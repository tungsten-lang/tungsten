# PORT-REPORT: the bounded projection/basis/walk search in Tungsten

Written on the integration branch `metaflip-tungsten-port` (no agent: the weekly API limit stopped the subagents).
Toolchain: `/Users/erik/tungsten/bin/tungsten`, `python3` 3.14.7, Ruby 4.0, Apple M5 Max, machine shared (load 8-12).

## Files

| file | lines | original | what |
|---|---|---|---|
| `bits/tungsten-metaflip/lib/metaflip/gf2/projection_walks.w` | 270 | `tools/search_wide_projection_walks.py` 230 | `ProjectionWalks`: `proposals`, `select`, `project_grid` (the independent second projection of the original's `neutral.project_grid`), `verify_file`, `public_comparison`, `run` |
| `bits/tungsten-metaflip/tools/projection_walks.w` | 35 | | command line: `--seed --digest [--walker --output-dir] [--depth --beam --steps --nonce-base] [--list-only] [--no-ruby]` |
| `bits/tungsten-metaflip/spec/gf2_projection_walks_test.w`, `spec/fixtures/gf2_projection_walks/` | 82, 104 KB | `tools/search_wide_projection_walks.py` | 16 checks |

From one exact parent the search takes every coordinate projection of the parent and of its two-pass basis rewrites (modes 6 to 17) as a
candidate child (`Derive.child`: projection, then shared-factor compression), keeps at most two distinct children per shape, orders them by
rank relative to the public rank, takes the `--beam` first (distinct shapes first), walks them with the compiled directed walker
(`tools/wide_rect_walk.w`), verifies parents, children and results (both gates of the Tungsten verifier and, as in the original,
`tools/verify_tensor.rb`), and repeats `--depth` times. The library builds on `derive.w` (ported earlier) and `scheme.w`.

## What is checked

* `spec/gf2_projection_walks_test.w` (16 checks): the cases of `spec/fixtures/gf2_projection_walks/cases.json` on the 3x3x4 rank-29 seed, with
  a rank table for its children: the listing of the selected children (JSON, `indent=2`), a depth-2 search with two children per parent
  (six walks, three of which lower the rank), a depth-1 search with one; and the searches that must end badly (a walker that writes garbage,
  one that answers with another shape, one that fails, an output directory that exists, a nonce out of range, a rank table with two ranks for
  one format). The walks use stand-in walkers that answer with what the compiled walker returned (`in/alt/`): `generate.py` runs the Python
  original with the real compiled walker (20,000 proposals, nonces from 7), keeps its results, runs the original again with the stand-ins and
  asserts that both give the same manifest. The goldens are the original's printed lines, its `manifest.json` (scratch directory written
  `$T`) and the name and SHA-256 of every file next to it. The Ruby verifier runs in both.
* Real data (`bits/tungsten-metaflip/lib/metaflip/seeds/gf2` seeds and bundle A, with the real `fmm_sota.json` as the rank table):

| what | result |
|---|---|
| `--list-only --beam 4` on 3x5x7 (79 terms), 4x5x6 (90), 4x5x7 (104) and the rank-562 3x14x18 recipe of bundle A | text **identical** to the original's in all four |
| depth 2, beam 3, 300,000 proposals, nonces from 11, the compiled walker, on 4x5x6 and 4x5x7 (12 walks each) | the 13 printed lines, `manifest.json` and all 24 files (seeds and results) **identical** in both searches |

### Timing (one run each, release binary; the listing of the rank-562 seed, so no walker time)

| | wall | CPU (user + system) | peak memory |
|---|---|---|---|
| `search_wide_projection_walks.py --list-only` | 3.2 s | 3.05 + 0.04 s | 44 MB |
| `projection_walks --list-only` | 3.5 s | 3.34 + 0.09 s | 1.2 GB |

No speed-up: the profile of the port is flat (allocation, the hexadecimal keys of the groups, hash probes) and is the shared-factor
compression of `derive.w`, which the original runs on Python integers and tuples. The memory is the missing garbage collector.

## Deviations from the original

* `--no-ruby` is new (it skips `tools/verify_tensor.rb`; the two gates of the Tungsten verifier remain); the original always runs Ruby.
* The exactness gate is the verifier's two gates, the original's `exact` is one.
* A failed check raises `ProjectionWalksError` with the original's message where it has one; the original raises `AssertionError`,
  `ValueError` or `CalledProcessError`. The specs compare accept and reject, not the messages.
* The basis modes are a literal list (a `(6...18).each` before the loop over the modes trips the compiler, see PORT-BLOCKERS.md).

## For the integrator

Native shard, 5 s: `spec/gf2_projection_walks_test.w` (it calls `ruby`). `tools/regen_manifests.w` once after the merges.
