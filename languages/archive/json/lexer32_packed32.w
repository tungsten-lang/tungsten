# JSON Lexer (Lex32 PACKED-i32 variant) — type + offset in one i32 store.
#
# Layout per cell:  [type:4][offset:28]  →  one i32 store per token.
# Max source size:  2^28 = 256 MB. Larger files must be sharded.
#
# Single store per token (vs the SoA variant's u8 + i32) keeps the L1d
# write port unsaturated. The shift+or to construct the value is free
# since it overlaps with the store μop.

## i64: count, pos, tc, v, w, c, c2, start, data_ptr, cp_mask
## i64: t_lbrace, t_rbrace, t_lbracket, t_rbracket, t_comma, t_colon
## i64: t_string, t_number, t_true, t_false, t_null, t_ws
## u32[]: lc
## i32[]: cells
-> json_tokenize_fast32_packed32(lc, count, cells)
  pos = 0
  tc = 0
  data_ptr = ccall_nobox("w_typed_array_data_ptr", lc)
  cp_mask = 0x1FFFFF

  t_lbrace   = 0x1 << 28
  t_rbrace   = 0x2 << 28
  t_lbracket = 0x3 << 28
  t_rbracket = 0x4 << 28
  t_comma    = 0x5 << 28
  t_colon    = 0x6 << 28
  t_string   = 0x7 << 28
  t_number   = 0x8 << 28
  t_true     = 0x9 << 28
  t_false    = 0xA << 28
  t_null     = 0xB << 28
  t_ws       = 0xC << 28

  loop
    v = lc[pos]
    if v == 0
      break
    c = (v >> 11) & cp_mask

    case v & 0x3F

    when 0x08
      cells[tc] = t_ws | pos
      pos++
      if (lc[pos] & 0x08) != 0
        pos++
        if (lc[pos] & 0x08) != 0
          pos++
          if (lc[pos] & 0x08) != 0
            pos++
            pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x08)
      tc++

    when 0x04
      if c == 0x7B
        cells[tc] = t_lbrace | pos
      elsif c == 0x7D
        cells[tc] = t_rbrace | pos
      elsif c == 0x5B
        cells[tc] = t_lbracket | pos
      elsif c == 0x5D
        cells[tc] = t_rbracket | pos
      elsif c == 0x2C
        cells[tc] = t_comma | pos
      else
        cells[tc] = t_colon | pos
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
      cells[tc] = t_number | pos
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
      if c == 0x74
        cells[tc] = t_true | pos
        pos += 4
      elsif c == 0x66
        cells[tc] = t_false | pos
        pos += 5
      else
        cells[tc] = t_null | pos
        pos += 4
      tc++

    else
      pos++

  tc
