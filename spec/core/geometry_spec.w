# Foundational differential-geometry regressions.
# Run in both engines:
#   bin/tungsten run spec/core/geometry_spec.w
#   bin/tungsten compile spec/core/geometry_spec.w --out /tmp/geometry-spec

use geometry

-> geometry_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> geometry_close?(got, want, tolerance = ~1.0e-9)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

zero = Expression.constant(0)
one = Expression.constant(1)
two = Expression.constant(2)

# Cartesian R^2 is exactly flat.
cartesian = Chart.new([:x, :y])
cartesian_metric = Metric.new(
  cartesian, [[one, zero], [zero, one]], [1, 1])
geometry_check("chart.dimension", cartesian.dimension == 2)
geometry_check("metric.signature.riemannian",
               cartesian_metric.signature.riemannian?)
geometry_check("metric.determinant", cartesian_metric.determinant == one)
geometry_check("metric.inverse",
               cartesian_metric.inverse_component(0, 0) == one &&
               cartesian_metric.inverse_component(0, 1) == zero)
geometry_check("tensor.index.variance",
               cartesian_metric.tensor.indices[0].covariant? &&
               cartesian_metric.inverse_tensor.indices[0].contravariant?)
geometry_check("cartesian.connection",
               cartesian_metric.connection.component(0, 0, 0) == zero)
geometry_check("cartesian.ricci",
               cartesian_metric.curvature.ricci_tensor.component(0, 0) == zero)
geometry_check("cartesian.scalar",
               cartesian_metric.curvature.scalar_curvature == zero)
geometry_check("cartesian.einstein",
               cartesian_metric.curvature.einstein_tensor.component(1, 1) == zero)
geometry_check("cartesian.kretschmann",
               cartesian_metric.curvature.kretschmann_scalar == zero)

# The exact inverse path is not restricted to diagonal coordinate metrics.
skew_basis_metric = Metric.new(
  cartesian, [[two, one], [one, two]], [1, 1])
geometry_check("metric.nondiagonal.determinant",
               skew_basis_metric.determinant == Expression.constant(3))
geometry_check("metric.nondiagonal.inverse.diagonal",
               skew_basis_metric.inverse_component(0, 0) == (
                 Expression.constant(Rational.new(2, 3))))
geometry_check("metric.nondiagonal.inverse.off_diagonal",
               skew_basis_metric.inverse_component(0, 1) == (
                 Expression.constant(Rational.new(-1, 3))))

# Polar coordinates have nonzero Christoffels but zero curvature.
polar = Chart.new([:r, :theta])
r = polar.coordinate(0)
polar_metric = Metric.new(
  polar, [[one, zero], [zero, r**2]], [1, 1])
polar_connection = polar_metric.connection
polar_point = {r: ~2.0, theta: ~0.4}
geometry_check("polar.gamma.r_theta_theta",
               polar_connection.component(0, 1, 1) == -r)
geometry_check("polar.gamma.theta_r_theta",
               geometry_close?(
                 polar_connection.evaluate(polar_point)[1][0][1], ~0.5))
geometry_check("polar.scalar.zero",
               geometry_close?(
                 polar_metric.curvature.scalar_curvature.evaluate(polar_point),
                 ~0.0))
geometry_check("polar.kretschmann.zero",
               geometry_close?(
                 polar_metric.curvature.kretschmann_scalar.evaluate(polar_point),
                 ~0.0))

# The unit two-sphere has Ricci = g, scalar curvature 2, and |Riemann|^2 = 4.
sphere = Chart.new([:theta, :phi])
theta = sphere.coordinate(0)
phi = sphere.coordinate(1)
sphere_metric = Metric.new(
  sphere, [[one, zero], [zero, theta.sin**2]], [1, 1])
sphere_curvature = sphere_metric.curvature
sphere_point = {theta: ~1.1, phi: ~0.2}
sphere_ricci = sphere_curvature.ricci_tensor.evaluate(sphere_point)
geometry_check("sphere.ricci.theta_theta",
               geometry_close?(sphere_ricci[0][0], ~1.0))
geometry_check("sphere.ricci.phi_phi",
               geometry_close?(
                 sphere_ricci[1][1], Math.sin(~1.1)**2))
geometry_check("sphere.scalar.two",
               geometry_close?(
                 sphere_curvature.scalar_curvature.evaluate(sphere_point),
                 ~2.0))
geometry_check("sphere.einstein.zero",
               geometry_close?(
                 sphere_curvature.einstein_tensor.evaluate(sphere_point)[0][0],
                 ~0.0))
geometry_check("sphere.kretschmann.four",
               geometry_close?(
                 sphere_curvature.kretschmann_scalar.evaluate(sphere_point),
                 ~4.0))

# A flat geodesic keeps constant velocity. The RHS and the integrator use the
# same [position..., velocity...] state convention.
flat_geodesic = cartesian_metric.geodesic_system
rhs = flat_geodesic.rhs(~0.0, [~1.0, ~2.0, ~3.0, ~-1.0])
geometry_check("geodesic.rhs.position",
               rhs[0] == ~3.0 && rhs[1] == ~-1.0)
geometry_check("geodesic.rhs.acceleration",
               rhs[2] == ~0.0 && rhs[3] == ~0.0)
trajectory = flat_geodesic.trajectory(
  [~1.0, ~2.0], [~3.0, ~-1.0], ~0.0, ~1.0, ~0.1)
final_position = trajectory.final_position
geometry_check("geodesic.trajectory.x",
               geometry_close?(final_position[0], ~4.0))
geometry_check("geodesic.trajectory.y",
               geometry_close?(final_position[1], ~1.0))

<< "geometry_spec: all checks passed"
