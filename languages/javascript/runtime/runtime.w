# blade/js/runtime — what compiled (tier-0) code calls at run time: frames, property access
# on any value, calls and construction of interpreted functions, generators and async
# functions on goroutines, for-in enumeration, and the error bridge.
#
# A frame is a Tungsten Array: slot 0 is the parent frame. Function frames reserve
# FS_THIS .. FS_HOME; variables start at FS_FIRST. Block frames start at 1.

FS_THIS = 1
FS_FUNC = 2
FS_NT = 3
FS_GEN = 4
FS_HOME = 5
FS_FIRST = 6

# Uninitialized let/const/class binding (temporal dead zone).
+ JsTdz
  -> new
JS_TDZ = JsTdz.new

# Optional-chain short circuit marker (never escapes a :chain).
+ JsShort
  -> new
JS_SHORT = JsShort.new

# Abrupt completions other than throw. Statements return nil for a normal completion.
C_BREAK = 1
C_CONTINUE = 2
C_RETURN = 3

+ JsCompletion
  rw :kind, :label, :value
  -> new(@kind, @label, @value)

# `return v` without allocating: v goes in a per-thread register and one shared completion
# reads it back. Consumers take .value at once; a finally block that runs code while a
# return is pending saves and restores the register (js_run_try_finally and friends).
+ JsRetMark < JsCompletion
  -> value
    JS_RETVAL[0]

JS_RETVAL = JsTlsCell.new(1, nil)
JS_RET_MARK = JsRetMark.new(C_RETURN, nil, nil)

-> js_ret(v)
  JS_RETVAL[0] = v
  JS_RET_MARK

BREAK_PLAIN = JsCompletion.new(C_BREAK, nil, nil)
CONTINUE_PLAIN = JsCompletion.new(C_CONTINUE, nil, nil)

# A generator being closed by return(): unwinds through finally blocks, not catchable.
+ JsGenReturn < Error
  ro :value
  -> new(@value)
  -> message
    "generator return"

# One compiled function: everything the interpreter needs to activate it.
+ JsCode
  rw :name, :length, :nslots, :binder, :body, :strict, :kind, :expr_body, :src, :pos, :fin, :is_class, :derived, :args_slot, :method, :lazy_kind, :self_slot, :url, :builtin, :pending, :native, :unit, :aot_src, :calls, :aot_map, :aot_lex, :aot_hoist, :frame_free

  -> new(@name)
    @length = 0
    @nslots = FS_FIRST
    @binder = nil
    @body = nil
    @strict = false
    @kind = :normal
    @expr_body = false
    @src = nil
    @pos = 0
    @fin = 0
    @is_class = false
    @derived = false
    @args_slot = -1
    @method = false
    @lazy_kind = 0
    @self_slot = -1
    @pending = nil
    @native = nil
    @unit = nil
    @aot_src = nil
    @calls = 0
    @aot_map = nil
    @aot_lex = nil
    @aot_hoist = nil

  -> arrow?
    @kind == :arrow || @kind == :async_arrow

  -> source_text
    return "function " + @name.to_s + "() { \[native code] }" if @src == nil || @builtin
    @src.slice(@pos, @fin - @pos)

# Per-class instance field list, captured when the class is evaluated.
+ JsFieldInit
  rw :env, :size, :items, :privs
  -> new(@env, @size)
    @items = []
    @privs = []

# per thread (blade/js/tls)
JS_DEPTH = JsTlsCell.new(1, 0)
JS_STACK = JsTlsCell.new(1000, nil)
# The source position of the call (or `new`) each frame is executing; [0] is global code.
JS_POS = JsTlsCell.new(1001, -1)
# The running top-level script: [src, url].
JS_TOP = JsTlsCell.new(2, "")
# Interpreted frames allowed. Goroutine stacks are 4 MB (they are touched, not just reserved,
# so a larger hint multiplies the memory of every suspended generator/async function);
# 4 MB holds about 2500 frames.
JS_MAX_DEPTH = [2500]
JS_LAST_ENV = JsTlsCell.new(1, nil)

# ---- frames ----

-> js_up(env, hops)
  e = env
  h = hops
  while h > 0
    e = e[0]
    h -= 1
  e

-> js_tdz_error(name)
  raise JsThrow.new(js_reference_error("Cannot access '" + name + "' before initialization"))

-> js_const_error(name)
  raise JsThrow.new(js_type_error("Assignment to constant variable."))

-> js_unresolved(name)
  raise JsThrow.new(js_reference_error(name + " is not defined"))

# ---- globals (the global object plus the realm's script-scope lexical bindings) ----

+ JsCell
  rw :v, :name, :is_const
  -> new(@name, @v, @is_const)

-> js_gget(name)
  r = JS_REALM[0]
  c = r.glex[name]
  if c != nil
    v = c.v
    js_tdz_error(name) if v.is_a?(JsTdz)
    return v
  g = r.global
  v = g.props[name]
  return v if v != nil
  js_unresolved(name) if !g.has_property?(name)
  g.get(name, g)

-> js_gtypeof(name)
  r = JS_REALM[0]
  c = r.glex[name]
  return js_typeof_v(c.v) if c != nil
  g = r.global
  return "undefined" if !g.has_property?(name)
  js_typeof_v(g.get(name, g))

-> js_gset(name, v, strict)
  r = JS_REALM[0]
  c = r.glex[name]
  if c != nil
    js_tdz_error(name) if c.v.is_a?(JsTdz)
    js_const_error(name) if c.is_const
    c.v = v
    return v
  g = r.global
  if strict && !g.has_property?(name)
    js_unresolved(name)
  ok = g.set(name, v, g)
  js_throw_type("Cannot assign to read only property '" + name + "' of object") if !ok && strict
  v

# ---- property access on any value ----

-> js_getv(o, k)
  return o.get(k, o) if o.is_a?(JsObject)
  return JS_SHORT if o == JS_SHORT
  if o.is_a?(String)
    return js_len(o) + ~0.0 if k == "length"
    if k.is_a?(String) && k.size > 0 && k.byte_at(0) >= 48 && k.byte_at(0) <= 57 && js_array_index?(k)
      i = k.to_i
      return js_char_at(o, i) if i < js_len(o)
    return JS_REALM[0].intrinsic("String.prototype").get(k, o)
  if js_nullish?(o)
    raise JsThrow.new(js_type_error("Cannot read properties of " + js_to_display(o) + " (reading '" + js_key_display(k).to_s + "')"))
  js_proto_for_primitive(o).get(k, o)

-> js_proto_for_primitive(o)
  r = JS_REALM[0]
  return r.intrinsic("Number.prototype") if o.is_a?(Float)
  return r.intrinsic("String.prototype") if o.is_a?(String)
  return r.intrinsic("Boolean.prototype") if o == true || o == false
  return r.intrinsic("Symbol.prototype") if o.is_a?(JsSymbol)
  return r.intrinsic("BigInt.prototype") if o.is_a?(JsBigInt)
  r.object_proto

-> js_char_at(s, i)
  if js_ascii?(s)
    return s.slice(i, 1)
  u = js_units(s)
  return "" if i < 0 || i >= u.size
  js_from_units([u[i]])

# o[k] for a computed key.
-> js_getidx(o, k)
  if k.is_a?(Float)
    if o.is_a?(JsArray)
      if k >= ~0.0 && k < (o.elems.size + ~0.0)
        i = k.to_i
        if i + ~0.0 == k
          v = o.elems[i]
          return v if v != JS_HOLE
    elsif o.is_a?(JsObject)
      if k >= ~0.0 && k < ~4294967295.0
        i = k.to_i
        return o.get_idx(i) if i + ~0.0 == k
    elsif o.is_a?(String)
      if k >= ~0.0
        i = k.to_i
        if i + ~0.0 == k
          return nil if i >= js_len(o)
          return js_char_at(o, i)
  if o.is_a?(JsObject)
    pk = js_to_property_key(k)
    v = o.get(pk, o)
    js_trace_miss(o, pk) if v == nil && JS_TRACE_MISS[0]
    return v
  if js_nullish?(o)
    raise JsThrow.new(js_type_error("Cannot read properties of " + js_to_display(o) + " (reading '" + js_key_display(js_to_property_key(k)).to_s + "')"))
  js_getv(o, js_to_property_key(k))

# o.k = v; strict: a failed assignment throws.
# Debugging aid (BLADE_JS_WATCH=name): report every assignment to a property with that name.
JS_WATCH = [Env.get("BLADE_JS_WATCH", "")]

-> js_watch_hit(k, v)
  ccall("w_eputs", "\[js watch] " + k.to_s + " = " + js_inspect(v, 0, []).slice(0, 80))
  ls = js_stack_lines().split("\n")
  i = 0
  while i < ls.size && i < 4
    ccall("w_eputs", "      " + ls[i].slice(0, 160))
    i += 1
  nil

-> js_setv(o, k, v, strict)
  js_watch_hit(k, v) if JS_WATCH[0].size > 0 && k == JS_WATCH[0]
  if o.is_a?(JsObject)
    ok = o.set(k, v, o)
    js_set_failed(o, k) if !ok && strict
    return v
  if js_nullish?(o)
    raise JsThrow.new(js_type_error("Cannot set properties of " + js_to_display(o) + " (setting '" + js_key_display(k).to_s + "')"))
  # primitives: setters on the prototype chain run with the primitive as this; nothing is stored
  p = js_proto_for_primitive(o)
  ok = p.set(k, v, o)
  js_set_failed(o, k) if strict && !ok
  v

-> js_set_failed(o, k)
  js_throw_type("Cannot assign to read only property '" + js_key_display(k).to_s + "' of " + (o.is_a?(JsObject) ? "object" : js_typeof(o)))

-> js_setidx(o, k, v, strict)
  if k.is_a?(Float) && o.is_a?(JsObject) && k >= ~0.0 && k < ~4294967295.0
    i = k.to_i
    if i + ~0.0 == k
      if o.is_a?(JsArray)
        el = o.elems
        if i < el.size && el[i] != JS_HOLE
          el[i] = v
          return v
        if i == el.size && o.extensible && o.slen == nil && !o.len_ro && o.proto == JS_REALM[0].array_proto && !JS_REALM[0].array_proto_indexed
          el.push(v)
          return v
      ok = o.set_idx(i, v)
      js_set_failed(o, i.to_s) if !ok && strict
      return v
  js_setv(o, js_to_property_key(k), v, strict)

-> js_delete(o, k, strict)
  ob = js_to_object(o)
  ok = ob.delete_own(k)
  js_throw_type("Cannot delete property '" + js_key_display(k).to_s + "' of " + js_to_display(o)) if !ok && strict
  ok

# CreateDataPropertyOrThrow
-> js_create_data(o, k, v)
  if o.is_a?(JsArray) || !o.has_own?(k)
    if o.is_a?(JsArray) || o.extensible
      ok = o.define_own_property(k, JsPropDesc.data(v, ATTR_ALL))
      js_throw_type("Cannot add property " + js_key_display(k).to_s + ", object is not extensible") if !ok
      return v
  ok = o.define_own_property(k, JsPropDesc.data(v, ATTR_ALL))
  js_throw_type("Cannot redefine property: " + js_key_display(k).to_s) if !ok
  v

# ---- calls ----

-> js_call_named(f, this, args, what)
  return JS_SHORT if f == JS_SHORT
  if !f.is_a?(JsFunction) && !(f.is_a?(JsObject) && f.callable?)
    raise JsThrow.new(js_type_error(what + " is not a function"))
  js_call(f, this, args)

-> js_construct_named(f, args, what)
  if !(f.is_a?(JsObject) && js_is_constructor?(f))
    raise JsThrow.new(js_type_error(what + " is not a constructor"))
  js_construct(f, args, nil)

-> js_is_constructor?(f)
  return f.ctor if f.is_a?(JsFunction)
  return f.is_constructor? if f.proxy?
  false

# [[Call]] of an interpreted function.
-> js_call_code(f, this, args)
  code = f.code
  if code.is_class
    js_throw_type("Class constructor " + code.name.to_s + " cannot be invoked without 'new'")
  k = code.kind
  if k == :normal || k == :arrow || k == :method
    return js_exec(f, code, this, args, nil)
  if k == :generator
    return js_gen_create(f, code, this, args)
  if k == :async || k == :async_arrow
    return js_async_call(f, code, this, args)
  if k == :async_gen
    return js_async_gen_create(f, code, this, args)
  js_exec(f, code, this, args, nil)

# Allocate and fill a function frame, bind parameters; returns the frame.
-> js_activation(f, code, this, args, nt)
  js_code_ready(code) if code.pending != nil
  env = Array.new(code.nslots, nil)
  env[0] = f.scope
  if !code.arrow?
    if !code.strict && (this == nil || this == JS_NULL)
      this = JS_REALM[0].global
    elsif !code.strict && !this.is_a?(JsObject) && !this.is_a?(JsTdz)
      this = js_to_object(this)
    env[FS_THIS] = this
    env[FS_FUNC] = f
    env[FS_NT] = nt
    env[FS_HOME] = f.home
  code.binder.call(env, args)
  env

-> js_exec(f, code, this, args, nt)
  d = JS_DEPTH[0] + 1
  if d > JS_MAX_DEPTH[0]
    raise JsThrow.new(js_range_error("Maximum call stack size exceeded"))
  JS_DEPTH[0] = d
  if d < 1000
    JS_STACK[d] = code
    JS_POS[d] = -1
  js_watchdog() if ((JS_TICKS[0] += 1) & 4095) == 0
  if code.unit != nil
    if code.native != nil && nt == nil
      JS_DEPTH[0] = d - 1
      return js_native_exec(f, code, this, args)
    code.calls += 1
    js_aot_note_hot(code) if code.calls == JS_AOT_HOT[0]
  env = js_activation(f, code, this, args, nt)
  r = nil
  begin
    if JS_FN_PROFILE[0]
      t0 = clock_ms()
      r = code.body.call(env)
      js_fn_profile_add(code, clock_ms() - t0)
    else
      r = code.body.call(env)
  rescue e
    # a throw unwinds this frame too (catchers anywhere see the right depth)
    JS_DEPTH[0] = d - 1
    raise e
  JS_DEPTH[0] = d - 1
  if code.frame_free
    # nothing can reference this frame any more (no closures, eval, mapped arguments,
    # coroutine or derived-constructor use): release it now
    v = code.expr_body ? r : ((r != nil && r.kind == C_RETURN) ? r.value : nil)
    ccall("w_value_free_w", env)
    JS_LAST_ENV[0] = nil
    return v
  JS_LAST_ENV[0] = env
  return r if code.expr_body
  return r.value if r != nil && r.kind == C_RETURN
  nil

# [[Construct]] of an interpreted function.
-> js_construct_code(f, args, nt)
  code = f.code
  js_throw_type(code.name.to_s + " is not a constructor") if !f.ctor
  if f.cls_kind == :derived
    if code.kind == :default_derived
      parent = f.get_prototype_of
      js_throw_type("Super constructor " + js_to_display(parent) + " of anonymous class is not a constructor") if !(parent.is_a?(JsObject) && js_is_constructor?(parent))
      obj = js_construct(parent, args, nt)
      js_init_fields(f, obj)
      return obj
    r = js_exec(f, code, JS_TDZ, args, nt)
    env = JS_LAST_ENV[0]
    return r if r.is_a?(JsObject)
    js_throw_type("Derived constructors may only return object or undefined") if r != nil
    th = env[FS_THIS]
    raise JsThrow.new(js_reference_error("Must call super constructor in derived class before accessing 'this' or returning from derived constructor")) if th.is_a?(JsTdz)
    return th
  proto = nt.get("prototype")
  proto = JS_REALM[0].object_proto if !proto.is_a?(JsObject)
  obj = JsObject.new(proto, "Object")
  js_init_fields(f, obj) if f.fields != nil
  return obj if code.kind == :default_base
  r = js_exec(f, code, obj, args, nt)
  return r if r.is_a?(JsObject)
  obj

# Instance fields and private methods of class constructor f on a fresh obj.
-> js_init_fields(f, obj)
  fi = f.fields
  return nil if fi == nil
  fi.privs.each ->(p)
    obj.priv_add(p[0], p[1])
  return nil if fi.items.size == 0
  env = Array.new(fi.size, nil)
  env[0] = fi.env
  env[FS_THIS] = obj
  env[FS_FUNC] = f
  env[FS_HOME] = f.home
  fi.items.each ->(it)
    init = it[1]
    v = init == nil ? nil : init.call(env)
    if it[2]
      obj.priv_add(it[0], v)
    else
      js_create_data(obj, it[0], v)
  nil

# Make a closure for code over frame env.
-> js_make_closure(code, env)
  r = JS_REALM[0]
  k = code.kind
  proto = r.function_proto
  if k == :generator
    proto = r.intrinsic("%GeneratorFunction.prototype%")
  elsif k == :async || k == :async_arrow
    proto = r.intrinsic("%AsyncFunction.prototype%")
  elsif k == :async_gen
    proto = r.intrinsic("%AsyncGeneratorFunction.prototype%")
  f = JsFunction.new(proto, nil, code.name, code.length, k == :normal && !code.method)
  f.code = code
  f.scope = env
  f.lazy = code.lazy_kind
  f

# Function.prototype.toString
-> js_function_source(f)
  return "function " + f.fname.to_s + "() { \[native code] }" if f.code == nil || f.code.builtin
  f.code.source_text

# ---- errors: Tungsten exceptions → JS values ----

JS_DEBUG = [false]

-> js_error_value(e)
  return e.value if e.is_a?(JsThrow)
  msg = e.is_a?(String) ? e : e.message.to_s
  if JS_DEBUG[0]
    where = []
    k = JS_DEPTH[0]
    while k > 0 && where.size < 8
      c = JS_STACK[k]
      where.push(c.name.to_s + "@" + c.pos.to_s) if c != nil && k < 1000
      k -= 1
    ccall("w_eputs", "\[js internal] " + (e.is_a?(String) ? "String" : e.class_name) + ": " + msg + " in " + where.join(" < "))
  if msg.index("stack") != nil && msg.index("overflow") != nil
    return js_range_error("Maximum call stack size exceeded")
  js_type_error("internal: " + msg)

# ---- for-in ----

-> js_for_in_keys(v)
  return [] if js_nullish?(v)
  o = js_to_object(v)
  seen = {}
  out = []
  while o != nil && o != JS_NULL
    o.own_keys.each ->(k)
      if k.is_a?(String) && !seen.has_key?(k)
        seen[k] = true
        d = o.get_own_property(k)
        out.push(k) if d != nil && d.enumerable == true
    o = o.get_prototype_of
  out

# ---- arguments objects (unmapped) ----

-> js_arguments(args, callee, strict)
  r = JS_REALM[0]
  a = JsObject.new(r.object_proto, "Arguments")
  i = 0
  while i < args.size
    a.props[i.to_s] = args[i]
    i += 1
  a.define("length", args.size + ~0.0, ATTR_W + ATTR_C)
  a.define(SYM_ITERATOR, r.intrinsic("%ArrayProto_values%"), ATTR_W + ATTR_C)
  if strict
    th = r.intrinsic("%ThrowTypeError%")
    a.define_accessor("callee", th, th, 0)
  else
    a.define("callee", callee, ATTR_W + ATTR_C)
  a

# Mapped arguments (§10.4.4): a sloppy function with simple parameters aliases arguments[i]
# and its i-th parameter both ways while the index stays mapped.
+ JsArgumentsObj < JsObject
  rw :env, :map

  -> slot_for(k)
    return nil if !k.is_a?(String) || @map == nil
    s = @map[k]
    s

  -> unmap(k)
    @map.delete(k) if @map != nil
    nil

  -> own_value(k, receiver)
    s = slot_for(k)
    return @env[s] if s != nil
    super(k, receiver)

  -> get(k, receiver = nil)
    s = slot_for(k)
    return @env[s] if s != nil
    ord_get(k, receiver)

  -> set(k, v, receiver = nil)
    s = slot_for(k)
    if s != nil && (receiver == nil || receiver == self)
      @env[s] = v
      @props[k] = v
      return true
    ord_set(k, v, receiver)

  -> get_own_property(k)
    d = super(k)
    s = slot_for(k)
    d.value = @env[s] if d != nil && s != nil
    d

  -> define_own_property(k, desc)
    s = slot_for(k)
    if s != nil && !desc.accessor? && !desc.has_value && desc.writable == false
      # freezing a mapped index keeps its current value
      desc.value = @env[s]
      desc.has_value = true
    ok = super(k, desc)
    return ok if !ok || s == nil
    if desc.accessor?
      unmap(k)
    else
      @env[s] = desc.value if desc.has_value
      unmap(k) if desc.writable == false
    true

  -> delete_own(k)
    ok = super(k)
    unmap(k) if ok
    ok

-> js_mapped_arguments(args, callee, env, idx)
  r = JS_REALM[0]
  a = JsArgumentsObj.new(r.object_proto, "Arguments")
  a.env = env
  m = {}
  used = {}
  i = idx.size - 1
  while i >= 0
    # with duplicate parameter names the last one is the binding
    if i < args.size && !used.has_key?(idx[i])
      m[i.to_s] = idx[i]
    used[idx[i]] = true
    i -= 1
  a.map = m
  i = 0
  while i < args.size
    a.props[i.to_s] = args[i]
    i += 1
  a.define("length", args.size + ~0.0, ATTR_W + ATTR_C)
  a.define(SYM_ITERATOR, r.intrinsic("%ArrayProto_values%"), ATTR_W + ATTR_C)
  a.define("callee", callee, ATTR_W + ATTR_C)
  a

# ---- spread / rest ----

-> js_spread_into(out, v)
  if v.is_a?(JsArray) && js_array_iter_pristine?(v)
    i = 0
    while i < v.length
      out.push(js_arr_elem(v, i))
      i += 1
    return out
  if v.is_a?(String) && js_ascii?(v) && js_string_iter_pristine?()
    i = 0
    while i < v.size
      out.push(v.slice(i, 1))
      i += 1
    return out
  js_for_of(v, ->(x) out.push(x))
  out

-> js_array_iter_pristine?(a)
  r = JS_REALM[0]
  a.proto == r.array_proto && !a.has_own?(SYM_ITERATOR) && r.array_iter_pristine?

-> js_string_iter_pristine?
  JS_REALM[0].string_iter_pristine?

# ---- generators on goroutines ----

+ JsCoro
  rw :to, :from, :state, :code, :env, :f
  -> new(@code, @env)
    @to = nil
    @from = nil
    @state = :start
    @f = nil

+ JsGenerator < JsObject
  rw :coro

-> js_gen_create(f, code, this, args)
  env = js_activation(f, code, this, args, nil)
  p = f.get("prototype")
  p = JS_REALM[0].intrinsic("%GeneratorPrototype%") if !p.is_a?(JsObject)
  g = JsGenerator.new(p, "Generator")
  c = JsCoro.new(code, env)
  g.coro = c
  env[FS_GEN] = c
  g

JS_GOROUTINE_INIT = [false]
JS_CORO_LIVE = JsTlsCell.new(1, 0)
JS_CORO_TOTAL = JsTlsCell.new(1, 0)

-> js_coro_spawn(c)
  if !JS_GOROUTINE_INIT[0]
    JS_GOROUTINE_INIT[0] = true
    n = (4194304 ## int)
    ccall("w_goroutine_stack_size_hint", n)
  JS_CORO_LIVE[0] += 1
  JS_CORO_TOTAL[0] += 1
  if JS_CORO_LIVE[0] > 9000
    JS_CORO_LIVE[0] -= 1
    raise JsThrow.new(js_range_error("Too many suspended generators and async functions"))
  c.to = Channel.new(0)
  c.from = Channel.new(0)
  go ->
    js_coro_body(c)
  nil

# Only the main stack ever hands control to a coroutine (TODO(tungsten): two goroutines
# rendezvousing on unbuffered channels while main waits deadlocks the scheduler; repro
# nested_go2.w). A coroutine that wants to resume another asks main to do it with :call.
JS_CUR_CORO = JsTlsCell.new(1, nil)
JS_CORO_TRACE = [Env.get("BLADE_CORO_TRACE", "") == "1"]

-> js_coro_resume(c, msg, first)
  cur = JS_CUR_CORO[0]
  return js_coro_drive(c, msg, first) if cur == nil
  cur.from.send([:call, c, msg, first])
  reply = cur.to.receive
  reply[1]

-> js_coro_drive(c, msg, first)
  ccall("w_eputs", "drive first=" + first.to_s + " msg=" + msg.to_s) if JS_CORO_TRACE[0]
  JS_CUR_CORO[0] = c
  d0 = JS_DEPTH[0]
  if first
    js_coro_spawn(c)
  else
    c.to.send(msg)
  m = js_coro_wait(c)
  # the caller's depth is unchanged by whatever ran (and suspended) on the coroutine
  JS_DEPTH[0] = d0
  m

-> js_coro_wait(c)
  while true
    m = c.from.receive
    ccall("w_eputs", "got " + m[0].to_s) if JS_CORO_TRACE[0]
    JS_CUR_CORO[0] = nil
    if m[0] == :call
      res = js_coro_drive(m[1], m[2], m[3])
      JS_CUR_CORO[0] = c
      c.to.send([:ret, res])
    else
      return m
  nil

-> js_coro_body(c)
  depth = JS_DEPTH[0]
  msg = nil
  begin
    r = c.code.body.call(c.env)
    v = c.code.expr_body ? r : ((r != nil && r.kind == C_RETURN) ? r.value : nil)
    msg = [:return, v]
  rescue e
    if e.is_a?(JsGenReturn)
      msg = [:return, e.value]
    else
      msg = [:throw, js_error_value(e)]
  JS_DEPTH[0] = depth
  JS_CORO_LIVE[0] -= 1
  c.from.send(msg)
  nil

# Resume a generator: kind is :next, :throw or :return. Returns the iterator result.
-> js_gen_resume(g, kind, v)
  c = g.coro
  js_throw_type("next method called on incompatible receiver") if c == nil
  st = c.state
  if st == :running
    js_throw_type("Generator is already running")
  if st == :done
    raise JsThrow.new(v) if kind == :throw
    return js_iter_result(kind == :return ? v : nil, true)
  if st == :start
    if kind == :return
      c.state = :done
      return js_iter_result(v, true)
    if kind == :throw
      c.state = :done
      raise JsThrow.new(v)
    c.state = :running
    msg = js_coro_resume(c, nil, true)
  else
    c.state = :running
    msg = js_coro_resume(c, [kind, v], false)
  k = msg[0]
  if k == :yield
    c.state = :suspended
    return js_iter_result(msg[1], false)
  if k == :yield_raw
    c.state = :suspended
    return msg[1]
  c.state = :done
  c.env = nil
  raise JsThrow.new(msg[1]) if k == :throw
  js_iter_result(msg[1], true)

# Inside the generator's goroutine: hand v out and wait to be resumed.
-> js_yield(c, v)
  c.from.send([:yield, v])
  msg = c.to.receive
  k = msg[0]
  return msg[1] if k == :next
  raise JsThrow.new(msg[1]) if k == :throw
  raise JsGenReturn.new(msg[1])

# yield* iterable
-> js_yield_star(c, iterable)
  rec = js_get_iterator(iterable)
  received_kind = :next
  received = nil
  while true
    if received_kind == :next
      r = js_call(rec.next_fn, rec.iterator, [received])
    elsif received_kind == :throw
      th = js_get_method(rec.iterator, "throw")
      if th == nil
        js_iter_close(rec)
        js_throw_type("The iterator does not provide a 'throw' method")
      r = js_call(th, rec.iterator, [received])
    else
      rt = js_get_method(rec.iterator, "return")
      raise JsGenReturn.new(received) if rt == nil
      r = js_call(rt, rec.iterator, [received])
      js_throw_type("iterator result is not an object") if !r.is_a?(JsObject)
      raise JsGenReturn.new(r.get("value")) if js_to_boolean(r.get("done"))
    js_throw_type("iterator result is not an object") if !r.is_a?(JsObject)
    return r.get("value") if js_to_boolean(r.get("done")) && received_kind != :return
    c.from.send([:yield_raw, r])
    msg = c.to.receive
    received_kind = msg[0]
    received = msg[1]
  nil

# ---- async functions ----

-> js_async_call(f, code, this, args)
  cap = js_new_capability()
  env = nil
  begin
    env = js_activation(f, code, this, args, nil)
  rescue e
    js_call(cap.reject, nil, [js_error_value(e)])
    return cap.promise
  c = JsCoro.new(code, env)
  env[FS_GEN] = c
  c.state = :running
  js_async_step(c, cap, js_coro_resume(c, nil, true))
  cap.promise

-> js_async_step(c, cap, msg)
  k = msg[0]
  if k == :await
    c.state = :suspended
    on_ok = ->(x) js_async_resume(c, cap, :next, x)
    on_err = ->(x) js_async_resume(c, cap, :throw, x)
    js_promise_then_native(msg[1], on_ok, on_err)
    return nil
  c.state = :done
  c.env = nil
  if k == :return
    js_call(cap.resolve, nil, [msg[1]])
  else
    js_call(cap.reject, nil, [msg[1]])
  nil

-> js_async_resume(c, cap, kind, v)
  c.state = :running
  js_async_step(c, cap, js_coro_resume(c, [kind, v], false))
  nil

# Inside an async body's goroutine.
-> js_await(c, v)
  c.from.send([:await, v])
  msg = c.to.receive
  return msg[1] if msg[0] == :next
  raise JsThrow.new(msg[1])

# ---- async generators ----

+ JsAsyncGen < JsObject
  rw :coro, :queue, :busy

-> js_async_gen_create(f, code, this, args)
  env = js_activation(f, code, this, args, nil)
  p = f.get("prototype")
  p = JS_REALM[0].intrinsic("%AsyncGeneratorPrototype%") if !p.is_a?(JsObject)
  g = JsAsyncGen.new(p, "AsyncGenerator")
  c = JsCoro.new(code, env)
  g.coro = c
  g.queue = []
  g.busy = false
  env[FS_GEN] = c
  g

# next/throw/return on an async generator: queue the request, return its promise.
-> js_async_gen_enqueue(g, kind, v)
  cap = js_new_capability()
  if !g.is_a?(JsAsyncGen)
    js_call(cap.reject, nil, [js_type_error("not an async generator")])
    return cap.promise
  g.queue.push([kind, v, cap])
  js_async_gen_drain(g) if !g.busy
  cap.promise

-> js_async_gen_drain(g)
  c = g.coro
  while g.queue.size > 0 && !g.busy
    req = g.queue[0]
    kind = req[0]
    v = req[1]
    if c.state == :done || (c.state == :start && kind != :next)
      g.queue.shift
      c.state = :done
      if kind == :throw
        js_call(req[2].reject, nil, [v])
      else
        js_call(req[2].resolve, nil, [js_iter_result(kind == :return ? v : nil, true)])
    else
      g.busy = true
      first = c.state == :start
      c.state = :running
      js_async_gen_step(g, js_coro_resume(c, first ? nil : [kind, v], first))
  nil

-> js_async_gen_step(g, msg)
  c = g.coro
  k = msg[0]
  if k == :await
    on_ok = ->(x) js_async_gen_resume(g, :next, x)
    on_err = ->(x) js_async_gen_resume(g, :throw, x)
    js_promise_then_native(msg[1], on_ok, on_err)
    return nil
  req = g.queue.shift
  g.busy = false
  if k == :yield
    c.state = :suspended
    js_call(req[2].resolve, nil, [js_iter_result(msg[1], false)])
  elsif k == :return
    c.state = :done
    js_call(req[2].resolve, nil, [js_iter_result(msg[1], true)])
  else
    c.state = :done
    js_call(req[2].reject, nil, [msg[1]])
  js_async_gen_drain(g)
  nil

-> js_async_gen_resume(g, kind, v)
  c = g.coro
  js_async_gen_step(g, js_coro_resume(c, [kind, v], false))
  nil

# yield inside an async generator: await the value, then hand it out.
-> js_async_yield(c, v)
  v = js_await(c, v)
  c.from.send([:yield, v])
  msg = c.to.receive
  k = msg[0]
  return msg[1] if k == :next
  raise JsThrow.new(msg[1]) if k == :throw
  raise JsGenReturn.new(js_await(c, msg[1]))

# "    at name (url:line:col)" lines for the current call stack (Error.stack).
# The stack in JavaScriptCore's format (Blade presents as Safari): one "name@url:line:col"
# line per frame, innermost first, ending with "global code@url:line:col".
-> js_stack_lines
  out = []
  k = JS_DEPTH[0]
  k = 999 if k > 999
  while k > 0 && out.size < 100
    c = JS_STACK[k]
    if c != nil
      p = JS_POS[k] >= 0 ? JS_POS[k] : c.pos
      out.push(c.name.to_s + "@" + js_src_location(c.builtin ? nil : c.src, c.url, p) + (JS_DEBUG[0] && c.src != nil ? "  " + c.src.slice(p, 300).gsub("\n", " ") : ""))
    k -= 1
  if JS_TOP[0].size > 0 || JS_TOP[1].size > 0
    out.push("global code@" + js_src_location(JS_TOP[0], JS_TOP[1], JS_POS[0] < 0 ? 0 : JS_POS[0]))
  out.join("\n")

# The top frame's [url, line, column] (JSC's Error line/column/sourceURL).
-> js_top_location
  k = JS_DEPTH[0]
  src = JS_TOP[0]
  url = JS_TOP[1]
  p = JS_POS[0]
  if k > 0 && k < 1000 && JS_STACK[k] != nil
    c = JS_STACK[k]
    src = c.src
    url = c.url
    p = JS_POS[k] >= 0 ? JS_POS[k] : c.pos
  lc = js_src_linecol(src, p < 0 ? 0 : p)
  [url == nil ? "" : url, lc[0], lc[1]]

-> js_src_location(src, url, p)
  return "\[native code]" if src == nil
  lc = js_src_linecol(src, p)
  (url == nil || url == "" ? "" : url) + ":" + lc[0].to_s + ":" + lc[1].to_s

-> js_src_linecol(src, p)
  return [1, 1] if src == nil
  # perf: newline indexes of the last 8 sources (an Error's stack walks frames from several
  # scripts; one entry rebuilt the index of a 300 KB script per frame)
  srcs = JS_LINE_CACHE[0]
  if srcs == nil
    srcs = []
    JS_LINE_CACHE[0] = srcs
    JS_LINE_CACHE[1] = []
  nls = nil
  ci = 0
  while ci < srcs.size && nls == nil
    nls = JS_LINE_CACHE[1][ci] if srcs[ci] == src
    ci += 1
  if nls == nil
    nls = []
    k = src.index("\n", 0)
    while k != nil
      nls.push(k)
      k = src.index("\n", k + 1)
    if srcs.size >= 8
      srcs.shift
      JS_LINE_CACHE[1].shift
    srcs.push(src)
    JS_LINE_CACHE[1].push(nls)
  lo = 0
  hi = nls.size
  while lo < hi
    mid = (lo + hi) / 2
    if nls[mid] < p
      lo = mid + 1
    else
      hi = mid
  [lo + 1, lo == 0 ? p + 1 : p - nls[lo - 1]]

JS_LINE_CACHE = JsTlsCell.new(2, nil)

-> js_code_location(c)
  return "native" if c.src == nil
  lc = js_src_linecol(c.src, c.pos)
  "script:" + lc[0].to_s + ":" + lc[1].to_s

# BLADE_JS_PROFILE=2: calls and inclusive milliseconds per function.
JS_FN_PROFILE = [false]
JS_FN_STATS = {}

-> js_fn_profile_add(code, ms)
  e = JS_FN_STATS[code]
  if e == nil
    e = [0, 0]
    JS_FN_STATS[code] = e
  e[0] += 1
  e[1] += ms
  nil

-> js_fn_profile_report(n)
  rows = JS_FN_STATS.keys.map(->(c) [c, JS_FN_STATS[c]])
  rows = rows.sort_by(->(r) 0 - r[1][1])
  k = 0
  while k < n && k < rows.size
    c = rows[k][0]
    st = rows[k][1]
    ccall("w_eputs", "  " + st[1].to_s + " ms  " + st[0].to_s + " calls  " + c.name.to_s + " " + js_code_location(c) + " " + (c.src == nil ? "" : c.src.slice(c.pos, 90).gsub("\n", " ")))
    k += 1
  nil

# A task (script, timer, event callback) that runs longer than JS_TASK_MS is stopped with
# an error, as browsers stop unresponsive scripts. The embedder calls js_task_begin per task.
JS_TICKS = JsTlsCell.new(1, 0)
JS_TASK_MS = [10000]
JS_DEADLINE = JsTlsCell.new(1, 0)

JS_TASK_SEQ = JsTlsCell.new(1, 0)

-> js_task_begin
  js_aot_poll() if JS_AOT_UNITS.size > 0
  JS_DEADLINE[0] = clock_ms() + JS_TASK_MS[0]
  JS_TASK_SEQ[0] += 1
  nil

-> js_watchdog
  return nil if JS_DEADLINE[0] == 0 || clock_ms() < JS_DEADLINE[0]
  JS_DEADLINE[0] = 0
  where = js_stack_lines()
  ccall("w_eputs", "\[js] script timed out:\n" + where) if JS_DEBUG[0]
  raise JsThrow.new(js_range_error("Script timed out (busy for more than " + (JS_TASK_MS[0] / 1000).to_s + " s)"))
