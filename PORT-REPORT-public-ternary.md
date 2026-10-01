# PORT-REPORT: the import of public integer and ternary schemes (tools/screen_public_ternary_gf2.py) in Tungsten

Written on the integration branch `metaflip-tungsten-port` (no agent: the weekly API limit stopped the subagents).
Toolchain: `/Users/erik/tungsten/bin/tungsten`, `python3` 3.14.7, Apple M5 Max, machine shared (load 10-25, other sessions and the
benchmark runs), so CPU time is quoted next to wall time.

## Files

| file | lines | what |
|---|---|---|
| `bits/tungsten-metaflip/lib/metaflip/gf2/public_ternary.w` | 382 | library `Metaflip:Gf2:PublicTernary`: parity of exact and rational coefficients, `reduce_mod2`, `integer_files`, `seeds`, `walk` |
| `bits/tungsten-metaflip/tools/public_ternary.w` | 50 | command line with the two subcommands (argparse-style usage and help from `Cli`) |
| `bits/tungsten-metaflip/spec/gf2_public_ternary_test.w` | 168 | 125 checks against goldens of the Python original |
| `bits/tungsten-metaflip/spec/fixtures/gf2_public_ternary/` | 312 KB | `generate.py` (runs the ORIGINAL on a small scheme tree), the tree, a stand-in walker, `expected/` |

Original: `tools/screen_public_ternary_gf2.py`, 234 lines (plus `argparse`, `json`, `re`, `fractions`, `hashlib`, `zlib`, `subprocess`,
`concurrent.futures`, which the support libraries replace).

## What it does

`seeds` converts the distinct integer schemes of a FastMatrixMultiplication-format repository (best integer rank of each shape, or within
best + N; the ring is the file-name suffix; `_Q` files only with `--include-rational`, and then only those whose denominators are odd) into
MFW1 seeds: coefficients reduced modulo two, equal terms cancelled in pairs, terms with a zero factor dropped, the result checked against the
matrix-multiplication tensor by both gates, written below a new directory with a `seeds.json` manifest. `walk` runs the compiled walker over
the seeds, `jobs` at a time, and appends one JSON row per walk to a log (finished walks are not repeated).

## Parity with the original

All commands from `~/.tungsten/metaflip/experiments/record-hunt-20260926/work` (`GIT_NO_LAZY_FETCH=1`), outputs compared with `diff -rq`.

| input | original | port |
|---|---|---|
| `seeds` on `upstream/fmm` (FastMatrixMultiplication at 613599b, `--alternatives 1 --include-rational`, 1,454 scheme files, 1.8 GB tree) | 1,189 seeds, 0 mod-2 cancellations, 243 rejected; the output directory is identical to the campaign's `seeds_perminov_0929` | the same summary; all 1,190 files (1,189 seeds and `seeds.json`) **byte-identical** |
| `seeds` on `upstream/merlijn` (fmm-schemes at 8fa0f2a, `--include-rational`) | 25 seeds, 0 rejected; identical to the campaign's `seeds_merlijn_0929` | the same summary; all 26 files **byte-identical** |
| `walk` over 10 real seeds, 2 nonces each (20 walks of 200,000 steps) | 20 rows | the 20 rows (sorted: rows are written in completion order) and the 20 output files **byte-identical** |
| `walk` over 6 real seeds (3,000,000 steps, a manifest as a dictionary with one seed lacking `mfw_sha256`, `--largest-first`), then a resume with `--repeats 2 --min-rank 22` | 12 rows | stdout, the 12 rows and the output files identical; the resume starts only the new walks |
| `walk` over the naive schemes of 2x2x2, 2x2x3, 2x3x3 (20,000 steps) | `DROP 2x2x2 8 -> 7`, `DROP 2x2x3 12 -> 11`, `DROP 2x3x3 18 -> 16` | the same lines, rows and files |

`spec/gf2_public_ternary_test.w` (125 checks, 6 s: it builds a git repository of the fixture tree): `parity` on 51 values (integers up to 2^70,
rationals with reducible and unreducible denominators, zero and invalid denominators, floats, booleans, null, arrays) with the original's result
or message; `parse_result` on 11 texts against the original's regular expression; `integer_files` for four (alternatives, rational) pairs;
`seeds` for six option sets over a tree of 41 files (naive and Strassen schemes in integer, ternary and rational coefficients; 21 rejected files
with each message of the original: wrong sizes, missing keys, a float, a boolean, null and text coefficients, a zero and an even denominator, an
inexact scheme, a rank that disagrees with the file name, broken, empty and trailing-garbage JSON; a duplicate seed, a repeated term and a term
with an even factor that lower the rank; `known/` files, `_Q` files without the flag and a window of shapes that are skipped): the summary, the
`seeds.json` text (byte for byte) and the SHA-256 of every seed file; and `walk` through a stand-in walker (success, a rank drop, a failure
status, no result line, a seed without a hash): log rows, printed lines and output files. The existing output directory is refused.

## Timing (medians of three runs, alternating; the machine was shared)

| task | original | port |
|---|---|---|
| `seeds` on FastMatrixMultiplication | 126.6 s wall, 110.8 s CPU (user 90.8, sys 20.0), 315 MB | 83.8 s wall, 58.3 s CPU (user 38.7, sys 19.6), 1,613 MB |
| `seeds` on fmm-schemes | 4.93 s wall, 4.35 s CPU, 167 MB | 1.56 s wall, 1.02 s CPU, 235 MB |

The 20 s of system time in both is the 1,454 `git show` calls. The port uses 1.9 times less CPU time on the large repository (2.3 times less
user time) and 4.3 times less on the small one; its peak resident set is five times the original's on the large one (no garbage collector:
the text of each scheme file and its parse tree are freed, but `Procx` holds a copy of every `git show` output until the caller frees it).

## Deviations from the original

* A walker that cannot be executed is recorded as an error row (status 127 and the shell's message); the original stops with `FileNotFoundError`.
* A scheme file whose JSON root is not an object is rejected with `unsupported scheme header`; the original stops with a `TypeError`.
* The output directory that already exists raises `FsError` (the original `FileExistsError`); a revision that does not exist raises `GitError`.
* `walk` writes a row when a walk finishes, in completion order, as the original does; `--jobs` defaults to the CPU count minus two.
* The usage line names `public_ternary.w`.

## Blockers and workarounds (PORT-BLOCKERS.md)

`is_a?(Hash)` is false for every Hash (the runtime's `w_value_is_a` has no Hash branch), so the two tests are `type(x) == "Hash"`, marked
`TODO(port)`; `value.is_a?(Integer)` once per coefficient took a fifth of the samples (`w_method_call_slow`), `type(value)` is three tag checks
(117 s to 38 s of CPU time on the large repository). A parenthesised ternary before `+` drops the `+` (also a parse error in one position).
Test suggestion for the integrator: `spec/gf2_public_ternary_test.w`, native shard (runs compiled), 6 s.
