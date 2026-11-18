# Wassat engine performance, 2026-11-17

## Main integration validation, 2026-11-18

Revalidated the scoped changes on clean main `dca0188e`, including the newly
landed private-query storage ownership. Both clean-main and patched strict
builds printed `VERIFIED stage 1 .ll == stage 2 .ll`. Fourteen focused Wassat
specs, the compiler string-dependency regression, both compiler cache checks,
and four interpreted specs passed. CLI WRAT/DRAT/LRAT, mixed sinks, portfolio
proofs, failure handling and cleanup passed. A fresh 60-case differential
matched CaDiCaL, checked 32 SAT models and independently verified 28 DRAT
proofs. Records are under `build/wassat-land-20261118/`.

The performance tables below retain their frozen 2026-11-17 measurements;
this landing run checks compatibility with current main. Unrelated ongoing
work is excluded. The installed Wassat executable was not replaced.

## Work checklist

- [x] Capture release baseline and sample representative CDCL workloads.
- [x] Identify and implement measured engine improvements.
- [x] Compare interleaved fixed-work runs and verify search results.
- [x] Run focused regression and independent certificate checks.
- [x] Record results, limitations, and algorithmic follow-ups.

## Continued proof-path work

- [x] Capture a release proof benchmark and allocation baseline.
- [x] Remove temporary learned-clause/hint collections from streamed WRAT.
- [x] Finish same-binary timing and byte comparisons, then independently
  verify completed certificates and exercise sink boundaries/failures.
- [x] Record measurements and remaining algorithmic opportunities.

Evidence for this continuation lives in `build/wassat-proof-perf-20261117/`.

Streamed WRAT now formats the learned literals and hint IDs directly from
typed buffers into a reusable 1 MiB byte buffer. Dual DRAT output uses its
existing native formatter too. The library's in-memory result contract is
unchanged. Oversized records fall back after flushing; mixed text/byte paths
preserve order. Both dialects reserve distinct scratch filenames, avoiding
collisions when one library caller's output is named after the other plus
`.chunk`.

The random-500 dual-proof allocation run completes SAT at 102,843 conflicts.
The same-binary text/native controls have identical search counters and replay
the SAT model against the original CNF. `wait4` reports peak RSS of 445,366,272
versus 150,847,488 bytes (424.7 versus 143.9 MiB). Instrumented new arrays fall
from 208,298 to 2,316; growth operations fall from 423,922 to 26. These include
startup/search metadata, and do not count all allocations. Timing is recorded
separately in the interleaved run, with allocation instrumentation disabled.

Five interleaved repetitions per configuration, one final release binary,
text versus native sinks (milliseconds, medians):

| Input / mode | Text | Native | Change |
| --- | ---: | ---: | ---: |
| random250 / WRAT, complete SAT | 389.8 | 313.4 | −19.6% |
| random250 / dual, complete SAT | 385.2 | 301.4 | −21.7% |
| random500 / WRAT, complete SAT | 2,625.0 | 2,372.1 | −9.6% |
| random500 / dual, complete SAT | 2,906.9 | 2,451.3 | −15.7% |
| PHP(9,8) / dual, complete UNSAT | 145.6 | 141.0 | −3.2% |
| PHP(11,10) / dual, complete UNSAT | 4,514.0 | 4,655.5 | +3.1% |
| clique_n2_k10 / dual, 10k conflicts, UNKNOWN | 1,485.5 | 1,451.7 | −2.3% |
| random500 / DRAT, 20k conflicts, UNKNOWN | 188.8 | 197.1 | +4.4% |

All 80 runs have identical search counters and proof-file bytes within each
configuration. The DRAT-only control executes the same formatting path in
both settings; its 4.4% timing spread is a useful limit on small differences.
The random-SAT WRAT gains and allocation reduction are the retained result;
no speedup is claimed for the remaining cases, nor for an entire benchmark
suite or portfolio. `controlled-results.json` records every run, counters,
input/binary hashes, proof hashes, and sizes; `pairs_controlled.py` reproduces
the experiment. `pairs-results.json` is the earlier separate-binary trial,
not the basis for these claims. The final completed pigeonhole certificates
were independently rechecked after the controlled run (`final-proof-checks.json`).

The baseline CPU sample has 2,822 main-thread samples: propagation accounts
for 61.4%, `Array#join` for 7.4%, literal-array materialization for 1.7%, and
proof-sink flushing for 2.6%. Hint construction and other formatting work
remain in the learned-clause logger. Sampled runs are not timing results.

Validation so far: 76 compiled examples across proof formatting, proof sinks,
the solver, and incremental queries; the three formatter examples also pass
interpreted. Tests cover maximum signed 64-bit proof IDs, signed 32-bit
literals, conservative capacity boundaries, arithmetic-overflow rejection,
forced oversized fallback, mixed sinks, headers, ordering, aborts, failed
writes, and scratch-name collisions. Independent WRAT and DRAT checking passed
the 1,097- and 13,715-conflict raw pigeonhole refutations. CLI checks also
independently verified WRAT/DRAT/LRAT, mixed stdout/file output, and portfolio
proofs, and checked SAT/UNKNOWN cleanup and write-failure behavior.

### Compiler cache defect exposed by the continuation

The scratch-name change exposed stale literal bindings in cached library LLVM
bodies: a proof header could become an error-message prefix, and result hash
keys could name the wrong fields. Disabling integer releases initially hid
the failure; decoding the emitted LLVM and disabling library-body caching
isolated the actual cause. The cache key covered the library's lowering-time
string prefix, while optimized functions can reference later strings.

`function_emit_library_string_count` now extends that prefix through every
string ID actually referenced by eligible library functions, including switch
cases. The cache version changes to invalidate old entries. This preserves
reuse when only unrelated entry literals change. The new dependency spec
fails on clean HEAD and passes after the fix; existing rendered-function-cache
and linear-postprocessing scripts pass. The dependency spec uses compiled-only
WIRE intrinsics, so it is explicitly in the compiled lane.

Clean HEAD, the patched isolated checkout, and the patched working checkout
all printed `VERIFIED stage 1 .ll == stage 2 .ll`. The fixed compiler is now
installed in this checkout. Warm cached and uncached LLVM for the actual
proof benchmark match byte-for-byte, and its installed-compiler proof bytes
match the qualified binary (`installed-cache-check.json`). The installed
Wassat executable was not replaced;
the current validated CLI is `build/wassat-proof-perf-20261117/wassat-final`.
No runtime source was changed by this work. Compiler and source hashes,
build logs, allocation logs, and all certificate checks are in the evidence
directory above.

## Continued propagation work

- [x] Compare saved scan positions on ordinary and Kissat search policies.
- [x] Check fresh complete-solve cases and independently compare verdicts.
- [x] Record the rejected default change and retain reproducible controls.

Evidence: `build/wassat-scan-perf-20261117/`. The benchmark fixture can now
force saved replacement positions on or off after loading, independently of
the other Kissat-profile choices. Both columns use the same release binary.
The production solver is byte-for-byte unchanged from the proof pass.

The initial screen covers 19 configurations, three interleaved repetitions
each (114 runs). Many bounded runs become substantially faster, including
clique and homer, but every configuration changes its search trajectory.
These are exploratory timings, not evidence for a global default: the final
screen and start of the fresh run briefly overlap, and one early fresh run
overlaps a test compilation. The decisive regression below was then repeated
separately, with no competing jobs launched by this investigation.

Fresh cases are twenty 250-variable, 1,075-clause random 3-CNFs generated with
Python `random.Random(17112026 + seed)`, seeds 0–19. One bounded trial per
setting, with a ten-second search limit checked every 5,000 conflicts, solves
19/20 with positions disabled and 18/20 enabled. This is a diagnostic sample,
not a statistically qualified benchmark score. All completed verdicts agree
with independent CaDiCaL runs; the benchmark replays every SAT model against
the input. The agreement checks are not certificate verification.

Seed 1 is the reason to reject global enabling. The original scan policy
finishes UNSAT at 225,057 conflicts, in roughly 3.7 seconds. The saved-position
trial initially exceeded the 90-second process timeout. Repeating with
explicit conflict bounds gives the same deterministic counters twice:

| Policy / limit | Status | Conflicts | Median solve time | Watch rebuilds |
| --- | --- | ---: | ---: | ---: |
| Ordinary / 250k | UNSAT | 225,057 | 3,671.5 ms | 49 |
| Saved positions / 250k | UNKNOWN | 250,000 | 3,923.0 ms | 52 |
| Ordinary / 1M | UNSAT | 225,057 | 3,709.5 ms | 49 |
| Saved positions / 1M | UNKNOWN | 1,000,000 | 31,977.5 ms | 732 |

At one million conflicts the saved-position run has 622 pool overflows.
Thus the loss includes both a worse search trajectory and much more watch
maintenance; it cannot be diagnosed as a simple per-scan slowdown. The
existing Kissat profile already combines saved positions with a different
watch-headroom policy and search schedule. Keep that tested combination;
do not generalize one component based only on early conflict throughput.

Retained infrastructure: `prop_bench.w`'s benchmark-only
`WASSAT_BENCH_SAVED_POS` control; search-time/tick bounds and explicit verdict
summaries in `engine_pairs.py`; and timeout evidence saved before a failed
child aborts the harness. Four new saved-position examples pass compiled and
interpreted, covering suffix selection, wraparound, units/conflicts, maximum
packed clause IDs, and the 8/9/32767/32768 length boundaries. Harness smoke
checks cover bounded invocations, summary statuses, and saved timeout records.

Raw records: `pairs-scan.json`, `pairs-holdout-bounded.json`,
`pairs-regression.json`, `reference-verification.json`, and
`source-manifest.json`. `pairs-holdout.json` is the initial interrupted run;
its first timeout predates the harness timeout-recording fix.

The next pass below investigates propagation memory traffic while preserving
watch traversal order. The profile, rather than allocation counts, motivates
the compact literal arena.

## Compact arena: integrated and qualified

- [x] Inspect release propagation assembly and array-access lowering.
- [x] Reject a slower non-inlined capacity-repair helper.
- [x] Preserve search policy while narrowing arena storage.
- [x] Qualify all affected readers, growth, compaction and shared-input loading.
- [x] Measure final release binaries with repeated paired timings and peak RSS.

`build/wassat-memory-perf-20261117/` contains this pass. The final arena uses
two i32 header cells (clause index and length/scan position), followed by i32
literals. Packed watch words retain i64 storage. `@acap`/`@aused` retain the
previous one-header logical budget, while `@asize` counts physical cells.
Backing storage reserves one extra header cell per clause slot. This keeps
learning headroom and fixed-worker compaction policy unchanged. Both growth
paths check the signed physical-offset bound before allocating, and stable-
index compaction counts resident records independently of the high clause ID.

Final measurements use `prop-final` against the frozen `prop-scan` i64
baseline, built with the same compiler and unchanged benchmark dependencies.
Five alternating repetitions per binary/configuration give 200 runs. Every
verdict, conflict, decision, propagation, tick, restart and reduction count
matches. Median search time falls 3.1%–13.1% across these twenty configurations
(7.6% lower geometric mean). Parsing, loading and original-model verification
are outside the timed interval; capped UNKNOWN rows measure fixed-work
throughput, not completed-solve time. This is not a competition-wide or
portfolio-speed claim. Small differences remain subject to shared-host noise.

| Configuration / termination | i64 arena | i32 arena | Change |
| --- | ---: | ---: | ---: |
| DivS_568_11, complete SAT | 3,408 ms | 3,256 ms | -4.5% |
| clique_n2_k10, 20k conflicts, UNKNOWN | 2,722 ms | 2,527 ms | -7.2% |
| homer11, 20k conflicts, UNKNOWN | 3,020 ms | 2,761 ms | -8.6% |
| random250, complete SAT | 97 ms | 94 ms | -3.1% |
| Circuit_multiplier36, 10k conflicts, UNKNOWN | 194 ms | 172 ms | -11.3% |
| AProVE07-01, 10k conflicts, UNKNOWN | 929 ms | 887 ms | -4.5% |
| n320p5q2, 10k conflicts, UNKNOWN | 491 ms | 431 ms | -12.2% |
| carry, complete SAT | 691 ms | 645 ms | -6.7% |
| DivS_568, Kissat, complete SAT | 1,563 ms | 1,375 ms | -12.0% |
| clique, Kissat, 20k conflicts, UNKNOWN | 312 ms | 274 ms | -12.2% |
| homer, Kissat, 20k conflicts, UNKNOWN | 274 ms | 254 ms | -7.3% |
| DivS_862_11, 20k conflicts, UNKNOWN | 3,296 ms | 2,865 ms | -13.1% |
| ntil-90d-33, 20k conflicts, UNKNOWN | 467 ms | 416 ms | -10.9% |
| ntil-90d-41, 20k conflicts, UNKNOWN | 570 ms | 533 ms | -6.5% |
| cover, 20k conflicts, UNKNOWN | 820 ms | 780 ms | -4.9% |
| st540, 20k conflicts, UNKNOWN | 387 ms | 367 ms | -5.2% |
| random500, complete SAT | 314 ms | 300 ms | -4.5% |
| PHP(9,8), complete UNSAT | 99 ms | 94 ms | -5.1% |
| PHP(11,10), complete UNSAT | 3,456 ms | 3,270 ms | -5.4% |
| fresh random250 UNSAT, complete UNSAT | 3,634 ms | 3,434 ms | -5.5% |

`pairs-final.json` retains every run, input/binary hash and counter. Separate
`wait4` measurements use two alternating repetitions; macOS `ru_maxrss` is
in bytes. Whole-process peak RSS includes parsing and all solver state:

| Input | Baseline peak RSS | Compact peak RSS | Change |
| --- | ---: | ---: | ---: |
| DivS_568_11 | 275.2 MiB | 251.8 MiB | -8.5% |
| n320p5q2 | 17.8 MiB | 14.2 MiB | -20.5% |
| DivS_862_11 | 282.6 MiB | 246.5 MiB | -12.8% |
| PHP(11,10) | 6.8 MiB | 6.4 MiB | -5.6% |

The huge raw loader still consumes its parser mirrors to avoid retaining a
second large literal buffer. It records `flat_lits_bits=32`, and model checking
uses a matching native reader. Repeated consumption of the same artifact is
rejected explicitly. The exact consuming branch is exercised on small arrays,
including invalid models, empty clauses, duplicate units and descriptor
aliases after growth. A full 40-million-clause run was not performed.

Qualification covers 285 compiled examples in 32 focused specs, including
ordinary/Kissat search, incremental assumptions, both compaction forms,
capacity boundaries, proof buffers, inprocessing, cancellation, snapshots,
SLS refill and clause sharing. Twelve affected specs also pass interpreted.
The final production CLI passed all 27 portfolio examples. Two stale fixture
issues were reproduced on unchanged sources: DRAT recycling was incorrectly
forbidden, and propagation state arrays omitted newer tick/scan slots. The
fixtures now express the existing contract and pass on both applicable lanes.

Final PHP(9,8)/PHP(11,10) dual and DRAT-only search counters and proof bytes
match the i64 baseline; all twelve baseline/candidate certificates pass the
independent checker. CLI WRAT/DRAT/LRAT, mixed sinks, portfolio proofs, failure
handling and SAT/UNKNOWN cleanup pass. A fresh 120-case CaDiCaL differential
matches every verdict, checks all 64 SAT models and independently verifies
56 UNSAT DRAT proofs. The 100,000-operation packed allocation probe reports
zero BigInts. Evidence is summarized in `qualification-final.json`.

The final binaries are `prop-final`, `proof-final`, and `wassat-final` in the
memory experiment directory. `final-binaries.json`, `source-manifest-final.json`,
`summary-final.json` and `rss-final.json` identify the measured artifacts.
The installed Wassat executable remains unchanged. These artifacts record
the validated source before main integration.

Earlier `arena32/` through `arena32-v4/` copies and their generator scripts
retain the development evidence. Their preliminary timings are not the basis
for the table above. The separate cold-helper experiment reduced propagation
assembly from 536 to 462 lines but slowed every case in 120 paired runs;
`cold.patch` was rejected. Existing native loops already hoist descriptor loads
inside replacement scans, and the extra call inhibited other hoisting.

Scope: general solver machinery, independent of SC2025 specialist work.
The checkout already has unrelated edits, including the CLI and parser;
preserve them. Baseline source, binaries, profiles, and raw measurements live
in `build/wassat-perf-20261117/`. Builds use `--release` and a private build
store at `/tmp/wassat-perf-store`.

## Profiles and the change

Five-second macOS CPU samples of `prop_bench` (main thread only) found:

| Input | Propagation | Watch-pool rebuild |
| --- | ---: | ---: |
| DivS_568_11 | 53.8% | 43.1% |
| clique_n2_k10 | 96.4% | negligible |
| homer11 | 95.1% | negligible |

The dense input completed with 434 watch rebuilds, including 428 overflows.
The flat loader reserved less watch relocation space than the ordinary
constructor/table-growth path. Large per-literal blocks repeatedly consumed
that spare space; each overflow triggered a count/fill pass over the database.

The flat loader now starts with the existing table-growth watch bound for
databases with at least 131,072 long clauses and at least 64 long clauses per
variable, below four million input clauses. Binaries, units, and empty clauses
do not count toward this decision. It changes only watch storage: clause
capacity, learning headroom, search policies, and the lean lucky loader retain
their sizes. The Kissat profile already used this pool bound.

An explicit `WASSAT_WATCH_EXTRA` setting replaces this automatic sizing, so
`WASSAT_WATCH_EXTRA=0` provides a same-binary control for these workloads.
This is a memory/time tradeoff within the solver's existing growth envelope,
not an allocation-free reduction in memory use.

## Controlled results

Five interleaved repetitions, one release binary, automatic sizing versus
`WASSAT_WATCH_EXTRA=0`. Medians below exclude parse/load time. Only the first
row is a complete solve; the other three stop at 20,000 conflicts and remain
UNKNOWN. Fewer rebuilds can change watch traversal order, so these rows are
not identical search trajectories (the harness records that explicitly).

| Input / bound | Before | After | Reduction | Watch rebuilds | Extra pool per solver |
| --- | ---: | ---: | ---: | ---: | ---: |
| DivS_568_11, complete SAT solve | 3,606 ms | 2,811 ms | 22.0% | 434 → 32 | 12.7 MiB |
| DivS_862_11, 20k conflicts | 2,913 ms | 1,796 ms | 38.3% | 224 → 20 | 19.6 MiB |
| ntil-90d-33, 20k conflicts | 297 ms | 273 ms | 8.1% | 33 → 6 | 5.1 MiB |
| ntil-90d-41, 20k conflicts | 415 ms | 356 ms | 14.2% | 23 → 5 | 12.4 MiB |

The other twelve configurations (including three Kissat-profile controls)
had identical search counters across policy settings. Their median timing
ratios were 0.954–1.038. This is a targeted engine result, not an SC2025 score
or a claim that every formula becomes faster. Absolute times varied with host
load; use the interleaved controls, not timings from different experiment runs.
Additional memory is per solver, so a portfolio multiplies the cost by the
number of affected resident arms. Existing conservative memory gates remain
in force; the new pool does not exceed its existing table-growth bound.

Evidence under `build/wassat-perf-20261117/`:

- `reserve-controlled-results.json`: all 160 runs, counters, binary/input
  hashes, and the 16-row manifest.
- `reserve-qualification-results.json`: separate-binary breadth comparison.
- `*.sample`, `prop-baseline.sidemap`: CPU samples and symbol decoding.
- `alloc-baseline.json`: allocation census at 1 and 20,000 conflicts.
- `model-replay.json`: current-source SAT model replay, including a prepared
  kernel, and the dense UNSAT fixture.
- `dense-unsat-reference.log`, `dense-unsat-proof-check.log`: independent
  CaDiCaL agreement and WRAT verification of its 59-step DRAT refutation.

`engine_pairs.py` accepts the saved manifest, so these runs can be repeated
with another release binary. `prop_bench.w` now checks SAT search models
against the original CNF after the timed interval, reconstructing eliminated
variables for prepared kernels.

## Validation

Passed 114 compiled examples across the policy, dense intake, watch pool,
watch recycling, propagation snapshots/cancellation, solver, incremental, and
Kissat-search specs; the seven policy examples also passed interpreted.
The 80-case differential agreed with CaDiCaL, replayed 40 SAT models, and
independently checked 40 Wassat DRAT refutations with WRAT.

The standalone policy spec initially exposed a missing `use cnf` dependency
for `wassat_unsigned_decimal?`. The same failure reproduced using HEAD's
policy source. Declaring the dependency fixes standalone policy loading;
ordinary solver loading already imported CNF before policy.

The initial watch-sizing pass changed no compiler, runtime, installed solver
binary, or SC2025 specialist source. Its validated CLI is retained at
`build/wassat-perf-20261117/wassat-final`; these measurements preceded the scoped main integration above.

## WValue and allocation audit

`runtime/wvalue.h` already represents signed 48-bit integers, doubles, and
small singleton values directly. The solver's literal IDs, clause IDs, statuses,
and most counters fit those immediate values. Packed 64-bit watch words stay in typed `i64[]` buffers/native helpers:
treating arbitrary packed words as immediate Integers would overflow the
48-bit payload. The integrated arena instead splits each header into two i32
cells and stores literals as i32. Individual values fit WValue immediates,
but typed storage uses four bytes per cell and already avoids per-value heap
allocation; a boxed WValue array would use eight bytes per cell.

`TUNGSTEN_ALLOC_PROFILE=1` on the baseline showed identical instrumented
allocation totals at 1 and 20,000 conflicts for both DivS_568_11 and
clique_n2_k10: 143 array allocations, four hashes, and one startup BigInt.
The random-250 SAT solve added only its final model array. These counters cover
the runtime's instrumented categories, not every possible malloc, but together
with the CPU samples they rule out per-conflict boxed integers/temporary arrays
as the dominant cost on these paths. Preserve this property in future changes.

## Algorithm review

- The packed binary lists, cached blockers, flat clause arena, reusable
  analysis buffers, and native integer loops are appropriate. The measured
  bottleneck is memory traversal and list maintenance, not heap allocation.
- Saved replacement positions already avoid repeated prefix scanning in the
  Kissat profile. The fresh complete-solve experiment above rejected enabling
  them globally: faster scans can still produce a much worse search trajectory.
- The compact i32 arena reduces literal bandwidth without changing watch
  traversal. Headers use two cells; packed watch words retain 64-bit storage.
  Keep logical learning budgets separate from physical storage dimensions.
- The proof continuation above removes streamed learned-clause literal/hint
  arrays and decimal strings. In-memory certificates still retain text as
  required by the public result contract.
- Keep portfolio decisions separate from engine measurements. `prop_bench`
  isolates one solver, while the new `engine_pairs.py` records whether the
  search trajectory actually remained identical.

## Rejected experiments

Four parallel truth probes per replacement-scan iteration preserved search
counters but slowed the sampled workloads (roughly 10–24% on the longer runs).
Deferring clause-header decoding had mixed results. Reclaiming smaller watch
prefixes and changing relocation growth from 2x to 1.5x also failed broader
checks. Those changes were removed; none is part of the retained engine patch.
