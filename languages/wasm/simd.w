# wasm/simd — validation and compilation of the 128-bit SIMD instructions (and relaxed SIMD).
#
# A v128 lives in two consecutive i64 slots (low word first). Every lane-wise operation
# compiles to OP_VOP d a b c sub; the interpreter runs it with the kernel for `sub` (the
# instruction's 0xFD opcode). Loads/stores of whole vectors on memory 0 use OP_LD128/ST128.

# Operand shape of each 0xFD opcode: u unary v→v, b binary, t ternary, s shift (v,i32),
# r reduce v→i32, -: not an opcode.
-> wasm_simd_kind(sub)
  return "u" if sub == 77 || sub == 94 || sub == 95 || sub == 96 || sub == 97 || sub == 98
  return "u" if (sub >= 103 && sub <= 106) || sub == 116 || sub == 117 || sub == 122 || (sub >= 124 && sub <= 129)
  return "u" if (sub >= 135 && sub <= 138) || sub == 148 || sub == 160 || sub == 161 || (sub >= 167 && sub <= 170)
  return "u" if sub == 192 || sub == 193 || (sub >= 199 && sub <= 202) || sub == 224 || sub == 225 || sub == 227
  return "u" if sub == 236 || sub == 237 || sub == 239 || (sub >= 248 && sub <= 255) || (sub >= 257 && sub <= 260)
  return "r" if sub == 83 || sub == 99 || sub == 100 || sub == 131 || sub == 132 || sub == 163 || sub == 164 || sub == 195 || sub == 196
  return "s" if (sub >= 107 && sub <= 109) || (sub >= 139 && sub <= 141) || (sub >= 171 && sub <= 173) || (sub >= 203 && sub <= 205)
  return "t" if sub == 82 || (sub >= 261 && sub <= 268) || sub == 275
  return "b" if sub == 14 || (sub >= 35 && sub <= 76) || (sub >= 78 && sub <= 81) || sub == 101 || sub == 102
  return "b" if (sub >= 110 && sub <= 115) || (sub >= 118 && sub <= 121) || sub == 123 || sub == 130 || sub == 133 || sub == 134
  return "b" if (sub >= 142 && sub <= 147) || (sub >= 149 && sub <= 153) || (sub >= 155 && sub <= 159)
  return "b" if sub == 174 || sub == 177 || (sub >= 181 && sub <= 186) || (sub >= 188 && sub <= 191)
  return "b" if sub == 206 || sub == 209 || (sub >= 213 && sub <= 223) || (sub >= 228 && sub <= 235) || (sub >= 240 && sub <= 247)
  return "b" if sub == 256 || (sub >= 269 && sub <= 274)
  "-"

-> wasm_simd_compile(c, r, sub)
  if sub <= 10
    nat = [4, 3, 3, 3, 3, 3, 3, 0, 1, 2, 3][sub]
    c.simd_mem(sub, nat, false, -1)
  elsif sub == 11
    c.simd_mem(sub, 4, true, -1)
  elsif sub == 92
    c.simd_mem(sub, 2, false, -1)
  elsif sub == 93
    c.simd_mem(sub, 3, false, -1)
  elsif sub >= 84 && sub <= 91
    nat = (sub - 84) % 4
    c.simd_lane_mem(sub, nat, sub >= 88, 16 >> nat)
  elsif sub == 12
    lo = 0
    k = 0
    while k < 8
      lo = (lo | (r.byte() << (8 * k))) ## i64
      k += 1
    hi = 0
    k = 0
    while k < 8
      hi = (hi | (r.byte() << (8 * k))) ## i64
      k += 1
    c.simd_const(lo, hi)
  elsif sub == 13
    lo = 0
    k = 0
    while k < 8
      l = r.byte()
      w_invalid("invalid lane index") if l >= 32
      lo = (lo | (l << (8 * k))) ## i64
      k += 1
    hi = 0
    k = 0
    while k < 8
      l = r.byte()
      w_invalid("invalid lane index") if l >= 32
      hi = (hi | (l << (8 * k))) ## i64
      k += 1
    c.simd_shuffle(lo, hi)
  elsif sub >= 15 && sub <= 20
    ts = [I32, I32, I32, I64, F32, F64][sub - 15]
    c.simd_unop(ts, V128, sub)
  elsif sub >= 21 && sub <= 34
    lane = r.byte()
    info = [[16, I32, 0], [16, I32, 0], [16, I32, 1], [8, I32, 0], [8, I32, 0], [8, I32, 1], [4, I32, 0], [4, I32, 1], [2, I64, 0], [2, I64, 1], [4, F32, 0], [4, F32, 1], [2, F64, 0], [2, F64, 1]][sub - 21]
    w_invalid("invalid lane index") if lane >= info[0]
    if info[2] == 0
      c.simd_lane_op(V128, info[1], sub, lane)
    else
      c.simd_replace(info[1], sub, lane)
  else
    k = wasm_simd_kind(sub)
    if k == "u"
      c.simd_unop(V128, V128, sub)
    elsif k == "b"
      c.simd_binop(V128, V128, V128, sub)
    elsif k == "t"
      c.simd_ternop(V128, sub)
    elsif k == "s"
      c.simd_binop(V128, I32, V128, sub)
    elsif k == "r"
      c.simd_unop(V128, I32, sub)
    else
      w_malformed("illegal opcode 0xfd " + sub.to_s)
  nil

+ WCompiler
  -> simd_lane_mem(sub, nat, store, lanes)
    ma = memarg(nat)
    lane = @r.byte()
    w_invalid("invalid lane index") if lane >= lanes
    mi = ma[0]
    at = addr_type(mi)
    v = pop_slot(V128)
    a = pop_slot(at)
    if store
      ext(0xfd0000 + sub, [mi, a, v, ma[1], lane])
    else
      d = push(V128)
      ext(0xfd0000 + sub, [mi, d, a, ma[1], lane, v])
    nil

  -> simd_shuffle(lo, hi)
    b = pop_slot(V128)
    a = pop_slot(V128)
    d = push(V128)
    emit_d([OP_VOP, d, a, b, @code.size + 8, 13])
    # the lane pattern follows inline after a jump-over
    emit_n([OP_JMP, @code.size + 4, lo, hi])
