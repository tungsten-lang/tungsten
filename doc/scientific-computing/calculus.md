# Calculus

`use calculus` loads the smooth numeric calculus layer. It complements exact
polynomial methods in `use algebra`: `Polynomial#derivative`,
`#antiderivative`, and `#definite_integral` stay exact over the coefficient
field, while `Calculus` propagates floating Taylor and differential data
through arbitrary user functions.

It also exposes `Calculus.symbol` and `Calculus.symbols` for canonical
expressions with exact symbolic derivatives and elementary antiderivatives;
`Calculus.antiderivative` and `Calculus.symbolic_integrate` keep exact
constants symbolic and fail loudly for unsupported patterns. See
[../symbolic.md](../symbolic.md).

## Exact formal series

`FormalPowerSeries` complements the floating `TaylorJet`. It stores exact
`Expression` coefficients for powers of `(x - center)` and supports symbolic
parameters, π/e, radicals, arithmetic, composition, and elementary
transcendentals:

```w
x, y = Calculus.symbols([:x, :y])

exact = (x*y).exp.series(:x, 0, 5)
exact.coefficients
exact.derivative
exact.antiderivative
exact.to_expression

Calculus.series(x.sin, :x, 0, 7)
Calculus.limit(x.sin / x, :x, 0)  # exact 1
```

Formal cancellation handles removable finite-point singularities. Genuine
poles use the separate Laurent surface below, while rational-power branch
points use Puiseux series. Logarithmic terms and general transseries still
raise. A formal truncation is algebraic data, not a convergence or
remainder-error certificate. Differentiation lowers its retained order,
antiderivation raises it, and `truncate` refuses to manufacture unavailable
coefficients.

## Laurent series, poles, and residues

`FormalLaurentSeries` retains a finite lower power and an explicit highest
known power. It supports exact meromorphic arithmetic, differentiation,
principal/regular parts, pole order, and residues:

```w
x = Calculus.symbol(:x)
one = Expression.constant(1)

pole = (x.sin / (x*x)).laurent_series(:x, 0, 5)
pole.minimum_power                 # -1
pole.residue                       # 1
pole.coefficient(1)                # -1/6
pole.principal_part
pole.regular_part

geometric = Calculus.laurent_series(
  one / (x*(one - x)), :x, 0, 5)
# x^-1 + 1 + x + x^2 + ... + x^5 + O(x^6)
```

Products and quotients retain only coefficients justified by both operands'
known windows. Addition detects exact cancellation of leading pole terms.
Integrating a nonzero residue raises because the result needs a logarithm.
Likewise `exp(1/x)` raises as an essential singularity. `sqrt(x)` at zero is
handled by the Puiseux surface below. `search_margin` is an explicit, bounded
amount of extra internal precision for nested expressions.

## Puiseux series and ramified branches

`FormalPuiseuxSeries` uses an integer index `k` and a positive ramification
index `e` to represent the power `(x-center)^(k/e)`. Coefficients are exact
`Expression` objects. Arithmetic between different denominators refines both
series to their least common ramification index:

```w
x = Calculus.symbol(:x)

root = x.sqrt.puiseux_series(:x, 0, 4)
root.ramification_index                         # 2
root.valuation                                  # 1/2
root.coefficient(Rational.new(1, 2))            # 1

branched = (x*(Expression.constant(1) + x)).sqrt
branched.puiseux_series(:x, 0, 3)
# x^(1/2) + 1/2*x^(3/2) - 1/8*x^(5/2) + O(x^(7/2))

x.sqrt.exp.puiseux_series(:x, 0, 3)
(x.sqrt + x.cbrt).puiseux_series(:x, 0, 3)
# the mixed result has ramification index 6
```

The implementation supports exact rational powers, arithmetic, quotient
valuation, differentiation, shifted centers, and analytic unary composition
in the local parameter. It represents one formal branch: it does not choose
or certify an analytic branch cut. `log(sqrt(x))` still raises because its
answer contains `log(x)`; essential singularities remain separate. The
calculus layer does not itself solve implicit equations. With `use algebra`,
a rational plane polynomial has `newton_polygon` and `puiseux_sheets`
(`puiseux_branches` is the conventional alias);
the current exact lift handles squarefree characteristic polynomials.
Irreducible higher-degree factors become conjugate sheet packets over
certified simple-extension fields. Repeated rational linear factors trigger
recursive translated Newton polygons; repeated higher-degree algebraic
factors and nonreduced component extraction still raise.

Ramified results are sheets of the selected projection until algebraic
root-of-unity reparameterization orbits are grouped. In particular, the two
formal sheets `+x^(3/2)` and `-x^(3/2)` of a cusp describe one normalized
geometric branch. Do not infer a geometric branch count from the array size.

## Arbitrary-order derivatives and Taylor series

`TaylorJet` stores normalized Taylor coefficients
`a[k] = f^(k)(x₀) / k!`. Products use convolution; division and elementary
transcendentals use formal series recurrences.

```w
use calculus

f = -> (x) x.exp * x.sin

Calculus.derivative(f, ~0.0)     # 1
Calculus.derivative(f, ~0.0, 3)  # 2

jet = Calculus.taylor(f, ~0.0, 7)
jet.coefficients
jet.derivatives
```

Inside a differentiated closure, call elementary functions on the active
value (`x.exp`, `x.log`, `x.sin`, `x.cos`, `x.tan`, `x.sinh`, `x.cosh`,
`x.tanh`, `x.asin`, `x.acos`, `x.atan`, `x.asinh`, `x.acosh`, `x.atanh`,
`x.expm1`, `x.log1p`, `x.log2`, `x.log10`, `x.cbrt`, `x.sqrt`). `Math.sin(x)`
and the other `Math` primitives are the raw scalar surface and intentionally
accept real scalars rather than active calculus objects.

The principal real Lambert W branch is active as `x.lambert_w` (or
`x.lambertw`) for both arbitrary-order `TaylorJet` propagation and
gradient/Hessian `Differential` propagation. At the origin the implementation
uses the analytic limits \(W'(0)=1\) and \(W''(0)=-2\); the branch point
\(-1/e\) is correctly treated as singular for differentiation.

## Black-box numerical derivatives

`Calculus.numerical_derivative` is the explicit fallback for scalar callbacks
that cannot accept `TaylorJet` or `Differential` values, such as foreign or
opaque f64 functions. It does not replace `Calculus.derivative`.

```w
result = Calculus.numerical_derivative(
  -> (x) Math.sin(x),
  ~1.0,
  1,          # derivative order: 1 or 2
  :central,   # :central, :forward, or :backward
  nil,        # initial step; nil uses 0.1 * max(1, abs(x))
  ~1.0e-10,   # absolute tolerance
  ~1.0e-8,    # relative tolerance
  10,         # maximum refinement levels
  ~1.4,       # step contraction factor
  64          # maximum coarse-step retries before a valid row
)

result.value
result.error_estimate
result.step
result.evaluations
result.levels                 # valid Richardson rows
result.attempts               # rows plus bounded coarse-step retries
result.cancellation_indicator
result.resolution_floor
result.status
result.algorithm              # :richardson_extrapolation
result.error_model            # :extrapolation_with_resolution_floor
result.estimate_available?
result.converged?
result.derivative             # alias for value
```

`contraction` must be at least `1.1`; values too close to one make the
Richardson denominators ill-conditioned. Each refinement must also produce a
strictly smaller representable step. `max_levels` bounds valid Richardson
rows. The separate `max_coarse_shrinks` budget (default 64) controls retries
for a nonfinite coordinate, sample, or intermediate before the first valid
row. `attempts` exposes both kinds of work. A budget of two valid rows can
produce an estimate but cannot satisfy the two-row convergence check.

The implementation combines second-order central or one-sided stencils with
Richardson/Ridders extrapolation. Central errors are eliminated in powers
`h^2, h^4, ...`; one-sided errors use `h^2, h^3, ...`. Convergence requires two
successive current refinement rows to satisfy both the requested tolerance and
an inter-row consistency check. The returned converged value is that current
candidate, not an older historical minimum.

Coordinates use explicitly fused multiply-add. A resolution floor combines
the measured defect between actual and intended node offsets with 16 binary64
roundoffs per weighted sample, and propagates through the extrapolation
coefficients. Convergence requires this floor as well as consistency to meet
tolerance. This prevents repeated rounded stencil values from masquerading
as accurate derivatives; very large constant offsets can be resolution limited
even when every sample is identical. On failure, the reported error also
includes disagreement with the latest usable extrapolation row.

Only the previous and current Richardson rows are retained. The center sample
is cached for second derivatives and one-sided schemes: with no retries,
central first/second and one-sided first use respectively `2*levels`,
`1+2*levels`, and `1+2*levels` evaluations; one-sided second uses `1+3*levels`.

Visible statuses include `:converged`, `:max_levels`,
`:roundoff_or_noise_limited`, `:step_unrepresentable`,
`:nonfinite_abscissa`, `:nonfinite_sample`, `:unsupported_sample_type`, and
`:nonfinite_arithmetic`.
Configuration errors raise. Callback exceptions propagate. If no valid
extrapolated estimate exists, `estimate_available?` is false and the value,
error, step, and cancellation indicator are `nil`.

The callback must be a pure deterministic `f64 -> f64` function smooth near
the query point. The error is a consistency estimate; it cannot establish
differentiability, detect every scale, or separate truncation, roundoff, and
sample noise. `NumericalDerivativeResult#certified?` is always false.

For opaque vector inputs, `Calculus.numerical_gradient(f, point, scheme,
initial_step, abs_tol, rel_tol, max_levels)` and `numerical_jacobian` use the
same defaults and return `NumericalArrayResult`. Its `value` and
`error_estimate` are a vector or row-major matrix; `component_results` retains
the individual derivative diagnostics. `status` is the first component failure
or `:converged`; the aggregate value is nil if any component has no estimate.
Tolerances apply per component, not to a matrix norm. `evaluations` counts
actual callback calls: Jacobian samples are shared across output components.
Changing output length raises, and all inputs and callback entries must be f64.

```w
g = Calculus.numerical_gradient(-> (v) v[0]*v[1], [~2.0, ~3.0])
j = Calculus.numerical_jacobian(
  -> (v) [v[0]*v[1], v[0]*v[0]], [~2.0, ~3.0])
g.value  # approximately [3, 2]
j.value  # approximately [[3, 2], [4, 0]]
```

`Optim.fd_grad_result` exposes this result directly. `Optim.fd_grad` retains
its vector return on convergence and raises with the status otherwise.
`Autodiff.grad_fd` similarly checks convergence instead of returning a fixed
step estimate without diagnostics.

## Gradients, Jacobians, and Hessians

`Differential` carries a value, gradient, and Hessian. The exact first- and
second-order chain rules are evaluated once through the closure:

```w
surface = -> (v)
  x = v[0]
  y = v[1]
  x * x * y + (x * y).sin

Calculus.gradient(surface, [~1.0, ~2.0])
Calculus.hessian(surface, [~1.0, ~2.0])
Calculus.value_gradient_hessian(surface, [~1.0, ~2.0])

mapping = -> (v) [v[0] * v[1], v[0].sin + v[1].cos]
Calculus.jacobian(mapping, [~2.0, ~3.0])
```

The same elementary surface is supported by `Differential`, along with
piecewise-smooth `abs` and constant powers. Branches and singular points retain
their ordinary analytic limitations; `abs` at zero and `cbrt` derivatives at
zero fail loudly.

Scalar AD facades reject array/non-scalar outputs and require returned active
values to match the requested dimension or jet order. Real logarithms, inverse
trigonometric/hyperbolic functions and square roots reject invalid domains and
singular derivative points. NaN/infinite input points are rejected.

`Calculus.jvp(f, point, tangent)` and `Calculus.vjp(f, point, cotangent)` delegate
to the existing `Autodiff` module. JVP uses `Dual` tangent seeds and returns
`{"value": primal, "jvp": directional_derivative}`. VJP records operations
using `TapeValue` over `Tape` and returns `{"value": primal, "vjp": input_vector}`.
The callback may return a scalar or Array; cotangent shape must match it.
`Calculus.reverse_gradient(f, point)` is the scalar-output VJP seeded with one.

Both paths support arithmetic, constant powers, `scale`, `sqrt`, `exp`, `log`,
`sin`, `cos`, and `tanh`. Unsupported methods raise. Use methods on active
values (e.g. `v[0].sin`) so operations are traced. Tape values from different
recordings cannot be combined. Reverse propagation visits structural ancestors
of the requested outputs, validates finite values and local derivatives, and
ignores unrelated operations. This is runtime operator-overloading AD;
compiler transformations, checkpointing, mutation analysis, and higher-order
reverse differentiation are not provided. Derivatives describe the executed
smooth program and do not certify differentiability at a branch boundary.

## Adaptive Simpson integration

`Calculus.integrate` uses adaptive Simpson subdivision on a finite real
parameter interval. Integrands may return real or complex values. The result
never hides the stopping condition:

```w
result = Calculus.integrate(
  -> (x) Math.sin(x),
  ~0.0,
  ~3.141592653589793,
  ~1.0e-10,  # absolute tolerance
  ~1.0e-10,  # relative tolerance
  20         # maximum subdivision depth
)

result.value
result.error_estimate
result.evaluations
result.intervals
result.converged?
result.status       # :converged, :max_depth, or a failure status (see below)
result.algorithm    # :adaptive_simpson
result.error_model  # :richardson_difference
```

For example, complex quadrature uses the same call:

```w
i = Complex<f64>.i
wave = Calculus.integrate(
  -> (x) i.scale(x).exp,
  ~0.0,
  ~3.141592653589793)
# wave.value ≈ 0 + 2i
```

`QuadratureResult#certified?` is always false. Its error is the accumulated
Simpson/Richardson estimate, not an interval-arithmetic proof. Improper,
oscillatory-specialized, singular, and multidimensional quadrature remain
future capabilities.

Simpson validates finite bounds/tolerances and samples, and reports
`:nonfinite_integrand`, `:nonfinite_arithmetic`, or `:precision_limit` when
appropriate. An initial failure has no estimate. A later failure may retain
a complete earlier estimate with the failure status; inspect `converged?`.
`:tolerance_not_met` indicates that the final accumulated error missed the
global tolerance after the initial relative-tolerance allocation. Public result
constructors reject contradictory availability, coverage, and convergence.

## Adaptive Gauss-Kronrod integration

`Calculus.integrate_gk15` is a separate finite-real f64 path. Each panel uses
an embedded 7-point Gauss / 15-point Kronrod pair, QUADPACK-style `resasc`
rescaling, and a binary64 roundoff floor. The global controller repeatedly
bisects the panel with the largest estimated error using a stable max-heap.
Compensated incremental totals are rebuilt as the partition doubles, before
accepting convergence, and before returning. Equal errors retain the old
active-array ordering. Rule constants are allocated once per integration.

```w
result = Calculus.integrate_gk15(
  -> (x) Math.exp(~0.0 - x*x),
  ~0.0,
  ~1.0,
  ~1.0e-10,  # absolute tolerance
  ~1.0e-10,  # relative tolerance
  1024,      # maximum active intervals
  30_705     # maximum callback evaluations
)

result.value
result.companion_value
result.error_estimate
result.absolute_integral_estimate
result.worst_interval
result.worst_error
result.evaluations
result.intervals
result.status
result.estimate_available?
result.complete_coverage?
```

The algorithm is reported as `:adaptive_gk15` with error model
`:embedded_gauss_kronrod`. Statuses include `:converged`, `:max_intervals`,
`:max_evaluations`, `:roundoff_limited`, `:precision_limit`,
`:nonfinite_integrand`, `:unsupported_sample_type`, and `:nonfinite_arithmetic`. A successful initial panel
uses 15 evaluations; each accepted bisection adds 30, so a normal run satisfies
`evaluations == 15 + 30 * (intervals - 1)`.

An initial sampling or precision failure returns no estimate: the value and
error are `nil`, `estimate_available?` is false, and `complete_coverage?` is
false. If a later child panel fails, the result retains the last complete
active-partition estimate but remains nonconverged with the failure status.
This makes the number inspectable without presenting it as a successful
answer.

Gauss-Kronrod agreement is still heuristic and can miss narrow or adversarial
features. The method does not accept complex-valued integrands; use the
existing Simpson path for those. Callbacks must be pure and deterministic;
sampling stops immediately on a failed sample or child panel. Panels whose
smallest mapped weight would be subnormal stop with
`:precision_limit`; so do nonzero mapped sample/deviation contributions that
would be subnormal. This avoids trusting quantized embedded-rule agreement.
Improper, singularity-specialized, oscillatory-specialized, and
multidimensional rules remain separate future work. `certified?` is always
false.

`Calculus.integrate_with_points(f, lower, upper, points, abs_tol, rel_tol,
max_intervals, max_evaluations)` initializes the same global GK15 controller
at caller-declared breakpoints. Points must be finite, strictly ascending,
unique, and interior, including when bounds are reversed. Both budgets include
the initial partition and must cover it. There is one global error target;
independently relaxed relative tolerances are not assigned to separate pieces.
The open-node rule does not evaluate the breakpoint itself. With `p` initial
pieces and no failed panel, `evaluations == 15*p + 30*(intervals-p)`.

```w
piecewise = -> (x) x < ~0.2 ? ~-2.0 : ~3.0
q = Calculus.integrate_with_points(piecewise, ~0.0, ~1.0, [~0.2])
q.value  # 2
```

## Radial Mellin/Fourier identities

`RadialMellinTransform` models the analytic transform identities used in
high-dimensional radial Fourier arguments. It is a continuous-transform
surface, separate from the discrete `FFT`:

```w
use calculus

m = RadialMellinTransform.critical_multiplier(8, ~2.0)
m.abs                                      # approximately 1

# Stable even when the Gaussian value itself is too large for f64:
RadialMellinTransform.gaussian_critical_log_value(1024, ~2.0)

x = RadialMellinTransform.gaussian_critical_line(8, ~2.0)
residual = RadialMellinTransform.gaussian_reflection_residual(8, ~2.0)
# x(t) = m(t) x(-t) for the self-Fourier Gaussian

RadialMellinTransform.hankel_multiplier(
  3, Special.complex(~1.5, ~-0.75))
```

With the Fourier convention
`F(f)(xi) = integral f(x) exp(-2*pi*i*x.xi) dx`, the implemented multiplier is

```text
h_d(z) = pi^(d/2-z) Gamma(z/2) / Gamma((d-z)/2).
```

On `z=d/2-it` it is a unit-modulus phase and reflection in Mellin frequency.
Equivalently, after `v=log(r)`, this is ordinary one-dimensional Fourier
frequency in log radius. `CohnElkiesAsymptotics` supplies the associated
limiting density root, sign-uncertainty leading scale, limiting Mellin-
frequency density, and ideal-shell/remote-interval damping formulas. More
precisely, the logistic density is in Mellin frequency; `v=log(r)` is its
Fourier-dual coordinate. Shell parameter `a` is a log-dilation parameter in
`r -> r*exp(+-a/lambda)`, not a Euclidean radius:

```w
CohnElkiesAsymptotics.density_root_limit
CohnElkiesAsymptotics.density_root_limit_exact
CohnElkiesAsymptotics.sign_uncertainty_leading_scale(100)
CohnElkiesAsymptotics.limiting_mellin_frequency_density(~0.0)
CohnElkiesAsymptotics.ideal_shell_displacement_exact
CohnElkiesAsymptotics.interval_shell_damping(~20.0, ~1.5)
```

Trust boundary:

- the log-Gamma complex evaluations and reflection residuals are **numeric**;
- the expression objects are **exact symbolic expressions** for the imported
  closed forms;
- the density-root, sign-uncertainty, and ideal-shell conclusions are
  **trusted theorem imports** from the manuscript, not derivations in
  Tungsten;
- a small residual is only a floating diagnostic, not a certificate for a
  Fourier transform, a finite-dimensional packing optimum, or a zeta-zero
  statement.

## Certified transcendental enclosures

For proof-oriented real evaluation at rational arguments, `Calculus` has a
separate exact enclosure surface:

```w
tolerance = Rational.new(1, 10**30)

pi_value = Calculus.certified_pi(tolerance)
pi_value.lower_bound
pi_value.upper_bound
pi_value.width <= tolerance                 # true
pi_value.certificate.verified?              # true

Calculus.certified_e(tolerance)
Calculus.certified_exp(Rational.new(3, 2), tolerance)
Calculus.certified_log(2, tolerance)
Calculus.certified_sin(Rational.new(1, 3), tolerance)
Calculus.certified_cos(Rational.new(1, 3), tolerance)
Calculus.certified_atan(1, tolerance)
```

These are `CertifiedTranscendentalValue` objects with
`CertifiedRealInterval` endpoints in \(\mathbb Q\). They do not pad a
binary64 result. Exponential uses positive Taylor terms plus a geometric
tail bound; logarithm uses exact powers-of-two reduction and the atanh
series; sine and cosine use the alternating Taylor remainder; arctangent
uses small-argument transformations; and \(\pi\) uses Machin's identity.
The certificate replays every rational operation and width. The analytic
series and remainder theorems are explicit trusted theorem imports, not
kernel-formalized proofs.

The optional term limit fails with `unknown`-style capability errors rather
than returning a wider unlabelled approximation. This surface is deliberately
distinct from the current binary64 `Interval`, whose endpoints do not yet
have full IEEE-1788 outward rounding.

## Transcendental accuracy

The derived `Math` layer now uses cancellation-safe local series for `expm1`
and `log1p`, sign-stable saturation for `tanh`, scaled `hypot`, stable inverse
hyperbolic formulas, a binary64-accurate range-reduced `atan`, and exact
inverse-trig endpoint handling. These are still binary64 numerical functions,
not symbolic transcendental expressions.

`Special` supplies the denser real transcendental catalogue. In addition to
`erf`/`erfc`, gamma/polygamma, beta, and Bessel \(J_0,J_1\), it now provides:

```w
Special.gammainc(a, x)       # regularized lower P(a,x)
Special.gammaincc(a, x)      # cancellation-safe upper Q(a,x)
Special.betainc(a, b, x)     # regularized incomplete beta
Special.zeta(s)              # integer or real s > 1
Special.hurwitz_zeta(s, a)   # real s > 1, a > 0
Special.lambert_w(x)         # principal real W, x >= -1/e

z = Complex<f64>.new([~0.4, ~-0.3])
Special.complex_log_gamma(z)       # principal complex log-Gamma
Special.complex_gamma(z)
Special.complex_erf(z)             # power-series branch, |z| <= 4
Special.complex_lambert_w(z, -2)   # explicit integer branch
```

Incomplete gamma switches between its convergent lower series and a Lentz
continued fraction for the small upper tail; incomplete beta likewise selects
the stable side of its continued fraction. Hurwitz zeta uses an
Euler--Maclaurin tail. Differential fixtures cover central values and small
tails against SciPy 1.17.1. Principal complex Gamma/log-Gamma use Lanczos plus
reflection, complex erf uses its entire power series on the documented disk,
and complex Lambert W exposes every integer branch and checks the final
defining-equation residual. Their differential fixtures come from SageMath
10.9.

These `Special` methods are high-accuracy binary64 algorithms, not interval
certificates; use the `Calculus.certified_*` subset above when an exact
rational enclosure is required. Complex zeta/polylogarithms, asymptotic
complex erf outside the current disk, and certified complex balls remain
future layers.

Current operator dispatch is receiver-directed: write `x * ~2.0` inside an
active closure. Reverse scalar operations such as `~2.0 * x` need a future
general reverse-operator protocol.
