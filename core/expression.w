# Expression — canonical symbolic real expressions.
#
# Expressions are immutable-by-convention trees built through simplifying
# factories. They support exact arithmetic constants, elementary
# transcendental functions, substitution, numerical/active-value evaluation,
# symbolic differentiation, and conversion to exact polynomial rings.
#
#   x, y = Expression.variables([:x, :y])
#   f = (x**2 + y**2).sqrt + (x * y).sin
#   f.derivative(:x)
#   f.evaluate({x: ~3.0, y: ~4.0})
#
# `use calculus` exposes the shorter `Calculus.symbol` / `.symbols` facade.

use core/math

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
    Expression.node("constant", [value])

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

  -> constant_value
    raise "expression is not constant" if !constant?
    @arguments[0]

  -> name
    raise "expression is not a variable" if !variable?
    @arguments[0].to_sym

  -> variable_text
    raise "expression is not a variable" if !variable?
    @arguments[0]

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
      "Decimal", "Decimal32", "Decimal64", "Decimal128"
    ]
    scalar_names.include?(name)

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
            constant_total = constant_total + value
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
        groups[found][1] = groups[found][1] + coefficient
      else
        groups.push([base, coefficient])

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
    return Expression.constant(0 - expression.constant_value) if expression.constant?
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
              constant_total = constant_total * value
            else
              constant_total = value
              constant_seen = true
        else
          flattened.push(piece)
    return Expression.constant(0) if zero_factor

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
      if !Expression.one_value?(constant_total)
        factors = [Expression.constant(constant_total)] + factors
    return Expression.constant(1) if factors.size == 0
    return factors[0] if factors.size == 1
    Expression.node("multiply", factors)

  -> .multiply(left, right)
    Expression.product([left, right])

  -> .divide_constants(numerator, denominator)
    raise "symbolic division by zero" if Expression.zero_value?(denominator)
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
    if left.constant? && right.constant?
      return Expression.constant(
        Expression.divide_constants(left.constant_value, right.constant_value))
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
        return Expression.constant(base_value ** value)
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
    raise "unknown symbolic unary operation: " + operation

  -> .unary(operation, argument)
    name = operation.to_s
    expression = Expression.wrap(argument)

    if expression.constant?
      value = expression.constant_value
      if Expression.zero_value?(value)
        if name == "cos" || name == "cosh" || name == "exp"
          return Expression.constant(1)
        logarithm = name == "log" || name == "log2" || name == "log10"
        if !logarithm && name != "acosh" && name != "acos"
          return Expression.constant(0)
      if Expression.one_value?(value)
        return Expression.constant(0) if name == "log"
        identity = name == "sqrt" || name == "cbrt" || name == "abs"
        return Expression.constant(1) if identity
      return Expression.constant(Expression.apply_unary(name, value))

    if name == "log" && expression.operation == "exp"
      return expression.arguments[0]
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
    return self if constant? || variable?
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
    return Expression.constant(0) if constant?
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
    return derivative / (Expression.constant(~0.6931471805599453) * argument) if @operation == "log2"
    return derivative / (Expression.constant(~2.302585092994046) * argument) if @operation == "log10"
    return derivative / (Expression.constant(3) * argument.cbrt**2) if @operation == "cbrt"
    return argument * derivative / argument.abs if @operation == "abs"
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
    if !constant?
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
    if constant?
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
    ["TaylorJet", "Differential", "Polynomial", "Complex"].include?(name)

  -> .add_values(left, right)
    if Expression.scalar_value?(left) && Expression.active_value?(right)
      return right + left
    left + right

  -> .multiply_values(left, right)
    if Expression.scalar_value?(left) && Expression.active_value?(right)
      return right.scale(left) if right.respond_to?("scale")
      return right * left
    left * right

  -> .subtract_values(left, right)
    if Expression.scalar_value?(left) && Expression.active_value?(right)
      return (-right) + left
    left - right

  -> .divide_values(left, right)
    if Expression.scalar_value?(left) && Expression.active_value?(right)
      if right.respond_to?("reciprocal")
        inverse = right.reciprocal
        return inverse.scale(left) if inverse.respond_to?("scale")
        return inverse * left
    left / right

  -> evaluate(bindings)
    raise "expression evaluation needs a Hash" if bindings.class_name != "Hash"
    return @arguments[0] if constant?
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
    return 1 if constant? || variable?
    total = 1
    @arguments.each -> (argument)
      total += argument.complexity
    total

  -> polynomial_expression?
    return true if constant? || variable?
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

    text = ""
    if @operation == "add"
      pieces = []
      @arguments.each -> (argument)
        pieces.push(argument.render(10))
      text = pieces.join(" + ").replace("+ -", "- ")
    elsif @operation == "multiply"
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
