# Statistics

`use statistics` loads a focused numerical foundation for estimation and
linear-model research. It is substantially more than a convenience collection,
but it is not a claim to implement all modern statistics. The current tranche
provides compensated and mergeable descriptive estimators, explicit weighted
and multivariate moments, and rank-revealing ordinary/weighted least squares
with classical and heteroskedasticity-consistent inference. A second focused
layer adds deterministic foundations from recent research: robust scalar mean
estimation, cheap-subsampling interval postprocessing, conformal ranks and
half-mass scores, bounded scalar confidence sequences, and finite-candidate
relative-fit inversion. These additions expose their assumptions and do not
claim to implement the full scope of the source papers.

The public facade remains `Statistics`. Implementation is divided by ownership:

```text
core/statistics.w                         public facade and shared validation
core/statistics/univariate.w              scalar moments
core/statistics/bivariate.w               paired moments
core/statistics/estimation/weighted.w     scalar weighted estimation
core/statistics/estimation/multivariate.w weighted vector estimation
core/statistics/robust/location/
  all_purpose_mean.w                      robust scalar point estimation
core/statistics/inference/student_t.w     internal inferential tail integration
core/statistics/inference/conformal/
  rank.w                                  exact conformal rank calibration
  half_mass.w                             half-mass candidate scoring
core/statistics/inference/relative_fit/
  bounded_kl.w                            bounded finite-candidate KL inversion
core/statistics/resampling/
  cheap_subsampling.w                     deterministic interval postprocessing
core/statistics/sequential/
  empirical_bernstein.w                   bounded scalar confidence sequence
core/statistics/regression/solver.w       column-pivoted Householder QR
core/statistics/regression/diagnostics.w  immutable diagnostics
core/statistics/regression/linear_model.w OLS/WLS results and inference
```

Statistics owns estimation, inference, regression, diagnostics, resampling,
and robust or multivariate methods. Probability remains the proper owner of
distributions, random sampling, and stochastic processes. The internal
Student-t tail helper consumes `Special.betainc` for model inference; it is not
a public distribution or sampling API.

## Descriptive and streaming estimation

```tungsten
use statistics

summary = Statistics.summarize([1, 2, 3, 4, 5])
<< summary.mean                    # 3.0
<< summary.sample_variance         # 2.5
<< summary.population_variance     # 2.0
<< Statistics.quantile([1, 2, 3, 4], ~0.25) # 1.75

estimate = summary.mean_measurement
<< estimate                        # 3.0 ± 0.707...
```

| Entry point | Meaning |
|---|---|
| `sum(values)` | Neumaier compensated floating-point sum |
| `mean(values)` / `summarize(values)` | compensated mean and one-pass `StatisticsSummary` |
| `variance(values, correction=1)` | central moment divided by `n - correction` |
| `population_variance` / `sample_variance` | explicit correction 0 / 1 forms |
| `standard_deviation(values, correction=1)` | square root of the corresponding variance |
| `standard_error(values)` | sample standard deviation divided by `sqrt(n)` |
| `quantile(values, p)` / `median(values)` | Hyndman--Fan type 7 quantiles |
| `covariance(xs, ys, correction=1)` | stable paired co-moment divided by `n - correction` |
| `correlation(xs, ys)` | Pearson product-moment correlation |
| `mean_measurement(values)` | sample mean and IID standard error as a `Measurement` |

`StatisticsAccumulator` and `StatisticsBivariateAccumulator` accept `push`,
combine independent partitions with `merge`, and return snapshots. They use
Welford/Chan moment updates; the scalar sum is additionally compensated.

## Weighted estimation

```tungsten
weighted = Statistics.weighted_summarize(
  [~1.0, ~2.0, ~5.0], [~1.0, ~2.0, ~1.0])

<< weighted.mean                    # 2.5
<< weighted.population_variance     # 2.25
<< weighted.reliability_variance    # 3.6
<< weighted.frequency_variance      # 3.0
<< weighted.effective_sample_size   # 2.666...
```

The weighting convention is never guessed:

- population variance divides the weighted central moment by `sum(w)`;
- reliability variance uses the unbiased denominator
  `sum(w) - sum(w*w)/sum(w)`;
- frequency variance requires every weight to be an exact nonnegative integer
  and divides by `sum(w) - 1`;
- effective sample size is `(sum(w)^2)/sum(w*w)`, evaluated as
  `sum(w)/(sum(w*w)/sum(w))` to avoid an avoidable square overflow.

`StatisticsWeightedAccumulator` is mergeable. `count` includes every supplied
row, while `positive_weight_count` reports rows that influence the estimate.
A zero-weight row is still validated, then contributes no moment. Negative,
non-finite, or all-zero weights fail explicitly.

## Multivariate moments

`Statistics.multivariate_summarize(rows, weights=nil)` returns a
`StatisticsMultivariateSummary` with a mean vector, scatter matrix, population,
reliability, and integer-frequency covariance matrices, effective sample size,
and a correlation matrix. The corresponding accumulator is streaming and
mergeable:

```tungsten
accumulator = Statistics.multivariate_accumulator(2)
accumulator.push([~1.0, ~2.0], ~1.0)
accumulator.push([~2.0, ~4.0], ~2.0)
summary = accumulator.snapshot
```

Rows must have the declared dimension and contain finite real scalars.
Correlation raises when any dimension has zero variance. Returned vectors and
matrices are defensive copies so downstream mutation cannot alter an estimate.
This is dense covariance estimation; it does not regularize a singular sample
covariance or silently impute missing data.

## Linear models and inference

```tungsten
x = [[~0.0], [~1.0], [~2.0], [~3.0], [~4.0]]
y = [~1.0, ~3.0, ~5.0, ~7.0, ~10.0]

model = Statistics.linear_regression(x, y)
<< model.coefficients               # approximately [0.8, 2.2]
<< model.standard_errors            # classical covariance
<< model.p_values
<< model.confidence_intervals(~0.95)
<< model.covariance(:hc3)
<< model.diagnostics.leverage
<< model.diagnostics.cooks_distance
```

The full call is
`linear_regression(predictors, response, intercept=true, weights=nil,
tolerance=1e-12)`. It implements OLS or analytic-weight WLS. WLS weights are
relative precision weights, not replicated-frequency counts. Zero-weight rows
remain in fitted and residual output but do not affect the fit or residual
degrees of freedom.

The fit uses column-pivoted Householder QR. It does not form normal equations to
estimate coefficients. Rank is checked against a scale-aware tolerance before
the triangular solve; rank-deficient, underdetermined, and ill-conditioned
designs raise instead of returning arbitrary coefficients. The reported
`condition_estimate` is the ratio of the largest to smallest `abs(diag(R))`
after pivoting. It is a useful deterministic diagnostic, not an exact SVD
2-norm condition number.

`StatisticsLinearModelResult` reports coefficients, fitted values, residuals,
rank, residual degrees of freedom, weighted RSS, residual variance, R-squared,
adjusted R-squared, status, covariance products, and inference. Its associated
`StatisticsRegressionDiagnostics` reports QR permutation, leverage,
standardized weighted residuals, Cook's distance, condition estimate, WLS
status, and warnings. Returned collections are defensive copies.

Covariance choices are explicit:

| Kind | Interpretation |
|---|---|
| `:classical` | `sigma^2 (X'WX)^-1`; homoskedastic after WLS scaling |
| `:hc0` | uncorrected Eicker--Huber--White sandwich |
| `:hc1` | HC0 multiplied by `n/(n-p)` |
| `:hc2` | residual squares divided by `1-h` |
| `:hc3` | residual squares divided by `(1-h)^2` |

HC covariance protects coefficient covariance against unspecified
heteroskedasticity; it is not a robust coefficient estimator and it does not
protect the fit from high-leverage contamination. P-values and intervals use
two-sided Student-t tails with residual degrees of freedom for every covariance
choice. HC inference is therefore a documented finite-sample convention, not
an asymptotic coverage certificate.

Perfect or numerically exact fits remain successful result objects with
warnings, but standard errors, t statistics, p-values, and confidence intervals
raise because residual scale is zero. HC2 and HC3 are unavailable if a
positive-weight row has leverage numerically equal to one. A constant response
returns `nil` for R-squared and adjusted R-squared with a warning.

## Paper-derived deterministic foundations

These methods are intentionally narrow implementations of the mathematical
cores in the linked primary sources. Every result distinguishes mechanically
checked input conditions from theoretical assumptions that cannot be verified
from one sample.

### Exact order statistics

`Statistics.order_statistic(values, rank)` returns the one-based exact order
statistic after sorting a finite copy. It does not interpolate. Conformal ranks
and nearest-neighbor scores must not use the facade's type-7 `quantile`, whose
interpolation has different semantics.

### All-purpose robust scalar mean

```tungsten
result = Statistics.all_purpose_mean(values, ~0.05)
<< result.estimate
<< result.initial_estimate
<< result.scaled_influence_parameter
<< result.equation_residual
<< result.assumptions
```

This implements the scalar estimator analyzed by Lee, Mckelvie, Song, and
Valiant. With preliminary estimate `kappa`, it solves

```text
sum(min(alpha * (x - kappa)^2, 1)) = log(1 / delta) / 3
```

and clips each centered contribution by the resulting influence weight. The
implementation uses balanced contiguous median-of-means groups and solves a
scale-normalized equation, avoiding a raw square of very large observations.
`influence_parameter` is `nil` if the unscaled alpha is outside binary64's
representable range; `scaled_influence_parameter` remains meaningful.

The method returns a `StatisticsRobustMeanResult`, not a confidence interval.
Its finite-variance sub-Gaussian, strong-contamination, low-moment, neighborhood,
and asymptotic-efficiency claims require the paper's IID and initializer
conditions. In particular, input ordering must be independent of values.
Nonconvergence, insufficient rows for `ceil(log(1/delta))` groups, or a root
outside the finite representable range raises explicitly.

Primary source: [Lee et al., ICML 2025](https://proceedings.mlr.press/v267/lee25w.html).

### Cheap subsampling intervals

```tungsten
interval = Statistics.cheap_subsampling_interval(
  full_estimate,
  estimates_from_subsamples,
  n,
  m,
  ~0.95,
  :asymptotically_linear_iid)

planned = Statistics.cheap_subsampling_from_indices(
  values,
  estimator,
  explicit_subset_indices,
  ~0.95,
  :asymptotically_linear_iid)
```

For `B` supplied scalar estimates from independent size-`m` subsets drawn
without replacement, this computes

```text
S^2 = (1 / B) * sum((subsample_estimate - full_estimate)^2)
standard_error = sqrt(m / (n - m)) * S
interval = full_estimate +/- t(B, level) * standard_error
```

`StatisticsCheapSubsamplingResult` records the finite-population scale,
Student-t critical value, degrees of freedom `B`, endpoints, warnings, and
assumptions. `S == 0` returns status `:degenerate` and does not support a nominal
coverage claim. `B < 25` is a practical variability warning, not a theorem
threshold.

`cheap_subsampling_from_indices` validates equal nonempty subset sizes, integer
range, and no duplicate index within a subset, then evaluates the supplied
estimator on each subset and the full sample. Repeated subsets across
replications are permitted. This makes deterministic plans replayable and
testable without moving subset generation into Statistics.

The acknowledgement symbol is mandatory because the method's coverage theorem
requires an IID, asymptotically linear scalar estimator and an asymptotic
subsample regime. Statistics does not generate subsets. Probability remains
the owner of replayable RNG streams and uniform sampling without replacement.
“Robust” in the paper's title concerns operational bootstrap behavior, not
contamination resistance.

Primary source: [Ohlendorff et al., arXiv:2501.10289v3](https://arxiv.org/abs/2501.10289).

### Conformal rank and half-mass geometry

```tungsten
rank = Statistics.conformal_rank(
  calibration_scores, candidate_score, ~0.05)

candidate = Statistics.conformal_half_mass_candidate(
  sample_rows, candidate_row, ~0.05)
```

`conformal_rank` uses the exact conservative p-value

```text
(1 + count(calibration_score >= candidate_score)) / (n + 1)
```

and includes a candidate only when `p > miscoverage`. Only
`:conservative` ties are supported. Randomized ties would require an explicit
Probability-owned RNG.

The half-mass method applies that rank to augmented leave-one-out scores. For a
bag of size `n`, each score is the distance to the
`floor(n / 2) + 1` nearest neighbor, exactly the minimum radius containing a
strict majority. `StatisticsHalfMassConformalResult` reports every score,
candidate score, dimension, rank, p-value, and warnings.

Under exchangeability this is a finite-sample **marginal** guarantee for the
next row. It is not generic conditional coverage. The implementation is a
quadratic reference candidate scorer using Euclidean geometry; it is not a
scalable continuous-region constructor, and coordinate scaling remains the
caller's responsibility.

Primary source: [Cholaquidis, Joly, and Moreno, arXiv:2604.18441](https://arxiv.org/abs/2604.18441).

### Closed-form empirical-Bernstein confidence sequences

```tungsten
sequence = Statistics.empirical_bernstein_sequence(
  ~0.05, ~0.0, ~1.0, ~0.25)

stream.each -> (value)
  sequence.push(value)
  current = sequence.snapshot
  << current.interval
```

`StatisticsEmpiricalBernsteinSequence` accepts observations in a fixed known
finite support, rescales to `[0, 1]`, and uses the predictable estimate

```text
(0.5 + sum(previous observations)) / t
```

with `psi(u) = -log1p(-u) - u`. It evaluates the paper's hitting condition in
the log domain. Before the proved closed form becomes active, snapshots return
the complete known support with status `:warming_up`. Afterward they return a
`StatisticsConfidenceSequenceResult` with status `:active`, center, raw
half-width, small outward numerical guard, support intersection, variance
process, predictor, and `active_from` time.

The simultaneous target is the **historical average conditional mean** of a
bounded adapted stream. It is not the current instantaneous mean after drift.
`kappa` and support are fixed at construction, and the state is order-dependent
and deliberately not mergeable. Binary64 evaluation is not a formal coverage
certificate. The matrix theorem is not implemented because Core lacks the
required stable symmetric spectral functional calculus.

Primary source: [Chugg and Ramdas, arXiv:2512.21300v1](https://arxiv.org/abs/2512.21300).

### Bounded KL relative-fit inversion

```tungsten
result = Statistics.bounded_kl_relative_fit(
  log_ratio_scores_by_candidate,
  theoretical_score_bound,
  ~0.05,
  :iid_bounded_log_ratio)
```

Each row contains held-out
`log(pilot_density / candidate_density)` scores for one candidate. The pilot
must have been fit on an independent split. Given the paper's theoretical
centered-score bound `B`, the method accepts candidates whose mean score is at
most

```text
B * sqrt(log(1 / miscoverage) / (2 * holdout_size))
```

`StatisticsRelativeFitResult` reports accepted candidate indices, all mean
scores, threshold, holdout/candidate counts, target `:kl`, scope
`:finite_candidate_family`, and coverage kind `:finite_sample_bounded_score`.
Observed score minima/maxima are not substitutes for the required theoretical
bound. The acknowledgement is mandatory; split independence and the bound are
not mechanically verified.

This deterministic inversion avoids premature Probability coupling. Probability
should eventually own models and normalized log-density protocols. Studentized,
Gaussian-corrupted, Hellinger, density-power, continuous-parameter, and
approximate-projection variants are not included.

Primary source: [Park, Balakrishnan, and Wasserman, *Biometrika* 2025](https://doi.org/10.1093/biomet/asaf070).

## Shared assumptions and failures

- Observations, predictors, responses, and weights must be finite built-in real
  numeric scalars. Computation is ordinary floating point, not exact or
  certified.
- `nil`, strings, complex values, quantities, and `Measurement` observations
  are rejected. Extracting `Measurement#value` implicitly would discard
  uncertainty and correlation.
- Missing-data omission is deliberately absent. Filtering must be explicit so
  research code cannot silently change its effective sample.
- Empty means and quantiles raise. Sample variance requires at least two rows.
  Paired operations require equal lengths. Pearson correlation raises on zero
  variation.
- Quantiles materialize and sort a copy in `O(n log n)` time. Streaming
  quantile sketches are not part of this tranche.
- Regression requires more positive-weight observations than fitted
  parameters. The implementation is dense and intended for low-to-moderate
  parameter counts where explicit diagnostics are useful.
- A fit whose RSS is below `tolerance^2 * (1 + sum(w*y*y))` is classified as
  numerically exact. This prevents QR roundoff from manufacturing inferential
  scale, and means the supplied tolerance is part of the fit contract.

`mean_measurement` uses the existing `Measurement` primitive. Its uncertainty
is the estimated standard error under IID finite-variance sampling. It is not
instrument-error propagation, a confidence interval, or a coverage guarantee.

## Scope and next layers

This tranche enables reproducible weighted/covariance pipelines, diagnosed
dense linear models, a modern scalar robust point estimator, deterministic
subsampling inference postprocessing, exact conformal ranks, bounded scalar
sequential inference, and finite-grid bounded relative-fit inversion in both
interpreted and native Tungsten. It does not yet supply robust scale/covariance
or M-regression, RNG-backed bootstrap/permutation orchestration, clustered or
HAC covariance, generalized or nonlinear models, mixed effects,
high-dimensional or `p >= n` methods, sparse/penalized estimation, Bayesian
computation, survival/time-series methods, or domain-specific designs.
SVD-backed near-rank-deficient analysis, matrix confidence sequences, scalable
continuous conformal geometry, and density/integration-backed robust universal
inference are also future work.

Those are coherent future submodules under `core/statistics/`; distributions,
sampling algorithms, and stochastic-process primitives should instead enter
through a stable Probability module. The older `Stats` module remains available
for its compatibility PDFs/CDFs and reproducible RNG and is not silently
changed by `Statistics`.
