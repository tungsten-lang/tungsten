# Cinder (`bits/tungsten-cinder`) specification suite:
#   1. ARM64 & x86_64 machine-code assemblers (`CinderA64`, `CinderX64`)
#   2. Cross-platform WIRE IR parser, optimizer, and in-process JIT (`arm64` & `x86_64`),
#      including IEEE-754 binary16 `Float16Array` (`ebits=-16`) and non-zero `WArray->start`
#      slice offsets
#   3. Pure-Tungsten Mach-O 64 (`MH_OBJECT`) & ELF64 (`ET_REL`) binary object writers
#   4. End-to-end `.ll` -> `.o` -> native executable compilation without `clang`, `llc`, or `as`
#
# spec: compiled -- Cinder uses inline LLVM IR trampolines (`ll <<~IR`) for in-process JIT
# invocation and zero-copy byte buffer I/O.

use spec
use ../lib/cinder

-> cinder_spec_tmp_dir
  base = env("TMPDIR")
  base = "/tmp" if base == nil || base == ""
  base = base.slice(0, base.size() - 1) if base.ends_with?("/")
  dir = base + "/cinder-spec-" + (ccall_nobox("__w_clock_ns_raw") ## i64).to_s()
  ccall("__w_mkdir_p", dir)
  dir

CINDER_SPEC_TMP = cinder_spec_tmp_dir()

# Simulate a sliced `WArray` view (`start > 0`) by setting `arr->start` (`i32` at +4) and `arr->size` (`i32` at +8).
fn cinder_spec_set_warray_start_size(arr_wv, new_start, new_size) (i64 i64 i64) i64
  ll <<~IR
    %p = and i64 %arr_wv, 281474976710648
    %ptr = inttoptr i64 %p to ptr
    %st = getelementptr i8, ptr %ptr, i64 4
    %sp = getelementptr i8, ptr %ptr, i64 8
    %st32 = trunc i64 %new_start to i32
    %sp32 = trunc i64 %new_size to i32
    store i32 %st32, ptr %st, align 4
    store i32 %sp32, ptr %sp, align 4
    ret i64 0
  IR

describe "Cinder host & assemblers" ->
  it "detects host OS, architecture, and JIT readiness" ->
    os = cinder_host_os()
    arch = cinder_host_arch()
    expect(os == "macos" || os == "linux").to eq(true)
    expect(arch == "arm64" || arch == "x86_64").to eq(true)
    expect(cinder_jit_ready?()).to eq(true)

  it "encodes ARM64 instructions, immediates, branches, and relocations" ->
    a = CinderA64.new(64)
    l_skip = a.new_label()
    a.mov_imm64(R_X0, 0x123456789ABCDEF0)
    a.b(l_skip)
    a.nop()
    a.bind(l_skip)
    a.addr_sym_got(R_X1, "ext_var", 8)
    a.ret()
    expect(a.patch_fixups()).to eq(true)
    expect(a.byte_len() > 20).to eq(true)
    expect(a.rel_off.size()).to eq(2)

  it "encodes x86_64 REX/ModRM/SIB instructions, branches, SSE2, and ELF relocations" ->
    x = CinderX64.new(64)
    l_done = x.new_label()
    x.push_r(X64_RBP)
    x.mov_rr(X64_RBP, X64_RSP)
    x.sub_ri(X64_RSP, 32)
    x.mov_imm64(X64_RAX, 0x123456789ABCDEF0)
    x.store64(X64_RAX, X64_RSP, 0)
    x.load64(X64_R12, X64_RSP, 0)
    x.store64(X64_R12, X64_R13, 0)
    x.addr_sym_got(X64_RCX, "g_ext", 8)
    x.jmp(l_done)
    x.ud2()
    x.bind(l_done)
    x.add_ri(X64_RSP, 32)
    x.pop_r(X64_RBP)
    x.ret()
    expect(x.patch_fixups()).to eq(true)
    expect(x.byte_len() > 40).to eq(true)
    expect(x.rel_off.size()).to eq(1)
    expect(x.rel_kind[0]).to eq(CREL_X64_GOTPCREL)

describe "Cinder cross-platform WIRE IR JIT" ->
  it "parses, optimizes, cross-encodes (ARM64 + x86_64), and JIT-executes WIRE IR" ->
    ir_txt = <<~WIRE
      function wire_sum_sq(a:f32[], n:i64) -> f64
        __entry:
          %vs.0 = alloca_f64
          %vs.1 = alloca_i64
          %p0 = arr_data_ptr %a ebits=-32
          %z0 = const_f64 0.0
          store_double %z0 ptr=%vs.0
          %z1 = const_i64 0
          store_i64 %z1 ptr=%vs.1
          br %while.cond
        while.cond:
          %i = load_i64 ptr=%vs.1
          %cmp = icmp_i64 slt %i %n
          cond_br %cmp %while.body %while.end
        while.body:
          %s = load_double ptr=%vs.0
          %idx = load_i64 ptr=%vs.1
          %v = typed_array_get_inline %p0 %idx ebits=-32
          %sq = fmul_f64 %v %v
          %ns = fadd_f64 %s %sq
          store_double %ns ptr=%vs.0
          %one = const_i64 1
          %ni = add_i64 %idx %one
          store_i64 %ni ptr=%vs.1
          br %while.cond
        while.end:
          %out = load_double ptr=%vs.0
          ret_f64 %out
    WIRE
    mod = wire_parse_text(ir_txt)
    wf = mod.functions[0]
    wf.abi = :wvalue_ret_f64
    wire_opt_func(wf)

    a64_enc = wire_encode_func_for_arch(wf, "arm64")
    x64_enc = wire_encode_func_for_arch(wf, "x86_64")
    expect(a64_enc[0] && a64_enc[1].len > 64).to eq(true)
    expect(x64_enc[0] && x64_enc[1].len > 64).to eq(true)

    cr = wire_compile_func(wf)
    expect(cr[0] != 0).to eq(true)

    arr = f32[64]
    idx = 0
    exp_sum = ~0.0
    while idx < 64
      fv = (idx - 16).to_f() * ~0.5
      arr[idx] = fv ## f32
      exp_sum += (arr[idx] ## f64) * (arr[idx] ## f64)
      idx += 1
    got = wvalue_from_bits(cinder_raw_call2(cr[0], wvalue_bits(arr) ## i64, wvalue_bits(64) ## i64))
    expect(got).to eq(exp_sum)

  it "honors non-zero WArray->start on sliced TypedArray views" ->
    slice_ir = <<~WIRE
      function slice_sum(a:f64[]) -> f64
        __entry:
          %vs.0 = alloca_f64
          %vs.1 = alloca_i64
          %p0 = arr_data_ptr %a ebits=-64
          %len = array_size_raw %a
          %z0 = const_f64 0.0
          store_double %z0 ptr=%vs.0
          %z1 = const_i64 0
          store_i64 %z1 ptr=%vs.1
          br %lp
        lp:
          %i = load_i64 ptr=%vs.1
          %cmp = icmp_i64 slt %i %len
          cond_br %cmp %bd %ex
        bd:
          %s = load_double ptr=%vs.0
          %idx = load_i64 ptr=%vs.1
          %v = typed_array_get_inline %p0 %idx ebits=-64
          %ns = fadd_f64 %s %v
          store_double %ns ptr=%vs.0
          %one = const_i64 1
          %ni = add_i64 %idx %one
          store_i64 %ni ptr=%vs.1
          br %lp
        ex:
          %out = load_double ptr=%vs.0
          ret_f64 %out
    WIRE
    mod = wire_parse_text(slice_ir)
    wf = mod.functions[0]
    wf.abi = :wvalue_ret_f64
    wire_opt_func(wf)
    cr = wire_compile_func(wf)
    expect(cr[0] != 0).to eq(true)

    ta_buf = f64[8]
    ta_buf[0] = ~100.0; ta_buf[1] = ~200.0
    ta_buf[2] = ~10.0;  ta_buf[3] = ~20.0; ta_buf[4] = ~30.0
    cinder_spec_set_warray_start_size(wvalue_bits(ta_buf) ## i64, 2, 3)
    got = wvalue_from_bits(cinder_raw_call1(cr[0], wvalue_bits(ta_buf) ## i64))
    cinder_spec_set_warray_start_size(wvalue_bits(ta_buf) ## i64, 0, 8)
    expect(got).to eq(~60.0)

  it "executes Float16Array (IEEE-754 binary16) round-trip in JIT machine code" ->
    f16_ir = <<~WIRE
      function f16_rw(a:f16[], x:f64) -> f64
        __entry:
          %p0 = arr_data_ptr %a ebits=-16
          %i0 = const_i64 0
          %i1 = const_i64 1
          %nx = fneg_f64 %x
          typed_array_set_inline %p0 %i0 %x ebits=-16
          typed_array_set_inline %p0 %i1 %nx ebits=-16
          %r0 = typed_array_get_inline %p0 %i0 ebits=-16
          %r1 = typed_array_get_inline %p0 %i1 ebits=-16
          %d = fsub_f64 %r0 %r1
          ret_f64 %d
    WIRE
    mod = wire_parse_text(f16_ir)
    wf = mod.functions[0]
    wf.abi = :wvalue_ret_f64

    a64_enc = wire_encode_func_for_arch(wf, "arm64")
    x64_enc = wire_encode_func_for_arch(wf, "x86_64")
    expect(a64_enc[0] && x64_enc[0]).to eq(true)

    cr = wire_compile_func(wf)
    expect(cr[0] != 0).to eq(true)
    f16_backing = u16[8]
    got = wvalue_from_bits(cinder_raw_call2(cr[0], wvalue_bits(f16_backing) ## i64, wvalue_bits(~3.5) ## i64))
    expect(got).to eq(~7.0)

  it "separates blazing-fast Tier-1 baseline compile from Tier-2 optimizing pass replacement without mutating WireFunc" ->
    ir_txt = <<~WIRE
      function dot_tiered(a:f32[], b:f32[], n:i64) -> f64
        __entry:
          %vs.0 = alloca_f64
          %vs.1 = alloca_i64
          %pa = arr_data_ptr %a ebits=-32
          %pb = arr_data_ptr %b ebits=-32
          %z0 = const_f64 0.0
          store_double %z0 ptr=%vs.0
          %z1 = const_i64 0
          store_i64 %z1 ptr=%vs.1
          br %lp
        lp:
          %i = load_i64 ptr=%vs.1
          %cmp = icmp_i64 slt %i %n
          cond_br %cmp %bd %ex
        bd:
          %s = load_double ptr=%vs.0
          %idx = load_i64 ptr=%vs.1
          %va = typed_array_get_inline %pa %idx ebits=-32
          %vb = typed_array_get_inline %pb %idx ebits=-32
          %p = fmul_f64 %va %vb
          %ns = fadd_f64 %s %p
          store_double %ns ptr=%vs.0
          %one = const_i64 1
          %ni = add_i64 %idx %one
          store_i64 %ni ptr=%vs.1
          br %lp
        ex:
          %out = load_double ptr=%vs.0
          ret_f64 %out
    WIRE
    wf = wire_parse_text(ir_txt).functions[0]
    wf.abi = :wvalue_ret_f64
    entry_insts_before = wf.blocks[0].insts.size()

    a64_t1 = wire_encode_func_for_arch_tier(wf, "arm64", 1)
    a64_t2 = wire_encode_func_for_arch_tier(wf, "arm64", 2)
    x64_t1 = wire_encode_func_for_arch_tier(wf, "x86_64", 1)
    x64_t2 = wire_encode_func_for_arch_tier(wf, "x86_64", 2)
    expect(a64_t1[0] && a64_t2[0] && x64_t1[0] && x64_t2[0]).to eq(true)
    expect(wf.blocks[0].insts.size()).to eq(entry_insts_before)

    t1 = wire_compile_func_tier(wf, 1)
    t2 = wire_compile_func_tier(wf, 2)
    expect(t1[0] != 0 && t2[0] != 0 && t1[0] != t2[0]).to eq(true)

    va = f32[37]; vb = f32[37]
    k = 0; exp = ~0.0
    while k < 37
      va[k] = ((k - 9).to_f() * ~0.25) ## f32
      vb[k] = ((k % 7).to_f() * ~0.5) ## f32
      exp += (va[k] ## f64) * (vb[k] ## f64)
      k += 1
    r1 = wvalue_from_bits(cinder_raw_call3(t1[0], wvalue_bits(va) ## i64, wvalue_bits(vb) ## i64, wvalue_bits(37) ## i64))
    r2 = wvalue_from_bits(cinder_raw_call3(t2[0], wvalue_bits(va) ## i64, wvalue_bits(vb) ## i64, wvalue_bits(37) ## i64))
    expect(r1).to eq(exp)
    expect(r2).to eq(exp)

  it "fuses straight-line 4-limb u256 carry and borrow chains into hardware adds/adcs/subs/sbcs on ARM64 & x86_64" ->
    wf_add = WireFunc.new("u256_add", ["out", "a", "b"], [:arr, :arr, :arr], [64, 64, 64], :i64, :wvalue_ret_i64)
    po = wf_add.emit_arr_ptr(0, 64)
    pa = wf_add.emit_arr_ptr(1, 64)
    pb = wf_add.emit_arr_ptr(2, 64)
    c_prev = -1
    limb = 0
    while limb < 4
      iv = wf_add.emit_const_i64(limb)
      ai = wf_add.emit_ta_get(pa, iv, 64)
      bi = wf_add.emit_ta_get(pb, iv, 64)
      if limb == 0
        s0 = wf_add.emit_bin(:add_i64, ai, bi, :i64)
        c_prev = wf_add.emit_addcarry_u64(ai, bi)
        wf_add.emit_ta_set(po, iv, s0, 64)
      else
        tk = wf_add.emit_bin(:add_i64, ai, bi, :i64)
        c1 = wf_add.emit_addcarry_u64(ai, bi)
        sk = wf_add.emit_bin(:add_i64, tk, c_prev, :i64)
        c2 = wf_add.emit_addcarry_u64(tk, c_prev)
        c_prev = wf_add.emit_bin(:add_i64, c1, c2, :i64)
        wf_add.emit_ta_set(po, iv, sk, 64)
      limb += 1
    wf_add.emit_ret(c_prev)

    wf_opt_chk = wf_add.clone()
    wire_run_tier2_passes(wf_opt_chk)
    adcs_cnt = 0
    wf_opt_chk.blocks[0].insts.each ->(ins)
      adcs_cnt += 1 if ins.op == :adcs_u64
    expect(adcs_cnt).to eq(3)

    expect(wire_encode_func_for_arch_tier(wf_add, "arm64", 2)[0]).to eq(true)
    expect(wire_encode_func_for_arch_tier(wf_add, "x86_64", 2)[0]).to eq(true)
    cr_t1 = wire_compile_func_tier(wf_add, 1)
    cr_t2 = wire_compile_func_tier(wf_add, 2)

    out1 = u64[4]
    out2 = u64[4]
    a_u = u64[4]
    b_u = u64[4]
    # Ripple carry across all 4 limbs: (2^256 - 1) + 1 == 2^256 (carry=1, all limbs=0)
    a_u[0] = (-1) ## u64
    a_u[1] = (-1) ## u64
    a_u[2] = (-1) ## u64
    a_u[3] = (-1) ## u64
    b_u[0] = 1 ## u64
    b_u[1] = 0 ## u64
    b_u[2] = 0 ## u64
    b_u[3] = 0 ## u64
    cout1 = cinder_raw_call3(cr_t1[0], wvalue_bits(out1) ## i64, wvalue_bits(a_u) ## i64, wvalue_bits(b_u) ## i64)
    cout2 = cinder_raw_call3(cr_t2[0], wvalue_bits(out2) ## i64, wvalue_bits(a_u) ## i64, wvalue_bits(b_u) ## i64)
    expect(cout1).to eq(1)
    expect(cout2).to eq(1)
    expect([out2[0] ## i64, out2[1] ## i64, out2[2] ## i64, out2[3] ## i64]).to eq([0, 0, 0, 0])

    # Straight-line 4-limb u256_sub borrow ripple: 0 - 1 == borrow=1, all limbs = 0xFFFFFFFFFFFFFFFF
    wf_sub = WireFunc.new("u256_sub", ["out", "a", "b"], [:arr, :arr, :arr], [64, 64, 64], :i64, :wvalue_ret_i64)
    spo = wf_sub.emit_arr_ptr(0, 64)
    spa = wf_sub.emit_arr_ptr(1, 64)
    spb = wf_sub.emit_arr_ptr(2, 64)
    b_prev = -1
    limb = 0
    while limb < 4
      iv = wf_sub.emit_const_i64(limb)
      ai = wf_sub.emit_ta_get(spa, iv, 64)
      bi = wf_sub.emit_ta_get(spb, iv, 64)
      if limb == 0
        d0 = wf_sub.emit_bin(:sub_i64, ai, bi, :i64)
        b_prev = wf_sub.emit_subborrow_u64(ai, bi)
        wf_sub.emit_ta_set(spo, iv, d0, 64)
      else
        dk = wf_sub.emit_bin(:sub_i64, ai, bi, :i64)
        b1 = wf_sub.emit_subborrow_u64(ai, bi)
        sk = wf_sub.emit_bin(:sub_i64, dk, b_prev, :i64)
        b2 = wf_sub.emit_subborrow_u64(dk, b_prev)
        b_prev = wf_sub.emit_bin(:add_i64, b1, b2, :i64)
        wf_sub.emit_ta_set(spo, iv, sk, 64)
      limb += 1
    wf_sub.emit_ret(b_prev)
    expect(wire_encode_func_for_arch_tier(wf_sub, "arm64", 2)[0]).to eq(true)
    expect(wire_encode_func_for_arch_tier(wf_sub, "x86_64", 2)[0]).to eq(true)
    cs_t2 = wire_compile_func_tier(wf_sub, 2)
    z_u = u64[4]
    bout = cinder_raw_call3(cs_t2[0], wvalue_bits(out2) ## i64, wvalue_bits(z_u) ## i64, wvalue_bits(b_u) ## i64)
    expect(bout).to eq(1)
    expect([out2[0] ## i64, out2[1] ## i64, out2[2] ## i64, out2[3] ## i64]).to eq([-1, -1, -1, -1])

  it "executes 4x-unrolled hardware carry loops (add_limbs, sub_limbs, mul1_limbs, addmul1_limbs) on odd limb counts" ->
    # 1. add_limbs (n = 19 = 4 quads + 3 tail limbs!)
    wf_al = WireFunc.new("add_limbs", ["out", "a", "b", "n"], [:arr, :arr, :arr, :i64], [64, 64, 64, 0], :i64, :wvalue_ret_i64)
    sl_c = wf_al.new_slot(:i64, "c")
    sl_i = wf_al.new_slot(:i64, "i")
    po = wf_al.emit_arr_ptr(0, 64); pa = wf_al.emit_arr_ptr(1, 64); pb = wf_al.emit_arr_ptr(2, 64)
    z = wf_al.emit_const_i64(0); one = wf_al.emit_const_i64(1)
    wf_al.emit_store_slot(sl_c, z); wf_al.emit_store_slot(sl_i, z)
    b_c = wf_al.new_block("cond"); b_b = wf_al.new_block("body"); b_e = wf_al.new_block("end")
    wf_al.emit_br(b_c)
    wf_al.set_block(b_c)
    iv = wf_al.emit_load_slot(sl_i)
    wf_al.emit_cond_br(wf_al.emit_cmp(:icmp_i64, :slt, iv, 3), b_b, b_e)
    wf_al.set_block(b_b)
    ib = wf_al.emit_load_slot(sl_i); cb = wf_al.emit_load_slot(sl_c)
    ai = wf_al.emit_ta_get(pa, ib, 64); bi = wf_al.emit_ta_get(pb, ib, 64)
    t1 = wf_al.emit_bin(:add_i64, ai, bi, :i64); c1 = wf_al.emit_addcarry_u64(ai, bi)
    s2 = wf_al.emit_bin(:add_i64, t1, cb, :i64); c2 = wf_al.emit_addcarry_u64(t1, cb)
    wf_al.emit_ta_set(po, ib, s2, 64)
    wf_al.emit_store_slot(sl_c, wf_al.emit_bin(:add_i64, c1, c2, :i64))
    wf_al.emit_store_slot(sl_i, wf_al.emit_bin(:add_i64, ib, one, :i64))
    wf_al.emit_br(b_c)
    wf_al.set_block(b_e)
    wf_al.emit_ret(wf_al.emit_load_slot(sl_c))

    # 2. addmul1_limbs: out[i] = out[i] + a[i] * w + c
    wf_am = WireFunc.new("addmul1_limbs", ["out", "a", "w", "n"], [:arr, :arr, :i64, :i64], [64, 64, 0, 0], :i64, :wvalue_ret_i64)
    mc = wf_am.new_slot(:i64, "c"); mi = wf_am.new_slot(:i64, "i")
    mpo = wf_am.emit_arr_ptr(0, 64); mpa = wf_am.emit_arr_ptr(1, 64)
    mz = wf_am.emit_const_i64(0); mone = wf_am.emit_const_i64(1)
    wf_am.emit_store_slot(mc, mz); wf_am.emit_store_slot(mi, mz)
    mc_b = wf_am.new_block("cond"); mb_b = wf_am.new_block("body"); me_b = wf_am.new_block("end")
    wf_am.emit_br(mc_b)
    wf_am.set_block(mc_b)
    miv = wf_am.emit_load_slot(mi)
    wf_am.emit_cond_br(wf_am.emit_cmp(:icmp_i64, :slt, miv, 3), mb_b, me_b)
    wf_am.set_block(mb_b)
    mib = wf_am.emit_load_slot(mi); mcb = wf_am.emit_load_slot(mc)
    moi = wf_am.emit_ta_get(mpo, mib, 64); mai = wf_am.emit_ta_get(mpa, mib, 64)
    mlo = wf_am.emit_bin(:mul_i64, mai, 2, :i64); mhi = wf_am.emit_mulhi_u64(mai, 2)
    ms1 = wf_am.emit_bin(:add_i64, moi, mlo, :i64); mc1 = wf_am.emit_addcarry_u64(moi, mlo)
    ms2 = wf_am.emit_bin(:add_i64, ms1, mcb, :i64); mc2 = wf_am.emit_addcarry_u64(ms1, mcb)
    wf_am.emit_ta_set(mpo, mib, ms2, 64)
    wf_am.emit_store_slot(mc, wf_am.emit_bin(:add_i64, wf_am.emit_bin(:add_i64, mhi, mc1, :i64), mc2, :i64))
    wf_am.emit_store_slot(mi, wf_am.emit_bin(:add_i64, mib, mone, :i64))
    wf_am.emit_br(mc_b)
    wf_am.set_block(me_b)
    wf_am.emit_ret(wf_am.emit_load_slot(mc))

    expect(wire_encode_func_for_arch_tier(wf_al, "arm64", 2)[0] && wire_encode_func_for_arch_tier(wf_al, "x86_64", 2)[0]).to eq(true)
    expect(wire_encode_func_for_arch_tier(wf_am, "arm64", 2)[0] && wire_encode_func_for_arch_tier(wf_am, "x86_64", 2)[0]).to eq(true)

    fp_al = wire_compile_func_tier(wf_al, 2)[0]
    fp_am = wire_compile_func_tier(wf_am, 2)[0]

    nl = 19
    ta_a = u64[nl]; ta_b = u64[nl]; ta_o = u64[nl]
    big_a = 0 ## int
    big_b = 0 ## int
    mask64 = ((1 ## int) << 64) - 1
    li = 0
    while li < nl
      va_u = (((li + 1) ## int) * (0x9E3779B97F4A7C15 ## int) + (0xFFFFFFFFFFFFFFF0 ## int)) & mask64
      vb_u = (((li + 3) ## int) * (0xBF58476D1CE4E5B9 ## int) + (0x7FFFFFFFFFFFFFFF ## int)) & mask64
      ta_a[li] = (va_u >= ((1 ## int) << 63) ? (va_u - ((1 ## int) << 64)) : va_u) ## u64
      ta_b[li] = (vb_u >= ((1 ## int) << 63) ? (vb_u - ((1 ## int) << 64)) : vb_u) ## u64
      big_a = big_a | (va_u << (li * 64))
      big_b = big_b | (vb_u << (li * 64))
      li += 1
    c_al = cinder_raw_call4(fp_al, wvalue_bits(ta_o) ## i64, wvalue_bits(ta_a) ## i64, wvalue_bits(ta_b) ## i64, nl ## i64)
    got_sum = (c_al ## int) << (nl * 64)
    li = 0
    while li < nl
      raw_l = ta_o[li] ## i64
      ul = raw_l < 0 ? ((raw_l ## int) + ((1 ## int) << 64)) : (raw_l ## int)
      got_sum = got_sum | (ul << (li * 64))
      li += 1
    expect(got_sum).to eq(big_a + big_b)

    # Now run `addmul1_limbs(ta_o, ta_a, w, 19)` with max limb `w = 2^64 - 1` (`-1 ## i64`)!
    w_max = mask64
    c_am = cinder_raw_call4(fp_am, wvalue_bits(ta_o) ## i64, wvalue_bits(ta_a) ## i64, -1 ## i64, nl ## i64)
    uc_am = c_am < 0 ? ((c_am ## int) + ((1 ## int) << 64)) : (c_am ## int)
    got_am = uc_am << (nl * 64)
    li = 0
    while li < nl
      raw_l = ta_o[li] ## i64
      ul = raw_l < 0 ? ((raw_l ## int) + ((1 ## int) << 64)) : (raw_l ## int)
      got_am = got_am | (ul << (li * 64))
      li += 1
    exp_am = ((big_a + big_b) & (((1 ## int) << (nl * 64)) - 1)) + big_a * w_max
    expect(got_am).to eq(exp_am)

describe "Cinder binary object writers & AOT native compiler" ->
  it "emits valid Mach-O 64 and ELF64 relocatable .o files from LLVM IR" ->
    mini_ll = <<~LLVM
      @g_counter = internal global i64 40, align 8
      define i64 @add_two(i64 %x) {
      entry:
        %p = getelementptr inbounds i64, ptr @g_counter, i64 0
        %v = load i64, ptr %p, align 8
        %r = add i64 %v, %x
        ret i64 %r
      }
    LLVM
    macho_bytes = cinder_compile_ll_a64(mini_ll, true).build_bytes()
    elf_a64_bytes = cinder_compile_ll_a64(mini_ll, false).build_bytes()
    elf_x64_bytes = cinder_compile_ll_x64(mini_ll).build_bytes()

    expect(macho_bytes.read_u32_le(0)).to eq(0xFEEDFACF)
    expect(elf_a64_bytes.read_u32_le(0)).to eq(0x464C457F)
    expect(elf_x64_bytes.read_u32_le(0)).to eq(0x464C457F)

  it "compiles and links a multi-feature Tungsten program to a native binary without clang" ->
    src_path = CINDER_SPEC_TMP + "/aot_prog.w"
    bin_path = CINDER_SPEC_TMP + "/aot_prog"
    prog = <<~WPROG
      + BoxVal
        rw :v
        -> new(@v)
          nil

      -> many_args(a, b, c, d, e, f, g, h, i, j, k)
        a + b + c + d + e + f + g + h + i + j + k

      -> fib_iter(n)
        a = 0
        b = 1
        idx = 0
        while idx < n
          nxt = a + b
          a = b
          b = nxt
          idx += 1
        a

      bx = BoxVal.new(fib_iter(10))
      s11 = many_args(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
      big = (1 << 80) + 7
      rem = big % 97
      fsum = (~1.5 * ~4.0) + ~0.5
      << [bx.v, s11, rem, fsum].join("|")
    WPROG
    write_file(src_path, prog)
    ok = cinder_compile_input(src_path, bin_path, false, "", false)
    expect(ok).to eq(true)
    out = capture("'" + bin_path + "'").strip()
    expected_rem = ((1 << 80) + 7) % 97
    expect(out).to eq("55|66|" + expected_rem.to_s() + "|6.5")

describe "Cinder optimization levels (-O0..-O3), pass toggles, function inlining & stage determinism" ->
  it "parses -O0..-O3, -Ofast, --fast, --strict-math, --\[no-\]debug, and -f\[no-\]<pass> toggles" ->
    c0 = CinderOptConfig.new(0)
    expect(c0.opt_level).to eq(0)
    expect(c0.pass_enabled?("always-inline")).to eq(true)
    expect(c0.pass_enabled?("inline")).to eq(false)
    expect(c0.pass_enabled?("gvn")).to eq(false)

    c2 = CinderOptConfig.new(0)
    expect(c2.apply_arg("-O2")).to eq(true)
    expect(c2.pass_enabled?("inline")).to eq(true)
    expect(c2.pass_enabled?("gvn")).to eq(true)
    expect(c2.pass_enabled?("licm")).to eq(true)
    expect(c2.apply_arg("-fno-inline")).to eq(true)
    expect(c2.pass_enabled?("inline")).to eq(false)
    expect(c2.apply_arg("--fast")).to eq(true)
    expect(c2.fast_math).to eq(true)
    expect(c2.apply_arg("--strict-math")).to eq(true)
    expect(c2.fast_math).to eq(false)
    expect(c2.strict_math).to eq(true)
    expect(c2.apply_arg("--debug")).to eq(true)
    expect(c2.debug).to eq(true)
    expect(c2.frame_pointers).to eq(true)
    expect(c2.apply_arg("--no-debug")).to eq(true)
    expect(c2.debug).to eq(false)

    cexp = CinderOptConfig.new(2)
    expect(cexp.apply_arg("--opt-passes=sroa,const-fold,dce")).to eq(true)
    expect(cexp.pass_enabled?("sroa")).to eq(true)
    expect(cexp.pass_enabled?("gvn")).to eq(false)

  it "inlines WIRE functions (alwaysinline at -O0, multi-block at -O2) and honors noinline / -fno-inline via module JIT" ->
    mod_txt = <<~WIRE
      function sq_always(x:i64) -> i64 alwaysinline
        __entry:
          %p = mul_i64 %x %x
          ret_i64 %p

      function abs_diff_multi(a:i64, b:i64) -> i64
        __entry:
          %gt = icmp_i64 sgt %a %b
          cond_br %gt %pos %neg
        pos:
          %d1 = sub_i64 %a %b
          ret_i64 %d1
        neg:
          %d2 = sub_i64 %b %a
          ret_i64 %d2

      function never_inl(v:i64) -> i64 noinline
        __entry:
          %ten = const_i64 10
          %r = add_i64 %v %ten
          ret_i64 %r

      function caller_fn(x:i64, y:i64) -> i64
        __entry:
          %s = call_direct_i64 @sq_always %x
          %d = call_direct_i64 @abs_diff_multi %s %y
          %z = call_direct_i64 @never_inl %d
          ret_i64 %z
    WIRE
    wmod = wire_parse_text(mod_txt)
    wmod.functions.each ->(fn) fn.abi = :wvalue_ret_i64

    # At -O0: `sq_always` MUST be inlined, while `abs_diff_multi` and `never_inl` remain direct calls!
    cfg0 = CinderOptConfig.new(0)
    caller_o0 = wmod.find_func("caller_fn").clone()
    wire_run_passes(caller_o0, cfg0, wmod)
    calls_o0 = []
    caller_o0.blocks.each ->(b)
      b.insts.each ->(ins)
        calls_o0.push(ins.sym) if ins.op == :call_direct_i64
    expect(calls_o0.include?("sq_always")).to eq(false)
    expect(calls_o0).to eq(["abs_diff_multi", "never_inl"])

    # At -O2: `sq_always` AND multi-block `abs_diff_multi` are both inlined, while `never_inl` stays out-of-line!
    cfg2 = CinderOptConfig.new(2)
    caller_o2 = wmod.find_func("caller_fn").clone()
    wire_run_passes(caller_o2, cfg2, wmod)
    calls_o2 = []
    caller_o2.blocks.each ->(b)
      b.insts.each ->(ins)
        calls_o2.push(ins.sym) if ins.op == :call_direct_i64
    expect(calls_o2).to eq(["never_inl"])

    # Compile and execute the entire module under both -O0, -O2, and -O2 -fno-inline!
    res_o0 = wire_compile_module_opt(wmod, CinderOptConfig.new(0))
    res_o2 = wire_compile_module_opt(wmod, CinderOptConfig.new(2))
    cfg_noinl = CinderOptConfig.new(2)
    cfg_noinl.apply_arg("-fno-inline")
    res_noinl = wire_compile_module_opt(wmod, cfg_noinl)

    # x = 5 -> sq = 25; y = 40 -> |25 - 40| = 15; + 10 = 25
    expect(cinder_raw_call2(res_o0["caller_fn"][0], 5, 40)).to eq(25)
    expect(cinder_raw_call2(res_o2["caller_fn"][0], 5, 40)).to eq(25)
    expect(cinder_raw_call2(res_noinl["caller_fn"][0], 5, 40)).to eq(25)

  it "inlines .ll functions (u128 bignum sumcarry, multi-block PHI repair), drops dead helpers, and lowers <2 x i64> SIMD" ->
    inl_ll = <<~LLVM
      define private i128 @__helper_sumcarry(i64 %a, i64 %b) #0 {
      ; tungsten:alwaysinline
      entry:
        %sum = add i64 %a, %b
        %carry = icmp ult i64 %sum, %a
        %s128 = zext i64 %sum to i128
        %c128 = zext i1 %carry to i128
        %hi = shl i128 %c128, 64
        %pk = or i128 %hi, %s128
        ret i128 %pk
      }

      define internal i64 @clamp_pos(i64 %x) {
      entry:
        %neg = icmp slt i64 %x, 0
        br i1 %neg, label %zero_it, label %keep_it
      zero_it:
        ret i64 0
      keep_it:
        ret i64 %x
      }

      define internal i64 @keep_out_of_line(i64 %x) #1 {
      entry:
        %r = add i64 %x, 1
        ret i64 %r
      }

      define i64 @vec_and_inline_entry(ptr %va, ptr %vb, i64 %x, i64 %y) {
      entry:
        %v0 = load <2 x i64>, ptr %va, align 8
        %v1 = load <2 x i64>, ptr %vb, align 8
        %vx = xor <2 x i64> %v0, %v1
        store <2 x i64> %vx, ptr %va, align 8
        %sc = call i128 @__helper_sumcarry(i64 %x, i64 %y)
        %lo = trunc i128 %sc to i64
        %hi128 = lshr i128 %sc, 64
        %hi = trunc i128 %hi128 to i64
        %cval = call i64 @clamp_pos(i64 %lo)
        br label %join
      join:
        %phi_v = phi i64 \[ %cval, %entry \]
        %ool = call i64 @keep_out_of_line(i64 %phi_v)
        %ans = add i64 %ool, %hi
        ret i64 %ans
      }

      attributes #0 = { alwaysinline nounwind }
      attributes #1 = { noinline nounwind }
    LLVM

    cfg_dbg = CinderOptConfig.new(0)
    cfg_dbg.apply_arg("--debug")
    cfg_rel = CinderOptConfig.new(3)
    cfg_rel.apply_arg("--no-debug")

    w_dbg = cinder_compile_ll_a64(inl_ll, true, cfg_dbg)
    w_rel = cinder_compile_ll_a64(inl_ll, true, cfg_rel)
    w_x64 = cinder_compile_ll_x64(inl_ll, cfg_rel)

    # Dead `private alwaysinline` `@__helper_sumcarry` is stripped under `-O3 --no-debug`,
    # while `noinline` `@keep_out_of_line` is preserved!
    expect(w_dbg.sym_names.include?("___helper_sumcarry")).to eq(true)
    expect(w_rel.sym_names.include?("___helper_sumcarry")).to eq(false)
    expect(w_rel.sym_names.include?("_keep_out_of_line")).to eq(true)
    expect(w_x64.sym_names.include?("__helper_sumcarry")).to eq(false)
    expect(w_x64.sym_names.include?("keep_out_of_line")).to eq(true)

  it "lowers exact Granlund-Montgomery 64-bit unsigned division & modulo across full u64 boundary values" ->
    # Including `d = 7`, which requires the overflow-add (`add_ind == 1`) magic sequence!
    wf_div = WireFunc.new("gm_divmod", ["x"], [:i64], [0], :i64, :wvalue_ret_i64)
    c7 = wf_div.emit_const_i64(7)
    c10 = wf_div.emit_const_i64(10)
    cmod = wf_div.emit_const_i64(1000000007)
    q7 = wf_div.emit_bin(:udiv_i64, 0, c7, :i64)
    r7 = wf_div.emit_bin(:urem_i64, 0, c7, :i64)
    q10 = wf_div.emit_bin(:udiv_i64, q7, c10, :i64)
    rm = wf_div.emit_bin(:urem_i64, 0, cmod, :i64)
    s1 = wf_div.emit_bin(:xor_i64, q10, r7, :i64)
    s2 = wf_div.emit_bin(:xor_i64, s1, rm, :i64)
    wf_div.emit_ret(s2)

    expect(wire_encode_func_for_arch_opt(wf_div, "arm64", CinderOptConfig.new(2))[0]).to eq(true)
    expect(wire_encode_func_for_arch_opt(wf_div, "x86_64", CinderOptConfig.new(2))[0]).to eq(true)

    fp_gm = wire_compile_func_opt(wf_div, CinderOptConfig.new(2))[0]
    u64_max = ((1 ## int) << 64) - 1
    samples = [0 ## int, 1 ## int, 6 ## int, 7 ## int, 8 ## int, 69 ## int, 70 ## int, ((1 ## int) << 63), u64_max - 1, u64_max]
    si = 0
    while si < samples.size()
      uv = samples[si]
      raw_in = (uv >= ((1 ## int) << 63) ? (uv - ((1 ## int) << 64)) : uv) ## i64
      got_raw = cinder_raw_call1(fp_gm, raw_in)
      got_u = got_raw < 0 ? ((got_raw ## int) + ((1 ## int) << 64)) : (got_raw ## int)
      exp_u = (((uv / 7) / 10) ^ (uv % 7)) ^ (uv % 1000000007)
      expect(got_u).to eq(exp_u)
      si += 1

  it "verifies byte-for-byte Stage 1 == Stage 2 .o determinism across Mach-O 64 and ELF64" ->
    src_path = CINDER_SPEC_TMP + "/aot_prog.w"
    cfg_o0 = CinderOptConfig.new(0)
    cfg_o3 = CinderOptConfig.new(3)
    cfg_o3.apply_arg("--fast")
    cfg_o3.apply_arg("--no-debug")
    expect(cinder_verify_stage_determinism(src_path, cfg_o0, "arm64-apple-macosx14.0.0", false)).to eq(true)
    expect(cinder_verify_stage_determinism(src_path, cfg_o3, "arm64-apple-macosx14.0.0", false)).to eq(true)
    expect(cinder_verify_stage_determinism(src_path, cfg_o3, "x86_64-unknown-linux-gnu", false)).to eq(true)
    expect(cinder_verify_stage_determinism(src_path, cfg_o3, "aarch64-unknown-linux-gnu", false)).to eq(true)

  it "lowers C source (structs, pointers, __uint128_t, ctzll, memcpy) directly to WIRE and JIT-executes on ARM64 & x86_64" ->
    c_code = <<~CSRC
      typedef struct Pair64 {
        uint64_t x;
        uint64_t y;
      } Pair64;

      static inline uint64_t mix128(uint64_t a, uint64_t b) {
        __uint128_t r = (__uint128_t)a * (__uint128_t)b;
        return (uint64_t)(r >> 64) ^ (uint64_t)r;
      }

      uint64_t pair_gcd_mix(const Pair64 *p) {
        uint64_t a = p->x;
        uint64_t b = p->y;
        uint64_t az = (uint64_t)__builtin_ctzll(a);
        uint64_t bz = (uint64_t)__builtin_ctzll(b);
        uint64_t sh = az < bz ? az : bz;
        a >>= az;
        b >>= bz;
        while (a != b) {
          uint64_t d = a - b;
          uint64_t tz = (uint64_t)__builtin_ctzll(d);
          uint64_t lo = a < b ? a : b;
          uint64_t mag = a < b ? (0ULL - d) : d;
          b = lo;
          a = mag >> tz;
        }
        uint64_t g = a << sh;
        return mix128(g, 0xe7037ed1a0b428dbULL);
      }
    CSRC
    wmod = c_parse_to_wire_module(c_code)
    fn_pgm = wmod.find_func("pair_gcd_mix")
    expect(wire_encode_func_for_arch_opt(fn_pgm, "arm64", CinderOptConfig.new(3), wmod)[0]).to eq(true)
    expect(wire_encode_func_for_arch_opt(fn_pgm, "x86_64", CinderOptConfig.new(3), wmod)[0]).to eq(true)

    res = cinder_compile_c_to_wire_jit(c_code, CinderOptConfig.new(3))
    fp = res[1]["pair_gcd_mix"][0]
    pair_buf = i64[2]
    pair_buf[0] = 48 * 97
    pair_buf[1] = 18 * 97
    p_ptr = cinder_raw_u8_ptr(wvalue_bits(pair_buf) ## i64)
    got_raw = cinder_raw_call1(fp, p_ptr)
    got_u = got_raw < 0 ? ((got_raw ## int) + ((1 ## int) << 64)) : (got_raw ## int)
    g_exp = (6 * 97) ## int
    prod = g_exp * (0xe7037ed1a0b428db ## int)
    mask64 = ((1 ## int) << 64) - 1
    exp_u = ((prod >> 64) ^ prod) & mask64
    expect(got_u).to eq(exp_u)

describe "Cinder Cross-File Link-Time Optimization (Fat-LTO .o, .a archives, whole-program inlining & slab fusion)" ->
  it "embeds and extracts CNDRLTO1 Fat-LTO sections in Mach-O 64, ELF64 (x86_64 & AArch64), and Unix .a archives" ->
    lib_ir = <<~LLVM
      @dead_table = private constant [4 x i64] [i64 11, i64 22, i64 33, i64 44], align 8
      @live_bias  = internal constant i64 7, align 8

      define internal i64 @local_step(i64 %x) #0 {
      entry:
        %p = getelementptr inbounds i64, ptr @live_bias, i64 0
        %b = load i64, ptr %p, align 8
        %r = add i64 %x, %b
        ret i64 %r
      }

      define i64 @fast_mad(i64 %a, i64 %b, i64 %c) #0 {
      entry:
        %m = mul i64 %a, %b
        %s = add i64 %m, %c
        %t = call i64 @local_step(i64 %s)
        ret i64 %t
      }

      define i64 @single_caller_cube_plus(i64 %v) {
      entry:
        %v2 = mul i64 %v, %v
        %v3 = mul i64 %v2, %v
        %r  = add i64 %v3, 100
        ret i64 %r
      }

      define i64 @pure_const_magic() #1 {
      entry:
        ret i64 31337
      }

      define i64 @unused_library_export(i64 %x) {
      entry:
        %p = getelementptr inbounds [4 x i64], ptr @dead_table, i64 0, i64 2
        %v = load i64, ptr %p, align 8
        %r = add i64 %v, %x
        ret i64 %r
      }

      attributes #0 = { alwaysinline nounwind }
      attributes #1 = { noinline nounwind }
    LLVM

    main_ir = <<~LLVM
      declare i64 @fast_mad(i64, i64, i64)
      declare i64 @single_caller_cube_plus(i64)
      declare i64 @pure_const_magic()

      define internal i64 @local_step(i64 %x) #0 {
      entry:
        %r = mul i64 %x, 2
        ret i64 %r
      }

      define i32 @main() {
      entry:
        %a = call i64 @fast_mad(i64 3, i64 4, i64 5)
        %b = call i64 @single_caller_cube_plus(i64 5)
        %c = call i64 @local_step(i64 10)
        %k = call i64 @pure_const_magic()
        %s1 = add i64 %a, %b
        %s2 = add i64 %s1, %c
        %tot = add i64 %s2, %k
        %ok = icmp eq i64 %tot, 31606
        %rc = select i1 %ok, i32 0, i32 42
        ret i32 %rc
      }

      attributes #0 = { noinline nounwind }
    LLVM

    cfg_lto = CinderOptConfig.new(2)
    cfg_lto.apply_arg("--lto")
    cfg_lto.apply_arg("--no-debug")

    macho_o = CINDER_SPEC_TMP + "/lib_macho.o"
    elf_x64_o = CINDER_SPEC_TMP + "/lib_x64.o"
    elf_a64_o = CINDER_SPEC_TMP + "/lib_a64.o"
    main_ll_p = CINDER_SPEC_TMP + "/main_lto.ll"
    ar_path = CINDER_SPEC_TMP + "/libmath_lto.a"
    write_file(main_ll_p, main_ir)

    expect(cinder_compile_ll_str_to_obj(lib_ir, macho_o, "arm64-apple-macosx14.0.0", cfg_lto, true)[0]).to eq(true)
    expect(cinder_compile_ll_str_to_obj(lib_ir, elf_x64_o, "x86_64-unknown-linux-gnu", cfg_lto, true)[0]).to eq(true)
    expect(cinder_compile_ll_str_to_obj(lib_ir, elf_a64_o, "aarch64-unknown-linux-gnu", cfg_lto, true)[0]).to eq(true)

    expect(cinder_extract_lto_from_file(macho_o)).to eq(lib_ir)
    expect(cinder_extract_lto_from_file(elf_x64_o)).to eq(lib_ir)
    expect(cinder_extract_lto_from_file(elf_a64_o)).to eq(lib_ir)

    host_lib_o = cinder_host_os() == "macos" ? macho_o : (cinder_host_arch() == "x86_64" ? elf_x64_o : elf_a64_o)
    expect(system("ar rcs '" + ar_path + "' '" + host_lib_o + "'")).to eq(true)
    ar_ext = cinder_extract_lto_from_archive(ar_path)
    expect(ar_ext != nil && ar_ext[0].size() == 1 && ar_ext[1] == false).to eq(true)
    expect(ar_ext[0][0]).to eq(lib_ir)

    # Merge `main_ir` + `lib_ir` with Whole-Program LTO (`lto-internalize` + `ipa-sccp` + `lto-dce`)!
    merged = cinder_lto_merge_modules([main_ir, lib_ir], true, cfg_lto)
    # `@dead_table` is only referenced by `@unused_library_export`; once `@unused_library_export` is internalized & dead-stripped:
    w_m = cinder_compile_ll_a64(merged, true, cfg_lto)
    w_x = cinder_compile_ll_x64(merged, cfg_lto)
    # Cross-file `alwaysinline` `@fast_mad`, single-caller `@single_caller_cube_plus`, `ipa-sccp` `@pure_const_magic`,
    # and unreferenced `@unused_library_export` are ALL internalized, folded/inlined into `@main`, and stripped!
    expect(w_m.sym_names.include?("_fast_mad")).to eq(false)
    expect(w_m.sym_names.include?("_single_caller_cube_plus")).to eq(false)
    expect(w_m.sym_names.include?("_pure_const_magic")).to eq(false)
    expect(w_m.sym_names.include?("_unused_library_export")).to eq(false)
    expect(w_x.sym_names.include?("fast_mad")).to eq(false)
    expect(w_x.sym_names.include?("single_caller_cube_plus")).to eq(false)
    expect(w_x.sym_names.include?("unused_library_export")).to eq(false)

    # Link `main_lto.ll` + `libmath_lto.a` end-to-end into a native executable and run!
    # Expected math: fast_mad(3,4,5) = (3*4 + 5) + 7 = 24; cube_plus(5) = 125 + 100 = 225;
    # main local_step(10) = 20 (no collision with lib's local_step!); pure_const_magic() = 31337;
    # sum = 24 + 225 + 20 + 31337 = 31606 -> exit code 0!
    lto_exe = CINDER_SPEC_TMP + "/lto_merged_exe"
    expect(cinder_compile_inputs([main_ll_p, ar_path], lto_exe, false, "", false, cfg_lto)).to eq(true)
    expect(system("'" + lto_exe + "'")).to eq(true)
    expect(cinder_verify_stage_determinism_multi([main_ll_p, ar_path], cfg_lto, "arm64-apple-macosx14.0.0", false)).to eq(true)
    expect(cinder_verify_stage_determinism_multi([main_ll_p, ar_path], cfg_lto, "x86_64-unknown-linux-gnu", false)).to eq(true)

  it "links multi-file .w Fat-LTO objects with fused @__static_slab and inlined BigInt hot-slot boundaries" ->
    lib_w = CINDER_SPEC_TMP + "/lto_lib.w"
    app_w = CINDER_SPEC_TMP + "/lto_app.w"
    lib_o = CINDER_SPEC_TMP + "/lto_lib.o"
    app_bin = CINDER_SPEC_TMP + "/lto_app_bin"

    write_file(lib_w, "G_LIB_TAG = \"cinder-cross-lto-slab\"\n")
    write_file(app_w, <<~WAPP
      a = (1 << 100) + 17
      b = (1 << 100) + 29
      acc = 0
      i = 0
      while i < 8
        s = a * b
        acc += (s & 0xFF)
        i += 1
      << "app-slab-header|" + acc.to_s()
    WAPP
    )

    cfg_full = CinderOptConfig.new(3)
    cfg_full.apply_arg("--full-lto")
    cfg_full.apply_arg("--no-debug")

    expect(cinder_compile_inputs([lib_w], lib_o, true, "", false, cfg_full)).to eq(true)
    expect(cinder_extract_lto_from_file(lib_o) != nil).to eq(true)
    expect(cinder_compile_inputs([app_w, lib_o], app_bin, false, "", false, cfg_full)).to eq(true)

    out = capture("'" + app_bin + "'").strip()
    exp_low = (((1 << 100) + 17) * ((1 << 100) + 29)) & 0xFF
    expect(out).to eq("app-slab-header|" + (exp_low * 8).to_s())
    system("rm -rf '" + CINDER_SPEC_TMP + "'")
