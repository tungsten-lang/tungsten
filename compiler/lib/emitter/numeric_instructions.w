# Emitter numeric instructions — memory, arithmetic, vectors, and conversions.

-> render_numeric_instruction(inst, string_wvs, used_ptr_ids, phi_label_redirects = nil, fp_flags = "", arm64_target = true, windows_target = false)
  op = wire_kind(inst)

  case op
  # Memory
  when :alloca_i64
    wire_get(inst, :ptr) + " = alloca i64, align 8"
  when :alloca_i128
    wire_get(inst, :ptr) + " = alloca i128, align 16"
  when :store_i64
    "store i64 " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :ptr) + ", align 8"
  when :store_i128
    "store i128 " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :ptr) + ", align 16"
  when :store_float
    "store float " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :ptr) + ", align 4"
  when :store_double
    "store double " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :ptr) + ", align 8"
  when :load_i64
    wire_get(inst, :temp) + " = load i64, ptr " + wire_get(inst, :ptr) + ", align 8" + range_metadata_suffix(inst, "i64")
  when :load_float
    wire_get(inst, :temp) + " = load float, ptr " + wire_get(inst, :ptr) + ", align 4"
  when :load_double
    wire_get(inst, :temp) + " = load double, ptr " + wire_get(inst, :ptr) + ", align 8"
  when :load_u8_ptr
    p = wire_get(inst, :temp) + ".p"
    ep = wire_get(inst, :temp) + ".ep"
    b = wire_get(inst, :temp) + ".b"
    p + " = inttoptr i64 " + wire_get(inst, :ptr) + " to ptr\n  " + ep + " = getelementptr i8, ptr " + p + ", i64 " + wire_get(inst, :index) + "\n  " + b + " = load i8, ptr " + ep + ", align 1" + range_metadata_suffix(inst, "i8") + "\n  " + wire_get(inst, :temp) + " = zext i8 " + b + " to i64"
  when :store_u8_ptr
    p = wire_get(inst, :temp) + ".p"
    ep = wire_get(inst, :temp) + ".ep"
    b = wire_get(inst, :temp) + ".b"
    p + " = inttoptr i64 " + wire_get(inst, :ptr) + " to ptr\n  " + ep + " = getelementptr i8, ptr " + p + ", i64 " + wire_get(inst, :index) + "\n  " + b + " = trunc i64 " + wire_get(inst, :value) + " to i8\n  store i8 " + b + ", ptr " + ep + ", align 1\n  " + wire_get(inst, :temp) + " = zext i8 " + b + " to i64"
  when :load_u32_ptr
    p = wire_get(inst, :temp) + ".p"
    ep = wire_get(inst, :temp) + ".ep"
    w = wire_get(inst, :temp) + ".w"
    p + " = inttoptr i64 " + wire_get(inst, :ptr) + " to ptr\n  " + ep + " = getelementptr i8, ptr " + p + ", i64 " + wire_get(inst, :index) + "\n  " + w + " = load i32, ptr " + ep + ", align 1" + range_metadata_suffix(inst, "i32") + "\n  " + wire_get(inst, :temp) + " = zext i32 " + w + " to i64"
  when :load_u64_ptr
    p = wire_get(inst, :temp) + ".p"
    ep = wire_get(inst, :temp) + ".ep"
    p + " = inttoptr i64 " + wire_get(inst, :ptr) + " to ptr\n  " + ep + " = getelementptr i8, ptr " + p + ", i64 " + wire_get(inst, :index) + "\n  " + wire_get(inst, :temp) + " = load i64, ptr " + ep + ", align 1" + range_metadata_suffix(inst, "i64")
  when :ptr_slot_get
    p = wire_get(inst, :temp) + ".p"
    ep = wire_get(inst, :temp) + ".ep"
    slot_type = wire_get(inst, :slot_type)
    if slot_type == "w64" || slot_type == "i64" || slot_type == "u64"
      p + " = inttoptr i64 " + wire_get(inst, :ptr) + " to ptr\n  " + ep + " = getelementptr i64, ptr " + p + ", i64 " + wire_get(inst, :index) + "\n  " + wire_get(inst, :temp) + " = load i64, ptr " + ep + ", align 8"
    elsif slot_type == "u8" || slot_type == "i8"
      b = wire_get(inst, :temp) + ".b"
      p + " = inttoptr i64 " + wire_get(inst, :ptr) + " to ptr\n  " + ep + " = getelementptr i8, ptr " + p + ", i64 " + wire_get(inst, :index) + "\n  " + b + " = load i8, ptr " + ep + ", align 1\n  " + wire_get(inst, :temp) + " = zext i8 " + b + " to i64"
    else
      p + " = inttoptr i64 " + wire_get(inst, :ptr) + " to ptr\n  " + ep + " = getelementptr i64, ptr " + p + ", i64 " + wire_get(inst, :index) + "\n  " + wire_get(inst, :temp) + " = load i64, ptr " + ep + ", align 8"
  when :load_i128
    wire_get(inst, :temp) + " = load i128, ptr " + wire_get(inst, :ptr) + ", align 16" + range_metadata_suffix(inst, "i128")

  # Integer arithmetic
  when :add_i64
    wire_get(inst, :temp) + " = add i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :sub_i64
    wire_get(inst, :temp) + " = sub i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :mul_i64
    wire_get(inst, :temp) + " = mul i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :sdiv_i64
    wire_get(inst, :temp) + " = sdiv i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :udiv_i64
    wire_get(inst, :temp) + " = udiv i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :srem_i64
    wire_get(inst, :temp) + " = srem i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :urem_i64
    wire_get(inst, :temp) + " = urem i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :add_i128
    wire_get(inst, :temp) + " = add i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :sub_i128
    wire_get(inst, :temp) + " = sub i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :mul_i128
    wire_get(inst, :temp) + " = mul i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :mulhi_u64
    # high 64 bits of the unsigned 64x64->128 product. LLVM lowers this to a
    # single UMULH on arm64 / MULX on x86 — the carry-primitive `mulhi`.
    t = wire_get(inst, :temp)
    o = StringBuffer(192)
    o << t + ".az = zext i64 " + wire_get(inst, :lhs) + " to i128\n  "
    o << t + ".bz = zext i64 " + wire_get(inst, :rhs) + " to i128\n  "
    o << t + ".pp = mul i128 " + t + ".az, " + t + ".bz\n  "
    o << t + ".hs = lshr i128 " + t + ".pp, 64\n  "
    o << t + " = trunc i128 " + t + ".hs to i64"
    o.to_s()
  when :addcarry_u64
    # carry-out (0/1) of a + b via i128 widening: ((zext a + zext b) >> 64).
    # LLVM keeps the carry in the flag and chains these as ADDS/ADCS instead of
    # materialising it with CMP/CSET. Carry-primitive `addcarry`.
    t = wire_get(inst, :temp)
    o = StringBuffer(192)
    o << t + ".az = zext i64 " + wire_get(inst, :lhs) + " to i128\n  "
    o << t + ".bz = zext i64 " + wire_get(inst, :rhs) + " to i128\n  "
    o << t + ".sm = add i128 " + t + ".az, " + t + ".bz\n  "
    o << t + ".hs = lshr i128 " + t + ".sm, 64\n  "
    o << t + " = trunc i128 " + t + ".hs to i64"
    o.to_s()
  when :subborrow_u64
    # borrow-out (0/1) of a - b via i128: ((zext a - zext b) >> 127). When a<b the
    # i128 difference is negative (sign bit set) -> 1, else 0. LLVM chains these as
    # SUBS/SBCS. Carry-primitive `subborrow`.
    t = wire_get(inst, :temp)
    o = StringBuffer(192)
    o << t + ".az = zext i64 " + wire_get(inst, :lhs) + " to i128\n  "
    o << t + ".bz = zext i64 " + wire_get(inst, :rhs) + " to i128\n  "
    o << t + ".df = sub i128 " + t + ".az, " + t + ".bz\n  "
    o << t + ".hs = lshr i128 " + t + ".df, 127\n  "
    o << t + " = trunc i128 " + t + ".hs to i64"
    o.to_s()
  when :asm_add_test
    # POC: prove LLVM inline asm emits/links/runs. a+b via an aarch64 ADD.
    wire_get(inst, :temp) + " = call i64 asm sideeffect \"add ${0:x}, ${1:x}, ${2:x}\", \"=r,r,r\"(i64 " + wire_get(inst, :lhs) + ", i64 " + wire_get(inst, :rhs) + ")"
  when :arr_data_ptr
    # raw data-base pointer (as i64) of a u64[]: header tag-mask, +16, load ptr.
    t = wire_get(inst, :temp)
    t + ".ar = and i64 " + wire_get(inst, :arr) + ", 140737488355312\n  " + t + ".bp = inttoptr i64 " + t + ".ar to ptr\n  " + t + ".gp = getelementptr i8, ptr " + t + ".bp, i64 16\n  " + t + ".pp = load ptr, ptr " + t + ".gp\n  " + t + " = ptrtoint ptr " + t + ".pp to i64"
  when :asm_add_n
    # Flag-threaded adc loop: out[i]=a[i]+b[i] over n limbs, carry kept
    # in the flag across iterations (sub/cbnz don't clobber C). Returns final carry.
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Acmn xzr, xzr\\0A1:\\0Aldr x10, \[x13], #8\\0Aldr x11, \[x14], #8\\0Aadcs x12, x10, x11\\0Astr x12, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Acset ${0:x}, cs"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}\"(i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_neon_umull
    # POC: NEON 2-lane umull loop. out[2i,2i+1] = a[i].lanes * b[i].lanes (u32->u64).
    # All via memory + GPR pointer operands; NEON work internal (v-reg clobbers).
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0A1:\\0Ald1 {v1.2s}, \[x13], #8\\0Ald1 {v2.2s}, \[x14], #8\\0Aumull v0.2d, v1.2s, v2.2s\\0Ast1 {v0.2d}, \[x15], #16\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{memory},~{cc}\"(i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_neon_redc
    # NEON 2-lane Montgomery REDC: out[i] = REDC(a[i]*b[i]) mod p=998244353, R=2^32.
    # ninv=998244351. t=a*b; m=(t mod R)*ninv mod R; t=(t+m*p)>>32; if t>=p t-=p.
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Amov w10, #1\\0Amovk w10, #15232, lsl #16\\0Adup v5.2s, w10\\0Auxtl v7.2d, v5.2s\\0Amov w11, #65535\\0Amovk w11, #15231, lsl #16\\0Adup v6.2s, w11\\0A1:\\0Ald1 {v1.2s}, \[x13], #8\\0Ald1 {v2.2s}, \[x14], #8\\0Aumull v0.2d, v1.2s, v2.2s\\0Axtn v3.2s, v0.2d\\0Amul v3.2s, v3.2s, v6.2s\\0Aumull v4.2d, v3.2s, v5.2s\\0Aadd v0.2d, v0.2d, v4.2d\\0Aushr v0.2d, v0.2d, #32\\0Asub v8.2d, v0.2d, v7.2d\\0Acmhs v16.2d, v0.2d, v7.2d\\0Abit v0.16b, v8.16b, v16.16b\\0Axtn v0.2s, v0.2d\\0Ast1 {v0.2s}, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x11},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{v16},~{memory},~{cc}\"(i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_neon_redc4
    # NEON 4-lane Montgomery REDC: out lanes = REDC(a*b) mod p=998244353, R=2^32.
    # Processes 4 u32 lanes (= 2 u64 elements) per iter via umull+umull2. n = #pairs.
    # ninv=998244351. t=a*b; m=(t&mask)*ninv&mask; t=(t+m*p)>>32; if t>=p t-=p.
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Amov w10, #1\\0Amovk w10, #15232, lsl #16\\0Adup v5.4s, w10\\0Auxtl v7.2d, v5.2s\\0Amov w11, #65535\\0Amovk w11, #15231, lsl #16\\0Adup v6.4s, w11\\0A1:\\0Ald1 {v1.4s}, \[x13], #16\\0Ald1 {v2.4s}, \[x14], #16\\0Aumull v0.2d, v1.2s, v2.2s\\0Aumull2 v17.2d, v1.4s, v2.4s\\0Axtn v3.2s, v0.2d\\0Amul v3.2s, v3.2s, v6.2s\\0Aumull v4.2d, v3.2s, v5.2s\\0Aadd v0.2d, v0.2d, v4.2d\\0Aushr v0.2d, v0.2d, #32\\0Asub v8.2d, v0.2d, v7.2d\\0Acmhs v16.2d, v0.2d, v7.2d\\0Abit v0.16b, v8.16b, v16.16b\\0Axtn v18.2s, v17.2d\\0Amul v18.2s, v18.2s, v6.2s\\0Aumull v19.2d, v18.2s, v5.2s\\0Aadd v17.2d, v17.2d, v19.2d\\0Aushr v17.2d, v17.2d, #32\\0Asub v20.2d, v17.2d, v7.2d\\0Acmhs v21.2d, v17.2d, v7.2d\\0Abit v17.16b, v20.16b, v21.16b\\0Axtn v0.2s, v0.2d\\0Axtn2 v0.4s, v17.2d\\0Ast1 {v0.4s}, \[x15], #16\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x11},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{v16},~{v17},~{v18},~{v19},~{v20},~{v21},~{memory},~{cc}\"(i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_neon_madd4
    # NEON 4-lane modular add mod p=998244353: out=a+b; if out>=p out-=p. 4 u32/iter.
    # inputs < p, sum < 2p < 2^31 so 32-bit lane add cannot overflow. n = #pairs.
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Amov w10, #1\\0Amovk w10, #15232, lsl #16\\0Ains v5.s\[0], w10\\0Ains v5.s\[1], w10\\0Ains v5.s\[2], w10\\0Ains v5.s\[3], w10\\0A1:\\0Ald1 {v1.4s}, \[x13], #16\\0Ald1 {v2.4s}, \[x14], #16\\0Aadd v0.4s, v1.4s, v2.4s\\0Acmhs v4.4s, v0.4s, v5.4s\\0Aand v6.16b, v4.16b, v5.16b\\0Asub v0.4s, v0.4s, v6.4s\\0Ast1 {v0.4s}, \[x15], #16\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{v4},~{v5},~{v6},~{memory},~{cc}\"(i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_neon_msub4
    # NEON 4-lane modular sub mod p=998244353: r=a-b; if a<b r+=p. 4 u32/iter.
    # use: d=a-b (u32 wrap); if a<b (cmhi b>a) add p. n = #pairs.
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Amov w10, #1\\0Amovk w10, #15232, lsl #16\\0Adup v5.4s, w10\\0A1:\\0Ald1 {v1.4s}, \[x13], #16\\0Ald1 {v2.4s}, \[x14], #16\\0Asub v0.4s, v1.4s, v2.4s\\0Acmhi v4.4s, v2.4s, v1.4s\\0Aand v6.16b, v4.16b, v5.16b\\0Aadd v0.4s, v0.4s, v6.4s\\0Ast1 {v0.4s}, \[x15], #16\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{v4},~{v5},~{v6},~{memory},~{cc}\"(i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_neon_ntt_stage
    # Whole-butterfly NEON DIT NTT stage, mod p=998244353, Montgomery, R=2^32.
    # v = coeffs as 4xu32/16B; stw = per-stage twiddles (u32, len=half). For each of
    # nblocks blocks: a=block base, b=a+half; for halfq groups of 4: t=REDC(b,w);
    # store a+t at a, a-t at b. ALL in vector regs (load->modmul->add/sub->store).
    # operands: ${1}=v ${2}=stw ${3}=nblocks ${4}=halfq.  half_bytes=halfq*16.
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x9, ${3:x}\\0Amov x10, ${4:x}\\0Alsl x11, x10, #4\\0Amov w12, #1\\0Amovk w12, #15232, lsl #16\\0Adup v5.4s, w12\\0Auxtl v7.2d, v5.2s\\0Amov w12, #65535\\0Amovk w12, #15231, lsl #16\\0Adup v6.4s, w12\\0A2:\\0Amov x15, x13\\0Aadd x16, x13, x11\\0Amov x17, x14\\0Amov x8, x10\\0A3:\\0Ald1 {v1.4s}, \[x15]\\0Ald1 {v2.4s}, \[x16]\\0Ald1 {v9.4s}, \[x17], #16\\0Aumull v0.2d, v2.2s, v9.2s\\0Aumull2 v10.2d, v2.4s, v9.4s\\0Axtn v3.2s, v0.2d\\0Amul v3.2s, v3.2s, v6.2s\\0Aumull v4.2d, v3.2s, v5.2s\\0Aadd v0.2d, v0.2d, v4.2d\\0Aushr v0.2d, v0.2d, #32\\0Asub v8.2d, v0.2d, v7.2d\\0Acmhs v11.2d, v0.2d, v7.2d\\0Abit v0.16b, v8.16b, v11.16b\\0Axtn v12.2s, v10.2d\\0Amul v12.2s, v12.2s, v6.2s\\0Aumull v13.2d, v12.2s, v5.2s\\0Aadd v10.2d, v10.2d, v13.2d\\0Aushr v10.2d, v10.2d, #32\\0Asub v14.2d, v10.2d, v7.2d\\0Acmhs v15.2d, v10.2d, v7.2d\\0Abit v10.16b, v14.16b, v15.16b\\0Axtn v0.2s, v0.2d\\0Axtn2 v0.4s, v10.2d\\0Aadd v16.4s, v1.4s, v0.4s\\0Acmhs v17.4s, v16.4s, v5.4s\\0Aand v18.16b, v17.16b, v5.16b\\0Asub v16.4s, v16.4s, v18.4s\\0Asub v19.4s, v1.4s, v0.4s\\0Acmhi v20.4s, v0.4s, v1.4s\\0Aand v21.16b, v20.16b, v5.16b\\0Aadd v19.4s, v19.4s, v21.4s\\0Ast1 {v16.4s}, \[x15], #16\\0Ast1 {v19.4s}, \[x16], #16\\0Asub x8, x8, #1\\0Acbnz x8, 3b\\0Aadd x13, x13, x11, lsl #1\\0Asub x9, x9, #1\\0Acbnz x9, 2b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{v9},~{v10},~{v11},~{v12},~{v13},~{v14},~{v15},~{v16},~{v17},~{v18},~{v19},~{v20},~{v21},~{memory},~{cc}\"(i64 " + wire_get(inst, :vp) + ", i64 " + wire_get(inst, :twp) + ", i64 " + wire_get(inst, :nb) + ", i64 " + wire_get(inst, :hq) + ")"
  when :asm_gold_stage
    # Scalar Goldilocks radix-4 DIF NTT stage. P=2^64-2^32+1, ep=2^32-1.
    # ${1}=v ${2}=stw ${3}=nblocks ${4}=q.  block = 4*q coeffs = q*32 bytes.
    # Reduced register footprint (indexed loads, 3 scratch). Regs:
    #  x1=block base, x2=stw ptr, x3=stw base, x4=block ctr, x5=q (group reload),
    #  x6=qbytes(q*8), x7=group ctr, x8=i0 ptr, x9=2*qbytes, x10=3*qbytes,
    #  x12=ep, x13=pp(=P); coeffs/y in x14..x17; t0=x19 t1=x20 t2=x21 d=x22
    #  t3=x23; scratch x24,x25,x26 (x26 also holds w/prod in mul phase).
    # i1..i3 via indexed addressing [x8,x6]/[x8,x9]/[x8,x10].
    t = wire_get(inst, :temp)
    asmt = "mov x1, ${1:x}\\0Amov x3, ${2:x}\\0Amov x4, ${3:x}\\0Amov x5, ${4:x}\\0Alsl x6, x5, #3\\0Alsl x9, x5, #4\\0Aadd x10, x9, x6\\0Amovz x12, #65535\\0Amovk x12, #65535, lsl #16\\0Amovz x13, #1\\0Amovk x13, #65535, lsl #32\\0Amovk x13, #65535, lsl #48\\0A2:\\0Amov x8, x1\\0Amov x2, x3\\0Amov x7, x5\\0A3:\\0Aldr x14, \[x8]\\0Aldr x15, \[x8, x6]\\0Aldr x16, \[x8, x9]\\0Aldr x17, \[x8, x10]\\0Aadds x19, x14, x16\\0Acsel x24, x12, xzr, cs\\0Aadd x19, x19, x24\\0Asubs x24, x19, x13\\0Acsel x19, x24, x19, hs\\0Asubs x20, x14, x16\\0Acsel x24, x13, xzr, cc\\0Aadd x20, x20, x24\\0Aadds x21, x15, x17\\0Acsel x24, x12, xzr, cs\\0Aadd x21, x21, x24\\0Asubs x24, x21, x13\\0Acsel x21, x24, x21, hs\\0Asubs x22, x15, x17\\0Acsel x24, x13, xzr, cc\\0Aadd x22, x22, x24\\0Alsl x24, x22, #48\\0Aubfx x25, x22, #16, #48\\0Alsr x26, x25, #32\\0Aand x25, x25, x12\\0Asubs x23, x24, x26\\0Acsel x24, x12, xzr, cc\\0Asub x23, x23, x24\\0Alsl x24, x25, #32\\0Asub x24, x24, x25\\0Aadds x23, x23, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x23, x23, x24\\0Asubs x24, x23, x13\\0Acsel x23, x24, x23, hs\\0Aadds x14, x19, x21\\0Acsel x24, x12, xzr, cs\\0Aadd x14, x14, x24\\0Asubs x24, x14, x13\\0Acsel x14, x24, x14, hs\\0Aadds x15, x20, x23\\0Acsel x24, x12, xzr, cs\\0Aadd x15, x15, x24\\0Asubs x24, x15, x13\\0Acsel x15, x24, x15, hs\\0Asubs x16, x19, x21\\0Acsel x24, x13, xzr, cc\\0Aadd x16, x16, x24\\0Asubs x17, x20, x23\\0Acsel x24, x13, xzr, cc\\0Aadd x17, x17, x24\\0Astr x14, \[x8]\\0Aldr x26, \[x2]\\0Amul x25, x15, x26\\0Aumulh x26, x15, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x25, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x25, x25, x24\\0Asubs x24, x25, x13\\0Acsel x25, x24, x25, hs\\0Astr x25, \[x8, x6]\\0Aldr x26, \[x2, #8]\\0Amul x25, x16, x26\\0Aumulh x26, x16, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x25, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x25, x25, x24\\0Asubs x24, x25, x13\\0Acsel x25, x24, x25, hs\\0Astr x25, \[x8, x9]\\0Aldr x26, \[x2, #16]\\0Amul x25, x17, x26\\0Aumulh x26, x17, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x25, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x25, x25, x24\\0Asubs x24, x25, x13\\0Acsel x25, x24, x25, hs\\0Astr x25, \[x8, x10]\\0Aadd x8, x8, #8\\0Aadd x2, x2, #24\\0Asubs x7, x7, #1\\0Acbnz x7, 3b\\0Aadd x1, x1, x6, lsl #2\\0Asubs x4, x4, #1\\0Acbnz x4, 2b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x1},~{x2},~{x3},~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{x19},~{x20},~{x21},~{x22},~{x23},~{x24},~{x25},~{x26},~{memory},~{cc}\"(i64 " + wire_get(inst, :vp) + ", i64 " + wire_get(inst, :twp) + ", i64 " + wire_get(inst, :nb) + ", i64 " + wire_get(inst, :hq) + ")"
  when :asm_gold_stage_inv
    # Scalar Goldilocks radix-4 DIT (inverse) NTT stage. P=2^64-2^32+1, ep=2^32-1.
    # ${1}=v ${2}=stw ${3}=iv ${4}=nblocks ${5}=q.  block = 4*q coeffs.
    #  x1=block base, x2=stw ptr, x3=stw base, x4=block ctr, x5=q, x6=qbytes,
    #  x7=group ctr, x8=i0 ptr, x9=2*qbytes, x10=3*qbytes, x11=iinv,
    #  x12=ep, x13=pp; coeffs a0..a3 in x14..x17; t0=x19 t1=x20 t2=x21 d=x22
    #  t3=x23; scratch x24,x25,x26.  Twiddle FIRST (in place), then combine.
    t = wire_get(inst, :temp)
    asmt = "mov x1, ${1:x}\\0Amov x3, ${2:x}\\0Aldr x11, \[${3:x}]\\0Amov x4, ${4:x}\\0Alsl x6, ${5:x}, #3\\0Alsl x9, x6, #1\\0Aadd x10, x9, x6\\0Amovz x12, #65535\\0Amovk x12, #65535, lsl #16\\0Amovz x13, #1\\0Amovk x13, #65535, lsl #32\\0Amovk x13, #65535, lsl #48\\0A2:\\0Amov x8, x1\\0Amov x2, x3\\0Alsr x7, x6, #3\\0A3:\\0Aldr x14, \[x8]\\0Aldr x15, \[x8, x6]\\0Aldr x16, \[x8, x9]\\0Aldr x17, \[x8, x10]\\0Aldr x26, \[x2]\\0Amul x25, x15, x26\\0Aumulh x26, x15, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x15, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x15, x15, x24\\0Asubs x24, x15, x13\\0Acsel x15, x24, x15, hs\\0Aldr x26, \[x2, #8]\\0Amul x25, x16, x26\\0Aumulh x26, x16, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x16, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x16, x16, x24\\0Asubs x24, x16, x13\\0Acsel x16, x24, x16, hs\\0Aldr x26, \[x2, #16]\\0Amul x25, x17, x26\\0Aumulh x26, x17, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x17, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x17, x17, x24\\0Asubs x24, x17, x13\\0Acsel x17, x24, x17, hs\\0Aadds x19, x14, x16\\0Acsel x24, x12, xzr, cs\\0Aadd x19, x19, x24\\0Asubs x24, x19, x13\\0Acsel x19, x24, x19, hs\\0Asubs x20, x14, x16\\0Acsel x24, x13, xzr, cc\\0Aadd x20, x20, x24\\0Aadds x21, x15, x17\\0Acsel x24, x12, xzr, cs\\0Aadd x21, x21, x24\\0Asubs x24, x21, x13\\0Acsel x21, x24, x21, hs\\0Asubs x22, x15, x17\\0Acsel x24, x13, xzr, cc\\0Aadd x22, x22, x24\\0Amul x25, x22, x11\\0Aumulh x26, x22, x11\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x23, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x23, x23, x24\\0Asubs x24, x23, x13\\0Acsel x23, x24, x23, hs\\0Aadds x14, x19, x21\\0Acsel x24, x12, xzr, cs\\0Aadd x14, x14, x24\\0Asubs x24, x14, x13\\0Acsel x14, x24, x14, hs\\0Astr x14, \[x8]\\0Aadds x15, x20, x23\\0Acsel x24, x12, xzr, cs\\0Aadd x15, x15, x24\\0Asubs x24, x15, x13\\0Acsel x15, x24, x15, hs\\0Astr x15, \[x8, x6]\\0Asubs x16, x19, x21\\0Acsel x24, x13, xzr, cc\\0Aadd x16, x16, x24\\0Astr x16, \[x8, x9]\\0Asubs x17, x20, x23\\0Acsel x24, x13, xzr, cc\\0Aadd x17, x17, x24\\0Astr x17, \[x8, x10]\\0Aadd x8, x8, #8\\0Aadd x2, x2, #24\\0Asubs x7, x7, #1\\0Acbnz x7, 3b\\0Aadd x1, x1, x6, lsl #2\\0Asubs x4, x4, #1\\0Acbnz x4, 2b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,~{x1},~{x2},~{x3},~{x4},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{x19},~{x20},~{x21},~{x22},~{x23},~{x24},~{x25},~{x26},~{memory},~{cc}\"(i64 " + wire_get(inst, :vp) + ", i64 " + wire_get(inst, :twp) + ", i64 " + wire_get(inst, :ivp) + ", i64 " + wire_get(inst, :nb) + ", i64 " + wire_get(inst, :hq) + ")"
  when :asm_neon_gadd2
    # NEON 2-lane Goldilocks add: out[i] lanes = gadd(a,b) mod P=2^64-2^32+1.
    # r=a+b; if r<a (overflow) r+=ep(0xFFFFFFFF); if r>=pp(2^64-ep) r-=pp. 2 u64/op.
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Amovz w10, #65535\\0Amovk w10, #65535, lsl #16\\0Adup v7.2d, x10\\0Amovz x11, #1\\0Amovk x11, #65535, lsl #32\\0Amovk x11, #65535, lsl #48\\0Adup v6.2d, x11\\0A1:\\0Ald1 {v1.2d}, \[x13], #16\\0Ald1 {v2.2d}, \[x14], #16\\0Aadd v0.2d, v1.2d, v2.2d\\0Acmhi v3.2d, v1.2d, v0.2d\\0Aand v4.16b, v3.16b, v7.16b\\0Aadd v0.2d, v0.2d, v4.2d\\0Acmhs v5.2d, v0.2d, v6.2d\\0Aand v8.16b, v5.16b, v6.16b\\0Asub v0.2d, v0.2d, v8.2d\\0Ast1 {v0.2d}, \[x15], #16\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x11},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{memory},~{cc}\"(i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_add_no
    # offset add_n: out[oo..]=a[ao..]+b[bo..] over n limbs; ptr = base + off<<3 in
    # asm. Flag-threaded adc returns carry. (basecase for the Toom ladder)
    # Non-arm64 targets get a portable i128-carry IR loop with identical
    # semantics (the arch-gated-kernel contract: WIRE op is the portable
    # boundary, the emitter target-selects the body).
    t = wire_get(inst, :temp)
    if !arm64_target
      bid = t.slice(1, t.size() - 1)
      po = StringBuffer(1024)
      po << t + ".oo3 = shl i64 " + wire_get(inst, :ooff) + ", 3\n  "
      po << t + ".ob = add i64 " + wire_get(inst, :outp) + ", " + t + ".oo3\n  "
      po << t + ".ao3 = shl i64 " + wire_get(inst, :aoff) + ", 3\n  "
      po << t + ".ab = add i64 " + wire_get(inst, :ap) + ", " + t + ".ao3\n  "
      po << t + ".bo3 = shl i64 " + wire_get(inst, :boff) + ", 3\n  "
      po << t + ".bb = add i64 " + wire_get(inst, :bp) + ", " + t + ".bo3\n  "
      po << "br label %ano.pre." + bid + "\n"
      po << "ano.pre." + bid + ":\n  "
      po << "br label %ano.head." + bid + "\n"
      po << "ano.head." + bid + ":\n  "
      po << t + ".i = phi i64 \[ 0, %ano.pre." + bid + " ], \[ " + t + ".i2, %ano.body." + bid + " ]\n  "
      po << t + ".c = phi i64 \[ 0, %ano.pre." + bid + " ], \[ " + t + ".c2, %ano.body." + bid + " ]\n  "
      po << t + ".done = icmp sge i64 " + t + ".i, " + wire_get(inst, :n) + "\n  "
      po << "br i1 " + t + ".done, label %ano.exit." + bid + ", label %ano.body." + bid + "\n"
      po << "ano.body." + bid + ":\n  "
      po << t + ".i8 = shl i64 " + t + ".i, 3\n  "
      po << t + ".aa = add i64 " + t + ".ab, " + t + ".i8\n  "
      po << t + ".ap = inttoptr i64 " + t + ".aa to ptr\n  "
      po << t + ".av = load i64, ptr " + t + ".ap, align 8\n  "
      po << t + ".ba = add i64 " + t + ".bb, " + t + ".i8\n  "
      po << t + ".bpp = inttoptr i64 " + t + ".ba to ptr\n  "
      po << t + ".bv = load i64, ptr " + t + ".bpp, align 8\n  "
      po << t + ".az = zext i64 " + t + ".av to i128\n  "
      po << t + ".bz = zext i64 " + t + ".bv to i128\n  "
      po << t + ".cz = zext i64 " + t + ".c to i128\n  "
      po << t + ".s1 = add i128 " + t + ".az, " + t + ".bz\n  "
      po << t + ".s2 = add i128 " + t + ".s1, " + t + ".cz\n  "
      po << t + ".lo = trunc i128 " + t + ".s2 to i64\n  "
      po << t + ".hi = lshr i128 " + t + ".s2, 64\n  "
      po << t + ".c2 = trunc i128 " + t + ".hi to i64\n  "
      po << t + ".oa = add i64 " + t + ".ob, " + t + ".i8\n  "
      po << t + ".op = inttoptr i64 " + t + ".oa to ptr\n  "
      po << "store i64 " + t + ".lo, ptr " + t + ".op, align 8\n  "
      po << t + ".i2 = add i64 " + t + ".i, 1\n  "
      po << "br label %ano.head." + bid + "\n"
      po << "ano.exit." + bid + ":\n  "
      po << t + " = add i64 " + t + ".c, 0"
      return po.to_s()
    # 4x-unrolled adcs quad loop (ldp/stp paired, ~3 insns/limb vs 5 for
    # the old 1x form — the delta that separated the harness loop from
    # the C kernel's unrolled ladder). Flag audit: lsr/and/sub/cbz/cbnz
    # never touch flags, so the carry threads across quads, across the
    # loop back-edge, and into the 1x remainder untouched.
    asmt = "add x15, ${1:x}, ${2:x}, lsl #3\\0Aadd x13, ${3:x}, ${4:x}, lsl #3\\0Aadd x14, ${5:x}, ${6:x}, lsl #3\\0Amov x9, ${7:x}\\0Acmn xzr, xzr\\0Alsr x8, x9, #2\\0Aand x9, x9, #3\\0Acbz x8, 2f\\0A1:\\0Aldp x10, x11, \[x13], #16\\0Aldp x16, x17, \[x14], #16\\0Aadcs x12, x10, x16\\0Aadcs x16, x11, x17\\0Astp x12, x16, \[x15], #16\\0Aldp x10, x11, \[x13], #16\\0Aldp x16, x17, \[x14], #16\\0Aadcs x12, x10, x16\\0Aadcs x16, x11, x17\\0Astp x12, x16, \[x15], #16\\0Asub x8, x8, #1\\0Acbnz x8, 1b\\0A2:\\0Acbz x9, 4f\\0A3:\\0Aldr x10, \[x13], #8\\0Aldr x11, \[x14], #8\\0Aadcs x12, x10, x11\\0Astr x12, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 3b\\0A4:\\0Acset ${0:x}, cs"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{memory},~{cc}\"(i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :ooff) + ", i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :aoff) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :boff) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_sub_no
    # offset sub_n: out[oo..]=a[ao..]-b[bo..]; flag-threaded sbcs returns borrow.
    # 4x-unrolled quad loop mirroring asm_add_no's: ldp/sbcs/stp pairs with a
    # 1x remainder; lsr/and/sub/cbz/cbnz never touch flags, so the borrow
    # (carry-clear) threads across quads, the back-edge, and the remainder.
    # `subs xzr, xzr, xzr` seeds C=1 (no borrow). Non-arm64 targets get a
    # portable i128 borrow loop with identical semantics.
    t = wire_get(inst, :temp)
    if !arm64_target
      bid = t.slice(1, t.size() - 1)
      po = StringBuffer(1024)
      po << t + ".oo3 = shl i64 " + wire_get(inst, :ooff) + ", 3\n  "
      po << t + ".ob = add i64 " + wire_get(inst, :outp) + ", " + t + ".oo3\n  "
      po << t + ".ao3 = shl i64 " + wire_get(inst, :aoff) + ", 3\n  "
      po << t + ".ab = add i64 " + wire_get(inst, :ap) + ", " + t + ".ao3\n  "
      po << t + ".bo3 = shl i64 " + wire_get(inst, :boff) + ", 3\n  "
      po << t + ".bb = add i64 " + wire_get(inst, :bp) + ", " + t + ".bo3\n  "
      po << "br label %sno.pre." + bid + "\n"
      po << "sno.pre." + bid + ":\n  "
      po << "br label %sno.head." + bid + "\n"
      po << "sno.head." + bid + ":\n  "
      po << t + ".i = phi i64 \[ 0, %sno.pre." + bid + " ], \[ " + t + ".i2, %sno.body." + bid + " ]\n  "
      po << t + ".w = phi i64 \[ 0, %sno.pre." + bid + " ], \[ " + t + ".w2, %sno.body." + bid + " ]\n  "
      po << t + ".done = icmp sge i64 " + t + ".i, " + wire_get(inst, :n) + "\n  "
      po << "br i1 " + t + ".done, label %sno.exit." + bid + ", label %sno.body." + bid + "\n"
      po << "sno.body." + bid + ":\n  "
      po << t + ".i8 = shl i64 " + t + ".i, 3\n  "
      po << t + ".aa = add i64 " + t + ".ab, " + t + ".i8\n  "
      po << t + ".apt = inttoptr i64 " + t + ".aa to ptr\n  "
      po << t + ".av = load i64, ptr " + t + ".apt, align 8\n  "
      po << t + ".ba = add i64 " + t + ".bb, " + t + ".i8\n  "
      po << t + ".bpt = inttoptr i64 " + t + ".ba to ptr\n  "
      po << t + ".bv = load i64, ptr " + t + ".bpt, align 8\n  "
      po << t + ".az = zext i64 " + t + ".av to i128\n  "
      po << t + ".bz = zext i64 " + t + ".bv to i128\n  "
      po << t + ".wz = zext i64 " + t + ".w to i128\n  "
      po << t + ".d1 = sub i128 " + t + ".az, " + t + ".bz\n  "
      po << t + ".d2 = sub i128 " + t + ".d1, " + t + ".wz\n  "
      po << t + ".lo = trunc i128 " + t + ".d2 to i64\n  "
      po << t + ".hb = lshr i128 " + t + ".d2, 127\n  "
      po << t + ".w2 = trunc i128 " + t + ".hb to i64\n  "
      po << t + ".oa = add i64 " + t + ".ob, " + t + ".i8\n  "
      po << t + ".opt = inttoptr i64 " + t + ".oa to ptr\n  "
      po << "store i64 " + t + ".lo, ptr " + t + ".opt, align 8\n  "
      po << t + ".i2 = add i64 " + t + ".i, 1\n  "
      po << "br label %sno.head." + bid + "\n"
      po << "sno.exit." + bid + ":\n  "
      po << t + " = add i64 " + t + ".w, 0"
      return po.to_s()
    asmt = "add x15, ${1:x}, ${2:x}, lsl #3\\0Aadd x13, ${3:x}, ${4:x}, lsl #3\\0Aadd x14, ${5:x}, ${6:x}, lsl #3\\0Amov x9, ${7:x}\\0Asubs xzr, xzr, xzr\\0Alsr x8, x9, #2\\0Aand x9, x9, #3\\0Acbz x8, 2f\\0A1:\\0Aldp x10, x11, \[x13], #16\\0Aldp x16, x17, \[x14], #16\\0Asbcs x12, x10, x16\\0Asbcs x16, x11, x17\\0Astp x12, x16, \[x15], #16\\0Aldp x10, x11, \[x13], #16\\0Aldp x16, x17, \[x14], #16\\0Asbcs x12, x10, x16\\0Asbcs x16, x11, x17\\0Astp x12, x16, \[x15], #16\\0Asub x8, x8, #1\\0Acbnz x8, 1b\\0A2:\\0Acbz x9, 4f\\0A3:\\0Aldr x10, \[x13], #8\\0Aldr x11, \[x14], #8\\0Asbcs x12, x10, x11\\0Astr x12, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 3b\\0A4:\\0Acset ${0:x}, cc"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{memory},~{cc}\"(i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :ooff) + ", i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :aoff) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :boff) + ", i64 " + wire_get(inst, :n) + ")"
  # Fused UNEQUAL-length add: adcs over the shorter operand, then propagate
  # the carry across the longer operand's remaining limbs — one pass, one
  # call. This exists because a source-level tail loop over those remaining
  # limbs runs on the strided view-field path and measured 2.5x against C's
  # single propagate. ${1}=out ${2}=a(longer) ${3}=alen ${4}=b(shorter)
  # ${5}=blen; returns carry-out. `sub` is flag-neutral, so the carry
  # threads from the adcs loop through the propagate loop untouched.
  when :asm_add_uneq
    t = wire_get(inst, :temp)
    if !arm64_target
      bid = t.slice(1, t.size() - 1)
      po = StringBuffer(1400)
      po << t + ".op = inttoptr i64 " + wire_get(inst, :outp) + " to ptr\n  "
      po << t + ".apx = inttoptr i64 " + wire_get(inst, :ap) + " to ptr\n  "
      po << t + ".bpx = inttoptr i64 " + wire_get(inst, :bp) + " to ptr\n  "
      po << "br label %aue.h1." + bid + "\n"
      po << "aue.h1." + bid + ":\n  "
      po << t + ".i = phi i64 \[ 0, %" + wire_get(inst, :entry_label) + " ], \[ " + t + ".i2, %aue.b1." + bid + " ]\n  "
      po << t + ".c = phi i64 \[ 0, %" + wire_get(inst, :entry_label) + " ], \[ " + t + ".c2, %aue.b1." + bid + " ]\n  "
      po << t + ".d1 = icmp sge i64 " + t + ".i, " + wire_get(inst, :nb) + "\n  "
      po << "br i1 " + t + ".d1, label %aue.h2." + bid + ", label %aue.b1." + bid + "\n"
      po << "aue.b1." + bid + ":\n  "
      po << t + ".ag = getelementptr i64, ptr " + t + ".apx, i64 " + t + ".i\n  "
      po << t + ".av = load i64, ptr " + t + ".ag, align 8\n  "
      po << t + ".bg = getelementptr i64, ptr " + t + ".bpx, i64 " + t + ".i\n  "
      po << t + ".bv = load i64, ptr " + t + ".bg, align 8\n  "
      po << t + ".az = zext i64 " + t + ".av to i128\n  "
      po << t + ".bz = zext i64 " + t + ".bv to i128\n  "
      po << t + ".cz = zext i64 " + t + ".c to i128\n  "
      po << t + ".s1 = add i128 " + t + ".az, " + t + ".bz\n  "
      po << t + ".s2 = add i128 " + t + ".s1, " + t + ".cz\n  "
      po << t + ".lo = trunc i128 " + t + ".s2 to i64\n  "
      po << t + ".hi = lshr i128 " + t + ".s2, 64\n  "
      po << t + ".c2 = trunc i128 " + t + ".hi to i64\n  "
      po << t + ".og = getelementptr i64, ptr " + t + ".op, i64 " + t + ".i\n  "
      po << "store i64 " + t + ".lo, ptr " + t + ".og, align 8\n  "
      po << t + ".i2 = add i64 " + t + ".i, 1\n  "
      po << "br label %aue.h1." + bid + "\n"
      po << "aue.h2." + bid + ":\n  "
      po << t + ".j = phi i64 \[ " + t + ".i, %aue.h1." + bid + " ], \[ " + t + ".j2, %aue.b2." + bid + " ]\n  "
      po << t + ".tc = phi i64 \[ " + t + ".c, %aue.h1." + bid + " ], \[ " + t + ".tc2, %aue.b2." + bid + " ]\n  "
      po << t + ".d2 = icmp sge i64 " + t + ".j, " + wire_get(inst, :na) + "\n  "
      po << "br i1 " + t + ".d2, label %aue.x." + bid + ", label %aue.b2." + bid + "\n"
      po << "aue.b2." + bid + ":\n  "
      po << t + ".tag = getelementptr i64, ptr " + t + ".apx, i64 " + t + ".j\n  "
      po << t + ".tav = load i64, ptr " + t + ".tag, align 8\n  "
      po << t + ".ts = add i64 " + t + ".tav, " + t + ".tc\n  "
      po << t + ".tov = icmp ult i64 " + t + ".ts, " + t + ".tav\n  "
      po << t + ".tc2 = zext i1 " + t + ".tov to i64\n  "
      po << t + ".tog = getelementptr i64, ptr " + t + ".op, i64 " + t + ".j\n  "
      po << "store i64 " + t + ".ts, ptr " + t + ".tog, align 8\n  "
      po << t + ".j2 = add i64 " + t + ".j, 1\n  "
      po << "br label %aue.h2." + bid + "\n"
      po << "aue.x." + bid + ":\n  "
      po << t + " = add i64 " + t + ".tc, 0"
      return po.to_s()
    asmt = "mov x15, ${1:x}\\0Amov x13, ${2:x}\\0Amov x14, ${4:x}\\0Amov x9, ${5:x}\\0Amov x8, ${3:x}\\0Asub x8, x8, x9\\0Acmn xzr, xzr\\0Acbz x9, 2f\\0A1:\\0Aldr x10, \[x13], #8\\0Aldr x11, \[x14], #8\\0Aadcs x12, x10, x11\\0Astr x12, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0A2:\\0Acbz x8, 3f\\0A4:\\0Aldr x10, \[x13], #8\\0Aadcs x12, x10, xzr\\0Astr x12, \[x15], #8\\0Asub x8, x8, #1\\0Acbz x8, 3f\\0Ab.cc 5f\\0Ab 4b\\0A5:\\0Acmp x8, #4\\0Ab.lt 6f\\0Aldp x10, x11, \[x13], #16\\0Aldp x16, x17, \[x13], #16\\0Astp x10, x11, \[x15], #16\\0Astp x16, x17, \[x15], #16\\0Asub x8, x8, #4\\0Acbnz x8, 5b\\0Ab 7f\\0A6:\\0Aldr x10, \[x13], #8\\0Astr x10, \[x15], #8\\0Asub x8, x8, #1\\0Acbnz x8, 6b\\0A7:\\0Amov ${0:x}, #0\\0Ab 8f\\0A3:\\0Acset ${0:x}, cs\\0A8:"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{memory},~{cc}\"(i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :na) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :nb) + ")"

  # Fused UNEQUAL-length subtract: sbcs over the shorter operand, then
  # propagate the borrow across the longer operand's remaining limbs.
  # `subs xzr, xzr, xzr` seeds C=1 (no borrow).
  when :asm_sub_uneq
    t = wire_get(inst, :temp)
    if !arm64_target
      bid = t.slice(1, t.size() - 1)
      po = StringBuffer(1400)
      po << t + ".op = inttoptr i64 " + wire_get(inst, :outp) + " to ptr\n  "
      po << t + ".apx = inttoptr i64 " + wire_get(inst, :ap) + " to ptr\n  "
      po << t + ".bpx = inttoptr i64 " + wire_get(inst, :bp) + " to ptr\n  "
      po << "br label %sue.h1." + bid + "\n"
      po << "sue.h1." + bid + ":\n  "
      po << t + ".i = phi i64 \[ 0, %" + wire_get(inst, :entry_label) + " ], \[ " + t + ".i2, %sue.b1." + bid + " ]\n  "
      po << t + ".w = phi i64 \[ 0, %" + wire_get(inst, :entry_label) + " ], \[ " + t + ".w2, %sue.b1." + bid + " ]\n  "
      po << t + ".d1 = icmp sge i64 " + t + ".i, " + wire_get(inst, :nb) + "\n  "
      po << "br i1 " + t + ".d1, label %sue.h2." + bid + ", label %sue.b1." + bid + "\n"
      po << "sue.b1." + bid + ":\n  "
      po << t + ".ag = getelementptr i64, ptr " + t + ".apx, i64 " + t + ".i\n  "
      po << t + ".av = load i64, ptr " + t + ".ag, align 8\n  "
      po << t + ".bg = getelementptr i64, ptr " + t + ".bpx, i64 " + t + ".i\n  "
      po << t + ".bv = load i64, ptr " + t + ".bg, align 8\n  "
      po << t + ".az = zext i64 " + t + ".av to i128\n  "
      po << t + ".bz = zext i64 " + t + ".bv to i128\n  "
      po << t + ".wz = zext i64 " + t + ".w to i128\n  "
      po << t + ".s1 = sub i128 " + t + ".az, " + t + ".bz\n  "
      po << t + ".s2 = sub i128 " + t + ".s1, " + t + ".wz\n  "
      po << t + ".lo = trunc i128 " + t + ".s2 to i64\n  "
      po << t + ".hb = lshr i128 " + t + ".s2, 127\n  "
      po << t + ".w2 = trunc i128 " + t + ".hb to i64\n  "
      po << t + ".og = getelementptr i64, ptr " + t + ".op, i64 " + t + ".i\n  "
      po << "store i64 " + t + ".lo, ptr " + t + ".og, align 8\n  "
      po << t + ".i2 = add i64 " + t + ".i, 1\n  "
      po << "br label %sue.h1." + bid + "\n"
      po << "sue.h2." + bid + ":\n  "
      po << t + ".j = phi i64 \[ " + t + ".i, %sue.h1." + bid + " ], \[ " + t + ".j2, %sue.b2." + bid + " ]\n  "
      po << t + ".tw = phi i64 \[ " + t + ".w, %sue.h1." + bid + " ], \[ " + t + ".tw2, %sue.b2." + bid + " ]\n  "
      po << t + ".d2 = icmp sge i64 " + t + ".j, " + wire_get(inst, :na) + "\n  "
      po << "br i1 " + t + ".d2, label %sue.x." + bid + ", label %sue.b2." + bid + "\n"
      po << "sue.b2." + bid + ":\n  "
      po << t + ".tag = getelementptr i64, ptr " + t + ".apx, i64 " + t + ".j\n  "
      po << t + ".tav = load i64, ptr " + t + ".tag, align 8\n  "
      po << t + ".ts = sub i64 " + t + ".tav, " + t + ".tw\n  "
      po << t + ".tov = icmp ult i64 " + t + ".tav, " + t + ".tw\n  "
      po << t + ".tw2 = zext i1 " + t + ".tov to i64\n  "
      po << t + ".tog = getelementptr i64, ptr " + t + ".op, i64 " + t + ".j\n  "
      po << "store i64 " + t + ".ts, ptr " + t + ".tog, align 8\n  "
      po << t + ".j2 = add i64 " + t + ".j, 1\n  "
      po << "br label %sue.h2." + bid + "\n"
      po << "sue.x." + bid + ":\n  "
      po << t + " = add i64 " + t + ".tw, 0"
      return po.to_s()
    asmt = "mov x15, ${1:x}\\0Amov x13, ${2:x}\\0Amov x14, ${4:x}\\0Amov x9, ${5:x}\\0Amov x8, ${3:x}\\0Asub x8, x8, x9\\0Asubs xzr, xzr, xzr\\0Acbz x9, 2f\\0A1:\\0Aldr x10, \[x13], #8\\0Aldr x11, \[x14], #8\\0Asbcs x12, x10, x11\\0Astr x12, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0A2:\\0Acbz x8, 3f\\0A4:\\0Aldr x10, \[x13], #8\\0Asbcs x12, x10, xzr\\0Astr x12, \[x15], #8\\0Asub x8, x8, #1\\0Acbz x8, 3f\\0Ab.cs 5f\\0Ab 4b\\0A5:\\0Acmp x8, #4\\0Ab.lt 6f\\0Aldp x10, x11, \[x13], #16\\0Aldp x16, x17, \[x13], #16\\0Astp x10, x11, \[x15], #16\\0Astp x16, x17, \[x15], #16\\0Asub x8, x8, #4\\0Acbnz x8, 5b\\0Ab 7f\\0A6:\\0Aldr x10, \[x13], #8\\0Astr x10, \[x15], #8\\0Asub x8, x8, #1\\0Acbnz x8, 6b\\0A7:\\0Amov ${0:x}, #0\\0Ab 8f\\0A3:\\0Acset ${0:x}, cc\\0A8:"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{memory},~{cc}\"(i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :na) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :nb) + ")"

  when :asm_addmul1
    # offset addmul_1: out[oo..] += a[ao..]*bsc; returns carry.
    # x14=out ptr, x13=a ptr, x3=bsc, x9=n, x15=carry.
    t = wire_get(inst, :temp)
    if !arm64_target
      bid = t.slice(1, t.size() - 1)
      po = StringBuffer(1200)
      po << t + ".oo3 = shl i64 " + wire_get(inst, :ooff) + ", 3\n  "
      po << t + ".ob = add i64 " + wire_get(inst, :outp) + ", " + t + ".oo3\n  "
      po << t + ".ao3 = shl i64 " + wire_get(inst, :aoff) + ", 3\n  "
      po << t + ".ab = add i64 " + wire_get(inst, :ap) + ", " + t + ".ao3\n  "
      po << t + ".op = inttoptr i64 " + t + ".ob to ptr\n  "
      po << t + ".apx = inttoptr i64 " + t + ".ab to ptr\n  "
      po << "br label %am1.pre." + bid + "\n"
      po << "am1.pre." + bid + ":\n  "
      po << "br label %am1.head." + bid + "\n"
      po << "am1.head." + bid + ":\n  "
      po << t + ".i = phi i64 \[ 0, %am1.pre." + bid + " ], \[ " + t + ".i2, %am1.body." + bid + " ]\n  "
      po << t + ".c = phi i64 \[ 0, %am1.pre." + bid + " ], \[ " + t + ".c2, %am1.body." + bid + " ]\n  "
      po << t + ".done = icmp sge i64 " + t + ".i, " + wire_get(inst, :n) + "\n  "
      po << "br i1 " + t + ".done, label %am1.exit." + bid + ", label %am1.body." + bid + "\n"
      po << "am1.body." + bid + ":\n  "
      po << t + ".ag = getelementptr i64, ptr " + t + ".apx, i64 " + t + ".i\n  "
      po << t + ".av = load i64, ptr " + t + ".ag, align 8\n  "
      po << t + ".og = getelementptr i64, ptr " + t + ".op, i64 " + t + ".i\n  "
      po << t + ".ov = load i64, ptr " + t + ".og, align 8\n  "
      po << t + ".az = zext i64 " + t + ".av to i128\n  "
      po << t + ".bz = zext i64 " + wire_get(inst, :bsc) + " to i128\n  "
      po << t + ".oz = zext i64 " + t + ".ov to i128\n  "
      po << t + ".cz = zext i64 " + t + ".c to i128\n  "
      po << t + ".prod = mul i128 " + t + ".az, " + t + ".bz\n  "
      po << t + ".sum1 = add i128 " + t + ".prod, " + t + ".oz\n  "
      po << t + ".sum2 = add i128 " + t + ".sum1, " + t + ".cz\n  "
      po << t + ".lo = trunc i128 " + t + ".sum2 to i64\n  "
      po << t + ".hi = lshr i128 " + t + ".sum2, 64\n  "
      po << t + ".c2 = trunc i128 " + t + ".hi to i64\n  "
      po << "store i64 " + t + ".lo, ptr " + t + ".og, align 8\n  "
      po << t + ".i2 = add i64 " + t + ".i, 1\n  "
      po << "br label %am1.head." + bid + "\n"
      po << "am1.exit." + bid + ":\n  "
      po << t + " = add i64 " + t + ".c, 0"
      return po.to_s()
    asmt = "add x14, ${1:x}, ${2:x}, lsl #3\\0Aadd x13, ${3:x}, ${4:x}, lsl #3\\0Amov x3, ${5:x}\\0Amov x9, ${6:x}\\0Amov x15, #0\\0A1:\\0Aldr x4, \[x13], #8\\0Amul x8, x4, x3\\0Aumulh x12, x4, x3\\0Aadds x8, x8, x15\\0Aadc x12, x12, xzr\\0Aldr x5, \[x14]\\0Aadds x8, x5, x8\\0Aadc x15, x12, xzr\\0Astr x8, \[x14], #8\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, x15"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,r,~{x3},~{x4},~{x5},~{x8},~{x9},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}\"(i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :ooff) + ", i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :aoff) + ", i64 " + wire_get(inst, :bsc) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_mulbase
    # Schoolbook multiplication as ONE asm block: out[oo..oo+na+nb) = a[ao..]*b[bo..].
    # row 0 = mul_1, rows 1..na-1 = addmul_1. One call/basecase (no per-row spill).
    # x16=out base, x17=a ptr, x7=b base; inner: x2=b ptr,x4=out ptr,x5=nb,x15=carry.
    t = wire_get(inst, :temp)
    if !arm64_target
      bid = t.slice(1, t.size() - 1)
      po = StringBuffer(2400)
      po << t + ".oo3 = shl i64 " + wire_get(inst, :ooff) + ", 3\n  "
      po << t + ".ob = add i64 " + wire_get(inst, :outp) + ", " + t + ".oo3\n  "
      po << t + ".ao3 = shl i64 " + wire_get(inst, :aoff) + ", 3\n  "
      po << t + ".ab = add i64 " + wire_get(inst, :ap) + ", " + t + ".ao3\n  "
      po << t + ".bo3 = shl i64 " + wire_get(inst, :boff) + ", 3\n  "
      po << t + ".bb = add i64 " + wire_get(inst, :bp) + ", " + t + ".bo3\n  "
      po << t + ".op = inttoptr i64 " + t + ".ob to ptr\n  "
      po << t + ".apx = inttoptr i64 " + t + ".ab to ptr\n  "
      po << t + ".bpx = inttoptr i64 " + t + ".bb to ptr\n  "
      po << t + ".total = add i64 " + wire_get(inst, :na) + ", " + wire_get(inst, :nb) + "\n  "
      po << "br label %mb.zero.pre." + bid + "\n"
      po << "mb.zero.pre." + bid + ":\n  "
      po << "br label %mb.zero.head." + bid + "\n"
      po << "mb.zero.head." + bid + ":\n  "
      po << t + ".zi = phi i64 \[ 0, %mb.zero.pre." + bid + " ], \[ " + t + ".zi2, %mb.zero.body." + bid + " ]\n  "
      po << t + ".zdone = icmp sge i64 " + t + ".zi, " + t + ".total\n  "
      po << "br i1 " + t + ".zdone, label %mb.outer.pre." + bid + ", label %mb.zero.body." + bid + "\n"
      po << "mb.zero.body." + bid + ":\n  "
      po << t + ".zg = getelementptr i64, ptr " + t + ".op, i64 " + t + ".zi\n  "
      po << "store i64 0, ptr " + t + ".zg, align 8\n  "
      po << t + ".zi2 = add i64 " + t + ".zi, 1\n  "
      po << "br label %mb.zero.head." + bid + "\n"
      po << "mb.outer.pre." + bid + ":\n  "
      po << "br label %mb.outer.head." + bid + "\n"
      po << "mb.outer.head." + bid + ":\n  "
      po << t + ".i = phi i64 \[ 0, %mb.outer.pre." + bid + " ], \[ " + t + ".i2, %mb.row.done." + bid + " ]\n  "
      po << t + ".odone = icmp sge i64 " + t + ".i, " + wire_get(inst, :na) + "\n  "
      po << "br i1 " + t + ".odone, label %mb.exit." + bid + ", label %mb.row.pre." + bid + "\n"
      po << "mb.row.pre." + bid + ":\n  "
      po << t + ".ag = getelementptr i64, ptr " + t + ".apx, i64 " + t + ".i\n  "
      po << t + ".av = load i64, ptr " + t + ".ag, align 8\n  "
      po << t + ".az = zext i64 " + t + ".av to i128\n  "
      po << "br label %mb.inner.head." + bid + "\n"
      po << "mb.inner.head." + bid + ":\n  "
      po << t + ".j = phi i64 \[ 0, %mb.row.pre." + bid + " ], \[ " + t + ".j2, %mb.inner.body." + bid + " ]\n  "
      po << t + ".c = phi i64 \[ 0, %mb.row.pre." + bid + " ], \[ " + t + ".c2, %mb.inner.body." + bid + " ]\n  "
      po << t + ".idone = icmp sge i64 " + t + ".j, " + wire_get(inst, :nb) + "\n  "
      po << "br i1 " + t + ".idone, label %mb.row.done." + bid + ", label %mb.inner.body." + bid + "\n"
      po << "mb.inner.body." + bid + ":\n  "
      po << t + ".bg = getelementptr i64, ptr " + t + ".bpx, i64 " + t + ".j\n  "
      po << t + ".bv = load i64, ptr " + t + ".bg, align 8\n  "
      po << t + ".oi = add i64 " + t + ".i, " + t + ".j\n  "
      po << t + ".og = getelementptr i64, ptr " + t + ".op, i64 " + t + ".oi\n  "
      po << t + ".ov = load i64, ptr " + t + ".og, align 8\n  "
      po << t + ".bz = zext i64 " + t + ".bv to i128\n  "
      po << t + ".oz = zext i64 " + t + ".ov to i128\n  "
      po << t + ".cz = zext i64 " + t + ".c to i128\n  "
      po << t + ".prod = mul i128 " + t + ".az, " + t + ".bz\n  "
      po << t + ".sum1 = add i128 " + t + ".prod, " + t + ".oz\n  "
      po << t + ".sum2 = add i128 " + t + ".sum1, " + t + ".cz\n  "
      po << t + ".lo = trunc i128 " + t + ".sum2 to i64\n  "
      po << t + ".hi = lshr i128 " + t + ".sum2, 64\n  "
      po << t + ".c2 = trunc i128 " + t + ".hi to i64\n  "
      po << "store i64 " + t + ".lo, ptr " + t + ".og, align 8\n  "
      po << t + ".j2 = add i64 " + t + ".j, 1\n  "
      po << "br label %mb.inner.head." + bid + "\n"
      po << "mb.row.done." + bid + ":\n  "
      po << t + ".ci = add i64 " + t + ".i, " + wire_get(inst, :nb) + "\n  "
      po << t + ".cg = getelementptr i64, ptr " + t + ".op, i64 " + t + ".ci\n  "
      po << "store i64 " + t + ".c, ptr " + t + ".cg, align 8\n  "
      po << t + ".i2 = add i64 " + t + ".i, 1\n  "
      po << "br label %mb.outer.head." + bid + "\n"
      po << "mb.exit." + bid + ":\n  "
      po << t + " = add i64 0, 0"
      return po.to_s()
    asmt = "add x16, ${1:x}, ${2:x}, lsl #3\\0Aadd x17, ${3:x}, ${4:x}, lsl #3\\0Aadd x7, ${5:x}, ${6:x}, lsl #3\\0Aldr x6, \[x17], #8\\0Amov x2, x7\\0Amov x4, x16\\0Amov x5, ${8:x}\\0Amov x15, #0\\0A1:\\0Aldr x10, \[x2], #8\\0Amul x8, x10, x6\\0Aumulh x12, x10, x6\\0Aadds x8, x8, x15\\0Aadc x15, x12, xzr\\0Astr x8, \[x4], #8\\0Asubs x5, x5, #1\\0Abne 1b\\0Astr x15, \[x4]\\0Asubs x3, ${7:x}, #1\\0Amov x14, x16\\0A2:\\0Acbz x3, 3f\\0Aadd x14, x14, #8\\0Aldr x6, \[x17], #8\\0Amov x2, x7\\0Amov x4, x14\\0Amov x5, ${8:x}\\0Amov x15, #0\\0A4:\\0Aldr x10, \[x2], #8\\0Amul x8, x10, x6\\0Aumulh x12, x10, x6\\0Aadds x8, x8, x15\\0Aadc x12, x12, xzr\\0Aldr x9, \[x4]\\0Aadds x8, x9, x8\\0Aadc x15, x12, xzr\\0Astr x8, \[x4], #8\\0Asubs x5, x5, #1\\0Abne 4b\\0Astr x15, \[x4]\\0Asub x3, x3, #1\\0Ab 2b\\0A3:\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,r,r,r,~{x2},~{x3},~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x12},~{x14},~{x15},~{x16},~{x17},~{memory},~{cc}\"(i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :ooff) + ", i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :aoff) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :boff) + ", i64 " + wire_get(inst, :na) + ", i64 " + wire_get(inst, :nb) + ")"
  when :sdiv_i128
    wire_get(inst, :temp) + " = sdiv i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :udiv_i128
    wire_get(inst, :temp) + " = udiv i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :srem_i128
    wire_get(inst, :temp) + " = srem i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :urem_i128
    wire_get(inst, :temp) + " = urem i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)

  # Checked i48 arithmetic with overflow branch to bigint
  when :add_i48_checked, :sub_i48_checked
    intrinsic = "llvm.sadd.with.overflow.i64"
    if op == :sub_i48_checked
      intrinsic = "llvm.ssub.with.overflow.i64"
    bid = wire_get(inst, :block_id).to_s()
    t = wire_get(inst, :temp)
    pair = t + ".pair"
    raw = t + ".raw"
    i64ovf = t + ".i64ovf"
    over = t + ".over"
    under = t + ".under"
    rovf = t + ".rovf"
    ovf = t + ".ovf"
    masked = t + ".masked"
    boxed = t + ".fast"
    slow = t + ".slow"
    out = StringBuffer(384)
    out << pair + " = call {i64, i1} @" + intrinsic + "(i64 " + wire_get(inst, :lhs) + ", i64 " + wire_get(inst, :rhs) + ")\n  "
    out << raw + " = extractvalue {i64, i1} " + pair + ", 0\n  "
    out << i64ovf + " = extractvalue {i64, i1} " + pair + ", 1\n  "
    out << over + " = icmp sgt i64 " + raw + ", 140737488355327\n  "
    out << under + " = icmp slt i64 " + raw + ", -140737488355328\n  "
    out << rovf + " = or i1 " + over + ", " + under + "\n  "
    out << ovf + " = or i1 " + i64ovf + ", " + rovf + "\n  "
    out << "br i1 " + ovf + ", label %ovf.slow." + bid + ", label %ovf.fast." + bid + ", !prof !31412\n"
    out << "ovf.fast." + bid + ":\n  "
    out << masked + " = and i64 " + raw + ", 281474976710655\n  "
    out << boxed + " = or i64 " + masked + ", -1688849860263936\n  "
    out << "br label %ovf.merge." + bid + "\n"
    out << "ovf.slow." + bid + ":\n  "
    out << slow + " = call i64 @" + wire_get(inst, :rt_fallback) + "(i64 " + wire_get(inst, :lhs_boxed) + ", i64 " + wire_get(inst, :rhs_boxed) + ")\n  "
    out << "br label %ovf.merge." + bid + "\n"
    out << "ovf.merge." + bid + ":\n  "
    out << t + " = phi i64 \[" + boxed + ", %ovf.fast." + bid + "], \[" + slow + ", %ovf.slow." + bid + "]"
    out.to_s()

  when :mul_i48_checked
    bid = wire_get(inst, :block_id).to_s()
    t = wire_get(inst, :temp)
    pair = t + ".pair"
    raw = t + ".raw"
    i64ovf = t + ".i64ovf"
    over = t + ".over"
    under = t + ".under"
    rovf = t + ".rovf"
    ovf = t + ".ovf"
    masked = t + ".masked"
    boxed = t + ".fast"
    slow = t + ".slow"
    out = StringBuffer(384)
    out << pair + " = call {i64, i1} @llvm.smul.with.overflow.i64(i64 " + wire_get(inst, :lhs) + ", i64 " + wire_get(inst, :rhs) + ")\n  "
    out << raw + " = extractvalue {i64, i1} " + pair + ", 0\n  "
    out << i64ovf + " = extractvalue {i64, i1} " + pair + ", 1\n  "
    out << over + " = icmp sgt i64 " + raw + ", 140737488355327\n  "
    out << under + " = icmp slt i64 " + raw + ", -140737488355328\n  "
    out << rovf + " = or i1 " + over + ", " + under + "\n  "
    out << ovf + " = or i1 " + i64ovf + ", " + rovf + "\n  "
    out << "br i1 " + ovf + ", label %ovf.slow." + bid + ", label %ovf.fast." + bid + ", !prof !31412\n"
    out << "ovf.fast." + bid + ":\n  "
    out << masked + " = and i64 " + raw + ", 281474976710655\n  "
    out << boxed + " = or i64 " + masked + ", -1688849860263936\n  "
    out << "br label %ovf.merge." + bid + "\n"
    out << "ovf.slow." + bid + ":\n  "
    out << slow + " = call i64 @" + wire_get(inst, :rt_fallback) + "(i64 " + wire_get(inst, :lhs_boxed) + ", i64 " + wire_get(inst, :rhs_boxed) + ")\n  "
    out << "br label %ovf.merge." + bid + "\n"
    out << "ovf.merge." + bid + ":\n  "
    out << t + " = phi i64 \[" + boxed + ", %ovf.fast." + bid + "], \[" + slow + ", %ovf.slow." + bid + "]"
    out.to_s()

  # Guarded i48 arithmetic: inline fast path for boxed ints, runtime fallback otherwise.
  when :add_i48_guarded, :sub_i48_guarded, :mul_i48_guarded
    render_guarded_i48(inst)

  # Bitwise
  when :and_i64
    wire_get(inst, :temp) + " = and i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :or_i64
    wire_get(inst, :temp) + " = or i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :xor_i64
    wire_get(inst, :temp) + " = xor i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :shl_i64
    wire_get(inst, :temp) + " = shl i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :ashr_i64
    wire_get(inst, :temp) + " = ashr i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :lshr_i64
    wire_get(inst, :temp) + " = lshr i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :and_i128
    wire_get(inst, :temp) + " = and i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :or_i128
    wire_get(inst, :temp) + " = or i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :xor_i128
    wire_get(inst, :temp) + " = xor i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :shl_i128
    wire_get(inst, :temp) + " = shl i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :ashr_i128
    wire_get(inst, :temp) + " = ashr i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :lshr_i128
    if wire_get(inst, :lhs) != nil
      wire_get(inst, :temp) + " = lshr i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
    elsif wire_get(inst, :shift) != nil
      wire_get(inst, :temp) + " = lshr i128 " + wire_get(inst, :value) + ", " + wire_get(inst, :shift).to_s()
    else
      "; UNKNOWN WIRE OP: " + op.to_s()

  # Comparison
  when :icmp_i64
    wire_get(inst, :temp) + " = icmp " + wire_get(inst, :pred) + " i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :truthy_inline
    wire_get(inst, :temp) + " = icmp ugt i64 " + wire_get(inst, :value) + ", 1"
  when :icmp_ne_zero
    wire_get(inst, :temp) + " = icmp ne i64 " + wire_get(inst, :value) + ", 0"
  when :icmp_ne_i64
    wire_get(inst, :temp) + " = icmp ne i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :icmp_i128
    wire_get(inst, :temp) + " = icmp " + wire_get(inst, :pred) + " i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)

  # Boolean
  when :and_i1
    wire_get(inst, :temp) + " = and i1 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :or_i1
    wire_get(inst, :temp) + " = or i1 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :not_i1
    wire_get(inst, :temp) + " = xor i1 " + wire_get(inst, :value) + ", true"

  # Cast
  when :zext_i1_i64
    wire_get(inst, :temp) + " = zext i1 " + wire_get(inst, :value) + " to i64"
  when :trunc_i64_i32
    wire_get(inst, :temp) + " = trunc i64 " + wire_get(inst, :value) + " to i32"
  when :sext_i64_i128
    wire_get(inst, :temp) + " = sext i64 " + wire_get(inst, :value) + " to i128"
  when :zext_i32_i64
    wire_get(inst, :temp) + " = zext i32 " + wire_get(inst, :value) + " to i64"
  when :select_i64
    wire_get(inst, :temp) + " = select i1 " + wire_get(inst, :cond) + ", i64 " + wire_get(inst, :then_val) + ", i64 " + wire_get(inst, :else_val)

  # NaN-boxing
  when :nanbox_int
    raw_str = wire_get(inst, :raw).to_s()
    ch = raw_str.slice(0, 1)
    if ch != nil && (ch == "-" || (ch >= "0" && ch <= "9"))
      wval = (raw_str.to_i() & 281474976710655) | -1688849860263936
      lit = llvm_wvalue_literal(wval)
      wire_get(inst, :temp_masked) + " = or i64 0, " + lit + "\n  " + wire_get(inst, :temp) + " = or i64 0, " + lit
    else
      wire_get(inst, :temp_masked) + " = and i64 " + raw_str + ", " + machine_i64_text(w_payload_mask) + "\n  " + wire_get(inst, :temp) + " = or i64 " + wire_get(inst, :temp_masked) + ", " + machine_i64_text(w_tag_int)
  when :nanunbox_int
    wire_get(inst, :temp_shl) + " = shl i64 " + wire_get(inst, :boxed) + ", 16\n  " + wire_get(inst, :temp) + " = ashr i64 " + wire_get(inst, :temp_shl) + ", 16"
  when :nanbox_bool
    wire_get(inst, :temp) + " = select i1 " + wire_get(inst, :value) + ", i64 " + w_true.to_s() + ", i64 " + w_false.to_s()
  when :nanunbox_float
    wire_get(inst, :temp_bits) + " = sub i64 " + wire_get(inst, :boxed) + ", " + machine_i64_text(w_double_bias) + "\n  " + wire_get(inst, :temp) + " = bitcast i64 " + wire_get(inst, :temp_bits) + " to double"
  when :nanbox_float
    wire_get(inst, :temp_bits) + " = bitcast double " + wire_get(inst, :raw) + " to i64\n  " + wire_get(inst, :temp) + " = add i64 " + wire_get(inst, :temp_bits) + ", " + machine_i64_text(w_double_bias)

  # Raw float value plumbing
  when :fpext_f32_f64
    wire_get(inst, :temp) + " = fpext float " + wire_get(inst, :value) + " to double"
  when :fptrunc_f64_f32
    wire_get(inst, :temp) + " = fptrunc double " + wire_get(inst, :value) + " to float"
  when :fptosi_f64_i64
    wire_get(inst, :temp) + " = fptosi double " + wire_get(inst, :value) + " to i64"
  when :fptoui_f64_i64
    wire_get(inst, :temp) + " = fptoui double " + wire_get(inst, :value) + " to i64"
  when :fptosi_f64_i128
    wire_get(inst, :temp) + " = fptosi double " + wire_get(inst, :value) + " to i128"
  when :fptoui_f64_i128
    wire_get(inst, :temp) + " = fptoui double " + wire_get(inst, :value) + " to i128"
  when :bitcast_i64_f64
    wire_get(inst, :temp) + " = bitcast i64 " + wire_get(inst, :value) + " to double"
  when :bitcast_f64_i64
    wire_get(inst, :temp) + " = bitcast double " + wire_get(inst, :value) + " to i64"
  when :bitcast_i32_f32
    wire_get(inst, :temp) + " = bitcast i32 " + wire_get(inst, :value) + " to float"
  when :bitcast_f32_i32
    wire_get(inst, :temp) + " = bitcast float " + wire_get(inst, :value) + " to i32"

  # IEEE-half (f16) element conversion. Storage is i16; arithmetic is f32.
  # fptrunc/fpext lower to single fcvt instructions on AArch64.
  when :fptrunc_f32_f16
    wire_get(inst, :temp) + " = fptrunc float " + wire_get(inst, :value) + " to half"
  when :fpext_f16_f32
    wire_get(inst, :temp) + " = fpext half " + wire_get(inst, :value) + " to float"
  when :bitcast_f16_i16
    wire_get(inst, :temp) + " = bitcast half " + wire_get(inst, :value) + " to i16"
  when :bitcast_i16_f16
    wire_get(inst, :temp) + " = bitcast i16 " + wire_get(inst, :value) + " to half"
  when :zext_i16_i64
    wire_get(inst, :temp) + " = zext i16 " + wire_get(inst, :value) + " to i64"
  when :trunc_i64_i16
    wire_get(inst, :temp) + " = trunc i64 " + wire_get(inst, :value) + " to i16"

  # Float arithmetic — wire_get(inst, :fp_flags) overrides the function-level default for
  # @fastmath / @strictmath block scopes; nil means use the function default.
  when :fadd_f64
    f = wire_get(inst, :fp_flags)
    f = fp_flags if f == nil
    wire_get(inst, :temp) + " = fadd " + f + "double " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :fsub_f64
    f = wire_get(inst, :fp_flags)
    f = fp_flags if f == nil
    wire_get(inst, :temp) + " = fsub " + f + "double " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :fmul_f64
    f = wire_get(inst, :fp_flags)
    f = fp_flags if f == nil
    wire_get(inst, :temp) + " = fmul " + f + "double " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :fdiv_f64
    f = wire_get(inst, :fp_flags)
    f = fp_flags if f == nil
    wire_get(inst, :temp) + " = fdiv " + f + "double " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :frem_f64
    wire_get(inst, :temp) + " = frem double " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)

  # FMA peephole: emitted by lowering/ops.w for a*b+c / a*b-c in precise mode.
  # This is the llvm.fmuladd intrinsic: "fuse if target supports it" — always
  # maps to a single hardware FMA on targets that have one (ARM, x86 AVX2+).
  # Operands ride on :lhs (a) / :rhs (b) / :value (c) — the three field names
  # already known to apply_subst (mem2reg) and content_hash. Using novel keys
  # would make the mul/add operands invisible to those operand-walkers, so a
  # promoted-away load would leave the fmuladd referencing a deleted temp.
  when :fmuladd_f64
    wire_get(inst, :temp) + " = call double @llvm.fmuladd.f64(double " + wire_get(inst, :lhs) + ", double " + wire_get(inst, :rhs) + ", double " + wire_get(inst, :value) + ")"
  # Explicit `fma(a,b,c)` — llvm.fma.f64 is ALWAYS a true fused multiply-add
  # (single rounding), unlike fmuladd's "contract if profitable". Same
  # lhs/rhs/value operand fields for mem2reg/content-hash safety.
  # Hardware population count on a raw i64 — single cnt/popcnt instruction.
  # Operand rides on :value (walked by apply_subst / content_hash).
  when :ctpop_i64
    wire_get(inst, :temp) + " = call i64 @llvm.ctpop.i64(i64 " + wire_get(inst, :value) + ")"
  when :fma_f64
    wire_get(inst, :temp) + " = call double @llvm.fma.f64(double " + wire_get(inst, :lhs) + ", double " + wire_get(inst, :rhs) + ", double " + wire_get(inst, :value) + ")"
  # Raw libm call — Math.* fast path on unboxed operands (lowering/
  # method_call.w). Unary rides on :value, binary (pow/atan2) on :lhs/:rhs —
  # all three field names are walked by apply_subst and content_hash, so
  # mem2reg promotion of the operand loads stays correct (see :fmuladd_f64).
  when :call_libm_f64
    if wire_get(inst, :value) != nil
      wire_get(inst, :temp) + " = call double @" + wire_get(inst, :name) + "(double " + wire_get(inst, :value) + ")"
    else
      wire_get(inst, :temp) + " = call double @" + wire_get(inst, :name) + "(double " + wire_get(inst, :lhs) + ", double " + wire_get(inst, :rhs) + ")"

  # Numeric->raw-double coercion of a boxed WValue (ensure_raw_f64 fallback):
  # takes an i64 WValue (boxed double / Decimal / Int), returns a raw double.
  # Routed through the alwaysinline helper so the boxed-double case (a :f64
  # param arriving as a WValue, nbody's `dt`) folds to sub+bitcast inline
  # instead of an out-of-line w_num_to_f64 call per use site.
  when :call_num_to_f64
    wire_get(inst, :temp) + " = call double @__w_num_to_f64_fast(i64 " + wire_get(inst, :value) + ")"

  # Fused-elementwise loop ops (lowering/ops.w try_fuse_elementwise). The
  # header decode is hoisted out of the fused loop deliberately: the loop
  # body the fuser emits contains no push/clear/realloc, so slots/start are
  # invariant for its duration — unlike typed_array_get_inline sites, which
  # must re-read them per access. Operands ride on :value/:ptr/:index only
  # (fields apply_subst and content_hash already walk).
  when :ta_f64_elems_ptr
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    parts = StringBuffer(420)
    parts << t + ".hdr = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".slp = getelementptr i8, ptr " + t + ".hp, i64 16\n  "
    parts << t + ".slots = load ptr, ptr " + t + ".slp, align 8" + tbaa_header_suffix() + "\n  "
    parts << t + ".stp = getelementptr i8, ptr " + t + ".hp, i64 4\n  "
    parts << t + ".st32 = load i32, ptr " + t + ".stp, align 4" + tbaa_header_suffix() + "\n  "
    parts << t + ".st = sext i32 " + t + ".st32 to i64\n  "
    parts << t + " = getelementptr double, ptr " + t + ".slots, i64 " + t + ".st"
    parts.to_s()
  when :ta_size_raw
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    parts = StringBuffer(240)
    parts << t + ".hdr = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".szp = getelementptr i8, ptr " + t + ".hp, i64 8\n  "
    parts << t + ".sz32 = load i32, ptr " + t + ".szp, align 4" + tbaa_header_suffix() + "\n  "
    parts << t + " = sext i32 " + t + ".sz32 to i64"
    parts.to_s()
  # `.size` for a statically-:array receiver. Unlike :ta_size_raw (typed
  # arrays — always real WArrays), a :array-typed var can hold a BODY-REF at
  # runtime: an AST child-list packed box (tag 0xFFFE, subtype 6) that quacks
  # like an array — e.g. `args = call_node.args` nil-defaulted with
  # `args = []` keeps the :array static type but carries the packed box. The
  # runtime's w_array_size handles that with a w_is_body check; dropping it
  # segfaulted stage 2 (load through 0xFFFEC…). The body length lives in the
  # box's low 21 bits, so both paths stay inline and call-free — the whole
  # diamond is pure and LICM-hoistable, preserving the fill-loop win.
  when :array_size_raw
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    lbl = "asz." + t.slice(1, t.size() - 1)
    parts = StringBuffer(480)
    parts << t + ".tg = lshr i64 " + v + ", 45\n  "
    parts << t + ".isb = icmp eq i64 " + t + ".tg, 524278\n  "
    parts << "br i1 " + t + ".isb, label %" + lbl + ".body, label %" + lbl + ".arr\n"
    parts << lbl + ".body:\n  "
    parts << t + ".bl = and i64 " + v + ", 2097151\n  "
    parts << "br label %" + lbl + ".done\n"
    parts << lbl + ".arr:\n  "
    parts << t + ".hdr = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".szp = getelementptr i8, ptr " + t + ".hp, i64 8\n  "
    parts << t + ".sz32 = load i32, ptr " + t + ".szp, align 4" + tbaa_header_suffix() + "\n  "
    parts << t + ".sz = sext i32 " + t + ".sz32 to i64\n  "
    parts << "br label %" + lbl + ".done\n"
    parts << lbl + ".done:\n  "
    parts << t + " = phi i64 \[" + t + ".bl, %" + lbl + ".body], \[" + t + ".sz, %" + lbl + ".arr]"
    parts.to_s()
  # Loop-versioning guard (lower_while_versioned): i1 = receiver is a live
  # polymorphic WArray — object space (high 16 bits zero, >= 16), heap
  # subtag 10, header ebits 65. Mirrors __w_array_get_i64_fast's entry
  # checks; the ebits load happens only behind the object-space branch, so
  # the whole test is safe on ANY WValue. Internal labels keep the phi's
  # predecessors self-contained (same trick as :array_size_raw).
  when :poly_array_guard
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    lbl = "pag." + t.slice(1, t.size() - 1)
    parts = StringBuffer(560)
    # v5: W_TAG_ARRAY (0xFFF4 = 65524) — the object-space + subtag pair
    # collapses to one tag compare; ebits load stays behind the branch.
    parts << t + ".hi = lshr i64 " + v + ", 48\n  "
    parts << t + ".o2 = icmp eq i64 " + t + ".hi, 65524\n  "
    parts << "br i1 " + t + ".o2, label %" + lbl + ".hdr, label %" + lbl + ".no\n"
    parts << lbl + ".no:\n  "
    parts << "br label %" + lbl + ".out\n"
    parts << lbl + ".hdr:\n  "
    parts << t + ".base = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".p = inttoptr i64 " + t + ".base to ptr\n  "
    parts << t + ".ebp = getelementptr i8, ptr " + t + ".p, i64 1\n  "
    parts << t + ".eb = load i8, ptr " + t + ".ebp, align 1" + invariant_load_suffix() + "\n  "
    parts << t + ".is65 = icmp eq i8 " + t + ".eb, 65\n  "
    parts << "br label %" + lbl + ".out\n"
    parts << lbl + ".out:\n  "
    parts << t + " = phi i1 \[false, %" + lbl + ".no], \[" + t + ".is65, %" + lbl + ".hdr]"
    parts.to_s()
  # WArray.cap (i32 header field at +12) — same shape/soundness as :ta_size_raw.
  when :ta_cap_raw
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    parts = StringBuffer(240)
    parts << t + ".hdr = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".cpp = getelementptr i8, ptr " + t + ".hp, i64 12\n  "
    parts << t + ".cp32 = load i32, ptr " + t + ".cpp, align 4" + tbaa_header_suffix() + "\n  "
    parts << t + " = sext i32 " + t + ".cp32 to i64"
    parts.to_s()
  # The *_at family carries warray_data TBAA (these are typed-array element
  # accesses) plus per-fusion-site scoped no-alias metadata when lowering
  # stamped ewscope (see ewscope_md_defs above).
  when :load_f64_at
    t = wire_get(inst, :temp)
    t + ".p = getelementptr double, ptr " + wire_get(inst, :ptr) + ", i64 " + wire_get(inst, :index) + "\n  " + t + " = load double, ptr " + t + ".p, align 8" + tbaa_elem_suffix() + ewscope_load_suffix(inst)
  when :store_f64_at
    t = wire_get(inst, :temp)
    t + " = getelementptr double, ptr " + wire_get(inst, :ptr) + ", i64 " + wire_get(inst, :index) + "\n  store double " + wire_get(inst, :value) + ", ptr " + t + ", align 8" + tbaa_elem_suffix() + ewscope_store_suffix(inst)
  # f32 variants: 4-byte stride, fpext on load / fptrunc on store so the
  # fused per-element computation stays in f64 (matching the CPU kernels,
  # which read f32 elements into doubles).
  when :load_f32_at
    t = wire_get(inst, :temp)
    t + ".p = getelementptr float, ptr " + wire_get(inst, :ptr) + ", i64 " + wire_get(inst, :index) + "\n  " + t + ".f32 = load float, ptr " + t + ".p, align 4" + tbaa_elem_suffix() + ewscope_load_suffix(inst) + "\n  " + t + " = fpext float " + t + ".f32 to double"
  when :store_f32_at
    t = wire_get(inst, :temp)
    t + ".tr = fptrunc double " + wire_get(inst, :value) + " to float\n  " + t + " = getelementptr float, ptr " + wire_get(inst, :ptr) + ", i64 " + wire_get(inst, :index) + "\n  store float " + t + ".tr, ptr " + t + ", align 4" + tbaa_elem_suffix() + ewscope_store_suffix(inst)
  when :load_i64_at
    t = wire_get(inst, :temp)
    t + ".p = getelementptr i64, ptr " + wire_get(inst, :ptr) + ", i64 " + wire_get(inst, :index) + "\n  " + t + " = load i64, ptr " + t + ".p, align 8" + tbaa_elem_suffix() + ewscope_load_suffix(inst)
  # Element-0 address of a typed array as a raw i64 — the arg block handed
  # to w_fused_parallel_run / w_fused_gpu_run. 8-byte stride (i64 blocks).
  when :ta_data_addr
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    parts = StringBuffer(400)
    parts << t + ".hdr = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".slp = getelementptr i8, ptr " + t + ".hp, i64 16\n  "
    parts << t + ".slots = load ptr, ptr " + t + ".slp, align 8" + tbaa_header_suffix() + "\n  "
    parts << t + ".stp = getelementptr i8, ptr " + t + ".hp, i64 4\n  "
    parts << t + ".st32 = load i32, ptr " + t + ".stp, align 4" + tbaa_header_suffix() + "\n  "
    parts << t + ".st = sext i32 " + t + ".st32 to i64\n  "
    parts << t + ".ep = getelementptr i64, ptr " + t + ".slots, i64 " + t + ".st\n  "
    parts << t + " = ptrtoint ptr " + t + ".ep to i64"
    parts.to_s()
  # f32 element-pointer decode (float stride) — sibling of :ta_f64_elems_ptr.
  when :ta_f32_elems_ptr
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    parts = StringBuffer(420)
    parts << t + ".hdr = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".slp = getelementptr i8, ptr " + t + ".hp, i64 16\n  "
    parts << t + ".slots = load ptr, ptr " + t + ".slp, align 8" + tbaa_header_suffix() + "\n  "
    parts << t + ".stp = getelementptr i8, ptr " + t + ".hp, i64 4\n  "
    parts << t + ".st32 = load i32, ptr " + t + ".stp, align 4" + tbaa_header_suffix() + "\n  "
    parts << t + ".st = sext i32 " + t + ".st32 to i64\n  "
    parts << t + " = getelementptr float, ptr " + t + ".slots, i64 " + t + ".st"
    parts.to_s()
  # Fixed-width integer sibling of the float element-pointer decoders. The
  # signedness lives on loads, not pointer arithmetic; :type is i8/i16/i32/i64.
  when :ta_int_elems_ptr
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    ty = wire_get(inst, :type)
    parts = StringBuffer(420)
    parts << t + ".hdr = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".slp = getelementptr i8, ptr " + t + ".hp, i64 16\n  "
    parts << t + ".slots = load ptr, ptr " + t + ".slp, align 8" + tbaa_header_suffix() + "\n  "
    parts << t + ".stp = getelementptr i8, ptr " + t + ".hp, i64 4\n  "
    parts << t + ".st32 = load i32, ptr " + t + ".stp, align 4" + tbaa_header_suffix() + "\n  "
    parts << t + ".st = sext i32 " + t + ".st32 to i64\n  "
    parts << t + " = getelementptr " + ty + ", ptr " + t + ".slots, i64 " + t + ".st"
    parts.to_s()
  when :load_int_at
    t = wire_get(inst, :temp)
    ty = wire_get(inst, :type)
    align = "8"
    if ty == "i8"
      align = "1"
    elsif ty == "i16"
      align = "2"
    elsif ty == "i32"
      align = "4"
    parts = StringBuffer(220)
    parts << t + ".p = getelementptr " + ty + ", ptr " + wire_get(inst, :ptr) + ", i64 " + wire_get(inst, :index) + "\n  "
    if ty == "i64"
      parts << t + " = load i64, ptr " + t + ".p, align " + align + tbaa_elem_suffix() + ewscope_load_suffix(inst)
    else
      parts << t + ".n = load " + ty + ", ptr " + t + ".p, align " + align + tbaa_elem_suffix() + ewscope_load_suffix(inst) + "\n  "
      ext = wire_get(inst, :kind) == :signed ? "sext" : "zext"
      parts << t + " = " + ext + " " + ty + " " + t + ".n to i64"
    parts.to_s()
  when :narrow_i64
    t = wire_get(inst, :temp)
    ty = wire_get(inst, :type)
    ext = wire_get(inst, :kind) == :signed ? "sext" : "zext"
    t + ".tr = trunc i64 " + wire_get(inst, :value) + " to " + ty + "\n  " + t + " = " + ext + " " + ty + " " + t + ".tr to i64"
  when :store_int_at
    t = wire_get(inst, :temp)
    ty = wire_get(inst, :type)
    align = "8"
    if ty == "i8"
      align = "1"
    elsif ty == "i16"
      align = "2"
    elsif ty == "i32"
      align = "4"
    parts = StringBuffer(220)
    stored = wire_get(inst, :value)
    if ty != "i64"
      parts << t + ".tr = trunc i64 " + stored + " to " + ty + "\n  "
      stored = t + ".tr"
    parts << t + " = getelementptr " + ty + ", ptr " + wire_get(inst, :ptr) + ", i64 " + wire_get(inst, :index) + "\n  "
    parts << "store " + ty + " " + stored + ", ptr " + t + ", align " + align + tbaa_elem_suffix() + ewscope_store_suffix(inst)
    parts.to_s()
  when :inttoptr_i64
    wire_get(inst, :temp) + " = inttoptr i64 " + wire_get(inst, :value) + " to ptr"
  # Address of a module function as raw i64 — passed to the runtime fused
  # partitioner, which calls it back as int64_t(*)(int64_t,int64_t,int64_t).
  when :fn_addr_i64
    wire_get(inst, :temp) + " = ptrtoint ptr @" + wire_get(inst, :name) + " to i64"
  when :fneg_f64
    wire_get(inst, :temp) + " = fneg double " + wire_get(inst, :value)

  # Float comparison — fp_flags only applies for fast mode (nnan changes predicate semantics)
  when :fcmp_f64
    f = wire_get(inst, :fp_flags)
    f = fp_flags if f == nil
    cmp_flags = f == "fast " ? "fast " : ""
    wire_get(inst, :temp) + " = fcmp " + cmp_flags + wire_get(inst, :pred) + " double " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)

  # i128 operations
  when :zext_i64_i128
    wire_get(inst, :temp) + " = zext i64 " + wire_get(inst, :value) + " to i128"
  when :trunc_i128_i64
    wire_get(inst, :temp) + " = trunc i128 " + wire_get(inst, :value) + " to i64"

  # Inline bool array get: load byte, add 1 -> W_FALSE(1) or W_TRUE(2)
  when :bool_array_get_byte_inline
    t = wire_get(inst, :temp)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    ap = t + ".ap"
    ap_p = t + ".app"
    dg = t + ".dg"
    dp = t + ".dp"
    ep = t + ".ep"
    byte = t + ".byte"
    ext = t + ".ext"
    out = StringBuffer(256)
    out << ap + " = and i64 " + arr + ", 140737488355312\n  "
    out << ap_p + " = inttoptr i64 " + ap + " to ptr\n  "
    out << dg + " = getelementptr i8, ptr " + ap_p + ", i64 8\n  "
    out << dp + " = load ptr, ptr " + dg + "\n  "
    out << ep + " = getelementptr i8, ptr " + dp + ", i64 " + idx + "\n  "
    out << byte + " = load i8, ptr " + ep + ", align 1, !range !{i8 0, i8 2}\n  "
    out << ext + " = zext i8 " + byte + " to i64\n  "
    out << t + " = add i64 " + ext + ", 1"
    out.to_s()

  # Inline bool array set: store (val - 1) as byte. W_TRUE(2)->1, W_FALSE(1)->0
  when :bool_array_set_byte_inline
    t = wire_get(inst, :temp)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    val = wire_get(inst, :val)
    ap = t + ".ap"
    ap_p = t + ".app"
    dg = t + ".dg"
    dp = t + ".dp"
    ep = t + ".ep"
    sub = t + ".sub"
    byte_val = t + ".bv"
    out = StringBuffer(256)
    out << ap + " = and i64 " + arr + ", 140737488355312\n  "
    out << ap_p + " = inttoptr i64 " + ap + " to ptr\n  "
    out << dg + " = getelementptr i8, ptr " + ap_p + ", i64 8\n  "
    out << dp + " = load ptr, ptr " + dg + "\n  "
    out << ep + " = getelementptr i8, ptr " + dp + ", i64 " + idx + "\n  "
    out << sub + " = sub i64 " + val + ", 1\n  "
    out << byte_val + " = trunc i64 " + sub + " to i8\n  "
    out << "store i8 " + byte_val + ", ptr " + ep + "\n  "
    out << t + " = add i64 " + val + ", 0"
    out.to_s()

  # Inline bool array get (bit-packed): unbox ptr, load data, bit test.
  # WArray-merge layout: slots ptr at offset 16, start i32 at
  # offset 4 (matching typed_array_get_inline). Pre-merge this read from
  # offset 8, which now points at size/cap and produces a garbage pointer.
  when :bool_array_get_inline
    t = wire_get(inst, :temp)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    ap = t + ".ap"
    ap_p = t + ".app"
    dg = t + ".dg"
    dp = t + ".dp"
    sg = t + ".sg"
    s32 = t + ".s32"
    s64 = t + ".s64"
    abs_idx = t + ".abs"
    bi = t + ".bi"
    bit64 = t + ".bit64"
    bit8 = t + ".bit8"
    mask = t + ".mask"
    ep = t + ".ep"
    byte = t + ".byte"
    masked = t + ".masked"
    is_set = t + ".is_set"
    out = StringBuffer(384)
    out << ap + " = and i64 " + arr + ", 140737488355312\n  "
    out << ap_p + " = inttoptr i64 " + ap + " to ptr\n  "
    out << dg + " = getelementptr i8, ptr " + ap_p + ", i64 16\n  "
    out << dp + " = load ptr, ptr " + dg + ", align 8" + tbaa_header_suffix() + "\n  "
    out << sg + " = getelementptr i8, ptr " + ap_p + ", i64 4\n  "
    out << s32 + " = load i32, ptr " + sg + ", align 4" + tbaa_header_suffix() + "\n  "
    out << s64 + " = sext i32 " + s32 + " to i64\n  "
    out << abs_idx + " = add i64 " + s64 + ", " + idx + "\n  "
    out << bi + " = lshr i64 " + abs_idx + ", 3\n  "
    out << bit64 + " = and i64 " + abs_idx + ", 7\n  "
    out << bit8 + " = trunc i64 " + bit64 + " to i8\n  "
    out << mask + " = shl i8 1, " + bit8 + "\n  "
    out << ep + " = getelementptr i8, ptr " + dp + ", i64 " + bi + "\n  "
    out << byte + " = load i8, ptr " + ep + tbaa_elem_suffix() + "\n  "
    out << masked + " = and i8 " + byte + ", " + mask + "\n  "
    # Two output flavors. With as_i1 the inline op leaves `t` as the
    # raw bit (`icmp ne i8 masked, 0`) — `if !bits[i]` / `while bits[i]`
    # consumers can branch on it directly. Without, we wrap in a select
    # to produce the W_TRUE/W_FALSE WValue. The lowering picks as_i1
    # when it knows the caller wants a boolean (truthy-elision); other
    # call sites get the WValue form and ensure_i64_value re-boxes if
    # needed.
    if wire_get(inst, :as_i1) == true
      out << t + " = icmp ne i8 " + masked + ", 0"
    else
      out << is_set + " = icmp ne i8 " + masked + ", 0\n  "
      out << t + " = select i1 " + is_set + ", i64 " + w_true.to_s() + ", i64 " + w_false.to_s()
    out.to_s()

  # Inline bool array set: val is guaranteed W_TRUE(2) or W_FALSE(1) by lowering.
  # Same offset fix as bool_array_get_inline above (slots ptr at offset 16,
  # start i32 at offset 4 — WArray-merge layout).
  when :bool_array_set_inline
    t = wire_get(inst, :temp)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    val = wire_get(inst, :val)
    ap = t + ".ap"
    ap_p = t + ".app"
    dg = t + ".dg"
    dp = t + ".dp"
    sg = t + ".sg"
    s32 = t + ".s32"
    s64 = t + ".s64"
    abs_idx = t + ".abs"
    bi = t + ".bi"
    bit64 = t + ".bit64"
    bit8 = t + ".bit8"
    mask = t + ".mask"
    ep = t + ".ep"
    byte = t + ".byte"
    set_bit = t + ".set"
    inv_mask = t + ".inv"
    cleared = t + ".clr"
    with_bit = t + ".wbit"
    new_byte = t + ".nb"
    out = StringBuffer(416)
    out << ap + " = and i64 " + arr + ", 140737488355312\n  "
    out << ap_p + " = inttoptr i64 " + ap + " to ptr\n  "
    out << dg + " = getelementptr i8, ptr " + ap_p + ", i64 16\n  "
    out << dp + " = load ptr, ptr " + dg + ", align 8" + tbaa_header_suffix() + "\n  "
    out << sg + " = getelementptr i8, ptr " + ap_p + ", i64 4\n  "
    out << s32 + " = load i32, ptr " + sg + ", align 4" + tbaa_header_suffix() + "\n  "
    out << s64 + " = sext i32 " + s32 + " to i64\n  "
    out << abs_idx + " = add i64 " + s64 + ", " + idx + "\n  "
    out << bi + " = lshr i64 " + abs_idx + ", 3\n  "
    out << bit64 + " = and i64 " + abs_idx + ", 7\n  "
    out << bit8 + " = trunc i64 " + bit64 + " to i8\n  "
    out << mask + " = shl i8 1, " + bit8 + "\n  "
    out << ep + " = getelementptr i8, ptr " + dp + ", i64 " + bi + "\n  "
    out << byte + " = load i8, ptr " + ep + tbaa_elem_suffix() + "\n  "
    out << set_bit + " = icmp ugt i64 " + val + ", 1\n  "
    out << inv_mask + " = xor i8 " + mask + ", -1\n  "
    out << cleared + " = and i8 " + byte + ", " + inv_mask + "\n  "
    out << with_bit + " = or i8 " + cleared + ", " + mask + "\n  "
    out << new_byte + " = select i1 " + set_bit + ", i8 " + with_bit + ", i8 " + cleared + "\n  "
    out << "store i8 " + new_byte + ", ptr " + ep + tbaa_elem_suffix() + "\n  "
    out << t + " = add i64 " + val + ", 0"
    out.to_s()

  # Int to float conversion
  when :sitofp_i64_f64
    wire_get(inst, :temp) + " = sitofp i64 " + wire_get(inst, :value) + " to double"
  when :uitofp_i64_f64
    wire_get(inst, :temp) + " = uitofp i64 " + wire_get(inst, :value) + " to double"
  when :sitofp_i128_f64
    wire_get(inst, :temp) + " = sitofp i128 " + wire_get(inst, :value) + " to double"
  when :uitofp_i128_f64
    wire_get(inst, :temp) + " = uitofp i128 " + wire_get(inst, :value) + " to double"

  else
    nil
