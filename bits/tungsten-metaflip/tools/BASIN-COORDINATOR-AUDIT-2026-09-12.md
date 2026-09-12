# Coordinator gas and bounded bridge-split screen — 2026-09-12

Retain the exact-preserving coordinator optimization. Do not promote the
experimental donor split or claim a new rank record. The user's live 7x7
CPU/GPU campaign was neither stopped nor restarted.

## Profile and retained changes

Baseline source: `35c28e54`. A three-second macOS `sample` of PID 94260 put
most coordinator samples in `ffbi_identity_view` and its factor transforms;
two sampled CPU workers were parked in their input channel about 85% of the
time. This is a sampled interval, not a campaign-wide utilization average.

`tungsten flame --pid 94260 -d 3 --counters rates` currently returns a TODO,
not a profile. Instead, attach Instruments for one second using Flame's
`flame-counters-cache.tracetemplate`, export **counters-profile** (not the raw
kdebug counter table), and replay through `tools/analyze_profile.w` and the
Flame sidemap/counter parser. All eight folded metrics had nonzero output.

Of 3,516,925,248 attributed branches, 1,232,084,292 were in factor transforms
and 633,809,633 in identity calculation: together 53.1%. Their branch-miss
rates were about 2.13% and 2.17%. Partner lookup had 5,200,109 attributed L1D
load misses and 5.93% branch misses; pair-pressure checking had 2,435,294 and
9.21%. These are baseline sampled counter attributions, not a proof of stall
cycles. The template's `LLC-load-misses` alias is actually
`MMU_TABLE_WALK_DATA`; do not interpret it as measured LLC misses. This
counter set does not provide IPC.

Retained implementation:

- Replace per-bit transpose/reversal loops in basin canonicalization with
  byte packing and fixed bit permutations. Preserve all twelve D3/reversal
  images, the GL histogram, and the exact same 62-bit digest formula.
- Compute each island identity once per telemetry snapshot, plus the leader
  once. For 16 islands, status identity evaluations fall from 168 to 17;
  rendering falls from 216 to 17, including its per-island rows.
- Reuse campaign-owned storage for snapshot IDs and leader distances. Never
  reuse IDs across state mutations; no hash-only freshness check or growing
  per-frame allocation. TUI fields and the archive/density policies remain
  unchanged. The digest remains a heuristic, not a tensor equality proof.

## Measurements

Native release/native/no-LTO microbenchmark, identical frozen 16-island
corpus, alternating old and new code in one binary, 40 snapshots per sample:

| Shape | Reference ms (three runs) | Optimized ms (three runs) |
|---|---:|---:|
| 5x5 | 802 / 982 / 1156 | 25 / 59 / 28 |
| 7x7 | 4184 / 3443 / 3412 | 137 / 101 / 125 |

All checksums match. An earlier 7x7 pass, before the overlapping fleet
measurements, was 2843/2811/2753 ms versus 93/80/79 ms. Thus approximately
30x faster snapshots, not 30x faster flipping. The host was not exclusive;
retain the raw spread rather than treating this as thermal qualification.

Integrated A/B/B/A: ordinary 7x7, 16 CPU workers, eight seconds each,
nonce 19071, separate empty state directories, GPU and background refinement
disabled in these test runs. The user's CPU/GPU run remained active.

| Run | Moves | Coordinator ms | Status ms |
|---|---:|---:|---:|
| baseline A | 2,689,340,109 | 1260 | 957 |
| optimized B | 3,241,606,025 | 192 | 62 |
| optimized B | 3,222,029,031 | 193 | 66 |
| baseline A | 2,880,032,057 | 1262 | 957 |

Mean throughput: 348.1M -> 404.0M attempts/s (+16.1%). All four runs finished
cleanly and their saved complete GF(2) tensors passed the independent Ruby
verifier. This does not establish the same gain with GPU/refinement enabled,
on a quiet host, or in the distinct packed 8..16 backend.

## Approach experiment: donor-factor splits

Disposable packed-walker prototype: replace the split-off coordinate bit
with a different factor from an existing term on the same axis (up to eight
draws, then the original fallback). The XOR complement preserves the tensor
and creates an external shared-factor connection. Both arms use the current
density-neutral nonbacktracking walker, the same rank band and split cadence.
No new density objective or greedy reducing-move selection was introduced.

32 one-second runs, 8/12/15/16 squares, two RNG seeds, A/B/B/A per shape/seed:
89,604,096 attempts, 293 snapshots and 32 best endpoints. Every snapshot and
best endpoint passed independent full-tensor expansion. Canonical full bytes,
not cache hashes, were used for sampled-state deduplication.

| Shape | Current best rank in both arms | Globally distinct sampled states, old / donor |
|---|---:|---:|
| 8x8 | 329 | 36/36 / 37/37 |
| 12x12 | 1068 | 38/38 / 37/37 |
| 15x15 | 2058 | 36/36 / 37/37 |
| 16x16 | 2209 | 20/36 / 23/36 |

No rank improvement. These are bundled/composed starts, not the user's
stronger historical checkpoints (in particular, not the 15x15 rank-2008
checkpoint). Donor splitting reduced the 16x16 bounded-cache repeat fraction
from 43.6% to 34.9%, but the exact sampled-state gain was small and acceptance
throughput only rose about 2.6%. That is insufficient to change the default
or add another runtime policy. Prototype and raw evidence stay outside Git.

The more consequential next search-pipeline problem is refinement latency:
the live snapshot had 622 refinement jobs pending, with composition capacity
blocking new refinement work. `ffrf_job` reserves composition capacity before
matrix cleanup. A future change should separate verified same-shape cleanup
feedback from deferred projection/composition expansion, while retaining
durable tickets, bounded storage and distinct completion cursors. Do not
remove backpressure or mark unfinished expansion complete to inflate output.

## Focused checks and evidence

- `basin_identity_test.w`: 96,346 bit-permutation comparisons; all 2..7
  frontier seeds/current states against a frozen pre-change identity oracle;
  all twelve symmetry images with reversed term order; 0..16-island snapshot
  parity, in-place mutation, leader/rank changes and empty reuse.
- `archive_admission_test.w`: 16,041 exhaustive-equivalent comparisons plus
  8,869 cache-property comparisons.
- `fleet_phase_timing_env_test.rb`, `fleet_async_scheduler_test.rb`: scheduler
  overrides, timing accounting, interrupt/reset, clean draining and exact
  checkpoints.
- Real 3x3/8x8/16x16 PTY TUI tests, including resize and q.
- Package build, runtime manifest verification, test manifest and layout.

Reproduce the microbenchmark from the package root:

```sh
tungsten compile spec/basin_identity_bench.w --release --native --no-lto --out /tmp/basin-bench
/tmp/basin-bench 7 40
```

Local raw evidence (not committed):
`/tmp/metaflip-coordinator-abba-20260912/`,
`/tmp/metaflip-basin-{5,7}-20260912.log`,
`/tmp/metaflip-basin-tui-20260912/`,
`/tmp/metaflip-bridge-ablation-20260912/`, and the
`/tmp/metaflip-gas-live-7x7-*20260912` profile files. Instruments traces include
process environment metadata and must not be published unsanitized.

SHA256 provenance:

```text
baseline binary fdf59bdae31cdbda1b0de3eeb64ff6a4aee0090d98bfb20381d5e8d3426340fc
optimized binary 616921235db8ad1de031f79af80627e5faa9310a9e91683ec90d9ae004ea04b9
fleet results.json a4fe633dccf4dcdbfd0cdc704efb2fe4f7831a723044a7475229082ca456d3eb
bridge results.jsonl 95cd69fb255cb66b981ad31fe285629af5c59c011e0f4f973b31c6d4f9071327
bridge prototype 8090e008a0033f24062f7be685bcf700e8377c53d60099bc6c6bb2eb19ca29a3
```
