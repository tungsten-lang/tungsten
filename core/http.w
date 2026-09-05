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
  ro :version, :status, :reason, :headers, :body, :trailers

  -> new(@version, @status, @reason, @headers, @body, @trailers)

  -> header(name)
    @headers[name.to_s.downcase]

  # Chunked trailer field (RFC 9112 section 7.1.2). Trailers are kept apart
  # from headers so a trailer can never alter framing or routing decisions.
  -> trailer(name)
    @trailers[name.to_s.downcase]

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
    lines = []
    loop
      line = read_line("chunk trailers")
      break if line.empty?
      lines.push(line)
    @trailers = HTTP.parse_fields(lines, 0, "chunk trailer")
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

  # Parse one complete buffered response. Bytes after the framed message are
  # an error here; the socket path simply closes the connection instead.
  -> .parse_response(raw, request_method = nil)
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
      lines = reader.read_head.split("\r\n")
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
      headers = HTTP.parse_fields(lines, 1, "response header")
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

    HTTPResponse.new(version, status, reason, headers, body, reader.trailers)

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

  # Field lines from index start: name ":" OWS value OWS. Duplicate names
  # combine with ", ". A line starting with SP or HTAB is an obs-fold
  # continuation, which a user agent replaces with a single SP before
  # interpreting the value (RFC 9112 section 5.2).
  -> .parse_fields(lines, start, what)
    fields = {}
    last_key = nil
    i = start
    while i < lines.size
      line = lines[i]
      if line.starts_with?(" ") || line.starts_with?("\t")
        if last_key == nil
          raise "HTTP: malformed " + what
        continuation = line.strip
        if !HTTP.valid_field_value?(continuation)
          raise "HTTP: invalid " + what + " value"
        if !continuation.empty?
          fields[last_key] += " " + continuation
      else
        colon = line.index(":")
        if colon == nil || colon == 0
          raise "HTTP: malformed " + what
        name = line.slice(0, colon)
        if !HTTP.valid_token?(name)
          raise "HTTP: invalid " + what + " name"
        value = line.slice(colon + 1, line.size - colon - 1).strip
        if !HTTP.valid_field_value?(value)
          raise "HTTP: invalid " + what + " value"
        last_key = name.downcase
        if fields[last_key] == nil
          fields[last_key] = value
        else
          fields[last_key] += ", " + value
      i += 1
    fields

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
    bytes = text.bytes.to_a
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
