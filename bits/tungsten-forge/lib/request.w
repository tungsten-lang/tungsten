# Forge::Request — HTTP request parsing
# Parses HTTP/1.1, HTTP/2, and HTTP/3 requests into a unified object

+ Request
  ro :method
  ro :path
  ro :query_string
  ro :headers
  ro :body
  ro :version
  ro :remote_addr
  rw :params

  # Options-hash constructor (like Response.new): kwarg constructors
  # diverge between engines (the interpreter passes them as one hash,
  # compiled passes them positionally), so an explicit hash is the only
  # form that behaves identically in both.
  -> new(options = {})
    @method       = options[:method].to_s.upcase.to_sym
    @path         = options[:path]
    @query_string = self.extract_query(options[:path])
    @headers      = Headers.new(options[:headers] || {})
    @body         = options[:body]
    @version      = options[:version] || "HTTP/1.1"
    @remote_addr  = options[:remote_addr]
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

  # Parse a raw HTTP/1.1 request (request line + headers + optional body).
  # Split-based: String#index(needle, offset) diverges between engines
  # (the self-hosted interpreter ignores the offset argument), so parsing
  # never uses the offset form. Returns nil for a malformed request line.
  -> .parse(raw)
    separator = raw.index("\r\n\r\n")
    head = raw
    body = nil
    if separator
      head = raw.slice(0, separator)
      body_start = separator + 4
      body = raw.slice(body_start, raw.size() - body_start)

    lines = head.split("\r\n")
    result = nil
    if lines.size > 0
      parts = lines[0].split(" ")
      if parts.size >= 3
        headers = {}
        i = 1
        while i < lines.size
          line = lines[i]
          colon = line.index(": ")
          if colon
            key = line.slice(0, colon)
            value_start = colon + 2
            headers[key] = line.slice(value_start, line.size - value_start)
          i += 1

        result = self.new({
          method: parts[0],
          path: parts[1],
          headers: headers,
          body: body,
          version: parts[2]
        })
    result

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
