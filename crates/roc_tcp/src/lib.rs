use roc_std::{RocBox, RocList, RocResult, RocStr};
use roc_std_heap::ThreadSafeRefcountedResourceHeap;
use std::env;
use std::io::{BufRead, BufReader, ErrorKind, Read, Write};
use std::net::TcpStream;
use std::sync::OnceLock;
use std::time::Duration;

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

#[repr(C)]
pub struct Request {
    body: RocList<u8>,
    headers: RocList<Header>,
    method: RocStr,
    mime_type: RocStr,
    timeout_ms: u64,
    url: RocStr,
}

#[repr(C)]
pub struct Header {
    key: RocStr,
    value: RocStr,
}

impl roc_std::RocRefcounted for Header {
    fn inc(&mut self) {
        self.key.inc();
        self.value.inc();
    }
    fn dec(&mut self) {
        self.key.dec();
        self.value.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[repr(C)]
pub struct Metadata {
    headers: RocList<Header>,
    status_text: RocStr,
    url: RocStr,
    status_code: u16,
}

impl Metadata {
    fn empty() -> Metadata {
        Metadata {
            headers: RocList::empty(),
            status_text: RocStr::empty(),
            url: RocStr::empty(),
            status_code: 0,
        }
    }
}

#[repr(C)]
pub struct InternalResponse {
    body: RocList<u8>,
    metadata: Metadata,
    variant: RocStr,
}

impl InternalResponse {
    fn bad_request(error: &str) -> InternalResponse {
        InternalResponse {
            variant: "BadRequest".into(),
            metadata: Metadata {
                status_text: RocStr::from(error),
                ..Metadata::empty()
            },
            body: RocList::empty(),
        }
    }

    fn good_status(metadata: Metadata, body: RocList<u8>) -> InternalResponse {
        InternalResponse {
            variant: "GoodStatus".into(),
            metadata,
            body,
        }
    }

    fn bad_status(metadata: Metadata, body: RocList<u8>) -> InternalResponse {
        InternalResponse {
            variant: "BadStatus".into(),
            metadata,
            body,
        }
    }

    fn timeout() -> InternalResponse {
        InternalResponse {
            variant: "Timeout".into(),
            metadata: Metadata::empty(),
            body: RocList::empty(),
        }
    }

    fn network_error() -> InternalResponse {
        InternalResponse {
            variant: "NetworkError".into(),
            metadata: Metadata::empty(),
            body: RocList::empty(),
        }
    }
}

/// sendRequest! : Box Request => InternalResponse
pub fn send_request(rt: &tokio::runtime::Runtime, roc_request: &Request) -> InternalResponse {
    let method = parse_http_method(roc_request.method.as_str());
    let mut req_builder = hyper::Request::builder()
        .method(method)
        .uri(roc_request.url.as_str());
    let mut has_content_type_header = false;

    for header in roc_request.headers.iter() {
        req_builder = req_builder.header(header.key.as_str(), header.value.as_str());
        if header.key.eq_ignore_ascii_case("Content-Type") {
            has_content_type_header = true;
        }
    }

    let bytes = String::from_utf8(roc_request.body.as_slice().to_vec()).unwrap();
    let mime_type_str = roc_request.mime_type.as_str();

    if !has_content_type_header && !mime_type_str.is_empty() {
        req_builder = req_builder.header("Content-Type", mime_type_str);
    }

    let request = match req_builder.body(bytes) {
        Ok(req) => req,
        Err(err) => return InternalResponse::bad_request(err.to_string().as_str()),
    };

    if roc_request.timeout_ms > 0 {
        let time_limit = Duration::from_millis(roc_request.timeout_ms);

        rt.block_on(async {
            tokio::time::timeout(time_limit, async_send_request(request, &roc_request.url)).await
        })
        .unwrap_or_else(|_err| InternalResponse::timeout())
    } else {
        rt.block_on(async_send_request(request, &roc_request.url))
    }
}

fn parse_http_method(method: &str) -> hyper::Method {
    match method {
        "Connect" => hyper::Method::CONNECT,
        "Delete" => hyper::Method::DELETE,
        "Get" => hyper::Method::GET,
        "Head" => hyper::Method::HEAD,
        "Options" => hyper::Method::OPTIONS,
        "Patch" => hyper::Method::PATCH,
        "Post" => hyper::Method::POST,
        "Put" => hyper::Method::PUT,
        "Trace" => hyper::Method::TRACE,
        _other => unreachable!("Should only pass known HTTP methods from Roc side"),
    }
}

async fn async_send_request(request: hyper::Request<String>, url: &str) -> InternalResponse {
    use hyper::Client;
    use hyper_rustls::HttpsConnectorBuilder;

    let https = HttpsConnectorBuilder::new()
        .with_native_roots()
        .https_or_http()
        .enable_http1()
        .build();

    let client: Client<_, String> = Client::builder().build(https);
    let res = client.request(request).await;

    match res {
        Ok(response) => {
            let status = response.status();
            let status_str = status.canonical_reason().unwrap_or_else(|| status.as_str());

            let headers_iter = response.headers().iter().map(|(name, value)| Header {
                key: RocStr::from(name.as_str()),
                value: RocStr::from(value.to_str().unwrap_or_default()),
            });

            let metadata = Metadata {
                headers: RocList::from_iter(headers_iter),
                status_text: RocStr::from(status_str),
                url: RocStr::from(url),
                status_code: status.as_u16(),
            };

            let bytes = hyper::body::to_bytes(response.into_body()).await.unwrap();
            let body: RocList<u8> = RocList::from_iter(bytes);

            if status.is_success() {
                InternalResponse::good_status(metadata, body)
            } else {
                InternalResponse::bad_status(metadata, body)
            }
        }
        Err(err) => {
            if err.is_timeout() {
                InternalResponse::timeout()
            } else if err.is_connect() || err.is_closed() {
                InternalResponse::network_error()
            } else {
                InternalResponse::bad_request(err.to_string().as_str())
            }
        }
    }
}

/// tcpConnect! : Str, U16 => Result TcpStream Str
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

/// tcpReadUpTo! : TcpStream, U64 => Result (List U8) Str
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

/// tcpReadExactly! : TcpStream, U64 => Result (List U8) Str
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

/// tcpReadUntil! : TcpStream, U8 => Result (List U8) Str
pub fn tcp_read_until(stream: RocBox<()>, byte: u8) -> RocResult<RocList<u8>, RocStr> {
    let stream: &mut BufReader<TcpStream> =
        ThreadSafeRefcountedResourceHeap::box_to_resource(stream);

    let mut buffer = RocList::empty();
    match roc_file::read_until(stream, byte, &mut buffer) {
        Ok(_) => RocResult::ok(buffer),
        Err(err) => RocResult::err(to_tcp_stream_err(err)),
    }
}

/// tcpWrite! : TcpStream, List U8 => Result {} Str
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
