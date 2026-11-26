# runtime/b_promise — High-speed Promise (ES2024 plus withResolvers / try) and microtask glue.
#
# Inline single-reaction slots on JS:Promise avoid allocating Capability / resolving closures /
# Reaction / reactions[] on intrinsic Promise chains. Reactions run on Realm#jobs's flat
# power-of-2 ring buffer with zero Tungsten closure allocations per microtask.

in JS

JS_SLOW_SENTINEL = wvalue_from_bits(6)

fn js_is_slow_bits(b) (i64) i64
  b == 6 ? 1 : 0

# Reaction slot modes on JS:Promise (@rx_kind):
#   0 = none
#   1 = single intrinsic .then() target: @rx_target = target JS:Promise (or nil), @rx_on_f, @rx_on_r
#   2 = single general JS:Reaction pair: @rx_on_f = fr, @rx_on_r = rr
#   3 = multiple reactions in @reactions: array of [kind, a, b, c]
#   4 = single stackless SmFrame awaiting this promise: @rx_target = frame

+ Promise < JS:Base
  rw :state, :value, :reactions, :handled, :rx_kind, :rx_target, :rx_on_f, :rx_on_r

  -> new(@shape)
    @state = :pending
    @handled = false
    @rx_kind = 0
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_OBJECT)
    js_gc_reg(self) if JS_GC_ON[0]

  -> init_fulfilled(v)
    @state = :fulfilled
    @value = v
    self

+ Capability
  rw :promise, :resolve, :reject
  -> new(@promise, @resolve, @reject)
    nil

# A reaction: handler is a JS function, a Tungsten lambda ->(v), or nil (pass through).
+ Reaction
  # keep: values the handler lambda captures (for a collector)
  rw :cap, :kind, :handler, :keep
  -> new(@cap, @kind, @handler)
    @keep = nil

# Rejected promises without a handler (per-realm so isolates stay completely separate).
JS_UNHANDLED = []

-> js_unhandled
  r = js_realm()
  r == nil ? JS_UNHANDLED : r.unhandled

# Epoch-cached pristine check for intrinsic Promise / Promise.prototype / Promise[Symbol.species].
# [verified_epoch, result (0/1)]
JS_PROM_PRISTINE = i64[2]

# Dynamically discovered byte offsets for pure-LLVM Promise chain draining:
#   [0]=state, [1]=value, [2]=rx_kind, [3]=rx_target, [4]=rx_on_f, [5]=rx_on_r, [6]=q_head, [7]=q_tail
JS_PROM_OFFS = i64[8]
JS_PROM_DRAIN_OUT = i64[4]   # [cur_target_bits, next_target_bits, next_handler_bits, last_res_bits]

-> js_prom_offs_init(q)
  return nil if JS_PROM_OFFS[0] != 0
  p = JS:Promise.new(js_realm().promise_shape)
  p.state = :pending
  p.value = :__pv_probe
  p.rx_kind = 13579
  p.rx_target = :__pt_probe
  p.rx_on_f = :__pf_probe
  p.rx_on_r = :__pr_probe
  pb = wvalue_bits(p) ## i64
  JS_PROM_OFFS[0] = js_find_ivar_off(pb, wvalue_bits(:pending) ## i64)
  JS_PROM_OFFS[1] = js_find_ivar_off(pb, wvalue_bits(:__pv_probe) ## i64)
  JS_PROM_OFFS[2] = js_find_ivar_off(pb, wvalue_bits(13579) ## i64)
  JS_PROM_OFFS[3] = js_find_ivar_off(pb, wvalue_bits(:__pt_probe) ## i64)
  JS_PROM_OFFS[4] = js_find_ivar_off(pb, wvalue_bits(:__pf_probe) ## i64)
  JS_PROM_OFFS[5] = js_find_ivar_off(pb, wvalue_bits(:__pr_probe) ## i64)
  q2 = JS:JobQueue.new
  q2.head = 11111
  q2.tail = 22222
  qb = wvalue_bits(q2) ## i64
  JS_PROM_OFFS[6] = js_find_ivar_off(qb, wvalue_bits(11111) ## i64)
  JS_PROM_OFFS[7] = js_find_ivar_off(qb, wvalue_bits(22222) ## i64)
  nil

# Pure-LLVM tight drain for consecutive same-handler JITted intrinsic Promise chains when queue is empty!
# Writes current target into out_p[0] before each call so exceptions reject the exact throwing promise!
# Return codes:
#   0 = chain completely finished (target became nil or settled with no next reaction)
#   1 = handoff: out_p[0]=target (already fulfilled with out_p[3]), out_p[1]=next_target, out_p[2]=next_handler
#   2 = fallback needed on out_p[0] with handler fn_bits and val out_p[3] (JSR_SLOW, object result, non-empty queue, or rk != 1)
fn js_drain_prom_chain_ll(target_bits, fp, fn_bits, val_bits, pend_bits, fulf_bits, q_bits, offs_p, out_p) (i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %op = inttoptr i64 %offs_p to ptr
    %off_st = load i64, ptr %op, align 8
    %op1 = getelementptr i64, ptr %op, i64 1
    %off_vl = load i64, ptr %op1, align 8
    %op2 = getelementptr i64, ptr %op, i64 2
    %off_rk = load i64, ptr %op2, align 8
    %op3 = getelementptr i64, ptr %op, i64 3
    %off_tg = load i64, ptr %op3, align 8
    %op4 = getelementptr i64, ptr %op, i64 4
    %off_of = load i64, ptr %op4, align 8
    %op5 = getelementptr i64, ptr %op, i64 5
    %off_or = load i64, ptr %op5, align 8
    %op6 = getelementptr i64, ptr %op, i64 6
    %off_qh = load i64, ptr %op6, align 8
    %op7 = getelementptr i64, ptr %op, i64 7
    %off_qt = load i64, ptr %op7, align 8
    %qraw = sub i64 %q_bits, 4
    %qp = inttoptr i64 %qraw to ptr
    %qhp = getelementptr i8, ptr %qp, i64 %off_qh
    %qtp = getelementptr i8, ptr %qp, i64 %off_qt
    %out = inttoptr i64 %out_p to ptr
    %out1 = getelementptr i64, ptr %out, i64 1
    %out2 = getelementptr i64, ptr %out, i64 2
    %out3 = getelementptr i64, ptr %out, i64 3
    br label %loop
  loop:
    %cur_t = phi i64 [ %target_bits, %0 ], [ %nt, %cont ]
    %cur_v = phi i64 [ %val_bits, %0 ], [ %res, %cont ]
    store i64 %cur_t, ptr %out, align 8
    %res = call i64 %f(i64 %fn_bits, i64 0, i64 1, i64 %cur_v, i64 0, i64 0, i64 0, i64 0)
    %is_slow = icmp eq i64 %res, 6
    br i1 %is_slow, label %bail_slow, label %chk_t
  chk_t:
    %tnil = icmp eq i64 %cur_t, 0
    br i1 %tnil, label %ret_done, label %chk_prim
  chk_prim:
    ; Primitive check: Number, nil/false/true (<=2), or flat String (0xFFF9, bit 0 clear)
    %rx = sub i64 %res, 281474976710656
    %risn = icmp ult i64 %rx, u0xFFF0000000000001
    br i1 %risn, label %prim_ok, label %chk_p2
  chk_p2:
    %rsm = icmp ule i64 %res, 2
    br i1 %rsm, label %prim_ok, label %chk_ps
  chk_ps:
    %rst = and i64 %res, u0xFFFF000000000001
    %riss = icmp eq i64 %rst, u0xFFF9000000000000
    br i1 %riss, label %prim_ok, label %bail_res
  prim_ok:
    %traw = sub i64 %cur_t, 4
    %tp = inttoptr i64 %traw to ptr
    %stp = getelementptr i8, ptr %tp, i64 %off_st
    %st = load i64, ptr %stp, align 8
    %is_pend = icmp eq i64 %st, %pend_bits
    br i1 %is_pend, label %chk_rk, label %ret_done
  chk_rk:
    %rkp = getelementptr i8, ptr %tp, i64 %off_rk
    %rk_box = load i64, ptr %rkp, align 8
    %rk = and i64 %rk_box, 281474976710655
    %is_rk1 = icmp eq i64 %rk, 1
    br i1 %is_rk1, label %chk_q, label %bail_res
  chk_q:
    %qh = load i64, ptr %qhp, align 8
    %qt = load i64, ptr %qtp, align 8
    %qempty = icmp eq i64 %qh, %qt
    br i1 %qempty, label %settle, label %bail_res
  settle:
    %tgp = getelementptr i8, ptr %tp, i64 %off_tg
    %nt = load i64, ptr %tgp, align 8
    %ofp = getelementptr i8, ptr %tp, i64 %off_of
    %nh = load i64, ptr %ofp, align 8
    %orp = getelementptr i8, ptr %tp, i64 %off_or
    %vlp = getelementptr i8, ptr %tp, i64 %off_vl
    store i64 %fulf_bits, ptr %stp, align 8
    store i64 %res, ptr %vlp, align 8
    %rk0 = and i64 %rk_box, u0xFFFF000000000000
    store i64 %rk0, ptr %rkp, align 8
    store i64 0, ptr %tgp, align 8
    store i64 0, ptr %ofp, align 8
    store i64 0, ptr %orp, align 8
    %same_h = icmp eq i64 %nh, %fn_bits
    br i1 %same_h, label %cont, label %ret_handoff
  cont:
    br label %loop
  ret_handoff:
    store i64 %nt, ptr %out1, align 8
    store i64 %nh, ptr %out2, align 8
    store i64 %res, ptr %out3, align 8
    ret i64 1
  bail_res:
    store i64 %res, ptr %out3, align 8
    ret i64 2
  bail_slow:
    store i64 %cur_v, ptr %out3, align 8
    ret i64 3
  ret_done:
    ret i64 0
  IR

-> js_promise?(v)
  v.is_a?(JS:Promise)

-> js_promise_alloc(proto)
  r = js_realm()
  return JS:Promise.new(r.promise_shape) if proto == r.promise_proto && r.promise_shape != nil
  JS:Promise.new(js_root_shape(proto, 0, 2))

-> js_promise_pristine?(r)
  ep = JS_EPOCH[0]
  if JS_PROM_PRISTINE[0] == ep && JS_PROM_PRISTINE[1] != 0
    return true
  pp = r.promise_proto
  pc = r.promise_ctor
  return false if pp == nil || pc == nil
  ok = pp.get_own("then") == r.promise_then_fn && pp.get_own("constructor") == pc && pc.get_own("resolve") == r.promise_resolve_fn && pc.get_own(SYM_SPECIES) == r.promise_species_acc
  JS_PROM_PRISTINE[0] = ep
  JS_PROM_PRISTINE[1] = ok ? 1 : 0
  ok

# CreateResolvingFunctions
-> js_resolving_functions(p)
  r = js_realm()
  done = [false]
  res = js_keep(r.native("", 1, ->(this, args, nt) js_resolve_once(p, done, js_arg(args, 0))), [p, done])
  rej = js_keep(r.native("", 1, ->(this, args, nt) js_reject_once(p, done, js_arg(args, 0))), [p, done])
  [res, rej]

-> js_resolve_once(p, done, x)
  return nil if done[0]
  done[0] = true
  js_promise_resolve_with(p, x)
  nil

-> js_reject_once(p, done, x)
  return nil if done[0]
  done[0] = true
  js_promise_reject(p, x)
  nil

-> js_promise_resolve_with(p, x)
  if x == p
    js_promise_reject(p, js_type_error("Chaining cycle detected for promise"))
    return nil
  if !js_object?(x)
    js_promise_fulfill(p, x)
    return nil
  r = js_realm()
  # fast path: a native promise with the intrinsic then
  if js_promise?(x) && x.proto == r.promise_proto && !x.has_own?("then") && js_promise_then_pristine?()
    r.jobs.push_adopt(p, x)
    return nil
  th = nil
  begin
    th = jget(x, "then")
  rescue e
    js_promise_reject(p, js_error_value(e))
    return nil
  if !js_callable?(th)
    js_promise_fulfill(p, x)
    return nil
  r.jobs.push_thenable(p, x, th)
  nil

-> js_promise_then_pristine?
  r = js_realm()
  r.promise_proto.get_own("then") == r.promise_then_fn

-> js_promise_adopt(p, x)
  # Fast zero-closure adoption when target is a plain JS:Promise!
  r = js_realm()
  if js_promise?(p) && p.state == :pending
    if x.state == :fulfilled
      x.handled = true
      r.jobs.push_rx_prom(p, nil, x.value, 0)
      return nil
    if x.state == :rejected
      if !x.handled
        idx = JS_UNHANDLED.index(x)
        JS_UNHANDLED.delete_at(idx) if idx != nil
      x.handled = true
      r.jobs.push_rx_prom(p, nil, x.value, 1)
      return nil
    js_promise_attach_raw(x, 1, p, nil, nil)
    x.handled = true
    return nil
  fns = js_resolving_functions(p)
  a = JS:Reaction.new(nil, :fulfill, ->(v) js_call_arr(fns[0], nil, [v]))
  a.keep = fns
  b = JS:Reaction.new(nil, :reject, ->(v) js_call_arr(fns[1], nil, [v]))
  b.keep = fns
  js_perform_then(x, a, b)
  nil

-> js_thenable_job(p, x, th)
  fns = js_resolving_functions(p)
  begin
    js_call_arr(th, x, [fns[0], fns[1]])
  rescue e
    js_call_arr(fns[1], nil, [js_error_value(e)])
  nil

-> js_promise_attach_raw(p, kind, a, b, c)
  rk = p.rx_kind
  if rk == 0
    p.rx_kind = kind
    p.rx_target = a
    p.rx_on_f = b
    p.rx_on_r = c
    return nil
  if rk != 3
    p.reactions = [[rk, p.rx_target, p.rx_on_f, p.rx_on_r], [kind, a, b, c]]
    p.rx_kind = 3
    p.rx_target = nil
    p.rx_on_f = nil
    p.rx_on_r = nil
    return nil
  p.reactions.push([kind, a, b, c])
  nil

-> js_promise_fulfill_fast(p, v, q)
  return nil if p.state != :pending
  rk = p.rx_kind
  p.state = :fulfilled
  p.value = v
  return nil if rk == 0
  p.rx_kind = 0
  if rk == 1
    t = p.rx_target
    h = p.rx_on_f
    p.rx_target = nil
    p.rx_on_f = nil
    p.rx_on_r = nil
    q.push_rx_prom(t, h, v, 0)
    return nil
  if rk == 4
    fr = p.rx_target
    p.rx_target = nil
    q.push_async(fr, v, 0)
    return nil
  if rk == 2
    fr = p.rx_on_f
    p.rx_on_f = nil
    p.rx_on_r = nil
    q.push_rx_cap(fr, v)
    return nil
  rs = p.reactions
  p.reactions = nil
  if rs != nil
    i = 0
    while i < rs.size
      e = rs[i]
      ek = e[0]
      if ek == 1
        q.push_rx_prom(e[1], e[2], v, 0)
      elsif ek == 4
        q.push_async(e[1], v, 0)
      else
        q.push_rx_cap(e[2], v)
      i += 1
  nil

-> js_promise_fulfill(p, v)
  js_promise_fulfill_fast(p, v, js_realm().jobs)

-> js_promise_reject_fast(p, v, q)
  return nil if p.state != :pending
  rk = p.rx_kind
  p.state = :rejected
  p.value = v
  JS_UNHANDLED.push(p) if !p.handled
  return nil if rk == 0
  p.rx_kind = 0
  if rk == 1
    t = p.rx_target
    h = p.rx_on_r
    p.rx_target = nil
    p.rx_on_f = nil
    p.rx_on_r = nil
    q.push_rx_prom(t, h, v, 1)
    return nil
  if rk == 4
    fr = p.rx_target
    p.rx_target = nil
    q.push_async(fr, v, 1)
    return nil
  if rk == 2
    rr = p.rx_on_r
    p.rx_on_f = nil
    p.rx_on_r = nil
    q.push_rx_cap(rr, v)
    return nil
  rs = p.reactions
  p.reactions = nil
  if rs != nil
    i = 0
    while i < rs.size
      e = rs[i]
      ek = e[0]
      if ek == 1
        q.push_rx_prom(e[1], e[3], v, 1)
      elsif ek == 4
        q.push_async(e[1], v, 1)
      else
        q.push_rx_cap(e[3], v)
      i += 1
  nil

-> js_promise_reject(p, v)
  js_promise_reject_fast(p, v, js_realm().jobs)

-> js_trigger(rx, v)
  js_realm().jobs.push_rx_cap(rx, v)
  nil

# Hot inline microtask runner called directly from Realm#run_jobs (exceptions caught by outer loop!).
-> js_run_prom_rx_inline(target, h, v, is_rej, q)
  if h == nil
    return nil if target == nil
    if is_rej != 0
      js_promise_reject_fast(target, v, q)
    else
      js_promise_fulfill_fast(target, v, q)
    return nil
  res = nil
  if h.is_a?(JS:Function)
    c = h.code
    fp = c.jit_fp
    if fp == 0 && c.jit_state == 0
      h_cnt = c.jit_hits + 1
      c.jit_hits = h_cnt
      if h_cnt >= WK_JIT_FN_THRESH
        jit_compile_and_install(c)
        fp = c.jit_fp
    if fp != 0
      res = wvalue_from_bits(jit_raw_call8(fp ## i64, wvalue_bits(h) ## i64, 0, 1, wvalue_bits(v) ## i64, 0, 0, 0, 0))
      if js_is_slow_bits(wvalue_bits(res) ## i64) != 0
        res = wk_call_tier0(h, nil, 1, v, nil, nil, nil, nil)
    else
      res = js_call(h, nil, 1, v, nil, nil, nil, nil)
  elsif js_object?(h)
    res = js_call(h, nil, 1, v, nil, nil, nil, nil)
  else
    res = h.call(v)
  return nil if target == nil
  if !js_object?(res)
    js_promise_fulfill_fast(target, res, q)
  else
    js_promise_resolve_with(target, res)
  nil

# Called from Realm#run_jobs for general JS:Reaction (exceptions caught by outer loop!).
-> js_reaction_job_inline(rx, v)
  h = rx.handler
  cap = rx.cap
  if h == nil
    return nil if cap == nil
    if rx.kind == :reject
      js_cap_reject(cap, v)
    else
      js_cap_resolve(cap, v)
    return nil
  res = nil
  if js_object?(h)
    res = js_call(h, nil, 1, v, nil, nil, nil, nil)
  else
    res = h.call(v)
  return nil if cap == nil
  js_cap_resolve(cap, res)
  nil

-> js_cap_resolve(cap, v)
  if js_object?(cap.resolve)
    js_call_arr(cap.resolve, nil, [v])
  else
    cap.resolve.call(v)

-> js_cap_reject(cap, v)
  if js_object?(cap.reject)
    js_call_arr(cap.reject, nil, [v])
  else
    cap.reject.call(v)

# PerformPromiseThen with two JS:Reaction objects.
-> js_perform_then(p, fr, rr)
  if p.state == :pending
    js_promise_attach_raw(p, 2, nil, fr, rr)
  elsif p.state == :fulfilled
    js_realm().jobs.push_rx_cap(fr, p.value)
  else
    if !p.handled
      i = JS_UNHANDLED.index(p)
      JS_UNHANDLED.delete_at(i) if i != nil
    js_realm().jobs.push_rx_cap(rr, p.value)
  p.handled = true
  nil

# Attach a stackless SmFrame to an awaited value `v` (zero Promise/Reaction/closure allocations on fast path!).
-> js_promise_attach_async(v, frame, q)
  r = js_realm()
  if js_promise_pristine?(r)
    if !js_object?(v)
      q.push_async(frame, v, 0)
      return nil
    if js_promise?(v) && v.shape == r.promise_shape
      st = v.state
      if st == :fulfilled
        v.handled = true
        q.push_async(frame, v.value, 0)
        return nil
      if st == :rejected
        if !v.handled
          i = JS_UNHANDLED.index(v)
          JS_UNHANDLED.delete_at(i) if i != nil
        v.handled = true
        q.push_async(frame, v.value, 1)
        return nil
      js_promise_attach_raw(v, 4, frame, nil, nil)
      v.handled = true
      return nil
  p = js_promise_resolve_value(v)
  if js_promise?(p) && p.shape == r.promise_shape && js_promise_then_pristine?()
    st = p.state
    if st == :fulfilled
      p.handled = true
      q.push_async(frame, p.value, 0)
      return nil
    if st == :rejected
      if !p.handled
        i = JS_UNHANDLED.index(p)
        JS_UNHANDLED.delete_at(i) if i != nil
      p.handled = true
      q.push_async(frame, p.value, 1)
      return nil
    js_promise_attach_raw(p, 4, frame, nil, nil)
    p.handled = true
    return nil
  a = JS:Reaction.new(nil, :fulfill, ->(x) js_sm_async_resume(frame, x, 0, js_realm().jobs))
  a.keep = frame
  b = JS:Reaction.new(nil, :reject, ->(x) js_sm_async_resume(frame, x, 1, js_realm().jobs))
  b.keep = frame
  js_perform_then(p, a, b)
  nil

# A capability for the intrinsic Promise (resolve/reject are JS functions).
-> js_new_capability
  p = js_promise_alloc(js_realm().promise_proto)
  fns = js_resolving_functions(p)
  JS:Capability.new(p, fns[0], fns[1])

# NewPromiseCapability(C)
-> js_new_capability_from(c)
  r = js_realm()
  return js_new_capability() if c == r.promise_ctor
  js_throw_type(js_to_display_short(c) + " is not a constructor") if !js_is_constructor?(c)
  slots = [nil, nil]
  ex = js_keep(r.native("", 2, ->(this, args, nt) js_capability_executor(slots, args)), [slots])
  p = js_construct(c, [ex], nil)
  js_throw_type("Promise resolve or reject function is not callable") if !js_callable?(slots[0]) || !js_callable?(slots[1])
  JS:Capability.new(p, slots[0], slots[1])

-> js_capability_executor(slots, args)
  js_throw_type("Promise executor has already been invoked with non-undefined arguments") if slots[0] != nil || slots[1] != nil
  slots[0] = js_arg(args, 0)
  slots[1] = js_arg(args, 1)
  nil

-> js_promise_ctor(args, nt)
  js_throw_type("Promise constructor cannot be invoked without 'new'") if nt == nil
  ex = js_arg(args, 0)
  js_throw_type("Promise resolver " + js_err_display(ex) + " is not a function") if !js_callable?(ex)
  p = js_promise_alloc(js_realm().proto_from(nt, "Promise"))
  fns = js_resolving_functions(p)
  begin
    js_call_arr(ex, nil, [fns[0], fns[1]])
  rescue e
    js_call_arr(fns[1], nil, [js_error_value(e)])
  p

# Ultra-fast JIT entry for p.then(fn) when JIT already guarded JS_EPOCH, p.shape == prom_sh, and fn is callable!
-> js_promise_then_jit(p, f, sh)
  target = JS:Promise.new(sh)
  if p.state == :pending
    if p.rx_kind == 0
      p.rx_kind = 1
      p.rx_target = target
      p.rx_on_f = f
      p.handled = true
      return target
    js_promise_attach_raw(p, 1, target, f, nil)
    p.handled = true
    return target
  r = js_realm()
  if p.state == :fulfilled
    r.jobs.push_rx_prom(target, f, p.value, 0)
  else
    if !p.handled
      i = JS_UNHANDLED.index(p)
      JS_UNHANDLED.delete_at(i) if i != nil
    r.jobs.push_rx_prom(target, nil, p.value, 1)
  p.handled = true
  target

# Fast intrinsic Promise.prototype.then (ZERO Capability / resolving closures / Reaction allocations!).
-> js_promise_then_fast(p, on_f, on_r)
  r = js_realm()
  if js_promise?(p) && p.shape == r.promise_shape && js_promise_pristine?(r)
    target = JS:Promise.new(r.promise_shape)
    f = js_callable?(on_f) ? on_f : nil
    rj = js_callable?(on_r) ? on_r : nil
    st = p.state
    if st == :pending
      js_promise_attach_raw(p, 1, target, f, rj)
    elsif st == :fulfilled
      r.jobs.push_rx_prom(target, f, p.value, 0)
    else
      if !p.handled
        i = JS_UNHANDLED.index(p)
        JS_UNHANDLED.delete_at(i) if i != nil
      r.jobs.push_rx_prom(target, rj, p.value, 1)
    p.handled = true
    return target
  js_promise_then_slow(p, on_f, on_r)

-> js_promise_then(p, on_f, on_r)
  js_promise_then_fast(p, on_f, on_r)

-> js_promise_then_slow(p, on_f, on_r)
  js_throw_type("Method Promise.prototype.then called on incompatible receiver " + js_err_display(p)) if !js_promise?(p)
  r = js_realm()
  c = js_species_ctor(p, r.promise_ctor)
  if c == r.promise_ctor
    target = JS:Promise.new(r.promise_shape)
    f = js_callable?(on_f) ? on_f : nil
    rj = js_callable?(on_r) ? on_r : nil
    st = p.state
    if st == :pending
      js_promise_attach_raw(p, 1, target, f, rj)
    elsif st == :fulfilled
      r.jobs.push_rx_prom(target, f, p.value, 0)
    else
      if !p.handled
        i = JS_UNHANDLED.index(p)
        JS_UNHANDLED.delete_at(i) if i != nil
      r.jobs.push_rx_prom(target, rj, p.value, 1)
    p.handled = true
    return target
  cap = js_new_capability_from(c)
  f = js_callable?(on_f) ? on_f : nil
  rj = js_callable?(on_r) ? on_r : nil
  js_perform_then(p, JS:Reaction.new(cap, :fulfill, f), JS:Reaction.new(cap, :reject, rj))
  cap.promise

-> js_species_ctor(o, dflt)
  c = jget(o, "constructor")
  return dflt if c == nil
  js_throw_type("object.constructor is not an object") if !js_object?(c)
  s = jget(c, SYM_SPECIES)
  return dflt if js_nullish?(s)
  return s if js_is_constructor?(s)
  js_throw_type("object.constructor\[Symbol.species] is not a constructor")

# PromiseResolve(%Promise%, v)
-> js_promise_resolve_value(v)
  r = js_realm()
  if !js_object?(v)
    return JS:Promise.new(r.promise_shape).init_fulfilled(v)
  if js_promise?(v)
    return v if v.shape == r.promise_shape && js_promise_pristine?(r)
    return v if jget(v, "constructor") == r.promise_ctor
  p = JS:Promise.new(r.promise_shape)
  js_promise_resolve_with(p, v)
  p

-> js_promise_resolve_fast(v)
  r = js_realm()
  return JS:Promise.new(r.promise_shape).init_fulfilled(v) if !js_object?(v)
  js_promise_resolve_value(v)

-> js_promise_resolve_ctor(c, v)
  r = js_realm()
  return js_promise_resolve_value(v) if c == r.promise_ctor
  js_throw_type("PromiseResolve called on non-object") if !js_object?(c)
  if js_promise?(v) && jget(v, "constructor") == c
    return v
  cap = js_new_capability_from(c)
  js_call_arr(cap.resolve, nil, [v])
  cap.promise

# Attach Tungsten lambdas to any value (resolved as a promise). Used by the host.
-> js_promise_then_native(v, on_ok, on_err, keep = nil)
  p = js_promise_resolve_value(v)
  a = JS:Reaction.new(nil, :fulfill, on_ok)
  a.keep = keep
  b = JS:Reaction.new(nil, :reject, on_err)
  b.keep = keep
  js_perform_then(p, a, b)
  nil

# p.then(f) where f is a Tungsten lambda; returns the derived promise.
-> js_promise_then_value(p, f, keep = nil)
  r = js_realm()
  target = JS:Promise.new(r.promise_shape)
  if keep != nil
    cap = JS:Capability.new(target, ->(x) js_promise_resolve_with(target, x), ->(x) js_promise_reject(target, x))
    a = JS:Reaction.new(cap, :fulfill, f)
    a.keep = keep
    b = JS:Reaction.new(cap, :reject, nil)
    js_perform_then(p, a, b)
    return target
  st = p.state
  if st == :pending
    js_promise_attach_raw(p, 1, target, f, nil)
  elsif st == :fulfilled
    r.jobs.push_rx_prom(target, f, p.value, 0)
  else
    if !p.handled
      i = JS_UNHANDLED.index(p)
      JS_UNHANDLED.delete_at(i) if i != nil
    r.jobs.push_rx_prom(target, nil, p.value, 1)
  p.handled = true
  target

-> js_promise_finally(p, on_fin)
  js_throw_type("Promise.prototype.finally called on non-object") if !js_object?(p)
  c = js_species_ctor(p, js_realm().promise_ctor)
  return js_invoke(p, "then", [on_fin, on_fin]) if !js_callable?(on_fin)
  r = js_realm()
  tf = js_keep(r.native("", 1, ->(this, args, nt) js_finally_then(c, on_fin, js_arg(args, 0), false)), [c, on_fin])
  cf = js_keep(r.native("", 1, ->(this, args, nt) js_finally_then(c, on_fin, js_arg(args, 0), true)), [c, on_fin])
  js_invoke(p, "then", [tf, cf])

-> js_finally_then(c, on_fin, v, thrown)
  res = js_call_arr(on_fin, nil, JS_NO_ARGS)
  pr = js_promise_resolve_ctor(c, res)
  r = js_realm()
  k = js_keep(thrown ? r.native("", 0, ->(this, args, nt) js_throw_value(v)) : r.native("", 0, ->(this, args, nt) v), [v])
  js_invoke(pr, "then", [k])

# ---- combinators ----

-> js_promise_combinator(c, iterable, mode)
  cap = js_new_capability_from(c)
  rec = nil
  begin
    resolve_fn = js_get_value(c, "resolve")
    js_throw_type("Promise resolve is not a function") if !js_callable?(resolve_fn)
    rec = js_get_iterator(iterable)
    r = js_realm()
    values = []
    remaining = [1]
    i = 0
    while true
      x = js_iter_step(rec)
      break if x == JS_ITER_DONE
      values.push(nil)
      remaining[0] += 1
      p = js_call_arr(resolve_fn, c, [x])
      js_combinator_attach(c, cap, p, i, values, remaining, mode)
      i += 1
    remaining[0] -= 1
    if remaining[0] == 0 && mode != :race
      if mode == :any
        js_call_arr(cap.reject, nil, [js_aggregate_error_ctor([r.adopt_array(values), "All promises were rejected"], nil)])
      else
        js_call_arr(cap.resolve, nil, [r.adopt_array(values)])
  rescue e
    js_iter_close_quiet(rec) if rec != nil && !rec.done
    js_call_arr(cap.reject, nil, [js_error_value(e)])
  cap.promise

-> js_combinator_attach(c, cap, p, i, values, remaining, mode)
  r = js_realm()
  done = [false]
  if mode == :all
    ok = js_keep(r.native("", 1, ->(this, args, nt) js_comb_settle(cap, values, remaining, i, done, js_arg(args, 0), :value)), [cap, values, remaining, done])
    js_invoke(p, "then", [ok, cap.reject])
  elsif mode == :all_settled
    ok = js_keep(r.native("", 1, ->(this, args, nt) js_comb_settle(cap, values, remaining, i, done, js_settled_obj("fulfilled", "value", js_arg(args, 0)), :value)), [cap, values, remaining, done])
    bad = js_keep(r.native("", 1, ->(this, args, nt) js_comb_settle(cap, values, remaining, i, done, js_settled_obj("rejected", "reason", js_arg(args, 0)), :value)), [cap, values, remaining, done])
    js_invoke(p, "then", [ok, bad])
  elsif mode == :any
    bad = js_keep(r.native("", 1, ->(this, args, nt) js_comb_settle(cap, values, remaining, i, done, js_arg(args, 0), :error)), [cap, values, remaining, done])
    js_invoke(p, "then", [cap.resolve, bad])
  else
    js_invoke(p, "then", [cap.resolve, cap.reject])
  nil

-> js_settled_obj(status, key, v)
  o = js_realm().new_object
  o.put_own("status", status)
  o.put_own(key, v)
  o

-> js_comb_settle(cap, values, remaining, i, done, v, kind)
  return nil if done[0]
  done[0] = true
  values[i] = v
  remaining[0] -= 1
  if remaining[0] == 0
    r = js_realm()
    if kind == :error
      js_call_arr(cap.reject, nil, [js_aggregate_error_ctor([r.new_array(values), "All promises were rejected"], nil)])
    else
      js_call_arr(cap.resolve, nil, [r.new_array(values)])
  nil

-> js_promise_keyed_combinator(c, promises, settled)
  cap = js_new_capability_from(c)
  begin
    resolve_fn = js_get_value(c, "resolve")
    js_throw_type("Promise resolve is not a function") if !js_callable?(resolve_fn)
    js_throw_type("Promise." + (settled ? "allSettledKeyed" : "allKeyed") + " requires an object") if !js_object?(promises)
    all_keys = jown_keys(promises)
    keys = []
    values = []
    remaining = [1]
    r = js_realm()
    ki = 0
    while ki < all_keys.size
      k = all_keys[ki]
      d = jget_own_property(promises, k)
      if d != nil && d.enumerable == true
        pv = jget(promises, k)
        idx = keys.size
        keys.push(k)
        values.push(nil)
        remaining[0] += 1
        p = js_call_arr(resolve_fn, c, [pv])
        js_keyed_attach(cap, p, idx, keys, values, remaining, settled)
      ki += 1
    remaining[0] -= 1
    if remaining[0] == 0
      js_call_arr(cap.resolve, nil, [js_keyed_result_obj(keys, values)])
  rescue e
    js_call_arr(cap.reject, nil, [js_error_value(e)])
  cap.promise

-> js_keyed_result_obj(keys, values)
  o = js_new_object(nil)
  i = 0
  while i < keys.size
    o.define(keys[i], values[i], ATTR_ALL)
    i += 1
  o

-> js_keyed_attach(cap, p, idx, keys, values, remaining, settled)
  r = js_realm()
  done = [false]
  if !settled
    ok = js_keep(r.native("", 1, ->(this, args, nt) js_keyed_settle(cap, keys, values, remaining, idx, done, js_arg(args, 0))), [cap, keys, values, remaining, done])
    js_invoke(p, "then", [ok, cap.reject])
  else
    ok = js_keep(r.native("", 1, ->(this, args, nt) js_keyed_settle(cap, keys, values, remaining, idx, done, js_settled_obj("fulfilled", "value", js_arg(args, 0)))), [cap, keys, values, remaining, done])
    bad = js_keep(r.native("", 1, ->(this, args, nt) js_keyed_settle(cap, keys, values, remaining, idx, done, js_settled_obj("rejected", "reason", js_arg(args, 0)))), [cap, keys, values, remaining, done])
    js_invoke(p, "then", [ok, bad])
  nil

-> js_keyed_settle(cap, keys, values, remaining, idx, done, v)
  return nil if done[0]
  done[0] = true
  values[idx] = v
  remaining[0] -= 1
  if remaining[0] == 0
    js_call_arr(cap.resolve, nil, [js_keyed_result_obj(keys, values)])
  nil

-> js_promise_with_resolvers(c)
  cap = js_new_capability_from(c)
  o = js_realm().new_object
  o.put_own("promise", cap.promise)
  o.put_own("resolve", cap.resolve)
  o.put_own("reject", cap.reject)
  o

-> js_promise_try(c, args)
  js_throw_type("Promise.try called on non-object") if !js_object?(c)
  v = nil
  threw = false
  err = nil
  begin
    v = js_call_arr(js_arg(args, 0), nil, args.size > 1 ? js_arr_copy(args, 1, args.size - 1) : JS_NO_ARGS)
  rescue e
    threw = true
    err = js_error_value(e)
  if threw
    cap = js_new_capability_from(c)
    js_call_arr(cap.reject, nil, [err])
    return cap.promise
  js_promise_resolve_ctor(c, v)

js_install(->(r) js_install_promise(r))

-> js_install_promise(r)
  pp = js_new_object(r.object_proto)
  pc = r.constructor("Promise", 1, ->(this, args, nt) js_promise_ctor(args, nt), pp)
  th = r.method(pp, "then", 2, ->(this, args, nt) js_promise_then(this, js_arg(args, 0), js_arg(args, 1)))
  r.set_intrinsic("%PromiseProto_then%", th)
  r.method(pp, "catch", 1, ->(this, args, nt) js_invoke(this, "then", [nil, js_arg(args, 0)]))
  r.method(pp, "finally", 1, ->(this, args, nt) js_promise_finally(this, js_arg(args, 0)))
  pp.define(SYM_TO_STRING_TAG, "Promise", ATTR_C)
  res_fn = r.method(pc, "resolve", 1, ->(this, args, nt) js_promise_resolve_ctor(this, js_arg(args, 0)))
  r.set_intrinsic("%Promise_resolve%", res_fn)
  r.method(pc, "reject", 1, ->(this, args, nt) js_promise_reject_static(this, js_arg(args, 0)))
  r.method(pc, "all", 1, ->(this, args, nt) js_promise_combinator(this, js_arg(args, 0), :all))
  r.method(pc, "allSettled", 1, ->(this, args, nt) js_promise_combinator(this, js_arg(args, 0), :all_settled))
  r.method(pc, "allKeyed", 1, ->(this, args, nt) js_promise_keyed_combinator(this, js_arg(args, 0), false))
  r.method(pc, "allSettledKeyed", 1, ->(this, args, nt) js_promise_keyed_combinator(this, js_arg(args, 0), true))
  r.method(pc, "any", 1, ->(this, args, nt) js_promise_combinator(this, js_arg(args, 0), :any))
  r.method(pc, "race", 1, ->(this, args, nt) js_promise_combinator(this, js_arg(args, 0), :race))
  r.method(pc, "withResolvers", 0, ->(this, args, nt) js_promise_with_resolvers(this))
  r.method(pc, "try", 1, ->(this, args, nt) js_promise_try(this, args))
  r.getter(pc, SYM_SPECIES, ->(this, args, nt) this)
  js_mark_proto(pc)
  r.promise_proto = pp
  r.promise_ctor = pc
  r.promise_then_fn = th
  r.promise_resolve_fn = res_fn
  r.promise_species_acc = pc.get_own(SYM_SPECIES)
  r.promise_shape = js_root_shape(pp, 0, 2)
  JS_PROM_PRISTINE[0] = -1
  JS_PROM_PRISTINE[1] = 0
  nil

-> js_promise_reject_static(c, v)
  r = js_realm()
  if c == r.promise_ctor
    p = JS:Promise.new(r.promise_shape)
    js_promise_reject(p, v)
    return p
  cap = js_new_capability_from(c)
  js_call_arr(cap.reject, nil, [v])
  cap.promise
