# PORT-REPORT: the lineage verifier and builder, and the paper scripts, in Tungsten

Written on the integration branch `metaflip-tungsten-port` (no agent: the weekly API limit stopped the subagents).
Toolchain: `/Users/erik/tungsten/bin/tungsten`, `python3` 3.14.7, Ruby 4.0, Apple M5 Max, machine shared (load 10-25, other sessions and
the benchmark runs), so CPU time is quoted next to wall time.

## Files

| file | lines | original | what |
|---|---|---|---|
| `bits/tungsten-metaflip/lib/metaflip/gf2/lineage.w` | 311 | `tools/verify_gf2_lineage.py` 205, `tools/build_gf2_lineage_bundle.py` 77 | `Metaflip:Gf2:Lineage`: `verify`, `build`, `recipe_rank`, `lines` |
| `bits/tungsten-metaflip/tools/verify_lineage.w` | 38 | | command line of the verifier |
| `bits/tungsten-metaflip/tools/build_lineage.w` | 32 | | command line of the builder (it ends by verifying what it wrote) |
| `bits/tungsten-metaflip/spec/gf2_lineage_test.w`, `spec/gf2_lineage_build_test.w`, `spec/fixtures/gf2_lineage/` | 96, 88, 564 KB | `spec/verify_gf2_lineage_test.py`, `spec/build_gf2_lineage_bundle_test.py` | 55 and 11 checks |
| `bits/tungsten-metaflip/papers/scripts/{gen_results_data,prior_art_flags,make_arxiv_md,pack_arxiv,ruby_verify_all}.w` | 210, 108, 128, 135, 109 | the `.py` of the same names: 153, 44, 54, 111, 86 | the paper build and audit scripts |
| `bits/tungsten-metaflip/lib/metaflip/papers/tex.w` | 152 | the regular expressions of `pack_arxiv.py` and `make_arxiv_md.py` | `Tex.strip_comments`, `references`, `todo_lines`, `abstract`, `cited_keys` |
| `bits/tungsten-metaflip/spec/papers_tex_test.w` | 40 | | 6 checks against the originals' results on the same snippets |

`papers/Makefile` compiles the scripts into `build/` with the compiler and runs them (`TOOLS=py` runs the Python originals).

## The lineage verifier

What is checked, by row kind, is the header of `lib/metaflip/gf2/lineage.w` and of the original: exact tensors (both gates), parent links,
recipe rank arithmetic, re-derivation of `public-mod2`, `archived` and `retained` rows from their upstream files, `basis` and `projection`
rows from their parents (`Derive.two_pass`, `Derive.child`), walk replays through the compiled walker. Memory: a parent's terms are kept
until its last child has been checked.

### Parity with the original (`--no-ruby`, so one exactness check each; the port runs both of its gates)

All commands from `~/.tungsten/metaflip/experiments/record-hunt-20260926/work` (`GIT_NO_LAZY_FETCH=1`), release 2026-09-29 bundles.

| bundle | rows | original | port |
|---|---|---|---|
| B `gf2-closure-products` | 203 closure | `PASS 203 ... rows: 203 closure` and 203 final ranks | **identical** output (apart from the name of the verifier in the PASS line), in all three runs |
| C `gf2-block47-certificates-2026-07`, `--source tungsten=<repository>` | 186 archived | `186 archived+rederived` | identical, in all three runs |
| A `gf2-searched-records`, sources perminov, Merlijn, tungsten, `--repo-root` | 677 (40 archived, 64 closure, 225 projection, 5 public-mod2, 82 recipe-replay, 25 retained, 236 walk) | `40 archived+rederived, ... 5 public-mod2+rederived, 82 recipe-replay, 25 retained+matched, 236 walk` and 82 notes | identical (512 lines), in all three runs |
| D `gf2-public-ternary-walks-2026-09-26`, sources perminov, Merlijn, `--replay-walk` | 21 (10 public-mod2, 11 walk) | `10 public-mod2+rederived, 11 walk+replayed` | identical; the 11 walks of 40M proposals run the same compiled walker in both (307 s and 245 s wall) |

`spec/gf2_lineage_test.w` (55 checks, 1 s): the rank arithmetic of recipes (split, product, projection, three refused); 37 bundles built by the
original's test code and checked by the original (`generate.py` asserts that it accepts the 12 good ones and rejects the 25 others): the good
bundle with every derived kind (closure, basis, walk, projection with and without a basis rewrite), 17 tampered copies (a swapped file, a
wrong recipe rank, projection coordinate or basis mode, an unknown kind, a walk that raises the rank, missing provenance, a bad header, a
record claim, a missing, later or unexpected parent, a wrong rank or shape field, an inexact tensor, a non-canonical text), `retained` rows with
and without a repository root and with the wrong file, `archived` rows with and without a source, with a wrong digest and with another
tensor, `public-mod2` rows with and without a source, with a wrong rank and with a wrong digest, `recipe-replay` rows with and without a
source, walk replays through a copying, a corrupting and a failing walker and skipped by `--replay-max-rank`. The output of every accepted
bundle is compared with the original's. `spec/gf2_lineage_build_test.w` (11 checks): the original's test of the builder.

### Timing (medians of three runs, alternating; the machine was shared)

| bundle | original (wall, CPU, peak memory) | port | CPU ratio |
|---|---|---|---|
| B (203 closure rows) | 30.2 s, 30.1 s, 590 MB | 2.5 s, 2.4 s, 714 MB | 12.3 |
| C (186 archived rows) | 60.7 s, 58.3 s, 628 MB | 12.5 s, 9.4 s, 2.5 GB | 6.2 |
| A (677 rows) | 153.4 s, 152.5 s, 1.66 GB | 54.0 s, 52.7 s, 9.0 GB | 2.9 |

The memory is the price of having no garbage collector: the first complete run of bundle A peaked at 81 GB (the projection rows alone
allocated 60 GB). `Derive` now frees its temporaries (the keys and groups of `parity` and `compress_shared`, the hash tables and
BigInt intermediates of `matrix_factors`, the operator results of `drop_matrix`), and `Procx.run` frees the captured text after copying
it: a basis rewrite of a rank-6,005 tensor went from 644 MB to 49 MB and a projection with compression from 334 MB to 66 MB, with identical
output (`spec/gf2_derive_test.w` 217 checks, `spec/gf2_derive_parity.py` 218 of 218 on real tensors, `rebuild_closure` 259 of 267 as
before, `spec/gf2_recipes_test.w`, `spec/gf2_record_board_test.w` incl. the final board). Bundle C still holds the decimal text of the
archived certificates (`RecordBoard.decimal_terms` frees nothing); bundle A's remaining 9 GB is the garbage of the exactness gate and the
parse of the largest tensors.

### Deviations from the original

* The second opinion of the original, an independent Ruby reconstruction (`tools/verify_tensor.rb`), is not called: each tensor passes both
  gates of the Tungsten verifier, and `papers/scripts/ruby_verify_all.w` runs the Ruby oracle over all release tensors (below). `--no-ruby` and
  `--cache-dir` are accepted and do nothing. The PASS line reads `(Tungsten, two gates)` where the original's reads `(Python)` or `(Python and Ruby)`.
* The re-derivation of `recipe-replay` rows (the replay of matmulcatalog recipes, `mmc_gf2_replay.py`) is not part of this port: a row of that
  kind with a source is noted as `recipe replay is not part of this verifier; not re-derived`, one without a source as in the original.
* A failed check raises `LineageError` with the row and the check named; the original raises `AssertionError` (often without a message) or `KeyError`.
* The gzip layer of the builder's files is written by `core/gzip` (level 9, Base64 lines of 76), so its bytes differ from Python's `gzip.compress`;
  the rows' SHA-256 are those of the uncompressed tensors and agree.

## The paper scripts

All five run on the real inputs of the release (`~/.tungsten/metaflip/experiments/record-hunt-20260926/work`) into scratch directories.

| script | check against the original | timing (original / port) |
|---|---|---|
| `gen_results_data` | all files written (`records.tsv`, `family_counts.tsv`, the two scatter files, the four tables) **byte-identical**, and equal to the committed ones; the three progress lines identical | 0.11 s / 0.01 s |
| `prior_art_flags` | `prior_art_flags.tsv` byte-identical, equal to the campaign's file; the counts (80, 7, 105, 7, 9) asserted | 0.13 s / 0.00 s |
| `make_arxiv_md` | `ARXIV.md` byte-identical (it also stops over the 1,920-character limit of the abstract field) | |
| `pack_arxiv` | the same 37 files and the same `\todo` lines; the extracted contents are identical; the archive is 59,304 bytes against 59,384 (the two compressors differ); the standalone build of the bundle passes (279,572 bytes, 0 undefined references) | |
| `ruby_verify_all` | all 1,090 output lines identical, in order, to the committed `verification/ruby_all_20260929.log` (985 bundle tensors, 102 committed certificates, 2 fleet checkpoints, 0 failures) | 29.5 s wall with 8 jobs and the Ruby oracle |

Differences: `pack_arxiv` writes a ustar archive (zero owners and times) and compresses it with `core/gzip`; the verification build unpacks it with `tar`.
`ruby_verify_all` keeps the oracle in Ruby (it is the independent check) and drives it from Tungsten with `Procx.run_all`.

## Blockers and workarounds (PORT-BLOCKERS.md)

A parenthesised ternary before `+` drops the `+` (found again in `ruby_verify_all`); `String#rstrip` is undefined; a string literal
containing `[...]` is interpolated, so the usage lines and the LaTeX snippets escape the brackets; a multi-line string joined by trailing `+` does not
parse. No new blockers beyond those. Test suggestions for the integrator: `spec/gf2_lineage_test.w`, `spec/gf2_lineage_build_test.w` and
`spec/papers_tex_test.w`, native shard (they run compiled), a few seconds each.
