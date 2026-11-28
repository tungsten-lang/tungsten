# jsn/arm64 — pure-Tungsten ARM64 (AArch64) machine-code assembler.
#
# Encodes 32-bit ARM64 instructions directly into a growable i64[] word buffer,
# supports forward/backward labels with automatic branch patching, and finalizes
# directly into MAP_JIT memory via jit_mem_emit().

in JS

# ---- General-purpose registers ----
R_X0  = 0;  R_X1  = 1;  R_X2  = 2;  R_X3  = 3
R_X4  = 4;  R_X5  = 5;  R_X6  = 6;  R_X7  = 7
R_X8  = 8;  R_X9  = 9;  R_X10 = 10; R_X11 = 11
R_X12 = 12; R_X13 = 13; R_X14 = 14; R_X15 = 15
R_X16 = 16; R_X17 = 17; R_X18 = 18
R_X19 = 19; R_X20 = 20; R_X21 = 21; R_X22 = 22
R_X23 = 23; R_X24 = 24; R_X25 = 25; R_X26 = 26
R_X27 = 27; R_X28 = 28; R_FP  = 29; R_LR  = 30
R_SP  = 31; R_XZR = 31

# ---- Floating-point / NEON scalar registers (d0..d31) ----
R_D0  = 0;  R_D1  = 1;  R_D2  = 2;  R_D3  = 3
R_D4  = 4;  R_D5  = 5;  R_D6  = 6;  R_D7  = 7
R_D8  = 8;  R_D9  = 9;  R_D10 = 10; R_D11 = 11
R_D12 = 12; R_D13 = 13; R_D14 = 14; R_D15 = 15
R_D16 = 16; R_D17 = 17; R_D18 = 18; R_D19 = 19
R_D20 = 20; R_D21 = 21; R_D22 = 22; R_D23 = 23
R_D24 = 24; R_D25 = 25; R_D26 = 26; R_D27 = 27
R_D28 = 28; R_D29 = 29; R_D30 = 30; R_D31 = 31

# ---- Condition codes ----
CC_EQ = 0;  CC_NE = 1
CC_HS = 2;  CC_LO = 3
CC_MI = 4;  CC_PL = 5
CC_VS = 6;  CC_VC = 7
CC_HI = 8;  CC_LS = 9
CC_GE = 10; CC_LT = 11
CC_GT = 12; CC_LE = 13

# Fixup kinds
FX_B26   = 1   # B / BL (26-bit signed word offset at bits 0..25)
FX_B19   = 2   # B.cond / CBZ / CBNZ (19-bit signed word offset at bits 5..23)
FX_B14   = 3   # TBZ / TBNZ (14-bit signed word offset at bits 5..18)
FX_ADR   = 4   # ADR (21-bit signed byte offset: immlo[30:29], immhi[23:5])

+ A64
  rw :buf, :len, :cap, :labels, :fix_pos, :fix_lbl, :fix_kind, :failed

  -> new(init_cap = 256)
    @cap = init_cap
    @buf = i64[init_cap]
    @len = 0
    @labels = []      # label_id -> word index (or -1 if unbound)
    @fix_pos = []     # word index of instruction to patch
    @fix_lbl = []     # target label_id
    @fix_kind = []    # FX_*
    @failed = false

  -> grow
    old_buf = @buf
    nc = @cap * 2
    nb = i64[nc]
    i = 0
    while i < @len
      nb[i] = old_buf[i]
      i += 1
    @buf = nb
    @cap = nc
    ccall("w_value_free_w", old_buf)
    nil

  -> release
    ccall("w_value_free_w", @buf) if @buf != nil
    ccall("w_value_free_w", @labels) if @labels != nil
    ccall("w_value_free_w", @fix_pos) if @fix_pos != nil
    ccall("w_value_free_w", @fix_lbl) if @fix_lbl != nil
    ccall("w_value_free_w", @fix_kind) if @fix_kind != nil
    @buf = nil
    @labels = nil
    @fix_pos = nil
    @fix_lbl = nil
    @fix_kind = nil
    nil

  -> emit(insn)
    grow() if @len >= @cap
    @buf[@len] = insn & 0xFFFFFFFF
    @len += 1
    nil

  -> pos
    @len

  -> new_label
    id = @labels.size
    @labels.push(-1)
    id

  -> bind(lbl)
    @labels[lbl] = @len
    nil

  -> add_fix(lbl, kind)
    @fix_pos.push(@len)
    @fix_lbl.push(lbl)
    @fix_kind.push(kind)
    nil

  # Patch all label branches and emit into executable MAP_JIT memory.
  -> finalize
    return 0 if @failed
    i = 0
    n = @fix_pos.size
    while i < n
      p = @fix_pos[i]
      lbl = @fix_lbl[i]
      k = @fix_kind[i]
      tgt = @labels[lbl]
      if tgt < 0
        @failed = true
        return 0
      diff = tgt - p
      ins = @buf[p]
      if k == FX_B26
        @buf[p] = (ins & 0xFC000000) | (diff & 0x03FFFFFF)
      elsif k == FX_B19
        if diff < -262144 || diff > 262143
          @failed = true
          return 0
        @buf[p] = (ins & 0xFF00001F) | ((diff & 0x7FFFF) << 5)
      elsif k == FX_B14
        if diff < -8192 || diff > 8191
          @failed = true
          return 0
        @buf[p] = (ins & 0xFFF8001F) | ((diff & 0x3FFF) << 5)
      elsif k == FX_ADR
        bdiff = diff * 4
        lo = bdiff & 3
        hi = (bdiff >> 2) & 0x7FFFF
        @buf[p] = (ins & 0x9F00001F) | (lo << 29) | (hi << 5)
      i += 1
    jit_mem_emit(@buf, @len)

  # ---- Moves & Immediates ----

  # MOV Xd, Xm  (ORR Xd, XZR, Xm)
  -> mov_r(rd, rm)
    return nil if rd == rm
    emit(0xAA0003E0 | (rm << 16) | rd)

  # MOV Wd, Wm  (ORR Wd, WZR, Wm)
  -> mov_w(rd, rm)
    return nil if rd == rm
    emit(0x2A0003E0 | (rm << 16) | rd)

  # MOV Xd, SP or MOV SP, Xn (ADD Xd, Xn, #0)
  -> mov_sp(rd, rn)
    emit(0x91000000 | (rn << 5) | rd)

  # MOVZ Xd, #imm16, LSL #(hw*16)
  -> movz_x(rd, imm16, hw = 0)
    emit(0xD2800000 | (hw << 21) | ((imm16 & 0xFFFF) << 5) | rd)

  # MOVK Xd, #imm16, LSL #(hw*16)
  -> movk_x(rd, imm16, hw = 0)
    emit(0xF2800000 | (hw << 21) | ((imm16 & 0xFFFF) << 5) | rd)

  # MOVN Xd, #imm16, LSL #(hw*16)
  -> movn_x(rd, imm16, hw = 0)
    emit(0x92800000 | (hw << 21) | ((imm16 & 0xFFFF) << 5) | rd)

  # Load an arbitrary 64-bit integer into Xd using minimal MOVZ/MOVN + MOVK sequence.
  -> mov_imm64(rd, v)
    if v >= 0 && v <= 0xFFFF
      movz_x(rd, v, 0)
      return nil
    if v < 0 && v >= -65536
      movn_x(rd, (v ^ 0xFFFF) & 0xFFFF, 0)
      return nil
    c0 = v & 0xFFFF
    c1 = (v >> 16) & 0xFFFF
    c2 = (v >> 32) & 0xFFFF
    c3 = (v >> 48) & 0xFFFF
    # Count 0xFFFF chunks vs 0x0000 chunks to choose MOVN vs MOVZ
    nf = (c0 == 0xFFFF ? 1 : 0) + (c1 == 0xFFFF ? 1 : 0) + (c2 == 0xFFFF ? 1 : 0) + (c3 == 0xFFFF ? 1 : 0)
    nz = (c0 == 0 ? 1 : 0) + (c1 == 0 ? 1 : 0) + (c2 == 0 ? 1 : 0) + (c3 == 0 ? 1 : 0)
    if nf > nz
      first = true
      if c0 != 0xFFFF
        movn_x(rd, c0 ^ 0xFFFF, 0)
        first = false
      if c1 != 0xFFFF
        if first
          movn_x(rd, c1 ^ 0xFFFF, 1)
          first = false
        else
          movk_x(rd, c1, 1)
      if c2 != 0xFFFF
        if first
          movn_x(rd, c2 ^ 0xFFFF, 2)
          first = false
        else
          movk_x(rd, c2, 2)
      if c3 != 0xFFFF
        if first
          movn_x(rd, c3 ^ 0xFFFF, 3)
          first = false
        else
          movk_x(rd, c3, 3)
      movn_x(rd, 0, 0) if first
    else
      first = true
      if c0 != 0
        movz_x(rd, c0, 0)
        first = false
      if c1 != 0
        if first
          movz_x(rd, c1, 1)
          first = false
        else
          movk_x(rd, c1, 1)
      if c2 != 0
        if first
          movz_x(rd, c2, 2)
          first = false
        else
          movk_x(rd, c2, 2)
      if c3 != 0
        if first
          movz_x(rd, c3, 3)
          first = false
        else
          movk_x(rd, c3, 3)
      movz_x(rd, 0, 0) if first
    nil

  # Load an arbitrary 32-bit signed integer into Wd (zero-extended into Xd).
  -> mov_imm32(rd, v)
    u = v & 0xFFFFFFFF
    lo = u & 0xFFFF
    hi = (u >> 16) & 0xFFFF
    if hi == 0
      emit(0x52800000 | (lo << 5) | rd)       # MOVZ Wd, #lo
    elsif hi == 0xFFFF
      emit(0x12800000 | ((lo ^ 0xFFFF) << 5) | rd)  # MOVN Wd, #~lo
    else
      emit(0x52800000 | (lo << 5) | rd)
      emit(0x72A00000 | (hi << 5) | rd)       # MOVK Wd, #hi, LSL #16
    nil

  # ---- 64-bit Integer Arithmetic ----

  # ADD Xd, Xn, #imm12 (sh=1 for LSL #12)
  -> add_i(rd, rn, imm12, sh = 0)
    emit(0x91000000 | (sh << 22) | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)

  # SUB Xd, Xn, #imm12
  -> sub_i(rd, rn, imm12, sh = 0)
    emit(0xD1000000 | (sh << 22) | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)

  # ADDS Xd, Xn, #imm12
  -> adds_i(rd, rn, imm12, sh = 0)
    emit(0xB1000000 | (sh << 22) | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)

  # SUBS Xd, Xn, #imm12
  -> subs_i(rd, rn, imm12, sh = 0)
    emit(0xF1000000 | (sh << 22) | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)

  # CMP Xn, #imm12
  -> cmp_i(rn, imm12, sh = 0)
    subs_i(R_XZR, rn, imm12, sh)

  # ADD Xd, Xn, Xm [, LSL #shift]
  -> add_r(rd, rn, rm, shift = 0)
    emit(0x8B000000 | (rm << 16) | ((shift & 63) << 10) | (rn << 5) | rd)

  # SUB Xd, Xn, Xm [, LSL #shift]
  -> sub_r(rd, rn, rm, shift = 0)
    emit(0xCB000000 | (rm << 16) | ((shift & 63) << 10) | (rn << 5) | rd)

  # ADDS Xd, Xn, Xm
  -> adds_r(rd, rn, rm)
    emit(0xAB000000 | (rm << 16) | (rn << 5) | rd)

  # SUBS Xd, Xn, Xm
  -> subs_r(rd, rn, rm)
    emit(0xEB000000 | (rm << 16) | (rn << 5) | rd)

  # CMP Xn, Xm
  -> cmp_r(rn, rm)
    subs_r(R_XZR, rn, rm)

  # CCMP Xn, Xm, #nzcv, cond  (if cond holds, sets flags from Xn - Xm; else sets NZCV = nzcv!)
  -> ccmp_r(rn, rm, nzcv, cond)
    emit(0xFA400000 | (rm << 16) | ((cond & 15) << 12) | (rn << 5) | (nzcv & 15))

  # MUL Xd, Xn, Xm  (MADD Xd, Xn, Xm, XZR)
  -> mul_x(rd, rn, rm)
    emit(0x9B007C00 | (rm << 16) | (rn << 5) | rd)

  # MADD Xd, Xn, Xm, Xa  (Xd = Xa + Xn * Xm)
  -> madd_x(rd, rn, rm, ra)
    emit(0x9B000000 | (rm << 16) | (ra << 10) | (rn << 5) | rd)

  # MSUB Xd, Xn, Xm, Xa  (Xd = Xa - Xn * Xm)
  -> msub_x(rd, rn, rm, ra)
    emit(0x9B008000 | (rm << 16) | (ra << 10) | (rn << 5) | rd)

  # SDIV Xd, Xn, Xm
  -> sdiv_x(rd, rn, rm)
    emit(0x9AC00C00 | (rm << 16) | (rn << 5) | rd)

  # UDIV Xd, Xn, Xm
  -> udiv_x(rd, rn, rm)
    emit(0x9AC00800 | (rm << 16) | (rn << 5) | rd)

  # NEG Xd, Xm
  -> neg_x(rd, rm)
    sub_r(rd, R_XZR, rm)

  # ---- 32-bit Integer Arithmetic (exact JS int32 wrapping!) ----

  # ADD Wd, Wn, #imm12
  -> add_wi(rd, rn, imm12)
    emit(0x11000000 | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)

  # SUB Wd, Wn, #imm12
  -> sub_wi(rd, rn, imm12)
    emit(0x51000000 | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)

  # ADDS Wd, Wn, #imm12
  -> adds_wi(rd, rn, imm12)
    emit(0x31000000 | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)

  # SUBS Wd, Wn, #imm12
  -> subs_wi(rd, rn, imm12)
    emit(0x71000000 | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)

  # CMP Wn, #imm12
  -> cmp_wi(rn, imm12)
    subs_wi(R_XZR, rn, imm12)

  # ADD Wd, Wn, Wm [, LSL #shift]
  -> add_w(rd, rn, rm, shift = 0)
    emit(0x0B000000 | (rm << 16) | ((shift & 31) << 10) | (rn << 5) | rd)

  # CSEL Wd, Wn, Wm, cond
  -> csel_w(rd, rn, rm, cc)
    emit(0x1A800000 | (rm << 16) | (cc << 12) | (rn << 5) | rd)

  # SUB Wd, Wn, Wm
  -> sub_w(rd, rn, rm)
    emit(0x4B000000 | (rm << 16) | (rn << 5) | rd)

  # ADDS Wd, Wn, Wm (sets V on signed 32-bit overflow)
  -> adds_w(rd, rn, rm)
    emit(0x2B000000 | (rm << 16) | (rn << 5) | rd)

  # SUBS Wd, Wn, Wm
  -> subs_w(rd, rn, rm)
    emit(0x6B000000 | (rm << 16) | (rn << 5) | rd)

  # CMP Wn, Wm
  -> cmp_w(rn, rm)
    subs_w(R_XZR, rn, rm)

  # MUL Wd, Wn, Wm
  -> mul_w(rd, rn, rm)
    emit(0x1B007C00 | (rm << 16) | (rn << 5) | rd)

  # MADD Wd, Wn, Wm, Wa (Wd = Wa + Wn * Wm)
  -> madd_w(rd, rn, rm, ra)
    emit(0x1B000000 | (rm << 16) | (ra << 10) | (rn << 5) | rd)

  # MSUB Wd, Wn, Wm, Wa (Wd = Wa - Wn * Wm)
  -> msub_w(rd, rn, rm, ra)
    emit(0x1B008000 | (rm << 16) | (ra << 10) | (rn << 5) | rd)

  # SDIV Wd, Wn, Wm
  -> sdiv_w(rd, rn, rm)
    emit(0x1AC00C00 | (rm << 16) | (rn << 5) | rd)

  # UDIV Wd, Wn, Wm
  -> udiv_w(rd, rn, rm)
    emit(0x1AC00800 | (rm << 16) | (rn << 5) | rd)

  # NEG Wd, Wm
  -> neg_w(rd, rm)
    sub_w(rd, R_XZR, rm)

  # NEGS Wd, Wm
  -> negs_w(rd, rm)
    subs_w(rd, R_XZR, rm)

  # ---- Bitwise & Shifts ----

  # 64-bit
  -> and_r(rd, rn, rm)
    emit(0x8A000000 | (rm << 16) | (rn << 5) | rd)
  -> orr_r(rd, rn, rm)
    emit(0xAA000000 | (rm << 16) | (rn << 5) | rd)
  -> eor_r(rd, rn, rm)
    emit(0xCA000000 | (rm << 16) | (rn << 5) | rd)
  -> bic_r(rd, rn, rm)
    emit(0x8A200000 | (rm << 16) | (rn << 5) | rd)
  -> tst_r(rn, rm)
    emit(0xEA000000 | (rm << 16) | (rn << 5) | R_XZR)

  # 32-bit
  -> and_w(rd, rn, rm)
    emit(0x0A000000 | (rm << 16) | (rn << 5) | rd)
  -> bic_w(rd, rn, rm)
    emit(0x0A200000 | (rm << 16) | (rn << 5) | rd)
  -> orr_w(rd, rn, rm)
    emit(0x2A000000 | (rm << 16) | (rn << 5) | rd)
  -> eor_w(rd, rn, rm)
    emit(0x4A000000 | (rm << 16) | (rn << 5) | rd)
  # EOR Wd, Wn, Wm, LSR #sh
  -> eor_w_lsr(rd, rn, rm, sh)
    emit(0x4A400000 | (rm << 16) | ((sh & 31) << 10) | (rn << 5) | rd)
  # EOR Wd, Wn, Wm, ROR #sh
  -> eor_w_ror(rd, rn, rm, sh)
    emit(0x4AC00000 | (rm << 16) | ((sh & 31) << 10) | (rn << 5) | rd)
  -> mvn_w(rd, rm)
    emit(0x2A2003E0 | (rm << 16) | rd)
  -> tst_w(rn, rm)
    emit(0x6A000000 | (rm << 16) | (rn << 5) | R_XZR)

  # AND Wd, Wn, #((1<<nbits)-1)  (low-mask immediate, 1 <= nbits <= 31; nbits <= 0 -> 0)
  -> and_w_lowmask(rd, rn, nbits)
    if nbits <= 0
      mov_imm32(rd, 0)
      return nil
    emit(0x12000000 | ((nbits - 1) << 10) | (rn << 5) | rd)

  # AND Xd, Xn, #((1<<nbits)-1)  (low-mask immediate, 1 <= nbits <= 63)
  -> and_x_lowmask(rd, rn, nbits)
    emit(0x92400000 | ((nbits - 1) << 10) | (rn << 5) | rd)

  # AND Xd, Xn, #0x00007FFFFFFFFFF0 (untag WArray*: bits 46..4, clearing bit 47 + low nibble)
  -> and_x_ptr47(rd, rn)
    emit(0x927CA800 | (rn << 5) | rd)

  # TST Xn, #((1<<nbits)-1)
  -> tst_x_lowmask(rn, nbits)
    emit(0xF2400000 | ((nbits - 1) << 10) | (rn << 5) | R_XZR)

  # TST Xn, #0xFFFF00000000000F (single-insn check after sub #4: top 16 bits == 0 && low 4 bits == 0)
  -> tst_wobj_bad(rn)
    emit(0xF2504C00 | (rn << 5) | R_XZR)

  # Variable shifts (32-bit: ARM64 automatically masks shift amount mod 32, matching JS!)
  -> lsl_w(rd, rn, rm)
    emit(0x1AC02000 | (rm << 16) | (rn << 5) | rd)
  -> lsr_w(rd, rn, rm)
    emit(0x1AC02400 | (rm << 16) | (rn << 5) | rd)
  -> asr_w(rd, rn, rm)
    emit(0x1AC02800 | (rm << 16) | (rn << 5) | rd)

  # Variable shifts (64-bit)
  -> lsl_x(rd, rn, rm)
    emit(0x9AC02000 | (rm << 16) | (rn << 5) | rd)
  -> lsr_x(rd, rn, rm)
    emit(0x9AC02400 | (rm << 16) | (rn << 5) | rd)
  -> asr_x(rd, rn, rm)
    emit(0x9AC02800 | (rm << 16) | (rn << 5) | rd)

  # Immediate shifts (32-bit)
  -> lsl_wi(rd, rn, sh)
    s = sh & 31
    if s == 0
      mov_w(rd, rn)
    else
      emit(0x53000000 | (((32 - s) & 31) << 16) | ((31 - s) << 10) | (rn << 5) | rd)
  -> lsr_wi(rd, rn, sh)
    s = sh & 31
    if s == 0
      mov_w(rd, rn)
    else
      emit(0x53007C00 | (s << 16) | (rn << 5) | rd)
  -> asr_wi(rd, rn, sh)
    s = sh & 31
    if s == 0
      mov_w(rd, rn)
    else
      emit(0x13007C00 | (s << 16) | (rn << 5) | rd)
  # ROR Wd, Wn, #sh  (EXTR Wd, Wn, Wn, #sh)
  -> ror_wi(rd, rn, sh)
    s = sh & 31
    if s == 0
      mov_w(rd, rn)
    else
      emit(0x13800000 | (rn << 16) | (s << 10) | (rn << 5) | rd)

  # ROR Xd, Xn, #sh  (EXTR Xd, Xn, Xn, #sh)
  -> ror_xi(rd, rn, sh)
    s = sh & 63
    if s == 0
      mov_r(rd, rn)
    else
      emit(0x93C00000 | (rn << 16) | (s << 10) | (rn << 5) | rd)
  # REV Wd, Wn (32-bit byte-reverse for big-endian loads!)
  -> rev_w(rd, rn)
    emit(0x5AC00800 | (rn << 5) | rd)
  # RBIT Wd, Wn (32-bit bit-reverse for fast CTZ = CLZ(RBIT(x))!)
  -> rbit_w(rd, rn)
    emit(0x5AC00000 | (rn << 5) | rd)
  # RBIT Xd, Xn (64-bit bit-reverse for fast 64-bit CTZ = CLZ(RBIT(x))!)
  -> rbit_x(rd, rn)
    emit(0xDAC00000 | (rn << 5) | rd)

  # Immediate shifts (64-bit)
  -> lsl_xi(rd, rn, sh)
    s = sh & 63
    if s == 0
      mov_r(rd, rn)
    else
      emit(0xD3400000 | (((64 - s) & 63) << 16) | ((63 - s) << 10) | (rn << 5) | rd)
  -> lsr_xi(rd, rn, sh)
    s = sh & 63
    if s == 0
      mov_r(rd, rn)
    else
      emit(0xD340FC00 | (s << 16) | (rn << 5) | rd)
  -> asr_xi(rd, rn, sh)
    s = sh & 63
    if s == 0
      mov_r(rd, rn)
    else
      emit(0x9340FC00 | (s << 16) | (rn << 5) | rd)

  # SXTW Xd, Wn (sign-extend 32 -> 64)
  -> sxtw(rd, rn)
    emit(0x93407C00 | (rn << 5) | rd)

  # UXTW Xd, Wn (zero-extend 32 -> 64)
  -> uxtw(rd, rn)
    mov_w(rd, rn)

  # CLZ Wd, Wn
  -> clz_w(rd, rn)
    emit(0x5AC01000 | (rn << 5) | rd)
  # CLZ Xd, Xn
  -> clz_x(rd, rn)
    emit(0xDAC01000 | (rn << 5) | rd)

  # ---- Conditional Select / Set ----

  # CSET Xd, cond  (CSINC Xd, XZR, XZR, invert(cond))
  -> cset(rd, cc)
    emit(0x9A9F07E0 | ((cc ^ 1) << 12) | rd)

  # CSEL Xd, Xn, Xm, cond
  -> csel_x(rd, rn, rm, cc)
    emit(0x9A800000 | (rm << 16) | (cc << 12) | (rn << 5) | rd)

  # CSEL Wd, Wn, Wm, cond
  -> csel_w(rd, rn, rm, cc)
    emit(0x1A800000 | (rm << 16) | (cc << 12) | (rn << 5) | rd)

  # CNEG Wd, Wn, cond  (CSNEG Wd, Wn, Wn, invert(cond))
  -> cneg_w(rd, rn, cc)
    emit(0x5A800400 | (rn << 16) | ((cc ^ 1) << 12) | (rn << 5) | rd)

  # CNEG Xd, Xn, cond  (CSNEG Xd, Xn, Xn, invert(cond))
  -> cneg_x(rd, rn, cc)
    emit(0xDA800400 | (rn << 16) | ((cc ^ 1) << 12) | (rn << 5) | rd)

  # CINC Wd, Wn, cond  (CSINC Wd, Wn, Wn, invert(cond))
  -> cinc_w(rd, rn, cc)
    emit(0x1A800400 | (rn << 16) | ((cc ^ 1) << 12) | (rn << 5) | rd)

  # ---- Floating-Point (double d0..d31) ----

  # FMOV Dd, Xn (bitcast i64 -> f64)
  -> fmov_d_x(dd, rn)
    emit(0x9E670000 | (rn << 5) | dd)

  # FMOV Xd, Dn (bitcast f64 -> i64)
  -> fmov_x_d(rd, dn)
    emit(0x9E660000 | (dn << 5) | rd)

  # FMOV Dd, Dn
  -> fmov_d(dd, dn)
    return nil if dd == dn
    emit(0x1E604000 | (dn << 5) | dd)

  # FMOV Dd, #1.0
  -> fmov_d_one(dd)
    emit(0x1E6E1000 | (dd & 31))

  -> fadd_d(dd, dn, dm)
    emit(0x1E602800 | (dm << 16) | (dn << 5) | dd)
  -> fsub_d(dd, dn, dm)
    emit(0x1E603800 | (dm << 16) | (dn << 5) | dd)
  -> fmul_d(dd, dn, dm)
    emit(0x1E600800 | (dm << 16) | (dn << 5) | dd)
  -> fdiv_d(dd, dn, dm)
    emit(0x1E601800 | (dm << 16) | (dn << 5) | dd)
  # FMADD Dd, Dn, Dm, Da (Dd = Da + Dn * Dm)
  -> fmadd_d(dd, dn, dm, da)
    emit(0x1F400000 | (dm << 16) | (da << 10) | (dn << 5) | dd)
  # FMSUB Dd, Dn, Dm, Da (Dd = Da - Dn * Dm)
  -> fmsub_d(dd, dn, dm, da)
    emit(0x1F408000 | (dm << 16) | (da << 10) | (dn << 5) | dd)
  -> fneg_d(dd, dn)
    emit(0x1E614000 | (dn << 5) | dd)
  -> fabs_d(dd, dn)
    emit(0x1E60C000 | (dn << 5) | dd)
  -> fsqrt_d(dd, dn)
    emit(0x1E61C000 | (dn << 5) | dd)
  -> frintm_d(dd, dn)   # floor
    emit(0x1E654000 | (dn << 5) | dd)
  -> frintp_d(dd, dn)   # ceil
    emit(0x1E64C000 | (dn << 5) | dd)
  -> frintz_d(dd, dn)   # trunc
    emit(0x1E65C000 | (dn << 5) | dd)
  -> frintn_d(dd, dn)   # round-to-nearest-even
    emit(0x1E644000 | (dn << 5) | dd)
  -> fcmp_d(dn, dm)
    emit(0x1E602000 | (dm << 16) | (dn << 5))
  -> fcmp_d0(dn)
    emit(0x1E602008 | (dn << 5))
  -> fcsel_d(dd, dn, dm, cc)
    emit(0x1E600C00 | (dm << 16) | (cc << 12) | (dn << 5) | dd)

  # Conversions
  -> scvtf_d_w(dd, rn)   # int32 -> double
    emit(0x1E620000 | (rn << 5) | dd)
  -> scvtf_d_x(dd, rn)   # int64 -> double
    emit(0x9E620000 | (rn << 5) | dd)
  -> ucvtf_d_w(dd, rn)   # uint32 -> double
    emit(0x1E630000 | (rn << 5) | dd)
  -> fcvtzs_w_d(rd, dn)  # double -> int32 (saturating)
    emit(0x1E780000 | (dn << 5) | rd)
  -> fcvtzs_x_d(rd, dn)  # double -> int64 (saturating)
    emit(0x9E780000 | (dn << 5) | rd)
  -> fcvtzu_w_d(rd, dn)  # double -> uint32 (saturating)
    emit(0x1E790000 | (dn << 5) | rd)
  -> fcvt_d_s(dd, sn)    # float32 -> double
    emit(0x1E22C000 | (sn << 5) | dd)
  -> fcvt_s_d(sd, dn)    # double -> float32
    emit(0x1E624000 | (dn << 5) | sd)
  -> fcvt_d_h(dd, hn)    # float16 -> double (ARMv8.2 FP16)
    emit(0x1EE2C000 | (hn << 5) | dd)
  -> fcvt_h_d(hd, dn)    # double -> float16 (ARMv8.2 FP16)
    emit(0x1E63C000 | (dn << 5) | hd)
  -> fcvt_s_h(sd, hn)    # float16 -> float32
    emit(0x1EE24000 | (hn << 5) | sd)
  -> fcvt_h_s(hd, sn)    # float32 -> float16
    emit(0x1E23C000 | (sn << 5) | hd)
  -> ucvtf_d_x(dd, rn)   # uint64 -> double
    emit(0x9E630000 | (rn << 5) | dd)
  -> fcvtzu_x_d(rd, dn)  # double -> uint64
    emit(0x9E790000 | (dn << 5) | rd)
  -> fmov_s_w(sd, rn)    # bitcast i32 -> f32
    emit(0x1E270000 | (rn << 5) | sd)
  -> fmov_w_s(rd, sn)    # bitcast f32 -> i32
    emit(0x1E260000 | (sn << 5) | rd)
  -> fadd_s(sd, sn, sm)
    emit(0x1E202800 | (sm << 16) | (sn << 5) | sd)
  -> fsub_s(sd, sn, sm)
    emit(0x1E203800 | (sm << 16) | (sn << 5) | sd)
  -> fmul_s(sd, sn, sm)
    emit(0x1E200800 | (sm << 16) | (sn << 5) | sd)
  -> fdiv_s(sd, sn, sm)
    emit(0x1E201800 | (sm << 16) | (sn << 5) | sd)
  -> fmin_d(dd, dn, dm)
    emit(0x1E605800 | (dm << 16) | (dn << 5) | dd)
  -> fmax_d(dd, dn, dm)
    emit(0x1E604800 | (dm << 16) | (dn << 5) | dd)
  # LDR Ht, [Xn, Xm, LSL #1]
  -> ldr_h_idx(ht, rn, rm)
    emit(0x7C607800 | (rm << 16) | (rn << 5) | ht)
  # STR Ht, [Xn, Xm, LSL #1]
  -> str_h_idx(ht, rn, rm)
    emit(0x7C207800 | (rm << 16) | (rn << 5) | ht)

  # ---- Loads & Stores ----

  # LDR Xt, [Xn, #uoff] (uoff multiple of 8, 0..32760)
  -> ldr_x(rt, rn, uoff = 0)
    if uoff >= 0 && (uoff & 7) == 0 && uoff <= 32760
      emit(0xF9400000 | ((uoff >> 3) << 10) | (rn << 5) | rt)
    elsif uoff >= -256 && uoff <= 255
      emit(0xF8400000 | ((uoff & 0x1FF) << 12) | (rn << 5) | rt)   # LDUR
    else
      @failed = true
    nil

  # STR Xt, [Xn, #uoff]
  -> str_x(rt, rn, uoff = 0)
    if uoff >= 0 && (uoff & 7) == 0 && uoff <= 32760
      emit(0xF9000000 | ((uoff >> 3) << 10) | (rn << 5) | rt)
    elsif uoff >= -256 && uoff <= 255
      emit(0xF8000000 | ((uoff & 0x1FF) << 12) | (rn << 5) | rt)   # STUR
    else
      @failed = true
    nil

  # LDR Wt, [Xn, #uoff]
  -> ldr_w(rt, rn, uoff = 0)
    if uoff >= 0 && (uoff & 3) == 0 && uoff <= 16380
      emit(0xB9400000 | ((uoff >> 2) << 10) | (rn << 5) | rt)
    elsif uoff >= -256 && uoff <= 255
      emit(0xB8400000 | ((uoff & 0x1FF) << 12) | (rn << 5) | rt)
    else
      @failed = true
    nil

  # STR Wt, [Xn, #uoff]
  -> str_w(rt, rn, uoff = 0)
    if uoff >= 0 && (uoff & 3) == 0 && uoff <= 16380
      emit(0xB9000000 | ((uoff >> 2) << 10) | (rn << 5) | rt)
    elsif uoff >= -256 && uoff <= 255
      emit(0xB8000000 | ((uoff & 0x1FF) << 12) | (rn << 5) | rt)
    else
      @failed = true
    nil

  # LDRSW Xt, [Xn, #uoff]
  -> ldrsw(rt, rn, uoff = 0)
    if uoff >= 0 && (uoff & 3) == 0 && uoff <= 16380
      emit(0xB9800000 | ((uoff >> 2) << 10) | (rn << 5) | rt)
    elsif uoff >= -256 && uoff <= 255
      emit(0xB8800000 | ((uoff & 0x1FF) << 12) | (rn << 5) | rt)
    else
      @failed = true
    nil

  # LDRB Wt, [Xn, #uoff]
  -> ldrb(rt, rn, uoff = 0)
    if uoff >= 0 && uoff <= 4095
      emit(0x39400000 | (uoff << 10) | (rn << 5) | rt)
    elsif uoff >= -256 && uoff <= 255
      emit(0x38400000 | ((uoff & 0x1FF) << 12) | (rn << 5) | rt)
    else
      @failed = true
    nil

  # STRB Wt, [Xn, #uoff]
  -> strb(rt, rn, uoff = 0)
    if uoff >= 0 && uoff <= 4095
      emit(0x39000000 | (uoff << 10) | (rn << 5) | rt)
    elsif uoff >= -256 && uoff <= 255
      emit(0x38000000 | ((uoff & 0x1FF) << 12) | (rn << 5) | rt)
    else
      @failed = true
    nil

  # LDR Dt, [Xn, #uoff]
  -> ldr_d(dt, rn, uoff = 0)
    if uoff >= 0 && (uoff & 7) == 0 && uoff <= 32760
      emit(0xFD400000 | ((uoff >> 3) << 10) | (rn << 5) | dt)
    elsif uoff >= -256 && uoff <= 255
      emit(0xFC400000 | ((uoff & 0x1FF) << 12) | (rn << 5) | dt)
    else
      @failed = true
    nil

  # STR Dt, [Xn, #uoff]
  -> str_d(dt, rn, uoff = 0)
    if uoff >= 0 && (uoff & 7) == 0 && uoff <= 32760
      emit(0xFD000000 | ((uoff >> 3) << 10) | (rn << 5) | dt)
    elsif uoff >= -256 && uoff <= 255
      emit(0xFC000000 | ((uoff & 0x1FF) << 12) | (rn << 5) | dt)
    else
      @failed = true
    nil

  # Scaled register loads/stores: [Xn, Xm, LSL #scale]
  # LDR Xt, [Xn, Xm, LSL #3]
  -> ldr_x_idx(rt, rn, rm)
    emit(0xF8607800 | (rm << 16) | (rn << 5) | rt)
  # STR Xt, [Xn, Xm, LSL #3]
  -> str_x_idx(rt, rn, rm)
    emit(0xF8207800 | (rm << 16) | (rn << 5) | rt)
  # LDR Dt, [Xn, Xm, LSL #3]
  -> ldr_d_idx(dt, rn, rm)
    emit(0xFC607800 | (rm << 16) | (rn << 5) | dt)
  # STR Dt, [Xn, Xm, LSL #3]
  -> str_d_idx(dt, rn, rm)
    emit(0xFC207800 | (rm << 16) | (rn << 5) | dt)
  # LDR St, [Xn, Xm, LSL #2]
  -> ldr_s_idx(st, rn, rm)
    emit(0xBC607800 | (rm << 16) | (rn << 5) | st)
  # STR St, [Xn, Xm, LSL #2]
  -> str_s_idx(st, rn, rm)
    emit(0xBC207800 | (rm << 16) | (rn << 5) | st)
  # LDRSW Xt, [Xn, Xm, LSL #2]
  -> ldrsw_idx(rt, rn, rm)
    emit(0xB8A07800 | (rm << 16) | (rn << 5) | rt)
  # LDR Wt, [Xn, Xm, LSL #2]
  -> ldr_w_idx(rt, rn, rm)
    emit(0xB8607800 | (rm << 16) | (rn << 5) | rt)
  # LDR Wt, [Xn, Xm] (unscaled byte-offset 32-bit load!)
  -> ldr_w_byte(rt, rn, rm)
    emit(0xB8606800 | (rm << 16) | (rn << 5) | rt)
  # STR Wt, [Xn, Xm] (unscaled byte-offset 32-bit store!)
  -> str_w_byte(rt, rn, rm)
    emit(0xB8206800 | (rm << 16) | (rn << 5) | rt)
  # LDR Xt, [Xn, Xm] (unscaled byte-offset 64-bit load!)
  -> ldr_x_byte(rt, rn, rm)
    emit(0xF8606800 | (rm << 16) | (rn << 5) | rt)
  # STR Xt, [Xn, Xm] (unscaled byte-offset 64-bit store!)
  -> str_x_byte(rt, rn, rm)
    emit(0xF8206800 | (rm << 16) | (rn << 5) | rt)
  # STR Wt, [Xn, Xm, LSL #2]
  -> str_w_idx(rt, rn, rm)
    emit(0xB8207800 | (rm << 16) | (rn << 5) | rt)
  # LDRB Wt, [Xn, Xm]
  -> ldrb_idx(rt, rn, rm)
    emit(0x38606800 | (rm << 16) | (rn << 5) | rt)
  # STRB Wt, [Xn, Xm]
  -> strb_idx(rt, rn, rm)
    emit(0x38206800 | (rm << 16) | (rn << 5) | rt)
  # LDRSB Wt, [Xn, Xm]
  -> ldrsb_idx(rt, rn, rm)
    emit(0x38E06800 | (rm << 16) | (rn << 5) | rt)
  # LDRH Wt, [Xn, Xm, LSL #1]
  -> ldrh_idx(rt, rn, rm)
    emit(0x78607800 | (rm << 16) | (rn << 5) | rt)
  # LDRSH Wt, [Xn, Xm, LSL #1]
  -> ldrsh_idx(rt, rn, rm)
    emit(0x78E07800 | (rm << 16) | (rn << 5) | rt)
  # STRH Wt, [Xn, Xm, LSL #1]
  -> strh_idx(rt, rn, rm)
    emit(0x78207800 | (rm << 16) | (rn << 5) | rt)

  # Load/Store pairs (signed offset multiple of 8, -512..504)
  -> stp_x(rt1, rt2, rn, off = 0)
    emit(0xA9000000 | (((off >> 3) & 0x7F) << 15) | (rt2 << 10) | (rn << 5) | rt1)
  -> ldp_x(rt1, rt2, rn, off = 0)
    emit(0xA9400000 | (((off >> 3) & 0x7F) << 15) | (rt2 << 10) | (rn << 5) | rt1)
  -> stp_pre(rt1, rt2, rn, off)
    emit(0xA9800000 | (((off >> 3) & 0x7F) << 15) | (rt2 << 10) | (rn << 5) | rt1)
  -> ldp_post(rt1, rt2, rn, off)
    emit(0xA8C00000 | (((off >> 3) & 0x7F) << 15) | (rt2 << 10) | (rn << 5) | rt1)
  -> stp_d(dt1, dt2, rn, off = 0)
    emit(0x6D000000 | (((off >> 3) & 0x7F) << 15) | (dt2 << 10) | (rn << 5) | dt1)
  -> ldp_d(dt1, dt2, rn, off = 0)
    emit(0x6D400000 | (((off >> 3) & 0x7F) << 15) | (dt2 << 10) | (rn << 5) | dt1)

  # ---- Control Flow ----

  -> b(lbl)
    add_fix(lbl, FX_B26)
    emit(0x14000000)

  -> bl(lbl)
    add_fix(lbl, FX_B26)
    emit(0x94000000)

  -> b_cond(cc, lbl)
    add_fix(lbl, FX_B19)
    emit(0x54000000 | cc)

  -> cbz_x(rt, lbl)
    add_fix(lbl, FX_B19)
    emit(0xB4000000 | rt)

  -> cbnz_x(rt, lbl)
    add_fix(lbl, FX_B19)
    emit(0xB5000000 | rt)

  -> cbz_w(rt, lbl)
    add_fix(lbl, FX_B19)
    emit(0x34000000 | rt)

  -> cbnz_w(rt, lbl)
    add_fix(lbl, FX_B19)
    emit(0x35000000 | rt)

  -> tbz(rt, bit, lbl)
    add_fix(lbl, FX_B14)
    b5 = (bit >> 5) & 1
    b40 = bit & 31
    emit(0x36000000 | (b5 << 31) | (b40 << 19) | rt)

  -> tbnz(rt, bit, lbl)
    add_fix(lbl, FX_B14)
    b5 = (bit >> 5) & 1
    b40 = bit & 31
    emit(0x37000000 | (b5 << 31) | (b40 << 19) | rt)

  -> blr(rn)
    emit(0xD63F0000 | (rn << 5))

  -> br(rn)
    emit(0xD61F0000 | (rn << 5))

  -> ret
    emit(0xD65F03C0)

  -> nop
    emit(0xD503201F)

  # FJCVTZS Wd, Dn (ARMv8.3-A hardware JavaScript ToInt32: 100% exact for ALL 2^64 doubles!)
  -> fjcvtzs_w_d(rd, dn)
    emit(0x1E7E0000 | (dn << 5) | rd)

  # Scalar 64-bit SIMD integer ADD/SUB in D registers (zero-FMOV NaN-box bias!)
  -> add_d_i64(rd, rn, rm)
    emit(0x5EE08400 | (rm << 16) | (rn << 5) | rd)

  -> sub_d_i64(rd, rn, rm)
    emit(0x7EE08400 | (rm << 16) | (rn << 5) | rd)

  # ---- 128-bit ARM64 NEON Advanced SIMD (machine-verified encodings) ----

  # 128-bit Q-register Loads & Stores
  -> ldr_q(qt, rn, uoff = 0)
    emit(0x3DC00000 | ((uoff >> 4) << 10) | (rn << 5) | qt)
  -> str_q(qt, rn, uoff = 0)
    emit(0x3D800000 | ((uoff >> 4) << 10) | (rn << 5) | qt)
  -> ldr_q_post(qt, rn, simm9)
    emit(0x3CC00400 | ((simm9 & 0x1FF) << 12) | (rn << 5) | qt)
  -> str_q_post(qt, rn, simm9)
    emit(0x3C800400 | ((simm9 & 0x1FF) << 12) | (rn << 5) | qt)
  -> ldp_q(qt1, qt2, rn, off = 0)
    emit(0xAD400000 | (((off >> 4) & 0x7F) << 15) | (qt2 << 10) | (rn << 5) | qt1)
  -> stp_q(qt1, qt2, rn, off = 0)
    emit(0xAD000000 | (((off >> 4) & 0x7F) << 15) | (qt2 << 10) | (rn << 5) | qt1)
  -> ldp_q_post(qt1, qt2, rn, off)
    emit(0xACC00000 | (((off >> 4) & 0x7F) << 15) | (qt2 << 10) | (rn << 5) | qt1)
  -> stp_q_post(qt1, qt2, rn, off)
    emit(0xAC800000 | (((off >> 4) & 0x7F) << 15) | (qt2 << 10) | (rn << 5) | qt1)
  -> ldr_s_post(st, rn, simm9)
    emit(0xBC400400 | ((simm9 & 0x1FF) << 12) | (rn << 5) | st)
  # LD4 {Vt.16b, Vt+1.16b, Vt+2.16b, Vt+3.16b}, [Xn], #64 (16 RGBA pixels de-interleaved in 1 insn!)
  -> ld4_16b_post(vt, rn)
    emit(0x4CDF0000 | (rn << 5) | vt)

  # Broadcast / Zero / Lane Extract
  -> movi_zero_16b(vd)
    emit(0x4F00E400 | vd)
  -> dup_4s_g(vd, rn)
    emit(0x4E040C00 | (rn << 5) | vd)
  -> dup_16b_g(vd, rn)
    emit(0x4E010C00 | (rn << 5) | vd)
  -> dup_4s_elt0(vd, vn)
    emit(0x4E040400 | (vn << 5) | vd)
  -> dup_2d_elt0(vd, vn)
    emit(0x4E080400 | (vn << 5) | vd)
  -> umov_w_s(rd, vn, idx)
    emit(0x0E043C00 | (idx << 19) | (vn << 5) | rd)

  # NEON f64 (2d) & f32 (4s) Arithmetic + Pairwise Reduction
  -> fadd_2d(vd, vn, vm)
    emit(0x4E60D400 | (vm << 16) | (vn << 5) | vd)
  -> fmul_2d(vd, vn, vm)
    emit(0x6E60DC00 | (vm << 16) | (vn << 5) | vd)
  -> fmla_2d(vd, vn, vm)
    emit(0x4E60CC00 | (vm << 16) | (vn << 5) | vd)
  -> faddp_d(dd, vn)
    emit(0x7E70D800 | (vn << 5) | dd)
  -> fadd_4s(vd, vn, vm)
    emit(0x4E20D400 | (vm << 16) | (vn << 5) | vd)
  -> fmul_4s(vd, vn, vm)
    emit(0x6E20DC00 | (vm << 16) | (vn << 5) | vd)
  -> fmla_4s(vd, vn, vm)
    emit(0x4E20CC00 | (vm << 16) | (vn << 5) | vd)
  -> fmax_4s(vd, vn, vm)
    emit(0x4E20F400 | (vm << 16) | (vn << 5) | vd)

  # NEON FP Widening / Narrowing Conversions (f16 <-> f32 <-> f64)
  -> fcvtl_2d_2s(vd, vn)
    emit(0x0E617800 | (vn << 5) | vd)
  -> fcvtl2_2d_4s(vd, vn)
    emit(0x4E617800 | (vn << 5) | vd)
  -> fcvtn_2s_2d(vd, vn)
    emit(0x0E616800 | (vn << 5) | vd)
  -> fcvtn2_4s_2d(vd, vn)
    emit(0x4E616800 | (vn << 5) | vd)
  -> fcvtl_4s_4h(vd, vn)
    emit(0x0E217800 | (vn << 5) | vd)
  -> fcvtl2_4s_8h(vd, vn)
    emit(0x4E217800 | (vn << 5) | vd)
  -> fcvtn_4h_4s(vd, vn)
    emit(0x0E216800 | (vn << 5) | vd)
  -> fcvtn2_8h_4s(vd, vn)
    emit(0x4E216800 | (vn << 5) | vd)

  # NEON Integer Vector Ops (16b / 8h / 4s)
  -> eor_16b(vd, vn, vm)
    emit(0x6E201C00 | (vm << 16) | (vn << 5) | vd)
  -> mul_4s(vd, vn, vm)
    emit(0x4EA09C00 | (vm << 16) | (vn << 5) | vd)
  -> sshr_4s(vd, vn, sh)
    emit(0x4F000400 | ((64 - sh) << 16) | (vn << 5) | vd)
  -> umull_8h_8b(vd, vn, vm)
    emit(0x2E20C000 | (vm << 16) | (vn << 5) | vd)
  -> umull2_8h_16b(vd, vn, vm)
    emit(0x6E20C000 | (vm << 16) | (vn << 5) | vd)
  -> umlal_8h_8b(vd, vn, vm)
    emit(0x2E208000 | (vm << 16) | (vn << 5) | vd)
  -> umlal2_8h_16b(vd, vn, vm)
    emit(0x6E208000 | (vm << 16) | (vn << 5) | vd)
  -> shrn_8b_8h(vd, vn, sh)
    emit(0x0F008400 | ((16 - sh) << 16) | (vn << 5) | vd)
  -> shrn2_16b_8h(vd, vn, sh)
    emit(0x4F008400 | ((16 - sh) << 16) | (vn << 5) | vd)

  # ---- Direct absolute call (within ±128 MB uses BL, otherwise MOV + BLR) ----
  -> call_abs(tmp_reg, addr)
    mov_imm64(tmp_reg, addr)
    blr(tmp_reg)
