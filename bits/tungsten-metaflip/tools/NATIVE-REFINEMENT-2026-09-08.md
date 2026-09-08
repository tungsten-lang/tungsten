# Native background refinement integration — 2026-09-08

This is an implementation/replay milestone, not a new rank record. Ordinary
square and rectangular `bin/metaflip` runs now process distinct verified
candidate representations with a native background worker. Rank ties and
nonleaders enter the same durable intake as strict rank improvements.

## Implemented boundary

Immediate pair/matrix cleanup remains in the existing exact admission gate.
Cold jobs run in one `nice -n 10` native child, at most two inputs per launch.
Each job tries six one-axis bases and all single-coordinate projections of
the cleaned source and the selected grouping endpoint. Every output crosses
the complete tensor gate. Ordered shape plus sorted full term multiset is the
identity; hashes locate objects but never substitute for the algebraic check.

Inputs, output manifests and a consumed cursor persist beside the run status.
Deferred tickets are not marked completed during shutdown. Indexed cross-shape
artifacts survive even when no active island can use them. Same-shape proposals
feed bounded seed/archive admission without sharing a mutable worker buffer.
Result collection continues while a seed waits for an island. Fresh naive/reset
generations cannot import proposals from an earlier frontier.

The worker is not a recursive composition engine. Incremental recipe repricing,
cross-shape campaign dispatch and large multiword compositions remain offline.
There is no fixed disk-byte quota; a long campaign can accumulate artifacts.

## Focused verification

- Native queue test admits two distinct rank-7 2x2 decompositions and a rank-9
  nonleader, rejects a full-term duplicate, and verifies same-shape feedback.
  It tests immutable snapshots, persisted cursors and tail-index recovery.
- Independent Python replay compares complete output sets, canonical bytes and
  full tensor coefficients. Four inputs, including the external 4x8x4/r94
  control, yield 31 exact outputs. The control includes the known 4x7x4/r85
  projection. The imported parent is not redistributed here.
- Stop/replay is idempotent. Hash corruption, false tensor identities, malformed
  canonical encodings, overflow and unsorted terms cannot commit a result.
- The public-binary integration test covers 5x5 seed feedback, 2x5x6 processing
  and restart, disabled refinement, full verification of every stored tensor,
  and absence of surviving owned refinement processes after shutdown.
- Existing asynchronous interrupt/raw-TUI reset checks pass, including final
  CPU intake and independent verification of the persisted best.
- Public release/native build succeeds. All 310 packaged runtime hashes and
  161 source-manifest entries match the exact tracked-source inventory;
  ignored generated GPU sidecars are excluded.

Focused replay commands (from the repository root):

```sh
bin/tungsten-compiler compile bits/tungsten-metaflip/spec/refinement_worker_test.w \
  --out /tmp/metaflip-refinement-test --release --native --no-lto
python3 -B bits/tungsten-metaflip/spec/refinement_worker_parity_test.py \
  /tmp/metaflip-refinement-test
python3 -B bits/tungsten-metaflip/spec/refinement_fleet_test.py \
  bits/tungsten-metaflip/bin/metaflip
ruby bits/tungsten-metaflip/spec/fleet_async_scheduler_test.rb \
  bits/tungsten-metaflip/bin/metaflip bits/tungsten-metaflip/lib/metaflip
```

The parity runner accepts an optional external 4x8x4/r94 file as its second
argument. Independent oracles are test dependencies, not runtime dependencies.

## Bounded resource canary

Binary SHA-256:
`a163a1a94639218db9e014d3eae7612851481a4bfb08155630d11689a99fc7d9`.

Two sequential isolated CPU-only runs used 5x5, two islands, 500,000-step
epochs, a 15-second limit, `nice -n 10`, and refinement off/on. Native CPU/GPU
code was otherwise unchanged; the GPU was disabled to isolate this path.

| Refinement | Reported attempts | Jobs completed | Seed uses | Last sampled main RSS |
| --- | ---: | ---: | ---: | ---: |
| Off | 1,457,314,974 | 0 | 0 | 22,832 KiB |
| On | 1,458,692,747 | 15/15 | 8 | 28,928 KiB |

The enabled spool contained 795 small files totaling 649,521 logical bytes.
There were no refinement failures, and both runs stopped their children.
Direct integer parsing and empty-queue polling guards avoided the earlier
split-string allocation growth. Sampling was every roughly 0.54 seconds, so
these are sampled RSS values, not an upper bound on short-lived child peaks.

This single canary does not establish a speedup, long-run memory plateau or
record-finding advantage. Seed feedback changes the actual walk. Longer
matched-budget efficacy tests and storage compaction remain follow-up work.
