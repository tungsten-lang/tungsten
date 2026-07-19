# Forge::Connection — connection handling
# Keep-alive, HTTP/2 multiplexing, graceful close

+ Connection
  ro :socket
  ro :config
  ro :protocol
  ro :created_at
  ro :request_count
  ro :h2_session

  -> new(@socket, config:)
    @config        = config
    @protocol      = self.detect_protocol
    @created_at    = Time.now
    @request_count = 0
    @h2_session    = nil

  -> read_request
    @request_count += 1

    case @protocol
      :h2 =>
        self.read_h2_request
      :http11 =>
        self.read_http11_request
      => nil

  -> write_response(response)
    case @protocol
      :h2 =>
        self.write_h2_response(response)
      :http11 =>
        @socket.write(response.to_http)

  -> keep_alive?
    @request_count < 1000 && (Time.now - @created_at) < @config.idle_timeout

  -> close
    if @h2_session
      @h2_session.goaway(H2:Frame:NO_ERROR) rescue nil
    @socket.close rescue nil

  # --- Protocol detection ---

  -> detect_protocol
    # HTTP/2 is negotiated via ALPN in TLS
    alpn = @socket.alpn_protocol
    if alpn
      case alpn
        "h2"       => :h2
        "http/1.1" => :http11
        => :http11
    else
      :http11

  # --- HTTP/1.1 ---

  -> read_http11_request
    raw = ""
    loop
      chunk = @socket.read(65536)
      break unless chunk
      raw += chunk
      break if raw.include?("\r\n\r\n")

    return nil if raw.empty?
    Request.parse(raw)

  -> write_http11_response(response)
    @socket.write(response.to_http)

  # --- HTTP/2 ---

  -> run_h2(handler)
    # Run HTTP/2 session — takes over the connection
    # handler is called with (request) and returns a response
    @h2_session = H2:Session.new(@socket)

    @h2_session.on_request -> (stream, headers, data)
      request = H2:RequestBuilder.build(headers, data)
      response = handler.call(request)
      H2:ResponseWriter.write(@h2_session, stream.id, response, @h2_session.hpack_encoder)

    @h2_session.run

  -> read_h2_request
    # Legacy stub — H2 uses run_h2 instead of request/response loop
    nil

  -> write_h2_response(response)
    # Legacy stub — H2 uses run_h2 instead
    nil
