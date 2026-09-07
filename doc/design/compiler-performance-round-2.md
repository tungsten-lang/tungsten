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
| 10 | Use effect/escape facts for proven allocation removal and LLVM attributes | Object-shell reuse retained; generic source-function attributes rejected |

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

## Escape-proven source-object shell reuse

The ownership pass already identified exact guarded `Class.new` results that
could not escape and inserted `w_value_free` at their proven lifetime end. It
now couples the two sides of that proof: the guarded allocation arm uses
`w_object_recycle_or_new`, and the matching release uses `w_object_recycle`.
The common eight-ivar object shape is kept in a bounded thread-local LIFO pool.
The shell is reset before reuse, so nested or reentrant allocations pop distinct
objects; uncommon larger layouts retain the existing `calloc`/`free` behavior.
Frozen objects never enter the pool.

The recycle flag is late-pass metadata in a spare packed-WIRE field rather than
part of every method-call record's canonical layout. The new release opcode was
appended to the stable opcode table. Content hashing includes the recycle flag,
so an ordinary constructor body cannot content-collapse with a recycling one.
Because the allocation arm is marked only while free insertion runs,
`TUNGSTEN_FREE=0` restores both ordinary allocation and the absence of an
inserted release.

The permanent `benchmarks/primitives/new_object.w` benchmark was corrected to
put its temporary in a function-local scope. Its former top-level `o` was a
global and therefore measured an escaping object that the compiler correctly
could not recycle. Eight alternating pairs used 50,000,000 iterations and
`--release --native --fast --no-debug`; every run printed the same operation
count and checksum `0`. External user CPU median moved from 1.220 s to 0.245 s
(-79.92%), and mean moved from 1.221 s to 0.245 s (-79.94%). Wall median moved
from 3.78 s to 0.57 s, but wall time was background-load sensitive and is not
the primary acceptance signal. A one-million-iteration statistics run recorded
999,999 object-pool hits, one miss, and no drops. LLVM confirms the intended
boundary: the old hot loop calls `w_object_new` plus `w_value_free`; the new
loop calls `w_object_recycle_or_new` plus `w_object_recycle`.

The feature is not claimed as a broad compiler-throughput win. Eight
cache-disabled compiler self-check pairs were neutral (user median 3.910 s to
3.890 s, -0.51%; means 3.885 s and 3.890 s). Eight full self-emission pairs
showed a small but noisy movement (user median 6.030 s to 5.950 s, -1.33%; mean
6.066 s to 5.884 s, -3.01%), while wall measurements were unusable under host
contention. Both compilers emitted the same compiler LLVM, and no recycler call
appears in that compiler image, so these timings do not justify a general
compile-speed claim.

Focused gates cover runtime shell reset, cross-class reuse, nested live-object
separation, frozen objects, duplicate releases, content-hash identity, the
`TUNGSTEN_FREE=0` kill switch, and batch-versus-solo LLVM identity. A debug
emission still contains the recycler calls while retaining `uwtable`, all frame
pointers, `noinline`, and disabled tail calls for backtrace fidelity. The final
compiler re-emitted byte-identical LLVM at SHA-256
`e59e372b27ba5c509f7e9d721afcfcd2cef63c38a531282d1df68d2810a758ca`.

### Rejected generic source-function attribute

A controlled probe added `memory(none)` to a noinline, register-only Tungsten
helper. After the ordinary `clang -O3` stage, annotated and unannotated modules
were byte-identical once their input filenames were normalized (SHA-256
`736b31055571ef6fd5c6c279318aa38a9121456a05f76dcbdc0fb1cbd1f2d312`).
LLVM inferred the same effect and optimized the caller identically. The current
escape summary's `pure` bit is also intentionally too coarse for LLVM memory
semantics: some operations allocate, release operands, or call incompletely
classified externs. No generic source-function memory attribute was added.

## Combined landing validation — 2026-09-07

The three retained round-two commits were rebased after the module split on
local main `ab662a58`. A fresh release/native/fast/no-debug compiler, current C
VM, and native runtime tests validate the combined changes. The older bootstrap
compiler's emission has 22 more inline-cache calls than the new compiler's
emission, reflecting the loop-edge facts. Rebuilding from the new compiler's
own output reaches a byte-identical self-host fixed point at SHA-256
`a36744163f53f122a64bd3409a7d452c6bf9d3e1741578d6783a28027af33e1d`.

Fresh focused gates passed: fast-loader/canonical-parser LLVM identity and its
native acid test; generated units and all 188 WIRE constructors; compiler image
and module boundaries; native object-shell and arena tests; content-hash,
ownership-phi, and escaping-object specs; the complete focused type-facts
contract script; and five-program batch/solo LLVM identity, including the new
loop-edge fixture. Debug emission retains backtrace attributes while recycling;
`TUNGSTEN_FREE=0` removes both recycler allocation and release calls. The full
suite remains a CI responsibility.

Runtime reruns compare the main compiler built from `99a2beaa` (the compiler,
Core, and runtime sources are unchanged through `ab662a58`) with the combined
compiler. Both benchmark variants link the same current runtime sources and use
`--release --native --fast --no-debug`. One warmup and three alternating measured
pairs each run 50,000,000 iterations, with identical outputs (`50000000` for the
shared-owner dispatch loop and `0` for the object checksum).

| Workload | Before user CPU | After user CPU | Before wall | After wall |
| --- | ---: | ---: | ---: | ---: |
| Shared-owner loop dispatch | 0.82 s | 0.02 s | 0.838 s | 0.030 s |
| Non-escaping object churn | 0.81 s | 0.16 s | 0.821 s | 0.170 s |

These are workload-specific runtime improvements, not a claim that the compiler
itself is uniformly faster. The module split's cold-compilation regression in
`compiler-module-boundaries.md` remains an open follow-up; it was not silently
removed from the landing report.
