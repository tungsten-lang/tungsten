# Fixed-width bit-count benchmark

`count_ones.w` compares `BitOps.count_ones_u32/u64` with the allocation-free
Kernighan loop previously duplicated by exact-search applications. The
current native compiler lowers the `BitOps` methods directly to
`llvm.ctpop.i32/i64`; interpreter and C-VM paths provide exact fallbacks.

Build once:

```sh
bin/tungsten -o /tmp/tungsten-count-ones-bench benchmarks/bit_ops/count_ones.w
```

Run one matched pair:

```sh
/tmp/tungsten-count-ones-bench u32 mixed bitops 10000000
/tmp/tungsten-count-ones-bench u32 mixed kernighan 10000000
```

Arguments are width (`u32` or `u64`), population (`sparse`, `mixed`, or
`dense`), implementation, and iteration count. `sparse` contains one bit;
`dense` contains all but one bit. Every result includes a checksum so paired
runs also check semantic agreement.

## 2026-07-29 intrinsic results

Seven alternating Apple M4 pairs over one billion mixed words compared the
frozen SWAR source with the explicit intrinsic source:

| width | SWAR median | intrinsic median | throughput |
|---|---:|---:|---:|
| u32 | 1.169986 s | 1.055936 s | **1.108x** |
| u64 | 1.034897 s | 1.033040 s | 1.002x |

The benchmark-source SHA-256 was
`976f062661c502cfa40fd0551fcfcb11aaa9dbd62d9d53b04451d6da8e1c650c`.
The optimized `tungsten-flame` run placed 99.7% of branch events in the
inlined main loop, with no runtime-helper or dynamic-dispatch hotspot; its SVG
is `/tmp/bit-count-intrinsic-final.svg` (SHA-256
`dbcb9ee03e0f814e8f741814633a72a27c242e58ff033bcba36be8bc15dc462e`).
An earlier 21-pair assembly-model comparison measured the zero-defined u32
trailing-zero intrinsic 6.23% faster than the sentinel construction. The u64
form was already recognized as the optimal `rbit; clz` pair.

## 2026-07-26 historical SWAR results

Before explicit intrinsic lowering, five compiled 10,000,000-word runs per
cell compared the fixed-stage SWAR implementation with Kernighan; values are
median nanoseconds per word.

| width / population | SWAR | Kernighan | speedup |
|---|---:|---:|---:|
| u32 / one bit | 6.733 | 6.898 | 1.02x |
| u32 / mixed | 6.685 | 18.068 | 2.70x |
| u32 / all but one bit | 6.626 | 14.491 | 2.19x |
| u64 / one bit | 5.565 | 10.998 | 1.98x |
| u64 / mixed | 5.773 | 16.259 | 2.82x |
| u64 / all but one bit | 5.578 | 11.076 | 1.99x |

Checksums matched within every pair. The new implementation is essentially
neutral on the u32 one-bit edge case and materially faster on mixed and dense
words.
