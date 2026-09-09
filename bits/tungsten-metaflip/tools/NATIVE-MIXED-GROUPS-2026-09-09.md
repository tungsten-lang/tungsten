# Automatic mixed groups, with pair-plan fallback

MetaFlip now considers shared-factor groups of size 2, 3 and 4, on different
axes within the same construction. This is native Tungsten in the existing
low-priority deferred composition worker, not another runtime script or a
change to CPU/GPU flip kernels. No new seed tensor is bundled.

## Exact scope and limits

The existing immutable 22-leaf bank provides all singleton and pair leaves
for the 27 ordered scales in `{2,3,4}^3`. Larger groups are eligible only when
their oriented leaf shape is also present in that exact bank; missing leaves
have no price and cannot enter a plan. This is not a general grid packer or
an exhaustive tensor-rank search.

`ffmg_plan` first computes the unchanged mixed-pair plan. It then searches
disjoint groups on equality-connected components of at most 16 parent terms.
One shared budget limits the entire parent/context to 50,000 group probes,
including memo hits; the preceding pair stage retains its separate
50,000-state budget. A component that is too large or does not finish keeps
its original pair plan. Every completed component is checked against that
baseline, so the resulting formula price cannot regress. Fallback is reported
explicitly and does not certify optimality.

The limits remain input rank 512, positive narrow factors of at most 63 bits,
leaf rank 128, packed output factors of at most 1,024 bits and predicted
output rank 16,384. The constructor validates the entire partition, shared
factors and available leaf masks before touching its output buffer. The
normal worker also rechecks parent and leaf tensors and checks the complete
output tensor before archive admission. Formula prices are not tensor gates.

## Durable integration

New parent tickets are `MFMD2`; their 27 contexts become `MFM2` recipes.
The recipe and parent versions must agree. Existing `MFMD1`/`MFM1` work keeps
the previous pair algorithm and its immutable dependencies, even after
restart or a change of configuration. Re-offering the same tensor and bank
under the new version is a separate, deduplicated intake, not a rewrite of
completed evidence. There is no retrospective whole-archive rescan.

`METAFLIP_COMPOSITION_MIXED_GROUPS=0` offers pair-only tickets. Disabling new
mixed intake altogether still uses `METAFLIP_COMPOSITION_MIXED=0`. Both
controls preserve and drain previously committed work. The existing shared
pending limit, backpressure, scheduling fairness, error handling and stop
semantics are unchanged. The pending limit is not a disk-byte quota.

## Why these groups

A bounded offline replay considered 289 distinct verified retained parents
at 27 scales: 7,803 distinct constructions. The larger offline family
(equal-factor groups plus elementary 2x2 grids) lowered 1,732 pair-only
prices. All cases finished within that model, but none beat the retained
local closure. Eight diagnostic products independently passed full Python
substitution/tensor checks, covering 19 distinct parent/leaf/output tensors.

Restricting to the existing native leaf bank, without grids, still lowers
876 prices; 687 of those attain the broader offline price. That justified
this small native extension without adding more tensor data. The largest
formula saving in this replay is eight terms.

The native implementation replays all 7,803 cases with the same prices as
the independent bounded Ruby solver, zero fallback components and at most
217 group probes in any case (255,441 total). Eight products on distinct
canonical target shapes also pass independent Python substitution and full
tensor checks. One reproduces 14x15x20/r2514, already retained. There are
**zero new local bounds and no world-record claim**; do not add these cases
to the historical candidate count. This was not a fresh public novelty audit.

The comparison pins the 5,984-shape closure with SHA-256
`0b4ad918bd36a262797cb89017513cbed0fe07dbdb832df4d5462c4e4e2c0da7`,
plus the already retained newer bounds 6x6x32/774, 7x9x18/768,
9x15x20/1646, 9x15x22/1856 and 9x17x20/1926. The parent identities are the
deduplicated union of the two [mixed-observer studies](BUD-MIXED-OBSERVERS-2026-09-09.md).
The inputs, reports, products and disposable drivers remain outside the repo:

- `/private/tmp/metaflip-observer-broad-packing-20260909/report.json`
- `/private/tmp/metaflip-observer-broad-packing-20260909/independent.json`
- `/private/tmp/metaflip-bank-group-screen-20260909.json`
- `/private/tmp/metaflip-native-group-corpus-20260909/report.json`

The corpus run includes independent checking and process startup; its
wall time is not a matched throughput benchmark.

A final bounded cleanup of the eight native wide outputs tried 45 distinct
shared-matrix refactorings followed by exact pair/matrix compression. All
eight final tensors were checked again; no rank decreased. This diagnostic
was offline and does not imply automatic recursive wide-output refinement.

## Focused regressions

```sh
bin/tungsten-compiler compile bits/tungsten-metaflip/spec/mixed_group_composition_test.w \
  --out /tmp/metaflip-groups --release --native --no-lto
bin/tungsten-compiler compile bits/tungsten-metaflip/spec/mixed_composition_test.w \
  --out /tmp/metaflip-pairs --release --native --no-lto
python3 bits/tungsten-metaflip/spec/mixed_group_composition_parity_test.py \
  /tmp/metaflip-groups /tmp/metaflip-pairs
bin/tungsten-compiler compile bits/tungsten-metaflip/spec/refinement_backpressure_test.w \
  --out /tmp/metaflip-group-queue --release --native --no-lto
python3 bits/tungsten-metaflip/spec/mixed_composition_queue_test.py \
  /tmp/metaflip-group-queue
```

The engine regression covers 259 plans against an independent subset oracle,
explicit pair-plan fallbacks, rank 512, high factor bits, deterministic replay,
malformed plans/buffers/costs, all 27 scale orientations and 45 complete tensor
reconstructions, including forced four-term substitutions on every axis.
It runs in both release/native and non-release/native builds.
The queue regression checks default-on groups, distinct
same-rank inputs, old/new version coexistence and gains, version forgery,
immutable leaf changes, three input/price failures, interrupted commits,
the exact shared 1,269-recipe test cap and deferred-only coordinator shutdown.
The public executable also passes bounded one-CPU/no-GPU 5x5 and rectangular
2x5x6 runs, restart and disabled-refinement checks. These are integration
checks, not a GPU utilization or throughput measurement.
