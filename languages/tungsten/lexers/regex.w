# Legacy character-at-a-time Tungsten lexer.
# The packed compiler lexer imports regex_base directly for shared scanner helpers.

use regex_base

+ RegexLexer < RegexBase
  -> tokenize
    while @pos < @char_count
      tokenize_one()

    # Emit remaining DEDENTs
    while @indent_stack.last() > 0
      @indent_stack.pop()
      emit(:DEDENT, nil)

    emit(:EOF, nil)
    @tokens

  -> tokenize_one
    if @at_line_start
      handle_indentation()
      return nil

    ch = @chars[@pos]
    cp = @lc[@pos]

    # Whitespace
    if ch == " " || ch == "\t"
      @pos += 1
      @col += 1
      while @pos < @char_count && (@chars[@pos] == " " || @chars[@pos] == "\t")
        @pos += 1
        @col += 1
      return nil

    # Type hint (##) or comment (#)
    if ch == "#"
      if @pos + 1 < @char_count && @chars[@pos + 1] == "#"
        @pos += 2
        @col += 2
        # Skip whitespace after ##
        while @pos < @char_count && (@chars[@pos] == " " || @chars[@pos] == "\t")
          @pos += 1
          @col += 1
        hint = StringBuffer(@char_count - @pos)
        while @pos < @char_count && @chars[@pos] != "\n"
          hint << @chars[@pos]
          @pos += 1
          @col += 1
        emit(:TYPE_HINT, hint.to_s())
        return nil
      # Key literal: #[Enter], #[Ctrl+C]
      if @pos + 1 < @char_count && @chars[@pos + 1] == "\["
        @pos += 2
        @col += 2
        scan_key_literal()
        return nil
      # Color literal: #RGB, #RGBA, #RRGGBB, #RRGGBBAA
      if @pos + 1 < @char_count && is_hex_char?(@lc[@pos + 1])
        if try_scan_color()
          return nil
      @pos += 1
      @col += 1
      while @pos < @char_count && @chars[@pos] != "\n"
        @pos += 1
        @col += 1
      return nil

    # Newline
    if ch == "\n"
      if @paren_depth == 0
        emit(:NEWLINE, nil)
      @regex_capture_scope = false
      @pos += 1
      @line += 1
      @col = 1
      @at_line_start = true
      return nil

    # Byte array literal « ... »
    if ch == "«"
      @pos += 1
      @col += 1
      scan_byte_array()
      return nil

    # String
    if ch == "\""
      @pos += 1
      @col += 1
      scan_string()
      return nil

    # Symbol — :identifier
    if ch == ":" && @pos + 1 < @char_count && is_ident_start?(peek_lc_at(1))
      @pos += 1
      @col += 1
      word = scan_ident()
      emit(:SYMBOL, word)
      return nil

    # Also allow :UpperCase symbols
    if ch == ":" && @pos + 1 < @char_count && is_upper?(peek_lc_at(1))
      @pos += 1
      @col += 1
      word = scan_class_name()
      emit(:SYMBOL, word)
      return nil

    # Char literal `:-X` (Phase 7). Recognized BEFORE the operator-symbol
    # dispatch below because `:-` itself is the method-name symbol for `-`
    # but `:-<non-whitespace>` is unambiguously a char literal. This works
    # because Tungsten requires leading whitespace on binary operators —
    # `: - X` (with spaces) is three tokens but `:-X` (contiguous) cannot
    # mean "colon followed by binary minus" and so is available for use.
    #
    # `:-\n`, `:-\t`, `:-\\`, `:-\0`, `:-\s` are escape forms.
    # Non-ASCII (codepoint > 0x7F) raises an error — users needing
    # unicode should use the existing `U+xxxx` form.
    if ch == ":" && @pos + 2 < @char_count && peek_char_at(1) == "-"
      third = peek_char_at(2)
      if third != " " && third != "\t" && third != "\n" && third != "\r"
        start_col = @col
        if third == "\\" && @pos + 3 < @char_count
          esc = peek_char_at(3)
          cp = nil
          if esc == "n"
            cp = 10
          if esc == "t"
            cp = 9
          if esc == "r"
            cp = 13
          if esc == "\\"
            cp = 92
          if esc == "0"
            cp = 0
          if esc == "s"
            cp = 32
          if esc == "'"
            cp = 39
          if esc == "\""
            cp = 34
          if cp != nil
            @pos += 4
            @col += 4
            push_token({type: :CHAR, value: cp, line: @line, col: start_col})
            return nil
        # Bare ASCII char
        cp = third.ord()
        if cp > 127
          raise {rt: :compile_error, code: :E_LEX_CHAR_NON_ASCII, message: "`:-X` char literal only supports ASCII. Use U+[cp.to_s(16)] for non-ASCII characters.", file: @file, row: @line, col: start_col, span_length: 3}
        @pos += 3
        @col += 3
        push_token({type: :CHAR, value: cp, line: @line, col: start_col})
        return nil

    # Operator symbols: :+, :-, :==, :<=>, :[], :[]=, etc.
    if ch == ":" && @pos + 1 < @char_count
      nc = peek_char_at(1)
      if nc == "+" || nc == "-" || nc == "*" || nc == "/" || nc == "~" || nc == "!" || nc == "%" || nc == "^" || nc == "&" || nc == "<" || nc == ">" || nc == "|" || nc == "="
        @pos += 1
        @col += 1
        scan_operator_symbol()
        return nil
      if nc == "\["
        if @pos + 3 < @char_count && peek_char_at(2) == "]" && peek_char_at(3) == "="
          @pos += 4
          emit(:SYMBOL, "[]=")
          return nil
        if @pos + 2 < @char_count && peek_char_at(2) == "]"
          @pos += 3
          emit(:SYMBOL, "[]")
          return nil

    # Class variable (@@name)
    if ch == "@" && @pos + 1 < @char_count && @chars[@pos + 1] == "@" && @pos + 2 < @char_count && is_ident_start?(@lc[@pos + 2])
      start_col = @col
      @pos += 2
      word = scan_ident()
      full = "@@" + word
      push_token({type: :CVAR, value: full, line: @line, col: start_col})
      @col = start_col + full.size()
      return nil

    # Positional argument: @1, @2, etc.
    if ch == "@" && @pos + 1 < @char_count && is_digit?(peek_lc_at(1)) && peek_char_at(1) != "0"
      start_col = @col
      @pos += 1
      parg_num = ""
      while @pos < @char_count && is_digit?(@lc[@pos])
        parg_num += @chars[@pos]
        @pos += 1
      push_token({type: :PARG, value: parg_num, line: @line, col: start_col})
      @col = start_col + 1 + parg_num.size()
      return nil

    # Regex capture variable: $1, $2, etc.
    if @regex_capture_scope && ch == "$" && @pos + 1 < @char_count && is_digit?(peek_lc_at(1)) && peek_char_at(1) != "0" && !(@pos + 2 < @char_count && is_digit?(@lc[@pos + 2])) && !(@pos + 3 < @char_count && @chars[@pos + 2] == "." && is_digit?(@lc[@pos + 3]))
      start_col = @col
      @pos += 1
      capture_num = ""
      while @pos < @char_count && is_digit?(@lc[@pos])
        capture_num += @chars[@pos]
        @pos += 1
      push_token({type: :REGEX_CAPTURE, value: capture_num, line: @line, col: start_col})
      @col = start_col + 1 + capture_num.size()
      return nil

    # Instance variable
    if ch == "@" && @pos + 1 < @char_count && is_ident_start?(peek_lc_at(1))
      start_col = @col
      @pos += 1
      word = scan_ident()
      full = "@" + word
      push_token({type: :IVAR, value: full, line: @line, col: start_col})
      @col = start_col + full.size()
      return nil

    # Multi-char currency prefix: C$10, A$10, R$10 (must check before class name)
    if (ch == "C" || ch == "A" || ch == "R") && @pos + 1 < @char_count && @chars[@pos + 1] == "$" && @pos + 2 < @char_count && is_digit?(@lc[@pos + 2])
      scan_currency_signed()
      return nil

    # Char literal: U+0041, U+10FFFF
    if ch == "U" && @pos + 1 < @char_count && @chars[@pos + 1] == "+" && @pos + 2 < @char_count && is_hex_char?(@lc[@pos + 2])
      scan_codepoint_literal()
      return nil

    # Class name (uppercase start)
    if is_upper?(cp)
      word = scan_class_name()
      emit(:NAME, word)
      return nil

    # Signed currency literal: -$5.25, +€100, -C$10
    if (ch == "-" || ch == "+") && @pos + 1 < @char_count
      nc = @chars[@pos + 1]
      if is_currency_prefix?(nc) && @pos + 2 < @char_count && is_digit?(@lc[@pos + 2])
        scan_currency_signed()
        return nil
      if (nc == "C" || nc == "A" || nc == "R") && @pos + 2 < @char_count && @chars[@pos + 2] == "$" && @pos + 3 < @char_count && is_digit?(@lc[@pos + 3])
        scan_currency_signed()
        return nil

    # Global variable
    if ch == "$" && @pos + 1 < @char_count && is_ident_start?(@lc[@pos + 1])
      @pos += 1
      word = scan_ident()
      emit(:GLOBAL, "$" + word)
      return nil

    # Currency literal: $123.45, €100, ₹500
    if is_currency_prefix?(ch) && @pos + 1 < @char_count && is_digit?(@lc[@pos + 1])
      scan_currency_signed()
      return nil

    # Raw WValue literal: u0x followed by exactly 16 hex digits
    if ch == "u" && @pos + 2 < @char_count && @chars[@pos + 1] == "0" && @chars[@pos + 2] == "x"
      scan_wvalue()
      return nil

    # Float literal with ~ prefix: ~3.14, ~-1.5e-3
    if ch == "~" && @pos + 1 < @char_count
      nc = @chars[@pos + 1]
      if is_digit?(@lc[@pos + 1])
        @pos += 1
        scan_number()
        # Override the token type to FLOAT (scan_number emits DECIMAL for dotted numbers)
        if @token_count > 0
          last = @last_token
          if last[:type] == :DECIMAL || last[:type] == :INT
            last[:type] = :FLOAT
            @last_token_type = :FLOAT
        return nil
      if (nc == "-" || nc == "+") && @pos + 2 < @char_count && is_digit?(@lc[@pos + 2])
        sign = nc
        @pos += 2
        scan_number()
        if @token_count > 0
          last = @last_token
          if last[:type] == :DECIMAL || last[:type] == :INT
            last[:type] = :FLOAT
            @last_token_type = :FLOAT
          if sign == "-"
            last[:value] = "-" + last[:value]
        return nil

    # UUID literal (must check before number — UUIDs start with hex digits)
    if is_hex_char?(cp) && try_scan_uuid()
      return nil

    # Number (may become QUANTITY or DURATION with suffix)
    if is_digit?(cp)
      scan_number()
      return nil

    # Two-character operators (check before single-char)
    if @pos + 1 < @char_count
      next_ch = @chars[@pos + 1]
      two = ch + next_ch

      if two == "->"
        # Lambda arity: ->/2, ->/*,  ->/&
        if @pos + 3 < @char_count && @chars[@pos + 2] == "/"
          lac = @chars[@pos + 3]
          if lac == "*" || lac == "&"
            @pos += 4
            emit(:LAMBDA_ARITY, "->/" + lac)
            return nil
          if is_digit?(@lc[@pos + 3])
            @pos += 3
            arity = ""
            while @pos < @char_count && is_digit?(@lc[@pos])
              arity += @chars[@pos]
              @pos += 1
            emit(:LAMBDA_ARITY, "->/" + arity)
            return nil
        @pos += 2
        emit(:ARROW, "->")
        return nil

      if two == "<<"
        # Heredoc: <<~DELIM (always heredoc, no context check needed)
        if @pos + 2 < @char_count && @chars[@pos + 2] == "~"
          scan_heredoc()
          return nil
        @pos += 2
        last_type = nil
        if @token_count > 0
          last_type = @last_token_type
        if is_value_type?(last_type)
          emit(:LSHIFT, "<<")
        else
          emit(:PUTS_OP, "<<")
        return nil

      if two == "<-"
        @pos += 2
        emit(:PRINT_OP, "<-")
        return nil

      if two == "<!"
        @pos += 2
        emit(:RAISE_OP, "<!")
        return nil

      if two == "=>"
        @pos += 2
        emit(:FAT_ARROW, "=>")
        return nil

      if two == "=="
        @pos += 2
        emit(:EQ, "==")
        return nil

      if two == "=~"
        @pos += 2
        emit(:MATCH, "=~")
        return nil

      if two == "!="
        @pos += 2
        emit(:NEQ, "!=")
        return nil

      if two == "<="
        @pos += 2
        emit(:LTE, "<=")
        return nil

      if two == ">>"
        @pos += 2
        emit(:RSHIFT, ">>")
        return nil

      if two == ">="
        @pos += 2
        emit(:GTE, ">=")
        return nil

      if two == "&."
        @pos += 2
        emit(:SAFE_NAV, "&.")
        return nil

      if two == "&&"
        @pos += 2
        emit(:AND, "&&")
        return nil

      if two == "||" && @pos + 2 < @char_count && @chars[@pos + 2] == "="
        @pos += 3
        emit(:OR_ASSIGN, "||=")
        return nil

      if two == "||"
        @pos += 2
        emit(:OR, "||")
        return nil

      if two == "|>"
        @pos += 2
        emit(:PIPE_FWD, "|>")
        return nil

      if two == "++"
        @pos += 2
        emit(:PLUS_PLUS, "++")
        return nil

      if two == "+="
        @pos += 2
        emit(:PLUS_EQ, "+=")
        return nil

      if two == "--"
        @pos += 2
        emit(:MINUS_MINUS, "--")
        return nil

      if two == "-="
        @pos += 2
        emit(:MINUS_EQ, "-=")
        return nil

      if two == "**"
        @pos += 2
        emit(:POW, "**")
        return nil

      if two == "*="
        @pos += 2
        emit(:STAR_EQ, "*=")
        return nil

      if two == "/="
        @pos += 2
        emit(:SLASH_EQ, "/=")
        return nil

      if two == "%="
        @pos += 2
        emit(:PERCENT_EQ, "%=")
        return nil

    # Single-character operators and delimiters
    if ch == "+"
      @pos += 1
      last_type = nil
      if @token_count > 0
        last_type = @last_token_type
      if is_value_type?(last_type)
        emit(:PLUS, "+")
      else
        emit(:CLASS_DEF, "+")
      return nil

    if ch == "-"
      @pos += 1
      emit(:MINUS, "-")
      return nil

    if ch == "*"
      @pos += 1
      emit(:STAR, "*")
      return nil

    if ch == "/"
      last_type = nil
      if @token_count > 0
        last_type = @last_token_type
      if !is_value_type?(last_type) && peek_char_at(1) != "/" && peek_char_at(1) != "=" && regex_literal_ahead?()
        scan_regex()
        return nil
      # MAP: /method_name (value-expected context only)
      if @pos + 1 < @char_count && is_ident_start?(@lc[@pos + 1])
        if !is_value_type?(last_type)
          @pos += 1
          emit(:MAP, "/")
          return nil
      @pos += 1
      emit(:SLASH, "/")
      return nil

    if ch == "%"
      # %w[...] word array, %i[...] symbol array
      if @pos + 2 < @char_count && @chars[@pos + 1] == "w" && @chars[@pos + 2] == "\["
        @pos += 3
        @col += 3
        scan_word_array()
        return nil
      if @pos + 2 < @char_count && @chars[@pos + 1] == "i" && @chars[@pos + 2] == "\["
        @pos += 3
        @col += 3
        scan_symbol_array()
        return nil
      @pos += 1
      emit(:PERCENT, "%")
      return nil

    if ch == "<"
      @pos += 1
      emit(:LT, "<")
      return nil

    if ch == ">"
      @pos += 1
      emit(:GT, ">")
      return nil

    if ch == "="
      @pos += 1
      emit(:ASSIGN, "=")
      return nil

    if ch == "!"
      @pos += 1
      emit(:BANG, "!")
      return nil

    if ch == "."
      if @pos + 2 < @char_count && @chars[@pos + 1] == "." && @chars[@pos + 2] == "."
        @pos += 3
        emit(:DOTDOTDOT, "...")
        return nil
      if @pos + 1 < @char_count && @chars[@pos + 1] == "."
        @pos += 2
        emit(:DOTDOT, "..")
        return nil
      @pos += 1
      emit(:DOT, ".")
      return nil

    if ch == ","
      @pos += 1
      emit(:COMMA, ",")
      return nil

    if ch == "&"
      if @pos + 1 < @char_count && @chars[@pos + 1] == "("
        @pos += 2
        emit(:BLOCK_CALL, "&(")
        return nil
      @pos += 1
      emit(:AMPERSAND, "&")
      return nil

    if ch == "|"
      @pos += 1
      emit(:PIPE, "|")
      return nil

    if ch == "^"
      @pos += 1
      emit(:CARET, "^")
      return nil

    if ch == "("
      @paren_depth += 1
      @pos += 1
      emit(:LPAREN, "(")
      return nil

    if ch == ")"
      if @paren_depth > 0
        @paren_depth -= 1
      @pos += 1
      emit(:RPAREN, ")")
      return nil

    if ch == "{"
      @paren_depth += 1
      @pos += 1
      emit(:LBRACE, "{")
      return nil

    if ch == "}"
      if @paren_depth > 0
        @paren_depth -= 1
      @pos += 1
      emit(:RBRACE, "}")
      return nil

    if ch == "\["
      @paren_depth += 1
      @pos += 1
      emit(:LBRACKET, "\[")
      return nil

    if ch == "]"
      if @paren_depth > 0
        @paren_depth -= 1
      @pos += 1
      emit(:RBRACKET, "]")
      return nil

    if ch == "?"
      @pos += 1
      emit(:QUESTION, "?")
      return nil

    if ch == ":"
      @pos += 1
      emit(:COLON, ":")
      return nil

    if ch == ";"
      @pos += 1
      emit(:SEMICOLON, ";")
      return nil

    # Magic constants (__FILE__, __LINE__, __DIR__)
    if ch == "_" && match_ahead?("__FILE__")
      @pos += 8
      emit(:MAGIC_FILE, "__FILE__")
      return nil
    if ch == "_" && match_ahead?("__LINE__")
      @pos += 8
      emit(:MAGIC_LINE, "__LINE__")
      return nil
    if ch == "_" && match_ahead?("__DIR__")
      @pos += 7
      emit(:MAGIC_DIR, "__DIR__")
      return nil

    # Greek/math symbols as identifiers: π, τ, ∞, etc.
    if is_greek_math?(ch)
      word = StringBuffer(8)
      while @pos < @char_count && (is_greek_math?(@chars[@pos]) || is_subscript?(@chars[@pos]))
        word << @chars[@pos]
        @pos += 1
      emit(:ID, word.to_s())
      return nil

    # Superscript digits: ⁰¹²³⁴⁵⁶⁷⁸⁹
    if is_superscript_digit?(ch)
      word = StringBuffer(8)
      while @pos < @char_count && is_superscript_digit?(@chars[@pos])
        word << @chars[@pos]
        @pos += 1
      emit(:SUPERSCRIPT, word.to_s())
      return nil

    # Identifier or keyword
    if is_ident_start?(cp)
      word = scan_ident()
      if word.include?("__")
        raise {rt: :compile_error, code: :E_LEX_RESERVED_IDENT, message: "'__' is not allowed in identifiers (reserved for magic constants)", file: @file, row: @line, col: @col, span_length: word.size()}
      if word.starts_with?("_w_")
        raise {rt: :compile_error, code: :E_LEX_RESERVED_IDENT, message: "'_w_' prefix is reserved for internal use", file: @file, row: @line, col: @col, span_length: word.size()}
      if is_keyword?(word)
        use_statement = @last_token_type == nil || @last_token_type == :NEWLINE || @last_token_type == :INDENT || @last_token_type == :DEDENT || @last_token_type == :SEMICOLON
        if word == "use" && use_statement
          emit(:KEYWORD, word)
          scan_use_path()
        else
          emit(:KEYWORD, word)
      elsif is_type_name?(word)
        emit(:TYPE, word)
      else
        emit(:ID, word)
      return nil

    raise {rt: :compile_error, code: :E_LEX_UNEXPECTED_CHAR, message: "Unexpected character '[ch]'", file: @file, row: @line, col: @col, span_length: 1}
  -> match_ahead?(expected)
    len = expected.size()
    if @pos + len > @char_count
      return false
    i = 0
    while i < len
      if @chars[@pos + i] != expected[i]
        return false
      i += 1
    # Ensure the match isn't followed by an ident char
    if @pos + len < @char_count && is_ident_char?(@lc[@pos + len])
      return false
    true

  -> regex_literal_ahead?
    i = @pos + 1
    escaped = false
    in_class = false
    while i < @char_count
      ch = @chars[i]
      if ch == "\n"
        return false
      if escaped
        escaped = false
      elsif ch == "\\"
        escaped = true
      elsif ch == "\["
        in_class = true
      elsif ch == "]"
        in_class = false
      elsif ch == "/" && !in_class
        return true
      i += 1
    false

  -> scan_regex
    start_col = @col
    @pos += 1
    @col += 1
    pattern = StringBuffer(32)
    escaped = false
    in_class = false

    while @pos < @char_count
      ch = @chars[@pos]
      if ch == "\n"
        raise {rt: :compile_error, code: :E_LEX_UNTERMINATED_REGEX, message: "Unterminated regex literal", file: @file, row: @line, col: start_col, span_length: 1}
      if escaped
        pattern << "\\"
        pattern << ch
        escaped = false
        @pos += 1
        @col += 1
      elsif ch == "\\"
        escaped = true
        @pos += 1
        @col += 1
      elsif ch == "\["
        in_class = true
        pattern << ch
        @pos += 1
        @col += 1
      elsif ch == "]"
        in_class = false
        pattern << ch
        @pos += 1
        @col += 1
      elsif ch == "/" && !in_class
        @pos += 1
        @col += 1
        opts = StringBuffer(4)
        while @pos < @char_count && is_ident_char?(@lc[@pos])
          opts << @chars[@pos]
          @pos += 1
          @col += 1
        push_token({type: :REGEX, value: [pattern.to_s(), opts.to_s()], line: @line, col: start_col, file: @file})
        return nil
      else
        pattern << ch
        @pos += 1
        @col += 1

    raise {rt: :compile_error, code: :E_LEX_UNTERMINATED_REGEX, message: "Unterminated regex literal", file: @file, row: @line, col: start_col, span_length: 1}

  -> scan_use_path
    # Skip whitespace after 'use'
    while @pos < @char_count && (@chars[@pos] == " " || @chars[@pos] == "\t")
      @pos += 1
      @col += 1
    # If it's a quoted string, let normal tokenization handle it
    if @pos < @char_count && @chars[@pos] == "\""
      return nil
    # Scan non-whitespace chars as the path, leaving newline for normal emission
    path = ""
    while @pos < @char_count && @chars[@pos] != " " && @chars[@pos] != "\t" && @chars[@pos] != "\n" && @chars[@pos] != "\r" && @chars[@pos] != ";" && @chars[@pos] != "#"
      path = path + @chars[@pos]
      @pos += 1
      @col += 1
    if path.size() > 0
      emit(:STRING, path)
    nil

  -> scan_ident
    word = StringBuffer(16)
    while @pos < @char_count && is_ident_char?(@lc[@pos])
      word << @chars[@pos]
      @pos += 1
    # Trailing ? or !
    if @pos < @char_count && (@chars[@pos] == "?" || @chars[@pos] == "!")
      word << @chars[@pos]
      @pos += 1
    # Arity suffix: /N, /*, /&
    if @pos < @char_count && @chars[@pos] == "/"
      nxt_pos = @pos + 1
      if nxt_pos < @char_count
        nxt = @chars[nxt_pos]
        if nxt == "&" || nxt == "*"
          word << "/"
          word << nxt
          @pos += 2
        elsif nxt >= "0" && nxt <= "9"
          word << "/"
          @pos += 1
          while @pos < @char_count && @chars[@pos] >= "0" && @chars[@pos] <= "9"
            word << @chars[@pos]
            @pos += 1
    word.to_s()

  -> scan_class_name
    word = StringBuffer(16)
    while @pos < @char_count && is_name_char?(@lc[@pos])
      word << @chars[@pos]
      @pos += 1
    word.to_s()

  -> scan_operator_symbol
    # Called after ':' consumed. @pos is at first operator char.
    ch = @chars[@pos]
    @pos += 1
    # Try longest match first
    if @pos < @char_count
      nc = @chars[@pos]
      # Three-char: ===, <=>
      if @pos + 1 < @char_count
        nnc = @chars[@pos + 1]
        if ch == "=" && nc == "=" && nnc == "="
          @pos += 2
          emit(:SYMBOL, "===")
          return nil
        if ch == "<" && nc == "=" && nnc == ">"
          @pos += 2
          emit(:SYMBOL, "<=>")
          return nil
      # Two-char operators
      if ch == "=" && nc == "="
        @pos += 1
        emit(:SYMBOL, "==")
        return nil
      if ch == "=" && nc == "~"
        @pos += 1
        emit(:SYMBOL, "=~")
        return nil
      if ch == "<" && nc == "="
        @pos += 1
        emit(:SYMBOL, "<=")
        return nil
      if ch == ">" && nc == "="
        @pos += 1
        emit(:SYMBOL, ">=")
        return nil
      if ch == "<" && nc == "<"
        @pos += 1
        emit(:SYMBOL, "<<")
        return nil
      if ch == ">" && nc == ">"
        @pos += 1
        emit(:SYMBOL, ">>")
        return nil
      if ch == "*" && nc == "*"
        @pos += 1
        emit(:SYMBOL, "**")
        return nil
      if (ch == "+" || ch == "-" || ch == "~" || ch == "!") && nc == "@"
        @pos += 1
        emit(:SYMBOL, ch + "@")
        return nil
    # Single-char operator symbol
    emit(:SYMBOL, ch)

  -> handle_indentation
    @at_line_start = false

    # Measure leading whitespace
    indent = 0
    while @pos < @chars.size() && (@chars[@pos] == " " || @chars[@pos] == "\t")
      indent += 1
      @pos += 1

    # Check for blank line
    if @pos >= @chars.size()
      @col = indent + 1
      return nil

    ch = @chars[@pos]

    if ch == "\n"
      @pos += 1
      @line += 1
      @col = 1
      @at_line_start = true
      return nil

    # Shebang (#!): skip this line and the next if it starts with "exec "
    if ch == "#" && @pos + 1 < @chars.size() && @chars[@pos + 1] == "!"
      while @pos < @chars.size() && @chars[@pos] != "\n"
        @pos += 1
      if @pos < @chars.size()
        @pos += 1
      @line += 1
      @col = 1
      # Skip exec line if present
      if @pos + 4 < @chars.size() && @chars[@pos] == "e" && @chars[@pos + 1] == "x" && @chars[@pos + 2] == "e" && @chars[@pos + 3] == "c" && @chars[@pos + 4] == " "
        while @pos < @chars.size() && @chars[@pos] != "\n"
          @pos += 1
        if @pos < @chars.size()
          @pos += 1
        @line += 1
        @col = 1
      @at_line_start = true
      return nil

    # Comment-only line (but not ## type hints)
    if ch == "#" && !(@pos + 1 < @chars.size() && @chars[@pos + 1] == "#")
      while @pos < @chars.size() && @chars[@pos] != "\n"
        @pos += 1
      if @pos < @chars.size()
        @pos += 1
      @line += 1
      @col = 1
      @at_line_start = true
      return nil

    # Inside parens/brackets: suppress INDENT/DEDENT, just update column
    @col = indent + 1
    if @paren_depth > 0
      return nil

    # Real content — process indentation
    current_indent = @indent_stack.last()

    if indent > current_indent
      @indent_stack.push(indent)
      emit(:INDENT, nil)
    elsif indent < current_indent
      while @indent_stack.last() > indent
        @indent_stack.pop()
        emit(:DEDENT, nil)
