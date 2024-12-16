//! This crate provides common functionality for Roc to interface with `std::net::tcp`
use roc_std::{roc_refcounted_noop_impl, RocBox, RocList, RocRefcounted, RocResult, RocStr};
use roc_std_heap::ThreadSafeRefcountedResourceHeap;
use std::env;
use std::io::{BufRead, BufReader, ErrorKind, Read, Write};
use std::net::TcpStream;
use std::sync::OnceLock;

pub fn heap() -> &'static ThreadSafeRefcountedResourceHeap<BufReader<TcpStream>> {
    // TODO: Should this be a BufReader and BufWriter of the tcp stream?
    // like this: https://stackoverflow.com/questions/58467659/how-to-store-tcpstream-with-bufreader-and-bufwriter-in-a-data-structure/58491889#58491889

    static TCP_HEAP: OnceLock<ThreadSafeRefcountedResourceHeap<BufReader<TcpStream>>> =
        OnceLock::new();
    TCP_HEAP.get_or_init(|| {
        let default_max = 65536;
        let max_tcp_streams = env::var("ROC_BASIC_CLI_MAX_TCP_STREAMS")
            .map(|v| v.parse().unwrap_or(default_max))
            .unwrap_or(default_max);
        ThreadSafeRefcountedResourceHeap::new(max_tcp_streams)
            .expect("Failed to allocate mmap for tcp handle references.")
    })
}

const UNEXPECTED_EOF_ERROR: &str = "UnexpectedEof";

#[derive(Clone, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct RequestToAndFromHost {
    pub body: RocList<u8>,
    pub headers: RocList<Header>,
    pub method_ext: RocStr,
    pub timeout_ms: u64,
    pub uri: RocStr,
    pub method: MethodTag,
}

impl RocRefcounted for RequestToAndFromHost {
    fn inc(&mut self) {
        self.body.inc();
        self.headers.inc();
        self.method_ext.inc();
        self.uri.inc();
    }
    fn dec(&mut self) {
        self.body.dec();
        self.headers.dec();
        self.method_ext.dec();
        self.uri.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

impl From<hyper::Request<String>> for RequestToAndFromHost {
    fn from(hyper_req: hyper::Request<String>) -> RequestToAndFromHost {
        let body = RocList::from(hyper_req.body().as_bytes());
        let headers = RocList::from_iter(hyper_req.headers().iter().map(|(key, value)| {
            Header::new(
                RocStr::from(key.as_str()),
                RocStr::from(value.to_str().unwrap()),
            )
        }));
        let method = hyper_req.method().into();
        let method_ext = {
            if method == MethodTag::Extension {
                RocStr::from(hyper_req.method().as_str())
            } else {
                RocStr::empty()
            }
        };
        let timeout_ms = 0; // request is from server... roc hasn't got a timeout
        let uri = hyper_req.uri().to_string().as_str().into();

        RequestToAndFromHost {
            body,
            headers,
            method,
            method_ext,
            timeout_ms,
            uri,
        }
    }
}

impl RequestToAndFromHost {
    pub fn has_timeout(&self) -> Option<u64> {
        if self.timeout_ms > 0 {
            Some(self.timeout_ms)
        } else {
            None
        }
    }

    pub fn to_hyper_request(&self) -> Result<hyper::Request<String>, hyper::http::Error> {
        let method: hyper::Method = match self.method {
            MethodTag::Connect => hyper::Method::CONNECT,
            MethodTag::Delete => hyper::Method::DELETE,
            MethodTag::Get => hyper::Method::GET,
            MethodTag::Head => hyper::Method::HEAD,
            MethodTag::Options => hyper::Method::OPTIONS,
            MethodTag::Patch => hyper::Method::PATCH,
            MethodTag::Post => hyper::Method::POST,
            MethodTag::Put => hyper::Method::PUT,
            MethodTag::Trace => hyper::Method::TRACE,
            MethodTag::Extension => hyper::Method::from_bytes(self.method_ext.as_bytes()).unwrap(),
        };

        let mut req_builder = hyper::Request::builder()
            .method(method)
            .uri(self.uri.as_str());

        // we will give a default content type if the user hasn't
        // set one in the provided headers
        let mut has_content_type_header = false;

        for header in self.headers.iter() {
            req_builder = req_builder.header(header.name.as_str(), header.value.as_str());
            if header.name.eq_ignore_ascii_case("Content-Type") {
                has_content_type_header = true;
            }
        }

        if !has_content_type_header {
            req_builder = req_builder.header("Content-Type", "text/plain");
        }

        let bytes = String::from_utf8(self.body.as_slice().to_vec()).unwrap();

        req_builder.body(bytes)
    }
}

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum MethodTag {
    Connect = 0,
    Delete = 1,
    Extension = 2,
    Get = 3,
    Head = 4,
    Options = 5,
    Patch = 6,
    Post = 7,
    Put = 8,
    Trace = 9,
}

impl From<&hyper::Method> for MethodTag {
    fn from(method: &hyper::Method) -> Self {
        match *method {
            hyper::Method::CONNECT => Self::Connect,
            hyper::Method::DELETE => Self::Delete,
            hyper::Method::GET => Self::Get,
            hyper::Method::HEAD => Self::Head,
            hyper::Method::OPTIONS => Self::Options,
            hyper::Method::PATCH => Self::Patch,
            hyper::Method::POST => Self::Post,
            hyper::Method::PUT => Self::Put,
            hyper::Method::TRACE => Self::Trace,
            _ => Self::Extension,
        }
    }
}

impl core::fmt::Debug for MethodTag {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Connect => f.write_str("MethodTag::Connect"),
            Self::Delete => f.write_str("MethodTag::Delete"),
            Self::Extension => f.write_str("MethodTag::Extension"),
            Self::Get => f.write_str("MethodTag::Get"),
            Self::Head => f.write_str("MethodTag::Head"),
            Self::Options => f.write_str("MethodTag::Options"),
            Self::Patch => f.write_str("MethodTag::Patch"),
            Self::Post => f.write_str("MethodTag::Post"),
            Self::Put => f.write_str("MethodTag::Put"),
            Self::Trace => f.write_str("MethodTag::Trace"),
        }
    }
}

roc_refcounted_noop_impl!(MethodTag);

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct ResponseToAndFromHost {
    pub body: RocList<u8>,
    pub headers: RocList<Header>,
    pub status: u16,
}

impl RocRefcounted for ResponseToAndFromHost {
    fn inc(&mut self) {
        self.body.inc();
        self.headers.inc();
    }
    fn dec(&mut self) {
        self.body.dec();
        self.headers.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

impl From<hyper::http::Error> for ResponseToAndFromHost {
    fn from(err: hyper::http::Error) -> Self {
        ResponseToAndFromHost {
            status: 500,
            headers: RocList::empty(),
            body: err.to_string().as_bytes().into(),
        }
    }
}

impl From<ResponseToAndFromHost> for hyper::StatusCode {
    fn from(response: ResponseToAndFromHost) -> Self {
        hyper::StatusCode::from_u16(response.status).expect("valid status code from roc")
    }
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct Header {
    name: RocStr,
    value: RocStr,
}

impl Header {
    pub fn new<T: Into<RocStr>>(name: T, value: T) -> Header {
        Header {
            name: name.into(),
            value: value.into(),
        }
    }
}

impl roc_std::RocRefcounted for Header {
    fn inc(&mut self) {
        self.name.inc();
        self.value.inc();
    }
    fn dec(&mut self) {
        self.name.dec();
        self.value.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

pub fn tcp_connect(host: &RocStr, port: u16) -> RocResult<RocBox<()>, RocStr> {
    match TcpStream::connect((host.as_str(), port)) {
        Ok(stream) => {
            let buf_reader = BufReader::new(stream);

            let heap = heap();
            let alloc_result = heap.alloc_for(buf_reader);
            match alloc_result {
                Ok(out) => RocResult::ok(out),
                Err(err) => RocResult::err(to_tcp_connect_err(err)),
            }
        }
        Err(err) => RocResult::err(to_tcp_connect_err(err)),
    }
}

pub fn tcp_read_up_to(stream: RocBox<()>, bytes_to_read: u64) -> RocResult<RocList<u8>, RocStr> {
    let stream: &mut BufReader<TcpStream> =
        ThreadSafeRefcountedResourceHeap::box_to_resource(stream);

    let mut chunk = stream.take(bytes_to_read);

    //TODO: fill a roc list directly. This is an extra O(n) copy.
    match chunk.fill_buf() {
        Ok(received) => {
            let received = received.to_vec();
            stream.consume(received.len());

            RocResult::ok(RocList::from(&received[..]))
        }
        Err(err) => RocResult::err(to_tcp_stream_err(err)),
    }
}

pub fn tcp_read_exactly(stream: RocBox<()>, bytes_to_read: u64) -> RocResult<RocList<u8>, RocStr> {
    let stream: &mut BufReader<TcpStream> =
        ThreadSafeRefcountedResourceHeap::box_to_resource(stream);

    let mut buffer = Vec::with_capacity(bytes_to_read as usize);
    let mut chunk = stream.take(bytes_to_read);

    //TODO: fill a roc list directly. This is an extra O(n) copy.
    match chunk.read_to_end(&mut buffer) {
        Ok(read) => {
            if (read as u64) < bytes_to_read {
                RocResult::err(UNEXPECTED_EOF_ERROR.into())
            } else {
                RocResult::ok(RocList::from(&buffer[..]))
            }
        }
        Err(err) => RocResult::err(to_tcp_stream_err(err)),
    }
}

pub fn tcp_read_until(stream: RocBox<()>, byte: u8) -> RocResult<RocList<u8>, RocStr> {
    let stream: &mut BufReader<TcpStream> =
        ThreadSafeRefcountedResourceHeap::box_to_resource(stream);

    let mut buffer = RocList::empty();
    match roc_file::read_until(stream, byte, &mut buffer) {
        Ok(_) => RocResult::ok(buffer),
        Err(err) => RocResult::err(to_tcp_stream_err(err)),
    }
}

pub fn tcp_write(stream: RocBox<()>, msg: &RocList<u8>) -> RocResult<(), RocStr> {
    let stream: &mut BufReader<TcpStream> =
        ThreadSafeRefcountedResourceHeap::box_to_resource(stream);

    match stream.get_mut().write_all(msg.as_slice()) {
        Ok(()) => RocResult::ok(()),
        Err(err) => RocResult::err(to_tcp_stream_err(err)),
    }
}

// TODO replace with IOErr
fn to_tcp_connect_err(err: std::io::Error) -> RocStr {
    match err.kind() {
        ErrorKind::PermissionDenied => "ErrorKind::PermissionDenied".into(),
        ErrorKind::AddrInUse => "ErrorKind::AddrInUse".into(),
        ErrorKind::AddrNotAvailable => "ErrorKind::AddrNotAvailable".into(),
        ErrorKind::ConnectionRefused => "ErrorKind::ConnectionRefused".into(),
        ErrorKind::Interrupted => "ErrorKind::Interrupted".into(),
        ErrorKind::TimedOut => "ErrorKind::TimedOut".into(),
        ErrorKind::Unsupported => "ErrorKind::Unsupported".into(),
        other => format!("{:?}", other).as_str().into(),
    }
}

fn to_tcp_stream_err(err: std::io::Error) -> RocStr {
    match err.kind() {
        ErrorKind::PermissionDenied => "ErrorKind::PermissionDenied".into(),
        ErrorKind::ConnectionRefused => "ErrorKind::ConnectionRefused".into(),
        ErrorKind::ConnectionReset => "ErrorKind::ConnectionReset".into(),
        ErrorKind::Interrupted => "ErrorKind::Interrupted".into(),
        ErrorKind::OutOfMemory => "ErrorKind::OutOfMemory".into(),
        ErrorKind::BrokenPipe => "ErrorKind::BrokenPipe".into(),
        other => format!("{:?}", other).as_str().into(),
    }
}
