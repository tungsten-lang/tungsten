# MetaFlip independent CPU epochs and allocation follow-up

## Outcome

The normal executable has been rebuilt with the Bitfile's release/native
defaults. Keep Core ML off and synchronous CPU scheduling on by default.
Independent completion is available with `METAFLIP_CPU_SCHEDULER=async`, but
higher CPU occupancy did not consistently improve search throughput.

Changes:

- A bounded two-buffer CPU pool supports independent completion. Workers own
  their live state; the coordinator sees complete, stable snapshots. A lane
  resumes only after its own intake and lease renewal. Rank drops, TUI resets,
  and shutdown drain outstanding endpoints before changing generations.
- Frontier admission caches pair distances, validating every ordered factor
  word, rank, and dimension. Exact tensor gates and admission tie-breaking are
  unchanged. In-place mutation invalidates the corresponding cache rows.
- The GPU Pareto bank copies only admitted candidates and recycles storage.
- Exact parity masks use a typed `i64` one instead of boxed Integer shifts.
  Checkpoint serialization uses `StringBuffer`, not growing-prefix copies.

These improve the engine, not the known tensor ranks. No new rank record was
found in the 5x5 performance runs. All final witnesses independently verify as
rank 93, density 967, with SHA256
`c80233c763939feac7940d60e343c0cba1c88a5d55b6d635b6ff379b9193149f`.

## Measurements

Apple M5 Max, 18 logical CPUs, 128 GiB, macOS 26.6.2. Each run used isolated
state, 5x5 GF(2), 16 CPU workers, the adaptive Metal portfolio, a 250 ms CPU
target, no TUI, and no Core ML. These are desktop workload measurements, not
general speedup guarantees. OS CPU is main-process CPU time divided by wall
time; GPU utilization is system-wide. Coordinator time overlaps CPU work in
async mode and is not equivalent to worker idle time.

The four 75-second same-binary runs (sync/async/async/sync, excluding the first
15 seconds) isolated scheduling after the archive and Pareto changes:

| Mode | Mean CPU moves/s | Main busy cores | Coordinator wall fraction | RSS growth MiB/min |
|---|---:|---:|---:|---:|
| Sync | 781.9M | 13.52 | 7.61% | 464.6 |
| Async | 724.5M | 14.01 | 18.18% | 577.3 |

A separate compiler process was observed during one async replicate; other
desktop activity was not globally suspended. Do not interpret the exact
percentage difference as a controlled hardware limit. It was sufficient to
reject an automatic async-default promotion.

The allocation trace identified `ffw_support_tensor_error_scratch` calling
`bignum_shl_generic` and `ffn_dump_trusted` retaining string prefixes. After
fixing both, two 90-second runs (first 20 seconds excluded) produced:

| Mode | CPU moves/s | Main busy cores | Peak main RSS MiB | RSS growth MiB/min | Mean system GPU |
|---|---:|---:|---:|---:|---:|
| Sync | 857.5M | 13.81 | 99.5 | 37.7 | 93.3% |
| Async | 857.6M | 14.70 | 133.6 | 58.1 | 89.0% |

This is roughly 90% less memory growth than the preceding runs. Memory is
still growing; it is not a bounded-process-memory proof or an indefinite-run
qualification. Sync achieved essentially the same throughput with less CPU
and memory overhead, so it remains the default.

The real 7x7, 16-entry archive microfixture retained the same admission action:
one uncached bounded decision took 165.8 ms; a warm cached decision averaged
0.762 ms over 20 repetitions (about 217x for this repeated decision only).
The initial cache fill computed 120 pairs; unchanged accesses computed none.

An earlier four-run preserved-baseline comparison averaged 608.0M versus
833.4M moves/s for the combined scheduler/cache changes. That comparison did
not isolate scheduling and exposed worse RSS growth. The subsequent
same-binary comparison and allocation fixes above supersede it for choosing
defaults. A separate battery/clamshell-sleep sweep was discarded entirely.

## Verification and provenance

- Native pool tests: slow-lane independence; complete bitwise continuation;
  private quotas, fringe/tuned/cycle-watch controls; reset and final drain.
- Archive: 16,041 exhaustive-policy and 8,869 cached property comparisons,
  including mutations, reordered slots, cache fallback, and equal minima.
- Pareto: 480 reference-policy comparisons, capacity high-water bound,
  reusable-intake isolation, rank drops and resets.
- Exact verifier: scratch reuse after corruption and explicit bit-63 syndrome.
- Serialization: byte-identical current/best checkpoints and exact tensors
  for 2x2 through 7x7, before and after walking.
- Native CLI: scheduler/cadence defaults and errors; Ctrl-C and TUI reset/q;
  final intake, persistence, and independent GF(2) reconstruction.
- 305 packaged runtime checksums pass. The source checkout's layout test sees
  two pre-existing ignored `cal2zone_555.metal`/`.cu` files dated September 5.
  They were left untouched. The layout test passes in a clean source package
  staged without those generated artifacts and with its Bitfile/CLI source.
- The rebuilt canonical executable completed a bounded CPU+GPU smoke with
  `gpu_degraded=0`, all 16 distinct CPU term sets, and an exact final witness.

No full rake suite was run. No records, curated seeds, user checkpoints,
unrelated compiler/GPU changes, or logo work were modified by this follow-up.
The measurements below describe the tested source snapshots; binary hashes
remain the authority for reproducing those particular runs.

Isolated worktree base: `83f3737616c86a39b578e224cd80947641438fc3`.
Canonical source HEAD at rebuild: `5c2408440dc02337bf13de0b983473b9eea13d53`.
Unrelated runtime/compiler differences between those bases are not overwritten.

Binary SHA256:

- Same-binary scheduler sweep: `01df2949a20409eaf0b0bf5c3cec957062f08be20ef9cde099ed6ceaa99c2f60`.
- Final isolated memory-fixed sweep: `55c24f397f327bbbe389430a05b8b671e3fa6d81337f19ecd477b487ab054049`.
- Canonical `tungsten build` executable: `7896da37e6e17c28f197dec0e42cb755951ca0af4bd05807eda534b0564c33b4`.

Evidence directory: `/private/tmp/metaflip-scheduler-20260906/`.
`final-ac/`, `memory-fixed-ac/`, and `matched-ac/` retain full commands, binary
hashes, samples, phases, final checkpoints and cleanup results.
`memory-profile/` contains malloc-history stacks and heap summaries.
`canonical-counters/` contains the final native GPU smoke. Its attempted new
Instruments recording was incomplete after an app restart (missing template
on export), so it is **not** new counter evidence. Earlier valid Flame
counter traces remain documented in `PROFILE-2026-09-06.md`.

Replay a matched scheduler sweep with the current binary's actual hash:

```sh
ruby tools/bench_cpu_epochs.rb \
  --binary "$PWD/bin/metaflip" --expected-sha ACTUAL_SHA256 \
  --runtime-root "$PWD/lib/metaflip" --output /tmp/metaflip-fresh-sweep \
  --seconds 90 --warmup 20 --targets 250 \
  --schedulers sync,async,async,sync
```

Use a fresh output directory. The harness rejects sleep-sized sampling gaps,
power-source changes, unhealthy GPU completion, failed exact checks and live
owned descendants. It does not suppress unrelated desktop workloads.

## Rectangular search follow-up

The rebuilt executable completed a six-shape, 16-worker/GPU tranche with a
300-second launch budget and a final exact drain at 326 seconds. It reported
57,818,697,871 moves: 17,186,377,871 CPU and 40,632,320,000 GPU. Parent health
was `ok`; GPU, CPU and MITM failures were all zero. No rank or density gain
was found. The saved leaders were:

| Shape | Rank | Density |
|---|---:|---:|
| 2x2x5 | 18 | 84 |
| 2x5x6 | 47 | 438 |
| 3x4x6 | 54 | 488 |
| 4x5x6 | 90 | 906 |
| 4x5x7 | 104 | 1089 |
| 4x6x7 | 123 | 1406 |

All six leaders and 48 side-archive witnesses passed independent GF(2)
reconstruction using `tools/verify_tensor.rb`. This checker expands each
factor's supports, XORs W into every U/V coefficient pair, and compares the
entire rectangular tensor. It does not call the native verifier. Focused
tests include asymmetric axes, the high bit of a 64-bit word, XOR cancellation,
out-of-bounds factors, corruptions and wrong shapes (43 assertions).
Exactness is not a novelty or world-record certificate.

Evidence: `/private/tmp/metaflip-record-search-20260906/portfolio.status` and
`verification.json`. All search state is isolated from user checkpoints and
the curated corpus. Replay individual checkpoints with:

```sh
ruby tools/verify_tensor.rb --shape 4x5x7 /path/to/best.txt
```

For paths beneath `checkpoints/gf2/NxMxP/`, the shape may be inferred from that
directory. Every result includes a SHA256 of the exact bytes verified.

### Rectangular fill scheduling

The coordinator previously restarted completed CPU-only children for one
additional round at a time, and could leave them idle until a slow GPU child
published its first progress. It now batches fills to at most the base quota
and roughly one predicted second, with a single-round fallback for slower
rounds that fit. A still-live GPU child with no first-round report permits a
bounded provisional fill window. The campaign's time limit clamps new
launches; active endpoints still drain. Per-segment accounting uses the actual
launched quota and any partial completion, not an assumed one-round fill.

`METAFLIP_RECT_FILL=single|batch` permits replaying the comparison. Batch is
the new rectangular default; the square fleet still defaults to synchronous
CPU scheduling. This does not change the flip operation or tensor verifier.

Four same-binary 90-second runs, in single/batch/batch/single order, used the
same five shapes (256, 346, 456, 457, 467), copied starting archives, 16 CPU
workers, 8,192 GPU walkers, 40,000 GPU steps and 32 base rounds. After excluding
the first 20 seconds:

| Fill mode | Mean CPU moves/s | Mean GPU moves/s | Combined moves/s |
|---|---:|---:|---:|
| Single | 57.68M | 84.30M | 141.98M |
| Batch | 92.49M | 84.36M | 176.86M |

That is 60.35% more CPU work and 24.56% more combined work in this workload;
GPU throughput was essentially unchanged. Individual CPU results were
56.25M, 94.90M, 90.08M, 59.11M. All four runs had healthy terminal status,
clean process shutdown, AC power unchanged and sampling gaps below 1.11s.
All 54 saved files per run verified independently; no rank/density gain was
found. These timing repeats revisit some deterministic trajectories and must
not be presented as an equal number of unique search moves or new schemes.

The initial measurement attempt was rejected for two sampling gaps above
5s. The rerun removed synchronous `ioreg` utilization queries from the timing
path. Its GPU measurements above are actual completed-work counters, not
utilization percentages. System utilization polling is optional in the new
`tools/bench_rect_fills.rb` harness. Total child CPU time includes sampler
helpers and startup/drain; it is not steady-state core occupancy.

Evidence: `/private/tmp/metaflip-scheduler-20260906/rect-fill-abba-2/`.
Measured binary SHA256:
`6ea39fb9b8889144cef7bb355e95581927965a36cfb8dd3193b41435fc97925d`.
Focused checks passed: fill quota boundaries, partial-segment accounting,
process isolation, exact two-epoch parent counters, policy defaults/overrides
and invalid policy rejection. No full rake was run.

The batching-only canonical `tungsten build` executable had SHA256
`929bc94a65aec34c5c673f60044df2baf985a525b0beaeb95fd2757b56503420`.
Its native rectangular CLI checks and all 305 runtime checksums passed. It ran
a no-time-limit seven-shape campaign (adding 2x2x9) from verified
archives in `/private/tmp/metaflip-record-search-20260906-batched/`; command,
binary hash and starting-state provenance are retained there. No submission,
publication or commit was made.

That tranche was interrupted at 860 seconds for the next matched comparison.
All 63 saved witnesses verified independently; leader ranks/densities were
unchanged. Terminal counters retained 344,496,251,362 moves, but the last live
status had reported 353,931,204,634. This exposed a cancellation-accounting
bug, not a failed tensor: cancelled threads were marked joined before their
last status was harvested. Do not use that interrupted tranche as a clean
throughput measurement. The fix below harvests the last published counters
once and forces an exact audit of cancelled children's durable checkpoints.

### CPU work during GPU epochs

The GPU-owning rectangular child formerly completed one CPU batch and waited
for its GPU epoch. Its calibrated CPU quota could reach the existing hard cap
while leaving most of its CPU lanes idle. The new overlap policy continues
the same CPU islands in short follow-up batches until the GPU completes.
Each batch fully collects before quotas change; GPU and block-interior jobs
use separate round-start snapshots. An observed CPU rank drop stops further
batches and proceeds to intake. Interrupt/time-limit checks occur between
batches. The nominal target is at most 200 ms, not a real-time guarantee;
there are at most 128 follow-ups per GPU epoch, and no follow-up exceeds the
measured first-batch quota. Extra moves are explicitly included in telemetry.

Four same-binary 90-second runs used barrier/overlap/overlap/barrier order,
the same seed archives and five-shape configuration as the fill comparison,
and a 20-second warmup exclusion. GPU ownership remained on 4x5x7 within these
short runs; this is not an all-shapes GPU sweep.

| CPU/GPU policy | Mean CPU moves/s | Mean GPU moves/s | Combined moves/s |
|---|---:|---:|---:|
| Barrier | 98.77M | 86.19M | 184.95M |
| Overlap | 254.82M | 83.86M | 338.68M |

This is +158.01% CPU work and +83.12% combined work. The completed-GPU-work
rate was 2.70% lower in these short windows. Individual CPU rates were
107.39M, 260.69M, 248.95M and 90.14M. The GPU-owning child performed
15.61–16.46B CPU moves with overlap versus 1.12B with the barrier. Process
child CPU time, including sampler/startup/drain, rose from about 497 to
801 seconds per run; it is not a steady-state per-core utilization metric.

All four runs ended healthy without forced termination or surviving children,
on unchanged AC power, with sampling gaps below 1.12s. All 54 saved files per
run independently verified (216 file checks, not 216 novel schemes). The
93,260,376,080 aggregate moves revisit deterministic trajectories in repeats.
No rank or density improvement was found. No new hardware-counter/Metal trace
is claimed for this comparison; GPU rates are completed-work counters.

`METAFLIP_RECT_CPU_GPU=overlap` is now the rectangular default; `barrier`
remains available for comparison. CPU-only quotas and the square scheduler
are unchanged. Native checks passed for all modes, invalid values, real GPU
execution, exact final witnesses and Ctrl-C cleanup with CPU-only and GPU
portfolios. A full-state continuation test compared every worker word against
serial execution over nine variable-quota batches, on 2x3x4, 2x2x9 and 4x6x7,
including ordinary and cold split cadences. The test applies exact verification
to both copies because verification itself increments diagnostic counters.

The new interrupt regression reproduced `245000000 -> 0` on the pre-fix
binary. It passes on the rebuilt binary with monotone CPU/GPU/MITM totals,
matching shape sums, exact saved witnesses and no surviving owned children.
Terminal child publication is also excluded from completed-round estimates;
it increments status sequence but does not perform another search round.

Evidence: `/private/tmp/metaflip-scheduler-20260906/rect-overlap-abba/`.
Measured binary SHA256:
`51881171aaa86de8a1621f27b38d3c3b450a727047c0dfbf743b2c6523bfe74c`.
Rebuilt normal `bin/metaflip`, including the default and cancellation fix:
`fc7f9cc91bddfd67f06642bf3fa8025e968e7b2b43870a539adb65d54e16676a`.
All 305 runtime hashes pass; only focused checks were run. These source
snapshots leave unrelated compiler/GPU/logo changes untouched.

The seven-shape search was restarted from all 63 verified saved witnesses in
`/private/tmp/metaflip-record-search-20260906-overlap/`, with `-J 16`, GPU
enabled and `--secs 0`. Its `command.json` records the exact binary, arguments,
environment and starting-witness hashes. These are scheme checkpoints, not
serialized RNG continuations; restarted trajectories can revisit earlier work.

## GPU recovery after a host-sleep interval

The continuing seven-shape run recorded one GPU failure across a low-power
hibernation interval. The failure alone does not establish a hardware fault.
The 2x5x6 exposure counter reached roughly 93.6 million, versus roughly
1--4 million for peers, because GPU wall time includes the host sleep. The
ordinary score comparison then kept that degraded lane from getting the GPU
epoch required to clear its recovery gate, even after backoff expired.

`ffrpo_gpu_allocate_recovering` now prioritizes an eligible recovery probe
before ordinary adaptive scoring. Multiple eligible probes rotate independently
of their scores. Existing readiness, retry backoff, CPU-host requirements,
8192-walker occupancy floors and total lane budgets still apply. Only a clean
GPU epoch clears degradation; a CPU-only epoch does not. This change prevents
recovery starvation; it does not make sleep-contaminated exposure or elapsed
wall time into valid performance measurements.

The focused native allocation regression covers the observed exposure/penalty
state, unequal-score recovery rotation, backoff, host gates, single/adaptive
occupancy and returning to normal scoring after recovery. The separate
release/native binary `/private/tmp/metaflip-gpu-recovery-20260906` also passed
real GPU default/barrier/overlap execution and CPU-only/CPU+GPU interrupt
cleanup. All 305 runtime checksums passed.

After those checks, the old portfolio was cleanly stopped at 3,338,408,030,806
completed moves; its logs and degraded terminal status remain intact.
All 63 saved witnesses were independently verified and copied byte-for-byte
to `/private/tmp/metaflip-record-search-20260906-gpu-recovery/`.
The normal `tungsten build` release/native executable has SHA256
`389e2b30d04ccc8bc0f494918d986e4a85af1a72a32cd02ade96851e7ed6b115`.
It restarted the same seven shapes with 16 CPU lanes, 8192 GPU walkers and
`--secs 0`. `command.json` records the binary, runtime-manifest hash, old
terminal totals and every starting-witness hash. This resumes exact schemes,
not RNG trajectories or sleep-contaminated exposure statistics. No historical
failure was erased from the old evidence.
The rebuilt normal binary separately passed all three real-GPU
default/barrier/overlap checks, and its restarted portfolio reports healthy
state with both CPU and GPU completed-work counters advancing.
