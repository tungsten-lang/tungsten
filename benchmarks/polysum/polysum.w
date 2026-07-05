# Polynomial ranged-sum benchmark — multi-term polynomials, degree sweep.
#
# For each polynomial P (degrees 1, 2, 3, 7, 20 — multiple terms, mixed
# signs, constant terms), sum P over the range (1+r .. N+r), accumulated
# across REPS rep-shifted passes:
#
#   deg 1 :  2x + 3
#   deg 2 :  5x² − 3x + 1
#   deg 3 :  4x³ − 2x² + 7x − 5
#   deg 7 :  92x⁷ + 13x³ − 5x + 8
#   deg 20:  x²⁰ + 17x¹³ − 4x⁵ + 2x + 9
#
# `Σ(2x⁷ + 3x²)` is the math-notation spelling — implicit multiplication
# (`2x` = 2·x for the bound variable x) and superscript exponents (`x⁷` =
# x**7), sugar for `map(x -> 2*x**7 + 3*x**2):sum`. Tungsten analyses each
# polynomial's AST into coefficients and folds the whole ranged sum to a
# CLOSED FORM — Σ_k cₖ·Σxᵏ via Faulhaber — O(degree²), INDEPENDENT of N,
# result auto-promoted to BigInt. No loop is emitted.
#
# Every other language must iterate (O(N·REPS) per polynomial); the
# systems languages additionally OVERFLOW their fixed 64-bit integers.
#
# N/REPS come from argv (defaults 1_000_000 / 100). The bin/bench suite
# passes a smaller size so the looping languages stay practical; pass e.g.
# `1000000000 100` for the headline closed-form-vs-loop contrast.

a = argv()
n = 1000000
reps = 100

if a.size >= 1
  n = a[0].to_i

if a.size >= 2
  reps = a[1].to_i

0: t1, t2, t3, t7, t20

reps -> (r)
  lo = 1 + r
  hi = n + r

  range = (lo..hi)

  t1  += range/Σ(2x + 3)
  t2  += range/Σ(5x² - 3x + 1)
  t3  += range/Σ(4x³ - 2x² + 7x - 5)
  t7  += range/Σ(92x⁷ + 13x³ - 5x + 8)
  t20 += range/Σ(x²⁰ + 17x¹³ - 4x⁵ + 2x + 9)

<< t1, t2, t3, t7, t20
