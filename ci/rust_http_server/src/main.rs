/// Adapted from hyper examples examples/hello.rs and examples/web_api.rs
/// Licensed under the MIT License.
/// Thank you, hyper contributors!
use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::body::Incoming;
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Method, Request, Response, StatusCode};
use hyper_util::rt::TokioTimer;
use std::net::{Ipv4Addr, Ipv6Addr, SocketAddr};
use tokio::net::TcpListener;

type GenericError = Box<dyn std::error::Error + Send + Sync>;
type BoxBody = http_body_util::combinators::BoxBody<Bytes, hyper::Error>;

fn full<T: Into<Bytes>>(chunk: T) -> BoxBody {
    Full::new(chunk.into())
        .map_err(|never| match never {})
        .boxed()
}

async fn handle_request(req: Request<Incoming>) -> Result<Response<BoxBody>, GenericError> {
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
