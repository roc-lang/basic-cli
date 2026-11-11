//! TLS client sessions for `Tcp.connect_tls!` and HTTPS: the trust an app chose, the rustls
//! configurations built for it, the failures a handshake reports, and the non-blocking driving of a
//! session over the buffered socket.
//!
//! A session is driven step by step on the connection's non-blocking socket, so the deadline,
//! signal polling and buffer of `socket.rs` apply unchanged. Plaintext that rustls has already
//! decrypted is always taken before the socket is waited on.
use core::mem::ManuallyDrop;
use std::io::{self, Read, Write};
use std::sync::{Arc, LazyLock, Mutex, PoisonError};

use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::{ring, CryptoProvider};
use rustls::pki_types::{pem::PemObject, CertificateDer, ServerName, UnixTime};
use rustls::time_provider::{DefaultTimeProvider, TimeProvider};
use rustls::{
    CertificateError, ClientConfig, ClientConnection, DigitallySignedStruct, RootCertStore,
    SignatureScheme,
};

use crate::roc_platform_abi::*;
use crate::socket::{wait_ready, Deadline};

/// `Tls.Trust`, copied out of Roc.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Trust {
    Default,
    AddPem(Vec<u8>),
    DangerAcceptInvalidCerts,
}

impl Trust {
    /// Copy the trust out of its Roc value and release that value.
    pub(crate) fn from_roc(
        trust: AddPemOrDangerAcceptInvalidCertsOrDefault,
        roc_host: &RocHost,
    ) -> Self {
        let copied = match trust.tag {
            AddPemOrDangerAcceptInvalidCertsOrDefaultTag::Default => Self::Default,
            AddPemOrDangerAcceptInvalidCertsOrDefaultTag::AddPem => Self::AddPem(
                unsafe { trust.borrow_payload_add_pem_unchecked() }
                    .as_slice()
                    .to_vec(),
            ),
            AddPemOrDangerAcceptInvalidCertsOrDefaultTag::DangerAcceptInvalidCerts => {
                Self::DangerAcceptInvalidCerts
            }
        };
        unsafe { trust.decref(roc_host) };
        copied
    }
}

/// `Tls.Err` as the host produces it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum TlsFailure {
    UnknownIssuer,
    Expired,
    NameMismatch,
    BadPem(String),
    Other(String),
}

impl TlsFailure {
    /// Name the certificate failures Roc can match on; keep rustls's description of the rest.
    /// webpki reports the `…Context` spellings, so both forms of each are named.
    pub(crate) fn from_rustls(error: &rustls::Error) -> Self {
        match error {
            rustls::Error::InvalidCertificate(CertificateError::UnknownIssuer) => {
                Self::UnknownIssuer
            }
            rustls::Error::InvalidCertificate(
                CertificateError::Expired | CertificateError::ExpiredContext { .. },
            ) => Self::Expired,
            rustls::Error::InvalidCertificate(
                CertificateError::NotValidForName | CertificateError::NotValidForNameContext { .. },
            ) => Self::NameMismatch,
            other => Self::Other(other.to_string()),
        }
    }

    pub(crate) fn to_roc(&self, roc_host: &RocHost) -> TlsErr {
        let message = |text: &str| ManuallyDrop::new(RocStr::from_str(text, roc_host));
        match self {
            Self::UnknownIssuer => TlsErr {
                payload: TlsErrPayload { unknown_issuer: [] },
                tag: TlsErrTag::UnknownIssuer,
            },
            Self::Expired => TlsErr {
                payload: TlsErrPayload { expired: [] },
                tag: TlsErrTag::Expired,
            },
            Self::NameMismatch => TlsErr {
                payload: TlsErrPayload { name_mismatch: [] },
                tag: TlsErrTag::NameMismatch,
            },
            Self::BadPem(text) => TlsErr {
                payload: TlsErrPayload {
                    bad_pem: message(text),
                },
                tag: TlsErrTag::BadPem,
            },
            Self::Other(text) => TlsErr {
                payload: TlsErrPayload {
                    other: message(text),
                },
                tag: TlsErrTag::Other,
            },
        }
    }
}

/// Why `Tcp.connect_tls!` failed: the connection itself, or TLS.
#[derive(Debug)]
pub(crate) enum ConnectError {
    Io(io::Error),
    Tls(TlsFailure),
}

impl From<io::Error> for ConnectError {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

static DEFAULT: LazyLock<Arc<ClientConfig>> = LazyLock::new(|| {
    Arc::new(
        build_config(&Trust::Default, Arc::new(DefaultTimeProvider))
            .expect("the bundled roots build a configuration"),
    )
});
static ACCEPT_ANY: LazyLock<Arc<ClientConfig>> = LazyLock::new(|| {
    Arc::new(
        build_config(
            &Trust::DangerAcceptInvalidCerts,
            Arc::new(DefaultTimeProvider),
        )
        .expect("accepting any certificate builds a configuration"),
    )
});
/// `AddPem` configurations by their exact bytes, most recently used last.
static WITH_PEM: Mutex<Vec<(Vec<u8>, Arc<ClientConfig>)>> = Mutex::new(Vec::new());
const CACHED_PEM_CONFIGS: usize = 8;

/// The configuration for `trust`. Built once per distinct trust and shared, so connections with
/// the same trust share a session cache and can resume. `AddPem` is parsed here, before any I/O.
pub(crate) fn client_config(trust: &Trust) -> Result<Arc<ClientConfig>, TlsFailure> {
    let pem = match trust {
        Trust::Default => return Ok(default_config()),
        Trust::DangerAcceptInvalidCerts => return Ok(ACCEPT_ANY.clone()),
        Trust::AddPem(pem) => pem,
    };
    let mut cached = WITH_PEM.lock().unwrap_or_else(PoisonError::into_inner);
    if let Some(index) = cached.iter().position(|(bytes, _)| bytes == pem) {
        let hit = cached.remove(index);
        let config = hit.1.clone();
        cached.push(hit);
        return Ok(config);
    }
    let config = Arc::new(build_config(trust, Arc::new(DefaultTimeProvider))?);
    if cached.len() == CACHED_PEM_CONFIGS {
        cached.remove(0);
    }
    cached.push((pem.clone(), config.clone()));
    Ok(config)
}

/// `client_config(&Trust::Default)`, which cannot fail.
pub(crate) fn default_config() -> Arc<ClientConfig> {
    DEFAULT.clone()
}

/// The configuration for `trust` with an explicit clock. Production passes `DefaultTimeProvider`;
/// tests move the clock to reach an expired certificate.
fn build_config(trust: &Trust, time: Arc<dyn TimeProvider>) -> Result<ClientConfig, TlsFailure> {
    // The provider and protocol versions of `hyper_rustls`'s `with_webpki_roots()`.
    let provider = Arc::new(ring::default_provider());
    let builder = ClientConfig::builder_with_details(provider.clone(), time)
        .with_safe_default_protocol_versions()
        .map_err(|error| TlsFailure::Other(error.to_string()))?;
    let mut roots = RootCertStore::empty();
    roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let builder = match trust {
        Trust::Default => builder.with_root_certificates(roots),
        Trust::AddPem(pem) => {
            let mut added = 0;
            for certificate in CertificateDer::pem_slice_iter(pem) {
                let certificate = certificate
                    .map_err(|error| TlsFailure::BadPem(format!("invalid PEM: {error}")))?;
                added += 1;
                roots.add(certificate).map_err(|error| {
                    TlsFailure::BadPem(format!(
                        "certificate {added} is not a usable trust anchor: {error}"
                    ))
                })?;
            }
            if added == 0 {
                return Err(TlsFailure::BadPem(
                    "no CERTIFICATE section found".to_string(),
                ));
            }
            builder.with_root_certificates(roots)
        }
        Trust::DangerAcceptInvalidCerts => builder
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(AcceptAnyCertificate(provider))),
    };
    Ok(builder.with_no_client_auth())
}

/// The name `host` is verified against: a DNS name (also sent as SNI) or an IP address.
pub(crate) fn server_name(host: &str) -> Result<ServerName<'static>, TlsFailure> {
    ServerName::try_from(host)
        .map(|name| name.to_owned())
        .map_err(|_| {
            TlsFailure::Other(format!(
                "{host:?} is not a valid name for TLS server verification"
            ))
        })
}

/// The rustls error somewhere in `error`'s chain, looking inside `io::Error` payloads too:
/// `io::Error::source()` skips its own payload, which is where hyper-rustls puts it.
pub(crate) fn rustls_error_in<'a>(
    mut error: &'a (dyn std::error::Error + 'static),
) -> Option<&'a rustls::Error> {
    loop {
        if let Some(found) = error.downcast_ref::<rustls::Error>() {
            return Some(found);
        }
        let payload = error
            .downcast_ref::<io::Error>()
            .and_then(io::Error::get_ref)
            .map(|inner| inner as &(dyn std::error::Error + 'static));
        error = payload.or_else(|| error.source())?;
    }
}

/// Send what the session owes, as far as the socket takes it now.
fn flush_without_waiting(conn: &mut ClientConnection, socket: &socket2::Socket) -> io::Result<()> {
    while conn.wants_write() {
        match conn.write_tls(&mut &*socket) {
            Ok(_) => {}
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => return Ok(()),
            Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
            Err(error) => return Err(error),
        }
    }
    Ok(())
}

/// Complete the handshake within `deadline`, then flush the client's last flight.
pub(crate) fn handshake(
    conn: &mut ClientConnection,
    socket: &socket2::Socket,
    deadline: Deadline,
) -> Result<(), ConnectError> {
    while conn.is_handshaking() || conn.wants_write() {
        deadline.remaining()?;
        if conn.wants_write() {
            match conn.write_tls(&mut &*socket) {
                Ok(_) => {}
                Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                    wait_ready(socket, true, deadline)?
                }
                Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
                Err(error) => return Err(error.into()),
            }
            continue;
        }
        match conn.read_tls(&mut &*socket) {
            Ok(0) => {
                return Err(ConnectError::Tls(TlsFailure::Other(
                    "the server closed the connection during the TLS handshake".to_string(),
                )))
            }
            Ok(_) => {
                if let Err(error) = conn.process_new_packets() {
                    // Let the server see our alert, if the socket takes it now.
                    let _ = conn.write_tls(&mut &*socket);
                    return Err(ConnectError::Tls(TlsFailure::from_rustls(&error)));
                }
            }
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                wait_ready(socket, false, deadline)?
            }
            Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
            Err(error) => return Err(error.into()),
        }
    }
    Ok(())
}

/// One attempt to read plaintext into `dst` that never waits. `WouldBlock` asks the caller to
/// wait for the socket; `Ok(0)` is the peer's `close_notify`. The caller checks the deadline
/// before each attempt.
pub(crate) fn read(
    conn: &mut ClientConnection,
    socket: &socket2::Socket,
    dst: &mut [u8],
) -> io::Result<usize> {
    loop {
        // Plaintext already decrypted comes first: waiting on the socket while it is here could
        // block with data available.
        match conn.reader().read(dst) {
            Ok(count) => return Ok(count),
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {}
            // Not `UnexpectedEof`, which a fixed-size read reports as the end of input.
            Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => {
                return Err(io::Error::other(
                    "the peer closed the TLS connection without close_notify; data may be missing",
                ))
            }
            Err(error) => return Err(error),
        }
        // Send what the session owes (alerts, key update replies) if the socket takes it now. A
        // failure here is not fatal: records already received still need processing, and
        // `read_tls` reports the socket's state.
        let _ = flush_without_waiting(conn, socket);
        // Records are processed whatever the socket read gives, so a failed session reports its
        // error again on every later read. `Ok(0)` is the end of TCP, which the reader reports.
        let received = conn.read_tls(&mut &*socket);
        conn.process_new_packets().map_err(|error| {
            let _ = flush_without_waiting(conn, socket);
            io::Error::other(format!("TLS: {error}"))
        })?;
        received?;
    }
}

/// Write all of `bytes` within `deadline`. On failure any prefix may have been sent.
pub(crate) fn write_all(
    conn: &mut ClientConnection,
    socket: &socket2::Socket,
    bytes: &[u8],
    deadline: Deadline,
) -> io::Result<()> {
    let mut accepted = 0;
    loop {
        deadline.remaining()?;
        if accepted < bytes.len() {
            // Zero when the session's send buffer is full.
            accepted += conn.writer().write(&bytes[accepted..])?;
        }
        if !conn.wants_write() {
            if accepted == bytes.len() {
                return Ok(());
            }
            continue;
        }
        match conn.write_tls(&mut &*socket) {
            Ok(_) => {}
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                wait_ready(socket, true, deadline)?
            }
            Err(error) if error.kind() == io::ErrorKind::Interrupted => {}
            Err(error) => return Err(error),
        }
    }
}

/// Queue `close_notify` and write what the socket takes now, without waiting.
pub(crate) fn close(conn: &mut ClientConnection, socket: &socket2::Socket) {
    conn.send_close_notify();
    let _ = flush_without_waiting(conn, socket);
}

/// `DangerAcceptInvalidCerts`: accept any certificate, but still require the handshake to be
/// signed by its key, so the session is encrypted to whoever holds it.
#[derive(Debug)]
struct AcceptAnyCertificate(Arc<CryptoProvider>);

impl ServerCertVerifier for AcceptAnyCertificate {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.0.signature_verification_algorithms.supported_schemes()
    }
}

/// Local TLS servers for the tests of this module, `tcp` and `http`.
#[cfg(test)]
pub(crate) mod testing {
    use super::*;
    use rustls::pki_types::PrivateKeyDer;
    use rustls::server::{ClientHello, ResolvesServerCert};
    use rustls::sign::CertifiedKey;
    use rustls::{ServerConfig, ServerConnection, StreamOwned};
    use std::net::{TcpListener, TcpStream};
    use std::thread::{self, JoinHandle};
    use std::time::Duration;

    pub(crate) const LOCALHOST_PEM: &[u8] = include_bytes!("../tests/tls/localhost-cert.pem");
    pub(crate) type ServerStream = StreamOwned<ServerConnection, TcpStream>;

    fn certificate() -> CertificateDer<'static> {
        CertificateDer::from(include_bytes!("../tests/tls/localhost-cert.der").to_vec())
    }

    fn key(der: &[u8]) -> PrivateKeyDer<'static> {
        PrivateKeyDer::try_from(der.to_vec()).unwrap()
    }

    fn server_builder() -> rustls::ConfigBuilder<ServerConfig, rustls::server::WantsServerCert> {
        ServerConfig::builder_with_provider(Arc::new(ring::default_provider()))
            .with_safe_default_protocol_versions()
            .unwrap()
            .with_no_client_auth()
    }

    /// The localhost certificate and its key.
    pub(crate) fn server_config() -> Arc<ServerConfig> {
        let key = key(include_bytes!("../tests/tls/localhost-key.der"));
        Arc::new(
            server_builder()
                .with_single_cert(vec![certificate()], key)
                .unwrap(),
        )
    }

    /// Presents the localhost certificate but signs with a key that does not match it.
    /// `with_single_cert` would refuse the pair, so the resolver hands it over unchecked.
    #[derive(Debug)]
    struct MismatchedKey(Arc<CertifiedKey>);
    impl ResolvesServerCert for MismatchedKey {
        fn resolve(&self, _: ClientHello<'_>) -> Option<Arc<CertifiedKey>> {
            Some(self.0.clone())
        }
    }

    pub(crate) fn mismatched_key_server_config() -> Arc<ServerConfig> {
        let signing_key = ring::default_provider()
            .key_provider
            .load_private_key(key(include_bytes!("../tests/tls/unrelated-key.der")))
            .unwrap();
        let certified = CertifiedKey::new(vec![certificate()], signing_key);
        Arc::new(server_builder().with_cert_resolver(Arc::new(MismatchedKey(Arc::new(certified)))))
    }

    /// A client configuration for `trust` whose clock reads `unix_seconds`.
    pub(crate) fn config_at(trust: &Trust, unix_seconds: u64) -> Arc<ClientConfig> {
        #[derive(Debug)]
        struct FixedTime(UnixTime);
        impl TimeProvider for FixedTime {
            fn current_time(&self) -> Option<UnixTime> {
                Some(self.0)
            }
        }
        let time = UnixTime::since_unix_epoch(Duration::from_secs(unix_seconds));
        Arc::new(build_config(trust, Arc::new(FixedTime(time))).unwrap())
    }

    /// Accept one client on a fresh port bound to `localhost`, the way the client resolves it
    /// (see `connect_timeout_includes_localhost_resolution` in tcp.rs), and hand the server
    /// session to `serve` on a thread. The socket blocks, with 5 s timeouts.
    pub(crate) fn serve_one(
        config: Arc<ServerConfig>,
        serve: impl FnOnce(ServerStream) + Send + 'static,
    ) -> (u16, JoinHandle<()>) {
        let listener = TcpListener::bind(("localhost", 0)).unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = thread::spawn(move || {
            let (socket, _) = listener.accept().unwrap();
            socket
                .set_read_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            socket
                .set_write_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            serve(StreamOwned::new(
                ServerConnection::new(config).unwrap(),
                socket,
            ));
        });
        (port, server)
    }

    /// Drive the server's side of the handshake to its end.
    pub(crate) fn finish_handshake(stream: &mut ServerStream) -> Result<(), io::Error> {
        while stream.conn.is_handshaking() {
            stream.conn.complete_io(&mut stream.sock)?;
        }
        Ok(())
    }

    /// Like `pair()` in tcp.rs: a connected client `Connection` over TLS and the server's end,
    /// the handshake done.
    pub(crate) fn tls_pair() -> (crate::tcp::Connection, ServerStream) {
        let (sender, receiver) = std::sync::mpsc::channel();
        let (port, server) = serve_one(server_config(), move |mut stream| {
            finish_handshake(&mut stream).unwrap();
            sender.send(stream).unwrap();
        });
        let stream = TcpStream::connect(("localhost", port)).unwrap();
        let config = client_config(&Trust::AddPem(LOCALHOST_PEM.to_vec())).unwrap();
        let name = server_name("localhost").unwrap();
        let deadline = Deadline::after_nanos(10_000_000_000).unwrap();
        let connection = crate::tcp::Connection::new_tls(stream, config, name, deadline).unwrap();
        let peer = receiver.recv().unwrap();
        server.join().unwrap();
        (connection, peer)
    }
}

#[cfg(test)]
mod tests {
    use super::testing::LOCALHOST_PEM;
    use super::*;

    #[test]
    fn pem_roots_are_parsed_before_any_connection() {
        let bad_pem = |pem: &[u8]| match client_config(&Trust::AddPem(pem.to_vec())) {
            Err(TlsFailure::BadPem(message)) => message,
            other => panic!("expected BadPem, got {:?}", other.map(|_| ())),
        };
        assert_eq!(bad_pem(b"junk"), "no CERTIFICATE section found");
        assert!(
            bad_pem(b"-----BEGIN CERTIFICATE-----\n!!!\n-----END CERTIFICATE-----\n")
                .starts_with("invalid PEM")
        );
        // A key alone is not a root, and a certificate that does not parse is not an anchor.
        assert_eq!(
            bad_pem(include_bytes!("../tests/tls/localhost-key.pem")),
            "no CERTIFICATE section found"
        );
        assert!(
            bad_pem(b"-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n")
                .starts_with("certificate 1 is not a usable trust anchor")
        );
        assert!(client_config(&Trust::AddPem(LOCALHOST_PEM.to_vec())).is_ok());
    }

    #[test]
    fn certificate_errors_are_named() {
        use rustls::Error::InvalidCertificate;
        let named = |error: rustls::Error| TlsFailure::from_rustls(&error);
        let now = UnixTime::now();
        assert_eq!(
            named(InvalidCertificate(CertificateError::UnknownIssuer)),
            TlsFailure::UnknownIssuer
        );
        assert_eq!(
            named(InvalidCertificate(CertificateError::Expired)),
            TlsFailure::Expired
        );
        assert_eq!(
            named(InvalidCertificate(CertificateError::ExpiredContext {
                time: now,
                not_after: now,
            })),
            TlsFailure::Expired
        );
        assert_eq!(
            named(InvalidCertificate(CertificateError::NotValidForName)),
            TlsFailure::NameMismatch
        );
        assert_eq!(
            named(InvalidCertificate(
                CertificateError::NotValidForNameContext {
                    expected: server_name("localhost").unwrap(),
                    presented: vec!["DNS:example.com".to_string()],
                }
            )),
            TlsFailure::NameMismatch
        );
        // Anything else keeps rustls's description.
        let other = rustls::Error::InvalidCertificate(CertificateError::NotValidYet);
        assert_eq!(named(other.clone()), TlsFailure::Other(other.to_string()));
        assert_eq!(
            server_name("not a host name"),
            Err(TlsFailure::Other(
                "\"not a host name\" is not a valid name for TLS server verification".to_string()
            ))
        );
    }

    #[test]
    fn rustls_errors_are_found_inside_io_errors() {
        // How hyper-rustls reports a failed handshake to hyper.
        let wrapped = io::Error::other(io::Error::new(
            io::ErrorKind::InvalidData,
            rustls::Error::InvalidCertificate(CertificateError::UnknownIssuer),
        ));
        assert_eq!(
            rustls_error_in(&wrapped),
            Some(&rustls::Error::InvalidCertificate(
                CertificateError::UnknownIssuer
            ))
        );
        assert_eq!(rustls_error_in(&io::Error::other("no TLS here")), None);
    }

    #[test]
    fn configs_are_shared_per_trust() {
        let config = |trust: &Trust| client_config(trust).unwrap();
        let pem = Trust::AddPem(LOCALHOST_PEM.to_vec());
        assert!(Arc::ptr_eq(&config(&pem), &config(&pem)));
        assert!(Arc::ptr_eq(
            &config(&Trust::Default),
            &config(&Trust::Default)
        ));
        assert!(Arc::ptr_eq(
            &config(&Trust::DangerAcceptInvalidCerts),
            &config(&Trust::DangerAcceptInvalidCerts)
        ));
        // Different bytes are a different trust, even when they hold the same certificate.
        let mut repeated = LOCALHOST_PEM.to_vec();
        repeated.extend_from_slice(LOCALHOST_PEM);
        assert!(!Arc::ptr_eq(
            &config(&pem),
            &config(&Trust::AddPem(repeated))
        ));
        assert!(!Arc::ptr_eq(&config(&pem), &config(&Trust::Default)));
    }
}
