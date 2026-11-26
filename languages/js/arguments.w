# runtime/arguments — arguments objects (§10.4.4).
#
# Unmapped (strict code, non-simple parameter lists): an ordinary object with the
# indices, length, @@iterator and a callee that throws. Mapped (a sloppy function with
# simple parameters): an exotic object whose first indices alias the parameters, which
# the analysis keeps in the function's environment so the aliasing outlives the call.

in JS

+ Arguments < JS:Special
  rw :env, :map

  -> new(@shape)
    @cls = "Arguments"
    @ext = nil
    @internal = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    @env = nil
    @map = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_EXOTIC)

  # The environment slot index key aliases, or -1.
  -> mapped(key)
    return -1 if @map == nil || !js_string?(key) || !js_array_index?(key)
    i = key.to_i
    return -1 if i >= @map.size
    @map[i]

  -> unmap(key)
    @map[key.to_i] = -1
    nil

  -> get(key, receiver = JS_HOLE)
    m = mapped(key)
    return js_env_get(@env, m) if m >= 0
    super(key, receiver)

  -> get_own(key)
    m = mapped(key)
    return js_env_get(@env, m) if m >= 0
    super(key)

  -> set(key, v, receiver = JS_HOLE)
    m = mapped(key)
    if m >= 0 && (receiver == JS_HOLE || receiver == self)
      js_env_set(@env, m, v)
      super(key, v, receiver)
      return true
    super(key, v, receiver)

  -> get_own_property(key)
    d = super(key)
    m = mapped(key)
    d.value = js_env_get(@env, m) if d != nil && m >= 0
    d

  -> define_own_property(key, desc)
    m = mapped(key)
    if m >= 0 && !desc.accessor? && !desc.has_value && desc.writable == false
      # freezing a mapped index keeps its current value
      desc.value = js_env_get(@env, m)
      desc.has_value = true
    ok = super(key, desc)
    return false if !ok
    if m >= 0
      if desc.accessor?
        unmap(key)
      else
        js_env_set(@env, m, desc.value) if desc.has_value
        unmap(key) if desc.writable == false
    true

  -> delete_own(key)
    m = mapped(key)
    ok = super(key)
    unmap(key) if ok && m >= 0
    ok

# The arguments object of a call. slots: the environment slot of each parameter (mapped
# objects only), env: the function's environment.
-> js_arguments(args, callee, mapped, env, slots)
  r = js_realm()
  o = JS:Arguments.new(js_root_shape(r.object_proto, SP_INLINE, SP_IBASE))
  n = args.size
  i = 0
  while i < n
    o.define(i.to_s, args[i], ATTR_DEFAULT)
    i += 1
  o.define("length", n.to_f, ATTR_W + ATTR_C)
  it = r.intrinsics["%Array.prototype.values%"]
  o.define(SYM_ITERATOR, it, ATTR_W + ATTR_C) if it != nil
  if mapped
    o.define("callee", callee, ATTR_W + ATTR_C)
    o.env = env
    m = []
    i = 0
    while i < n && i < slots.size
      m.push(slots[i])
      i += 1
    # a parameter named twice aliases only its last occurrence
    i = 0
    while i < m.size
      j = i + 1
      while j < m.size
        m[i] = -1 if m[j] == m[i]
        j += 1
      i += 1
    o.map = m
  else
    th = js_throw_type_function()
    o.define_accessor("callee", th, th, 0)
  o

# %ThrowTypeError%: one per realm.
-> js_throw_type_function
  r = js_realm()
  t = r.intrinsics["%ThrowTypeError%"]
  if t == nil
    t = r.native("", 0, ->(this, args, nt) js_throw_type("'caller', 'callee', and 'arguments' properties may not be accessed on strict mode functions or the arguments objects for calls to them"))
    t.prevent_extensions
    r.set_intrinsic("%ThrowTypeError%", t)
  t
