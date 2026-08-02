# Type-aware Drawille inspection checks against public core math classes.
# Run both ways from the repository root:
#   bin/tungsten run bits/tungsten-drawille/spec/inspection_spec.w
#   bin/tungsten compile bits/tungsten-drawille/spec/inspection_spec.w --out /tmp/drawille-inspection-spec

use algebra
use calculus
use geometry
use core/numeric/vec3
use core/numeric/vec4
use ../lib/drawille

-> inspection_check(name, condition)
  if !condition
    raise "FAIL " + name
  << "PASS " + name

-> contains_braille?(text)
  text.chars.any? -> (character)
    DRAWILLE_BRAILLE_GLYPHS.include?(character) && character != DRAWILLE_BRAILLE_GLYPHS[0]

-> renders(value, label)
  picture = DrawilleInspection.render(value, 24, 6)
  picture != "" && picture.include?(label) && !picture.include?("visualization unavailable") && contains_braille?(picture)

line_ring = PolynomialRing.new([:x])
x = line_ring.generator(0)
inspection_check("ring", renders(line_ring, "PolynomialRing"))
inspection_check("polynomial.univariate", renders(x*x - 1, "Polynomial"))
finite_ring = PolynomialRing.new([:u], FiniteField.new(5))
finite_picture = DrawilleInspection.render(finite_ring.generator(0) + 1, 24, 6)
inspection_check(
  "polynomial.finite_field_not_ordered",
  finite_picture.include?("No ordered numeric embedding") && !contains_braille?(finite_picture))

plane_ring = PolynomialRing.new([:x, :y])
px, py = plane_ring.generators
inspection_check("polynomial.bivariate", renders(px*px + py*py - 1, "Polynomial"))
squared_circle = (px*px + py*py - 1)**2
squared_circle_picture = DrawilleInspection.render(squared_circle, 24, 6)
positive_circle_picture = DrawilleInspection.render(squared_circle + 1, 24, 6)
inspection_check(
  "polynomial.bivariate_even_multiplicity",
  contains_braille?(squared_circle_picture))
inspection_check(
  "polynomial.bivariate_positive_valley_not_zero",
  !contains_braille?(positive_circle_picture))

space_ring = PolynomialRing.new([:x, :y, :z])
sx, sy, sz = space_ring.generators
inspection_check("polynomial.ternary", renders(sx*sx + sy*sy + sz*sz - 1, "3-D"))
squared_sphere = (sx*sx + sy*sy + sz*sz - 1)**2
squared_sphere_picture = DrawilleInspection.render(squared_sphere, 24, 6)
positive_sphere_picture = DrawilleInspection.render(squared_sphere + 1, 24, 6)
inspection_check(
  "polynomial.ternary_even_multiplicity",
  contains_braille?(squared_sphere_picture))
inspection_check(
  "polynomial.ternary_positive_valley_not_zero",
  !contains_braille?(positive_sphere_picture))

p2 = ProjectiveSpace<ℚ, 2>.new(:X, :Y, :Z)
X = p2.coords[0]
Y = p2.coords[1]
Z = p2.coords[2]
curve = Curve.new(p2, Y**2 * Z - X**3 + X * Z**2 - Z**3)
inspection_check("projective.space", renders(p2, "ProjectiveSpace"))
inspection_check("projective.point", renders(p2.point(0, 1, 1), "ProjectivePoint"))
finite_space = ProjectiveSpace<FiniteField, 2>.new(
  Algebra.field(FiniteField.new(5)), 2, [:X, :Y, :Z])
finite_space_picture = DrawilleInspection.render(finite_space, 24, 6)
inspection_check(
  "projective.finite_field_not_ordered",
  finite_space_picture.include?("no ordered real embedding") &&
  !contains_braille?(finite_space_picture))
inspection_check("curve", renders(curve, "AffineChart"))
inspection_check("affine.chart", renders(curve.affine_chart, "AffineChart"))
inspection_check("elliptic", renders(EllipticCurve.new(p2, -1, 1), "EllipticCurve"))
inspection_check(
  "hyperelliptic",
  renders(HyperellipticCurve.new(x**5 - x), "HyperellipticCurve"))

number_field = NumberField.new(x*x - 2, :a)
inspection_check("number_field_element", renders(number_field.generator + 1, "power-basis coefficients"))
simple_extension = SimpleExtensionField.new(x*x - 2, :b)
inspection_check("simple_extension_element", renders(simple_extension.generator + 1, "power-basis coefficients"))
finite_extension_ring = PolynomialRing.new([:t], FiniteField.new(2))
finite_t = finite_extension_ring.generator(0)
finite_extension = SimpleExtensionField.new(
  finite_t*finite_t + finite_t + 1, :a)
finite_element_picture = DrawilleInspection.render(
  finite_extension.generator + 1, 24, 6)
inspection_check(
  "simple_extension.finite_field_not_ordered",
  finite_element_picture.include?("no ordered real embedding") &&
  !contains_braille?(finite_element_picture))
real_root = (x*x - 2).real_roots[0]
inspection_check("algebraic_real", renders(real_root, "AlgebraicRealRoot"))

differential = Differential.new(
  ~1.0, [~2.0, ~-1.0], [[~1.0, ~0.5], [~0.5, ~2.0]])
inspection_check("differential", renders(differential, "second-order local model"))

schwarzschild = Schwarzschild.new(1)
einstein_picture = DrawilleInspection.render(
  schwarzschild.einstein_tensor, 32, 8)
inspection_check(
  "tensor_field.schwarzschild_einstein",
  einstein_picture.include?("TensorField") &&
  einstein_picture.include?("rank 2 on a 4-D chart") &&
  einstein_picture.include?("all 16 components vanish within 1e-9") &&
  einstein_picture.include?("not a symbolic proof") &&
  !einstein_picture.include?("visualization unavailable"))

horizon_picture = DrawilleInspection.render(schwarzschild.horizons, 32, 8)
inspection_check(
  "horizon_set.radial_view",
  horizon_picture.include?("HorizonSet") &&
  horizon_picture.include?("killing_event") &&
  horizon_picture.include?("r = 2") && contains_braille?(horizon_picture))

regge_wheeler_picture = DrawilleInspection.render(
  schwarzschild.regge_wheeler(2), 32, 8)
inspection_check(
  "regge_wheeler.samples_and_scope",
  regge_wheeler_picture.include?("ReggeWheelerPotential") &&
  regge_wheeler_picture.include?("exterior peak") &&
  regge_wheeler_picture.include?("not nonlinear stability") &&
  contains_braille?(regge_wheeler_picture))

bulk_chord_picture = DrawilleInspection.render(
  RandallSundrum.new(1).bulk_chord(4), 32, 8)
inspection_check(
  "brane_bulk_chord.spatial_not_causal",
  bulk_chord_picture.include?("BraneBulkChord") &&
  bulk_chord_picture.include?("proper length") &&
  bulk_chord_picture.include?("causal shortcut?: false") &&
  bulk_chord_picture.include?("not an FTL/null-return claim") &&
  contains_braille?(bulk_chord_picture))

ideal_cone = WarpedConeSurface.exponential(1, 1)
ideal_cone_picture = DrawilleInspection.render(ideal_cone, 40, 10)
inspection_check(
  "warped_cone.ideal_apex_separations",
  ideal_cone_picture.include?("WarpedConeSurface") &&
  ideal_cone_picture.include?("ideal apex at t = infinity") &&
  ideal_cone_picture.include?("normalized separation Delta-theta") &&
  ideal_cone_picture.include?("physical cross-section arc f(t) Delta-theta") &&
  ideal_cone_picture.include?("not unrestricted geodesic distance") &&
  ideal_cone_picture.include?("non-isometric profile wireframe") &&
  contains_braille?(ideal_cone_picture))

finite_cone_picture = DrawilleInspection.render(
  WarpedConeSurface.linear(1, 1), 32, 8)
inspection_check(
  "warped_cone.finite_apex_labeled",
  finite_cone_picture.include?("finite apex at t = 1") &&
  !finite_cone_picture.include?("ideal apex at t = infinity") &&
  contains_braille?(finite_cone_picture))

qexp = QExpansion.new([0, 1, -2, 3])
inspection_check("q_expansion", renders(qexp, "q-expansion"))
finite_qexp = FieldQExpansion.new(FiniteField.new(5), [0, 1, 4])
finite_qexp_picture = DrawilleInspection.render(finite_qexp, 24, 6)
inspection_check(
  "q_expansion.finite_field_not_ordered",
  finite_qexp_picture.include?("no ordered real embedding") &&
  !contains_braille?(finite_qexp_picture))
formal = FormalPowerSeries.new([1, 2, 3])
inspection_check("formal_series", renders(formal, "no convergence is implied"))
laurent = FormalLaurentSeries.new([1, 2, 3], -2)
laurent_picture = DrawilleInspection.render(laurent, 24, 6)
inspection_check(
  "formal_laurent.power_axis",
  laurent_picture.include?("\n  -2") && contains_braille?(laurent_picture))
puiseux = FormalPuiseuxSeries.new([1, 2, 3], -1, 2)
puiseux_picture = DrawilleInspection.render(puiseux, 24, 6)
inspection_check(
  "formal_puiseux.power_axis",
  puiseux_picture.include?("\n  -1/2") && contains_braille?(puiseux_picture))

theta_space = SymplecticF2Space.new(2)
theta_form = ThetaQuadraticForm.new(theta_space, [1, 0, 0, 1])
theta_picture = DrawilleInspection.render(theta_form, 40, 6)
inspection_check("theta.truth_table", theta_picture.include?("0000:") && theta_picture.include?("1111:") && !theta_picture.include?("visualization unavailable"))
large_characteristic = []
34.times -> large_characteristic.push(0)
large_theta = ThetaQuadraticForm.new(
  SymplecticF2Space.new(17), large_characteristic)
inspection_check(
  "theta.bounded_dimension",
  DrawilleInspection.render(large_theta, 40, 6).include?("omitted above dimension 32"))

inspection_check("array.series", renders([1, 3, 2, 5], "numeric samples"))
inspection_check("array.points3d", renders([[0, 0, 0], [1, 1, 1]], "points in R^3"))
large_series = []
1000.times -> (i)
  large_series.push(i)
# Index 1 is deliberately not among the 16 evenly sampled source indices at
# the minimum eight-column viewport. A pre-conversion sampler stays bounded;
# an eager numeric copy would reject the entire source.
large_series[1] = "unsampled"
large_series_picture = DrawilleInspection.render(large_series, 8, 4)
inspection_check(
  "array.scalar_preconversion_sampling",
  large_series_picture.include?("sampled 16 of 1000 numeric samples") &&
  contains_braille?(large_series_picture))
large_points = []
1000.times -> (i)
  large_points.push([i, i % 7, i % 11])
large_points_picture = DrawilleInspection.render(large_points, 8, 4)
inspection_check(
  "array.point_count_bounded",
  large_points_picture.include?("sampled 16 of 1000 points in R^3") &&
  contains_braille?(large_points_picture))
array4_picture = DrawilleInspection.render(
  [[0, 0, 0, 9], [1, 1, 1, 8]], 24, 6)
inspection_check(
  "array.points4d_projection_labeled",
  array4_picture.include?("first-three-coordinate") &&
  array4_picture.include?("R^4") && contains_braille?(array4_picture))
vector3 = Vec3<f64>.new([~1.0, ~2.0, ~3.0] ## f64[3])
inspection_check("vector3", renders(vector3, "perspective projection"))
vector4 = Vec4<f64>.new([~1.0, ~2.0, ~3.0, ~4.0] ## f64[4])
vector4_picture = DrawilleInspection.render(vector4, 24, 6)
inspection_check(
  "vector4.projection_labeled",
  vector4_picture.include?("first-three-coordinate") &&
  vector4_picture.include?("R^4") && contains_braille?(vector4_picture))
inspection_check("unsupported.empty", DrawilleInspection.render("not geometry") == "")

<< "drawille inspection spec: all checks passed"
