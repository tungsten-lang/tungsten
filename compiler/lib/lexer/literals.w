+ Lexer
  -> new(source, @file = nil)
    @source = strip_bash_shebang(source)
    @chars = @source.chars()
    # LexChars are tagged WValues stored in physical 64-bit slots. Keep the
    # ivar as w64[] so ordinary reads return those bits unchanged; treating the
    # slots as numeric i64[] boxes the negative 0xFFFC... word as a BigInt.
    set_lexchars(@source.lchs("tungsten"))
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
    # Canonical tagless packed-token stream. The native scanner stages numeric
    # descriptors in i64[] before these values cross into the boxed Array.
    # Parser sites read them via tok_type/tok_off/tok_len helpers; no hashes
    # are built.
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

  # The typed @-parameter is the compiler's ordinary-object ivar contract.
  # It keeps @lc in raw WValue-slot representation at every read site.
  -> set_lexchars(@lc) (w64[])
    self

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
    (wvalue_bits(lc) & 8) != 0

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
    cp = lc_cp(@lc[pos])
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
