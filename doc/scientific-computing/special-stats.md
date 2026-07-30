# Special functions & stats — naming

## Why `core/special` is not stuffed into `math`

| Name | Verdict |
|------|---------|
| `core/math` | Elementary only (exp/log/sin). Keep thin. |
| **`core/special`** | denser catalogue (erf, gamma, Bessel) |
| **`core/stats`** | distributions |
| Whole package | The science stack stays separated by mathematical concern. |

## Special (`core/special.w`)

erf, erfc, gamma, lgamma, digamma, trigamma, arbitrary integral-order
polygamma, integer zeta, beta, j0/j1, logistic, softplus, gammainc, factorial.
`erf` and `erfc` use complementary incomplete-gamma algorithms so both central
values and small tails retain near-machine precision. `use calculus` also
exposes them as `Expression#erf` and `Expression#erfc`.

The gamma/polygamma numeric path uses recurrence plus a differentiated
Bernoulli asymptotic expansion on positive real arguments. Symbolic
`Expression#gamma`, `#log_gamma`, `#digamma`, `#trigamma`, and `#polygamma`
add exact integer and half-integer values, exact derivatives and affine
antiderivatives, formal Taylor series, arbitrary-order jets, and Hessians.
`Expression.zeta(n)` keeps odd values named and reduces common even values to
powers of π.

## Stats (`core/stats.w`)

mean/variance/std/median/percentile, Pearson r,
Normal / Uniform / Exponential / Poisson / Student-t / Gamma / Bernoulli /
Binomial PDFs (and some CDFs), mulberry32 RNG with Box–Muller normals.
