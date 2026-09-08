# One grouping pass for primary and observer objectives

The offline parent walker now prices the primary objective and its read-only
observers in one shared equal-factor grouping pass. Matched measurements show
about 4% less native time on the tested 4x4x5 parent and 7–8% on 5x5x5 when
observers are enabled. Saved tensors and walk accounting are unchanged.
This is not a default-fleet speedup or a new production search policy.

A separate bounded projection/continuation study produced one verified local
composition improvement: **5x32x32, 3460 -> 3430**. It remains above the pinned
reference screen of 3200. No primitive rank, main-square rank, or reference
crossing improved.

## Scorer and validation

The previous batched scorer shared grouping among observers, but the primary
objective still repeated that work. In observer mode, the price buffer now
starts with the primary table, followed by the unchanged observer tables.
`ffbp_observer_costs` evaluates all of them together. The public table format,
eight-observer limit, output numbering, RNG, tie-breaks, and verifier gates
are unchanged. Zero-observer, holdout, and grid paths retain their old scorer;
holdouts/grids remain incompatible with these sidecar tables.

Focused tests use nonlinear primary prices as well as eight distinct observer
tables. They compare independent single-objective runs, exact output bytes,
accounting, and direct bucket sums. Large rectangular and square cases check
both native layouts above rank 64. Result: **14 tests, 892 assertions, zero
failures/errors/skips**.

```sh
# Repository root; no fleet, GPU, or full rake suite.
nice -n 10 bin/tungsten-compiler compile \
  bits/tungsten-metaflip/tools/bud_parent_walk.w \
  --out /tmp/bud-unified --release --native --no-lto
METAFLIP_BUD_WALK_BINARY=/tmp/bud-unified nice -n 10 ruby \
  bits/tungsten-metaflip/spec/bud_parent_walk_test.rb
```

Binary SHA-256 before:
`c76188b9743d0f26bed7bae07134e15ca05853baa7025074095b0ee0593d0985`.
After:
`dca21c38ccd08d257b6896685174a95b8ad78fbb06b5b3a8ecd0e8035fed946d`.

Each benchmark cell has four matched repetitions in alternating order,
33,554,432 attempted moves per run, and byte-identical outputs. Medians below
are native milliseconds. All jobs were sequential, one-worker, and low
priority; process user/system times and every output are retained too.

| Parent | Observers | Before, ms | Unified, ms |
| --- | ---: | ---: | ---: |
| 2x2x5 | 0 | 697.5 | 700.0 |
| 2x2x5 | 1 | 700.5 | 698.0 |
| 2x2x5 | 8 | 702.0 | 702.0 |
| 4x4x5 | 0 | 350.0 | 351.5 |
| 4x4x5 | 1 | 365.5 | 350.0 |
| 4x4x5 | 8 | 369.5 | 354.5 |
| 5x5x5 | 0 | 388.0 | 389.5 |
| 5x5x5 | 1 | 424.0 | 392.5 |
| 5x5x5 | 8 | 429.0 | 395.5 |

The small/zero-observer differences include regressions and ties; these short
local measurements are not a universal non-regression guarantee. Replaying
the earlier 51-cell campaign additionally reproduced all **4,080 output
tensors and 51 inputs**, including every winner, endpoint, score, and native
accounting field except elapsed time. The replay attempted 1,711,276,032
moves and took 23.66 seconds. That whole-campaign timing is one observation,
not the matched benchmark above.

## Search: retain the higher-rank endpoint

The first follow-up targeted the rank-37 3x3x5 parent behind 10x27x27 at 4352.
Two parents at debt 2/4/6/8 received 32 trials each, 64 chunks of 65,536 moves,
observation interval 4,096, density slack four, and RNG 912097. All eight
cells remained at 4352. The 1,073,741,824-move study added 383 literal parent
identities, but full recomposition found no lower price. Debt also affects
the engine's density allowance: this is not an isolated rank-only ablation.

Mixed-bucket/grid packing of the closest 32 parents likewise found no gain.
All cases completed within the producer's stated model limits: leaf side 32,
40 vertices, 100,000 states, 50,000 candidates, and grid side four. An
independent checker verified all 32 disjoint covers and their exact prices,
**not the exhaustiveness or optimality of the packing search**.

Next, eight 3x3x5 parents were projected to 2x2x5, 2x3x4, and 3x2x4, with no
intermediate-rank pruning and deterministic pair cleanup before retention.
All **228,480** planned canonical dual-kernel views completed. The retention
allowance was one above the current target price; 338 new literal identities
survived. Independent dense-map replay checked these and all eight source
tensors: 346 tensors, 7,062 terms, 41,267 support-pair XORs. This verifies the
retained mathematics, not exhaustion over every possible projection.

Each projected source then received four rank-objective trials of 32 chunks
of 65,536 moves (RNG 912131, debt two, observation interval 65,536). Two prior
rank-matched controls received the same per-seed work. Across 340 seeds this
is 2,852,126,720 attempts. Every source reached the already-known primitive
rank: 18 for 2x2x5 or 20 for 2x3x4. Unequal cohort sizes do not support an
aggregate search win-rate comparison. Independent checking covered 2,836
unique tensors, 55,376 terms, and 397,317 support-pair XORs.

Raw projections alone gave no cheaper composition. Adding continuation
winners **and endpoints** gave 5x32x32 at 3430. Its parent is a rank-19
2x2x5 endpoint with U-bucket sizes `1,2,2,2,4,4,4`, at scale `16,16,1`:

```text
3 * rank(4,16,16) + 3 * rank(2,16,16) + rank(1,16,16)
= 3 * 666 + 3 * 392 + 256 = 3430.
```

The profitable endpoint was reached from two sources in the **single-dual
control** category. Do not attribute this gain specifically to using two
non-coordinate duals together. Parent tensor SHA-256:
`a2750f1c3e17b5973431f55b94b790a427ef8eb42c07f4c6274b934b2f5f3554`.
Expanded product SHA-256:
`708de8c081b3cf924c482ef7de6feaf2a9e1f8de056274a134b8ef1cb69bacff`.
Independent full recipe/tensor replay checked nine tensors, 9,507 terms,
and 702,628 support-pair XORs, including the expanded product.

The resulting corpus has **15,482 literal shape-plus-tensor identities**,
not isomorphism classes. Relative to the preceding bounded cohort's fixed
baseline, the deduplicated lower-price set grows from 71 to **72 shapes**;
six have newly expanded certificates and 66 remain arithmetic recipes.
The separate scoped reference-crossing shortlist stays at **41**. None of
these counts is a tally of confirmed world records.

## Evidence and next action

Local evidence lives under
`benchmarks/matmul/metaflip/unified_objective_audit_2026_09_08/`: both binaries,
before/after source snapshots, matched logs, full replay, negative controls,
projection maps, continuation outputs, compressed pricing inputs, and the
self-contained expanded product. Checksums exclude generated Python
bytecode. Earlier pinned local ancestry is still needed to reproduce full
pricing/search; copied product and projection checkers replay independently.
Imported data are not redistribution-cleared and are not included in commits.

The literature recheck found that the reserved-block residual search in
[Kauers, Moosbauer, and Wood, Section 5](https://arxiv.org/html/2602.11041v1#S5)
is already represented by our fixed-group/holdout tools. The earlier matched
holdout result remains negative; no duplicate production operator was added.
The next bounded target is the new rank-19 endpoint's composition value,
with rank-only endpoints retained and all proposed products checked exactly.
