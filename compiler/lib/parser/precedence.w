# Precedence-climbing expression parsers split out of parser/core.w to stay
# within the 1,800-line worker boundary (compiler/test/test_module_boundaries.sh).

+ Parser

  # Operator precedence: bitwise binds tighter than comparison — matching
  # Python, Ruby, Go and Rust — so `x & 1 == 1` means `(x & 1) == 1`.
  # C, C++, Java and JavaScript order these the other way, which makes the
  # same expression `x & (1 == 1)`; Ritchie called it a mistake he could not
  # fix once code depended on it, and C compilers now warn about it. A
  # language whose pitch is readable pseudocode should not inherit it.

  -> parse_or
    parse_or_from(parse_and())

  -> parse_or_from(left)
    while @current_type == TOK_OR
      advance()
      right = parse_and()
      left = Tungsten:AST:Or.new(left, right)
    left

  -> parse_and
    parse_and_from(parse_in_test())

  -> parse_and_from(left)
    while @current_type == TOK_AND
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
    parse_in_test_from(parse_comparison())

  -> parse_in_test_from(left)
    if at_kw?("in")
      advance()
      if @current_type != TOK_LPAREN
        raise compile_error_at(:E_PARSE_IN_EXPECTS_TUPLE, "`in` requires a parenthesized tuple on the right-hand side")
      advance()
      elements = []
      # Suppress bare-arg parsing while inside the tuple — otherwise
      # `in (A B C)` parses A as a Name and treats B/C as its bare
      # args, turning a 3-element tuple into a 1-element function call.
      # The flag is checked in parse_call_args_and_block.
      prev_no_bare_args = @no_bare_args
      @no_bare_args = true
      while @current_type != TOK_RPAREN && @current_type != TOK_EOF
        elements.push(parse_expression())
      @no_bare_args = prev_no_bare_args
      if elements.size() == 0
        raise compile_error_at(:E_PARSE_IN_EMPTY_TUPLE, "`in` tuple must have at least one element")
      expect_type(TOK_RPAREN)
      return Tungsten:AST:InTest.new(left, elements)
    left

  -> parse_bitwise_or
    parse_bitwise_or_from(parse_bitwise_xor())

  -> parse_bitwise_or_from(left)
    # Dot-prefix: `.|` shares bitwise-or precedence with `|`.
    while @current_type in (TOK_PIPE T_DOT_PIPE TOK_UNION)
      set_union = @current_type == TOK_UNION
      op = advance_op_sym()
      right = parse_bitwise_xor()
      if set_union
        left = Tungsten:AST:Call.new(left, "union", [right])
      else
        left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_bitwise_xor
    parse_bitwise_xor_from(parse_bitwise_and())

  -> parse_bitwise_xor_from(left)
    # Dot-prefix: `.^` shares bitwise-xor precedence with `^`.
    while @current_type in (TOK_CARET T_DOT_CARET)
      op = advance_op_sym()
      right = parse_bitwise_and()
      left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_bitwise_and
    parse_bitwise_and_from(parse_addition())

  -> parse_bitwise_and_from(left)
    # Dot-prefix: `.&` shares bitwise-and precedence with `&`.
    while @current_type in (TOK_AMPERSAND T_DOT_AMP TOK_INTERSECTION)
      set_intersection = @current_type == TOK_INTERSECTION
      op = advance_op_sym()
      right = parse_addition()
      if set_intersection
        left = Tungsten:AST:Call.new(left, "intersect", [right])
      else
        left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_comparison
    left = parse_unary()
    t = @current_type
    if t < 80 || t == TOK_ASSIGN || t == TOK_CONSTANT
      return left
    parse_comparison_from(parse_equality_from(parse_bitwise_or_from(parse_bitwise_xor_from(parse_bitwise_and_from(parse_addition_from(parse_shift_from(parse_multiplication_from(parse_power_from(left)))))))))

  -> parse_comparison_from(left)
    if !(@current_type in (TOK_LT TOK_LTE TOK_GT TOK_GTE TOK_SPACESHIP TOK_MEMBER T_NOT_MEMBER TOK_SUBSET))
      return left
    chain = []
    while @current_type in (TOK_LT TOK_LTE TOK_GT TOK_GTE TOK_SPACESHIP TOK_MEMBER T_NOT_MEMBER TOK_SUBSET)
      token_type = @current_type
      hidden = "__comparison#" + current_line().to_s() + "_" + current_col().to_s()
      op = advance_op_sym()
      right = parse_equality()
      if token_type == TOK_SPACESHIP
        left = Tungsten:AST:Call.new(left, "<=>", [right])
      else
        continues = @current_type in (TOK_LT TOK_LTE TOK_GT TOK_GTE TOK_MEMBER T_NOT_MEMBER TOK_SUBSET)
        saved = right
        if continues
          saved = Tungsten:AST:Assign.new(Tungsten:AST:Var.new(hidden), right)
        comparison = comparison_node(left, token_type, op, saved, hidden)
        if continues
          chain.push(comparison)
          left = Tungsten:AST:Var.new(hidden)
        else
          # Nest the remaining comparisons on the RHS so every saved
          # operand dominates its uses in the generated control flow.
          left = comparison
          i = chain.size() - 1
          while i >= 0
            left = Tungsten:AST:And.new(chain[i], left)
            i -= 1
          chain = []
    left

  -> comparison_node(left, token_type, op, right, hidden)
    if token_type == TOK_MEMBER || token_type == T_NOT_MEMBER
      # Membership sends to the RHS collection, but operand evaluation
      # remains left-to-right. Internal names cannot occur in source.
      name = hidden + "_element"
      save = Tungsten:AST:Assign.new(Tungsten:AST:Var.new(name), left)
      test = Tungsten:AST:Call.new(right, "include?", [Tungsten:AST:Var.new(name)])
      if token_type == T_NOT_MEMBER
        test = Tungsten:AST:Not.new(test)
      return Tungsten:AST:Begin.new([save, test])
    if token_type == TOK_SUBSET
      return Tungsten:AST:Call.new(left, "subset?", [right])
    Tungsten:AST:BinaryOp.new(left, op, right)

  -> parse_equality
    parse_equality_from(parse_bitwise_or())

  -> parse_equality_from(left)
    while @current_type in (TOK_EQ TOK_TRIPLE_EQ TOK_NEQ TOK_MATCH TOK_NMATCH TOK_APPROX)
      op = advance_op_sym()
      right = parse_bitwise_or()
      left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_addition
    parse_addition_from(parse_shift())

  -> parse_addition_from(left)
    # Dot-prefix elementwise: `.+ .-` share addition precedence
    # with their scalar counterparts. Julia convention.
    if !(@current_type in (TOK_PLUS TOK_MINUS T_DOT_PLUS T_DOT_MINUS TOK_PLUS_MINUS))
      return left
    # If left is a block-introducing statement (while/if/loop/etc),
    # don't continue with binary ops. The block's value (typically nil)
    # shouldn't combine with a following `-N` on the next line —
    # `while ...; -1` would parse as `(while ...) - 1` → nil-1.
    if is_block_node?(left)
      return left
    while @current_type in (TOK_PLUS TOK_MINUS T_DOT_PLUS T_DOT_MINUS TOK_PLUS_MINUS)
      measurement = @current_type == TOK_PLUS_MINUS
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
    parse_shift_from(parse_multiplication())

  -> parse_shift_from(left)
    # Dot-prefix: `.<<` `.>>` share shift precedence.
    while @current_type in (TOK_LSHIFT TOK_RSHIFT T_DOT_LSHIFT T_DOT_RSHIFT)
      op = advance_op_sym()
      right = parse_multiplication()
      left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_multiplication
    parse_multiplication_from(parse_power())

  -> parse_multiplication_from(left)
    # Dot-prefix elementwise: `.* ./` share multiplication
    # precedence with their scalar counterparts.
    while @current_type in (TOK_STAR TOK_SLASH TOK_PERCENT T_DOT_STAR T_DOT_SLASH T_DOT_PRODUCT TOK_CROSS_PRODUCT TOK_HADAMARD TOK_KRONECKER)
      op = advance_op_sym()
      right = parse_power()
      left = Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_power
    parse_power_from(parse_unary())

  -> parse_power_from(left)
    t = @current_type
    if t == TOK_EXPONENT
      # Superscript exponent: `x⁷` ⇒ `x ** 7`. The EXPONENT token carries
      # the decoded digit string; build the same BinaryOp a written `**`
      # would, so the rest of the compiler is none the wiser.
      exp_raw = current_value()
      advance()
      exp_lit = Tungsten:AST:Int.new(parse_int_value(exp_raw), nil, exp_raw)
      return Tungsten:AST:BinaryOp.new(left, :POW, exp_lit)
    if t == TOK_TETRATE
      advance()
      right = parse_power()
      return Tungsten:AST:Call.new(left, "tetrate", [right])
    if t == TOK_POW
      op = advance_op_sym()
      right = parse_power()
      return Tungsten:AST:BinaryOp.new(left, op, right)
    left

  -> parse_unary
    t = @current_type
    if t == TOK_BANG
      advance()
      operand = parse_unary()
      return Tungsten:AST:Not.new(operand)
    if t == TOK_MINUS
      advance()
      operand = parse_unary()
      return Tungsten:AST:UnaryOp.new(:MINUS, operand)
    if t == TOK_STAR
      advance()
      operand = parse_unary()
      return Tungsten:AST:UnaryOp.new(:DEREF, operand)
    if t == TOK_SQRT
      # `√expr` ⇒ `expr.sqrt`. The operand parses at power precedence so
      # `√x²` reads as `√(x²)`, matching the math convention.
      advance()
      operand = parse_power()
      return Tungsten:AST:Call.new(operand, "sqrt", [], nil)
    parse_call_chain()
