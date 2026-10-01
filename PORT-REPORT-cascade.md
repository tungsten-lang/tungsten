# PORT-REPORT: the cascade drivers (parents, projection screen, child selection, walk screen, iterative deepening) in Tungsten

Written on the integration branch `metaflip-tungsten-port` (no agent: the weekly API limit stopped the subagents).
Toolchain: `/Users/erik/tungsten/bin/tungsten`, `python3` 3.14.7, Apple M5 Max, machine shared (load 8-12). Real data from
`~/.tungsten/metaflip/experiments/record-hunt-20260926/work` (the campaign's boards, projection logs and its compiled walker `wide-rect-walk`).

## Files

| file | lines | original | what |
|---|---|---|---|
| `bits/tungsten-metaflip/lib/metaflip/gf2/cascade.w` | 350 | `next_parents.py` 27, `project_screen.py` 78, `pick_children.py` 45, `sweep.py` 76, `iterate.py` 83 | `Cascade`: `next_parents`, `project_screen` (+ `screen_one`), `pick_children`, `sweep`, `iterate` |
| `bits/tungsten-metaflip/tools/cascade.w` | 103 | | command line: `parents`, `screen` (+ the internal `screen-one`), `pick`, `sweep`, `iterate` |
| `bits/tungsten-metaflip/tools/campaign/*.py`, `README.md` | 328 | | the six originals, copied unchanged from the campaign's working directory (the oracles); they keep their machine-specific paths |
| `bits/tungsten-metaflip/spec/gf2_cascade_test.w`, `spec/fixtures/gf2_cascade/` | 110, 364 KB | the originals | 33 checks |

These scripts drove the campaign's cascade (they lived in the working directory, not in the repository): the scoreboard's witnesses of the kinds
`below_all`/`gf2_valid_only` that no projection log covers yet (`next_parents`), their projection children over the 13 bases
(`project_screen`, on `ProjectionWalks.proposals`), the children that beat the scoreboard and are within a tolerance of the best listed rank
(`pick_children`), the compiled directed walker over the children (`sweep`) and its iterative deepening (`iterate`). The ranks come from the same public tables as the
scoreboard (`RecordBoard.public_tables`); the Tungsten tools take them as options (`--lille`, `--catalog`, `--fmm-repo`, `--extra-repo`) where the originals
read the working directory's `pub.py`.

## What is checked

* `spec/gf2_cascade_test.w` (33 checks): the ten steps of `spec/fixtures/gf2_cascade/cases.json` on six seeds of the repository (3x3x4, 3x4x4, 2x3x5, 3x3x5 and
  two weaker ones of rank 31 and 40), in order in one scratch directory: two selections of parents (default kinds; `tie,above` with two logs), the projection screen of
  four parents and again (nothing left), the child selection at tolerances 0.03, 0 and 0.5, a walk screen with two repeats and again, and an iterative deepening of three
  shapes (two of which drop). The walks use a stand-in walker that answers with what the compiled walker answered; `generate.py` runs the Python originals with the real
  walker through a recording wrapper, keeps its answers, runs them again with the stand-in and asserts the same results. Per step the printed lines, the output and the name
  and SHA-256 of every file written are the original's. A last check runs the screen with a process of its own for each parent (`bin/tungsten run tools/cascade.w --
  screen-one`, what the tool does) and compares log and files with the in-process screen.
* Real data, Python original (run from the work directory, or from a copy with its constants rewritten) against the Tungsten tool, same inputs:

| step | inputs | result |
|---|---|---|
| `parents` | the final board (3,662 rows) and the logs `proj_r1`, `proj_r2`, with kinds default, `+tie`, `above`, `below_all` | 172, 1,585, 1,454 and 144 parents: the printed line and the 39,651 / 380,991 / 316,449 / 33,520-byte files **byte-identical** |
| `pick` | five (log, board, tolerance) combinations of the campaign: up to 887 child shapes, 519 no gain, 368 selected, tolerances 0 to 0.5, the real public tables (Lille, matmulcatalog, FastMatrixMultiplication, Merlijn) | printed line and seed file **byte-identical** in all five (the files are 56 to 177 KB) |
| `screen` | ten real parents of 94 to 420 terms (4x4x8 to 8x8x10), jobs 1 and 4 | the log (24 rows), the three `CHILD-BELOW-LILLE` lines and all 24 child files identical; with four jobs the same rows in another order, as the pool's |
| `sweep` | eight child seeds, five of them chosen by a filter file, two repeats, 200,000 proposals, the campaign's walker | the ten rows, the `DROP` lines and the ten output files identical |
| `iterate` | four child seeds, 300,000 proposals, 2 walks per round, patience 2, three jobs | the `DROP`/`DONE` lines, the 22 rows (per shape, in order) and the 22 output files identical |

### Timing and memory

`screen` of the ten parents (release binary against `python3`, sequential): 8.7 s against 6.7 s, 0.9 GB for the largest process against 0.29 GB; with `--jobs 4` the
Tungsten tool takes 3.3 s. Each parent is screened by a process of its own (the original has a process pool too): the language has no garbage collector, and one rank-562
parent leaves about a gigabyte in the process (`Derive.child` keeps about 1 MB of unreachable memory per call at that size), so a loop over 400 parents in one process would
not fit. A change to `Derive.drop_matrix` (it freed the BigInt temporaries but not the list literals that named them) took the unreachable memory of the 35 children of that
parent from 64 MB to 38 MB; `spec/gf2_derive_parity.py` (218 of 218 operations on real tensors) and `spec/gf2_derive_test.w` (217 checks) still agree.

## Deviations from the originals

* `screen` runs a worker process per parent (`screen-one`), `--jobs` at a time, and logs in the order they finish; the original's pool does the same. Without `options["worker"]` (the
  library's default, and the spec's) the parents run one after the other in the calling process.
* `sweep` and `iterate` run the walker as processes (the originals use threads that run it). `iterate` runs the rounds of all shapes in lock step: the rows of one shape come in
  the original's order, those of different shapes are not interleaved as they finish.
* A parent that cannot be decoded is reported as `ERROR <file> <message>` (the original prints the repr of its Python exception).
* The tools take the public tables as options; the originals' `pub.py` is a module of the working directory with the campaign's paths.
* `PublicTernary.parse_result` returns all six numbers of the walker's result line (it returned the first three); its spec and golden were updated.

## Not ported

`collect_chains.py`, `collect_leaves.py`, `resolve_leaves*.py`, `build_bundle.py`, `release_index.py`, `make_release_metadata.py`, `make_receipt.py`, `write_readmes.py` and the other scripts of the
campaign's working directory read its logs and file layout (generations of logs, a scratchpad prefix that was stripped, upload receipts): they stay Python.

## For the integrator

`spec/gf2_cascade_test.w` is classified native (it runs `bin/tungsten` as a child), ~10 s. The classification of the 21 tests of the port is in `spec/native_tests.txt` and
`spec/interpreted_tests.txt` (three of them, `gf2_derive_test`, `gf2_mmc_alg_test` and `papers_tex_test`, pass interpreted and are in shards 1, 2 and 8);
`spec/metaflip_test_manifest_spec.w` still reports the 7 problems it has on main (six unclassified older tests and `spec/learned_residual_native.w`).
