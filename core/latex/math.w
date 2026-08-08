# LatexMath — typed semantic mathematics with deterministic LaTeX lowering.
#
# The vocabulary is deliberately closed. Semantic nodes cannot contain raw TeX
# or caller-defined operations; existing Core values remain independent of this
# module and may opt in through `LaTeX.semantic`.

+ LatexMath
  -> new(concept, children = nil, value = nil, sort = nil)
    @concept = concept.to_s
    @children = []
    if children != nil
      raise "LatexMath children must be an Array" if children.class_name != "Array"
      children.each -> (child)
        if child.class_name != "LatexMath"
          raise "LatexMath children must be semantic math values"
        @children.push(child)
    @value = value
    @sort = sort
    validate!

  -> .sort?(value)
    [:scalar, :set, :matrix, :proposition].include?(value)

  -> .leaf_sort?(value)
    [:scalar, :set, :matrix].include?(value)

  -> .require_leaf_sort(value)
    if !LatexMath.leaf_sort?(value)
      raise "LatexMath symbol sort must be scalar, set, or matrix: " + value.to_s
    value

  -> .require_math(value, operation)
    if value.class_name != "LatexMath"
      raise "LatexMath " + operation + " needs semantic math values"
    value

  -> .require_sort(value, sort, operation)
    child = LatexMath.require_math(value, operation)
    if child.sort != sort
      message = "LatexMath " + operation + " needs " + sort.to_s
      raise message + ", got " + child.sort.to_s
    child

  -> .copy_math_array(values, operation, minimum = 2)
    raise "LatexMath " + operation + " needs an Array" if values.class_name != "Array"
    if values.size < minimum
      raise "LatexMath " + operation + " needs at least " + minimum.to_s + " values"
    out = []
    values.each -> (value)
      out.push(LatexMath.require_sort(value, :scalar, operation))
    out

  -> .number(value)
    if !LaTeX.scalar?(value)
      raise "LatexMath.number needs a supported Core scalar, got " + value.class_name
    LatexMath.new("number", [], value, :scalar)

  -> .named_constant(name)
    text = name.to_s
    concept = nil
    concept = "pi" if text == "pi"
    concept = "e" if text == "e"
    concept = "euler-gamma" if text == "euler_gamma" || text == "euler-gamma"
    raise "unknown LatexMath named constant: " + text if concept == nil
    LatexMath.new(concept, [], nil, :scalar)

  -> .symbol(name, sort = :scalar)
    text = name.to_s
    raise "LatexMath symbol name cannot be empty" if text.empty?
    LatexMath.new("identifier", [], text, LatexMath.require_leaf_sort(sort))

  -> .sum(terms)
    LatexMath.new("plus", LatexMath.copy_math_array(terms, "sum"), nil, :scalar)

  -> .product(factors)
    children = LatexMath.copy_math_array(factors, "product")
    LatexMath.new("times", children, nil, :scalar)

  -> .quotient(numerator, denominator)
    top = LatexMath.require_sort(numerator, :scalar, "quotient")
    bottom = LatexMath.require_sort(denominator, :scalar, "quotient")
    LatexMath.new("quotient", [top, bottom], nil, :scalar)

  -> .power(base, exponent)
    left = LatexMath.require_sort(base, :scalar, "power")
    right = LatexMath.require_sort(exponent, :scalar, "power")
    LatexMath.new("power", [left, right], nil, :scalar)

  -> .square_root(value)
    child = LatexMath.require_sort(value, :scalar, "square root")
    LatexMath.new("square-root", [child], nil, :scalar)

  -> .absolute_value(value)
    child = LatexMath.require_sort(value, :scalar, "absolute value")
    LatexMath.new("absolute-value", [child], nil, :scalar)

  -> .determinant(value)
    child = LatexMath.require_sort(value, :matrix, "determinant")
    LatexMath.new("determinant", [child], nil, :scalar)

  -> .cartesian_product(left, right)
    first = LatexMath.require_sort(left, :set, "Cartesian product")
    second = LatexMath.require_sort(right, :set, "Cartesian product")
    LatexMath.new("cartesian-product", [first, second], nil, :set)

  -> .matrix_product(left, right)
    first = LatexMath.require_sort(left, :matrix, "matrix product")
    second = LatexMath.require_sort(right, :matrix, "matrix product")
    LatexMath.new("matrix-product", [first, second], nil, :matrix)

  -> .equals(left, right)
    first = LatexMath.require_math(left, "equality")
    second = LatexMath.require_math(right, "equality")
    if first.sort == :proposition || second.sort == :proposition
      raise "LatexMath equality operands cannot be propositions"
    if first.sort != second.sort
      message = "LatexMath equality sort mismatch: " + first.sort.to_s
      raise message + " versus " + second.sort.to_s
    LatexMath.new("equals", [first, second], nil, :proposition)

  -> .require_expression_arity(operation, arguments, expected)
    if arguments.size != expected
      message = "semantic Expression " + operation + " needs " + expected.to_s
      raise message + " arguments, got " + arguments.size.to_s
    true

  -> .from_expression(expression)
    arguments = expression.arguments
    if expression.constant?
      LatexMath.require_expression_arity("constant", arguments, 1)
      return LatexMath.number(expression.constant_value)
    if expression.variable?
      LatexMath.require_expression_arity("variable", arguments, 1)
      return LatexMath.symbol(expression.variable_text)
    if expression.named_constant?
      LatexMath.require_expression_arity("named_constant", arguments, 1)
      return LatexMath.named_constant(expression.named_constant_name)

    operation = expression.operation
    supported = ["add", "multiply", "divide", "power", "sqrt", "abs"]
    if !supported.include?(operation)
      raise "unsupported semantic Expression operation: " + operation
    LatexMath.require_expression_arity(operation, arguments, 2) if operation == "divide"
    LatexMath.require_expression_arity(operation, arguments, 2) if operation == "power"
    LatexMath.require_expression_arity(operation, arguments, 1) if operation == "sqrt"
    LatexMath.require_expression_arity(operation, arguments, 1) if operation == "abs"
    converted = []
    arguments.each -> (argument)
      converted.push(LatexMath.from(argument))
    return LatexMath.sum(converted) if operation == "add"
    return LatexMath.product(converted) if operation == "multiply"
    return LatexMath.quotient(converted[0], converted[1]) if operation == "divide"
    return LatexMath.power(converted[0], converted[1]) if operation == "power"
    return LatexMath.square_root(converted[0]) if operation == "sqrt"
    return LatexMath.absolute_value(converted[0]) if operation == "abs"
    raise "unsupported semantic Expression operation: " + operation

  -> .from(value)
    return value if value.class_name == "LatexMath"
    return LatexMath.number(value) if LaTeX.scalar?(value)
    return LatexMath.symbol(value) if value.class_name == "Symbol"
    return LatexMath.from_expression(value) if value.class_name == "Expression"
    raise "cannot convert " + value.class_name + " to LatexMath"

  -> validate_arity(expected)
    if @children.size != expected
      raise "LatexMath " + @concept + " needs " + expected.to_s + " children"
    true

  -> validate_scalar_children
    @children.each -> (child)
      if child.sort != :scalar
        raise "LatexMath " + @concept + " needs scalar children"
    true

  -> validate!
    if !LatexMath.sort?(@sort)
      raise "unknown LatexMath sort: " + @sort.to_s
    if @concept != "number" && @concept != "identifier" && @value != nil
      raise "LatexMath " + @concept + " cannot carry a hidden payload"
    if @concept == "number"
      validate_arity(0)
      raise "LatexMath number sort must be scalar" if @sort != :scalar
      raise "LatexMath number value is unsupported" if !LaTeX.scalar?(@value)
      return true
    if @concept == "identifier"
      validate_arity(0)
      LatexMath.require_leaf_sort(@sort)
      raise "LatexMath identifier payload must be a String" if @value.class_name != "String"
      raise "LatexMath symbol name cannot be empty" if @value.empty?
      return true
    if ["pi", "e", "euler-gamma"].include?(@concept)
      validate_arity(0)
      raise "LatexMath named constants are scalar" if @sort != :scalar
      return true
    if @concept == "plus" || @concept == "times"
      raise "LatexMath " + @concept + " needs at least two children" if @children.size < 2
      validate_scalar_children
      raise "LatexMath " + @concept + " result must be scalar" if @sort != :scalar
      return true
    if @concept == "quotient" || @concept == "power"
      validate_arity(2)
      validate_scalar_children
      raise "LatexMath " + @concept + " result must be scalar" if @sort != :scalar
      return true
    if ["square-root", "absolute-value"].include?(@concept)
      validate_arity(1)
      validate_scalar_children
      raise "LatexMath " + @concept + " result must be scalar" if @sort != :scalar
      return true
    if @concept == "determinant"
      validate_arity(1)
      raise "LatexMath determinant needs a matrix" if @children[0].sort != :matrix
      raise "LatexMath determinant result must be scalar" if @sort != :scalar
      return true
    if @concept == "cartesian-product"
      validate_arity(2)
      @children.each -> (child)
        raise "LatexMath Cartesian product needs sets" if child.sort != :set
      raise "LatexMath Cartesian product result must be a set" if @sort != :set
      return true
    if @concept == "matrix-product"
      validate_arity(2)
      @children.each -> (child)
        raise "LatexMath matrix product needs matrices" if child.sort != :matrix
      raise "LatexMath matrix product result must be a matrix" if @sort != :matrix
      return true
    if @concept == "equals"
      validate_arity(2)
      left_sort = @children[0].sort
      right_sort = @children[1].sort
      if left_sort == :proposition || left_sort != right_sort
        raise "LatexMath equality needs matching non-proposition sorts"
      raise "LatexMath equality result must be a proposition" if @sort != :proposition
      return true
    raise "unknown LatexMath concept: " + @concept

  -> concept
    @concept

  -> sort
    @sort

  -> children
    out = []
    @children.each -> (child)
      out.push(child)
    out

  -> number_value
    raise "LatexMath value is not a number" if @concept != "number"
    @value

  -> symbol_name
    raise "LatexMath value is not an identifier" if @concept != "identifier"
    @value

  -> precedence
    return 5 if @concept == "equals"
    return 10 if @concept == "plus"
    if ["times", "quotient", "cartesian-product", "matrix-product"].include?(@concept)
      return 20
    return 30 if @concept == "power"
    return 40 if ["square-root", "absolute-value", "determinant"].include?(@concept)
    100

  -> negative_one_number?
    @concept == "number" && @value == -1

  -> render_sum
    source = ""
    i = 0
    while i < @children.size
      part = @children[i].render_at(precedence).source
      if i == 0
        source += part
      elsif part.starts_with?("-")
        source += " - " + LaTeX.slice_text(part, 1, part.size - 1)
      else
        source += " + " + part
      i += 1
    LaTeX.raw(source)

  -> render_product
    start = 0
    prefix = ""
    if @children.size > 1 && @children[0].negative_one_number?
      prefix = "-"
      start = 1
    parts = []
    i = start
    while i < @children.size
      factor = @children[i].render_at(precedence)
      if (i > start || !prefix.empty?) && factor.source.starts_with?("-")
        factor = LaTeX.parenthesize(factor)
      parts.push(factor.source)
      i += 1
    LaTeX.raw(prefix + parts.join("\\,"))

  -> render_at(parent_precedence)
    result = nil
    if @concept == "number"
      result = LaTeX.number(@value)
    elsif @concept == "identifier"
      result = LaTeX.symbol(@value)
    elsif @concept == "pi"
      result = LaTeX.raw("\\pi")
    elsif @concept == "e"
      result = LaTeX.raw("\\mathrm{e}")
    elsif @concept == "euler-gamma"
      result = LaTeX.raw("\\gamma")
    elsif @concept == "plus"
      result = render_sum
    elsif @concept == "times"
      result = render_product
    elsif @concept == "quotient"
      result = LaTeX.fraction(
        @children[0].render_at(0), @children[1].render_at(0))
    elsif @concept == "power"
      base = @children[0].render_at(precedence + 1)
      base = LaTeX.parenthesize(base) if base.source.starts_with?("-")
      result = LaTeX.superscript(base, @children[1].render_at(0))
    elsif @concept == "square-root"
      result = LaTeX.sqrt(@children[0].render_at(0))
    elsif @concept == "absolute-value" || @concept == "determinant"
      result = LaTeX.absolute(@children[0].render_at(0))
    elsif @concept == "cartesian-product"
      source = @children[0].render_at(precedence + 1).source + " \\times "
      source += @children[1].render_at(precedence + 1).source
      result = LaTeX.raw(source)
    elsif @concept == "matrix-product"
      source = @children[0].render_at(precedence).source + " \\times "
      source += @children[1].render_at(precedence).source
      result = LaTeX.raw(source)
    elsif @concept == "equals"
      source = @children[0].render_at(precedence).source + " = "
      source += @children[1].render_at(precedence).source
      result = LaTeX.raw(source)
    else
      raise "unknown LatexMath concept: " + @concept
    if precedence < parent_precedence
      return LaTeX.parenthesize(result)
    result

  -> to_latex
    render_at(0)

  -> to_s
    to_latex.source

  -> inspect
    "LatexMath(" + @concept + ": " + to_s + ")"
