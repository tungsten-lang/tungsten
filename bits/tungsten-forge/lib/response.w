# Forge::Response — HTTP response building
# Fluent interface for constructing responses with headers and body

in Tungsten:Forge

+ Response
  rw :status
  rw :headers
  rw :body
  rw :stream

  -> new(status: 200, headers: {}, body: "")
    @status  = status
    @headers = {"Content-Type" => "text/html; charset=utf-8"}
    @headers.merge!(headers)
    @body    = body
    @stream  = nil

  # --- Factory methods ---

  -> .ok(body, content_type: "text/html; charset=utf-8")
    self.new(status: 200, headers: {"Content-Type" => content_type}, body: body)

  -> .json(data, status: 200)
    body = JSON.encode(data)
    self.new(status: status, headers: {"Content-Type" => "application/json"}, body: body)

  -> .html(body, status: 200)
    self.new(status: status, headers: {"Content-Type" => "text/html; charset=utf-8"}, body: body)

  -> .text(body, status: 200)
    self.new(status: status, headers: {"Content-Type" => "text/plain"}, body: body)

  -> .redirect(location, status: 302)
    self.new(status: status, headers: {"Location" => location}, body: "")

  -> .not_found(body = "Not Found")
    self.new(status: 404, body: body)

  -> .error(body = "Internal Server Error", status: 500)
    self.new(status: status, body: body)

  -> .no_content
    self.new(status: 204, body: "")

  -> .created(body = "", location: nil)
    headers = {}
    headers["Location"] = location if location
    self.new(status: 201, headers: headers, body: body)

  # --- Fluent interface ---

  -> header(name, value)
    @headers[name] = value
    self

  -> content_type(type)
    @headers["Content-Type"] = type
    self

  -> cache(max_age:, public: true)
    visibility = if public then "public" else "private"
    @headers["Cache-Control"] = "[visibility], max-age=[max_age]"
    self

  -> no_cache
    @headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
    self

  -> etag(value)
    @headers["ETag"] = "\"" + value + "\""
    self

  -> cookie(name, value, **options)
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
    body_len = @body.size()
    @headers["Content-Length"] = body_len.to_s unless @stream

    out = StringBuffer(128 + body_len)
    out << "HTTP/1.1 "
    out << @status
    out << " "
    out << self.status_text
    out << "\r\n"

    @headers.each -> (key, value)
      out << key
      out << ": "
      out << value
      out << "\r\n"

    out << "\r\n"
    out << @body
    out.to_s

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
