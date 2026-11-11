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

	## Why a TLS handshake failed, or why the settings were rejected before
	## connecting.
	##
	## - `UnknownIssuer`: the certificate does not chain to a trusted root.
	## - `Expired`: the certificate, or one it chains to, has expired.
	## - `NameMismatch`: the certificate is not valid for the host name or IP
	##   address that was connected to.
	## - `BadPem(message)`: the `AddPem` bytes hold no usable certificate.
	## - `Other(message)`: any other handshake failure, such as no common
	##   protocol version or an alert from the server.
	Err := [UnknownIssuer, Expired, NameMismatch, BadPem(Str), Other(Str)].{

		## Compare two TLS errors, so results that contain one work with `==`.
		is_eq : _

		## Describe the error for display.
		to_str : Err -> Str
		to_str = |err|
			match err {
				UnknownIssuer => "the server certificate is not issued by a trusted certificate authority"
				Expired => "the server certificate has expired"
				NameMismatch => "the server certificate is not valid for the requested host"
				BadPem(message) => "the PEM trust roots cannot be used: ${message}"
				Other(message) => message
			}
	}
}

expect Tls.Options.{}.trust == Default
expect Tls.Options.{ trust: AddPem([1]) }.trust == AddPem([1])
expect Tls.Err.to_str(Expired) == "the server certificate has expired"
expect {
	result : Try({}, [TlsErr(Tls.Err)])
	result = Err(TlsErr(NameMismatch))
	result == Err(TlsErr(NameMismatch)) and result != Err(TlsErr(Expired))
}
