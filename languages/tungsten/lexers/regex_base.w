use regex_helpers

+ RegexBase
  -> new(source, @file = nil)
    @source = strip_bash_shebang(source)
    @chars = @source.chars()
    @lc = @source.lchs()
    @char_count = @chars.size()
    @pos = 0
    @line = 1
    @col = 1
    @tokens = []
    @token_count = 0
    @last_token = nil
    @last_token_type = nil
    @indent_stack = [0]
    @at_line_start = true
    @paren_depth = 0
    @regex_capture_scope = false

  -> push_token(tok)
    @tokens.push(tok)
    @token_count += 1
    @last_token = tok
    @last_token_type = tok[:type]
    if tok[:type] == :REGEX
      @regex_capture_scope = true
    if tok[:type] == :NEWLINE || tok[:type] == :SEMICOLON
      @regex_capture_scope = false

  -> emit(type, value)
    push_token({type: type, value: value, line: @line, col: @col, file: @file})
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

    # Check for unit suffix → quantity (e.g. 3kg, 5.25m)
    if @pos < @chars.size() && is_alpha?(@lc[@pos])
      unit = scan_unit_suffix()
      if unit != nil
        emit(:QUANTITY, [num, unit])
        return nil

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
        raise {rt: :compile_error, code: :E_LEX_WVALUE_HEX_LENGTH, message: "WValue literal must use exactly 16 hex digits", file: @file, row: @line, col: @col, span_length: 1}
      num += @chars[@pos]
      @pos += 1
      count += 1
    if count != 16
      raise {rt: :compile_error, code: :E_LEX_WVALUE_HEX_LENGTH, message: "WValue literal must use exactly 16 hex digits", file: @file, row: @line, col: @col, span_length: 1}
    if @pos < @chars.size() && (@chars[@pos] == "_" || is_hex_char?(@lc[@pos]))
      raise {rt: :compile_error, code: :E_LEX_WVALUE_HEX_LENGTH, message: "WValue literal must use exactly 16 hex digits", file: @file, row: @line, col: @col, span_length: 1}
    emit(:WVALUE, num)

  -> is_hex_char?(lc)
    (lc & 8) != 0

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

  -> scan_unit_suffix
    # Scan a unit suffix: sequence of alpha chars (e.g. kg, m, Hz).
    # Also allow / and · for compound units (m/s, kg·m), digits for exponents (m2),
    # subscript digits/letters (g₀, mₚₗ), and superscript digits/sign (m², cm⁻¹).
    saved_pos = @pos
    unit = ""
    while @pos < @chars.size() && (is_alpha?(@lc[@pos]) || @chars[@pos] == "/" || @chars[@pos] == "·" || @chars[@pos] == "*" || @chars[@pos] == "^" || (@chars[@pos] >= "0" && @chars[@pos] <= "9" && unit.size() > 0) || is_subscript?(@chars[@pos]) || is_superscript_char?(@chars[@pos]))
      unit += @chars[@pos]
      @pos += 1
    if unit.size() > 0
      return unit
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
            # \e[ is a common ANSI prefix — consume the [ too to avoid triggering interpolation
            if @pos + 2 < @chars.size() && @chars[@pos + 2] == "\["
              str += "\e\["
              @pos += 3
              @col += 3
            else
              str += "\e"
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

      # String interpolation — [] (empty) is literal, not interpolation
      if ch == "\[" && @pos + 1 < @chars.size() && @chars[@pos + 1] != "]"
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

    raise {rt: :compile_error, code: :E_LEX_UNTERMINATED_STRING, message: "Unterminated string", file: @file, row: start_line, col: start_col, span_length: 1}

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

      raise {rt: :compile_error, code: :E_LEX_BYTEARRAY_BAD_CHAR, message: "Unexpected character in byte array: [ch]", file: @file, row: @line, col: @col, span_length: 1}

    raise {rt: :compile_error, code: :E_LEX_UNTERMINATED_BYTEARRAY, message: "Unterminated byte array", file: @file, row: @line, col: @col, span_length: 1}

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
    push_token({type: :COLOR, value: [r, g, b, a], line: @line, col: start_col})
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
          raise {rt: :compile_error, code: :E_LEX_EMPTY_KEY, message: "Empty key literal", file: @file, row: @line, col: @col, span_length: 1}
        emit(:KEY, result)
        return nil
      if ch == "\n"
        raise {rt: :compile_error, code: :E_LEX_UNTERMINATED_KEY, message: "Unterminated key literal", file: @file, row: @line, col: @col, span_length: 1}
      content << ch
      @pos += 1
      @col += 1
    raise {rt: :compile_error, code: :E_LEX_UNTERMINATED_KEY, message: "Unterminated key literal", file: @file, row: @line, col: @col, span_length: 1}

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
      raise {rt: :compile_error, code: :E_LEX_CHAR_HEX_LENGTH, message: "Codepoint literal U+ requires 4-6 hex digits", file: @file, row: @line, col: start_col, span_length: 1}
    codepoint = hex_str.to_i(16)
    if codepoint > 1114111
      raise {rt: :compile_error, code: :E_LEX_CHAR_UNICODE_RANGE, message: "Codepoint literal U+[hex_str] exceeds Unicode range", file: @file, row: @line, col: start_col, span_length: 1}
    if codepoint >= 55296 && codepoint <= 57343
      raise {rt: :compile_error, code: :E_LEX_CHAR_SURROGATE, message: "Codepoint literal U+[hex_str] is a Unicode surrogate", file: @file, row: @line, col: start_col, span_length: 1}
    push_token({type: :CODEPOINT, value: codepoint, line: @line, col: start_col})

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
    raise {rt: :compile_error, code: :E_LEX_UNTERMINATED_PW, message: "Unterminated %w[] literal", file: @file, row: @line, col: @col, span_length: 1}

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
    raise {rt: :compile_error, code: :E_LEX_UNTERMINATED_PI, message: "Unterminated %i[] literal", file: @file, row: @line, col: @col, span_length: 1}

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
      raise {rt: :compile_error, code: :E_LEX_HEREDOC_NO_DELIM, message: "Expected delimiter after <<~", file: @file, row: @line, col: @col, span_length: 1}
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
    raise {rt: :compile_error, code: :E_LEX_UNTERMINATED_HEREDOC, message: "Unterminated heredoc (expected [delim_str])", file: @file, row: start_line, col: 1, span_length: 1}
