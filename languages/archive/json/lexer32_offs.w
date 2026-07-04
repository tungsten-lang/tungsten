# JSON Lexer (Lex32 OFFSETS-ONLY variant) — measurement-only.
#
# Writes only `offsets[tc] = start` per token, no type, no length.
# This is the absolute minimum work the lexer can do per token while
# still emitting one record per token. Used to isolate whether the
# u8 type-store in the SoA variant is what's costing us.

## i64: count, pos, tc, v, w, c, c2, start, data_ptr, cp_mask
## u32[]: lc
## i32[]: offsets
-> json_tokenize_fast32_offs(lc, count, offsets)
  pos = 0
  tc = 0
  data_ptr = ccall_nobox("w_typed_array_data_ptr", lc)
  cp_mask = 0x1FFFFF

  loop
    v = lc[pos]
    if v == 0
      break
    c = (v >> 11) & cp_mask

    case v & 0x3F

    when 0x08
      offsets[tc] = pos
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
      offsets[tc] = pos
      tc++
      pos++

    when 0x02
      offsets[tc] = pos
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
      tc++

    when 0x01
      offsets[tc] = pos
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
      offsets[tc] = pos
      if c == 0x74
        pos += 4
      elsif c == 0x66
        pos += 5
      else
        pos += 4
      tc++

    else
      pos++

  tc
