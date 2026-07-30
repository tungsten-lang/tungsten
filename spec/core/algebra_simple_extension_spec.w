# Exact certified simple extensions K[a]/(m), including finite towers and
# polynomial/geometry interoperability.
#
# Run both ways:
#   bin/tungsten run spec/core/algebra_simple_extension_spec.w
#   bin/tungsten compile spec/core/algebra_simple_extension_spec.w --out /tmp/algebra-simple-extension-spec

use algebra

-> extension_check(name, got, want)
  equal = got == want
  if got.class_name == "Polynomial" && want.class_name == "Polynomial"
    equal = got.eql?(want)
  elsif got.class_name == "SimpleExtensionElement"
    equal = got.eql?(want)
  elsif got.class_name == "ProjectivePoint" && want.class_name == "ProjectivePoint"
    equal = got == want
  elsif got.class_name == "Array" && want.class_name == "Array"
    equal = got.to_s == want.to_s
  if !equal
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

# A simple presentation of F4 over F2.
f2 = FiniteField.new(2)
r2 = PolynomialRing.new([:t], f2)
t2 = r2.generator(0)
e4 = SimpleExtensionField.new(t2**2 + t2 + 1, :a)
a4 = e4.generator

extension_check("F4.base", e4.base_field, f2)
extension_check("F4.relative_degree", e4.relative_degree, 2)
extension_check("F4.absolute_degree", e4.absolute_degree, 2)
extension_check("F4.order", e4.order, 4)
extension_check("F4.characteristic", e4.characteristic, 2)
extension_check("F4.finite", e4.finite_field?, true)
extension_check("F4.modulus_certificate",
                e4.modulus_certificate.verified?, true)
extension_check("F4.generator_relation", a4**2 + a4 + 1, e4.zero)
extension_check("F4.inverse", a4 * a4.inverse, e4.one)
extension_check("F4.power_basis", e4.power_basis.size, 2)
extension_check("F4.frobenius_period", e4.frobenius(a4, 2), a4)
extension_check("F4.inverse_frobenius",
                e4.inverse_frobenius(e4.frobenius(a4)), a4)
extension_check("F4.relative_trace", e4.relative_trace(a4), f2.one)
extension_check("F4.relative_norm", e4.relative_norm(a4), f2.one)
extension_check("F4.trace", e4.trace(a4), f2.one)
extension_check("F4.norm", e4.norm(a4), f2.one)

elements4 = []
e4.each_element -> elements4.push(item)
extension_check("F4.enumeration.count", elements4.size, 4)
distinct_products = true
elements4.each -> (left)
  if !left.zero?
    distinct_products = false if !(left * left.inverse).one?
extension_check("F4.enumeration.inverses", distinct_products, true)

# A genuine tower F4[b]/(b²+b+a) = F16. Raw embedding is distinct from
# external integer coercion: Integer 2 is zero in characteristic two, while
# the packed base-field residue 2 represents a.
f4_packed = FiniteField.extension(2, 2)
r4 = PolynomialRing.new([:u], f4_packed)
u4 = r4.generator(0)
a4_raw = f4_packed.generator
a4_constant = r4.monomial_raw(a4_raw, r4.zero_exponents)
modulus16 = u4**2 + u4 + a4_constant
e16 = SimpleExtensionField.new(modulus16, :b)
b16 = e16.generator
embedded_a4 = e16.embed_base_element(a4_raw)

extension_check("F16.base", e16.base_field, f4_packed)
extension_check("F16.relative_degree", e16.relative_degree, 2)
extension_check("F16.absolute_degree", e16.absolute_degree, 4)
extension_check("F16.order", e16.order, 16)
extension_check("F16.generator_relation",
                b16**2 + b16 + embedded_a4, e16.zero)
extension_check("F16.external_integer_is_prime_scalar",
                e16.coerce(2), e16.zero)
extension_check("F16.raw_base_embedding_nonzero",
                embedded_a4.zero?, false)
extension_check("F16.inverse", b16 * b16.inverse, e16.one)
extension_check("F16.frobenius_period", e16.frobenius(b16, 4), b16)
extension_check("F16.relative_trace",
                e16.relative_trace(b16), f4_packed.one)
extension_check("F16.relative_norm",
                e16.relative_norm(b16), a4_raw)
extension_check("F16.trace", e16.trace(b16), f4_packed.one)
extension_check("F16.norm", e16.norm(b16), a4_raw)

# Base change uses Field#embed_from, preserving the packed F4 coefficient.
source_polynomial = u4 + a4_constant
target_ring = PolynomialRing.new([:u], e16)
changed_polynomial = source_polynomial.change_ring(target_ring)
extension_check("F16.change_ring.raw_coefficient",
                changed_polynomial.coeff(0), embedded_a4)

# Finite-field factorization works over the structured tower field too.
x16_ring = PolynomialRing.new([:x], e16)
x16 = x16_ring.generator(0)
split16 = (x16 + b16) * (x16 + b16 + 1)
split16_factors = split16.factor
extension_check("F16.factor.count", split16_factors.size, 2)
extension_check("F16.factor.degrees",
                split16_factors.map -> item.degree, [1, 1])
extension_check("F16.factor.product",
                split16_factors[0] * split16_factors[1], split16)

determinant16 = Algebra.determinant_raw(
  [[e16.one, b16], [embedded_a4, e16.one]], e16)
expected_determinant16 = e16.one - b16*embedded_a4
extension_check("F16.determinant",
                determinant16, expected_determinant16)

plane16 = ProjectiveSpace<FiniteField, 2>.new(
  Algebra.field(e16), 2, [:X, :Y, :Z])
projective16 = plane16.point_raw(
  [b16, embedded_a4, e16.zero])
extension_check("F16.projective.normalized_pivot",
                projective16.coordinates[0], e16.one)

# Finite geometry enumerates structured elements through the field protocol,
# rather than assuming packed Integer residues. A smooth projective conic has
# q+1 rational points.
plane4 = ProjectiveSpace<SimpleExtensionField, 2>.new(
  Algebra.field(e4), 2, [:X, :Y, :Z])
x4_geo = plane4.coords[0]
y4_geo = plane4.coords[1]
z4_geo = plane4.coords[2]
conic4 = Curve.new(plane4, x4_geo*z4_geo - y4_geo**2)
extension_check("F4.geometry.point_count", conic4.point_count, 5)

# The same quotient abstraction works over Q; NumberField remains the richer
# Q-specific API when maximal-order arithmetic is wanted.
rq = PolynomialRing.new([:s], RationalField.new)
sq = rq.generator(0)
q_sqrt2 = SimpleExtensionField.new(sq**2 - 2, :r)
r_sqrt2 = q_sqrt2.generator
extension_check("Qsqrt2.finite", q_sqrt2.finite_field?, false)
extension_check("Qsqrt2.degree", q_sqrt2.degree, 2)
extension_check("Qsqrt2.relation", r_sqrt2**2, q_sqrt2.coerce(2))
extension_check("Qsqrt2.inverse",
                r_sqrt2 * r_sqrt2.inverse, q_sqrt2.one)
extension_check("Qsqrt2.trace",
                q_sqrt2.trace(r_sqrt2), Rational.new(0))
extension_check("Qsqrt2.norm",
                q_sqrt2.norm(r_sqrt2), Rational.new(-2))
extension_check("Qsqrt2.modulus_certificate",
                q_sqrt2.modulus_certificate.certified?, true)

reducible_failed = false
begin
  SimpleExtensionField.new(sq**2 - 1)
rescue error
  reducible_failed = "[error]".include?("reducible")
extension_check("reducible_is_loud", reducible_failed, true)

# Absolute packed fields do not pretend to have a canonical embedding from a
# differently presented non-prime field.
embedding_failed = false
begin
  target_absolute = FiniteField.extension(2, 4)
  target_absolute.embed_from(f4_packed, a4_raw)
rescue error
  embedding_failed = "[error]".include?("no certified field embedding")
extension_check("uncertified_embedding_is_loud", embedding_failed, true)

<< "algebra_simple_extension_spec: all checks passed"
