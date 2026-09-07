# Exact packing and parent-neighborhood follow-up, 2026-09-06

Targeted parent walks improve two earlier local GF(2) products:
10x16x16 from rank 1535 to 1530, and 10x12x12 from 895 to 894.
Reusing their new parents across the corpus improves six targets in total.
The primitive 4x4x5 parent still has rank 60. These are verified research
candidates, not confirmed world records or a change to the live record ledger.

The construction gains one more disjoint equal-U pair: six pairs and 48
singletons give `48*26 + 6*47 = 1530` and `48*15 + 6*29 = 894`.
The earlier 8x12x15 rank 896 target did not improve in its targeted walk.
All imported-leaf and GPL-parent attribution/redistribution restrictions in
[the earlier report](BUD-PARENT-WALKS-2026-09-06.md) still apply.

## Bounded exact packing

`bud_packings.rb` enumerates positive-gain equal-factor groups, separates
their overlap graph into disjoint components, and solves each component by
memoized set packing. Nonpositive-gain groups can be replaced by singletons
without increasing the **formula** cost. This argument does not establish
minimum rank after output cancellation, or optimal tensor rank.

The candidate, vertex and state limits are explicit. A limit returns a
verified constructive partition with `exact_within_model: false`, never an
optimality or no-candidate claim. A complete result is optimal only within
the stated single-equal-factor, bounded-leaf model and frozen leaf library.
The report mode first replays every baseline recipe, rejects changed leaf
pricing, and retains a no-worse baseline formula if the bounded search stops.
Formula improvement alone is not automatic admission of a lower exact rank.

The frozen 352-target enriched corpus needed just 3,220 memoized states;
the largest connected component had seven terms. All 352 cases completed
without a cutoff, with **zero formula or exact-rank improvements**. Thus
suboptimal packing of those particular winning parents was not the bottleneck.
This does not close the search over other parents or construction families.

Six focused tests (136 assertions) compare the solver with an independently
written exhaustive partition recurrence, exercise mixed-axis groups, all
three cutoffs, exact recipe replay, baseline preservation, pricing drift,
argument errors and overwrite refusal. The mixed-axis fixture genuinely
beats every pure-axis partition, 328 to 324, so the test is not only a tie.

## Matched parent experiments

The first five studies use 16 trials of 512 batches of 512 attempted moves
for each of ordinary wandering, greedy acceptance and annealing.

| Parent source | Scale | Initial | Best in all three policies |
|---|---|---:|---:|
| 4x4x5 rank 60, density 628 GL frontier | 4x4x2 | 1535 | 1530 |
| Same | 3x3x2 | 895 | 894 |
| Same | 2x3x3 | 896 | 896 |
| 4x4x5 rank 60, density 919 raw seed | 4x4x2 | 1535 | 1530 |
| 4x4x5 rank 60, density 662 orbit seed | 4x4x2 | 1535 | 1530 |

Two larger matched sweeps then use 32 trials of 2,048 batches of 512 moves:
33,554,432 attempted moves per policy and setting.

- Rank-debt allowances 2, 4 and 8 all reached exactly 1530 in every trial
  of all three policies. Larger debt is not promoted as a better default.
- Density-slack allowances 4, 16 and 64, with debt fixed at 2, also all
  reached exactly 1530. The wider neighborhoods produced different parents
  but no better target rank. Density slack is likewise not promoted.
- The existing wander rule permits a per-flip density increase of
  `density_slack + current_rank_band`; it is not a total-density ceiling.
  Changing rank debt also changes that allowance, so the debt sweep is a
  comparison of the actual coupled setting, not an isolated rank effect.
- The default density-four run reproduced all 96 prior debt-two outputs
  byte-for-byte in parent identity and trial outcomes. Optional parameters
  do not change the ten-argument native invocation's default behavior.
- Sampled endpoint counters confirm excursions: density-four wandering
  reached parent rank 61 / density 716, while density-64 wandering reached
  rank 62 / density 726. These are batch-end observations, not path maxima.

These are matched **move-attempt** studies, not throughput benchmarks.
The separate CPU/GPU fleet continued running, and elapsed times must not be
read as controlled hardware comparisons. Across the five short studies and
six larger settings, 666,894,336 attempts were executed. No production
scheduler, acceptance policy or live archive was changed by these tools.

## Exact audits and replay

Appending the new parents to the frozen corpus yields 651 term-order-distinct
parents (1,175 input files), versus 324 previously. The same 150-leaf library,
scale/dimension bounds and 16 mixed-packing trials give 25,141 product cases
and the same 352 targets. Six targets improve; none regresses:

| Canonical shape | Previous local rank | New exact GF(2) witness rank |
|---|---:|---:|
| 5x12x12 | 525 | 522 |
| 5x12x16 | 700 | 696 |
| 5x16x16 | 930 | 924 |
| 10x12x12 | 895 | 894 |
| 10x12x16 | 1190 | 1188 |
| 10x16x16 | 1535 | 1530 |

All six retained recipes use the same rank-60, density-641 parent with six
U-pairs. Their full coefficients, source lineage and audits are in
`benchmarks/matmul/metaflip/bud_parent_walk_2026_09_06/followup/`.
The entire new 352-target output passes independent Python reconstruction:
159,771 terms, 5,225,204 support-pair XORs. The six retained copies were then
independently replayed again: 5,754 terms and 202,617 support-pair XORs.
The 21-term sum is across six different targets, not a single-rank saving.

The scan's reported elapsed time includes macOS hibernation from
2026-09-06 05:28:20 to 15:22:46 CDT (low battery). It is not a timing result.
The live fleet recorded one 2x5x6 GPU failure across that interval; CPU/GPU
move counters advanced after wake. Failure details were not retained in the
overwritten child log, so no hardware-fault diagnosis follows. The fleet was
not manually restarted; its health flag remains degraded until the affected
shape completes a clean accelerator epoch. Its existing retry policy is
unchanged by this experiment.

Every saved native parent is verified by the native tensor checker, its
composition score is checked by the Ruby implementation, and every product
is fully reconstructed. The older independent Python tensor verifier also
passed all 816 outputs of this follow-up's native studies and all 352
packing-corpus products. These are 1,168 audit cases, including repeated
witnesses, not 1,168 distinct algorithms.

Evidence directories:

- `/private/tmp/metaflip-bud-parent-20260906-445-{gl-442,gl-332,gl-233,raw-442,orbit-442}`
- `/private/tmp/metaflip-bud-parent-20260906-445-debt{2,4,8}`
- `/private/tmp/metaflip-bud-parent-20260906-445-density{4,16,64}`
- `/private/tmp/metaflip-bud-packing-20260906-corpus`

Independent audit manifests:

- `/private/tmp/metaflip-bud-parent-20260906-445-independent-audit.json`
- `/private/tmp/metaflip-bud-packing-20260906-independent-audit.json`
- `/private/tmp/metaflip-bud-parent-20260906-debt-independent-audit.json`
- `/private/tmp/metaflip-bud-parent-20260906-density-independent-audit.json`

From the bit directory:

```sh
tungsten --release --native -o /tmp/bud-parent-walk tools/bud_parent_walk.w
METAFLIP_BUD_WALK_BINARY=/tmp/bud-parent-walk ruby spec/bud_parent_walk_test.rb
ruby spec/bud_packings_test.rb

ruby tools/bench_bud_parents.rb --binary /tmp/bud-parent-walk \
  --parent lib/metaflip/seeds/gf2/matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt \
  --library /path/to/frozen-leaf-library --scale 4x4x2 \
  --trials 32 --chunks 2048 --steps 512 --seed 900001 \
  --debt 2 --density-slack 4 --output /tmp/new-parent-study

ruby tools/bud_packings.rb --library /path/to/frozen-leaf-library \
  --from-report /path/to/composer/report.json \
  --max-vertices 18 --max-states 5000 --max-candidates 5000 \
  --output /tmp/new-packing-study
```

The enriched library is not distributed with the bit. Its source audit and
unresolved redistribution terms remain separate from engine licensing.
No commit, publication, submission, or canonical record promotion occurred.
