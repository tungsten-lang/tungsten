# blade/js/gc — a precise mark-sweep collector for the JavaScript heap.
#
# The Tungsten runtime never reclaims the engine's values, so without this every object,
# closure and frame a page creates stays allocated. The collector frees only what it can
# prove unreachable:
#
# What it frees (the registry, JS_GC_HEAP): allocations made by running JavaScript —
#   object and array literals, closures, instances made by `new`, arguments objects, and
#   frames that outlive their call (js_activation / block and loop frames). Objects that
#   builtins and host code create are never freed (they may be referenced from places the
#   collector cannot see).
#
# Reachability: a mark phase from the roots through everything, not just JS objects —
#   Arrays, Hashes and any Tungsten instance (its ivars, read with w_ivar_get_idx), so DOM
#   nodes, timers, observers, media objects and other modules' structures are followed.
#   The one thing it cannot look into is a Tungsten lambda's captures. So:
#   - lambdas the engine and DOM bindings store (promise reactions and resolving
#     functions, timers, network callbacks, observers, ...) record what they capture in a
#     traceable `keep` list (js_keep / JsReaction.keep / pending-network entries);
#   - natives created by other modules (anything not installed by the engine or the DOM
#     bindings) are untrusted: calling one pins its `this` and arguments for good, and
#     nothing allocated while it runs is registered;
#   - a coroutine (generator / async function) may hold values in its suspended goroutine
#     stack, which cannot be scanned: everything it allocates or is resumed with is pinned
#     to it until it finishes, and every live coroutine is a root.
#
# Roots: every realm (and its global object, intrinsics and caches), the page runtimes
#   (js_gc_add_root: timers, frames, wrappers, pending requests, the page and its DOM),
#   live coroutines, pinned values, the engine's thread-local registers, and module tables
#   registered with js_gc_add_root.
#
# Safepoints (no native frame holds an unrooted JavaScript value): between tasks with the
#   microtask queue empty (the page runtime's run_timers / settle), and at loop back-edges
#   of top-level code (call depth 0, outside eval) with the loop's frame and iterator as
#   extra roots. Deeper back-edges are not safepoints: a caller's half-evaluated
#   expression lives in native locals.
#
# Off unless BLADE_JS_GC=1 (being validated); BLADE_JS_GC_LOG=1 prints one line per collection.

JS_GC_ON = [Env.get("BLADE_JS_GC", "") == "1"]
JS_GC_LOG = [Env.get("BLADE_JS_GC_LOG", "") == "1"]
JS_GC_HEAP = []
JS_GC_ROOTS = []
JS_GC_REALMS = []
JS_GC_REALM_SET = {}
JS_GC_HOST_CLASSES = {}
JS_GC_PINS = []
JS_GC_COROS = {}
# allocations since the last collection that trigger the next one
# (BLADE_JS_GC_EVERY=n collects every n allocations: tests)
JS_GC_BASE = [Env.get("BLADE_JS_GC_EVERY", "").size > 0 ? Env.get("BLADE_JS_GC_EVERY", "").to_i : 200000]
JS_GC_NEXT = [JS_GC_BASE[0]]
# > 0 while an untrusted native runs (its allocations are not registered)
JS_GC_UNTRUSTED = [0]
# > 0 while any native function runs (no safepoints beneath a native frame)
JS_GC_NATIVE = [0]
# true while the innermost native is an engine builtin: realm.new_array/new_object register
JS_GC_IN_ENGINE = [false]
# true while the engine and the DOM bindings install their natives (those are trusted)
JS_GC_TRUST = [false]
# > 0 inside eval code (a top-level eval's loop is not a safepoint)
JS_GC_EVAL = [0]
# scripts being run (js_run_script); back-edges are safepoints only in the outermost
JS_GC_SCRIPTS = [0]
# collections, objects freed in total, last mark+sweep ms, live after last collection
JS_GC_STATS = [0, 0, 0, 0]
JS_GC_DBG = {}
JS_GC_IVARS = {}
# BLADE_JS_GC_VERIFY=1: swept objects are only recorded; a later mark that reaches one
# reports it (a missing root) instead of freeing
JS_GC_VERIFY = [Env.get("BLADE_JS_GC_VERIFY", "") == "1"]
JS_GC_DEAD = {}
# the runtime's names for builtin types (w_class_name); anything else is a class instance
JS_GC_VALUE_TYPES = {}
["Array", "BigDecimal", "BigInt", "Boolean", "Char", "Class", "Color", "Complex", "Currency", "Date", "Decimal", "Duration", "Float", "Hash", "Instant", "Int", "IPv4", "IPv6", "MAC", "Mmap", "Nil", "Point2D", "Quantity", "Range", "Rational", "SockAddr", "Socket", "String", "StringBuffer", "Symbol", "Unknown", "UUID", "Vec2f", "Vec2i", "Vec3f"].each ->(t) JS_GC_VALUE_TYPES[t] = true
JS_GC_SENTINEL = ["gc-probe"]

# Only the main OS thread's allocations are registered and collected (workers keep theirs).
-> js_gc_main_thread?
  js_tp() == JS_TLS_MAIN[0]

# Register an allocation made by JavaScript code as collectable.
-> js_gc_reg(v)
  return v if !JS_GC_ON[0]
  if JS_GC_UNTRUSTED[0] > 0 || js_tp() != JS_TLS_MAIN[0]
    JS_GC_DBG["unregistered"] = (JS_GC_DBG["unregistered"] || 0) + 1 if JS_GC_LOG[0]
    return v
  JS_GC_HEAP.push(v)
  c = JS_CUR_CORO[0]
  if c != nil
    c.pins = [] if c.pins == nil
    c.pins.push(v)
  v

-> js_gc_add_root(v)
  JS_GC_ROOTS.push(v)
  nil

-> js_gc_add_realm(r)
  JS_GC_REALMS.push(r)
  JS_GC_REALM_SET[r] = true
  nil

# Host classes whose instances may hold JavaScript values (traced like Js* classes).
-> js_gc_host_class(name)
  JS_GC_HOST_CLASSES[name] = true
  nil

-> js_gc_pin(v)
  JS_GC_PINS.push(v) if v != nil && !js_gc_atomic?(v)
  nil

# A stored lambda's captured values, kept reachable through the function.
-> js_keep(f, vals)
  f.keep = vals
  f.gc_trusted = true
  f

# Values that cannot hold references (never traced).
-> js_gc_atomic?(v)
  v == nil || v == true || v == false || v.is_a?(Float) || v.is_a?(String) || v.is_a?(Symbol)

# ---- triggering ----

# Safepoint of the event loop: between tasks, nothing on the native stack.
JS_GC_SKIPS = [0]

-> js_gc_idle(extra)
  return nil if !JS_GC_ON[0]
  if JS_GC_LOG[0]
    JS_GC_DBG["idles"] = (JS_GC_DBG["idles"] || 0) + 1
    ccall("w_eputs", "\[js gc] idle heap " + JS_GC_HEAP.size.to_s + " unregistered " + (JS_GC_DBG["unregistered"] || 0).to_s) if (JS_GC_DBG["idles"] & 255) == 1
  return nil if JS_GC_HEAP.size < JS_GC_NEXT[0]
  r = JS_REALM[0]
  if JS_DEPTH[0] != 0 || JS_GC_SCRIPTS[0] != 0 || JS_GC_NATIVE[0] > 0 || JS_CUR_CORO[0] != nil || (r != nil && r.jobs.size > 0)
    JS_GC_SKIPS[0] += 1
    if JS_GC_LOG[0] && (JS_GC_SKIPS[0] & 63) == 1
      ccall("w_eputs", "\[js gc] idle skipped: depth " + JS_DEPTH[0].to_s + " scripts " + JS_GC_SCRIPTS[0].to_s + " natives " + JS_GC_NATIVE[0].to_s + " coro " + (JS_CUR_CORO[0] != nil).to_s + " jobs " + (r == nil ? 0 : r.jobs.size).to_s + " heap " + JS_GC_HEAP.size.to_s)
    return nil
  js_gc_collect(extra)

# Safepoint at a loop back-edge: only in top-level code (depth 0), outside eval, with an
# empty job queue (queued jobs are lambdas whose captures cannot be traced).
-> js_gc_backedge(env, x1, x2)
  return nil if JS_GC_HEAP.size < JS_GC_NEXT[0] || !JS_GC_ON[0]
  return nil if JS_DEPTH[0] != 0 || JS_GC_SCRIPTS[0] != 1 || JS_GC_EVAL[0] > 0 || JS_GC_NATIVE[0] > 0 || JS_CUR_CORO[0] != nil
  r = JS_REALM[0]
  return nil if r == nil || r.jobs.size > 0
  js_gc_collect([env, x1, x2])

# ---- mark ----

-> js_gc_collect(extra)
  return nil if !js_gc_main_thread?
  t0 = clock_ms()
  marks = {}
  stack = []
  js_gc_push_roots(stack, extra)
  if JS_GC_VERIFY[0]
    js_gc_verify_mark(stack, marks)
  else
    while stack.size > 0
      v = stack.pop
      js_gc_trace(v, marks, stack) if !marks.has_key?(v)
  marks_n = marks.size
  # ---- sweep ----
  live = []
  freed = 0
  hn = JS_GC_HEAP.size
  hi = 0
  while hi < hn
    v = JS_GC_HEAP[hi]
    hi += 1
    if marks.has_key?(v)
      live.push(v)
    else
      if JS_GC_VERIFY[0]
        JS_GC_DEAD[v] = true
      else
        js_gc_free(v)
      freed += 1
  live_n = live.size
  js_gc_replace_heap(live)   # (frees the list)
  ccall("w_value_free_w", marks)
  ccall("w_value_free_w", stack)
  JS_GC_STATS[0] += 1
  JS_GC_STATS[1] += freed
  JS_GC_STATS[2] = clock_ms() - t0
  JS_GC_STATS[3] = live_n
  # next collection after as many new allocations as survived (at least the base)
  JS_GC_NEXT[0] = live_n + (live_n > JS_GC_BASE[0] ? live_n : JS_GC_BASE[0])
  ccall("w_eputs", "\[js gc] freed " + freed.to_s + " live " + live_n.to_s + " marked " + marks_n.to_s + " in " + JS_GC_STATS[2].to_s + " ms") if JS_GC_LOG[0]
  nil

-> js_gc_replace_heap(live)
  # JS_GC_HEAP is a constant array: refill it in place
  while JS_GC_HEAP.size > 0
    JS_GC_HEAP.pop
  live.each ->(v) JS_GC_HEAP.push(v)
  ccall("w_value_free_w", live)
  nil

-> js_gc_push_roots(stack, extra)
  extra.each(->(v) stack.push(v) if v != nil) if extra != nil
  JS_GC_REALMS.each ->(r) stack.push(r)
  JS_GC_ROOTS.each ->(r) stack.push(r)
  JS_GC_PINS.each ->(r) stack.push(r)
  JS_GC_PIN_SET.keys.each ->(r) stack.push(r)
  JS_GC_COROS.keys.each ->(c) stack.push(c)
  # engine registers and tables
  stack.push(JS_RETVAL)
  stack.push(JS_LAST_ENV)
  stack.push(JS_CUR_CORO)
  stack.push(JS_UNHANDLED)
  stack.push(JS_MODULES)
  stack.push(JS_NO_ARGS)
  stack.push(JS_REALM)
  nil

-> js_gc_trace(v, marks, stack)
  return nil if js_gc_atomic?(v)
  marks[v] = true
  if v.is_a?(Array)
    i = 0
    n = v.size
    while i < n
      x = v[i]
      stack.push(x) if x != nil && !js_gc_atomic?(x) && !marks.has_key?(x)
      i += 1
    return nil
  if v.is_a?(Hash)
    v.each ->(k, x)
      stack.push(k) if !js_gc_atomic?(k) && !marks.has_key?(k)
      stack.push(x) if !js_gc_atomic?(x) && !marks.has_key?(x)
    return nil
  cn = ccall("w_class_name", v)
  if cn == "SmallArray" || cn == "BigArray"
    v.each ->(x) stack.push(x) if x != nil && !js_gc_atomic?(x) && !marks.has_key?(x)
    return nil
  # builtin value types (lambdas are "Unknown"): nothing traceable inside
  return nil if JS_GC_VALUE_TYPES.has_key?(cn)
  # Only classes that can hold JavaScript values are followed: the engine's and the
  # bindings' Js* classes and the registered host classes. Others (the page, network,
  # media pipelines, ...) may be mutated by their own threads while we trace.
  return nil if !(cn.starts_with?("Js") || JS_GC_HOST_CLASSES.has_key?(cn))
  # a worker's realm belongs to its thread
  return nil if cn == "JsRealm" && !JS_GC_REALM_SET.has_key?(v)
  n = js_gc_ivar_count(v, cn)
  i = 0
  while i < n
    x = ccall("w_ivar_get_idx", v, (i ## int))
    stack.push(x) if x != nil && !js_gc_atomic?(x) && !marks.has_key?(x)
    i += 1
  nil

# Instances of a class all have its ivar count; found once per class by writing a
# sentinel past the known fields (w_ivar_set_idx answers nil out of range) and restoring.
-> js_gc_ivar_count(v, cn)
  n = JS_GC_IVARS[cn]
  return n if n != nil
  k = 0
  while k < 256
    old = ccall("w_ivar_get_idx", v, (k ## int))
    r = ccall("w_ivar_set_idx", v, (k ## int), JS_GC_SENTINEL)
    break if r != JS_GC_SENTINEL
    ccall("w_ivar_set_idx", v, (k ## int), old)
    k += 1
  JS_GC_IVARS[cn] = k
  k

# ---- sweep ----

# Release one registered allocation: the object's own tables, then the object.
-> js_gc_free(v)
  if v.is_a?(Array)
    ccall("w_value_free_w", v)
    return nil
  if v.is_a?(JsObject)
    js_gc_free_part(v.props)
    js_gc_free_part(v.attrs)
    js_gc_free_part(v.getters)
    js_gc_free_part(v.setters)
    js_gc_free_part(v.seq)
    js_gc_free_part(v.priv)
    js_gc_free_part(v.priv_handlers)
    js_gc_free_part(v.elems) if v.is_a?(JsArray)
    ccall("w_value_free_w", v)
    return nil
  # other engine records (reactions, capabilities)
  ccall("w_value_free_w", v)
  nil

-> js_gc_free_part(t)
  ccall("w_value_free_w", t) if t != nil && (t.is_a?(Hash) || t.is_a?(Array))
  nil

# ---- coroutines ----

-> js_gc_coro_start(c)
  JS_GC_COROS[c] = true if JS_GC_ON[0]
  nil

-> js_gc_coro_done(c)
  if JS_GC_COROS.has_key?(c)
    JS_GC_COROS.delete(c)
  c.pins = nil
  nil

-> js_gc_coro_resumed(c, v)
  return nil if !JS_GC_ON[0] || js_gc_atomic?(v)
  c.pins = [] if c.pins == nil
  c.pins.push(v)
  nil

# ---- natives ----

# Call a native: one created by another module (untrusted) may keep its this/arguments
# where the collector cannot see (in a lambda), so they are pinned; what it allocates
# while it runs is not registered.
-> js_native_call(f, this, args, nt)
  return f.native.call(this, args, nt) if !JS_GC_ON[0]
  if f.gc_trusted
    # no collection while any native frame is on the stack (it may hold values)
    JS_GC_NATIVE[0] += 1
    ie = JS_GC_IN_ENGINE[0]
    JS_GC_IN_ENGINE[0] = f.gc_trusted == 2
    r0 = nil
    begin
      r0 = f.native.call(this, args, nt)
    rescue e0
      JS_GC_NATIVE[0] -= 1
      JS_GC_IN_ENGINE[0] = ie
      raise e0
    JS_GC_NATIVE[0] -= 1
    JS_GC_IN_ENGINE[0] = ie
    return r0
  js_gc_pin_once(this)
  args.each ->(a) js_gc_pin_once(a)
  JS_GC_UNTRUSTED[0] += 1
  JS_GC_NATIVE[0] += 1
  r = nil
  begin
    r = f.native.call(this, args, nt)
  rescue e
    JS_GC_UNTRUSTED[0] -= 1
    JS_GC_NATIVE[0] -= 1
    raise e
  JS_GC_UNTRUSTED[0] -= 1
  JS_GC_NATIVE[0] -= 1
  r

JS_GC_PIN_SET = {}

-> js_gc_pin_once(v)
  return nil if js_gc_atomic?(v) || !v.is_a?(JsObject) || JS_GC_PIN_SET.has_key?(v)
  JS_GC_PIN_SET[v] = true
  nil

# Eval code runs inside an expression of its caller: its loops are not safepoints.
-> js_gc_eval_run(run, env)
  JS_GC_EVAL[0] += 1
  r = nil
  begin
    r = run.call(env)
  rescue e
    JS_GC_EVAL[0] -= 1
    raise e
  JS_GC_EVAL[0] -= 1
  r

# Verify mode: mark with parent tracking; report dead objects reached again.
-> js_gc_verify_mark(stack, marks)
  parent = {}
  reported = [0]
  while stack.size > 0
    v = stack.pop
    if !marks.has_key?(v)
      if JS_GC_DEAD.has_key?(v) && reported[0] < 20
        reported[0] += 1
        ccall("w_eputs", "\[js gc verify] swept object reachable: " + js_gc_describe(v) + " path: " + js_gc_path(v, parent))
      before = stack.size
      js_gc_trace(v, marks, stack)
      i = before
      while i < stack.size
        parent[stack[i]] = v if !parent.has_key?(stack[i])
        i += 1
  nil

-> js_gc_describe(v)
  return "Array(" + v.size.to_s + ")" if v.is_a?(Array)
  return "Hash" if v.is_a?(Hash)
  cn = ccall("w_class_name", v).to_s
  return cn + "(" + v.cls.to_s + ")" if v.is_a?(JsObject)
  cn

-> js_gc_path(v, parent)
  out = []
  cur = v
  n = 0
  while parent.has_key?(cur) && n < 12
    cur = parent[cur]
    out.push(js_gc_describe(cur))
    n += 1
  out.join(" < ")

# An argument list the interpreter built for a call that has returned: collectable when
# the callee was an engine builtin (they copy what they keep; host natives may not).
-> js_gc_args(f, av)
  js_gc_reg(av) if JS_GC_ON[0] && av.size > 0 && f.is_a?(JsFunction) && f.gc_trusted == 2
  nil

# Collectable when allocated in engine context (see JS_GC_IN_ENGINE).
-> js_gc_eng(v)
  JS_GC_IN_ENGINE[0] ? js_gc_reg(v) : v

# Run job with the allocation context set: true for engine jobs (promise jobs), false
# around host lambdas (whatever they allocate may be held where the collector cannot see).
-> js_gc_ctx(flag, job)
  ie = JS_GC_IN_ENGINE[0]
  JS_GC_IN_ENGINE[0] = flag
  r = nil
  begin
    r = job.call()
  rescue e
    JS_GC_IN_ENGINE[0] = ie
    raise e
  JS_GC_IN_ENGINE[0] = ie
  r

# Between microtasks (realm.run_jobs): a safepoint when the pending jobs' values are all
# known (each job was queued with a keep list) and nothing JavaScript is on the stack.
-> js_gc_between_jobs(r)
  return nil if !JS_GC_ON[0] || JS_GC_HEAP.size < JS_GC_NEXT[0] || r.jobs_opaque[0] > 0
  return nil if JS_DEPTH[0] != 0 || JS_GC_SCRIPTS[0] != 0 || JS_GC_NATIVE[0] > 0 || JS_CUR_CORO[0] != nil
  return nil if r != JS_REALM[0] || !JS_GC_REALM_SET.has_key?(r)
  js_gc_collect(nil)
