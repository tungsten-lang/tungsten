# Focused compiled checks for structural LaTeX rendering of algebra objects.
#
# Run:
#   bin/tungsten compile spec/core/latex_algebra_spec.w --out /tmp/latex-algebra-spec
#   /tmp/latex-algebra-spec

use core/algebra/field
use core/algebra/polynomial
use core/expression
use core/numeric/interval

-> latex_algebra_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

field = RationalField.new
ring = PolynomialRing.new([:x, :y_1], field)
x, y = ring.generators
polynomial = x**2 * Rational.new(1, 2) - y * 3 + 1

latex_algebra_check("field.rational", LaTeX.render(field).to_s, "\\mathbb{Q}")
latex_algebra_check(
  "ring.multivariate",
  LaTeX.render(ring).to_s,
  "\\mathbb{Q}\\left\[x, y_{1}\\right]")
latex_algebra_check(
  "polynomial.multivariate",
  LaTeX.render(polynomial).to_s,
  "\\frac{1}{2}\\,x^{2} - 3\\,y_{1} + 1")

latex_algebra_check(
  "field.finite_prime",
  LaTeX.render(FiniteField.new(5)).to_s,
  "\\mathbb{F}_{5}")
latex_algebra_check(
  "field.finite_extension",
  LaTeX.render(FiniteField.new(2, [1, 1, 1])).to_s,
  "\\mathbb{F}_{4}")

z = Expression.variable(:z)
expression = (z**2 + 1) / (z - 1)
latex_algebra_check(
  "expression.precedence",
  LaTeX.render(expression).to_s,
  "\\frac{z^{2} + 1}{z - 1}")
latex_algebra_check(
  "expression.named_constants",
  LaTeX.render(Expression.pi * z + Expression.euler_gamma).to_s,
  "z\\,\\pi + \\gamma")

latex_algebra_check(
  "interval.bounds",
  LaTeX.render(Interval.new(~1.0, ~2.5)).to_s,
  "\\left\[1, 2.5\\right]")

projective = Algebra.rational_projective_plane(:X, :Y, :Z).point(2, -4, 0)
latex_algebra_check(
  "projective.coordinates",
  LaTeX.render(projective).to_s,
  "\\left\[1:-2:0\\right]")

<< "latex_algebra_spec: all checks passed"
