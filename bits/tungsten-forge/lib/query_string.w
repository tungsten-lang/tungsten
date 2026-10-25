# Forge::QueryString — application/x-www-form-urlencoded parsing.
#
# Turns a URL query string ("a=1&b=hello+world") or an urlencoded request
# body into a Hash of String keys to String values. This is the class
# Request#query_params (the "?..." portion of the path) and
# Request#form_body (a form POST body) delegate to — before this file
# existed both methods referenced an undefined QueryString and crashed.
#
# Decoding rules (application/x-www-form-urlencoded / WHATWG URL):
#   - pairs are separated by "&"; a pair splits on its FIRST "="
#   - "+" decodes to a space
#   - "%XX" decodes to the byte whose hex value is XX
#   - a pair with no "=" ("flag") yields key => "" (present, empty value)
#   - empty pairs (a trailing "&", or "&&") are skipped
#   - duplicate keys: the LAST value wins — matching Headers' last-wins
#     and Request.parse's duplicate-header rule, so the whole request
#     surface is consistent
#
# Keys and values stay Strings (not Symbols): query names are arbitrary
# client input, and interning attacker-controlled text into symbols is a
# memory-growth foot-gun. This also lines up with Response#cookie and the
# header hash, which are String-keyed.
#
# Percent-decoding is exact across the ASCII range (0x00-0x7F), which is
# every reserved/sub-delim byte a well-formed query string percent-
# escapes. A "%XX" escape for a byte >= 0x80 (a fragment of a multi-byte
# UTF-8 sequence) decodes through Integer#chr, which UTF-8-re-encodes the
# codepoint instead of emitting the raw byte: the runtime exposes no
# raw-byte String constructor that bit code can call under BOTH engines
# (w_string_from_byte is compiled-only and off the interpreter's ccall
# whitelist), so a byte-accurate assembler is not available here. Plain
# text and every ASCII escape are unaffected.
#
# NOTE: no `&.` / safe-navigation and no early-return-past-a-block below,
# mirroring request.w — the self-hosted interpreter implements neither.

+ QueryString
  # Parse a query string / urlencoded body into { "key" => "value" }.
  -> .parse(text)
    result = {}
    if text != nil && !text.empty?
      pairs = text.split("&")
      i = 0
      n = pairs.size
      while i < n
        pair = pairs[i]
        if !pair.empty?
          eq = pair.index("=")
          if eq == nil
            result[self.decode(pair)] = ""
          else
            key = pair.slice(0, eq)
            value = pair.slice(eq + 1, pair.size - eq - 1)
            result[self.decode(key)] = self.decode(value)
        i += 1
    result

  # Percent- and plus-decode a single query component.
  -> .decode(component)
    return "" if component == nil
    n = component.size
    return component if n == 0
    return component if component.index("+") == nil && component.index("%") == nil
    out = ""
    run_start = 0
    i = 0
    while i < n
      b = component.byte_at(i)
      if b == 43
        if i > run_start
          out = out + component.slice(run_start, i - run_start)
        out = out + " "
        i += 1
        run_start = i
      elsif b == 37 && i + 2 < n
        hi = self.nibble_byte(component.byte_at(i + 1))
        lo = self.nibble_byte(component.byte_at(i + 2))
        if hi >= 0 && lo >= 0
          if i > run_start
            out = out + component.slice(run_start, i - run_start)
          out = out + (hi * 16 + lo).chr
          i += 3
          run_start = i
        else
          i += 1
      else
        i += 1
    if run_start < n
      out = out + component.slice(run_start, n - run_start)
    out

  -> .nibble_byte(b)
    return b - 48 if b >= 48 && b <= 57
    return b - 87 if b >= 97 && b <= 102
    return b - 55 if b >= 65 && b <= 70
    0 - 1

  # Hex digit -> value 0..15, or nil if `ch` is not a hex digit.
  -> .nibble(ch)
    "0123456789abcdef".index(ch.downcase)
