use super::{Stream, CHUNK};
use std::io;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

static PREVIOUS_WAKE_ACTION: Mutex<Option<libc::sigaction>> = Mutex::new(None);

extern "C" fn wake(_: libc::c_int) {}

pub fn prepare() -> io::Result<()> {
    let mut saved = PREVIOUS_WAKE_ACTION.lock().unwrap();
    unsafe {
        let mut previous: libc::sigaction = std::mem::zeroed();
        if libc::sigaction(libc::SIGUSR2, std::ptr::null(), &mut previous) != 0 {
            return Err(io::Error::last_os_error());
        }
        if previous.sa_sigaction != libc::SIG_DFL && previous.sa_sigaction != libc::SIG_IGN {
            return Err(io::Error::new(
                io::ErrorKind::AlreadyExists,
                "SIGUSR2 is reserved for native I/O cancellation",
            ));
        }
        let mut action: libc::sigaction = std::mem::zeroed();
        action.sa_sigaction = wake as extern "C" fn(libc::c_int) as libc::sighandler_t;
        libc::sigemptyset(&mut action.sa_mask);
        if libc::sigaction(libc::SIGUSR2, &action, std::ptr::null_mut()) != 0 {
            return Err(io::Error::last_os_error());
        }
        // Ignored dispositions survive exec, including those inherited from a
        // shell or supervisor. They must not disable ordinary standard I/O.
        *saved = Some(previous);
    }
    Ok(())
}

pub fn rollback() {
    let Some(previous) = PREVIOUS_WAKE_ACTION.lock().unwrap().take() else {
        return;
    };
    unsafe {
        let mut action: libc::sigaction = std::mem::zeroed();
        if libc::sigaction(libc::SIGUSR2, std::ptr::null(), &mut action) == 0
            && action.sa_sigaction == wake as extern "C" fn(libc::c_int) as libc::sighandler_t
        {
            libc::sigaction(libc::SIGUSR2, &previous, std::ptr::null_mut());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::process::CommandExt;
    use std::process::Command;

    #[test]
    fn inherited_ignored_wake_signal_allows_stdio_and_is_restored_on_rollback() {
        const CHILD: &str = "BASIC_CLI_INHERITED_IGNORED_WAKE_TEST";
        if std::env::var_os(CHILD).is_none() {
            let mut command = Command::new(std::env::current_exe().unwrap());
            let test = format!(
                "{}::inherited_ignored_wake_signal_allows_stdio_and_is_restored_on_rollback",
                module_path!().split_once("::").unwrap().1,
            );
            command
                .args(["--exact", &test, "--nocapture"])
                .env(CHILD, "1");
            unsafe {
                command.pre_exec(|| {
                    if libc::signal(libc::SIGUSR2, libc::SIG_IGN) == libc::SIG_ERR {
                        Err(io::Error::last_os_error())
                    } else {
                        Ok(())
                    }
                });
            }
            let output = command.output().unwrap();
            assert!(
                output.status.success(),
                "{}",
                String::from_utf8_lossy(&output.stderr)
            );
            assert!(output
                .stdout
                .windows(b"inherited ignore works\n".len())
                .any(|part| part == b"inherited ignore works\n"));
            return;
        }
        prepare().unwrap();
        rollback();
        let mut action: libc::sigaction = unsafe { std::mem::zeroed() };
        assert_eq!(
            unsafe { libc::sigaction(libc::SIGUSR2, std::ptr::null(), &mut action) },
            0
        );
        assert_eq!(action.sa_sigaction, libc::SIG_IGN);
        crate::native_stdio::write(Stream::Stdout, b"inherited ignore works\n").unwrap();
    }
}

pub fn thread() -> io::Result<usize> {
    unsafe {
        let mut wake: libc::sigset_t = std::mem::zeroed();
        libc::sigemptyset(&mut wake);
        libc::sigaddset(&mut wake, libc::SIGUSR2);
        let error = libc::pthread_sigmask(libc::SIG_UNBLOCK, &wake, std::ptr::null_mut());
        if error != 0 {
            return Err(io::Error::from_raw_os_error(error));
        }
        Ok(libc::pthread_self() as usize)
    }
}
pub fn cancel(thread: usize) {
    unsafe {
        libc::pthread_kill(thread as libc::pthread_t, libc::SIGUSR2);
    }
}

fn fd(stream: Stream) -> libc::c_int {
    match stream {
        Stream::Stdout => libc::STDOUT_FILENO,
        Stream::Stderr => libc::STDERR_FILENO,
    }
}

fn ready(fd: libc::c_int, events: libc::c_short) -> io::Result<()> {
    let mut poll = libc::pollfd {
        fd,
        events,
        revents: 0,
    };
    if unsafe { libc::poll(&mut poll, 1, -1) } < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

#[derive(Default)]
pub struct Input;
impl Input {
    pub fn read(&mut self, bytes: &mut [u8], cancelled: &AtomicBool) -> io::Result<usize> {
        if cancelled.load(Ordering::Acquire) {
            return Err(io::ErrorKind::Interrupted.into());
        }
        let result =
            unsafe { libc::read(libc::STDIN_FILENO, bytes.as_mut_ptr().cast(), bytes.len()) };
        if result >= 0 {
            return Ok(result as usize);
        }
        let error = io::Error::last_os_error();
        match error.raw_os_error() {
            Some(libc::EBADF) => Ok(0),
            Some(libc::EAGAIN) => {
                ready(libc::STDIN_FILENO, libc::POLLIN)?;
                Err(io::ErrorKind::Interrupted.into())
            }
            _ => Err(error),
        }
    }
}

#[derive(Default)]
pub struct Output {}
impl Output {
    pub fn cancel(&mut self) {}
    pub fn write(
        &mut self,
        stream: Stream,
        bytes: &[u8],
        cancelled: &AtomicBool,
    ) -> io::Result<usize> {
        if cancelled.load(Ordering::Acquire) {
            return Err(io::ErrorKind::Interrupted.into());
        }
        let result =
            unsafe { libc::write(fd(stream), bytes.as_ptr().cast(), bytes.len().min(CHUNK)) };
        if result >= 0 {
            return Ok(result as usize);
        }
        let error = io::Error::last_os_error();
        match error.raw_os_error() {
            Some(libc::EBADF) => Ok(bytes.len()),
            Some(libc::EAGAIN) => {
                ready(fd(stream), libc::POLLOUT)?;
                Err(io::ErrorKind::Interrupted.into())
            }
            _ => Err(error),
        }
    }
}
