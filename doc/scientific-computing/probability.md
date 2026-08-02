# Probability

`use probability` loads Core Probability: checked probability laws, explicit
random streams, stable probability-domain numerics, Monte Carlo algorithms,
and stochastic processes. It builds on committed Core `Math`, `Special`,
`LinAlg`, and the compatibility RNG in `Stats`; it has no dependency on
separate Statistics, Finance, Optimization, Signal, or Physics worktrees.

Probability owns probability measures, generative models, stochastic
processes, sampling, and general algorithms that operate on a caller-supplied
probability target. Statistics owns data-derived estimators, regression,
hypothesis tests, fitted-model policy, and statistical reporting. Thus HMC and
particle filtering live here, while estimating a model's parameters from a
dataset belongs in Statistics.

## Architecture

`core/probability.w` is the public feature boundary and compatibility facade.
The implementation is split by mathematical role:

| Submodule | Responsibility |
|-----------|----------------|
| `primitives.w`, `special.w`, `accuracy.w` | checked scalars, log-domain arithmetic, extreme Normal tails, inspectable numerical contracts |
| `support.w` | interval, finite, integral, union, and real-vector supports |
| `rng.w`, `streams.w`, `random_tests.w` | mulberry32 compatibility, Philox counter streams, non-certifying smoke battery |
| `distribution.w`, `distributions/*.w` | scalar distribution protocol and concrete laws |
| `linear_algebra.w`, `multivariate.w` | checked dense SPD algebra and multivariate Normal laws |
| `sampling.w` | weighted draws, permutations, sampling without replacement, particle resampling |
| `transforms.w`, `dependence/copulas.w` | affine/truncated/conditioned laws and Gaussian copulas |
| `process.w`, `processes*.w` | discrete/continuous-time processes, HMMs, renewal, scalar SDE integration |
| `inference/*.w` | MCMC, fixed-trajectory HMC, bootstrap SMC, mean-field VI, diagnostics |

Applications should normally `use probability`; nested modules are ownership
boundaries, not an assembly burden for callers.

## Scalar distributions

Every scalar factory returns a `ProbabilityDistribution`. Densities and masses
remain distinct:

```w
d = Probability.normal(~3.0, ~2.0)

d.continuous?              # true
d.pdf(~3.0)                # a density, not singleton probability
d.probability(~3.0)        # pdf for continuous, pmf for discrete
d.log_prob(~3.0)
d.cdf(~3.0)
d.survival(~3.0)
d.log_cdf(~3.0)
d.log_survival(~3.0)
d.mean
d.variance
d.entropy
d.quantile(~0.95)
d.support.contains?(~3.0)
d.log_probabilities([~1.0, ~2.0, ~3.0])
```

Calling `pdf` on a discrete law or `pmf` on a continuous law raises. A base
method also raises when the concrete law does not implement it; absence is not
encoded as a plausible number.

| Factory | Parameter domain | Implemented surface |
|---------|------------------|---------------------|
| `bernoulli(p)` | `0 <= p <= 1` | PMF, CDF/survival, moments, entropy, quantile, sampling |
| `uniform(a, b)` | finite `a < b` | PDF, CDF/survival, moments, entropy, quantile, sampling |
| `normal(mu, sigma)` | finite `mu`; finite `sigma > 0` | PDF, extreme log tails, moments, entropy, inverse CDF, sampling |
| `exponential(rate)` | finite `rate > 0` | PDF, CDF/survival, moments, entropy, quantile, sampling |
| `gamma(shape, scale)` | finite positive parameters | PDF, incomplete-gamma tails, moments, entropy, bisection quantile, sampling |
| `beta(alpha, beta)` | finite positive parameters | PDF, incomplete-beta/reflected tails, moments, entropy, bisection quantile, sampling |
| `categorical(weights)` | nonempty nonnegative finite weights with positive total | index PMF, CDF, moments, entropy, quantile, sampling |
| `poisson(rate)` | finite `rate > 0` | PMF, incomplete-gamma tails, moments, quantile, small/large-rate sampling |
| `mixture(components, weights)` | nonempty components with one measure type | density/mass, log-sum-exp likelihood, CDF, moments, union support, sampling |

Categorical values are integer indices. Supplied weight arrays are copied and
normalized with compensated summation. Mixture entropy/quantile and Poisson
entropy remain unimplemented and raise. Gamma/Beta endpoint singularities are
represented as infinite densities, not atoms. `Poisson.quantile(1)` is positive
infinity because the support is unbounded.

## Multivariate Normal and dense covariance algebra

```w
mvn = Probability.multivariate_normal(
  [~1.0, ~-2.0],
  [[~4.0, ~1.0], [~1.0, ~9.0]])

log_density = mvn.log_prob([~0.5, ~1.0])
draws = mvn.samples(1000, Probability.counter_rng(7, 0))
conditional = mvn.condition([0], [~3.0])
marginal = mvn.marginal([1])
image = mvn.affine([[~1.0, ~2.0]], [~0.0])
```

`MultivariateNormalDistribution` provides stable Cholesky log density,
Mahalanobis distance, reproducible sampling, batch log evaluation, marginals,
Gaussian conditioning, and exact affine images. Inputs are finite dense nested
Arrays. Covariance is copied, checked square and symmetric to relative
`1e-12`, and required to be strictly positive definite. Factorization never
silently adds jitter or clips eigenvalues.

The implementation reuses one factorization for density/sampling and one for a
conditioning block. It does not yet accept `Tensor` or `SparseMatrix`, dispatch
to BLAS/LAPACK, pivot semidefinite covariances, or expose low-rank operators.
Ill-conditioned matrices can lose accuracy even when Cholesky succeeds; query
`Probability.numerical_contract(:multivariate_normal)` for the executable
contract.

## Random streams and sampling

Sampling always requires an explicit RNG. There is no global seed:

```w
serial = Probability.rng(20260802)
parallel = Probability.counter_rng(20260802, 17)
streams = Probability.stream_pool(20260802, 8)
```

`Probability.rng` preserves the original mulberry32 stream. It is replayable
but not splittable. `Probability.counter_rng` implements Philox2x32-10 over a
64-bit counter and a 32-bit stream key; `split(stream)` and `stream_pool`
provide deterministic addressable streams suitable for partitioned CPU/GPU
work assignment. The current implementation is pure Core code and does not
itself supply a GPU kernel. Both generators expose unbiased rejection-based
`integer(limit)` through `2^32`.

Neither generator is cryptographic. The Philox mapping is cross-engine golden
tested, but this module does not prove stream independence. `random_battery`
checks mean, variance, lag-one correlation, and binned chi-square at broad
six-sigma thresholds. Its result always reports `certified? == false`; it is a
regression smoke test, not TestU01 or PractRand.

Distribution samplers use Box-Muller, inverse Exponential transform,
Marsaglia-Tsang Gamma rejection, Gamma-ratio Beta sampling, cumulative
categorical selection, Knuth small-rate Poisson, and Hoermann PTRS large-rate
Poisson. Rejection loops have explicit caps.

`ProbabilitySampling` supplies weighted selection, seeded permutations,
sampling without replacement, and systematic/stratified resampling. Resampling
returns source indices and requires an explicit output population size.

## Numerical probability contract

Core Probability uses IEEE-754 binary64 and deterministic algorithms, not
interval arithmetic or certified error bounds.

```w
tail = Probability.normal.log_survival(~40.0)  # finite near -804.6084
contract = Probability.numerical_contract(:normal_tail)
contract.certified?                            # false
```

- Normal CDF/survival uses complementary `erfc` centrally. Log tails beyond
  eight standard deviations use a 12-term asymptotic Mills-ratio expansion, so
  log probabilities remain finite after linear probabilities underflow.
- Inverse Normal uses Acklam's approximation followed by a tail-aware Newton
  correction. Tests cover a `1e-12` upper probability, not every subnormal.
- Gamma/Poisson tails inherit Core Special's complementary incomplete gamma;
  Beta upper tails use the reflected incomplete beta.
- Gamma/Beta quantiles perform 100 deterministic bisection steps without a
  returned proof interval.
- `logaddexp`, `logsumexp`, `logdiffexp`, `log1mexp`, normalized log weights,
  and ESS avoid routine cancellation. NaNs, positive-infinite log weights,
  all-zero mass, and invalid domains raise.
- Base `log_cdf`/`log_survival` implementations for laws without specialized
  tails can still underflow. PDFs/PMFs can underflow; prefer `log_prob`.
- A 32-bit uniform limits inverse-transform resolution. Exponential samples
  top out near `22.18/rate`; Box-Muller radial magnitude tops out near `6.66`
  standard deviations; Gamma shape boosting can return exact zero through
  finite stream resolution.

Numerical contract objects describe algorithms and known limitations. They do
not contain invented error guarantees.

## MCMC, SMC, variational inference, and diagnostics

Inference objects accept log targets rather than owning fitted statistical
models:

```w
log_target = -> (x)
  ~-0.5*(x[0]*x[0] + x[1]*x[1])
gradient = -> (x)
  [~0.0 - x[0], ~0.0 - x[1]]

rw = Probability.random_walk_metropolis(log_target, ~0.8)
rw_chain = rw.run([~0.0, ~0.0], 5000, Probability.rng(1), 1000, 2)

hmc = Probability.hamiltonian_monte_carlo(log_target, gradient, ~0.15, 12)
hmc_chain = hmc.run([~0.0, ~0.0], 3000,
                    Probability.counter_rng(2, 0), 500, 1)

ess = hmc_chain.effective_sample_size(0)
rhat = ProbabilityDiagnostics.split_rhat(
  [hmc_chain.samples, another_chain.samples], 0)
```

Implemented algorithms and their honest scope:

- `RandomWalkMetropolis` supports scalar or per-coordinate Gaussian proposal
  scales, burn-in, thinning, log-domain acceptance, and replayable chains.
- `HamiltonianMonteCarlo` uses identity mass, fixed step size, and a fixed
  leapfrog count. It records acceptance and energy-error divergences. Burn-in
  discards draws but performs no step-size or mass adaptation.
- HMC requires an explicit finite analytic gradient. Current Core `Dual`/`Tape`
  autodiff does not trace arbitrary vector closures and control flow, so no
  automatic-gradient or NUTS claim is made.
- `BootstrapParticleFilter` implements sequential importance weighting,
  adaptive systematic resampling by ESS, replayable propagation, filtering
  histories, and a log normalizing-constant estimate. Its callbacks are a
  stationary transition `(particle, rng)` and likelihood `(observation,
  particle)`; smoothing and ancestor genealogy are not implemented.
- `MeanFieldVariationalInference` uses reparameterized gradients and Adam for a
  diagonal Gaussian approximation. The caller supplies target gradient. It
  returns the approximation and stochastic ELBO trace, not an accuracy proof.
- `ProbabilityDiagnostics` provides lag autocorrelation, Geyer
  initial-positive-pair ESS, MCSE, and classical split R-hat. Split R-hat is
  neither rank-normalized nor folded. Users must run multiple chains and inspect
  all diagnostics; a successful API call is not convergence.

There is no NUTS, adaptation windowing, dense mass adaptation, tempering,
slice sampling, reversible jump, SMC smoothing, normalizing flow, or general
black-box VI yet.

## Stochastic processes

Implemented process models are:

- `FiniteMarkovChain`: normalized finite transitions, path sampling, and path
  log mass;
- `WienerProcess`: exact scalar Gaussian transitions and finite-grid paths;
- `PoissonProcess`: interarrivals, counts, grids, and Poisson increments;
- `ContinuousTimeMarkovChain`: validated generator matrices, absorbing states,
  exponential holding times, bounded-event jump paths, and state queries;
- `HiddenMarkovModel`: distribution-valued emissions, stable scaled forward
  likelihood/filtering, Viterbi paths, and joint sequence sampling;
- `EulerMaruyamaProcess`: scalar, possibly state/time-dependent drift and
  diffusion over strictly increasing grids;
- `RenewalProcess`: positive finite interarrival laws, arrivals, and bounded
  count queries.

CTMC matrix exponentials and finite-time transition matrices are absent.
Euler-Maruyama is fixed-grid (typically strong order `1/2` and weak order `1`
under regularity conditions), not an adaptive SDE solver; it supplies no
weak/strong error estimator. Vector SDEs, Milstein,
bridges, jump diffusions, Gaussian processes, SPDEs, and random fields remain
future work.

## Dependence, transformations, and conditioning

`GaussianCopula` validates an SPD correlation matrix, evaluates copula log
density, and samples through a latent multivariate Normal. A
`CopulaDistribution` composes it with continuous marginals supporting CDF,
quantile, and log density.

`AffineDistribution` supports nonzero positive or negative scalar transforms.
`TruncatedDistribution` provides finite-interval density, CDF, quantile, and
inverse-CDF sampling when the interval mass is representable in binary64;
extreme intervals whose endpoint CDFs coincide raise explicitly.
`FiniteConditionedDistribution` renormalizes a discrete base law over an
explicit finite set. Multivariate Gaussian `condition` provides analytic
coordinate conditioning.

Generic nonlinear change-of-variables graphs, Jacobian autodiff, regular
conditional probabilities, arbitrary events, vine/Archimedean copulas, and
copula parameter fitting are not implemented.

## Performance and validation

Scalar and multivariate distributions expose batch Array evaluation. Dense
multivariate factorization is cached, conditional solves reuse a block
factorization, and Philox streams can be assigned without mutable shared state.
No API silently converts sparse or Tensor inputs to dense.

Compiled microbenchmarks live in `benchmarks/probability/`:

```sh
bin/tungsten -o /tmp/probability_bench \
  benchmarks/probability/monte_carlo.w
/tmp/probability_bench
```

Focused interpreted/native specs cover analytic references, numerical
normalization, extreme tails, cross-engine RNG/sampler vectors, SPD rejection,
Gaussian conditioning, MCMC moments, SMC weights, VI recovery, process
invariants, copula formulas, transformation support, failure domains, and RNG
smoke batteries. These tests characterize selected regimes, not universal
statistical correctness.

`spec/reference/probability_numpy_reference.py` independently checks the
multivariate Normal, conditioning, affine covariance, HMM, and Gaussian-copula
constants against NumPy linear algebra. It is a development/reference check,
not a runtime dependency.

## Symbolic probability boundary

Core `Expression` can differentiate and integrate many scalar formulas, but it
does not currently provide assumption propagation, measurable spaces, discrete
versus continuous measure objects, support-aware piecewise integration, Dirac
masses, or normalization/conditioning proof machinery. A symbolic probability
facade without those dependencies would only print formal expressions, so Core
Probability intentionally does not expose one yet.

The sound next dependency is a measure-aware symbolic layer with assumptions
and piecewise support, followed by exact expectation/conditioning rules tested
against the numeric laws here.

## Major remaining gaps

This is a substantial numerical probability and Monte Carlo foundation, not a
state-of-the-art probabilistic programming system. Major gaps include
Dirichlet/Wishart and other multivariate families, singular/low-rank Gaussian
measures, sparse/BLAS/Tensor covariance backends, quasi-Monte Carlo, certified
extreme-tail/arbitrary-precision algorithms, adaptive NUTS and mass matrices,
advanced SMC/VI, generic random-variable graphs, measure-aware symbolic
probability, continuous-time transition solvers, vector/adaptive SDE methods,
Gaussian processes, random fields, and accelerator kernels.

Statistical estimation, regression, hypothesis testing, model comparison, and
fitted-distribution APIs remain deliberately in the Statistics domain.
