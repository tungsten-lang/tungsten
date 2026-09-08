# Native incremental pair composition — 2026-09-08

This records the initial `d851dc7c` milestone. The subsequent
[paged queue and native leaf upgrade](NATIVE-COMPOSITION-PAGES-2026-09-08.md)
retains the same exact admission boundary.

Implementation milestone, not a new rank record. Refinement inputs and outputs
now trigger a native composition queue in ordinary square/rectangular fleets.
The old standalone 7x7 composer is unchanged.

## Exact boundary

- Candidate identity includes the ordered shape and complete sorted terms,
  including rank-tied representations. No rank-only parent deduplication.
- The bounded strategy forms disjoint equal-factor pairs separately on all
  three axes. The other two dimensions scale by 2, 3 or 4. Only recipes beating
  this parent's naive Kronecker expansion are scheduled; that is a heuristic
  family restriction, not an exhaustive lower-bound prune.
- Small leaves are verified 2x2x2/r7, 2x3x3/r15 and 2x4x4/r28. The r15 leaf is
  projected and exactly compressed from the packaged Peterson block15+11
  2x3x5/r26 seed; r28 is four disjoint Strassen blocks. No new imported assets.
- Every task names immutable parent/leaf hashes, axis, scale, target and formula
  rank. Materialization reloads and verifies both inputs, checks the formula,
  expands the exact linear maps, removes zero/duplicate terms over GF(2), then
  verifies every tensor coefficient, including off-support entries.
- Native little-endian 32-bit limbs allow up to 1,024-bit factors/16,384 terms.
  Verification uses one U-fiber at a time and bounded scratch. Its 20-million
  limb-XOR budget returns a distinct unverified state on exhaustion.
- MFW1 objects use canonical lowercase hex. Hashes locate objects but do not
  certify tensor identities. All rank ties survive immutable archive admission;
  the per-shape best file is advisory and never an admission cutoff.

## Scheduling and recovery

Composition intake completes before the refinement manifest is committed.
Each full parent is processed once for this fixed leaf-library version.
Durable FIFO tickets retain all overflow. Two expansions follow each input;
idle batches expand four. Only one low-priority native child runs at a time.
The UI reads counters at low cadence, never wide tensor verification.

Stop is cooperative between proposals, projections and expansions; pending
work remains pending. Task/index/cursor recovery is idempotent. Invalid or
over-budget head tasks remain pending, emit an error and pause automatic
composition; ordinary flipping/refinement continues. Storage is not byte-capped.

## Focused evidence

- Packed test covers 31/32/63/64/65/1,024-bit boundaries, full identity checks,
  off-support corruption, zero-term removal, duplicate parity, bounds and
  operation-budget exhaustion.
- Independent Python uses arbitrary-size integers and separate coordinate maps.
  72 parent/axis/scale cases match complete term sets and full tensor identities.
  This includes non-injective maps, 63-bit parent masks and large redundant
  parent buckets.
- Queue test checks exact leaf generation, parent/task deduplication, a crash
  between ticket/index/counter writes, stop/restart, replay after a lost cursor,
  and refusal to admit a forged rank price.
- External r94 regression runs the complete native projection/queue/expansion
  chain: 105 recipes independently expanded and checked, including 4x7x4/r85
  to 12x7x12/r651. The imported parent remains outside the distributable tree.
- Public CPU-only 5x5 and 2x5x6 tests consume composed outputs, verify every
  completed recipe independently, resume pending work and leave no owned child
  process after shutdown. A two-second 5x5 replay completed 12/945 composition
  recipes; its backlog is explicit, not counted as verified work.
- Existing asynchronous interrupt/raw-TUI reset checks pass, including final
  CPU intake and independently checked persisted tensor identities.

Focused commands, repository root:

```sh
bin/tungsten-compiler compile bits/tungsten-metaflip/spec/packed_composition_test.w \
  --out /tmp/metaflip-composition-test --release --native --no-lto
python3 -B bits/tungsten-metaflip/spec/packed_composition_parity_test.py \
  /tmp/metaflip-composition-test [EXTERNAL_4x7x4_R85]
python3 -B bits/tungsten-metaflip/spec/composition_queue_test.py \
  /tmp/metaflip-composition-test [EXTERNAL_4x8x4_R94]
python3 -B bits/tungsten-metaflip/spec/refinement_fleet_test.py \
  bits/tungsten-metaflip/bin/metaflip
```

## Remaining scope

This is parent-triggered composition with a fixed exact leaf library, not the
whole offline closure engine. Larger/mixed shared groups, better-leaf reverse
dependency updates, recursive wide composition, storage compaction and launching
cross-shape fleets remain open. No new world-record or throughput claim follows
from replaying the previously known rank-651 construction.

## Bounded resource canary

Public release/native binary SHA-256:
`afa17bcbf3bab0726a2d614da41b6bb8e7c792bd245fddaf8c4328cab88c2b00`.

Two low-priority CPU-only 5x5 runs used two islands, 500,000-step epochs and
a 15-second search limit. Refinement/composition was disabled, then enabled.
This is a resource/safety canary, not a matched-attempt performance experiment:
seed feedback changes the walks, and a focused compiler job overlapped part of
the first run. Do not infer a speedup or a regression rate from these timings.

| Mode | Reported moves | Sampled main peak KiB | Sampled total owned peak KiB |
| --- | ---: | ---: | ---: |
| Disabled | 855,749,103 | 22,432 | 22,432 |
| Enabled | 818,333,738 | 29,328 | 34,288 |

Enabled completed 15/15 refinement jobs and 78/3,078 composition recipes, with
eight seed uses and zero failures. All 78 completed recipes were independently
replayed after exit. The 3,000 pending recipes were not counted as verified.
The spool had 7,479 files / 6,581,027 logical bytes; both temporary run spools
were removed after checks. No owned worker survived shutdown. Sampling every
roughly 0.4 seconds does not bound shorter child-memory peaks or prove a long-run
memory plateau. The backlog/file count makes priority scheduling and compact
storage the next engineering bottleneck; default runs remain storage-unbounded.

All 314 runtime digests and 165 source-manifest entries match the tracked
runtime inventory plus these four added modules. Generated GPU sidecars are
excluded; unrelated compiler/GPU edits were preserved.
