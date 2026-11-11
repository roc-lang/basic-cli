## Exchange lines with a TLS echo server whose certificate is signed by a
## private certificate authority, read from a PEM file.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.27.0/9yjxqdGTP4xSpSEmDazwTmRsehfRZzA19pwEKkR6fj1g.tar.zst" }

import pf.Duration
import pf.OsStr
import pf.Path
import pf.Stdout
import pf.Tcp

# The test runner starts a local TLS echo server on port 8443 and passes the
# certificate it trusts. To try it by hand, run scripts/tls_test_server.py in
# another terminal, then:
#
#     $ roc examples/tcp-tls.roc -- tests/tls/localhost-cert.pem
#
# Without an argument only the bundled public roots are trusted, so the same
# server is rejected with `TlsErr(UnknownIssuer)`.
main! : List(OsStr) => Try({}, _)
main! = |args| {
	trust = match args {
		[ca_file] => AddPem(Path.from_os_str(ca_file).read_bytes!()?)
		_ => Default
	}

	# The handshake verifies the certificate against the host name. It is part
	# of the connect, so `connect_timeout` bounds it as well.
	conn = Tcp.connect_tls!("localhost", 8443, { connect_timeout: Duration.seconds(5), io_timeout: Duration.seconds(5), tls: { trust } })?
	Stdout.line!("Connected over TLS")?

	# From here on it is an ordinary `Tcp.Connection`.
	conn.write_utf8!("hello\nover tls\n")?
	var $pending = 2
	for! item in conn.lines() {
		match item {
			Ok(line) => Stdout.line!("< ${line}")?
			# These two concern one line; the stream carries on with the next.
			Err(BadUtf8({ index, .. })) => Stdout.line!("< (invalid UTF-8 at byte ${index.to_str()})")?
			Err(ReadLimitExceeded(limit)) => Stdout.line!("< (a line longer than ${limit.to_str()} bytes)")?
			# The connection failed or timed out, and this is the last item.
			Err(TcpErr(err)) => {
				return Err(TcpErr(err))
			}
			Err(Interrupted) => {
				return Err(Interrupted)
			}
		}
		# The echo server keeps the connection open, so stop at the last reply
		# instead of waiting for the end of input.
		$pending = $pending - 1
		if $pending == 0 {
			break
		}
	}

	Ok({})
}
