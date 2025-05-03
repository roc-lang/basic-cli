use hyper::{Body, Method, Request, Response, Server, StatusCode};
use hyper::service::{make_service_fn, service_fn};
use std::convert::Infallible;

async fn handle_request(req: Request<Body>) -> Result<Response<Body>, Infallible> {
    let response = match (req.method(), req.uri().path()) {
        (&Method::GET, "/utf8test") => {
            // UTF-8 encoded "Hello utf8"
            let utf8_bytes = "Hello utf8".as_bytes().to_vec();
            
            Response::builder()
                .status(StatusCode::OK)
                .header("Content-Type", "text/plain; charset=utf-8")
                .body(Body::from(utf8_bytes))
                .unwrap()
        },
        _ => {
            // Default response (original functionality)
            // output of: Encode.to_bytes({foo: "Hello Json!"}, Json.utf8)
            let json_bytes: Vec<u8> = vec![123, 34, 102, 111, 111, 34, 58, 34, 72, 101, 108, 108, 111, 32, 74, 115, 111, 110, 33, 34, 125];

            Response::builder()
                .status(StatusCode::OK)
                .header("Content-Type", "application/json")
                .body(Body::from(json_bytes))
                .unwrap()
        }
    };

    Ok(response)
}

#[tokio::main]
async fn main() {
    // Address to bind the server to
    let addr = ([127, 0, 0, 1], 8000).into();

    // A service is what handles the actual processing of requests
    let service = make_service_fn(|_conn| async {
        Ok::<_, Infallible>(service_fn(handle_request))
    });

    let server = Server::bind(&addr)
        .serve(service)
        .with_graceful_shutdown(shutdown_signal());

    println!("Listening on http://{}", addr);

    if let Err(e) = server.await {
        eprintln!("server error: {}", e);
    }
}

async fn shutdown_signal() {
    tokio::signal::ctrl_c().await.expect("Failed to install CTRL+C signal handler.");
}
