# Alternate Tungsten lexer spike: 32-bit LexChar input, WToken32 output.
#
# WToken32 packs type/offset/flags into a u32 and stores token length in a
# parallel u8[]:
#
#   bits 31..8  offset  24 bits
#   bits 7..2   type     6 bits
#   bits 1..0   flags    2 bits
#
# Lengths are stored in lengths[tc]. This keeps the hot token cell to one
# compact 32-bit store plus one byte store.

## u32[]: lc, tokens
## u8[]: lengths
## i64[]: indents
## i64: count
-> tungsten_tokenize_wtoken32(lc, count, tokens, lengths, indents)
  pos = 0
  tc = 0
  at_line_start = 1
  paren_depth = 0
  indent_top = 0
  indents[0] = 0
  data_ptr = ccall_nobox("w_typed_array_data_ptr", lc)

  cp_mask = 0x1FFFFF
  f_sp_before = 0x1
  f_sp_after = 0x2

  t_id           = (0x01 << 2)
  t_name         = (0x02 << 2)
  t_int          = (0x03 << 2)
  t_decimal      = (0x04 << 2)
  t_string       = (0x05 << 2)
  t_symbol       = (0x06 << 2)
  t_type_hint    = (0x07 << 2)
  t_newline      = (0x08 << 2)
  t_indent       = (0x09 << 2)
  t_dedent       = (0x0A << 2)
  t_op           = (0x0B << 2)
  t_ivar         = (0x0C << 2)
  t_cvar         = (0x0D << 2)
  t_parg         = (0x0E << 2)
  t_byte_array   = (0x0F << 2)
  t_key          = (0x10 << 2)
  t_color        = (0x11 << 2)
  t_char         = (0x12 << 2)
  t_codepoint    = (0x13 << 2)
  t_word_array   = (0x14 << 2)
  t_symbol_array = (0x15 << 2)
  t_magic        = (0x16 << 2)
  t_eof          = (0x17 << 2)
  t_path         = (0x18 << 2)

  loop
    if pos >= count
      break

    if at_line_start != 0
      at_line_start = 0
      indent = 0
      while pos < count
        c = (lc[pos] >> 11) & cp_mask
        if c == 32 || c == 9
          indent++
          pos++
        else
          break

      if pos >= count
        break

      c = (lc[pos] >> 11) & cp_mask
      if c == 10 || c == 13
        pos++
        if c == 13 && pos < count && ((lc[pos] >> 11) & cp_mask) == 10
          pos++
        at_line_start = 1
        next

      if c == :-# && pos + 1 < count && ((lc[pos + 1] >> 11) & cp_mask) == :-!
        pos = ccall_nobox("w_lex32_scan_until_flag", data_ptr, count, pos, 0x80)
        if pos < count
          pos++
        match = 0
        if pos + 4 < count
          c = (lc[pos] >> 11) & cp_mask
          c2 = (lc[pos + 1] >> 11) & cp_mask
          c3 = (lc[pos + 2] >> 11) & cp_mask
          c4 = (lc[pos + 3] >> 11) & cp_mask
          c5 = (lc[pos + 4] >> 11) & cp_mask
          if c == :-e && c2 == :-x && c3 == :-e && c4 == :-c && c5 == 32
            match = 1
        if match != 0
          pos = ccall_nobox("w_lex32_scan_until_flag", data_ptr, count, pos, 0x80)
          if pos < count
            pos++
        at_line_start = 1
        next

      if c == :-# && !(pos + 1 < count && ((lc[pos + 1] >> 11) & cp_mask) == :-#)
        pos = ccall_nobox("w_lex32_scan_until_flag", data_ptr, count, pos, 0x80)
        if pos < count
          pos++
        at_line_start = 1
        next

      if paren_depth == 0
        current_indent = indents[indent_top]
        if indent > current_indent
          indent_top++
          indents[indent_top] = indent
          tokens[tc] = t_indent | (pos << 8)
          lengths[tc] = 0
          tc++
        elsif indent < current_indent
          while indent_top > 0 && indents[indent_top] > indent
            indent_top -= 1
            tokens[tc] = t_dedent | (pos << 8)
            lengths[tc] = 0
            tc++

    v = lc[pos]
    c = (v >> 11) & cp_mask

    case v & 0xD7
    when 0x10
      pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x10)

    when 0x80
      if paren_depth == 0
        tokens[tc] = t_newline | (pos << 8)
        lengths[tc] = 1
        tc++
      pos++
      if c == 13 && pos < count && ((lc[pos] >> 11) & cp_mask) == 10
        pos++
      at_line_start = 1

    when 0x40
      start = pos

      # Magic constants start with "_" but contain uppercase letters, which
      # are intentionally not ID_CONTINUE in the Tungsten flag table.
      if c == :-_ && pos + 6 < count && ((lc[pos + 1] >> 11) & cp_mask) == :-_
        match = 0
        len = 0
        if pos + 7 < count
          c2 = (lc[pos + 2] >> 11) & cp_mask
          c3 = (lc[pos + 3] >> 11) & cp_mask
          if c2 == :-F && c3 == :-I
            if ((lc[pos + 4] >> 11) & cp_mask) == :-L
              if ((lc[pos + 5] >> 11) & cp_mask) == :-E
                if ((lc[pos + 6] >> 11) & cp_mask) == :-_
                  if ((lc[pos + 7] >> 11) & cp_mask) == :-_
                    match = 1
                    len = 8
          elsif c2 == :-L && c3 == :-I
            if ((lc[pos + 4] >> 11) & cp_mask) == :-N
              if ((lc[pos + 5] >> 11) & cp_mask) == :-E
                if ((lc[pos + 6] >> 11) & cp_mask) == :-_
                  if ((lc[pos + 7] >> 11) & cp_mask) == :-_
                    match = 1
                    len = 8
        if match == 0 && pos + 6 < count
          c2 = (lc[pos + 2] >> 11) & cp_mask
          c3 = (lc[pos + 3] >> 11) & cp_mask
          if c2 == :-D && c3 == :-I
            if ((lc[pos + 4] >> 11) & cp_mask) == :-R
              if ((lc[pos + 5] >> 11) & cp_mask) == :-_
                if ((lc[pos + 6] >> 11) & cp_mask) == :-_
                  match = 1
                  len = 7
        if match != 0
          tokens[tc] = t_magic | (pos << 8)
          out_len = len
          if out_len > 255
            out_len = 255
          lengths[tc] = out_len
          tc++
          pos += len
          next

      if c == :-U && pos + 2 < count
        if ((lc[pos + 1] >> 11) & cp_mask) == :-+
          if (lc[pos + 2] & 0x08) != 0
            pos += 2
            pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x08)
            tokens[tc] = t_codepoint | (start << 8)
            out_len = pos - start
            if out_len > 255
              out_len = 255
            lengths[tc] = out_len
            tc++
            next

      pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x20)

      if pos < count
        c2 = (lc[pos] >> 11) & cp_mask
        if c2 == :-? || c2 == :-!
          pos++
      if pos < count && ((lc[pos] >> 11) & cp_mask) == :-/
        if pos + 1 < count
          c2 = (lc[pos + 1] >> 11) & cp_mask
          if c2 == :-* || c2 == :-&
            pos += 2
          elsif (lc[pos + 1] & 0x01) != 0
            pos += 1
            pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x01)

      len = pos - start
      match = 0
      if len == 8
        if ((lc[start] >> 11) & cp_mask) == :-_
          if ((lc[start + 1] >> 11) & cp_mask) == :-_
            if ((lc[start + 6] >> 11) & cp_mask) == :-_
              if ((lc[start + 7] >> 11) & cp_mask) == :-_
                match = 1
      if match != 0
        tokens[tc] = t_magic | (start << 8)
        out_len = len
        if out_len > 255
          out_len = 255
        lengths[tc] = out_len
      elsif c >= 65 && c <= 90
        tokens[tc] = t_name | (start << 8)
        out_len = len
        if out_len > 255
          out_len = 255
        lengths[tc] = out_len
      else
        tokens[tc] = t_id | (start << 8)
        out_len = len
        if out_len > 255
          out_len = 255
        lengths[tc] = out_len
      tc++

      match = 0
      if len == 3
        if ((lc[start] >> 11) & cp_mask) == :-u
          if ((lc[start + 1] >> 11) & cp_mask) == :-s
            if ((lc[start + 2] >> 11) & cp_mask) == :-e
              match = 1
      if match != 0
        use_statement = 0
        prev_pos = start - 1
        while prev_pos >= 0
          c2 = (lc[prev_pos] >> 11) & cp_mask
          if c2 == 32 || c2 == 9
            prev_pos -= 1
          else
            break
        if prev_pos < 0
          use_statement = 1
        else
          c2 = (lc[prev_pos] >> 11) & cp_mask
          if c2 == 10 || c2 == 13 || c2 == :-;
            use_statement = 1
        if use_statement != 0
          while pos < count
            c2 = (lc[pos] >> 11) & cp_mask
            if c2 == 32 || c2 == 9
              pos++
            else
              break
          if pos < count && ((lc[pos] >> 11) & cp_mask) != :-\"
            start = pos
            while pos < count
              c2 = (lc[pos] >> 11) & cp_mask
              if c2 == 32 || c2 == 9 || c2 == 10 || c2 == 13 || c2 == :-; || c2 == :-#
                break
              pos++
            if pos > start
              tokens[tc] = t_path | (start << 8)
              out_len = pos - start
              if out_len > 255
                out_len = 255
              lengths[tc] = out_len
              tc++

    when 0x01
      start = pos
      is_float = 0
      match = 0
      if c == :-0 && pos + 1 < count
        c2 = (lc[pos + 1] >> 11) & cp_mask
        if c2 == :-x || c2 == :-X
          match = 1
          pos += 2
          loop
            if pos >= count
              break
            c2 = (lc[pos] >> 11) & cp_mask
            if (lc[pos] & 0x08) != 0 || c2 == :-_
              pos++
            else
              break
        elsif c2 == :-b || c2 == :-B
          match = 1
          pos += 2
          while pos < count
            c2 = (lc[pos] >> 11) & cp_mask
            if c2 == :-0 || c2 == :-1 || c2 == :-_
              pos++
            else
              break
        elsif c2 == :-o || c2 == :-O
          match = 1
          pos += 2
          while pos < count
            c2 = (lc[pos] >> 11) & cp_mask
            if (c2 >= 48 && c2 <= 55) || c2 == :-_
              pos++
            else
              break
        else
          pos++
          while pos < count && ((lc[pos] & 0x01) != 0 || ((lc[pos] >> 11) & cp_mask) == :-_)
            pos++
      else
        pos++
        while pos < count && ((lc[pos] & 0x01) != 0 || ((lc[pos] >> 11) & cp_mask) == :-_)
          pos++

      if match == 0 && pos == start + 4 && pos + 2 < count && ((lc[pos] >> 11) & cp_mask) == :-- && (lc[pos + 1] & 0x01) != 0 && (lc[pos + 2] & 0x01) != 0
        if pos + 5 < count && ((lc[pos + 3] >> 11) & cp_mask) == :-- && (lc[pos + 4] & 0x01) != 0 && (lc[pos + 5] & 0x01) != 0
          pos += 6
        else
          pos += 3
        tokens[tc] = t_int | (start << 8)
        out_len = pos - start
        if out_len > 255
          out_len = 255
        lengths[tc] = out_len
        tc++
        next

      if match == 0 && pos + 1 < count && ((lc[pos] >> 11) & cp_mask) == :-. && (lc[pos + 1] & 0x01) != 0
        len = pos
        c4 = 0
        match = 1
        while c4 < 3
          if len >= count || ((lc[len] >> 11) & cp_mask) != :-.
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
          if len < count && ((lc[len] >> 11) & cp_mask) == :-. && len + 1 < count && (lc[len + 1] & 0x01) != 0
            match = 0
        if match != 0
          if len + 1 < count && ((lc[len] >> 11) & cp_mask) == :-/ && (lc[len + 1] & 0x01) != 0
            len++
            while len < count && (lc[len] & 0x01) != 0
              len++
          pos = len
          tokens[tc] = t_int | (start << 8)
          out_len = pos - start
          if out_len > 255
            out_len = 255
          lengths[tc] = out_len
          tc++
          next
        match = 0

      if match == 0 && pos + 1 < count && ((lc[pos] >> 11) & cp_mask) == :-. && (lc[pos + 1] & 0x01) != 0
        pos++
        is_float = 1
        while pos < count && ((lc[pos] & 0x01) != 0 || ((lc[pos] >> 11) & cp_mask) == :-_)
          pos++

      if match == 0 && pos < count
        c2 = (lc[pos] >> 11) & cp_mask
        if c2 == :-e || c2 == :-E
          c3 = 0
          if pos + 1 < count
            c3 = (lc[pos + 1] >> 11) & cp_mask
          match = 0
          if pos + 1 < count && (lc[pos + 1] & 0x01) != 0
            match = 1
          elsif pos + 2 < count && (c3 == :-+ || c3 == :--) && (lc[pos + 2] & 0x01) != 0
            match = 1
          if match != 0
            pos++
            is_float = 1
            if pos < count
              c3 = (lc[pos] >> 11) & cp_mask
              if c3 == :-+ || c3 == :--
                pos++
            pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x01)

      if match == 0 && pos < count && ((lc[pos] >> 11) & cp_mask) == :-%
        pos++
        tokens[tc] = t_decimal | (start << 8)
        out_len = pos - start
        if out_len > 255
          out_len = 255
        lengths[tc] = out_len
        tc++
        next

      if match == 0 && is_float == 0 && pos + 1 < count && ((lc[pos] >> 11) & cp_mask) == :-/ && (lc[pos + 1] & 0x01) != 0
        pos++
        while pos < count && ((lc[pos] & 0x01) != 0 || ((lc[pos] >> 11) & cp_mask) == :-_)
          pos++
        tokens[tc] = t_int | (start << 8)
        out_len = pos - start
        if out_len > 255
          out_len = 255
        lengths[tc] = out_len
        tc++
        next

      if match == 0 && pos < count
        c2 = (lc[pos] >> 11) & cp_mask
        if (lc[pos] & 0x40) != 0 || (c2 >= 65 && c2 <= 90)
          pos++
          while pos < count
            c2 = (lc[pos] >> 11) & cp_mask
            if (lc[pos] & 0x40) != 0 || (c2 >= 65 && c2 <= 90) || (lc[pos] & 0x01) != 0 || c2 == :-/
              pos++
            else
              break
          tokens[tc] = t_decimal | (start << 8)
          out_len = pos - start
          if out_len > 255
            out_len = 255
          lengths[tc] = out_len
          tc++
          next

      len = pos - start
      if is_float != 0
        tokens[tc] = t_decimal | (start << 8)
        out_len = len
        if out_len > 255
          out_len = 255
        lengths[tc] = out_len
      else
        tokens[tc] = t_int | (start << 8)
        out_len = len
        if out_len > 255
          out_len = 255
        lengths[tc] = out_len
      tc++

    when 0x02
      start = pos
      pos++
      if c == :-\"
        loop
          if pos >= count
            break
          c2 = (lc[pos] >> 11) & cp_mask
          if c2 == :-\\
            if pos + 2 < count && ((lc[pos + 1] >> 11) & cp_mask) == :-e && ((lc[pos + 2] >> 11) & cp_mask) == :-[
              pos += 3
            else
              pos += 2
          elsif c2 == :-\"
            pos++
            break
          elsif c2 == :-[ && pos + 1 < count && ((lc[pos + 1] >> 11) & cp_mask) != :-]
            pos++
            depth = 1
            while pos < count && depth > 0
              c2 = (lc[pos] >> 11) & cp_mask
              if c2 == :-[
                depth++
              elsif c2 == :-]
                depth -= 1
              pos++
          else
            pos++
        tokens[tc] = t_string | (start << 8)
        out_len = pos - start
        if out_len > 255
          out_len = 255
        lengths[tc] = out_len
      else
        loop
          if pos >= count
            break
          pos = ccall_nobox("w_lex32_scan_to_cp_or", data_ptr, count, pos, :-\', :-\\)
          if pos >= count
            break
          c2 = (lc[pos] >> 11) & cp_mask
          if c2 == :-\\
            pos += 2
          elsif c2 == :-\'
            pos++
            break
        tokens[tc] = t_string | (start << 8)
        out_len = pos - start
        if out_len > 255
          out_len = 255
        lengths[tc] = out_len
      tc++

    when 0x04
      start = pos

      if c == :-#
        if pos + 1 < count && ((lc[pos + 1] >> 11) & cp_mask) == :-#
          pos += 2
          while pos < count
            c2 = (lc[pos] >> 11) & cp_mask
            if c2 == 32 || c2 == 9
              pos++
            else
              break
          start = pos
          pos = ccall_nobox("w_lex32_scan_until_flag", data_ptr, count, pos, 0x80)
          tokens[tc] = t_type_hint | (start << 8)
          out_len = pos - start
          if out_len > 255
            out_len = 255
          lengths[tc] = out_len
          tc++
          next
        if pos + 1 < count && ((lc[pos + 1] >> 11) & cp_mask) == :-[
          pos += 2
          start = pos
          while pos < count && ((lc[pos] >> 11) & cp_mask) != :-]
            pos++
          if pos < count
            pos++
          tokens[tc] = t_key | (start << 8)
          out_len = pos - start
          if out_len > 255
            out_len = 255
          lengths[tc] = out_len
          tc++
          next
        if pos + 1 < count && (lc[pos + 1] & 0x08) != 0
          pos += 1
          pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x08)
          len = pos - start - 1
          if len == 3 || len == 4 || len == 6 || len == 8
            tokens[tc] = t_color | (start << 8)
            out_len = pos - start
            if out_len > 255
              out_len = 255
            lengths[tc] = out_len
            tc++
            next
        pos = start + 1
        pos = ccall_nobox("w_lex32_scan_until_flag", data_ptr, count, pos, 0x80)
        next

      if c == :-:
        if pos + 2 < count && ((lc[pos + 1] >> 11) & cp_mask) == :--
          c2 = (lc[pos + 2] >> 11) & cp_mask
          if c2 != 32 && c2 != 9 && c2 != 10 && c2 != 13
            pos += 3
            if c2 == :-\\ && pos < count
              pos++
            tokens[tc] = t_char | (start << 8)
            out_len = pos - start
            if out_len > 255
              out_len = 255
            lengths[tc] = out_len
            tc++
            next
        if pos + 1 < count
          c2 = (lc[pos + 1] >> 11) & cp_mask
          if c2 == :-+ || c2 == :-- || c2 == :-* || c2 == :-/ || c2 == :-~ || c2 == :-! || c2 == :-% || c2 == :-^ || c2 == :-& || c2 == :-< || c2 == :-> || c2 == :-| || c2 == :-=
            op = c2
            pos += 2
            if pos + 1 < count
              c2 = (lc[pos] >> 11) & cp_mask
              c3 = (lc[pos + 1] >> 11) & cp_mask
              if op == :-= && c2 == :-= && c3 == :-=
                pos += 2
                tokens[tc] = t_symbol | (start << 8)
                out_len = pos - start
                if out_len > 255
                  out_len = 255
                lengths[tc] = out_len
                tc++
                next
              if op == :-< && c2 == :-= && c3 == :->
                pos += 2
                tokens[tc] = t_symbol | (start << 8)
                out_len = pos - start
                if out_len > 255
                  out_len = 255
                lengths[tc] = out_len
                tc++
                next
            if pos < count
              c2 = (lc[pos] >> 11) & cp_mask
              match = 0
              if op == :-= && (c2 == :-= || c2 == :-~)
                match = 1
              elsif op == :-< && (c2 == :-= || c2 == :-<)
                match = 1
              elsif op == :-> && (c2 == :-= || c2 == :->)
                match = 1
              elsif op == :-* && c2 == :-*
                match = 1
              elsif (op == :-+ || op == :-- || op == :-~ || op == :-!) && c2 == :-@
                match = 1
              if match != 0
                pos++
            tokens[tc] = t_symbol | (start << 8)
            out_len = pos - start
            if out_len > 255
              out_len = 255
            lengths[tc] = out_len
            tc++
            next
        if pos + 1 < count
          c2 = (lc[pos + 1] >> 11) & cp_mask
        if pos + 1 < count && ((lc[pos + 1] & 0x40) != 0 || (c2 >= 65 && c2 <= 90))
          pos += 1
          if (lc[pos] & 0x20) != 0
            pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x20)
          else
            pos++
            while pos < count
              c2 = (lc[pos] >> 11) & cp_mask
              if (lc[pos] & 0x20) != 0 || (c2 >= 65 && c2 <= 90)
                pos++
              else
                break
          if pos < count
            c2 = (lc[pos] >> 11) & cp_mask
            if c2 == :-? || c2 == :-!
              pos++
          if pos < count && ((lc[pos] >> 11) & cp_mask) == :-/
            if pos + 1 < count
              c2 = (lc[pos + 1] >> 11) & cp_mask
              if c2 == :-* || c2 == :-&
                pos += 2
              elsif (lc[pos + 1] & 0x01) != 0
                pos += 1
                pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x01)
          tokens[tc] = t_symbol | (start << 8)
          out_len = pos - start
          if out_len > 255
            out_len = 255
          lengths[tc] = out_len
          tc++
          next
        if pos + 1 < count && ((lc[pos + 1] >> 11) & cp_mask) == :-[
          pos += 2
          if pos < count && ((lc[pos] >> 11) & cp_mask) == :-]
            pos++
            if pos < count && ((lc[pos] >> 11) & cp_mask) == :-=
              pos++
            tokens[tc] = t_symbol | (start << 8)
            out_len = pos - start
            if out_len > 255
              out_len = 255
            lengths[tc] = out_len
            tc++
            next

      if c == :-% && pos + 2 < count
        c2 = (lc[pos + 1] >> 11) & cp_mask
        c3 = (lc[pos + 2] >> 11) & cp_mask
        if (c2 == :-w || c2 == :-i) && c3 == :-[
          pos += 3
          while pos < count && ((lc[pos] >> 11) & cp_mask) != :-]
            pos++
          if pos < count
            pos++
          if c2 == :-w
            tokens[tc] = t_word_array | (start << 8)
            out_len = pos - start
            if out_len > 255
              out_len = 255
            lengths[tc] = out_len
          else
            tokens[tc] = t_symbol_array | (start << 8)
            out_len = pos - start
            if out_len > 255
              out_len = 255
            lengths[tc] = out_len
          tc++
          next

      if c == :-- && pos + 3 < count && ((lc[pos + 1] >> 11) & cp_mask) == :-> && ((lc[pos + 2] >> 11) & cp_mask) == :-/
        c2 = (lc[pos + 3] >> 11) & cp_mask
        if c2 == :-* || c2 == :-&
          pos += 4
          tokens[tc] = t_op | (start << 8)
          out_len = pos - start
          if out_len > 255
            out_len = 255
          lengths[tc] = out_len
          tc++
          next
        if (lc[pos + 3] & 0x01) != 0
          pos += 3
          while pos < count && (lc[pos] & 0x01) != 0
            pos++
          tokens[tc] = t_op | (start << 8)
          out_len = pos - start
          if out_len > 255
            out_len = 255
          lengths[tc] = out_len
          tc++
          next

      if c == :-~
        scan = pos + 1
        if scan < count
          c2 = (lc[scan] >> 11) & cp_mask
          if (c2 == :-+ || c2 == :--) && scan + 1 < count && (lc[scan + 1] & 0x01) != 0
            scan++
          if scan < count && (lc[scan] & 0x01) != 0
            scan++
            while scan < count && ((lc[scan] & 0x01) != 0 || ((lc[scan] >> 11) & cp_mask) == :-_)
              scan++
            if scan + 1 < count && ((lc[scan] >> 11) & cp_mask) == :-. && (lc[scan + 1] & 0x01) != 0
              scan++
              while scan < count && ((lc[scan] & 0x01) != 0 || ((lc[scan] >> 11) & cp_mask) == :-_)
                scan++
            if scan < count
              c2 = (lc[scan] >> 11) & cp_mask
              if c2 == :-e || c2 == :-E
                exp_pos = scan + 1
                if exp_pos < count
                  c3 = (lc[exp_pos] >> 11) & cp_mask
                  if c3 == :-+ || c3 == :--
                    exp_pos++
                if exp_pos < count && (lc[exp_pos] & 0x01) != 0
                  scan = exp_pos + 1
                  while scan < count && (lc[scan] & 0x01) != 0
                    scan++
            pos = scan
            tokens[tc] = t_decimal | (start << 8)
            out_len = pos - start
            if out_len > 255
              out_len = 255
            lengths[tc] = out_len
            tc++
            next

      if c == :-< && pos + 2 < count && ((lc[pos + 1] >> 11) & cp_mask) == :-< && ((lc[pos + 2] >> 11) & cp_mask) == :-~
        pos += 3
        while pos < count
          c2 = (lc[pos] >> 11) & cp_mask
          if c2 == 32 || c2 == 9
            pos++
          else
            break
        delim_start = pos
        while pos < count
          c2 = (lc[pos] >> 11) & cp_mask
          if (lc[pos] & 0x20) != 0 || (c2 >= 65 && c2 <= 90)
            pos++
          else
            break
        delim_len = pos - delim_start
        while pos < count
          c2 = (lc[pos] >> 11) & cp_mask
          if c2 == 10 || c2 == 13
            break
          pos++
        if pos < count
          c2 = (lc[pos] >> 11) & cp_mask
          pos++
          if c2 == 13 && pos < count && ((lc[pos] >> 11) & cp_mask) == 10
            pos++
        found = 0
        while pos < count && found == 0
          line_pos = pos
          while line_pos < count
            c2 = (lc[line_pos] >> 11) & cp_mask
            if c2 == 32 || c2 == 9
              line_pos++
            else
              break
          match = 0
          if delim_len > 0 && line_pos + delim_len <= count
            match = 1
            di = 0
            while di < delim_len
              if ((lc[line_pos + di] >> 11) & cp_mask) != ((lc[delim_start + di] >> 11) & cp_mask)
                match = 0
                break
              di++
          if match != 0
            after = line_pos + delim_len
            if after < count
              c2 = (lc[after] >> 11) & cp_mask
              if c2 != 10 && c2 != 13 && c2 != 32 && c2 != 9
                match = 0
          if match != 0
            pos = after
            while pos < count
              c2 = (lc[pos] >> 11) & cp_mask
              if c2 == 32 || c2 == 9
                pos++
              else
                break
            found = 1
          else
            while pos < count
              c2 = (lc[pos] >> 11) & cp_mask
              if c2 == 10 || c2 == 13
                break
              pos++
            if pos < count
              c2 = (lc[pos] >> 11) & cp_mask
              pos++
              if c2 == 13 && pos < count && ((lc[pos] >> 11) & cp_mask) == 10
                pos++
        tokens[tc] = t_string | (start << 8)
        out_len = pos - start
        if out_len > 255
          out_len = 255
        lengths[tc] = out_len
        tc++
        next

      if c == :-/
        regex_context = 1
        prev_pos = start - 1
        while prev_pos >= 0
          c2 = (lc[prev_pos] >> 11) & cp_mask
          if c2 == 32 || c2 == 9
            prev_pos -= 1
          else
            break
        if prev_pos >= 0
          c2 = (lc[prev_pos] >> 11) & cp_mask
          if (lc[prev_pos] & 0x20) != 0 || (lc[prev_pos] & 0x01) != 0 || c2 == :-) || c2 == :-] || c2 == :-} || c2 == :-\" || c2 == :-\' || c2 == :-? || c2 == :-! || c2 == 0xBB
            regex_context = 0
        if regex_context != 0 && pos + 1 < count
          c2 = (lc[pos + 1] >> 11) & cp_mask
          if c2 != :-/ && c2 != :-=
            scan = pos + 1
            escaped = 0
            in_class = 0
            found = 0
            while scan < count && found == 0
              c2 = (lc[scan] >> 11) & cp_mask
              if c2 == 10 || c2 == 13
                break
              if escaped != 0
                escaped = 0
              elsif c2 == :-\\
                escaped = 1
              elsif c2 == :-[
                in_class = 1
              elsif c2 == :-]
                in_class = 0
              elsif c2 == :-/ && in_class == 0
                scan++
                while scan < count && (lc[scan] & 0x20) != 0
                  scan++
                pos = scan
                tokens[tc] = t_string | (start << 8)
                out_len = pos - start
                if out_len > 255
                  out_len = 255
                lengths[tc] = out_len
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
        c2 = (lc[pos] >> 11) & cp_mask
        if c == :-. && c2 == :-. && pos + 1 < count && ((lc[pos + 1] >> 11) & cp_mask) == :-.
          pos += 2
        elsif c == :-. && c2 == :-.
          pos++
        elsif c == :-| && c2 == :-| && pos + 1 < count && ((lc[pos + 1] >> 11) & cp_mask) == :-=
          pos += 2
        else
          match = 0
          case c
          when :--
            if c2 == :-> || c2 == :-- || c2 == :-=
              match = 1
          when :-<
            if c2 == :-< || c2 == :-- || c2 == :-! || c2 == :-=
              match = 1
          when :-=
            if c2 == :-> || c2 == :-= || c2 == :-~
              match = 1
          when :-!
            if c2 == :-=
              match = 1
          when :->
            if c2 == :-> || c2 == :-=
              match = 1
          when :-&
            if c2 == :-. || c2 == :-& || c2 == :-(
              match = 1
          when :-|
            if c2 == :-| || c2 == :->
              match = 1
          when :-+
            if c2 == :-+ || c2 == :-=
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

      tokens[tc] = t_op | (start << 8)

      out_len = pos - start

      if out_len > 255

        out_len = 255

      lengths[tc] = out_len
      tc++

    else
      start = pos
      if c == :-U && pos + 2 < count && ((lc[pos + 1] >> 11) & cp_mask) == :-+
        if (lc[pos + 2] & 0x08) != 0
          pos += 2
          pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x08)
          tokens[tc] = t_codepoint | (start << 8)
          out_len = pos - start
          if out_len > 255
            out_len = 255
          lengths[tc] = out_len
          tc++
      elsif c >= 65 && c <= 90
        pos++
        while pos < count
          c2 = (lc[pos] >> 11) & cp_mask
          if (lc[pos] & 0x20) != 0 || (c2 >= 65 && c2 <= 90)
            pos++
          else
            break
        tokens[tc] = t_name | (start << 8)
        out_len = pos - start
        if out_len > 255
          out_len = 255
        lengths[tc] = out_len
        tc++
      elsif c == :-@
        pos++
        if pos < count && ((lc[pos] >> 11) & cp_mask) == :-@ && pos + 1 < count && (lc[pos + 1] & 0x40) != 0
          pos++
          pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x20)
          tokens[tc] = t_cvar | (start << 8)
          out_len = pos - start
          if out_len > 255
            out_len = 255
          lengths[tc] = out_len
        elsif pos < count && (lc[pos] & 0x01) != 0
          pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x01)
          tokens[tc] = t_parg | (start << 8)
          out_len = pos - start
          if out_len > 255
            out_len = 255
          lengths[tc] = out_len
        elsif pos < count && (lc[pos] & 0x40) != 0
          pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x20)
          tokens[tc] = t_ivar | (start << 8)
          out_len = pos - start
          if out_len > 255
            out_len = 255
          lengths[tc] = out_len
        else
          tokens[tc] = t_op | (start << 8)
          lengths[tc] = 1
        tc++
      elsif c == :-$ && pos + 1 < count && (lc[pos + 1] & 0x01) != 0
        pos++
        while pos < count && (lc[pos] & 0x01) != 0
          pos++
        if pos + 1 < count && ((lc[pos] >> 11) & cp_mask) == :-. && (lc[pos + 1] & 0x01) != 0
          pos++
          while pos < count && (lc[pos] & 0x01) != 0
            pos++
        tokens[tc] = t_decimal | (start << 8)
        out_len = pos - start
        if out_len > 255
          out_len = 255
        lengths[tc] = out_len
        tc++
      elsif c == :-$ && pos + 1 < count && (lc[pos + 1] & 0x40) != 0
        pos += 1
        pos = ccall_nobox("w_lex32_scan_flag", data_ptr, count, pos, 0x20)
        tokens[tc] = t_id | (start << 8)
        out_len = pos - start
        if out_len > 255
          out_len = 255
        lengths[tc] = out_len
        tc++
      elsif c == 0xAB
        pos++
        while pos < count && ((lc[pos] >> 11) & cp_mask) != 0xBB
          pos++
        if pos < count
          pos++
        tokens[tc] = t_byte_array | (start << 8)
        out_len = pos - start
        if out_len > 255
          out_len = 255
        lengths[tc] = out_len
        tc++
      else
        tokens[tc] = t_op | (pos << 8)
        lengths[tc] = 1
        tc++
        pos++

  while indent_top > 0
    indent_top -= 1
    tokens[tc] = t_dedent | (pos << 8)
    lengths[tc] = 0
    tc++

  tokens[tc] = t_eof | (pos << 8)

  lengths[tc] = 0
  token_total = tc + 1

  i = 0
  while i < token_total
    tok = tokens[i]
    off = tok >> 8
    len = lengths[i]
    type_id = (tok >> 2) & 0x3F
    flags = 0
    if off < count && type_id != 8 && type_id != 9 && type_id != 10 && type_id != 23
      if off > 0
        c2 = (lc[off - 1] >> 11) & cp_mask
        if c2 == 32 || c2 == 9
          flags = flags | f_sp_before
      after = off + len
      if len == 255
        next_i = i + 1
        if next_i < token_total
          after = (tokens[next_i] >> 8) - 1
      if after >= off && after < count
        c2 = (lc[after] >> 11) & cp_mask
        if c2 == 32 || c2 == 9
          flags = flags | f_sp_after
    tokens[i] = tok | flags
    i += 1

  token_total
