# runtime/units — loading compiled units into a running host (PLAN.md 1.4, milestone 5).
#
# A unit (translate/unit.w, built by tools/jsu.sh) is an object file holding the
# translated functions of one script. Loading one:
#
#   u = js_unit_load(obj_path, manifest_text, codes)
#
# reads the manifest, fills the unit's context — the code pointer and captures of the
# host closure for each runtime entry it calls (runtime/unit_rt.w), then a slot per host
# value it uses — loads the object in memory (w_jit_load_object), and calls its
# jsu_init, which reports the address of each function's entry. Each JS:Code in codes
# (the host's descriptors, by function index: tier 0's, so closures tier 0 already made
# go native too) then gets entry (a closure), and js_dispatch calls it instead of
# tier 0 (js_unit_enter).

in JS

JSU_ABI = 1

use unit_id

# Everything a loaded unit's context points at stays reachable from here.
JSU_UNITS = []
# Loaded object files cached by path (one mmap per .o; jsu_init builds closures per ctx).
JSU_OBJ_FP = {}
# Parsed manifests cached by path (native Tungsten Hash/Array via JSON.parse).
JSU_MAN_CACHE = {}

+ Unit
  rw :path, :ctx, :keep, :nentries
  -> new(@path)
    @ctx = nil
    @keep = []
    @nentries = 0

# ---- what units call that compiled programs do not ----

-> js_env_new(up)
  JS:Env.new(up)

-> js_envn_new(up, n)
  JS:EnvN.new(up, n)

-> js_private_name_new(desc)
  JS:PrivateName.new(desc)

-> js_object_proto
  js_realm().object_proto

# The Array operations translated code does on its own lists (argument and key lists).
-> js_list_at(l, i)
  l[i]

-> js_list_size(l)
  l.size

-> js_list_push(l, x)
  l.push(x)
  l

# js_getp, js_setp, js_call_method and js_new with the unit's own cache table.
-> js_getp_t(o, key, ic, k)
  r = jsr_ic_get(ic, k, wvalue_bits(o) ## i64, JS_EPOCH[0])
  return wvalue_from_bits(r) if r != (6 ## i64)
  js_get_miss(o, key, ic, k)

-> js_setp_t(o, key, v, ic, k)
  i = jsr_ic_set(ic, k, wvalue_bits(o) ## i64, JS_EPOCH[0])
  if i > 0
    ccall("w_ivar_set_idx", o, i, v)
    return v
  js_set_miss(o, key, v, ic, k, false)

-> js_call_method_t(o, key, ic, k, argc, a0, a1, a2, a3, more)
  f = js_getp_t(o, key, ic, k)
  js_call(f, o, argc, a0, a1, a2, a3, more)

-> js_new_t(f, ic, k, argc, a0, a1, a2, a3, more)
  fb = wvalue_bits(f) ## i64
  kind = jsr_kind(fb) & 15
  if kind == KIND_FUNCTION && (f.code.flags & CODE_CTOR) != 0
    proto = js_getp_t(f, "prototype", ic, k)
    pb = wvalue_bits(proto) ## i64
    sh = nil
    sb = jsr_ic_word_if(ic, k + 4, pb, k + 5)
    if sb != 0
      sh = wvalue_from_bits(sb)
    else
      p = js_object?(proto) ? proto : js_realm().object_proto
      sh = js_root_shape(p, OBJ_INLINE, OBJ_IBASE)
      if js_object?(proto)
        ic[k + 4] = pb
        ic[k + 5] = wvalue_bits(sh) ## i64
    obj = (f.code.flags & CODE_DERIVED) != 0 ? nil : JS:Object.new(sh)
    if (f.code.flags & CODE_NONT) != 0
      r = js_dispatch(f.code.index, f, obj, argc, a0, a1, a2, a3, more)
      return js_object?(r) ? r : obj
    saved = JS_NEW_TARGET[0]
    JS_NEW_TARGET[0] = f
    r = js_dispatch(f.code.index, f, obj, argc, a0, a1, a2, a3, more)
    JS_NEW_TARGET[0] = saved
    return js_object?(r) ? r : obj
  js_new(f, JS_IC_SCRATCH, argc, a0, a1, a2, a3, more)

# ---- calling into a unit ----

# Call the entry of a function a unit compiled (code.entry, its closure, set at load).
# (C calls throughout: an argument passed as raw bits would not count as escaping.)
-> js_unit_enter(code, f, this, argc, a0, a1, a2, a3, more)
  ccall("w_closure_call_8", code.entry, f, this, argc, a0, a1, a2, a3, more)

fn jsu_call_init(fp, ctx) (i64 i64) i64
  ll <<~IR
    %fn = inttoptr i64 %fp to ptr
    %r = call i64 %fn(i64 %ctx)
    ret i64 %r
  IR

# The address of a typed array's elements (they never move).
fn jsu_raw(t) (i64[]) i64
  ll <<~IR
    ret i64 %t
  IR

# ---- loading ----

# The host value for a manifest slot [kind, key, data].
-> js_unit_slot_value(s, codes)
  kind = s[0]
  key = s[1]
  return key if kind == "str"
  return js_gcell(key) if kind == "gcell"
  return js_lcell(key) if kind == "lcell"
  return codes[key.to_i] if kind == "code"
  return js_lit_shape(s[2]) if kind == "shape"
  if kind == "tmpl"
    cooked = s[2][0].map(->(x) x == nil || x == JS_NULL ? nil : x)
    return js_template_object(cooked, s[2][1].dup)
  return i64[s[2].to_i < 8 ? 8 : s[2].to_i] if kind == "ic"
  if kind == "const"
    return js_realm() if key == "JSR"
    return JS_HOLE if key == "JS_HOLE"
    return JS_NULL if key == "JS_NULL"
    return JS_NO_ARGS if key == "JS_NO_ARGS"
    return JS_ITER_DONE if key == "JS_ITER_DONE"
  js_throw_type("unit: unknown slot " + kind + " " + key)

# Load the unit at obj_path for a script whose functions' JS:Code descriptors are codes
# (indexed like the script's functions). Returns the JS:Unit, or a String saying why not.
-> js_unit_load(obj_path, manifest_text, codes)
  man = JSU_MAN_CACHE[obj_path]
  if man == nil
    man = JSON.parse(manifest_text)
    JSU_MAN_CACHE[obj_path] = man if man.is_a?(Hash)
  return "manifest is not an object" if !man.is_a?(Hash)
  abi = man["abi"]
  return "unit ABI " + abi.to_s + ", host " + JSU_ABI.to_s if abi == nil || abi.to_i != JSU_ABI
  eng = man["engine"]
  return "unit from engine " + eng.to_s + ", host " + JSU_ENGINE_ID if eng != JSU_ENGINE_ID
  rt = man["rt"]
  slots = man["slots"]
  nfuncs = man["funcs"].to_i
  return "the unit's script has " + nfuncs.to_s + " functions, the host's " + codes.size.to_s if nfuncs != codes.size
  u = JS:Unit.new(obj_path)
  ctx = i64[1024 + slots.size]
  u.ctx = ctx
  k = 0
  while k < rt.size
    cl = JSU_RT[rt[k]]
    return "the host has no runtime entry " + rt[k] if cl == nil
    u.keep.push(cl)
    ctx[2 * k] = wvalue_bits(cl) ## i64
    k += 1
  j = 0
  while j < slots.size
    if slots[j][0] == "epoch"
      # the address of the prototype epoch (inline caches in the unit compare it)
      ctx[1024 + j] = jsu_raw(JS_EPOCH)
    else
      v = js_unit_slot_value(slots[j], codes)
      u.keep.push(v)
      ctx[1024 + j] = wvalue_bits(v) ## i64
    j += 1
  fp = JSU_OBJ_FP[obj_path]
  if fp == nil
    fp = ccall("w_jit_load_object", obj_path, "jsu_init")
    return "cannot load " + obj_path if fp == nil
    JSU_OBJ_FP[obj_path] = fp
  ctxi = jsu_raw(ctx)
  # jsu_init(ctx) answers [index, closure, …]: a function's entry is its closure (over ctx)
  pairs = wvalue_from_bits(jsu_call_init(fp ## i64, wvalue_bits(ctxi) ## i64))
  return "jsu_init answered no entries" if !pairs.is_a?(Array)
  u.keep.push(pairs)
  i = 0
  while i + 1 < pairs.size
    n = pairs[i]
    c = codes[n]
    if c != nil
      c.entry = pairs[i + 1]
      u.nentries += 1
    i += 2
  JSU_UNITS.push(u)
  u
