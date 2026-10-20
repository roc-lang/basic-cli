/// Adapted from hyper examples examples/hello.rs and examples/web_api.rs
/// Licensed under the MIT License.
/// Thank you, hyper contributors!
use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::body::{Body, Frame, Incoming};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Method, Request, Response, StatusCode};
use hyper_util::rt::TokioTimer;
use std::collections::VecDeque;
use std::future::Future;
use std::net::{Ipv4Addr, Ipv6Addr, SocketAddr};
use std::pin::Pin;
use std::task::{Context, Poll};
use std::time::Duration;
use tokio::net::TcpListener;

type GenericError = Box<dyn std::error::Error + Send + Sync>;
type BoxBody = http_body_util::combinators::BoxBody<Bytes, GenericError>;

fn full<T: Into<Bytes>>(chunk: T) -> BoxBody {
    Full::new(chunk.into())
        .map_err(|never| match never {})
        .boxed()
}

/// One step of a body that is sent piece by piece, without a Content-Length.
enum Part {
    Data(Bytes),
    /// Send nothing for a while. What came before has reached the client.
    Pause(Duration),
    /// Abort the connection, leaving the body incomplete.
    Fail,
}

/// The body behind the `/stream/...` routes that examples/http-download.roc
/// and tests/http-streaming.roc read as it arrives.
struct Parts {
    parts: VecDeque<Part>,
    pause: Option<Pin<Box<tokio::time::Sleep>>>,
}

fn parts(parts: impl IntoIterator<Item = Part>) -> BoxBody {
    Parts {
        parts: parts.into_iter().collect(),
        pause: None,
    }
    .boxed()
}

impl Body for Parts {
    type Data = Bytes;
    type Error = GenericError;

    fn poll_frame(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Option<Result<Frame<Bytes>, GenericError>>> {
        loop {
            if let Some(pause) = self.pause.as_mut() {
                if pause.as_mut().poll(cx).is_pending() {
                    return Poll::Pending;
                }
                self.pause = None;
            }
            match self.parts.pop_front() {
                Some(Part::Data(bytes)) => return Poll::Ready(Some(Ok(Frame::data(bytes)))),
                Some(Part::Pause(duration)) => {
                    self.pause = Some(Box::pin(tokio::time::sleep(duration)))
                }
                Some(Part::Fail) => return Poll::Ready(Some(Err("body aborted".into()))),
                None => return Poll::Ready(None),
            }
        }
    }
}

/// `len` bytes starting `start` bytes into a fixed pattern, so a client can
/// check a body by its length and the sum of its bytes.
fn pattern(start: usize, len: usize) -> Bytes {
    (start..start + len).map(|i| (i % 251) as u8).collect()
}

async fn handle_request(req: Request<Incoming>) -> Result<Response<BoxBody>, GenericError> {
    if req.uri().path().starts_with("/redirect/") {
        return handle_redirect(req).await;
    }
    let response = match (req.method(), req.uri().path()) {
        (&Method::GET, "/utf8test") => {
            // UTF-8 encoded "Hello utf8"
            let utf8_bytes = "Hello utf8".as_bytes().to_vec();

            Response::builder()
                .status(StatusCode::OK)
                .header("Content-Type", "text/plain; charset=utf-8")
                .body(full(Bytes::from(utf8_bytes)))?
        }
        (&Method::GET, "/html") => Response::builder()
            .status(StatusCode::OK)
            .header("Content-Type", "text/html; charset=utf-8")
            .body(full(Bytes::from_static(
                b"<html>\n<body>Basic CLI HTTP test</body>\n</html>",
            )))?,
        (&Method::GET, "/invalid-json") => Response::builder()
            .status(StatusCode::OK)
            .header("Content-Type", "application/json")
            .body(full(Bytes::from_static(b"not-json")))?,
        (&Method::GET, "/invalid-utf8") => Response::builder()
            .status(StatusCode::OK)
            .header("Content-Type", "application/octet-stream")
            .body(full(Bytes::from_static(&[0xff])))?,
        // 200,000 bytes with a Content-Length.
        (&Method::GET, "/stream/sized") => Response::builder()
            .status(StatusCode::OK)
            .header("Content-Type", "application/octet-stream")
            .body(full(pattern(0, 200_000)))?,
        // 300,000 bytes with chunked transfer encoding, in pieces larger than
        // the 64 KiB the platform hands out at a time.
        (&Method::GET, "/stream/chunked") => Response::builder()
            .status(StatusCode::OK)
            .header("Content-Type", "application/octet-stream")
            .body(parts([
                Part::Data(pattern(0, 100_000)),
                Part::Data(pattern(100_000, 150_000)),
                Part::Data(pattern(250_000, 50_000)),
            ]))?,
        // Goes quiet for a second in the middle of the body.
        (&Method::GET, "/stream/slow") => Response::builder()
            .status(StatusCode::OK)
            .header("Content-Type", "text/plain; charset=utf-8")
            .body(parts([
                Part::Data(Bytes::from_static(b"one,")),
                Part::Pause(Duration::from_secs(1)),
                Part::Data(Bytes::from_static(b"two")),
            ]))?,
        // Sends 70,000 bytes, then drops the connection mid-body.
        (&Method::GET, "/stream/broken") => Response::builder()
            .status(StatusCode::OK)
            .header("Content-Type", "application/octet-stream")
            .body(parts([
                Part::Data(pattern(0, 70_000)),
                Part::Pause(Duration::from_millis(300)),
                Part::Fail,
            ]))?,
        (&Method::GET, "/not-found") => Response::builder()
            .status(StatusCode::NOT_FOUND)
            .header("Content-Type", "text/plain; charset=utf-8")
            .body(full(Bytes::from_static(b"nothing here\n")))?,
        (&Method::POST, "/echo-json") => {
            let body = req.into_body().collect().await?.to_bytes();

            Response::builder()
                .status(StatusCode::OK)
                .header("Content-Type", "application/json")
                .body(full(body))?
        }
        _ => {
            // Default JSON response for `{ foo: "Hello Json!" }`.
            let json_bytes: Vec<u8> = vec![
                123, 34, 102, 111, 111, 34, 58, 34, 72, 101, 108, 108, 111, 32, 74, 115, 111, 110,
                33, 34, 125,
            ];

            Response::builder()
                .status(StatusCode::OK)
                .header("Content-Type", "application/json")
                .body(full(Bytes::from(json_bytes)))?
        }
    };

    Ok(response)
}

/// Redirects intentionally keep their bodies unfinished. Following a redirect
/// must close that body and send the next request without collecting it.
fn redirect(status: u16, locations: &[String]) -> Result<Response<BoxBody>, GenericError> {
    let mut response = Response::builder().status(status);
    for location in locations {
        response = response.header("Location", location);
    }
    Ok(response.body(parts([
        Part::Data(Bytes::from_static(b"discard this intermediate body")),
        Part::Pause(Duration::from_secs(60)),
    ]))?)
}

async fn handle_redirect(req: Request<Incoming>) -> Result<Response<BoxBody>, GenericError> {
    let path = req.uri().path().to_owned();
    if path == "/redirect/inspect" {
        let method = req.method().as_str().to_owned();
        let uri = req.uri().to_string();
        let fields = [
            "host",
            "authorization",
            "cookie",
            "proxy-authorization",
            "content-type",
            "user-agent",
            "content-length",
            "x-hop",
            "x-public",
            "expect",
            "digest",
        ];
        let headers: String = fields
            .into_iter()
            .map(|name| {
                format!(
                    "{name}: {}\n",
                    req.headers()
                        .get(name)
                        .map_or("<absent>", |v| v.to_str().unwrap_or("<invalid>"))
                )
            })
            .collect();
        let body = req.into_body().collect().await?.to_bytes();
        let report = format!(
            "method: {method}\nuri: {uri}\nbody: {}\n{headers}",
            String::from_utf8_lossy(&body)
        );
        return Ok(Response::builder()
            .header("X-Request-Method", method)
            .body(full(report))?);
    }
    if path == "/redirect/final" {
        return Ok(Response::new(full("final")));
    }
    if let Some(left) = path.strip_prefix("/redirect/delayed/") {
        tokio::time::sleep(Duration::from_millis(250)).await;
        let left: u8 = left.parse()?;
        return if left == 0 {
            Ok(Response::new(parts([
                Part::Pause(Duration::from_millis(250)),
                Part::Data(Bytes::from_static(b"final")),
            ])))
        } else {
            redirect(302, &[format!("/redirect/delayed/{}", left - 1)])
        };
    }
    if let Some(left) = path.strip_prefix("/redirect/chain/") {
        let left: u8 = left.parse()?;
        return if left == 0 {
            Ok(Response::new(full("final")))
        } else {
            redirect(302, &[format!("/redirect/chain/{}", left - 1)])
        };
    }
    match path.as_str() {
        "/redirect/non-utf8" => {
            return Ok(Response::builder()
                .status(302)
                .header(
                    "Location",
                    hyper::header::HeaderValue::from_bytes(b"/bad\xff")?,
                )
                .body(full("invalid location"))?)
        }
        "/redirect/unicode" => {
            return Ok(Response::builder()
                .status(302)
                .header(
                    "Location",
                    hyper::header::HeaderValue::from_bytes(
                        "/redirect/inspect?name=caf\u{e9}".as_bytes(),
                    )?,
                )
                .body(full("unicode location"))?)
        }
        "/redirect/missing" => {
            return Ok(Response::builder()
                .status(302)
                .body(full("missing-location"))?)
        }
        "/redirect/duplicate" => {
            return redirect(302, &["/redirect/final".into(), "/not-found".into()])
        }
        "/redirect/malformed" => return redirect(302, &["http://[".into()]),
        "/redirect/unsupported" => return redirect(302, &["ftp://example.com/file".into()]),
        "/redirect/not-found" => return redirect(302, &["/not-found".into()]),
        "/redirect/loop" => return redirect(302, &["/redirect/loop".into()]),
        "/redirect/fragment" => return redirect(302, &["/redirect/inspect#never-send".into()]),
        _ => {}
    }
    let segments: Vec<_> = path.trim_start_matches('/').split('/').collect();
    if let ["redirect", status, target] = segments.as_slice() {
        let status: u16 = status.parse()?;
        let location = match *target {
            "echo" => "/redirect/inspect",
            "relative" => "../inspect",
            "cross" => "http://localhost:9000/redirect/inspect",
            "network" => "//localhost:9000/redirect/inspect",
            _ => {
                return Ok(Response::builder()
                    .status(404)
                    .body(full("unknown redirect target"))?)
            }
        };
        return redirect(status, &[location.to_owned()]);
    }
    Ok(Response::builder()
        .status(404)
        .body(full("unknown redirect route"))?)
}

#[tokio::main]
async fn main() -> Result<(), GenericError> {
    // `examples/http-client.roc` reaches this server by host name so the platform
    // actually resolves it, and Windows answers `localhost` with ::1 ahead of
    // 127.0.0.1. Bind both loopback families so either answer connects. IPv6 is
    // best effort: hosts without it fall back to the IPv4 listener.
    //
    // Bind ::1 first. `wait_for_port` in scripts/test.py polls 127.0.0.1 for
    // readiness, so the IPv4 listener has to be the last one to come up.
    let mut listeners = Vec::new();
    for addr in [
        SocketAddr::from((Ipv6Addr::LOCALHOST, 9000)),
        SocketAddr::from((Ipv4Addr::LOCALHOST, 9000)),
    ] {
        match TcpListener::bind(addr).await {
            Ok(listener) => {
                println!("Listening on http://{}", addr);
                listeners.push(listener);
            }
            Err(err) if addr.is_ipv6() => println!("Skipping IPv6 loopback: {}", err),
            Err(err) => return Err(err.into()),
        }
    }

    let accepting: Vec<_> = listeners
        .into_iter()
        .map(|l| tokio::spawn(accept(l)))
        .collect();
    for task in accepting {
        task.await??;
    }

    Ok(())
}

async fn accept(listener: TcpListener) -> Result<(), GenericError> {
    loop {
        // When an incoming TCP connection is received grab a TCP stream for
        // client<->server communication.
        //
        // Note, this is a .await point, this loop will loop forever but is not a busy loop. The
        // .await point allows the Tokio runtime to pull the task off of the thread until the task
        // has work to do. In this case, a connection arrives on the port we are listening on and
        // the task is woken up, at which point the task is then put back on a thread, and is
        // driven forward by the runtime, eventually yielding a TCP stream.
        let (tcp, _) = listener.accept().await?;
        // Use an adapter to access something implementing `tokio::io` traits as if they implement
        // `hyper::rt` IO traits.
        let io = hyper_util::rt::TokioIo::new(tcp);

        // Spin up a new task in Tokio so we can continue to listen for new TCP connection on the
        // current task without waiting for the processing of the HTTP1 connection we just received
        // to finish
        tokio::task::spawn(async move {
            // Handle the connection from the client using HTTP1 and pass any
            // HTTP requests received on that connection to the `hello` function
            if let Err(err) = http1::Builder::new()
                .timer(TokioTimer::new())
                .serve_connection(io, service_fn(handle_request))
                .await
            {
                println!("Error serving connection: {:?}", err);
            }
        });
    }
}
