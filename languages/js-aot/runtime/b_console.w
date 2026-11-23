# runtime/b_console — console and value inspection (Node-like formatting).
# (Ported from blade/js/b_console.w.)

in JS

-> js_console_inspect(v, depth, seen)
  return "undefined" if v == nil
  return "null" if v == JS_NULL
  return (v ? "true" : "false") if v == true || v == false
  if js_number?(v)
    return "-0" if v == ~0.0 && ~1.0 / v < ~0.0
    return js_number_to_s(v)
  return (depth == 0 ? v : js_json_quote(v)) if js_string?(v)
  return v.to_s if v.is_a?(JS:Symbol)
  return v.v.to_s + "n" if v.is_a?(JS:BigIntValue)
  return "\[" + v.class_name + "]" if !js_object?(v)
  i = 0
  while i < seen.size
    return "\[Circular]" if js_ident?(seen[i], v)
    i += 1
  if js_callable?(v)
    nm = jget_own(v, "name")
    n = js_string?(nm) ? nm : ""
    k = jsr_kind(wvalue_bits(v) ## i64) & 15
    cls = k == KIND_FUNCTION && (v.code.flags & CODE_CLASS) != 0
    return (cls ? "\[class " : "\[Function: ") + (n == "" ? "(anonymous)" : n) + "]"
  c = js_array?(v) ? "Array" : js_cls(v)
  c = "Object" if c == nil
  if (c == "Error") || (c == "DOMException") || js_inherits_error?(v)
    st = jget(v, "stack")
    hd = js_error_to_string(v)
    return hd if !js_string?(st) || st.size == 0
    # JSC stacks carry no "Name: message" header; show it like Safari's console does
    return st if st.starts_with?(hd)
    return hd + "\n    " + st.gsub("\n", "\n    ")
  return "\[Promise]" if js_promise?(v)
  if c == "RegExp"
    return js_to_string(js_invoke(v, "toString", []))
  if c == "Date"
    return js_to_string(js_invoke(v, "toISOString", [])) if js_number?(v.internal) && v.internal == v.internal
    return "Invalid Date"
  return "\[" + c + "]" if depth > 2
  seen.push(v)
  out = ""
  if js_array?(v)
    parts = []
    n = v.size
    i = 0
    while i < n && i < 100
      parts.push(js_console_inspect(js_el(v, i), depth + 1, seen))
      i += 1
    parts.push("... " + (n - 100).to_s + " more items") if n > 100
    out = parts.size == 0 ? "\[]" : "\[ " + parts.join(", ") + " ]"
  elsif (c == "Map" || c == "Set") && v.internal.is_a?(JS:MapData)
    parts = []
    e = v.internal.head
    while e != nil
      if !e.dead
        if c == "Map"
          parts.push(js_console_inspect(e.key, depth + 1, seen) + " => " + js_console_inspect(e.value, depth + 1, seen))
        else
          parts.push(js_console_inspect(e.key, depth + 1, seen))
      e = e.next
    out = c + "(" + v.internal.size.to_s + ") {" + (parts.size == 0 ? "" : " " + parts.join(", ") + " ") + "}"
  else
    parts = []
    oks = jown_keys(v)
    i = 0
    while i < oks.size
      k = oks[i]
      d = jget_own_property(v, k)
      if d != nil && d.enumerable == true
        ks = k.is_a?(JS:Symbol) ? "\[" + k.to_s + "]" : (js_ident_name?(k) ? k : js_json_quote(k))
        if d.accessor?
          parts.push(ks + ": \[Getter" + (d.setter != nil ? "/Setter" : "") + "]")
        else
          parts.push(ks + ": " + js_console_inspect(d.value, depth + 1, seen))
      i += 1
    prefix = ""
    if c != "Object" && c != "global"
      prefix = c + " "
    elsif jproto(v) == nil
      prefix = "\[Object: null prototype] "
    out = prefix + (parts.size == 0 ? "{}" : "{ " + parts.join(", ") + " }")
  seen.pop
  out

-> js_ident_name?(k)
  return false if k.size == 0
  i = 0
  while i < k.size
    b = k.byte_at(i)
    ok = (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || b == 95 || b == 36 || (i > 0 && b >= 48 && b <= 57)
    return false if !ok
    i += 1
  true

# console.log("%s is %d", ...) substitutions, then the remaining args inspected.
-> js_console_format(args)
  return "" if args.size == 0
  parts = []
  start = 0
  first = args[0]
  if js_string?(first) && first.index("%") != nil && args.size > 1
    sb = StringBuffer()
    k = 1
    i = 0
    n = first.size
    while i < n
      b = first.byte_at(i)
      if b == 37 && i + 1 < n
        c = first.byte_at(i + 1)
        if (c == 115 || c == 100 || c == 105 || c == 102 || c == 111 || c == 79 || c == 106 || c == 99) && k < args.size
          a = args[k]
          k += 1
          if c == 115
            sb.append(js_string?(a) ? a : js_console_inspect(a, 1, []))
          elsif c == 100 || c == 105
            n2 = js_to_number(a.is_a?(JS:Symbol) ? js_nan() : a)
            sb.append(js_number_to_s(c == 105 || true ? js_math_trunc(n2) : n2))
          elsif c == 102
            sb.append(js_number_to_s(js_to_number(a)))
          elsif c == 99
            sb.append("")
          else
            sb.append(js_console_inspect(a, 1, []))
          i += 2
        elsif c == 37
          sb.append("%")
          i += 2
        else
          sb.append("%")
          i += 1
      else
        sb.append(first.slice(i, 1))
        i += 1
    parts.push(sb.to_s)
    start = k
  else
    parts.push(js_console_inspect(first, 0, []))
    start = 1
  i = start
  while i < args.size
    parts.push(js_console_inspect(args[i], 0, []))
    i += 1
  parts.join(" ")

# TODO(js-aot): per thread once workers run JS.
JS_CONSOLE_COUNTS = {}
JS_CONSOLE_TIMERS = {}
JS_CONSOLE_INDENT = [""]

-> js_console_out(level, args)
  h = js_realm().host
  text = JS_CONSOLE_INDENT[0] + js_console_format(args)
  if h == nil
    << text
  else
    h.console(level, text)
  nil

js_install(->(r) js_install_console(r))

-> js_install_console(r)
  c = js_new_object(r.object_proto)
  r.global.define("console", c, BUILTIN_ATTRS)
  lvs = ["log", "info", "warn", "error", "debug", "trace", "dir", "dirxml"]
  i = 0
  while i < lvs.size
    js_install_console_level(r, c, lvs[i])
    i += 1
  r.method(c, "assert", 0, ->(this, args, nt) js_console_assert(args))
  r.method(c, "count", 0, ->(this, args, nt) js_console_count(js_arg(args, 0)))
  r.method(c, "countReset", 0, ->(this, args, nt) js_console_count_reset(js_arg(args, 0)))
  r.method(c, "group", 0, ->(this, args, nt) js_console_group(args))
  r.method(c, "groupCollapsed", 0, ->(this, args, nt) js_console_group(args))
  r.method(c, "groupEnd", 0, ->(this, args, nt) js_console_group_end())
  r.method(c, "time", 0, ->(this, args, nt) js_console_time(js_arg(args, 0)))
  r.method(c, "timeEnd", 0, ->(this, args, nt) js_console_time_end(js_arg(args, 0), true))
  r.method(c, "timeLog", 0, ->(this, args, nt) js_console_time_end(js_arg(args, 0), false))
  r.method(c, "table", 1, ->(this, args, nt) js_console_out("log", args))
  r.method(c, "clear", 0, ->(this, args, nt) nil)
  r.method(c, "profile", 0, ->(this, args, nt) nil)
  r.method(c, "profileEnd", 0, ->(this, args, nt) nil)
  r.method(c, "timeStamp", 0, ->(this, args, nt) nil)
  nil

-> js_install_console_level(r, c, lv)
  level = lv == "dir" || lv == "dirxml" || lv == "trace" ? "log" : lv
  r.method(c, lv, 0, ->(this, args, nt) js_console_out(level, args))

-> js_console_assert(args)
  return nil if js_truthy(js_arg(args, 0))
  rest = args.size > 1 ? js_arr_copy(args, 1, args.size - 1) : JS_NO_ARGS
  js_console_out("error", ["Assertion failed" + (rest.size > 0 ? ":" : "")] + rest)

-> js_console_count(l)
  k = l == nil ? "default" : js_to_string(l)
  n = JS_CONSOLE_COUNTS.has_key?(k) ? JS_CONSOLE_COUNTS[k] + 1 : 1
  JS_CONSOLE_COUNTS[k] = n
  js_console_out("log", [k + ": " + n.to_s])

-> js_console_group(args)
  js_console_out("log", args) if args.size > 0
  JS_CONSOLE_INDENT[0] = JS_CONSOLE_INDENT[0] + "  "
  nil

-> js_console_group_end
  s = JS_CONSOLE_INDENT[0]
  JS_CONSOLE_INDENT[0] = s.size >= 2 ? s.slice(0, s.size - 2) : ""
  nil

-> js_console_time(l)
  k = l == nil ? "default" : js_to_string(l)
  JS_CONSOLE_TIMERS[k] = clock_ms()
  nil

-> js_console_time_end(l, remove)
  k = l == nil ? "default" : js_to_string(l)
  t = JS_CONSOLE_TIMERS[k]
  return nil if t == nil
  JS_CONSOLE_TIMERS.delete(k) if remove
  js_console_out("log", [k + ": " + (clock_ms() - t).to_s + " ms"])

-> js_inherits_error?(v)
  r = js_realm()
  return false if r == nil
  ep = r.proto_of("Error")
  return false if !js_object?(ep)
  p = jproto(v)
  n = 0
  while p != nil && n < 50
    return true if p == ep
    p = jproto(p)
    n += 1
  false

-> js_console_count_reset(l)
  JS_CONSOLE_COUNTS.delete(l == nil ? "default" : js_to_string(l))
  nil
