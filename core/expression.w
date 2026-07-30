# Expression — canonical symbolic real expressions.
#
# Expressions are immutable-by-convention trees built through simplifying
# factories. They support exact arithmetic constants, elementary
# transcendental functions, substitution, numerical/active-value evaluation,
# symbolic differentiation and elementary integration, polynomial-shaped
# manipulation, and conversion to exact polynomial rings.
#
#   x, y = Expression.variables([:x, :y])
#   f = (x**2 + y**2).sqrt + (x * y).sin
#   f.derivative(:x)
#   f.evaluate({x: ~3.0, y: ~4.0})
#
# `use calculus` exposes the shorter `Calculus.symbol` / `.symbols` facade.

use core/math
use core/special

+ Expression
  -> new(operation, arguments)
    @operation = operation.to_s
    @arguments = []
    arguments.each -> (argument)
      @arguments.push(argument)

  -> operation
    @operation

  -> arguments
    out = []
    @arguments.each -> (argument)
      out.push(argument)
    out

  -> .node(operation, arguments)
    Expression.new(operation, arguments)

  -> .wrap(value)
    return value if value.class_name == "Expression"
    Expression.constant(value)

  -> .constant(value)
    return value if value.class_name == "Expression"
    if value.class_name == "Rational" && value.denominator == 1
      value = value.numerator
    Expression.node("constant", [value])

  -> .named_constant(name)
    text = name.to_s
    if text != "pi" && text != "e"
      raise "unknown symbolic named constant: " + text
    Expression.node("named_constant", [text])

  -> .pi
    Expression.named_constant(:pi)

  -> .e
    Expression.named_constant(:e)

  -> .variable(name)
    text = name.to_s
    raise "expression variable name cannot be empty" if text.empty?
    Expression.node("variable", [text])

  -> .variables(names)
    raise "expression variable names must be an Array" if names.class_name != "Array"
    out = []
    names.each -> (name)
      out.push(Expression.variable(name))
    out

  -> constant?
    @operation == "constant"

  -> variable?
    @operation == "variable"

  -> named_constant?
    @operation == "named_constant"

  -> constant_value
    raise "expression is not constant" if !constant?
    @arguments[0]

  -> name
    raise "expression is not a variable" if !variable?
    @arguments[0].to_sym

  -> variable_text
    raise "expression is not a variable" if !variable?
    @arguments[0]

  -> named_constant_name
    raise "expression is not a named constant" if !named_constant?
    @arguments[0].to_sym

  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .zero_value?(value)
    return value.zero? if value.respond_to?("zero?")
    value == 0

  -> .one_value?(value)
    return value.one? if value.respond_to?("one?")
    value == 1

  -> .negative_one_value?(value)
    value == -1

  -> .scalar_value?(value)
    name = value.class_name
    scalar_names = [
      "Integer", "Int", "BigInt",
      "Float", "Float16", "Float32", "Float64", "Float80", "Float128",
      "Float256", "Rational",
      "Decimal", "Decimal32", "Decimal64", "Decimal128",
      "AlgebraicRealRoot"
    ]
    scalar_names.include?(name)

  -> .exact_value?(value)
    exact = Expression.integer?(value) || value.class_name == "Rational"
    exact || value.class_name == "AlgebraicRealRoot"

  -> .rational_exact_value?(value)
    Expression.integer?(value) || value.class_name == "Rational"

  -> .add_constant_values(left, right)
    algebraic = left.class_name == "AlgebraicRealRoot"
    algebraic = algebraic || right.class_name == "AlgebraicRealRoot"
    if algebraic
      return AlgebraicRealArithmetic.value(left, right, "+")
    left + right

  -> .multiply_constant_values(left, right)
    algebraic = left.class_name == "AlgebraicRealRoot"
    algebraic = algebraic || right.class_name == "AlgebraicRealRoot"
    if algebraic
      return AlgebraicRealArithmetic.value(left, right, "*")
    left * right

  -> .perfect_square_root(value)
    if Expression.integer?(value)
      return nil if value < 0
      root = value.isqrt
      return root if root * root == value
      return nil
    if value.class_name == "Rational"
      return nil if value.negative?
      numerator_root = value.numerator.isqrt
      denominator_root = value.denominator.isqrt
      if numerator_root * numerator_root == value.numerator
        if denominator_root * denominator_root == value.denominator
          return Rational.new(numerator_root, denominator_root)
      return nil
    nil

  -> .integer_cube_root(value)
    negative = value < 0
    magnitude = negative ? 0 - value : value
    low = 0
    high = magnitude
    root = 0
    while low <= high
      middle = (low + high) / 2
      cube = middle * middle * middle
      if cube <= magnitude
        root = middle
        low = middle + 1
      else
        high = middle - 1
    negative ? 0 - root : root

  -> .perfect_cube_root(value)
    if Expression.integer?(value)
      root = Expression.integer_cube_root(value)
      return root if root * root * root == value
      return nil
    if value.class_name == "Rational"
      numerator_root = Expression.integer_cube_root(value.numerator)
      denominator_root = Expression.integer_cube_root(value.denominator)
      if numerator_root * numerator_root * numerator_root == value.numerator
        if denominator_root * denominator_root * denominator_root == value.denominator
          return Rational.new(numerator_root, denominator_root)
      return nil
    nil

  -> .integer_square_decomposition(value)
    outside = 1
    inside = 1
    value.factor.each -> (prime_power)
      outside = outside * prime_power.prime ** (prime_power.exponent / 2)
      if prime_power.exponent.odd?
        inside = inside * prime_power.prime
    [outside, inside]

  -> .square_decomposition(value)
    if Expression.integer?(value)
      return nil if value <= 0
      return nil if value.bit_length > 32
      return Expression.integer_square_decomposition(value)
    if value.class_name == "Rational"
      return nil if value.numerator <= 0
      return nil if value.numerator.bit_length > 32
      return nil if value.denominator.bit_length > 32
      top = Expression.integer_square_decomposition(value.numerator)
      bottom = Expression.integer_square_decomposition(value.denominator)
      return [
        Rational.new(top[0], bottom[0]),
        Rational.new(top[1], bottom[1])
      ]
    nil

  -> .integer_cube_decomposition(value)
    sign = value < 0 ? -1 : 1
    magnitude = value < 0 ? 0 - value : value
    outside = sign
    inside = 1
    magnitude.factor.each -> (prime_power)
      outside = outside * prime_power.prime ** (prime_power.exponent / 3)
      remainder = prime_power.exponent % 3
      inside = inside * prime_power.prime ** remainder if remainder > 0
    [outside, inside]

  -> .cube_decomposition(value)
    if Expression.integer?(value)
      return nil if value == 0
      magnitude = value < 0 ? 0 - value : value
      return nil if magnitude.bit_length > 32
      return Expression.integer_cube_decomposition(value)
    if value.class_name == "Rational"
      return nil if value.zero?
      magnitude = value.numerator < 0 ? 0 - value.numerator : value.numerator
      return nil if magnitude.bit_length > 32
      return nil if value.denominator.bit_length > 32
      top = Expression.integer_cube_decomposition(value.numerator)
      bottom = Expression.integer_cube_decomposition(value.denominator)
      return [
        Rational.new(top[0], bottom[0]),
        Rational.new(top[1], bottom[1])
      ]
    nil

  -> .sort_expressions(values)
    out = []
    values.each -> (value)
      out.push(value)
    i = 1
    while i < out.size
      j = i
      while j > 0 && out[j].sort_key < out[j - 1].sort_key
        temporary = out[j - 1]
        out[j - 1] = out[j]
        out[j] = temporary
        j -= 1
      i += 1
    out

  -> sort_key
    self.to_s

  # Return [coefficient, symbolic base] for additive like-term collection.
  -> .coefficient_and_base(term)
    if term.operation == "multiply"
      factors = term.arguments
      if factors.size > 1 && factors[0].constant?
        coefficient = factors[0].constant_value
        rest = factors.copy(1, factors.size - 1)
        base = rest.size == 1 ? rest[0] : Expression.product(rest)
        return [coefficient, base]
    [1, term]

  # Recognize unary_function(argument)^2 without making assumptions about the
  # argument. This is enough to apply the globally valid circular and
  # hyperbolic Pythagorean identities during additive normalization.
  -> .unary_square_argument(base, operation)
    return nil if base.operation != "power"
    pieces = base.arguments
    return nil if !pieces[1].constant?
    return nil if pieces[1].constant_value != 2
    unary = pieces[0]
    return nil if unary.operation != operation
    unary.arguments[0]

  # Remove matched c*sin(x)^2 + c*cos(x)^2 and
  # c*cosh(x)^2 - c*sinh(x)^2 groups, returning the updated constant state.
  -> .collapse_squared_identities(groups, constant_seen, constant_total)
    i = 0
    while i < groups.size
      base = groups[i][0]
      argument = Expression.unary_square_argument(base, "sin")
      target_operation = "cos"
      opposite_coefficient = false
      if argument == nil
        argument = Expression.unary_square_argument(base, "cosh")
        target_operation = "sinh"
        opposite_coefficient = true

      if argument != nil
        j = 0
        while j < groups.size
          if j != i
            other_argument = Expression.unary_square_argument(
              groups[j][0], target_operation)
            expected = groups[i][1]
            expected = 0 - expected if opposite_coefficient
            if other_argument == argument && groups[j][1] == expected
              contribution = groups[i][1]
              groups[i][1] = 0
              groups[j][1] = 0
              if constant_seen
                constant_total = Expression.add_constant_values(
                  constant_total, contribution)
              else
                constant_total = contribution
                constant_seen = true
              break
          j += 1
      i += 1
    [constant_seen, constant_total]

  # Canonical n-ary sum. Constants are combined exactly and like terms with
  # identical canonical bases have their coefficients collected.
  -> .sum(values)
    flattened = []
    constant_seen = false
    constant_total = nil
    values.each -> (source)
      expression = Expression.wrap(source)
      pieces = expression.operation == "add" ? expression.arguments : [expression]
      pieces.each -> (piece)
        if piece.constant?
          value = piece.constant_value
          if constant_seen
            constant_total = Expression.add_constant_values(
              constant_total, value)
          else
            constant_total = value
            constant_seen = true
        else
          flattened.push(piece)

    groups = []
    flattened.each -> (term)
      pair = Expression.coefficient_and_base(term)
      coefficient = pair[0]
      base = pair[1]
      found = -1
      i = 0
      while i < groups.size
        if groups[i][0] == base
          found = i
          break
        i += 1
      if found >= 0
        groups[found][1] = Expression.add_constant_values(
          groups[found][1], coefficient)
      else
        groups.push([base, coefficient])

    identity_state = Expression.collapse_squared_identities(
      groups, constant_seen, constant_total)
    constant_seen = identity_state[0]
    constant_total = identity_state[1]

    terms = []
    groups.each -> (group)
      coefficient = group[1]
      if !Expression.zero_value?(coefficient)
        if Expression.one_value?(coefficient)
          terms.push(group[0])
        else
          terms.push(Expression.product([
            Expression.constant(coefficient),
            group[0]
          ]))

    terms = Expression.sort_expressions(terms)
    if constant_seen && !Expression.zero_value?(constant_total)
      terms.push(Expression.constant(constant_total))
    return Expression.constant(0) if terms.size == 0
    return terms[0] if terms.size == 1
    Expression.node("add", terms)

  -> .add(left, right)
    Expression.sum([left, right])

  -> .subtract(left, right)
    Expression.sum([left, Expression.negate(right)])

  -> .negate(value)
    expression = Expression.wrap(value)
    if expression.constant?
      constant = expression.constant_value
      if constant.class_name == "AlgebraicRealRoot"
        return Expression.constant(constant.negate)
      return Expression.constant(0 - constant)
    Expression.product([Expression.constant(-1), expression])

  # Return [base, positive integral multiplicity] for multiplicative
  # collection. Non-integral powers remain indivisible factors.
  -> .base_and_power(factor)
    if factor.operation == "power"
      pieces = factor.arguments
      if pieces[1].constant?
        exponent = pieces[1].constant_value
        if Expression.integer?(exponent) && exponent > 0
          return [pieces[0], exponent]
    [factor, 1]

  # Canonical n-ary product. Constants are combined and repeated factors are
  # collected into integral powers.
  -> .product(values)
    flattened = []
    constant_seen = false
    constant_total = nil
    zero_factor = false
    values.each -> (source)
      expression = Expression.wrap(source)
      pieces = expression.operation == "multiply" ? expression.arguments : [expression]
      pieces.each -> (piece)
        if piece.constant?
          value = piece.constant_value
          if Expression.zero_value?(value)
            zero_factor = true
          else
            if constant_seen
              constant_total = Expression.multiply_constant_values(
                constant_total, value)
            else
              constant_total = value
              constant_seen = true
        else
          flattened.push(piece)
    return Expression.constant(0) if zero_factor

    # Cancel an explicit denominator against an identical product factor.
    # This matches the existing x/x simplification and keeps rational
    # transcendental coefficients canonical (for example log(2)/log(2)).
    cancellation_left = 0
    while cancellation_left < flattened.size
      factor = flattened[cancellation_left]
      if factor.operation == "divide"
        pieces = factor.arguments
        cancellation_right = 0
        while cancellation_right < flattened.size
          if cancellation_right != cancellation_left
            if flattened[cancellation_right] == pieces[1]
              rewritten = []
              if constant_seen
                rewritten.push(Expression.constant(constant_total))
              i = 0
              while i < flattened.size
                if i != cancellation_left && i != cancellation_right
                  rewritten.push(flattened[i])
                i += 1
              rewritten.push(pieces[0])
              return Expression.product(rewritten)
          cancellation_right += 1
      cancellation_left += 1

    groups = []
    flattened.each -> (factor)
      pair = Expression.base_and_power(factor)
      base = pair[0]
      exponent = pair[1]
      found = -1
      i = 0
      while i < groups.size
        if groups[i][0] == base
          found = i
          break
        i += 1
      if found >= 0
        groups[found][1] = groups[found][1] + exponent
      else
        groups.push([base, exponent])

    factors = []
    groups.each -> (group)
      if group[1] == 1
        factors.push(group[0])
      else
        factors.push(Expression.power(group[0], Expression.constant(group[1])))
    factors = Expression.sort_expressions(factors)

    if constant_seen
      return Expression.constant(constant_total) if factors.size == 0
      if factors.size == 1 && factors[0].operation == "divide"
        quotient = factors[0].arguments
        if quotient[0].constant?
          combined = constant_total * quotient[0].constant_value
          return Expression.divide(
            Expression.constant(combined), quotient[1])
      if !Expression.one_value?(constant_total)
        factors = [Expression.constant(constant_total)] + factors
    return Expression.constant(1) if factors.size == 0
    return factors[0] if factors.size == 1
    Expression.node("multiply", factors)

  -> .multiply(left, right)
    Expression.product([left, right])

  -> .divide_constants(numerator, denominator)
    raise "symbolic division by zero" if Expression.zero_value?(denominator)
    algebraic = numerator.class_name == "AlgebraicRealRoot"
    algebraic = algebraic || denominator.class_name == "AlgebraicRealRoot"
    if algebraic
      return AlgebraicRealArithmetic.value(numerator, denominator, "/")
    if Expression.integer?(numerator) && Expression.integer?(denominator)
      return Rational.new(numerator, denominator)
    numerator / denominator

  -> .divide(numerator, denominator)
    left = Expression.wrap(numerator)
    right = Expression.wrap(denominator)
    if right.constant? && Expression.zero_value?(right.constant_value)
      raise "symbolic division by zero"
    return Expression.constant(0) if left.constant? && Expression.zero_value?(left.constant_value)
    return Expression.constant(1) if left == right
    return left if right.constant? && Expression.one_value?(right.constant_value)
    return Expression.negate(left) if right.constant? && Expression.negative_one_value?(right.constant_value)
    if left.operation == "multiply"
      numerator_factors = left.arguments
      i = 0
      while i < numerator_factors.size
        if numerator_factors[i] == right
          remaining = []
          j = 0
          while j < numerator_factors.size
            remaining.push(numerator_factors[j]) if j != i
            j += 1
          return Expression.product(remaining)
        i += 1
    if left.constant? && right.constant?
      return Expression.constant(
        Expression.divide_constants(left.constant_value, right.constant_value))
    if right.operation == "multiply"
      denominator_factors = right.arguments
      if denominator_factors.size > 1 && denominator_factors[0].constant?
        reciprocal = Expression.divide_constants(
          1, denominator_factors[0].constant_value)
        scaled_numerator = Expression.product([
          Expression.constant(reciprocal), left
        ])
        remaining = denominator_factors.copy(
          1, denominator_factors.size - 1)
        denominator_base = Expression.product(remaining)
        denominator_base = remaining[0] if remaining.size == 1
        return Expression.divide(scaled_numerator, denominator_base)
    if right.constant? && Expression.exact_value?(right.constant_value)
      reciprocal = Expression.divide_constants(1, right.constant_value)
      return Expression.product([Expression.constant(reciprocal), left])
    if right.constant? && left.operation == "multiply"
      pieces = left.arguments
      if pieces.size > 1 && pieces[0].constant?
        coefficient = Expression.divide_constants(
          pieces[0].constant_value, right.constant_value)
        return Expression.product(
          [Expression.constant(coefficient)] + pieces.copy(1, pieces.size - 1))
    if right.constant? && left.operation == "add"
      pieces = []
      left.arguments.each -> (argument)
        pieces.push(Expression.divide(argument, right))
      return Expression.sum(pieces)
    Expression.node("divide", [left, right])

  -> .power(base, exponent)
    left = Expression.wrap(base)
    right = Expression.wrap(exponent)
    if right.constant?
      value = right.constant_value
      return Expression.constant(1) if Expression.zero_value?(value)
      return left if Expression.one_value?(value)
      if left.constant?
        base_value = left.constant_value
        if Expression.integer?(base_value) && Expression.integer?(value) && value < 0
          denominator = base_value ** (0 - value)
          return Expression.constant(Rational.new(1, denominator))
        if !Expression.exact_value?(base_value) || Expression.integer?(value)
          return Expression.constant(base_value ** value)
        if value.class_name == "Rational" && value.denominator == 1
          return Expression.constant(base_value ** value.numerator)
      if left.operation == "power" && Expression.integer?(value)
        inner = left.arguments
        if inner[1].constant? && Expression.integer?(inner[1].constant_value)
          return Expression.power(
            inner[0],
            Expression.constant(inner[1].constant_value * value))
    if left.constant? && Expression.one_value?(left.constant_value)
      return Expression.constant(1)
    Expression.node("power", [left, right])

  -> .apply_unary(operation, value)
    if value.class_name == "AlgebraicRealRoot"
      return Expression.apply_unary(operation, value.to_f)
    if value.respond_to?(operation)
      return value.exp if operation == "exp"
      return value.log if operation == "log"
      return value.sqrt if operation == "sqrt"
      return value.sin if operation == "sin"
      return value.cos if operation == "cos"
      return value.tan if operation == "tan"
      return value.sinh if operation == "sinh"
      return value.cosh if operation == "cosh"
      return value.tanh if operation == "tanh"
      return value.asin if operation == "asin"
      return value.acos if operation == "acos"
      return value.atan if operation == "atan"
      return value.asinh if operation == "asinh"
      return value.acosh if operation == "acosh"
      return value.atanh if operation == "atanh"
      return value.expm1 if operation == "expm1"
      return value.log1p if operation == "log1p"
      return value.log2 if operation == "log2"
      return value.log10 if operation == "log10"
      return value.cbrt if operation == "cbrt"
      return value.abs if operation == "abs"
      return value.erf if operation == "erf"
      return value.erfc if operation == "erfc"
    return Math.exp(value) if operation == "exp"
    return Math.log(value) if operation == "log"
    return Math.sqrt(value) if operation == "sqrt"
    return Math.sin(value) if operation == "sin"
    return Math.cos(value) if operation == "cos"
    return Math.tan(value) if operation == "tan"
    return Math.sinh(value) if operation == "sinh"
    return Math.cosh(value) if operation == "cosh"
    return Math.tanh(value) if operation == "tanh"
    return Math.asin(value) if operation == "asin"
    return Math.acos(value) if operation == "acos"
    return Math.atan(value) if operation == "atan"
    return Math.asinh(value) if operation == "asinh"
    return Math.acosh(value) if operation == "acosh"
    return Math.atanh(value) if operation == "atanh"
    return Math.expm1(value) if operation == "expm1"
    return Math.log1p(value) if operation == "log1p"
    return Math.log2(value) if operation == "log2"
    return Math.log10(value) if operation == "log10"
    return Math.cbrt(value) if operation == "cbrt"
    return Math.abs(value) if operation == "abs"
    return Special.erf(value) if operation == "erf"
    return Special.erfc(value) if operation == "erfc"
    raise "unknown symbolic unary operation: " + operation

  -> .named_constant_value(name)
    return Math.acos(~-1.0) if name.to_s == "pi"
    return Math.exp(~1.0) if name.to_s == "e"
    raise "unknown symbolic named constant: " + name.to_s

  # Return [handled, exact expression]. Exact arguments never fall through to
  # libm merely because a simplifier happened to see them.
  -> .exact_unary(operation, value)
    zero = Expression.zero_value?(value)
    one = Expression.one_value?(value)
    negative_one = Expression.negative_one_value?(value)

    if zero
      if operation == "cos" || operation == "cosh" || operation == "exp"
        return [true, Expression.constant(1)]
      if operation == "acos"
        return [true, Expression.pi / Expression.constant(2)]
      zero_operations = [
        "sqrt", "sin", "tan", "sinh", "tanh", "asin", "atan", "asinh",
        "atanh", "expm1", "log1p", "cbrt", "abs", "erf"
      ]
      return [true, Expression.constant(0)] if zero_operations.include?(operation)
      return [true, Expression.constant(1)] if operation == "erfc"

    if one
      logarithm = operation == "log" || operation == "log2" || operation == "log10"
      return [true, Expression.constant(0)] if logarithm || operation == "acos" || operation == "acosh"
      return [true, Expression.e] if operation == "exp"
      return [true, Expression.pi / Expression.constant(2)] if operation == "asin"
      return [true, Expression.pi / Expression.constant(4)] if operation == "atan"
      identity = operation == "sqrt" || operation == "cbrt" || operation == "abs"
      return [true, Expression.constant(1)] if identity

    if negative_one
      return [true, Expression.constant(1)] if operation == "abs"
      return [true, Expression.constant(-1)] if operation == "cbrt"
      return [true, Expression.negate(Expression.pi / Expression.constant(2))] if operation == "asin"
      return [true, Expression.negate(Expression.pi / Expression.constant(4))] if operation == "atan"
      return [true, Expression.pi] if operation == "acos"

    half = Rational.new(1, 2)
    if value == half
      return [true, Expression.pi / Expression.constant(6)] if operation == "asin"
      return [true, Expression.pi / Expression.constant(3)] if operation == "acos"
    if value == 0 - half
      return [true, Expression.negate(Expression.pi / Expression.constant(6))] if operation == "asin"
      if operation == "acos"
        return [true, Expression.constant(2) * Expression.pi / Expression.constant(3)]

    if operation == "sqrt"
      root = Expression.perfect_square_root(value)
      return [true, Expression.constant(root)] if root != nil
      decomposition = Expression.square_decomposition(value)
      if decomposition != nil && !Expression.one_value?(decomposition[0])
        radical = Expression.node(
          "sqrt", [Expression.constant(decomposition[1])])
        return [true, Expression.constant(decomposition[0]) * radical]
    if operation == "cbrt"
      root = Expression.perfect_cube_root(value)
      return [true, Expression.constant(root)] if root != nil
      decomposition = Expression.cube_decomposition(value)
      if decomposition != nil && !Expression.one_value?(decomposition[0])
        radical = Expression.node(
          "cbrt", [Expression.constant(decomposition[1])])
        return [true, Expression.constant(decomposition[0]) * radical]
    return [true, Expression.constant(value.abs)] if operation == "abs"
    [false, nil]

  # Recognize exact rational multiples of pi in canonical multiply/divide
  # forms. This is intentionally small and sound; a future assumptions layer
  # can add general trigonometric reduction.
  -> .pi_multiple(expression)
    return Rational.new(1) if expression.named_constant? && expression.named_constant_name == :pi
    if expression.operation == "multiply"
      pieces = expression.arguments
      if pieces.size == 2 && pieces[0].constant?
        coefficient = pieces[0].constant_value
        if Expression.rational_exact_value?(coefficient)
          rest = Expression.pi_multiple(pieces[1])
          return Rational.coerce(coefficient) * rest if rest != nil
    if expression.operation == "divide"
      pieces = expression.arguments
      if pieces[1].constant? && Expression.rational_exact_value?(pieces[1].constant_value)
        numerator = Expression.pi_multiple(pieces[0])
        if numerator != nil
          return numerator / Rational.coerce(pieces[1].constant_value)
    nil

  -> .pi_twelfth_sine(residue)
    k = residue
    sign = 1
    if k > 12
      k -= 12
      sign = -1
    if k > 6
      k = 12 - k

    value = Expression.constant(0)
    sqrt_two = Expression.constant(2).sqrt
    sqrt_three = Expression.constant(3).sqrt
    sqrt_six = Expression.constant(6).sqrt
    value = (sqrt_six - sqrt_two) / Expression.constant(4) if k == 1
    value = Expression.constant(Rational.new(1, 2)) if k == 2
    value = sqrt_two / Expression.constant(2) if k == 3
    value = sqrt_three / Expression.constant(2) if k == 4
    value = (sqrt_six + sqrt_two) / Expression.constant(4) if k == 5
    value = Expression.constant(1) if k == 6
    sign < 0 ? Expression.negate(value) : value

  -> .pi_twelfth_tangent(residue)
    k = residue % 12
    return nil if k == 6
    sqrt_three = Expression.constant(3).sqrt
    two = Expression.constant(2)
    return Expression.constant(0) if k == 0
    return two - sqrt_three if k == 1
    return sqrt_three / Expression.constant(3) if k == 2
    return Expression.constant(1) if k == 3
    return sqrt_three if k == 4
    return two + sqrt_three if k == 5
    return Expression.negate(two + sqrt_three) if k == 7
    return Expression.negate(sqrt_three) if k == 8
    return Expression.constant(-1) if k == 9
    return Expression.negate(sqrt_three / Expression.constant(3)) if k == 10
    Expression.negate(two - sqrt_three)

  -> .trig_pi_value(operation, expression)
    coefficient = Expression.pi_multiple(expression)
    return [false, nil] if coefficient == nil
    denominator = coefficient.denominator
    scaled_numerator = coefficient.numerator * 12
    return [false, nil] if scaled_numerator % denominator != 0
    twelfths = scaled_numerator / denominator
    residue = twelfths % 24
    residue += 24 if residue < 0
    if operation == "sin"
      return [true, Expression.pi_twelfth_sine(residue)]
    if operation == "cos"
      cosine_residue = (residue + 6) % 24
      return [true, Expression.pi_twelfth_sine(cosine_residue)]
    if operation == "tan"
      tangent = Expression.pi_twelfth_tangent(residue)
      return [true, tangent] if tangent != nil
    [false, nil]

  # Return the positive counterpart of a syntactically negative exact
  # argument. No sign assumptions about variables are introduced.
  -> .positive_negative_argument(expression)
    if expression.constant?
      value = expression.constant_value
      if Expression.rational_exact_value?(value) && value < 0
        return Expression.constant(0 - value)
    if expression.operation == "multiply"
      pieces = expression.arguments
      if pieces.size > 1 && pieces[0].constant?
        coefficient = pieces[0].constant_value
        if Expression.rational_exact_value?(coefficient) && coefficient < 0
          return Expression.negate(expression)
    nil

  -> .unary(operation, argument)
    name = operation.to_s
    expression = Expression.wrap(argument)

    if expression.constant?
      value = expression.constant_value
      if Expression.exact_value?(value)
        exact = Expression.exact_unary(name, value)
        return exact[1] if exact[0]
      else
        return Expression.constant(Expression.apply_unary(name, value))

    if name == "log" && expression.operation == "exp"
      return expression.arguments[0]
    if name == "log" && expression.named_constant? && expression.named_constant_name == :e
      return Expression.constant(1)
    if name == "sin" || name == "cos" || name == "tan"
      exact_trig = Expression.trig_pi_value(name, expression)
      return exact_trig[1] if exact_trig[0]
    positive_argument = Expression.positive_negative_argument(expression)
    if positive_argument != nil
      odd_operations = [
        "sin", "tan", "sinh", "tanh", "asin", "atan", "asinh", "atanh",
        "cbrt", "erf"
      ]
      if odd_operations.include?(name)
        return Expression.negate(
          Expression.unary(name, positive_argument))
      even_operations = ["cos", "cosh", "abs"]
      if even_operations.include?(name)
        return Expression.unary(name, positive_argument)
      if name == "erfc"
        return Expression.subtract(
          Expression.constant(2), Expression.unary(name, positive_argument))
    if name == "abs" && expression.operation == "abs"
      return expression
    if name == "sqrt" && expression.operation == "power"
      pieces = expression.arguments
      if pieces[1].constant? && pieces[1].constant_value == 2
        return Expression.unary("abs", pieces[0])
    Expression.node(name, [expression])

  -> +(other)
    Expression.add(self, other)

  -> -(other)
    Expression.subtract(self, other)

  -> -@
    Expression.negate(self)

  -> *(other)
    Expression.multiply(self, other)

  -> /(other)
    Expression.divide(self, other)

  -> **(exponent)
    Expression.power(self, exponent)

  -> pow(exponent)
    Expression.power(self, exponent)

  -> exp
    Expression.unary("exp", self)

  -> log
    Expression.unary("log", self)

  -> sqrt
    Expression.unary("sqrt", self)

  -> sin
    Expression.unary("sin", self)

  -> cos
    Expression.unary("cos", self)

  -> tan
    Expression.unary("tan", self)

  -> sinh
    Expression.unary("sinh", self)

  -> cosh
    Expression.unary("cosh", self)

  -> tanh
    Expression.unary("tanh", self)

  -> asin
    Expression.unary("asin", self)

  -> acos
    Expression.unary("acos", self)

  -> atan
    Expression.unary("atan", self)

  -> asinh
    Expression.unary("asinh", self)

  -> acosh
    Expression.unary("acosh", self)

  -> atanh
    Expression.unary("atanh", self)

  -> expm1
    Expression.unary("expm1", self)

  -> log1p
    Expression.unary("log1p", self)

  -> log2
    Expression.unary("log2", self)

  -> log10
    Expression.unary("log10", self)

  -> cbrt
    Expression.unary("cbrt", self)

  -> abs
    Expression.unary("abs", self)

  -> erf
    Expression.unary("erf", self)

  -> erfc
    Expression.unary("erfc", self)

  -> ==/1
    other = @1
    return false if other.class_name != "Expression"
    return false if @operation != other.operation
    other_arguments = other.arguments
    return false if @arguments.size != other_arguments.size
    i = 0
    while i < @arguments.size
      return false if @arguments[i] != other_arguments[i]
      i += 1
    true

  -> !=/1
    !(self == @1)

  -> simplify
    return self if constant? || variable? || named_constant?
    simplified = []
    @arguments.each -> (argument)
      simplified.push(argument.simplify)
    return Expression.sum(simplified) if @operation == "add"
    return Expression.product(simplified) if @operation == "multiply"
    return Expression.divide(simplified[0], simplified[1]) if @operation == "divide"
    return Expression.power(simplified[0], simplified[1]) if @operation == "power"
    Expression.unary(@operation, simplified[0])

  -> derivative(variable)
    sought = variable.to_s
    return Expression.constant(0) if constant? || named_constant?
    if variable?
      return Expression.constant(@arguments[0] == sought ? 1 : 0)

    if @operation == "add"
      derivatives = []
      @arguments.each -> (argument)
        derivatives.push(argument.derivative(sought))
      return Expression.sum(derivatives)

    if @operation == "multiply"
      terms = []
      i = 0
      while i < @arguments.size
        factors = []
        j = 0
        while j < @arguments.size
          factors.push(j == i ? @arguments[j].derivative(sought) : @arguments[j])
          j += 1
        terms.push(Expression.product(factors))
        i += 1
      return Expression.sum(terms)

    if @operation == "divide"
      numerator = @arguments[0]
      denominator = @arguments[1]
      top = numerator.derivative(sought) * denominator
      top -= numerator * denominator.derivative(sought)
      return top / (denominator ** 2)

    if @operation == "power"
      base = @arguments[0]
      exponent = @arguments[1]
      if exponent.constant?
        value = exponent.constant_value
        factor = Expression.constant(value) * (base ** (value - 1))
        return factor * base.derivative(sought)
      logarithmic = exponent.derivative(sought) * base.log
      logarithmic += exponent * base.derivative(sought) / base
      return self * logarithmic

    argument = @arguments[0]
    derivative = argument.derivative(sought)
    return argument.exp * derivative if @operation == "exp"
    return derivative / argument if @operation == "log"
    return derivative / (Expression.constant(2) * argument.sqrt) if @operation == "sqrt"
    return argument.cos * derivative if @operation == "sin"
    return -argument.sin * derivative if @operation == "cos"
    return derivative / (argument.cos ** 2) if @operation == "tan"
    return argument.cosh * derivative if @operation == "sinh"
    return argument.sinh * derivative if @operation == "cosh"
    return derivative / (argument.cosh ** 2) if @operation == "tanh"
    return derivative / (Expression.constant(1) - argument**2).sqrt if @operation == "asin"
    return -derivative / (Expression.constant(1) - argument**2).sqrt if @operation == "acos"
    return derivative / (Expression.constant(1) + argument**2) if @operation == "atan"
    return derivative / (Expression.constant(1) + argument**2).sqrt if @operation == "asinh"
    return derivative / (argument**2 - Expression.constant(1)).sqrt if @operation == "acosh"
    return derivative / (Expression.constant(1) - argument**2) if @operation == "atanh"
    return argument.exp * derivative if @operation == "expm1"
    return derivative / (Expression.constant(1) + argument) if @operation == "log1p"
    return derivative / (Expression.constant(2).log * argument) if @operation == "log2"
    return derivative / (Expression.constant(10).log * argument) if @operation == "log10"
    return derivative / (Expression.constant(3) * argument.cbrt**2) if @operation == "cbrt"
    return argument * derivative / argument.abs if @operation == "abs"
    if @operation == "erf" || @operation == "erfc"
      scale = @operation == "erfc" ? -2 : 2
      return Expression.product([
        Expression.constant(scale),
        Expression.constant(1) / Expression.pi.sqrt,
        (-(argument**2)).exp,
        derivative
      ])
    raise "cannot differentiate symbolic operation: " + @operation

  -> diff(variable)
    derivative(variable)

  -> gradient(variables)
    out = []
    variables.each -> (variable)
      out.push(derivative(variable))
    out

  -> hessian(variables)
    out = []
    variables.each -> (left)
      row = []
      variables.each -> (right)
        row.push(derivative(left).derivative(right))
      out.push(row)
    out

  -> collect_variable_texts(out)
    if variable?
      out.push(@arguments[0]) if !out.include?(@arguments[0])
      return out
    if !constant? && !named_constant?
      @arguments.each -> (argument)
        argument.collect_variable_texts(out)
    out

  -> free_variables
    texts = Expression.sort_strings(collect_variable_texts([]))
    out = []
    texts.each -> (text)
      out.push(text.to_sym)
    out

  -> .sort_strings(values)
    out = []
    values.each -> (value)
      out.push(value)
    i = 1
    while i < out.size
      j = i
      while j > 0 && out[j] < out[j - 1]
        temporary = out[j - 1]
        out[j - 1] = out[j]
        out[j] = temporary
        j -= 1
      i += 1
    out

  -> depends_on?(variable)
    collect_variable_texts([]).include?(variable.to_s)

  -> substitute(bindings)
    raise "expression substitution needs a Hash" if bindings.class_name != "Hash"
    if constant? || named_constant?
      return self
    if variable?
      text = @arguments[0]
      return Expression.wrap(bindings[text]) if bindings.has_key?(text)
      symbol = text.to_sym
      return Expression.wrap(bindings[symbol]) if bindings.has_key?(symbol)
      return self
    replaced = []
    @arguments.each -> (argument)
      replaced.push(argument.substitute(bindings))
    Expression.node(@operation, replaced).simplify

  -> .active_value?(value)
    name = value.class_name
    [
      "TaylorJet", "Differential", "FormalPowerSeries", "Polynomial", "Complex"
    ].include?(name)

  -> .add_values(left, right)
    algebraic = left.class_name == "AlgebraicRealRoot"
    algebraic = algebraic || right.class_name == "AlgebraicRealRoot"
    if algebraic
      return AlgebraicRealArithmetic.value(left, right, "+")
    if Expression.scalar_value?(left) && Expression.active_value?(right)
      return right + left
    left + right

  -> .multiply_values(left, right)
    algebraic = left.class_name == "AlgebraicRealRoot"
    algebraic = algebraic || right.class_name == "AlgebraicRealRoot"
    if algebraic
      return AlgebraicRealArithmetic.value(left, right, "*")
    if Expression.scalar_value?(left) && Expression.active_value?(right)
      return right.scale(left) if right.respond_to?("scale")
      return right * left
    left * right

  -> .subtract_values(left, right)
    algebraic = left.class_name == "AlgebraicRealRoot"
    algebraic = algebraic || right.class_name == "AlgebraicRealRoot"
    if algebraic
      return AlgebraicRealArithmetic.value(left, right, "-")
    if Expression.scalar_value?(left) && Expression.active_value?(right)
      return (-right) + left
    left - right

  -> .divide_values(left, right)
    algebraic = left.class_name == "AlgebraicRealRoot"
    algebraic = algebraic || right.class_name == "AlgebraicRealRoot"
    if algebraic
      return AlgebraicRealArithmetic.value(left, right, "/")
    if Expression.scalar_value?(left) && Expression.active_value?(right)
      if right.respond_to?("reciprocal")
        inverse = right.reciprocal
        return inverse.scale(left) if inverse.respond_to?("scale")
        return inverse * left
    left / right

  -> evaluate(bindings)
    raise "expression evaluation needs a Hash" if bindings.class_name != "Hash"
    return @arguments[0] if constant?
    return Expression.named_constant_value(@arguments[0]) if named_constant?
    if variable?
      text = @arguments[0]
      return bindings[text] if bindings.has_key?(text)
      symbol = text.to_sym
      return bindings[symbol] if bindings.has_key?(symbol)
      raise "missing value for symbolic variable " + text

    values = []
    @arguments.each -> (argument)
      values.push(argument.evaluate(bindings))
    if @operation == "add"
      result = values[0]
      i = 1
      while i < values.size
        result = Expression.add_values(result, values[i])
        i += 1
      return result
    if @operation == "multiply"
      result = values[0]
      i = 1
      while i < values.size
        result = Expression.multiply_values(result, values[i])
        i += 1
      return result
    if @operation == "divide"
      return Expression.divide_values(values[0], values[1])
    if @operation == "power"
      return values[0] ** values[1]
    Expression.apply_unary(@operation, values[0])

  -> at(bindings)
    evaluate(bindings)

  -> complexity
    return 1 if constant? || variable? || named_constant?
    total = 1
    @arguments.each -> (argument)
      total += argument.complexity
    total

  -> .distribute(left, right)
    left_terms = left.operation == "add" ? left.arguments : [left]
    right_terms = right.operation == "add" ? right.arguments : [right]
    products = []
    left_terms.each -> (left_term)
      right_terms.each -> (right_term)
        products.push(Expression.product([left_term, right_term]))
    Expression.sum(products)

  # Expand products and nonnegative integral powers without changing
  # transcendental nodes or turning exact coefficients into approximations.
  -> expand
    return self if constant? || variable? || named_constant?
    if @operation == "add"
      terms = []
      @arguments.each -> (argument)
        terms.push(argument.expand)
      return Expression.sum(terms)
    if @operation == "multiply"
      result = Expression.constant(1)
      @arguments.each -> (argument)
        result = Expression.distribute(result, argument.expand)
      return result
    if @operation == "power"
      base = @arguments[0].expand
      exponent = @arguments[1]
      if exponent.constant?
        value = exponent.constant_value
        if Expression.integer?(value) && value >= 0
          result = Expression.constant(1)
          factor = base
          n = value
          while n > 0
            result = Expression.distribute(result, factor) if n.odd?
            n = n / 2
            factor = Expression.distribute(factor, factor) if n > 0
          return result
      return Expression.power(base, exponent.expand)
    if @operation == "divide"
      return Expression.divide(@arguments[0].expand, @arguments[1].expand)
    Expression.unary(@operation, @arguments[0].expand)

  -> .zero_expression?(expression)
    expression.constant? && Expression.zero_value?(expression.constant_value)

  -> .coefficient_map_add_entry(entries, degree, coefficient)
    i = 0
    while i < entries.size
      if entries[i][0] == degree
        combined = entries[i][1] + coefficient
        if Expression.zero_expression?(combined)
          entries.delete_at(i)
        else
          entries[i][1] = combined
        return entries
      i += 1
    entries.push([degree, coefficient]) if !Expression.zero_expression?(coefficient)
    entries

  -> .coefficient_map_add(left, right)
    out = []
    left.each -> (entry)
      Expression.coefficient_map_add_entry(out, entry[0], entry[1])
    right.each -> (entry)
      Expression.coefficient_map_add_entry(out, entry[0], entry[1])
    out

  -> .coefficient_map_multiply(left, right)
    out = []
    left.each -> (left_entry)
      right.each -> (right_entry)
        Expression.coefficient_map_add_entry(
          out,
          left_entry[0] + right_entry[0],
          left_entry[1] * right_entry[1])
    out

  # Sparse coefficients when this expression is viewed as a polynomial in
  # one selected variable. Other symbols and named constants are coefficients.
  -> coefficient_terms(variable)
    sought = variable.to_s
    return [[0, self]] if !depends_on?(sought)
    if variable?
      return [[1, Expression.constant(1)]] if @arguments[0] == sought
      return [[0, self]]
    if @operation == "add"
      result = []
      @arguments.each -> (argument)
        result = Expression.coefficient_map_add(
          result, argument.coefficient_terms(sought))
      return result
    if @operation == "multiply"
      result = [[0, Expression.constant(1)]]
      @arguments.each -> (argument)
        result = Expression.coefficient_map_multiply(
          result, argument.coefficient_terms(sought))
      return result
    if @operation == "power"
      exponent = @arguments[1]
      valid = exponent.constant?
      valid = Expression.integer?(exponent.constant_value) if valid
      valid = exponent.constant_value >= 0 if valid
      if valid
        result = [[0, Expression.constant(1)]]
        factor = @arguments[0].coefficient_terms(sought)
        n = exponent.constant_value
        while n > 0
          result = Expression.coefficient_map_multiply(result, factor) if n.odd?
          n = n / 2
          factor = Expression.coefficient_map_multiply(factor, factor) if n > 0
        return result
    if @operation == "divide" && !@arguments[1].depends_on?(sought)
      result = []
      @arguments[0].coefficient_terms(sought).each -> (entry)
        result.push([entry[0], entry[1] / @arguments[1]])
      return result
    raise "expression is not polynomial in " + sought

  -> degree_in(variable)
    entries = coefficient_terms(variable)
    return -1 if entries.size == 0
    result = entries[0][0]
    entries.each -> (entry)
      result = entry[0] if entry[0] > result
    result

  -> coefficient(variable, degree)
    if !Expression.integer?(degree) || degree < 0
      raise "symbolic coefficient degree must be a nonnegative integer"
    entries = coefficient_terms(variable)
    i = 0
    while i < entries.size
      return entries[i][1] if entries[i][0] == degree
      i += 1
    Expression.constant(0)

  -> collect(variable)
    sought = variable.to_s
    symbol = Expression.variable(sought)
    terms = []
    coefficient_terms(sought).each -> (entry)
      if entry[0] == 0
        terms.push(entry[1])
      else
        terms.push(entry[1] * (symbol ** entry[0]))
    Expression.sum(terms)

  -> linear_rate(variable)
    rate = derivative(variable)
    if rate.depends_on?(variable)
      raise "symbolic antiderivative needs a linear inner expression"
    if Expression.zero_expression?(rate)
      raise "symbolic antiderivative has zero inner derivative"
    rate

  -> .scale_by_reciprocal(expression, denominator)
    reciprocal = Expression.divide(Expression.constant(1), denominator)
    Expression.wrap(expression) * reciprocal

  -> antiderivative_power(base, exponent, variable)
    rate = base.linear_rate(variable)
    next_exponent = exponent + 1
    if Expression.zero_value?(next_exponent)
      return Expression.scale_by_reciprocal(base.abs.log, rate)
    denominator = rate * Expression.constant(next_exponent)
    Expression.scale_by_reciprocal(base ** next_exponent, denominator)

  # Elementary, exact antiderivatives. Unsupported integration patterns fail
  # loudly instead of switching to numerical quadrature or returning a guess.
  -> antiderivative(variable)
    sought = variable.to_s
    symbol = Expression.variable(sought)
    return self * symbol if !depends_on?(sought)
    if variable?
      if @arguments[0] == sought
        return symbol**2 * Expression.constant(Rational.new(1, 2))

    if @operation == "add"
      terms = []
      @arguments.each -> (argument)
        terms.push(argument.antiderivative(sought))
      return Expression.sum(terms)

    if @operation == "multiply"
      independent = []
      dependent = []
      @arguments.each -> (argument)
        if argument.depends_on?(sought)
          dependent.push(argument)
        else
          independent.push(argument)
      if dependent.size == 1
        return Expression.product(independent) * dependent[0].antiderivative(sought)

    if @operation == "divide"
      numerator = @arguments[0]
      denominator = @arguments[1]
      if !denominator.depends_on?(sought)
        return Expression.scale_by_reciprocal(
          numerator.antiderivative(sought), denominator)
      if !numerator.depends_on?(sought)
        rate = denominator.linear_rate(sought)
        return Expression.scale_by_reciprocal(
          numerator * denominator.abs.log, rate)

    if @operation == "power" && @arguments[1].constant?
      exponent = @arguments[1].constant_value
      if Expression.exact_value?(exponent)
        return antiderivative_power(@arguments[0], exponent, sought)

    argument = @arguments[0]
    rate = argument.linear_rate(sought)
    return Expression.scale_by_reciprocal(argument.exp, rate) if @operation == "exp"
    return Expression.scale_by_reciprocal(-argument.cos, rate) if @operation == "sin"
    return Expression.scale_by_reciprocal(argument.sin, rate) if @operation == "cos"
    return Expression.scale_by_reciprocal(argument.cosh, rate) if @operation == "sinh"
    return Expression.scale_by_reciprocal(argument.sinh, rate) if @operation == "cosh"
    if @operation == "sqrt"
      return antiderivative_power(argument, Rational.new(1, 2), sought)
    if @operation == "cbrt"
      return antiderivative_power(argument, Rational.new(1, 3), sought)
    if @operation == "log"
      return Expression.scale_by_reciprocal(
        argument * argument.log - argument, rate)
    if @operation == "expm1"
      return Expression.scale_by_reciprocal(argument.exp - argument, rate)
    if @operation == "log1p"
      shifted = argument + 1
      return Expression.scale_by_reciprocal(
        shifted * shifted.log - shifted, rate)
    if @operation == "abs"
      return Expression.scale_by_reciprocal(
        argument * argument.abs, rate * Expression.constant(2))
    if @operation == "erf"
      primitive = argument * argument.erf
      primitive += Expression.product([
        Expression.constant(1) / Expression.pi.sqrt,
        (-(argument**2)).exp
      ])
      return Expression.scale_by_reciprocal(primitive, rate)
    if @operation == "erfc"
      primitive = argument * argument.erfc
      primitive -= Expression.product([
        Expression.constant(1) / Expression.pi.sqrt,
        (-(argument**2)).exp
      ])
      return Expression.scale_by_reciprocal(primitive, rate)
    raise "no elementary symbolic antiderivative implemented for " + self.to_s

  -> integrate(variable)
    antiderivative(variable)

  -> definite_integral(variable, lower, upper)
    sought = variable.to_s
    primitive = antiderivative(sought)
    lower_bindings = {}
    upper_bindings = {}
    lower_bindings[sought.to_sym] = lower
    upper_bindings[sought.to_sym] = upper
    primitive.substitute(upper_bindings) - primitive.substitute(lower_bindings)

  -> polynomial_expression?
    return true if constant? || variable?
    return false if named_constant?
    if @operation == "add" || @operation == "multiply"
      i = 0
      while i < @arguments.size
        return false if !@arguments[i].polynomial_expression?
        i += 1
      return true
    if @operation == "power"
      exponent = @arguments[1]
      return false if !exponent.constant?
      value = exponent.constant_value
      return false if !Expression.integer?(value) || value < 0
      return @arguments[0].polynomial_expression?
    if @operation == "divide"
      return false if !@arguments[0].polynomial_expression?
      return @arguments[1].constant?
    false

  -> to_polynomial(ring)
    if ring.class_name != "PolynomialRing"
      raise "symbolic polynomial conversion needs a PolynomialRing"
    return ring.constant(@arguments[0]) if constant?
    if named_constant?
      raise "named transcendental constant is not a polynomial coefficient: " + @arguments[0]
    if variable?
      index = ring.index_of(@arguments[0])
      raise "symbolic variable is not in polynomial ring: " + @arguments[0] if index == nil
      return ring.generator(index)
    if @operation == "add"
      result = ring.zero
      @arguments.each -> (argument)
        result = result + argument.to_polynomial(ring)
      return result
    if @operation == "multiply"
      result = ring.one
      @arguments.each -> (argument)
        result = result * argument.to_polynomial(ring)
      return result
    if @operation == "divide"
      if !@arguments[1].constant?
        raise "nonconstant symbolic denominator is not a polynomial"
      numerator = @arguments[0].to_polynomial(ring)
      denominator = ring.constant(@arguments[1].constant_value)
      return numerator / denominator
    if @operation == "power"
      exponent = @arguments[1]
      valid = exponent.constant?
      valid = Expression.integer?(exponent.constant_value) if valid
      if !valid || exponent.constant_value < 0
        raise "polynomial conversion needs a nonnegative integer exponent"
      return @arguments[0].to_polynomial(ring) ** exponent.constant_value
    raise "transcendental expression is not a polynomial: " + @operation

  -> .from_polynomial(polynomial)
    if polynomial.class_name != "Polynomial"
      raise "Expression.from_polynomial needs a Polynomial"
    if polynomial.ring.field.class_name != "RationalField"
      raise "symbolic polynomial conversion currently requires RationalField"

    variables = Expression.variables(polynomial.ring.names)
    terms = []
    polynomial.each_term -> (coefficient, exponents)
      factors = [Expression.constant(coefficient)]
      i = 0
      while i < exponents.size
        if exponents[i] > 0
          factors.push(variables[i] ** exponents[i])
        i += 1
      terms.push(Expression.product(factors))
    Expression.sum(terms)

  -> precedence
    return 10 if @operation == "add"
    return 20 if @operation == "multiply" || @operation == "divide"
    return 30 if @operation == "power"
    40

  -> render(parent_precedence = 0)
    return @arguments[0].to_s if constant?
    return @arguments[0] if variable?
    if named_constant?
      return "π" if @arguments[0] == "pi"
      return "e"

    text = ""
    if @operation == "add"
      pieces = []
      @arguments.each -> (argument)
        pieces.push(argument.render(10))
      text = pieces.join(" + ").replace("+ -", "- ")
    elsif @operation == "multiply"
      numerator_factors = []
      reciprocal_denominators = []
      @arguments.each -> (factor)
        reciprocal = factor.operation == "divide"
        reciprocal = reciprocal && factor.arguments[0].constant?
        if reciprocal
          reciprocal = Expression.one_value?(
            factor.arguments[0].constant_value)
        if reciprocal
          reciprocal_denominators.push(factor.arguments[1])
        else
          numerator_factors.push(factor)
      if reciprocal_denominators.size > 0
        numerator = Expression.product(numerator_factors)
        denominator = Expression.product(reciprocal_denominators)
        text = numerator.render(21) + "/" + denominator.render(21)
      else
        pieces = []
        start = 0
        negative_coefficient = false
        if @arguments.size > 1 && @arguments[0].constant?
          negative_coefficient = Expression.negative_one_value?(@arguments[0].constant_value)
        if negative_coefficient
          start = 1
          rest = []
          i = start
          while i < @arguments.size
            rest.push(@arguments[i].render(20))
            i += 1
          text = "-" + rest.join("*")
        else
          @arguments.each -> (argument)
            pieces.push(argument.render(20))
          text = pieces.join("*")
    elsif @operation == "divide"
      text = @arguments[0].render(21) + "/" + @arguments[1].render(21)
    elsif @operation == "power"
      text = @arguments[0].render(31) + "^" + @arguments[1].render(30)
    else
      text = @operation + "(" + @arguments[0].render(0) + ")"

    if precedence < parent_precedence
      return "(" + text + ")"
    text

  -> to_s
    render(0)

  -> inspect
    to_s
