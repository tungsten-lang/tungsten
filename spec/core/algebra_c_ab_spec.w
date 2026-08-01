# Exact C_ab one-point function spaces for the shell-width plane quartic.

use algebra

field = FiniteField.new(5)
space = ProjectiveSpace<FiniteField, 2>.new(
  Algebra.field(field), 2, [:B, :S, :Z])
B = space.coords[0]
S = space.coords[1]
Z = space.coords[2]
equation = (
  B**3*Z*16 + B*S**2*Z*48 -
  S**4*3 + S**3*Z*8 +
  S**2*Z**2*162 + Z**4*729)
curve = Curve.new(space, equation)

# At the unique point [1:0:0], S and B have pole orders 3 and 4.
model = curve.c_ab_model(1, 0, 2, 3, 4)
raise "FAIL cab.shell.affine_point_count" if (
  model.affine_rational_points.size != 7)
<< "PASS cab.shell.affine_point_count"
raise "FAIL cab.shell.certified" if !model.certified?
<< "PASS cab.shell.certified"
raise "FAIL cab.shell.genus" if model.genus != 3
<< "PASS cab.shell.genus"
raise "FAIL cab.shell.infinity" if (
  model.infinity_point != space.point(1, 0, 0))
<< "PASS cab.shell.infinity"
raise "FAIL cab.shell.relation_reduces" if !model.reduce(
  model.affine_equation).zero?
<< "PASS cab.shell.relation_reduces"
raise "FAIL cab.shell.relation.y_degree" if (
  model.relation_rhs.degree_in(1) >= 3)
<< "PASS cab.shell.relation.y_degree"

l0 = model.riemann_roch_space(0)
l3 = model.riemann_roch_space(3)
l4 = model.riemann_roch_space(4)
l5 = model.riemann_roch_space(5)
l14 = model.riemann_roch_space(14)
raise "FAIL cab.L0.dimension" if l0.dimension != 1
<< "PASS cab.L0.dimension"
raise "FAIL cab.L3.dimension" if l3.dimension != 2
<< "PASS cab.L3.dimension"
raise "FAIL cab.L4.dimension" if l4.dimension != 3
<< "PASS cab.L4.dimension"
raise "FAIL cab.gap5.dimension" if l5.dimension != 3
<< "PASS cab.gap5.dimension"
raise "FAIL cab.L14.dimension" if l14.dimension != 12
<< "PASS cab.L14.dimension"
raise "FAIL cab.L14.riemann_roch" if l14.dimension != 14 + 1 - 3
<< "PASS cab.L14.riemann_roch"
raise "FAIL cab.L14.certified" if !l14.certified?
<< "PASS cab.L14.certified"
expected_exponents = (
  "\[\[0, 0\], \[1, 0\], \[0, 1\], \[2, 0\], \[1, 1\], " +
  "\[0, 2\], \[3, 0\], \[2, 1\], \[1, 2\], \[4, 0\], " +
  "\[3, 1\], \[2, 2\]\]")
raise "FAIL cab.L14.weights" if (
  l14.exponents.to_s != expected_exponents)
<< "PASS cab.L14.weights"

sample_function = model.x**2 + model.y*3 + 4
vector = l14.coordinates(sample_function)
raise "FAIL cab.coordinates.roundtrip" if (
  l14.function(vector) != sample_function)
<< "PASS cab.coordinates.roundtrip"
raise "FAIL cab.coordinates.contains" if !l14.contains?(sample_function)
<< "PASS cab.coordinates.contains"
raise "FAIL cab.coordinates.reject_bound" if l5.contains?(sample_function)
<< "PASS cab.coordinates.reject_bound"

# y^3 is replaced by the affine curve relation and stays within pole order 12.
reduced_cube = model.multiply(model.y**2, model.y, 12)
raise "FAIL cab.multiply.normal_form" if (
  reduced_cube.degree_in(1) >= 3)
<< "PASS cab.multiply.normal_form"
raise "FAIL cab.multiply.pole_bound" if (
  model.pole_bound(reduced_cube) > 12)
<< "PASS cab.multiply.pole_bound"
raise "FAIL cab.multiply.relation" if !model.reduce(
  model.y**3 - reduced_cube).zero?
<< "PASS cab.multiply.relation"

evaluation_point = space.point(0, 4, 1)
raise "FAIL cab.evaluate" if (
  model.evaluate(model.x + model.y, evaluation_point) != 4)
<< "PASS cab.evaluate"
second_evaluation_point = space.point(2, 2, 1)
raise "FAIL cab.evaluate.second_on_curve" if !curve.contains?(
  second_evaluation_point)
<< "PASS cab.evaluate.second_on_curve"

# Coordinate kernels give exact spaces L(n*infinity - Q_1 - ... - Q_r).
kernel_q = l14.evaluation_kernel([evaluation_point])
kernel_r = l14.evaluation_kernel([second_evaluation_point])
kernel_qr = l14.evaluation_kernel([
  evaluation_point, second_evaluation_point])
raise "FAIL cab.kernel.certified" if !kernel_qr.certified?
<< "PASS cab.kernel.certified"
raise "FAIL cab.kernel.one_point_dimension" if (
  kernel_q.dimension != 11 || kernel_r.dimension != 11)
<< "PASS cab.kernel.one_point_dimension"
raise "FAIL cab.kernel.two_point_dimension" if kernel_qr.dimension != 10
<< "PASS cab.kernel.two_point_dimension"
intersection = kernel_q.subspace.intersection(kernel_r.subspace)
raise "FAIL cab.kernel.intersection" if !intersection.same_subspace?(
  kernel_qr.subspace)
<< "PASS cab.kernel.intersection"
raise "FAIL cab.kernel.sum" if !kernel_q.subspace.sum(
  kernel_r.subspace).same_subspace?(l14.full_subspace)
<< "PASS cab.kernel.sum"

# Products of function subspaces are reduced through the C_ab relation and
# canonicalized in the target L-space.
l7 = model.riemann_roch_space(7)
l7_q = l7.vanishing_subspace([evaluation_point])
l7_r = l7.vanishing_subspace([second_evaluation_point])
product_qr = l7_q.multiply(l7_r, l14)
raise "FAIL cab.subspace.product_certified" if !product_qr.certified?
<< "PASS cab.subspace.product_certified"
raise "FAIL cab.subspace.product_vanishing" if !kernel_qr.subspace.contains_subspace?(
  product_qr)
<< "PASS cab.subspace.product_vanishing"
raise "FAIL cab.subspace.product_surjective" if !product_qr.same_subspace?(
  kernel_qr.subspace)
<< "PASS cab.subspace.product_surjective"
preimage_q = l7_r.multiplier_preimage_in(product_qr, l7)
raise "FAIL cab.subspace.preimage_certified" if !preimage_q.certified?
<< "PASS cab.subspace.preimage_certified"
raise "FAIL cab.subspace.preimage_recovers_factor" if !preimage_q.subspace.same_subspace?(
  l7_q)
<< "PASS cab.subspace.preimage_recovers_factor"
embedded_l7_q = l7_q.embedded_in(l14)
raise "FAIL cab.subspace.embedding" if embedded_l7_q.dimension != (
  l7_q.dimension)
<< "PASS cab.subspace.embedding"
infinity_failed = false
begin
  model.evaluate(model.x, model.infinity_point)
rescue error
  infinity_failed = error.to_s.include?("at infinity")
raise "FAIL cab.evaluate.infinity_is_loud" if !infinity_failed
<< "PASS cab.evaluate.infinity_is_loud"

bad_weights_failed = false
begin
  curve.c_ab_model(1, 0, 2, 2, 4)
rescue error
  bad_weights_failed = true
raise "FAIL cab.invalid_weights_is_loud" if !bad_weights_failed
<< "PASS cab.invalid_weights_is_loud"

bad_infinity_curve = Curve.new(
  space, equation + B*S**3)
bad_infinity_failed = false
begin
  bad_infinity_curve.c_ab_model(1, 0, 2, 3, 4)
rescue error
  bad_infinity_failed = true
raise "FAIL cab.invalid_infinity_is_loud" if !bad_infinity_failed
<< "PASS cab.invalid_infinity_is_loud"

<< "algebra_c_ab_spec: all checks passed"
