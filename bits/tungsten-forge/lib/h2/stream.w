# Forge::H2::Stream — HTTP/2 stream state machine
# RFC 7540 Section 5.1: Stream states and transitions
#
#                          +--------+
#                  send PP |        | recv PP
#                 ,--------|  idle  |--------.
#                /         |        |         \
#               v          +--------+          v
#        +----------+          |           +----------+
#        |          |          | send H /  |          |
#   ,----| reserved |          | recv H    | reserved |----.
#   |    | (local)  |          |           | (remote) |    |
#   |    +----------+          v           +----------+    |
#   |         |           +--------+           |           |
#   |         |   recv ES |        | send ES   |           |
#   |  send H |  ,--------|  open  |--------.  | recv H    |
#   |         | /         |        |         \ |           |
#   |         v v         +--------+          vv           |
#   |    +----------+          |           +----------+    |
#   |    |   half   |          |           |   half   |    |
#   |    |  closed  |          | send R /  |  closed  |    |
#   |    | (remote) |          | recv R    | (local)  |    |
#   |    +----------+          |           +----------+    |
#   |         |                |                |          |
#   |         | send ES /      |       recv ES /|          |
#   |         | send R /       v        send R /|          |
#   |         | recv R    +--------+    recv R  |          |
#   |  send R `---------->|        |<----------'  send R   |
#   `--------------------->| closed |<---------------------'
#                          |        |
#                          +--------+

in Tungsten:Forge:H2

+ Stream
  ro :id
  rw :state
  rw :window_size
  ro :header_block
  ro :data_chunks
  rw :headers_complete
  rw :end_stream

  -> new(@id, initial_window: 65535)
    @state = :idle
    @window_size = initial_window
    @header_block = Bytes.new(0)
    @data_chunks = []
    @headers_complete = false
    @end_stream = false

  # --- Receiving frames ---

  -> receive_headers(frame)
    # Validate state transition
    case @state
      :idle =>
        # idle -> open (or half_closed_remote if END_STREAM)
        nil
      :reserved_remote =>
        # reserved (remote) -> half_closed_local
        nil
      :half_closed_local =>
        # Trailers on half_closed_local are allowed
        nil
      =>
        <! StreamError.new(@id, Frame:PROTOCOL_ERROR, "HEADERS frame not allowed in state [@state]")

    # Accumulate header block fragment
    @header_block = @header_block.concat(frame.payload)

    # Check END_HEADERS
    @headers_complete = frame.end_headers?

    # Determine new state based on END_STREAM flag
    if frame.end_stream?
      @end_stream = true
      case @state
        :idle =>
          @state = :half_closed_remote
        :reserved_remote =>
          @state = :closed
        :half_closed_local =>
          @state = :closed
    else
      case @state
        :idle =>
          @state = :open
        :reserved_remote =>
          @state = :half_closed_local

  -> receive_continuation(frame)
    # CONTINUATION must follow HEADERS/CONTINUATION when headers are incomplete
    <! StreamError.new(@id, Frame:PROTOCOL_ERROR, "Unexpected CONTINUATION frame") if @headers_complete

    # Only valid in states that allow header blocks
    unless @state == :open || @state == :half_closed_local || @state == :half_closed_remote
      <! StreamError.new(@id, Frame:PROTOCOL_ERROR, "CONTINUATION frame not allowed in state [@state]")

    # Accumulate header block fragment
    @header_block = @header_block.concat(frame.payload)

    # Check END_HEADERS
    @headers_complete = frame.end_headers?

  -> receive_data(frame)
    # DATA frames are only valid in open or half_closed_local
    case @state
      :open =>
        nil
      :half_closed_local =>
        nil
      :half_closed_remote =>
        <! StreamError.new(@id, Frame:STREAM_CLOSED, "DATA frame received on [@state] stream")
      :closed =>
        <! StreamError.new(@id, Frame:STREAM_CLOSED, "DATA frame received on [@state] stream")
      =>
        <! StreamError.new(@id, Frame:PROTOCOL_ERROR, "DATA frame not allowed in state [@state]")

    # Deduct payload length from flow control window
    length = frame.payload.size
    @window_size -= length

    if @window_size < 0
      <! StreamError.new(@id, Frame:FLOW_CONTROL_ERROR, "Flow control window exceeded")

    # Accumulate data
    @data_chunks.push(frame.payload)

    # Check END_STREAM
    if frame.end_stream?
      @end_stream = true
      case @state
        :open =>
          @state = :half_closed_remote
        :half_closed_local =>
          @state = :closed

  -> receive_rst_stream(frame)
    # RST_STREAM can be received in any state except idle
    if @state == :idle
      <! StreamError.new(@id, Frame:PROTOCOL_ERROR, "RST_STREAM on idle stream")

    @state = :closed

  -> receive_window_update(frame)
    # WINDOW_UPDATE can be received in any state except idle and closed
    # (though closed streams may receive it as a race condition — ignore)
    if @state == :idle
      <! StreamError.new(@id, Frame:PROTOCOL_ERROR, "WINDOW_UPDATE on idle stream")

    return nil if @state == :closed

    # Parse the 4-byte increment (top bit reserved)
    payload = frame.payload
    increment = ((payload.get(0) & 0x7F) << 24) | (payload.get(1) << 16) | (payload.get(2) << 8) | payload.get(3)

    if increment == 0
      <! StreamError.new(@id, Frame:PROTOCOL_ERROR, "WINDOW_UPDATE with zero increment")

    @window_size += increment

    # Check for overflow (max is 2^31 - 1)
    if @window_size > 0x7FFFFFFF
      <! StreamError.new(@id, Frame:FLOW_CONTROL_ERROR, "Flow control window overflow")

  # --- Sending frames ---

  -> send_headers(end_stream: false)
    case @state
      :idle =>
        @state = if end_stream then :half_closed_local else :open
      :open =>
        # Sending trailers
        @state = :half_closed_local if end_stream
      :half_closed_remote =>
        @state = :closed if end_stream
      :reserved_local =>
        @state = if end_stream then :closed else :half_closed_remote
      =>
        <! StreamError.new(@id, Frame:PROTOCOL_ERROR, "Cannot send HEADERS in state [@state]")

  -> send_data(end_stream: false)
    case @state
      :open =>
        nil
      :half_closed_remote =>
        nil
      =>
        <! StreamError.new(@id, Frame:PROTOCOL_ERROR, "Cannot send DATA in state [@state]")

    if @window_size <= 0
      <! StreamError.new(@id, Frame:FLOW_CONTROL_ERROR, "Flow control window exhausted")

    if end_stream
      case @state
        :open =>
          @state = :half_closed_local
        :half_closed_remote =>
          @state = :closed

  -> send_rst_stream
    if @state == :idle
      <! StreamError.new(@id, Frame:PROTOCOL_ERROR, "Cannot send RST_STREAM on idle stream")

    @state = :closed

  # --- Query helpers ---

  -> request_complete?
    @headers_complete && @end_stream

  -> accumulated_data
    result = Bytes.new(0)
    @data_chunks.each -> (chunk)
      result = result.concat(chunk)
    result

  -> closed?
    @state == :closed

  -> reset_header_block
    @header_block = Bytes.new(0)
    @headers_complete = false


+ StreamError < StandardError
  ro :stream_id
  ro :error_code

  -> new(@stream_id, @error_code, message)
    super(message)
