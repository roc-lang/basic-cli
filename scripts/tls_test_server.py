#!/usr/bin/env python3
"""Local TLS helper servers used by the TLS example test.

Serves the self-signed `localhost` certificate from tests/tls over TLS:
  * 8443: echo server; echoes bytes until the client closes, then sends
    close_notify and closes.
  * 9443: HTTPS server; GET /hello -> 200 "ok", GET /redirect -> 302 to
    /hello, GET /redirect-cross -> 302 to https://127.0.0.1:9443/hello (the
    same server under a name the certificate does not cover), anything else
    -> 404.

Both bind ::1 (best effort) and 127.0.0.1. Windows resolves `localhost` to ::1
first, while scripts/test.py polls 127.0.0.1:8443 for readiness, so every other
listener is bound first and 127.0.0.1:8443 last. Handshake failures (clients
rejecting the certificate, plain-TCP readiness probes) never stop the servers.
"""
import socket
import socketserver
import ssl
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

TLS_DIR = Path(__file__).resolve().parent.parent / "tests" / "tls"
ECHO_PORT = 8443
HTTPS_PORT = 9443

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(TLS_DIR / "localhost-cert.pem", TLS_DIR / "localhost-key.pem")


def echo(conn: socket.socket) -> None:
    try:
        with conn:
            conn.settimeout(30)
            try:
                tls = context.wrap_socket(conn, server_side=True)
            except (OSError, ValueError):
                return
            try:
                while True:
                    data = tls.recv(4096)
                    if not data:
                        break
                    tls.sendall(data)
                tls.unwrap()
            except (OSError, ValueError):
                pass
    except OSError:
        pass


def serve_echo(listener: socket.socket) -> None:
    while True:
        try:
            conn, _ = listener.accept()
        except OSError:
            continue
        threading.Thread(target=echo, args=(conn,), daemon=True).start()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:
        if self.path == "/hello":
            self.reply(200, b"ok")
        elif self.path == "/redirect":
            self.reply(302, b"", {"Location": "/hello"})
        elif self.path == "/redirect-cross":
            self.reply(302, b"", {"Location": f"https://127.0.0.1:{HTTPS_PORT}/hello"})
        else:
            self.reply(404, b"not found")

    def reply(self, status: int, body: bytes, headers: dict[str, str] | None = None) -> None:
        self.send_response(status)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        pass


class HttpsServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, family: socket.AddressFamily, host: str) -> None:
        self.address_family = family
        super().__init__((host, HTTPS_PORT), Handler)

    def server_bind(self) -> None:
        # HTTPServer.server_bind also resolves its own name with socket.getfqdn,
        # a reverse DNS lookup that took seconds on macOS CI runners: long enough
        # for scripts/test.py to give up waiting. Nothing here uses the name.
        socketserver.TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name = host
        self.server_port = port

    def finish_request(self, request, client_address) -> None:  # type: ignore[no-untyped-def]
        # Handshake in the per-connection thread so a bad client cannot block accept.
        request.settimeout(30)
        super().finish_request(context.wrap_socket(request, server_side=True), client_address)

    def handle_error(self, request, client_address) -> None:  # type: ignore[no-untyped-def]
        pass


def listen_echo(family: socket.AddressFamily, host: str) -> socket.socket:
    listener = socket.socket(family, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((host, ECHO_PORT))
    listener.listen(16)
    return listener


def main() -> None:
    echo_listeners = []
    https_servers = []
    # The runner's readiness probe polls 127.0.0.1:8443, so that listener comes
    # up last: once it accepts, so does every other one. ::1 is best effort.
    addresses = [(socket.AF_INET6, "::1"), (socket.AF_INET, "127.0.0.1")]
    for family, host in addresses:
        try:
            https_servers.append(HttpsServer(family, host))
        except OSError:
            if family == socket.AF_INET:
                raise
    for family, host in addresses:
        try:
            echo_listeners.append(listen_echo(family, host))
        except OSError:
            if family == socket.AF_INET:
                raise
    for server in https_servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    threads = [threading.Thread(target=serve_echo, args=(l,), daemon=True) for l in echo_listeners]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()


if __name__ == "__main__":
    main()
