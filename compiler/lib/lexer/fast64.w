## i64[]: lc, tokens, indents
## i64: count
-> tungsten_tokenize_fast64(lc, count, tokens, indents)
  pos = 0
  tc = 0
  data_ptr = ccall_nobox("w_array_data_ptr", lc)
  at_line_start = 1
  paren_depth = 0
  indent_top = 0
  indents[0] = 0

  cp_mask = 0x1FFFFF
  f_line_start = 0x1

  t_id           = 0x01 << 38
  t_name         = 0x02 << 38
  t_int          = 0x03 << 38
  t_decimal      = 0x04 << 38
  t_string       = 0x05 << 38
  t_symbol       = 0x06 << 38
  t_type_hint    = 0x07 << 38
  t_newline      = 0x08 << 38
  t_indent       = 0x09 << 38
  t_dedent       = 0x0A << 38
  t_op           = 0x0B << 38
  t_ivar         = 0x0C << 38
  t_cvar         = 0x0D << 38
  t_parg         = 0x0E << 38
  t_byte_array   = 0x0F << 38
  t_key          = 0x10 << 38
  t_color        = 0x11 << 38
  t_char         = 0x12 << 38
  t_codepoint    = 0x13 << 38
  t_word_array   = 0x14 << 38
  t_symbol_array = 0x15 << 38
  t_magic        = 0x16 << 38
  t_eof          = 0x17 << 38
  t_path         = 0x18 << 38
  t_sp           = 0x19 << 38
  # SCREAMING_SNAKE_CASE identifier: starts uppercase, no lowercase
  # ASCII letters. Distinguished from t_name (PascalCase) inline in
  # the chunker by tracking `has_lower` as identifier-extend bytes
  # are consumed.
  t_constant     = 0x1A << 38
  t_hyper_array  = 0x1B << 38
  t_decimal_array = 0x1C << 38
  t_float_array  = 0x1D << 38

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
      tokens[tc] = t_sp | (((pos - sp_start) & 0xFFF) << 26) | (sp_start << 2)
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
          tokens[tc] = t_magic | ((len & 0xFFF) << 26) | (pos << 2)
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
            tokens[tc] = t_codepoint | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
        tokens[tc] = t_magic | ((len & 0xFFF) << 26) | (start << 2)
      elsif c >= 65 && c <= 90
        # Uppercase first char: PascalCase iff later bytes include a
        # lowercase letter; otherwise SCREAMING_SNAKE_CASE constant.
        if has_lower != 0
          tokens[tc] = t_name | ((len & 0xFFF) << 26) | (start << 2)
        else
          tokens[tc] = t_constant | ((len & 0xFFF) << 26) | (start << 2)
      else
        tokens[tc] = t_id | ((len & 0xFFF) << 26) | (start << 2)
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
              tokens[tc] = t_path | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
        tokens[tc] = t_int | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
          tokens[tc] = t_int | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
        tokens[tc] = t_decimal | (((pos - start) & 0xFFF) << 26) | (start << 2)
        tc++
        next

      if match == 0 && is_float == 0 && pos + 1 < count && ((lc[pos] >> 18) & cp_mask) == :-/ && (lc[pos + 1] & 0x01) != 0
        pos++
        while pos < count && ((lc[pos] & 0x01) != 0 || ((lc[pos] >> 18) & cp_mask) == :-_)
          pos++
        tokens[tc] = t_int | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
          tokens[tc] = t_decimal | (((pos - start) & 0xFFF) << 26) | (start << 2)
          tc++
          next

      len = pos - start
      if is_float != 0
        tokens[tc] = t_decimal | ((len & 0xFFF) << 26) | (start << 2)
      else
        tokens[tc] = t_int | ((len & 0xFFF) << 26) | (start << 2)
      tc++

    when 0x02
      start = pos
      if c == 39
        # Keep the boxed helper result out of the raw scanner's offset state.
        phrase_end = ccall_nobox("w_numeric_to_i64", unit_apostrophe_phrase_end(lc, pos, count)) ## i64
        if phrase_end > pos
          # The number materializer owns this whole phrase. Emit a transport
          # chunk and leave the next newline/statement to the raw scanner.
          pos = phrase_end
          tokens[tc] = t_id | (((pos - start) & 0xFFF) << 26) | (start << 2)
          tc++
          next
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
        tokens[tc] = t_string | (((pos - start) & 0xFFF) << 26) | (start << 2)
      else
        # A single quote has no escape or interpolation semantics, so one
        # SIMD-friendly scan finds the terminator. Materialization separately
        # rejects any non-ASCII codepoint in the body.
        pos = ccall_nobox("w_lex64_scan_to_cp", data_ptr, count, pos, :-\')
        if pos < count
          pos++
        tokens[tc] = t_string | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
          # Line-initial `##` is a standalone hint/comment line: it never
          # carries a `= initializer` (that form is the trailing
          # `x ## T = 0` ascription), so it scans to EOL. Stopping at `=`
          # here would strand the rest of a prose comment as live tokens
          # (`## squaring: q² = ...` broke the whole file).
          hint_bol = tc == 0
          if !hint_bol
            prev_tt = tokens[tc - 1] >> 38
            if prev_tt == 0x08 || prev_tt == 0x09 || prev_tt == 0x0A
              hint_bol = true
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
            # A `=` ends the hint at ANY depth: `x ## i64 = 0` is a typed
            # ASSIGNMENT — hint on the target; the `=` and initializer lex
            # normally and the parser folds them into Assign#type_hint. No
            # legitimate hint text contains `=` (before this rule the
            # whole-line scan swallowed `= 0` into the hint text, leaving
            # the var undeclared — silent nil reads compiled, "Undefined
            # variable" interpreted).
            elsif cp_here == :-= && !hint_bol
              break
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
          tokens[tc] = t_type_hint | (((pos - start) & 0xFFF) << 26) | (start << 2)
          tc++
          next
        if pos + 1 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-[
          pos += 2
          start = pos
          while pos < count && ((lc[pos] >> 18) & cp_mask) != :-]
            pos++
          if pos < count
            pos++
          tokens[tc] = t_key | (((pos - start) & 0xFFF) << 26) | (start << 2)
          tc++
          next
        if pos + 1 < count && (lc[pos + 1] & 0x08) != 0
          pos += 1
          while pos < count && (lc[pos] & 0x08) != 0
            pos++
          len = pos - start - 1
          if len == 3 || len == 4 || len == 6 || len == 8
            tokens[tc] = t_color | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
            tokens[tc] = t_char | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
                tokens[tc] = t_symbol | (((pos - start) & 0xFFF) << 26) | (start << 2)
                tc++
                next
              if op == :-< && c2 == :-= && c3 == :->
                pos += 2
                tokens[tc] = t_symbol | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
            tokens[tc] = t_symbol | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
          tokens[tc] = t_symbol | (((pos - start) & 0xFFF) << 26) | (start << 2)
          tc++
          next
        if pos + 1 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-[
          pos += 2
          if pos < count && ((lc[pos] >> 18) & cp_mask) == :-]
            pos++
            if pos < count && ((lc[pos] >> 18) & cp_mask) == :-=
              pos++
            tokens[tc] = t_symbol | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
            tokens[tc] = t_word_array | (((pos - start) & 0xFFF) << 26) | (start << 2)
          elsif c2 == :-i
            tokens[tc] = t_symbol_array | (((pos - start) & 0xFFF) << 26) | (start << 2)
          else
            tokens[tc] = t_decimal_array | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
          tokens[tc] = t_hyper_array | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
          tokens[tc] = t_float_array | (((pos - start) & 0xFFF) << 26) | (start << 2)
          tc++
          next

      if c == :-- && pos + 3 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-> && ((lc[pos + 2] >> 18) & cp_mask) == :-/
        c2 = (lc[pos + 3] >> 18) & cp_mask
        if c2 == :-* || c2 == :-&
          pos += 4
          tokens[tc] = t_op | (((pos - start) & 0xFFF) << 26) | (start << 2)
          tc++
          next
        if (lc[pos + 3] & 0x01) != 0
          pos += 3
          while pos < count && (lc[pos] & 0x01) != 0
            pos++
          tokens[tc] = t_op | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
            tokens[tc] = t_decimal | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
        tokens[tc] = t_string | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
          # Superscript digits (² ³ ¹ and ⁰…⁹) end a value — `a²/b` and
          # `W/m²/Hz` divide; without them the slash opened a phantom regex
          # that swallowed through the next `/` on the line (even inside a
          # later string literal).
          if (lc[prev_pos] & 0x20) != 0 || (lc[prev_pos] & 0x01) != 0 || (c2 >= 65 && c2 <= 90) || c2 == :-) || c2 == :-] || c2 == :-} || c2 == :-\" || c2 == :-\' || c2 == :-? || c2 == :-! || c2 == 0xBB || c2 == 0xB2 || c2 == 0xB3 || c2 == 0xB9 || (c2 >= 0x2070 && c2 <= 0x2079)
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
                    tokens[tc] = t_string | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
          # Dot-prefix elementwise operators: `.+ .- .* ./
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

      tokens[tc] = t_op | (((pos - start) & 0xFFF) << 26) | (start << 2)
      tc++

    else
      start = pos
      case c
      when :-U
        if pos + 2 < count && ((lc[pos + 1] >> 18) & cp_mask) == :-+ && (lc[pos + 2] & 0x08) != 0
          pos += 2
          while pos < count && (lc[pos] & 0x08) != 0
            pos++
          tokens[tc] = t_codepoint | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
            tokens[tc] = t_name | (((pos - start) & 0xFFF) << 26) | (start << 2)
          else
            tokens[tc] = t_constant | (((pos - start) & 0xFFF) << 26) | (start << 2)
        tc++
      when :-@
        pos++
        if pos < count && ((lc[pos] >> 18) & cp_mask) == :-@ && pos + 1 < count && (lc[pos + 1] & 0x40) != 0
          pos++
          while pos < count && (lc[pos] & 0x20) != 0
            pos++
          tokens[tc] = t_cvar | (((pos - start) & 0xFFF) << 26) | (start << 2)
        elsif pos < count && (lc[pos] & 0x01) != 0
          while pos < count && (lc[pos] & 0x01) != 0
            pos++
          tokens[tc] = t_parg | (((pos - start) & 0xFFF) << 26) | (start << 2)
        elsif pos < count && (lc[pos] & 0x40) != 0
          while pos < count && (lc[pos] & 0x20) != 0
            pos++
          tokens[tc] = t_ivar | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
          tokens[tc] = t_decimal | (((pos - start) & 0xFFF) << 26) | (start << 2)
        elsif pos + 1 < count && (lc[pos + 1] & 0x40) != 0
          pos += 1
          while pos < count && (lc[pos] & 0x20) != 0
            pos++
          tokens[tc] = t_id | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
        tokens[tc] = t_byte_array | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
            tokens[tc] = t_name | (((pos - start) & 0xFFF) << 26) | (start << 2)
          else
            tokens[tc] = t_constant | (((pos - start) & 0xFFF) << 26) | (start << 2)
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
