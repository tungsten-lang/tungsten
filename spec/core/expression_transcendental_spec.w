# Exact common-angle transcendentals and globally valid identities. Run in
# both interpreter and native engines.

use calculus

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> close?(got, want, tolerance = ~1.0e-12)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

x = Calculus.symbol(:x)
pi = Expression.pi
sqrt_two = Expression.constant(2).sqrt
sqrt_three = Expression.constant(3).sqrt
sqrt_six = Expression.constant(6).sqrt

check("trig.sin_pi_six",
      (pi / 6).sin == Expression.constant(Rational.new(1, 2)))
check("trig.cos_pi_three",
      (pi / 3).cos == Expression.constant(Rational.new(1, 2)))
check("trig.sin_pi_four", (pi / 4).sin == sqrt_two / 2)
check("trig.cos_pi_six", (pi / 6).cos == sqrt_three / 2)
check("trig.sin_pi_twelve",
      (pi / 12).sin == (sqrt_six - sqrt_two) / 4)
check("trig.cos_pi_twelve",
      (pi / 12).cos == (sqrt_six + sqrt_two) / 4)
check("trig.tan_pi_twelve",
      (pi / 12).tan == Expression.constant(2) - sqrt_three)
check("trig.negative_angle",
      (Expression.negate(pi) / 6).sin ==
        Expression.constant(Rational.new(-1, 2)))
check("trig.periodic_angle",
      (pi * Rational.new(25, 12)).sin ==
        (sqrt_six - sqrt_two) / 4)
check("trig.undefined_tangent_stays_symbolic",
      (pi / 2).tan.operation == "tan")

lattice_ok = true
machine_pi = Math.acos(~-1.0)
24.times -> (k)
  lattice_angle = pi * Rational.new(k, 12)
  machine_angle = machine_pi * k.to_f / ~12.0
  lattice_ok = false if !close?(
    lattice_angle.sin.evaluate({}), Math.sin(machine_angle))
  lattice_ok = false if !close?(
    lattice_angle.cos.evaluate({}), Math.cos(machine_angle))
  if k % 12 != 6
    lattice_ok = false if !close?(
      lattice_angle.tan.evaluate({}), Math.tan(machine_angle))
check("trig.full_pi_twelfth_lattice", lattice_ok)

check("inverse.asin_half", Expression.constant(Rational.new(1, 2)).asin == pi / 6)
check("inverse.asin_negative_half",
      Expression.constant(Rational.new(-1, 2)).asin == -(pi / 6))
check("inverse.acos_half", Expression.constant(Rational.new(1, 2)).acos == pi / 3)
check("inverse.acos_negative_half",
      Expression.constant(Rational.new(-1, 2)).acos == pi * Rational.new(2, 3))

check("parity.sin", (-x).sin == -x.sin)
check("parity.cos", (-x).cos == x.cos)
check("parity.sinh", (-x).sinh == -x.sinh)
check("parity.cosh", (-x).cosh == x.cosh)
check("parity.cbrt_exact", Expression.constant(-2).cbrt == -Expression.constant(2).cbrt)

check("identity.circular", x.sin**2 + x.cos**2 == Expression.constant(1))
check("identity.circular_scaled",
      x.sin**2 * 3 + x.cos**2 * 3 == Expression.constant(3))
check("identity.hyperbolic", x.cosh**2 - x.sinh**2 == Expression.constant(1))
check("identity.nonmatching_untouched",
      (x.sin**2 + (x + 1).cos**2).operation == "add")
check("facade.simplify",
      Calculus.simplify(
        Expression.node("add", [x.sin**2, x.cos**2])) ==
        Expression.constant(1))

angle = pi / 12
check("trig.exact_value_evaluates",
      close?(angle.sin.evaluate({}), Math.sin(Math.acos(~-1.0) / ~12.0)))

<< "expression_transcendental_spec: all checks passed"
