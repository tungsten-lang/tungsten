# jsn/gc — Precise mark-sweep garbage collector for the jsn JavaScript engine.
#
# Uses 47-bit unboxed pointer keys (js_gc_key) so mark/sweep allocates ZERO WBigints,
# supports ephemeron WeakMap marking, WeakMap/WeakSet/WeakRef clearing,
# FinalizationRegistry cleanup scheduling, JS_AEXT pruning, and page teardown cleanup.

JS_GC_IVARS = {}
JS_GC_SENTINEL = ["gc-probe"]
JS_GC_VALUE_TYPES = {}
["Array", "BigDecimal", "BigInt", "Boolean", "Char", "Class", "Color", "Complex", "Currency", "Date", "Decimal", "Duration", "Float", "Hash", "Instant", "Int", "IPv4", "IPv6", "MAC", "Mmap", "Nil", "Point2D", "Quantity", "Range", "Rational", "SockAddr", "Socket", "String", "StringBuffer", "Symbol", "Unknown", "UUID", "Vec2f", "Vec2i", "Vec3f"].each ->(t) JS_GC_VALUE_TYPES[t] = true

-> js_gc_add_realm(r)
  if !JS_GC_REALM_SET.has_key?(r)
    JS_GC_REALMS.push(r)
    JS_GC_REALM_SET[r] = true
  nil

-> js_gc_remove_realm(r)
  JS_GC_REALMS.delete(r)
  JS_GC_REALM_SET.delete(r)
  JS_REALM[0] = nil if JS_REALM[0] == r
  nil

-> js_gc_atomic?(v)
  v == nil || v == true || v == false || v.is_a?(Float) || v.is_a?(Int) || v.is_a?(String) || v.is_a?(Symbol)

-> js_gc_push(stack, marks, x)
  return nil if js_gc_atomic?(x)
  xk = js_gc_key(wvalue_bits(x) ## i64)
  stack.push(x) if xk != 0 && !marks.has_key?(xk)
  nil

-> js_gc_jobs_safe?(r)
  return true if r == nil
  q = r.jobs
  return true if q == nil
  h = q.head
  t = q.tail
  m = q.mask
  while h != t
    return false if q.kinds[h] == JOB_LAMBDA
    h = (h + 1) & m
  true

JS_GC_BACKEDGE_ON = [Env.get("BLADE_JS_GC_BACKEDGE", "") == "1"]

# Safepoint between browser tasks / scripts.
-> js_gc_idle(extra)
  return nil if !JS_GC_ON[0] || JS_GC_HEAP.size < JS_GC_NEXT[0]
  return nil if JS_CUR_ACT[0] != nil || JS_CALL_DEPTH[0] != 0
  r = JS_REALM[0]
  return nil if r != nil && !js_gc_jobs_safe?(r)
  js_gc_collect(extra, "idle")

# Forced collection on page teardown / tab close (when no JS frame is active).
-> js_gc_force
  return nil if !JS_GC_ON[0] || JS_GC_HEAP.size == 0
  return nil if JS_CUR_ACT[0] != nil || JS_CALL_DEPTH[0] != 0
  r = JS_REALM[0]
  return nil if r != nil && !js_gc_jobs_safe?(r)
  js_gc_collect(nil, "force")

# Safepoint at a top-level script loop back-edge (opt-in: nested for-of/for-in hold native stack refs).
-> js_gc_backedge(act)
  return nil if !JS_GC_BACKEDGE_ON[0] || !JS_GC_ON[0] || JS_GC_HEAP.size < JS_GC_NEXT[0]
  return nil if JS_CALL_DEPTH[0] != 0 || act == nil || act.caller != nil || act.f == nil || !act.f.script || act.f.analysis.eval_mode
  r = JS_REALM[0]
  return nil if r != nil && !js_gc_jobs_safe?(r)
  js_gc_collect(act, "backedge")

# Run a full mark-sweep cycle (also callable from $262.gc() when BLADE_JS_GC=1).
-> js_gc_collect(extra = nil, why = "manual")
  return nil if !JS_GC_ON[0]
  t0 = clock() * ~1000.0
  marks = {}
  stack = []
  live_wms = []
  # ---- 1. Push roots ----
  js_gc_push(stack, marks, extra) if extra != nil
  js_gc_push(stack, marks, JS_CUR_ACT[0]) if JS_CUR_ACT[0] != nil
  js_gc_push(stack, marks, JS_REALM[0]) if JS_REALM[0] != nil
  i = 0
  while i < JS_GC_REALMS.size
    js_gc_push(stack, marks, JS_GC_REALMS[i])
    i += 1
  i = 0
  while i < JS_GC_ROOTS.size
    js_gc_push(stack, marks, JS_GC_ROOTS[i])
    i += 1
  js_gc_push(stack, marks, JS_UNHANDLED)
  js_gc_push(stack, marks, JS_LEXICAL)
  js_gc_push(stack, marks, JS_GLOBAL_VARS)
  js_gc_push(stack, marks, JS_POLY_KEEP)
  js_gc_push(stack, marks, JS_RX_REALM)
  js_gc_push(stack, marks, JIT_CODE_KEEP)
  js_gc_push(stack, marks, JIT_RT_KEEP)
  js_gc_push(stack, marks, JS_WAITERS)
  js_gc_push(stack, marks, WK_TC)
  js_gc_push(stack, marks, JS_NEW_TARGET)
  js_gc_push(stack, marks, JS_ARR_REALM_PROTO)
  js_gc_push(stack, marks, JS_RX_STR_KEEP)
  js_gc_push(stack, marks, JS_MODULES)
  # ---- 2. Mark ----
  while stack.size > 0
    js_gc_trace(stack.pop, marks, stack, live_wms)
  # ---- 3. Partition JS_GC_HEAP into live vs dead (recording dead keys as `marks[vk] = false`) ----
  # First, if any live WeakMaps exist, run ephemeron fixed-point before declaring any heap object dead!
  if live_wms.size > 0
    # Build temporary set of currently-registered heap keys (47-bit unboxed Int!) for ephemeron check
    heap_keys = {}
    hi = 0
    hn = JS_GC_HEAP.size
    while hi < hn
      heap_keys[js_gc_key(wvalue_bits(JS_GC_HEAP[hi]) ## i64)] = true
      hi += 1
    changed = true
    while changed
      changed = false
      wi = 0
      while wi < live_wms.size
        wm = live_wms[wi]
        wi += 1
        if wm.cls == "WeakMap" && wm.internal.is_a?(JS:MapData)
          d = wm.internal
          ki = 0
          kn = d.keys.size
          while ki < kn
            k = d.keys[ki]
            if k != JS_HOLE && !js_gc_atomic?(k)
              kk = js_gc_key(wvalue_bits(k) ## i64)
              if marks.has_key?(kk) || !heap_keys.has_key?(kk)
                val = d.vals[ki]
                if !js_gc_atomic?(val)
                  vk = js_gc_key(wvalue_bits(val) ## i64)
                  if vk != 0 && !marks.has_key?(vk)
                    stack.push(val)
                    changed = true
            ki += 1
      while stack.size > 0
        js_gc_trace(stack.pop, marks, stack, live_wms)
    ccall("w_value_free_w", heap_keys)
  mark_end = clock() * ~1000.0
  # Partition heap: live objects get marks[vk] = 2 (deduplicated); dead objects get marks[vk] = false!
  has_weak = live_wms.size > 0 || JS_GC_WEAK_REFS.size > 0 || JS_GC_FIN_REGS.size > 0 || JS_AEXT_KEEP.size > 0 || JS_ROOT_KEEP.size > 0
  live = []
  dead = has_weak ? [] : nil
  freed = 0
  hn = JS_GC_HEAP.size
  hi = 0
  while hi < hn
    v = JS_GC_HEAP[hi]
    hi += 1
    vk = js_gc_key(wvalue_bits(v) ## i64)
    st = marks[vk]
    if st == true
      marks[vk] = 2
      live.push(v)
    elsif st == nil
      marks[vk] = false
      JS_GC_KEEP.delete(vk) if JS_GC_KEEP.size > 0
      if has_weak
        dead.push(v)
      elsif JS_GC_VERIFY[0]
        JS_GC_DEAD[vk] = ccall("w_class_name", v)
      else
        js_gc_free(v, marks)
      freed += 1
  # ---- 4. Weak clearing (while dead objects are still intact so MapData removal works!) ----
  if has_weak
    wi = 0
    while wi < live_wms.size
      wm = live_wms[wi]
      wi += 1
      d = wm.internal
      if d.is_a?(JS:MapData)
        ki = 0
        kn = d.keys.size
        while ki < kn
          k = d.keys[ki]
          if k != JS_HOLE && !js_gc_atomic?(k)
            kk = js_gc_key(wvalue_bits(k) ## i64)
            js_map_remove(d, k) if marks[kk] == false
          ki += 1
    if JS_GC_WEAK_REFS.size > 0
      keep_wr = []
      wi = 0
      while wi < JS_GC_WEAK_REFS.size
        wr = JS_GC_WEAK_REFS[wi]
        wi += 1
        wrk = js_gc_key(wvalue_bits(wr) ## i64)
        if marks[wrk] != false
          t = wr.internal
          if t != nil && !js_gc_atomic?(t)
            tk = js_gc_key(wvalue_bits(t) ## i64)
            wr.internal = nil if marks[tk] == false
          keep_wr.push(wr) if wr.internal != nil
      JS_GC_WEAK_REFS.clear
      keep_wr.each ->(x) JS_GC_WEAK_REFS.push(x)
      ccall("w_value_free_w", keep_wr)
    if JS_GC_FIN_REGS.size > 0
      r_cur = JS_REALM[0]
      keep_fr = []
      fi = 0
      while fi < JS_GC_FIN_REGS.size
        fr = JS_GC_FIN_REGS[fi]
        fi += 1
        frk = js_gc_key(wvalue_bits(fr) ## i64)
        if marks[frk] != false
          recs = fr.s0
          if recs.is_a?(Array) && recs.size > 0
            rem = []
            ri = 0
            while ri < recs.size
              rec = recs[ri]
              ri += 1
              tk = js_gc_key(wvalue_bits(rec[0]) ## i64)
              if marks[tk] == false
                cb = fr.internal
                held = rec[1]
                r_cur.jobs.push_rx_prom(nil, cb, held, 0) if r_cur != nil && cb != nil
              else
                rem.push(rec)
            fr.s0 = rem
          keep_fr.push(fr)
      JS_GC_FIN_REGS.clear
      keep_fr.each ->(x) JS_GC_FIN_REGS.push(x)
      ccall("w_value_free_w", keep_fr)
    if JS_AEXT_KEEP.size > 0
      dead_aext = []
      JS_AEXT_KEEP.each ->(k, a)
        ak = js_gc_key(wvalue_bits(a) ## i64)
        dead_aext.push(k) if marks[ak] == false
      di = 0
      while di < dead_aext.size
        dk = dead_aext[di]
        di += 1
        ext = JS_AEXT[dk]
        JS_AEXT.delete(dk)
        JS_AEXT_KEEP.delete(dk)
        if ext != nil
          ek = js_gc_key(wvalue_bits(ext) ## i64)
          ccall("w_value_free_w", ext) if marks[ek] == nil && !JS_GC_VERIFY[0]
      ccall("w_value_free_w", dead_aext)
    if JS_ROOT_KEEP.size > 0
      keep_rk = []
      ri = 0
      while ri < JS_ROOT_KEEP.size
        pr = JS_ROOT_KEEP[ri]
        ri += 1
        pk = js_gc_key(wvalue_bits(pr) ## i64)
        if marks[pk] == false
          h = JS_ROOTS[pk]
          JS_ROOTS.delete(pk)
          ccall("w_value_free_w", h) if h != nil && !JS_GC_VERIFY[0]
        else
          keep_rk.push(pr)
      JS_ROOT_KEEP.clear
      keep_rk.each ->(x) JS_ROOT_KEEP.push(x)
      ccall("w_value_free_w", keep_rk)
    # Free deferred dead objects now that weak references have been cleared!
    di = 0
    while di < dead.size
      if JS_GC_VERIFY[0]
        dv = dead[di]
        JS_GC_DEAD[js_gc_key(wvalue_bits(dv) ## i64)] = ccall("w_class_name", dv)
      else
        js_gc_free(dead[di], marks)
      di += 1
    ccall("w_value_free_w", dead)
  # ---- 5. Compact heap & free scratch tables ----
  live_n = live.size
  JS_GC_HEAP.clear
  li = 0
  while li < live_n
    JS_GC_HEAP.push(live[li])
    li += 1
  ccall("w_value_free_w", live)
  ccall("w_value_free_w", live_wms)
  ccall("w_value_free_w", marks)
  ccall("w_value_free_w", stack)
  finish = clock() * ~1000.0
  dt = (finish - t0).to_i
  JS_GC_STATS[0] += 1
  JS_GC_STATS[1] += freed
  JS_GC_STATS[2] = dt
  JS_GC_STATS[3] = live_n
  JS_GC_NEXT[0] = live_n + (live_n > JS_GC_BASE[0] ? live_n : JS_GC_BASE[0])
  observer = JS_GC_OBSERVER[0]
  observer.call(why, [((finish - t0) * ~1000.0).round, ((mark_end - t0) * ~1000.0).round, ((finish - mark_end) * ~1000.0).round, live_n, freed]) if observer != nil
  ccall("w_eputs", "\[jsn gc " + why + "] freed " + freed.to_s + " live " + live_n.to_s + " in " + dt.to_s + " ms") if JS_GC_LOG[0]
  nil

-> js_gc_trace(v, marks, stack, live_wms)
  return nil if js_gc_atomic?(v)
  vk = js_gc_key(wvalue_bits(v) ## i64)
  return nil if vk == 0 || marks.has_key?(vk)
  if JS_GC_VERIFY[0] && JS_GC_DEAD.has_key?(vk)
    ccall("w_eputs", "\[jsn gc VERIFY FAIL] resurrected dead " + JS_GC_DEAD[vk].to_s)
    JS_GC_DEAD.delete(vk)
  marks[vk] = true
  # Every JS:Base object carries its [[Prototype]] inside @shape.proto — trace it so custom
  # prototypes (class/Object.create) are never collected while live instances still point to them!
  if v.is_a?(JS:Base)
    js_gc_push(stack, marks, v.shape.proto) if v.shape != nil
    if JS_GC_KEEP.size > 0
      kp = JS_GC_KEEP[vk]
      js_gc_push(stack, marks, kp) if kp != nil
  # Fast direct-ivar dispatch for hot JS engine types (ZERO reflection overhead!)
  if v.is_a?(JS:Object)
    js_gc_push(stack, marks, v.ext)
    js_gc_push(stack, marks, v.s0)
    js_gc_push(stack, marks, v.s1)
    js_gc_push(stack, marks, v.s2)
    js_gc_push(stack, marks, v.s3)
    js_gc_push(stack, marks, v.s4)
    js_gc_push(stack, marks, v.s5)
    js_gc_push(stack, marks, v.s6)
    js_gc_push(stack, marks, v.s7)
    return nil
  if v.is_a?(Array)
    # Only polymorphic WValue arrays (ebits == 65) can hold heap references; skip ByteArray / i64[] / f64[] in O(1)!
    return nil if jb_ld_u8(vk + 1) != 65
    i = 0
    n = v.size
    while i < n
      js_gc_push(stack, marks, v[i])
      i += 1
    if (jsr_aflags(wvalue_bits(v) ## i64) & JS_AF_EXT) != 0
      ext = JS_AEXT[vk]
      js_gc_push(stack, marks, ext) if ext != nil
    return nil
  if v.is_a?(JS:Function)
    js_gc_push(stack, marks, v.env)
    js_gc_push(stack, marks, v.ext)
    js_gc_push(stack, marks, v.s0)
    js_gc_push(stack, marks, v.s1)
    js_gc_push(stack, marks, v.s2)
    js_gc_push(stack, marks, v.s3)
    if v.is_a?(JS:Method)
      js_gc_push(stack, marks, v.home)
      js_gc_push(stack, marks, v.fields)
      js_gc_push(stack, marks, v.privs)
      js_gc_push(stack, marks, v.inits)
    return nil
  if v.is_a?(JS:Env)
    js_gc_push(stack, marks, v.up)
    js_gc_push(stack, marks, v.v0)
    js_gc_push(stack, marks, v.v1)
    js_gc_push(stack, marks, v.v2)
    js_gc_push(stack, marks, v.v3)
    js_gc_push(stack, marks, v.v4)
    js_gc_push(stack, marks, v.v5)
    js_gc_push(stack, marks, v.v6)
    return nil
  if v.is_a?(JS:EnvN)
    js_gc_push(stack, marks, v.up)
    js_gc_push(stack, marks, v.v0)
    js_gc_push(stack, marks, v.v1)
    js_gc_push(stack, marks, v.v2)
    js_gc_push(stack, marks, v.v3)
    js_gc_push(stack, marks, v.v4)
    js_gc_push(stack, marks, v.v5)
    js_gc_push(stack, marks, v.v6)
    js_gc_push(stack, marks, v.vars)
    js_gc_push(stack, marks, v.dyn)
    return nil
  if v.is_a?(JS:WithEnv)
    js_gc_push(stack, marks, v.up)
    js_gc_push(stack, marks, v.obj)
    return nil
  if v.is_a?(JS:Promise)
    js_gc_push(stack, marks, v.ext)
    js_gc_push(stack, marks, v.value)
    js_gc_push(stack, marks, v.reactions)
    js_gc_push(stack, marks, v.rx_target)
    js_gc_push(stack, marks, v.rx_on_f)
    js_gc_push(stack, marks, v.rx_on_r)
    return nil
  if v.is_a?(JS:GlobalCell)
    js_gc_push(stack, marks, v.fast)
    js_gc_push(stack, marks, v.store)
    return nil
  if v.is_a?(JS:GlobalObject)
    js_gc_push(stack, marks, v.cells)
    js_gc_push(stack, marks, v.ext)
    js_gc_push(stack, marks, v.internal)
    js_gc_push(stack, marks, v.priv_handlers)
    return nil
  if v.is_a?(JS:NativeFunction)
    js_gc_push(stack, marks, v.ext)
    js_gc_push(stack, marks, v.data)
    js_gc_push(stack, marks, v.s0)
    js_gc_push(stack, marks, v.s1)
    js_gc_push(stack, marks, v.realm)
    return nil
  if v.is_a?(JS:Generator)
    js_gc_push(stack, marks, v.ext)
    js_gc_push(stack, marks, v.frame)
    js_gc_push(stack, marks, v.s0)
    js_gc_push(stack, marks, v.s1)
    js_gc_push(stack, marks, v.s2)
    js_gc_push(stack, marks, v.s3)
    return nil
  if v.is_a?(JS:AsyncGen)
    js_gc_push(stack, marks, v.ext)
    js_gc_push(stack, marks, v.frame)
    js_gc_push(stack, marks, v.queue)
    js_gc_push(stack, marks, v.s0)
    js_gc_push(stack, marks, v.s1)
    js_gc_push(stack, marks, v.s2)
    js_gc_push(stack, marks, v.s3)
    return nil
  if v.is_a?(JS:SmFrame)
    js_gc_push(stack, marks, v.act)
    js_gc_push(stack, marks, v.vstack)
    js_gc_push(stack, marks, v.tries)
    js_gc_push(stack, marks, v.pendings)
    js_gc_push(stack, marks, v.env_stack)
    js_gc_push(stack, marks, v.iters)
    js_gc_push(stack, marks, v.temps)
    js_gc_push(stack, marks, v.disps)
    js_gc_push(stack, marks, v.disp_awaiting)
    js_gc_push(stack, marks, v.promise)
    js_gc_push(stack, marks, v.async_gen)
    js_gc_push(stack, marks, v.ystar_rec)
    js_gc_push(stack, marks, v.result_val)
    return nil
  if v.is_a?(JS:Realm)
    js_gc_push(stack, marks, v.global)
    js_gc_push(stack, marks, v.intrinsics)
    js_gc_push(stack, marks, v.jobs)
    js_gc_push(stack, marks, v.host)
    js_gc_push(stack, marks, v.symbol_registry)
    js_gc_push(stack, marks, v.template_cache)
    js_gc_push(stack, marks, v.modules)
    js_gc_push(stack, marks, v.errors)
    js_gc_push(stack, marks, v.lexical)
    js_gc_push(stack, marks, v.global_vars)
    js_gc_push(stack, marks, v.unhandled)
    js_gc_push(stack, marks, v.promise_species_acc)
    js_gc_push(stack, marks, v.rx_parens)
    js_gc_push(stack, marks, v.jit_keep)
    return nil
  if v.is_a?(JS:JobQueue)
    h = v.head
    t = v.tail
    m = v.mask
    while h != t
      js_gc_push(stack, marks, v.qa[h])
      js_gc_push(stack, marks, v.qb[h])
      js_gc_push(stack, marks, v.qc[h])
      h = (h + 1) & m
    return nil
  if v.is_a?(JS:Proxy)
    js_gc_push(stack, marks, v.ext)
    js_gc_push(stack, marks, v.target)
    js_gc_push(stack, marks, v.handler)
    return nil
  if v.is_a?(JS:BoundFunction)
    js_gc_push(stack, marks, v.ext)
    js_gc_push(stack, marks, v.target)
    js_gc_push(stack, marks, v.bthis)
    js_gc_push(stack, marks, v.args)
    js_gc_push(stack, marks, v.s0)
    js_gc_push(stack, marks, v.s1)
    js_gc_push(stack, marks, v.s2)
    return nil
  if v.is_a?(JS:Accessor)
    js_gc_push(stack, marks, v.getter)
    js_gc_push(stack, marks, v.setter)
    return nil
  if v.is_a?(JS:Reaction)
    js_gc_push(stack, marks, v.cap)
    js_gc_push(stack, marks, v.handler)
    js_gc_push(stack, marks, v.keep)
    return nil
  if v.is_a?(JS:Capability)
    js_gc_push(stack, marks, v.promise)
    js_gc_push(stack, marks, v.resolve)
    js_gc_push(stack, marks, v.reject)
    return nil
  if v.is_a?(JS:MapData)
    js_gc_push(stack, marks, v.keys)
    js_gc_push(stack, marks, v.vals)
    return nil
  if v.is_a?(JS:Special)
    c = v.cls
    if c == "WeakRef"
      js_gc_push(stack, marks, v.ext)
      js_gc_push(stack, marks, v.s0)
      js_gc_push(stack, marks, v.s1)
      js_gc_push(stack, marks, v.s2)
      js_gc_push(stack, marks, v.s3)
      return nil
    if c == "WeakMap" || c == "WeakSet"
      js_gc_push(stack, marks, v.ext)
      js_gc_push(stack, marks, v.s0)
      js_gc_push(stack, marks, v.s1)
      js_gc_push(stack, marks, v.s2)
      js_gc_push(stack, marks, v.s3)
      live_wms.push(v)
      return nil
    if c == "FinalizationRegistry"
      js_gc_push(stack, marks, v.ext)
      js_gc_push(stack, marks, v.internal)
      js_gc_push(stack, marks, v.s1)
      js_gc_push(stack, marks, v.s2)
      js_gc_push(stack, marks, v.s3)
      recs = v.s0
      if recs.is_a?(Array)
        ri = 0
        while ri < recs.size
          js_gc_push(stack, marks, recs[ri][1])
          js_gc_push(stack, marks, recs[ri][2])
          ri += 1
      return nil
    if !v.is_a?(JsObject) && !v.is_a?(JS:TypedArray) && !v.is_a?(JS:DataView) && !v.is_a?(JS:ArrayBuffer) && !v.is_a?(JS:Arguments)
      js_gc_push(stack, marks, v.ext)
      js_gc_push(stack, marks, v.internal)
      js_gc_push(stack, marks, v.s0)
      js_gc_push(stack, marks, v.s1)
      js_gc_push(stack, marks, v.s2)
      js_gc_push(stack, marks, v.s3)
      return nil
  if v.is_a?(Hash)
    v.each ->(k, x)
      js_gc_push(stack, marks, k)
      js_gc_push(stack, marks, x)
    return nil
  if v.is_a?(WkAct)
    js_gc_push(stack, marks, v.fobj)
    js_gc_push(stack, marks, v.fe)
    js_gc_push(stack, marks, v.this)
    js_gc_push(stack, marks, v.locals)
    js_gc_push(stack, marks, v.env)
    js_gc_push(stack, marks, v.args)
    js_gc_push(stack, marks, v.a0)
    js_gc_push(stack, marks, v.a1)
    js_gc_push(stack, marks, v.a2)
    js_gc_push(stack, marks, v.a3)
    js_gc_push(stack, marks, v.disp)
    js_gc_push(stack, marks, v.coro)
    js_gc_push(stack, marks, v.nt)
    js_gc_push(stack, marks, v.rv)
    js_gc_push(stack, marks, v.env_at_entry)
    js_gc_push(stack, marks, v.caller)
    return nil
  cn = ccall("w_class_name", v)
  return nil if JS_GC_VALUE_TYPES.has_key?(cn)
  return nil if cn == "JS:Shape" || cn == "JS:Code" || cn == "JS:Regex" || cn == "JS:RxNode" || cn == "JS:PrivateName" || cn == "JS:Symbol" || cn == "JS:Hole" || cn == "JS:Null"
  return nil if !(cn.starts_with?("JS:") || cn.starts_with?("Js") || JS_GC_HOST_CLASSES.has_key?(cn))
  n = js_gc_ivar_count(v, cn)
  i = 0
  while i < n
    js_gc_push(stack, marks, ccall("w_ivar_get_idx", v, (i ## int)))
    i += 1
  nil

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

-> js_gc_free(v, marks)
  if v.is_a?(JS:Base) && v.ext != nil
    ek = js_gc_key(wvalue_bits(v.ext) ## i64)
    if marks[ek] == nil
      marks[ek] = false
      ccall("w_value_free_w", v.ext)
  if v.is_a?(JS:ArrayBuffer) && !v.shared && v.data != nil
    dk = js_gc_key(wvalue_bits(v.data) ## i64)
    if marks[dk] == nil
      marks[dk] = false
      ccall("w_value_free_w", v.data)
  elsif v.is_a?(JS:Promise) && v.reactions.is_a?(Array)
    rk = js_gc_key(wvalue_bits(v.reactions) ## i64)
    if marks[rk] == nil
      marks[rk] = false
      ccall("w_value_free_w", v.reactions)
  elsif v.is_a?(JS:Special) && v.internal.is_a?(JS:MapData)
    d = v.internal
    dk = js_gc_key(wvalue_bits(d) ## i64)
    if marks[dk] == nil
      marks[dk] = false
      if d.keys != nil
        kk = js_gc_key(wvalue_bits(d.keys) ## i64)
        if marks[kk] == nil
          marks[kk] = false
          ccall("w_value_free_w", d.keys)
      if d.vals != nil
        vlk = js_gc_key(wvalue_bits(d.vals) ## i64)
        if marks[vlk] == nil
          marks[vlk] = false
          ccall("w_value_free_w", d.vals)
      ccall("w_value_free_w", d)
  elsif v.is_a?(JS:EnvN)
    ccall("w_value_free_w", v.vars) if v.vars != nil
    ccall("w_value_free_w", v.dyn) if v.dyn != nil
  ccall("w_value_free_w", v)
  nil
