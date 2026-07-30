# Exact arbitrary-degree number-field regressions.
# Run both ways:
#   bin/tungsten run spec/core/algebra_number_field_spec.w
#   bin/tungsten compile spec/core/algebra_number_field_spec.w --out /tmp/algebra-number-field-spec

use algebra
use core/algebra/number_field

-> number_field_check(name, got, want)
  equal = got == want
  if got.class_name == "Polynomial"
    equal = got.eql?(want)
  elsif got.class_name == "NumberFieldElement"
    equal = got.eql?(want)
  if !equal
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

x = Poly<ℚ>.new(:x).generator

# The real Weil cubic at p=5 is already maximal.
h5 = x**3 + x**2*2 - x*9 - 12
k5 = NumberField.new(h5, :a)
a = k5.generator
number_field_check("h5.defining_polynomial", k5.defining_polynomial, h5)
number_field_check("h5.power_basis_discriminant",
                   k5.power_basis_discriminant, Rational.new(3624))
number_field_check("h5.field_discriminant", k5.field_discriminant, 3624)
number_field_check("h5.discriminant_alias", k5.discriminant, 3624)
number_field_check("h5.maximal_order_index", k5.maximal_order_index, 1)
number_field_check("h5.irreducibility_certified",
                   k5.irreducibility_certified?, true)
number_field_check("h5.field_discriminant_certified",
                   k5.field_discriminant_certified?, true)
number_field_check("h5.signature", k5.signature.to_s, "\[3, 0\]")
number_field_check("h5.totally_real", k5.totally_real?, true)
number_field_check("h5.generator_relation", k5.evaluate(h5, a), k5.zero)
number_field_check("h5.inverse", a * a.inverse, k5.one)
number_field_check("h5.division", (a + 1) / (a + 1), k5.one)
number_field_check("h5.integral_basis_size", k5.integral_basis.size, 3)

# NumberField implements the Field protocol, so exact polynomial arithmetic
# over the quotient field uses the same ring layer as Q and finite fields.
ka_ring = PolynomialRing.new([:u], k5)
u = ka_ring.generator(0)
number_field_check("h5.polynomial_ring",
                   (u + a) * (u - a), u**2 - ka_ring.constant(a*a))

# At p=7 the power order has index four: 3664 / 4^2 = 229. This is the
# motivating test that distinguishes maximal-order discriminants from simply
# returning the polynomial discriminant.
h7 = x**3 + x**2*2 - x*11 + 4
k7 = NumberField.new(h7, :b)
number_field_check("h7.power_basis_discriminant",
                   k7.power_basis_discriminant, Rational.new(3664))
number_field_check("h7.integral_power_basis_discriminant",
                   k7.integral_power_basis_discriminant, 3664)
number_field_check("h7.maximal_order_index", k7.maximal_order_index, 4)
number_field_check("h7.field_discriminant", k7.field_discriminant, 229)
number_field_check("h7.polynomial_field_discriminant",
                   h7.field_discriminant, 229)
number_field_check("h7.totally_real", k7.totally_real?, true)

# At p=47, the power-basis discriminant has square divisor 576^2, but an
# index-576 overorder would have field discriminant 1 and is impossible by
# Minkowski's bound. The local maximal-order certificate exhausts every
# index-p and index-p^2 overorder at each step: a minimal S/R has R+nS as an
# intermediate order, so S/R is elementary p, and its dimension is at most
# two because 1 is already primitive in the rank-three order. It finds the
# maximal basis [1, a/4, a^2/16], of index 64 and discriminant 81.
h47 = x**3 + x**2*12 - 64
k47 = NumberField.new(h47, :d)
number_field_check("h47.power_basis_discriminant",
                   k47.power_basis_discriminant, Rational.new(331776))
number_field_check("h47.integral_power_basis_discriminant",
                   k47.integral_power_basis_discriminant, 331776)
number_field_check("h47.maximal_order_index", k47.maximal_order_index, 64)
number_field_check("h47.field_discriminant", k47.field_discriminant, 81)
number_field_check("h47.polynomial_field_discriminant",
                   h47.field_discriminant, 81)
number_field_check("h47.totally_real", k47.totally_real?, true)
number_field_check("h47.integral_basis.1",
                   k47.integral_basis[1], k47.generator / 4)
number_field_check("h47.integral_basis.2",
                   k47.integral_basis[2], k47.generator**2 / 16)

# A nonmonic rational cubic is converted to an integral generator without
# changing the quotient generator exposed to the caller.
nonmonic = x**3*2 + x + 1
nonmonic_field = NumberField.new(nonmonic, :n)
number_field_check("nonmonic.defining_polynomial",
                   nonmonic_field.defining_polynomial,
                   x**3 + x*Rational.new(1, 2) + Rational.new(1, 2))
number_field_check("nonmonic.power_basis_discriminant",
                   nonmonic_field.power_basis_discriminant,
                   Rational.new(-29, 4))
number_field_check("nonmonic.integral_polynomial",
                   nonmonic_field.integral_defining_polynomial,
                   x**3 + x*2 + 4)
number_field_check("nonmonic.field_discriminant",
                   nonmonic_field.field_discriminant, -116)
number_field_check("nonmonic.generator_relation",
                   nonmonic_field.evaluate(nonmonic, nonmonic_field.generator),
                   nonmonic_field.zero)

# Different certified field discriminants rule out a root in K immediately;
# the defining cubic has exactly one root in its non-Galois cubic field.
roots5 = h5.roots_in(k5)
number_field_check("roots.same_field.size", roots5.size, 1)
number_field_check("roots.same_field.value",
                   k5.evaluate(h5, roots5[0]), k5.zero)
number_field_check("roots.different_field", h7.roots_in(k5).size, 0)

# A cyclic irreducible cubic has all three roots in its own field. The square
# discriminant gives the other two through the exact Vandermonde identity.
cyclic = x**3 - x*3 + 1
cyclic_field = NumberField.new(cyclic, :c)
cyclic_roots = cyclic.roots_in(cyclic_field)
number_field_check("cyclic.discriminant", cyclic.discriminant, Rational.new(81))
number_field_check("cyclic.root_count", cyclic_roots.size, 3)
cyclic_roots.each -> (root)
  number_field_check("cyclic.root_relation",
                     cyclic_field.evaluate(cyclic, root), cyclic_field.zero)

# Sturm counts certify signatures without floating-point root approximations.
one_real = x**3 - 2
one_real_field = NumberField.new(one_real, :r)
number_field_check("sturm.three_real", cyclic.real_root_count, 3)
number_field_check("sturm.one_real", one_real.real_root_count, 1)
number_field_check("signature.one_real", one_real_field.signature.to_s, "\[1, 1\]")
number_field_check("signature.not_totally_real", one_real_field.totally_real?, false)

# Quotient-field arithmetic is degree-generic. Cubic-only maximal-order
# capabilities remain explicit instead of returning a power-order value under
# the field-discriminant name.
quadratic = x**2 + 1
quadratic_field = NumberField.new(quadratic, :i)
i = quadratic_field.generator
number_field_check("quadratic.degree", quadratic_field.degree, 2)
number_field_check("quadratic.relation", i**2, -1)
number_field_check("quadratic.inverse",
                   (i + 1) * (i + 1).inverse, quadratic_field.one)
number_field_check("quadratic.signature",
                   quadratic_field.signature.to_s, "\[0, 1\]")
number_field_check("quadratic.power_basis_size",
                   quadratic_field.power_basis.size, 2)
number_field_check("quadratic.generator_minpoly",
                   i.minimal_polynomial, quadratic)
number_field_check("quadratic.generator_minpoly_certificate",
                   i.minimal_polynomial_certificate.verified?, true)
number_field_check("quadratic.trace", i.trace, Rational.new(0))
number_field_check("quadratic.norm", i.norm, Rational.new(1))
number_field_check("quadratic.integral", i.integral?, true)
number_field_check("quadratic.nonintegral_rational",
                   quadratic_field.coerce(Rational.new(1, 2)).integral?, false)

sqrt2_field = NumberField.new(x**2 - 2, :s)
real_embeddings = sqrt2_field.real_embeddings
number_field_check("quadratic.real_embedding_count",
                   real_embeddings.size, 2)
number_field_check("quadratic.real_embedding_certificate",
                   real_embeddings[0].verified?, true)
number_field_check("quadratic.real_embedding_generator",
                   real_embeddings[1].image(sqrt2_field.generator),
                   real_embeddings[1].root)

quartic = x**4 + 1
quartic_field = NumberField.new(quartic, :q)
q = quartic_field.generator
number_field_check("quartic.degree", quartic_field.degree, 4)
number_field_check("quartic.relation", q**4, -1)
number_field_check("quartic.inverse",
                   (q**3 + q + 1) * (q**3 + q + 1).inverse,
                   quartic_field.one)
number_field_check("quartic.signature",
                   quartic_field.signature.to_s, "\[0, 2\]")
number_field_check("quartic.power_basis_discriminant",
                   quartic_field.power_basis_discriminant, Rational.new(256))
number_field_check("quartic.power_basis_discriminant_certified",
                   quartic_field.power_basis_discriminant_certified?, true)
number_field_check("quartic.field_discriminant_not_certified",
                   quartic_field.field_discriminant_certified?, false)
number_field_check("quartic.maximal_order_not_certified",
                   quartic_field.maximal_order_certified?, false)

quadratic_subfield_element = q + q**3
number_field_check("quartic.element_minpoly",
                   quadratic_subfield_element.minimal_polynomial, x**2 + 2)
number_field_check("quartic.element_charpoly",
                   quadratic_subfield_element.characteristic_polynomial,
                   x**4 + x**2*4 + 4)
number_field_check("quartic.element_minpoly_certificate",
                   quadratic_subfield_element.minimal_polynomial_certificate.verified?,
                   true)
nonminimal_certificate = NumberFieldMinimalPolynomialCertificate.new(
  quartic_field, quadratic_subfield_element,
  quadratic_subfield_element.characteristic_polynomial)
number_field_check("quartic.element_minpoly_certificate_rejects_charpoly",
                   nonminimal_certificate.verified?, false)
number_field_check("quartic.element_trace",
                   quadratic_subfield_element.trace, Rational.new(0))
number_field_check("quartic.element_norm",
                   quadratic_subfield_element.norm, Rational.new(4))

# NumberField is an actual Field object at the polynomial/projective layers,
# while NumberField remains the compile-time family tag.
quartic_poly = Poly<NumberField>.new(
  Algebra.field(quartic_field), [:u])
u4 = quartic_poly.generator
number_field_check("quartic.poly_field",
                   (u4 + q) * (u4 - q),
                   u4**2 - quartic_poly.ring.constant(q*q))
quartic_plane = ProjectiveSpace<NumberField, 2>.new(
  Algebra.field(quartic_field), 2, [:X, :Y, :Z])
quartic_point = quartic_plane.point([q, 1, 0])
number_field_check("quartic.projective_field",
                   quartic_plane.field, quartic_field)
number_field_check("quartic.projective_normalized_pivot",
                   quartic_point[0], quartic_field.one)

quintic = x**5 - 2
quintic_field = NumberField.new(quintic, :v)
v = quintic_field.generator
number_field_check("quintic.degree", quintic_field.degree, 5)
number_field_check("quintic.relation", v**5, 2)
number_field_check("quintic.inverse",
                   (v + 1) / (v + 1), quintic_field.one)
number_field_check("quintic.signature",
                   quintic_field.signature.to_s, "\[1, 2\]")
number_field_check("quintic.generator_norm", v.norm, Rational.new(2))

field_mismatch_failed = false
begin
  q + sqrt2_field.generator
rescue error
  field_mismatch_failed = "[error]".include?(
    "number-field elements belong to different fields")
number_field_check("number_field_mismatch_is_loud",
                   field_mismatch_failed, true)

noncubic_discriminant_failed = false
begin
  quartic_field.discriminant
rescue error
  noncubic_discriminant_failed = "[error]".include?(
    "certified only for cubic number fields")
number_field_check("noncubic_field_discriminant_is_loud",
                   noncubic_discriminant_failed, true)

noncubic_roots_failed = false
begin
  quartic.roots_in(quartic_field)
rescue error
  noncubic_roots_failed = "[error]".include?(
    "complete only for cubic number fields")
number_field_check("noncubic_roots_in_is_loud",
                   noncubic_roots_failed, true)

reducible_failed = false
begin
  NumberField.new(x**3 - x)
rescue error
  reducible_failed = "[error]".include?("reducible over ℚ")
number_field_check("reducible_is_loud", reducible_failed, true)

wrong_degree_failed = false
begin
  NumberField.new(x + 1)
rescue error
  wrong_degree_failed = "[error]".include?("degree at least two")
number_field_check("wrong_degree_is_loud", wrong_degree_failed, true)

reducible_quartic_failed = false
begin
  NumberField.new(x**4 - 1)
rescue error
  reducible_quartic_failed = "[error]".include?("reducible over ℚ")
number_field_check("reducible_quartic_is_loud",
                   reducible_quartic_failed, true)

unknown_failed = false
begin
  NumberField.certify_irreducible_cubic(x**3 + x + 1, 0)
rescue error
  unknown_failed = "[error]".include?("reducibility unknown")
number_field_check("resource_unknown_is_loud", unknown_failed, true)

higher_degree_unknown_failed = false
begin
  NumberField.certify_irreducible(x**4 + 1, 0)
rescue error
  higher_degree_unknown_failed = "[error]".include?(
    "Kronecker factor search limit exceeded")
number_field_check("higher_degree_resource_unknown_is_loud",
                   higher_degree_unknown_failed, true)

<< "algebra_number_field_spec: all checks passed"
