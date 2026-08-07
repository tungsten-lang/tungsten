# Dynamics — dynamical systems in core

`core/dynamics` models continuous flows and discrete maps with the standard
research toolkit: trajectory integration, fixed points and linear stability,
Lyapunov exponents and spectra, bifurcation sweeps, Poincaré sections, and
attractor reconstruction. Classes autoload — referencing `Dynamics` (or any
system class) is enough; no `use` directive is required.

States are plain Arrays of `~f64` Floats. Spectral and Jacobian work rides
`LinAlg` (`solve`, `qr`, `eigenvalues` — dense float, row-major nested
lists); the closure-based general ODE API stays in `Solve`
(`Solve.ivp(f, t_start, t_stop, y0, method, dt)`).

## System contracts

A continuous system subclasses `Flow` and supplies `dim` and
`f(t, x) -> dx/dt`; a discrete system subclasses `MapSystem` and supplies
`dim` and `step(x)`. Both inherit a central-difference `jac` — override it
with an analytic Jacobian when cheap. Separable Hamiltonian systems
subclass `HamiltonianSystem` and supply `accel(q) = -∇V(q)` (plus
`potential(q)` for `energy(q, p)` reporting).

```tungsten
+ Lorenz < Flow
  -> new(sigma, rho, beta)
    ...
  -> dim
    3
  -> f(t, x)
    [@sigma * (x[1] - x[0]), x[0] * (@rho - x[2]) - x[1], x[0] * x[1] - @beta * x[2]]
  -> jac(t, x)
    ...
```

Classic systems ship with `.classic` factories carrying canonical
parameters: `Lorenz` (10, 28, 8/3), `Rossler` (0.2, 0.2, 5.7), `VanDerPol`,
`Duffing`, `DoublePendulum`, `HarmonicOscillator`, and the maps
`LogisticMap` (r = 4), `Henon` (1.4, 0.3), `StandardMap` (K = 0.971635).

## Integration

```tungsten
lz = Lorenz.classic
tr = Dynamics.trajectory(lz, [~1.0, ~1.0, ~1.0], ~0.0, ~50.0, ~0.01)
# tr[:t] — times, tr[:x] — states (fixed-step RK4)
ta = Dynamics.trajectory_adaptive(lz, x0, ~0.0, ~50.0, ~0.01)
# adaptive Dormand-Prince 5(4) via Solve.rk45 — tolerances pick the step
sol = Solve.rk45_dense(-> (t, y) lz.f(t, y), ~0.0, ~50.0, x0, ~0.01)
sol.at(~12.34)   # dense output: continuous solution at any time in range
x  = Dynamics.advance(lz, x0, ~0.0, 5000, ~0.01)   # no path storage
orb = Dynamics.orbit(Henon.classic, [~0.1, ~0.1], 10_000)
```

Hamiltonian systems get symplectic steppers whose energy error stays
bounded instead of drifting: `Dynamics.verlet(ham, q0, p0, t_stop, dt)`
(Störmer-Verlet) and `Dynamics.yoshida4(...)` (4th order).

## Fixed points and stability

```tungsten
fp = Dynamics.fixed_point_flow(lz, [~0.1, ~0.1, ~0.1])   # Newton + LinAlg.solve
Dynamics.classify_flow(lz, fp)                            # :saddle
Dynamics.eigenvalues_flow(lz, fp)                         # [[re, im], …]
mp = Dynamics.fixed_point_map(Henon.classic, [~0.6, ~0.2])
Dynamics.classify_map(Henon.classic, mp)                  # :saddle
```

Flow classes: `:sink`, `:spiral_sink`, `:source`, `:spiral_source`,
`:saddle`, `:center`, `:nonhyperbolic`. Map classes compare |λ| to 1:
`:sink`, `:source`, `:saddle`, `:nonhyperbolic`. Eigenvalues come from
`LinAlg.eigenvalues`: n ≤ 8 uses the characteristic polynomial +
Durand-Kerner (dependency-free); larger matrices route through the
LAPACK `dgeev` bridge (Accelerate / OpenBLAS) with Durand-Kerner as the
fallback wherever the bridge is unavailable.

## Lyapunov exponents

```tungsten
Dynamics.lyapunov_max(lz, x0, transient_t, run_t, dt)      # Benettin
Dynamics.lyapunov_max_map(msys, x0, transient, n)          # tangent vector
Dynamics.lyapunov_spectrum(lz, x0, transient_t, renorms, steps_per, dt)
Dynamics.lyapunov_spectrum_map(msys, x0, transient, n)     # QR each step
Dynamics.kaplan_yorke(spectrum)                            # Lyapunov dimension
```

Spectra integrate the tangent matrix dV/dt = J(x)·V alongside the state
(RK4 on the augmented system) with periodic `LinAlg.qr`
re-orthonormalization, accumulating ln of R's diagonal.

Validated against the literature (spec/core/dynamics_spec.w):
logistic r=4 gives λ = ln 2; Hénon gives λ ≈ [0.42, −1.63] with
λ₁+λ₂ = ln b exactly and Kaplan-Yorke ≈ 1.26; Lorenz gives
λ ≈ [0.90, 0, −14.5] with Σλ = −(σ+1+β) exactly and Kaplan-Yorke ≈ 2.06.

## Bifurcations, periods, Poincaré sections

```tungsten
bf = Dynamics.bifurcation(-> (r) LogisticMap.new(r), ~2.8, ~4.0, 400, [~0.3], 500, 64)
# bf[:r] / bf[:x] — parallel arrays, ready to plot
Dynamics.period(LogisticMap.new(~3.5), [~0.3], 2000, 16, ~1.0e-5)   # → 4
pc = Dynamics.poincare(lz, x0, [~0.0, ~0.0, ~1.0], ~27.0, ~5.0, ~200.0, ~0.005)
# upward crossings of z = 27, secant-interpolated onto the plane
Dynamics.return_map(pc[:points], 0)    # [[v_k, v_{k+1}], …]
```

## Continuation and periodic orbits

```tungsten
br = Dynamics.continue_equilibria(-> (rho) Lorenz.new(~10.0, rho, ~8.0/~3.0), ~0.5, ~1.5, 41, [~0.1, ~0.1, ~0.1])
Dynamics.stability_changes(br)     # [[p_before, p_after, class_before, class_after], …]
# → detects the pitchfork at ρ = 1 and (on the C± branch) the
#   subcritical Hopf at ρ ≈ 24.74

orb = Dynamics.shoot_periodic(VanDerPol.classic, [~2.0, ~0.0], ~6.28, ~0.01)
orb[:period]        # 6.66328687 (Van der Pol μ = 1)
orb[:multipliers]   # Floquet spectrum from the monodromy — {1, 0.00086}
Dynamics.shoot_forced(sys, x0, forcing_period, dt)   # non-autonomous, T known
Dynamics.monodromy(sys, x0, period, steps)           # [φ_T(x0), M]
```

Equilibrium branches follow the fixed point across a parameter sweep
(secant predictor + Newton corrector), recording the stability class at
every point; periodic orbits solve φ_T(x0) = x0 by single shooting on the
monodromy with a bordered phase row (autonomous) or plain Newton (forced).

## Basins of attraction

```tungsten
well = Duffing.new(~0.5, ~0.0 - ~1.0, ~1.0, ~0.0, ~1.0)   # damped double well
grid = Dynamics.basins(well, ~0.0-~2.0, ~2.0, ~0.0-~2.0, ~2.0, 200, 200,
                       ~50.0, ~0.01, [[~0.0-~1.0, ~0.0], [~1.0, ~0.0]], ~0.5)
Dynamics.basin_counts(grid)    # {0 => …, 1 => …, -1 => …}
```

Each cell integrates independently and labels itself by the attractor it
lands nearest — which is also why the sweep is embarrassingly parallel:
`doc/examples/gpu_basins.w` is the same sweep as a `@gpu fn` Metal kernel
(one thread per cell), verified cell-for-cell against the CPU twin.

## Attractor reconstruction

```tungsten
vecs = Dynamics.embed(series, m, tau)          # Takens delay embedding
tau  = Dynamics.suggest_tau(series, max_lag)   # first autocorrelation < 1/e
d2   = Dynamics.correlation_dimension(points, eps_lo, eps_hi, neps)
# Grassberger-Procaccia: slope of ln C(ε) vs ln ε over the scaling region
```

The Hénon attractor comes out at D₂ ≈ 1.21 from ~350 points.

## Performance notes

The interpreter engine runs everything but is ~100× slower on the hot
loops — long Benettin runs, flow spectra, and O(N²) correlation sums
belong on the compiled engine (`bin/tungsten -o`). Correlation sums are
pairwise: keep N ≲ 2000, or expect quadratic time.

## Follow-ups

- Pseudo-arclength continuation (the natural-parameter sweep stops at
  folds; arclength follows the branch around them).
- Multiple shooting / collocation for stiff or long-period orbits.
- GPU parameter-grid sweeps beyond basins (Lyapunov maps, isoperiodic
  diagrams).
