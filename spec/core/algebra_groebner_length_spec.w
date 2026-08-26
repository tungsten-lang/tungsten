# Zero-dimensional ideals: standard monomials and length.

use core/algebra/field
use core/algebra/finite_field
use core/algebra/polynomial
use core/algebra/groebner
use core/algebra/groebner_length

-> check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

field = FiniteField.new(101)
ring = PolynomialRing.new([:x, :y], field, :grevlex)
gens = ring.generators
x = gens[0]
y = gens[1]

monomial_ideal = Ideal.new([x**2, y**3])
check("monomial ideal is zero-dimensional", monomial_ideal.zero_dimensional?, true)
check("monomial ideal length", monomial_ideal.length, 6)
check("monomial ideal standard monomials", monomial_ideal.standard_monomials.size, 6)

twisted = Ideal.new([x**2 - y, y**2 - x])
check("x^2 - y, y^2 - x is zero-dimensional", twisted.zero_dimensional?, true)
check("x^2 - y, y^2 - x has length 4", twisted.length, 4)

basis = GroebnerBasis.new([x**2 - y, y**2 - x])
check("GroebnerBasis length", basis.length, 4)
check("GroebnerBasis standard monomial polynomials",
      basis.standard_monomial_polynomials.size, 4)

curve = Ideal.new([x * y])
check("x*y is not zero-dimensional", curve.zero_dimensional?, false)
raised = false
begin
  curve.length
rescue error
  raised = true
check("length raises for a positive-dimensional ideal", raised, true)

unit = Ideal.new([x + 1, x + 2])
check("unit ideal is zero-dimensional", unit.zero_dimensional?, true)
check("unit ideal has length 0", unit.length, 0)

ring3 = PolynomialRing.new([:x, :y, :z], field, :grevlex)
gens3 = ring3.generators
x3 = gens3[0]
y3 = gens3[1]
z3 = gens3[2]
triple = Ideal.new([x3**2 + y3 + 1, y3**2 + z3 + 2, z3**2 + x3 + 3])
check("triple is zero-dimensional", triple.zero_dimensional?, true)
check("triple has length 8", triple.length, 8)
<< "ALL PASS"
