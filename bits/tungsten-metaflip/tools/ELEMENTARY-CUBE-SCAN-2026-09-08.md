# Exact elementary-cube replacement screen

`elementary_cube_groups.rb` recognizes a restricted, useful eight-term pattern:
two disjoint nondegenerate 2x2 elementary layers with the same free-factor array,
up to row and column swaps. It returns an exact 2x2x2 factor map; replacing that
block with a checked rank-seven leaf preserves the tensor over GF(2).

This is an offline library, not a change to the live fleet or a general
rank-seven subtensor detector. It keeps one checked map per exact eight-term
index set. That suffices to witness an 8-to-7 replacement, but does not prove
equivalence or dominance of other maps, leaf choices, or subsequent walks.

```ruby
require_relative 'elementary_cube_groups'
parent = MetaflipBudProducts.load_scheme(path)
result = MetaflipElementaryCubeGroups.scan(parent,
  max_layers: 50_000, max_pairs: 50_000, max_groups: 64)
result[:groups].each do |cube|
  partition = MetaflipElementaryCubeGroups.partition(parent, cube)
  # Pass the checked partition to the existing product/recipe exporter.
end
```

Each limit is explicit and sets `complete: false` when further work is cut off.
The pair limit counts attempted matching-layer comparisons, including overlaps.
The library has no wall-clock deadline; the census driver separately uses a
two-second per-parent timeout and a 180-second budget checked between parents.
Loading and final sealing are outside that deadline.

## Exact prerequisite, not a heuristic prune

Every free-factor value in two disjoint matching layers must occur at least
twice in the original parent. The detector therefore excludes singleton free
values **before generating layers**. This cannot discard a cube in the stated
model. `bud_packings.rb` exposes the restriction as `min_free_multiplicity`;
its default remains one, preserving existing grid-packing behavior and order.
The detector uses two; `prune_singleton_free: false` provides a control.

An earlier diagnosis blamed overlapping layer joins. That was wrong: all 17
limited cases were capped during layer generation, and observed joins had no
overlaps. The overlap-index prototype was rejected and removed. Its report and
exact source remain retained separately; it is not claimed as a performance win.

## Frozen-corpus experiment

All runs used one `nice -n 10` CPU worker, without the GPU or live fleet.

| Detector | Parents visited | Layer-limited cases | Reported cubes | Observed seconds |
| --- | ---: | ---: | ---: | ---: |
| Original layer pairing | 31,215 | 17 | 8 | 78.14 |
| Rejected overlap-index prototype | 31,215 | 17 | 8 | 77.22 |
| Singleton-free prerequisite | 31,215 | 0 | 8 | 49.43 |

The final producer completed its declared model on all retained parents. These
are single-run host timings, not a matched general throughput benchmark.
Independent replay checked all source tensors, factor maps and canonical-leaf
replacement ranks: **31,215 distinct tensor checks, 2,694,571 terms and
227,275,327 support-pair XORs**, including the leaf and source-body deduplication.
The independent checker does **not** certify absence of unreported patterns or
the producer's exhaustion claim.

The eight groups occur in six ordered parents. Four larger parents are
orientations of 20x30x32 and 24x25x32, each starting at rank 10,135. Two are
rank-eight 2x2x2 controls. Their canonical replacements gave rank 10,134 and
seven respectively, not lower than the current local prices.

We additionally enumerated all 216 GL(2,2)^3 coordinate-change codes on the
bundled rank-seven leaf, giving 36 distinct leaf representations. Independent
Python replay reproduced every code action and all **288** substitutions into
the eight reported cube maps, including cancellation against outside terms.
This audit checked 42 tensors, 40,808 terms and 14,255,964 support-pair XORs.
No variant improved the local price or gained extra cross-boundary cancellation.
Other cube maps, non-GL-equivalent leaves, and larger replacement patterns remain
outside this finite screen.

## Complete retained 5x5x6 follow-up

The reusable parent-cover scanner also covered all **445** retained 5x5x6
parents at 180 integral scales each: **80,100 cases** in 175.70 seconds.
Independent selection, tensor, map and price replay checked 445 tensors,
49,002 terms and 870,717 support-pair XORs. There were 8,500 saved covers;
3,670 were new to their existing parents. Full repricing considered 2,721,442
total group expressions, including 835,454 mixed expressions, in 57.03 seconds.
Neither direct pricing nor propagation lowered any additional price. This
finishes the previously sampled family, not the space of all 5x5x6 tensors.

The cumulative local cohort is unchanged: **336 distinct lower-price shapes,
35 expanded at their current best price, and 301 recipe-only candidates**.
There is no new primitive/main-square improvement or confirmed world record.
The pinned reference shortlist remains 45 and was not refreshed for this
non-improving batch. Numerical reference ranks are not constructive leaves.

## Validation and evidence

The focused suite passes **41 Ruby tests / 809 assertions** and **49 Python
tests**. It includes exact naive-cube counts, literal reversal, invertible raw
factor images, duplicate terms, real substitutions, all cutoff types, small
flipped-parent comparison against unfiltered layer pairs, singleton-free
controls, source/map/accounting mutations, and invalid source tensors even after
all supplied hashes are rebound.

The independent census checker is reusable:

```sh
nice -n 10 python3 -B benchmarks/matmul/metaflip/verify_elementary_cube_census.py \
  --root CENSUS --inputs BASE/inputs.json --price-plan BASE/report.json \
  --leaf bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt \
  --output CENSUS/independent-audit.json
```

It verifies the visited corpus prefix and every reported replacement, including
the actual rank after GF(2) cancellation. `complete` means replay finished;
`search_absence_certified` remains false even when all producer rows completed.

Local evidence is retained under
`benchmarks/matmul/metaflip/elementary_cube_audit_2026_09_08/`: all three census
versions and source snapshots, final audit, complete leaf-orbit replay, full
5x5x6 scan and repricing, frozen input/price documents, prior cohort summary,
drivers, checkers, provenance, licenses and a checked manifest. Large
`inputs.json` files are gzip-compressed with their uncompressed hashes recorded.
Historical pins resolve to the historical source, not the edited current file.

Imported tensors and derived artifacts stay outside commits pending
redistribution review. Only the tools, tests and this documentation are intended
for commit. No push, publication, submission or canonical archive change occurs.
