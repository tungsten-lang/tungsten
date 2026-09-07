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
| 9 | Complete closed-world flow-sensitive type propagation | In progress |
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
