# JSON Lexer (Lex16 variant) — see lexer.w for token format details.
#
# Lex16 LexChar: codepoint in high byte (or 0x80 placeholder for non-ASCII),
# 8-bit flag byte in low byte. Codepoint extract is `v >> 8`.
#
# Output: i32[] tokens, one packed cell per non-whitespace token.
# Cell layout: [type:3][offset:29] — 8 type slots, 512 MB max source.
# Type encoding matches lexer32.w (parser disambiguates separators / literals).

## i64: pos, tc, v, w, c, c2, start, data_ptr
## i64: t_lbrace, t_rbrace, t_lbracket, t_rbracket, t_sep, t_string, t_lit
-> json_tokenize_fast16(lc, count, tokens) (u16[] i64 i32[]) i64
  pos = 0
  tc = 0
  data_ptr = ccall_nobox("w_array_data_ptr", lc)

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
        tokens[tc] = t_lbrace | pos
      elsif c == 0x7D
        tokens[tc] = t_rbrace | pos
      elsif c == 0x5B
        tokens[tc] = t_lbracket | pos
      elsif c == 0x5D
        tokens[tc] = t_rbracket | pos
      else
        tokens[tc] = t_sep | pos
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
      tokens[tc] = t_string | start
      tc++

    when 0x01
      tokens[tc] = t_lit | pos
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
      tokens[tc] = t_lit | pos
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
