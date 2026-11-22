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
  rw :name, :length, :nslots, :binder, :body, :strict, :kind, :expr_body, :src, :pos, :fin, :is_class, :derived, :args_slot, :method, :lazy_kind, :self_slot

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

  -> arrow?
    @kind == :arrow || @kind == :async_arrow

  -> source_text
    return "function " + @name.to_s + "() { \[native code] }" if @src == nil
    @src.slice(@pos, @fin - @pos)

# Per-class instance field list, captured when the class is evaluated.
+ JsFieldInit
  rw :env, :size, :items, :privs
  -> new(@env, @size)
    @items = []
    @privs = []

JS_DEPTH = [0]
JS_MAX_DEPTH = [900]
JS_LAST_ENV = [nil]

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
-> js_setv(o, k, v, strict)
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
  env = js_activation(f, code, this, args, nt)
  r = code.body.call(env)
  JS_DEPTH[0] = d - 1
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
  return "function " + f.fname.to_s + "() { \[native code] }" if f.code == nil
  f.code.source_text

# ---- errors: Tungsten exceptions → JS values ----

JS_DEBUG = [false]

-> js_error_value(e)
  return e.value if e.is_a?(JsThrow)
  msg = e.message.to_s
  if JS_DEBUG[0]
    STDERR.puts("\[js internal] " + msg)
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

# ---- spread / rest ----

-> js_spread_into(out, v)
  if v.is_a?(JsArray) && js_array_iter_pristine?(v)
    el = v.elems
    i = 0
    while i < el.size
      x = el[i]
      out.push(x == JS_HOLE ? nil : x)
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

-> js_coro_spawn(c)
  if !JS_GOROUTINE_INIT[0]
    JS_GOROUTINE_INIT[0] = true
    n = (4194304 ## int)
    ccall("w_goroutine_stack_size_hint", n)
  c.to = Channel.new(0)
  c.from = Channel.new(0)
  go ->
    js_coro_body(c)
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
    js_coro_spawn(c)
  else
    c.state = :running
    c.to.send([kind, v])
  msg = c.from.receive
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
  js_coro_spawn(c)
  js_async_step(c, cap, c.from.receive)
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
  c.to.send([kind, v])
  js_async_step(c, cap, c.from.receive)
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
      if c.state == :start
        c.state = :running
        js_coro_spawn(c)
      else
        c.state = :running
        c.to.send([kind, v])
      js_async_gen_step(g, c.from.receive)
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
  c.to.send([kind, v])
  js_async_gen_step(g, c.from.receive)
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
