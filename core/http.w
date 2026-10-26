# HTTP — bounded HTTP/1.1 client and response framing.
#
# `https://` uses Core's in-process TLS client, including peer and hostname/IP
# verification. A runtime built without TLS support raises rather than falling
# back to a plain connection.
#
# Responses are buffered up to max_response_bytes. Streaming bodies, redirects,
# proxies, cancellation, and typed transport/status errors remain future API.

# HTTPResponse — immutable buffered HTTP response.
+ HTTPResponse
  ro :version, :status, :reason

  -> new(@version, @status, @reason, @headers, @body, @raw_resp = nil)

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

  -> success?
    @status >= 200 && @status < 300

  -> ok?
    success?()

  -> redirect?
    @status >= 300 && @status < 400


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
    raw = ""
    begin
      socket.set_timeout(timeout)
      if url.scheme == "https"
        TLS.client_wrap(socket, url.host)
        protocol = socket.alpn_protocol()
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

      loop
        chunk = socket.read(65_536)
        break if chunk == nil || chunk.empty?
        if raw.size + chunk.size > max_response_bytes
          raise "HTTP: response exceeds max_response_bytes"
        raw += chunk
    ensure
      socket.close()

    HTTP.parse_response(raw, verb)

  -> .build_request_head(verb, url, headers = {}, body = nil)
    body = body.to_s if body != nil
    method = verb.to_s.upcase
    if !HTTP.valid_token?(method)
      raise "HTTP: invalid request method"

    out = method + " " + url.request_target + " HTTP/1.1\r\n"
    host = url.host_for_output()
    if url.port != nil && url.port != url.default_port()
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

    separator = raw.index("\r\n\r\n")
    if separator == nil
      raise "HTTP: incomplete response headers"
    if separator == 0
      raise "HTTP: missing status line"

    view = ccall("w_string_bytes_view", raw) ## u8[]
    line_end = http_find_crlf(view, 0, separator)
    version = nil
    status = 0
    reason = ""
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
          reason = raw.slice(13, line_end - 13)
      else
        raise "HTTP: malformed response status"
    else
      status_line = raw.slice(0, line_end)
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

    headers = {}
    pos = line_end + 2
    while pos < separator
      next_crlf = http_find_crlf(view, pos, separator)
      b0 = view[pos] ## i64
      if next_crlf == pos || b0 == 32 || b0 == 9
        raise "HTTP: malformed response header"
      colon = http_find_colon_valid_token(view, pos, next_crlf)
      if colon == -1
        raise "HTTP: malformed response header"
      if colon == -2
        raise "HTTP: invalid response header name"
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
        raise "HTTP: invalid response header value"
      key = raw.slice(pos, colon - pos).downcase
      value = val_end > val_start ? raw.slice(val_start, val_end - val_start) : ""
      if headers[key] == nil
        headers[key] = value
      else
        headers[key] += ", " + value
      pos = next_crlf + 2

    body = raw.slice(separator + 4, raw.size - separator - 4)
    if status >= 100 && status < 200
      if status == 101
        raise "HTTP: protocol upgrades are not supported"
      if body.empty?
        raise "HTTP: informational response has no final response"
      return HTTP.parse_response(body, request_method)
    transfer_encoding = headers["transfer-encoding"]
    content_length = headers["content-length"]
    if transfer_encoding != nil && content_length != nil
      raise "HTTP: response has both Transfer-Encoding and Content-Length"

    no_body = request_method != nil && request_method.to_s.upcase == "HEAD"
    no_body = true if status == 204 || status == 304
    if no_body
      body = ""
    elsif transfer_encoding != nil
      if transfer_encoding.downcase.strip != "chunked"
        raise "HTTP: unsupported response Transfer-Encoding"
      body = HTTP.decode_chunked(body)
    elsif content_length != nil
      if content_length.empty? || !HTTP.decimal?(content_length)
        raise "HTTP: invalid Content-Length"
      expected = content_length.to_i
      if body.size < expected
        raise "HTTP: incomplete response body"
      if body.size > expected
        raise "HTTP: response contains bytes after Content-Length body"

    HTTPResponse.new(version, status, reason, headers, body)

  -> .decode_chunked(raw)
    out = StringBuffer(raw.size)
    cursor = 0
    loop
      line_end = raw.index("\r\n", cursor)
      if line_end == nil
        raise "HTTP: incomplete chunk size"
      size_line = raw.slice(cursor, line_end - cursor)
      extension = size_line.index(";")
      if extension != nil
        size_line = size_line.slice(0, extension)
      size_line = size_line.strip
      if size_line.empty? || !HTTP.hexadecimal?(size_line)
        raise "HTTP: invalid chunk size"
      chunk_size = size_line.to_i(16)
      cursor = line_end + 2

      if chunk_size == 0
        if raw.slice(cursor, 2) == "\r\n" && cursor + 2 == raw.size
          return out.to_s
        trailer_end = raw.index("\r\n\r\n", cursor)
        if trailer_end == nil || trailer_end + 4 != raw.size
          raise "HTTP: malformed chunk trailers"
        trailers = raw.slice(cursor, trailer_end - cursor).split("\r\n")
        i = 0
        while i < trailers.size
          trailer = trailers[i]
          colon = trailer.index(":")
          if colon == nil || colon == 0 || !HTTP.valid_token?(trailer.slice(0, colon))
            raise "HTTP: malformed chunk trailer"
          value = trailer.slice(colon + 1, trailer.size - colon - 1).strip
          if !HTTP.valid_field_value?(value)
            raise "HTTP: invalid chunk trailer value"
          i += 1
        return out.to_s

      if chunk_size > raw.size - cursor - 2
        raise "HTTP: incomplete chunk data"
      out.append(raw.slice(cursor, chunk_size))
      cursor += chunk_size
      if raw.slice(cursor, 2) != "\r\n"
        raise "HTTP: malformed chunk terminator"
      cursor += 2

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
