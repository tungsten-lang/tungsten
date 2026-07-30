# Expression must be usable through core autoload without `use calculus`.

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

x = Expression.variable(:x)
check("autoload.class", x.class_name == "Expression")
check("autoload.simplify", x + x == x*2)
check("autoload.derivative", (x**3).derivative(:x) == x**2*3)
check("autoload.evaluate",
      (x**2 + 1).evaluate({x: ~2.0}) == ~5.0)
check("autoload.transcendental",
      (x.sin.derivative(:x) == x.cos))
check("autoload.exact_fraction",
      (Expression.constant(1) / 2).constant_value == Rational.new(1, 2))

<< "expression_autoload_spec: all checks passed"
