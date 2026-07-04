# NEON `shrn`/`xtn` Tail Compression on Apple Silicon — Don't Do It

The runtime's NEON scan helpers (`runtime/runtime.c`, `w_lex16_scan_*` /
`w_lex32_scan_*`) end each iteration with a comparison vector whose lanes are
either `0` (no stop) or `-1` (stop here). The classic simdjson-style trick to
find the first stop lane is to **compress** the comparison vector to a packed
bitmap, then use `__builtin_ctz` to find the first set bit:

```c
/* The simdjson trick — wins big on Intel/AMD, LOSES on Apple Silicon. */
uint16x4_t narrowed = vshrn_n_u32(vreinterpretq_u32_s32(cmp), 4);
uint64_t bitmap = vget_lane_u64(vreinterpret_u64_u16(narrowed), 0);
if (bitmap) return pos + (__builtin_ctzll(bitmap) >> 4);
```

On Intel/AMD this beats the alternative of multiple sequential lane extracts:
`pmovmskb` runs on a vector ALU port, the `tzcnt` runs on an integer port —
two different execution units, fully overlapping. **Measured ~3-5% win** on
similar workloads in published simdjson benchmarks.

## What we measured on Apple M3

We tried this exact rewrite on all 11 helpers in the JSON lexer hot path
(`languages/json/lexer32.w` chain). The scan_flag inner loop went from 7
instructions to 5, with one fewer NEON-side serial-latency cycle. Expected
result: small but real win.

**Actual result: ~28% throughput regression.**

```
                                            single-thread
old (dup + orr + fmov + cbz, 7 insn)        1958 MB/s    ← winner
shrn + fmov + cbz + ctz + lsr (5 insn)      1330 MB/s    -32%
```

## Root cause

On Apple Silicon, **`xtn`/`shrn` and `fmov d→x` share the same execution
port**. Both are 1-per-cycle throughput on the "narrow + transfer" unit. The
old reduction pattern uses `dup.2d` (lane permute), `orr.16b` (general vec
ALU), and `fmov d→x` (transfer) — three different ports, only the `fmov` is
the bottleneck at 1/cycle. The new pattern stacks `xtn` and `fmov` on the
*same* scarce port → throughput halves.

| Pattern | Critical-path latency | Bottleneck throughput |
|---|---|---|
| `dup + orr + fmov` (old) | ~7 cycles | 1 fmov / cycle = **4 chars/cycle** |
| `xtn + fmov` (new) | ~6 cycles | 0.5 (xtn+fmov) / cycle = **2 chars/cycle** |

Latency went *down* by 1 cycle, but steady-state throughput halved — and the
inner loop is throughput-bound, not latency-bound, because the load latency
hides easily on sequential access.

## Can the port pressure be avoided?

**No.** Execution port assignment is the dispatcher's job, not the
programmer's. There's no NEON instruction that compresses a 4×i32 mask vector
to a small bitmap *and* dispatches to a different unit than the transfer port.
The alternatives all hit the same constraint:

- `vminvq_u32` / `vmaxvq_u32` (horizontal reduce): also goes through the
  transfer port, with 6-cycle latency — *worse* than the dup+orr+fmov pattern.
- `addv` / `addp` (pairwise adds): same port family, no win.
- `vqmovn_*` (saturating narrow): same port as `xtn`, same problem.

The only way to compress + branch on the result without touching the transfer
port is to skip compression entirely — keep the work in NEON registers and use
a vector-side branch hint. ARM doesn't have one. We already use the cleanest
alternative: reduce 128 → 64 with `dup + orr` (vector permute + general ALU,
both on plentiful ports), then *one* `fmov d→x` for the branch test. There's
no further reshuffling available.

## Lesson

simdjson-style bitmap-compress-and-ctz is **micro-architecture-specific**. It
wins on Intel/AMD because their port layout puts `pmovmskb` and `tzcnt` on
different execution units. On Apple Silicon, the equivalent `xtn`/`shrn`
instructions share a port with the NEON→GPR transfer, so the trick actively
backfires. **Always benchmark micro-optimizations on the actual target CPU.**

A related lesson: instruction-count reductions don't translate to throughput
gains when the new instructions consume already-saturated ports. The relevant
metric is **ops on the bottleneck port per iteration**, not total instructions.

## What we shipped instead

For the bound-check question (which was the original motivation for trying the
shrn rewrite), the working solution is to convert the NEON helper loops from
`while (pos + N <= length + LEX_SENTINEL_PAD)` to `for (;;)`. The data
sentinel pad (16 zero entries past every typed-array's live region) makes the
loop terminate via the data path on the first lane that crosses into the pad.
This guarantees no source-level bound check exists for LLVM to emit, regardless
of whether LLVM would have eliminated it on its own.

Net effect: ~+2.5% over the previous bounded variant, no port-pressure
regression, no UB risk from `__builtin_ctzll(0)`.
