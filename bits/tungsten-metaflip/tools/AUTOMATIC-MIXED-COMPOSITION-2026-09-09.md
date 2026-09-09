# Automatic mixed-axis composition

This is the original `MFM1` integration audit. The default now uses
versioned `MFM2` mixed groups, while preserving old tickets exactly; see
[the mixed-group extension](NATIVE-MIXED-GROUPS-2026-09-09.md).

The native mixed-pair engine now runs by default after candidate refinement.
Every distinct verified input and refined parent, including rank ties, is
offered with its immutable 22-leaf bank. This extends the existing automatic
matrix cleanup, bounded basis proposals, coordinate projections and fixed-axis
group composition. It adds no runtime Ruby/Python dependency and does not
change the CPU/GPU flip kernels.

## Scheduling and exact admission

Mixed work has independent paged parent, recipe and result journals under
`composition/mixed/`. A parent/bank pair offers 27 ordered scale contexts in
`{2,3,4}^3`; an `MFM1` recipe binds the original parent ticket, context,
ordered output shape and predicted price. Its version fixes a 50,000-state
matching budget. Small components finish exactly when that budget permits;
large or exhausted components retain the engine's valid deterministic
packing. A fallback is not an optimality certificate.

Parent references are durable deferred work, not an immediate 27-recipe
reservation. At most 27 contexts are admitted per cold batch. Fixed-axis
and mixed pending recipes share the existing default 4,096 limit, and
mixed admission yields freed room while a source job is blocked. The old
nine-recipe-per-parent reservation and recovery rules remain unchanged.
`METAFLIP_COMPOSITION_PENDING=1269..1000000` selects a different limit;
`0` retains the explicit unlimited control.

The single low-priority native child expands at most two recipes after a
source and four per idle batch. It alternates lanes while both have work.
Each lane retains its 128-ticket priority window and forced-oldest service
every fourth lane completion. Both lanes share the verified output archive
and per-shape best index. Priority affects order, not admission or pruning.

The consumer rechecks full parent and leaf tensors, recomputes the plan and
price, and checks every output tensor coefficient before writing an archive
entry. A forged price, bank or missing leaf cannot be accepted using its
hash alone. Both journals recover interrupted appends and completion writes
without changing the other lane's tickets. Errors leave recipes pending;
stop preserves all unfinished work.

Status `compose_submitted/completed/pending/failures` now sums both lanes.
`compose_deferred` and the TUI's `deferred` field show unadmitted contexts.
Deferred-only work also wakes the coordinator when no source jobs remain.
`METAFLIP_COMPOSITION_MIXED=0` disables new mixed offers, but still drains
previously committed work. Re-offering a parent with a changed exact bank
queues new contexts while preserving its old dependencies and recipes.

## Focused checks

From the repository root:

```sh
bin/tungsten-compiler compile \
  bits/tungsten-metaflip/spec/refinement_backpressure_test.w \
  --out /tmp/metaflip-mixed-queue --release --native --no-lto
python3 bits/tungsten-metaflip/spec/mixed_composition_queue_test.py \
  /tmp/metaflip-mixed-queue
bin/tungsten-compiler compile bits/tungsten-metaflip/bin/metaflip.w \
  --out /tmp/metaflip-auto-mixed --release --native --no-lto
python3 bits/tungsten-metaflip/spec/refinement_fleet_test.py \
  /tmp/metaflip-auto-mixed
```

The focused mixed queue regression passes:

- Default-on intake, distinct same-rank parents, deduplication and exact
  leaf-bank changes without rewriting old dependencies.
- Recovery after interrupted parent, recipe and completion commits, with
  fixed-axis journal preservation.
- Three deliberately invalid dependencies/prices rejected before output
  archive admission, followed by valid restart and full tensor replay.
- Exactly 1,269 shared pending recipes: 450 fixed-axis plus 819 mixed,
  with 531 deferred contexts. A blocked source reserves against both lanes,
  gets first claim on freed slots and then resumes within the limit.
- Explicit unlimited and pre-existing over-limit drain controls.
- Deferred-only coordinator completion of 27 exact outputs, consistent
  status/TUI counters and no remaining owned child after stop.

The existing fixed-axis queue, grouped queue and backpressure regressions
also pass with new mixed intake disabled as their matched control. Public
release/native smoke tests cover 5x5, rectangular 2x5x6, rectangular restart
and disabled refinement, with independent tensor checks of both output
lanes. These use one CPU walker and no GPU; they are integration checks,
not throughput measurements.

## Completed finite search replay

Two retained parents were passed through the full native source-refinement
pipeline and all of their resulting finite composition work was drained.
These were ordinary queue runs, not hand-picked direct calls to the mixed
engine. Independent Python checks verified parent/recipe linkage, immutable
object hashes and complete output tensor identities.

| Parent | Fixed-axis completions | Mixed completions | Total |
| --- | ---: | ---: | ---: |
| 3x5x5/r58 | 159 | 486 | 645 |
| 3x3x8/r56 | 219 | 756 | 975 |
| Both | 378 | 1,242 | 1,620 |

All queues ended with zero pending recipes, zero deferred contexts and zero
failures. The outputs span 153 distinct canonical shapes. This automatically
reproduces 9x20x15/r1646 and 6x6x32/r774, already retained in the preceding
offline/native studies. There are **zero new local bounds** and **zero new
public-reference crossings**, so this milestone adds no world-record claim
or cumulative candidate count.

The comparison used the saved 5,984-shape local closure through dimension
32, augmented with the already retained newer bounds so they were not
credited again. The closure file's SHA-256 is
`0b4ad918bd36a262797cb89017513cbed0fe07dbdb832df4d5462c4e4e2c0da7`.
Saved public comparisons remain stronger than the two reproduced outputs
(1,604 and 758). This was not a fresh worldwide literature audit.

The report, spool and full tensors remain outside the checkout at
`/private/tmp/metaflip-automatic-mixed-20260909/completed-report.json`.
The original source SHA-256 values are
`72a7f671f68d0e83018f5b36d4f20ec23aa060a50a5f113e2c20cb6abbb52594`
and `69a371bb827ada61c304ede2565f07406fcd326f01e8348e73ea7fcca4318f69`.
No imported source tensor or generated output corpus is added to the repo.
The finite runs are stopped; there is no indefinite search left running.

## Limits and follow-up

- This is mixed disjoint-pair packing, not the offline packer's overlapping
  groups or exhaustive basis search. Supported no-saving contexts are kept
  too, because their constructive Kronecker outputs may be useful.
- Input rank is at most 512; packed output factors are at most 1,024 bits
  and predicted rank at most 16,384. Unsupported contexts advance the
  planning cursor without being counted as verified tensor completions.
- The pending recipe limit is not a disk-byte quota. Original candidates,
  deferred parent records and completed evidence can continue accumulating.
- Bank repricing requires a parent to be re-offered; there is no global
  reverse-dependency sweep or recursive wide-output intake.
- Wide outputs remain exact archive witnesses, not automatic live-worker
  seeds. Automatic cross-shape campaign dispatch is still separate work.

See [Native mixed-axis pairs](NATIVE-MIXED-PAIRS-2026-09-09.md) for engine
optimality boundaries and its independent matching/term-set tests.
