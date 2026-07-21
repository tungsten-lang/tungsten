# Forge::Multipart — multipart/form-data body parsing (RFC 7578 / RFC 2046).
#
# Turns a `multipart/form-data` request body into an ordered collection of
# parts, each carrying its form-field name, optional filename, optional
# per-part Content-Type, and raw body bytes. This is the enctype a browser
# uses for any form that uploads a file (`<form enctype="multipart/form-
# data">`) — the request surface had no way to read it before this file, so
# uploads and mixed file+field forms were simply unhandled. It is the
# structured sibling of QueryString (application/x-www-form-urlencoded), the
# other form encoding: QueryString maps flat name=value text to a Hash;
# multipart parts are richer (a filename and content-type per part, and a
# body that can be binary), so parsing yields a small MultipartForm object
# with typed accessors rather than a plain Hash.
#
# Request#multipart? / Request#multipart_body delegate here, mirroring
# Request#form? / #form_body over QueryString.
#
# Wire format (RFC 7578 §4):
#
#   --BOUNDARY CRLF
#   Content-Disposition: form-data; name="field" CRLF
#   CRLF
#   value CRLF
#   --BOUNDARY CRLF
#   Content-Disposition: form-data; name="file"; filename="a.txt" CRLF
#   Content-Type: text/plain CRLF
#   CRLF
#   <file bytes> CRLF
#   --BOUNDARY-- CRLF
#
# Parsing rules:
#   - the boundary is read from the Content-Type header's `boundary=`
#     parameter (quoted or bare); with no boundary, parse yields no parts
#   - the true delimiter is CRLF + "--" + boundary, so a "--boundary" that
#     happens to fall inside a part's bytes is NOT a false split; the body
#     is CRLF-prefixed before scanning so the opening delimiter matches too
#   - anything before the first delimiter (the preamble) and the segment
#     after the closing "--boundary--" (the epilogue) are ignored
#   - within a part, the first CRLFCRLF separates its headers from its body;
#     the CRLF that precedes the next boundary is the delimiter's, so it is
#     not part of the body (bodies come out with no trailing CRLF)
#   - Content-Disposition params (name, filename) are read by splitting the
#     header value on ";" and each token on its first "="; a value wrapped
#     in one pair of DQUOTEs is unwrapped. Splitting on tokens (not a raw
#     "name=" substring search) is deliberate: "filename=" contains the
#     bytes "name=", so a substring scan would confuse the two
#   - parts stay in wire order; duplicate names are all kept (a file input
#     can submit several files under one name), and the accessors return
#     the FIRST match
#
# Limitations (pragmatic, matching cookie.w / query_string.w): a ";" inside
# a quoted param value (e.g. a filename literally containing a semicolon)
# and a preamble that itself begins with CRLF are not handled — neither is
# emitted by real browsers. Percent-decoding is NOT applied: multipart
# field values are transmitted verbatim, unlike urlencoded forms.
#
# NOTE: no `&.` / safe-navigation, and every class method is single-exit
# (no early `return` in a method that also holds block closures) — both are
# self-hosted-interpreter constraints mirrored throughout forge's parsers.

+ Multipart
  # Parse a multipart body into a MultipartForm (always non-nil; its parts
  # list is empty when there is no boundary, no body, or no valid part).
  -> .parse(body, content_type)
    parts = []
    boundary = self.boundary(content_type)
    if boundary != nil && body != nil && !body.empty?
      dash = "\r\n--" + boundary
      segments = ("\r\n" + body).split(dash)
      # segments[0] is the preamble (before the opening boundary); every
      # later segment is a part, except the closing one which starts "--".
      rest = segments.slice(1, segments.size - 1)
      # A real part segment opens with the CRLF that ends its boundary
      # line; the closing "--boundary--" leaves a segment opening with "--".
      rest.each -> (seg)
        if seg.slice(0, 2) != "--"
          part = self.parse_part(seg)
          parts.push(part) if part != nil
    MultipartForm.new(parts)

  # Read the `boundary` parameter out of a Content-Type header value, or
  # nil when absent. The parameter name is matched case-insensitively; the
  # boundary value keeps its original case (boundaries are case-sensitive).
  -> .boundary(content_type)
    result = nil
    if content_type != nil
      content_type.split(";").each -> (token)
        t = token.strip
        eq = t.index("=")
        if eq != nil
          k = t.slice(0, eq).strip.downcase
          if k == "boundary" && result == nil
            v = t.slice(eq + 1, t.size - eq - 1).strip
            result = self.unquote(v)
    result

  # --- Internals ---

  # Turn one delimiter-bounded segment ("\r\n" + headers + CRLFCRLF + body)
  # into a MultipartPart, or nil when it has no usable structure.
  -> .parse_part(seg)
    result = nil
    lead = seg.index("\r\n")
    if lead != nil
      part_text = seg.slice(lead + 2, seg.size - lead - 2)
      header_block = part_text
      body = ""
      sep = part_text.index("\r\n\r\n")
      if sep != nil
        header_block = part_text.slice(0, sep)
        body = part_text.slice(sep + 4, part_text.size - sep - 4)

      disposition = nil
      ctype = nil
      header_block.split("\r\n").each -> (line)
        c = line.index(": ")
        if c != nil
          hname = line.slice(0, c).downcase
          hval = line.slice(c + 2, line.size - c - 2)
          if hname == "content-disposition"
            disposition = hval
          elsif hname == "content-type"
            ctype = hval

      name = nil
      filename = nil
      if disposition != nil
        dparams = self.params(disposition)
        name = dparams["name"]
        filename = dparams["filename"]

      result = MultipartPart.new(name, filename, ctype, body)
    result

  # Split a header value like `form-data; name="a"; filename="b.txt"` into
  # a { "name" => "a", "filename" => "b.txt" } Hash. The leading type token
  # ("form-data") has no "=" and is skipped; keys are downcased; values are
  # unquoted.
  -> .params(header_value)
    result = {}
    header_value.split(";").each -> (token)
      t = token.strip
      eq = t.index("=")
      if eq != nil
        k = t.slice(0, eq).strip.downcase
        v = t.slice(eq + 1, t.size - eq - 1).strip
        result[k] = self.unquote(v)
    result

  # Strip one surrounding pair of double-quotes, if present.
  -> .unquote(value)
    n = value.size
    if n >= 2 && value.slice(0, 1) == "\"" && value.slice(n - 1, 1) == "\""
      value.slice(1, n - 2)
    else
      value


# A single parsed part: its form-field name, optional filename (nil for a
# plain field), optional per-part Content-Type, and raw body String.
+ MultipartPart
  ro :name
  ro :filename
  ro :content_type
  ro :body

  -> new(@name, @filename, @content_type, @body)

  # A part is a file upload when it declared a filename.
  -> file?
    @filename != nil


# The ordered collection Multipart.parse returns. Callers usually reach for
# field / file by name; parts exposes the raw ordered list.
+ MultipartForm
  ro :parts

  -> new(@parts)

  -> size
    @parts.size

  -> empty?
    @parts.empty?

  -> each(&block)
    @parts.each(&block)

  # The first part with this name (file or field), or nil.
  -> part(name)
    found = nil
    @parts.each -> (p)
      if found == nil && p.name == name
        found = p
    found

  # The body String of the first part with this name, or nil — the common
  # "read a plain form field" path.
  -> field(name)
    p = self.part(name)
    if p == nil
      nil
    else
      p.body

  # The first uploaded file (a part that declared a filename) with this
  # name, or nil.
  -> file(name)
    found = nil
    @parts.each -> (p)
      if found == nil && p.name == name && p.filename != nil
        found = p
    found

  # Every part that is a file upload, in wire order.
  -> files
    @parts.select -> (p) p.filename != nil
