# Forge::Authorization — HTTP authentication credential parsing
# (RFC 7235 credentials, RFC 6750 Bearer, RFC 7617 Basic).
#
# Turns the value of an `Authorization` (or `Proxy-Authorization`) request
# header into a structured `Credentials` — a scheme token plus the raw
# credential string — with conveniences for the two schemes almost every
# app actually reads:
#
#   Bearer:  request.bearer_token            # "Bearer <token68>"  -> the token
#   Basic:   request.basic_auth              # "Basic <base64>"    -> {username:, password:}
#
# This is the request-surface counterpart to the cookie / query / forwarded
# parsers: before this file, an auth handler had to reach into the raw
# header, split off the scheme, and (for Basic) base64-decode by hand — and
# no pure base64 decoder existed on the interpreted path (core Base64 is a
# `ccall`-backed compiled-only codec). `Base64Codec` below is a small pure
# decoder that behaves identically under both engines.
#
# Parsing rules (RFC 7235 §2.1 — `credentials = auth-scheme [ 1*SP … ]`):
#   - the scheme is the token before the first space, matched
#     case-insensitively and exposed downcased ("bearer", "basic", …)
#   - the credentials are everything after that first space, with the
#     surrounding optional whitespace (BWS) trimmed; Bearer token68 and
#     Basic base64 carry no interior spaces, so they survive verbatim
#   - a header with no space is a bare scheme with empty credentials
#     (e.g. "Negotiate"); a blank or nil header parses to nil, so
#     `request.authorization` is nil when the client sent no credentials
#
# NOTE: no `&.` / safe-navigation and no early-return-past-a-block below,
# mirroring request.w / cookie.w — the self-hosted interpreter implements
# neither. `?`-suffixed methods are never chained (that lexes as safe-nav).

+ Credentials
  # Downcased auth-scheme token ("bearer", "basic", "digest", …).
  ro :scheme
  # The raw credential string after the scheme (token68 / base64 / the
  # auth-param list), whitespace-trimmed; "" for a bare scheme.
  ro :credentials

  -> new(@scheme, @credentials)

  # Parse an Authorization / Proxy-Authorization header value into a
  # Credentials, or nil when the header is absent or blank.
  -> .parse(header)
    return nil if header == nil
    trimmed = header.strip
    return nil if trimmed.empty?
    sp = trimmed.index(" ")
    if sp == nil
      self.new(trimmed.downcase, "")
    else
      scheme = trimmed.slice(0, sp).downcase
      rest   = trimmed.slice(sp + 1, trimmed.size - sp - 1).strip
      self.new(scheme, rest)

  # Case-insensitive scheme test — `creds.scheme?("Bearer")`.
  -> scheme?(name)
    @scheme == name.downcase

  -> bearer?
    @scheme == "bearer"

  -> basic?
    @scheme == "basic"

  # The RFC 6750 Bearer token, or nil when this is not a (non-empty) Bearer
  # credential.
  -> token
    return nil unless self.bearer?
    return nil if @credentials.empty?
    @credentials

  # The decoded Basic userid-password string ("userid:password"), or nil
  # when this is not Basic or the base64 is malformed.
  -> decoded
    return nil unless self.basic?
    Base64Codec.decode(@credentials)

  # The Basic userid (RFC 7617). The user-id may not contain a colon, so it
  # is everything before the FIRST colon; a value with no colon is taken to
  # be the whole userid. nil when this is not a valid Basic credential.
  -> username
    dec = self.decoded
    return nil if dec == nil
    colon = dec.index(":")
    if colon == nil
      dec
    else
      dec.slice(0, colon)

  # The Basic password — everything after the first colon (it may itself
  # contain colons). nil when this is not Basic, the base64 is malformed, or
  # the credential carries no colon (userid only).
  -> password
    dec = self.decoded
    return nil if dec == nil
    colon = dec.index(":")
    return nil if colon == nil
    dec.slice(colon + 1, dec.size - colon - 1)

  # Basic credentials as {username:, password:}, or nil when this is not a
  # decodable Basic credential. `password` is nil when the credential had no
  # colon.
  -> basic_credentials
    dec = self.decoded
    return nil if dec == nil
    colon = dec.index(":")
    if colon == nil
      {username: dec, password: nil}
    else
      {username: dec.slice(0, colon), password: dec.slice(colon + 1, dec.size - colon - 1)}


# --- Pure base64 decoder (RFC 4648 §4) ---
#
# A dual-engine standard-alphabet base64 decoder. Core's `Base64.decode` is
# a `ccall`/`raw_load_u8` codec that only exists on the compiled path; this
# one is plain Tungsten (alphabet index + bit-shifts + `Integer#chr`) so the
# interpreted specs and a compiled server decode Basic credentials the same.
#
# Leniency: ASCII whitespace inside the input is skipped, and decoding stops
# at the first "=" pad. An out-of-alphabet byte, or a trailing lone sextet
# (which cannot form a whole octet), makes the input malformed and returns
# nil. Output is built one codepoint at a time, so bytes 0-127 (the common
# ASCII userid:password case) round-trip exactly; a value carrying raw
# non-ASCII octets is outside what a pure per-codepoint reassembly can
# preserve.
+ Base64Codec
  -> .decode(text)
    return nil if text == nil
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    vals = []
    i = 0
    n = text.size
    while i < n
      ch = text.slice(i, 1)
      if ch == "="
        i = n
      else
        if ch == " " || ch == "\r" || ch == "\n" || ch == "\t"
          i += 1
        else
          idx = alphabet.index(ch)
          return nil if idx == nil
          vals.push(idx)
          i += 1
    self.bytes_from_sextets(vals)

  # Reassemble 6-bit groups into octets. Full groups of four sextets yield
  # three bytes; a trailing 2 or 3 sextets yield 1 or 2 bytes; a trailing
  # single sextet is malformed (nil).
  -> .bytes_from_sextets(vals)
    out = ""
    j = 0
    m = vals.size
    while j + 4 <= m
      trip = (vals[j] << 18) | (vals[j + 1] << 12) | (vals[j + 2] << 6) | vals[j + 3]
      out = out + ((trip >> 16) & 255).chr
      out = out + ((trip >> 8) & 255).chr
      out = out + (trip & 255).chr
      j += 4
    rem = m - j
    if rem == 1
      return nil
    if rem == 2
      trip = (vals[j] << 18) | (vals[j + 1] << 12)
      out = out + ((trip >> 16) & 255).chr
    if rem == 3
      trip = (vals[j] << 18) | (vals[j + 1] << 12) | (vals[j + 2] << 6)
      out = out + ((trip >> 16) & 255).chr
      out = out + ((trip >> 8) & 255).chr
    out
