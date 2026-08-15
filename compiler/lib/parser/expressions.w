+ Parser

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
        # `x.&(y)` — the lexer fuses `&(` into one BLOCK_CALL token; the
        # name is `&` with the arg list's LPAREN already consumed.
        dot_name_fused = at_type?(T_BLOCK_CALL)
        if dot_name_fused
          advance()
          name = "&"
        else
          name = expect_method_name_value()
          # SCREAMING_SNAKE identifiers tokenize as CONSTANT followed by a
          # separate bang, unlike lowercase `sort!` whose bang stays in the ID
          # token. Accept the same method-name suffix for class-level contract
          # spellings such as Tungsten.LOCK_THE_DOORS!.
          if at_type?(T_BANG) && !@sp_before
            advance()
            name = name + "!"
        result = parse_call_args_and_block(true, name_line, name_col, name, dot_name_fused)
        args = result[0]
        block = result[1]
        if args == nil
          args = []
        receiver = expr
        expr = Tungsten:AST:Call.new(receiver, name, args, block)
        # Closed-world compiler contracts are legal only in the entry program.
        # Preserve their file provenance across Loader's flattened `use` graph
        # so it can reject a dependency that tries to impose either contract
        # on its caller.
        if ast_kind(receiver) == :class_ref && receiver.name == "Tungsten" && name in ("PROTECT_THE_CORE!" "STOP_THE_PRESS!" "LOCK_THE_DOORS!")
          expr.source_path = @file
        # ClassRef nodes are interned by name, so sparse generic metadata must
        # live on this distinct call node. Otherwise parsing `Mat<T, m, n>` in
        # one source file can overwrite a user's later `Mat<f64, 2, 3>` (or
        # vice versa) through the globally shared `Mat` leaf.
        if ast_kind(receiver) == :class_ref && receiver.type_args != nil
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
      elsif at_type?(T_LBRACKET) && !is_block_node?(expr) && !@sp_before && current_line() == expr_end_line_for(expr)
        # Indexing is a TIGHT postfix: `xs[i]` on the same line. A `[` on a
        # later line after a call-with-block used to be misparsed as
        # `xs.each(...)[n, n]` → "Expected RBRACKET, got COMMA" for a bare
        # tail array literal. Mirror the same-line rule used for trailing
        # `if` / `unless` modifiers.
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

  # Classify an int literal's spelling from its TOKEN TEXT. Beyond-i64
  # decimals are marked :dec_big AT PARSE TIME: magnitude must be decided
  # here, not during inference — reading a packed literal node's sparse
  # raw/value fields in infer_type materializes the node and perturbs
  # slab-arena state, which shifts block numbering between stage 1 and
  # stage 2 (a .ll identity break). `format` is an eager constructor
  # field, so its reads stay side-effect-free. Decimal literals are
  # unsigned in source; 19 same-length digit strings compare numerically.
  -> int_literal_format(raw)
    if raw.starts_with?("0x") || raw.starts_with?("0X")
      return :hex
    if raw.starts_with?("0b") || raw.starts_with?("0B")
      return :bin
    if raw.starts_with?("0o") || raw.starts_with?("0O")
      return :oct
    digits = raw
    if digits.index("_") != nil
      digits = digits.replace("_", "")
    dl = digits.size()
    if dl > 19 || (dl == 19 && digits > "9223372036854775807")
      return :dec_big
    nil

  # Build an Int AST node from an integer value via its decimal text — the
  # same construction T_INT uses (a bare Int.new(n) stores a value that
  # ast_get(:value) reads back wrong downstream).
  -> sigma_int(n)
    s = "" + n.to_s()
    Tungsten:AST:Int.new(parse_int_value(s), int_literal_format(s), s)

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
      return Tungsten:AST:Int.new(parse_int_value(raw), int_literal_format(raw), raw)

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

    # Decimal array (%d[1.0 2.5 3.75]) — desugars to a plain Array of
    # Decimal literals, so lowering, the interpreter, and `| <unit>`
    # treat it exactly like [1.0, 2.5, 3.75].
    if at_type?(T_DECIMAL_ARRAY)
      comps = advance_value()
      nodes = []
      ci = 0
      while ci < comps.size()
        nodes.push(Tungsten:AST:Decimal.new(comps[ci]))
        ci += 1
      return Tungsten:AST:Array.new(nodes)

    # Typed float array (%f32[1.0 2.5] / %f64[…]) — desugars to a Float
    # literal Array piped through Array#to_f32/to_f64, which build a real
    # typed buffer (ebits -32/-64), the same storage f64[n] fills.
    if at_type?(T_FLOAT_ARRAY)
      payload = advance_value()
      width = payload[0]
      if width != "32" && width != "64"
        raise compile_error_at(:E_PARSE_UNEXPECTED_TOKEN, "unsupported float array width %f" + width + " — use %f32 or %f64")
      comps = payload[1]
      nodes = []
      ci = 0
      while ci < comps.size()
        # Validate each component here: an unchecked token (e.g. "1.5," from
        # comma-separated elements) would flow into the Float literal and
        # surface only as a clang parse error on the emitted IR.
        if !float_array_component_valid?(comps[ci])
          raise compile_error_at(:E_PARSE_UNEXPECTED_TOKEN, "invalid %f" + width + "[] element '" + comps[ci] + "' — elements are space-separated float literals")
        nodes.push(Tungsten:AST:Float.new(comps[ci]))
        ci += 1
      conv = "to_f64"
      if width == "32"
        conv = "to_f32"
      return Tungsten:AST:Call.new(Tungsten:AST:Array.new(nodes), conv, [])
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

  # A %f32[…]/%f64[…] element must be a bare float literal: optional sign,
  # digits with at most one dot, optional e/E exponent with optional sign.
  -> float_array_component_valid?(s)
    if s == nil || s.size() == 0
      return false
    i = 0
    first = s.slice(0, 1)
    if first == "-" || first == "+"
      i = 1
    digits = 0
    dots = 0
    seen_exp = false
    while i < s.size()
      c = s.slice(i, 1)
      if c >= "0" && c <= "9"
        digits += 1
      elsif c == "."
        if dots > 0 || seen_exp
          return false
        dots += 1
      elsif (c == "e" || c == "E") && digits > 0 && !seen_exp
        seen_exp = true
        if i + 1 < s.size()
          nxt = s.slice(i + 1, 1)
          if nxt == "-" || nxt == "+"
            i += 1
      else
        return false
      i += 1
    digits > 0

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
    # `## type` annotates the returned VALUE, not the control-transfer node.
    # The general expression wrapper cannot repair this after parse_return:
    # lowering a TypeAscription(Return(...)) emits the return first and then
    # tries to coerce its nil placeholder. Keep the annotation inside Return
    # so typed raw helpers preserve early-return control flow and ABI.
    value = parse_assignment()
    value = consume_trailing_type_ascription(value)
    Tungsten:AST:Return.new(value)

  -> consume_trailing_type_ascription(expr)
    if !at_type?(T_TYPE_HINT)
      return expr
    hint = current_value()
    comment_pos = hint.index("#")
    if comment_pos != nil
      hint = hint.slice(0, comment_pos)
    validate_type_hint_spelling(hint)
    advance()
    Tungsten:AST:TypeAscription.new(expr, hint.strip())

  # `str` is a common Python/Ruby translation slip, but it has never been a
  # Tungsten type. Reject it where the source still has a precise span instead
  # of letting lowering intern :str as an unknown pseudo-type. Internal
  # interpolation tuples use :str as a storage tag; they never enter here.
  -> validate_type_hint_spelling(hint)
    text = hint.to_s().strip()
    colon = text.index(":")
    if colon != nil
      text = text.slice(0, colon).strip()
    else
      parts = text.split(" ")
      if parts.size() > 0
        text = parts[0].strip()
    if text == "str" || text.starts_with?("str\[")
      raise compile_error_at(:E_PARSE_INVALID_TYPE_NAME, "unknown type 'str'; Tungsten's text type is 'string'")

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
    # Assignment level, NOT parse_expression — same reason as parse_raise
    # above. `exit(20) if cond` must attach the modifier to the statement;
    # parse_expression binds it to the argument instead, giving
    # `exit(20 if cond)` → `exit(nil)` → a silent exit 0 that also drops
    # every statement after it whenever cond is false.
    Tungsten:AST:Call.new(nil, "exit", [parse_assignment()])

  -> parse_use
    advance()
    # The lexer scans the use path as a STRING token (bare or quoted)
    Tungsten:AST:Use.new(advance_value())

  # begin / rescue / ensure. One or more rescue clauses may follow the body:
  #   rescue e            bind any error
  #   rescue e: Class     bind only an instance of Class (or a subclass)
  #   rescue Class        match without binding
  #   rescue              match without binding
  # Clauses are tried in source order; the first match wins. A single
  # untyped clause is the Begin node's native shape. Typed or multiple
  # clauses desugar in the parser — so both engines share one implementation
  # — to a hidden binding plus an `is_a?` chain, whose final arm re-raises
  # the ORIGINAL error object so the enclosing handler (and this begin's own
  # ensure) see it unchanged.
  -> parse_begin
    expect_kw("begin")
    skip_newlines()
    body = parse_body()

    clauses = []
    while at_kw?("rescue")
      advance()
      clause_var = nil
      clause_class = nil
      if !at_type?(T_NEWLINE) && !at_type?(T_INDENT) && !at_type?(T_DEDENT) && !at_type?(T_EOF)
        if at_type?(T_ID)
          clause_var = expect_type_value(T_ID)
          if at_type?(T_COLON)
            advance()
            clause_class = expect_name_or_constant_value()
        else
          clause_class = expect_name_or_constant_value()
      skip_newlines()
      clause_body = parse_body()
      clauses.push([clause_var, clause_class, clause_body])

    ensure_body = nil
    if at_kw?("ensure")
      advance()
      skip_newlines()
      ensure_body = parse_body()

    if clauses.size() == 0
      return Tungsten:AST:Begin.new(body, nil, nil, ensure_body)
    if clauses[0][1] == nil
      # An untyped first clause catches everything; later clauses are
      # unreachable, exactly as in Ruby.
      return Tungsten:AST:Begin.new(body, clauses[0][0], clauses[0][2], ensure_body)
    hidden = "__rescued"
    Tungsten:AST:Begin.new(body, hidden, [rescue_dispatch_chain(hidden, clauses)], ensure_body)

  # `__rescued.is_a?(Class)`
  -> rescue_class_test(hidden, class_name)
    Tungsten:AST:Call.new(Tungsten:AST:Var.new(hidden), "is_a?", [Tungsten:AST:ClassRef.new(class_name)], nil)

  # The clause body, prefixed with `var = __rescued` when the clause binds.
  -> rescue_clause_body(hidden, clause)
    stmts = []
    if clause[0] != nil
      stmts.push(Tungsten:AST:Assign.new(Tungsten:AST:Var.new(clause[0]), Tungsten:AST:Var.new(hidden), nil))
    i = 0
    while i < clause[2].size()
      stmts.push(clause[2][i])
      i += 1
    stmts

  # if __rescued.is_a?(C1) ... elsif __rescued.is_a?(C2) ... else <bare
  # clause body, or `raise __rescued`>. The first clause is known typed.
  -> rescue_dispatch_chain(hidden, clauses)
    elsifs = []
    else_body = nil
    i = 1
    while i < clauses.size()
      clause = clauses[i]
      if clause[1] == nil
        else_body = rescue_clause_body(hidden, clause)
        break
      elsifs.push([rescue_class_test(hidden, clause[1]), rescue_clause_body(hidden, clause)])
      i += 1
    if else_body == nil
      else_body = [Tungsten:AST:Raise.new(Tungsten:AST:Var.new(hidden))]
    Tungsten:AST:If.new(rescue_class_test(hidden, clauses[0][1]), rescue_clause_body(hidden, clauses[0]), elsifs, else_body)

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
      elsif type_name == "no_raise"
        # Function-level optimizer contract. Keep it in the existing hint
        # sidecar so the packed MethodDef/FnDef schema does not grow merely
        # for a rare declaration-level bit.
        result["__function_no_raise"] = :no_raise
    if result.size() == 0
      return nil
    result
