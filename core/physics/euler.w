# Euler systems of gas dynamics: full compressible (ideal-gas EOS) and
# isothermal, in 1, 2, or 3 space dimensions.
#
# This is the *reference* layer: boxed, dimension-generic, and a
# line-for-line mirror of the formally verified building blocks in
# Lanyon's CompressibleEuler C implementations (state validity, physical
# fluxes, characteristic wavespeeds). The finite-volume kernels in
# core/physics/finite_volume.w inline the same formulas on raw f64[]
# storage; the physics spec cross-checks the two.
#
# State vectors are plain Arrays in the C layout:
#   compressible: [rho, mom_x, (mom_y, (mom_z,)) energy]
#   isothermal:   [rho, mom_x, (mom_y, (mom_z))]
# with all entries raw ~f64. Momentum components are indexed 1..dim;
# `dir` arguments are 0-based (0 = x, 1 = y, 2 = z).

+ EulerSystem
  -> dim
    @dim

  -> nstate
    @nstate

  # Normal velocity in direction dir.
  -> velocity(u, dir)
    u[1 + dir] / u[0]

  # ½ ρ |v|² — kinetic energy density.
  -> kinetic_energy(u)
    total = ~0.0
    d = 0
    while d < @dim
      total = total + u[1 + d] * u[1 + d] / u[0]
      d = d + 1
    ~0.5 * total

  # Characteristic wavespeeds in direction dir, one per equation, ordered
  # [u_n - c, u_n, ..., u_n, u_n + c] exactly as the C wavespeed blocks.
  -> wavespeeds(u, dir)
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
    un = self.velocity(u, dir)
    c = self.sound_speed(u)
    lo = Math.abs(un - c)
    hi = Math.abs(un + c)
    lo > hi ? lo : hi

+ CompressibleEuler < EulerSystem
  # gas_gamma: adiabatic index, must exceed 1 (Decimal or Float accepted).
  -> new(dim, gas_gamma)
    if dim < 1 || dim > 3
      raise "CompressibleEuler: dim must be 1, 2, or 3 (got [dim])"
    @dim = dim
    @nstate = dim + 2
    @gas_gamma = Physics.dimensionless(gas_gamma)

  -> gas_gamma
    @gas_gamma

  -> name
    "compressible_euler_[@dim]d"

  -> compressible?
    true

  -> params_valid?
    @gas_gamma > ~1.0

  -> state_valid?(u)
    u[0] > ~0.0 && u[@nstate - 1] > ~0.0

  # p = (γ − 1)(E − ½ ρ |v|²)
  -> pressure(u)
    (@gas_gamma - ~1.0) * (u[@nstate - 1] - self.kinetic_energy(u))

  -> sound_speed(u)
    Math.sqrt(@gas_gamma * self.pressure(u) / u[0])

  # Physical flux vector in direction dir (the C x/y/z_flux blocks).
  -> flux(u, dir)
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
    rho = prim[0].to_f()
    u = [rho]
    ke = ~0.0
    d = 0
    while d < @dim
      v = prim[1 + d].to_f()
      u.push(rho * v)
      ke = ke + v * v
      d = d + 1
    u.push(~0.5 * rho * ke + prim[1 + @dim].to_f() / (@gas_gamma - ~1.0))
    u

  # Conserved state -> [rho, v..., p].
  -> primitive(u)
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
    if dim < 1 || dim > 3
      raise "IsothermalEuler: dim must be 1, 2, or 3 (got [dim])"
    @dim = dim
    @nstate = dim + 1
    @vt = Physics.si(vt, "m/s")

  -> vt
    @vt

  -> name
    "isothermal_euler_[@dim]d"

  -> compressible?
    false

  -> params_valid?
    @vt > ~0.0

  -> state_valid?(u)
    u[0] > ~0.0

  # Effective pressure ρ v_t².
  -> pressure(u)
    u[0] * @vt * @vt

  -> sound_speed(u)
    @vt

  -> flux(u, dir)
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
    rho = prim[0].to_f()
    u = [rho]
    d = 0
    while d < @dim
      u.push(rho * prim[1 + d].to_f())
      d = d + 1
    u

  -> primitive(u)
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
