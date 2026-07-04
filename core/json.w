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
    chars = s.chars
    result = parse_value_chars(s, chars, 0)
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

  -> .skip_ws(s, pos)
    skip_ws_chars(s.chars, pos)

  -> .skip_ws_chars(chars, pos)
    while pos < chars.size
      ch = chars[pos]
      if ch != " " && ch != "\t" && ch != "\n" && ch != "\r"
        return pos
      pos += 1
    pos

  -> .parse_value(s, pos)
    parse_value_chars(s, s.chars, pos)

  -> .parse_value_chars(s, chars, pos)
    pos = skip_ws_chars(chars, pos)
    ch = chars[pos]

    if ch == "\""
      return parse_string_chars(chars, pos)
    if ch == "{"
      return parse_object_chars(s, chars, pos)
    if ch == "\["
      return parse_array_chars(s, chars, pos)
    if ch == "t"
      return [true, pos + 4]
    if ch == "f"
      return [false, pos + 5]
    if ch == "n"
      return [nil, pos + 4]

    # Number
    parse_number_chars(s, chars, pos)

  -> .parse_string(s, pos)
    parse_string_chars(s.chars, pos)

  -> .parse_string_chars(chars, pos)
    pos += 1  # skip opening "
    out = StringBuffer(32)
    while pos < chars.size
      ch = chars[pos]
      if ch == "\""
        return [out.to_s, pos + 1]
      if ch == "\\"
        pos += 1
        esc = chars[pos]
        if esc == "n"
          out << "\n"
        elsif esc == "r"
          out << "\r"
        elsif esc == "t"
          out << "\t"
        elsif esc == "\\"
          out << "\\"
        elsif esc == "\""
          out << "\""
        elsif esc == "/"
          out << "/"
        else
          out << esc
      else
        out << ch
      pos += 1
    [out.to_s, pos]

  -> .parse_number(s, pos)
    parse_number_chars(s, s.chars, pos)

  -> .parse_number_chars(s, chars, pos)
    start = pos
    if chars[pos] == "-"
      pos += 1
    while pos < chars.size && chars[pos] >= "0" && chars[pos] <= "9"
      pos += 1
    if pos < chars.size && chars[pos] == "."
      pos += 1
      while pos < chars.size && chars[pos] >= "0" && chars[pos] <= "9"
        pos += 1
      return [s.slice(start, pos - start).to_f, pos]
    [s.slice(start, pos - start).to_i, pos]

  -> .parse_object(s, pos)
    parse_object_chars(s, s.chars, pos)

  -> .parse_object_chars(s, chars, pos)
    pos += 1  # skip {
    result = {}
    pos = skip_ws_chars(chars, pos)
    if chars[pos] == "}"
      return [result, pos + 1]
    while true
      pos = skip_ws_chars(chars, pos)
      key_result = parse_string_chars(chars, pos)
      key = key_result[0]
      pos = key_result[1]
      pos = skip_ws_chars(chars, pos)
      pos += 1  # skip :
      val_result = parse_value_chars(s, chars, pos)
      result[key] = val_result[0]
      pos = val_result[1]
      pos = skip_ws_chars(chars, pos)
      if chars[pos] == "}"
        return [result, pos + 1]
      pos += 1  # skip ,
    [result, pos]

  -> .parse_array(s, pos)
    parse_array_chars(s, s.chars, pos)

  -> .parse_array_chars(s, chars, pos)
    pos += 1  # skip [
    result = []
    pos = skip_ws_chars(chars, pos)
    if chars[pos] == "\]"
      return [result, pos + 1]
    while true
      val_result = parse_value_chars(s, chars, pos)
      result.push(val_result[0])
      pos = val_result[1]
      pos = skip_ws_chars(chars, pos)
      if chars[pos] == "\]"
        return [result, pos + 1]
      pos += 1  # skip ,
    [result, pos]
