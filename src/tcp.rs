//! TCP connections: deadline-bounded reads and writes over one buffered socket.
//!
//! A connection keeps the bytes it has received but not yet returned to Roc in
//! its own buffer, and a read removes bytes from that buffer only when it
//! succeeds. A read that fails, in particular one that times out, therefore
//! consumes nothing, and the next read sees every byte that had arrived.
//!
//! Every failure crosses to Roc as a typed `IOErr`. A socket timeout is
//! reported by the OS as `WouldBlock` on some platforms and `TimedOut` on
//! others; both become `TimedOut` here.
use core::mem::ManuallyDrop;
use std::io::{self, Read, Write};
use std::net::{IpAddr, SocketAddr, TcpStream, ToSocketAddrs};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use crate::roc_platform_abi::*;
use crate::{roc_host, roc_u8_list_from_slice};

/// How much one socket read may add to a connection's buffer. Also the upper
/// bound of a `Tcp.Connection.chunks` item, which asks for this many bytes.
const READ_CHUNK: usize = 64 * 1024;

fn timed_out() -> io::Error {
    io::Error::new(io::ErrorKind::TimedOut, "TCP operation timed out")
}

/// Give a socket timeout the one kind Roc sees, whichever the OS reported.
fn normalize(error: io::Error) -> io::Error {
    if error.kind() == io::ErrorKind::WouldBlock {
        timed_out()
    } else {
        error
    }
}

/// The typed error for Roc. Used by every hosted Tcp function.
pub(crate) fn tcp_io_err(error: io::Error, roc_host: &RocHost) -> IOErr {
    crate::tcp_io_err_from_io(&normalize(error), roc_host)
}

/// The instant a whole operation must finish by.
#[derive(Clone, Copy)]
pub(crate) struct Deadline(Option<Instant>);

impl Deadline {
    /// A deadline `nanos` from now. Zero has already expired. A timeout too
    /// long for the clock to represent never expires.
    pub(crate) fn after_nanos(nanos: u64) -> io::Result<Self> {
        if nanos == 0 {
            return Err(timed_out());
        }
        Ok(Self(
            Instant::now().checked_add(Duration::from_nanos(nanos)),
        ))
    }

    /// The time left, or `TimedOut` once there is none. `None` is unbounded.
    pub(crate) fn remaining(self) -> io::Result<Option<Duration>> {
        let Some(deadline) = self.0 else {
            return Ok(None);
        };
        match deadline.checked_duration_since(Instant::now()) {
            Some(remaining) if !remaining.is_zero() => Ok(Some(remaining)),
            _ => Err(timed_out()),
        }
    }
}

pub(crate) fn resolve_with_deadline(
    host: String,
    port: u16,
    deadline: Deadline,
) -> io::Result<Vec<SocketAddr>> {
    if let Ok(ip) = host.parse::<IpAddr>() {
        return Ok(vec![SocketAddr::new(ip, port)]);
    }

    let (sender, receiver) = mpsc::sync_channel(1);
    thread::Builder::new()
        .name("basic-cli-tcp-resolve".to_string())
        .spawn(move || {
            let resolved = (host.as_str(), port)
                .to_socket_addrs()
                .map(|addresses| addresses.collect());
            let _ = sender.send(resolved);
        })?;

    let received = match deadline.remaining()? {
        Some(remaining) => receiver.recv_timeout(remaining),
        None => receiver
            .recv()
            .map_err(|_| mpsc::RecvTimeoutError::Disconnected),
    };
    match received {
        Ok(result) => result,
        Err(mpsc::RecvTimeoutError::Timeout) => Err(timed_out()),
        Err(mpsc::RecvTimeoutError::Disconnected) => Err(io::Error::other(
            "TCP address resolution worker stopped unexpectedly",
        )),
    }
}

fn connect(host: String, port: u16, timeout_nanos: u64) -> io::Result<TcpStream> {
    let deadline = Deadline::after_nanos(timeout_nanos)?;
    let addresses = resolve_with_deadline(host, port, deadline)?;
    let mut last_error = None;

    for address in addresses {
        let attempt = match deadline.remaining()? {
            Some(remaining) => TcpStream::connect_timeout(&address, remaining),
            None => TcpStream::connect(address),
        };
        match attempt {
            Ok(stream) => return Ok(stream),
            Err(error) => last_error = Some(normalize(error)),
        }
    }

    Err(last_error.unwrap_or_else(|| {
        io::Error::new(
            io::ErrorKind::AddrNotAvailable,
            "hostname resolved to no TCP addresses",
        )
    }))
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
pub(crate) struct Connection {
    stream: TcpStream,
    /// Received bytes. Those before `start` have been returned already.
    buffer: Vec<u8>,
    start: usize,
    /// The delimiter of an over-long record whose tail has not all arrived
    /// yet. The next read discards through it before doing anything else.
    discarding: Option<u8>,
}

impl Connection {
    pub(crate) fn new(stream: TcpStream) -> Self {
        Self {
            stream,
            buffer: Vec::new(),
            start: 0,
            discarding: None,
        }
    }

    fn available(&self) -> &[u8] {
        &self.buffer[self.start..]
    }

    fn consume(&mut self, count: usize) {
        self.start += count;
        if self.start == self.buffer.len() {
            self.buffer.clear();
            self.start = 0;
        }
    }

    fn take(&mut self, count: usize) -> Vec<u8> {
        let bytes = self.available()[..count].to_vec();
        self.consume(count);
        bytes
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
            let attempt = deadline
                .remaining()
                .and_then(|remaining| self.stream.set_read_timeout(remaining))
                .and_then(|()| (&self.stream).read(&mut self.buffer[filled..]));
            match attempt {
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                other => break other.map_err(normalize),
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
        Ok(Some(self.take(count.min(self.available().len()))))
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
        Ok(self.take(count))
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
                return Ok(Some(self.take(scanned + index + 1)));
            }
            scanned = window;
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
                return Ok((rest > 0).then(|| self.take(rest)));
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
            self.stream.set_write_timeout(deadline.remaining()?)?;
            match self.stream.write(&bytes[written..]) {
                Ok(0) => return Err(io::Error::from(io::ErrorKind::WriteZero)),
                Ok(count) => written += count,
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                Err(error) => return Err(normalize(error)),
            }
        }
        Ok(())
    }
}

/// Run `operation` on the connection behind `handle`, then drop the reference
/// the hosted call was passed. Final release closes the socket.
fn with_connection<T>(
    handle: *mut u64,
    roc_host: &RocHost,
    operation: impl FnOnce(&mut Connection) -> T,
) -> T {
    let result = operation(unsafe { crate::resources::resource_ref::<Connection>(handle) });
    crate::resources::release(handle, roc_host);
    result
}

fn bytes_ok(bytes: &[u8], roc_host: &RocHost) -> ManuallyDrop<RocListWith<u8, false>> {
    ManuallyDrop::new(roc_u8_list_from_slice(bytes, roc_host))
}

/// The result of `Tcp.connect!` or of a successful accept.
pub(crate) fn connection_result(
    stream: io::Result<TcpStream>,
    roc_host: &RocHost,
) -> io::Result<*mut u64> {
    crate::resources::box_resource(Connection::new(stream?), roc_host)
}

fn delimited_result(
    result: Result<Option<Vec<u8>>, ReadUntilError>,
    limit: u64,
    roc_host: &RocHost,
) -> HostTcpReadLineResult {
    type Error = EndOfInputOrReadLimitExceededOrTcpErr;
    type Payload = EndOfInputOrReadLimitExceededOrTcpErrPayload;
    type Tag = EndOfInputOrReadLimitExceededOrTcpErrTag;

    let error = match result {
        Ok(Some(bytes)) => {
            return HostTcpReadLineResult {
                payload: HostTcpReadLineResultPayload {
                    ok: bytes_ok(&bytes, roc_host),
                },
                tag: HostTcpReadLineResultTag::Ok,
            }
        }
        Ok(None) => Error {
            payload: Payload { end_of_input: [] },
            tag: Tag::EndOfInput,
        },
        Err(ReadUntilError::LimitExceeded) => Error {
            payload: Payload {
                read_limit_exceeded: ManuallyDrop::new(limit),
            },
            tag: Tag::ReadLimitExceeded,
        },
        Err(ReadUntilError::Io(error)) => Error {
            payload: Payload {
                tcp_err: ManuallyDrop::new(tcp_io_err(error, roc_host)),
            },
            tag: Tag::TcpErr,
        },
    };
    HostTcpReadLineResult {
        payload: HostTcpReadLineResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostTcpReadLineResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_tcp_connect(
    host: RocStr,
    port: u16,
    timeout_nanos: u64,
) -> HostTcpConnectResult {
    let roc_host = roc_host();
    let host_string = host.as_str().to_owned();
    unsafe { host.decref(roc_host) };

    match connection_result(connect(host_string, port, timeout_nanos), roc_host) {
        Ok(handle) => HostTcpConnectResult {
            payload: HostTcpConnectResultPayload {
                ok: ManuallyDrop::new(handle),
            },
            tag: HostTcpConnectResultTag::Ok,
        },
        Err(error) => HostTcpConnectResult {
            payload: HostTcpConnectResultPayload {
                err: ManuallyDrop::new(tcp_io_err(error, roc_host)),
            },
            tag: HostTcpConnectResultTag::Err,
        },
    }
}

#[no_mangle]
pub extern "C" fn hosted_tcp_read_up_to(
    handle: *mut u64,
    count: u64,
    timeout_nanos: u64,
) -> HostTcpReadUpToResult {
    let roc_host = roc_host();
    let result = with_connection(handle, roc_host, |connection| {
        connection.read_up_to(count, timeout_nanos)
    });
    let error = match result {
        Ok(Some(bytes)) => {
            return HostTcpReadUpToResult {
                payload: HostTcpReadUpToResultPayload {
                    ok: bytes_ok(&bytes, roc_host),
                },
                tag: HostTcpReadUpToResultTag::Ok,
            }
        }
        Ok(None) => EndOfInputOrTcpErr {
            payload: EndOfInputOrTcpErrPayload { end_of_input: [] },
            tag: EndOfInputOrTcpErrTag::EndOfInput,
        },
        Err(error) => EndOfInputOrTcpErr {
            payload: EndOfInputOrTcpErrPayload {
                tcp_err: ManuallyDrop::new(tcp_io_err(error, roc_host)),
            },
            tag: EndOfInputOrTcpErrTag::TcpErr,
        },
    };
    HostTcpReadUpToResult {
        payload: HostTcpReadUpToResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostTcpReadUpToResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_tcp_read_exactly(
    handle: *mut u64,
    count: u64,
    timeout_nanos: u64,
) -> HostTcpReadExactlyResult {
    let roc_host = roc_host();
    let result = with_connection(handle, roc_host, |connection| {
        connection.read_exactly(count, timeout_nanos)
    });
    let error = match result {
        Ok(bytes) => {
            return HostTcpReadExactlyResult {
                payload: HostTcpReadExactlyResultPayload {
                    ok: bytes_ok(&bytes, roc_host),
                },
                tag: HostTcpReadExactlyResultTag::Ok,
            }
        }
        Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => {
            TcpErrOrUnexpectedEndOfInput {
                payload: TcpErrOrUnexpectedEndOfInputPayload {
                    unexpected_end_of_input: [],
                },
                tag: TcpErrOrUnexpectedEndOfInputTag::UnexpectedEndOfInput,
            }
        }
        Err(error) => TcpErrOrUnexpectedEndOfInput {
            payload: TcpErrOrUnexpectedEndOfInputPayload {
                tcp_err: ManuallyDrop::new(tcp_io_err(error, roc_host)),
            },
            tag: TcpErrOrUnexpectedEndOfInputTag::TcpErr,
        },
    };
    HostTcpReadExactlyResult {
        payload: HostTcpReadExactlyResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostTcpReadExactlyResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_tcp_read_until(
    handle: *mut u64,
    delimiter: u8,
    limit: u64,
    timeout_nanos: u64,
) -> HostTcpReadLineResult {
    let roc_host = roc_host();
    let result = with_connection(handle, roc_host, |connection| {
        connection.read_until(delimiter, limit, timeout_nanos)
    });
    delimited_result(result, limit, roc_host)
}

#[no_mangle]
pub extern "C" fn hosted_tcp_read_line(
    handle: *mut u64,
    limit: u64,
    timeout_nanos: u64,
) -> HostTcpReadLineResult {
    let roc_host = roc_host();
    let result = with_connection(handle, roc_host, |connection| {
        connection.read_line(limit, timeout_nanos)
    });
    delimited_result(result, limit, roc_host)
}

#[no_mangle]
pub extern "C" fn hosted_tcp_write(
    handle: *mut u64,
    bytes: RocListWith<u8, false>,
    timeout_nanos: u64,
) -> HostTcpListenerCloseResult {
    let roc_host = roc_host();
    let result = with_connection(handle, roc_host, |connection| {
        connection.write(bytes.as_slice(), timeout_nanos)
    });
    unsafe { bytes.decref(roc_host) };
    match result {
        Ok(()) => HostTcpListenerCloseResult {
            payload: HostTcpListenerCloseResultPayload { ok: [] },
            tag: HostTcpListenerCloseResultTag::Ok,
        },
        Err(error) => HostTcpListenerCloseResult {
            payload: HostTcpListenerCloseResultPayload {
                err: ManuallyDrop::new(tcp_io_err(error, roc_host)),
            },
            tag: HostTcpListenerCloseResultTag::Err,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{Shutdown, TcpListener};

    const LONG: u64 = 10_000_000_000;
    const SHORT: u64 = 30_000_000;
    const NO_LIMIT: u64 = u64::MAX;

    /// A connection under test and the peer's end of it.
    fn pair() -> (Connection, TcpStream) {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let client = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let (peer, _) = listener.accept().unwrap();
        (Connection::new(client), peer)
    }

    fn kind<T: std::fmt::Debug>(result: io::Result<T>) -> io::ErrorKind {
        result.unwrap_err().kind()
    }

    fn until_kind(result: Result<Option<Vec<u8>>, ReadUntilError>) -> io::ErrorKind {
        match result {
            Err(ReadUntilError::Io(error)) => error.kind(),
            other => panic!("expected an I/O error, got {other:?}"),
        }
    }

    fn line(connection: &mut Connection, limit: u64) -> Option<Vec<u8>> {
        connection.read_line(limit, LONG).unwrap()
    }

    /// Time out reads until `expected` has arrived and is sitting in the buffer.
    fn time_out_until_buffered(connection: &mut Connection, expected: &[u8]) {
        for _ in 0..200 {
            assert_eq!(
                until_kind(connection.read_line(NO_LIMIT, SHORT)),
                io::ErrorKind::TimedOut
            );
            if connection.available() == expected {
                return;
            }
        }
        panic!("{expected:?} never arrived");
    }

    #[test]
    fn timed_out_reads_consume_nothing() {
        let (mut connection, mut peer) = pair();
        peer.write_all(b"par").unwrap();
        time_out_until_buffered(&mut connection, b"par");

        // Every kind of read that cannot finish leaves the bytes in place.
        assert_eq!(
            until_kind(connection.read_until(b'|', NO_LIMIT, SHORT)),
            io::ErrorKind::TimedOut
        );
        assert_eq!(
            kind(connection.read_exactly(5, SHORT)),
            io::ErrorKind::TimedOut
        );
        assert_eq!(connection.available(), b"par");

        // A zero timeout expires at once, even with data ready.
        assert_eq!(kind(connection.read_up_to(3, 0)), io::ErrorKind::TimedOut);
        assert_eq!(kind(connection.read_exactly(3, 0)), io::ErrorKind::TimedOut);
        assert_eq!(
            until_kind(connection.read_line(NO_LIMIT, 0)),
            io::ErrorKind::TimedOut
        );
        assert_eq!(
            until_kind(connection.read_until(b'r', NO_LIMIT, 0)),
            io::ErrorKind::TimedOut
        );
        assert_eq!(connection.available(), b"par");

        // The rest of the line arrives after the deadlines: nothing was lost.
        peer.write_all(b"tial\r\nnext").unwrap();
        assert_eq!(line(&mut connection, NO_LIMIT).unwrap(), b"partial");

        while connection.available() != b"next" {
            assert_eq!(
                kind(connection.read_exactly(10, SHORT)),
                io::ErrorKind::TimedOut
            );
        }
        assert_eq!(connection.read_up_to(2, LONG).unwrap().unwrap(), b"ne");
        peer.write_all(b"|").unwrap();
        assert_eq!(
            connection
                .read_until(b'|', NO_LIMIT, LONG)
                .unwrap()
                .unwrap(),
            b"xt|"
        );
        // Nothing is buffered now, so this deadline is the socket's own.
        assert_eq!(
            kind(connection.read_up_to(1, SHORT)),
            io::ErrorKind::TimedOut
        );
    }

    #[test]
    fn stalled_read_respects_the_deadline() {
        let (mut connection, _peer) = pair();
        let started = Instant::now();
        assert_eq!(
            kind(connection.read_up_to(1, SHORT)),
            io::ErrorKind::TimedOut
        );
        // A socket timeout is counted in clock ticks on Windows and can end a
        // little before its nominal length, so only half of it is required.
        let elapsed = started.elapsed();
        assert!(elapsed >= Duration::from_nanos(SHORT / 2), "{elapsed:?}");
        assert!(elapsed < Duration::from_secs(5), "{elapsed:?}");
    }

    #[test]
    fn over_long_record_is_discarded_before_the_next_read() {
        let (mut connection, mut peer) = pair();

        // The whole record is already here: it is dropped with the error.
        peer.write_all(b"0123456789\nok\n").unwrap();
        while connection.available().len() < 14 {
            let _ = connection.read_exactly(100, SHORT);
        }
        assert!(matches!(
            connection.read_line(4, LONG),
            Err(ReadUntilError::LimitExceeded)
        ));
        assert_eq!(line(&mut connection, 4).unwrap(), b"ok");

        // The record's tail has not arrived yet: the next read waits for it,
        // within its own timeout, and then returns the record after it.
        peer.write_all(b"abcdefgh").unwrap();
        assert!(matches!(
            connection.read_line(4, LONG),
            Err(ReadUntilError::LimitExceeded)
        ));
        assert_eq!(
            until_kind(connection.read_line(4, SHORT)),
            io::ErrorKind::TimedOut
        );
        peer.write_all(b"ij").unwrap();
        assert_eq!(
            kind(connection.read_up_to(8, SHORT)),
            io::ErrorKind::TimedOut
        );
        peer.write_all(b"kl\nnext\nrest").unwrap();
        assert_eq!(line(&mut connection, 5).unwrap(), b"next");

        // Any read finishes the discard, not only a delimited one, and each
        // record is discarded through the delimiter it was read with.
        assert!(matches!(
            connection.read_until(b'|', 2, LONG),
            Err(ReadUntilError::LimitExceeded)
        ));
        peer.write_all(b"\nstill the same record|AB").unwrap();
        assert_eq!(connection.read_exactly(2, LONG).unwrap(), b"AB");

        // The input may end inside the discarded record.
        peer.write_all(b"too long").unwrap();
        peer.shutdown(Shutdown::Write).unwrap();
        assert!(matches!(
            connection.read_line(3, LONG),
            Err(ReadUntilError::LimitExceeded)
        ));
        assert_eq!(line(&mut connection, 3), None);
        assert_eq!(line(&mut connection, 3), None);
    }

    #[test]
    fn limit_counts_the_delimiter_and_spares_a_final_record() {
        let (mut connection, mut peer) = pair();
        peer.write_all(b"abc\nabcd\nab|abcd").unwrap();
        peer.shutdown(Shutdown::Write).unwrap();

        assert_eq!(line(&mut connection, 4).unwrap(), b"abc");
        assert!(matches!(
            connection.read_line(4, LONG),
            Err(ReadUntilError::LimitExceeded)
        ));
        assert_eq!(
            connection.read_until(b'|', 3, LONG).unwrap().unwrap(),
            b"ab|"
        );
        // Four bytes and then the end: a record of four bytes, within the limit.
        assert_eq!(
            connection.read_until(b'|', 4, LONG).unwrap().unwrap(),
            b"abcd"
        );
        // A limit of zero admits no record, but the end is still the end.
        assert_eq!(connection.read_until(b'|', 0, LONG).unwrap(), None);
        assert_eq!(line(&mut connection, 0), None);
    }

    #[test]
    fn end_of_input_follows_the_remaining_data() {
        let (mut connection, mut peer) = pair();
        peer.write_all(b"a\r\n\nlast").unwrap();
        peer.shutdown(Shutdown::Write).unwrap();

        assert_eq!(line(&mut connection, NO_LIMIT).unwrap(), b"a");
        // An empty line is data, not the end.
        assert_eq!(line(&mut connection, NO_LIMIT).unwrap(), b"");
        // A final unterminated line is a line.
        assert_eq!(line(&mut connection, NO_LIMIT).unwrap(), b"last");
        // The end is reported by every read, and again when asked again.
        assert_eq!(line(&mut connection, NO_LIMIT), None);
        assert_eq!(line(&mut connection, NO_LIMIT), None);
        assert_eq!(connection.read_until(b'|', NO_LIMIT, LONG).unwrap(), None);
        assert_eq!(connection.read_up_to(8, LONG).unwrap(), None);
        assert_eq!(
            kind(connection.read_exactly(1, LONG)),
            io::ErrorKind::UnexpectedEof
        );
        // Asking for nothing is answered without reading.
        assert_eq!(connection.read_up_to(0, LONG).unwrap(), Some(Vec::new()));
        assert!(connection.read_exactly(0, LONG).unwrap().is_empty());
    }

    #[test]
    fn short_exact_read_leaves_the_bytes_that_arrived() {
        let (mut connection, mut peer) = pair();
        peer.write_all(b"hi").unwrap();
        peer.shutdown(Shutdown::Write).unwrap();

        assert_eq!(
            kind(connection.read_exactly(3, LONG)),
            io::ErrorKind::UnexpectedEof
        );
        assert_eq!(connection.read_up_to(8, LONG).unwrap().unwrap(), b"hi");
        assert_eq!(connection.read_up_to(8, LONG).unwrap(), None);
        assert_eq!(
            kind(connection.read_exactly(u64::MAX, LONG)),
            io::ErrorKind::OutOfMemory
        );
    }

    #[test]
    fn lines_drop_the_terminator_and_one_carriage_return() {
        let (mut connection, mut peer) = pair();
        peer.write_all(b"a\r\r\n\rb\rc\n\r\nok\n\xff\xfe\r\nx|y|\ny\r")
            .unwrap();
        peer.shutdown(Shutdown::Write).unwrap();

        // Only one `\r` is removed, and only next to the terminator.
        assert_eq!(line(&mut connection, NO_LIMIT).unwrap(), b"a\r");
        assert_eq!(line(&mut connection, NO_LIMIT).unwrap(), b"\rb\rc");
        assert_eq!(line(&mut connection, NO_LIMIT).unwrap(), b"");
        assert_eq!(line(&mut connection, NO_LIMIT).unwrap(), b"ok");
        // Bytes that are not UTF-8 are passed through for Roc to decode.
        assert_eq!(line(&mut connection, NO_LIMIT).unwrap(), b"\xff\xfe");
        // A delimited read keeps its delimiter and shares the cursor.
        assert_eq!(
            connection
                .read_until(b'|', NO_LIMIT, LONG)
                .unwrap()
                .unwrap(),
            b"x|"
        );
        assert_eq!(line(&mut connection, NO_LIMIT).unwrap(), b"y|");
        // An unterminated last line is returned as it is.
        assert_eq!(line(&mut connection, NO_LIMIT).unwrap(), b"y\r");
        assert_eq!(line(&mut connection, NO_LIMIT), None);
    }

    #[test]
    fn chunk_reads_are_non_empty_and_bounded() {
        let (mut connection, mut peer) = pair();
        let expected: Vec<u8> = (0..300_001).map(|i| i as u8).collect();
        let sent = expected.clone();
        let writer = thread::spawn(move || {
            peer.write_all(&sent).unwrap();
        });

        let mut received = Vec::new();
        while let Some(chunk) = connection.read_up_to(READ_CHUNK as u64, LONG).unwrap() {
            assert!(!chunk.is_empty() && chunk.len() <= READ_CHUNK);
            received.extend(chunk);
        }
        writer.join().unwrap();
        assert_eq!(received, expected);
    }

    #[test]
    fn exact_and_delimited_reads_cross_many_socket_reads() {
        let (mut connection, mut peer) = pair();
        let mut expected: Vec<u8> = (0..200_000).map(|i| (i % 251) as u8 + 1).collect();
        expected.push(0);
        let sent = expected.clone();
        let writer = thread::spawn(move || {
            for part in sent.chunks(7_001) {
                peer.write_all(part).unwrap();
            }
            peer
        });

        assert_eq!(
            connection.read_exactly(100_000, LONG).unwrap(),
            expected[..100_000]
        );
        assert_eq!(
            connection.read_until(0, NO_LIMIT, LONG).unwrap().unwrap(),
            expected[100_000..]
        );
        drop(writer.join().unwrap());
        assert_eq!(connection.read_up_to(1, LONG).unwrap(), None);
    }

    #[test]
    fn writes_arrive_and_a_zero_timeout_writes_nothing() {
        let (mut connection, mut peer) = pair();
        assert_eq!(kind(connection.write(b"lost", 0)), io::ErrorKind::TimedOut);
        connection.write(b"hello", LONG).unwrap();
        connection.write(b"", LONG).unwrap();
        drop(connection);

        let mut received = Vec::new();
        peer.read_to_end(&mut received).unwrap();
        assert_eq!(received, b"hello");
    }

    #[test]
    fn connect_timeout_includes_localhost_resolution() {
        // Bind through the same hostname the client resolves so both sides use
        // the platform's preferred address family (IPv6 on Windows, IPv4 on
        // some Unix hosts). Otherwise an unavailable first address can consume
        // a deliberately short deadline before the matching address is tried.
        let listener = TcpListener::bind(("localhost", 0)).unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = thread::spawn(move || {
            listener.accept().unwrap();
        });

        connect("localhost".to_string(), port, LONG).unwrap();
        server.join().unwrap();

        assert_eq!(
            kind(connect("localhost".to_string(), port, 0)),
            io::ErrorKind::TimedOut
        );
        // The longest timeout Roc can express is accepted, not an overflow.
        assert!(Deadline::after_nanos(u64::MAX).is_ok());
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn stalled_connect_respects_the_deadline() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let address = listener.local_addr().unwrap();
        let mut queued_connections = Vec::new();

        loop {
            match TcpStream::connect_timeout(&address, Duration::from_millis(10)) {
                Ok(stream) => queued_connections.push(stream),
                Err(error)
                    if matches!(
                        error.kind(),
                        io::ErrorKind::TimedOut | io::ErrorKind::WouldBlock
                    ) =>
                {
                    break;
                }
                Err(error) => panic!("could not fill the local TCP accept queue: {error}"),
            }
            assert!(queued_connections.len() < 4_096);
        }

        let started = Instant::now();
        // Whichever kind the OS reports, the host reports `TimedOut`.
        assert_eq!(
            kind(connect(address.ip().to_string(), address.port(), SHORT)),
            io::ErrorKind::TimedOut
        );
        assert!(started.elapsed() < Duration::from_secs(1));
    }

    #[test]
    fn failures_cross_as_typed_io_errors() {
        let host = crate::resources::make_host();
        let tag = |error: io::Error| tcp_io_err(error, &host).tag;

        // Nothing listens on a port that was just released.
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let port = listener.local_addr().unwrap().port();
        drop(listener);
        let refused = connect("127.0.0.1".to_string(), port, LONG).unwrap_err();
        assert_eq!(tag(refused), IOErrTag::ConnectionRefused);

        // A real socket timeout, as the OS reported it, and both spellings.
        let (mut connection, _peer) = pair();
        let stalled = connection.read_up_to(1, SHORT).unwrap_err();
        assert_eq!(tag(stalled), IOErrTag::TimedOut);
        assert_eq!(tag(io::ErrorKind::WouldBlock.into()), IOErrTag::TimedOut);
        assert_eq!(tag(io::ErrorKind::TimedOut.into()), IOErrTag::TimedOut);
        assert_eq!(
            tag(Deadline::after_nanos(0).err().unwrap()),
            IOErrTag::TimedOut
        );

        for (kind, expected) in [
            (io::ErrorKind::AddrInUse, IOErrTag::AddrInUse),
            (io::ErrorKind::AddrNotAvailable, IOErrTag::AddrNotAvailable),
            (io::ErrorKind::ConnectionReset, IOErrTag::ConnectionReset),
            (io::ErrorKind::BrokenPipe, IOErrTag::BrokenPipe),
            (io::ErrorKind::PermissionDenied, IOErrTag::PermissionDenied),
        ] {
            assert_eq!(tag(kind.into()), expected);
        }

        // Anything else keeps its message.
        let other = tcp_io_err(io::Error::other("odd failure"), &host);
        assert_eq!(other.tag, IOErrTag::Other);
        let message = unsafe { ManuallyDrop::into_inner(other.payload.other) };
        assert_eq!(message.as_str(), "odd failure");
        unsafe { message.decref(&host) };
    }
}
