# Forge::Request — HTTP request parsing
# Parses HTTP/1.1, HTTP/2, and HTTP/3 requests into a unified object

in Tungsten:Forge

+ Request
  ro :method
  ro :path
  ro :query_string
  ro :headers
  ro :body
  ro :version
  ro :remote_addr
  rw :params

  -> new(method:, path:, headers: {}, body: nil, version: "HTTP/1.1", remote_addr: nil)
    @method       = method.to_s.upcase.to_sym
    @path         = path
    @query_string = self.extract_query(path)
    @headers      = Headers.new(headers)
    @body         = body
    @version      = version
    @remote_addr  = remote_addr
    @params       = {}

  -> normalize_path!
    @path = @path.downcase.chomp("/")
    @path = "/" if @path.empty?

  -> content_type
    @headers.get("Content-Type")

  -> content_length
    @headers.get("Content-Length")&.to_i

  -> json?
    content_type&.include?("application/json")

  -> form?
    content_type&.include?("application/x-www-form-urlencoded")

  -> websocket_upgrade?
    @headers.get("Upgrade")&.downcase == "websocket"

  -> keep_alive?
    case @version
      "HTTP/1.0" => @headers.get("Connection")&.downcase == "keep-alive"
      => @headers.get("Connection")&.downcase != "close"

  -> json_body
    JSON.parse(@body) if @body && self.json?

  -> form_body
    QueryString.parse(@body) if @body && self.form?

  -> query_params
    QueryString.parse(@query_string) if @query_string

  # --- Parsing ---

  -> .parse(raw)
    line_end = raw.index("\r\n")
    request_line = raw.slice(0, line_end)
    sp1 = request_line.index(" ")
    sp2 = request_line.index(" ", sp1 + 1)

    method = request_line.slice(0, sp1)
    path_start = sp1 + 1
    path = request_line.slice(path_start, sp2 - path_start)
    version_start = sp2 + 1
    version = request_line.slice(version_start, request_line.size() - version_start)

    separator = raw.index("\r\n\r\n")
    header_end = raw.size()
    if separator
      header_end = separator

    headers = {}
    pos = line_end + 2
    while pos < header_end
      next_end = raw.index("\r\n", pos)
      if !next_end || next_end > header_end
        next_end = header_end

      colon = raw.index(": ", pos)
      if colon && colon < next_end
        key = raw.slice(pos, colon - pos)
        value_start = colon + 2
        value = raw.slice(value_start, next_end - value_start)
        headers[key] = value

      pos = next_end + 2

    body = nil
    if separator
      body_start = separator + 4
      body = raw.slice(body_start, raw.size() - body_start)

    self.new(
      method: method,
      path: path,
      headers: headers,
      body: body,
      version: version
    )

  -> extract_query(path)
    idx = path.index("?")
    if idx
      @path = path.slice(0, idx)
      query_start = idx + 1
      path.slice(query_start, path.size() - query_start)
    else
      nil


# --- Case-insensitive header access ---

+ Headers
  ro :raw

  -> new(@raw = {})
    @normalized = {}
    @raw.each -> (key, value)
      @normalized[key.downcase] = value

  -> get(name)
    @normalized[name.downcase]

  -> set(name, value)
    @raw[name] = value
    @normalized[name.downcase] = value

  -> has?(name)
    @normalized.key?(name.downcase)

  -> each(&block)
    @raw.each(&block)

  -> to_h
    @raw
