# JSON Lexer (Lex64 variant)
#
# Lex64 LexChar: 21-bit codepoint at bits 18-38, 8-bit flag byte at bits 0-7.
# Codepoint extract is `(v >> 18) & 0x1FFFFF`. Sentinel is the all-zero word.
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
# per RFC 8259. The post-case ws-eat at the bottom of the loop body folds
# the advance-past-ws work into the same iteration as the preceding emit.
#
# Comma vs colon, and number vs true vs false vs null, are disambiguated
# by the parser via lc[offset] when materializing the token value.
#
# This Lex64 variant uses scalar `while` loops for the ws/number/string
# scans rather than NEON helpers — there are no NEON helpers for the i64
# LexChar layout because each entry is already 8 bytes (no narrow ops to
# vectorize). Lex16 and Lex32 are faster in practice for this reason.

## i64: pos, tc, v, w, c, c2, start, data_ptr, cp_mask
## i64: t_lbrace, t_rbrace, t_lbracket, t_rbracket, t_sep, t_string, t_lit
-> json_tokenize_fast(lc, count, tokens) (i64[] i64 i32[]) i64
  pos = 0
  tc = 0
  data_ptr = ccall_nobox("w_array_data_ptr", lc)
  cp_mask = 0x1FFFFF

  t_lbrace   = 0x1 << 29
  t_rbrace   = 0x2 << 29
  t_lbracket = 0x3 << 29
  t_rbracket = 0x4 << 29
  t_sep      = 0x5 << 29
  t_string   = 0x6 << 29
  t_lit      = 0x7 << 29

  # Leading whitespace
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
      tokens[tc] = t_string | start
      tc++

    when 0x01
      tokens[tc] = t_lit | pos
      pos++
      while (lc[pos] & 0x20) != 0
        pos++
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
    while (lc[pos] & 0x08) != 0
      pos++

  tc
