# Aligned-parent continuations and the native-refinement control

The shared-span alignment scout improves some raw parent representations,
but the existing native refinement worker already matches all four selected
starting gains. It should not become another default operation on the basis
of that comparison. This turn adds a measurement regression, not a new
runtime operator or a performance claim.

The matched continuation study made **1,073,741,824 flip attempts**. It found
no new retained rank bound or reference crossing. The recent deduplicated
cohort is now **3,836 parents / 186,876 distinct parent-context pairs**;
these are coverage counts, not numbers of records. The saved reference table
was not refreshed against worldwide literature in this study.

## Matched continuation

Four source/aligned pairs were selected from the preceding
[alignment study](BUD-GRID-ALIGNMENT-2026-09-09.md): sort by price relative to
the smaller retained/reference bound, then saving, target and full identity;
take at most two pairs per parent shape, with distinct source identities and
targets. Only two parent shapes supplied eligible pairs, so four—not the
maximum eight—were tested.

Each arm uses 16 trials, 256 chunks, 16,384 attempts per chunk, observation
every 2,048 attempts, debt 2, additional density slack 8, and a 50,000-state
mixed group/grid scoring budget. Both `walk` and deterministic `anneal` run
from both sources, with paired seeds and alternating arm order. The price
tables are bound to full verified GF(2) leaf witnesses. Absolute starting
density can differ between representations; equal seeds do not imply equal
trajectories. These are efficacy trials, not isolated throughput timings.

For 8x10x14, all 32 aligned trials recovered retained rank 724, versus 2/32
original-parent trials. No arm beat 724. Across the other three cells,
annealing/ordinary-walk results were mixed. Broader repricing of 447 distinct
input/output/cleanup parents across 63 scales found four aligned-pool
advantages over the original pool; all remained worse than retained bounds.
Three rank-105 4x5x7 outputs compressed to 104, and one rank-24 3x3x3 output
compressed to 23. These remove excursion debt, not primitive rank records.

The walker was rebuilt with `--release --native` from the current scorer
sources. A host assertion initially counted the starting score once per
trial; the implementation correctly counts it once for the whole run.
The first completed run was recovered from its saved output, not rerun.
`counter-preflight-failure.json` records that measurement error. The first
run's host `seconds` value measures readback, and aggregate host time excludes
that earlier launch; neither is a timing comparison. An earlier setup
metadata failure performed zero native work.

## Compare against what MetaFlip already does

The actual public binary was run with `--refine-batch ROOT 1 8`, without the
optional composition-runtime argument. This invokes eight bounded jobs,
not the live fleet, TUI, GPU, or an indefinite worker. Each result was checked
against the independent native-worker oracle: pair/matrix cleanup, all six
bounded basis variants, and source/selected-base coordinate projections.

| Target context | Original raw | Original + native refinement | Aligned raw | Aligned + native refinement |
|---|---:|---:|---:|---:|
| 8x10x14 | 726 | 724 | 724 | 724 |
| 10x12x21 | 1555 | 1554 | 1554 | 1554 |
| 6x12x12 | 593 | 588 | 588 | 583 |
| 6x9x9 | 353 | 349 | 349 | 349 |

This is the consequential control: the earlier raw-parent advantages do not
establish an incremental benefit over MetaFlip's existing pipeline. The
583 result after alignment plus refinement is not yet compared against two
rounds of existing refinement. Equal prices also need not have identical
tensor identities. Both limitations preclude claiming redundancy for the
whole alignment family or an unconditional win for it.

The worker emitted 166 checked occurrences / 131 distinct output objects.
Including its inputs gives 138 parents priced in 8,694 contexts. It emits
all six basis variants; its rank/pair-count selection is only for choosing
projection bases. No new default work was enabled by this audit.

## Bounded packing follow-up

The initial native-output repricing had 41 packing fallbacks on five parents.
A second pass raised the component cap from 24 to 64 vertices and the state
cap from 50,000 to 200,000, keeping 50,000 candidates and 2x2 grids. Each
query had a three-second limit, with 120 seconds total; no timeout occurred.
The better prior constructive result was retained if the new pass fell back.

Twenty prices improved, by at most 20 multiplications; none beat retained
bounds. Twenty-five cases finished exactly within the enumerated packing
model. Sixteen remained bounded, rather than being called exact or exhausted.

Those sixteen have an independent rational dual check. Assign each parent
term a nonnegative weight. For every legal positive-gain group, verify that
its term weights sum to at least its saving against singleton expansion.
Then any disjoint packing saves at most the sum of all weights, giving

```
formula lower bound = ceil(parent_rank * singleton_cost - sum(term_weights))
```

For equal-factor buckets, checking the cheapest `k` weights covers every
`k`-subset; the independent checker enumerates every applicable literal 2x2
grid separately. It checks 677 bucket-size constraints, nine grid constraints,
and 78 full parent/leaf tensors. All sixteen lower bounds exceed or equal
the retained formula prices, with minimum margin 107.

This closes only the fixed-library disjoint-group/grid **formula-price**
question for those cases. It does not bound the final rank after XOR
cancellation, arbitrary rewrites, other leaf libraries, or tensor rank.
The dual is offline evidence, not a new runtime pruning rule.

## Verification and retained evidence

The focused `packing_primary_walk_test.py` regression now covers three trials
with partial observation spans for pair, group and grid objectives. It checks
`1 + trials * chunks * ceil(steps / cadence)` evaluations, per-trial output
identities, complete tensors, and attempted/observed counts. Existing steering,
reproducibility, fallback, rank-above-64 and malformed-table checks also pass.
There was no runtime counter bug to fix.

Independent replay checks all 447 continuation parents and all 256 saved
winner scores (183 distinct exact score problems). One transient native
fallback occurred during search, but every exported winner score agrees with
the independent exact restricted objective. Selected product replays cover
12 continuation, eight native-control, and eight tightened constructions;
these are selected witnesses, not a claim that every possible composition
was materialized.

A relocated replay uses only archived source/checker/library snapshots. It
rechecks all 36,855 prices from the two current repricing passes, reruns the
eight actual native jobs, verifies the dual certificates and selected
products, and recomputes the cumulative identity/context union. The billion
flip attempts are not repeated during cold replay.

Evidence is retained outside the checkout at
`~/.local/share/tungsten-metaflip/evidence/2026-09-09-aligned-continuation.tar.gz`.
The archive includes inputs, outputs, logs, pinned binaries and source,
comparison tables, independent checkers, bounded/incomplete statuses, and
file manifests. It is 9,472,559 bytes; SHA-256:
`47577f3033f67e518bafd1872341bdbcf84a2f88a05bac79aae574f8d44c11f4`.
All 2,629 manifest-listed archived payloads were hash-checked after packing.
No bulk benchmark artifacts or canonical seed changes belong to this commit.

Next useful comparison: run composition-priced continuations from the
existing native-refinement variants, with the same verification/work budget.
Improve routing or feedback only if that experiment shows a gain; the raw
alignment comparison is not sufficient justification for another default
mutation stage.
