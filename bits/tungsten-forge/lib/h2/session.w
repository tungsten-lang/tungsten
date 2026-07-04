# Forge::H2::Session — HTTP/2 connection manager
# RFC 7540: manages the full H2 lifecycle — connection preface, settings
# exchange, frame dispatch, stream multiplexing, and flow control.
#
# The writer goroutine pattern ensures that multiple request-handling
# goroutines can safely queue frames without interleaving on the wire.

in Tungsten:Forge:H2

+ Session
  ro :socket
  ro :streams
  ro :settings
  ro :peer_settings
  ro :hpack_decoder
  ro :hpack_encoder
  ro :write_channel
  rw :next_stream_id
  rw :last_stream_id
  rw :closed

  CONNECTION_PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  -> new(@socket)
    @streams = {}
    @settings = Settings.defaults
    @peer_settings = Settings.defaults
    @hpack_decoder = Decoder.new(max_size: 4096)
    @hpack_encoder = Encoder.new(max_size: 4096)
    @write_channel = Channel.new(256)
    @next_stream_id = 2
    @last_stream_id = 0
    @closed = false
    @on_request = nil
    @connection_window = 65535

  -> on_request(handler)
    @on_request = handler

  -> run
    begin
      self.read_connection_preface
      self.read_initial_settings
      self.send_our_settings
      self.send_settings_ack
      go -> self.writer_loop
      self.frame_loop
    rescue e
      self.goaway(Frame:INTERNAL_ERROR)
    ensure
      self.close

  # --- Connection startup ---

  -> read_connection_preface
    preface = @socket.read_exact(24)
    <! ConnectionError.new(Frame:PROTOCOL_ERROR, "Missing connection preface") unless preface

    expected = CONNECTION_PREFACE.to_bytes
    i = 0
    while i < 24
      if preface.get(i) != expected.get(i)
        <! ConnectionError.new(Frame:PROTOCOL_ERROR, "Invalid connection preface")
      i += 1

  -> read_initial_settings
    frame = Frame.read(@socket)

    unless frame && frame.type == Frame:SETTINGS && !frame.ack?
      <! ConnectionError.new(Frame:PROTOCOL_ERROR, "Expected SETTINGS frame after preface")

    self.apply_peer_settings(frame)

  -> send_our_settings
    pairs = @settings.to_a
    self.send_frame(Frame.settings(pairs))

  -> send_settings_ack
    self.send_frame(Frame.settings([], ack: true))

  # --- Write path ---

  -> send_frame(frame)
    @write_channel.send(frame)

  -> writer_loop
    loop
      frame = @write_channel.recv
      break unless frame
      @socket.write_bytes(frame.encode)

  # --- Read path ---

  -> frame_loop
    loop
      break if @closed
      frame = Frame.read(@socket)
      break unless frame
      self.dispatch_frame(frame)

  -> dispatch_frame(frame)
    case frame.type
      Frame:SETTINGS      => self.handle_settings(frame)
      Frame:HEADERS       => self.handle_headers(frame)
      Frame:CONTINUATION  => self.handle_continuation(frame)
      Frame:DATA          => self.handle_data(frame)
      Frame:WINDOW_UPDATE => self.handle_window_update(frame)
      Frame:PING          => self.handle_ping(frame)
      Frame:GOAWAY        => self.handle_goaway(frame)
      Frame:RST_STREAM    => self.handle_rst_stream(frame)

  # --- Frame handlers ---

  -> handle_settings(frame)
    return nil if frame.ack?
    self.apply_peer_settings(frame)
    self.send_frame(Frame.settings([], ack: true))

  -> handle_headers(frame)
    stream_id = frame.stream_id

    # Client-initiated streams must be odd
    if stream_id % 2 == 0
      <! ConnectionError.new(Frame:PROTOCOL_ERROR, "Client stream ID must be odd: [stream_id]")

    # Stream IDs must increase monotonically
    if stream_id <= @last_stream_id
      <! ConnectionError.new(Frame:PROTOCOL_ERROR, "Stream ID [stream_id] not greater than last [@last_stream_id]")

    @last_stream_id = stream_id
    stream = self.get_or_create_stream(stream_id)

    begin
      stream.receive_headers(frame)
    rescue e : StreamError
      self.send_frame(Frame.rst_stream(e.stream_id, e.error_code))
      return nil

    self.maybe_dispatch(stream) if stream.headers_complete

  -> handle_continuation(frame)
    stream = @streams[frame.stream_id]
    unless stream
      <! ConnectionError.new(Frame:PROTOCOL_ERROR, "CONTINUATION for unknown stream [frame.stream_id]")

    begin
      stream.receive_continuation(frame)
    rescue e : StreamError
      self.send_frame(Frame.rst_stream(e.stream_id, e.error_code))
      return nil

    self.maybe_dispatch(stream) if stream.headers_complete

  -> handle_data(frame)
    stream = @streams[frame.stream_id]
    unless stream
      <! ConnectionError.new(Frame:PROTOCOL_ERROR, "DATA for unknown stream [frame.stream_id]")

    begin
      stream.receive_data(frame)
    rescue e : StreamError
      self.send_frame(Frame.rst_stream(e.stream_id, e.error_code))
      return nil

    # Connection-level flow control: send WINDOW_UPDATE when half consumed
    length = frame.payload.size
    @connection_window -= length

    if @connection_window < 32768
      increment = 65535 - @connection_window
      self.send_frame(Frame.window_update(0, increment))
      @connection_window += increment

    self.maybe_dispatch(stream)

  -> handle_window_update(frame)
    if frame.stream_id == 0
      # Connection-level window update
      payload = frame.payload
      increment = ((payload.get(0) & 0x7F) << 24) | (payload.get(1) << 16) | (payload.get(2) << 8) | payload.get(3)

      if increment == 0
        <! ConnectionError.new(Frame:PROTOCOL_ERROR, "WINDOW_UPDATE with zero increment on connection")

      @connection_window += increment

      if @connection_window > 0x7FFFFFFF
        <! ConnectionError.new(Frame:FLOW_CONTROL_ERROR, "Connection flow control window overflow")
    else
      stream = @streams[frame.stream_id]
      return nil unless stream

      begin
        stream.receive_window_update(frame)
      rescue e : StreamError
        self.send_frame(Frame.rst_stream(e.stream_id, e.error_code))

  -> handle_ping(frame)
    if frame.stream_id != 0
      <! ConnectionError.new(Frame:PROTOCOL_ERROR, "PING on non-zero stream [frame.stream_id]")

    if frame.payload.size != 8
      <! ConnectionError.new(Frame:FRAME_SIZE_ERROR, "PING payload must be 8 bytes")

    return nil if frame.ack?
    self.send_frame(Frame.ping(frame.payload, ack: true))

  -> handle_goaway(frame)
    @closed = true

  -> handle_rst_stream(frame)
    stream = @streams[frame.stream_id]
    return nil unless stream

    begin
      stream.receive_rst_stream(frame)
    rescue e : StreamError
      nil

  # --- Request dispatch ---

  -> maybe_dispatch(stream)
    return nil unless stream.request_complete?
    self.dispatch_request(stream)

  -> dispatch_request(stream)
    headers = @hpack_decoder.decode(stream.header_block)
    data = stream.accumulated_data
    stream.reset_header_block

    go ->
      begin
        @on_request.call(stream, headers, data) if @on_request
      rescue e
        # Send RST_STREAM on handler error
        self.send_frame(Frame.rst_stream(stream.id, Frame:INTERNAL_ERROR))

  # --- Stream management ---

  -> get_or_create_stream(stream_id)
    existing = @streams[stream_id]
    return existing if existing

    initial_window = @peer_settings[Settings:INITIAL_WINDOW_SIZE] || 65535
    stream = Stream.new(stream_id, initial_window: initial_window)
    @streams[stream_id] = stream
    stream

  # --- Settings ---

  -> apply_peer_settings(frame)
    parsed = Settings.parse(frame.payload)
    parsed.each -> (id, value)
      @peer_settings[id] = value

    # Update HPACK decoder table size if changed
    if parsed.key?(Settings:HEADER_TABLE_SIZE)
      new_size = parsed[Settings:HEADER_TABLE_SIZE]
      @hpack_decoder = Decoder.new(max_size: new_size)

    # Update stream initial window sizes if changed
    if parsed.key?(Settings:INITIAL_WINDOW_SIZE)
      new_window = parsed[Settings:INITIAL_WINDOW_SIZE]
      old_window = 65535
      delta = new_window - old_window

      @streams.each -> (id, stream)
        stream.window_size = stream.window_size + delta

  # --- Connection lifecycle ---

  -> goaway(error_code, debug_data: Bytes.new(0))
    self.send_frame(Frame.goaway(@last_stream_id, error_code, debug_data: debug_data))
    @closed = true

  -> close
    @closed = true
    @write_channel.close
    @socket.close rescue nil


+ ConnectionError < StandardError
  ro :error_code

  -> new(@error_code, message)
    super(message)
