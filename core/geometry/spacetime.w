# Exact coordinate models used to exercise the differential-geometry spine.

+ Horizon
  -> new(@kind, @coordinate, @radius, @generator = nil,
         @description = nil)

  -> kind
    @kind

  -> coordinate
    @coordinate

  -> radius
    @radius

  -> generator
    @generator

  -> description
    @description

  -> contains?(point, tolerance = ~1.0e-12)
    value = point
    if point.class_name == "Hash"
      if !point.has_key?(@coordinate)
        raise "horizon point is missing coordinate " + @coordinate.to_s
      value = point[@coordinate]
    Math.abs(value.to_f - @radius.to_f) <= tolerance

  -> to_s
    "Horizon(" + @kind.to_s + ", " + @coordinate.to_s + "=" + (
      @radius.to_s) + ")"

  -> inspect
    to_s


+ HorizonSet
  -> new(horizons)
    if horizons.class_name != "Array"
      raise "horizon set needs an Array"
    @horizons = []
    horizons.each -> (horizon)
      raise "horizon set entries must be Horizons" if horizon.class_name != "Horizon"
      @horizons.push(horizon)

  -> size
    @horizons.size

  -> horizons
    Geometry.copy_array(@horizons)

  -> [](index)
    @horizons[index]

  -> radii
    out = []
    @horizons.each -> (horizon)
      out.push(horizon.radius)
    out

  -> to_s
    "HorizonSet(" + @horizons.join(", ") + ")"

  -> inspect
    to_s


+ SchwarzschildSpacetime
  -> new(@mass = 1)
    if @mass.to_f <= ~0.0
      raise "Schwarzschild mass must be positive"
    @chart = Chart.new([:t, :r, :theta, :phi])
    t, r, theta, phi = @chart.coordinates
    mass = Expression.wrap(@mass)
    lapse = Geometry.one - mass * 2 / r
    @lapse = lapse
    zero = Geometry.zero
    @metric = Metric.new(@chart, [
      [-lapse, zero, zero, zero],
      [zero, Geometry.one / lapse, zero, zero],
      [zero, zero, r*r, zero],
      [zero, zero, zero, r*r*theta.sin**2]
    ], [-1, 1, 1, 1])
    @ingoing_ef_metric = nil
    @horizons = HorizonSet.new([
      Horizon.new(
        :killing_event, :r, 2 * @mass, :partial_t,
        "Schwarzschild Killing horizon; in the maximal extension this is the event horizon")
    ])

  -> mass
    @mass

  -> chart
    @chart

  -> metric
    @metric

  -> curvature
    @metric.curvature

  -> einstein_tensor
    self.curvature.einstein_tensor

  -> kretschmann_scalar
    self.curvature.kretschmann_scalar

  -> horizons
    @horizons

  -> horizon_radius
    2 * @mass

  -> horizon_area
    radius = Expression.wrap(self.horizon_radius)
    Geometry.simplify_scalar(Expression.pi * radius * radius * 4)

  -> surface_gravity
    Geometry.simplify_scalar(
      Geometry.one / (Expression.wrap(@mass) * 4))

  # Squared norm of the normal dr to an r=constant surface.  Its zero at
  # r=2M identifies the Schwarzschild Killing horizon in this chart.
  -> radial_normal_norm
    @lapse

  # Ingoing Eddington-Finkelstein coordinates remove the Schwarzschild-chart
  # coordinate singularity at r=2M: ds^2=-f dv^2+2dvdr+r^2 dOmega^2.
  -> ingoing_ef_metric
    if @ingoing_ef_metric == nil
      ef_chart = Chart.new([:v, :r, :theta, :phi])
      v, r, theta, phi = ef_chart.coordinates
      lapse = @lapse
      zero = Geometry.zero
      one = Geometry.one
      @ingoing_ef_metric = Metric.new(ef_chart, [
        [-lapse, one, zero, zero],
        [one, zero, zero, zero],
        [zero, zero, r*r, zero],
        [zero, zero, zero, r*r*theta.sin**2]
      ], [-1, 1, 1, 1])
    @ingoing_ef_metric

  -> horizon_invariants
    radius = self.horizon_radius
    mass = Expression.wrap(@mass)
    horizon_kretschmann = Geometry.simplify_scalar(
      Expression.constant(Rational.new(3, 4)) / (mass**4))
    {
      radius: radius,
      area: self.horizon_area,
      surface_gravity: self.surface_gravity,
      normal_norm: self.radial_normal_norm.evaluate({r: radius}),
      # The Schwarzschild-coordinate contraction has removable lapse factors
      # at r=2M. Use its regular limit 48M^2/r^6 = 3/(4M^4).
      kretschmann: horizon_kretschmann
    }

  -> exterior?(radius)
    radius > self.horizon_radius

  -> regge_wheeler(angular_mode = 2)
    ReggeWheelerPotential.new(@mass, angular_mode)

  -> to_s
    "SchwarzschildSpacetime(M=" + @mass.to_s + ")"

  -> inspect
    to_s


# Short spelling for the standard vacuum model.
+ Schwarzschild
  -> .new(mass = 1)
    SchwarzschildSpacetime.new(mass)
