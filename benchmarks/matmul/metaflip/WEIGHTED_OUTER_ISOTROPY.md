# Weighted whole-outer isotropy

Status date: 2026-07-14.

Block composition is sensitive to the support pattern of the outer algorithm,
not just its rank.  An exact change of basis on the outer tensor preserves the
outer rank, but it changes which row and column blocks each outer factor
touches.  With unequal block sizes, that changes the dimensions, and therefore
the rank, of the leaf substituted at each outer term.  This note records the
complete rank-7 Strassen audit and the bounded rank-47 search.

## Complete Strassen audit: a useful restart bank

[`flipfleet_outer_isotropy_pareto.w`](flipfleet_outer_isotropy_pareto.w)
exhausts all `GL(2,2)^3` images of Strassen and all eight 3+4 block placements:
216 exact outer images and 1,728 image/allocation pairs.  The best nominal
formula is rank 248.  There are 480 formula-minimizing recipes; materializing
all of them produces 48 exact rank-247 recipes and eight distinct rank-247
term sets.

Every rank-247 recipe loses exactly one product because a mapped outer factor
becomes zero.  None uses duplicate-parity cancellation.  All eight distinct
endpoints have density 3,554 and 43 equal-factor pairs.  Their term-set
distance from the original saved rank-247 endpoint, and from one another, is
494, the maximum possible symmetric difference for two rank-247 term sets.
This is therefore a genuinely separated restart bank even though the scalar
quality metrics tie.

The original leader is retained, and three additional exact shoulders are
saved:

| certificate | SHA-256 |
|---|---|
| [`matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt`](matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt) | `cb18a91b28e9e8b452dde46f69d876638a5af733c1d419ea77185da1c2487ea3` |
| [`matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt`](matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt) | `834ccc02f4c95b1f9850fec78cf6192c0fdb444559467879494932a6e2e87f30` |
| [`matmul_7x7_rank247_d3554_outer_isotropy_c021_m4_gf2.txt`](matmul_7x7_rank247_d3554_outer_isotropy_c021_m4_gf2.txt) | `c367fce47db45109175c0381a4c74d765b1afba56cf8136dd354fbc0294fc1b4` |
| [`matmul_7x7_rank247_d3554_outer_isotropy_c024_m0_gf2.txt`](matmul_7x7_rank247_d3554_outer_isotropy_c024_m0_gf2.txt) | `1f282bf41e054487527c32bd9ecbbd1fc0243791ac5c647cb0b779c754c964ca` |

[`flipfleet_outer_isotropy_pareto_test.w`](flipfleet_outer_isotropy_pareto_test.w)
reloads and exact-gates all four files and checks every pairwise distance.

### Public-schema certificate

[`catalog_gf2_export.py`](catalog_gf2_export.py) converts the reproducing text
certificate to dense GF(2) JSON while explicitly permuting FlipFleet's
row-major output factor into the public output-transpose `W` convention. It
fully reconstructs the tensor before writing, reparses the JSON, reverses the
permutation, and reconstructs it again. The retained export is:

| certificate | SHA-256 |
|---|---|
| [`matmul_7x7_rank247_d3554_outer_isotropy_gf2.json`](matmul_7x7_rank247_d3554_outer_isotropy_gf2.json) | `3bab7abfd9f21b406572dc274e5fa656e69a512bcf9a6ecb258c24a4ef6a6c7b` |

A clean clone of FastMatrixMultiplication at commit
`e0ec7db4cb7d7ca41abbb2c6e3bd8c7de75c7c64` independently accepted that file
with its unmodified `Scheme.load(path, validate=True)`, reporting
`n=[7,7,7]`, rank 247, and `z2=True`. That upstream revision's own status
table lists 7x7 rank 249 over the rationals and 250 over ternary/integer
coefficients, with no binary-field entry. This makes the checked construction
a strong candidate GF(2) record, still subject to normal external review and
the possibility of an unpublished scheme.

## Rank-47 search method

[`flipfleet_weighted_outer_descent.w`](flipfleet_weighted_outer_descent.w)
scores the exact rank-47 `4x4x4` outer against a fixed block allocation.  Its
inner loop evaluates the 36 elementary transvections in `GL(4,2)^3`, accepts
the steepest strict improvement, and repeats to a local minimum.  Randomized
runs add reproducible transvection words of length 4 through 16 and eight
equal-formula plateau steps before descending again.

The fast scorer uses a fixed 2--8 leaf-rank table.  Every accepted endpoint is
cross-checked with the authoritative block-composition scorer and exact outer
verifier.  Any candidate that reaches the saved formula is fully composed,
oriented, exact-gated, serialized, reloaded, and exact-gated again.  The three
dimension-two leaves needed by the exceptional 12x12x14 recipe are local to
this harness; it does not mutate the shared FlipFleet leaf pool.

The `selftest` mode checks all 36 bitwise transvections against the
authoritative implementation, compares 32 random fast scores with the full
scorer, and asserts that a known one-generator minimum terminates after
exactly 36 neighbor evaluations.  That last assertion is the regression for
the nested-loop increment bug described below.

An additional pair neighborhood scores all 1,296 ordered pairs of elementary
transvections at a one-generator minimum.  Only the pair endpoint is scored,
so its first step may cross an unfavorable ridge.  After an accepted pair,
ordinary descent closes the new basin and the pair neighborhood is repeated.
Changed outers that merely tie a saved formula are still fully materialized,
because mapped-zero and duplicate-parity reductions are not visible in the
formula score.

### Validity boundary

An early development build placed the innermost source-index increment inside
the `source != destination` branch.  Its neighbor loop stalled at the diagonal
entry.  All runs from that build are invalid and are intentionally excluded
from the counts and conclusions below.  The loop was corrected before the
reported audits, stale processes were terminated, and the fixed-loop
termination assertion is now part of `selftest`.

## Rank-47 coverage and result

No tested rank-47 outer image improves a saved formula or creates a stronger
post-embedding cancellation.  This is a negative bounded search result, not a
proof over all `GL(4,2)^3` images.

| audit | coverage | result | measured runtime |
|---|---:|---|---:|
| d450 direct descent | all 93 materialized recipes; 3,348 generator evaluations | every saved outer is already a one-generator local minimum | 0.27 s real, 0.15 s user |
| d450 ordered-pair descent | all 93 recipes; 123,876 one-generator/pair evaluations | no pair accepted and no formula gain | 1.71 s real, 1.14 s user |
| d450 random multistart | 16 restarts for all 93 recipes; about one million generator evaluations | no formula gain | 41.46 s real, 13.79 s user |
| d450 balanced squares | every `q x q x q`, `q=12..32`, 128 restarts each | no formula gain | 32.87 s real, 28.13 s user |
| d450 selected hard targets | 128 restarts each for 12x12x14, 13x13x13, 13x16x20, 21x21x21, 26x32x32, and the ten cancellation-bearing recipes below | no formula or exact-rank gain | 21x21x21 took 14.56 s real including composition/reload; other runs were individually bounded |
| d677 direct descent | all 93 recipes | often descends to the d450 formula, never below the saved d450 result | completed |
| d677 ordered-pair descent | all 93 recipes; 227,988 evaluations | 73 pairs accepted on 53 targets; no formula gain over d450; all 11 changed formula ties materialized with zero additional cancellation | 40.05 s real, 25.31 s user |
| d677 random multistart | 16 and 128 restarts for all 93 recipes | no result strictly below the d450 saved formula | completed; the original wrapper did not retain timing |

The ten saved recipes with a formula-to-exact gap were each rechecked with 128
restarts: 13x13x16 (1651 to 1648), 13x13x17 (1781 to 1778), 13x14x16
(1768 to 1763), 13x14x17 (1908 to 1907), 13x15x15 (1798 to 1796),
14x14x16 (1885 to 1881), 15x15x15 (2014 to 2008), 17x18x19 (3422 to
3420), 18x19x19 (3820 to 3812), and 19x19x19 (4005 to 3993).  Each run
reproduced the existing exact rank but found no lower formula and no stronger
materialized rank.

The omitted square 21x21x21 target was also tested explicitly with allocation
`5,6,5,5 | 6,5,5,5 | 5,6,5,5`.  Its rank-5223 formula and exact rank remain
5223, with zero mapped-zero and zero parity reduction, so it does not improve
the public rank-5198 construction.

## Reproduction

From the repository root:

```sh
bin/tungsten compile --release --lto -o /tmp/weighted-outer \
  benchmarks/matmul/metaflip/flipfleet_weighted_outer_descent.w
/tmp/weighted-outer selftest
/tmp/weighted-outer scan
/tmp/weighted-outer pairscan
/tmp/weighted-outer pairscan677
/tmp/weighted-outer randomscan 16
/tmp/weighted-outer squares 128
/tmp/weighted-outer randomscan677 128

bin/tungsten compile --release --lto -o /tmp/outer-pareto \
  benchmarks/matmul/metaflip/flipfleet_outer_isotropy_pareto.w
/tmp/outer-pareto
```

The weighted tool now includes end-to-end milliseconds in its summary so
future long scans retain timing even when per-target output is filtered.

## Search implication

Whole-outer isotropy is worth keeping for very small outers where the full
group is enumerable: the Strassen audit produced eight maximally separated
rank-247 doors essentially for free.  The ordered-pair move is a real tunnel:
it crosses 53 d677 one-generator minima, but every resulting endpoint remains
at or above the d450 formula and the 11 exact ties add no mapped-zero or parity
reduction.  It is therefore useful as a diagnostic move, not yet justified as
a default fleet lane.  Further compute is more likely to pay on a better
rank-47 base scheme, on a more structured multi-generator identity, or on
improving a high-leverage rectangular leaf than by extending the same random
transvection restart count.
