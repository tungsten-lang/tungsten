# Forge::Cookie — HTTP request Cookie header parsing (RFC 6265 §4.2 / §5.4).
#
# Turns the value of a request `Cookie` header ("a=1; b=2; theme=dark")
# into a Hash of String keys to String values. This is the class
# Request#cookies (and the single-name Request#cookie) delegate to — the
# request surface had no way to read an inbound cookie before this file,
# so sessions/auth handlers had to reach into the raw header and split it
# by hand. It is the inbound counterpart to Response#cookie, which writes
# an outbound Set-Cookie header.
#
# Parsing rules:
#   - cookie-pairs are separated by ";"
#   - each segment is whitespace-trimmed (so the SP that follows every
#     "; " per the grammar, and any sloppy padding, are absorbed)
#   - a segment splits on its FIRST "="; the name and value are trimmed
#   - a value wrapped in one pair of DQUOTEs is unwrapped (RFC 6265 allows
#     the quoted cookie-value form; other servers emit it)
#   - a segment with no "=" ("flag") yields name => "" (present, empty)
#   - a segment whose name is empty after trimming ("=x") is skipped
#   - empty segments (a stray or trailing ";") are skipped
#   - nil / empty header => {} (so callers never nil-guard the lookup)
#
# Two rules deliberately DIVERGE from QueryString (query/form parsing):
#
#   1. Duplicate names: the FIRST value wins, not the last. A client may
#      send several cookies of one name (RFC 6265 §5.4 orders them
#      most-specific-path first), and the first is authoritative — the
#      same choice Rack and the npm `cookie` package make. QueryString is
#      last-wins to match the header hash; cookies are their own surface.
#
#   2. Values are NOT percent-decoded. Cookie octets are opaque per RFC
#      6265, and Forge's Response#cookie writes values verbatim, so
#      parse and build round-trip byte-for-byte. Apps that URL-encode a
#      cookie value can decode it explicitly with QueryString.decode.
#
# Keys and values stay Strings (not Symbols): cookie names are arbitrary
# client input, and interning attacker-controlled text into symbols is a
# memory-growth foot-gun — same reasoning as QueryString and the header
# hash, all of which are String-keyed.
#
# NOTE: no `&.` / safe-navigation and no early-return-past-a-block below,
# mirroring request.w / query_string.w — the self-hosted interpreter
# implements neither.

+ Cookie
  # Parse a Cookie header value into { "name" => "value" }.
  -> .parse(header)
    result = {}
    if header != nil && !header.empty?
      header.split(";").each -> (segment)
        pair = segment.strip
        if !pair.empty?
          eq = pair.index("=")
          if eq == nil
            result[pair] = "" unless result.key?(pair)
          else
            name  = pair.slice(0, eq).strip
            value = pair.slice(eq + 1, pair.size - eq - 1).strip
            if !name.empty? && !result.key?(name)
              result[name] = self.unquote(value)
    result

  # Strip one surrounding pair of double-quotes, if present; otherwise
  # return the value unchanged.
  -> .unquote(value)
    n = value.size
    if n >= 2 && value.slice(0, 1) == "\"" && value.slice(n - 1, 1) == "\""
      value.slice(1, n - 2)
    else
      value
