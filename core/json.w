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
  -> .parse(s_in)
    # Byte-indexed parse: a borrowed u8[] view of the input replaces the old
    # s.chars array (which allocated one String per codepoint of the whole
    # document). Structural bytes are ASCII (< 0x80) and UTF-8 lead/
    # continuation bytes are all >= 0x80, so scanning bytes for the ASCII
    # delimiters never trips on multibyte content; string/number values are
    # sliced out of s (s.slice is byte-indexed, so it stays multibyte-exact).
    # The view is threaded through (not a raw pointer) so it can't be freed
    # underneath the recursion.
    s = s_in ## String
    view = ccall("w_string_bytes_view", s) ## u8[]
    n = view.size ## i64
    pos_box = [0]
    parse_value_b(s, view, n, 0, pos_box)

  -> .encode(value)
    if value == nil
      return "null"
    if value == true
      return "true"
    if value == false
      return "false"
    t = type(value)
    if t == "Int" || t == "Fixnum" || t == "Float"
      return value.to_s
    if t == "String"
      return encode_string(value)
    if t == "Array" || t == "Hash"
      buf = StringBuffer(64)
      encode_into(value, buf)
      return buf.to_s
    encode_string(value.to_s)

  -> .encode_into(value, buf_in)
    buf = buf_in ## StringBuffer
    if value == nil
      buf << "null"
      return nil
    if value == true
      buf << "true"
      return nil
    if value == false
      buf << "false"
      return nil
    t = type(value)
    if t == "Int" || t == "Fixnum" || t == "Float"
      buf << value.to_s
      return nil
    if t == "String"
      encode_string_into(value, buf)
      return nil
    if t == "Array"
      arr = value ## array
      n = arr.size
      buf << "\["
      i = 0
      while i < n
        if i > 0
          buf << ","
        encode_into(arr[i], buf)
        i += 1
      buf << "\]"
      return nil
    if t == "Hash"
      h = value ## hash
      ks = h.keys
      vs = h.values
      n = ks.size
      buf << "{"
      i = 0
      while i < n
        if i > 0
          buf << ","
        k = ks[i]
        if type(k) == "String"
          encode_string_into(k, buf)
        else
          encode_string_into(k.to_s, buf)
        buf << ":"
        encode_into(vs[i], buf)
        i += 1
      buf << "}"
      return nil
    encode_string_into(value.to_s, buf)
    nil

  -> .encode_string(s_in)
    s = s_in ## String
    sv = (s$value & -2) ## i64
    smode = (sv >> 1) & 7
    has_escape = false
    if smode <= 5
      i = 0
      while i < smode
        b = (sv >> (4 + 8 * i)) & 0xFF
        if b == 34 || b == 92 || b == 10 || b == 13 || b == 9
          has_escape = true
          break
        i += 1
      if !has_escape
        return "\"" + s + "\""
      out = StringBuffer(smode + 8)
      encode_string_into(s, out)
      return out.to_s
    n = ccall_nobox("w_string_byte_length", s) ## i64
    ptr = ccall_nobox("w_string_data_ptr", s) ## i64
    i = 0
    while i + 4 <= n
      b0 = raw_load_u8(ptr, i)
      b1 = raw_load_u8(ptr, i + 1)
      b2 = raw_load_u8(ptr, i + 2)
      b3 = raw_load_u8(ptr, i + 3)
      if b0 < 32 || b0 == 34 || b0 == 92 || b1 < 32 || b1 == 34 || b1 == 92 || b2 < 32 || b2 == 34 || b2 == 92 || b3 < 32 || b3 == 34 || b3 == 92
        break
      i += 4
    while i < n
      b = raw_load_u8(ptr, i)
      if b == 34 || b == 92 || b == 10 || b == 13 || b == 9
        has_escape = true
        break
      i += 1
    if !has_escape
      return "\"" + s + "\""
    out = StringBuffer(n + 8)
    encode_string_into(s, out)
    out.to_s

  -> .encode_string_into(s_in, buf_in)
    s = s_in ## String
    buf = buf_in ## StringBuffer
    sv = (s$value & -2) ## i64
    smode = (sv >> 1) & 7
    if smode <= 5
      has_esc = false
      i = 0
      while i < smode
        b = (sv >> (4 + 8 * i)) & 0xFF
        if b == 34 || b == 92 || b == 10 || b == 13 || b == 9
          has_esc = true
          break
        i += 1
      if !has_esc
        buf << "\""
        buf << s
        buf << "\""
        return nil
      buf << "\""
      run_start = 0
      i = 0
      while i < smode
        b = (sv >> (4 + 8 * i)) & 0xFF
        if b == 34 || b == 92 || b == 10 || b == 13 || b == 9
          if i > run_start
            buf << s.slice(run_start, i - run_start)
          if b == 34
            buf << "\\\""
          elsif b == 92
            buf << "\\\\"
          elsif b == 10
            buf << "\\n"
          elsif b == 13
            buf << "\\r"
          else
            buf << "\\t"
          i += 1
          run_start = i
        else
          i += 1
      if run_start < smode
        buf << s.slice(run_start, smode - run_start)
      buf << "\""
      return nil
    n = ccall_nobox("w_string_byte_length", s) ## i64
    ptr = ccall_nobox("w_string_data_ptr", s) ## i64
    buf << "\""
    run_start = 0
    i = 0
    while i + 4 <= n
      b0 = raw_load_u8(ptr, i)
      b1 = raw_load_u8(ptr, i + 1)
      b2 = raw_load_u8(ptr, i + 2)
      b3 = raw_load_u8(ptr, i + 3)
      if b0 >= 32 && b0 != 34 && b0 != 92 && b1 >= 32 && b1 != 34 && b1 != 92 && b2 >= 32 && b2 != 34 && b2 != 92 && b3 >= 32 && b3 != 34 && b3 != 92
        i += 4
      else
        break
    while i < n
      b = raw_load_u8(ptr, i)
      if b == 34 || b == 92 || b == 10 || b == 13 || b == 9
        if i > run_start
          buf << s.slice(run_start, i - run_start)
        if b == 34
          buf << "\\\""
        elsif b == 92
          buf << "\\\\"
        elsif b == 10
          buf << "\\n"
        elsif b == 13
          buf << "\\r"
        else
          buf << "\\t"
        i += 1
        run_start = i
      else
        i += 1
    if run_start == 0
      buf << s
    elsif run_start < n
      buf << s.slice(run_start, n - run_start)
    buf << "\""
    nil

  # -- Internal parsing --

  # Byte helpers. Structural JSON bytes (ASCII): " 34, \ 92, { 123, } 125,
  # [ 91, ] 93, : 58, , 44, - 45, . 46, 0..9 48..57, space 32, tab 9, LF 10,
  # CR 13, t 116, f 102, n 110, / 47, escapes r 114.

  -> .skip_ws_b(view_in, n_in, pos_in)
    view = view_in ## u8[]
    n = n_in ## i64
    pos = pos_in ## i64
    while pos < n
      b = view[pos]
      if b > 32
        return pos
      if b != 32 && b != 9 && b != 10 && b != 13
        return pos
      pos += 1
    pos

  # `view` is a BORROWED u8[] over the input: indexing at or past n reads
  # unrelated heap memory, so every structural read below is bounds-checked
  # and malformed input raises instead of walking off the end. (Truncated
  # documents used to spin in the object/array loops or return garbage,
  # depending on what happened to follow the string in memory.)
  -> .parse_value_b(s_in, view_in, n_in, pos_in, pos_box)
    s = s_in ## String
    view = view_in ## u8[]
    n = n_in ## i64
    pos = pos_in ## i64
    if pos < n && view[pos] <= 32
      pos = skip_ws_b(view, n, pos) ## i64
    if pos >= n
      raise "JSON.parse: unexpected end of input"
    b = view[pos]

    if b == 34
      return parse_string_b(s, view, n, pos, pos_box)
    if b == 123
      return parse_object_b(s, view, n, pos, pos_box)
    if b == 91
      return parse_array_b(s, view, n, pos, pos_box)
    if b == 116
      if pos + 4 > n || view[pos + 1] != 114 || view[pos + 2] != 117 || view[pos + 3] != 101
        raise "JSON.parse: invalid literal at byte " + pos.to_s
      pos_box[0] = pos + 4
      return true
    if b == 102
      if pos + 5 > n || view[pos + 1] != 97 || view[pos + 2] != 108 || view[pos + 3] != 115 || view[pos + 4] != 101
        raise "JSON.parse: invalid literal at byte " + pos.to_s
      pos_box[0] = pos + 5
      return false
    if b == 110
      if pos + 4 > n || view[pos + 1] != 117 || view[pos + 2] != 108 || view[pos + 3] != 108
        raise "JSON.parse: invalid literal at byte " + pos.to_s
      pos_box[0] = pos + 4
      return nil

    # Number
    parse_number_b(s, view, n, pos, pos_box)

  -> .parse_string_b(s_in, view_in, n_in, pos_in, pos_box)
    s = s_in ## String
    view = view_in ## u8[]
    n = n_in ## i64
    pos = pos_in ## i64
    ptr = ccall_nobox("w_u8_live_data_ptr", view) ## i64
    start = pos + 1  # first content byte, past opening "
    # Fast scan for the closing quote; if no backslash escape appears, the
    # value is one byte-range slice of s — no StringBuffer, no per-char work.
    e = start
    while e + 4 <= n
      b0 = raw_load_u8(ptr, e)
      b1 = raw_load_u8(ptr, e + 1)
      b2 = raw_load_u8(ptr, e + 2)
      b3 = raw_load_u8(ptr, e + 3)
      if b0 != 34 && b0 != 92 && b1 != 34 && b1 != 92 && b2 != 34 && b2 != 92 && b3 != 34 && b3 != 92
        e += 4
      else
        break
    while e < n
      b = raw_load_u8(ptr, e)
      if b == 34
        pos_box[0] = e + 1
        return s.slice(start, e - start)
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
        pos_box[0] = p + 1
        return out.to_s
      if b == 92
        if p > run_start
          out << s.slice(run_start, p - run_start)
        p += 1
        if p >= n
          raise "JSON.parse: unterminated string escape"
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
    raise "JSON.parse: unterminated string"

  # Always consumes at least one digit, so a caller's element loop cannot
  # spin on a byte that is not a number at all.
  -> .parse_number_b(s_in, view_in, n_in, pos_in, pos_box)
    s = s_in ## String
    view = view_in ## u8[]
    n = n_in ## i64
    pos = pos_in ## i64
    start = pos
    neg = false
    if pos < n && view[pos] == 45
      neg = true
      pos += 1
    first_digit = pos
    int_val = 0 ## i64
    while pos < n
      d = view[pos]
      break if d < 48 || d > 57
      int_val = int_val * 10 + (d - 48)
      pos += 1
    int_digits = pos - first_digit
    if int_digits == 0
      raise "JSON.parse: unexpected byte at " + start.to_s
    is_float = false
    frac_digits = 0 ## i64
    if pos < n && view[pos] == 46
      is_float = true
      pos += 1
      frac_start = pos
      while pos < n
        d = view[pos]
        break if d < 48 || d > 57
        int_val = int_val * 10 + (d - 48)
        pos += 1
      frac_digits = pos - frac_start
    # Exponent (1e5 / 2.5E-3): without this the digits after `e` were parsed
    # as separate array/object elements, silently corrupting the value.
    has_exp = false
    if pos < n && (view[pos] == 101 || view[pos] == 69)
      is_float = true
      has_exp = true
      pos += 1
      if pos < n && (view[pos] == 43 || view[pos] == 45)
        pos += 1
      exp_digit = pos
      while pos < n && view[pos] >= 48 && view[pos] <= 57
        pos += 1
      if pos == exp_digit
        raise "JSON.parse: malformed exponent at byte " + start.to_s
    pos_box[0] = pos
    if !is_float
      if int_digits <= 14
        return neg ? 0 - int_val : int_val
      return s.slice(start, pos - start).to_i
    if !has_exp && int_digits + frac_digits <= 15 && frac_digits <= 6
      scale = 1.0
      if frac_digits == 1
        scale = 10.0
      elsif frac_digits == 2
        scale = 100.0
      elsif frac_digits == 3
        scale = 1000.0
      elsif frac_digits == 4
        scale = 10000.0
      elsif frac_digits == 5
        scale = 100000.0
      elsif frac_digits == 6
        scale = 1000000.0
      signed_val = neg ? 0 - int_val : int_val
      return (signed_val * 1.0) / scale
    s.slice(start, pos - start).to_f

  -> .parse_object_b(s_in, view_in, n_in, pos_in, pos_box)
    s = s_in ## String
    view = view_in ## u8[]
    n = n_in ## i64
    p0 = pos_in ## i64
    pos = p0 + 1  # skip {
    result = {}
    if pos < n && view[pos] <= 32
      pos = skip_ws_b(view, n, pos) ## i64
    if pos >= n
      raise "JSON.parse: unterminated object"
    if view[pos] == 125
      pos_box[0] = pos + 1
      return result
    pbox = pos_box ## array
    while true
      if pos < n && view[pos] <= 32
        pos = skip_ws_b(view, n, pos) ## i64
      if pos >= n || view[pos] != 34
        raise "JSON.parse: expected a string key in object at byte " + pos.to_s
      key = parse_string_b(s, view, n, pos, pbox)
      pos = pbox[0] ## i64
      if pos < n && view[pos] <= 32
        pos = skip_ws_b(view, n, pos) ## i64
      if pos >= n || view[pos] != 58
        raise "JSON.parse: expected ':' in object at byte " + pos.to_s
      pos += 1  # skip :
      val = parse_value_b(s, view, n, pos, pbox)
      result[key] = val
      pos = pbox[0] ## i64
      if pos < n && view[pos] <= 32
        pos = skip_ws_b(view, n, pos) ## i64
      if pos >= n
        raise "JSON.parse: unterminated object"
      if view[pos] == 125
        pbox[0] = pos + 1
        return result
      if view[pos] != 44
        raise "JSON.parse: expected ',' or '}' in object at byte " + pos.to_s
      pos += 1  # skip ,
    result

  -> .parse_array_b(s_in, view_in, n_in, pos_in, pos_box)
    s = s_in ## String
    view = view_in ## u8[]
    n = n_in ## i64
    p0 = pos_in ## i64
    pos = p0 + 1  # skip [
    result = []
    if pos < n && view[pos] <= 32
      pos = skip_ws_b(view, n, pos) ## i64
    if pos >= n
      raise "JSON.parse: unterminated array"
    if view[pos] == 93
      pos_box[0] = pos + 1
      return result
    pbox = pos_box ## array
    while true
      val = parse_value_b(s, view, n, pos, pbox)
      result.push(val)
      pos = pbox[0] ## i64
      if pos < n && view[pos] <= 32
        pos = skip_ws_b(view, n, pos) ## i64
      if pos >= n
        raise "JSON.parse: unterminated array"
      if view[pos] == 93
        pbox[0] = pos + 1
        return result
      if view[pos] != 44
        raise "JSON.parse: expected ',' or ']' in array at byte " + pos.to_s
      pos += 1  # skip ,
    result
