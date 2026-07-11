# Recursive descent parser for tungsten
use ast
use ../../core/token

+ Parser
  -> new(@token_count, @packed_tokens, @source, @values, @line_at, @col_at, @file)
    @pos = 0
    @pending_type_hints = []
    @in_class_body = false
    # File-level namespace from an `in Foo:Bar` directive — when
    # set, bare class declarations get prefixed with this. nil =
    # no namespace, declarations land at top level.
    @namespace_prefix = nil
    # All fully-qualified class names declared in this file, used
    # to resolve an unqualified superclass via the Ruby-style
    # walk-up (current namespace → parent → … → top).
    @declared_classes = {}
    # @current_packed is the W_LEXICAL_TOKEN i64 for the current
    # position, populated by sync_current from @packed_tokens[@pos].
    # @source is the raw source buffer — tok_equal? and at_kw? /
    # expect_kw? helpers slice into it on demand.
    @current_packed = 0
    # @no_bare_args suppresses bare-arg parsing in parse_call_args_and_block
    # when set true. parse_in_test sets it around its element loop so
    # `in (A B C)` parses as 3 separate elements instead of `A(B C)`.
    @no_bare_args = false
    # Per-class-body collection of `with NAME in (typenames)` constraints.
    # nil outside a class/trait body; reset+restored across nested defs.
    @pending_class_constraints = nil
    # Struct names referenced in `- data (StructName)` blocks — the
    # backing C-struct name for a class's instances. PascalCase names
    # listed here are struct references, NOT class references; downstream
    # passes can use this set to distinguish them once they need to.
    @struct_names = {}
    # Register this file's per-codepoint line/col tables (already
    # built by the lexer) under a small file_id, so FileOffset
    # locations constructed below can be resolved back to line/col
    # later — see register_file_tables in ast.w for why.
    @file_id = register_file_tables(@file, @line_at, @col_at)
    sync_current()

  -> register_struct_name(name)
    if name != nil
      @struct_names[name] = true

  -> struct_name?(name)
    @struct_names[name] == true

  # Inline-shift accessors for packed Tokens. Token's class methods
  # (`.type`/`.offset`) route through W_TAG_CHAR subtype dispatch — the
  # C VM stage 0 doesn't support that dispatch on Integer-typed values
  # (Tungsten boxes packed i64s as Integer when read out of an Array).
  # Calling these helpers instead does the bit-shift inline so both the
  # C VM and the compiled binary see the same arithmetic.
  -> tok_type(p)
    (p >> 38) & 0xFF

  -> tok_off(p)
    (p >> 2) & 0xFFFFFF

  -> tok_len(p)
    (p >> 26) & 0xFFF

  # Set the codepoint array post-construction. The packed token's `off`
  # indexes this array (codepoint-indexed), NOT the byte-indexed
  # @source string. Adding @chars as a 7th constructor arg triggered a
  # C VM constant-pool overflow / IP-misalignment issue, so we set it
  # via this method right after Parser.new.
  -> set_chars(chars)
    @chars = chars
    self

  # Compare a packed token's source bytes against a literal string.
  # See set_chars for why @chars exists separately from @source — the
  # short version is "lexer offsets are codepoint indices and the
  # runtime's String.slice is byte-indexed, so we walk @chars to do
  # the comparison codepoint-by-codepoint". Tungsten keywords and
  # operators are all ASCII, so lit[i] (one codepoint) compares
  # directly to @chars[off+i] (one codepoint).
  -> tok_equal?(p, src, lit)
    len = (p >> 26) & 0xFFF
    if len != lit.size()
      return false
    # @chars is codepoint-indexed (= source.chars()), matching the token's
    # codepoint offset; @source.slice would be byte-indexed and misalign
    # after any multi-byte UTF-8 char earlier in the file. Keywords and
    # operators are ASCII, so a per-codepoint string compare is exact.
    off = (p >> 2) & 0xFFFFFF
    lit_cps = lit.chars()
    i = 0
    while i < len
      if @chars[off + i] != lit_cps[i]
        return false
      i += 1
    true

  -> sync_current
    # Transparently skip :SP tokens so existing parser sites don't see
    # them. @sp_before records whether at least one :SP was skipped,
    # giving disambiguators (e.g., `foo(x)` vs `foo (x)`) a single-bit
    # query without restructuring the grammar around explicit SP nodes.
    @sp_before = false
    while @pos < @token_count && tok_type(@packed_tokens[@pos]) == T_SP
      @sp_before = true
      @pos += 1
    if @pos < @token_count
      @current_packed = @packed_tokens[@pos]
      return nil
    @current_packed = 0

  # Pack a source location into a W_PACKED_LOCATION WValue (w64) for
  # a node's `:loc` slab slot — FileOffset mode: file_id + a
  # byte-into-@chars offset (a codepoint index; see ast.w's
  # register_file_tables comment for why this must NOT be a raw byte
  # offset into @source). The ccall_nobox dispatch returns a fully
  # tagged WValue (W_TAG_PACKED | subtype 7 | mode 2 | file_id |
  # offset). The lowering whitelist marks w_location_file_offset as
  # `:i64` (already boxed) so downstream storage passes it verbatim —
  # the slot really does hold a Location WValue, not a NaN-boxed int
  # with the location payload. Node.line / Node.col reconstruct line/
  # col lazily via the @file_id-keyed tables register_file_tables set
  # up in the constructor. `0` remains the absent-slot sentinel
  # because any tagged Location has bit 49 set and is non-zero.
  -> make_loc_offset(offset)
    ccall_nobox("w_location_file_offset", @file_id, offset)

  # Derive (line, col) for a packed Token by looking up its offset in
  # the lexer-built tables. Each table is one entry per source
  # codepoint — large but already in memory, so the lookup is O(1).
  -> tok_line(packed_tok)
    @line_at[tok_off(packed_tok)]

  -> tok_col(packed_tok)
    @col_at[tok_off(packed_tok)]

  -> current_line
    @line_at[tok_off(@current_packed)]

  -> current_col
    @col_at[tok_off(@current_packed)]

  -> current_offset
    tok_off(@current_packed)

  # Compile-error helper — builds the runtime raise dict for a parse
  # error AT THE CURRENT POSITION, deriving file/row/col from @file
  # and the @line_at/@col_at lookup tables (indexed by the current
  # packed token's offset). Replaces the verbose hash-reading raise
  # blocks at error sites. Unrelated to make_loc_offset above: this
  # builds a plain Hash with row/col as ordinary Integers (no bit-
  # packing), so there's no truncation concern here to begin with.
  -> compile_error_at(code, message)
    off = tok_off(@current_packed)
    {rt: :compile_error, code: code, message: message, file: @file, row: @line_at[off], col: @col_at[off], span_length: 1}

  # Packed-loc for any packed Token. Used at AST-construction sites
  # that want the loc for a specific (peeked or saved) token rather
  # than @current_packed.
  -> make_loc_for(packed_tok)
    make_loc_offset(tok_off(packed_tok))

  -> make_loc_here
    make_loc_offset(tok_off(@current_packed))

  # Symbolic name for an integer token type id — used in error
  # messages where the human-friendly symbol name (e.g. "KEYWORD")
  # is more useful than the integer. Inverse of the lexer's
  # type_sym_to_id mapping. Unknown ids fall back to the integer
  # string so messages still surface SOMETHING even for new types
  # the table hasn't been updated for.
  -> tok_type_name(type_id)
    n = tok_type_name_a(type_id)
    if n != nil
      return n
    n = tok_type_name_b(type_id)
    if n != nil
      return n
    n = tok_type_name_c(type_id)
    if n != nil
      return n
    type_id.to_s()

  -> tok_type_name_a(type_id)
    case type_id
    when 0 then "UNKNOWN"
    when 1 then "ID"
    when 2 then "NAME"
    when 3 then "INT"
    when 4 then "DECIMAL"
    when 5 then "STRING"
    when 6 then "SYMBOL"
    when 7 then "TYPE_HINT"
    when 8 then "NEWLINE"
    when 9 then "INDENT"
    when 10 then "DEDENT"
    when 12 then "IVAR"
    when 13 then "CVAR"
    when 14 then "PARG"
    when 15 then "BYTE_ARRAY"
    when 16 then "KEY"
    when 17 then "COLOR"
    when 18 then "CHAR"
    when 19 then "CODEPOINT"
    when 20 then "WORD_ARRAY"
    when 21 then "SYMBOL_ARRAY"
    when 22 then "MAGIC"
    when 23 then "EOF"
    when 24 then "PATH"
    when 25 then "SP"
    when 26 then "KEYWORD"
    when 27 then "TYPE"
    when 28 then "GLOBAL"
    when 29 then "AND"
    when 30 then "OR"
    else nil

  -> tok_type_name_b(type_id)
    case type_id
    when 31 then "FLOAT"
    when 32 then "RATIONAL"
    when 33 then "WVALUE"
    when 34 then "DATE"
    when 35 then "DATETIME"
    when 36 then "TIME"
    when 37 then "MONTH"
    when 38 then "DURATION"
    when 39 then "IP"
    when 40 then "CIDR"
    when 41 then "UUID"
    when 42 then "BASE"
    when 43 then "CURRENCY"
    when 44 then "QUANTITY"
    when 45 then "LAMBDA_ARITY"
    when 46 then "REGEX_CAPTURE"
    when 47 then "STRING_INTERP"
    when 48 then "REGEX"
    when 49 then "BYTE_ARRAY_INTERP"
    when 50 then "LPAREN"
    when 51 then "RPAREN"
    when 52 then "LBRACE"
    when 53 then "RBRACE"
    when 54 then "LBRACKET"
    when 55 then "RBRACKET"
    when 56 then "COMMA"
    when 57 then "COLON"
    when 58 then "SEMICOLON"
    when 59 then "DOT"
    when 60 then "DOTDOT"
    when 61 then "DOTDOTDOT"
    when 62 then "ARROW"
    when 63 then "FAT_ARROW"
    when 64 then "SAFE_NAV"
    when 65 then "BANG"
    when 66 then "QUESTION"
    when 67 then "PIPE_FWD"
    when 68 then "MAP"
    when 69 then "BLOCK_CALL"
    when 70 then "CLASS_DEF"
    when 71 then "PUTS_OP"
    when 72 then "PRINT_OP"
    when 73 then "RAISE_OP"
    else nil

  -> tok_type_name_c(type_id)
    case type_id
    when 80 then "PLUS"
    when 81 then "MINUS"
    when 82 then "STAR"
    when 83 then "SLASH"
    when 84 then "PERCENT"
    when 85 then "POW"
    when 90 then "ASSIGN"
    when 91 then "PLUS_EQ"
    when 92 then "MINUS_EQ"
    when 93 then "STAR_EQ"
    when 94 then "SLASH_EQ"
    when 95 then "PERCENT_EQ"
    when 96 then "OR_ASSIGN"
    when 100 then "EQ"
    when 101 then "NEQ"
    when 102 then "LT"
    when 103 then "GT"
    when 104 then "LTE"
    when 105 then "GTE"
    when 106 then "SPACESHIP"
    when 107 then "MATCH"
    when 110 then "LSHIFT"
    when 111 then "RSHIFT"
    when 112 then "AMPERSAND"
    when 113 then "PIPE"
    when 114 then "CARET"
    when 120 then "DOT_PRODUCT"
    when 121 then "CROSS_PRODUCT"
    when 122 then "PLUS_PLUS"
    when 123 then "MINUS_MINUS"
    when 140 then "MAGIC_FILE"
    when 141 then "MAGIC_LINE"
    when 142 then "MAGIC_DIR"
    when 143 then "SUPERSCRIPT"
    when 145 then "BASE32"
    when 146 then "BASE58"
    when 147 then "BASE64"
    when 148 then "IP4"
    when 149 then "CIDR4"
    when 156 then "IP6"
    when 157 then "CIDR6"
    when 159 then "PLUS_MINUS"
    else nil

  # Exclusive end-of-span loc for the construct just parsed (AST task
  # #9). The parser hasn't advanced past the next token yet, so its
  # current() is exactly the position right after the construct's last
  # consumed character — the natural exclusive end.
  -> make_end_loc
    make_loc_here()

  # Formatted description of the current token for error messages:
  # "KEYWORD(if)" / "ID(x)" / "EOF()".
  -> current_desc
    "[tok_type_name(tok_type(@current_packed))]([current_value()])"

  # Returns the operator symbol (:PLUS, :STAR, …) for the current
  # token, then advances. Replaces the legacy `advance()[:type]`
  # idiom in the binary-op while-loops. The symbol contract is the
  # same one lowering's `op == :PLUS` branches consume.
  -> advance_op_sym
    sym = op_sym(tok_type(@current_packed))
    advance()
    sym

  -> op_sym(type_id)
    case type_id
    when T_PLUS then :PLUS
    when T_MINUS then :MINUS
    when T_STAR then :STAR
    when T_SLASH then :SLASH
    when T_PERCENT then :PERCENT
    when T_POW then :POW
    when T_DOT_PLUS then :DOT_PLUS
    when T_DOT_MINUS then :DOT_MINUS
    when T_DOT_STAR then :DOT_STAR
    when T_DOT_SLASH then :DOT_SLASH
    when T_DOT_PRODUCT then :DOT_PRODUCT
    when T_CROSS_PRODUCT then :CROSS_PRODUCT
    when T_HADAMARD then :HADAMARD
    when T_KRONECKER then :KRONECKER
    when T_LSHIFT then :LSHIFT
    when T_RSHIFT then :RSHIFT
    when T_DOT_LSHIFT then :DOT_LSHIFT
    when T_DOT_RSHIFT then :DOT_RSHIFT
    when T_EQ then :EQ
    when T_NEQ then :NEQ
    when T_MATCH then :MATCH
    when T_LT then :LT
    when T_GT then :GT
    when T_LTE then :LTE
    when T_GTE then :GTE
    when T_SPACESHIP then :SPACESHIP
    when T_AMPERSAND then :AMPERSAND
    when T_DOT_AMP then :DOT_AMP
    when T_PIPE then :PIPE
    when T_DOT_PIPE then :DOT_PIPE
    when T_CARET then :CARET
    when T_DOT_CARET then :DOT_CARET
    else nil

  -> parse
    exprs = parse_program()
    expect_type(T_EOF)
    Tungsten:AST:Program.new(exprs)

  # -- Token stream helpers --

  # Returns the W_LEXICAL_TOKEN i64 at `offset` non-SP positions
  # ahead, or 0 if past EOF. `peek_type(N)` is the common shorthand
  # for `tok_type(peek_packed(N))`.
  -> peek_packed(offset = 1)
    idx = @pos + 1
    seen = 0
    while idx < @token_count
      if tok_type(@packed_tokens[idx]) != T_SP
        seen += 1
        if seen == offset
          return @packed_tokens[idx]
      idx += 1
    0

  # Index in @packed_tokens/@values of the Nth non-SP token past
  # @pos. Returns -1 if past EOF. Used by peek_value_at(N) so it
  # can read @values[idx] without re-walking the SP skip.
  -> peek_pos(offset = 1)
    idx = @pos + 1
    seen = 0
    while idx < @token_count
      if tok_type(@packed_tokens[idx]) != T_SP
        seen += 1
        if seen == offset
          return idx
      idx += 1
    -1

  -> peek_type(offset = 1)
    tok_type(peek_packed(offset))

  # Pre-parsed value at `offset` non-SP positions ahead — reads from
  # @values, which mirrors the hash's :value slot. For ID/KEYWORD/TYPE
  # this is the raw identifier string; for FLOAT/COLOR/RATIONAL it's
  # the lexer's pre-decoded form. Different from .value(@source),
  # which gives raw source bytes only.
  -> peek_value(offset = 1)
    idx = peek_pos(offset)
    if idx < 0
      return nil
    @values[idx]

  # Pre-parsed value at the current position — same data the hash
  # carried in :value. Used at AST-construction sites that consume
  # the lexer's already-decoded form.
  -> current_value
    @values[@pos]

  -> advance
    if @pos >= @token_count
      return nil
    @pos += 1
    sync_current()
    nil

  # Advance-and-return the lexer-decoded value. Equivalent to
  # `advance_value()` but reads @values[@pos] before the bump,
  # avoiding the hash subscript.
  -> advance_value
    if @pos >= @token_count
      return nil
    v = @values[@pos]
    @pos += 1
    sync_current()
    v

  # Integer-id dispatch — same as at_type?(T_SYM) but reads the packed
  # Token's type field directly, skipping the symbol comparison and
  # avoiding hash lookups once the call site is migrated. T_X
  # constants live in core/token.w. The Token class is autoloaded
  # via Lexer.new → Token.make so its top-level T_X assignments are
  # in scope by the time the parser runs.
  -> at_type?(type_id)
    tok_type(@current_packed) == type_id

  -> minus_token?
    at_type?(T_MINUS)

  -> star_token?
    at_type?(T_STAR)

  -> data_decl_ahead?
    idx = @pos + 1
    while idx < @token_count && tok_type(@packed_tokens[idx]) == T_SP
      idx += 1
    if idx >= @token_count
      return false
    t = tok_type(@packed_tokens[idx])
    t == T_ID || t == T_TYPE

  # Integer-id companion of expect_type(T_SYM). Raises on mismatch.
  # No return value — all callers throw it away.
  -> expect_type(type_id)
    if tok_type(@current_packed) != type_id
      raise compile_error_at(:E_PARSE_EXPECTED_TOKEN, "Expected [type_id], got [current_desc()]")
    advance()

  # Combines expect_type + value read — replaces the common idiom
  # `expect_type_value(T_X)`. Raises on type mismatch, otherwise
  # returns @values[pos] then advances.
  -> expect_type_value(type_id)
    if tok_type(@current_packed) != type_id
      raise compile_error_at(:E_PARSE_EXPECTED_TOKEN, "Expected [type_id], got [current_desc()]")
    v = @values[@pos]
    advance()
    v

  # Accept either T_NAME (PascalCase) or T_CONSTANT (SCREAMING_SNAKE) —
  # both used to come through as T_NAME before the lexer split. Used at
  # positions like `+ Name`, `is Name`, etc. where pre-split code wrote
  # `expect_name_or_constant()` / `expect_name_or_constant_value()`.
  -> at_name_or_constant?
    at_type?(T_NAME) || at_type?(T_CONSTANT)

  -> expect_name_or_constant
    if !at_name_or_constant?()
      raise compile_error_at(:E_PARSE_EXPECTED_TOKEN, "Expected NAME or CONSTANT, got [current_desc()]")
    advance()

  -> expect_name_or_constant_value
    if !at_name_or_constant?()
      raise compile_error_at(:E_PARSE_EXPECTED_TOKEN, "Expected NAME or CONSTANT, got [current_desc()]")
    v = @values[@pos]
    advance()
    v

  -> at_kw?(kw)
    tok_type(@current_packed) == T_KEYWORD && @values[@pos] == kw

  -> expect_kw(kw)
    if !at_kw?(kw)
      raise compile_error_at(:E_PARSE_EXPECTED_TOKEN, "Expected keyword '[kw]', got [current_desc()]")
    advance()

  # Generic (type, literal) check — used for IVAR + specific name
  # combos like `@gpu`, `@schedule` that disambiguate attribute
  # directives. Same pattern as at_kw? but parameterized on type.
  -> at_typed?(type_id, literal)
    tok_type(@current_packed) == type_id && tok_equal?(@current_packed, @source, literal)

  -> expect_typed(type_id, literal)
    if !at_typed?(type_id, literal)
      raise compile_error_at(:E_PARSE_EXPECTED_TOKEN, "Expected '[literal]', got [current_desc()]")
    advance()

  -> expect_method_name
    if tok_type(@current_packed) in (T_ID T_TYPE T_KEYWORD T_NAME T_CONSTANT)
      advance()
      return nil
    if at_type?(T_LBRACKET) && peek_type() == T_RBRACKET
      advance()
      advance()
      if at_type?(T_ASSIGN)
        advance()
      return nil
    if tok_type(@current_packed) in (T_BANG T_PUTS_OP T_LSHIFT T_RSHIFT T_PLUS T_MINUS T_STAR T_POW T_SLASH T_PERCENT T_DOT_PRODUCT T_CROSS_PRODUCT T_HADAMARD T_KRONECKER T_EQ T_TRIPLE_EQ T_NEQ T_MATCH T_NMATCH T_LT T_GT T_LTE T_GTE T_SPACESHIP)
      advance()
      return nil
    raise compile_error_at(:E_PARSE_EXPECTED_METHOD_NAME, "Expected method name, got [current_desc()]")

  # String-returning companion. Same dispatch as expect_method_name
  # but returns just the name (e.g. "foo", "[]", "[]=", "+") without
  # the surrounding hash. Used at AST-construction sites that only
  # need the name + an already-captured loc.
  -> expect_method_name_value
    if tok_type(@current_packed) in (T_ID T_TYPE T_KEYWORD T_NAME T_CONSTANT)
      return advance_value()
    if at_type?(T_LBRACKET) && peek_type() == T_RBRACKET
      advance()
      advance()
      if at_type?(T_ASSIGN)
        advance()
        return "[]="
      return "[]"
    if tok_type(@current_packed) in (T_BANG T_PUTS_OP T_LSHIFT T_RSHIFT T_PLUS T_MINUS T_STAR T_POW T_SLASH T_PERCENT T_DOT_PRODUCT T_CROSS_PRODUCT T_HADAMARD T_KRONECKER T_EQ T_TRIPLE_EQ T_NEQ T_MATCH T_NMATCH T_LT T_GT T_LTE T_GTE T_SPACESHIP)
      return advance_value()
    # T_CLASS_DEF is the bare `+` token at line-start positions; after
    # `-> ` it's still the plus method name. Accept it here so
    # `-> +/1` (componentwise add) parses.
    if at_type?(T_CLASS_DEF)
      return advance_value()
    expect_method_name()
    ""

  -> identifier_name_token?
    tok_type(@current_packed) == T_ID || tok_type(@current_packed) == T_TYPE || at_kw?("with")

  -> keyword_label_token?
    (at_type?(T_ID) || at_kw?("with")) && peek_type() == T_COLON && peek_type(2) != T_COLON

  -> expect_identifier_name
    if identifier_name_token?()
      advance()
      return nil
    expect_type(T_ID)

  # String-returning companion — used at AST-construction sites that
  # just need the identifier name. expect_type_value(T_ID) doesn't
  # work for soft-identifier keywords (with, in) that
  # identifier_name_token? accepts; this helper preserves that.
  -> expect_identifier_name_value
    if identifier_name_token?()
      return advance_value()
    expect_type_value(T_ID)

  -> with_loop_start?
    peek_type() == T_ID && peek_type(2) == T_KEYWORD && peek_value(2) == "in"

  # Integer-id companion of match?(:SYM) — advances on match.
  -> match_type?(type_id)
    if tok_type(@current_packed) != type_id
      return false
    advance()
    true

  -> skip_newlines
    while tok_type(@current_packed) in (T_NEWLINE T_TYPE_HINT)
      if at_type?(T_TYPE_HINT)
        @pending_type_hints.push(current_value())
      advance()

  -> skip_spaces
    while at_type?(T_SP)
      advance()

  -> skip_statement_end
    while tok_type(@current_packed) in (T_NEWLINE T_SEMICOLON T_TYPE_HINT)
      if at_type?(T_TYPE_HINT)
        @pending_type_hints.push(current_value())
      advance()

  -> skip_block_whitespace
    while tok_type(@current_packed) in (T_NEWLINE T_SEMICOLON T_INDENT T_DEDENT)
      advance()

  # -- Program & body parsing --

  -> parse_program
    skip_newlines()
    exprs = []
    while !at_type?(T_EOF) && !at_type?(T_DEDENT)
      expr = parse_expression()
      exprs.push(finish_statement_expression(expr))
    exprs

  -> parse_body
    expect_type(T_INDENT)
    exprs = []
    while !at_type?(T_DEDENT) && !at_type?(T_EOF)
      expr = parse_expression()
      exprs.push(finish_statement_expression(expr))
    if !at_type?(T_EOF)
      expect_type(T_DEDENT)
    exprs

  -> finish_statement_expression(expr)
    skip_statement_end()
    expr = parse_statement_continuations(expr)
    while at_type?(T_PIPE_FWD)
      expr = parse_pipeline_tail(expr)
      skip_statement_end()
      expr = parse_statement_continuations(expr)
    expr

  -> statement_continuation_start?
    if at_type?(T_DOT)
      return true
    if at_type?(T_INDENT)
      t1_type = peek_type()
      if t1_type == T_DOT
        return true
      if t1_type == T_KEYWORD && peek_value() == "self" && peek_type(2) == T_DOT
        return true
    false

  -> parse_statement_continuations(expr)
    while statement_continuation_start?()
      if at_type?(T_DOT)
        expr = parse_continuation_call(expr, false)
        skip_statement_end()
      elsif at_type?(T_INDENT)
        advance()
        skip_newlines()
        while !at_type?(T_DEDENT) && !at_type?(T_EOF)
          if at_type?(T_DOT)
            expr = parse_continuation_call(expr, false)
          elsif at_kw?("self") && peek_type() == T_DOT
            expr = parse_continuation_call(expr, true)
          else
            break
          skip_statement_end()
        if at_type?(T_DEDENT)
          advance()
          skip_statement_end()
    expr

  -> parse_continuation_call(receiver, consume_self)
    if consume_self
      expect_kw("self")
      expect_type(T_DOT)
    else
      expect_type(T_DOT)
    # Capture line/col/loc of the method-name token BEFORE the call,
    # since expect_method_name() advances past it. For the synthetic
    # `[]` / `[]=` case the helper internally uses the same source
    # location (the LBRACKET), so this stays correct.
    name_line = current_line()
    name_col = current_col()
    name_loc = make_loc_here()
    name = expect_method_name_value()
    result = parse_call_args_and_block(true, name_line, name_col, name)
    args = result[0]
    block = result[1]
    if args == nil
      args = []
    call = Tungsten:AST:Call.new(receiver, name, args, block)
    call.loc = name_loc
    call.loc_end = make_end_loc()
    call

  # -- Expression parsing --

  -> is_block_node?(node)
    t = ast_kind(node)
    t in (:if :while :with :parallel_with :case :begin :method_def :fn_def :class_def :trait_def :on_guard)

  -> parse_expression(allow_passthrough = true)
    if at_kw?("trait")
      return parse_trait_def()

    if at_type?(T_CLASS_DEF)
      return parse_class_def()

    # `in NAMESPACE` file-level directive. Records the prefix on the
    # parser so subsequent `+ Foo` declarations get rewritten to
    # `NAMESPACE:Foo`. Lets ast.w drop the per-class `AST:` prefix.
    # Token shape: KEYWORD("in") SP CONSTANT/NAME/ID SYMBOL* NL.
    if at_kw?("in")
      ns_pos = @pos + 1
      while ns_pos < @token_count && tok_type(@packed_tokens[ns_pos]) == T_SP
        ns_pos += 1
      tt = tok_type(@packed_tokens[ns_pos])
      if tt == T_NAME || tt == T_CONSTANT || tt == T_TYPE || tt == T_ID
        advance()  # `in`
        skip_spaces()
        ns = advance_value()
        while at_type?(T_SYMBOL)
          ns = ns + ":" + current_value()
          advance()
        @namespace_prefix = ns
        return Tungsten:AST:NamespaceDecl.new(ns)

    # @fastmath / @strictmath scoped math-mode blocks.
    # Syntax: `@fastmath ->\n  body...` or inline `@fastmath -> expr`.
    # Lowering temporarily overrides ctx[:math_mode_override] to :fast/:strict
    # so float instructions inside the block carry the right fp_flags.
    if at_typed?(T_IVAR, "@fastmath") && peek_type() == T_ARROW
      return parse_mathmode_block(:fastmath_block)
    if at_typed?(T_IVAR, "@strictmath") && peek_type() == T_ARROW
      return parse_mathmode_block(:strictmath_block)

    # `Math.promote -> body` / `Math.trap -> body` / `Math.wrap -> body`
    # lexical integer-overflow-mode blocks. They re-route default int +/-/*
    # within the block's lexical scope: promote → BigInt on overflow, trap →
    # abort on overflow, wrap → explicit native silent-wrap. Token shape:
    # NAME("Math") DOT ID(mode) ARROW. Only intercepted for the three known
    # modes; any other `Math.foo -> ...` falls through to normal parsing.
    if at_type?(T_NAME) && current_value() == "Math" && peek_type() == T_DOT && peek_type(2) == T_ID && peek_type(3) == T_ARROW
      ovf_mode_name = peek_value(2)
      if ovf_mode_name == "promote" || ovf_mode_name == "trap" || ovf_mode_name == "wrap"
        return parse_overflow_block(ovf_mode_name)

    # GPU kernel attribute: `@gpu fn NAME(ARGS)` — top-level (not inside a
    # class body). Lowered to a target-specific shader (MSL for v1) by
    # compiler/lib/metal_emitter.w rather than through the normal
    # method-dispatch pipeline.
    if at_typed?(T_IVAR, "@gpu") && peek_type() == T_KEYWORD && peek_value() == "fn"
      return parse_gpu_kernel_def()

    # Schedule language (P3.4):
    #   @schedule kernel_name.variant_name
    #     axis :m, parallelize: :threadgroup
    #     axis :b, parallelize: :simdgroup_lane, stride: 32
    if at_typed?(T_IVAR, "@schedule") && peek_type() == T_ID && peek_type(2) == T_DOT
      return parse_schedule_def()
    if at_typed?(T_IVAR, "@layout") && peek_type() == T_ID && peek_type(2) == T_DOT
      return parse_layout_def()

    # `- ivars` block: typed slab-layout declaration for class
    # constructors. Format:
    #   - ivars
    #     @field1 w64
    #     @field2 ast
    # Emits {node: :ivars_decl, entries: [{name, type}, ...]} so
    # downstream lowering / generator passes can drive SC selection
    # and accessor generation from the declared shape. Lower
    # silently ignores unknown class-body node kinds, so this is
    # free to add even before the consumer lowering lands.
    if minus_token?() && peek_type() == T_ID && peek_value() == "ivars"
      advance()       # `-`
      skip_spaces()
      advance()       # `ivars`
      skip_newlines()
      entries = []
      if at_type?(T_INDENT)
        advance()
        while !at_type?(T_DEDENT) && !at_type?(T_EOF)
          skip_newlines()
          if at_type?(T_DEDENT) || at_type?(T_EOF)
            break
          if !at_type?(T_IVAR)
            raise compile_error_at(:E_PARSE_EXPECTED_IVAR, "Expected @ivar in `- ivars` block, got [current_desc()]")
          field_name = advance_value()
          # Type spec: slurp tokens up to the next newline. The
          # exact text doesn't matter at lower time yet; preserve
          # it for future tooling.
          type_parts = []
          while !at_type?(T_NEWLINE) && !at_type?(T_DEDENT) && !at_type?(T_EOF)
            type_parts.push(current_value())
            advance()
          entries.push({name: field_name, type: type_parts.join("")})
          skip_newlines()
        if at_type?(T_DEDENT)
          advance()
      return Tungsten:AST:IvarsDecl.new(entries)

    # Data declaration: - data / raw N OR typed fields
    # Only valid inside a class body (detected by indent context)
    if minus_token?() && data_decl_ahead?()
      saved = @pos
      advance()
      skip_spaces()
      if tok_type(@current_packed) in (T_ID T_TYPE)
        name = advance_value()
        skip_spaces()
        # Optional `(StructName)` — the backing C-struct name for this
        # class's instances. PascalCase here is a struct reference, not
        # a class reference; capture the raw value (don't parse through
        # parse_primary, which would make a class node) and register the
        # name in @struct_names so future passes can distinguish.
        struct_name = nil
        if at_type?(T_LPAREN)
          advance()
          skip_spaces()
          if at_name_or_constant?() || at_type?(T_ID) || at_type?(T_TYPE)
            struct_name = advance_value()
            register_struct_name(struct_name)
            skip_spaces()
          if at_type?(T_RPAREN)
            advance()
          skip_spaces()
        skip_newlines()
        if at_type?(T_INDENT)
          advance()
          skip_spaces()
          if at_type?(T_ID) && current_value() == "raw"
            # Raw byte layout: raw N
            advance()
            skip_spaces()
            if tok_type(@current_packed) == T_INT
              count = advance_value()
              skip_spaces()
              skip_newlines()
              if at_type?(T_DEDENT)
                advance()
              return Tungsten:AST:ViewDecl.new(name, "raw", count)
          else
            # Structured layout: typed fields
            fields = []
            depth = 1
            base_pointer_line = false
            while depth > 0 && !at_type?(T_EOF)
              if at_type?(T_INDENT)
                depth += 1
                advance()
              elsif at_type?(T_DEDENT)
                depth -= 1
                advance()
                if depth == 0 && star_token?()
                  depth = 1
                  base_pointer_line = true
              elsif at_type?(T_NEWLINE)
                advance()
                if base_pointer_line && !star_token?()
                  break
              elsif at_type?(T_SP)
                advance()
              elsif star_token?() || at_type?(T_ID) || at_type?(T_TYPE) || at_type?(T_NAME) || at_type?(T_CONSTANT)
                fields.push(parse_data_field())
              else
                advance()
            return Tungsten:AST:ViewDecl.new(name, "struct", {fields: fields, struct_name: struct_name})
        # Not a data decl — backtrack
        @pos = saved
        sync_current()
      else
        @pos = saved
        sync_current()

    start_line = current_line()
    expr = parse_assignment()

    # Implicit each: expr -> block (must be same line)
    t = ast_kind(expr)
    if t != :method_def && t != :fn_def && current_line() == start_line && (at_type?(T_ARROW) || at_type?(T_LBRACE))
      block = nil
      each_loc = make_loc_here()
      if at_type?(T_ARROW)
        block = parse_lambda()
      elsif at_type?(T_LBRACE)
        block = parse_block()
      if block != nil
        if ast_kind(expr) == :var && expr.name == "each"
          expr = Tungsten:AST:Call.new(nil, "each", [], block)
        else
          expr = Tungsten:AST:Call.new(expr, "each", [], block)
        expr.loc = each_loc
        expr.loc_end = make_end_loc()

    # Suffix if/unless/while/rescue (only for simple expressions, not block statements)
    if !is_block_node?(expr) && current_line() == start_line
      if at_kw?("if")
        advance()
        condition = parse_assignment()
        expr = Tungsten:AST:If.new(condition, [expr])

      elsif at_kw?("unless")
        advance()
        condition = parse_assignment()
        expr = Tungsten:AST:If.new(Tungsten:AST:Not.new(condition), [expr])

      elsif at_kw?("while")
        advance()
        condition = parse_assignment()
        expr = Tungsten:AST:While.new(condition, [expr])

      elsif at_kw?("rescue")
        advance()
        fallback = parse_assignment()
        expr = Tungsten:AST:RescueExpr.new(expr, fallback)

    if allow_passthrough && current_line() == start_line && at_type?(T_COLON)
      # `<int>: a, b, c` — initialize each of a, b, c to <int> (multi-init).
      # An int literal as a bare statement is never a meaningful passthrough,
      # so the int gate disambiguates from `expr : x`. Desugars to a
      # MultiAssign destructuring a replicated array.
      if ast_kind(expr) == :int
        advance()
        targets = [Tungsten:AST:Var.new(advance_value())]
        while at_type?(T_COMMA)
          advance()
          targets.push(Tungsten:AST:Var.new(advance_value()))
        elements = []
        i = 0
        while i < targets.size()
          elements.push(expr)
          i += 1
        return Tungsten:AST:MultiAssign.new(targets, Tungsten:AST:Array.new(elements))
      advance()
      passthrough = parse_assignment()
      expr = Tungsten:AST:Passthrough.new(expr, passthrough)

    expr

  -> parse_assignment
    left = parse_ternary()

    # Swap: `a <> b` exchanges two variables. Desugars to the same
    # MultiAssign shape the multi-init path builds — targets [a, b]
    # destructuring the array [b, a] — so lowering and the interpreter
    # need no new node kind.
    if at_type?(T_SWAP) && ast_kind(left) == :var
      advance()
      lname = left.name
      rname = expect_type_value(T_ID)
      targets = [Tungsten:AST:Var.new(lname), Tungsten:AST:Var.new(rname)]
      elements = [Tungsten:AST:Var.new(rname), Tungsten:AST:Var.new(lname)]
      return Tungsten:AST:MultiAssign.new(targets, Tungsten:AST:Array.new(elements))

    # Multi-assignment: a, b = expr
    # Use backtracking: restore position if we don't find '=' after the targets
    # Only attempt if left is a valid assignment target type
    if at_type?(T_COMMA) && valid_assign_target?(left)
      saved_pos = @pos
      targets = [to_assign_target(left)]
      found_assign = false
      while at_type?(T_COMMA)
        advance()
        # Multi-assign targets are always simple identifiers — advance a single token
        if at_type?(T_ID)
          targets.push(Tungsten:AST:Var.new(advance_value()))
        elsif at_type?(T_IVAR)
          targets.push(Tungsten:AST:Ivar.new(advance_value()))
        elsif at_type?(T_CVAR)
          targets.push(Tungsten:AST:Cvar.new(advance_value()))
        else
          break
        if at_type?(T_ASSIGN)
          found_assign = true
          break
      if found_assign
        advance()
        value = parse_assignment()
        return Tungsten:AST:MultiAssign.new(targets, value)
      @pos = saved_pos
      sync_current()

    if at_type?(T_ASSIGN)
      advance()
      value = parse_assignment()
      # Inline type annotation: a = 34 ## i128
      # Inline memory hint:     a = [] ## reuse  /  a = {} ## recycle
      # Inline axis tag:        a = expr ## axis :name [, type]
      hint = nil
      axis_name = nil
      if at_type?(T_TYPE_HINT)
        hint = current_value()
        # Strip trailing comment: "i64  # comment" → "i64"
        comment_pos = hint.index("#")
        if comment_pos != nil
          hint = hint.slice(0, comment_pos)
        hint = hint.strip()
        advance()
        # Memory hints attach to the RHS allocation node, not to the assign
        # as a type annotation. Lowering reads :reuse_safe from the literal.
        if hint == "reuse"
          if value != nil
            value.reuse_safe = true
          hint = nil
        elsif hint == "recycle"
          if value != nil
            value.recycle_safe = true
          hint = nil
        elsif hint == "reuse_drain"
          # Hash-only: reuse slot + drain values to pools on reset. Only
          # applies to {} literals; non-hash RHS silently ignores.
          if value != nil && ast_kind(value) == :hash_literal
            value.reuse_safe = true
            value.drain_safe = true
          hint = nil
        elsif hint == "stack"
          # Phase 6d: opt-in stack allocation for SmallArray.new (and
          # eventually array literals). Caller asserts the value won't
          # outlive its allocating frame. Phase 6e's escape analysis
          # will set this flag automatically when safe.
          if value != nil
            value.stack_safe = true
          hint = nil
        elsif hint.starts_with?("axis ")
          # Schedule-language axis tag: `## axis :m` or `## axis :b, i32`.
          # Stored on the assign as :axis_name; remaining text after a
          # comma is the type hint.
          rest = hint.slice(5, hint.size() - 5).strip()
          comma_pos = rest.index(",")
          if comma_pos != nil
            axis_part = rest.slice(0, comma_pos).strip()
            type_part = rest.slice(comma_pos + 1, rest.size() - comma_pos - 1).strip()
            hint = type_part
          else
            axis_part = rest
            hint = nil
          if axis_part.starts_with?(":")
            axis_part = axis_part.slice(1, axis_part.size() - 1)
          axis_name = axis_part
      target = to_assign_target(left)
      result = Tungsten:AST:Assign.new(target, value, hint)
      if axis_name != nil
        result.axis_name = axis_name
      return result

    if at_type?(T_PLUS_EQ)
      advance()
      value = parse_assignment()
      target = to_assign_target(left)
      return Tungsten:AST:CompoundAssign.new(target, :PLUS, value)

    if at_type?(T_MINUS_EQ)
      advance()
      value = parse_assignment()
      target = to_assign_target(left)
      return Tungsten:AST:CompoundAssign.new(target, :MINUS, value)

    if at_type?(T_STAR_EQ)
      advance()
      value = parse_assignment()
      target = to_assign_target(left)
      return Tungsten:AST:CompoundAssign.new(target, :STAR, value)

    if at_type?(T_SLASH_EQ)
      advance()
      value = parse_assignment()
      target = to_assign_target(left)
      return Tungsten:AST:CompoundAssign.new(target, :SLASH, value)

    if at_type?(T_PERCENT_EQ)
      advance()
      value = parse_assignment()
      target = to_assign_target(left)
      return Tungsten:AST:CompoundAssign.new(target, :PERCENT, value)

    if at_type?(T_PLUS_PLUS)
      advance()
      target = to_assign_target(left)
      return Tungsten:AST:CompoundAssign.new(target, :PLUS, Tungsten:AST:Int.new(1))

    if at_type?(T_MINUS_MINUS)
      advance()
      target = to_assign_target(left)
      return Tungsten:AST:CompoundAssign.new(target, :MINUS, Tungsten:AST:Int.new(1))

    if at_type?(T_OR_ASSIGN)
      advance()
      value = parse_assignment()
      target = to_assign_target(left)
      return Tungsten:AST:Assign.new(target, Tungsten:AST:Or.new(left, value))

    left

  -> valid_assign_target?(node)
    t = ast_kind(node)
    if !(t in (:var :gvar :ivar :cvar :call))
      return false
    # Reject bare `func(args)` (no receiver, has args) — it would
    # silently lower as `func = value` (local-var assign of the
    # function name) rather than an intended ast_set/setter call.
    if t == :call && node.receiver == nil && !node.args.empty?()
      return false
    true

  -> to_assign_target(node)
    if ast_kind(node) in (:var :gvar :ivar :cvar)
      return node
    if ast_kind(node) == :call
      if node.receiver == nil && node.args.empty?() && node.block == nil
        return Tungsten:AST:Var.new(node.name)
      # `recv.method(...) = value` is valid (setter dispatch). A bare
      # `func(...) = value` with no receiver silently falls through to
      # a local-var assign of the function name — dropping the intended
      # mutation. Reject so typos like `node.x = v` surface.
      if node.receiver == nil
        raise compile_error_at(:E_PARSE_INVALID_ASSIGN_TARGET, "Cannot assign to a bare function call — did you mean a setter via `ast_set(...)` or `obj.method = ...`?")
      return node
    raise compile_error_at(:E_PARSE_INVALID_ASSIGN_TARGET, "Invalid assignment target")

  # -- Ranges --

  -> parse_ternary
    condition = parse_message_chain()
    if at_type?(T_QUESTION)
      advance()
      true_val = parse_expression(false)
      # Drop a `## type` ascription on the true branch (e.g.
      # `cond ? 1 ## T : 0 ## T`). v0 doesn't apply the hint;
      # lowering still infers from the underlying expression.
      while at_type?(T_TYPE_HINT)
        advance()
      expect_type(T_COLON)
      false_val = parse_expression(false)
      return Tungsten:AST:If.new(condition, [true_val], [], [false_val])
    condition

  # Space-separated trailing method call: `EXPR .method(args)` binds the call
  # to the WHOLE preceding expression (low precedence), unlike `EXPR.method`
  # (no space) which binds tightly to the immediate operand. Lets a range or
  # other operator expression be the receiver without parens, e.g.
  # `0..100 .count(:prime?)` == `(0..100).count(:prime?)`.
  #
  # sync_current() transparently skips :SP and records @sp_before, so a
  # space-preceded `.` shows up as a T_DOT with @sp_before true. The tight
  # postfix loop (parse_postfix_from) declines such a dot (`!@sp_before`),
  # leaving it for this lower-precedence level. A leading-dot line
  # continuation arrives as a newline, not @sp_before, so it is untouched.
  -> parse_message_chain
    expr = parse_range()
    while at_type?(T_DOT) && @sp_before
      dot_loc = make_loc_here()
      advance()
      name_line = current_line()
      name_col = current_col()
      name = expect_method_name_value()
      result = parse_call_args_and_block(true, name_line, name_col, name)
      args = result[0]
      block = result[1]
      if args == nil
        args = []
      call = Tungsten:AST:Call.new(expr, name, args, block)
      call.loc = dot_loc
      call.loc_end = make_end_loc()
      # Any tight postfix (`.foo` `/map` `[i]`) chains onto the result.
      expr = parse_postfix_from(call)
    expr

  -> parse_range
    left = parse_pipeline()
    if at_type?(T_DOTDOT)
      advance()
      # Open-ended range: 1.. (right absent)
      right = nil
      if !at_type?(T_RBRACKET) && !at_type?(T_RPAREN) && !at_type?(T_NEWLINE) && !at_type?(T_EOF) && !at_type?(T_COMMA) && !at_type?(T_DEDENT) && !at_type?(T_ARROW)
        right = parse_or()
      return Tungsten:AST:Range.new(left, right, false)
    if at_type?(T_DOTDOTDOT)
      advance()
      right = nil
      if !at_type?(T_RBRACKET) && !at_type?(T_RPAREN) && !at_type?(T_NEWLINE) && !at_type?(T_EOF) && !at_type?(T_COMMA) && !at_type?(T_DEDENT) && !at_type?(T_ARROW)
        right = parse_or()
      return Tungsten:AST:Range.new(left, right, true)
    left

  -> parse_pipeline
    left = parse_or()
    while at_type?(T_PIPE_FWD)
      left = parse_pipeline_tail(left)
    left

  -> parse_pipeline_tail(left)
    advance()
    if at_type?(T_DOT)
      dot_loc = make_loc_here()
      advance()
      name_line = current_line()
      name_col = current_col()
      name = expect_method_name_value()
      result = parse_call_args_and_block(true, name_line, name_col, name)
      args = result[0]
      block = result[1]
      if args == nil
        args = []
      call = Tungsten:AST:Call.new(left, name, args, block)
      call.loc = dot_loc
      call.loc_end = make_end_loc()
      return call
    target = parse_or()
    pipe_target(left, target)

  -> pipe_target(left, target)
    if ast_kind(target) == :call
      recv = target.receiver
      args = [left]
      if target.args != nil
        i = 0
        while i < target.args.size()
          args.push(target.args[i])
          i += 1
      if recv != nil && ast_kind(recv) == :self_ref
        return Tungsten:AST:Call.new(left, target.name, target.args, target.block)
      return Tungsten:AST:Call.new(recv, target.name, args, target.block)
    if ast_kind(target) == :var
      return Tungsten:AST:Call.new(nil, target.name, [left])
    Tungsten:AST:Call.new(target, "call", [left])

  # -- Operator precedence chain --

  -> parse_or
    left = parse_and()
    while at_type?(T_OR)
      advance()
      right = parse_and()
      left = Tungsten:AST:Or.new(left, right)
    left

  -> parse_and
    left = parse_in_test()
    while at_type?(T_AND)
      advance()
      right = parse_in_test()
      left = Tungsten:AST:And.new(left, right)
    left

  # Membership test: `c in (a b c)` — space-separated tuple form.
  # The tuple syntax is scoped to the RHS of `in` only; no other
  # production recognizes space-separated parenthesized expressions.
  # Lowered to a flat OR chain of equality comparisons at lowering
  # time; Phase 8 peephole promotes homogeneous chains to dispatch.
  -> parse_in_test
    left = parse_bitwise_or()
    if at_kw?("in")
      advance()
      if !at_type?(T_LPAREN)
        raise compile_error_at(:E_PARSE_IN_EXPECTS_TUPLE, "`in` requires a parenthesized tuple on the right-hand side")
      advance()
      elements = []
      # Suppress bare-arg parsing while inside the tuple — otherwise
      # `in (A B C)` parses A as a Name and treats B/C as its bare
      # args, turning a 3-element tuple into a 1-element function call.
      # The flag is checked in parse_call_args_and_block.
      prev_no_bare_args = @no_bare_args
      @no_bare_args = true
      while !at_type?(T_RPAREN) && !at_type?(T_EOF)
        elements.push(parse_expression())
      @no_bare_args = prev_no_bare_args
      if elements.size() == 0
        raise compile_error_at(:E_PARSE_IN_EMPTY_TUPLE, "`in` tuple must have at least one element")
      expect_type(T_RPAREN)
      return Tungsten:AST:InTest.new(left, elements)
    left

  -> parse_bitwise_or
    left = parse_bitwise_xor()
    # Phase 4e dot-prefix: `.|` shares bitwise-or precedence with `|`.
    while at_type?(T_PIPE) || at_type?(T_DOT_PIPE)
      op = advance_op_sym()
      right = parse_bitwise_xor()
      left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_bitwise_xor
    left = parse_bitwise_and()
    # Phase 4e dot-prefix: `.^` shares bitwise-xor precedence with `^`.
    while at_type?(T_CARET) || at_type?(T_DOT_CARET)
      op = advance_op_sym()
      right = parse_bitwise_and()
      left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_bitwise_and
    left = parse_comparison()
    # Phase 4e dot-prefix: `.&` shares bitwise-and precedence with `&`.
    while at_type?(T_AMPERSAND) || at_type?(T_DOT_AMP)
      op = advance_op_sym()
      right = parse_comparison()
      left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_comparison
    left = parse_equality()
    while tok_type(@current_packed) in (T_LT T_LTE T_GT T_GTE T_SPACESHIP)
      op = advance_op_sym()
      right = parse_equality()
      if op == :SPACESHIP
        # `<=>` has no runtime primitive — it is an ordinary polymorphic
        # method (defined per class via `-> <=>/1`). Lower it as a direct
        # method call so the receiver's own `<=>` runs.
        left = Tungsten:AST:Call.new(left, "<=>", [right])
      else
        left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_equality
    left = parse_addition()
    while tok_type(@current_packed) in (T_EQ T_NEQ T_MATCH)
      op = advance_op_sym()
      right = parse_addition()
      left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_addition
    left = parse_shift()
    # If left is a block-introducing statement (while/if/loop/etc),
    # don't continue with binary ops. The block's value (typically nil)
    # shouldn't combine with a following `-N` on the next line —
    # `while ...; -1` would parse as `(while ...) - 1` → nil-1.
    if is_block_node?(left)
      return left
    # Phase 4e dot-prefix elementwise: `.+ .-` share addition precedence
    # with their scalar counterparts. Julia convention.
    while tok_type(@current_packed) in (T_PLUS T_MINUS T_DOT_PLUS T_DOT_MINUS T_PLUS_MINUS)
      measurement = at_type?(T_PLUS_MINUS)
      if measurement
        advance()
      else
        op = advance_op_sym()
      right = parse_shift()
      if measurement
        left = Tungsten:AST:Call.new(Tungsten:AST:ClassRef.new("Measurement"), "new", [left, right], nil)
      else
        left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_shift
    left = parse_multiplication()
    # Phase 4e dot-prefix: `.<<` `.>>` share shift precedence.
    while tok_type(@current_packed) in (T_LSHIFT T_RSHIFT T_DOT_LSHIFT T_DOT_RSHIFT)
      op = advance_op_sym()
      right = parse_multiplication()
      left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_multiplication
    left = parse_power()
    # Phase 4e dot-prefix elementwise: `.* ./` share multiplication
    # precedence with their scalar counterparts.
    while tok_type(@current_packed) in (T_STAR T_SLASH T_PERCENT T_DOT_STAR T_DOT_SLASH T_DOT_PRODUCT T_CROSS_PRODUCT T_HADAMARD T_KRONECKER)
      op = advance_op_sym()
      right = parse_power()
      left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_power
    left = parse_unary()
    if at_type?(T_EXPONENT)
      # Superscript exponent: `x⁷` ⇒ `x ** 7`. The EXPONENT token carries
      # the decoded digit string; build the same BinaryOp a written `**`
      # would, so the rest of the compiler is none the wiser.
      exp_raw = current_value()
      advance()
      exp_lit = Tungsten:AST:Int.new(parse_int_value(exp_raw), nil, exp_raw)
      return Tungsten:AST:BinaryOp.new(left, :POW, exp_lit)
    if at_type?(T_POW)
      op = advance_op_sym()
      right = parse_power()
      return Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_unary
    if at_type?(T_BANG)
      advance()
      operand = parse_unary()
      return Tungsten:AST:Not.new(operand)
    if at_type?(T_SQRT)
      # `√expr` ⇒ `expr.sqrt`. The operand parses at power precedence so
      # `√x²` reads as `√(x²)`, matching the math convention.
      advance()
      operand = parse_power()
      return Tungsten:AST:Call.new(operand, "sqrt", [], nil)
    if at_type?(T_STAR)
      advance()
      operand = parse_unary()
      return Tungsten:AST:UnaryOp.new(:DEREF, operand)
    if at_type?(T_MINUS)
      advance()
      operand = parse_unary()
      return Tungsten:AST:UnaryOp.new(:MINUS, operand)
    parse_call_chain()

  # -- Method calls, indexing, dot access --

  -> parse_call_chain
    expr_line = current_line()
    parse_postfix_from(parse_primary())

  # Tight postfix chain (`.method` `/map` `:reduce` `[]` `?.`) applied to an
  # already-parsed receiver. Shared by parse_call_chain (seeded with a primary)
  # and parse_message_chain (seeded after a space-separated `.method`).
  -> parse_postfix_from(expr)
    cont = true
    saw_map = false
    while cont
      if at_type?(T_MAP)
        map_loc = make_loc_here()
        advance()
        stage_name = expect_method_name_value()
        stage_args = []
        if at_type?(T_LPAREN)
          advance()
          stage_args = parse_arg_list(:RPAREN)
          expect_type(T_RPAREN)
        expr = build_pipeline_stage(expr, stage_name, stage_args)
        expr.loc = map_loc
        expr.loc_end = make_end_loc()
        saw_map = true
      elsif at_type?(T_SYMBOL) && (saw_map || ast_kind(expr) in (:range :array))
        # Trailing `:reduce`. Normally requires a preceding `/map` stage
        # to disambiguate `expr:sym` from other colon uses — but a bare
        # `(1..n):sum` / `[1,2,3]:sum` (range/array source, no map) is
        # unambiguously a reduce, so accept it there too. This lets a
        # plain ranged sum reach the pipeline lowering (and its O(1)
        # closed form) instead of materializing the range.
        sym_loc = make_loc_here()
        reduce_name = advance_value()
        expr = build_pipeline_reduce(expr, reduce_name)
        expr.loc = sym_loc
        expr.loc_end = make_end_loc()
        saw_map = false
      elsif at_type?(T_DOT) && !@sp_before
        advance()
        name_line = current_line()
        name_col = current_col()
        name_loc = make_loc_here()
        name = expect_method_name_value()
        result = parse_call_args_and_block(true, name_line, name_col, name)
        args = result[0]
        block = result[1]
        if args == nil
          args = []
        receiver = expr
        expr = Tungsten:AST:Call.new(receiver, name, args, block)
        # ClassRef nodes are interned by name, so sparse metadata written on
        # `Tensor` would otherwise leak to every Tensor reference parsed later.
        # Unit-bearing Tensor syntax belongs to this factory call, not the
        # globally interned class leaf.
        if ast_kind(receiver) == :class_ref && receiver.name == "Tensor" && receiver.type_args != nil
          expr.type_args = receiver.type_args
          receiver.type_args = nil
        expr.loc = name_loc
        expr.loc_end = make_end_loc()
      elsif at_type?(T_SAFE_NAV)
        advance()
        name_line = current_line()
        name_col = current_col()
        name_loc = make_loc_here()
        name = expect_method_name_value()
        result = parse_call_args_and_block(true, name_line, name_col, name)
        args = result[0]
        block = result[1]
        if args == nil
          args = []
        expr = Tungsten:AST:SafeNav.new(expr, name, args, block)
        expr.loc = name_loc
        expr.loc_end = make_end_loc()
      elsif at_type?(T_GLOBAL) && !@sp_before
        # `expr$field` — postfix view-decl field access on an explicit
        # receiver (no space before the `$`, mirroring the tight `.method`
        # rule above). The lexer emits `$field` as a T_GLOBAL whose value
        # includes the leading `$`; strip it for the field name. A bare
        # `$field` (no left-hand receiver) is unaffected — it never enters
        # this loop and still parses as a GVar / __self view-field read.
        vf_loc = make_loc_here()
        vf_raw = advance_value()
        vf_field = vf_raw.slice(1, vf_raw.size() - 1)
        expr = Tungsten:AST:ViewFieldVar.new(expr, vf_field)
        expr.loc = vf_loc
        expr.loc_end = make_end_loc()
      elsif at_type?(T_LBRACKET) && !is_block_node?(expr)
        lbr_loc = make_loc_here()
        advance()
        index = parse_expression()
        expect_type(T_RBRACKET)
        if at_type?(T_ASSIGN)
          advance()
          value = parse_assignment()
          expr = Tungsten:AST:Call.new(expr, "\[]=", [index, value])
        else
          expr = Tungsten:AST:Call.new(expr, "\[]", [index])
        expr.loc = lbr_loc
        expr.loc_end = make_end_loc()
      else
        cont = false

    expr

  # Build one pipeline stage from `source /name(args)`. `select`/`reject`/
  # `detect` are recognized filter/find stages; any other name is a map
  # (apply `name(args)` to each element). The element-applied function is a
  # Call with a nil receiver — lowering interprets nil-receiver as "the
  # current element", and recognizes known elementwise calcs (sq/cube/…).
  -> build_pipeline_stage(source, name, args)
    if name == "select"
      return Tungsten:AST:Map.new(source, pipeline_predicate(args), :select)
    if name == "reject"
      return Tungsten:AST:Map.new(source, pipeline_predicate(args), :reject)
    if name == "detect"
      sel = Tungsten:AST:Map.new(source, pipeline_predicate(args), :select)
      return Tungsten:AST:Calc.new("detect", sel, :auto)
    # Explicit `map(-> (x) …)` — the block IS the per-element function,
    # not a method named "map" applied to each element.
    if name == "map" && args.size() == 1 && ast_kind(args[0]) == :block
      return Tungsten:AST:Map.new(source, args[0], :map)
    # `Σ(expr)` is sugar for `map(x -> expr):sum` — a sum over the range of
    # the polynomial `expr` in its bound variable x (the trailing `:sum` is
    # redundant). The bound variable is inferred as the single distinct name
    # in the body — a bare `x` or the base of an implicit-mult quantity like
    # `2x⁷` (which lexes as QUANTITY[2,"x⁷"]); those are then rewritten to
    # real arithmetic. An explicit `Σ(x -> …)` lambda is used as-is.
    # Desugars to the same Calc(sum, Map) the closed-form recognizer folds.
    # Falls through to a plain map if the variable can't be inferred.
    if name == "Σ" && args.size() == 1
      sig_body = args[0]
      if ast_kind(sig_body) == :block
        return Tungsten:AST:Calc.new("sum", Tungsten:AST:Map.new(source, sig_body, :map), :auto)
      sig_bases = []
      sigma_collect_var_bases(sig_body, sig_bases)
      if sig_bases.size() == 1
        sig_var = sig_bases[0]
        sig_rbody = sigma_rewrite(sig_body, sig_var)
        sig_lam = Tungsten:AST:Block.new([sig_var], [sig_rbody])
        return Tungsten:AST:Calc.new("sum", Tungsten:AST:Map.new(source, sig_lam, :map), :auto)
    func = Tungsten:AST:Call.new(nil, name, args, nil)
    Tungsten:AST:Map.new(source, func, :map)

  # The predicate of select/reject/detect: `select(:even?)` keeps elements
  # where `element.even?`. args[0] is the predicate-name symbol; any extra
  # args become call args (`select(:>, 5)` → element.>(5)).
  -> pipeline_predicate(args)
    if args.size() >= 1 && ast_kind(args[0]) == :symbol
      pname = "" + args[0].value
      rest = []
      i = 1
      while i < args.size()
        rest.push(args[i])
        i += 1
      return Tungsten:AST:Call.new(nil, pname, rest, nil)
    Tungsten:AST:Call.new(nil, "itself", [], nil)

  # Trailing `:name` reduce. Builds a terminal Calc wrapping the map chain;
  # lowering fuses known reducing calcs (sum/min/max/product) inline and
  # falls back to a `.reduce` call for anything else.
  -> build_pipeline_reduce(source, reduce_name)
    Tungsten:AST:Calc.new("" + reduce_name, source, :auto)

  # Σ(expr[, range]) / ∫(expr[, range]) called as plain functions rather than
  # pipeline stages: rewrite the polynomial body into a real lambda Block,
  # exactly as the pipeline Σ does (implicit-mult quantities like 2x⁷ become
  # 2*x**7). The interpreter provides the Σ/∫ builtins; bounds come from the
  # optional range argument (the REPL inspector defaults Σ's when omitted).
  -> math_fn_rewrite(name, args)
    if !(name in ("Σ" "∫"))
      return args
    if args == nil || args.size() < 1 || args.size() > 2
      return args
    body = args[0]
    if !is_ast_node?(body) || ast_kind(body) == :block
      return args
    bases = []
    sigma_collect_var_bases(body, bases)
    if bases.size() != 1
      return args
    svar = bases[0]
    rbody = sigma_rewrite(body, svar)
    lam = Tungsten:AST:Block.new([svar], [rbody])
    out = [lam]
    if args.size() == 2
      out.push(args[1])
    out

  # Collect the distinct bare-variable names in `expr`, used to infer the
  # bound variable of a `Σ(…)` sum (e.g. `x` in `Σ(2x⁷ + 3x²)`).
  -> collect_pipeline_var_names(expr, acc)
    if !is_ast_node?(expr)
      return nil
    k = ast_kind(expr)
    if k == :var
      nm = "" + expr.name
      found = false
      ai = 0
      while ai < acc.size()
        if acc[ai] == nm
          found = true
        ai += 1
      if !found
        acc.push(nm)
    elsif k == :binary_op
      collect_pipeline_var_names(expr.left, acc)
      collect_pipeline_var_names(expr.right, acc)
    elsif k == :unary_op
      collect_pipeline_var_names(expr.operand, acc)
    elsif k == :call
      r = expr.receiver
      if r != nil
        collect_pipeline_var_names(r, acc)
      cargs = expr.args
      if cargs != nil
        ci = 0
        while ci < cargs.size()
          collect_pipeline_var_names(cargs[ci], acc)
          ci += 1
    nil

  # The single bound variable of a `Σ(…)` body, or nil if the expression
  # has zero or several free variables (then we can't infer it).
  -> pipeline_single_var(expr)
    names = []
    collect_pipeline_var_names(expr, names)
    if names.size() == 1
      return names[0]
    nil

  # A Unicode superscript-digit char → its value, or -1. Used to split a
  # quantity unit like "x⁷" for implicit multiplication inside Σ.
  -> sigma_sup_digit(c)
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

  # Split a quantity unit into [base, exponent]: "x⁷" → ["x", 7],
  # "x" → ["x", 1]. nil if there is no leading identifier base.
  -> sigma_decode_unit(unit)
    cs = unit.chars()
    base = ""
    i = 0
    while i < cs.size() && sigma_sup_digit(cs[i]) < 0
      base = base + cs[i]
      i = i + 1
    if base.size() == 0
      return nil
    exp = 1
    if i < cs.size()
      exp = 0
      while i < cs.size()
        d = sigma_sup_digit(cs[i])
        if d < 0
          return nil
        exp = exp * 10 + d
        i = i + 1
    [base, exp]

  -> sigma_add_base(acc, nm)
    found = false
    i = 0
    while i < acc.size()
      if acc[i] == nm
        found = true
      i = i + 1
    if !found
      acc.push(nm)

  # Distinct candidate variable names in a `Σ(…)` body: bare vars (`x`) and
  # the bases of implicit-mult quantities (`2x⁷` → base `x`). Exactly one
  # distinct name ⇒ that is the bound variable.
  -> sigma_collect_var_bases(node, acc)
    if !is_ast_node?(node)
      return nil
    k = ast_kind(node)
    if k == :var
      sigma_add_base(acc, "" + node.name)
    elsif k == :quantity
      dec = sigma_decode_unit("" + node.unit)
      if dec != nil
        sigma_add_base(acc, dec[0])
    elsif k == :binary_op
      sigma_collect_var_bases(node.left, acc)
      sigma_collect_var_bases(node.right, acc)
    elsif k == :unary_op
      sigma_collect_var_bases(node.operand, acc)
    elsif k == :call
      r = node.receiver
      if r != nil
        sigma_collect_var_bases(r, acc)
      cargs = node.args
      if cargs != nil
        ci = 0
        while ci < cargs.size()
          sigma_collect_var_bases(cargs[ci], acc)
          ci += 1
    nil

  # Build an Int AST node from an integer value via its decimal text — the
  # same construction T_INT uses (a bare Int.new(n) stores a value that
  # ast_get(:value) reads back wrong downstream).
  -> sigma_int(n)
    s = "" + n.to_s()
    Tungsten:AST:Int.new(parse_int_value(s), nil, s)

  # Rewrite implicit-mult quantities whose base is the bound variable into
  # arithmetic: QUANTITY[2,"x⁷"] with svar="x" → `2 * x ** 7`. A quantity
  # on any other base (a real unit like `5m²`) is left untouched.
  -> sigma_rewrite(node, svar)
    if !is_ast_node?(node)
      return node
    k = ast_kind(node)
    if k == :quantity
      dec = sigma_decode_unit("" + node.unit)
      if dec != nil && dec[0] == svar
        coeff = sigma_int(parse_int_value("" + node.number_str))
        vref = Tungsten:AST:Var.new(svar)
        if dec[1] == 1
          return Tungsten:AST:BinaryOp.new(coeff, :STAR, vref)
        powed = Tungsten:AST:BinaryOp.new(vref, :POW, sigma_int(dec[1]))
        return Tungsten:AST:BinaryOp.new(coeff, :STAR, powed)
      return node
    if k == :binary_op
      node.left = sigma_rewrite(node.left, svar)
      node.right = sigma_rewrite(node.right, svar)
      return node
    if k == :unary_op
      node.operand = sigma_rewrite(node.operand, svar)
      return node
    if k == :call
      r = node.receiver
      if r != nil
        node.receiver = sigma_rewrite(r, svar)
      cargs = node.args
      if cargs != nil
        # Child-list arrays are immutable once frozen into a node's
        # slot (even a just-constructed Call's :args — slab_alloc_init
        # freezes on construction), so rebuild and write the whole
        # field back rather than index-assigning into `cargs`.
        new_args = []
        ci = 0
        while ci < cargs.size()
          new_args.push(sigma_rewrite(cargs[ci], svar))
          ci += 1
        node.args = new_args
      return node
    node

  -> parse_primary
    # Parenthesized expression
    if at_type?(T_LPAREN)
      advance()
      skip_newlines()
      expr = parse_expression()
      skip_newlines()
      expect_type(T_RPAREN)
      return expr

    # &(args) — invoke the implicit block
    if at_type?(T_BLOCK_CALL)
      return parse_block_call()

    # Array literal
    if at_type?(T_LBRACKET)
      return parse_array_literal()

    # Hash literal
    if at_type?(T_LBRACE)
      return parse_hash_literal()

    # Leading-dot receiver shorthand: .name(args) means self.name(args).
    if at_type?(T_DOT)
      dot_loc = make_loc_here()
      advance()
      name_line = current_line()
      name_col = current_col()
      name = expect_method_name_value()
      result = parse_call_args_and_block(true, name_line, name_col, name)
      args = result[0]
      block = result[1]
      if args == nil
        args = []
      call = Tungsten:AST:Call.new(Tungsten:AST:Self.new, name, args, block)
      call.loc = dot_loc
      call.loc_end = make_end_loc()
      return call

    # Integer
    if at_type?(T_INT)
      raw = advance_value()
      fmt = nil
      if raw.starts_with?("0x") || raw.starts_with?("0X")
        fmt = :hex
      elsif raw.starts_with?("0b") || raw.starts_with?("0B")
        fmt = :bin
      elsif raw.starts_with?("0o") || raw.starts_with?("0O")
        fmt = :oct
      return Tungsten:AST:Int.new(parse_int_value(raw), fmt, raw)

    # Raw WValue literal: u0x followed by exactly 16 hex digits
    if at_type?(T_WVALUE)
      raw = advance_value()
      return Tungsten:AST:Wvalue.new(parse_wvalue_value(raw), raw)

    # Float (~3.14)
    if at_type?(T_FLOAT)
      return Tungsten:AST:Float.new(advance_value())

    # Decimal (3.14)
    if at_type?(T_DECIMAL)
      return Tungsten:AST:Decimal.new(advance_value())

    # Currency literal ($5.25)
    if at_type?(T_CURRENCY)
      val = advance_value()
      return Tungsten:AST:Currency.new(val[0], val[1], val[2])

    # Quantity literal (3kg, 7.65%)
    if at_type?(T_QUANTITY)
      lit_loc = make_loc_here()
      val = advance_value()
      expr = Tungsten:AST:Quantity.new(val[0], val[1])
      expr.loc = lit_loc
      expr.loc_end = make_end_loc()
      return expr

    # Duration literal (2h30m, 500ms)
    if at_type?(T_DURATION)
      lit_loc = make_loc_here()
      expr = Tungsten:AST:Duration.new(advance_value())
      expr.loc = lit_loc
      expr.loc_end = make_end_loc()
      return expr

    # UUID literal
    if at_type?(T_UUID)
      return Tungsten:AST:Uuid.new(advance_value())

    # Date literal (2026-04-08)
    if at_type?(T_DATE)
      lit_loc = make_loc_here()
      expr = Tungsten:AST:Date.new(advance_value())
      expr.loc = lit_loc
      expr.loc_end = make_end_loc()
      return expr

    # DateTime literal (2026-04-08T14:30:00Z)
    if at_type?(T_DATETIME)
      lit_loc = make_loc_here()
      expr = Tungsten:AST:Datetime.new(advance_value())
      expr.loc = lit_loc
      expr.loc_end = make_end_loc()
      return expr

    # Time literal (14:30:00)
    if at_type?(T_TIME)
      lit_loc = make_loc_here()
      expr = Tungsten:AST:Time.new(advance_value())
      expr.loc = lit_loc
      expr.loc_end = make_end_loc()
      return expr

    # Month literal (2026-04)
    if at_type?(T_MONTH)
      return Tungsten:AST:Month.new(advance_value())

    # IPv4 literal (192.168.1.1)
    if at_type?(T_IP4)
      return Tungsten:AST:Ip4.new(advance_value())

    # CIDR4 literal (10.0.0.0/8)
    if at_type?(T_CIDR4)
      return Tungsten:AST:Cidr4.new(advance_value())

    # IPv6 literal (::1, 2001:db8::1)
    if at_type?(T_IP6)
      return Tungsten:AST:Ip6.new(advance_value())

    # CIDR6 literal (2001:db8::/32)
    if at_type?(T_CIDR6)
      return Tungsten:AST:Cidr6.new(advance_value())

    # Rational literal (3/4)
    if at_type?(T_RATIONAL)
      return Tungsten:AST:Rational.new(advance_value())

    # Char literal `:-X` — raw ASCII integer (0-127). Lowers to a
    # compile-time int constant, so comparisons against extracted
    # codepoints work without char/int coercion.
    if at_type?(T_CHAR)
      return Tungsten:AST:Char.new(advance_value())

    # Codepoint literal `U+XXXX` — boxed Unicode codepoint. Lowers to
    # the const_char IR op which calls w_box_char to produce a wvalue
    # with the 0xFFFC codepoint tag. Use for full Unicode range and
    # when you need a first-class codepoint value (not just its int).
    if at_type?(T_CODEPOINT)
      return Tungsten:AST:Codepoint.new(advance_value())

    # Key literal (#[Enter])
    if at_type?(T_KEY)
      return Tungsten:AST:Key.new(advance_value())

    # Word array (%w[foo bar baz])
    if at_type?(T_WORD_ARRAY)
      return Tungsten:AST:WordArray.new(advance_value())

    # Symbol array (%i[one two three])
    if at_type?(T_SYMBOL_ARRAY)
      return Tungsten:AST:SymbolArray.new(advance_value())
    # Hypercomplex literal: %h4-f32[1 2 3 4] -> Quaternion<f32>.new([1, 2, 3, 4]).
    # Desugars to a generic constructor call, reusing the whole construction path.
    if at_type?(T_HYPER_ARRAY)
      return build_hyper_literal(advance_value())

    # MAP operator (/method_name) — consume the following identifier
    if at_type?(T_MAP)
      advance()
      return Tungsten:AST:MapOp.new(advance_value())

    # Positional argument (@1, @2)
    if at_type?(T_PARG)
      return Tungsten:AST:Parg.new(advance_value().to_i())

    # Regex capture ($1, $2)
    if at_type?(T_REGEX_CAPTURE)
      return Tungsten:AST:RegexCapture.new(advance_value().to_i())

    # Lambda arity (->/2, ->/* , ->/&)
    if at_type?(T_LAMBDA_ARITY)
      return Tungsten:AST:LambdaArity.new(advance_value())

    # Superscript (²³⁴)
    if at_type?(T_SUPERSCRIPT)
      return Tungsten:AST:Superscript.new(advance_value())

    # Base-encoded literals (0b32-..., 0b58-..., 0b64-...)
    if at_type?(T_BASE32)
      return Tungsten:AST:Encoded.new(advance_value(), "32")

    if at_type?(T_BASE58)
      return Tungsten:AST:Encoded.new(advance_value(), "58")

    if at_type?(T_BASE64)
      return Tungsten:AST:Encoded.new(advance_value(), "64")

    # Color literal (#FF6B35)
    if at_type?(T_COLOR)
      val = advance_value()
      return Tungsten:AST:Color.new(val[0], val[1], val[2], val[3])

    # Global variable
    if at_type?(T_GLOBAL)
      return Tungsten:AST:GVar.new(advance_value())

    # Regex
    if at_type?(T_REGEX)
      val = advance_value()
      return Tungsten:AST:Regex.new(val[0], val[1])

    # String
    if at_type?(T_STRING)
      return Tungsten:AST:String.new(advance_value())

    # String interpolation
    if at_type?(T_STRING_INTERP)
      return parse_string_interp()

    # Byte array
    if at_type?(T_BYTE_ARRAY)
      return Tungsten:AST:ByteArray.new(advance_value())

    # Byte array interpolation
    if at_type?(T_BYTE_ARRAY_INTERP)
      parts = advance_value().map -> (part)
        if part[0] == :bytes
          Tungsten:AST:ByteArray.new(part[1])
        else
          parse_string_from(part[1])
      return Tungsten:AST:ByteArrayInterp.new(parts)

    # Symbol
    if at_type?(T_SYMBOL)
      return Tungsten:AST:Symbol.new(advance_value())

    # true
    if at_kw?("true")
      advance()
      return Tungsten:AST:Bool.new(true)

    # false
    if at_kw?("false")
      advance()
      return Tungsten:AST:Bool.new(false)

    # nil
    if at_kw?("nil")
      advance()
      return Tungsten:AST:Nil.new

    # self
    if at_kw?("self")
      advance()
      return Tungsten:AST:Self.new

    # super
    if at_kw?("super")
      advance()
      args = []
      if at_type?(T_LPAREN)
        advance()
        args = parse_arg_list(:RPAREN)
        expect_type(T_RPAREN)
      return Tungsten:AST:Super.new(args)

    # << puts — one or more comma-separated values, each printed on its own
    # line (`<< t1, t2, t3`). Always a list, length 1 for `<< x`.
    if at_type?(T_PUTS_OP)
      advance()
      # Parse each printed value without consuming suffix modifiers. In
      # `<< i /= 2 while i > 0`, the `while` applies to the whole print
      # statement, not to the RHS of the compound assignment.
      values = [parse_assignment()]
      while at_type?(T_COMMA)
        advance()
        values.push(parse_assignment())
      return Tungsten:AST:Puts.new(values)

    # <- print
    if at_type?(T_PRINT_OP)
      advance()
      value = parse_assignment()
      return Tungsten:AST:Print.new(value)

    # Class variable
    if at_type?(T_CVAR)
      return Tungsten:AST:Cvar.new(advance_value())

    # <! raise shorthand
    if at_type?(T_RAISE_OP)
      advance()
      value = parse_assignment()
      return Tungsten:AST:Raise.new(value)

    # Instance variable
    if at_type?(T_IVAR)
      return Tungsten:AST:Ivar.new(advance_value())

    # Class name or constant (may be constructor call or namespace path).
    # T_NAME (PascalCase: Integer, Hash) — would emit ClassRef once the
    # compiled-parser divergence is fixed.
    # T_CONSTANT (SCREAMING_SNAKE: SC_2, KIND_VAR) — assignable Var.
    if at_name_or_constant?()
      is_class_ref = at_type?(T_NAME)
      name_line = current_line()
      name_col = current_col()
      name_loc = make_loc_here()
      name = advance_value()
      # Handle namespace paths: Name:Sub:Sub (tokenized as NAME SYMBOL*)
      while at_type?(T_SYMBOL)
        name = name + ":" + advance_value()
      # Generic instantiation: `Foo<T>.method(args)` or `Foo<T, U>.new(...)`.
      # Only valid on PascalCase names (class refs). Same lookahead as
      # parse_class_def — only commits when shape is `<` IDENT (`>`|`,`).
      inst_type_args = nil
      if is_class_ref
        inst_type_args = parse_type_args_if_present()
      # Handle constructor calls: Name(args) or Name { block }
      result = parse_call_args_and_block(false, name_line, name_col, name)
      args = result[0]
      block = result[1]
      if args != nil || block != nil
        if args == nil
          args = []
        args = math_fn_rewrite(name, args)
        call_node = Tungsten:AST:Call.new(nil, name, args, block)
        call_node.loc = name_loc
        call_node.loc_end = make_end_loc()
        if inst_type_args != nil
          call_node.type_args = inst_type_args
        return call_node
      if is_class_ref
        result = Tungsten:AST:ClassRef.new(name)
        if inst_type_args != nil
          result.type_args = inst_type_args
        return result
      return Tungsten:AST:Var.new(name)

    # Keywords
    if at_type?(T_KEYWORD)
      return parse_keyword()

    # Arrow -> lambda (no name) or method definition
    if at_type?(T_ARROW)
      if peek_type() == T_LPAREN
        return parse_lambda()
      return parse_method_def()

    # Magic constants
    if at_type?(T_MAGIC_FILE)
      loc = make_loc_here()
      advance()
      return Tungsten:AST:MagicConstant.new("FILE", loc, make_end_loc())
    if at_type?(T_MAGIC_LINE)
      loc = make_loc_here()
      advance()
      return Tungsten:AST:MagicConstant.new("LINE", loc, make_end_loc())
    if at_type?(T_MAGIC_DIR)
      loc = make_loc_here()
      advance()
      return Tungsten:AST:MagicConstant.new("DIR", loc, make_end_loc())

    # Typed array: i128[1000]
    if at_type?(T_TYPE) && peek_type() == T_LBRACKET
      type_name = advance_value()
      expect_type(T_LBRACKET)
      size = parse_expression()
      expect_type(T_RBRACKET)
      return Tungsten:AST:TypedArray.new(type_name, size)

    # Bare type name (for future use)
    if at_type?(T_TYPE)
      return Tungsten:AST:Var.new(advance_value())

    # Identifier (variable or call)
    if at_type?(T_ID)
      return parse_var_or_call()

    raise compile_error_at(:E_PARSE_UNEXPECTED_TOKEN, "Unexpected token [current_desc()] @pos=[@pos]/[@token_count]")

  # -- Specific construct parsers --

  -> parse_keyword
    val = current_value()
    if val == "if"
      return parse_if()
    if val == "unless"
      return parse_unless()
    if val == "while"
      return parse_while()
    if val == "until"
      return parse_until()
    if val == "loop"
      return parse_loop()
    if val == "case"
      return parse_case()
    if val == "when"
      return parse_when()
    if val == "return"
      return parse_return()
    if val == "break"
      advance()
      return Tungsten:AST:Break.new
    if val == "next"
      advance()
      return Tungsten:AST:Next.new
    if val == "recase"
      return parse_recase()
    if val == "raise"
      return parse_raise()
    if val == "exit"
      return parse_exit()
    if val == "use"
      return parse_use()
    if val == "begin"
      return parse_begin()
    if val == "yield"
      return parse_yield()
    if val == "with"
      # Class/trait body constraint clause: `with T in (type1 type2 …)`.
      # Only fires inside a class body where the shape clearly matches —
      # peek(1) is an identifier, peek(2) is the `in` keyword, peek(3) is `(`.
      # Falls through to with_loop_start? otherwise.
      if @pending_class_constraints != nil
        t1 = peek_type(1)
        if t1 == T_NAME || t1 == T_ID || t1 == T_CONSTANT || t1 == T_TYPE
          if peek_type(2) == T_KEYWORD && peek_value(2) == "in" && peek_type(3) == T_LPAREN
            return parse_with_constraint()
      if with_loop_start?()
        return parse_with()
      return Tungsten:AST:Var.new(advance_value())
    if val == "fn"
      return parse_fn_def()
    if val == "parallel"
      return parse_parallel_with()
    if val == "extern"
      return parse_extern_lib()
    if val == "go"
      return parse_go()
    if val == "in"
      return parse_in()
    if val == "is"
      return parse_trait_include()
    if val == "on"
      return parse_on_guard()
    if val == "module"
      return parse_module()
    if val == "trait"
      return parse_trait_def()
    raise compile_error_at(:E_PARSE_UNEXPECTED_KEYWORD, "Unexpected keyword '[val]'")

  -> parse_if
    expect_kw("if")
    condition = parse_expression()

    # Inline: if cond then expr [else expr]
    if at_kw?("then")
      advance()
      then_expr = parse_expression()
      else_body = nil
      if at_kw?("else")
        advance()
        else_body = [parse_expression()]
      return Tungsten:AST:If.new(condition, [then_expr], [], else_body)

    skip_newlines()
    then_body = parse_body()

    elsif_clauses = []
    while at_kw?("elsif")
      advance()
      elsif_cond = parse_expression()
      skip_newlines()
      elsif_body = parse_body()
      elsif_clauses.push([elsif_cond, elsif_body])

    else_body = nil
    if at_kw?("else")
      advance()
      skip_newlines()
      else_body = parse_body()

    Tungsten:AST:If.new(condition, then_body, elsif_clauses, else_body)

  -> parse_unless
    expect_kw("unless")
    condition = parse_expression()
    skip_newlines()
    then_body = parse_body()

    else_body = nil
    if at_kw?("else")
      advance()
      skip_newlines()
      else_body = parse_body()

    Tungsten:AST:If.new(Tungsten:AST:Not.new(condition), then_body, [], else_body)

  -> parse_while
    expect_kw("while")
    condition = parse_expression()
    skip_newlines()
    body = parse_body()
    Tungsten:AST:While.new(condition, body)

  -> parse_until
    expect_kw("until")
    condition = parse_expression()
    skip_newlines()
    body = parse_body()
    Tungsten:AST:While.new(Tungsten:AST:Not.new(condition), body)

  -> parse_loop
    expect_kw("loop")
    skip_newlines()
    body = parse_body()
    Tungsten:AST:While.new(Tungsten:AST:Bool.new(true), body)

  -> parse_case
    expect_kw("case")

    # Condition-only case: case\n  when ...\n
    if at_type?(T_NEWLINE) || at_type?(T_EOF) || at_type?(T_SEMICOLON)
      skip_newlines()
      if at_kw?("when")
        clauses = parse_when_clauses()
        whens = clauses[0]
        else_body = clauses[1]
        return Tungsten:AST:Case.new(whens, else_body)
      return parse_case_arrow_conditions()

    # Value-dispatch case: case subject\n  when ... or pattern => body
    subject = parse_expression()
    skip_newlines()

    # If when clauses follow, desugar: when "a" → when subject == "a"
    if at_kw?("when")
      clauses = parse_when_clauses()
      return Tungsten:AST:CaseValue.new(subject, when_clauses_to_case_arms(clauses[0]), clauses[1])

    if at_type?(T_INDENT)
      advance()

      # when clauses inside indented block
      if at_kw?("when")
        clauses = parse_when_clauses()
        if at_type?(T_DEDENT)
          advance()
        return Tungsten:AST:CaseValue.new(subject, when_clauses_to_case_arms(clauses[0]), clauses[1])

      result = parse_case_arrow_value_arms(subject, true)
      return result

    parse_case_arrow_value_arms(subject, false)

  -> case_arrow_stop?
    at_type?(T_DEDENT) || at_type?(T_EOF) || at_type?(T_RPAREN) || at_type?(T_RBRACKET) || at_type?(T_RBRACE) || at_type?(T_COMMA)

  -> parse_case_arrow_body
    if at_type?(T_NEWLINE) || at_type?(T_EOF)
      skip_newlines()
      return parse_body()
    body = [parse_expression()]
    while at_type?(T_SEMICOLON)
      advance()
      if at_type?(T_NEWLINE) || at_type?(T_EOF) || case_arrow_stop?()
        break
      body.push(parse_expression())
    skip_newlines()
    body

  -> parse_case_arrow_conditions
    whens = []
    else_body = nil
    indented = false
    if at_type?(T_INDENT)
      advance()
      indented = true

    while !case_arrow_stop?()
      skip_newlines()
      if case_arrow_stop?()
        break
      if at_type?(T_FAT_ARROW)
        advance()
        else_body = parse_case_arrow_body()
        break
      conditions = [parse_expression()]
      while at_type?(T_COMMA)
        advance()
        conditions.push(parse_expression())
      expect_type(T_FAT_ARROW)
      body = parse_case_arrow_body()
      whens.push(Tungsten:AST:When.new(conditions, body))

    if indented && at_type?(T_DEDENT)
      advance()
    Tungsten:AST:Case.new(whens, else_body)

  -> parse_case_arrow_value_arms(subject, already_indented = false)
    arms = []
    else_body = nil

    while !case_arrow_stop?()
      skip_newlines()
      if case_arrow_stop?()
        break

      # Catch-all: => body (no pattern)
      if at_type?(T_FAT_ARROW)
        advance()
        else_body = parse_case_arrow_body()
        break

      # Pattern (possibly with guard: expr if condition)
      patterns = [parse_expression()]
      while at_type?(T_COMMA)
        advance()
        patterns.push(parse_expression())
      guard = nil
      if at_kw?("if")
        advance()
        guard = parse_expression()

      expect_type(T_FAT_ARROW)
      body = parse_case_arrow_body()
      pi = 0
      while pi < patterns.size()
        arms.push(Tungsten:AST:CaseArm.new(patterns[pi], guard, body))
        pi += 1

    if already_indented && at_type?(T_DEDENT)
      advance()

    Tungsten:AST:CaseValue.new(subject, arms, else_body)

  -> parse_when
    clauses = parse_when_clauses()
    whens = clauses[0]
    else_body = clauses[1]
    Tungsten:AST:Case.new(whens, else_body)

  -> parse_when_clauses
    whens = []
    skip_statement_end()
    while at_kw?("when")
      advance()
      conditions = [parse_expression()]
      while at_type?(T_COMMA)
        advance()
        conditions.push(parse_expression())
      body = parse_when_clause_body()
      whens.push(Tungsten:AST:When.new(conditions, body))
      skip_statement_end()
    else_body = nil
    if at_kw?("else")
      advance()
      else_body = parse_when_clause_body()
    [whens, else_body]

  -> parse_when_clause_body
    if at_kw?("then")
      advance()
      return [parse_expression()]
    if at_type?(T_NEWLINE) || at_type?(T_SEMICOLON)
      skip_newlines()
      return parse_body()
    [parse_expression()]

  -> when_clauses_to_case_arms(whens)
    arms = []
    wi = 0
    while wi < whens.size()
      w = whens[wi]
      conditions = w.conditions
      body = w.body
      ci = 0
      while ci < conditions.size()
        arms.push(Tungsten:AST:CaseArm.new(conditions[ci], nil, body))
        ci += 1
      wi += 1
    arms

  # Rewrite case-value when clauses: when "a", "b" → when subject == "a" || subject == "b"
  -> desugar_case_whens(subject, whens)
    result = []
    i = 0
    while i < whens.size()
      w = whens[i]
      conditions = w.conditions
      body = w.body
      # Build subject == c1 || subject == c2 || ...
      new_conditions = []
      j = 0
      while j < conditions.size()
        new_conditions.push(Tungsten:AST:BinaryOp.new(subject, :EQ, conditions[j]))
        j += 1
      result.push(Tungsten:AST:When.new(new_conditions, body))
      i += 1
    result

  -> parse_return
    advance()
    if at_type?(T_NEWLINE) || at_type?(T_EOF) || at_type?(T_DEDENT) || at_type?(T_SEMICOLON)
      return Tungsten:AST:ReturnNil.new
    Tungsten:AST:Return.new(parse_assignment())

  # `recase` / `recase expr` — re-run the enclosing case. Bare form (nil value)
  # re-evaluates the original subject; the expr form dispatches on expr. Same
  # optional-operand shape as `return`.
  -> parse_recase
    advance()
    if at_type?(T_NEWLINE) || at_type?(T_EOF) || at_type?(T_DEDENT) || at_type?(T_SEMICOLON)
      return Tungsten:AST:Recase.new(nil)
    Tungsten:AST:Recase.new(parse_assignment())

  -> parse_raise
    raise_loc = make_loc_here()
    advance()
    # Parse the operand(s) at the assignment level, NOT parse_expression:
    # parse_expression applies the suffix `if`/`unless`/`while` modifier, so
    # `raise "msg" if cond` would bind the modifier to the *argument*
    # (`"msg" if cond` → nil when false → `raise nil`) instead of the whole
    # statement. Stopping below the modifier lets the caller attach it to the
    # raise itself, matching `y = 0 if cond`.
    val = parse_assignment()
    # Ruby-style two-arg form: `raise ExceptionClass, "message"`.
    # Construct the exception with the message — `ExceptionClass.new(msg)`
    # — so the single-value Raise node carries a fully-built instance.
    if at_type?(T_COMMA)
      advance()
      msg = parse_assignment()
      val = Tungsten:AST:Call.new(val, "new", [msg])
    node = Tungsten:AST:Raise.new(val)
    node.loc = raise_loc
    node.loc_end = make_end_loc()
    node

  -> parse_exit
    advance()
    if at_type?(T_NEWLINE) || at_type?(T_EOF) || at_type?(T_DEDENT) || at_type?(T_SEMICOLON)
      return Tungsten:AST:Call.new(nil, "exit", [Tungsten:AST:Int.new(0)])
    Tungsten:AST:Call.new(nil, "exit", [parse_expression()])

  -> parse_use
    advance()
    # The lexer scans the use path as a STRING token (bare or quoted)
    Tungsten:AST:Use.new(advance_value())

  -> parse_begin
    expect_kw("begin")
    skip_newlines()
    body = parse_body()

    rescue_var = nil
    rescue_body = nil
    if at_kw?("rescue")
      advance()
      rescue_var = nil
      if !at_type?(T_NEWLINE) && !at_type?(T_INDENT) && !at_type?(T_DEDENT) && !at_type?(T_EOF)
        rescue_var = expect_type_value(T_ID)
        if at_type?(T_COLON)
          advance()
          expect_name_or_constant()
      skip_newlines()
      rescue_body = parse_body()

    ensure_body = nil
    if at_kw?("ensure")
      advance()
      skip_newlines()
      ensure_body = parse_body()

    Tungsten:AST:Begin.new(body, rescue_var, rescue_body, ensure_body)

  -> parse_yield
    advance()
    args = []
    if !at_type?(T_NEWLINE) && !at_type?(T_EOF) && !at_type?(T_DEDENT) && !at_type?(T_SEMICOLON)
      if at_type?(T_LPAREN)
        advance()
        args = parse_arg_list(:RPAREN)
        expect_type(T_RPAREN)
      else
        args = parse_bare_args()
    Tungsten:AST:Yield.new(args)

  # &(args) — invoke the implicit block, desugars to yield
  -> parse_block_call
    advance()  # consume &(
    args = []
    skip_newlines()
    if !at_type?(T_RPAREN)
      args.push(parse_expression())
      while at_type?(T_COMMA)
        advance()
        skip_newlines()
        args.push(parse_expression())
    expect_type(T_RPAREN)
    Tungsten:AST:Yield.new(args)

  -> parse_with
    expect_kw("with")
    bindings = []

    cont = true
    while cont
      var = Tungsten:AST:Var.new(expect_type_value(T_ID))
      expect_kw("in")
      collection = parse_message_chain()
      bindings.push([var, collection])
      if at_type?(T_COMMA)
        advance()
      else
        cont = false

    skip_newlines()
    body = parse_body()
    Tungsten:AST:With.new(bindings, body)

  -> parse_parallel_with
    expect_kw("parallel")
    expect_kw("with")
    var = Tungsten:AST:Var.new(expect_type_value(T_ID))
    expect_kw("in")
    collection = parse_message_chain()
    if at_type?(T_COMMA)
      raise compile_error_at(:E_PARSE_PARALLEL_WITH_SINGLE_BINDING, "parallel with supports only a single binding")
    skip_newlines()
    body = parse_body()
    Tungsten:AST:ParallelWith.new([[var, collection]], body)

  # extern lib "name" ->
  #   fn_name(Type, Type) -> ReturnType
  #   fn_name(Type) -> Void
  -> parse_extern_lib
    expect_kw("extern")
    expect_typed(T_ID, "lib")
    lib_name = expect_type_value(T_STRING)
    expect_type(T_ARROW)
    skip_newlines()
    declarations = []
    while !at_type?(T_DEDENT) && !at_type?(T_EOF)
      fn_name = expect_type_value(T_ID)
      expect_type(T_LPAREN)
      param_types = []
      unless at_type?(T_RPAREN)
        param_types.push(expect_type_value(T_ID))
        while at_type?(T_COMMA)
          advance()
          param_types.push(expect_type_value(T_ID))
      expect_type(T_RPAREN)
      expect_type(T_ARROW)
      return_type = expect_type_value(T_ID)
      declarations.push(Tungsten:AST:ExternFn.new(fn_name, return_type, param_types))
      skip_newlines()
    if at_type?(T_DEDENT)
      advance()
    Tungsten:AST:ExternLib.new(lib_name, declarations)

  # go -> body
  -> parse_go
    expect_kw("go")
    expect_type(T_ARROW)
    skip_newlines()
    body = nil
    if at_type?(T_INDENT)
      body = parse_body()
    else
      body = [parse_expression()]
    Tungsten:AST:Go.new(body)

  # in Tungsten:Forge:H2 — namespace declaration (skip for now)
  -> parse_in
    expect_kw("in")
    expect_name_or_constant()
    while at_type?(T_COLON)
      advance()
      expect_name_or_constant()
    Tungsten:AST:Nil.new

  -> consume_type_hints
    hints = @pending_type_hints
    @pending_type_hints = []
    if hints.empty?()
      return nil
    # Parse hint lines: "i32 x, y" or "i32: x, y" → {x: :i32, y: :i32}
    result = {}
    hints.each -> (hint)
      # Support both "i32 x, y" and "i32: x, y"
      colon_pos = hint.index(":")
      if colon_pos != nil && colon_pos > 0
        type_name = hint.slice(0, colon_pos).strip()
        rest = hint.slice(colon_pos + 1, hint.size() - colon_pos - 1).strip()
      else
        parts = hint.split(" ")
        if parts.size() >= 2
          type_name = parts[0]
          rest = hint.slice(type_name.size(), hint.size() - type_name.size()).strip()
        else
          rest = ""
          type_name = hint
      if rest.size() > 0
        names = rest.split(",")
        names.each -> (n)
          clean = n.strip()
          if clean.size() > 0
            result[clean] = type_name.to_sym()
    if result.size() == 0
      return nil
    result

  -> parse_method_def
    type_hints = consume_type_hints()
    method_off = current_offset()
    expect_type(T_ARROW)

    # Check for -> .method_name (dot-prefix class method)
    is_class_method = false
    if at_type?(T_DOT)
      advance()
      is_class_method = true
    elsif at_kw?("self")
      raise compile_error_at(:E_PARSE_SELF_METHOD_DEF, "use '-> .method_name' for class methods (not '-> self.method_name')")

    # Capture the name-token type BEFORE expect_method_name_value()
    # advances — the identifier-vs-operator distinction below depends
    # on it for arity suffix handling.
    name_tok_type = tok_type(@current_packed)
    name = expect_method_name_value()
    # Setter methods: name= (e.g. cache_dir=)
    if at_type?(T_ASSIGN)
      advance()
      name = name + "="

    # Method-name arity (`/N`, `/*`, `/&`). Two shapes reach here:
    #   * identifier names — the lexer bundles the suffix into the name
    #     token (`divmod/1`). An identifier cannot contain `/`, so the
    #     first `/` is unambiguously the suffix separator.
    #   * operator names (`<=>`, `==`, `/`, …) — the operator scanner
    #     stops at the operator, so any suffix arrives as its own tokens.
    # Splitting only the identifier token, and reading operator arity
    # straight from the token stream, means a method literally named `/`
    # or `//` is never mistaken for a name carrying an arity suffix.
    arity = nil
    base_name = name
    if name_tok_type in (T_ID T_TYPE T_KEYWORD)
      if name.include?("/")
        parts = name.split("/")
        base_name = parts[0]
        suffix = parts[1]
        if suffix == "&"
          arity = :block
        elsif suffix == "*"
          arity = :splat
        else
          arity = suffix.to_i()
    elsif at_type?(T_SLASH)
      advance()
      if at_type?(T_STAR)
        advance()
        arity = :splat
      elsif at_type?(T_AMPERSAND)
        advance()
        arity = :block
      else
        arity = advance_value().to_i()

    params = []

    if arity == :block
      params.push(Tungsten:AST:Param.new("&", nil, false, false, true, false))
    elsif arity != nil && arity != :splat
      i = 1
      while i <= arity
        params.push(Tungsten:AST:Param.new("__arg" + i.to_s(), nil, false, false, false, false))
        i += 1
    elsif at_type?(T_LPAREN)
      advance()
      while !at_type?(T_RPAREN)
        params.push(parse_method_param())
        match_type?(T_COMMA)
      expect_type(T_RPAREN)

    skip_spaces()

    # Phase 3: optional param-type list `(i64 i64)`. Disambiguated by
    # peeking inside the paren group — if the contents are all `:TYPE`
    # tokens followed by `)`, it's a param-type annotation. Otherwise
    # fall through to the trailing-expression path (which handles
    # things like `(a + b)` as a trailing expression).
    param_types = nil
    if at_type?(T_LPAREN) && looks_like_param_types?()
      advance()
      param_types = []
      while !at_type?(T_RPAREN)
        if !is_param_type_token?(tok_type(@current_packed))
          raise compile_error_at(:E_PARSE_BAD_PARAM_TYPE, "Expected type name in param type list, got [current_desc()]")
        type_name = advance_value()
        # Optional `[]` suffix for typed-array params (e.g. `i64[]`).
        # Stored as the symbol `:"i64[]"` so the lowering's existing
        # `## i64[]: name` normalization picks it up without change.
        if at_type?(T_LBRACKET) && peek_type() == T_RBRACKET
          advance()
          advance()
          type_name = type_name + "\[]"
        param_types.push(type_name.to_sym())
      expect_type(T_RPAREN)
      skip_spaces()

    # Phase 3: optional return type — a bare `:TYPE` token followed by
    # `:` (inline body introducer) or a newline/indent (multi-line body)
    # or the end of the header.
    return_type = nil
    if at_type?(T_TYPE) && looks_like_return_type?()
      return_type = advance_value().to_sym()
      skip_spaces()

    annotations_present = param_types != nil || return_type != nil

    # Phase 3: `:` is the inline-body introducer in both typed and
    # untyped forms. The untyped form additionally keeps the old
    # bare-trailing-expression path for back-compat so `-> add(a,b) a+b`
    # still parses as today.
    trailing_expr = nil
    if at_type?(T_ASSIGN)
      advance()
      trailing_expr = parse_expression()
    elsif at_type?(T_COLON)
      advance()
      trailing_expr = parse_expression()
    elsif !annotations_present
      # Untyped back-compat: bare trailing expression becomes accumulator
      # init or inline body, same as before Phase 3.
      if !at_type?(T_NEWLINE) && !at_type?(T_DEDENT) && !at_type?(T_EOF) && !at_type?(T_SEMICOLON)
        trailing_expr = parse_expression()

    skip_newlines()
    body = nil

    if trailing_expr != nil
      if at_type?(T_INDENT)
        # Trailing expr + indented body = accumulator.
        #
        # Shape rewrite: the trailing expression becomes an accumulator
        # seed `acc = trailing`, the indented body runs after the seed,
        # and the final expression is `acc` so the method returns the
        # accumulator. Accumulator name is detected from body contents
        # (first use of `out` / `acc`) or defaults to `out`.
        #
        # Array construction: use push-in-order instead of `[init] + body
        # + [ret]`. The `+` spelling crashed at parse time because
        # Tungsten arrays don't support `+` concatenation — the old
        # code was dead (nothing in the compiler used method accumulator
        # form) so the crash was latent. Switching to push works today.
        parsed_body = parse_body()
        init_expr = trailing_expr
        acc_name = nil
        if ast_kind(trailing_expr) == :assign && ast_kind(trailing_expr.target) == :var
          acc_name = trailing_expr.target.name
          init_expr = trailing_expr.value
        else
          acc_name = detect_accumulator_name(parsed_body)
          if acc_name == nil
            acc_name = "out"
        init = Tungsten:AST:Assign.new(Tungsten:AST:Var.new(acc_name), init_expr)
        ret = Tungsten:AST:Var.new(acc_name)
        body = []
        body.push(init)
        pbi = 0
        while pbi < parsed_body.size()
          body.push(parsed_body[pbi])
          pbi += 1
        body.push(ret)
      else
        # Trailing expr, no indented body = inline body
        body = [trailing_expr]
    elsif at_type?(T_INDENT)
      body = parse_body()
    elsif at_type?(T_DEDENT) || at_type?(T_EOF) || at_type?(T_CLASS_DEF) || at_type?(T_ARROW)
      body = []
    else
      body = [parse_expression()]

    # Fallthrough: `: expr` after body — default return value
    if at_type?(T_COLON)
      advance()
      fallthrough = parse_expression()
      body.push(fallthrough)

    result = Tungsten:AST:MethodDef.new(base_name, params, body, type_hints, is_class_method)
    result.loc = make_loc_offset(method_off)
    result.loc_end = make_end_loc()
    if param_types != nil
      result.param_types = param_types
    if return_type != nil
      result.return_type = return_type
    result

  # Phase 3 lookahead: is the current LPAREN the start of a param-type
  # annotation `(type type type)`? True iff inside the paren we see one
  # or more `:TYPE` tokens followed by `)`. Distinguishes param types
  # from a trailing expression like `(a + b)` or `(i64[5])`.
  # A param-type-list element is a builtin type (`i64`, T_TYPE) OR a class
  # name (`Vector`, `Vec3` — T_NAME/T_CONSTANT). Without the class-name forms,
  # `-> */1(Vec3)` never parsed as a typed overload (the `(Vec3)` fell through
  # to a trailing expression and param_types stayed nil).
  -> is_param_type_token?(t)
    t == T_TYPE || t == T_NAME || t == T_CONSTANT

  -> looks_like_param_types?
    if !at_type?(T_LPAREN)
      return false
    # First token inside must be a param-type token.
    if !is_param_type_token?(peek_type(1))
      return false
    # Walk forward: param-type tokens or RPAREN only. Reject if we see
    # LBRACKET (that's typed-array construction like `i64[5]`), COMMA, or
    # any other token. The bound is just a safety cap: the walk already
    # returns false on the first non-type token, so a real expression can
    # never reach it; only a genuine (very long) param-type list does.
    # 32 was too small — an 18-param typed signature has ~32 type-list
    # tokens (each `i64[]`/`w64[]` is 3) and would bail here, then get
    # mis-parsed as a trailing expression. 256 supports ~80 params.
    off = 1
    while off < 256
      t = peek_type(off)
      if t == T_RPAREN
        return true
      if !is_param_type_token?(t)
        return false
      off += 1
      # Accept optional `[]` suffix for typed-array param types.
      if peek_type(off) == T_LBRACKET && peek_type(off + 1) == T_RBRACKET
        off += 2
    false

  # Phase 3 lookahead: is the current `:TYPE` token a return-type
  # annotation? True iff the token after it is `:` (inline body
  # introducer), `:NEWLINE`, or `:INDENT`. False if it's anything that
  # could start an expression like `.method` or `[index]` or `(args)`.
  -> looks_like_return_type?
    if !at_type?(T_TYPE)
      return false
    t = peek_type(1)
    t == T_COLON || t == T_NEWLINE || t == T_INDENT || t == T_DEDENT || t == T_EOF || t == T_SEMICOLON

  # Scan AST nodes for first use of "out" or "acc" as a variable name.
  -> detect_accumulator_name(nodes)
    i = 0
    while i < nodes.size()
      result = detect_acc_in_node(nodes[i])
      if result != nil
        return result
      i += 1
    nil

  -> detect_acc_in_node(node)
    if node == nil
      return nil
    if !is_ast_node?(node)
      return nil
    if ast_kind(node) == :var
      if node.name in ("out" "acc")
        return node.name
      return nil
    # Walk every AST child looking for an out/acc :var.
    children = ast_children(node)
    ci = 0
    while ci < children.size()
      result = detect_acc_in_node(children[ci])
      if result != nil
        return result
      ci += 1
    nil

  -> parse_fn_def
    type_hints = consume_type_hints()
    fn_off = current_offset()
    expect_kw("fn")
    name = expect_type_value(T_ID)
    params = []
    param_types = nil
    return_type = nil

    if at_type?(T_LPAREN)
      advance()
      while !at_type?(T_RPAREN)
        params.push(parse_method_param())
        match_type?(T_COMMA)
      expect_type(T_RPAREN)
      skip_spaces()
      # Optional `(types)` parameter-type list — same form as
      # parse_method_def so `fn foo(a, b) (i64, i64) i64` parses.
      if at_type?(T_LPAREN)
        advance()
        param_types = []
        while !at_type?(T_RPAREN)
          if at_type?(T_TYPE) || at_type?(T_ID)
            param_types.push(advance_value().to_sym())
          else
            break
          match_type?(T_COMMA)
          skip_spaces()
        expect_type(T_RPAREN)
        skip_spaces()
      if at_type?(T_TYPE) && looks_like_return_type?()
        return_type = advance_value().to_sym()
        skip_spaces()

    skip_newlines()
    body = nil
    if at_type?(T_INDENT)
      body = parse_body()
    elsif at_type?(T_DEDENT) || at_type?(T_EOF) || at_type?(T_CLASS_DEF) || at_type?(T_ARROW)
      body = []
    else
      body = [parse_expression()]

    # Inside a class body, `fn` is an alias for `->` — produce a
    # method_def so the class machinery registers it as an instance
    # method. The `from_fn: true` flag tells the lowering to also
    # register a memo table (matching top-level fn semantics).
    if @in_class_body
      result = Tungsten:AST:MethodDef.new(name, params, body, type_hints, false)
      result.from_fn = true
      result.loc = make_loc_offset(fn_off)
      result.loc_end = make_end_loc()
      if param_types != nil
        result.param_types = param_types
      if return_type != nil
        result.return_type = return_type
      return result

    # Top-level fn: produce a regular fn_def with both annotations
    # attached. Note: setting :param_types triggers typed-overload
    # name mangling in function_name_for_def. Call-site resolution
    # for typed overloads is still incomplete, so this only works
    # cleanly when there's exactly one definition for a given name
    # (the common case). For now keep param_types attached so the
    # body benefits from typed parameter unboxing inside the fn.
    result = Tungsten:AST:FnDef.new(name, params, body, type_hints)
    result.loc = make_loc_offset(fn_off)
    result.loc_end = make_end_loc()
    if param_types != nil
      result.param_types = param_types
    if return_type != nil
      result.return_type = return_type
    result

  # Parse `@gpu fn NAME(ARGS)` kernel definition. Body accepts the same
  # parse grammar as a regular fn but gets lowered via metal_emitter.w
  # rather than the normal WIRE pipeline. The restricted-subset check
  # happens at lowering time, not here.
  -> parse_gpu_kernel_def
    attr_off = current_offset()
    expect_typed(T_IVAR, "@gpu")
    type_hints = consume_type_hints()
    expect_kw("fn")
    name = expect_type_value(T_ID)
    params = []
    if at_type?(T_LPAREN)
      advance()
      while !at_type?(T_RPAREN)
        params.push(parse_method_param())
        match_type?(T_COMMA)
      expect_type(T_RPAREN)
    skip_newlines()
    body = nil
    if at_type?(T_INDENT)
      body = parse_body()
    elsif at_type?(T_DEDENT) || at_type?(T_EOF) || at_type?(T_CLASS_DEF) || at_type?(T_ARROW)
      body = []
    else
      body = [parse_expression()]
    result = Tungsten:AST:GpuKernelDef.new(name, params, body, "gpu", type_hints)
    result.loc = make_loc_offset(attr_off)
    result.loc_end = make_end_loc()
    result

  # Parse `@fastmath -> body` or `@strictmath -> body` scoped math-mode blocks.
  # The node is a plain hash (not slab-allocated) since it only lives during
  # lowering. kind is :fastmath_block or :strictmath_block.
  -> parse_mathmode_block(kind)
    advance()         # consume @fastmath or @strictmath
    advance()         # consume ->
    skip_newlines()
    body = []
    if at_type?(T_INDENT)
      body = parse_body()
    elsif !at_type?(T_NEWLINE) && !at_type?(T_EOF) && !at_type?(T_DEDENT)
      body = [parse_expression()]
    {node: kind, body: body}

  # Parse `Math.promote -> body` / `Math.trap -> body` / `Math.wrap -> body`
  # scoped integer-overflow-mode blocks. Like the math-mode blocks, the node
  # is a plain hash ({node: :overflow_block, mode:, body:}) that only lives
  # during lowering. mode_name is "promote" / "trap" / "wrap".
  -> parse_overflow_block(mode_name)
    advance()         # Math (NAME)
    advance()         # . (DOT)
    advance()         # promote / trap / wrap (ID)
    advance()         # ->
    skip_newlines()
    body = []
    if at_type?(T_INDENT)
      body = parse_body()
    elsif !at_type?(T_NEWLINE) && !at_type?(T_EOF) && !at_type?(T_DEDENT)
      body = [parse_expression()]
    {node: :overflow_block, mode: mode_name.to_sym(), body: body}

  # Parse `@schedule kernel.variant` block. Body is a sequence of
  # ordinary expressions (typically calls like `axis :m, parallelize: :threadgroup`)
  # collected as the schedule's directive list. The compiler pass that
  # actually applies a schedule reads the directives at MSL emit time;
  # the parser just records them.
  -> parse_schedule_def
    attr_off = current_offset()
    expect_typed(T_IVAR, "@schedule")
    kernel_name = expect_type_value(T_ID)
    expect_type(T_DOT)
    variant_name = expect_type_value(T_ID)
    skip_newlines()
    directives = []
    if at_type?(T_INDENT)
      directives = parse_body()
    result = Tungsten:AST:ScheduleDef.new(kernel_name, variant_name, directives)
    result.loc = make_loc_offset(attr_off)
    result.loc_end = make_end_loc()
    result

  # Parse `@layout kernel.variant` block. Mirrors parse_schedule_def but
  # holds buffer-reshape directives like
  #   buffer :w_q, from: :i8[], to: :i32[], unpack: :sign_extend_per_byte
  -> parse_layout_def
    attr_off = current_offset()
    expect_typed(T_IVAR, "@layout")
    kernel_name = expect_type_value(T_ID)
    expect_type(T_DOT)
    variant_name = expect_type_value(T_ID)
    skip_newlines()
    directives = []
    if at_type?(T_INDENT)
      directives = parse_body()
    result = Tungsten:AST:LayoutDef.new(kernel_name, variant_name, directives)
    result.loc = make_loc_offset(attr_off)
    result.loc_end = make_end_loc()
    result

  -> parse_method_param
    # &block parameter (named: &block, anonymous: &)
    if at_type?(T_AMPERSAND)
      advance()
      if identifier_name_token?()
        return Tungsten:AST:Param.new(advance_value(), nil, false, false, true, false)
      return Tungsten:AST:Param.new("&", nil, false, false, true, false)

    # *args / **kwargs splat
    if at_type?(T_POW)
      advance()
      if identifier_name_token?()
        name = advance_value()
      else
        name = expect_type_value(T_ID)
      return Tungsten:AST:Param.new(name, nil, false, false, false, true)

    if star_token?()
      advance()
      if at_type?(T_STAR)
        advance()
        if identifier_name_token?()
          name = advance_value()
        else
          name = expect_type_value(T_ID)
        return Tungsten:AST:Param.new(name, nil, false, false, false, true)
      if identifier_name_token?()
        name = advance_value()
      else
        name = expect_type_value(T_ID)
      return Tungsten:AST:Param.new(name, nil, false, false, false, true)

    ivar_assign = false
    param_name = nil

    if at_type?(T_IVAR)
      ivar = advance_value()
      param_name = ivar.slice(1, ivar.size() - 1)
      ivar_assign = true
    else
      param_name = expect_identifier_name_value()

    # Keyword param: name: or name: default
    if at_type?(T_COLON)
      advance()
      default = nil
      if !at_type?(T_COMMA) && !at_type?(T_RPAREN)
        default = parse_expression()
      return Tungsten:AST:Param.new(param_name, default, ivar_assign, true, false, false)

    default = nil
    if at_type?(T_ASSIGN)
      advance()
      default = parse_expression()

    # Inline ## type ascription on a constructor param: `(@components ## T[4])`.
    # v0 consumes the hint but does not surface it on the Param node —
    # monomorphization specializes via the class-level :type_params chain
    # and the type hint is informational for now.
    if at_type?(T_TYPE_HINT)
      advance()

    Tungsten:AST:Param.new(param_name, default, ivar_assign)

  -> parse_data_field
    pointer = false
    if at_type?(T_STAR)
      pointer = true
      advance()
      skip_spaces()

    # T_NAME / T_CONSTANT accepted so parametric data-field types like
    # `T components[4]` parse — monomorphization substitutes T at
    # specialization time.
    if !(at_type?(T_ID) || at_type?(T_TYPE) || at_type?(T_NAME) || at_type?(T_CONSTANT))
      raise compile_error_at(:E_PARSE_EXPECTED_DATA_FIELD_TYPE, "Expected data field type, got [current_desc()]")

    ftype = advance_value()
    skip_spaces()

    # Array-style bracket-after-type: `u8[2] _pad`, `u8[] slots`.
    if at_type?(T_LBRACKET)
      ftype = ftype + parse_data_field_bracket()
      skip_spaces()

    fname = expect_identifier_name_value()
    skip_spaces()

    # Quaternion/Mat-style bracket-after-name: `T components[4]`,
    # `T elements[M * N]`. The array suffix attaches to the type string
    # so monomorphization's textual type-param substitution sees it.
    if at_type?(T_LBRACKET)
      ftype = ftype + parse_data_field_bracket()
      skip_spaces()

    if pointer
      ftype = "*" + ftype

    {name: fname, type: ftype}

  # Parse a `[...]` array-size suffix in a data-field declaration,
  # returning the bracketed string (e.g. "[4]", "[]", "[M * N]").
  # Accepts a literal int, an empty pair, or an arbitrary size
  # expression collected verbatim (generic shape params like M * N).
  -> parse_data_field_bracket
    expect_type(T_LBRACKET)
    if at_type?(T_INT)
      arr_size = advance_value()
      expect_type(T_RBRACKET)
      return "\[" + arr_size.to_s() + "\]"
    if at_type?(T_RBRACKET)
      advance()
      return "\[\]"
    size_str = ""
    while !at_type?(T_RBRACKET) && !at_type?(T_EOF)
      size_str = size_str + current_value().to_s()
      advance()
      skip_spaces()
    expect_type(T_RBRACKET)
    "\[" + size_str + "\]"

  -> parse_class_def
    expect_type(T_CLASS_DEF)
    if at_type?(T_NAME) || at_type?(T_CONSTANT) || at_type?(T_ID) || at_type?(T_TYPE)
      name = advance_value()
    else
      name = expect_name_or_constant_value()
    # Namespaced class: Foo:Bar — the :Bar is tokenized as SYMBOL
    while at_type?(T_SYMBOL)
      name = name + ":" + current_value()
      advance()
    superclass = nil
    class_role = nil

    # Type parameters: `+ Name<T>` or `+ Name<T, M, N>`. Lookahead
    # disambiguates from `+ Name < Parent` (inheritance): consume `<...>`
    # only when the token shape is `<` IDENT (`>`|`,`).
    type_params = parse_type_args_if_present()

    if at_type?(T_LBRACKET)
      advance()
      if at_type?(T_NAME) || at_type?(T_CONSTANT) || at_type?(T_ID) || at_type?(T_TYPE)
        class_role = advance_value()
      else
        class_role = expect_name_or_constant_value()
      expect_type(T_RBRACKET)

    parent_type_args = nil
    if at_type?(T_LT)
      advance()
      if at_type?(T_NAME) || at_type?(T_CONSTANT) || at_type?(T_ID) || at_type?(T_TYPE)
        superclass = advance_value()
      else
        superclass = expect_name_or_constant_value()
      while at_type?(T_SYMBOL)
        superclass = superclass + ":" + current_value()
        advance()
      # Parametric parent: `< Parent<T>` or `< Parent<T, U>`.
      parent_type_args = parse_type_args_if_present()

    # Second role-marker position: `+ Name < Super [role]`. Reserves
    # `+ Name[Category]` for class type/category use. Both positions
    # parse; the bracket-attached-to-name spot loses (gets shadowed)
    # if both are supplied.
    if class_role == nil && at_type?(T_LBRACKET)
      advance()
      if at_type?(T_NAME) || at_type?(T_CONSTANT) || at_type?(T_ID) || at_type?(T_TYPE)
        class_role = advance_value()
      else
        class_role = expect_name_or_constant_value()
      expect_type(T_RBRACKET)

    skip_newlines()
    body = nil
    prev_in_class = @in_class_body
    prev_constraints = @pending_class_constraints
    @in_class_body = true
    @pending_class_constraints = []
    if at_type?(T_INDENT)
      body = parse_body()
    else
      body = []
    @in_class_body = prev_in_class
    collected_constraints = @pending_class_constraints
    @pending_class_constraints = prev_constraints

    # Apply file-level `in NAMESPACE` prefix to the class name.
    if @namespace_prefix != nil
      if !name.include?(":")
        name = @namespace_prefix + ":" + name

    # Ruby-style constant lookup for the superclass: walk the
    # namespace chain from the current `in` prefix up to the top
    # level. The first declared name wins; unmatched names pass
    # through bare so runtime builtins (StandardError, …) still
    # resolve at the top level.
    if superclass != nil && !superclass.include?(":") && @namespace_prefix != nil
      segments = @namespace_prefix.split(":")
      while segments.size() > 0
        candidate = segments.join(":") + ":" + superclass
        if @declared_classes[candidate] == true
          superclass = candidate
          break
        segments.pop()

    @declared_classes[name] = true
    result = Tungsten:AST:ClassDef.new(name, superclass, body, class_role)
    # Generic-class side channel (parser-only for v0). Sparse-meta
    # storage; monomorphization later reads these to specialize.
    if type_params != nil
      result.type_params = type_params
    if parent_type_args != nil
      result.parent_type_args = parent_type_args
    if collected_constraints != nil && collected_constraints.size() > 0
      result.type_constraints = collected_constraints
    result

  -> parse_module
    expect_kw("module")
    name = expect_name_or_constant_value()
    skip_newlines()
    body = nil
    if at_type?(T_INDENT)
      body = parse_body()
    else
      body = []
    Tungsten:AST:ModuleDef.new(name, body)

  -> parse_trait_def
    expect_kw("trait")
    if at_type?(T_NAME) || at_type?(T_CONSTANT) || at_type?(T_ID) || at_type?(T_TYPE)
      name = advance_value()
    else
      name = expect_name_or_constant_value()
    while at_type?(T_SYMBOL)
      name = name + ":" + current_value()
      advance()
    type_params = parse_type_args_if_present()
    skip_newlines()
    body = nil
    prev_in_class = @in_class_body
    prev_constraints = @pending_class_constraints
    @in_class_body = true
    @pending_class_constraints = []
    if at_type?(T_INDENT)
      body = parse_body()
    else
      body = []
    @in_class_body = prev_in_class
    collected_constraints = @pending_class_constraints
    @pending_class_constraints = prev_constraints
    result = Tungsten:AST:TraitDef.new(name, body)
    if type_params != nil
      result.type_params = type_params
    if collected_constraints != nil && collected_constraints.size() > 0
      result.type_constraints = collected_constraints
    result

  -> parse_trait_include
    expect_kw("is")
    if at_type?(T_NAME) || at_type?(T_CONSTANT) || at_type?(T_ID) || at_type?(T_TYPE)
      name = advance_value()
    else
      name = expect_name_or_constant_value()
    while at_type?(T_SYMBOL)
      name = name + ":" + current_value()
      advance()
    trait_type_args = parse_type_args_if_present()
    result = Tungsten:AST:TraitInclude.new(name)
    if trait_type_args != nil
      result.trait_type_args = trait_type_args
    result

  # Generic type-argument list parsing. Disambiguates `Name<T>` (type
  # args) from `Name < Parent` (inheritance) via one-token lookahead:
  # only consume `<...>` when we see `<` IDENT (`>`|`,`). The IDENT
  # accepts T_NAME (PascalCase like T), T_CONSTANT (SCREAMING), T_ID
  # (lowercase — handles primitive type names in `Foo<i32>`), and
  # T_TYPE (`:Int` form).
  -> parse_type_args_if_present
    if !at_type?(T_LT)
      return nil
    t1 = peek_type(1)
    if t1 != T_NAME && t1 != T_ID && t1 != T_CONSTANT && t1 != T_TYPE && t1 != T_INT
      return nil
    t2 = peek_type(2)
    if t2 != T_GT && t2 != T_COMMA && t2 != T_SLASH && t2 != T_STAR && t2 != T_DOT_PRODUCT
      return nil
    advance()
    params = []
    current = ""
    while !at_type?(T_GT) && !at_type?(T_EOF)
      if at_type?(T_COMMA)
        if current == ""
          raise compile_error_at(:E_PARSE_EXPECTED_TOKEN, "Empty generic type argument")
        params.push(current)
        current = ""
        advance()
      else
        # Preserve a type argument as compact source text. Besides ordinary
        # names/shape integers this permits unit expressions in aggregate
        # types: `Tensor<f64, m/s>`. The argument remains metadata unless the
        # referenced class is an actual generic template.
        current = current + current_value().to_s()
        advance()
    if current == ""
      raise compile_error_at(:E_PARSE_EXPECTED_TOKEN, "Empty generic type argument")
    params.push(current)
    expect_type(T_GT)
    params

  # Desugar a %h<dim>-<type>[...] literal token (payload [dim, type, comps])
  # into `<Class><scalar>.new([components])`, reusing the generic-construction
  # path. dim -> base class; a Metal vector type (float4 etc.) maps to its
  # scalar element, and at dim 4 selects the scalar-last QuaternionMetal.
  -> build_hyper_literal(payload)
    dim = payload[0].to_i()
    info = hyper_class_and_scalar(dim, payload[1])
    comps = payload[2]
    nodes = []
    ci = 0
    while ci < comps.size()
      nodes.push(hyper_component_node(comps[ci]))
      ci += 1
    cr = Tungsten:AST:ClassRef.new(info[0])
    cr.type_args = [info[1]]
    Tungsten:AST:Call.new(cr, "new", [Tungsten:AST:Array.new(nodes)], nil)

  -> hyper_class_and_scalar(dim, type)
    base = "Complex"
    if dim == 4
      base = "Quaternion"
    elsif dim == 8
      base = "Octonion"
    elsif dim == 16
      base = "Sedenion"
    elsif dim == 32
      base = "Trigintaduonion"
    elsif dim == 64
      base = "Sexagintaquatronion"
    elsif dim == 128
      base = "Centumduodetrigintanion"
    elsif dim == 256
      base = "Ducentiquinquagintasexion"
    scalar = type
    if type.starts_with?("float") || type.starts_with?("half") || type.starts_with?("bfloat")
      scalar = "f32"
      if type.starts_with?("half")
        scalar = "f16"
      elsif type.starts_with?("bfloat")
        scalar = "bf16"
      if dim == 4
        base = "QuaternionMetal"
    [base, scalar]

  -> hyper_component_node(s)
    if s.include?(".")
      return Tungsten:AST:Decimal.new(s)
    if s.to_i().to_s() == s
      return Tungsten:AST:Int.new(parse_int_value(s), nil, s)
    Tungsten:AST:Var.new(s)

  # Class-body `with NAME in (type1 type2 …)` constraint clause.
  # Whitespace-delimited typename list. Registers the constraint on
  # the enclosing class def via @pending_class_constraints; returns
  # a NilLit so the no-op sits harmlessly in the body.
  -> parse_with_constraint
    expect_kw("with")
    if !(at_type?(T_NAME) || at_type?(T_CONSTANT) || at_type?(T_ID) || at_type?(T_TYPE))
      raise compile_error_at(:E_PARSE_EXPECTED_TOKEN, "Expected type-param name after `with`, got [current_desc()]")
    param_name = advance_value()
    expect_kw("in")
    expect_type(T_LPAREN)
    types = []
    skip_structure_whitespace()
    while !at_type?(T_RPAREN) && !at_type?(T_EOF)
      if at_type?(T_NAME) || at_type?(T_CONSTANT) || at_type?(T_ID) || at_type?(T_TYPE)
        types.push(advance_value())
      else
        raise compile_error_at(:E_PARSE_EXPECTED_TOKEN, "Expected type name inside constraint list, got [current_desc()]")
      skip_structure_whitespace()
      if at_type?(T_COMMA)
        advance()
        skip_structure_whitespace()
    expect_type(T_RPAREN)
    if @pending_class_constraints == nil
      raise compile_error_at(:E_PARSE_EXPECTED_TOKEN, "`with NAME in (...)` constraint only legal inside a class or trait body")
    @pending_class_constraints.push([param_name, types])
    Tungsten:AST:Nil.new()

  -> parse_var_or_call
    tok_line = current_line()
    tok_col = current_col()
    tok_loc = make_loc_here()
    name = advance_value()

    # Prime notation: `x'` is the same-named property on the first
    # argument — `x - x'` reads "my x minus their x". Desugars to
    # `@1.x`, so it is meaningful inside `-> name/N` arity methods,
    # whose positional args bind as __arg1, __arg2, ….
    if name.size() > 1 && name.ends_with?("'")
      prime_call = Tungsten:AST:Call.new(Tungsten:AST:Parg.new(1), name.slice(0, name.size() - 1), [], nil)
      prime_call.loc = tok_loc
      return prime_call

    # Typed array allocation: bool[expr]
    if name == "bool" && at_type?(T_LBRACKET)
      advance()
      size_expr = parse_expression()
      expect_type(T_RBRACKET)
      return Tungsten:AST:TypedArrayNew.new("bool", size_expr)

    if name in ("ro" "rw")
      return parse_accessor_call(name, tok_loc, tok_line)

    result = parse_call_args_and_block(false, tok_line, tok_col, name)
    args = result[0]
    block = result[1]

    if args != nil || block != nil
      if args == nil
        args = []
      args = math_fn_rewrite(name, args)
      call_node = Tungsten:AST:Call.new(nil, name, args, block)
      call_node.loc = tok_loc
      call_node.loc_end = make_end_loc()
      return call_node

    Tungsten:AST:Var.new(name)

  -> hash_literal_body_start?
    if !at_type?(T_LBRACE)
      return false
    t1 = peek_type(1)
    t2 = peek_type(2)
    if t1 == T_RBRACE
      return true
    if t1 == T_ID && t2 == T_COLON
      return true
    if t1 in (T_STRING T_SYMBOL T_INT T_NAME T_CONSTANT) && (t2 == T_COLON || t2 == T_FAT_ARROW)
      return true
    false

  -> parse_accessor_call(name, tok_loc, tok_line)
    args = nil
    block = nil
    default_expr = nil

    if at_type?(T_LPAREN)
      advance()
      args = parse_arg_list(:RPAREN)
      expect_type(T_RPAREN)
    elsif !@no_bare_args && (current_line() == tok_line) && bare_arg_start?()
      args = parse_bare_args()

    if args == nil
      args = []

    if at_type?(T_LBRACE)
      if hash_literal_body_start?()
        default_expr = parse_hash_literal()
      else
        block = parse_block()
        if block != nil
          # AST task #5: block_body skips kind+slab_offset_for lookup;
          # cache the Array so .size() and [0] don't re-fetch.
          blk_body = block_body(block)
          if blk_body != nil && blk_body.size() == 1
            default_expr = blk_body[0]

    args = math_fn_rewrite(name, args)
    call_node = Tungsten:AST:Call.new(nil, name, args, block)
    call_node.loc = tok_loc
    call_node.loc_end = make_end_loc()
    if default_expr != nil
      call_node.default = default_expr
    call_node

  -> parse_lambda
    expect_type(T_ARROW)
    params = []
    if at_type?(T_LPAREN)
      advance()
      while !at_type?(T_RPAREN)
        if at_type?(T_POW)
          advance()
          params.push(expect_identifier_name_value())
        elsif at_type?(T_STAR)
          advance()
          if at_type?(T_STAR)
            advance()
          params.push(expect_identifier_name_value())
        else
          params.push(expect_identifier_name_value())
        match_type?(T_COMMA)
      expect_type(T_RPAREN)
    skip_newlines()
    body = nil
    if at_type?(T_INDENT)
      body = parse_body()
    elsif at_type?(T_LBRACE)
      advance()
      skip_block_whitespace()
      body = []
      while !at_type?(T_RBRACE) && !at_type?(T_EOF)
        body.push(parse_expression())
        skip_block_whitespace()
      expect_type(T_RBRACE)
    else
      body = [parse_expression(false)]
    Tungsten:AST:Block.new(params, body)

  -> parse_call_args_and_block(allow_block_without_args = false, call_line = nil, call_col = nil, call_name = nil)
    args = nil
    block = nil
    has_parens = false

    if at_type?(T_LPAREN)
      has_parens = true
      advance()
      args = parse_arg_list(:RPAREN)
      expect_type(T_RPAREN)
    elsif !@no_bare_args && (call_line == nil || current_line() == call_line) && bare_arg_start?()
      if at_type?(T_LBRACKET) && call_col != nil && call_name != nil && current_col() <= call_col + call_name.size()
        return [args, block]
      args = parse_bare_args()

    # Bare `name ->` is ambiguous with constructs like range implicit-each,
    # but dotted calls like `recv.each ->` should always be allowed.
    if args != nil || has_parens || allow_block_without_args
      if at_type?(T_LBRACE)
        block = parse_block()
      elsif at_type?(T_ARROW)
        block = parse_lambda()

    [args, block]

  -> parse_arg_list(terminator)
    args = []
    skip_newlines()
    # All call sites pass :RPAREN; we ignore the arg and check directly
    # against T_RPAREN. Keeps the param for now in case future callers
    # want a different terminator (e.g., T_RBRACKET).
    while !at_type?(T_RPAREN)
      # Block pass: &name
      if at_type?(T_AMPERSAND)
        advance()
        args.push(Tungsten:AST:Var.new(expect_identifier_name_value()))
        if at_type?(T_COMMA)
          advance()
          skip_spaces()
          skip_newlines()
        else
          skip_newlines()
          break
        next
      # Splat / kwargs splat: *name or **name → pass through as expression.
      if at_type?(T_POW)
        advance()
        args.push(parse_expression())
        if at_type?(T_COMMA)
          advance()
          skip_spaces()
          skip_newlines()
        else
          skip_newlines()
          break
        next
      if at_type?(T_STAR)
        advance()
        if at_type?(T_STAR)
          advance()
        args.push(parse_expression())
        if at_type?(T_COMMA)
          advance()
          skip_spaces()
          skip_newlines()
        else
          skip_newlines()
          break
        next
      # Keyword arg: name: value → collected into a hash literal
      if keyword_label_token?()
        entries = []
        while keyword_label_token?()
          key_value = advance_value()
          advance()  # consume ':'
          val = parse_expression()
          entries.push([Tungsten:AST:Symbol.new(key_value), val])
          if at_type?(T_COMMA)
            advance()
            skip_spaces()
            skip_newlines()
          else
            break
        kwh = Tungsten:AST:HashLiteral.new(entries)
        kwh.from_kwargs = true
        args.push(kwh)
      else
        arg = parse_expression()
        if at_type?(T_FAT_ARROW)
          advance()
          val = parse_expression()
          arg = Tungsten:AST:HashLiteral.new([[arg, val]])
        args.push(arg)
        if at_type?(T_COMMA)
          advance()
          skip_spaces()
          skip_newlines()
        else
          skip_newlines()
          break
    args

  -> bare_arg_start?
    t = tok_type(@current_packed)
    if t in (T_INT T_FLOAT T_STRING T_STRING_INTERP T_REGEX T_REGEX_CAPTURE T_SYMBOL)
      return true
    if t in (T_NAME T_CONSTANT T_IVAR T_BANG T_LPAREN T_LBRACKET T_BLOCK_CALL)
      return true
    if at_kw?("with")
      return true
    if t == T_ID && !is_keyword?(current_value())
      return true
    false

  -> parse_bare_args
    args = []
    if keyword_label_token?()
      entries = []
      while keyword_label_token?()
        key_value = advance_value()
        advance()
        val = parse_assignment()
        entries.push([Tungsten:AST:Symbol.new(key_value), val])
        if at_type?(T_COMMA)
          advance()
          skip_spaces()
        else
          break
      kwh = Tungsten:AST:HashLiteral.new(entries)
      kwh.from_kwargs = true
      args.push(kwh)
      return args

    arg = parse_assignment()
    if at_type?(T_FAT_ARROW)
      advance()
      val = parse_assignment()
      arg = Tungsten:AST:HashLiteral.new([[arg, val]])
    args.push(arg)
    while at_type?(T_COMMA)
      advance()
      skip_spaces()
      if keyword_label_token?()
        entries = []
        while keyword_label_token?()
          key_value = advance_value()
          advance()
          val = parse_assignment()
          entries.push([Tungsten:AST:Symbol.new(key_value), val])
          if at_type?(T_COMMA)
            advance()
            skip_spaces()
          else
            break
        kwh = Tungsten:AST:HashLiteral.new(entries)
        kwh.from_kwargs = true
        args.push(kwh)
        return args
      arg = parse_assignment()
      if at_type?(T_FAT_ARROW)
        advance()
        val = parse_assignment()
        arg = Tungsten:AST:HashLiteral.new([[arg, val]])
      args.push(arg)
    args

  -> parse_block
    if !at_type?(T_LBRACE)
      return nil
    advance()
    params = []

    if at_type?(T_PIPE)
      advance()
      while !at_type?(T_PIPE)
        params.push(expect_identifier_name_value())
        match_type?(T_COMMA)
      expect_type(T_PIPE)

    skip_block_whitespace()
    body = []
    while !at_type?(T_RBRACE) && !at_type?(T_EOF)
      body.push(parse_expression())
      skip_block_whitespace()
    expect_type(T_RBRACE)

    Tungsten:AST:Block.new(params, body)

  -> parse_array_literal
    expect_type(T_LBRACKET)
    skip_structure_whitespace()
    elements = []

    while !at_type?(T_RBRACKET)
      elem = parse_expression()
      # Per-element type ascription: `[1 ## T, 0 ## T, …]`. parse_expression
      # stops before a `## TYPE` postfix (only assignment / ternary / call-arg
      # contexts consume it), so absorb it here and pin it on the element.
      # Monomorphization rewrites the `T` to a concrete type, then lower_array
      # coerces a float-typed integer literal into a real float element — the
      # matrix `.identity` / `.zero` bodies and any `[N ## T, …]` rely on this.
      if at_type?(T_TYPE_HINT)
        hint = current_value()
        comment_pos = hint.index("#")
        if comment_pos != nil
          hint = hint.slice(0, comment_pos)
        elem.type_hint = hint.strip()
        advance()
      elements.push(elem)
      if at_type?(T_COMMA)
        advance()
        skip_structure_whitespace()
      else
        skip_structure_whitespace()
        break

    expect_type(T_RBRACKET)
    Tungsten:AST:Array.new(elements)

  -> skip_structure_whitespace
    while at_type?(T_NEWLINE) || at_type?(T_SEMICOLON) || at_type?(T_INDENT) || at_type?(T_DEDENT)
      advance()

  -> parse_hash_literal
    expect_type(T_LBRACE)
    skip_structure_whitespace()
    entries = []

    while !at_type?(T_RBRACE)
      # Phase 4e: hash-key sigil shadowing fix — type-name tokens (`u8`, `f32`,
      # `i64`, etc.) followed by `:` parse as symbol keys here, matching the
      # shorthand for `:ID:`. Without this, `{f16: buf}` and `{u8: count}` would
      # fall into parse_expression for the key, where `f16` / `u8` start a
      # typed-array constructor instead of resolving as a symbol literal.
      if (at_type?(T_ID) || at_type?(T_TYPE) || at_kw?("with")) && peek_type() == T_COLON
        key_value = advance_value()
        advance()  # consume ':'
        # Shorthand {key:} means {key: key} — value is same as key name
        if at_type?(T_COMMA) || at_type?(T_RBRACE) || at_type?(T_NEWLINE) || at_type?(T_DEDENT)
          entries.push([Tungsten:AST:Symbol.new(key_value), Tungsten:AST:Var.new(key_value)])
        else
          value = parse_expression()
          entries.push([Tungsten:AST:Symbol.new(key_value), value])
      else
        key = parse_expression(false)
        if at_type?(T_FAT_ARROW)
          advance()
        else
          expect_type(T_COLON)
        value = parse_expression()
        entries.push([key, value])
      if at_type?(T_COMMA)
        advance()
        skip_structure_whitespace()
      else
        skip_structure_whitespace()
        break

    expect_type(T_RBRACE)
    Tungsten:AST:HashLiteral.new(entries)

  -> parse_string_interp
    raw_parts = advance_value()
    parts = []
    i = 0
    while i < raw_parts.size()
      part = raw_parts[i]
      if part[0] == :str
        parts.push([:str, part[1]])
      else
        expr_source = part[1]
        expr_lexer = Lexer.new(expr_source, "<interp>")
        expr_count = expr_lexer.tokenize()
        expr_parser = Parser.new(expr_count, expr_lexer.packed_tokens, expr_source, expr_lexer.values, expr_lexer.line_at, expr_lexer.col_at, expr_lexer.file).set_chars(expr_lexer.chars)
        expr_parser.skip_newlines()
        expr_ast = expr_parser.parse_expression()
        parts.push([:expr, expr_ast])
      i += 1
    Tungsten:AST:StringInterp.new(parts)

  -> parse_int_value(str)
    if str.size() >= 2
      prefix = str.slice(0, 2)
      if prefix in ("0x" "0X")
        return parse_hex_int(str)
      if prefix in ("0b" "0B")
        return parse_bin_int(str)
      if prefix in ("0o" "0O")
        return parse_oct_int(str)
    # Decimal — remove underscores and convert
    clean = str.replace("_", "")
    result = 0
    i = 0
    while i < clean.size()
      result = result * 10 + clean[i].to_i()
      i += 1
    result

  -> hex_digit_value(ch)
    if ch >= "0" && ch <= "9"
      return ch.to_i()
    if ch in ("a" "A")
      return 10
    if ch in ("b" "B")
      return 11
    if ch in ("c" "C")
      return 12
    if ch in ("d" "D")
      return 13
    if ch in ("e" "E")
      return 14
    if ch in ("f" "F")
      return 15
    0

  -> parse_hex_int(str)
    digits = str.slice(2, str.size() - 2).replace("_", "")
    result = 0
    i = 0
    while i < digits.size()
      result = result * 16 + hex_digit_value(digits[i])
      i += 1
    result

  -> parse_wvalue_value(str)
    digits = str.slice(3, str.size() - 3)
    result = 0
    i = 0
    while i < digits.size()
      result = result * 16 + hex_digit_value(digits[i])
      i += 1
    result

  # Accumulate the digit through hex_digit_value (same as parse_hex_int)
  # rather than a bare `to_i`/`+= 1`: its boxed return keeps `result` off the
  # native-i64 path, so the accumulator promotes to BigInt above 2^63 instead
  # of wrapping (parity with hex; lets >2^63 binary/octal literals be exact).
  -> parse_bin_int(str)
    digits = str.slice(2, str.size() - 2).replace("_", "")
    result = 0
    i = 0
    while i < digits.size()
      result = result * 2 + hex_digit_value(digits[i])
      i += 1
    result

  -> parse_oct_int(str)
    digits = str.slice(2, str.size() - 2).replace("_", "")
    result = 0
    i = 0
    while i < digits.size()
      result = result * 8 + hex_digit_value(digits[i])
      i += 1
    result

  # -- Platform guard parsing --
  #
  # Grammar:
  #   on_guard       := 'on' target_or (with_clause)* INDENT body DEDENT
  #   target_or      := target_and ('||' target_and)*
  #   target_and     := target_not ('&&' target_not)*
  #   target_not     := '!' target_not | target_primary
  #   target_primary := ID | '(' target_or ')'
  #   with_clause    := 'with' ID

  -> parse_on_guard
    expect_kw("on")
    predicate = parse_target_or()
    capabilities = []
    while at_kw?("with")
      advance()
      capabilities.push(expect_type_value(T_ID))
    skip_newlines()
    body = parse_body()
    Tungsten:AST:OnGuard.new(predicate, capabilities, body)

  -> parse_target_or
    left = parse_target_and()
    while at_type?(T_OR)
      advance()
      left = Tungsten:AST:TargetOr.new(left, parse_target_and())
    left

  -> parse_target_and
    left = parse_target_not()
    while at_type?(T_AND)
      advance()
      left = Tungsten:AST:TargetAnd.new(left, parse_target_not())
    left

  -> parse_target_not
    if at_type?(T_BANG)
      advance()
      return Tungsten:AST:TargetNot.new(parse_target_not())
    parse_target_primary()

  -> parse_target_primary
    if at_type?(T_LPAREN)
      advance()
      expr = parse_target_or()
      expect_type(T_RPAREN)
      return expr
    name = expect_type_value(T_ID)
    Tungsten:AST:TargetDesignator.new(name)
