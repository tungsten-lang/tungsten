Bun.serve({
  port: 8084,
  hostname: "127.0.0.1",
  fetch(req) {
    return new Response("Hello World\n", {
      headers: { "Content-Length": "12" },
    });
  },
});
