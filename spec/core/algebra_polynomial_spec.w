# Focused exact-polynomial regression identities.

use core/algebra/field
use core/algebra/polynomial

-> check(name, got, want)
  equal = got == want
  if got.class_name == "Polynomial"
    equal = got.eql?(want)
  elsif want.class_name == "Polynomial"
    equal = want.eql?(got)
  if !equal
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

field = RationalField.new
lex_ring = PolynomialRing.new([:x, :y, :z], field, :lex)
grlex_ring = PolynomialRing.new([:x, :y, :z], field, :grlex)
grevlex_ring = PolynomialRing.new([:x, :y, :z], field, :grevlex)
product_ring = PolynomialRing.new(
  [:x, :y, :z], field, MonomialOrder.product(1, :lex, :grevlex))

unsupported_ring_failed = false
begin
  PolynomialRing.new([:x], Field.new)
rescue error
  unsupported_ring_failed = "[error]".include?("unsupported coefficient field")
check("ring unsupported field raises", unsupported_ring_failed, true)

lx, ly, lz = lex_ring.generators
gx, gy, gz = grlex_ring.generators
rx, ry, rz = grevlex_ring.generators
px, py, pz = product_ring.generators

# x^2 z and x y^2 have the same total degree. Lex/grlex choose the former;
# grevlex chooses the latter. Product order first compares the x block.
check("order.lex", (lx**2 * lz + lx * ly**2).leading_exponents.join(","), "2,0,1")
check("order.grlex", (gx**2 * gz + gx * gy**2).leading_exponents.join(","), "2,0,1")
check("order.grevlex", (rx**2 * rz + rx * ry**2).leading_exponents.join(","), "1,2,0")
check("order.product", (px**2 * pz + px * py**2).leading_exponents.join(","), "2,0,1")

qring = PolynomialRing.new([:t], field, :grevlex)
t = qring.generator(0)
half = Rational.new(1, 2)
three_quarters = Rational.new(3, 4)
p = t**2 * half - three_quarters

check("term.coeff", p.coeff(2), half)
check("term.missing_coeff", p.coeff(1), 0)
check("term.exponents.first", p.exponents[0][0], 2)
check("term.exponents.second", p.exponents[1][0], 0)
seen = []
p.each_term -> (coefficient, exponents)
  seen.push([coefficient, exponents])
check("term.each_term.first.coeff", seen[0][0], half)
check("term.each_term.first.exponent", seen[0][1][0], 2)
check("term.each_term.second.coeff", seen[1][0], 0 - three_quarters)
check("term.each_term.second.exponent", seen[1][1][0], 0)
check("term.sorted", p.leading_exponents[0], 2)

check("content", p.content, Rational.new(1, 4))
check("primitive_part", p.primitive_part, t**2 * 2 - 3)
check("leading_coefficient", p.leading_coefficient, half)
check("lc", p.lc, half)
check("LC", p.LC, half)

dividend = t**3 - 1
divisor = t - 1
division = dividend.divmod(divisor)
check("divmod.quotient", division[0], t**2 + t + 1)
check("divmod.remainder", division[1], 0)
check("quo", dividend.quo(divisor), t**2 + t + 1)
check("rem", (t**2 + 1).rem(t + 1), 2)
check("exact division", dividend / divisor, t**2 + t + 1)

nonexact_raised = false
begin
  (t**2 + 1) / (t + 1)
rescue error
  nonexact_raised = true
check("nonexact division raises", nonexact_raised, true)

other_ring = PolynomialRing.new([:u], field)
u = other_ring.generator(0)
mismatch_raised = false
begin
  t + u
rescue error
  mismatch_raised = true
check("ring mismatch raises", mismatch_raised, true)

check("gcd", (t**3 - t).gcd(t**2 - 1), t**2 - 1)
check("primitive_gcd", (t**2 * 2 - 2).primitive_gcd(t**2 * 3 - 3), t**2 - 1)
xgcd = (t**3 - 1).xgcd(t**2 - 1)
check("xgcd.gcd", xgcd[0], t - 1)
check("xgcd.bezout",
      xgcd[1] * (t**3 - 1) + xgcd[2] * (t**2 - 1),
      xgcd[0])

multi_ring = PolynomialRing.new([:x, :y], field, :grevlex)
mx, my = multi_ring.generators
shared = mx + my
check("multivariate primitive gcd",
      ((mx - my) * shared).primitive_gcd((mx + 1) * shared),
      shared)
check("multivariate coefficient-content gcd",
      ((mx + 1) * (my + 1)).gcd((mx + 1) * (my**2 + 1)),
      mx + 1)
check("multivariate squarefree product", (mx * my).squarefree?, true)
check("multivariate repeated factor", ((mx + my)**2 * (mx + 1)).squarefree?, false)

factors = (t**3 - t).factor
factor_product = qring.one
factors.each -> factor_product = factor_product * item
check("factor.product", factor_product, t**3 - t)
check("factor.linear_count", factors.size, 3)

quartic = (t**2 + 1) * (t**2 + 2)
quartic_factors = quartic.factor
quartic_product = qring.one
quartic_factors.each -> quartic_product = quartic_product * item
check("factor.quartic_without_roots.product", quartic_product, quartic)
check("factor.quartic_without_roots.count", quartic_factors.size, 2)
quartic_pair_forward = quartic_factors[0].eql?(t**2 + 1) && quartic_factors[1].eql?(t**2 + 2)
quartic_pair_reverse = quartic_factors[0].eql?(t**2 + 2) && quartic_factors[1].eql?(t**2 + 1)
check("factor.quartic_without_roots.irreducibles",
      quartic_pair_forward || quartic_pair_reverse, true)

repeated_quadratic = (t**2 + 1)**2
repeated_factors = repeated_quadratic.factor
check("factor.repeated_irreducible.count", repeated_factors.size, 2)
check("factor.repeated_irreducible.first", repeated_factors[0], t**2 + 1)
check("factor.repeated_irreducible.second", repeated_factors[1], t**2 + 1)

irreducible_quartic = t**4 + 1
check("factor.irreducible_quartic.count", irreducible_quartic.factor.size, 1)
check("factor.irreducible_quartic.value", irreducible_quartic.factor[0], irreducible_quartic)

check("resultant.linear", (t**2 - 2).resultant(t - 1), -1)
check("discriminant.quadratic", (t**2 + t + 1).discriminant, -3)
check("discriminant.cubic", (t**3 - t).discriminant, 4)

<< "algebra_polynomial_spec: all checks passed"
