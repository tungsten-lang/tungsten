# Physics module spec — constants, ideal gas EOS, Euler systems, and the
# Lax–Friedrichs/minmod blocks with their verified-property predicates.
#
# The block formulas mirror Lanyon's formally verified CompressibleEuler C
# implementations; the identities checked here (wave-sum, flux-jump,
# reconstruction consistency) are the same properties the Lean proofs
# certify for the C. Cross-validation against the C binaries themselves
# lives in ~/math/lanyonai/compressible-euler/validation.
#
# Runs in both engines:
#   bin/tungsten spec/core/physics_spec.w

use physics

-> physics_check(name, ok)
  if ok
    << "PASS [name]"
  else
    raise "FAIL [name]"

-> close?(got, want, tolerance = ~1.0e-10)
  d = got - want
  d = ~0.0 - d if d < ~0.0
  d < tolerance

# -- constants ---------------------------------------------------------------

physics_check("constants.c_si", Physics.speed_of_light_si == ~299792458.0)
physics_check("constants.atm_si", close?(Physics.standard_atmosphere_si, ~101325.0))
physics_check("constants.gamma", close?(Physics.air_gamma, ~1.4))

c_q = Physics.speed_of_light
physics_check("constants.c_quantity", close?(Physics.si(c_q, "m/s"), ~299792458.0))
atm = Physics.standard_atmosphere
physics_check("constants.atm_quantity", close?(Physics.si(atm, "Pa"), ~101325.0))

# Unit boundary: Quantities in any compatible unit cross to SI floats.
physics_check("si.km", close?(Physics.si(2 km, "m"), ~2000.0))
physics_check("si.celsius", close?(Physics.si(20 °C, "K"), ~293.15))
physics_check("si.plain", close?(Physics.si(0.4, "s"), ~0.4))
physics_check("si.density", close?(Physics.si(1.225 kg/m³, "kg/m³"), ~1.225))
physics_check("si.pressure_atm", close?(Physics.si(1 atm, "Pa"), ~101325.0))
physics_check("dimensionless", close?(Physics.dimensionless(1.4), ~1.4))

# -- ideal gas ----------------------------------------------------------------

# p = rho R T for air at sea level comes out near one atmosphere.
p_air = IdealGas.pressure(1.225 kg/m³, 287.0528 J/(kg·K), 288.15 K)
physics_check("ideal_gas.sea_level", close?(Physics.si(p_air, "Pa"), ~101308.0, ~50.0))

# c = sqrt(gamma R T): 340.3 m/s at 15 °C.
c_air = IdealGas.sound_speed(1.4, 287.0528 J/(kg·K), 288.15 K)
physics_check("ideal_gas.sound_speed", close?(c_air, ~340.3, ~0.1))

physics_check("ideal_gas.pressure_si",
  close?(IdealGas.pressure_si(~1.4, ~2.5, ~0.0), ~1.0))
physics_check("ideal_gas.internal_energy_si",
  close?(IdealGas.internal_energy_si(~1.4, ~1.0), ~2.5))
physics_check("ideal_gas.sound_speed_si",
  close?(IdealGas.sound_speed_si(~1.4, ~1.0, ~1.0), Math.sqrt(~1.4)))

# -- Euler systems ------------------------------------------------------------

ce = Physics.compressible_euler(3, 1.4)
physics_check("ce.params_valid", ce.params_valid?)
physics_check("ce.nstate", ce.nstate == 5)

prim = [~0.8, ~0.3, ~-0.4, ~0.2, ~0.7]
u = ce.conserved(prim)
back = ce.primitive(u)
ok = true
k = 0
while k < 5
  ok = ok && close?(back[k], prim[k])
  k = k + 1
physics_check("ce.primitive_roundtrip", ok)
physics_check("ce.state_valid", ce.state_valid?(u))
physics_check("ce.pressure", close?(ce.pressure(u), ~0.7))

# Wavespeed ordering: u_n - c < u_n < u_n + c in every direction.
dir = 0
ok = true
while dir < 3
  speeds = ce.wavespeeds(u, dir)
  un = ce.velocity(u, dir)
  cs = ce.sound_speed(u)
  ok = ok && close?(speeds[0], un - cs)
  ok = ok && close?(speeds[4], un + cs)
  ok = ok && close?(speeds[2], un)
  dir = dir + 1
physics_check("ce.wavespeeds", ok)

ie = Physics.isothermal_euler(2, 2 m/s)
physics_check("ie.vt_quantity", close?(ie.vt, ~2.0))
physics_check("ie.nstate", ie.nstate == 3)
u2 = ie.conserved([~1.5, ~0.4, ~-0.2])
physics_check("ie.pressure", close?(ie.pressure(u2), ~1.5 * ~4.0))
physics_check("ie.sound_speed", close?(ie.sound_speed(u2), ~2.0))

# -- Lax–Friedrichs blocks: the verified properties ----------------------------

ce1 = Physics.compressible_euler(1, 1.4)
ul = ce1.conserved([~1.0, ~0.75, ~1.0])
ur = ce1.conserved([~0.125, ~0.0, ~0.1])

physics_check("lf.waves_consistent", LaxFriedrichs.waves_consistent?(ce1, ul, 0))
physics_check("lf.waves_valid", LaxFriedrichs.waves_valid?(ce1, ul, ur, 0))
physics_check("lf.fluct_consistent", LaxFriedrichs.fluctuations_consistent?(ce1, ul, 0))
physics_check("lf.flux_jump", LaxFriedrichs.fluctuations_valid?(ce1, ul, ur, 0))

# Explicit flux-jump identity: A- + A+ == F(ur) - F(ul), componentwise.
left = LaxFriedrichs.left_fluctuation(ce1, ul, ur, 0)
right = LaxFriedrichs.right_fluctuation(ce1, ul, ur, 0)
fl = ce1.flux(ul, 0)
fr = ce1.flux(ur, 0)
ok = true
k = 0
while k < 3
  ok = ok && close?(left[k] + right[k], fr[k] - fl[k], ~1.0e-12)
  k = k + 1
physics_check("lf.flux_jump_exact", ok)

# The same identities hold for every direction of the isothermal 3D system.
ie3 = Physics.isothermal_euler(3, 1 m/s)
vl = ie3.conserved([~1.0, ~0.3, ~-0.2, ~0.1])
vr = ie3.conserved([~2.7, ~-1.1, ~0.6, ~-0.3])
dir = 0
ok = true
while dir < 3
  ok = ok && LaxFriedrichs.waves_valid?(ie3, vl, vr, dir)
  ok = ok && LaxFriedrichs.fluctuations_valid?(ie3, vl, vr, dir)
  dir = dir + 1
physics_check("lf.isothermal_3d", ok)

# -- minmod --------------------------------------------------------------------

physics_check("minmod.zero_at_extremum", close?(Minmod.slope(~1.0, ~-1.0), ~0.0))
physics_check("minmod.takes_smaller", close?(Minmod.slope(~0.5, ~2.0), ~0.5))
physics_check("minmod.negative", close?(Minmod.slope(~-0.5, ~-2.0), ~-0.5))
physics_check("minmod.left_consistent", Minmod.left_consistent?(ul))
physics_check("minmod.right_consistent", Minmod.right_consistent?(ul))

rec_l = Minmod.left([~1.0, ~1.0, ~1.0], [~2.0, ~2.0, ~2.0], [~4.0, ~4.0, ~4.0])
rec_r = Minmod.right([~1.0, ~1.0, ~1.0], [~2.0, ~2.0, ~2.0], [~4.0, ~4.0, ~4.0])
physics_check("minmod.left_edge", close?(rec_l[0], ~1.5))
physics_check("minmod.right_edge", close?(rec_r[0], ~2.5))

<< "PHYSICS_SPEC_OK"
