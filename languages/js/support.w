# runtime/support — entry points the translator emits that are not operators or
# property access: environments, literals, `this`, and running a script.

in JS

# ---- environments (JS:Env: @up then seven variables; JS:EnvN beyond seven) ----

-> js_env_get(e, i)
  return e.vars[i - 7] if i >= 7
  eb = wvalue_bits(e) ## i64
  wvalue_from_bits(jsr_ivar(eb, i + 1))

-> js_env_set(e, i, v)
  if i >= 7
    e.vars[i - 7] = v
    return v
  ccall("w_ivar_set_idx", e, i + 1, v)
  v

-> js_env_up(e)
  eb = wvalue_bits(e) ## i64
  wvalue_from_bits(jsr_ivar(eb, 0))

# A copy of a loop's environment for the next iteration (per-iteration let bindings).
-> js_env_copy(e)
  n = nil
  if e.is_a?(JS:EnvN)
    n = JS:EnvN.new(e.up, 0)
    n.vars = e.vars.dup
  else
    n = JS:Env.new(e.up)
  n.v0 = e.v0
  n.v1 = e.v1
  n.v2 = e.v2
  n.v3 = e.v3
  n.v4 = e.v4
  n.v5 = e.v5
  n.v6 = e.v6
  n

# ---- literals ----

# The final shape of an object literal with these keys (computed once per site).
-> js_lit_shape(keys)
  s = js_root_shape(js_realm().object_proto, OBJ_INLINE, OBJ_IBASE)
  i = 0
  while i < keys.size
    s = s.add(keys[i], ATTR_DEFAULT)
    i += 1
  s

# Fast pure-LLVM allocators (1-malloc inline WArray & direct w_object_new JS:Object!)
JS_OBJ_CLS_B = i64[1]

-> js_obj_cls_bits
  cb = JS_OBJ_CLS_B[0]
  if cb == 0
    cb = wvalue_bits(JS:Object) ## i64
    JS_OBJ_CLS_B[0] = cb
  cb

fn jsr_new_obj_raw(cls_b, sh_b) (i64 i64) i64
  ll <<~IR
    %ob = call i64 @w_object_new(i64 %cls_b)
    %raw = sub i64 %ob, 4
    %p = inttoptr i64 %raw to ptr
    %kp = getelementptr i8, ptr %p, i64 4
    store i8 1, ptr %kp, align 1
    %sp = getelementptr i64, ptr %p, i64 1
    store i64 %sh_b, ptr %sp, align 8
    ret i64 %ob
  IR

# Pure-LLVM 6-slot inline literal allocation + fill (1 calloc, ZERO w_construct_cached or nil overwrites!).
fn jsr_lit6_new_raw(cls_b, sh_b, a, b, c, d, e, g) (i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %ob = call i64 @w_object_new(i64 %cls_b)
    %raw = sub i64 %ob, 4
    %p = inttoptr i64 %raw to ptr
    %kp = getelementptr i8, ptr %p, i64 4
    store i8 1, ptr %kp, align 1
    %sp = getelementptr i64, ptr %p, i64 1
    store i64 %sh_b, ptr %sp, align 8
    %p0 = getelementptr i64, ptr %p, i64 3
    %p1 = getelementptr i64, ptr %p, i64 4
    %p2 = getelementptr i64, ptr %p, i64 5
    %p3 = getelementptr i64, ptr %p, i64 6
    %p4 = getelementptr i64, ptr %p, i64 7
    %p5 = getelementptr i64, ptr %p, i64 8
    store i64 %a, ptr %p0, align 8
    store i64 %b, ptr %p1, align 8
    store i64 %c, ptr %p2, align 8
    store i64 %d, ptr %p3, align 8
    store i64 %e, ptr %p4, align 8
    store i64 %g, ptr %p5, align 8
    ret i64 %ob
  IR

# Single-malloc inline JS Arrays (w_array_new_inline(65, cap) -> 1 malloc + cap>=4 avoids realloc on first pushes!).
# Ensure `@w_array_new_inline` is always declared in emitted LLVM IR even for programs without inline Tungsten array literals.
-> js_decl_w_array_new_inline_shim
  ccall_nobox("w_array_new_inline", 65 ## i64, 1 ## i64) ## i64

fn jsr_arr0_raw() () i64
  ll <<~IR
    %ab = call i64 @w_array_new_inline(i64 65, i64 4)
    %p = and i64 %ab, 140737488355312
    %q = inttoptr i64 %p to ptr
    %fp = getelementptr i8, ptr %q, i64 2
    store i8 1, ptr %fp, align 1
    %szp = getelementptr i8, ptr %q, i64 8
    store i32 0, ptr %szp, align 4
    ret i64 %ab
  IR

fn jsr_arr1_raw(a0) (i64) i64
  ll <<~IR
    %ab = call i64 @w_array_new_inline(i64 65, i64 4)
    %p = and i64 %ab, 140737488355312
    %q = inttoptr i64 %p to ptr
    %fp = getelementptr i8, ptr %q, i64 2
    store i8 1, ptr %fp, align 1
    %szp = getelementptr i8, ptr %q, i64 8
    store i32 1, ptr %szp, align 4
    %slp = getelementptr i8, ptr %q, i64 16
    %sl = load ptr, ptr %slp, align 8
    store i64 %a0, ptr %sl, align 8
    ret i64 %ab
  IR

fn jsr_arr2_raw(a0, a1) (i64 i64) i64
  ll <<~IR
    %ab = call i64 @w_array_new_inline(i64 65, i64 2)
    %p = and i64 %ab, 140737488355312
    %q = inttoptr i64 %p to ptr
    %fp = getelementptr i8, ptr %q, i64 2
    store i8 1, ptr %fp, align 1
    %slp = getelementptr i8, ptr %q, i64 16
    %sl = load ptr, ptr %slp, align 8
    store i64 %a0, ptr %sl, align 8
    %s1 = getelementptr i64, ptr %sl, i64 1
    store i64 %a1, ptr %s1, align 8
    ret i64 %ab
  IR

fn jsr_arr3_raw(a0, a1, a2) (i64 i64 i64) i64
  ll <<~IR
    %ab = call i64 @w_array_new_inline(i64 65, i64 3)
    %p = and i64 %ab, 140737488355312
    %q = inttoptr i64 %p to ptr
    %fp = getelementptr i8, ptr %q, i64 2
    store i8 1, ptr %fp, align 1
    %slp = getelementptr i8, ptr %q, i64 16
    %sl = load ptr, ptr %slp, align 8
    store i64 %a0, ptr %sl, align 8
    %s1 = getelementptr i64, ptr %sl, i64 1
    store i64 %a1, ptr %s1, align 8
    %s2 = getelementptr i64, ptr %sl, i64 2
    store i64 %a2, ptr %s2, align 8
    ret i64 %ab
  IR

fn jsr_arr_holey_raw(n, hole_b) (i64 i64) i64
  ll <<~IR
    %ab = call i64 @w_array_new_inline(i64 65, i64 %n)
    %p = and i64 %ab, 140737488355312
    %q = inttoptr i64 %p to ptr
    %fp = getelementptr i8, ptr %q, i64 2
    store i8 3, ptr %fp, align 1
    %slp = getelementptr i8, ptr %q, i64 16
    %sl = load ptr, ptr %slp, align 8
    br label %loop
  loop:
    %i = phi i64 [ 0, %0 ], [ %ni, %body ]
    %done = icmp sge i64 %i, %n
    br i1 %done, label %fin, label %body
  body:
    %ep = getelementptr i64, ptr %sl, i64 %i
    store i64 %hole_b, ptr %ep, align 8
    %ni = add i64 %i, 1
    br label %loop
  fin:
    ret i64 %ab
  IR

fn jsr_arr_dup_raw(src_b) (i64) i64
  ll <<~IR
    %sp = and i64 %src_b, 140737488355312
    %sq = inttoptr i64 %sp to ptr
    %stp = getelementptr i8, ptr %sq, i64 4
    %st32 = load i32, ptr %stp, align 4
    %st = sext i32 %st32 to i64
    %szp = getelementptr i8, ptr %sq, i64 8
    %sz32 = load i32, ptr %szp, align 4
    %sz = sext i32 %sz32 to i64
    %lt4 = icmp slt i64 %sz, 4
    %cap = select i1 %lt4, i64 4, i64 %sz
    %ab = call i64 @w_array_new_inline(i64 65, i64 %cap)
    %dp = and i64 %ab, 140737488355312
    %dq = inttoptr i64 %dp to ptr
    %fp = getelementptr i8, ptr %dq, i64 2
    store i8 1, ptr %fp, align 1
    %dszp = getelementptr i8, ptr %dq, i64 8
    store i32 %sz32, ptr %dszp, align 4
    %gt0 = icmp sgt i64 %sz, 0
    br i1 %gt0, label %copy, label %fin
  copy:
    %sslp = getelementptr i8, ptr %sq, i64 16
    %ssl0 = load ptr, ptr %sslp, align 8
    %ssl = getelementptr i64, ptr %ssl0, i64 %st
    %dslp = getelementptr i8, ptr %dq, i64 16
    %dsl = load ptr, ptr %dslp, align 8
    %nb = shl i64 %sz, 3
    call void @llvm.memcpy.p0.p0.i64(ptr align 8 %dsl, ptr align 8 %ssl, i64 %nb, i1 false)
    br label %fin
  fin:
    ret i64 %ab
  IR

fn jsr_arr_from_buf_raw(src_p, start, cnt) (i64 i64 i64) i64
  ll <<~IR
    %ab = call i64 @w_array_new_inline(i64 65, i64 %cnt)
    %dp = and i64 %ab, 140737488355312
    %dq = inttoptr i64 %dp to ptr
    %fp = getelementptr i8, ptr %dq, i64 2
    store i8 1, ptr %fp, align 1
    %gt0 = icmp sgt i64 %cnt, 0
    br i1 %gt0, label %copy, label %fin
  copy:
    %s0 = inttoptr i64 %src_p to ptr
    %src = getelementptr i64, ptr %s0, i64 %start
    %dslp = getelementptr i8, ptr %dq, i64 16
    %dsl = load ptr, ptr %dslp, align 8
    %nb = shl i64 %cnt, 3
    call void @llvm.memcpy.p0.p0.i64(ptr align 8 %dsl, ptr align 8 %src, i64 %nb, i1 false)
    br label %fin
  fin:
    ret i64 %ab
  IR

fn jsr_str_slice_raw(sb, start, len) (i64 i64 i64) i64
  ll <<~IR
    %r = call i64 @w_string_slice_raw(i64 %sb, i64 %start, i64 %len)
    ret i64 %r
  IR

# Escape-scoped bump-pointer nursery arena for proven-non-escaping JS regions (100% GC-safe & leak-free!).
# Backing slabs are polymorphic WArrays (ebits == 65, 524288 qwords = 4 MiB each) so Tungsten's GC
# automatically traces every WValue stored inside arena-allocated JS:Objects and fixed-size WArrays!
# State layout (i64[8]):
#   [0] cur_ptr (0 when inactive)  [1] end_ptr  [2] depth  [3] slab_idx
#   [4] cur_base  [5] arr_on (0/1) [6] wobj_hdr [7] arena_state_ptr
JS_ARENA_SLAB_QW = 524288
JS_ARENA_SLAB_BYTES = 4194288
JS_ARENA_STATE = i64[8]
JS_ARENA_SLABS = []
JS_ARENA_BASES = i64[32]
JS_ARENA_EXT_ARRS = []

fn jsr_arena_alloc_arr0_raw(st_p) (i64) i64
  ll <<~IR
    %st = inttoptr i64 %st_p to ptr
    %aop = getelementptr i64, ptr %st, i64 5
    %ao = load i64, ptr %aop, align 8
    %aok = icmp ne i64 %ao, 0
    br i1 %aok, label %chk, label %miss
  chk:
    %cur = load i64, ptr %st, align 8
    %act = icmp ne i64 %cur, 0
    br i1 %act, label %chk2, label %miss
  chk2:
    %ep = getelementptr i64, ptr %st, i64 1
    %end = load i64, ptr %ep, align 8
    %nxt = add i64 %cur, 64
    %ok = icmp ule i64 %nxt, %end
    br i1 %ok, label %hit, label %miss
  hit:
    store i64 %nxt, ptr %st, align 8
    %ap = inttoptr i64 %cur to ptr
    store i64 82370, ptr %ap, align 8
    %p1 = getelementptr i64, ptr %ap, i64 1
    store i64 17179869184, ptr %p1, align 8
    %slp = add i64 %cur, 32
    %p2 = getelementptr i64, ptr %ap, i64 2
    store i64 %slp, ptr %p2, align 8
    %ab = or i64 %cur, u0xFFF4000000000000
    ret i64 %ab
  miss:
    ret i64 0
  IR

# Grow an arena-allocated WArray's slots directly inside the bump arena (zero malloc, zero leak!).
# Returns new_size (>0) on hit, -1 if arena slab needs grow, 0 if not an arena array or > 16384 elems.
fn jsr_arena_grow_push_raw(st_p, ab, vb) (i64 i64 i64) i64
  ll <<~IR
    %ap_i = and i64 %ab, 140737488355312
    %ap = inttoptr i64 %ap_i to ptr
    %fl = load i8, ptr %ap, align 1
    %is_np = and i8 %fl, 192
    %ok_np = icmp eq i8 %is_np, 192
    br i1 %ok_np, label %chk_st, label %no
  chk_st:
    %st = inttoptr i64 %st_p to ptr
    %cur = load i64, ptr %st, align 8
    %act = icmp ne i64 %cur, 0
    br i1 %act, label %chk_cap, label %no
  chk_cap:
    %stp = getelementptr i8, ptr %ap, i64 4
    %st32 = load i32, ptr %stp, align 4
    %st64 = sext i32 %st32 to i64
    %szp = getelementptr i8, ptr %ap, i64 8
    %sz32 = load i32, ptr %szp, align 4
    %sz = sext i32 %sz32 to i64
    %cp = getelementptr i8, ptr %ap, i64 12
    %c32 = load i32, ptr %cp, align 4
    %cap = sext i32 %c32 to i64
    %fit = icmp slt i64 %sz, %cap
    br i1 %fit, label %fast_put, label %need_grow
  fast_put:
    %slp0 = getelementptr i8, ptr %ap, i64 16
    %sl0 = load ptr, ptr %slp0, align 8
    %idx0 = add i64 %st64, %sz
    %dst0 = getelementptr i64, ptr %sl0, i64 %idx0
    store i64 %vb, ptr %dst0, align 8
    %nsz0 = add i64 %sz, 1
    %nsz0_32 = trunc i64 %nsz0 to i32
    store i32 %nsz0_32, ptr %szp, align 4
    ret i64 %nsz0
  need_grow:
    %nc0 = shl i64 %cap, 1
    %lt4 = icmp slt i64 %nc0, 4
    %nc = select i1 %lt4, i64 4, i64 %nc0
    %big = icmp sgt i64 %nc, 16384
    br i1 %big, label %no, label %chk_room
  chk_room:
    %nb = shl i64 %nc, 3
    %ep = getelementptr i64, ptr %st, i64 1
    %end = load i64, ptr %ep, align 8
    %nxt = add i64 %cur, %nb
    %ok = icmp ule i64 %nxt, %end
    br i1 %ok, label %do_grow, label %slab_full
  do_grow:
    store i64 %nxt, ptr %st, align 8
    %nsl = inttoptr i64 %cur to ptr
    %slp1 = getelementptr i8, ptr %ap, i64 16
    %osl0 = load ptr, ptr %slp1, align 8
    %has_old = icmp sgt i64 %sz, 0
    br i1 %has_old, label %docopy, label %after_copy
  docopy:
    %osl = getelementptr i64, ptr %osl0, i64 %st64
    %cpy_b = shl i64 %sz, 3
    call void @llvm.memcpy.p0.p0.i64(ptr align 8 %nsl, ptr align 8 %osl, i64 %cpy_b, i1 false)
    br label %after_copy
  after_copy:
    %vslot = getelementptr i64, ptr %nsl, i64 %sz
    store i64 %vb, ptr %vslot, align 8
    store ptr %nsl, ptr %slp1, align 8
    store i32 0, ptr %stp, align 4
    %nsz1 = add i64 %sz, 1
    %nsz1_32 = trunc i64 %nsz1 to i32
    store i32 %nsz1_32, ptr %szp, align 4
    %nc32 = trunc i64 %nc to i32
    store i32 %nc32, ptr %cp, align 4
    ret i64 %nsz1
  slab_full:
    ret i64 -1
  no:
    ret i64 0
  IR

fn jsr_arr_is_arena(ab) (i64) i64
  ll <<~IR
    %ap_i = and i64 %ab, 140737488355312
    %ap = inttoptr i64 %ap_i to ptr
    %fl = load i8, ptr %ap, align 1
    %m = and i8 %fl, 128
    %r = icmp ne i8 %m, 0
    %r64 = zext i1 %r to i64
    ret i64 %r64
  IR

fn jsr_arena_attach_buf(ab, buf_slots_p, new_cap, vb) (i64 i64 i64 i64) i64
  ll <<~IR
    %ap_i = and i64 %ab, 140737488355312
    %ap = inttoptr i64 %ap_i to ptr
    %stp = getelementptr i8, ptr %ap, i64 4
    %st32 = load i32, ptr %stp, align 4
    %st64 = sext i32 %st32 to i64
    %szp = getelementptr i8, ptr %ap, i64 8
    %sz32 = load i32, ptr %szp, align 4
    %sz = sext i32 %sz32 to i64
    %cp = getelementptr i8, ptr %ap, i64 12
    %slp = getelementptr i8, ptr %ap, i64 16
    %osl0 = load ptr, ptr %slp, align 8
    %nsl = inttoptr i64 %buf_slots_p to ptr
    %has_old = icmp sgt i64 %sz, 0
    br i1 %has_old, label %docopy, label %after_copy
  docopy:
    %osl = getelementptr i64, ptr %osl0, i64 %st64
    %nb = shl i64 %sz, 3
    call void @llvm.memcpy.p0.p0.i64(ptr align 8 %nsl, ptr align 8 %osl, i64 %nb, i1 false)
    br label %after_copy
  after_copy:
    %vslot = getelementptr i64, ptr %nsl, i64 %sz
    store i64 %vb, ptr %vslot, align 8
    store ptr %nsl, ptr %slp, align 8
    store i32 0, ptr %stp, align 4
    %nsz = add i64 %sz, 1
    %nsz32 = trunc i64 %nsz to i32
    store i32 %nsz32, ptr %szp, align 4
    %nc32 = trunc i64 %new_cap to i32
    store i32 %nc32, ptr %cp, align 4
    ret i64 %nsz
  IR

fn jsr_arr_set_size_raw(arr_bits, sz) (i64 i64) i64
  ll <<~IR
    %p = and i64 %arr_bits, 140737488355312
    %q = inttoptr i64 %p to ptr
    %sp = getelementptr i8, ptr %q, i64 8
    %s32 = trunc i64 %sz to i32
    store i32 %s32, ptr %sp, align 4
    ret i64 0
  IR

fn jsr_memset_zero(ptr_i, nbytes) (i64 i64) i64
  ll <<~IR
    %gt0 = icmp sgt i64 %nbytes, 0
    br i1 %gt0, label %go, label %done
  go:
    %p = inttoptr i64 %ptr_i to ptr
    call void @llvm.memset.p0.i64(ptr align 16 %p, i8 0, i64 %nbytes, i1 false)
    br label %done
  done:
    ret i64 0
  IR

fn jsr_arena_alloc_obj_raw(st_p, sh_b) (i64 i64) i64
  ll <<~IR
    %st = inttoptr i64 %st_p to ptr
    %cur = load i64, ptr %st, align 8
    %act = icmp ne i64 %cur, 0
    br i1 %act, label %chk, label %miss
  chk:
    %ep = getelementptr i64, ptr %st, i64 1
    %end = load i64, ptr %ep, align 8
    %nxt = add i64 %cur, 96
    %ok = icmp ule i64 %nxt, %end
    br i1 %ok, label %hit, label %miss
  hit:
    store i64 %nxt, ptr %st, align 8
    %hp = getelementptr i64, ptr %st, i64 6
    %hdr = load i64, ptr %hp, align 8
    %op = inttoptr i64 %cur to ptr
    store i64 %hdr, ptr %op, align 8
    %sp = getelementptr i64, ptr %op, i64 1
    store i64 %sh_b, ptr %sp, align 8
    %ob = add i64 %cur, 4
    ret i64 %ob
  miss:
    ret i64 0
  IR

fn jsr_arena_alloc_arr_raw(st_p, n, aflags) (i64 i64 i64) i64
  ll <<~IR
    %st = inttoptr i64 %st_p to ptr
    %aop = getelementptr i64, ptr %st, i64 5
    %ao = load i64, ptr %aop, align 8
    %aok = icmp ne i64 %ao, 0
    br i1 %aok, label %chk_n, label %miss
  chk_n:
    %n1 = icmp sge i64 %n, 1
    %n8 = icmp sle i64 %n, 8
    %nok = and i1 %n1, %n8
    br i1 %nok, label %chk, label %miss
  chk:
    %cur = load i64, ptr %st, align 8
    %act = icmp ne i64 %cur, 0
    br i1 %act, label %chk2, label %miss
  chk2:
    %np1 = add i64 %n, 1
    %cap = and i64 %np1, -2
    %pl = shl i64 %cap, 3
    %sz = add i64 %pl, 32
    %ep = getelementptr i64, ptr %st, i64 1
    %end = load i64, ptr %ep, align 8
    %nxt = add i64 %cur, %sz
    %ok = icmp ule i64 %nxt, %end
    br i1 %ok, label %hit, label %miss
  hit:
    store i64 %nxt, ptr %st, align 8
    %ap = inttoptr i64 %cur to ptr
    %af16 = shl i64 %aflags, 16
    %h0 = or i64 %af16, 16834
    store i64 %h0, ptr %ap, align 8
    %cap32 = shl i64 %cap, 32
    %h1 = or i64 %cap32, %n
    %p1 = getelementptr i64, ptr %ap, i64 1
    store i64 %h1, ptr %p1, align 8
    %slp = add i64 %cur, 32
    %p2 = getelementptr i64, ptr %ap, i64 2
    store i64 %slp, ptr %p2, align 8
    %ab = or i64 %cur, u0xFFF4000000000000
    ret i64 %ab
  miss:
    ret i64 0
  IR

fn jsr_arena_dup_arr_raw(st_p, src_b) (i64 i64) i64
  ll <<~IR
    %st = inttoptr i64 %st_p to ptr
    %aop = getelementptr i64, ptr %st, i64 5
    %ao = load i64, ptr %aop, align 8
    %aok = icmp ne i64 %ao, 0
    br i1 %aok, label %chk_src, label %miss
  chk_src:
    %sp = and i64 %src_b, 140737488355312
    %sq = inttoptr i64 %sp to ptr
    %szp = getelementptr i8, ptr %sq, i64 8
    %sz32 = load i32, ptr %szp, align 4
    %sz = sext i32 %sz32 to i64
    %le64 = icmp sle i64 %sz, 64
    %ge0 = icmp sge i64 %sz, 0
    %sok = and i1 %le64, %ge0
    br i1 %sok, label %chk_cur, label %miss
  chk_cur:
    %cur = load i64, ptr %st, align 8
    %act = icmp ne i64 %cur, 0
    br i1 %act, label %chk_fit, label %miss
  chk_fit:
    %lt4 = icmp slt i64 %sz, 4
    %szp1 = add i64 %sz, 1
    %even = and i64 %szp1, -2
    %cap = select i1 %lt4, i64 4, i64 %even
    %pl = shl i64 %cap, 3
    %bytes = add i64 %pl, 32
    %ep = getelementptr i64, ptr %st, i64 1
    %end = load i64, ptr %ep, align 8
    %nxt = add i64 %cur, %bytes
    %ok = icmp ule i64 %nxt, %end
    br i1 %ok, label %hit, label %miss
  hit:
    store i64 %nxt, ptr %st, align 8
    %ap = inttoptr i64 %cur to ptr
    store i64 82370, ptr %ap, align 8
    %cap32 = shl i64 %cap, 32
    %h1 = or i64 %cap32, %sz
    %p1 = getelementptr i64, ptr %ap, i64 1
    store i64 %h1, ptr %p1, align 8
    %slp = add i64 %cur, 32
    %p2 = getelementptr i64, ptr %ap, i64 2
    store i64 %slp, ptr %p2, align 8
    %gt0 = icmp sgt i64 %sz, 0
    br i1 %gt0, label %copy, label %fin
  copy:
    %stp = getelementptr i8, ptr %sq, i64 4
    %st32 = load i32, ptr %stp, align 4
    %st64 = sext i32 %st32 to i64
    %sslp = getelementptr i8, ptr %sq, i64 16
    %ssl0 = load ptr, ptr %sslp, align 8
    %ssl = getelementptr i64, ptr %ssl0, i64 %st64
    %dsl = inttoptr i64 %slp to ptr
    %nb = shl i64 %sz, 3
    call void @llvm.memcpy.p0.p0.i64(ptr align 8 %dsl, ptr align 8 %ssl, i64 %nb, i1 false)
    br label %fin
  fin:
    %ab = or i64 %cur, u0xFFF4000000000000
    ret i64 %ab
  miss:
    ret i64 0
  IR

-> js_arena_owns_ptr?(ptr_i)
  last_si = JS_ARENA_STATE[3]
  si = 0
  while si <= last_si
    b = JS_ARENA_BASES[si]
    return true if ptr_i >= b && ptr_i < b + JS_ARENA_SLAB_BYTES
    si += 1
  false

-> js_arena_ensure_hdr
  if JS_ARENA_STATE[6] == 0
    tmp = JS:Object.new(nil)
    clsid = jit_obj_clsid(wvalue_bits(tmp) ## i64)
    # WObject header: class_id(u16) | ivar_count=10(u8)<<16 | W_FLAG_GC_NO_POOL=128(u8)<<24 | KIND_OBJECT=1(u8)<<32
    JS_ARENA_STATE[6] = clsid | (10 << 16) | (128 << 24) | (1 << 32)
    JS_ARENA_STATE[7] = jit_arr_slots_ptr(wvalue_bits(JS_ARENA_STATE) ## i64)
  JS_ARENA_STATE[7]

-> js_arena_ensure_slab(idx)
  while JS_ARENA_SLABS.size <= idx
    sl = Array.new(JS_ARENA_SLAB_QW, nil)
    raw = jit_arr_slots_ptr(wvalue_bits(sl) ## i64)
    aligned = (raw + 15) & -16
    JS_ARENA_BASES[JS_ARENA_SLABS.size] = aligned
    JS_ARENA_SLABS.push(sl)
  sl = JS_ARENA_SLABS[idx]
  jsr_arr_set_size_raw(wvalue_bits(sl) ## i64, JS_ARENA_SLAB_QW)
  JS_ARENA_BASES[idx]

JS_ARENA_MAP_POOL = []
JS_ARENA_USED_MAPS = []

fn jmap_arr_is_old(arr_bits) (i64) i64
  ll <<~IR
    %p = and i64 %arr_bits, 140737488355312
    %q = inttoptr i64 %p to ptr
    %fp = getelementptr i8, ptr %q, i64 3
    %fl = load i8, ptr %fp, align 1
    %o = and i8 %fl, 4
    %is = icmp ne i8 %o, 0
    %r = zext i1 %is to i64
    ret i64 %r
  IR

-> js_arena_enter(allow_arr)
  d = JS_ARENA_STATE[2]
  if d == 0
    js_arena_ensure_hdr()
    b0 = js_arena_ensure_slab(0)
    JS_ARENA_STATE[0] = b0
    JS_ARENA_STATE[1] = b0 + JS_ARENA_SLAB_BYTES
    JS_ARENA_STATE[3] = 0
    JS_ARENA_STATE[4] = b0
    JS_ARENA_STATE[5] = allow_arr ? 1 : 0
  JS_ARENA_STATE[2] = d + 1
  nil

-> js_arena_next_slab
  si = JS_ARENA_STATE[3] + 1
  return false if si >= 32
  b = js_arena_ensure_slab(si)
  JS_ARENA_STATE[0] = b
  JS_ARENA_STATE[1] = b + JS_ARENA_SLAB_BYTES
  JS_ARENA_STATE[3] = si
  JS_ARENA_STATE[4] = b
  true

-> js_arena_leave(promote_cells = nil)
  d = JS_ARENA_STATE[2]
  return nil if d <= 0
  d -= 1
  JS_ARENA_STATE[2] = d
  return nil if d > 0
  if promote_cells != nil
    pi = 0
    while pi < promote_cells.size
      gc = promote_cells[pi]
      v = gc.value
      if v.is_a?(JS:Object) && js_arena_owns_ptr?((wvalue_bits(v) ## i64) - 4)
        sh = v.shape
        cp = wvalue_from_bits(jsr_new_obj_raw(js_obj_cls_bits(), wvalue_bits(sh) ## i64))
        cp.ext = v.ext.dup if v.ext != nil
        ki = 0
        while ki < sh.inline && ki < sh.count
          cp.slot_set(ki, v.slot_get(ki))
          ki += 1
        gc.value = cp
      pi += 1
  last_si = JS_ARENA_STATE[3]
  cur = JS_ARENA_STATE[0]
  cur_base = JS_ARENA_STATE[4]
  JS_ARENA_STATE[0] = 0
  JS_ARENA_STATE[1] = 0
  JS_ARENA_STATE[3] = 0
  JS_ARENA_STATE[4] = 0
  JS_ARENA_STATE[5] = 0
  JS_ARENA_EXT_ARRS.clear if JS_ARENA_EXT_ARRS.size > 0
  js_arena_recycle_maps(promote_cells == nil) if JS_ARENA_USED_MAPS.size > 0
  si = 0
  while si <= last_si
    base_i = JS_ARENA_BASES[si]
    used = si < last_si ? JS_ARENA_SLAB_BYTES : (cur - cur_base)
    jsr_memset_zero(base_i, used) if used > 0
    jsr_arr_set_size_raw(wvalue_bits(JS_ARENA_SLABS[si]) ## i64, 0)
    si += 1
  while JS_ARENA_SLABS.size > 6
    JS_ARENA_SLABS.pop
  nil

-> js_arena_alloc_arr0_slow
  st_p = JS_ARENA_STATE[7]
  if st_p != 0 && JS_ARENA_STATE[0] != 0 && JS_ARENA_STATE[5] != 0 && js_arena_next_slab()
    ab = jsr_arena_alloc_arr0_raw(st_p)
    return wvalue_from_bits(ab) if ab != 0
  js_arr0_fast()

-> js_arena_push_one(a, v)
  ab = wvalue_bits(a) ## i64
  vb = wvalue_bits(v) ## i64
  st_p = JS_ARENA_STATE[7]
  if st_p != 0 && JS_ARENA_STATE[0] != 0
    r = jsr_arena_grow_push_raw(st_p, ab, vb)
    return r if r > 0
    if r == -1 && js_arena_next_slab()
      r2 = jsr_arena_grow_push_raw(st_p, ab, vb)
      return r2 if r2 > 0
  if jsr_arr_is_arena(ab) != 0
    nc = a.size < 4 ? 8 : (a.size * 2)
    buf = Array.new(nc, nil)
    JS_ARENA_EXT_ARRS.push(buf)
    return jsr_arena_attach_buf(ab, jit_arr_slots_ptr(wvalue_bits(buf) ## i64), nc ## i64, vb)
  a.push(v)
  a.size ## i64

-> js_arena_alloc_obj_slow(sh)
  st_p = JS_ARENA_STATE[7]
  if st_p != 0 && JS_ARENA_STATE[0] != 0 && js_arena_next_slab()
    ob = jsr_arena_alloc_obj_raw(st_p, wvalue_bits(sh) ## i64)
    return wvalue_from_bits(ob) if ob != 0
  js_new_obj_fast(sh)

-> js_arena_alloc_arr_slow(n)
  ni = js_to_int32(n)
  st_p = JS_ARENA_STATE[7]
  if st_p != 0 && JS_ARENA_STATE[0] != 0 && JS_ARENA_STATE[5] != 0 && js_arena_next_slab()
    ab = jsr_arena_alloc_arr_raw(st_p, ni ## i64, JS_AF_ARRAY ## i64)
    return wvalue_from_bits(ab) if ab != 0
  js_mark_array(Array.new(ni, nil))

-> js_new_obj_fast(shape)
  if JS_ARENA_STATE[0] != 0
    ob = jsr_arena_alloc_obj_raw(JS_ARENA_STATE[7], wvalue_bits(shape) ## i64)
    return wvalue_from_bits(ob) if ob != 0
    return js_arena_alloc_obj_slow(shape)
  o = wvalue_from_bits(jsr_new_obj_raw(js_obj_cls_bits(), wvalue_bits(shape) ## i64))
  JS_GC_ON[0] ? js_gc_reg(o) : o

-> js_arr0_fast
  return js_mark_array([]) if JS_MULTI_REALM[0] || JS_GC_ON[0]
  wvalue_from_bits(jsr_arr0_raw())

-> js_arr1_fast(a0)
  return js_mark_array([a0]) if JS_MULTI_REALM[0] || JS_GC_ON[0]
  wvalue_from_bits(jsr_arr1_raw(wvalue_bits(a0) ## i64))

-> js_arr2_fast(a0, a1)
  return js_mark_array([a0, a1]) if JS_MULTI_REALM[0] || JS_GC_ON[0]
  wvalue_from_bits(jsr_arr2_raw(wvalue_bits(a0) ## i64, wvalue_bits(a1) ## i64))

-> js_arr3_fast(a0, a1, a2)
  return js_mark_array([a0, a1, a2]) if JS_MULTI_REALM[0] || JS_GC_ON[0]
  wvalue_from_bits(jsr_arr3_raw(wvalue_bits(a0) ## i64, wvalue_bits(a1) ## i64, wvalue_bits(a2) ## i64))

# An object literal of up to six properties: one block.
-> js_lit(shape, a, b, c, d, e, g)
  o = wvalue_from_bits(jsr_lit6_new_raw(js_obj_cls_bits(), wvalue_bits(shape) ## i64, wvalue_bits(a) ## i64, wvalue_bits(b) ## i64, wvalue_bits(c) ## i64, wvalue_bits(d) ## i64, wvalue_bits(e) ## i64, wvalue_bits(g) ## i64))
  JS_GC_ON[0] ? js_gc_reg(o) : o

-> js_lit_n(shape, vals)
  o = js_new_obj_fast(shape)
  i = 0
  while i < vals.size
    o.slot_set(i, vals[i])
    i += 1
  o

-> js_define_literal(o, key, v)
  o.define(key, v, ATTR_DEFAULT)
  nil

-> js_mark_holey(a)
  ab = wvalue_bits(a) ## i64
  jsr_set_aflags(ab, JS_AF_ARRAY | JS_AF_HOLES)
  if JS_MULTI_REALM[0] && JS_REALM[0] != nil
    JS_ARR_REALM_PROTO[ab & 140737488355312] = JS_REALM[0].array_proto
  JS_GC_ON[0] ? js_gc_reg(a) : a

# ---- the JS call stack (positions for Error.stack and host tools) ----

# The innermost running activation of tier 0 (each links to its caller), nil outside JS.
JS_CUR_ACT = [nil]
# ->() the stack lines, ->() [url, line, column]: set by tier 0.
JS_STACK_HOOK = [nil]
JS_LOCATION_HOOK = [nil]

-> js_stack_lines
  JS_STACK_HOOK[0] == nil ? "" : JS_STACK_HOOK[0].call()

-> js_top_location
  JS_LOCATION_HOOK[0] == nil ? ["", 1, 1] : JS_LOCATION_HOOK[0].call()

-> js_src_location(src, url, p)
  return "\[native code]" if src == nil
  lc = js_src_linecol(src, p)
  (url == nil ? "" : url) + ":" + lc[0].to_s + ":" + lc[1].to_s

# Line and column (1-based) of byte offset p; the newline index of the last few sources
# is kept (a stack walks frames of a few big scripts).
JS_LINE_CACHE = [[], []]

-> js_src_linecol(src, p)
  return [1, 1] if src == nil
  srcs = JS_LINE_CACHE[0]
  nls = nil
  ci = 0
  while ci < srcs.size && nls == nil
    nls = JS_LINE_CACHE[1][ci] if js_ident?(srcs[ci], src)
    ci += 1
  if nls == nil
    nls = []
    i = 0
    while true
      k = src.index("\n", i)
      break if k == nil
      nls.push(k)
      i = k + 1
    if srcs.size >= 8
      srcs.shift
      JS_LINE_CACHE[1].shift
    srcs.push(src)
    JS_LINE_CACHE[1].push(nls)
  lo = 0
  hi = nls.size
  while lo < hi
    mid = (lo + hi) / 2
    if nls[mid] < p
      lo = mid + 1
    else
      hi = mid
  [lo + 1, lo == 0 ? p + 1 : p - nls[lo - 1]]

# ---- script-level lexical bindings (top-level let, const, class; per-realm!) ----

+ JsTdz
  -> new
    nil

JS_TDZ = JS:JsTdz.new

JS_LEXICAL = {}
JS_GLOBAL_VARS = {}

-> js_lexical_map
  r = js_realm()
  r == nil ? JS_LEXICAL : r.lexical

-> js_global_vars
  r = js_realm()
  r == nil ? JS_GLOBAL_VARS : r.global_vars

-> js_lcell(name)
  lm = js_lexical_map()
  c = lm[name]
  if c == nil
    c = JS:GlobalCell.new(name)
    c.put(JS_HOLE, ATTR_W + ATTR_E)
    lm[name] = c
  c

# Initializing a script-level let/const/class (its declaration runs).
-> js_linit(c, v, is_const)
  c.put(v, is_const ? ATTR_E : ATTR_W + ATTR_E)
  v

# Assigning one: TDZ before its declaration, TypeError for a const.
-> js_lset(c, v)
  js_throw_reference("Cannot access '" + c.name + "' before initialization") if c.value == JS_HOLE
  js_throw_type("Assignment to constant variable.") if (c.attrs & ATTR_W) == 0
  c.value = v
  v

# ---- this, calls, operators on objects ----

# A sloppy-mode function's this: undefined and null become the global object, primitives box.
-> js_sloppy_this(t)
  return js_realm().global if t == nil || t == JS_NULL
  return t if js_object?(t)
  js_realm().wrap_primitive(t)

-> js_tonumeric(v)
  return v if js_number?(v)
  js_numeric_value(v)

# o[key](args)
-> js_call_computed(o, key, argc, a0, a1, a2, a3, more)
  f = js_getv(o, key)
  js_call(f, o, argc, a0, a1, a2, a3, more)

-> js_delete(o, key, strict)
  js_throw_type("Cannot convert undefined or null to object") if js_nullish?(o)
  k = js_to_property_key(key)
  if js_array?(o)
    if k.is_a?(String) && js_array_index?(k)
      i = k.to_i
      if i < o.size && o[i] != JS_HOLE
        if js_array_sealed?(o)
          js_throw_type("Cannot delete property '" + k + "' of \[object Array]") if strict
          return false
        o[i] = JS_HOLE
        ab = wvalue_bits(o) ## i64
        jsr_set_aflags(ab, jsr_aflags(ab) | JS_AF_HOLES)
        return true
      x = js_array_slow_elem(o, k)
      return true if x == nil
      ok = x.delete_own(k)
      js_throw_type("Cannot delete property '" + k + "' of \[object Array]") if !ok && strict
      return ok
    if k == "length"
      js_throw_type("Cannot delete property 'length' of \[object Array]") if strict
      return false
    return true if (js_array_flags(o) & JS_AF_EXT) == 0
    ok = js_array_ext(o, false).delete_own(k)
    js_throw_type("Cannot delete property '" + js_to_display(js_key_display(k)) + "'") if !ok && strict
    return ok
  if js_string?(o)
    if k == "length" || (k.is_a?(String) && js_array_index?(k) && k.to_i < js_len(o))
      js_throw_type("Cannot delete property '" + js_to_display(js_key_display(k)) + "' of string") if strict
      return false
    return true
  if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
    ok = JS_DOM_HOOK[0].delete_own(o, k)
    js_throw_type("Cannot delete property '" + js_to_display(js_key_display(k)) + "'") if !ok && strict
    return ok
  return true if !o.is_a?(JS:Base)
  ok = o.delete_own(k)
  js_throw_type("Cannot delete property '" + js_to_display(js_key_display(k)) + "'") if !ok && strict
  ok

-> js_in(key, o)
  js_throw_type("Cannot use 'in' operator to search for a key in " + js_to_display(o)) if !js_object?(o)
  k = js_to_property_key(key)
  return jhas_property?(o, k) if js_array?(o) || js_dom_handle?(o)
  js_has_property(o, k)

-> js_has_property(o, k)
  return false if o == nil
  return jhas_property?(o, k) if js_dom_handle?(o)
  o.has_property?(k)

# v instanceof f (§13.10.2): f's @@hasInstance when it is not Function.prototype's own.
-> js_instanceof(v, f)
  js_throw_type("Right-hand side of 'instanceof' is not an object") if !js_object?(f)
  h = js_get_method(f, SYM_HAS_INSTANCE)
  return js_truthy(js_call_arr(h, f, [v])) if h != nil && h != js_realm().intrinsics["%FunctionProto_hasInstance%"]
  js_throw_type("Right-hand side of 'instanceof' is not callable") if !js_callable?(f)
  js_ordinary_has_instance(f, v)

# ---- running a script ----

JS_EXIT = [0]

# After the script: flush output and exit (1 when an exception was uncaught).
JS_T0 = [clock_ms()]

-> js_finish
  js_realm().run_jobs
  << "(" + (clock_ms() - JS_T0[0]).to_s + " ms)" if Env.get("JSRUN_TIME", "") == "1"
  ccall("w_flush")
  if Env.get("JSRUN_PAUSE", "") == "1"
    # tools/memstat.sh --heap: hold the heap still for `heap` until killed
    ccall("w_eputs", "jsrun: paused")
    while true
      sleep(1)
  exit(JS_EXIT[0])

-> js_report_uncaught(e)
  v = js_error_value(e)
  # an error prints as toString and its stack (frames only, as JavaScriptCore keeps them)
  << "Uncaught " + js_inspect(v, 1)
  JS_EXIT[0] = 1
  nil

# Called by the entry of a function this program does not compile (partial builds).
-> js_tier0_only(i)
  js_throw_type("function " + i.to_s + " is not compiled in this build")

# The code descriptor of a function this program does not compile (partial builds; in a
# unit the host hands these over).
JS_CODE_AT = {}

-> js_code_at(i)
  c = JS_CODE_AT[i]
  if c == nil
    c = JS:Code.new("", 0, -1, 8)
    JS_CODE_AT[i] = c
  c

# ---- for-in (§14.7.5.9 EnumerateObjectProperties) ----

# Cached check: does Object.prototype have zero enumerable own properties at current JS_EPOCH?
JS_OP_NO_ENUM_EP = [-1]
JS_OP_NO_ENUM_OP = [nil]
JS_OP_NO_ENUM_OK = [false]

-> js_obj_proto_no_enum?(op)
  ep = JS_EPOCH[0]
  return JS_OP_NO_ENUM_OK[0] if JS_OP_NO_ENUM_EP[0] == ep && JS_OP_NO_ENUM_OP[0] == op
  ok = true
  if op != nil
    ks = jown_keys(op)
    i = 0
    while i < ks.size
      if js_string?(ks[i]) && jenumerable?(op, ks[i])
        ok = false
        break
      i += 1
    ok = false if jproto(op) != nil
  JS_OP_NO_ENUM_EP[0] = ep
  JS_OP_NO_ENUM_OP[0] = op
  JS_OP_NO_ENUM_OK[0] = ok
  ok

# The string keys a for-in over v visits: own enumerable keys first, then each
# prototype's, without duplicates (a non-enumerable own key still shadows). The loop
# checks each key is still present before visiting it.
-> js_for_in_keys(v)
  return JS_NO_ARGS if js_nullish?(v)
  # O(1) zero-allocation fast path for plain JS:Object inheriting directly from untouched Object.prototype!
  if v.is_a?(JS:Object)
    sh = v.shape
    if !sh.dict
      op = sh.proto
      return sh.enum_str_keys() if op == nil || (op == js_realm().object_proto && js_obj_proto_no_enum?(op))
  start = js_object?(v) ? v : js_realm().wrap_primitive(v)
  out = []
  ks = jown_keys(start)
  i = 0
  while i < ks.size
    k = ks[i]
    out.push(k) if js_string?(k) && jenumerable?(start, k)
    i += 1
  o = jproto(start)
  seen = nil
  while o != nil
    ks = jown_keys(o)
    i = 0
    while i < ks.size
      k = ks[i]
      if js_string?(k) && jenumerable?(o, k)
        if seen == nil
          seen = {}
          cur = start
          while cur != nil && cur != o
            cks = jown_keys(cur)
            j = 0
            while j < cks.size
              seen[cks[j]] = true if js_string?(cks[j])
              j += 1
            cur = jproto(cur)
        if !seen.has_key?(k)
          seen[k] = true
          out.push(k)
      i += 1
    if seen != nil
      i = 0
      while i < ks.size
        seen[ks[i]] = true if js_string?(ks[i])
        i += 1
    o = jproto(o)
  out

# ---- template literals ----

# The template object of a tagged template site (§13.2.8.4): a frozen array of the cooked
# strings with a frozen raw array, made once per site.
-> js_template_object(cooked, raw)
  c = js_mark_array(cooked)
  rw = js_mark_array(raw)
  js_array_ext(c, true).define("raw", rw, 0)
  js_array_freeze(rw)
  js_array_freeze(c)
  c

-> js_array_freeze(a)
  ext = js_array_ext(a, true)
  ext.define(JS_AK_SEALED, true, 0)
  ext.define(JS_AK_FROZEN, true, 0)
  ext.define(JS_AK_LENRO, true, 0)
  ext.prevent_extensions
  nil

# ---- shared by both tiers (moved from tier0/walk.w) ----

# A substitution in a template literal: ToString, which a Symbol refuses.
-> js_template_string(v)
  return v if js_string?(v)
  js_to_string(v)

# CopyDataProperties (spread in object literals and rest patterns).
-> js_copy_data_properties(o, src, excluded)
  return o if js_nullish?(src)
  from = js_object?(src) ? src : js_realm().wrap_primitive(src)
  ks = jown_keys(from)
  j = 0
  while j < ks.size
    kk = ks[j]
    if !excluded.include?(kk) && jenumerable?(from, kk)
      o.define(kk, jget(from, kk, src), ATTR_DEFAULT)
    j += 1
  o

# SetFunctionName for a computed key (the static ones are named by the analysis).
-> js_set_fn_name(f, key, prefix)
  return nil if !f.is_a?(JS:Function)
  nm = key.is_a?(JS:Symbol) ? (key.description == nil ? "" : "\[" + key.description + "]") : js_to_string(key)
  nm = prefix + " " + nm if prefix != nil
  f.define("name", nm, ATTR_C)
  nil

-> js_priv_get(o, pn)
  js_throw_type("Cannot read private member " + pn.to_s + " from an object whose class did not declare it") if !o.is_a?(JS:Base)
  o.priv_get(pn)

-> js_priv_set(o, pn, v)
  js_throw_type("Cannot write private member " + pn.to_s + " to an object whose class did not declare it") if !o.is_a?(JS:Base)
  o.priv_set(pn, v)

-> js_bigint_literal(s)
  t = s
  base = 10
  if t.size > 2 && t.byte_at(0) == 48
    b = t.byte_at(1) | 32
    base = b == 120 ? 16 : (b == 111 ? 8 : (b == 98 ? 2 : 10))
    t = t.slice(2, t.size - 2) if base != 10
  v = 0
  i = 0
  while i < t.size
    b = t.byte_at(i)
    v = v * base + js_digit(b) if b != 95
    i += 1
  JS:BigIntValue.new(v)

# ---- compiled code (tier 1): helpers the translator emits for the rarer constructs ----

# The unmapped arguments object of a compiled function (strict code or non-simple
# parameters; a mapped one keeps the function in tier 0).
-> js_args_object(argc, a0, a1, a2, a3, more)
  js_arguments(js_args_array(argc, a0, a1, a2, a3, more).dup, nil, false, nil, nil)

# A rest parameter: the arguments from index i on, as a JS array.
-> js_rest_args(i, argc, a0, a1, a2, a3, more)
  out = []
  j = i
  while j < argc
    out.push(j == 0 ? a0 : (j == 1 ? a1 : (j == 2 ? a2 : (j == 3 ? a3 : more[j]))))
    j += 1
  js_mark_array(out)

# new.target of the running function, taken (and cleared) once at its entry. Functions
# that never read it have CODE_NONT, so js_new does not set it for them.
-> js_take_nt
  v = JS_NEW_TARGET[0]
  JS_NEW_TARGET[0] = nil
  v

# for-in: is key k (from js_for_in_keys) still present when its turn comes?
-> js_for_in_has?(o, k)
  !js_object?(o) || jhas_property?(o, k)

# for-of: nil when v is an array iterated in place (its iterator is still the intrinsic
# one, which has no return method), else v's iterator record.
-> js_for_of_iter(v)
  return nil if js_array?(v) && js_array_iter_pristine?(v)
  js_get_iterator(v)

# The next value of a for-of (rec from js_for_of_iter, i the index for arrays), or
# JS_ITER_DONE.
-> js_for_of_step(v, rec, i)
  if rec == nil
    return JS_ITER_DONE if i >= js_arr_len(v)
    return js_arr_elem(v, i)
  js_iter_step(rec)

-> js_for_of_close(rec)
  js_iter_close(rec) if rec != nil
  nil

-> js_for_of_close_quiet(rec)
  js_iter_close_quiet(rec) if rec != nil
  nil

# Array destructuring: the array itself when it is iterated in place, else an iterator
# record. js_pat_step reads element i (an array) or takes the next value (a record).
-> js_pat_iter(v)
  return v if js_array?(v) && js_array_iter_pristine?(v)
  js_get_iterator(v)

-> js_pat_step(it, i)
  if js_array?(it)
    return nil if i >= js_arr_len(it)
    return js_arr_elem(it, i)
  return nil if it.done
  x = js_iter_step(it)
  x == JS_ITER_DONE ? nil : x

# An elision ([a, , b]): consumes a value of an iterator.
-> js_pat_skip(it)
  js_pat_step(it, 0) if !js_array?(it)
  nil

-> js_pat_rest(it, i)
  out = []
  if js_array?(it)
    while i < js_arr_len(it)
      out.push(js_arr_elem(it, i))
      i += 1
    return js_mark_array(out)
  while !it.done
    x = js_iter_step(it)
    out.push(x) if x != JS_ITER_DONE
  js_mark_array(out)

-> js_pat_close(it)
  js_iter_close(it) if !js_array?(it)
  nil

-> js_pat_close_quiet(it)
  js_iter_close_quiet(it) if !js_array?(it)
  nil

# Object destructuring of v (TypeError for undefined and null).
-> js_req_coercible(v)
  js_throw_type("Cannot destructure '" + js_to_display(v) + "' as it is " + (v == nil ? "undefined" : "null") + ".") if js_nullish?(v)
  v

# {...rest}: the own enumerable properties of v not named in used.
-> js_object_rest(v, used)
  js_copy_data_properties(js_new_object(js_realm().object_proto), v, used)

# get/set key(){} in an object literal: an accessor merged with the other half, if any.
-> js_lit_accessor(o, key, f, is_get)
  cur = o.get_own_property(key)
  g = is_get ? f : (cur != nil && cur.accessor? ? cur.getter : nil)
  st = is_get ? (cur != nil && cur.accessor? ? cur.setter : nil) : f
  o.define_accessor(key, g, st, ATTR_E + ATTR_C)
  nil

# __proto__: v in an object literal.
-> js_lit_proto(o, v)
  o.set_prototype_of(v) if js_object?(v) || v == JS_NULL
  nil

# #x in o
-> js_priv_in(o, pn)
  js_throw_type("Cannot use 'in' operator to search for a private field in a non-object") if !js_object?(o)
  o.is_a?(JS:Base) && o.priv_has?(pn)

# ---- classes (§15.7.14 ClassDefinitionEvaluation, as tier 0's wk_class) ----

# The constructor of a class (a JS:Method whose home is the new prototype object).
-> js_class_create(code, env, has_super, sup)
  r = js_realm()
  proto_parent = r.object_proto
  ctor_parent = r.function_proto
  if has_super
    if sup == JS_NULL
      proto_parent = nil
    else
      js_throw_type("Class extends value " + js_to_display_short(sup) + " is not a constructor or null") if !js_is_constructor?(sup)
      pp = jget(sup, "prototype")
      js_throw_type("Class extends value does not have valid prototype property " + js_to_display_short(pp)) if !js_object?(pp) && pp != JS_NULL
      proto_parent = pp == JS_NULL ? nil : pp
      ctor_parent = sup
  proto = js_new_object(proto_parent)
  f = js_method_closure(code, env, proto)
  f.set_prototype_of(ctor_parent) if ctor_parent != r.function_proto
  f.define("length", code.nparams.to_f, ATTR_C)
  f.define("name", code.name.to_s, ATTR_C)
  f.define("prototype", proto, 0)
  proto.define("constructor", f, ATTR_W + ATTR_C)
  f

-> js_home(f)
  f.home

# A public method or accessor of a class on target (the prototype, or the constructor).
-> js_class_method(target, key, fo, kind, computed)
  js_set_fn_name(fo, key, kind == "method" ? nil : kind)
  if kind == "method"
    ok = jdefine_own_property(target, key, JS:PropDesc.data(fo, ATTR_W + ATTR_C))
    js_throw_type("Cannot define property " + js_to_display(js_key_display(key))) if !ok
    return nil
  d = JS:PropDesc.new
  if kind == "get"
    d.getter = fo
    d.has_get = true
  else
    d.setter = fo
    d.has_set = true
  d.enumerable = false
  d.configurable = true
  ok = jdefine_own_property(target, key, d)
  js_throw_type("Cannot define property " + js_to_display(js_key_display(key))) if !ok
  nil

# A private method or accessor: on the constructor (static) or for every instance.
-> js_class_priv_method(f, is_static, pn, fo, kind)
  if is_static
    if kind == "method"
      f.priv_add_method(pn, fo)
    else
      f.priv_add_accessor(pn, kind == "get" ? fo : nil, kind == "set" ? fo : nil)
    return nil
  f.privs = [] if f.privs == nil
  f.privs.push([pn, fo, kind])
  nil

-> js_class_add_field(f, key, init)
  f.fields = [] if f.fields == nil
  f.fields.push([key, init])
  nil

# A static field, defined once the class is complete (this = the constructor).
-> js_class_static_field(f, key, init)
  v = init == nil ? nil : js_call(init, f, 0, nil, nil, nil, nil, nil)
  if key.is_a?(JS:PrivateName)
    f.priv_add(key, v)
  else
    jdefine_own_or_throw(f, key, v)
  nil

# The default constructor of a class (§15.7.14 step 10).
-> js_default_ctor(fobj, this, nt, derived, argc, a0, a1, a2, a3, more)
  if derived
    parent = fobj.get_prototype_of
    js_throw_type("Super constructor " + js_to_display_short(parent) + " of anonymous class is not a constructor") if !js_is_constructor?(parent)
    obj = js_construct(parent, js_args_array(argc, a0, a1, a2, a3, more).dup, nt)
    js_init_fields(obj, fobj)
    return obj
  js_init_fields(this, fobj)
  this

# What a class constructor's [[Construct]] returns for `return r` (or the end, r nil)
# when its this is t.
-> js_ctor_result(r, t, derived)
  return r if js_object?(r)
  js_throw_type("Derived constructors may only return object or undefined") if derived && r != nil
  js_throw_reference("Must call super constructor in derived class before accessing 'this' or returning from derived constructor") if t == nil
  t

# super.x / super[x] in a method whose object is fo, with receiver this.
-> js_super_get(fo, key, this)
  p = jget_prototype_of(fo.home)
  return nil if p == JS_NULL
  jget(p, key, js_enc_recv(this))

-> js_super_set(fo, key, v, this, strict)
  p = jget_prototype_of(fo.home)
  ok = p == JS_NULL ? false : jset(p, key, v, js_enc_recv(this))
  js_throw_type("Cannot assign to read only property '" + js_to_display(js_key_display(key)) + "' of object") if !ok && strict
  v

# super(...args): the parent constructor's object (the caller binds this, then
# initializes fields).
-> js_super_construct(fo, nt, args)
  parent = fo.get_prototype_of
  js_throw_type("Super constructor " + js_to_display_short(parent) + " of anonymous class is not a constructor") if !js_is_constructor?(parent)
  js_construct(parent, args, nt)

# A second super() call (this already bound).
-> js_super_bound(cur)
  js_throw_reference("Super constructor may only be called once") if cur != nil
  nil

# Function.prototype.toString for compiled code: the script's text (one per program)
# and each code's span in it.
JS_SCRIPT_SOURCE = [nil]

-> js_set_source(src)
  JS_SCRIPT_SOURCE[0] = src
  JS_FN_SOURCE_HOOK[0] = ->(f) js_code_source(f)
  nil

-> js_code_span(c, start, fin)
  c.start = start
  c.fin = fin
  c

-> js_code_source(f)
  c = f.code
  s = JS_SCRIPT_SOURCE[0]
  return nil if s == nil || c.fin <= c.start
  s.slice(c.start, c.fin - c.start)
