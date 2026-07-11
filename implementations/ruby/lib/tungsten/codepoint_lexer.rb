# frozen_string_literal: true

require "tungsten"
require "tungsten/lexer"

module Tungsten
  # Experimental byte/codepoint-dispatch lexer.
  #
  # This is intentionally side-by-side with Lexer. The regex lexer remains the
  # readable reference; this class is a spike for measuring the ceiling on a
  # manual scanner ported from compiler/lib/lexer.w.
  class CodepointLexer
    attr_accessor :file
    attr_reader :profile_branch_counts, :profile_regex_attempts, :profile_regex_hits, :profile_token_counts,
                :profile_path_counts

    KEYWORDS_BY_FIRST_AND_LENGTH = Lexer::KEYWORDS.each_with_object({}) do |kw, groups|
      next unless kw.getbyte(0) >= 97

      by_length = groups[kw.getbyte(0)] ||= {}
      (by_length[kw.bytesize] ||= []) << [kw, kw.to_sym]
    end.each_value do |by_length|
      by_length.transform_values!(&:freeze)
      by_length.freeze
    end.freeze
    TYPE_NAMES_BY_FIRST_AND_LENGTH = Lexer::TYPE_NAMES.each_with_object({}) do |name, groups|
      by_length = groups[name.getbyte(0)] ||= {}
      (by_length[name.bytesize] ||= []) << name
    end.each_value do |by_length|
      by_length.transform_values!(&:freeze)
      by_length.freeze
    end.freeze
    TYPE_NAMES = Lexer::TYPE_NAMES.to_h { |name| [name, true] }.freeze

    ONE_CHAR_TOKENS = {
      33 => :"!", 36 => :"$", 37 => :%, 38 => :&, 40 => :"(", 41 => :")", 42 => :*, 43 => :+,
      44 => :",", 45 => :-, 46 => :".", 47 => :/, 58 => :":", 59 => :";", 60 => :<, 61 => :"=",
      62 => :>, 63 => :"?", 64 => :"@", 91 => :"[", 93 => :"]", 94 => :^, 123 => :"{", 124 => :|,
      125 => :"}", 126 => :~
    }.freeze

    SYMBOL_OPERATORS = [
      ":[]=", ":[]", ":<=>", ":===", ":==", ":<=", ":>=", ":=~", ":<<", ":>>", ":+@", ":-@", ":~@",
      ":!@", ":**", ":+", ":-", ":*", ":/", ":~", ":!", ":%", ":^", ":&", ":<", ":>", ":|"
    ].freeze

    SUBSCRIPT_TAIL = /[₀₁₂₃₄₅₆₇₈₉ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓₔ]+/.freeze
    SUPERSCRIPT_DIGITS = /[⁰¹²³⁴⁵⁶⁷⁸⁹]+/.freeze
    # Δ[ident] is the delta notation (an undefined Δx reads as `x - x'`).
    UNICODE_IDENTIFIER = /[πτϕφℯℇ∞ℎℏσεμµ][₀₁₂₃₄₅₆₇₈₉ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓₔ]*|Δ[a-z0-9_]*|°[\p{L}]+/.freeze
    BYTE_ARRAY_BINARY = /0b([01](?:_?[01])*)/.freeze
    BYTE_ARRAY_OCTAL = /0o([0-7](?:_?[0-7])*)/.freeze
    BYTE_ARRAY_DECIMAL = /0d(\d(?:_?\d)*)/.freeze
    BYTE_ARRAY_HEX_PREFIX = /0x(\h(?:_?\h)*)/.freeze
    BYTE_ARRAY_HEX = /(\h{1,2})/.freeze

    REGEX_PROFILE_NAMES = {
      Lexer::CIDR6 => :CIDR6,
      Lexer::IP6 => :IP6,
      Lexer::CIDR4 => :CIDR4,
      Lexer::IP4 => :IP4,
      Lexer::MAC => :MAC,
      Lexer::UUID => :UUID,
      Lexer::DATETIME => :DATETIME,
      Lexer::TIME => :TIME,
      Lexer::DATE => :DATE,
      Lexer::WEEK => :WEEK,
      Lexer::INVALID_WEEK => :INVALID_WEEK,
      Lexer::MONTH => :MONTH,
      Lexer::CURRENCY => :CURRENCY,
      Lexer::DURATION => :DURATION,
      Lexer::UNIT_STRING => :UNIT_STRING,
      SUBSCRIPT_TAIL => :SUBSCRIPT_TAIL,
      SUPERSCRIPT_DIGITS => :SUPERSCRIPT_DIGITS,
      UNICODE_IDENTIFIER => :UNICODE_IDENTIFIER,
      BYTE_ARRAY_BINARY => :BYTE_ARRAY_BINARY,
      BYTE_ARRAY_OCTAL => :BYTE_ARRAY_OCTAL,
      BYTE_ARRAY_DECIMAL => :BYTE_ARRAY_DECIMAL,
      BYTE_ARRAY_HEX_PREFIX => :BYTE_ARRAY_HEX_PREFIX,
      BYTE_ARRAY_HEX => :BYTE_ARRAY_HEX
    }.freeze

    def initialize(code, profile: false)
      @token = Token.new
      @source = clean(code)
      @length = @source.bytesize
      @pos = 0
      @row = 1
      @col = 1
      @indent = 0
      @indebt = 0
      @dedebt = 0
      @bracket_depth = 0
      @line_start = true
      @last_significant_token_type = nil
      @regex_capture_scope = false
      @profile_enabled = profile
      @profile_branch_counts = Hash.new(0) if profile
      @profile_regex_attempts = Hash.new(0) if profile
      @profile_regex_hits = Hash.new(0) if profile
      @profile_token_counts = Hash.new(0) if profile
      @profile_path_counts = Hash.new(0) if profile

      handle_indentation
    end

    def clean(code)
      copy = code.dup
      copy.gsub!(BOM, "")
      copy.gsub!(TRAILING_SPACE, "")
      copy.sub!(/\A(#![^\n]*bash[^\n]*\n)exec /, '\1#exec ')
      copy
    end

    def tokens
      list = []
      list << next_token.clone until @token.type?(:EOF)
      list
    end

    def next_token
      if @indebt > 0
        @indebt -= 1
        @indent += 1
        set_token(:INDENT)
        @line_start = true
      elsif @dedebt > 0
        @dedebt -= 1
        @indent -= 1
        set_token(:DEDENT)
        @line_start = true
      else
        scan_token
      end

      @regex_capture_scope = false if %i[NL ;].include?(@token.type)
      @regex_capture_scope = true if @token.type == :REGEX

      # Track open-bracket nesting so indentation inside a multi-line
      # (...)/[...]/{...} is treated as line-continuation, not as block
      # structure (see handle_indentation).
      case @token.type
      when :"(", :"[", :"{"
        @bracket_depth += 1
      when :")", :"]", :"}"
        @bracket_depth -= 1 if @bracket_depth.positive?
      end

      @line_start = false unless %i[INDENT DEDENT NL SP SHEBANG].include?(@token.type)
      @last_significant_token_type = @token.type unless %i[INDENT DEDENT NL SP SHEBANG].include?(@token.type)
      @token
    end

    def string
      @source
    end

    def pos
      @pos
    end

    def pos=(new_pos)
      @pos = new_pos
      sync_position
    end

    def eos?
      eof?
    end

    def rest
      @source.byteslice(@pos, @length - @pos)
    end

    def scan(pattern)
      text = match_scanner_pattern(pattern)
      return nil unless text

      advance_text(text)
      text
    end

    def skip(pattern)
      text = scan(pattern)
      text&.bytesize
    end

    def check(pattern)
      match_scanner_pattern(pattern)
    end

    private

    def set_token(type, value = nil, row = @row, col = @col)
      @token.reset_location
      @token.file = @file
      @token.row = row
      @token.col = col
      @token.type = type
      @token.value = value
      @profile_token_counts[type] += 1 if @profile_enabled
    end

    def profile_path(name)
      @profile_path_counts[name] += 1 if @profile_enabled
    end

    def error(msg)
      err = Error.new("syntax on line #{@row}: #{msg}")
      err.location = Location.new(@file, @row, @col)
      err.source_code = @source
      err.file_path = @file
      raise err
    end

    def byte(offset = 0)
      @source.getbyte(@pos + offset)
    end

    def eof?
      @pos >= @length
    end

    def slice(start_pos, end_pos = @pos)
      @source.byteslice(start_pos, end_pos - start_pos)
    end

    def advance(count = 1)
      @pos += count
      @col += count
    end

    def advance_text(text)
      @pos += text.bytesize
      line_start = 0
      newline_count = 0
      text.each_byte.with_index do |b, i|
        next unless b == 10

        newline_count += 1
        line_start = i + 1
      end

      if newline_count.zero?
        @col += text.bytesize
      else
        @row += newline_count
        @col = text.bytesize - line_start + 1
        @line_start = true
      end
    end

    def sync_position
      @row = 1
      @col = 1
      p = 0
      while p < @pos
        if @source.getbyte(p) == 10
          @row += 1
          @col = 1
        else
          @col += 1
        end
        p += 1
      end
    end

    def match_scanner_pattern(pattern)
      case pattern
      when String
        match_bytes?(pattern) ? pattern : nil
      when Regexp
        match_regex_at(pattern)&.[](0)
      else
        raise TypeError, "expected String or Regexp"
      end
    end

    def newline_byte?(b)
      b == 10
    end

    def space_byte?(b)
      b == 32
    end

    def digit_byte?(b)
      b && b >= 48 && b <= 57
    end

    def sign_byte?(b)
      b == 43 || b == 45
    end

    def unicode_minus_at?(offset = 0)
      @source.byteslice(@pos + offset, 3) == "−"
    end

    def unicode_rational_slash_at?(position = @pos)
      slash = @source.byteslice(position, 3)
      slash == "⁄" || slash == "∕"
    end

    def consume_number_sign
      if sign_byte?(byte)
        advance
      elsif unicode_minus_at?
        advance_utf8_char
      end
    end

    def lower_byte?(b)
      b && b >= 97 && b <= 122
    end

    def upper_byte?(b)
      b && b >= 65 && b <= 90
    end

    def alpha_byte?(b)
      lower_byte?(b) || upper_byte?(b)
    end

    def ident_start_byte?(b)
      lower_byte?(b) || b == 95
    end

    def ident_continue_byte?(b)
      ident_start_byte?(b) || digit_byte?(b)
    end

    def hex_byte?(b)
      digit_byte?(b) || (b && b >= 65 && b <= 70) || (b && b >= 97 && b <= 102)
    end

    def vigesimal_byte?(b)
      digit_byte?(b) || (b && b >= 65 && b <= 74) || (b && b >= 97 && b <= 106)
    end

    def unit_start_byte?(b)
      alpha_byte?(b) || non_ascii_byte?(b)
    end

    def non_ascii_byte?(b)
      b && b >= 128
    end

    def match_bytes?(text, offset = 0)
      len = text.bytesize
      return false if @pos + offset + len > @length

      i = 0
      while i < len
        return false unless @source.getbyte(@pos + offset + i) == text.getbyte(i)

        i += 1
      end
      true
    end

    def boundary_after?(offset)
      !ident_continue_byte?(byte(offset))
    end

    def whitespace_or_start_before?
      return true if @pos.zero?

      prev = @source.getbyte(@pos - 1)
      prev == 32 || prev == 10
    end

    def method_operator_after?(bytes)
      b = byte(bytes)
      b.nil? || b == 32 || b == 10 || b == 40
    end

    def bracket_operator_context?(bytes)
      return false unless method_operator_after?(bytes)
      return true if whitespace_or_start_before?

      prev = @source.getbyte(@pos - 1)
      ident_continue_byte?(prev) || upper_byte?(prev)
    end

    def scan_token
      if eof?
        if @indent > 0
          @dedebt = @indent
          next_token
        else
          set_token(:EOF)
        end
        return
      end

      b = byte
      @profile_branch_counts[b] += 1 if @profile_enabled

      case b
      when 32
        return scan_spaces
      when 10
        return scan_space_or_newline
      when 105, 110, 114, 116, 99, 119, 101, 112, 108, 97, 98, 100, 103,
           104, 106, 107, 109, 111, 113, 115, 118, 120, 121, 122
        return if hex_reference_literal_possible? && network_literal_shape_possible? && scan_network_literal

        return scan_identifier
      when 58
        return if byte(1) == 58 && network_literal_shape_possible? && scan_network_literal

        return scan_symbol_or_colon
      when 61
        return scan_operator_or_punctuation if byte(1) == 61 || byte(1) == 62 || byte(1) == 126

        return emit_fixed(:"=", 1)
      when 40
        return scan_operator_or_punctuation if byte(1) == 62

        return emit_fixed(:"(", 1)
      when 41
        return scan_operator_or_punctuation if byte(1) == 62

        return emit_fixed(:")", 1)
      when 44
        return emit_fixed(:",", 1)
      when 91
        return if bracketed_ip6_start? && scan_network_literal

        return emit_fixed(:"[", 1) unless byte(1) == 93
      when 93
        return scan_operator_or_punctuation if byte(1) == 62

        return emit_fixed(:"]", 1)
      when 34
        # The `"> ` operator is only valid in operator position (after a value).
        # In value position -- e.g. after `<<`, `=`, `(` -- a `"` opens a string,
        # even when its content starts with `>` followed by a terminator
        # (`out << ">;\n"`), which the bare terminator check would misread as the
        # operator. regex_literal_allowed? is true exactly in value position.
        if byte(1) == 62 && terminator_byte?(byte(2)) && !regex_literal_allowed?
          return scan_operator_or_punctuation
        end

        return scan_string
      when 102
        if (fe80_start? || (hex_reference_literal_possible? && network_literal_shape_possible?)) && scan_network_literal
          return
        end

        return scan_identifier
      when 9, 13, 12
        error "unexpected character: #{slice(@pos, @pos + 1).inspect}"
      when 35
        prev = @pos > 0 ? @source.getbyte(@pos - 1) : 0
        hash_allowed =
          color_literal_ahead? || @line_start || @last_significant_token_type.nil? || prev == 32 || prev == 9
        unless hash_allowed || byte(1) == 35 || byte(1) == 91
          error "unexpected character: #"
        end

        return scan_hash
      when 59
        return emit_fixed(:';', 1)
      when 36
        return scan_regex_capture if regex_capture_start?
        return if scan_currency_literal
        return scan_prefixed_name(:GLOBAL, 1) if ident_start_byte?(byte(1))
      when 70
        if (fe80_start? || (hex_reference_literal_possible? && network_literal_shape_possible?)) && scan_network_literal
          return
        end

        return scan_name
      when 95
        if match_bytes?("__FILE__") && boundary_after?(8)
          return emit_fixed(:MAGIC_FILE, 8)
        elsif match_bytes?("__LINE__") && boundary_after?(8)
          return emit_fixed(:MAGIC_LINE, 8)
        elsif match_bytes?("__DIR__") && boundary_after?(7)
          return emit_fixed(:MAGIC_DIR, 7)
        end
        return scan_identifier
      when 74, 67
        return if scan_currency_literal
        return if hex_reference_literal_possible? && network_literal_shape_possible? && scan_network_literal

        return scan_name
      when 43
        next_byte = byte(1)
        if next_byte == 43 || next_byte == 61 || next_byte == 64
          profile_path(:plus_operator) if @profile_enabled
          return scan_operator_or_punctuation
        end

        if digit_byte?(next_byte)
          profile_path(:plus_number) if @profile_enabled
          return scan_number
        end

        if next_byte == 126 && approximate_float_literal_possible?
          profile_path(:plus_approx_number) if @profile_enabled
          return scan_number(approx: true)
        end

        if (@pos.zero? || @line_start) && space_byte?(next_byte) && upper_byte?(byte(2))
          profile_path(:plus_class) if @profile_enabled
          return emit_fixed(:CLASS, 1)
        end

        profile_path(:plus) if @profile_enabled
        return emit_fixed(:+, 1)
      when 45
        next_byte = byte(1)
        if next_byte == 45 || next_byte == 61 || next_byte == 62 || next_byte == 64
          profile_path(:minus_operator) if @profile_enabled
          return scan_operator_or_punctuation
        end

        if digit_byte?(next_byte)
          profile_path(:minus_number) if @profile_enabled
          return scan_number
        end

        if next_byte == 126 && approximate_float_literal_possible?
          profile_path(:minus_approx_number) if @profile_enabled
          return scan_number(approx: true)
        end

        profile_path(:minus) if @profile_enabled
        return emit_fixed(:-, 1)
      when 42
        return scan_operator_or_punctuation if byte(1) == 42 || byte(1) == 61

        return emit_fixed(:*, 1)
      when 117
        return scan_wvalue if byte(1) == 48 && byte(2) == 120

        return scan_identifier
      when 80
        return if scan_duration_literal

        return scan_name
      when 85
        return scan_codepoint_literal if byte(1) == 43 && hex_byte?(byte(2))

        return scan_name
      when 126
        if digit_byte?(byte(1)) || (sign_byte?(byte(1)) && digit_byte?(byte(2))) ||
           (unicode_minus_at?(1) && digit_byte?(byte(4)))
          return scan_number(approx: true)
        end
      when 48, 49, 50, 51, 52, 53, 54, 55, 56, 57
        if radix_number_literal?
          profile_path(:digit_radix_number) if @profile_enabled
          return scan_number
        end

        if simple_number_literal?
          profile_path(:digit_number_fast) if @profile_enabled
          return scan_number
        end

        if special_decimal_literal_possible? && scan_special_decimal_literal
          profile_path(:digit_special_decimal) if @profile_enabled
          return
        end

        if rational_literal_possible? && scan_rational_literal
          profile_path(:digit_rational) if @profile_enabled
          return
        end

        if numeric_reference_possible? && scan_numeric_reference_literal
          profile_path(:digit_reference) if @profile_enabled
          return
        end

        profile_path(:digit_number) if @profile_enabled
        return scan_number
      when 64
        return scan_at
      when 65, 66, 68, 69, 71, 72, 73, 75, 76, 77, 78, 79,
           81, 82, 83, 84, 86, 87, 88, 89, 90
        return if hex_reference_literal_possible? && network_literal_shape_possible? && scan_network_literal

        return scan_name
      when 37
        return scan_percent
      when 46
        return scan_dot if byte(1) == 46

        # Phase 4e dot-prefix elementwise operators: .+ .- .* ./ .| .& .^ .<< .>>
        # Whitespace before AND after disambiguates from method-call dot
        # syntax (`a.foo` stays a method call). Without space-before, fall
        # through to the single-char `.` emit and let the parser raise on
        # `a.+` (no method-name `+` at that position).
        if whitespace_or_start_before?
          b1 = byte(1)
          b2 = byte(2)
          if b2 == 32 || b2 == 10
            return emit_operator(:".+", 2, @col) if b1 == 43
            return emit_operator(:".-", 2, @col) if b1 == 45
            return emit_operator(:".*", 2, @col) if b1 == 42
            return emit_operator(:"./", 2, @col) if b1 == 47
            return emit_operator(:".|", 2, @col) if b1 == 124
            return emit_operator(:".&", 2, @col) if b1 == 38
            return emit_operator(:".^", 2, @col) if b1 == 94
          end
          # 3-char shifts (.<< .>>)
          if b1 == 60 && byte(2) == 60 && (byte(3) == 32 || byte(3) == 10)
            return emit_operator(:".<<", 3, @col)
          end
          if b1 == 62 && byte(2) == 62 && (byte(3) == 32 || byte(3) == 10)
            return emit_operator(:".>>", 3, @col)
          end
        end

        return emit_fixed(:".", 1)
      when 47
        return scan_regex_literal if regex_literal_allowed? && byte(1) != 47 && byte(1) != 61 && regex_literal_ahead?

        return scan_slash_or_operator
      when 123
        return emit_fixed(:"{", 1)
      when 125
        return emit_fixed(:"}", 1)
      end

      scan_operator_or_punctuation
    end

    def match_regex_at(regex, pos = @pos)
      if @profile_enabled
        label = REGEX_PROFILE_NAMES[regex] || regex.source
        @profile_regex_attempts[label] += 1
      end

      match = anchored_regex(regex).match(@source.byteslice(pos, @length - pos))
      @profile_regex_hits[label] += 1 if @profile_enabled && match
      match
    end

    def anchored_regex(regex)
      @anchored_regexes ||= {}
      @anchored_regexes[regex] ||= Regexp.new("\\A(?:#{regex.source})", regex.options)
    end

    def consume_text(text, type, value = text, col = @col)
      advance(text.bytesize)
      set_token(type, value, @row, col)
      true
    end

    def scan_reference_literal
      (network_literal_shape_possible? && scan_network_literal) || scan_calendar_literal
    end

    def scan_float_literal
      match = match_regex_at(Lexer::FLOAT)
      return false unless match

      consume_text(match[0], :FLOAT)
    end

    def scan_rational_literal
      match = match_regex_at(Lexer::RATIONAL)
      return false unless match

      consume_text(match[0], :RATIONAL)
    end

    def scan_special_decimal_literal
      match = match_regex_at(Lexer::DECIMAL)
      return false unless match

      text = match[0]
      return false unless text.include?("K") || text.include?("°") || text.include?("'") ||
                          text.include?("′") || text.include?("″") || text.include?("‴") ||
                          text.start_with?("0r60-")

      consume_text(text, :DECIMAL)
    end

    def fe80_start?
      (byte == 102 || byte == 70) &&
        (byte(1) == 101 || byte(1) == 69) &&
        byte(2) == 56 &&
        byte(3) == 48 &&
        byte(4) == 58
    end

    def bracketed_ip6_start?
      (byte(1) == 58 && byte(2) == 58) ||
        ((byte(1) == 102 || byte(1) == 70) &&
         (byte(2) == 101 || byte(2) == 69) &&
         byte(3) == 56 &&
         byte(4) == 48 &&
         byte(5) == 58)
    end

    def scan_numeric_reference_literal
      (network_literal_shape_possible? && scan_network_literal) || scan_calendar_literal ||
        scan_currency_literal || scan_duration_literal
    end

    def hex_reference_literal_possible?
      return false unless hex_byte?(byte)

      p = @pos
      while p < @length
        b = @source.getbyte(p)
        return true if b == 45 || b == 46 || b == 58 || b == 47
        return false if terminator_byte?(b)

        p += 1
      end

      false
    end

    def network_literal_shape_possible?
      p = @pos
      colons = 0
      dots = 0
      hyphens = 0
      slash = false
      double_colon = false

      while p < @length
        b = @source.getbyte(p)
        break if terminator_byte?(b)

        case b
        when 58
          double_colon = true if @source.getbyte(p + 1) == 58
          colons += 1
        when 46
          dots += 1
        when 45
          hyphens += 1
        when 47
          slash = true
        end

        p += 1
      end

      double_colon || colons >= 2 || dots >= 2 || hyphens == 4 || hyphens == 5 ||
        (slash && (colons.positive? || dots >= 2))
    end

    def approximate_float_literal_possible?
      if byte == 126
        approximate_decimal_after?(@pos + 1)
      elsif sign_byte?(byte) && byte(1) == 126
        approximate_decimal_after?(@pos + 2)
      elsif unicode_minus_at? && byte(3) == 126
        approximate_decimal_after?(@pos + 4)
      else
        false
      end
    end

    def approximate_decimal_after?(index)
      return false unless digit_byte?(@source.getbyte(index))

      index += 1
      index += 1 while digit_byte?(@source.getbyte(index)) || @source.getbyte(index) == 95
      @source.getbyte(index) == 46 && digit_byte?(@source.getbyte(index + 1))
    end

    def rational_literal_possible?
      index = @pos
      if sign_byte?(@source.getbyte(index))
        index += 1
      elsif @source.byteslice(index, 3) == "−"
        index += 3
      end

      return false unless digit_byte?(@source.getbyte(index))

      index += 1
      index += 1 while digit_byte?(@source.getbyte(index)) || @source.getbyte(index) == 95

      b = @source.getbyte(index)
      return digit_byte?(@source.getbyte(index + 1)) if b == 47

      unicode_rational_slash_at?(index) && digit_byte?(@source.getbyte(index + 3))
    end

    def special_decimal_literal_possible?
      return true if match_bytes?("0r60-")

      p = @pos
      while p < @length
        b = @source.getbyte(p)
        return false if terminator_byte?(b)
        return true if special_decimal_marker_at?(p)

        p += 1
      end

      false
    end

    def special_decimal_marker_at?(pos)
      b = @source.getbyte(pos)
      b == 75 || b == 39 || bytes_at?(pos, "°") || bytes_at?(pos, "′") ||
        bytes_at?(pos, "″") || bytes_at?(pos, "‴")
    end

    def simple_number_literal?
      return false if match_bytes?("0r60-")

      p = @pos
      p += 1 while digit_byte?(@source.getbyte(p)) || @source.getbyte(p) == 95

      return true if @source.getbyte(p) == 47 || unicode_rational_slash_at?(p)

      if @source.getbyte(p) == 46 && digit_byte?(@source.getbyte(p + 1))
        p += 1
        p += 1 while digit_byte?(@source.getbyte(p)) || @source.getbyte(p) == 95
      end

      if exponent_start_at?(p)
        p += 1
        p += 1 if sign_byte?(@source.getbyte(p))
        p += 1 while digit_byte?(@source.getbyte(p))
      end

      b = @source.getbyte(p)
      terminator_byte?(b) || b == 37
    end

    def exponent_start_at?(pos)
      b = @source.getbyte(pos)
      return false unless b == 101 || b == 69

      next_byte = @source.getbyte(pos + 1)
      digit_byte?(next_byte) || (sign_byte?(next_byte) && digit_byte?(@source.getbyte(pos + 2)))
    end

    def radix_number_literal?
      byte == 48 && prefix_int_byte?(byte(1)) && !sexagesimal_decimal_prefix?
    end

    def numeric_reference_possible?
      return false if byte == 48 && prefix_int_byte?(byte(1))

      p = @pos
      p += 1 while digit_byte?(@source.getbyte(p)) || @source.getbyte(p) == 95
      b = @source.getbyte(p)
      b == 45 || b == 46 || b == 58 || unit_start_byte?(b)
    end

    def prefix_int_byte?(b)
      b == 98 || b == 66 || b == 100 || b == 111 || b == 79 || b == 114 || b == 118 || b == 120 || b == 88
    end

    def sexagesimal_decimal_prefix?
      byte(1) == 114 && byte(2) == 54 && byte(3) == 48 && byte(4) == 45
    end

    def scan_network_literal
      start_col = @col
      if (match = match_regex_at(Lexer::CIDR6))
        consume_text(match[0], :CIDR6, match[0], start_col)
      elsif (match = match_regex_at(Lexer::IP6))
        consume_text(match[0], :IP6, match[0], start_col)
      elsif (match = match_regex_at(Lexer::CIDR4))
        consume_text(match[0], :CIDR4, match[0], start_col)
      elsif (match = match_regex_at(Lexer::IP4))
        consume_text(match[0], :IP4, match[0], start_col)
      elsif (match = match_regex_at(Lexer::MAC))
        consume_text(match[0], :MAC, match[0], start_col)
      elsif (match = match_regex_at(Lexer::UUID))
        consume_text(match[0], :UUID, match[0], start_col)
      end
    end

    def scan_calendar_literal
      start_col = @col
      if (match = match_regex_at(Lexer::DATETIME))
        consume_text(match[0], :DATETIME, match[0], start_col)
      elsif (match = match_regex_at(Lexer::TIME))
        consume_text(match[0], :TIME, match[0], start_col)
      elsif (match = match_regex_at(Lexer::DATE))
        consume_text(match[0], :DATE, match[0], start_col)
      elsif (match = match_regex_at(Lexer::WEEK))
        validate_week!(match[0])
        consume_text(match[0], :WEEK, match[0], start_col)
      elsif (match = match_regex_at(Lexer::INVALID_WEEK))
        error "invalid week: #{match[0]}"
      elsif (match = match_regex_at(Lexer::MONTH))
        consume_text(match[0], :MONTH, match[0], start_col)
      end
    end

    def scan_currency_literal
      match = match_regex_at(Lexer::CURRENCY)
      return false unless match

      if match[:prefix] && ![nil, "", "/-"].include?(match[:suffix])
        error "unexpected suffix #{match[:suffix]} on currency with prefix: #{match[:prefix]}"
      end

      value = [match[:amount], match[:prefix], match[:suffix]]
      consume_text(match[0], :CURRENCY, value)
    end

    def scan_duration_literal
      match = match_regex_at(Lexer::DURATION)
      return false unless match

      validate_duration_order!(match[0])
      consume_text(match[0], :DURATION)
    end

    def validate_duration_order!(str)
      return if str.start_with?("P")

      units = str.scan(/mo|ms|[µμ]s|ns|m(?!s|o)|[ywdhms]/)
      indices = units.map { |unit| Lexer::DURATION_ORDER.index(unit.tr("μ", "µ")) }
      return if indices == indices.sort && indices.uniq == indices

      error "duration units must be in descending order: #{str}"
    end

    def validate_week!(match)
      year = match[0, 4].to_i
      week = match[6, 2].to_i
      return unless week == 53 && !iso_long_year?(year)

      error "invalid week: #{match} (#{year} has only 52 weeks)"
    end

    def iso_long_year?(year)
      dow = (1 + 5 * ((year - 1) % 4) + 4 * ((year - 1) % 100) + 6 * ((year - 1) % 400)) % 7
      leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
      dow == 4 || (leap && dow == 3)
    end

    def emit_fixed(type, bytes, value = nil)
      start_col = @col
      advance(bytes)
      set_token(type, value, @row, start_col)
    end

    def scan_spaces
      start_col = @col
      start = @pos
      advance while space_byte?(byte)
      if byte == 10
        profile_path(:spaces_before_newline) if @profile_enabled
        @pos = start
        @col = start_col
        scan_space_or_newline
      elsif byte == 35 && (space_byte?(byte(1)) || newline_byte?(byte(1)))
        profile_path(:spaces_before_comment) if @profile_enabled
        @pos = start
        @col = start_col
        scan_comment_with_prefix
      else
        profile_path(:spaces) if @profile_enabled
        set_token(:SP, nil, @row, start_col)
      end
    end

    def scan_space_or_newline
      start_col = @col
      if (count = consume_newlines)
        profile_path(:newline) if @profile_enabled
        set_token(:NL, count, @row, start_col)
        @row += count
        @col = 1
        @line_start = true
        handle_indentation
      else
        profile_path(:spaces) if @profile_enabled
        set_token(:SP, nil, @row, start_col)
      end
    end

    def consume_newlines
      p = @pos
      count = 0
      loop do
        before_spaces = p
        p += 1 while p < @length && @source.getbyte(p) == 32
        unless p < @length && @source.getbyte(p) == 10
          p = before_spaces
          break
        end

        count += 1
        p += 1
      end
      return nil if count.zero?

      @pos = p
      count
    end

    def handle_indentation
      return unless @line_start

      # Inside an open bracket (...)/[...]/{...} a newline is a line
      # continuation, not block structure: a continuation line indented deeper
      # than the body would otherwise emit a spurious INDENT (absorbed mid
      # expression) whose matching DEDENT later truncates the enclosing block.
      # Consume the leading indentation and emit no indent/dedent while nested.
      if @bracket_depth.positive?
        cp = @pos
        cp += 1 while cp < @length && @source.getbyte(cp) == 32
        @col += (cp - @pos)
        @pos = cp
        return
      end

      # Full-line comments are indentation-transparent: a comment occupying its
      # own line must not drive indent/dedent. Skip its leading spaces and defer
      # the indent computation to the next non-comment line. Otherwise a comment
      # sitting between a block body and a continuation keyword (elsif / else /
      # rescue / ensure) makes the DEDENT fire *before* the comment, and the
      # comment's own trailing NL then detaches the continuation from its opener
      # (if / begin) — surfacing as a spurious "unexpected elsif". Matches plain
      # `# ` / bare-`#` comments only; `##` and `#[`/`#hex` keep their handling.
      cp = @pos
      cp += 1 while cp < @length && @source.getbyte(cp) == 32
      if cp < @length && @source.getbyte(cp) == 35
        after = @source.getbyte(cp + 1)
        if after.nil? || after == 32 || after == 10
          @col += (cp - @pos)
          @pos = cp
          return
        end
      end

      # A bare newline (blank line) is not real content — it must not
      # trigger a dedent. This matters because scan_comment now calls
      # handle_indentation directly, and a line-ending comment may be
      # followed by a blank line; the reference Lexer's `^(?=\S)` check
      # already excludes \n, so this keeps the two lexers in parity.
      if eof? || (!space_byte?(byte) && !newline_byte?(byte))
        @dedebt += @indent
        return
      end

      p = @pos
      p += 1 while p < @length && @source.getbyte(p) == 32
      return unless p < @length && @source.getbyte(p) != 10

      spaces = p - @pos
      return if spaces.odd?

      @pos = p
      @col += spaces
      diff = (spaces / 2) - @indent
      if diff > 0
        @indebt = diff
      elsif diff < 0
        @dedebt = -diff
      end
    end

    def scan_hash
      if match_bytes?("#[")
        return scan_key_literal
      end

      return if scan_color_literal

      if match_bytes?("##")
        return scan_type_hint_or_comment
      end

      scan_comment
    end

    def color_literal_ahead?
      !color_literal_hex.nil?
    end

    def color_literal_hex
      p = @pos + 1
      p += 1 while hex_byte?(@source.getbyte(p))

      length = p - @pos - 1
      return nil unless [3, 4, 6, 8].include?(length)

      next_byte = @source.getbyte(p)
      return nil if next_byte && (alpha_byte?(next_byte) || digit_byte?(next_byte) || next_byte == 95)

      @source.byteslice(@pos + 1, length)
    end

    def scan_color_literal
      hex = color_literal_hex
      return false unless hex

      start_col = @col
      advance(hex.bytesize + 1)
      hex = hex.chars.map { |char| char * 2 }.join if hex.length == 3 || hex.length == 4
      r = hex[0..1].to_i(16)
      g = hex[2..3].to_i(16)
      b = hex[4..5].to_i(16)
      a = hex.length == 8 ? hex[6..7].to_i(16) : 255
      set_token(:COLOR, [r, g, b, a], @row, start_col)
      true
    end

    def scan_comment_with_prefix
      advance while space_byte?(byte)
      scan_comment
    end

    def scan_comment
      start_col = @col
      advance until eof? || newline_byte?(byte)
      if newline_byte?(byte)
        advance
        set_token(:NL, 1, @row, start_col)
        @row += 1
        @col = 1
        @line_start = true
        # A line-ending comment terminates the line exactly like a bare
        # newline (see scan_space_or_newline) — it must run the same
        # indentation bookkeeping, or the next line's leading spaces are
        # lexed as a mid-line :SP and the parser fails with
        # `expected 'INDENT'`.
        handle_indentation
      else
        set_token(:EOF, nil, @row, start_col)
      end
    end

    def scan_type_hint_or_comment
      after_hashes = @pos + 2
      spaces = 0
      spaces += 1 while @source.getbyte(after_hashes + spaces) == 32

      if spaces.positive? && type_hint_start?(after_hashes + spaces)
        start_col = @col
        @pos = after_hashes + spaces
        @col += 2 + spaces
        hint_start = @pos
        advance until eof? || newline_byte?(byte)
        hint = slice(hint_start).strip
        return set_token(:TYPE_HINT, hint, @row, start_col) unless hint.empty?
      end

      scan_comment
    end

    def type_hint_start?(pos)
      b = @source.getbyte(pos)
      if lower_byte?(b)
        p = pos
        p += 1 while ident_continue_byte?(@source.getbyte(p))
        return true if @source.getbyte(p) == 58
      end

      TYPE_NAMES.each_key do |name|
        len = name.bytesize
        next unless bytes_at?(pos, name)
        return true unless ident_continue_byte?(@source.getbyte(pos + len))
      end
      false
    end

    def bytes_at?(pos, text)
      return false if pos + text.bytesize > @length

      i = 0
      while i < text.bytesize
        return false unless @source.getbyte(pos + i) == text.getbyte(i)

        i += 1
      end
      true
    end

    def scan_key_literal
      start_col = @col
      @pos += 2
      @col += 2
      content_start = @pos
      advance until eof? || byte == 93
      error "unterminated key literal" if eof?

      content = slice(content_start).strip
      error "empty key literal" if content.empty?

      advance
      set_token(:KEY, content, @row, start_col)
    end

    def scan_string
      start_col = @col
      advance
      parts = []
      str = +""
      has_interp = false

      loop do
        error "unterminated string" if eof?

        case byte
        when 34
          advance
          break
        when 92
          scan_string_escape(str)
        when 91
          if byte(1) != 93 && matching_close_bracket_before_newline?(@pos + 1)
            has_interp = true
            parts << [:str, str] unless str.empty?
            str = +""
            advance
            parts << [:expr, scan_interpolation_expr]
          else
            str << "["
            advance
          end
        else
          chunk_start = @pos
          advance_utf8_char
          str << slice(chunk_start)
        end
      end

      if has_interp
        parts << [:str, str] unless str.empty?
        set_token(:STRING_INTERP, parts, @row, start_col)
      else
        set_token(:STRING, str, @row, start_col)
      end
    end

    def scan_string_escape(out)
      if match_bytes?("\\n")
        out << "\n"
        advance(2)
      elsif match_bytes?("\\r")
        out << "\r"
        advance(2)
      elsif match_bytes?("\\t")
        out << "\t"
        advance(2)
      elsif match_bytes?("\\e[")
        out << "\e["
        advance(3)
      elsif match_bytes?("\\e")
        out << "\e"
        advance(2)
      elsif match_bytes?("\\\\")
        out << "\\"
        advance(2)
      elsif match_bytes?("\\\"")
        out << '"'
        advance(2)
      elsif match_bytes?("\\[")
        out << "["
        advance(2)
      elsif match_bytes?("\\]")
        out << "]"
        advance(2)
      elsif match_bytes?("\\u") && hex_byte?(byte(2)) && hex_byte?(byte(3)) && hex_byte?(byte(4)) && hex_byte?(byte(5))
        out << [slice(@pos + 2, @pos + 6).to_i(16)].pack("U")
        advance(6)
      else
        out << "\\"
        advance
      end
    end

    def matching_close_bracket_before_newline?(pos)
      depth = 1
      p = pos
      while p < @length && depth.positive?
        b = @source.getbyte(p)
        return false if b == 10

        if b == 91
          depth += 1
        elsif b == 93
          depth -= 1
        end
        p += utf8_width_at(p)
      end
      depth.zero?
    end

    def scan_interpolation_expr
      expr_start = @pos
      depth = 1
      in_string = false
      escaped = false

      while @pos < @length && depth.positive?
        b = byte
        if in_string
          if escaped
            escaped = false
          elsif b == 92
            escaped = true
          elsif b == 34
            in_string = false
          end
        elsif b == 34
          in_string = true
        elsif b == 91
          depth += 1
        elsif b == 93
          depth -= 1
          break if depth.zero?
        end
        advance_utf8_char
      end

      error "unterminated interpolation" unless depth.zero?
      expr = slice(expr_start).strip
      advance
      expr
    end

    def scan_byte_array
      start_row = @row
      start_col = @col
      bytes = []
      parts = []
      has_interp = false

      advance_utf8_char

      loop do
        skip_byte_array_separators

        if match_bytes?("»")
          advance_utf8_char
          break
        end

        error "unterminated byte array" if eof?

        if byte == 91
          has_interp = true
          parts << [:bytes, bytes.dup] unless bytes.empty?
          bytes = []
          advance
          parts << [:expr, scan_interpolation_expr]
        elsif (match = match_regex_at(BYTE_ARRAY_BINARY))
          append_byte_array_value(bytes, match, 2)
        elsif (match = match_regex_at(BYTE_ARRAY_OCTAL))
          append_byte_array_value(bytes, match, 8)
        elsif (match = match_regex_at(BYTE_ARRAY_DECIMAL))
          append_byte_array_value(bytes, match, 10)
        elsif (match = match_regex_at(BYTE_ARRAY_HEX_PREFIX))
          append_byte_array_value(bytes, match, 16)
        elsif (match = match_regex_at(BYTE_ARRAY_HEX))
          append_byte_array_value(bytes, match, 16)
        else
          ch_start = @pos
          advance_utf8_char
          error "unexpected character in byte array: #{slice(ch_start).inspect}"
        end
      end

      if has_interp
        parts << [:bytes, bytes] unless bytes.empty?
        set_token(:BYTE_ARRAY_INTERP, parts, start_row, start_col)
      else
        set_token(:BYTE_ARRAY, bytes, start_row, start_col)
      end
    end

    def skip_byte_array_separators
      loop do
        case byte
        when 32, 9, 44
          advance
        when 10
          @pos += 1
          @row += 1
          @col = 1
          @line_start = true
        else
          break
        end
      end
    end

    def append_byte_array_value(bytes, match, base)
      val = match[1].delete("_").to_i(base)
      advance(match[0].bytesize)
      error "byte value #{val} out of range (0-255)" unless val >= 0 && val <= 255

      bytes << val
    end

    def advance_utf8_char
      width = utf8_width_at(@pos)
      @pos += width
      @col += 1
    end

    def utf8_width_at(pos)
      b = @source.getbyte(pos)
      return 1 unless b
      return 1 if b < 128
      return 2 if b < 224
      return 3 if b < 240

      4
    end

    def scan_symbol_or_colon
      start_col = @col

      if byte(1) == 45
        third = byte(2)
        if third && third != 9 && third != 10 && third != 13 && third != 32
          return scan_ascii_char_literal(start_col)
        end
      end

      if ident_start_byte?(byte(1)) || upper_byte?(byte(1)) || digit_byte?(byte(1))
        start = @pos
        advance
        if upper_byte?(byte)
          scan_ascii_name_bytes
        else
          scan_ident_bytes
        end
        return set_token(:SYMBOL, slice(start), @row, start_col)
      end

      operator = scan_symbol_operator
      return set_token(:SYMBOL, operator, @row, start_col) if operator

      advance
      set_token(:":", nil, @row, start_col)
    end

    def scan_ascii_char_literal(start_col)
      if byte(2) == 92 && (esc = byte(3))
        cp =
          case esc
          when 110 then 10  # n
          when 116 then 9   # t
          when 114 then 13  # r
          when 92  then 92  # backslash
          when 48  then 0   # 0
          when 115 then 32  # s
          when 39  then 39  # '
          when 34  then 34  # "
          else esc
          end
        advance(4)
        return set_token(:CHAR, cp, @row, start_col)
      end

      cp = byte(2)
      error "`:-X` char literal only supports ASCII. Use U+#{cp.to_s(16)} for non-ASCII characters." if cp >= 128

      advance(3)
      set_token(:CHAR, cp, @row, start_col)
    end

    def scan_symbol_operator
      return nil unless byte == 58

      SYMBOL_OPERATORS.each do |op|
        next unless match_bytes?(op)

        advance(op.bytesize)
        return op
      end
      nil
    end

    def scan_at
      if byte(1) == 64 && ident_start_byte?(byte(2))
        return scan_prefixed_name(:CVAR, 2)
      elsif digit_byte?(byte(1)) && byte(1) != 48
        start_col = @col
        start = @pos
        advance
        advance while digit_byte?(byte)
        return set_token(:PARG, slice(start), @row, start_col)
      elsif ident_start_byte?(byte(1))
        return scan_prefixed_name(:IVAR, 1)
      end

      emit_fixed(:'@', 1)
    end

    def scan_regex_capture
      start_col = @col
      start = @pos
      advance
      advance while digit_byte?(byte)
      set_token(:REGEX_CAPTURE, slice(start + 1), @row, start_col)
    end

    def regex_capture_start?
      @regex_capture_scope &&
        digit_byte?(byte(1)) && byte(1) != 48 &&
        !digit_byte?(byte(2)) &&
        !(byte(2) == 46 && digit_byte?(byte(3)))
    end

    def scan_prefixed_name(type, prefix_len)
      start_col = @col
      start = @pos
      advance(prefix_len)
      scan_ident_bytes
      set_token(type, slice(start), @row, start_col)
    end

    def scan_name
      start_col = @col
      start = @pos
      scan_ascii_name_bytes
      scan_subscript_tail if @pos == start + 1
      value = slice(start)
      type = value.ascii_only? ? (constant_name?(value) ? :CONSTANT : :NAME) : :ID
      set_token(type, value, @row, start_col)
    end

    def scan_ascii_name_bytes
      advance while ident_continue_byte?(byte) || upper_byte?(byte)
    end

    def constant_name?(value)
      i = 0
      need_segment = true
      while i < value.bytesize
        b = value.getbyte(i)
        if need_segment
          return false unless upper_byte?(b) || digit_byte?(b)

          need_segment = false
        elsif b == 95
          need_segment = true
        elsif !(upper_byte?(b) || digit_byte?(b))
          return false
        end
        i += 1
      end
      !need_segment
    end

    def scan_identifier
      start_col = @col
      start = @pos
      if byte == 107 && match_bytes?("kB") && boundary_after?(2)
        advance(2)
        return set_token(:ID, "kB", @row, start_col)
      else
        has_arity = scan_ident_bytes
        finish = @pos
        return if !has_arity && emit_reserved_identifier(start, finish, start_col)
      end

      set_token(has_arity ? :ID_WITH_ARITY : :ID, slice(start), @row, start_col)
    end

    def emit_reserved_identifier(start, finish, start_col)
      case finish - start
      when 3
        if bytes_at?(start, "nil")
          set_token(:NIL, nil, @row, start_col)
          return true
        end
      when 4
        if bytes_at?(start, "true")
          set_token(:TRUE, nil, @row, start_col)
          return true
        end
      when 5
        if bytes_at?(start, "false")
          set_token(:FALSE, nil, @row, start_col)
          return true
        end
      end

      if (keyword = keyword_at(start, finish))
        set_token(:KEYWORD, keyword, @row, start_col)
        return true
      end

      if (type_name = type_name_at(start, finish))
        set_token(:TYPE, type_name, @row, start_col)
        return true
      end

      false
    end

    def keyword_at(start, finish)
      by_length = KEYWORDS_BY_FIRST_AND_LENGTH[@source.getbyte(start)]
      return nil unless by_length

      candidates = by_length[finish - start]
      return nil unless candidates

      candidates.each do |text, value|
        return value if bytes_at?(start, text)
      end
      nil
    end

    def type_name_at(start, finish)
      by_length = TYPE_NAMES_BY_FIRST_AND_LENGTH[@source.getbyte(start)]
      return nil unless by_length

      candidates = by_length[finish - start]
      return nil unless candidates

      candidates.each do |text|
        return text if bytes_at?(start, text)
      end
      nil
    end

    def scan_ident_bytes
      advance while ident_continue_byte?(byte)
      scan_subscript_tail

      if byte == 63 || byte == 33 || byte == 61
        advance
      end

      # Primed identifier: `x'` — the prime (39) joins the identifier
      # only when it can't be opening a single-quoted string: the next
      # byte must not be an identifier, digit, uppercase, or quote.
      if byte == 39
        nb = byte(1)
        unless nb && (ident_continue_byte?(nb) || nb == 39 || nb == 34 || (nb >= 65 && nb <= 90))
          advance
        end
      end

      return false unless byte == 47

      if byte(1) == 42 || byte(1) == 38
        advance(2)
        true
      elsif digit_byte?(byte(1))
        advance
        advance while digit_byte?(byte)
        true
      else
        false
      end
    end

    def scan_subscript_tail
      return false unless non_ascii_byte?(byte)

      match = match_regex_at(SUBSCRIPT_TAIL)
      return false unless match

      advance(match[0].bytesize)
      true
    end

    def scan_number(approx: false)
      start_col = @col
      start = @pos
      consume_number_sign
      if approx || byte == 126
        advance
        consume_number_sign
      end

      if byte == 48
        case byte(1)
        when 120, 88
          advance(2)
          advance while hex_byte?(byte) || byte == 95
          return finish_number_token(slice(start), :INT, start_col)
        when 98, 66
          advance(2)
          if byte(-1) == 98 && digit_byte?(byte) && digit_byte?(byte(1)) && byte(2) == 45
            advance while !eof? && !terminator_byte?(byte)
          else
            advance while byte == 48 || byte == 49 || byte == 95
          end
          return finish_number_token(slice(start), :INT, start_col)
        when 111, 79
          advance(2)
          advance while (byte && byte >= 48 && byte <= 55) || byte == 95
          return finish_number_token(slice(start), :INT, start_col)
        when 100
          advance(2)
          advance while digit_byte?(byte) || byte == 95
          return finish_number_token(slice(start), :INT, start_col)
        when 118
          advance(2)
          advance while vigesimal_byte?(byte) || byte == 95
          return finish_number_token(slice(start), :INT, start_col)
        when 114
          advance(2)
          advance while !eof? && !terminator_byte?(byte)
          return finish_number_token(slice(start), :INT, start_col)
        end
      end

      advance while digit_byte?(byte) || byte == 95

      if (byte == 47 && digit_byte?(byte(1))) || (unicode_rational_slash_at? && digit_byte?(byte(3)))
        byte == 47 ? advance : advance_utf8_char
        advance while digit_byte?(byte) || byte == 95
        return finish_number_token(slice(start), :RATIONAL, start_col)
      end

      is_decimal = false
      if byte == 46 && digit_byte?(byte(1))
        is_decimal = true
        advance
        advance while digit_byte?(byte) || byte == 95
      end

      if (byte == 101 || byte == 69) && (digit_byte?(byte(1)) || (sign_byte?(byte(1)) && digit_byte?(byte(2))))
        is_decimal = true
        advance
        advance if sign_byte?(byte)
        advance while digit_byte?(byte)
      end

      if byte == 37
        advance
        return set_token(:PERCENTAGE, [slice(start, @pos - 1), is_decimal ? :DECIMAL : :INT], @row, start_col)
      end

      finish_number_token(slice(start), approx ? :FLOAT : (is_decimal ? :DECIMAL : :INT), start_col)
    end

    def finish_number_token(num_str, num_type, start_col)
      saved_pos = @pos
      saved_col = @col
      space = false

      # Concise uncertainty notation: `2.1232442(2)` directly attached, no space.
      uncertainty_str = nil
      if byte == 40  # '('
        if (m = match_regex_at(/\((\d+)\)/))
          uncertainty_str = m[1]
          advance(m[0].bytesize)
        end
      end

      if space_byte?(byte)
        unless unit_start_byte?(byte(1))
          if uncertainty_str
            set_token(:MEASUREMENT, [num_str, num_type, uncertainty_str], @row, start_col)
          else
            set_token(num_type, num_str, @row, start_col)
          end
          return
        end

        advance
        space = true
      elsif !unit_start_byte?(byte)
        if uncertainty_str
          set_token(:MEASUREMENT, [num_str, num_type, uncertainty_str], @row, start_col)
        else
          set_token(num_type, num_str, @row, start_col)
        end
        return
      end

      if (unit = scan_unit_string)
        burned = false
        if unit == "burned"
          burned_pos = @pos
          burned_col = @col
          if space_byte?(byte)
            advance
            if (real_unit = scan_unit_string)
              if Units.resolve_unit(real_unit)
                unit = real_unit
                burned = true
              else
                @pos = burned_pos
                @col = burned_col
              end
            else
              @pos = burned_pos
              @col = burned_col
            end
          end
        end

        if (unit == "square" || unit == "cubic") && space_byte?(byte)
          extend_pos = @pos
          extend_col = @col
          advance
          if (mod_unit = scan_unit_string)
            unit = "#{unit} #{mod_unit}"
          else
            @pos = extend_pos
            @col = extend_col
          end
        end

        unit = extend_unit_with_word(unit, " ")
        unit = extend_unit_with_word(unit, "-")
        unit = extend_unit_with_of_phrase(unit)
        unit = "burned #{unit}" if burned

        if match_regex_at(/\s*\(/)
          @pos = saved_pos
          @col = saved_col
          set_token(num_type, num_str, @row, start_col)
        elsif uncertainty_str
          set_token(:MEASURED_QUANTITY, [num_str, unit, num_type, uncertainty_str], @row, start_col)
        else
          set_token(:QUANTITY, [num_str, unit, num_type], @row, start_col)
        end
      else
        @pos = saved_pos if space
        @col = saved_col if space
        if uncertainty_str
          set_token(:MEASUREMENT, [num_str, num_type, uncertainty_str], @row, start_col)
        else
          set_token(num_type, num_str, @row, start_col)
        end
      end
    end

    def scan_unit_string
      match = match_regex_at(/Δ(?:°[\p{L}]+|K)/) || match_regex_at(Lexer::UNIT_STRING)
      return nil unless match

      advance(match[0].bytesize)
      match[0]
    end

    # Extend a unit with " of <word>" if (and only if) the resulting phrase is a
    # registered unit alias. This supports water-column pressure units ("m of water",
    # "in of water", "ft of water") without breaking the existing substance-modifier
    # syntax — "1 cup of flour" stays a method call because "cup of flour" is not in
    # the unit registry, so the extension rolls back.
    def extend_unit_with_of_phrase(unit)
      extend_pos = @pos
      extend_col = @col

      return unit unless space_byte?(byte)
      advance

      of_match = match_regex_at(/of /)
      unless of_match
        @pos = extend_pos
        @col = extend_col
        return unit
      end
      advance(of_match[0].bytesize)

      word_match = match_regex_at(/[\p{L}\d]+/)
      unless word_match
        @pos = extend_pos
        @col = extend_col
        return unit
      end
      advance(word_match[0].bytesize)

      combined = "#{unit} of #{word_match[0]}"
      return combined if Units::UNIT_ALIASES.key?(combined) || Units::UNIT_TABLE.key?(combined)

      @pos = extend_pos
      @col = extend_col
      unit
    end

    def extend_unit_with_word(unit, separator)
      extend_pos = @pos
      extend_col = @col

      if separator == " "
        return unit unless space_byte?(byte)

        advance
        match = match_regex_at(/[\p{L}]+/)
      else
        return unit unless byte == 45

        advance
        match = match_regex_at(/[\p{L}]+/)
      end

      unless match
        @pos = extend_pos
        @col = extend_col
        return unit
      end

      advance(match[0].bytesize)
      combined = "#{unit}#{separator}#{match[0]}"
      return combined if Units::UNIT_ALIASES.key?(combined) || Units::UNIT_TABLE.key?(combined)

      @pos = extend_pos
      @col = extend_col
      unit
    end

    def terminator_byte?(b)
      b.nil? || b == 32 || b == 10 || b == 9 || b == 13 || b == 12 || b == 35 || b == 59 ||
        b == 40 || b == 41 || b == 91 || b == 93 || b == 123 || b == 125 || b == 44
    end

    def scan_wvalue
      start_col = @col
      start = @pos
      advance(3)
      advance while hex_byte?(byte)
      value = slice(start)
      error "WValue literal must use exactly 16 hex digits" unless value.match?(/\Au0x\h{16}\z/)

      set_token(:WVALUE, value, @row, start_col)
    end

    def scan_codepoint_literal
      start_col = @col
      start = @pos
      match = match_regex_at(CHAR)
      unless match
        advance(2)
        advance while hex_byte?(byte)
        error "Invalid Unicode codepoint: #{slice(start)}"
      end

      advance(2)
      advance while hex_byte?(byte)
      hex = slice(start + 2)
      codepoint = hex.to_i(16)
      error "Invalid Unicode surrogate:    #{slice(start)}" if codepoint >= 0xD800 && codepoint <= 0xDFFF
      error "Invalid Unicode noncharacter: #{slice(start)}" if codepoint >= 0xFDD0 && codepoint <= 0xFDEF
      error "Invalid Unicode noncharacter: #{slice(start)}" if (codepoint & 0xFFFE) == 0xFFFE
      set_token(:CODEPOINT, [codepoint].pack("U"), @row, start_col)
    end

    def scan_percent
      if match_bytes?("%w[")
        return emit_fixed(:WORD_ARRAY, 3)
      elsif match_bytes?("%i[")
        return emit_fixed(:SYMBOL_ARRAY, 3)
      elsif byte(1) == 37 || byte(1) == 61
        return scan_operator_or_punctuation
      end

      emit_fixed(:%, 1)
    end

    def scan_dot
      start_col = @col
      if match_bytes?("...")
        advance(3)
        set_token(:"...", nil, @row, start_col)
      elsif match_bytes?("..")
        advance(2)
        set_token(:"..", nil, @row, start_col)
      else
        advance
        set_token(:".", nil, @row, start_col)
      end
    end

    def scan_slash_or_operator
      if ident_start_byte?(byte(1))
        return emit_fixed(:MAP, 1)
      end

      scan_operator_or_punctuation
    end

    VALUE_TOKEN_TYPES = [
      :INT, :FLOAT, :DECIMAL, :STRING, :STRING_INTERP, :REGEX, :REGEX_CAPTURE, :SYMBOL, :NAME, :ID,
      :IVAR, :CVAR, :GLOBAL, :")", :"]", :"}", :MAGIC_FILE, :MAGIC_LINE, :MAGIC_DIR, :UUID, :CURRENCY,
      :QUANTITY, :DURATION, :WVALUE, :BYTE_ARRAY, :BYTE_ARRAY_INTERP, :DATE, :DATETIME, :TIME, :MONTH,
      :IP4, :CIDR4, :RATIONAL, :CHAR, :CODEPOINT, :KEY, :WORD_ARRAY, :SYMBOL_ARRAY, :PARG, :SUPERSCRIPT,
      :COLOR, :TRUE, :FALSE, :NIL
    ].freeze

    def regex_literal_allowed?
      @line_start || !VALUE_TOKEN_TYPES.include?(@last_significant_token_type)
    end

    def regex_literal_ahead?
      i = @pos + 1
      escaped = false
      in_class = false
      while i < @length
        b = @source.getbyte(i)
        return false if b == 10

        if escaped
          escaped = false
        elsif b == 92
          escaped = true
        elsif b == 91
          in_class = true
        elsif b == 93
          in_class = false
        elsif b == 47 && !in_class
          return true
        end
        i += 1
      end
      false
    end

    def scan_regex_literal
      start = @pos
      start_col = @col
      i = start + 1
      escaped = false
      in_class = false

      while i < @length
        b = @source.getbyte(i)
        error "unterminated regex literal" if b == 10

        if escaped
          escaped = false
        elsif b == 92
          escaped = true
        elsif b == 91
          in_class = true
        elsif b == 93
          in_class = false
        elsif b == 47 && !in_class
          pattern = @source.byteslice(start + 1, i - start - 1)
          i += 1
          opts_start = i
          i += 1 while i < @length && @source.getbyte(i).chr.match?(/[a-z]/i)
          advance(i - start)
          return set_token(:REGEX, [pattern, @source.byteslice(opts_start, i - opts_start).to_s], @row, start_col)
        end
        i += 1
      end

      error "unterminated regex literal"
    end

    def emit_operator(type, bytes, start_col)
      advance(bytes)
      set_token(type, nil, @row, start_col)
      true
    end

    def scan_operator_or_punctuation
      start_col = @col

      if byte == 42
        if byte(1) == 42 && (ident_start_byte?(byte(2)) || byte(2) == 64 || byte(2) == 91 || byte(2) == 40)
          advance(2)
          return set_token(:**, nil, @row, start_col)
        elsif ident_start_byte?(byte(1)) || byte(1) == 64 || byte(1) == 91 || byte(1) == 40
          advance
          return set_token(:*, nil, @row, start_col)
        end
      end

      one = byte
      return if scan_multi_char_operator(one, start_col)

      if (type = ONE_CHAR_TOKENS[one])
        advance
        return set_token(type, nil, @row, start_col)
      end

      if non_ascii_byte?(one)
        return scan_unicode_token
      end

      error "can't lex anymore: #{@source.byteslice(@pos, [40, @length - @pos].min)}"
    end

    def scan_multi_char_operator(one, start_col)
      case one
      when 33 # !
        case byte(1)
        when 61
          return emit_operator(:"!==", 3, start_col) if byte(2) == 61

          emit_operator(:"!=", 2, start_col)
        when 126
          emit_operator(:"!~", 2, start_col)
        end
      when 34 # "
        emit_operator(:'">', 2, start_col) if byte(1) == 62
      when 37 # %
        case byte(1)
        when 37
          return emit_operator(:"%%=", 3, start_col) if byte(2) == 61

          emit_operator(:"%%", 2, start_col)
        when 61
          emit_operator(:"%=", 2, start_col)
        end
      when 38 # &
        case byte(1)
        when 38
          return emit_operator(:"&&=", 3, start_col) if byte(2) == 61

          emit_operator(:"&&", 2, start_col)
        when 40
          emit_operator(:"&(", 2, start_col)
        when 46
          emit_operator(:"&.", 2, start_col)
        when 61
          emit_operator(:"&=", 2, start_col)
        end
      when 41 # )
        emit_operator(:")>", 2, start_col) if byte(1) == 62
      when 42 # *
        case byte(1)
        when 42
          return emit_operator(:"**=", 3, start_col) if byte(2) == 61

          emit_operator(:**, 2, start_col)
        when 61
          emit_operator(:"*=", 2, start_col)
        end
      when 43 # +
        case byte(1)
        when 43 then emit_operator(:"++", 2, start_col)
        when 61 then emit_operator(:"+=", 2, start_col)
        when 64 then emit_operator(:+@, 2, start_col)
        end
      when 45 # -
        case byte(1)
        when 45 then emit_operator(:"--", 2, start_col)
        when 61 then emit_operator(:"-=", 2, start_col)
        when 62 then emit_operator(:"->", 2, start_col)
        when 64 then emit_operator(:-@, 2, start_col)
        end
      when 46 # .
        # Phase 4e dot-prefix elementwise operators: .+ .- .* ./ — only
        # when whitespace-bracketed (the disambiguator from method-call
        # syntax `a.foo`). Without space-before, fall through to the
        # ONE_CHAR_TOKENS '.' path; the parser raises on `a.+` since
        # `+` isn't a valid method-name token at that position.
        if whitespace_or_start_before?
          case byte(1)
          when 43 then return emit_operator(:".+", 2, start_col) if byte(2) == 32 || byte(2) == 10
          when 45 then return emit_operator(:".-", 2, start_col) if byte(2) == 32 || byte(2) == 10
          when 42 then return emit_operator(:".*", 2, start_col) if byte(2) == 32 || byte(2) == 10
          when 47 then return emit_operator(:"./", 2, start_col) if byte(2) == 32 || byte(2) == 10
          end
        end
      when 47 # /
        case byte(1)
        when 47
          return emit_operator(:"//=", 3, start_col) if byte(2) == 61

          emit_operator(:"//", 2, start_col)
        when 61
          emit_operator(:"/=", 2, start_col)
        end
      when 60 # <
        case byte(1)
        when 33
          emit_operator(:"<!", 3, start_col) if byte(2) == 32
        when 34
          emit_operator(:'<"', 2, start_col)
        when 62
          # `<>` — the swap operator (a <> b).
          emit_operator(:"<>", 2, start_col)
        when 40
          emit_operator(:"<(", 2, start_col)
        when 45
          return emit_operator(:"<->", 3, start_col) if byte(2) == 62

          emit_operator(:"<-", 2, start_col)
        when 60
          return emit_operator(:"<<=", 3, start_col) if byte(2) == 61

          emit_operator(:<<, 2, start_col)
        when 61
          return emit_operator(:"<=>", 3, start_col) if byte(2) == 62

          emit_operator(:"<=", 2, start_col)
        when 91
          emit_operator(:"<[", 2, start_col)
        end
      when 61 # =
        case byte(1)
        when 61
          return emit_operator(:"===", 3, start_col) if byte(2) == 61

          emit_operator(:"==", 2, start_col)
        when 62
          emit_operator(:"=>", 2, start_col)
        when 126
          emit_operator(:"=~", 2, start_col)
        end
      when 62 # >
        case byte(1)
        when 61
          emit_operator(:>=, 2, start_col)
        when 62
          return emit_operator(:">>=", 3, start_col) if byte(2) == 61

          emit_operator(:>>, 2, start_col)
        end
      when 91 # [
        return false unless byte(1) == 93

        case byte(2)
        when 61
          emit_operator(:"[]=", 3, start_col) if bracket_operator_context?(3)
        when 63
          emit_operator(:"[]?", 3, start_col) if bracket_operator_context?(3)
        else
          emit_operator(:[], 2, start_col) if bracket_operator_context?(2)
        end
      when 93 # ]
        emit_operator(:"]>", 2, start_col) if byte(1) == 62
      when 94 # ^
        emit_operator(:"^=", 2, start_col) if byte(1) == 61
      when 124 # |
        case byte(1)
        when 62
          emit_operator(:"|>", 2, start_col)
        when 61
          emit_operator(:"|=", 2, start_col)
        when 124
          return emit_operator(:"||=", 3, start_col) if byte(2) == 61

          emit_operator(:"||", 2, start_col)
        end
      when 126 # ~
        case byte(1)
        when 61 then emit_operator(:"~=", 2, start_col)
        when 64 then emit_operator(:"~@", 2, start_col)
        when 126 then emit_operator(:"~~", 2, start_col)
        end
      end
    end

    def scan_unicode_token
      if unicode_minus_at?
        return true if approximate_float_literal_possible? && scan_float_literal
        return true if rational_literal_possible? && scan_rational_literal
        return scan_number if digit_byte?(byte(3))
      end

      return scan_byte_array if match_bytes?("«")
      return true if scan_currency_literal
      return true if scan_superscript
      return true if scan_unicode_identifier

      scan_unicode_operator
    end

    def scan_superscript
      start_col = @col
      match = match_regex_at(SUPERSCRIPT_DIGITS)
      return false unless match

      advance(match[0].bytesize)
      set_token(:SUPERSCRIPT, match[0], @row, start_col)
      true
    end

    def scan_unicode_identifier
      start_col = @col
      match = match_regex_at(/Δ(?:°[\p{L}]+|K)/) || match_regex_at(UNICODE_IDENTIFIER)
      return false unless match

      advance(match[0].bytesize)
      set_token(:ID, match[0], @row, start_col)
      true
    end

    def scan_unicode_operator
      start_col = @col
      if match_bytes?("√")
        # Prefix square root: √expr ⇒ expr.sqrt (parser desugars).
        advance_utf8_char
        set_token(:"√", nil, @row, start_col)
      elsif match_bytes?("·") || match_bytes?("⋅") || match_bytes?("×")
        advance_utf8_char
        set_token(:*, nil, @row, start_col)
      elsif match_bytes?("÷") || match_bytes?("∕")
        advance_utf8_char
        set_token(:/, nil, @row, start_col)
      elsif match_bytes?("…")
        advance_utf8_char
        set_token(:"...", nil, @row, start_col)
      elsif match_bytes?("»")
        advance_utf8_char
        set_token(:"»", nil, @row, start_col)
      elsif match_bytes?("±")
        # Uncertainty operator: `5.0 ± 0.1` builds a Measurement.
        advance_utf8_char
        set_token(:±, nil, @row, start_col)
      else
        error "can't lex anymore: #{@source.byteslice(@pos, [40, @length - @pos].min)}"
      end
    end
  end
end
