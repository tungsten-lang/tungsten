# JSON Lexer (Lex32 SoA variant) — see lexer32.w for token format details.
#
# This variant emits tokens as TWO parallel arrays instead of one packed
# i64 array:
#   types[tc]   : u8   token type (1..0xC)
#   offsets[tc] : i32  byte offset into the source LexChar stream
#
# Lengths are NOT stored; the parser recovers them as
#   length(i) = offsets[i+1] - offsets[i]
# which is correct because every byte of the source is covered by some
# token (whitespace included). The final sentinel offset is written by
# the bench/parser caller to terminate the recovery chain.
#
# Compared to the packed-i64 lexer this avoids:
#   - the two `shl` + two `or` ops needed to construct the packed value
#   - the i64 store (8 bytes) becomes one i32 + one u8 (5 bytes total)
#   - the per-token type-base constants (`t_ws`, `t_lbrace`, ...) collapse
#     to one-byte literals that the codegen materializes inline
#
# Type byte values (matches the low nibble of the packed-i64 type field):
#   0x1 lbrace   0x2 rbrace   0x3 lbracket   0x4 rbracket
#   0x5 comma    0x6 colon    0x7 string     0x8 number
#   0x9 true     0xA false    0xB null       0xC ws

## i64: count, pos, tc, v, w, c, c2, start, data_ptr, cp_mask
## u32[]: lc
## u8[]: types
## i32[]: offsets
-> json_tokenize_fast32_soa(lc, count, types, offsets)
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

    # ── Whitespace ───────────────────────────────────────────────────
    when 0x08
      offsets[tc] = pos
      types[tc] = 0xC
      pos++
      if (lc[pos] & 0x08) != 0
        pos++
        if (lc[pos] & 0x08) != 0
          pos++
          if (lc[pos] & 0x08) != 0
            pos++
            pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x08)
      tc++

    # ── Structural single-char ───────────────────────────────────────
    when 0x04
      offsets[tc] = pos
      if c == 0x7B
        types[tc] = 0x1
      elsif c == 0x7D
        types[tc] = 0x2
      elsif c == 0x5B
        types[tc] = 0x3
      elsif c == 0x5D
        types[tc] = 0x4
      elsif c == 0x2C
        types[tc] = 0x5
      else
        types[tc] = 0x6
      tc++
      pos++

    # ── String literal ───────────────────────────────────────────────
    when 0x02
      offsets[tc] = pos
      types[tc] = 0x7
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

    # ── Number literal ───────────────────────────────────────────────
    when 0x01
      offsets[tc] = pos
      types[tc] = 0x8
      pos++
      if (lc[pos] & 0x20) != 0
        pos++
        if (lc[pos] & 0x20) != 0
          pos++
          if (lc[pos] & 0x20) != 0
            pos++
            pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x20)
      tc++

    # ── Keyword (true / false / null) ────────────────────────────────
    when 0x10
      offsets[tc] = pos
      if c == 0x74
        types[tc] = 0x9
        pos += 4
      elsif c == 0x66
        types[tc] = 0xA
        pos += 5
      else
        types[tc] = 0xB
        pos += 4
      tc++

    else
      pos++

  tc
