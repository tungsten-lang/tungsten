# cinder/x64 — Pure-Tungsten x86_64 (AMD64 / System V) machine-code assembler.
#
# Encodes variable-length x86_64 instructions into a ByteBuf, supporting:
#   1. In-process RWX JIT execution on Linux/macOS x86_64 (local rel32 fixups).
#   2. Ahead-of-time ELF64 relocatable object emission (PLT32, PC32, GOTPCREL,
#      64-bit absolute, and Local-Exec TLS %fs:0 + TPOFF32 relocations).

use ./buf
use ./jit_mem

# ---- x86_64 GPRs ----
X64_RAX = 0;  X64_RCX = 1;  X64_RDX = 2;  X64_RBX = 3
X64_RSP = 4;  X64_RBP = 5;  X64_RSI = 6;  X64_RDI = 7
X64_R8  = 8;  X64_R9  = 9;  X64_R10 = 10; X64_R11 = 11
X64_R12 = 12; X64_R13 = 13; X64_R14 = 14; X64_R15 = 15

# ---- XMM registers ----
X64_XMM0  = 0;  X64_XMM1  = 1;  X64_XMM2  = 2;  X64_XMM3  = 3
X64_XMM4  = 4;  X64_XMM5  = 5;  X64_XMM6  = 6;  X64_XMM7  = 7
X64_XMM8  = 8;  X64_XMM9  = 9;  X64_XMM10 = 10; X64_XMM11 = 11
X64_XMM12 = 12; X64_XMM13 = 13; X64_XMM14 = 14; X64_XMM15 = 15

# ---- Condition codes (matches Jcc / SETcc / CMOVcc low 4 bits) ----
XCC_O  = 0;  XCC_NO = 1
XCC_B  = 2;  XCC_AE = 3    # unsigned < (ULT), >= (UGE)
XCC_E  = 4;  XCC_NE = 5    # ==, !=
XCC_BE = 6;  XCC_A  = 7    # unsigned <= (ULE), > (UGT)
XCC_S  = 8;  XCC_NS = 9
XCC_P  = 10; XCC_NP = 11   # parity / unordered NaN
XCC_L  = 12; XCC_GE = 13   # signed < (SLT), >= (SGE)
XCC_LE = 14; XCC_G  = 15   # signed <= (SLE), > (SGT)

# ---- Internal fixups & ELF64 relocations ----
FX_X64_REL32      = 1

CREL_X64_64       = 1
CREL_X64_PC32     = 2
CREL_X64_PLT32    = 4
CREL_X64_GOTPCREL = 9
CREL_X64_TPOFF32  = 23

-> x64_fits_i8?(v)
  v >= -128 && v <= 127

-> x64_fits_i32?(v)
  v >= -2147483648 && v <= 2147483647

+ CinderX64
  rw :buf, :labels, :fix_off, :fix_lbl, :failed
  rw :rel_off, :rel_sym, :rel_kind, :rel_add

  -> new(init_bytes = 512)
    @buf = ByteBuf.new(init_bytes)
    @labels = []
    @fix_off = []
    @fix_lbl = []
    @rel_off = []
    @rel_sym = []
    @rel_kind = []
    @rel_add = []
    @failed = false

  -> byte_len
    @buf.len

  -> align_bytes(pow2)
    @buf.align_to(pow2, 0x90)
    nil

  -> new_label
    id = @labels.size()
    @labels.push(-1)
    id

  -> bind(lbl)
    @labels[lbl] = @buf.len
    nil

  -> add_fix32(lbl)
    @fix_off.push(@buf.len)
    @fix_lbl.push(lbl)
    @buf.put_u32_le(0)
    nil

  -> add_reloc(sym, kind, addend = 0)
    @rel_off.push(@buf.len)
    @rel_sym.push(sym)
    @rel_kind.push(kind)
    @rel_add.push(addend)
    nil

  -> patch_fixups
    return false if @failed
    i = 0
    n = @fix_off.size()
    while i < n
      off = @fix_off[i]
      lbl = @fix_lbl[i]
      tgt = @labels[lbl]
      if tgt < 0
        @failed = true
        return false
      # rel32 is relative to the instruction END (off + 4)
      rel = tgt - (off + 4)
      @buf.patch_u32_le(off, rel)
      i += 1
    true

  -> finalize
    return 0 if !patch_fixups()
    cinder_jit_emit_buf(@buf)

  # ---- Low-level REX / ModRM / SIB helpers ----

  -> emit_rex(w, r_reg, x_reg, b_reg, force_rex = false)
    rw_b = w ? 8 : 0
    rr_b = (r_reg >= 8) ? 4 : 0
    rx_b = (x_reg >= 8) ? 2 : 0
    rb_b = (b_reg >= 8) ? 1 : 0
    bits = rw_b | rr_b | rx_b | rb_b
    if bits != 0 || force_rex
      @buf.put_u8(0x40 | bits)
    nil

  -> emit_modrm_rr(reg, rm)
    @buf.put_u8(0xC0 | ((reg & 7) << 3) | (rm & 7))
    nil

  # Memory `[base + disp]` (handles RSP/R12 SIB 0x24 and RBP/R13 disp8 0x00!)
  -> emit_modrm_mem(reg, base, disp)
    b_lo = base & 7
    r_lo = reg & 7
    if disp == 0 && b_lo != 5
      @buf.put_u8((r_lo << 3) | b_lo)
      @buf.put_u8(0x24) if b_lo == 4
    elsif x64_fits_i8?(disp)
      @buf.put_u8(0x40 | (r_lo << 3) | b_lo)
      @buf.put_u8(0x24) if b_lo == 4
      @buf.put_u8(disp)
    else
      @buf.put_u8(0x80 | (r_lo << 3) | b_lo)
      @buf.put_u8(0x24) if b_lo == 4
      @buf.put_u32_le(disp)
    nil

  # Indexed memory `[base + idx * (1<<scale_sh) + disp]` (idx != RSP=4!)
  -> emit_modrm_sib(reg, base, idx, scale_sh, disp)
    b_lo = base & 7
    i_lo = idx & 7
    r_lo = reg & 7
    sib = ((scale_sh & 3) << 6) | (i_lo << 3) | b_lo
    if disp == 0 && b_lo != 5
      @buf.put_u8((r_lo << 3) | 4)
      @buf.put_u8(sib)
    elsif x64_fits_i8?(disp)
      @buf.put_u8(0x40 | (r_lo << 3) | 4)
      @buf.put_u8(sib)
      @buf.put_u8(disp)
    else
      @buf.put_u8(0x80 | (r_lo << 3) | 4)
      @buf.put_u8(sib)
      @buf.put_u32_le(disp)
    nil

  # ---- Stack & Prologue/Epilogue ----

  -> push_r(r)
    @buf.put_u8(0x41) if r >= 8
    @buf.put_u8(0x50 + (r & 7))
  -> pop_r(r)
    @buf.put_u8(0x41) if r >= 8
    @buf.put_u8(0x58 + (r & 7))
  -> ret
    @buf.put_u8(0xC3)
  -> ud2
    @buf.put_u8(0x0F); @buf.put_u8(0x0B)
  -> nop
    @buf.put_u8(0x90)

  # ---- GPR Moves & Immediates ----

  -> mov_rr(rd, rs)
    return nil if rd == rs
    emit_rex(true, rs, 0, rd)
    @buf.put_u8(0x89)
    emit_modrm_rr(rs, rd)

  -> mov_rr32(rd, rs)
    emit_rex(false, rs, 0, rd)
    @buf.put_u8(0x89)
    emit_modrm_rr(rs, rd)

  -> xchg_rr(ra, rb)
    return nil if ra == rb
    emit_rex(true, ra, 0, rb)
    @buf.put_u8(0x87)
    emit_modrm_rr(ra, rb)

  -> mov_imm64(rd, v)
    if v == 0
      # xor eax, eax (3 bytes, zero-extends to 64-bit!)
      emit_rex(false, rd, 0, rd)
      @buf.put_u8(0x31)
      emit_modrm_rr(rd, rd)
    elsif v > 0 && v <= 2147483647
      # mov r32, imm32 (5-6 bytes, zero-extends to 64-bit!)
      @buf.put_u8(0x41) if rd >= 8
      @buf.put_u8(0xB8 + (rd & 7))
      @buf.put_u32_le(v)
    elsif v >= -2147483648 && v < 0
      # mov r64, sign-extended imm32 (7 bytes)
      emit_rex(true, 0, 0, rd)
      @buf.put_u8(0xC7)
      emit_modrm_rr(0, rd)
      @buf.put_u32_le(v)
    else
      # movabs r64, imm64 (10 bytes)
      emit_rex(true, 0, 0, rd)
      @buf.put_u8(0xB8 + (rd & 7))
      @buf.put_u64_le(v)
    nil

  -> lea_mem(rd, base, disp)
    emit_rex(true, rd, 0, base)
    @buf.put_u8(0x8D)
    emit_modrm_mem(rd, base, disp)

  -> lea_sib(rd, base, idx, scale_sh, disp = 0)
    emit_rex(true, rd, idx, base)
    @buf.put_u8(0x8D)
    emit_modrm_sib(rd, base, idx, scale_sh, disp)

  # ---- Symbol Address & Call Helpers (for ELF64 .o) ----

  # Address of module-local/defined symbol (+ addend): `leaq sym+addend(%rip), rd`
  -> addr_sym_local(rd, sym, addend = 0)
    emit_rex(true, rd, 0, 0)
    @buf.put_u8(0x8D)
    @buf.put_u8(0x05 | ((rd & 7) << 3))
    add_reloc(sym, CREL_X64_PC32, addend - 4)
    @buf.put_u32_le(0)

  # Address of external global symbol via GOT (+ optional addend): `movq sym@GOTPCREL(%rip), rd`
  -> addr_sym_got(rd, sym, addend = 0)
    emit_rex(true, rd, 0, 0)
    @buf.put_u8(0x8B)
    @buf.put_u8(0x05 | ((rd & 7) << 3))
    add_reloc(sym, CREL_X64_GOTPCREL, -4)
    @buf.put_u32_le(0)
    add_ri(rd, addend) if addend != 0
    nil

  # Address of Local-Exec TLS symbol (`@.ic`, `@reuse.site.*`) on Linux x86_64:
  #   movq %fs:0, rd          (64 48/4C 8B /r 04 25 00 00 00 00)
  #   leaq sym@TPOFF32+addend(rd), rd
  -> addr_tls_linux(rd, sym, addend = 0)
    @buf.put_u8(0x64)
    emit_rex(true, rd, 0, 0)
    @buf.put_u8(0x8B)
    @buf.put_u8(0x04 | ((rd & 7) << 3))
    @buf.put_u8(0x25)
    @buf.put_u32_le(0)
    emit_rex(true, rd, 0, rd)
    @buf.put_u8(0x8D)
    @buf.put_u8(0x80 | ((rd & 7) << 3) | (rd & 7))
    @buf.put_u8(0x24) if (rd & 7) == 4
    add_reloc(sym, CREL_X64_TPOFF32, addend)
    @buf.put_u32_le(0)

  -> call_sym(sym)
    @buf.put_u8(0xE8)
    add_reloc(sym, CREL_X64_PLT32, -4)
    @buf.put_u32_le(0)

  -> call_r(rn)
    emit_rex(false, 0, 0, rn)
    @buf.put_u8(0xFF)
    emit_modrm_rr(2, rn)

  -> jmp_r(rn)
    emit_rex(false, 0, 0, rn)
    @buf.put_u8(0xFF)
    emit_modrm_rr(4, rn)

  -> call_abs(tmp_reg, addr)
    mov_imm64(tmp_reg, addr)
    call_r(tmp_reg)

  # ---- Memory Loads & Stores (base + disp & indexed SIB) ----

  -> load64(rd, base, disp = 0)
    emit_rex(true, rd, 0, base)
    @buf.put_u8(0x8B)
    emit_modrm_mem(rd, base, disp)

  -> store64(rs, base, disp = 0)
    emit_rex(true, rs, 0, base)
    @buf.put_u8(0x89)
    emit_modrm_mem(rs, base, disp)

  -> load32_zext(rd, base, disp = 0)
    emit_rex(false, rd, 0, base)
    @buf.put_u8(0x8B)
    emit_modrm_mem(rd, base, disp)

  -> load32_sext(rd, base, disp = 0)
    emit_rex(true, rd, 0, base)
    @buf.put_u8(0x63)
    emit_modrm_mem(rd, base, disp)

  -> store32(rs, base, disp = 0)
    emit_rex(false, rs, 0, base)
    @buf.put_u8(0x89)
    emit_modrm_mem(rs, base, disp)

  -> load16_zext(rd, base, disp = 0)
    emit_rex(false, rd, 0, base)
    @buf.put_u8(0x0F); @buf.put_u8(0xB7)
    emit_modrm_mem(rd, base, disp)

  -> load16_sext(rd, base, disp = 0)
    emit_rex(true, rd, 0, base)
    @buf.put_u8(0x0F); @buf.put_u8(0xBF)
    emit_modrm_mem(rd, base, disp)

  -> store16(rs, base, disp = 0)
    @buf.put_u8(0x66)
    emit_rex(false, rs, 0, base)
    @buf.put_u8(0x89)
    emit_modrm_mem(rs, base, disp)

  -> load8_zext(rd, base, disp = 0)
    emit_rex(false, rd, 0, base)
    @buf.put_u8(0x0F); @buf.put_u8(0xB6)
    emit_modrm_mem(rd, base, disp)

  -> load8_sext(rd, base, disp = 0)
    emit_rex(true, rd, 0, base)
    @buf.put_u8(0x0F); @buf.put_u8(0xBE)
    emit_modrm_mem(rd, base, disp)

  -> store8(rs, base, disp = 0)
    # Force REX when rs >= 4 so RSP..RDI map to SPL..DIL rather than AH..BH!
    emit_rex(false, rs, 0, base, rs >= 4)
    @buf.put_u8(0x88)
    emit_modrm_mem(rs, base, disp)

  # Indexed SIB loads/stores `[base + idx * (1<<scale_sh)]`
  -> load64_idx(rd, base, idx)
    emit_rex(true, rd, idx, base); @buf.put_u8(0x8B); emit_modrm_sib(rd, base, idx, 3, 0)
  -> store64_idx(rs, base, idx)
    emit_rex(true, rs, idx, base); @buf.put_u8(0x89); emit_modrm_sib(rs, base, idx, 3, 0)
  -> load32_zext_idx(rd, base, idx)
    emit_rex(false, rd, idx, base); @buf.put_u8(0x8B); emit_modrm_sib(rd, base, idx, 2, 0)
  -> load32_sext_idx(rd, base, idx)
    emit_rex(true, rd, idx, base); @buf.put_u8(0x63); emit_modrm_sib(rd, base, idx, 2, 0)
  -> store32_idx(rs, base, idx)
    emit_rex(false, rs, idx, base); @buf.put_u8(0x89); emit_modrm_sib(rs, base, idx, 2, 0)
  -> load16_zext_idx(rd, base, idx)
    emit_rex(false, rd, idx, base); @buf.put_u8(0x0F); @buf.put_u8(0xB7); emit_modrm_sib(rd, base, idx, 1, 0)
  -> load16_sext_idx(rd, base, idx)
    emit_rex(true, rd, idx, base); @buf.put_u8(0x0F); @buf.put_u8(0xBF); emit_modrm_sib(rd, base, idx, 1, 0)
  -> store16_idx(rs, base, idx)
    @buf.put_u8(0x66); emit_rex(false, rs, idx, base); @buf.put_u8(0x89); emit_modrm_sib(rs, base, idx, 1, 0)
  -> load8_zext_idx(rd, base, idx)
    emit_rex(false, rd, idx, base); @buf.put_u8(0x0F); @buf.put_u8(0xB6); emit_modrm_sib(rd, base, idx, 0, 0)
  -> load8_sext_idx(rd, base, idx)
    emit_rex(true, rd, idx, base); @buf.put_u8(0x0F); @buf.put_u8(0xBE); emit_modrm_sib(rd, base, idx, 0, 0)
  -> store8_idx(rs, base, idx)
    emit_rex(false, rs, idx, base, rs >= 4); @buf.put_u8(0x88); emit_modrm_sib(rs, base, idx, 0, 0)

  # ---- 64-bit & 32-bit Integer ALU ----

  -> alu_rr(op_rm_r, rd, rs, w64 = true)
    emit_rex(w64, rs, 0, rd)
    @buf.put_u8(op_rm_r)
    emit_modrm_rr(rs, rd)

  -> alu_ri(subop, rd, imm, w64 = true, scratch = 11)
    if x64_fits_i8?(imm)
      emit_rex(w64, 0, 0, rd)
      @buf.put_u8(0x83)
      emit_modrm_rr(subop, rd)
      @buf.put_u8(imm)
    elsif x64_fits_i32?(imm)
      emit_rex(w64, 0, 0, rd)
      @buf.put_u8(0x81)
      emit_modrm_rr(subop, rd)
      @buf.put_u32_le(imm)
    else
      mov_imm64(scratch, imm)
      # subop: 0=ADD(0x01), 1=OR(0x09), 2=ADC(0x11), 3=SBB(0x19), 4=AND(0x21), 5=SUB(0x29), 6=XOR(0x31), 7=CMP(0x39)
      alu_rr(subop * 8 + 1, rd, scratch, w64)
    nil

  -> add_rr(rd, rs)
    alu_rr(0x01, rd, rs, true)
  -> adc_rr(rd, rs)
    alu_rr(0x11, rd, rs, true)
  -> sub_rr(rd, rs)
    alu_rr(0x29, rd, rs, true)
  -> sbb_rr(rd, rs)
    alu_rr(0x19, rd, rs, true)
  -> add_load64(rd, base, disp = 0)
    emit_rex(true, rd, 0, base); @buf.put_u8(0x03); emit_modrm_mem(rd, base, disp)
  -> adc_load64(rd, base, disp = 0)
    emit_rex(true, rd, 0, base); @buf.put_u8(0x13); emit_modrm_mem(rd, base, disp)
  -> sbb_load64(rd, base, disp = 0)
    emit_rex(true, rd, 0, base); @buf.put_u8(0x1B); emit_modrm_mem(rd, base, disp)
  -> and_rr(rd, rs)
    alu_rr(0x21, rd, rs, true)
  -> or_rr(rd, rs)
    alu_rr(0x09, rd, rs, true)
  -> xor_rr(rd, rs)
    alu_rr(0x31, rd, rs, true)
  -> cmp_rr(ra, rb)
    alu_rr(0x39, ra, rb, true)
  -> test_rr(ra, rb)
    alu_rr(0x85, ra, rb, true)

  -> clc
    @buf.put_u8(0xF8)
  -> stc
    @buf.put_u8(0xF9)
  -> inc_r(rd)
    emit_rex(true, 0, 0, rd); @buf.put_u8(0xFF); emit_modrm_rr(0, rd)
  -> dec_r(rd)
    emit_rex(true, 0, 0, rd); @buf.put_u8(0xFF); emit_modrm_rr(1, rd)

  -> add_ri(rd, imm)
    return nil if imm == 0
    alu_ri(0, rd, imm, true)
  -> adc_ri(rd, imm)
    alu_ri(2, rd, imm, true)
  -> sub_ri(rd, imm)
    return nil if imm == 0
    alu_ri(5, rd, imm, true)
  -> sbb_ri(rd, imm)
    alu_ri(3, rd, imm, true)
  -> and_ri(rd, imm)
    alu_ri(4, rd, imm, true)
  -> or_ri(rd, imm)
    alu_ri(1, rd, imm, true)
  -> xor_ri(rd, imm)
    alu_ri(6, rd, imm, true)
  -> cmp_ri(ra, imm)
    alu_ri(7, ra, imm, true)

  -> add_rr32(rd, rs)
    alu_rr(0x01, rd, rs, false)
  -> sub_rr32(rd, rs)
    alu_rr(0x29, rd, rs, false)
  -> and_rr32(rd, rs)
    alu_rr(0x21, rd, rs, false)
  -> or_rr32(rd, rs)
    alu_rr(0x09, rd, rs, false)
  -> xor_rr32(rd, rs)
    alu_rr(0x31, rd, rs, false)
  -> cmp_rr32(ra, rb)
    alu_rr(0x39, ra, rb, false)

  -> neg_r(rd)
    emit_rex(true, 0, 0, rd); @buf.put_u8(0xF7); emit_modrm_rr(3, rd)
  -> not_r(rd)
    emit_rex(true, 0, 0, rd); @buf.put_u8(0xF7); emit_modrm_rr(2, rd)

  # IMUL rd, rs (2-operand 64-bit / 32-bit)
  -> imul_rr(rd, rs)
    emit_rex(true, rd, 0, rs)
    @buf.put_u8(0x0F); @buf.put_u8(0xAF)
    emit_modrm_rr(rd, rs)

  -> imul_rr32(rd, rs)
    emit_rex(false, rd, 0, rs)
    @buf.put_u8(0x0F); @buf.put_u8(0xAF)
    emit_modrm_rr(rd, rs)

  # 1-operand widening RDX:RAX = RAX * rm64 (signed IMUL / unsigned MUL)
  -> imul1_r(rm)
    emit_rex(true, 0, 0, rm); @buf.put_u8(0xF7); emit_modrm_rr(5, rm)
  -> mul1_r(rm)
    emit_rex(true, 0, 0, rm); @buf.put_u8(0xF7); emit_modrm_rr(4, rm)

  # 64-bit IDIV / DIV (divides RDX:RAX by rm64 -> quotient RAX, remainder RDX)
  -> cqo
    @buf.put_u8(0x48); @buf.put_u8(0x99)
  -> idiv_r(rm)
    emit_rex(true, 0, 0, rm); @buf.put_u8(0xF7); emit_modrm_rr(7, rm)
  -> div_r(rm)
    emit_rex(true, 0, 0, rm); @buf.put_u8(0xF7); emit_modrm_rr(6, rm)

  # ---- Shifts & Bit Extensions ----

  # Shift by imm8: subop 4=SHL, 5=SHR, 7=SAR
  -> shift_ri(subop, rd, sh, w64 = true)
    mask = w64 ? 63 : 31
    s = sh & mask
    return nil if s == 0 && w64
    emit_rex(w64, 0, 0, rd)
    if s == 1
      @buf.put_u8(0xD1)
      emit_modrm_rr(subop, rd)
    else
      @buf.put_u8(0xC1)
      emit_modrm_rr(subop, rd)
      @buf.put_u8(s)
    nil

  # Shift by CL (RCX low byte!)
  -> shift_cl(subop, rd, w64 = true)
    emit_rex(w64, 0, 0, rd)
    @buf.put_u8(0xD3)
    emit_modrm_rr(subop, rd)

  -> shl_ri(rd, sh)
    shift_ri(4, rd, sh, true)
  -> shr_ri(rd, sh)
    shift_ri(5, rd, sh, true)
  -> sar_ri(rd, sh)
    shift_ri(7, rd, sh, true)
  -> shl_cl(rd)
    shift_cl(4, rd, true)
  -> shr_cl(rd)
    shift_cl(5, rd, true)
  -> sar_cl(rd)
    shift_cl(7, rd, true)

  -> shl_ri32(rd, sh)
    shift_ri(4, rd, sh, false)
  -> shr_ri32(rd, sh)
    shift_ri(5, rd, sh, false)
  -> sar_ri32(rd, sh)
    shift_ri(7, rd, sh, false)
  -> shl_cl32(rd)
    shift_cl(4, rd, false)
  -> shr_cl32(rd)
    shift_cl(5, rd, false)
  -> sar_cl32(rd)
    shift_cl(7, rd, false)

  # Sign/Zero-extend register to 64-bit
  -> movsxd_32_64(rd, rs)
    emit_rex(true, rd, 0, rs); @buf.put_u8(0x63); emit_modrm_rr(rd, rs)
  -> movsx_16_64(rd, rs)
    emit_rex(true, rd, 0, rs); @buf.put_u8(0x0F); @buf.put_u8(0xBF); emit_modrm_rr(rd, rs)
  -> movsx_8_64(rd, rs)
    emit_rex(true, rd, 0, rs, rs >= 4); @buf.put_u8(0x0F); @buf.put_u8(0xBE); emit_modrm_rr(rd, rs)
  -> movzx_16_64(rd, rs)
    emit_rex(false, rd, 0, rs); @buf.put_u8(0x0F); @buf.put_u8(0xB7); emit_modrm_rr(rd, rs)
  -> movzx_8_64(rd, rs)
    emit_rex(false, rd, 0, rs, rs >= 4); @buf.put_u8(0x0F); @buf.put_u8(0xB6); emit_modrm_rr(rd, rs)

  # Baseline x86_64-v1 bit scans (BSF/BSR work on EVERY x86_64 CPU!)
  -> bsf_r(rd, rs)
    emit_rex(true, rd, 0, rs); @buf.put_u8(0x0F); @buf.put_u8(0xBC); emit_modrm_rr(rd, rs)
  -> bsr_r(rd, rs)
    emit_rex(true, rd, 0, rs); @buf.put_u8(0x0F); @buf.put_u8(0xBD); emit_modrm_rr(rd, rs)

  # ---- Conditional Set, Move & Branches ----

  # SETcc into low byte of `rd`, then zero-extend to 64-bit (`movzx rd, rd_b`)!
  -> setcc_zext(cc, rd)
    emit_rex(false, 0, 0, rd, rd >= 4)
    @buf.put_u8(0x0F)
    @buf.put_u8(0x90 | (cc & 15))
    emit_modrm_rr(0, rd)
    movzx_8_64(rd, rd)

  -> cmovcc(cc, rd, rs)
    emit_rex(true, rd, 0, rs)
    @buf.put_u8(0x0F)
    @buf.put_u8(0x40 | (cc & 15))
    emit_modrm_rr(rd, rs)

  -> jmp(lbl)
    @buf.put_u8(0xE9)
    add_fix32(lbl)

  -> jcc(cc, lbl)
    @buf.put_u8(0x0F)
    @buf.put_u8(0x80 | (cc & 15))
    add_fix32(lbl)

  # ---- SSE2 Scalar & Packed Floating-Point / Integer Vector Ops ----

  -> sse_op_rr(prefix, op2, xd, xs, rex_w = false)
    @buf.put_u8(prefix) if prefix != 0
    emit_rex(rex_w, xd, 0, xs)
    @buf.put_u8(0x0F)
    @buf.put_u8(op2)
    emit_modrm_rr(xd, xs)

  -> movsd_rr(xd, xs)
    return nil if xd == xs
    sse_op_rr(0xF2, 0x10, xd, xs)

  -> movsd_load(xd, base, disp = 0)
    @buf.put_u8(0xF2); emit_rex(false, xd, 0, base); @buf.put_u8(0x0F); @buf.put_u8(0x10); emit_modrm_mem(xd, base, disp)
  -> movsd_store(xs, base, disp = 0)
    @buf.put_u8(0xF2); emit_rex(false, xs, 0, base); @buf.put_u8(0x0F); @buf.put_u8(0x11); emit_modrm_mem(xs, base, disp)
  -> movsd_load_idx(xd, base, idx)
    @buf.put_u8(0xF2); emit_rex(false, xd, idx, base); @buf.put_u8(0x0F); @buf.put_u8(0x10); emit_modrm_sib(xd, base, idx, 3, 0)
  -> movsd_store_idx(xs, base, idx)
    @buf.put_u8(0xF2); emit_rex(false, xs, idx, base); @buf.put_u8(0x0F); @buf.put_u8(0x11); emit_modrm_sib(xs, base, idx, 3, 0)

  -> movss_load_idx(xd, base, idx)
    @buf.put_u8(0xF3); emit_rex(false, xd, idx, base); @buf.put_u8(0x0F); @buf.put_u8(0x10); emit_modrm_sib(xd, base, idx, 2, 0)
  -> movss_store_idx(xs, base, idx)
    @buf.put_u8(0xF3); emit_rex(false, xs, idx, base); @buf.put_u8(0x0F); @buf.put_u8(0x11); emit_modrm_sib(xs, base, idx, 2, 0)
  -> movss_load(xd, base, disp = 0)
    @buf.put_u8(0xF3); emit_rex(false, xd, 0, base); @buf.put_u8(0x0F); @buf.put_u8(0x10); emit_modrm_mem(xd, base, disp)
  -> movss_store(xs, base, disp = 0)
    @buf.put_u8(0xF3); emit_rex(false, xs, 0, base); @buf.put_u8(0x0F); @buf.put_u8(0x11); emit_modrm_mem(xs, base, disp)

  # Bitcast GPR <-> XMM (64-bit MOVQ / 32-bit MOVD)
  -> movq_x_r(xd, rs)
    sse_op_rr(0x66, 0x6E, xd, rs, true)
  -> movq_r_x(rd, xs)
    @buf.put_u8(0x66); emit_rex(true, xs, 0, rd); @buf.put_u8(0x0F); @buf.put_u8(0x7E); emit_modrm_rr(xs, rd)
  -> movd_x_r(xd, rs)
    sse_op_rr(0x66, 0x6E, xd, rs, false)
  -> movd_r_x(rd, xs)
    @buf.put_u8(0x66); emit_rex(false, xs, 0, rd); @buf.put_u8(0x0F); @buf.put_u8(0x7E); emit_modrm_rr(xs, rd)

  -> xorpd_rr(xd, xs)
    sse_op_rr(0x66, 0x57, xd, xs)
  -> orpd_rr(xd, xs)
    sse_op_rr(0x66, 0x56, xd, xs)
  -> andpd_rr(xd, xs)
    sse_op_rr(0x66, 0x54, xd, xs)
  -> addsd_rr(xd, xs)
    sse_op_rr(0xF2, 0x58, xd, xs)
  -> subsd_rr(xd, xs)
    sse_op_rr(0xF2, 0x5C, xd, xs)
  -> mulsd_rr(xd, xs)
    sse_op_rr(0xF2, 0x59, xd, xs)
  -> divsd_rr(xd, xs)
    sse_op_rr(0xF2, 0x5E, xd, xs)
  -> sqrtsd_rr(xd, xs)
    sse_op_rr(0xF2, 0x51, xd, xs)
  -> minsd_rr(xd, xs)
    sse_op_rr(0xF2, 0x5D, xd, xs)
  -> maxsd_rr(xd, xs)
    sse_op_rr(0xF2, 0x5F, xd, xs)
  -> ucomisd_rr(xa, xb)
    sse_op_rr(0x66, 0x2E, xa, xb)

  # Conversions
  -> cvtsi2sd_x_r64(xd, rs)
    sse_op_rr(0xF2, 0x2A, xd, rs, true)
  -> cvtsi2sd_x_r32(xd, rs)
    sse_op_rr(0xF2, 0x2A, xd, rs, false)
  -> cvttsd2si_r64_x(rd, xs)
    sse_op_rr(0xF2, 0x2C, rd, xs, true)
  -> cvttsd2si_r32_x(rd, xs)
    sse_op_rr(0xF2, 0x2C, rd, xs, false)
  -> cvtss2sd_rr(xd, xs)
    sse_op_rr(0xF3, 0x5A, xd, xs)
  -> cvtsd2ss_rr(xd, xs)
    sse_op_rr(0xF2, 0x5A, xd, xs)

  # SSE4.1 ROUNDSD (imm8: 9 = floor, 10 = ceil, 11 = trunc)
  -> roundsd_rr(xd, xs, mode)
    @buf.put_u8(0x66)
    emit_rex(false, xd, 0, xs)
    @buf.put_u8(0x0F); @buf.put_u8(0x3A); @buf.put_u8(0x0B)
    emit_modrm_rr(xd, xs)
    @buf.put_u8(mode & 0xFF)

  # 128-bit SSE2 Packed Ops (for x86_64 WIRE SIMD auto-vectorizer!)
  -> movups_load(xd, base, disp = 0)
    emit_rex(false, xd, 0, base); @buf.put_u8(0x0F); @buf.put_u8(0x10); emit_modrm_mem(xd, base, disp)
  -> movups_store(xs, base, disp = 0)
    emit_rex(false, xs, 0, base); @buf.put_u8(0x0F); @buf.put_u8(0x11); emit_modrm_mem(xs, base, disp)
  -> addpd_rr(xd, xs)
    sse_op_rr(0x66, 0x58, xd, xs)
  -> mulpd_rr(xd, xs)
    sse_op_rr(0x66, 0x59, xd, xs)
  -> cvtps2pd_rr(xd, xs)
    sse_op_rr(0, 0x5A, xd, xs)
  -> cvtpd2ps_rr(xd, xs)
    sse_op_rr(0x66, 0x5A, xd, xs)
  -> unpcklpd_rr(xd, xs)
    sse_op_rr(0x66, 0x14, xd, xs)
  -> unpckhpd_rr(xd, xs)
    sse_op_rr(0x66, 0x15, xd, xs)
  -> movhlps_rr(xd, xs)
    sse_op_rr(0, 0x12, xd, xs)
  -> movlhps_rr(xd, xs)
    sse_op_rr(0, 0x16, xd, xs)
