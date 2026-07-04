# JSON Lexer (Lex32 variant) — see lexer.w for token format details.
#
# Output: i32[] tokens, one packed cell per non-whitespace token.
# Cell layout: [type:3][offset:29] — 8 type slots, 512 MB max source.
#
# Type encoding (3 bits, 8 slots):
#   0  reserved        1  lbrace          2  rbrace
#   3  lbracket        4  rbracket        5  separator (comma OR colon)
#   6  string          7  literal (number / true / false / null)
#
# Whitespace is skipped without emitting a cell — JSON ws is insignificant
# per RFC 8259, and pretty-printed JSON has more ws tokens than real ones.
# The post-case ws-eat at the bottom of the loop body folds the
# advance-past-ws work into the same iteration as the preceding emit, so
# the dispatch loop never wastes an iteration on a no-token-emitted run.
#
# Comma vs colon, and number vs true vs false vs null, are disambiguated
# by the parser via lc[offset] — the parser dereferences that byte anyway
# when materializing the token value, so the disambiguation is free.

-> json_tokenize_fast32(lc, count, tokens) (u32[] i64 i32[]) i64
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
        pos = ccall_nobox("w_lex32_scan_flag_pure", data_ptr, count, pos, 0x08)

  loop
    v = lc[pos]
    if v == 0
      break
    c = (v >> 11) & cp_mask

    case v & 0x3F

    when 0x04
      if c == :-{
        tokens[tc] = t_lbrace | pos
      elsif c == :-}
        tokens[tc] = t_rbrace | pos
      elsif c == :-[
        tokens[tc] = t_lbracket | pos
      elsif c == :-]
        tokens[tc] = t_rbracket | pos
      else
        tokens[tc] = t_sep | pos
      tc++
      pos++

    when 0x02
      start = pos
      pos++
      loop
        pos = ccall_nobox("w_lex32_scan_to_cp_or", data_ptr, count, pos, :-\", :-\\)
        w = lc[pos]
        if w == 0
          break
        c2 = (w >> 11) & cp_mask
        if c2 == :-\"
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
            pos = ccall_nobox("w_lex32_scan_flag_pure", data_ptr, count, pos, 0x20)
      tc++

    when 0x10
      tokens[tc] = t_lit | pos
      if c == :-f
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
          pos = ccall_nobox("w_lex32_scan_flag_pure", data_ptr, count, pos, 0x08)

  tc
