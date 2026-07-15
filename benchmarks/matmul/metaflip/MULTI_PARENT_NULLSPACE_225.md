# Correlated multi-parent affine search for `<2,2,5>`

## Why this is stronger than pairwise crossover

Every exact GF(2) decomposition is a binary subset of rank-one tensor columns
whose XOR is the matrix-multiplication tensor.  For a union of exact schemes,
one known parent mask is a solution and the nullspace of the unique term
columns gives every other solution in that union.  Enumerating the resulting
affine coset can therefore expose a dependency using terms from three or more
parents even when every pairwise symmetric difference has only its full-parent
relation.

`flipfleet_rect_multi_parent_nullspace.w` implements that complete search in
pure Tungsten. It deduplicates terms by their full `(u,v,w)` triple, builds the
rectangular tensor-column nullspace, enumerates every affine solution when the
nullity is at most 24, materializes every subset no larger than the anchor, and
independently reconstructs the complete tensor before returning a candidate.
No fingerprint participates in admission.

The regression `flipfleet_rect_multi_parent_nullspace_test.w` pins both the
five-door hull and a six-parent hull containing deterministic block parent
1253.

## Five production doors

The union of the five retained rank-18 doors contains 55 unique rank-one
terms. Its column matrix has rank 51 and nullity four, so its complete affine
solution set has only 16 members. Seven have rank 18; none has rank 17. The
pairwise breadth-first closure reaches the same seven exact schemes and then
saturates. The two schemes omitted by the old single-best crossover are
documented in `ARCHIVE_NULLSPACE_CLOSURE_225.md`; a matched 1.12-billion-move
continuation found no downstream objective win, so they are not default doors.

## Every deterministic block parent, singly

`flipfleet_225_multi_parent_batch.w` added each of the 4,096 block-local GL
parents to the full five-door union and exhausted every affine coset:

```text
parents=4096
union=55..73
nullity histogram=4:1,5:210,6:3621,7:255,8:9
affine solutions=273424
rank-18 subsets independently gated=53936
rank below 18=0
gate failures=0
```

This closes the first correlated family suggested by the earlier pairwise
negative: a rank-17 subset cannot be assembled from all five doors plus any
one member of the complete deterministic block bank.

## Maximin block-parent pairs and triples

`flipfleet_225_multi_parent_pair_batch.w` greedily selected 32 block parents
by maximum minimum term-set distance from the five doors and prior selections.
The deterministic indices are:

```text
2577,1182,281,2650,293,1097,3822,151,
692,89,1458,1181,1213,3363,636,1879,
3169,30,456,1359,1530,2859,2958,2830,
667,1082,2908,3000,1449,3587,3572,955
```

All 496 five-door-plus-two-parent hulls were complete:

```text
union=88..91
nullity histogram=8:383,9:95,10:13,11:4,12:1
affine solutions=172288
rank-18 subsets independently gated=11040
rank below 18=0
gate failures=0
```

`flipfleet_225_multi_parent_triple_batch.w` then exhausted all 4,960 triples
from the same archive:

```text
union=105..109
nullity histogram=10:2979,11:1366,12:397,13:147,14:48,
                  15:12,16:5,17:4,18:1,19:1
affine solutions=11496448
rank-18 subsets independently gated=167995
rank below 18=0
gate failures=0
```

Across the base, single-parent, pair, and triple experiments, 11,942,176
affine masks were exhaustively visited. The 232,978 independently gated
rank-18 occurrences are not claimed unique across overlapping hulls. There
was no rank-17 mask.

## Replay

```sh
bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_rect_multi_parent_nullspace_test.w \
  -o /tmp/ffrmp-test
/tmp/ffrmp-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_225_multi_parent_batch.w \
  -o /tmp/ff225-multi-single
/tmp/ff225-multi-single 4096 /tmp/ff225-r17.txt

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_225_multi_parent_pair_batch.w \
  -o /tmp/ff225-multi-pair
/tmp/ff225-multi-pair 4096 32 /tmp/ff225-r17.txt

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_225_multi_parent_triple_batch.w \
  -o /tmp/ff225-multi-triple
/tmp/ff225-multi-triple 32 /tmp/ff225-r17.txt
```

These are finite exact negatives for the listed term unions, not a global
rank lower bound. The next scale step is a weight-17 XOR/cardinality solver or
meet-in-the-middle decoder over the full 32-parent union, which can mix terms
from any number of archive parents without enumerating its entire high-nullity
affine space.
