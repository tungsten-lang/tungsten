# Batch observer scoring without changing the walk

Read-only observers now share the equal-factor grouping pass for each axis.
The matched runs retain exactly the same tensors, scores, tie breaks, and
walk accounting as the previous implementation. This reduces optional
multi-observer overhead; it does not change the production fleet, its default
policy, or the tensor verification gate.

The accompanying search produced **71 lower local composition prices**, but
**zero new reference crossings**. The rank-only control already supplies 70
of those improvements. The bounded reference-screen shortlist therefore stays
at **41 shapes**, not 112, and none is being promoted to a confirmed world
record. Primitive ranks and the main square ranks did not improve.

## Shared grouping and focused checks

Previously each observer rebuilt the same three equal-factor bucket lists.
`ffbp_observer_costs` now builds each list once, then prices it with every
observer table. Scratch scores are separate from retained winner scores;
the walk state, price tables, RNG, and primary acceptance path are unchanged.
The batching call is guarded by a positive observer count.

The independent Ruby test compares all eight observers against separate
single-objective runs. An additional test checks direct bucket sums and full
tensors for rank-132 rectangular and rank-125 square naive parents, exercising
both native layouts above rank 64. Existing default, grid, holdout, invalid
input, and overwrite tests remain in scope.

Focused result: **14 tests, 884 assertions, zero failures/errors/skips**.

```sh
# From the repository root:
bin/tungsten-compiler compile bits/tungsten-metaflip/tools/bud_parent_walk.w \
  --out /tmp/bud-batched --release --native --no-lto
METAFLIP_BUD_WALK_BINARY=/tmp/bud-batched \
  ruby bits/tungsten-metaflip/spec/bud_parent_walk_test.rb
```

Baseline binary SHA-256:
`408976232b063a0c1ffae7330fdb17bcb99eaed33a4b83939902e1e469993969`.
Batched binary SHA-256:
`c76188b9743d0f26bed7bae07134e15ca05853baa7025074095b0ee0593d0985`.

## Matched overhead measurements

Each row below has four matched repetitions in alternating before/after order,
8,388,608 attempted flips per run, and identical saved output bytes and native
accounting. Times are median native milliseconds; the local bundle also retains
process user/system time from `/usr/bin/time -p`. All runs were sequential,
single-worker, and low-priority. No GPU fleet was launched.

| Parent | Observers | Before, ms | Batched, ms |
| --- | ---: | ---: | ---: |
| 2×2×5 | 0 | 181.5 | 182.5 |
| 2×2×5 | 1 | 181.5 | 181.0 |
| 2×2×5 | 8 | 182.5 | 179.5 |
| 4×4×5 | 0 | 91.0 | 91.0 |
| 4×4×5 | 1 | 95.0 | 93.5 |
| 4×4×5 | 8 | 129.0 | 106.0 |
| 5×5×5 | 0 | 101.0 | 102.0 |
| 5×5×5 | 1 | 110.0 | 110.0 |
| 5×5×5 | 8 | 174.0 | 116.0 |

The eight-observer 4×4×5 and 5×5×5 cases use approximately 18% and 33% less
native wall time. Zero- and one-observer differences are small, including
one-millisecond regressions; do not infer a speedup for the ordinary fleet.
These short local measurements do not establish universal performance or a
statistically rigorous non-regression guarantee.

The full 51-cell campaign replay reproduced **4,080 output tensors** and all
51 inputs byte-for-byte, including every primary/context winner and endpoint.
Both versions attempted 1,711,276,032 flips. Total recorded wall time changed
from 28.44 to 24.25 seconds; that whole-campaign timing is one observation, not
an independent general throughput result.

## Search efficacy: mostly control gains

The experiment starts from the previously checked 11,415-parent corpus. It
selects eight price objectives per family among 13 useful parent families,
including 3×3×3, 4×4×4, and 5×5×5. The target side cap is 32. Selection retains
distinct complete price tables up to positive integer scaling and uses up to
four full-identity seeds per family, giving 51 seeds and 104 family/objective
combinations. This deduplication is only about price ordering: it does not
merge tensor identities, claim state dominance, or exclude untested shapes.

Each seed uses eight trials, 64 chunks of 65,536 attempts, observation interval
4,096, debt two, density slack four, and RNG seed 912083. Context retention
beats rank retention in 153/408 seed/objective comparisons. As before, this
is a retention comparison along identical walks, not a strategy win rate.

Independent verification checked **1,044 unique tensors, 44,775 terms, and
488,220 pair XORs**. Full recomposition and recipe checks then gave:

- Rank winners and endpoints: 487 new identities, 70 lower prices.
- Add context winners: 364 further identities, 71 lower prices.
- Final corpus: 12,266 distinct tensor identities.

The single extra shape is **10×27×27: 4387 → 4352**. It uses a rank-37
3×3×5 parent, not a primitive rank improvement over the existing rank-36
parents. This is exactly why composition value cannot be replaced by parent
rank alone. It remains above the pinned screened reference of 4315.

Five selected gains were fully materialized and independently checked:

| Shape | Previous local | Checked new | Pinned reference screen |
| --- | ---: | ---: | ---: |
| 10×27×27 | 4387 | 4352 | 4315 |
| 18×24×32 | 7480 | 7458 | 7245 |
| 19×24×32 | 8248 | 8226 | 7806 |
| 12×14×32 | 3200 | 3180 | 3104 |
| 10×18×20 | 2184 | 2168 | 2157 |

Their recipe replay checked **28 tensors, 45,995 terms, and 5,772,721 pair
XORs**, including all five expanded outputs. The other 66 improvements remain
arithmetic recipes rather than newly expanded certificates. The reference
column is the earlier bounded mixed-field construction screen, not a fresh
exhaustive literature audit or a constructive common-field theorem.

## Evidence and next action

Local-only evidence is preserved in
`benchmarks/matmul/metaflip/batched_observer_audit_2026_09_08/`: complete bounded
run logs, both native versions, input/output tensors, exact replay reports,
alternating-order measurements, compressed pricing inputs, and selected
expanded products. Full product replay is self-contained there; reproducing
the entire campaign still requires the pinned earlier composition ancestry.
Imported leaves are not redistribution-cleared and are not added to source
commits.

Do not allocate eight observers indiscriminately based on the 153 retention
wins. Full recomposition showed only one incremental shape beyond the control.
The next falsifiable target is the higher-rank 3×3×5 parent behind 4352:
test bounded continuation and mixed-bucket covers, retaining rank-only
endpoints and checking actual expanded products before promoting any gain.
