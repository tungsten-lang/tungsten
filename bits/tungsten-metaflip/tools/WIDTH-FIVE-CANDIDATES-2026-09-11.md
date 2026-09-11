# Nine checked GF(2) candidates from mixed-width blocks

Allowing width-five blocks in the per-slot construction produces nine new
**source-scoped candidates** below the freshly fetched Lille comparisons.
These are complete GF(2) witnesses, not established world records,
general-field algorithms, optimality proofs or redistribution clearance.

| Canonical shape | Previous retained | Checked rank | Fresh Lille |
| --- | ---: | ---: | ---: |
| 7x16x17 | 1,244 | **1,220** | 1,236 |
| 7x16x19 | 1,384 | **1,369** | 1,381 |
| 7x16x20 | 1,434 | **1,430** | 1,436 |
| 8x13x17 | 1,154 | **1,140** | 1,145 |
| 8x13x20 | 1,335 | **1,326** | 1,330 |
| 8x15x17 | 1,294 | **1,273** | 1,294 |
| 8x16x17 | 1,334 | **1,326** | 1,358 |
| 8x17x17 | 1,470 | **1,436** | 1,447 |
| 10x16x17 | 1,690 | **1,688** | 1,696 |

The retained column is a pinned local construction baseline, not a public
record. This batch improves **42** such local bounds; only the nine above
also beat the screened catalogue comparisons. They are distinct from the
[eight preceding candidates](PER-SLOT-LEAF-CANDIDATES-2026-09-11.md), giving
17 source-scoped candidate shapes across the two studies. No main square
such as 3x3, 4x4 or 5x5 improves.

## Construction and finite scope

The outer parent is the already checked 2x4x4/r26 representation. Enumerate
all **58,025** ordered width-3/4/5 allocations containing at least one five:
`3^10 - 2^10`. They cover **219** canonical target shapes. Each outer term
uses a checked leaf sized to its actual block extents.

The ten actual GF(2) leaf ranks are:

```
333:23 334:29 335:36 344:38 345:47
355:58 444:47 445:60 455:76 555:93
```

For each target, materialize the two lowest formula-price contexts, or the
single context when only one exists: **435 constructions** in total.
Every construction is expanded, exactly cleaned and fully verified. This
is exhaustive formula pricing, but only a heuristic shortlist for the
post-cleanup minimum; no claim covers unmaterialized contexts.

For example, 8x16x17 uses allocations `[4,4]`, `[4,4,4,4]`,
`[4,4,4,5]`. Eighteen slots use 4x4x4/r47 and eight use 4x4x5/r60:
`18*47 + 8*60 = 1326`. Similarly, 8x17x17 uses twelve rank-47,
twelve rank-60 and two rank-76 leaves, totaling 1,436.
All nine headline witnesses retain their nominal rank after embedding and
cleanup. Their gain comes from the mixed-width construction, not an
unreported primitive flip improvement.

Materialization completes in about 50.5 seconds with one low-priority CPU
worker and no GPU. This is a run observation, not a throughput benchmark.

## What the preceding negative searches established

The intervening width-3/4 study prices 2,149 additional multiple-clipping
allocations, then materializes and independently verifies 411 selected
contexts over 130 targets. Its sole retained-rank gain is 8x13x16/r1060,
which **does not** beat the live Lille rank 1,054.

For that shape, all 216 contexts from 27 outer presentations and eight
width-three placements verify without a further rank gain. They add 208
new full-object identities. A leaf follow-up checks 828 single moves,
then scores all 14,832 new ordered two-move words within one leaf and a
bounded 20,000 two-leaf proposals out of 329,508. It finds no lower rank;
one exactly reconstructed and fully verified endpoint reduces density
from 24,306 to 24,305. These finite negatives motivated changing the block
width family. The two-leaf shortlist is not an exhaustive search.

The cumulative identity rollup is:

```
11,520 previous + 411 multi-clip + 208 outer-basis
       + 1 density-only + 435 width-five = 12,575
```

This includes 166 original inputs, hence 12,409 non-input representations.
Identities include the ordered shape and complete tensor terms; these are
not isomorphism classes, records or transient scored proposals. Prior
identity/replay receipts are retained separately from this bundle's 435
independently replayed endpoints.

## Independent replay

The Python checker independently rebuilds all 58,025 allocations and their
prices from coordinate supports, checks shortlist coverage, reconstructs
each recipe's coordinate images, applies GF(2) parity, recomputes matrix
cleanup, and expands the entire tensor identity. Source and endpoint hashes
are checked. The native full verifier accepts every endpoint within the
20-million-work allowance; limited responses are not successes.

Both checkers reject a validly encoded one-bit corruption of each of the
nine candidates. Standalone replay from the copied evidence package passes:
435 recipes, 435 distinct new endpoints, nine corruptions rejected. It
also parses and validates the hashes/ranks in all nine saved fresh HTTP
responses. The native binaries and checker sources are pinned.

| Shape | Full MFW1 SHA-256 |
| --- | --- |
| 7x16x17 | `3b5910e5d5f3fbe15010586b0ef687568194bda6462090ee64c4c1d1155c0ec3` |
| 7x16x19 | `66ce4ff4d91df97a63fc452dadc14dc459a219b822db9e84cb14d401e7b827c3` |
| 7x16x20 | `1ab8e3baa0bfb300dfacabf81ee3e59a85f5e948f6beeb115ca249f757dd9a72` |
| 8x13x17 | `41e468d4b18701972b4ff77f993af70b1d5fd3bf6eafdd83918bbaf470c670fe` |
| 8x13x20 | `bbbc85a6c50542d5a9643d3eabb1fa59a159ae6141007a18be7b575a2cd010b5` |
| 8x15x17 | `52cd148e19859190be742a6f2f840a59ca25ec66ca39d73cfd11e51334b319a9` |
| 8x16x17 | `c01b612c3601ea79137481d5f510361bf3809d58b8f69dd339578d403422f858` |
| 8x17x17 | `820bb856d80537110b15f0827811e311ed7f3cb80879257ebd3163f44b3b6808` |
| 10x16x17 | `0a96870cbb3057ad05e6f6f06596454d72b093aab2b854571960e0df6615f95c` |

## Reference and retention boundaries

Fresh responses saved September 11, 2026 at 15:32 UTC give the table for
[7x16x17](https://fmm.univ-lille.fr/7x16x17.html),
[7x16x19](https://fmm.univ-lille.fr/7x16x19.html),
[7x16x20](https://fmm.univ-lille.fr/7x16x20.html),
[8x13x17](https://fmm.univ-lille.fr/8x13x17.html),
[8x13x20](https://fmm.univ-lille.fr/8x13x20.html),
[8x15x17](https://fmm.univ-lille.fr/8x15x17.html),
[8x16x17](https://fmm.univ-lille.fr/8x16x17.html),
[8x17x17](https://fmm.univ-lille.fr/8x17x17.html), and
[10x16x17](https://fmm.univ-lille.fr/10x16x17.html).
The fresh 8x13x17 page says 1,145, versus 1,144 in the earlier frozen
comparison; rank 1,140 beats both. Cached search snippets are not used.

The two checked catalogue HEADs remain unchanged:
`solven-eu/matmulcatalog` at `f3a7f0f61b1005666c2cb03f98f2a16727604ea0`,
and `dronperminov/FastMatrixMultiplication` at
`db560ca5811bc38d5a6d5c0a3ec4315937ceabce`. This is not a global literature
absence, novelty or public-acceptance proof.

The private bundle contains all 435 recipes and source/leaf snapshots,
endpoint tensors, full census, checker sources, native binaries, source
pins, fresh reference pages, prior replay receipts and a payload manifest.
Repeated payloads use hardlinks; no tensor collection is added to Git.

```
~/.local/share/tungsten-metaflip/evidence/2026-09-11-width-five-candidates.tar.gz
46,399,976 bytes; 3,972 payloads
SHA256 fffd8e8896e38268c408cc56d783560b90b2498b320b897ebe10cab8424d3e32
```

Run `python3 -B replay.py` after extraction. This host uses Homebrew Python
3.14 with NumPy; the native binaries are platform-specific. Producer
scripts under `provenance/` preserve their original scratch paths; the
standalone replay does not require those paths or a live repository.
Archive payload readback and a fresh extraction both pass the full manifest
check, including hardlink targets; no unmanifested payloads are present.

No canonical seed, installed binary, live search, public catalogue, push or
publication changed in this study. The next useful test is to propagate
these checked representations into larger targets, rather than continue
the unchanged negative 8x13x16 basis search.
