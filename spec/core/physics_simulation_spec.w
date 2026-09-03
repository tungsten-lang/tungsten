# EulerSimulation (core/physics/simulation.w): the dimensioned builder layer
# over FiniteVolume.
#
# What must hold:
#   - every builder method returns self, so the chain in the module's own
#     doc-comment composes;
#   - Quantities cross to raw SI exactly once, at solver construction —
#     a 2 km domain is 2000 m and 300 ms is 0.3 s;
#   - a run captures frame_count + 1 frames on a uniform time cadence and
#     lands exactly on the requested duration;
#   - captured frames are min/max-quantized fields whose recorded range is
#     the real range of the underlying field;
#   - viewer_spec reports the geometry, field names and metadata actually
#     used, and the physics still conserves mass on a periodic domain.
#
#   bin/tungsten -o /tmp/physics-sim-spec spec/core/physics_simulation_spec.w && /tmp/physics-sim-spec
#   bin/tungsten run --interpret spec/core/physics_simulation_spec.w
#     (compiled: well under a second; interpreted: minutes — the FiniteVolume
#      kernels underneath are cell-by-cell machine loops, so the lane is
#      `compiled`.)

use physics

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> close?(got, want, tolerance = ~1.0e-12)
  d = got - want
  d = ~0.0 - d if d < ~0.0
  d <= tolerance

# --- the builder chain returns self at every link ---------------------------

blank = EulerSimulation.compressible(1)
check("builder.titled", blank.titled("x") == blank)
check("builder.resolution", blank.resolution([8]) == blank)
check("builder.domain", blank.domain([~1.0]) == blank)
check("builder.gas_gamma", blank.gas_gamma(1.4) == blank)
check("builder.duration", blank.duration(~1.0) == blank)
check("builder.courant", blank.courant(0.3) == blank)
check("builder.capture", blank.capture([:rho], 4) == blank)
check("builder.boundary", blank.boundary(:periodic) == blank)
check("builder.boundary_face", blank.boundary_face(0, 1, :outflow, nil) == blank)
check("builder.meta", blank.meta("note", 42) == blank)
check("builder.init", blank.init(-> (x) [~1.0, ~0.0, ~1.0]) == blank)
check("builder.solid", blank.solid(-> (x) false) == blank)
check("builder.title_readback", blank.title == "x")
check("builder.no_solver_until_built", blank.fv == nil)
check("builder.frames_start_empty", blank.frames.size == 0)

# --- units cross to SI once, at construction --------------------------------

united = EulerSimulation.compressible(1)
  .resolution([10])
  .domain([2 km])
  .duration(300 ms)
  .courant(0.25)
  .gas_gamma(1.4)
united.init -> (x) [~1.0, ~0.0, ~1.0]
solver = united.build_solver
check("units.domain_km_to_m", close?(solver.dx(0), ~200.0))
check("units.centre_in_metres", close?(solver.centre(0, 0), ~100.0))
check("units.courant", close?(solver.cfl, ~0.25))
check("units.build_returns_the_fv", solver == united.fv)

thermal = EulerSimulation.isothermal(1)
  .resolution([8])
  .domain([1 m])
  .thermal_velocity(2000 m/s)
thermal.init -> (x) [~1.0, ~0.0]
thermal_fv = thermal.build_solver
# p = rho vt^2 with vt = 2000 m/s
check("units.thermal_velocity_m_per_s",
      close?(thermal_fv.field(:pressure)[0], ~4.0e6, ~1.0))
check("units.isothermal_nstate", thermal_fv.cell(0).size == 2)
# BUG: a prefixed *length* over seconds is a broken unit literal — `2 km/s`
# and `2 cm/s` SIGSEGV compiled and raise "undefined method 'size' for
# Object" interpreted, while `2 km/h`, `2 kg/m`, `2 m/s` and `2 km` are all
# fine. Repro: `bin/tungsten -e "use physics" -e "v = 2 km/s"`, or the two
# lines `use physics` / `v = 2 km/s` in a file.
# thermal_km = EulerSimulation.isothermal(1)
#   .resolution([8]).domain([1 m]).thermal_velocity(2 km/s)
# thermal_km.init -> (x) [~1.0, ~0.0]
# check("units.thermal_velocity_km_per_s",
#       close?(thermal_km.build_solver.field(:pressure)[0], ~4.0e6, ~1.0))

# --- a compressible 1D run: cadence, endpoint, capture ----------------------

sod = EulerSimulation.compressible(1)
  .titled("sod tube")
  .resolution([64])
  .domain([1 m])
  .gas_gamma(1.4)
  .duration(0.1 s)
  .courant(0.3)
  .boundary(:outflow)
  .capture([:rho, :pressure], 4)
# (if/else, not an early `return`: `return` inside a lambda body is broken in
#  the native interpreter — it escapes the lambda as a __SIGNAL__ error.)
sod.init -> (x)
  if x < ~0.5
    [~1.0, ~0.0, ~1.0]
  else
    [~0.125, ~0.0, ~0.1]
sod.run!

check("run.frame_count", sod.frames.size == 5)
check("run.lands_on_duration", close?(sod.fv.time, ~0.1, ~1.0e-13))
check("run.took_steps", sod.fv.steps > 4)
check("run.positivity", sod.fv.invalid_cells == 0)
check("run.first_frame_at_zero", close?(sod.frames[0][:t], ~0.0))
check("run.last_frame_at_end", close?(sod.frames[4][:t], ~0.1, ~1.0e-13))
# uniform cadence: frame k is at k * duration / 4
check("run.cadence_1", close?(sod.frames[1][:t], ~0.025, ~1.0e-13))
check("run.cadence_2", close?(sod.frames[2][:t], ~0.05, ~1.0e-13))
check("run.cadence_3", close?(sod.frames[3][:t], ~0.075, ~1.0e-13))
check("run.frames_monotone", sod.frames[1][:t] < sod.frames[2][:t])

first = sod.frames[0][:fields]
check("capture.field_names", first.keys.size == 2)
check("capture.has_rho", first["rho"] != nil)
check("capture.has_pressure", first["pressure"] != nil)
# the packed frame records the true min/max of the field it quantized
check("capture.rho_min", close?(first["rho"]["min"], ~0.125))
check("capture.rho_max", close?(first["rho"]["max"], ~1.0))
check("capture.pressure_min", close?(first["pressure"]["min"], ~0.1))
check("capture.pressure_max", close?(first["pressure"]["max"], ~1.0))
check("capture.base64_present", first["rho"]["b64"].size > 0)
# 64 cells -> 64 bytes -> ceil(64/3)*4 = 88 base64 characters
check("capture.base64_length", first["rho"]["b64"].size == 88)

# the shock tube still obeys the exact Riemann solution's undisturbed regions
sod_rho = sod.fv.field(:rho)
check("run.left_undisturbed", close?(sod_rho[2], ~1.0, ~1.0e-6))
check("run.right_undisturbed", close?(sod_rho[61], ~0.125, ~1.0e-6))
check("run.no_new_extrema", sod_rho.max <= ~1.0 + ~1.0e-12 &&
                            sod_rho.min >= ~0.125 - ~1.0e-12)

# --- viewer_spec ------------------------------------------------------------

view = sod.viewer_spec
check("viewer.kind_1d", view[:kind] == "spacetime")
check("viewer.title", view[:title] == "sod tube")
check("viewer.dims", view[:dims][0] == 64 && view[:dims][1] == 1 && view[:dims][2] == 1)
check("viewer.domain", close?(view[:domain][0], ~1.0))
check("viewer.fields", view[:fields][0] == "rho" && view[:fields][1] == "pressure")
check("viewer.frames_attached", view[:frames].size == 5)
check("viewer.no_mask_without_solid", view[:mask] == nil)
check("viewer.meta_system", view[:meta]["system"] == "compressible Euler 1D")
# (brackets escaped: a bare "[64]" in a Tungsten string interpolates to "64")
check("viewer.meta_resolution", view[:meta]["resolution"] == "\[64]")
check("viewer.meta_steps", view[:meta]["steps"] == "[sod.fv.steps]")
check("viewer.meta_gamma_reported", view[:meta]["gamma"].starts_with?("1.4"))
check("viewer.meta_duration_reported", view[:meta]["duration, s"].starts_with?("0.1"))
check("viewer.meta_cfl_reported", view[:meta]["CFL"].starts_with?("0.3"))
# BUG: `Decimal#to_f` is not correctly rounded, so the gamma the builder
# stores (Physics.dimensionless(1.4), i.e. (1.4).to_f = 1.4000000000000001)
# is one ulp above the nearest double `~1.4` = 1.3999999999999999. Same for
# 0.3 and 3.3; 0.1, 0.2 and 1.1 round correctly. Repro (both engines):
#   bin/tungsten -e '<< "[(1.4).to_f] [~1.4] [(0.3).to_f] [~0.3]"'
# check("viewer.meta_gamma", view[:meta]["gamma"] == "[~1.4]")

# --- 2D: periodic mass conservation, surface viewer, extra metadata ---------

square = EulerSimulation.compressible(2)
  .titled("shear layer")
  .resolution([16, 16])
  .domain([1 m, 1 m])
  .duration(0.05 s)
  .boundary(:periodic)
  .capture([:rho], 2)
  .meta("note", "y-invariant")
square.init -> (x, y)
  [~1.0 + ~0.2 * Math.sin(~6.283185307179586 * x), ~0.5, ~0.0, ~1.0]
square.run!
check("2d.frames", square.frames.size == 3)
check("2d.viewer_kind", square.viewer_spec[:kind] == "surface")
check("2d.viewer_dims", square.viewer_spec[:dims][1] == 16 &&
                        square.viewer_spec[:dims][2] == 1)
check("2d.meta_extra", square.viewer_spec[:meta]["note"] == "y-invariant")
# the sine integrates to zero over the period: mean density 1, conserved
check("2d.mass_conserved", close?(square.fv.totals[0], ~1.0, ~1.0e-12))
check("2d.y_momentum_stays_zero", close?(square.fv.totals[2], ~0.0, ~1.0e-12))
check("2d.positivity", square.fv.invalid_cells == 0)

# --- a solid body publishes a mask ------------------------------------------

blocked = EulerSimulation.compressible(1)
  .resolution([10])
  .domain([1 m])
  .duration(0.001 s)
  .capture([:rho], 1)
blocked.init -> (x) [~1.0, ~0.0, ~1.0]
blocked.solid -> (x) x > ~0.5
blocked.run!
check("solid.mask_published", blocked.viewer_spec[:mask] != nil)
check("solid.mask_base64_length", blocked.viewer_spec[:mask].size == 16)
check("solid.cells_marked", blocked.fv.solid?(9) && !blocked.fv.solid?(0))

# --- loud failures ----------------------------------------------------------

raised = false
begin
  EulerSimulation.compressible(2).resolution([4])
rescue e
  raised = true
check("error.resolution_arity", raised)

raised = false
begin
  EulerSimulation.compressible(2).domain([~1.0])
rescue e
  raised = true
check("error.domain_arity", raised)

raised = false
begin
  incomplete = EulerSimulation.compressible(1).resolution([4])
  incomplete.build_solver
rescue e
  raised = true
check("error.domain_required", raised)

raised = false
begin
  no_init = EulerSimulation.compressible(1).resolution([4]).domain([~1.0])
  no_init.build_solver
rescue e
  raised = true
check("error.init_required", raised)

<< "physics_simulation_spec: all checks passed"
