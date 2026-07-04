# forge_h2_hello.w — HTTP/2-capable server in Tungsten
# Compile with self-hosted compiler → LLVM IR → executable
# Test with: curl --http2 -k https://localhost:8443/

TLS.init()
TLS.load_cert("/tmp/bench_cert.pem", "/tmp/bench_key.pem")

listener = Socket.listen("0.0.0.0", 8443, 128)
listener.serve_http { |req|
  Response.new(200, "Hello World\n")
}
