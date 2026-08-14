# W_TAG_ARRAY promotion (v5) — benchmark

Measured 2026-08-13 on the M-series dev machine, `--release` builds,
interleaved rounds, medians after warmup, startup baseline subtracted.
All checksums matched before/after. "Before" = arrays in object space
(subtag 0xA); "after" = arrays on the dedicated top-level tag 0xFFF4
(one-compare `w_is_array`, five-instruction guards collapsed to
`lshr 48; icmp eq 65524` in the emitter's inline fast paths).

## Workloads

- `dyn_ops.w` — boxed polymorphic arrays: literal construction, push,
  index, size, include?, each; values escape through a cell.
- `typed_inline.w` — `## i64[]` element access through the emitter's
  inline mask+load sequences (read-modify-write + xor accumulate).
- `dispatch.w` — IC-dispatch-heavy method calls on dynamically-typed
  array receivers (first/last/size/sum/empty?).

## Results

| workload      | before/after | verdict            |
|---------------|--------------|--------------------|
| dyn_ops       | 1.005x       | parity             |
| typed_inline  | 1.004x       | parity             |
| dispatch      | 1.018x       | slight win         |

The move itself is representation-neutral on throughput (guards were
rarely the bottleneck; allocation and IC machinery dominate). Its value
is the reclaimed encoding space: bit 47 + the low nibble of every array
value are now reserved flag bits (arena-vs-heap, small-vs-full
candidates), subtag 0xA is freed (dispatch-key-only, like BigInt's
0x02), and every inline array guard is 4 instructions shorter.

Run with `python3` + the runner in the scratchpad (see bench_runner.py
pattern in ../range_imm/).
