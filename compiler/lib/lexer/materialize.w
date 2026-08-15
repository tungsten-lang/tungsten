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
      reject_mixed_case_join(raw, off, false)
      emit_at(:IVAR, raw, off)
    when 13
      reject_mixed_case_join(raw, off, false)
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

  -> reject_mixed_case_join(raw, off, allow_unit)
    # Lowercase identifiers stop before uppercase ASCII in the packed scanner,
    # so `camelCase` would otherwise materialize as adjacent ID + NAME tokens
    # and fail later (or be misread as a juxtaposition call). Reject that join
    # at the lexical boundary. Registered mixed-case unit spellings such as
    # `eV`, `mmHg`, and `kWh` remain split for the parser's unit-expecting
    # surfaces; they are not admitted as ordinary identifiers.
    mixed_end = off + raw.size()
    if mixed_end < @char_count && @chars[mixed_end] >= "A" && @chars[mixed_end] <= "Z"
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
    reject_mixed_case_join(raw, off, true)
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
      # Approximate equality (`a ≈ b`, equality precedence). Also accepted
      # as a method name (`-> ≈(other)`) via the parser's operator-method
      # list, like == and <=>.
      emit_at(:APPROX, raw, off)
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
