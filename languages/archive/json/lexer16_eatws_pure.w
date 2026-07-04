# JSON Lexer (Lex16 EAT-WS-PURE variant) — packed-i32 cells, post-case
# whitespace eat, no whitespace tokens emitted. Mirrors the design of
# lexer32_eatws_pure for the u16 LexChar layout.
#
# Layout per cell: [type:3][offset:29] in i32. 512 MB max source.
# Type encoding:
#   0  (reserved — was ws)
#   1  lbrace      2  rbrace      3  lbracket     4  rbracket
#   5  separator   (comma OR colon — parser disambiguates from lc[offset])
#   6  string
#   7  literal     (number / true / false / null — parser disambiguates)

## i64: count, pos, tc, v, w, c, c2, start, data_ptr
## i64: t_lbrace, t_rbrace, t_lbracket, t_rbracket, t_sep, t_string, t_lit
## u16[]: lc
## i32[]: cells
-> json_tokenize_fast16_eatws_pure(lc, count, cells)
  pos = 0
  tc = 0
  data_ptr = ccall_nobox("w_typed_array_data_ptr", lc)

  t_lbrace   = 0x1 << 29
  t_rbrace   = 0x2 << 29
  t_lbracket = 0x3 << 29
  t_rbracket = 0x4 << 29
  t_sep      = 0x5 << 29
  t_string   = 0x6 << 29
  t_lit      = 0x7 << 29

  # Leading whitespace
  if (lc[pos] & 0x08) != 0
    pos++
    if (lc[pos] & 0x08) != 0
      pos++
      if (lc[pos] & 0x08) != 0
        pos++
        pos = ccall_nobox("w_lex16_scan_flag", data_ptr, count, pos, 0x08)

  loop
    v = lc[pos]
    if v == 0
      break
    c = v >> 8

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

    when 0x02
      start = pos
      pos++
      loop
        pos = ccall_nobox("w_lex16_scan_to_cp_or", data_ptr, count, pos, 0x22, 0x5C)
        w = lc[pos]
        if w == 0
          break
        c2 = w >> 8
        if c2 == 0x22
          pos++
          break
        pos += 2
      cells[tc] = t_string | start
      tc++

    when 0x01
      cells[tc] = t_lit | pos
      pos++
      if (lc[pos] & 0x20) != 0
        pos++
        if (lc[pos] & 0x20) != 0
          pos++
          if (lc[pos] & 0x20) != 0
            pos++
            pos = ccall_nobox("w_lex16_scan_flag", data_ptr, count, pos, 0x20)
      tc++

    when 0x10
      cells[tc] = t_lit | pos
      if c == 0x66
        pos += 5
      else
        pos += 4
      tc++

    else
      pos++

    # Eat trailing whitespace once per iteration
    if (lc[pos] & 0x08) != 0
      pos++
      if (lc[pos] & 0x08) != 0
        pos++
        if (lc[pos] & 0x08) != 0
          pos++
          pos = ccall_nobox("w_lex16_scan_flag", data_ptr, count, pos, 0x08)

  tc
