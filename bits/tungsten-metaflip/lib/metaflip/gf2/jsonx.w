# JSON for the GF(2) toolchain: a reader and two writers that match the
# originals byte for byte.
#
# The lineage manifests, seed lists, scoreboards and campaign logs were written
# by Python's `json.dumps` (indent 1 or 2, default separators, ensure_ascii) and
# the independent verifier prints Ruby's `JSON.pretty_generate`. The Tungsten
# tools must reproduce those files exactly and read the public tables back:
#
#   Jsonx.loads(text)        json.loads          (also JSON Lines: loads_lines)
#   Jsonx.dumps(value, ...)  json.dumps          indent, sort_keys, separators, ensure_ascii
#   Jsonx.pretty_generate(v) Ruby JSON.pretty_generate (verify_tensor.rb)
#
# Values: null -> nil, true/false, integers of any size (Int / BigInt), floats
# -> Float (an IEEE double, printed with Python's shortest repr, see floatx.w),
# strings, arrays, objects -> Hash (insertion ordered; a repeated key keeps the
# position of its first occurrence and the value of its last, as Python does).
#
# Why not core's JSON.parse: on the real inputs it is 5x (the 10.7 MB matmulcatalog
# table) to 13x (FMM scheme files) slower than this reader, it does not decode
# \uXXXX escapes (or \b, \f: they become the letter after the backslash), it
# accepts trailing garbage, leading zeros, invalid escapes and raw control
# characters, rejects NaN / Infinity, and its errors carry no position. This
# reader is strict like Python's: it raises JsonError with Python's message and
# its "line L column C (char N)" suffix. Numbers, key order, repeated keys and
# integers of any size were already right in core and are kept.
#
# Text is UTF-8 bytes throughout. loads does not validate UTF-8 (Python's
# read_text() did, before json saw the text); dumps refuses invalid UTF-8 only
# where it must decode it (ensure_ascii).
#
# There is no garbage collector: Jsonx.release(tree) frees a parsed tree.
use floatx

+ JsonError < Error
  -> new(@message, @offset)

  # Byte offset of the offending character.
  ro :offset

+ Jsonx
  # ---- reading -------------------------------------------------------------

  # Parse one JSON document; anything but whitespace after it is an error.
  -> .loads(text)
    view = ccall("w_string_bytes_view", text) ## u8[]
    n = text.size ## i64
    st = i64[2]
    Jsonx.fail(text, "Unexpected UTF-8 BOM (decode using utf-8-sig)", 0) if n >= 3 && view[0] == 239 && view[1] == 187 && view[2] == 191
    st[0] = Jsonx.skip_ws(view, n, 0)
    value = Jsonx.parse_value(text, view, n, st)
    at = Jsonx.skip_ws(view, n, st[0]) ## i64
    Jsonx.fail(text, "Extra data", at) if at != n
    value

  # Read and parse a file (a missing file raises).
  -> .load(path)
    text = read_file(path)
    raise JsonError.new("cannot read " + path, 0) if text == nil
    Jsonx.loads(text)

  # A JSON Lines log: one value per non-blank line (blank lines skipped, as
  # `if line.strip()` does in collect_chains.py).
  -> .loads_lines(text)
    rows = []
    text.split("\n").each -> (line)
      rows.push(Jsonx.loads(line)) if line.strip.size > 0
    rows

  # Free a tree returned by loads / loads_lines once the caller is done with it.
  # Tungsten has no garbage collector: a parsed 15 MB scheme file leaves about
  # 30 MB behind, so a tool that walks thousands of files must release each tree
  # (or run one process per file). Every node is freed, so nothing taken out of
  # the tree may be used afterwards.
  -> .release(value)
    kind = type(value)
    if kind == "Array"
      value.each -> (item)
        Jsonx.release(item)
      ccall("w_value_free_w", value)
    elsif kind == "Hash"
      value.each -> (key, item)
        Jsonx.release(key)
        Jsonx.release(item)
      ccall("w_value_free_w", value)
    elsif kind == "String" || kind == "BigInt"
      ccall("w_value_free_w", value)
    nil

  -> .skip_ws(view, n, pos) (u8[] i64 i64) i64
    p = pos ## i64
    while p < n
      b = view[p] ## i64
      return p if b != 32 && b != 10 && b != 13 && b != 9
      p += 1
    p

  # The value starting at st[0] (after whitespace); st[0] ends just past it.
  -> .parse_value(text, view, n, st) (String u8[] i64 i64[])
    p = Jsonx.skip_ws(view, n, st[0]) ## i64
    Jsonx.fail(text, "Expecting value", p) if p >= n
    b = view[p] ## i64
    return Jsonx.parse_string(text, view, n, st, p) if b == 34
    return Jsonx.parse_object(text, view, n, st, p) if b == 123
    return Jsonx.parse_array(text, view, n, st, p) if b == 91
    return Jsonx.parse_number(text, view, n, st, p) if b == 45 || (b >= 48 && b <= 57)
    return Jsonx.literal(text, view, n, st, p, "true", true) if b == 116
    return Jsonx.literal(text, view, n, st, p, "false", false) if b == 102
    return Jsonx.literal(text, view, n, st, p, "null", nil) if b == 110
    return Jsonx.literal(text, view, n, st, p, "NaN", Floatx.nan) if b == 78
    return Jsonx.literal(text, view, n, st, p, "Infinity", Floatx.infinity) if b == 73
    Jsonx.fail(text, "Expecting value", p)

  -> .literal(text, view, n, st, pos, word, value) (String u8[] i64 i64[] i64 String)
    size = word.size ## i64
    Jsonx.fail(text, "Expecting value", pos) if pos + size > n || text.slice(pos, size) != word
    st[0] = pos + size
    value

  # Numbers follow the JSON grammar exactly: -?(0|[1-9]\d*)(\.\d+)?([eE][-+]?\d+)?
  # (plus Python's -Infinity). Up to 18 digits are accumulated in a machine word;
  # longer integers go through String#to_i (BigInt); anything with a fraction or
  # exponent is rounded to the nearest double by Floatx.from_decimal.
  -> .parse_number(text, view, n, st, pos) (String u8[] i64 i64[] i64)
    p = pos ## i64
    negative = false
    if view[p] == 45
      negative = true
      p += 1
      if p < n && view[p] == 73
        Jsonx.fail(text, "Expecting value", pos) if p + 8 > n || text.slice(p, 8) != "Infinity"
        st[0] = p + 8
        return Floatx.infinity(true)
    start = p ## i64
    b = 0 ## i64
    b = view[p] if p < n
    Jsonx.fail(text, "Expecting value", pos) if b < 48 || b > 57
    value = 0 ## i64
    if b == 48
      p += 1
    else
      while p < n
        b = view[p]
        break if b < 48 || b > 57
        value = value * 10 + (b - 48)
        p += 1
    whole_end = p ## i64
    is_float = false
    if p + 1 < n && view[p] == 46 && view[p + 1] >= 48 && view[p + 1] <= 57
      is_float = true
      p += 1
      while p < n && view[p] >= 48 && view[p] <= 57
        p += 1
    fraction_end = p ## i64
    exponent = 0
    if p < n && (view[p] == 101 || view[p] == 69)
      q = p + 1 ## i64
      exponent_negative = false
      if q < n && (view[q] == 43 || view[q] == 45)
        exponent_negative = view[q] == 45
        q += 1
      if q < n && view[q] >= 48 && view[q] <= 57
        exponent_start = q ## i64
        while q < n && view[q] >= 48 && view[q] <= 57
          q += 1
        exponent = text.slice(exponent_start, q - exponent_start).to_i
        exponent = 0 - exponent if exponent_negative
        is_float = true
        p = q
    st[0] = p
    if is_float
      digits = text.slice(start, whole_end - start)
      if fraction_end > whole_end
        digits = digits + text.slice(whole_end + 1, fraction_end - whole_end - 1)
      return Floatx.from_decimal(negative, digits.to_i, exponent - (fraction_end > whole_end ? fraction_end - whole_end - 1 : 0))
    return text.slice(pos, whole_end - pos).to_i if whole_end - start > 18
    return 0 - value if negative
    value

  -> .parse_string(text, view, n, st, pos) (String u8[] i64 i64[] i64)
    start = pos + 1 ## i64
    p = start ## i64
    while p < n
      b = view[p] ## i64
      if b == 34
        st[0] = p + 1
        return text.slice(start, p - start)
      return Jsonx.parse_escaped(text, view, n, st, pos) if b == 92
      Jsonx.fail(text, "Invalid control character at", p) if b < 32
      p += 1
    Jsonx.fail(text, "Unterminated string starting at", pos)

  # A string containing escapes: runs of plain bytes are copied whole, escapes
  # are decoded (\uXXXX including surrogate pairs; a lone surrogate is kept as
  # its three-byte encoding so that dumps writes it back unchanged).
  -> .parse_escaped(text, view, n, st, pos) (String u8[] i64 i64[] i64)
    out = StringBuffer(64)
    run = pos + 1 ## i64
    p = run ## i64
    while p < n
      b = view[p] ## i64
      if b == 34
        out << text.slice(run, p - run)
        st[0] = p + 1
        decoded = out.to_s
        ccall("w_value_free_w", out)
        return decoded
      Jsonx.fail(text, "Invalid control character at", p) if b < 32
      if b != 92
        p += 1
      else
        out << text.slice(run, p - run)
        Jsonx.fail(text, "Unterminated string starting at", pos) if p + 1 >= n
        e = view[p + 1] ## i64
        if e == 117
          code = Jsonx.hex4(text, view, n, p + 2) ## i64
          p += 6
          if code >= 55296 && code <= 56319 && p + 5 < n && view[p] == 92 && view[p + 1] == 117
            low = Jsonx.hex4(text, view, n, p + 2) ## i64
            if low >= 56320 && low <= 57343
              code = 65536 + ((code - 55296) << 10) + (low - 56320)
              p += 6
          out << (code == 0 ? Jsonx.nul_char : code.chr)
        else
          out << Jsonx.simple_escape(text, e, p)
          p += 2
        run = p
    Jsonx.fail(text, "Unterminated string starting at", pos)

  # A one-byte string holding NUL (Integer#chr cannot make one).
  -> .nul_char
    bytes = u8[1]
    bytes[0] = 0
    ccall("w_string_from_byte_array", bytes)

  -> .simple_escape(text, e, at)
    return "\"" if e == 34
    return "\\" if e == 92
    return "/" if e == 47
    return 8.chr if e == 98
    return 12.chr if e == 102
    return "\n" if e == 110
    return "\r" if e == 114
    return "\t" if e == 116
    Jsonx.fail(text, "Invalid \\escape", at)

  # Four hex digits at pos as a number.
  -> .hex4(text, view, n, pos) (String u8[] i64 i64) i64
    Jsonx.fail(text, "Invalid \\uXXXX escape", pos - 1) if pos + 4 > n
    value = 0 ## i64
    i = 0 ## i64
    while i < 4
      b = view[pos + i] ## i64
      digit = 0 - 1 ## i64
      digit = b - 48 if b >= 48 && b <= 57
      digit = b - 87 if b >= 97 && b <= 102
      digit = b - 55 if b >= 65 && b <= 70
      Jsonx.fail(text, "Invalid \\uXXXX escape", pos - 1) if digit < 0
      value = value * 16 + digit
      i += 1
    value

  -> .parse_array(text, view, n, st, pos) (String u8[] i64 i64[] i64)
    result = []
    p = Jsonx.skip_ws(view, n, pos + 1) ## i64
    if p < n && view[p] == 93
      st[0] = p + 1
      return result
    st[1] += 1
    Jsonx.fail(text, "maximum recursion depth exceeded while decoding a JSON array", pos) if st[1] > 1000
    while true
      st[0] = p
      result.push(Jsonx.parse_value(text, view, n, st))
      p = Jsonx.skip_ws(view, n, st[0])
      Jsonx.fail(text, "Expecting ',' delimiter", p) if p >= n
      b = view[p] ## i64
      if b == 93
        st[0] = p + 1
        st[1] -= 1
        return result
      Jsonx.fail(text, "Expecting ',' delimiter", p) if b != 44
      comma = p ## i64
      p = Jsonx.skip_ws(view, n, p + 1)
      Jsonx.fail(text, "Illegal trailing comma before end of array", comma) if p < n && view[p] == 93
    result

  -> .parse_object(text, view, n, st, pos) (String u8[] i64 i64[] i64)
    result = {}
    p = Jsonx.skip_ws(view, n, pos + 1) ## i64
    if p < n && view[p] == 125
      st[0] = p + 1
      return result
    st[1] += 1
    Jsonx.fail(text, "maximum recursion depth exceeded while decoding a JSON object", pos) if st[1] > 1000
    while true
      p = Jsonx.skip_ws(view, n, p)
      Jsonx.fail(text, "Expecting property name enclosed in double quotes", p) if p >= n || view[p] != 34
      key = Jsonx.parse_string(text, view, n, st, p)
      p = Jsonx.skip_ws(view, n, st[0])
      Jsonx.fail(text, "Expecting ':' delimiter", p) if p >= n || view[p] != 58
      st[0] = p + 1
      result[key] = Jsonx.parse_value(text, view, n, st)
      p = Jsonx.skip_ws(view, n, st[0])
      Jsonx.fail(text, "Expecting ',' delimiter", p) if p >= n
      b = view[p] ## i64
      if b == 125
        st[0] = p + 1
        st[1] -= 1
        return result
      Jsonx.fail(text, "Expecting ',' delimiter", p) if b != 44
      comma = p ## i64
      p = Jsonx.skip_ws(view, n, p + 1)
      Jsonx.fail(text, "Illegal trailing comma before end of object", comma) if p < n && view[p] == 125
    result

  # JsonDecodeError as Python words it: "Expecting value: line 1 column 1 (char 0)".
  # Lines and columns count characters; `offset` is a byte offset.
  -> .fail(text, what, offset)
    view = ccall("w_string_bytes_view", text) ## u8[]
    line = 1 ## i64
    column = 1 ## i64
    chars = 0 ## i64
    i = 0 ## i64
    while i < offset
      b = view[i] ## i64
      if b == 10
        line += 1
        column = 1
      elsif (b & 192) != 128
        column += 1
      chars += 1 if (b & 192) != 128
      i += 1
    raise JsonError.new(what + ": line " + line.to_s + " column " + column.to_s + " (char " + chars.to_s + ")", offset)

  # ---- writing -------------------------------------------------------------

  # json.dumps(value, indent=, sort_keys=, separators=, ensure_ascii=).
  #   indent      nil (one line), or a number of spaces / an indent string
  #   separators  nil, or [item_separator, key_separator]; the defaults are
  #               [", ", ": "] and, when indent is given, [",", ": "]
  # Arrays and Hashes nest freely; keys are Strings (or Symbols).
  -> .dumps(value, indent: nil, sort_keys: false, separators: nil, ensure_ascii: true)
    writer = JsonWriter.new(indent, sort_keys, separators, ensure_ascii, false)
    writer.emit(value, 0)
    writer.result

  # Ruby's JSON.pretty_generate: two-space indent, `"key": value`, raw UTF-8,
  # empty containers as [] and {}. Floats are refused (see JsonWriter.emit_float).
  -> .pretty_generate(value)
    writer = JsonWriter.new(2, false, nil, false, true)
    writer.emit(value, 0)
    writer.result

  # An object key as text: Strings and Symbols, and the integers and booleans
  # Python also accepts; anything else is refused with Python's message.
  -> .key_text(key)
    kind = type(key)
    return key if kind == "String"
    return key.to_s if kind == "Symbol" || kind == "Int" || kind == "BigInt"
    return (key ? "true" : "false") if kind == "Boolean"
    return "null" if kind == "Nil"
    return Floatx.repr(key) if kind == "Float" || kind == "Decimal"
    raise JsonError.new("keys must be str, int, float, bool or None, not " + kind, 0)

  # Bytewise order of two strings (UTF-8 byte order is code point order, which
  # is how Python sorts keys). Unlike String#<=>, a NUL byte is ordinary data.
  -> .compare_text(a, b) (String String) i64
    left = ccall("w_string_bytes_view", a) ## u8[]
    right = ccall("w_string_bytes_view", b) ## u8[]
    n = a.size ## i64
    m = b.size ## i64
    common = n ## i64
    common = m if m < n
    i = 0 ## i64
    while i < common
      x = left[i] ## i64
      y = right[i] ## i64
      return 0 - 1 if x < y
      return 1 if x > y
      i += 1
    return 0 - 1 if n < m
    return 1 if n > m
    0

  # ---- string escapes (used by JsonWriter) ---------------------------------

  # Python's \-escapes for the ASCII bytes it never writes raw.
  -> .escape_ascii(b) (i64)
    return "\\\"" if b == 34
    return "\\\\" if b == 92
    return "\\n" if b == 10
    return "\\r" if b == 13
    return "\\t" if b == 9
    return "\\b" if b == 8
    return "\\f" if b == 12
    "\\u" + b.to_s(16).lpad(4, "0")

  # Length of the UTF-8 sequence a lead byte starts (0 when it cannot start one).
  -> .utf8_size(lead) (i64) i64
    return 2 if lead >= 194 && lead <= 223
    return 3 if lead >= 224 && lead <= 239
    return 4 if lead >= 240 && lead <= 244
    0

  # The code point of the `size`-byte sequence at i, or -1 when malformed.
  -> .utf8_code(view, n, i, size) (u8[] i64 i64 i64) i64
    return 0 - 1 if size == 0 || i + size > n
    lead = view[i] ## i64
    code = lead & (127 >> size) ## i64
    k = 1 ## i64
    while k < size
      c = view[i + k] ## i64
      return 0 - 1 if (c & 192) != 128
      code = (code << 6) | (c & 63)
      k += 1
    # overlong forms and code points beyond U+10FFFF are not UTF-8
    return 0 - 1 if (size == 3 && code < 2048) || (size == 4 && (code < 65536 || code > 1114111))
    code

# The recursive emitter behind dumps / pretty_generate.
+ JsonWriter
  -> new(indent, @sort_keys, separators, @ascii, @ruby)
    @indent = nil
    if indent != nil
      @indent = type(indent) == "String" ? indent : " " * indent
    @item_separator = @indent == nil ? ", " : ","
    @key_separator = ": "
    if separators != nil
      @item_separator = separators[0]
      @key_separator = separators[1]
    @margins = []
    @hex = []
    byte = 0
    while byte < 256
      @hex.push(byte.to_s(16).lpad(2, "0"))
      byte += 1
    @out = StringBuffer(4096)

  # The text written so far. The buffer is released with it (there is no garbage
  # collector), so a writer is good for one document.
  -> result
    text = @out.to_s
    ccall("w_value_free_w", @out)
    text

  -> emit(value, level)
    case type(value)
    when "String"
      emit_string(value)
    when "Int", "BigInt"
      @out << value.to_s
    when "Array"
      emit_array(value, level)
    when "Hash"
      emit_hash(value, level)
    when "Boolean"
      @out << (value ? "true" : "false")
    when "Nil"
      @out << "null"
    when "Float", "Decimal"
      emit_float(value)
    when "Symbol"
      emit_string(value.to_s)
    else
      raise JsonError.new("Object of type " + type(value) + " is not JSON serializable", 0)
    nil

  # NaN and the infinities are the bare words Python writes. Ruby's json gem
  # prints a float with its own shortest-digit printer, which differs from
  # Float#to_s (and so from anything implementable here) in the last digit
  # for about one float in 150, so pretty_generate refuses floats.
  -> emit_float(value)
    raise JsonError.new("pretty_generate does not support floats", 0) if @ruby
    x = Floatx.of(value)
    word = Floatx.special(x, "Infinity", "NaN")
    @out << (word == nil ? Floatx.repr(x) : word)
    nil

  -> emit_array(items, level)
    count = items.size ## i64
    if count == 0
      @out << "\[\]"
      return nil
    @out << "\["
    i = 0 ## i64
    while i < count
      @out << @item_separator if i > 0
      @out << margin(level + 1) if @indent != nil
      emit(items[i], level + 1)
      i += 1
    @out << margin(level) if @indent != nil
    @out << "\]"
    nil

  -> emit_hash(pairs, level)
    if pairs.size == 0
      @out << "{}"
      return nil
    @out << "{"
    first = true
    if @sort_keys
      keys = pairs.keys.sort -> (a, b)
        Jsonx.compare_text(Jsonx.key_text(a), Jsonx.key_text(b))
      keys.each -> (key)
        emit_pair(key, pairs[key], level, first)
        first = false
    else
      pairs.each -> (key, item)
        emit_pair(key, item, level, first)
        first = false
    @out << margin(level) if @indent != nil
    @out << "}"
    nil

  -> emit_pair(key, item, level, first)
    @out << @item_separator if !first
    @out << margin(level + 1) if @indent != nil
    emit_string(Jsonx.key_text(key))
    @out << @key_separator
    emit(item, level + 1)
    nil

  # "\n" followed by the indent repeated `level` times (cached per level).
  -> margin(level)
    while @margins.size <= level
      @margins.push("\n" + @indent * @margins.size)
    @margins[level]

  # A string literal. Plain text is copied whole; each byte that needs an
  # escape is replaced. (Instance methods cannot carry typed signatures, see
  # PORT-BLOCKERS.md, so the locals are typed instead.) The first scan reads
  # the string in place; only text that needs escapes is copied to a byte view.
  -> emit_string(text)
    n = ccall_nobox("w_string_byte_length", text) ## i64
    ptr = ccall_nobox("w_string_byte_ptr", text) ## i64
    limit = 256 ## i64
    limit = 127 if @ascii
    i = 0 ## i64
    while i < n
      b = raw_load_u8(ptr, i) ## i64
      break if b < 32 || b == 34 || b == 92 || b >= limit
      i += 1
    if i == n
      @out << "\""
      @out << text
      @out << "\""
      return nil
    view = ccall("w_string_bytes_view", text) ## u8[]
    @out << "\""
    run = 0 ## i64
    while i < n
      b = view[i] ## i64
      if b >= 32 && b != 34 && b != 92 && b < limit
        i += 1
      else
        @out << text.slice(run, i - run)
        if b < 128
          @out << Jsonx.escape_ascii(b)
          i += 1
        else
          size = Jsonx.utf8_size(b) ## i64
          code = Jsonx.utf8_code(view, n, i, size) ## i64
          raise JsonError.new("invalid UTF-8 in string at byte " + i.to_s, i) if code < 0
          escape_code(code)
          i += size
        run = i
    @out << text.slice(run, n - run)
    @out << "\""
    nil

  # \uXXXX for a code point (a surrogate pair above U+FFFF; a lone surrogate,
  # which loads keeps as its three-byte encoding, comes out as \udXXX).
  -> escape_code(code)
    if code >= 65536
      offset = code - 65536 ## i64
      escape_unit(55296 + (offset >> 10))
      escape_unit(56320 + (offset & 1023))
    else
      escape_unit(code)
    nil

  -> escape_unit(unit)
    @out << "\\u"
    @out << @hex[unit >> 8]
    @out << @hex[unit & 255]
