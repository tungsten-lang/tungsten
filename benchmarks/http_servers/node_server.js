const http = require("http");
const server = http.createServer((req, res) => {
  res.writeHead(200, { "Content-Length": "12" });
  res.end("Hello World\n");
});
server.listen(8080);
