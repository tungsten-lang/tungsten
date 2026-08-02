# Statistics

`use statistics` loads a focused numerical foundation for estimation and
linear-model research. It is substantially more than a convenience collection,
but it is not a claim to implement all modern statistics. The current tranche
provides compensated and mergeable descriptive estimators, explicit weighted
and multivariate moments, and rank-revealing ordinary/weighted least squares
with classical and heteroskedasticity-consistent inference.

The public facade remains `Statistics`. Implementation is divided by ownership:

```text
core/statistics.w                         public facade and shared validation
core/statistics/univariate.w              scalar moments
core/statistics/bivariate.w               paired moments
core/statistics/estimation/weighted.w     scalar weighted estimation
core/statistics/estimation/multivariate.w weighted vector estimation
core/statistics/inference/student_t.w     internal inferential tail integration
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

This tranche enables reproducible weighted/covariance pipelines and diagnosed
dense linear-model inference in both interpreted and native Tungsten. It does
not yet supply standalone robust location/scale or M-estimation, bootstrap and
permutation resampling, clustered or HAC covariance, generalized or nonlinear
models, mixed effects, high-dimensional or `p >= n` methods, sparse/penalized
estimation, Bayesian computation, survival/time-series methods, or
domain-specific designs. SVD-backed near-rank-deficient analysis and stronger
condition estimation are also future work.

Those are coherent future submodules under `core/statistics/`; distributions,
sampling algorithms, and stochastic-process primitives should instead enter
through a stable Probability module. The older `Stats` module remains available
for its compatibility PDFs/CDFs and reproducible RNG and is not silently
changed by `Statistics`.
