# HTTP — bounded HTTP/1.1 client and response framing.
#
# The transport deliberately supports plain `http://` URLs only. Silently
# sending an `https://` request over Socket's plain TCP connection would leak
# credentials and body data; HTTPS stays unavailable until Core has an
# in-process client TLS transport with certificate and hostname verification.
#
# Responses are buffered up to max_response_bytes. Streaming bodies, redirects,
# proxies, cancellation, and typed transport/status errors remain future API.

# HTTPResponse — immutable buffered HTTP response.
+ HTTPResponse
  ro :version, :status, :reason, :headers, :body

  -> new(@version, @status, @reason, @headers, @body)

  -> header(name)
    @headers[name.to_s.downcase]

  -> success?
    @status >= 200 && @status < 300

  -> ok?
    success?()

  -> redirect?
    @status >= 300 && @status < 400


# HTTP — plain HTTP/1.1 requests over the event-loop-backed Socket transport.
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
    if url.scheme != "http"
      if url.scheme == "https"
        raise "HTTP: https requires a verified in-process TLS client transport"
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
    socket.set_timeout(timeout)
    raw = ""
    begin
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

  -> .parse_response(raw, request_method = nil)
    separator = raw.index("\r\n\r\n")
    if separator == nil
      raise "HTTP: incomplete response headers"

    header_text = raw.slice(0, separator)
    lines = header_text.split("\r\n")
    if lines.empty?
      raise "HTTP: missing status line"
    status_line = lines[0]
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
    i = 1
    while i < lines.size
      line = lines[i]
      if line.empty? || line.starts_with?(" ") || line.starts_with?("\t")
        raise "HTTP: malformed response header"
      colon = line.index(":")
      if colon == nil || colon == 0
        raise "HTTP: malformed response header"
      name = line.slice(0, colon)
      if !HTTP.valid_token?(name)
        raise "HTTP: invalid response header name"
      value = line.slice(colon + 1, line.size - colon - 1).strip
      if !HTTP.valid_field_value?(value)
        raise "HTTP: invalid response header value"
      key = name.downcase
      if headers[key] == nil
        headers[key] = value
      else
        headers[key] += ", " + value
      i += 1

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
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~"
    i = 0
    while i < text.size
      return false if allowed.index(text.slice(i, 1)) == nil
      i += 1
    true

  -> .decimal?(text)
    return false if text == nil || text.empty?
    i = 0
    while i < text.size
      return false if "0123456789".index(text.slice(i, 1)) == nil
      i += 1
    true

  -> .valid_field_value?(text)
    bytes = text.bytes
    i = 0
    while i < bytes.size
      byte = bytes[i]
      return false if byte == 127 || (byte < 32 && byte != 9)
      i += 1
    true

  -> .hexadecimal?(text)
    return false if text == nil || text.empty?
    i = 0
    while i < text.size
      return false if "0123456789abcdefABCDEF".index(text.slice(i, 1)) == nil
      i += 1
    true
