# Probability

`use probability` loads Core Probability: checked scalar probability laws,
stable probability-domain primitives, explicit replayable sampling, and a
focused set of stochastic processes. It builds only on committed Core `Math`,
`Special`, and the mulberry32 engine in `Stats`; it does not depend on separate
Statistics, Finance, Optimization, Signal, or Physics worktrees.

Probability owns probability measures, random streams, Monte Carlo sampling,
and stochastic processes. Statistics owns estimation, hypothesis testing,
fitted models, and inference policy. The log-weight and resampling operations
here are inference-facing building blocks, not estimators.

## Module architecture

`core/probability.w` is the public feature boundary and compatibility facade.
The implementation is split by mathematical role, following the nested Core
Algebra layout:

| Submodule | Responsibility |
|-----------|----------------|
| `probability/primitives.w` | parameter checks, Kahan sums, log-sum-exp, normalized weights, effective sample size |
| `probability/special.w` | tail-stable standard Normal CDF/survival, inverse Normal, log-factorial |
| `probability/support.w` | interval, integral, and union support objects |
| `probability/rng.w` | explicit RNG contract and replayable `ProbabilityRng` |
| `probability/distribution.w` | executable scalar distribution protocol |
| `probability/distributions/*.w` | elementary, Gamma/Beta, count, categorical, and mixture laws |
| `probability/sampling.w` | weighted draws, permutations, sampling without replacement, particle resampling |
| `probability/process.w` | stochastic-process base protocol |
| `probability/processes.w` | finite Markov chains, Wiener processes, homogeneous Poisson processes |

Applications should normally `use probability`; the nested modules make
ownership and future extension clear rather than requiring callers to assemble
the feature themselves.

## Distribution protocol

Every distribution factory returns a `ProbabilityDistribution`. The common
surface distinguishes densities from masses:

```w
use probability

d = Probability.normal(~3.0, ~2.0)

d.continuous?              # true
d.discrete?                # false
d.pdf(~3.0)                # density; not a singleton probability
d.probability(~3.0)        # pdf for continuous, pmf for discrete
d.log_prob(~3.0)           # common log-likelihood spelling
d.cdf(~3.0)
d.survival(~3.0)
d.log_cdf(~3.0)
d.log_survival(~3.0)
d.mean
d.variance
d.standard_deviation
d.entropy
d.quantile(~0.95)
d.support.contains?(~3.0)
```

Calling `pdf` on a discrete law or `pmf` on a continuous law raises. Base
protocol methods also raise when a concrete law does not implement the
operation; absence is never represented by a plausible numeric value.

`ProbabilitySupport` represents finite or unbounded interval endpoints,
open/closed boundaries, and integral support. `ProbabilityUnionSupport`
represents the union of mixture component supports. Nil endpoints denote an
unbounded side, rather than using a floating infinity sentinel.

### Implemented laws

All parameters are converted to binary64 after validation unless stated
otherwise.

| Factory | Domain | Implemented operations |
|---------|--------|------------------------|
| `bernoulli(p)` | `0 <= p <= 1` | PMF, CDF/survival, moments, entropy, quantile, sampling |
| `uniform(a, b)` | finite `a < b` | PDF, CDF/survival, moments, entropy, quantile, sampling |
| `normal(mu, sigma)` | finite `mu`; finite `sigma > 0` | PDF, tail-stable CDF/survival, moments, entropy, inverse CDF, sampling |
| `exponential(rate)` | finite `rate > 0` | PDF, CDF/survival, moments, entropy, quantile, sampling |
| `gamma(shape, scale)` | finite `shape, scale > 0` | PDF, incomplete-gamma CDF/survival, moments, entropy, quantile, sampling |
| `beta(alpha, beta)` | finite `alpha, beta > 0` | PDF, incomplete-beta CDF/reflected survival, moments, entropy, quantile, sampling |
| `categorical(weights)` | nonempty finite nonnegative weights with positive total | index PMF, CDF, moments, entropy, quantile, sampling |
| `poisson(rate)` | finite `rate > 0` | PMF, incomplete-gamma CDF/survival, moments, quantile, small/large-rate sampling |
| `mixture(components, weights)` | nonempty components with one common measure type | PDF or PMF, stable log probability, CDF, moments, union support, sampling |

Categorical values are integer indices `0..category_count-1`; associate domain
labels in application code. Supplied weights are normalized with compensated
summation and are copied. A mixture likewise normalizes its weights and rejects
mixing discrete and continuous components. Mixture entropy and quantile, and
Poisson entropy, are not yet implemented and raise through the base protocol.

Gamma and Beta densities correctly expose infinite endpoint densities when a
shape parameter is below one. This is a density singularity, not an atom.
`Poisson.quantile(1)` returns positive infinity, consistent with its unbounded
support.

## Sampling and reproducibility

Sampling always requires an explicit RNG. There is no hidden global state:

```w
rng = Probability.rng(20260802)
d = Probability.gamma(~2.5, ~0.75)

x = d.sample(rng)
xs = d.samples(1000, rng)
```

`Probability.rng(seed)` wraps Tungsten's committed mulberry32 `StatsRng`.
Seeds must be integers, are reduced to their low 32 bits, and zero is normalized
to one. Equal seeds produce identical streams in interpreted and compiled
execution. `rng.integer(limit)` uses rejection over exact 32-bit words and is
unbiased for integer limits through `2^32`.

The distribution samplers use:

- direct comparison for Bernoulli and affine transforms for Uniform;
- Box-Muller for Normal and inverse transform with `log1p` for Exponential;
- Marsaglia-Tsang rejection, including the shape-boost transform, for Gamma;
- independent Gamma ratios for Beta;
- cumulative selection for Categorical and mixtures;
- Knuth's product method for Poisson rates below 30 and Hoermann PTRS
  transformed rejection at larger rates.

Rejection loops have explicit attempt limits and raise if those limits are
exceeded. A custom RNG is accepted when it responds to `random` and every draw
is a real binary64 value in `[0, 1)`; the contract is checked at use sites.

The bundled generator is appropriate for deterministic tests, replayable local
simulation, and modest serial Monte Carlo. It is not cryptographically secure,
splittable, counter-based, or designed to prove independence between parallel
streams. Use `Random.bytes` for security-sensitive entropy.

## Probability-domain and Monte Carlo primitives

Likelihood and particle methods can stay in the log domain until normalized:

```w
logs = [~-1000.0, ~-1001.0, ~-1004.0]
normalizer = Probability.logsumexp(logs)
weights = Probability.normalize_log_weights(logs)
ess = Probability.effective_sample_size_from_log(logs)

indices = Probability.systematic_resample(
  weights, 1000, Probability.rng(7))
```

`logaddexp`, `logsumexp`, `log1mexp`, normalization of linear or log weights,
and effective sample size use stable formulas. All-negative-infinity log
weights, NaNs, negative weights, nonfinite weights, empty weight vectors, and
zero total mass raise.

`ProbabilitySampling` also supplies weighted selection, unbiased seeded
permutations, sampling without replacement, and systematic and stratified
resampling. Resampling returns source indices and requires an explicit output
count, making particle population changes visible at the call site.

## Stochastic processes

Three finite-dimensional process building blocks are implemented:

```w
chain = Probability.markov_chain(
  [~1.0, ~0.0],
  [[~0.9, ~0.1], [~0.25, ~0.75]])
states = chain.sample_path(100, Probability.rng(3))
path_log_mass = chain.path_log_probability(states)

brownian = Probability.wiener(~0.1, ~2.0)
values = brownian.sample_grid(
  [~0.0, ~0.25, ~0.5, ~1.0], Probability.rng(4))
transition = brownian.transition_distribution(~0.5, values[2], ~1.0)

events = Probability.poisson_process(~3.0)
arrivals = events.sample_arrivals(20, Probability.rng(5))
counts = events.sample_grid([~0.5, ~1.0, ~2.0], Probability.rng(5))
```

`FiniteMarkovChain` normalizes and copies the initial and square transition
weights, samples index-valued paths, and evaluates complete path log mass.
`WienerProcess` supports drift and positive volatility, exact Gaussian
transitions, nondecreasing finite grids, and regular-grid paths.
`PoissonProcess` supports exponential interarrival paths, counts on finite
nondecreasing grids, count moments, and Poisson increment distributions. Its
open-ended counting operations take an explicit event cap to bound work.

Process grids are completely validated before consuming randomness. Invalid
times, states, shapes, negative counts, decreasing grids, or exceeded event
caps raise with probability-specific messages.

## Numerical contract and limitations

This module uses IEEE-754 binary64 values and ordinary deterministic
algorithms, not interval arithmetic or certified error bounds.

- Normal central and tail probabilities inherit `Special.erfc`; its inverse is
  Acklam's approximation followed by one Newton correction.
- Gamma and Poisson tails inherit complementary incomplete-gamma routines.
  Beta upper tails use the reflected incomplete-beta identity rather than
  subtracting a value near one.
- Gamma and Beta quantiles use 100 bisection steps. They are deterministic and
  monotone, but not accompanied by a returned error certificate.
- PDFs and PMFs can underflow in extreme tails. Prefer analytic `log_prob` and
  log-sum-exp for likelihood calculations. Base `log_cdf` and `log_survival`
  can still underflow after the underlying probability rounds to zero.
- The RNG supplies only 32 bits per uniform variate. Exponential inverse draws
  therefore cannot exceed about `22.18/rate`, and the Box-Muller radial factor
  cannot exceed about `6.66` standard deviations. Gamma shape-boost sampling
  can produce an exact zero through finite RNG resolution.
- NaN evaluation points generally propagate through analytic functions and are
  never members of a support. Invalid parameters and nonfinite process inputs
  raise.
- Numerical normalization tests establish focused invariants at practical
  tolerances; they are not formal proofs over every parameter regime.

## Major remaining gaps

Core Probability now has a coherent scalar-distribution, sampling, and basic
process foundation, but it is not a complete state-of-the-art probabilistic
programming or research stack. Important missing work includes multivariate
and matrix-valued laws, Dirichlet and conjugate families, truncation and
transforms, generic random-variable graphs and conditioning, measure-theoretic
combinators, quasi-Monte Carlo, counter-based/splittable parallel RNGs, alias
tables, MCMC/HMC/SMC kernels and diagnostics, automatic reparameterization,
continuous-time Markov chains, bridges, general Gaussian processes, jump/SDE
solvers, and certified extreme-tail or arbitrary-precision numerics.

Estimation, posterior inference, model comparison, and fitted-distribution APIs
remain deliberately outside this module and should be developed in Statistics
against these public probability primitives.
