# JSON Lexer (Lex32 EAT-WS-CCALL variant) — clean code via direct ccall.
#
# Same shape as eatws but the trailing-ws skip is a single ccall_nobox
# to w_lex32_scan_flag with no inline scalar prefix. With LTO inlining
# the ccall folds into the emit branch as straight-line NEON; the
# scalar prefix only matters when the helper is a real call, not when
# it's inlined.

## i64: count, pos, tc, v, w, c, c2, start, data_ptr, cp_mask
## i64: t_lbrace, t_rbrace, t_lbracket, t_rbracket, t_sep, t_string, t_lit
## u32[]: lc
## i32[]: cells
-> json_tokenize_fast32_eatws_cc(lc, count, cells)
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
      pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x08)

    when 0x10
      cells[tc] = t_lit | pos
      if c == 0x66
        pos += 5
      else
        pos += 4
      tc++
      pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x08)

    else
      pos++

  tc
