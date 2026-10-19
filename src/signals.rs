//! Process-wide cooperative cancellation. Native handlers only publish bits
//! and wake a normal thread; allocation, locks and notifications happen there.
use std::io;
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::{Condvar, Mutex, OnceLock};
use std::time::{Duration, Instant};

pub(crate) const INTERRUPT: u8 = 1;
pub(crate) const TERMINATE: u8 = 2;
static PENDING: AtomicU8 = AtomicU8::new(0);
static CAUGHT: AtomicU8 = AtomicU8::new(0);
static BROKER: OnceLock<Broker> = OnceLock::new();
static SETUP: Mutex<()> = Mutex::new(());

struct Broker {
    epoch: Mutex<u64>,
    changed: Condvar,
    async_changed: tokio::sync::Notify,
}

fn notify() {
    if let Some(broker) = BROKER.get() {
        let mut epoch = broker.epoch.lock().unwrap_or_else(|e| e.into_inner());
        *epoch = epoch.wrapping_add(1);
        broker.changed.notify_all();
        broker.async_changed.notify_waiters();
    }
}

#[cfg(test)]
thread_local! { static TEST_PENDING: std::cell::Cell<bool> = const { std::cell::Cell::new(false) }; }

#[cfg(test)]
pub(crate) fn set_test_pending(value: bool) {
    TEST_PENDING.set(value);
}

pub(crate) fn is_pending() -> bool {
    #[cfg(test)]
    if TEST_PENDING.get() {
        return true;
    }
    PENDING.load(Ordering::Acquire) != 0
}

pub(crate) fn poll() -> u8 {
    PENDING.swap(0, Ordering::AcqRel)
}

pub(crate) fn catch(requested: u8) -> io::Result<()> {
    if requested == 0 {
        return Ok(());
    }
    let _setup = SETUP.lock().unwrap_or_else(|e| e.into_inner());
    if BROKER.get().is_none() {
        BROKER
            .set(Broker {
                epoch: Mutex::new(0),
                changed: Condvar::new(),
                async_changed: tokio::sync::Notify::new(),
            })
            .ok();
    }
    sys::initialize()?;
    let old = CAUGHT.load(Ordering::Acquire);
    let additional = requested & !old;
    if additional != 0 {
        // Publish before enabling delivery: a Windows Ctrl-C may arrive as
        // soon as SetConsoleCtrlHandler re-enables it.
        CAUGHT.store(old | additional, Ordering::Release);
        if let Err(error) = sys::install(additional) {
            CAUGHT.store(old, Ordering::Release);
            return Err(error);
        }
    }
    Ok(())
}

/// True when the duration elapsed; false when an unacknowledged event wins.
/// No lock is held by the calling operation while waiting here.
pub(crate) fn wait_for(duration: Duration) -> bool {
    if is_pending() {
        return false;
    }
    let Some(broker) = BROKER.get() else {
        std::thread::sleep(duration);
        return !is_pending();
    };
    let started = Instant::now();
    let mut epoch = broker.epoch.lock().unwrap_or_else(|e| e.into_inner());
    loop {
        if is_pending() {
            return false;
        }
        let Some(left) = duration.checked_sub(started.elapsed()) else {
            return true;
        };
        if left.is_zero() {
            return true;
        }
        let result = broker.changed.wait_timeout(epoch, left);
        epoch = result.unwrap_or_else(|e| e.into_inner()).0;
    }
}

pub(crate) async fn cancelled() {
    let Some(broker) = BROKER.get() else {
        return std::future::pending().await;
    };
    loop {
        let notified = broker.async_changed.notified();
        tokio::pin!(notified);
        notified.as_mut().enable();
        if is_pending() {
            return;
        }
        notified.await;
    }
}

#[cfg(windows)]
pub(crate) fn dispatch_console_event(event: u32) -> bool {
    sys::dispatch(event)
}

#[cfg(unix)]
mod sys {
    use super::*;
    use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
    use std::sync::atomic::{AtomicI32, Ordering};

    static WRITE_FD: AtomicI32 = AtomicI32::new(-1);
    static PIPE: OnceLock<OwnedFd> = OnceLock::new();

    pub(super) fn initialize() -> io::Result<()> {
        if PIPE.get().is_some() {
            return Ok(());
        }
        let mut fds = [-1; 2];
        if unsafe { libc::pipe(fds.as_mut_ptr()) } != 0 {
            return Err(io::Error::last_os_error());
        }
        let read = unsafe { OwnedFd::from_raw_fd(fds[0]) };
        let write = unsafe { OwnedFd::from_raw_fd(fds[1]) };
        for fd in [read.as_raw_fd(), write.as_raw_fd()] {
            if unsafe { libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC) } == -1 {
                return Err(io::Error::last_os_error());
            }
        }
        if unsafe { libc::fcntl(write.as_raw_fd(), libc::F_SETFL, libc::O_NONBLOCK) } == -1 {
            return Err(io::Error::last_os_error());
        }
        std::thread::Builder::new()
            .name("roc-signal-broker".into())
            .spawn(move || {
                let mut bytes = [0u8; 64];
                loop {
                    let count = unsafe {
                        libc::read(read.as_raw_fd(), bytes.as_mut_ptr().cast(), bytes.len())
                    };
                    if count > 0 {
                        notify();
                    } else if count == 0
                        || io::Error::last_os_error().kind() != io::ErrorKind::Interrupted
                    {
                        break;
                    }
                }
            })?;
        WRITE_FD.store(write.as_raw_fd(), Ordering::Release);
        let _ = PIPE.set(write);
        Ok(())
    }

    #[cfg(target_os = "macos")]
    unsafe fn errno() -> *mut libc::c_int {
        unsafe { libc::__error() }
    }
    #[cfg(not(target_os = "macos"))]
    unsafe fn errno() -> *mut libc::c_int {
        unsafe { libc::__errno_location() }
    }

    extern "C" fn handler(signal: libc::c_int) {
        unsafe {
            let saved = *errno();
            PENDING.fetch_or(
                if signal == libc::SIGINT {
                    INTERRUPT
                } else {
                    TERMINATE
                },
                Ordering::Release,
            );
            let fd = WRITE_FD.load(Ordering::Acquire);
            if fd >= 0 {
                let byte = 1u8;
                libc::write(fd, (&byte as *const u8).cast(), 1);
            }
            *errno() = saved;
        }
    }

    pub(super) fn install(additional: u8) -> io::Result<()> {
        let mut installed = Vec::new();
        for (bit, signal) in [(INTERRUPT, libc::SIGINT), (TERMINATE, libc::SIGTERM)] {
            if additional & bit == 0 {
                continue;
            }
            let mut action = unsafe { std::mem::zeroed::<libc::sigaction>() };
            action.sa_sigaction = handler as extern "C" fn(libc::c_int) as libc::sighandler_t;
            unsafe { libc::sigemptyset(&mut action.sa_mask) };
            let mut old = unsafe { std::mem::zeroed::<libc::sigaction>() };
            if unsafe { libc::sigaction(signal, &action, &mut old) } != 0 {
                let error = io::Error::last_os_error();
                for (signal, old) in installed {
                    unsafe { libc::sigaction(signal, &old, std::ptr::null_mut()) };
                }
                return Err(error);
            }
            installed.push((signal, old));
        }
        Ok(())
    }
}

#[cfg(windows)]
mod sys {
    use super::*;
    use std::sync::atomic::{AtomicPtr, Ordering};
    use windows_sys::Win32::Foundation::{FALSE, TRUE};
    use windows_sys::Win32::System::Console::{SetConsoleCtrlHandler, CTRL_C_EVENT};
    use windows_sys::Win32::System::Threading::{
        CreateEventW, SetEvent, WaitForSingleObject, INFINITE,
    };

    static EVENT: AtomicPtr<core::ffi::c_void> = AtomicPtr::new(std::ptr::null_mut());

    pub(super) fn initialize() -> io::Result<()> {
        if !EVENT.load(Ordering::Acquire).is_null() {
            return Ok(());
        }
        let event = unsafe { CreateEventW(std::ptr::null(), FALSE, FALSE, std::ptr::null()) };
        if event.is_null() {
            return Err(io::Error::last_os_error());
        }
        let address = event as usize;
        if let Err(error) = std::thread::Builder::new()
            .name("roc-signal-broker".into())
            .spawn(move || loop {
                if unsafe { WaitForSingleObject(address as _, INFINITE) } != 0 {
                    break;
                }
                notify();
            })
        {
            unsafe { windows_sys::Win32::Foundation::CloseHandle(event) };
            return Err(error);
        }
        EVENT.store(event, Ordering::Release);
        Ok(())
    }

    pub(super) fn dispatch(event: u32) -> bool {
        if event != CTRL_C_EVENT || CAUGHT.load(Ordering::Acquire) & INTERRUPT == 0 {
            return false;
        }
        PENDING.fetch_or(INTERRUPT, Ordering::Release);
        let wake = EVENT.load(Ordering::Acquire);
        if !wake.is_null() {
            unsafe { SetEvent(wake) };
        }
        true
    }

    unsafe extern "system" fn handler(event: u32) -> i32 {
        if dispatch(event) {
            TRUE
        } else {
            FALSE
        }
    }

    pub(super) fn install(additional: u8) -> io::Result<()> {
        if additional & TERMINATE != 0 {
            return Err(io::ErrorKind::Unsupported.into());
        }
        if unsafe { SetConsoleCtrlHandler(Some(handler), TRUE) } == 0 {
            return Err(io::Error::last_os_error());
        }
        if unsafe { SetConsoleCtrlHandler(None, FALSE) } == 0 {
            let error = io::Error::last_os_error();
            unsafe { SetConsoleCtrlHandler(Some(handler), FALSE) };
            return Err(error);
        }
        Ok(())
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;

    #[test]
    fn caught_events_wake_waits_and_remain_pending_until_acknowledged() {
        const CHILD: &str = "BASIC_CLI_SIGNAL_TEST_CHILD";
        if std::env::var_os(CHILD).is_none() {
            let status = std::process::Command::new(std::env::current_exe().unwrap())
                .args(["--exact", "signals::tests::caught_events_wake_waits_and_remain_pending_until_acknowledged", "--nocapture"])
                .env(CHILD, "1")
                .status()
                .unwrap();
            assert!(status.success());
            return;
        }
        catch(INTERRUPT | TERMINATE).unwrap();
        let sender = std::thread::spawn(|| {
            std::thread::sleep(Duration::from_millis(30));
            unsafe {
                libc::raise(libc::SIGINT);
            }
        });
        let started = Instant::now();
        assert!(!wait_for(Duration::from_secs(20)));
        sender.join().unwrap();
        assert!(started.elapsed() < Duration::from_secs(2));
        unsafe {
            libc::raise(libc::SIGINT);
            libc::raise(libc::SIGTERM);
        }
        assert!(!wait_for(Duration::ZERO));
        assert_eq!(poll(), INTERRUPT | TERMINATE);
        assert_eq!(poll(), 0);
        assert!(wait_for(Duration::ZERO));
        catch(0).unwrap();
        unsafe {
            libc::raise(libc::SIGTERM);
        }
        assert_eq!(poll(), TERMINATE);
    }
}
