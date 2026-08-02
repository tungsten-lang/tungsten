# Warped surfaces with circular cross-sections.
#
# The intrinsic metric is
#
#   ds^2 = dt^2 + f(t)^2 dtheta^2.
#
# An exponential or power profile has f(t) -> 0 only as t -> infinity, so
# distinct meridians have vanishing cross-sectional separation while the
# ideal apex remains infinitely far away.  The linear profile reaches its
# apex in finite meridian distance and is included as the Euclidean-cone
# contrast.
#
# `display_point` and the sampling helpers use the convenient profile drawing
# (f cos(theta), f sin(theta), t).  That drawing is generally *not* an
# isometric Euclidean embedding of the intrinsic metric above.

+ WarpedConeSurface
  -> .exponential(initial_radius = 1, rate = 1)
    WarpedConeSurface.new(:exponential, initial_radius, rate, 1)

  -> .power(initial_radius = 1, rate = 1, exponent = 1)
    WarpedConeSurface.new(:power, initial_radius, rate, exponent)

  -> .reciprocal(initial_radius = 1, rate = 1)
    WarpedConeSurface.power(initial_radius, rate, 1)

  -> .linear(initial_radius = 1, slope = 1)
    WarpedConeSurface.new(:linear, initial_radius, slope, 1)

  -> new(shrink_law, @initial_radius = 1, @rate = 1, @exponent = 1)
    @shrink_law = shrink_law.to_s.to_sym
    if ![:exponential, :power, :linear].include?(@shrink_law)
      raise "warped cone shrink law must be exponential, power, or linear"
    initial_value = @initial_radius.to_f
    rate_value = @rate.to_f
    if initial_value <= ~0.0
      raise "warped cone initial radius must be positive"
    if rate_value <= ~0.0
      raise "warped cone rate or slope must be positive"
    if @shrink_law == :power
      exponent_value = @exponent.to_f
      if exponent_value <= ~0.0
        raise "warped cone power exponent must be positive"

    @chart = Chart.new([:t, :theta], [self.height_domain, "periodic angle"])
    t = @chart.coordinate(0)
    @radius_expression = self.build_radius_expression(t)
    @curvature_expression = self.build_curvature_expression(t)
    zero = Geometry.zero
    @metric = Metric.new(@chart, [
      [Geometry.one, zero],
      [zero, Geometry.simplify_scalar(
        @radius_expression * @radius_expression)]
    ])

  -> shrink_law
    @shrink_law

  -> shrink_law_label
    return "f(t) = r0 exp(-rate t)" if @shrink_law == :exponential
    if @shrink_law == :power
      return "f(t) = r0 / (1 + rate t)^exponent"
    "f(t) = r0 - slope t"

  -> initial_radius
    @initial_radius

  -> rate
    @rate

  -> slope
    @rate

  -> exponent
    @exponent

  -> ideal_apex?
    @shrink_law != :linear

  -> finite_apex?
    !self.ideal_apex?

  # Nil means that the apex is an ideal boundary point at infinite meridian
  # distance.  The linear model's value is exact for exact scalar inputs.
  -> finite_apex_height
    return nil if self.ideal_apex?
    @initial_radius / @rate

  -> radius_limit_at_apex
    0

  -> regular_height?(height)
    value = height.to_f
    return false if value < ~0.0
    return true if self.ideal_apex?
    value < self.finite_apex_height.to_f

  -> height_domain
    if self.ideal_apex?
      return "0 <= t < infinity"
    "0 <= t < " + self.finite_apex_height.to_s + " (regular metric)"

  -> chart
    @chart

  -> metric
    @metric

  # Curves with theta constant and affine parameter t have unit tangent and
  # zero acceleration: both Gamma^t_tt and Gamma^theta_tt vanish identically.
  -> meridians_geodesic?
    connection = @metric.connection
    radial = Geometry.zero_scalar?(connection.component(0, 0, 0))
    angular = Geometry.zero_scalar?(connection.component(1, 0, 0))
    radial && angular

  -> radius_expression
    @radius_expression

  -> gaussian_curvature_expression
    @curvature_expression

  # The Gaussian curvature of ds^2=dt^2+f(t)^2dtheta^2 is -f''(t)/f(t).
  # This method evaluates the closed-form expression rather than estimating
  # derivatives from samples.  For the linear model K=0 only on the regular
  # locus before the apex; the cone tip itself has distributional curvature.
  -> gaussian_curvature(height)
    self.validate_height(height)
    if !self.regular_height?(height)
      raise "Gaussian curvature is singular at the finite linear apex"
    @curvature_expression.evaluate({t: height})

  -> curvature_scope
    if self.finite_apex?
      return "K = 0 on t below the apex; the finite cone tip is singular"
    "smooth Gaussian curvature at every finite nonnegative height"

  -> radius(height)
    self.validate_height(height)
    @radius_expression.evaluate({t: height})

  -> circumference_expression
    Geometry.simplify_scalar(
      Expression.constant(2) * Expression.pi * @radius_expression)

  -> circumference(height)
    self.validate_height(height)
    self.circumference_expression.evaluate({t: height})

  # Shortest angular separation on the normalized unit cross-section, in
  # radians.  Period reduction requires a floating approximation to pi.
  -> normalized_separation(first_angle, second_angle)
    first_value = first_angle.to_f
    second_value = second_angle.to_f
    pi = Math.acos(~-1.0)
    tau = ~2.0 * pi
    difference = Math.abs(first_value - second_value) % tau
    difference > pi ? tau - difference : difference

  # Arc length on one height-t circle.  This is not the unrestricted surface
  # geodesic distance between the two points.
  -> physical_separation(height, first_angle, second_angle)
    self.radius(height).to_f * (
      self.normalized_separation(first_angle, second_angle))

  -> meridian_distance(first_height, second_height)
    self.validate_height(first_height)
    self.validate_height(second_height)
    Math.abs(first_height.to_f - second_height.to_f)

  # Whether exact rational inputs can remain exact when radius(height) is
  # evaluated.  Exponential values are retained symbolically by
  # radius_expression, but general numeric evaluation is transcendental.
  -> rational_profile_evaluation?
    rational_parameters = Expression.rational_exact_value?(@initial_radius)
    rational_parameters = rational_parameters && (
      Expression.rational_exact_value?(@rate))
    return rational_parameters if @shrink_law == :linear
    rational_parameters && @shrink_law == :power && (
      Expression.integer?(@exponent))

  -> numeric_scope
    "radius and curvature have symbolic closed forms; rational linear and " + (
      "integer-power evaluations can stay exact; angle normalization and " + (
      "display sampling are floating-point approximations; linear-tip " + (
      "curvature is not represented by the regular-locus formula")))

  # Convenient non-isometric coordinates for a surface-of-revolution plot.
  -> display_point(height, angle)
    radial = self.radius(height).to_f
    theta = angle.to_f
    [
      radial * Math.cos(theta),
      radial * Math.sin(theta),
      height.to_f
    ]

  -> default_stop_height
    if self.finite_apex?
      return self.finite_apex_height.to_f
    ~8.0 / @rate.to_f

  -> profile_samples(start_height = 0, stop_height = nil, count = 81)
    stop_value = stop_height == nil ? self.default_stop_height : (
      stop_height.to_f)
    self.validate_sample_interval(start_height, stop_value, count)
    out = []
    i = 0
    while i < count
      height = start_height.to_f + (stop_value - start_height.to_f) * (
        i.to_f / (count - 1).to_f)
      out.push([height, self.radius(height).to_f])
      i += 1
    out

  -> meridian_samples(angle, start_height = 0, stop_height = nil, count = 81)
    profile = self.profile_samples(start_height, stop_height, count)
    out = []
    profile.each -> (sample)
      out.push(self.display_point(sample[0], angle))
    out

  # Rings include the duplicated theta=0/2pi seam point so a renderer can
  # connect each returned row without special casing closure.
  -> surface_samples(start_height = 0, stop_height = nil,
                     height_count = 41, angular_count = 49)
    if !Expression.integer?(angular_count) || angular_count < 3
      raise "warped cone angular sample count must be an integer " + (
        "of at least three")
    profile = self.profile_samples(start_height, stop_height, height_count)
    tau = ~2.0 * Math.acos(~-1.0)
    rings = []
    profile.each -> (sample)
      ring = []
      j = 0
      while j < angular_count
        angle = tau * j.to_f / (angular_count - 1).to_f
        ring.push(self.display_point(sample[0], angle))
        j += 1
      rings.push(ring)
    rings

  -> build_radius_expression(height)
    radius = Expression.wrap(@initial_radius)
    rate = Expression.wrap(@rate)
    if @shrink_law == :exponential
      return Geometry.simplify_scalar(
        radius * (Geometry.zero - rate * height).exp)
    if @shrink_law == :power
      base = Geometry.one + rate * height
      return Geometry.simplify_scalar(
        radius * (base ** (0 - @exponent)))
    Geometry.simplify_scalar(radius - rate * height)

  -> build_curvature_expression(height)
    rate = Expression.wrap(@rate)
    return Geometry.zero if @shrink_law == :linear
    if @shrink_law == :exponential
      return Geometry.simplify_scalar(Geometry.zero - rate * rate)
    exponent = Expression.wrap(@exponent)
    base = Geometry.one + rate * height
    Geometry.simplify_scalar(
      Geometry.zero - exponent * (exponent + Geometry.one) * rate * rate / (
        base * base))

  -> validate_height(height)
    value = height.to_f
    if value < ~0.0
      raise "warped cone height must be nonnegative"
    if self.finite_apex? && value > self.finite_apex_height.to_f
      raise "warped cone height lies beyond the finite linear apex"
    true

  -> validate_sample_interval(start_height, stop_height, count)
    self.validate_height(start_height)
    self.validate_height(stop_height)
    if stop_height.to_f <= start_height.to_f
      raise "warped cone samples need start height below stop height"
    if !Expression.integer?(count) || count < 2
      raise "warped cone sample count must be an integer of at least two"
    true

  -> to_s
    apex = self.ideal_apex? ? "ideal apex" : (
      "finite apex t=" + self.finite_apex_height.to_s)
    "WarpedConeSurface(" + @shrink_law.to_s + ", " + apex + ")"

  -> inspect
    to_s
