These certificate and private-key fixtures are original basic-cli test data
under the repository's UPL-1.0 license. The key is public test material and must
never secure a real service. The self-signed localhost certificate is valid from
October 2026 through October 2036 and has a localhost subject alternative name.

Generated with OpenSSL `req -x509 -newkey rsa:2048 -nodes -subj /CN=localhost
-addext subjectAltName=DNS:localhost
-addext basicConstraints=critical,CA:FALSE
-addext keyUsage=critical,digitalSignature,keyEncipherment
-addext extendedKeyUsage=serverAuth -days 3650`, then converted with `x509
-outform DER` and `pkcs8 -topk8 -nocrypt -outform DER`.
