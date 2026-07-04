# Forge::H2::ResponseWriter — Serializes a Response into H2 frames
# Encodes response headers via HPACK, splits into HEADERS/CONTINUATION
# frames, and sends DATA frames respecting the peer's MAX_FRAME_SIZE.

in Tungsten:Forge:H2

+ ResponseWriter

  -> .write(session, stream_id, response, encoder)
    # Build headers array: pseudo-header first, then response headers
    headers = [[":status", response.status.to_s]]

    response.headers.each -> (name, value)
      headers.push([name.downcase, value])

    # HPACK encode the full header block
    header_block = encoder.encode(headers)

    # Determine peer's max frame size
    max_frame_size = session.peer_settings[Settings:MAX_FRAME_SIZE] || 16384

    has_body = response.body && response.body.size > 0
    end_stream = !has_body

    # Send HEADERS (+ CONTINUATION if needed)
    self.send_headers(session, stream_id, header_block, end_stream: end_stream, max_frame_size: max_frame_size)

    # Send body as DATA frames if present
    if has_body
      self.send_body(session, stream_id, response.body, max_frame_size: max_frame_size)

  -> .send_headers(session, stream_id, header_block, end_stream:, max_frame_size:)
    if header_block.size <= max_frame_size
      # Fits in a single HEADERS frame
      session.send_frame(Frame.headers(stream_id, header_block, end_stream: end_stream, end_headers: true))
    else
      # First chunk goes in HEADERS frame (no END_HEADERS)
      first = header_block.slice(0, max_frame_size)
      session.send_frame(Frame.headers(stream_id, first, end_stream: end_stream, end_headers: false))

      # Remaining chunks go in CONTINUATION frames
      offset = max_frame_size

      while offset < header_block.size
        remaining = header_block.size - offset
        chunk_size = if remaining < max_frame_size then remaining else max_frame_size
        chunk = header_block.slice(offset, chunk_size)
        is_last = (offset + chunk_size) >= header_block.size

        session.send_frame(Frame.continuation(stream_id, chunk, end_headers: is_last))

        offset += chunk_size

  -> .send_body(session, stream_id, body, max_frame_size:)
    data = body.to_bytes
    offset = 0

    while offset < data.size
      remaining = data.size - offset
      chunk_size = if remaining < max_frame_size then remaining else max_frame_size
      chunk = data.slice(offset, chunk_size)
      is_last = (offset + chunk_size) >= data.size

      session.send_frame(Frame.data(stream_id, chunk, end_stream: is_last))

      offset += chunk_size
