# PORT-REPORT: the record scoreboard (tools/gf2_record_board.py) in Tungsten

Written on the integration branch `metaflip-tungsten-port` (no agent: the weekly API limit stopped the subagents).
Toolchain: `/Users/erik/tungsten/bin/tungsten`, `python3` 3.14.7, Apple M5 Max, machine shared (load 14-29, other sessions and
the benchmark runs), so CPU time is quoted next to wall time.

## Files

| file | lines | what |
|---|---|---|
| `bits/tungsten-metaflip/lib/metaflip/gf2/record_board.w` | 324 | library `Metaflip:Gf2:RecordBoard`: name parsers, witness decoding and verification, cache, public tables, classification |
| `bits/tungsten-metaflip/tools/gf2_record_board.w` | 43 | command line (same options as the original, argparse-style usage and help from `Cli`) |
| `bits/tungsten-metaflip/spec/gf2_record_board_test.w` | 91 | 55 checks against goldens of the Python original, and against the campaign's final board |
| `bits/tungsten-metaflip/spec/fixtures/gf2_record_board/` | 152 KB | `generate.py` (runs the ORIGINAL on a small tree of witnesses and tables), `in/`, `expected/` |

Original: `tools/gf2_record_board.py`, 235 lines (plus the process pool, `argparse`, `json`, `re`, `pathlib`, `hashlib`,
`gzip`, `base64` and `subprocess`, which the support libraries and `core/gzip` replace).

## What it does

For every witness file under the given roots (`*.mfw`, `*.mfw.gz.b64`, `best.txt`, `matmul_*_gf2.txt`): unpack, hash (SHA-256 of
the bytes), verify against the matrix-multiplication tensor (canonical MFW1 through `Scheme.parse` and the two gates; decimal files
through the orientations that the file or directory name allows), keep the best verified rank per sorted shape (first path
wins a tie), compare with the four public tables (Lille rank list, matmulcatalog `catalog.json`, FastMatrixMultiplication file
names from `git ls-tree` of a pinned clone, extra FMM-format directories) and classify: `below_all`, `gf2_valid_only`, `tie`,
`above`, `no_public_rank`. Verdicts are cached by digest in a JSON file.

## Parity with the original

All commands from `~/.tungsten/metaflip/experiments/record-hunt-20260926/work` (`GIT_NO_LAZY_FETCH=1`); the original
with `--jobs 8`, the port single-process; both start from an empty cache.

| input | original | port |
|---|---|---|
| A: `tools/certificates`, `lib/metaflip/seeds/gf2`, `~/.tungsten/metaflip/checkpoints/gf2` and the four tables | 630 witness files, 594 verified, 293 shapes; 14.5 s wall, 75.1 s CPU | same counts; rows file **byte-identical** (75,619 bytes), cache equal, stdout identical; 6.1 s wall, 5.9 s CPU |
| B: A plus the 1,087 tensors of the port corpus (937 MB) | 1,717 files, 1,543 verified, 924 shapes (below_all 733, gf2_valid_only 62, tie 35, above 94); 49.5 s wall, 294.8 s CPU | same counts; rows file **byte-identical** (268,728 bytes, 924 rows), cache file **byte-identical** (137,520 bytes), stdout identical; 21.2 s wall, 20.5 s CPU |
| C: the campaign's `board_final.json` | 3,662 rows | recomputed from its own witness ranks and the four public tables (pinned clones, `git ls-tree` included): **byte-identical** file |

The port used 14.4 times less CPU time than the original on B (20.5 s against 294.8 s); its peak resident set is 929 MB against
the original's 181 MB per process (no garbage collector: the verifier's limb arrays of the largest tensors).

`spec/gf2_record_board_test.w` (55 checks, 0.5 s as a cached binary): `find_dims` on 14 names and the FMM file-name table on 35 names
against the original's `re` results; `fmm_ranks`; the verdict of `decode` for all 15 witness files of the fixture (MFW1, gzip+base64,
decimal with and without rank line and `R ` prefixes, schemes stored in another orientation than the name suggests, an inexact
one, an unsorted MFW1, a hidden directory, a file without a shape hint); the rows, cache, summary and `-v` lines of the whole tool;
and, when `GF2_RECORD_HUNT_WORK` names the campaign work directory, the reproduction of `board_final.json` (C).

## Deviations from the original

* Witnesses are verified one after the other (the compiled gates need no process pool); `--jobs` is accepted and ignored.
* A witness whose gzip or base64 layer is damaged is skipped; the original stops on a corrupt deflate stream.
* Decimal rows must be plain unsigned integers (the original's `int()` also accepts signs and underscores).
* `ls_tree` returns exact names; the original splits git's output on whitespace (no name of the pinned clones has a space).
* The usage line names `gf2_record_board.w`.

## Blockers and workarounds (PORT-BLOCKERS.md)

`Array#sort` on a long string built by concatenation orders wrongly against a shorter one (the file lists of `Fsx.rglob`), worked
around by copying with `to_s` (`TODO(port)` in `witness_files`); a parenthesised ternary before `+` silently drops the `+`.
Test suggestion for the integrator: `spec/gf2_record_board_test.w`, native shard (runs compiled), 1 s without the real-data check.
