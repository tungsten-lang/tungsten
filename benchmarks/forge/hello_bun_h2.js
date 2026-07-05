Bun.serve({
  port: 8445,
  hostname: "127.0.0.1",
  tls: {
    key: Bun.file("/tmp/bench_key.pem"),
    cert: Bun.file("/tmp/bench_cert.pem"),
  },
  fetch(req) {
    return new Response("Hello World\n", {
      headers: { "Content-Length": "12" },
    });
  },
});
