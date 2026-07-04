# Forge::ACME::HTTPClient — minimal HTTP/1.1 client for ACME
# Supports GET, POST, HEAD over HTTP and HTTPS (TLS)

in Tungsten:Forge:ACME

+ HTTPClient

  -> .get(url)
    self.request("GET", url)

  -> .post(url, body: "", content_type: "application/jose+json")
    self.request("POST", url, body: body, content_type: content_type)

  -> .head(url)
    self.request("HEAD", url)

  -> .request(method, url, body: "", content_type: nil)
    parsed  = self.parse_url(url)
    host    = parsed[:host]
    port    = parsed[:port]
    path    = parsed[:path]
    use_tls = parsed[:scheme] == "https"

    socket = Socket.connect(host, port)

    if use_tls
      socket = TLS.client_wrap(socket, host)

    # Build request
    request  = "[method] [path] HTTP/1.1\r\n"
    request += "Host: [host]\r\n"
    request += "Connection: close\r\n"
    request += "User-Agent: Tungsten-Forge-ACME/1.0\r\n"

    if content_type
      request += "Content-Type: [content_type]\r\n"

    if body && body.size > 0
      request += "Content-Length: [body.size]\r\n"

    request += "\r\n"

    if body && body.size > 0
      request += body

    # Send
    socket.write(request)

    # Read response — read until connection close
    raw = ""
    loop
      chunk = socket.read(65536)
      break unless chunk
      break if chunk.size == 0
      raw += chunk

    socket.close

    self.parse_response(raw)

  -> .parse_url(url)
    scheme = "https"
    rest   = url

    if url.starts_with?("https://")
      scheme = "https"
      rest   = url[8..]
    elsif url.starts_with?("http://")
      scheme = "http"
      rest   = url[7..]

    port = if scheme == "https" then 443 else 80

    # Split host from path
    slash_idx = rest.index("/")
    if slash_idx
      host_part = rest[0...slash_idx]
      path      = rest[slash_idx..]
    else
      host_part = rest
      path      = "/"

    # Check for explicit port in host
    colon_idx = host_part.index(":")
    if colon_idx
      host = host_part[0...colon_idx]
      port = host_part[(colon_idx + 1)..].to_i
    else
      host = host_part

    {scheme: scheme, host: host, port: port, path: path}

  -> .parse_response(raw)
    # Split headers from body at the blank line
    separator_idx = raw.index("\r\n\r\n")
    return HTTPResponse.new(0, {}, "") unless separator_idx

    header_section = raw[0...separator_idx]
    body_raw       = raw[(separator_idx + 4)..]

    lines       = header_section.split("\r\n")
    status_line = lines.first

    # Parse "HTTP/1.1 200 OK"
    parts  = status_line.split(" ", 3)
    status = parts[1].to_i

    # Parse headers
    headers = {}
    lines[1..].each -> (line)
      colon_idx = line.index(": ")
      if colon_idx
        key   = line[0...colon_idx].downcase
        value = line[(colon_idx + 2)..]
        headers[key] = value

    # Handle chunked transfer encoding
    body = if headers["transfer-encoding"] && headers["transfer-encoding"].include?("chunked")
      self.decode_chunked(body_raw)
    else
      body_raw

    HTTPResponse.new(status, headers, body)

  -> .decode_chunked(raw)
    decoded = ""
    remaining = raw

    loop
      # Find the chunk size line
      line_end = remaining.index("\r\n")
      break unless line_end

      size_str = remaining[0...line_end].strip
      chunk_size = size_str.to_i(16)
      break if chunk_size == 0

      chunk_start = line_end + 2
      decoded += remaining[chunk_start...(chunk_start + chunk_size)]
      remaining = remaining[(chunk_start + chunk_size + 2)..]

      break if remaining.size == 0

    decoded


+ HTTPResponse
  ro :status
  ro :headers
  ro :body

  -> new(@status, @headers, @body)

  -> header(name)
    @headers[name.downcase]

  -> ok?
    @status >= 200 && @status < 300
