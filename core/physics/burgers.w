# Inviscid Burgers equation reference model.
#
# This module supplies analytic-form scalar relations and entropy-solution
# reference values, evaluated in ordinary numeric arithmetic, for
#
#   u_t + (u^2 / 2)_x = 0.
#
# It is intentionally not a spatial discretization or a time integrator. A
# finite-volume solver can use `godunov_flux`; benchmark and convergence code
# can use the Riemann solution without duplicating shock/rarefaction logic.

+ BurgersEquation
  -> .finite_number?(value)
    name = value.class_name
    numeric = name == "Float" || name == "Integer"
    numeric = true if name == "BigInt" || name == "Decimal"
    return false if !numeric
    number = value.to_f()
    !number.nan? && !number.infinite?

  -> .validate_value(value, label)
    if !BurgersEquation.finite_number?(value)
      raise label + " must be a finite number"
    true

  -> .flux(value)
    validate_value(value, "Burgers state")
    ~0.5 * value * value

  -> .characteristic_speed(value)
    validate_value(value, "Burgers state")
    value

  -> .entropy(value)
    validate_value(value, "Burgers state")
    ~0.5 * value * value

  -> .entropy_flux(value)
    validate_value(value, "Burgers state")
    value * value * value / ~3.0

  # Rankine-Hugoniot speed for the quadratic flux.
  -> .shock_speed(left, right)
    validate_value(left, "left Burgers state")
    validate_value(right, "right Burgers state")
    ~0.5 * (left + right)

  -> .riemann_kind(left, right)
    validate_value(left, "left Burgers state")
    validate_value(right, "right Burgers state")
    return :shock if left > right
    return :rarefaction if left < right
    :constant

  # Entropy solution as a function of xi = (x - x0) / t. At a shock this
  # adopts the right trace exactly on the discontinuity.
  -> .riemann_value(left, right, similarity_coordinate)
    validate_value(left, "left Burgers state")
    validate_value(right, "right Burgers state")
    validate_value(similarity_coordinate, "similarity coordinate")
    if left < right
      return left if similarity_coordinate <= left
      return right if similarity_coordinate >= right
      return similarity_coordinate
    if left > right
      return left if similarity_coordinate < shock_speed(left, right)
      return right
    left

  -> .riemann_value_at(left, right, x, time, origin = ~0.0)
    validate_value(left, "left Burgers state")
    validate_value(right, "right Burgers state")
    validate_value(x, "Burgers coordinate")
    validate_value(time, "Burgers Riemann time")
    validate_value(origin, "Burgers origin")
    raise "Burgers Riemann time cannot be negative" if time < ~0.0
    if time == ~0.0
      return left if x < origin
      return right
    similarity_coordinate = (x - origin) / time
    riemann_value(left, right, similarity_coordinate)

  # Entropy-consistent Godunov flux for the exact scalar Riemann problem.
  -> .godunov_flux(left, right)
    validate_value(left, "left Burgers state")
    validate_value(right, "right Burgers state")
    if left <= right
      return flux(left) if left >= ~0.0
      return flux(right) if right <= ~0.0
      return ~0.0
    return flux(left) if shock_speed(left, right) >= ~0.0
    flux(right)

  # First breaking time for u(x,0) = amplitude * sin(wavenumber * x).
  -> .sine_shock_time(amplitude, wavenumber)
    validate_value(amplitude, "sine amplitude")
    validate_value(wavenumber, "sine wavenumber")
    steepening_rate = amplitude.abs * wavenumber.abs
    if steepening_rate == ~0.0
      raise "sine shock time needs nonzero amplitude and wavenumber"
    ~1.0 / steepening_rate
