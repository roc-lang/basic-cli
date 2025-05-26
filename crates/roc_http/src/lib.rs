//! This crate provides common functionality for Roc to interface with `std::net::tcp`
use roc_std::{RocBox, RocList, RocRefcounted, RocResult, RocStr};
use roc_std_heap::ThreadSafeRefcountedResourceHeap;
use std::env;
use std::io::{BufRead, BufReader, ErrorKind, Read, Write};
use std::net::TcpStream;
use std::sync::OnceLock;
use bytes::Bytes;

pub const REQUEST_TIMEOUT_BODY: &[u8] = "RequestTimeout".as_bytes();
pub const REQUEST_NETWORK_ERR: &[u8] = "Network Error".as_bytes();
pub const REQUEST_BAD_BODY: &[u8] = "Bad Body".as_bytes();

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
#[repr(C, align(8))]
pub struct RequestToAndFromHost {
    pub body: RocList<u8>,
    pub headers: RocList<Header>,
    pub method: u64,
    pub method_ext: RocStr,
    pub timeout_ms: u64,
    pub uri: RocStr,
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
        let method: u64 = RequestToAndFromHost::from_hyper_method(hyper_req.method());
        let method_ext = {
            if RequestToAndFromHost::is_extension_method(method) {
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

    pub fn is_extension_method(raw_method: u64) -> bool {
        raw_method == 2
    }

    pub fn from_hyper_method(method: &hyper::Method) -> u64 {
        match *method {
            hyper::Method::CONNECT => 0,
            hyper::Method::DELETE => 1,
            hyper::Method::GET => 3,
            hyper::Method::HEAD => 4,
            hyper::Method::OPTIONS => 5,
            hyper::Method::PATCH => 6,
            hyper::Method::POST => 7,
            hyper::Method::PUT => 8,
            hyper::Method::TRACE => 9,
            _ => 2,
        }
    }

    pub fn as_hyper_method(&self) -> hyper::Method {
        match self.method {
            0 => hyper::Method::CONNECT,
            1 => hyper::Method::DELETE,
            2 => hyper::Method::from_bytes(self.method_ext.as_bytes()).unwrap(),
            3 => hyper::Method::GET,
            4 => hyper::Method::HEAD,
            5 => hyper::Method::OPTIONS,
            6 => hyper::Method::PATCH,
            7 => hyper::Method::POST,
            8 => hyper::Method::PUT,
            9 => hyper::Method::TRACE,
            _ => panic!("invalid method"),
        }
    }

    pub fn to_hyper_request(&self) -> Result<hyper::Request<http_body_util::Full<Bytes>>, hyper::http::Error> {
        let method: hyper::Method = self.as_hyper_method();
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

        let bytes: http_body_util::Full<Bytes> = http_body_util::Full::new(self.body.as_slice().to_vec().into());

        req_builder.body(bytes)
    }
}

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

impl From<ResponseToAndFromHost> for hyper::Response<http_body_util::Full<Bytes>> {
    fn from(roc_response: ResponseToAndFromHost) -> Self {
        let mut builder = hyper::Response::builder();

        // TODO handle invalid status code provided from roc....
        // we should return an error
        builder = builder.status(
            hyper::StatusCode::from_u16(roc_response.status).expect("valid status from roc"),
        );

        for header in roc_response.headers.iter() {
            builder = builder.header(header.name.as_str(), header.value.as_bytes());
        }

        builder
            .body(http_body_util::Full::new(Vec::from(roc_response.body.as_slice()).into())) // TODO try not to use Vec here
            .unwrap() // TODO don't unwrap this
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
    pub name: RocStr,
    pub value: RocStr,
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
