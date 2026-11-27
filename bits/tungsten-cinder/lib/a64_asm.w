# cinder/a64_asm — Pure-Tungsten ARM64 Text Assembler (for `module asm` & `call i64 asm`).
#
# Encodes all ARM64 instructions, NEON vector ops, CSSC `umin`, `.short` lookup tables,
# `.balign`/`.p2align`/`.globl` directives, named labels, directional numeric local labels
# (`1:`..`99:`, `1b`/`1f`), and Mach-O/ELF external relocations (`bl`, `b`, `@TLVPPAGE`,
# `@TLVPPAGEOFF`) used by Tungsten's `core/numeric/big_int/limb_kernels.w`.

use ./a64

-> a64_asm_parse_int(s)
  t = s.strip()
  t = t.slice(1, t.size() - 1).strip() if t.starts_with?("#")
  neg = false
  if t.starts_with?("-")
    neg = true
    t = t.slice(1, t.size() - 1)
  elsif t.starts_with?("+")
    t = t.slice(1, t.size() - 1)
  val = 0
  if t.starts_with?("0x") || t.starts_with?("0X")
    i = 2
    n = cinder_blen(t)
    while i < n
      b = t.byte_at(i)
      d = b >= 48 && b <= 57 ? (b - 48) : (b >= 97 && b <= 102 ? (b - 87) : (b >= 65 && b <= 70 ? (b - 55) : 0))
      val = (val << 4) | d
      i += 1
  else
    val = t.to_i()
  neg ? (0 - val) : val

# Returns [reg_num, kind] where kind is :x, :w, :q, :v, :sp, or nil
-> a64_asm_parse_reg(tok)
  t = tok.strip()
  return [31, :sp] if t == "sp"
  return [31, :x]  if t == "xzr"
  return [31, :w]  if t == "wzr"
  return [29, :x]  if t == "fp"
  return [30, :x]  if t == "lr"
  return nil if t.size() < 2
  c0 = t.byte_at(0)
  rest = t.slice(1, t.size() - 1)
  # Strip vector lane suffix like `v0.2d` or `v1.16b` if present
  dot = rest.index(".")
  rest = rest.slice(0, dot) if dot != nil
  b0 = rest.byte_at(0)
  return nil if b0 < 48 || b0 > 57
  rn = rest.to_i()
  return nil if rn < 0 || rn > 31
  return [rn, :x] if c0 == 120   # 'x'
  return [rn, :w] if c0 == 119   # 'w'
  return [rn, :q] if c0 == 113   # 'q'
  return [rn, :v] if c0 == 118   # 'v'
  return [rn, :d] if c0 == 100   # 'd'
  nil

-> a64_asm_parse_cc(s)
  t = s.strip().downcase()
  return CC_EQ if t == "eq"
  return CC_NE if t == "ne"
  return CC_HS if t == "hs" || t == "cs"
  return CC_LO if t == "lo" || t == "cc"
  return CC_MI if t == "mi"
  return CC_PL if t == "pl"
  return CC_VS if t == "vs"
  return CC_VC if t == "vc"
  return CC_HI if t == "hi"
  return CC_LS if t == "ls"
  return CC_GE if t == "ge"
  return CC_LT if t == "lt"
  return CC_GT if t == "gt"
  return CC_LE if t == "le"
  return CC_AL if t == "al"
  -1

# Split instruction operand string on top-level commas (not splitting inside `[...]`)
-> a64_asm_split_ops(s)
  out = []
  depth = 0
  start = 0
  i = 0
  n = cinder_blen(s)
  while i < n
    b = s.byte_at(i)
    if b == 91
      depth += 1
    elsif b == 93
      depth -= 1
    elsif b == 44 && depth == 0
      out.push(s.slice(start, i - start).strip())
      start = i + 1
    i += 1
  tail = s.slice(start, n - start).strip()
  out.push(tail) if tail != ""
  out

# Parse optional shift modifier token like `lsl #3`, `lsr #63`, `asr #1` -> [stype, amount]
-> a64_asm_parse_shift(tok)
  t = tok.strip()
  sp = t.index(" ")
  sp = t.index("\t") if sp == nil
  return [0, 0] if sp == nil
  kind = t.slice(0, sp).strip().downcase()
  amt = a64_asm_parse_int(t.slice(sp + 1, t.size() - sp - 1))
  return [0, amt] if kind == "lsl"
  return [1, amt] if kind == "lsr"
  return [2, amt] if kind == "asr"
  [0, amt]

# Unescape LLVM asm string (`\0A` -> `\n`, `\09` -> `\t`, `\\` -> `\`, `\22` -> `"`)
# and optionally substitute `${0:x}` / `${0:w}` .. `${9:x}` with register names!
-> a64_asm_unescape(raw, op_regs = nil)
  n = cinder_blen(raw)
  sb = StringBuffer(n + 16)
  i = 0
  while i < n
    b = raw.byte_at(i)
    if b == 92 && i + 2 < n
      b1 = raw.byte_at(i + 1)
      b2 = raw.byte_at(i + 2)
      if b1 == 92
        sb << "\\"
        i += 2
      else
        h1 = b1 >= 48 && b1 <= 57 ? (b1 - 48) : (b1 >= 97 && b1 <= 102 ? (b1 - 87) : (b1 >= 65 && b1 <= 70 ? (b1 - 55) : -1))
        h2 = b2 >= 48 && b2 <= 57 ? (b2 - 48) : (b2 >= 97 && b2 <= 102 ? (b2 - 87) : (b2 >= 65 && b2 <= 70 ? (b2 - 55) : -1))
        if h1 >= 0 && h2 >= 0
          code = (h1 << 4) | h2
          if code == 10
            sb << "\n"
          elsif code == 9
            sb << " "
          else
            sb << code.chr()
          i += 3
        else
          sb << b.chr()
          i += 1
    elsif b == 36 && op_regs != nil && i + 1 < n
      # Inline asm operand: `${N:x}`, `${N:w}`, or `$N`
      if raw.byte_at(i + 1) == 123
        close = raw.index("}", i + 2)
        if close != nil
          inner = raw.slice(i + 2, close - (i + 2))
          col = inner.index(":")
          idx = col != nil ? inner.slice(0, col).to_i() : inner.to_i()
          mod = col != nil ? inner.slice(col + 1, inner.size() - col - 1) : "x"
          rnum = op_regs[idx]
          sb << (mod == "w" ? ("w" + rnum.to_s()) : ("x" + rnum.to_s()))
          i = close + 1
        else
          sb << "$"
          i += 1
      else
        b1 = raw.byte_at(i + 1)
        if b1 >= 48 && b1 <= 57
          idx = b1 - 48
          rnum = op_regs[idx]
          sb << ("x" + rnum.to_s())
          i += 2
        else
          sb << "$"
          i += 1
    else
      sb << (b == 9 ? " " : b.chr())
      i += 1
  sb.to_s()

+ A64AsmState
  rw :a, :named_lbls, :num_cur, :num_fwd, :globl_syms, :def_syms

  -> new(@a)
    @named_lbls = {}   # name -> label_id
    @num_cur = {}      # num_str -> most recently bound label_id (for `Nb`)
    @num_fwd = {}      # num_str -> pending unbound label_id (for `Nf`)
    @globl_syms = {}   # raw_sym -> true
    @def_syms = []     # [[raw_sym, byte_off], ...]

  -> get_named_label(nm)
    id = @named_lbls[nm]
    if id == nil
      id = @a.new_label()
      @named_lbls[nm] = id
    id

  -> bind_label_token(lbl_name)
    # Check if numeric local label (`0`..`999`)
    c0 = lbl_name.byte_at(0)
    is_num = c0 >= 48 && c0 <= 57
    if is_num
      i = 0
      while i < cinder_blen(lbl_name)
        b = lbl_name.byte_at(i)
        is_num = false if b < 48 || b > 57
        i += 1
    if is_num
      fwd = @num_fwd[lbl_name]
      if fwd != nil
        @a.bind(fwd)
        @num_cur[lbl_name] = fwd
        @num_fwd[lbl_name] = nil
      else
        lid = @a.new_label()
        @a.bind(lid)
        @num_cur[lbl_name] = lid
    else
      lid = get_named_label(lbl_name)
      @a.bind(lid)
      if !lbl_name.starts_with?("L") && !lbl_name.starts_with?(".")
        @def_syms.push([lbl_name, @a.byte_len()])
    nil

  # Resolve branch target token -> [:lbl, lid] or [:ext, raw_sym]
  -> resolve_target(tok)
    t = tok.strip()
    n = cinder_blen(t)
    if n >= 2
      c0 = t.byte_at(0)
      last = t.byte_at(n - 1)
      if c0 >= 48 && c0 <= 57 && (last == 98 || last == 102)
        num_s = t.slice(0, n - 1)
        all_d = true
        k = 0
        while k < cinder_blen(num_s)
          bd = num_s.byte_at(k)
          all_d = false if bd < 48 || bd > 57
          k += 1
        if all_d
          if last == 98   # 'b' backward
            return [:lbl, @num_cur[num_s]]
          else            # 'f' forward
            fwd = @num_fwd[num_s]
            if fwd == nil
              fwd = @a.new_label()
              @num_fwd[num_s] = fwd
            return [:lbl, fwd]
    if t.starts_with?("L") || @named_lbls[t] != nil
      return [:lbl, get_named_label(t)]
    [:ext, t]

  -> assemble_text(text)
    a = @a
    lines = text.split("\n")
    li = 0
    while li < lines.size()
      s = lines[li].strip()
      li += 1
      # Strip `//` or `;` comments
      ci = s.index("//")
      s = s.slice(0, ci).strip() if ci != nil
      if s == ""
        next

      # Handle one or more `label:` prefixes on the line (without matching `[x0, sym@PAGEOFF]`)
      has_lbl = true
      while has_lbl && s != ""
        has_lbl = false
        col = s.index(":")
        br = s.index("\[")
        if col != nil && !s.starts_with?(".") && (br == nil || col < br)
          cand = s.slice(0, col).strip()
          if cand != "" && cand.index(" ") == nil && cand.index(",") == nil
            bind_label_token(cand)
            s = s.slice(col + 1, s.size() - col - 1).strip()
            has_lbl = true
      if s == ""
        next

      # Split mnemonic / directive from operands
      sp = s.index(" ")
      mn = sp == nil ? s : s.slice(0, sp)
      rest = sp == nil ? "" : s.slice(sp + 1, s.size() - sp - 1).strip()
      ml = mn.downcase()

      if ml.starts_with?(".")
        if ml == ".balign"
          a.align_bytes(a64_asm_parse_int(rest))
        elsif ml == ".p2align"
          sh = a64_asm_parse_int(rest.split(",")[0])
          a.align_bytes(1 << sh)
        elsif ml == ".globl" || ml == ".global"
          @globl_syms[rest.strip()] = true
        elsif ml == ".short" || ml == ".hword"
          vals = a64_asm_split_ops(rest)
          vi = 0
          while vi < vals.size()
            a.emit_u16(a64_asm_parse_int(vals[vi]))
            vi += 1
        # `.text` and `.arch_extension` need no bytes
        next

      ops = rest == "" ? [] : a64_asm_split_ops(rest)

      if ml == "ret"
        a.ret()
      elsif ml == "nop"
        a.nop()
      elsif ml == "blr"
        r = a64_asm_parse_reg(ops[0])
        a.blr(r[0])
      elsif ml == "bl"
        tgt = resolve_target(ops[0])
        if tgt[0] == :lbl
          a.bl(tgt[1])
        else
          a.bl_sym(tgt[1])
      elsif ml == "b"
        tgt = resolve_target(ops[0])
        if tgt[0] == :lbl
          a.b(tgt[1])
        else
          a.b_sym(tgt[1])
      elsif ml.starts_with?("b.") || ml == "bne" || ml == "beq" || ml == "blt" || ml == "bge" || ml == "bgt" || ml == "ble"
        cc_s = ml.starts_with?("b.") ? ml.slice(2, ml.size() - 2) : ml.slice(1, ml.size() - 1)
        cc = a64_asm_parse_cc(cc_s)
        tgt = resolve_target(ops[0])
        a.b_cond(cc, tgt[1])
      elsif ml == "cbz" || ml == "cbnz"
        r = a64_asm_parse_reg(ops[0])
        tgt = resolve_target(ops[1])
        if ml == "cbz"
          r[1] == :w ? a.cbz_w(r[0], tgt[1]) : a.cbz_x(r[0], tgt[1])
        else
          r[1] == :w ? a.cbnz_w(r[0], tgt[1]) : a.cbnz_x(r[0], tgt[1])
      elsif ml == "tbz" || ml == "tbnz"
        r = a64_asm_parse_reg(ops[0])
        bit = a64_asm_parse_int(ops[1])
        tgt = resolve_target(ops[2])
        ml == "tbz" ? a.tbz(r[0], bit, tgt[1]) : a.tbnz(r[0], bit, tgt[1])
      elsif ml == "adr"
        r = a64_asm_parse_reg(ops[0])
        tgt = resolve_target(ops[1])
        a.adr(r[0], tgt[1])
      elsif ml == "adrp"
        r = a64_asm_parse_reg(ops[0])
        sym_tok = ops[1]
        if sym_tok.ends_with?("@TLVPPAGE")
          sym_nm = sym_tok.slice(0, sym_tok.size() - 9)
          a.add_reloc(sym_nm, CREL_A64_TLVP_PAGE21, 0)
          a.emit(0x90000000 | r[0])
        elsif sym_tok.ends_with?("@GOTPAGE")
          sym_nm = sym_tok.slice(0, sym_tok.size() - 8)
          a.add_reloc(sym_nm, CREL_A64_GOT_PAGE21, 0)
          a.emit(0x90000000 | r[0])
        else
          sym_nm = sym_tok.ends_with?("@PAGE") ? sym_tok.slice(0, sym_tok.size() - 5) : sym_tok
          a.add_reloc(sym_nm, CREL_A64_PAGE21, 0)
          a.emit(0x90000000 | r[0])
      elsif ml == "mov"
        rd = a64_asm_parse_reg(ops[0])
        if ops[1].starts_with?("#") || (ops[1].byte_at(0) >= 48 && ops[1].byte_at(0) <= 57) || ops[1].starts_with?("-")
          imm = a64_asm_parse_int(ops[1])
          rd[1] == :w ? a.mov_imm32(rd[0], imm) : a.mov_imm64(rd[0], imm)
        else
          rm = a64_asm_parse_reg(ops[1])
          if rd[1] == :sp || rm[1] == :sp
            a.mov_sp(rd[0], rm[0])
          elsif rd[1] == :w
            a.mov_w(rd[0], rm[0])
          else
            a.mov_r(rd[0], rm[0])
      elsif ml == "mvn"
        rd = a64_asm_parse_reg(ops[0])
        rm = a64_asm_parse_reg(ops[1])
        sh = ops.size() >= 3 ? a64_asm_parse_shift(ops[2]) : [0, 0]
        rd[1] == :w ? a.mvn_w(rd[0], rm[0]) : a.mvn_x(rd[0], rm[0], sh[1], sh[0])
      elsif ml == "neg" || ml == "negs"
        rd = a64_asm_parse_reg(ops[0])
        rm = a64_asm_parse_reg(ops[1])
        if ml == "neg"
          rd[1] == :w ? a.neg_w(rd[0], rm[0]) : a.neg_x(rd[0], rm[0])
        else
          rd[1] == :w ? a.negs_w(rd[0], rm[0]) : a.negs_x(rd[0], rm[0])
      elsif ml == "ngc"
        rd = a64_asm_parse_reg(ops[0]); rm = a64_asm_parse_reg(ops[1])
        a.ngc_x(rd[0], rm[0])
      elsif ml == "clz"
        rd = a64_asm_parse_reg(ops[0]); rn = a64_asm_parse_reg(ops[1])
        rd[1] == :w ? a.clz_w(rd[0], rn[0]) : a.clz_x(rd[0], rn[0])
      elsif ml == "add" || ml == "adds" || ml == "sub" || ml == "subs"
        rd = a64_asm_parse_reg(ops[0])
        rn = a64_asm_parse_reg(ops[1])
        op2 = ops[2]
        if op2.starts_with?("#") || (op2.byte_at(0) >= 48 && op2.byte_at(0) <= 57) || op2.starts_with?("-")
          imm = a64_asm_parse_int(op2)
          sh_fl = 0
          if ops.size() >= 4
            sh_p = a64_asm_parse_shift(ops[3])
            sh_fl = sh_p[1] == 12 ? 1 : 0
          if rd[1] == :w
            a.add_wi(rd[0], rn[0], imm)  if ml == "add"
            a.adds_wi(rd[0], rn[0], imm) if ml == "adds"
            a.sub_wi(rd[0], rn[0], imm)  if ml == "sub"
            a.subs_wi(rd[0], rn[0], imm) if ml == "subs"
          else
            a.add_i(rd[0], rn[0], imm, sh_fl)  if ml == "add"
            a.adds_i(rd[0], rn[0], imm, sh_fl) if ml == "adds"
            a.sub_i(rd[0], rn[0], imm, sh_fl)  if ml == "sub"
            a.subs_i(rd[0], rn[0], imm, sh_fl) if ml == "subs"
        else
          rm = a64_asm_parse_reg(op2)
          sh = ops.size() >= 4 ? a64_asm_parse_shift(ops[3]) : [0, 0]
          if rd[1] == :w
            a.add_w(rd[0], rn[0], rm[0], sh[1]) if ml == "add"
            a.adds_w(rd[0], rn[0], rm[0])       if ml == "adds"
            a.sub_w(rd[0], rn[0], rm[0])        if ml == "sub"
            a.subs_w(rd[0], rn[0], rm[0])       if ml == "subs"
          else
            a.add_r(rd[0], rn[0], rm[0], sh[1], sh[0])  if ml == "add"
            a.adds_r(rd[0], rn[0], rm[0], sh[1], sh[0]) if ml == "adds"
            a.sub_r(rd[0], rn[0], rm[0], sh[1], sh[0])  if ml == "sub"
            a.subs_r(rd[0], rn[0], rm[0], sh[1], sh[0]) if ml == "subs"
      elsif ml == "cmp" || ml == "cmn"
        rn = a64_asm_parse_reg(ops[0])
        op1 = ops[1]
        if op1.starts_with?("#") || (op1.byte_at(0) >= 48 && op1.byte_at(0) <= 57) || op1.starts_with?("-")
          imm = a64_asm_parse_int(op1)
          if rn[1] == :w
            a.cmp_wi(rn[0], imm)
          else
            ml == "cmp" ? a.cmp_i(rn[0], imm) : a.cmn_i(rn[0], imm)
        else
          rm = a64_asm_parse_reg(op1)
          sh = ops.size() >= 3 ? a64_asm_parse_shift(ops[2]) : [0, 0]
          if rn[1] == :w
            a.cmp_w(rn[0], rm[0])
          else
            ml == "cmp" ? a.cmp_r(rn[0], rm[0], sh[1], sh[0]) : a.cmn_r(rn[0], rm[0], sh[1], sh[0])
      elsif ml == "adc" || ml == "adcs" || ml == "sbc" || ml == "sbcs"
        rd = a64_asm_parse_reg(ops[0]); rn = a64_asm_parse_reg(ops[1]); rm = a64_asm_parse_reg(ops[2])
        a.adc_x(rd[0], rn[0], rm[0])  if ml == "adc"
        a.adcs_x(rd[0], rn[0], rm[0]) if ml == "adcs"
        a.sbc_x(rd[0], rn[0], rm[0])  if ml == "sbc"
        a.sbcs_x(rd[0], rn[0], rm[0]) if ml == "sbcs"
      elsif ml == "and" || ml == "orr" || ml == "eor"
        rd = a64_asm_parse_reg(ops[0]); rn = a64_asm_parse_reg(ops[1])
        op2 = ops[2]
        if op2.starts_with?("#") || (op2.byte_at(0) >= 48 && op2.byte_at(0) <= 57)
          imm = a64_asm_parse_int(op2)
          a.and_xi(rd[0], rn[0], imm) if ml == "and"
          a.orr_xi(rd[0], rn[0], imm) if ml == "orr"
          a.eor_xi(rd[0], rn[0], imm) if ml == "eor"
        else
          rm = a64_asm_parse_reg(op2)
          sh = ops.size() >= 4 ? a64_asm_parse_shift(ops[3]) : [0, 0]
          if rd[1] == :w
            a.and_w(rd[0], rn[0], rm[0]) if ml == "and"
            a.orr_w(rd[0], rn[0], rm[0]) if ml == "orr"
            a.eor_w(rd[0], rn[0], rm[0]) if ml == "eor"
          else
            a.and_r(rd[0], rn[0], rm[0], sh[1], sh[0]) if ml == "and"
            a.orr_r(rd[0], rn[0], rm[0], sh[1], sh[0]) if ml == "orr"
            a.eor_r(rd[0], rn[0], rm[0], sh[1], sh[0]) if ml == "eor"
      elsif ml == "lsl" || ml == "lsr" || ml == "asr"
        rd = a64_asm_parse_reg(ops[0]); rn = a64_asm_parse_reg(ops[1])
        op2 = ops[2]
        if op2.starts_with?("#") || (op2.byte_at(0) >= 48 && op2.byte_at(0) <= 57)
          sh = a64_asm_parse_int(op2)
          if rd[1] == :w
            a.lsl_wi(rd[0], rn[0], sh) if ml == "lsl"
            a.lsr_wi(rd[0], rn[0], sh) if ml == "lsr"
            a.asr_wi(rd[0], rn[0], sh) if ml == "asr"
          else
            a.lsl_xi(rd[0], rn[0], sh) if ml == "lsl"
            a.lsr_xi(rd[0], rn[0], sh) if ml == "lsr"
            a.asr_xi(rd[0], rn[0], sh) if ml == "asr"
        else
          rm = a64_asm_parse_reg(op2)
          if rd[1] == :w
            a.lsl_w(rd[0], rn[0], rm[0]) if ml == "lsl"
            a.lsr_w(rd[0], rn[0], rm[0]) if ml == "lsr"
            a.asr_w(rd[0], rn[0], rm[0]) if ml == "asr"
          else
            a.lsl_x(rd[0], rn[0], rm[0]) if ml == "lsl"
            a.lsr_x(rd[0], rn[0], rm[0]) if ml == "lsr"
            a.asr_x(rd[0], rn[0], rm[0]) if ml == "asr"
      elsif ml == "mul" || ml == "umulh" || ml == "smulh"
        rd = a64_asm_parse_reg(ops[0]); rn = a64_asm_parse_reg(ops[1]); rm = a64_asm_parse_reg(ops[2])
        a.mul_x(rd[0], rn[0], rm[0])   if ml == "mul"
        a.umulh_x(rd[0], rn[0], rm[0]) if ml == "umulh"
        a.smulh_x(rd[0], rn[0], rm[0]) if ml == "smulh"
      elsif ml == "madd" || ml == "msub"
        rd = a64_asm_parse_reg(ops[0]); rn = a64_asm_parse_reg(ops[1]); rm = a64_asm_parse_reg(ops[2]); ra = a64_asm_parse_reg(ops[3])
        ml == "madd" ? a.madd_x(rd[0], rn[0], rm[0], ra[0]) : a.msub_x(rd[0], rn[0], rm[0], ra[0])
      elsif ml == "sbfx"
        rd = a64_asm_parse_reg(ops[0]); rn = a64_asm_parse_reg(ops[1])
        lsb = a64_asm_parse_int(ops[2]); wid = a64_asm_parse_int(ops[3])
        a.sbfx_x(rd[0], rn[0], lsb, wid)
      elsif ml == "extr"
        rd = a64_asm_parse_reg(ops[0]); rn = a64_asm_parse_reg(ops[1]); rm = a64_asm_parse_reg(ops[2])
        lsb = a64_asm_parse_int(ops[3])
        a.extr_x(rd[0], rn[0], rm[0], lsb)
      elsif ml == "umin"
        rd = a64_asm_parse_reg(ops[0]); rn = a64_asm_parse_reg(ops[1])
        op2 = ops[2]
        if op2.starts_with?("#") || (op2.byte_at(0) >= 48 && op2.byte_at(0) <= 57)
          a.umin_xi(rd[0], rn[0], a64_asm_parse_int(op2))
        else
          rm = a64_asm_parse_reg(op2)
          a.umin_xr(rd[0], rn[0], rm[0])
      elsif ml == "cset"
        rd = a64_asm_parse_reg(ops[0]); cc = a64_asm_parse_cc(ops[1])
        rd[1] == :w ? a.cset_w(rd[0], cc) : a.cset(rd[0], cc)
      elsif ml == "cinc"
        rd = a64_asm_parse_reg(ops[0]); rn = a64_asm_parse_reg(ops[1]); cc = a64_asm_parse_cc(ops[2])
        rd[1] == :w ? a.cinc_w(rd[0], rn[0], cc) : a.cinc_x(rd[0], rn[0], cc)
      elsif ml == "csel" || ml == "csinc"
        rd = a64_asm_parse_reg(ops[0]); rn = a64_asm_parse_reg(ops[1]); rm = a64_asm_parse_reg(ops[2]); cc = a64_asm_parse_cc(ops[3])
        if ml == "csel"
          rd[1] == :w ? a.csel_w(rd[0], rn[0], rm[0], cc) : a.csel_x(rd[0], rn[0], rm[0], cc)
        else
          rd[1] == :w ? a.csinc_w(rd[0], rn[0], rm[0], cc) : a.csinc_x(rd[0], rn[0], rm[0], cc)
      elsif ml == "ccmp"
        rn = a64_asm_parse_reg(ops[0]); op1 = ops[1]; nzcv = a64_asm_parse_int(ops[2]); cc = a64_asm_parse_cc(ops[3])
        if op1.starts_with?("#") || (op1.byte_at(0) >= 48 && op1.byte_at(0) <= 57)
          a.ccmp_xi(rn[0], a64_asm_parse_int(op1), nzcv, cc)
        else
          rm = a64_asm_parse_reg(op1)
          a.ccmp_xr(rn[0], rm[0], nzcv, cc)
      elsif ml == "dup.2d"
        vd = a64_asm_parse_reg(ops[0]); rn = a64_asm_parse_reg(ops[1])
        a.dup_2d_g(vd[0], rn[0])
      elsif ml == "neg.2d"
        vd = a64_asm_parse_reg(ops[0]); vn = a64_asm_parse_reg(ops[1])
        a.neg_2d(vd[0], vn[0])
      elsif ml == "orr.16b"
        vd = a64_asm_parse_reg(ops[0]); vn = a64_asm_parse_reg(ops[1]); vm = a64_asm_parse_reg(ops[2])
        a.orr_16b(vd[0], vn[0], vm[0])
      elsif ml == "ushl.2d"
        vd = a64_asm_parse_reg(ops[0]); vn = a64_asm_parse_reg(ops[1]); vm = a64_asm_parse_reg(ops[2])
        a.ushl_2d(vd[0], vn[0], vm[0])
      elsif ml == "ldp" || ml == "stp"
        r1 = a64_asm_parse_reg(ops[0]); r2 = a64_asm_parse_reg(ops[1])
        mem = ops[2]
        # Post-index: `[xN], #imm` (`ops.size() == 4`)
        if ops.size() == 4
          base_s = mem.slice(1, mem.size() - 2)
          rn = a64_asm_parse_reg(base_s)
          off = a64_asm_parse_int(ops[3])
          if r1[1] == :q
            ml == "ldp" ? a.ldp_q_post(r1[0], r2[0], rn[0], off) : a.stp_q_post(r1[0], r2[0], rn[0], off)
          else
            ml == "ldp" ? a.ldp_post(r1[0], r2[0], rn[0], off) : a.stp_post(r1[0], r2[0], rn[0], off)
        else
          pre = mem.ends_with?("!")
          inner = pre ? mem.slice(1, mem.size() - 3) : mem.slice(1, mem.size() - 2)
          mops = a64_asm_split_ops(inner)
          rn = a64_asm_parse_reg(mops[0])
          off = mops.size() >= 2 ? a64_asm_parse_int(mops[1]) : 0
          if pre
            a.stp_pre(r1[0], r2[0], rn[0], off)
          elsif r1[1] == :q
            ml == "ldp" ? a.ldp_q(r1[0], r2[0], rn[0], off) : a.stp_q(r1[0], r2[0], rn[0], off)
          else
            ml == "ldp" ? a.ldp_x(r1[0], r2[0], rn[0], off) : a.stp_x(r1[0], r2[0], rn[0], off)
      elsif ml == "ldr" || ml == "str" || ml == "ldrb" || ml == "strb" || ml == "ldrh" || ml == "strh" || ml == "ldur" || ml == "stur"
        rt = a64_asm_parse_reg(ops[0])
        mem = ops[1]
        if ops.size() == 3
          # Post-index: `ldr xN, [xBase], #imm`
          rn = a64_asm_parse_reg(mem.slice(1, mem.size() - 2))
          off = a64_asm_parse_int(ops[2])
          ml == "ldr" ? a.ldr_x_post(rt[0], rn[0], off) : a.str_x_post(rt[0], rn[0], off)
        else
          pre = mem.ends_with?("!")
          inner = pre ? mem.slice(1, mem.size() - 3) : mem.slice(1, mem.size() - 2)
          mops = a64_asm_split_ops(inner)
          rn = a64_asm_parse_reg(mops[0])
          if pre
            off = a64_asm_parse_int(mops[1])
            ml == "ldr" ? a.ldr_x_pre(rt[0], rn[0], off) : a.str_x_pre(rt[0], rn[0], off)
          elsif mops.size() == 1
            if ml == "ldrb"
              a.ldrb(rt[0], rn[0], 0)
            elsif ml == "strb"
              a.strb(rt[0], rn[0], 0)
            elsif ml == "ldrh"
              a.ldrh(rt[0], rn[0], 0)
            elsif ml == "strh"
              a.strh(rt[0], rn[0], 0)
            elsif rt[1] == :q
              ml == "ldr" || ml == "ldur" ? a.ldr_q(rt[0], rn[0], 0) : a.str_q(rt[0], rn[0], 0)
            else
              ml == "ldr" ? a.ldr_x(rt[0], rn[0], 0) : a.str_x(rt[0], rn[0], 0)
          elsif mops[1].ends_with?("@TLVPPAGEOFF")
            sym_nm = mops[1].slice(0, mops[1].size() - 12)
            a.add_reloc(sym_nm, CREL_A64_TLVP_PAGEOFF12, 0)
            a.emit(0xF9400000 | (rn[0] << 5) | rt[0])
          elsif mops[1].starts_with?("#") || (mops[1].byte_at(0) >= 48 && mops[1].byte_at(0) <= 57) || mops[1].starts_with?("-")
            off = a64_asm_parse_int(mops[1])
            if ml == "ldur" && rt[1] == :q
              a.ldur_q(rt[0], rn[0], off)
            elsif ml == "stur" && rt[1] == :q
              a.stur_q(rt[0], rn[0], off)
            elsif rt[1] == :q
              ml == "ldr" ? a.ldr_q(rt[0], rn[0], off) : a.str_q(rt[0], rn[0], off)
            elsif ml == "ldrb"
              a.ldrb(rt[0], rn[0], off)
            elsif ml == "strb"
              a.strb(rt[0], rn[0], off)
            elsif ml == "ldrh"
              a.ldrh(rt[0], rn[0], off)
            elsif ml == "strh"
              a.strh(rt[0], rn[0], off)
            else
              ml == "ldr" || ml == "ldur" ? a.ldr_x(rt[0], rn[0], off) : a.str_x(rt[0], rn[0], off)
          else
            # Register-indexed `[xBase, xIdx (, lsl #3)]`
            rm = a64_asm_parse_reg(mops[1])
            sh = mops.size() >= 3 ? a64_asm_parse_shift(mops[2])[1] : 0
            if sh == 3
              ml == "ldr" ? a.ldr_x_idx(rt[0], rn[0], rm[0]) : a.str_x_idx(rt[0], rn[0], rm[0])
            else
              ml == "ldr" ? a.ldr_x_reg(rt[0], rn[0], rm[0]) : a.str_x_reg(rt[0], rn[0], rm[0])
      else
        raise "Cinder ARM64 asm: unhandled mnemonic `" + ml + "` in line: " + s
    nil
