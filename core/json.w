# JSON encoder/decoder — interface and default implementation.
#
# Supports: strings, integers, floats, booleans, nil/null,
#           arrays, and hashes (objects with string keys).
#
#   JSON.parse("{\"name\":\"hello\"}")  => {"name": "hello"}
#   JSON.encode({"name": "hello"})      => "{\"name\":\"hello\"}"
#
# This file defines the JSON contract and ships a default recursive-
# descent implementation that works under both the self-hosted compiler
# and the Ruby interpreter bootstrap path.
#
# Bits can override JSON.parse with a faster implementation. The
# canonical high-throughput implementation lives in the `tungsten-json`
# bit (`bits/tungsten-json/`), which uses a 16-byte SIMD classifier
# (simdjson-class, ~5 GB/s on Apple Silicon). When that bit is loaded
# its `+ JSON` block overrides the methods here transparently, with
# the same value-tree contract.
#
# Contract (any conforming implementation must satisfy):
#   parse(s : String)  -> Hash | Array | String | Number | Boolean | nil
#   encode(v)          -> String

+ JSON
  -> .parse(s)
    # Byte-indexed parse: a borrowed u8[] view of the input replaces the old
    # s.chars array (which allocated one String per codepoint of the whole
    # document). Structural bytes are ASCII (< 0x80) and UTF-8 lead/
    # continuation bytes are all >= 0x80, so scanning bytes for the ASCII
    # delimiters never trips on multibyte content; string/number values are
    # sliced out of s (s.slice is byte-indexed, so it stays multibyte-exact).
    # The view is threaded through (not a raw pointer) so it can't be freed
    # underneath the recursion.
    view = ccall("w_string_bytes_view", s) ## u8[]
    n = view.size
    result = parse_value_b(s, view, n, 0)
    result[0]

  -> .encode(value)
    t = type(value)

    if value == nil
      return "null"

    if t == "Boolean" || value == true || value == false
      if value
        return "true"
      return "false"

    if t == "Integer" || t == "Fixnum"
      return value.to_s

    if t == "Float"
      return value.to_s

    if t == "String"
      return encode_string(value)

    if t == "Array"
      parts = []
      value -> parts.push(JSON.encode(item))
      comma = ","
      return "\[" + parts.join(comma) + "\]"

    if t == "Hash"
      parts = []
      keys = value.keys
      keys -> parts.push(encode_string(key.to_s) + ":" + JSON.encode(value[key]))
      comma = ","
      return "{" + parts.join(comma) + "}"

    # Fallback
    encode_string(value.to_s)

  -> .encode_string(s)
    # Fast path: when no character needs escaping (the common case), wrap the
    # whole string in quotes and skip the per-character chars-array + append
    # loop below. The escape set checked here matches that loop exactly —
    # double-quote, backslash, newline, carriage return, tab — so behavior is
    # unchanged; only the allocation-heavy path is avoided. includes? is the
    # SIMD strstr, far cheaper than materializing s.chars.
    if !s.include?("\"") && !s.include?("\\") && !s.include?("\n") && !s.include?("\r") && !s.include?("\t")
      return "\"" + s + "\""
    out = StringBuffer(s.size + 2)
    out << "\""
    chars = s.chars
    i = 0
    while i < chars.size
      ch = chars[i]
      if ch == "\""
        out << "\\\""
      elsif ch == "\\"
        out << "\\\\"
      elsif ch == "\n"
        out << "\\n"
      elsif ch == "\r"
        out << "\\r"
      elsif ch == "\t"
        out << "\\t"
      else
        out << ch
      i += 1
    out << "\""
    out.to_s

  # -- Internal parsing --

  # Byte helpers. Structural JSON bytes (ASCII): " 34, \ 92, { 123, } 125,
  # [ 91, ] 93, : 58, , 44, - 45, . 46, 0..9 48..57, space 32, tab 9, LF 10,
  # CR 13, t 116, f 102, n 110, / 47, escapes r 114.

  -> .skip_ws_b(view, n, pos)
    while pos < n
      b = view[pos]
      if b != 32 && b != 9 && b != 10 && b != 13
        return pos
      pos += 1
    pos

  -> .parse_value_b(s, view, n, pos)
    pos = skip_ws_b(view, n, pos)
    b = view[pos]

    if b == 34
      return parse_string_b(s, view, n, pos)
    if b == 123
      return parse_object_b(s, view, n, pos)
    if b == 91
      return parse_array_b(s, view, n, pos)
    if b == 116
      return [true, pos + 4]
    if b == 102
      return [false, pos + 5]
    if b == 110
      return [nil, pos + 4]

    # Number
    parse_number_b(s, view, n, pos)

  -> .parse_string_b(s, view, n, pos)
    start = pos + 1  # first content byte, past opening "
    # Fast scan for the closing quote; if no backslash escape appears, the
    # value is one byte-range slice of s — no StringBuffer, no per-char work.
    e = start
    while e < n
      b = view[e]
      if b == 34
        return [s.slice(start, e - start), e + 1]
      if b == 92
        e = n  # escape present — fall to the slow builder below
      else
        e += 1
    # Slow path (has escapes): copy non-escape byte-runs whole, decode escapes.
    out = StringBuffer(32)
    run_start = start
    p = start
    while p < n
      b = view[p]
      if b == 34
        if p > run_start
          out << s.slice(run_start, p - run_start)
        return [out.to_s, p + 1]
      if b == 92
        if p > run_start
          out << s.slice(run_start, p - run_start)
        p += 1
        esc = view[p]
        if esc == 110
          out << "\n"
        elsif esc == 114
          out << "\r"
        elsif esc == 116
          out << "\t"
        elsif esc == 92
          out << "\\"
        elsif esc == 34
          out << "\""
        elsif esc == 47
          out << "/"
        else
          out << s.slice(p, 1)
        p += 1
        run_start = p
      else
        p += 1
    if p > run_start
      out << s.slice(run_start, p - run_start)
    [out.to_s, p]

  -> .parse_number_b(s, view, n, pos)
    start = pos
    if view[pos] == 45
      pos += 1
    while pos < n && view[pos] >= 48 && view[pos] <= 57
      pos += 1
    if pos < n && view[pos] == 46
      pos += 1
      while pos < n && view[pos] >= 48 && view[pos] <= 57
        pos += 1
      return [s.slice(start, pos - start).to_f, pos]
    [s.slice(start, pos - start).to_i, pos]

  -> .parse_object_b(s, view, n, pos)
    pos += 1  # skip {
    result = {}
    pos = skip_ws_b(view, n, pos)
    if view[pos] == 125
      return [result, pos + 1]
    while true
      pos = skip_ws_b(view, n, pos)
      key_result = parse_string_b(s, view, n, pos)
      key = key_result[0]
      pos = key_result[1]
      pos = skip_ws_b(view, n, pos)
      pos += 1  # skip :
      val_result = parse_value_b(s, view, n, pos)
      result[key] = val_result[0]
      pos = val_result[1]
      pos = skip_ws_b(view, n, pos)
      if view[pos] == 125
        return [result, pos + 1]
      pos += 1  # skip ,
    [result, pos]

  -> .parse_array_b(s, view, n, pos)
    pos += 1  # skip [
    result = []
    pos = skip_ws_b(view, n, pos)
    if view[pos] == 93
      return [result, pos + 1]
    while true
      val_result = parse_value_b(s, view, n, pos)
      result.push(val_result[0])
      pos = val_result[1]
      pos = skip_ws_b(view, n, pos)
      if view[pos] == 93
        return [result, pos + 1]
      pos += 1  # skip ,
    [result, pos]
