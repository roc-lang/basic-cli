## Choose which server certificates a TLS client accepts, for [Tcp.connect_tls!]
## and for HTTPS through [Http.send!] and [Http.send_streaming!].
##
## See the [host runtime behavior](https://github.com/roc-lang/basic-cli#host-runtime-behavior)
## for where the default roots come from.
Tls :: [].{

	## Which server certificates a client accepts.
	##
	## - `Default`: certificates that chain to the bundled WebPKI (Mozilla) roots.
	##   The operating system's trust store is not consulted.
	## - `AddPem(bytes)`: the bundled roots plus every `CERTIFICATE` in the PEM
	##   bytes, such as a private certificate authority. Other PEM sections are
	##   ignored. Bytes without any certificate are `BadPem`, before anything is
	##   sent.
	## - `DangerAcceptInvalidCerts`: any certificate, for any name, expired or
	##   not. The connection is still encrypted and the server must still hold
	##   the key of the certificate it presents, but anyone on the network path
	##   can present their own. Only for development against a server with a
	##   self-signed certificate.
	Trust : [Default, AddPem(List(U8)), DangerAcceptInvalidCerts]

	## TLS settings. `{}` selects the defaults.
	##
	## ```roc
	## ca = Path.read_bytes!("ca.pem")?
	## conn = Tcp.connect_tls!("db.internal", 6380, { connect_timeout: Duration.seconds(5), io_timeout: Duration.seconds(30), tls: { trust: AddPem(ca) } })?
	## ```
	Options := { trust : Trust ?? Default }

	## Why a TLS handshake failed.
	##
	## - `UnknownIssuer`: the certificate does not chain to a trusted root.
	## - `Expired`: the certificate, or one it chains to, has expired.
	## - `NameMismatch`: the certificate is not valid for the host name or IP
	##   address that was connected to.
	## - `Other`: any other handshake failure, such as no common protocol
	##   version, an alert from the server, or a server that closed the
	##   connection during the handshake.
	Reason := [UnknownIssuer, Expired, NameMismatch, Other].{

		## Compare two reasons, so results that contain one work with `==`.
		is_eq : _

		## Describe the reason for display.
		to_str : Reason -> Str
		to_str = |reason|
			match reason {
				UnknownIssuer => "the server certificate is not issued by a trusted certificate authority"
				Expired => "the server certificate has expired"
				NameMismatch => "the server certificate is not valid for the requested host"
				Other => "the TLS handshake failed"
			}
	}

	## A failed TLS handshake, carried as `TlsErr(err)`.
	##
	## - `host`: the server whose handshake failed. Over HTTP with redirects
	##   this is the hop that failed, which may not be the first host.
	## - `reason`: the cause, for matching.
	## - `detail`: the TLS library's description, for diagnostics only. Its
	##   wording may change between releases, so match on `reason` instead.
	##
	## ```roc
	## match Tcp.connect_tls!(host, port, options) {
	## 	Err(TlsErr({ reason: UnknownIssuer, .. })) => Stderr.line!("Pass the server's CA with --cacert")
	## 	...
	## }
	## ```
	##
	## Trust roots that cannot be used are a separate error, `BadPem(message)`,
	## reported before any network activity.
	Err : { host : Str, reason : Reason, detail : Str }
}

expect Tls.Options.{}.trust == Default
expect Tls.Options.{ trust: AddPem([1]) }.trust == AddPem([1])
expect Tls.Reason.to_str(Expired) == "the server certificate has expired"
expect {
	result : Try({}, [TlsErr(Tls.Err)])
	result = Err(TlsErr({ host: "localhost", reason: NameMismatch, detail: "x" }))
	matched = match result {
		Err(TlsErr({ reason: NameMismatch, .. })) => True
		_ => False
	}
	matched and result != Err(TlsErr({ host: "localhost", reason: Expired, detail: "x" }))
}
