# Forge::H2::RequestBuilder — Convert HPACK-decoded headers into a Forge::Request
# RFC 7540 Section 8.1.2.3: pseudo-header fields for requests
#
# Pseudo-headers (:method, :path, :scheme, :authority) are extracted
# and mapped to the corresponding Forge::Request fields. All remaining
# headers are passed through as regular HTTP headers.

in Tungsten:Forge:H2

+ RequestBuilder
  -> .build(headers, data)
    method    = nil
    path      = nil
    scheme    = nil
    authority = nil
    regular   = {}

    headers.each -> (pair)
      name  = pair[0]
      value = pair[1]

      if name.start_with?(":")
        case name
          ":method"    => method    = value
          ":path"      => path      = value
          ":scheme"    => scheme    = value
          ":authority" => authority = value
      else
        regular[name] = value

    # :method and :path are required per RFC 7540 Section 8.1.2.3
    <! H2Error.new("Missing :method pseudo-header") unless method
    <! H2Error.new("Missing :path pseudo-header")   unless path

    # Use :authority as Host header if not already present
    if authority && !regular.key?("host")
      regular["host"] = authority

    # Accumulate body from data chunks (may be nil or empty)
    body = if data && data.size > 0
      data.to_s

    Forge:Request.new(
      method:  method,
      path:    path,
      headers: regular,
      body:    body,
      version: "HTTP/2"
    )


+ H2Error < StandardError
