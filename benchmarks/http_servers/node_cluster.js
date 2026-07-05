const cluster = require("cluster");
const http = require("http");
const os = require("os");

if (cluster.isPrimary) {
  const cpus = os.availableParallelism();
  for (let i = 0; i < cpus; i++) cluster.fork();
} else {
  http.createServer((req, res) => {
    res.writeHead(200, { "Content-Length": "12" });
    res.end("Hello World\n");
  }).listen(8080);
}
