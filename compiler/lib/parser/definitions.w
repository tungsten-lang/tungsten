+ Parser

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
    name_tok_type = parser_tok_type(@current_packed)
    # `-> &(other)` — the lexer fuses `&(` into one BLOCK_CALL token, so
    # the method name is `&` and the param list's LPAREN is already
    # consumed; the params branch below keys on name_tok_type.
    if name_tok_type == T_BLOCK_CALL
      advance()
      name = "&"
    else
      name = expect_method_name_value()
    # Setter methods: name= (e.g. cache_dir=)
    if at_type?(T_ASSIGN)
      advance()
      name = name + "="

    # Method-name arity (`/N`, `/*`, `/&`). Current lexers emit the suffix as
    # operator tokens so `value/10` remains ordinary division outside a
    # definition. The bundled-name branch is retained for one bootstrap:
    # an older stage-0 lexer may still hand this parser `divmod/1` as one ID.
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
    if arity == nil && at_type?(T_SLASH)
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

    if name_tok_type == T_BLOCK_CALL
      # `&(`'s paren is part of the fused token — parse the param list
      # straight to its closing RPAREN.
      while !at_type?(T_RPAREN)
        params.push(parse_method_param())
        match_type?(T_COMMA)
      expect_type(T_RPAREN)
    elsif arity == :block
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

    # Optional param-type list `(i64 i64)`. Disambiguated by
    # peeking inside the paren group — if the contents are all `:TYPE`
    # tokens followed by `)`, it's a param-type annotation. Otherwise
    # fall through to the trailing-expression path (which handles
    # things like `(a + b)` as a trailing expression).
    param_types = nil
    if at_type?(T_LPAREN) && looks_like_param_types?()
      advance()
      param_types = []
      while !at_type?(T_RPAREN)
        if !is_param_type_token?(parser_tok_type(@current_packed))
          raise compile_error_at(:E_PARSE_BAD_PARAM_TYPE, "Expected type name in param type list, got [current_desc()]")
        param_types.push(parse_type_name_with_array_suffix().to_sym())
      expect_type(T_RPAREN)
      skip_spaces()

    # Optional return type — a bare `:TYPE` token followed by
    # `:` (inline body introducer) or a newline/indent (multi-line body)
    # or the end of the header.
    return_type = nil
    if at_type?(T_TYPE) && looks_like_return_type?()
      return_type = parse_type_name_with_array_suffix().to_sym()
      skip_spaces()

    annotations_present = param_types != nil || return_type != nil

    # `:` is the inline-body introducer in both typed and
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
      # init or inline body, same as before typed signatures existed.
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
    else
      # No trailing expression and no indented block: the method is bodiless
      # (an abstract/interface declaration). A following statement at the
      # SAME indent is a sibling — `-> to_s` then `alias_method :to_s/1,
      # :strftime/1` in a class body must leave to_s abstract, not slurp the
      # alias call as its body.
      body = []

    # Fallthrough: `: expr` after body — default return value
    if at_type?(T_COLON)
      advance()
      fallthrough = parse_expression()
      body_with_fallthrough = Tungsten:AST:BodyBuilder.new(body.size() + 1)
      bfi = 0
      while bfi < body.size()
        body_with_fallthrough.push(body[bfi])
        bfi += 1
      body_with_fallthrough.push(fallthrough)
      body = body_with_fallthrough.finish()

    result = Tungsten:AST:MethodDef.new(base_name, params, body, type_hints, is_class_method)
    result.loc = make_loc_offset(method_off)
    result.loc_end = make_end_loc()
    if param_types != nil
      result.param_types = param_types
    if return_type != nil
      result.return_type = return_type
    result.source_path = @file
    result

  # Lookahead: is the current LPAREN the start of a param-type
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

  # Lookahead: is the current `:TYPE` token a return-type
  # annotation? True iff the token after it is `:` (inline body
  # introducer), `:NEWLINE`, or `:INDENT`. False if it's anything that
  # could start an expression like `.method` or `[index]` or `(args)`.
  -> looks_like_return_type?
    if !at_type?(T_TYPE)
      return false
    t = peek_type(1)
    # `f64[]` — a typed-array return. Look past an *empty* bracket pair
    # before deciding, so the body introducer after it is what gets
    # tested. Requiring `[` `]` adjacent keeps this unambiguous: an index
    # expression like `x[0]` always has something between the brackets.
    if t == T_LBRACKET && peek_type(2) == T_RBRACKET
      t = peek_type(3)
    t == T_COLON || t == T_NEWLINE || t == T_INDENT || t == T_DEDENT || t == T_EOF || t == T_SEMICOLON

  # A type name with an optional `[]` suffix for typed arrays (`f64[]`),
  # stored as the symbol `:"f64[]"` so lowering's existing `## f64[]:`
  # normalization picks it up unchanged. Shared by the param-type list
  # and both return-type slots so every position accepts one spelling.
  -> parse_type_name_with_array_suffix
    validate_type_hint_spelling(current_value())
    name = advance_value()
    if at_type?(T_LBRACKET) && peek_type() == T_RBRACKET
      advance()
      advance()
      name = name + "\[]"
    name

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
            param_types.push(parse_type_name_with_array_suffix().to_sym())
          else
            break
          match_type?(T_COMMA)
          skip_spaces()
        expect_type(T_RPAREN)
        skip_spaces()
      if at_type?(T_TYPE) && looks_like_return_type?()
        return_type = parse_type_name_with_array_suffix().to_sym()
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
      result.source_path = @file
      return result

    # Top-level fn: produce a regular fn_def with both annotations attached.
    # Setting :param_types drives signature-mangled compiled functions and the
    # interpreter's runtime overload table, so same-name typed siblings remain
    # distinct in both engines.
    result = Tungsten:AST:FnDef.new(name, params, body, type_hints)
    result.loc = make_loc_offset(fn_off)
    result.loc_end = make_end_loc()
    if param_types != nil
      result.param_types = param_types
    if return_type != nil
      result.return_type = return_type
    result.source_path = @file
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
      validate_type_hint_spelling(current_value())
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
    validate_type_hint_spelling(ftype)
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

    # Apply file-level `in NAMESPACE` prefix to the class name. Qualified
    # declarations (`+ Registry:Client`) are prefixed like their bare
    # siblings — under `in Tungsten:Bit` both `+ Registry` and
    # `+ Registry:Client` register inside the namespace. A declaration
    # that already spells the active prefix (`+ Tungsten:LRUCache` under
    # `in Tungsten`) passes through unchanged.
    if @namespace_prefix != nil
      if !name.starts_with?(@namespace_prefix + ":")
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
    result.source_path = @file
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
    result = Tungsten:AST:ModuleDef.new(name, body)
    result.source_path = @file
    result

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
    result.source_path = @file
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
      return Tungsten:AST:Int.new(parse_int_value(s), int_literal_format(s), s)
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

  -> parse_call_args_and_block(allow_block_without_args = false, call_line = nil, call_col = nil, call_name = nil, paren_open = false)
    args = nil
    block = nil
    has_parens = false

    # paren_open: the caller consumed a fused name+LPAREN token
    # (BLOCK_CALL `&(`), so the arg list is already open.
    if paren_open
      has_parens = true
      args = parse_arg_list(:RPAREN)
      expect_type(T_RPAREN)
    elsif at_type?(T_LPAREN)
      has_parens = true
      advance()
      args = parse_arg_list(:RPAREN)
      expect_type(T_RPAREN)
    elsif !@no_bare_args && (call_line == nil || current_line() == call_line) && bare_arg_start?()
      if at_type?(T_LBRACKET) && call_col != nil && call_name != nil && current_col() <= call_col + call_name.size()
        return [args, block]
      # `myVar` / `s.myMethod` — a lowercase name immediately followed
      # (NO space) by a Capitalized run is not a call: calls take a space
      # or a paren, and uppercase ASCII is not valid inside identifiers.
      # The one adjacent join that means anything is a unit spelling
      # (`eV`, `mmHg`, `kWh`), which unit-expecting surfaces reconstruct
      # from the juxtaposition call this falls through to.
      if (at_type?(T_NAME) || at_type?(T_CONSTANT)) && call_col != nil && call_name != nil && current_line() == call_line && current_col() == call_col + call_name.size()
        joined_ident = call_name + current_value()
        if !known_unit_name?(joined_ident)
          raise compile_error_at(:E_LEX_INVALID_IDENTIFIER, "uppercase ASCII is not valid in identifiers: '" + joined_ident + "' — use snake_case")
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
    t = parser_tok_type(@current_packed)
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
        validate_type_hint_spelling(hint)
        elem = Tungsten:AST:TypeAscription.new(elem, hint.strip())
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
      # Hash-key sigil shadowing fix — type-name tokens (`u8`, `f32`,
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
