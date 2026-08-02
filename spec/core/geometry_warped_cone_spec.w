# Ideal-apex warped surfaces and their finite Euclidean-cone contrast.
# Run in both engines:
#   bin/tungsten run spec/core/geometry_warped_cone_spec.w
#   bin/tungsten compile spec/core/geometry_warped_cone_spec.w \
#     --out /tmp/geometry-warped-cone-spec && /tmp/geometry-warped-cone-spec

use geometry

-> cone_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> cone_close?(left, right, tolerance = ~2.0e-12)
  difference = Math.abs(left.to_f - right.to_f)
  scale = Math.abs(right.to_f)
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance * scale

exponential = WarpedConeSurface.exponential(2, Rational.new(1, 2))
cone_check("exponential.ideal_apex", exponential.ideal_apex?)
cone_check("exponential.no_finite_height",
           exponential.finite_apex_height == nil)
cone_check("exponential.profile",
           cone_close?(exponential.radius(2), ~2.0*Math.exp(~-1.0)))
cone_check("exponential.curvature.exact",
           exponential.gaussian_curvature(7) == Rational.new(-1, 4))
cone_check("exponential.metric.components",
           exponential.metric.component(0, 0) == Geometry.one &&
           exponential.metric.component(0, 1) == Geometry.zero)
exponential_connection = exponential.metric.connection
cone_check("exponential.meridians.geodesic.exact",
           exponential.meridians_geodesic? &&
           exponential_connection.component(0, 0, 0) == Geometry.zero &&
           exponential_connection.component(1, 0, 0) == Geometry.zero)
cone_check("exponential.scalar_is_twice_gaussian",
           cone_close?(
             exponential.metric.curvature.scalar_curvature.evaluate(
               {t: ~1.3, theta: ~0.2}),
             ~2.0*exponential.gaussian_curvature(~1.3)))

power = WarpedConeSurface.power(3, 2, 2)
cone_check("power.ideal_apex", power.ideal_apex?)
cone_check("power.radius.exact",
           power.radius(1) == Rational.new(1, 3))
cone_check("power.curvature.exact",
           power.gaussian_curvature(1) == Rational.new(-8, 3))
cone_check("power.rational_profile", power.rational_profile_evaluation?)

reciprocal = WarpedConeSurface.reciprocal(4, 3)
cone_check("reciprocal.alias",
           reciprocal.shrink_law == :power && reciprocal.exponent == 1)
cone_check("reciprocal.radius.exact",
           reciprocal.radius(1) == 1)

linear = WarpedConeSurface.linear(3, 1)
cone_check("linear.finite_apex", linear.finite_apex?)
cone_check("linear.apex_height.exact", linear.finite_apex_height == 3)
cone_check("linear.radius.exact", linear.radius(2) == 1)
cone_check("linear.apex.radius", linear.radius(3) == 0)
cone_check("linear.curvature.zero", linear.gaussian_curvature(2) == 0)
cone_check("linear.rational_profile", linear.rational_profile_evaluation?)
cone_check("linear.apex.not_regular", !linear.regular_height?(3))
cone_check("linear.curvature.scope",
           linear.curvature_scope.include?("tip is singular"))

apex_curvature_failed = false
begin
  linear.gaussian_curvature(3)
rescue error
  apex_curvature_failed = error.to_s.include?("singular")
cone_check("linear.apex.curvature_is_loud", apex_curvature_failed)

float_linear = WarpedConeSurface.linear(~3.0, ~1.0)
cone_check("linear.float_profile.not_rational",
           !float_linear.rational_profile_evaluation?)

pi = Math.acos(~-1.0)
angular_gap = exponential.normalized_separation(~0.1, ~2.0*pi - ~0.1)
cone_check("separation.periodic", cone_close?(angular_gap, ~0.2))
cone_check("separation.physical.scales",
           cone_close?(
             exponential.physical_separation(~0.0, ~0.1, ~2.0*pi - ~0.1),
             ~0.4))
cone_check("separation.converges",
           exponential.physical_separation(
             ~10.0, ~0.1, ~2.0*pi - ~0.1) < ~0.003)
cone_check("separation.normalized.persists",
           cone_close?(
             exponential.normalized_separation(~0.1, ~2.0*pi - ~0.1),
             angular_gap))
cone_check("circumference",
           cone_close?(exponential.circumference(0), ~4.0*pi))

profile = reciprocal.profile_samples(0, 2, 3)
cone_check("samples.profile.shape",
           profile.size == 3 && profile[0].size == 2)
cone_check("samples.profile.endpoints",
           cone_close?(profile[0][1], ~4.0) &&
           cone_close?(profile[2][1], ~4.0/~7.0))
meridian = reciprocal.meridian_samples(0, 0, 2, 3)
cone_check("samples.meridian.shape",
           meridian.size == 3 && meridian[0].size == 3)
cone_check("samples.meridian.coordinates",
           cone_close?(meridian[0][0], ~4.0) &&
           cone_close?(meridian[0][1], ~0.0) &&
           cone_close?(meridian[2][2], ~2.0))
rings = reciprocal.surface_samples(0, 2, 3, 5)
cone_check("samples.surface.shape",
           rings.size == 3 && rings[0].size == 5)
cone_check("samples.surface.seam",
           cone_close?(rings[0][0][0], rings[0][4][0]) &&
           cone_close?(rings[0][0][1], rings[0][4][1]))
cone_check("samples.scope_is_loud",
           reciprocal.numeric_scope.include?("floating-point approximations"))

beyond_apex_failed = false
begin
  linear.radius(~3.1)
rescue error
  beyond_apex_failed = error.to_s.include?("beyond the finite linear apex")
cone_check("linear.beyond_apex.rejected", beyond_apex_failed)

bad_rate_failed = false
begin
  WarpedConeSurface.exponential(1, 0)
rescue error
  bad_rate_failed = error.to_s.include?("must be positive")
cone_check("invalid.rate.rejected", bad_rate_failed)

bad_count_failed = false
begin
  exponential.profile_samples(0, 1, ~2.5)
rescue error
  bad_count_failed = error.to_s.include?("integer of at least two")
cone_check("invalid.sample_count.rejected", bad_count_failed)

<< "geometry_warped_cone_spec: all checks passed"
