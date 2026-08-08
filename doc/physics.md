# Physics

`use physics` loads Tungsten's shared Core surface for measured scalar data,
basic thermodynamics, and a narrow finite-volume gas-dynamics foundation. The
module unifies the earlier experimental-data and Euler APIs; neither API is
deprecated by the union.

| Area | Public surface | Present scope |
|---|---|---|
| Measurement | `Measurement` | Scalar values with first-order standard-uncertainty propagation |
| Experiments | `PhysicalObservable`, `PhysicalObservation`, `ExperimentalDataset`, `PhysicsEstimate` | Same-observable datasets and a one-constant generalized least-squares fit |
| Constants and gas laws | `Physics`, `IdealGas` | Selected SI constants, unit-boundary conversion, and an ideal-gas equation of state |
| Hyperbolic systems | `CompressibleEuler`, `IsothermalEuler` | Boxed reference states, fluxes, wavespeeds, and admissibility in one to three dimensions |
| Numerical flux and reconstruction | `LaxFriedrichs`, `Minmod` | Local Lax-Friedrichs fluctuations and componentwise minmod reconstruction |
| Scalar reference model | `BurgersEquation` | Inviscid Burgers flux, entropy pair, exact Riemann values, and Godunov flux |
| Grid evolution | `FiniteVolume` | Cartesian finite-volume kernels with minmod reconstruction and SSP-RK2 time stepping |
| Diagnostics | `FiniteVolumeDiagnostics` | Sampled error, variation, entropy, conservation, convergence, and CFL checks |
| Configured runs | `EulerSimulation` | Unit-aware solver setup and Plot3D visualization capture |

This is a computational foundation, not a comprehensive physics framework.
It has no general field/trajectory data model, material database, multiphase or
viscous model, unstructured mesh, adaptive mesh, implicit solver, turbulence
model, automatic parameter inference, or proof-producing numerical backend.

## Measurements and uncertainty

The `value ± uncertainty` syntax constructs a `Measurement` whose uncertainty
is a standard uncertainty. Arithmetic uses a first-order Taylor model. For
two inputs `x` and `y`,

```text
var(f(x,y)) = fx² ux² + fy² uy² + 2 fx fy rho ux uy,
```

where `fx` and `fy` are the local derivatives, `ux` and `uy` are standard
uncertainties, and `rho` is their Pearson correlation coefficient. Addition,
subtraction, multiplication, division, scalar scaling, powers, and square
roots follow this rule. For example, multiplication uses `fx = y` and
`fy = x`; it does not add relative errors linearly.

Distinct inputs are independent unless one has been linked directly to the
other with `correlate`; using the identical `Measurement` object twice implies
correlation one. The current object records one direct peer correlation. A
derived result does not retain a covariance graph, so shared-input expressions
must be reformulated or supplied through an explicit covariance matrix when
correlation matters. Random and systematic labels are propagated by the same
local derivative and correlation model; the labels do not create a richer
component-specific covariance model. General arithmetic returns a symmetric
standard uncertainty even when an input was asymmetric. Nonlinear propagation
is a local linearization: it can be inaccurate for large uncertainties,
singular points, strongly skewed distributions, or discontinuous models. A
`Measurement` is not an interval enclosure or a distributional guarantee.

```tungsten
length = Measurement.new(~2.0, ~0.01)
width = Measurement.new(~3.0, ~0.02)
area = length * width

same_sensor_a = Measurement.new(~10.0, ~0.2)
same_sensor_b = Measurement.new(~12.0, ~0.3)
same_sensor_a.correlate(same_sensor_b, ~0.5)
difference = same_sensor_a - same_sensor_b
```

`PhysicalObservable` gives an experimental scalar a name and an opaque common
unit tag. Convert all values and uncertainties into that common unit before
constructing observations; this layer does not convert `Quantity` values
inside a covariance matrix. `PhysicalObservation` also records a run ID,
capture label, metadata, and measurement provenance.

`ExperimentalDataset` accepts either independent observations or a supplied
covariance matrix. The matrix must be square, symmetric, positive definite,
and have diagonal entries equal to the squared observation uncertainties.
`fit_constant`/`gls_mean` estimates one constant shared by every row:

```text
mu       = (1^T C^-1 y) / (1^T C^-1 1)
u(mu)^2  = 1 / (1^T C^-1 1).
```

The result reports chi-square and degrees of freedom. It assumes that the
covariance is complete and fixed and interprets the inputs as first-order
Gaussian standard uncertainties. It neither estimates nor rescales the
covariance, and `converged?` describes completion of the direct solve rather
than goodness of fit. It is numerical and deliberately reports
`certified? == false`; no conditioning or rank-revealing solver is yet used.

## Units and raw SI kernels

Constants such as `Physics.speed_of_light` and `Physics.boltzmann` return
dimensioned `Quantity` values. Their `_si` forms return raw `f64` values in SI
base units. `Physics.si(value, unit)` is the explicit conversion boundary used
by configured simulations; a plain number is assumed to already use the
requested SI unit.

`IdealGas` provides dimensioned pressure, density, and temperature helpers and
raw-SI gamma-law helpers. `FiniteVolume` deliberately stores plain `f64[]`
arrays for its hot loops. Units should be checked and converted once at the
configuration boundary and reattached when reporting results.

## Euler state model

The boxed Euler APIs use conserved arrays in this order:

```text
compressible: [rho, rho*vx, (rho*vy, (rho*vz,)) E]
isothermal:   [rho, rho*vx, (rho*vy, (rho*vz,))]
```

Primitive compressible arrays are `[rho, vx, ..., pressure]`; primitive
isothermal arrays are `[rho, vx, ...]`. Directions are zero based. A
compressible state is admissible only when all components are finite,
`rho > 0`, and internal-energy density
`E - |momentum|²/(2 rho) > 0`. Isothermal states require finite components and
positive density.

Use the explicit grid methods when state layout matters:

```tungsten
fv.set_primitive_cell(0, [~1.0, ~0.0, ~1.0])
primitive = fv.primitive_cell(0)
conserved = fv.conserved_cell(0)
fv.set_conserved_cell(0, conserved)
```

The older `set_cell(i, j, k, primitive)` and `cell(...)` methods remain for
compatibility; `cell` returns conserved values.

## Finite-volume evolution

`FiniteVolume` operates on uniform Cartesian grids in one, two, or three
dimensions. It combines componentwise minmod reconstruction, local
Lax-Friedrichs fluctuations, conservative intra-cell flux correction, and an
explicit SSP-RK2 update. Boundaries support the solver's periodic, outflow,
reflecting, inflow, and masked-solid paths.

The public CFL value is the global sum-rate Courant number:

```text
dt = cfl / sum_d(max_wave_speed_d / dx_d).
```

Its default is `0.4`; assignments must be finite and in `(0, 1]`. That range
is an API safety bound, not a theorem that every configuration is stable at
`cfl = 1`. Explicit timesteps must also be positive, finite, and no larger
than the current CFL step.

Second-order reconstructed face states that are non-finite or violate density
or internal-energy admissibility fall back locally to the cell-average state.
`last_reconstruction_fallbacks` reports how often that occurred in the most
recent step. Both SSP-RK2 stages are scanned for admissibility; a failing step
restores the pre-step state and raises. This is a controlled failure policy,
not a proof of positivity preservation. There is no step retry, adaptive
fallback hierarchy, vacuum model, or demonstrated convergence order for the
Euler driver yet.

`field(:internal_energy)` and `field(:specific_internal_energy)` return
specific internal energy for compressible Euler. Isothermal systems have no
energy equation and reject these fields. `totals` multiplies the conserved
cell densities by cell volume and returns their discrete domain integrals,
excluding masked solid cells. Conservation interpretation requires compatible
closed or periodic boundaries and consistent source-free evolution.

`FiniteVolumeDiagnostics` can consume `field(...)` arrays and `totals`
vectors. Its TVD, entropy, CFL, conservation, and observed-order answers are
sampled numerical diagnostics, not stability or convergence proofs. See
[physics-nonlinear-pde.md](physics-nonlinear-pde.md) for the scalar reference
and diagnostic details.

## Configured simulations and data retention

`EulerSimulation` adds a unit-aware builder around `FiniteVolume`:

```tungsten
sim = Physics.compressible_simulation(1)
  .resolution([200])
  .domain([1 m])
  .duration(0.2 s)
  .courant(~0.4)
  .capture([:rho, :pressure], 20)
  .init -> (x) x < ~0.5 ? [~1.0, ~0.0, ~1.0] : [~0.125, ~0.0, ~0.1]

sim.run!
```

Each `run!` rebuilds the solver from the configured initial condition. Use
`sim.fv.run_to!` explicitly when continuing an existing raw solver state.

Captured `frames` are Plot3D-packed, 8-bit quantized visualization artifacts.
They are not lossless solver checkpoints or a research trajectory format. Use
the underlying `fv` fields and totals for numerical analysis and retain the
configuration, code revision, raw state, and capture metadata separately when
reproducibility matters.

No Lean proof, generated proof artifact, outward-rounded enclosure, or
code-to-proof identity certificate ships with this module. Focused interpreted
and native tests provide regression evidence only.
