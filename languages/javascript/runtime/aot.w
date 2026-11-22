# blade/js/aot — tier 1: hot functions compiled ahead of time to native code.
#
# A function that the closure interpreter (interp.w) has run often enough is translated
# here, from the same AST and the same static scopes, into LLVM IR over Tungsten values
# (NaN-boxed WValue bits): locals live in registers, numbers are unboxed doubles with
# guards, control flow is native branches, and everything with JavaScript semantics
# beyond that (property access, calls, strings, coercions) is an upcall into the same
# run-time helpers the interpreter uses, through w_closure_call_N. clang -O2 builds the
# IR of all of a script's hot functions into one self-contained dylib (no undefined
# symbols, so no exported runtime is needed) on a background thread; the result is kept
# in ~/Library/Caches/Blade/jsaot/ keyed by the script's SHA-256 and JS_AOT_VERSION, and
# a repeat visit loads it with dlopen (no compiler involved) as functions are first called.
#
# Correctness: a function is compiled only when every construct in it is supported (see
# JsAotGen#gx / #gs); anything else raises JsAotUnsupported and the function stays in the
# interpreter. Generic paths are the interpreter's own helpers, so there is no
# deoptimization: a guard that fails takes the generic path in place.
#
# Validation: an artefact is used only when the manifest's engine version matches and the
# IR regenerated now for that function hashes to the hash recorded when it was built
# (so any change to the generator, the helper table or the function's source discards it).
#
# Native ABI: i64 @jsn_N(ptr ctx, i64 f, i64 this, i64 args, i64 scope); args is the
# Tungsten Array of arguments, scope the function's closure frame. ctx (one i64[] per
# function): [0..4] addresses of w_closure_call_0..4, [8 ...] the helper closures (JS_AOT_H),
# then the function's constants (strings, null, cells).

JS_AOT_VERSION = "jsaot-1"
JS_AOT_ON = [Env.get("BLADE_JS_AOT", "1") != "0"]
JS_AOT_DEBUG = [Env.get("BLADE_JS_AOT_DEBUG", "") == "1"]
# BLADE_JS_AOT_SYNC=1: build as soon as a function is hot and wait (tests).
JS_AOT_SYNC = [Env.get("BLADE_JS_AOT_SYNC", "") == "1"]
# Calls before a function is considered hot (BLADE_JS_AOT_HOT).
JS_AOT_HOT = [Env.get("BLADE_JS_AOT_HOT", "").size > 0 ? Env.get("BLADE_JS_AOT_HOT", "").to_i : 200]
JS_AOT_STATS = [0, 0, 0, 0, 0]   # hot, unsupported, compiled (built), loaded from cache, native calls

AOT_HBASE = 8
# Scripts at least this long get tier 1 (smaller ones rarely have hot code worth a build).
JS_AOT_MIN = [Env.get("BLADE_JS_AOT_MIN", "").size > 0 ? Env.get("BLADE_JS_AOT_MIN", "").to_i : 8192]

+ JsAotUnsupported < Error
  ro :what
  -> new(@what)
  -> message
    "unsupported: " + @what.to_s

# ---- the helper table: closures the native code upcalls (index = AOT_HBASE + position) ----

H_GETV = 0
H_LEN = 1
H_GETIDX = 2
H_SETV_S = 3
H_SETV = 4
H_PRESET = 5
H_SETIDX_S = 6
H_SETIDX = 7
H_GGET = 8
H_GUNDEF = 9
H_GTYPEOF = 10
H_GSET_S = 11
H_GSET = 12
H_CELLGET = 13
H_CELLSET = 14
H_CELLINIT = 15
H_TDZ = 16
H_CONSTERR = 17
H_ADD = 18
H_SUB = 19
H_MUL = 20
H_DIV = 21
H_MOD = 22
H_POW = 23
H_SHL = 24
H_SAR = 25
H_SHR = 26
H_BAND = 27
H_BOR = 28
H_BXOR = 29
H_LT = 30
H_GT = 31
H_LE = 32
H_GE = 33
H_SEQ = 34
H_LEQ = 35
H_INSTOF = 36
H_IN = 37
H_TRUTHY = 38
H_NEG = 39
H_TONUM = 40
H_BITNOT = 41
H_TYPEOF = 42
H_NUMVAL = 43
H_INC = 44
H_UPDMEM_S = 45
H_UPDMEM = 46
H_TOKEY = 47
H_CALL0 = 48
H_CALL1 = 49
H_CALL2 = 50
H_CALLA = 51
H_CALLM0 = 52
H_CALLM1 = 53
H_CALLM2 = 54
H_CALLMA = 55
H_CALLTA = 56
H_NEWA = 57
H_TARR = 58
H_TPUSH = 59
H_JSARR = 60
H_NEWOBJ = 61
H_LITPUT = 62
H_THROW = 63
H_REGEX = 64
H_TICK = 65
H_NULLSET = 66
H_GETVX = 67
H_REST = 68
H_NEWFRAME = 69
H_CLOSURE = 70
H_LITFN = 71
H_CALLF = 72
H_COUNT = 73

# Arity of each helper (which w_closure_call_N to use).
JS_AOT_HARITY = [2, 1, 2, 3, 3, 2, 3, 3, 1, 0, 1, 2, 2, 2, 2, 2, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 2, 4, 4, 1, 2, 3, 4, 3, 2, 3, 4, 3, 3, 3, 0, 2, 1, 0, 3, 1, 2, 0, 2, 2, 2, 2, 2, 4, 4]

JS_AOT_H = [nil]

-> js_aot_helpers
  return JS_AOT_H[0] if JS_AOT_H[0] != nil
  h = Array.new(H_COUNT, nil)
  h[H_GETV] = ->(o, k) js_getv_s(o, k)
  h[H_LEN] = ->(o) js_get_length(o)
  h[H_GETIDX] = ->(o, k) js_getidx_s(o, k)
  h[H_SETV_S] = ->(o, k, v) js_setv(o, k, v, true)
  h[H_SETV] = ->(o, k, v) js_setv(o, k, v, false)
  h[H_PRESET] = ->(o, k) js_aot_preset(o, k)
  h[H_SETIDX_S] = ->(o, k, v) js_setidx(o, k, v, true)
  h[H_SETIDX] = ->(o, k, v) js_setidx(o, k, v, false)
  h[H_GGET] = ->(nm) js_gget(nm)
  h[H_GUNDEF] = ->() js_gget_undefined()
  h[H_GTYPEOF] = ->(nm) js_gtypeof(nm)
  h[H_GSET_S] = ->(nm, v) js_gset(nm, v, true)
  h[H_GSET] = ->(nm, v) js_gset(nm, v, false)
  h[H_CELLGET] = ->(c, nm) js_tdz_check(c.v, nm)
  h[H_CELLSET] = ->(c, v) js_cell_assign(c, v)
  h[H_CELLINIT] = ->(c, v) js_aot_cell_init(c, v)
  h[H_TDZ] = ->(nm) js_tdz_error(nm)
  h[H_CONSTERR] = ->(nm) js_const_error(nm)
  h[H_ADD] = ->(a, b) js_add(a, b)
  h[H_SUB] = ->(a, b) js_arith(:sub, a, b)
  h[H_MUL] = ->(a, b) js_arith(:mul, a, b)
  h[H_DIV] = ->(a, b) js_arith(:div, a, b)
  h[H_MOD] = ->(a, b) js_arith(:mod, a, b)
  h[H_POW] = ->(a, b) js_arith(:pow, a, b)
  h[H_SHL] = ->(a, b) js_arith(:shl, a, b)
  h[H_SAR] = ->(a, b) js_arith(:sar, a, b)
  h[H_SHR] = ->(a, b) js_arith(:shr, a, b)
  h[H_BAND] = ->(a, b) js_arith(:band, a, b)
  h[H_BOR] = ->(a, b) js_arith(:bor, a, b)
  h[H_BXOR] = ->(a, b) js_arith(:bxor, a, b)
  h[H_LT] = ->(a, b) js_lt(a, b)
  h[H_GT] = ->(a, b) js_gt(a, b)
  h[H_LE] = ->(a, b) js_le(a, b)
  h[H_GE] = ->(a, b) js_ge(a, b)
  h[H_SEQ] = ->(a, b) js_strict_eq(a, b)
  h[H_LEQ] = ->(a, b) js_loose_eq(a, b)
  h[H_INSTOF] = ->(a, b) js_instanceof(a, b)
  h[H_IN] = ->(a, b) js_in(a, b)
  h[H_TRUTHY] = ->(v) js_truthy(v)
  h[H_NEG] = ->(v) js_neg(v)
  h[H_TONUM] = ->(v) js_to_number(v)
  h[H_BITNOT] = ->(v) js_bitnot(v)
  h[H_TYPEOF] = ->(v) js_typeof_v(v)
  h[H_NUMVAL] = ->(v) js_numeric_value(v)
  h[H_INC] = ->(v, d) js_inc(v, d)
  h[H_UPDMEM_S] = ->(o, k, d, p) js_update_member(o, k, d, p, true)
  h[H_UPDMEM] = ->(o, k, d, p) js_update_member(o, k, d, p, false)
  h[H_TOKEY] = ->(v) js_to_property_key(v)
  h[H_CALL0] = ->(f, w) js_call_named(f, nil, [], w)
  h[H_CALL1] = ->(f, w, a) js_call_named(f, nil, [a], w)
  h[H_CALL2] = ->(f, w, a, b) js_call_named(f, nil, [a, b], w)
  h[H_CALLA] = ->(f, w, arr) js_call_named(f, nil, arr, w)
  h[H_CALLM0] = ->(o, k) js_call_method(o, k, [])
  h[H_CALLM1] = ->(o, k, a) js_call_method(o, k, [a])
  h[H_CALLM2] = ->(o, k, a, b) js_call_method(o, k, [a, b])
  h[H_CALLMA] = ->(o, k, arr) js_call_method(o, k, arr)
  h[H_CALLTA] = ->(f, t, arr) js_call_named(f, t, arr, "expression")
  h[H_NEWA] = ->(f, w, arr) js_construct_named(f, arr, w)
  h[H_TARR] = ->() []
  h[H_TPUSH] = ->(arr, v) js_aot_push(arr, v)
  h[H_JSARR] = ->(arr) JsArray.new(JS_REALM[0].array_proto, arr)
  h[H_NEWOBJ] = ->() JsObject.new(JS_REALM[0].object_proto, "Object")
  h[H_LITPUT] = ->(o, k, v) js_lit_put(o, k, v)
  h[H_THROW] = ->(v) js_throw_value(v)
  h[H_REGEX] = ->(p, fl) js_regexp_create(p, fl)
  h[H_TICK] = ->() js_watchdog()
  h[H_NULLSET] = ->(o, k) js_nullish_set_check(o, k)
  h[H_GETVX] = ->(o, k) js_getv(o, k)
  h[H_REST] = ->(args, k) js_aot_rest(args, k)
  h[H_NEWFRAME] = ->(n, parent) js_aot_frame(n, parent)
  h[H_CLOSURE] = ->(code, env) js_make_closure(code, env)
  h[H_LITFN] = ->(o, k, code, env) js_lit_put_named_fn(o, k, code, env)
  h[H_CALLF] = ->(f, o, k, arr) js_call_named(f, o, arr, js_callee_desc(o, k))
  JS_AOT_H[0] = h
  h

-> js_aot_preset(o, k)
  js_nullish_set_check(o, k)
  (k.is_a?(Float) || k.is_a?(String) || k.is_a?(JsSymbol)) ? k : js_to_property_key(k)

-> js_aot_frame(n, parent)
  e = Array.new(n.to_i, nil)
  e[0] = parent
  e

-> js_aot_rest(args, k)
  out = []
  i = k.to_i
  while i < args.size
    out.push(args[i])
    i += 1
  JsArray.new(JS_REALM[0].array_proto, out)

-> js_aot_cell_init(c, v)
  c.v = v
  v

-> js_aot_push(arr, v)
  arr.push(v)
  arr

# ---- per-script units: hot functions, the background build, the cache ----

+ JsAotUnit
  rw :src, :url, :sha, :entries, :pending, :building, :thread, :result, :lib, :manifest, :loaded_syms, :dir, :failed, :seq

  -> new(@src, @url)
    @sha = nil
    @entries = {}      # "pos:fin" → JsAotEntry
    @pending = false
    @building = false
    @thread = nil
    @result = nil
    @lib = nil
    @manifest = nil    # "pos:fin" → [symbol, irhash] from the cache
    @loaded_syms = nil
    @dir = nil
    @failed = false
    @seq = 0

  -> key_sha
    @sha = Crypto.sha256(@src) if @sha == nil
    @sha

+ JsAotEntry
  rw :code, :ir, :hash, :sym, :consts, :ctx, :fp, :env_mode
  -> new(@code, @ir, @hash, @sym, @consts)
    @ctx = nil
    @fp = 0
    @env_mode = false

JS_AOT_UNITS = []

-> js_aot_unit_for(src, url)
  return nil if !JS_AOT_ON[0]
  u = JsAotUnit.new(src, url)
  JS_AOT_UNITS.push(u)
  u

JS_AOT_SWEPT = [false]

-> js_aot_dir
  home = Env.get("HOME", "/tmp")
  d = Env.get("BLADE_JS_AOT_DIR", "")
  d = home + "/Library/Caches/Blade/jsaot" if d.size == 0
  if !JS_AOT_SWEPT[0]
    # builds cut off by an exit leave their temporaries (name-bN-time.*): sweep old ones
    JS_AOT_SWEPT[0] = true
    OS.system("find '" + d + "' -name '*-" + JS_AOT_VERSION + "-b*' -mmin +10 -delete 2>/dev/null")
  d

-> js_aot_cc
  cc = Env.get("BLADE_JS_AOT_CC", "")
  return cc if cc.size > 0
  cands = ["/usr/bin/clang", "/opt/homebrew/opt/llvm/bin/clang"]
  i = 0
  while i < cands.size
    return cands[i] if File.exist?(cands[i])
    i += 1
  nil

-> js_aot_key(code)
  code.pos.to_s + ":" + code.fin.to_s

# A function crossed the hot threshold: translate it now (cheap, on this thread) and
# queue the unit for a background build.
-> js_aot_note_hot(code)
  u = code.unit
  return nil if u == nil || u.failed
  JS_AOT_STATS[0] += 1
  k = js_aot_key(code)
  return nil if u.entries.has_key?(k)
  e = js_aot_translate(code, u)
  if e == nil
    u.entries[k] = nil
    return nil
  u.entries[k] = e
  u.pending = true
  if JS_AOT_SYNC[0]
    js_aot_start_build(u)
    js_aot_install(u) if u.result != nil
  nil

# Translate one function; nil (and a debug line) when it uses something unsupported.
-> js_aot_translate(code, u)
  p = code.aot_src
  return nil if p == nil
  g = JsAotGen.new(code, p.node, p.sc, u.entries.size)
  ir = nil
  begin
    ir = g.gen_function()
  rescue e
    JS_AOT_STATS[1] += 1
    ccall("w_eputs", "\[jsaot] skip " + code.name.to_s + " @" + code.pos.to_s + ": " + e.message.to_s) if JS_AOT_DEBUG[0]
    return nil
  en = JsAotEntry.new(code, ir, Crypto.sha256(ir).slice(0, 16), g.sym, g.consts)
  en.env_mode = g.env_mode
  en

# Called at task boundaries (js_task_begin): start builds, install finished ones.
-> js_aot_poll
  return nil if !JS_AOT_ON[0]
  i = 0
  while i < JS_AOT_UNITS.size
    u = JS_AOT_UNITS[i]
    if u.building && u.result != nil
      js_aot_install(u)
    if u.pending && !u.building && !u.failed
      js_aot_start_build(u)
    i += 1
  nil

-> js_aot_start_build(u)
  cc = js_aot_cc()
  if cc == nil
    u.failed = true
    return nil
  u.pending = false
  u.building = true
  u.result = nil
  ents = u.entries.values.select(->(e) e != nil)
  sb = [JS_AOT_PRELUDE]
  ents.each ->(e) sb.push(e.ir)
  text = sb.join("\n")
  dir = js_aot_dir()
  u.seq += 1
  base = dir + "/" + u.key_sha.slice(0, 32) + "-" + JS_AOT_VERSION + "-b" + u.seq.to_s + "-" + clock_ms().to_s
  man = js_aot_manifest_text(u, ents)
  final = dir + "/" + u.key_sha.slice(0, 32) + "-" + JS_AOT_VERSION
  if JS_AOT_SYNC[0]
    js_aot_build(u, cc, dir, base, final, text, man, ents)
    return nil
  u.thread = Thread.new ->
    js_aot_build(u, cc, dir, base, final, text, man, ents)
  nil

# The build itself (a background thread, or inline in sync mode): clang, then publish the
# dylib and manifest under their final names (a rename, so readers never see half a file).
-> js_aot_build(u, cc, dir, base, final, text, man, ents)
  t0 = clock_ms()
  OS.system("mkdir -p '" + dir + "'")
  File.write(base + ".ll", text)
  st = OS.system(cc + " -O2 -shared -fPIC -Wno-override-module -o '" + base + ".dylib' '" + base + ".ll' 2>'" + base + ".err'")
  ok = st == true || st == 0
  if ok
    OS.system("mv -f '" + base + ".dylib' '" + final + ".dylib'")
    File.write(base + ".man", man)
    OS.system("mv -f '" + base + ".man' '" + final + ".manifest'")
    OS.system("rm -f '" + base + ".ll' '" + base + ".err'") if !JS_AOT_DEBUG[0]
  else
    # keep the IR and clang's message for a bug report, never a half-built library
    OS.system("rm -f '" + base + ".dylib'")
  u.result = [ok, final + ".dylib", ents, clock_ms() - t0]
  nil

-> js_aot_manifest_text(u, ents)
  lines = [JS_AOT_VERSION + " " + H_COUNT.to_s + " " + u.key_sha]
  ents.each ->(e) lines.push(js_aot_key(e.code) + " " + e.sym + " " + e.hash)
  lines.join("\n") + "\n"

-> js_aot_install(u)
  r = u.result
  u.building = false
  u.result = nil
  if !r[0]
    u.failed = true
    ccall("w_eputs", "\[jsaot] build failed for " + u.url.to_s) if JS_AOT_DEBUG[0]
    return nil
  JS_AOT_STATS[2] += r[2].size
  ccall("w_eputs", "\[jsaot] built " + r[2].size.to_s + " functions in " + r[3].to_s + " ms for " + u.url.to_s.slice(0, 80)) if JS_AOT_DEBUG[0]
  # dlopen caches by path: copy to a fresh name per load
  p = r[1] + "." + clock_ms().to_s + ".so"
  OS.system("cp '" + r[1] + "' '" + p + "'")
  h = ccall("w_dlopen", p)
  OS.system("rm -f '" + p + "'")
  if h == nil
    u.failed = true
    return nil
  r[2].each ->(e)
    a = ccall("w_dlsym", h, e.sym)
    js_aot_activate(e, a) if a != nil
  nil

-> js_aot_activate(e, addr)
  ctx = i64[AOT_HBASE + H_COUNT + e.consts.size + 1]
  ctx[0] = jsn_cc0_addr(0)
  ctx[1] = jsn_cc1_addr(0)
  ctx[2] = jsn_cc2_addr(0)
  ctx[3] = jsn_cc3_addr(0)
  ctx[4] = jsn_cc4_addr(0)
  hs = js_aot_helpers()
  i = 0
  while i < H_COUNT
    ctx[AOT_HBASE + i] = wvalue_bits(hs[i]) ## i64
    i += 1
  j = 0
  while j < e.consts.size
    ctx[AOT_HBASE + H_COUNT + j] = wvalue_bits(e.consts[j]) ## i64
    j += 1
  e.ctx = ctx
  e.fp = addr
  e.code.native = e
  nil

# Repeat visit: does the cache hold this function? Then load the unit's dylib (once) and
# use it, after regenerating the IR and checking its hash.
-> js_aot_from_cache(code)
  u = code.unit
  return nil if u == nil || u.failed
  if u.manifest == nil
    u.manifest = js_aot_read_manifest(u)
  return nil if u.manifest.size == 0
  k = js_aot_key(code)
  m = u.manifest[k]
  return nil if m == nil
  if u.lib == nil
    p = js_aot_dir() + "/" + u.key_sha.slice(0, 32) + "-" + JS_AOT_VERSION + ".dylib"
    tmp = p + "." + clock_ms().to_s + ".so"
    OS.system("cp '" + p + "' '" + tmp + "'")
    u.lib = ccall("w_dlopen", tmp)
    OS.system("rm -f '" + tmp + "'")
    if u.lib == nil
      u.failed = true
      return nil
  e = js_aot_translate_named(code, u, m[0])
  return nil if e == nil || e.hash != m[1]
  a = ccall("w_dlsym", u.lib, m[0])
  return nil if a == nil
  u.entries[k] = e
  js_aot_activate(e, a)
  JS_AOT_STATS[3] += 1
  nil

-> js_aot_translate_named(code, u, sym)
  p = code.aot_src
  return nil if p == nil
  g = JsAotGen.new(code, p.node, p.sc, 0)
  g.sym = sym
  ir = nil
  begin
    ir = g.gen_function()
  rescue e
    return nil
  File.write("/tmp/jsaot_" + sym + ".ll", ir) if JS_AOT_DEBUG[0]
  en = JsAotEntry.new(code, ir, Crypto.sha256(ir).slice(0, 16), sym, g.consts)
  en.env_mode = g.env_mode
  en

-> js_aot_read_manifest(u)
  m = {}
  path = js_aot_dir() + "/" + u.key_sha.slice(0, 32) + "-" + JS_AOT_VERSION + ".manifest"
  return m if !File.exist?(path)
  lines = File.read(path).split("\n")
  return m if lines.size == 0
  hd = lines[0].split(" ")
  return m if hd.size < 3 || hd[0] != JS_AOT_VERSION || hd[1] != H_COUNT.to_s || hd[2] != u.key_sha
  i = 1
  while i < lines.size
    f = lines[i].split(" ")
    m[f[0]] = [f[1], f[2]] if f.size == 3
    i += 1
  m

# Wait for running builds (tools, tests).
-> js_aot_wait
  js_aot_poll()
  JS_AOT_UNITS.each ->(u)
    u.thread.join if u.building && u.thread != nil
  js_aot_poll()
  nil

# ---- calling native code ----

-> js_native_exec(f, code, this, args)
  e = code.native
  d = JS_DEPTH[0] + 1
  if d > JS_MAX_DEPTH[0]
    raise JsThrow.new(js_range_error("Maximum call stack size exceeded"))
  JS_DEPTH[0] = d
  if d < 1000
    JS_STACK[d] = code
    JS_POS[d] = -1
  js_watchdog() if ((JS_TICKS[0] += 1) & 4095) == 0
  if !code.arrow? && !code.strict
    if this == nil || this == JS_NULL
      this = JS_REALM[0].global
    elsif !this.is_a?(JsObject) && !this.is_a?(JsTdz)
      this = js_to_object(this)
  JS_AOT_STATS[4] += 1
  fr = f.scope
  if e.env_mode
    # frame mode: the interpreter's own activation (parameters, arguments, hoisting)
    fr = js_activation(f, code, this, args, nil)
    js_tdz_fill(fr, code.aot_lex) if code.aot_lex != nil && code.aot_lex.size > 0
    code.aot_hoist.call(fr) if code.aot_hoist != nil
  r = jsn_invoke(e.fp, e.ctx, wvalue_bits(f) ## i64, wvalue_bits(this) ## i64, wvalue_bits(args) ## i64, wvalue_bits(fr) ## i64)
  JS_DEPTH[0] = d - 1
  wvalue_from_bits(r)

fn jsn_invoke(fp, ctx, f, th, args, scope) (i64 i64[] i64 i64 i64 i64) i64
  ll <<~IR
    %fn = inttoptr i64 %fp to ptr
    %cp = inttoptr i64 %ctx to ptr
    %r = call i64 %fn(ptr %cp, i64 %f, i64 %th, i64 %args, i64 %scope)
    ret i64 %r
  IR

fn jsn_cc0_addr(x) (i64) i64
  ll <<~IR
    %a = ptrtoint ptr @w_closure_call_0 to i64
    ret i64 %a
  IR

fn jsn_cc1_addr(x) (i64) i64
  ll <<~IR
    %a = ptrtoint ptr @w_closure_call_1 to i64
    ret i64 %a
  IR

fn jsn_cc2_addr(x) (i64) i64
  ll <<~IR
    %a = ptrtoint ptr @w_closure_call_2 to i64
    ret i64 %a
  IR

fn jsn_cc3_addr(x) (i64) i64
  ll <<~IR
    %a = ptrtoint ptr @w_closure_call_3 to i64
    ret i64 %a
  IR

fn jsn_cc4_addr(x) (i64) i64
  ll <<~IR
    %a = ptrtoint ptr @w_closure_call_4 to i64
    ret i64 %a
  IR

# Keeps w_closure_call_0..4 declared in the module (native code jumps to them).
-> js_aot_keep_cc(f)
  if f == 12345
    ccall("w_closure_call_0", f)
    ccall("w_closure_call_1", f, 0)
    ccall("w_closure_call_2", f, 0, 0)
    ccall("w_closure_call_3", f, 0, 0, 0)
    ccall("w_closure_call_4", f, 0, 0, 0, 0)
  nil

# ---- the IR every module starts with ----
# hcN: upcall helper i with N arguments; kld: constant j; isd/unb/box: doubles;
# aget/aset: element i of a Tungsten Array (frames); argn: argument k or undefined.

JS_AOT_PRELUDE = "; Blade JS AOT module (" + JS_AOT_VERSION + ")
define internal i64 @hc0(ptr %ctx, i64 %i) alwaysinline {
  %fa = load i64, ptr %ctx
  %fn = inttoptr i64 %fa to ptr
  %cp = getelementptr i64, ptr %ctx, i64 %i
  %c = load i64, ptr %cp
  %r = call i64 %fn(i64 %c)
  ret i64 %r
}
define internal i64 @hc1(ptr %ctx, i64 %i, i64 %a) alwaysinline {
  %fp = getelementptr i64, ptr %ctx, i64 1
  %fa = load i64, ptr %fp
  %fn = inttoptr i64 %fa to ptr
  %cp = getelementptr i64, ptr %ctx, i64 %i
  %c = load i64, ptr %cp
  %r = call i64 %fn(i64 %c, i64 %a)
  ret i64 %r
}
define internal i64 @hc2(ptr %ctx, i64 %i, i64 %a, i64 %b) alwaysinline {
  %fp = getelementptr i64, ptr %ctx, i64 2
  %fa = load i64, ptr %fp
  %fn = inttoptr i64 %fa to ptr
  %cp = getelementptr i64, ptr %ctx, i64 %i
  %c = load i64, ptr %cp
  %r = call i64 %fn(i64 %c, i64 %a, i64 %b)
  ret i64 %r
}
define internal i64 @hc3(ptr %ctx, i64 %i, i64 %a, i64 %b, i64 %d) alwaysinline {
  %fp = getelementptr i64, ptr %ctx, i64 3
  %fa = load i64, ptr %fp
  %fn = inttoptr i64 %fa to ptr
  %cp = getelementptr i64, ptr %ctx, i64 %i
  %c = load i64, ptr %cp
  %r = call i64 %fn(i64 %c, i64 %a, i64 %b, i64 %d)
  ret i64 %r
}
define internal i64 @hc4(ptr %ctx, i64 %i, i64 %a, i64 %b, i64 %d, i64 %e) alwaysinline {
  %fp = getelementptr i64, ptr %ctx, i64 4
  %fa = load i64, ptr %fp
  %fn = inttoptr i64 %fa to ptr
  %cp = getelementptr i64, ptr %ctx, i64 %i
  %c = load i64, ptr %cp
  %r = call i64 %fn(i64 %c, i64 %a, i64 %b, i64 %d, i64 %e)
  ret i64 %r
}
define internal i64 @kld(ptr %ctx, i64 %i) alwaysinline {
  %cp = getelementptr i64, ptr %ctx, i64 %i
  %c = load i64, ptr %cp
  ret i64 %c
}
define internal i1 @isd(i64 %v) alwaysinline {
  %s = sub i64 %v, 281474976710656
  %r = icmp ule i64 %s, -4503599627370496
  ret i1 %r
}
define internal double @unb(i64 %v) alwaysinline {
  %s = sub i64 %v, 281474976710656
  %d = bitcast i64 %s to double
  ret double %d
}
define internal i64 @box(double %d) alwaysinline {
  %n = fcmp uno double %d, %d
  %b = bitcast double %d to i64
  %x = add i64 %b, 281474976710656
  %r = select i1 %n, i64 9221401712017801216, i64 %x
  ret i64 %r
}
define internal ptr @aslot(i64 %a, i64 %i) alwaysinline {
  %p = and i64 %a, 140737488355312
  %ap = inttoptr i64 %p to ptr
  %stp = getelementptr i8, ptr %ap, i64 4
  %st = load i32, ptr %stp
  %st64 = sext i32 %st to i64
  %slp = getelementptr i8, ptr %ap, i64 16
  %sl = load ptr, ptr %slp
  %k = add i64 %st64, %i
  %ep = getelementptr i64, ptr %sl, i64 %k
  ret ptr %ep
}
define internal i64 @aget(i64 %a, i64 %i) alwaysinline {
  %ep = call ptr @aslot(i64 %a, i64 %i)
  %v = load i64, ptr %ep
  ret i64 %v
}
define internal void @aset(i64 %a, i64 %i, i64 %v) alwaysinline {
  %ep = call ptr @aslot(i64 %a, i64 %i)
  store i64 %v, ptr %ep
  ret void
}
define internal i64 @argn(i64 %a, i64 %k) alwaysinline {
  %p = and i64 %a, 140737488355312
  %ap = inttoptr i64 %p to ptr
  %szp = getelementptr i8, ptr %ap, i64 8
  %sz = load i32, ptr %szp
  %sz64 = sext i32 %sz to i64
  %in = icmp slt i64 %k, %sz64
  br i1 %in, label %yes, label %no
yes:
  %v = call i64 @aget(i64 %a, i64 %k)
  ret i64 %v
no:
  ret i64 0
}
define internal i1 @truthy(ptr %ctx, i64 %v) alwaysinline {
  %t = icmp eq i64 %v, 2
  br i1 %t, label %yes, label %n1
n1:
  %f = icmp ule i64 %v, 1
  br i1 %f, label %no, label %n2
n2:
  %d = call i1 @isd(i64 %v)
  br i1 %d, label %dbl, label %slow
dbl:
  %x = call double @unb(i64 %v)
  %nz = fcmp one double %x, 0.0
  ret i1 %nz
slow:
  %r = call i64 @hc1(ptr %ctx, i64 " + (AOT_HBASE + H_TRUTHY).to_s + ", i64 %v)
  %rb = icmp eq i64 %r, 2
  ret i1 %rb
yes:
  ret i1 1
no:
  ret i1 0
}
declare double @llvm.fabs.f64(double)
"

# ---- the translator ----

+ JsAotLoop
  rw :labels, :brk, :cont
  -> new(@labels, @brk, @cont)

+ JsAotGen
  rw :sym, :consts, :env_mode

  -> new(@code, @node, @sc, @id)
    @jc = JsCompiler.new(@code.src)
    @sym = "jsn_" + @code.pos.to_s + "_" + @id.to_s
    @consts = []
    @const_ix = {}
    @lines = []
    @t = 0
    @cur = "body"
    @loops = []
    @fsc = nil
    @strict = false
    @null_k = -1
    @tdz_k = -1
    @env_mode = false
    @frames = []
    @map = nil

  # ---- emission helpers ----

  -> emit(s)
    @lines.push("  " + s)
    nil

  -> tmp
    @t += 1
    "%t" + @t.to_s

  -> newlabel(p)
    @t += 1
    p + @t.to_s

  -> label(l)
    @lines.push(l + ":")
    @cur = l
    nil

  -> br(l)
    emit("br label %" + l)

  -> condbr(c, a, b)
    emit("br i1 " + c + ", label %" + a + ", label %" + b)

  # A terminator was emitted; anything after it goes to an unreachable block.
  -> dead
    label(newlabel("dead"))

  -> unsupported(what)
    raise JsAotUnsupported.new(what)

  # Constant table slot for a Tungsten value (strings, null, cells, names).
  -> kidx(v)
    if v.is_a?(String)
      j = @const_ix[v]
      return j if j != nil
    j = @consts.size
    @consts.push(v)
    @const_ix[v] = j if v.is_a?(String)
    j

  -> kload(v)
    t = tmp()
    emit(t + " = call i64 @kld(ptr %ctx, i64 " + (AOT_HBASE + H_COUNT + kidx(v)).to_s + ")")
    t

  -> knull
    @null_k = kidx(JS_NULL) if @null_k < 0
    t = tmp()
    emit(t + " = call i64 @kld(ptr %ctx, i64 " + (AOT_HBASE + H_COUNT + @null_k).to_s + ")")
    t

  -> ktdz
    @tdz_k = kidx(JS_TDZ) if @tdz_k < 0
    t = tmp()
    emit(t + " = call i64 @kld(ptr %ctx, i64 " + (AOT_HBASE + H_COUNT + @tdz_k).to_s + ")")
    t

  -> hcall(h, args)
    n = JS_AOT_HARITY[h]
    unsupported("helper arity") if n != args.size
    t = tmp()
    s = t + " = call i64 @hc" + n.to_s + "(ptr %ctx, i64 " + (AOT_HBASE + h).to_s
    args.each ->(a) s = s + ", i64 " + a
    emit(s + ")")
    t

  # A helper that never returns (throws).
  -> hthrow(h, args)
    hcall(h, args)
    emit("unreachable")
    dead()
    nil

  -> num_bits(x)
    (wvalue_bits(x) ## i64).to_s

  -> truthy(v)
    t = tmp()
    emit(t + " = call i1 @truthy(ptr %ctx, i64 " + v + ")")
    t

  -> bool_of(c)
    t = tmp()
    emit(t + " = select i1 " + c + ", i64 2, i64 1")
    t

  -> phi2(a, la, b, lb)
    t = tmp()
    emit(t + " = phi i64 \[ " + a + ", %" + la + " ], \[ " + b + ", %" + lb + " ]")
    t

  -> hargs
    "%args"

  -> slot_ptr(i)
    "%l" + i.to_s

  # ---- the function ----

  -> gen_function
    n = @node
    code = @code
    unsupported("kind " + code.kind.to_s) if code.kind != :normal && code.kind != :method && code.kind != :arrow
    unsupported("class constructor") if code.is_class
    js_lazy_parse_body(n, code.src) if n.b == nil && n.c != nil
    arrow = n.kind == :arrow
    body0 = n.b
    simple = true
    n.list.each ->(p)
      simple = false if !(p.kind == :ident || (p.kind == :assign_pattern && p.a.kind == :ident && !@jc.has_closure?(p.b)) || (p.kind == :rest && p.a.kind == :ident))
    closures = (arrow && n.has?(F_EXPR_BODY)) ? @jc.has_closure?(body0) : @jc.any_closure?(body0)
    if closures || !simple || (!arrow && n.has?(F_USES_ARGS))
      return gen_frame_function()
    fsc = JsScope.new(arrow ? :arrow : :function, @sc, true)
    fsc.strict = @sc.strict || n.has?(F_STRICT)
    fsc.derived = false
    @fsc = fsc
    @strict = fsc.strict
    if n.kind == :function && n.str != nil
      b = JsBinding.new(n.str, :self, fsc, FS_FUNC)
      fsc.names[n.str] = b
    params = n.list
    pidx = []
    pdef = []
    rest = -1
    params.each ->(p)
      if p.kind == :ident
        pidx.push(fsc.declare(p.str, :param).index)
        pdef.push(nil)
      elsif p.kind == :assign_pattern && p.a.kind == :ident
        pidx.push(fsc.declare(p.a.str, :param).index)
        pdef.push(p.b)
      elsif p.kind == :rest && p.a.kind == :ident
        rest = fsc.declare(p.a.str, :param).index
      else
        unsupported("pattern parameter")
    # defaults run in order, each after the parameters before it are bound
    k = 0
    while k < pidx.size
      if pdef[k] != nil
        unsupported("closure in default") if @jc.has_closure?(pdef[k])
        cur = tmp()
        emit(cur + " = load i64, ptr %l" + pidx[k].to_s)
        z = tmp()
        emit(z + " = icmp eq i64 " + cur + ", 0")
        ld = newlabel("pd")
        lj = newlabel("pdj")
        condbr(z, ld, lj)
        label(ld)
        dv = gx(pdef[k], fsc)
        emit("store i64 " + dv + ", ptr %l" + pidx[k].to_s)
        br(lj)
        label(lj)
      k += 1
    if rest >= 0
      rv = hcall(H_REST, [hargs(), num_bits(pidx.size + ~0.0)])
      emit("store i64 " + rv + ", ptr %l" + rest.to_s)
    body = n.b
    if arrow && n.has?(F_EXPR_BODY)
      unsupported("closure in body") if @jc.has_closure?(body)
      v = gx(body, fsc)
      emit("ret i64 " + v)
    else
      unsupported("closure in body") if @jc.any_closure?(body)
      vn = @jc.var_names(body, [], fsc.strict, true)
      vn.each ->(nm) fsc.declare(nm, :var)
      body.each ->(s)
        unsupported("function declaration") if s.kind == :function_decl
      @jc.lex_decls(body, fsc.strict).each ->(d) fsc.declare(d[0], d[1])
      tdz_fill(fsc.lex)
      body.each ->(s) gs(s, fsc, nil)
      emit("ret i64 0")
    # entry block: one alloca per frame slot, parameters from the arguments array
    pre = ["define i64 @" + @sym + "(ptr %ctx, i64 %f, i64 %this, i64 %args, i64 %scope) {", "entry:"]
    i = FS_FIRST
    while i < fsc.size
      pre.push("  %l" + i.to_s + " = alloca i64")
      pre.push("  store i64 0, ptr %l" + i.to_s)
      i += 1
    pre.push("  %tick = alloca i64")
    pre.push("  store i64 0, ptr %tick")
    k = 0
    while k < pidx.size
      pre.push("  %a" + k.to_s + " = call i64 @argn(i64 %args, i64 " + k.to_s + ")")
      pre.push("  store i64 %a" + k.to_s + ", ptr %l" + pidx[k].to_s)
      k += 1
    pre.push("  br label %body")
    pre.push("body:")
    (pre + @lines + ["}", ""]).join("\n")

  # Frame mode, for functions with closures, `arguments` or patterned parameters: every
  # binding lives in the interpreter's frames (same scopes, same slots, recorded by
  # interp.w in code.aot_map), so inner functions (still interpreted) share them. The
  # host builds the activation; %scope is that frame.
  -> gen_frame_function
    n = @node
    @env_mode = true
    @map = @code.aot_map
    unsupported("no scope map") if @map == nil
    fsc = @map[n]
    unsupported("no function scope") if fsc == nil
    @fsc = fsc
    @strict = fsc.strict
    @frames = [[fsc, "%scope"]]
    body = n.b
    if n.kind == :arrow && n.has?(F_EXPR_BODY)
      v = gx(body, fsc)
      emit("ret i64 " + v)
    else
      body.each ->(st) gs(st, fsc, nil)
      emit("ret i64 0")
    pre = ["define i64 @" + @sym + "(ptr %ctx, i64 %f, i64 %this, i64 %args, i64 %scope) {", "entry:", "  %tick = alloca i64", "  store i64 0, ptr %tick", "  br label %body", "body:"]
    (pre + @lines + ["}", ""]).join("\n")

  # The SSA value holding the frame of scope fr (frame mode).
  -> frame_val(fr)
    i = @frames.size - 1
    while i >= 0
      return @frames[i][1] if @frames[i][0] == fr
      i -= 1
    unsupported("frame")

  -> frame_tdz_fill(fr, lex)
    return nil if lex.size == 0
    tz = ktdz()
    e = frame_val(fr)
    lex.each ->(i) emit("call void @aset(i64 " + e + ", i64 " + i.to_s + ", i64 " + tz + ")")
    nil

  # let/const/class bindings start in the TDZ (marker 3, never a JS value).
  -> tdz_fill(lex)
    lex.each ->(i) emit("store i64 3, ptr %l" + i.to_s)
    nil

  # ---- statements ----

  -> gs(n, sc, labels)
    k = n.kind
    case k
    when :expr_stmt
      gx(n.a, sc)
    when :var_decl
      g_var_decl(n, sc)
    when :empty, :debugger
      nil
    when :block
      g_block(n, sc)
    when :function_decl
      unsupported("function declaration") if !@env_mode || sc != @fsc
    when :if
      c = truthy(gx(n.a, sc))
      lt = newlabel("then")
      le = newlabel("else")
      lj = newlabel("endif")
      condbr(c, lt, n.c == nil ? lj : le)
      label(lt)
      gs(n.b, sc, nil)
      br(lj)
      if n.c != nil
        label(le)
        gs(n.c, sc, nil)
        br(lj)
      label(lj)
    when :while
      lh = newlabel("while")
      lb = newlabel("wbody")
      lx = newlabel("wend")
      br(lh)
      label(lh)
      c = truthy(gx(n.a, sc))
      condbr(c, lb, lx)
      label(lb)
      @loops.push(JsAotLoop.new(labels, lx, lh))
      gs(n.b, sc, nil)
      @loops.pop
      tick()
      br(lh)
      label(lx)
    when :do_while
      lb = newlabel("dbody")
      lc = newlabel("dcond")
      lx = newlabel("dend")
      br(lb)
      label(lb)
      @loops.push(JsAotLoop.new(labels, lx, lc))
      gs(n.a, sc, nil)
      @loops.pop
      br(lc)
      label(lc)
      tick()
      c = truthy(gx(n.b, sc))
      condbr(c, lb, lx)
      label(lx)
    when :for
      g_for(n, sc, labels)
    when :return
      v = n.a == nil ? "0" : gx(n.a, sc)
      emit("ret i64 " + v)
      dead()
    when :break
      t = loop_target(n.str, false)
      br(t.brk)
      dead()
    when :continue
      t = loop_target(n.str, true)
      br(t.cont)
      dead()
    when :throw
      v = gx(n.a, sc)
      hthrow(H_THROW, [v])
    when :labeled
      ls = labels == nil ? [n.str] : labels + [n.str]
      b = n.a
      if b.kind == :while || b.kind == :do_while || b.kind == :for || b.kind == :labeled
        gs(b, sc, ls)
      else
        lx = newlabel("lend")
        @loops.push(JsAotLoop.new(ls, lx, nil))
        gs(b, sc, nil)
        @loops.pop
        br(lx)
        label(lx)
    else
      unsupported("statement " + k.to_s)
    nil

  -> loop_target(lbl, cont)
    i = @loops.size - 1
    while i >= 0
      l = @loops[i]
      if lbl == nil
        return l if l.cont != nil
      elsif l.labels != nil && l.labels.include?(lbl)
        unsupported("continue to a non-loop label") if cont && l.cont == nil
        return l
      i -= 1
    unsupported("jump target")

  -> tick
    a = tmp()
    emit(a + " = load i64, ptr %tick")
    b = tmp()
    emit(b + " = add i64 " + a + ", 1")
    emit("store i64 " + b + ", ptr %tick")
    c = tmp()
    emit(c + " = and i64 " + b + ", 65535")
    z = tmp()
    emit(z + " = icmp eq i64 " + c + ", 0")
    lt = newlabel("tick")
    lj = newlabel("tickj")
    condbr(z, lt, lj)
    label(lt)
    hcall(H_TICK, [])
    br(lj)
    label(lj)

  -> g_var_decl(n, sc)
    n.list.each ->(d)
      unsupported("destructuring") if d.a.kind != :ident
      if d.b != nil
        unsupported("named function value") if (d.b.kind == :class) && d.b.str == nil
        v = gx(d.b, sc)
        set_ident(d.a.str, sc, :init, v)
      elsif n.str != "var"
        set_ident(d.a.str, sc, :init, "0")
    nil

  -> g_block(bn, sc)
    stmts = bn.list
    needs = false
    stmts.each ->(s)
      unsupported("declaration in block") if s.kind == :function_decl || s.kind == :class_decl
      needs = true if s.kind == :var_decl && s.str != "var"
    if !needs
      stmts.each ->(s) gs(s, sc, nil)
      return nil
    if @env_mode
      bs = @map[bn]
      unsupported("block scope") if bs == nil || !bs.is_a?(JsScope)
      if bs.frame == bs
        e2 = hcall(H_NEWFRAME, [num_bits(bs.size + ~0.0), frame_val(sc.frame)])
        @frames.push([bs, e2])
        frame_tdz_fill(bs, bs.lex)
        stmts.each ->(s) gs(s, bs, nil)
        @frames.pop
      else
        frame_tdz_fill(bs.frame, bs.lex)
        stmts.each ->(s) gs(s, bs, nil)
      return nil
    bs = JsScope.new(:block, sc, false)
    @jc.lex_decls(stmts, sc.strict).each ->(d) bs.declare(d[0], d[1])
    tdz_fill(bs.lex)
    stmts.each ->(s) gs(s, bs, nil)
    nil

  -> g_for(n, sc, labels)
    init = n.a
    lexical = init != nil && init.kind == :var_decl && init.str != "var"
    ls = sc
    if lexical && @env_mode
      ls = @map[n]
      unsupported("for scope") if ls == nil || !ls.is_a?(JsScope)
      unsupported("per-iteration frame") if ls.frame == ls
      frame_tdz_fill(ls.frame, ls.lex)
    elsif lexical
      ls = JsScope.new(:block, sc, false)
      bound = []
      init.list.each ->(d) @jc.bound_names(d.a, bound)
      bound.each ->(nm) ls.declare(nm, init.str == "const" ? :const : :let)
      tdz_fill(ls.lex)
    if init != nil
      if init.kind == :var_decl
        g_var_decl(init, ls)
      else
        gx(init, ls)
    lh = newlabel("for")
    lb = newlabel("fbody")
    lu = newlabel("fupd")
    lx = newlabel("fend")
    br(lh)
    label(lh)
    if n.b != nil
      c = truthy(gx(n.b, ls))
      condbr(c, lb, lx)
    else
      br(lb)
    label(lb)
    @loops.push(JsAotLoop.new(labels, lx, lu))
    gs(n.d, ls, nil)
    @loops.pop
    br(lu)
    label(lu)
    tick()
    gx(n.c, ls) if n.c != nil
    br(lh)
    label(lx)
    nil

  # ---- identifiers ----

  # Frame `hops` levels out from scope sc's frame (alloca mode: 1 = the closure's scope).
  -> env_at_from(sc, hops)
    e = frame_val(sc.frame)
    h = 0
    while h < hops
      t = tmp()
      emit(t + " = call i64 @aget(i64 " + e + ", i64 0)")
      e = t
      h += 1
    e

  -> env_at(hops)
    e = "%scope"
    h = 1
    while h < hops
      t = tmp()
      emit(t + " = call i64 @aget(i64 " + e + ", i64 0)")
      e = t
      h += 1
    e

  -> tdz_check_local(v, name)
    z = tmp()
    emit(z + " = icmp eq i64 " + v + ", 3")
    lt = newlabel("tdz")
    lj = newlabel("tdzok")
    condbr(z, lt, lj)
    label(lt)
    hthrow(H_TDZ, [kload(name)])
    br(lj)
    label(lj)

  -> tdz_check_outer(v, name)
    tz = ktdz()
    z = tmp()
    emit(z + " = icmp eq i64 " + v + ", " + tz)
    lt = newlabel("tdz")
    lj = newlabel("tdzok")
    condbr(z, lt, lj)
    label(lt)
    hthrow(H_TDZ, [kload(name)])
    br(lj)
    label(lj)

  -> get_ident(name, sc)
    r = @jc.resolve(name, sc)
    unsupported("with") if r.withs != nil
    if r.kind == :slot && @env_mode
      e = env_at_from(sc, r.hops)
      v = tmp()
      emit(v + " = call i64 @aget(i64 " + e + ", i64 " + r.index.to_s + ")")
      tdz_check_outer(v, name) if r.binding.tdz
      return v
    if r.kind == :slot
      b = r.binding
      if r.hops == 0
        return "%f" if b.kind == :self
        v = tmp()
        emit(v + " = load i64, ptr " + slot_ptr(r.index))
        tdz_check_local(v, name) if b.tdz
        return v
      e = env_at(r.hops)
      v = tmp()
      emit(v + " = call i64 @aget(i64 " + e + ", i64 " + r.index.to_s + ")")
      tdz_check_outer(v, name) if b.tdz
      return v
    if r.kind == :cell
      return hcall(H_CELLGET, [kload(r.binding.cell), kload(name)])
    return hcall(H_GUNDEF, []) if name == "undefined"
    hcall(H_GGET, [kload(name)])

  -> set_ident(name, sc, mode, v)
    r = @jc.resolve(name, sc)
    unsupported("with") if r.withs != nil && mode != :init
    if r.kind == :slot
      b = r.binding
      if mode == :assign && b.kind == :self
        hthrow(H_CONSTERR, [kload(name)]) if @strict
        return v
      if r.hops == 0 && !@env_mode
        if mode == :assign && (b.is_const || b.tdz)
          cur = tmp()
          emit(cur + " = load i64, ptr " + slot_ptr(r.index))
          tdz_check_local(cur, name)
          if b.is_const
            hthrow(H_CONSTERR, [kload(name)])
            return v
        emit("store i64 " + v + ", ptr " + slot_ptr(r.index))
        return v
      e = @env_mode ? env_at_from(sc, r.hops) : env_at(r.hops)
      if mode == :assign && (b.is_const || b.tdz)
        cur = tmp()
        emit(cur + " = call i64 @aget(i64 " + e + ", i64 " + r.index.to_s + ")")
        tdz_check_outer(cur, name)
        if b.is_const
          hthrow(H_CONSTERR, [kload(name)])
          return v
      emit("call void @aset(i64 " + e + ", i64 " + r.index.to_s + ", i64 " + v + ")")
      return v
    if r.kind == :cell
      return hcall(mode == :init ? H_CELLINIT : H_CELLSET, [kload(r.binding.cell), v])
    unsupported("global var init") if mode == :init && r.binding != nil && r.binding.global
    hcall(@strict ? H_GSET_S : H_GSET, [kload(name), v])
    v

  -> g_this(sc)
    ts = @jc.this_scope(sc)
    unsupported("derived this") if ts.derived
    if @env_mode
      e = env_at_from(sc, @jc.hops_between(sc.frame, ts.frame))
      v = tmp()
      emit(v + " = call i64 @aget(i64 " + e + ", i64 " + FS_THIS.to_s + ")")
      return v
    return "%this" if ts == @fsc
    h = @jc.hops_between(sc.frame, ts.frame)
    unsupported("this hops") if h < 1
    e = env_at(h)
    v = tmp()
    emit(v + " = call i64 @aget(i64 " + e + ", i64 " + FS_THIS.to_s + ")")
    v

  # ---- expressions: return an i64 operand ----

  -> gx(n, sc)
    k = n.kind
    case k
    when :num
      num_bits(n.a)
    when :string
      kload(n.str)
    when :true
      "2"
    when :false
      "1"
    when :null
      knull()
    when :ident
      get_ident(n.str, sc)
    when :this
      g_this(sc)
    when :member
      g_member(n, sc)
    when :call
      g_call(n, sc)
    when :new
      g_new(n, sc)
    when :binary
      g_binary(n, sc)
    when :logical
      g_logical(n, sc)
    when :unary
      g_unary(n, sc)
    when :update
      g_update(n, sc)
    when :assign
      g_assign(n, sc)
    when :cond
      c = truthy(gx(n.a, sc))
      la = newlabel("ca")
      lb = newlabel("cb")
      lj = newlabel("cj")
      condbr(c, la, lb)
      label(la)
      a = gx(n.b, sc)
      ea = @cur
      br(lj)
      label(lb)
      b = gx(n.c, sc)
      eb = @cur
      br(lj)
      label(lj)
      phi2(a, ea, b, eb)
    when :seq
      v = "0"
      n.list.each ->(x) v = gx(x, sc)
      v
    when :array
      arr = hcall(H_TARR, [])
      n.list.each ->(x)
        unsupported("array hole or spread") if x == nil || x.kind == :spread
        hcall(H_TPUSH, [arr, gx(x, sc)])
      hcall(H_JSARR, [arr])
    when :object
      g_object(n, sc)
    when :regex
      hcall(H_REGEX, [kload(n.str), kload(n.a)])
    when :function, :arrow
      unsupported("closure outside frame mode") if !@env_mode
      c = @map[n]
      unsupported("inner function not compiled") if c == nil || !c.is_a?(JsCode)
      hcall(H_CLOSURE, [kload(c), frame_val(sc.frame)])
    else
      unsupported("expression " + k.to_s)

  -> g_object(n, sc)
    o = hcall(H_NEWOBJ, [])
    n.list.each ->(p)
      unsupported("object spread") if p.kind == :spread
      unsupported("object method") if p.has?(F_METHOD) || p.str != "init"
      unsupported("computed key") if p.has?(F_COMPUTED)
      nm = @jc.js_static_key(p.a)
      unsupported("key") if nm == nil || nm == "__proto__"
      vn = p.b
      vn = vn.a if p.has?(F_SHORTHAND) && vn.kind == :assign_pattern
      unsupported("anonymous class value") if vn.kind == :class && vn.str == nil
      hcall(H_LITPUT, [o, kload(nm), gx(vn, sc)])
    o

  -> g_member(n, sc)
    unsupported("super") if n.a.kind == :super
    unsupported("optional chain") if n.has?(F_OPTIONAL)
    unsupported("private name") if n.b.kind == :private_name
    o = gx(n.a, sc)
    if n.has?(F_COMPUTED)
      k = gx(n.b, sc)
      return hcall(H_GETIDX, [o, k])
    key = n.b.str
    return hcall(H_LEN, [o]) if key == "length"
    hcall(H_GETV, [o, kload(key)])

  -> plain_args(list)
    list.each ->(x) unsupported("spread argument") if x.kind == :spread
    nil

  # Arguments as a Tungsten Array (for calls with more than two).
  -> args_array(list, sc)
    arr = hcall(H_TARR, [])
    list.each ->(x) hcall(H_TPUSH, [arr, gx(x, sc)])
    arr

  -> g_call(n, sc)
    callee = n.a
    unsupported("optional call") if n.has?(F_OPTIONAL)
    plain_args(n.list)
    unsupported("super call") if callee.kind == :super
    nargs = n.list.size
    if callee.kind == :member
      unsupported("super method") if callee.a.kind == :super
      unsupported("optional member call") if callee.has?(F_OPTIONAL)
      unsupported("private method") if callee.b.kind == :private_name
      o = gx(callee.a, sc)
      if callee.has?(F_COMPUTED)
        key = hcall(H_TOKEY, [gx(callee.b, sc)])
        f = hcall(H_GETVX, [o, key])
        arr = args_array(n.list, sc)
        return hcall(H_CALLTA, [f, o, arr])
      # EvaluateCall: the method is fetched before the arguments are evaluated (§13.3.6.1)
      k = kload(callee.b.str)
      f = hcall(H_GETVX, [o, k])
      return hcall(H_CALLF, [f, o, k, args_array(n.list, sc)])
    unsupported("eval") if callee.kind == :ident && callee.str == "eval"
    unsupported("chain call") if callee.kind == :chain
    f = gx(callee, sc)
    what = kload(callee.kind == :ident ? callee.str : "expression")
    if nargs == 0
      return hcall(H_CALL0, [f, what])
    if nargs == 1
      a = gx(n.list[0], sc)
      return hcall(H_CALL1, [f, what, a])
    if nargs == 2
      a = gx(n.list[0], sc)
      b = gx(n.list[1], sc)
      return hcall(H_CALL2, [f, what, a, b])
    hcall(H_CALLA, [f, what, args_array(n.list, sc)])

  -> g_new(n, sc)
    plain_args(n.list)
    f = gx(n.a, sc)
    a = n.a
    w = a.kind == :ident ? a.str : (a.kind == :member && !a.has?(F_COMPUTED) && a.b.kind == :ident ? a.b.str : "expression")
    hcall(H_NEWA, [f, kload(w), args_array(n.list, sc)])

  # Both operands doubles? → i1
  -> both_d(a, b)
    da = tmp()
    emit(da + " = call i1 @isd(i64 " + a + ")")
    db = tmp()
    emit(db + " = call i1 @isd(i64 " + b + ")")
    t = tmp()
    emit(t + " = and i1 " + da + ", " + db)
    t

  -> unb(v)
    t = tmp()
    emit(t + " = call double @unb(i64 " + v + ")")
    t

  -> box(d)
    t = tmp()
    emit(t + " = call i64 @box(double " + d + ")")
    t

  # fast: ->(da, db) operand string; slow helper h.
  -> num_binop(a, b, h, fop, cmp)
    c = both_d(a, b)
    lf = newlabel("nf")
    ls = newlabel("ns")
    lj = newlabel("nj")
    condbr(c, lf, ls)
    label(lf)
    x = unb(a)
    y = unb(b)
    r1 = nil
    if cmp
      ci = tmp()
      emit(ci + " = fcmp " + fop + " double " + x + ", " + y)
      r1 = bool_of(ci)
    else
      dv = tmp()
      emit(dv + " = " + fop + " double " + x + ", " + y)
      r1 = box(dv)
    ef = @cur
    br(lj)
    label(ls)
    r2 = hcall(h, [a, b])
    es = @cur
    br(lj)
    label(lj)
    phi2(r1, ef, r2, es)

  # Int32 bit operation with a double fast path (|x| < 9e15, so fptosi is exact mod 2^32).
  -> int_binop(a, b, h, iop)
    c = both_d(a, b)
    lf = newlabel("if")
    lg = newlabel("ig")
    ls = newlabel("is")
    lj = newlabel("ij")
    condbr(c, lf, ls)
    label(lf)
    fx = unb(a)
    fy = unb(b)
    ax = tmp()
    emit(ax + " = call double @llvm.fabs.f64(double " + fx + ")")
    ay = tmp()
    emit(ay + " = call double @llvm.fabs.f64(double " + fy + ")")
    o1 = tmp()
    emit(o1 + " = fcmp olt double " + ax + ", 9.0e15")
    o2 = tmp()
    emit(o2 + " = fcmp olt double " + ay + ", 9.0e15")
    ok = tmp()
    emit(ok + " = and i1 " + o1 + ", " + o2)
    condbr(ok, lg, ls)
    label(lg)
    xi = tmp()
    emit(xi + " = fptosi double " + fx + " to i64")
    xt = tmp()
    emit(xt + " = trunc i64 " + xi + " to i32")
    x = tmp()
    emit(x + " = sext i32 " + xt + " to i64")
    yi = tmp()
    emit(yi + " = fptosi double " + fy + " to i64")
    yt = tmp()
    emit(yt + " = trunc i64 " + yi + " to i32")
    y = tmp()
    emit(y + " = sext i32 " + yt + " to i64")
    r = tmp()
    d = tmp()
    if iop == "shl" || iop == "ashr" || iop == "lshr"
      sh = tmp()
      emit(sh + " = and i64 " + y + ", 31")
      if iop == "lshr"
        u = tmp()
        emit(u + " = and i64 " + x + ", 4294967295")
        emit(r + " = lshr i64 " + u + ", " + sh)
        emit(d + " = uitofp i64 " + r + " to double")
      elsif iop == "shl"
        r0 = tmp()
        emit(r0 + " = shl i64 " + x + ", " + sh)
        r1 = tmp()
        emit(r1 + " = trunc i64 " + r0 + " to i32")
        emit(r + " = sext i32 " + r1 + " to i64")
        emit(d + " = sitofp i64 " + r + " to double")
      else
        emit(r + " = ashr i64 " + x + ", " + sh)
        emit(d + " = sitofp i64 " + r + " to double")
    else
      emit(r + " = " + iop + " i64 " + x + ", " + y)
      emit(d + " = sitofp i64 " + r + " to double")
    r1b = box(d)
    eg = @cur
    br(lj)
    label(ls)
    r2 = hcall(h, [a, b])
    es = @cur
    br(lj)
    label(lj)
    phi2(r1b, eg, r2, es)

  -> g_binary(n, sc)
    op = n.str
    unsupported("private in") if n.a.kind == :private_name
    a = gx(n.a, sc)
    b = gx(n.b, sc)
    binop(op, a, b)

  -> binop(op, a, b)
    case op
    when "+"
      num_binop(a, b, H_ADD, "fadd", false)
    when "-"
      num_binop(a, b, H_SUB, "fsub", false)
    when "*"
      num_binop(a, b, H_MUL, "fmul", false)
    when "/"
      num_binop(a, b, H_DIV, "fdiv", false)
    when "%"
      hcall(H_MOD, [a, b])
    when "**"
      hcall(H_POW, [a, b])
    when "<"
      num_binop(a, b, H_LT, "olt", true)
    when ">"
      num_binop(a, b, H_GT, "ogt", true)
    when "<="
      num_binop(a, b, H_LE, "ole", true)
    when ">="
      num_binop(a, b, H_GE, "oge", true)
    when "==="
      g_seq(a, b, false)
    when "!=="
      g_seq(a, b, true)
    when "=="
      hcall(H_LEQ, [a, b])
    when "!="
      r = hcall(H_LEQ, [a, b])
      t = tmp()
      emit(t + " = sub i64 3, " + r)
      t
    when "&"
      int_binop(a, b, H_BAND, "and")
    when "|"
      int_binop(a, b, H_BOR, "or")
    when "^"
      int_binop(a, b, H_BXOR, "xor")
    when "<<"
      int_binop(a, b, H_SHL, "shl")
    when ">>"
      int_binop(a, b, H_SAR, "ashr")
    when ">>>"
      int_binop(a, b, H_SHR, "lshr")
    when "instanceof"
      hcall(H_INSTOF, [a, b])
    when "in"
      hcall(H_IN, [a, b])
    else
      unsupported("operator " + op)

  # Strict equality: doubles compare as doubles; identical bits of non-doubles are equal;
  # a double against a non-double is unequal; anything else (strings…) asks the helper.
  -> g_seq(a, b, negate)
    da = tmp()
    emit(da + " = call i1 @isd(i64 " + a + ")")
    db = tmp()
    emit(db + " = call i1 @isd(i64 " + b + ")")
    both = tmp()
    emit(both + " = and i1 " + da + ", " + db)
    lf = newlabel("qd")
    l2 = newlabel("qn")
    l3 = newlabel("qm")
    ls = newlabel("qs")
    lj = newlabel("qj")
    condbr(both, lf, l2)
    label(lf)
    ci = tmp()
    emit(ci + " = fcmp oeq double " + unb(a) + ", " + unb(b))
    r1 = bool_of(ci)
    br(lj)
    label(l2)
    eq = tmp()
    emit(eq + " = icmp eq i64 " + a + ", " + b)
    r2 = "2"
    either = tmp()
    emit(either + " = or i1 " + da + ", " + db)
    condbr(eq, lj, l3)
    label(l3)
    condbr(either, lj, ls)
    label(ls)
    r4 = hcall(H_SEQ, [a, b])
    es = @cur
    br(lj)
    label(lj)
    t = tmp()
    emit(t + " = phi i64 \[ " + r1 + ", %" + lf + " ], \[ 2, %" + l2 + " ], \[ 1, %" + l3 + " ], \[ " + r4 + ", %" + es + " ]")
    return t if !negate
    u = tmp()
    emit(u + " = sub i64 3, " + t)
    u

  -> g_logical(n, sc)
    op = n.str
    a = gx(n.a, sc)
    la = @cur
    lr = newlabel("lr")
    lj = newlabel("lj")
    c = nil
    if op == "??"
      nl = knull()
      z1 = tmp()
      emit(z1 + " = icmp eq i64 " + a + ", 0")
      z2 = tmp()
      emit(z2 + " = icmp eq i64 " + a + ", " + nl)
      c = tmp()
      emit(c + " = or i1 " + z1 + ", " + z2)
      la = @cur
      condbr(c, lr, lj)
    else
      c = truthy(a)
      la = @cur
      if op == "&&"
        condbr(c, lr, lj)
      else
        condbr(c, lj, lr)
    label(lr)
    b = gx(n.b, sc)
    eb = @cur
    br(lj)
    label(lj)
    phi2(a, la, b, eb)

  -> g_unary(n, sc)
    op = n.str
    a = n.a
    if op == "typeof" && a.kind == :ident
      r = @jc.resolve(a.str, sc)
      unsupported("with") if r.withs != nil
      return hcall(H_GTYPEOF, [kload(a.str)]) if r.kind == :global
    unsupported("delete") if op == "delete"
    v = gx(a, sc)
    case op
    when "!"
      c = truthy(v)
      t = tmp()
      emit(t + " = select i1 " + c + ", i64 1, i64 2")
      t
    when "-"
      d = tmp()
      emit(d + " = call i1 @isd(i64 " + v + ")")
      lf = newlabel("ngf")
      ls = newlabel("ngs")
      lj = newlabel("ngj")
      condbr(d, lf, ls)
      label(lf)
      x = tmp()
      emit(x + " = fneg double " + unb(v))
      r1 = box(x)
      ef = @cur
      br(lj)
      label(ls)
      r2 = hcall(H_NEG, [v])
      es = @cur
      br(lj)
      label(lj)
      phi2(r1, ef, r2, es)
    when "+"
      d = tmp()
      emit(d + " = call i1 @isd(i64 " + v + ")")
      lf = newlabel("pf")
      ls = newlabel("ps")
      lj = newlabel("pj")
      ef = @cur
      condbr(d, lj, ls)
      label(ls)
      r2 = hcall(H_TONUM, [v])
      es = @cur
      br(lj)
      label(lj)
      phi2(v, ef, r2, es)
    when "~"
      hcall(H_BITNOT, [v])
    when "typeof"
      hcall(H_TYPEOF, [v])
    when "void"
      "0"
    else
      unsupported("unary " + op)

  # x + d (d = ±1) with a double fast path; returns [old numeric, new].
  -> inc_value(v, d)
    dd = tmp()
    emit(dd + " = call i1 @isd(i64 " + v + ")")
    lf = newlabel("uf")
    ls = newlabel("us")
    lj = newlabel("uj")
    condbr(dd, lf, ls)
    label(lf)
    x = tmp()
    emit(x + " = fadd double " + unb(v) + ", " + (d > ~0.0 ? "1.0" : "-1.0"))
    n1 = box(x)
    ef = @cur
    br(lj)
    label(ls)
    o2 = hcall(H_NUMVAL, [v])
    n2 = hcall(H_INC, [o2, num_bits(d)])
    es = @cur
    br(lj)
    label(lj)
    old = phi2(v, ef, o2, es)
    nv = phi2(n1, ef, n2, es)
    [old, nv]

  -> g_update(n, sc)
    t = n.a
    prefix = n.has?(F_PREFIX)
    d = n.str == "++" ? ~1.0 : ~-1.0
    if t.kind == :ident
      v = get_ident(t.str, sc)
      on = inc_value(v, d)
      set_ident(t.str, sc, :assign, on[1])
      return prefix ? on[1] : on[0]
    if t.kind == :member
      unsupported("super update") if t.a.kind == :super
      unsupported("private update") if t.b.kind == :private_name
      o = gx(t.a, sc)
      k = t.has?(F_COMPUTED) ? hcall(H_TOKEY, [gx(t.b, sc)]) : kload(t.b.str)
      return hcall(@strict ? H_UPDMEM_S : H_UPDMEM, [o, k, num_bits(d), prefix ? "2" : "1"])
    unsupported("update target")

  -> nullish_set_check(o, k)
    nl = knull()
    z1 = tmp()
    emit(z1 + " = icmp eq i64 " + o + ", 0")
    z2 = tmp()
    emit(z2 + " = icmp eq i64 " + o + ", " + nl)
    c = tmp()
    emit(c + " = or i1 " + z1 + ", " + z2)
    lt = newlabel("nul")
    lj = newlabel("nulok")
    condbr(c, lt, lj)
    label(lt)
    hthrow(H_NULLSET, [o, k])
    br(lj)
    label(lj)

  -> g_assign(n, sc)
    op = n.str
    t = n.a
    if op == "="
      if t.kind == :ident
        unsupported("anonymous class value") if n.b.kind == :class && n.b.str == nil
        v = gx(n.b, sc)
        return set_ident(t.str, sc, :assign, v)
      if t.kind == :member
        unsupported("super set") if t.a.kind == :super
        unsupported("private set") if t.b.kind == :private_name
        o = gx(t.a, sc)
        if t.has?(F_COMPUTED)
          key = hcall(H_PRESET, [o, gx(t.b, sc)])
          v = gx(n.b, sc)
          hcall(@strict ? H_SETIDX_S : H_SETIDX, [o, key, v])
          return v
        k = kload(t.b.str)
        nullish_set_check(o, k)
        v = gx(n.b, sc)
        hcall(@strict ? H_SETV_S : H_SETV, [o, k, v])
        return v
      unsupported("destructuring assignment")
    if op == "&&=" || op == "||=" || op == "??="
      unsupported("logical assignment to member") if t.kind != :ident
      cur = get_ident(t.str, sc)
      la = @cur
      lr = newlabel("lar")
      lj = newlabel("laj")
      if op == "??="
        nl = knull()
        z1 = tmp()
        emit(z1 + " = icmp eq i64 " + cur + ", 0")
        z2 = tmp()
        emit(z2 + " = icmp eq i64 " + cur + ", " + nl)
        c = tmp()
        emit(c + " = or i1 " + z1 + ", " + z2)
        la = @cur
        condbr(c, lr, lj)
      else
        c = truthy(cur)
        la = @cur
        if op == "&&="
          condbr(c, lr, lj)
        else
          condbr(c, lj, lr)
      label(lr)
      v = gx(n.b, sc)
      set_ident(t.str, sc, :assign, v)
      er = @cur
      br(lj)
      label(lj)
      return phi2(cur, la, v, er)
    bop = op.slice(0, op.size - 1)
    if t.kind == :ident
      g = get_ident(t.str, sc)
      v = gx(n.b, sc)
      r = binop(bop, g, v)
      return set_ident(t.str, sc, :assign, r)
    if t.kind == :member
      unsupported("super compound") if t.a.kind == :super
      unsupported("private compound") if t.b.kind == :private_name
      o = gx(t.a, sc)
      k = t.has?(F_COMPUTED) ? hcall(H_TOKEY, [gx(t.b, sc)]) : kload(t.b.str)
      old = hcall(H_GETVX, [o, k])
      v = gx(n.b, sc)
      r = binop(bop, old, v)
      hcall(@strict ? H_SETV_S : H_SETV, [o, k, r])
      return r
    unsupported("assignment target")
