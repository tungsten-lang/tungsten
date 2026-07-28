# Focused exact-geometry regression identities.
# Run both ways:
#   bin/tungsten run spec/core/algebra_geometry_spec.w
#   bin/tungsten compile spec/core/algebra_geometry_spec.w --out /tmp/algebra-geometry-spec

use algebra

-> check(name, got, want)
  equal = got == want
  if got.class_name == "Polynomial"
    equal = got.eql?(want)
  elsif got.class_name == "EllipticPoint" || got.class_name == "MumfordDivisor"
    equal = got.eql?(want)
  elsif got.class_name == "ProjectivePoint" && want.class_name == "ProjectivePoint"
    equal = got.space == want.space && got.to_s == want.to_s
  if !equal
    raise "FAIL " + name + " got " + got.to_s + " want " + want.to_s
  << "PASS " + name

P2 = ProjectiveSpace<ℚ, 2>.new(:X, :Y, :Z)
X = P2.coords[0]
Y = P2.coords[1]
Z = P2.coords[2]

# Affine-chart dehomogenization is a first-class object and homogenizing it
# recovers the original homogeneous equation.
smooth_equation = Y**2 * Z - X**3 + X * Z**2 - Z**3
smooth = Curve.new(P2, smooth_equation)
chart = smooth.affine_chart(2)
check("chart.class", chart.class_name, "AffineChart")
check("chart.equation", chart.equation, Y**2 - X**3 + X - 1)
check("chart.homogenize", chart.homogenize.equation, smooth_equation)
check("chart.point", chart.point([0, 1]), P2.point(0, 1, 1))
check("chart.contains", chart.contains?([0, 1]), true)

# The singular locus is an ideal. Nonsingularity is derived from whether that
# ideal has a point on any standard projective chart.
singular = Curve.new(P2, Y**2 * Z - X**3)
check("singular_locus.class", singular.singular_locus.class_name, "Ideal")
check("singular.cubic", singular.nonsingular?, false)
check("nonsingular.cubic", smooth.nonsingular?, true)
check("elliptic.plane_cubic", smooth.elliptic?, true)
check("elliptic.short_weierstrass_recognition", smooth.short_weierstrass?, true)

# y^2 = x^3 - x + 1 has discriminant -368. Its rational group law gives
# 2(0, 1) = (1/4, -7/8).
elliptic = EllipticCurve.new(P2, -1, 1)
recognized_elliptic = smooth.to_short_weierstrass
check("elliptic.discriminant", elliptic.discriminant, -368)
check("elliptic.recognized_discriminant", recognized_elliptic.discriminant, -368)
check("elliptic.recognized_equation", recognized_elliptic.equation, smooth.equation)
check("elliptic.nonsingular", elliptic.nonsingular?, true)
p = elliptic.point(0, 1)
two_p = elliptic.point(Rational.new(1, 4), Rational.new(-7, 8))
check("elliptic.double", p + p, two_p)
check("elliptic.scalar.double", p * 2, two_p)
check("elliptic.scalar.zero", p * 0, elliptic.identity)
check("elliptic.scalar.negative", p * -1, -p)
check("elliptic.inverse", p + (-p), elliptic.identity)
check("elliptic.identity", p + elliptic.identity, p)
check("elliptic.projective", elliptic.contains?(two_p.projective_point), true)
check("elliptic.jacobian.class", elliptic.jacobian.class_name, "EllipticJacobian")
check("elliptic.jacobian.dimension", elliptic.jacobian.dimension, 1)
check("elliptic.curve_delegate", elliptic.curve.class_name, "Curve")

# Mumford pairs and slow Cantor composition give an exact Jacobian prototype
# without pretending that arithmetic rank is already certified.
t = Poly<ℚ>.new(:t).generator
hyperelliptic = HyperellipticCurve.new(t**5 - t)
jacobian = hyperelliptic.jacobian
divisor = jacobian.divisor(t, 0)
branch_one = jacobian.divisor(t - 1, 0)
branch_minus_one = jacobian.divisor(t + 1, 0)
check("hyperelliptic.model", hyperelliptic.hyperelliptic_model?, true)
check("hyperelliptic.genus", hyperelliptic.genus, 2)
check("mumford.identity", jacobian.identity.identity?, true)
check("mumford.reduced", divisor.reduced?, true)
check("mumford.negate", (-divisor).u, divisor.u)

even_model = HyperellipticCurve.new(t**4 + t + 1)
check("hyperelliptic.even_degree.genus", even_model.genus, 1)
even_jacobian_failed = false
begin
  even_model.jacobian
rescue error
  even_jacobian_failed = "[error]".include?("odd-degree model")
check("mumford.even_degree_is_loud", even_jacobian_failed, true)

nonmonic_model = HyperellipticCurve.new(t**5 * 2 - t + 1)
nonmonic_jacobian_failed = false
begin
  nonmonic_model.jacobian
rescue error
  nonmonic_jacobian_failed = "[error]".include?("monic model")
check("mumford.nonmonic_is_loud", nonmonic_jacobian_failed, true)

invalid_mumford_failed = false
begin
  jacobian.divisor(t, 1)
rescue error
  invalid_mumford_failed = error.to_s.include?("u | (v^2 - f)")
check("mumford.validates_relation", invalid_mumford_failed, true)
check("mumford.identity.add", divisor + jacobian.identity, divisor)
check("mumford.branch.two_torsion", divisor.double, jacobian.identity)
branch_pair = divisor + branch_one
check("mumford.composition.u", branch_pair.u, t**2 - t)
check("mumford.composition.v", branch_pair.v, 0)
reduced_three = branch_pair + branch_minus_one
check("mumford.cantor_reduction.u", reduced_three.u, t**2 + 1)
check("mumford.cantor_reduction.v", reduced_three.v, 0)
check("mumford.reduced_two_torsion", reduced_three.double, jacobian.identity)

# A non-branch point exercises the three-way Bezout lift, not only the
# v = 0 two-torsion path.  At (0, 1) on y^2 = x^5 - x + 1, tangent
# interpolation gives 2(x, 1) = (x^2, 1 - x/2) in Mumford form.
nonbranch_curve = HyperellipticCurve.new(t**5 - t + 1)
nonbranch_jacobian = nonbranch_curve.jacobian
nonbranch = nonbranch_jacobian.divisor(t, 1)
nonbranch_double = nonbranch.double
check("mumford.nonbranch.double.u", nonbranch_double.u, t**2)
check("mumford.nonbranch.double.v",
      nonbranch_double.v, t * Rational.new(-1, 2) + 1)
check("mumford.nonbranch.inverse",
      nonbranch + (-nonbranch), nonbranch_jacobian.identity)
check("mumford.scalar.double", nonbranch * 2, nonbranch_double)
check("mumford.scalar.zero", nonbranch * 0, nonbranch_jacobian.identity)
check("mumford.scalar.negative", nonbranch * -1, -nonbranch)

# Exact low-degree Galois groups: factorization decides degrees one and two;
# an irreducible cubic is cyclic exactly when its discriminant is a square.
quadratic_group = (t**2 - 2).galois_group
split_group = ((t - 1) * (t - 2)).galois_group
s3_group = (t**3 - 2).galois_group
a3_group = (t**3 - t * 3 + 1).galois_group
check("galois.quadratic.name", quadratic_group.name, "C2")
check("galois.quadratic.order", quadratic_group.order, 2)
check("galois.split", split_group.order, 1)
check("galois.cubic.s3", s3_group.name, "S3")
check("galois.cubic.a3", a3_group.name, "A3")
check("galois.certified", a3_group.certified?, true)

elliptic_rank_failed = false
begin
  elliptic.jacobian.rank
rescue error
  elliptic_rank_failed = "[error]".include?("certified descent")
check("elliptic.rank_certified_only", elliptic_rank_failed, true)

rank_failed = false
begin
  jacobian.rank
rescue error
  rank_failed = "[error]".include?("certified descent")
check("jacobian.rank_certified_only", rank_failed, true)
