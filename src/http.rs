use core::mem::ManuallyDrop;
use std::sync::LazyLock;
use std::time::{Duration, Instant};

use crate::roc_platform_abi::*;
use crate::{resources, roc_host, roc_u8_list_from_slice};

// The generated glue names the request/response records by anonymous-struct
// number; alias them to stable semantic names. Host ABI headers are `(Str, Str)`
// tuples, rendered as a struct with `_0` (name) and `_1` (value) fields.
type HttpResponse = HostHttpSendRequestOk;
type HttpHeader = HostHttpSendRequestArg0Headers;
type HttpResult = HostHttpSendRequestResult;
type HttpResultPayload = HostHttpSendRequestResultPayload;
type HttpResultTag = HostHttpSendRequestResultTag;
type HttpTransportErr = BadBodyOrInterruptedOrNetworkErrorOrOtherOrTimeout;
type HttpTransportErrPayload = BadBodyOrInterruptedOrNetworkErrorOrOtherOrTimeoutPayload;
type HttpTransportErrTag = BadBodyOrInterruptedOrNetworkErrorOrOtherOrTimeoutTag;

// Deliberately a `static`, so this runtime is never dropped.
//
// Hyper previously resolved names with `getaddrinfo` on tokio's blocking pool, whose
// threads linger for ten seconds after their last job, and dropping a runtime
// waits for each of them to acknowledge the shutdown. This used to be a thread
// local, which is dropped when its thread exits. On Windows the main thread's
// thread locals are dropped during `ExitProcess`, after the OS has already
// terminated every other thread, so a program that had sent a request in its
// last ten seconds waited forever for a pool thread that no longer existed.
// Leaking the runtime at exit costs nothing, since the OS reclaims it either way.
//
// So: do not give this runtime an owner that drops it, and do not shut it down
// from `lib.rs` alongside `process_service::shutdown`. Either reintroduces the
// hang. `examples/http-client.roc` guards the exit path by reaching the test
// server by host name. DNS now uses our bounded broker, whose native workers
// are also process-owned and never joined during host teardown.
static TOKIO_RUNTIME: LazyLock<tokio::runtime::Runtime> = LazyLock::new(|| {
    tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()
        .expect("failed to build tokio runtime")
});

// Numeric method tags must match `to_host_method` in platform/InternalHttp.roc.
fn as_hyper_method(method: u8, method_ext: &str) -> Option<hyper::Method> {
    match method {
        0 => Some(hyper::Method::CONNECT),
        1 => Some(hyper::Method::DELETE),
        2 => hyper::Method::from_bytes(method_ext.as_bytes()).ok(),
        3 => Some(hyper::Method::GET),
        4 => Some(hyper::Method::HEAD),
        5 => Some(hyper::Method::OPTIONS),
        6 => Some(hyper::Method::PATCH),
        7 => Some(hyper::Method::POST),
        8 => Some(hyper::Method::PUT),
        9 => Some(hyper::Method::TRACE),
        _ => None,
    }
}

fn http_ok(response: HttpResponse) -> HttpResult {
    HttpResult {
        payload: HttpResultPayload {
            ok: ManuallyDrop::new(response),
        },
        tag: HttpResultTag::Ok,
    }
}

fn http_err(error: HttpTransportErr) -> HttpResult {
    HttpResult {
        payload: HttpResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HttpResultTag::Err,
    }
}

fn http_err_interrupted() -> HttpTransportErr {
    HttpTransportErr {
        payload: HttpTransportErrPayload { interrupted: [] },
        tag: HttpTransportErrTag::Interrupted,
    }
}

fn http_err_timeout() -> HttpTransportErr {
    HttpTransportErr {
        payload: HttpTransportErrPayload { timeout: [] },
        tag: HttpTransportErrTag::Timeout,
    }
}

fn http_err_bad_body() -> HttpTransportErr {
    HttpTransportErr {
        payload: HttpTransportErrPayload { bad_body: [] },
        tag: HttpTransportErrTag::BadBody,
    }
}

fn http_err_other(message: &str, roc_host: &RocHost) -> HttpTransportErr {
    HttpTransportErr {
        payload: HttpTransportErrPayload {
            other: ManuallyDrop::new(roc_u8_list_from_slice(message.as_bytes(), roc_host)),
        },
        tag: HttpTransportErrTag::Other,
    }
}

type HyperRequest = hyper::Request<http_body_util::Full<bytes::Bytes>>;

/// The request record as it crosses the host boundary. `Http.send!` receives
/// its fields as the hosted function's arguments and `Http.send_streaming!`
/// receives them as one record; both build the same hyper request from this.
struct RequestParts<'a> {
    method: u8,
    method_ext: &'a str,
    uri: &'a str,
    headers: &'a [HttpHeader],
    body: &'a [u8],
}

impl<'a> From<&'a HostHttpSendRequestArgs> for RequestParts<'a> {
    fn from(args: &'a HostHttpSendRequestArgs) -> Self {
        Self {
            method: args.method,
            method_ext: args.method_ext.as_str(),
            uri: args.uri.as_str(),
            headers: args.headers.as_slice(),
            body: args.body.as_slice(),
        }
    }
}

impl<'a> From<&'a HostHttpSendStreamingArg0> for RequestParts<'a> {
    fn from(request: &'a HostHttpSendStreamingArg0) -> Self {
        Self {
            method: request.method,
            method_ext: request.method_ext.as_str(),
            uri: request.uri.as_str(),
            headers: request.headers.as_slice(),
            body: request.body.as_slice(),
        }
    }
}

fn build_hyper_request(parts: RequestParts<'_>) -> Result<HyperRequest, String> {
    let method = as_hyper_method(parts.method, parts.method_ext)
        .ok_or_else(|| "invalid HTTP method".to_string())?;
    let mut builder = hyper::Request::builder().method(method).uri(parts.uri);

    // Defaults are resolved once in Roc. Never resurrect body headers after redirects.
    for header in parts.headers {
        builder = builder.header(header._0.as_str(), header._1.as_str());
    }

    let body = http_body_util::Full::new(bytes::Bytes::from(parts.body.to_vec()));
    builder.body(body).map_err(|err| err.to_string())
}

fn header_pairs(headers: &hyper::HeaderMap) -> Vec<(String, String)> {
    headers
        .iter()
        .map(|(name, value)| {
            (
                name.as_str().to_string(),
                std::str::from_utf8(value.as_bytes())
                    .unwrap_or_default()
                    .to_string(),
            )
        })
        .collect()
}

fn invalid_location(headers: &hyper::HeaderMap) -> Option<u8> {
    headers
        .get_all(hyper::header::LOCATION)
        .iter()
        .find_map(|value| {
            std::str::from_utf8(value.as_bytes())
                .err()
                .map(|error| value.as_bytes()[error.valid_up_to()])
        })
}

fn build_roc_headers(pairs: &[(String, String)], roc_host: &RocHost) -> RocList<HttpHeader> {
    let list = unsafe { RocList::<HttpHeader>::allocate(pairs.len(), roc_host) };
    for (index, (name, value)) in pairs.iter().enumerate() {
        let header = HttpHeader {
            _0: RocStr::from_str(name, roc_host),
            _1: RocStr::from_str(value, roc_host),
        };
        unsafe {
            list.elements.add(index).write(header);
        }
    }
    list
}

fn https_connector() -> hyper_rustls::HttpsConnector<
    hyper_util::client::legacy::connect::HttpConnector<crate::dns::HttpResolver>,
> {
    let mut http = hyper_util::client::legacy::connect::HttpConnector::new_with_resolver(
        crate::dns::HttpResolver,
    );
    http.enforce_http(false);
    hyper_rustls::HttpsConnectorBuilder::new()
        .with_webpki_roots()
        .https_or_http()
        .enable_http1()
        .wrap_connector(http)
}

async fn async_send_request(request: HyperRequest, roc_host: &RocHost) -> HttpResult {
    use http_body_util::BodyExt;
    use hyper_util::client::legacy::Client;
    use hyper_util::rt::TokioExecutor;

    let client: Client<_, http_body_util::Full<bytes::Bytes>> =
        Client::builder(TokioExecutor::new()).build(https_connector());

    match client.request(request).await {
        Ok(response) => {
            let status = response.status().as_u16();
            let pairs = header_pairs(response.headers());

            match response.into_body().collect().await {
                Ok(collected) => {
                    let bytes = collected.to_bytes();
                    http_ok(HttpResponse {
                        body: roc_u8_list_from_slice(&bytes, roc_host),
                        headers: build_roc_headers(&pairs, roc_host),
                        status,
                    })
                }
                Err(_) => http_err(http_err_bad_body()),
            }
        }
        Err(err) => {
            let detail = err.to_string();
            http_err(http_err_other(&detail, roc_host))
        }
    }
}

#[no_mangle]
pub extern "C" fn hosted_http_send_request(args: HostHttpSendRequestArgs) -> HttpResult {
    let roc_host = roc_host();
    let timeout_ms = args.timeout_ms;

    // Build the hyper request from the borrowed args, then release the owned
    // Roc values (the request has copied everything it needs).
    let request_result = build_hyper_request((&args).into());
    unsafe {
        args.body.decref(roc_host);
        for header in args.headers.as_slice() {
            header.decref(roc_host);
        }
        args.headers.decref(roc_host);
        args.method_ext.decref(roc_host);
        args.uri.decref(roc_host);
    }

    match request_result {
        Ok(request) => send_request(request, timeout_ms, roc_host),
        Err(err) => http_err(http_err_other(&err, roc_host)),
    }
}

// A zero timeout means the caller did not set one.
fn send_request(request: HyperRequest, timeout_ms: u64, roc_host: &RocHost) -> HttpResult {
    if crate::signals::is_pending() {
        return http_err(http_err_interrupted());
    }
    let until = (timeout_ms > 0)
        .then(|| Instant::now().checked_add(Duration::from_millis(timeout_ms)))
        .flatten();
    TOKIO_RUNTIME
        .block_on(await_io(until, async_send_request(request, roc_host)))
        .unwrap_or_else(|failure| http_err(failure.to_roc(roc_host)))
}

// ============================================================================
// Streaming responses
//
// `Http.send_streaming!` returns once the status and headers have arrived and
// leaves the body in the host, behind a `Resource.HttpResponse` handle. Every
// stream and `read_to_end!` call of one response reads through that handle, so
// they share one cursor.
//
// The request is sent by the same client type as `Http.send!`, with pooling
// off: each response owns its connection, which hyper drives from a task on
// `TOKIO_RUNTIME`. That task only runs while a hosted call is inside
// `block_on`, so wherever the body is given up (`StreamingBody::close`) the
// runtime is turned a few times to let the task see it and close the socket.
// ----------------------------------------------------------------------------

/// The largest chunk handed to Roc.
const MAX_CHUNK_BYTES: usize = 64 * 1024;

/// How often the runtime is turned after a body has been given up. One turn
/// lets the connection task observe the dropped body and finish; the others
/// cover a TLS session that needs another poll to shut down.
const SETTLE_TURNS: usize = 4;

/// A transport failure, as `Http.TransportErr` names it.
#[derive(Clone, Debug, PartialEq, Eq)]
enum Failure {
    Interrupted,
    Timeout,
    BadBody,
    Other(String),
}

impl Failure {
    fn to_roc(&self, roc_host: &RocHost) -> HttpTransportErr {
        match self {
            Failure::Interrupted => http_err_interrupted(),
            Failure::Timeout => http_err_timeout(),
            Failure::BadBody => http_err_bad_body(),
            Failure::Other(message) => http_err_other(message, roc_host),
        }
    }
}

/// Poll cancellation, then the clock, then readiness. `tokio::time::timeout`
/// polls its inner future first, which would let ready I/O beat an expired
/// timeout. Use an absolute clock so constructing a connector costs time too.
async fn await_io<T>(
    until: Option<Instant>,
    operation: impl std::future::Future<Output = T>,
) -> Result<T, Failure> {
    if crate::signals::is_pending() {
        return Err(Failure::Interrupted);
    }
    if until.is_some_and(|until| until <= Instant::now()) {
        return Err(Failure::Timeout);
    }
    tokio::select! {
        biased;
        _ = crate::signals::cancelled() => Err(Failure::Interrupted),
        _ = async {
            match until {
                Some(until) => tokio::time::sleep_until(tokio::time::Instant::from_std(until)).await,
                None => std::future::pending::<()>().await,
            }
        } => Err(Failure::Timeout),
        result = operation => Ok(result),
    }
}

#[derive(Debug, PartialEq, Eq)]
enum ReadToEndErr {
    /// More than the caller's limit of unread bytes has arrived. They are kept.
    LimitExceeded,
    Failed(Failure),
}

enum BodyState {
    /// The connection is open and the body has not ended.
    Open(hyper::body::Incoming),
    /// The body ended and the connection has been released.
    Ended,
    /// The body failed for good and the connection has been released. Every
    /// later read reports the same failure.
    Failed(Failure),
}

/// The resource behind a `Resource.HttpResponse` handle.
pub struct StreamingBody {
    state: BodyState,
    /// Bytes that have arrived and not been handed to Roc yet: the tail of a
    /// frame larger than one chunk, or what `read_to_end` had collected when
    /// it stopped at an idle timeout or at its limit.
    pending: bytes::BytesMut,
    /// The longest single wait for the next part of the body.
    idle_timeout: Option<Duration>,
    /// The `Request` timeout: when the whole exchange has to be over.
    deadline: Option<Instant>,
}

/// Why a wait for the next frame stopped without one.
enum Stalled {
    Interrupted,
    /// Nothing arrived within the idle timeout. The body is intact and the
    /// wait can be repeated.
    Idle,
    Failed(Failure),
}

/// Let the connection task of a body that was just given up close its socket.
fn settle() {
    // Never reached from inside the runtime: hosted calls drop handles only
    // after `block_on` has returned. A nested `block_on` would panic.
    if tokio::runtime::Handle::try_current().is_ok() {
        return;
    }
    TOKIO_RUNTIME.block_on(async {
        for _ in 0..SETTLE_TURNS {
            tokio::task::yield_now().await;
        }
    });
}

/// The time allowed for one wait: the idle timeout, cut short by the deadline.
/// `Err` means the deadline has already passed.
fn wait_budget(
    idle_timeout: Option<Duration>,
    deadline: Option<Instant>,
    now: Instant,
) -> Result<Option<Duration>, ()> {
    let remaining = match deadline {
        Some(deadline) if deadline <= now => return Err(()),
        Some(deadline) => Some(deadline - now),
        None => None,
    };
    Ok(match (idle_timeout, remaining) {
        (Some(idle), Some(remaining)) => Some(idle.min(remaining)),
        (idle, remaining) => idle.or(remaining),
    })
}

/// The body length a response declares: its `Content-Length`, unless the body
/// is sent with a transfer encoding, whose length is not known in advance.
fn declared_content_length(headers: &hyper::HeaderMap) -> Option<u64> {
    if headers.contains_key(hyper::header::TRANSFER_ENCODING) {
        return None;
    }
    let mut lengths = headers
        .get_all(hyper::header::CONTENT_LENGTH)
        .iter()
        .map(|value| value.to_str().ok()?.trim().parse::<u64>().ok());
    let first = lengths.next()??;
    lengths.all(|length| length == Some(first)).then_some(first)
}

impl StreamingBody {
    fn check_read(&mut self) -> Result<(), Failure> {
        if crate::signals::is_pending() {
            return Err(Failure::Interrupted);
        }
        if let BodyState::Failed(failure) = &self.state {
            return Err(failure.clone());
        }
        if matches!(self.state, BodyState::Open(_))
            && self
                .deadline
                .is_some_and(|deadline| deadline <= Instant::now())
        {
            return Err(self.fail(Failure::Timeout));
        }
        Ok(())
    }

    /// Give up the connection and remember how the body finished.
    fn close(&mut self, state: BodyState) {
        let was_open = matches!(self.state, BodyState::Open(_));
        // Dropping the body is what tells the connection task to stop.
        self.state = state;
        if was_open {
            settle();
        }
    }

    fn fail(&mut self, failure: Failure) -> Failure {
        self.pending.clear();
        self.close(BodyState::Failed(failure.clone()));
        failure
    }

    /// Wait for the next non-empty data frame. `Ok(None)` is the end of the body.
    fn next_frame(&mut self) -> Result<Option<bytes::Bytes>, Stalled> {
        use http_body_util::BodyExt;

        loop {
            if crate::signals::is_pending() {
                return Err(Stalled::Interrupted);
            }
            let body = match &mut self.state {
                BodyState::Open(body) => body,
                BodyState::Ended => return Ok(None),
                BodyState::Failed(failure) => return Err(Stalled::Failed(failure.clone())),
            };
            let now = Instant::now();
            let Ok(budget) = wait_budget(self.idle_timeout, self.deadline, now) else {
                return Err(Stalled::Failed(self.fail(Failure::Timeout)));
            };
            // Abandoning `frame()` at a timeout loses nothing: the future holds
            // no data, and a frame that was not returned stays in the body.
            let until = budget.and_then(|budget| now.checked_add(budget));
            let frame = match TOKIO_RUNTIME.block_on(await_io(until, body.frame())) {
                Ok(frame) => frame,
                Err(Failure::Interrupted) => return Err(Stalled::Interrupted),
                Err(Failure::Timeout)
                    if !self
                        .deadline
                        .is_some_and(|deadline| deadline <= Instant::now()) =>
                {
                    return Err(Stalled::Idle);
                }
                Err(failure) => return Err(Stalled::Failed(self.fail(failure))),
            };
            match frame {
                Some(Ok(frame)) => match frame.into_data() {
                    Ok(data) if !data.is_empty() => return Ok(Some(data)),
                    // An empty frame carries nothing, and trailers are not exposed.
                    _ => continue,
                },
                Some(Err(_)) => {
                    if crate::signals::is_pending() {
                        // Remember the native failure for the next read without
                        // exposing it ahead of the pending interruption.
                        self.close(BodyState::Failed(Failure::BadBody));
                        return Err(Stalled::Interrupted);
                    }
                    self.check_read().map_err(Stalled::Failed)?;
                    return Err(Stalled::Failed(self.fail(Failure::BadBody)));
                }
                None => {
                    // EOF can be polled again. Leave the body open if an
                    // interruption wins, so its deadline remains effective.
                    self.check_read().map_err(|failure| match failure {
                        Failure::Interrupted => Stalled::Interrupted,
                        failure => Stalled::Failed(failure),
                    })?;
                    self.close(BodyState::Ended);
                    return Ok(None);
                }
            }
        }
    }

    /// The next non-empty chunk of at most `MAX_CHUNK_BYTES`, or `None` at the
    /// end of the body.
    fn read_chunk(&mut self) -> Result<Option<bytes::Bytes>, Failure> {
        self.check_read()?;
        if self.pending.is_empty() {
            match self.next_frame() {
                Ok(Some(frame)) => self.pending.extend_from_slice(&frame),
                Ok(None) => return Ok(None),
                Err(Stalled::Interrupted) => return Err(Failure::Interrupted),
                Err(Stalled::Idle) => return Err(Failure::Timeout),
                Err(Stalled::Failed(failure)) => return Err(failure),
            }
        }
        self.check_read()?;
        let len = self.pending.len().min(MAX_CHUNK_BYTES);
        Ok(Some(self.pending.split_to(len).freeze()))
    }

    /// Everything that has not been read, once the body has ended.
    ///
    /// Fails as soon as more than `max` unread bytes have arrived. Whatever
    /// had been collected when this stops at the limit or at an idle timeout
    /// stays unread, so a later read continues from the same place.
    fn read_to_end(&mut self, max: u64) -> Result<bytes::Bytes, ReadToEndErr> {
        loop {
            self.check_read().map_err(ReadToEndErr::Failed)?;
            if self.pending.len() as u64 > max {
                return Err(ReadToEndErr::LimitExceeded);
            }
            match self.next_frame() {
                Ok(Some(frame)) => self.pending.extend_from_slice(&frame),
                Ok(None) => {
                    self.check_read().map_err(ReadToEndErr::Failed)?;
                    return Ok(self.pending.split().freeze());
                }
                Err(Stalled::Interrupted) => {
                    return Err(ReadToEndErr::Failed(Failure::Interrupted))
                }
                Err(Stalled::Idle) => return Err(ReadToEndErr::Failed(Failure::Timeout)),
                Err(Stalled::Failed(failure)) => return Err(ReadToEndErr::Failed(failure)),
            }
        }
    }
}

impl Drop for StreamingBody {
    fn drop(&mut self) {
        // An unread body still holds its connection.
        self.close(BodyState::Ended);
    }
}

/// The status line and headers of a response whose body has not been read.
struct StreamingHead {
    status: u16,
    headers: Vec<(String, String)>,
    invalid_location: Option<u8>,
    content_length: Option<u64>,
}

/// Send `request` and wait for the status and headers.
///
/// `timeout_ms` is the `Request` timeout, the deadline for the whole exchange,
/// where zero means none. `idle_timeout` bounds this wait and each later wait
/// for part of the body; zero expires before anything is sent.
#[cfg(test)]
fn send_streaming(
    request: HyperRequest,
    timeout_ms: u64,
    idle_timeout: Option<Duration>,
) -> Result<(StreamingHead, StreamingBody), Failure> {
    let deadline = match timeout_ms {
        0 => None,
        ms => Instant::now().checked_add(Duration::from_millis(ms)),
    };
    send_streaming_at(request, idle_timeout, deadline)
}

fn send_streaming_at(
    request: HyperRequest,
    idle_timeout: Option<Duration>,
    deadline: Option<Instant>,
) -> Result<(StreamingHead, StreamingBody), Failure> {
    use hyper_util::client::legacy::Client;
    use hyper_util::rt::TokioExecutor;
    if crate::signals::is_pending() {
        return Err(Failure::Interrupted);
    }
    if idle_timeout == Some(Duration::ZERO) {
        return Err(Failure::Timeout);
    }
    let now = Instant::now();
    let budget = wait_budget(idle_timeout, deadline, now).map_err(|()| Failure::Timeout)?;
    let until = budget.and_then(|budget| now.checked_add(budget));

    let response = TOKIO_RUNTIME.block_on(async {
        // The same client as `async_send_request`, so both entry points put
        // the same request on the wire. Without a pool the connection is not
        // kept for a later request: it closes when its response is finished
        // with.
        let client: Client<_, http_body_util::Full<bytes::Bytes>> =
            Client::builder(TokioExecutor::new())
                .pool_max_idle_per_host(0)
                .build(https_connector());
        await_io(until, client.request(request)).await
    });
    let response = match response {
        Ok(Ok(response)) => response,
        Ok(Err(error)) => return Err(Failure::Other(error.to_string())),
        Err(failure) => {
            settle();
            return Err(failure);
        }
    };

    // The result has not crossed to Roc yet. An event that arrived while the
    // ready response was being polled must still win over its headers.
    let stopped = if crate::signals::is_pending() {
        Some(Failure::Interrupted)
    } else if until.is_some_and(|until| until <= Instant::now()) {
        Some(Failure::Timeout)
    } else {
        None
    };
    if let Some(failure) = stopped {
        drop(response);
        settle();
        return Err(failure);
    }

    let (parts, body) = response.into_parts();
    let head = StreamingHead {
        status: parts.status.as_u16(),
        headers: header_pairs(&parts.headers),
        invalid_location: invalid_location(&parts.headers),
        content_length: declared_content_length(&parts.headers),
    };
    let body = StreamingBody {
        state: BodyState::Open(body),
        pending: bytes::BytesMut::new(),
        idle_timeout,
        deadline,
    };
    Ok((head, body))
}

fn streaming_err(failure: &Failure, roc_host: &RocHost) -> HostHttpSendStreamingResult {
    HostHttpSendStreamingResult {
        payload: HostHttpSendStreamingResultPayload {
            err: ManuallyDrop::new(failure.to_roc(roc_host)),
        },
        tag: HostHttpSendStreamingResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_http_send_streaming(
    request: HostHttpSendStreamingArg0,
    idle_timeout: AfterOrNoTimeout,
    deadline: AtOrNoTimeout,
) -> HostHttpSendStreamingResult {
    let roc_host = roc_host();
    let deadline = match deadline.tag {
        AtOrNoTimeoutTag::At => crate::monotonic_origin()
            .checked_add(Duration::from_nanos(unsafe { *deadline.payload.at })),
        AtOrNoTimeoutTag::NoTimeout => None,
    };
    let idle_timeout = match idle_timeout.tag {
        AfterOrNoTimeoutTag::After => {
            Some(Duration::from_nanos(unsafe { *idle_timeout.payload.after }))
        }
        AfterOrNoTimeoutTag::NoTimeout => None,
    };

    // The hyper request copies what it needs, so the Roc values can go.
    let hyper_request = build_hyper_request((&request).into());
    unsafe { request.decref(roc_host) };

    let sent = hyper_request
        .map_err(Failure::Other)
        .and_then(|request| send_streaming_at(request, idle_timeout, deadline));
    let (head, body) = match sent {
        Ok(sent) => sent,
        Err(failure) => return streaming_err(&failure, roc_host),
    };
    let handle = match resources::box_resource(body, roc_host) {
        Ok(handle) => handle,
        Err(error) => return streaming_err(&Failure::Other(error.to_string()), roc_host),
    };
    let content_length = match head.content_length {
        Some(length) => KnownOrUnknown {
            payload: KnownOrUnknownPayload {
                known: ManuallyDrop::new(length),
            },
            tag: KnownOrUnknownTag::Known,
        },
        None => KnownOrUnknown {
            payload: KnownOrUnknownPayload { unknown: [] },
            tag: KnownOrUnknownTag::Unknown,
        },
    };
    let invalid_location = match head.invalid_location {
        Some(byte) => NoneOrSome {
            payload: NoneOrSomePayload {
                some: ManuallyDrop::new(byte),
            },
            tag: NoneOrSomeTag::Some,
        },
        None => NoneOrSome {
            payload: NoneOrSomePayload { none: [] },
            tag: NoneOrSomeTag::None,
        },
    };
    HostHttpSendStreamingResult {
        payload: HostHttpSendStreamingResultPayload {
            ok: ManuallyDrop::new(HostHttpSendStreamingOk {
                content_length,
                invalid_location,
                body: handle,
                headers: build_roc_headers(&head.headers, roc_host),
                status: head.status,
            }),
        },
        tag: HostHttpSendStreamingResultTag::Ok,
    }
}

#[no_mangle]
pub extern "C" fn hosted_http_close_body(handle: *mut u64) {
    let host = roc_host();
    unsafe { resources::resource_ref::<StreamingBody>(handle) }.close(BodyState::Ended);
    resources::release(handle, host);
}

fn read_body_err(error: HostHttpReadBodyErr) -> HostHttpReadBodyResult {
    HostHttpReadBodyResult {
        payload: HostHttpReadBodyResultPayload {
            err: ManuallyDrop::new(error),
        },
        tag: HostHttpReadBodyResultTag::Err,
    }
}

fn read_body_ok(bytes: &[u8], roc_host: &RocHost) -> HostHttpReadBodyResult {
    HostHttpReadBodyResult {
        payload: HostHttpReadBodyResultPayload {
            ok: ManuallyDrop::new(roc_u8_list_from_slice(bytes, roc_host)),
        },
        tag: HostHttpReadBodyResultTag::Ok,
    }
}

fn read_body_failed(failure: &Failure, roc_host: &RocHost) -> HostHttpReadBodyResult {
    read_body_err(HostHttpReadBodyErr {
        payload: HostHttpReadBodyErrPayload {
            http_err: ManuallyDrop::new(failure.to_roc(roc_host)),
        },
        tag: HostHttpReadBodyErrTag::HttpErr,
    })
}

/// # Safety
///
/// `handle` must be a live response handle from `hosted_http_send_streaming`.
#[no_mangle]
pub unsafe extern "C" fn hosted_http_read_body(
    handle: *mut u64,
    amount: ChunkOrToEnd,
) -> HostHttpReadBodyResult {
    let roc_host = roc_host();
    let body = unsafe { resources::resource_ref::<StreamingBody>(handle) };
    let result = match amount.tag {
        ChunkOrToEndTag::Chunk => match body.read_chunk() {
            Ok(Some(chunk)) => read_body_ok(&chunk, roc_host),
            Ok(None) => read_body_err(HostHttpReadBodyErr {
                payload: HostHttpReadBodyErrPayload { end_of_body: [] },
                tag: HostHttpReadBodyErrTag::EndOfBody,
            }),
            Err(failure) => read_body_failed(&failure, roc_host),
        },
        ChunkOrToEndTag::ToEnd => match body.read_to_end(unsafe { *amount.payload.to_end }) {
            Ok(rest) => read_body_ok(&rest, roc_host),
            Err(ReadToEndErr::LimitExceeded) => read_body_err(HostHttpReadBodyErr {
                payload: HostHttpReadBodyErrPayload {
                    read_limit_exceeded: [],
                },
                tag: HostHttpReadBodyErrTag::ReadLimitExceeded,
            }),
            Err(ReadToEndErr::Failed(failure)) => read_body_failed(&failure, roc_host),
        },
    };
    // Only now, outside `block_on`: this may be the last reference.
    resources::release(handle, roc_host);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::sync::mpsc;
    use std::thread;
    use std::time::Duration;

    #[test]
    fn ring_tls_handshake_and_untrusted_certificate_rejection() {
        use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName};
        use std::io::{Read, Write};
        use std::sync::Arc;

        let cert = CertificateDer::from(include_bytes!("../tests/tls/localhost-cert.der").to_vec());
        let key =
            PrivateKeyDer::try_from(include_bytes!("../tests/tls/localhost-key.der").to_vec())
                .unwrap();
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let config = rustls::ServerConfig::builder_with_provider(provider.clone())
            .with_safe_default_protocol_versions()
            .unwrap()
            .with_no_client_auth()
            .with_single_cert(vec![cert.clone()], key)
            .unwrap();
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let address = listener.local_addr().unwrap();
        let server = thread::spawn(move || {
            for accepted in [true, false] {
                let deadline = std::time::Instant::now() + Duration::from_secs(5);
                let socket = loop {
                    match listener.accept() {
                        Ok((socket, _)) => break socket,
                        Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                            assert!(
                                std::time::Instant::now() < deadline,
                                "TLS client did not connect"
                            );
                            thread::sleep(Duration::from_millis(5));
                        }
                        Err(error) => panic!("TLS listener failed: {error}"),
                    }
                };
                socket.set_nonblocking(false).unwrap();
                socket
                    .set_read_timeout(Some(Duration::from_secs(5)))
                    .unwrap();
                socket
                    .set_write_timeout(Some(Duration::from_secs(5)))
                    .unwrap();
                let connection = rustls::ServerConnection::new(Arc::new(config.clone())).unwrap();
                let mut tls = rustls::StreamOwned::new(connection, socket);
                let mut byte = [0];
                if accepted {
                    tls.read_exact(&mut byte).unwrap();
                    assert_eq!(byte, [42]);
                    tls.write_all(&[43]).unwrap();
                    tls.flush().unwrap();
                } else {
                    assert!(
                        tls.read(&mut byte).is_err(),
                        "untrusted certificate was accepted"
                    );
                }
            }
        });
        let mut roots = rustls::RootCertStore::empty();
        roots.add(cert).unwrap();
        let config = rustls::ClientConfig::builder_with_provider(provider)
            .with_safe_default_protocol_versions()
            .unwrap()
            .with_root_certificates(roots)
            .with_no_client_auth();
        let connection = rustls::ClientConnection::new(
            Arc::new(config),
            ServerName::try_from("localhost").unwrap(),
        )
        .unwrap();
        let socket =
            std::net::TcpStream::connect_timeout(&address, Duration::from_secs(5)).unwrap();
        socket
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        socket
            .set_write_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        let mut tls = rustls::StreamOwned::new(connection, socket);
        tls.write_all(&[42]).unwrap();
        tls.flush().unwrap();
        let mut byte = [0];
        tls.read_exact(&mut byte).unwrap();
        assert_eq!(byte, [43]);
        drop(tls);

        // The actual HTTP connector trusts WebPKI roots, so our test certificate
        // must fail even though the same ring implementation completed TLS above.
        TOKIO_RUNTIME.block_on(async {
            let client: hyper_util::client::legacy::Client<_, http_body_util::Full<bytes::Bytes>> =
                hyper_util::client::legacy::Client::builder(hyper_util::rt::TokioExecutor::new())
                    .build(https_connector());
            let request = hyper::Request::builder()
                .uri(format!("https://localhost:{}/", address.port()))
                .body(http_body_util::Full::new(bytes::Bytes::new()))
                .unwrap();
            assert!(
                tokio::time::timeout(Duration::from_secs(5), client.request(request))
                    .await
                    .unwrap()
                    .is_err()
            );
        });
        server.join().unwrap();
    }

    fn request_args(
        method: u8,
        method_ext: &str,
        uri: &str,
        headers: &[(&str, &str)],
        host: &RocHost,
    ) -> HostHttpSendRequestArgs {
        let headers: Vec<(String, String)> = headers
            .iter()
            .map(|(name, value)| (name.to_string(), value.to_string()))
            .collect();
        HostHttpSendRequestArgs {
            timeout_ms: 0,
            body: roc_u8_list_from_slice(b"payload", host),
            headers: build_roc_headers(&headers, host),
            method_ext: RocStr::from_str(method_ext, host),
            uri: RocStr::from_str(uri, host),
            method,
        }
    }

    fn content_types(args: HostHttpSendRequestArgs, host: &RocHost) -> Vec<String> {
        let request = build_hyper_request((&args).into()).unwrap();
        unsafe { args.decref(host) };
        request
            .headers()
            .get_all("content-type")
            .iter()
            .map(|value| value.to_str().unwrap().to_string())
            .collect()
    }

    // Serves one connection after consuming the request head, so closing the
    // socket cannot reset it while the client is still writing.
    fn local_server(
        handler: impl FnOnce(TcpStream) + Send + 'static,
    ) -> (String, thread::JoinHandle<()>) {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let uri = format!(
            "http://127.0.0.1:{}/",
            listener.local_addr().unwrap().port()
        );
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut head = Vec::new();
            let mut byte = [0u8; 1];
            while !head.ends_with(b"\r\n\r\n") && stream.read(&mut byte).unwrap() == 1 {
                head.push(byte[0]);
            }
            handler(stream);
        });
        (uri, server)
    }

    fn get(uri: &str, timeout_ms: u64, host: &RocHost) -> HttpResult {
        let request = hyper::Request::builder()
            .uri(uri)
            .body(http_body_util::Full::default())
            .unwrap();
        send_request(request, timeout_ms, host)
    }

    fn transport_err_tag(result: HttpResult, host: &RocHost) -> HttpTransportErrTag {
        assert!(result.tag == HttpResultTag::Err);
        let tag = unsafe { result.payload.err.tag };
        unsafe { result.decref(host) };
        tag
    }

    // Mirrors `to_host_method` in platform/InternalHttp.roc: the two tables can
    // only drift apart silently, since the method crosses the ABI as a bare `U8`.
    #[test]
    fn method_tags_match_the_platform_encoding() {
        let expected = [
            (0, hyper::Method::CONNECT),
            (1, hyper::Method::DELETE),
            (3, hyper::Method::GET),
            (4, hyper::Method::HEAD),
            (5, hyper::Method::OPTIONS),
            (6, hyper::Method::PATCH),
            (7, hyper::Method::POST),
            (8, hyper::Method::PUT),
            (9, hyper::Method::TRACE),
        ];
        for (tag, method) in expected {
            // Only the extension tag reads `method_ext`.
            assert_eq!(as_hyper_method(tag, "IGNORED"), Some(method));
        }
        assert_eq!(
            as_hyper_method(2, "QUERY")
                .as_ref()
                .map(hyper::Method::as_str),
            Some("QUERY")
        );
        assert_eq!(as_hyper_method(2, "not a token"), None);
        assert_eq!(as_hyper_method(2, ""), None);
        assert_eq!(as_hyper_method(10, "GET"), None);
    }

    #[test]
    fn request_preserves_resolved_content_type_without_adding_defaults() {
        let host = crate::resources::make_host();
        let uri = "http://example.invalid/";

        let defaulted = request_args(7, "", uri, &[("Accept", "*/*")], &host);
        assert!(content_types(defaulted, &host).is_empty());

        let explicit = request_args(7, "", uri, &[("content-TYPE", "application/json")], &host);
        assert_eq!(content_types(explicit, &host), ["application/json"]);
    }

    #[test]
    fn unbuildable_requests_report_why() {
        let host = crate::resources::make_host();
        let uri = "http://example.invalid/";
        let rejects = |method, method_ext, uri, headers| {
            let args = request_args(method, method_ext, uri, headers, &host);
            let error = build_hyper_request((&args).into()).unwrap_err();
            unsafe { args.decref(&host) };
            assert!(!error.is_empty());
        };
        rejects(10, "", uri, &[]);
        rejects(2, "not a token", uri, &[]);
        rejects(3, "", "http://exa mple.invalid/", &[]);
        rejects(3, "", uri, &[("bad name", "value")]);
    }

    #[test]
    fn redirect_header_metadata_preserves_utf8_and_reports_invalid_bytes() {
        let mut headers = hyper::HeaderMap::new();
        headers.append(
            "Location",
            hyper::header::HeaderValue::from_bytes("/caf\u{e9}".as_bytes()).unwrap(),
        );
        assert_eq!(invalid_location(&headers), None);
        assert_eq!(
            header_pairs(&headers),
            [("location".into(), "/caf\u{e9}".into())]
        );
        headers.append(
            "Location",
            hyper::header::HeaderValue::from_bytes(b"/bad\xff").unwrap(),
        );
        assert_eq!(invalid_location(&headers), Some(255));
    }

    #[test]
    fn response_status_headers_and_body_reach_roc() {
        let host = crate::resources::make_host();
        let (uri, server) = local_server(|mut stream| {
            stream
                .write_all(
                    b"HTTP/1.1 404 Not Found\r\nX-Test: yes\r\nContent-Length: 4\r\n\r\nbody",
                )
                .unwrap();
        });

        let result = get(&uri, 5_000, &host);
        server.join().unwrap();

        assert!(result.tag == HttpResultTag::Ok);
        {
            let response = unsafe { &result.payload.ok };
            assert_eq!(response.status, 404);
            assert_eq!(response.body.as_slice(), b"body");
            assert!(response
                .headers
                .as_slice()
                .iter()
                .any(|header| header._0.as_str() == "x-test" && header._1.as_str() == "yes"));
        }
        unsafe { result.decref(&host) };
    }

    #[test]
    fn stalled_response_maps_to_timeout() {
        let host = crate::resources::make_host();
        let (release_tx, release_rx) = mpsc::channel::<()>();
        let (uri, server) = local_server(move |_stream| {
            let _ = release_rx.recv();
        });

        let result = get(&uri, 50, &host);
        drop(release_tx);
        server.join().unwrap();

        assert!(transport_err_tag(result, &host) == HttpTransportErrTag::Timeout);
    }

    #[test]
    fn truncated_body_maps_to_bad_body() {
        let host = crate::resources::make_host();
        let (uri, server) = local_server(|mut stream| {
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhi")
                .unwrap();
        });

        let result = get(&uri, 5_000, &host);
        server.join().unwrap();

        assert!(transport_err_tag(result, &host) == HttpTransportErrTag::BadBody);
    }

    #[test]
    fn refused_connection_maps_to_other_with_a_message() {
        let host = crate::resources::make_host();
        // Bind then drop, so the port is known to have no listener.
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let uri = format!(
            "http://127.0.0.1:{}/",
            listener.local_addr().unwrap().port()
        );
        drop(listener);

        let result = get(&uri, 5_000, &host);

        assert!(result.tag == HttpResultTag::Err);
        {
            let error = unsafe { &result.payload.err };
            assert!(error.tag == HttpTransportErrTag::Other);
            assert!(!unsafe { &error.payload.other }.as_slice().is_empty());
        }
        unsafe { result.decref(&host) };
    }

    // ---- Streaming responses ------------------------------------------------

    fn open_stream(
        uri: &str,
        timeout_ms: u64,
        idle_timeout: Option<Duration>,
    ) -> Result<(StreamingHead, StreamingBody), Failure> {
        let request = hyper::Request::builder()
            .uri(uri)
            .body(http_body_util::Full::default())
            .unwrap();
        send_streaming(request, timeout_ms, idle_timeout)
    }

    /// An idle timeout for tests that wait for it to expire. Long enough that
    /// a loaded machine still delivers a local response inside it.
    const IDLE: Duration = Duration::from_millis(250);

    fn pattern(len: usize) -> Vec<u8> {
        (0..len).map(|i| (i % 251) as u8).collect()
    }

    fn chunked(parts: &[&[u8]]) -> Vec<u8> {
        let mut encoded = Vec::new();
        for part in parts {
            encoded.extend(format!("{:x}\r\n", part.len()).as_bytes());
            encoded.extend(*part);
            encoded.extend(b"\r\n");
        }
        encoded.extend(b"0\r\n\r\n");
        encoded
    }

    /// Read chunks to the end of the body, checking the size rule on each.
    fn drain(body: &mut StreamingBody) -> Vec<u8> {
        let mut bytes = Vec::new();
        while let Some(chunk) = body.read_chunk().unwrap() {
            assert!(!chunk.is_empty() && chunk.len() <= MAX_CHUNK_BYTES);
            bytes.extend(chunk);
        }
        bytes
    }

    /// Whether the peer closes or resets the connection within the read timeout.
    fn peer_closed(stream: &mut TcpStream) -> bool {
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        let mut sink = [0u8; 64];
        loop {
            match stream.read(&mut sink) {
                Ok(0) => return true,
                Ok(_) => continue,
                Err(error) => {
                    return !matches!(
                        error.kind(),
                        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                    )
                }
            }
        }
    }

    #[test]
    fn wait_budget_is_the_idle_timeout_cut_short_by_the_deadline() {
        let now = Instant::now();
        let secs = Duration::from_secs;
        assert_eq!(wait_budget(None, None, now), Ok(None));
        assert_eq!(wait_budget(Some(secs(3)), None, now), Ok(Some(secs(3))));
        assert_eq!(
            wait_budget(None, Some(now + secs(9)), now),
            Ok(Some(secs(9)))
        );
        assert_eq!(
            wait_budget(Some(secs(3)), Some(now + secs(9)), now),
            Ok(Some(secs(3)))
        );
        assert_eq!(
            wait_budget(Some(secs(30)), Some(now + secs(9)), now),
            Ok(Some(secs(9)))
        );
        // A deadline that has arrived leaves no time, whatever the idle timeout.
        assert_eq!(wait_budget(Some(secs(3)), Some(now), now), Err(()));
        assert_eq!(wait_budget(None, Some(now), now + secs(1)), Err(()));
    }

    #[test]
    fn content_length_comes_from_the_header_unless_the_body_is_encoded() {
        let headers = |pairs: &[(&'static str, &'static str)]| {
            let mut map = hyper::HeaderMap::new();
            for (name, value) in pairs {
                map.append(*name, hyper::header::HeaderValue::from_static(value));
            }
            map
        };
        assert_eq!(declared_content_length(&headers(&[])), None);
        assert_eq!(
            declared_content_length(&headers(&[("content-length", "0")])),
            Some(0)
        );
        assert_eq!(
            declared_content_length(&headers(&[("Content-Length", " 1048576 ")])),
            Some(1_048_576)
        );
        assert_eq!(
            declared_content_length(&headers(&[
                ("content-length", "7"),
                ("content-length", "7")
            ])),
            Some(7)
        );
        for unusable in [
            &[("content-length", "7"), ("content-length", "8")][..],
            &[("content-length", "seven")],
            &[("content-length", "-1")],
            &[("content-length", "7"), ("transfer-encoding", "chunked")],
            &[("transfer-encoding", "chunked")],
        ] {
            assert_eq!(declared_content_length(&headers(unusable)), None);
        }
    }

    #[test]
    fn streaming_returns_the_head_before_the_body_has_been_sent() {
        let body = pattern(200_000);
        let sent = body.clone();
        let (send_rest_tx, send_rest_rx) = mpsc::channel::<()>();
        let (uri, server) = local_server(move |mut stream| {
            stream
                .write_all(
                    format!(
                        "HTTP/1.1 404 Not Found\r\nX-Test: yes\r\nContent-Length: {}\r\n\r\n",
                        sent.len()
                    )
                    .as_bytes(),
                )
                .unwrap();
            stream.write_all(&sent[..10]).unwrap();
            // Nothing more until the client has looked at the head.
            send_rest_rx.recv().unwrap();
            stream.write_all(&sent[10..]).unwrap();
            // The connection is released at the end of the body, not when the
            // response is dropped: the test still holds it below.
            assert!(peer_closed(&mut stream));
        });

        let (head, mut stream) = open_stream(&uri, 0, Some(Duration::from_secs(5))).unwrap();
        // Any status is a response, and its head is here while the body is not.
        assert_eq!(head.status, 404);
        assert_eq!(head.content_length, Some(200_000));
        assert!(head
            .headers
            .iter()
            .any(|(name, value)| name == "x-test" && value == "yes"));
        assert_eq!(&stream.read_chunk().unwrap().unwrap()[..], &body[..10]);
        send_rest_tx.send(()).unwrap();

        let mut received = body[..10].to_vec();
        received.extend(drain(&mut stream));
        assert_eq!(received, body);
        // The end is reported again, by both kinds of read.
        assert_eq!(stream.read_chunk(), Ok(None));
        assert_eq!(stream.read_to_end(0), Ok(bytes::Bytes::new()));
        server.join().unwrap();
    }

    #[test]
    fn chunks_are_never_empty_or_larger_than_64_kib() {
        let body = pattern(300_000);
        // One encoded chunk far larger than 64 KiB between two small ones.
        let wire = chunked(&[&body[..1], &body[1..250_000], &body[250_000..]]);
        let (uri, server) = local_server(move |mut stream| {
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
                .unwrap();
            stream.write_all(&wire).unwrap();
            assert!(peer_closed(&mut stream));
        });

        let (head, mut stream) = open_stream(&uri, 0, Some(Duration::from_secs(5))).unwrap();
        assert_eq!(head.status, 200);
        assert_eq!(head.content_length, None);
        assert_eq!(drain(&mut stream), body);
        assert_eq!(stream.read_chunk(), Ok(None));
        server.join().unwrap();
    }

    #[test]
    fn an_idle_timeout_leaves_the_response_usable() {
        let (resume_tx, resume_rx) = mpsc::channel::<()>();
        let (uri, server) = local_server(move |mut stream| {
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello")
                .unwrap();
            resume_rx.recv().unwrap();
            stream.write_all(b" ").unwrap();
            resume_rx.recv().unwrap();
            stream.write_all(b"world").unwrap();
        });

        let (_, mut stream) = open_stream(&uri, 0, Some(IDLE)).unwrap();
        assert_eq!(&stream.read_chunk().unwrap().unwrap()[..], b"hello");
        let started = Instant::now();
        assert_eq!(stream.read_chunk(), Err(Failure::Timeout));
        assert!(started.elapsed() >= IDLE);
        // Not final: the same wait can be repeated, and times out again.
        assert_eq!(stream.read_chunk(), Err(Failure::Timeout));
        assert!(matches!(stream.state, BodyState::Open(_)));

        resume_tx.send(()).unwrap();
        assert_eq!(&stream.read_chunk().unwrap().unwrap()[..], b" ");
        // `read_to_end` keeps what it has when it times out ...
        assert_eq!(
            stream.read_to_end(u64::MAX),
            Err(ReadToEndErr::Failed(Failure::Timeout))
        );
        resume_tx.send(()).unwrap();
        // ... so nothing is lost by asking again.
        assert_eq!(&stream.read_to_end(u64::MAX).unwrap()[..], b"world");
        assert_eq!(stream.read_chunk(), Ok(None));
        server.join().unwrap();
    }

    #[test]
    fn read_to_end_keeps_collected_bytes_across_an_idle_timeout() {
        let (resume_tx, resume_rx) = mpsc::channel::<()>();
        let (uri, server) = local_server(move |mut stream| {
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\nhalf")
                .unwrap();
            resume_rx.recv().unwrap();
            stream.write_all(b"time").unwrap();
        });

        let (_, mut stream) = open_stream(&uri, 0, Some(IDLE)).unwrap();
        assert_eq!(
            stream.read_to_end(u64::MAX),
            Err(ReadToEndErr::Failed(Failure::Timeout))
        );
        resume_tx.send(()).unwrap();
        assert_eq!(&stream.read_to_end(u64::MAX).unwrap()[..], b"halftime");
        server.join().unwrap();
    }

    #[test]
    fn an_expired_wait_does_not_poll_ready_io() {
        let mut polled = false;
        let result = TOKIO_RUNTIME.block_on(await_io(Some(Instant::now()), async {
            polled = true;
        }));
        assert_eq!(result, Err(Failure::Timeout));
        assert!(!polled);
    }

    #[test]
    fn interruption_precedes_timeout_and_sends_nothing() {
        struct Reset;
        impl Drop for Reset {
            fn drop(&mut self) {
                crate::signals::set_test_pending(false);
            }
        }
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        listener.set_nonblocking(true).unwrap();
        let uri = format!("http://{}/", listener.local_addr().unwrap());
        let _reset = Reset;
        crate::signals::set_test_pending(true);
        let mut polled = false;
        let result = TOKIO_RUNTIME.block_on(await_io(Some(Instant::now()), async {
            polled = true;
        }));
        assert_eq!(result, Err(Failure::Interrupted));
        assert!(!polled);
        assert_eq!(
            open_stream(&uri, 1, Some(Duration::ZERO)).err(),
            Some(Failure::Interrupted)
        );
        assert_eq!(
            listener.accept().unwrap_err().kind(),
            std::io::ErrorKind::WouldBlock
        );
        let host = crate::resources::make_host();
        assert!(transport_err_tag(get(&uri, 1, &host), &host) == HttpTransportErrTag::Interrupted);
    }

    #[test]
    fn interrupted_body_reads_keep_the_cursor_and_collected_prefix() {
        struct Reset;
        impl Drop for Reset {
            fn drop(&mut self) {
                crate::signals::set_test_pending(false);
            }
        }
        let (resume_tx, resume_rx) = mpsc::channel::<()>();
        let (uri, server) = local_server(move |mut stream| {
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\nhalf")
                .unwrap();
            resume_rx.recv().unwrap();
            stream.write_all(b"time").unwrap();
        });
        let (_, mut stream) = open_stream(&uri, 0, Some(IDLE)).unwrap();
        assert_eq!(
            stream.read_to_end(u64::MAX),
            Err(ReadToEndErr::Failed(Failure::Timeout))
        );
        assert_eq!(&stream.pending[..], b"half");
        let reset = Reset;
        crate::signals::set_test_pending(true);
        assert_eq!(stream.read_chunk(), Err(Failure::Interrupted));
        assert_eq!(
            stream.read_to_end(u64::MAX),
            Err(ReadToEndErr::Failed(Failure::Interrupted))
        );
        assert_eq!(&stream.pending[..], b"half");
        assert!(matches!(stream.state, BodyState::Open(_)));
        drop(reset);
        resume_tx.send(()).unwrap();
        assert_eq!(&stream.read_to_end(u64::MAX).unwrap()[..], b"halftime");
        server.join().unwrap();
    }

    #[test]
    fn an_expired_deadline_prevents_consuming_buffered_body_bytes() {
        let (resume_tx, resume_rx) = mpsc::channel::<()>();
        let (uri, server) = local_server(move |mut stream| {
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\nhalf")
                .unwrap();
            let _ = resume_rx.recv();
        });
        let (_, mut stream) = open_stream(&uri, 0, Some(IDLE)).unwrap();
        assert_eq!(
            stream.read_to_end(u64::MAX),
            Err(ReadToEndErr::Failed(Failure::Timeout))
        );
        assert_eq!(&stream.pending[..], b"half");
        stream.deadline = Some(Instant::now());
        assert_eq!(stream.read_chunk(), Err(Failure::Timeout));
        assert!(matches!(stream.state, BodyState::Failed(Failure::Timeout)));
        drop(resume_tx);
        server.join().unwrap();
    }

    #[test]
    fn read_to_end_returns_the_remainder_and_enforces_its_limit() {
        let body = pattern(100_000);
        let sent = body.clone();
        let (uri, server) = local_server(move |mut stream| {
            stream
                .write_all(
                    format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n", sent.len()).as_bytes(),
                )
                .unwrap();
            stream.write_all(&sent).unwrap();
        });

        let (_, mut stream) = open_stream(&uri, 0, Some(Duration::from_secs(5))).unwrap();
        let first = stream.read_chunk().unwrap().unwrap();
        let unread = body.len() - first.len();

        // Fails once more than the limit has arrived, however often it is asked.
        assert_eq!(stream.read_to_end(10), Err(ReadToEndErr::LimitExceeded));
        assert_eq!(stream.read_to_end(10), Err(ReadToEndErr::LimitExceeded));
        assert_eq!(
            stream.read_to_end(unread as u64 - 1),
            Err(ReadToEndErr::LimitExceeded)
        );
        // The limit consumed nothing: chunks and a large enough limit see the
        // same bytes, in order, from the one cursor.
        let second = stream.read_chunk().unwrap().unwrap();
        assert!(!second.is_empty() && second.len() <= MAX_CHUNK_BYTES);
        let unread = unread - second.len();
        let rest = stream.read_to_end(unread as u64).unwrap();
        assert_eq!(rest.len(), unread);
        assert_eq!([&first[..], &second[..], &rest[..]].concat(), body);
        assert_eq!(stream.read_to_end(0), Ok(bytes::Bytes::new()));
        assert_eq!(stream.read_chunk(), Ok(None));
        server.join().unwrap();
    }

    #[test]
    fn the_request_timeout_is_a_deadline_for_the_whole_body_and_is_final() {
        let (release_tx, release_rx) = mpsc::channel::<()>();
        let (uri, server) = local_server(move |mut stream| {
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello")
                .unwrap();
            // The client gives the connection up when the deadline passes.
            assert!(peer_closed(&mut stream));
            let _ = release_rx.recv();
        });

        // No idle timeout: only the deadline can end the wait.
        let (_, mut stream) = open_stream(&uri, 400, None).unwrap();
        assert_eq!(&stream.read_chunk().unwrap().unwrap()[..], b"hello");
        let started = Instant::now();
        assert_eq!(stream.read_chunk(), Err(Failure::Timeout));
        assert!(started.elapsed() < Duration::from_secs(5));
        // Final: every later read reports it again, without waiting.
        assert!(matches!(stream.state, BodyState::Failed(Failure::Timeout)));
        assert_eq!(stream.read_chunk(), Err(Failure::Timeout));
        assert_eq!(
            stream.read_to_end(u64::MAX),
            Err(ReadToEndErr::Failed(Failure::Timeout))
        );
        drop(release_tx);
        server.join().unwrap();

        // An idle timeout longer than what is left of the deadline is cut short
        // by it, and the failure is the deadline's, so it is final too.
        let (release_tx, release_rx) = mpsc::channel::<()>();
        let (uri, server) = local_server(move |mut stream| {
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\n")
                .unwrap();
            let _ = release_rx.recv();
        });
        let (_, mut stream) = open_stream(&uri, 400, Some(Duration::from_secs(60))).unwrap();
        assert_eq!(stream.read_chunk(), Err(Failure::Timeout));
        assert!(matches!(stream.state, BodyState::Failed(Failure::Timeout)));
        drop(release_tx);
        server.join().unwrap();
    }

    #[test]
    fn waiting_for_the_head_is_bounded_by_both_timeouts() {
        for (timeout_ms, idle_timeout) in [
            (0, Some(Duration::from_millis(50))),
            (50, None),
            (50, Some(Duration::from_secs(60))),
        ] {
            let (release_tx, release_rx) = mpsc::channel::<()>();
            let (uri, server) = local_server(move |_stream| {
                let _ = release_rx.recv();
            });
            let result = open_stream(&uri, timeout_ms, idle_timeout);
            assert_eq!(result.err(), Some(Failure::Timeout));
            drop(release_tx);
            server.join().unwrap();
        }
    }

    #[test]
    fn a_zero_idle_timeout_expires_before_anything_is_sent() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        listener.set_nonblocking(true).unwrap();
        let uri = format!(
            "http://127.0.0.1:{}/",
            listener.local_addr().unwrap().port()
        );
        let result = open_stream(&uri, 0, Some(Duration::ZERO));
        assert_eq!(result.err(), Some(Failure::Timeout));
        // Nobody connected.
        assert_eq!(
            listener.accept().unwrap_err().kind(),
            std::io::ErrorKind::WouldBlock
        );
        // A zero `Request` timeout, by contrast, means no deadline.
        drop(listener);
        let (uri, server) = local_server(|mut stream| {
            stream
                .write_all(b"HTTP/1.1 204 No Content\r\n\r\n")
                .unwrap();
        });
        let (head, mut stream) = open_stream(&uri, 0, None).unwrap();
        assert_eq!(head.status, 204);
        assert_eq!(head.content_length, None);
        assert_eq!(stream.read_chunk(), Ok(None));
        server.join().unwrap();
    }

    #[test]
    fn a_broken_body_is_reported_by_every_later_read() {
        let (uri, server) = local_server(|mut stream| {
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhi")
                .unwrap();
        });
        let (head, mut stream) = open_stream(&uri, 0, Some(Duration::from_secs(5))).unwrap();
        server.join().unwrap();
        assert_eq!(head.content_length, Some(10));
        assert_eq!(&stream.read_chunk().unwrap().unwrap()[..], b"hi");
        assert_eq!(stream.read_chunk(), Err(Failure::BadBody));
        assert_eq!(stream.read_chunk(), Err(Failure::BadBody));
        assert_eq!(
            stream.read_to_end(u64::MAX),
            Err(ReadToEndErr::Failed(Failure::BadBody))
        );
    }

    #[test]
    fn failing_to_connect_reports_why() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let uri = format!(
            "http://127.0.0.1:{}/",
            listener.local_addr().unwrap().port()
        );
        drop(listener);
        match open_stream(&uri, 5_000, Some(Duration::from_secs(5))).err() {
            Some(Failure::Other(message)) => assert!(!message.is_empty()),
            other => panic!("expected a connection error, got {other:?}"),
        }
    }

    // Both ways of giving a body up before its end must close the socket
    // without another hosted call: dropping the resource directly, and
    // releasing the last reference to its handle through the allocator.
    #[test]
    fn dropping_an_unread_response_closes_its_connection() {
        for through_handle in [false, true] {
            let (closed_tx, closed_rx) = mpsc::channel::<bool>();
            let (uri, server) = local_server(move |mut stream| {
                stream
                    .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 1000000\r\n\r\npart")
                    .unwrap();
                closed_tx.send(peer_closed(&mut stream)).unwrap();
            });

            let (_, mut stream) = open_stream(&uri, 0, None).unwrap();
            assert_eq!(&stream.read_chunk().unwrap().unwrap()[..], b"part");
            if through_handle {
                let host = crate::resources::make_host();
                let handle = crate::resources::box_resource(stream, &host).unwrap();
                crate::resources::release(handle, &host);
            } else {
                drop(stream);
            }
            assert_eq!(
                closed_rx.recv_timeout(Duration::from_secs(10)),
                Ok(true),
                "the connection stayed open (through_handle: {through_handle})"
            );
            server.join().unwrap();
        }
    }

    /// The bytes a client puts on the wire for one request.
    fn captured_request(send: impl FnOnce(&str)) -> String {
        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = Vec::new();
            let mut byte = [0u8; 1];
            // The head, then the seven-byte body `request_args` sends.
            while !request.ends_with(b"\r\n\r\npayload") && stream.read(&mut byte).unwrap() == 1 {
                request.push(byte[0]);
            }
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
                .unwrap();
            String::from_utf8(request)
                .unwrap()
                .replace(&port.to_string(), "PORT")
        });
        send(&format!("http://127.0.0.1:{port}/path?query=1"));
        server.join().unwrap()
    }

    #[test]
    fn streaming_sends_the_same_request_as_send() {
        let host = crate::resources::make_host();
        let build = |uri: &str, headers: &[(&str, &str)]| {
            let args = request_args(7, "", uri, headers, &host);
            let request = build_hyper_request((&args).into()).unwrap();
            unsafe { args.decref(&host) };
            request
        };
        for headers in [
            &[][..],
            &[("Content-Type", "application/json"), ("X-A", "b")],
        ] {
            let buffered = captured_request(|uri| {
                let result = send_request(build(uri, headers), 5_000, &host);
                assert!(result.tag == HttpResultTag::Ok);
                unsafe { result.decref(&host) };
            });
            let streamed = captured_request(|uri| {
                let (head, mut stream) =
                    send_streaming(build(uri, headers), 5_000, Some(Duration::from_secs(5)))
                        .unwrap();
                assert_eq!(head.status, 200);
                assert_eq!(stream.read_chunk(), Ok(None));
            });
            assert_eq!(streamed, buffered);
            assert!(buffered.starts_with("POST /path?query=1 HTTP/1.1\r\n"));
            assert!(buffered.ends_with("\r\n\r\npayload"));
            assert!(!buffered
                .to_ascii_lowercase()
                .contains("content-type: text/plain\r\n"));
        }
    }

    // The two argument shapes the glue generates for the request record must
    // stay field-for-field the same, since one builder reads both.
    #[test]
    fn both_request_records_build_the_same_request() {
        let host = crate::resources::make_host();
        let args = request_args(2, "QUERY", "http://example.invalid/x", &[("A", "b")], &host);
        let record = HostHttpSendStreamingArg0 {
            timeout_ms: args.timeout_ms,
            body: args.body,
            headers: args.headers,
            method_ext: args.method_ext,
            uri: args.uri,
            method: args.method,
        };
        let from_args = build_hyper_request((&args).into()).unwrap();
        let from_record = build_hyper_request((&record).into()).unwrap();
        assert_eq!(from_args.method(), from_record.method());
        assert_eq!(from_args.method().as_str(), "QUERY");
        assert_eq!(from_args.uri(), from_record.uri());
        assert_eq!(from_args.headers(), from_record.headers());
        // `record` shares the Roc values with `args`; release them once.
        unsafe { args.decref(&host) };
    }

    // Guards the shape of `TOKIO_RUNTIME`: a thread that used it must be able to
    // exit while the blocking pool still holds work. An owned runtime blocks in
    // `Drop` until every pool thread acknowledges the shutdown, which is the
    // Windows exit hang described above the static. A blocking task held until
    // after the join stands in for a pool thread that cannot acknowledge.
    //
    // This only covers the declaration; the exit path itself is covered by the
    // `http-client` run cases in scripts/test_spec.json, which reach the test
    // server by host name and so actually put work on the blocking pool.
    #[test]
    fn thread_exit_does_not_wait_for_the_blocking_pool() {
        // Generous: the passing case finishes in microseconds. This only has to
        // be shorter than a hang, which never ends.
        const EXIT_BUDGET: Duration = Duration::from_secs(5);

        let (release_tx, release_rx) = mpsc::channel::<()>();
        let user = thread::spawn(move || {
            TOKIO_RUNTIME.spawn_blocking(move || {
                let _ = release_rx.recv();
            });
        });

        let (exited_tx, exited_rx) = mpsc::channel::<()>();
        let watcher = thread::spawn(move || {
            let _ = user.join();
            let _ = exited_tx.send(());
        });

        let exited = exited_rx.recv_timeout(EXIT_BUDGET).is_ok();
        // Release the pool before asserting, so a failure unwinds instead of
        // leaving `user` parked in `Drop` and `watcher` joined to it forever.
        drop(release_tx);
        watcher.join().expect("watcher thread panicked");

        assert!(
            exited,
            "a thread that used the HTTP runtime hung on exit while a blocking task was running"
        );
    }
}
