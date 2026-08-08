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

# Ideal intersection: (x) ∩ (y) = (x y), including neutral/absorbing edges.
x_ideal = Ideal.new([x])
y_ideal = Ideal.new([y])
axes_union = x_ideal.intersection(y_ideal)
check("intersection.contains_product", axes_union.contains?(x * y), true)
check("intersection.excludes_x", axes_union.contains?(x), false)
check("intersection.excludes_y", axes_union.contains?(y), false)
check("intersection.basis", axes_union.basis[0], x * y)
check("intersection.unit_neutral", x_ideal.intersect(Ideal.unit(ring)), x_ideal)
check("intersection.zero_absorbing", x_ideal.intersect(zero), zero)

# Products distribute over the displayed generators.
coordinate_ideal = Ideal.new([x, y])
coordinate_square = coordinate_ideal
coordinate_square = coordinate_square * coordinate_ideal
check("product.contains_x2", coordinate_square.contains?(x**2), true)
check("product.contains_xy", coordinate_square.contains?(x * y), true)
check("product.contains_y2", coordinate_square.contains?(y**2), true)
check("product.excludes_x", coordinate_square.contains?(x), false)

# Saturation by J=(x,y) is the intersection of the two principal saturations.
# It is not sequential saturation by x and then y: for I=(xy), the true result
# remains (xy), while sequential saturation would incorrectly return (1).
by_coordinates = product_ideal.saturate(coordinate_ideal)
check("ideal_saturation.contains_product",
      by_coordinates.contains?(x * y), true)
check("ideal_saturation.excludes_x", by_coordinates.contains?(x), false)
check("ideal_saturation.excludes_y", by_coordinates.contains?(y), false)
check("ideal_saturation.basis", by_coordinates.basis[0], x * y)

# The result depends only on J, not its displayed generators.
same_coordinates = Ideal.new([x, x + y])
check("ideal_saturation.generator_invariant",
      product_ideal.saturate(same_coordinates), by_coordinates)

# Irrelevant saturation removes an embedded component at the origin but keeps
# projective components visible in a coordinate chart.
embedded_origin = Ideal.new([x**2, x * y])
check("principal_quotient.differs_from_saturation",
      embedded_origin.colon(x), coordinate_ideal)
check("principal_saturation.reaches_unit",
      embedded_origin.saturate(x).unit?, true)
check("ideal_quotient.recovers_factor",
      embedded_origin.colon(coordinate_ideal), x_ideal)
check("ideal_quotient.generator_invariant",
      embedded_origin.colon(same_coordinates), x_ideal)
check("ideal_quotient.product_inverse",
      (x_ideal * coordinate_ideal).quotient(coordinate_ideal), x_ideal)
check("ideal_quotient.zero_denominator",
      x_ideal.quotient(zero).unit?, true)
check("ideal_quotient.unit_denominator",
      x_ideal.quotient(Ideal.unit(ring)), x_ideal)
check("irrelevant_saturation.removes_embedded_origin",
      embedded_origin.saturate_irrelevant, x_ideal)
check("irrelevant_saturation.keeps_axes",
      product_ideal.saturate_irrelevant, product_ideal)
check("irrelevant_saturation.empty_projective_scheme",
      coordinate_ideal.saturate_irrelevant.unit?, true)
check("irrelevant_saturation.zero_stays_zero",
      zero.saturate_irrelevant.zero?, true)

intersection_mismatch = false
begin
  x_ideal.intersection(Ideal.new([other_ring.generator(0)]))
rescue error
  intersection_mismatch = error.to_s.include?("different rings")
check("intersection.ring_mismatch_raises", intersection_mismatch, true)

saturation_mismatch = false
begin
  x_ideal.saturate(Ideal.new([other_ring.generator(0)]))
rescue error
  saturation_mismatch = error.to_s.include?("different ring")
check("ideal_saturation.ring_mismatch_raises", saturation_mismatch, true)

product_mismatch = false
begin
  x_ideal.product(Ideal.new([other_ring.generator(0)]))
rescue error
  product_mismatch = error.to_s.include?("different rings")
check("product.ring_mismatch_raises", product_mismatch, true)

quotient_mismatch = false
begin
  x_ideal.quotient(Ideal.new([other_ring.generator(0)]))
rescue error
  quotient_mismatch = error.to_s.include?("different ring")
check("ideal_quotient.ring_mismatch_raises", quotient_mismatch, true)

# Auxiliary elimination tags are fresh even when users choose the internal
# stem names as coordinates.
collision_ring = PolynomialRing.new(
  ["__t".to_sym, "__intersection_t".to_sym],
  RationalField.new, :lex)
tag_x, tag_y = collision_ring.generators
tag_product = Ideal.new([tag_x * tag_y])
check("auxiliary_name.intersection_collision",
      Ideal.new([tag_x]).intersect(Ideal.new([tag_y])), tag_product)
check("auxiliary_name.saturation_collision",
      tag_product.saturate(tag_x), Ideal.new([tag_y]))

# The outer eliminating block composes with a non-lex caller order.
grev_ring = PolynomialRing.new(
  [:a, :b], RationalField.new, :grevlex)
grev_a, grev_b = grev_ring.generators
grev_a_ideal = Ideal.new([grev_a])
grev_b_ideal = Ideal.new([grev_b])
check("grevlex.intersection",
      grev_a_ideal.intersect(grev_b_ideal),
      Ideal.new([grev_a * grev_b]))
grev_embedded = Ideal.new([grev_a**2, grev_a * grev_b])
check("grevlex.quotient",
      grev_embedded.colon(grev_a),
      Ideal.new([grev_a, grev_b]))
check("grevlex.irrelevant_saturation",
      grev_embedded.saturate_irrelevant, grev_a_ideal)

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
