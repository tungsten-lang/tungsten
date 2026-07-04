# Ruby Lexer — Lex64 throughput spike
#
# Input:  LexChar array from String#lchs("ruby")
# Output: i64[] token array, packed as W_TAG_CHAR token subtype:
#   W_TAG | (type << 40) | (length << 28) | (offset << 4)
#
# This is a broad-token scanner meant to benchmark the LexChar path against
# Prism's current front door in Spinel. It recognizes Ruby's hot lexical shapes
# without yet attempting full Prism-token parity or context-sensitive regexp
# vs division disambiguation.

## i64: pos
## i64[]: lc
fn ruby64_cp(lc, pos)
  (lc[pos] >> 18) & 0x1FFFFF

## i64: count, pos, tc, v, w, c, c2, start, len, tag, cp_mask, t_ident, t_const, t_int, t_float, t_string, t_symbol, t_op, t_comment, t_nl, t_ivar, t_cvar, t_gvar, t_error, quote, is_float
## i64[]: lc, tokens
-> ruby_tokenize_fast64(lc, count, tokens)
  pos = 0
  tc = 0

  tag = 0xFFFC << 48
  cp_mask = 0x1FFFFF

  t_ident   = tag | (0x01 << 40)
  t_const   = tag | (0x02 << 40)
  t_int     = tag | (0x03 << 40)
  t_float   = tag | (0x04 << 40)
  t_string  = tag | (0x05 << 40)
  t_symbol  = tag | (0x06 << 40)
  t_op      = tag | (0x07 << 40)
  t_comment = tag | (0x08 << 40)
  t_nl      = tag | (0x09 << 40)
  t_ivar    = tag | (0x0A << 40)
  t_cvar    = tag | (0x0B << 40)
  t_gvar    = tag | (0x0C << 40)
  t_error   = tag | (0x0D << 40)

  loop
    if pos >= count
      break

    v = lc[pos]
    c = (v >> 18) & cp_mask
    if c == 0
      break

    case v & 0xD7

    when 0x10
      pos++
      while pos < count && (lc[pos] & 0x10) != 0
        pos++

    when 0x80
      start = pos
      pos++
      if c == 13 && pos < count && ruby64_cp(lc, pos) == 10
        pos++
      tokens[tc] = t_nl | ((pos - start) << 28) | (start << 4)
      tc++

    when 0x40
      start = pos
      pos++
      while pos < count && (lc[pos] & 0x20) != 0
        pos++
      if pos < count
        c2 = ruby64_cp(lc, pos)
        if c2 == :-? || c2 == :-!
          pos++
      len = pos - start
      if c >= 65 && c <= 90
        tokens[tc] = t_const | (len << 28) | (start << 4)
      else
        tokens[tc] = t_ident | (len << 28) | (start << 4)
      tc++

    when 0x01
      start = pos
      is_float = 0

      if c == :-0 && pos + 1 < count
        c2 = ruby64_cp(lc, pos + 1)
        if c2 == :-x || c2 == :-X
          pos += 2
          while pos < count && ((lc[pos] & 0x08) != 0 || ruby64_cp(lc, pos) == :-_)
            pos++
          tokens[tc] = t_int | ((pos - start) << 28) | (start << 4)
          tc++
          next
        if c2 == :-b || c2 == :-B
          pos += 2
          loop
            c2 = ruby64_cp(lc, pos)
            if c2 == :-0 || c2 == :-1 || c2 == :-_
              pos++
            else
              break
          tokens[tc] = t_int | ((pos - start) << 28) | (start << 4)
          tc++
          next
        if c2 == :-o || c2 == :-O
          pos += 2
          loop
            c2 = ruby64_cp(lc, pos)
            if (c2 >= 48 && c2 <= 55) || c2 == :-_
              pos++
            else
              break
          tokens[tc] = t_int | ((pos - start) << 28) | (start << 4)
          tc++
          next

      pos++
      while pos < count
        c2 = ruby64_cp(lc, pos)
        if (lc[pos] & 0x01) != 0 || c2 == :-_
          pos++
        else
          break

      if pos + 1 < count && ruby64_cp(lc, pos) == :-. && (lc[pos + 1] & 0x01) != 0
        is_float = 1
        pos += 2
        while pos < count
          c2 = ruby64_cp(lc, pos)
          if (lc[pos] & 0x01) != 0 || c2 == :-_
            pos++
          else
            break

      if pos < count
        c2 = ruby64_cp(lc, pos)
        if c2 == :-e || c2 == :-E
          is_float = 1
          pos++
          if pos < count
            c2 = ruby64_cp(lc, pos)
            if c2 == :-+ || c2 == :--
              pos++
          while pos < count
            c2 = ruby64_cp(lc, pos)
            if (lc[pos] & 0x01) != 0 || c2 == :-_
              pos++
            else
              break

      len = pos - start
      if is_float != 0
        tokens[tc] = t_float | (len << 28) | (start << 4)
      else
        tokens[tc] = t_int | (len << 28) | (start << 4)
      tc++

    when 0x02
      start = pos
      quote = c
      pos++
      loop
        if pos >= count
          break
        w = lc[pos]
        c2 = (w >> 18) & cp_mask
        if c2 == 0
          break
        if c2 == :-\\
          pos += 2
        elsif c2 == quote
          pos++
          break
        else
          pos++
      tokens[tc] = t_string | ((pos - start) << 28) | (start << 4)
      tc++

    when 0x04
      start = pos

      if c == :-#
        pos++
        while pos < count && (lc[pos] & 0x80) == 0
          pos++
        tokens[tc] = t_comment | ((pos - start) << 28) | (start << 4)
        tc++
        next

      if c == :-@ && pos + 1 < count
        if ruby64_cp(lc, pos + 1) == :-@
          pos += 2
          while pos < count && (lc[pos] & 0x20) != 0
            pos++
          tokens[tc] = t_cvar | ((pos - start) << 28) | (start << 4)
          tc++
          next
        if (lc[pos + 1] & 0x40) != 0
          pos += 1
          while pos < count && (lc[pos] & 0x20) != 0
            pos++
          tokens[tc] = t_ivar | ((pos - start) << 28) | (start << 4)
          tc++
          next

      if c == :-$ && pos + 1 < count
        pos++
        if (lc[pos] & 0x40) != 0
          pos++
          while pos < count && (lc[pos] & 0x20) != 0
            pos++
        elsif (lc[pos] & 0x01) != 0
          while pos < count && (lc[pos] & 0x01) != 0
            pos++
        else
          pos++
        tokens[tc] = t_gvar | ((pos - start) << 28) | (start << 4)
        tc++
        next

      if c == :-: && pos + 1 < count
        c2 = ruby64_cp(lc, pos + 1)
        if c2 != :-: && ((lc[pos + 1] & 0x40) != 0 || (lc[pos + 1] & 0x02) != 0)
          pos++
          if (lc[pos] & 0x02) != 0
            quote = ruby64_cp(lc, pos)
            pos++
            loop
              if pos >= count
                break
              c2 = ruby64_cp(lc, pos)
              if c2 == :-\\
                pos += 2
              elsif c2 == quote
                pos++
                break
              else
                pos++
          else
            while pos < count && (lc[pos] & 0x20) != 0
              pos++
            if pos < count
              c2 = ruby64_cp(lc, pos)
              if c2 == :-? || c2 == :-!
                pos++
          tokens[tc] = t_symbol | ((pos - start) << 28) | (start << 4)
          tc++
          next

      pos++
      while pos < count
        c2 = ruby64_cp(lc, pos)
        if c2 == :-# || c2 == :-@ || c2 == :-$ || c2 == :-\" || c2 == :-\' || c2 == :-`
          break
        if (lc[pos] & 0x04) != 0
          pos++
        else
          break
      tokens[tc] = t_op | ((pos - start) << 28) | (start << 4)
      tc++

    else
      tokens[tc] = t_error | (0x1 << 28) | (pos << 4)
      tc++
      pos++

  tc

