# Exact symbolic-expression operations backed by the rational polynomial
# layer. Keep this extension under `use algebra`: the base Expression tree
# does not implicitly load fields, polynomial algorithms, or geometry.

use core/expression

+ Expression
  -> univariate_variable(variable = nil)
    variables = free_variables
    if variable == nil
      return nil if variables.size == 0
      if variables.size != 1
        raise "univariate symbolic operation needs exactly one variable"
      return variables[0]

    sought = variable.to_s
    variables.each -> (candidate)
      if candidate.to_s != sought
        raise "symbolic expression is not univariate in " + sought
    sought.to_sym

  -> rational_univariate_polynomial(variable = nil)
    selected = univariate_variable(variable)
    if selected == nil
      ring = PolynomialRing.new([:_constant], RationalField.new)
      return [ring, ring.constant(constant_value)] if constant?
      raise "symbolic expression has no polynomial variable"
    ring = PolynomialRing.new([selected], RationalField.new)
    [ring, to_polynomial(ring)]

  -> factor_list(variable = nil)
    selected = univariate_variable(variable)
    return [self] if selected == nil
    pair = rational_univariate_polynomial(selected)
    out = []
    pair[1].factor.each -> (piece)
      out.push(Expression.from_polynomial(piece))
    out

  -> factors(variable = nil)
    factor_list(variable)

  -> factor(variable = nil)
    Expression.product(factor_list(variable))

  -> .real_roots_of_degree_at_most_two(polynomial)
    degree = polynomial.degree
    return [] if degree <= 0
    if degree == 1
      constant = polynomial.coeff(0)
      linear = polynomial.coeff(1)
      return [Expression.constant(0 - constant) / Expression.constant(linear)]
    if degree != 2
      raise "exact symbolic solving needs factors of degree at most two"

    constant = polynomial.coeff(0)
    linear = polynomial.coeff(1)
    quadratic = polynomial.coeff(2)
    discriminant = linear * linear - quadratic * constant * 4
    return [] if discriminant.negative?
    center = Expression.constant(0 - linear)
    denominator = Expression.constant(quadratic * 2)
    return [center / denominator] if discriminant.zero?
    radical = Expression.constant(discriminant).sqrt
    [
      (center - radical) / denominator,
      (center + radical) / denominator
    ]

  # Exact real roots. Linear roots stay Rational, quadratic roots retain their
  # familiar radical form, and higher irreducible factors become certified
  # AlgebraicRealRoot constants with refinable rational isolating intervals.
  -> real_roots(variable = nil)
    selected = univariate_variable(variable)
    if selected == nil
      if constant? && Expression.zero_value?(constant_value)
        raise "zero expression has infinitely many roots"
      return []

    pair = rational_univariate_polynomial(selected)
    polynomial = pair[1]
    raise "zero polynomial has infinitely many roots" if polynomial.zero?
    roots = []
    polynomial.real_roots.each -> (value)
      if value.class_name == "AlgebraicRealRoot"
        factor = value.defining_polynomial
        if factor.degree == 2
          explicit = Expression.real_roots_of_degree_at_most_two(factor)
          roots.push(explicit[value.root_index])
        else
          roots.push(Expression.constant(value))
      else
        roots.push(Expression.constant(value))
    roots

  -> solve(variable = nil)
    real_roots(variable)


+ Algebra
  -> .factor(expression, variable = nil)
    Expression.wrap(expression).factor(variable)

  -> .solve(expression, variable = nil)
    Expression.wrap(expression).solve(variable)
