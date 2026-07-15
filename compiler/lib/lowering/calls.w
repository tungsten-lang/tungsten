# Lowering / calls — variable resolution + call dispatch + method calls.
# Includes the ~25 fast-path specializations (typed array calls,
# StringBuffer calls, known C calls), the inline-iterator path, the
# direct static-method path, and lower_puts / lower_print.
#
# Depends on pass_registry.w, types.w, literals.w, ops.w, monomorphize.w,
# blocks.w, control_flow.w. This file deliberately has no `use`
# directives — see pass_registry.w.


# Expand trailing kwargs hash literal into positional args.
# pad("hi", 10, align: "right") has args = ["hi", 10, {hash: [[":align", "right"]]}]
# → expanded to ["hi", 10, "right"] (values in source order)
-> expand_kwargs(args)
  if args == nil || args.size() == 0
    return args
  last = args[args.size() - 1]
  if last == nil || ast_kind(last) != :hash_literal || last.from_kwargs != true
    return args
  expanded = []
  i = 0
  while i < args.size() - 1
    expanded.push(args[i])
    i += 1
  entries = last.entries
  if entries != nil
    i = 0
    while i < entries.size()
      expanded.push(entries[i][1])
      i += 1
  expanded

# -- Calls --

-> call_has_ast_block?(node)
  block = node.block
  block != nil && is_ast_node?(block)

-> name_is_local_var?(wfn, ctx, name)
  if wfn[:var_slots] != nil && wfn[:var_slots][name] != nil
    return true
  if ctx[:bindings] != nil && ctx[:bindings][name] != nil
    return true
  if ctx[:unboxed_vars] != nil && ctx[:unboxed_vars][name] != nil
    return true
  i = 0
  while i < wfn[:params].size()
    if wfn[:params][i] == name
      return true
    i += 1
  if ctx[:mod][:top_level_vars] != nil && ctx[:mod][:top_level_vars][name] == true
    return true
  false

-> lower_call(ctx, node)
  wfn = ctx[:func]
  name = node.name
  receiver = node.receiver
  args = expand_kwargs(node.args)

  # Compiler-generated typed-overload dispatch. These calls never appear in
  # user AST: definitions.w synthesizes them only after it has selected the
  # exact worker set for a class. Keep both operations out of dynamic method
  # dispatch — the former calls the runtime ancestry primitive directly and
  # the latter calls the already-known internal worker symbol.
  if name in ("__compiler_overload_is_a" "__compiler_overload_worker")
    marker = ast_get(node, :compiler_intrinsic)
    expected_marker = :overload_is_a
    if name == "__compiler_overload_worker"
      expected_marker = :overload_worker
    if marker != expected_marker
      raise compile_error_for_node(:E_LOWER_RESERVED_INTRINSIC, "reserved compiler intrinsic '" + name + "'", ctx[:source_path], node)

  if name == "__compiler_overload_is_a" && receiver == nil && args != nil && args.size() == 2
    recv_tv = lower_expression(ctx, args[0])
    type_tv = lower_expression(ctx, args[1])
    recv_reg = ensure_i64_value(wfn, recv_tv)
    type_reg = ensure_i64_value(wfn, type_tv)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_value_is_a", args: [recv_reg, type_reg]})
    return typed_value(:i64, temp)

  if name == "__compiler_overload_worker" && receiver == nil && args != nil && args.size() >= 2
    target_node = args[0]
    if ast_kind(target_node) != :string
      << "internal overload worker target must be a string literal"
      exit(1)
    target = target_node.value
    call_args = []
    i = 1
    while i < args.size()
      arg_tv = lower_expression(ctx, args[i])
      call_args.push(ensure_i64_value(wfn, arg_tv))
      i += 1
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: target, args: call_args})
    return typed_value(:i64, temp)

  # Low-level WValue bit casts used by source-defined packed value classes.
  # Both representations are LLVM i64, so these are deliberately emit-free:
  # `wvalue_bits` exposes an arbitrary boxed value as a raw machine integer,
  # while `wvalue_from_bits` marks a raw bit pattern as an already-boxed
  # WValue. Keeping this boundary in the compiler lets packed constructors
  # move into core/*.w without replacing one runtime implementation with a
  # one-line C identity helper.
  if name == "wvalue_bits" && receiver == nil && args != nil && args.size() == 1
    value = lower_expression(ctx, args[0])
    return typed_value(:raw_i64, ensure_i64_value(wfn, value))

  if name == "wvalue_from_bits" && receiver == nil && args != nil && args.size() == 1
    value = lower_expression(ctx, args[0])
    inferred = infer_type(args[0], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    return typed_value(:i64, ensure_raw_machine_int(wfn, value, :i64, inferred))

  # Carry-primitive intrinsic: `mulhi(a, b)` = high 64 bits of the unsigned
  # 64x64->128 product, lowered to a single UMULH (arm64) / MULX (x86). Builtin
  # because the surface can't express the high half of a wide multiply; it's the
  # keystone for fast multi-word bignum (SSA / Montgomery). Returns :raw_i64.
  if name == "mulhi" && receiver == nil && args != nil && args.size() == 2
    a_raw = lower_machine_int_expression(ctx, args[0], :u64)
    b_raw = lower_machine_int_expression(ctx, args[1], :u64)
    t = next_temp(wfn)
    emit_instruction(wfn, {op: :mulhi_u64, temp: t, lhs: a_raw, rhs: b_raw})
    return typed_value(:raw_i64, t)

  # Carry-primitives `addcarry(a,b)` / `subborrow(a,b)` = the carry-out / borrow-out
  # (0 or 1) of a+b / a-b, lowered via i128 so LLVM threads the carry in the flag
  # (ADDS/ADCS, SUBS/SBCS) instead of CMP/CSET. Drop-in for the `(s < a)` carry
  # idiom in multi-word add/sub. Returns :raw_i64.
  if name == "addcarry" && receiver == nil && args != nil && args.size() == 2
    a_raw = lower_machine_int_expression(ctx, args[0], :u64)
    b_raw = lower_machine_int_expression(ctx, args[1], :u64)
    t = next_temp(wfn)
    emit_instruction(wfn, {op: :addcarry_u64, temp: t, lhs: a_raw, rhs: b_raw})
    return typed_value(:raw_i64, t)
  if name == "subborrow" && receiver == nil && args != nil && args.size() == 2
    a_raw = lower_machine_int_expression(ctx, args[0], :u64)
    b_raw = lower_machine_int_expression(ctx, args[1], :u64)
    t = next_temp(wfn)
    emit_instruction(wfn, {op: :subborrow_u64, temp: t, lhs: a_raw, rhs: b_raw})
    return typed_value(:raw_i64, t)

  # POC: inline-asm feasibility — asm_add(a,b) = a+b via an LLVM inline-asm ADD.
  if name == "asm_add" && receiver == nil && args != nil && args.size() == 2
    a_raw = lower_machine_int_expression(ctx, args[0], :u64)
    b_raw = lower_machine_int_expression(ctx, args[1], :u64)
    t = next_temp(wfn)
    emit_instruction(wfn, {op: :asm_add_test, temp: t, lhs: a_raw, rhs: b_raw})
    return typed_value(:raw_i64, t)

  # arr_data_ptr(u64arr) → raw data-base pointer as i64.
  if name == "arr_data_ptr" && receiver == nil && args != nil && args.size() == 1
    av = lower_expression(ctx, args[0])
    t = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: t, arr: av[:value]})
    return typed_value(:raw_i64, t)

  # asm_add_n(out, a, b, n): out[0..n) = a[0..n) + b[0..n) via a GMP-shape adc
  # loop; returns the carry-out. POC for hand-asm bignum basecase.
  if name == "asm_add_n" && receiver == nil && args != nil && args.size() == 4
    ov = lower_expression(ctx, args[0])
    av = lower_expression(ctx, args[1])
    bv = lower_expression(ctx, args[2])
    nv = lower_expression(ctx, args[3])
    nt = infer_type(args[3], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    nraw = ensure_raw_machine_int(wfn, nv, :i64, nt)
    to = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: to, arr: ov[:value]})
    ta = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: ta, arr: av[:value]})
    tb = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: tb, arr: bv[:value]})
    tc = next_temp(wfn)
    emit_instruction(wfn, {op: :asm_add_n, temp: tc, outp: to, ap: ta, bp: tb, n: nraw})
    return typed_value(:raw_i64, tc)

  # POC: NEON SIMD 2-lane umull — asm_neon_umull(out, a, b, npairs): for each i,
  # out[2i],out[2i+1] = (u32 lanes of a[i]) * (u32 lanes of b[i]) via NEON umull
  # (32x32->64, 2 lanes). a/b are u64[npairs] (2 packed u32 each), out u64[2*npairs].
  # Proves Tungsten can emit working vector inline asm.
  if name == "asm_neon_umull" && receiver == nil && args != nil && args.size() == 4
    ov = lower_expression(ctx, args[0])
    av = lower_expression(ctx, args[1])
    bv = lower_expression(ctx, args[2])
    nv = lower_expression(ctx, args[3])
    nt = infer_type(args[3], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    nraw = ensure_raw_machine_int(wfn, nv, :i64, nt)
    to = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: to, arr: ov[:value]})
    ta = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: ta, arr: av[:value]})
    tb = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: tb, arr: bv[:value]})
    tc = next_temp(wfn)
    emit_instruction(wfn, {op: :asm_neon_umull, temp: tc, outp: to, ap: ta, bp: tb, n: nraw})
    return typed_value(:raw_i64, tc)

  # POC: NEON SIMD 2-lane Montgomery modmul — asm_neon_redc(out, a, b, npairs):
  # out[i] lanes = REDC(a[i]*b[i]) mod p=998244353 (119*2^23+1), 2 u32 lanes/elem.
  # Proves a full SIMD modular multiply (umull + Montgomery reduce, all in NEON).
  if name == "asm_neon_redc" && receiver == nil && args != nil && args.size() == 4
    ov = lower_expression(ctx, args[0])
    av = lower_expression(ctx, args[1])
    bv = lower_expression(ctx, args[2])
    nv = lower_expression(ctx, args[3])
    nt = infer_type(args[3], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    nraw = ensure_raw_machine_int(wfn, nv, :i64, nt)
    to = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: to, arr: ov[:value]})
    ta = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: ta, arr: av[:value]})
    tb = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: tb, arr: bv[:value]})
    tc = next_temp(wfn)
    emit_instruction(wfn, {op: :asm_neon_redc, temp: tc, outp: to, ap: ta, bp: tb, n: nraw})
    return typed_value(:raw_i64, tc)

  # NEON SIMD 4-lane Montgomery modmul / modadd / modsub mod p=998244353.
  # *4(out, a, b, npairs): each pair = 2 u64 elems (4 packed u32). out=u64[npairs].
  if (name == "asm_neon_redc4" || name == "asm_neon_madd4" || name == "asm_neon_msub4") && receiver == nil && args != nil && args.size() == 4
    ov = lower_expression(ctx, args[0])
    av = lower_expression(ctx, args[1])
    bv = lower_expression(ctx, args[2])
    nv = lower_expression(ctx, args[3])
    nt = infer_type(args[3], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    nraw = ensure_raw_machine_int(wfn, nv, :i64, nt)
    to = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: to, arr: ov[:value]})
    ta = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: ta, arr: av[:value]})
    tb = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: tb, arr: bv[:value]})
    tc = next_temp(wfn)
    theop = :asm_neon_redc4
    if name == "asm_neon_madd4"
      theop = :asm_neon_madd4
    if name == "asm_neon_msub4"
      theop = :asm_neon_msub4
    emit_instruction(wfn, {op: theop, temp: tc, outp: to, ap: ta, bp: tb, n: nraw})
    return typed_value(:raw_i64, tc)

  # NEON whole-butterfly DIT NTT stage — asm_neon_ntt_stage(v, stw, nblocks, halfq):
  # v=coeffs 4xu32/16B, stw=per-stage twiddles, nblocks=llen/len, halfq=half/4.
  if name == "asm_neon_ntt_stage" && receiver == nil && args != nil && args.size() == 4
    vv = lower_expression(ctx, args[0])
    wv = lower_expression(ctx, args[1])
    nbv = lower_expression(ctx, args[2])
    nbt = infer_type(args[2], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    nbr = ensure_raw_machine_int(wfn, nbv, :i64, nbt)
    hqv = lower_expression(ctx, args[3])
    hqt = infer_type(args[3], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    hqr = ensure_raw_machine_int(wfn, hqv, :i64, hqt)
    tvp = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: tvp, arr: vv[:value]})
    ttwp = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: ttwp, arr: wv[:value]})
    tc = next_temp(wfn)
    emit_instruction(wfn, {op: :asm_neon_ntt_stage, temp: tc, vp: tvp, twp: ttwp, nb: nbr, hq: hqr})
    return typed_value(:raw_i64, tc)

  # Scalar Goldilocks radix-4 DIF NTT stage — asm_gold_stage(v, stw, nblocks, q):
  # v = u64 coeffs; stw = per-stage twiddles prepacked 3/group (w1,w2,w3 for
  # p=0..q-1, consecutive). For each of nblocks blocks (block = 4*q coeffs):
  #   for group p<q: i0=base+p, i1=i0+q, i2=i0+2q, i3=i0+3q (u64 indices)
  #   t0=x0+x2; t1=x0-x2; t2=x1+x3; t3=mulI(x1-x3) [mulI = *2^48 shift-reduce];
  #   y0=t0+t2; y1=t1-t3; y2=t0-t2; y3=t1+t3;
  #   v[i0]=y0; v[i1]=y1*w1; v[i2]=y2*w2; v[i3]=y3*w3.  P=2^64-2^32+1.
  if name == "asm_gold_stage" && receiver == nil && args != nil && args.size() == 4
    vv = lower_expression(ctx, args[0])
    wv = lower_expression(ctx, args[1])
    nbv = lower_expression(ctx, args[2])
    nbt = infer_type(args[2], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    nbr = ensure_raw_machine_int(wfn, nbv, :i64, nbt)
    qv = lower_expression(ctx, args[3])
    qt = infer_type(args[3], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    qr = ensure_raw_machine_int(wfn, qv, :i64, qt)
    tvp = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: tvp, arr: vv[:value]})
    ttwp = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: ttwp, arr: wv[:value]})
    tc = next_temp(wfn)
    emit_instruction(wfn, {op: :asm_gold_stage, temp: tc, vp: tvp, twp: ttwp, nb: nbr, hq: qr})
    return typed_value(:raw_i64, tc)

  # Scalar Goldilocks radix-4 DIT (inverse) NTT stage —
  # asm_gold_stage_inv(v, stw, iv, nblocks, q): stw = inverse twiddles 3/group,
  # iv[0] = iinv (= I^-1). For each block (4*q coeffs), each group p<q:
  #   a0=x0; a1=x1*w1; a2=x2*w2; a3=x3*w3 (twiddle FIRST);
  #   t0=a0+a2; t1=a0-a2; t2=a1+a3; t3=gmul(a1-a3, iinv);
  #   v[i0]=t0+t2; v[i1]=t1-t3; v[i2]=t0-t2; v[i3]=t1+t3.  P=2^64-2^32+1.
  if name == "asm_gold_stage_inv" && receiver == nil && args != nil && args.size() == 5
    vv = lower_expression(ctx, args[0])
    wv = lower_expression(ctx, args[1])
    ivv = lower_expression(ctx, args[2])
    nbv = lower_expression(ctx, args[3])
    nbt = infer_type(args[3], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    nbr = ensure_raw_machine_int(wfn, nbv, :i64, nbt)
    qv = lower_expression(ctx, args[4])
    qt = infer_type(args[4], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    qr = ensure_raw_machine_int(wfn, qv, :i64, qt)
    tvp = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: tvp, arr: vv[:value]})
    ttwp = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: ttwp, arr: wv[:value]})
    tivp = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: tivp, arr: ivv[:value]})
    tc = next_temp(wfn)
    emit_instruction(wfn, {op: :asm_gold_stage_inv, temp: tc, vp: tvp, twp: ttwp, ivp: tivp, nb: nbr, hq: qr})
    return typed_value(:raw_i64, tc)

  # NEON SIMD 2-lane Goldilocks add — asm_neon_gadd2(out, a, b, npairs):
  # out[2i,2i+1] = gadd(a[..],b[..]) mod P=2^64-2^32+1, 2 u64 lanes/op.
  if name == "asm_neon_gadd2" && receiver == nil && args != nil && args.size() == 4
    ov = lower_expression(ctx, args[0])
    av = lower_expression(ctx, args[1])
    bv = lower_expression(ctx, args[2])
    nv = lower_expression(ctx, args[3])
    nt = infer_type(args[3], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    nraw = ensure_raw_machine_int(wfn, nv, :i64, nt)
    to = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: to, arr: ov[:value]})
    ta = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: ta, arr: av[:value]})
    tb = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: tb, arr: bv[:value]})
    tc = next_temp(wfn)
    emit_instruction(wfn, {op: :asm_neon_gadd2, temp: tc, outp: to, ap: ta, bp: tb, n: nraw})
    return typed_value(:raw_i64, tc)

  # asm_add_no(out, oo, a, ao, b, bo, n): offset add_n; GMP adc loop; returns carry.
  if name == "asm_add_no" && receiver == nil && args != nil && args.size() == 7
    ov = lower_expression(ctx, args[0])
    oor = lower_machine_int_expression(ctx, args[1], :i64)
    av = lower_expression(ctx, args[2])
    aor = lower_machine_int_expression(ctx, args[3], :i64)
    bv = lower_expression(ctx, args[4])
    bor = lower_machine_int_expression(ctx, args[5], :i64)
    nraw = lower_machine_int_expression(ctx, args[6], :i64)
    to = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: to, arr: ov[:value]})
    ta = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: ta, arr: av[:value]})
    tb = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: tb, arr: bv[:value]})
    tc = next_temp(wfn)
    emit_instruction(wfn, {op: :asm_add_no, temp: tc, outp: to, ooff: oor, ap: ta, aoff: aor, bp: tb, boff: bor, n: nraw})
    return typed_value(:raw_i64, tc)

  # asm_sub_no(out, oo, a, ao, b, bo, n): offset sub_n; GMP sbcs loop; returns borrow.
  if name == "asm_sub_no" && receiver == nil && args != nil && args.size() == 7
    ov = lower_expression(ctx, args[0])
    oor = lower_machine_int_expression(ctx, args[1], :i64)
    av = lower_expression(ctx, args[2])
    aor = lower_machine_int_expression(ctx, args[3], :i64)
    bv = lower_expression(ctx, args[4])
    bor = lower_machine_int_expression(ctx, args[5], :i64)
    nraw = lower_machine_int_expression(ctx, args[6], :i64)
    to = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: to, arr: ov[:value]})
    ta = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: ta, arr: av[:value]})
    tb = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: tb, arr: bv[:value]})
    tc = next_temp(wfn)
    emit_instruction(wfn, {op: :asm_sub_no, temp: tc, outp: to, ooff: oor, ap: ta, aoff: aor, bp: tb, boff: bor, n: nraw})
    return typed_value(:raw_i64, tc)

  # asm_addmul1(out, oo, a, ao, bsc, n): offset addmul_1 (GMP __gmpn_addmul_1);
  # out[oo..] += a[ao..]*bsc; returns carry-out. The dominant Toom basecase loop.
  if name == "asm_addmul1" && receiver == nil && args != nil && args.size() == 6
    ov = lower_expression(ctx, args[0])
    oor = lower_machine_int_expression(ctx, args[1], :i64)
    av = lower_expression(ctx, args[2])
    aor = lower_machine_int_expression(ctx, args[3], :i64)
    bsc = lower_machine_int_expression(ctx, args[4], :u64)
    nraw = lower_machine_int_expression(ctx, args[5], :i64)
    to = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: to, arr: ov[:value]})
    ta = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: ta, arr: av[:value]})
    tc = next_temp(wfn)
    emit_instruction(wfn, {op: :asm_addmul1, temp: tc, outp: to, ooff: oor, ap: ta, aoff: aor, bsc: bsc, n: nraw})
    return typed_value(:raw_i64, tc)

  # asm_mulbase(out, oo, a, ao, b, bo, na, nb): GMP mpn_mul_basecase in one asm
  # block; out[oo..oo+na+nb) = a[ao..]*b[bo..]. One call/basecase. Returns 0.
  if name == "asm_mulbase" && receiver == nil && args != nil && args.size() == 8
    ov = lower_expression(ctx, args[0])
    oor = lower_machine_int_expression(ctx, args[1], :i64)
    av = lower_expression(ctx, args[2])
    aor = lower_machine_int_expression(ctx, args[3], :i64)
    bv = lower_expression(ctx, args[4])
    bor = lower_machine_int_expression(ctx, args[5], :i64)
    nar = lower_machine_int_expression(ctx, args[6], :i64)
    nbr = lower_machine_int_expression(ctx, args[7], :i64)
    to = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: to, arr: ov[:value]})
    ta = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: ta, arr: av[:value]})
    tb = next_temp(wfn)
    emit_instruction(wfn, {op: :arr_data_ptr, temp: tb, arr: bv[:value]})
    tc = next_temp(wfn)
    emit_instruction(wfn, {op: :asm_mulbase, temp: tc, outp: to, ooff: oor, ap: ta, aoff: aor, bp: tb, boff: bor, na: nar, nb: nbr})
    return typed_value(:raw_i64, tc)

  # Phase 2 lazy pipeline: `source.lazy/sq/cube.take(n)`. `.take(n)` on a
  # fused-pipeline receiver (:map / :calc) routes to a take-bounded
  # variant of lower_pipeline that exits after n produced elements —
  # one loop, no source materialization. `.lazy` is a passthrough
  # marker; fuse_pipeline unwraps `Call(_, "lazy", [])` at the base.
  if name == "take" && args != nil && args.size() == 1 && is_ast_node?(receiver) && ast_kind(receiver) in (:map :calc)
    materialize_bindings(ctx)
    return lower_pipeline(ctx, receiver, args[0])
  if name == "lazy" && (args == nil || args.size() == 0) && receiver != nil
    return lower_expression(ctx, receiver)

  # Explicit fused multiply-add: `fma(a, b, c)` over floats lowers to
  # llvm.fma.f64 — a GUARANTEED single-rounding fuse on every target (soft-float
  # fallback where no hardware FMA exists), like C's fma() from <math.h>. This
  # is the ONLY way to get an FMA in strict math mode, and it fuses in every
  # mode. Gated on all three args being statically float so a user-defined
  # `fma` over other types still dispatches normally. Operands ride on
  # lhs/rhs/value (apply_subst / content_hash already rewrite those — see the
  # :fmuladd_f64 emitter case).
  if receiver == nil && name == "fma" && args != nil && args.size() == 3
    fa0 = infer_type(args[0], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    fa1 = infer_type(args[1], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    fa2 = infer_type(args[2], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    if fa0 in (:float :f64) && fa1 in (:float :f64) && fa2 in (:float :f64)
      fma_a = ensure_raw_f64(wfn, lower_expression(ctx, args[0]))
      fma_b = ensure_raw_f64(wfn, lower_expression(ctx, args[1]))
      fma_c = ensure_raw_f64(wfn, lower_expression(ctx, args[2]))
      fma_t = next_temp(wfn)
      emit_instruction(wfn, {op: :fma_f64, temp: fma_t, lhs: fma_a, rhs: fma_b, value: fma_c})
      return typed_value(:raw_f64, fma_t)

  # Phase 6i follow-up: rewrite `$bytes[i]` / `$bits[i]` (and any
  # `$<view>[i]`) into a :view_access AST node. The lexer emits the
  # `$<name>` as a :GLOBAL token which the parser turns into a :gvar
  # node (older parsers used :var), so the index call lands here as
  # `:call recv=:gvar "$bytes",
  # name="[]"`. Routing through lower_view_access produces the
  # view_load_byte / view_load_bit ops with proper !range metadata.
  if receiver != nil && name in ("\[]" "[]") && args.size() == 1 && (ast_kind(receiver) == :var || ast_kind(receiver) == :gvar) && receiver.name != nil && receiver.name.starts_with?("$") && ctx[:class_name] != nil
    bare = receiver.name.slice(1, receiver.name.size() - 1)
    finfo = view_field_info(ctx, bare)
    # Fixed inline arrays live at field_offset + index inside the receiver's
    # backing struct. The containing method performs its own semantic bounds
    # check; this lowering is deliberately a bounds-independent raw u8 load.
    if finfo != nil && inline_u8_array_field?(finfo[:type])
      self_tv = lower_var(ctx, Tungsten:AST:Var.new("__self"))
      self_reg = ensure_i64_value(wfn, self_tv)
      idx_tv = lower_expression(ctx, args[0])
      idx_type = infer_type(args[0], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
      idx_raw = ensure_raw_machine_int(wfn, idx_tv, :i64, idx_type)
      effective_offset = finfo[:offset]
      if class_uses_implicit_type_byte?(ctx[:class_name])
        effective_offset += 1
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :view_load_inline_byte, temp: temp, ptr: self_reg, offset: effective_offset, index: idx_raw})
      return typed_value(:raw_int, temp)
    # Unknown `$view[i]` names retain the older raw-object-relative behavior.
    if finfo == nil
      return lower_view_access(ctx, Tungsten:AST:ViewAccess.new(bare, args[0]))

  # Phase 6i follow-up: `$<view>.<field>` — explicit access to a named
  # view's field. With one data block per class, `$data.tag` is
  # equivalent to bare `$tag`. Route to lower_view_field so the field
  # lookup goes through the same view_layouts table.
  if receiver != nil && (ast_kind(receiver) == :var || ast_kind(receiver) == :gvar) && receiver.name != nil && receiver.name.starts_with?("$") && ctx[:class_name] != nil && (args == nil || args.size() == 0)
    bare_recv = receiver.name.slice(1, receiver.name.size() - 1)
    field_info = view_field_info(ctx, name)
    # Only fire when the field resolves AND the receiver is a view-block
    # name (e.g. "data") — i.e. the receiver name is NOT itself a field.
    if field_info != nil && view_field_info(ctx, bare_recv) == nil
      return lower_view_field(ctx, Tungsten:AST:ViewField.new(name))

  if receiver != nil && name in ("\[]" "[]") && args.size() == 1 && ast_kind(receiver) == :view_field
    info = view_field_info(ctx, receiver.field)
    if info != nil && inline_u8_array_field?(info[:type])
      self_tv = lower_var(ctx, Tungsten:AST:Var.new("__self"))
      self_reg = ensure_i64_value(wfn, self_tv)
      idx_tv = lower_expression(ctx, args[0])
      idx_type = infer_type(args[0], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
      idx_raw = ensure_raw_machine_int(wfn, idx_tv, :i64, idx_type)
      effective_offset = info[:offset]
      if class_uses_implicit_type_byte?(ctx[:class_name])
        effective_offset += 1
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :view_load_inline_byte, temp: temp, ptr: self_reg, offset: effective_offset, index: idx_raw})
      return typed_value(:raw_int, temp)
    if info != nil && pointer_array_field?(info[:type])
      ptr_tv = lower_view_field(ctx, receiver)
      idx_tv = lower_expression(ctx, args[0])
      idx_type = infer_type(args[0], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
      idx_raw = ensure_raw_machine_int(wfn, idx_tv, :i64, idx_type)
      temp = next_temp(wfn)
      elem_type = pointer_array_element_type(info[:type])
      emit_instruction(wfn, {op: :ptr_slot_get, temp: temp, ptr: ptr_tv[:value], index: idx_raw, slot_type: elem_type})
      if elem_type == "w64"
        return typed_value(:i64, temp)
      return typed_value(:raw_int, temp)

  # `value$bytes[i]` — explicit-receiver fixed inline field access. A named
  # type hint on `value` selects the backing layout; the source method is
  # responsible for checking the dynamic type before applying that hint.
  if receiver != nil && name in ("\[]" "[]") && args.size() == 1 && ast_kind(receiver) == :view_field_var
    recv_node = receiver.receiver
    recv_type = infer_type(recv_node, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    layout_class = view_layout_class_for_type(ctx[:mod], recv_type)
    if layout_class != nil
      info = ctx[:mod][:view_layouts][layout_class][receiver.field]
      if info != nil && inline_u8_array_field?(info[:type])
        recv_tv = lower_expression(ctx, recv_node)
        recv_reg = ensure_i64_value(wfn, recv_tv)
        idx_tv = lower_expression(ctx, args[0])
        idx_type = infer_type(args[0], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
        idx_raw = ensure_raw_machine_int(wfn, idx_tv, :i64, idx_type)
        effective_offset = info[:offset]
        if class_uses_implicit_type_byte?(layout_class)
          effective_offset += 1
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :view_load_inline_byte, temp: temp, ptr: recv_reg, offset: effective_offset, index: idx_raw})
        return typed_value(:raw_int, temp)

  # Fast `node.field` access: when the receiver's static type is a
  # specific AST kind AND `name` is a slab field on that kind AND
  # there are no args/block, rewrite to a direct ast_get call —
  # skipping the per-kind method dispatch + accessor frame. Routed
  # through ast_get (not an inline w_node_field_load) so the offset
  # is resolved from the RUNTIME kind: sound even if infer_type's
  # static guess is wrong (a reassigned local). The strict gate
  # (specific AST kind, not :i64) avoids method-name collisions and
  # keeps the rewrite scoped to provable AST nodes; untyped
  # receivers fall through to per-kind dispatch, which resolves the
  # materialized accessor on the kind's class (→ Node via the
  # superclass chain) — also sound.
  if receiver != nil && (args == nil || args.size() == 0) && node.block == nil
    recv_type = infer_type(receiver, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    if recv_type != nil && kind_id_table[recv_type] != nil
      if slab_offset_for(recv_type, name.to_sym()) != nil
        synthetic = Tungsten:AST:Call.new(nil, "ast_get", [receiver, Tungsten:AST:Symbol.new(name)], nil)
        return lower_call(ctx, synthetic)

  # Receiver calls → dynamic dispatch
  if receiver != nil
    return lower_method_call(ctx, node)

  # Built-in class constructors: StringBuffer() / StringBuffer(N) → w_strbuf_new(N)
  if name == "StringBuffer"
    if args.size() > 0
      cap_val = lower_expression(ctx, args[0])
    else
      cap_val = typed_value(:raw_int, "0")
    cap_reg = ensure_i64_value(wfn, cap_val)
    # ## reuse — per-site thread-local slot reused across calls. Capacity
    # grows on demand; length resets to 0 on each hit.
    if node.reuse_safe == true
      cap_raw = next_temp(wfn)
      emit_instruction(wfn, {op: :nanunbox_int, temp: cap_raw, temp_shl: cap_raw + ".shl", boxed: cap_reg})
      site_id = ctx[:mod][:next_reuse_site]
      ctx[:mod][:next_reuse_site] = site_id + 1
      slot_name = "reuse.site." + site_id.to_s()
      ctx[:mod][:reuse_sites].push(slot_name)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_reuse_or_new_strbuf, temp: temp, slot: slot_name, cap: cap_raw})
      return typed_value(:i64, temp)
    # ## recycle — pop from pool or allocate; recycled at scope exit.
    if node.recycle_safe == true
      cap_raw = next_temp(wfn)
      emit_instruction(wfn, {op: :nanunbox_int, temp: cap_raw, temp_shl: cap_raw + ".shl", boxed: cap_reg})
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_recycle_or_new_strbuf, temp: temp, cap: cap_raw})
      track_recycle_temp(wfn, temp, :strbuf)
      return typed_value(:i64, temp)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_strbuf_new", args: [cap_reg]})
    return typed_value(:i64, temp)

  # raw_load_u8(ptr, offset) → inline LLVM byte load from a raw pointer.
  # Intended for tight parsers that already hoisted a stable byte pointer
  # from a runtime value via ccall_nobox.
  if name == "raw_load_u8" && args.size() == 2
    ptr_tv = lower_expression(ctx, args[0])
    idx_tv = lower_expression(ctx, args[1])
    ptr_type = infer_type(args[0], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    idx_type = infer_type(args[1], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    ptr_raw = ensure_raw_machine_int(wfn, ptr_tv, :i64, ptr_type)
    idx_raw = ensure_raw_machine_int(wfn, idx_tv, :i64, idx_type)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :load_u8_ptr, temp: temp, ptr: ptr_raw, index: idx_raw})
    return typed_value(:raw_int, temp)

  # raw_store_u8(ptr, offset, value) → inline LLVM byte store to a raw
  # pointer. Pointer/index/value are all machine integers; the returned value
  # is the truncated byte. Byte codecs use this after hoisting a stable,
  # start-adjusted data pointer from their preallocated u8[] output.
  if name == "raw_store_u8" && args.size() == 3
    ptr_tv = lower_expression(ctx, args[0])
    idx_tv = lower_expression(ctx, args[1])
    value_tv = lower_expression(ctx, args[2])
    ptr_type = infer_type(args[0], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    idx_type = infer_type(args[1], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    value_type = infer_type(args[2], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    ptr_raw = ensure_raw_machine_int(wfn, ptr_tv, :i64, ptr_type)
    idx_raw = ensure_raw_machine_int(wfn, idx_tv, :i64, idx_type)
    value_raw = ensure_raw_machine_int(wfn, value_tv, :i64, value_type)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :store_u8_ptr, temp: temp, ptr: ptr_raw, index: idx_raw, value: value_raw})
    return typed_value(:raw_int, temp)

  # raw_load_u32(ptr, offset) → inline unaligned little-endian u32 load from
  # a raw byte pointer. Use for fixed ASCII sentinels such as CRLFCRLF.
  if name == "raw_load_u32" && args.size() == 2
    ptr_tv = lower_expression(ctx, args[0])
    idx_tv = lower_expression(ctx, args[1])
    ptr_type = infer_type(args[0], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    idx_type = infer_type(args[1], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    ptr_raw = ensure_raw_machine_int(wfn, ptr_tv, :i64, ptr_type)
    idx_raw = ensure_raw_machine_int(wfn, idx_tv, :i64, idx_type)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :load_u32_ptr, temp: temp, ptr: ptr_raw, index: idx_raw})
    return typed_value(:raw_int, temp)

  # raw_load_u64(ptr, offset) → inline unaligned u64 load from a raw byte
  # pointer. Intended for hot ASCII header/tag comparisons.
  if name == "raw_load_u64" && args.size() == 2
    ptr_tv = lower_expression(ctx, args[0])
    idx_tv = lower_expression(ctx, args[1])
    ptr_type = infer_type(args[0], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    idx_type = infer_type(args[1], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    ptr_raw = ensure_raw_machine_int(wfn, ptr_tv, :i64, ptr_type)
    idx_raw = ensure_raw_machine_int(wfn, idx_tv, :i64, idx_type)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :load_u64_ptr, temp: temp, ptr: ptr_raw, index: idx_raw})
    return typed_value(:raw_i64, temp)

  # slab_alloc_init(kind, sc, field0, field1, ...) — slab-AST node
  # constructor intrinsic. Replaces the three-step:
  #   n = ccall_nobox("w_node_alloc", KIND, SC)
  #   ccall_nobox("w_node_field_store", n, 0, field0)
  #   ccall_nobox("w_node_field_store", n, 1, field1)
  #   n
  # with a single fused emit op that bumps the arena once and writes
  # all field values against the just-computed slot address. Saves
  # N-1 redundant slot-address derivations per constructor (the
  # standalone field_store path re-extracts cursor/sc/stride/base
  # from the W_PACKED_NODE on every call, ~10 LLVM ops apiece).
  #
  # First two args (kind, sc) must lower to literal i64 values; the
  # rest are arbitrary expressions stored at slots 0..N-1.
  if name == "slab_alloc_init" && args.size() >= 2
    # Kind and sc must be raw i64 — they're indices/payload bits, not
    # NaN-boxed WValues. Same convention as ccall_nobox: if the lowered
    # expression already produced a raw machine int (e.g. from a `## i64`
    # global), use it directly; otherwise box-then-treat-as-i64.
    kind_tv = lower_expression(ctx, args[0])
    sc_tv = lower_expression(ctx, args[1])
    kind_reg = nil
    if kind_tv[:type] in (:raw_int :raw_i64 :raw_u64)
      kind_reg = kind_tv[:value]
    else
      kind_reg = ensure_i64_value(wfn, kind_tv)
    sc_reg = nil
    if sc_tv[:type] in (:raw_int :raw_i64 :raw_u64)
      sc_reg = sc_tv[:value]
    else
      sc_reg = ensure_i64_value(wfn, sc_tv)
    # Field values are arbitrary WValues stored at slot offsets 0..N-1.
    field_vals = []
    i = 2
    while i < args.size()
      f_tv = lower_expression(ctx, args[i])
      field_vals.push(ensure_i64_value(wfn, f_tv))
      i += 1
    ctx[:mod][:ccall_fns]["w_node_alloc"] = 2
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :slab_alloc_init, temp: temp, kind: kind_reg, sc: sc_reg, fields: field_vals})
    return typed_value(:i64, temp)

  # ccall("c_function_name", arg1, arg2, ...) → direct call to named C function
  if name == "ccall" && args.size() >= 1
    # First arg must be a string literal — the C function name
    fn_node = args[0]
    if ast_kind(fn_node) != :string
      << "ccall: first argument must be a string literal"
      exit(1)
    fn_name = fn_node.value

    # Register the function for declaration in emitter
    ctx[:mod][:ccall_fns][fn_name] = args.size() - 1

    # Lower remaining args — pass raw machine ints directly (no boxing)
    lowered_args = []
    i = 1
    while i < args.size()
      arg_tv = lower_expression(ctx, args[i])
      if arg_tv[:type] in (:raw_int :raw_i64 :raw_u64)
        lowered_args.push(arg_tv[:value])
      else
        lowered_args.push(ensure_i64_value(wfn, arg_tv))
      i += 1

    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: fn_name, args: lowered_args})
    return typed_value(:i64, temp)

  # ccall_nobox("c_function_name", arg1, ...) → C function whose return is
  # a raw int64_t, NOT a NaN-boxed WValue.
  #
  # Use this for native helpers that return positions/counts/raw bits and
  # whose result needs to flow into a `## i64:` typed local. Plain ccall
  # tags the result as :i64 (= "WValue holding int") which is correct for
  # C functions returning WValues (w_int, w_runtime_dir, …) but causes a
  # tag-check panic when the result is consumed by the machine-int unbox
  # path. ccall_nobox tags the result as :raw_int so machine-int targets
  # cast directly and untyped/WValue targets nanbox at the assignment
  # boundary, without disturbing existing ccall sites.
  if name == "ccall_nobox" && args.size() >= 1
    fn_node = args[0]
    if ast_kind(fn_node) != :string
      << "ccall_nobox: first argument must be a string literal"
      exit(1)
    fn_name = fn_node.value
    ctx[:mod][:ccall_fns][fn_name] = args.size() - 1
    lowered_args = []
    i = 1
    while i < args.size()
      arg_tv = lower_expression(ctx, args[i])
      if arg_tv[:type] in (:raw_int :raw_i64 :raw_u64)
        lowered_args.push(arg_tv[:value])
      else
        lowered_args.push(ensure_i64_value(wfn, arg_tv))
      i += 1
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: fn_name, args: lowered_args})
    # Slab-AST exception: w_node_alloc returns a W_PACKED_NODE WValue,
    # not a raw int. w_node_field_load returns a slab slot value
    # (arbitrary WValue). w_node_singleton and w_ast_bool_cached also
    # return W_PACKED_NODE WValues. Tagging these as :raw_int would
    # have downstream storage call w_int(n) to box, clobbering the
    # high tag bits — the slab handle becomes a fake int and
    # subsequent slab reads SEGV. Returning :i64 marks them as
    # already-boxed so downstream storage passes them through verbatim.
    if ccall_nobox_returns_wvalue?(fn_name)
      return typed_value(:i64, temp)
    return typed_value(:raw_int, temp)

  # ccall_rawargs("c_function_name", ...)
  #
  # Like ccall(), but raw machine-int arguments stay raw instead of being
  # boxed first. Use for C helpers with mixed WValue/raw signatures.
  if name == "ccall_rawargs" && args.size() >= 1
    fn_node = args[0]
    if ast_kind(fn_node) != :string
      << "ccall_rawargs: first argument must be a string literal"
      exit(1)
    fn_name = fn_node.value
    ctx[:mod][:ccall_fns][fn_name] = args.size() - 1
    lowered_args = []
    i = 1
    while i < args.size()
      arg_tv = lower_expression(ctx, args[i])
      if arg_tv[:type] in (:raw_int :raw_i64 :raw_u64)
        lowered_args.push(arg_tv[:value])
      else
        lowered_args.push(ensure_i64_value(wfn, arg_tv))
      i += 1
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: fn_name, args: lowered_args})
    return typed_value(:i64, temp)

  # Typed overloads: resolve by inferred argument types and emit a direct call
  # to the signature-mangled function. This is deliberately static: if the
  # argument types are unknown or no exact overload exists, the normal call path
  # below handles the expression.
  if args != nil && args.size() > 0
    arg_types = inferred_arg_types(args, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    typed_key = typed_call_signature_key(name, arg_types)
    typed_target = ctx[:mod][:known_calls][typed_key]
    if typed_target != nil
      # Raw-i64 ABI win: the typed-overload key already resolved to a fn
      # registered via lower_method_def's all-i64-params detection. Pass
      # raw ints, get raw return — no nanbox/nanunbox round-trip.
      if ctx[:mod][:raw_callable_fns][typed_key] != nil && !call_has_ast_block?(node)
        pkinds = ctx[:mod][:raw_fn_param_kinds][typed_key]
        arg_regs = []
        i = 0
        while i < args.size()
          arg_tv = lower_expression(ctx, args[i])
          # Mixed raw ABI: typed-array params take the boxed handle as-is;
          # scalar params take raw machine ints.
          if pkinds != nil && pkinds[i] == :arr
            arg_regs.push(ensure_i64_value(wfn, arg_tv))
          else
            arg_regs.push(ensure_raw_machine_int(wfn, arg_tv, :i64, arg_types[i]))
          i += 1
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: typed_target, args: arg_regs})
        return typed_value(:raw_i64, temp)

      arg_regs = []
      fresh_boxes = []
      i = 0
      while i < args.size()
        val = lower_expression(ctx, args[i])
        reg = ensure_i64_value(wfn, val)
        # A raw machine int boxed here may mint a heap bigint (>2^47 via
        # w_int/w_u64/w_i128/w_u128). The typed callee unboxes the param on
        # entry, so the box is provably dead once the call returns — free
        # it or every wide-valued call leaks one WBigint.
        if val[:type] in (:raw_i64 :raw_u64 :raw_i128 :raw_u128)
          fresh_boxes.push(reg)
        arg_regs.push(reg)
        i += 1

      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: typed_target, args: arg_regs})
      fb = 0
      while fb < fresh_boxes.size()
        emit_instruction(wfn, {op: :free_value, value: fresh_boxes[fb]})
        fb += 1
      return typed_value(:i64, temp)

    has_unknown_arg = false
    ati = 0
    while ati < arg_types.size()
      if arg_types[ati] == nil
        has_unknown_arg = true
      ati += 1
    if has_unknown_arg && ctx[:mod][:known_calls][name] == nil
      arity_key = typed_overload_arity_key(name, args.size())
      if ctx[:mod][:known_typed_overload_counts][arity_key] == 1
        fallback_key = ctx[:mod][:known_unique_typed_overload_keys][arity_key]
        fallback_target = ctx[:mod][:known_calls][fallback_key]
        fallback_types = ctx[:mod][:known_unique_typed_overload_param_types][arity_key]
        if fallback_target != nil && fallback_types != nil
          if ctx[:mod][:raw_callable_fns][fallback_key] != nil && !call_has_ast_block?(node)
            pkinds = ctx[:mod][:raw_fn_param_kinds][fallback_key]
            arg_regs = []
            i = 0
            while i < args.size()
              arg_tv = lower_expression(ctx, args[i])
              if pkinds != nil && pkinds[i] == :arr
                arg_regs.push(ensure_i64_value(wfn, arg_tv))
              else
                arg_regs.push(ensure_raw_machine_int(wfn, arg_tv, :i64, fallback_types[i]))
              i += 1
            temp = next_temp(wfn)
            emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: fallback_target, args: arg_regs})
            return typed_value(:raw_i64, temp)

          arg_regs = []
          fresh_boxes = []
          i = 0
          while i < args.size()
            val = lower_expression(ctx, args[i])
            reg = ensure_i64_value(wfn, val)
            if val[:type] in (:raw_i64 :raw_u64 :raw_i128 :raw_u128)
              fresh_boxes.push(reg)
            arg_regs.push(reg)
            i += 1

          temp = next_temp(wfn)
          emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: fallback_target, args: arg_regs})
          fb = 0
          while fb < fresh_boxes.size()
            emit_instruction(wfn, {op: :free_value, value: fresh_boxes[fb]})
            fb += 1
          return typed_value(:i64, temp)

  # Variable holding a closure: load and dispatch via w_closure_call_<n>.
  # User wrote `inc()` where `inc` is a local/top-level variable (typically
  # assigned `inc = -> () body`); invoke it as a closure.
  if name_is_local_var?(wfn, ctx, name) && ctx[:mod][:known_calls][name] == nil && ctx[:mod][:known_pure_calls][name] == nil && ctx[:mod][:known_classes][name] == nil
    # A bare identifier matching a local var is parsed as a 0-arg call (the AST
    # can't tell `x` from `x()`). Only dispatch as a closure when the var
    # actually holds one (closure_bindings); otherwise it's a plain variable
    # read. Without this, a non-closure local — e.g. an int param used as an
    # array index `arr[ro]` — emits w_closure_call_0 on a non-closure and dies
    # at runtime with "expected closure".
    if args.size() == 0 && node.block == nil && (ctx[:closure_bindings] == nil || ctx[:closure_bindings][name] == nil)
      return lower_var(ctx, Tungsten:AST:Var.new(name))
    closure_tv = lower_var(ctx, Tungsten:AST:Var.new(name))
    closure_reg = ensure_i64_value(wfn, closure_tv)
    arg_regs = []
    i = 0
    while i < args.size()
      val = lower_expression(ctx, args[i])
      arg_regs.push(ensure_i64_value(wfn, val))
      i += 1
    temp = next_temp(wfn)
    if arg_regs.size() == 0
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_closure_call_0", args: [closure_reg]})
    elsif arg_regs.size() == 1
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_closure_call_1", args: [closure_reg, arg_regs[0]]})
    elsif arg_regs.size() == 2
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_closure_call_2", args: [closure_reg, arg_regs[0], arg_regs[1]]})
    else
      raise compile_error_for_node(:E_LOWER_CLOSURE_CALL_ARITY, "closure call supports 0..2 args, got [arg_regs.size()]", ctx[:source_path], node)
    return typed_value(:i64, temp)

  # Inside a class method: implicit self dispatch for non-top-level calls
  if ctx[:class_name] != nil && ctx[:mod][:known_calls][name] == nil && ctx[:mod][:known_pure_calls][name] == nil
    self_node = Tungsten:AST:Call.new(Tungsten:AST:Self.new, name, args, node.block)
    return lower_method_call(ctx, self_node)

  # Raw-i64 ABI: when callee is a `## i64:`-annotated top-level fn, pass
  # raw ints directly and tag the return as :raw_i64. The boxing round-
  # trip across the call boundary disappears — the caller's raw register
  # is consumed verbatim by the callee, the callee's raw return becomes
  # the caller's raw value. LLVM still sees a regular `call i64 @fn(i64,
  # i64, ...)`, but with no nanbox/nanunbox ops bracketing the call,
  # cross-fn LTO can fold the arithmetic.
  raw_target = ctx[:mod][:raw_callable_fns][name]
  if raw_target != nil && !call_has_ast_block?(node)
    pkinds = ctx[:mod][:raw_fn_param_kinds][name]
    arg_regs = []
    i = 0
    while i < args.size()
      arg_tv = lower_expression(ctx, args[i])
      if pkinds != nil && pkinds[i] == :arr
        arg_regs.push(ensure_i64_value(wfn, arg_tv))
      else
        arg_type = infer_type(args[i], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
        arg_regs.push(ensure_raw_machine_int(wfn, arg_tv, :i64, arg_type))
      i += 1
    expected_raw = ctx[:mod][:known_fn_param_counts][name]
    if expected_raw != nil
      while arg_regs.size() < expected_raw
        arg_regs.push("0")
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: raw_target, args: arg_regs})
    return typed_value(:raw_i64, temp)

  # Known function → direct call
  arg_regs = []
  i = 0
  while i < args.size()
    val = lower_expression(ctx, args[i])
    arg_regs.push(ensure_i64_value(wfn, val))
    i += 1

  # If call has a block, materialize bindings for capture analysis
  cblk = node.block
  if cblk != nil && is_ast_node?(cblk)
    materialize_bindings(ctx)
    closure_tv = lower_block_closure(ctx, cblk)
    closure_reg = ensure_i64_value(wfn, closure_tv)
    arg_regs.push(closure_reg)

  # Pad with nil for missing keyword/default params
  expected = ctx[:mod][:known_fn_param_counts][name]
  if expected != nil
    while arg_regs.size() < expected
      arg_regs.push(w_nil.to_s())

  temp = next_temp(wfn)
  # Mangle name for compiled functions
  target = "__w_" + mangle_method_name(name)
  if ctx[:mod][:known_calls][name] != nil
    target = ctx[:mod][:known_calls][name]
  elsif ctx[:mod][:known_fn_param_counts][name] == nil
    # Constructor sugar: a bare call naming a known class builds an
    # instance — Point(3, 4, 5) ≡ Point.new(3, 4, 5). (The tree-walker
    # has always done this; see eval's bare-call class branch.)
    if ctx[:mod][:known_classes][name] != nil
      ctor = Tungsten:AST:Call.new(Tungsten:AST:ClassRef.new(name), "new", node.args, node.block)
      return lower_call(ctx, ctor)
    # Truly unknown call. If the name is a well-known idiom from another
    # language, teach the translation now instead of failing at link time
    # with an inscrutable missing __w_ symbol.
    hint = foreign_idiom_hint(name)
    if hint != nil
      raise compile_error_for_node(:E_LOWER_FOREIGN_IDIOM, "unknown function '" + name + "' — " + hint, ctx[:source_path], node)

  # Inline wymix: 128-bit multiply, XOR high and low halves.
  # Returns i48 NaN-boxed integer (truncated to 48 bits for safe chaining).
  if name == "wymix" && arg_regs.size() == 2
    a_ext = next_temp(wfn)
    b_ext = next_temp(wfn)
    prod = next_temp(wfn)
    lo = next_temp(wfn)
    hi_128 = next_temp(wfn)
    hi = next_temp(wfn)
    xor_raw = next_temp(wfn)
    emit_instruction(wfn, {op: :zext_i64_i128, temp: a_ext, value: arg_regs[0]})
    emit_instruction(wfn, {op: :zext_i64_i128, temp: b_ext, value: arg_regs[1]})
    emit_instruction(wfn, {op: :mul_i128, temp: prod, lhs: a_ext, rhs: b_ext})
    emit_instruction(wfn, {op: :trunc_i128_i64, temp: lo, value: prod})
    emit_instruction(wfn, {op: :lshr_i128, temp: hi_128, value: prod, shift: 64})
    emit_instruction(wfn, {op: :trunc_i128_i64, temp: hi, value: hi_128})
    emit_instruction(wfn, {op: :xor_i64, temp: xor_raw, lhs: lo, rhs: hi})
    # NaN-box as i48 integer (mask to payload + tag)
    result_tv = nanbox_int_emit(wfn, xor_raw)
    return result_tv

  # Memoized pure function call (fn keyword, arity <= 2)
  pure_target = ctx[:mod][:known_pure_calls][name]
  if pure_target != nil && arg_regs.size() <= 2
    memo_global = ctx[:mod][:fn_memo_tables][name]
    mark_memo_table_used(ctx[:mod], name)
    memo_ptr = next_temp(wfn)
    emit_instruction(wfn, {op: :load_memo_ptr, temp: memo_ptr, global: memo_global})
    if arg_regs.size() == 0
      emit_instruction(wfn, {op: :memo_call0_i64, temp: temp, table: memo_ptr, fn_name: target})
      return typed_value(:i64, temp)
    if arg_regs.size() == 1
      emit_instruction(wfn, {op: :memo_call1_i64, temp: temp, table: memo_ptr, fn_name: target, args: arg_regs})
      return typed_value(:i64, temp)
    if arg_regs.size() == 2
      emit_instruction(wfn, {op: :memo_call2_i64, temp: temp, table: memo_ptr, fn_name: target, args: arg_regs})
      return typed_value(:i64, temp)

  emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: target, args: arg_regs})
  if target == "__w_exit"
    emit_instruction(wfn, {op: :unreachable})
  typed_value(:i64, temp)

-> static_param_type(static_info, index)
  pts = static_info[:param_types]
  if pts != nil && index < pts.size()
    return pts[index]
  nil

-> lower_direct_static_method_call(ctx, static_info, recv_node, args)
  wfn = ctx[:func]
  receiver_val = lower_expression(ctx, recv_node)
  receiver_reg = ensure_i64_value(wfn, receiver_val)
  call_args = expand_kwargs(args)
  if call_args == nil
    call_args = []

  arg_regs = [receiver_reg]
  i = 0
  while i < call_args.size()
    param_type = static_param_type(static_info, i)
    if static_info[:raw_abi] == true && is_machine_int64_type(param_type)
      arg_regs.push(lower_machine_int_expression(ctx, call_args[i], param_type))
    else
      arg_val = lower_expression(ctx, call_args[i])
      arg_regs.push(ensure_i64_value(wfn, arg_val))
    i += 1
  while arg_regs.size() < static_info[:arity]
    arg_regs.push(w_nil.to_s())

  temp = next_temp(wfn)

  # `fn`-defined class methods get the same memoization dispatch as
  # top-level fn defs: w_memo_lookup keyed by (self, args...). Only
  # applicable when arity ≤ 2 (the runtime exposes memo_call0/1/2_i64
  # variants); over that, fall back to a direct call.
  static_key = nil
  if static_info[:from_fn] == true && arg_regs.size() <= 2
    keys = ctx[:mod][:known_pure_calls].keys()
    ki = 0
    while ki < keys.size()
      k = keys[ki]
      if ctx[:mod][:known_pure_calls][k] == static_info[:fn_name]
        static_key = k
        break
      ki += 1
  if static_key != nil
    memo_global = ctx[:mod][:fn_memo_tables][static_key]
    mark_memo_table_used(ctx[:mod], static_key)
    memo_ptr = next_temp(wfn)
    emit_instruction(wfn, {op: :load_memo_ptr, temp: memo_ptr, global: memo_global})
    if arg_regs.size() == 1
      emit_instruction(wfn, {op: :memo_call1_i64, temp: temp, table: memo_ptr, fn_name: static_info[:fn_name], args: arg_regs})
    elsif arg_regs.size() == 2
      emit_instruction(wfn, {op: :memo_call2_i64, temp: temp, table: memo_ptr, fn_name: static_info[:fn_name], args: arg_regs})
    else
      emit_instruction(wfn, {op: :memo_call0_i64, temp: temp, table: memo_ptr, fn_name: static_info[:fn_name]})
  else
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: static_info[:fn_name], args: arg_regs})

  static_return_type = static_info[:return_type]
  if static_return_type != nil && is_machine_int64_type(static_return_type)
    return typed_value(raw_machine_value_type(static_return_type), temp)
  typed_value(:i64, temp)

-> lower_inline_array_iterator_call(ctx, recv_node, method_name, block)
  if block == nil || !is_ast_node?(block) || ast_kind(block) != :block
    return nil
  if !inline_array_iterator_method?(method_name)
    return nil

  wfn = ctx[:func]
  param_name = inline_block_param_name(block, ctx)

  receiver_val = lower_expression(ctx, recv_node)
  receiver_reg = ensure_i64_value(wfn, receiver_val)
  size_box = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: size_box, name: "w_array_size", args: [receiver_reg]})
  size_raw = nanunbox_int_emit(wfn, size_box)

  result_ptr = nil
  default_result = w_nil.to_s()
  if method_name == "all?"
    default_result = w_true.to_s()
  elsif method_name == "any?"
    default_result = w_false.to_s()
  elsif method_name == "none?"
    default_result = w_true.to_s()
  if method_name != "each"
    result_ptr = ensure_var_slot(wfn, "__array_iter_result." + next_label(wfn, "air"))
    emit_instruction(wfn, {op: :store_i64, value: default_result, ptr: result_ptr})

  materialize_bindings(ctx)

  # This loop is an inlined lexical block, not the enclosing function body.
  # A block-local register (including a ## recycle temp) must not escape into
  # the next sibling CFG and be materialized from a path it does not dominate.
  # materialize_bindings leaves only pristine raw parameter registers live;
  # preserve that uncommon map and otherwise let the body reuse the empty map.
  # At exit the body map is discarded in O(1), avoiding a keys()/delete scan
  # for every inlined iterator during self-host compilation.
  outer_bindings = ctx[:bindings]
  iterator_has_outer_bindings = outer_bindings.size() > 0
  if iterator_has_outer_bindings
    ctx[:bindings] = {}

  # The block parameter's temporary unknown type must not overwrite an outer
  # fact for the same name.
  outer_var_types = ctx[:var_types]
  iterator_absent_type = :__inline_iterator_absent_type
  iterator_saved_param_type = iterator_absent_type
  if param_name != nil && outer_var_types.has_key?(param_name)
    iterator_saved_param_type = outer_var_types[param_name]

  # An iterator parameter shadows an equally named unboxed variable from an
  # enclosing while loop. Copy that normally tiny map only on an actual name
  # collision; the overwhelmingly common path keeps the original by reference.
  outer_unboxed_vars = ctx[:unboxed_vars]
  if outer_unboxed_vars != nil && param_name != nil && outer_unboxed_vars[param_name] != nil
    iterator_unboxed_vars = {}
    unboxed_names = outer_unboxed_vars.keys()
    uni = 0
    while uni < unboxed_names.size()
      unboxed_name = unboxed_names[uni]
      if unboxed_name != param_name
        iterator_unboxed_vars[unboxed_name] = outer_unboxed_vars[unboxed_name]
      uni += 1
    ctx[:unboxed_vars] = iterator_unboxed_vars

  pre_label = next_label(wfn, "array.iter.pre")
  header_label = next_label(wfn, "array.iter.hdr")
  body_label = next_label(wfn, "array.iter.body")
  inc_label = next_label(wfn, "array.iter.inc")
  exit_label = next_label(wfn, "array.iter.exit")

  emit_instruction(wfn, {op: :br, label: pre_label})
  start_block(wfn, pre_label)
  emit_instruction(wfn, {op: :br, label: header_label})

  start_block(wfn, header_label)
  idx_raw = next_temp(wfn)
  idx_next = next_temp(wfn)
  emit_instruction(wfn, {op: :phi_i64, temp: idx_raw, a_value: "0", a_label: pre_label, b_value: idx_next, b_label: inc_label})
  cmp = next_temp(wfn)
  emit_instruction(wfn, {op: :icmp_i64, temp: cmp, pred: "slt", lhs: idx_raw, rhs: size_raw})
  emit_instruction(wfn, {op: :cond_br, cond: cmp, then_label: body_label, else_label: exit_label})

  start_block(wfn, body_label)
  iterator_recycle_depth = wfn[:scope_recycle_stack].size()
  iterator_sid = next_scope_id(wfn)
  emit_scope_push(wfn, iterator_sid)
  idx_boxed = nanbox_int_emit(wfn, idx_raw)
  scratch = []
  si = 0
  while si < 10
    scratch.push(next_temp(wfn))
    si += 1
  elem = next_temp(wfn)
  emit_instruction(wfn, {op: :array_get_inline, temp: elem, arr: receiver_reg, idx: idx_boxed[:value], s: scratch})
  if param_name != nil
    ptr = ensure_var_slot(wfn, param_name)
    emit_instruction(wfn, {op: :store_i64, value: elem, ptr: ptr})
    ctx[:bindings][param_name] = nil
    ctx[:var_types][param_name] = nil

  push_loop_with_recycle_depth(wfn, exit_label, inc_label, nil, iterator_recycle_depth)

  body = block.body
  if body != nil && body.size() > 0
    if method_name == "each"
      bi = 0
      while bi < body.size()
        if block_terminated(wfn)
          break
        lower_statement(ctx, body[bi])
        bi += 1
    else
      bi = 0
      while bi < body.size() - 1
        if block_terminated(wfn)
          break
        lower_statement(ctx, body[bi])
        bi += 1
      if !block_terminated(wfn)
        pred_val = lower_expression(ctx, body[body.size() - 1])
      if !block_terminated(wfn)
        if pred_val[:type] == :i1
          pred_bool = pred_val[:value]
        else
          pred_reg = ensure_i64_value(wfn, pred_val)
          pred_bool = next_temp(wfn)
          emit_instruction(wfn, {op: :truthy_inline, temp: pred_bool, value: pred_reg})

        # Predicate result and `elem` are now materialized. Recycle this
        # iteration's lexical values once before either the continue or hit
        # edge; no cleanup temp then leaks into the zero-iteration exit path.
        emit_scope_pop(wfn, iterator_sid)
        hit_label = next_label(wfn, "array.iter.hit")
        if method_name == "all?"
          emit_instruction(wfn, {op: :cond_br, cond: pred_bool, then_label: inc_label, else_label: hit_label})
          start_block(wfn, hit_label)
          emit_instruction(wfn, {op: :store_i64, value: w_false.to_s(), ptr: result_ptr})
          emit_instruction(wfn, {op: :br, label: exit_label})
        elsif method_name == "none?"
          emit_instruction(wfn, {op: :cond_br, cond: pred_bool, then_label: hit_label, else_label: inc_label})
          start_block(wfn, hit_label)
          emit_instruction(wfn, {op: :store_i64, value: w_false.to_s(), ptr: result_ptr})
          emit_instruction(wfn, {op: :br, label: exit_label})
        elsif method_name == "any?"
          emit_instruction(wfn, {op: :cond_br, cond: pred_bool, then_label: hit_label, else_label: inc_label})
          start_block(wfn, hit_label)
          emit_instruction(wfn, {op: :store_i64, value: w_true.to_s(), ptr: result_ptr})
          emit_instruction(wfn, {op: :br, label: exit_label})
        else
          emit_instruction(wfn, {op: :cond_br, cond: pred_bool, then_label: hit_label, else_label: inc_label})
          start_block(wfn, hit_label)
          emit_instruction(wfn, {op: :store_i64, value: elem, ptr: result_ptr})
          emit_instruction(wfn, {op: :br, label: exit_label})

  pop_loop(wfn)

  if !block_terminated(wfn)
    emit_scope_pop(wfn, iterator_sid)
    emit_instruction(wfn, {op: :br, label: inc_label})
  else
    # break/next/return already emitted runtime cleanup for the abandoned
    # iteration; restore only the lowering stack before building sibling CFG.
    restore_recycle_scope_depth(wfn, iterator_recycle_depth)
  start_block(wfn, inc_label)
  emit_instruction(wfn, {op: :add_i64, temp: idx_next, lhs: idx_raw, rhs: "1"})
  emit_instruction(wfn, {op: :br, label: header_label})

  start_block(wfn, exit_label)
  if iterator_has_outer_bindings
    ctx[:bindings] = outer_bindings
  else
    ctx[:bindings] = {}
  if param_name != nil
    if iterator_saved_param_type == iterator_absent_type
      outer_var_types.delete(param_name)
    else
      outer_var_types[param_name] = iterator_saved_param_type
  ctx[:var_types] = outer_var_types
  ctx[:unboxed_vars] = outer_unboxed_vars
  if method_name == "each"
    return typed_value(:i64, receiver_reg)
  result = next_temp(wfn)
  emit_instruction(wfn, {op: :load_i64, temp: result, ptr: result_ptr})
  typed_value(:i64, result)

# -- I/O --

# node.value is a LIST of value-nodes (`<< a, b, c`); print each on its own
# line. When produce_value, the statement's value is the last print's result.
# Familiar call names from other languages, mapped to the Tungsten idiom.
# Consulted only for calls the module doesn't know — a user-defined fn or
# method with one of these names wins. Keep entries to names that are
# overwhelmingly likely to be a translation slip (Ruby/Python/JS/Go/Java).
-> foreign_idiom_hint(name)
  case name
    "puts" => "Tungsten prints with `<<`: << expression"
    "print" => "Tungsten prints with `<<` (newline included): << expression"
    "println" => "Tungsten prints with `<<`: << expression"
    "printf" => "Tungsten prints with `<<` and \[..\] interpolation: << \"x = \[x\]\""
    "echo" => "Tungsten prints with `<<`: << expression"
    "len" => "length is a method: value.size()"
    "lambda" => "blocks are written with `->`: list.map -> item * 2"
    "require" => "Tungsten imports with `use`: use core/tensor"
    "require_relative" => "Tungsten imports with `use`: use core/tensor"
    "import" => "Tungsten imports with `use`: use core/tensor"
    "str" => "convert with .to_s(): value.to_s()"
    "input" => "read a line with gets()"
    "elif" => "Tungsten spells it `elsif`"
    => nil

-> lower_puts(ctx, node, produce_value = true)
  wfn = ctx[:func]
  values = node.value
  result = nil
  i = 0
  n = values.size()
  while i < n
    val = lower_expression(ctx, values[i])
    val_reg = ensure_i64_value(wfn, val)
    if produce_value && i == n - 1
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :puts_i64, temp: temp, value: val_reg})
      result = typed_value(:i64, temp)
    else
      emit_instruction(wfn, {op: :puts_i64, value: val_reg})
    i += 1
  result

-> lower_print(ctx, node, produce_value = true)
  wfn = ctx[:func]
  val = lower_expression(ctx, node.value)
  val_reg = ensure_i64_value(wfn, val)
  if produce_value
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :print_i64, temp: temp, value: val_reg})
    return typed_value(:i64, temp)
  emit_instruction(wfn, {op: :print_i64, value: val_reg})
  nil
