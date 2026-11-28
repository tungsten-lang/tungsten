# runtime/function — function objects, code descriptors, environments, and calls.
#
#   JS:Code            one per function per loaded script: name, parameter count, flags, and
#                      the index of its native entry in the program's js_dispatch.
#   JS:Function        @shape @ext @code @env + 4 inline slots: 72 bytes, one block. name,
#                      length and prototype are virtual until a script writes, deletes or
#                      (for prototype) first reads them.
#   JS:NativeFunction  a static Tungsten function ->(this, args, new_target) and a data
#                      slot, so a builtin needs no capturing lambda.
#   JS:Env             a captured scope: @up and seven variables (JS:EnvN beyond).
#
# Entry convention of every compiled function (generic form):
#   jsf_N(f, this, argc, a0, a1, a2, a3, more)
# all WValues; argc an Int; more an Array of the arguments when argc > 4.

in JS

CODE_STRICT = 1
CODE_ARROW = 2
CODE_METHOD = 4
CODE_CTOR = 8          # constructible (ordinary functions and classes)
CODE_CLASS = 16        # class constructor (throws when called without new)
CODE_DERIVED = 32      # derived class constructor (`this` comes from super())
CODE_GEN = 64          # generator function
CODE_ASYNC = 128       # async function
CODE_NONT = 256        # compiled code that never reads new.target (js_new leaves it unset)

+ Code
  rw :name, :nparams, :index, :flags, :url, :start, :fin, :node, :entry, :jit_fp, :jit_hits, :jit_fast_fp, :jit_repeat_fp, :jit_fast_sig, :jit_state, :sm_code, :realm, :src_text, :jst_desc, :jst_state, :warm_args, :jit_vs_fp, :jit_vs_sig, :region_info, :ctor_rsh

  # node: tier 0's form of the function (its analysed JaFunc), when it has one.
  # entry: its compiled entry in a loaded unit, a closure (runtime/units.w; unit code
  # reads it as ivar 8); 0 when it has none.
  # jit_fp: in-process ARM64 JIT native entry address (ivar 9); 0 when uncompiled.
  -> new(@name, @nparams, @index, @flags)
    @url = nil
    @start = 0
    @fin = 0
    @node = nil
    @entry = 0
    @jit_fp = 0
    @jit_hits = 0
    @jit_fast_fp = 0
    @jit_repeat_fp = 0
    @jit_fast_sig = 0
    @jit_state = 0
    @sm_code = nil
    @realm = nil
    @src_text = nil
    @jst_desc = nil
    @jst_state = 0
    @warm_args = nil
    @jit_vs_fp = 0
    @jit_vs_sig = nil
    @region_info = nil
    @ctor_rsh = nil

FN_IBASE = 4
FN_INLINE = 4
# Function kind byte bits above the kind (KIND_PROTO is 128).
FNV_DONE = 64          # name/length were made real properties
FNV_PROTO = 32         # prototype was created (or a script defined it)
FNV_CTOR = 16          # (natives) callable with new

+ Function < JS:Base
  rw :code, :env, :s0, :s1, :s2, :s3

  -> new(@shape, @code, @env)
    @ext = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_FUNCTION)

  -> callable?
    true

  -> vflag?(b)
    (jsr_kind(wvalue_bits(self) ## i64) & b) != 0

  -> set_vflag(b)
    ob = wvalue_bits(self) ## i64
    jsr_set_kind(ob, jsr_kind(ob) | b)
    nil

  -> get_virtual(key)
    if key == "prototype"
      return JS_HOLE if vflag?(FNV_PROTO)
      fl = @code.flags
      r = @code.realm != nil ? @code.realm : js_realm()
      if (fl & CODE_GEN) != 0
        # a generator's prototype inherits %GeneratorPrototype% and has no constructor
        set_vflag(FNV_PROTO)
        gp = r.intrinsics[(fl & CODE_ASYNC) != 0 ? "%AsyncGeneratorPrototype%" : "%GeneratorPrototype%"]
        p = js_new_object(gp == nil ? r.object_proto : gp)
        define("prototype", p, ATTR_W)
        return p
      return JS_HOLE if (fl & CODE_CTOR) == 0
      set_vflag(FNV_PROTO)
      p = js_new_object(r.object_proto)
      p.define("constructor", self, ATTR_W + ATTR_C)
      define("prototype", p, ATTR_W)
      return p
    if (key == "caller" || key == "arguments") && (@code.flags & (CODE_STRICT | CODE_ARROW | CODE_METHOD | CODE_CLASS | CODE_GEN | CODE_ASYNC)) == 0
      r = @code.realm != nil ? @code.realm : js_realm()
      if @shape.proto == r.function_proto
        return key == "caller" ? js_fn_sloppy_caller(self) : js_fn_sloppy_arguments(self)
    return JS_HOLE if vflag?(FNV_DONE)
    return @code.name if key == "name"
    return @code.nparams.to_f if key == "length"
    JS_HOLE

  # name and length become real (non-enumerable, configurable) properties before any
  # change to the object's own keys.
  -> materialize
    return nil if vflag?(FNV_DONE)
    set_vflag(FNV_DONE)
    super_define("length", @code.nparams.to_f, ATTR_C) if !has_own_slot?("length")
    super_define("name", @code.name, ATTR_C) if !has_own_slot?("name")
    get_virtual("prototype")
    nil

  -> has_own_slot?(key)
    @shape.slot_of(key) >= 0

  -> super_define(key, v, attrs)
    i = @shape.slot_of(key)
    if i >= 0
      slot_set(i, v)
    else
      add_property(key, v, attrs)
    nil

  -> has_own?(key)
    materialize()
    @shape.slot_of(key) >= 0

  -> get_own(key)
    materialize()
    i = @shape.slot_of(key)
    return JS_HOLE if i < 0
    slot_get(i)

  -> own_keys
    materialize()
    super()

  -> delete_own(key)
    materialize()
    super(key)

  -> set(key, v, receiver = JS_HOLE)
    materialize() if !vflag?(FNV_DONE)
    super(key, v, receiver)

  -> define(key, v, attrs = ATTR_DEFAULT)
    if key == "prototype" && !vflag?(FNV_PROTO)
      set_vflag(FNV_PROTO)
    elsif !vflag?(FNV_DONE)
      materialize()
    super(key, v, attrs)

  -> define_accessor(key, g, st, flags = ATTR_E + ATTR_C)
    materialize() if !vflag?(FNV_DONE)
    super(key, g, st, flags)

  -> define_own_property(key, desc)
    materialize() if !vflag?(FNV_DONE)
    super(key, desc)

# A method or class constructor: a function with a home object (for super) and, for a
# class constructor, its instance fields ([key, initializer function or nil] pairs) and
# private methods ([private name, function, kind] triples).
+ Method < JS:Function
  rw :home, :fields, :privs, :inits

  -> new(@shape, @code, @env)
    @ext = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    @home = nil
    @fields = nil
    @privs = nil
    @inits = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_FUNCTION)

-> js_method_closure(code, env, home)
  fl = code.flags
  m = JS:Method.new((fl & 192) == 0 ? js_realm().fn_shape : js_fn_kind_shape(fl), code, env)
  m.home = home
  m

+ NativeFunction < JS:Base
  rw :fn, :name, :len, :data, :s0, :s1, :realm

  -> new(@shape, @fn, @name, @len)
    @ext = nil
    @data = nil
    @s0 = nil
    @s1 = nil
    @realm = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_NATIVE)

  -> callable?
    true

  # A builtin constructor (new F() calls it with new_target).
  -> ctor?
    (jsr_kind(wvalue_bits(self) ## i64) & FNV_CTOR) != 0

  -> set_ctor
    ob = wvalue_bits(self) ## i64
    jsr_set_kind(ob, jsr_kind(ob) | FNV_CTOR)
    nil

  -> get_virtual(key)
    return JS_HOLE if (jsr_kind(wvalue_bits(self) ## i64) & FNV_DONE) != 0
    return @name if key == "name"
    return @len.to_f if key == "length"
    JS_HOLE

  # length and name become real (non-enumerable, configurable) properties, in that
  # order, before any change to them or a listing of the own keys.
  -> materialize
    ob = wvalue_bits(self) ## i64
    return nil if (jsr_kind(ob) & FNV_DONE) != 0
    jsr_set_kind(ob, jsr_kind(ob) | FNV_DONE)
    add_property("length", @len.to_f, ATTR_C) if @shape.slot_of("length") < 0
    add_property("name", @name, ATTR_C) if @shape.slot_of("name") < 0
    nil

  -> own_keys
    materialize()
    super()

  -> delete_own(key)
    materialize() if key == "name" || key == "length"
    super(key)

  -> set(key, v, receiver = JS_HOLE)
    materialize() if (jsr_kind(wvalue_bits(self) ## i64) & FNV_DONE) == 0
    super(key, v, receiver)

  -> define(key, v, attrs = ATTR_DEFAULT)
    materialize() if (jsr_kind(wvalue_bits(self) ## i64) & FNV_DONE) == 0
    super(key, v, attrs)

  -> define_accessor(key, g, st, flags = ATTR_E + ATTR_C)
    materialize() if (jsr_kind(wvalue_bits(self) ## i64) & FNV_DONE) == 0
    super(key, g, st, flags)

  -> define_own_property(key, desc)
    materialize() if (jsr_kind(wvalue_bits(self) ## i64) & FNV_DONE) == 0
    super(key, desc)

NF_IBASE = 6
NF_INLINE = 2

+ Env
  rw :up, :v0, :v1, :v2, :v3, :v4, :v5, :v6
  -> new(@up)
    @v0 = nil
    @v1 = nil
    @v2 = nil
    @v3 = nil
    @v4 = nil
    @v5 = nil
    @v6 = nil

# More than seven: the first seven inline like JS:Env (same ivar positions, so a slot
# below seven reads the same way in both), the rest in @vars (slot 7 is vars[0]).
+ EnvN
  rw :up, :v0, :v1, :v2, :v3, :v4, :v5, :v6, :vars, :dyn
  -> new(@up, n)
    @v0 = nil
    @v1 = nil
    @v2 = nil
    @v3 = nil
    @v4 = nil
    @v5 = nil
    @v6 = nil
    @vars = Array.new(n > 7 ? n - 7 : 0, nil)
    @dyn = nil

# Object environment record for `with (obj) stmt` (ivar 0 = @up, matching JS:Env/JS:EnvN!).
+ WithEnv
  rw :up, :obj
  -> new(@up, @obj)
    nil

# A new closure over env for code.
-> js_closure(code, env)
  fl = code.flags
  f = (fl & 192) == 0 ? JS:Function.new(js_realm().fn_shape, code, env) : JS:Function.new(js_fn_kind_shape(fl), code, env)
  JS_GC_ON[0] ? js_gc_reg(f) : f

# The root shape of generator, async and async generator functions: their [[Prototype]]
# is %GeneratorFunction.prototype% and so on.
-> js_fn_kind_shape(fl)
  r = js_realm()
  k = fl & 192
  sh = r.kind_shapes[k]
  if sh == nil
    nm = (fl & CODE_GEN) != 0 ? ((fl & CODE_ASYNC) != 0 ? "%AsyncGeneratorFunction.prototype%" : "%GeneratorFunction.prototype%") : "%AsyncFunction.prototype%"
    p = r.intrinsics[nm]
    return r.fn_shape if p == nil
    sh = js_root_shape(p, FN_INLINE, FN_IBASE)
    r.kind_shapes[k] = sh
  sh

-> js_native(name, len, fn)
  r = js_realm()
  f = JS:NativeFunction.new(r.native_shape, fn, name, len)
  f.realm = r
  f

-> js_call_native(f, this, args, nt)
  fr = f.realm
  if fr == nil || fr == JS_REALM[0]
    return f.fn.call(this, args, nt)
  prev = JS_REALM[0]
  JS_REALM[0] = fr
  res = nil
  begin
    res = f.fn.call(this, args, nt)
  rescue ex
    JS_REALM[0] = prev
    raise ex
  JS_REALM[0] = prev
  res

# ---- calls ----

# The arguments of a generic entry as an Array (for natives and rest parameters).
-> js_args_array(argc, a0, a1, a2, a3, more)
  return more if argc > 4
  return JS_NO_ARGS if argc == 0
  return [a0] if argc == 1
  return [a0, a1] if argc == 2
  return [a0, a1, a2] if argc == 3
  [a0, a1, a2, a3]

JS_NO_ARGS = []

# Calls f with this and the arguments in generic-entry form.
-> js_call(f, this, argc, a0, a1, a2, a3, more)
  fb = wvalue_bits(f) ## i64
  k = jsr_kind(fb) & 15
  if k == KIND_FUNCTION
    code = wvalue_from_bits(jsr_ivar(fb, 2))
    return js_dispatch(wvalue_from_bits(jsr_ivar(wvalue_bits(code) ## i64, 2)), f, this, argc, a0, a1, a2, a3, more)
  js_call_slow(f, this, argc, a0, a1, a2, a3, more)

-> js_call_slow(f, this, argc, a0, a1, a2, a3, more)
  k = jsr_kind(wvalue_bits(f) ## i64) & 15
  if k == KIND_NATIVE
    return js_call_native(f, this, js_args_array(argc, a0, a1, a2, a3, more), nil)
  if k == KIND_BOUND
    return js_call_arr(f.target, f.bthis, f.args + js_args_array(argc, a0, a1, a2, a3, more))
  if k == KIND_EXOTIC && f.callable?
    return f.call_obj(this, js_args_array(argc, a0, a1, a2, a3, more).dup)
  js_throw_type(js_to_display_short(f) + " is not a function")

-> js_to_display_short(v)
  return "undefined" if v == nil
  return "null" if v == JS_NULL
  return "\[Proxy]" if js_proxy?(v)
  return js_inspect(v, 0) if js_object?(v)
  js_to_display(v)

# f(...args) with an Array of arguments (runtime and builtin callers).
-> js_call_arr(f, this, args)
  fb = wvalue_bits(f) ## i64
  if (jsr_kind(fb) & 15) == KIND_NATIVE
    return js_call_native(f, this, args, nil)
  n = args.size
  if n > 4
    return js_call(f, this, n, args[0], args[1], args[2], args[3], args)
  a0 = n > 0 ? args[0] : nil
  a1 = n > 1 ? args[1] : nil
  a2 = n > 2 ? args[2] : nil
  a3 = n > 3 ? args[3] : nil
  js_call(f, this, n, a0, a1, a2, a3, nil)

# The method call o.m(args) for a property site k.
-> js_call_method(o, key, k, argc, a0, a1, a2, a3, more)
  f = js_getp(o, key, k)
  js_call(f, o, argc, a0, a1, a2, a3, more)

# ic[j] when ic[i] == key (and key is not 0), else 0.
fn jsr_ic_word_if(ic, i, key, j) (i64[] i64 i64 i64) i64
  if key != 0 && ic[i] == key
    return ic[j]
  0

# new.target of the running constructor (one register per thread).
JS_NEW_TARGET = [nil]
JS_CONSTRUCT_REALM = [nil]

# new F(args) at a site with cache k: words k..k+3 cache F.prototype's slot, k+4 and
# k+5 the prototype and the root shape for its instances.
-> js_new(f, k, argc, a0, a1, a2, a3, more)
  fb = wvalue_bits(f) ## i64
  kind = jsr_kind(fb) & 15
  if kind == KIND_FUNCTION && (f.code.flags & CODE_CTOR) != 0
    proto = js_getp(f, "prototype", k)
    pb = wvalue_bits(proto) ## i64
    sh = nil
    sb = jsr_ic_word_if(JS_IC, k + 4, pb, k + 5)
    if sb != 0
      sh = wvalue_from_bits(sb)
    else
      p = js_object?(proto) ? proto : js_get_function_realm(f).object_proto
      sh = js_root_shape(p, OBJ_INLINE, OBJ_IBASE)
      if js_object?(proto)
        JS_IC[k + 4] = pb
        JS_IC[k + 5] = wvalue_bits(sh) ## i64
    is_der = (f.code.flags & CODE_DERIVED) != 0
    obj = is_der ? nil : JS:Object.new(sh)
    if (f.code.flags & CODE_NONT) != 0 && !is_der
      r = js_dispatch(f.code.index, f, obj, argc, a0, a1, a2, a3, more)
      return js_object?(r) ? r : obj
    saved = JS_NEW_TARGET[0]
    saved_cr = JS_CONSTRUCT_REALM[0]
    JS_NEW_TARGET[0] = f
    JS_CONSTRUCT_REALM[0] = JS_REALM[0] if is_der
    r = nil
    begin
      r = js_dispatch(f.code.index, f, obj, argc, a0, a1, a2, a3, more)
    rescue ex
      JS_NEW_TARGET[0] = saved
      JS_CONSTRUCT_REALM[0] = saved_cr
      raise ex
    JS_NEW_TARGET[0] = saved
    JS_CONSTRUCT_REALM[0] = saved_cr
    return js_object?(r) ? r : obj
  if kind == KIND_NATIVE && f.ctor?
    return js_call_native(f, nil, js_args_array(argc, a0, a1, a2, a3, more), f)
  if kind == KIND_BOUND || (kind == KIND_EXOTIC && f.constructor?)
    return js_construct(f, js_args_array(argc, a0, a1, a2, a3, more).dup, f)
  js_throw_type(js_to_display_short(f) + " is not a constructor")

-> js_new_arr(f, args)
  n = args.size
  js_new(f, JS_IC_SCRATCH, n, n > 0 ? args[0] : nil, n > 1 ? args[1] : nil, n > 2 ? args[2] : nil, n > 3 ? args[3] : nil, n > 4 ? args : nil)

# The environment of a function object (its @env, ivar 3).
-> js_fenv(f)
  fb = wvalue_bits(f) ## i64
  wvalue_from_bits(jsr_ivar(fb, 3))

# 1 when f is a JS:Function whose code is c (a call site's guess at its callee).
fn jsr_code_is(fb, cb) (i64 i64) i64
  if (jsr_kind(fb) & 15) != 2
    return 0
  if jsr_ivar(fb, 2) == cb
    return 1
  0

-> js_code_is?(f, c)
  fb = wvalue_bits(f) ## i64
  cb = wvalue_bits(c) ## i64
  jsr_code_is(fb, cb) != 0

# Legacy sloppy Function.prototype.caller lookup (walks JS_CUR_ACT).
-> js_fn_sloppy_caller(f)
  a = JS_CUR_ACT[0]
  while a != nil
    if a.fobj == f
      c = a.caller
      while c != nil && c.fobj == nil && c.caller != nil
        c = c.caller
      return JS_NULL if c == nil || c.f == nil || c.f.script
      cf = c.fobj
      return JS_NULL if cf == nil || c.f.strict || (cf.is_a?(JS:Function) && (cf.code.flags & (CODE_STRICT | CODE_GEN | CODE_ASYNC)) != 0)
      return cf
    a = a.caller
  JS_NULL

# Legacy sloppy Function.prototype.arguments lookup (walks JS_CUR_ACT).
-> js_fn_sloppy_arguments(f)
  a = JS_CUR_ACT[0]
  while a != nil
    if a.fobj == f
      arr = js_args_array(a.argc, a.a0, a.a1, a.a2, a.a3, a.args)
      return js_arguments(arr, f, true, nil, [])
    a = a.caller
  JS_NULL

# GetFunctionRealm (§7.3.22): returns obj's realm, throwing TypeError if obj is a revoked Proxy.
-> js_get_function_realm(obj)
  cur = obj
  while cur != nil
    k = jsr_kind(wvalue_bits(cur) ## i64) & 15
    if k == KIND_FUNCTION
      r = cur.code.realm
      return r != nil ? r : js_realm()
    elsif k == KIND_NATIVE
      r = cur.realm
      return r != nil ? r : js_realm()
    elsif k == KIND_BOUND
      cur = cur.target
    elsif k == KIND_EXOTIC && cur.proxy?
      cur.check()
      cur = cur.proxy_target
    else
      break
  js_realm()

-> js_check_function_realm(obj)
  js_get_function_realm(obj)
  nil

# [[Construct]](args, newTarget) for any constructor: the object (unless a derived class
# constructor makes its own through super()), created from newTarget's prototype.
-> js_construct(f, args, nt = nil)
  nt = f if nt == nil
  n = args.size
  a0 = n > 0 ? args[0] : nil
  a1 = n > 1 ? args[1] : nil
  a2 = n > 2 ? args[2] : nil
  a3 = n > 3 ? args[3] : nil
  more = n > 4 ? args : nil
  fb = wvalue_bits(f) ## i64
  kind = jsr_kind(fb) & 15
  if kind == KIND_FUNCTION && (f.code.flags & CODE_CTOR) != 0
    obj = nil
    is_der = (f.code.flags & CODE_DERIVED) != 0
    if !is_der
      proto = jget(nt, "prototype")
      if !js_object?(proto)
        proto = js_get_function_realm(nt).object_proto
      obj = js_new_object(proto)
    if (f.code.flags & CODE_NONT) != 0 && !is_der
      r = js_dispatch(f.code.index, f, obj, n, a0, a1, a2, a3, more)
      return js_object?(r) ? r : obj
    saved = JS_NEW_TARGET[0]
    saved_cr = JS_CONSTRUCT_REALM[0]
    JS_NEW_TARGET[0] = nt
    JS_CONSTRUCT_REALM[0] = JS_REALM[0] if is_der
    r = nil
    begin
      r = js_dispatch(f.code.index, f, obj, n, a0, a1, a2, a3, more)
    rescue ex
      JS_NEW_TARGET[0] = saved
      JS_CONSTRUCT_REALM[0] = saved_cr
      raise ex
    JS_NEW_TARGET[0] = saved
    JS_CONSTRUCT_REALM[0] = saved_cr
    return js_object?(r) ? r : obj
  if kind == KIND_NATIVE && f.ctor?
    return js_call_native(f, nil, args, nt)
  return f.construct(args, nt) if kind == KIND_BOUND || kind == KIND_EXOTIC
  js_throw_type(js_to_display_short(f) + " is not a constructor")

-> js_is_constructor?(f)
  fb = wvalue_bits(f) ## i64
  kind = jsr_kind(fb) & 15
  return (f.code.flags & CODE_CTOR) != 0 if kind == KIND_FUNCTION
  return f.ctor? if kind == KIND_NATIVE
  return f.constructor? if kind == KIND_BOUND || kind == KIND_EXOTIC
  false

-> js_auto_accessor_get(pn)
  fn = ->(this, args, nt)
    js_priv_get(this, pn)
  js_native("", 0, fn)

-> js_auto_accessor_set(pn)
  fn = ->(this, args, nt)
    js_priv_set(this, pn, args.size > 0 ? args[0] : nil)
    nil
  js_native("", 1, fn)

# The instance elements of a class (§7.3.34 InitializeInstanceElements): private methods,
# then fields in order, then decorator extra initializers.
-> js_init_fields(obj, f)
  return nil if !f.is_a?(JS:Method)
  ps = f.privs
  if ps != nil
    i = 0
    while i < ps.size
      e = ps[i]
      if e[2] == "method"
        obj.priv_add_method(e[0], e[1])
      else
        obj.priv_add_accessor(e[0], e[2] == "get" ? e[1] : nil, e[2] == "set" ? e[1] : nil)
      i += 1
  fs = f.fields
  if fs != nil
    i = 0
    while i < fs.size
      fd = fs[i]
      v = fd[1] == nil ? nil : js_call(fd[1], obj, 0, nil, nil, nil, nil, nil)
      if fd.size > 2 && fd[2]
        dk = fd.size > 3 && fd[3] != nil ? fd[3] : fd[0]
        js_set_fn_name(v, dk.is_a?(JS:PrivateName) ? dk.to_s : dk, nil)
      if fd.size > 4 && fd[4] != nil
        cbs = fd[4]
        ci = 0
        while ci < cbs.size
          v = js_call(cbs[ci], obj, 1, v, nil, nil, nil, nil)
          ci += 1
      if fd[0].is_a?(JS:PrivateName)
        obj.priv_add(fd[0], v)
      else
        jdefine_own_or_throw(obj, fd[0], v)
      i += 1
  ins = f.inits
  if ins != nil
    i = 0
    while i < ins.size
      js_call(ins[i], obj, 0, nil, nil, nil, nil, nil)
      i += 1
  nil

-> jdefine_own_or_throw(o, key, v)
  ok = jdefine_own_property(o, key, JS:PropDesc.data(v, ATTR_DEFAULT))
  js_throw_type("Cannot define property " + js_to_display(js_key_display(key))) if !ok
  nil
