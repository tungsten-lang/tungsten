# Native composition: paged storage and rank-26 leaf — 2026-09-08

This records `0fc7038c`; the subsequent
[priority scheduling audit](NATIVE-COMPOSITION-PRIORITY-2026-09-08.md) covers
out-of-order completion and its restart protocol.

Follow-up to `d851dc7c`, not a new world-record claim. Ordinary MetaFlip already
feeds exact inputs and refined outputs into native pair composition. This
change reduces its small-file cost and strengthens its scale-four leaf.

## Native leaf construction

An independent screen tried 429 projections of packaged small seeds. The
best 2x4x4 projection had rank 27: remove Z coordinate 2 from the packaged
2x4x5/r33 catalog seed, then run exact pair and shared-matrix cleanup.

A bounded native scout ran 16 trials of 32 x 65,536 attempted moves, observing
every 4,096 moves with rank debt 2. Of 33,554,432 attempts, 4,512,586 flips were
accepted. Two trials reached rank 26 (densities 223 and 233); the other fourteen
remained rank 27. The scout reported 0.569 seconds on one low-priority CPU,
without a GPU. This is one search result, not a general throughput benchmark.

Production `composition/leaf_walk.w` replays only trial four's first eight
chunks: 524,288 attempts, with seed `19 + 4*104729 + chunk*8191`. It retains
rank/density endpoints and fully verifies every retained tensor. The resulting
canonical MFR1 tensor is 2x4x4/r26/d223, hash:

`7094276aa856a9efa625b5adcd22601eaa3a230d078bf180b6036f6a198c58b5`

An independent full-term comparison matched the scout's winner, whose raw
file hash is `0eacb0003591577c6a22ccbe35f549a3c82d74a08e1f931e3a74b67e6053b4ef`.
The production leaf is cached only after the complete tensor check. No new
imported seed asset, Ruby/Python runtime dependency, or live-shape allowlist
entry is needed. Stop is checked between observations; cancellation is not
reported as a failed refinement.

For the external 4x7x4/r85 parent with 38 pairs and nine singletons on the
useful axis, this changes the scale-four price from
`38*28 + 9*16 = 1208` to `38*26 + 9*16 = 1132`. The entire 16x7x16/r1132
tensor, not just that arithmetic, is independently expanded and verified.
Scale three still verifies 12x7x12/r651. These reproduce known local bounds;
there is no new primitive rank record or public novelty claim.

## Bounded record pages

`composition/pages.w` writes at most 64 task/result records per page. Records
are newline-terminated, 2..256 bytes, with no embedded newline. A bounded
header records the first sequence, count and SHA-256 of the payload. Reads
check the block boundary, payload digest, exact line count and lengths.
Writes atomically replace the page only for its next sequence or an identical
replay; conflicting rewrites and gaps are rejected. A payload hash is not a
tensor certificate: every composition still reloads its inputs and crosses
the full coefficient gate.

Legacy `tasks/N`, `results/N` and `by-id/HASH` files remain readable. New pages
can start midway through a block after a legacy prefix. Existing evidence is
not automatically deleted or rewritten. New recipes omit the per-task hash
index; the single writer recovers the at-most-nine-recipe in-flight parent
suffix by complete record bytes. A damaged/missing counter beyond that bounded
recovery window fails visibly rather than silently acknowledging work.
The suffix is loaded once per parent; including new records, its local cache
holds at most 18 records. Appending loads the current page only once. This
avoids repeatedly reading/hashing the same page inside each recipe's dedup scan.

Parent markers now contain all three leaf hashes. When a parent is offered
again, unchanged scales are skipped and changed scales get new exact recipes.
Old tasks retain their original immutable leaves. This is selective re-offer
repricing, not a global reverse-dependency sweep.

## Focused verification

- Native page tests cross sequences 64/65 and 128/129, retain a 37-record
  legacy prefix, and reject oversized/multiline/empty/conflicting/gapped writes.
- Queue tests cover interrupted intake, lost completion cursors, old r28 leaf
  migration, legacy result prefixes, same-rank changed-leaf repricing, stop,
  corrupted page hashes, and forged prices with correctly recomputed hashes.
- 72 independent generic packed-composition cases still match complete term
  sets and tensor identities, including limb boundaries and non-injective maps.
- The external r94 projection chain generates 105 recipes, all independently
  replayed, including r651 and r1132. Its queue bookkeeping needs four pages
  instead of the previous 315 task/index/result files. Tensor objects and
  provenance are not dropped to obtain this reduction.
- Rebuilt public release/native binary:
  `cdc6d7090f71321fb0c152c318c734ff211e0786c581e3812fd857530720931c`.
  Focused public tests verify 112 narrow 5x5-run objects, 12/981 compositions,
  and one feedback seed; rectangular restart advances 6/96 to 10/96. Disabled
  refinement creates no spool. Async interrupt and raw-TUI reset checks pass.
- All 316 runtime digests and 167 source-manifest entries match the tracked
  runtime plus the two new modules. Generated GPU sidecars are excluded.

The replay commands are unchanged from the initial audit. The generic packed
test still deliberately includes the old valid rank-28 leaf; the queue test
exercises the generated rank-26 leaf as well as the upgrade path.

## Short storage canary

One low-priority, CPU-only 5x5 run used `-J 1`, 65,536-step epochs and a
15-second limit in a temporary isolated state directory. It reported
686,161,920 moves, completed 18/19 refinement jobs and 80/3,456 compositions,
used eight feedback seeds, and had zero composition failures. All 395 narrow
objects and all 80 completed compositions were independently checked after
exit; no owned child survived shutdown. The temporary spool was removed.

The spool held 1,457 files / 6,837,671 logical bytes. Its task/result bookkeeping
used 56 pages; the same submitted/completed counts in v1 would require
`2*3456 + 80 = 6992` task/index/result files. This comparison holds the work
counts fixed; it is not a speedup claim.

About 0.4-second process sampling (33 live samples) observed peaks of
29,216 KiB for the main process and 42,416 KiB for all owned processes. An
earlier paged prototype without the bounded suffix cache sampled 29,392 /
96,800 KiB while completing 60/3,840 compositions (35 live samples; binary
`d8281b56311c3eb82dab1faf84220d78a9d3b5f8a07c66c964cf8a439378a1b1`).
That observation motivated removing the redundant reads. These runs consumed
different walks and job counts and are not a matched memory/performance
experiment; short sampling can miss child peaks and says nothing about a
long-run plateau. The original v1 canary also used a different worker count.

The remaining 3,376 compositions and one source job are pending, not
verified. Paging reduces filesystem entries, not the number of queued jobs or
the retained tensor volume. Priority/fairness scheduling, a disk-byte policy,
global changed-leaf propagation, recursive wide composition and cross-shape
fleet dispatch remain open. No unbounded search was left running.
