# Fused pipeline benchmark — results

Workload: `Σ x² for even x in (1+r .. N+r)` accumulated over `REPS`
passes (the per-rep range is shifted by `r` so the work can't be hoisted
as loop-invariant). Defaults `N=1_000_000`, `REPS=100` → the pipeline
runs 100 times. All implementations print the same exact value
`16669166833300000000`.

Each language uses its idiomatic pipeline spelling:

| Lang     | Spelling                                            | Shape                  |
|----------|-----------------------------------------------------|------------------------|
| Tungsten | `(lo..hi)/select(:even?)/sq:sum`                    | fused → **closed form**|
| Ruby     | `(lo..hi).select(&:even?).map { x*x }.sum`          | eager, 2 intermediate arrays |
| Python   | `sum(x*x for x in range(...) if x%2==0)`            | genexpr, lazy + fused  |
| C / Go   | hand-written loop                                   | native baseline        |

## Numbers (Apple M-series, best-of-5 warm, perf_counter)

| Implementation            | best (s) | vs Tungsten |
|---------------------------|---------:|------------:|
| C (clang, closed-form)    |   0.0015 |  1.6× faster |
| **Tungsten (closed-form)**|   0.0024 |   1.0×       |
| Python (genexpr)          |   2.09   |   861× slower|
| Ruby --yjit               |   4.01   |  1655× slower|

## Why Tungsten is in clang's league

The pipeline `range / [sq|cube] / [select(:even?|:odd?)] : sum` has an
O(1) closed form (Faulhaber's formula). Tungsten's pipeline lowering
recognizes the pattern and emits a single `w_range_pow_sum(lo, hi,
power, parity)` call — Σxⁿ over an arithmetic subsequence, computed in
`__int128` and returned exactly (BigInt-promoting, matching the loop's
`w_add`). No loop is emitted at all:

```
$ echo '<< (1..1000000000)/sq:sum' | tungsten -      # billion elements
333333333833333333500000000                          # 0.00s — one O(1) call
```

clang gets the same win on the C version via scalar-evolution + loop
idiom recognition (it solves the polynomial sum analytically). The
interpreters can't — they execute every element.

## Notes / caveats

- The C/Tungsten "closed-form" times are essentially `REPS` O(1) calls
  plus process startup; they measure the recognition, not per-element
  throughput.
- When the closed form does NOT apply (array sources, `sqrt`/`abs`/
  method-call maps, `product`/`min`/`max` over non-trivial chains), the
  pipeline falls back to ONE fused loop — still zero intermediate
  arrays, but O(n). Tightening that loop to raw-int arithmetic (it
  currently NaN-boxes each element and calls `w_mul`/`w_add`) is a
  separate follow-up.
- Go and Crystal sources are included for machines that have those
  toolchains; not run in the table above (not installed on this host).

Reproduce:

```
clang -O3 -march=native -flto pipeline.c -o /tmp/c && /tmp/c
tungsten compile --release pipeline.w -o /tmp/w && /tmp/w
ruby --yjit pipeline.rb
python3 pipeline.py
```
