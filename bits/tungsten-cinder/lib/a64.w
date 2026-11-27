# cinder/a64 — Pure-Tungsten ARM64 (AArch64) machine-code assembler.
#
# Emits 32-bit little-endian ARM64 instructions into a ByteBuf, supporting:
#   1. In-process JIT execution (local label fixups + cinder_jit_emit_buf).
#   2. Ahead-of-time Mach-O 64 & ELF64 object emission (external symbol relocations,
#      GOT loads, TLV / TLS page loads, arbitrary-size stack frame helpers, and
#      far-branch-safe conditional jumps).

use ./buf
use ./jit_mem

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
CC_CS = 2;  CC_CC = 3
CC_MI = 4;  CC_PL = 5
CC_VS = 6;  CC_VC = 7
CC_HI = 8;  CC_LS = 9
CC_GE = 10; CC_LT = 11
CC_GT = 12; CC_LE = 13
CC_AL = 14

# ---- Internal label fixup kinds ----
FX_A64_B26 = 1
FX_A64_B19 = 2
FX_A64_B14 = 3
FX_A64_ADR = 4

# ---- External object relocation kinds ----
CREL_A64_BRANCH26       = 1
CREL_A64_PAGE21         = 2
CREL_A64_PAGEOFF12      = 3
CREL_A64_GOT_PAGE21     = 4
CREL_A64_GOT_PAGEOFF12  = 5
CREL_A64_TLVP_PAGE21    = 6
CREL_A64_TLVP_PAGEOFF12 = 7

# Encode a 64-bit or 32-bit ARM64 logical bitmask immediate -> (N << 12) | (immr << 6) | imms, or -1 if not representable.
-> a64_encode_bitmask_imm(val, reg_bits)
  v = reg_bits == 32 ? (val & 0xFFFFFFFF) : val
  return -1 if v == 0
  return -1 if reg_bits == 32 && v == 0xFFFFFFFF
  return -1 if reg_bits == 64 && v == -1
  # Test element sizes 2, 4, 8, 16, 32, 64
  size = 2
  while size <= reg_bits
    mask = size == 64 ? -1 : ((1 << size) - 1)
    elt = v & mask
    # Verify v repeats `elt` across all lanes of `reg_bits`
    ok_rep = true
    sh = size
    while sh < reg_bits
      if ((v >> sh) & mask) != elt
        ok_rep = false
        sh = reg_bits
      sh += size
    if ok_rep
      # `elt` must be a non-zero, non-all-ones rotated contiguous run of 1s within `size` bits.
      # Try rotations r = 0..size-1 right: ror(elt, r) == (1 << ones) - 1
      ones = 0
      b = 0
      while b < size
        ones += 1 if ((elt >> b) & 1) != 0
        b += 1
      if ones > 0 && ones < size
        want = (1 << ones) - 1
        rot = 0
        while rot < size
          # Rotate `want` right by `rot` within `size` bits (= left by size - rot)
          cand = rot == 0 ? want : (((want >> rot) | (want << (size - rot))) & mask)
          if cand == elt
            n_bit = size == 64 ? 1 : 0
            imms = (((0x3F ^ (size * 2 - 1)) & 0x3F) | (ones - 1)) & 0x3F
            return (n_bit << 12) | (rot << 6) | imms
          rot += 1
    size = size * 2
  -1

+ CinderA64
  rw :buf, :labels, :fix_off, :fix_lbl, :fix_kind, :failed
  rw :rel_off, :rel_sym, :rel_kind, :rel_add

  -> new(init_words = 256)
    @buf = ByteBuf.new(init_words * 4)
    @labels = []
    @fix_off = []
    @fix_lbl = []
    @fix_kind = []
    @rel_off = []
    @rel_sym = []
    @rel_kind = []
    @rel_add = []
    @failed = false

  -> len
    @buf.len >> 2

  -> byte_len
    @buf.len

  -> emit(insn)
    @buf.put_u32_le(insn)
    nil

  -> emit_u16(val)
    @buf.put_u16_le(val)
    nil

  -> align_bytes(pow2)
    # Pad with NOPs if 4-byte aligned, else zero bytes
    if (pow2 >= 4) && ((@buf.len & 3) == 0)
      while (@buf.len & (pow2 - 1)) != 0
        nop()
    else
      @buf.align_to(pow2, 0)
    nil

  -> new_label
    id = @labels.size()
    @labels.push(-1)
    id

  -> bind(lbl)
    @labels[lbl] = @buf.len
    nil

  -> add_fix(lbl, kind)
    @fix_off.push(@buf.len)
    @fix_lbl.push(lbl)
    @fix_kind.push(kind)
    nil

  -> add_reloc(sym, kind, addend = 0)
    @rel_off.push(@buf.len)
    @rel_sym.push(sym)
    @rel_kind.push(kind)
    @rel_add.push(addend)
    nil

  # Resolve all internal label fixups in-place inside @buf. Returns true on success.
  -> patch_fixups
    return false if @failed
    i = 0
    n = @fix_off.size()
    while i < n
      off = @fix_off[i]
      lbl = @fix_lbl[i]
      k = @fix_kind[i]
      tgt = @labels[lbl]
      if tgt < 0
        @failed = true
        return false
      bdiff = tgt - off
      wdiff = bdiff >> 2
      ins = @buf.read_u32_le(off)
      if k == FX_A64_B26
        @buf.patch_u32_le(off, (ins & 0xFC000000) | (wdiff & 0x03FFFFFF))
      elsif k == FX_A64_B19
        if wdiff < -262144 || wdiff > 262143
          @failed = true
          return false
        @buf.patch_u32_le(off, (ins & 0xFF00001F) | ((wdiff & 0x7FFFF) << 5))
      elsif k == FX_A64_B14
        if wdiff < -8192 || wdiff > 8191
          @failed = true
          return false
        @buf.patch_u32_le(off, (ins & 0xFFF8001F) | ((wdiff & 0x3FFF) << 5))
      elsif k == FX_A64_ADR
        lo = bdiff & 3
        hi = (bdiff >> 2) & 0x7FFFF
        @buf.patch_u32_le(off, (ins & 0x9F00001F) | (lo << 29) | (hi << 5))
      i += 1
    true

  -> finalize
    return 0 if !patch_fixups()
    cinder_jit_emit_buf(@buf)

  # ---- External Symbol Address / Call Helpers (for Mach-O / ELF64 .o) ----

  -> bl_sym(sym)
    add_reloc(sym, CREL_A64_BRANCH26, 0)
    emit(0x94000000)

  -> b_sym(sym)
    add_reloc(sym, CREL_A64_BRANCH26, 0)
    emit(0x14000000)

  # Materialize address of module-defined symbol (+ optional addend) into `rd`.
  -> addr_sym_local(rd, sym, addend = 0)
    add_reloc(sym, CREL_A64_PAGE21, 0)
    emit(0x90000000 | rd)
    add_reloc(sym, CREL_A64_PAGEOFF12, 0)
    emit(0x91000000 | (rd << 5) | rd)
    add_sp_imm(rd, rd, addend) if addend != 0
    nil

  # Materialize address of external symbol via GOT into `rd` (and optional + addend).
  -> addr_sym_got(rd, sym, addend = 0)
    add_reloc(sym, CREL_A64_GOT_PAGE21, 0)
    emit(0x90000000 | rd)
    add_reloc(sym, CREL_A64_GOT_PAGEOFF12, 0)
    emit(0xF9400000 | (rd << 5) | rd)
    add_sp_imm(rd, rd, addend) if addend != 0
    nil

  # Materialize macOS TLV descriptor address (`sym@TLVPPAGE` + `sym@TLVPPAGEOFF`) into `x0`,
  # then invoke `[x0]` thunk (`_tlv_bootstrap` / fast TLS getter), which preserves all regs
  # except `x0, x16, x17` and returns the thread-local base pointer in `x0`!
  -> addr_tls_macos(sym, addend = 0)
    add_reloc(sym, CREL_A64_TLVP_PAGE21, 0)
    emit(0x90000000 | R_X0)
    add_reloc(sym, CREL_A64_TLVP_PAGEOFF12, 0)
    emit(0xF9400000 | (R_X0 << 5) | R_X0)
    ldr_x(R_X16, R_X0, 0)
    blr(R_X16)
    add_sp_imm(R_X0, R_X0, addend) if addend != 0
    nil

  # ---- Moves & Immediates ----

  -> mov_r(rd, rm)
    return nil if rd == rm
    emit(0xAA0003E0 | (rm << 16) | rd)

  -> mov_w(rd, rm)
    return nil if rd == rm && false
    emit(0x2A0003E0 | (rm << 16) | rd)

  -> mov_sp(rd, rn)
    emit(0x91000000 | (rn << 5) | rd)

  -> movz_x(rd, imm16, hw = 0)
    emit(0xD2800000 | (hw << 21) | ((imm16 & 0xFFFF) << 5) | rd)

  -> movk_x(rd, imm16, hw = 0)
    emit(0xF2800000 | (hw << 21) | ((imm16 & 0xFFFF) << 5) | rd)

  -> movn_x(rd, imm16, hw = 0)
    emit(0x92800000 | (hw << 21) | ((imm16 & 0xFFFF) << 5) | rd)

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
    nf = (c0 == 0xFFFF ? 1 : 0) + (c1 == 0xFFFF ? 1 : 0) + (c2 == 0xFFFF ? 1 : 0) + (c3 == 0xFFFF ? 1 : 0)
    nz = (c0 == 0 ? 1 : 0) + (c1 == 0 ? 1 : 0) + (c2 == 0 ? 1 : 0) + (c3 == 0 ? 1 : 0)
    if nf > nz
      first = true
      if c0 != 0xFFFF
        movn_x(rd, c0 ^ 0xFFFF, 0); first = false
      if c1 != 0xFFFF
        if first
          movn_x(rd, c1 ^ 0xFFFF, 1); first = false
        else
          movk_x(rd, c1, 1)
      if c2 != 0xFFFF
        if first
          movn_x(rd, c2 ^ 0xFFFF, 2); first = false
        else
          movk_x(rd, c2, 2)
      if c3 != 0xFFFF
        if first
          movn_x(rd, c3 ^ 0xFFFF, 3); first = false
        else
          movk_x(rd, c3, 3)
      movn_x(rd, 0, 0) if first
    else
      first = true
      if c0 != 0
        movz_x(rd, c0, 0); first = false
      if c1 != 0
        if first
          movz_x(rd, c1, 1); first = false
        else
          movk_x(rd, c1, 1)
      if c2 != 0
        if first
          movz_x(rd, c2, 2); first = false
        else
          movk_x(rd, c2, 2)
      if c3 != 0
        if first
          movz_x(rd, c3, 3); first = false
        else
          movk_x(rd, c3, 3)
      movz_x(rd, 0, 0) if first
    nil

  -> mov_imm32(rd, v)
    u = v & 0xFFFFFFFF
    lo = u & 0xFFFF
    hi = (u >> 16) & 0xFFFF
    if hi == 0
      emit(0x52800000 | (lo << 5) | rd)
    elsif hi == 0xFFFF
      emit(0x12800000 | ((lo ^ 0xFFFF) << 5) | rd)
    else
      emit(0x52800000 | (lo << 5) | rd)
      emit(0x72A00000 | (hi << 5) | rd)
    nil

  # ---- 64-bit & Arbitrary-Offset SP Arithmetic ----

  -> add_i(rd, rn, imm12, sh = 0)
    emit(0x91000000 | (sh << 22) | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)

  -> sub_i(rd, rn, imm12, sh = 0)
    emit(0xD1000000 | (sh << 22) | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)

  # Add arbitrary signed 64-bit constant to `rn` (supports SP as `rn` and/or `rd`!).
  -> add_sp_imm(rd, rn, delta, scratch = 16)
    if delta == 0
      mov_sp(rd, rn) if rd != rn
      return nil
    if delta < 0
      return sub_sp_imm(rd, rn, 0 - delta, scratch)
    if delta <= 4095
      add_i(rd, rn, delta, 0)
    elsif delta <= 16777215
      hi = (delta >> 12) & 0xFFF
      lo = delta & 0xFFF
      if hi != 0 && lo != 0
        add_i(rd, rn, hi, 1)
        add_i(rd, rd, lo, 0)
      elsif hi != 0
        add_i(rd, rn, hi, 1)
      else
        add_i(rd, rn, lo, 0)
    else
      mov_imm64(scratch, delta)
      # ADD (extended register): 0x8B206000 (UXTX #0) supports SP as rd/rn!
      emit(0x8B206000 | (scratch << 16) | (rn << 5) | rd)
    nil

  -> sub_sp_imm(rd, rn, delta, scratch = 16)
    if delta == 0
      mov_sp(rd, rn) if rd != rn
      return nil
    if delta < 0
      return add_sp_imm(rd, rn, 0 - delta, scratch)
    if delta <= 4095
      sub_i(rd, rn, delta, 0)
    elsif delta <= 16777215
      hi = (delta >> 12) & 0xFFF
      lo = delta & 0xFFF
      if hi != 0 && lo != 0
        sub_i(rd, rn, hi, 1)
        sub_i(rd, rd, lo, 0)
      elsif hi != 0
        sub_i(rd, rn, hi, 1)
      else
        sub_i(rd, rn, lo, 0)
    else
      mov_imm64(scratch, delta)
      emit(0xCB206000 | (scratch << 16) | (rn << 5) | rd)
    nil

  -> adds_i(rd, rn, imm12, sh = 0)
    emit(0xB1000000 | (sh << 22) | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)
  -> subs_i(rd, rn, imm12, sh = 0)
    emit(0xF1000000 | (sh << 22) | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)
  -> cmp_i(rn, imm12, sh = 0)
    subs_i(R_XZR, rn, imm12, sh)
  -> cmn_i(rn, imm12, sh = 0)
    adds_i(R_XZR, rn, imm12, sh)

  # Shifted register: shift_type 0=LSL, 1=LSR, 2=ASR
  -> add_r(rd, rn, rm, shift = 0, stype = 0)
    emit(0x8B000000 | ((stype & 3) << 22) | (rm << 16) | ((shift & 63) << 10) | (rn << 5) | rd)
  -> sub_r(rd, rn, rm, shift = 0, stype = 0)
    emit(0xCB000000 | ((stype & 3) << 22) | (rm << 16) | ((shift & 63) << 10) | (rn << 5) | rd)
  -> adds_r(rd, rn, rm, shift = 0, stype = 0)
    emit(0xAB000000 | ((stype & 3) << 22) | (rm << 16) | ((shift & 63) << 10) | (rn << 5) | rd)
  -> subs_r(rd, rn, rm, shift = 0, stype = 0)
    emit(0xEB000000 | ((stype & 3) << 22) | (rm << 16) | ((shift & 63) << 10) | (rn << 5) | rd)
  -> cmp_r(rn, rm, shift = 0, stype = 0)
    subs_r(R_XZR, rn, rm, shift, stype)
  -> cmn_r(rn, rm, shift = 0, stype = 0)
    adds_r(R_XZR, rn, rm, shift, stype)

  # Carry arithmetic (essential for i128 & BigInt kernels!)
  -> adc_x(rd, rn, rm)
    emit(0x9A000000 | (rm << 16) | (rn << 5) | rd)
  -> adcs_x(rd, rn, rm)
    emit(0xBA000000 | (rm << 16) | (rn << 5) | rd)
  -> sbc_x(rd, rn, rm)
    emit(0xDA000000 | (rm << 16) | (rn << 5) | rd)
  -> sbcs_x(rd, rn, rm)
    emit(0xFA000000 | (rm << 16) | (rn << 5) | rd)
  -> ngc_x(rd, rm)
    sbc_x(rd, R_XZR, rm)

  -> mul_x(rd, rn, rm)
    emit(0x9B007C00 | (rm << 16) | (rn << 5) | rd)
  -> madd_x(rd, rn, rm, ra)
    emit(0x9B000000 | (rm << 16) | (ra << 10) | (rn << 5) | rd)
  -> msub_x(rd, rn, rm, ra)
    emit(0x9B008000 | (rm << 16) | (ra << 10) | (rn << 5) | rd)
  -> smulh_x(rd, rn, rm)
    emit(0x9B407C00 | (rm << 16) | (rn << 5) | rd)
  -> umulh_x(rd, rn, rm)
    emit(0x9BC07C00 | (rm << 16) | (rn << 5) | rd)
  -> sdiv_x(rd, rn, rm)
    emit(0x9AC00C00 | (rm << 16) | (rn << 5) | rd)
  -> udiv_x(rd, rn, rm)
    emit(0x9AC00800 | (rm << 16) | (rn << 5) | rd)
  -> neg_x(rd, rm)
    sub_r(rd, R_XZR, rm)
  -> negs_x(rd, rm)
    subs_r(rd, R_XZR, rm)

  # 32-bit Integer Arithmetic
  -> add_wi(rd, rn, imm12)
    emit(0x11000000 | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)
  -> sub_wi(rd, rn, imm12)
    emit(0x51000000 | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)
  -> adds_wi(rd, rn, imm12)
    emit(0x31000000 | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)
  -> subs_wi(rd, rn, imm12)
    emit(0x71000000 | ((imm12 & 0xFFF) << 10) | (rn << 5) | rd)
  -> cmp_wi(rn, imm12)
    subs_wi(R_XZR, rn, imm12)
  -> add_w(rd, rn, rm, shift = 0)
    emit(0x0B000000 | (rm << 16) | ((shift & 31) << 10) | (rn << 5) | rd)
  -> sub_w(rd, rn, rm)
    emit(0x4B000000 | (rm << 16) | (rn << 5) | rd)
  -> adds_w(rd, rn, rm)
    emit(0x2B000000 | (rm << 16) | (rn << 5) | rd)
  -> subs_w(rd, rn, rm)
    emit(0x6B000000 | (rm << 16) | (rn << 5) | rd)
  -> cmp_w(rn, rm)
    subs_w(R_XZR, rn, rm)
  -> mul_w(rd, rn, rm)
    emit(0x1B007C00 | (rm << 16) | (rn << 5) | rd)
  -> madd_w(rd, rn, rm, ra)
    emit(0x1B000000 | (rm << 16) | (ra << 10) | (rn << 5) | rd)
  -> msub_w(rd, rn, rm, ra)
    emit(0x1B008000 | (rm << 16) | (ra << 10) | (rn << 5) | rd)
  -> sdiv_w(rd, rn, rm)
    emit(0x1AC00C00 | (rm << 16) | (rn << 5) | rd)
  -> udiv_w(rd, rn, rm)
    emit(0x1AC00800 | (rm << 16) | (rn << 5) | rd)
  -> neg_w(rd, rm)
    sub_w(rd, R_XZR, rm)
  -> negs_w(rd, rm)
    subs_w(rd, R_XZR, rm)

  # ---- Bitwise, Bitfields & Shifts ----

  -> and_r(rd, rn, rm, shift = 0, stype = 0)
    emit(0x8A000000 | ((stype & 3) << 22) | (rm << 16) | ((shift & 63) << 10) | (rn << 5) | rd)
  -> orr_r(rd, rn, rm, shift = 0, stype = 0)
    emit(0xAA000000 | ((stype & 3) << 22) | (rm << 16) | ((shift & 63) << 10) | (rn << 5) | rd)
  -> eor_r(rd, rn, rm, shift = 0, stype = 0)
    emit(0xCA000000 | ((stype & 3) << 22) | (rm << 16) | ((shift & 63) << 10) | (rn << 5) | rd)
  -> bic_r(rd, rn, rm)
    emit(0x8A200000 | (rm << 16) | (rn << 5) | rd)
  -> mvn_x(rd, rm, shift = 0, stype = 0)
    emit(0xAA2003E0 | ((stype & 3) << 22) | (rm << 16) | ((shift & 63) << 10) | rd)
  -> tst_r(rn, rm)
    emit(0xEA000000 | (rm << 16) | (rn << 5) | R_XZR)

  -> and_w(rd, rn, rm)
    emit(0x0A000000 | (rm << 16) | (rn << 5) | rd)
  -> orr_w(rd, rn, rm)
    emit(0x2A000000 | (rm << 16) | (rn << 5) | rd)
  -> eor_w(rd, rn, rm)
    emit(0x4A000000 | (rm << 16) | (rn << 5) | rd)
  -> mvn_w(rd, rm)
    emit(0x2A2003E0 | (rm << 16) | rd)
  -> tst_w(rn, rm)
    emit(0x6A000000 | (rm << 16) | (rn << 5) | R_XZR)

  -> and_xi(rd, rn, imm_val, scratch = 17)
    enc = a64_encode_bitmask_imm(imm_val, 64)
    if enc >= 0
      emit(0x92000000 | (enc << 10) | (rn << 5) | rd)
    else
      mov_imm64(scratch, imm_val)
      and_r(rd, rn, scratch)
    nil

  -> orr_xi(rd, rn, imm_val, scratch = 17)
    enc = a64_encode_bitmask_imm(imm_val, 64)
    if enc >= 0
      emit(0xB2000000 | (enc << 10) | (rn << 5) | rd)
    else
      mov_imm64(scratch, imm_val)
      orr_r(rd, rn, scratch)
    nil

  -> eor_xi(rd, rn, imm_val, scratch = 17)
    enc = a64_encode_bitmask_imm(imm_val, 64)
    if enc >= 0
      emit(0xD2000000 | (enc << 10) | (rn << 5) | rd)
    else
      mov_imm64(scratch, imm_val)
      eor_r(rd, rn, scratch)
    nil

  -> and_x_ptr47(rd, rn)
    emit(0x927CA800 | (rn << 5) | rd)

  -> lsl_w(rd, rn, rm)
    emit(0x1AC02000 | (rm << 16) | (rn << 5) | rd)
  -> lsr_w(rd, rn, rm)
    emit(0x1AC02400 | (rm << 16) | (rn << 5) | rd)
  -> asr_w(rd, rn, rm)
    emit(0x1AC02800 | (rm << 16) | (rn << 5) | rd)
  -> lsl_x(rd, rn, rm)
    emit(0x9AC02000 | (rm << 16) | (rn << 5) | rd)
  -> lsr_x(rd, rn, rm)
    emit(0x9AC02400 | (rm << 16) | (rn << 5) | rd)
  -> asr_x(rd, rn, rm)
    emit(0x9AC02800 | (rm << 16) | (rn << 5) | rd)

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

  -> sxtb_x(rd, rn)
    emit(0x93401C00 | (rn << 5) | rd)
  -> sxth_x(rd, rn)
    emit(0x93403C00 | (rn << 5) | rd)
  -> sxtw(rd, rn)
    emit(0x93407C00 | (rn << 5) | rd)
  -> uxtb_x(rd, rn)
    emit(0x53001C00 | (rn << 5) | rd)
  -> uxth_x(rd, rn)
    emit(0x53003C00 | (rn << 5) | rd)
  -> uxtw(rd, rn)
    mov_w(rd, rn)

  # SBFX Xd, Xn, #lsb, #width  (SBFM Xd, Xn, #lsb, #(lsb + width - 1))
  -> sbfx_x(rd, rn, lsb, width)
    imms = (lsb + width - 1) & 63
    emit(0x93400000 | ((lsb & 63) << 16) | (imms << 10) | (rn << 5) | rd)

  # EXTR Xd, Xn, Xm, #lsb
  -> extr_x(rd, rn, rm, lsb)
    emit(0x93C00000 | (rm << 16) | ((lsb & 63) << 10) | (rn << 5) | rd)

  -> clz_x(rd, rn)
    emit(0xDAC01000 | (rn << 5) | rd)
  -> clz_w(rd, rn)
    emit(0x5AC01000 | (rn << 5) | rd)
  -> ctz_x(rd, rn)
    emit(0xDAC01800 | (rn << 5) | rd)
  -> ctz_w(rd, rn)
    emit(0x5AC01800 | (rn << 5) | rd)
  -> rbit_x(rd, rn)
    emit(0xDAC00000 | (rn << 5) | rd)

  # ARMv8.9 CSSC UMIN
  -> umin_xi(rd, rn, imm8)
    emit(0x91CC0000 | ((imm8 & 0xFF) << 10) | (rn << 5) | rd)
  -> umin_xr(rd, rn, rm)
    emit(0x9AC06C00 | (rm << 16) | (rn << 5) | rd)

  # ---- Conditional Select / Compare ----

  -> cset(rd, cc)
    emit(0x9A9F07E0 | ((cc ^ 1) << 12) | rd)
  -> cset_w(rd, cc)
    emit(0x1A9F07E0 | ((cc ^ 1) << 12) | rd)
  -> csel_x(rd, rn, rm, cc)
    emit(0x9A800000 | (rm << 16) | (cc << 12) | (rn << 5) | rd)
  -> csel_w(rd, rn, rm, cc)
    emit(0x1A800000 | (rm << 16) | (cc << 12) | (rn << 5) | rd)
  -> csinc_x(rd, rn, rm, cc)
    emit(0x9A800400 | (rm << 16) | (cc << 12) | (rn << 5) | rd)
  -> csinc_w(rd, rn, rm, cc)
    emit(0x1A800400 | (rm << 16) | (cc << 12) | (rn << 5) | rd)
  -> csinv_x(rd, rn, rm, cc)
    emit(0xDA800000 | (rm << 16) | (cc << 12) | (rn << 5) | rd)
  -> csinv_w(rd, rn, rm, cc)
    emit(0x5A800000 | (rm << 16) | (cc << 12) | (rn << 5) | rd)
  -> csneg_x(rd, rn, rm, cc)
    emit(0xDA800400 | (rm << 16) | (cc << 12) | (rn << 5) | rd)
  -> csneg_w(rd, rn, rm, cc)
    emit(0x5A800400 | (rm << 16) | (cc << 12) | (rn << 5) | rd)
  -> cinc_x(rd, rn, cc)
    csinc_x(rd, rn, rn, cc ^ 1)
  -> cinc_w(rd, rn, cc)
    csinc_w(rd, rn, rn, cc ^ 1)
  -> cinv_x(rd, rn, cc)
    csinv_x(rd, rn, rn, cc ^ 1)
  -> cinv_w(rd, rn, cc)
    csinv_w(rd, rn, rn, cc ^ 1)
  -> cneg_x(rd, rn, cc)
    csneg_x(rd, rn, rn, cc ^ 1)
  -> cneg_w(rd, rn, cc)
    csneg_w(rd, rn, rn, cc ^ 1)
  -> ccmp_xr(rn, rm, nzcv, cc)
    emit(0xFA400000 | (rm << 16) | ((cc & 15) << 12) | (rn << 5) | (nzcv & 15))
  -> ccmp_xi(rn, imm5, nzcv, cc)
    emit(0xFA400800 | ((imm5 & 31) << 16) | ((cc & 15) << 12) | (rn << 5) | (nzcv & 15))

  # ---- Scalar Floating-Point ----

  -> fmov_d_x(dd, rn)
    emit(0x9E670000 | (rn << 5) | dd)
  -> fmov_x_d(rd, dn)
    emit(0x9E660000 | (dn << 5) | rd)
  -> fmov_s_w(sd, rn)
    emit(0x1E270000 | (rn << 5) | sd)
  -> fmov_w_s(rd, sn)
    emit(0x1E260000 | (sn << 5) | rd)
  -> fmov_d(dd, dn)
    return nil if dd == dn
    emit(0x1E604000 | (dn << 5) | dd)

  -> fadd_d(dd, dn, dm)
    emit(0x1E602800 | (dm << 16) | (dn << 5) | dd)
  -> fsub_d(dd, dn, dm)
    emit(0x1E603800 | (dm << 16) | (dn << 5) | dd)
  -> fmul_d(dd, dn, dm)
    emit(0x1E600800 | (dm << 16) | (dn << 5) | dd)
  -> fdiv_d(dd, dn, dm)
    emit(0x1E601800 | (dm << 16) | (dn << 5) | dd)
  -> fmadd_d(dd, dn, dm, da)
    emit(0x1F400000 | (dm << 16) | (da << 10) | (dn << 5) | dd)
  -> fmsub_d(dd, dn, dm, da)
    emit(0x1F408000 | (dm << 16) | (da << 10) | (dn << 5) | dd)
  -> fneg_d(dd, dn)
    emit(0x1E614000 | (dn << 5) | dd)
  -> fabs_d(dd, dn)
    emit(0x1E60C000 | (dn << 5) | dd)
  -> fsqrt_d(dd, dn)
    emit(0x1E61C000 | (dn << 5) | dd)
  -> frintm_d(dd, dn)
    emit(0x1E654000 | (dn << 5) | dd)
  -> frintp_d(dd, dn)
    emit(0x1E64C000 | (dn << 5) | dd)
  -> frintz_d(dd, dn)
    emit(0x1E65C000 | (dn << 5) | dd)
  -> frintn_d(dd, dn)
    emit(0x1E644000 | (dn << 5) | dd)
  -> fmin_d(dd, dn, dm)
    emit(0x1E605800 | (dm << 16) | (dn << 5) | dd)
  -> fmax_d(dd, dn, dm)
    emit(0x1E604800 | (dm << 16) | (dn << 5) | dd)
  -> fcmp_d(dn, dm)
    emit(0x1E602000 | (dm << 16) | (dn << 5))
  -> fcmp_d0(dn)
    emit(0x1E602008 | (dn << 5))
  -> fcsel_d(dd, dn, dm, cc)
    emit(0x1E600C00 | (dm << 16) | (cc << 12) | (dn << 5) | dd)

  -> scvtf_d_w(dd, rn)
    emit(0x1E620000 | (rn << 5) | dd)
  -> scvtf_d_x(dd, rn)
    emit(0x9E620000 | (rn << 5) | dd)
  -> ucvtf_d_w(dd, rn)
    emit(0x1E630000 | (rn << 5) | dd)
  -> ucvtf_d_x(dd, rn)
    emit(0x9E630000 | (rn << 5) | dd)
  -> fcvtzs_w_d(rd, dn)
    emit(0x1E780000 | (dn << 5) | rd)
  -> fcvtzs_x_d(rd, dn)
    emit(0x9E780000 | (dn << 5) | rd)
  -> fcvtzu_w_d(rd, dn)
    emit(0x1E790000 | (dn << 5) | rd)
  -> fcvtzu_x_d(rd, dn)
    emit(0x9E790000 | (dn << 5) | rd)
  -> fcvt_d_s(dd, sn)
    emit(0x1E22C000 | (sn << 5) | dd)
  -> fcvt_s_d(sd, dn)
    emit(0x1E624000 | (dn << 5) | sd)
  -> fcvt_d_h(dd, hn)
    emit(0x1EE2C000 | (hn << 5) | dd)
  -> fcvt_h_d(hd, dn)
    emit(0x1E63C000 | (dn << 5) | hd)

  # ---- Loads & Stores (with automatic large-offset fallback!) ----

  -> ldr_x(rt, rn, off = 0, scratch = 17)
    if off >= 0 && (off & 7) == 0 && off <= 32760
      emit(0xF9400000 | ((off >> 3) << 10) | (rn << 5) | rt)
    elsif off >= -256 && off <= 255
      emit(0xF8400000 | ((off & 0x1FF) << 12) | (rn << 5) | rt)
    else
      addr_r = scratch == rn ? (scratch == 17 ? 16 : 17) : scratch
      add_sp_imm(addr_r, rn, off, addr_r)
      emit(0xF9400000 | (addr_r << 5) | rt)
    nil

  -> str_x(rt, rn, off = 0, scratch = 17)
    if off >= 0 && (off & 7) == 0 && off <= 32760
      emit(0xF9000000 | ((off >> 3) << 10) | (rn << 5) | rt)
    elsif off >= -256 && off <= 255
      emit(0xF8000000 | ((off & 0x1FF) << 12) | (rn << 5) | rt)
    else
      addr_r = (scratch == rt || scratch == rn) ? (rt != 16 && rn != 16 ? 16 : 15) : scratch
      add_sp_imm(addr_r, rn, off, addr_r)
      emit(0xF9000000 | (addr_r << 5) | rt)
    nil

  -> ldr_x_post(rt, rn, simm9)
    emit(0xF8400400 | ((simm9 & 0x1FF) << 12) | (rn << 5) | rt)
  -> ldr_x_pre(rt, rn, simm9)
    emit(0xF8400C00 | ((simm9 & 0x1FF) << 12) | (rn << 5) | rt)
  -> str_x_post(rt, rn, simm9)
    emit(0xF8000400 | ((simm9 & 0x1FF) << 12) | (rn << 5) | rt)
  -> str_x_pre(rt, rn, simm9)
    emit(0xF8000C00 | ((simm9 & 0x1FF) << 12) | (rn << 5) | rt)

  -> ldr_w(rt, rn, off = 0, scratch = 17)
    if off >= 0 && (off & 3) == 0 && off <= 16380
      emit(0xB9400000 | ((off >> 2) << 10) | (rn << 5) | rt)
    elsif off >= -256 && off <= 255
      emit(0xB8400000 | ((off & 0x1FF) << 12) | (rn << 5) | rt)
    else
      addr_r = scratch == rn ? 16 : scratch
      add_sp_imm(addr_r, rn, off, addr_r)
      emit(0xB9400000 | (addr_r << 5) | rt)
    nil

  -> str_w(rt, rn, off = 0, scratch = 17)
    if off >= 0 && (off & 3) == 0 && off <= 16380
      emit(0xB9000000 | ((off >> 2) << 10) | (rn << 5) | rt)
    elsif off >= -256 && off <= 255
      emit(0xB8000000 | ((off & 0x1FF) << 12) | (rn << 5) | rt)
    else
      addr_r = (scratch == rt || scratch == rn) ? (rt != 16 && rn != 16 ? 16 : 15) : scratch
      add_sp_imm(addr_r, rn, off, addr_r)
      emit(0xB9000000 | (addr_r << 5) | rt)
    nil

  -> ldrsw(rt, rn, off = 0, scratch = 17)
    if off >= 0 && (off & 3) == 0 && off <= 16380
      emit(0xB9800000 | ((off >> 2) << 10) | (rn << 5) | rt)
    elsif off >= -256 && off <= 255
      emit(0xB8800000 | ((off & 0x1FF) << 12) | (rn << 5) | rt)
    else
      addr_r = scratch == rn ? 16 : scratch
      add_sp_imm(addr_r, rn, off, addr_r)
      emit(0xB9800000 | (addr_r << 5) | rt)
    nil

  -> ldrh(rt, rn, off = 0, scratch = 17)
    if off >= 0 && (off & 1) == 0 && off <= 8190
      emit(0x79400000 | ((off >> 1) << 10) | (rn << 5) | rt)
    elsif off >= -256 && off <= 255
      emit(0x78400000 | ((off & 0x1FF) << 12) | (rn << 5) | rt)
    else
      addr_r = scratch == rn ? 16 : scratch
      add_sp_imm(addr_r, rn, off, addr_r)
      emit(0x79400000 | (addr_r << 5) | rt)
    nil

  -> strh(rt, rn, off = 0, scratch = 17)
    if off >= 0 && (off & 1) == 0 && off <= 8190
      emit(0x79000000 | ((off >> 1) << 10) | (rn << 5) | rt)
    elsif off >= -256 && off <= 255
      emit(0x78000000 | ((off & 0x1FF) << 12) | (rn << 5) | rt)
    else
      addr_r = (scratch == rt || scratch == rn) ? (rt != 16 && rn != 16 ? 16 : 15) : scratch
      add_sp_imm(addr_r, rn, off, addr_r)
      emit(0x79000000 | (addr_r << 5) | rt)
    nil

  -> ldrb(rt, rn, off = 0, scratch = 17)
    if off >= 0 && off <= 4095
      emit(0x39400000 | (off << 10) | (rn << 5) | rt)
    elsif off >= -256 && off <= 255
      emit(0x38400000 | ((off & 0x1FF) << 12) | (rn << 5) | rt)
    else
      addr_r = scratch == rn ? 16 : scratch
      add_sp_imm(addr_r, rn, off, addr_r)
      emit(0x39400000 | (addr_r << 5) | rt)
    nil

  -> strb(rt, rn, off = 0, scratch = 17)
    if off >= 0 && off <= 4095
      emit(0x39000000 | (off << 10) | (rn << 5) | rt)
    elsif off >= -256 && off <= 255
      emit(0x38000000 | ((off & 0x1FF) << 12) | (rn << 5) | rt)
    else
      addr_r = (scratch == rt || scratch == rn) ? (rt != 16 && rn != 16 ? 16 : 15) : scratch
      add_sp_imm(addr_r, rn, off, addr_r)
      emit(0x39000000 | (addr_r << 5) | rt)
    nil

  -> ldr_d(dt, rn, off = 0, scratch = 17)
    if off >= 0 && (off & 7) == 0 && off <= 32760
      emit(0xFD400000 | ((off >> 3) << 10) | (rn << 5) | dt)
    elsif off >= -256 && off <= 255
      emit(0xFC400000 | ((off & 0x1FF) << 12) | (rn << 5) | dt)
    else
      add_sp_imm(scratch, rn, off, scratch)
      emit(0xFD400000 | (scratch << 5) | dt)
    nil

  -> str_d(dt, rn, off = 0, scratch = 17)
    if off >= 0 && (off & 7) == 0 && off <= 32760
      emit(0xFD000000 | ((off >> 3) << 10) | (rn << 5) | dt)
    elsif off >= -256 && off <= 255
      emit(0xFC000000 | ((off & 0x1FF) << 12) | (rn << 5) | dt)
    else
      add_sp_imm(scratch, rn, off, scratch)
      emit(0xFD000000 | (scratch << 5) | dt)
    nil

  # Scaled register-offset loads & stores
  -> ldr_x_idx(rt, rn, rm)
    emit(0xF8607800 | (rm << 16) | (rn << 5) | rt)
  -> ldr_x_reg(rt, rn, rm)
    emit(0xF8606800 | (rm << 16) | (rn << 5) | rt)
  -> str_x_idx(rt, rn, rm)
    emit(0xF8207800 | (rm << 16) | (rn << 5) | rt)
  -> str_x_reg(rt, rn, rm)
    emit(0xF8206800 | (rm << 16) | (rn << 5) | rt)
  -> ldr_d_idx(dt, rn, rm)
    emit(0xFC607800 | (rm << 16) | (rn << 5) | dt)
  -> str_d_idx(dt, rn, rm)
    emit(0xFC207800 | (rm << 16) | (rn << 5) | dt)
  -> ldr_s_idx(st, rn, rm)
    emit(0xBC607800 | (rm << 16) | (rn << 5) | st)
  -> str_s_idx(st, rn, rm)
    emit(0xBC207800 | (rm << 16) | (rn << 5) | st)
  -> ldr_h_idx(ht, rn, rm)
    emit(0x7C607800 | (rm << 16) | (rn << 5) | ht)
  -> str_h_idx(ht, rn, rm)
    emit(0x7C207800 | (rm << 16) | (rn << 5) | ht)
  -> ldrsw_idx(rt, rn, rm)
    emit(0xB8A07800 | (rm << 16) | (rn << 5) | rt)
  -> ldr_w_idx(rt, rn, rm)
    emit(0xB8607800 | (rm << 16) | (rn << 5) | rt)
  -> str_w_idx(rt, rn, rm)
    emit(0xB8207800 | (rm << 16) | (rn << 5) | rt)
  -> ldrb_idx(rt, rn, rm)
    emit(0x38606800 | (rm << 16) | (rn << 5) | rt)
  -> strb_idx(rt, rn, rm)
    emit(0x38206800 | (rm << 16) | (rn << 5) | rt)
  -> ldrsb_idx(rt, rn, rm)
    emit(0x38E06800 | (rm << 16) | (rn << 5) | rt)
  -> ldrh_idx(rt, rn, rm)
    emit(0x78607800 | (rm << 16) | (rn << 5) | rt)
  -> ldrsh_idx(rt, rn, rm)
    emit(0x78E07800 | (rm << 16) | (rn << 5) | rt)
  -> strh_idx(rt, rn, rm)
    emit(0x78207800 | (rm << 16) | (rn << 5) | rt)

  # Load/Store pairs
  -> stp_x(rt1, rt2, rn, off = 0)
    emit(0xA9000000 | (((off >> 3) & 0x7F) << 15) | (rt2 << 10) | (rn << 5) | rt1)
  -> ldp_x(rt1, rt2, rn, off = 0)
    emit(0xA9400000 | (((off >> 3) & 0x7F) << 15) | (rt2 << 10) | (rn << 5) | rt1)
  -> stp_pre(rt1, rt2, rn, off)
    emit(0xA9800000 | (((off >> 3) & 0x7F) << 15) | (rt2 << 10) | (rn << 5) | rt1)
  -> stp_post(rt1, rt2, rn, off)
    emit(0xA8800000 | (((off >> 3) & 0x7F) << 15) | (rt2 << 10) | (rn << 5) | rt1)
  -> ldp_post(rt1, rt2, rn, off)
    emit(0xA8C00000 | (((off >> 3) & 0x7F) << 15) | (rt2 << 10) | (rn << 5) | rt1)
  -> stp_d(dt1, dt2, rn, off = 0)
    emit(0x6D000000 | (((off >> 3) & 0x7F) << 15) | (dt2 << 10) | (rn << 5) | dt1)
  -> ldp_d(dt1, dt2, rn, off = 0)
    emit(0x6D400000 | (((off >> 3) & 0x7F) << 15) | (dt2 << 10) | (rn << 5) | dt1)

  # ---- Control Flow ----

  -> b(lbl)
    add_fix(lbl, FX_A64_B26)
    emit(0x14000000)

  -> bl(lbl)
    add_fix(lbl, FX_A64_B26)
    emit(0x94000000)

  -> adr(rd, lbl)
    add_fix(lbl, FX_A64_ADR)
    emit(0x10000000 | rd)

  -> b_cond(cc, lbl)
    add_fix(lbl, FX_A64_B19)
    emit(0x54000000 | cc)

  # Far conditional branch (±128 MB range via inverted skip + B26)
  -> b_cond_far(cc, lbl)
    emit(0x54000040 | (cc ^ 1))
    b(lbl)

  -> cbz_x(rt, lbl)
    add_fix(lbl, FX_A64_B19)
    emit(0xB4000000 | rt)
  -> cbnz_x(rt, lbl)
    add_fix(lbl, FX_A64_B19)
    emit(0xB5000000 | rt)
  -> cbz_w(rt, lbl)
    add_fix(lbl, FX_A64_B19)
    emit(0x34000000 | rt)
  -> cbnz_w(rt, lbl)
    add_fix(lbl, FX_A64_B19)
    emit(0x35000000 | rt)

  -> cbnz_x_far(rt, lbl)
    emit(0xB4000040 | rt)
    b(lbl)

  -> tbz(rt, bit, lbl)
    add_fix(lbl, FX_A64_B14)
    b5 = (bit >> 5) & 1
    b40 = bit & 31
    emit(0x36000000 | (b5 << 31) | (b40 << 19) | rt)

  -> tbnz(rt, bit, lbl)
    add_fix(lbl, FX_A64_B14)
    b5 = (bit >> 5) & 1
    b40 = bit & 31
    emit(0x37000000 | (b5 << 31) | (b40 << 19) | rt)

  -> blr(rn)
    emit(0xD63F0000 | (rn << 5))
  -> br(rn)
    emit(0xD61F0000 | (rn << 5))
  -> ret
    emit(0xD65F03C0)
  -> brk(imm16 = 1)
    emit(0xD4200000 | ((imm16 & 0xFFFF) << 5))
  -> nop
    emit(0xD503201F)

  -> call_abs(tmp_reg, addr)
    mov_imm64(tmp_reg, addr)
    blr(tmp_reg)

  # ---- 128-bit NEON SIMD ----

  -> ldr_q(qt, rn, uoff = 0)
    emit(0x3DC00000 | ((uoff >> 4) << 10) | (rn << 5) | qt)
  -> str_q(qt, rn, uoff = 0)
    emit(0x3D800000 | ((uoff >> 4) << 10) | (rn << 5) | qt)
  -> ldur_q(qt, rn, simm9)
    emit(0x3CC00000 | ((simm9 & 0x1FF) << 12) | (rn << 5) | qt)
  -> stur_q(qt, rn, simm9)
    emit(0x3C800000 | ((simm9 & 0x1FF) << 12) | (rn << 5) | qt)
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
  -> ld4_16b_post(vt, rn)
    emit(0x4CDF0000 | (rn << 5) | vt)

  -> movi_zero_16b(vd)
    emit(0x4F00E400 | vd)
  -> dup_2d_g(vd, rn)
    emit(0x4E080C00 | (rn << 5) | vd)
  -> dup_4s_g(vd, rn)
    emit(0x4E040C00 | (rn << 5) | vd)
  -> dup_16b_g(vd, rn)
    emit(0x4E010C00 | (rn << 5) | vd)
  -> dup_4s_elt0(vd, vn)
    emit(0x4E040400 | (vn << 5) | vd)
  -> dup_2d_elt0(vd, vn)
    emit(0x4E080400 | (vn << 5) | vd)
  -> umov_d_lane1(dd, vn)
    emit(0x5E180400 | (vn << 5) | dd)
  -> ins_h_elt(vd, dst_idx, vn)
    emit(0x6E020400 | ((dst_idx & 7) << 18) | (vn << 5) | vd)
  -> umov_w_s(rd, vn, idx)
    emit(0x0E043C00 | (idx << 19) | (vn << 5) | rd)

  -> cnt_8b(vd, vn)
    emit(0x0E205800 | (vn << 5) | vd)
  -> uaddlv_8b(hd, vn)
    emit(0x2E303800 | (vn << 5) | hd)

  -> neg_2d(vd, vn)
    emit(0x6EE0B800 | (vn << 5) | vd)
  -> orr_16b(vd, vn, vm)
    emit(0x4EA01C00 | (vm << 16) | (vn << 5) | vd)
  -> and_16b(vd, vn, vm)
    emit(0x4E201C00 | (vm << 16) | (vn << 5) | vd)
  -> eor_16b(vd, vn, vm)
    emit(0x6E201C00 | (vm << 16) | (vn << 5) | vd)
  -> ushl_2d(vd, vn, vm)
    emit(0x6EE04400 | (vm << 16) | (vn << 5) | vd)

  -> fadd_2d(vd, vn, vm)
    emit(0x4E60D400 | (vm << 16) | (vn << 5) | vd)
  -> fmul_2d(vd, vn, vm)
    emit(0x6E60DC00 | (vm << 16) | (vn << 5) | vd)
  -> fmla_2d(vd, vn, vm)
    emit(0x4E60CC00 | (vm << 16) | (vn << 5) | vd)
  -> fcmgt_2d(vd, vn, vm)
    emit(0x6EE0E400 | (vm << 16) | (vn << 5) | vd)
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
