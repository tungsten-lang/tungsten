# C Lexer — tokenizes C source using LexChar arrays
#
# Input:  LexChar array from String#lchs()
# Output: i64[] token array (type << 56 | length << 24 | offset)
#
# Handles common C preprocessing tokens while staying benchmark-friendly.
# This is still not a full C front-end or macro expander. It now covers
# directive-aware '#', header names, pp-number fallback, hex floats, digraphs,
# prefixed literals, UCN spelling in identifiers/literals, and error tokens.
# Remaining gaps include full trigraph compatibility and semantic validation
# of decoded UCN/codepoint legality.
#
# ── C LexChar bit layout ──────────────────────────────────────────────
#
# Each LexChar is a 64-bit NaN-boxed value:
#
#  63        48 47 46  45-39  38──────────────18  17-16   15-11   10-7    6──0
# ┌───────────┬──┬──┬───────┬───────────────────┬──────┬───────┬───────┬───────┐
# │  W_TAG    │  │ST│  (0)  │     codepoint     │utf8  │ cat   │ digit │ flags │
# │  0xFFFC   │  │01│       │     (21 bits)     │len-1 │(5bit) │(4bit) │(7bit) │
# └───────────┴──┴──┴───────┴───────────────────┴──────┴───────┴───────┴───────┘
#
# C-specific flag bits (8 bits: 7 flags + 1 borrowed from digit_value):
#
#   bit 7(128): IS_NEWLINE       \n \r (borrows bit 7 from digit_value field)
#   bit 6 (64): IS_ID_START      a-z A-Z _
#   bit 5 (32): IS_ID_CONTINUE   a-z A-Z 0-9 _
#   bit 4 (16): IS_WHITESPACE    space tab
#   bit 3  (8): IS_HEX           0-9 a-f A-F
#   bit 2  (4): IS_OPERATOR      + - * / % ^ & | < > = ! ~ ? . : ; , ( ) [ ] { } #
#   bit 1  (2): IS_QUOTE         " '
#   bit 0  (1): IS_DIGIT         0-9
#
# Case dispatch: `case v & 0xD7` (bits 7,6,4,2,1,0) maps to unique values:
#   0x80=newline  0x40=ident  0x10=whitespace  0x04=operator  0x02=quote  0x01=digit
#
# Override source: languages/c/overrides.w + c.lex64
# ──────────────────────────────────────────────────────────────────────

# Note: this benchmark lexer emits all identifiers as t_ident — keyword
# distinction is left to the parser. Keyword tables would just bloat the
# scan loop. If a downstream consumer wants keyword tokens it can do its
# own table lookup on (offset, length) against the source string.

# Extra token kinds used by the more semantic C lexer path.
# Type IDs still live in bits 38-41, so existing type/len/offset extraction
# remains valid. Bits 42-47 carry token trivia/error metadata.
#
#   bit 42: token starts at logical beginning-of-line
#   bit 43: token had leading whitespace/comment trivia
#   bit 44: token is malformed but recoverable

## i64: pos
## i64[]: lc
fn c64_cp(lc, pos)
  (lc[pos] >> 18) & 0x1FFFFF

## i64: pos, kind, i
## i64[]: lc
fn c64_ucn_len(lc, pos)
  return 0 if c64_cp(lc, pos) != :-\\

  kind = c64_cp(lc, pos + 1)
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
## i64[]: lc
fn c64_ident_is_include(lc, start, len)
  if len == 7
    ok = 1
    if c64_cp(lc, start) != :-i
      ok = 0
    if c64_cp(lc, start + 1) != :-n
      ok = 0
    if c64_cp(lc, start + 2) != :-c
      ok = 0
    if c64_cp(lc, start + 3) != :-l
      ok = 0
    if c64_cp(lc, start + 4) != :-u
      ok = 0
    if c64_cp(lc, start + 5) != :-d
      ok = 0
    if c64_cp(lc, start + 6) != :-e
      ok = 0
    if ok != 0
      return 1

  if len == 12
    ok = 1
    if c64_cp(lc, start) != :-i
      ok = 0
    if c64_cp(lc, start + 1) != :-n
      ok = 0
    if c64_cp(lc, start + 2) != :-c
      ok = 0
    if c64_cp(lc, start + 3) != :-l
      ok = 0
    if c64_cp(lc, start + 4) != :-u
      ok = 0
    if c64_cp(lc, start + 5) != :-d
      ok = 0
    if c64_cp(lc, start + 6) != :-e
      ok = 0
    if c64_cp(lc, start + 7) != :-_
      ok = 0
    if c64_cp(lc, start + 8) != :-n
      ok = 0
    if c64_cp(lc, start + 9) != :-e
      ok = 0
    if c64_cp(lc, start + 10) != :-x
      ok = 0
    if c64_cp(lc, start + 11) != :-t
      ok = 0
    if ok != 0
      return 1

  0

# ── Fast variant: inferred i64 locals, inline GEP, raw machine ops ───
#
# Branch order optimized by token frequency (42% OP, 23% IDENT, 21% WS, 11% NL).
# Dispatch uses flag-only checks for 91% of tokens — no codepoint extraction.
# Operator lookahead (c2) compares packed LexChar i64 values directly.
#
## i64: count, pos, tc, v, w, c, c2, start, is_float, ec, sc, len, tag, t_ident, t_int, t_float, t_string, t_char, t_op, t_preproc, t_comment, t_ws, t_nl, t_header, t_error, t_ppnum, tok_bol, tok_space, tok_error, len_1_shifted, cp_mask, sentinel, at_bol, leading_space, in_directive, directive_seen, expect_header, tok_flags, ucn_len, err, has_hex, prefix_len, pc, quote
## i64[]: lc, tokens
-> c_tokenize_fast(lc, count, tokens)
  pos = 0
  tc = 0

  # Token bases: W_TAG_CHAR (0xFFFC) subtag 00 (Token)
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
  cp_mask = 0x1FFFFF

  # Sentinel: LexChar subtag with no codepoint, no flags. Loop termination only.
  sentinel = tag | (0x1 << 46)                            # 0xFFFC400000000000

  at_bol = 1
  leading_space = 0
  in_directive = 0
  directive_seen = 0
  expect_header = 0

  loop
    v = lc[pos]
    c = (v >> 18) & cp_mask                            # extract codepoint (sentinel has cp=0)
    if c == 0
      break

    # Translation phase 2: splice escaped physical newlines. This keeps the
    # token stream logical while preserving original offsets for later tokens.
    if c == :-\\ && (lc[pos + 1] & 0x80) != 0
      pos += 2
      leading_space = 1
      next

    tok_flags = 0
    if at_bol != 0
      tok_flags = tok_flags | tok_bol
    if leading_space != 0
      tok_flags = tok_flags | tok_space

    # UCN identifiers may start with a backslash even though '\' is not flagged
    # as ID_START. We conservatively accept valid UCN spellings as identifier
    # chunks and leave codepoint legality to a later semantic pass.
    ucn_len = c64_ucn_len(lc, pos)
    if ucn_len != 0
      start = pos
      pos += ucn_len
      loop
        while (lc[pos] & 0x20) != 0
          pos++
        ucn_len = c64_ucn_len(lc, pos)
        if ucn_len == 0
          break
        pos += ucn_len
      tokens[tc] = t_ident | tok_flags | ((pos - start) << 24) | start
      tc++
      at_bol = 0
      leading_space = 0
      next

    # Dispatch on flag category: mask out IS_ID_CONTINUE and IS_HEX
    case v & 0xD7

    # ── 1. IS_OPERATOR (32%) — operators, preprocessor, comments ──────
    when 0x04                                            # IS_OPERATOR
      # Header names are context-sensitive preprocessing tokens after
      # #include/#include_next.
      if expect_header != 0 && c == :-<
        start = pos
        pos++
        err = 1
        loop
          w = lc[pos]
          if w == sentinel || (w & 0x80) != 0
            break
          if c64_cp(lc, pos) == :->
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

      # Leading-dot floating constants.
      if c == :-. && (lc[pos + 1] & 0x1) != 0
        start = pos
        pos += 2
        while (lc[pos] & 0x1) != 0
          pos++
        ec = c64_cp(lc, pos)
        if ec == :-e || ec == :-E
          pos++
          c2 = c64_cp(lc, pos)
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
          sc = c64_cp(lc, pos)
          if sc in (:-f :-F :-l :-L)
            pos++
          else
            break
        tokens[tc] = t_float | tok_flags | ((pos - start) << 24) | start
        tc++
        at_bol = 0
        leading_space = 0
        next

      # Single-char operators (58% of ops) — checked first, no lookahead needed
      if c in (:-( :-) :-; :-, :-{ :-} :-[ :-] :-: :-?)
        tokens[tc] = t_op | tok_flags | len_1_shifted | pos
        tc++
        pos++
        at_bol = 0
        leading_space = 0
        next

      # Directive marker. Unlike the older benchmark path, this does not
      # swallow the whole directive line — it emits '#' as an ordinary
      # preprocessing punctuator and flips directive context for following
      # tokens only when '#' appears at logical BOL.
      if c == :-# || (c == :-% && c64_cp(lc, pos + 1) == :-:)
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

      # Digraph punctuators.
      c2 = c64_cp(lc, pos + 1)
      if (c == :-< && c2 == :-:) || (c == :-: && c2 == :->) || (c == :-< && c2 == :-%) || (c == :-% && c2 == :->)
        tokens[tc] = t_op | tok_flags | (2 << 24) | pos
        tc++
        pos += 2
        at_bol = 0
        leading_space = 0
        next
      if c == :-% && c2 == :-: && c64_cp(lc, pos + 2) == :-% && c64_cp(lc, pos + 3) == :-:
        tokens[tc] = t_op | tok_flags | (4 << 24) | pos
        tc++
        pos += 4
        at_bol = 0
        leading_space = 0
        next

      if c == :-#
        start = pos
        pos++
        if c64_cp(lc, pos) == :-#
          pos++
        tokens[tc] = t_op | tok_flags | ((pos - start) << 24) | start
        tc++
        at_bol = 0
        leading_space = 0
        next

      # Comments '//' and '/* */'
      if c == :-/
        c2 = (lc[pos + 1] >> 18) & cp_mask
        if c2 == :-/                                    # '//' line comment
          start = pos
          pos += 2
          loop
            w = lc[pos]
            if w == sentinel
              break
            if (w & 0x80) != 0                         # IS_NEWLINE
              if pos > start + 2 && c64_cp(lc, pos - 1) == :-\\
                pos++
                next
              break
            pos++
          tokens[tc] = t_comment | tok_flags | ((pos - start) << 24) | start
          tc++
          leading_space = 1
          next
        if c2 == :-*                                    # '/*' block comment
          start = pos
          pos += 2
          err = 1
          loop
            w = lc[pos]
            if w == sentinel
              break
            if ((w >> 18) & cp_mask) == :-* && ((lc[pos + 1] >> 18) & cp_mask) == :-/
              pos += 2
              err = 0
              break
            pos++
          if err != 0
            tokens[tc] = t_error | tok_flags | tok_error | ((pos - start) << 24) | start
          else
            tokens[tc] = t_comment | tok_flags | ((pos - start) << 24) | start
          tc++
          leading_space = 1
          next

      # Compound operators — grouped by first char, c2 checked inside
      start = pos
      pos++
      c2 = (lc[pos] >> 18) & cp_mask
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
          if ((lc[pos] >> 18) & cp_mask) == :-=
            pos++
      when :-<                                                                     # <= << <<=
        if c2 == :-=
          pos++
        elsif c2 == :-<
          pos++
          if ((lc[pos] >> 18) & cp_mask) == :-=
            pos++
      when :-*                                                                     # *=
        if c2 == :-=
          pos++
      when :-.                                                                     # ...
        if c2 == :-. && c64_cp(lc, pos + 1) == :-.
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

    # ── 2. IS_ID_START (26%) — identifiers (a-z A-Z _ with lchs("c"))
    when 0x40                                            # IS_ID_START
      start = pos
      pos++
      loop
        while (lc[pos] & 0x20) != 0                    # IS_ID_CONTINUE (sentinel terminates)
          pos++
        ucn_len = c64_ucn_len(lc, pos)
        if ucn_len == 0
          break
        pos += ucn_len

      len = pos - start

      # Literal prefixes: L"...", u"...", U"...", u8"...", and char forms.
      c2 = c64_cp(lc, pos)
      prefix_len = 0
      if len == 1
        pc = c64_cp(lc, start)
        if pc == :-L || pc == :-u || pc == :-U
          prefix_len = 1
      elsif len == 2 && c64_cp(lc, start) == :-u && c64_cp(lc, start + 1) == :-8
        prefix_len = 2
      if prefix_len != 0 && (c2 == :-\" || c2 == :-\')
        quote = c2
        pos++
        err = 1
        loop
          w = lc[pos]
          if w == sentinel || (w & 0x80) != 0
            break
          c2 = c64_cp(lc, pos)
          if c2 == :-\\
            ucn_len = c64_ucn_len(lc, pos)
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
        elsif quote == :-\'
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
        if c64_ident_is_include(lc, start, len) != 0
          expect_header = 1
        directive_seen = 1
      at_bol = 0
      leading_space = 0

    # ── 3. IS_WHITESPACE (21%) — space, tab ───────────────────────────
    when 0x10                                            # IS_WHITESPACE
      start = pos
      pos++
      while (lc[pos] & 0x10) != 0                      # sentinel terminates
        pos++
      tokens[tc] = t_ws | tok_flags | ((pos - start) << 24) | start
      tc++
      leading_space = 1

    # ── 4. IS_NEWLINE (13%) — newline ────────────────────────────────
    when 0x80                                            # IS_NEWLINE
      tokens[tc] = t_nl | tok_flags | len_1_shifted | pos
      tc++
      pos++
      at_bol = 1
      leading_space = 0
      in_directive = 0
      directive_seen = 0
      expect_header = 0

    # ── 5. IS_QUOTE (0.2%) — string and character literals ───────────
    when 0x02                                            # IS_QUOTE
      start = pos
      pos++
      if c == :-\"                                       # '"' string literal
        err = 1
        loop
          w = lc[pos]
          if w == sentinel || (w & 0x80) != 0
            break
          c2 = (w >> 18) & cp_mask
          if c2 == :-\\                                  # backslash escape
            ucn_len = c64_ucn_len(lc, pos)
            if ucn_len != 0
              pos += ucn_len
            else
              pos += 2
          elsif c2 == :-\"                               # closing '"'
            pos++
            err = 0
            break
          else
            pos++
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
          w = lc[pos]
          if w == sentinel || (w & 0x80) != 0
            break
          c2 = (w >> 18) & cp_mask
          if c2 == :-\\
            ucn_len = c64_ucn_len(lc, pos)
            if ucn_len != 0
              pos += ucn_len
            else
              pos += 2
          elsif c2 == :-\'
            pos++
            err = 0
            break
          else
            pos++
        if err != 0
          tokens[tc] = t_error | tok_flags | tok_error | ((pos - start) << 24) | start
        else
          tokens[tc] = t_char | tok_flags | ((pos - start) << 24) | start
      tc++
      at_bol = 0
      leading_space = 0

    # ── 6. IS_DIGIT (0.8%) — numbers ─────────────────────────────────
    when 0x01                                            # IS_DIGIT
      start = pos
      is_float = 0
      if c == :-0                                        # '0' prefix
        c2 = (lc[pos + 1] >> 18) & cp_mask
        if c2 == :-x || c2 == :-X                        # 'x' or 'X' (hex)
          pos += 2
          has_hex = 0
          while (lc[pos] & 0x8) != 0                     # IS_HEX (sentinel terminates)
            has_hex = 1
            pos++
          if c64_cp(lc, pos) == :-.
            is_float = 1
            pos++
            while (lc[pos] & 0x8) != 0
              has_hex = 1
              pos++
          ec = c64_cp(lc, pos)
          if ec == :-p || ec == :-P
            is_float = 1
            pos++
            c2 = c64_cp(lc, pos)
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
        elsif c2 == :-b || c2 == :-B                     # 'b' or 'B' (binary)
          pos += 2
          while ((lc[pos] >> 18) & cp_mask) == :-0 || ((lc[pos] >> 18) & cp_mask) == :-1
            pos++
        else
          pos++
          while (lc[pos] & 0x1) != 0                     # IS_DIGIT (sentinel terminates)
            pos++
      else
        pos++
        while (lc[pos] & 0x1) != 0                       # IS_DIGIT (sentinel terminates)
          pos++

      # Decimal point '.'
      if ((lc[pos] >> 18) & cp_mask) == :-.
        pos++
        is_float = 1
        while (lc[pos] & 0x1) != 0
          pos++

      # Exponent 'e' or 'E'
      ec = (lc[pos] >> 18) & cp_mask
      if ec == :-e || ec == :-E
        pos++
        is_float = 1
        c2 = (lc[pos] >> 18) & cp_mask
        if c2 == :-+ || c2 == :--                        # '+' or '-'
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

      # Suffixes: u U l L f F
      loop
        sc = (lc[pos] >> 18) & cp_mask
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
