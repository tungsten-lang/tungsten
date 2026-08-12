# Local TLS integration. scripts/test-http-tls.sh supplies an OpenSSL server
# whose certificate is trusted through SSL_CERT_FILE.

use core/http

-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit(1)

-> fetch_tls(host, port)
  HTTP.get("https://[host]:[port]/")

port = argv()[0].to_i
first = fetch_tls("localhost", port)
check("http.tls.first_status", first.status == 200)
check("http.tls.first_body", !first.body.empty?)

# Same compiled TLS.client_wrap call site must continue to use the native
# verified handshake rather than caching the empty Core facade declaration.
second = fetch_tls("localhost", port)
check("http.tls.repeated_status", second.status == 200)

hostname_rejected = false
begin
  fetch_tls("127.0.0.1", port)
rescue error
  hostname_rejected = error.to_s.include?("TLS")
check("http.tls.hostname_verification", hostname_rejected)

<< "http_tls_socket_spec: all checks passed"
