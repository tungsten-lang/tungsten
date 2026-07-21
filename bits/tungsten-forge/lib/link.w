# Forge::Link — Web Linking header parsing and building (RFC 8288).
#
# The `Link` header is how an HTTP resource points at OTHER resources:
# pagination (`rel="next"` / `rel="prev"`), API discovery
# (`rel="describedby"`, `rel="service-doc"`), canonical URLs, preload
# hints, alternates, and the paging links every JSON API on the public
# internet emits (GitHub, Stripe, the W3C, ...). It is the one standard
# way a client walks a paginated collection without inventing a body
# convention.
#
# Forge could neither READ nor WRITE one before this file: nothing in the
# request/response surface mentioned Link, so a client had to substring
# match `rel="next"` out of the raw header by hand and a handler had to
# hand-assemble the string (getting the quoting wrong).
#
# The grammar (RFC 8288 section 3):
#
#     Link       = #link-value
#     link-value = "<" URI-Reference ">" *( OWS ";" OWS link-param )
#     link-param = token BWS [ "=" BWS ( token / quoted-string ) ]
#
# So a header is a comma-separated list of ENTRIES, each an
# angle-bracketed target URI followed by ";"-separated params:
#
#     Link: <https://api.example.com/items?page=2>; rel="next",
#           <https://api.example.com/items?page=9>; rel="last"; title="End"
#
# Parsing rules implemented here:
#   - the entry split honours BOTH angle brackets and quotes: a comma or
#     semicolon inside <...> (a URI may contain either) or inside a
#     quoted-string is NOT a separator
#   - param names are case-insensitive (downcased here); values may be a
#     bare token or a DQUOTE quoted-string, whose quotes are stripped and
#     whose "\X" escapes are unescaped (RFC 7230 quoted-string)
#   - a valueless param ("; noscript") is stored as `true`, like
#     CacheControl flag directives
#   - a duplicate param keeps the FIRST occurrence — RFC 8288 section 3
#     requires exactly this for rel/media/title/type ("occurrences after
#     the first MUST be ignored")
#   - `rel` may carry SEVERAL space-separated relation types in one value
#     (`rel="prev index"`); #rels splits them and every lookup matches any
#     of them
#   - a malformed entry (no "<", or no closing ">") is SKIPPED, not
#     raised: one bad entry from a proxy must not cost a client the rest
#     of the header. An absent/blank header parses to an empty Link, so
#     callers never nil-guard
#
# Relation types are compared case-insensitively (RFC 8288 section 3.3);
# the target URI keeps its exact bytes. Values stay Strings, never
# Symbols — arbitrary remote input must not be interned.
#
# RFC 8187 ext-values (`title*=UTF-8''...`) are exposed RAW through
# #param("title*"); they are not percent-decoded here (multipart.w treats
# `filename*` the same way).
#
# Building is the same object in reverse: `Link.new.add(url, {rel:
# "next"})` (or `Response#link`) and #to_s emits a conformant header.
#
# NOTE: no `&.` / safe-navigation and no early-return-past-a-block below,
# mirroring request.w / forwarded.w / cache_control.w — the self-hosted
# interpreter implements neither.

# One link-value: an angle-bracketed target plus its params.
+ LinkValue
  # The URI-Reference between "<" and ">", exactly as sent (never
  # resolved against a base — that needs the request URL, which the
  # header alone does not carry).
  ro :target
  # Downcased param name => unquoted String value, or `true` for a
  # valueless param. Insertion-ordered, first-occurrence-wins.
  ro :params

  # Hand-built values accept Symbol- or String-keyed params with any
  # stringable value: LinkValue.new("/p?page=2", {rel: "next"}).
  -> new(target, params = {})
    @target = target
    @params = LinkValue.normalize(params)

  # Parse ONE link-value ("<uri>; rel=\"next\"") into a LinkValue, or nil
  # when it is malformed (empty, or missing its <...> target).
  -> .parse(entry)
    return nil if entry == nil
    s = entry.strip
    return nil if s.empty?
    return nil unless s.slice(0, 1) == "<"
    close = s.index(">")
    return nil if close == nil
    target = s.slice(1, close - 1)
    rest   = s.slice(close + 1, s.size - close - 1)
    params = {}
    Link.split_top(rest, ";").each -> (piece)
      pair = piece.strip
      if !pair.empty?
        eq = pair.index("=")
        if eq == nil
          name = pair.downcase
          params[name] = true if !name.empty? && !params.key?(name)
        else
          name  = pair.slice(0, eq).strip.downcase
          value = pair.slice(eq + 1, pair.size - eq - 1).strip
          params[name] = Link.unquote(value) if !name.empty? && !params.key?(name)
    self.new(target, params)

  # --- Params ---

  # A param's value (case-insensitive name): the unquoted String, `true`
  # for a valueless param, or nil when it is absent.
  -> param(name)
    @params[name.to_s.downcase]

  -> has?(name)
    @params.key?(name.to_s.downcase)

  -> to_h
    @params

  # --- Well-known params (RFC 8288 section 3.4) ---

  # The raw `rel` value, verbatim and possibly multi-valued
  # ("prev index"), or nil. Use #rels / #rel? to test a relation type.
  -> rel
    self.string_param("rel")

  # The relation types this entry declares, downcased, in order. Empty
  # when the entry carries no (usable) rel — such an entry is a link with
  # no stated relation, which no rel lookup may match.
  -> rels
    v = self.rel
    return [] if v == nil
    LinkValue.split_ws(v.downcase)

  # Does this entry declare `name` as one of its relation types?
  # Case-insensitive, and true when rel carries several types.
  -> rel?(name)
    return false if name == nil
    wanted = name.to_s.strip.downcase
    return false if wanted.empty?
    found = false
    self.rels.each -> (r)
      found = true if r == wanted
    found

  -> title
    self.string_param("title")

  -> type
    self.string_param("type")

  -> hreflang
    self.string_param("hreflang")

  -> media
    self.string_param("media")

  # The context IRI this link applies to instead of the requested
  # resource (RFC 8288 section 3.2), or nil.
  -> anchor
    self.string_param("anchor")

  # --- Serialization ---

  # This entry as a conformant link-value. Values are always emitted as
  # quoted-strings (legal for every param, and the only safe choice for
  # one carrying a comma or semicolon); valueless params emit bare.
  -> to_s
    out = "<" + @target + ">"
    @params.each -> (name, value)
      if value == true
        out = out + "; " + name
      else
        out = out + "; " + name + "=\"" + LinkValue.escape(value) + "\""
    out

  # --- Internals ---

  # A param that must be a String to be meaningful: nil when absent or
  # valueless (a bare "; title" says nothing).
  -> string_param(name)
    v = @params[name]
    return nil if v == nil
    return nil if v == true
    v

  # Downcase param names, stringify values, drop nils, keep the first of
  # a duplicate. Accepts Symbol or String keys so hand-built params read
  # naturally.
  -> .normalize(params)
    out = {}
    if params != nil
      params.each -> (name, value)
        key = name.to_s.downcase
        if !key.empty? && !out.key?(key) && value != nil
          if value == true
            out[key] = true
          else
            out[key] = value.to_s
    out

  # Split on runs of ASCII whitespace, dropping empties. (String#split is
  # a literal split in both engines, so " ".split does not collapse runs
  # the way Ruby's awk-mode split does.)
  -> .split_ws(s)
    out = []
    buf = ""
    i = 0
    n = s.size
    while i < n
      ch = s.slice(i, 1)
      if ch == " " || ch == "\t"
        out.push(buf) unless buf.empty?
        buf = ""
      else
        buf = buf + ch
      i += 1
    out.push(buf) unless buf.empty?
    out

  # Escape a value for emission inside a quoted-string: "\" and DQUOTE
  # take a backslash (RFC 7230 quoted-pair).
  -> .escape(value)
    out = ""
    i = 0
    s = value.to_s
    n = s.size
    while i < n
      ch = s.slice(i, 1)
      out = out + "\\" if ch == "\\" || ch == "\""
      out = out + ch
      i += 1
    out


# The whole Link header: an ordered list of LinkValues, with lookup by
# relation type.
+ Link
  # The parsed entries in header order. Always an Array (empty when the
  # header was absent, blank, or entirely malformed).
  ro :entries

  -> new(entries = nil)
    @entries = entries || []

  # Parse a Link header value. Accepts nil / blank (yields an empty
  # Link). Request#links and Response#links delegate here.
  -> .parse(header)
    values = []
    if header != nil
      s = header.strip
      if !s.empty?
        self.split_top(s, ",").each -> (piece)
          v = LinkValue.parse(piece)
          values.push(v) if v != nil
    self.new(values)

  # --- Collection access ---

  -> size
    @entries.size

  -> empty?
    @entries.size == 0

  -> each(&block)
    @entries.each(&block)

  -> to_a
    @entries

  -> [](index)
    @entries[index]

  # --- Lookup by relation type ---

  # The FIRST entry declaring this relation type, or nil. Matching is
  # case-insensitive and honours multi-valued rels (`rel="prev index"`).
  -> find(rel)
    found = nil
    @entries.each -> (v)
      found = v if found == nil && v.rel?(rel)
    found

  # Every entry declaring this relation type, in header order (a resource
  # may offer several `rel="alternate"` representations).
  -> all(rel)
    out = []
    @entries.each -> (v)
      out.push(v) if v.rel?(rel)
    out

  # The target URI of the first entry with this relation type, or nil —
  # `links.href("next")` is the pagination one-liner.
  -> href(rel)
    v = self.find(rel)
    return nil if v == nil
    v.target

  -> has?(rel)
    self.find(rel) != nil

  # Every distinct relation type present, downcased, in first-seen order.
  -> rels
    out = []
    @entries.each -> (v)
      v.rels.each -> (r)
        out.push(r) unless Link.contains?(out, r)
    out

  # --- Building ---

  # Append a link-value; returns self so calls chain:
  #   Link.new.add("/items?page=2", {rel: "next"}).add("/items", {rel: "first"})
  -> add(target, params = {})
    @entries.push(LinkValue.new(target, params))
    self

  -> push(value)
    @entries.push(value)
    self

  # The entries as a conformant Link header value ("" when empty).
  -> to_s
    parts = []
    @entries.each -> (v)
      parts.push(v.to_s)
    parts.join(", ")

  # --- Internals ---

  # Split `str` on single-character `delim`, but only at the TOP level: a
  # delimiter inside <...> (a URI may contain "," and ";") or inside a
  # double-quoted string (honouring "\" escapes) is kept literally. Quote
  # and backslash bytes are preserved so `unquote` can process them
  # afterwards. Always returns at least one (possibly empty) piece.
  -> .split_top(str, delim)
    parts    = []
    buf      = ""
    in_quote = false
    in_angle = false
    escaped  = false
    i = 0
    n = str.size
    while i < n
      ch = str.slice(i, 1)
      if escaped
        buf = buf + ch
        escaped = false
      elsif in_quote && ch == "\\"
        buf = buf + ch
        escaped = true
      elsif ch == "\"" && !in_angle
        buf = buf + ch
        in_quote = !in_quote
      elsif ch == "<" && !in_quote
        buf = buf + ch
        in_angle = true
      elsif ch == ">" && !in_quote
        buf = buf + ch
        in_angle = false
      elsif ch == delim && !in_quote && !in_angle
        parts.push(buf)
        buf = ""
      else
        buf = buf + ch
      i += 1
    parts.push(buf)
    parts

  # Strip one surrounding pair of double-quotes and unescape "\X" -> "X"
  # inside them (RFC 7230 quoted-string). An unquoted token is returned
  # unchanged.
  -> .unquote(value)
    n = value.size
    if n >= 2 && value.slice(0, 1) == "\"" && value.slice(n - 1, 1) == "\""
      inner = value.slice(1, n - 2)
      out = ""
      i = 0
      m = inner.size
      while i < m
        ch = inner.slice(i, 1)
        if ch == "\\" && i + 1 < m
          i += 1
          out = out + inner.slice(i, 1)
        else
          out = out + ch
        i += 1
      out
    else
      value

  -> .contains?(list, value)
    found = false
    list.each -> (item)
      found = true if item == value
    found
