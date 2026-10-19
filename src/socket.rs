//! Buffered, deadline-bounded, interruptible stream sockets shared by TCP and AF_UNIX.
use std::io::{self, Read, Write};
use std::time::{Duration, Instant};

pub(crate) fn check_interrupt() -> io::Result<()> {
    if crate::signals::is_pending() {
        Err(io::ErrorKind::Interrupted.into())
    } else {
        Ok(())
    }
}

/// Bound readiness polls so a native signal wakes every target promptly, even
/// when its console event cannot participate in the socket provider's poll set.
const POLL_SLICE: Duration = Duration::from_millis(10);

pub(crate) fn wait_ready(
    socket: &socket2::Socket,
    write: bool,
    deadline: Deadline,
) -> io::Result<()> {
    loop {
        let duration = deadline.remaining()?.unwrap_or(POLL_SLICE).min(POLL_SLICE);
        let millis = duration
            .as_millis()
            .saturating_add(u128::from(duration.subsec_nanos() % 1_000_000 != 0))
            .min(i32::MAX as u128) as i32;
        #[cfg(unix)]
        let ready = {
            use std::os::fd::AsRawFd;
            let mut fd = libc::pollfd {
                fd: socket.as_raw_fd(),
                events: if write { libc::POLLOUT } else { libc::POLLIN },
                revents: 0,
            };
            let count = unsafe { libc::poll(&mut fd, 1, millis) };
            if count < 0 {
                Err(io::Error::last_os_error())
            } else {
                Ok(count > 0)
            }
        };
        #[cfg(windows)]
        let ready = {
            use std::os::windows::io::AsRawSocket;
            use windows_sys::Win32::Networking::WinSock::{
                WSAGetLastError, WSAPoll, POLLRDNORM, POLLWRNORM, SOCKET_ERROR, WSAPOLLFD,
            };
            let mut fd = WSAPOLLFD {
                fd: socket.as_raw_socket() as _,
                events: if write { POLLWRNORM } else { POLLRDNORM },
                revents: 0,
            };
            let count = unsafe { WSAPoll(&mut fd, 1, millis) };
            if count == SOCKET_ERROR {
                Err(io::Error::from_raw_os_error(unsafe { WSAGetLastError() }))
            } else {
                Ok(count > 0)
            }
        };
        deadline.remaining()?;
        match ready {
            Ok(true) => return Ok(()),
            Ok(false) => {}
            Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
            Err(error) => return Err(error),
        }
    }
}

pub(crate) fn connect(
    socket: &socket2::Socket,
    address: &socket2::SockAddr,
    deadline: Deadline,
) -> io::Result<()> {
    deadline.remaining()?;
    socket.set_nonblocking(true)?;
    match socket.connect(address) {
        Ok(()) => return Ok(()),
        Err(error) if error.kind() == io::ErrorKind::WouldBlock => {}
        #[cfg(unix)]
        Err(error) if error.raw_os_error() == Some(libc::EINPROGRESS) => {}
        Err(error) => return Err(error),
    }
    wait_ready(socket, true, deadline)?;
    match socket.take_error()? {
        Some(error) => Err(error),
        None => Ok(()),
    }
}

/// How much one socket read may add to a connection's buffer. Also the upper
/// bound of a `Tcp.Connection.chunks` item, which asks for this many bytes.
pub(crate) const READ_CHUNK: usize = 64 * 1024;

pub(crate) fn timed_out() -> io::Error {
    io::Error::new(io::ErrorKind::TimedOut, "TCP operation timed out")
}

/// Give a socket timeout the one kind Roc sees, whichever the OS reported.
pub(crate) fn normalize(error: io::Error) -> io::Error {
    if error.kind() == io::ErrorKind::WouldBlock {
        timed_out()
    } else {
        error
    }
}

/// The instant a whole operation must finish by.
#[derive(Clone, Copy)]
pub(crate) struct Deadline(Option<Instant>);

impl Deadline {
    pub(crate) fn for_wait(nanos: Option<u64>) -> io::Result<Self> {
        match nanos {
            Some(nanos) => Self::after_nanos(nanos),
            None => {
                check_interrupt()?;
                Ok(Self(None))
            }
        }
    }
    /// A deadline `nanos` from now. Zero has already expired. A timeout too
    /// long for the clock to represent never expires.
    pub(crate) fn after_nanos(nanos: u64) -> io::Result<Self> {
        check_interrupt()?;
        if nanos == 0 {
            return Err(timed_out());
        }
        Ok(Self(
            Instant::now().checked_add(Duration::from_nanos(nanos)),
        ))
    }

    /// The time left, or `TimedOut` once there is none. `None` is unbounded.
    pub(crate) fn remaining(self) -> io::Result<Option<Duration>> {
        check_interrupt()?;
        let Some(deadline) = self.0 else {
            return Ok(None);
        };
        match deadline.checked_duration_since(Instant::now()) {
            Some(remaining) if !remaining.is_zero() => Ok(Some(remaining)),
            _ => Err(timed_out()),
        }
    }
}

fn out_of_memory() -> io::Error {
    io::Error::new(
        io::ErrorKind::OutOfMemory,
        "could not reserve memory for TCP read",
    )
}

/// Why a delimited read returned no record.
#[derive(Debug)]
pub(crate) enum ReadUntilError {
    Io(io::Error),
    /// The record is longer than the limit. Its tail is discarded before the
    /// next read returns.
    LimitExceeded,
}

impl From<io::Error> for ReadUntilError {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

/// A connected socket and the bytes received from it but not yet returned.
pub(crate) struct BufferedSocket {
    stream: socket2::Socket,
    /// Received bytes. Those before `start` have been returned already.
    buffer: Vec<u8>,
    start: usize,
    /// The delimiter of an over-long record whose tail has not all arrived
    /// yet. The next read discards through it before doing anything else.
    discarding: Option<u8>,
}

impl BufferedSocket {
    pub(crate) fn new(stream: socket2::Socket) -> io::Result<Self> {
        stream.set_nonblocking(true)?;
        Ok(Self {
            stream,
            buffer: Vec::new(),
            start: 0,
            discarding: None,
        })
    }

    pub(crate) fn available(&self) -> &[u8] {
        &self.buffer[self.start..]
    }

    fn consume(&mut self, count: usize) {
        self.start += count;
        if self.start == self.buffer.len() {
            self.buffer.clear();
            self.start = 0;
        }
    }

    fn take(&mut self, count: usize) -> io::Result<Vec<u8>> {
        check_interrupt()?;
        let bytes = self.available()[..count].to_vec();
        self.consume(count);
        Ok(bytes)
    }

    /// Wait for the socket and append what one read returns. `Ok(0)` is the
    /// end of input. Buffered bytes are kept whatever the outcome.
    fn fill(&mut self, deadline: Deadline) -> io::Result<usize> {
        if self.start > 0 {
            self.buffer.drain(..self.start);
            self.start = 0;
        }
        let filled = self.buffer.len();
        self.buffer
            .try_reserve(READ_CHUNK)
            .map_err(|_| out_of_memory())?;
        self.buffer.resize(filled + READ_CHUNK, 0);
        let result = loop {
            if let Err(error) = deadline.remaining() {
                break Err(error);
            }
            match (&self.stream).read(&mut self.buffer[filled..]) {
                Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                    if let Err(error) = wait_ready(&self.stream, false, deadline) {
                        break Err(error);
                    }
                }
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                other => break other,
            }
        };
        self.buffer
            .truncate(filled + *result.as_ref().unwrap_or(&0));
        result
    }

    /// Drop the tail of a record that exceeded the limit, through its
    /// delimiter or to the end of input, within `deadline`. If the deadline
    /// passes first, what has arrived is dropped and the rest is left for the
    /// read after this one.
    fn finish_discard(&mut self, deadline: Deadline) -> io::Result<()> {
        while let Some(delimiter) = self.discarding {
            match self.available().iter().position(|&byte| byte == delimiter) {
                Some(index) => {
                    self.consume(index + 1);
                    self.discarding = None;
                }
                None => {
                    self.consume(self.available().len());
                    if self.fill(deadline)? == 0 {
                        self.discarding = None;
                    }
                }
            }
        }
        Ok(())
    }

    /// Read at most `count` bytes, as soon as any are available.
    ///
    /// `None` is the end of input. Asking for zero bytes performs no I/O and
    /// returns an empty buffer, which is data, not the end.
    pub(crate) fn read_up_to(
        &mut self,
        count: u64,
        timeout_nanos: u64,
    ) -> io::Result<Option<Vec<u8>>> {
        let deadline = Deadline::after_nanos(timeout_nanos)?;
        if count == 0 {
            return Ok(Some(Vec::new()));
        }
        self.finish_discard(deadline)?;
        if self.available().is_empty() && self.fill(deadline)? == 0 {
            return Ok(None);
        }
        let count = usize::try_from(count).unwrap_or(usize::MAX);
        Ok(Some(self.take(count.min(self.available().len()))?))
    }

    /// Read exactly `count` bytes.
    ///
    /// If the input ends first the error is `UnexpectedEof`. Like every
    /// failed read that consumes nothing: the bytes that did arrive stay
    /// buffered.
    pub(crate) fn read_exactly(&mut self, count: u64, timeout_nanos: u64) -> io::Result<Vec<u8>> {
        let deadline = Deadline::after_nanos(timeout_nanos)?;
        if count == 0 {
            return Ok(Vec::new());
        }
        let count = usize::try_from(count).map_err(|_| out_of_memory())?;
        self.finish_discard(deadline)?;
        self.buffer
            .try_reserve(count.saturating_sub(self.available().len()))
            .map_err(|_| out_of_memory())?;
        while self.available().len() < count {
            if self.fill(deadline)? == 0 {
                return Err(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    "TCP connection ended before the requested bytes arrived",
                ));
            }
        }
        self.take(count)
    }

    /// Read bytes through and including the next `delimiter`.
    ///
    /// If the input ends first, the bytes before the end are returned without
    /// a delimiter. `None` is the end of input: no byte was left to return.
    ///
    /// A record, counting its delimiter, may be at most `limit` bytes. A
    /// longer one is `LimitExceeded`: the part already received is dropped
    /// at once, and the rest by the next read (see `finish_discard`).
    pub(crate) fn read_until(
        &mut self,
        delimiter: u8,
        limit: u64,
        timeout_nanos: u64,
    ) -> Result<Option<Vec<u8>>, ReadUntilError> {
        let deadline = Deadline::after_nanos(timeout_nanos)?;
        self.finish_discard(deadline)?;
        let limit = usize::try_from(limit).unwrap_or(usize::MAX);
        let mut scanned = 0;
        loop {
            let available = self.available();
            let window = available.len().min(limit);
            let find = |bytes: &[u8]| bytes.iter().position(|&byte| byte == delimiter);
            if let Some(index) = find(&available[scanned..window]) {
                return Ok(Some(self.take(scanned + index + 1)?));
            }
            scanned = window;
            check_interrupt()?;
            if available.len() > limit {
                match find(&available[limit..]) {
                    Some(index) => self.consume(limit + index + 1),
                    None => {
                        self.consume(self.available().len());
                        self.discarding = Some(delimiter);
                    }
                }
                return Err(ReadUntilError::LimitExceeded);
            }
            if self.fill(deadline)? == 0 {
                // The input ended inside the limit: the tail is a record.
                let rest = self.available().len();
                return if rest > 0 {
                    Ok(Some(self.take(rest)?))
                } else {
                    Ok(None)
                };
            }
        }
    }

    /// Read one line, without its `\n` terminator and without one `\r` before
    /// it: the rule of `file_reader::read_line`. The terminator counts
    /// towards `limit`. A final unterminated line is a line.
    pub(crate) fn read_line(
        &mut self,
        limit: u64,
        timeout_nanos: u64,
    ) -> Result<Option<Vec<u8>>, ReadUntilError> {
        Ok(self
            .read_until(b'\n', limit, timeout_nanos)?
            .map(|mut line| {
                if line.last() == Some(&b'\n') {
                    line.pop();
                    if line.last() == Some(&b'\r') {
                        line.pop();
                    }
                }
                line
            }))
    }

    /// Write all of `bytes`. On failure any prefix may have been sent.
    pub(crate) fn write(&mut self, bytes: &[u8], timeout_nanos: u64) -> io::Result<()> {
        let deadline = Deadline::after_nanos(timeout_nanos)?;
        let mut written = 0;
        while written < bytes.len() {
            deadline.remaining()?;
            match self.stream.write(&bytes[written..]) {
                Ok(0) => return Err(io::Error::from(io::ErrorKind::WriteZero)),
                Ok(count) => written += count,
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                    wait_ready(&self.stream, true, deadline)?
                }
                Err(error) => return Err(error),
            }
        }
        Ok(())
    }
}
