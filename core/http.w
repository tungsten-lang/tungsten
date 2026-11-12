# HTTP — bounded HTTP/1.1 client and response framing.
#
# `https://` uses Core's in-process TLS client, including peer and hostname/IP
# verification. A runtime built without TLS support raises rather than falling
# back to a plain connection.
#
# Responses are framed incrementally as they arrive (RFC 9112 section 6):
# HEAD/1xx/204/304 carry no body, `Transfer-Encoding: chunked` is decoded
# per section 7.1 (hex sizes, chunk extensions, trailer fields), a
# Content-Length body is read exactly, and anything else is read to EOF
# (HTTP/1.0 style). The client sends `Connection: close` and closes after one
# response, but never depends on the server closing: a complete message
# returns as soon as its framing says so. max_response_bytes bounds the bytes
# accepted from the transport, and an announced Content-Length or chunk size
# that cannot fit the remaining bound is refused before it is downloaded.
# Content-Encoding is not decoded; the body is delivered as sent.
#
# Streaming bodies, redirects, proxies, cancellation, per-phase timeouts, and
# typed transport/status errors remain future API.

# HTTPResponse — immutable buffered HTTP response.
+ HTTPResponse
  ro :version, :status, :reason

  -> new(@version, @status, @reason, @headers, @body, @raw_resp = nil, @trailers = nil)

  -> body
    if @body == nil && @raw_resp != nil
      bstart = ((@headers ## i64) >> 16) + 4
      @body = @raw_resp.slice(bstart, @raw_resp.size - bstart)
    @body

  -> headers
    if @raw_resp != nil
      bounds = @headers ## i64
      if @body == nil
        bstart = (bounds >> 16) + 4
        @body = @raw_resp.slice(bstart, @raw_resp.size - bstart)
      @headers = HTTP.__parse_headers(@raw_resp, bounds & 65535, bounds >> 16)
      @raw_resp = nil
    @headers

  -> header(name)
    self.headers[name.to_s.downcase]

  # Chunked trailer fields (RFC 9112 section 7.1.2), {} when there are none.
  # Trailers are kept apart from headers so a trailer can never alter framing
  # or routing decisions.
  -> trailers
    @trailers = {} if @trailers == nil
    @trailers

  -> trailer(name)
    self.trailers[name.to_s.downcase]

  -> success?
    @status >= 200 && @status < 300

  -> ok?
    success?()

  -> redirect?
    @status >= 300 && @status < 400


# HTTPReader — incremental HTTP/1.1 response framer over a Socket or a String.
#
# One decoder serves every transport: HTTP.request feeds it a Socket (plain
# TCP or TLS — Socket#read is transport-aware) and HTTP.parse_response feeds
# it an already-buffered String with socket = nil. limit bounds the bytes
# accepted in total (nil = unbounded); timeout is the socket's read deadline
# in milliseconds, used to tell an expired deadline from a peer close.
+ HTTPReader
  ro :trailers

  -> new(@socket, @buffer, @limit, @timeout)
    @cursor = 0
    @received = @buffer.size
    @trailers = {}
    if @limit != nil && @received > @limit
      raise "HTTP: response exceeds max_response_bytes"

  # Unconsumed buffered bytes.
  -> available
    @buffer.size - @cursor

  # Buffered bytes remain after the message ended.
  -> leftover?
    available() > 0

  # Everything up to the blank line that ends the head; raises at EOF.
  -> read_head
    loop
      head_end = @buffer.index("\r\n\r\n", @cursor)
      if head_end != nil
        head = @buffer.slice(@cursor, head_end - @cursor)
        @cursor = head_end + 4
        return head
      if !fill()
        raise "HTTP: incomplete response headers"

  # One line without its CRLF; raises "incomplete <what>" at EOF.
  -> read_line(what)
    loop
      line_end = @buffer.index("\r\n", @cursor)
      if line_end != nil
        line = @buffer.slice(@cursor, line_end - @cursor)
        @cursor = line_end + 2
        return line
      if !fill()
        raise "HTTP: incomplete " + what

  # Exactly count bytes; raises "incomplete <what>" at EOF. A count that
  # cannot fit the remaining bound is refused before anything is read, so an
  # announced size never causes a download.
  -> read_bytes(count, what)
    return "" if count == 0
    avail = available()
    if count <= avail
      out = @buffer.slice(@cursor, count)
      @cursor += count
      return out
    if @limit != nil && count - avail > @limit - @received
      raise "HTTP: response exceeds max_response_bytes"
    if @socket == nil
      raise "HTTP: incomplete " + what
    out = StringBuffer(count)
    if avail > 0
      out.append(@buffer.slice(@cursor, avail))
    @cursor = @buffer.size
    remaining = count - avail
    while remaining > 0
      want = 65_536
      want = remaining if remaining < want
      chunk = read_socket(want)
      if chunk == nil
        raise "HTTP: incomplete " + what
      count_received(chunk.size)
      out.append(chunk)
      remaining -= chunk.size
    out.to_s

  # Everything until EOF (HTTP/1.0-style framing).
  -> read_to_eof
    out = StringBuffer(available())
    if available() > 0
      out.append(@buffer.slice(@cursor, available()))
    @cursor = @buffer.size
    loop
      chunk = read_socket(65_536)
      break if chunk == nil
      count_received(chunk.size)
      out.append(chunk)
    out.to_s

  # RFC 9112 section 7.1: chunk-size [chunk-ext] CRLF chunk-data CRLF ...,
  # last-chunk, optional trailer section, CRLF. Chunk extensions are ignored;
  # trailer fields are parsed into `trailers`.
  -> read_chunked_body
    out = StringBuffer(0)
    loop
      size = HTTP.parse_chunk_size(read_line("chunk size"))
      break if size == 0
      out.append(read_bytes(size, "chunk data"))
      if read_line("chunk terminator") != ""
        raise "HTTP: malformed chunk terminator"
    section = ""
    loop
      line = read_line("chunk trailers")
      break if line.empty?
      section += "\r\n" if !section.empty?
      section += line
    if !section.empty?
      @trailers = HTTP.parse_fields(section, 0, "chunk trailer")
    out.to_s

  # Pull one more socket read into the buffer; false at EOF.
  -> fill
    chunk = read_socket(65_536)
    return false if chunk == nil
    count_received(chunk.size)
    if @cursor > 0
      if @cursor >= @buffer.size
        @buffer = ""
      else
        @buffer = @buffer.slice(@cursor, @buffer.size - @cursor)
      @cursor = 0
    @buffer += chunk
    true

  # Count bytes against the bound.
  -> count_received(count)
    if @limit != nil && @received + count > @limit
      raise "HTTP: response exceeds max_response_bytes"
    @received += count

  # One socket read; nil at EOF. Socket#read also returns nil when the read
  # deadline set by Socket#set_timeout expires, so a nil that arrives only
  # once the deadline has elapsed is reported as a timeout, not a close.
  -> read_socket(count)
    return nil if @socket == nil
    started = clock_ms()
    chunk = @socket.read(count)
    if chunk == nil || chunk.empty?
      if @timeout != nil && clock_ms() - started >= @timeout - 1
        raise "HTTP: timed out waiting for the response"
      return nil
    chunk


# HTTP — HTTP/1.1 requests over event-loop-backed Socket and TLS transports.
+ HTTP
  -> .get(source, headers = {}, timeout = 30_000)
    HTTP.request("GET", source, headers, nil, timeout)

  -> .head(source, headers = {}, timeout = 30_000)
    HTTP.request("HEAD", source, headers, nil, timeout)

  -> .post(source, body = "", headers = {}, timeout = 30_000)
    HTTP.request("POST", source, headers, body, timeout)

  -> .request(verb, source, headers = {}, body = nil, timeout = 30_000, max_response_bytes = 16_777_216)
    body = body.to_s if body != nil
    url = URL.parse(source.to_s)
    if url.scheme != "http" && url.scheme != "https"
      raise "HTTP: unsupported URL scheme: " + url.scheme
    if !url.authority? || url.host == nil || url.host.empty?
      raise "HTTP: URL requires a host"
    if url.username != nil || url.password != nil
      raise "HTTP: URL userinfo is not supported"
    if timeout <= 0
      raise "HTTP: timeout must be positive"
    if max_response_bytes <= 0
      raise "HTTP: max_response_bytes must be positive"

    request_head = HTTP.build_request_head(verb, url, headers, body)
    socket = Socket.connect(url.host, url.effective_port)
    response = nil
    begin
      socket.set_timeout(timeout)
      if url.scheme == "https"
        TLS.client_wrap(socket, url.host)
        protocol = socket.alpn_protocol
        if protocol != nil && protocol != "http/1.1"
          raise "HTTP: TLS negotiated unsupported ALPN protocol: " + protocol
      written = socket.write(request_head)
      if written != request_head.size
        raise "HTTP: connection closed while writing request headers"
      if body != nil && !body.empty?
        body_bytes = ccall("w_string_bytes_view", body) ## u8[]
        written = socket.write_bytes(body_bytes)
        if written != body_bytes.size
          raise "HTTP: connection closed while writing request body"

      reader = HTTPReader.new(socket, "", max_response_bytes, timeout)
      response = HTTP.read_response(reader, verb)
    ensure
      socket.close
    response

  -> .build_request_head(verb, url, headers = {}, body = nil)
    body = body.to_s if body != nil
    method = verb.to_s.upcase
    if !HTTP.valid_token?(method)
      raise "HTTP: invalid request method"

    out = method + " " + url.request_target + " HTTP/1.1\r\n"
    host = url.host_for_output
    if url.port != nil && url.port != url.default_port
      host += ":" + url.port.to_s
    out += "Host: " + host + "\r\n"

    headers.each -> (name_value, header_value)
      name = name_value.to_s
      value = header_value.to_s
      if !HTTP.valid_token?(name)
        raise "HTTP: invalid header name: " + name
      if !HTTP.valid_field_value?(value)
        raise "HTTP: invalid header value: " + name
      lower = name.downcase
      if lower == "transfer-encoding"
        raise "HTTP: request Transfer-Encoding is not supported"
      if lower != "host" && lower != "content-length" && lower != "connection"
        out += name + ": " + value + "\r\n"

    if body != nil
      out += "Content-Length: " + body.size.to_s + "\r\n"
    out += "Connection: close\r\n\r\n"
    out

  -> .__parse_headers(raw, start_pos, separator)
    view = ccall("w_string_bytes_view", raw) ## u8[]
    headers = {}
    pos = start_pos ## i64
    sep = separator ## i64
    while pos < sep
      next_crlf = http_find_crlf(view, pos, sep)
      colon = http_find_colon_valid_token(view, pos, next_crlf)
      val_start = colon + 1
      val_end = next_crlf
      while val_start < val_end
        vb = view[val_start] ## i64
        break if vb != 32 && vb != 9 && vb != 13 && vb != 10
        val_start += 1
      while val_end > val_start
        vb = view[val_end - 1] ## i64
        break if vb != 32 && vb != 9 && vb != 13 && vb != 10
        val_end -= 1
      key = raw.slice(pos, colon - pos).downcase
      value = val_end > val_start ? raw.slice(val_start, val_end - val_start) : ""
      if headers[key] == nil
        headers[key] = value
      else
        headers[key] += ", " + value
      pos = next_crlf + 2
    headers

  # Parse one complete buffered response. Bytes after the framed message are
  # an error here; the socket path simply closes the connection instead.
  #
  # The runtime's one-pass scanner (w_http_parse_fast) accepts only a final
  # response (status 200 and up, except 204 and 304) whose head is valid as
  # sent, with no Transfer-Encoding and no folded line, and whose body is
  # exactly the rest of the buffer: one Content-Length equal to it, or none
  # (read to EOF). HTTPReader frames such a message identically, so it is
  # returned without decoding, its headers and body parsed on first use.
  # Everything else, and every call that names a request method (HEAD changes
  # the framing), is framed by HTTP.read_response.
  -> .parse_response(raw, request_method = nil)
    if request_method == nil
      fast_pack = ccall("w_string_take_byte_array", raw, -14)
      if fast_pack != nil
        pk = fast_pack ## i64
        f_status = pk & 1023
        f_version = ((pk >> 10) & 1) == 1 ? "HTTP/1.1" : "HTTP/1.0"
        f_line_end = (pk >> 12) & 65535
        f_sep = (pk >> 28) & 262143
        if ((pk >> 11) & 1) == 1
          f_reason = "OK"
        elsif f_line_end <= 13
          f_reason = ""
        else
          f_reason = raw.slice(13, f_line_end - 13)
        f_bounds = (f_line_end + 2) | (f_sep << 16)
        return HTTPResponse.new(f_version, f_status, f_reason, f_bounds, nil, raw)

    reader = HTTPReader.new(nil, raw, nil, nil)
    response = HTTP.read_response(reader, request_method)
    if reader.leftover?
      raise "HTTP: response contains bytes after the message body"
    response

  # Read one response from reader: interim 1xx responses are consumed until
  # the final one, then the body is framed per RFC 9112 section 6.3.
  -> .read_response(reader, request_method = nil)
    version = nil
    status = 0
    reason = ""
    headers = {}
    loop
      head = reader.read_head
      if head.empty?
        raise "HTTP: missing status line"
      view = ccall("w_string_bytes_view", head) ## u8[]
      head_end = view.size ## i64
      line_end = http_find_crlf(view, 0, head_end)
      if line_end >= 12 && view[0] == 72 && view[1] == 84 && view[2] == 84 && view[3] == 80 && view[4] == 47 && view[5] == 49 && view[6] == 46 && view[8] == 32 && (view[7] == 49 || view[7] == 48)
        version = view[7] == 49 ? "HTTP/1.1" : "HTTP/1.0"
        d0 = view[9] ## i64
        d1 = view[10] ## i64
        d2 = view[11] ## i64
        if d0 < 48 || d0 > 57 || d1 < 48 || d1 > 57 || d2 < 48 || d2 > 57
          raise "HTTP: malformed response status"
        status = (d0 - 48) * 100 + (d1 - 48) * 10 + (d2 - 48)
        if line_end == 12
          reason = ""
        elsif view[12] == 32
          if !http_valid_field_range?(view, 13, line_end)
            raise "HTTP: invalid response reason"
          if line_end == 15 && view[13] == 79 && view[14] == 75
            reason = "OK"
          else
            reason = head.slice(13, line_end - 13)
        else
          raise "HTTP: malformed response status"
      else
        status_line = head.slice(0, line_end)
        first_space = status_line.index(" ")
        if first_space == nil
          raise "HTTP: malformed status line"
        second_space = status_line.index(" ", first_space + 1)
        version = status_line.slice(0, first_space)
        if version != "HTTP/1.0" && version != "HTTP/1.1"
          raise "HTTP: unsupported response version: " + version
        if second_space == nil
          status_text = status_line.slice(first_space + 1, status_line.size - first_space - 1)
          reason = ""
        else
          status_text = status_line.slice(first_space + 1, second_space - first_space - 1)
          reason = status_line.slice(second_space + 1, status_line.size - second_space - 1)
        if status_text.size != 3 || !HTTP.decimal?(status_text)
          raise "HTTP: malformed response status"
        if !HTTP.valid_field_value?(reason)
          raise "HTTP: invalid response reason"
        status = status_text.to_i
      headers = HTTP.parse_fields(head, line_end + 2, "response header")
      break if status < 100 || status >= 200
      if status == 101
        raise "HTTP: protocol upgrades are not supported"

    transfer_encoding = headers["transfer-encoding"]
    content_length = headers["content-length"]
    if transfer_encoding != nil && content_length != nil
      raise "HTTP: response has both Transfer-Encoding and Content-Length"
    if transfer_encoding != nil && version == "HTTP/1.0"
      raise "HTTP: Transfer-Encoding in an HTTP/1.0 response"

    no_body = request_method != nil && request_method.to_s.upcase == "HEAD"
    no_body = true if status == 204 || status == 304
    body = ""
    if no_body
      body = ""
    elsif transfer_encoding != nil
      if transfer_encoding.downcase.strip != "chunked"
        raise "HTTP: unsupported response Transfer-Encoding: " + transfer_encoding
      body = reader.read_chunked_body
    elsif content_length != nil
      if content_length.empty? || !HTTP.decimal?(content_length)
        raise "HTTP: invalid Content-Length"
      body = reader.read_bytes(content_length.to_i, "response body")
    else
      body = reader.read_to_eof

    HTTPResponse.new(version, status, reason, headers, body, nil, reader.trailers)

  # Decode one complete buffered chunked body (RFC 9112 section 7.1).
  -> .decode_chunked(raw)
    reader = HTTPReader.new(nil, raw, nil, nil)
    body = reader.read_chunked_body
    if reader.leftover?
      raise "HTTP: response contains bytes after the last chunk"
    body

  # chunk-size [ chunk-ext ] — hex digits, then an optional ";"-led extension
  # that is ignored (RFC 9112 section 7.1.1). Digits are accumulated with an
  # explicit width cap so no engine-specific to_i overflow behavior applies.
  -> .parse_chunk_size(line)
    text = line
    extension = text.index(";")
    if extension != nil
      text = text.slice(0, extension)
    text = text.strip
    if text.empty? || !HTTP.hexadecimal?(text)
      raise "HTTP: invalid chunk size"
    i = 0
    while i < text.size && text.slice(i, 1) == "0"
      i += 1
    if text.size - i > 15
      raise "HTTP: chunk size too large"
    size = 0
    while i < text.size
      size = size * 16 + "0123456789abcdef".index(text.slice(i, 1).downcase)
      i += 1
    size

  # Field lines in raw from byte start_pos to its end, CRLF-separated:
  # name ":" OWS value OWS. Duplicate names combine with ", ". A line starting
  # with SP or HTAB is an obs-fold continuation, which a user agent replaces
  # with a single SP before interpreting the value (RFC 9112 section 5.2).
  -> .parse_fields(raw, start_pos, what)
    view = ccall("w_string_bytes_view", raw) ## u8[]
    fields = {}
    last_key = nil
    pos = start_pos ## i64
    finish = view.size ## i64
    while pos < finish
      next_crlf = http_find_crlf(view, pos, finish)
      b0 = view[pos] ## i64
      folded = b0 == 32 || b0 == 9
      colon = pos
      val_start = pos
      if folded
        if last_key == nil
          raise "HTTP: malformed " + what
      else
        colon = http_find_colon_valid_token(view, pos, next_crlf)
        if colon == -1
          raise "HTTP: malformed " + what
        if colon == -2
          raise "HTTP: invalid " + what + " name"
        val_start = colon + 1
      val_end = next_crlf
      while val_start < val_end
        vb = view[val_start] ## i64
        break if vb != 32 && vb != 9 && vb != 13 && vb != 10
        val_start += 1
      while val_end > val_start
        vb = view[val_end - 1] ## i64
        break if vb != 32 && vb != 9 && vb != 13 && vb != 10
        val_end -= 1
      if !http_valid_field_range?(view, val_start, val_end)
        raise "HTTP: invalid " + what + " value"
      value = val_end > val_start ? raw.slice(val_start, val_end - val_start) : ""
      if folded
        if !value.empty?
          fields[last_key] += " " + value
      else
        last_key = raw.slice(pos, colon - pos).downcase
        if fields[last_key] == nil
          fields[last_key] = value
        else
          fields[last_key] += ", " + value
      pos = next_crlf + 2
    fields

  -> .valid_token?(text)
    return false if text == nil || text.empty?
    view = ccall("w_string_bytes_view", text) ## u8[]
    n = view.size ## i64
    i = 0 ## i64
    while i < n
      b = view[i] ## i64
      ok = (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || (b >= 48 && b <= 57) || b == 45 || b == 95 || b == 46 || b == 33 || (b >= 35 && b <= 39) || b == 42 || b == 43 || (b >= 94 && b <= 96) || b == 124 || b == 126
      return false if !ok
      i += 1
    true

  -> .decimal?(text)
    return false if text == nil || text.empty?
    view = ccall("w_string_bytes_view", text) ## u8[]
    n = view.size ## i64
    i = 0 ## i64
    while i < n
      b = view[i] ## i64
      return false if b < 48 || b > 57
      i += 1
    true

  -> .valid_field_value?(text)
    view = ccall("w_string_bytes_view", text) ## u8[]
    n = view.size ## i64
    i = 0 ## i64
    while i < n
      byte = view[i] ## i64
      return false if byte == 127 || (byte < 32 && byte != 9)
      i += 1
    true

  -> .hexadecimal?(text)
    return false if text == nil || text.empty?
    view = ccall("w_string_bytes_view", text) ## u8[]
    n = view.size ## i64
    i = 0 ## i64
    while i < n
      b = view[i] ## i64
      ok = (b >= 48 && b <= 57) || (b >= 97 && b <= 102) || (b >= 65 && b <= 70)
      return false if !ok
      i += 1
    true

-> http_find_crlf(view, start, limit) (u8[] i64 i64) i64
  i = start
  while i + 1 < limit
    if view[i] == 13 && view[i + 1] == 10
      return i
    i += 1
  limit

-> http_valid_field_range?(view, start, finish) (u8[] i64 i64) bool
  i = start
  while i < finish
    byte = view[i] ## i64
    if byte == 127 || (byte < 32 && byte != 9)
      return false
    i += 1
  true

-> http_find_colon_valid_token(view, start, finish) (u8[] i64 i64) i64
  i = start
  while i < finish
    b = view[i] ## i64
    if b == 58
      if i == start
        return 0 - 1
      return i
    ok = (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || (b >= 48 && b <= 57) || b == 45 || b == 95 || b == 46 || b == 33 || (b >= 35 && b <= 39) || b == 42 || b == 43 || (b >= 94 && b <= 96) || b == 124 || b == 126
    if !ok
      j = i + 1
      while j < finish
        if view[j] == 58
          return 0 - 2
        j += 1
      return 0 - 1
    i += 1
  0 - 1
