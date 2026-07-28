# Exact algebra core and mathematical source notation.
# Run both ways:
#   bin/tungsten run spec/core/algebra_spec.w
#   bin/tungsten compile spec/core/algebra_spec.w --out /tmp/algebra-spec

use algebra

-> check(name, got, want)
  if got != want
    raise "FAIL " + name + " got " + got.to_s + " want " + want.to_s
  << "PASS " + name

# Spacing is cosmetic inside a curve declaration. Coefficient-coordinate
# adjacency belongs to this declaration grammar, not global multiplication.
C ⊂ ℙ²_ℚ (X, Y, Z) : 16X³Z + 48XY²Z − 3Y⁴ + 8Y³Z + 162Y²Z² + 729Z⁴ = 0
C.assert_homogeneous(4)
projective_curve = C
C⊂ℙ²_ℚ(x,y):16x³+48xy²−3y⁴+8y³+162y²+729=0
affine_curve = C

affine_curve.assert_homogeneous(4)
check("projective.degree", projective_curve.degree, 4)
check("affine.degree", affine_curve.degree, 4)

P2 = projective_curve.space
known_points = [P2[1:0:0], P2[0:9:1], P2[-3:-3:1]]
check("point.infinity", projective_curve.contains?(known_points[0]), true)
check("point.positive", projective_curve.contains?(known_points[1]), true)
check("point.negative", projective_curve.contains?(known_points[2]), true)
check("point.normalize", P2[-2:0:0].to_s, "\[1:0:0\]")

# The global ambient has conventional coordinates and can be renamed.
check("global.projective_plane", ℙ²_ℚ.dimension, 2)
renamed = ℙ²_ℚ.with_coords(:B, :S, :Z)
check("renamed.coords", renamed.coordinate_names.join(","), "B,S,Z")
explicit_p2 = ProjectiveSpace<ℚ, 2>.new(:B, :S, :Z)
check("explicit.projective_space", explicit_p2.coordinate_names.join(","), "B,S,Z")

x0 = Poly<ℚ>.new(:x).generator
cubic = x0**3 - x0
check("poly.degree", cubic.degree, 3)
check("poly.coefficient_class", cubic.leading_term[0].class_name, "Rational")
check("poly.to_s", cubic.to_s, "x^3 - x")
check("poly.discriminant", cubic.discriminant, 4)
check("poly.squarefree", cubic.squarefree?, true)
large_value = (x0**2 + 1).at(1000000000000)
check("poly.large_value_class", large_value.class_name, "Rational")
check("poly.large_value_exact", large_value.numerator, 1000000000000000000000001)

hyperelliptic = HyperellipticCurve.new(x0**5 - x0)
check("hyperelliptic.nonsingular", hyperelliptic.nonsingular?, true)
check("hyperelliptic.genus", hyperelliptic.genus, 2)
check("hyperelliptic.jacobian_dimension", hyperelliptic.jacobian.dimension, 2)

weil = WeilCubic.new(x0**3 + x0 + 1)
check("weil.discriminant", weil.discriminant, -31)

check("curve.nonsingular", projective_curve.nonsingular?, true)
check("curve.genus", projective_curve.genus, 3)
check("curve.hyperelliptic", projective_curve.hyperelliptic?, false)
check("jacobian.dimension", projective_curve.jacobian.dimension, 3)
