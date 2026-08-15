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
    # @current_packed is the tagless packed-token i64 for the current
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

  -> file_id
    @file_id

  -> register_struct_name(name)
    if name != nil
      @struct_names[name] = true

  -> struct_name?(name)
    @struct_names[name] == true

  # Raw accessors for packed token descriptors. Production values fit the
  # inline-Int payload. Normalize once so the helpers also accept tagged Token
  # fixtures, then keep shifts and masks unboxed.
  -> tok_type(p)
    parser_tok_type(p)

  -> tok_off(p)
    parser_tok_off(p)

  -> tok_len(p)
    parser_tok_len(p)

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
    # Decode once here rather than dynamically dispatching through tok_len
    # and tok_off. Equality needs both fields from the same token, so two
    # helper calls would repeat numeric normalization and IC dispatch.
    bits = ccall_nobox("w_numeric_to_i64", p)
    len = (bits >> 26) & 0xFFF
    if len != lit.size()
      return false
    # @chars is codepoint-indexed (= source.chars()), matching the token's
    # codepoint offset; @source.slice would be byte-indexed and misalign
    # after any multi-byte UTF-8 char earlier in the file. Keywords and
    # operators are ASCII, so a per-codepoint string compare is exact.
    off = (bits >> 2) & 0xFFFFFF
    ccall_nobox("w_parser_chars_equal_ascii", @chars, off, len, lit) == 1

  -> sync_current
    # Transparently skip :SP tokens so existing parser sites don't see
    # them. @sp_before records whether at least one :SP was skipped,
    # giving disambiguators (e.g., `foo(x)` vs `foo (x)`) a single-bit
    # query without restructuring the grammar around explicit SP nodes.
    @sp_before = false
    while @pos < @token_count && parser_tok_type(@packed_tokens[@pos]) == T_SP
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
    @line_at[parser_tok_off(packed_tok)]

  -> tok_col(packed_tok)
    @col_at[parser_tok_off(packed_tok)]

  -> current_line
    @line_at[parser_tok_off(@current_packed)]

  -> current_col
    @col_at[parser_tok_off(@current_packed)]

  -> current_offset
    parser_tok_off(@current_packed)

  # Compile-error helper — builds the runtime raise dict for a parse
  # error AT THE CURRENT POSITION, deriving file/row/col from @file
  # and the @line_at/@col_at lookup tables (indexed by the current
  # packed token's offset). Replaces the verbose hash-reading raise
  # blocks at error sites. Unrelated to make_loc_offset above: this
  # builds a plain Hash with row/col as ordinary Integers (no bit-
  # packing), so there's no truncation concern here to begin with.
  -> compile_error_at(code, message)
    off = parser_tok_off(@current_packed)
    {rt: :compile_error, code: code, message: message, file: @file, row: @line_at[off], col: @col_at[off], span_length: 1}

  # Packed-loc for any packed Token. Used at AST-construction sites
  # that want the loc for a specific (peeked or saved) token rather
  # than @current_packed.
  -> make_loc_for(packed_tok)
    make_loc_offset(parser_tok_off(packed_tok))

  -> make_loc_here
    make_loc_offset(parser_tok_off(@current_packed))

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
    when 168 then "APPROX"
    when 160 then "POW_EQ"
    when 161 then "AMP_EQ"
    when 162 then "PIPE_EQ"
    when 163 then "CARET_EQ"
    when 164 then "LSHIFT_EQ"
    when 165 then "RSHIFT_EQ"
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
    "[tok_type_name(parser_tok_type(@current_packed))]([current_value()])"

  # Returns the operator symbol (:PLUS, :STAR, …) for the current
  # token, then advances. Replaces the legacy `advance()[:type]`
  # idiom in the binary-op while-loops. The symbol contract is the
  # same one lowering's `op == :PLUS` branches consume.
  -> advance_op_sym
    sym = op_sym(parser_tok_type(@current_packed))
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
    when T_APPROX then :APPROX
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
      if parser_tok_type(@packed_tokens[idx]) != T_SP
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
      if parser_tok_type(@packed_tokens[idx]) != T_SP
        seen += 1
        if seen == offset
          return idx
      idx += 1
    -1

  -> peek_type(offset = 1)
    parser_tok_type(peek_packed(offset))

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
    parser_tok_type(@current_packed) == type_id

  -> minus_token?
    at_type?(T_MINUS)

  -> star_token?
    at_type?(T_STAR)

  -> data_decl_ahead?
    idx = @pos + 1
    while idx < @token_count && parser_tok_type(@packed_tokens[idx]) == T_SP
      idx += 1
    if idx >= @token_count
      return false
    t = parser_tok_type(@packed_tokens[idx])
    t == T_ID || t == T_TYPE

  # Integer-id companion of expect_type(T_SYM). Raises on mismatch.
  # No return value — all callers throw it away.
  -> expect_type(type_id)
    if parser_tok_type(@current_packed) != type_id
      raise compile_error_at(:E_PARSE_EXPECTED_TOKEN, "Expected [type_id], got [current_desc()]")
    advance()

  # Combines expect_type + value read — replaces the common idiom
  # `expect_type_value(T_X)`. Raises on type mismatch, otherwise
  # returns @values[pos] then advances.
  -> expect_type_value(type_id)
    if parser_tok_type(@current_packed) != type_id
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
    parser_tok_type(@current_packed) == T_KEYWORD && @values[@pos] == kw

  -> expect_kw(kw)
    if !at_kw?(kw)
      raise compile_error_at(:E_PARSE_EXPECTED_TOKEN, "Expected keyword '[kw]', got [current_desc()]")
    advance()

  # Generic (type, literal) check — used for IVAR + specific name
  # combos like `@gpu`, `@schedule` that disambiguate attribute
  # directives. Same pattern as at_kw? but parameterized on type.
  -> at_typed?(type_id, literal)
    parser_tok_type(@current_packed) == type_id && tok_equal?(@current_packed, @source, literal)

  -> expect_typed(type_id, literal)
    if !at_typed?(type_id, literal)
      raise compile_error_at(:E_PARSE_EXPECTED_TOKEN, "Expected '[literal]', got [current_desc()]")
    advance()

  -> expect_method_name
    if parser_tok_type(@current_packed) in (T_ID T_TYPE T_KEYWORD T_NAME T_CONSTANT)
      advance()
      return nil
    if at_type?(T_LBRACKET) && peek_type() == T_RBRACKET
      advance()
      advance()
      if at_type?(T_ASSIGN)
        advance()
      return nil
    if parser_tok_type(@current_packed) in (T_BANG T_PUTS_OP T_LSHIFT T_RSHIFT T_PLUS T_MINUS T_STAR T_POW T_SLASH T_PERCENT T_AMPERSAND T_PIPE T_CARET T_DOT_PRODUCT T_CROSS_PRODUCT T_HADAMARD T_KRONECKER T_EQ T_TRIPLE_EQ T_NEQ T_MATCH T_NMATCH T_LT T_GT T_LTE T_GTE T_SPACESHIP T_APPROX)
      advance()
      return nil
    raise compile_error_at(:E_PARSE_EXPECTED_METHOD_NAME, "Expected method name, got [current_desc()]")

  # String-returning companion. Same dispatch as expect_method_name
  # but returns just the name (e.g. "foo", "[]", "[]=", "+") without
  # the surrounding hash. Used at AST-construction sites that only
  # need the name + an already-captured loc.
  -> expect_method_name_value
    if parser_tok_type(@current_packed) in (T_ID T_TYPE T_KEYWORD T_NAME T_CONSTANT)
      return advance_value()
    if at_type?(T_LBRACKET) && peek_type() == T_RBRACKET
      advance()
      advance()
      if at_type?(T_ASSIGN)
        advance()
        return "[]="
      return "[]"
    if parser_tok_type(@current_packed) in (T_BANG T_PUTS_OP T_LSHIFT T_RSHIFT T_PLUS T_MINUS T_STAR T_POW T_SLASH T_PERCENT T_AMPERSAND T_PIPE T_CARET T_DOT_PRODUCT T_CROSS_PRODUCT T_HADAMARD T_KRONECKER T_EQ T_TRIPLE_EQ T_NEQ T_MATCH T_NMATCH T_LT T_GT T_LTE T_GTE T_SPACESHIP T_APPROX)
      return advance_value()
    # T_CLASS_DEF is the bare `+` token at line-start positions; after
    # `-> ` it's still the plus method name. Accept it here so
    # `-> +/1` (componentwise add) parses.
    if at_type?(T_CLASS_DEF)
      return advance_value()
    expect_method_name()
    ""

  -> identifier_name_token?
    parser_tok_type(@current_packed) == T_ID || parser_tok_type(@current_packed) == T_TYPE || at_kw?("with")

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
    if parser_tok_type(@current_packed) != type_id
      return false
    advance()
    true

  -> skip_newlines
    while parser_tok_type(@current_packed) in (T_NEWLINE T_TYPE_HINT)
      if at_type?(T_TYPE_HINT)
        validate_type_hint_spelling(current_value())
        @pending_type_hints.push(current_value())
      advance()

  -> skip_spaces
    while at_type?(T_SP)
      advance()

  -> skip_statement_end
    while parser_tok_type(@current_packed) in (T_NEWLINE T_SEMICOLON T_TYPE_HINT)
      if at_type?(T_TYPE_HINT)
        validate_type_hint_spelling(current_value())
        @pending_type_hints.push(current_value())
      advance()

  -> skip_block_whitespace
    while parser_tok_type(@current_packed) in (T_NEWLINE T_SEMICOLON T_INDENT T_DEDENT)
      advance()

  # -- Program & body parsing --

  -> parse_program
    skip_newlines()
    exprs = Tungsten:AST:BodyBuilder.new()
    while !at_type?(T_EOF) && !at_type?(T_DEDENT)
      expr = parse_expression()
      expr = finish_statement_expression(expr)
      # Loader flattens every `use`d program into one top-level expression
      # stream.  Preserve the declaring file on *all* top-level statements,
      # not only definitions: stable-Core partitioning also needs to own
      # global initializers, aliases, and other executable prelude setup.
      # source_path is a sparse AST sidecar, so this does not enlarge packed
      # slab nodes or change the generated schema ABI. Do not attach it to an
      # interned/inline/singleton leaf: those handles are shared by value (a
      # top-level `nil` in two files is literally the same node), so metadata
      # there would alias provenance. Such unusual standalone leaves make the
      # reuse contract conservatively fall back instead.
      kind = ast_kind(expr)
      kind_id = kind_id_table[kind]
      schema_keys = nil
      if kind_id != nil
        schema_keys = slab_keys_table[kind_id]
      occurrence_local = schema_keys != nil && schema_keys.size() > 0 && kind != :bool
      if occurrence_local
        first_offset = slab_offset_for(kind, schema_keys[0])
        occurrence_local = first_offset == nil || first_offset < 256
      if occurrence_local && ast_get(expr, :source_path) == nil
        ast_set(expr, :source_path, @file)
      exprs.push(expr)
    exprs.finish()

  -> parse_body
    expect_type(T_INDENT)
    exprs = Tungsten:AST:BodyBuilder.new()
    while !at_type?(T_DEDENT) && !at_type?(T_EOF)
      expr = parse_expression()
      exprs.push(finish_statement_expression(expr))
    if !at_type?(T_EOF)
      expect_type(T_DEDENT)
    exprs.finish()

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
    if t in (:if :while :with :parallel_with :case :begin :method_def :fn_def :class_def :trait_def :on_guard)
      return true
    # A call that carries a trailing block is a multi-line statement form
    # (`xs.each -> …`). Do not accept a next-line `[` as indexing of it —
    # that misparses a bare tail array literal as `each(...)[n, n]`.
    if t == :call && node.block != nil
      return true
    false

  # Exclusive end line of `expr` when recorded; else its start line; else
  # the current line. Used to keep tight postfix `[]` on the same line as
  # the receiver (see parse_postfix_from indexing rule).
  -> expr_end_line_for(expr)
    out = current_line()
    if expr != nil
      el = expr.end_line
      if el != nil && el > 0
        out = el
      else
        sl = expr.line
        out = sl if sl != nil && sl > 0
    out

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
      while ns_pos < @token_count && parser_tok_type(@packed_tokens[ns_pos]) == T_SP
        ns_pos += 1
      tt = parser_tok_type(@packed_tokens[ns_pos])
      if tt == T_NAME || tt == T_CONSTANT || tt == T_TYPE || tt == T_ID
        advance()  # `in`
        skip_spaces()
        ns = advance_value()
        while at_type?(T_SYMBOL)
          ns = ns + ":" + current_value()
          advance()
        @namespace_prefix = ns
        return Tungsten:AST:NamespaceDecl.new(ns)

    # `constant_alias "WC"` bit directive: parsed here (not as a generic
    # bare call) so the file's active `in` namespace rides along as a
    # second string argument — lowering and the tree-walker register
    # alias → namespace from the args alone, with no file context.
    # Token shape: ID("constant_alias") SP STRING NL. With no active
    # namespace (or a non-literal argument) it parses as an ordinary
    # call, which both engines treat as a no-op.
    if at_typed?(T_ID, "constant_alias") && @namespace_prefix != nil
      str_pos = @pos + 1
      while str_pos < @token_count && parser_tok_type(@packed_tokens[str_pos]) == T_SP
        str_pos += 1
      if str_pos < @token_count && parser_tok_type(@packed_tokens[str_pos]) == T_STRING
        advance()
        skip_spaces()
        alias_name = advance_value()
        return Tungsten:AST:Call.new(nil, "constant_alias", [Tungsten:AST:String.new(alias_name), Tungsten:AST:String.new(@namespace_prefix)], nil)

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
      if parser_tok_type(@current_packed) in (T_ID T_TYPE)
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
            if parser_tok_type(@current_packed) == T_INT
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

    # Expression-local type ascription. Assignment already consumes a
    # trailing `## type` into Assign#type_hint; this companion handles the
    # same syntax inside parentheses and arguments, e.g. `($value ## i64)`.
    # Keeping it here gives the ascription lower precedence than arithmetic
    # while still consuming it before the enclosing `)` / `,` delimiter.
    # NEVER onto a def: a def inside a class body ends by consuming its
    # DEDENT, which leaves a next-line `## i64: name` param annotation as
    # the current token here — attaching it to the just-parsed method-def
    # swallowed the hint meant for the NEXT def (class-method `## i64:`
    # ascriptions silently never typed their bodies). Defs take no trailing
    # ascription; own-line hints flow to @pending_type_hints via
    # skip_statement_end for the next def to consume.
    if ast_kind(expr) != :method_def && ast_kind(expr) != :fn_def
      expr = consume_trailing_type_ascription(expr)

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

    # Typed-target assignment: `x ## i64 = 0`. The lexer ends the hint at
    # `=`, so the shape arrives as target, TYPE_HINT("i64"), ASSIGN, value.
    # Normalize to the SAME Assign(+type_hint) node the postfix form
    # (`x = 0 ## i64`) builds, so lowering, both interpreters, and the GPU
    # emitter see one canonical shape.
    if at_type?(T_TYPE_HINT) && peek_type() == T_ASSIGN && valid_assign_target?(left)
      hint = current_value()
      comment_pos = hint.index("#")
      if comment_pos != nil
        hint = hint.slice(0, comment_pos)
      hint = hint.strip()
      validate_type_hint_spelling(hint)
      advance()
      advance()
      value = parse_assignment()
      return Tungsten:AST:Assign.new(to_assign_target(left), value, hint)

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
        validate_type_hint_spelling(hint)
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
          # Opt-in stack allocation for SmallArray.new (and
          # eventually array literals). Caller asserts the value won't
          # outlive its allocating frame. A future escape analysis
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

    if at_type?(T_POW_EQ)
      advance()
      value = parse_assignment()
      target = to_assign_target(left)
      return Tungsten:AST:CompoundAssign.new(target, :POW, value)

    if at_type?(T_AMP_EQ)
      advance()
      value = parse_assignment()
      target = to_assign_target(left)
      return Tungsten:AST:CompoundAssign.new(target, :AMPERSAND, value)

    if at_type?(T_PIPE_EQ)
      advance()
      value = parse_assignment()
      target = to_assign_target(left)
      return Tungsten:AST:CompoundAssign.new(target, :PIPE, value)

    if at_type?(T_CARET_EQ)
      advance()
      value = parse_assignment()
      target = to_assign_target(left)
      return Tungsten:AST:CompoundAssign.new(target, :CARET, value)

    if at_type?(T_LSHIFT_EQ)
      advance()
      value = parse_assignment()
      target = to_assign_target(left)
      return Tungsten:AST:CompoundAssign.new(target, :LSHIFT, value)

    if at_type?(T_RSHIFT_EQ)
      advance()
      value = parse_assignment()
      target = to_assign_target(left)
      return Tungsten:AST:CompoundAssign.new(target, :RSHIFT, value)

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
    if !(t in (:var :gvar :ivar :cvar :call :view_field_var))
      return false
    # Reject bare `func(args)` (no receiver, has args) — it would
    # silently lower as `func = value` (local-var assign of the
    # function name) rather than an intended ast_set/setter call.
    if t == :call && node.receiver == nil && !node.args.empty?()
      return false
    true

  -> to_assign_target(node)
    if ast_kind(node) in (:var :gvar :ivar :cvar :view_field_var)
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
    # PascalCase identifiers parse as class_ref (e.g. `Wit`, `FooBar`,
    # `WIT_keys`). They are not assignable variables. SCREAMING_SNAKE
    # (`WIT_KEYS`, `GOOD_7`) and snake_case (`wit_keys`) are fine.
    if ast_kind(node) == :class_ref
      raise compile_error_at(:E_PARSE_INVALID_ASSIGN_TARGET, "Cannot assign to PascalCase name `[node.name]` — it is a class reference. Use snake_case or SCREAMING_SNAKE for variables (e.g. `wit_keys` or `WIT_KEYS`).")
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
        validate_type_hint_spelling(current_value())
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
  #
  # Loosest to tightest:
  #   or → and → in_test → comparison → equality →
  #   bitwise_or → bitwise_xor → bitwise_and → addition → shift → mult → …
  #
  # Bitwise `& | ^` bind TIGHTER than comparison and equality, following
  # Python, Ruby, Go and Rust — so `x & 1 == 1` means `(x & 1) == 1`.
  # C, C++, Java and JavaScript order these the other way, which makes the
  # same expression `x & (1 == 1)`; Ritchie called it a mistake he could not
  # fix once code depended on it, and C compilers now warn about it. A
  # language whose pitch is readable pseudocode should not inherit it.

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
  # time; a peephole promotes homogeneous chains to dispatch.
  -> parse_in_test
    left = parse_comparison()
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
    # Dot-prefix: `.|` shares bitwise-or precedence with `|`.
    while at_type?(T_PIPE) || at_type?(T_DOT_PIPE)
      op = advance_op_sym()
      right = parse_bitwise_xor()
      left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_bitwise_xor
    left = parse_bitwise_and()
    # Dot-prefix: `.^` shares bitwise-xor precedence with `^`.
    while at_type?(T_CARET) || at_type?(T_DOT_CARET)
      op = advance_op_sym()
      right = parse_bitwise_and()
      left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_bitwise_and
    left = parse_addition()
    # Dot-prefix: `.&` shares bitwise-and precedence with `&`.
    while at_type?(T_AMPERSAND) || at_type?(T_DOT_AMP)
      op = advance_op_sym()
      right = parse_addition()
      left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_comparison
    left = parse_equality()
    while parser_tok_type(@current_packed) in (T_LT T_LTE T_GT T_GTE T_SPACESHIP)
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
    left = parse_bitwise_or()
    while parser_tok_type(@current_packed) in (T_EQ T_NEQ T_MATCH T_APPROX)
      op = advance_op_sym()
      right = parse_bitwise_or()
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
    # Dot-prefix elementwise: `.+ .-` share addition precedence
    # with their scalar counterparts. Julia convention.
    while parser_tok_type(@current_packed) in (T_PLUS T_MINUS T_DOT_PLUS T_DOT_MINUS T_PLUS_MINUS)
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
    # Dot-prefix: `.<<` `.>>` share shift precedence.
    while parser_tok_type(@current_packed) in (T_LSHIFT T_RSHIFT T_DOT_LSHIFT T_DOT_RSHIFT)
      op = advance_op_sym()
      right = parse_multiplication()
      left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_multiplication
    left = parse_power()
    # Dot-prefix elementwise: `.* ./` share multiplication
    # precedence with their scalar counterparts.
    while parser_tok_type(@current_packed) in (T_STAR T_SLASH T_PERCENT T_DOT_STAR T_DOT_SLASH T_DOT_PRODUCT T_CROSS_PRODUCT T_HADAMARD T_KRONECKER)
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
