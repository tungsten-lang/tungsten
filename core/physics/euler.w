# Euler systems of gas dynamics: full compressible (ideal-gas EOS) and
# isothermal, in 1, 2, or 3 space dimensions.
#
# This is the boxed, dimension-generic reference layer for the standard
# ideal-gas and isothermal Euler equations. The finite-volume kernels inline
# the same formulas on raw f64[] storage; focused tests check numerical
# identities, not external proof artifacts.
#
# State vectors are plain Arrays in the C layout:
#   compressible: [rho, mom_x, (mom_y, (mom_z,)) energy]
#   isothermal:   [rho, mom_x, (mom_y, (mom_z))]
# with all entries raw ~f64. Momentum components are indexed 1..dim;
# `dir` arguments are 0-based (0 = x, 1 = y, 2 = z).

+ EulerSystem
  -> .finite_number?(value)
    name = value.class_name
    numeric = name == "Float" || name == "Integer" || name == "Int"
    numeric = true if name == "BigInt" || name == "Decimal"
    return false if !numeric
    number = value.to_f()
    !number.nan? && !number.infinite?

  -> dim
    @dim

  -> nstate
    @nstate

  -> state_shape_valid?(u)
    u.class_name == "Array" && u.size == @nstate

  -> direction_valid?(dir)
    Physics.integer?(dir) && dir >= 0 && dir < @dim

  -> validate_state_shape(u)
    if !self.state_shape_valid?(u)
      raise "EulerSystem: state needs [@nstate] components"
    true

  -> validate_direction(dir)
    if !self.direction_valid?(dir)
      raise "EulerSystem: direction must be between 0 and [@dim - 1]"
    true

  -> validate_state(u)
    if !self.state_valid?(u)
      raise "EulerSystem: state is outside the admissible set"
    true

  # Normal velocity in direction dir.
  -> velocity(u, dir)
    self.validate_direction(dir)
    self.validate_state(u)
    u[1 + dir] / u[0]

  # ½ ρ |v|² — kinetic energy density.
  -> kinetic_energy_unchecked(u)
    total = ~0.0
    d = 0
    while d < @dim
      total = total + u[1 + d] * u[1 + d] / u[0]
      d = d + 1
    ~0.5 * total

  -> kinetic_energy(u)
    self.validate_state(u)
    self.kinetic_energy_unchecked(u)

  # Characteristic wavespeeds in direction dir, one per equation, ordered
  # [u_n - c, u_n, ..., u_n, u_n + c] exactly as the C wavespeed blocks.
  -> wavespeeds(u, dir)
    self.validate_direction(dir)
    self.validate_state(u)
    un = self.velocity(u, dir)
    c = self.sound_speed(u)
    speeds = [un - c]
    k = 0
    while k < @nstate - 2
      speeds.push(un)
      k = k + 1
    speeds.push(un + c)
    speeds

  # Largest absolute characteristic speed in direction dir.
  -> max_wavespeed(u, dir)
    self.validate_direction(dir)
    self.validate_state(u)
    un = self.velocity(u, dir)
    c = self.sound_speed(u)
    lo = Math.abs(un - c)
    hi = Math.abs(un + c)
    lo > hi ? lo : hi

+ CompressibleEuler < EulerSystem
  # gas_gamma: adiabatic index, must exceed 1 (Decimal or Float accepted).
  -> new(dim, gas_gamma)
    if !Physics.integer?(dim) || dim < 1 || dim > 3
      raise "CompressibleEuler: dim must be 1, 2, or 3 (got [dim])"
    @dim = dim
    @nstate = dim + 2
    @gas_gamma = Physics.dimensionless(gas_gamma)
    if !self.params_valid?
      raise "CompressibleEuler: gas gamma must be finite and greater than one"

  -> gas_gamma
    @gas_gamma

  -> name
    "compressible_euler_[@dim]d"

  -> compressible?
    true

  -> energy_equation?
    true

  -> params_valid?
    EulerSystem.finite_number?(@gas_gamma) && @gas_gamma > ~1.0

  -> state_valid?(u)
    return false if !self.state_shape_valid?(u)
    k = 0
    while k < @nstate
      return false if !EulerSystem.finite_number?(u[k])
      k = k + 1
    return false if u[0] <= ~0.0
    internal = u[@nstate - 1] - self.kinetic_energy_unchecked(u)
    internal > ~0.0

  -> internal_energy(u)
    self.validate_state(u)
    u[@nstate - 1] - self.kinetic_energy_unchecked(u)

  # p = (γ − 1)(E − ½ ρ |v|²)
  -> pressure(u)
    (@gas_gamma - ~1.0) * self.internal_energy(u)

  -> sound_speed(u)
    self.validate_state(u)
    Math.sqrt(@gas_gamma * self.pressure(u) / u[0])

  # Physical flux vector in direction dir (the C x/y/z_flux blocks).
  -> flux(u, dir)
    self.validate_direction(dir)
    self.validate_state(u)
    rho = u[0]
    mn = u[1 + dir]
    p = self.pressure(u)
    f = [mn]
    d = 0
    while d < @dim
      component = mn * u[1 + d] / rho
      component = component + p if d == dir
      f.push(component)
      d = d + 1
    f.push((u[@nstate - 1] + p) * mn / rho)
    f

  # [rho, v..., p]  ->  conserved state.
  -> conserved(prim)
    if prim.class_name != "Array" || prim.size != @nstate
      raise "CompressibleEuler: primitive state needs [@nstate] components"
    prim.each -> (value)
      if !EulerSystem.finite_number?(value)
        raise "CompressibleEuler: primitive entries must be finite numbers"
    rho = prim[0].to_f()
    if !EulerSystem.finite_number?(rho) || rho <= ~0.0
      raise "CompressibleEuler: primitive density must be positive and finite"
    u = [rho]
    ke = ~0.0
    d = 0
    while d < @dim
      v = prim[1 + d].to_f()
      if !EulerSystem.finite_number?(v)
        raise "CompressibleEuler: primitive velocities must be finite"
      u.push(rho * v)
      ke = ke + v * v
      d = d + 1
    pressure = prim[1 + @dim].to_f()
    if !EulerSystem.finite_number?(pressure) || pressure <= ~0.0
      raise "CompressibleEuler: primitive pressure must be positive and finite"
    u.push(~0.5 * rho * ke + pressure / (@gas_gamma - ~1.0))
    self.validate_state(u)
    u

  # Conserved state -> [rho, v..., p].
  -> primitive(u)
    self.validate_state(u)
    prim = [u[0]]
    d = 0
    while d < @dim
      prim.push(u[1 + d] / u[0])
      d = d + 1
    prim.push(self.pressure(u))
    prim

+ IsothermalEuler < EulerSystem
  # vt: constant thermal velocity, must be positive. Accepts a Quantity
  # (converted to m/s) or a raw number.
  -> new(dim, vt)
    if !Physics.integer?(dim) || dim < 1 || dim > 3
      raise "IsothermalEuler: dim must be 1, 2, or 3 (got [dim])"
    @dim = dim
    @nstate = dim + 1
    @vt = Physics.si(vt, "m/s")
    if !self.params_valid?
      raise "IsothermalEuler: thermal velocity must be positive and finite"

  -> vt
    @vt

  -> name
    "isothermal_euler_[@dim]d"

  -> compressible?
    true

  -> energy_equation?
    false

  -> params_valid?
    EulerSystem.finite_number?(@vt) && @vt > ~0.0

  -> state_valid?(u)
    return false if !self.state_shape_valid?(u)
    k = 0
    while k < @nstate
      return false if !EulerSystem.finite_number?(u[k])
      k = k + 1
    u[0] > ~0.0

  # Effective pressure ρ v_t².
  -> pressure(u)
    self.validate_state(u)
    u[0] * @vt * @vt

  -> sound_speed(u)
    self.validate_state(u)
    @vt

  -> flux(u, dir)
    self.validate_direction(dir)
    self.validate_state(u)
    rho = u[0]
    mn = u[1 + dir]
    f = [mn]
    d = 0
    while d < @dim
      component = mn * u[1 + d] / rho
      component = component + rho * @vt * @vt if d == dir
      f.push(component)
      d = d + 1
    f

  -> conserved(prim)
    if prim.class_name != "Array" || prim.size != @nstate
      raise "IsothermalEuler: primitive state needs [@nstate] components"
    prim.each -> (value)
      if !EulerSystem.finite_number?(value)
        raise "IsothermalEuler: primitive entries must be finite numbers"
    rho = prim[0].to_f()
    if !EulerSystem.finite_number?(rho) || rho <= ~0.0
      raise "IsothermalEuler: primitive density must be positive and finite"
    u = [rho]
    d = 0
    while d < @dim
      velocity = prim[1 + d].to_f()
      if !EulerSystem.finite_number?(velocity)
        raise "IsothermalEuler: primitive velocities must be finite"
      u.push(rho * velocity)
      d = d + 1
    self.validate_state(u)
    u

  -> primitive(u)
    self.validate_state(u)
    prim = [u[0]]
    d = 0
    while d < @dim
      prim.push(u[1 + d] / u[0])
      d = d + 1
    prim

+ Physics
  # Facade constructors.
  -> .compressible_euler(dim, gas_gamma = 1.4)
    CompressibleEuler.new(dim, gas_gamma)

  -> .isothermal_euler(dim, vt)
    IsothermalEuler.new(dim, vt)
