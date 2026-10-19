//! Deadline-aware listeners using a host-thread reactor.
use crate::tcp::Deadline;
use crate::{resources, roc_host, roc_platform_abi::*};
use std::{io, mem::ManuallyDrop, net::TcpStream};

pub(crate) struct Listener {
    socket: Option<socket2::Socket>,
}

/// Why a listener operation produced no value.
#[derive(Debug)]
enum ListenerError {
    /// `Tcp.Listener.close!` already released the socket.
    Closed,
    Io(io::Error),
}

impl From<io::Error> for ListenerError {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

fn listen(host: String, port: u16, timeout_nanos: u64) -> io::Result<Listener> {
    let deadline = Deadline::after_nanos(timeout_nanos)?;
    let addresses = crate::tcp::resolve_with_deadline(host, port, deadline)?;
    let mut error = io::Error::from(io::ErrorKind::AddrNotAvailable);
    for address in addresses {
        deadline.remaining()?;
        let result = (|| {
            let socket = socket2::Socket::new(
                socket2::Domain::for_address(address),
                socket2::Type::STREAM,
                Some(socket2::Protocol::TCP),
            )?;
            #[cfg(windows)]
            exclusive_address(&socket)?;
            socket.bind(&address.into())?;
            socket.listen(128)?;
            socket.set_nonblocking(true)?;
            Ok(Listener {
                socket: Some(socket),
            })
        })();
        match result {
            Ok(listener) => return Ok(listener),
            Err(e) => error = e,
        }
    }
    Err(error)
}

#[cfg(windows)]
fn exclusive_address(socket: &socket2::Socket) -> io::Result<()> {
    use std::os::windows::io::AsRawSocket;
    use windows_sys::Win32::Networking::WinSock::{
        setsockopt, WSAGetLastError, SOL_SOCKET, SO_EXCLUSIVEADDRUSE,
    };
    let enabled: i32 = 1;
    let result = unsafe {
        setsockopt(
            socket.as_raw_socket() as _,
            SOL_SOCKET,
            SO_EXCLUSIVEADDRUSE,
            (&enabled as *const i32).cast(),
            size_of::<i32>() as i32,
        )
    };
    if result == 0 {
        Ok(())
    } else {
        Err(io::Error::from_raw_os_error(unsafe { WSAGetLastError() }))
    }
}

impl Listener {
    fn socket(&self) -> Result<&socket2::Socket, ListenerError> {
        self.socket.as_ref().ok_or(ListenerError::Closed)
    }

    /// Wait for a connection: for `Some(nanos)`, or indefinitely for `None`.
    /// The wait bounds this call only; the accepted socket has no timeout of
    /// its own until a read or write sets one.
    fn accept(&self, wait_nanos: Option<u64>) -> Result<TcpStream, ListenerError> {
        let socket = self.socket()?;
        let deadline = Deadline::for_wait(wait_nanos)?;
        loop {
            deadline.remaining()?;
            match socket.accept() {
                Ok((stream, _)) => return Ok(stream.into()),
                Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                    crate::socket::wait_ready(socket, false, deadline)?
                }
                Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
                Err(error) => return Err(error.into()),
            }
        }
    }
}

fn closed_or_tcp_err(error: ListenerError, host: &RocHost) -> ClosedOrTcpErr {
    match error {
        ListenerError::Closed => ClosedOrTcpErr {
            tag: ClosedOrTcpErrTag::Closed,
            payload: ClosedOrTcpErrPayload { closed: [] },
        },
        ListenerError::Io(error) => ClosedOrTcpErr {
            tag: ClosedOrTcpErrTag::TcpErr,
            payload: ClosedOrTcpErrPayload {
                tcp_err: ManuallyDrop::new(crate::tcp::tcp_io_err(error, host)),
            },
        },
    }
}

#[no_mangle]
pub extern "C" fn hosted_tcp_listen(
    host: RocStr,
    port: u16,
    timeout_nanos: u64,
) -> HostTcpListenResult {
    let roc_host = roc_host();
    let name = host.as_str().to_owned();
    unsafe { host.decref(roc_host) };
    match listen(name, port, timeout_nanos)
        .and_then(|listener| resources::box_resource(listener, roc_host))
    {
        Ok(handle) => HostTcpListenResult {
            tag: HostTcpListenResultTag::Ok,
            payload: HostTcpListenResultPayload {
                ok: ManuallyDrop::new(handle),
            },
        },
        Err(error) => HostTcpListenResult {
            tag: HostTcpListenResultTag::Err,
            payload: HostTcpListenResultPayload {
                err: ManuallyDrop::new(crate::tcp::tcp_io_err(error, roc_host)),
            },
        },
    }
}

#[no_mangle]
pub extern "C" fn hosted_tcp_local_port(handle: *mut u64) -> HostTcpLocalPortResult {
    let host = roc_host();
    let listener = unsafe { resources::resource_ref::<Listener>(handle) };
    let port = listener.socket().and_then(|socket| {
        Ok(socket
            .local_addr()?
            .as_socket()
            .ok_or_else(|| io::Error::other("listener has no IP address"))?
            .port())
    });
    let result = match port {
        Ok(port) => HostTcpLocalPortResult {
            tag: HostTcpLocalPortResultTag::Ok,
            payload: HostTcpLocalPortResultPayload {
                ok: ManuallyDrop::new(port),
            },
        },
        Err(error) => HostTcpLocalPortResult {
            tag: HostTcpLocalPortResultTag::Err,
            payload: HostTcpLocalPortResultPayload {
                err: ManuallyDrop::new(closed_or_tcp_err(error, host)),
            },
        },
    };
    resources::release(handle, host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_tcp_accept(
    handle: *mut u64,
    wait: AfterOrNoTimeout,
) -> HostTcpAcceptResult {
    let host = roc_host();
    let wait_nanos = match wait.tag {
        AfterOrNoTimeoutTag::After => Some(unsafe { *wait.payload.after }),
        AfterOrNoTimeoutTag::NoTimeout => None,
    };
    let listener = unsafe { resources::resource_ref::<Listener>(handle) };
    let connection = listener.accept(wait_nanos).and_then(|stream| {
        crate::tcp::connection_result(Ok(stream), host).map_err(ListenerError::Io)
    });
    let result = match connection {
        Ok(connection) => HostTcpAcceptResult {
            tag: HostTcpAcceptResultTag::Ok,
            payload: HostTcpAcceptResultPayload {
                ok: ManuallyDrop::new(connection),
            },
        },
        Err(error) => HostTcpAcceptResult {
            tag: HostTcpAcceptResultTag::Err,
            payload: HostTcpAcceptResultPayload {
                err: ManuallyDrop::new(closed_or_tcp_err(error, host)),
            },
        },
    };
    resources::release(handle, host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_tcp_listener_close(handle: *mut u64) -> HostTcpListenerCloseResult {
    let host = roc_host();
    let listener = unsafe { resources::resource_ref::<Listener>(handle) };
    listener.socket.take();
    resources::release(handle, host);
    HostTcpListenerCloseResult {
        tag: HostTcpListenerCloseResultTag::Ok,
        payload: HostTcpListenerCloseResultPayload { ok: [] },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;
    use std::time::Duration;

    const LONG: u64 = 10_000_000_000;
    const SHORT: u64 = 20_000_000;

    fn timed_out(result: Result<TcpStream, ListenerError>) -> bool {
        matches!(result, Err(ListenerError::Io(error)) if error.kind() == io::ErrorKind::TimedOut)
    }

    #[test]
    fn reserved_port_accept_deadline_and_close() {
        let mut listener = listen("127.0.0.1".into(), 0, LONG).unwrap();
        let address = listener
            .socket()
            .unwrap()
            .local_addr()
            .unwrap()
            .as_socket()
            .unwrap();
        assert_ne!(address.port(), 0);
        assert!(TcpListener::bind(address).is_err());
        assert!(timed_out(listener.accept(Some(SHORT))));
        assert!(timed_out(listener.accept(Some(0))));
        // A timed-out accept leaves the listener accepting.
        let client = TcpStream::connect(address).unwrap();
        let server = listener.accept(Some(LONG)).unwrap();
        // A zero wait expires even when a client is already queued.
        let second_client = TcpStream::connect(address).unwrap();
        assert!(timed_out(listener.accept(Some(0))));
        let second_server = listener.accept(None).unwrap();
        // The accept wait is not left on the connection as a socket timeout.
        assert_eq!(server.read_timeout().unwrap(), None);
        assert_eq!(second_server.write_timeout().unwrap(), None);
        drop((client, server, second_client, second_server));
        listener.socket.take();
        assert!(matches!(
            listener.accept(Some(LONG)),
            Err(ListenerError::Closed)
        ));
        assert!(matches!(listener.accept(None), Err(ListenerError::Closed)));
        assert!(matches!(listener.socket(), Err(ListenerError::Closed)));
    }

    #[test]
    fn accept_without_a_timeout_waits_for_a_client() {
        let listener = listen("127.0.0.1".into(), 0, LONG).unwrap();
        let address = listener
            .socket()
            .unwrap()
            .local_addr()
            .unwrap()
            .as_socket()
            .unwrap();
        let client = std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(100));
            TcpStream::connect(address).unwrap()
        });
        let started = std::time::Instant::now();
        let server = listener.accept(None).unwrap();
        assert!(started.elapsed() >= Duration::from_millis(50));
        drop((server, client.join().unwrap()));
    }

    #[test]
    fn listen_failures_are_typed() {
        let host = resources::make_host();
        assert_eq!(
            listen("127.0.0.1".into(), 0, 0).err().unwrap().kind(),
            io::ErrorKind::TimedOut
        );
        let listener = listen("127.0.0.1".into(), 0, LONG).unwrap();
        let port = listener
            .socket()
            .unwrap()
            .local_addr()
            .unwrap()
            .as_socket()
            .unwrap()
            .port();
        let Err(in_use) = listen("127.0.0.1".into(), port, LONG) else {
            panic!("a bound port was bound again");
        };
        assert_eq!(in_use.kind(), io::ErrorKind::AddrInUse);
        assert_eq!(
            crate::tcp::tcp_io_err(in_use, &host).tag,
            IOErrTag::AddrInUse
        );
        let closed = closed_or_tcp_err(ListenerError::Closed, &host);
        assert_eq!(closed.tag, ClosedOrTcpErrTag::Closed);
        let timed_out = closed_or_tcp_err(listener.accept(Some(0)).unwrap_err(), &host);
        assert_eq!(timed_out.tag, ClosedOrTcpErrTag::TcpErr);
        assert_eq!(unsafe { timed_out.payload.tcp_err.tag }, IOErrTag::TimedOut);
    }

    #[test]
    fn final_arc_release_releases_port() {
        let host = resources::make_host();
        let listener = listen("127.0.0.1".into(), 0, LONG).unwrap();
        let address = listener
            .socket()
            .unwrap()
            .local_addr()
            .unwrap()
            .as_socket()
            .unwrap();
        let handle = resources::box_resource(listener, &host).unwrap();
        unsafe { incref_box(handle.cast(), 1) };
        resources::release(handle, &host);
        assert!(TcpListener::bind(address).is_err());
        resources::release(handle, &host);
        assert!(TcpListener::bind(address).is_ok());
    }
}
