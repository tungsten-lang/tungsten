# Ideal-gas equation of state.
#
# Two API layers:
#   - Quantity-level class methods (pressure/density/temperature/sound_speed)
#     for dimensioned configuration and reporting. These use only +,-,*,/
#     between quantities, so unit algebra stays sound.
#   - _si raw-f64 twins for numeric code.
#
# The gamma-law relations used by the Euler solvers
# (p = (γ−1)(E − ½ρ|u|²), c = √(γp/ρ)) live here in raw form; the
# finite-volume kernels inline them for speed, and the spec suite checks
# the inlined copies against these references.

+ IdealGas
  # p = ρ R_s T  (specific gas constant form). Quantity in, Quantity out.
  # The registry keeps temperature deltas as their own dimension, so the
  # K⁻¹ inside R_s can't cancel a delta directly; each factor crosses to
  # an exact dimensionless Decimal and the SI unit is reattached at the
  # end (Decimal · Quantity multiplication is exact).
  -> .pressure(density, specific_gas_constant, temperature)
    rho = (density | "kg/m³") / 1 kg/m³
    rs = (specific_gas_constant | "J/(kg·K)") / 1 J/(kg·K)
    t = ((temperature | "K") - 0 K) / (2 K - 1 K)
    rho * rs * t * 1 Pa

  -> .density(pressure, specific_gas_constant, temperature)
    p = (pressure | "Pa") / 1 Pa
    rs = (specific_gas_constant | "J/(kg·K)") / 1 J/(kg·K)
    t = ((temperature | "K") - 0 K) / (2 K - 1 K)
    p / (rs * t) * 1 kg/m³

  # Absolute temperature as kelvins above absolute zero (a K delta).
  -> .temperature(pressure, density, specific_gas_constant)
    p = (pressure | "Pa") / 1 Pa
    rho = (density | "kg/m³") / 1 kg/m³
    rs = (specific_gas_constant | "J/(kg·K)") / 1 J/(kg·K)
    p / (rho * rs) * (2 K - 1 K)

  # -- raw f64 gamma-law core ----------------------------------------------

  -> .pressure_si(gas_gamma, energy, kinetic_energy) (f64 f64 f64) f64
    (gas_gamma - ~1.0) * (energy - kinetic_energy)

  -> .internal_energy_si(gas_gamma, pressure) (f64 f64) f64
    pressure / (gas_gamma - ~1.0)

  -> .sound_speed_si(gas_gamma, pressure, density) (f64 f64 f64) f64
    Math.sqrt(gas_gamma * pressure / density)

  # Speed of sound c = √(γ R_s T). Accepts Quantities or raw SI numbers;
  # returns raw f64 in m/s (square roots have no Quantity form).
  -> .sound_speed(gas_gamma, specific_gas_constant, temperature)
    gamma_f = Physics.dimensionless(gas_gamma)
    rs = Physics.si(specific_gas_constant, "J/(kg·K)")
    t = Physics.si(temperature, "K")
    Math.sqrt(gamma_f * rs * t)

  # Mach number from dimensioned or raw m/s speeds.
  -> .mach_number(speed, sound_speed)
    Physics.si(speed, "m/s") / Physics.si(sound_speed, "m/s")
