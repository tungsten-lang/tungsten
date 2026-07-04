# JSON Lexer (Lex64 EAT-WS-PURE variant) — packed-i32 cells, post-case
# whitespace eat, no whitespace tokens emitted. Mirrors the design of
# lexer32_eatws_pure for the i64 LexChar layout.
#
# Lex64 LexChar: 21-bit codepoint at bits 18-38, 8-bit flag byte at bits 0-7.
# Codepoint extract is `(v >> 18) & 0x1FFFFF`. Sentinel is the all-zero word.
# The Lex64 input runs in i64[] arrays, but we still emit the cells as i32.
#
# Layout per cell: [type:3][offset:29] in i32. 512 MB max source.

## i64: count, pos, tc, v, w, c, c2, start, data_ptr, cp_mask
## i64: t_lbrace, t_rbrace, t_lbracket, t_rbracket, t_sep, t_string, t_lit
## i64[]: lc
## i32[]: cells
-> json_tokenize_fast_eatws_pure(lc, count, cells)
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

  # Leading whitespace
  if (lc[pos] & 0x08) != 0
    pos++
    if (lc[pos] & 0x08) != 0
      pos++
      if (lc[pos] & 0x08) != 0
        pos++
        while (lc[pos] & 0x08) != 0
          pos++

  loop
    v = lc[pos]
    c = (v >> 18) & cp_mask
    if c == 0
      break

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
        w = lc[pos]
        if w == 0
          break
        c2 = (w >> 18) & cp_mask
        if c2 == 0x5C
          pos += 2
        elsif c2 == 0x22
          pos++
          break
        else
          pos++
      cells[tc] = t_string | start
      tc++

    when 0x01
      cells[tc] = t_lit | pos
      pos++
      while (lc[pos] & 0x20) != 0
        pos++
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
    while (lc[pos] & 0x08) != 0
      pos++

  tc
