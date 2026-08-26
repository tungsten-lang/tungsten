# Resultants and discriminants with respect to one variable in any arity.

use core/algebra/field
use core/algebra/finite_field
use core/algebra/polynomial
use core/algebra/polynomial_resultant
use core/algebra/polynomial_gcd
use core/algebra/polynomial_resultant_multivariate

-> check(name, got, want)
  equal = got == want
  if got.class_name == "Polynomial"
    equal = got.eql?(want)
  elsif want.class_name == "Polynomial"
    equal = want.eql?(got)
  if !equal
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

field = FiniteField.new(101)
ring = PolynomialRing.new([:x, :y, :z], field, :grevlex)
gens = ring.generators
x = gens[0]
y = gens[1]
z = gens[2]

# Substitute a polynomial value for y by expanding coefficients.
-> at_y(h, value)
  acc = h.ring.zero
  exponent = 0
  while exponent <= h.degree_in(:y)
    acc = acc + h.coefficient_in(:y, exponent) * value**exponent
    exponent += 1
  acc

f = y**2 + x * y + z
g = y**3 + z * y - x * x
h = x * y**2 + (z + 3) * y + 1
a = x * z + 2

check("multiplicativity Res_y(fg,h) = Res_y(f,h) Res_y(g,h)",
      (f * g).resultant_in(h, :y),
      f.resultant_in(h, :y) * g.resultant_in(h, :y))
check("Res_y(y - a, h) = h(a)", (y - a).resultant_in(h, :y), at_y(h, a))
check("Res_y(h, y - a) = ±h(a)",
      h.resultant_in(y - a, :y).eql?(at_y(h, a)) ||
        h.resultant_in(y - a, :y).eql?(-at_y(h, a)),
      true)
check("resultant does not involve the variable",
      f.resultant_in(g, :y).degree_in(:y), 0)
check("degree-zero right factor", f.resultant_in(x + 1, :y), (x + 1)**2)
check("shared factor gives zero", (f * h).resultant_in(f * g, :y), ring.zero)
check("discriminant of a square is zero", (f * f).discriminant_in(:y), ring.zero)
check("discriminant of y^2 + xy + z", f.discriminant_in(:y), x * x - z * 4)
check("resultant in x", (x - z).resultant_in(x * x - z * z, :x), ring.zero)
check("resultant in z", (z - x).resultant_in(z * z + y, :z), x * x + y)
check("derivative_in", f.derivative_in(:y), y * 2 + x)

# Consistency with bivariate_resultant on a two-variable ring: compare the
# univariate answer with the same-ring answer after evaluation.
ring2 = PolynomialRing.new([:x, :y], field, :grevlex)
gens2 = ring2.generators
x2 = gens2[0]
y2 = gens2[1]
f2 = y2**2 + x2 * y2 + 5
g2 = y2**3 + x2 * y2 * 2 + x2
bivariate = f2.bivariate_resultant(g2, :y)
same_ring = f2.resultant_in(g2, :y)
point = 7
check("agrees with bivariate_resultant at x = 7",
      same_ring.substitute(:x, point).evaluate([0, 0]),
      bivariate.evaluate([point]))
check("agrees with bivariate_resultant at x = 40",
      same_ring.substitute(:x, 40).evaluate([0, 0]),
      bivariate.evaluate([40]))

# Trivariate chain used by the critical-locus argument:
# rho(z) = Res_x( Res_y(Phi, Phi_x), Res_y(Phi, Phi_y) ).
phi = y * y + x * y * z + x**3 + z
res_x = phi.resultant_in(phi.derivative_in(:x), :y)
res_y = phi.resultant_in(phi.derivative_in(:y), :y)
rho = res_x.resultant_in(res_y, :x)
check("chain involves only z", rho.degree_in(:x) == 0 && rho.degree_in(:y) == 0, true)
check("chain is nonzero", rho.zero?, false)
# Specialisation commutes with the chain at a point where no leading
# coefficient drops (degrees stay the same after z = 5).
z0 = 5
phi0 = phi.substitute(:z, z0)
rho0 = phi0.resultant_in(phi0.derivative_in(:x), :y).resultant_in(
  phi0.resultant_in(phi0.derivative_in(:y), :y), :x)
check("chain commutes with specialisation z = 5",
      rho.substitute(:z, z0), rho0)
<< "ALL PASS"
