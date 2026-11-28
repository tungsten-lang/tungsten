# runtime/b_promise — High-speed Promise (ES2024 plus withResolvers / try) and microtask glue.
#
# Inline single-reaction slots on JS:Promise avoid allocating Capability / resolving closures /
# Reaction / reactions[] on intrinsic Promise chains. Reactions run on Realm#jobs's flat
# power-of-2 ring buffer with zero Tungsten closure allocations per microtask.

in JS

JS_SLOW_SENTINEL = wvalue_from_bits(6)

fn js_is_slow_bits(b) (i64) i64
  b == 6 ? 1 : 0

# Fast 4-insn check: is WValue `b` a Number OR undefined/false/true (<= 2)?
fn js_is_prim_num_or_small(b) (i64) i64
  ll <<~IR
    %x = sub i64 %b, 281474976710656
    %isn = icmp ult i64 %x, u0xFFF0000000000001
    %iss = icmp ule i64 %b, 2
    %ok = or i1 %isn, %iss
    %r = zext i1 %ok to i64
    ret i64 %r
  IR

# Reaction slot modes on JS:Promise (@rx_kind):
#   0 = none
#   1 = single intrinsic .then() target: @rx_target = target JS:Promise (or nil), @rx_on_f, @rx_on_r
#   2 = single general JS:Reaction pair: @rx_on_f = fr, @rx_on_r = rr
#   3 = multiple reactions in @reactions: array of [kind, a, b, c]
#   4 = single stackless SmFrame awaiting this promise: @rx_target = frame
#   5 = zero-closure Promise.all waiter: @rx_target = PromiseAllState, @rx_on_f = idx
#   6 = zero-frame 2-await async chain: @rx_target = target JS:Promise, @rx_on_f = fn2

+ PromiseAllState
  rw :target, :values, :rem, :settled
  -> new(@target, @values, @rem)
    @settled = false

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
#   [0]=state, [1]=value, [2]=rx_kind, [3]=rx_target, [4]=rx_on_f, [5]=rx_on_r, [6]=q_head, [7]=q_tail, [8]=q_mask
JS_PROM_OFFS = i64[9]
JS_PROM_DRAIN_OUT = i64[4]   # [cur_target_bits, next_target_bits, next_handler_bits, last_res_bits]
JS_PIPE_ARGS = i64[20]       # param block for js_drain_async_pipe_all_ll

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
  q2.mask = 33333
  qb = wvalue_bits(q2) ## i64
  JS_PROM_OFFS[6] = js_find_ivar_off(qb, wvalue_bits(11111) ## i64)
  JS_PROM_OFFS[7] = js_find_ivar_off(qb, wvalue_bits(22222) ## i64)
  JS_PROM_OFFS[8] = js_find_ivar_off(qb, wvalue_bits(33333) ## i64)
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

# Pure-LLVM atomic batch drain for JOB_ASYNC_PIPE jobs targeting one Promise.all with a pure compiled stage2!
# Returns 1 if ALL n_total items verified, executed cleanly, settled their promises, and cleared the queue; 0 otherwise (ZERO promise/queue mutations!).
fn js_drain_async_pipe_all_ll(args_p) (i64) i64
  ll <<~IR
    %ap = inttoptr i64 %args_p to ptr
    %p0 = load i64, ptr %ap, align 8
    %a1 = getelementptr i64, ptr %ap, i64 1
    %v0 = load i64, ptr %a1, align 8
    %a2 = getelementptr i64, ptr %ap, i64 2
    %st_b = load i64, ptr %a2, align 8
    %a3 = getelementptr i64, ptr %ap, i64 3
    %cell_b = load i64, ptr %a3, align 8
    %a4 = getelementptr i64, ptr %ap, i64 4
    %fp2 = load i64, ptr %a4, align 8
    %a5 = getelementptr i64, ptr %ap, i64 5
    %fn2_b = load i64, ptr %a5, align 8
    %a6 = getelementptr i64, ptr %ap, i64 6
    %pend_b = load i64, ptr %a6, align 8
    %a7 = getelementptr i64, ptr %ap, i64 7
    %fulf_b = load i64, ptr %a7, align 8
    %a8 = getelementptr i64, ptr %ap, i64 8
    %vals_pi = load i64, ptr %a8, align 8
    %a9 = getelementptr i64, ptr %ap, i64 9
    %offs_pi = load i64, ptr %a9, align 8
    %a10 = getelementptr i64, ptr %ap, i64 10
    %qk_pi = load i64, ptr %a10, align 8
    %a11 = getelementptr i64, ptr %ap, i64 11
    %qf_pi = load i64, ptr %a11, align 8
    %a12 = getelementptr i64, ptr %ap, i64 12
    %qa_pi = load i64, ptr %a12, align 8
    %a13 = getelementptr i64, ptr %ap, i64 13
    %qb_pi = load i64, ptr %a13, align 8
    %a14 = getelementptr i64, ptr %ap, i64 14
    %qc_pi = load i64, ptr %a14, align 8
    %a15 = getelementptr i64, ptr %ap, i64 15
    %qh = load i64, ptr %a15, align 8
    %a16 = getelementptr i64, ptr %ap, i64 16
    %qmask = load i64, ptr %a16, align 8
    %a17 = getelementptr i64, ptr %ap, i64 17
    %ntot = load i64, ptr %a17, align 8
    %a18 = getelementptr i64, ptr %ap, i64 18
    %rk5_b = load i64, ptr %a18, align 8
    %a19 = getelementptr i64, ptr %ap, i64 19
    %int0_b = load i64, ptr %a19, align 8

    %f2 = inttoptr i64 %fp2 to ptr
    %vals_p = inttoptr i64 %vals_pi to ptr
    %op = inttoptr i64 %offs_pi to ptr
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
    %qk_p = inttoptr i64 %qk_pi to ptr
    %qf_p = inttoptr i64 %qf_pi to ptr
    %qa_p = inttoptr i64 %qa_pi to ptr
    %qb_p = inttoptr i64 %qb_pi to ptr
    %qc_p = inttoptr i64 %qc_pi to ptr
    br label %v_loop

  v_loop:
    %k = phi i64 [ 0, %0 ], [ %k_next, %v_ok ]
    %v_done = icmp sge i64 %k, %ntot
    br i1 %v_done, label %c_loop, label %v_body

  v_body:
    %is_k0 = icmp eq i64 %k, 0
    br i1 %is_k0, label %v_use0, label %v_loadq

  v_use0:
    br label %v_chk

  v_loadq:
    %km1 = sub i64 %k, 1
    %s0 = add i64 %qh, %km1
    %slot = and i64 %s0, %qmask
    %kptr = getelementptr i64, ptr %qk_p, i64 %slot
    %jk = load i64, ptr %kptr, align 8
    %ok_jk = icmp eq i64 %jk, 8
    br i1 %ok_jk, label %v_chk_fl, label %bail

  v_chk_fl:
    %fptr = getelementptr i64, ptr %qf_p, i64 %slot
    %jfl = load i64, ptr %fptr, align 8
    %ok_fl = icmp eq i64 %jfl, 3
    br i1 %ok_fl, label %v_chk_cb, label %bail

  v_chk_cb:
    %bptr = getelementptr i64, ptr %qb_p, i64 %slot
    %jcb = load i64, ptr %bptr, align 8
    %ok_cb = icmp eq i64 %jcb, %cell_b
    br i1 %ok_cb, label %v_ld_pv, label %bail

  v_ld_pv:
    %aptr = getelementptr i64, ptr %qa_p, i64 %slot
    %pq = load i64, ptr %aptr, align 8
    %cptr = getelementptr i64, ptr %qc_p, i64 %slot
    %vq = load i64, ptr %cptr, align 8
    br label %v_chk

  v_chk:
    %cp = phi i64 [ %p0, %v_use0 ], [ %pq, %v_ld_pv ]
    %cv = phi i64 [ %v0, %v_use0 ], [ %vq, %v_ld_pv ]
    ; Check cv is Number or nil/false/true (<=2) so pure stage2 cannot throw or invoke valueOf!
    %vx = sub i64 %cv, 281474976710656
    %visn = icmp ult i64 %vx, u0xFFF0000000000001
    br i1 %visn, label %v_chk_p, label %v_chk_v2

  v_chk_v2:
    %vsm = icmp ule i64 %cv, 2
    br i1 %vsm, label %v_chk_p, label %bail

  v_chk_p:
    ; Verify cp is a WObject pointer with state==:pending, rx_kind==5, rx_target==st_b, 0<=idx<ntot!
    %ptag = and i64 %cp, 7
    %isp = icmp eq i64 %ptag, 4
    br i1 %isp, label %v_chk_p2, label %bail

  v_chk_p2:
    %p_hi = and i64 %cp, u0xFFFF000000000000
    %p_hiz = icmp eq i64 %p_hi, 0
    br i1 %p_hiz, label %v_chk_p3, label %bail

  v_chk_p3:
    %praw = sub i64 %cp, 4
    %pp = inttoptr i64 %praw to ptr
    %stp = getelementptr i8, ptr %pp, i64 %off_st
    %pst = load i64, ptr %stp, align 8
    %ok_st = icmp eq i64 %pst, %pend_b
    br i1 %ok_st, label %v_chk_rk, label %bail

  v_chk_rk:
    %rkp = getelementptr i8, ptr %pp, i64 %off_rk
    %prk = load i64, ptr %rkp, align 8
    %ok_rk = icmp eq i64 %prk, %rk5_b
    br i1 %ok_rk, label %v_chk_tg, label %bail

  v_chk_tg:
    %tgp = getelementptr i8, ptr %pp, i64 %off_tg
    %ptg = load i64, ptr %tgp, align 8
    %ok_tg = icmp eq i64 %ptg, %st_b
    br i1 %ok_tg, label %v_chk_ix, label %bail

  v_chk_ix:
    %ofp = getelementptr i8, ptr %pp, i64 %off_of
    %pof = load i64, ptr %ofp, align 8
    %idx = sub i64 %pof, %int0_b
    %ok_ix = icmp ult i64 %idx, %ntot
    br i1 %ok_ix, label %v_call, label %bail

  v_call:
    %res = call i64 %f2(i64 %fn2_b, i64 0, i64 1, i64 %cv, i64 0, i64 0, i64 0, i64 0)
    %is_slow = icmp eq i64 %res, 6
    br i1 %is_slow, label %bail, label %v_chk_res

  v_chk_res:
    %rx = sub i64 %res, 281474976710656
    %risn = icmp ult i64 %rx, u0xFFF0000000000001
    br i1 %risn, label %v_store, label %v_chk_r2

  v_chk_r2:
    %rsm = icmp ule i64 %res, 2
    br i1 %rsm, label %v_store, label %v_chk_rs

  v_chk_rs:
    %rst = and i64 %res, u0xFFFF000000000001
    %riss = icmp eq i64 %rst, u0xFFF9000000000000
    br i1 %riss, label %v_store, label %bail

  v_store:
    %vp = getelementptr i64, ptr %vals_p, i64 %idx
    store i64 %res, ptr %vp, align 8
    br label %v_ok

  v_ok:
    %k_next = add i64 %k, 1
    br label %v_loop

  ; Pass 2: ALL n_total items succeeded! Commit promise fulfillments and clear queue slots!
  c_loop:
    %j = phi i64 [ 0, %v_loop ], [ %j_next, %c_next ]
    %c_done = icmp sge i64 %j, %ntot
    br i1 %c_done, label %ret_ok, label %c_body

  c_body:
    %is_j0 = icmp eq i64 %j, 0
    br i1 %is_j0, label %c_use0, label %c_loadq

  c_use0:
    br label %c_settle

  c_loadq:
    %jm1 = sub i64 %j, 1
    %cs0 = add i64 %qh, %jm1
    %cslot = and i64 %cs0, %qmask
    %captr = getelementptr i64, ptr %qa_p, i64 %cslot
    %cpq = load i64, ptr %captr, align 8
    store i64 0, ptr %captr, align 8
    %cbptr = getelementptr i64, ptr %qb_p, i64 %cslot
    store i64 0, ptr %cbptr, align 8
    %ccptr = getelementptr i64, ptr %qc_p, i64 %cslot
    store i64 0, ptr %ccptr, align 8
    br label %c_settle

  c_settle:
    %sp = phi i64 [ %p0, %c_use0 ], [ %cpq, %c_loadq ]
    %sraw = sub i64 %sp, 4
    %spp = inttoptr i64 %sraw to ptr
    %sofp = getelementptr i8, ptr %spp, i64 %off_of
    %spof = load i64, ptr %sofp, align 8
    %sidx = sub i64 %spof, %int0_b
    %svp = getelementptr i64, ptr %vals_p, i64 %sidx
    %sval = load i64, ptr %svp, align 8
    %sstp = getelementptr i8, ptr %spp, i64 %off_st
    %svlp = getelementptr i8, ptr %spp, i64 %off_vl
    %srkp = getelementptr i8, ptr %spp, i64 %off_rk
    %stgp = getelementptr i8, ptr %spp, i64 %off_tg
    %sorp = getelementptr i8, ptr %spp, i64 %off_or
    store i64 %fulf_b, ptr %sstp, align 8
    store i64 %sval, ptr %svlp, align 8
    store i64 %int0_b, ptr %srkp, align 8
    store i64 0, ptr %stgp, align 8
    store i64 0, ptr %sofp, align 8
    store i64 0, ptr %sorp, align 8
    br label %c_next

  c_next:
    %j_next = add i64 %j, 1
    br label %c_loop

  ret_ok:
    ret i64 1

  bail:
    ret i64 0
  IR

# Pure-LLVM atomic batch drain for SM_AWAIT_PROMISE_ALL when queue holds ONLY the n matching JOB_ASYNC_PIPE jobs!
# Verifies every arr[k] == q.qa[(qh+k)&mask] is pending with rx_kind == 0 (zero external observers), runs pure fp2,
# fills values[k], settles all arr[k], clears q slots, and returns 1 (else 0 with ZERO promise/queue mutations!).
fn js_drain_async_pipe_arr_ll(args_p) (i64) i64
  ll <<~IR
    %ap = inttoptr i64 %args_p to ptr
    %arr_pi = load i64, ptr %ap, align 8
    %a1 = getelementptr i64, ptr %ap, i64 1
    %cell_b = load i64, ptr %a1, align 8
    %a2 = getelementptr i64, ptr %ap, i64 2
    %fp2 = load i64, ptr %a2, align 8
    %a3 = getelementptr i64, ptr %ap, i64 3
    %fn2_b = load i64, ptr %a3, align 8
    %a4 = getelementptr i64, ptr %ap, i64 4
    %pend_b = load i64, ptr %a4, align 8
    %a5 = getelementptr i64, ptr %ap, i64 5
    %fulf_b = load i64, ptr %a5, align 8
    %a6 = getelementptr i64, ptr %ap, i64 6
    %vals_pi = load i64, ptr %a6, align 8
    %a7 = getelementptr i64, ptr %ap, i64 7
    %offs_pi = load i64, ptr %a7, align 8
    %a8 = getelementptr i64, ptr %ap, i64 8
    %qk_pi = load i64, ptr %a8, align 8
    %a9 = getelementptr i64, ptr %ap, i64 9
    %qf_pi = load i64, ptr %a9, align 8
    %a10 = getelementptr i64, ptr %ap, i64 10
    %qa_pi = load i64, ptr %a10, align 8
    %a11 = getelementptr i64, ptr %ap, i64 11
    %qb_pi = load i64, ptr %a11, align 8
    %a12 = getelementptr i64, ptr %ap, i64 12
    %qc_pi = load i64, ptr %a12, align 8
    %a13 = getelementptr i64, ptr %ap, i64 13
    %qh = load i64, ptr %a13, align 8
    %a14 = getelementptr i64, ptr %ap, i64 14
    %qmask = load i64, ptr %a14, align 8
    %a15 = getelementptr i64, ptr %ap, i64 15
    %ntot = load i64, ptr %a15, align 8
    %a16 = getelementptr i64, ptr %ap, i64 16
    %int0_b = load i64, ptr %a16, align 8
    %a17 = getelementptr i64, ptr %ap, i64 17
    %psh_b = load i64, ptr %a17, align 8

    %f2 = inttoptr i64 %fp2 to ptr
    %arr_p = inttoptr i64 %arr_pi to ptr
    %vals_p = inttoptr i64 %vals_pi to ptr
    %op = inttoptr i64 %offs_pi to ptr
    %off_st = load i64, ptr %op, align 8
    %op1 = getelementptr i64, ptr %op, i64 1
    %off_vl = load i64, ptr %op1, align 8
    %op2 = getelementptr i64, ptr %op, i64 2
    %off_rk = load i64, ptr %op2, align 8
    %qk_p = inttoptr i64 %qk_pi to ptr
    %qf_p = inttoptr i64 %qf_pi to ptr
    %qa_p = inttoptr i64 %qa_pi to ptr
    %qb_p = inttoptr i64 %qb_pi to ptr
    %qc_p = inttoptr i64 %qc_pi to ptr
    br label %v_loop

  v_loop:
    %k = phi i64 [ 0, %0 ], [ %k_next, %v_ok ]
    %v_done = icmp sge i64 %k, %ntot
    br i1 %v_done, label %c_loop, label %v_body

  v_body:
    %s0 = add i64 %qh, %k
    %slot = and i64 %s0, %qmask
    %kptr = getelementptr i64, ptr %qk_p, i64 %slot
    %jk = load i64, ptr %kptr, align 8
    %ok_jk = icmp eq i64 %jk, 8
    br i1 %ok_jk, label %v_fl, label %bail

  v_fl:
    %fptr = getelementptr i64, ptr %qf_p, i64 %slot
    %jfl = load i64, ptr %fptr, align 8
    %ok_fl = icmp eq i64 %jfl, 3
    br i1 %ok_fl, label %v_cb, label %bail

  v_cb:
    %bptr = getelementptr i64, ptr %qb_p, i64 %slot
    %jcb = load i64, ptr %bptr, align 8
    %ok_cb = icmp eq i64 %jcb, %cell_b
    br i1 %ok_cb, label %v_match, label %bail

  v_match:
    %aptr = getelementptr i64, ptr %qa_p, i64 %slot
    %pq = load i64, ptr %aptr, align 8
    %arr_ep = getelementptr i64, ptr %arr_p, i64 %k
    %pa = load i64, ptr %arr_ep, align 8
    %ok_eq = icmp eq i64 %pq, %pa
    br i1 %ok_eq, label %v_chk_v, label %bail

  v_chk_v:
    %cptr = getelementptr i64, ptr %qc_p, i64 %slot
    %cv = load i64, ptr %cptr, align 8
    %vx = sub i64 %cv, 281474976710656
    %visn = icmp ult i64 %vx, u0xFFF0000000000001
    br i1 %visn, label %v_chk_p, label %v_chk_v2

  v_chk_v2:
    %vsm = icmp ule i64 %cv, 2
    br i1 %vsm, label %v_chk_p, label %bail

  v_chk_p:
    %ptag = and i64 %pq, 7
    %isp = icmp eq i64 %ptag, 4
    br i1 %isp, label %v_chk_p2, label %bail

  v_chk_p2:
    %p_hi = and i64 %pq, u0xFFFF000000000000
    %p_hiz = icmp eq i64 %p_hi, 0
    br i1 %p_hiz, label %v_chk_p3, label %bail

  v_chk_p3:
    %praw = sub i64 %pq, 4
    %pp = inttoptr i64 %praw to ptr
    %shp = getelementptr i8, ptr %pp, i64 8
    %shv = load i64, ptr %shp, align 8
    %ok_sh = icmp eq i64 %shv, %psh_b
    br i1 %ok_sh, label %v_chk_st, label %bail

  v_chk_st:
    %stp = getelementptr i8, ptr %pp, i64 %off_st
    %pst = load i64, ptr %stp, align 8
    %ok_st = icmp eq i64 %pst, %pend_b
    br i1 %ok_st, label %v_chk_rk, label %bail

  v_chk_rk:
    %rkp = getelementptr i8, ptr %pp, i64 %off_rk
    %prk = load i64, ptr %rkp, align 8
    %ok_rk = icmp eq i64 %prk, %int0_b
    br i1 %ok_rk, label %v_call, label %bail

  v_call:
    %res = call i64 %f2(i64 %fn2_b, i64 0, i64 1, i64 %cv, i64 0, i64 0, i64 0, i64 0)
    %is_slow = icmp eq i64 %res, 6
    br i1 %is_slow, label %bail, label %v_chk_res

  v_chk_res:
    %rx = sub i64 %res, 281474976710656
    %risn = icmp ult i64 %rx, u0xFFF0000000000001
    br i1 %risn, label %v_store, label %v_chk_r2

  v_chk_r2:
    %rsm = icmp ule i64 %res, 2
    br i1 %rsm, label %v_store, label %v_chk_rs

  v_chk_rs:
    %rst = and i64 %res, u0xFFFF000000000001
    %riss = icmp eq i64 %rst, u0xFFF9000000000000
    br i1 %riss, label %v_store, label %bail

  v_store:
    %vp = getelementptr i64, ptr %vals_p, i64 %k
    store i64 %res, ptr %vp, align 8
    br label %v_ok

  v_ok:
    %k_next = add i64 %k, 1
    br label %v_loop

  c_loop:
    %j = phi i64 [ 0, %v_loop ], [ %j_next, %c_next ]
    %c_done = icmp sge i64 %j, %ntot
    br i1 %c_done, label %ret_ok, label %c_body

  c_body:
    %cs0 = add i64 %qh, %j
    %cslot = and i64 %cs0, %qmask
    %captr = getelementptr i64, ptr %qa_p, i64 %cslot
    %sp = load i64, ptr %captr, align 8
    store i64 0, ptr %captr, align 8
    %cbptr = getelementptr i64, ptr %qb_p, i64 %cslot
    store i64 0, ptr %cbptr, align 8
    %ccptr = getelementptr i64, ptr %qc_p, i64 %cslot
    store i64 0, ptr %ccptr, align 8
    %svp = getelementptr i64, ptr %vals_p, i64 %j
    %sval = load i64, ptr %svp, align 8
    %sraw = sub i64 %sp, 4
    %spp = inttoptr i64 %sraw to ptr
    %sstp = getelementptr i8, ptr %spp, i64 %off_st
    %svlp = getelementptr i8, ptr %spp, i64 %off_vl
    store i64 %fulf_b, ptr %sstp, align 8
    store i64 %sval, ptr %svlp, align 8
    br label %c_next

  c_next:
    %j_next = add i64 %j, 1
    br label %c_loop

  ret_ok:
    ret i64 1

  bail:
    ret i64 0
  IR

# Pure-LLVM zero-dispatch fast enqueue for `fast_kind == 2` 2-await async functions with pure compiled stage1!
# Verifies epoch, cell1==fn1, q.mask unchanged, q not full, x0 primitive -> calls fp1(x0) -> writes JOB_ASYNC_PIPE!
fn js_sm_fast2_enq_ll(cache_p, prom_b, x0_b) (i64 i64 i64) i64
  ll <<~IR
    %vx = sub i64 %x0_b, 281474976710656
    %visn = icmp ult i64 %vx, u0xFFF0000000000001
    %vsm = icmp ule i64 %x0_b, 2
    %vok = or i1 %visn, %vsm
    br i1 %vok, label %chk_ep, label %bail

  chk_ep:
    %cp = inttoptr i64 %cache_p to ptr
    %ep_pi = load i64, ptr %cp, align 8
    %ep_p = inttoptr i64 %ep_pi to ptr
    %ep_cur = load i64, ptr %ep_p, align 8
    %c1 = getelementptr i64, ptr %cp, i64 1
    %ep_exp = load i64, ptr %c1, align 8
    %ep_ok = icmp eq i64 %ep_cur, %ep_exp
    br i1 %ep_ok, label %chk_c1, label %bail

  chk_c1:
    %c2 = getelementptr i64, ptr %cp, i64 2
    %c1_pi = load i64, ptr %c2, align 8
    %c1_p = inttoptr i64 %c1_pi to ptr
    %c1_vp = getelementptr i8, ptr %c1_p, i64 8
    %fn1_cur = load i64, ptr %c1_vp, align 8
    %c3 = getelementptr i64, ptr %cp, i64 3
    %fn1_exp = load i64, ptr %c3, align 8
    %fn1_ok = icmp eq i64 %fn1_cur, %fn1_exp
    br i1 %fn1_ok, label %chk_q, label %bail

  chk_q:
    %c6 = getelementptr i64, ptr %cp, i64 6
    %q_pi = load i64, ptr %c6, align 8
    %qp = inttoptr i64 %q_pi to ptr
    %c15 = getelementptr i64, ptr %cp, i64 15
    %int0_b = load i64, ptr %c15, align 8
    %c16 = getelementptr i64, ptr %cp, i64 16
    %off_qm = load i64, ptr %c16, align 8
    %qmp = getelementptr i8, ptr %qp, i64 %off_qm
    %qm_box = load i64, ptr %qmp, align 8
    %qm_cur = sub i64 %qm_box, %int0_b
    %c9 = getelementptr i64, ptr %cp, i64 9
    %qm_exp = load i64, ptr %c9, align 8
    %qm_ok = icmp eq i64 %qm_cur, %qm_exp
    br i1 %qm_ok, label %chk_space, label %bail

  chk_space:
    %c7 = getelementptr i64, ptr %cp, i64 7
    %off_qh = load i64, ptr %c7, align 8
    %c8 = getelementptr i64, ptr %cp, i64 8
    %off_qt = load i64, ptr %c8, align 8
    %qhp = getelementptr i8, ptr %qp, i64 %off_qh
    %qtp = getelementptr i8, ptr %qp, i64 %off_qt
    %qh_box = load i64, ptr %qhp, align 8
    %qt_box = load i64, ptr %qtp, align 8
    %qh = sub i64 %qh_box, %int0_b
    %qt = sub i64 %qt_box, %int0_b
    %qt1 = add i64 %qt, 1
    %nt = and i64 %qt1, %qm_exp
    %full = icmp eq i64 %nt, %qh
    br i1 %full, label %bail, label %do_call

  do_call:
    %c5 = getelementptr i64, ptr %cp, i64 5
    %fp1_i = load i64, ptr %c5, align 8
    %fp1 = inttoptr i64 %fp1_i to ptr
    %val = call i64 %fp1(i64 %fn1_exp, i64 0, i64 1, i64 %x0_b, i64 0, i64 0, i64 0, i64 0)
    %is_slow = icmp eq i64 %val, 6
    br i1 %is_slow, label %bail, label %chk_val

  chk_val:
    %rx = sub i64 %val, 281474976710656
    %risn = icmp ult i64 %rx, u0xFFF0000000000001
    %rsm = icmp ule i64 %val, 2
    %rok = or i1 %risn, %rsm
    br i1 %rok, label %enq, label %bail

  enq:
    %c4 = getelementptr i64, ptr %cp, i64 4
    %cell2_b = load i64, ptr %c4, align 8
    %c10 = getelementptr i64, ptr %cp, i64 10
    %qk_pi = load i64, ptr %c10, align 8
    %qk_p = inttoptr i64 %qk_pi to ptr
    %c11 = getelementptr i64, ptr %cp, i64 11
    %qf_pi = load i64, ptr %c11, align 8
    %qf_p = inttoptr i64 %qf_pi to ptr
    %c12 = getelementptr i64, ptr %cp, i64 12
    %qa_pi = load i64, ptr %c12, align 8
    %qa_p = inttoptr i64 %qa_pi to ptr
    %c13 = getelementptr i64, ptr %cp, i64 13
    %qb_pi = load i64, ptr %c13, align 8
    %qb_p = inttoptr i64 %qb_pi to ptr
    %c14 = getelementptr i64, ptr %cp, i64 14
    %qc_pi = load i64, ptr %c14, align 8
    %qc_p = inttoptr i64 %qc_pi to ptr
    %kp = getelementptr i64, ptr %qk_p, i64 %qt
    store i64 8, ptr %kp, align 8
    %fp = getelementptr i64, ptr %qf_p, i64 %qt
    store i64 3, ptr %fp, align 8
    %ap = getelementptr i64, ptr %qa_p, i64 %qt
    store i64 %prom_b, ptr %ap, align 8
    %bp = getelementptr i64, ptr %qb_p, i64 %qt
    store i64 %cell2_b, ptr %bp, align 8
    %cp2 = getelementptr i64, ptr %qc_p, i64 %qt
    store i64 %val, ptr %cp2, align 8
    %nt_box = add i64 %int0_b, %nt
    store i64 %nt_box, ptr %qtp, align 8
    ret i64 1

  bail:
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
  if rk == 5
    st = p.rx_target
    idx = p.rx_on_f
    p.rx_target = nil
    p.rx_on_f = nil
    q.push_all_settle(st, idx, v, 0)
    return nil
  if rk == 6
    t = p.rx_target
    fn2 = p.rx_on_f
    p.rx_target = nil
    p.rx_on_f = nil
    q.push_async_chain(t, fn2, v, 0)
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
      elsif ek == 5
        q.push_all_settle(e[1], e[2], v, 0)
      elsif ek == 6
        q.push_async_chain(e[1], e[2], v, 0)
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
  if rk == 5
    st = p.rx_target
    idx = p.rx_on_f
    p.rx_target = nil
    p.rx_on_f = nil
    q.push_all_settle(st, idx, v, 1)
    return nil
  if rk == 6
    t = p.rx_target
    p.rx_target = nil
    p.rx_on_f = nil
    q.push_async_chain(t, nil, v, 1)
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
      elsif ek == 5
        q.push_all_settle(e[1], e[2], v, 1)
      elsif ek == 6
        q.push_async_chain(e[1], nil, v, 1)
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

-> js_prom_all_settle(st, idx, v, is_rej, q)
  return nil if st.settled
  if is_rej != 0
    st.settled = true
    js_promise_reject_fast(st.target, v, q)
    return nil
  st.values[idx] = v
  rem = st.rem - 1
  st.rem = rem
  if rem == 0
    st.settled = true
    js_promise_fulfill_fast(st.target, js_realm().adopt_array(st.values), q)
  nil

-> js_prom_async_chain_step(target, fn2, val, is_rej, q)
  if is_rej != 0
    js_promise_reject_fast(target, val, q)
    return nil
  r = js_realm()
  p2 = nil
  if !JS_MULTI_REALM[0] && fn2.is_a?(JS:Function) && fn2.code != nil && fn2.code.sm_code != nil && fn2.code.sm_code.fast_kind == 1
    p2 = js_sm_fast1_call(fn2.code.sm_code, fn2, 1, val, nil, nil, nil, r)
  p2 = js_call(fn2, nil, 1, val, nil, nil, nil, nil) if p2 == nil
  if js_promise_pristine?(r)
    if !js_object?(p2)
      q.push_rx_prom(target, nil, p2, 0)
      return nil
    if js_promise?(p2) && p2.shape == r.promise_shape
      st = p2.state
      if st == :pending
        js_promise_attach_raw(p2, 1, target, nil, nil)
        p2.handled = true
        return nil
      if st == :fulfilled
        p2.handled = true
        q.push_rx_prom(target, nil, p2.value, 0)
        return nil
      if !p2.handled
        ui = JS_UNHANDLED.index(p2)
        JS_UNHANDLED.delete_at(ui) if ui != nil
      p2.handled = true
      q.push_rx_prom(target, nil, p2.value, 1)
      return nil
  p2r = js_promise_resolve_value(p2)
  if js_promise?(p2r) && p2r.shape == r.promise_shape && js_promise_then_pristine?()
    js_promise_adopt(target, p2r)
  else
    js_promise_resolve_with(target, p2r)
  nil

-> js_promise_combinator(c, iterable, mode)
  r = js_realm()
  # Zero-closure pristine dense-array Promise.all fast path (100% ECMA-262 tick-exact!)
  if mode == :all && c == r.promise_ctor && js_promise_pristine?(r) && js_array?(iterable) && (js_array_flags(iterable) & 15) == JS_AF_ARRAY && js_array_iter_pristine?(iterable)
    n = js_arr_len(iterable)
    target = JS:Promise.new(r.promise_shape)
    q = r.jobs
    if n == 0
      js_promise_fulfill_fast(target, r.adopt_array([]), q)
      return target
    values = Array.new(n, nil)
    st = JS:PromiseAllState.new(target, values, n)
    ps = r.promise_shape
    i = 0
    while i < n
      x = iterable[i]
      if js_promise?(x) && x.shape == ps
        xst = x.state
        if xst == :pending
          js_promise_attach_raw(x, 5, st, i, nil)
          x.handled = true
        elsif xst == :fulfilled
          x.handled = true
          q.push_all_settle(st, i, x.value, 0)
        else
          if !x.handled
            ui = JS_UNHANDLED.index(x)
            JS_UNHANDLED.delete_at(ui) if ui != nil
          x.handled = true
          q.push_all_settle(st, i, x.value, 1)
      elsif !js_object?(x)
        q.push_all_settle(st, i, x, 0)
      else
        begin
          px = js_promise_resolve_value(x)
          if js_promise?(px) && px.shape == ps
            pxst = px.state
            if pxst == :pending
              js_promise_attach_raw(px, 5, st, i, nil)
              px.handled = true
            elsif pxst == :fulfilled
              px.handled = true
              q.push_all_settle(st, i, px.value, 0)
            else
              if !px.handled
                ui = JS_UNHANDLED.index(px)
                JS_UNHANDLED.delete_at(ui) if ui != nil
              px.handled = true
              q.push_all_settle(st, i, px.value, 1)
          else
            idx_c = i
            ok_f = r.native("", 1, ->(this, args, nt) js_prom_all_settle(st, idx_c, js_arg(args, 0), 0, js_realm().jobs))
            bad_f = r.native("", 1, ->(this, args, nt) js_prom_all_settle(st, idx_c, js_arg(args, 0), 1, js_realm().jobs))
            js_invoke(px, "then", [ok_f, bad_f])
        rescue ex
          js_prom_all_settle(st, i, js_error_value(ex), 1, q)
      i += 1
    return target
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
