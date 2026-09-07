# Compiler performance, round 2

This document records the second compiler-performance queue and its acceptance
decisions. Timings are matched local measurements on Apple M5. They describe
the measured workloads, not a general speed claim. Retained transformations
must preserve native behavior and every applicable LLVM/sidemap identity gate.

## Queue

| Item | Work | Status |
| --- | --- | --- |
| 1 | PGO-train tagged release compilers | Shipped in `28529c1d` |
| 2 | Split closed-world compiler images from REPL/Metal support | Shipped in `99a2beaa` |
| 3 | Lower only reachable non-Core definitions | Rejected after A/B |
| 4 | Parallel function-body lowering | Deferred: requires isolated worker arenas and deterministic ID relocation |
| 5 | Per-file or per-function library WIRE reuse | Existing cohort cache retained; narrow prefix experiment rejected |
| 6 | Incremental or parallel escape/content hashing | Linear dependency-order experiment rejected; finer summary reuse remains open |
| 7 | Persistent compiler service | Existing `compile-batch` process/pool is the supported path; daemon work remains open |
| 8 | Replace hot WIRE field lookups with numeric schema identity | Retained |
| 9 | Complete closed-world flow-sensitive type propagation | Retained |
| 10 | Use effect/escape facts for proven allocation removal and LLVM attributes | In progress |

## Rejected reachability-lowering prototype

The prototype pruned only non-Core top-level function definitions and required
both protected Core and locked method tables. A self-compile removed 38 of
1,708 eligible definitions. Nine alternating release/native/fast runs moved
wall median from 4.460 s to 4.538 s (+1.74%) and mean from 4.671 s to 4.711 s
(+0.86%). It was removed.

## Function-body lowering parallelism boundary

Lowering currently mutates shared module maps, class tables, counters, AST/WIRE
arenas, and one reallocating process-global WIRE arena. Threads cannot safely
produce independent bodies until workers receive private arenas and deterministic
merge/remap rules (or preassigned disjoint ID ranges). The existing process-level
`compile-batch` path is already safe and measured 23.85 s versus 3.43 s for the
150-program workload (6.95x), so no unsafe nested thread path was added.

## Rejected linear dependency-order prototype

Replacing the escape/content-hash dependency scans with one Kahn topological
walk preserved LLVM but did not improve the self-compile. Across nine alternating
runs, wall median moved from 8.407 s to 8.729 s; escape median from 474 ms to
498 ms; content-hash median from 538 ms to 511 ms while its mean was flat. The
prototype was removed.

## Schema-shaped WIRE field cache

WIRE field lookup formerly cached `(record offset, field symbol)`. Every pass
therefore relearned the same ordinal independently for every instruction.
Generated constructors give each opcode a canonical field order, so the cache
now keys on the compact numeric WIRE kind plus field symbol. A hit still verifies
that the record actually contains the requested symbol at the cached ordinal;
compatibility records with reordered fields fall back to the linear scan.

Entries are cleared at every WIRE-store reset. Symbol handles can be reused for
different names in a later compiler generation, so carrying the cache through a
`compile-batch` reset is unsound even with ordinal verification.

Eight fresh alternating self-compile pairs used
`--release --native --fast --no-debug --emit-ll`, eight emitter workers, and
disabled frontend/incremental/render caches. LLVM was byte-identical at SHA-256
`67d75f24b1d091abd0125a42d120db509b6a14d087bc6519428226e45ebeaa8b`.
Median compiler time moved from 3.812 s to 3.793 s (-0.50%) and mean from
3.986 s to 3.916 s (-1.78%). External wall median moved from 4.88 s to 4.86 s
(-0.41%) and mean from 5.039 s to 4.971 s (-1.34%). The content-hash median
improved 2.90% and emitter median 1.06%. Four wall pairs won, three lost, and
one tied, so this is retained as a small structural improvement rather than a
large benchmark claim.

Focused gates cover reordered compatibility records, native arena behavior,
generated-constructor freshness, eight-program batch-vs-solo LLVM identity,
fast-loader/canonical-parser stage-1 identity, and a compiled native acid test.
The serial/parallel emitter LLVM mismatch observed by its older standalone gate
also reproduces byte-for-byte with the unmodified baseline; it is not introduced
by this cache.

## Closed-world loop-edge class sets

The bounded class-set pass now models ordinary `break` exits and `next`
backedges explicitly. A loop fixed point joins fallthrough and `next`
environments at its header, then joins stable `break` environments with the
condition-false exit. `redo`, transfers through `begin`/`ensure`, and iterator
regions remain conservative until their extra control-flow is represented.

Protected-Core lowering also needed a root-boundary fix. Core and user
expressions are lowered through the same main context, while nested
`lower_program` calls intentionally share the current root's analysis. After a
cached Core partition completes, the user root now resets only the analysis
readiness marker so its top-level calls receive their own flow facts. A
regression combines `PROTECT_THE_CORE!`, `LOCK_THE_DOORS!`, `break`, and `next`;
the resulting two-class receiver sets emit exhaustive direct arms and no value
inline cache, and the native result is checked.

The runtime acceptance benchmark constructs two objects once, alternates their
references for 50,000,000 iterations, and calls a method both classes inherit
from the same owner. Before this change the hot call is `call_method_i64`; after
it is one direct source call. Eight alternating binaries built with
`--release --native --fast --no-debug` produced identical result `50000000`.
External wall median moved from 3.160 s to 0.075 s (-97.63%) and user CPU median
from 1.245 s to 0.030 s (-97.59%). This deliberately demonstrates downstream
optimization potential: once dispatch is direct, full LTO inlines the
constant-return method and collapses most of the loop. It is not a standalone
measurement of raw IC latency.

That optimization has a compile-time cost. Against the exact preceding commit,
eight cache-disabled frontend-only self-check pairs moved user CPU median from
3.835 s to 4.035 s (+5.22%) and mean from 3.911 s to 4.045 s (+3.42%). A full
six-pair self-compile, which also benefits from 22 fewer emitted method-cache
calls, moved user CPU median from 6.155 s to 6.200 s (+0.73%) and mean from
6.165 s to 6.218 s (+0.87%); its wall data was too contention-sensitive to use
as the primary cost measure. The change is retained for the large closed-world
runtime opportunity, with the frontend cost recorded rather than hidden.

A compiler rebuilt from this source then re-emitted the compiler with the same
cache-disabled release/native/fast/no-debug profile. The two successive stages
were byte-identical at SHA-256
`d60d072b72716fcbc5b69fdcaa5ef75ab8af377cb6fd579688e74c950f616d37`.
