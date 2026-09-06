//! Deadline-aware listeners using a host-thread reactor.
use crate::{roc_host, resources, roc_platform_abi::*};
use std::{io, mem::ManuallyDrop, net::{TcpListener, TcpStream}, time::Duration};

thread_local! {
    static RUNTIME: tokio::runtime::Runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all().build().expect("TCP listener runtime");
}
struct Listener { socket: Option<tokio::net::TcpListener> }

fn listen(host: String, port: u16, timeout_ms: u64) -> io::Result<Listener> {
    let deadline = crate::tcp::deadline_from_timeout(timeout_ms)?;
    let addresses = crate::tcp::resolve_with_deadline(host, port, deadline)?;
    let mut error = io::Error::from(io::ErrorKind::AddrNotAvailable);
    for address in addresses {
        crate::tcp::remaining_time(deadline)?;
        let result = (|| {
            let socket = socket2::Socket::new(socket2::Domain::for_address(address), socket2::Type::STREAM, Some(socket2::Protocol::TCP))?;
            #[cfg(windows)] exclusive_address(&socket)?;
            socket.bind(&address.into())?;
            socket.listen(128)?;
            socket.set_nonblocking(true)?;
            RUNTIME.with(|runtime| {
                let _entered = runtime.enter();
                tokio::net::TcpListener::from_std(TcpListener::from(socket))
                    .map(|socket| Listener { socket: Some(socket) })
            })
        })();
        match result { Ok(listener) => return Ok(listener), Err(e) => error = e }
    }
    Err(error)
}

#[cfg(windows)]
fn exclusive_address(socket: &socket2::Socket) -> io::Result<()> {
    use std::os::windows::io::AsRawSocket;
    use windows_sys::Win32::Networking::WinSock::{setsockopt, WSAGetLastError, SOL_SOCKET, SO_EXCLUSIVEADDRUSE};
    let enabled: i32 = 1;
    let result = unsafe { setsockopt(socket.as_raw_socket() as _, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, (&enabled as *const i32).cast(), size_of::<i32>() as i32) };
    if result == 0 { Ok(()) } else { Err(io::Error::from_raw_os_error(unsafe { WSAGetLastError() })) }
}

impl Listener {
    fn socket(&self) -> io::Result<&tokio::net::TcpListener> {
        self.socket.as_ref().ok_or_else(|| io::Error::new(io::ErrorKind::NotConnected, "ListenerClosed"))
    }
    fn accept(&self, timeout_ms: u64) -> io::Result<TcpStream> {
        crate::tcp::deadline_from_timeout(timeout_ms)?;
        let socket = self.socket()?;
        RUNTIME.with(|runtime| runtime.block_on(async {
            let (stream, _) = tokio::time::timeout(Duration::from_millis(timeout_ms), socket.accept()).await
                .map_err(|_| io::Error::from(io::ErrorKind::TimedOut))??;
            let stream = stream.into_std()?;
            stream.set_nonblocking(false)?;
            Ok(stream)
        }))
    }
}

fn error_string(error: io::Error, host: &RocHost) -> RocStr {
    if error.kind() == io::ErrorKind::NotConnected {
        RocStr::from_str("ListenerClosed", host)
    } else { crate::tcp::to_tcp_connect_err(error, host) }
}

#[no_mangle]
pub extern "C" fn hosted_tcp_listen(host: RocStr, port: u16, timeout_ms: u64) -> HostTcpListenResult {
    let roc_host = roc_host();
    let name = host.as_str().to_owned();
    unsafe { host.decref(roc_host) };
    match listen(name, port, timeout_ms) {
        Ok(listener) => HostTcpListenResult { tag: HostTcpListenResultTag::Ok, payload: HostTcpListenResultPayload { ok: ManuallyDrop::new(resources::box_resource(listener, roc_host)) } },
        Err(error) => HostTcpListenResult { tag: HostTcpListenResultTag::Err, payload: HostTcpListenResultPayload { err: ManuallyDrop::new(error_string(error, roc_host)) } },
    }
}

#[no_mangle]
pub extern "C" fn hosted_tcp_local_port(handle: *mut u64) -> HostTcpLocalPortResult {
    let host = roc_host();
    let listener = unsafe { resources::resource_ref::<Listener>(handle) };
    let result = match listener.socket().and_then(|socket| socket.local_addr()) {
        Ok(address) => HostTcpLocalPortResult { tag: HostTcpLocalPortResultTag::Ok, payload: HostTcpLocalPortResultPayload { ok: ManuallyDrop::new(address.port()) } },
        Err(error) => HostTcpLocalPortResult { tag: HostTcpLocalPortResultTag::Err, payload: HostTcpLocalPortResultPayload { err: ManuallyDrop::new(error_string(error, host)) } },
    };
    resources::release(handle, host);
    result
}

#[no_mangle]
pub extern "C" fn hosted_tcp_accept(handle: *mut u64, timeout_ms: u64) -> HostTcpAcceptResult {
    let host = roc_host();
    let listener = unsafe { resources::resource_ref::<Listener>(handle) };
    let result = match listener.accept(timeout_ms) {
        Ok(stream) => HostTcpAcceptResult { tag: HostTcpAcceptResultTag::Ok, payload: HostTcpAcceptResultPayload { ok: ManuallyDrop::new(crate::tcp::box_tcp_stream(std::io::BufReader::new(stream), host)) } },
        Err(error) => HostTcpAcceptResult { tag: HostTcpAcceptResultTag::Err, payload: HostTcpAcceptResultPayload { err: ManuallyDrop::new(error_string(error, host)) } },
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
    HostTcpListenerCloseResult { tag: HostTcpListenerCloseResultTag::Ok, payload: HostTcpListenerCloseResultPayload { ok: [] } }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reserved_port_accept_deadline_and_close() {
        let mut listener = listen("127.0.0.1".into(), 0, 1000).unwrap();
        let address = listener.socket().unwrap().local_addr().unwrap();
        assert_ne!(address.port(), 0);
        assert!(TcpListener::bind(address).is_err());
        assert_eq!(listener.accept(10).unwrap_err().kind(), io::ErrorKind::TimedOut);
        assert_eq!(listener.accept(0).unwrap_err().kind(), io::ErrorKind::TimedOut);
        let client = TcpStream::connect(address).unwrap();
        let server = listener.accept(1000).unwrap();
        drop(client); drop(server);
        listener.socket.take();
        assert_eq!(listener.accept(1000).unwrap_err().kind(), io::ErrorKind::NotConnected);
    }
    #[test]
    fn final_arc_release_releases_port() {
        let host = resources::make_host();
        let listener = listen("127.0.0.1".into(), 0, 1000).unwrap();
        let address = listener.socket().unwrap().local_addr().unwrap();
        let handle = resources::box_resource(listener, &host);
        unsafe { incref_box(handle.cast(), 1) };
        resources::release(handle, &host);
        assert!(TcpListener::bind(address).is_err());
        resources::release(handle, &host);
        assert!(TcpListener::bind(address).is_ok());
    }
}
