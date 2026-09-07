# Screened kernel words and paired representation search

## Cofactor-aware joint leaf search

`outer_cofactor_join.rb` now searches two leaf representations jointly and
fuses terms that share two factors, XORing the third. This is a different
operation from identical-triple cancellation. It found independently checked
local GF(2) ranks 507 for 7×7×15, 1164 for 11×11×15, and 1200 for 11×13×13.
The prior local ranks were 508, 1168, and 1204. No worldwide-record or
addition-count improvement is asserted.

```sh
ruby bits/tungsten-metaflip/tools/outer_cofactor_join.rb \
  --output /new/output --kernel-pair-width 8 /path/to/outer-product.recipe.json
ruby bits/tungsten-metaflip/tools/outer_cofactor_join.rb \
  --replay /new/output/SHAPE-SLOT-SLOT.merge.json
```

The exact sparse join returns the minimum cofactor-normalized pair rank over
the retained pools. The optional paired-word shortlist (0 by default, at
most 32 per axis) is heuristic. Every selected leaf and full fused tensor
passes exact admission. `outer-cofactor-merge` recipes retain the higher-rank
raw product separately, and `composition_closure.rb` can consume these
checked recipes as constructive seeds. This is not yet a production fleet
lane or a throughput claim.

See the [cofactor audit](../../../benchmarks/matmul/metaflip/cofactor_merge_audit_2026_09_06/README.md)
for the eight bounded studies, independent Cartesian replay, exact witnesses,
fresh reference snapshots, and license/novelty boundaries.

### Three-axis words and outer-parent diversity

The join also accepts `--kernel-triple-width N` (default 0, maximum 16).
It composes one shortlisted kernel word from each vertex axis; all single
proposals remain available. The shortlist is heuristic, not a dominance
rule or a claim to exhaust the general linear group.

```sh
ruby bits/tungsten-metaflip/tools/outer_cofactor_join.rb \
  --output /new/output --kernel-pair-width 8 --kernel-triple-width 8 \
  /path/to/outer-product.recipe.json
```

Width-8 and width-16 triple words alone did not lower the four previous
incumbents. Changing the outer parent was more productive: a 980-configuration
screen followed by 16 bounded joins lowered nine local GF(2) ranks, including
15×15×15 from 2055 to 2048 and 13×13×16 from 1701 to 1696. Every retained
endpoint passed independent full tensor and Cartesian-pool replay. The
unchanged-leaf score, raw-rank allowance of 12, and target-diverse shortlist
are proposal heuristics; none is an admissible lower-bound prune.

The [extension audit](../../../benchmarks/matmul/metaflip/cofactor_extension_audit_2026_09_06/README.md)
retains the exact parent/allocation/leaf states and comparisons. Six of the
nine new local ranks are below the freshly fetched Lille listings. This is
not a worldwide-record certificate. The separate recursive propagation of
the *previous* three cofactor winners covers all 5,456 shapes with dimensions
2 through 32: 24 local improvements, including 21 derived shapes. None of
those 21 derived values beats its current Lille listing. The nine new
parent-diverse winners have not yet been included in that propagation.

This is an offline GF(2) representation search, not a new production fleet
lane or a world-record oracle. A leaf keeps the same abstract tensor while
its basis changes; truncation by the outer recipe can change the resulting
rank or coefficient density.

`outer_representation_walk.rb --screen-before-verify` now supports exact
term-set scoring before full tensor admission. Every selected leaf is fully
checked before changing state, every accepted history is replayed, and the
final whole product is always checked. Unselected raw proposals are not
reported as tensor witnesses. The default still fully checks all neighbors.

The 28-shape matched run compared 69,705 proposals and produced identical
histories, ranks, densities, and final byte hashes. Six single-round ABBA
cases observed 1.35x to 1.61x faster offline walks. Inputs were loaded outside
the timed region; a CPU/GPU fleet and another offline scan ran concurrently.
These timings do not measure native production flips/s or search success.

The broad single-word pass and its deeper continuation found density gains,
but no additional rank gains. The prior 13x13x16 rank-1701 witness remains a
separate, already-verified result.

## Paired words

`--kernel-pair-width N` shortlists at most N single-word actions per clipped
axis, then scores compositions on two different axes of the same leaf. It
includes the ordinary single moves, uses complete term-multiset identities,
and records both component words in every accepted paired move. A paired
move may improve even when neither constituent is individually accepted.

The shortlist is heuristic: it is not a dominance theorem or exhaustive
GL-orbit coverage. `settled` only means the particular bounded neighborhood
made no strict rank/density improvement in the last round. A round-limit
termination is separately recorded.

```sh
ruby bits/tungsten-metaflip/tools/outer_representation_walk.rb \
  --output /new/output --moves kernel --rounds 4 \
  --kernel-maximum 8 --kernel-pair-width 8 --screen-before-verify \
  /path/to/verified/13x13x16.recipe.json
```

The retained [paired-kernel audit](../../../benchmarks/matmul/metaflip/paired_kernel_audit_2026_09_06/README.md)
contains the matched baseline, screened pass, deeper continuation, width-8
and width-32 paired sweeps, six-case timings, frozen tools, and intermediate
leaf/whole-product snapshots. Its Python checker independently expands each
accepted basis word and checks every retained complete tensor.

Both paired sweeps found no rank gain. Width 8 accepted six paired actions
and improved density on three shapes; width 32 made no further improvement
on its 23 applicable targets. Independent verification passed for 398
retained tensors and all 250 accepted transitions, including prior passes
and benchmark histories. Use Python 3.10 or newer for the audit command.

```sh
ruby bits/tungsten-metaflip/spec/outer_basis_products_test.rb
ruby bits/tungsten-metaflip/spec/outer_leaf_portfolio_test.rb
ruby bits/tungsten-metaflip/spec/outer_representation_walk_test.rb
python3 benchmarks/matmul/metaflip/verify_representation_portfolio.py \
  --root benchmarks/matmul/metaflip/paired_kernel_audit_2026_09_06 --workers 2
```

Imported coefficients remain outside the distributable bit. No canonical
seed, live archive, record ledger, commit, or publication is changed here.

## Codimension-one zero-deletion filter

`projection_conditions.rb` adds exact single- and two-axis envelopes plus
joint-axis Boolean conditions for **deleted nominal terms**. It uses paired
primal/dual kernel lines with binary dot product one, and emits explicit
invertible basis words. It does not bound rank after duplicate cancellation;
such searches must not be pruned by this filter. Candidate tensor admission
is unchanged.

The [projection-filter audit](../../../benchmarks/matmul/metaflip/projection_filter_audit_2026_09_06/README.md)
retains the 177 single-axis and 81 two-axis screens, 112 solver queries,
higher-rank alternative leaves, and a six-parent three-way construction
screen. No new rank was found. Independent replay passed 506 complete
tensors, 2,692 clipping comparisons, and 463 basis/allocation transitions.
Solver replay is explicitly not an independently checked UNSAT proof.

```sh
ruby bits/tungsten-metaflip/spec/projection_conditions_test.rb
python3 -m unittest discover -s benchmarks/matmul/metaflip \
  -p test_verify_projection_filters.py
```

## Direct cancellation neighborhoods

`cancellation_patterns.rb` implements exact shared-factor matrix compression
and a three-to-two lookup after that compression. These act on complete factor
words, not hull signatures. The three-term lookup is limited to triples whose
three factor spans each have dimension at most two; it is not a general rank
minimizer. Callers must still tensor-check a completed replacement.

The [wide cancellation audit](../../../benchmarks/matmul/metaflip/wide_cancellation_audit_2026_09_06/README.md)
also contains an experimental, non-production 256-bit-factor flip/plus worker.
It executes 1.04 billion bounded attempts without improving rank. An exact
matched control shows periodic matrix compression changes temporary states
but none of the 224 retained best outputs. Longer reduction windows yield
lower-density ties on 13x13x16 and 13x14x16. These policies are not enabled in
the production fleet. Independent verification passes all 614 retained
unique tensors, and the native algebra tests also pass ASan/UBSan.

```sh
ruby bits/tungsten-metaflip/spec/cancellation_patterns_test.rb
```

## Exact matrix pockets and cross-leaf image certificates

The [shared-factor renewal audit](../../../benchmarks/matmul/metaflip/bud_renewal_audit_2026_09_06/README.md)
adds optional `--compression-width` and `--compression-slack` assessment to
`outer_cofactor_join.rb`. It checks a bounded number of pairs separately at
each nearby cofactor rank, then chooses by final compressed rank and density.
Defaults preserve the old single-minimum behavior. A matched nine-target pass
independently replays 103 assessments and finds no additional rank reduction.
The same audit independently constructs 45 improved local shared-factor
products; a wider metadata comparison leaves four candidates for further
novelty checks, not four certified worldwide records.

The later [cofactor propagation and continuation audit](../../../benchmarks/matmul/metaflip/cofactor_propagation_audit_2026_09_06/README.md)
retains a 7×11×12 improvement from rank 621 to 620 and a complete 95-output
propagation of the previous nine direct winners. The new direct gain requires
two additional shared-factor matrix compressions. Its independent checker
replays those nonempty histories with separate matrix row equations. This
also exposes a search limitation: a minimum cofactor score need not yield the
minimum final compressed rank. Near-best pairs deserve bounded post-compression
assessment; their cofactor rank is not a safe final-rank pruning bound.

The [matrix-pocket audit](../../../benchmarks/matmul/metaflip/matrix_pocket_audit_2026_09_06/README.md)
adds an offline exact 4x2x2 tensor lookup and neutral pocket-replacement arm.
The 28-incumbent census has 1,913 pockets and no rank reduction. Four-round
neutral descents lower coefficient density on 21 targets. A matched 16M-attempt
follow-up retains rank 1701 on 13x13x16, with density 37105 for the pocket arm
versus 37213 for its control. These remain unpromoted representation ties.

The companion delta join has an exact full-term collision score and a
factor-image disjointness certificate. All 588 cross-slot pairs in the 28
fixed recipes have a zero factor-image intersection on at least one axis.
Thus arbitrary leaf representation changes cannot produce *cross-slot*
duplicate cancellation in those fixed embeddings; changing the parent,
allocation, or leaf dimensions is outside that certificate. This closes the
cross-leaf collision arm without assuming a bounded shortlist covers it.
It does not rule out cross-slot algebraic recompression: six slot pairs
still overlap on two factor axes and are eligible for a targeted two-factor
merger search. Independent replay passes 316 tensors, all 1,913 census
pockets, 79 accepted pilot/full-sweep macro transitions, and 588 space pairs.

```sh
ruby bits/tungsten-metaflip/spec/matrix_pockets_test.rb
ruby bits/tungsten-metaflip/spec/leaf_delta_collisions_test.rb
```
