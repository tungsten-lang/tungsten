# Forge::Server — HTTP server core
# Goroutine-per-connection with graceful shutdown
# Supports HTTP/1.1 (request-response loop) and HTTP/2 (session-based multiplexing)

+ Server
  ro :listener
  ro :router
  ro :middleware
  ro :config
  ro :connections
  ro :running

  -> new(listener:, router:, middleware:, config:)
    @listener    = listener
    @router      = router
    @middleware   = middleware
    @config      = config
    @connections  = ConnectionTracker.new(config.max_connections)
    @running      = false

  -> start
    @running = true

    # Register signal handlers for graceful shutdown
    Signal.trap(:INT)  -> self.shutdown(:graceful)
    Signal.trap(:TERM) -> self.shutdown(:graceful)

    @listener.start -> (socket)
      if @connections.accept?
        conn = Connection.new(socket, config: @config)
        @connections.track(conn)

        go ->
          begin
            self.handle_connection(conn)
          ensure
            @connections.release(conn)

  -> stop
    self.shutdown(:immediate)

  -> shutdown(mode = :graceful)
    @running = false
    Logger.info("Shutdown mode: [mode]")

    case mode
      :graceful =>
        # Wait for in-flight goroutines to complete
        @connections.drain(timeout: 30)
      :immediate =>
        # Force close all connections immediately
        @connections.force_close

    @listener.stop

  -> handle_connection(conn)
    case conn.protocol
      :h2 =>
        self.handle_h2_connection(conn)
      :http11 =>
        self.handle_http11_connection(conn)

  -> handle_http11_connection(conn)
    loop
      break unless @running
      request = conn.read_request
      break unless request

      # Normalize path if configured
      if @config.normalize_paths
        request.normalize_path!

      # Build the handler: middleware wrapping the router
      handler = @middleware.build -> (req)
        self.dispatch(req)

      response = handler.call(request)
      conn.write_response(response)

      # Keep-alive or close
      break unless conn.keep_alive? && @running

  -> handle_h2_connection(conn)
    # HTTP/2: delegate to session which handles multiplexing internally
    # The session spawns goroutines per-stream — no request/response loop needed
    handler = @middleware.build -> (req)
      self.dispatch(req)

    conn.run_h2(handler)

  -> dispatch(request)
    # Try static files first
    if @config.static_dir
      static = Static.serve(request, @config)
      return static if static

    # Route to application
    match = @router.resolve(request.method, request.path)

    if match
      request.params = match.params
      match.handler.call(request)
    else
      Response.not_found("Not Found: [request.path]")


  # --- Connection tracking ---

  + ConnectionTracker
    ro :max
    ro :count

    -> new(@max)
      @count = Atomic.new(0)
      @connections = ConcurrentSet.new

    -> accept?
      @count.get < @max

    -> track(conn)
      @count.increment
      @connections.add(conn)

    -> release(conn)
      @connections.remove(conn)
      @count.decrement

    -> drain(timeout: 30)
      deadline = Time.now + timeout
      loop
        break if @connections.empty? || Time.now > deadline
        Goroutine.yield

      # Force-close remaining connections
      self.force_close

    -> force_close
      @connections.each -> (conn)
        conn.close
