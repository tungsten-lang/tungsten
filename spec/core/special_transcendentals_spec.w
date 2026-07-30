# Tail-stable special/transcendental functions.
#
# Numeric fixtures are differential records from SciPy 1.17.1.  Tolerances
# cover binary64 rounding, not algorithmic uncertainty certificates.

use calculus

-> special_abs(value)
  value < ~0.0 ? ~0.0 - value : value

-> special_close(name, got, want,
                  absolute = ~2.0e-14,
                  relative = ~2.0e-14)
  error = special_abs(got - want)
  scale = special_abs(want)
  limit = absolute + relative*scale
  if error > limit
    raise ("FAIL " + name + ": got " + got.to_s +
           ", want " + want.to_s + ", error " + error.to_s)
  << "PASS " + name

-> special_complex_close(name, got, real, imaginary,
                          tolerance = ~3.0e-13)
  special_close(name + ".real", got.real, real,
                tolerance, tolerance)
  special_close(name + ".imag", got.imag, imaginary,
                tolerance, tolerance)

special_close("gammainc.lower_series",
              Special.gammainc(~0.5, ~0.1),
              ~0.34527915398142317)
special_close("gammainc.central",
              Special.gammainc(~100.0, ~100.0),
              ~0.5132987982791487, ~8.0e-14, ~8.0e-14)
special_close("gammaincc.small_tail",
              Special.gammaincc(~2.5, ~20.0),
              ~1.493367900050396e-7, ~1.0e-20, ~3.0e-14)
special_close("gammainc.complement",
              Special.gammainc(~10.0, ~20.0) +
              Special.gammaincc(~10.0, ~20.0),
              ~1.0)

special_close("betainc.arcsine",
              Special.betainc(~0.5, ~0.5, ~0.25),
              ~0.3333333333333333)
special_close("betainc.left_tail",
              Special.betainc(~2.5, ~3.5, ~0.1),
              ~0.02857566804235542)
special_close("betainc.central",
              Special.betainc(~20.0, ~30.0, ~0.4),
              ~0.5077001996576478)
special_close("betainc.right_tail",
              Special.betainc(~100.0, ~2.0, ~0.99),
              ~0.7320646825464587)

special_close("lambertw.negative",
              Special.lambert_w(~-0.3),
              ~-0.4894022271802149)
special_close("lambertw.positive",
              Special.lambertw(~0.5),
              ~0.35173371124919584)
special_close("lambertw.large",
              Special.lambert_w(~1000000.0),
              ~11.383358086140053)
w = Special.lambert_w(~10.0)
special_close("lambertw.defining_identity",
              w*Math.exp(w), ~10.0)
special_close("lambertw.jet.first_at_zero",
              Calculus.derivative(-> (x) x.lambert_w, ~0.0),
              ~1.0)
special_close("lambertw.jet.second_at_zero",
              Calculus.derivative(-> (x) x.lambert_w, ~0.0, 2),
              ~-2.0)
special_close("lambertw.jet.third_at_zero",
              Calculus.derivative(-> (x) x.lambert_w, ~0.0, 3),
              ~9.0)
lambert_diff = Calculus.differential(
  -> (v) v[0].lambert_w, [~0.5])
lambert_value = Special.lambert_w(~0.5)
lambert_first = (
  lambert_value / (~0.5*(~1.0 + lambert_value)))
lambert_second = (
  (~0.0 - lambert_value*lambert_value*(~2.0 + lambert_value)) /
  (~0.25*(~1.0 + lambert_value)**3))
special_close("lambertw.differential.gradient",
              lambert_diff.gradient[0], lambert_first)
special_close("lambertw.differential.hessian",
              lambert_diff.hessian[0][0], lambert_second)

special_close("zeta.real",
              Special.zeta(~2.5),
              ~1.3414872572509176)
special_close("hurwitz_zeta.near_pole",
              Special.hurwitz_zeta(~1.1, ~1.0),
              ~10.584448464950801)
special_close("hurwitz_zeta.shifted",
              Special.hurwitz_zeta(~2.5, ~0.25),
              ~32.84745195469768, ~5.0e-13, ~3.0e-14)
special_close("hurwitz_zeta.small",
              Special.hurwitz_zeta(~5.5, ~10.0),
              ~8.752204611642284e-6, ~1.0e-18, ~3.0e-14)

special_close("logistic.negative_stable",
              Special.logistic(~-1000.0), ~0.0, ~0.0, ~0.0)
special_close("softplus.negative_stable",
              Special.softplus(~-50.0),
              ~1.9287498479639178e-22, ~1.0e-35, ~3.0e-14)

lambert_domain = false
begin
  Special.lambert_w(~-0.4)
rescue error
  lambert_domain = true
if !lambert_domain
  raise "FAIL lambertw.domain"
<< "PASS lambertw.domain"

# Principal complex Gamma/log-Gamma, entire erf, and integer Lambert-W
# branches. Fixtures are differential records from SageMath 10.9.
complex_z = Complex<f64>.new([~0.4, ~-0.3])
special_complex_close(
  "complex.log_gamma",
  Special.complex_log_gamma(complex_z),
  ~0.5279912253710829, ~0.6575604927958080)
special_complex_close(
  "complex.gamma",
  Special.complex_gamma(complex_z),
  ~1.3419819788320783, ~1.0362830129822285)
special_complex_close(
  "complex.erf",
  Special.complex_erf(complex_z),
  ~0.4644372129795614, ~-0.2944398077693171)

complex_w0_argument = Complex<f64>.new([~1.0, ~1.0])
complex_w0 = Special.complex_lambert_w(
  complex_w0_argument)
special_complex_close(
  "complex.lambertw.branch0", complex_w0,
  ~0.6569660692304364, ~0.3254503394134150)
special_complex_close(
  "complex.lambertw.branch0.identity",
  complex_w0*complex_w0.exp,
  ~1.0, ~1.0)

complex_branch_argument = Complex<f64>.new([~2.0, ~-3.0])
complex_w1 = Special.complex_lambertw(
  complex_branch_argument, 1)
special_complex_close(
  "complex.lambertw.branch1", complex_w1,
  ~-0.03158280838987505, ~3.721107986637061)
complex_w_minus_two = Special.complex_lambert_w(
  complex_branch_argument, -2)
special_complex_close(
  "complex.lambertw.branch_minus2", complex_w_minus_two,
  ~-1.1972601078812846, ~-11.877910111617443)
special_complex_close(
  "complex.lambertw.branch_minus2.identity",
  complex_w_minus_two*complex_w_minus_two.exp,
  ~2.0, ~-3.0, ~8.0e-13)

complex_branch_error = false
begin
  Special.complex_lambert_w(complex_z, ~0.5)
rescue error
  complex_branch_error = true
if !complex_branch_error
  raise "FAIL complex.lambertw.branch_type"
<< "PASS complex.lambertw.branch_type"

complex_erf_radius = false
begin
  Special.complex_erf(Complex<f64>.real(~5.0))
rescue error
  complex_erf_radius = true
if !complex_erf_radius
  raise "FAIL complex.erf.radius"
<< "PASS complex.erf.radius"
