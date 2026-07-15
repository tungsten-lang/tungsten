# Three-Strassen block-local GL/nullspace audit for `<2,2,6>`

This is a finite pure-Tungsten campaign around the exact rank-21 upper
construction for the live rank-20 `<2,2,6>` target. It is search coverage,
not a lower-bound proof.

## Construction

The baseline is the direct `2+2+2` output-column composition of three exact
rank-7 Strassen `<2,2,2>` leaves. For deterministic parent index `i`,
`flipfleet_226_block_gl_parent_lib.w` applies an unrelated short word of exact
leaf-local transvections to each of the three leaves, composes them with the
rank-3 schoolbook `<1,1,3>` outer, and reconstructs all 576 tensor
coefficients. The three words use independent nonce streams and independent
move schedules.

Reproduce the parent bank and full difference campaign with:

```sh
bin/tungsten compile \
  benchmarks/matmul/metaflip/flipfleet_226_block_gl_bank.w \
  --out /tmp/ff226-block-gl-bank --release
/tmp/ff226-block-gl-bank 4096 /tmp/ff226_block_gl

bin/tungsten compile \
  benchmarks/matmul/metaflip/flipfleet_226_block_nullspace_scan.w \
  --out /tmp/ff226-nullspace --release
/tmp/ff226-nullspace 4096 32 /tmp/ff226_rank20.txt
```

## Complete measured hull

All 4,096 generated parents were exact rank 21. Seventy nonce words returned
the baseline presentation; every one of the other 4,026 parents had the
maximum possible term-set distance 42 from it. A greedy zero-overlap archive
retained 32 parents separated by at least 30 terms, adding all 496 archive
pairs to the audit.

The complete result was:

- 4,592 total pairs, 4,522 with nonempty difference;
- difference 42 for every nonempty pair;
- nullity exactly 3 and column rank 39 for every nonempty pair;
- 31,654 nonzero dependency combinations enumerated (`4,522 * 7`);
- 27,132 proper hybrids (`4,522 * 6`), all independently reconstructed as
  exact rank 21;
- zero rank-20 projections, zero exact-gate failures, and zero capped hulls.

The three nullspace dimensions are the expected independent choices of which
disjoint Strassen block presentation to use. Every nontrivial subset swaps
one or two complete seven-term leaves, so this family tunnels broadly between
presentations but does not couple the blocks or save a term. The measured
scan took 1.136 seconds inside the program (1.14 seconds wall clock) on the
July 14, 2026 development host. The 4,096-parent generation/selection pass
took 1.11 seconds wall clock.

A matched ordinary-worker screen then spent 100 million moves from the
baseline and 100 million from the retained door with the same RNG seed and
the standard 10%/70%/20% campaign phases. Both arms remained exact rank
21/d108 with zero rejects; wall times were 5.088 and 5.106 seconds. The
baseline arm retained its original term set, while the door arm finished at a
different exact d108 presentation. This is neutral objective evidence but
confirms that the second door is an active basin rather than a dead import.

## Correlated multi-parent closure

Pairwise leaf swaps do not, by themselves, exclude a dependency using terms
from three or more parents. The dimension-generic
`flipfleet_rect_multi_parent_nullspace.w` therefore searched complete affine
solution cosets over unique joint term unions.

Adding each of the 4,096 deterministic parents to both retained doors visited
252,344 affine masks and independently gated 107,267 rank-21 subsets. Joint
hulls containing every pair from the separated 32-parent archive added 369,088
masks and 30,597 exact rank-21 subsets. Of its 4,960 triples, 4,956 had nullity
at most 20 and were completely enumerated: 52,050,432 affine masks and 591,135
exact rank-21 subsets. None of these searches produced rank 20. Four triple
hulls had nullity 30 and were deliberately not brute-force enumerated.

Those four caps do not leave a rank-20 ambiguity for this dictionary. The
pure-Tungsten `flipfleet_226_block_locality_test.w` regenerated all 4,096
parents and checked all 86,016 term occurrences. Every term belongs to exactly
one of the three disjoint two-column output blocks, with 28,672 occurrences in
each block and none spanning blocks. Restricting any exact subset to one block
is therefore an exact `<2,2,2>` decomposition. The checked equality
`R_GF(2)(<2,2,2>) = 7` forces at least seven selected terms in each block, hence
at least 21 overall. Consequently **no subset of the entire deterministic
block-local term dictionary can have rank 20**, regardless of its affine
nullity. This is a proof for the restricted dictionary, not a global tensor
rank lower bound.

## Retained door

Parent index 7 simultaneously optimized all three selection criteria:

- rank 21, density 108, and 21 equal-factor pairs;
- distance 42 and zero shared terms with the rank-21/d108 baseline;
- deterministic replay from the three nonce streams;
- complete exact verification before write and after reload.

It is saved as
`matmul_2x2x6_rank21_d108_block_local_gl_gf2.txt`, SHA-256
`6c74b5bb150e2e9d6529c00edcd319baaed3d8b53792024c7d0f7d71198b5405`,
and rotates as the second CPU door for `--tensor 2x2x6`. The nullspace scan
itself is not a production pool strategy: its finite family has been
exhausted and found no rank-20 projection.

`flipfleet_226_block_gl_frontier_test.w` independently regenerates index 7,
checks the maximum-distance certificate, enumerates its seven baseline-door
relations, materializes all six proper children, and verifies that all six
remain exact rank 21. `flipfleet_226_worker_door_test.w` then loads both files
through the production rectangular worker's separate parser/coefficient gate
and confirms that short ordinary walks preserve exactness.
