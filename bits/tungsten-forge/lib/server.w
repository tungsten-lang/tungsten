# Forge Server — HTTP/1.1 server core (v1: blocking accept loop).
#
# Real, working live path: binds via the compiled runtime's Socket class
# (Socket.listen / accept / read / write / close — see runtime/runtime.c),
# reads one request per connection, parses it with Request.parse,
# dispatches through the middleware chain + Router, and writes the
# serialized Response back. Connections are closed after each response
# (Connection: close); keep-alive, goroutine-per-connection concurrency,
# TLS, and HTTP/2+ are future work (see listener.w / connection.w /
# thread_pool.w / tls.w for the aspirational designs).
#
# Socket is a compiled-runtime builtin (compiler/lib/lowering/types.w
# builtin_runtime_classes) — the live path runs COMPILED only. The
# self-hosted interpreter can load this file but cannot resolve Socket
# at runtime.

+ Server
  ro :router
  ro :middleware
  ro :config
  ro :host
  ro :port
  ro :running

  -> new(router, middleware, config)
    @router     = router
    @middleware = middleware
    @config     = config
    @host       = config.host
    @port       = config.port
    @running    = false
    @socket     = nil

  # Bind and serve until stop is called (or the process is killed).
  -> start
    @running = true
    @socket = Socket.listen(@host, @port, 128)
    while @running
      conn = @socket.accept
      self.serve_connection(conn)

  -> stop
    @running = false
    if @socket
      @socket.close
      @socket = nil

  # Handle one connection, turning handler exceptions into a 500 rather
  # than letting them kill the accept loop.
  -> serve_connection(conn)
    failed = nil
    begin
      self.handle_connection(conn)
    rescue e
      failed = e
    if failed != nil
      begin
        conn.write(Response.error.to_http)
        conn.close
      rescue e2
        nil

  # Read one request, dispatch it, write the response, close.
  -> handle_connection(conn)
    raw = self.read_request_raw(conn)
    if raw.index("\r\n\r\n") != nil
      raw = self.read_remaining_body(conn, raw)
      request = Request.parse(raw)
      if request == nil
        conn.write(Response.error("Bad Request", {status: 400}).to_http)
      else
        response = self.dispatch(request)
        response.header("Connection", "close")
        conn.write(response.to_http)
    conn.close

  # Accumulate reads until the header terminator arrives (or EOF).
  -> read_request_raw(conn)
    raw = ""
    reading = true
    while reading
      if raw.index("\r\n\r\n") != nil
        reading = false
      else
        chunk = conn.read(8192)
        if chunk == nil
          reading = false
        else
          raw = raw + chunk
    raw

  # Headers are complete; keep reading until Content-Length bytes of
  # body have arrived (or the peer closes).
  -> read_remaining_body(conn, raw)
    separator = raw.index("\r\n\r\n")
    result = raw
    needed = self.content_length_in(raw.slice(0, separator))
    body_have = result.size - (separator + 4)
    while body_have < needed
      chunk = conn.read(8192)
      if chunk == nil
        body_have = needed
      else
        result = result + chunk
        body_have = body_have + chunk.size
    result

  # Scan a raw header block for Content-Length (case-insensitive).
  -> content_length_in(head)
    found = 0
    head.split("\r\n").each -> (line)
      colon = line.index(": ")
      if colon
        key = line.slice(0, colon).downcase
        if key == "content-length"
          value_start = colon + 2
          found = line.slice(value_start, line.size - value_start).strip.to_i
    found

  # Middleware chain wrapping the router. Path normalization (downcase,
  # trailing-slash strip) happens inside Router#resolve.
  -> dispatch(request)
    target = self
    handler = @middleware.build(-> (req) target.route(req))
    handler.call(request)

  -> route(request)
    match = @router.resolve(request.method, request.path)
    if match
      request.params = match.params
      match.handler.call(request)
    else
      Response.not_found("Not Found: " + request.path)
