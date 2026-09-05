# Focused finite-volume driver, CFL, admissibility, and layout checks.

use physics

-> fv_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> fv_close?(got, want, tolerance = ~1.0e-10)
  difference = (got - want).abs
  scale = want.abs
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance * scale

ce = Physics.compressible_euler(1, ~1.4)
fv = FiniteVolume.new(ce, [16], [~1.0])
fv.boundary(:periodic)
fv.init_each(-> (x) [~1.0, ~0.25, ~1.0])

fv_check("cfl.default", fv.cfl == ~0.4)
wavespeed = ~0.25 + Math.sqrt(~1.4)
expected_dt = ~0.4 / (wavespeed / (~1.0 / ~16.0))
fv_check("cfl.default_dt", fv_close?(fv.stable_dt, expected_dt))

fv.cfl = ~0.2
fv_check("cfl.setter", fv.cfl == ~0.2)
fv_check("cfl.setter_dt", fv_close?(fv.stable_dt, ~0.5 * expected_dt))

bad_cfl_rejected = false
begin
  fv.cfl = ~0.0
rescue error
  bad_cfl_rejected = error.to_s.include?("in (0, 1]")
fv_check("cfl.zero_rejected", bad_cfl_rejected)

cells_copy = fv.cells
cells_copy[0] = 1
fv_check("grid.cells_defensive_copy", fv.cells[0] == 16)

primitive = fv.primitive_cell(0)
fv_check("cell.primitive_density", primitive[0] == ~1.0)
fv_check("cell.primitive_velocity", primitive[1] == ~0.25)
fv_check("cell.primitive_pressure", fv_close?(primitive[2], ~1.0))
conserved = fv.conserved_cell(0)
fv_check("cell.conserved_momentum", conserved[1] == ~0.25)

invalid_state_rejected = false
begin
  fv.set_conserved_cell(0, [~1.0, ~10.0, ~1.0])
rescue error
  invalid_state_rejected = error.to_s.include?("admissible set")
fv_check("cell.invalid_conserved_rejected", invalid_state_rejected)

initial_totals = fv.totals
step_dt = fv.step!
final_totals = fv.totals
component = 0
conserved_ok = true
while component < initial_totals.size
  conserved_ok = (
    conserved_ok && fv_close?(initial_totals[component], final_totals[component]))
  component += 1
fv_check("step.periodic_conservation", conserved_ok)
fv_check("step.time", fv_close?(fv.time, step_dt))
fv_check("step.count", fv.steps == 1)
fv_check("step.admissible", fv.invalid_cells == 0)

rho = fv.field(:rho)
uniform = true
i = 0
while i < rho.size
  uniform = uniform && fv_close?(rho[i], ~1.0)
  i += 1
fv_check("step.constant_state", uniform)

too_large_dt_rejected = false
begin
  fv.step!(fv.stable_dt * ~1.01)
rescue error
  too_large_dt_rejected = error.to_s.include?("exceeds the configured CFL")
fv_check("step.unstable_dt_rejected", too_large_dt_rejected)

ie2 = Physics.isothermal_euler(2, ~1.0)
fv2 = FiniteVolume.new(ie2, [4, 4], [~1.0, ~1.0])
fv2.boundary(:periodic)
fv2.init_each(-> (x, y) [~1.0, ~0.0, ~0.0])
fv_check("cfl.2d_global_contract", fv_close?(fv2.stable_dt, ~0.05))

unsupported_field_rejected = false
begin
  fv2.field(:specific_internal_energy)
rescue error
  unsupported_field_rejected = error.to_s.include?("no internal-energy")
fv_check("field.isothermal_internal_energy_rejected",
         unsupported_field_rejected)

# The raw diagnostic kernel must reject positive rho/E with negative internal
# energy, which the old rho/E-only scan accepted.
bad_q = f64[15]
bad_mask = u8[5]
bad_q[6] = ~1.0
bad_q[7] = ~10.0
bad_q[8] = ~1.0
bad_count = FiniteVolume.kernel_invalid(
  bad_q, bad_mask, 5, 1, 1, 3, 1, 1)
fv_check("admissibility.kernel_negative_pressure", bad_count == 1)

# An invalid second-order face state falls back to its admissible cell average.
face_q = f64[15]
face_ql = f64[15]
face_qr = f64[15]
face_mask = u8[5]
face_mask[1] = 1
face_mask[3] = 1
face_q[6] = ~1.0
face_q[7] = ~0.0
face_q[8] = ~2.5
face_ql[6] = ~1.0
face_ql[7] = ~10.0
face_ql[8] = ~1.0
face_qr[6] = ~1.0
face_qr[7] = ~0.0
face_qr[8] = ~2.5
fallbacks = FiniteVolume.admissible_reconstruction(
  face_q, face_ql, face_qr, face_mask,
  0, 5, 1, 1, 0, 1, 0, 3, 1, 1)
fv_check("reconstruction.fallback_count", fallbacks == 1)
fv_check("reconstruction.fallback_left", face_ql[7] == ~0.0)
fv_check("reconstruction.fallback_right", face_qr[8] == ~2.5)

bad_grid_rejected = false
begin
  FiniteVolume.new(ce, [0], [~1.0])
rescue error
  bad_grid_rejected = error.to_s.include?("positive Integers")
fv_check("grid.zero_cells_rejected", bad_grid_rejected)

boundary_probe = FiniteVolume.new(ce, [8], [~1.0])
invalid_inflow_rejected = false
begin
  boundary_probe.boundary_face(0, 0, :inflow)
rescue error
  invalid_inflow_rejected = error.to_s.include?("needs a primitive state")
boundary_probe.init_each(-> (x) [~1.0, ~0.0, ~1.0])
boundary_probe.step!
boundary_uniform = true
boundary_rho = boundary_probe.field(:rho)
i = 0
while i < boundary_rho.size
  boundary_uniform = boundary_uniform && fv_close?(boundary_rho[i], ~1.0)
  i += 1
fv_check("boundary.invalid_inflow_rejected", invalid_inflow_rejected)
fv_check("boundary.rejected_inflow_is_atomic", boundary_uniform)

bad_mode_rejected = false
begin
  EulerSimulation.new(:typo, 1)
rescue error
  bad_mode_rejected = error.to_s.include?("mode must be")
fv_check("simulation.bad_mode_rejected", bad_mode_rejected)
fv_check("simulation.facade",
  Physics.compressible_simulation(1).mode == :compressible)

zero_frames_rejected = false
begin
  EulerSimulation.compressible(1).capture([:rho], 0)
rescue error
  zero_frames_rejected = error.to_s.include?("positive Integer")
fv_check("simulation.zero_frames_rejected", zero_frames_rejected)

tiny_target = ~1.0e-15
simulation = Physics.isothermal_simulation(1)
  .resolution([4])
  .domain([~1.0])
  .duration(tiny_target)
  .capture([:rho], 1)
  .init(-> (x) [~1.0, ~0.0])
simulation.run!
fv_check("simulation.tiny_duration_advances",
  simulation.fv.steps == 1 && simulation.fv.time == tiny_target)
fv_check("simulation.initial_plus_requested_frames",
  simulation.frames.size == 2)
simulation.resolution([6])
simulation.run!
fv_check("simulation.rerun_rebuilds_configuration",
  simulation.fv.cells[0] == 6 && simulation.fv.steps == 1)

# Inflow configuration order cannot change any face's prescribed state.
inflow_a = FiniteVolume.new(ie2, [4, 4], [~1.0, ~1.0])
inflow_b = FiniteVolume.new(ie2, [4, 4], [~1.0, ~1.0])
inflow_a.boundary_face(0, 0, :inflow, [~1.0, ~10.0, ~0.0])
inflow_a.boundary_face(1, 0, :inflow, [~2.0, ~0.0, ~20.0])
inflow_b.boundary_face(1, 0, :inflow, [~2.0, ~0.0, ~20.0])
inflow_b.boundary_face(0, 0, :inflow, [~1.0, ~10.0, ~0.0])
inflow_a.init_each(-> (x, y) [~1.0, ~0.0, ~0.0])
inflow_b.init_each(-> (x, y) [~1.0, ~0.0, ~0.0])
fv_check("inflow.multidimensional_cfl",
  fv_close?(inflow_a.stable_dt, ~0.4 / (~4.0 * (~11.0 + ~21.0))))
inflow_a.step!(~1.0e-4)
inflow_b.step!(~1.0e-4)
same_inflow = true
j = 0
while j < 4
  i = 0
  while i < 4
    same_inflow = same_inflow && inflow_a.cell(i, j) == inflow_b.cell(i, j)
    i += 1
  j += 1
fv_check("inflow.per_face_order_independent", same_inflow)

fast_inflow = FiniteVolume.new(Physics.isothermal_euler(1, ~1.0), [4], [~1.0])
fast_inflow.init_each(-> (x) [~1.0, ~0.0])
fast_inflow.boundary_face(0, 0, :inflow, [~1.0, ~100.0])
fv_check("inflow.cfl_includes_boundary",
  fv_close?(fast_inflow.stable_dt, ~0.4 / (~101.0 * ~4.0)))
fast_inflow.step!
fv_check("inflow.fast_default_step", fast_inflow.steps == 1 && fast_inflow.invalid_cells == 0)

# A one-cell impermeable wall isolates the right-hand initial-value problem.
wall_a = FiniteVolume.new(Physics.isothermal_euler(1, ~1.0), [7], [~7.0])
wall_b = FiniteVolume.new(Physics.isothermal_euler(1, ~1.0), [7], [~7.0])
wall_a.boundary(:reflect)
wall_b.boundary(:reflect)
wall_a.init_each(-> (x) [x < ~3.0 ? ~1.8 : x - ~2.5, ~0.0])
wall_b.init_each(-> (x) [x < ~3.0 ? ~0.2 : x - ~2.5, ~0.0])
wall_a.solid_each(-> (x) x > ~3.0 && x < ~4.0)
wall_b.solid_each(-> (x) x > ~3.0 && x < ~4.0)
wall_mass = wall_a.totals[0]
wall_a.step!(~0.001)
wall_b.step!(~0.001)
isolated = true
i = 4
while i < 7
  isolated = isolated && wall_a.cell(i) == wall_b.cell(i)
  i += 1
fv_check("solid.one_cell_wall_isolation", isolated)
fv_check("solid.wall_mass_conserved", fv_close?(wall_a.totals[0], wall_mass))

clock_probe = FiniteVolume.new(Physics.isothermal_euler(1, ~1.0), [1], [~10.0])
clock_probe.init_each(-> (x) [~1.0, ~0.0])
clock_probe.step!(~1.0)
before_clock_cell = clock_probe.cell(0)
tiny_step_rejected = false
begin
  clock_probe.step!(~1.0e-20)
rescue error
  tiny_step_rejected = error.to_s.include?("cannot advance")
fv_check("step.no_progress_rejected", tiny_step_rejected)
fv_check("step.no_progress_atomic",
  clock_probe.time == ~1.0 && clock_probe.steps == 1 && clock_probe.cell(0) == before_clock_cell)

unpaired_rejected = false
begin
  clock_probe.boundary_face(0, 0, :periodic)
  clock_probe.step!(~0.01)
rescue error
  unpaired_rejected = error.to_s.include?("must be paired")
fv_check("boundary.unpaired_periodic_rejected", unpaired_rejected)
clock_probe.boundary_face(0, 1, :periodic)
clock_probe.step!(~0.01)
fv_check("boundary.paired_periodic_accepted", clock_probe.steps == 2)

three_d = FiniteVolume.new(Physics.compressible_euler(3), [2, 2, 2], [~1.0, ~1.0, ~1.0])
three_d.boundary(:periodic)
three_d.init_each(-> (x, y, z) [~2.0, ~1.0, ~2.0, ~-3.0, ~4.0])
three_d.step!(~0.001)
fv_check("fields.transverse_velocities",
  three_d.field(:vy)[0] == ~2.0 && three_d.field(:vz)[0] == ~-3.0)
fv_check("fields.internal_energy_density",
  fv_close?(three_d.field(:internal_energy_density)[0], ~10.0))
fv_check("fields.internal_energy_units",
  fv_close?(three_d.field(:specific_internal_energy)[0], ~5.0))
inactive_field_rejected = false
begin
  fv2.field(:vz)
rescue error
  inactive_field_rejected = error.to_s.include?("inactive")
fv_check("fields.inactive_direction_rejected", inactive_field_rejected)

builder = Physics.isothermal_simulation(1).resolution([4]).domain([~1.0])
builder.duration(~0.001).capture([:rho], 1).init(-> (x) [~1.0, ~0.0])
bad_builder_boundary_rejected = false
begin
  builder.boundary(:teleport)
rescue error
  bad_builder_boundary_rejected = error.to_s.include?("unknown boundary")
fv_check("builder.boundary_validates_immediately", bad_builder_boundary_rejected)
begin
  builder.duration(~-1.0)
rescue error
  nil
builder.run!
fv_check("builder.rejected_change_is_atomic", builder.fv.time == ~0.001)

<< "physics_finite_volume_contract_spec: all checks passed"
