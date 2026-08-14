# Immediate Range (Location mode 11) — producer benchmark

Measured 2026-08-13 on the M-series dev machine, `--release` builds
(`-O3` + LTO), interleaved rounds, medians of 10 timed runs after one
warmup, process-startup baseline (null program, ~3 ms) subtracted.
Every binary prints a checksum; all before/after pairs matched.

"Before" binaries were built at the pre-campaign tree (escaped `lo..hi`
lowered to an eagerly materialized Array via an IR push loop); "after"
binaries are the SAME `.w` sources on the producer-era compiler
(`lower_range` → `w_range_make` → packed Location-mode-11 Range,
eager-Array fallback only for non-encodable bounds).

## Workloads

- `arr.w` / `arr4k.w` — escaped-range workload: `lo..hi` stored through
  an array cell and reloaded (defeats fusion and range-elision #49), then
  `first/last/size/include?/sum` per iteration. 2,000,000 iterations at
  len 64; 40,000 at len 4096.
- `imm.w` / `imm4k.w` — same loop but constructing through the raw
  runtime funnel (`ccall w_range_imm_try_w`) with computed untyped
  locals; doubles as the regression proof that plain-ccall args stay
  boxed (the analysis.w pin + assign.w bypass gate).
- `fused.w` — `(1..150M).each` accumulate: the fused-pipeline path,
  which the campaign must not disturb.

## Results

| pair                          | ratio  | meaning                        |
|-------------------------------|--------|--------------------------------|
| arr before/after (len 64)     | 12.9x  | end-to-end producer win        |
| arr4k before/after (len 4096) | ~590x  | O(len) → O(1) cliff            |
| fused before/after            | 0.98x  | parity — fusion untouched      |
| imm_after vs arr_after        | ≈equal | ccall funnel ≡ literal path    |

Raw medians (workload-only): arr 1.046 s → 0.081 s; arr4k 1.117 s →
0.0019 s (near noise floor — treat ~590x as "orders of magnitude");
fused ~15 ms both sides.

Run with: `python3 bench_runner.py <dir-with-binaries>` after building
each `.w` with `bin/tungsten -o <bin> --release`.
