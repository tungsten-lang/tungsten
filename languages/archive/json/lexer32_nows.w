# JSON Lexer (Lex32 NO-WS variant) — packed-i32 cells, whitespace skipped.
#
# JSON whitespace is insignificant per RFC 8259, so we don't emit a token
# for it — we just advance `pos` through ws runs and continue. This drops
# the per-token store for what's typically the most common token class
# in pretty-printed JSON (often 30-50% of all tokens).
#
# Layout per cell: [type:3][offset:29] in i32. 512 MB max source.
# Type encoding (7 used, 1 reserved):
#   0  (reserved — was ws)
#   1  lbrace
#   2  rbrace
#   3  lbracket
#   4  rbracket
#   5  separator   (comma OR colon)
#   6  string
#   7  literal     (number / true / false / null)

## i64: count, pos, tc, v, w, c, c2, start, data_ptr, cp_mask
## i64: t_lbrace, t_rbrace, t_lbracket, t_rbracket, t_sep, t_string, t_lit
## u32[]: lc
## i32[]: cells
-> json_tokenize_fast32_nows(lc, count, cells)
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

  loop
    v = lc[pos]
    if v == 0
      break
    c = (v >> 11) & cp_mask

    case v & 0x3F

    when 0x08
      # Whitespace — advance pos but emit no token.
      pos++
      if (lc[pos] & 0x08) != 0
        pos++
        if (lc[pos] & 0x08) != 0
          pos++
          if (lc[pos] & 0x08) != 0
            pos++
            pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x08)

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
        cells[tc] = t_sep | pos                         # comma or colon
      tc++
      pos++

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

    when 0x01
      cells[tc] = t_lit | pos                            # number
      pos++
      if (lc[pos] & 0x20) != 0
        pos++
        if (lc[pos] & 0x20) != 0
          pos++
          if (lc[pos] & 0x20) != 0
            pos++
            pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x20)
      tc++

    when 0x10
      cells[tc] = t_lit | pos                            # true / false / null
      if c == 0x66
        pos += 5
      else
        pos += 4
      tc++

    else
      pos++

  tc
