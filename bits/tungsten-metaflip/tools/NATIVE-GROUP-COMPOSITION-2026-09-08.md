# Native shared-factor groups — 2026-09-08

Follow-up to `73a28bd0`. Ordinary MetaFlip now considers larger fixed-axis
shared-factor groups during automatic background refinement. This closes
part of the offline composition gap; it is not a new rank record.

## Bounded native construction

At scales three/four, `composition/groups.w` partitions each equal-U, equal-V
or equal-W bucket with a dynamic program over exact leaves of sizes 1..6.
Singletons and pairs are included, so the chosen predicted rank is no worse
than pair-only pricing. Equal costs prefer the larger leaf, which may produce
a different useful rank-tied representation. The DP is optimal only for this
fixed-axis disjoint-bucket family and these leaf costs. It does not optimize
mixed-axis or overlapping groups. Scale two retains the existing pair path.

`composition/group_bank.w` constructs and fully verifies the six leaves from
packaged witnesses and exact disjoint-row sums. There are no new runtime
Ruby/Python dependencies, downloaded seeds or redistributed external tensors.

| Scale | Costs for group sizes 1, 2, 3, 4, 5, 6 |
| --- | --- |
| 2 (test bank) | 4, 7, 11, 14, 18, 21 |
| 3 | 9, 15, 23, 29, 36, 44 |
| 4 | 16, 26, 38, 47, 60, 73 |

The scale-three size-six leaf is a rank-44 block sum of the size-two and
size-four witnesses. Full bank manifests bind all six leaf identities.
Materialization reloads and full-tensor-checks every member before using its
actual rank. Hashes and cost formulas are not verification gates.

`MCG1` recipes reference a bank; `MFC1` retains the original pair replay.
One recipe is chosen per axis/scale, so each parent still submits at most
nine recipes and the backpressure reservation remains valid. The new parent
marker stores nine recipe identities, allowing unchanged pair-only axes to
remain unchanged after a larger-leaf update. Old recipes/results and bank
manifests remain immutable. A changed pair leaf rebuilds its bank and causes
selective repricing when a parent is re-offered, not a global dependency scan.
`METAFLIP_COMPOSITION_GROUPS=0` selects the pair-only control for new intake;
it does not disable replay of grouped recipes already queued.

Mapped outputs still pass the complete packed tensor gate before archive
admission. Width, rank and verification-work limits are unchanged. Wide
witnesses are archived; recursive wide search and automatic cross-shape
worker dispatch remain open. This change does not alter hot CPU/GPU flips.

## Exact regressions and fault injection

- Native plan tests cover an 80-member bucket, partition coverage, cost,
  invalid dimensions/axis, truncated slabs and invalid leaf costs.
- Independent Python integer algebra verifies all 18 bank leaves and 90
  composed outputs, comparing the entire canonical term set and tensor
  identity. Cases include all three axes/scales, large buckets, duplicate
  terms, non-injective factor maps, singleton axes and wide outputs.
- The unchanged packaged `2x2x8/r28` parent yields `8x8x8/r329`, versus
  pair-only rank 364. This reproduces a known retained construction.
- The queue upgrade starts with three pair recipes and adds two grouped
  recipes. It preserves the old records and survives interrupted intake.
- Five negative cases reject a forged price, corrupted bank bytes, missing
  member, wrong-shaped member with a valid manifest hash, and a false tensor
  with the correct shape and freshly recomputed hashes. None is admitted or
  advances the completion cursor. A changed valid same-rank pair leaf only
  reprices scale-four work and leaves previous bank bytes intact.
- Existing paged/legacy queue, 128-ticket fairness, duplicate/restart and
  same-rank repricing checks pass. The external r94 projection regression
  still produces 105 fully replayed recipes including ranks 651 and 1,132.
- The matched FIFO/priority replay ends with identical verified output sets.
  Priority reaches r1132 at completion 4 vs 48 and r651 at 8 vs 47. These are
  workload-specific ordering results, not a universal throughput claim.
- Backpressure still defers without derived writes, resumes after draining,
  handles a lost submitted cursor and distinguishes errors from deferrals.
  Its coordinator check ends with 1/1 source and 22/1,032 compositions done,
  1,010 pending, zero failures and no lost input.
- Public 5x5 and 2x5x6 runs, rectangular restart and disabled refinement pass.
  Their complete narrow objects and finished compositions verify independently.

Focused replay, from the repository root:

```sh
bin/tungsten-compiler compile bits/tungsten-metaflip/spec/group_composition_test.w \
  --out /tmp/metaflip-groups --release --native --no-lto
python3 -B bits/tungsten-metaflip/spec/group_composition_parity_test.py /tmp/metaflip-groups
bin/tungsten-compiler compile bits/tungsten-metaflip/spec/packed_composition_test.w \
  --out /tmp/metaflip-group-queue --release --native --no-lto
python3 -B bits/tungsten-metaflip/spec/group_composition_queue_test.py /tmp/metaflip-group-queue
python3 -B bits/tungsten-metaflip/spec/composition_queue_test.py /tmp/metaflip-group-queue
```

Runtime inventory: 171 source entries and 320 matching file digests.
Public release/native binary SHA-256:
`baf1d83c367db18e84dd50cc5d6a23f78311a7a4985ba3adb08007ad422cd6e7`.

## Bounded canary and parent screen — no new best-known shape

A 15-second low-priority CPU-only canary used one worker and a 1,269 pending
limit. It reported 1,119,617,024 moves, 5/12 source jobs and 70/1,161
compositions completed, three feedback seed uses and zero failures. All 148
narrow objects and 70 finished compositions verified. At 50ms sampling, the
309 samples saw backpressure and a peak of 1,143 pending compositions. Seven
originals and 1,091 compositions remained pending at clean shutdown. The
temporary spool held 643 files / 4,852,134 logical bytes and was removed after
verification. No child survived. This is not a matched throughput comparison.

`native_group_screen.py` replayed the frozen 168-parent projection corpus.
121 parents fit the native 63-bit-per-factor gate; 47 were explicitly outside
that scope. There were no duplicate parents. Native intake emitted 831
recipes. Independent bucket DP found 124 strict improvements over pair-only
pricing across 64 dimension-sorted targets, but **zero prices below the
retained comparison table**. The best pair-price saving was 28 terms for a
24x24x8 target: 3,206 to 3,178, still above retained rank 2,632.

This screen validates input/leaf tensors and predicted prices; it does not
claim full expansion of all 831 recipes or a search exhaustion theorem.
Its temporary queue is removed, with only the compact JSON report retained
outside the repository. Reproduction inputs:

- parent corpus SHA-256: `602dc282357928af098eeb556dd31588dbc33363d7b9b09e0e2cc177ee390fb5`
- retained prices SHA-256: `5a283ebd193c37f4246a0e3fb00cd095d3159b05e13ce6f401439dc076a9c721`
- test binary SHA-256: `8a24ec0e886521062b5c0699bfe099447ad5ead06008003cd2bb9c8053cb8e7d`

No new seed, world-record claim, unbounded search, GPU workload, publication
or push accompanies this integration.
