# Odd-parity linear perturbations of Schwarzschild spacetime.

+ PerturbativeStabilityCertificate
  -> new(@mass, @angular_mode)
    if @mass.to_f <= ~0.0 || !Expression.integer?(@angular_mode) || (
       @angular_mode < 2)
      raise "axial stability certificate requires M > 0 and integer l >= 2"

  -> sector
    :schwarzschild_axial

  -> assumptions
    ["M > 0", "integer l >= 2", "r >= 2M", "regular exterior boundary data"]

  -> claim
    "the axial Regge-Wheeler mode has nonnegative conserved energy"

  -> proof
    "For r >= 2M, (1-2M/r) >= 0. Also l(l+1)r-6M " + (
      ">= 2M(l(l+1)-3) > 0 for integer l >= 2, so V_l(r) >= 0. " + (
      "The Regge-Wheeler energy integral is therefore nonnegative."))

  -> certified?
    @mass.to_f > ~0.0 && Expression.integer?(@angular_mode) && (
      @angular_mode >= 2)

  -> scope
    "mode-energy positivity; not nonlinear stability"

  -> to_s
    "PerturbativeStabilityCertificate(" + self.sector.to_s + ": " + (
      self.claim) + ")"

  -> inspect
    to_s


+ ReggeWheelerPotential
  -> new(@mass = 1, @angular_mode = 2)
    if @mass.to_f <= ~0.0
      raise "Regge-Wheeler mass must be positive"
    if !Expression.integer?(@angular_mode) || @angular_mode < 2
      raise "gravitational Regge-Wheeler modes require integer l >= 2"
    @radius = Expression.variable(:r)
    mass = Expression.wrap(@mass)
    mode = Expression.wrap(@angular_mode)
    @expression = Geometry.simplify_scalar(
      (Geometry.one - mass*2/@radius) * (
        mode*(mode + 1)/(@radius*@radius) -
        mass*6/(@radius*@radius*@radius)))

  -> mass
    @mass

  -> angular_mode
    @angular_mode

  -> horizon_radius
    2 * @mass

  -> expression
    @expression

  -> potential_expression
    @expression

  -> at(radius)
    if radius < self.horizon_radius
      raise "Regge-Wheeler exterior potential needs r >= 2M"
    @expression.evaluate({r: radius})

  -> potential_at(radius)
    at(radius)

  -> tortoise_expression
    r = @radius
    mass = Expression.wrap(@mass)
    Geometry.simplify_scalar(
      r + mass*2*(r/(mass*2) - Geometry.one).log)

  -> tortoise_at(radius)
    if radius <= self.horizon_radius
      raise "finite Schwarzschild tortoise coordinate needs r > 2M"
    radius.to_f + ~2.0*@mass.to_f*Math.log(
      radius.to_f/(~2.0*@mass.to_f) - ~1.0)

  # Unique exterior maximum of the l >= 2 potential.  Writing x=r/(2M),
  # dV/dr=0 gives 2Lx^2-3(L+3)x+12=0; the plus root is exterior.
  -> peak_radius
    angular = @angular_mode.to_f * (@angular_mode + 1).to_f
    discriminant = ~9.0*(angular + ~3.0)**2 - ~96.0*angular
    x = (~3.0*(angular + ~3.0) + Math.sqrt(discriminant)) / (
      ~4.0*angular)
    ~2.0*@mass.to_f*x

  -> peak_potential
    self.at(self.peak_radius).to_f

  -> samples(start_radius = nil, stop_radius = nil, count = 120)
    start_value = start_radius == nil ? ~2.001*@mass.to_f : start_radius.to_f
    stop_value = stop_radius == nil ? ~20.0*@mass.to_f : stop_radius.to_f
    if start_value <= ~2.0*@mass.to_f || stop_value <= start_value
      raise "Regge-Wheeler samples need 2M < start < stop"
    if !Expression.integer?(count) || count < 2
      raise "Regge-Wheeler samples need an integer count of at least two"
    out = []
    i = 0
    while i < count
      radius = start_value + (stop_value - start_value) * (
        i.to_f / (count - 1).to_f)
      out.push([radius, self.at(radius).to_f])
      i += 1
    out

  -> stability_certificate
    PerturbativeStabilityCertificate.new(@mass, @angular_mode)

  -> to_s
    "ReggeWheelerPotential(M=" + @mass.to_s + ", l=" + (
      @angular_mode.to_s) + ")"

  -> inspect
    to_s
