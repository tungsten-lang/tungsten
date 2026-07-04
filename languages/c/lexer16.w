# C Lexer (Lex16 variant) — tokenizes C source using a 16-bit LexChar array.
#
# Input:  ## u16[] LexChar array from String#lchs("c", bits: 16)
# Output: ## i64[] token array (type << 56 | length << 24 | offset)
#
# Same token format and dispatch shape as languages/c/lexer.w; the LexChar
# is packed into 16 bits with the codepoint placeholder in the high byte.
#
# ── Lex16 LexChar bit layout ──────────────────────────────────────────
#
#   15────────8 7────────0
#  ┌───────────┬─────────┐
#  │ codepoint │  flags  │
#  │ (8 bits)  │ (8 bits)│
#  └───────────┴─────────┘
#
# For ASCII (cp <= 0x7F), the high byte stores cp directly.
# For non-ASCII (cp > 0x7F), the high byte stores 0x80 as a placeholder
# and the flag byte still carries the language flags (looked up in the
# lex64 table at packing time). The lexer dispatches on flags only, so
# the actual codepoint isn't needed — it's recovered from the source
# string via (offset, length) when the parser materializes a token.
#
# C-specific flag bits (8 bits — same layout as Lex64):
#
#   bit 7(128): IS_NEWLINE       \n \r
#   bit 6 (64): IS_ID_START      a-z A-Z _
#   bit 5 (32): IS_ID_CONTINUE   a-z A-Z 0-9 _
#   bit 4 (16): IS_WHITESPACE    space tab
#   bit 3  (8): IS_HEX           0-9 a-f A-F
#   bit 2  (4): IS_OPERATOR      + - * / % ^ & | < > = ! ~ ? . : ; , ( ) [ ] { } #
#   bit 1  (2): IS_QUOTE         " '
#   bit 0  (1): IS_DIGIT         0-9
#
# Sentinel: cp=0 + flags=0 → packed 0. Real characters always have a
# non-zero codepoint or at least one set flag.
# ──────────────────────────────────────────────────────────────────────

# Extra token kinds share the normal token layout:
#   bits 38-41: type
#   bits 42-47: token metadata flags
#     bit 42: logical beginning-of-line
#     bit 43: leading whitespace/comment trivia
#     bit 44: malformed recoverable token

## i64: pos
## u16[]: lc
fn c16_cp(lc, pos)
  lc[pos] >> 8

## i64: pos, kind, i
## u16[]: lc
fn c16_ucn_len(lc, pos)
  return 0 if c16_cp(lc, pos) != :-\\

  kind = c16_cp(lc, pos + 1)
  if kind == :-u
    i = 0
    while i < 4
      return 0 if (lc[pos + 2 + i] & 0x8) == 0
      i++
    return 6

  if kind == :-U
    i = 0
    while i < 8
      return 0 if (lc[pos + 2 + i] & 0x8) == 0
      i++
    return 10

  0

## i64: start, len, ok
## u16[]: lc
fn c16_ident_is_include(lc, start, len)
  if len == 7
    ok = 1
    if c16_cp(lc, start) != :-i
      ok = 0
    if c16_cp(lc, start + 1) != :-n
      ok = 0
    if c16_cp(lc, start + 2) != :-c
      ok = 0
    if c16_cp(lc, start + 3) != :-l
      ok = 0
    if c16_cp(lc, start + 4) != :-u
      ok = 0
    if c16_cp(lc, start + 5) != :-d
      ok = 0
    if c16_cp(lc, start + 6) != :-e
      ok = 0
    if ok != 0
      return 1

  if len == 12
    ok = 1
    if c16_cp(lc, start) != :-i
      ok = 0
    if c16_cp(lc, start + 1) != :-n
      ok = 0
    if c16_cp(lc, start + 2) != :-c
      ok = 0
    if c16_cp(lc, start + 3) != :-l
      ok = 0
    if c16_cp(lc, start + 4) != :-u
      ok = 0
    if c16_cp(lc, start + 5) != :-d
      ok = 0
    if c16_cp(lc, start + 6) != :-e
      ok = 0
    if c16_cp(lc, start + 7) != :-_
      ok = 0
    if c16_cp(lc, start + 8) != :-n
      ok = 0
    if c16_cp(lc, start + 9) != :-e
      ok = 0
    if c16_cp(lc, start + 10) != :-x
      ok = 0
    if c16_cp(lc, start + 11) != :-t
      ok = 0
    if ok != 0
      return 1

  0

# ── Fast variant: u16 LexChars, inline GEP, raw machine ops ──────────
#
# Codepoint extraction is `c = v >> 8` (no mask — already in the high byte).
# Sentinel check is `if v == 0` — a single-instruction `cbz` on aarch64.
#
## i64: count, pos, tc, v, w, c, c2, start, is_float, ec, sc, len, tag, t_ident, t_int, t_float, t_string, t_char, t_op, t_preproc, t_comment, t_ws, t_nl, t_header, t_error, t_ppnum, tok_bol, tok_space, tok_error, len_1_shifted, data_ptr, at_bol, leading_space, in_directive, directive_seen, expect_header, tok_flags, ucn_len, err, has_hex, prefix_len, pc, quote
## u16[]: lc
## i64[]: tokens
-> c_tokenize_fast16(lc, count, tokens)
  pos = 0
  tc = 0
  data_ptr = ccall_nobox("w_typed_array_data_ptr", lc)  # Shape B: hoist unbox out of hot helpers

  tag = 0xFFFC << 48
  t_ident   = tag | (0x1 << 38)
  t_int     = tag | (0x3 << 38)
  t_float   = tag | (0x4 << 38)
  t_string  = tag | (0x5 << 38)
  t_char    = tag | (0x6 << 38)
  t_op      = tag | (0x7 << 38)
  t_preproc = tag | (0x8 << 38)
  t_comment = tag | (0x9 << 38)
  t_ws      = tag | (0xA << 38)
  t_nl      = tag | (0xB << 38)
  t_header  = tag | (0xC << 38)
  t_error   = tag | (0xD << 38)
  t_ppnum   = tag | (0xE << 38)
  tok_bol   = 0x1 << 42
  tok_space = 0x2 << 42
  tok_error = 0x4 << 42
  len_1_shifted = 0x1 << 24

  at_bol = 1
  leading_space = 0
  in_directive = 0
  directive_seen = 0
  expect_header = 0

  loop
    v = lc[pos]
    if v == 0                                            # sentinel
      break
    c = v >> 8                                           # extract codepoint (8-bit ASCII or 0x80 placeholder)

    if c == :-\\ && (lc[pos + 1] & 0x80) != 0
      pos += 2
      leading_space = 1
      next

    tok_flags = 0
    if at_bol != 0
      tok_flags = tok_flags | tok_bol
    if leading_space != 0
      tok_flags = tok_flags | tok_space

    ucn_len = c16_ucn_len(lc, pos)
    if ucn_len != 0
      start = pos
      pos += ucn_len
      loop
        while (lc[pos] & 0x20) != 0
          pos++
        ucn_len = c16_ucn_len(lc, pos)
        if ucn_len == 0
          break
        pos += ucn_len
      tokens[tc] = t_ident | tok_flags | ((pos - start) << 24) | start
      tc++
      at_bol = 0
      leading_space = 0
      next

    case v & 0xD7

    # ── 1. IS_OPERATOR ────────────────────────────────────────────────
    when 0x04
      if expect_header != 0 && c == :-<
        start = pos
        pos++
        err = 1
        loop
          w = lc[pos]
          if w == 0 || (w & 0x80) != 0
            break
          if c16_cp(lc, pos) == :->
            pos++
            err = 0
            break
          pos++
        if err != 0
          tokens[tc] = t_error | tok_flags | tok_error | ((pos - start) << 24) | start
        else
          tokens[tc] = t_header | tok_flags | ((pos - start) << 24) | start
        tc++
        expect_header = 0
        at_bol = 0
        leading_space = 0
        next

      if c == :-. && (lc[pos + 1] & 0x1) != 0
        start = pos
        pos += 2
        while (lc[pos] & 0x1) != 0
          pos++
        ec = c16_cp(lc, pos)
        if ec == :-e || ec == :-E
          pos++
          c2 = c16_cp(lc, pos)
          if c2 == :-+ || c2 == :--
            pos++
          if (lc[pos] & 0x1) == 0
            while (lc[pos] & 0x20) != 0
              pos++
            tokens[tc] = t_ppnum | tok_flags | ((pos - start) << 24) | start
            tc++
            at_bol = 0
            leading_space = 0
            next
          while (lc[pos] & 0x1) != 0
            pos++
        loop
          sc = c16_cp(lc, pos)
          if sc in (:-f :-F :-l :-L)
            pos++
          else
            break
        tokens[tc] = t_float | tok_flags | ((pos - start) << 24) | start
        tc++
        at_bol = 0
        leading_space = 0
        next

      if c in (:-( :-) :-; :-, :-{ :-} :-[ :-] :-: :-?)
        tokens[tc] = t_op | tok_flags | len_1_shifted | pos
        tc++
        pos++
        at_bol = 0
        leading_space = 0
        next

      if c == :-# || (c == :-% && c16_cp(lc, pos + 1) == :-:)
        start = pos
        len = 1
        if c == :-%                                     # digraph %:
          len = 2
        pos += len
        tokens[tc] = t_op | tok_flags | (len << 24) | start
        tc++
        if at_bol != 0
          in_directive = 1
          directive_seen = 0
          expect_header = 0
        at_bol = 0
        leading_space = 0
        next

      c2 = c16_cp(lc, pos + 1)
      if (c == :-< && c2 == :-:) || (c == :-: && c2 == :->) || (c == :-< && c2 == :-%) || (c == :-% && c2 == :->)
        tokens[tc] = t_op | tok_flags | (2 << 24) | pos
        tc++
        pos += 2
        at_bol = 0
        leading_space = 0
        next
      if c == :-% && c2 == :-: && c16_cp(lc, pos + 2) == :-% && c16_cp(lc, pos + 3) == :-:
        tokens[tc] = t_op | tok_flags | (4 << 24) | pos
        tc++
        pos += 4
        at_bol = 0
        leading_space = 0
        next

      # Comments
      if c == :-/
        c2 = lc[pos + 1] >> 8
        if c2 == :-/                                    # '//'
          start = pos
          pos += 2
          # NEON sweep — see lexer32.w for rationale.
          loop
            pos = ccall_nobox("w_lex16_scan_until_flag", data_ptr, count, pos, 0x80)
            w = lc[pos]
            if w == 0
              break
            if pos > start + 2 && c16_cp(lc, pos - 1) == :-\\
              pos++
              next
            break
          tokens[tc] = t_comment | tok_flags | ((pos - start) << 24) | start
          tc++
          leading_space = 1
          next
        if c2 == :-*                                    # '/*'
          start = pos
          pos += 2
          # NEON two-cp block comment scan — see lexer32.w for rationale.
          pos = ccall_nobox("w_lex16_scan_to_cp2", data_ptr, count, pos, :-*, :-/)
          w = lc[pos]
          err = 1
          if w != 0
            pos += 2                                     # found '*/', skip past it
            err = 0
          if err != 0
            tokens[tc] = t_error | tok_flags | tok_error | ((pos - start) << 24) | start
          else
            tokens[tc] = t_comment | tok_flags | ((pos - start) << 24) | start
          tc++
          leading_space = 1
          next

      # Compound operators
      start = pos
      pos++
      c2 = lc[pos] >> 8
      case c
      when :--                                                                     # -> -- -=
        if c2 == :->
          pos++
        elsif c2 == :--
          pos++
        elsif c2 == :-=
          pos++
      when :-=                                                                     # ==
        if c2 == :-=
          pos++
      when :-&                                                                     # && &=
        if c2 == :-&
          pos++
        elsif c2 == :-=
          pos++
      when :-!                                                                     # !=
        if c2 == :-=
          pos++
      when :-|                                                                     # || |=
        if c2 == :-|
          pos++
        elsif c2 == :-=
          pos++
      when :-+                                                                     # ++ +=
        if c2 == :-+
          pos++
        elsif c2 == :-=
          pos++
      when :->                                                                     # >= >> >>=
        if c2 == :-=
          pos++
        elsif c2 == :->
          pos++
          if (lc[pos] >> 8) == :-=
            pos++
      when :-<                                                                     # <= << <<=
        if c2 == :-=
          pos++
        elsif c2 == :-<
          pos++
          if (lc[pos] >> 8) == :-=
            pos++
      when :-*                                                                     # *=
        if c2 == :-=
          pos++
      when :-.                                                                     # ...
        if c2 == :-. && c16_cp(lc, pos + 1) == :-.
          pos += 2
      when :-^                                                                     # ^=
        if c2 == :-=
          pos++
      when :-/                                                                     # /=
        if c2 == :-=
          pos++
      when :-%                                                                     # %=
        if c2 == :-=
          pos++
      when :-#                                                                     # ##
        if c2 == :-#
          pos++
      tokens[tc] = t_op | tok_flags | ((pos - start) << 24) | start
      tc++
      at_bol = 0
      leading_space = 0

    # ── 2. IS_ID_START ────────────────────────────────────────────────
    when 0x40
      start = pos
      pos++
      # Hybrid scalar/SIMD — see lexer32.w for the rationale.
      if (lc[pos] & 0x20) != 0
        pos++
        if (lc[pos] & 0x20) != 0
          pos++
          if (lc[pos] & 0x20) != 0
            pos++
            pos = ccall_nobox("w_lex16_scan_flag", data_ptr, count, pos, 0x20)
      loop
        ucn_len = c16_ucn_len(lc, pos)
        if ucn_len == 0
          break
        pos += ucn_len
        while (lc[pos] & 0x20) != 0
          pos++
      len = pos - start
      c2 = c16_cp(lc, pos)
      prefix_len = 0
      if len == 1
        pc = c16_cp(lc, start)
        if pc == :-L || pc == :-u || pc == :-U
          prefix_len = 1
      elsif len == 2 && c16_cp(lc, start) == :-u && c16_cp(lc, start + 1) == :-8
        prefix_len = 2
      if prefix_len != 0 && (c2 == :-" || c2 == :-')
        quote = c2
        pos++
        err = 1
        loop
          w = lc[pos]
          if w == 0 || (w & 0x80) != 0
            break
          c2 = c16_cp(lc, pos)
          if c2 == :-\\
            ucn_len = c16_ucn_len(lc, pos)
            if ucn_len != 0
              pos += ucn_len
            else
              pos += 2
          elsif c2 == quote
            pos++
            err = 0
            break
          else
            pos++
        if err != 0
          tokens[tc] = t_error | tok_flags | tok_error | ((pos - start) << 24) | start
        elsif quote == :-'
          tokens[tc] = t_char | tok_flags | ((pos - start) << 24) | start
        else
          tokens[tc] = t_string | tok_flags | ((pos - start) << 24) | start
        tc++
        at_bol = 0
        leading_space = 0
        next
      tokens[tc] = t_ident | tok_flags | (len << 24) | start
      tc++
      if in_directive != 0 && directive_seen == 0
        if c16_ident_is_include(lc, start, len) != 0
          expect_header = 1
        directive_seen = 1
      at_bol = 0
      leading_space = 0

    # ── 3. IS_WHITESPACE ──────────────────────────────────────────────
    # Stays scalar (see lexer32.w for rationale).
    when 0x10
      start = pos
      pos++
      while (lc[pos] & 0x10) != 0
        pos++
      tokens[tc] = t_ws | tok_flags | ((pos - start) << 24) | start
      tc++
      leading_space = 1

    # ── 4. IS_NEWLINE ─────────────────────────────────────────────────
    when 0x80
      tokens[tc] = t_nl | tok_flags | len_1_shifted | pos
      tc++
      pos++
      at_bol = 1
      leading_space = 0
      in_directive = 0
      directive_seen = 0
      expect_header = 0

    # ── 5. IS_QUOTE ───────────────────────────────────────────────────
    when 0x02
      start = pos
      pos++
      if c == :-"                                       # '"' string literal
        # NEON-scan to next '"' or '\\' — see lexer32.w for rationale.
        err = 1
        loop
          pos = ccall_nobox("w_lex16_scan_to_cp_or", data_ptr, count, pos, :-", :-\\)
          w = lc[pos]
          if w == 0 || (w & 0x80) != 0
            break                                        # sentinel
          c2 = w >> 8
          if c2 == :-"
            pos++
            err = 0
            break                                        # closing '"'
          ucn_len = c16_ucn_len(lc, pos)
          if ucn_len != 0
            pos += ucn_len
          else
            pos += 2                                     # backslash escape
        if expect_header != 0
          if err != 0
            tokens[tc] = t_error | tok_flags | tok_error | ((pos - start) << 24) | start
          else
            tokens[tc] = t_header | tok_flags | ((pos - start) << 24) | start
          expect_header = 0
        elsif err != 0
          tokens[tc] = t_error | tok_flags | tok_error | ((pos - start) << 24) | start
        else
          tokens[tc] = t_string | tok_flags | ((pos - start) << 24) | start
      else                                               # '\'' character literal
        err = 1
        loop
          pos = ccall_nobox("w_lex16_scan_to_cp_or", data_ptr, count, pos, :-', :-\\)
          w = lc[pos]
          if w == 0 || (w & 0x80) != 0
            break
          c2 = w >> 8
          if c2 == :-'
            pos++
            err = 0
            break
          ucn_len = c16_ucn_len(lc, pos)
          if ucn_len != 0
            pos += ucn_len
          else
            pos += 2
        if err != 0
          tokens[tc] = t_error | tok_flags | tok_error | ((pos - start) << 24) | start
        else
          tokens[tc] = t_char | tok_flags | ((pos - start) << 24) | start
      tc++
      at_bol = 0
      leading_space = 0

    # ── 6. IS_DIGIT ───────────────────────────────────────────────────
    when 0x01
      start = pos
      is_float = 0
      if c == :-0                                       # '0' prefix
        c2 = lc[pos + 1] >> 8
        if c2 == :-x || c2 == :-X                      # 'x' / 'X' (hex)
          pos += 2
          has_hex = 0
          while (lc[pos] & 0x8) != 0
            has_hex = 1
            pos++
          if c16_cp(lc, pos) == :-.
            is_float = 1
            pos++
            while (lc[pos] & 0x8) != 0
              has_hex = 1
              pos++
          ec = c16_cp(lc, pos)
          if ec == :-p || ec == :-P
            is_float = 1
            pos++
            c2 = c16_cp(lc, pos)
            if c2 == :-+ || c2 == :--
              pos++
            if (lc[pos] & 0x1) == 0 || has_hex == 0
              while (lc[pos] & 0x20) != 0
                pos++
              tokens[tc] = t_ppnum | tok_flags | ((pos - start) << 24) | start
              tc++
              at_bol = 0
              leading_space = 0
              next
            while (lc[pos] & 0x1) != 0
              pos++
          elsif is_float != 0
            tokens[tc] = t_ppnum | tok_flags | ((pos - start) << 24) | start
            tc++
            at_bol = 0
            leading_space = 0
            next
        elsif c2 == :-b || c2 == :-B                   # 'b' / 'B' (binary)
          pos += 2
          while (lc[pos] >> 8) == :-0 || (lc[pos] >> 8) == :-1
            pos++
        else
          pos++
          while (lc[pos] & 0x1) != 0
            pos++
      else
        pos++
        while (lc[pos] & 0x1) != 0
          pos++

      if (lc[pos] >> 8) == :-.
        pos++
        is_float = 1
        while (lc[pos] & 0x1) != 0
          pos++

      ec = lc[pos] >> 8
      if ec == :-e || ec == :-E
        pos++
        is_float = 1
        c2 = lc[pos] >> 8
        if c2 == :-+ || c2 == :--
          pos++
        if (lc[pos] & 0x1) == 0
          while (lc[pos] & 0x20) != 0
            pos++
          tokens[tc] = t_ppnum | tok_flags | ((pos - start) << 24) | start
          tc++
          at_bol = 0
          leading_space = 0
          next
        while (lc[pos] & 0x1) != 0
          pos++

      loop
        sc = lc[pos] >> 8
        if sc in (:-u :-U :-l :-L :-f :-F)
          pos++
        else
          break

      len = pos - start
      if is_float != 0
        tokens[tc] = t_float | tok_flags | (len << 24) | start
      else
        tokens[tc] = t_int | tok_flags | (len << 24) | start
      tc++
      at_bol = 0
      leading_space = 0

    # ── 7. Unknown character ─────────────────────────────────────────
    else
      tokens[tc] = t_error | tok_flags | tok_error | len_1_shifted | pos
      tc++
      pos++
      at_bol = 0
      leading_space = 0

  tc
