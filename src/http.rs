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

async fn async_send_request(
    request: hyper::Request<http_body_util::Full<bytes::Bytes>>,
    roc_host: &RocHost,
) -> HttpResult {
    use http_body_util::BodyExt;
    use hyper_rustls::HttpsConnectorBuilder;
    use hyper_util::client::legacy::Client;
    use hyper_util::rt::TokioExecutor;

    let https = HttpsConnectorBuilder::new()
        .with_webpki_roots()
        .https_or_http()
        .enable_http1()
        .build();

    let client: Client<_, http_body_util::Full<bytes::Bytes>> =
        Client::builder(TokioExecutor::new()).build(https);

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

    let request = match request_result {
        Ok(request) => request,
        Err(err) => return http_err(http_err_other(&err, roc_host)),
    };

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
    use std::sync::mpsc;
    use std::thread;
    use std::time::Duration;

    // hyper's default resolver runs getaddrinfo on tokio's blocking pool, so a
    // request to a host name leaves a pool thread alive for up to ten seconds
    // afterwards. Dropping a runtime waits for every pool thread to acknowledge
    // the shutdown. A runtime owned by a thread local is dropped when its
    // thread exits, and on Windows the main thread's thread locals are dropped
    // during ExitProcess, after the OS has already terminated every other
    // thread. Nothing was left to acknowledge, so a program that had sent a
    // request in its last ten seconds never finished exiting.
    //
    // A blocking task held until after the join stands in for the terminated
    // pool thread. Either way the pool cannot acknowledge, and a thread that
    // used the runtime must still be able to exit.
    #[test]
    fn thread_exit_does_not_wait_for_the_blocking_pool() {
        let (release_tx, release_rx) = mpsc::channel::<()>();
        let user = thread::spawn(move || {
            TOKIO_RUNTIME.spawn_blocking(move || {
                let _ = release_rx.recv();
            });
        });

        let (exited_tx, exited_rx) = mpsc::channel::<()>();
        thread::spawn(move || {
            let _ = user.join();
            let _ = exited_tx.send(());
        });
        let exited = exited_rx.recv_timeout(Duration::from_secs(5)).is_ok();
        drop(release_tx);
        assert!(
            exited,
            "a thread that used the HTTP runtime hung on exit while a blocking task was running"
        );
    }
}
