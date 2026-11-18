# Wassat propagation, 18 November 2026

Release build of local main `9640787f`, arm64 macOS. Measurements use
`benchmarks/prop_bench.w` in raw, single-worker mode. The compiler SHA-256
was `0dd691fa5d293600873aad2bd4a98a40088d242a06ed89da87d0c0cf05d56913`.
SAT runs replayed their models against the input. An exhausted conflict
budget reports UNKNOWN. The UNSAT rows report solver verdicts.

Main advanced during the experiment. A clean strict bootstrap of `f1b4fcb0`
verified stage identity. Its release benchmark emitted the same 514 arm64
instructions for the entire propagation function, byte for byte. Baseline
and instrumented runs from that revision reproduced all ten search-counter
records and histograms. Timings below are from the frozen initial build.

The default propagation policy was retained. The largest full-solve change
came from circular search after a deep scan. It made ordering-320 4.6×
faster and ordering-384 1.4× slower. Both pairs produced checked SAT models.

## Where the work goes

A separate two-second CPU sample on clique put 1,449 of 1,522 main-queue
samples (95.2%) in `wassat_propagate`. The hottest listed offsets, +912 and
+840, resolve to the replacement path. These are instruction samples. Cache-miss rates require hardware events.

A long-watch visit first tests its cached blocker. A true blocker skips
the arena. On a miss, a true other watch also avoids the replacement scan.
A probe counts one tail literal tested, including the successful probe and
both parts of a wrapped scan. The final column weights scans by actual
literal probes. Rounded zeroes include small nonzero shares.

| Workload | Long visits | Blocker hit | Scans | Probes/scan | One probe | Over 32 probes | Probes in scans over 32 |
|---|---:|---:|---:|---:|---:|---:|---:|
| DivS 568 | 134,940,205 | 57.6% | 54,697,392 | 1.72 | 60.2% | 0.0% | 0.0% |
| clique | 214,709,092 | 50.9% | 100,418,732 | 7.94 | 14.2% | 3.5% | 20.4% |
| homer | 181,832,615 | 36.0% | 112,993,059 | 9.90 | 2.0% | 0.7% | 2.7% |
| ordering | 8,651,405 | 32.4% | 5,357,618 | 54.65 | 0.5% | 71.2% | 90.6% |
| DivS 568, Kissat | 43,332,502 | 52.8% | 19,548,074 | 1.33 | 77.5% | 0.0% | 0.0% |
| DivS 862 | 119,044,681 | 58.9% | 47,037,622 | 1.66 | 62.6% | 0.0% | 0.0% |
| ntil-41 | 94,959,084 | 88.3% | 10,097,533 | 13.02 | 35.2% | 13.4% | 45.4% |
| PHP 11/10 | 319,792,938 | 45.4% | 160,968,927 | 4.91 | 19.7% | 0.0% | 0.0% |
| random-500 | 13,425,272 | 36.8% | 8,130,845 | 2.39 | 66.6% | 0.2% | 3.2% |
| clique, Kissat | 16,814,716 | 52.9% | 6,755,540 | 7.96 | 36.3% | 4.5% | 24.4% |

The other watch was true on 2.9–14.6% of blocker misses. A replacement was
found on 73.0–99.7% of scans. Watch-pool growth and prefix recycling inside
propagation copied 0.057–0.345 eight-byte entries per long-watch visit.
Those counts exclude whole-pool rebuilds and clause database compaction.

For ordering, the long tail dominates. For DivS, most visits that reach a
scan succeed quickly, so the cost of inspecting and moving the watch matters
even when the replacement loop takes one iteration. The ntil-41 blocker
skips the arena on 88.3% of visits, yet its long scans account for 45.4% of
literal probes.

<details>
<summary>Exact replacement-scan histogram</summary>

| Workload | 1 | 2 | 3–4 | 5–8 | 9–16 | 17–32 | 33+ |
|---|---:|---:|---:|---:|---:|---:|---:|
| DivS 568 | 32,908,196 | 12,500,458 | 7,369,658 | 1,761,317 | 154,789 | 2,895 | 79 |
| clique | 14,232,289 | 14,209,351 | 20,902,201 | 21,314,402 | 19,635,244 | 6,595,952 | 3,529,293 |
| homer | 2,223,998 | 5,609,727 | 18,038,799 | 29,409,418 | 40,733,470 | 16,166,980 | 810,667 |
| ordering | 28,895 | 27,839 | 52,126 | 184,632 | 389,559 | 861,583 | 3,812,984 |
| DivS 568, Kissat | 15,146,565 | 3,270,549 | 960,593 | 130,614 | 39,493 | 255 | 5 |
| DivS 862 | 29,440,355 | 10,333,483 | 5,799,924 | 1,340,629 | 121,576 | 1,570 | 85 |
| ntil-41 | 3,558,327 | 218,161 | 538,168 | 1,006,208 | 1,845,997 | 1,577,290 | 1,353,382 |
| PHP 11/10 | 31,720,746 | 28,468,675 | 40,775,824 | 34,177,381 | 20,132,647 | 5,687,927 | 5,727 |
| random-500 | 5,411,632 | 906,824 | 887,079 | 545,185 | 263,957 | 100,019 | 16,149 |
| clique, Kissat | 2,450,791 | 713,422 | 661,315 | 828,940 | 1,096,135 | 699,461 | 305,476 |

</details>

## Testing alternatives

Each screen used separate, uninstrumented release binaries built from the
same clean tree and compiler. The seven common workloads ran four times per
binary, with rotated binary order and shuffled workload order. Budgets were
12,000 conflicts or the manifest limit if smaller, with early termination
on a verdict. Percentages are median paired changes in solve time. A
negative percentage means less time. The true-blocker and deep circular
search policies could change the search. Their timings include that effect.
The remaining prototypes matched the baseline verdict, conflicts, decisions,
propagations, ticks, restarts and reductions on the screened cases.

| Change | DivS 568 | clique | homer | ordering | ntil-41 | DivS Kissat | random-500 |
|---|---:|---:|---:|---:|---:|---:|---:|
| Reuse loaded literal and index | +2.1% | +3.4% | +4.3% | -0.4% | +0.8% | +1.4% | +1.1% |
| Probe variable and compare polarity | +2.1% | +2.5% | +1.9% | +4.9% | +5.9% | +5.7% | +2.1% |
| Probe four literals after eight misses | +12.9% | +18.1% | +20.1% | +20.7% | +11.1% | +10.4% | +5.2% |
| Power-of-two mirrored assignment | +3.4% | -0.4% | -2.0% | -3.6% | -1.3% | -0.1% | +0.0% |
| Keep a true replacement as blocker | +20.6% | +7.4% | +1.0% | +11.7% | +9.0% | +15.8% | +3.1% |
| Cache false prefixes for one propagation call | +6.2% | +7.9% | +10.8% | -0.9% | +2.9% | +2.3% | +5.2% |
| Accumulate watch removals in locals | -2.3% | +2.5% | +2.5% | -2.0% | +1.1% | -4.0% | +2.1% |
| Typed helper with an early-return loop | +0.3% | -1.7% | -1.4% | -0.1% | -0.0% | -0.2% | +1.5% |
| Range iterator in a typed helper | +42.9% | +77.4% | +97.3% | +176.0% | +75.1% | +43.9% | +27.3% |
| Call existing grow/append helper on full block | +9.6% | +5.0% | +7.4% | +2.9% | +5.2% | +11.1% | +6.7% |
| Defer the second watched-slot store | -0.1% | -2.2% | -0.3% | -0.7% | -1.3% | +3.8% | +1.0% |
| Range iterator with explicit i64 locals | -0.5% | -0.1% | +1.0% | +3.9% | +2.1% | +0.1% | +0.0% |
| Centered truth bytes with an aliased variable view | +3.5% | -3.5% | -1.0% | -3.9% | -1.3% | +5.0% | +1.0% |
| Enable circular search after a deep scan | +4.9% | -0.2% | +9.2% | -38.9% | +1.4% | +2.2% | +0.5% |
| Prefetch the clause two watch entries ahead | -6.2% | -1.1% | -0.3% | +0.2% | -3.4% | -4.5% | +2.1% |

The grouped scan tests four literals together after eight misses. The prefix
cache remembers a proven-false prefix within one monotonic propagation call.
Both preserved replacement order. The mirrored assignment puts the opposite
polarity at a power-of-two masked index. The centered version uses a single
truth table indexed by signed literal, a zero-copy positive-variable view,
and centered blocker indices. Both layouts shortened the long-scan path on
ordering and incurred a cost on DivS.

The ordinary range helper generated WValue tag checks and runtime arithmetic
fallbacks for its scan intermediates. Explicit `i64` types on the literal,
sign and index eliminated those calls in release code. The native baseline
used an `i32` arena, `i8` truth bytes and raw integer indices throughout
the scan. The two-entry lookahead compiled to an arm64 `prfum pldl1keep`
on the upcoming clause header. The entire baseline and prefetch propagation
functions contained no call instructions in these release builds. The final
counter build also kept the propagation kernel call-free, with a typed
histogram helper inlined into it. Formatting goes through a StringBuffer
before and after the timed search.

## Confirmation

The signed mirror, deferred watched-slot store and typed range iterator each
ran six more times on nine configurations at their original budgets. This
included complete DivS 568, random-500, PHP 9/8 and random-250 searches.
Every repetition matched baseline search counters.

| Candidate | Geometric mean of per-case ratios | Fastest change | Slowest change |
|---|---:|---|---|
| Signed mirror | +0.9% | -5.9% (ordering) | +7.0% (dense-kissat) |
| Deferred store | -0.7% | -3.0% (ordering) | +1.9% (dense862) |
| Typed range iterator | -0.3% | -3.6% (dense-kissat) | +2.3% (ntil33) |

The prefetch ran six interleaved pairs on **17 configurations**. Every search
counter matched. The equal-weight geometric mean of the 17 median paired
candidate/baseline ratios was **0.999**.
ntil-41 improved in all six pairs (median -2.3%).
DivS 568 moved from a 6.2% screening gain to +0.9% in the
repeat. On the second ordering input, the change was +1.6%.
The repeated timings gave little reason to add a prefetch to every blocker miss.

The deep circular policy activates only after reaching slot 32 of a clause
with at least 64 literals, then uses the saved position on later visits.
Its 38.9% shorter ordering screen covered a changed search. The follow-up
ran two pairs per input. Times are median solve milliseconds, with SAT
model replay for completed SAT rows. A fixed-conflict UNKNOWN row measures
the cost of reaching the limit. The exact policy is in the
[deep-cursor patch](../benchmarks/profiles/deep-cursor-9640787f.patch).

| Workload | Verdict (base / circular) | Conflicts (base / circular) | Solve ms (base / circular) |
|---|---|---:|---:|
| dense | SAT / SAT | 24,489 / 24,489 | 1541.5 / 1602.5 |
| dense-kissat | SAT / SAT | 9,761 / 9,761 | 567.5 / 658 |
| php11 | UNSAT / UNSAT | 14,660 / 14,660 | 2608 / 2672.5 |
| fresh-unsat | UNSAT / UNSAT | 225,057 / 225,057 | 2674.5 / 2679.5 |
| random500 | SAT / SAT | 24,265 / 24,375 | 232.5 / 227 |
| ordering | SAT / SAT | 37,487 / 15,978 | 1052 / 228 |
| ordering384 | SAT / SAT | 24,196 / 45,473 | 739 / 1020.5 |
| homer | UNKNOWN / UNKNOWN | 20,000 / 20,000 | 2076.5 / 2153 |
| verification | UNKNOWN / UNKNOWN | 10,000 / 10,000 | 480.5 / 534.5 |

A second prefix-cache prototype kept its epoch across monotonic branch
decisions inside the search and invalidated it on backjumps and database
maintenance. It matched the search counters in all six four-pair screens.
Its median paired changes were -1.5% on ordering,
+8.8% on clique and +9.3% on homer. The lookup and maintenance
cost persisted on workloads where the circular policy had little to skip.

## Copies and concurrency

The engine already appends clauses to a flat arena and publishes short learned
clauses across portfolio workers through a seqlock ring. Within one worker,
a watch move mutates the first two clause slots and two watch lists, and a
unit can enqueue another literal or end propagation on a conflict. Sharing
mutable clause bodies across workers would require per-worker watch positions
or a different propagation order. A channel or goroutine for each watch would
add coordination to the private loop measured here. The trail and watch scan
already pass typed buffers as arguments. Batching the scanned list's directory updates in
local integers gave mixed timings in the screen. The experiments measured
single-worker search only. Portfolio scaling requires its own benchmark.

## Reproducing the counters

Use a clean checkout of the measured revision for the diagnostic build.
The source changes are in the [diagnostic patch](../benchmarks/profiles/propagation-9640787f.patch). The two PROFILE records bracket
the search. Subtract the first record from the second. Use an uninstrumented
build for timing. `block_hit + block_miss` counts all visited long watches.
Binary implications have their own counter. `moves + exhausted` and the
sum of the histogram bins must both equal `scans`. A three-watch fixture
independently checked a blocker hit, a miss satisfied by the other watch
and a three-probe move. The four saved-position examples also passed with
the diagnostic applied.

```sh
git apply /path/to/propagation-9640787f.patch
bin/tungsten -o /tmp/prop-counts --release bits/tungsten-wassat/benchmarks/prop_bench.w
/tmp/prop-counts input.cnf 20000 0 raw 0
```

| Workload | Input | Conflict limit | Verdict |
|---|---|---:|---|
| dense | `DivS_568_11--0c9da400944b.cnf` | unlimited | SAT |
| clique | `clique_n2_k10--cb2e8b7fada4.cnf` | 20000 | UNKNOWN |
| homer | `homer11.shuffled--1890f49a43a9.cnf` | 20000 | UNKNOWN |
| ordering | `n320p5q2_n.af_239--5de866bc7ff4.cnf` | 10000 | UNKNOWN |
| dense-kissat | `DivS_568_11--0c9da400944b.cnf` | 20000 | SAT |
| dense862 | `DivS_862_11--74931e82fd20.cnf` | 20000 | UNKNOWN |
| ntil41 | `ntil-90d-41--fed1f1b55b33.cnf` | 20000 | UNKNOWN |
| php11 | `php11-10.cnf` | unlimited | UNSAT |
| random500 | `random500.cnf` | unlimited | SAT |
| clique-kissat | `clique_n2_k10--cb2e8b7fada4.cnf` | 20000 | UNKNOWN |

The two Kissat rows set `WASSAT_KSEARCH=1`.
