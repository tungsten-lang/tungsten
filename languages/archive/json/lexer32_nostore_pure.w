# JSON Lexer (Lex32 variant) — see lexer.w for token format.
#
# Lex32 LexChar: 21-bit codepoint at bits 11-31, 8-bit flag byte at
# bits 0-7. Codepoint extract is `(v >> 11) & 0x1FFFFF`. Sentinel is
# the all-zero word.
#
# Vectorized hot loops via ccall_nobox into runtime/runtime.c helpers:
#   - whitespace runs   → scan_flag(0x08)
#   - string content    → scan_to_cp_or(0x22, 0x5C)
#   - number runs       → scan_flag(0x20)  (IS_NUM_CONT)

## i64: count, pos, tc, v, w, c, c2, start, len, tag, t_lbrace, t_rbrace, t_lbracket, t_rbracket, t_comma, t_colon, t_string, t_number, t_true, t_false, t_null, t_ws, len_1_shifted, cp_mask, data_ptr
## u32[]: lc
## i64[]: tokens
-> json_tokenize_fast32_nostore_pure(lc, count, tokens)
  pos = 0
  tc = 0
  data_ptr = ccall_nobox("w_typed_array_data_ptr", lc)  # Shape B: hoist unbox out of hot helpers

  tag = 0xFFFC << 48
  t_lbrace   = tag | (0x1 << 38)
  t_rbrace   = tag | (0x2 << 38)
  t_lbracket = tag | (0x3 << 38)
  t_rbracket = tag | (0x4 << 38)
  t_comma    = tag | (0x5 << 38)
  t_colon    = tag | (0x6 << 38)
  t_string   = tag | (0x7 << 38)
  t_number   = tag | (0x8 << 38)
  t_true     = tag | (0x9 << 38)
  t_false    = tag | (0xA << 38)
  t_null     = tag | (0xB << 38)
  t_ws       = tag | (0xC << 38)
  len_1_shifted = 0x1 << 24
  cp_mask = 0x1FFFFF

  loop
    v = lc[pos]
    if v == 0
      break
    c = (v >> 11) & cp_mask

    case v & 0x3F

    # ── Whitespace ───────────────────────────────────────────────────
    when 0x08
      start = pos
      pos++
      # 3-char scalar prefix amortizes ccall on short runs (single space
      # between values), then NEON for indentation runs / pretty-printed
      # padding.
      if (lc[pos] & 0x08) != 0
        pos++
        if (lc[pos] & 0x08) != 0
          pos++
          if (lc[pos] & 0x08) != 0
            pos++
            pos = ccall_nobox("w_lex32_scan_flag_pure", data_ptr, count, pos, 0x08)
      tc++

    # ── Structural single-char ───────────────────────────────────────
    when 0x04
      tc++
      pos++

    # ── String literal ───────────────────────────────────────────────
    when 0x02
      start = pos
      pos++
      # NEON-scan to next '"' or '\\'. Tail handles closing-vs-escape.
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
      start = pos
      pos++
      # Numbers in JSON are typically 1-15 chars; use a short scalar
      # prefix and fall through to NEON for longer floats / scientific.
      if (lc[pos] & 0x20) != 0
        pos++
        if (lc[pos] & 0x20) != 0
          pos++
          if (lc[pos] & 0x20) != 0
            pos++
            pos = ccall_nobox("w_lex32_scan_flag_pure", data_ptr, count, pos, 0x20)
      tc++

    # ── Keyword (true / false / null) ────────────────────────────────
    when 0x10
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
