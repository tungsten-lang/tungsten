# Fixed elementary groups in offline parent walks

`bench_bud_parents.rb --holdout-indices ... --holdout-shape AxBxC` now
prices the held literal terms as a verified elementary matrix-multiplication
group. This is an optional offline objective, not a new production fleet lane.

The adapter verifies the group's coordinate maps and materializes the exact
GF(2) leaf for `elementary_shape * scale`. The native walker searches the
remaining tensor and rejoins the held terms before scoring or exporting a
complete parent. Its objective is the cheaper of:

- the existing pure-axis cover of the whole parent;
- the verified held-leaf cost plus a pure-axis cover of the remainder.

The second cover is used only while all held literals survive reinsertion.
Cancellation falls back to the whole-parent cover. No residual is exported
or admitted as a matrix-multiplication tensor. The independent Python replay
checks the held coordinate maps, complete leaf tensor, scores, and every
saved winner/end tensor; a price supplied to the native CLI alone is not a
certificate.

Unlike the dynamic one-grid enumerator, this fixed cover does not have a
rank-64 limit. Native shape/mask restrictions still apply: non-square offline
parents need a leading dimension in 2..7, other dimensions at most 15, and
each factor width at most 62 bits. Axis permutations can put a compatible
parent into that orientation. The ordinary CLI/default objective is unchanged.
Fixed-group mode currently requires one scale, no portfolio or dynamic
`--grids`, and a held-leaf shape within the bounded dimension-16 library.

## Checked experiment

The parent behind the existing 10x18x24 rank-2540 candidate has rank 170 and
shape (8,5,6). Rotating to (5,8,6) with scale (2,3,3), held indices
`131,134,130,163` form a 2x2x1 group. Its leaf (4,6,3) has checked rank 54.
The fixed cover reproduces 2540; the ordinary pure-axis cover costs 2544.
This recovers an already-known construction, not a new improvement.

Three ablations—ordinary full walk, fixed terms with the old score, and fixed
terms with the new score—each used walk/greedy/annealed policies with
16 trials * 128 chunks * 512 attempts, observe-every 32, debt 2, density slack
4, and seed 927907. Total: 9,437,184 attempts, 144 saved winners and 144 end
states. Independent replay checked 127 distinct complete tensors, 19,678
terms, and 524,000 pair XORs.

None improved its initial objective. For this experiment the two held-term
objectives also produced identical accepted-flip counts, saved winners, and
end states: the four-unit scoring benefit did not improve this search.
Keep ordinary wandering as a control. Timing under the concurrent CPU/GPU
campaign is not a throughput comparison, and this finite negative result is
not an exhaustion claim. Retained endpoints can still be priced for other
shapes through `extend_composition_parents.py` and checked literal covers.

That reuse admitted 107 distinct parents and produced four independently
verified local gains: 18x30x32=9165, 18x31x32=9741, 19x30x32=10125,
and 19x31x32=10733. Each saves three multiplications over the preceding local
closure; none beats the checked reference. The first construction uses an
ordinary-walk endpoint, not a held-group winner. Adding 180 held-grid covers
to the price model produced no additional gains.

A follow-up from that endpoint targets 18x30x32 directly with scale (6,4,3).
Matched walk/greedy/annealed runs at density slack 4 and 16 each used 32
trials * 256 chunks * 512 attempts. All 192 trials reached score 9162,
matching but not beating the checked reference, in 25,165,824 total attempts.
Independent replay checked 384 complete tensors, 65,135 terms, and 1,799,753
pair XORs. The larger constructions are now independently materialized and
verified: 18x30x32=9162, 18x31x32=9738, 19x30x32=10122, and 19x31x32=10730.
They save six each over the preceding local closure; only the first ties a
checked reference and none crosses it. The self-contained replay is in
`benchmarks/matmul/metaflip/fixed_group_walk_audit_2026_09_07` at repo root.

## Focused checks

Build the offline tool and unit spec from this bit with `--release --native`:

```sh
../../bin/tungsten --release --native -o /tmp/bud-parent-walk tools/bud_parent_walk.w
../../bin/tungsten --release --native -o /tmp/bud-holdout-test spec/bud_holdout_test.w
/tmp/bud-holdout-test
METAFLIP_BUD_WALK_BINARY=/tmp/bud-parent-walk ruby spec/bud_parent_walk_test.rb
```

The integration suite passed 11 tests / 682 assertions, including a rank-72
parent, exact larger-product replay, invalid map/cost rejection, and existing
mode behavior. The focused Python parent-audit/extension tests passed 19
tests. Six old-CLI parity cases matched all saved tensor bytes, scores, and
acceptance counts across 36,864 attempts per binary. These checks do not
authorize canonical archive promotion or redistribution of imported leaves.
