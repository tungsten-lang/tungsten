# C Lexer (WValue baseline) — legacy NaN-boxed tokenizer
#
# This older tokenizer is kept as a readable/scalar benchmark baseline. The
# semantic reference for the C lexer family is now languages/c/lexer.w; the
# 16/32-bit backends are expected to match that token stream.

use ./lexer

# Token types — packed at bit 56 in the WValue layout used by this baseline.
# The fast c_tokenize_fast variants in lexer.w / lexer16.w / lexer32.w use
# a different format (type at bits 38-46, see those files for details).
T_IDENT   = 1 << 56
T_INT     = 3 << 56
T_FLOAT   = 4 << 56
T_STRING  = 5 << 56
T_CHAR    = 6 << 56
T_OP      = 7 << 56
T_PREPROC = 8 << 56
T_COMMENT = 9 << 56
T_WS      = 10 << 56
T_NL      = 11 << 56

# Tokenize a C source file from its LexChar array (baseline — NaN-boxed ops)
# Returns number of tokens written to `tokens` array
fn c_tokenize(lc, count, tokens)
  pos = 0 ## i64
  token_count = 0 ## i64

  while pos < count
    v = lc[pos] ## i64
    c = (v >> 18) & 2097151 ## i64

    # Whitespace (space, tab)
    if (v & 16) != 0
      start = pos ## i64
      pos += 1
      while pos < count && (lc[pos] & 16) != 0
        pos += 1
      tokens[token_count] = T_WS | ((pos - start) << 24) | start
      token_count += 1
      next

    # Newline
    if c == 10
      tokens[token_count] = T_NL | (1 << 24) | pos
      token_count += 1
      pos += 1
      next

    # Identifier (keyword detection skipped for throughput — all identifiers emit T_IDENT)
    if (v & 64) != 0
      start = pos ## i64
      pos += 1
      while pos < count && (lc[pos] & 32) != 0
        pos += 1
      tokens[token_count] = T_IDENT | ((pos - start) << 24) | start
      token_count += 1
      next

    # Number (IS_DIGIT flag = bit 0)
    if (v & 1) != 0
      start = pos ## i64
      is_float = false
      # Check for hex/octal/binary prefix
      if c == 48 && pos + 1 < count
        c2 = cp(lc[pos + 1])
        if c2 == 120 || c2 == 88
          # 0x / 0X hex
          pos += 2
          while pos < count && (lc[pos] & 8) != 0
            pos += 1
        elsif c2 == 98 || c2 == 66
          # 0b / 0B binary
          pos += 2
          while pos < count
            bc = cp(lc[pos])
            if bc == 48 || bc == 49
              pos += 1
            else
              break
        else
          pos += 1
          while pos < count && is_digit(lc[pos])
            pos += 1
      else
        pos += 1
        while pos < count && is_digit(lc[pos])
          pos += 1

      # Check for decimal point (float)
      if pos < count && cp(lc[pos]) == 46
        pos += 1
        is_float = true
        while pos < count && is_digit(lc[pos])
          pos += 1

      # Check for exponent
      if pos < count
        ec = cp(lc[pos])
        if ec == 101 || ec == 69
          pos += 1
          is_float = true
          if pos < count
            sc = cp(lc[pos])
            if sc == 43 || sc == 45
              pos += 1
          while pos < count && is_digit(lc[pos])
            pos += 1

      # Skip suffixes (u, l, ll, f, etc.)
      while pos < count
        sc = cp(lc[pos])
        if sc == 117 || sc == 85 || sc == 108 || sc == 76 || sc == 102 || sc == 70
          pos += 1
        else
          break

      len = pos - start ## i64
      if is_float
        tokens[token_count] = T_FLOAT | (len << 24) | start
      else
        tokens[token_count] = T_INT | (len << 24) | start
      token_count += 1
      next

    # String literal
    if c == 34
      start = pos ## i64
      pos += 1
      while pos < count
        sc = cp(lc[pos])
        if sc == 92
          pos += 2
        elsif sc == 34
          pos += 1
          break
        else
          pos += 1
      tokens[token_count] = T_STRING | ((pos - start) << 24) | start
      token_count += 1
      next

    # Character literal
    if c == 39
      start = pos ## i64
      pos += 1
      while pos < count
        sc = cp(lc[pos])
        if sc == 92
          pos += 2
        elsif sc == 39
          pos += 1
          break
        else
          pos += 1
      tokens[token_count] = T_CHAR | ((pos - start) << 24) | start
      token_count += 1
      next

    # Preprocessor directive
    if c == 35
      start = pos ## i64
      pos += 1
      while pos < count
        pc = cp(lc[pos])
        if pc == 10
          break
        if pc == 92 && pos + 1 < count && cp(lc[pos + 1]) == 10
          pos += 2
          next
        pos += 1
      tokens[token_count] = T_PREPROC | ((pos - start) << 24) | start
      token_count += 1
      next

    # Comments
    if c == 47 && pos + 1 < count
      c2 = cp(lc[pos + 1])
      if c2 == 47
        start = pos ## i64
        pos += 2
        while pos < count && cp(lc[pos]) != 10
          pos += 1
        tokens[token_count] = T_COMMENT | ((pos - start) << 24) | start
        token_count += 1
        next
      if c2 == 42
        start = pos ## i64
        pos += 2
        while pos < count
          if cp(lc[pos]) == 42 && pos + 1 < count && cp(lc[pos + 1]) == 47
            pos += 2
            break
          pos += 1
        tokens[token_count] = T_COMMENT | ((pos - start) << 24) | start
        token_count += 1
        next

    # Operators
    start = pos ## i64
    pos += 1
    if pos < count
      c2 = cp(lc[pos])
      if (c == 43 && c2 == 43) || (c == 43 && c2 == 61)
        pos += 1
      elsif (c == 45 && c2 == 45) || (c == 45 && c2 == 61) || (c == 45 && c2 == 62)
        pos += 1
      elsif (c == 42 && c2 == 61) || (c == 47 && c2 == 61) || (c == 37 && c2 == 61)
        pos += 1
      elsif (c == 38 && c2 == 38) || (c == 38 && c2 == 61)
        pos += 1
      elsif (c == 124 && c2 == 124) || (c == 124 && c2 == 61)
        pos += 1
      elsif (c == 94 && c2 == 61) || (c == 126 && c2 == 61)
        pos += 1
      elsif (c == 60 && c2 == 60) || (c == 60 && c2 == 61)
        pos += 1
        if c == 60 && c2 == 60 && pos < count && cp(lc[pos]) == 61
          pos += 1
      elsif (c == 62 && c2 == 62) || (c == 62 && c2 == 61)
        pos += 1
        if c == 62 && c2 == 62 && pos < count && cp(lc[pos]) == 61
          pos += 1
      elsif c == 61 && c2 == 61
        pos += 1
      elsif c == 33 && c2 == 61
        pos += 1
      elsif c == 46 && c2 == 46 && pos < count && cp(lc[pos]) == 46
        pos += 2
      elsif c == 35 && c2 == 35
        pos += 1

    tokens[token_count] = T_OP | ((pos - start) << 24) | start
    token_count += 1

  token_count

# Token type name for display
-> token_type_name(t)
  case t
  when 0
    "EOF"
  when 1
    "IDENT"
  when 2
    "KEYWORD"
  when 3
    "INT"
  when 4
    "FLOAT"
  when 5
    "STRING"
  when 6
    "CHAR"
  when 7
    "OP"
  when 8
    "PREPROC"
  when 9
    "COMMENT"
  when 10
    "WS"
  when 11
    "NL"
  else
    "?"
