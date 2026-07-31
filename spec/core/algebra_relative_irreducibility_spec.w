# Exact relative modular irreducibility over a number field.

use algebra

-> relative_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

qx = PolynomialRing.new([:x], RationalField.new, :lex)
x = qx.generator(0)
k = NumberField.new(x**2 - 2, :a)
reduction = NumberFieldPowerBasisPrimeReduction.new(k, 7, 3)

relative_check("reduction.certified",
               reduction.certified?, true)
relative_check("reduction.generator",
               reduction.reduce(k.generator), 3)

ky = PolynomialRing.new([:y], k, :lex)
y = ky.generator(0)
polynomial = y**2 + 1
certificate = NumberFieldRelativeModularDegreeIrreducibilityCertificate.new(
  polynomial, [reduction])

relative_check("relative.certified",
               certificate.certified?, true)
relative_check("relative.patterns",
               certificate.factor_degree_patterns.to_s,
               "\[\[2\]\]")
relative_check("relative.remaining",
               certificate.remaining_degrees.to_s,
               "\[\]")
relative_check("relative.kernel",
               certificate.kernel_checked?, true)

bad = false
begin
  NumberFieldPowerBasisPrimeReduction.new(k, 7, 2)
rescue error
  bad = true
relative_check("reduction.rejects_nonroot", bad, true)

<< "algebra_relative_irreducibility_spec: all checks passed"
