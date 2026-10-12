//! Terminal raw mode, with host-side tracking of whether the host enabled it.
//!
//! The host only reverts a mode it enabled itself. `restore` is the cleanup
//! entry point for every path on which the app stops running. While raw mode
//! is enabled, `sys` also restores the terminal when the process is asked to
//! terminate from the outside.

use std::io;
use std::sync::{Mutex, TryLockError};

/// Whether the host currently holds the terminal in raw mode.
struct RawMode {
    enabled: bool,
}

impl RawMode {
    const fn new() -> Self {
        Self { enabled: false }
    }

    /// Idempotent: a second enable must not overwrite the mode saved by the first.
    fn enable(&mut self, enable: impl FnOnce() -> io::Result<()>) -> io::Result<()> {
        if !self.enabled {
            enable()?;
            self.enabled = true;
        }
        Ok(())
    }

    /// Stays enabled when the terminal rejects the change, so cleanup retries.
    fn disable(&mut self, disable: impl FnOnce() -> io::Result<()>) -> io::Result<()> {
        if self.enabled {
            disable()?;
            self.enabled = false;
        }
        Ok(())
    }
}

static RAW_MODE: Mutex<RawMode> = Mutex::new(RawMode::new());

pub(crate) fn enable_raw_mode() -> io::Result<()> {
    RAW_MODE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .enable(sys::enable)
}

pub(crate) fn disable_raw_mode() -> io::Result<()> {
    RAW_MODE
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .disable(sys::disable)
}

/// Best-effort cleanup for when the app stops running. There is nobody left to
/// report a failure to, and this must not block a process that is going down.
pub(crate) fn restore() {
    let mut raw_mode = match RAW_MODE.try_lock() {
        Ok(raw_mode) => raw_mode,
        Err(TryLockError::Poisoned(poisoned)) => poisoned.into_inner(),
        Err(TryLockError::WouldBlock) => return,
    };
    let _ = raw_mode.disable(sys::disable);
}

#[cfg(unix)]
mod sys {
    use std::cell::UnsafeCell;
    use std::io;
    use std::mem::MaybeUninit;
    use std::sync::atomic::{AtomicI32, Ordering};

    const NO_TERMINAL: i32 = -1;

    /// Signals that terminate the process by default and can be caught.
    const TERMINATION_SIGNALS: [libc::c_int; 4] =
        [libc::SIGHUP, libc::SIGINT, libc::SIGQUIT, libc::SIGTERM];

    /// The mode to put back. Shared with the signal handler, which cannot take a
    /// lock, so it is published by storing `TERMINAL` after this is written.
    struct SavedMode(UnsafeCell<MaybeUninit<libc::termios>>);

    // Written only under the `RAW_MODE` lock while `TERMINAL` is `NO_TERMINAL`.
    unsafe impl Sync for SavedMode {}

    static SAVED_MODE: SavedMode = SavedMode(UnsafeCell::new(MaybeUninit::uninit()));
    static TERMINAL: AtomicI32 = AtomicI32::new(NO_TERMINAL);

    pub(super) fn enable() -> io::Result<()> {
        let terminal = open_terminal()?;
        let result = enter_raw_mode(terminal);
        if result.is_err() {
            close_terminal(terminal);
        }
        result
    }

    pub(super) fn disable() -> io::Result<()> {
        let terminal = TERMINAL.load(Ordering::SeqCst);
        set_mode(terminal, SAVED_MODE.0.get().cast())?;
        remove_signal_handlers();
        TERMINAL.store(NO_TERMINAL, Ordering::SeqCst);
        close_terminal(terminal);
        Ok(())
    }

    fn enter_raw_mode(terminal: libc::c_int) -> io::Result<()> {
        let mut mode = MaybeUninit::<libc::termios>::uninit();
        if unsafe { libc::tcgetattr(terminal, mode.as_mut_ptr()) } != 0 {
            return Err(io::Error::last_os_error());
        }
        let saved = unsafe { mode.assume_init() };

        let mut raw = saved;
        unsafe { libc::cfmakeraw(&mut raw) };

        // Be ready to restore before there is anything to restore, so a signal
        // can never find the terminal in raw mode without a handler in place.
        unsafe { SAVED_MODE.0.get().write(MaybeUninit::new(saved)) };
        TERMINAL.store(terminal, Ordering::SeqCst);
        install_signal_handlers();

        let result = set_mode(terminal, &raw);
        if result.is_err() {
            remove_signal_handlers();
            TERMINAL.store(NO_TERMINAL, Ordering::SeqCst);
        }
        result
    }

    /// Standard input when it is a terminal, and otherwise the controlling
    /// terminal, so raw mode still works when input is redirected.
    fn open_terminal() -> io::Result<libc::c_int> {
        if unsafe { libc::isatty(libc::STDIN_FILENO) } == 1 {
            return Ok(libc::STDIN_FILENO);
        }
        let terminal = unsafe { libc::open(c"/dev/tty".as_ptr(), libc::O_RDWR | libc::O_CLOEXEC) };
        if terminal < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(terminal)
    }

    fn close_terminal(terminal: libc::c_int) {
        if terminal != libc::STDIN_FILENO {
            unsafe { libc::close(terminal) };
        }
    }

    fn set_mode(terminal: libc::c_int, mode: *const libc::termios) -> io::Result<()> {
        loop {
            if unsafe { libc::tcsetattr(terminal, libc::TCSANOW, mode) } == 0 {
                return Ok(());
            }
            let error = io::Error::last_os_error();
            if error.kind() != io::ErrorKind::Interrupted {
                return Err(error);
            }
        }
    }

    /// Only async-signal-safe calls are allowed here.
    extern "C" fn restore_and_terminate(signal: libc::c_int) {
        let terminal = TERMINAL.load(Ordering::SeqCst);
        unsafe {
            if terminal != NO_TERMINAL {
                libc::tcsetattr(terminal, libc::TCSANOW, SAVED_MODE.0.get().cast());
            }
            // Die from the signal itself, so the parent sees the usual status.
            libc::signal(signal, libc::SIG_DFL);
            libc::raise(signal);
        }
    }

    fn handler_address() -> libc::sighandler_t {
        restore_and_terminate as extern "C" fn(libc::c_int) as libc::sighandler_t
    }

    fn current_handler(signal: libc::c_int) -> Option<libc::sighandler_t> {
        let mut action = MaybeUninit::<libc::sigaction>::zeroed();
        if unsafe { libc::sigaction(signal, std::ptr::null(), action.as_mut_ptr()) } != 0 {
            return None;
        }
        Some(unsafe { action.assume_init() }.sa_sigaction)
    }

    /// Leaves alone any signal that is ignored or already handled: an ignored
    /// signal (as under `nohup`) must not start terminating the process.
    fn install_signal_handlers() {
        for signal in TERMINATION_SIGNALS {
            if current_handler(signal) == Some(libc::SIG_DFL) {
                unsafe {
                    let mut action = MaybeUninit::<libc::sigaction>::zeroed().assume_init();
                    action.sa_sigaction = handler_address();
                    libc::sigemptyset(&mut action.sa_mask);
                    libc::sigaction(signal, &action, std::ptr::null_mut());
                }
            }
        }
    }

    fn remove_signal_handlers() {
        for signal in TERMINATION_SIGNALS {
            if current_handler(signal) == Some(handler_address()) {
                unsafe { libc::signal(signal, libc::SIG_DFL) };
            }
        }
    }
}

#[cfg(windows)]
mod sys {
    use std::io;
    use std::ptr;
    use std::sync::atomic::{AtomicPtr, AtomicU32, Ordering};

    use windows_sys::Win32::Foundation::{
        CloseHandle, BOOL, FALSE, GENERIC_READ, GENERIC_WRITE, HANDLE, INVALID_HANDLE_VALUE, TRUE,
    };
    use windows_sys::Win32::Storage::FileSystem::{
        CreateFileW, FILE_SHARE_READ, FILE_SHARE_WRITE, OPEN_EXISTING,
    };
    use windows_sys::Win32::System::Console::{
        GetConsoleMode, SetConsoleCtrlHandler, SetConsoleMode, ENABLE_ECHO_INPUT,
        ENABLE_LINE_INPUT, ENABLE_PROCESSED_INPUT,
    };

    /// The console input features that raw mode turns off.
    const COOKED_INPUT: u32 = ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT;

    /// Shared with the console control handler, which runs on its own thread.
    /// `SAVED_MODE` is published by storing `CONSOLE` after it is written.
    static SAVED_MODE: AtomicU32 = AtomicU32::new(0);
    static CONSOLE: AtomicPtr<core::ffi::c_void> = AtomicPtr::new(ptr::null_mut());

    pub(super) fn enable() -> io::Result<()> {
        let console = open_console()?;
        let result = enter_raw_mode(console);
        if result.is_err() {
            unsafe { CloseHandle(console) };
        }
        result
    }

    pub(super) fn disable() -> io::Result<()> {
        let console = CONSOLE.load(Ordering::SeqCst);
        set_mode(console, SAVED_MODE.load(Ordering::SeqCst))?;
        unsafe { SetConsoleCtrlHandler(Some(restore_on_console_event), FALSE) };
        CONSOLE.store(ptr::null_mut(), Ordering::SeqCst);
        unsafe { CloseHandle(console) };
        Ok(())
    }

    fn enter_raw_mode(console: HANDLE) -> io::Result<()> {
        let mut saved = 0;
        if unsafe { GetConsoleMode(console, &mut saved) } == 0 {
            return Err(io::Error::last_os_error());
        }

        // Be ready to restore before there is anything to restore, so a console
        // event can never find raw mode enabled without a handler in place.
        SAVED_MODE.store(saved, Ordering::SeqCst);
        CONSOLE.store(console, Ordering::SeqCst);
        unsafe { SetConsoleCtrlHandler(Some(restore_on_console_event), TRUE) };

        let result = set_mode(console, saved & !COOKED_INPUT);
        if result.is_err() {
            unsafe { SetConsoleCtrlHandler(Some(restore_on_console_event), FALSE) };
            CONSOLE.store(ptr::null_mut(), Ordering::SeqCst);
        }
        result
    }

    /// The console's input buffer, which is reachable even when standard input
    /// is redirected.
    fn open_console() -> io::Result<HANDLE> {
        let name: Vec<u16> = "CONIN$\0".encode_utf16().collect();
        let console = unsafe {
            CreateFileW(
                name.as_ptr(),
                GENERIC_READ | GENERIC_WRITE,
                FILE_SHARE_READ | FILE_SHARE_WRITE,
                ptr::null(),
                OPEN_EXISTING,
                0,
                ptr::null_mut(),
            )
        };
        if console == INVALID_HANDLE_VALUE {
            return Err(io::Error::last_os_error());
        }
        Ok(console)
    }

    fn set_mode(console: HANDLE, mode: u32) -> io::Result<()> {
        if unsafe { SetConsoleMode(console, mode) } == 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }

    /// Runs for Ctrl+C, Ctrl+Break, and the console closing. Returning `FALSE`
    /// passes the event on, so the process still terminates as it would have.
    unsafe extern "system" fn restore_on_console_event(_event: u32) -> BOOL {
        let console = CONSOLE.load(Ordering::SeqCst);
        if !console.is_null() {
            unsafe { SetConsoleMode(console, SAVED_MODE.load(Ordering::SeqCst)) };
        }
        FALSE
    }
}

#[cfg(not(any(unix, windows)))]
mod sys {
    use std::io;

    pub(super) fn enable() -> io::Result<()> {
        Err(io::Error::from(io::ErrorKind::Unsupported))
    }

    pub(super) fn disable() -> io::Result<()> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    fn rejected() -> io::Result<()> {
        Err(io::Error::from(io::ErrorKind::PermissionDenied))
    }

    #[test]
    fn repeated_enables_change_the_terminal_once() {
        let calls = Cell::new(0);
        let count = || {
            calls.set(calls.get() + 1);
            Ok(())
        };
        let mut raw_mode = RawMode::new();

        raw_mode.enable(count).unwrap();
        raw_mode.enable(count).unwrap();

        assert_eq!(calls.get(), 1);
    }

    #[test]
    fn disable_leaves_a_mode_the_host_did_not_enable() {
        let mut raw_mode = RawMode::new();

        raw_mode
            .disable(|| panic!("reverted a mode the host never enabled"))
            .unwrap();
    }

    #[test]
    fn one_disable_reverts_any_number_of_enables() {
        let calls = Cell::new(0);
        let count = || {
            calls.set(calls.get() + 1);
            Ok(())
        };
        let mut raw_mode = RawMode::new();
        raw_mode.enable(|| Ok(())).unwrap();
        raw_mode.enable(|| Ok(())).unwrap();

        raw_mode.disable(count).unwrap();
        raw_mode.disable(count).unwrap();

        assert_eq!(calls.get(), 1);
    }

    #[test]
    fn rejected_enable_leaves_nothing_to_revert() {
        let mut raw_mode = RawMode::new();

        assert!(raw_mode.enable(rejected).is_err());

        raw_mode
            .disable(|| panic!("reverted a mode that was never enabled"))
            .unwrap();
    }

    #[test]
    fn rejected_disable_is_retried() {
        let mut raw_mode = RawMode::new();
        raw_mode.enable(|| Ok(())).unwrap();

        assert!(raw_mode.disable(rejected).is_err());

        let retried = Cell::new(false);
        raw_mode
            .disable(|| {
                retried.set(true);
                Ok(())
            })
            .unwrap();
        assert!(retried.get());
    }
}
