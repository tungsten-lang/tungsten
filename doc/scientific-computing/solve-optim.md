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
provides bounded scalar methods whose convergence and failure states are
visible:

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

`core/optim` remains a legacy compatibility surface for the earlier v0 API.
Its bare-value `Optim.root_bisection` now delegates to the supported
bisection implementation and raises when the result is not converged;
`Optim.root_bisection_result` provides the result object for migration. Its
experimental vector routines retain their old return shapes and are not part
of this foundation.

Closed-form polynomial sums (`compiler/lib/lowering/poly_sum.w`) are
**compile-time** folds of `Σ p(x)` — orthogonal to numerical search.
