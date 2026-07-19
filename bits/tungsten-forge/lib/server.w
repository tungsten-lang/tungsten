# Forge Server — HTTP/1.1 server core (v2: keep-alive + goroutine-per-connection).
#
# Real, working live path: binds via the compiled runtime's Socket class
# (Socket.listen / accept / read / write / close — see runtime/runtime.c),
# accepts connections in a goroutine, and serves each connection from its
# own goroutine. Connections are persistent: requests are framed out of a
# carried buffer (pipelined bytes included), dispatched through the
# middleware chain + Router, and the serialized Responses written back —
# batched into one write when several pipelined requests are buffered.
# The Connection header is honored (HTTP/1.1 defaults to keep-alive,
# "Connection: close" closes; HTTP/1.0 defaults to close, opt-in via
# "Connection: keep-alive"). TLS and HTTP/2+ remain future work (see
# listener.w / connection.w / thread_pool.w / tls.w).
#
# Concurrency model: all socket work runs in goroutines; the main thread
# drives the cooperative scheduler (`w_scheduler_run`). This matters —
# outside a goroutine, a socket park is a plain blocking poll(2) that
# would never let other goroutines run, so accept MUST live inside a
# goroutine. Runtime sockets are non-blocking: reads/accepts that would
# block park only their own goroutine on the event loop, so an idle or
# dead client stalls its own connection goroutine, never the server.
# (Socket#set_timeout is a no-op here: SO_RCVTIMEO never fires on a
# non-blocking fd, so the idle guard is goroutine isolation plus the
# per-connection request cap; a closed/reset peer surfaces as a nil
# read and ends the connection goroutine.)
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
  # The accept loop runs in a goroutine; the main thread becomes the
  # scheduler and never returns while goroutines are live.
  -> start
    @running = true
    @socket = Socket.listen(@host, @port, 128)
    Server.spawn_accept_loop(self)
    ccall("w_scheduler_run")

  # `go` closure capture only works for the enclosing frame's PARAMS
  # (capturing a method local compiles to a bogus method call), so the
  # accept goroutine is spawned from a method that takes the server as
  # a parameter.
  -> .spawn_accept_loop(server)
    go -> server.accept_loop

  -> stop
    @running = false
    if @socket
      @socket.close
      @socket = nil

  -> accept_loop
    while @running
      conn = @socket.accept
      Server.spawn_connection(self, conn)

  # Spawn the per-connection goroutine. This MUST stay a separate method:
  # `go` closures capture enclosing frame SLOTS, not values, so spawning
  # straight from the accept loop would alias every connection goroutine
  # to the most recently accepted conn (the known closure-capture
  # miscompile — see spec/fixtures/repros/closure_capture/). A dedicated
  # call frame per spawn gives each goroutine its own captured conn.
  -> .spawn_connection(server, conn)
    go -> server.serve_connection(conn)

  # Serve one connection, turning failures into a closed connection (and
  # a 500 for handler errors) rather than letting them kill the goroutine.
  -> serve_connection(conn)
    failed = nil
    begin
      self.handle_connection(conn)
    rescue e
      failed = e
    if failed != nil
      begin
        conn.write(Response.error.header("Connection", "close").to_http)
      rescue e2
        nil
      begin
        conn.close
      rescue e3
        nil

  # Keep-alive read loop. Frames complete requests out of `buf` (carrying
  # any pipelined remainder across iterations), dispatches them, and
  # accumulates responses in `out`, which is flushed in a single write
  # whenever the buffer runs out of complete requests — so a pipelined
  # batch gets one write, not one per response. Exits when the peer
  # closes (nil read), a request asks for close, parsing fails, or the
  # per-connection request cap is reached.
  -> handle_connection(conn)
    buf = ""
    out = ""
    served = 0
    alive = true
    while alive
      total = Server.request_length(buf)
      if total == 0
        # No complete request buffered — flush pending responses, then read.
        if out.size > 0
          conn.write(out)
          out = ""
        if buf.size > 16_777_216
          # Oversized request (headers + body) — reject and close.
          conn.write(Response.error("Request Too Large", {status: 413}).header("Connection", "close").to_http)
          alive = false
        else
          chunk = conn.read(8192)
          if chunk == nil
            alive = false
          else
            if buf.size == 0
              buf = chunk
            else
              buf = buf + chunk
      else
        raw = buf
        if buf.size == total
          # Fully consumed — reset to a fresh literal instead of slicing,
          # so no chain of parent buffers is retained across requests.
          buf = ""
        else
          raw = buf.slice(0, total)
          buf = buf.slice(total, buf.size - total)
        request = Request.parse(raw)
        if request == nil
          out = out + Response.error("Bad Request", {status: 400}).header("Connection", "close").to_http
          alive = false
        else
          served += 1
          keep = request.keep_alive?
          if served >= 10_000
            # Per-connection request cap — bounds a single connection's
            # lifetime so one peer cannot hold its goroutine forever.
            keep = false
          response = nil
          begin
            response = self.dispatch(request)
          rescue e
            response = nil
          if response == nil
            response = Response.error
            keep = false
          if keep
            response.header("Connection", "keep-alive")
          else
            response.header("Connection", "close")
          out = out + response.to_http
          alive = keep
    if out.size > 0
      conn.write(out)
    conn.close

  # --- Request framing (pure string functions; spec'd in framing_spec.w) ---

  # Byte length of the first complete HTTP/1.1 request in buf, or 0 when
  # more bytes are needed. A request is complete once the header block
  # has terminated and Content-Length bytes of body (default 0) follow.
  # Flag style, no early returns: returning early after the nested
  # closure-bearing content_length_in call corrupts the self-hosted
  # interpreter (segfault).
  -> .request_length(buf)
    result = 0
    separator = buf.index("\r\n\r\n")
    if separator != nil
      total = separator + 4 + Server.content_length_in(buf.slice(0, separator))
      if buf.size >= total
        result = total
    result

  # Scan a raw header block for Content-Length (case-insensitive).
  -> .content_length_in(head)
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
