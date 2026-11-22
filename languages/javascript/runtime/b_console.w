# blade/js/b_console — console and value inspection (Node-like formatting).

-> js_inspect(v, depth, seen)
  return "undefined" if v == nil
  return "null" if v == JS_NULL
  return (v ? "true" : "false") if v == true || v == false
  if v.is_a?(Float)
    return "-0" if v == ~0.0 && ~1.0 / v < ~0.0
    return js_number_to_s(v)
  return (depth == 0 ? v : js_json_quote(v)) if v.is_a?(String)
  return v.to_s if v.is_a?(JsSymbol)
  return v.v.to_s + "n" if v.is_a?(JsBigInt)
  return "\[" + v.class_name + "]" if !v.is_a?(JsObject)
  return "\[Circular]" if seen.include?(v)
  if v.callable?
    n = v.is_a?(JsFunction) ? v.fname.to_s : ""
    cls = v.is_a?(JsFunction) && v.code != nil && v.code.is_class
    return (cls ? "\[class " : "\[Function: ") + (n == "" ? "(anonymous)" : n) + "]"
  c = v.cls
  if (c == "Error") || (c == "DOMException") || js_inherits_error?(v)
    st = v.get("stack", v)
    hd = js_error_to_string(v)
    return hd if !st.is_a?(String) || st.size == 0
    # JSC stacks carry no "Name: message" header; show it like Safari's console does
    return st if st.starts_with?(hd)
    return hd + "\n    " + st.gsub("\n", "\n    ")
  return "\[Promise]" if v.is_a?(JsPromise)
  if c == "RegExp"
    return js_to_string(js_call_method(v, "toString", []))
  if c == "Date"
    return js_to_string(js_call_method(v, "toISOString", [])) if js_date_valid?(v)
    return "Invalid Date"
  return "\[" + c + "]" if depth > 2
  seen.push(v)
  out = ""
  if v.is_a?(JsArray)
    parts = []
    n = v.length
    i = 0
    while i < n && i < 100
      parts.push(js_inspect(v.get_idx(i), depth + 1, seen))
      i += 1
    parts.push("... " + (n - 100).to_s + " more items") if n > 100
    out = parts.size == 0 ? "\[]" : "\[ " + parts.join(", ") + " ]"
  elsif v.is_a?(JsMapObj) && (c == "Map" || c == "Set")
    parts = []
    e = v.data.head
    while e != nil
      if !e.dead
        if c == "Map"
          parts.push(js_inspect(e.key, depth + 1, seen) + " => " + js_inspect(e.value, depth + 1, seen))
        else
          parts.push(js_inspect(e.key, depth + 1, seen))
      e = e.next
    out = c + "(" + v.data.size.to_s + ") {" + (parts.size == 0 ? "" : " " + parts.join(", ") + " ") + "}"
  else
    parts = []
    v.own_keys.each ->(k)
      d = v.get_own_property(k)
      if d != nil && d.enumerable == true
        ks = k.is_a?(JsSymbol) ? "\[" + k.to_s + "]" : (js_ident_name?(k) ? k : js_json_quote(k))
        if d.accessor?
          parts.push(ks + ": \[Getter" + (d.setter != nil ? "/Setter" : "") + "]")
        else
          parts.push(ks + ": " + js_inspect(d.value, depth + 1, seen))
    prefix = ""
    if c != "Object" && c != "global"
      prefix = c + " "
    elsif v.proto == JS_NULL
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
  if first.is_a?(String) && first.index("%") != nil && args.size > 1
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
            sb.append(a.is_a?(String) ? a : js_inspect(a, 1, []))
          elsif c == 100 || c == 105
            n2 = js_to_number(a.is_a?(JsSymbol) ? js_nan() : a)
            sb.append(js_number_to_s(c == 105 || true ? js_math_trunc(n2) : n2))
          elsif c == 102
            sb.append(js_number_to_s(js_to_number(a)))
          elsif c == 99
            sb.append("")
          else
            sb.append(js_inspect(a, 1, []))
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
    parts.push(js_inspect(first, 0, []))
    start = 1
  i = start
  while i < args.size
    parts.push(js_inspect(args[i], 0, []))
    i += 1
  parts.join(" ")

JS_CONSOLE_COUNTS = {}
JS_CONSOLE_TIMERS = {}
JS_CONSOLE_INDENT = [""]

-> js_console_out(level, args)
  h = JS_REALM[0].host
  text = JS_CONSOLE_INDENT[0] + js_console_format(args)
  if h == nil
    << text
  else
    h.console(level, text)
  nil

js_install(->(r) js_install_console(r))

-> js_install_console(r)
  c = JsObject.new(r.object_proto, "Object")
  r.global.define("console", c, BUILTIN_ATTRS)
  ["log", "info", "warn", "error", "debug", "trace", "dir", "dirxml"].each ->(lv)
    js_install_console_level(r, c, lv)
  r.method(c, "assert", 0, ->(this, args, nt) js_console_assert(args))
  r.method(c, "count", 0, ->(this, args, nt) js_console_count(js_arg(args, 0)))
  r.method(c, "countReset", 0, ->(this, args, nt) JS_CONSOLE_COUNTS.delete(js_arg(args, 0) == nil ? "default" : js_to_string(js_arg(args, 0))))
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
  rest = args.size > 1 ? args.slice(1, args.size - 1) : []
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
  r = JS_REALM[0]
  return false if r == nil
  ep = r.proto_of("Error")
  return false if !ep.is_a?(JsObject)
  p = v.proto
  n = 0
  while p.is_a?(JsObject) && n < 50
    return true if p == ep
    p = p.proto
    n += 1
  false
