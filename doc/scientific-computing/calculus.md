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
a rational plane polynomial has `newton_polygon` and `puiseux_branches`;
the current exact lift handles edges whose characteristic polynomials split
into distinct nonzero rational roots and raises on unresolved algebraic or
repeated roots.

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

## Adaptive integration

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
