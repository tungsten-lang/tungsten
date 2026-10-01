# PORT-REPORT: the replay of matmulcatalog recipes (composition primitives, replayer, seed driver) in Tungsten

Written on the integration branch `metaflip-tungsten-port` (no agent: the weekly API limit stopped the subagents).
Toolchain: `/Users/erik/tungsten/bin/tungsten`, `python3` 3.14.7, Apple M5 Max, machine shared (load 8-11, other sessions), so CPU time is
quoted next to wall time. Real data from `~/.tungsten/metaflip/experiments/record-hunt-20260926/work` (`GIT_NO_LAZY_FETCH=1`: the catalogue
clone is a blob-less partial clone), matmulcatalog at `f0c2ba9e3797`, release 2026-09-29.

## Files

| file | lines | original | what |
|---|---|---|---|
| `bits/tungsten-metaflip/lib/metaflip/gf2/mmc_alg.w` | 543 | `tools/mmc_gf2_alg.py` 685 | `MmcAlg`: orientations and axis permutations, Kronecker products, concatenation, projection, recombination, bud decompositions, the serendipitous product, `clean` |
| `bits/tungsten-metaflip/lib/metaflip/gf2/catalogue.w` | 993 | `tools/mmc_gf2_replay.py` 659 | `MmcSource` (a catalogue checkout pinned at one revision), `MmcReplayer` (atoms in every layout, the lineage language, leaf references, best-at-a-shape), `Mmc` (parsers, parity, MFW1 cache) |
| `bits/tungsten-metaflip/lib/metaflip/gf2/catalogue_seeds.w` | 204 | `tools/mmc_gf2_seeds.py` 225 | `CatalogueSeeds.select_targets`, `.replay` |
| `bits/tungsten-metaflip/tools/mmc_seeds.w` | 55 | | command line: `targets` and `replay` |
| `bits/tungsten-metaflip/spec/gf2_mmc_alg_test.w`, `spec/fixtures/gf2_mmc_alg/` | 107, 124 KB | `tools/mmc_gf2_alg.py` | 692 checks |
| `bits/tungsten-metaflip/spec/gf2_catalogue_test.w`, `spec/fixtures/gf2_catalogue/` | 135, 280 KB | `tools/mmc_gf2_replay.py` | 232 checks |
| `bits/tungsten-metaflip/spec/gf2_catalogue_seeds_test.w`, `spec/fixtures/gf2_catalogue_seeds/` | 114, 284 KB | `tools/mmc_gf2_seeds.py` | 35 checks |

The lineage verifier (`lib/metaflip/gf2/lineage.w`) calls the replayer for `recipe-replay` rows (see PORT-REPORT-lineage-and-papers.md).
The goldens are what the Python originals produce (`spec/fixtures/*/generate.py` run them, and nothing from the Tungsten side).

## What is checked

* `mmc_alg` (692 checks): 19 input schemes (naive, Strassen, products of them, the 3x3x4 seed of rank 29, a scheme with zero and repeated
  terms) through every primitive, with the terms in the order the original returns them (the constructions index terms by position, so the
  order is part of the result).
* `catalogue` (232 checks): a synthetic checkout of 57 scheme files, committed with a fixed author and date so that its revision is fixed:
  atoms in the dense, sparse, row-map and reduced layouts with integer, rational, float and text coefficients; recipes that use every
  operation of the lineage language and every kind of leaf reference; 19 files that must fail (an inexact atom, an even denominator, a cycle, a
  dangling `@ref`, a missing key, an unsupported operation, a shape that is not the declared one) with the original's message. Every file is replayed
  with and without the disk cache (the two must agree); `best`, `best_rank` and `candidates` at seven shapes; `parity` of 36 coefficients.
* `catalogue_seeds` (35 checks): the ten steps of `spec/fixtures/gf2_catalogue_seeds/cases.json` over one shared cache directory on a small
  synthetic catalogue: three target selections (default, slack 1, minimum dimension 3 with slack 100; entries that must be skipped: commutative,
  complex, not stamped F2, a dimension of 1, a dimension above 32, a rank above the best listed one, a shape already on the scoreboard), a replay
  of ten targets without a scoreboard (5 succeed; an over-claiming recipe, an even denominator, a leaf that is no
  reference and two recipes that need a leaf the F2 atoms do not have fail with the original's reason), the same command again (nothing left
  to do), with a scoreboard (a local rank-23 witness serves as a leaf: `leaf_mode` `board`, with the witness's SHA-256 in the attribution),
  with `--allow-nonf2` (an integer-only rank-17 atom serves: `leaf_mode` `wide`), `--retry-failed`, `--only` by shape and by file, and from the
  selected targets file. Per step: the printed lines, the targets file, the results log (with `secs` zeroed), `seeds.json` and the name and
  SHA-256 of every seed file are compared with the original's. The same ten steps were also run through the compiled tool itself (`tools/mmc_seeds.w`,
  command line included) against the same goldens: identical.

## Real data

| what | original | port |
|---|---|---|
| `targets` on the real catalogue (138 of its schemes chosen against the campaign's final board of 3,662 shapes, Lille's table, FastMatrixMultiplication at HEAD and the Merlijn repository) | file and printed line | **byte-identical** targets file (138 targets, 108 below the best listed rank) |
| `replay` of the first eight of them | 6 fail with `even denominator coefficient '-1/8'` (recipes whose rank needs a rational leaf), 2 above the catalogue rank | identical `results.jsonl` (secs zeroed), `seeds.json` |
| `replay` of the 82 `recipe-replay` rows of bundle A (`gf2-searched-records`) | 82 seeds, 0 failures | identical `results.jsonl`, `seeds.json` and **82 of 82 `.mfw` files byte for byte**; 71 equal the SHA-256 of the bundle rows the campaign marked as rederivable, the other 11 are the equal-rank variants of the manifest |
| the lineage verifier on bundle A with `--source matmulcatalog=<clone>` | PASS, `71 recipe-replay+rederived`, 11 `recipe-replay` and 11 notes | identical output (441 lines) |

### Timing

Replay of the 82 recipes into seeds, release binary against `python3`, medians of three runs, the replay cache holding only the raw JSON of the
catalogue (every scheme is computed):

| | wall | CPU (user + system) | peak memory |
|---|---|---|---|
| `mmc_gf2_seeds.py replay` | 13.5 s | 12.2 + 0.9 s | 242 MB |
| `mmc_seeds replay` | 5.1 s | 2.9 + 1.0 s | 2.6 GB |

The lineage verifier on bundle A with the catalogue source, medians of three alternating runs:

| | wall | CPU (user + system) | peak memory |
|---|---|---|---|
| `verify_gf2_lineage.py --no-ruby` | 179.3 s | 170.6 + 5.9 s | 2.03 GB |
| `verify_lineage` (release binary) | 61.7 s | 56.5 + 2.0 s | 9.06 GB |

(all three runs of each: Python 181.7 / 179.3 / 178.3 s wall, Tungsten 61.3 / 61.7 / 63.2 s; the outputs are identical in all six runs. The first
three Tungsten runs, before `Derive.drop_matrix` freed its list literals (PORT-REPORT-cascade.md), took 66.1 / 68.0 / 67.1 s and 11.0 GB. Without
the catalogue source the same bundle took 53 s and 9.0 GB before that change, see PORT-REPORT-lineage-and-papers.md.)

The memory is the price of having no garbage collector: the replayer keeps every scheme it has materialized (`@file_memo`, the best-at-a-shape
memo), and nothing frees the intermediate tensors of the constructions.

## Deviations from the original

* A scheme file that is neither cached nor in the clone is one failed `git show` and a `FetchError`; the original retries six times with sleeps
  of 1 to 6 s and then raises `RuntimeError` (the seed driver records either as a failure; the port's reason names `RuntimeError` too, without
  the traceback the original appends to every reason that is neither a `ReplayError` nor an assertion).
* The Python exceptions that the original lets through (a `TypeError` of malformed JSON and the like) are `ReplayError`s here, with the message
  `<path>: <Type>: <repr>` where it is reproducible.
* `Scheme` refuses a zero dimension, so a projection onto an empty list of coordinates raises `MmcError` (the original returns an `Alg` with no
  terms); the case is not in the goldens.
* `tools/mmc_seeds.w replay` runs the targets one after the other: `--jobs` is accepted, a warning says it is ignored.
* Option `--cache-dir` of the verifier is real now (it was accepted and ignored before the replay was ported).

## Notes on the original (kept, see PORT-BLOCKERS.md)

The seed driver keeps one replayer per process and the replayer's disk cache is keyed by the mode only (`_board`, `_wide` or none), not by
the board's content: a replay with another scoreboard, or `--allow-nonf2 --board` after a run without the board, reuses the recipes the earlier
replay materialized. The golden of the step `replay-selected` shows it (a recipe that needs the board's rank-23 leaf fails at rank 189).

## Blockers and workarounds (PORT-BLOCKERS.md)

A splat method (`note(*parts)`) in a class whose constructor takes keyword arguments binds `self` for two arguments (`note_log(line)` takes one String);
a closure reading a block parameter in sibling branches failed on one real recipe (the bud blocks are three methods with loops); `X.file?(path)`
means "exists" for any `X` in the compiled engine (the replayer uses `Fsx.regular?`).

## For the integrator

Native shard, a few seconds each (they run compiled and call `git`): `spec/gf2_mmc_alg_test.w`, `spec/gf2_catalogue_test.w` (6.5 s),
`spec/gf2_catalogue_seeds_test.w` (6.3 s). `tools/regen_manifests.w` once after the merges (`lib/metaflip/SHA256SUMS`).
