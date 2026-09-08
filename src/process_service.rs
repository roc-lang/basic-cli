//! Rust-owned process supervision. No Roc allocations cross the service boundary.
use process_wrap::tokio::*;
use std::{
    collections::VecDeque,
    io,
    process::Stdio,
    sync::{Arc, Condvar, Mutex, OnceLock, Weak},
    time::{Duration, Instant},
};
use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWriteExt},
    sync::{Mutex as AsyncMutex, Notify},
};

#[derive(Clone, Debug, Default)]
pub struct Output {
    pub exit_code: i32,
    pub signal: i32,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub failure: u8,
}
#[derive(Clone, Debug)]
pub struct Event {
    pub stream: u8,
    pub bytes: Vec<u8>,
}
pub struct Config {
    pub command: std::process::Command,
    pub stdin_mode: u8,
    pub stdout_mode: u8,
    pub stderr_mode: u8,
    pub input: Vec<u8>,
    pub timeout_ms: u64,
    pub output_limit: usize,
    pub pending_limit: usize,
    pub manage_tree: bool,
    pub merge_stderr: bool,
}
struct State {
    output: Output,
    events: VecDeque<Event>,
    pending: usize,
    done: bool,
    error: Option<(io::ErrorKind, String)>,
}
struct Shared {
    state: Mutex<State>,
    changed: Condvar,
    cancel: Notify,
}
pub struct Child {
    pid: u32,
    shared: Arc<Shared>,
    stdin: Arc<AsyncMutex<Option<tokio::process::ChildStdin>>>,
    closed: Mutex<bool>,
}
fn registry() -> &'static Mutex<Vec<Weak<Shared>>> {
    static REGISTRY: OnceLock<Mutex<Vec<Weak<Shared>>>> = OnceLock::new();
    REGISTRY.get_or_init(|| Mutex::new(Vec::new()))
}
/// Terminate and reap children before the host exits normally.
pub fn shutdown() {
    let children: Vec<_> = registry()
        .lock()
        .unwrap()
        .iter()
        .filter_map(Weak::upgrade)
        .collect();
    for child in &children {
        child.cancel.notify_one();
    }
    for child in children {
        let mut state = child.state.lock().unwrap();
        while !state.done {
            state = child.changed.wait(state).unwrap();
        }
    }
}
fn service() -> &'static tokio::runtime::Handle {
    static HANDLE: OnceLock<tokio::runtime::Handle> = OnceLock::new();
    HANDLE.get_or_init(|| {
        let (tx, rx) = std::sync::mpsc::sync_channel(1);
        std::thread::Builder::new()
            .name("roc-process-service".into())
            .spawn(move || {
                let runtime = tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .build()
                    .expect("process runtime");
                tx.send(runtime.handle().clone()).unwrap();
                runtime.block_on(std::future::pending::<()>());
            })
            .expect("process service thread");
        rx.recv().unwrap()
    })
}
fn sync_task<T: Send + 'static>(
    future: impl std::future::Future<Output = T> + Send + 'static,
) -> T {
    let (tx, rx) = std::sync::mpsc::sync_channel(1);
    service().spawn(async move {
        let value = future.await;
        let _ = tx.send(value);
    });
    rx.recv().expect("process task stopped")
}
fn forwarding_slots() -> Arc<tokio::sync::Semaphore> {
    static SLOTS: OnceLock<Arc<tokio::sync::Semaphore>> = OnceLock::new();
    SLOTS
        .get_or_init(|| Arc::new(tokio::sync::Semaphore::new(2)))
        .clone()
}
// A cancelled async waiter does not interrupt an OS write. Keep the permit in
// the actual blocking closure to bound stranded forwarding work across commands.
async fn forward_blocking(
    write: impl FnOnce() -> io::Result<()> + Send + 'static,
) -> io::Result<()> {
    let permit = forwarding_slots()
        .acquire_owned()
        .await
        .map_err(io::Error::other)?;
    tokio::task::spawn_blocking(move || {
        let _permit = permit;
        write()
    })
    .await
    .map_err(io::Error::other)?
}
fn output_stdio(mode: u8) -> Stdio {
    match mode {
        2 => Stdio::null(),
        3..=5 => Stdio::piped(),
        _ => Stdio::inherit(),
    }
}
fn closed_error() -> io::Error {
    io::Error::new(io::ErrorKind::BrokenPipe, "Child is closed")
}
impl Child {
    pub fn spawn(config: Config) -> io::Result<Self> {
        sync_task(async move { spawn(config).await })
    }
    fn check_open(&self) -> io::Result<()> {
        if *self.closed.lock().unwrap() {
            Err(closed_error())
        } else {
            Ok(())
        }
    }
    pub fn pid(&self) -> io::Result<u32> {
        self.check_open()?;
        Ok(self.pid)
    }
    pub fn wait(&self) -> io::Result<Output> {
        self.close_stdin()?;
        let mut state = self.shared.state.lock().unwrap();
        while !state.done {
            state = self.shared.changed.wait(state).unwrap();
        }
        result(&state)
    }
    pub fn try_wait(&self) -> io::Result<Option<Output>> {
        self.check_open()?;
        let state = self.shared.state.lock().unwrap();
        if state.done {
            result(&state).map(Some)
        } else {
            Ok(None)
        }
    }
    pub fn kill(&self) -> io::Result<()> {
        self.check_open()?;
        self.shared.cancel.notify_one();
        Ok(())
    }
    pub fn close(&self) -> io::Result<()> {
        let mut closed = self.closed.lock().unwrap();
        if *closed {
            return Ok(());
        }
        self.shared.cancel.notify_one();
        let mut state = self.shared.state.lock().unwrap();
        while !state.done {
            state = self.shared.changed.wait(state).unwrap();
        }
        *closed = true;
        result(&state).map(|_| ())
    }
    pub fn close_stdin(&self) -> io::Result<()> {
        self.check_open()?;
        let stdin = self.stdin.clone();
        sync_task(async move {
            stdin.lock().await.take();
        });
        Ok(())
    }
    pub fn write(&self, bytes: Vec<u8>, timeout_ms: u64) -> io::Result<()> {
        self.check_open()?;
        let stdin = self.stdin.clone();
        sync_task(async move {
            let deadline = tokio::time::Instant::now()
                .checked_add(Duration::from_millis(timeout_ms))
                .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Timeout is too large"))?;
            tokio::time::timeout_at(deadline, async {
                let mut input = stdin.lock().await;
                input
                    .as_mut()
                    .ok_or_else(closed_error)?
                    .write_all(&bytes)
                    .await
            })
            .await
            .map_err(|_| io::Error::new(io::ErrorKind::TimedOut, "Child stdin write timed out"))?
        })
    }
    pub fn read(&self, max_bytes: usize, timeout_ms: u64) -> io::Result<Event> {
        self.check_open()?;
        if max_bytes == 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "Read size must be positive",
            ));
        }
        let deadline = Instant::now()
            .checked_add(Duration::from_millis(timeout_ms))
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Timeout is too large"))?;
        let mut state = self.shared.state.lock().unwrap();
        loop {
            if let Some(mut event) = state.events.pop_front() {
                if event.bytes.len() > max_bytes {
                    let rest = event.bytes.split_off(max_bytes);
                    state.events.push_front(Event {
                        stream: event.stream,
                        bytes: rest,
                    });
                }
                state.pending -= event.bytes.len();
                return Ok(event);
            }
            if state.done {
                if let Some((kind, message)) = &state.error {
                    return Err(io::Error::new(*kind, message.clone()));
                }
                return Ok(Event {
                    stream: 0,
                    bytes: Vec::new(),
                });
            }
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(io::Error::new(
                    io::ErrorKind::TimedOut,
                    "Child output read timed out",
                ));
            }
            state = self
                .shared
                .changed
                .wait_timeout(state, remaining)
                .unwrap()
                .0;
        }
    }
}
impl Drop for Child {
    fn drop(&mut self) {
        self.shared.cancel.notify_one();
    }
}
fn result(state: &State) -> io::Result<Output> {
    if let Some((kind, message)) = &state.error {
        Err(io::Error::new(*kind, message.clone()))
    } else {
        Ok(state.output.clone())
    }
}
fn report_error(shared: &Shared, error: &io::Error) {
    shared.state.lock().unwrap().error = Some((error.kind(), error.to_string()));
    shared.cancel.notify_one();
    shared.changed.notify_all();
}
async fn observed_pump<R: AsyncRead + Unpin>(
    reader: R,
    shared: Arc<Shared>,
    stream: u8,
    mode: u8,
    output_limit: usize,
    pending_limit: usize,
) -> io::Result<()> {
    let result = pump(
        reader,
        shared.clone(),
        stream,
        mode,
        output_limit,
        pending_limit,
    )
    .await;
    if let Err(error) = &result {
        report_error(&shared, error);
    }
    result
}
async fn pump<R: AsyncRead + Unpin>(
    mut reader: R,
    shared: Arc<Shared>,
    stream: u8,
    mode: u8,
    output_limit: usize,
    pending_limit: usize,
) -> io::Result<()> {
    let mut buffer = [0u8; 8192];
    loop {
        let count = reader.read(&mut buffer).await?;
        if count == 0 {
            return Ok(());
        }
        {
            let mut state = shared.state.lock().unwrap();
            if mode == 4 {
                let keep = count.min(pending_limit.saturating_sub(state.pending));
                if keep != 0 {
                    state.events.push_back(Event {
                        stream,
                        bytes: buffer[..keep].to_vec(),
                    });
                    state.pending += keep;
                }
                if keep != count {
                    state.output.failure = 2;
                    shared.cancel.notify_one();
                }
            } else if mode == 3 || mode == 5 {
                let used = state.output.stdout.len() + state.output.stderr.len();
                let keep = count.min(output_limit.saturating_sub(used));
                if stream == 1 {
                    state.output.stdout.extend_from_slice(&buffer[..keep]);
                } else {
                    state.output.stderr.extend_from_slice(&buffer[..keep]);
                }
                if keep != count {
                    state.output.failure = 2;
                    shared.cancel.notify_one();
                }
            }
            shared.changed.notify_all();
        }
        if mode == 5 || mode == 1 || mode == 0 {
            // Blocking terminal writes run outside the service thread.
            let bytes = buffer[..count].to_vec();
            forward_blocking(move || {
                use std::io::Write;
                if stream == 1 {
                    std::io::stdout().write_all(&bytes)
                } else {
                    std::io::stderr().write_all(&bytes)
                }
            })
            .await?;
        }
    }
}
async fn spawn(mut config: Config) -> io::Result<Child> {
    let deadline = if config.timeout_ms == 0 {
        None
    } else {
        Some(tokio::time::Instant::now()
            .checked_add(Duration::from_millis(config.timeout_ms))
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Timeout is too large"))?)
    };
    config.command.stdin(match config.stdin_mode {
        2 => Stdio::null(),
        3 | 4 => Stdio::piped(),
        _ => Stdio::inherit(),
    });
    config.command.stdout(output_stdio(config.stdout_mode));
    config.command.stderr(output_stdio(config.stderr_mode));
    // Both descriptors share one kernel pipe, preserving their actual write ordering.
    let merged = if config.merge_stderr && config.stdout_mode != 2 {
        let (reader, writer) = std::io::pipe()?;
        config.command.stdout(Stdio::from(writer.try_clone()?));
        config.command.stderr(Stdio::from(writer));
        #[cfg(unix)]
        let reader = std::process::ChildStdout::from(std::os::fd::OwnedFd::from(reader));
        #[cfg(windows)]
        let reader =
            std::process::ChildStdout::from(std::os::windows::io::OwnedHandle::from(reader));
        Some(tokio::process::ChildStdout::from_std(reader)?)
    } else {
        if config.merge_stderr {
            config.command.stderr(Stdio::null());
        }
        None
    };
    let mut command = CommandWrap::from(tokio::process::Command::from(config.command));
    command.wrap(KillOnDrop);
    if config.manage_tree {
        #[cfg(unix)]
        command.wrap(ProcessGroup::leader());
        #[cfg(windows)]
        command.wrap(JobObject);
    }
    let mut child = command.spawn()?;
    let pid = child
        .id()
        .ok_or_else(|| io::Error::other("Child has no process ID"))?;
    let stdout = merged.or_else(|| child.stdout().take());
    let stderr = child.stderr().take();
    let mut input_pipe = child.stdin().take();
    let automatic_input = if config.stdin_mode == 3 {
        input_pipe.take()
    } else {
        None
    };
    let stdin = Arc::new(AsyncMutex::new(input_pipe));
    let shared = Arc::new(Shared {
        state: Mutex::new(State {
            output: Output::default(),
            events: VecDeque::new(),
            pending: 0,
            done: false,
            error: None,
        }),
        changed: Condvar::new(),
        cancel: Notify::new(),
    });
    {
        let mut registry = registry().lock().unwrap();
        registry.retain(|entry| entry.strong_count() > 0);
        registry.push(Arc::downgrade(&shared));
    }
    let handle = Child {
        pid,
        shared: shared.clone(),
        stdin: stdin.clone(),
        closed: Mutex::new(false),
    };
    tokio::spawn(async move {
        let mut readers = Vec::new();
        if let Some(pipe) = stdout {
            readers.push(tokio::spawn(observed_pump(
                pipe,
                shared.clone(),
                1,
                config.stdout_mode,
                config.output_limit,
                config.pending_limit,
            )));
        }
        if let Some(pipe) = stderr {
            readers.push(tokio::spawn(observed_pump(
                pipe,
                shared.clone(),
                if config.merge_stderr { 1 } else { 2 },
                if config.merge_stderr {
                    config.stdout_mode
                } else {
                    config.stderr_mode
                },
                config.output_limit,
                config.pending_limit,
            )));
        }
        let mut writer = if config.stdin_mode == 3 {
            let shared = shared.clone();
            Some(tokio::spawn(async move {
                let result = if let Some(mut input) = automatic_input {
                    input.write_all(&config.input).await
                } else {
                    Ok(())
                };
                if let Err(error) = &result {
                    report_error(&shared, error);
                }
                result
            }))
        } else {
            None
        };
        let completion = async {
            let status = child.wait().await?;
            for reader in &mut readers {
                reader.await.map_err(io::Error::other)??;
            }
            if let Some(writer) = writer.as_mut() {
                writer.await.map_err(io::Error::other)??;
            }
            Ok::<_, io::Error>(status)
        };
        let completed = tokio::select! {
            result = completion => Some(result),
            _ = shared.cancel.notified() => None,
            _ = async { if let Some(deadline)=deadline {tokio::time::sleep_until(deadline).await} else {std::future::pending::<()>().await} } => {shared.state.lock().unwrap().output.failure=1;None},
        };
        let status = match completed {
            Some(Ok(status)) => Ok(status),
            Some(Err(err)) => {
                let _ = child.start_kill();
                let _ = child.wait().await;
                Err(err)
            }
            None => {
                let _ = child.start_kill();
                child.wait().await
            }
        };
        for reader in readers {
            reader.abort();
        }
        if let Some(writer) = writer {
            writer.abort();
        }
        stdin.lock().await.take();
        let mut state = shared.state.lock().unwrap();
        match status {
            Ok(status) => {
                state.output.exit_code = status.code().unwrap_or(-1);
                #[cfg(unix)]
                {
                    use std::os::unix::process::ExitStatusExt;
                    state.output.signal = status.signal().unwrap_or(0);
                }
            }
            Err(err) => state.error = Some((err.kind(), err.to_string())),
        }
        state.done = true;
        shared.changed.notify_all();
    });
    Ok(handle)
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    fn shell(script: &str) -> Config {
        let mut command = std::process::Command::new("sh");
        command.args(["-c", script]);
        Config {
            command,
            stdin_mode: 2,
            stdout_mode: 3,
            stderr_mode: 3,
            input: vec![],
            timeout_ms: 3000,
            output_limit: 16 * 1024 * 1024,
            pending_limit: 1024 * 1024,
            manage_tree: true,
            merge_stderr: false,
        }
    }
    #[test]
    fn canceled_forwarding_does_not_accumulate_blocked_workers() {
        sync_task(async {
            let mut releases = Vec::new();
            for _ in 0..2 {
                let (release_tx, release_rx) = std::sync::mpsc::channel();
                let (started_tx, started_rx) = tokio::sync::oneshot::channel();
                let task = tokio::spawn(forward_blocking(move || {
                    let _ = started_tx.send(());
                    release_rx.recv().unwrap();
                    Ok(())
                }));
                started_rx.await.unwrap();
                task.abort();
                releases.push(release_tx);
            }
            assert_eq!(forwarding_slots().available_permits(), 0);
            for _ in 0..20 {
                let task = tokio::spawn(forward_blocking(|| {
                    panic!("forwarding exceeded worker bound")
                }));
                tokio::task::yield_now().await;
                task.abort();
            }
            for release in releases {
                release.send(()).unwrap();
            }
            tokio::time::timeout(Duration::from_secs(1), async {
                while forwarding_slots().available_permits() != 2 {
                    tokio::task::yield_now().await;
                }
            })
            .await
            .unwrap();
        });
    }
    #[test]
    fn nonzero_and_bytes() {
        let child = Child::spawn(shell("printf '\\377'; printf err >&2; exit 7")).unwrap();
        let output = child.wait().unwrap();
        assert_eq!(output.exit_code, 7);
        assert_eq!(output.stdout, [255]);
        assert_eq!(output.stderr, b"err");
        assert_eq!(child.wait().unwrap().exit_code, 7);
    }
    #[test]
    fn simultaneous_output_cannot_deadlock() {
        let output = Child::spawn(shell(
            "(head -c 200000 /dev/zero >&2) & head -c 200000 /dev/zero; wait",
        ))
        .unwrap()
        .wait()
        .unwrap();
        assert_eq!(output.stdout.len(), 200000);
        assert_eq!(output.stderr.len(), 200000);
        assert_eq!(output.failure, 0);
    }
    #[test]
    fn capture_limit_retains_bounded_partial_output() {
        let mut config = shell("head -c 200000 /dev/zero");
        config.output_limit = 1000;
        let output = Child::spawn(config).unwrap().wait().unwrap();
        assert_eq!(output.failure, 2);
        assert_eq!(output.stdout.len(), 1000);
    }
    #[test]
    fn deadline_includes_descendant_pipe_ownership() {
        let mut config = shell("sleep 30 & exit 0");
        config.timeout_ms = 60;
        let before = Instant::now();
        let output = Child::spawn(config).unwrap().wait().unwrap();
        assert_eq!(output.failure, 1);
        assert!(before.elapsed() < Duration::from_secs(2));
    }
    #[test]
    fn interactive_stdin_and_chunked_output() {
        let mut config = shell("cat");
        config.stdin_mode = 4;
        config.stdout_mode = 4;
        let child = Child::spawn(config).unwrap();
        assert!(child.try_wait().unwrap().is_none());
        child.write(b"hello".to_vec(), 1000).unwrap();
        child.close_stdin().unwrap();
        let mut bytes = Vec::new();
        loop {
            let event = child.read(2, 1000).unwrap();
            if event.stream == 0 {
                break;
            }
            assert!(event.bytes.len() <= 2);
            bytes.extend(event.bytes);
        }
        assert_eq!(bytes, b"hello");
        assert_eq!(child.wait().unwrap().exit_code, 0);
        child.close().unwrap();
        child.close().unwrap();
        assert!(child.pid().is_err());
    }
    #[test]
    fn cwd_does_not_change_parent() {
        let original = std::env::current_dir().unwrap();
        let tmp = tempfile::tempdir().unwrap();
        let mut config = shell("pwd");
        config.command.current_dir(tmp.path());
        let child = Child::spawn(config).unwrap();
        let output = child.wait().unwrap();
        assert_eq!(
            std::path::Path::new(String::from_utf8(output.stdout).unwrap().trim()),
            std::fs::canonicalize(tmp.path()).unwrap()
        );
        assert_eq!(std::env::current_dir().unwrap(), original);
    }
    #[test]
    fn drop_terminates_and_reaps() {
        let child = Child::spawn(shell("sleep 30")).unwrap();
        let shared = child.shared.clone();
        drop(child);
        let state = shared.state.lock().unwrap();
        let (state, result) = shared
            .changed
            .wait_timeout_while(state, Duration::from_secs(2), |state| !state.done)
            .unwrap();
        assert!(!result.timed_out());
        assert!(state.done);
    }
    #[test]
    fn merged_output_preserves_kernel_pipe_order() {
        let mut config = shell("printf a; printf b >&2; printf c; printf d >&2");
        config.merge_stderr = true;
        let output = Child::spawn(config).unwrap().wait().unwrap();
        assert_eq!(output.stdout, b"abcd");
        assert!(output.stderr.is_empty());
    }
    #[test]
    fn automatic_input_is_not_lost_by_wait() {
        let mut config = shell("cat");
        config.stdin_mode = 3;
        config.input = vec![42; 200000];
        let output = Child::spawn(config).unwrap().wait().unwrap();
        assert_eq!(output.stdout, vec![42; 200000]);
    }
    #[test]
    fn wait_closes_interactive_stdin() {
        let mut config = shell("cat");
        config.stdin_mode = 4;
        let child = Child::spawn(config).unwrap();
        assert_eq!(child.wait().unwrap().exit_code, 0);
    }
    #[test]
    fn signal_status_and_kill() {
        let child = Child::spawn(shell("sleep 30")).unwrap();
        child.kill().unwrap();
        let output = child.wait().unwrap();
        assert_eq!(output.signal, libc::SIGKILL);
        assert_eq!(output.failure, 0);
    }
    #[test]
    fn pending_output_limit_is_bounded() {
        let mut config = shell("head -c 200000 /dev/zero");
        config.stdout_mode = 4;
        config.pending_limit = 1000;
        let child = Child::spawn(config).unwrap();
        let output = child.wait().unwrap();
        assert_eq!(output.failure, 2);
        assert_eq!(child.read(2000, 1000).unwrap().bytes.len(), 1000);
    }
    #[test]
    fn native_arguments_survive_without_utf8_conversion() {
        use std::os::unix::ffi::OsStringExt;
        let mut config = shell("printf '%s' \"$1\"");
        config
            .command
            .arg("script")
            .arg(std::ffi::OsString::from_vec(vec![255, 42]));
        let output = Child::spawn(config).unwrap().wait().unwrap();
        assert_eq!(output.stdout, [255, 42]);
    }
    #[test]
    fn missing_program_is_spawn_error() {
        let mut config = shell("");
        config.command = std::process::Command::new("/does/not/exist/basic-cli");
        assert_eq!(
            Child::spawn(config).err().unwrap().kind(),
            io::ErrorKind::NotFound
        );
    }
}
