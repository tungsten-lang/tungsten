# Focused Gröbner-basis and ideal regression identities.

use core/algebra/field
use core/algebra/polynomial
use core/algebra/groebner

-> check(name, got, want)
  equal = got == want
  if got.class_name == "Polynomial"
    equal = got.eql?(want)
  elsif want.class_name == "Polynomial"
    equal = want.eql?(got)
  if !equal
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

ring = PolynomialRing.new([:x, :y], RationalField.new, :lex)
x, y = ring.generators

generator = x * y - 1
dividend = x**2 * y + x * y**2 + y
division = dividend.divide([generator])
check("multivariate quotient", division[0][0], x + y)
check("multivariate remainder", division[1], x + y * 2)
check("division identity",
      division[0][0] * generator + division[1],
      dividend)

ideal = Ideal.new([x * y - 1, y**2 - x])
basis = ideal.basis
check("basis.size", basis.size, 2)
check("basis.first", basis[0], x - y**2)
check("basis.second", basis[1], y**3 - 1)
check("basis.monic.first", basis[0].leading_coefficient, 1)
check("basis.monic.second", basis[1].leading_coefficient, 1)

check("ideal.generator membership", ideal.contains?(x * y - 1), true)
check("ideal.consequence membership", ideal.contains?(y**3 - 1), true)
check("ideal.nonmembership", ideal.contains?(x), false)
check("ideal.proper", ideal.proper?, true)

gb = GroebnerBasis.new([x * y - 1, y**2 - x])
check("groebner object membership", gb.contains?(x * y - 1), true)
check("groebner object reduced size", gb.polynomials.size, basis.size)
check("groebner object reduced first", gb.polynomials[0], basis[0])
check("groebner object reduced second", gb.polynomials[1], basis[1])

unit = Ideal.new([x, ring.one - x])
check("unit ideal", unit.unit?, true)
check("unit basis size", unit.basis.size, 1)
check("unit basis one", unit.basis[0], ring.one)
check("unit contains arbitrary", unit.contains?(x**7 + y), true)

zero = Ideal.zero(ring)
check("zero ideal", zero.zero?, true)
check("zero contains zero", zero.contains?(ring.zero), true)
check("zero excludes x", zero.contains?(x), false)

other_ring = PolynomialRing.new([:u], RationalField.new, :lex)
mixed_raised = false
begin
  Ideal.new([x, other_ring.generator(0)])
rescue error
  mixed_raised = true
check("ideal ring mismatch raises", mixed_raised, true)

same_ideal = Ideal.new([x * y - 1, y**2 - x, y**3 - 1])
check("ideal equality by membership", same_ideal.eql?(ideal), true)

# Principal saturation: (x y) : x^∞ = (y).
product_ideal = Ideal.new([x * y])
saturated = product_ideal.saturate(x)
check("saturation.contains_y", saturated.contains?(y), true)
check("saturation.excludes_x", saturated.contains?(x), false)
check("saturation.basis", saturated.basis[0], y)

# Elimination of the first variable from ⟨y - x^2⟩ is the zero ideal in k[y].
parabola = Ideal.new([y - x * x])
eliminated = parabola.eliminate(1)
check("elimination.ring", eliminated.ring.names.join(","), "y")
check("elimination.zero", eliminated.zero?, true)

# Lex elimination of a simple linear system recovers the projected generator.
lex_ring = PolynomialRing.new([:u, :v], RationalField.new, :lex)
u = lex_ring.generator(0)
v = lex_ring.generator(1)
linear = Ideal.new([u + v - 1, u - v])
proj = linear.eliminate(1)
# Reduced Gröbner bases are monic, so 2v - 1 becomes v - 1/2 in the
# remaining univariate ring (not the original bivariate ring).
check("elimination.linear", proj.basis[0].to_s, "v - 1/2")
check("elimination.linear_degree", proj.basis[0].degree, 1)

<< "algebra_groebner_spec: all checks passed"
