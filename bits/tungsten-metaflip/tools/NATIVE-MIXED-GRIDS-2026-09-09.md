# Automatic multi-grid composition

The low-priority native composition worker now packs multiple disjoint 2x2
grids together with mixed-axis shared-factor groups. It reproduces the three
direct constructions from the [two-grid parent study](TWO-GRID-PARENT-2026-09-09.md):

| Target | Previous native group price | Native grid rank |
| --- | ---: | ---: |
| 8x10x14 | 728 | 724 |
| 8x15x21 | 1556 | 1548 |
| 12x15x14 | 1550 | 1542 |

These are integration regressions, **not three additional discoveries**.
The underlying study has five verified local improvements and two
reference-crossing GF(2) candidates, not confirmed world records. Its
deduplicated recent rollup remains 916 parents / 24,732 parent-context pairs;
replaying existing parents does not increase that count.

## Exact construction and bounded work

Grid kinds U/V, U/W and V/W represent elementary shapes 2x1x2, 1x2x2 and
2x2x1. Each has exactly two distinct values in each constrained factor and
one term at every Cartesian cell. The unconstrained third factor is a
general linear map. The constructor checks all four cells, the full
partition, factor masks and oriented leaf masks before writing output.
Repeated cells or a third class are not accepted as a grid. When a cell
contains several candidate terms, the planner retains every alternative;
choosing one representative would be an incomplete packing search.

The existing immutable 22-leaf bank supplies the eligible grid leaves.
Unsupported shapes are disabled, not assigned an unattested price. No new
tensor seed, Ruby runtime or Python runtime is added to MetaFlip.

`ffmx_plan` first obtains the unchanged MFM2 group plan. It then optimizes
groups and grids jointly on equality components of at most 16 terms. A
separate 50,000-probe budget covers the entire parent/context, including
recursive memo hits and failed rectangle probes. Oversized or incomplete
components keep their previous group plan. When no bank-backed grid can
save, the additional solve is skipped. The existing 50,000-state pair and
50,000-probe group budgets remain separate and visible in the engine status.
The result never costs more than its group baseline. Fallback is not proof
of optimality, and none of these limits is a tensor-rank exhaustion bound.

The unchanged outer limits are rank 512, narrow input factors up to 63 bits,
leaf rank 128, output factors up to 1,024 bits and formula rank 16,384.
The worker independently checks parents and leaves and crosses the full
output tensor gate before archive/best/result writes. A price alone cannot
enter the archive.

## Automatic intake and replay

New tickets use `MFMD3` and recipes use `MFM3`, with up to 27 scale contexts
per distinct verified parent/bank/version. This includes rank ties and
refined parents. Work remains in the existing cold child and shares the
existing occupancy limit, backpressure, fair scheduling and stop handling.
No grid enumeration is added to a CPU/GPU per-flip hot loop.

Old MFM1 and MFM2 tickets retain their exact planner, bank and price when
resumed. Re-offering a parent under MFM3 creates distinct versioned work;
it does not rewrite the old evidence or scan the entire archive.

- `METAFLIP_COMPOSITION_GRIDS=0` offers the previous MFM2 group algorithm.
- `METAFLIP_COMPOSITION_MIXED_GROUPS=0` offers MFM1 pairs only.
- `METAFLIP_COMPOSITION_MIXED=0` disables new mixed intake.

These controls do not abandon already queued work. Outputs remain checked
wide archive tensors; automatic recursive wide-output composition and
cross-shape live-worker dispatch are not introduced by this change.

## Focused checks

The independent Python oracle checks 197 plans, including random costs,
duplicate cells, rank 512, deterministic replay, missing leaves, explicit
budget/size fallback and group-plan non-regression. It separately checks
the complete linear substitution and tensor identity of 40 outputs:
all 27 scale contexts, dense sheared grids in all three orientations,
two disjoint grids in a small tensor, and the three external-parent targets.
Both release/native and non-release builds pass. Malformed grid plans,
leaf/buffer bounds and invalid costs reject without writing the output.
The previous group suite also passes its 259 plans and 45 tensor replays.

The queue tests cover default-on grids, distinct same-rank representations,
all three replay versions, strict pair-to-group and group-to-grid gains,
forged recipe versions/prices, damaged or missing dependencies, interrupted
journal commits, the exact shared 1,269-recipe test cap, stop and a
deferred-only coordinator that exits with no remaining child process.
The rebuilt public `bin/metaflip` also passes bounded one-CPU/no-GPU 5x5
and 2x5x6 runs, rectangular restart and disabled-refinement checks. Those
timed runs preserve unfinished queue/deferred counts and stop their children;
they do not claim to exhaust every admitted recipe or measure GPU throughput.

```sh
bin/tungsten compile bits/tungsten-metaflip/spec/mixed_group_composition_test.w \
  --out /tmp/metaflip-grids --release --native
bin/tungsten compile bits/tungsten-metaflip/spec/mixed_composition_test.w \
  --out /tmp/metaflip-pairs --release --native
python3 bits/tungsten-metaflip/spec/mixed_grid_composition_parity_test.py \
  /tmp/metaflip-grids /tmp/metaflip-pairs --parent /path/to/external-parent.txt
python3 bits/tungsten-metaflip/spec/mixed_group_composition_parity_test.py \
  /tmp/metaflip-grids /tmp/metaflip-pairs
bin/tungsten compile bits/tungsten-metaflip/spec/refinement_backpressure_test.w \
  --out /tmp/metaflip-grid-queue --release --native
python3 bits/tungsten-metaflip/spec/mixed_composition_queue_test.py \
  /tmp/metaflip-grid-queue
```

The external parent is not redistributed. Its canonical MFR1 identity is
`aff53644b9d84e0ef7c4b6509050897b54b5894b8b89bf6004ca724990a56357`.
Omit `--parent` to run all 37 self-contained tensor regressions.

## Matched retained-corpus replay

The 350 distinct parents from the two-grid study were repriced at all 27
contexts with the same verified native bank. All 9,450 group/grid comparisons
use a pinned executable and identical 50,000-probe budgets. The grid plan
lowers **1,377 construction prices**, with zero regressions and zero fallback
cases in this corpus. The independent plan checker validates every reported
partition and price; this is not full expansion of all 9,450 recipes.

The comparison alternates group/grid execution order in 64-case batches.
Total subprocess time, including parsing and startup, is about 1.2 seconds
per arm; complete Python checking takes about 50 seconds. This single short
replay is not evidence of a throughput improvement or unchanged live flips/s.
The older overlapping-build timing draft is excluded; the retained v2 pass
checks executable SHA-256 before every batch and after completion.

Separately, the ordinary cold queue admits the winning parent twice,
deduplicates it to one grid ticket, drains nine fixed-axis plus 27 MFM3
recipes, and independently checks every emitted tensor. All three target
ranks above occur in that output set. The replay exits with no pending work.
This is an end-to-end integration check, not a new search campaign.

Reports and generated tensors are outside the repository:

- `/private/tmp/metaflip-native-grid-compare-20260909-v2/report.json`
- `/private/tmp/metaflip-native-grid-cold-20260909/report.json`

The retained evidence archive is
`~/.local/share/tungsten-metaflip/evidence/2026-09-09-native-mixed-grids.tar.gz`
(1,156,717 bytes), SHA-256
`078bd685b5a9bddc21e5547cb7a4302fe0e78937457b6053a917a0f83c84381c`.
A fresh extraction checks 185 file hashes and independently replays all 36
outputs using the copied checkers, without the original scratch paths.

The code adds no imported parent or leaf tensor, no seed promotion, and no
publication or submission.
