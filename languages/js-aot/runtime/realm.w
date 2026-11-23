# runtime/realm — the realm (intrinsics and the global object), generic property access,
# errors, and the builtins the compiled programs need so far.
#
# The global object keeps its properties in JS:GlobalCell records, one per name, so a
# compiled global read or write is one cell load or store: a site resolves its cell once
# (js_gcell) and keeps it. A cell holding JS_HOLE is an absent property.

in JS

+ Realm
  rw :global, :object_proto, :function_proto, :array_proto, :string_proto, :number_proto, :boolean_proto, :error_proto, :symbol_proto, :fn_shape, :native_shape, :errors
  -> new
    @global = nil
    @errors = {}

JS_REALM = [nil]

-> js_realm
  JS_REALM[0]

# @fast holds the value while the cell is a plain writable data property, else the
# W_UNDEF bit pattern (3, never a JS value): a compiled read or write tests one word.
# Otherwise (absent, read-only, accessor) the value is in @store.
+ GlobalCell
  rw :fast, :store, :cattrs, :name
  -> new(@name)
    @fast = JS_NOTPLAIN
    @store = JS_HOLE
    @cattrs = ATTR_DEFAULT

  -> value
    jsr_is_notplain(wvalue_bits(@fast) ## i64) != 0 ? @store : @fast

  -> attrs
    @cattrs

  -> value=(v)
    put(v, @cattrs)

  -> attrs=(a)
    put(value(), a)

  -> put(v, a)
    @cattrs = a
    if v != JS_HOLE && (a & ATTR_W) != 0 && (a & ATTR_ACCESSOR) == 0
      @fast = v
      @store = JS_HOLE
    else
      @fast = JS_NOTPLAIN
      @store = v
    v

JS_NOTPLAIN = wvalue_from_bits(3)

fn jsr_is_notplain(b) (i64) i64
  b == 3 ? 1 : 0

+ GlobalObject < JS:Base
  rw :cells, :order

  -> new(@shape)
    @ext = nil
    @cells = {}
    @order = []
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_EXOTIC)

  -> cell(key)
    c = @cells[key]
    if c == nil
      c = JS:GlobalCell.new(key)
      @cells[key] = c
    c

  -> get_own(key)
    c = @cells[key]
    return JS_HOLE if c == nil
    c.value

  -> has_own?(key)
    c = @cells[key]
    c != nil && c.value != JS_HOLE

  -> get(key, receiver)
    c = @cells[key]
    if c != nil && c.value != JS_HOLE
      return js_accessor_get(c.value, receiver) if (c.attrs & ATTR_ACCESSOR) != 0
      return c.value
    p = @shape.proto
    p == nil ? nil : p.get(key, receiver)

  -> set(key, v, receiver)
    c = cell(key)
    if c.value != JS_HOLE
      return js_accessor_set(c.value, receiver, v) if (c.attrs & ATTR_ACCESSOR) != 0
      return false if (c.attrs & ATTR_W) == 0
      c.value = v
      return true
    c.put(v, ATTR_DEFAULT)
    @order.push(key)
    true

  -> put_own(key, v)
    c = cell(key)
    @order.push(key) if c.value == JS_HOLE
    c.value = v
    v

  -> define(key, v, attrs)
    c = cell(key)
    @order.push(key) if c.value == JS_HOLE
    c.put(v, attrs)
    v

  -> delete_own(key)
    c = @cells[key]
    return true if c == nil || c.value == JS_HOLE
    return false if (c.attrs & ATTR_C) == 0
    c.value = JS_HOLE
    @order = @order.select(->(k) k != key)
    true

  -> own_keys
    @order.select(->(k) @cells[k].value != JS_HOLE)

  -> enumerable?(key)
    c = @cells[key]
    c != nil && (c.attrs & ATTR_E) != 0

# The cell of a global name (created absent).
-> js_gcell(name)
  js_realm().global.cell(name)

# A global read: the cell's value, else the global object's prototype chain, else a
# ReferenceError.
-> js_gget(c)
  cb = wvalue_bits(c) ## i64
  v = jsr_gcell_fast(cb)
  return wvalue_from_bits(v) if v != JSR_SLOW
  js_gget_slow(c)

# A cell's value while it is plain, else JSR_SLOW. (Raw bits are compared only inside
# typed fns: in untyped code an i64 beyond 48 bits would box.)
fn jsr_gcell_fast(cb) (i64) i64
  v = jsr_ivar(cb, 0)
  if v == 3
    return 6
  v


-> js_gget_slow(c)
  g = js_realm().global
  if c.value != JS_HOLE
    return (c.attrs & ATTR_ACCESSOR) != 0 ? js_accessor_get(c.value, g) : c.value
  p = g.shape.proto
  if p != nil
    i = p.shape.slot_of(c.name)
    return p.get(c.name, g) if i >= 0
  js_throw_reference(c.name + " is not defined")

# typeof of a global name: undefined instead of a ReferenceError.
-> js_gtypeof(c)
  v = c.value
  return js_typeof(v) if v != JS_HOLE && (c.attrs & ATTR_ACCESSOR) == 0
  g = js_realm().global
  js_typeof(g.get(c.name, g))

# A global write. strict: an undeclared name is a ReferenceError.
-> js_gset(c, v, strict)
  cb = wvalue_bits(c) ## i64
  if jsr_gcell_fast(cb) != JSR_SLOW
    ccall("w_ivar_set_idx", c, 0, v)
    return v
  js_throw_reference(c.name + " is not defined") if strict && c.value == JS_HOLE
  g = js_realm().global
  ok = g.set(c.name, v, g)
  js_throw_type("Cannot assign to read only property '" + c.name + "' of object") if !ok && strict
  v

# A top-level var or function declaration (configurable: false, as declared bindings are).
-> js_gdeclare(c, v, is_fn)
  if c.value == JS_HOLE
    js_realm().global.define(c.name, is_fn ? v : nil, ATTR_W + ATTR_E)
  elsif is_fn
    c.value = v
  nil

# ---- generic property access (computed keys, primitives) ----

# o[key] for any value o and any key value.
-> js_getv(o, key)
  if js_array?(o)
    return js_array_get_index(o, key) if js_number?(key)
    return js_array_get(o, js_to_property_key(key))
  k = js_to_property_key(key)
  return o.get(k, o) if o.is_a?(JS:Base)
  js_get_prim(o, k)

# A property of a value that is not a JS:Base object.
-> js_get_prim(o, key)
  return js_array_get(o, key) if js_array?(o)
  if js_string?(o)
    if key == "length"
      return js_str_length(o)
    if key.is_a?(String) && js_array_index?(key)
      i = key.to_i
      return js_str_at(o, i) if i < js_str_length(o).to_i
      return nil
    return js_realm().string_proto.get(key, o)
  return js_realm().number_proto.get(key, o) if js_number?(o)
  return js_realm().boolean_proto.get(key, o) if o == true || o == false
  return js_realm().symbol_proto.get(key, o) if o.is_a?(JS:Symbol)
  js_throw_type("Cannot read properties of " + js_to_display(o) + " (reading '" + js_to_display(js_key_display(key)) + "')") if js_nullish?(o)
  nil

-> js_get_value(o, key)
  return o.get(key, o) if o.is_a?(JS:Base)
  js_get_prim(o, key)

# o[key] = v for any value o.
-> js_setv(o, key, v, strict)
  if js_array?(o)
    ok = js_array_set(o, key, v)
    js_throw_type("Cannot assign to read only property") if !ok && strict
    return v
  k = js_to_property_key(key)
  if o.is_a?(JS:Base)
    ok = o.set(k, v, o)
    js_throw_type("Cannot assign to read only property '" + js_to_display(js_key_display(k)) + "' of object") if !ok && strict
    return v
  js_set_prim(o, k, v)
  v

-> js_set_prim(o, key, v)
  return js_array_set(o, key, v) if js_array?(o)
  js_throw_type("Cannot set properties of " + js_to_display(o) + " (setting '" + js_to_display(js_key_display(key)) + "')") if js_nullish?(o)
  nil

# ---- strings (UTF-16 view of UTF-8 strings) ----

-> js_str_length(s)
  return s.size.to_f if s.ascii?
  js_str_units(s).size.to_f

-> js_str_units(s)
  out = []
  s.codepoints.each ->(cp)
    if cp >= 65536
      c = cp - 65536
      out.push(55296 + (c >> 10))
      out.push(56320 + (c & 1023))
    else
      out.push(cp)
  out

-> js_str_at(s, i)
  return s.slice(i, 1) if s.ascii?
  u = js_str_units(s)[i]
  u.chr

# ---- errors ----

-> js_make_error(kind, msg)
  r = js_realm()
  p = r.errors[kind]
  p = r.error_proto if p == nil
  e = js_new_object(p)
  e.define("message", msg, ATTR_W + ATTR_C)
  e.define("stack", kind + ": " + msg, ATTR_W + ATTR_C)
  e

-> js_throw_type(msg)
  js_throw(js_make_error("TypeError", msg))

-> js_throw_range(msg)
  js_throw(js_make_error("RangeError", msg))

-> js_throw_reference(msg)
  js_throw(js_make_error("ReferenceError", msg))

# ---- the realm's intrinsics ----

SYM_TO_PRIMITIVE = JS:Symbol.new("Symbol.toPrimitive")
SYM_ITERATOR = JS:Symbol.new("Symbol.iterator")

-> js_method(o, name, len, fn)
  o.define(name, js_native(name, len, fn), ATTR_W + ATTR_C)
  nil

-> js_arg(args, i)
  i < args.size ? args[i] : nil

-> js_new_realm
  r = JS:Realm.new
  JS_REALM[0] = r
  op = js_new_object(nil)
  r.object_proto = op
  # functions need Function.prototype for their root shape: build it as a native
  fp = JS:NativeFunction.new(js_root_shape(op, NF_INLINE, NF_IBASE), ->(this, args, nt) nil, "", 0)
  r.function_proto = fp
  r.fn_shape = js_root_shape(fp, FN_INLINE, FN_IBASE)
  r.native_shape = js_root_shape(fp, NF_INLINE, NF_IBASE)
  r.array_proto = js_new_object(op)
  r.string_proto = js_new_object(op)
  r.number_proto = js_new_object(op)
  r.boolean_proto = js_new_object(op)
  r.symbol_proto = js_new_object(op)
  ep = js_new_object(op)
  r.error_proto = ep
  ep.define("name", "Error", ATTR_W + ATTR_C)
  ep.define("message", "", ATTR_W + ATTR_C)
  js_method(ep, "toString", 0, ->(this, args, nt) js_error_to_string(this))
  ["TypeError", "RangeError", "ReferenceError", "SyntaxError", "EvalError", "URIError"].each ->(k)
    p = js_new_object(ep)
    p.define("name", k, ATTR_W + ATTR_C)
    r.errors[k] = p
  g = JS:GlobalObject.new(js_root_shape(op, 0, 2))
  r.global = g
  g.define("globalThis", g, ATTR_W + ATTR_C)
  g.define("undefined", nil, 0)
  g.define("NaN", js_nan(), 0)
  g.define("Infinity", ~1.0 / ~0.0, 0)
  js_install_console(r, g)
  js_install_basics(r, g)
  r

-> js_error_to_string(this)
  n = js_get_value(this, "name")
  m = js_get_value(this, "message")
  ns = n == nil ? "Error" : js_to_string(n)
  ms = m == nil ? "" : js_to_string(m)
  return ms if ns == ""
  return ns if ms == ""
  ns + ": " + ms

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
  op = r.object_proto
  js_method(op, "hasOwnProperty", 1, ->(this, args, nt) js_has_own_property(this, js_arg(args, 0)))
  js_method(op, "toString", 0, ->(this, args, nt) js_object_to_string(this))
  js_method(op, "valueOf", 0, ->(this, args, nt) this)
  js_method(r.number_proto, "toString", 1, ->(this, args, nt) js_to_string(this))
  js_method(r.string_proto, "toString", 0, ->(this, args, nt) this)
  js_method(r.string_proto, "charCodeAt", 1, ->(this, args, nt) js_char_code_at(this, js_arg(args, 0)))
  js_method(r.function_proto, "call", 1, ->(this, args, nt) js_call_arr(this, js_arg(args, 0), args.size > 1 ? args.slice(1, args.size - 1).copy : []))
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

-> js_has_own_property(this, key)
  k = js_to_property_key(key)
  return js_array_get(this, k) != nil if js_array?(this)
  return this.has_own?(k) if this.is_a?(JS:Base)
  false

-> js_object_to_string(this)
  return "\[object Undefined]" if this == nil
  return "\[object Null]" if this == JS_NULL
  return "\[object Array]" if js_array?(this)
  return "\[object Function]" if js_callable?(this)
  "\[object Object]"

-> js_char_code_at(s, i)
  str = js_to_string(s)
  n = i == nil ? 0 : js_to_number(i).to_i
  u = js_str_units(str)
  return js_nan() if n < 0 || n >= u.size
  u[n].to_f
