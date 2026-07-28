# Polynomial degree sweep (`polysum.*`)

A benchmark that stresses the closed form across multi-term polynomials of
varying degree. For each P the program sums P over the range
`(1+r .. N+r)`, accumulated across `REPS` rep-shifted passes:

| degree | polynomial                       |
|-------:|----------------------------------|
| 1      | `2x + 3`                         |
| 2      | `5x² − 3x + 1`                   |
| 3      | `4x³ − 2x² + 7x − 5`             |
| 7      | `92x⁷ + 13x³ − 5x + 8`           |
| 20     | `x²⁰ + 17x¹³ − 4x⁵ + 2x + 9`     |

Mixed signs, constant terms, and several powers per polynomial — so the
fold is a genuine linear combination `Σ_k cₖ·Σxᵏ`, not a single power.
The Tungsten spelling is `(range)/Σ(5x² - 3x + 1)` — `Σ(expr)` is sugar
for `map(x -> expr):sum`, with implicit multiplication (`2x` = 2·x for the
bound variable) and superscript exponents (`x⁷` = x**7). Tungsten analyses
each polynomial's AST into coefficients and folds the ranged sum to that
closed form — O(degree²), **independent of N**, result auto-promoted to
BigInt.

## Two axes at once: speed AND correctness

- **Tungsten** — closed form, BigInt-exact, any degree. O(1) in N. Exact for
  bounds up to the i64 range: verified against independent
  arbitrary-precision references at N = 10⁹, 10¹², 10¹⁵, 10¹⁶ and 4×10¹⁸ (the
  last returning 390-digit values in 0.003 s). Bounds past 2⁴⁸ used to wrap
  silently — see `spec/compiler/poly_ranged_sum_big_bounds_spec.w`, which
  straddles that boundary.
- **Python / Ruby** — arbitrary-precision, so *correct*, but must iterate:
  O(N·REPS) per degree.
- **C / Go / Zig / Odin** — fixed 64-bit: *fast loop but wrong*. A degree-2
  sum over 1e6×100 already exceeds 2⁶⁴; `x⁷`/`x²⁰` overflow at once.
  Their printed values are mod 2⁶⁴ — they cannot represent the answer at
  all. `polysum.c` exists only as a native-loop speed reference.
  `bin/bench` knows this: it verifies the fixed-64 languages as their own
  group (they must agree with each other mod 2⁶⁴) instead of comparing
  them against Tungsten's exact values.

## Numbers (Apple M-series)

| N        | REPS | Tungsten (closed-form) | C (loop, **overflows**) | Python (BigInt loop) |
|---------:|-----:|-----------------------:|------------------------:|---------------------:|
| 100 000  |  10  | 0.13 s (startup)       | 0.11 s                  | 0.42 s               |
| 1 000 000|  10  | 0.00 s                 | ~0.1 s                  | 8.54 s               |
| **10⁹**  | 100  | **0.00 s**             | ~hours (and wrong)      | ~hours               |

The headline: Tungsten's time is **flat** from N=10⁵ to N=10⁹ — the work
is `5 × REPS` O(1) calls either way. The loop languages scale with
`N·REPS` (≈10¹¹ evaluations at the bottom row) and the systems languages
are additionally incorrect.

Flatness holds for the **native binary**, not just the interpreter: the
compiled program runs 10⁹ × 100 in 0.17 s. It did not always — until the
range-materialization elision landed, `range = (lo..hi)` still built the
range as a real array (an O(N) push loop) even though every use of it was
folded to closed form, so the compiled binary took 114 s on that row while
the interpreter reported 0.00 s. Any future "the fold is firing" claim
should be checked against a compiled run at large N, not `bin/tungsten`.

At the suite's own size (`bin/bench polysum`, N=10⁸ REPS=10):

| Tungsten | Odin  | Zig   | Rust  | C     | Go     |
|---------:|------:|------:|------:|------:|-------:|
| 0.005 s  | 1.35 s| 1.39 s| 1.42 s| 2.67 s| 17.5 s |

## Reproduce

```
tungsten compile --release polysum.w -o /tmp/p && /tmp/p 1000000 100
python3 polysum.py 1000000 100        # correct, slow
clang -O3 polysum.c -o /tmp/pc && /tmp/pc   # fast, OVERFLOWS (wrong)
```

Or through the suite: `bin/bench polysum`.
