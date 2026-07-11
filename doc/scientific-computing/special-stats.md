# Special functions & stats — naming

## Why `core/sci/special` not stuffed into `math`?

| Name | Verdict |
|------|---------|
| `core/math` | Elementary only (exp/log/sin). Keep thin. |
| **`core/sci/special`** | denser catalogue (erf, gamma, Bessel) |
| **`core/sci/stats`** | distributions |
| Whole package | `core/sci/*` is the science stack — not a junk drawer if each file is one concern |

## Special (`core/special.w`)

erf, erfc, gamma, lgamma, beta, j0/j1, logistic, softplus, gammainc, factorial.

## Stats (`core/stats.w`)

mean/variance/std/median/percentile, Pearson r,
Normal / Uniform / Exponential / Poisson / Student-t / Gamma / Bernoulli /
Binomial PDFs (and some CDFs), mulberry32 RNG with Box–Muller normals.
