# Radial Mellin/Fourier and Cohn--Elkies asymptotic regressions.
# Run in both engines:
#   bin/tungsten run spec/core/calculus_radial_mellin_spec.w
#   bin/tungsten compile spec/core/calculus_radial_mellin_spec.w \
#     --out /tmp/calculus-radial-mellin-spec

use calculus

-> mellin_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> mellin_close?(left, right, tolerance = ~1.0e-11)
  difference = Math.abs(left - right)
  scale = Math.abs(right)
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance * scale

dimensions = [1, 3, 8, 32]
frequencies = [~0.0, ~0.25, ~2.0, ~9.0]
dimensions.each -> (dimension)
  frequencies.each -> (frequency)
    multiplier = RadialMellinTransform.critical_multiplier(
      dimension, frequency)
    mellin_check("multiplier.unit.[dimension].[frequency]",
                 mellin_close?(multiplier.abs, ~1.0, ~4.0e-12))
    residual = RadialMellinTransform.gaussian_reflection_residual(
      dimension, frequency)
    scale = RadialMellinTransform.gaussian_critical_line(
      dimension, frequency).abs
    scale = ~1.0 if scale < ~1.0
    mellin_check("gaussian.reflection.[dimension].[frequency]",
                 residual.abs <= ~2.0e-11 * scale)

# The log-Gamma implementation must retain the unit phase where separate
# Gamma evaluation overflows or underflows.
[512, 1024, 16384].each -> (dimension)
  multiplier = RadialMellinTransform.critical_multiplier(dimension, ~2.0)
  mellin_check("multiplier.high_dimension.[dimension]",
               mellin_close?(multiplier.abs, ~1.0, ~2.0e-10))
high_gaussian_log = RadialMellinTransform.gaussian_critical_log_value(
  1024, ~2.0)
mellin_check("gaussian.log_value.high_dimension",
             high_gaussian_log.real == high_gaussian_log.real &&
               high_gaussian_log.imag == high_gaussian_log.imag)

z = Special.complex(~1.5, ~-0.75)
direct = RadialMellinTransform.hankel_multiplier(3, z)
critical = RadialMellinTransform.critical_multiplier(3, ~0.75)
mellin_check("hankel.critical.specialization",
             (direct - critical).abs < ~2.0e-12)

expected_root = Math.sqrt(~2.71828182845904523536 /
                          (~2.0 * ~3.14159265358979323846))
mellin_check("cohn_elKies.root_limit",
             mellin_close?(CohnElkiesAsymptotics.density_root_limit,
                           expected_root))
mellin_check("cohn_elKies.symbolic_root",
             mellin_close?(
               CohnElkiesAsymptotics.density_root_limit_exact.evaluate({}),
               expected_root))
mellin_check("cohn_elKies.displacement",
             mellin_close?(
               CohnElkiesAsymptotics.ideal_shell_displacement,
               ~-0.5 * Math.log(~3.14159265358979323846 / ~2.0)))
mellin_check("cohn_elKies.displacement.origin",
             CohnElkiesAsymptotics.ideal_shell_displacement_density(~0.0) ==
               ~-0.5)
mellin_check("cohn_elKies.leading_scale",
             mellin_close?(
               CohnElkiesAsymptotics.sign_uncertainty_leading_scale(100),
               ~10.0 / ~3.14159265358979323846))
mellin_check("cohn_elKies.frequency_density.origin",
             mellin_close?(
               CohnElkiesAsymptotics
                 .limiting_mellin_frequency_density(~0.0),
               ~0.78539816339744830962))

# Point support resonates exactly, while unit-interval averaging stays
# positive at the same nonzero frequency.
frequency = ~2.0
point_radius = ~3.14159265358979323846
mellin_check("shell.point.resonance",
             Math.abs(CohnElkiesAsymptotics.point_shell_damping(
               point_radius, frequency)) < ~1.0e-14)
mellin_check("shell.interval.breaks_resonance",
             CohnElkiesAsymptotics.interval_shell_damping(
               point_radius, frequency) > ~0.0)
mellin_check("shell.interval.zero_frequency",
             CohnElkiesAsymptotics.interval_shell_damping(
               ~7.0, ~0.0) == ~0.0)
mellin_check("shell.point.tiny_frequency",
             CohnElkiesAsymptotics.point_shell_damping(
               ~7.0, ~1.0e-10) > ~0.0)
mellin_check("shell.interval.tiny_frequency",
             CohnElkiesAsymptotics.interval_shell_damping(
               ~7.0, ~1.0e-10) > ~0.0)
mellin_check("shell.interval.remote_tiny_frequency",
             CohnElkiesAsymptotics.interval_shell_damping(
               ~1.0e12, ~1.0e-10) > ~0.0)

<< "calculus_radial_mellin_spec: all checks passed"
