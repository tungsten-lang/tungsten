+ Lexer

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

    # The native scanner performs raw masks/shifts over the tagged words, so
    # reinterpret the w64[] storage as machine integers only for this call.
    lc = @lc ## i64[]
    packed = i64[lc.size() + 2048]
    indents = i64[1024]
    count = tungsten_tokenize_fast64(lc, lc.size(), packed, indents)

    i = 0
    while i < count
      # Every field lives in bits 0-45, so descriptors remain inline Ints
      # after crossing from the raw staging buffer into @packed_tokens.
      materialize_packed_token(packed[i])
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
    if @line_at != nil && off < @line_at.size() && @line_at[off] != nil
      @line = @line_at[off]
    else
      @line = 1
    if @col_at != nil && off < @col_at.size() && @col_at[off] != nil
      @col = @col_at[off]
    else
      @col = 1

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
    when :APPROX then 168
    when :CARET_EQ then 163
    when :LSHIFT_EQ then 164
    when :RSHIFT_EQ then 165
    when :DECIMAL_ARRAY then 166
    when :FLOAT_ARRAY then 167
    else 0
