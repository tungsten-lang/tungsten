# Why we lose the rows we lose — diagnosis, 2026-07-27

Measured at `a6d8999` against CaDiCaL 3.0.1 with its own `--stats`, on the 16
rows wassat fails to solve inside budget plus the worst-ratio rows. The
conclusion is not what the standing report implied.

**It is not one gap. It is three, and only one of them is about reasoning.**

## The decisive split: trajectory vs throughput

For every bad row, compare conflict *count* (reasoning quality) against
conflicts *per second* (engineering). They point at opposite fixes, so measure
before theorising.

| row | wassat confl | CaDiCaL confl | wassat c/s | CaDiCaL c/s | conflicts ratio | rate ratio |
|---|---:|---:|---:|---:|---:|---:|
| `n320p5q2_n` | 25,490 | 33,604 | 809 | 75,824 | **0.8x** | 0.01x |
| `n384p5q2_vh` | 25,465 | 107,530 | 383 | 69,695 | **0.2x** | 0.01x |
| `DivS_568_11` | 26,418 | 21,020 | 171 | 9,397 | 1.3x | 0.02x |
| `minand064` | 94,504 | 13,548 | 21,427 | 32,835 | 7.0x | 0.65x |
| `Urquhart-s3-b3` | 2,622,079 | 139,586 | 53,954 | 306,433 | 18.8x | 0.18x |

On the first three wassat's **search is as good or better** — it needs fewer
conflicts and still loses by 43-71x. That is not a solver-reasoning problem.

## Gap 1 — the SLS burst is structurally dead on the raw path (the big one)

`wassat.w` runs a stochastic-local-search burst before the CDCL race, gated on
`art["clauses"].size > 2000 && <= 50000`. On the raw path `art` comes from
`wassat_raw_artifact`, which returns **`"clauses": []`** — it carries flat
arrays instead. So the gate reads 0, and the burst never fires.

`raw_kernel?` is true for `@nclauses > 5000` (non-ternary-dominated). **The raw
window and the burst window overlap**, so the burst is silently unreachable
across exactly the 5,000-50,000-clause band it was written for. The profile
confirms it: `c prof cli.sls_burst 0ms` on every raw run.

What that costs, measuring `wassat sls` directly against the shipped path:

| row | clauses | SLS | shipped | CaDiCaL | vs shipped | vs CaDiCaL |
|---|---:|---:|---:|---:|---:|---:|
| `n320p5q2_n` | 30,726 | **0.07s** | 25.06s | 0.43s | 371x | **6.4x faster** |
| `n384p5q2_vh` | 44,173 | **0.47s** | 58.67s | 1.71s | 124x | **3.6x faster** |
| `DivS_568_11` | 553,495 | **2.34s** | DNF@60s | 2.34s | 26x | tie |
| `DivS_862_11` | ~550k | **3.63s** | DNF@60s | 3.55s | 17x | tie |
| `ntil-90d-33` | 200,920 | **22.98s** | DNF@60s | 12.74s | 2.6x | 0.6x |

Five of the sixteen unsolved/worst rows, solved by a component already in the
tree. Two of them turn into wins **over CaDiCaL**.

Forcing the non-raw route (`WASSAT_RAW_AT=100000000`) on `n320p5q2_n` gives
`s SATISFIABLE` in **0.06s with 0 conflicts**, mode `fast (light+sls burst)`,
6,610 flips — a 545x swing, and proof this is a routing defect rather than a
missing technique.

**The fix is not to widen the window.** Two of those rows (553k and 201k
clauses) sit far outside it, and the window exists because a serial burst that
fails is pure wasted wall time. The design this file already believes in is the
race: preprocessing "is not a decision the coordinator makes and pays for up
front, it is a racer" (`wassat.w`). **Add an SLS arm to the raw race**, the same
shape as `wassat_race_add_pre`. Then a burst that fails costs one core rather
than the critical path, the clause-count window disappears entirely, and
`lib/sls.w` already supports the allocation-free, phase-seeded operation a
worker thread needs.

## Gap 2 — throughput on dense, few-variable formulas

`n320p5q2_n` is 320 variables / 30,726 clauses. `DivS_568_11` is 568 variables
/ 553,495 clauses — roughly 975 clauses per variable. wassat runs 171-809
conflicts/second on these against CaDiCaL's 9k-76k. Per-literal watch lists on
such formulas are enormous, and that is where the two orders of magnitude go.

Gap 1 hides most of this (SLS answers these rows outright), but it is a real
and separate weakness, and it would surface on a dense UNSAT instance where
local search cannot help.

## Gap 3 — genuine reasoning gap on XOR/parity kernels

tseitin/Urquhart is the only place where wassat needs *more search*: 18.8x the
conflicts on `Urquhart-s3-b3`, and DNF on the other two. CaDiCaL does it with
no Gaussian elimination at all (`substituted: 0`, 3 variables eliminated) —
just 139k conflicts at 306k conflicts/sec plus `shrunken 27.4%` and
`subsumed 68.9%`.

## Banked negative: All-UIP shrinking still does not transfer

CaDiCaL shrinks 20-76% of learned literals on nearly every row we lose
(`n320p5q` 74.8%, `n384p5q` 75.7%, `2bitadd_10` 46.2%, `Carry_Bits` 41.6%,
urquhart 29-31%), and wassat's pass is dormant. That looked like the obvious
answer, and the measurement that disabled it in 2026-07-24 used only php87,
bmc-ibm-12, ibm-10 and uuf250 — **every one a row wassat already wins**.

So it was re-measured on the losing rows, via a `WASSAT_SHRINK` hook, one
binary, chrono-free arms:

| row | conflicts, shrink off | shrink on |
|---|---:|---:|
| `n320p5q2_n` | 25,490 | 25,437 (unchanged) |
| `Urquhart-s3-b3` | 2,622,079 | **6,130,451** (2.3x worse) |

It removes essentially nothing and perturbs badly where it acts — the original
diagnosis holds on the rows it was never tested on. Do not re-enable it.

**Second-order finding worth its own item:** shrinking is additionally gated
`@use_shrink && !@use_chrono`, so it is structurally excluded from every
chronological-backtracking arm, because wassat does not track the per-variable
trail positions CaDiCaL uses to shrink under chrono. CaDiCaL runs chrono on
10-49% of conflicts *and* shrinks. In wassat the two techniques are mutually
exclusive; in CaDiCaL they compose.

## Ranked work list

1. **Make the SLS burst reachable on the raw path, as a race arm.** Five rows,
   two of them becoming wins over CaDiCaL. Highest value, and it is a routing
   fix rather than new reasoning.
2. **Watch/propagation throughput on dense few-variable formulas.** Two orders
   of magnitude; currently masked by (1).
3. **XOR/parity reasoning** for tseitin/Urquhart — the only true reasoning gap.
4. Per-variable trail positions, which would let shrinking and chrono compose.

## Method note

All of this was measured in a detached worktree at HEAD
(`git worktree add --detach`) with a hash-pinned copy of
`bin/tungsten-compiler`, because another agent held an in-flight refactor of
`lib/{policy,portfolio,solver,wassat}.w` in the main tree at the time. Nothing
here was measured against that WIP.
