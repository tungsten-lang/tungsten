# unit/prelude — the base program of a compiled unit (tools/jsc.w with JSC_UNIT set).
#
# A unit holds the translated functions of one script (or a window of one) and nothing
# of the host: it is loaded into a running host (runtime/units.w) and reaches the host's
# runtime only through its context, ctx (a Tungsten Int holding the address of a
# host-made i64 table):
#
#   ctx[2k], ctx[2k+1]   (k < JSU_RT_MAX) the code pointer and captures of the host
#                        closure for runtime entry k (the unit's manifest names them)
#   ctx[JSU_SLOTS + j]   slot j: the raw bits of a host value (strings, global cells,
#                        codes, literal shapes, template objects, inline-cache tables)
#
# A host closure's code takes (captures, args...) with every argument a raw WValue
# (runtime/units.w makes one per entry), so a call through jsu_cN is an indirect call
# with no boxing. Strings longer than five bytes come from slots: a unit's own string
# slab means nothing in the host. The unit defines no classes and runs no main.

fn jsu_c0(ctx, k) (i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %k2 = shl i64 %k, 1
    %pf = getelementptr i64, ptr %base, i64 %k2
    %fn = load i64, ptr %pf
    %pc = getelementptr i64, ptr %pf, i64 1
    %caps = load i64, ptr %pc
    %fp = inttoptr i64 %fn to ptr
    %r = call i64 %fp(i64 %caps)
    ret i64 %r
  IR

fn jsu_c1(ctx, k, a0) (i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %k2 = shl i64 %k, 1
    %pf = getelementptr i64, ptr %base, i64 %k2
    %fn = load i64, ptr %pf
    %pc = getelementptr i64, ptr %pf, i64 1
    %caps = load i64, ptr %pc
    %fp = inttoptr i64 %fn to ptr
    %r = call i64 %fp(i64 %caps, i64 %a0)
    ret i64 %r
  IR

fn jsu_c2(ctx, k, a0, a1) (i64 i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %k2 = shl i64 %k, 1
    %pf = getelementptr i64, ptr %base, i64 %k2
    %fn = load i64, ptr %pf
    %pc = getelementptr i64, ptr %pf, i64 1
    %caps = load i64, ptr %pc
    %fp = inttoptr i64 %fn to ptr
    %r = call i64 %fp(i64 %caps, i64 %a0, i64 %a1)
    ret i64 %r
  IR

fn jsu_c3(ctx, k, a0, a1, a2) (i64 i64 i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %k2 = shl i64 %k, 1
    %pf = getelementptr i64, ptr %base, i64 %k2
    %fn = load i64, ptr %pf
    %pc = getelementptr i64, ptr %pf, i64 1
    %caps = load i64, ptr %pc
    %fp = inttoptr i64 %fn to ptr
    %r = call i64 %fp(i64 %caps, i64 %a0, i64 %a1, i64 %a2)
    ret i64 %r
  IR

fn jsu_c4(ctx, k, a0, a1, a2, a3) (i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %k2 = shl i64 %k, 1
    %pf = getelementptr i64, ptr %base, i64 %k2
    %fn = load i64, ptr %pf
    %pc = getelementptr i64, ptr %pf, i64 1
    %caps = load i64, ptr %pc
    %fp = inttoptr i64 %fn to ptr
    %r = call i64 %fp(i64 %caps, i64 %a0, i64 %a1, i64 %a2, i64 %a3)
    ret i64 %r
  IR

fn jsu_c5(ctx, k, a0, a1, a2, a3, a4) (i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %k2 = shl i64 %k, 1
    %pf = getelementptr i64, ptr %base, i64 %k2
    %fn = load i64, ptr %pf
    %pc = getelementptr i64, ptr %pf, i64 1
    %caps = load i64, ptr %pc
    %fp = inttoptr i64 %fn to ptr
    %r = call i64 %fp(i64 %caps, i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4)
    ret i64 %r
  IR

fn jsu_c6(ctx, k, a0, a1, a2, a3, a4, a5) (i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %k2 = shl i64 %k, 1
    %pf = getelementptr i64, ptr %base, i64 %k2
    %fn = load i64, ptr %pf
    %pc = getelementptr i64, ptr %pf, i64 1
    %caps = load i64, ptr %pc
    %fp = inttoptr i64 %fn to ptr
    %r = call i64 %fp(i64 %caps, i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5)
    ret i64 %r
  IR

fn jsu_c7(ctx, k, a0, a1, a2, a3, a4, a5, a6) (i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %k2 = shl i64 %k, 1
    %pf = getelementptr i64, ptr %base, i64 %k2
    %fn = load i64, ptr %pf
    %pc = getelementptr i64, ptr %pf, i64 1
    %caps = load i64, ptr %pc
    %fp = inttoptr i64 %fn to ptr
    %r = call i64 %fp(i64 %caps, i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6)
    ret i64 %r
  IR

fn jsu_c8(ctx, k, a0, a1, a2, a3, a4, a5, a6, a7) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %k2 = shl i64 %k, 1
    %pf = getelementptr i64, ptr %base, i64 %k2
    %fn = load i64, ptr %pf
    %pc = getelementptr i64, ptr %pf, i64 1
    %caps = load i64, ptr %pc
    %fp = inttoptr i64 %fn to ptr
    %r = call i64 %fp(i64 %caps, i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7)
    ret i64 %r
  IR

fn jsu_c9(ctx, k, a0, a1, a2, a3, a4, a5, a6, a7, a8) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %k2 = shl i64 %k, 1
    %pf = getelementptr i64, ptr %base, i64 %k2
    %fn = load i64, ptr %pf
    %pc = getelementptr i64, ptr %pf, i64 1
    %caps = load i64, ptr %pc
    %fp = inttoptr i64 %fn to ptr
    %r = call i64 %fp(i64 %caps, i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7, i64 %a8)
    ret i64 %r
  IR

fn jsu_c10(ctx, k, a0, a1, a2, a3, a4, a5, a6, a7, a8, a9) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %k2 = shl i64 %k, 1
    %pf = getelementptr i64, ptr %base, i64 %k2
    %fn = load i64, ptr %pf
    %pc = getelementptr i64, ptr %pf, i64 1
    %caps = load i64, ptr %pc
    %fp = inttoptr i64 %fn to ptr
    %r = call i64 %fp(i64 %caps, i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7, i64 %a8, i64 %a9)
    ret i64 %r
  IR

fn jsu_c11(ctx, k, a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %k2 = shl i64 %k, 1
    %pf = getelementptr i64, ptr %base, i64 %k2
    %fn = load i64, ptr %pf
    %pc = getelementptr i64, ptr %pf, i64 1
    %caps = load i64, ptr %pc
    %fp = inttoptr i64 %fn to ptr
    %r = call i64 %fp(i64 %caps, i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7, i64 %a8, i64 %a9, i64 %a10)
    ret i64 %r
  IR

# Slot j of the context (raw bits of a host value).
fn jsu_k(ctx, j) (i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ctx to ptr
    %j2 = add i64 %j, 1024
    %p = getelementptr i64, ptr %base, i64 %j2
    %v = load i64, ptr %p
    ret i64 %v
  IR
