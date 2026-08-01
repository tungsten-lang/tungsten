# Point-divisor spaces and first Khuri--Makdisi products on the shell quartic.

use algebra

-> shell_c_ab_model(prime)
  field = FiniteField.new(prime)
  plane = ProjectiveSpace<FiniteField, 2>.new(
    Algebra.field(field), 2, [:B, :S, :Z])
  b = plane.coords[0]
  s = plane.coords[1]
  z = plane.coords[2]
  equation = (
    b**3*z*16 + b*s**2*z*48 -
    s**4*3 + s**3*z*8 +
    s**2*z**2*162 + z**4*729)
  Curve.new(plane, equation).c_ab_model(1, 0, 2, 3, 4)

-> shell_rational_curve
  plane = ProjectiveSpace<ℚ, 2>.new(:B, :S, :Z)
  b = plane.coords[0]
  s = plane.coords[1]
  z = plane.coords[2]
  equation = (
    b**3*z*16 + b*s**2*z*48 -
    s**4*3 + s**3*z*8 +
    s**2*z**2*162 + z**4*729)
  Curve.new(plane, equation)

-> quadratic_place_on_line(curve, coefficients)
  intersection = curve.line_intersection(Line.new(curve.space, coefficients))
  answer = nil
  intersection.divisor.terms.each -> (term)
    place = term[1]
    answer = place if place.class_name == "ClosedPlace" && place.degree == 2
  raise "quadratic place not found on shell line" if answer == nil
  answer

# Over F_5 the seven affine rational points give a minimal d0=2g+1 base
# divisor and hence a five-dimensional representative in L(14*infinity).
model5 = shell_c_ab_model(5)
points5 = model5.affine_rational_points
divisor5 = CAbEffectivePointDivisor.new(model5, points5)
raise "FAIL cab.divisor.certified" if !divisor5.certified?
<< "PASS cab.divisor.certified"
raise "FAIL cab.divisor.degree" if divisor5.degree != 7
<< "PASS cab.divisor.degree"
divisor_space5 = divisor5.function_space(14)
raise "FAIL cab.divisor_space.certified" if !divisor_space5.certified?
<< "PASS cab.divisor_space.certified"
raise "FAIL cab.divisor_space.dimension" if (
  divisor_space5.dimension != 5 || divisor_space5.codimension != 7)
<< "PASS cab.divisor_space.dimension"
raise "FAIL cab.divisor_space.independent" if (
  !divisor_space5.independent_conditions_certified?)
<< "PASS cab.divisor_space.independent"

representative5 = CAbKhuriMakdisiRepresentative.new(model5, divisor5)
raise "FAIL cab.km.certified" if !representative5.certified?
<< "PASS cab.km.certified"
raise "FAIL cab.km.dimension" if representative5.dimension != 5
<< "PASS cab.km.dimension"
raise "FAIL cab.km.class" if !representative5.class_description.include?(
  "D_7")
<< "PASS cab.km.class"

duplicate_failed = false
begin
  CAbEffectivePointDivisor.new(model5, [points5[0], points5[0]])
rescue error
  duplicate_failed = error.to_s.include?("squarefree")
raise "FAIL cab.divisor.duplicate_is_loud" if !duplicate_failed
<< "PASS cab.divisor.duplicate_is_loud"

small_base_failed = false
begin
  six_points = []
  index = 0
  while index < 6
    six_points.push(points5[index])
    index += 1
  CAbKhuriMakdisiRepresentative.new(
    model5, CAbEffectivePointDivisor.new(model5, six_points))
rescue error
  small_base_failed = error.to_s.include?("at least 2g+1")
raise "FAIL cab.km.small_base_is_loud" if !small_base_failed
<< "PASS cab.km.small_base_is_loud"

# F_17 has enough rational support for two disjoint degree-seven divisors.
# Their 5x5 function-space product is checked against the full twelve-
# dimensional evaluation kernel in L(28*infinity), not merely sampled.
q_curve = shell_rational_curve
model17 = q_curve.reduce(17).c_ab_model(1, 0, 2, 3, 4)
points17 = model17.affine_rational_points
raise "FAIL cab.km.f17_support" if points17.size < 14
<< "PASS cab.km.f17_support"
jacobian_order17 = model17.curve.zeta.numerator.at(1)
raise "FAIL cab.km.f17_jacobian_order" if jacobian_order17 != 6478
<< "PASS cab.km.f17_jacobian_order"

# The two residual conics defining E reduce to degree-two closed places at
# p=17.  Evaluation in each quadratic residue field must impose exactly two
# base-field linear conditions, rather than treating the conjugate pair as a
# single sampled point.
q_d9 = quadratic_place_on_line(q_curve, [0, 1, -9])
q_d0 = quadratic_place_on_line(q_curve, [2, 1, -3])
d9_reduction = q_d9.reduction(model17.curve)
d0_reduction = q_d0.reduction(model17.curve)
raise "FAIL cab.place_reduction.certified" if (
  !d9_reduction.certified? || !d0_reduction.certified?)
<< "PASS cab.place_reduction.certified"
raise "FAIL cab.place_reduction.factors" if (
  d9_reduction.reduced_factor.to_s != "B^2 + 3" ||
  d0_reduction.reduced_factor.degree != 2 ||
  d0_reduction.factorization.factors.size != 1)
<< "PASS cab.place_reduction.factors"
d9_divisor = CAbEffectivePlaceDivisor.new(model17, d9_reduction.divisor)
d0_divisor = CAbEffectivePlaceDivisor.new(model17, d0_reduction.divisor)
raise "FAIL cab.place_divisor.certified" if (
  !d9_divisor.certified? || !d0_divisor.certified?)
<< "PASS cab.place_divisor.certified"
raise "FAIL cab.place_divisor.degree" if (
  d9_divisor.degree != 2 || d0_divisor.degree != 2)
<< "PASS cab.place_divisor.degree"
d9_space = d9_divisor.function_space(14)
d0_space = d0_divisor.function_space(14)
raise "FAIL cab.place_space.certified" if (
  !d9_space.certified? || !d0_space.certified?)
<< "PASS cab.place_space.certified"
raise "FAIL cab.place_space.rows" if (
  d9_space.evaluation_kernel.evaluation_matrix.size != 2 ||
  d0_space.evaluation_kernel.evaluation_matrix.size != 2)
<< "PASS cab.place_space.rows"
raise "FAIL cab.place_space.dimension" if (
  d9_space.dimension != 10 || d9_space.codimension != 2 ||
  d0_space.dimension != 10 || d0_space.codimension != 2)
<< "PASS cab.place_space.dimension"

left_points = []
right_points = []
index = 0
while index < 7
  left_points.push(points17[index])
  right_points.push(points17[index + 7])
  index += 1
left_divisor = CAbEffectivePointDivisor.new(model17, left_points)
right_divisor = CAbEffectivePointDivisor.new(model17, right_points)
left = CAbKhuriMakdisiRepresentative.new(model17, left_divisor)
right = CAbKhuriMakdisiRepresentative.new(model17, right_divisor)
product = left.unreduced_product(right)
raise "FAIL cab.km.product_certified" if !product.certified?
<< "PASS cab.km.product_certified"
raise "FAIL cab.km.product_degree" if product.combined_divisor.degree != 14
<< "PASS cab.km.product_degree"
raise "FAIL cab.km.product_dimension" if product.dimension != 12
<< "PASS cab.km.product_dimension"
raise "FAIL cab.km.product_exact" if !product.function_subspace.same_subspace?(
  product.expected_divisor_space.function_subspace)
<< "PASS cab.km.product_exact"

zero17 = CAbKhuriMakdisiZero.new(model17, 7)
raise "FAIL cab.km.zero_certified" if !zero17.certified?
<< "PASS cab.km.zero_certified"
raise "FAIL cab.km.zero_dimension" if zero17.dimension != 5
<< "PASS cab.km.zero_dimension"

negative_sum = CAbKhuriMakdisiAddFlip.new(left, right)
raise "FAIL cab.km.addflip_certified" if !negative_sum.certified?
<< "PASS cab.km.addflip_certified"
raise "FAIL cab.km.addflip_sections" if (
  negative_sum.section_subspace.dimension != 5)
<< "PASS cab.km.addflip_sections"
raise "FAIL cab.km.addflip_division" if (
  !negative_sum.division.certified? || negative_sum.dimension != 5)
<< "PASS cab.km.addflip_division"
affine_zero17 = CAbKhuriMakdisiAffineZero.search(model17, 7)
raise "FAIL cab.km.affine_zero_certified" if !affine_zero17.certified?
<< "PASS cab.km.affine_zero_certified"
raise "FAIL cab.km.affine_zero_degree" if affine_zero17.divisor.degree != 7
<< "PASS cab.km.affine_zero_degree"
affine_zero_test17 = CAbKhuriMakdisiZeroTest.new(affine_zero17)
raise "FAIL cab.km.zero_test_identity" if (
  !affine_zero_test17.certified? || !affine_zero_test17.zero?)
<< "PASS cab.km.zero_test_identity"
zero_sum17 = CAbKhuriMakdisiSum.new(
  affine_zero17, affine_zero17, affine_zero17)
raise "FAIL cab.km.sum_identity" if (
  !zero_sum17.certified? || !CAbKhuriMakdisiZeroTest.new(zero_sum17).zero?)
<< "PASS cab.km.sum_identity"
zero_equality17 = CAbKhuriMakdisiEquality.new(
  affine_zero17, zero_sum17, affine_zero17)
raise "FAIL cab.km.equality_identity" if (
  !zero_equality17.certified? || !zero_equality17.equal?)
<< "PASS cab.km.equality_identity"
sum_representative = negative_sum.sum_representative(affine_zero17)
raise "FAIL cab.km.sum_certified" if !sum_representative.certified?
<< "PASS cab.km.sum_certified"
raise "FAIL cab.km.sum_dimension" if sum_representative.dimension != 5
<< "PASS cab.km.sum_dimension"

# Construct the two shell-width classes themselves in J(C)(F_17).  P is the
# rational difference [0:9:1]-[-3:-3:1].  E is the difference of the two
# reduced quadratic places D9-D0.  Common rational padding raises each signed
# divisor to d0=7 and cancels exactly in the three-AddFlip difference.
p_positive_place = model17.curve.place([0, 9, 1])
p_negative_place = model17.curve.place([-3, -3, 1])
p_padding_places = []
index = 0
while index < points17.size && p_padding_places.size < 6
  candidate = model17.curve.place(points17[index])
  if !candidate.eql?(p_positive_place) && (
       !candidate.eql?(p_negative_place))
    p_padding_places.push(candidate)
  index += 1
raise "FAIL cab.shell_image.padding_support" if p_padding_places.size != 6
<< "PASS cab.shell_image.padding_support"

p_positive = CAbEffectivePlaceDivisor.new(model17, [p_positive_place])
p_negative = CAbEffectivePlaceDivisor.new(model17, [p_negative_place])
p_padding = CAbEffectivePlaceDivisor.new(model17, p_padding_places)
p_image17 = CAbKhuriMakdisiPlaceDifference.new(
  model17, p_positive, p_negative, p_padding, affine_zero17)
raise "FAIL cab.shell_image.P_certified" if !p_image17.certified?
<< "PASS cab.shell_image.P_certified"
raise "FAIL cab.shell_image.P_dimension" if p_image17.dimension != 5
<< "PASS cab.shell_image.P_dimension"

e_padding_places = []
index = 0
while index < 5
  e_padding_places.push(p_padding_places[index])
  index += 1
e_padding = CAbEffectivePlaceDivisor.new(model17, e_padding_places)
e_image17 = CAbKhuriMakdisiPlaceDifference.new(
  model17, d9_divisor, d0_divisor, e_padding, affine_zero17)
raise "FAIL cab.shell_image.E_certified" if !e_image17.certified?
<< "PASS cab.shell_image.E_certified"
raise "FAIL cab.shell_image.E_dimension" if e_image17.dimension != 5
<< "PASS cab.shell_image.E_dimension"
raise "FAIL cab.shell_image.place_degree" if (
  e_image17.positive_divisor.degree != 2 ||
  e_image17.negative_divisor.degree != 2 ||
  e_image17.left_divisor.degree != 7 ||
  e_image17.right_divisor.degree != 7)
<< "PASS cab.shell_image.place_degree"
raise "FAIL cab.shell_image.P_nonzero" if (
  CAbKhuriMakdisiZeroTest.new(p_image17).zero?)
<< "PASS cab.shell_image.P_nonzero"
raise "FAIL cab.shell_image.E_nonzero" if (
  CAbKhuriMakdisiZeroTest.new(e_image17).zero?)
<< "PASS cab.shell_image.E_nonzero"
e_twice17 = CAbKhuriMakdisiScalarMultiple.new(
  e_image17, 2, affine_zero17)
raise "FAIL cab.shell_image.E_scalar_certified" if !e_twice17.certified?
<< "PASS cab.shell_image.E_scalar_certified"
raise "FAIL cab.shell_image.E_twice_nonzero" if e_twice17.zero?
<< "PASS cab.shell_image.E_twice_nonzero"
p_order17 = CAbKhuriMakdisiOrder.new(p_image17, affine_zero17)
e_order17 = CAbKhuriMakdisiOrder.new(e_image17, affine_zero17)
raise "FAIL cab.shell_image.orders_certified" if (
  !p_order17.certified? || !e_order17.certified?)
<< "PASS cab.shell_image.orders_certified"
raise "FAIL cab.shell_image.P_order" if p_order17.order != 6478
<< "PASS cab.shell_image.P_order"
raise "FAIL cab.shell_image.E_order" if e_order17.order != 6478
<< "PASS cab.shell_image.E_order"
p_nondivisibility17 = CAbKhuriMakdisiNondivisibility.new(p_order17)
nondivisibility_primes = p_nondivisibility17.primes
nondivisibility_odd_primes = p_nondivisibility17.odd_primes
nondivisibility_failure = (
  "FAIL cab.shell_image.P_nondivisibility " +
  nondivisibility_primes.to_s + " / " +
  nondivisibility_odd_primes.to_s)
raise nondivisibility_failure if (
  !p_nondivisibility17.certified? ||
  nondivisibility_primes.size != 3 ||
  nondivisibility_primes[0] != 2 ||
  nondivisibility_primes[1] != 41 ||
  nondivisibility_primes[2] != 79 ||
  nondivisibility_odd_primes.size != 2 ||
  nondivisibility_odd_primes[0] != 41 ||
  nondivisibility_odd_primes[1] != 79)
<< "PASS cab.shell_image.P_nondivisibility"
p_e_equality17 = CAbKhuriMakdisiEquality.new(
  p_image17, e_image17, affine_zero17)
raise "FAIL cab.shell_image.P_E_distinct" if (
  !p_e_equality17.certified? || p_e_equality17.equal?)
<< "PASS cab.shell_image.P_E_distinct"

overlap_failed = false
begin
  left.unreduced_product(left)
rescue error
  overlap_failed = error.to_s.include?("disjoint support")
raise "FAIL cab.km.overlap_is_loud" if !overlap_failed
<< "PASS cab.km.overlap_is_loud"

<< "algebra_c_ab_divisors_spec: all checks passed"
