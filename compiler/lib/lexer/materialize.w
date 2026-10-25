+ Lexer

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

  -> emit_id(type_id, type, value)
    tok = (@current_packed_tok & 0x3FFFFFFFFF) | (type_id << 38)
    @current_packed_tok = tok
    @packed_tokens.push(tok)
    @values.push(value)
    @token_count += 1
    @last_token_type = type
    @last_token_value = value
    @after_lambda_params = false

  -> emit_same_id(type, value)
    @packed_tokens.push(@current_packed_tok)
    @values.push(value)
    @token_count += 1
    @last_token_type = type
    @last_token_value = value
    @after_lambda_params = false

  -> raise_unexpected_character(raw, off)
    line = (@line_at != nil && off < @line_at.size() && @line_at[off] != nil) ? @line_at[off] : 1
    col = (@col_at != nil && off < @col_at.size() && @col_at[off] != nil) ? @col_at[off] : 1
    raise compile_error_with_span(:E_LEX_UNEXPECTED_CHAR, "Unexpected character '" + raw.to_s() + "'", @file, line, col, raw.size())

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

  -> materialize_packed_token(tok)
    # This is a dynamically dispatched Lexer method, so its argument crosses
    # the method boundary as a boxed Int even though the staging buffer is an
    # i64[]. Normalize once before the hot shifts. Declaring `tok` as raw i64
    # made the callee reinterpret W_TAG_INT bits as token bits.
    bits = ccall_nobox("w_numeric_to_i64", tok)
    @current_packed_tok = bits
    type_id = (bits >> 38) & 0xFF
    off = (bits >> 2) & 0xFFFFFF
    len = (bits >> 26) & 0xFFF
    # Skip packed op tokens already consumed by a superscript run (each
    # superscript char is a separate native token; materialize_op scans
    # the whole run at once and sets @sup_skip_to past it).
    if off < @sup_skip_to
      return nil

    case type_id
    when 25
      # :SP token — one-or-more spaces/tabs between non-whitespace
      # tokens. Value carries the raw source span so the parser /
      # error formatter can see the exact whitespace if needed.
      @packed_tokens.push(bits)
      if len == 1
        @values.push(@chars[off])
      else
        @values.push(slice_chars(off, len))
      @token_count += 1
    when 1
      materialize_id(slice_chars(off, len), off)
    when 2
      emit_same_id(:NAME, slice_chars(off, len))
    when 3
      materialize_number_at(off, len)
    when 4
      materialize_decimal_at(off, len)
    when 5
      materialize_string_like_at(off, len)
    when 6
      emit_same_id(:SYMBOL, slice_chars(off + 1, len - 1))
    when 7
      emit_same_id(:TYPE_HINT, slice_chars(off, len))
    when 8
      @regex_capture_scope = false
      emit_same_id(:NEWLINE, nil)
    when 9
      emit_same_id(:INDENT, nil)
    when 10
      emit_same_id(:DEDENT, nil)
    when 11
      if @lc != nil
        materialize_op_at(off, len)
      else
        materialize_op(slice_chars(off, len), off)
    when 12
      raw = slice_chars(off, len)
      if off + len < @char_count && is_upper?(@lc[off + len])
        reject_mixed_case_join(raw, off, false)
      emit_same_id(:IVAR, raw)
    when 13
      raw = slice_chars(off, len)
      if off + len < @char_count && is_upper?(@lc[off + len])
        reject_mixed_case_join(raw, off, false)
      emit_same_id(:CVAR, raw)
    when 14
      emit_same_id(:PARG, slice_chars(off + 1, len - 1))
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
      materialize_char(slice_chars(off, len), off)
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
      materialize_magic(slice_chars(off, len), off)
    when 23
      emit_same_id(:EOF, nil)
    when 24
      emit_id(5, :STRING, slice_chars(off, len))
    when 26
      # t_constant — SCREAMING_SNAKE chunk identified inline by the
      # chunker. No re-scan needed at materialize time.
      emit_id(152, :CONSTANT, slice_chars(off, len))
    else
      emit_at(:UNKNOWN, slice_chars(off, len), off)

  -> reject_mixed_case_join(raw, off, allow_unit)
    # Lowercase identifiers stop before uppercase ASCII in the packed scanner,
    # so `camelCase` would otherwise materialize as adjacent ID + NAME tokens
    # and fail later (or be misread as a juxtaposition call). Reject that join
    # at the lexical boundary. Registered mixed-case unit spellings such as
    # `eV`, `mmHg`, and `kWh` remain split for the parser's unit-expecting
    # surfaces; they are not admitted as ordinary identifiers.
    mixed_end = off + raw.size()
    if mixed_end < @char_count && is_upper?(@lc[mixed_end])
      p = mixed_end
      while p < @char_count
        ch = @chars[p]
        if (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9") || ch == "_"
          p += 1
        else
          break
      joined = slice_chars(off, p - off)
      if !allow_unit || !known_unit_name?(joined)
        raise compile_error_with_span(:E_LEX_INVALID_IDENTIFIER, "uppercase ASCII is not valid in identifiers: '" + joined + "' — use snake_case", @file, @line_at[off], @col_at[off], joined.size())

  -> materialize_id(raw, off)
    rlen = raw.size()
    if @lc != nil
      lc = @lc ## i64[]
      mixed_end = off + rlen
      c_next = 0
      if mixed_end < @char_count
        c_next = (lc[mixed_end] >> 18) & 0x1FFFFF
        if c_next >= 65 && c_next <= 90
          reject_mixed_case_join(raw, off, true)
      if rlen == 8 && c_next == 45
        reset_scan_position(off)
        if try_scan_uuid()
          @sup_skip_to = @pos
          return nil
      if rlen <= 4 && c_next == 58 && all_hex_chunk_at?(off, rlen)
        reset_scan_position(off)
        if try_scan_ipv6()
          @sup_skip_to = @pos
          return nil
      if rlen == 0
        emit_same_id(:ID, raw)
        return nil
      c0 = (lc[off] >> 18) & 0x1FFFFF
      if c0 == 36
        emit_id(28, :GLOBAL, raw)
        return nil
      if rlen == 19 && c0 == 117 && raw.starts_with?("u0x")
        reset_scan_position(off)
        scan_wvalue()
        return nil
      c_last = (lc[off + rlen - 1] >> 18) & 0x1FFFFF
      if c_last == 63 || c_last == 33 || c0 == 95 || rlen == 1 || rlen > 13
        emit_same_id(:ID, raw)
        return nil
      if c_last >= 97 && c_last <= 122
        if rlen == 3 && raw == "and"
          emit_id(29, :AND, raw)
        elsif rlen == 2 && raw == "or"
          emit_id(30, :OR, raw)
        elsif rlen <= 8 && is_keyword?(raw)
          emit_id(26, :KEYWORD, raw)
        elsif (rlen == 3 && raw == "int") || (rlen == 4 && raw == "bool") || (rlen == 6 && (raw == "string" || raw == "bigint")) || (rlen == 7 && raw == "integer") || (rlen == 10 && raw == "bigdecimal") || (rlen == 13 && raw == "string_buffer")
          emit_id(27, :TYPE, raw)
        else
          emit_same_id(:ID, raw)
        return nil
      if c_last >= 48 && c_last <= 57 && rlen <= 7 && is_type_name?(raw)
        emit_id(27, :TYPE, raw)
        return nil
      emit_same_id(:ID, raw)
      return nil

    reject_mixed_case_join(raw, off, true)
    # A UUID whose first field starts with a hex letter (a–f) is chunked as an
    # identifier; recognize it here. Digit-first UUIDs go through scan_number.
    if rlen == 8 && off + 8 < @char_count && @chars[off + 8] == "-"
      reset_scan_position(off)
      if try_scan_uuid()
        @sup_skip_to = @pos
        return nil
    # IPv6 whose first group starts with a hex letter (fe80::1, db8::…) is
    # chunked as an identifier. Digit-first groups go through scan_number.
    # Guard: a 1-4 char all-hex chunk immediately followed by ':'. The "::"
    # requirement inside try_scan_ipv6 is the real filter (a hash key like
    # `ab: 1` fails it and falls through to the normal identifier path).
    if rlen <= 4 && off + rlen < @char_count && @chars[off + rlen] == ":" && all_hex_chunk_at?(off, rlen)
      reset_scan_position(off)
      if try_scan_ipv6()
        @sup_skip_to = @pos
        return nil
    if rlen > 0 && @chars[off] == "$"
      emit_id(28, :GLOBAL, raw)
      return nil
    if rlen == 19 && raw.starts_with?("u0x")
      reset_scan_position(off)
      scan_wvalue()
      return nil
    if raw.ends_with?("?") || raw.ends_with?("!")
      emit_same_id(:ID, raw)
      return nil
    if rlen == 3 && raw == "and"
      emit_id(29, :AND, raw)
    elsif rlen == 2 && raw == "or"
      emit_id(30, :OR, raw)
    elsif is_keyword?(raw)
      emit_id(26, :KEYWORD, raw)
    elsif is_type_name?(raw)
      emit_id(27, :TYPE, raw)
    else
      emit_same_id(:ID, raw)

  -> materialize_number_at(off, len = 0)
    if @lc != nil && (len == 1 || len == 2)
      lc = @lc ## i64[]
      if (lc[off] & 0x01) != 0 && (len == 1 || (lc[off + 1] & 0x01) != 0)
        end_pos = off + len
        if end_pos >= @char_count
          emit_same_id(:INT, slice_chars(off, len))
          return nil
        next_lc = lc[end_pos]
        ncp = (next_lc >> 18) & 0x1FFFFF
        if ncp < 128 && (next_lc & 0x69) == 0 && !(ncp >= 65 && ncp <= 90) && ncp != 46 && ncp != 32 && ncp != 58 && ncp != 45 && ncp != 37 && ncp != 47 && ncp != 94
          emit_same_id(:INT, slice_chars(off, len))
          return nil
        if ncp == 32 && (end_pos + 1 >= @char_count || (((lc[end_pos + 1] >> 18) & 0x1FFFFF) < 128 && (lc[end_pos + 1] & 0x40) == 0 && !(((lc[end_pos + 1] >> 18) & 0x1FFFFF) >= 65 && ((lc[end_pos + 1] >> 18) & 0x1FFFFF) <= 90)))
          emit_same_id(:INT, slice_chars(off, len))
          return nil
    if off + 2 < @char_count && @chars[off] == "u" && @chars[off + 1] == "0" && @chars[off + 2] == "x"
      reset_scan_position(off)
      scan_wvalue()
      return nil
    reset_scan_position(off)
    scan_number()
    @sup_skip_to = @pos

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

  -> materialize_decimal_at(off, len)
    if off < @char_count
      ch0 = @chars[off]
      if ch0 == "~"
        if off + 1 < @char_count && @chars[off + 1] == "+"
          value = slice_chars(off + 2, len - 2)
        else
          value = slice_chars(off + 1, len - 1)
        emit_id(31, :FLOAT, value)
        return nil
      if ch0 == "$"
        if @regex_capture_scope
          emit_id(46, :REGEX_CAPTURE, slice_chars(off + 1, len - 1))
        else
          reset_scan_position(off)
          scan_currency_signed()
        return nil
    reset_scan_position(off)
    scan_number()
    @sup_skip_to = @pos

  -> materialize_decimal(raw, off)
    if raw.size() > 0 && raw[0] == "~"
      value = raw.slice(1, raw.size() - 1)
      if value.size() > 0 && value[0] == "+"
        value = value.slice(1, value.size() - 1)
      emit_id(31, :FLOAT, value)
      return nil
    if raw.size() > 0 && raw[0] == "$"
      if @regex_capture_scope
        emit_id(46, :REGEX_CAPTURE, raw.slice(1, raw.size() - 1))
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

  -> materialize_string_like_at(off, len)
    if off < @char_count
      ch0 = @chars[off]
      if ch0 == "\""
        reset_scan_position(off + 1)
        scan_string()
        @sup_skip_to = @pos
        return nil
      if ch0 == "'"
        materialize_ascii_literal(slice_chars(off, len), off)
        return nil
      if ch0 == "/"
        materialize_regex(slice_chars(off, len), off)
        return nil
      if ch0 == "<" && off + 2 < @char_count && @chars[off + 1] == "<" && @chars[off + 2] == "~"
        reset_scan_position(off)
        scan_heredoc()
        @sup_skip_to = @pos
        return nil
    materialize_string_like(slice_chars(off, len), off)

  -> materialize_string_like(raw, off)
    if raw.starts_with?("<<~")
      reset_scan_position(off)
      scan_heredoc()
      @sup_skip_to = @pos
      return nil
    if raw.size() > 0 && raw[0] == "/"
      materialize_regex(raw, off)
      return nil
    if raw.size() > 0 && raw[0] == "'"
      materialize_ascii_literal(raw, off)
      return nil
    reset_scan_position(off + 1)
    scan_string()
    @sup_skip_to = @pos

  -> materialize_regex(raw, off)
    chars = raw.chars()
    n = chars.size()
    pattern = StringBuffer(raw.size())
    escaped = false
    in_class = false
    i = 1
    while i < n
      ch = chars[i]
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
        opts = StringBuffer(4)
        j = i + 1
        while j < n
          opts << chars[j]
          j += 1
        emit_at(:REGEX, [pattern.to_s(), opts.to_s()], off)
        return nil
      else
        pattern << ch
      i += 1
    emit_at(:REGEX, [pattern.to_s(), ""], off)

  # ASCII literals are deliberately simple String values: the
  # first following quote terminates them, and neither backslash nor `[]` has
  # special meaning. The packed scanner therefore does no escape/interpolation
  # work; validation happens once while the token is materialized.
  -> materialize_ascii_literal(raw, off)
    if !raw.ends_with?("'")
      raise compile_error(:E_LEX_UNTERMINATED_ASCII_LITERAL, "Unterminated ASCII literal", @file, @line_at[off], @col_at[off])
    body = raw.slice(1, raw.size() - 2)
    bytes = body.bytes()
    i = 0
    while i < bytes.size()
      if bytes[i] >= 128
        raise compile_error_with_span(:E_LEX_NON_ASCII_LITERAL, "ASCII literals accept ASCII bytes only; use double quotes for Unicode", @file, @line_at[off], @col_at[off], raw.size())
      i += 1
    emit_at(:STRING, body, off)

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

  -> materialize_op_at(off, len)
    lc = @lc ## i64[]
    c0 = (lc[off] >> 18) & 0x1FFFFF
    if len == 1 && c0 < 128
      case c0
      when 46
        emit_id(59, :DOT, ".")
      when 40
        opens_lambda = 0
        if @last_token_type == :ARROW
          opens_lambda = 1
        @paren_lambda_stack.push(opens_lambda)
        emit_id(50, :LPAREN, "(")
      when 41
        was_lambda = 0
        if @paren_lambda_stack.size() > 0
          was_lambda = @paren_lambda_stack.pop()
        emit_id(51, :RPAREN, ")")
        if was_lambda == 1
          @after_lambda_params = true
      when 44
        emit_id(56, :COMMA, ",")
      when 61
        emit_id(90, :ASSIGN, "=")
      when 58
        if off + 1 < @char_count && ((lc[off + 1] >> 18) & 0x1FFFFF) == 58
          reset_scan_position(off)
          if try_scan_ipv6()
            @sup_skip_to = @pos
            return nil
        emit_id(57, :COLON, ":")
      when 91
        emit_id(54, :LBRACKET, "\[")
      when 93
        emit_id(55, :RBRACKET, "]")
      when 43
        if is_value_type?(@last_token_type) || is_value_keyword_prev?()
          emit_id(80, :PLUS, "+")
        else
          emit_id(70, :CLASS_DEF, "+")
      when 45
        emit_id(81, :MINUS, "-")
      when 42
        emit_id(82, :STAR, "*")
      when 47
        if off + 1 < @char_count && (lc[off + 1] & 64) != 0
          emit_id(68, :MAP, "/")
        else
          emit_id(83, :SLASH, "/")
      when 60
        emit_id(102, :LT, "<")
      when 62
        emit_id(103, :GT, ">")
      when 33
        emit_id(65, :BANG, "!")
      when 63
        emit_id(66, :QUESTION, "?")
      when 124
        emit_id(113, :PIPE, "|")
      when 38
        emit_id(112, :AMPERSAND, "&")
      when 37
        emit_id(84, :PERCENT, "%")
      when 123
        emit_id(52, :LBRACE, "{")
      when 125
        emit_id(53, :RBRACE, "}")
      when 94
        emit_id(114, :CARET, "^")
      when 59
        @regex_capture_scope = false
        emit_id(58, :SEMICOLON, ";")
      when 35
        emit_id(169, :PRIMORIAL, "#")
      else
        raise_unexpected_character(slice_chars(off, len), off)
      return nil

    if len == 2 && c0 < 128
      c1 = (lc[off + 1] >> 18) & 0x1FFFFF
      if c1 < 128
        case (c0 << 8) | c1
        when 11582 then emit_id(62, :ARROW, "->")
        when 15677 then emit_id(100, :EQ, "==")
        when 8509 then emit_id(101, :NEQ, "!=")
        when 9766 then emit_id(29, :AND, "&&")
        when 31868 then emit_id(30, :OR, "||")
        when 11069 then emit_id(91, :PLUS_EQ, "+=")
        when 11581 then emit_id(92, :MINUS_EQ, "-=")
        when 15421 then emit_id(104, :LTE, "<=")
        when 15933 then emit_id(105, :GTE, ">=")
        when 15420
          if (is_value_type?(@last_token_type) || is_value_keyword_prev?()) && !@after_lambda_params
            emit_id(110, :LSHIFT, "<<")
          else
            emit_id(71, :PUTS_OP, "<<")
        when 15934 then emit_id(111, :RSHIFT, ">>")
        when 15678 then emit_id(63, :FAT_ARROW, "=>")
        when 11822 then emit_id(60, :DOTDOT, "..")
        when 11051 then emit_id(122, :PLUS_PLUS, "++")
        when 11565 then emit_id(123, :MINUS_MINUS, "--")
        when 10794 then emit_id(85, :POW, "**")
        when 10813 then emit_id(93, :STAR_EQ, "*=")
        when 12093 then emit_id(94, :SLASH_EQ, "/=")
        when 9533 then emit_id(95, :PERCENT_EQ, "%=")
        when 9789 then emit_id(161, :AMP_EQ, "&=")
        when 31805 then emit_id(162, :PIPE_EQ, "|=")
        when 24125 then emit_id(163, :CARET_EQ, "^=")
        when 31806 then emit_id(67, :PIPE_FWD, "|>")
        when 9774 then emit_id(64, :SAFE_NAV, "&.")
        when 9768 then emit_id(69, :BLOCK_CALL, "&(")
        when 15405 then emit_id(72, :PRINT_OP, "<-")
        when 15393 then emit_id(73, :RAISE_OP, "<!")
        when 15742
          @regex_capture_scope = true
          emit_id(107, :MATCH, "=~")
        when 8574 then emit_id(150, :NMATCH, "!~")
        when 9342 then emit_id(46, :REGEX_CAPTURE, "1000000")
        when 9254 then emit_id(46, :REGEX_CAPTURE, "0")
        when 9312 then emit_id(46, :REGEX_CAPTURE, "1000001")
        when 9255 then emit_id(46, :REGEX_CAPTURE, "1000002")
        when 9259 then emit_id(46, :REGEX_CAPTURE, "1000003")
        when 11584 then emit_id(1, :ID, "-@")
        when 11072 then emit_id(1, :ID, "+@")
        when 15422 then emit_id(155, :SWAP, "<>")
        when 11819 then emit_id(130, :DOT_PLUS, ".+")
        when 11821 then emit_id(131, :DOT_MINUS, ".-")
        when 11818 then emit_id(132, :DOT_STAR, ".*")
        when 11823 then emit_id(133, :DOT_SLASH, "./")
        when 11900 then emit_id(134, :DOT_PIPE, ".|")
        when 11814 then emit_id(135, :DOT_AMP, ".&")
        when 11870 then emit_id(136, :DOT_CARET, ".^")
        else
          materialize_op(slice_chars(off, len), off)
        return nil

    materialize_op(slice_chars(off, len), off)

  -> materialize_op(raw, off)
    rlen = raw.size()
    if rlen == 1
      if raw == "."
        emit_id(59, :DOT, raw)
      elsif raw == "("
        # Remember whether this `(` opens a lambda param list (`->(`). Read
        # @last_token_type before emit_at overwrites it. Store 1/0 (not a
        # bool) to sidestep the inline bool-array codegen path.
        opens_lambda = 0
        if @last_token_type == :ARROW
          opens_lambda = 1
        @paren_lambda_stack.push(opens_lambda)
        emit_id(50, :LPAREN, raw)
      elsif raw == ")"
        was_lambda = 0
        if @paren_lambda_stack.size() > 0
          was_lambda = @paren_lambda_stack.pop()
        emit_id(51, :RPAREN, raw)
        # Set after emit_at so push_token's reset doesn't clear it.
        if was_lambda == 1
          @after_lambda_params = true
      elsif raw == ","
        emit_id(56, :COMMA, raw)
      elsif raw == "="
        emit_id(90, :ASSIGN, raw)
      elsif raw == ":"
        # Leading "::" opens an IPv6 literal (::1, bare ::, ::ffff:1.2.3.4, ::/0).
        # Fire before the operator table so "::" isn't split into two COLONs.
        # There are no bare "::" operator sequences in valid .w source (all "::"
        # in compiler/core/lib live inside strings or comments), so this cannot
        # change the self-host token stream. Falls through on no-match.
        if off + 1 < @char_count && @chars[off + 1] == ":"
          reset_scan_position(off)
          if try_scan_ipv6()
            @sup_skip_to = @pos
            return nil
        emit_id(57, :COLON, raw)
      elsif raw == "\["
        emit_id(54, :LBRACKET, raw)
      elsif raw == "]"
        emit_id(55, :RBRACKET, raw)
      elsif raw == "+"
        if is_value_type?(@last_token_type) || is_value_keyword_prev?()
          emit_id(80, :PLUS, raw)
        else
          emit_id(70, :CLASS_DEF, raw)
      elsif raw == "-"
        emit_id(81, :MINUS, raw)
      elsif raw == "*"
        emit_id(82, :STAR, raw)
      elsif raw == "/"
        # MAP operator: `/name` with an identifier immediately after the slash
        # (no space) is a pipeline map stage — both prefix (`/sq`) and infix
        # (`arr/sq`). Division requires spaces (`a / b`) or a non-ident operand
        # (`10/2`); the is_ident_start check below excludes both. Note: this
        # makes `a/b` (two bare identifiers, no spaces) a map, by design.
        if off + 1 < @char_count && is_ident_start?(@lc[off + 1])
          emit_id(68, :MAP, raw)
        else
          emit_id(83, :SLASH, raw)
      elsif raw == "<"
        emit_id(102, :LT, raw)
      elsif raw == ">"
        emit_id(103, :GT, raw)
      elsif raw == "!"
        emit_id(65, :BANG, raw)
      elsif raw == "?"
        emit_id(66, :QUESTION, raw)
      elsif raw == "|"
        emit_id(113, :PIPE, raw)
      elsif raw == "&"
        emit_id(112, :AMPERSAND, raw)
      elsif raw == "%"
        emit_id(84, :PERCENT, raw)
      elsif raw == "{"
        emit_id(52, :LBRACE, raw)
      elsif raw == "}"
        emit_id(53, :RBRACE, raw)
      elsif raw == "^"
        emit_id(114, :CARET, raw)
      elsif raw == ";"
        @regex_capture_scope = false
        emit_id(58, :SEMICOLON, raw)
      elsif raw == "#"
        emit_id(169, :PRIMORIAL, raw)
      else
        raise_unexpected_character(raw, off)
      return nil

    if rlen == 2
      if raw == "->"
        emit_id(62, :ARROW, raw)
      elsif raw == "=="
        emit_id(100, :EQ, raw)
      elsif raw == "!="
        emit_id(101, :NEQ, raw)
      elsif raw == "&&"
        emit_id(29, :AND, raw)
      elsif raw == "||"
        emit_id(30, :OR, raw)
      elsif raw == "+="
        emit_id(91, :PLUS_EQ, raw)
      elsif raw == "-="
        emit_id(92, :MINUS_EQ, raw)
      elsif raw == "<="
        emit_id(104, :LTE, raw)
      elsif raw == ">="
        emit_id(105, :GTE, raw)
      elsif raw == "<<"
        # `->(x) << ...` — the `)` closes a lambda param list, not a value, so
        # `<<` begins the body as a PUTS_OP. Without the latch, RPAREN's
        # value-type classification would mis-emit LSHIFT here.
        if (is_value_type?(@last_token_type) || is_value_keyword_prev?()) && !@after_lambda_params
          emit_id(110, :LSHIFT, raw)
        else
          emit_id(71, :PUTS_OP, raw)
      elsif raw == ">>"
        emit_id(111, :RSHIFT, raw)
      elsif raw == "=>"
        emit_id(63, :FAT_ARROW, raw)
      elsif raw == ".."
        emit_id(60, :DOTDOT, raw)
      elsif raw == "++"
        emit_id(122, :PLUS_PLUS, raw)
      elsif raw == "--"
        emit_id(123, :MINUS_MINUS, raw)
      elsif raw == "**"
        emit_id(85, :POW, raw)
      elsif raw == "*="
        emit_id(93, :STAR_EQ, raw)
      elsif raw == "/="
        emit_id(94, :SLASH_EQ, raw)
      elsif raw == "%="
        emit_id(95, :PERCENT_EQ, raw)
      elsif raw == "&="
        emit_id(161, :AMP_EQ, raw)
      elsif raw == "|="
        emit_id(162, :PIPE_EQ, raw)
      elsif raw == "^="
        emit_id(163, :CARET_EQ, raw)
      elsif raw == "|>"
        emit_id(67, :PIPE_FWD, raw)
      elsif raw == "&."
        emit_id(64, :SAFE_NAV, raw)
      elsif raw == "&("
        emit_id(69, :BLOCK_CALL, raw)
      elsif raw == "<-"
        emit_id(72, :PRINT_OP, raw)
      elsif raw == "<!"
        emit_id(73, :RAISE_OP, raw)
      elsif raw == "=~"
        @regex_capture_scope = true
        emit_id(107, :MATCH, raw)
      elsif raw == "!~"
        emit_id(150, :NMATCH, raw)
      elsif raw == "$~"
        emit_id(46, :REGEX_CAPTURE, "1000000")
      elsif raw == "$&"
        emit_id(46, :REGEX_CAPTURE, "0")
      elsif raw == "$`"
        emit_id(46, :REGEX_CAPTURE, "1000001")
      elsif raw == "$'"
        emit_id(46, :REGEX_CAPTURE, "1000002")
      elsif raw == "$+"
        emit_id(46, :REGEX_CAPTURE, "1000003")
      elsif raw == "-@"
        # Unary-minus method-name marker (`-> -@`). Emitted as T_ID so
        # expect_method_name treats it as a normal identifier.
        emit_id(1, :ID, raw)
      elsif raw == "+@"
        # Unary-plus method-name marker (`-> +@`). Same shape as `-@`.
        emit_id(1, :ID, raw)
      elsif raw == "<>"
        emit_id(155, :SWAP, raw)
      elsif raw == ".+"
        emit_id(130, :DOT_PLUS, raw)
      elsif raw == ".-"
        emit_id(131, :DOT_MINUS, raw)
      elsif raw == ".*"
        emit_id(132, :DOT_STAR, raw)
      elsif raw == "./"
        emit_id(133, :DOT_SLASH, raw)
      elsif raw == ".|"
        emit_id(134, :DOT_PIPE, raw)
      elsif raw == ".&"
        emit_id(135, :DOT_AMP, raw)
      elsif raw == ".^"
        emit_id(136, :DOT_CARET, raw)
      elsif raw == "·"
        emit_id(120, :DOT_PRODUCT, raw)
      elsif raw == "×"
        emit_id(121, :CROSS_PRODUCT, raw)
      elsif raw == "±"
        emit_id(159, :PLUS_MINUS, raw)
      elsif raw == "°"
        # Degree unit (°C / °F / °R): scan the ° plus any trailing letters into
        # one NAME token so a bare unit after `|` (`100 °C | °F`) resolves via
        # known_unit_name?. A number-prefixed `100 °C` is caught earlier in the
        # number path. @sup_skip_to suppresses the now-consumed letter chunks.
        deg_j = off + 1
        while deg_j < @char_count && unit_alpha_at?(deg_j)
          deg_j = deg_j + 1
        emit_id(2, :NAME, slice_chars(off, deg_j - off))
        @sup_skip_to = deg_j
      elsif superscript_digit(@chars[off]) >= 0
        sup_digits = ""
        sup_j = off
        while sup_j < @char_count && superscript_digit(@chars[sup_j]) >= 0
          sup_digits = sup_digits + superscript_digit(@chars[sup_j]).to_s()
          sup_j = sup_j + 1
        emit(:EXPONENT, sup_digits)
        @sup_skip_to = sup_j
      else
        raise_unexpected_character(raw, off)
      return nil

    if raw.starts_with?("->/")
      emit_id(45, :LAMBDA_ARITY, raw)
    elsif raw == "..."
      emit_id(61, :DOTDOTDOT, raw)
    elsif raw == "==="
      @regex_capture_scope = true
      emit_id(151, :TRIPLE_EQ, raw)
    elsif raw == "<=>"
      emit_id(106, :SPACESHIP, raw)
    elsif raw == "||="
      emit_id(96, :OR_ASSIGN, raw)
    elsif raw == "<<="
      emit_id(164, :LSHIFT_EQ, raw)
    elsif raw == ">>="
      emit_id(165, :RSHIFT_EQ, raw)
    elsif raw == "**="
      emit_id(160, :POW_EQ, raw)
    elsif raw == ".<<"
      emit_id(137, :DOT_LSHIFT, raw)
    elsif raw == ".>>"
      emit_id(138, :DOT_RSHIFT, raw)
    elsif raw == "⋅"
      emit_id(120, :DOT_PRODUCT, raw)
    elsif raw == "√"
      emit_id(154, :SQRT, raw)
    elsif raw == "⊙"
      emit_id(124, :HADAMARD, raw)
    elsif raw == "⊗"
      emit_id(125, :KRONECKER, raw)
    elsif raw == "≈"
      # Approximate equality (`a ≈ b`, equality precedence). Also accepted
      # as a method name (`-> ≈(other)`) via the parser's operator-method
      # list, like == and <=>.
      emit_id(168, :APPROX, raw)
    elsif raw == "∘"
      emit_id(170, :COMPOSE, raw)
    elsif raw == "↑↑"
      emit_id(171, :TETRATE, raw)
    elsif raw == "∈"
      emit_id(172, :MEMBER, raw)
    elsif raw == "∉"
      emit_id(173, :NOT_MEMBER, raw)
    elsif raw == "∪"
      emit_id(174, :UNION, raw)
    elsif raw == "∩"
      emit_id(175, :INTERSECTION, raw)
    elsif raw == "⊆"
      emit_id(176, :SUBSET, raw)
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
    else
      raise_unexpected_character(raw, off)
