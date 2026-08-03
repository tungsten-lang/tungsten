# ODE solvers and optimization

## `core/solve` (IVPs)

SciPy name: `solve_ivp`. We use **Solve** so BVP/DAE can join later
without `core/ode` becoming a lie.

```
use core/solve
f = -> (t, y)
  # y' = -y
  out = []
  out = out.push(~0.0 - y[0])
  out
traj = Solve.rk4(f, ~0.0, ~1.0, [~1.0], ~0.05)
# also: Solve.euler, Solve.rk45, Solve.ivp(..., method: :rk4)
```

## `core/optimization`

| Platform | Name |
|----------|------|
| SciPy | `scipy.optimize` |
| Julia | Optim.jl / NLsolve |
| MATLAB | `fminsearch` / `fsolve` |
| R | `optim` / `uniroot` |

The supported foundation is deliberately smaller than those packages. It
provides deterministic binary64 methods whose convergence and failure states
are visible. The original bounded scalar layer remains the simplest entry
point:

```w
use optimization

g = -> (x) x * x - ~2.0
root = Optimization.bisection(g, ~0.0, ~2.0)
root.root
root.residual
root.status_code
root.iterations
root.evaluations

objective = -> (x) (x - ~3.0) * (x - ~3.0)
minimum = Optimization.golden_section(objective, ~0.0, ~8.0)
minimum.argmin
minimum.minimum
```

`Optimization.root` delegates to bisection; `Optimization.minimize` and
`Optimization.minimize_scalar` delegate to golden-section search. Both accept
an optional `OptimizationCriteria`:

```w
criteria = OptimizationCriteria.new(
  ~1.0e-12, # absolute x tolerance
  ~1.0e-12, # relative x tolerance
  ~0.0,     # root residual tolerance; zero means exact zeros only
  100       # maximum bracket updates
)
```

The x stopping test is
`half_interval_width <= abs_tol + rel_tol * abs(estimate)`. Bisection may also
stop at an exact zero or at the optional residual tolerance. A residual
tolerance is scale-dependent, so it is disabled by default. Golden-section
search stops only from its shrinking x interval.

Invalid finite bounds or criteria raise immediately. Numerical failures return
an `OptimizationResult` with one of `:invalid_bracket`,
`:non_finite_value`, `:iteration_limit`, or `:precision_limit`; successful
results use `:converged`. Callback exceptions are not swallowed. Every result
exposes the last interval, estimate, value, iteration/evaluation counts,
status, and method. `certified?` is always false.

These methods coerce bounds and callback values to finite IEEE-754 binary64.
Bisection assumes continuity and an endpoint sign change. Golden-section
search assumes a finite unimodal objective on the closed interval. A
`:converged` result records satisfaction of the requested numerical stopping
condition; it does not prove continuity, unimodality, root existence, global
optimality, or a rounding-error bound.

### Why the support types are optimization-prefixed

`OptimizationCriteria`, `OptimizationStatus`, and `OptimizationResult` retain
their domain prefix intentionally. An audit of the existing scientific core did
not find a stable cross-domain result contract to extract:

- quadrature reports an error estimate and subdivision count, and limits
  recursive depth rather than optimization iterations;
- ODE solvers produce trajectories and have step-size, acceptance, and
  underflow concerns;
- statistical fitting needs parameter vectors and diagnostics such as loss or
  covariance, rather than a scalar bracket and estimate.

The apparent common surface -- absolute/relative tolerances, a convergence
flag, and a message -- is too small to define useful shared semantics. Even
within this module, `residual_tol` applies only to root finding, while
golden-section search stops from x-width alone. The result aliases (`root`,
`residual`, `argmin`, and `minimum`) and failure codes such as
`:invalid_bracket` are likewise specific to this scalar optimization layer.

Core types are globally autoloaded, so bare names such as `Criteria`, `Status`,
or `Result` would also create an unnecessarily collision-prone public API.
A neutral shared namespace can be reconsidered after at least two numerical
domains have concrete, matching lifecycle and diagnostic requirements; until
then the prefix makes the supported scope explicit without constraining those
future APIs.

Binary64 rounding can also make distinct nearby arguments produce identical
objective values (for example, when a tiny quadratic perturbation is added to
a much larger constant). Golden-section search treats those values as a flat
region; it cannot reconstruct information discarded by the callback's
arithmetic. `:precision_limit` specifically reports cases where no usable
interior search point remains representable before the requested x tolerance.

### Derivatives

Central finite differences are available independently of a solver:

```w
d = Optimization.finite_difference_derivative(f, x)
g = Optimization.finite_difference_gradient(objective, parameters)
j = Optimization.finite_difference_jacobian(residual, parameters)
```

The default relative step is `sqrt(binary64 epsilon)` scaled by
`max(1, abs(parameter))`. A positive explicit relative step may be supplied as
the final argument. These routines require finite points and finite callback
values; callback exceptions propagate. They do not estimate truncation error,
adapt the stencil near a domain boundary, or recover information already lost
to rounding.

Existing `Calculus` automatic differentiation is exposed through explicit
adapters:

```w
jacobian = Optimization.autodiff_jacobian_adapter(residual)
gradient = Optimization.autodiff_gradient_adapter(objective)
```

The adapter is sound only when the callback uses operations implemented by
`Differential`. Unsupported operations remain errors; Optimization never
silently substitutes finite differences for a requested autodiff callback.

### Brent, Newton, and secant roots

```w
brent = Optimization.brent(f, lower, upper, criteria)
newton = Optimization.newton(f, derivative, initial, criteria)
safe_newton = Optimization.newton(
  f, derivative, initial, criteria, [lower, upper])
secant = Optimization.secant(f, first, second, criteria)
safe_secant = Optimization.secant(
  f, first, second, criteria, [lower, upper])
```

`brentq` is an alias for `brent`. Brent-Dekker maintains an endpoint sign
bracket and discards unsafe inverse-quadratic/secant proposals in favor of
bisection. Newton accepts `nil` as its derivative to request central finite
differences. Optional Newton and secant brackets must contain an endpoint sign
change; an out-of-bracket step, zero derivative, or zero secant slope then
falls back to the midpoint. Without a bracket, zero slopes return
`:zero_derivative` or `:zero_secant_slope`.

All three return `OptimizationResult`. Function evaluations are counted in
`evaluations`; Newton derivative-callback calls are not included. Callback
exceptions propagate, matching the original scalar API. Other failures use
the existing `:invalid_bracket`, `:non_finite_value`, `:precision_limit`, and
`:iteration_limit` status codes.

### Small dense nonlinear least squares

Residual callbacks accept an `n`-parameter Array and return a nonempty
`m`-residual Array. This layer currently requires `m >= n`. An explicit
Jacobian callback returns an `m`-by-`n` nested row-major Array:

```w
residual = -> (x)
  [x[0] + ~2.0*x[1] - ~5.0,
   ~2.0*x[0] - x[1],
   x[0] - x[1] + ~1.0]
jacobian = -> (x)
  [[~1.0, ~2.0], [~2.0, ~-1.0], [~1.0, ~-1.0]]

gn = Optimization.gauss_newton(
  residual, [~0.0, ~0.0], jacobian)
lm = Optimization.levenberg_marquardt(
  residual, [~0.0, ~0.0]) # central-difference Jacobian
also_lm = Optimization.least_squares(
  residual, [~0.0, ~0.0], jacobian)
```

`least_squares` defaults to Levenberg-Marquardt and also accepts
`:gauss_newton` as its final method argument. Its criteria are separate from
scalar root criteria:

```w
criteria = OptimizationLeastSquaresCriteria.new(
  ~1.0e-10, # residual 2-norm tolerance
  ~1.0e-10, # infinity norm of J' residual
  ~1.0e-10, # relative parameter-step tolerance
  100,      # attempted iterations
  ~1.0e-12, # relative pivot/rank tolerance
  ~1.0e12,  # maximum reported condition estimate
  ~1.0e-3   # initial LM damping
)
```

`OptimizationLeastSquaresResult` exposes `parameters`, `residuals`,
`residual_norm`, `objective` (`0.5 * ||r||^2`), `gradient_norm`, `step_norm`,
`iterations`, separate residual/Jacobian evaluation counts, linear solves,
accepted/rejected steps, numerical rank, condition estimate, final damping,
and `convergence_reason`. Callback exceptions are captured as
`:callback_error`; malformed residual/Jacobian shapes use `:invalid_residual`
or `:invalid_jacobian`; non-finite values remain distinct. `:underdetermined`,
`:rank_deficient`, `:ill_conditioned`, `:singular_system`, `:damping_limit`,
and `:iteration_limit` are non-converged results.

Gauss-Newton solves the linearized least-squares problem with modified
Gram-Schmidt QR and column pivoting rather than forming `J'J`. It takes the
full step and has no globalization, so it is intended for locally good initial
guesses. LM solves a diagonally scaled damped augmented least-squares system,
accepts only objective-decreasing steps, and adjusts damping from the ratio of
actual to predicted reduction.

The reported condition estimate is the largest-to-smallest accepted
`abs(diag(R))` ratio after pivoting. It is useful as a small dense diagnostic
but is not an SVD-based 2-norm condition number. The current `SparseMatrix`
surface does not expose rectangular rank-revealing factorization diagnostics,
so sparse Jacobians are deliberately not accepted yet.

### BFGS, L-BFGS, and box bounds

```w
result = Optimization.bfgs(objective, initial, gradient)
limited = Optimization.lbfgs(objective, initial) # finite-difference gradient

bounds = OptimizationBounds.new(
  [~0.0, nil], # nil means unbounded
  [~1.0, nil])
boxed = Optimization.lbfgs(
  objective, initial, gradient, criteria, bounds)
```

`OptimizationMultivariateCriteria` configures gradient, step, and objective
change tolerances, the iteration and line-search limits, the curvature-update
tolerance, and L-BFGS history size. Both methods use an Armijo backtracking
line search. BFGS maintains a dense inverse-Hessian approximation; L-BFGS uses
the standard two-loop recursion and a bounded correction history. Curvature
pairs that fail the positive-curvature threshold are skipped and counted.

Bounds project trial points and suppress outward directions and gradient
components at active faces. This is a useful small dense box-constrained
method, but it is not the generalized Cauchy-point/subspace algorithm known as
L-BFGS-B. Results report raw and projected gradient norms, line-search and
callback counts, skipped updates, active bounds, and convergence reason.
Callback, non-finite, invalid-gradient, line-search, and iteration failures are
explicit statuses.

### Carefully scoped equality and inequality constraints

```w
constraints = OptimizationConstraints.new(
  [-> (x) x[0] + x[1] - ~1.0], # equality c(x) = 0
  [-> (x) ~0.0 - x[0]])        # inequality g(x) <= 0

result = Optimization.minimize_constrained(
  objective, initial, constraints, criteria, bounds, :bfgs)
```

The implementation is an outer quadratic-penalty loop around BFGS or L-BFGS.
It increases the penalty until the maximum absolute equality violation and
positive inequality violation meet `feasibility_tol`, or until
`max_outer_iterations` is reached. The result exposes `constraint_violation`,
`outer_iterations`, and the final penalty.

This wrapper does not maintain feasible iterates, compute Lagrange
multipliers, test KKT conditions, provide SQP/interior-point convergence
guarantees, or distinguish incompatible constraints beyond a final
`:constraint_violation`. Constraint scaling materially affects the result.
Those omissions are part of the public numerical boundary, not hidden future
behavior.

### Scope boundary

These methods are for small deterministic scientific problems. Global
evolutionary/stochastic heuristics and ML training-loop optimizers remain out
of Core Optimization and belong in Koala or a domain package. No method here
claims global optimality or state-of-the-art large-scale performance. All
results are binary64 numerical evidence and return `certified? == false`.

`core/optim` remains a legacy compatibility surface for the earlier v0 API.
Its bare-value `Optim.root_bisection` now delegates to the supported
bisection implementation and raises when the result is not converged;
`Optim.root_bisection_result` provides the result object for migration. Its
experimental vector routines retain their old return shapes and are not part
of this foundation. `Optim.least_squares_result` is the explicit-result
migration path to Levenberg-Marquardt; the historical `Optim.least_squares`
hash return remains unchanged.

Closed-form polynomial sums (`compiler/lib/lowering/poly_sum.w`) are
**compile-time** folds of `Σ p(x)` — orthogonal to numerical search.
