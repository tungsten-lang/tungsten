# Forge::CacheControl — Cache-Control directive parsing (RFC 7234 §5.2,
# extended by RFC 8246 immutable and RFC 5861 stale-while-revalidate /
# stale-if-error).
#
# Cache-Control is the header that governs HTTP freshness: how long a
# response may be reused before it goes stale, and whether it may be
# cached at all. It appears on BOTH sides of a conversation with
# different (overlapping) directive sets:
#
#   request  — max-age / max-stale / min-fresh / no-cache / no-store /
#              no-transform / only-if-cached / stale-if-error
#   response — public / private / no-cache / no-store / no-transform /
#              must-revalidate / proxy-revalidate / max-age / s-maxage /
#              immutable / stale-while-revalidate / stale-if-error
#
# Before this file Forge could only *write* a Cache-Control string
# (Response#cache / #no_cache and the static-file config) — nothing could
# read one back into structured form. A handler that wants to honour a
# client's "Cache-Control: no-cache" (force revalidation) or "max-age=0",
# or a cache layer that needs the freshness lifetime a response declares,
# had to substring-match the raw header by hand. This is the freshness
# companion to the validators (ETag / Last-Modified, see conditional.w)
# and the conditional-request evaluation already on the request surface.
#
# The grammar (RFC 7234 §5.2):
#
#     Cache-Control   = 1#cache-directive
#     cache-directive = token [ "=" ( token / quoted-string ) ]
#
# Directive names are case-insensitive (lower-cased here). A directive is
# either valueless (a flag, e.g. "no-cache") or carries a value after "="
# that may be a bare token or a DQUOTE-wrapped quoted-string (e.g.
# no-cache="Set-Cookie", private="X-Field"); the surrounding quotes are
# stripped. A comma inside a quoted-string is NOT a directive separator,
# so the split is quote-aware — same rule as ETag list parsing.
#
# Duplicate directives keep the FIRST occurrence (RFC 7234 leaves this
# undefined; first-wins matches Cookie parsing on this surface).
#
# delta-seconds directives (max-age, s-maxage, min-fresh, s-w-r, s-i-e)
# are 1*DIGIT per §1.2.1; a value that is empty or not all-digits is
# treated as absent numerically (the accessor returns nil), while the raw
# string is still reachable through #get.
#
# NOTE: no `&.` / safe-navigation and no early-return-from-inside-a-block
# below, mirroring the other request-surface parsers. Directive names and
# values stay Strings (arbitrary client input — never interned to
# Symbols).

+ CacheControl
  # The parsed directives: a Hash of downcased name => `true` (a valueless
  # flag) or the unquoted String value. Always present (empty when the
  # header was absent or blank), so callers never nil-guard.
  ro :directives

  -> new(directives = {})
    @directives = directives

  # Parse a Cache-Control header value into a CacheControl. Accepts nil /
  # blank (yields an empty instance). Request#cache_control and
  # Response#cache_control delegate here.
  -> .parse(header)
    directives = {}
    if header != nil
      s = header.strip
      if !s.empty?
        self.split_directives(s).each -> (part)
          eq = part.index("=")
          if eq == nil
            name = part.downcase
            directives[name] = true unless name.empty? || directives.key?(name)
          else
            name  = part.slice(0, eq).strip.downcase
            value = part.slice(eq + 1, part.size - eq - 1).strip
            if !name.empty? && !directives.key?(name)
              directives[name] = self.unquote(value)
    self.new(directives)

  # --- Generic access ---

  -> empty?
    @directives.size == 0

  # Is a directive present (by any name, case-insensitive)?
  -> has?(name)
    @directives.key?(name.downcase)

  # The raw value of a directive: `true` for a valueless flag, the
  # unquoted String for a value directive, or nil when it is absent.
  -> get(name)
    @directives[name.downcase]

  -> to_h
    @directives

  # --- Flag directives ---

  -> no_cache?
    @directives.key?("no-cache")

  -> no_store?
    @directives.key?("no-store")

  -> no_transform?
    @directives.key?("no-transform")

  -> must_revalidate?
    @directives.key?("must-revalidate")

  -> proxy_revalidate?
    @directives.key?("proxy-revalidate")

  -> public?
    @directives.key?("public")

  -> private?
    @directives.key?("private")

  -> only_if_cached?
    @directives.key?("only-if-cached")

  -> immutable?
    @directives.key?("immutable")

  # --- delta-seconds directives (Integer or nil) ---

  -> max_age
    self.int_value("max-age")

  -> s_maxage
    self.int_value("s-maxage")

  -> min_fresh
    self.int_value("min-fresh")

  -> stale_while_revalidate
    self.int_value("stale-while-revalidate")

  -> stale_if_error
    self.int_value("stale-if-error")

  # max-stale is special (RFC 7234 §5.2.1.2): absent => nil; present with
  # no value (or a malformed one) => :any (accept a stale response of any
  # age); present with a delta-seconds value => that Integer bound.
  -> max_stale
    return nil unless @directives.key?("max-stale")
    v = @directives["max-stale"]
    return :any if v == true
    return :any unless self.digits?(v)
    v.to_i

  # --- Field-name lists (no-cache / private response forms) ---

  # The header field-names a response's no-cache="f1, f2" restricts to, as
  # an Array of Strings (empty when no-cache is a bare flag or absent).
  -> no_cache_fields
    self.field_list("no-cache")

  # The header field-names a response's private="f1" scopes, as an Array
  # of Strings (empty when private is a bare flag or absent).
  -> private_fields
    self.field_list("private")

  # --- Internals ---

  # A directive's value as a non-negative Integer, or nil when the
  # directive is absent, valueless, or its value is not all ASCII digits.
  -> int_value(name)
    v = @directives[name]
    return nil if v == nil
    return nil if v == true
    return nil unless self.digits?(v)
    v.to_i

  -> digits?(s)
    return false if s.empty?
    ok = true
    i = 0
    n = s.size
    while i < n
      ok = false unless "0123456789".include?(s.slice(i, 1))
      i += 1
    ok

  -> field_list(name)
    v = @directives[name]
    return [] if v == nil || v == true
    out = []
    v.split(",").each -> (f)
      t = f.strip
      out.push(t) unless t.empty?
    out

  # Split a header on the commas that separate directives, honouring
  # quotes: a comma inside a quoted-string's DQUOTEs is kept literally.
  # Returns trimmed, non-empty tokens.
  -> .split_directives(s)
    parts = []
    buf = ""
    in_quote = false
    i = 0
    n = s.size
    while i < n
      ch = s.slice(i, 1)
      if ch == "\""
        buf = buf + ch
        in_quote = !in_quote
      elsif ch == "," && !in_quote
        parts.push(buf)
        buf = ""
      else
        buf = buf + ch
      i += 1
    parts.push(buf)
    out = []
    parts.each -> (p)
      t = p.strip
      out.push(t) unless t.empty?
    out

  # Strip one surrounding pair of double-quotes, if present.
  -> .unquote(value)
    n = value.size
    if n >= 2 && value.slice(0, 1) == "\"" && value.slice(n - 1, 1) == "\""
      value.slice(1, n - 2)
    else
      value
