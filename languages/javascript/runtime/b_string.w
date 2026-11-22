# blade/js/b_string — String and String.prototype. Strings are UTF-8; positions and
# lengths are in UTF-16 code units, so ASCII strings (the common case) index bytes directly.

-> js_this_str(v, what)
  return v if v.is_a?(String)
  js_throw_type("String.prototype." + what + " called on null or undefined") if js_nullish?(v)
  return v.internal if v.is_a?(JsObject) && v.cls == "String" && v.internal.is_a?(String)
  js_to_string(v)

# UTF-16 offset → byte offset in s.
-> js_unit_to_byte(s, u)
  return u if js_ascii?(s)
  n = s.size
  i = 0
  k = 0
  while i < n && k < u
    b = s.byte_at(i)
    if b < 0x80
      i += 1
      k += 1
    elsif b < 0xE0
      i += 2
      k += 1
    elsif b < 0xF0
      i += 3
      k += 1
    else
      i += 4
      k += 2
  i > n ? n : i

-> js_byte_to_unit(s, bi)
  return bi if js_ascii?(s)
  i = 0
  k = 0
  while i < bi
    b = s.byte_at(i)
    if b < 0x80
      i += 1
      k += 1
    elsif b < 0xE0
      i += 2
      k += 1
    elsif b < 0xF0
      i += 3
      k += 1
    else
      i += 4
      k += 2
  k

-> js_str_index_of(s, sub, from)
  n = js_len(s)
  from = 0 if from < 0
  return (from <= n ? from : n) if sub.size == 0
  return -1 if from >= n
  bi = s.index(sub, js_unit_to_byte(s, from))
  return -1 if bi == nil
  js_byte_to_unit(s, bi)

-> js_str_last_index_of(s, sub, from)
  n = js_len(s)
  from = n if from > n
  from = 0 if from < 0
  sl = js_len(sub)
  k = from
  k = n - sl if k > n - sl
  while k >= 0
    return k if js_substring(s, k, k + sl) == sub
    k -= 1
  -1

-> js_str_slice(s, a, b)
  n = js_len(s)
  ai = js_rel_index(a, n, 0)
  bi = js_rel_index(b, n, n)
  js_substring(s, ai, bi)

-> js_clamp_int(v, lo, hi, dflt)
  return dflt if v == nil
  n = js_to_integer(v)
  return lo if n < lo + ~0.0
  return hi if n > hi + ~0.0
  n.to_i

-> js_str_substring(s, a, b)
  n = js_len(s)
  ai = js_clamp_int(a, 0, n, 0)
  bi = js_clamp_int(b, 0, n, n)
  if ai > bi
    t = ai
    ai = bi
    bi = t
  js_substring(s, ai, bi)

-> js_str_substr(s, a, l)
  n = js_len(s)
  st = js_rel_index(a, n, 0)
  len = l == nil ? n - st : js_clamp_int(l, 0, n - st, n - st)
  return "" if len <= 0
  js_substring(s, st, st + len)

-> js_str_repeat(s, c)
  n = js_to_integer(c)
  raise JsThrow.new(js_range_error("Invalid count value: " + js_number_to_s(n))) if n < ~0.0 || n == INF
  return "" if n == ~0.0 || s.size == 0
  raise JsThrow.new(js_range_error("Invalid string length")) if n * s.size > ~536870888.0
  s * n.to_i

-> js_str_pad(s, maxlen, fill, at_start)
  n = js_to_length(maxlen)
  len = js_len(s)
  return s if n <= len
  f = fill == nil ? " " : js_to_string(fill)
  return s if f.size == 0
  need = n - len
  fl = js_len(f)
  reps = need / fl + 1
  pad = js_substring(f * reps, 0, need)
  at_start ? pad + s : s + pad

-> js_str_case(s, upper)
  if js_ascii?(s)
    return upper ? s.upcase : s.downcase
  upper ? s.unicode_upcase : s.unicode_downcase

-> js_is_trim_cp(cp)
  cp == 9 || cp == 10 || cp == 11 || cp == 12 || cp == 13 || cp == 32 || cp == 0xA0 || cp == 0x1680 || (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 || cp == 0x2029 || cp == 0x202F || cp == 0x205F || cp == 0x3000 || cp == 0xFEFF

-> js_str_trim(s, start, fin)
  a = 0
  b = s.size
  if start
    while a < b
      w = js_utf8_width(s, a)
      cp = js_utf8_decode_at(s, a)
      break if !js_is_trim_cp(cp)
      a += w
  if fin
    while b > a
      j = b - 1
      while j > a && (s.byte_at(j) & 0xC0) == 0x80
        j -= 1
      cp = js_utf8_decode_at(s, j)
      break if !js_is_trim_cp(cp)
      b = j
  return s if a == 0 && b == s.size
  s.slice(a, b - a)

-> js_utf8_width(s, i)
  b = s.byte_at(i)
  b < 0x80 ? 1 : (b < 0xE0 ? 2 : (b < 0xF0 ? 3 : 4))

-> js_utf8_decode_at(s, i)
  b = s.byte_at(i)
  return b if b < 0x80
  n = s.size
  return ((b & 0x1F) << 6) | (s.byte_at(i + 1) & 0x3F) if b < 0xE0 && i + 1 < n
  return ((b & 0x0F) << 12) | ((s.byte_at(i + 1) & 0x3F) << 6) | (s.byte_at(i + 2) & 0x3F) if b < 0xF0 && i + 2 < n
  return ((b & 0x07) << 18) | ((s.byte_at(i + 1) & 0x3F) << 12) | ((s.byte_at(i + 2) & 0x3F) << 6) | (s.byte_at(i + 3) & 0x3F) if i + 3 < n
  0xFFFD

-> js_str_split(this, sep, limit)
  s = js_this_str(this, "split")
  r = JS_REALM[0]
  if !js_nullish?(sep) && !sep.is_a?(String)
    sp = js_get_method(sep, SYM_SPLIT)
    return js_call(sp, sep, [s, limit]) if sp != nil
  lim = limit == nil ? 4294967295 : js_to_uint32(limit)
  sepstr = js_to_string(sep)
  return r.new_array([]) if lim == 0
  return r.new_array([s]) if sep == nil
  out = []
  if sepstr.size == 0
    if js_ascii?(s)
      i = 0
      while i < s.size && out.size < lim
        out.push(s.slice(i, 1))
        i += 1
    else
      js_units(s).each ->(u)
        out.push(js_from_units([u])) if out.size < lim
    return r.new_array(out)
  st = 0
  while out.size < lim
    j = s.index(sepstr, st)
    if j == nil
      out.push(s.slice(st, s.size - st))
      break
    out.push(s.slice(st, j - st))
    st = j + sepstr.size
  r.new_array(out)

# GetSubstitution for string patterns and regex matches (captures: Array, named: JsObject or nil).
-> js_get_substitution(matched, s, pos, captures, named, repl)
  return repl if repl.index("$") == nil
  sb = StringBuffer()
  n = repl.size
  i = 0
  m = captures.size
  while i < n
    c = repl.byte_at(i)
    if c == 36 && i + 1 < n
      d = repl.byte_at(i + 1)
      if d == 36
        sb.append("$")
        i += 2
      elsif d == 38
        sb.append(matched)
        i += 2
      elsif d == 96
        sb.append(js_substring(s, 0, pos))
        i += 2
      elsif d == 39
        e = pos + js_len(matched)
        sb.append(js_substring(s, e, js_len(s)))
        i += 2
      elsif d >= 48 && d <= 57
        num = d - 48
        used = 2
        if i + 2 < n && repl.byte_at(i + 2) >= 48 && repl.byte_at(i + 2) <= 57
          two = num * 10 + (repl.byte_at(i + 2) - 48)
          if two >= 1 && two <= m
            num = two
            used = 3
        if num >= 1 && num <= m
          cv = captures[num - 1]
          sb.append(cv) if cv != nil
          i += used
        else
          sb.append("$")
          i += 1
      elsif d == 60 && named != nil
        e = repl.index(">", i + 2)
        if e == nil
          sb.append("$<")
          i += 2
        else
          gname = repl.slice(i + 2, e - i - 2)
          gv = named.get(gname, named)
          sb.append(js_to_string(gv)) if gv != nil
          i = e + 1
      else
        sb.append("$")
        i += 1
    else
      j = repl.index("$", i)
      j = n if j == nil
      sb.append(repl.slice(i, j - i))
      i = j
  sb.to_s

-> js_str_replace(this, pat, repl, all)
  js_throw_type("String.prototype.replace called on null or undefined") if js_nullish?(this)
  if !js_nullish?(pat) && !pat.is_a?(String)
    if all && js_is_regexp?(pat)
      fl = js_to_string(js_getv(pat, "flags"))
      js_throw_type("replaceAll must be called with a global RegExp") if fl.index("g") == nil
    rp = js_get_method(pat, SYM_REPLACE)
    return js_call(rp, pat, [js_this_str(this, "replace"), repl]) if rp != nil
  s = js_this_str(this, "replace")
  p = js_to_string(pat)
  fun = repl.is_a?(JsObject) && repl.callable? ? repl : nil
  rs = fun == nil ? js_to_string(repl) : nil
  sb = StringBuffer()
  st = 0
  searched = 0
  while true
    j = s.index(p, searched)
    break if j == nil
    sb.append(s.slice(st, j - st))
    upos = js_byte_to_unit(s, j)
    if fun != nil
      sb.append(js_to_string(js_call(fun, nil, [p, upos + ~0.0, s])))
    else
      sb.append(js_get_substitution(p, s, upos, [], nil, rs))
    st = j + p.size
    searched = p.size == 0 ? st + 1 : st
    break if !all
    break if searched > s.size
  sb.append(s.slice(st, s.size - st)) if st <= s.size
  sb.to_s

-> js_str_from_char_code(args)
  if args.size == 1
    c = js_to_uint32(args[0]) & 0xFFFF
    return c.chr if c < 128 && c > 0
  units = args.map(->(a) js_to_uint32(a) & 0xFFFF)
  js_from_units(units)

-> js_str_from_code_point(args)
  sb = StringBuffer()
  args.each ->(a)
    n = js_to_number(a)
    if n != n || n < ~0.0 || n > ~1114111.0 || n != Math.floor(n)
      raise JsThrow.new(js_range_error("Invalid code point " + js_to_string(a)))
    sb.append(js_chr(n.to_i))
  sb.to_s

-> js_str_raw(args)
  cooked = js_to_object(js_arg(args, 0))
  raw = js_to_object(cooked.get("raw", cooked))
  n = js_len_of(raw)
  sb = StringBuffer()
  i = 0
  while i < n
    sb.append(js_to_string(js_el(raw, i)))
    if i + 1 < n && i + 1 < args.size
      sb.append(js_to_string(args[i + 1]))
    i += 1
  sb.to_s

-> js_str_code_point_at(s, idx)
  n = js_len(s)
  i = js_to_integer(idx)
  return nil if i < ~0.0 || i >= n + ~0.0
  k = i.to_i
  if js_ascii?(s)
    return s.byte_at(k) + ~0.0
  u = js_units(s)
  c = u[k]
  if c >= 0xD800 && c <= 0xDBFF && k + 1 < u.size && u[k + 1] >= 0xDC00 && u[k + 1] <= 0xDFFF
    return (0x10000 + ((c - 0xD800) << 10) + (u[k + 1] - 0xDC00)) + ~0.0
  c + ~0.0

-> js_str_char_code_at(s, idx)
  if idx.is_a?(Float) && js_ascii?(s)
    k = idx.to_i
    return s.byte_at(k) + ~0.0 if k + ~0.0 == idx && k >= 0 && k < s.size
  i = idx == nil ? ~0.0 : js_to_integer(idx)
  n = js_len(s)
  return js_nan() if i < ~0.0 || i >= n + ~0.0
  js_char_code_at(s, i.to_i)

-> js_str_char_at(s, idx)
  i = idx == nil ? ~0.0 : js_to_integer(idx)
  n = js_len(s)
  return "" if i < ~0.0 || i >= n + ~0.0
  js_char_at(s, i.to_i)

-> js_str_at(s, idx)
  n = js_len(s)
  i = js_to_integer(idx)
  i = i + n if i < ~0.0
  return nil if i < ~0.0 || i >= n + ~0.0
  js_char_at(s, i.to_i)

-> js_str_starts(this, args, at_end)
  s = js_this_str(this, at_end ? "endsWith" : "startsWith")
  p = js_arg(args, 0)
  js_throw_type("First argument to String.prototype." + (at_end ? "endsWith" : "startsWith") + " must not be a regular expression") if js_is_regexp?(p)
  ps = js_to_string(p)
  n = js_len(s)
  if at_end
    e = js_clamp_int(js_arg(args, 1), 0, n, n)
    st = e - js_len(ps)
    return false if st < 0
    return js_substring(s, st, e) == ps
  st = js_clamp_int(js_arg(args, 1), 0, n, 0)
  return s.slice(st, ps.size) == ps if js_ascii?(s)
  js_substring(s, st, st + js_len(ps)) == ps

-> js_str_includes(this, args)
  s = js_this_str(this, "includes")
  p = js_arg(args, 0)
  js_throw_type("First argument to String.prototype.includes must not be a regular expression") if js_is_regexp?(p)
  js_str_index_of(s, js_to_string(p), js_clamp_int(js_arg(args, 1), 0, js_len(s), 0)) >= 0

-> js_locale_compare(a, b)
  return ~0.0 if a == b
  la = js_str_case(a, false)
  lb = js_str_case(b, false)
  if la != lb
    return la < lb ? ~-1.0 : ~1.0
  # same letters: lowercase sorts first
  a > b ? ~-1.0 : ~1.0

-> js_str_normalize(s, f)
  form = f == nil ? "NFC" : js_to_string(f)
  raise JsThrow.new(js_range_error("The normalization form should be one of NFC, NFD, NFKC, NFKD.")) if !(form == "NFC" || form == "NFD" || form == "NFKC" || form == "NFKD")
  return s if js_ascii?(s)
  if form == "NFC"
    return s.nfc
  if form == "NFD"
    return s.nfd
  if form == "NFKC"
    return s.nfkc
  s.nfkd

-> js_str_well_formed?(s)
  return true if js_ascii?(s)
  u = js_units(s)
  i = 0
  while i < u.size
    c = u[i]
    if c >= 0xD800 && c <= 0xDBFF
      return false if i + 1 >= u.size || u[i + 1] < 0xDC00 || u[i + 1] > 0xDFFF
      i += 2
    elsif c >= 0xDC00 && c <= 0xDFFF
      return false
    else
      i += 1
  true

-> js_str_to_well_formed(s)
  return s if js_str_well_formed?(s)
  u = js_units(s)
  out = []
  i = 0
  while i < u.size
    c = u[i]
    if c >= 0xD800 && c <= 0xDBFF && i + 1 < u.size && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF
      out.push(c)
      out.push(u[i + 1])
      i += 2
    elsif c >= 0xD800 && c <= 0xDFFF
      out.push(0xFFFD)
      i += 1
    else
      out.push(c)
      i += 1
  js_from_units(out)

-> js_string_ctor(args, nt)
  v = args.size == 0 ? "" : args[0]
  s = (nt == nil && v.is_a?(JsSymbol)) ? v.to_s : js_to_string(v)
  return s if nt == nil
  o = JsObject.new(JS_REALM[0].proto_from(nt, "String"), "String")
  o.internal = s
  o.define("length", js_len(s) + ~0.0, 0)
  o

-> js_str_concat(this, args)
  s = js_this_str(this, "concat")
  args.each ->(a) s = s + js_to_string(a)
  s

-> js_str_match(this, rx, all)
  js_throw_type("String.prototype.match called on null or undefined") if js_nullish?(this)
  sym = all ? SYM_MATCH_ALL : SYM_MATCH
  if !js_nullish?(rx)
    if all && js_is_regexp?(rx)
      fl = js_to_string(js_getv(rx, "flags"))
      js_throw_type("String.prototype.matchAll called with a non-global RegExp argument") if fl.index("g") == nil
    m = js_get_method(rx, sym)
    return js_call(m, rx, [js_this_str(this, "match")]) if m != nil
  s = js_this_str(this, "match")
  re = js_regexp_create(rx == nil ? "" : js_to_string(rx), all ? "g" : "")
  js_call(js_getv(re, sym), re, [s])

-> js_str_search(this, rx)
  js_throw_type("String.prototype.search called on null or undefined") if js_nullish?(this)
  if !js_nullish?(rx)
    m = js_get_method(rx, SYM_SEARCH)
    return js_call(m, rx, [js_this_str(this, "search")]) if m != nil
  s = js_this_str(this, "search")
  re = js_regexp_create(rx == nil ? "" : js_to_string(rx), "")
  js_call(js_getv(re, SYM_SEARCH), re, [s])

js_install(->(r) js_install_string(r))

-> js_install_string(r)
  sp = JsObject.new(r.object_proto, "String")
  sp.internal = ""
  sp.define("length", ~0.0, 0)
  sc = r.constructor("String", 1, ->(this, args, nt) js_string_ctor(args, nt), sp)
  r.method(sc, "fromCharCode", 1, ->(this, args, nt) js_str_from_char_code(args))
  r.method(sc, "fromCodePoint", 1, ->(this, args, nt) js_str_from_code_point(args))
  r.method(sc, "raw", 1, ->(this, args, nt) js_str_raw(args))
  r.method(sp, "at", 1, ->(this, args, nt) js_str_at(js_this_str(this, "at"), js_arg(args, 0)))
  r.method(sp, "charAt", 1, ->(this, args, nt) js_str_char_at(js_this_str(this, "charAt"), js_arg(args, 0)))
  r.method(sp, "charCodeAt", 1, ->(this, args, nt) js_str_char_code_at(js_this_str(this, "charCodeAt"), js_arg(args, 0)))
  r.method(sp, "codePointAt", 1, ->(this, args, nt) js_str_code_point_at(js_this_str(this, "codePointAt"), js_arg(args, 0)))
  r.method(sp, "concat", 1, ->(this, args, nt) js_str_concat(this, args))
  r.method(sp, "endsWith", 1, ->(this, args, nt) js_str_starts(this, args, true))
  r.method(sp, "startsWith", 1, ->(this, args, nt) js_str_starts(this, args, false))
  r.method(sp, "includes", 1, ->(this, args, nt) js_str_includes(this, args))
  r.method(sp, "indexOf", 1, ->(this, args, nt) js_str_index_of_v(this, args))
  r.method(sp, "lastIndexOf", 1, ->(this, args, nt) js_str_last_index_of_v(this, args))
  r.method(sp, "localeCompare", 1, ->(this, args, nt) js_locale_compare(js_this_str(this, "localeCompare"), js_to_string(js_arg(args, 0))))
  r.method(sp, "match", 1, ->(this, args, nt) js_str_match(this, js_arg(args, 0), false))
  r.method(sp, "matchAll", 1, ->(this, args, nt) js_str_match(this, js_arg(args, 0), true))
  r.method(sp, "normalize", 0, ->(this, args, nt) js_str_normalize(js_this_str(this, "normalize"), js_arg(args, 0)))
  r.method(sp, "padEnd", 1, ->(this, args, nt) js_str_pad(js_this_str(this, "padEnd"), js_arg(args, 0), js_arg(args, 1), false))
  r.method(sp, "padStart", 1, ->(this, args, nt) js_str_pad(js_this_str(this, "padStart"), js_arg(args, 0), js_arg(args, 1), true))
  r.method(sp, "repeat", 1, ->(this, args, nt) js_str_repeat(js_this_str(this, "repeat"), js_arg(args, 0)))
  r.method(sp, "replace", 2, ->(this, args, nt) js_str_replace(this, js_arg(args, 0), js_arg(args, 1), false))
  r.method(sp, "replaceAll", 2, ->(this, args, nt) js_str_replace(this, js_arg(args, 0), js_arg(args, 1), true))
  r.method(sp, "search", 1, ->(this, args, nt) js_str_search(this, js_arg(args, 0)))
  r.method(sp, "slice", 2, ->(this, args, nt) js_str_slice(js_this_str(this, "slice"), js_arg(args, 0), js_arg(args, 1)))
  r.method(sp, "split", 2, ->(this, args, nt) js_str_split(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(sp, "substring", 2, ->(this, args, nt) js_str_substring(js_this_str(this, "substring"), js_arg(args, 0), js_arg(args, 1)))
  r.method(sp, "substr", 2, ->(this, args, nt) js_str_substr(js_this_str(this, "substr"), js_arg(args, 0), js_arg(args, 1)))
  r.method(sp, "toLowerCase", 0, ->(this, args, nt) js_str_case(js_this_str(this, "toLowerCase"), false))
  r.method(sp, "toUpperCase", 0, ->(this, args, nt) js_str_case(js_this_str(this, "toUpperCase"), true))
  r.method(sp, "toLocaleLowerCase", 0, ->(this, args, nt) js_str_case(js_this_str(this, "toLocaleLowerCase"), false))
  r.method(sp, "toLocaleUpperCase", 0, ->(this, args, nt) js_str_case(js_this_str(this, "toLocaleUpperCase"), true))
  r.method(sp, "toString", 0, ->(this, args, nt) js_this_string_value(this))
  r.method(sp, "valueOf", 0, ->(this, args, nt) js_this_string_value(this))
  r.method(sp, "trim", 0, ->(this, args, nt) js_str_trim(js_this_str(this, "trim"), true, true))
  ts = r.method(sp, "trimStart", 0, ->(this, args, nt) js_str_trim(js_this_str(this, "trimStart"), true, false))
  te = r.method(sp, "trimEnd", 0, ->(this, args, nt) js_str_trim(js_this_str(this, "trimEnd"), false, true))
  sp.define("trimLeft", ts, BUILTIN_ATTRS)
  sp.define("trimRight", te, BUILTIN_ATTRS)
  r.method(sp, "isWellFormed", 0, ->(this, args, nt) js_str_well_formed?(js_this_str(this, "isWellFormed")))
  r.method(sp, "toWellFormed", 0, ->(this, args, nt) js_str_to_well_formed(js_this_str(this, "toWellFormed")))
  it = r.method(sp, SYM_ITERATOR, 0, ->(this, args, nt) js_string_iter(js_this_str(this, "\[Symbol.iterator]")))
  r.set_intrinsic("%StringProto_iterator%", it)
  ["anchor:a:name", "big:big:", "blink:blink:", "bold:b:", "fixed:tt:", "fontcolor:font:color", "fontsize:font:size", "italics:i:", "link:a:href", "small:small:", "strike:strike:", "sub:sub:", "sup:sup:"].each ->(spec)
    js_install_html_method(r, sp, spec)
  nil

-> js_install_html_method(r, sp, spec)
  parts = spec.split(":")
  nm = parts[0]
  tag = parts[1]
  at = parts.size > 2 ? parts[2] : ""
  r.method(sp, nm, at == "" ? 0 : 1, ->(this, args, nt) js_html_wrap(js_this_str(this, nm), tag, at, js_arg(args, 0)))

-> js_html_wrap(s, tag, at, v)
  open = "<" + tag
  open = open + " " + at + "=\"" + js_to_string(v).sub("\"", "&quot;") + "\"" if at != ""
  open + ">" + s + "</" + tag + ">"

-> js_this_string_value(v)
  return v if v.is_a?(String)
  return v.internal if v.is_a?(JsObject) && v.cls == "String" && v.internal.is_a?(String)
  js_throw_type("String.prototype.valueOf requires that 'this' be a String")

-> js_str_last_index_of_v(this, args)
  s = js_this_str(this, "lastIndexOf")
  sub = js_to_string(js_arg(args, 0))
  p = js_to_number(js_arg(args, 1))
  from = p != p ? js_len(s) : (p == INF ? js_len(s) : (p == NEG_INF ? 0 : js_to_integer(p).to_i))
  js_str_last_index_of(s, sub, from) + ~0.0

-> js_str_index_of_v(this, args)
  s = js_this_str(this, "indexOf")
  sub = js_to_string(js_arg(args, 0))
  js_str_index_of(s, sub, js_clamp_int(js_arg(args, 1), 0, js_len(s), 0)) + ~0.0
