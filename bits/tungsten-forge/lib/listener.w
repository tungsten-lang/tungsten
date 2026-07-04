# Forge::Listener — socket listener with goroutines
# Uses compiled runtime Socket.listen + non-blocking I/O + goroutine parking

in Tungsten:Forge

+ Listener
  ro :host
  ro :port
  ro :tls
  ro :protocols
  ro :socket

  -> new(host:, port:, tls:, protocols:)
    @host      = host
    @port      = port
    @tls       = tls
    @protocols = protocols
    @socket    = nil
    @quic      = nil
    @running   = false

  -> start(&on_connection)
    @running = true

    # Start QUIC listener for HTTP/3 if enabled
    if @protocols.include?(:h3)
      @quic = QUIC:Listener.new(
        host: @host,
        port: @port,
        tls: self.tls_context,
        on_stream: on_connection
      )
      go -> @quic.listen

    # Start TCP listener using compiled runtime sockets
    @socket = Socket.listen(@host, @port, 1024)

    loop
      break unless @running
      raw = @socket.accept
      client = if @tls[:enabled]
        self.tls_context.wrap(raw)
      else
        raw
      on_connection.call(client)

  -> stop
    @running = false
    @socket&.close
    @quic&.close

  -> tls_context
    @_tls_context ||= TLS.build_context(@tls, @protocols)
