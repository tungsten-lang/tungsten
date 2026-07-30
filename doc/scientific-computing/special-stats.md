# Special functions & stats — naming

## Why `core/special` is not stuffed into `math`

| Name | Verdict |
|------|---------|
| `core/math` | Elementary only (exp/log/sin). Keep thin. |
| **`core/special`** | denser catalogue (erf, gamma, Bessel) |
| **`core/stats`** | distributions |
| Whole package | The science stack stays separated by mathematical concern. |

## Special (`core/special.w`)

erf, erfc, gamma, lgamma, beta, j0/j1, logistic, softplus, gammainc, factorial.
`erf` and `erfc` use complementary incomplete-gamma algorithms so both central
values and small tails retain near-machine precision. `use calculus` also
exposes them as `Expression#erf` and `Expression#erfc`.

## Stats (`core/stats.w`)

mean/variance/std/median/percentile, Pearson r,
Normal / Uniform / Exponential / Poisson / Student-t / Gamma / Bernoulli /
Binomial PDFs (and some CDFs), mulberry32 RNG with Box–Muller normals.
