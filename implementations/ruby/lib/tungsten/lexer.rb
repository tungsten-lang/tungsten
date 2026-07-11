require "strscan"

$debug = false unless defined?($debug)

# @todo safe-navigation operator
#   obj?method
#   obj?.method
#   obj? .method
#   obj ?.method
#   try obj.method

module Tungsten
  BOM = /\A#{"\uFEFF"}/u
  CR  = /\r/
  TRAILING_SPACE = /\b +$/

  CHAR = /
    U\+
    (?<hex>
             10\h{4}
    |  [1-9a-f]\h{4}
    |          \h{4}
    )
    (?!\h)
  /xi

  class Lexer < StringScanner
    attr_accessor :file

    def initialize(code)
      debug(code) if $debug

      @token = Token.new

      @indent = 0

      @indebt = 0
      @dedebt = 0

      @line_start = true
      @last_significant_token_type = nil
      @regex_capture_scope = false
      @bracket_depth = 0

      @row  = 1
      @cols = nil
      @next_col = nil

      super(clean(code))

      handle_indentation
    end

    def debug(code)
      puts
      puts
      puts code
      puts
      puts
    end

    def debug_token
      if @token.type == :NL
        puts
      elsif @token.type == :INDENT
        print '  ' * (@indent - 1)
        print '  '
      else
        print @token.type.to_s + " "
      end
    end

    def clean(code)
      code.dup.tap do |copy|
        # Strip initial BOM, if present
        copy.gsub! BOM, ''

        # Strip trailing spaces at end of lines (but not newlines)
        copy.gsub! TRAILING_SPACE, ''

        # Polyglot scripts begin with `#!/usr/bin/env bash` then an `exec`
        # line that re-execs the file under tungsten. Comment out the exec
        # line so it parses everywhere. Line numbers stay stable because we
        # only mutate the existing line in-place.
        copy.sub!(/\A(#![^\n]*bash[^\n]*\n)exec /, '\1#exec ')
      end
    end

    def handle_indentation
      # Inside an open bracket (...)/[...]/{...} a newline is a line
      # continuation, not block structure: a continuation line indented deeper
      # than the body would otherwise emit a spurious INDENT (absorbed mid
      # expression) whose matching DEDENT later truncates the enclosing block.
      # Consume the leading indentation and emit no indent/dedent while nested.
      # Kept in lockstep with CodepointLexer#handle_indentation (parity-tested).
      if @bracket_depth.positive?
        skip_scan(/^[ ]*/)
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
      # Kept in lockstep with CodepointLexer#handle_indentation (parity-tested).
      if check(/^[ ]*#(?: |\n|\z)/)
        skip_scan(/^[ ]*/)
        return
      end

      # no indent or end of file
      if check(/^(?=\S)|^(?=\z)/)
        @dedebt += @indent
        @cols = nil
        return
      end

      if (indent = skip_scan(/^(?:  )+(?=\S)/))
        diff = (indent / 2) - @indent

        if diff > 0
          @indebt = diff
        elsif diff < 0
          @dedebt = diff.abs
        end
      end

      @cols = nil
    end

    def error(msg)
      err = Error.new("syntax on line #{@row}: #{msg}")
      err.location = Location.new(@file, @row, @token.col)
      err.source_code = string
      err.file_path = @file
      raise err
    end

    def validate_duration_order!(str)
      return if str.start_with?("P") # ISO 8601 order is enforced by the regex

      units = str.scan(/mo|ms|[µμ]s|ns|m(?!s|o)|[ywdhms]/)
      indices = units.map { |u| DURATION_ORDER.index(u.tr("μ", "µ")) }

      unless indices == indices.sort && indices.uniq == indices
        error "duration units must be in descending order: #{str}"
      end
    end

    def validate_week!(match)
      year = match[0, 4].to_i
      week = match[6, 2].to_i

      if week == 53 && !iso_long_year?(year)
        error "invalid week: #{match} (#{year} has only 52 weeks)"
      end
    end

    def iso_long_year?(year)
      # Jan 1 day of week via Gauss's algorithm (0=Sun, 1=Mon, ..., 4=Thu)
      dow = (1 + 5 * ((year - 1) % 4) + 4 * ((year - 1) % 100) + 6 * ((year - 1) % 400)) % 7
      leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
      dow == 4 || (leap && dow == 3)
    end

    # Override StringScanner#scan to track columns
    def scan(regex)
      if (text = super)
        @cols = (@cols || 0) + text.length
        text
      end
    end

    def skip_scan(regex)
      if (length = skip(regex))
        @cols = (@cols || 0) + length
        length
      end
    end

    def skip_newlines
      start = pos
      length = skip_scan(/\s*\n+/)
      return unless length

      count = 0
      stop = start + length
      while start < stop
        count += 1 if string.getbyte(start) == 10
        start += 1
      end
      count
    end

    def token(type, value=nil)
      @token.type  = type
      @token.value = value
    end

    def tokens
      list = []
      list << next_token.clone until @token.type?(:EOF)
      list
    end

    def next_token
      @token.reset_location
      @token.value = nil
      @token.file  = @file
      @token.row   = @row

      if @next_col
        @token.col = @next_col
        @next_col = nil
        @cols = nil
      elsif @cols
        @token.col += @cols
      else
        @token.col = 1
      end

      @cols = nil

      if @indebt > 0
        @indebt -= 1
        @indent += 1

        @cols = 2
        @line_start = true

        token :INDENT

      elsif @dedebt > 0
        @dedebt -= 1
        @indent -= 1

        if @dedebt > 0
          @cols = -2
        else
          @next_col = @indent * 2 + 1
          @cols = nil
        end
        @line_start = true

        token :DEDENT
      else
        scan_token
      end

      debug_token if $debug

      # Clear line_start for non-whitespace tokens (used by nested CLASS detection)
      @regex_capture_scope = false if %i[NL ;].include?(@token.type)
      @regex_capture_scope = true if @token.type == :REGEX

      # Track open-bracket nesting so indentation inside a multi-line
      # (...)/[...]/{...} is treated as line-continuation, not as block
      # structure (see handle_indentation). Kept in lockstep with
      # CodepointLexer#next_token (parity-tested).
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

    def scan_token
      if eos?
        if @indent > 0
          @dedebt = @indent
          next_token
        else
          token :EOF
        end

      elsif scan(/\uFEFF/)
        error "unexpected byte order mark (U+FEFF)"

      elsif (text = scan(/[\t\r\f]/))
        error "unexpected character: #{text.inspect}"

      # trailing whitespace followed by newline(s) — ignore the space and emit a single NL token
      elsif (count = skip_newlines)
        token :NL, count
        @row += count
        @line_start = true

        handle_indentation

      elsif skip_scan(/#\[/)
        scan_key_literal

      elsif (text = scan(/#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{4}|[0-9a-fA-F]{3})(?![0-9a-fA-F\w])/))
        scan_color_literal(text[1..])

      elsif scan(/«/)
        scan_byte_array

      # Type hints: ## type_name ... (only when starting with a known type or type:var pattern)
      elsif skip_scan(TYPE_HINT_START)
        hint = scan(/[^\n]*/)&.strip || ""
        token :TYPE_HINT, hint unless hint.empty?
      elsif skip_scan(/## */)
        scan_comment

      # @todo attach comments/docs to tokens
      elsif @line_start && skip_scan(/# /)
        scan_comment
      elsif @line_start && skip_scan(/#(?=\n|\z)/)
        scan_comment
      elsif skip_scan(/ +# /)
        scan_comment
      elsif skip_scan(/ +#(?=\n|\z)/)
        scan_comment

      elsif skip_scan(/ +/)
        token :SP

      elsif skip_scan(/;/)
        token :";"

      elsif (text = scan(CIDR6))
        token :CIDR6, text
      elsif (text = scan(IP6))
        token :IP6, text
      elsif (text = scan(CIDR4))
        token :CIDR4, text
      elsif (text = scan(IP4))
        token :IP4, text
      elsif (text = scan(MAC))
        token :MAC, text

      elsif (text = scan(UUID))
        token :UUID, text

      elsif (text = scan(DATETIME))
        token :DATETIME, text
      elsif (text = scan(TIME))
        token :TIME, text
      elsif (text = scan(DATE))
        token :DATE, text
      elsif (text = scan(WEEK))
        validate_week!(text)
        token :WEEK, text
      elsif (text = scan(INVALID_WEEK))
        error "invalid week: #{text}"
      elsif (text = scan(MONTH))
        token :MONTH, text

      elsif @regex_capture_scope && (text = scan(/\$[1-9](?![0-9])(?!(?:\.\d))/))
        token :REGEX_CAPTURE, text.delete_prefix("$")
      elsif scan(CURRENCY)
        case self[:suffix]
        when "/-", "", nil
          # okay with prefix (e.g. "£5/-", "₹500/-", "£5", "5/-", "5")
        else
          error "unexpected suffix #{self[:suffix]} on currency with prefix: #{self[:prefix]}" if self[:prefix]
        end

        token :CURRENCY, [self[:amount], self[:prefix], self[:suffix]]
      elsif (text = scan(WVALUE))
        error "WValue literal must use exactly 16 hex digits" unless text.match?(/\Au0x\h{16}\z/)
        token :WVALUE, text
      elsif (text = scan(DURATION))
        validate_duration_order!(text)
        token :DURATION, text
      elsif (text = scan(DECIMAL))
        scan_quantity_or_number(text, :DECIMAL)
      elsif (text = scan(FLOAT))
        scan_quantity_or_number(text, :FLOAT)
      elsif (text = scan(RATIONAL))
        scan_quantity_or_number(text, :RATIONAL)
      elsif (text = scan(INT))
        scan_quantity_or_number(text, :INT)

      elsif (text = scan(CHAR))
        codepoint = self[:hex].to_i(16)
        error "Invalid Unicode surrogate:    #{text}" if codepoint >= 0xD800 && codepoint <= 0xDFFF
        error "Invalid Unicode noncharacter: #{text}" if codepoint >= 0xFDD0 && codepoint <= 0xFDEF
        error "Invalid Unicode noncharacter: #{text}" if (codepoint & 0xFFFE) == 0xFFFE
        token :CODEPOINT, [codepoint].pack('U')
      elsif (text = scan(/U\+\h+/))
        error "Invalid Unicode codepoint: #{text}"

      # do not match method calls: nil? or nil!
      elsif skip_scan(/nil(?![?!])\b/)
        token :NIL

      elsif skip_scan(/true\b/)
        token :TRUE

      elsif skip_scan(/false\b/)
        token :FALSE

      elsif skip_scan(/%w\[/)
        token :WORD_ARRAY
      elsif skip_scan(/%i\[/)
        token :SYMBOL_ARRAY

      elsif skip_scan(/"(?!>(?:\s|$))/)
        scan_string

      elsif regex_literal_allowed? && !check(%r{//|/=}) && check(%r{/}) && regex_literal_ahead?
        scan_regex_literal

      # range operators (before keywords so '...' is not matched as keyword)
      elsif (text = scan(%r[\.{3}|\.{2}|…]))
        token text.to_sym

      elsif (pos.zero? || @line_start) && skip_scan(/[+](?= [A-Z][a-zA-Z0-9]*)/)
        token :CLASS

      elsif scan(/\band\b/)
        token :"&&"
      elsif scan(/\bor\b/)
        token :"||"
      elsif (text = scan(KEYWORD_REGEX))
        token :KEYWORD, text.to_sym

        # @todo consider renaming
      elsif (text = scan(/@([1-9][0-9]*)/))
        token :PARG, text

      # ASCII character literal, e.g. :-# or :-\n. Keep this before symbol
      # operators so :-# is not split as symbol/comment.
      elsif (text = scan(/:-(?:\\[^\s]|[^\s])/))
        value =
          if text[2] == "\\"
            case text[3]
            when "n" then 10
            when "t" then 9
            when "r" then 13
            when "\\" then 92
            when "0" then 0
            when "s" then 32
            when "'" then 39
            when "\"" then 34
            else text[3].ord
            end
          else
            text[2].ord
          end
        token :CHAR, value

      # symbol operators
      elsif (text = scan(%r[:(?:[+*/~!%^&<>|-]|\+@|-@|~@|!@|\*\*|<=|>=|===|==|<=>|=~|<<|>>|\[\]\=|\[\])]))
        token :SYMBOL, text

      # symbols
      # @todo support quoted symbols "" and ''
      # @todo extend to all valid symbols
      elsif (text = scan(/:[a-zA-Z0-9_]+[?!=]?(?:\/\*|\/\d+)?/))
        token :SYMBOL, text

      # Uppercase + subscript identifiers (e.g. Nₐ for Avogadro)
      elsif (text = scan(/[A-Z][₀₁₂₃₄₅₆₇₈₉ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓₔ]+/))
        token :ID, text

        # @todo consider renaming
      elsif (text = scan(/[A-Z](?:_?[A-Z0-9])*(?!\p{Sc})\b/))
        # @todo check if class or make sure classes are in constants lookup
        token :CONSTANT, text

      # @todo consider renaming
      elsif (text = scan(/[A-Z][a-zA-Z0-9]*/))
        token :NAME, text

      # @todo consider renaming...gvar, ivar, var
      #
      # global variables
      elsif (text = scan(/\$[a-z_](?:_?[a-z0-9])*/))
        token :GLOBAL, text

      # class variables
      elsif (text = scan(/@@[a-z_](?:_?[a-z0-9])*/))
        token :CVAR, text

      # instance variables
      elsif (text = scan(/@[a-z_](?:_?[a-z0-9])*/))
        token :IVAR, text

      elsif skip_scan(/__FILE__\b/)
        token :MAGIC_FILE
      elsif skip_scan(/__LINE__\b/)
        token :MAGIC_LINE
      elsif skip_scan(/__DIR__\b/)
        token :MAGIC_DIR

      # Scientific constant: Boltzmann constant kB
      elsif (text = scan(/kB\b/))
        token :ID, text

      # Primed identifier: `x'` — the same-named property on the first
      # argument (README prime notation; the parser desugars it to
      # `@1.x`). The prime joins the identifier only when it can't be
      # opening a single-quoted string: the char after it must not be
      # an identifier, digit, or quote character, so `x'y'` still lexes
      # as `x` + string `'y'`.
      elsif (text = scan(/[a-z_][a-z0-9_₀₁₂₃₄₅₆₇₈₉ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓₔ]*'(?!['"a-zA-Z0-9_])/))
        token :ID, text

      # name=/1
      elsif (text = scan(/[a-z_][a-z0-9_₀₁₂₃₄₅₆₇₈₉ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓₔ]*[=]\/1/))
        token :ID_WITH_ARITY, text

      # name=
      elsif (text = scan(/[a-z_][a-z0-9_₀₁₂₃₄₅₆₇₈₉ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓₔ]*[=]/))
        token :ID, text

      # name?/1
      # reduce!/*
      # add/2
      # select/&
      elsif (text = scan(/[a-z_][a-z0-9_₀₁₂₃₄₅₆₇₈₉ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓₔ]*[?!]?(?:\/&|\/\*|\/\d+)/))
        token :ID_WITH_ARITY, text

      # numeric type names (reserved identifiers)
      elsif (text = scan(TYPE_NAME_REGEX))
        token :TYPE, text

      # variable or method name
      # name?
      # some_method!
      # add
      elsif (text = scan(/[a-z_][a-z0-9_₀₁₂₃₄₅₆₇₈₉ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓₔ]*[?!]?/))
        token :ID, text

      # Unicode identifiers (Greek letters, math symbols, with optional subscripts)
      elsif (text = scan(/[πτϕφℯℇ∞ℎℏσεμµ][₀₁₂₃₄₅₆₇₈₉ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓₔ]*/))
        token :ID, text

      # Δ-prefixed identifier (delta notation: an undefined Δx reads as
      # `x - x'` — the interpreter resolves it; see visit_call).
      elsif (text = scan(/Δ(?:°[\p{L}]+|K|[a-z0-9_]*)/))
        token :ID, text

      # Unit-prefix identifiers (°C, °F, etc.)
      elsif (text = scan(/°[\p{L}]+/))
        token :ID, text

      # heredoc strings: <<~DELIM ... DELIM
      elsif skip_scan(/<<~(?=[A-Z_])/)
        delim = scan(/[A-Z_][A-Z0-9_]*/)
        error "expected heredoc delimiter after <<~" unless delim
        scan_heredoc(delim)

      # raise shorthand: <! expression
      elsif skip_scan(/<! /)
        token :"<!"

      # comparison operators, plus the swap operator <>
      # == != === !== =~ !~ < <= <=> >= > <-> <>
      elsif (text = scan(%r[(?<=^|\s)(==|!=|===|!==|=~|!~|<>|<|<=|<=>|>=|>|<->)(?=\s|$)]))
        token text.to_sym

      # anonymous lambda with arity: ->/2, ->/3
      elsif (text = scan(%r[(?<=^|\s)->/\d+(?=\s|$)]))
        token :LAMBDA_ARITY, text

      # method operators
      # => -> []= []? []
      # e.g. -> [](x)
      # e.g. -> []=(i, value)
      elsif (text = scan(%r[(?<=^|\s)(=>|->|\[\]=|\[\]\?|\[\])(?=\s|$|\()]))
        token text.to_sym

      # assignment operators
      # = <-
      elsif (text = scan(%r[(?<=^|\s)(=|<-)(?=\s|$)]))
        token text.to_sym

      # / U+002F SOLIDUS
      # ∕ U+2215 DIVISION SLASH
      # ⁄ U+2044 FRACTION SLASH
      elsif (text = scan(%r[(?<=^|\s)([&|^%*/+~-]=)(?=\s|$)]))
        token text.to_sym

      elsif (text = scan(%r[(?<=^|\s)((?://|\|\||&&|\*\*|%%|~~|<<|>>)=)(?=\s|$)]))
        token text.to_sym

      # math operators
      # ± is the uncertainty/measurement operator: `5.0 ± 0.1` builds a
      # Measurement(5.0, 0.1). It's a binary infix that returns a value
      # carrying both a magnitude and a Gaussian sigma.
      # @todo add ∘ for function composition (U+2218)
      elsif (text = scan(%r[(?<=^|\s)([&|^%*/+~′″‴»±-])(?=\s|$)]))
        token text.to_sym

      # // || && ** %% ~~ << >> |>
      elsif (text = scan(%r[(?<=^|\s)(//|\|\||&&|\*\*|%%|~~|<<|>>|\|>)(?=\s|$)]))
        token text.to_sym

      # Phase 4e dot-prefix elementwise operators: .+ .- .* ./
      # Same whitespace-around requirement as the other binary ops above
      # disambiguates from method-call dot syntax (a.foo stays a method call).
      elsif (text = scan(%r[(?<=^|\s)(\.[+\-*/])(?=\s|$)]))
        token text.to_sym

      # grouping operators
      # <[ ]> <" "> <( )>
      # @todo add <: :>
      elsif (text = scan(%r[<\[|\]>|<"|">|<\(|\)>]))
        token text.to_sym

      # ( ) { } [ ]
      elsif (text = scan(%r[[(){}]|\[|\]]))
        token text.to_sym

      # unary operators
      # ++ -- +@ -@ ~@
      elsif (text = scan(%r[\+\+|--|\+@|-@|~@]))
        token text.to_sym

      # splat operators (prefix *, ** followed by identifier or bracket)
      elsif (text = scan(%r[(\*\*|\*)(?=[a-zA-Z_@\[\(])]))
        token text.to_sym

      # &. safe navigation
      elsif skip_scan(/&\./)
        token :"&."

      # &( block call — invoke implicit block
      elsif skip_scan(/&\(/)
        token :"&("

      # & for block params (named: &block, anonymous: &)
      elsif skip_scan(/&(?=[a-zA-Z_),])/)
        token :"&"

      # !() @ $ ? : ; . ,
      elsif (text = scan(%r[[!@$?:;.,]]))
        token text.to_sym

      # Unicode square root — prefix operator: √expr ⇒ expr.sqrt
      elsif skip_scan(/√/)
        token :"√"

      # Unicode multiplication (·⋅×) → :*
      elsif scan(/[·⋅×]/)
        token :*

      # Unicode division (÷∕) → :/
      elsif scan(/[÷∕]/)
        token :/

      # map operator: /method (no space before slash, identifier after)
      elsif skip_scan(%r{/(?=[a-z_])})
        token :MAP

      # Superscript digits → SUPERSCRIPT
      elsif (text = scan(/[⁰¹²³⁴⁵⁶⁷⁸⁹]+/))
        token :SUPERSCRIPT, text

      elsif (text = scan(/#!.*\n/))
        @row += 1
        if check(/exec /)
          scan(/.*\n/)
          @row += 1
        end
        token :SHEBANG, text.chomp
        @cols = nil
      else
        error "can't lex anymore: #{rest}"
      end
    end

    def scan_comment
      if skip_scan(/.*\n/)
        token :NL, 1
        @row += 1
        @cols = nil
        # A line-ending comment ends the line just like a bare newline,
        # so it must run the same post-newline bookkeeping (see the
        # `skip_newlines` branch in scan_token) — otherwise the next
        # line's leading indentation is lexed as a mid-line :SP instead
        # of :INDENT, and the parser fails with `expected 'INDENT'`.
        @line_start = true
        handle_indentation
      elsif skip_scan(/.*/)
        token :EOF
      else
        error "Unknown token"
      end
    end

    VALUE_TOKEN_TYPES = [
      :INT, :FLOAT, :DECIMAL, :STRING, :STRING_INTERP, :REGEX, :REGEX_CAPTURE, :SYMBOL, :NAME, :ID,
      :CONSTANT, :IVAR, :CVAR, :GLOBAL, :")", :"]", :"}", :MAGIC_FILE, :MAGIC_LINE, :MAGIC_DIR,
      :UUID, :CURRENCY, :QUANTITY, :DURATION, :WVALUE, :BYTE_ARRAY, :BYTE_ARRAY_INTERP, :DATE,
      :DATETIME, :TIME, :MONTH, :IP4, :CIDR4, :RATIONAL, :CHAR, :CODEPOINT, :KEY, :WORD_ARRAY,
      :SYMBOL_ARRAY, :PARG, :SUPERSCRIPT, :COLOR, :TRUE, :FALSE, :NIL
    ].freeze

    def regex_literal_allowed?
      @line_start || !VALUE_TOKEN_TYPES.include?(@last_significant_token_type)
    end

    def regex_literal_ahead?
      i = pos + 1
      escaped = false
      in_class = false
      while i < string.bytesize
        b = string.getbyte(i)
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
      start = pos
      start_col = @token.col
      i = start + 1
      escaped = false
      in_class = false

      while i < string.bytesize
        b = string.getbyte(i)
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
          pattern = string.byteslice(start + 1, i - start - 1)
          i += 1
          opts_start = i
          i += 1 while i < string.bytesize && string.getbyte(i).chr.match?(/[a-z]/i)
          self.pos = i
          @cols = (@cols || 0) + (i - start)
          token :REGEX, [pattern, string.byteslice(opts_start, i - opts_start).to_s]
          @token.col = start_col
          return
        end
        i += 1
      end

      error "unterminated regex literal"
    end

    def scan_heredoc(delimiter)
      # Current pos is right after <<~DELIM
      rest_start = pos
      nl_pos = string.index("\n", rest_start)
      error "unterminated heredoc: <<~#{delimiter}" unless nl_pos

      rest_of_line = string[rest_start...nl_pos]
      body_start = nl_pos + 1

      # Find closing delimiter line
      body_end = nil
      closing_line_end = nil
      search_pos = body_start

      while search_pos < string.length
        line_end = string.index("\n", search_pos) || string.length
        line = string[search_pos...line_end]

        if line.strip == delimiter
          body_end = search_pos
          closing_line_end = [line_end + 1, string.length].min
          break
        end

        search_pos = line_end + 1
      end

      error "unterminated heredoc: <<~#{delimiter}" unless body_end

      # Extract body content
      body = string[body_start...body_end]

      # Strip common leading whitespace (<<~ semantics)
      lines = body.split("\n", -1)
      min_indent = lines.reject(&:empty?).map { |l| l[/^\s*/].length }.min || 0
      stripped = lines.map { |l| l.empty? ? l : l[min_indent..] }.join("\n")
      stripped.chomp!

      # Count newlines consumed (body lines + delimiter line)
      newlines_consumed = body.count("\n") + 1

      # Reconstruct source: replace heredoc region with rest-of-line content
      new_source = string[0...rest_start] + rest_of_line + "\n" + string[closing_line_end..]
      self.string = new_source
      self.pos = rest_start

      @row += newlines_consumed

      # Check for interpolation
      parts = parse_heredoc_parts(stripped)
      if parts
        token :STRING_INTERP, parts
      else
        token :STRING, stripped
      end
    end

    # Check that ] is found before \n — interpolation cannot span lines
    def has_matching_close_bracket?(str, start)
      depth = 1
      i = start
      while i < str.length && depth > 0
        ch = str[i]
        return false if ch == "\n"

        depth += 1 if ch == "["
        depth -= 1 if ch == "]"
        i += 1
      end
      depth == 0
    end

    def parse_heredoc_parts(str)
      parts = []
      current = +""
      has_interp = false
      i = 0

      while i < str.length
        ch = str[i]
        if ch == "\\" && i + 1 < str.length && str[i + 1] == "["
          current << "["
          i += 2
        elsif ch == "[" && i + 1 < str.length && str[i + 1] != "]" && has_matching_close_bracket?(str, i + 1)
          has_interp = true
          parts << [:str, current] unless current.empty?
          current = +""
          i += 1
          depth = 1
          expr = +""
          while i < str.length && depth > 0
            if str[i] == "["
              depth += 1
              expr << "["
            elsif str[i] == "]"
              depth -= 1
              expr << "]" unless depth == 0
            else
              expr << str[i]
            end
            i += 1
          end
          parts << [:expr, expr.strip]
        else
          current << ch
          i += 1
        end
      end

      return nil unless has_interp
      parts << [:str, current] unless current.empty?
      parts
    end

    def scan_key_literal
      content = +""
      until skip_scan(/\]/)
        error "unterminated key literal" if eos?
        content << scan(/./)
      end
      content.strip!
      error "empty key literal" if content.empty?
      token :KEY, content
    end

    def scan_color_literal(hex)
      # Expand shorthand: #RGB → RRGGBB, #RGBA → RRGGBBAA
      case hex.length
      when 3 then hex = hex.chars.map { |c| c * 2 }.join
      when 4 then hex = hex.chars.map { |c| c * 2 }.join
      end
      r = hex[0..1].to_i(16)
      g = hex[2..3].to_i(16)
      b = hex[4..5].to_i(16)
      a = hex.length == 8 ? hex[6..7].to_i(16) : 255
      token :COLOR, [r, g, b, a]
    end

    def scan_interpolation_expr
      expr = +""
      depth = 1

      until depth == 0
        if eos?
          error "unterminated interpolation"
        elsif skip_scan(/\[/)
          depth += 1
          expr << "["
        elsif skip_scan(/\]/)
          depth -= 1
          expr << "]" unless depth == 0
        elsif skip_scan(/"/)
          expr << '"'
          until skip_scan(/"/)
            error "unterminated string in interpolation" if eos?
            if skip_scan(/\\"/)
              expr << '\\"'
            elsif (text = scan(/[^"\\]+/))
              expr << text
            else
              expr << scan(/./)
            end
          end
          expr << '"'
        elsif (text = scan(/[^\[\]"]+/))
          expr << text
        else
          expr << scan(/./)
        end
      end

      expr.strip
    end

    def scan_byte_array
      bytes = []
      parts = []
      has_interp = false

      loop do
        # Skip whitespace and commas, track newlines
        loop do
          if skip_scan(/[ \t,]+/)
            next
          elsif skip_scan(/\n/)
            @row += 1
            @cols = nil
            next
          else
            break
          end
        end

        break if scan(/»/)
        error "unterminated byte array" if eos?

        if skip_scan(/\[/)
          has_interp = true
          parts << [:bytes, bytes.dup] unless bytes.empty?
          bytes = []
          parts << [:expr, scan_interpolation_expr]
        elsif scan(/0b([01](?:_?[01])*)/)
          val = self[1].delete("_").to_i(2)
          error "byte value #{val} out of range (0-255)" unless val >= 0 && val <= 255
          bytes << val
        elsif scan(/0o([0-7](?:_?[0-7])*)/)
          val = self[1].delete("_").to_i(8)
          error "byte value #{val} out of range (0-255)" unless val >= 0 && val <= 255
          bytes << val
        elsif scan(/0d(\d(?:_?\d)*)/)
          val = self[1].delete("_").to_i(10)
          error "byte value #{val} out of range (0-255)" unless val >= 0 && val <= 255
          bytes << val
        elsif scan(/0x(\h(?:_?\h)*)/)
          val = self[1].delete("_").to_i(16)
          error "byte value #{val} out of range (0-255)" unless val >= 0 && val <= 255
          bytes << val
        elsif scan(/(\h{1,2})/)
          bytes << self[1].to_i(16)
        else
          ch = scan(/./)
          error "unexpected character in byte array: #{ch.inspect}"
        end
      end

      if has_interp
        parts << [:bytes, bytes] unless bytes.empty?
        token :BYTE_ARRAY_INTERP, parts
      else
        token :BYTE_ARRAY, bytes
      end
    end

    # After scanning a number, try to scan an optional unit suffix.
    # Unit string: identifier optionally followed by compound operators (/, *, ^, ·)
    # and more identifiers. e.g. "m", "kg", "m/s", "m/s^2", "kg·m/s^2"
    # The unit is NOT consumed if followed by `(` (function call).
    UNIT_KEYWORDS = %w[if unless while until rescue ensure else elsif when then begin case class module return break next on yield super use with alias raise true false nil].freeze
    # Subscript digits (No) and superscript minus/plus (Sm) aren't \p{L}, so they have to be
    # listed explicitly. Subscript letters are mostly Lm and already covered by \p{L}, but listing
    # them keeps the unit-token alphabet co-located with the identifier alphabet at line 489/493.
    UNIT_STRING = %r{
      (?!(?:if|unless|while|until|rescue|ensure|else|elsif|when|then|begin|case|class|module|return|break|next|on|yield|super|use|with|alias|raise|true|false|nil)\b)
      [\p{L}°℃℉℈℥℔℧][\p{L}0-9_₀₁₂₃₄₅₆₇₈₉ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓₔ]*[⁰¹²³⁴⁵⁶⁷⁸⁹⁻⁺]*
      (?:[*/·⋅^][\p{L}0-9_^⁰¹²³⁴⁵⁶⁷⁸⁹⁻⁺₀₁₂₃₄₅₆₇₈₉ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓₔ]+)*
    }x

    def scan_quantity_or_number(num_str, num_type)
      # No space → percentage
      if skip_scan(/%/)
        token :PERCENTAGE, [num_str, num_type]
        return
      end

      # Concise uncertainty notation: `2.1232442(2)` → Measurement(2.1232442, 2e-7).
      # Must be directly attached (no space) to disambiguate from the call form.
      # The `(N)` is the uncertainty in the *last given digit* — for `2.13(5)`,
      # last digit is hundredths place, so uncertainty is 0.05.
      uncertainty_str = nil
      if (m = scan(/\((\d+)\)/))
        uncertainty_str = self[1]  # the digits between parens
      end

      # Try scanning optional space + unit (not followed by '(' which means function call)
      saved_pos = pos
      space = skip_scan(/ /)
      if (unit = scan(/Δ(?:°[\p{L}]+|K)/) || scan(UNIT_STRING))
        # "burned" prefix: "1 burned cord" → unit is "cord", flag burned
        burned = false
        if unit == "burned" && skip_scan(/ /) && (real_unit = scan(UNIT_STRING))
          if Units.resolve_unit(real_unit)
            unit = real_unit
            burned = true
          else
            self.pos = saved_pos + (space ? 1 : 0) + "burned".length
            # "burned" matched but next word isn't a unit — treat "burned" as unit
            # (will fail later, same as before)
          end
        end

        # "square"/"cubic" prefix: "1 square meter" → "square meter", "1 cubic ft" → "cubic ft"
        if (unit == "square" || unit == "cubic") && skip_scan(/ /) && (mod_unit = scan(UNIT_STRING))
          unit = "#{unit} #{mod_unit}"
        end

        # Try to extend with one more space-separated word for multi-word units
        extend_pos = pos
        if skip_scan(/ /) && (word2 = scan(/[\p{L}]+/))
          combined = "#{unit} #{word2}"
          if Units::UNIT_ALIASES.key?(combined) || Units::UNIT_TABLE.key?(combined)
            unit = combined
          else
            self.pos = extend_pos
          end
        else
          self.pos = extend_pos
        end

        # Try "<unit> of <word>" extension — only when the full phrase is a registered
        # alias. This supports water-column pressure units ("m of water", "in of water",
        # "ft of water") without conflicting with the existing substance-modifier syntax
        # ("1 cup of flour" remains a method call because "cup of flour" is not a unit).
        extend_pos = pos
        if skip_scan(/ of /) && (word2 = scan(/[\p{L}\d]+/))
          combined = "#{unit} of #{word2}"
          if Units::UNIT_ALIASES.key?(combined) || Units::UNIT_TABLE.key?(combined)
            unit = combined
          else
            self.pos = extend_pos
          end
        else
          self.pos = extend_pos
        end

        # Try hyphenated extension: "beard-second", "barn-megaparsec"
        extend_pos = pos
        if skip_scan(/-/) && (word2 = scan(/[\p{L}]+/))
          combined = "#{unit}-#{word2}"
          if Units::UNIT_ALIASES.key?(combined) || Units::UNIT_TABLE.key?(combined)
            unit = combined
          else
            self.pos = extend_pos
          end
        else
          self.pos = extend_pos
        end

        # Prepend "burned " back into unit string for interpreter
        unit = "burned #{unit}" if burned

        # Make sure unit is not followed by ( which would be a function call
        if check(/\s*\(/)
          self.pos = saved_pos
          token num_type, num_str
        elsif uncertainty_str
          token :MEASURED_QUANTITY, [num_str, unit, num_type, uncertainty_str]
        else
          token :QUANTITY, [num_str, unit, num_type]
        end
      elsif space
        # Scanned a space but no unit — put the space back
        self.pos = saved_pos
        if uncertainty_str
          token :MEASUREMENT, [num_str, num_type, uncertainty_str]
        else
          token num_type, num_str
        end
      elsif uncertainty_str
        token :MEASUREMENT, [num_str, num_type, uncertainty_str]
      else
        token num_type, num_str
      end
    end

    def scan_string
      parts = []
      str = ""
      has_interp = false

      until skip_scan(/"/)
        if eos?
          error "unterminated string"

        elsif skip_scan(/\\n/)  then str << "\n"
        elsif skip_scan(/\\r/)  then str << "\r"
        elsif skip_scan(/\\t/)  then str << "\t"
        elsif skip_scan(/\\e\[/) then str << "\e["
        elsif skip_scan(/\\e/)  then str << "\e"
        elsif (text = scan(/\\u([0-9a-fA-F]{4})/)) then str << [text[2..5].to_i(16)].pack("U")
        elsif skip_scan(/\\\\/) then str << "\\"
        elsif skip_scan(/\\"/)  then str << '"'
        elsif skip_scan(/\\\[/) then str << "["
        elsif skip_scan(/\\\]/) then str << "]"
        elsif skip_scan(/\[(?!\])/)
          if has_matching_close_bracket?(rest, 0)
            has_interp = true
            parts << [:str, str] unless str.empty?
            str = ""
            parts << [:expr, scan_interpolation_expr]
          else
            str << "["
          end
        elsif (text = scan(/[^"\\\[]+/))
          str << text
        else
          str << scan(/./)
        end
      end

      if has_interp
        parts << [:str, str] unless str.empty?
        token :STRING_INTERP, parts
      else
        token :STRING, str
      end
    end

    def next_token_skip_indent
      next_token
      skip_indent
    end

    def next_token_skip_space
      next_token
      skip_space
    end

    def next_token_skip_newline
      next_token
      skip_newline
    end

    def next_token_skip_whitespace
      next_token
      skip_whitespace
    end

    def next_token_skip_whitespace_all
      next_token
      skip_whitespace_all
    end

    def next_statement
      next_token
      skip_statement_end
    end

    def skip_dedent
      next_token if @token.type == :DEDENT
    end

    def skip_indent
      next_token while @token.type == :INDENT
    end

    def skip_space
      next_token while @token.type == :SP
    end

    def skip_whitespace
      next_token while @token.type == :SP || @token.type == :NL
    end

    def skip_whitespace_all
      loop do
        case @token.type
        when :SP, :NL, :INDENT, :DEDENT
          next_token
        else
          break
        end
      end
    end

    def skip_newline
      next_token while @token.type == :NL
    end

    def skip_statement_end
      next_token while @token.type == :SP || @token.type == :NL || @token.type == :TYPE_HINT

      case @token.type
      when :';'
        next_token
      when :KEYWORD
        next_token if @token.value == :end
      end
    end

    def next_token_if(*types)
      next_token while types.include? @token.type
    end


    KEYWORDS = %w[
      ...
      alias always
      begin break
      case continue
      else elsif ensure
      fn
      if in is
      loop
      module
      next
      on
      raise redo rescue retry return
      super
      then trait
      unless until use
      when while with
      yield
    ].freeze

    TYPE_NAMES = %w[
      bool int integer string string_buffer
      i4 i8 i16 i32 i64 i128
      u4 u8 u16 u32 u64 u128
      w64
      f16 f32 f64 f80 f128 f256
      d128 c32 c64 c128
      bigint bigdecimal
      bf16 tf32 fp8 fp4 nf4
      mxfp8 mxfp6 mxfp4 mxint8
      posit8 posit16 posit32 posit64
    ].freeze

    KEYWORD_PATTERN = KEYWORDS.map { |kw| Regexp.escape(kw) }.join("|").freeze
    KEYWORD_REGEX = /(#{KEYWORD_PATTERN})\b/
    TYPE_NAME_PATTERN = TYPE_NAMES.join("|").freeze
    TYPE_NAME_REGEX = /(#{TYPE_NAME_PATTERN})\b/
    TYPE_HINT_START = /## +(?=(?:#{TYPE_NAME_PATTERN})\b|[a-z]\w*:)/

    SIGN = /[+−-]/

    FLOAT = /
      #{SIGN}?

      ~                          # approx.

      (?:0|[1-9](?:_[0-9]+)*)    # 0.0 or 1_000.0

      \.                         # decimal required

      \d+(?:_\d+)*               # 0.0 or 0.000_1

      (?:e[+-]?(0|[1-9][0-9]*))? # scientific notation, no leading zero in exp
    /x

    WVALUE = /u0x\h+/

    # @todo http://tantek.pbworks.com/w/page/19402946/NewBase60
    # @todo https://en.wikipedia.org/wiki/Sexagesimal
    # @todo https://en.wikipedia.org/wiki/Cuneiform_Numbers_and_Punctuation
    # @todo https://en.wikipedia.org/wiki/List_of_numeral_systems
    #
    # @todo balanced ternary (0bt- or 0r3b- ?) digits { T, 0, 1 } representing { -1, 0, 1 }
    #
    # Consider #16rf00
    INT = /
      #{SIGN}?

      (?:
        0b[0-1]         (?:_?[0-1]+)*       #  2 binary
      | 0o[0-7]         (?:_?[0-7]+)*       #  8 octal
      | 0d[0-9]         (?:_?[0-9]+)*       # 10 decimal
      | 0x\h            (?:_?\h+)*          # 16 hexadecimal
      | 0v[0-9a-jA-J]   (?:_?[0-9a-jA-J]+)* # 20 vigesimal

      | 0r 2-[01]       (?:_?[01]+)*
      | 0r 3-[0-2]      (?:_?[0-2]+)*
      | 0r 4-[0-3]      (?:_?[0-3]+)*
      | 0r 5-[0-4]      (?:_?[0-4]+)*
      | 0r 6-[0-5]      (?:_?[0-5]+)*
      | 0r 7-[0-6]      (?:_?[0-6]+)*
      | 0r 8-[0-7]      (?:_?[0-7]+)*
      | 0r 9-[0-8]      (?:_?[0-8]+)*
      | 0r10-[0-9]      (?:_?[0-9]+)*
      | 0r11-[0-9a]     (?:_?[0-9a]+)*

      | 0r16-\h         (?:_?\h+)*
      | 0r20-[0-9a-jA-J](?:_?[0-9a-jA-J]+)*

      | 0b32-[2-7A-Z]+                     # Base32
      | 0b36-[0-9A-Z]+                     # Base36

      | 0b56-[2-9A-HJ-NP-Za-kmnp-z]+       # Base56
      | 0b58-[1-9A-HJ-NP-Za-km-z]+         # Base58 - letter order varies by application

      | 0b60-[0-9A-HJ-NP-Z_a-km-z]+        # Base60
      | 0b64-[0-9A-Za-z+=\/]+              # Base64

      | [1-9] (?:_?[0-9]+)*                # numbers
      | 0                                  # zero
      )
    /x

    # 3+2i or 1i
    # See Python, Ruby, Julia
    #
    # @todo finish this, clean up and expand pattern
    COMPLEX = /
      (?:                                  # Real part (optional)
        (?:
            0
          | [1-9] (?:_?[0-9]+)*
        )

        [+−-]                              # must have a separator
      )?

      [1-9][0-9]*i
    /

    # @todo add support for $1,000.00 and 1.000,00£
    DECIMAL = /
      #{SIGN}?

      (?:
        [$]?

        (?:
            [0-9] (?: _?[0-9]+)* \. [0-9] (?:_?[0-9]+)*
        )
        [K]?                               # kelvin

        |

        (?:
          # 1;24,51,10
          0r60-(?:\d+,?)+;(?:\d+,?)+       # sexagesimal

          # (48°57′54.8″N, 120°08′16.6″W)
          | \d+°\d+′\d+\.\d+″ [NSEW]?
          | \d+°\d+′\d+     ″ [NSEW]?

          | \d+°\d+'\d+\.\d+" [NSEW]?
          | \d+°\d+'\d+     " [NSEW]?

          # 8′29″44‴0⁗
          # in watchmaking triple prime represents a ligne (1⁄12 inch)
          # in astronomy triple prime denotes thirds (1⁄60 of a second)
          # in astronomy quadruple prime denotes fourths (1⁄60 of a third)
          | \d+′\d+″\d+‴\d+⁗
          | \d+′\d+″\d+‴
          | \d+′\d+″

          | \d+'\d+"\d+'''
          | \d+'\d+"
        )
      )
    /x

    # Capture as: <integer>.<fixed><recur>
    #
    # Denominator:
    #   9s: recur.length times
    #   0s: fixed.length times
    #
    # Numerator:
    #   (integer + fixed + recur) - (integer + fixed)
    #
    # Simplify using greatest common divisor (gcd)
    #
    # Reminder: the denominator for a repeating sequence of length n
    #           is always n nines (e.g. 0.1̅2̅ = 12/99)
    #
    # TO CONSIDER
    #   0.(3)  parentheses notation
    #   0.3... ellipses notation
    DECIMAL_RECURRING = /
      #{SIGN}?

      (?:
        (?:0|[1-9][0-9]*)                # one leading zero

        \.

        (?:
            \d*(?:\d\u0305)+             # Vinculum: 0.0̅1̅2̅3̅4̅5̅6̅7̅8̅9̅ Unicode
          | \d*\\overline\{\d+\}         # Vinculum: 0.0̅1̅2̅3̅4̅5̅6̅7̅8̅9̅ LaTeX

          | \d*\d\u0307                  # Single dot: 0.9̇ Unicode
          | \d*\d\\dot\{\d\}             # Single dot: 0.9̇ LaTeX

          | \d*\d\u0307\d+\d\u0307       # Bookend dots: 0.0̇123456789̇ Unicode
          | \d*\\dot\{\d\}\d+\\dot\{\d\} # Bookend dots: 0.0̇123456789̇ LaTeX
        )
      )
    /x

    RATIONAL = /
      #{SIGN}?

      (?: 0 | [1-9](?:_?[0-9]+)*)                # numerator
      [\/∕⁄]
      (?: 0 | [1-9](?:_?[0-9]+)*)                # denominator
    /x


    CURRENCY_PREFIX = /
      (?: JP|CN )?                               # Optional "JP" or "CN" prefix for yen and yuan
          \p{Sc}                                 # Unicode currency symbol prefix
    /x

    CURRENCY_SUFFIX = /
      (?: \p{Sc}|[p円元]|\/-)                    # postfix currency symbols for pence, yen, yuan
      (?! \p{L})                                 # no more letters, don't match px, pF
    /x

    CURRENCY_AMOUNT =/
      (?: 0|[1-9] (?:_?[0-9]+)* )                # Integer part
      (?: \.[0-9] (?:_?[0-9]+)* )?               # Optional decimal
    /x

    # ₹500/- is common notation for "500 rupees only"
    CURRENCY = /
      (?:(?<sign>#{SIGN})?(?<prefix>#{CURRENCY_PREFIX})(?<amount>#{CURRENCY_AMOUNT})(?<suffix>#{CURRENCY_SUFFIX})?)
    | (?:(?<sign>#{SIGN})?                             (?<amount>#{CURRENCY_AMOUNT})(?<suffix>#{CURRENCY_SUFFIX}))
    /x

    # TODO
    #   Units of measurement on numeric literals (including byte-size literals, 64KB, 2.5MB, 1GiB

    IP4SEG = /
      25[0-5]
    | 2[0-4][0-9]
    | 1[0-9][0-9]
    |  [1-9][0-9]
    |       [0-9]
    /x

    PORT = /
      6553[0-5]
    |  655[0-2][0-9]
    |   65[0-4][0-9]{2}
    |    6[0-4][0-9]{3}
    |     [1-5][0-9]{4}
    |     [1-9][0-9]{0,3}
    | 0
    /x

    IP4 = /\b (?:#{IP4SEG} \. ){3} #{IP4SEG} (?:#{PORT})? \b/x

    # IP6 regex is case-insensitive
    IP6SEG = /[0-9A-F]{1,4}/i

    # http://stackoverflow.com/questions/53497/regular-expression-that-matches-valid-ipv6-addresses
    # https://www.mediawiki.org/wiki/Help:Range_blocks/IPv6
    # IP6 = /
    #   fe80:(?::#{IP6SEG}){0,4}%[0-9a-zA-Z]+   # fe80::7:8%eth0    fe80::7:8%1 (link-local address with zone index)
    # | ::(?:ffff(?::0{1,4}){0,1}:){0,1}#{IP4}  # ::255.255.255.255 ::ffff:255.255.255.255 ::ffff:0:255.255.255.255 (IPv4-mapped IPv6 addresses and IPv4 translated addresses)
    # | (?:#{IP6SEG}:){1,4}:#{IP4}              # 2001:db8:3:4::192.0.2.33

    # | (?:#{IP6SEG}:){7,7}    #{IP6SEG}        # 1:2:3:4:5:6:7:8

    # |             :      (?::#{IP6SEG}){1,7}  #                  ::2:3:4:5:6:7:8 ::8
    # | (?:#{IP6SEG}:){1,1}(?::#{IP6SEG}){1,6}  # 1::3:4:5:6:7:8  1::3:4:5:6:7:8  1::8
    # | (?:#{IP6SEG}:){1,2}(?::#{IP6SEG}){1,5}  # 1::4:5:6:7:8  1:2::4:5:6:7:8  1:2::8
    # | (?:#{IP6SEG}:){1,3}(?::#{IP6SEG}){1,4}  # 1::5:6:7:8  1:2:3::5:6:7:8  1:2:3::8
    # | (?:#{IP6SEG}:){1,4}(?::#{IP6SEG}){1,3}  # 1::6:7:8  1:2:3:4::6:7:8  1:2:3:4::8
    # | (?:#{IP6SEG}:){1,5}(?::#{IP6SEG}){1,2}  # 1::7:8  1:2:3:4:5::7:8  1:2:3:4:5::8
    # | (?:#{IP6SEG}:){1,6}(?::#{IP6SEG}){1,1}  # 1::8  1:2:3:4:5:6::8  1:2:3:4:5:6::8
    # | (?:#{IP6SEG}:){1,7}   :                 # 1:: 1:2:3:4:5:6:7::
    # /xi

    IP6CORE = /
      fe80:(?::#{IP6SEG}){0,4}%[0-9a-zA-Z]+   # fe80::7:8%eth0    fe80::7:8%1 (link-local address with zone index)
    | ::(?:ffff(?::0{1,4}){0,1}:){0,1}#{IP4}  # ::255.255.255.255 ::ffff:255.255.255.255 ::ffff:0:255.255.255.255 (IPv4-mapped IPv6 addresses and IPv4 translated addresses)
    | (?:#{IP6SEG}:){1,4}   :#{IP4}           # 2001:db8:3:4::192.0.2.33

    | (?:#{IP6SEG}:){7,7}    #{IP6SEG}        # 1:2:3:4:5:6:7:8

    |             :      (?::#{IP6SEG}){1,7}  #                  ::2:3:4:5:6:7:8 ::8
    | (?:#{IP6SEG}:){1,1}(?::#{IP6SEG}){1,6}  # 1::3:4:5:6:7:8  1::3:4:5:6:7:8  1::8
    | (?:#{IP6SEG}:){1,2}(?::#{IP6SEG}){1,5}  # 1::4:5:6:7:8  1:2::4:5:6:7:8  1:2::8
    | (?:#{IP6SEG}:){1,3}(?::#{IP6SEG}){1,4}  # 1::5:6:7:8  1:2:3::5:6:7:8  1:2:3::8
    | (?:#{IP6SEG}:){1,4}(?::#{IP6SEG}){1,3}  # 1::6:7:8  1:2:3:4::6:7:8  1:2:3:4::8
    | (?:#{IP6SEG}:){1,5}(?::#{IP6SEG}){1,2}  # 1::7:8  1:2:3:4:5::7:8  1:2:3:4:5::8
    | (?:#{IP6SEG}:){1,6}(?::#{IP6SEG}){1,1}  # 1::8  1:2:3:4:5:6::8  1:2:3:4:5:6::8
    | (?:#{IP6SEG}:){1,7}   :                 # 1:: 1:2:3:4:5:6:7::
    /xi

    IP6 = /
      \[#{IP6CORE}\]:#{PORT}
    |   #{IP6CORE}
    /x

    CIDR4 = /#{IP4}\/(?:3[0-2]|[1-2]?[0-9])/x
    CIDR6 = /(?:#{IP6}|::)\/(?:12[0-8]|1[01][0-9]|[1-9]?[0-9])/x

    MACSEG = /[0-9A-F]{2}/i

    MAC = /
      (?:#{MACSEG}:){5}#{MACSEG}                # aa:bb:cc:dd:ee:ff (Unix)
    | (?:#{MACSEG}-){5}#{MACSEG}                # aa-bb-cc-dd-ee-ff (Windows)
    | #{MACSEG}{2}\.#{MACSEG}{2}\.#{MACSEG}{2}  # aabb.ccdd.eeff (Cisco)
    /xi

    UUID = /\h{8}-\h{4}-[1-8]\h{3}-[89aAbB]\h{3}-\h{12}/

    WEEK = /
      \d{4}-W(?:0[1-9]|[1-4]\d|5[0-3])(?!\d)    # YYYY-Www, ww: week number [01-53]
    /x

    INVALID_WEEK = /
      \d{4}-W\d*                                # malformed week (W, W0, W00, W54, W123, etc.)
    /x

    MONTH = /
      \d\d\d\d-(?:0[1-9]|1[0-2])                # YYYY-MM (01-12)
    /x

    # ISO 8601
    # - Doesn't allow years before 1582, except by mutual agreement
    # - Allows years before 0000 and after 9999 only by mutual agreement

    MM =   /0[1-9]|1[0-2]/                     # 01-12
    DD =   /0[1-9]|[12]\d|3[01]/               # 01-31
    DDD =  /[0-2]\d\d|3[0-5]\d|36[0-6]/        # 001-366
    WW =   /0[1-9]|[1-4]\d|5[0-3]/             # 01-53
    WDAY = /[1-7]/                             # 1-7

    DATE = /
      (
        \d\d\d\d-#{DDD}                        # YYYY-DDD, ordinal date
      | \d\d\d\d-W#{WW}-#{WDAY}                # YYYY-Www-D, week date
      | \d\d\d\d-#{MM}-#{DD}                   # YYYY-MM-DD, calendar date
      )
    /x

    # NOTE: Following ISO 8601, numeric offsets represent only time
    #       zones that differ from UTC by an integral number of minutes.
    #       However, many historical time zones differ from UTC by a non-
    #       integral number of minutes.  To represent such historical time
    #       stamps exactly, applications must convert them to a representable
    #       time zone.

    HH =    /[01]\d|2[0-3]/                    # 00-23
    MI =    /[0-5]\d/                          # 00-59
    SS =    /[0-5]\d|60/                       # 00-60 (leap second)
    TZ_HH = /0\d|1[0-4]/                       # 00-14

    TZ = /
      [+−-]#{TZ_HH}:#{MI} # ±hh:mm [plus minus hyphen]
    | [+−-]#{TZ_HH}#{MI}  # ±hhmm
    | [+−-]#{TZ_HH}       # ±hh
    | Z
    /x

    TIME = /
      (
        24:00:00\.0{1,3}           #{TZ}?      # midnight end-of-day (fractional)
      | 24:00:00                   #{TZ}?      # midnight end-of-day
      | 24:00                      #{TZ}?      # midnight end-of-day (short)
      | #{HH}:#{MI}:#{SS}\.\d\d?\d?#{TZ}?      # hh:mm:ss.sss
      | #{HH}:#{MI}:#{SS}          #{TZ}?      # hh:mm:ss±hh:mm
      | #{HH}:#{MI}               #{TZ}?       # hh:mm
      )
    /x

    DATETIME = /(#{DATE}T#{TIME})/x

    # 5m30s, 2h15m, 1d12h — compound required (2+ segments), order validated in lexer
    # `µs` accepts both U+00B5 (micro sign) and U+03BC (Greek small letter mu).
    DURATION_UNIT = /mo|ms|[µμ]s|ns|m(?!s|o)|[ywdhms]/
    DURATION_COMPACT = /
      \d+ (?:#{DURATION_UNIT})
      (?: \d+ (?:#{DURATION_UNIT}) )+
    /x

    # ISO 8601: P1Y2M3DT4H5M6S, P3Y6M, PT1H30M, P1DT12H, etc.
    # The last (smallest) component may be fractional: PT1.5H, P1.5Y, PT30.5M
    # Weeks (W) cannot be combined with other date components per ISO 8601
    DURATION_ISO_TIME = /T(?:(?:\d+H)            (?:\d+M)?             (?:\d+(?:\.\d+)?S)?
                        |    (?:\d+(?:\.\d+)?H)
                        |                        (?:\d+M)              (?:\d+(?:\.\d+)?S)?
                        |                        (?:\d+(?:\.\d+)?M)
                        |                                              (?:\d+(?:\.\d+)?S)
                        )/x

    DURATION_ISO_DATE = /(?:\d+(?:\.\d+)?W)
                        |(?:\d+Y)? (?:\d+M)?  (?:\d+\.\d+D)
                        |(?:\d+Y)  (?:\d+\.\d+M)
                        |(?:\d+\.\d+Y)
                        |(?:\d+Y)  (?:\d+M)?  (?:\d+D)?          (?:#{DURATION_ISO_TIME})?
                        |          (?:\d+M)   (?:\d+D)?          (?:#{DURATION_ISO_TIME})?
                        |                     (?:\d+D)           (?:#{DURATION_ISO_TIME})?
                        /x

    DURATION_ISO = /P(?:#{DURATION_ISO_DATE}|#{DURATION_ISO_TIME})/x

    DURATION = /#{DURATION_COMPACT}|#{DURATION_ISO}/

    DURATION_ORDER = %w[y mo w d h m s ms µs ns].freeze

    # TODO add support for sidereal time (for planets includes 1 extra day per year)
    #
    # Standard time on Earth is Solar Time, or a reference which keeps constant time with respect to the Sun.
    #
    # 1 sidereal day = 24 sidereal hours = 1440 sidereal minutes = 86400 sidereal seconds
    # 1 sidereal day = 23h 56m 04s
    #
    # Sidereal Time (ST) is the Hour Angle of the Vernal Equinox (HAVE)
    #
    # The international sidereal day begins when the vernal equinox transits the prime meridian
    #
    # The vernal equinox is the point on the celestial sphere at which the Sun crosses the plane of the Equator, moving
    # from south to north.
    #
    # if the mean equinox is used, the result is mean sidereal time
    # if the true equinox is used, the result is apparent sidereal time
    # LST = Local Sidereal Time
    # LMST = Local Mean Sidereal Time
    #
    # Greenwich Apparent Sidereal Time is corrected for the shift in the position of the vernal equinox due to nutation
    # GAST = GMST + (equation of the equinoxes) 
    #
    # Local Mean Sidereal Time
    # LMST = GMST + (observer's east longitude)
    #
    # See https://www.britannica.com/science/dynamical-time
    # See https://mavdisk.mnsu.edu/wp5884kt/courses/a125/siderealtime.pdf
    # See https://lweb.cfa.harvard.edu/~jzhao/times.html#:~:text=LST%20%2D%20Local%20Sidereal%20Time,-The%20definition%20of&text=In%20practice%2C%20LST%20is%20used,(equation%20of%20the%20equinoxes).
  end
end
