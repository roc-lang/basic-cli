//! Native pathname AF_UNIX stream sockets on Unix and Windows 10 1803+.
//! The socket pathname is never removed implicitly.
use crate::roc_platform_abi::*;
use crate::socket::{Deadline, ReadUntilError};
use crate::{roc_host, roc_u8_list_from_slice};
use core::mem::ManuallyDrop;
use std::io;
use std::path::Path;

pub(crate) struct Connection(crate::socket::BufferedSocket);
impl Connection {
    fn new(socket: socket2::Socket) -> io::Result<Self> {
        crate::socket::BufferedSocket::new(socket).map(Self)
    }
}
impl std::ops::Deref for Connection {
    type Target = crate::socket::BufferedSocket;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}
impl std::ops::DerefMut for Connection {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

pub(crate) struct Listener {
    socket: Option<socket2::Socket>,
}

fn address(path: &Path) -> io::Result<socket2::SockAddr> {
    #[cfg(unix)]
    let bytes = {
        use std::os::unix::ffi::OsStrExt;
        path.as_os_str().as_bytes()
    };
    #[cfg(windows)]
    let bytes = path
        .to_str()
        .ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidInput,
                "AF_UNIX pathname must be valid UTF-8 on Windows",
            )
        })?
        .as_bytes();
    if bytes.is_empty() || bytes.contains(&0) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "AF_UNIX requires a nonempty pathname without NUL",
        ));
    }
    socket2::SockAddr::unix(path)
}

fn connect(path: &Path, nanos: u64) -> io::Result<socket2::Socket> {
    let deadline = Deadline::after_nanos(nanos)?;
    let address = address(path)?;
    let socket = socket2::Socket::new(socket2::Domain::UNIX, socket2::Type::STREAM, None)?;
    crate::socket::connect(&socket, &address, deadline)?;
    Ok(socket)
}

fn listen(path: &Path) -> io::Result<Listener> {
    crate::socket::check_interrupt()?;
    let address = address(path)?;
    let socket = socket2::Socket::new(socket2::Domain::UNIX, socket2::Type::STREAM, None)?;
    socket.bind(&address)?;
    socket.listen(128)?;
    socket.set_nonblocking(true)?;
    Ok(Listener {
        socket: Some(socket),
    })
}

fn socket_io_err(error: io::Error, host: &RocHost) -> IOErr {
    crate::tcp::tcp_io_err(error, host)
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

/// The result of `UnixSocket.connect!` or of a successful accept.
pub(crate) fn connection_result(
    stream: io::Result<socket2::Socket>,
    roc_host: &RocHost,
) -> io::Result<*mut u64> {
    crate::resources::box_resource(Connection::new(stream?)?, roc_host)
}

fn delimited_result(
    result: Result<Option<Vec<u8>>, ReadUntilError>,
    limit: u64,
    roc_host: &RocHost,
) -> HostUnixSocketReadLineResult {
    type Error = EndOfInputOrReadLimitExceededOrUnixSocketErr;
    type Payload = EndOfInputOrReadLimitExceededOrUnixSocketErrPayload;
    type Tag = EndOfInputOrReadLimitExceededOrUnixSocketErrTag;

    let error = match result {
        Ok(Some(bytes)) => {
            return HostUnixSocketReadLineResult {
                payload: HostUnixSocketReadLineResultPayload {
                    ok: bytes_ok(&bytes, roc_host),
                },
                tag: HostUnixSocketReadLineResultTag::Ok,
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
                unix_socket_err: ManuallyDrop::new(socket_io_err(error, roc_host)),
            },
            tag: Tag::UnixSocketErr,
        },
    };
    HostUnixSocketReadLineResult {
        payload: HostUnixSocketReadLineResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostUnixSocketReadLineResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_unix_socket_connect(
    path: UnixBytesOrUtf8OrWindowsU16s,
    timeout_nanos: u64,
) -> HostUnixSocketConnectResult {
    let host = roc_host();
    let connected =
        crate::path_from_native(path, host).and_then(|path| connect(&path, timeout_nanos));
    match connection_result(connected, host) {
        Ok(handle) => HostUnixSocketConnectResult {
            tag: HostUnixSocketConnectResultTag::Ok,
            payload: HostUnixSocketConnectResultPayload {
                ok: ManuallyDrop::new(handle),
            },
        },
        Err(error) => HostUnixSocketConnectResult {
            tag: HostUnixSocketConnectResultTag::Err,
            payload: HostUnixSocketConnectResultPayload {
                err: ManuallyDrop::new(socket_io_err(error, host)),
            },
        },
    }
}

#[no_mangle]
pub extern "C" fn hosted_unix_socket_read_up_to(
    handle: *mut u64,
    count: u64,
    timeout_nanos: u64,
) -> HostUnixSocketReadUpToResult {
    let roc_host = roc_host();
    let result = with_connection(handle, roc_host, |connection| {
        connection.read_up_to(count, timeout_nanos)
    });
    let error = match result {
        Ok(Some(bytes)) => {
            return HostUnixSocketReadUpToResult {
                payload: HostUnixSocketReadUpToResultPayload {
                    ok: bytes_ok(&bytes, roc_host),
                },
                tag: HostUnixSocketReadUpToResultTag::Ok,
            }
        }
        Ok(None) => EndOfInputOrUnixSocketErr {
            payload: EndOfInputOrUnixSocketErrPayload { end_of_input: [] },
            tag: EndOfInputOrUnixSocketErrTag::EndOfInput,
        },
        Err(error) => EndOfInputOrUnixSocketErr {
            payload: EndOfInputOrUnixSocketErrPayload {
                unix_socket_err: ManuallyDrop::new(socket_io_err(error, roc_host)),
            },
            tag: EndOfInputOrUnixSocketErrTag::UnixSocketErr,
        },
    };
    HostUnixSocketReadUpToResult {
        payload: HostUnixSocketReadUpToResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostUnixSocketReadUpToResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_unix_socket_read_exactly(
    handle: *mut u64,
    count: u64,
    timeout_nanos: u64,
) -> HostUnixSocketReadExactlyResult {
    let roc_host = roc_host();
    let result = with_connection(handle, roc_host, |connection| {
        connection.read_exactly(count, timeout_nanos)
    });
    let error = match result {
        Ok(bytes) => {
            return HostUnixSocketReadExactlyResult {
                payload: HostUnixSocketReadExactlyResultPayload {
                    ok: bytes_ok(&bytes, roc_host),
                },
                tag: HostUnixSocketReadExactlyResultTag::Ok,
            }
        }
        Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => {
            UnexpectedEndOfInputOrUnixSocketErr {
                payload: UnexpectedEndOfInputOrUnixSocketErrPayload {
                    unexpected_end_of_input: [],
                },
                tag: UnexpectedEndOfInputOrUnixSocketErrTag::UnexpectedEndOfInput,
            }
        }
        Err(error) => UnexpectedEndOfInputOrUnixSocketErr {
            payload: UnexpectedEndOfInputOrUnixSocketErrPayload {
                unix_socket_err: ManuallyDrop::new(socket_io_err(error, roc_host)),
            },
            tag: UnexpectedEndOfInputOrUnixSocketErrTag::UnixSocketErr,
        },
    };
    HostUnixSocketReadExactlyResult {
        payload: HostUnixSocketReadExactlyResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostUnixSocketReadExactlyResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_unix_socket_read_until(
    handle: *mut u64,
    delimiter: u8,
    limit: u64,
    timeout_nanos: u64,
) -> HostUnixSocketReadLineResult {
    let roc_host = roc_host();
    let result = with_connection(handle, roc_host, |connection| {
        connection.read_until(delimiter, limit, timeout_nanos)
    });
    delimited_result(result, limit, roc_host)
}

#[no_mangle]
pub extern "C" fn hosted_unix_socket_read_line(
    handle: *mut u64,
    limit: u64,
    timeout_nanos: u64,
) -> HostUnixSocketReadLineResult {
    let roc_host = roc_host();
    let result = with_connection(handle, roc_host, |connection| {
        connection.read_line(limit, timeout_nanos)
    });
    delimited_result(result, limit, roc_host)
}

#[no_mangle]
pub extern "C" fn hosted_unix_socket_write(
    handle: *mut u64,
    bytes: RocListWith<u8, false>,
    timeout_nanos: u64,
) -> HostUnixSocketListenerCloseResult {
    let roc_host = roc_host();
    let result = with_connection(handle, roc_host, |connection| {
        connection.write(bytes.as_slice(), timeout_nanos)
    });
    unsafe { bytes.decref(roc_host) };
    match result {
        Ok(()) => HostUnixSocketListenerCloseResult {
            payload: HostUnixSocketListenerCloseResultPayload { ok: [] },
            tag: HostUnixSocketListenerCloseResultTag::Ok,
        },
        Err(error) => HostUnixSocketListenerCloseResult {
            payload: HostUnixSocketListenerCloseResultPayload {
                err: ManuallyDrop::new(socket_io_err(error, roc_host)),
            },
            tag: HostUnixSocketListenerCloseResultTag::Err,
        },
    }
}

#[no_mangle]
pub extern "C" fn hosted_unix_socket_listen(
    path: UnixBytesOrUtf8OrWindowsU16s,
) -> HostUnixSocketListenResult {
    let host = roc_host();
    match crate::path_from_native(path, host)
        .and_then(|path| listen(&path))
        .and_then(|listener| crate::resources::box_resource(listener, host))
    {
        Ok(handle) => HostUnixSocketListenResult {
            tag: HostUnixSocketListenResultTag::Ok,
            payload: HostUnixSocketListenResultPayload {
                ok: ManuallyDrop::new(handle),
            },
        },
        Err(error) => HostUnixSocketListenResult {
            tag: HostUnixSocketListenResultTag::Err,
            payload: HostUnixSocketListenResultPayload {
                err: ManuallyDrop::new(socket_io_err(error, host)),
            },
        },
    }
}

#[no_mangle]
pub extern "C" fn hosted_unix_socket_accept(
    handle: *mut u64,
    wait: AfterOrNoTimeout,
) -> HostUnixSocketAcceptResult {
    let host = roc_host();
    let listener = unsafe { crate::resources::resource_ref::<Listener>(handle) };
    let wait = match wait.tag {
        AfterOrNoTimeoutTag::After => Some(unsafe { *wait.payload.after }),
        AfterOrNoTimeoutTag::NoTimeout => None,
    };
    let accepted = (|| {
        let socket = listener.socket.as_ref().ok_or(None)?;
        let deadline = Deadline::for_wait(wait).map_err(Some)?;
        loop {
            deadline.remaining().map_err(Some)?;
            match socket.accept() {
                Ok((stream, _)) => return connection_result(Ok(stream), host).map_err(Some),
                Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                    crate::socket::wait_ready(socket, false, deadline).map_err(Some)?
                }
                Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
                Err(error) => return Err(Some(error)),
            }
        }
    })();
    crate::resources::release(handle, host);
    match accepted {
        Ok(handle) => HostUnixSocketAcceptResult {
            tag: HostUnixSocketAcceptResultTag::Ok,
            payload: HostUnixSocketAcceptResultPayload {
                ok: ManuallyDrop::new(handle),
            },
        },
        Err(error) => {
            let error = match error {
                None => ClosedOrUnixSocketErr {
                    tag: ClosedOrUnixSocketErrTag::Closed,
                    payload: ClosedOrUnixSocketErrPayload { closed: [] },
                },
                Some(error) => ClosedOrUnixSocketErr {
                    tag: ClosedOrUnixSocketErrTag::UnixSocketErr,
                    payload: ClosedOrUnixSocketErrPayload {
                        unix_socket_err: ManuallyDrop::new(socket_io_err(error, host)),
                    },
                },
            };
            HostUnixSocketAcceptResult {
                tag: HostUnixSocketAcceptResultTag::Err,
                payload: HostUnixSocketAcceptResultPayload {
                    err: ManuallyDrop::new(error),
                },
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn hosted_unix_socket_listener_close(
    handle: *mut u64,
) -> HostUnixSocketListenerCloseResult {
    let host = roc_host();
    unsafe { crate::resources::resource_ref::<Listener>(handle) }
        .socket
        .take();
    crate::resources::release(handle, host);
    HostUnixSocketListenerCloseResult {
        tag: HostUnixSocketListenerCloseResultTag::Ok,
        payload: HostUnixSocketListenerCloseResultPayload { ok: [] },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    const LONG: u64 = 5_000_000_000;

    #[cfg(target_os = "linux")]
    #[test]
    fn a_full_backlog_times_out_then_retries_until_a_connection_is_established() {
        let directory = tempfile::Builder::new().prefix("roc-").tempdir().unwrap();
        let path = directory.path().join("s");
        let listener =
            socket2::Socket::new(socket2::Domain::UNIX, socket2::Type::STREAM, None).unwrap();
        listener.bind(&address(&path).unwrap()).unwrap();
        // Linux allows one queued connection with backlog zero.
        listener.listen(0).unwrap();
        let _queued = connect(&path, LONG).unwrap();
        let probe =
            socket2::Socket::new(socket2::Domain::UNIX, socket2::Type::STREAM, None).unwrap();
        probe.set_nonblocking(true).unwrap();
        assert_eq!(
            probe.connect(&address(&path).unwrap()).unwrap_err().kind(),
            io::ErrorKind::WouldBlock
        );
        assert_eq!(
            connect(&path, 20_000_000).unwrap_err().kind(),
            io::ErrorKind::TimedOut
        );

        let server = std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(30));
            // Free the backlog slot while the next connect is retrying.
            let (_first, _) = listener.accept().unwrap();
            let (mut peer, _) = listener.accept().unwrap();
            peer.set_read_timeout(Some(std::time::Duration::from_secs(5)))
                .unwrap();
            let mut byte = [0];
            peer.read_exact(&mut byte).unwrap();
            assert_eq!(byte, [42]);
        });
        let mut connected = Connection::new(connect(&path, LONG).unwrap()).unwrap();
        connected.write(&[42], LONG).unwrap();
        server.join().unwrap();
    }

    #[test]
    fn pathname_roundtrip_preserves_buffer_and_requires_explicit_cleanup() {
        let directory = tempfile::Builder::new().prefix("roc-").tempdir().unwrap();
        let path = directory.path().join("s");
        let mut listener = listen(&path).unwrap();
        assert!(listen(&path).is_err());
        let socket = connect(&path, LONG).unwrap();
        let listening = listener.socket.as_ref().unwrap();
        crate::socket::wait_ready(listening, false, Deadline::after_nanos(LONG).unwrap()).unwrap();
        let (peer, _) = listening.accept().unwrap();
        peer.set_nonblocking(false).unwrap();
        let mut peer = peer;
        let mut connection = Connection::new(socket).unwrap();
        peer.write_all(b"par").unwrap();
        assert!(
            matches!(connection.read_line(1024, 20_000_000), Err(ReadUntilError::Io(error)) if error.kind() == io::ErrorKind::TimedOut)
        );
        peer.write_all(b"tial\r\nnext").unwrap();
        assert_eq!(
            connection.read_line(1024, LONG).unwrap(),
            Some(b"partial".to_vec())
        );
        assert_eq!(connection.read_exactly(4, LONG).unwrap(), b"next");
        connection.write(b"reply", LONG).unwrap();
        let mut bytes = [0; 5];
        peer.read_exact(&mut bytes).unwrap();
        assert_eq!(&bytes, b"reply");
        drop((connection, peer));
        listener.socket.take();
        assert!(path.exists());
        assert!(listen(&path).is_err());
        std::fs::remove_file(&path).unwrap();
        assert!(listen(&path).is_ok());
    }

    #[test]
    fn invalid_and_missing_pathnames_fail_without_removing_files() {
        assert!(address(Path::new("")).is_err());
        assert!(address(Path::new("a\0b")).is_err());
        let directory = tempfile::Builder::new().prefix("roc-").tempdir().unwrap();
        let path = directory.path().join("s");
        assert!(connect(&path, LONG).is_err());
        std::fs::write(&path, b"keep").unwrap();
        assert!(listen(&path).is_err());
        assert_eq!(std::fs::read(&path).unwrap(), b"keep");
    }

    #[cfg(unix)]
    #[test]
    fn pathname_preserves_native_non_utf8_bytes() {
        use std::os::unix::ffi::OsStringExt;
        let directory = tempfile::Builder::new().prefix("roc-").tempdir().unwrap();
        let path = directory
            .path()
            .join(std::ffi::OsString::from_vec(vec![b's', 255]));
        assert_eq!(address(&path).unwrap().as_pathname(), Some(path.as_path()));
        // Linux accepts this byte sequence as a filesystem name. Filesystems
        // on other Unix targets may reject it (for example APFS with EILSEQ).
        #[cfg(target_os = "linux")]
        {
            let listener = listen(&path).unwrap();
            let connected = connect(&path, LONG).unwrap();
            drop((connected, listener));
            std::fs::remove_file(path).unwrap();
        }
    }
}
