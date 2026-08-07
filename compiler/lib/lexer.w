# Default packed Tungsten lexer: 64-bit LexChar input, packed token output.
#
# This is the fast token stream used by the compiler lexer rewrite. It avoids
# token hashes and value string copies: tokens are packed as:
#
#   W_TAG_CHAR | (type_id << 38) | (length << 26) | (offset << 2) | line_start_flag
#
# Type ids use bits 38..45 (8 bits → 256 distinct types). The single
# preserved flag at bit 0 marks "first non-whitespace token on its source
# line"; the older sp_before / sp_after flags were dropped because the
# scanner now emits explicit :SP tokens between non-whitespace tokens,
# so the parser detects whitespace by token presence rather than a flag.
#
# The scanner expects source.lchs("tungsten"), whose flag table mirrors
# compiler/lib/lexer.w identifier semantics while adding newline dispatch.

#
# Lex64 is scalar: the NEON scan helpers target the narrower Lex16/Lex32
# layouts where each vector load covers more source characters.

use ../../languages/tungsten/lexers/regex_helpers

## i64[]: lc, tokens, indents
## i64: count
-> tungsten_tokenize_fast64(lc, count, tokens, indents)
  pos = 0
  tc = 0
  at_line_start = 1
  paren_depth = 0
  indent_top = 0
  indents[0] = 0

  tag = 0xFFFC << 48
  cp_mask = 0x1FFFFF
  f_line_start = 0x1

  t_id           = tag | (0x01 << 38)
  t_name         = tag | (0x02 << 38)
  t_int          = tag | (0x03 << 38)
  t_decimal      = tag | (0x04 << 38)
  t_string       = tag | (0x05 << 38)
  t_symbol       = tag | (0x06 << 38)
  t_type_hint    = tag | (0x07 << 38)
  t_newline      = tag | (0x08 << 38)
  t_indent       = tag | (0x09 << 38)
  t_dedent       = tag | (0x0A << 38)
  t_op           = tag | (0x0B << 38)
  t_ivar         = tag | (0x0C << 38)
  t_cvar         = tag | (0x0D << 38)
  t_parg         = tag | (0x0E << 38)
  t_byte_array   = tag | (0x0F << 38)
  t_key          = tag | (0x10 << 38)
  t_color        = tag | (0x11 << 38)
  t_char         = tag | (0x12 << 38)
  t_codepoint    = tag | (0x13 << 38)
  t_word_array   = tag | (0x14 << 38)
  t_symbol_array = tag | (0x15 << 38)
  t_magic        = tag | (0x16 << 38)
  t_eof          = tag | (0x17 << 38)
  t_path         = tag | (0x18 << 38)
  t_sp           = tag | (0x19 << 38)
  # SCREAMING_SNAKE_CASE identifier: starts uppercase, no lowercase
  # ASCII letters. Distinguished from t_name (PascalCase) inline in
  # the chunker by tracking `has_lower` as identifier-extend bytes
  # are consumed.
  t_constant     = tag | (0x1A << 38)
  t_hyper_array  = tag | (0x1B << 38)
  t_decimal_array = tag | (0x1C << 38)
  t_float_array  = tag | (0x1D << 38)

  loop
    if pos >= count
      break

    if at_line_start != 0
      at_line_start = 0
      indent = 0
      while pos < count
        c = (lc[pos] >> 18) & cp_mask
        if c == 32 || c == 9
          indent++
          pos++
        else
          break

      if pos >= count
        break

      c = (lc[pos] >> 18) & cp_mask
      if c == 10 || c == 13
        pos++
        if c == 13 && pos < count && ((lc[pos] >> 18) & cp_mask) == 10
          pos++
        at_line_start = 1
        next

      # Shebang, plus the common "exec " trampoline line used by scripts.
      if c == :-# && pos + 1 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-!
        while pos < count && (lc[pos] & 0x80) == 0
          pos++
        if pos < count
          pos++
        match = 0
        if pos + 4 < count
          c = (lc[pos] >> 18) & cp_mask
          c2 = (lc[pos + 1] >> 18) & cp_mask
          c3 = (lc[pos + 2] >> 18) & cp_mask
          c4 = (lc[pos + 3] >> 18) & cp_mask
          c5 = (lc[pos + 4] >> 18) & cp_mask
          if c == :-e && c2 == :-x && c3 == :-e && c4 == :-c && c5 == 32
            match = 1
        if match != 0
          while pos < count && (lc[pos] & 0x80) == 0
            pos++
          if pos < count
            pos++
        at_line_start = 1
        next

      # Comment-only lines do not emit NEWLINE. Type hints (##) are real tokens.
      if c == :-# && !(pos + 1 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-#)
        while pos < count && (lc[pos] & 0x80) == 0
          pos++
        if pos < count
          pos++
        at_line_start = 1
        next

      if paren_depth == 0
        current_indent = indents[indent_top]
        if indent > current_indent
          indent_top++
          indents[indent_top] = indent
          tokens[tc] = t_indent | (0 << 26) | (pos << 2)
          tc++
        elsif indent < current_indent
          while indent_top > 0 && indents[indent_top] > indent
            indent_top -= 1
            tokens[tc] = t_dedent | (0 << 26) | (pos << 2)
            tc++

    v = lc[pos]
    c = (v >> 18) & cp_mask

    case v & 0xD7
    when 0x10
      # Run of one or more space/tab characters mid-line. Emit a single
      # :SP token covering the run; the parser sees adjacency via the
      # presence/absence of this token between non-whitespace tokens.
      # Line-leading whitespace was already consumed above and produced
      # INDENT/DEDENT instead.
      sp_start = pos
      pos++
      while pos < count && (lc[pos] & 0x10) != 0
        pos++
      tokens[tc] = t_sp | ((pos - sp_start) << 26) | (sp_start << 2)
      tc++

    when 0x80
      if paren_depth == 0
        tokens[tc] = t_newline | (1 << 26) | (pos << 2)
        tc++
      pos++
      if c == 13 && pos < count && ((lc[pos] >> 18) & cp_mask) == 10
        pos++
      at_line_start = 1

    when 0x40
      start = pos

      # Raw WValue literal: u0x followed by exactly 16 hex digits.
      if c == :-u && pos + 18 < count
        if ((lc[pos + 1] >> 18) & cp_mask) == :-0 && ((lc[pos + 2] >> 18) & cp_mask) == :-x
          match = 1
          i = pos + 3
          while i < pos + 19
            if (lc[i] & 0x08) == 0
              match = 0
              break
            i++
          if match != 0
            if pos + 19 < count
              c2 = (lc[pos + 19] >> 18) & cp_mask
              if (lc[pos + 19] & 0x08) != 0 || c2 == :-_
                match = 0
          if match != 0
            pos += 19
            tokens[tc] = t_int | (19 << 26) | (start << 2)
            tc++
            next

      # Magic constants start with "_" but contain uppercase letters, which
      # are intentionally not ID_CONTINUE in the Tungsten flag table.
      if c == :-_ && pos + 6 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-_
        match = 0
        len = 0
        if pos + 7 < count
          c2 = (lc[pos + 2] >> 18) & cp_mask
          c3 = (lc[pos + 3] >> 18) & cp_mask
          if c2 == :-F && c3 == :-I
            if ((lc[pos + 4] >> 18) & cp_mask) == :-L
              if ((lc[pos + 5] >> 18) & cp_mask) == :-E
                if ((lc[pos + 6] >> 18) & cp_mask) == :-_
                  if ((lc[pos + 7] >> 18) & cp_mask) == :-_
                    match = 1
                    len = 8
          elsif c2 == :-L && c3 == :-I
            if ((lc[pos + 4] >> 18) & cp_mask) == :-N
              if ((lc[pos + 5] >> 18) & cp_mask) == :-E
                if ((lc[pos + 6] >> 18) & cp_mask) == :-_
                  if ((lc[pos + 7] >> 18) & cp_mask) == :-_
                    match = 1
                    len = 8
        if match == 0 && pos + 6 < count
          c2 = (lc[pos + 2] >> 18) & cp_mask
          c3 = (lc[pos + 3] >> 18) & cp_mask
          if c2 == :-D && c3 == :-I
            if ((lc[pos + 4] >> 18) & cp_mask) == :-R
              if ((lc[pos + 5] >> 18) & cp_mask) == :-_
                if ((lc[pos + 6] >> 18) & cp_mask) == :-_
                  match = 1
                  len = 7
        if match != 0
          tokens[tc] = t_magic | (len << 26) | (pos << 2)
          tc++
          pos += len
          next

      # U+0041-style codepoint literal.
      if c == :-U && pos + 2 < count
        if ((lc[pos + 1] >> 18) & cp_mask) == :-+
          if (lc[pos + 2] & 0x08) != 0
            pos += 2
            while pos < count && (lc[pos] & 0x08) != 0
              pos++
            tokens[tc] = t_codepoint | ((pos - start) << 26) | (start << 2)
            tc++
            next

      pos++
      has_lower = 0
      while pos < count && (lc[pos] & 0x20) != 0
        cp_here = (lc[pos] >> 18) & cp_mask
        if cp_here >= 97 && cp_here <= 122
          has_lower = 1
        pos++

      # Trailing ? or !. Numeric method arity is left as `/` + integer tokens;
      # the parser consumes it only after `-> name`. Keeping `/N` out of an
      # identifier makes ordinary `moves/10` division unambiguous everywhere
      # else and preserves normal multiplication/power precedence. Block and
      # splat suffixes stay bundled so `/&` and `/*` do not become raw ops.
      if pos < count
        c2 = (lc[pos] >> 18) & cp_mask
        if c2 == :-?
          pos++
        elsif c2 == :-!
          # `empty!` is an identifier, but `x!=y` and `x!~pattern` start
          # operators. Do not swallow their leading bang into the name.
          bang_suffix = 1
          if pos + 1 < count
            c3 = (lc[pos + 1] >> 18) & cp_mask
            if c3 == :-= || c3 == :-~
              bang_suffix = 0
          if bang_suffix != 0
            pos++
      # Trailing prime: `x'` — the same-named property on the first
      # argument (README's prime notation; the parser desugars it to
      # `@1.x`). Consumed into the identifier only when the `'` (cp 39)
      # is NOT opening a single-quoted string: the char after it must
      # not be an ident-continue (0x20), quote (0x02), or digit (0x01)
      # char, so `x'y'` still lexes as `x` + string `'y'`.
      if pos < count && ((lc[pos] >> 18) & cp_mask) == 39
        prime_ok = 1
        if pos + 1 < count && (lc[pos + 1] & 0x23) != 0
          prime_ok = 0
        if prime_ok != 0
          pos++
      if pos < count && ((lc[pos] >> 18) & cp_mask) == :-/
        if pos + 1 < count
          c2 = (lc[pos + 1] >> 18) & cp_mask
          if c2 == :-* || c2 == :-&
            pos += 2
      len = pos - start
      match = 0
      if len == 8
        if ((lc[start] >> 18) & cp_mask) == :-_
          if ((lc[start + 1] >> 18) & cp_mask) == :-_
            if ((lc[start + 6] >> 18) & cp_mask) == :-_
              if ((lc[start + 7] >> 18) & cp_mask) == :-_
                match = 1
      if match != 0
        tokens[tc] = t_magic | (len << 26) | (start << 2)
      elsif c >= 65 && c <= 90
        # Uppercase first char: PascalCase iff later bytes include a
        # lowercase letter; otherwise SCREAMING_SNAKE_CASE constant.
        if has_lower != 0
          tokens[tc] = t_name | (len << 26) | (start << 2)
        else
          tokens[tc] = t_constant | (len << 26) | (start << 2)
      else
        tokens[tc] = t_id | (len << 26) | (start << 2)
      tc++

      # Fast-path unquoted use paths so "use ./x" benchmarks like the real lexer.
      match = 0
      if len == 3
        if ((lc[start] >> 18) & cp_mask) == :-u
          if ((lc[start + 1] >> 18) & cp_mask) == :-s
            if ((lc[start + 2] >> 18) & cp_mask) == :-e
              match = 1
      if match != 0
        use_statement = 0
        prev_pos = start - 1
        while prev_pos >= 0
          c2 = (lc[prev_pos] >> 18) & cp_mask
          if c2 == 32 || c2 == 9
            prev_pos -= 1
          else
            break
        if prev_pos < 0
          use_statement = 1
        else
          c2 = (lc[prev_pos] >> 18) & cp_mask
          if c2 == 10 || c2 == 13 || c2 == :-;
            use_statement = 1
        if use_statement != 0
          while pos < count
            c2 = (lc[pos] >> 18) & cp_mask
            if c2 == 32 || c2 == 9
              pos++
            else
              break
          if pos < count && ((lc[pos] >> 18) & cp_mask) != :-\"
            start = pos
            while pos < count
              c2 = (lc[pos] >> 18) & cp_mask
              if c2 == 32 || c2 == 9 || c2 == 10 || c2 == 13 || c2 == :-; || c2 == :-#
                break
              pos++
            if pos > start
              tokens[tc] = t_path | ((pos - start) << 26) | (start << 2)
              tc++

    when 0x01
      start = pos
      is_float = 0
      match = 0
      if c == :-0 && pos + 1 < count
        c2 = (lc[pos + 1] >> 18) & cp_mask
        case c2
        when :-x
          match = 1
          pos += 2
          while pos < count && ((lc[pos] & 0x08) != 0 || ((lc[pos] >> 18) & cp_mask) == :-_)
            pos++
        when :-X
          match = 1
          pos += 2
          while pos < count && ((lc[pos] & 0x08) != 0 || ((lc[pos] >> 18) & cp_mask) == :-_)
            pos++
        when :-b
          match = 1
          pos += 2
          while pos < count
            c2 = (lc[pos] >> 18) & cp_mask
            if c2 == :-0 || c2 == :-1 || c2 == :-_
              pos++
            else
              break
        when :-B
          match = 1
          pos += 2
          while pos < count
            c2 = (lc[pos] >> 18) & cp_mask
            if c2 == :-0 || c2 == :-1 || c2 == :-_
              pos++
            else
              break
        when :-o
          match = 1
          pos += 2
          while pos < count
            c2 = (lc[pos] >> 18) & cp_mask
            if (c2 >= 48 && c2 <= 55) || c2 == :-_
              pos++
            else
              break
        when :-O
          match = 1
          pos += 2
          while pos < count
            c2 = (lc[pos] >> 18) & cp_mask
            if (c2 >= 48 && c2 <= 55) || c2 == :-_
              pos++
            else
              break
        else
          pos++
          while pos < count && ((lc[pos] & 0x01) != 0 || ((lc[pos] >> 18) & cp_mask) == :-_)
            pos++
      else
        pos++
        while pos < count && ((lc[pos] & 0x01) != 0 || ((lc[pos] >> 18) & cp_mask) == :-_)
          pos++

      if match == 0 && pos == start + 4 && pos + 2 < count && ((lc[pos] >> 18) & cp_mask) == :-- && (lc[pos + 1] & 0x01) != 0 && (lc[pos + 2] & 0x01) != 0
        if pos + 5 < count && ((lc[pos + 3] >> 18) & cp_mask) == :-- && (lc[pos + 4] & 0x01) != 0 && (lc[pos + 5] & 0x01) != 0
          pos += 6
        else
          pos += 3
        tokens[tc] = t_int | ((pos - start) << 26) | (start << 2)
        tc++
        next

      if match == 0 && pos + 1 < count && ((lc[pos] >> 18) & cp_mask) == :-. && (lc[pos + 1] & 0x01) != 0
        len = pos
        c4 = 0
        match = 1
        while c4 < 3
          if len >= count || ((lc[len] >> 18) & cp_mask) != :-.
            match = 0
            break
          len++
          if len >= count || (lc[len] & 0x01) == 0
            match = 0
            break
          while len < count && (lc[len] & 0x01) != 0
            len++
          c4++
        if match != 0
          if len < count && ((lc[len] >> 18) & cp_mask) == :-. && len + 1 < count && (lc[len + 1] & 0x01) != 0
            match = 0
        if match != 0
          if len + 1 < count && ((lc[len] >> 18) & cp_mask) == :-/ && (lc[len + 1] & 0x01) != 0
            len++
            while len < count && (lc[len] & 0x01) != 0
              len++
          pos = len
          tokens[tc] = t_int | ((pos - start) << 26) | (start << 2)
          tc++
          next
        match = 0

      if match == 0 && pos + 1 < count && ((lc[pos] >> 18) & cp_mask) == :-. && (lc[pos + 1] & 0x01) != 0
        pos++
        is_float = 1
        while pos < count && ((lc[pos] & 0x01) != 0 || ((lc[pos] >> 18) & cp_mask) == :-_)
          pos++

      if match == 0 && pos < count
        c2 = (lc[pos] >> 18) & cp_mask
        if c2 == :-e || c2 == :-E
          c3 = 0
          if pos + 1 < count
            c3 = (lc[pos + 1] >> 18) & cp_mask
          match = 0
          if pos + 1 < count && (lc[pos + 1] & 0x01) != 0
            match = 1
          elsif pos + 2 < count && (c3 == :-+ || c3 == :--) && (lc[pos + 2] & 0x01) != 0
            match = 1
          if match != 0
            pos++
            is_float = 1
            if pos < count
              c3 = (lc[pos] >> 18) & cp_mask
              if c3 == :-+ || c3 == :--
                pos++
            while pos < count && (lc[pos] & 0x01) != 0
              pos++

      if match == 0 && pos < count && ((lc[pos] >> 18) & cp_mask) == :-%
        pos++
        tokens[tc] = t_decimal | ((pos - start) << 26) | (start << 2)
        tc++
        next

      if match == 0 && is_float == 0 && pos + 1 < count && ((lc[pos] >> 18) & cp_mask) == :-/ && (lc[pos + 1] & 0x01) != 0
        pos++
        while pos < count && ((lc[pos] & 0x01) != 0 || ((lc[pos] >> 18) & cp_mask) == :-_)
          pos++
        tokens[tc] = t_int | ((pos - start) << 26) | (start << 2)
        tc++
        next

      if match == 0 && pos < count
        c2 = (lc[pos] >> 18) & cp_mask
        if (lc[pos] & 0x40) != 0 || (c2 >= 65 && c2 <= 90)
          pos++
          while pos < count
            c2 = (lc[pos] >> 18) & cp_mask
            if (lc[pos] & 0x40) != 0 || (c2 >= 65 && c2 <= 90) || (lc[pos] & 0x01) != 0 || c2 == :-/
              pos++
            else
              break
          tokens[tc] = t_decimal | ((pos - start) << 26) | (start << 2)
          tc++
          next

      len = pos - start
      if is_float != 0
        tokens[tc] = t_decimal | (len << 26) | (start << 2)
      else
        tokens[tc] = t_int | (len << 26) | (start << 2)
      tc++

    when 0x02
      start = pos
      pos++
      if c == :-\"
        loop
          if pos >= count
            break
          done = 0
          c2 = (lc[pos] >> 18) & cp_mask
          case c2
          when 92
            if pos + 2 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-e && ((lc[pos + 2] >> 18) & cp_mask) == :-[
              pos += 3
            else
              pos += 2
          when 34
            pos++
            done = 1
          when 91
            if pos + 1 < count && ((lc[pos + 1] >> 18) & cp_mask) != :-]
              pos++
              depth = 1
              while pos < count && depth > 0
                c2 = (lc[pos] >> 18) & cp_mask
                case c2
                when 91
                  depth++
                when 93
                  depth -= 1
                pos++
            else
              pos++
          else
            pos++
          if done != 0
            break
        tokens[tc] = t_string | ((pos - start) << 26) | (start << 2)
      else
        loop
          if pos >= count
            break
          done = 0
          c2 = (lc[pos] >> 18) & cp_mask
          case c2
          when 92
            pos += 2
          when 39
            pos++
            done = 1
          else
            pos++
          if done != 0
            break
        tokens[tc] = t_string | ((pos - start) << 26) | (start << 2)
      tc++

    when 0x04
      start = pos

      if c == :-#
        if pos + 1 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-#
          pos += 2
          while pos < count
            c2 = (lc[pos] >> 18) & cp_mask
            if c2 == 32 || c2 == 9
              pos++
            else
              break
          start = pos
          # Local bracket-depth tracks `[...]` inside the hint so `T[4]`
          # stays a single hint while still bailing at the closing
          # bracket of an enclosing indexer.
          th_brk = 0
          while pos < count && (lc[pos] & 0x80) == 0
            cp_here = (lc[pos] >> 18) & cp_mask
            if cp_here == :-\[
              th_brk++
            elsif cp_here == :-]
              if th_brk == 0 && paren_depth > 0
                break
              th_brk--
            # When inside a paren list (`paren_depth > 0`), stop at the
            # structural followers `)` / `,` / `;` / `:` / `?` so inline
            # ascriptions like `(@components ## T[4])` and ternary forms
            # `1 ## T : 0 ## T` don't swallow what comes after. At top
            # level the original whole-line scan is preserved — keeps
            # multi-binding `## i64[]: lc, tokens, indents` working.
            elsif paren_depth > 0
              if cp_here == :-) || cp_here == :-, || cp_here == :-; || cp_here == :-: || cp_here == :-?
                break
            pos++
          tokens[tc] = t_type_hint | ((pos - start) << 26) | (start << 2)
          tc++
          next
        if pos + 1 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-[
          pos += 2
          start = pos
          while pos < count && ((lc[pos] >> 18) & cp_mask) != :-]
            pos++
          if pos < count
            pos++
          tokens[tc] = t_key | ((pos - start) << 26) | (start << 2)
          tc++
          next
        if pos + 1 < count && (lc[pos + 1] & 0x08) != 0
          pos += 1
          while pos < count && (lc[pos] & 0x08) != 0
            pos++
          len = pos - start - 1
          if len == 3 || len == 4 || len == 6 || len == 8
            tokens[tc] = t_color | ((pos - start) << 26) | (start << 2)
            tc++
            next
        pos = start + 1
        while pos < count && (lc[pos] & 0x80) == 0
          pos++
        next

      if c == :-:
        if pos + 2 < count && ((lc[pos + 1] >> 18) & cp_mask) == :--
          c2 = (lc[pos + 2] >> 18) & cp_mask
          if c2 != 32 && c2 != 9 && c2 != 10 && c2 != 13
            pos += 3
            if c2 == :-\\ && pos < count
              pos++
            tokens[tc] = t_char | ((pos - start) << 26) | (start << 2)
            tc++
            next
        if pos + 1 < count
          c2 = (lc[pos + 1] >> 18) & cp_mask
          if c2 == :-+ || c2 == :-- || c2 == :-* || c2 == :-/ || c2 == :-~ || c2 == :-! || c2 == :-% || c2 == :-^ || c2 == :-& || c2 == :-< || c2 == :-> || c2 == :-| || c2 == :-=
            op = c2
            pos += 2
            if pos + 1 < count
              c2 = (lc[pos] >> 18) & cp_mask
              c3 = (lc[pos + 1] >> 18) & cp_mask
              if op == :-= && c2 == :-= && c3 == :-=
                pos += 2
                tokens[tc] = t_symbol | ((pos - start) << 26) | (start << 2)
                tc++
                next
              if op == :-< && c2 == :-= && c3 == :->
                pos += 2
                tokens[tc] = t_symbol | ((pos - start) << 26) | (start << 2)
                tc++
                next
            if pos < count
              c2 = (lc[pos] >> 18) & cp_mask
              match = 0
              case op
              when :-=
                if c2 == :-= || c2 == :-~
                  match = 1
              when :-<
                if c2 == :-= || c2 == :-<
                  match = 1
              when :->
                if c2 == :-= || c2 == :->
                  match = 1
              when :-*
                if c2 == :-*
                  match = 1
              when :-+
                if c2 == :-@
                  match = 1
              when :--
                if c2 == :-@
                  match = 1
              when :-~
                if c2 == :-@
                  match = 1
              when :-!
                if c2 == :-@
                  match = 1
              if match != 0
                pos++
            tokens[tc] = t_symbol | ((pos - start) << 26) | (start << 2)
            tc++
            next
        if pos + 1 < count
          c2 = (lc[pos + 1] >> 18) & cp_mask
        if pos + 1 < count && ((lc[pos + 1] & 0x40) != 0 || (c2 >= 65 && c2 <= 90))
          pos += 1
          while pos < count
            c2 = (lc[pos] >> 18) & cp_mask
            if (lc[pos] & 0x20) != 0 || (c2 >= 65 && c2 <= 90)
              pos++
            else
              break
          if pos < count
            c2 = (lc[pos] >> 18) & cp_mask
            if c2 == :-? || c2 == :-!
              pos++
          if pos < count && ((lc[pos] >> 18) & cp_mask) == :-/
            if pos + 1 < count
              c2 = (lc[pos + 1] >> 18) & cp_mask
              if c2 == :-* || c2 == :-&
                pos += 2
              elsif (lc[pos + 1] & 0x01) != 0
                pos += 1
                while pos < count && (lc[pos] & 0x01) != 0
                  pos++
          tokens[tc] = t_symbol | ((pos - start) << 26) | (start << 2)
          tc++
          next
        if pos + 1 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-[
          pos += 2
          if pos < count && ((lc[pos] >> 18) & cp_mask) == :-]
            pos++
            if pos < count && ((lc[pos] >> 18) & cp_mask) == :-=
              pos++
            tokens[tc] = t_symbol | ((pos - start) << 26) | (start << 2)
            tc++
            next

      if c == :-% && pos + 2 < count
        c2 = (lc[pos + 1] >> 18) & cp_mask
        c3 = (lc[pos + 2] >> 18) & cp_mask
        if (c2 == :-w || c2 == :-i || c2 == :-d) && c3 == :-[
          pos += 3
          while pos < count && ((lc[pos] >> 18) & cp_mask) != :-]
            pos++
          if pos < count
            pos++
          if c2 == :-w
            tokens[tc] = t_word_array | ((pos - start) << 26) | (start << 2)
          elsif c2 == :-i
            tokens[tc] = t_symbol_array | ((pos - start) << 26) | (start << 2)
          else
            tokens[tc] = t_decimal_array | ((pos - start) << 26) | (start << 2)
          tc++
          next
        # `%h<dim>-<type>[…]` hypercomplex literal — `%h` then a digit; scan to
        # the closing `]` exactly like %w/%i (materialize splits dim/type/comps).
        if c2 == :-h && c3 >= 48 && c3 <= 57
          pos += 2
          while pos < count && ((lc[pos] >> 18) & cp_mask) != :-]
            pos++
          if pos < count
            pos++
          tokens[tc] = t_hyper_array | ((pos - start) << 26) | (start << 2)
          tc++
          next
        # `%f<width>[…]` typed float array literal (%f32[…]/%f64[…]) — `%f`
        # then a digit; scan to the closing `]` (materialize splits width/comps).
        if c2 == :-f && c3 >= 48 && c3 <= 57
          pos += 2
          while pos < count && ((lc[pos] >> 18) & cp_mask) != :-]
            pos++
          if pos < count
            pos++
          tokens[tc] = t_float_array | ((pos - start) << 26) | (start << 2)
          tc++
          next

      if c == :-- && pos + 3 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-> && ((lc[pos + 2] >> 18) & cp_mask) == :-/
        c2 = (lc[pos + 3] >> 18) & cp_mask
        if c2 == :-* || c2 == :-&
          pos += 4
          tokens[tc] = t_op | ((pos - start) << 26) | (start << 2)
          tc++
          next
        if (lc[pos + 3] & 0x01) != 0
          pos += 3
          while pos < count && (lc[pos] & 0x01) != 0
            pos++
          tokens[tc] = t_op | ((pos - start) << 26) | (start << 2)
          tc++
          next

      if c == :-~
        scan = pos + 1
        if scan < count
          c2 = (lc[scan] >> 18) & cp_mask
          if (c2 == :-+ || c2 == :--) && scan + 1 < count && (lc[scan + 1] & 0x01) != 0
            scan++
          if scan < count && (lc[scan] & 0x01) != 0
            scan++
            while scan < count && ((lc[scan] & 0x01) != 0 || ((lc[scan] >> 18) & cp_mask) == :-_)
              scan++
            if scan + 1 < count && ((lc[scan] >> 18) & cp_mask) == :-. && (lc[scan + 1] & 0x01) != 0
              scan++
              while scan < count && ((lc[scan] & 0x01) != 0 || ((lc[scan] >> 18) & cp_mask) == :-_)
                scan++
            if scan < count
              c2 = (lc[scan] >> 18) & cp_mask
              if c2 == :-e || c2 == :-E
                exp_pos = scan + 1
                if exp_pos < count
                  c3 = (lc[exp_pos] >> 18) & cp_mask
                  if c3 == :-+ || c3 == :--
                    exp_pos++
                if exp_pos < count && (lc[exp_pos] & 0x01) != 0
                  scan = exp_pos + 1
                  while scan < count && (lc[scan] & 0x01) != 0
                    scan++
            pos = scan
            tokens[tc] = t_decimal | ((pos - start) << 26) | (start << 2)
            tc++
            next

      if c == :-< && pos + 2 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-< && ((lc[pos + 2] >> 18) & cp_mask) == :-~
        pos += 3
        while pos < count
          c2 = (lc[pos] >> 18) & cp_mask
          if c2 == 32 || c2 == 9
            pos++
          else
            break
        delim_start = pos
        while pos < count
          c2 = (lc[pos] >> 18) & cp_mask
          if (lc[pos] & 0x20) != 0 || (c2 >= 65 && c2 <= 90)
            pos++
          else
            break
        delim_len = pos - delim_start
        while pos < count
          c2 = (lc[pos] >> 18) & cp_mask
          if c2 == 10 || c2 == 13
            break
          pos++
        if pos < count
          c2 = (lc[pos] >> 18) & cp_mask
          pos++
          if c2 == 13 && pos < count && ((lc[pos] >> 18) & cp_mask) == 10
            pos++
        found = 0
        while pos < count && found == 0
          line_pos = pos
          while line_pos < count
            c2 = (lc[line_pos] >> 18) & cp_mask
            if c2 == 32 || c2 == 9
              line_pos++
            else
              break
          match = 0
          if delim_len > 0 && line_pos + delim_len <= count
            match = 1
            di = 0
            while di < delim_len
              if ((lc[line_pos + di] >> 18) & cp_mask) != ((lc[delim_start + di] >> 18) & cp_mask)
                match = 0
                break
              di++
          if match != 0
            after = line_pos + delim_len
            if after < count
              c2 = (lc[after] >> 18) & cp_mask
              if c2 != 10 && c2 != 13 && c2 != 32 && c2 != 9
                match = 0
          if match != 0
            pos = after
            while pos < count
              c2 = (lc[pos] >> 18) & cp_mask
              if c2 == 32 || c2 == 9
                pos++
              else
                break
            found = 1
          else
            while pos < count
              c2 = (lc[pos] >> 18) & cp_mask
              if c2 == 10 || c2 == 13
                break
              pos++
            if pos < count
              c2 = (lc[pos] >> 18) & cp_mask
              pos++
              if c2 == 13 && pos < count && ((lc[pos] >> 18) & cp_mask) == 10
                pos++
        tokens[tc] = t_string | ((pos - start) << 26) | (start << 2)
        tc++
        next

      if c == :-/
        regex_context = 1
        prev_pos = start - 1
        while prev_pos >= 0
          c2 = (lc[prev_pos] >> 18) & cp_mask
          if c2 == 32 || c2 == 9
            prev_pos -= 1
          else
            break
        if prev_pos >= 0
          c2 = (lc[prev_pos] >> 18) & cp_mask
          if (lc[prev_pos] & 0x20) != 0 || (lc[prev_pos] & 0x01) != 0 || (c2 >= 65 && c2 <= 90) || c2 == :-) || c2 == :-] || c2 == :-} || c2 == :-\" || c2 == :-\' || c2 == :-? || c2 == :-! || c2 == 0xBB
            keyword_context = 0
            if (lc[prev_pos] & 0x20) != 0
              word_start = prev_pos
              while word_start > 0 && (lc[word_start - 1] & 0x20) != 0
                word_start -= 1
              word_len = prev_pos - word_start + 1
              if word_len == 2
                if ((lc[word_start] >> 18) & cp_mask) == :-i && ((lc[word_start + 1] >> 18) & cp_mask) == :-f
                  keyword_context = 1
              elsif word_len == 4
                c3 = (lc[word_start] >> 18) & cp_mask
                c4 = (lc[word_start + 1] >> 18) & cp_mask
                c5 = (lc[word_start + 2] >> 18) & cp_mask
                c6 = (lc[word_start + 3] >> 18) & cp_mask
                if c3 == :-c && c4 == :-a && c5 == :-s && c6 == :-e
                  keyword_context = 1
                elsif c3 == :-t && c4 == :-h && c5 == :-e && c6 == :-n
                  keyword_context = 1
                elsif c3 == :-w && c4 == :-h && c5 == :-e && c6 == :-n
                  keyword_context = 1
              elsif word_len == 5
                c3 = (lc[word_start] >> 18) & cp_mask
                c4 = (lc[word_start + 1] >> 18) & cp_mask
                c5 = (lc[word_start + 2] >> 18) & cp_mask
                c6 = (lc[word_start + 3] >> 18) & cp_mask
                c7 = (lc[word_start + 4] >> 18) & cp_mask
                if c3 == :-e && c4 == :-l && c5 == :-s && c6 == :-i && c7 == :-f
                  keyword_context = 1
                elsif c3 == :-w && c4 == :-h && c5 == :-i && c6 == :-l && c7 == :-e
                  keyword_context = 1
                elsif c3 == :-u && c4 == :-n && c5 == :-t && c6 == :-i && c7 == :-l
                  keyword_context = 1
              elsif word_len == 6
                c3 = (lc[word_start] >> 18) & cp_mask
                c4 = (lc[word_start + 1] >> 18) & cp_mask
                c5 = (lc[word_start + 2] >> 18) & cp_mask
                c6 = (lc[word_start + 3] >> 18) & cp_mask
                c7 = (lc[word_start + 4] >> 18) & cp_mask
                c8 = (lc[word_start + 5] >> 18) & cp_mask
                if c3 == :-u && c4 == :-n && c5 == :-l && c6 == :-e && c7 == :-s && c8 == :-s
                  keyword_context = 1
                elsif c3 == :-r && c4 == :-e && c5 == :-t && c6 == :-u && c7 == :-r && c8 == :-n
                  keyword_context = 1
            if keyword_context == 0
              regex_context = 0
        if regex_context != 0 && pos + 1 < count
          c2 = (lc[pos + 1] >> 18) & cp_mask
          if c2 != :-/ && c2 != :-=
            scan = pos + 1
            escaped = 0
            in_class = 0
            found = 0
            while scan < count && found == 0
              c2 = (lc[scan] >> 18) & cp_mask
              if c2 == 10 || c2 == 13
                break
              if escaped != 0
                escaped = 0
              else
                case c2
                when :-\\
                  escaped = 1
                when :-[
                  in_class = 1
                when :-]
                  in_class = 0
                when :-/
                  if in_class == 0
                    scan++
                    while scan < count && (lc[scan] & 0x20) != 0
                      scan++
                    pos = scan
                    tokens[tc] = t_string | ((pos - start) << 26) | (start << 2)
                    tc++
                    found = 1
              if found == 0
                scan++
            if found != 0
              next

      pos++
      if c == :-( || c == :-[ || c == :-{
        paren_depth++
      elsif c == :-) || c == :-] || c == :-}
        if paren_depth > 0
          paren_depth -= 1

      if pos < count
        c2 = (lc[pos] >> 18) & cp_mask
        if c == :-. && c2 == :-. && pos + 1 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-.
          pos += 2
        elsif c == :-. && c2 == :-.
          pos++
        elsif ((c == :-* && c2 == :-*) || (c == :-< && c2 == :-<) || (c == :-> && c2 == :->)) && pos + 1 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-=
          # Consuming compound operators whose binary prefix is already a
          # two-character token: **=, <<=, >>=.
          pos += 2
        elsif c == :-| && c2 == :-| && pos + 1 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-=
          pos += 2
        elsif c == :-. && start > 0 && ((lc[start - 1] >> 18) & cp_mask) == 32 && (c2 == :-+ || c2 == :-- || c2 == :-* || c2 == :-/ || c2 == :-| || c2 == :-& || c2 == :-^)
          # Phase 4e dot-prefix elementwise operators: `.+ .- .* ./
          # .| .& .^` consumed as one token when preceded by whitespace.
          # The whitespace requirement disambiguates from method-call
          # syntax (`a.foo` stays a method call). Without space-before,
          # `a.+b` lexes as DOT then PLUS — the parser raises since `a.+`
          # isn't a valid method-call name. Same rationale as the `<<`
          # whitespace rule. (3-char `.<<` `.>>` are scanned by the
          # follow-up branch below since they share the `<<` / `>>`
          # 2-char op machinery.)
          pos++
        elsif c == :-. && start > 0 && ((lc[start - 1] >> 18) & cp_mask) == 32 && (c2 == :-< || c2 == :->) && pos + 1 < count && ((lc[pos + 1] >> 18) & cp_mask) == c2
          # `.<<` / `.>>` — three chars. Same whitespace requirement.
          pos += 2
        elsif c == :-< && c2 == :-= && pos + 1 < count && ((lc[pos + 1] >> 18) & cp_mask) == :->
          # `<=>` spaceship — three chars, scanned as one operator token.
          pos += 2
        elsif c == :-= && c2 == :-= && pos + 1 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-=
          # `===` case-equality — three chars, scanned as one operator token.
          pos += 2
        else
          match = 0
          case c
          when :--
            if c2 == :-> || c2 == :-- || c2 == :-= || c2 == :-@
              match = 1
          when :-<
            # `<>` (swap) pairs here too; generics like `Complex<f64>`
            # always have content between the brackets, so a directly
            # adjacent `<>` is unambiguous.
            if c2 == :-< || c2 == :-- || c2 == :-! || c2 == :-= || c2 == :->
              match = 1
          when :-=
            if c2 == :-> || c2 == :-= || c2 == :-~
              match = 1
          when :-!
            if c2 == :-= || c2 == :-~
              match = 1
          when :->
            if c2 == :-> || c2 == :-=
              match = 1
          when :-&
            if c2 == :-. || c2 == :-& || c2 == :-( || c2 == :-=
              match = 1
          when :-|
            if c2 == :-| || c2 == :-> || c2 == :-=
              match = 1
          when :-^
            if c2 == :-=
              match = 1
          when :-+
            if c2 == :-+ || c2 == :-= || c2 == :-@
              match = 1
          when :-*
            if c2 == :-= || c2 == :-*
              match = 1
          when :-/
            if c2 == :-=
              match = 1
          when :-%
            if c2 == :-=
              match = 1
          if match != 0
            pos++

      tokens[tc] = t_op | ((pos - start) << 26) | (start << 2)
      tc++

    else
      start = pos
      case c
      when :-U
        if pos + 2 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-+ && (lc[pos + 2] & 0x08) != 0
          pos += 2
          while pos < count && (lc[pos] & 0x08) != 0
            pos++
          tokens[tc] = t_codepoint | ((pos - start) << 26) | (start << 2)
        else
          pos++
          has_lower = 0
          while pos < count
            c2 = (lc[pos] >> 18) & cp_mask
            if (lc[pos] & 0x20) != 0 || (c2 >= 65 && c2 <= 90)
              if c2 >= 97 && c2 <= 122
                has_lower = 1
              pos++
            else
              break
          # First char was `U` (uppercase). Same split as the fast path:
          # has any lowercase byte → t_name; else SCREAMING_SNAKE.
          if has_lower != 0
            tokens[tc] = t_name | ((pos - start) << 26) | (start << 2)
          else
            tokens[tc] = t_constant | ((pos - start) << 26) | (start << 2)
        tc++
      when :-@
        pos++
        if pos < count && ((lc[pos] >> 18) & cp_mask) == :-@ && pos + 1 < count && (lc[pos + 1] & 0x40) != 0
          pos++
          while pos < count && (lc[pos] & 0x20) != 0
            pos++
          tokens[tc] = t_cvar | ((pos - start) << 26) | (start << 2)
        elsif pos < count && (lc[pos] & 0x01) != 0
          while pos < count && (lc[pos] & 0x01) != 0
            pos++
          tokens[tc] = t_parg | ((pos - start) << 26) | (start << 2)
        elsif pos < count && (lc[pos] & 0x40) != 0
          while pos < count && (lc[pos] & 0x20) != 0
            pos++
          tokens[tc] = t_ivar | ((pos - start) << 26) | (start << 2)
        else
          tokens[tc] = t_op | (1 << 26) | (start << 2)
        tc++
      when :-$
        if pos + 1 < count && (lc[pos + 1] & 0x01) != 0
          pos++
          while pos < count && (lc[pos] & 0x01) != 0
            pos++
          if pos + 1 < count && ((lc[pos] >> 18) & cp_mask) == :-. && (lc[pos + 1] & 0x01) != 0
            pos++
            while pos < count && (lc[pos] & 0x01) != 0
              pos++
          tokens[tc] = t_decimal | ((pos - start) << 26) | (start << 2)
        elsif pos + 1 < count && (lc[pos + 1] & 0x40) != 0
          pos += 1
          while pos < count && (lc[pos] & 0x20) != 0
            pos++
          tokens[tc] = t_id | ((pos - start) << 26) | (start << 2)
        else
          tokens[tc] = t_op | (1 << 26) | (pos << 2)
          pos++
        tc++
      when 0xAB
        pos++
        while pos < count && ((lc[pos] >> 18) & cp_mask) != 0xBB
          pos++
        if pos < count
          pos++
        tokens[tc] = t_byte_array | ((pos - start) << 26) | (start << 2)
        tc++
      else
        if c >= 65 && c <= 90
          pos++
          has_lower = 0
          while pos < count
            c2 = (lc[pos] >> 18) & cp_mask
            if (lc[pos] & 0x20) != 0 || (c2 >= 65 && c2 <= 90)
              if c2 >= 97 && c2 <= 122
                has_lower = 1
              pos++
            else
              break
          # Slow path: same has_lower split (PascalCase vs constant).
          if has_lower != 0
            tokens[tc] = t_name | ((pos - start) << 26) | (start << 2)
          else
            tokens[tc] = t_constant | ((pos - start) << 26) | (start << 2)
          tc++
        else
          tokens[tc] = t_op | (1 << 26) | (pos << 2)
          tc++
          pos++

  while indent_top > 0
    indent_top -= 1
    tokens[tc] = t_dedent | (0 << 26) | (pos << 2)
    tc++

  tokens[tc] = t_eof | (0 << 26) | (pos << 2)
  token_total = tc + 1

  # Post-pass: set f_line_start (bit 0) on every non-structural token
  # whose nearest preceding non-whitespace is a newline. INDENT/DEDENT/
  # NEWLINE/EOF (type ids 8/9/10/23) don't carry the flag — they're
  # structural markers, not lexical tokens. The earlier sp_before /
  # sp_after flags were dropped: the scanner now emits explicit :SP
  # tokens between non-whitespace tokens, so adjacency is observable
  # by token-presence at the parser layer.
  i = 0
  while i < token_total
    tok = tokens[i]
    off = (tok >> 2) & 0xFFFFFF
    type_id = (tok >> 38) & 0xFF
    if off < count && type_id != 8 && type_id != 9 && type_id != 10 && type_id != 23
      scan = off - 1
      while scan >= 0
        c2 = (lc[scan] >> 18) & cp_mask
        if c2 == 32 || c2 == 9
          scan -= 1
        else
          break
      if scan < 0
        tokens[i] = tok | f_line_start
      else
        c2 = (lc[scan] >> 18) & cp_mask
        if c2 == 10 || c2 == 13
          tokens[i] = tok | f_line_start
    i += 1

  token_total

+ Lexer
  -> new(source, @file = nil)
    @source = strip_bash_shebang(source)
    @chars = @source.chars()
    @lc = @source.lchs()
    @char_count = @chars.size()
    @pos = 0
    @line = 1
    @col = 1
    @token_count = 0
    @last_token_type = nil
    @last_token_value = nil
    @indent_stack = [0]
    @at_line_start = true
    @paren_depth = 0
    # One entry per open `(`: 1 if it opened a lambda param list (`->(`),
    # else 0. `@after_lambda_params` latches true across the closing `)` so
    # the body-starting `<<` lexes as PUTS_OP, not LSHIFT (RPAREN is a value
    # type). Reset on the next meaningful token in push_token.
    @paren_lambda_stack = []
    @after_lambda_params = false
    @regex_capture_scope = false
    # Canonical i64 packed token stream (W_LEXICAL_TOKEN per slot).
    # Parser sites read via tok_type/tok_off/tok_len helpers; no
    # hashes are built.
    @packed_tokens = []
    # Parallel values array — the pre-parsed value field. Nil for
    # tokens with no semantic value (operators, brackets, indentation).
    # String/Number/Array for tokens whose value the parser consumes.
    @values = []
    # In-flight packed value for the SIMD's current token. Set at the
    # top of materialize_packed_token so push_token can pair the emitted
    # token's metadata with its source packed value without per-helper
    # threading.
    @current_packed_tok = 0

  -> push_token(type_sym, value)
    @packed_tokens.push(@current_packed_tok)
    @values.push(value)
    @token_count += 1
    # :SP tokens don't overwrite @last_token_type — downstream classifiers
    # (materialize_op's PLUS-vs-CLASS_DEF, LSHIFT-vs-PUTS_OP discrimination)
    # check whether the previous *meaningful* token was a value, and a space
    # run in between is irrelevant to that decision.
    if type_sym != :SP
      @last_token_type = type_sym
      @last_token_value = value
      # The lambda-params latch only applies to the token that directly
      # follows the closing `)`. Whitespace (:SP) is transparent; any other
      # meaningful token clears it. The `)` branch re-sets it *after* this
      # runs, so the latch survives its own RPAREN push.
      @after_lambda_params = false
    if type_sym == :REGEX
      @regex_capture_scope = true
    if type_sym == :NEWLINE || type_sym == :SEMICOLON
      @regex_capture_scope = false

  -> emit(type, value)
    type_id = type_sym_to_id(type)
    if type_id != 0
      off_bits = (@current_packed_tok >> 2) & 0xFFFFFF
      len_bits = (@current_packed_tok >> 26) & 0xFFF
      flag_bit = @current_packed_tok & 0x1
      tag_bits = (@current_packed_tok >> 48) << 48
      @current_packed_tok = tag_bits | (type_id << 38) | (len_bits << 26) | (off_bits << 2) | flag_bit
    push_token(type, value)
    # Advance @col by the displayed source width of the token. For string-ish
    # tokens the scan routine has already walked the source char-by-char and
    # updated @col, so skip the extra bump here — and crucially, `value` for
    # STRING_INTERP / BYTE_ARRAY_INTERP is a nested array whose `.to_s()`
    # width differs between the Ruby interpreter and the compiled runtime,
    # which would otherwise desync stage-1 and stage-2 .ll hashes.
    if value != nil && type != :STRING && type != :STRING_INTERP && type != :BYTE_ARRAY && type != :BYTE_ARRAY_INTERP
      @col += value.to_s().size()

  -> peek_char
    if @pos < @char_count
      return @chars[@pos]
    nil

  -> peek_char_at(offset)
    idx = @pos + offset
    if idx < @char_count
      return @chars[idx]
    nil

  -> peek_lc_at(offset)
    idx = @pos + offset
    if idx < @char_count
      return @lc[idx]
    0

  -> advance_char
    ch = @chars[@pos]
    @pos += 1
    ch

  -> scan_number
    ch = @chars[@pos]
    # UUID (xxxxxxxx-xxxx-Vxxx-vxxx-xxxxxxxxxxxx) before the number paths, so the
    # first hex field isn't eaten as a scientific-notation number (550e8400…).
    if try_scan_uuid()
      return nil
    # IPv6 with a digit-first first group (2001:db8::1). Requires "::", so a
    # plain number / time / IPv4 falls straight through (try_scan_ipv6 leaves
    # @pos untouched on no-match).
    if try_scan_ipv6()
      return nil
    # Check hex, bin, oct prefixes
    if ch == "0" && @pos + 1 < @chars.size()
      nch = @chars[@pos + 1]
      if nch == "x" || nch == "X"
        scan_hex()
        return nil
      if nch == "b" || nch == "B"
        # Base encoding: 0b32-, 0b58-, 0b64- (lowercase 'b' only)
        if nch == "b" && try_scan_base_encoded()
          return nil
        scan_bin()
        return nil
      if nch == "o" || nch == "O"
        scan_oct()
        return nil
      if nch == "r" && @pos + 2 < @chars.size() && is_digit?(@lc[@pos + 2])
        scan_radix()
        return nil
      if nch == "d" && @pos + 2 < @chars.size() && is_digit?(@lc[@pos + 2])
        scan_decimal_prefix()
        return nil
      if nch == "v" && @pos + 2 < @chars.size()
        scan_vigesimal()
        return nil
    # Decimal
    num = ""
    while @pos < @chars.size() && (is_digit?(@lc[@pos]) || @chars[@pos] == "_")
      num += @chars[@pos]
      @pos += 1
    # Standalone time: HH:MM:SS (1-2 digit hour 0-23, colon, minute digit 0-5)
    if num.size() <= 2 && @pos < @chars.size() && @chars[@pos] == ":"
      hour_val = num.to_i()
      if hour_val <= 23 && @pos + 1 < @chars.size() && is_digit?(@lc[@pos + 1]) && @chars[@pos + 1] <= "5"
        if try_scan_time_after_hour(num)
          return nil

    # IPv4: N.N.N.N where first octet 0-255 (MUST check before float to prevent 192.168 → decimal)
    if num.size() <= 3 && @pos < @chars.size() && @chars[@pos] == "." && @pos + 1 < @chars.size() && is_digit?(@lc[@pos + 1])
      ip_val = num.to_i()
      if ip_val <= 255
        if try_scan_ipv4(num)
          return nil

    # Check for float: '.' followed by a digit (lookahead prevents 1..2 range misparse)
    is_float = false
    if @pos < @chars.size() && @chars[@pos] == "." && @pos + 1 < @chars.size() && is_digit?(@lc[@pos + 1])
      num += "."
      @pos += 1
      is_float = true
      while @pos < @chars.size() && (is_digit?(@lc[@pos]) || @chars[@pos] == "_")
        num += @chars[@pos]
        @pos += 1

    # Scientific notation: 2e46, 1.5e-3
    if @pos < @chars.size() && (@chars[@pos] == "e" || @chars[@pos] == "E")
      e_pos = @pos + 1
      if e_pos < @chars.size() && (@chars[e_pos] == "+" || @chars[e_pos] == "-")
        e_pos += 1
      if e_pos < @chars.size() && is_digit?(@lc[e_pos])
        num += @chars[@pos]
        @pos += 1
        if @pos < @chars.size() && (@chars[@pos] == "+" || @chars[@pos] == "-")
          num += @chars[@pos]
          @pos += 1
        while @pos < @chars.size() && is_digit?(@lc[@pos])
          num += @chars[@pos]
          @pos += 1
        is_float = true

    # Power notation: 2^46 (no space before ^, becomes integer)
    if @pos < @chars.size() && @chars[@pos] == "^" && !is_float
      exp_start = @pos + 1
      if exp_start < @chars.size() && is_digit?(@lc[exp_start])
        @pos = exp_start
        exp_str = ""
        while @pos < @chars.size() && is_digit?(@lc[@pos])
          exp_str += @chars[@pos]
          @pos += 1
        base_val = num.to_i()
        exp_val = exp_str.to_i()
        result = 1
        pi = 0
        while pi < exp_val
          result = result * base_val
          pi += 1
        num = result.to_s()

    # Date: YYYY-MM-DD (4-digit year followed by '-' then digit, not float)
    if !is_float && num.size() == 4 && @pos < @chars.size() && @chars[@pos] == "-" && @pos + 1 < @chars.size() && is_digit?(@lc[@pos + 1])
      if try_scan_date(num)
        return nil

    # Check for currency suffix: ¢, 円, 元, p (p requires no following alpha)
    if @pos < @chars.size()
      sc = @chars[@pos]
      if is_currency_suffix?(sc)
        @pos += 1
        emit(:CURRENCY, [num, nil, sc])
        return nil
      if sc == "p" && (@pos + 1 >= @chars.size() || !is_alpha?(@lc[@pos + 1]))
        @pos += 1
        emit(:CURRENCY, [num, nil, "p"])
        return nil

    # Check for % suffix → percentage (quantity with unit_id 0xFF)
    if @pos < @chars.size() && @chars[@pos] == "%"
      @pos += 1
      emit(:QUANTITY, [num, "%"])
      return nil

    # Check for duration pattern: digits followed by duration unit, then more digits+unit
    # e.g. 2h30m, 30s, 500ms
    if try_scan_duration(num)
      return nil

    # Rational: N/N (no spaces, e.g. 3/4, 1/3) — also accepts ∕ and ⁄
    if !is_float && @pos < @chars.size() && (@chars[@pos] == "/" || @chars[@pos] == "∕" || @chars[@pos] == "⁄") && @pos + 1 < @chars.size() && is_digit?(@lc[@pos + 1])
      if try_scan_rational(num)
        return nil

    # Check for unit suffix → quantity (e.g. 3kg, 5.25m, 100°C)
    if @pos < @chars.size() && unit_alpha_at?(@pos)
      unit = scan_unit_suffix()
      if unit != nil
        emit(:QUANTITY, [num, unit])
        return nil

    # Space-separated unit (`10 ft`, `299_792_458 m/s`): exactly one space,
    # then an identifier naming a KNOWN unit. Anything else backtracks —
    # unknown words after a number stay ordinary tokens, so `10 frogs` and
    # `10 m / 2` (where the trailing `/` makes the suffix unknown) are
    # untouched. `in` is excluded from the table (membership keyword).
    if @pos + 1 < @chars.size() && @chars[@pos] == " " && unit_alpha_at?(@pos + 1)
      spaced_save = @pos
      @pos += 1
      unit = scan_known_unit_phrase()
      if unit != nil
        emit(:QUANTITY, [num, unit])
        return nil
      # `in` is inches UNLESS a parenthesized tuple follows — membership
      # (`3 in (1 2 3)`) always parenthesizes its right-hand side.
      unit = scan_unit_suffix()
      if unit == "in" && !next_nonspace_is_lparen?()
        emit(:QUANTITY, [num, unit])
        return nil
      @pos = spaced_save

    if is_float
      emit(:DECIMAL, num)
      return nil
    emit(:INT, num)

  -> scan_hex
    num = ""
    num += @chars[@pos]
    @pos += 1
    num += @chars[@pos]
    @pos += 1
    while @pos < @chars.size() && (is_hex_char?(@lc[@pos]) || @chars[@pos] == "_")
      num += @chars[@pos]
      @pos += 1
    emit(:INT, num)

  -> scan_bin
    num = ""
    num += @chars[@pos]
    @pos += 1
    num += @chars[@pos]
    @pos += 1
    while @pos < @chars.size() && (@chars[@pos] == "0" || @chars[@pos] == "1" || @chars[@pos] == "_")
      num += @chars[@pos]
      @pos += 1
    emit(:INT, num)

  -> scan_oct
    num = ""
    num += @chars[@pos]
    @pos += 1
    num += @chars[@pos]
    @pos += 1
    while @pos < @chars.size() && (@chars[@pos] >= "0" && @chars[@pos] <= "7" || @chars[@pos] == "_")
      num += @chars[@pos]
      @pos += 1
    emit(:INT, num)

  -> is_radix_digit?(lc, radix)
    cp = lc_cp(lc)
    if radix <= 10
      return cp >= 48 && cp < 48 + radix
    # radix 11-20: digits 0-9 plus a-j
    if cp >= 48 && cp <= 57
      return true
    (cp >= 97 && cp <= 87 + radix) || (cp >= 65 && cp <= 55 + radix)

  -> scan_radix
    # 0rN-digits where N is 2-20
    num = "0r"
    @pos += 2
    # Read radix number
    radix_str = ""
    while @pos < @chars.size() && is_digit?(@lc[@pos])
      radix_str += @chars[@pos]
      num += @chars[@pos]
      @pos += 1
    radix = radix_str.to_i()
    # Expect dash
    if @pos < @chars.size() && @chars[@pos] == "-"
      num += "-"
      @pos += 1
    # Read digits
    while @pos < @chars.size() && (is_radix_digit?(@lc[@pos], radix) || @chars[@pos] == "_")
      num += @chars[@pos]
      @pos += 1
    emit(:INT, num)

  -> scan_decimal_prefix
    # 0dN — explicit decimal prefix
    num = "0d"
    @pos += 2
    while @pos < @chars.size() && (is_digit?(@lc[@pos]) || @chars[@pos] == "_")
      num += @chars[@pos]
      @pos += 1
    emit(:INT, num)

  -> scan_vigesimal
    # 0vN — base 20 (digits 0-9, a-j)
    num = "0v"
    @pos += 2
    while @pos < @chars.size() && (is_radix_digit?(@lc[@pos], 20) || @chars[@pos] == "_")
      num += @chars[@pos]
      @pos += 1
    emit(:INT, num)

  -> scan_wvalue
    num = ""
    num += @chars[@pos]
    @pos += 1
    num += @chars[@pos]
    @pos += 1
    num += @chars[@pos]
    @pos += 1
    count = 0
    while @pos < @chars.size() && is_hex_char?(@lc[@pos])
      if count >= 16
        raise compile_error(:E_LEX_WVALUE_HEX_LENGTH, "WValue literal must use exactly 16 hex digits", @file, @line, @col)
      num += @chars[@pos]
      @pos += 1
      count += 1
    if count != 16
      raise compile_error(:E_LEX_WVALUE_HEX_LENGTH, "WValue literal must use exactly 16 hex digits", @file, @line, @col)
    if @pos < @chars.size() && (@chars[@pos] == "_" || is_hex_char?(@lc[@pos]))
      raise compile_error(:E_LEX_WVALUE_HEX_LENGTH, "WValue literal must use exactly 16 hex digits", @file, @line, @col)
    emit(:WVALUE, num)

  -> is_hex_char?(lc)
    (lc & 8) != 0

  -> is_ipv6_hex?(c)
    # RFC 5952 §4.3: a canonical IPv6 address uses *lowercase* hex digits.
    # Requiring lowercase keeps a "::"-bearing literal from colliding with a
    # class reference, which begins with an uppercase letter (e.g. the
    # `Tungsten:JSON` namespace form). `c` is the raw source char, not the
    # `@lc` class byte, whose uppercase A-F would otherwise fold through as hex.
    (c >= "0" && c <= "9") || (c >= "a" && c <= "f")

  -> is_uuid_variant_char?(lc)
    cp = lc_cp(lc)
    cp == 56 || cp == 57 || cp == 97 || cp == 65 || cp == 98 || cp == 66

  -> try_scan_uuid
    # UUID: xxxxxxxx-xxxx-Vxxx-vxxx-xxxxxxxxxxxx (36 chars)
    # V = version [1-8], v = variant [89aAbB]
    if @pos + 36 > @char_count
      return false
    # After the UUID, next char must not continue an identifier
    if @pos + 36 < @char_count && is_name_char?(@lc[@pos + 36])
      return false
    p = @pos
    # 8 hex digits
    i = 0
    while i < 8
      if !is_hex_char?(@lc[p + i])
        return false
      i += 1
    if @chars[p + 8] != "-"
      return false
    # 4 hex digits
    i = 0
    while i < 4
      if !is_hex_char?(@lc[p + 9 + i])
        return false
      i += 1
    if @chars[p + 13] != "-"
      return false
    # version nibble [1-8]
    v = @chars[p + 14]
    if v < "1" || v > "8"
      return false
    # 3 hex digits
    i = 0
    while i < 3
      if !is_hex_char?(@lc[p + 15 + i])
        return false
      i += 1
    if @chars[p + 18] != "-"
      return false
    # variant nibble [89aAbB]
    if !is_uuid_variant_char?(@lc[p + 19])
      return false
    # 3 hex digits
    i = 0
    while i < 3
      if !is_hex_char?(@lc[p + 20 + i])
        return false
      i += 1
    if @chars[p + 23] != "-"
      return false
    # 12 hex digits
    i = 0
    while i < 12
      if !is_hex_char?(@lc[p + 24 + i])
        return false
      i += 1
    # Valid UUID — consume it
    value = ""
    i = 0
    while i < 36
      value = value + @chars[p + i]
      i += 1
    @pos = p + 36
    emit(:UUID, value)
    true

  -> scan_currency_signed
    # Handles: $5.25, €100, -$5.25, +₹500, C$10, -A$10
    num = ""
    # Optional sign
    if @chars[@pos] == "-" || @chars[@pos] == "+"
      num = @chars[@pos]
      @pos += 1
      @col += 1

    # Capture currency symbol (may be multi-char like C$, A$, R$)
    symbol = ""
    ch = @chars[@pos]
    if (ch == "C" || ch == "A" || ch == "R") && @pos + 1 < @chars.size() && @chars[@pos + 1] == "$"
      symbol = ch + "$"
      @pos += 2
      @col += 2
    else
      symbol = ch
      @pos += 1
      @col += 1

    # Scan digits
    while @pos < @chars.size() && (is_digit?(@lc[@pos]) || @chars[@pos] == "_")
      num += @chars[@pos]
      @pos += 1
    # Check for decimal part
    if @pos < @chars.size() && @chars[@pos] == "." && @pos + 1 < @chars.size() && is_digit?(@lc[@pos + 1])
      num += "."
      @pos += 1
      while @pos < @chars.size() && (is_digit?(@lc[@pos]) || @chars[@pos] == "_")
        num += @chars[@pos]
        @pos += 1

    # Check for suffix: /- (Indian notation)
    suffix = nil
    if @pos + 1 < @chars.size() && @chars[@pos] == "/" && @chars[@pos + 1] == "-"
      suffix = "/-"
      @pos += 2
      @col += 2

    emit(:CURRENCY, [num, symbol, suffix])

  -> is_duration_unit?(s)
    s == "y" || s == "mo" || s == "w" || s == "d" || s == "h" || s == "m" || s == "s" || s == "ms" || s == "ns"

  -> try_scan_duration(first_num)
    # Duration requires either:
    #   - 2+ components: 2h30m, 1y2mo
    #   - 1 component with unambiguous unit: 500ms, 100ns, 5mo
    # Single-component with ambiguous unit (y,w,d,h,m,s) → quantity instead
    saved_pos = @pos
    first_unit = peek_duration_unit()
    if first_unit == nil
      return false

    # We have at least <num><unit> — scan it
    parts = first_num + first_unit
    @pos += first_unit.size()

    # Continue scanning additional <num><unit> pairs
    component_count = 1
    while @pos < @chars.size() && is_digit?(@lc[@pos])
      n = ""
      while @pos < @chars.size() && is_digit?(@lc[@pos])
        n += @chars[@pos]
        @pos += 1
      u = peek_duration_unit()
      if u == nil
        # Not a valid continuation — backtrack the digits
        @pos -= n.size()
        break
      parts += n + u
      @pos += u.size()
      component_count += 1

    # Single-component with ambiguous unit → backtrack, let scan_unit_suffix handle it
    if component_count == 1 && first_unit != "ms" && first_unit != "ns" && first_unit != "mo"
      @pos = saved_pos
      return false

    emit(:DURATION, parts)
    true

  -> peek_duration_unit
    # Look ahead for a duration unit at current position
    if @pos >= @chars.size()
      return nil
    ch = @chars[@pos]
    # Two-char units first: mo, ms, ns
    if @pos + 1 < @chars.size()
      two = ch + @chars[@pos + 1]
      if two == "mo" || two == "ms" || two == "ns"
        # Make sure it's not followed by more alpha (e.g. "mol")
        if @pos + 2 >= @chars.size() || !is_alpha?(@lc[@pos + 2])
          return two
    # Single-char units: y, w, d, h, m, s
    if ch == "y" || ch == "w" || ch == "d" || ch == "h" || ch == "m" || ch == "s"
      # Make sure not followed by alpha (e.g. 'm' not followed by 'o' for 'mo')
      if @pos + 1 >= @chars.size() || !is_alpha?(@lc[@pos + 1])
        return ch
    nil

  -> next_nonspace_is_lparen?
    p = @pos
    while p < @chars.size() && @chars[p] == " "
      p += 1
    p < @chars.size() && @chars[p] == "("

  -> scan_unit_suffix
    # Scan a unit suffix: sequence of alpha chars (e.g. kg, m, Hz).
    # Also allow / and · for compound units (m/s, kg·m), digits for exponents (m2),
    # subscript digits/letters (g₀, mₚₗ), and superscript digits/sign (m², cm⁻¹).
    saved_pos = @pos
    unit = ""
    while @pos < @chars.size() && (unit_alpha_at?(@pos) || @chars[@pos] in ("_" "/" "·" "*" "^") || (@chars[@pos] >= "0" && @chars[@pos] <= "9" && unit.size() > 0) || is_subscript?(@chars[@pos]) || is_superscript_char?(@chars[@pos]))
      unit += @chars[@pos]
      @pos += 1
    if unit.size() > 0
      return unit
    @pos = saved_pos
    nil

  # The stage lexer has a deliberately small ASCII-oriented identifier fast
  # path. Unit symbols need a handful of additional Unicode letters that occur
  # in the shared registry.
  -> unit_alpha_at?(pos)
    return false if pos < 0 || pos >= @chars.size()
    cp = (@lc[pos] >> 18) & 2097151
    is_alpha?(@lc[pos]) || cp >= 128

  # Longest registered phrase after a number and a space. This covers Ruby's
  # multi-word and hyphenated aliases without turning arbitrary prose into a
  # quantity: only a prefix accepted by known_unit_name? is committed.
  -> scan_known_unit_phrase
    saved_pos = @pos
    candidate = ""
    last_unit = nil
    last_pos = saved_pos
    while @pos < @chars.size()
      ch = @chars[@pos]
      allowed = unit_alpha_at?(@pos) || ch in ("_" "/" "·" "*" "^" "-" "'" " " "(" ")") || (ch >= "0" && ch <= "9" && candidate.size() > 0) || is_subscript?(ch) || is_superscript_char?(ch)
      break if !allowed
      candidate += ch
      @pos += 1
      # Only commit a unit match at a word boundary: if the next char is an
      # ASCII letter, `candidate` is a prefix of a longer identifier/keyword
      # (e.g. "u" inside "unless", "m" inside "min") and must not be taken as
      # a unit. The scan continues, so a full-word unit ("min", "meters") is
      # still matched; a bare keyword after a number ("2 unless x") is not.
      next_is_letter = @pos < @chars.size() && is_alpha?(@lc[@pos])
      if known_unit_name?(candidate) && !next_is_letter
        last_unit = "" + candidate
        last_pos = @pos
    if last_unit != nil
      @pos = last_pos
      return last_unit
    @pos = saved_pos
    nil

  -> try_scan_base_encoded
    # @pos at '0', @pos+1 is 'b'. Check for 0bNN- where NN is 32,36,56,58,60,64
    p = @pos
    if p + 5 > @char_count || @chars[p + 1] != "b"
      return false
    d1 = @chars[p + 2]
    d2 = @chars[p + 3]
    if @chars[p + 4] != "-"
      return false
    base = d1 + d2
    if base != "32" && base != "36" && base != "56" && base != "58" && base != "60" && base != "64"
      return false
    prefix = "0b" + base + "-"
    @pos = p + 5
    value = StringBuffer(64)
    if base == "32"
      while @pos < @char_count && is_base32_char?(@lc[@pos])
        value << @chars[@pos]
        @pos += 1
    elsif base == "58"
      while @pos < @char_count && is_base58_char?(@lc[@pos])
        value << @chars[@pos]
        @pos += 1
    elsif base == "64"
      while @pos < @char_count && is_base64_char?(@lc[@pos])
        value << @chars[@pos]
        @pos += 1
    else
      # Base 36, 56, 60 — scan alphanumeric + underscore
      while @pos < @char_count && (is_alpha?(@lc[@pos]) || is_digit?(@lc[@pos]) || @chars[@pos] == "_")
        value << @chars[@pos]
        @pos += 1
    if value.size() == 0
      @pos = p
      return false
    full = prefix + value.to_s()
    if base == "32"
      emit(:BASE32, full)
    elsif base == "58"
      emit(:BASE58, full)
    elsif base == "64"
      emit(:BASE64, full)
    else
      emit(:INT, full)
    true

  -> try_scan_time_after_hour(hour_str)
    # hour_str is 1-2 digits (0-23), @pos is at ':'
    # Requires full HH:MM:SS to distinguish from hash key syntax
    saved_pos = @pos
    @pos += 1  # consume ':'
    # Minutes: 2 digits, first 0-5
    if @pos + 2 > @char_count || !is_digit?(@lc[@pos]) || !is_digit?(@lc[@pos + 1])
      @pos = saved_pos
      return false
    if @chars[@pos] > "5"
      @pos = saved_pos
      return false
    minutes = @chars[@pos] + @chars[@pos + 1]
    @pos += 2
    # Require seconds
    if @pos >= @char_count || @chars[@pos] != ":"
      @pos = saved_pos
      return false
    if @pos + 3 > @char_count || !is_digit?(@lc[@pos + 1]) || !is_digit?(@lc[@pos + 2])
      @pos = saved_pos
      return false
    if @chars[@pos + 1] > "5"
      @pos = saved_pos
      return false
    @pos += 1  # consume ':'
    seconds = @chars[@pos] + @chars[@pos + 1]
    @pos += 2
    time_str = hour_str + ":" + minutes + ":" + seconds
    # Optional fractional seconds
    if @pos < @char_count && @chars[@pos] == "."
      @pos += 1
      frac = ""
      while @pos < @char_count && is_digit?(@lc[@pos])
        frac += @chars[@pos]
        @pos += 1
      if frac.size() > 0
        time_str = time_str + "." + frac
    # Optional timezone: Z, +HH:MM, -HH:MM
    time_str = scan_timezone(time_str)
    emit(:TIME, time_str)
    true

  -> scan_timezone(time_str)
    if @pos < @char_count
      if @chars[@pos] == "Z"
        time_str = time_str + "Z"
        @pos += 1
      elsif @chars[@pos] == "+" || @chars[@pos] == "-"
        tz_sign = @chars[@pos]
        if @pos + 3 <= @char_count && is_digit?(@lc[@pos + 1]) && is_digit?(@lc[@pos + 2])
          tz = tz_sign + @chars[@pos + 1] + @chars[@pos + 2]
          @pos += 3
          if @pos + 1 <= @char_count && @chars[@pos] == ":"
            if @pos + 3 <= @char_count && is_digit?(@lc[@pos + 1]) && is_digit?(@lc[@pos + 2])
              tz = tz + ":" + @chars[@pos + 1] + @chars[@pos + 2]
              @pos += 3
          time_str = time_str + tz
    time_str

  -> try_scan_date(num)
    # num is 4-digit year, @pos is at '-'
    saved_pos = @pos
    @pos += 1  # consume '-'
    # Scan digits after first dash
    d = ""
    while @pos < @char_count && is_digit?(@lc[@pos])
      d += @chars[@pos]
      @pos += 1
    # Ordinal date: YYYY-DDD (3 digits)
    if d.size() == 3
      emit(:DATE, num + "-" + d)
      return true
    # Month must be exactly 2 digits
    if d.size() != 2
      @pos = saved_pos
      return false
    month = d
    # Check for day: YYYY-MM-DD
    if @pos < @char_count && @chars[@pos] == "-" && @pos + 1 < @char_count && is_digit?(@lc[@pos + 1])
      @pos += 1  # consume second '-'
      day = ""
      while @pos < @char_count && is_digit?(@lc[@pos])
        day += @chars[@pos]
        @pos += 1
      if day.size() != 2
        @pos = saved_pos
        return false
      date_str = num + "-" + month + "-" + day
      # Check for DateTime: T followed by time
      if @pos < @char_count && @chars[@pos] == "T"
        time_result = try_scan_time_component()
        if time_result != nil
          emit(:DATETIME, date_str + "T" + time_result)
          return true
      emit(:DATE, date_str)
      return true
    # Just YYYY-MM → month literal
    emit(:MONTH, num + "-" + month)
    true

  -> try_scan_time_component
    # @pos is at 'T', scan time part: HH:MM[:SS[.fff]][±TZ|Z]
    saved = @pos
    @pos += 1  # consume 'T'
    # Hours: 2 digits
    if @pos + 2 > @char_count || !is_digit?(@lc[@pos]) || !is_digit?(@lc[@pos + 1])
      @pos = saved
      return nil
    hours = @chars[@pos] + @chars[@pos + 1]
    @pos += 2
    if @pos >= @char_count || @chars[@pos] != ":"
      @pos = saved
      return nil
    @pos += 1  # consume ':'
    # Minutes: 2 digits
    if @pos + 2 > @char_count || !is_digit?(@lc[@pos]) || !is_digit?(@lc[@pos + 1])
      @pos = saved
      return nil
    minutes = @chars[@pos] + @chars[@pos + 1]
    @pos += 2
    time_str = hours + ":" + minutes
    # Optional seconds
    if @pos < @char_count && @chars[@pos] == ":"
      if @pos + 3 <= @char_count && is_digit?(@lc[@pos + 1]) && is_digit?(@lc[@pos + 2])
        @pos += 1  # consume ':'
        seconds = @chars[@pos] + @chars[@pos + 1]
        @pos += 2
        time_str = time_str + ":" + seconds
        # Optional fractional seconds
        if @pos < @char_count && @chars[@pos] == "."
          @pos += 1
          frac = ""
          while @pos < @char_count && is_digit?(@lc[@pos])
            frac += @chars[@pos]
            @pos += 1
          if frac.size() > 0
            time_str = time_str + "." + frac
    # Optional timezone
    time_str = scan_timezone(time_str)
    time_str

  -> try_scan_ipv4(first_octet)
    # first_octet is string "0"-"255", @pos is at first '.'
    saved_pos = @pos
    octets = first_octet
    # Scan 3 more octets: .N.N.N
    oi = 0
    while oi < 3
      if @pos >= @char_count || @chars[@pos] != "."
        @pos = saved_pos
        return false
      @pos += 1  # consume '.'
      octet = ""
      while @pos < @char_count && is_digit?(@lc[@pos])
        octet += @chars[@pos]
        @pos += 1
      if octet.size() == 0 || octet.to_i() > 255
        @pos = saved_pos
        return false
      octets = octets + "." + octet
      oi += 1
    # Ensure not followed by another dot+digit (would be a longer number pattern)
    if @pos < @char_count && @chars[@pos] == "." && @pos + 1 < @char_count && is_digit?(@lc[@pos + 1])
      @pos = saved_pos
      return false
    # Check for CIDR: /prefix (0-32)
    if @pos < @char_count && @chars[@pos] == "/" && @pos + 1 < @char_count && is_digit?(@lc[@pos + 1])
      cidr_start = @pos
      @pos += 1  # consume '/'
      prefix = ""
      while @pos < @char_count && is_digit?(@lc[@pos])
        prefix += @chars[@pos]
        @pos += 1
      prefix_val = prefix.to_i()
      if prefix_val <= 32
        emit(:CIDR4, octets + "/" + prefix)
        return true
      # Invalid CIDR prefix — backtrack just the /prefix part
      @pos = cidr_start
    # Check for port: :NNNNN (0-65535)
    if @pos < @char_count && @chars[@pos] == ":" && @pos + 1 < @char_count && is_digit?(@lc[@pos + 1])
      port_start = @pos
      @pos += 1  # consume ':'
      port = ""
      while @pos < @char_count && is_digit?(@lc[@pos])
        port += @chars[@pos]
        @pos += 1
      port_val = port.to_i()
      if port_val <= 65535
        emit(:IP4, octets + ":" + port)
        return true
      # Invalid port — backtrack
      @pos = port_start
    emit(:IP4, octets)
    true

  -> all_hex_chunk_at?(off, len)
    # True when the `len` chars at `off` are all hex digits (1-4 = one IPv6
    # group). Used to gate the letter-first IPv6 hook in materialize_id.
    i = 0
    while i < len
      if !is_hex_char?(@lc[off + i])
        return false
      i += 1
    len > 0

  -> ipv6_body_valid?(s)
    # Structural check for the scoped RFC 5952 grammar: the body must contain
    # exactly one "::" (zero-compression), no ":::" run, and every hex group
    # must be <= 4 chars. The runtime parser (w_ipv6_from_string) does the
    # authoritative byte parse; this only guards against mis-lexing normal
    # code (a bare "hexgroup:hexgroup" with no "::" is rejected here).
    n = s.size()
    if n == 0
      return false
    colon_run = 0
    group_len = 0
    double_colons = 0
    i = 0
    while i < n
      c = s[i]
      if c == ":"
        colon_run += 1
        group_len = 0
        if colon_run >= 3
          return false
        if colon_run == 2
          double_colons += 1
      elsif c == "."
        colon_run = 0
        group_len = 0
      else
        colon_run = 0
        group_len += 1
        if group_len > 4
          return false
      i += 1
    double_colons == 1

  -> try_scan_ipv6
    # IPv6 (RFC 5952, scoped to "::"-containing forms): "::1", "2001:db8::1",
    # "fe80::1", bare "::", "::ffff:1.2.3.4", plus an optional "/prefix"
    # (0-128) CIDR. @pos is at the first char of the candidate. Uses a local
    # cursor and only commits @pos on success (mirrors try_scan_uuid), so a
    # failed match leaves lexer state untouched for the normal token path.
    #
    # An IPv6 literal never follows a word character (letter/digit/underscore),
    # just as a symbol like `:foo` never does. So a "::" after an identifier is
    # a scope/namespace reference, not the all-zeros address — bail and let the
    # class reference keep its tokens. ("::" is not a Tungsten operator.)
    if @pos > 0 && is_name_char?(@lc[@pos - 1])
      return false
    p = @pos
    # Maximal address body: RFC 5952 lowercase hex digits, ':' and '.' — the
    # '.' only when it opens a "digit.digit" v4 tail, so "::1.to_s" keeps its
    # method call and "2001:db8::1..5" keeps its range. Lowercase-only hex is
    # what separates "fe80::1" (an address) from "FE80::1" (not one).
    while p < @char_count && (is_ipv6_hex?(@chars[p]) || @chars[p] == ":" || (@chars[p] == "." && p + 1 < @char_count && is_digit?(@lc[p + 1])))
      p += 1
    if p == @pos
      return false
    # Drop a dangling single ':' (an IPv6 key's hash separator, e.g.
    # `{::1: "x"}`), but keep a trailing "::" (its own zero-compression).
    if @chars[p - 1] == ":" && (p - @pos < 2 || @chars[p - 2] != ":")
      p -= 1
    addr = slice_chars(@pos, p - @pos)
    if !ipv6_body_valid?(addr)
      return false
    body_end = p
    # Optional CIDR "/prefix" (0-128).
    if body_end < @char_count && @chars[body_end] == "/" && body_end + 1 < @char_count && is_digit?(@lc[body_end + 1])
      q = body_end + 1
      prefix = ""
      while q < @char_count && is_digit?(@lc[q])
        prefix += @chars[q]
        q += 1
      if prefix.to_i() <= 128
        @pos = q
        emit(:CIDR6, addr + "/" + prefix)
        return true
      # Invalid prefix — fall through and emit the address alone.
    @pos = body_end
    emit(:IP6, addr)
    true

  -> try_scan_rational(num)
    # num is accumulated digits, @pos is at '/' (or ∕ or ⁄)
    slash = @chars[@pos]
    @pos += 1  # consume slash
    den = ""
    while @pos < @char_count && (is_digit?(@lc[@pos]) || @chars[@pos] == "_")
      den += @chars[@pos]
      @pos += 1
    emit(:RATIONAL, num + "/" + den)
    true

  -> scan_string
    str = ""
    parts = []
    has_interp = false
    start_line = @line
    start_col = @col - 1

    while @pos < @chars.size()
      ch = @chars[@pos]

      # End of string
      if ch == "\""
        @pos += 1
        @col += 1
        if has_interp
          if str.size() > 0
            parts.push([:str, str])
          emit(:STRING_INTERP, parts)
        else
          emit(:STRING, str)
        return nil

      # Escape sequences
      if ch == "\\"
        if @pos + 1 < @chars.size()
          esc = @chars[@pos + 1]
          if esc == "n"
            str += "\n"
            @pos += 2
            @col += 2
          elsif esc == "r"
            str += "\r"
            @pos += 2
            @col += 2
          elsif esc == "t"
            str += "\t"
            @pos += 2
            @col += 2
          elsif esc == "\\"
            str += "\\"
            @pos += 2
            @col += 2
          elsif esc == "\""
            str += "\""
            @pos += 2
            @col += 2
          elsif esc == "\["
            str += "\["
            @pos += 2
            @col += 2
          elsif esc == "\]"
            str += "\]"
            @pos += 2
            @col += 2
          elsif esc == "e"
            # \e → ESC (0x1B). Build the byte from its code rather than a
            # "\e" literal: the bootstrap compiler that lexes THIS file may
            # itself not yet handle \e, which would silently bake in a bare
            # "e" and make the fix self-defeating. \e[ is a common ANSI
            # prefix — consume the [ (code 91) too so it can't start
            # interpolation in the produced string.
            if @pos + 2 < @chars.size() && @chars[@pos + 2] == "\["
              str += 27.chr() + 91.chr()
              @pos += 3
              @col += 3
            else
              str += 27.chr()
              @pos += 2
              @col += 2
          elsif esc == "0"
            str += "\0"
            @pos += 2
            @col += 2
          elsif esc == "u" && @pos + 5 < @chars.size()
            hex = @chars[@pos + 2] + @chars[@pos + 3] + @chars[@pos + 4] + @chars[@pos + 5]
            codepoint = hex.to_i(16)
            str += codepoint.chr()
            @pos += 6
            @col += 6
          else
            str += ch
            @pos += 1
            @col += 1
        else
          str += ch
          @pos += 1
          @col += 1
        next

      # String interpolation — [] (empty) is literal, not interpolation.
      # A [ immediately preceded by ESC (0x1B) is also literal (language
      # ruling 2026-07-22): ESC-[ is the ANSI CSI prefix, so escape-bracket
      # sequences never start interpolation, while "\e[48;2;[r]m" still
      # interpolates [r] (its [ follows ';'). The \e-[ fast path in the
      # escape handler above already consumes the adjacent pair; this guard
      # catches ESC arriving any other way (backslash-u001b escape, concatenated
      # escapes). The 27.chr() comparison sits last so it only runs when ch
      # is [ (and it avoids a "\e" literal, which the bootstrap compiler may
      # not lex — see the escape-handler comment above).
      if ch == "\[" && @pos + 1 < @chars.size() && @chars[@pos + 1] != "]" && !(str.size() > 0 && str[str.size() - 1] == 27.chr())
        has_interp = true
        if str.size() > 0
          parts.push([:str, str])
        str = ""
        @pos += 1
        @col += 1

        # Scan until matching ]
        expr = ""
        depth = 1
        while @pos < @chars.size() && depth > 0
          c = @chars[@pos]
          if c == "\["
            depth += 1
            expr += c
          elsif c == "]"
            depth -= 1
            if depth > 0
              expr += c
          else
            expr += c
          @pos += 1
          @col += 1
        parts.push([:expr, expr.strip()])
        next

      # Newline in string
      if ch == "\n"
        str += "\n"
        @pos += 1
        @line += 1
        @col = 1
        next

      # Regular character
      str += ch
      @pos += 1
      @col += 1

    raise compile_error(:E_LEX_UNTERMINATED_STRING, "Unterminated string", @file, start_line, start_col)

  -> scan_byte_array
    bytes = []
    parts = []
    has_interp = false

    while @pos < @chars.size()
      ch = @chars[@pos]
      cp = @lc[@pos]

      # Skip whitespace, commas, and newlines
      if ch == " " || ch == "\t" || ch == ","
        @pos += 1
        @col += 1
        next
      if ch == "\n"
        @pos += 1
        @line += 1
        @col = 1
        next

      # End of byte array
      if ch == "»"
        @pos += 1
        @col += 1
        if has_interp
          if bytes.size() > 0
            parts.push([:bytes, bytes])
          emit(:BYTE_ARRAY_INTERP, parts)
        else
          emit(:BYTE_ARRAY, bytes)
        return nil

      # Interpolation — [] (empty) is literal; interpolation cannot span lines
      if ch == "\[" && @pos + 1 < @chars.size() && @chars[@pos + 1] != "]"
        has_interp = true
        if bytes.size() > 0
          parts.push([:bytes, bytes])
        bytes = []
        @pos += 1
        @col += 1
        expr = ""
        depth = 1
        while @pos < @chars.size() && depth > 0
          c = @chars[@pos]
          if c == "\["
            depth += 1
            expr += c
          elsif c == "]"
            depth -= 1
            if depth > 0
              expr += c
          else
            expr += c
          @pos += 1
          @col += 1
        parts.push([:expr, expr.strip()])
        next

      # Hex byte (1-2 hex digits)
      if is_hex_char?(cp)
        hex = ch
        @pos += 1
        @col += 1
        if @pos < @chars.size() && is_hex_char?(@lc[@pos])
          hex += @chars[@pos]
          @pos += 1
          @col += 1
        bytes.push(hex.to_i(16))
        next

      raise compile_error(:E_LEX_BYTEARRAY_BAD_CHAR, "Unexpected character in byte array: [ch]", @file, @line, @col)

    raise compile_error(:E_LEX_UNTERMINATED_BYTEARRAY, "Unterminated byte array", @file, @line, @col)

  -> try_scan_color
    # @pos is at '#', next char is a hex digit
    # Count consecutive hex digits after '#'
    p = @pos + 1
    count = 0
    while p < @char_count && is_hex_char?(@lc[p])
      count += 1
      p += 1
    # Must be exactly 3, 4, 6, or 8 hex digits, not followed by more hex/ident chars
    if count != 3 && count != 4 && count != 6 && count != 8
      return false
    if p < @char_count && is_name_char?(@lc[p])
      return false
    # Parse the hex digits
    start_col = @col
    @pos += 1  # consume '#'
    hex = StringBuffer(8)
    i = 0
    while i < count
      hex << @chars[@pos]
      @pos += 1
      i += 1
    raw = hex.to_s()
    # Expand shorthand: #RGB → RRGGBB, #RGBA → RRGGBBAA
    if count == 3
      raw = raw[0] + raw[0] + raw[1] + raw[1] + raw[2] + raw[2]
    elsif count == 4
      raw = raw[0] + raw[0] + raw[1] + raw[1] + raw[2] + raw[2] + raw[3] + raw[3]
    # Parse RGBA values
    r = (raw[0] + raw[1]).to_i(16)
    g = (raw[2] + raw[3]).to_i(16)
    b = (raw[4] + raw[5]).to_i(16)
    a = 255
    if raw.size() == 8
      a = (raw[6] + raw[7]).to_i(16)
    push_token(:COLOR, [r, g, b, a])
    @col = start_col + 1 + count
    true

  -> scan_key_literal
    # Scan content until closing ] — e.g. #[Enter], #[Ctrl+C]
    content = StringBuffer(16)
    while @pos < @char_count
      ch = @chars[@pos]
      if ch == "]"
        @pos += 1
        @col += 1
        result = content.to_s().strip()
        if result.size() == 0
          raise compile_error(:E_LEX_EMPTY_KEY, "Empty key literal", @file, @line, @col)
        emit(:KEY, result)
        return nil
      if ch == "\n"
        raise compile_error(:E_LEX_UNTERMINATED_KEY, "Unterminated key literal", @file, @line, @col)
      content << ch
      @pos += 1
      @col += 1
    raise compile_error(:E_LEX_UNTERMINATED_KEY, "Unterminated key literal", @file, @line, @col)

  -> scan_codepoint_literal
    # U+XXXX — 4-6 hex digits, validates Unicode range and surrogates.
    # Emits :CODEPOINT (distinct from :CHAR which is the `:-X` form).
    # CHAR is a raw ASCII integer, CODEPOINT is a boxed Unicode codepoint.
    start_col = @col
    @pos += 2  # consume 'U+'
    @col += 2
    hex = StringBuffer(6)
    while @pos < @char_count && is_hex_char?(@lc[@pos])
      hex << @chars[@pos]
      @pos += 1
      @col += 1
    hex_str = hex.to_s()
    if hex_str.size() < 4 || hex_str.size() > 6
      raise compile_error(:E_LEX_CHAR_HEX_LENGTH, "Codepoint literal U+ requires 4-6 hex digits", @file, @line, start_col)
    codepoint = hex_str.to_i(16)
    if codepoint > 1114111
      raise compile_error(:E_LEX_CHAR_UNICODE_RANGE, "Codepoint literal U+[hex_str] exceeds Unicode range", @file, @line, start_col)
    if codepoint >= 55296 && codepoint <= 57343
      raise compile_error(:E_LEX_CHAR_SURROGATE, "Codepoint literal U+[hex_str] is a Unicode surrogate", @file, @line, start_col)
    push_token(:CODEPOINT, codepoint)

  -> scan_word_array
    # Already consumed "%w[" — scan space-separated words until ]
    words = []
    word = StringBuffer(16)
    while @pos < @char_count
      ch = @chars[@pos]
      if ch == "]"
        @pos += 1
        @col += 1
        if word.size() > 0
          words.push(word.to_s())
        emit(:WORD_ARRAY, words)
        return nil
      if ch == " " || ch == "\t"
        if word.size() > 0
          words.push(word.to_s())
          word = StringBuffer(16)
        @pos += 1
        @col += 1
        next
      if ch == "\n"
        if word.size() > 0
          words.push(word.to_s())
          word = StringBuffer(16)
        @pos += 1
        @line += 1
        @col = 1
        next
      word << ch
      @pos += 1
      @col += 1
    raise compile_error(:E_LEX_UNTERMINATED_PW, "Unterminated %w[] literal", @file, @line, @col)

  -> scan_symbol_array
    # Already consumed "%i[" — scan space-separated symbols until ]
    symbols = []
    word = StringBuffer(16)
    while @pos < @char_count
      ch = @chars[@pos]
      if ch == "]"
        @pos += 1
        @col += 1
        if word.size() > 0
          symbols.push(word.to_s())
        emit(:SYMBOL_ARRAY, symbols)
        return nil
      if ch == " " || ch == "\t"
        if word.size() > 0
          symbols.push(word.to_s())
          word = StringBuffer(16)
        @pos += 1
        @col += 1
        next
      if ch == "\n"
        if word.size() > 0
          symbols.push(word.to_s())
          word = StringBuffer(16)
        @pos += 1
        @line += 1
        @col = 1
        next
      word << ch
      @pos += 1
      @col += 1
    raise compile_error(:E_LEX_UNTERMINATED_PI, "Unterminated %i[] literal", @file, @line, @col)

  -> scan_decimal_array
    # Already consumed "%d[" — scan space-separated decimal spellings until ].
    # Values stay strings here; the parser desugars to Decimal literal nodes.
    decimals = []
    word = StringBuffer(16)
    while @pos < @char_count
      ch = @chars[@pos]
      if ch == "]"
        @pos += 1
        @col += 1
        if word.size() > 0
          decimals.push(word.to_s())
        emit(:DECIMAL_ARRAY, decimals)
        return nil
      if ch == " " || ch == "\t"
        if word.size() > 0
          decimals.push(word.to_s())
          word = StringBuffer(16)
        @pos += 1
        @col += 1
        next
      if ch == "\n"
        if word.size() > 0
          decimals.push(word.to_s())
          word = StringBuffer(16)
        @pos += 1
        @line += 1
        @col = 1
        next
      word << ch
      @pos += 1
      @col += 1
    raise compile_error(:E_LEX_UNTERMINATED_PD, "Unterminated %d[] literal", @file, @line, @col)

  -> scan_float_array
    # Already consumed "%f"; @pos is at the width digits. Read <width> '['
    # then space/tab/newline-separated float spellings until ']'. The parser
    # validates the width (32/64) and desugars to [~…].to_f32/to_f64.
    width = StringBuffer(4)
    while @pos < @char_count && @chars[@pos] != "\["
      width << @chars[@pos]
      @pos += 1
      @col += 1
    if @pos < @char_count
      @pos += 1
      @col += 1
    comps = []
    word = StringBuffer(16)
    while @pos < @char_count
      ch = @chars[@pos]
      if ch == "]"
        @pos += 1
        @col += 1
        if word.size() > 0
          comps.push(word.to_s())
        emit(:FLOAT_ARRAY, [width.to_s(), comps])
        return nil
      if ch == " " || ch == "\t"
        if word.size() > 0
          comps.push(word.to_s())
          word = StringBuffer(16)
        @pos += 1
        @col += 1
        next
      if ch == "\n"
        if word.size() > 0
          comps.push(word.to_s())
          word = StringBuffer(16)
        @pos += 1
        @line += 1
        @col = 1
        next
      word << ch
      @pos += 1
      @col += 1
    raise compile_error(:E_LEX_UNTERMINATED_PF, "Unterminated %f[] literal", @file, @line, @col)

  -> scan_hyper_array
    # Already consumed "%h"; @pos is at the first dim digit. Read
    # <dim> '-' <type> '[' then space/tab/newline-separated components until ']'.
    dim = StringBuffer(4)
    while @pos < @char_count && @chars[@pos] != "-"
      dim << @chars[@pos]
      @pos += 1
      @col += 1
    if @pos < @char_count
      @pos += 1
      @col += 1
    type = StringBuffer(8)
    while @pos < @char_count && @chars[@pos] != "\["
      type << @chars[@pos]
      @pos += 1
      @col += 1
    if @pos < @char_count
      @pos += 1
      @col += 1
    components = []
    word = StringBuffer(16)
    while @pos < @char_count
      ch = @chars[@pos]
      if ch == "]"
        @pos += 1
        @col += 1
        if word.size() > 0
          components.push(word.to_s())
        emit(:HYPER_ARRAY, [dim.to_s(), type.to_s(), components])
        return nil
      if ch == " " || ch == "\t"
        if word.size() > 0
          components.push(word.to_s())
          word = StringBuffer(16)
        @pos += 1
        @col += 1
        next
      if ch == "\n"
        if word.size() > 0
          components.push(word.to_s())
          word = StringBuffer(16)
        @pos += 1
        @line += 1
        @col = 1
        next
      word << ch
      @pos += 1
      @col += 1
    raise compile_error(:E_LEX_UNTERMINATED_PH, "Unterminated %h[] literal", @file, @line, @col)

  -> scan_heredoc
    # @pos is at '<', '<<~' detected. Consume <<~ and delimiter.
    @pos += 3
    @col += 3
    # Skip whitespace before delimiter
    while @pos < @char_count && (@chars[@pos] == " " || @chars[@pos] == "\t")
      @pos += 1
      @col += 1
    # Scan delimiter (uppercase, lowercase, digits, underscore)
    delim = StringBuffer(16)
    if @pos < @char_count && (is_alpha?(@lc[@pos]) || @chars[@pos] == "_")
      while @pos < @char_count && is_name_char?(@lc[@pos])
        delim << @chars[@pos]
        @pos += 1
        @col += 1
    delim_str = delim.to_s()
    if delim_str.size() == 0
      raise compile_error(:E_LEX_HEREDOC_NO_DELIM, "Expected delimiter after <<~", @file, @line, @col)
    # Skip rest of current line
    while @pos < @char_count && @chars[@pos] != "\n"
      @pos += 1
    if @pos < @char_count
      @pos += 1
      @line += 1
      @col = 1
    # Collect body lines until delimiter
    body_lines = []
    min_indent = 999999
    start_line = @line
    while @pos < @char_count
      # Measure line indent
      line_start = @pos
      indent = 0
      while @pos < @char_count && (@chars[@pos] == " " || @chars[@pos] == "\t")
        indent += 1
        @pos += 1
      # Check if this line is the closing delimiter
      match = true
      di = 0
      while di < delim_str.size()
        if @pos + di >= @char_count || @chars[@pos + di] != delim_str[di]
          match = false
          break
        di += 1
      if match && di == delim_str.size()
        after = @pos + delim_str.size()
        if after >= @char_count || @chars[after] == "\n" || @chars[after] == " " || @chars[after] == "\t"
          @pos = after
          @col = indent + delim_str.size() + 1
          while @pos < @char_count && (@chars[@pos] == " " || @chars[@pos] == "\t")
            @pos += 1
          # Build result with dedent
          result = StringBuffer(256)
          i = 0
          while i < body_lines.size()
            line = body_lines[i]
            if line.size() == 0
              # Empty line — preserve as blank
              nil
            elsif min_indent < 999999 && line.size() > min_indent
              j = min_indent
              while j < line.size()
                result << line[j]
                j += 1
            elsif min_indent < 999999
              # Line shorter than min_indent (whitespace-only)
              nil
            else
              result << line
            if i < body_lines.size() - 1
              result << "\n"
            i += 1
          emit(:STRING, result.to_s())
          return nil
      # Not the delimiter — read full line content
      @pos = line_start
      line = StringBuffer(80)
      while @pos < @char_count && @chars[@pos] != "\n"
        line << @chars[@pos]
        @pos += 1
      line_str = line.to_s()
      body_lines.push(line_str)
      # Track minimum indent for non-empty lines
      stripped_len = line_str.strip().size()
      if stripped_len > 0
        li = 0
        while li < line_str.size() && (line_str[li] == " " || line_str[li] == "\t")
          li += 1
        if li < min_indent
          min_indent = li
      # Consume newline
      if @pos < @char_count
        @pos += 1
        @line += 1
        @col = 1
    raise compile_error(:E_LEX_UNTERMINATED_HEREDOC, "Unterminated heredoc (expected [delim_str])", @file, start_line, 1)


  # Accessor for the parallel packed-token Array. Parser.new
  # (compiler/lib/parser.w) reads this as its second arg so token-
  # method-migrated parser sites can dispatch on tok.type integer
  # ids instead of hash subscripts.
  -> packed_tokens
    @packed_tokens

  # Accessor for the parallel values Array — the pre-parsed value field
  # (mirroring the hash's :value slot). Parser.new takes this as its
  # 4th arg so AST-construction sites can read @values[idx] instead of
  # reaching through the hash.
  -> values
    @values

  # Token count populated by tokenize() — Parser.new takes this as
  # its first arg in place of the legacy `tokens` Array.
  -> token_count
    @token_count

  -> source
    @source

  -> file
    @file

  # @chars is the source split into a codepoint Array (UTF-8 aware).
  # The packed token's `off` bits index into this array, NOT into the
  # raw byte source. Parser.tok_equal? walks @chars[off..off+len] to
  # do codepoint-correct comparison; @source.slice would use byte
  # indices and skew on multi-byte characters (e.g. em-dashes).
  -> chars
    @chars

  -> line_at
    @line_at

  -> col_at
    @col_at

  -> tokenize
    @packed_tokens = []
    @values = []
    @token_count = 0
    @last_token_type = nil
    @last_token_value = nil
    @paren_lambda_stack = []
    @after_lambda_params = false
    @regex_capture_scope = false
    @sup_skip_to = 0
    build_line_index()

    lc = @source.lchs("tungsten")
    packed = i64[lc.size() + 2048]
    indents = i64[1024]
    count = tungsten_tokenize_fast64(lc, lc.size(), packed, indents)

    i = 0
    while i < count
      # Strip the W_LEXICAL_TOKEN tag (0xFFFC<<48) at the boundary: every
      # field lives in bits 0-45 (flag 0, offset 2-25, len 26-37, type
      # 38-45), so the low 46 bits carry the whole token and fit the
      # 47-bit inline-int payload. With the tag on, boxing the argument
      # allocated a BigInt PER TOKEN, and every downstream bit-op
      # (materialize, emit's repack, the parser's per-peek decodes) ran
      # bignum limb walks. Untagged, the stream is plain inline ints end
      # to end. No compiler-path consumer dispatches Token methods on the
      # tag (parser reads via mask helpers); token streams are identical.
      materialize_packed_token(packed[i] & 0x3FFFFFFFFFFF)
      i += 1

    @token_count

  -> build_line_index
    @line_at = []
    @col_at = []
    line = 1
    col = 1
    i = 0
    while i < @char_count
      @line_at.push(line)
      @col_at.push(col)
      if @chars[i] == "\n"
        line += 1
        col = 1
      else
        col += 1
      i += 1
    @line_at.push(line)
    @col_at.push(col)

  ## i64: tok
  -> packed_type_id(tok)
    (tok >> 38) & 0xFF

  ## i64: tok
  -> packed_offset(tok)
    (tok >> 2) & 0xFFFFFF

  ## i64: tok
  -> packed_length(tok)
    (tok >> 26) & 0xFFF

  -> slice_chars(off, len)
    out = StringBuffer(len)
    i = 0
    while i < len && off + i < @char_count
      out << @chars[off + i]
      i += 1
    out.to_s()

  -> reset_scan_position(off)
    @pos = off
    @line = @line_at[off]
    @col = @col_at[off]

  # Map a token symbol (`:KEYWORD`, `:LPAREN`, …) to its T_X integer id
  # from core/token.w. Used by emit_at to refine the packed token's
  # type bits — the SIMD layer only knows broad categories (T_ID=1
  # covers KEYWORD/TYPE/AND/OR/GLOBAL), so without this step packed.type
  # gives the broad category not the materialized refinement.
  -> type_sym_to_id(sym)
    r = type_sym_to_id_a(sym)
    if r != 0
      return r
    r = type_sym_to_id_b(sym)
    if r != 0
      return r
    type_sym_to_id_c(sym)

  # Broad SIMD categories (1–25) + identifier refinements (26–30).
  -> type_sym_to_id_a(sym)
    case sym
    when :ID then 1
    when :NAME then 2
    when :INT then 3
    when :DECIMAL then 4
    when :STRING then 5
    when :SYMBOL then 6
    when :TYPE_HINT then 7
    when :NEWLINE then 8
    when :INDENT then 9
    when :DEDENT then 10
    when :IVAR then 12
    when :CVAR then 13
    when :PARG then 14
    when :BYTE_ARRAY then 15
    when :KEY then 16
    when :COLOR then 17
    when :CHAR then 18
    when :CODEPOINT then 19
    when :WORD_ARRAY then 20
    when :SYMBOL_ARRAY then 21
    when :MAGIC then 22
    when :EOF then 23
    when :PATH then 24
    when :SP then 25
    when :KEYWORD then 26
    when :TYPE then 27
    when :GLOBAL then 28
    when :AND then 29
    when :OR then 30
    else 0

  # Numeric / string-like refinements (31–49).
  -> type_sym_to_id_b(sym)
    case sym
    when :FLOAT then 31
    when :RATIONAL then 32
    when :WVALUE then 33
    when :DATE then 34
    when :DATETIME then 35
    when :TIME then 36
    when :MONTH then 37
    when :DURATION then 38
    when :IP then 39
    when :CIDR then 40
    when :UUID then 41
    when :BASE then 42
    when :CURRENCY then 43
    when :QUANTITY then 44
    when :LAMBDA_ARITY then 45
    when :REGEX_CAPTURE then 46
    when :STRING_INTERP then 47
    when :REGEX then 48
    when :BYTE_ARRAY_INTERP then 49
    else 0

  # Punctuation/control + arithmetic + comparison + bitwise + dot-prefix
  # + magic constants (50–142).
  -> type_sym_to_id_c(sym)
    case sym
    when :LPAREN then 50
    when :RPAREN then 51
    when :LBRACE then 52
    when :RBRACE then 53
    when :LBRACKET then 54
    when :RBRACKET then 55
    when :COMMA then 56
    when :COLON then 57
    when :SEMICOLON then 58
    when :DOT then 59
    when :DOTDOT then 60
    when :DOTDOTDOT then 61
    when :ARROW then 62
    when :FAT_ARROW then 63
    when :SAFE_NAV then 64
    when :BANG then 65
    when :QUESTION then 66
    when :PIPE_FWD then 67
    when :MAP then 68
    when :BLOCK_CALL then 69
    when :CLASS_DEF then 70
    when :PUTS_OP then 71
    when :PRINT_OP then 72
    when :RAISE_OP then 73
    when :PLUS then 80
    when :MINUS then 81
    when :STAR then 82
    when :SLASH then 83
    when :PERCENT then 84
    when :POW then 85
    when :ASSIGN then 90
    when :PLUS_EQ then 91
    when :MINUS_EQ then 92
    when :STAR_EQ then 93
    when :SLASH_EQ then 94
    when :PERCENT_EQ then 95
    when :OR_ASSIGN then 96
    when :EQ then 100
    when :NEQ then 101
    when :LT then 102
    when :GT then 103
    when :LTE then 104
    when :GTE then 105
    when :SPACESHIP then 106
    when :MATCH then 107
    when :LSHIFT then 110
    when :RSHIFT then 111
    when :AMPERSAND then 112
    when :PIPE then 113
    when :CARET then 114
    when :DOT_PRODUCT then 120
    when :CROSS_PRODUCT then 121
    when :PLUS_PLUS then 122
    when :MINUS_MINUS then 123
    when :HADAMARD then 124
    when :KRONECKER then 125
    when :DOT_PLUS then 130
    when :DOT_MINUS then 131
    when :DOT_STAR then 132
    when :DOT_SLASH then 133
    when :DOT_PIPE then 134
    when :DOT_AMP then 135
    when :DOT_CARET then 136
    when :DOT_LSHIFT then 137
    when :DOT_RSHIFT then 138
    when :MAGIC_FILE then 140
    when :MAGIC_LINE then 141
    when :MAGIC_DIR then 142
    when :SUPERSCRIPT then 143
    when :FIELD then 144
    when :BASE32 then 145
    when :BASE58 then 146
    when :BASE64 then 147
    when :IP4 then 148
    when :CIDR4 then 149
    when :NMATCH then 150
    when :TRIPLE_EQ then 151
    when :CONSTANT then 152
    when :EXPONENT then 153
    when :SQRT then 154
    when :SWAP then 155
    when :IP6 then 156
    when :CIDR6 then 157
    when :HYPER_ARRAY then 158
    when :PLUS_MINUS then 159
    when :POW_EQ then 160
    when :AMP_EQ then 161
    when :PIPE_EQ then 162
    when :CARET_EQ then 163
    when :LSHIFT_EQ then 164
    when :RSHIFT_EQ then 165
    when :DECIMAL_ARRAY then 166
    when :FLOAT_ARRAY then 167
    else 0

  -> emit_at(type, value, off)
    type_id = type_sym_to_id(type)
    if type_id != 0
      # Rewrite bits 38-45 (type id) while preserving offset, length,
      # tag, and the f_line_start flag. Decompose then recombine to
      # avoid a 64-bit mask literal (Tungsten parses 0xFFFFC03F… as
      # String because it exceeds Int64.MAX).
      off_bits   = (@current_packed_tok >> 2) & 0xFFFFFF
      len_bits   = (@current_packed_tok >> 26) & 0xFFF
      flag_bit   = @current_packed_tok & 0x1
      tag_bits   = (@current_packed_tok >> 48) << 48
      @current_packed_tok = tag_bits | (type_id << 38) | (len_bits << 26) | (off_bits << 2) | flag_bit
    push_token(type, value)

  -> raise_unexpected_character(raw, off)
    raise compile_error_with_span(:E_LEX_UNEXPECTED_CHAR, "Unexpected character '[raw]'", @file, @line_at[off], @col_at[off], raw.size())

  # Map a Unicode superscript-digit codepoint to its value, or -1.
  -> superscript_digit(c)
    if c == "⁰"
      return 0
    if c == "¹"
      return 1
    if c == "²"
      return 2
    if c == "³"
      return 3
    if c == "⁴"
      return 4
    if c == "⁵"
      return 5
    if c == "⁶"
      return 6
    if c == "⁷"
      return 7
    if c == "⁸"
      return 8
    if c == "⁹"
      return 9
    0 - 1

  ## i64: tok
  -> materialize_packed_token(tok)
    # Inline the bit-extractions instead of routing through packed_*
    # helpers — the type ascription on this method propagates so the
    # shifts lower to raw machine ops. Calling out via packed_type_id
    # boxed the value at the call boundary in stage 1 compiled code.
    @current_packed_tok = tok
    type_id = (tok >> 38) & 0xFF
    off = (tok >> 2) & 0xFFFFFF
    len = (tok >> 26) & 0xFFF
    # Skip packed op tokens already consumed by a superscript run (each
    # superscript char is a separate native token; materialize_op scans
    # the whole run at once and sets @sup_skip_to past it).
    if off < @sup_skip_to
      return nil
    raw = slice_chars(off, len)

    case type_id
    when 1
      materialize_id(raw, off)
    when 2
      emit_at(:NAME, raw, off)
    when 3
      materialize_number(raw, off)
    when 4
      materialize_decimal(raw, off)
    when 5
      materialize_string_like(raw, off)
    when 6
      emit_at(:SYMBOL, raw.slice(1, raw.size() - 1), off)
    when 7
      emit_at(:TYPE_HINT, raw, off)
    when 8
      emit_at(:NEWLINE, nil, off)
    when 9
      emit_at(:INDENT, nil, off)
    when 10
      emit_at(:DEDENT, nil, off)
    when 11
      materialize_op(raw, off)
    when 12
      emit_at(:IVAR, raw, off)
    when 13
      emit_at(:CVAR, raw, off)
    when 14
      emit_at(:PARG, raw.slice(1, raw.size() - 1), off)
    when 15
      reset_scan_position(off + 1)
      scan_byte_array()
    when 16
      reset_scan_position(off + 2)
      scan_key_literal()
    when 17
      reset_scan_position(off)
      try_scan_color()
    when 18
      materialize_char(raw, off)
    when 19
      reset_scan_position(off)
      scan_codepoint_literal()
    when 20
      reset_scan_position(off + 3)
      scan_word_array()
    when 21
      reset_scan_position(off + 3)
      scan_symbol_array()
    when 28
      reset_scan_position(off + 3)
      scan_decimal_array()
    when 29
      reset_scan_position(off + 2)
      scan_float_array()
    when 27
      reset_scan_position(off + 2)
      scan_hyper_array()
    when 22
      materialize_magic(raw, off)
    when 23
      emit_at(:EOF, nil, off)
    when 24
      emit_at(:STRING, raw, off)
    when 25
      # :SP token — one-or-more spaces/tabs between non-whitespace
      # tokens. Value carries the raw source span so the parser /
      # error formatter can see the exact whitespace if needed.
      emit_at(:SP, raw, off)
    when 26
      # t_constant — SCREAMING_SNAKE chunk identified inline by the
      # chunker. No re-scan needed at materialize time.
      emit_at(:CONSTANT, raw, off)
    else
      emit_at(:UNKNOWN, raw, off)

  -> materialize_id(raw, off)
    # A UUID whose first field starts with a hex letter (a–f) is chunked as an
    # identifier; recognize it here. Digit-first UUIDs go through scan_number.
    if raw.size() == 8 && off + 8 < @char_count && @chars[off + 8] == "-"
      reset_scan_position(off)
      if try_scan_uuid()
        @sup_skip_to = @pos
        return nil
    # IPv6 whose first group starts with a hex letter (fe80::1, db8::…) is
    # chunked as an identifier. Digit-first groups go through scan_number.
    # Guard: a 1-4 char all-hex chunk immediately followed by ':'. The "::"
    # requirement inside try_scan_ipv6 is the real filter (a hash key like
    # `ab: 1` fails it and falls through to the normal identifier path).
    if raw.size() <= 4 && off + raw.size() < @char_count && @chars[off + raw.size()] == ":" && all_hex_chunk_at?(off, raw.size())
      reset_scan_position(off)
      if try_scan_ipv6()
        @sup_skip_to = @pos
        return nil
    if raw.size() > 0 && raw[0] == "$"
      emit_at(:GLOBAL, raw, off)
      return nil
    if raw.starts_with?("u0x") && raw.size() == 19
      reset_scan_position(off)
      scan_wvalue()
      return nil
    if raw == "and"
      emit_at(:AND, raw, off)
    elsif raw == "or"
      emit_at(:OR, raw, off)
    elsif is_keyword?(raw)
      emit_at(:KEYWORD, raw, off)
    elsif is_type_name?(raw)
      emit_at(:TYPE, raw, off)
    else
      emit_at(:ID, raw, off)

  -> materialize_number(raw, off)
    if raw.starts_with?("u0x")
      reset_scan_position(off)
      scan_wvalue()
      return nil
    reset_scan_position(off)
    scan_number()
    # scan_number may consume a unit suffix beyond its NUMBER packed token
    # (e.g. `2x⁷`/`5m²` fold the superscript into the unit). Skip those
    # already-consumed packed tokens so materialize_op doesn't ALSO emit a
    # stray EXPONENT for the same superscript char.
    @sup_skip_to = @pos

  -> materialize_decimal(raw, off)
    if raw.size() > 0 && raw[0] == "~"
      value = raw.slice(1, raw.size() - 1)
      if value.size() > 0 && value[0] == "+"
        value = value.slice(1, value.size() - 1)
      emit_at(:FLOAT, value, off)
      return nil
    if raw.size() > 0 && raw[0] == "$"
      if @regex_capture_scope
        emit_at(:REGEX_CAPTURE, raw.slice(1, raw.size() - 1), off)
      else
        reset_scan_position(off)
        scan_currency_signed()
      return nil
    reset_scan_position(off)
    scan_number()
    # See materialize_number: skip packed tokens scan_number consumed past
    # its own token (a quantity's unit superscripts), so materialize_op
    # doesn't ALSO emit a stray EXPONENT for them.
    @sup_skip_to = @pos

  -> materialize_string_like(raw, off)
    if raw.starts_with?("<<~")
      reset_scan_position(off)
      scan_heredoc()
      return nil
    if raw.size() > 0 && raw[0] == "/"
      materialize_regex(raw, off)
      return nil
    if raw.size() > 0 && raw[0] == "'"
      emit_at(:STRING, unquote_single(raw), off)
      return nil
    reset_scan_position(off + 1)
    scan_string()

  -> materialize_regex(raw, off)
    pattern = StringBuffer(raw.size())
    escaped = false
    in_class = false
    i = 1
    while i < raw.size()
      ch = raw[i]
      if escaped
        pattern << "\\"
        pattern << ch
        escaped = false
      elsif ch == "\\"
        escaped = true
      elsif ch == "\["
        in_class = true
        pattern << ch
      elsif ch == "]"
        in_class = false
        pattern << ch
      elsif ch == "/" && !in_class
        opts = raw.slice(i + 1, raw.size() - i - 1)
        emit_at(:REGEX, [pattern.to_s(), opts], off)
        return nil
      else
        pattern << ch
      i += 1
    emit_at(:REGEX, [pattern.to_s(), ""], off)

  -> unquote_single(raw)
    out = StringBuffer(raw.size())
    i = 1
    last = raw.size() - 1
    while i < last
      ch = raw[i]
      if ch == "\\" && i + 1 < last
        i += 1
        esc = raw[i]
        if esc == "n"
          out << "\n"
        elsif esc == "r"
          out << "\r"
        elsif esc == "t"
          out << "\t"
        else
          out << esc
      else
        out << ch
      i += 1
    out.to_s()

  -> materialize_char(raw, off)
    cp = 0
    if raw.size() >= 4 && raw[2] == "\\"
      esc = raw[3]
      if esc == "n"
        cp = 10
      elsif esc == "t"
        cp = 9
      elsif esc == "r"
        cp = 13
      elsif esc == "\\"
        cp = 92
      elsif esc == "0"
        cp = 0
      elsif esc == "s"
        cp = 32
      elsif esc == "'"
        cp = 39
      elsif esc == "\""
        cp = 34
      else
        cp = esc.ord()
    else
      cp = raw[2].ord()
    emit_at(:CHAR, cp, off)

  -> materialize_magic(raw, off)
    if raw == "__FILE__"
      emit_at(:MAGIC_FILE, raw, off)
    elsif raw == "__LINE__"
      emit_at(:MAGIC_LINE, raw, off)
    else
      emit_at(:MAGIC_DIR, raw, off)

  # True iff the previous meaningful token is a KEYWORD that denotes a
  # value (self, super, nil, true, false). The PLUS-vs-CLASS_DEF and
  # LSHIFT-vs-PUTS_OP discrimination needs this so `self + 1` parses
  # as addition rather than a malformed class declaration.
  -> is_value_keyword_prev?
    if @last_token_type != :KEYWORD
      return false
    @last_token_value == "self" || @last_token_value == "super" || @last_token_value == "nil" || @last_token_value == "true" || @last_token_value == "false"

  -> materialize_op(raw, off)
    # Leading "::" opens an IPv6 literal (::1, bare ::, ::ffff:1.2.3.4, ::/0).
    # Fire before the operator table so "::" isn't split into two COLONs.
    # There are no bare "::" operator sequences in valid .w source (all "::"
    # in compiler/core/lib live inside strings or comments), so this cannot
    # change the self-host token stream. Falls through on no-match.
    if @chars[off] == ":" && off + 1 < @char_count && @chars[off + 1] == ":"
      reset_scan_position(off)
      if try_scan_ipv6()
        @sup_skip_to = @pos
        return nil
    if raw == "->" || raw.starts_with?("->/")
      if raw.starts_with?("->/")
        emit_at(:LAMBDA_ARITY, raw, off)
      else
        emit_at(:ARROW, raw, off)
      return nil
    if raw == "<<"
      # `->(x) << ...` — the `)` closes a lambda param list, not a value, so
      # `<<` begins the body as a PUTS_OP. Without the latch, RPAREN's
      # value-type classification would mis-emit LSHIFT here.
      if (is_value_type?(@last_token_type) || is_value_keyword_prev?()) && !@after_lambda_params
        emit_at(:LSHIFT, raw, off)
      else
        emit_at(:PUTS_OP, raw, off)
      return nil
    if raw == "+"
      if is_value_type?(@last_token_type) || is_value_keyword_prev?()
        emit_at(:PLUS, raw, off)
      else
        emit_at(:CLASS_DEF, raw, off)
      return nil
    # MAP operator: `/name` with an identifier immediately after the slash
    # (no space) is a pipeline map stage — both prefix (`/sq`) and infix
    # (`arr/sq`). Division requires spaces (`a / b`) or a non-ident operand
    # (`10/2`); the is_ident_start check below excludes both. Note: this
    # makes `a/b` (two bare identifiers, no spaces) a map, by design.
    if raw == "/" && off + 1 < @char_count && is_ident_start?(@lc[off + 1])
      emit_at(:MAP, raw, off)
      return nil
    if raw == "<-"
      emit_at(:PRINT_OP, raw, off)
    elsif raw == "<!"
      emit_at(:RAISE_OP, raw, off)
    elsif raw == "=>"
      emit_at(:FAT_ARROW, raw, off)
    elsif raw == "=="
      emit_at(:EQ, raw, off)
    elsif raw == "==="
      emit_at(:TRIPLE_EQ, raw, off)
    elsif raw == "=~"
      emit_at(:MATCH, raw, off)
    elsif raw == "!="
      emit_at(:NEQ, raw, off)
    elsif raw == "!~"
      emit_at(:NMATCH, raw, off)
    elsif raw == "<=>"
      emit_at(:SPACESHIP, raw, off)
    elsif raw == "<="
      emit_at(:LTE, raw, off)
    elsif raw == ">>="
      emit_at(:RSHIFT_EQ, raw, off)
    elsif raw == ">>"
      emit_at(:RSHIFT, raw, off)
    elsif raw == ">="
      emit_at(:GTE, raw, off)
    elsif raw == "&."
      emit_at(:SAFE_NAV, raw, off)
    elsif raw == "&&"
      emit_at(:AND, raw, off)
    elsif raw == "||="
      emit_at(:OR_ASSIGN, raw, off)
    elsif raw == "||"
      emit_at(:OR, raw, off)
    elsif raw == "|>"
      emit_at(:PIPE_FWD, raw, off)
    elsif raw == "++"
      emit_at(:PLUS_PLUS, raw, off)
    elsif raw == "+="
      emit_at(:PLUS_EQ, raw, off)
    elsif raw == "--"
      emit_at(:MINUS_MINUS, raw, off)
    elsif raw == "-="
      emit_at(:MINUS_EQ, raw, off)
    elsif raw == "**="
      emit_at(:POW_EQ, raw, off)
    elsif raw == "**"
      emit_at(:POW, raw, off)
    elsif raw == "*="
      emit_at(:STAR_EQ, raw, off)
    elsif raw == "/="
      emit_at(:SLASH_EQ, raw, off)
    elsif raw == "%="
      emit_at(:PERCENT_EQ, raw, off)
    elsif raw == "<<="
      emit_at(:LSHIFT_EQ, raw, off)
    elsif raw == "&="
      emit_at(:AMP_EQ, raw, off)
    elsif raw == "|="
      emit_at(:PIPE_EQ, raw, off)
    elsif raw == "^="
      emit_at(:CARET_EQ, raw, off)
    elsif raw == "-"
      emit_at(:MINUS, raw, off)
    elsif raw == "-@"
      # Unary-minus method-name marker (`-> -@`). Emitted as T_ID so
      # expect_method_name treats it as a normal identifier.
      emit_at(:ID, raw, off)
    elsif raw == "+@"
      # Unary-plus method-name marker (`-> +@`). Same shape as `-@`.
      emit_at(:ID, raw, off)
    elsif raw == "*"
      emit_at(:STAR, raw, off)
    elsif raw == "/"
      emit_at(:SLASH, raw, off)
    elsif raw == "·" || raw == "⋅"
      emit_at(:DOT_PRODUCT, raw, off)
    elsif raw == "√"
      emit_at(:SQRT, raw, off)
    elsif raw == "<>"
      emit_at(:SWAP, raw, off)
    elsif raw == "×"
      emit_at(:CROSS_PRODUCT, raw, off)
    elsif raw == "⊙"
      emit_at(:HADAMARD, raw, off)
    elsif raw == "⊗"
      emit_at(:KRONECKER, raw, off)
    elsif raw == "±"
      emit_at(:PLUS_MINUS, raw, off)
    elsif raw == "≈"
      # Approx-equal. Currently only a method NAME in the stdlib (String#≈, a
      # bodyless declaration); not yet a binary operator. Emit as ID so
      # expect_method_name accepts `-> ≈(other)` — same shape as `-@`/`+@`.
      emit_at(:ID, raw, off)
    elsif raw == "%"
      emit_at(:PERCENT, raw, off)
    elsif raw == "<"
      emit_at(:LT, raw, off)
    elsif raw == ">"
      emit_at(:GT, raw, off)
    elsif raw == "="
      emit_at(:ASSIGN, raw, off)
    elsif raw == "!"
      emit_at(:BANG, raw, off)
    elsif raw == "..."
      emit_at(:DOTDOTDOT, raw, off)
    elsif raw == ".."
      emit_at(:DOTDOT, raw, off)
    elsif raw == ".+"
      emit_at(:DOT_PLUS, raw, off)
    elsif raw == ".-"
      emit_at(:DOT_MINUS, raw, off)
    elsif raw == ".*"
      emit_at(:DOT_STAR, raw, off)
    elsif raw == "./"
      emit_at(:DOT_SLASH, raw, off)
    elsif raw == ".|"
      emit_at(:DOT_PIPE, raw, off)
    elsif raw == ".&"
      emit_at(:DOT_AMP, raw, off)
    elsif raw == ".^"
      emit_at(:DOT_CARET, raw, off)
    elsif raw == ".<<"
      emit_at(:DOT_LSHIFT, raw, off)
    elsif raw == ".>>"
      emit_at(:DOT_RSHIFT, raw, off)
    elsif raw == "."
      emit_at(:DOT, raw, off)
    elsif raw == ","
      emit_at(:COMMA, raw, off)
    elsif raw == "&("
      emit_at(:BLOCK_CALL, raw, off)
    elsif raw == "&"
      emit_at(:AMPERSAND, raw, off)
    elsif raw == "|"
      emit_at(:PIPE, raw, off)
    elsif raw == "^"
      emit_at(:CARET, raw, off)
    elsif raw == "("
      # Remember whether this `(` opens a lambda param list (`->(`). Read
      # @last_token_type before emit_at overwrites it. Store 1/0 (not a
      # bool) to sidestep the inline bool-array codegen path.
      opens_lambda = 0
      if @last_token_type == :ARROW
        opens_lambda = 1
      @paren_lambda_stack.push(opens_lambda)
      emit_at(:LPAREN, raw, off)
    elsif raw == ")"
      was_lambda = 0
      if @paren_lambda_stack.size() > 0
        was_lambda = @paren_lambda_stack.pop()
      emit_at(:RPAREN, raw, off)
      # Set after emit_at so push_token's reset doesn't clear it.
      if was_lambda == 1
        @after_lambda_params = true
    elsif raw == "{"
      emit_at(:LBRACE, raw, off)
    elsif raw == "}"
      emit_at(:RBRACE, raw, off)
    elsif raw == "\["
      emit_at(:LBRACKET, raw, off)
    elsif raw == "]"
      emit_at(:RBRACKET, raw, off)
    elsif raw == "?"
      emit_at(:QUESTION, raw, off)
    elsif raw == ":"
      emit_at(:COLON, raw, off)
    elsif raw == ";"
      emit_at(:SEMICOLON, raw, off)
    elsif superscript_digit(@chars[off]) >= 0
      # A superscript run after a value is an exponent: x⁷ ⇒ x ** 7,
      # (a + b)¹² ⇒ (a + b) ** 12. The native tokenizer emits one packed op
      # token per superscript char, so we scan the whole contiguous run
      # here and emit ONE EXPONENT token carrying the decoded value, then
      # mark the rest of the run skipped (materialize_packed_token honours
      # @sup_skip_to). A distinct token (vs POW + INT) keeps the superscript
      # origin visible at the token level; the parser turns it into a `**`.
      sup_digits = ""
      sup_j = off
      while sup_j < @char_count && superscript_digit(@chars[sup_j]) >= 0
        sup_digits = sup_digits + superscript_digit(@chars[sup_j]).to_s()
        sup_j = sup_j + 1
      emit(:EXPONENT, sup_digits)
      @sup_skip_to = sup_j
    elsif raw == "°"
      # Degree unit (°C / °F / °R): scan the ° plus any trailing letters into
      # one NAME token so a bare unit after `|` (`100 °C | °F`) resolves via
      # known_unit_name?. A number-prefixed `100 °C` is caught earlier in the
      # number path. @sup_skip_to suppresses the now-consumed letter chunks.
      deg_j = off + 1
      while deg_j < @char_count && unit_alpha_at?(deg_j)
        deg_j = deg_j + 1
      emit_at(:NAME, slice_chars(off, deg_j - off), off)
      @sup_skip_to = deg_j
    else
      raise_unexpected_character(raw, off)

# --- BEGIN GENERATED: known_unit_name ---
-> known_unit_name?(s)
  if s in ("1/mol" "A" "A/m²" "AU tbsp" "Ah" "Apgar" "B" "B/flop" "B/s" "BOE" "BPM" "BTU")
    return true
  if s in ("Ba" "Beaufort" "Bortle" "Bps" "Bq" "Bq/kg" "Bq/m³" "C" "C/m³" "CFU" "CFU/mL" "CFUs")
    return true
  if s in ("CWT" "Ci" "D" "DMIPS" "DU" "DWORD" "Da" "E" "EA" "EB" "EBps" "EBq")
    return true
  if s in ("EC" "EDa" "EF" "EF-scale" "EFLOPS" "EGy" "EH" "EHz" "EJ" "EJy" "EK" "EL")
    return true
  if s in ("EN" "EOPS" "EPa" "ES" "ESv" "ET" "EV" "EVA" "EW" "EWb" "Eb" "Ebps")
    return true
  if s in ("Ecd" "Ecentury" "EeV" "Eflops" "Efortnight" "Eg" "Eh" "EiB" "Eib" "Ekat" "El" "Elm")
    return true
  if s in ("Elx" "Em" "Emol" "Eotvos" "Epc" "Eq" "Eq/L" "Es" "Et" "Evar" "Eötvös" "EΩ")
    return true
  if s in ("F" "F-scale" "F/m" "FLOPS" "FPS" "Fr_catheter" "GA" "GB" "GB/s" "GBps" "GBq" "GC")
    return true
  if s in ("GDa" "GF" "GFLOPS" "GGy" "GH" "GHz" "GIPS" "GJ" "GJy" "GK" "GL" "GMAC/s")
    return true
  if s in ("GN" "GOPS" "GPa" "GS" "GSv" "GT" "GT/s" "GUPS" "GV" "GVA" "GW" "GWb")
    return true
  if s in ("Ga" "Gal" "Gb" "Gb/s" "Gbps" "Gcd" "Gcentury" "GeV" "Gflops" "Gfortnight" "Gg" "GiB")
    return true
  if s in ("GiB/s" "Gib" "Gkat" "Gl" "Glm" "Glx" "Gm" "Gmol" "Gpc" "Gs" "Gt" "Gtok/s")
    return true
  if s in ("Gvar" "Gy" "Gy/s" "GΩ" "H" "HB" "HRC" "HU" "HV" "Hz" "IOPS" "ISO")
    return true
  if s in ("ISO sensitivity" "ISO_speed" "IU" "IU/mL" "J" "J/(kg·K)" "J/(mol·K)" "J/K" "J/kg" "J/kg/K" "J/m²" "J/m³")
    return true
  if s in ("J/op" "J/tok" "Jy" "J·s" "K" "KB" "KOPS" "KiB" "Kib" "L" "L per 100 km" "L/100km")
    return true
  if s in ("L/min" "LT" "L_sun_nominal" "La" "L☉_N" "M" "MA" "MAC/s" "MB" "MB/s" "MBps" "MBq")
    return true
  if s in ("MC" "MDa" "MF" "MFLOPS" "MGy" "MH" "MHz" "MIPS" "MJ" "MJy" "MK" "ML")
    return true
  if s in ("MMAC/s" "MN" "MOPS" "MPG" "MPGe" "MPa" "MS" "MSv" "MT" "MT/s" "MV" "MVA")
    return true
  if s in ("MW" "MWb" "MWh" "M_bol" "Mach at 20 C" "Mach in air at 20 C" "Mag" "Mb" "Mb/s" "Mbol" "Mbps" "Mcd")
    return true
  if s in ("Mcentury" "MeV" "Mflops" "Mfortnight" "Mg" "MiB" "MiB/s" "Mib" "Mkat" "Ml" "Mlm" "Mlx")
    return true
  if s in ("Mm" "Mmol" "Mohs" "Mpc" "Ms" "Mt" "Mtok/s" "Mvar" "Mw" "Mx" "MΩ" "M⊕")
    return true
  if s in ("M☉" "M☽" "M♃" "N" "N/A²" "N/m" "N·m" "N·s" "Oe" "Osm/L" "P" "PA")
    return true
  if s in ("PB" "PBps" "PBq" "PC" "PDa" "PF" "PFLOPS" "PFU" "PFU/mL" "PFUs" "PGy" "PH")
    return true
  if s in ("PHz" "PJ" "PJy" "PK" "PL" "PN" "POPS" "PPFD" "PPS" "PPa" "PS" "PSv")
    return true
  if s in ("PT" "PV" "PVA" "PVU" "PW" "PWb" "Pa" "Pb" "Pbps" "Pcd" "Pcentury" "PeV")
    return true
  if s in ("Pflops" "Pfortnight" "Pg" "PiB" "Pib" "Pkat" "Pl" "Planck length" "Planck mass" "Planck time" "Plm" "Plx")
    return true
  if s in ("Pm" "Pmol" "Ppc" "Ps" "Pt" "Pvar" "PΩ" "QA" "QALY" "QALYs" "QB" "QBps")
    return true
  if s in ("QBq" "QC" "QDa" "QF" "QGy" "QH" "QHz" "QJ" "QJy" "QK" "QL" "QN")
    return true
  if s in ("QPS" "QPa" "QS" "QSv" "QT" "QV" "QVA" "QW" "QWORD" "QWb" "Qb" "Qbps")
    return true
  if s in ("Qcd" "Qcentury" "QeV" "Qfortnight" "Qg" "QiB" "Qib" "Qkat" "Ql" "Qlm" "Qlx" "Qm")
    return true
  if s in ("Qmol" "Qpc" "Qs" "Qt" "Qvar" "QΩ" "RA" "RB" "RBE" "RBps" "RBq" "RC")
    return true
  if s in ("RDa" "RF" "RGy" "RH" "RHz" "RJ" "RJy" "RK" "RL" "RN" "RPS" "RPa")
    return true
  if s in ("RS" "RSv" "RT" "RU" "RV" "RVA" "RW" "RWb" "R_exposure" "R_sun_nominal" "Rb" "Rbps")
    return true
  if s in ("Rcd" "Rcentury" "ReV" "Rfortnight" "Rg" "RiB" "Rib" "Richter" "Rkat" "Rl" "Rlm" "Rlx")
    return true
  if s in ("Rm" "Rmol" "Rpc" "Rs" "Rt" "Rvar" "Ry" "RΩ" "R⊕" "R☉" "R☉_N" "S")
    return true
  if s in ("S/m" "SS_category" "Saffir-Simpson" "St" "Sv" "Sv/h" "Sv_ocean" "Svedberg" "T" "T/s" "TA" "TB")
    return true
  if s in ("TBps" "TBq" "TC" "TCE" "TDa" "TECU" "TEPS" "TF" "TFLOPS" "TGy" "TH" "THz")
    return true
  if s in ("TJ" "TJy" "TK" "TL" "TMAC/s" "TN" "TOPS" "TPS" "TPa" "TS" "TSv" "TT")
    return true
  if s in ("TT/s" "TV" "TVA" "TW" "TWb" "Tb" "Tbps" "Tcd" "Tcentury" "TeV" "Tflops" "Tfortnight")
    return true
  if s in ("Tg" "TiB" "Tib" "Tkat" "Tl" "Tlm" "Tlx" "Tm" "Tmol" "Torr" "Tpc" "Ts")
    return true
  if s in ("Tt" "Tvar" "TΩ" "U/L" "U_enzyme" "V" "V/m" "VA" "W" "W/(m²·K⁴)" "W/(m·K)" "W/m/K")
    return true
  if s in ("W/m²" "W/m²/Hz" "W/m³" "W/sr" "W/sr/m²" "Wb" "YA" "YB" "YBps" "YBq" "YC" "YDa")
    return true
  if s in ("YF" "YFLOPS" "YGy" "YH" "YHz" "YJ" "YJy" "YK" "YL" "YN" "YPa" "YS")
    return true
  if s in ("YSv" "YT" "YV" "YVA" "YW" "YWb" "Yb" "Ybps" "Ycd" "Ycentury" "YeV" "Yflops")
    return true
  if s in ("Yfortnight" "Yg" "YiB" "Yib" "Ykat" "Yl" "Ylm" "Ylx" "Ym" "Ymol" "Ypc" "Ys")
    return true
  if s in ("Yt" "Yvar" "YΩ" "ZA" "ZB" "ZBps" "ZBq" "ZC" "ZDa" "ZF" "ZFLOPS" "ZGy")
    return true
  if s in ("ZH" "ZHz" "ZJ" "ZJy" "ZK" "ZL" "ZN" "ZPa" "ZS" "ZSv" "ZT" "ZV")
    return true
  if s in ("ZVA" "ZW" "ZWb" "Zb" "Zbps" "Zcd" "Zcentury" "ZeV" "Zflops" "Zfortnight" "Zg" "ZiB")
    return true
  if s in ("Zib" "Zkat" "Zl" "Zlm" "Zlx" "Zm" "Zmol" "Zpc" "Zs" "Zt" "Zvar" "ZΩ")
    return true
  if s in ("a0" "aA" "aB" "aBps" "aBq" "aC" "aDa" "aF" "aGy" "aH" "aHz" "aJ")
    return true
  if s in ("aJy" "aK" "aL" "aN" "aPa" "aS" "aSv" "aT" "aV" "aVA" "aW" "aWb")
    return true
  if s in ("a_0" "ab" "ab-1" "abA" "abC" "abF" "abH" "abV" "ab^-1" "abampere" "abarn" "abcoulomb")
    return true
  if s in ("abfarad" "abhenry" "abinv" "abohm" "abps" "absolute magnitude" "absorbed-dose rad" "abvolt" "abΩ" "ab⁻¹" "ac" "acd")
    return true
  if s in ("acentury" "acre" "acres" "aeV" "afortnight" "ag" "akat" "al" "alm" "alpha" "altuve" "altuves")
    return true
  if s in ("alx" "am" "amah" "amol" "amot" "amp hours" "ampere" "ampere hour" "ampere-hour" "amperes" "amperes per square meter" "amphora")
    return true
  if s in ("amphorae" "amphoras" "angstrom" "angstroms" "angular acceleration" "angular velocity" "apc" "apgar" "apgar score" "apostilb" "apostilbs" "apparent magnitude")
    return true
  if s in ("arcmin" "arcsec" "areal density" "aroura" "arourae" "arouras" "arpent" "arpents" "arshin" "arshins" "as" "asb")
    return true
  if s in ("astronomical unit" "astronomical units" "at" "atm" "atmosphere" "atmospheres" "attobarn" "attobarns" "au" "australian tablespoon" "australian tablespoons" "australian tbsp")
    return true
  if s in ("australian_tbsp" "avar" "aΩ" "b" "baker's dozen" "bakers dozen" "bakers_dozen" "ban" "banana" "banana for scale" "banana_for_scale" "bananas")
    return true
  if s in ("bananas for scale" "bar" "barleycorn" "barleycorns" "barn" "barn megaparsec" "barn-megaparsec" "barn-megaparsecs" "barns" "barrel" "barrel of oil equivalent" "barrels")
    return true
  if s in ("barye" "basis point" "basis points" "basis_point" "basis_points" "bath" "baths" "baud" "beard second" "beard seconds" "beard-second" "beard-seconds")
    return true
  if s in ("beat" "beats" "beats per minute" "beaufort" "becquerel" "becquerels" "beka" "bekah" "bekas" "biblical talent" "biblical_mil" "biblical_mina")
    return true
  if s in ("biblical_talent" "billions and billions" "biot" "bit" "bit/(s·Hz)" "bit/s" "bit/s/Hz" "bit/symbol" "bits" "bits per second per hertz" "bits per symbol" "block")
    return true
  if s in ("blocks" "boe" "bohr magneton" "bohr_magneton" "bohr_radius" "boiler horsepower" "boiler_horsepower" "bolometric magnitude" "bortle" "bottle" "bottles" "bp_finance")
    return true
  if s in ("bpm" "bps" "brad" "brads" "brinell" "bu" "bushel" "bushels" "butt" "byte" "bytes" "bytes per flop")
    return true
  if s in ("cA" "cB" "cBps" "cBq" "cC" "cDa" "cF" "cGy" "cH" "cHz" "cJ" "cJy")
    return true
  if s in ("cK" "cL" "cN" "cP" "cPa" "cS" "cSt" "cSv" "cT" "cV" "cVA" "cW")
    return true
  if s in ("cWb" "cable" "cable length" "cable lengths" "cable_length" "cables" "cal" "cal_IT" "cal_th" "calorie" "calorie IT" "calories")
    return true
  if s in ("candela" "candela per square meter" "candelas" "carat" "carats" "catalytic activity concentration" "cb" "cbps" "ccd" "ccentury" "cd" "cd/m²")
    return true
  if s in ("ceV" "cell" "cells" "cells/mL" "celsius" "celsius difference" "cent" "cent_pitch" "centipoise" "centistokes" "cents" "centuries")
    return true
  if s in ("century" "cfortnight" "cg" "ch" "chain" "chains" "charge density" "chelakim" "chelek" "chetvert" "chetverts" "chi")
    return true
  if s in ("chinese dan" "chinese li" "chinese_dan" "chinese_li" "chis" "cicero" "ckat" "cl" "clm" "clo" "clo unit" "cloth nail")
    return true
  if s in ("cluster" "clusters" "clx" "cm" "cm-1" "cmH2O" "cm^-1" "cmol" "cm²" "cm³" "cm⁻¹" "colony forming unit")
    return true
  if s in ("colony-forming unit" "compton wavelength" "compton wavelength electron" "compton wavelength neutron" "compton wavelength proton" "compton_e" "compton_n" "compton_p" "compton_wavelength" "conductivity" "copies" "copies/mL")
    return true
  if s in ("copy" "cord" "cords" "coulomb" "coulombs" "coulombs per cubic meter" "count" "counts per minute" "counts per second" "cpc" "cpm" "cps")
    return true
  if s in ("crumb" "crumbs" "cs" "css rem" "ct" "cubic meters per second" "cubit" "cubits" "cun" "cuns" "cup" "cups")
    return true
  if s in ("curie" "curies" "current density" "cvar" "cwt" "cyc" "cycle" "cycles" "cΩ" "d" "dA" "dB")
    return true
  if s in ("dBps" "dBq" "dC" "dDa" "dF" "dGy" "dH" "dHz" "dJ" "dJy" "dK" "dL")
    return true
  if s in ("dN" "dPa" "dS" "dSv" "dT" "dV" "dVA" "dW" "dWb" "daA" "daB" "daBps")
    return true
  if s in ("daBq" "daC" "daDa" "daF" "daGy" "daH" "daHz" "daJ" "daJy" "daK" "daL" "daN")
    return true
  if s in ("daPa" "daS" "daSv" "daT" "daV" "daVA" "daW" "daWb" "dab" "dabps" "dacd" "dacentury")
    return true
  if s in ("daeV" "dafortnight" "dag" "dakat" "dal" "dalm" "dalton" "daltons" "dalx" "dam" "damol" "dan_cn")
    return true
  if s in ("dapc" "darcies" "darcy" "das" "dash" "dashes" "dat" "davar" "day" "days" "daΩ" "db")
    return true
  if s in ("dbps" "dcd" "dcentury" "deV" "debye" "debyes" "decade" "decades" "decay" "decays" "decays per minute" "deciban")
    return true
  if s in ("decibans" "decitex" "deg" "degree" "degrees" "delisle" "delta celsius" "delta fahrenheit" "delta kelvin" "delta rankine" "denier" "deniers")
    return true
  if s in ("dfortnight" "dg" "didot" "digit" "digits" "diopter" "diopters" "dioptre" "dioptres" "dit" "dits" "dkat")
    return true
  if s in ("dl" "dlm" "dlx" "dm" "dmol" "dobson unit" "dobson units" "dog year" "dog years" "dogyear" "donkey power" "donkey-power")
    return true
  if s in ("donkeypower" "dots per inch" "dots per pixel" "dozen" "dozens" "dpc" "dpi" "dpm" "dppx" "dr" "drachm" "drams")
    return true
  if s in ("drop" "drops" "ds" "dt" "dvar" "dword" "dwords" "dwt" "dyn" "dyne" "dynes" "dΩ")
    return true
  if s in ("eV" "earth mass" "earth radius" "earthmass" "earthradius" "edge" "edges" "egypt_palm" "egyptian palm" "egyptian palms" "einstein" "einsteins")
    return true
  if s in ("electric field" "electric horsepower" "electric_horsepower" "electron mass" "electron_mass" "electronvolt" "electronvolts" "em" "en" "energy density" "english cubit" "english cubits")
    return true
  if s in ("english_cubit" "enhanced fujita" "entropy" "enzyme unit" "enzyme units" "eotvos" "ephah" "ephahs" "ephas" "equivalent" "equivalents" "erg")
    return true
  if s in ("etzba" "etzbaot" "ev" "e₀" "f stop" "f-stop" "f-stops" "fA" "fB" "fBps" "fBq" "fC")
    return true
  if s in ("fDa" "fF" "fGy" "fH" "fHz" "fJ" "fJy" "fK" "fL" "fN" "fPa" "fS")
    return true
  if s in ("fSv" "fT" "fV" "fVA" "fW" "fWb" "f_stop" "fahrenheit" "fahrenheit difference" "farad" "farads" "fathom")
    return true
  if s in ("fathoms" "fb" "fb-1" "fb^-1" "fbarn" "fbinv" "fbps" "fb⁻¹" "fc" "fcd" "fcentury" "feV")
    return true
  if s in ("feet" "feet of water" "femtobarn" "femtobarns" "fen" "fens" "ffortnight" "fg" "fine structure constant" "fine_structure" "fingerbreadth" "firkin")
    return true
  if s in ("firkins" "fkat" "fl" "fl dr" "fl oz" "fldr" "flm" "flop" "flop/J" "flops" "flops per joule" "flops_count")
    return true
  if s in ("floz" "fluid dram" "fluid drams" "fluid ounce" "fluid ounces" "flx" "fm" "fmol" "foe" "foes" "foot" "foot candle")
    return true
  if s in ("foot candles" "foot of water" "foot pound" "foot pounds" "foot-candle" "foot-lambert" "foot-pound" "foot-pounds" "fortnight" "fortnights" "fpc" "fps")
    return true
  if s in ("frame" "frames" "frames per second" "franklin" "french gauge" "french_gauge" "fs" "fstop" "ft" "ft H2O" "ft of water" "ftH2O")
    return true
  if s in ("ftlbf" "ft²" "fujita" "fujita scale" "funt" "funt_ru" "fur" "furlong" "furlongs" "fvar" "fΩ" "g")
    return true
  if s in ("g CO2e" "g/L" "g/dL" "g0" "gCO₂e" "gCO₂e/kWh" "gCO₂e/pkm" "g_n" "gal" "gallon" "gallons" "gauss")
    return true
  if s in ("gaz" "gazes" "gee" "geopotential meter" "geopotential metre" "gerah" "gerahs" "giga-updates per second" "gigaton" "gigatons" "gilbert" "gilberts")
    return true
  if s in ("gill" "gills" "gon" "googol" "googolplex" "googolplexes" "googols" "gos" "gpm" "gr" "grad" "gradian")
    return true
  if s in ("gradians" "grain" "grains" "gram" "grams" "grams CO2e" "grape jelly" "grave" "gray" "grays" "great gross" "great_gross")
    return true
  if s in ("grid carbon intensity" "gross" "gō" "g₀" "h" "hA" "hB" "hBps" "hBq" "hC" "hDa" "hF")
    return true
  if s in ("hGy" "hH" "hHz" "hJ" "hJy" "hK" "hL" "hN" "hPa" "hS" "hSv" "hT")
    return true
  if s in ("hV" "hVA" "hW" "hWb" "ha" "halakim" "half step" "halfstep" "hand" "handbreadth" "handbreadths" "hands")
    return true
  if s in ("hartley" "hartleys" "hartree" "hartrees" "hath" "haths" "hb" "hbps" "hcd" "hcentury" "heV" "heap")
    return true
  if s in ("heaps" "heat capacity" "heat flux" "heat_capacity" "hectare" "hectares" "helek" "henries" "henry" "henrys" "hertz" "hfortnight")
    return true
  if s in ("hg" "hin" "hins" "hkat" "hl" "hlm" "hlx" "hm" "hmol" "hogshead" "hogsheads" "hole")
    return true
  if s in ("holes" "horsepower" "hounsfield" "hounsfield_unit" "hour" "hours" "hp" "hpc" "hs" "ht" "hvar" "hΩ")
    return true
  if s in ("imp gal" "imperial bottle" "imperial gallon" "imperial gallons" "imperial pint" "imperial pints" "imperial_pint" "impgal" "impulse" "in H2O" "in of water" "inH2O")
    return true
  if s in ("inHg" "inch" "inch of water" "inches" "inches of water" "indian kos" "instant" "instants" "instruction" "instructions" "international table calorie" "international unit")
    return true
  if s in ("international units" "inv_ab" "inv_fb" "inv_nb" "inv_pb" "inverse attobarn" "inverse femtobarn" "inverse nanobarn" "inverse picobarn" "io" "io_op" "io_ops")
    return true
  if s in ("iops" "ios" "isaron" "iso" "issaron" "iugera" "iugerum" "j" "jam" "janskies" "jansky" "janskys")
    return true
  if s in ("japanese cup" "japanese cups" "japanese_cup" "jelly" "jerk" "jeroboam" "jeroboams" "jiffies" "jiffy" "jigger" "jiggers" "jin")
    return true
  if s in ("jins" "jo" "jos" "joule" "joules" "joules per kelvin" "joules per operation" "joules per token" "jubilee" "jubilees" "jugerum" "julian year")
    return true
  if s in ("julian years" "julianyear" "jupiter mass" "jupitermass" "kA" "kB" "kBps" "kBq" "kC" "kDa" "kF" "kFLOPS")
    return true
  if s in ("kGy" "kH" "kHz" "kJ" "kJy" "kK" "kL" "kN" "kPa" "kS" "kSv" "kT")
    return true
  if s in ("kV" "kVA" "kW" "kWb" "kWh" "kab" "kabim" "kabs" "kanme" "kanmes" "kat" "kat/m³")
    return true
  if s in ("katal" "katals" "kayser" "kaysers" "kb" "kbps" "kcal" "kcal_IT" "kcal_th" "kcd" "kcentury" "keV")
    return true
  if s in ("kelvin" "kelvin difference" "kflops" "kfortnight" "kg" "kg CO2e" "kg/m" "kg/m²" "kg/m³" "kg/s" "kgCO₂e" "kgf")
    return true
  if s in ("kg·m/s" "khet" "khets" "kikar" "kilderkin" "kilderkins" "kilocalorie" "kilocalories" "kilogram" "kilogram force" "kilogram-force" "kilograms")
    return true
  if s in ("kilograms CO2e" "kilograms per cubic meter" "kilograms per second" "kiloton" "kilotons" "kilowarhol" "kilowarhols" "kilowatt hour" "kilowatt hours" "kilowatt-hour" "kilowatt-hours" "kkat")
    return true
  if s in ("kl" "klm" "klx" "km" "km/h" "kmol" "km²" "kn" "knot" "knots" "koku" "kokus")
    return true
  if s in ("kor" "korim" "kors" "kos" "kos_indian" "kpc" "kph" "ks" "kt" "ktok/s" "kvar" "kΩ")
    return true
  if s in ("l" "l/100km" "lambert" "lamberts" "lb" "lbf" "lbs" "league" "leagues" "li_cn" "liang" "liangs")
    return true
  if s in ("libra romana" "libra_roma" "lieue de poste" "lieue_de_poste" "lieues de poste" "light hour" "light hours" "light minute" "light minutes" "light nanosecond" "light second" "light seconds")
    return true
  if s in ("light year" "light years" "light-nanosecond" "light_nanosecond" "lighthour" "lighthours" "lightminute" "lightminutes" "lightsecond" "lightseconds" "lightyear" "lightyears")
    return true
  if s in ("linear density" "link" "link_chain" "links" "liter" "liters" "liters per 100 km" "liters per minute" "litre" "litres" "litres per minute" "lm")
    return true
  if s in ("lm·s" "long ton" "long tons" "lumen" "lumens" "luminous energy" "luminous exposure" "lunar month" "lunar months" "lunarmonth" "lustra" "lustrum")
    return true
  if s in ("lustrums" "lux" "lx" "lx·s" "ly" "m" "m H2O" "m of water" "m/s" "m/s²" "m/s³" "mA")
    return true
  if s in ("mB" "mBps" "mBq" "mC" "mDa" "mEq/L" "mF" "mGal" "mGy" "mH" "mH2O" "mHz")
    return true
  if s in ("mJ" "mJy" "mK" "mL" "mM" "mN" "mOsm/L" "mPa" "mS" "mSv" "mT" "mV")
    return true
  if s in ("mVA" "mW" "mWb" "m_e" "m_n" "m_p" "m_μ" "mac" "mach" "mach_air_20C" "macs" "mag")
    return true
  if s in ("magnitude" "magnitudes" "magnum" "magnums" "maneh" "mas" "mass density" "mass flow" "maund" "maunds" "maxwell" "maxwells")
    return true
  if s in ("mb" "mbar" "mbps" "mcd" "mcentury" "meV" "megaton" "megatons" "melchizedek" "melchizedeks" "meter" "meter of water")
    return true
  if s in ("meters" "meters of water" "methuselah" "methuselahs" "metric cup" "metric cups" "metric tablespoon" "metric tablespoons" "metric tbsp" "metric ton" "metric tons" "metric_cup")
    return true
  if s in ("metric_tbsp" "mfortnight" "mg" "mg/L" "mg/dL" "mg/dL glucose" "mg/dL_glucose" "mho" "mi" "mi/h" "mickey" "mickeys")
    return true
  if s in ("microarcsecond" "microarcseconds" "microlife" "microlives" "micromolar" "micromort" "micromorts" "mil" "mile" "mile per hour" "miles" "miles per gallon")
    return true
  if s in ("miles per gallon equivalent" "miles per hour" "mill_finance" "mille passuum" "mille_passuum" "millennia" "millennium" "millenniums" "milliarcsecond" "milliarcseconds" "milligal" "milligals")
    return true
  if s in ("millihelen" "millihelens" "millimolar" "mils" "min" "mina" "minas" "minute" "minutes" "mkat" "ml" "mlm")
    return true
  if s in ("mlx" "mm" "mmHg" "mmol" "mmol/L" "mmol/L glucose" "mmol/L_glucose" "mo" "mohs" "mol" "mol/L" "mol/mol")
    return true
  if s in ("mol/m³" "mol_photon/m²/s" "molal" "molar" "molar concentration" "molarity" "mole" "mole fraction" "moles" "moment" "moment magnitude" "moment_magnitude")
    return true
  if s in ("moments" "momentum" "momme" "mommes" "month" "months" "moon mass" "moonmass" "mpc" "mpg" "mpge" "mph")
    return true
  if s in ("ms" "mt" "mu" "muB" "muon mass" "muon_mass" "mus" "mvar" "m²" "m³" "m³/(kg·s²)" "m³/s")
    return true
  if s in ("mΩ" "mₚₗ" "nA" "nB" "nBps" "nBq" "nC" "nDa" "nF" "nGy" "nH" "nHz")
    return true
  if s in ("nJ" "nJy" "nK" "nL" "nM" "nN" "nPa" "nS" "nSv" "nT" "nV" "nVA")
    return true
  if s in ("nW" "nWb" "nail_cloth" "nanobarn" "nanobarns" "nanomolar" "nat" "nats" "nautical mile" "nautical miles" "nb" "nb-1")
    return true
  if s in ("nb^-1" "nbarn" "nbps" "nb⁻¹" "ncd" "ncentury" "neV" "nebuchadnezzar" "nebuchadnezzars" "neutron mass" "neutron_mass" "newton")
    return true
  if s in ("newtons" "newtons per meter" "nfortnight" "ng" "ng/mL" "nibble" "nibbles" "nit" "nits" "nkat" "nl" "nlm")
    return true
  if s in ("nlx" "nm" "nmi" "nmol" "nmol/L" "nominal solar luminosity" "nominal solar radius" "normality" "npc" "ns" "nt" "nvar")
    return true
  if s in ("nΩ" "o" "octave" "octaves" "octet" "octets" "oersted" "oersteds" "ohm" "ohm meter" "ohms" "oil barrel")
    return true
  if s in ("oil barrels" "oil_barrel" "omer" "omers" "onah" "onot" "op" "op/J" "operations per joule" "ops" "ops_per_s" "osmol")
    return true
  if s in ("osmolar" "osmole" "osmoles" "ounce" "ounces" "outhouse" "oz" "ozt" "pA" "pB" "pBps" "pBq")
    return true
  if s in ("pC" "pDa" "pF" "pGy" "pH" "pHz" "pJ" "pJy" "pK" "pL" "pN" "pPa")
    return true
  if s in ("pS" "pSv" "pT" "pV" "pVA" "pW" "pWb" "packet" "packets" "page" "pages" "paragraph")
    return true
  if s in ("paragraphs" "parsa" "parsec" "parsecs" "parts per billion" "parts per billion by volume" "parts per hundred million" "parts per million" "parts per million by mass" "parts per million by volume" "parts per trillion" "parts-per-billion")
    return true
  if s in ("parts-per-million" "parts-per-trillion" "pascal" "pascals" "passus" "passuses" "pb" "pb-1" "pb^-1" "pbarn" "pbps" "pb⁻¹")
    return true
  if s in ("pc" "pcd" "pcentury" "peV" "peanut butter" "peanutbutter" "peck" "pecks" "pedes" "pennyweight" "pennyweights" "perch")
    return true
  if s in ("perches" "person hour" "person hours" "person_hour" "pes" "petabyte" "petabytes" "petroleum barrel" "petroleum_barrel" "pfortnight" "pg" "phon")
    return true
  if s in ("phons" "phot" "photon" "photons" "photosynthetic photon flux density" "phots" "pica" "picas" "piccolo" "picobarn" "picobarns" "pied")
    return true
  if s in ("pied du roi" "pieds" "pieds du roi" "pieze" "pinch" "pinches" "pint" "pints" "pip" "pipe" "pipes" "pips")
    return true
  if s in ("pixel" "pixels" "pk" "pkat" "pl" "planck length" "planck mass" "planck time" "plaque forming unit" "plaque-forming unit" "plm" "plx")
    return true
  if s in ("pm" "pmol" "point" "points" "poise" "potential vorticity unit" "potential vorticity units" "pouce" "pouces" "pound" "pound force" "pound-force")
    return true
  if s in ("pounds" "ppb" "ppbv" "ppc" "pphm" "ppm" "ppmv" "ppmw" "pps" "ppt" "proton mass" "proton_mass")
    return true
  if s in ("ps" "psi" "pt" "pud" "puds" "puncheon" "puncheons" "pvar" "px" "pΩ" "qA" "qB")
    return true
  if s in ("qBps" "qBq" "qC" "qDa" "qF" "qGy" "qH" "qHz" "qJ" "qJy" "qK" "qL")
    return true
  if s in ("qN" "qPa" "qS" "qSv" "qT" "qV" "qVA" "qW" "qWb" "qb" "qbps" "qcd")
    return true
  if s in ("qcentury" "qeV" "qfortnight" "qg" "qkat" "ql" "qlm" "qlx" "qm" "qmol" "qpc" "qps")
    return true
  if s in ("qquad" "qr" "qs" "qt" "quad" "quality adjusted life year" "quality-adjusted life year" "quart" "quarter" "quarters" "quarts" "queries")
    return true
  if s in ("query" "quintal" "quintals" "qvar" "qword" "qwords" "qΩ" "rA" "rB" "rBps" "rBq" "rC")
    return true
  if s in ("rDa" "rF" "rGy" "rH" "rHz" "rJ" "rJy" "rK" "rL" "rN" "rPa" "rS")
    return true
  if s in ("rSv" "rT" "rV" "rVA" "rW" "rWb" "rack unit" "rack units" "rad" "rad/s" "rad/s²" "rad_dose")
    return true
  if s in ("radian" "radiance" "radians" "radiant exposure" "radiant intensity" "radiation absorbed dose" "rankine" "rankine difference" "rb" "rbe" "rbps" "rcd")
    return true
  if s in ("rcentury" "rd" "reV" "reactive power" "reaumur" "rega" "regaim" "rehoboam" "relative biological effectiveness" "rem" "rem_css" "rems")
    return true
  if s in ("request" "requests" "resistivity" "rev" "revolution" "revolutions" "revolutions per minute" "revs" "rfortnight" "rg" "ri" "richter")
    return true
  if s in ("richter scale" "rkat" "rl" "rlm" "rlx" "rm" "rmol" "rockwell" "rod" "rods" "roentgen" "roentgens")
    return true
  if s in ("roman libra" "roman mile" "roman uncia" "romer" "rope" "ropes" "rot" "rotation" "rotations" "rotations per minute" "royal cubit" "royal cubits")
    return true
  if s in ("royal_cubit" "rpc" "rpm" "rps" "rs" "rt" "rundlet" "rundlets" "russian funt" "russian_funt" "rutherford" "rutherfords")
    return true
  if s in ("rvar" "rydberg" "rydberg_unit" "rydbergs" "réaumur" "rømer" "rΩ" "s" "sabbath day's journey" "sabbatical" "saffir simpson" "saffir_simpson")
    return true
  if s in ("sagan" "sagans" "sample" "samples" "savart" "savarts" "sazhen" "sazhens" "sb" "score" "scores" "scruple")
    return true
  if s in ("scruples" "seah" "seahs" "second" "seconds" "sector" "sectors" "seer" "seers" "seim" "semitone" "semitones")
    return true
  if s in ("shaftment" "shaftments" "shake" "shakes" "shaku" "shakus" "shed" "shekalim" "shekel" "shekels" "shmita" "shmitas")
    return true
  if s in ("shmitta" "short ton" "short tons" "sidereal day" "sidereal days" "sidereal year" "sidereal years" "siderealday" "siderealyear" "siemens" "siemens per meter" "sievert")
    return true
  if s in ("sieverts" "sk" "skot" "skots" "slug" "slugs" "smidgen" "smidgens" "smoot" "smoots" "solar mass" "solar radius")
    return true
  if s in ("solarmass" "solarradius" "sone" "sones" "span" "spans" "specific energy" "specific heat capacity" "specific_energy" "spectral efficiency" "spectral flux density" "split")
    return true
  if s in ("splits" "sq ft" "sqft" "sqm" "square feet" "square foot" "sr" "st" "standard gravity" "statA" "statC" "statF")
    return true
  if s in ("statH" "statV" "statampere" "statcoulomb" "statfarad" "stathenry" "statohm" "statvolt" "statΩ" "steradian" "steradians" "stere")
    return true
  if s in ("stick" "stick of butter" "sticks" "sticks of butter" "stilb" "stilbs" "stokes" "stone" "stones" "stop" "stops" "story point")
    return true
  if s in ("story points" "story_point" "stère" "stères" "sun" "suns" "surface tension" "svedberg" "svedbergs" "sverdrup" "sverdrups" "symbol")
    return true
  if s in ("symbols" "synodic month" "synodic months" "t" "tablespoon" "tablespoons" "talent" "talents" "talmudic mil" "talmudic_mil" "tatami" "tatamis")
    return true
  if s in ("tbsp" "tce" "teaspoon" "teaspoons" "techum" "techum shabbat" "tefach" "tefachim" "tenth cent" "tenth_cent" "tertian" "tesla")
    return true
  if s in ("teslas" "tex" "texpt" "therm" "thermal conductivity" "thermochemical calorie" "thermochemical kilocalorie" "therms" "tick" "ticks" "tierce" "tierces")
    return true
  if s in ("tn" "toise" "toises" "tok" "tok/J" "tok/s" "token" "tokens" "tokens per joule" "tola" "tolas" "ton")
    return true
  if s in ("tonne" "tonne of coal equivalent" "tonnes" "tons" "torque" "torr" "torrs" "total electron content unit" "tps" "transaction" "transactions" "transfer")
    return true
  if s in ("transfers" "transport carbon intensity" "traversed edges per second" "tropical year" "tropical years" "tropicalyear" "troy ounce" "troy ounces" "troyounce" "tsp" "tsubo" "tsubos")
    return true
  if s in ("tun" "tuns" "turn" "turns" "txn" "tₚ" "u" "uA" "uB" "uBps" "uBq" "uC")
    return true
  if s in ("uDa" "uF" "uGy" "uH" "uHz" "uJ" "uJy" "uK" "uL" "uM" "uN" "uPa")
    return true
  if s in ("uS" "uSv" "uT" "uV" "uVA" "uW" "uWb" "uas" "ub" "ubps" "ucd" "ucentury")
    return true
  if s in ("ueV" "ufortnight" "ug" "ukat" "ul" "ulm" "ulx" "um" "umol" "uncia_roma" "upc" "update")
    return true
  if s in ("updates" "us" "ut" "uvar" "uΩ" "var" "vershok" "vershoks" "verst" "versts" "vh" "vickers")
    return true
  if s in ("viewport height" "viewport width" "volt" "volt ampere" "volt-ampere" "volts" "volts per meter" "volumetric flow" "vw" "warhol" "warhols" "water horsepower")
    return true
  if s in ("water_horsepower" "watt" "watts" "watts per square meter" "wavenumber" "weber" "webers" "wedgwood" "week" "weeks" "wk" "yA")
    return true
  if s in ("yB" "yBps" "yBq" "yC" "yDa" "yF" "yGy" "yH" "yHz" "yJ" "yJy" "yK")
    return true
  if s in ("yL" "yN" "yPa" "yS" "ySv" "yT" "yV" "yVA" "yW" "yWb" "yard" "yards")
    return true
  if s in ("yb" "ybps" "ycd" "ycentury" "yd" "yeV" "year" "years" "yfortnight" "yg" "ykat" "yl")
    return true
  if s in ("ylm" "ylx" "ym" "ymol" "yovel" "yovels" "ypc" "yr" "ys" "yt" "yvar" "yΩ")
    return true
  if s in ("zA" "zB" "zBps" "zBq" "zC" "zDa" "zF" "zGy" "zH" "zHz" "zJ" "zJy")
    return true
  if s in ("zK" "zL" "zN" "zPa" "zS" "zSv" "zT" "zV" "zVA" "zW" "zWb" "zb")
    return true
  if s in ("zbps" "zcd" "zcentury" "zeV" "zeret" "zfortnight" "zg" "zhang" "zhangs" "zkat" "zl" "zlm")
    return true
  if s in ("zlx" "zm" "zmol" "zpc" "zs" "zt" "zvar" "zΩ" "°" "°C" "°De" "°F")
    return true
  if s in ("°N" "°R" "°Ra" "°Re" "°Ré" "°Rø" "°W" "°r" "µA" "µB" "µBps" "µBq")
    return true
  if s in ("µC" "µDa" "µF" "µGy" "µH" "µHz" "µJ" "µJy" "µK" "µL" "µM" "µN")
    return true
  if s in ("µPa" "µS" "µSv" "µT" "µV" "µVA" "µW" "µWb" "µas" "µb" "µbps" "µcd")
    return true
  if s in ("µcentury" "µeV" "µfortnight" "µg" "µg/mL" "µkat" "µl" "µlm" "µlx" "µm" "µmol" "µmol/L")
    return true
  if s in ("µmol_photon/m²/s" "µpc" "µs" "µt" "µvar" "µΩ" "Å" "ångström" "ɡ" "ʒ" "ΔK" "Δ°C")
    return true
  if s in ("Δ°De" "Δ°F" "Δ°N" "Δ°R" "Δ°Ré" "Δ°Rø" "Δ°W" "Ω" "Ω·m" "α" "μA" "μB")
    return true
  if s in ("μBps" "μBq" "μC" "μDa" "μF" "μGy" "μH" "μHz" "μJ" "μJy" "μK" "μL")
    return true
  if s in ("μM" "μN" "μPa" "μS" "μSv" "μT" "μV" "μVA" "μW" "μWb" "μ_B" "μas")
    return true
  if s in ("μb" "μbps" "μcd" "μcentury" "μeV" "μfortnight" "μg" "μkat" "μl" "μlife" "μlm" "μlx")
    return true
  if s in ("μm" "μmol" "μmort" "μpc" "μs" "μt" "μvar" "μΩ" "℃" "℈" "℉" "ℓₚ")
    return true
  if s in ("℔" "℥" "℧" "㍳")
    return true
  false

# --- END GENERATED: known_unit_name ---
