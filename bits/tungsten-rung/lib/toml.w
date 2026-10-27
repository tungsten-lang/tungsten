# rung — the TOML subset models.toml uses.
#
# Supported: comments, [table] and [dotted."quoted:key"] headers, key = value
# with basic "strings" (\" \\ \n \t escapes), 'literal strings', multi-line
# """basic""" and '''literal''' strings, integers, booleans, and arrays of
# those (which may span lines). Everything parses into nested Hashes with
# String keys. Errors raise "models.toml line N: ...".

-> rung_toml_parse(text)
  root = {}
  cur = root
  lines = rung_lines(text)
  i = 0
  while i < lines.size
    lineno = i + 1
    raw = lines[i]
    i += 1
    line = rung_toml_strip_comment(raw).strip
    next if line == ""
    if line.starts_with?("\[")
      raise "models.toml line [lineno]: arrays of tables are not supported" if line.starts_with?("\[\[")
      raise "models.toml line [lineno]: unterminated table header" unless line.ends_with?("\]")
      keys = rung_toml_split_key(line.slice(1, line.size - 2).strip, lineno)
      cur = root
      keys.each -> (k)
        if cur[k] == nil
          cur[k] = {}
        cur = cur[k]
      next
    eq = rung_toml_find_eq(line)
    raise "models.toml line [lineno]: expected key = value" if eq == nil
    keys = rung_toml_split_key(line.slice(0, eq).strip, lineno)
    vtext = line.slice(eq + 1, line.size - eq - 1).strip
    # multi-line strings and arrays: keep reading until the value closes
    if vtext.starts_with?("\"\"\"") || vtext.starts_with?("'''")
      delim = vtext.slice(0, 3)
      body = vtext.slice(3, vtext.size - 3)
      while body.index(delim) == nil
        raise "models.toml line [lineno]: unterminated multi-line string" if i >= lines.size
        body = body + "\n" + lines[i]
        i += 1
      vtext = delim + body
    elsif vtext.starts_with?("\[")
      while !rung_toml_balanced?(vtext)
        raise "models.toml line [lineno]: unterminated array" if i >= lines.size
        vtext = vtext + " " + rung_toml_strip_comment(lines[i]).strip
        i += 1
    tbl = cur
    k = 0
    while k < keys.size - 1
      if tbl[keys[k]] == nil
        tbl[keys[k]] = {}
      tbl = tbl[keys[k]]
      k += 1
    tbl[keys[keys.size - 1]] = rung_toml_value(vtext, lineno)
  root

# Drop a # comment that is not inside a string.
-> rung_toml_strip_comment(line)
  q = ""
  i = 0
  while i < line.size
    c = line.slice(i, 1)
    if q == "\""
      if c == "\\"
        i += 1
      elsif c == "\""
        q = ""
    elsif q == "'"
      q = "" if c == "'"
    elsif c == "\"" || c == "'"
      q = c
    elsif c == "#"
      return line.slice(0, i)
    i += 1
  line

-> rung_toml_find_eq(line)
  q = ""
  i = 0
  while i < line.size
    c = line.slice(i, 1)
    if q != ""
      q = "" if c == q
    elsif c == "\"" || c == "'"
      q = c
    elsif c == "="
      return i
    i += 1
  nil

-> rung_toml_balanced?(text)
  depth = 0
  q = ""
  i = 0
  while i < text.size
    c = text.slice(i, 1)
    if q == "\""
      if c == "\\"
        i += 1
      elsif c == "\""
        q = ""
    elsif q == "'"
      q = "" if c == "'"
    elsif c == "\"" || c == "'"
      q = c
    elsif c == "\["
      depth += 1
    elsif c == "\]"
      depth -= 1
    i += 1
  depth <= 0

# a.b."c:d" -> ["a", "b", "c:d"]
-> rung_toml_split_key(text, lineno)
  keys = []
  cur = ""
  q = ""
  i = 0
  while i < text.size
    c = text.slice(i, 1)
    if q != ""
      if c == q
        q = ""
      else
        cur = cur + c
    elsif c == "\"" || c == "'"
      q = c
    elsif c == "."
      keys.push(cur.strip)
      cur = ""
    else
      cur = cur + c
    i += 1
  keys.push(cur.strip)
  keys.each -> (k)
    raise "models.toml line [lineno]: empty key" if k == ""
  keys

-> rung_toml_value(v, lineno)
  if v.starts_with?("\"\"\"")
    body = v.slice(3, v.index("\"\"\"", 3) - 3)
    body = body.slice(1, body.size - 1) if body.starts_with?("\n")
    return rung_toml_unescape(body)
  if v.starts_with?("'''")
    body = v.slice(3, v.index("'''", 3) - 3)
    body = body.slice(1, body.size - 1) if body.starts_with?("\n")
    return body
  if v.starts_with?("\"")
    j = rung_toml_close_basic(v, 1)
    raise "models.toml line [lineno]: unterminated string" if j == nil
    return rung_toml_unescape(v.slice(1, j - 1))
  if v.starts_with?("'")
    j = v.index("'", 1)
    raise "models.toml line [lineno]: unterminated string" if j == nil
    return v.slice(1, j - 1)
  if v.starts_with?("\[")
    return rung_toml_array(v, lineno)
  return true if v == "true"
  return false if v == "false"
  if rung_toml_int?(v)
    return rung_replace(v, "_", "").to_i
  raise "models.toml line [lineno]: unsupported value: [v]"

-> rung_toml_int?(v)
  return false if v == ""
  i = 0
  i = 1 if v.starts_with?("-") || v.starts_with?("+")
  return false if i >= v.size
  while i < v.size
    b = v.byte_at(i)
    return false unless (b >= 48 && b <= 57) || b == 95
    i += 1
  true

# Index of the closing quote of a basic string that opens before `from`.
-> rung_toml_close_basic(v, from)
  i = from
  while i < v.size
    c = v.slice(i, 1)
    if c == "\\"
      i += 2
      next
    return i if c == "\""
    i += 1
  nil

-> rung_toml_unescape(s)
  out = ""
  i = 0
  while i < s.size
    c = s.slice(i, 1)
    if c == "\\" && i + 1 < s.size
      n = s.slice(i + 1, 1)
      if n == "n"
        out = out + "\n"
      elsif n == "t"
        out = out + "\t"
      elsif n == "\""
        out = out + "\""
      elsif n == "\\"
        out = out + "\\"
      else
        out = out + c + n
      i += 2
      next
    out = out + c
    i += 1
  out

# [a, "b", 3] -> elements (no nested arrays).
-> rung_toml_array(v, lineno)
  inner = v.strip
  raise "models.toml line [lineno]: malformed array" unless inner.ends_with?("\]")
  inner = inner.slice(1, inner.size - 2)
  items = []
  cur = ""
  q = ""
  i = 0
  while i < inner.size
    c = inner.slice(i, 1)
    if q == "\""
      cur = cur + c
      if c == "\\"
        cur = cur + inner.slice(i + 1, 1)
        i += 1
      elsif c == "\""
        q = ""
    elsif q == "'"
      cur = cur + c
      q = "" if c == "'"
    elsif c == "\"" || c == "'"
      q = c
      cur = cur + c
    elsif c == ","
      items.push(cur.strip) unless cur.strip == ""
      cur = ""
    else
      cur = cur + c
    i += 1
  items.push(cur.strip) unless cur.strip == ""
  out = []
  items.each -> (it)
    out.push(rung_toml_value(it, lineno))
  out

# ---- emitting ------------------------------------------------------------------------

-> rung_toml_string(s)
  if s.index("'") == nil && s.index("\n") == nil
    return "'" + s + "'"
  t = rung_replace(s, "\\", "\\\\")
  t = rung_replace(t, "\"", "\\\"")
  t = rung_replace(t, "\n", "\\n")
  "\"" + t + "\""

-> rung_toml_scalar(v)
  return (v ? "true" : "false") if v == true || v == false
  if v.is_a?(Array)
    parts = []
    v.each -> (x)
      parts.push(rung_toml_scalar(x))
    return "\[" + parts.join(", ") + "\]"
  if v.is_a?(String)
    return rung_toml_string(v)
  v.to_s

-> rung_toml_key(k)
  ok = true
  i = 0
  while i < k.size
    b = k.byte_at(i)
    ok = false unless (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95 || b == 45
    i += 1
  ok && k != "" ? k : "\"" + k + "\""

# One table's scalar keys, in the order given.
-> rung_toml_table(header, h, order)
  out = "\[" + header + "\]\n"
  order.each -> (k)
    v = h[k]
    if v != nil && !v.is_a?(Hash)
      out = out + rung_toml_key(k) + " = " + rung_toml_scalar(v) + "\n"
  out
