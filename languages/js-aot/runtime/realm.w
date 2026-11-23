# runtime/realm — the realm (intrinsics and the global object), generic property access,
# errors, and the builtins the compiled programs need so far.
#
# The global object keeps its properties in JS:GlobalCell records, one per name, so a
# compiled global read or write is one cell load or store: a site resolves its cell once
# (js_gcell) and keeps it. A cell holding JS_HOLE is an absent property.

in JS

+ Realm
  rw :global, :intrinsics, :jobs, :host, :symbol_registry, :template_cache, :modules, :object_proto, :function_proto, :array_proto, :string_proto, :number_proto, :boolean_proto, :error_proto, :symbol_proto, :fn_shape, :native_shape, :errors

  -> new
    @global = nil
    @intrinsics = {}
    @jobs = []
    @host = nil
    @symbol_registry = {}
    @template_cache = {}
    @modules = {}
    @errors = {}

  -> intrinsic(name)
    v = @intrinsics[name]
    raise "js: missing intrinsic " + name if v == nil
    v

  -> intrinsic?(name)
    @intrinsics.has_key?(name)

  -> set_intrinsic(name, v)
    @intrinsics[name] = v

  # The prototype an error of this kind gets (TypeError, RangeError, ...).
  -> proto_of(kind)
    p = @intrinsics[kind + ".prototype"]
    p == nil ? @error_proto : p

  -> new_object
    js_new_object(@object_proto)

  # A JS array taking ownership of a fresh Tungsten list (no copy).
  -> adopt_array(elems)
    js_mark_array(elems)

  -> new_array(elems = nil)
    js_mark_array(elems == nil ? [] : elems.dup)

  # ToObject for primitives: the Number/String/Boolean/Symbol/BigInt wrappers.
  -> wrap_primitive(v)
    kind = js_number?(v) ? "Number" : (js_string?(v) ? "String" : ((v == true || v == false) ? "Boolean" : (v.is_a?(JS:Symbol) ? "Symbol" : "BigInt")))
    return js_string_object(intrinsic("String.prototype"), v) if js_string?(v)
    o = js_new_special(intrinsic(kind + ".prototype"), kind)
    o.internal = v
    o

  # ---- defining builtins (writable + configurable, not enumerable) ----

  -> native(name, arity, fun, ctor = false)
    f = js_native(name, arity, fun)
    f.set_ctor if ctor
    f

  -> method(obj, name, arity, fun)
    f = native(name.is_a?(JS:Symbol) ? "\[" + name.description + "]" : name, arity, fun)
    jdefine(obj, name, f, BUILTIN_ATTRS)
    f

  -> getter(obj, name, fun, setter = nil)
    g = native("get " + (name.is_a?(JS:Symbol) ? "\[" + name.description + "]" : name), 0, fun)
    st = setter == nil ? nil : native("set " + js_key_display(name).to_s, 1, setter)
    obj.define_accessor(name, g, st, ATTR_C)
    g

  -> constant(obj, name, v)
    jdefine(obj, name, v, 0)

  # A constructor with its prototype object linked both ways; installed on the global.
  -> constructor(name, arity, fun, proto = nil, parent_proto = nil)
    proto = js_new_special(parent_proto == nil ? @object_proto : parent_proto, name) if proto == nil
    c = native(name, arity, fun, true)
    c.define("prototype", proto, 0)
    proto.define("constructor", c, BUILTIN_ATTRS)
    @intrinsics[name] = c
    @intrinsics[name + ".prototype"] = proto
    @global.define(name, c, BUILTIN_ATTRS)
    c

  # OrdinaryCreateFromConstructor: the prototype a constructor call should use.
  -> proto_from(new_target, fallback_name)
    if new_target != nil
      p = jget(new_target, "prototype")
      return p if js_object?(p)
    intrinsic(fallback_name + ".prototype")

  # ---- jobs (microtasks) ----

  -> enqueue_job(job, keep = nil)
    @jobs.push(job)
    nil

  # Run queued jobs until none remain (HTML's "perform a microtask checkpoint").
  # Jobs run in batches (FIFO; what a job enqueues runs after the batch); an exception
  # thrown by one is reported and the rest still run.
  -> run_jobs
    while @jobs.size > 0
      q = @jobs
      @jobs = []
      i = 0
      while i < q.size
        j = q[i]
        q[i] = nil
        i += 1
        begin
          j.call()
        rescue e
          js_report_uncaught(e)
    nil

  # ---- symbols ----

  -> symbol_for(key)
    sy = @symbol_registry[key]
    if sy == nil
      sy = JS:Symbol.new(key)
      @symbol_registry[key] = sy
    sy

BUILTIN_ATTRS = ATTR_W + ATTR_C

# Builtin installers: each builtins file appends ->(realm) at load time; js_new_realm runs
# them in registration order.
JS_INSTALLERS = []

-> js_install(f)
  JS_INSTALLERS.push(f)
  nil

# An object with an internal slot and a class tag (Date, RegExp, Map, the primitive
# wrappers, and the embedder's host objects): JS:Base plus @cls and @internal.
+ Special < JS:Base
  rw :cls, :internal, :s0, :s1, :s2, :s3

  -> new(@shape, @cls)
    @ext = nil
    @internal = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_OBJECT)

SP_IBASE = 4
SP_INLINE = 4

-> js_new_special(proto, cls)
  JS:Special.new(js_root_shape(proto, SP_INLINE, SP_IBASE), cls)

# What the embedder provides: the console, timers, the clock. Blade subclasses it.
+ Host
  -> new
    nil
  -> console(level, text)
    << text
    nil
  -> set_timer(f, ms, repeat)
    0
  -> clear_timer(id)
    nil
  -> now_ms
    Instant.now.unix_ms + ~0.0
  -> perf_now
    clock_ms() + ~0.0

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
# A script's var or function declaration (eval code's are configurable: attrs).
-> js_gdeclare(c, v, is_fn, attrs = ATTR_W + ATTR_E)
  if c.value == JS_HOLE
    js_realm().global.define(c.name, is_fn ? v : nil, attrs)
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
  if o.is_a?(JS:BigIntValue)
    bp = js_realm().intrinsics["BigInt.prototype"]
    return bp == nil ? nil : bp.get(key, o)
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
  p = r.proto_of(kind)
  e = js_new_special(p, "Error")
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

-> js_new_realm(host = nil)
  r = JS:Realm.new
  r.host = host == nil ? JS:Host.new : host
  JS_REALM[0] = r
  op = js_new_special(nil, "Object")
  r.object_proto = op
  r.set_intrinsic("Object.prototype", op)
  # Function.prototype is itself callable: a native that returns undefined
  fp = JS:NativeFunction.new(js_root_shape(op, NF_INLINE, NF_IBASE), ->(this, args, nt) nil, "", 0)
  r.function_proto = fp
  r.set_intrinsic("Function.prototype", fp)
  r.fn_shape = js_root_shape(fp, FN_INLINE, FN_IBASE)
  r.native_shape = js_root_shape(fp, NF_INLINE, NF_IBASE)
  g = JS:GlobalObject.new(js_root_shape(op, 0, 2))
  r.global = g
  i = 0
  while i < JS_INSTALLERS.size
    JS_INSTALLERS[i].call(r)
    i += 1
  r.array_proto = r.intrinsic?("Array.prototype") ? r.intrinsic("Array.prototype") : js_new_special(op, "Array")
  r.string_proto = r.intrinsic?("String.prototype") ? r.intrinsic("String.prototype") : js_new_special(op, "String")
  r.number_proto = r.intrinsic?("Number.prototype") ? r.intrinsic("Number.prototype") : js_new_special(op, "Number")
  r.boolean_proto = r.intrinsic?("Boolean.prototype") ? r.intrinsic("Boolean.prototype") : js_new_special(op, "Boolean")
  r.symbol_proto = r.intrinsic?("Symbol.prototype") ? r.intrinsic("Symbol.prototype") : js_new_special(op, "Symbol")
  r.error_proto = r.intrinsic?("Error.prototype") ? r.intrinsic("Error.prototype") : js_new_special(op, "Error")
  g.define("globalThis", g, BUILTIN_ATTRS)
  g.define("undefined", nil, 0)
  g.define("NaN", js_nan(), 0)
  g.define("Infinity", ~1.0 / ~0.0, 0)
  r

