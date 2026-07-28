# Certified reciprocal-Weil-sextic Galois groups.
# Run both ways:
#   bin/tungsten run spec/core/algebra_galois_spec.w
#   bin/tungsten compile spec/core/algebra_galois_spec.w --out /tmp/algebra-galois-spec

use algebra

-> check(name, got, want)
  if got != want
    raise "FAIL " + name + " got " + got.to_s + " want " + want.to_s
  << "PASS " + name

ring = PolynomialRing.new([:x], RationalField.new)
x = ring.generator(0)

# Point counts (8,34,122) give the canonical p=5 numerator.
l5 = IntegerPolynomial.new([1, 2, 6, 8, 30, 50, 125])
check("weil5.irreducible", l5.irreducible?, true)
g5 = l5.galois_group
c5 = g5.certificate
check("weil5.name", g5.name, "W(C3)")
check("weil5.order", g5.order, 48)
check("weil5.certified", g5.certified?, true)
check("weil5.q", c5.q, 5)
check("weil5.real_cubic", c5.real_weil_cubic.coefficients.to_s,
      [Rational.new(-12), Rational.new(-9),
       Rational.new(2), Rational.new(1)].to_s)
check("weil5.real_group", c5.real_cubic_group.name, "S3")
check("weil5.real_discriminant", c5.real_cubic_discriminant, 3624)
check("weil5.kummer_rank", c5.kummer_rank, 3)
check("weil5.relations", c5.relation_basis.size, 0)
check("weil5.sextic_modular_certificate",
      c5.sextic_irreducibility.verified?, true)
check("weil5.sextic_witness_prime", c5.sextic_irreducibility.prime, 13)
check("weil5.cubic_modular_certificate",
      c5.cubic_irreducibility.verified?, true)
check("weil5.cubic_witness_prime", c5.cubic_irreducibility.prime, 5)

# Independently counted over F_(47^n):
#   #C(F_47)=60, #C(F_(47^2))=2348, #C(F_(47^3))=103668.
# The real cubic has square polynomial discriminant 331776 = 576^2 (its
# maximal-order field discriminant is 81), so Gal(h)=A3.  The three quadratic
# classes remain independent and the full sextic group has order 8*3=24.
l47_coefficients = [1, 12, 141, 1064, 6627, 26508, 103823]
l47 = IntegerPolynomial.new(l47_coefficients)
check("weil47.irreducible", l47.irreducible?, true)
g47 = l47.galois_group
c47 = g47.certificate
check("weil47.name", g47.name, "C2×A4")
check("weil47.order", g47.order, 24)
check("weil47.certified", g47.certified?, true)
check("weil47.q", c47.q, 47)
check("weil47.real_cubic", c47.real_weil_cubic.coefficients.to_s,
      [Rational.new(-64), Rational.new(0),
       Rational.new(12), Rational.new(1)].to_s)
check("weil47.real_group", c47.real_cubic_group.name, "A3")
check("weil47.real_discriminant", c47.real_cubic_discriminant, 331776)
check("weil47.kummer_rank", c47.kummer_rank, 3)
check("weil47.sextic_witness_prime", c47.sextic_irreducibility.prime, 5)
check("weil47.cubic_witness_prime", c47.cubic_irreducibility.prime, 5)

# The same focused classifier accepts an ordinary Q-polynomial.
l47_polynomial = ring.zero
i = 0
while i < l47_coefficients.size
  l47_polynomial = l47_polynomial + x**i * l47_coefficients[i]
  i += 1
check("weil47.rational_polynomial", l47_polynomial.galois_group.order, 24)

# A genuine q=2 Weil polynomial with a two-dimensional square-class relation
# plane exercises the smaller diagonal C2 kernel: |Gal| = 2*|S3| = 12.
smaller_kernel = IntegerPolynomial.new([1, 2, 0, -3, 0, 8, 8])
smaller_group = smaller_kernel.galois_group
check("weil.smaller_kernel.order", smaller_group.order, 12)
check("weil.smaller_kernel.rank", smaller_group.certificate.kummer_rank, 1)
check("weil.smaller_kernel.relations",
      smaller_group.certificate.relation_dimension, 2)
check("weil.smaller_kernel.certified", smaller_group.certified?, true)

# Reopening Polynomial#galois_group must not disturb the existing exact
# degree-at-most-three classifier.
check("low_degree_galois_stable", (x**3 - 2).galois_group.name, "S3")

bad_reciprocity = false
begin
  IntegerPolynomial.new([1, 2, 6, 8, 31, 50, 125]).galois_group
rescue error
  bad_reciprocity = error.to_s.include?("q-reciprocal")
check("weil.reject_nonreciprocal", bad_reciprocity, true)

non_weil_bounds = false
begin
  IntegerPolynomial.new([1, 8, -6, 48, -12, 32, 8]).galois_group
rescue error
  non_weil_bounds = error.to_s.include?("real Weil cubic")
check("weil.reject_non_weil_roots", non_weil_bounds, true)

# A deliberately reducible reciprocal sextic has no irreducible-mod-p
# certificate.  The focused path reports unknown instead of guessing a group.
reducible_unknown = false
begin
  ((x**2 * 5 - x + 1)**3).galois_group
rescue error
  reducible_unknown = error.to_s.include?("irreducibility is unknown")
check("weil.reducible_is_loud", reducible_unknown, true)
