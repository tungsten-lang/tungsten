const http2 = require("http2");
const fs = require("fs");

const server = http2.createSecureServer({
  key: fs.readFileSync("/tmp/bench_key.pem"),
  cert: fs.readFileSync("/tmp/bench_cert.pem"),
});

server.on("stream", (stream) => {
  stream.respond({ ":status": 200, "content-length": "12" });
  stream.end("Hello World\n");
});

server.listen(8444, "127.0.0.1");
