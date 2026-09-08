# Retain useful parents without repeating the walk

The bounded ordinary-walk experiment found three new GF(2) candidate-record
shapes relative to the checked reference screen. All three constructions are
fully materialized and independently tensor-verified; worldwide novelty,
isomorphism review, and redistribution clearance are still open.

| Shape | Previous local | Checked new | Strongest screened reference |
| --- | ---: | ---: | ---: |
| [10×24×24](https://fmm.univ-lille.fr/10x24x24.html) | 3324 | 3318 | 3324 |
| [20×25×28](https://fmm.univ-lille.fr/20x25x28.html) | 7574 | 7568 | 7569 |
| [20×25×32](https://fmm.univ-lille.fr/20x25x32.html) | 8590 | 8576 | 8580 |

The reference column includes recursive published/catalog parent partitions,
not just the linked Lille pages. It mixes reported fields and is comparison
data, not itself a constructive GF(2) certificate. The current bounded
reference-screen shortlist grows **38 → 41 shapes**; this is not a count of
confirmed world records or a replacement for differently scoped historical
candidate tallies. No primitive rank or main square rank improved.

## Finding the missing parent

We screened useful parent families against the pinned complete composition
table, selecting near-reference scale contexts. Seven families had qualifying
contexts: 2×3×5, 2×4×5, 3×3×4, 3×3×5, 3×4×4, 4×4×5, and 3×4×6.
There were two literal-identity seeds per context, each within two terms of its
family minimum. Selection by a bucket signature is only a pricing shortcut;
the actual search and archive identities remain complete tensors.

Each of the 14 cells ran the **same ordinary-walk trajectory twice**:

- retain the minimum tensor rank, then density;
- retain the minimum actual-context bucket-DP cost, then rank and density.

Each run used eight trials, 64 chunks, 65,536 attempts per chunk, observations
every 4,096 attempts, debt two, density slack four, RNG seed 912071. The paired
study made 939,524,096 attempts, sequentially at `nice -n 10`. Exact endpoints
and accepted-flip/chunk counters match across the observers in every trial.

Context retention found lower product costs in 5/14 cells, including
4×4×5 → 10×24×24 at 3318 instead of 3325 for the rank-only observer. This is
an archive-retention effect, **not a better acceptance policy**. Zero regressions
in the optimized cost are expected when minimizing that cost along identical
observations; this is not an unbiased strategy win-rate claim.

The useful rank-60 parent has 48 singleton groups and six equal-factor pairs:

`48 × rank(2×6×6) + 6 × rank(4×6×6) = 48×56 + 6×105 = 3318`.

The initial parent had only five pairs, giving 3325. Rank/density-only retention
lost the new grouping, despite visiting it. The old complete local table had
3324 from other constructions, so the actual local gain is six, not seven.

## Optional single-walk observers

`bud_parent_walk.w` now accepts up to eight additional read-only price observers.
They preserve winners from the **same walk**, with no extra attempted flips,
RNG use, acceptance decisions, or edits to the walked state. Each winner is a
private state copy, independently checked by the existing exact tensor gate
before retention and again on export. They are off by default and never alter
a live CPU/GPU fleet lane.

The low-level price-file format extends the usual four lines:

```text
LIMIT
primary U costs, starting at zero and containing LIMIT+1 entries
primary V costs
primary W costs
observers N
observer 0 U costs
observer 0 V costs
observer 0 W costs
...three rows for every remaining observer...
```

Each additional observer price is a canonical decimal integer in
`0..1_000_000_000`; only the zeroth entry may be zero. `N` is `1..8`.
Sidecars require `MODE=walk` and cannot
be combined with grid or holdout objectives, whose cover semantics differ.
The ordinary four-line and five-line grid formats are unchanged.

Additional outputs are `observer-I-trial-J.txt` with `BUD_OBSERVER` log rows
containing score, rank, density, and best observation time. Existing files are
not overwritten. The primary `trial-J.txt`, optional `end-J.txt`, and existing
log/accounting fields retain their meanings. For example:

```sh
tungsten --release --native -o /tmp/bud-observers tools/bud_parent_walk.w
mkdir /tmp/bud-observer-run
/tmp/bud-observers /path/to/parent.txt 4x4x5 /path/to/prices-with-observers.txt \
  8 64 65536 walk 912071 /tmp/bud-observer-run 2 4 4096
```

Price-table numbers are caller-supplied scores, **not a tensor-rank oracle**.
Bind bucket prices to checked leaf recipes, materialize any selected product,
and run the independent composition checker before claiming its bound. These
tables are the low-level native interface; the existing Ruby portfolio runner
does not implicitly generate sidecars or change its objective.

## Work and verification

One native run with a rank primary and context sidecar reproduced all 336 saved
primary winners, context winners, and endpoints from the paired study. That
used **469,762,048 attempts rather than 939,524,096**. Recorded wall time was
6.48 seconds versus 13.52 for the previous paired runs; these are single
non-isolated measurements, not a general 2× throughput claim.

The old binary hash was
`76ad85fbf2077fe7315ceb7d448227d24fbc7673eabb4eae1f1c77ddbca655a1`;
the sidecar build was
`408976232b063a0c1ffae7330fdb17bcb99eaed33a4b83939902e1e469993969`.
The compiler invocation was release/native with LTO disabled. Native tests:
**13 runs, 831 assertions, zero failures/errors/skips**. They cover all eight
observer slots against separate runs, exact matching tensors/metrics/endpoints,
bad table dimensions/prices/counts, incompatible modes, overwrite refusal,
and the existing default, grid, holdout, and public-shape behavior.

```sh
METAFLIP_BUD_WALK_BINARY=/tmp/bud-observers \
  ruby spec/bud_parent_walk_test.rb
```

Independent Python audits of each experiment checked 169 distinct tensors,
6,862 terms, and 66,451 pair XORs. All sidecar outputs exactly match the
corresponding independently verified separate-run tensors.

## Upstream composition and comparison

Both pricing runs started from the same 11,280-parent corpus and frozen leaf
table. The rank winners plus endpoints added 99 identities and yielded 53
lower local prices. Adding 36 context winners yielded **109** lower local
prices and 11,415 total identities. Full planner/recipe checks ran for both
corpora; no unchanged-price shortcut or hypothetical channel was admitted.
The 109 rows include the original 53 shapes; context snapshots add 56 newly
improved shapes and also improve some overlapping rows further.

All 14 improved prices below the reference screen were materialized, including
three newly crossing shapes and eleven previously flagged shapes. The separate
composition checker verified **71 tensors, 106,119 terms, 20,519,767 pair XORs**,
with zero failures. The other 95 price improvements remain arithmetic recipes,
not newly expanded tensor certificates. Rank-only endpoints supplied the
20×25×28 and 20×25×32 crossings; context retention supplied 10×24×24.

All 14 survive fresh Lille pages and a reference closure using 8,453 exact
catalog partition families, 261 published families, and 359,973 expressions.
There are 49 skipped catalog expressions with explicit reasons, so this is
not an exhaustive theorem about every published construction. GitHub HEADs
were rechecked and remain:

- [matmulcatalog](https://github.com/solven-eu/matmulcatalog):
  `f3a7f0f61b1005666c2cb03f98f2a16727604ea0`;
- [FastMatrixMultiplication](https://github.com/dronperminov/FastMatrixMultiplication):
  `db560ca5811bc38d5a6d5c0a3ec4315937ceabce`.

The local-only evidence bundle is
`benchmarks/matmul/metaflip/frontier_observer_audit_2026_09_08/`. It preserves
the two experiments, exact tensors and products, reference pages, source and
binary versions, compressed pricing inputs, and audit hashes. Full tensor and
product replay is local; rerunning the whole pricing campaign still requires
the pinned earlier parent/recipe ancestry. Generated/imported leaves remain
outside source commits and are not redistribution-cleared.

Next: reuse several near-reference contexts as simultaneous observers, then
independently check their full tensor and composition effects. Do not promote
these candidates to confirmed world records without resolving the remaining
reference-coverage, equivalence, and provenance checks.
