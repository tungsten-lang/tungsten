# Forge Response — HTTP response building
# Fluent interface for constructing responses with headers and body

+ Response
  rw :status
  rw :headers
  rw :body
  rw :stream

  -> new(options = {})
    @status  = options[:status] || 200
    @headers = {"Content-Type" => "text/html; charset=utf-8"}
    @headers.merge!(options[:headers]) if options[:headers]
    @body    = options[:body] || ""
    @stream  = nil

  # --- Factory methods ---

  -> .ok(body, options = {})
    content_type = options[:content_type] || "text/html; charset=utf-8"
    self.new({status: 200, headers: {"Content-Type" => content_type}, body: body})

  -> .json(data, options = {})
    body = JSON.encode(data)
    self.new({status: options[:status] || 200, headers: {"Content-Type" => "application/json"}, body: body})

  -> .html(body, options = {})
    self.new({status: options[:status] || 200, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: body})

  -> .text(body, options = {})
    self.new({status: options[:status] || 200, headers: {"Content-Type" => "text/plain"}, body: body})

  -> .redirect(location, options = {})
    self.new({status: options[:status] || 302, headers: {"Location" => location}, body: ""})

  -> .not_found(body = "Not Found")
    self.new({status: 404, body: body})

  -> .error(body = "Internal Server Error", options = {})
    self.new({status: options[:status] || 500, body: body})

  -> .no_content
    self.new({status: 204, body: ""})

  -> .created(body = "", options = {})
    headers = {}
    headers["Location"] = options[:location] if options[:location]
    self.new({status: 201, headers: headers, body: body})

  # --- Fluent interface ---

  -> header(name, value)
    @headers[name] = value
    self

  -> content_type(type)
    @headers["Content-Type"] = type
    self

  -> cache(max_age, options = {})
    visibility = "public"
    visibility = "private" if options[:public] == false
    @headers["Cache-Control"] = "[visibility], max-age=[max_age]"
    self

  -> no_cache
    @headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
    self

  # The response's own Cache-Control directives as a structured
  # CacheControl (public?, private?, max_age, s_maxage, immutable?, …).
  # Reads the header case-insensitively — set by #cache / #no_cache or a
  # raw #header call — and always returns a CacheControl (empty when
  # unset). The read counterpart to the writers above; see
  # lib/cache_control.w.
  -> cache_control
    CacheControl.parse(self.header_value("Cache-Control"))

  # A response header value looked up case-insensitively (@headers keeps
  # the author's casing), or nil when no header matches.
  -> header_value(name)
    target = name.downcase
    found = nil
    @headers.each -> (key, value)
      found = value if key.downcase == target
    found

  -> etag(value)
    @headers["ETag"] = "\"" + value + "\""
    self

  # Append a Web Linking entry to the Link header (RFC 8288) — the
  # standard way to hand a client pagination, canonical, preload or
  # discovery URLs:
  #
  #   Response.json(page).link(next_url, {rel: "next"})
  #                      .link(last_url, {rel: "last", title: "End"})
  #
  # Params take Symbol or String keys and are emitted as quoted-strings.
  # Entries already on the header are preserved (it is reparsed and
  # rebuilt), and an existing header keeps whatever casing it was set
  # with. See lib/link.w.
  -> link(target, params = {})
    key = "Link"
    @headers.each -> (name, value)
      key = name if name.downcase == "link"
    links = Link.parse(@headers[key])
    links.add(target, params)
    @headers[key] = links.to_s
    self

  # The response's own Link header parsed into an ordered Link (empty
  # when unset). The read counterpart to #link.
  -> links
    Link.parse(self.header_value("Link"))

  -> cookie(name, value, options = {})
    parts = ["[name]=[value]"]
    parts.push("Path=[options[:path]]") if options[:path]
    parts.push("Max-Age=[options[:max_age]]") if options[:max_age]
    parts.push("HttpOnly") if options[:http_only]
    parts.push("Secure") if options[:secure]
    parts.push("SameSite=[options[:same_site]]") if options[:same_site]
    @headers["Set-Cookie"] = parts.join("; ")
    self

  # --- Serialization ---

  -> to_http
    body_len = @body.size
    @headers["Content-Length"] = body_len.to_s unless @stream

    out = "HTTP/1.1 [@status] [self.status_text]\r\n"
    @headers.each -> (key, value)
      out = out + key + ": " + value + "\r\n"

    out + "\r\n" + @body

  -> status_text
    case @status
      200 => "OK"
      201 => "Created"
      204 => "No Content"
      301 => "Moved Permanently"
      302 => "Found"
      304 => "Not Modified"
      400 => "Bad Request"
      401 => "Unauthorized"
      403 => "Forbidden"
      404 => "Not Found"
      405 => "Method Not Allowed"
      422 => "Unprocessable Entity"
      429 => "Too Many Requests"
      500 => "Internal Server Error"
      502 => "Bad Gateway"
      503 => "Service Unavailable"
      => "Unknown"
