# Rotating GPU kernel pool

FlipFleet keeps six continuously useful GPU roles: rank, density, C3, generic
split, archive novelty, and cooperative SIMD.  Logical role 10 is a rotating
pool backed by up to three independent physical workers.  Each batch chooses
at most one kernel from each deliberately different family:

- constraint/lower-bound: projected defect, substitution scout, XOR-SAT cubes,
  and a bounded support-clustered frozen-fringe SAT child on 4×4;
- exact surgery: 5→4 MITM, 6→5/7→6 XOR, staged 8→7/9→8 XOR,
  complete three/four-term factor-span refactors, exact low-rank absorbed
  shears, one bounded whole-frontier 5×5 kernel-shear child, and one bounded
  distant-parent CPU differential child;
- algebraic escape/walk: lifted identity, fixed-cube break, orbit split,
  polarization, two identities, and live primitive five/six-circuit mining.

The workers have separate seed/output/log files, launch IDs, timing, and
reward contexts; their telemetry remains combined in the pool row.  A family
slot that finishes early selects and launches its next kernel independently.
When the dedicated side drains, its contemporaneous pool children become
barrier anchors; faster siblings keep refilling until those anchors finish,
then only their short tail drains before the clean allocation/rebalance
barrier.  Scalable modes share three eighths of configured lanes, rounded to complete 32-lane
SIMDgroups, with a 32-lane minimum and a 1536-lane cap.  MITM is capped at 512
lanes, the bounded 6→5/7→6 joins and circuit miner at 256, and the O(pool⁴)
8→7/9→8 joins at 128.  Span-3 is capped at 256 logical lanes and visits at
most eight independent neighborhoods. Span-4 is charged 128 lanes for device
pressure but is forced to one neighborhood: its complete worst case already
contains 3,375 candidate terms and 5,693,625 exact pairs. Parent differential,
whole-frontier kernel shear, and frozen-fringe SAT are each a single CPU
process represented by one 32-lane quantum. Global kernel shear is eligible
only on 5×5; frozen SAT is eligible only on 4×4 and receives a two-second process
deadline, and stays dimmed when `cryptominisat5` is absent. Excess quanta return
to the continuous roles.

Low-rank shear is enabled only for 5×5–7×7. It is capped at 256 logical lanes
on 5×5, where a real non-one-flip exact hit occurs after 504 source pairs, and
at 128 on 6×6/7×7 until their tensor-local UCB reward shows comparable value.
The 4×4 diagnostic lane remains off.

The 9,002-second audit snapshot of the live 4×4 lunch campaign supplied a
tensor-specific correction rather than a global retune. In that interval, the
constraint/lower-bound family ran 6,731 epochs without producing an exact
candidate, and substitution reached
only contraction bounds 12/16. Exact surgery continued to return exact local
hits, while generic escape returned 4,064 exact schemes and produced all six
nominal rank-46 near misses. Consequently, 4×4 caps a selected constraint child
at 128 lanes (four SIMDgroups), preserves its nonzero floor, and water-fills the
released width into exact surgery and generic escape. With the default 1,536-
lane pool this gives `128/512/896` for constraint/MITM/escape, or
`128/256/1152` when the surgery child is a capped XOR or span-3 join, and
`128/128/1280` for span-4. Other tensor sizes retain their existing allocation
until they have comparable evidence.

Every eligible kernel receives a cold launch within its family.  Afterwards
every fourth family launch is strict round-robin rotation; the other three use
integer UCB within the current `(tensor, rank-debt)` context.  Dedicated roles also accumulate
reward/exposure in tensor/rank-debt contexts, so a productive high-rank escape
does not teach the scheduler that the same role is productive from every seed
class.

At a fresh frontier, rank-first starts from the rank+2 bank, archive novelty
starts from a mixed algebraic escape, and cooperative SIMD starts from the
rank+1 bank.  Density and generic split deliberately retain the exact frontier.
This avoids sending every engine the same record scheme while preserving the
two roles whose objective genuinely depends on that scheme.

`DEGRADED` means current GPU coverage is unavailable: build, launch, process,
or coordinator I/O failure.  Exhaustive-gate rejection is counted as an exact
reject and does not disable the role.  A successful retry clears the health
banner while the per-role failure counter remains cumulative for diagnosis.

### Replayable internal exact rejects

The exhaustive generic-worker gate now emits stable sidecars whenever a
nominal improvement fails. It records the raw seed, raw candidate, worker
generation/round, and a deterministic exact-error code. Positive error `e`
encodes the first nonzero GF(2) syndrome coordinate as
`e = 1 + (ai*n² + bi)*n² + ci`; negative codes identify malformed factors.

The coordinator independently parses and gates that sidecar. If its nominal
rank is at or below the campaign's strict improvement target (`fleet best - 1`),
it first makes a bounded CPU syndrome-repair attempt. The safe-axis solver is
used through 7×7; the larger all-axis system is limited to 3×3–5×5. A repaired
candidate is admitted only after the ordinary complete `n^6` gate and then
flows through the existing reward/bank path. Irrespective of repair success,
the original reject is frozen as an immutable replay bundle under
`/tmp/flipfleet_gpu_reject_<run-tag>_*`, adding the physical slot, logical role
and pool mode, coordinator launch nonce, both exact-error results, decoded
coordinate/parities, and an `internal_rejects=N` counter. Every such event logs
one `GPU_INTERNAL_REJECT` line, and a machine-readable summary file points to
the latest bundle. Ordinary exact rejects and infrastructure failures retain
their previous accounting; syndrome repair itself does not change `DEGRADED`.

## Pool modes

| mode | implementation | admission contract |
|---|---|---|
| projected defect | persistent Metal local search at rank `R-1` | sixteen separable projections guide mutations; only exhaustive host verification can emit a scheme |
| 5→4 MITM | existing `flipfleet_mitm_lane.w` | full local identity and complete spliced tensor are verified |
| 6→5 XOR | GPU pair/triple join | 128-bit projected hits receive full local and complete-tensor verification |
| 7→6 XOR | GPU triple/triple join | same exact gates as 6→5 |
| primitive 5+ circuit | GPU pair/triple or triple/triple zero-signature join | every possible hit receives exhaustive zero-tensor and all-proper-subset primitivity checks before the identity is toggled into a live exact scheme |
| parent differential | single pure-Tungsten CPU child; exact bit-packed nullspace elimination over a bounded complete archive difference, with the primitive-five pair/triple join as fallback | every nullspace relation is exact over all n^6 coefficients; both parents and the materialized hybrid are exhaustive-gated; the real 5×5 d1155/d1168 pair emits an exact rank-93/d1165 third basin |
| 8→7 XOR | bounded GPU triple/quad join | the 128-bit join is only a filter; complete local and spliced-scheme reconstruction decides admission |
| 9→8 XOR | bounded GPU quad/quad join | same exact gates as 8→7; enabled after the planted 8→7 stage |
| span-refactor-3 | complete nonzero Cartesian product of the three selected factor spans, followed by an exact Metal signature join | exact 27-bit local tensors; rotates 3→2, 3↔3, and 3→4; every third neighborhood deliberately spans an external live term, whose reappearance is parity-compacted and scored at the actual global rank |
| span-refactor-4 | the same complete construction for four selected terms, with one memory-bounded neighborhood | exact signatures use all 64 bits; rotates 4→3 and 4↔4 over as many as 5,693,625 pair entries; one-third of offsets use an external-span door and all admitted results receive the complete tensor gate |
| low-rank shear | Metal enumerates rotated `(source pair, ordered axis pair, first carrier)` tuples for q=2 rank-1/rank-2 correction absorption | every structural hit is retained; the host rejects one-flip endpoints, parity-compacts any external live-term collisions, and runs local plus full `n^6` admission before serialization |
| global kernel shear | one bounded pure-Tungsten CPU child assigns one mutable axis to every 5×5 live term and eliminates the complete one-bit edit map | rejects no-ops and ordinary one-flip endpoints, then rebuilds, serializes, reparses, and full-gates the scheme; 8/64 real plans produced exact three/four-term basin edges, with no rank or density improvement |
| lifted identity | exact subspace-supported splits, plus a bounded 5x5 five-bucket projective `+1` shoulder, then cal2zone | every lifted seed and returned scheme is exhaustive-gated |
| substitution scout | GPU contraction-mask enumeration | host recomputes the GF(2) contraction rank and logs a replayable mask; it is a valid contraction bound, not yet a full substitution-chain proof |
| XOR-SAT cubes | single-bit projected `R-1` local search | a projected zero is only a candidate; no UNSAT or rank claim is made without an independent certificate |
| frozen-fringe SAT | one support-clustered pure-Tungsten CPU child at the 4×4 frontier | freezes 31 terms, encodes an exact 16→15 replacement, invokes CryptoMiniSat with a two-second deadline, and admits only a complete reconstructed-tensor match |
| fixed-cube break | asymmetric split of a fixed C3 cube followed by cal2zone | the exact escaped seed and returned scheme pass the usual gates |
| orbit split | complete C3-orbit escape bank followed by cal2zone | unavailable when no exact orbit bank exists |
| polarization | cubic-polarization escape bank followed by cal2zone | unavailable when no exact polarization bank exists |
| two identities | depth-two identity composition followed by cal2zone | exact construction plus exhaustive returned-scheme verification |

The XOR joins use packed shared `u32` fingerprint and hash-table storage on
both the Tungsten host and Metal device. Host helper annotations must remain
`u32[]`; declaring these buffers as `i64[]` changes optimized host indexing to
an eight-byte stride and does not match the Metal `uint` ABI. The planted
6→5/7→6/8→7/9→8 and primitive-circuit regression test covers this layout as
well as exact admission.  The large-k kernels enumerate regular count⁴ tuple
spaces on Metal and cap the candidate family at 16 in campaign use; this is a
bounded Schroeppel–Shamir-style split, not an exhaustive rank proof.

The span joins are different: after choosing the live three- or four-term
window, every nonzero factor in each of its three GF(2) spans is enumerated.
The local tensor has at most `3³=27` or `4³=64` coordinates, so a single `i64`
is an exact tensor, including sign bit 63. The four-term worker keeps every
pair in a duplicate-preserving open-addressed table (about 101 MB at the
worst supported neighborhood) and lets Metal probe the exact complementary
signature. The host resolves the winning tuple, applies the splice, and runs
the full `n^6` coefficient gate before serialization. A miss is complete only
for the selected local span, not a lower bound for the global scheme.

The low-rank-shear worker instead exploits the fact that two shifted source
terms have a complementary two-factor matrix of rank at most two. One Metal
thread derives that factorization and tests the first carrier, scanning for a
second carrier only for rank two. Nonce rotation changes both the source-pair
window and carrier order. On the checked-in 5×5 rank-93/d1155 frontier, one
512-pair dispatch covers 285,696 tuples and finds the first verified
non-one-flip rank-neutral endpoint at pair 504. This is evidence for an escape
lane, not a rank or density improvement.

The global-kernel-shear child solves a different whole-frontier linear map:
each live term receives exactly one mutable axis, so simultaneous factor edits
have no quadratic remainder. On the 5×5 rank-93/d1155 frontier, 64 plans took
about 0.7–0.8 seconds and returned eight beyond-one-flip exact endpoints changing three or
four terms. None improved rank or density. Negative 4×4/6×6/7×7 scans keep the
mode 5×5-only and at one logical quantum; its value is basin diversity, not a
claimed objective gain. The child rejects direct one-flip endpoints but does
not claim a complete quotient by arbitrary flip sequences; ordinary archive
novelty and downstream reward remain the production test of basin value.

The constraint kernels use the Tungsten GPU atomics
`atomic_load_i32`, `atomic_store_i32`, `atomic_exchange_i32`,
`atomic_fetch_add_i32`, and `atomic_min_i32`.  Persistent walkers publish new
device-wide score minima into an atomic ring during one dispatch.  The host
examines ring winners after the bounded epoch; no unsafe cross-threadgroup
barrier is assumed.

## CPU and archive companions

One CPU island (only when at least two CPU walkers exist) is the core/fringe
control.  Consensus terms are placed in stable low-numbered slots and are
excluded from both sides of every flip; an `n²`-term fringe remains mutable.
The other islands retain their ordinary sticky doors.

A 64-cell MAP-Elites archive separates exact states by rank debt, C3 closure,
density band, flip connectivity, and factor-reuse signature.  Pool surgery and
lifted-identity modes draw least-used niches from this archive.  Best+1 and
best+2 CPU returns additionally feed online survival statistics; after eight
completed trials a tier with under 12.5% returns receives half dwell, while a
tier above 50% receives 1.5× dwell.

On 5x5, one quarter of lifted-identity launches first enumerate at most 256
minimal five-factor circuits and test their exact dependency-median shoulders.
Only a full-gated `+1` endpoint replaces the ordinary lifted split. A matched
240M-move screen showed higher descendant novelty than generic `+1` splits,
while 4x4 produced no endpoint and 6x6/7x7 only produced `+2` debt. The
existing pool row therefore carries the experiment without changing the TUI;
the complete evidence is in `PROJECTIVE_CIRCUIT5_TUNNEL.md`.

## Reproduction smokes

```sh
# Policy, lifted identities, MAP-Elites, core/fringe, and rank-debt controls.
bin/tungsten -o /tmp/flipfleet-kernel-pool-test \
  benchmarks/matmul/metaflip/flipfleet_kernel_pool_test.w \
  --release --native --fast --lto
/tmp/flipfleet-kernel-pool-test

# Synthetic rank-valid/exact-invalid candidate, syndrome decoding, immutable
# seed/candidate replay bundle, launch nonce, and explicit counter summary.
bin/tungsten -o /tmp/flipfleet-gpu-reject-test \
  benchmarks/matmul/metaflip/flipfleet_gpu_reject_test.w \
  --release --native --fast --lto
/tmp/flipfleet-gpu-reject-test

# Exact reject-syndrome reconstruction and bounded safe-axis repair.
bin/tungsten -o /tmp/flipfleet-syndrome-repair-test \
  benchmarks/matmul/metaflip/flipfleet_syndrome_repair_test.w \
  --release --native --fast --lto
/tmp/flipfleet-syndrome-repair-test

# Clustered 4x4 frozen-fringe query construction plus the bounded worker ABI.
bin/tungsten -o /tmp/flipfleet-frozen-fringe-test \
  benchmarks/matmul/metaflip/flipfleet_frozen_fringe_sat_test.w \
  --release --native --fast --lto
/tmp/flipfleet-frozen-fringe-test
bin/tungsten -o /tmp/flipfleet-frozen-pool-test \
  benchmarks/matmul/metaflip/flipfleet_frozen_fringe_sat_pool_test.w \
  --release --native --fast --lto
/tmp/flipfleet-frozen-pool-test

# Planted exact 6→5, 7→6, 8→7, 9→8 and primitive-circuit joins.
TUNGSTEN_LL_PATH=benchmarks/matmul/metaflip/flipfleet_kxor_pool_test.ll \
  bin/tungsten -o /tmp/flipfleet-kxor-pool-test \
  benchmarks/matmul/metaflip/flipfleet_kxor_pool_test.w \
  --release --native --fast --lto
/tmp/flipfleet-kxor-pool-test

# Distant-parent hybrid surgery, including the one-CPU-child ABI.
TUNGSTEN_LL_PATH=/tmp/flipfleet-parent-diff-test.ll \
  bin/tungsten compile --release --native --fast --lto \
  -o /tmp/flipfleet-parent-diff-test \
  benchmarks/matmul/metaflip/flipfleet_differential_pool_test.w
/tmp/flipfleet-parent-diff-test

# Complete exact 3/4-term span refactors, including all five directions,
# signature bit 63, duplicate pair signatures, and a full GPU-splice gate.
TUNGSTEN_LL_PATH=/tmp/flipfleet-span-pool-test.ll \
  TUNGSTEN_METAL_PATH=/tmp/flipfleet-span-pool-test.metal \
  bin/tungsten -o /tmp/flipfleet-span-pool-test \
  benchmarks/matmul/metaflip/flipfleet_span_refactor_pool_test.w \
  --release --native --fast --lto
/tmp/flipfleet-span-pool-test /tmp/flipfleet-span-pool-test.metal
# Compile the emitted Metal source to a metallib using the normal
# flipfleet_metallib_cache helper, then pass source/metallib as argv 1/2.

# Exact low-rank correction absorption: planted rank two plus the real 5x5
# pair-504 endpoint, deterministic host materialization, and full n^6 splice.
TUNGSTEN_LL_PATH=/tmp/flipfleet-low-rank-shear-pool-test.ll \
  TUNGSTEN_METAL_PATH=/tmp/flipfleet-low-rank-shear-pool-test.metal \
  bin/tungsten -o /tmp/flipfleet-low-rank-shear-pool-test \
  benchmarks/matmul/metaflip/flipfleet_low_rank_shear_pool_test.w \
  --release --native --fast --lto
/tmp/flipfleet-low-rank-shear-pool-test \
  /tmp/flipfleet-low-rank-shear-pool-test.metal

# Compiler/runtime Metal atomic smoke.
TUNGSTEN_LL_PATH=spec/core/metal_atomic_spec.ll \
  bin/tungsten -o /tmp/metal-atomic-spec spec/core/metal_atomic_spec.w \
  --release --native --fast --lto
/tmp/metal-atomic-spec
```
