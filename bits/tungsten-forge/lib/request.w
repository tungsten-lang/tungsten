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
  # form that behaves identically in both. options[:headers] may be a
  # plain hash (normalized here) or an already-built Headers (the parse
  # fast path — no second walk).
  -> new(options = {})
    @method       = options[:method].to_s.upcase.to_sym
    @path         = options[:path]
    @query_string = self.extract_query(options[:path])
    given = options[:headers]
    if given == nil
      given = {}
    if given.is_a?(Headers)
      @headers = given
    else
      @headers = Headers.new(given)
    @body         = options[:body]
    @version      = options[:version] || "HTTP/1.1"
    @remote_addr  = options[:remote_addr]
    @params       = {}

  -> normalize_path!
    @path = @path.downcase.chomp("/")
    @path = "/" if @path.empty?

  -> content_type
    @headers.get("Content-Type")

  # NOTE: no `&.` below — the self-hosted interpreter does not implement
  # safe navigation (`Unknown AST node type: safe_nav`; it segfaults when
  # reached inside a method), so every nil check is written out plainly.

  -> content_length
    value = @headers.get("Content-Length")
    return nil if value == nil
    value.to_i

  -> json?
    ct = self.content_type
    return false if ct == nil
    ct.include?("application/json")

  -> form?
    ct = self.content_type
    return false if ct == nil
    ct.include?("application/x-www-form-urlencoded")

  -> multipart?
    ct = self.content_type
    return false if ct == nil
    ct.include?("multipart/form-data")

  -> websocket_upgrade?
    upgrade = @headers.get("Upgrade")
    return false if upgrade == nil
    upgrade.downcase == "websocket"

  # HTTP/1.1 defaults to keep-alive ("Connection: close" opts out);
  # HTTP/1.0 defaults to close ("Connection: keep-alive" opts in).
  -> keep_alive?
    token = ""
    value = @headers.get("Connection")
    if value != nil
      token = value.downcase
    if @version == "HTTP/1.0"
      return token == "keep-alive"
    token != "close"

  -> json_body
    JSON.parse(@body) if @body && self.json?

  -> form_body
    QueryString.parse(@body) if @body && self.form?

  # Parsed multipart/form-data body as a MultipartForm (fields + files), or
  # nil when the request is not multipart or carries no body. The
  # structured counterpart to form_body — see lib/multipart.w.
  -> multipart_body
    Multipart.parse(@body, self.content_type) if @body && self.multipart?

  -> query_params
    QueryString.parse(@query_string) if @query_string

  # Inbound cookies as { "name" => "value" }. Always a Hash (empty when
  # the request carries no Cookie header), so callers can index straight
  # into it — see lib/cookie.w for the parsing rules.
  -> cookies
    Cookie.parse(@headers.get("Cookie"))

  # The value of a single cookie by name, or nil when it is absent.
  -> cookie(name)
    self.cookies[name]

  # --- Content negotiation (see lib/negotiation.w) ---

  # Does the client's Accept header accept this media type? Honours media
  # ranges ("text/*", "*/*") and explicit ";q=0" refusals. An absent
  # Accept header accepts everything.
  -> accepts?(media_type)
    Negotiation.accepts?(@headers.get("Accept"), media_type, :media)

  # Given the media types this endpoint can produce, the client's most
  # preferred, or nil when it accepts none of them. Ties go to the
  # server's ordering (offered first = server preference).
  -> preferred_type(offered)
    Negotiation.best(@headers.get("Accept"), offered, :media)

  # The client's preferred language from those offered (Accept-Language),
  # or nil. A range "en" matches an offered tag "en-US".
  -> preferred_language(offered)
    Negotiation.best(@headers.get("Accept-Language"), offered, :lang)

  # The client's preferred content-coding from those offered
  # (Accept-Encoding), or nil. Honours ";q=0" refusals — unlike a bare
  # header substring check.
  -> preferred_encoding(offered)
    Negotiation.best(@headers.get("Accept-Encoding"), offered, :token)

  # The media ranges the client accepts, best-first (descending quality;
  # ";q=0" refusals dropped). Empty when there is no Accept header.
  -> accepted_media_types
    Negotiation.ranked(@headers.get("Accept"))

  # --- Byte ranges (see lib/byte_range.w) ---

  # The raw Range request header value, or nil when it is absent.
  -> range_header
    @headers.get("Range")

  # The byte ranges requested for a representation of `total` bytes
  # (RFC 7233). Returns nil when there is no usable Range header (serve the
  # full 200 body), :unsatisfiable when a valid bytes range-set fits none
  # of the resource (reply 416), or an Array of satisfiable ByteRanges in
  # request order (reply 206). See ByteRange for the resolved offsets.
  -> ranges(total)
    ByteRange.resolve(@headers.get("Range"), total)

  # --- Proxy forwarding (see lib/forwarded.w) ---

  # The structured RFC 7239 `Forwarded` header: an ordered Array of
  # elements, each a Hash of downcased param name => value (leftmost =
  # originating client). Empty when there is no Forwarded header.
  -> forwarded
    Forwarded.parse(@headers.get("Forwarded"))

  # The forwarded address chain as bare hosts, client-first. Read from the
  # RFC 7239 `Forwarded` `for=` values when present, else from
  # `X-Forwarded-For`. Ports and IPv6 brackets are stripped. Empty when
  # the request did not arrive through a proxy.
  -> forwarded_for
    hosts = []
    self.forwarded.each -> (el)
      f = el["for"]
      hosts.push(Forwarded.node_host(f)) if f != nil
    if hosts.size == 0
      Forwarded.split_list(@headers.get("X-Forwarded-For")).each -> (tok)
        hosts.push(Forwarded.node_host(tok))
    hosts

  # Best guess at the originating client's IP: the leftmost forwarded
  # address, or @remote_addr (the TCP peer) when the request did not come
  # through a proxy. SECURITY: the header is client-forgeable — trust this
  # only when a proxy you control sanitizes the inbound value (see
  # lib/forwarded.w).
  -> client_ip
    chain = self.forwarded_for
    if chain.size > 0
      chain[0]
    else
      @remote_addr

  # The scheme the client originally used ("https" / "http"), downcased,
  # from the RFC 7239 `proto` param or `X-Forwarded-Proto`, or nil when
  # neither is present.
  -> forwarded_proto
    proto = nil
    self.forwarded.each -> (el)
      p = el["proto"]
      proto = p if proto == nil && p != nil
    if proto == nil
      list = Forwarded.split_list(@headers.get("X-Forwarded-Proto"))
      proto = list[0] if list.size > 0
    if proto == nil
      proto
    else
      proto.downcase

  # The Host the client originally requested, from the RFC 7239 `host`
  # param or `X-Forwarded-Host`, or nil when neither is present.
  -> forwarded_host
    host = nil
    self.forwarded.each -> (el)
      h = el["host"]
      host = h if host == nil && h != nil
    if host == nil
      list = Forwarded.split_list(@headers.get("X-Forwarded-Host"))
      host = list[0] if list.size > 0
    host

  # The original client-facing port from `X-Forwarded-Port` as an Integer,
  # or nil when the header is absent.
  -> forwarded_port
    list = Forwarded.split_list(@headers.get("X-Forwarded-Port"))
    if list.size > 0
      list[0].to_i
    else
      nil

  # Did the client originally connect over TLS? True when the forwarded
  # scheme is "https".
  -> forwarded_ssl?
    self.forwarded_proto == "https"

  # Did this request arrive through at least one proxy that announced a
  # forwarded address (either header family)?
  -> via_proxy?
    self.forwarded_for.size > 0

  # --- Parsing ---

  # Parse a raw HTTP/1.1 request (request line + headers + optional body).
  #
  # Single forward scan (profile-guided rewrite): the split("\r\n")
  # parser it replaces allocated a line array plus a string per header
  # line, then Headers.new re-walked the finished hash to build a
  # downcased twin — Request#parse was 13.9% of server time under hammer
  # load, the top forge-code cost. Now each boundary is found once with
  # index(needle, offset) (offset honored by both engines since 3637550),
  # header names are downcased straight into the one normalized hash
  # Headers wraps, and the body honors Content-Length, so a pipelined
  # remainder is never swallowed (the old parser returned everything
  # after the blank line; without a Content-Length that remains the
  # fallback). Value bytes keep their original case.
  #
  # Returns nil for a malformed request line — exactly the old cases: a
  # first line with fewer than three single-space-separated fields
  # (split(" ") was literal, so "GET  / HTTP/1.1" still parses, with an
  # empty path). Header lines without ": " are skipped, the first ": "
  # in a line wins, and duplicate header names keep the LAST value
  # (matching the old normalize-last-wins and content_length_in's
  # rindex scan).
  -> .parse(raw)
    size = raw.size
    line_end = raw.index("\r\n")
    if line_end == nil
      line_end = size
    sp1 = raw.index(" ")
    sp2 = nil
    if sp1 != nil && sp1 < line_end
      sp2 = raw.index(" ", sp1 + 1)
    result = nil
    if sp2 != nil && sp2 < line_end
      vend = raw.index(" ", sp2 + 1)
      if vend == nil || vend > line_end
        vend = line_end

      headers = {}
      body = nil
      pos = line_end + 2
      while pos < size
        eol = raw.index("\r\n", pos)
        if eol == pos
          # Blank line — the body follows, bounded by Content-Length.
          body_start = pos + 2
          body_len = size - body_start
          cl = headers["content-length"]
          if cl != nil
            n = cl.to_i
            if n < body_len
              body_len = n
            if body_len < 0
              body_len = 0
          body = raw.slice(body_start, body_len)
          pos = size
        else
          stop = eol
          if stop == nil
            stop = size
          # index scans past `stop` when a line lacks ": " — the guard
          # below rejects those matches, so the line is just skipped.
          colon = raw.index(": ", pos)
          if colon != nil && colon < stop
            name = raw.slice(pos, colon - pos).downcase
            headers[name] = raw.slice(colon + 2, stop - colon - 2)
          pos = stop + 2

      built = Headers.new(headers, true)
      result = self.new({
        method: raw.slice(0, sp1),
        path: raw.slice(sp1 + 1, sp2 - sp1 - 1),
        headers: built,
        body: body,
        version: raw.slice(sp2 + 1, vend - sp2 - 1)
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
#
# One hash, keys downcased at insertion. (The previous shape kept the
# raw-cased hash AND a normalized twin, so every request paid a second
# full walk; nothing in forge or carbide ever read the raw casing.)
# each / to_h / raw therefore expose normalized lowercase names.

+ Headers
  # `normalized: true` trusts that `raw`'s keys are already lowercase —
  # Request.parse builds its hash that way in its single scan.
  -> new(raw = {}, normalized = false)
    if normalized == true
      @h = raw
    else
      @h = {}
      raw.each -> (key, value)
        @h[key.downcase] = value

  -> get(name)
    @h[name.downcase]

  -> set(name, value)
    @h[name.downcase] = value

  -> has?(name)
    @h.key?(name.downcase)

  -> each(&block)
    @h.each(&block)

  -> to_h
    @h

  -> raw
    @h
