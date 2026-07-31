# Inspect the projective special fibers of the shell-width quartic at its
# candidate bad primes. This is a finite exact diagnostic, not yet a regular
# model or a Jacobian local-image certificate.

use algebra

-> projective_points(curve)
  field = curve.field
  space = curve.space
  points = []
  y_index = 0
  while y_index < field.order
    y = field.element_from_index(y_index)
    x_index = 0
    while x_index < field.order
      x = field.element_from_index(x_index)
      point = space.point_raw([x, y, field.one])
      points.push(point) if curve.contains?(point)
      x_index += 1
    y_index += 1
  x_index = 0
  while x_index < field.order
    x = field.element_from_index(x_index)
    point = space.point_raw([x, field.one, field.zero])
    points.push(point) if curve.contains?(point)
    x_index += 1
  point = space.point_raw([field.one, field.zero, field.zero])
  points.push(point) if curve.contains?(point)
  points

-> singular?(curve, point)
  curve.partial_derivatives.all? -> (derivative)
    curve.field.zero?(
      derivative.evaluate_raw(point.coordinates))

-> local_data(curve, point)
  chart = 0
  while curve.field.zero?(point.coordinates[chart])
    chart += 1
  local = curve.singularity_at(
    point.dehomogenize(chart), chart)
  [
    point,
    "chart", chart,
    "local_polynomial", local.local_polynomial,
    "multiplicity", local.multiplicity,
    "tangent_cone", local.tangent_cone,
    "directions", local.tangent_direction_count,
    "ordinary", local.ordinary?
  ]

C ⊂ ℙ²_ℚ (B, S, Z) : 16B³Z + 48BS²Z − 3S⁴ + 8S³Z + 162S²Z² + 729Z⁴ = 0

[2, 3, 13].each -> (prime)
  fiber = C.reduce(prime)
  points = projective_points(fiber)
  singular = []
  local_singularities = []
  points.each -> (point)
    if singular?(fiber, point)
      singular.push(point)
      local_singularities.push(
        local_data(fiber, point))
  << ["prime", prime]
  << ["equation", fiber.equation]
  << ["point_count", points.size]
  << ["points", points]
  << ["singular_count", singular.size]
  << ["singular_points", singular]
  << ["local_singularities", local_singularities]
  if prime == 13
    model = C.certify_cuspidal_regular_model(
      13, [1, 8, 1])
    support_powers = []
    model.support_certificates.each ->
      support_powers.push(item[0])
    << ["cuspidal_model_certified", model.certified?]
    << ["singular_support_powers", support_powers]
    << ["total_space_value_valuation",
        model.source_value_valuation]
    << ["normalization_genus", model.normalization_genus]
    << ["normalization_extension_count",
        model.normalization_extension_point_count]
    << ["normalization_zeta_numerator",
        model.normalization_zeta_numerator]
    << ["normalization_jacobian_order",
        model.normalization_jacobian_order]
    << ["local_2_quotient_dimension_bound",
        model.dimension_upper_bound]
