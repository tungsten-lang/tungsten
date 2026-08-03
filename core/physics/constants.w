# Physical constants (CODATA 2022) and the Physics facade root.
#
# First worker of core/physics: defines + Physics and carries no dependency
# on any sibling worker (dispatch-shim role, per the module-split pattern).
# Later workers reopen + Physics to add facade methods.
#
# Every constant is exposed twice:
#   Physics.boltzmann      -> Quantity (dimensioned, for config/report layers)
#   Physics.boltzmann_si   -> raw ~f64 in SI base units (for numeric kernels)
#
# Quantities must never enter a hot loop (float * quantity dies; compound
# units heap-allocate) — cross to _si at the boundary, compute raw, and
# re-attach units only when reporting.

+ Physics
  # -- exact SI defining constants ----------------------------------------

  -> .speed_of_light
    299_792_458 m/s

  -> .speed_of_light_si
    ~299792458.0

  -> .boltzmann
    1.380649e-23 J/K

  -> .boltzmann_si
    ~1.380649e-23

  -> .planck
    6.62607015e-34 J·s

  -> .planck_si
    ~6.62607015e-34

  -> .avogadro_si
    ~6.02214076e23

  # Derived: R = N_A * kB, exact. J/(mol·K) is a registry unit; the mol⁻¹
  # spelling for bare Avogadro is not, which is why only _si exists above.
  -> .gas_constant
    8.31446261815324 J/(mol·K)

  -> .gas_constant_si
    ~8.31446261815324

  # -- conventional standards ---------------------------------------------

  -> .standard_gravity
    9.80665 m/s²

  -> .standard_gravity_si
    ~9.80665

  -> .standard_atmosphere
    101325 Pa

  -> .standard_atmosphere_si
    ~101325.0

  -> .stefan_boltzmann
    5.670374419e-8 W/(m²·K⁴)

  -> .stefan_boltzmann_si
    ~5.670374419e-8

  # -- measured (CODATA 2022) ---------------------------------------------

  -> .gravitational_constant
    6.6743e-11 m³/(kg·s²)

  -> .gravitational_constant_si
    ~6.6743e-11

  # -- common gas properties ----------------------------------------------

  # Adiabatic index: diatomic air, monatomic (e.g. helium, hydrogen plasma).
  -> .air_gamma
    ~1.4

  -> .monatomic_gamma
    ~5.0 / ~3.0

  # Specific gas constant of dry air.
  -> .air_gas_constant
    287.0528 J/(kg·K)

  -> .air_gas_constant_si
    ~287.0528

  -> .air_density
    1.225 kg/m³

  -> .air_density_si
    ~1.225

  # -- unit-boundary helper -------------------------------------------------

  # Raw f64 in the requested unit from a Quantity; plain numbers pass
  # through as f64 (assumed to already be in the requested unit).
  #
  #   Physics.si(2 km, "m")        == ~2000.0
  #   Physics.si(20 °C, "K")       == ~293.15
  #   Physics.si(0.4, "s")         == ~0.4
  #
  # Unit conversion needs a literal pipe target, so the supported unit
  # names are enumerated. Extend the case as new sim quantities appear.
  -> .si(value, unit_name)
    # Quantity detection uses w_quantity_unit_name (unit symbol, nil for
    # non-quantities): compiled inline caches die rather than deoptimize
    # when a .class/.to_f site alternates Decimal and Quantity receivers
    # (same 0xFFFD box kind) — see TODO.md. The quantity path lives in
    # its own method so every .to_f site stays monomorphic.
    unit = ccall("w_quantity_unit_name", value)
    if unit != nil
      Physics.si_quantity(value, unit_name)
    else
      value.to_f()

  # value is always a Quantity here. Temperatures use point-delta algebra:
  # (q|"K") - 0 K is a delta divisible by the unit delta (2 K - 1 K).
  -> .si_quantity(value, unit_name)
    out = ~0.0
    if unit_name == "m"
      out = ((value | "m") / 1 m).to_f()
    elsif unit_name == "s"
      out = ((value | "s") / 1 s).to_f()
    elsif unit_name == "kg"
      out = ((value | "kg") / 1 kg).to_f()
    elsif unit_name == "K"
      out = (((value | "K") - 0 K) / (2 K - 1 K)).to_f()
    elsif unit_name == "m/s"
      out = ((value | "m/s") / 1 m/s).to_f()
    elsif unit_name == "m/s²"
      out = ((value | "m/s²") / 1 m/s²).to_f()
    elsif unit_name == "kg/m³"
      out = ((value | "kg/m³") / 1 kg/m³).to_f()
    elsif unit_name == "Pa"
      out = ((value | "Pa") / 1 Pa).to_f()
    elsif unit_name == "J"
      out = ((value | "J") / 1 J).to_f()
    elsif unit_name == "J/K"
      out = ((value | "J/K") / 1 J/K).to_f()
    elsif unit_name == "J/(kg·K)"
      out = ((value | "J/(kg·K)") / 1 J/(kg·K)).to_f()
    elsif unit_name == "W"
      out = ((value | "W") / 1 W).to_f()
    elsif unit_name == "N"
      out = ((value | "N") / 1 N).to_f()
    else
      raise "Physics.si: unsupported unit '[unit_name]'"
    out

  # Raw f64 from a plain number (Int/Decimal/Float). Rejects Quantities so
  # a dimensioned value can't silently drop its unit.
  -> .dimensionless(value)
    unit = ccall("w_quantity_unit_name", value)
    if unit != nil
      raise "Physics.dimensionless: value carries units ([value])"
    value.to_f()
