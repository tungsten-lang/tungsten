# GF(2) record hunt, 2026-09-26 to 2026-09-29

A cold campaign outside the live fleet: exact GF(2) tensors, compared against four public
rank tables, found by composing, projecting and walking. **The tensors are not in this
directory.** They are release assets of the private
[`tungsten-lang/metaflip-archives`](https://github.com/tungsten-lang/metaflip-archives)
repository, tag `evidence-2026-09-29` (see "Where the tensors are"). This package keeps the
search and verification tools and this write-up.

Every counted tensor was expanded against the complete matrix-multiplication tensor by the
package gate. The independent Ruby reconstruction (`tools/verify_tensor.rb`) then re-expanded
all 691 record tensors held in the archive assets and all 661 chain heads of the four lineage
bundles (the last tensor of each chain), plus the four live-fleet checkpoints: every one exact, at
the indexed rank. The other 102 record tensors are certificates already committed under
`tools/certificates/`. Comparison ranks are comparison data, not certificates. Nothing here is an
optimality claim or a completed novelty audit: under `RECORD_POLICY.md` these are **apparent**
GF(2) upper bounds.

## Standing on 2026-09-29

Scored against Lille `fmm_digest` `9f26324` (2026-09-28), matmulcatalog `f0c2ba9` (2026-09-29,
commutative entries excluded), FastMatrixMultiplication `613599b` (2026-09-28) and fmm-schemes
`8fa0f2a` (release 1.1, 2026-09-27); the exact revisions are in the archive's `comparators.json`.

| Class (best verified local witness per shape) | Shapes |
|---|---:|
| Below every listed rank in any ring | **733** |
| Below every listed GF(2)-valid scheme, but an equal or lower rank is listed for another ring or an unspecified field | **62** |
| Tie the best listed rank | 1,413 |
| Above it | 1,454 |
| Shapes with a verified witness (of 5,456 with every side at most 32) | 3,662 |

That is **795 record shapes**, 235 more than at the start of 2026-09-29 on the same tables, none
lost, and 49 earlier records lowered further. 734 of the 795 have a side above 16, where the listed
ranks are mostly composition-based; a large margin there says the listed number is weak, not that
the walk found something deep. Of the 235 new ones, 200 are below every listed rank (margin 1 to
138, median 11; 60 by at most 3 and 30 by at least 50) and 35 are GF(2)-valid-only records.

For 458 of the 733 no GF(2)-valid scheme is listed at all, so the any-ring rank (usually the Lille
digest's, which gives a rank and format but not the field) is the only comparator. Of the 62
GF(2)-valid-only records, 55 are matched or beaten by a rank the Lille digest lists for an
unspecified field and 7 by a matmulcatalog scheme over another field. For 17 of the 62 a Perminov
rational scheme sits at or below our rank; all 17 use even denominators (1/2, 1/4, 1/8), so none
reduces mod 2.

### How the records were reached

The chain behind each witness, from the archive's lineage bundles:

| Chain | Records | Of which new today |
|---|---:|---:|
| Closure product (block sum / Kronecker product of exact witnesses), no search | 203 | 52 |
| July 2026 block-composition certificate, as archived | 151 | 0 |
| Certificate from the September campaign, as committed | 126 | 0 |
| Closure product, projected, then walked | 106 | 85 |
| matmulcatalog recipe replayed over GF(2), then walked | 58 | 38 |
| July certificate, projected | 36 | 0 |
| matmulcatalog recipe replayed over GF(2), no walk | 24 | 4 |
| Committed certificate, projected, then walked | 23 | 14 |
| July certificate, projected, then walked | 15 | 14 |
| Closure product, projected | 15 | 5 |
| matmulcatalog replay, projected, then walked | 12 | 12 |
| Closure product, walked | 8 | 7 |
| Committed certificate, projected | 8 | 3 |
| Public ternary seed reduced mod 2, then walked | 5 | 0 |
| matmulcatalog replay, projected | 1 | 1 |
| Live fleet checkpoints (7x7x7/247, 9x9x9/482, 13x13x13/1402, 15x15x15/2006) | 4 | 0 |

287 of the 795 have a walk or projection in their chain. Closure products are mechanical
consequences of already-public leaves (AlphaTensor's GF(2) 4x4x4/47 times a Perminov scheme, and
so on); count them separately from searched results.

Largest new margins below the best listed rank: 24x31x32 at 12297 (12435 listed), 16x20x23 at 4132
(4260), 16x23x28 at 5656 (5784), 19x27x28 at 7856 (7983), 16x27x32 at 7447 (7568). Among smaller
shapes, 10x13x14 at 1150 (1152 listed) and 11x13x15 at 1363 (1364 listed) are below every rank in
any ring; 9x9x9 at 482 (486 listed) was reached by the live fleet on 2026-09-12 and now also has a
replayable public-seed lineage.

## The public tables moved under the search

All four sources changed between 2026-09-26 and 2026-09-29. fmm-schemes release 1.1 lowered
13x14x16 to 1806, 9x14x16 to 1260 and 11x15x16 to 1641 and tied 8x11x16 (906) and 11x15x15 (1547).
Four of the ten shapes in the first bundle of this campaign (13x14x16, 9x14x16, 8x11x16, 11x15x15)
therefore stopped being GF(2)-valid records in that bundle's form; the bundle is kept in the archive
as history. Two of the four have better witnesses from later chains (8x11x16 at 889, 13x14x16 at
1763 from a July certificate); 9x14x16 (1260) and 11x15x15 (1547) only tie. One 200M-move walk
from a fmm-schemes seed took 11x14x14 from 1373 to 1372 and 9x11x13 from 840 to 836. The
comparison is a race: rescore against fresh tables before quoting any of these.

## Tools added

| Tool | Purpose |
|---|---|
| `screen_public_ternary_gf2.py` | Reduce public ternary/integer schemes mod 2 into exact seeds (ring from the file-name suffix, never the directory) and walk them with `wide_rect_walk.w`; walks resume by seed content hash |
| `mmc_gf2_alg.py`, `mmc_gf2_replay.py`, `mmc_gf2_seeds.py` | Replay matmulcatalog composition recipes over GF(2), pinned to one catalogue revision, with per-tensor attribution; a recipe the catalogue stamps F2 but that needs a Q/F3-only leaf is recorded as a failure, not emitted |
| `gf2_record_board.py` | Score every verified local witness against the four tables (verification cached by SHA-256, run in parallel) |
| `build_gf2_lineage_bundle.py`, `verify_gf2_lineage.py` | Write and verify lineage bundles: exact tensors, parent links, re-derivation of seeds from the pinned upstream file, replay of basis/projection steps, byte-identical native walk replay |

Specs: `spec/public_ternary_gf2_test.py`, `spec/mmc_gf2_alg_test.py`, `spec/mmc_gf2_replay_test.py`,
`spec/verify_gf2_lineage_test.py`, `spec/build_gf2_lineage_bundle_test.py`.

The campaign drivers that sat between these tools (closure pricing and materialization,
projection screening, child selection, iterative deepening, chain collection) are in the archive's
`gf2-campaign-records` asset under `scripts/`. They carry scratch-directory assumptions and are
**not yet promoted** into this package.

## matmulcatalog derived recipes over GF(2)

373 shapes had a matmulcatalog "derived" recipe stamped F2 that beat the other sources' best rank.
Replaying the lineage operations over GF(2) gave 263 exact tensors and 110 failures: each failure
depends on a leaf whose cheapest catalogue scheme is valid over Q or F3 only (3x3x6 is 40 over Q
but 42 over GF(2), affecting 30 targets; 3x3x8 55/56, 13; 2x4x5 32/33, 11). The catalogue's F2
stamp therefore over-claims for those recipes, and comparisons against its F2 minima are
conservative. The replay tool reproduces the first pass's 263 successes and 110 failures exactly;
216 of the 263 tensors are byte-identical and the other 47 are equal-rank variants or the five seeds
the first pass built with local witnesses as leaves. A second pass at the 2026-09-29 revision
replayed 979 targets into 835 exact tensors (144 failures).

A replay is now a pure function of the catalogue revision and the file. It was not: the disk cache
stores sorted terms while a freshly computed scheme kept its insertion order, and the bud and
recombination constructions index terms by position, so a result depended on which files an earlier
replay in the same cache had materialized. Only which equal-rank tensor came out varied: 43 of the
1,098 seeds of the two passes (35 and 8) differ from what an empty cache gives now, none in rank and
none in the success counts above. `materialize_file` sorts terms before memoizing, the replay spec
pins it, and the 11 replay seeds of the searched-records bundle that an empty cache does not
reproduce are marked `rederivable: false` (still exact and attributed).

## Finite negatives

- Of the 298 rational (`_Q`) schemes in FastMatrixMultiplication `613599b`, 278 use an even
  denominator (1/2, 1/4, 1/8) and do not reduce to GF(2). The other 20 use odd denominators only
  (19 small `serendipitous_base` shapes and 9x14x15/1182 with denominator 3) and would reduce mod 2,
  but none is below our witness for its shape (ties, or ours is lower).
- Walking 801 replayed matmulcatalog seeds that sit exactly at the listed rank dropped 38 of them
  (5%) at 40M moves; the rest tied.
- Walks of closure products at 40M moves: 2 of 433 from seeds below rank 2,000 dropped (10x12x23
  1718 to 1717, 3x27x31 1843 to 1842), against 27 of 261 from larger ones.
- Projection of the newest 118 parents produced 345 children over 316 distinct shapes, of which 4
  were worth walking: the projection cascade has converged on this witness set.
- The live fleet's baseline packed walker also reaches 9x9x9/482 from Perminov's 486 within 90 s,
  so that basin does not favour the directed walker.
- 162 alternative Perminov schemes for 123 shapes (the same rank as the best, or one or two above),
  100M moves each: 3 walked down to the best public rank and none below it.

## Where the tensors are

`tungsten-lang/metaflip-archives`, release `evidence-2026-09-29` (private):

| Asset | Contents |
|---|---|
| `2026-09-29-gf2-searched-records.tar.gz` | Lineage bundle: every record whose chain has a walk or projection, plus matmulcatalog replays and public seeds, from seed to retained tensor |
| `2026-09-29-gf2-closure-products.tar.gz` | The 203 closure-product records, each with its recipe |
| `2026-07-block47-certificates.tar.gz` | The 186 July block-composition certificates removed from this tree in `47ad44dc5`, as `archived` rows re-derivable from git history |
| `2026-09-26-gf2-public-ternary-walks.tar.gz` | The ten-shape bundle from the first day of the campaign, kept as history |
| `2026-09-29-gf2-campaign-records.tar.gz` | `records.tsv` (every record shape and the asset that holds its tensor), scoreboards, comparator revisions, walk logs, seed manifests, campaign scripts, fleet checkpoints, and a snapshot of this package (`metaflip-tools-<commit>/`, without `tools/certificates/`) |

Verify a bundle with `python3 tools/verify_gf2_lineage.py BUNDLE --source NAME=CLONE ...`; see the
docstring for which rows re-derive from which source. The snapshot in the campaign-records asset
runs the verifier without this branch; `retained` rows additionally need a checkout that has
`tools/certificates/` (`--repo-root`).

## Attribution

Tensors derived from public schemes carry the credit of their sources in each row's `details`:

- [Perminov, FastMatrixMultiplication](https://github.com/dronperminov/FastMatrixMultiplication)
  (MIT; Andrew I. Perminov and the authors the catalogue cites).
- [MerlijnW70, fmm-schemes](https://github.com/MerlijnW70/fmm-schemes) (CC BY 4.0).
- [solven-eu, matmulcatalog](https://github.com/solven-eu/matmulcatalog) (arXiv:2606.13408; no
  licence file). Each replayed tensor lists the catalogue file, revision and lineage, and every
  atomic scheme it depends on with the catalogue's recorded source and year: Perminov, AlphaTensor
  (Fawzi et al., 2022), AlphaEvolve (Novikov et al., 2025), Hopcroft and Kerr (1971) and others.
- Sedoglavic's Lille catalogue is used for comparison only.

The project owner's decision (2026-09-29) is that tensor decompositions are treated as mathematical
objects rather than licensable expression; attribution is kept regardless. Repository size is the
separate reason the tensors live in the archive rather than in this package.

## Open items

- Promote the campaign drivers into this package with parameters instead of scratch paths.
- Promotion of any result into `tungsten-metaflip-results` needs the prior-art audit and
  attribution review its `RECORD_POLICY.md` requires.
- The closure, deepening and projection queues were stopped at the owner's request: 638 of 713
  closure walks and 495 of an open-ended deepening run had finished. Results beyond this snapshot
  exist only as further walk logs.
