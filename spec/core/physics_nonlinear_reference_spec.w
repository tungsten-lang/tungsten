# Focused nonlinear-PDE reference and diagnostics checks.
# Run in both engines:
#   bin/tungsten run spec/core/physics_nonlinear_reference_spec.w
#   bin/tungsten compile spec/core/physics_nonlinear_reference_spec.w \
#     --out /tmp/physics-nonlinear-reference-spec

use physics

-> nonlinear_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> nonlinear_close?(got, want, tolerance = ~1.0e-12)
  difference = (got - want).abs
  scale = want.abs
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance * scale

# Burgers flux, entropy pair, and smooth-wave breaking time.
nonlinear_check("burgers.flux",
                nonlinear_close?(BurgersEquation.flux(~2.0), ~2.0))
nonlinear_check("burgers.characteristic_speed",
                BurgersEquation.characteristic_speed(~-0.5) == ~-0.5)
nonlinear_check("burgers.entropy",
                nonlinear_close?(BurgersEquation.entropy(~2.0), ~2.0))
nonlinear_check("burgers.entropy_flux",
                nonlinear_close?(BurgersEquation.entropy_flux(~3.0), ~9.0))
nonlinear_check("burgers.sine_shock_time",
                nonlinear_close?(
                  BurgersEquation.sine_shock_time(~2.0, ~0.5), ~1.0))

# Expansive data selects the entropy rarefaction fan.
nonlinear_check("burgers.rarefaction.kind",
                BurgersEquation.riemann_kind(~-1.0, ~1.0) == :rarefaction)
nonlinear_check("burgers.rarefaction.left",
                BurgersEquation.riemann_value(~-1.0, ~1.0, ~-2.0) == ~-1.0)
nonlinear_check("burgers.rarefaction.fan",
                BurgersEquation.riemann_value(~-1.0, ~1.0, ~0.25) == ~0.25)
nonlinear_check("burgers.rarefaction.right",
                BurgersEquation.riemann_value(~-1.0, ~1.0, ~2.0) == ~1.0)
nonlinear_check("burgers.rarefaction.godunov_flux",
                BurgersEquation.godunov_flux(~-1.0, ~1.0) == ~0.0)
nonlinear_check("burgers.positive_rarefaction.godunov_flux",
                BurgersEquation.godunov_flux(~1.0, ~2.0) == ~0.5)
nonlinear_check("burgers.negative_rarefaction.godunov_flux",
                BurgersEquation.godunov_flux(~-2.0, ~-1.0) == ~0.5)

# Compressive data selects a Rankine-Hugoniot shock.
nonlinear_check("burgers.shock.kind",
                BurgersEquation.riemann_kind(~2.0, ~0.0) == :shock)
nonlinear_check("burgers.shock.speed",
                BurgersEquation.shock_speed(~2.0, ~0.0) == ~1.0)
nonlinear_check("burgers.shock.left_trace",
                BurgersEquation.riemann_value(~2.0, ~0.0, ~0.5) == ~2.0)
nonlinear_check("burgers.shock.right_trace",
                BurgersEquation.riemann_value(~2.0, ~0.0, ~1.5) == ~0.0)
nonlinear_check("burgers.shock.position",
                BurgersEquation.riemann_value_at(
                  ~2.0, ~0.0, ~0.25, ~0.5) == ~2.0)
nonlinear_check("burgers.shock.godunov_flux",
                BurgersEquation.godunov_flux(~2.0, ~0.0) == ~2.0)
nonlinear_check("burgers.leftgoing_shock.godunov_flux",
                BurgersEquation.godunov_flux(~0.0, ~-2.0) == ~2.0)

negative_time_rejected = false
begin
  BurgersEquation.riemann_value_at(~1.0, ~0.0, ~0.0, ~-0.1)
rescue error
  negative_time_rejected = error.to_s.include?("cannot be negative")
nonlinear_check("burgers.negative_time_rejected", negative_time_rejected)

nonfinite_time_rejected = false
begin
  not_a_number = ~1.0e999 - ~1.0e999
  BurgersEquation.riemann_value_at(~1.0, ~0.0, ~0.0, not_a_number)
rescue error
  nonfinite_time_rejected = error.to_s.include?("finite number")
nonlinear_check("burgers.nonfinite_time_rejected", nonfinite_time_rejected)

# Solver-independent convergence, TVD, entropy, CFL, and conservation checks.
open_values = [~0.0, ~1.0, ~2.0]
nonlinear_check("diagnostics.total_variation.open",
                FiniteVolumeDiagnostics.total_variation(open_values) == ~2.0)
nonlinear_check("diagnostics.total_variation.periodic",
                FiniteVolumeDiagnostics.total_variation(
                  open_values, true) == ~4.0)
typed_values = f64[3]
typed_values[0] = ~0.0
typed_values[1] = ~1.0
typed_values[2] = ~2.0
nonlinear_check("diagnostics.total_variation.typed_array",
                FiniteVolumeDiagnostics.total_variation(
                  typed_values) == ~2.0)

before = [~0.0, ~1.0, ~0.0]
limited = [~0.25, ~0.75, ~0.25]
oscillatory = [~0.0, ~1.2, ~-0.1]
nonlinear_check("diagnostics.tvd.accepts_limited",
                FiniteVolumeDiagnostics.tvd?(before, limited))
nonlinear_check("diagnostics.tvd.rejects_oscillation",
                !FiniteVolumeDiagnostics.tvd?(before, oscillatory))

values = [~1.0, ~2.0]
reference = [~0.0, ~0.0]
nonlinear_check("diagnostics.l1_error",
                FiniteVolumeDiagnostics.l1_error(
                  values, reference, ~0.5) == ~1.5)
nonlinear_check("diagnostics.l2_error",
                nonlinear_close?(
                  FiniteVolumeDiagnostics.l2_error(values, reference, ~0.5),
                  Math.sqrt(~2.5)))
nonlinear_check("diagnostics.linf_error",
                FiniteVolumeDiagnostics.linf_error(values, reference) == ~2.0)
nonlinear_check("diagnostics.l2_norm",
                nonlinear_close?(
                  FiniteVolumeDiagnostics.l2_norm(values, ~0.5),
                  Math.sqrt(~2.5)))
nonlinear_check("diagnostics.quadratic_entropy",
                FiniteVolumeDiagnostics.quadratic_entropy(
                  values, ~0.5) == ~1.25)
nonlinear_check("diagnostics.entropy_nonincreasing",
                FiniteVolumeDiagnostics.nonincreasing?(~1.25, ~1.2))
nonlinear_check("diagnostics.observed_order",
                nonlinear_close?(
                  FiniteVolumeDiagnostics.observed_order(~0.04, ~0.01),
                  ~2.0))

drift = FiniteVolumeDiagnostics.conservation_drift(
  [~10.0, ~2.0], [~10.1, ~1.8])
nonlinear_check("diagnostics.conservation.mass",
                nonlinear_close?(drift[0], ~0.1))
nonlinear_check("diagnostics.conservation.momentum",
                nonlinear_close?(drift[1], ~-0.2))
relative_drift = FiniteVolumeDiagnostics.relative_conservation_drift(
  [~10.0, ~2.0], [~10.1, ~1.8])
nonlinear_check("diagnostics.conservation.relative_mass",
                nonlinear_close?(relative_drift[0], ~0.01))
nonlinear_check("diagnostics.conservation.relative_momentum",
                nonlinear_close?(relative_drift[1], ~-0.1))

nonlinear_check("diagnostics.cfl.accepts_bound",
                FiniteVolumeDiagnostics.cfl_contract?(~0.8, ~1.0))
nonlinear_check("diagnostics.cfl.rejects_excess",
                !FiniteVolumeDiagnostics.cfl_contract?(~1.01, ~1.0))

mismatch_rejected = false
begin
  FiniteVolumeDiagnostics.l1_error([~1.0], [~1.0, ~2.0])
rescue error
  mismatch_rejected = error.to_s.include?("same size")
nonlinear_check("diagnostics.size_mismatch_rejected", mismatch_rejected)

nonfinite_field_rejected = false
begin
  FiniteVolumeDiagnostics.linf_error([not_a_number], [~0.0])
rescue error
  nonfinite_field_rejected = error.to_s.include?("finite number")
nonlinear_check("diagnostics.nonfinite_field_rejected",
                nonfinite_field_rejected)

infinity = ~1.0e999
infinite_cfl_rejected = false
begin
  FiniteVolumeDiagnostics.cfl_contract?(~0.5, infinity)
rescue error
  infinite_cfl_rejected = error.to_s.include?("finite number")
nonlinear_check("diagnostics.infinite_cfl_rejected", infinite_cfl_rejected)

<< "physics_nonlinear_reference_spec: all checks passed"
