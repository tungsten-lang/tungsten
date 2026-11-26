# runtime/b_json — JSON.parse and JSON.stringify. (Ported from blade/js/b_json.w.)

in JS

+ JsonParser
  -> new(@s)
    @i = 0
    @n = @s.size
    @r = js_realm()

  -> fail(msg)
    js_throw_syntax(msg + " in JSON at position " + @i.to_s)

  -> ws
    while @i < @n
      b = @s.byte_at(@i)
      break if !(b == 32 || b == 9 || b == 10 || b == 13)
      @i += 1
    nil

  -> parse_top
    ws()
    v = j_value()
    ws()
    fail("Unexpected non-whitespace character after JSON") if @i < @n
    v

  -> j_value
    fail("Unexpected end of JSON input") if @i >= @n
    b = @s.byte_at(@i)
    if b == 123
      return j_object()
    if b == 91
      return j_array()
    if b == 34
      return j_string()
    if b == 116
      return lit("true", true)
    if b == 102
      return lit("false", false)
    if b == 110
      return lit("null", JS_NULL)
    if b == 45 || (b >= 48 && b <= 57)
      return j_number()
    fail("Unexpected token '" + @s.slice(@i, 1) + "'")

  -> lit(word, v)
    fail("Unexpected token") if @s.slice(@i, word.size) != word
    @i += word.size
    v

  -> j_number
    st = @i
    @i += 1 if @s.byte_at(@i) == 45
    fail("No number after minus sign") if @i >= @n || @s.byte_at(@i) < 48 || @s.byte_at(@i) > 57
    if @s.byte_at(@i) == 48
      @i += 1
    else
      while @i < @n && @s.byte_at(@i) >= 48 && @s.byte_at(@i) <= 57
        @i += 1
    if @i < @n && @s.byte_at(@i) == 46
      @i += 1
      d = @i
      while @i < @n && @s.byte_at(@i) >= 48 && @s.byte_at(@i) <= 57
        @i += 1
      fail("Unterminated fractional number") if @i == d
    if @i < @n && (@s.byte_at(@i) | 32) == 101
      @i += 1
      @i += 1 if @i < @n && (@s.byte_at(@i) == 43 || @s.byte_at(@i) == 45)
      d = @i
      while @i < @n && @s.byte_at(@i) >= 48 && @s.byte_at(@i) <= 57
        @i += 1
      fail("Exponent part is missing a number") if @i == d
    t = @s.slice(st, @i - st)
    t.to_f

  -> j_string
    @i += 1
    st = @i
    # fast path: no escapes
    while @i < @n
      b = @s.byte_at(@i)
      break if b == 34 || b == 92 || b < 32
      @i += 1
    if @i < @n && @s.byte_at(@i) == 34
      v = @s.slice(st, @i - st)
      @i += 1
      return v
    sb = StringBuffer()
    sb.append(@s.slice(st, @i - st))
    while true
      fail("Unterminated string") if @i >= @n
      b = @s.byte_at(@i)
      if b == 34
        @i += 1
        return sb.to_s
      fail("Bad control character in string literal") if b < 32
      if b == 92
        @i += 1
        fail("Unterminated string") if @i >= @n
        c = @s.byte_at(@i)
        @i += 1
        if c == 110
          sb.append("\n")
        elsif c == 116
          sb.append("\t")
        elsif c == 114
          sb.append("\r")
        elsif c == 98
          sb.append(js_cp_str(8))
        elsif c == 102
          sb.append(js_cp_str(12))
        elsif c == 34 || c == 92 || c == 47
          sb.append(c.chr)
        elsif c == 117
          u = hex4()
          if u >= 0xD800 && u <= 0xDBFF && @i + 1 < @n && @s.byte_at(@i) == 92 && @s.byte_at(@i + 1) == 117
            save = @i
            @i += 2
            lo = hex4()
            if lo >= 0xDC00 && lo <= 0xDFFF
              u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)
            else
              @i = save
          sb.append(js_cp_str(u))
        else
          fail("Bad escaped character")
      else
        j = @i
        while j < @n
          bb = @s.byte_at(j)
          break if bb == 34 || bb == 92 || bb < 32
          j += 1
        sb.append(@s.slice(@i, j - @i))
        @i = j
    nil

  -> hex4
    fail("Bad Unicode escape") if @i + 4 > @n
    v = 0
    k = 0
    while k < 4
      h = js_hexv(@s.byte_at(@i + k))
      fail("Bad Unicode escape") if h < 0
      v = v * 16 + h
      k += 1
    @i += 4
    v

  -> j_array
    @i += 1
    out = []
    ws()
    if @i < @n && @s.byte_at(@i) == 93
      @i += 1
      return @r.adopt_array(out)
    while true
      ws()
      out.push(j_value())
      ws()
      fail("Unterminated array") if @i >= @n
      b = @s.byte_at(@i)
      @i += 1
      break if b == 93
      fail("Expected ',' or ']' after array element") if b != 44
    @r.adopt_array(out)

  -> j_object
    @i += 1
    o = js_new_object(@r.object_proto)
    ws()
    if @i < @n && @s.byte_at(@i) == 125
      @i += 1
      return o
    while true
      ws()
      fail("Expected property name") if @i >= @n || @s.byte_at(@i) != 34
      k = j_string()
      ws()
      fail("Expected ':' after property name") if @i >= @n || @s.byte_at(@i) != 58
      @i += 1
      ws()
      v = j_value()
      if k == "__proto__"
        o.define(k, v, ATTR_ALL)
      else
        o.put_own(k, v)
      ws()
      fail("Unterminated object") if @i >= @n
      b = @s.byte_at(@i)
      @i += 1
      break if b == 125
      fail("Expected ',' or '}' after property value") if b != 44
    o

-> js_json_parse(text, reviver)
  s = js_to_string(text)
  v = JS:JsonParser.new(s).parse_top
  return v if !js_callable?(reviver)
  root = js_realm().new_object
  root.put_own("", v)
  js_json_revive(root, "", reviver)

-> js_json_revive(holder, k, reviver)
  v = jget(holder, k)
  if js_object?(v)
    if js_is_array(v)
      n = js_len_of(v)
      i = 0
      while i < n
        nv = js_json_revive(v, i.to_s, reviver)
        if nv == nil
          jdelete(v, i.to_s)
        else
          jdefine_own_property(v, i.to_s, JS:PropDesc.data(nv, ATTR_ALL))
        i += 1
    else
      ks = js_own_enum_keys(v)
      i = 0
      while i < ks.size
        pk = ks[i]
        nv = js_json_revive(v, pk, reviver)
        if nv == nil
          jdelete(v, pk)
        else
          jdefine_own_property(v, pk, JS:PropDesc.data(nv, ATTR_ALL))
        i += 1
  js_call_arr(reviver, holder, [k, v])

# ---- stringify ----

+ JsonWriter
  rw :sb, :stack, :indent, :gap, :replacer, :allow

  -> new(@replacer, @allow, @gap)
    @sb = StringBuffer()
    @stack = []
    @indent = ""

JS_JSON_ESC = ["\\u0000", "\\u0001", "\\u0002", "\\u0003", "\\u0004", "\\u0005", "\\u0006", "\\u0007", "\\b", "\\t", "\\n", "\\u000b", "\\f", "\\r", "\\u000e", "\\u000f", "\\u0010", "\\u0011", "\\u0012", "\\u0013", "\\u0014", "\\u0015", "\\u0016", "\\u0017", "\\u0018", "\\u0019", "\\u001a", "\\u001b", "\\u001c", "\\u001d", "\\u001e", "\\u001f"]

-> js_json_quote(s)
  sb = StringBuffer()
  sb.append("\"")
  n = s.size
  st = 0
  i = 0
  while i < n
    b = s.byte_at(i)
    if b < 32 || b == 34 || b == 92
      sb.append(s.slice(st, i - st)) if i > st
      if b == 34
        sb.append("\\\"")
      elsif b == 92
        sb.append("\\\\")
      else
        sb.append(JS_JSON_ESC[b])
      st = i + 1
    elsif b == 0xED && i + 2 < n && s.byte_at(i + 1) >= 0xA0
      # a lone surrogate (WTF-8): escape it
      sb.append(s.slice(st, i - st)) if i > st
      cp = ((b & 0x0F) << 12) | ((s.byte_at(i + 1) & 0x3F) << 6) | (s.byte_at(i + 2) & 0x3F)
      sb.append("\\u" + JS_DIGITS36.slice((cp >> 12) & 15, 1) + JS_DIGITS36.slice((cp >> 8) & 15, 1) + JS_DIGITS36.slice((cp >> 4) & 15, 1) + JS_DIGITS36.slice(cp & 15, 1))
      i += 2
      st = i + 1
    i += 1
  sb.append(s.slice(st, n - st)) if n > st
  sb.append("\"")
  sb.to_s

-> js_json_stringify(v, replacer, space)
  r = js_realm()
  fun = nil
  allow = nil
  if js_callable?(replacer)
    fun = replacer
  elsif js_is_array(replacer)
    allow = []
    n = js_len_of(replacer)
    i = 0
    while i < n
      e = js_el(replacer, i)
      item = nil
      if js_string?(e)
        item = e
      elsif js_number?(e)
        item = js_number_to_s(e)
      elsif js_cls(e) == "String" || js_cls(e) == "Number"
        item = js_to_string(e)
      allow.push(item) if item != nil && !allow.include?(item)
      i += 1
  sp = space
  if js_cls(sp) == "Number"
    sp = js_to_number(sp)
  elsif js_cls(sp) == "String"
    sp = js_to_string(sp)
  gap = ""
  if js_number?(sp)
    k = js_to_integer(sp)
    k = ~10.0 if k > ~10.0
    gap = " " * k.to_i if k >= ~1.0
  elsif js_string?(sp)
    gap = js_len(sp) > 10 ? js_substring(sp, 0, 10) : sp
  w = JS:JsonWriter.new(fun, allow, gap)
  wrapper = r.new_object
  wrapper.put_own("", v)
  ok = js_json_ser(w, wrapper, "", v)
  return nil if !ok
  w.sb.to_s

# toJSON and the replacer, then unwrap boxed primitives. JS_HOLE: not serializable (skip).
-> js_json_prep(w, holder, key, v)
  if js_object?(v) || v.is_a?(JS:BigIntValue)
    tj = js_get_value(v, "toJSON")
    v = js_call_arr(tj, v, [key]) if js_callable?(tj)
  v = js_call_arr(w.replacer, holder, [key, v]) if w.replacer != nil
  c = js_cls(v)
  if c != nil
    if c == "Number"
      v = js_to_number(v)
    elsif c == "String"
      v = js_to_string(v)
    elsif c == "Boolean"
      v = v.internal
    elsif v.internal.is_a?(JS:BigIntValue)
      v = v.internal
  return JS_HOLE if v == nil || v.is_a?(JS:Symbol) || js_callable?(v)
  v

-> js_json_ser(w, holder, key, v)
  p = js_json_prep(w, holder, key, v)
  return false if p == JS_HOLE
  js_json_write(w, p)
  true

-> js_json_write(w, v)
  sb = w.sb
  if v == JS_NULL
    sb.append("null")
  elsif v == true
    sb.append("true")
  elsif v == false
    sb.append("false")
  elsif js_string?(v)
    sb.append(js_json_quote(v))
  elsif js_number?(v)
    sb.append(js_finite?(v) ? js_number_to_s(v) : "null")
  elsif v.is_a?(JS:BigIntValue)
    js_throw_type("Do not know how to serialize a BigInt")
  else
    st = w.stack
    i = 0
    while i < st.size
      js_throw_type("Converting circular structure to JSON") if js_ident?(st[i], v)
      i += 1
    w.stack.push(v)
    stepback = w.indent
    w.indent = w.indent + w.gap
    if js_is_array(v)
      js_json_array(w, v)
    else
      js_json_object(w, v)
    w.stack.pop
    w.indent = stepback
  nil

-> js_json_object(w, o)
  keys = w.allow != nil ? w.allow : js_own_enum_keys(o)
  sb = w.sb
  sb.append("{")
  first = true
  i = 0
  while i < keys.size
    k = keys[i]
    p = js_json_prep(w, o, k, jget(o, k))
    if p != JS_HOLE
      sb.append(",") if !first
      sb.append("\n" + w.indent) if w.gap != ""
      sb.append(js_json_quote(k))
      sb.append(w.gap != "" ? ": " : ":")
      js_json_write(w, p)
      first = false
    i += 1
  if !first && w.gap != ""
    sb.append("\n" + w.indent.slice(0, w.indent.size - w.gap.size))
  sb.append("}")
  nil

-> js_json_array(w, a)
  n = js_len_of(a)
  sb = w.sb
  sb.append("\[")
  i = 0
  while i < n
    sb.append(",") if i > 0
    sb.append("\n" + w.indent) if w.gap != ""
    sb.append("null") if !js_json_ser(w, a, i.to_s, js_el(a, i))
    i += 1
  if n > 0 && w.gap != ""
    sb.append("\n" + w.indent.slice(0, w.indent.size - w.gap.size))
  sb.append("]")
  nil

js_install(->(r) js_install_json(r))

-> js_install_json(r)
  j = js_new_object(r.object_proto)
  r.global.define("JSON", j, BUILTIN_ATTRS)
  j.define(SYM_TO_STRING_TAG, "JSON", ATTR_C)
  r.method(j, "parse", 2, ->(this, args, nt) js_json_parse(js_arg(args, 0), js_arg(args, 1)))
  r.method(j, "stringify", 3, ->(this, args, nt) js_json_stringify(js_arg(args, 0), js_arg(args, 1), js_arg(args, 2)))
  nil
