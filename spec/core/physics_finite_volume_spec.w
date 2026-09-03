# FiniteVolume (core/physics/finite_volume.w): the LeVeque wave-propagation
# solver for the Euler systems on uniform Cartesian grids.
#
# Correctness anchors, not smoke tests:
#   - conservation:  a periodic domain conserves mass, momentum and energy to
#                    round-off, and so does an outflow domain for as long as
#                    no wave has reached a face;
#   - advection:     a density bump riding on a uniform (rho, p) flow is a
#                    contact discontinuity, so its excess-density centroid
#                    must translate at exactly the flow speed;
#   - Sod:           the classical shock tube against the *exact* Riemann
#                    solution (p* = 0.30313, u* = 0.92745, rho*L = 0.42632,
#                    rho*R = 0.26557, shock speed 1.7522) at t = 0.2;
#   - equilibrium:   a uniform state is a fixed point of the whole operator;
#   - EOS wiring:    E = p/(gamma-1) for CompressibleEuler, p = rho vt^2 for
#                    IsothermalEuler.
#
#   bin/tungsten -o /tmp/physics-fv-spec spec/core/physics_finite_volume_spec.w && /tmp/physics-fv-spec
#   bin/tungsten run --interpret spec/core/physics_finite_volume_spec.w
#     (compiled: well under a second; interpreted: minutes — every kernel is
#      a cell-by-cell machine loop, so this file's lane is `compiled`.)

use physics

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> close?(got, want, tolerance = ~1.0e-12)
  d = got - want
  d = ~0.0 - d if d < ~0.0
  d <= tolerance

-> rel_close?(got, want, tolerance = ~1.0e-12)
  scale = want
  scale = ~0.0 - scale if scale < ~0.0
  scale = ~1.0 if scale < ~1.0
  close?(got, want, tolerance * scale)

GAMMA = ~1.4

# --- grid geometry ----------------------------------------------------------

geom = FiniteVolume.new(Physics.compressible_euler(1, GAMMA), [200], [~1.0])
check("grid.cells", geom.cells[0] == 200)
check("grid.dx", close?(geom.dx(0), ~0.005))
check("grid.centre.first", close?(geom.centre(0, 0), ~0.0025))
check("grid.centre.last", close?(geom.centre(0, 199), ~0.9975))
# cell (i) sits i cells past the two-deep ghost ring
check("grid.index.ghost_offset", geom.cell_index(0) == 2)
check("grid.index.stride", geom.cell_index(7) - geom.cell_index(6) == 1)
check("grid.clock.starts_at_zero", geom.time == ~0.0 && geom.steps == 0)
check("grid.default_cfl", close?(geom.cfl, ~0.4))

# --- primitive <-> conserved round trip through the grid --------------------

geom.init_each -> (x) [~1.25, ~0.3, ~0.8]
cell = geom.cell(11)
# rho, rho*u, E = p/(gamma-1) + rho u^2 / 2
check("state.density", close?(cell[0], ~1.25))
check("state.momentum", close?(cell[1], ~1.25 * ~0.3))
check("state.energy", close?(cell[2], ~0.8 / ~0.4 + ~0.5 * ~1.25 * ~0.09))
check("state.field.rho", close?(geom.field(:rho)[11], ~1.25))
check("state.field.pressure", close?(geom.field(:pressure)[11], ~0.8))
check("state.field.vx", close?(geom.field(:vx)[11], ~0.3))
check("state.field.speed", close?(geom.field(:speed)[11], ~0.3))
# specific internal energy e = p / ((gamma - 1) rho)
check("state.field.internal_energy",
      close?(geom.field(:internal_energy)[11], ~0.8 / (~0.4 * ~1.25)))
check("state.field.size", geom.field(:rho).size == 200)
check("state.positivity", geom.invalid_cells == 0)
# uniform state over a unit domain: mass = rho, energy = E
tot = geom.totals
check("totals.mass", rel_close?(tot[0], ~1.25))
check("totals.momentum", rel_close?(tot[1], ~1.25 * ~0.3))
check("totals.energy", rel_close?(tot[2], ~0.8 / ~0.4 + ~0.5 * ~1.25 * ~0.09))

# --- a uniform state is a fixed point of the operator -----------------------

still = FiniteVolume.new(Physics.compressible_euler(1, GAMMA), [16], [~1.0])
still.boundary(:reflect)
still.init_each -> (x) [~2.0, ~0.0, ~3.0]
dt_taken = still.step!(~0.001)
check("uniform.step_returns_dt", close?(dt_taken, ~0.001))
check("uniform.clock_advanced", close?(still.time, ~0.001) && still.steps == 1)
check("uniform.density_unchanged", close?(still.field(:rho)[7], ~2.0))
check("uniform.pressure_unchanged", close?(still.field(:pressure)[7], ~3.0))
check("uniform.momentum_stays_zero", close?(still.cell(7)[1], ~0.0))
check("uniform.energy_unchanged", close?(still.cell(7)[2], ~3.0 / ~0.4))
# reflect walls do not manufacture momentum either
check("uniform.wall_cell", close?(still.field(:rho)[0], ~2.0))

# --- CFL timestep -----------------------------------------------------------

# uniform state at rest: a_max = c = sqrt(gamma p / rho) = sqrt(1.4*3/2)
sound = Math.sqrt(GAMMA * ~3.0 / ~2.0)
check("cfl.stable_dt", rel_close?(still.stable_dt, still.cfl * (~1.0 / ~16.0) / sound, ~1.0e-12))
still.cfl = ~0.2
check("cfl.setter", close?(still.cfl, ~0.2))
check("cfl.halved_dt", rel_close?(still.stable_dt, ~0.2 * (~1.0 / ~16.0) / sound, ~1.0e-12))

# --- periodic conservation + advection at the flow speed --------------------

# A Gaussian density bump on a uniform-pressure, uniform-velocity flow is a
# pure contact wave: it must translate at u with no change of mass.
bump = FiniteVolume.new(Physics.compressible_euler(1, GAMMA), [128], [~1.0])
bump.boundary(:periodic)
bump.init_each -> (x)
  d = x - ~0.25
  [~1.0 + ~0.5 * Math.exp(~0.0 - ~200.0 * d * d), ~1.0, ~1.0]
before = bump.totals
bump.run_to!(~0.25)
after = bump.totals
check("periodic.mass_conserved", rel_close?(after[0], before[0], ~1.0e-13))
check("periodic.momentum_conserved", rel_close?(after[1], before[1], ~1.0e-13))
check("periodic.energy_conserved", rel_close?(after[2], before[2], ~1.0e-13))
check("periodic.reached_t_end", close?(bump.time, ~0.25, ~1.0e-13))
check("periodic.took_steps", bump.steps > 10)
check("periodic.positivity", bump.invalid_cells == 0)

rho_bump = bump.field(:rho)
numerator = ~0.0
denominator = ~0.0
i = 0
while i < 128
  excess = rho_bump[i] - ~1.0
  numerator = numerator + excess * bump.centre(0, i)
  denominator = denominator + excess
  i = i + 1
# started at x = 0.25, u = 1 m/s, t = 0.25 s  =>  centroid at x = 0.5
check("advection.centroid_moved_at_u",
      close?(numerator / denominator, ~0.5, ~1.0e-3))
# the contact is only diffused, never amplified: no new extrema
check("advection.no_overshoot", rho_bump.max <= ~1.5 + ~1.0e-12)
check("advection.no_undershoot", rho_bump.min >= ~1.0 - ~1.0e-12)
# and the bump really moved: the peak is no longer where it started
check("advection.peak_left_origin", rho_bump[31] < rho_bump[63])

# --- Sod shock tube against the exact Riemann solution ----------------------

sod = FiniteVolume.new(Physics.compressible_euler(1, GAMMA), [200], [~1.0])
sod.boundary(:outflow)
# (if/else, not an early `return`: `return` inside a lambda body is broken in
#  the native interpreter — it escapes the lambda as a __SIGNAL__ error.)
sod.init_each -> (x)
  if x < ~0.5
    [~1.0, ~0.0, ~1.0]
  else
    [~0.125, ~0.0, ~0.1]
sod_mass0 = sod.totals[0]
sod_energy0 = sod.totals[2]
check("sod.initial_mass", rel_close?(sod_mass0, ~0.5625))
check("sod.initial_energy", rel_close?(sod_energy0, ~0.5 * ~2.5 + ~0.5 * ~0.25))
sod.run_to!(~0.2)
check("sod.positivity", sod.invalid_cells == 0)
# outflow faces, but at t = 0.2 no wave has reached either face, so the
# solver is still exactly conservative in mass and energy
check("sod.mass_conserved", rel_close?(sod.totals[0], sod_mass0, ~1.0e-12))
check("sod.energy_conserved", rel_close?(sod.totals[2], sod_energy0, ~1.0e-12))

sod_rho = sod.field(:rho)
sod_p = sod.field(:pressure)
sod_v = sod.field(:vx)
# no new extrema: the exact solution stays inside [0.125, 1]
check("sod.max_density", sod_rho.max <= ~1.0 + ~1.0e-12)
check("sod.min_density", sod_rho.min >= ~0.125 - ~1.0e-12)
# rarefaction head travels at -c_L = -1.1832: x < 0.26 is untouched
check("sod.left_undisturbed_rho", close?(sod_rho[8], ~1.0, ~1.0e-6))
check("sod.left_undisturbed_p", close?(sod_p[8], ~1.0, ~1.0e-6))
check("sod.left_undisturbed_v", close?(sod_v[8], ~0.0, ~1.0e-6))
# shock sits at 0.5 + 1.7522*0.2 = 0.8504: x > 0.86 is untouched
check("sod.right_undisturbed_rho", close?(sod_rho[190], ~0.125, ~1.0e-6))
check("sod.right_undisturbed_p", close?(sod_p[190], ~0.1, ~1.0e-6))
# star region, left of the contact at x = 0.6855: rho*L = 0.42632
check("sod.star_left_density", close?(sod_rho[120], ~0.42632, ~0.005))
# star region, right of the contact and left of the shock: rho*R = 0.26557
check("sod.star_right_density", close?(sod_rho[156], ~0.26557, ~0.005))
# pressure and velocity are continuous across the contact: p* and u*
check("sod.star_pressure_left", close?(sod_p[120], ~0.30313, ~0.005))
check("sod.star_pressure_right", close?(sod_p[156], ~0.30313, ~0.005))
check("sod.star_velocity_left", close?(sod_v[120], ~0.92745, ~0.01))
check("sod.star_velocity_right", close?(sod_v[156], ~0.92745, ~0.01))
# the contact is a density jump with no pressure jump
check("sod.contact_density_drops", sod_rho[120] > sod_rho[156] + ~0.1)
check("sod.contact_pressure_flat", close?(sod_p[120] - sod_p[156], ~0.0, ~0.005))
# monotone decrease through the rarefaction fan
check("sod.rarefaction_monotone", sod_rho[70] > sod_rho[90] && sod_rho[90] > sod_rho[110])
# the shock is a jump of at least 2x in density inside a handful of cells
check("sod.shock_present", sod_rho[165] > ~2.0 * sod_rho[180])

# --- isothermal Euler: p = rho vt^2 -----------------------------------------

iso = FiniteVolume.new(Physics.isothermal_euler(1, ~2.0), [16], [~1.0])
iso.boundary(:periodic)
iso.init_each -> (x) [~1.5, ~0.0]
check("isothermal.nstate", iso.cell(3).size == 2)
check("isothermal.density", close?(iso.cell(3)[0], ~1.5))
check("isothermal.pressure", close?(iso.field(:pressure)[3], ~1.5 * ~4.0))
check("isothermal.sound_speed_dt",
      rel_close?(iso.stable_dt, iso.cfl * (~1.0 / ~16.0) / ~2.0, ~1.0e-12))
iso.run_to!(~0.05)
check("isothermal.uniform_is_steady", close?(iso.field(:rho)[3], ~1.5, ~1.0e-12))

# --- two dimensions: conservation on a doubly periodic square ---------------

two_d = FiniteVolume.new(Physics.compressible_euler(2, GAMMA), [24, 24], [~1.0, ~1.0])
two_d.boundary(:periodic)
two_d.init_each -> (x, y)
  [~1.0 + ~0.3 * Math.sin(~6.283185307179586 * x), ~0.7, ~-0.4, ~1.0]
check("2d.dx", close?(two_d.dx(0), ~1.0 / ~24.0) && close?(two_d.dx(1), ~1.0 / ~24.0))
check("2d.nstate", two_d.cell(0, 0).size == 4)
# the sine averages to zero over the period, so the mean density is 1
d2_before = two_d.totals
check("2d.initial_mass", rel_close?(d2_before[0], ~1.0, ~1.0e-12))
check("2d.initial_x_momentum", rel_close?(d2_before[1], ~0.7, ~1.0e-12))
check("2d.initial_y_momentum", rel_close?(d2_before[2], ~-0.4, ~1.0e-12))
two_d.run_to!(~0.1)
d2_after = two_d.totals
check("2d.mass_conserved", rel_close?(d2_after[0], d2_before[0], ~1.0e-12))
check("2d.x_momentum_conserved", rel_close?(d2_after[1], d2_before[1], ~1.0e-12))
check("2d.y_momentum_conserved", rel_close?(d2_after[2], d2_before[2], ~1.0e-12))
check("2d.energy_conserved", rel_close?(d2_after[3], d2_before[3], ~1.0e-12))
check("2d.positivity", two_d.invalid_cells == 0)
# the initial state is y-invariant, and a periodic solver keeps it that way
row_a = two_d.field(:rho)
check("2d.stays_y_invariant", close?(row_a[5], row_a[5 + 24 * 13], ~1.0e-12))

# --- solid (stair-step) mask ------------------------------------------------

solid = FiniteVolume.new(Physics.compressible_euler(1, GAMMA), [10], [~1.0])
solid.init_each -> (x) [~1.0, ~0.0, ~1.0]
marked = solid.solid_each -> (x) x > ~0.5
check("solid.count", marked == 5)
check("solid.predicate_true", solid.solid?(5) && solid.solid?(9))
check("solid.predicate_false", !solid.solid?(0) && !solid.solid?(4))
grid = solid.mask_grid
check("solid.mask_size", grid.size == 10)
check("solid.mask_values", grid[0] == 0 && grid[4] == 0 && grid[5] == 1 && grid[9] == 1)
# solid cells are excluded from the interior totals: only 5 fluid cells left
check("solid.totals_skip_solid", rel_close?(solid.totals[0], ~0.5, ~1.0e-12))

# --- inflow face carries the state it was given -----------------------------

inflow = FiniteVolume.new(Physics.compressible_euler(1, GAMMA), [40], [~1.0])
inflow.boundary(:outflow)
inflow.boundary_face(0, 0, :inflow, [~2.0, ~1.0, ~1.5])
inflow.init_each -> (x) [~1.0, ~1.0, ~1.5]
inflow.run_to!(~0.05)
check("inflow.positivity", inflow.invalid_cells == 0)
# denser fluid is being pushed in from the left, so cell 0 has grown
check("inflow.raises_upstream_density", inflow.field(:rho)[0] > ~1.05)
# and the far end has not heard about it yet (u + c ~ 2.02, t = 0.05)
check("inflow.downstream_untouched", close?(inflow.field(:rho)[39], ~1.0, ~1.0e-6))

# --- loud failures ----------------------------------------------------------

raised = false
begin
  FiniteVolume.new(Physics.compressible_euler(2, GAMMA), [10], [~1.0])
rescue e
  raised = true
check("error.dimension_mismatch", raised)

raised = false
begin
  geom.boundary_face(0, 0, :teleport, nil)
rescue e
  raised = true
check("error.unknown_boundary_kind", raised)

raised = false
begin
  geom.boundary_face(0, 0, :inflow, nil)
rescue e
  raised = true
check("error.inflow_needs_a_state", raised)

raised = false
begin
  geom.field(:enthalpy)
rescue e
  raised = true
check("error.unknown_field", raised)

<< "physics_finite_volume_spec: all checks passed"
