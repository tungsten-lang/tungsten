# runtime/b_basics — the first builtins (console, a few Array/String methods) until the
# ports of Blade's b_*.w replace them.

in JS

js_install(->(r) js_install_basics_all(r))

-> js_install_basics_all(r)
  g = r.global
  op = r.object_proto
  ap = js_new_special(op, "Array")
  r.set_intrinsic("Array.prototype", ap)
  r.array_proto = ap
  ["String", "Number"].each ->(k) r.set_intrinsic(k + ".prototype", js_new_special(op, k))
  r.string_proto = r.intrinsic("String.prototype")
  r.number_proto = r.intrinsic("Number.prototype")
  js_install_console(r, g)
  js_install_basics(r, g)
  nil

JS_OUT = []

-> js_console_line(args)
  parts = []
  i = 0
  while i < args.size
    parts.push(js_to_display(args[i]))
    i += 1
  parts.join(" ")

-> js_install_console(r, g)
  c = js_new_object(r.object_proto)
  js_method(c, "log", 0, ->(this, args, nt) js_print(js_console_line(args)))
  js_method(c, "info", 0, ->(this, args, nt) js_print(js_console_line(args)))
  js_method(c, "warn", 0, ->(this, args, nt) js_print(js_console_line(args)))
  js_method(c, "error", 0, ->(this, args, nt) js_print(js_console_line(args)))
  g.define("console", c, ATTR_W + ATTR_C)
  nil

-> js_print(s)
  << s
  nil

-> js_install_basics(r, g)
  ap = r.array_proto
  js_method(ap, "push", 1, ->(this, args, nt) js_array_push(this, args))
  js_method(ap, "pop", 0, ->(this, args, nt) js_array_pop(this))
  js_method(ap, "join", 1, ->(this, args, nt) js_array_join(this, js_arg(args, 0)))
  js_method(r.number_proto, "toString", 1, ->(this, args, nt) js_to_string(this))
  js_method(r.string_proto, "toString", 0, ->(this, args, nt) this)
  js_method(r.string_proto, "charCodeAt", 1, ->(this, args, nt) js_basic_char_code_at(this, js_arg(args, 0)))
  nil

-> js_array_push(this, args)
  js_throw_type("Array.prototype.push called on a non-array") if !js_array?(this)
  i = 0
  while i < args.size
    this.push(args[i])
    i += 1
  this.size.to_f

-> js_array_pop(this)
  return nil if this.size == 0
  v = this.pop
  v == JS_HOLE ? nil : v

-> js_array_join(this, sep)
  s = sep == nil ? "," : js_to_string(sep)
  parts = []
  i = 0
  while i < this.size
    e = this[i]
    parts.push(js_nullish?(e) || e == JS_HOLE ? "" : js_to_string(e))
    i += 1
  parts.join(s)

-> js_basic_char_code_at(s, i)
  str = js_to_string(s)
  n = i == nil ? 0 : js_to_number(i).to_i
  u = js_str_units(str)
  return js_nan() if n < 0 || n >= u.size
  u[n].to_f
