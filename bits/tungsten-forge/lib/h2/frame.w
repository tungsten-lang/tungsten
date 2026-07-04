# Forge::H2::Frame — HTTP/2 binary frame codec
# RFC 7540 Section 4: 9-byte header + variable-length payload

in Tungsten:Forge:H2

+ Frame
  ro :type
  ro :flags
  ro :stream_id
  ro :payload

  # Frame type constants
  DATA          = 0x0
  HEADERS       = 0x1
  PRIORITY      = 0x2
  RST_STREAM    = 0x3
  SETTINGS      = 0x4
  PUSH_PROMISE  = 0x5
  PING          = 0x6
  GOAWAY        = 0x7
  WINDOW_UPDATE = 0x8
  CONTINUATION  = 0x9

  # Flag constants
  END_STREAM    = 0x1
  END_HEADERS   = 0x4
  PADDED        = 0x8
  PRIORITY_FLAG = 0x20
  ACK           = 0x1

  # Error codes
  NO_ERROR            = 0x0
  PROTOCOL_ERROR      = 0x1
  INTERNAL_ERROR      = 0x2
  FLOW_CONTROL_ERROR  = 0x3
  SETTINGS_TIMEOUT    = 0x4
  STREAM_CLOSED       = 0x5
  FRAME_SIZE_ERROR    = 0x6
  REFUSED_STREAM      = 0x7
  CANCEL              = 0x8
  COMPRESSION_ERROR   = 0x9
  CONNECT_ERROR       = 0xa
  ENHANCE_YOUR_CALM   = 0xb
  INADEQUATE_SECURITY = 0xc
  HTTP_1_1_REQUIRED   = 0xd

  -> new(@type, @flags, @stream_id, @payload)

  # --- Wire format ---

  -> .read(socket)
    # Read the 9-byte frame header
    header = socket.read_exact(9)
    return nil unless header

    # Length: 3 bytes big-endian (bytes 0-2)
    length = (header.get(0) << 16) | (header.get(1) << 8) | header.get(2)

    # Type: 1 byte (byte 3)
    type = header.get(3)

    # Flags: 1 byte (byte 4)
    flags = header.get(4)

    # Stream ID: 4 bytes big-endian (bytes 5-8), mask reserved bit
    stream_id = ((header.get(5) << 24) | (header.get(6) << 16) |
                 (header.get(7) << 8)  |  header.get(8)) & 0x7FFFFFFF

    # Read payload
    payload = if length > 0
      socket.read_exact(length)
    else
      Bytes.new(0)

    self.new(type, flags, stream_id, payload)

  -> encode
    length = @payload.size

    # Build the 9-byte header
    header = Bytes.new(9)

    # Length: 3 bytes big-endian
    header.set(0, (length >> 16) & 0xFF)
    header.set(1, (length >> 8)  & 0xFF)
    header.set(2,  length        & 0xFF)

    # Type
    header.set(3, @type)

    # Flags
    header.set(4, @flags)

    # Stream ID: 4 bytes big-endian (top bit stays 0)
    header.set(5, (@stream_id >> 24) & 0x7F)
    header.set(6, (@stream_id >> 16) & 0xFF)
    header.set(7, (@stream_id >> 8)  & 0xFF)
    header.set(8,  @stream_id        & 0xFF)

    header.concat(@payload)

  # --- Factory methods ---

  -> .settings(settings_pairs, stream_id: 0, ack: false)
    flags = if ack then ACK else 0

    if ack
      return self.new(SETTINGS, flags, stream_id, Bytes.new(0))

    # Each setting is a 2-byte identifier + 4-byte value
    payload = Bytes.new(settings_pairs.size * 6)

    settings_pairs.each_with_index -> (pair, i)
      id    = pair[0]
      value = pair[1]
      offset = i * 6

      # Identifier: 2 bytes big-endian
      payload.set(offset,     (id >> 8) & 0xFF)
      payload.set(offset + 1,  id       & 0xFF)

      # Value: 4 bytes big-endian
      payload.set(offset + 2, (value >> 24) & 0xFF)
      payload.set(offset + 3, (value >> 16) & 0xFF)
      payload.set(offset + 4, (value >> 8)  & 0xFF)
      payload.set(offset + 5,  value        & 0xFF)

    self.new(SETTINGS, flags, stream_id, payload)

  -> .headers(stream_id, header_block, end_stream: false, end_headers: true)
    flags = 0
    flags = flags | END_STREAM  if end_stream
    flags = flags | END_HEADERS if end_headers
    self.new(HEADERS, flags, stream_id, header_block)

  -> .data(stream_id, data, end_stream: false)
    flags = if end_stream then END_STREAM else 0
    self.new(DATA, flags, stream_id, data)

  -> .ping(payload, ack: false)
    flags = if ack then ACK else 0
    # PING payload must be exactly 8 bytes
    buf = Bytes.new(8)
    max = if payload.size < 8 then payload.size else 8
    i = 0
    while i < max
      buf.set(i, payload.get(i))
      i += 1
    self.new(PING, flags, 0, buf)

  -> .goaway(last_stream_id, error_code, debug_data: Bytes.new(0))
    # 4 bytes last-stream-id + 4 bytes error code + debug data
    payload = Bytes.new(8)

    # Last stream ID: 4 bytes big-endian (top bit reserved)
    payload.set(0, (last_stream_id >> 24) & 0x7F)
    payload.set(1, (last_stream_id >> 16) & 0xFF)
    payload.set(2, (last_stream_id >> 8)  & 0xFF)
    payload.set(3,  last_stream_id        & 0xFF)

    # Error code: 4 bytes big-endian
    payload.set(4, (error_code >> 24) & 0xFF)
    payload.set(5, (error_code >> 16) & 0xFF)
    payload.set(6, (error_code >> 8)  & 0xFF)
    payload.set(7,  error_code        & 0xFF)

    payload = payload.concat(debug_data)
    self.new(GOAWAY, 0, 0, payload)

  -> .rst_stream(stream_id, error_code)
    payload = Bytes.new(4)
    payload.set(0, (error_code >> 24) & 0xFF)
    payload.set(1, (error_code >> 16) & 0xFF)
    payload.set(2, (error_code >> 8)  & 0xFF)
    payload.set(3,  error_code        & 0xFF)
    self.new(RST_STREAM, 0, stream_id, payload)

  -> .window_update(stream_id, increment)
    payload = Bytes.new(4)
    # Window size increment: 4 bytes big-endian (top bit reserved)
    payload.set(0, (increment >> 24) & 0x7F)
    payload.set(1, (increment >> 16) & 0xFF)
    payload.set(2, (increment >> 8)  & 0xFF)
    payload.set(3,  increment        & 0xFF)
    self.new(WINDOW_UPDATE, 0, stream_id, payload)

  -> .continuation(stream_id, header_block, end_headers: true)
    flags = if end_headers then END_HEADERS else 0
    self.new(CONTINUATION, flags, stream_id, header_block)

  # --- Query helpers ---

  -> end_stream?
    (@flags & END_STREAM) != 0

  -> end_headers?
    (@flags & END_HEADERS) != 0

  -> ack?
    (@flags & ACK) != 0

  -> padded?
    (@flags & PADDED) != 0

  -> priority?
    (@flags & PRIORITY_FLAG) != 0
