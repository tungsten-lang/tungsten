# Symbolic expressions

`Expression` is Tungsten's canonical symbolic real-expression tree. It is
autoloaded directly, and `use calculus` adds the shorter
`Calculus.symbol` / `Calculus.symbols` constructors.

```w
use calculus

x, y = Calculus.symbols([:x, :y])
f = x**3*y + (x*y).sin + x.log1p

f
f.derivative(:x)
f.gradient([:x, :y])
f.hessian([:x, :y])
f.free_variables
```

Construction simplifies immediately. Addition and multiplication are
flattened and sorted, exact constants are combined, like terms and repeated
factors are collected, neutral elements disappear, and safe real identities
such as `log(exp(x)) = x` and `sqrt(x²) = abs(x)` are applied. Variables are
real unless a future assumptions layer says otherwise.

Exact inputs stay exact. Irrational elementary values are represented rather
than prematurely evaluated:

```w
Expression.pi                    # π
Expression.e                     # e
Expression.constant(2).sqrt      # sqrt(2), not a Float
Expression.constant(144).sqrt    # 12
Expression.constant(1).exp       # e
(Expression.pi / 2).sin          # 1
```

Named constants evaluate numerically only when `evaluate` is requested.
Perfect roots are reduced exactly. Square and cube factors are also extracted
from modest-size exact radicals, so `sqrt(8)` canonicalizes to `2*sqrt(2)`;
large non-perfect radicands stay symbolic rather than triggering unbounded
trial factorization.

The elementary surface matches numeric calculus:

```text
exp log sqrt sin cos tan sinh cosh tanh
asin acos atan asinh acosh atanh
expm1 log1p log2 log10 cbrt abs
```

## Substitution and evaluation

`substitute` returns another simplified expression. `evaluate` accepts String
or Symbol keys and returns values in the supplied domain:

```w
g = f.substitute({y: x + 1})
g.evaluate({x: ~0.5})

jet = TaylorJet.variable(~0.5, 5)
f.evaluate({x: jet, y: ~2.0})

z = Complex<f64>.new([~0.5, ~0.25])
f.evaluate({x: z, y: ~2.0})
```

The same evaluation path works with `Differential` and exact `Polynomial`
values. This lets one formula serve symbolic manipulation, arbitrary-order
Taylor differentiation, gradients/Hessians, complex analysis, and exact
polynomial evaluation.

## Exact polynomial bridge

```w
use algebra

ring = PolynomialRing.new([:x, :y], RationalField.new)
p = (x**3 * Rational.new(1, 2) + x*y*3 - y).to_polynomial(ring)
expression = p.to_expression
```

`to_polynomial` rejects transcendental operations, nonconstant denominators,
negative/nonintegral exponents, and variables missing from the target ring.
`Polynomial#to_expression` currently accepts rational-field polynomials.
Finite-field and number-field coefficients need field-aware symbolic constants
before that reverse conversion can preserve their representation, so it fails
loudly today.

## Expand, collect, factor, and solve

Polynomial-shaped expressions can be manipulated without abandoning the
symbolic surface:

```w
(x + 1)**3.expand
# x^3 + 3*x^2 + 3*x + 1

f = (x + y)*(x + 1)
f.degree_in(:x)          # 2
f.coefficient(:x, 1)     # y + 1
f.collect(:x)            # x^2 + (y + 1)*x + y
```

`use algebra` adds the operations backed by `PolynomialRing<ℚ>`:

```w
use algebra

(x**2 - 1).factor(:x)
(x**2 - 1).factor_list(:x)
(x**2 - 2).solve(:x)       # [-sqrt(2), sqrt(2)]
Algebra.solve(x**4 - 1, :x)
(x**3 - x + 1).solve(:x)    # [RootOf(x^3 - x + 1, 0)]
```

`factor` is exact univariate factorization over ℚ. `solve` returns all
distinct exact real roots. Linear roots remain rational and quadratic roots
retain their readable radical form. Higher-degree roots are exact
`AlgebraicRealRoot` constants represented by a defining irreducible polynomial,
an ordered root index, and a rational interval whose unique root is certified
by exact Sturm replay:

```w
root_expression = (x**3 - x + 1).solve(:x)[0]
root = root_expression.constant_value

root.certified?          # true
root.interval            # exact rational endpoints
root.refined(20)         # a narrower independently certified value
root.approximation(30)   # Rational midpoint, not a certificate
root.to_f                # convenient machine approximation
```

Polynomial users can call `sturm_root_count`, `real_root_count`,
`cauchy_root_bound`, `real_root_isolation`, and `real_roots` directly. The
complete `RealRootIsolation` certificate checks the exact distinct-root count,
every rational root or certified algebraic factor, and strict ordering of the
returned list. There is no silent floating-point fallback.

## Elementary symbolic integration

`antiderivative` supports exact polynomial powers, constant multiples, affine
substitution for powers and common elementary functions, logarithmic
reciprocals, and a small set of standard forms:

```w
primitive = (x**3 + 2*x + 3).antiderivative(:x)
primitive.derivative(:x) == x**3 + 2*x + 3

(2*x + 1).sin.antiderivative(:x)
x.sin.definite_integral(:x, 0, Expression.pi)  # 2

Calculus.antiderivative(x.exp, :x)
Calculus.symbolic_integrate(x.sin, :x, 0, Expression.pi)
```

This API is deliberately separate from adaptive numerical quadrature.
Unsupported elementary patterns raise with the expression that could not be
integrated; no numeric approximation is substituted.

## Exact formal series and finite limits

`use calculus` adds `FormalPowerSeries`, whose coefficient of degree `n` is
the exact symbolic coefficient of `(x - center)^n`:

```w
use calculus

s = x.exp.series(:x, 0, 6)
s.coefficients
# [1, 1, 1/2, 1/6, 1/24, 1/120, 1/720]

(x*y).exp.series(:x, 0, 4).coefficients
# [1, y, 1/2*y^2, 1/6*y^3, 1/24*y^4]

(Expression.pi*x).sin.series(:x, 0, 3)
x.log.series(:x, 1, 5)
Calculus.series((x + 1).sqrt, :x, 0, 5)
```

Series support exact arithmetic, division, integer and symbolic constant
powers, composition, derivatives, antiderivatives, and every elementary
function supported by `Expression`. Differentiation lowers retained order by
one and integration raises it by one; `truncate` can discard coefficients but
never invent higher precision. `to_expression` returns the retained
polynomial, and `at` evaluates that truncation exactly.

Common removable singularities are cancelled by formal valuation:

```w
(x.sin / x).series(:x, 0, 6)
(x.sin / x).limit(:x, 0)                 # 1
((Expression.constant(1) - x.cos) / x**2).limit(:x, 0)  # 1/2
Calculus.limit((x + 1).log / x, :x, 0)   # 1
```

The order is a truncation contract, not a convergence or error certificate.
Genuine poles require Laurent series, and branch points such as `sqrt(x)` at
zero require Puiseux series; both currently raise explicitly. Sign-dependent
forms such as `abs(x)` also raise when the center does not determine a smooth
branch.

## Current boundary

This is a canonical simplifier, exact differentiator, elementary integrator,
and rational-polynomial front end, not yet a complete computer algebra system.
It does not currently provide assumptions/refinement, piecewise expressions,
infinite or directional limits, Laurent/Puiseux series, general
transcendental equation solving, complex algebraic root objects, general
multivariate factorization, arithmetic between general `RootOf`
presentations, or Risch-style integration. Polynomial-native Gröbner bases,
ideals, and geometry remain in `use algebra`.

Operator dispatch is still receiver-directed. Write `x*2`, not `2*x`, until
the language has a general reverse-operator protocol.
