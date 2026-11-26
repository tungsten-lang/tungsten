# blade/jsn/compat — the old engine's names (blade/js) that Blade's bindings use, on the
# js-aot runtime. Host objects are JsObject, a JS:Special with the old constructor; the
# few host classes that override internal methods (NodeList, DOMTokenList, dataset,
# CSSStyleDeclaration, Storage) say so with host_exotic?, which gives them the exotic
# kind so every property access goes through their methods.

+ JsObject < JS:Special
  rw :priv_handlers

  -> new(proto = JS_NULL, cls = "Object")
    @priv_handlers = nil
    @shape = js_root_shape(proto == JS_NULL ? nil : proto, SP_INLINE, SP_IBASE)
    @cls = cls
    @ext = nil
    @internal = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    jsr_set_kind(wvalue_bits(self) ## i64, host_exotic? ? KIND_EXOTIC : KIND_OBJECT)

  -> host_exotic?
    false

  # Ordinary [[Get]] and [[Set]] for subclasses that override get and set.
  -> ord_get(key, receiver = JS_HOLE)
    r = receiver == JS_HOLE ? self : receiver
    o = self
    while o != nil
      return o.get(key, r) if o != self && js_exotic_bits?(wvalue_bits(o) ## i64)
      s = o.shape
      i = s.slot_of(key)
      if i >= 0
        v = o.slot_get(i)
        return js_accessor_get(v, r) if (s.attrs_of(key) & ATTR_ACCESSOR) != 0
        return v
      o = s.proto
    nil

  -> ord_set(key, v, receiver = JS_HOLE)
    r = receiver == JS_HOLE ? self : receiver
    o = self
    while o != nil
      return o.set(key, v, r) if o != self && js_exotic_bits?(wvalue_bits(o) ## i64)
      s = o.shape
      i = s.slot_of(key)
      if i >= 0
        a = s.attrs_of(key)
        return js_accessor_set(o.slot_get(i), r, v) if (a & ATTR_ACCESSOR) != 0
        return false if (a & ATTR_W) == 0
        break
      o = s.proto
    return js_set_on_receiver(r, key, v) if r != self
    i = @shape.slot_of(key)
    if i >= 0
      slot_set(i, v)
      return true
    return false if !is_extensible?
    add_property(key, v, ATTR_DEFAULT)
    true

  -> get_idx(i)
    get(i.to_s, self)

  -> set_idx(i, v)
    set(i.to_s, v, self)

  -> extensible
    is_extensible?

+ JsHost < JS:Host
  -> new
    nil

# A host function object (wasm exports subclass it): the old constructor's arguments.
+ JsFunction < JS:NativeFunction
  -> new(proto, native, fname = "", arity = 0, ctor = false)
    @shape = proto == js_realm().function_proto ? js_realm().native_shape : js_root_shape(proto, NF_INLINE, NF_IBASE)
    @fn = native
    @name = fname
    @len = arity
    @ext = nil
    @data = nil
    @s0 = nil
    @s1 = nil
    jsr_set_kind(wvalue_bits(self) ## i64, ctor ? KIND_NATIVE | FNV_CTOR : KIND_NATIVE)

# Per-thread cells in the old engine. The js-aot engine runs on one thread (workers
# included), so a cell is a plain Array.
+ JsTlsCell
  -> new(n, init)
    @main = Array.new(n, init)

  -> [](k)
    @main[k]

  -> []=(k, v)
    @main[k] = v

  -> size
    @main.size

  -> set_for(idx, k, v)
    @main[k] = v

-> js_tls_register
  nil

-> js_tls_unregister
  nil

# ---- the engine-neutral names (blade/js/neutral.w has the old engine's) ----

-> js_exception(v)
  JS:Throw.new(v)

-> js_thrown?(e)
  e.is_a?(JS:Throw)

-> js_typed_array?(v)
  v.is_a?(JS:TypedArray)

-> js_array_buffer?(v)
  v.is_a?(JS:ArrayBuffer)

-> js_data_view?(v)
  v.is_a?(JS:DataView)

-> js_bigint?(v)
  v.is_a?(JS:BigIntValue)

-> js_bigint_new(n)
  JS:BigIntValue.new(n)

-> js_map_obj?(v)
  v.is_a?(JS:Special) && v.internal.is_a?(JS:MapData)

-> js_map_data(m)
  m.internal

-> js_symbol?(v)
  v.is_a?(JS:Symbol)

-> js_desc_data(v, attrs)
  JS:PropDesc.data(v, attrs)

# (js_cls and js_internal are the runtime's own, helpers.w)

# A JS array is its own element Array.
-> js_elems(a)
  a

-> js_ta_view(kind, buffer, offset, len, track)
  nm = TA_KINDS[kind][0]
  t = js_special_new(js_realm().intrinsic(nm + ".prototype"), nm, :typed)
  t.buffer = buffer
  t.offset = offset
  t.len = len
  t.kind = kind
  t.track = track
  t

-> js_buffer_wrap(data, blen, max_len, shared)
  kind = shared ? "SharedArrayBuffer" : "ArrayBuffer"
  b = js_special_new(js_realm().intrinsic(kind + ".prototype"), kind, :buffer)
  b.data = data
  b.blen = blen
  b.max_len = max_len
  b.detached = false
  b.shared = shared
  b

-> js_dv_view(buffer, offset, len, track)
  dv = js_special_new(js_realm().intrinsic("DataView.prototype"), "DataView", :view)
  dv.buffer = buffer
  dv.offset = offset
  dv.len = len
  dv.track = track
  dv

-> js_float_from_bits(b)
  bb = b ## i64
  wvalue_from_bits((bb + (0x0001000000000000 ## i64)) ## i64)

# ---- running scripts ----

# The running script's source and URL (locations for the timeline and errors).
JS_TOP = ["", ""]

-> js_run_script(src, name = "script")
  os = JS_TOP[0]
  ou = JS_TOP[1]
  oc = JS_CURRENT_URL[0]
  JS_TOP[0] = src
  JS_TOP[1] = name == "script" ? "" : name
  JS_CURRENT_URL[0] = JS_TOP[1] if JS_TOP[1].size > 0
  v = nil
  begin
    v = wk_run(src, JS_TOP[1])
  rescue e
    JS_TOP[0] = os
    JS_TOP[1] = ou
    JS_CURRENT_URL[0] = oc
    raise e
  JS_TOP[0] = os
  JS_TOP[1] = ou
  JS_CURRENT_URL[0] = oc
  v

-> js_run_builtin(src, name)
  wk_run(src, name)

# Slow-script deadline per task (the old engine's watchdog; nothing checks it yet).
JS_DEADLINE = JsTlsCell.new(1, 0)
JS_DEBUG = [false]

# A task starts with no JS running (a native that caught a script's exception may have
# left the stack pointer behind).
-> js_task_begin
  JS_CUR_ACT[0] = nil
  jsu_poll()

-> js_getidx(o, k)
  js_getv(o, k)

# (Collector hooks live in gc_core.w and gc.w.)

# ---- ES Modules bridge to jsn/module.w ----

JS_MODULE_HOST = [nil]
JS_MODULES = {}

-> js_ensure_browser_module_loader
  return nil if JS_MODULE_LOADER_HOOK[0] != nil
  JS_MODULE_LOADER_HOOK[0] = ->(ref_url, spec, attrs, phase)
    h = JS_MODULE_HOST[0]
    js_throw_type("No module host configured") if h == nil
    base = (ref_url == nil || ref_url.size == 0) ? nil : ref_url
    url = h.resolve(spec, base)
    src = h.load(url)
    js_throw_type("Failed to load module: " + url.to_s) if src == nil
    kind = :source
    if attrs != nil && attrs.has_key?("type")
      t = attrs["type"]
      if t == "json"
        kind = :json
      elsif t == "text"
        kind = :text
      elsif t == "bytes"
        kind = :bytes
      else
        js_throw_type("Unsupported import attribute type: " + t.to_s)
    [url, kind, src]
  nil

-> js_module_get(url)
  js_ensure_browser_module_loader()
  r = js_realm()
  key = url + "\0source"
  existing = r.modules[key]
  return existing if existing != nil
  m = JS_MODULES[url]
  return m if m != nil && m.realm == r
  h = JS_MODULE_HOST[0]
  js_throw_type("No module host configured") if h == nil
  src = h.load(url)
  js_throw_type("Failed to load module: " + url.to_s) if src == nil
  js_module_from_source(url, src)

-> js_module_from_source(url, src)
  js_ensure_browser_module_loader()
  r = js_realm()
  mod = js_mod_parse(src, url, r)
  r.modules[url + "\0source"] = mod
  JS_MODULES[url] = mod
  mod

-> js_module_evaluate(m)
  return nil if m == nil
  js_ensure_browser_module_loader()
  js_mod_link(m) if m.status == :unlinked
  prom = js_mod_evaluate(m)
  if prom.is_a?(JS:Special) && prom.internal.is_a?(JS:PromiseData)
    pd = prom.internal
    js_throw(pd.result) if pd.state == :rejected
  prom

# An own data property's value, nil when absent (accessors not called).
-> js_own(o, k)
  v = jget_own(o, k)
  v == JS_HOLE ? nil : v

-> js_set_proto(o, p)
  jset_prototype_of(o, p)

-> js_share_jobs(fr, prev)
  fr.share_jobs(prev)

# Timezone classes referenced by blade/determinism.
+ JsTz < JS:Tz
  -> new
    super()

+ JsTzRule < JS:TzRule
  -> new
    super()
