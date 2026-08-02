# Radial Mellin/Fourier identities used in high-dimensional sphere-packing
# asymptotics.  The transform convention is
#
#   Fourier(f)(xi) = integral f(x) exp(-2*pi*i*x.xi) dx.
#
# These methods evaluate exact analytic formulas numerically; they do not
# approximate a continuous Fourier transform with the discrete FFT.

use core/expression
use core/special

+ RadialMellinTransform
  -> .validate_dimension(dimension)
    name = dimension.class_name
    integer = name == "Integer" || name == "Int" || name == "BigInt"
    if !integer || dimension < 1
      raise "radial Mellin dimension must be a positive integer"
    dimension

  -> .lambda(dimension)
    RadialMellinTransform.validate_dimension(dimension)
    (dimension + ~0.0) / ~2.0

  -> .complex(value)
    return value if value.respond_to?("imag")
    Special.complex(value + ~0.0)

  # Mellin multiplier relating a radial function and its Fourier transform:
  # M(Fourier(f))(z) = h_d(z) M(f)(d-z).
  -> .hankel_multiplier(dimension, z)
    RadialMellinTransform.validate_dimension(dimension)
    argument = RadialMellinTransform.complex(z)
    d = Special.complex(dimension + ~0.0)
    half = ~0.5
    pi = ~3.14159265358979323846
    log_multiplier = (
      (d.scale(half) - argument).scale(Math.log(pi)) +
      Special.complex_log_gamma(argument.scale(half)) -
      Special.complex_log_gamma((d - argument).scale(half)))
    log_multiplier.exp

  # Critical-line phase m_lambda(t).  It has unit modulus and reflects
  # Mellin frequency t to -t.
  -> .critical_multiplier(dimension, frequency)
    lambda = RadialMellinTransform.lambda(dimension)
    t = frequency + ~0.0
    numerator_argument = Special.complex(lambda / ~2.0, ~-0.5 * t)
    denominator_argument = numerator_argument.conjugate
    log_multiplier = (
      Special.complex(
        ~0.0, t * Math.log(~3.14159265358979323846)) +
      Special.complex_log_gamma(numerator_argument) -
      Special.complex_log_gamma(denominator_argument))
    log_multiplier.exp

  # Principal logarithm of the Gaussian Mellin value. This remains useful in
  # dimensions where exponentiating the true magnitude would overflow f64.
  -> .gaussian_critical_log_value(dimension, frequency)
    lambda = RadialMellinTransform.lambda(dimension)
    z = Special.complex(lambda, ~0.0 - (frequency + ~0.0))
    (Special.complex(Math.log(~0.5)) +
      z.scale(~-0.5 * Math.log(~3.14159265358979323846)) +
      Special.complex_log_gamma(z.scale(~0.5)))

  # Mellin transform on z=d/2-it of exp(-pi*r^2):
  #   1/2 pi^(-z/2) Gamma(z/2).
  -> .gaussian_critical_line(dimension, frequency)
    RadialMellinTransform.gaussian_critical_log_value(
      dimension, frequency).exp

  # A self-Fourier Gaussian obeys X(t)=m_lambda(t)X(-t).  The returned
  # residual should be near zero; it is a floating diagnostic, not a proof.
  -> .gaussian_reflection_residual(dimension, frequency)
    left = RadialMellinTransform.gaussian_critical_line(
      dimension, frequency)
    right = (
      RadialMellinTransform.critical_multiplier(
        dimension, frequency) *
      RadialMellinTransform.gaussian_critical_line(
        dimension, ~0.0 - (frequency + ~0.0)))
    left - right


+ CohnElkiesAsymptotics
  # lim LP_d^(1/d) in the normalization used by the linear-programming
  # sphere-packing bound.
  -> .density_root_limit
    Math.sqrt(~2.71828182845904523536 /
              (~2.0 * ~3.14159265358979323846))

  -> .density_root_limit_exact
    (Expression.e /
      (Expression.constant(2) * Expression.pi)).sqrt

  -> .sign_uncertainty_leading_scale(dimension)
    RadialMellinTransform.validate_dimension(dimension)
    Math.sqrt(dimension + ~0.0) / ~3.14159265358979323846

  # Limiting density in Mellin frequency. Log radius is the Fourier-dual
  # coordinate, not this density's argument.
  -> .limiting_mellin_frequency_density(value)
    x = ~1.57079632679489661923 * (value + ~0.0)
    ~0.78539816339744830962 / (Math.cosh(x) ** 2)

  # Formal ideal shell weight.  It is singular at zero; the displacement
  # density below is the regular quantity used by the asymptotic argument.
  -> .ideal_shell_weight(log_dilation)
    a = log_dilation + ~0.0
    raise "ideal shell weight needs positive log dilation" if a <= ~0.0
    ~-0.5 * Math.exp(~-2.0 * a) / (a * a * Math.cosh(a))

  -> .ideal_shell_displacement_density(log_dilation)
    a = log_dilation + ~0.0
    if a < ~0.0
      raise "shell displacement log dilation must be nonnegative"
    return ~-0.5 if a == ~0.0
    ~-0.5 * Math.exp(~-2.0 * a) * Math.tanh(a) / a

  -> .ideal_shell_displacement_exact
    (-Expression.constant(Rational.new(1, 2)) *
      (Expression.pi / Expression.constant(2)).log)

  -> .ideal_shell_displacement
    CohnElkiesAsymptotics.ideal_shell_displacement_exact.evaluate({})

  -> .sinc(value)
    x = value + ~0.0
    magnitude = Math.abs(x)
    if magnitude < ~1.0e-5
      square = x * x
      return ~1.0 - square / ~6.0 + square * square / ~120.0
    Math.sin(x) / x

  -> .one_minus_sinc(value)
    x = value + ~0.0
    if Math.abs(x) < ~1.0e-3
      square = x * x
      return (square / ~6.0 - square * square / ~120.0 +
              square * square * square / ~5040.0)
    ~1.0 - Math.sin(x) / x

  # A point shell has exact resonant zeros, which is why it cannot provide
  # uniform damping of every nonzero frequency.
  -> .point_shell_damping(log_dilation, frequency)
    phase = (log_dilation + ~0.0) * (frequency + ~0.0)
    sine = Math.sin(phase / ~2.0)
    ~2.0 * sine * sine

  # Averaging a remote shell over [B,B+1] removes those point resonances:
  # 1-sinc(T/2)cos((B+1/2)T), strictly positive for T != 0.
  -> .interval_shell_damping(start, frequency)
    b = start + ~0.0
    t = frequency + ~0.0
    phase = (b + ~0.5) * t
    sine = Math.sin(phase / ~2.0)
    (~2.0 * sine * sine + Math.cos(phase) *
      CohnElkiesAsymptotics.one_minus_sinc(t / ~2.0))
