# jsn/regexp_jit — Native ARM64 Regular Expression JIT Compiler for Blade JS.
#
# Compiles ASCII-eligible JS:Regex programs (RX_CHAR, RX_STR, RX_ANY, RX_CLASS, RX_OPEN,
# RX_CLOSE, RX_REP1 greedy/lazy, RX_ALT, RX_BOL, RX_EOL, RX_WORDB, RX_NWORDB, RX_EMPTY,
# RX_MATCH) directly to native ARM64 machine code using JS:A64!
#
# ABI:
#   i64 rx_jit_exec(i64 src_ptr, i64 len, i64 start_pos, i64 caps_ptr, i64 sticky)
#     Returns match_end (>= 0) on match (with caps_ptr[0..2*ngroups+1] populated),
#     or -1 on no match.
#
# Optimizations:
#   - Fast ARM64 first-byte skip-search (single char, single range `[a-z]` / `\d`, or 128-bit ASCII bitset)
#   - Zero-backtracking linear codegen when every RX_REP1 is provably disjoint from its continuation
#   - Full ARM64 SP-based backtracking for general RX_ALT & non-disjoint RX_REP1

in JS

# Raw 5-arg native call trampoline for rx_jit_exec(src_ptr, len, start_pos, caps_ptr, sticky).
fn jit_raw_call5(fp, a0, a1, a2, a3, a4) (i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4)
    ret i64 %r
  IR

# Compute ASCII 128-bit match bitset [lo_0_63, hi_64_127] for a single-char RxNode (ASCII input only!).
# Returns [lo, hi] (each stored as 4 x 16-bit chunks [c0, c1, c2, c3, c4, c5, c6, c7] to stay inside
# 48-bit Tungsten Int with ZERO WBigint boxing!), or nil if unsupported.
-> rx_jit_ascii_mask(n, icase, dotall)
  k = n.kind
  m = [0, 0, 0, 0, 0, 0, 0, 0]   # 8 x 16-bit words covering ASCII bytes 0..127
  if k == RX_CHAR
    c = n.c
    if c >= 0 && c < 128
      rx_mask_set(m, c)
      if icase
        rx_mask_set(m, c + 32) if c >= 65 && c <= 90
        rx_mask_set(m, c - 32) if c >= 97 && c <= 122
    return m
  if k == RX_ANY
    i = 0
    while i < 128
      if dotall || (i != 10 && i != 13)
        rx_mask_set(m, i)
      i += 1
    return m
  if k == RX_CLASS
    return nil if n.props != nil
    rs = n.ranges
    i = 0
    while i < rs.size
      lo = rs[i]
      hi = rs[i + 1]
      lo = 0 if lo < 0
      hi = 127 if hi > 127
      c = lo
      while c <= hi
        rx_mask_set(m, c)
        if icase
          rx_mask_set(m, c + 32) if c >= 65 && c <= 90
          rx_mask_set(m, c - 32) if c >= 97 && c <= 122
        c += 1
      i += 2
    if n.neg
      w = 0
      while w < 8
        m[w] = m[w] ^ 0xFFFF
        w += 1
    return m
  nil

-> rx_mask_set(m, c)
  m[c >> 4] = m[c >> 4] | (1 << (c & 15))
  nil

-> rx_mask_disjoint?(m1, m2)
  i = 0
  while i < 8
    return false if (m1[i] & m2[i]) != 0
    i += 1
  true

# Analyze an 8-word ASCII mask:
#   [:empty]
#   [:char, c]
#   [:range, lo, hi]
#   [:bitset, m]
-> rx_mask_classify(m)
  first = -1
  last = -1
  cnt = 0
  c = 0
  while c < 128
    if (m[c >> 4] & (1 << (c & 15))) != 0
      first = c if first < 0
      last = c
      cnt += 1
    c += 1
  return [:empty] if cnt == 0
  return [:char, first] if cnt == 1
  return [:range, first, last] if last - first + 1 == cnt
  [:bitset, m]

# Check if greedy RX_REP1(body) is provably disjoint from its continuation `nxt`.
-> rx_rep1_disjoint?(rep, icase, dotall)
  return false if !rep.greedy
  m1 = rx_jit_ascii_mask(rep.body, icase, dotall)
  return false if m1 == nil
  cur = rep.nxt
  steps = 0
  while cur != nil && steps < 16
    k = cur.kind
    return true if k == RX_MATCH
    if k == RX_EMPTY || k == RX_OPEN || k == RX_CLOSE
      cur = cur.nxt
      steps += 1
      next
    if k == RX_CHAR || k == RX_ANY || k == RX_CLASS
      m2 = rx_jit_ascii_mask(cur, icase, dotall)
      return m2 != nil && rx_mask_disjoint?(m1, m2)
    if k == RX_REP1 && cur.min >= 1
      m2 = rx_jit_ascii_mask(cur.body, icase, dotall)
      return m2 != nil && rx_mask_disjoint?(m1, m2)
    return false
  false

# Check if an entire JS:Regex is eligible for native linear ARM64 compilation!
# (Zero backtracking: no RX_ALT, no RX_REP, no RX_BACKREF, no RX_LOOK, every RX_REP1 disjoint!)
-> rx_jit_is_linear?(rx)
  return false if rx.unicode || rx.vmode || rx.ngroups > 15
  n = rx.prog
  seen = 0
  while n != nil && seen < 256
    k = n.kind
    if k == RX_MATCH
      return true
    elsif k == RX_CHAR || k == RX_ANY || k == RX_EMPTY || k == RX_OPEN || k == RX_CLOSE || k == RX_BOL || k == RX_EOL || k == RX_WORDB || k == RX_NWORDB
      n = n.nxt
    elsif k == RX_CLASS
      return false if n.props != nil
      n = n.nxt
    elsif k == RX_STR
      n = n.nxt
    elsif k == RX_REP1
      return false if n.body.kind == RX_CLASS && n.body.props != nil
      return false if !rx_rep1_disjoint?(n, rx.icase, rx.dotall)
      n = n.nxt
    else
      return false
    seen += 1
  false

# Emit ARM64 test for byte in `w_reg` matching classified mask `cl`.
# Branches to `lbl` if matched (when `br_match == true`) or if NOT matched (`br_match == false`).
# Clobbers R_X10, R_X11, R_X12.
-> rx_emit_char_test(a, w_reg, cl, lbl, br_match)
  kind = cl[0]
  if kind == :empty
    a.b(lbl) if !br_match
    return nil
  if kind == :char
    a.cmp_wi(w_reg, cl[1])
    a.b_cond(br_match ? CC_EQ : CC_NE, lbl)
    return nil
  if kind == :range
    lo = cl[1]
    span = cl[2] - lo
    if lo == 0
      a.cmp_wi(w_reg, span)
    else
      a.sub_wi(R_X10, w_reg, lo)
      a.cmp_wi(R_X10, span)
    a.b_cond(br_match ? CC_LS : CC_HI, lbl)
    return nil
  # :bitset (128-bit ASCII mask in 8 x 16-bit words m[0..7])
  m = cl[1]
  l_hi = a.new_label
  l_chk = a.new_label
  a.cmp_wi(w_reg, 64)
  a.b_cond(CC_GE, l_hi)
  # Low 64 bits (0..63)
  a.movz_x(R_X10, m[0], 0)
  a.movk_x(R_X10, m[1], 1) if m[1] != 0
  a.movk_x(R_X10, m[2], 2) if m[2] != 0
  a.movk_x(R_X10, m[3], 3) if m[3] != 0
  a.mov_w(R_X11, w_reg)
  a.b(l_chk)
  a.bind(l_hi)
  # High 64 bits (64..127)
  a.movz_x(R_X10, m[4], 0)
  a.movk_x(R_X10, m[5], 1) if m[5] != 0
  a.movk_x(R_X10, m[6], 2) if m[6] != 0
  a.movk_x(R_X10, m[7], 3) if m[7] != 0
  a.sub_wi(R_X11, w_reg, 64)
  a.bind(l_chk)
  # Test bit (R_X10 >> R_X11) & 1 -> use LSR variable? Wait: arm64.w has lsr_w (32-bit), check 64-bit!
  # Use LSR X10, X10, X11 (encoding: 0x9AC02400 | (rm << 16) | (rn << 5) | rd)!
  a.emit(0x9AC02400 | (R_X11 << 16) | (R_X10 << 5) | R_X10)
  a.tst_x_lowmask(R_X10, 1)
  a.b_cond(br_match ? CC_NE : CC_EQ, lbl)
  nil

# Emit ARM64 word-char test (`[0-9A-Za-z_]`) on byte in `w_reg` -> result 0 or 1 in `dst_reg`.
-> rx_emit_is_word(a, dst_reg, w_reg)
  l_yes = a.new_label
  l_done = a.new_label
  a.sub_wi(R_X10, w_reg, 48)
  a.cmp_wi(R_X10, 9)
  a.b_cond(CC_LS, l_yes)
  a.sub_wi(R_X10, w_reg, 65)
  a.cmp_wi(R_X10, 25)
  a.b_cond(CC_LS, l_yes)
  a.sub_wi(R_X10, w_reg, 97)
  a.cmp_wi(R_X10, 25)
  a.b_cond(CC_LS, l_yes)
  a.cmp_wi(w_reg, 95)
  a.b_cond(CC_EQ, l_yes)
  a.movz_x(dst_reg, 0)
  a.b(l_done)
  a.bind(l_yes)
  a.movz_x(dst_reg, 1)
  a.bind(l_done)
  nil

# Compile a linear (zero-backtrack) JS:Regex to native ARM64!
# Returns executable function pointer (i64) or 0 if not eligible.
-> rx_jit_compile(rx)
  return 0 if !jit_mem_ready?() || !rx_jit_is_linear?(rx)
  a = JS:A64.new(256)
  # Prologue: save fp, lr, x19..x24 (64 bytes)
  a.sub_i(R_SP, R_SP, 64)
  a.stp_x(R_FP, R_LR, R_SP, 0)
  a.mov_sp(R_FP, R_SP)
  a.stp_x(R_X19, R_X20, R_SP, 16)
  a.stp_x(R_X21, R_X22, R_SP, 32)
  a.stp_x(R_X23, R_X24, R_SP, 48)
  # Pin args:
  #   x19 = src_ptr, x20 = len, x21 = cur_start, x22 = caps_ptr, x23 = sticky
  a.mov_r(R_X19, R_X0)
  a.mov_r(R_X20, R_X1)
  a.mov_r(R_X21, R_X2)
  a.mov_r(R_X22, R_X3)
  a.mov_r(R_X23, R_X4)

  l_search = a.new_label
  l_try = a.new_label
  l_fail = a.new_label
  l_nomatch = a.new_label
  l_ret = a.new_label

  # Detect leading required first-byte class for fast skip-search!
  first_cl = nil
  anchored_bol = false
  fn0 = rx.prog
  while fn0 != nil && (fn0.kind == RX_EMPTY || fn0.kind == RX_OPEN || fn0.kind == RX_CLOSE)
    fn0 = fn0.nxt
  if fn0 != nil
    if fn0.kind == RX_BOL && !rx.multiline
      anchored_bol = true
    elsif fn0.kind == RX_CHAR || fn0.kind == RX_CLASS
      fm = rx_jit_ascii_mask(fn0, rx.icase, rx.dotall)
      first_cl = rx_mask_classify(fm) if fm != nil
    elsif fn0.kind == RX_REP1 && fn0.min >= 1
      fm = rx_jit_ascii_mask(fn0.body, rx.icase, rx.dotall)
      first_cl = rx_mask_classify(fm) if fm != nil

  # Search loop
  a.bind(l_search)
  if anchored_bol
    a.cbnz_x(R_X21, l_nomatch)
  if first_cl != nil && first_cl[0] != :empty
    # If sticky, skip the skip-loop and try once at x21
    a.cbnz_x(R_X23, l_try)
    l_skip = a.new_label
    a.bind(l_skip)
    a.cmp_r(R_X21, R_X20)
    a.b_cond(CC_GE, l_nomatch)
    a.ldrb_idx(R_X9, R_X19, R_X21)
    rx_emit_char_test(a, R_X9, first_cl, l_try, true)
    a.add_i(R_X21, R_X21, 1)
    a.b(l_skip)
  else
    a.cmp_r(R_X21, R_X20)
    a.b_cond(CC_GT, l_nomatch)

  a.bind(l_try)
  a.mov_r(R_X24, R_X21)   # x24 = pos = cur_start

  # Emit straight-line sequence of RxNodes!
  n = rx.prog
  while n != nil
    k = n.kind
    if k == RX_MATCH
      a.str_x(R_X21, R_X22, 0)   # caps[0] = cur_start
      a.str_x(R_X24, R_X22, 8)   # caps[1] = pos
      a.movz_x(R_X9, rx.ngroups)
      a.str_x(R_X9, R_X22, 240)  # caps[30] = ngroups (for sound SRA bounds check)
      a.mov_r(R_X0, R_X24)       # return match_end
      a.b(l_ret)
      break
    elsif k == RX_EMPTY
      nil
    elsif k == RX_OPEN
      a.str_x(R_X24, R_X22, n.group * 16)
    elsif k == RX_CLOSE
      a.str_x(R_X24, R_X22, n.group * 16 + 8)
    elsif k == RX_CHAR || k == RX_ANY || k == RX_CLASS
      a.cmp_r(R_X24, R_X20)
      a.b_cond(CC_GE, l_fail)
      a.ldrb_idx(R_X9, R_X19, R_X24)
      cl = rx_mask_classify(rx_jit_ascii_mask(n, rx.icase, rx.dotall))
      rx_emit_char_test(a, R_X9, cl, l_fail, false)
      a.add_i(R_X24, R_X24, 1)
    elsif k == RX_STR
      us = n.str
      j = 0
      while j < us.size
        a.cmp_r(R_X24, R_X20)
        a.b_cond(CC_GE, l_fail)
        a.ldrb_idx(R_X9, R_X19, R_X24)
        a.cmp_wi(R_X9, us[j])
        a.b_cond(CC_NE, l_fail)
        a.add_i(R_X24, R_X24, 1)
        j += 1
    elsif k == RX_REP1
      # Provably disjoint greedy repeat of single-char node!
      cl = rx_mask_classify(rx_jit_ascii_mask(n.body, rx.icase, rx.dotall))
      mn = n.min
      mx = n.max
      a.mov_r(R_X13, R_X24)     # x13 = rep_start
      if mx >= 0
        a.mov_imm64(R_X14, mx)
        a.add_r(R_X14, R_X24, R_X14)
        a.cmp_r(R_X14, R_X20)
        a.csel_x(R_X14, R_X20, R_X14, CC_GT)   # x14 = min(len, pos + max)
      else
        a.mov_r(R_X14, R_X20)                   # x14 = len
      l_rlp = a.new_label
      l_rdone = a.new_label
      a.bind(l_rlp)
      a.cmp_r(R_X24, R_X14)
      a.b_cond(CC_GE, l_rdone)
      a.ldrb_idx(R_X9, R_X19, R_X24)
      rx_emit_char_test(a, R_X9, cl, l_rdone, false)
      a.add_i(R_X24, R_X24, 1)
      a.b(l_rlp)
      a.bind(l_rdone)
      if mn > 0
        a.sub_r(R_X10, R_X24, R_X13)
        if mn <= 4095
          a.cmp_i(R_X10, mn)
        else
          a.mov_imm64(R_X11, mn)
          a.cmp_r(R_X10, R_X11)
        a.b_cond(CC_LT, l_fail)
    elsif k == RX_BOL
      if !rx.multiline
        a.cbnz_x(R_X24, l_fail)
      else
        l_bok = a.new_label
        a.cbz_x(R_X24, l_bok)
        a.sub_i(R_X10, R_X24, 1)
        a.ldrb_idx(R_X9, R_X19, R_X10)
        a.cmp_wi(R_X9, 10)
        a.b_cond(CC_EQ, l_bok)
        a.cmp_wi(R_X9, 13)
        a.b_cond(CC_NE, l_fail)
        a.bind(l_bok)
    elsif k == RX_EOL
      if !rx.multiline
        a.cmp_r(R_X24, R_X20)
        a.b_cond(CC_NE, l_fail)
      else
        l_eok = a.new_label
        a.cmp_r(R_X24, R_X20)
        a.b_cond(CC_EQ, l_eok)
        a.ldrb_idx(R_X9, R_X19, R_X24)
        a.cmp_wi(R_X9, 10)
        a.b_cond(CC_EQ, l_eok)
        a.cmp_wi(R_X9, 13)
        a.b_cond(CC_NE, l_fail)
        a.bind(l_eok)
    elsif k == RX_WORDB || k == RX_NWORDB
      # prev_w in x13, cur_w in x14
      l_p0 = a.new_label
      l_pd = a.new_label
      a.cbz_x(R_X24, l_p0)
      a.sub_i(R_X10, R_X24, 1)
      a.ldrb_idx(R_X9, R_X19, R_X10)
      rx_emit_is_word(a, R_X13, R_X9)
      a.b(l_pd)
      a.bind(l_p0)
      a.movz_x(R_X13, 0)
      a.bind(l_pd)
      l_c0 = a.new_label
      l_cd = a.new_label
      a.cmp_r(R_X24, R_X20)
      a.b_cond(CC_GE, l_c0)
      a.ldrb_idx(R_X9, R_X19, R_X24)
      rx_emit_is_word(a, R_X14, R_X9)
      a.b(l_cd)
      a.bind(l_c0)
      a.movz_x(R_X14, 0)
      a.bind(l_cd)
      a.cmp_r(R_X13, R_X14)
      a.b_cond(k == RX_WORDB ? CC_EQ : CC_NE, l_fail)
    n = n.nxt

  # Fail at cur_start: if sticky -> nomatch, else cur_start++ and retry!
  a.bind(l_fail)
  a.cbnz_x(R_X23, l_nomatch)
  a.add_i(R_X21, R_X21, 1)
  a.b(l_search)

  a.bind(l_nomatch)
  a.movn_x(R_X0, 0)   # return -1

  a.bind(l_ret)
  a.ldp_x(R_X23, R_X24, R_SP, 48)
  a.ldp_x(R_X21, R_X22, R_SP, 32)
  a.ldp_x(R_X19, R_X20, R_SP, 16)
  a.ldp_x(R_FP, R_LR, R_SP, 0)
  a.add_i(R_SP, R_SP, 64)
  a.ret
  a.finalize
