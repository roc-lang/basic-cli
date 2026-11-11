## Exercise the TLS trust options of `Tcp.connect_tls!` and `Http` against the
## local helper servers of scripts/tls_test_server.py, so that scripts/test.py
## can check each trust choice end to end. The only argument is the PEM file of
## the certificate the helper servers present.
app [main!] {
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	pf: platform "../platform/main.roc",
}

import pf.Duration
import pf.Http
import pf.OsStr
import pf.Path
import pf.Stdout
import pf.Tcp
import pf.Tls
import http.Request
import http.Response

check : Bool, Str -> Try({}, [CheckFailed(Str)])
check = |condition, message| if (condition) Ok({}) else Err(CheckFailed(message))

main! : List(OsStr) => Try({}, _)
main! = |args| {
	ca = match args {
		[ca_file] => Path.from_os_str(ca_file).read_bytes!()?
		_ => {
			return Err(MissingCaFile)
		}
	}

	tcp_trust!(ca)?
	Stdout.line!("tcp trust: ok")?
	tcp_bad_pem!(ca)?
	Stdout.line!("tcp bad pem before any network I/O: ok")?
	tcp_streams!(ca)?
	Stdout.line!("tcp reads over tls: ok")?
	http_trust!(ca)?
	Stdout.line!("http trust: ok")?
	http_redirects!(ca)?
	Stdout.line!("http redirects use the trust on every hop: ok")?
	http_streaming!(ca)?
	Stdout.line!("http streaming trust: ok")?
	http_bad_pem!()?
	Stdout.line!("http bad pem before any network I/O: ok")
}

## Connect to the helper's echo server on `host` and port 8443.
connect! : Str, Tls.Trust => Try(Tcp.Connection, [Interrupted, TlsErr(Tls.Err), TcpErr(_)])
connect! = |host, trust| Tcp.connect_tls!(host, 8443, { connect_timeout: Duration.seconds(5), io_timeout: Duration.seconds(5), tls: { trust } })

## Connect and send one line through the echo server.
echoes! : Str, Tls.Trust => Try(Str, _)
echoes! = |host, trust| {
	conn = connect!(host, trust)?
	conn.write_utf8!("ping\n")?
	conn.read_line!()
}

tcp_trust! : List(U8) => Try({}, _)
tcp_trust! = |ca| {
	# The private authority is trusted only when it is added.
	check(echoes!("localhost", AddPem(ca)) == Ok("ping"), "AddPem echoes")?
	check(echoes!("localhost", Default) == Err(TlsErr(UnknownIssuer)), "Default rejects the private certificate")?
	check(echoes!("localhost", DangerAcceptInvalidCerts) == Ok("ping"), "DangerAcceptInvalidCerts echoes")?

	# The certificate names `localhost` only, so an address is a mismatch
	# unless every certificate is accepted.
	check(echoes!("127.0.0.1", AddPem(ca)) == Err(TlsErr(NameMismatch)), "AddPem still checks the name")?
	check(echoes!("127.0.0.1", DangerAcceptInvalidCerts) == Ok("ping"), "DangerAcceptInvalidCerts accepts any name")?

	# The default options trust nothing but the bundled roots.
	defaults = Tcp.connect_tls!("localhost", 8443, { connect_timeout: Duration.seconds(5), io_timeout: Duration.seconds(5) }).map_ok(|_| {})
	check(defaults == Err(TlsErr(UnknownIssuer)), "omitted tls is Default")?
	check(Tls.Err.to_str(UnknownIssuer) != "", "UnknownIssuer describes itself")
}

tcp_bad_pem! : List(U8) => Try({}, _)
tcp_bad_pem! = |_ca| {
	bad = "this is not a PEM file".to_utf8()
	empty_section = "-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----\n".to_utf8()

	# The helper is listening, and nothing is sent to it.
	check(rejects_roots!(AddPem(bad)), "BadPem for text")?
	check(rejects_roots!(AddPem([])), "BadPem for no bytes")?
	check(rejects_roots!(AddPem(empty_section)), "BadPem for a certificate section without a certificate")?

	# Nothing listens on port 1. A connection attempt would be refused, so
	# `BadPem` shows that the roots are rejected before any network I/O.
	options = { connect_timeout: Duration.seconds(5), io_timeout: Duration.seconds(5), tls: { trust: AddPem(bad) } }
	unreachable = match Tcp.connect_tls!("127.0.0.1", 1, options) {
		Err(TlsErr(BadPem(_))) => True
		_ => False
	}
	check(unreachable, "BadPem before connecting")?
	plain = Tcp.connect!("127.0.0.1", 1, { connect_timeout: Duration.seconds(5), io_timeout: Duration.seconds(5) }).map_ok(|_| {})
	check(plain == Err(TcpErr(ConnectionRefused)), "port 1 refuses connections")
}

## Whether connecting to the echo server fails with a described `BadPem`.
rejects_roots! : Tls.Trust => Bool
rejects_roots! = |trust|
	match connect!("localhost", trust) {
		Err(TlsErr(BadPem(message))) => message != ""
		_ => False
	}

tcp_streams! : List(U8) => Try({}, _)
tcp_streams! = |ca| {
	conn = connect!("localhost", AddPem(ca))?

	# Lines, partial lines and bytes arrive as over plain TCP.
	conn.write_utf8!("first\nsecond\npart")?
	check(conn.read_line!() == Ok("first"), "read_line")?
	check(conn.read_until!('\n') == Ok("second\n".to_utf8()), "read_until")?
	conn.write_utf8!("ial\n")?
	check(conn.read_line!() == Ok("partial"), "a line split across writes")?

	conn.write_bytes!([0, 255, 128, 10])?
	check(conn.read_exactly!(3) == Ok([0, 255, 128]), "read_exactly")?
	check(conn.read_up_to!(1) == Ok([10]), "read_up_to")?

	# Nothing more was sent, so a short timeout expires and consumes nothing.
	idle = conn.with_timeout(Duration.millis(50)).read_line!()
	check(idle == Err(TcpErr(TimedOut)), "idle read times out")?

	conn.write_utf8!("a\nb\nc\n")?
	var $seen = []
	for! item in conn.lines() {
		match item {
			Ok(line) => {
				$seen = $seen.append(line)
			}
			Err(_) => {
				return Err(CheckFailed("lines item"))
			}
		}
		if $seen.len() == 3 {
			break
		}
	}
	check($seen == ["a", "b", "c"], "lines")?

	# 64 KiB spans several TLS records in each direction.
	big = Str.repeat("0123456789abcdef", 4096)
	conn.write_utf8!("${big}\n")?
	check(conn.read_line!() == Ok(big), "a 64 KiB line")
}

get : Str -> Request
get = |path| Request.from_method(GET).with_uri("https://localhost:9443${path}")

text : Response -> Str
text = |response| Str.from_utf8_lossy(Response.body(response))

http_trust! : List(U8) => Try({}, _)
http_trust! = |ca| {
	trusted = Http.send!(get("/hello"), { tls: { trust: AddPem(ca) } })?
	check(Response.status(trusted) == 200 and text(trusted) == "ok", "AddPem fetches /hello")?

	missing = Http.send!(get("/missing"), { tls: { trust: AddPem(ca) } })?
	check(Response.status(missing) == 404 and text(missing) == "not found", "AddPem reaches a 404")?

	untrusted = Http.send!(get("/hello"), {}).map_ok(|_| {})
	check(untrusted == Err(HttpErr(TlsErr(UnknownIssuer))), "Default rejects the private certificate")?
	explicit_default = Http.send!(get("/hello"), { tls: { trust: Default } }).map_ok(|_| {})
	check(explicit_default == Err(HttpErr(TlsErr(UnknownIssuer))), "Default is the same as omitting tls")?

	accepted = Http.send!(get("/hello"), { tls: { trust: DangerAcceptInvalidCerts } })?
	check(Response.status(accepted) == 200 and text(accepted) == "ok", "DangerAcceptInvalidCerts fetches /hello")?
	body = Http.get_utf8!("https://localhost:9443/hello", { tls: { trust: DangerAcceptInvalidCerts } })?
	check(body == "ok", "get_utf8!")?

	# The certificate is for `localhost`, so the address does not match.
	by_address = Request.from_method(GET).with_uri("https://127.0.0.1:9443/hello")
	mismatch = Http.send!(by_address, { tls: { trust: AddPem(ca) } }).map_ok(|_| {})
	check(mismatch == Err(HttpErr(TlsErr(NameMismatch))), "AddPem still checks the name")
}

http_redirects! : List(U8) => Try({}, _)
http_redirects! = |ca| {
	# Redirects are opt-in, and the first response needs the trust as well.
	first = Http.send!(get("/redirect"), { tls: { trust: AddPem(ca) } })?
	check(Response.status(first) == 302, "the redirect is not followed by default")?

	# The second request is a new TLS connection that must use the same trust.
	followed = Http.send!(get("/redirect"), { max_redirects: 1, tls: { trust: AddPem(ca) } })?
	check(Response.status(followed) == 200 and text(followed) == "ok", "AddPem on both hops")?

	accepted = Http.send!(get("/redirect"), { max_redirects: 1, tls: { trust: DangerAcceptInvalidCerts } })?
	check(Response.status(accepted) == 200 and text(accepted) == "ok", "DangerAcceptInvalidCerts on both hops")?

	untrusted = Http.send!(get("/redirect"), { max_redirects: 1 }).map_ok(|_| {})
	check(untrusted == Err(HttpErr(TlsErr(UnknownIssuer))), "Default rejects the first hop")?

	# The redirect leads to another origin: the same server by address, which the
	# certificate does not name. Trust is checked again on that hop and not
	# inherited from the first.
	cross = Http.send!(get("/redirect-cross"), { max_redirects: 1, tls: { trust: AddPem(ca) } }).map_ok(|_| {})
	check(cross == Err(HttpErr(TlsErr(NameMismatch))), "AddPem checks the name on a cross-origin hop")?
	cross_accepted = Http.send!(get("/redirect-cross"), { max_redirects: 1, tls: { trust: DangerAcceptInvalidCerts } })?
	check(Response.status(cross_accepted) == 200 and text(cross_accepted) == "ok", "DangerAcceptInvalidCerts on a cross-origin hop")
}

http_streaming! : List(U8) => Try({}, _)
http_streaming! = |ca| {
	response = Http.send_streaming!(get("/redirect"), { max_redirects: 1, tls: { trust: AddPem(ca) } })?
	check(response.status() == 200, "streamed status after the redirect")?
	body = response.read_to_end!(NoLimit)?
	check(body == "ok".to_utf8(), "streamed body")?

	untrusted = Http.send_streaming!(get("/hello"), {}).map_ok(|_| {})
	check(untrusted == Err(HttpErr(TlsErr(UnknownIssuer))), "Default rejects a streamed request")?

	accepted = Http.send_streaming!(get("/hello"), { tls: { trust: DangerAcceptInvalidCerts } })?
	check(accepted.read_to_end!(NoLimit) == Ok("ok".to_utf8()), "DangerAcceptInvalidCerts streams")
}

http_bad_pem! : () => Try({}, _)
http_bad_pem! = || {
	# Nothing listens on port 1; the roots are rejected before a connection.
	request = Request.from_method(GET).with_uri("https://127.0.0.1:1/")
	sent = match Http.send!(request, { tls: { trust: AddPem("x".to_utf8()) } }) {
		Err(HttpErr(TlsErr(BadPem(_)))) => True
		_ => False
	}
	check(sent, "send! with a bad PEM")?
	streamed = match Http.send_streaming!(request, { tls: { trust: AddPem([]) } }) {
		Err(HttpErr(TlsErr(BadPem(_)))) => True
		_ => False
	}
	check(streamed, "send_streaming! with a bad PEM")?

	# With the default roots a connection is attempted, and it fails.
	refused = match Http.send!(request, {}) {
		Err(HttpErr(Other(_))) => True
		Err(HttpErr(NetworkError)) => True
		_ => False
	}
	check(refused, "port 1 refuses connections")
}
