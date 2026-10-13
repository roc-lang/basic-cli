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

/// How a child ended. A signal is reported on Unix only.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Status {
    Exited(i32),
    #[cfg_attr(not(unix), allow(dead_code))]
    Signaled(i32),
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Output {
    pub status: Status,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}
/// Output captured before a deadline or a limit stopped the command.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Partial {
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}
/// Why a command did not start or did not run to completion.
#[derive(Debug)]
pub enum Error {
    /// No process exists: the program, its pipes or its supervisor failed.
    Start(io::Error),
    /// The command's own deadline expired and it was killed.
    TimedOut(Partial),
    /// A capture or pending-output limit was exceeded and it was killed.
    OutputLimitExceeded(Partial),
    /// An operating-system failure while the command ran, or an expired wait
    /// of one `read` or `write` (`io::ErrorKind::TimedOut`).
    Io(io::Error),
}
/// A failed operation on a child handle.
#[derive(Debug)]
pub enum ChildError {
    /// The handle was closed with `close`.
    Closed,
    Cmd(Error),
}
impl From<Error> for ChildError {
    fn from(error: Error) -> Self {
        ChildError::Cmd(error)
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Stream {
    Stdout,
    Stderr,
}
#[derive(Clone, Debug)]
pub struct Event {
    pub stream: Stream,
    pub bytes: Vec<u8>,
}
pub enum StdinMode {
    Inherit,
    Null,
    /// Written to the child and closed by the supervisor.
    Bytes(Vec<u8>),
    /// Written with `Child::write` and closed with `Child::close_stdin`.
    Pipe,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OutputMode {
    Inherit,
    Null,
    Capture,
    /// Captured and forwarded to the parent's stream.
    Tee,
    /// Queued as events for `Child::read`.
    Pipe,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StderrMode {
    Separate(OutputMode),
    /// Share stdout's OS pipe, mode and budget; reported as stdout.
    MergeWithStdout,
}
pub struct Config {
    pub command: std::process::Command,
    pub stdin: StdinMode,
    pub stdout: OutputMode,
    pub stderr: StderrMode,
    /// `None` is no deadline; zero expires immediately.
    pub timeout: Option<Duration>,
    /// Combined capture budget; `None` is unlimited.
    pub output_limit: Option<usize>,
    pub pending_limit: usize,
    pub manage_tree: bool,
}
/// What stopped a command before it finished on its own.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Stop {
    TimedOut,
    OutputLimit,
}
struct State {
    stdout: Vec<u8>,
    stderr: Vec<u8>,
    status: Status,
    events: VecDeque<Event>,
    pending: usize,
    done: bool,
    stop: Option<Stop>,
    error: Option<(io::ErrorKind, String)>,
    /// The error is from reaping the process, not from one of its pipes.
    reap_failed: bool,
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
fn output_stdio(mode: OutputMode) -> Stdio {
    match mode {
        OutputMode::Inherit => Stdio::inherit(),
        OutputMode::Null => Stdio::null(),
        OutputMode::Capture | OutputMode::Tee | OutputMode::Pipe => Stdio::piped(),
    }
}
fn stored_error(error: &(io::ErrorKind, String)) -> io::Error {
    io::Error::new(error.0, error.1.clone())
}
fn wait_timed_out(what: &str) -> Error {
    Error::Io(io::Error::new(io::ErrorKind::TimedOut, what))
}
impl Child {
    pub fn spawn(config: Config) -> Result<Self, Error> {
        sync_task(async move { spawn(config).await.map_err(Error::Start) })
    }
    fn check_open(&self) -> Result<(), ChildError> {
        if *self.closed.lock().unwrap() {
            Err(ChildError::Closed)
        } else {
            Ok(())
        }
    }
    /// The process ID the child was started with. It stays readable after
    /// `close`, when the operating system may have reused it.
    pub fn pid(&self) -> u32 {
        self.pid
    }
    pub fn wait(&self) -> Result<Output, ChildError> {
        self.close_stdin()?;
        let mut state = self.shared.state.lock().unwrap();
        while !state.done {
            state = self.shared.changed.wait(state).unwrap();
        }
        Ok(result(&state)?)
    }
    /// `None` while the child is running or its output is still being read.
    pub fn poll(&self) -> Result<Option<Output>, ChildError> {
        self.check_open()?;
        let state = self.shared.state.lock().unwrap();
        if state.done {
            Ok(Some(result(&state)?))
        } else {
            Ok(None)
        }
    }
    pub fn kill(&self) -> Result<(), ChildError> {
        self.check_open()?;
        self.shared.cancel.notify_one();
        Ok(())
    }
    /// Kill and reap the child. Only a failure to reap it is an error: a pipe
    /// that broke because the child was killed is not.
    pub fn close(&self) -> Result<(), Error> {
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
        match &state.error {
            Some(error) if state.reap_failed => Err(Error::Io(stored_error(error))),
            _ => Ok(()),
        }
    }
    pub fn close_stdin(&self) -> Result<(), ChildError> {
        self.check_open()?;
        let stdin = self.stdin.clone();
        sync_task(async move {
            stdin.lock().await.take();
        });
        Ok(())
    }
    /// Write all of `bytes` to a piped stdin within `wait`. A zero wait makes
    /// one attempt that does not block. A timed-out write may have delivered a
    /// prefix.
    pub fn write(&self, bytes: Vec<u8>, wait: Duration) -> Result<(), ChildError> {
        self.check_open()?;
        let stdin = self.stdin.clone();
        let written = sync_task(async move {
            let write = async {
                let mut input = stdin.lock().await;
                input
                    .as_mut()
                    .ok_or_else(|| {
                        io::Error::new(io::ErrorKind::BrokenPipe, "Child stdin is not open")
                    })?
                    .write_all(&bytes)
                    .await
            };
            // A wait too long to represent as a deadline never expires.
            match tokio::time::Instant::now().checked_add(wait) {
                Some(deadline) => tokio::time::timeout_at(deadline, write)
                    .await
                    .map_err(|_| wait_timed_out("Child stdin write timed out"))?
                    .map_err(Error::Io),
                None => write.await.map_err(Error::Io),
            }
        });
        Ok(written?)
    }
    /// The next queued chunk of piped output, waiting up to `wait` for one. A
    /// zero wait returns a chunk that is ready and otherwise times out. `None`
    /// once the child is done and every chunk has been returned.
    pub fn read(&self, wait: Duration) -> Result<Option<Event>, ChildError> {
        self.check_open()?;
        // A wait too long to represent as a deadline never expires.
        let deadline = Instant::now().checked_add(wait);
        let mut state = self.shared.state.lock().unwrap();
        loop {
            if let Some(event) = state.events.pop_front() {
                state.pending -= event.bytes.len();
                return Ok(Some(event));
            }
            if state.done {
                return match (&state.error, state.stop) {
                    (Some(error), None) => Err(Error::Io(stored_error(error)).into()),
                    _ => Ok(None),
                };
            }
            state = match deadline {
                Some(deadline) => {
                    let remaining = deadline.saturating_duration_since(Instant::now());
                    if remaining.is_zero() {
                        return Err(wait_timed_out("Child output read timed out").into());
                    }
                    self.shared
                        .changed
                        .wait_timeout(state, remaining)
                        .unwrap()
                        .0
                }
                None => self.shared.changed.wait(state).unwrap(),
            };
        }
    }
}
impl Drop for Child {
    fn drop(&mut self) {
        self.shared.cancel.notify_one();
    }
}
/// The outcome of a finished command. A deadline or limit that stopped it
/// outranks an I/O error, which is then a consequence of the kill.
fn result(state: &State) -> Result<Output, Error> {
    let partial = || Partial {
        stdout: state.stdout.clone(),
        stderr: state.stderr.clone(),
    };
    match (state.stop, &state.error) {
        (Some(Stop::TimedOut), _) => Err(Error::TimedOut(partial())),
        (Some(Stop::OutputLimit), _) => Err(Error::OutputLimitExceeded(partial())),
        (None, Some(error)) => Err(Error::Io(stored_error(error))),
        (None, None) => Ok(Output {
            status: state.status,
            stdout: state.stdout.clone(),
            stderr: state.stderr.clone(),
        }),
    }
}
fn report_error(shared: &Shared, error: &io::Error) {
    {
        let mut state = shared.state.lock().unwrap();
        if state.error.is_none() {
            state.error = Some((error.kind(), error.to_string()));
        }
    }
    shared.cancel.notify_one();
    shared.changed.notify_all();
}
/// The first reason to stop a command is the one reported.
fn stop(shared: &Shared, state: &mut State, reason: Stop) {
    if state.stop.is_none() {
        state.stop = Some(reason);
    }
    shared.cancel.notify_one();
}
struct Pump {
    shared: Arc<Shared>,
    stream: Stream,
    mode: OutputMode,
    output_limit: usize,
    pending_limit: usize,
}
async fn observed_pump<R: AsyncRead + Unpin>(reader: R, pump: Pump) -> io::Result<()> {
    let shared = pump.shared.clone();
    let result = pump.run(reader).await;
    if let Err(error) = &result {
        report_error(&shared, error);
    }
    result
}
impl Pump {
    async fn run<R: AsyncRead + Unpin>(self, mut reader: R) -> io::Result<()> {
        let Pump {
            shared,
            stream,
            mode,
            output_limit,
            pending_limit,
        } = self;
        let mut buffer = [0u8; 8192];
        loop {
            let count = reader.read(&mut buffer).await?;
            if count == 0 {
                return Ok(());
            }
            {
                let mut state = shared.state.lock().unwrap();
                match mode {
                    OutputMode::Pipe => {
                        let keep = count.min(pending_limit.saturating_sub(state.pending));
                        if keep != 0 {
                            state.events.push_back(Event {
                                stream,
                                bytes: buffer[..keep].to_vec(),
                            });
                            state.pending += keep;
                        }
                        if keep != count {
                            stop(&shared, &mut state, Stop::OutputLimit);
                        }
                    }
                    OutputMode::Capture | OutputMode::Tee => {
                        let used = state.stdout.len() + state.stderr.len();
                        let keep = count.min(output_limit.saturating_sub(used));
                        match stream {
                            Stream::Stdout => state.stdout.extend_from_slice(&buffer[..keep]),
                            Stream::Stderr => state.stderr.extend_from_slice(&buffer[..keep]),
                        }
                        if keep != count {
                            stop(&shared, &mut state, Stop::OutputLimit);
                        }
                    }
                    OutputMode::Inherit | OutputMode::Null => {}
                }
                shared.changed.notify_all();
            }
            // `Inherit` is pumped only for a merged stream, which has to pass
            // through the shared pipe to keep its order.
            if matches!(mode, OutputMode::Tee | OutputMode::Inherit) {
                // Blocking terminal writes run outside the service thread.
                let bytes = buffer[..count].to_vec();
                forward_blocking(move || {
                    use std::io::Write;
                    match stream {
                        Stream::Stdout => std::io::stdout().write_all(&bytes),
                        Stream::Stderr => std::io::stderr().write_all(&bytes),
                    }
                })
                .await?;
            }
        }
    }
}
async fn spawn(mut config: Config) -> io::Result<Child> {
    // A deadline too far away to represent never expires.
    let deadline = config
        .timeout
        .and_then(|timeout| tokio::time::Instant::now().checked_add(timeout));
    config.command.stdin(match config.stdin {
        StdinMode::Inherit => Stdio::inherit(),
        StdinMode::Null => Stdio::null(),
        StdinMode::Bytes(_) | StdinMode::Pipe => Stdio::piped(),
    });
    config.command.stdout(output_stdio(config.stdout));
    let merge = config.stderr == StderrMode::MergeWithStdout;
    // Both descriptors share one kernel pipe, preserving their actual write ordering.
    let merged = match config.stderr {
        StderrMode::Separate(mode) => {
            config.command.stderr(output_stdio(mode));
            None
        }
        StderrMode::MergeWithStdout if config.stdout == OutputMode::Null => {
            config.command.stderr(Stdio::null());
            None
        }
        StderrMode::MergeWithStdout => {
            let (reader, writer) = std::io::pipe()?;
            config.command.stdout(Stdio::from(writer.try_clone()?));
            config.command.stderr(Stdio::from(writer));
            #[cfg(unix)]
            let reader = std::process::ChildStdout::from(std::os::fd::OwnedFd::from(reader));
            #[cfg(windows)]
            let reader =
                std::process::ChildStdout::from(std::os::windows::io::OwnedHandle::from(reader));
            Some(tokio::process::ChildStdout::from_std(reader)?)
        }
    };
    let stderr_mode = match config.stderr {
        StderrMode::Separate(mode) => mode,
        StderrMode::MergeWithStdout => config.stdout,
    };
    let (automatic_input, input) = match config.stdin {
        StdinMode::Bytes(bytes) => (true, bytes),
        _ => (false, Vec::new()),
    };
    let output_limit = config.output_limit.unwrap_or(usize::MAX);
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
    let automatic_pipe = if automatic_input {
        input_pipe.take()
    } else {
        None
    };
    let stdin = Arc::new(AsyncMutex::new(input_pipe));
    let shared = Arc::new(Shared {
        state: Mutex::new(State {
            stdout: Vec::new(),
            stderr: Vec::new(),
            status: Status::Exited(-1),
            events: VecDeque::new(),
            pending: 0,
            done: false,
            stop: None,
            error: None,
            reap_failed: false,
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
                Pump {
                    shared: shared.clone(),
                    stream: Stream::Stdout,
                    mode: config.stdout,
                    output_limit,
                    pending_limit: config.pending_limit,
                },
            )));
        }
        if let Some(pipe) = stderr {
            readers.push(tokio::spawn(observed_pump(
                pipe,
                Pump {
                    shared: shared.clone(),
                    stream: if merge {
                        Stream::Stdout
                    } else {
                        Stream::Stderr
                    },
                    mode: stderr_mode,
                    output_limit,
                    pending_limit: config.pending_limit,
                },
            )));
        }
        let mut writer = if automatic_input {
            let shared = shared.clone();
            Some(tokio::spawn(async move {
                let result = if let Some(mut pipe) = automatic_pipe {
                    pipe.write_all(&input).await
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
        let expiry = async {
            match deadline {
                // The timer rounds up to its next tick, so a deadline that
                // has already passed is decided here and not by a sleep the
                // command could finish before.
                Some(deadline) if deadline <= tokio::time::Instant::now() => {}
                Some(deadline) => tokio::time::sleep_until(deadline).await,
                None => std::future::pending::<()>().await,
            }
        };
        // Polled in this order, so a deadline that has already passed (a zero
        // timeout) stops the command even if it would also have finished.
        let completed = tokio::select! {
            biased;
            _ = shared.cancel.notified() => None,
            _ = expiry => {
                let mut state = shared.state.lock().unwrap();
                stop(&shared, &mut state, Stop::TimedOut);
                None
            }
            result = completion => Some(result),
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
                state.status = Status::Exited(status.code().unwrap_or(-1));
                #[cfg(unix)]
                {
                    use std::os::unix::process::ExitStatusExt;
                    if let Some(signal) = status.signal() {
                        state.status = Status::Signaled(signal);
                    }
                }
            }
            Err(err) => {
                // A pipe failure was recorded when it happened; anything else
                // here is a failure to wait for the process itself.
                if state.error.is_none() {
                    state.error = Some((err.kind(), err.to_string()));
                    state.reap_failed = true;
                }
            }
        }
        state.done = true;
        shared.changed.notify_all();
    });
    Ok(handle)
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    const SECOND: Duration = Duration::from_secs(1);
    fn shell(script: &str) -> Config {
        let mut command = std::process::Command::new("sh");
        command.args(["-c", script]);
        Config {
            command,
            stdin: StdinMode::Null,
            stdout: OutputMode::Capture,
            stderr: StderrMode::Separate(OutputMode::Capture),
            timeout: Some(Duration::from_secs(3)),
            output_limit: Some(16 * 1024 * 1024),
            pending_limit: 1024 * 1024,
            manage_tree: true,
        }
    }
    fn run(config: Config) -> Result<Output, ChildError> {
        Child::spawn(config).unwrap().wait()
    }
    fn timed_out(result: Result<Output, ChildError>) -> Partial {
        match result {
            Err(ChildError::Cmd(Error::TimedOut(partial))) => partial,
            other => panic!("expected a timeout, got {other:?}"),
        }
    }
    fn limit_exceeded(result: Result<Output, ChildError>) -> Partial {
        match result {
            Err(ChildError::Cmd(Error::OutputLimitExceeded(partial))) => partial,
            other => panic!("expected an exceeded limit, got {other:?}"),
        }
    }
    fn io_kind<T: std::fmt::Debug>(result: Result<T, ChildError>) -> io::ErrorKind {
        match result {
            Err(ChildError::Cmd(Error::Io(error))) => error.kind(),
            other => panic!("expected an I/O error, got {other:?}"),
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
        assert_eq!(output.status, Status::Exited(7));
        assert_eq!(output.stdout, [255]);
        assert_eq!(output.stderr, b"err");
        assert_eq!(child.wait().unwrap().status, Status::Exited(7));
    }
    #[test]
    fn simultaneous_output_cannot_deadlock() {
        let output = run(shell(
            "(head -c 200000 /dev/zero >&2) & head -c 200000 /dev/zero; wait",
        ))
        .unwrap();
        assert_eq!(output.stdout.len(), 200000);
        assert_eq!(output.stderr.len(), 200000);
        assert_eq!(output.status, Status::Exited(0));
    }
    #[test]
    fn capture_limit_retains_bounded_partial_output() {
        let mut config = shell("printf err >&2; sleep 0.2; head -c 200000 /dev/zero");
        config.output_limit = Some(1000);
        let partial = limit_exceeded(run(config));
        assert_eq!(partial.stderr, b"err");
        assert_eq!(partial.stdout, vec![0; 997]);
    }
    #[test]
    fn zero_capture_limit_allows_no_output() {
        let mut config = shell("printf x");
        config.output_limit = Some(0);
        assert_eq!(limit_exceeded(run(config)), Partial::default());
    }
    #[test]
    fn no_capture_limit_keeps_everything() {
        let mut config = shell("head -c 200000 /dev/zero");
        config.output_limit = None;
        assert_eq!(run(config).unwrap().stdout.len(), 200000);
    }
    #[test]
    fn deadline_includes_descendant_pipe_ownership() {
        let mut config = shell("sleep 30 & exit 0");
        config.timeout = Some(Duration::from_millis(60));
        let before = Instant::now();
        timed_out(run(config));
        assert!(before.elapsed() < Duration::from_secs(2));
    }
    #[test]
    fn deadline_kills_and_returns_partial_output() {
        let mut config = shell("echo Hi; printf warn >&2; sleep 30");
        config.timeout = Some(Duration::from_millis(500));
        let before = Instant::now();
        let child = Child::spawn(config).unwrap();
        let partial = timed_out(child.wait());
        assert!(before.elapsed() < Duration::from_secs(5));
        assert_eq!(partial.stdout, b"Hi\n");
        assert_eq!(partial.stderr, b"warn");
        // The result is stable, and polling reports the same thing.
        assert_eq!(timed_out(child.wait()), partial);
        assert_eq!(timed_out(child.poll().map(Option::unwrap)), partial);
        // The process is gone: nothing answers to its ID.
        assert_eq!(unsafe { libc::kill(child.pid() as i32, 0) }, -1);
    }
    #[test]
    fn deadline_kills_a_spawned_child_nobody_waits_on() {
        let mut config = shell("sleep 30");
        config.timeout = Some(Duration::from_millis(100));
        let child = Child::spawn(config).unwrap();
        let before = Instant::now();
        loop {
            match child.poll() {
                Ok(None) => {
                    assert!(before.elapsed() < Duration::from_secs(5));
                    std::thread::sleep(Duration::from_millis(10));
                }
                other => {
                    assert_eq!(timed_out(other.map(Option::unwrap)), Partial::default());
                    break;
                }
            }
        }
    }
    #[test]
    fn zero_timeout_expires_immediately() {
        // The command would succeed at once; a zero deadline still wins.
        let mut config = shell("exit 0");
        config.timeout = Some(Duration::ZERO);
        let before = Instant::now();
        assert_eq!(timed_out(run(config)), Partial::default());
        let mut config = shell("sleep 30");
        config.timeout = Some(Duration::ZERO);
        assert_eq!(timed_out(run(config)), Partial::default());
        assert!(before.elapsed() < Duration::from_secs(5));
    }
    #[test]
    fn no_timeout_and_unrepresentable_timeout_do_not_expire() {
        let mut config = shell("sleep 0.2; echo done");
        config.timeout = None;
        assert_eq!(run(config).unwrap().stdout, b"done\n");
        let mut config = shell("echo done");
        config.timeout = Some(Duration::MAX);
        assert_eq!(run(config).unwrap().stdout, b"done\n");
    }
    #[test]
    fn interactive_stdin_and_chunked_output() {
        let mut config = shell("cat");
        config.stdin = StdinMode::Pipe;
        config.stdout = OutputMode::Pipe;
        let child = Child::spawn(config).unwrap();
        assert!(child.poll().unwrap().is_none());
        child.write(b"hello".to_vec(), SECOND).unwrap();
        child.close_stdin().unwrap();
        let mut bytes = Vec::new();
        while let Some(event) = child.read(SECOND).unwrap() {
            assert_eq!(event.stream, Stream::Stdout);
            bytes.extend(event.bytes);
        }
        assert_eq!(bytes, b"hello");
        // The end is reported again on every later read.
        assert!(child.read(Duration::ZERO).unwrap().is_none());
        assert_eq!(child.wait().unwrap().status, Status::Exited(0));
        child.close().unwrap();
        child.close().unwrap();
    }
    #[test]
    fn use_after_close_is_closed() {
        let mut config = shell("cat");
        config.stdin = StdinMode::Pipe;
        config.stdout = OutputMode::Pipe;
        let child = Child::spawn(config).unwrap();
        let pid = child.pid();
        child.close().unwrap();
        assert!(matches!(child.read(SECOND), Err(ChildError::Closed)));
        assert!(matches!(
            child.read(Duration::ZERO),
            Err(ChildError::Closed)
        ));
        assert!(matches!(
            child.write(b"x".to_vec(), SECOND),
            Err(ChildError::Closed)
        ));
        assert!(matches!(child.wait(), Err(ChildError::Closed)));
        assert!(matches!(child.poll(), Err(ChildError::Closed)));
        assert!(matches!(child.kill(), Err(ChildError::Closed)));
        assert!(matches!(child.close_stdin(), Err(ChildError::Closed)));
        // Closing again succeeds, and the process ID stays readable.
        child.close().unwrap();
        assert_eq!(child.pid(), pid);
    }
    #[test]
    fn close_kills_and_reaps_a_running_child() {
        let mut config = shell("sleep 30");
        config.stdin = StdinMode::Bytes(vec![1; 200000]);
        let child = Child::spawn(config).unwrap();
        let before = Instant::now();
        // The unread input pipe breaks when the child dies; that is not a
        // failure to close.
        child.close().unwrap();
        assert!(before.elapsed() < Duration::from_secs(2));
        assert_eq!(unsafe { libc::kill(child.pid() as i32, 0) }, -1);
    }
    #[test]
    fn zero_wait_read_returns_what_is_ready_or_times_out() {
        let mut config = shell("read line; echo \"$line\"; read line");
        config.stdin = StdinMode::Pipe;
        config.stdout = OutputMode::Pipe;
        let child = Child::spawn(config).unwrap();
        // Nothing has been written yet, and a zero wait does not block.
        let before = Instant::now();
        assert_eq!(io_kind(child.read(Duration::ZERO)), io::ErrorKind::TimedOut);
        assert!(before.elapsed() < Duration::from_millis(500));
        child.write(b"ping\n".to_vec(), SECOND).unwrap();
        // Wait for the reply to be queued, then take it without waiting.
        let deadline = Instant::now() + Duration::from_secs(5);
        let event = loop {
            match child.read(Duration::ZERO) {
                Ok(event) => break event.unwrap(),
                Err(error) => {
                    assert_eq!(io_kind::<()>(Err(error)), io::ErrorKind::TimedOut);
                    assert!(Instant::now() < deadline);
                    std::thread::sleep(Duration::from_millis(5));
                }
            }
        };
        assert_eq!(event.bytes, b"ping\n");
        // The child is still running, so a timed-out read is not the end.
        assert_eq!(
            io_kind(child.read(Duration::from_millis(20))),
            io::ErrorKind::TimedOut
        );
        assert!(child.poll().unwrap().is_none());
        child.close_stdin().unwrap();
        assert!(child.read(SECOND).unwrap().is_none());
    }
    #[test]
    fn write_without_a_pipe_is_broken_pipe_and_a_full_pipe_times_out() {
        let child = Child::spawn(shell("sleep 30")).unwrap();
        assert_eq!(
            io_kind(child.write(b"x".to_vec(), SECOND)),
            io::ErrorKind::BrokenPipe
        );
        let mut config = shell("sleep 30");
        config.stdin = StdinMode::Pipe;
        let child = Child::spawn(config).unwrap();
        // More than a pipe holds, to a child that never reads.
        let input = vec![7; 4 * 1024 * 1024];
        assert_eq!(
            io_kind(child.write(input.clone(), Duration::ZERO)),
            io::ErrorKind::TimedOut
        );
        assert_eq!(
            io_kind(child.write(input, Duration::from_millis(50))),
            io::ErrorKind::TimedOut
        );
        child.close_stdin().unwrap();
        assert_eq!(
            io_kind(child.write(b"x".to_vec(), SECOND)),
            io::ErrorKind::BrokenPipe
        );
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
        config.stderr = StderrMode::MergeWithStdout;
        let output = run(config).unwrap();
        assert_eq!(output.stdout, b"abcd");
        assert!(output.stderr.is_empty());
    }
    #[test]
    fn merged_output_follows_a_piped_or_null_stdout() {
        let mut config = shell("printf a; printf b >&2");
        config.stdout = OutputMode::Pipe;
        config.stderr = StderrMode::MergeWithStdout;
        let child = Child::spawn(config).unwrap();
        let mut bytes = Vec::new();
        while let Some(event) = child.read(SECOND).unwrap() {
            assert_eq!(event.stream, Stream::Stdout);
            bytes.extend(event.bytes);
        }
        assert_eq!(bytes, b"ab");
        let mut config = shell("printf a; printf b >&2");
        config.stdout = OutputMode::Null;
        config.stderr = StderrMode::MergeWithStdout;
        let output = run(config).unwrap();
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
    }
    #[test]
    fn separate_pipes_are_tagged_by_stream() {
        let mut config = shell("printf out; sleep 0.2; printf err >&2");
        config.stdout = OutputMode::Pipe;
        config.stderr = StderrMode::Separate(OutputMode::Pipe);
        let child = Child::spawn(config).unwrap();
        let mut events = Vec::new();
        while let Some(event) = child.read(SECOND).unwrap() {
            events.push((event.stream, event.bytes));
        }
        assert_eq!(
            events,
            [
                (Stream::Stdout, b"out".to_vec()),
                (Stream::Stderr, b"err".to_vec())
            ]
        );
    }
    #[test]
    fn automatic_input_is_not_lost_by_wait() {
        let mut config = shell("cat");
        config.stdin = StdinMode::Bytes(vec![42; 200000]);
        let output = run(config).unwrap();
        assert_eq!(output.stdout, vec![42; 200000]);
    }
    #[test]
    fn wait_closes_interactive_stdin() {
        let mut config = shell("cat");
        config.stdin = StdinMode::Pipe;
        let child = Child::spawn(config).unwrap();
        assert_eq!(child.wait().unwrap().status, Status::Exited(0));
    }
    #[test]
    fn signal_status_and_kill() {
        let child = Child::spawn(shell("sleep 30")).unwrap();
        child.kill().unwrap();
        // A kill the caller asked for is a status, not an error.
        let output = child.wait().unwrap();
        assert_eq!(output.status, Status::Signaled(libc::SIGKILL));
        // Killing a child that is gone does nothing.
        child.kill().unwrap();
        assert_eq!(child.wait().unwrap(), output);
    }
    #[test]
    fn signal_a_child_sends_itself_is_its_status() {
        let output = run(shell("kill -TERM $$")).unwrap();
        assert_eq!(output.status, Status::Signaled(libc::SIGTERM));
    }
    #[test]
    fn pending_output_limit_is_bounded() {
        let mut config = shell("head -c 200000 /dev/zero");
        config.stdout = OutputMode::Pipe;
        config.pending_limit = 1000;
        let child = Child::spawn(config).unwrap();
        // Piped output is not captured, so the partial output is empty.
        assert_eq!(limit_exceeded(child.wait()), Partial::default());
        let mut pending = 0;
        while let Some(event) = child.read(SECOND).unwrap() {
            pending += event.bytes.len();
        }
        assert_eq!(pending, 1000);
    }
    #[test]
    fn native_arguments_survive_without_utf8_conversion() {
        use std::os::unix::ffi::OsStringExt;
        let mut config = shell("printf '%s' \"$1\"");
        config
            .command
            .arg("script")
            .arg(std::ffi::OsString::from_vec(vec![255, 42]));
        let output = run(config).unwrap();
        assert_eq!(output.stdout, [255, 42]);
    }
    #[test]
    fn missing_program_is_a_start_failure() {
        let mut config = shell("");
        config.command = std::process::Command::new("/does/not/exist/basic-cli");
        // Even a zero deadline does not hide that nothing was started.
        config.timeout = Some(Duration::ZERO);
        match Child::spawn(config) {
            Err(Error::Start(error)) => assert_eq!(error.kind(), io::ErrorKind::NotFound),
            Err(other) => panic!("expected a start failure, got {other:?}"),
            Ok(_) => panic!("expected a start failure, got a child"),
        }
    }
    #[test]
    fn unstartable_program_is_a_start_failure() {
        let tmp = tempfile::tempdir().unwrap();
        let mut config = shell("");
        config.command = std::process::Command::new(tmp.path());
        match Child::spawn(config) {
            Err(Error::Start(error)) => {
                assert_eq!(error.kind(), io::ErrorKind::PermissionDenied)
            }
            Err(other) => panic!("expected a start failure, got {other:?}"),
            Ok(_) => panic!("expected a start failure, got a child"),
        }
    }
}
