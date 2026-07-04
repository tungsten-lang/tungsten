# JSON Lexer (Lex32 TWO-PASS variant)
#
# Pass 1: tokenize, writing only offsets into i32[]. Same as
#         lexer32_offs but kept here for self-containment.
# Pass 2: walk the offsets array, reload lc[offsets[i]], dispatch
#         on the flag byte (and codepoint for structural/keyword
#         classes), and write the type byte to a parallel u8 array.
#
# Compared to the single-pass packed-i32 design, this gambles that:
#   - Pass 1 runs at the offsets-only ceiling (~1740 MB/s)
#   - Pass 2 is a tight linear walk that hits L1d cleanly because the
#     offsets are monotonic and the LexChar reloads are sequential.
#
# If pass 2's per-token cost is < (packed_i32_cost - offsets_only_cost),
# the two-pass design wins. That's the experiment.

## i64: count, pos, tc, v, w, c, c2, start, data_ptr, cp_mask
## u32[]: lc
## i32[]: offsets
-> json_tokenize_offsets32(lc, count, offsets)
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

## i64: i, v, c, cp_mask
## u32[]: lc
## i32[]: offsets
## u8[]: types
-> json_derive_types32(lc, offsets, tc, types)
  cp_mask = 0x1FFFFF
  i = 0
  while i < tc
    v = lc[offsets[i]]
    case v & 0x3F
    when 0x08
      types[i] = 0xC
    when 0x04
      c = (v >> 11) & cp_mask
      if c == 0x7B
        types[i] = 0x1
      elsif c == 0x7D
        types[i] = 0x2
      elsif c == 0x5B
        types[i] = 0x3
      elsif c == 0x5D
        types[i] = 0x4
      elsif c == 0x2C
        types[i] = 0x5
      else
        types[i] = 0x6
    when 0x02
      types[i] = 0x7
    when 0x01
      types[i] = 0x8
    when 0x10
      c = (v >> 11) & cp_mask
      if c == 0x74
        types[i] = 0x9
      elsif c == 0x66
        types[i] = 0xA
      else
        types[i] = 0xB
    else
      types[i] = 0
    i += 1
  tc
