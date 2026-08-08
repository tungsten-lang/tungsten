# Nonlinear PDE reference support

This additive layer covers two narrow gaps exposed by Lanyon's
[nonlinear-PDE benchmarking note](https://lanyon.ai/research/nonlinear-benchmarking/):
an inviscid Burgers reference model and reusable diagnostics for finite-volume
outputs. It does not claim to be a complete nonlinear PDE solver or a formal
verification system.

The reference model and diagnostics are part of the unified Physics surface:

```tungsten
use physics
```

Code that needs only one dependency-free helper may instead load
`core/physics/burgers` or `core/physics/finite_volume_diagnostics` directly.

## Burgers reference model

`BurgersEquation` describes the inviscid scalar conservation law

```text
u_t + (u^2 / 2)_x = 0.
```

It provides the physical flux and characteristic speed, the quadratic entropy
pair, Rankine-Hugoniot shock speed, the exact self-similar entropy solution for
shock and rarefaction Riemann data, an entropy-consistent Godunov flux, and the
first breaking time for sinusoidal initial data. These are reference/model
operations: the module does not reconstruct cell edges or advance a grid.

```tungsten
kind = BurgersEquation.riemann_kind(~-1.0, ~1.0) # :rarefaction
u = BurgersEquation.riemann_value(~-1.0, ~1.0, ~0.25) # 0.25
s = BurgersEquation.shock_speed(~2.0, ~0.0) # 1.0
```

Only the inviscid equation is represented. Viscous Burgers, boundary
conditions, source terms, positivity policies, and a finite-volume driver are
outside this module.

## Numerical diagnostics

`FiniteVolumeDiagnostics` operates on scalar field arrays or vectors of
conserved totals. It supplies:

- open or periodic discrete total variation and a before/after TVD check;
- finite-volume `L1`, `L2`, and `Linf` errors and an `L2` norm;
- quadratic entropy and tolerance-aware non-increase checks;
- observed convergence order from two errors and a refinement ratio;
- signed absolute and relative conservation drift;
- validation of a Courant number against a caller-supplied CFL bound.

These are empirical diagnostics, not proofs. `tvd?` checks sampled output and
does not prove that every update is TVD. `observed_order` describes two measured
errors and does not establish asymptotic convergence. `cfl_contract?` does not
derive a stability limit: the caller must supply the bound appropriate to the
actual flux, limiter, reconstruction, dimensional splitting, and time
integrator. Floating-point comparisons use explicit tolerances.

## Integration boundary

The unified module also contains the Euler finite-volume solver: second-order
minmod reconstruction, Lax-Friedrichs wave fluctuations, conservative
intra-cell flux correction, a global sum-rate CFL timestep, SSP-RK2,
multidimensional states, conservation totals, and admissibility scans. These
kernels are not duplicated by the Burgers reference or diagnostic helpers.

Solver outputs connect directly to the diagnostics:

```tungsten
initial = fv.totals
before = fv.field(:rho)
fv.step!
after = fv.field(:rho)

drift = FiniteVolumeDiagnostics.conservation_drift(initial, fv.totals)
sampled_tvd = FiniteVolumeDiagnostics.tvd?(before, after, ~1.0e-10, true)
```

`totals` are cell-volume-weighted discrete integrals, and `field` returns raw
SI-valued arrays.
The Burgers model remains a reference-data source rather than a system adapter
for the Euler-only grid driver. A reusable scalar conservation-law driver is a
future extension.

No Lean proof, generated proof artifact, IEEE-754 proof, or code/proof identity
certificate is added by these modules. Passing the focused interpreted/native
tests is numerical regression evidence only.
