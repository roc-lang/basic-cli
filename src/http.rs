use core::mem::ManuallyDrop;
use std::sync::LazyLock;

use crate::roc_platform_abi::*;
use crate::{roc_host, roc_u8_list_from_slice};

// The generated glue names the request/response records by anonymous-struct
// number; alias them to stable semantic names. Host ABI headers are `(Str, Str)`
// tuples, rendered as a struct with `_0` (name) and `_1` (value) fields.
type HttpResponse = HostHttpSendRequestOk;
type HttpHeader = HostHttpSendRequestArg0Headers;
type HttpResult = HostHttpSendRequestResult;
type HttpResultPayload = HostHttpSendRequestResultPayload;
type HttpResultTag = HostHttpSendRequestResultTag;
type HttpTransportErr = BadBodyOrNetworkErrorOrOtherOrTimeout;
type HttpTransportErrPayload = BadBodyOrNetworkErrorOrOtherOrTimeoutPayload;
type HttpTransportErrTag = BadBodyOrNetworkErrorOrOtherOrTimeoutTag;

// Deliberately a `static`, so this runtime is never dropped.
//
// hyper resolves host names with `getaddrinfo` on tokio's blocking pool, whose
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
// server by host name; an IP literal skips the resolver, and with it the
// blocking pool, so it cannot reproduce this.
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

fn build_hyper_request(
    args: &HostHttpSendRequestArgs,
) -> Result<hyper::Request<http_body_util::Full<bytes::Bytes>>, String> {
    let method = as_hyper_method(args.method, args.method_ext.as_str())
        .ok_or_else(|| "invalid HTTP method".to_string())?;
    let mut builder = hyper::Request::builder()
        .method(method)
        .uri(args.uri.as_str());

    // Default to text/plain unless the caller already set a Content-Type.
    let mut has_content_type = false;
    for header in args.headers.as_slice() {
        builder = builder.header(header._0.as_str(), header._1.as_str());
        if header._0.as_str().eq_ignore_ascii_case("Content-Type") {
            has_content_type = true;
        }
    }
    if !has_content_type {
        builder = builder.header("Content-Type", "text/plain");
    }

    let body = http_body_util::Full::new(bytes::Bytes::from(args.body.as_slice().to_vec()));
    builder.body(body).map_err(|err| err.to_string())
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

fn https_connector(
) -> hyper_rustls::HttpsConnector<hyper_util::client::legacy::connect::HttpConnector> {
    hyper_rustls::HttpsConnectorBuilder::new()
        .with_webpki_roots()
        .https_or_http()
        .enable_http1()
        .build()
}

async fn async_send_request(
    request: hyper::Request<http_body_util::Full<bytes::Bytes>>,
    roc_host: &RocHost,
) -> HttpResult {
    use http_body_util::BodyExt;
    use hyper_util::client::legacy::Client;
    use hyper_util::rt::TokioExecutor;

    let client: Client<_, http_body_util::Full<bytes::Bytes>> =
        Client::builder(TokioExecutor::new()).build(https_connector());

    match client.request(request).await {
        Ok(response) => {
            let status = response.status().as_u16();
            let pairs: Vec<(String, String)> = response
                .headers()
                .iter()
                .map(|(name, value)| {
                    (
                        name.as_str().to_string(),
                        value.to_str().unwrap_or_default().to_string(),
                    )
                })
                .collect();

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
    let request_result = build_hyper_request(&args);
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
fn send_request(
    request: hyper::Request<http_body_util::Full<bytes::Bytes>>,
    timeout_ms: u64,
    roc_host: &RocHost,
) -> HttpResult {
    if timeout_ms > 0 {
        TOKIO_RUNTIME.block_on(async {
            match tokio::time::timeout(
                std::time::Duration::from_millis(timeout_ms),
                async_send_request(request, roc_host),
            )
            .await
            {
                Ok(response) => response,
                Err(_) => http_err(http_err_timeout()),
            }
        })
    } else {
        TOKIO_RUNTIME.block_on(async_send_request(request, roc_host))
    }
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
        let request = build_hyper_request(&args).unwrap();
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
    fn request_defaults_content_type_only_when_the_caller_set_none() {
        let host = crate::resources::make_host();
        let uri = "http://example.invalid/";

        let defaulted = request_args(7, "", uri, &[("Accept", "*/*")], &host);
        assert_eq!(content_types(defaulted, &host), ["text/plain"]);

        let explicit = request_args(7, "", uri, &[("content-TYPE", "application/json")], &host);
        assert_eq!(content_types(explicit, &host), ["application/json"]);
    }

    #[test]
    fn unbuildable_requests_report_why() {
        let host = crate::resources::make_host();
        let uri = "http://example.invalid/";
        let rejects = |method, method_ext, uri, headers| {
            let args = request_args(method, method_ext, uri, headers, &host);
            let error = build_hyper_request(&args).unwrap_err();
            unsafe { args.decref(&host) };
            assert!(!error.is_empty());
        };
        rejects(10, "", uri, &[]);
        rejects(2, "not a token", uri, &[]);
        rejects(3, "", "http://exa mple.invalid/", &[]);
        rejects(3, "", uri, &[("bad name", "value")]);
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
