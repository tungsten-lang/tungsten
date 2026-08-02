# Exact/numeric checks for the initial spacetime models.
#
#   bin/tungsten run spec/core/relativity_geometry_spec.w
#   bin/tungsten compile spec/core/relativity_geometry_spec.w \
#     --out /tmp/relativity-geometry-spec && /tmp/relativity-geometry-spec

use geometry

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> close?(got, want, tolerance = ~1.0e-9)
  difference = got.to_f - want.to_f
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

-> tensor_close_to_zero?(tensor, tolerance = ~1.0e-9)
  row = 0
  while row < tensor.size
    column = 0
    while column < tensor[row].size
      return false if !close?(tensor[row][column], ~0.0, tolerance)
      column += 1
    row += 1
  true

schwarzschild = Schwarzschild.new(1)
point = {t: ~0.0, r: ~5.0, theta: ~1.1, phi: ~0.0}

check("schwarzschild.signature",
      schwarzschild.metric.signature.lorentzian?)
check("schwarzschild.determinant",
      close?(schwarzschild.metric.determinant.evaluate(point),
             ~0.0 - ~625.0*Math.sin(~1.1)**2))
check("schwarzschild.einstein.vacuum",
      tensor_close_to_zero?(schwarzschild.einstein_tensor.evaluate(point)))
check("schwarzschild.kretschmann",
      close?(schwarzschild.kretschmann_scalar.evaluate(point),
             ~48.0 / ~15625.0))

horizon = schwarzschild.horizons[0]
check("horizon.radius", horizon.radius == 2)
check("horizon.contains", horizon.contains?(~2.0))
missing_horizon_coordinate_failed = false
begin
  horizon.contains?({x: 2})
rescue error
  missing_horizon_coordinate_failed = error.to_s.include?("missing coordinate")
check("horizon.missing_coordinate_is_loud", missing_horizon_coordinate_failed)
check("horizon.normal.null",
      close?(schwarzschild.radial_normal_norm.evaluate({r: ~2.0}), ~0.0))
check("horizon.normal.integer_exact",
      schwarzschild.radial_normal_norm.evaluate({r: 5}) == Rational.new(3, 5))
check("horizon.area",
      close?(schwarzschild.horizon_area.evaluate({}), ~16.0*Math.acos(~-1.0)))
check("horizon.surface_gravity",
      close?(schwarzschild.surface_gravity.evaluate({}), ~0.25))
invariants = schwarzschild.horizon_invariants
check("horizon.kretschmann.regular_limit",
      invariants[:kretschmann].evaluate({}) == Rational.new(3, 4))
ef_point = {v: ~0.0, r: ~2.0, theta: ~1.1, phi: ~0.0}
ef_components = schwarzschild.ingoing_ef_metric.evaluate(ef_point)
check("horizon.ef_regular_components",
      close?(ef_components[0][0], ~0.0) &&
      close?(ef_components[0][1], ~1.0) &&
      close?(ef_components[1][0], ~1.0) &&
      close?(ef_components[2][2], ~4.0))
check("horizon.ef_regular_determinant",
      close?(schwarzschild.ingoing_ef_metric.determinant.evaluate(ef_point),
             ~-16.0*Math.sin(~1.1)**2))
ef_inverse = schwarzschild.ingoing_ef_metric.inverse_at(ef_point)
check("horizon.ef_regular_inverse",
      close?(ef_inverse[0][0], ~0.0) &&
      close?(ef_inverse[0][1], ~1.0) &&
      close?(ef_inverse[1][0], ~1.0) &&
      close?(ef_inverse[1][1], ~0.0) &&
      close?(ef_inverse[2][2], ~0.25))

regge_wheeler = schwarzschild.regge_wheeler(2)
check("regge_wheeler.horizon_zero",
      close?(regge_wheeler.at(~2.0), ~0.0))
check("regge_wheeler.exterior_positive",
      regge_wheeler.at(~3.0) > ~0.0)
check("regge_wheeler.known_value",
      close?(regge_wheeler.at(~3.0), ~4.0/~27.0))
check("regge_wheeler.integer_exact",
      regge_wheeler.at(3) == Rational.new(4, 27))
check("regge_wheeler.peak_exterior",
      regge_wheeler.peak_radius > ~2.0)
check("regge_wheeler.peak_local",
      regge_wheeler.peak_potential > regge_wheeler.at(
        regge_wheeler.peak_radius - ~0.01) &&
      regge_wheeler.peak_potential > regge_wheeler.at(
        regge_wheeler.peak_radius + ~0.01))
certificate = regge_wheeler.stability_certificate
check("regge_wheeler.stability.certified", certificate.certified?)
check("regge_wheeler.stability.scoped",
      certificate.scope.include?("not nonlinear"))
fractional_mode_failed = false
begin
  ReggeWheelerPotential.new(1, ~2.5)
rescue error
  fractional_mode_failed = error.to_s.include?("integer l")
check("regge_wheeler.fractional_mode_is_loud", fractional_mode_failed)

rs = RandallSundrum.new(1)
chord = rs.bulk_chord(~4.0, 21)
points = chord.points
check("bulk_chord.endpoints",
      close?(points[0][1], ~1.0) &&
      close?(points[points.size - 1][1], ~1.0))
check("bulk_chord.enters_bulk", points[10][1] > ~1.0)
chord_circle_ok = true
points.each -> (point)
  circle_value = point[0]*point[0] + point[1]*point[1]
  chord_circle_ok = false if !close?(
    circle_value, chord.euclidean_radius**2)
check("bulk_chord.semicircle_equation", chord_circle_ok)
check("bulk_chord.proper_length",
      close?(chord.proper_length, ~2.0*Math.asinh(~2.0)))
check("bulk_chord.not_causal_shortcut", !chord.causal_shortcut?)
check("bulk_chord.null_no_return",
      !chord.null_return_certificate.returns_to_brane?)
fractional_samples_failed = false
begin
  rs.bulk_chord(~4.0, ~2.5)
rescue error
  fractional_samples_failed = error.to_s.include?("integer sample count")
check("bulk_chord.fractional_samples_is_loud", fractional_samples_failed)
zero_chord = rs.bulk_chord(0, 2)
check("bulk_chord.zero_separation",
      close?(zero_chord.proper_length, ~0.0) &&
      close?(zero_chord.points[0][1], ~1.0) &&
      close?(zero_chord.points[1][1], ~1.0))

ads = RandallSundrum.new(2)
ads_point = {t: ~0.0, x: ~0.0, y: ~0.0, w: ~0.0, z: ~2.0}
ads_integer_point = {t: 0, x: 0, y: 0, w: 0, z: 2}
ads_curvature = ads.curvature
check("ads5.scalar_curvature",
      close?(ads_curvature.scalar_curvature.evaluate(ads_point), ~-5.0))
check("ads5.integer_binding_exact",
      ads_curvature.scalar_curvature.evaluate(ads_integer_point) == -5)
check("ads5.kretschmann",
      close?(ads_curvature.kretschmann_scalar.evaluate(ads_point), ~2.5))
ads_einstein = ads_curvature.einstein_tensor.evaluate(ads_point)
check("ads5.einstein_tensor",
      close?(ads_einstein[0][0], ~-1.5) &&
      close?(ads_einstein[1][1], ~1.5) &&
      close?(ads_einstein[4][4], ~1.5))
ads_far_point = {t: ~0.0, x: ~0.0, y: ~0.0, w: ~0.0, z: ~4.0}
ads_far_metric = ads.metric.evaluate(ads_far_point)
ads_far_ricci = ads_curvature.ricci_tensor.evaluate(ads_far_point)
ads_far_einstein = ads_curvature.einstein_tensor.evaluate(ads_far_point)
check("ads5.ricci_proportional_nontrivial_z",
      close?(ads_far_ricci[0][0], ~-1.0*ads_far_metric[0][0]) &&
      close?(ads_far_ricci[1][1], ~-1.0*ads_far_metric[1][1]))
check("ads5.einstein_proportional_nontrivial_z",
      close?(ads_far_einstein[0][0], ~1.5*ads_far_metric[0][0]) &&
      close?(ads_far_einstein[1][1], ~1.5*ads_far_metric[1][1]))

<< "relativity_geometry_spec: all checks passed"
