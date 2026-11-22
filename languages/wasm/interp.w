# wasm/interp — the interpreter loop (GENERATED from interp.wt by tools/gen_interp.w;
# edit interp.wt, then run `bin/tungsten tools/gen_interp.w`).
#
# One typed function runs a module's register code at machine speed: raw i64 slots, raw
# typed-array access, a dense switch. It returns to the driver (runtime.w) for anything
# that needs objects or the outside world, with the reason as the result:
#   0 done (the entry frame returned)   1 trap (st[4] = trap code)   2 OP_EXT at st[0]
#   3 import call at st[0]              4 call_indirect slow path     5 call_ref
#   6 call stack exhausted
# st: [0] pc  [1] fp  [2] csp  [3] memory size in bytes  [4] trap code  [5] instance id
#     [6] stack limit (slots)  [7] control stack limit  [9] table 0 size
# glob holds numeric globals at 2*index (v128 high word at 2*index+1); gref ref globals.
# tab: table 0's function ids (0 = null); sx: store function info, 4 words per id:
#     [entry pc, instance id, canonical type, module function index].

-> wexec(code, stk, ostk, mem, glob, gref, tab, sx, cstk, st, jt, ctx) (i64[] i64[] Array u8[] i64[] Array i64[] i64[] i64[] i64[] i64[] i64[]) i64
  pc = st[0]
  fp = st[1]
  csp = st[2]
  msize = st[3]
  inst = st[5]
  slimit = st[6]
  climit = st[7]
  tsize = st[9]
  m32 = 4294967295 ## i64
  minv = (0 - 9223372036854775807 - 1) ## i64
  while true
    op = code[pc]
    case op
    when 14
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]]
      pc += 3
    when 17
      stk[fp + code[pc + 1]] = code[pc + 2]
      pc += 3
    when 29
      stk[fp + code[pc + 1]] = (stk[fp + code[pc + 2]] + stk[fp + code[pc + 3]]) & m32
      pc += 4
    when 82
      stk[fp + code[pc + 1]] = (stk[fp + code[pc + 2]] + code[pc + 3]) & m32
      pc += 4
    when 43
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] + stk[fp + code[pc + 3]]
      pc += 4
    when 83
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] + code[pc + 3]
      pc += 4
    when 203
      ea = stk[fp + code[pc + 2]] + code[pc + 3]
      if ea + 4 > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_ld32u(mem, ea)
      pc += 4
    when 212
      ea = stk[fp + code[pc + 1]] + code[pc + 3]
      if ea + 4 > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      wk_st32(mem, ea, stk[fp + code[pc + 2]])
      pc += 4
    when 1
      pc = code[pc + 1]
    when 2
      if stk[fp + code[pc + 1]] == 0
        pc = code[pc + 2]
      else
        pc += 3
    when 3
      if stk[fp + code[pc + 1]] != 0
        pc = code[pc + 2]
      else
        pc += 3
    when 109
      if stk[fp + code[pc + 1]] == stk[fp + code[pc + 2]]
        pc = code[pc + 3]
      else
        pc += 4
    when 110
      if stk[fp + code[pc + 1]] != stk[fp + code[pc + 2]]
        pc = code[pc + 3]
      else
        pc += 4
    when 111
      if wk_ult(stk[fp + code[pc + 1]], stk[fp + code[pc + 2]]) != 0
        pc = code[pc + 3]
      else
        pc += 4
    when 112
      if wk_ugt(stk[fp + code[pc + 1]], stk[fp + code[pc + 2]]) != 0
        pc = code[pc + 3]
      else
        pc += 4
    when 113
      if wk_ule(stk[fp + code[pc + 1]], stk[fp + code[pc + 2]]) != 0
        pc = code[pc + 3]
      else
        pc += 4
    when 114
      if wk_uge(stk[fp + code[pc + 1]], stk[fp + code[pc + 2]]) != 0
        pc = code[pc + 3]
      else
        pc += 4
    when 115
      if ((stk[fp + code[pc + 1]] << 32) >> 32) < ((stk[fp + code[pc + 2]] << 32) >> 32)
        pc = code[pc + 3]
      else
        pc += 4
    when 116
      if ((stk[fp + code[pc + 1]] << 32) >> 32) > ((stk[fp + code[pc + 2]] << 32) >> 32)
        pc = code[pc + 3]
      else
        pc += 4
    when 117
      if ((stk[fp + code[pc + 1]] << 32) >> 32) <= ((stk[fp + code[pc + 2]] << 32) >> 32)
        pc = code[pc + 3]
      else
        pc += 4
    when 118
      if ((stk[fp + code[pc + 1]] << 32) >> 32) >= ((stk[fp + code[pc + 2]] << 32) >> 32)
        pc = code[pc + 3]
      else
        pc += 4
    when 119
      if stk[fp + code[pc + 1]] < stk[fp + code[pc + 2]]
        pc = code[pc + 3]
      else
        pc += 4
    when 120
      if stk[fp + code[pc + 1]] > stk[fp + code[pc + 2]]
        pc = code[pc + 3]
      else
        pc += 4
    when 121
      if stk[fp + code[pc + 1]] <= stk[fp + code[pc + 2]]
        pc = code[pc + 3]
      else
        pc += 4
    when 122
      if stk[fp + code[pc + 1]] >= stk[fp + code[pc + 2]]
        pc = code[pc + 3]
      else
        pc += 4
    when 123
      if stk[fp + code[pc + 1]] == code[pc + 2]
        pc = code[pc + 3]
      else
        pc += 4
    when 124
      if stk[fp + code[pc + 1]] != code[pc + 2]
        pc = code[pc + 3]
      else
        pc += 4
    when 125
      if wk_ult(stk[fp + code[pc + 1]], code[pc + 2]) != 0
        pc = code[pc + 3]
      else
        pc += 4
    when 126
      if wk_ugt(stk[fp + code[pc + 1]], code[pc + 2]) != 0
        pc = code[pc + 3]
      else
        pc += 4
    when 127
      if wk_ule(stk[fp + code[pc + 1]], code[pc + 2]) != 0
        pc = code[pc + 3]
      else
        pc += 4
    when 128
      if wk_uge(stk[fp + code[pc + 1]], code[pc + 2]) != 0
        pc = code[pc + 3]
      else
        pc += 4
    when 129
      if ((stk[fp + code[pc + 1]] << 32) >> 32) < ((code[pc + 2] << 32) >> 32)
        pc = code[pc + 3]
      else
        pc += 4
    when 130
      if ((stk[fp + code[pc + 1]] << 32) >> 32) > ((code[pc + 2] << 32) >> 32)
        pc = code[pc + 3]
      else
        pc += 4
    when 131
      if ((stk[fp + code[pc + 1]] << 32) >> 32) <= ((code[pc + 2] << 32) >> 32)
        pc = code[pc + 3]
      else
        pc += 4
    when 132
      if ((stk[fp + code[pc + 1]] << 32) >> 32) >= ((code[pc + 2] << 32) >> 32)
        pc = code[pc + 3]
      else
        pc += 4
    when 133
      if stk[fp + code[pc + 1]] < code[pc + 2]
        pc = code[pc + 3]
      else
        pc += 4
    when 134
      if stk[fp + code[pc + 1]] > code[pc + 2]
        pc = code[pc + 3]
      else
        pc += 4
    when 135
      if stk[fp + code[pc + 1]] <= code[pc + 2]
        pc = code[pc + 3]
      else
        pc += 4
    when 136
      if stk[fp + code[pc + 1]] >= code[pc + 2]
        pc = code[pc + 3]
      else
        pc += 4
    when 6
      if csp >= climit
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 6
      cstk[csp] = pc + 3
      cstk[csp + 1] = fp
      csp += 2
      fp += code[pc + 2]
      pc = code[pc + 1]
    when 11
      if fp + code[pc + 1] > slimit
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 6
      z = fp + code[pc + 2]
      ze = fp + code[pc + 3]
      while z < ze
        stk[z] = 0
        z += 1
      if code[pc + 4] != 0
        z = fp + code[pc + 2]
        ze = fp + code[pc + 1]
        while z < ze
          ostk[z] = nil
          z += 1
      pc += 5
    when 5
      csp -= 2
      pc = cstk[csp]
      fp = cstk[csp + 1]
      if pc < 0
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 0
    when 10
      n = code[pc + 2]
      src = fp + code[pc + 3]
      k = 0
      while k < n
        stk[fp + k] = stk[src + k]
        ostk[fp + k] = ostk[src + k]
        k += 1
      pc = code[pc + 1]
    when 8
      idx = stk[fp + code[pc + 4]]
      if code[pc + 1] != 0
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 4
      if idx < 0 || idx >= tsize
        st[4] = 6
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      fid = tab[idx]
      if fid == 0
        st[4] = 7
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      if sx[fid * 4 + 2] != code[pc + 2] || sx[fid * 4 + 1] != inst
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 4
      if csp >= climit
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 6
      cstk[csp] = pc + 6
      cstk[csp + 1] = fp
      csp += 2
      fp += code[pc + 3]
      pc = sx[fid * 4]
    when 7
      st[0] = pc
      st[1] = fp
      st[2] = csp
      return 3
    when 9
      st[0] = pc
      st[1] = fp
      st[2] = csp
      return 5
    when 13
      st[0] = pc
      st[1] = fp
      st[2] = csp
      return 2
    when 12
      st[4] = code[pc + 1]
      st[0] = pc
      st[1] = fp
      st[2] = csp
      return 1
    when 4
      i = stk[fp + code[pc + 1]]
      n = code[pc + 2]
      if i < 0 || i > n
        i = n
      pc = code[pc + 3 + i]
    when 0
      pc += 1
    when 15
      d = fp + code[pc + 1]
      a = fp + code[pc + 2]
      stk[d] = stk[a]
      stk[d + 1] = stk[a + 1]
      pc += 3
    when 16
      ostk[fp + code[pc + 1]] = ostk[fp + code[pc + 2]]
      pc += 3
    when 18
      d = fp + code[pc + 1]
      stk[d] = code[pc + 2]
      stk[d + 1] = code[pc + 3]
      pc += 4
    when 19
      ostk[fp + code[pc + 1]] = nil
      pc += 2
    when 20
      if stk[fp + code[pc + 4]] != 0
        stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]]
      else
        stk[fp + code[pc + 1]] = stk[fp + code[pc + 3]]
      pc += 5
    when 21
      d = fp + code[pc + 1]
      a = fp + code[pc + 3]
      if stk[fp + code[pc + 4]] != 0
        a = fp + code[pc + 2]
      x0 = stk[a]
      x1 = stk[a + 1]
      stk[d] = x0
      stk[d + 1] = x1
      pc += 5
    when 22
      if stk[fp + code[pc + 4]] != 0
        ostk[fp + code[pc + 1]] = ostk[fp + code[pc + 2]]
      else
        ostk[fp + code[pc + 1]] = ostk[fp + code[pc + 3]]
      pc += 5
    when 23
      stk[fp + code[pc + 1]] = glob[code[pc + 2] * 2]
      pc += 3
    when 24
      glob[code[pc + 1] * 2] = stk[fp + code[pc + 2]]
      pc += 3
    when 25
      d = fp + code[pc + 1]
      g = code[pc + 2] * 2
      stk[d] = glob[g]
      stk[d + 1] = glob[g + 1]
      pc += 3
    when 26
      a = fp + code[pc + 2]
      g = code[pc + 1] * 2
      glob[g] = stk[a]
      glob[g + 1] = stk[a + 1]
      pc += 3
    when 27
      ostk[fp + code[pc + 1]] = gref[code[pc + 2]]
      pc += 3
    when 28
      gref[code[pc + 1]] = ostk[fp + code[pc + 2]]
      pc += 3
    when 30
      stk[fp + code[pc + 1]] = (stk[fp + code[pc + 2]] - stk[fp + code[pc + 3]]) & m32
      pc += 4
    when 31
      stk[fp + code[pc + 1]] = (stk[fp + code[pc + 2]] * stk[fp + code[pc + 3]]) & m32
      pc += 4
    when 32
      a = (stk[fp + code[pc + 2]] << 32) >> 32
      b = (stk[fp + code[pc + 3]] << 32) >> 32
      if b == 0
        st[4] = 2
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      if b == -1 && a == -2147483648
        st[4] = 3
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = (a / b) & m32
      pc += 4
    when 33
      b = stk[fp + code[pc + 3]]
      if b == 0
        st[4] = 2
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] / b
      pc += 4
    when 34
      a = (stk[fp + code[pc + 2]] << 32) >> 32
      b = (stk[fp + code[pc + 3]] << 32) >> 32
      if b == 0
        st[4] = 2
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      if b == -1
        stk[fp + code[pc + 1]] = 0
      else
        stk[fp + code[pc + 1]] = (a % b) & m32
      pc += 4
    when 35
      b = stk[fp + code[pc + 3]]
      if b == 0
        st[4] = 2
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] % b
      pc += 4
    when 36
      stk[fp + code[pc + 1]] = (stk[fp + code[pc + 2]] << (stk[fp + code[pc + 3]] & 31)) & m32
      pc += 4
    when 37
      stk[fp + code[pc + 1]] = (((stk[fp + code[pc + 2]] << 32) >> 32) >> (stk[fp + code[pc + 3]] & 31)) & m32
      pc += 4
    when 38
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] >> (stk[fp + code[pc + 3]] & 31)
      pc += 4
    when 39
      stk[fp + code[pc + 1]] = wk_rotl32(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 40
      stk[fp + code[pc + 1]] = wk_rotr32(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 41
      stk[fp + code[pc + 1]] = wk_clz32(stk[fp + code[pc + 2]])
      pc += 3
    when 42
      stk[fp + code[pc + 1]] = wk_ctz32(stk[fp + code[pc + 2]])
      pc += 3
    when 44
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] - stk[fp + code[pc + 3]]
      pc += 4
    when 45
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] * stk[fp + code[pc + 3]]
      pc += 4
    when 46
      a = stk[fp + code[pc + 2]]
      b = stk[fp + code[pc + 3]]
      if b == 0
        st[4] = 2
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      if b == -1 && a == minv
        st[4] = 3
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = a / b
      pc += 4
    when 47
      b = stk[fp + code[pc + 3]]
      if b == 0
        st[4] = 2
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_udiv64(stk[fp + code[pc + 2]], b)
      pc += 4
    when 48
      a = stk[fp + code[pc + 2]]
      b = stk[fp + code[pc + 3]]
      if b == 0
        st[4] = 2
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      if b == -1
        stk[fp + code[pc + 1]] = 0
      else
        stk[fp + code[pc + 1]] = a % b
      pc += 4
    when 49
      b = stk[fp + code[pc + 3]]
      if b == 0
        st[4] = 2
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_urem64(stk[fp + code[pc + 2]], b)
      pc += 4
    when 50
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] << (stk[fp + code[pc + 3]] & 63)
      pc += 4
    when 51
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] >> (stk[fp + code[pc + 3]] & 63)
      pc += 4
    when 52
      stk[fp + code[pc + 1]] = wk_lshr64(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 53
      stk[fp + code[pc + 1]] = wk_rotl64(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 54
      stk[fp + code[pc + 1]] = wk_rotr64(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 55
      stk[fp + code[pc + 1]] = wk_clz64(stk[fp + code[pc + 2]])
      pc += 3
    when 56
      stk[fp + code[pc + 1]] = wk_ctz64(stk[fp + code[pc + 2]])
      pc += 3
    when 57
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] & stk[fp + code[pc + 3]]
      pc += 4
    when 58
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] | stk[fp + code[pc + 3]]
      pc += 4
    when 59
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] ^ stk[fp + code[pc + 3]]
      pc += 4
    when 60
      stk[fp + code[pc + 1]] = wk_popcnt(stk[fp + code[pc + 2]])
      pc += 3
    when 61
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] == 0 ? 1 : 0
      pc += 3
    when 62
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] == stk[fp + code[pc + 3]] ? 1 : 0
      pc += 4
    when 63
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] != stk[fp + code[pc + 3]] ? 1 : 0
      pc += 4
    when 64
      stk[fp + code[pc + 1]] = wk_ult(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 65
      stk[fp + code[pc + 1]] = wk_ugt(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 66
      stk[fp + code[pc + 1]] = wk_ule(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 67
      stk[fp + code[pc + 1]] = wk_uge(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 68
      stk[fp + code[pc + 1]] = ((stk[fp + code[pc + 2]] << 32) >> 32) < ((stk[fp + code[pc + 3]] << 32) >> 32) ? 1 : 0
      pc += 4
    when 69
      stk[fp + code[pc + 1]] = ((stk[fp + code[pc + 2]] << 32) >> 32) > ((stk[fp + code[pc + 3]] << 32) >> 32) ? 1 : 0
      pc += 4
    when 70
      stk[fp + code[pc + 1]] = ((stk[fp + code[pc + 2]] << 32) >> 32) <= ((stk[fp + code[pc + 3]] << 32) >> 32) ? 1 : 0
      pc += 4
    when 71
      stk[fp + code[pc + 1]] = ((stk[fp + code[pc + 2]] << 32) >> 32) >= ((stk[fp + code[pc + 3]] << 32) >> 32) ? 1 : 0
      pc += 4
    when 72
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] < stk[fp + code[pc + 3]] ? 1 : 0
      pc += 4
    when 73
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] > stk[fp + code[pc + 3]] ? 1 : 0
      pc += 4
    when 74
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] <= stk[fp + code[pc + 3]] ? 1 : 0
      pc += 4
    when 75
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] >= stk[fp + code[pc + 3]] ? 1 : 0
      pc += 4
    when 76
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] & m32
      pc += 3
    when 77
      stk[fp + code[pc + 1]] = (stk[fp + code[pc + 2]] << 32) >> 32
      pc += 3
    when 78
      stk[fp + code[pc + 1]] = ((stk[fp + code[pc + 2]] << 56) >> 56) & m32
      pc += 3
    when 79
      stk[fp + code[pc + 1]] = ((stk[fp + code[pc + 2]] << 48) >> 48) & m32
      pc += 3
    when 80
      stk[fp + code[pc + 1]] = (stk[fp + code[pc + 2]] << 56) >> 56
      pc += 3
    when 81
      stk[fp + code[pc + 1]] = (stk[fp + code[pc + 2]] << 48) >> 48
      pc += 3
    when 84
      stk[fp + code[pc + 1]] = (stk[fp + code[pc + 2]] * code[pc + 3]) & m32
      pc += 4
    when 85
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] * code[pc + 3]
      pc += 4
    when 86
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] & code[pc + 3]
      pc += 4
    when 87
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] | code[pc + 3]
      pc += 4
    when 88
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] ^ code[pc + 3]
      pc += 4
    when 89
      stk[fp + code[pc + 1]] = (stk[fp + code[pc + 2]] << code[pc + 3]) & m32
      pc += 4
    when 90
      stk[fp + code[pc + 1]] = (((stk[fp + code[pc + 2]] << 32) >> 32) >> code[pc + 3]) & m32
      pc += 4
    when 91
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] >> code[pc + 3]
      pc += 4
    when 92
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] << code[pc + 3]
      pc += 4
    when 93
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] >> code[pc + 3]
      pc += 4
    when 94
      stk[fp + code[pc + 1]] = wk_lshr64(stk[fp + code[pc + 2]], code[pc + 3])
      pc += 4
    when 95
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] == code[pc + 3] ? 1 : 0
      pc += 4
    when 96
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] != code[pc + 3] ? 1 : 0
      pc += 4
    when 97
      stk[fp + code[pc + 1]] = wk_ult(stk[fp + code[pc + 2]], code[pc + 3])
      pc += 4
    when 98
      stk[fp + code[pc + 1]] = wk_ugt(stk[fp + code[pc + 2]], code[pc + 3])
      pc += 4
    when 99
      stk[fp + code[pc + 1]] = wk_ule(stk[fp + code[pc + 2]], code[pc + 3])
      pc += 4
    when 100
      stk[fp + code[pc + 1]] = wk_uge(stk[fp + code[pc + 2]], code[pc + 3])
      pc += 4
    when 101
      stk[fp + code[pc + 1]] = ((stk[fp + code[pc + 2]] << 32) >> 32) < ((code[pc + 3] << 32) >> 32) ? 1 : 0
      pc += 4
    when 102
      stk[fp + code[pc + 1]] = ((stk[fp + code[pc + 2]] << 32) >> 32) > ((code[pc + 3] << 32) >> 32) ? 1 : 0
      pc += 4
    when 103
      stk[fp + code[pc + 1]] = ((stk[fp + code[pc + 2]] << 32) >> 32) <= ((code[pc + 3] << 32) >> 32) ? 1 : 0
      pc += 4
    when 104
      stk[fp + code[pc + 1]] = ((stk[fp + code[pc + 2]] << 32) >> 32) >= ((code[pc + 3] << 32) >> 32) ? 1 : 0
      pc += 4
    when 105
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] < code[pc + 3] ? 1 : 0
      pc += 4
    when 106
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] > code[pc + 3] ? 1 : 0
      pc += 4
    when 107
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] <= code[pc + 3] ? 1 : 0
      pc += 4
    when 108
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] >= code[pc + 3] ? 1 : 0
      pc += 4
    when 137
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] & 2147483647
      pc += 3
    when 138
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] ^ 2147483648
      pc += 3
    when 139
      stk[fp + code[pc + 1]] = wk_f32_ceil(stk[fp + code[pc + 2]])
      pc += 3
    when 140
      stk[fp + code[pc + 1]] = wk_f32_floor(stk[fp + code[pc + 2]])
      pc += 3
    when 141
      stk[fp + code[pc + 1]] = wk_f32_trunc(stk[fp + code[pc + 2]])
      pc += 3
    when 142
      stk[fp + code[pc + 1]] = wk_f32_nearest(stk[fp + code[pc + 2]])
      pc += 3
    when 143
      stk[fp + code[pc + 1]] = wk_f32_sqrt(stk[fp + code[pc + 2]])
      pc += 3
    when 144
      stk[fp + code[pc + 1]] = wk_f32_add(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 145
      stk[fp + code[pc + 1]] = wk_f32_sub(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 146
      stk[fp + code[pc + 1]] = wk_f32_mul(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 147
      stk[fp + code[pc + 1]] = wk_f32_div(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 148
      stk[fp + code[pc + 1]] = wk_f32_min(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 149
      stk[fp + code[pc + 1]] = wk_f32_max(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 150
      stk[fp + code[pc + 1]] = (stk[fp + code[pc + 2]] & 2147483647) | (stk[fp + code[pc + 3]] & 2147483648)
      pc += 4
    when 151
      stk[fp + code[pc + 1]] = wk_f32_eq(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 152
      stk[fp + code[pc + 1]] = wk_f32_ne(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 153
      stk[fp + code[pc + 1]] = wk_f32_lt(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 154
      stk[fp + code[pc + 1]] = wk_f32_gt(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 155
      stk[fp + code[pc + 1]] = wk_f32_le(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 156
      stk[fp + code[pc + 1]] = wk_f32_ge(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 157
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] & 9223372036854775807
      pc += 3
    when 158
      stk[fp + code[pc + 1]] = stk[fp + code[pc + 2]] ^ minv
      pc += 3
    when 159
      stk[fp + code[pc + 1]] = wk_f64_ceil(stk[fp + code[pc + 2]])
      pc += 3
    when 160
      stk[fp + code[pc + 1]] = wk_f64_floor(stk[fp + code[pc + 2]])
      pc += 3
    when 161
      stk[fp + code[pc + 1]] = wk_f64_trunc(stk[fp + code[pc + 2]])
      pc += 3
    when 162
      stk[fp + code[pc + 1]] = wk_f64_nearest(stk[fp + code[pc + 2]])
      pc += 3
    when 163
      stk[fp + code[pc + 1]] = wk_f64_sqrt(stk[fp + code[pc + 2]])
      pc += 3
    when 164
      stk[fp + code[pc + 1]] = wk_f64_add(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 165
      stk[fp + code[pc + 1]] = wk_f64_sub(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 166
      stk[fp + code[pc + 1]] = wk_f64_mul(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 167
      stk[fp + code[pc + 1]] = wk_f64_div(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 168
      stk[fp + code[pc + 1]] = wk_f64_min(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 169
      stk[fp + code[pc + 1]] = wk_f64_max(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 170
      stk[fp + code[pc + 1]] = (stk[fp + code[pc + 2]] & 9223372036854775807) | (stk[fp + code[pc + 3]] & minv)
      pc += 4
    when 171
      stk[fp + code[pc + 1]] = wk_f64_eq(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 172
      stk[fp + code[pc + 1]] = wk_f64_ne(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 173
      stk[fp + code[pc + 1]] = wk_f64_lt(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 174
      stk[fp + code[pc + 1]] = wk_f64_gt(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 175
      stk[fp + code[pc + 1]] = wk_f64_le(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 176
      stk[fp + code[pc + 1]] = wk_f64_ge(stk[fp + code[pc + 2]], stk[fp + code[pc + 3]])
      pc += 4
    when 177
      x = stk[fp + code[pc + 2]]
      ck = wk_chk_f32_s32(x)
      if ck != 0
        st[4] = ck == 1 ? 4 : 3
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_sat_f32_s32(x)
      pc += 3
    when 178
      x = stk[fp + code[pc + 2]]
      ck = wk_chk_f32_u32(x)
      if ck != 0
        st[4] = ck == 1 ? 4 : 3
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_sat_f32_u32(x)
      pc += 3
    when 179
      x = stk[fp + code[pc + 2]]
      ck = wk_chk_f64_s32(x)
      if ck != 0
        st[4] = ck == 1 ? 4 : 3
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_sat_f64_s32(x)
      pc += 3
    when 180
      x = stk[fp + code[pc + 2]]
      ck = wk_chk_f64_u32(x)
      if ck != 0
        st[4] = ck == 1 ? 4 : 3
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_sat_f64_u32(x)
      pc += 3
    when 181
      x = stk[fp + code[pc + 2]]
      ck = wk_chk_f32_s64(x)
      if ck != 0
        st[4] = ck == 1 ? 4 : 3
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_sat_f32_s64(x)
      pc += 3
    when 182
      x = stk[fp + code[pc + 2]]
      ck = wk_chk_f32_u64(x)
      if ck != 0
        st[4] = ck == 1 ? 4 : 3
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_sat_f32_u64(x)
      pc += 3
    when 183
      x = stk[fp + code[pc + 2]]
      ck = wk_chk_f64_s64(x)
      if ck != 0
        st[4] = ck == 1 ? 4 : 3
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_sat_f64_s64(x)
      pc += 3
    when 184
      x = stk[fp + code[pc + 2]]
      ck = wk_chk_f64_u64(x)
      if ck != 0
        st[4] = ck == 1 ? 4 : 3
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_sat_f64_u64(x)
      pc += 3
    when 185
      stk[fp + code[pc + 1]] = wk_sat_f32_s32(stk[fp + code[pc + 2]])
      pc += 3
    when 186
      stk[fp + code[pc + 1]] = wk_sat_f32_u32(stk[fp + code[pc + 2]])
      pc += 3
    when 187
      stk[fp + code[pc + 1]] = wk_sat_f64_s32(stk[fp + code[pc + 2]])
      pc += 3
    when 188
      stk[fp + code[pc + 1]] = wk_sat_f64_u32(stk[fp + code[pc + 2]])
      pc += 3
    when 189
      stk[fp + code[pc + 1]] = wk_sat_f32_s64(stk[fp + code[pc + 2]])
      pc += 3
    when 190
      stk[fp + code[pc + 1]] = wk_sat_f32_u64(stk[fp + code[pc + 2]])
      pc += 3
    when 191
      stk[fp + code[pc + 1]] = wk_sat_f64_s64(stk[fp + code[pc + 2]])
      pc += 3
    when 192
      stk[fp + code[pc + 1]] = wk_sat_f64_u64(stk[fp + code[pc + 2]])
      pc += 3
    when 193
      stk[fp + code[pc + 1]] = wk_cvt_s32_f32(stk[fp + code[pc + 2]])
      pc += 3
    when 194
      stk[fp + code[pc + 1]] = wk_cvt_u32_f32(stk[fp + code[pc + 2]])
      pc += 3
    when 195
      stk[fp + code[pc + 1]] = wk_cvt_s64_f32(stk[fp + code[pc + 2]])
      pc += 3
    when 196
      stk[fp + code[pc + 1]] = wk_cvt_u64_f32(stk[fp + code[pc + 2]])
      pc += 3
    when 197
      stk[fp + code[pc + 1]] = wk_demote(stk[fp + code[pc + 2]])
      pc += 3
    when 198
      stk[fp + code[pc + 1]] = wk_cvt_s32_f64(stk[fp + code[pc + 2]])
      pc += 3
    when 199
      stk[fp + code[pc + 1]] = wk_cvt_u32_f64(stk[fp + code[pc + 2]])
      pc += 3
    when 200
      stk[fp + code[pc + 1]] = wk_cvt_s64_f64(stk[fp + code[pc + 2]])
      pc += 3
    when 201
      stk[fp + code[pc + 1]] = wk_cvt_u64_f64(stk[fp + code[pc + 2]])
      pc += 3
    when 202
      stk[fp + code[pc + 1]] = wk_promote(stk[fp + code[pc + 2]])
      pc += 3
    when 204
      ea = stk[fp + code[pc + 2]] + code[pc + 3]
      if ea + 8 > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_ld64(mem, ea)
      pc += 4
    when 205
      ea = stk[fp + code[pc + 2]] + code[pc + 3]
      if ea + 1 > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_ld8s(mem, ea) & m32
      pc += 4
    when 206
      ea = stk[fp + code[pc + 2]] + code[pc + 3]
      if ea + 1 > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_ld8u(mem, ea)
      pc += 4
    when 207
      ea = stk[fp + code[pc + 2]] + code[pc + 3]
      if ea + 2 > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_ld16s(mem, ea) & m32
      pc += 4
    when 208
      ea = stk[fp + code[pc + 2]] + code[pc + 3]
      if ea + 2 > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_ld16u(mem, ea)
      pc += 4
    when 209
      ea = stk[fp + code[pc + 2]] + code[pc + 3]
      if ea + 1 > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_ld8s(mem, ea)
      pc += 4
    when 210
      ea = stk[fp + code[pc + 2]] + code[pc + 3]
      if ea + 2 > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_ld16s(mem, ea)
      pc += 4
    when 211
      ea = stk[fp + code[pc + 2]] + code[pc + 3]
      if ea + 4 > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      stk[fp + code[pc + 1]] = wk_ld32s(mem, ea)
      pc += 4
    when 213
      ea = stk[fp + code[pc + 1]] + code[pc + 3]
      if ea + 8 > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      wk_st64(mem, ea, stk[fp + code[pc + 2]])
      pc += 4
    when 214
      ea = stk[fp + code[pc + 1]] + code[pc + 3]
      if ea + 1 > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      wk_st8(mem, ea, stk[fp + code[pc + 2]])
      pc += 4
    when 215
      ea = stk[fp + code[pc + 1]] + code[pc + 3]
      if ea + 2 > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      wk_st16(mem, ea, stk[fp + code[pc + 2]])
      pc += 4
    when 216
      ea = stk[fp + code[pc + 2]] + code[pc + 3]
      if ea + 16 > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      wk_ld128(mem, ea, stk, fp + code[pc + 1])
      pc += 4
    when 217
      ea = stk[fp + code[pc + 1]] + code[pc + 3]
      if ea + 16 > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      wk_st128(mem, ea, stk, fp + code[pc + 2])
      pc += 4
    when 218
      if stk[fp + code[pc + 1]] < 0
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      pc += 2
    when 219
      stk[fp + code[pc + 1]] = msize >> code[pc + 2]
      pc += 3
    when 220
      dd = stk[fp + code[pc + 1]]
      n = stk[fp + code[pc + 3]]
      if dd < 0 || n < 0 || dd + n > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      wk_memset(mem, dd, stk[fp + code[pc + 2]], n)
      pc += 4
    when 221
      dd = stk[fp + code[pc + 1]]
      ss = stk[fp + code[pc + 2]]
      n = stk[fp + code[pc + 3]]
      if dd < 0 || ss < 0 || n < 0 || dd + n > msize || ss + n > msize
        st[4] = 5
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      wk_memmove(mem, dd, ss, n)
      pc += 4
    when 222
      stk[fp + code[pc + 1]] = ostk[fp + code[pc + 2]] == nil ? 1 : 0
      pc += 3
    when 223
      stk[fp + code[pc + 1]] = w_ref_eq?(ostk[fp + code[pc + 2]], ostk[fp + code[pc + 3]]) ? 1 : 0
      pc += 4
    when 224
      if ostk[fp + code[pc + 1]] == nil
        st[4] = 10
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      pc += 2
    when 225
      if ostk[fp + code[pc + 1]] == nil
        pc = code[pc + 2]
      else
        pc += 3
    when 226
      if ostk[fp + code[pc + 1]] != nil
        pc = code[pc + 2]
      else
        pc += 3
    when 228
      r = wj_call(jt[code[pc + 1]], ctx, stk, fp)
      if r != 0
        st[4] = r
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 1
      csp -= 2
      pc = cstk[csp]
      fp = cstk[csp + 1]
      if pc < 0
        st[0] = pc
        st[1] = fp
        st[2] = csp
        return 0
    when 227
      wvop(stk, fp, code[pc + 1], code[pc + 2], code[pc + 3], code[pc + 4], code[pc + 5], code)
      pc += 6
    else
      st[4] = 99
      st[0] = pc
      st[1] = fp
      st[2] = csp
      return 1
  0

