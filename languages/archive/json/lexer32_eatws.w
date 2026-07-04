# JSON Lexer (Lex32 EAT-WS variant) — packed-i32 cells, ws inlined into emit branches.
#
# Builds on the no-ws variant by also eliminating the `when 0x08` case
# dispatch entirely. Each emit branch (struct, string, number, keyword)
# advances `pos` past any trailing whitespace before returning to the
# top of the loop, so the next iteration always sees a real token.
#
# Wins ~16M extra case-dispatch iterations per round on big.json by
# folding the ws-advance work into the same iteration as the preceding
# emit. Leading-ws at file start is handled by a single skip before the
# loop.
#
# Layout per cell: [type:3][offset:29] in i32. 512 MB max source.
# Type encoding: same as lexer32_nows.w (0 reserved, 1..7 used).

## i64: count, pos, tc, v, w, c, c2, start, data_ptr, cp_mask
## i64: t_lbrace, t_rbrace, t_lbracket, t_rbracket, t_sep, t_string, t_lit
## u32[]: lc
## i32[]: cells
-> json_tokenize_fast32_eatws(lc, count, cells)
  pos = 0
  tc = 0
  data_ptr = ccall_nobox("w_typed_array_data_ptr", lc)
  cp_mask = 0x1FFFFF

  t_lbrace   = 0x1 << 29
  t_rbrace   = 0x2 << 29
  t_lbracket = 0x3 << 29
  t_rbracket = 0x4 << 29
  t_sep      = 0x5 << 29
  t_string   = 0x6 << 29
  t_lit      = 0x7 << 29

  # Leading whitespace at file start
  if (lc[pos] & 0x08) != 0
    pos++
    if (lc[pos] & 0x08) != 0
      pos++
      if (lc[pos] & 0x08) != 0
        pos++
        pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x08)

  loop
    v = lc[pos]
    if v == 0
      break
    c = (v >> 11) & cp_mask

    case v & 0x3F

    when 0x04
      if c == 0x7B
        cells[tc] = t_lbrace | pos
      elsif c == 0x7D
        cells[tc] = t_rbrace | pos
      elsif c == 0x5B
        cells[tc] = t_lbracket | pos
      elsif c == 0x5D
        cells[tc] = t_rbracket | pos
      else
        cells[tc] = t_sep | pos
      tc++
      pos++
      # Eat trailing whitespace
      if (lc[pos] & 0x08) != 0
        pos++
        if (lc[pos] & 0x08) != 0
          pos++
          if (lc[pos] & 0x08) != 0
            pos++
            pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x08)

    when 0x02
      start = pos
      pos++
      loop
        pos = ccall_nobox("w_lex32_scan_to_cp_or", data_ptr, count, pos, 0x22, 0x5C)
        w = lc[pos]
        if w == 0
          break
        c2 = (w >> 11) & cp_mask
        if c2 == 0x22
          pos++
          break
        pos += 2
      cells[tc] = t_string | start
      tc++
      # Eat trailing whitespace
      if (lc[pos] & 0x08) != 0
        pos++
        if (lc[pos] & 0x08) != 0
          pos++
          if (lc[pos] & 0x08) != 0
            pos++
            pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x08)

    when 0x01
      cells[tc] = t_lit | pos
      pos++
      if (lc[pos] & 0x20) != 0
        pos++
        if (lc[pos] & 0x20) != 0
          pos++
          if (lc[pos] & 0x20) != 0
            pos++
            pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x20)
      tc++
      # Eat trailing whitespace
      if (lc[pos] & 0x08) != 0
        pos++
        if (lc[pos] & 0x08) != 0
          pos++
          if (lc[pos] & 0x08) != 0
            pos++
            pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x08)

    when 0x10
      cells[tc] = t_lit | pos
      if c == 0x66
        pos += 5
      else
        pos += 4
      tc++
      # Eat trailing whitespace
      if (lc[pos] & 0x08) != 0
        pos++
        if (lc[pos] & 0x08) != 0
          pos++
          if (lc[pos] & 0x08) != 0
            pos++
            pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x08)

    else
      pos++

  tc
