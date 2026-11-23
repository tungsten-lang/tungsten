# unit/prelude — the base program of a compiled unit (tools/jsc.w with JSC_UNIT set).
#
# A unit holds the translated functions of one script (or a window of one) and nothing
# of the host: it is loaded into a running host (runtime/units.w) and reaches the host's
# runtime only through its context, ctx (a Tungsten Int holding the address of a
# host-made i64 table):
#
#   ctx[2k]              (k < 512) the host closure for runtime entry k (the unit's
#                        manifest names them)
#   ctx[JSU_SLOTS + j]   slot j: the raw bits of a host value (strings, global cells,
#                        codes, literal shapes, template objects, inline-cache tables)
#
# A call through jsu_cN is w_closure_call_N on the host's closure for the entry
# (runtime/units.w makes one per entry). Strings longer than five bytes come from slots:
# a unit's own string slab means nothing in the host. The unit defines no classes and
# runs no main.

# The host closure for runtime entry k (ctx[2k] holds its bits).
fn jsu_rt(ctx, k) (i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %k2 = shl i64 %k, 1
    %p = getelementptr i64, ptr %base, i64 %k2
    %v = load i64, ptr %p
    ret i64 %v
  IR

# Runtime entry k with n arguments. A C call, so the compiler sees every argument escape:
# a value passed only as raw bits would look unused, and what the unit allocated (an
# Array literal) would be freed when the function returned.
-> jsu_c0(ctx, k)
  ccall("w_closure_call_0", wvalue_from_bits(jsu_rt(ctx, k)))

-> jsu_c1(ctx, k, a0)
  ccall("w_closure_call_1", wvalue_from_bits(jsu_rt(ctx, k)), a0)

-> jsu_c2(ctx, k, a0, a1)
  ccall("w_closure_call_2", wvalue_from_bits(jsu_rt(ctx, k)), a0, a1)

-> jsu_c3(ctx, k, a0, a1, a2)
  ccall("w_closure_call_3", wvalue_from_bits(jsu_rt(ctx, k)), a0, a1, a2)

-> jsu_c4(ctx, k, a0, a1, a2, a3)
  ccall("w_closure_call_4", wvalue_from_bits(jsu_rt(ctx, k)), a0, a1, a2, a3)

-> jsu_c5(ctx, k, a0, a1, a2, a3, a4)
  ccall("w_closure_call_5", wvalue_from_bits(jsu_rt(ctx, k)), a0, a1, a2, a3, a4)

-> jsu_c6(ctx, k, a0, a1, a2, a3, a4, a5)
  ccall("w_closure_call_6", wvalue_from_bits(jsu_rt(ctx, k)), a0, a1, a2, a3, a4, a5)

-> jsu_c7(ctx, k, a0, a1, a2, a3, a4, a5, a6)
  ccall("w_closure_call_7", wvalue_from_bits(jsu_rt(ctx, k)), a0, a1, a2, a3, a4, a5, a6)

-> jsu_c8(ctx, k, a0, a1, a2, a3, a4, a5, a6, a7)
  ccall("w_closure_call_8", wvalue_from_bits(jsu_rt(ctx, k)), a0, a1, a2, a3, a4, a5, a6, a7)

-> jsu_c9(ctx, k, a0, a1, a2, a3, a4, a5, a6, a7, a8)
  ccall("w_closure_call_9", wvalue_from_bits(jsu_rt(ctx, k)), a0, a1, a2, a3, a4, a5, a6, a7, a8)

-> jsu_c10(ctx, k, a0, a1, a2, a3, a4, a5, a6, a7, a8, a9)
  ccall("w_closure_call_10", wvalue_from_bits(jsu_rt(ctx, k)), a0, a1, a2, a3, a4, a5, a6, a7, a8, a9)

# Slot j of the context (raw bits of a host value).
fn jsu_k(ctx, j) (i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %j2 = add i64 %j, 1024
    %p = getelementptr i64, ptr %base, i64 %j2
    %v = load i64, ptr %p
    ret i64 %v
  IR

# ---- fast forms (translate/unit.w JSU_FAST): inline lanes, the rest through the host
# entry at the fixed index of JSU_FIXED ----

use ../runtime/prims

-> jsu_add(ctx, a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fadd(ab, bb)) if jsr_nn(ab, bb) != 0
  jsu_c2(ctx, 0, a, b)

-> jsu_sub(ctx, a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fsub(ab, bb)) if jsr_nn(ab, bb) != 0
  jsu_c2(ctx, 1, a, b)

-> jsu_mul(ctx, a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fmul(ab, bb)) if jsr_nn(ab, bb) != 0
  jsu_c2(ctx, 2, a, b)

-> jsu_lt(ctx, a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_flt(ab, bb)) if jsr_nn(ab, bb) != 0
  jsu_c2(ctx, 3, a, b)

-> jsu_gt(ctx, a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_flt(bb, ab)) if jsr_nn(ab, bb) != 0
  jsu_c2(ctx, 4, a, b)

-> jsu_le(ctx, a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fle(ab, bb)) if jsr_nn(ab, bb) != 0
  jsu_c2(ctx, 5, a, b)

-> jsu_ge(ctx, a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_fle(bb, ab)) if jsr_nn(ab, bb) != 0
  jsu_c2(ctx, 6, a, b)

-> jsu_seq(ctx, a, b)
  ab = wvalue_bits(a) ## i64
  bb = wvalue_bits(b) ## i64
  return wvalue_from_bits(jsr_feq(ab, bb)) if jsr_nn(ab, bb) != 0
  return true if ab == bb && jsr_num(ab) == 0
  jsu_c2(ctx, 7, a, b)

-> jsu_truthy(ctx, v)
  return v if v == true || v == false
  return false if v == nil
  vb = wvalue_bits(v) ## i64
  return v != ~0.0 && v == v if jsr_num(vb) != 0
  jsu_c1(ctx, 8, v) == true

# Inline-cache reads and writes (runtime/object.w jsr_ic_get / jsr_ic_set), against the
# host's prototype epoch (slot 1 holds its address).
fn jsu_ic_get(ic, k, ob, epoch) (i64[] i64 i64 i64) i64
  s = jsr_shape(ob)
  if s == 0 || s != ic[k]
    return 6
  i = ic[k + 1]
  h = ic[k + 2]
  if h == 0
    if i > 0
      return jsr_ivar(ob, i)
    return 6
  if ic[k + 3] != epoch || i <= 0
    return 6
  jsr_ivar(h, i)

fn jsu_ic_set(ic, k, ob, epoch) (i64[] i64 i64 i64) i64
  s = jsr_shape(ob)
  if s == 0 || s != ic[k]
    return 0
  ns = ic[k + 2]
  if ns != 0
    if ic[k + 3] != epoch
      return 0
    jsr_set_shape(ob, ns)
  ic[k + 1]

fn jsu_epoch(ctx) (i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %p = getelementptr i64, ptr %base, i64 1025
    %ep = load i64, ptr %p
    %e = inttoptr i64 %ep to ptr
    %v = load i64, ptr %e
    ret i64 %v
  IR

-> jsu_getp(ctx, o, key, ic, k)
  ob = wvalue_bits(o) ## i64
  r = jsu_ic_get(ic, k, ob, jsu_epoch(ctx))
  return wvalue_from_bits(r) if r != 6
  jsu_c4(ctx, 9, o, key, ic, k)

-> jsu_setp(ctx, o, key, v, ic, k)
  ob = wvalue_bits(o) ## i64
  i = jsu_ic_set(ic, k, ob, jsu_epoch(ctx))
  if i > 0
    ccall("w_ivar_set_idx", o, i, v)
    return v
  jsu_c5(ctx, 10, o, key, v, ic, k)

# A global read: the cell's value while it is plain (runtime/realm.w js_gget).
fn jsu_gcell_fast(cb) (i64) i64
  v = jsr_ivar(cb, 0)
  if v == 3
    return 6
  v

-> jsu_gget(ctx, c)
  cb = wvalue_bits(c) ## i64
  v = jsu_gcell_fast(cb)
  return wvalue_from_bits(v) if v != 6
  jsu_c1(ctx, 12, c)

# A call: a compiled function (any unit's) is entered directly through its JS:Code's entry
# closure (ivar 8, runtime/function.w); anything else through the host's js_call.
-> jsu_call(ctx, f, this, argc, a0, a1, a2, a3, more)
  fb = wvalue_bits(f) ## i64
  if (jsr_kind(fb) & 15) == 2
    e = wvalue_from_bits(jsr_ivar(jsr_ivar(fb, 2), 8))
    return ccall("w_closure_call_8", e, f, this, argc, a0, a1, a2, a3, more) if e != 0
  jsu_c8(ctx, 11, f, this, argc, a0, a1, a2, a3, more)
