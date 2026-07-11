# ODE solvers & optimization

## `core/solve` (IVPs)

SciPy name: `solve_ivp`. We use **Solve** so BVP/DAE can join later
without `core/ode` becoming a lie.

```
use core/sci/solve
f = -> (t, y)
  # y' = -y
  out = []
  out = out.push(~0.0 - y[0])
  out
traj = Solve.rk4(f, ~0.0, ~1.0, [~1.0], ~0.05)
# also: Solve.euler, Solve.rk45, Solve.ivp(..., method: :rk4)
```

## `core/optim`

| Platform | Name |
|----------|------|
| SciPy | `scipy.optimize` |
| Julia | Optim.jl / NLsolve |
| MATLAB | `fminsearch` / `fsolve` |
| R | `optim` / `uniroot` |

Tungsten: **`core/optim`** (sibling of solve).

```
use core/sci/optim
g = -> (x) x * x - ~2.0
<< Optim.root_bisection(g, ~0.0, ~2.0)
# also: root_newton, minimize_gd_fd, minimize_nm, least_squares
```

Closed-form polynomial sums (`compiler/lib/lowering/poly_sum.w`) are
**compile-time** folds of `Σ p(x)` — orthogonal to numerical search.
