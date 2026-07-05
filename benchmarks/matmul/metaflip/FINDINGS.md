# GF(2) matmul flip-graph campaign — consolidated findings

This is the durable record of the flip-graph rank-search campaign for GF(2)
(mod-2) matrix-multiplication tensors, consolidated from many sessions
(2026-06-18 through present). It exists so a future session doesn't re-run
experiments already settled here. Where a finding was later corrected, only
the corrected version is kept — see "corrections" at the end for what changed
and why.

## Verified record table (GF(2), n,m,p ≤ 7)

| format | naive | best known | source |
|---|---|---|---|
| ⟨3,3,3⟩ | 27 | **23** | Laderman 1976 |
| ⟨4,4,4⟩ | 64 | **47** | AlphaTensor (DeepMind, Nature 2022 — deep RL, not flip-graph-discovered) |
| ⟨5,5,5⟩ | 125 | **93** | Moosbauer–Poole symmetric flip-graph (arXiv:2502.04514) |
| ⟨6,6,6⟩ | 216 | **153** | Moosbauer–Poole symmetric flip-graph |
| ⟨7,7,7⟩ | 343 | 249 → **248** | Kauers–Wood meta flip-graph (arXiv:2510.19787) pushed 249→248 via Perminov's ternary meta flip-graph (arXiv:2511.20317, GPU population search, N=16384, 24-72 GPU-hours/run) |

**Corrected note:** an earlier session mis-attributed "777=250" as a
Perminov/GF(2)-flip-graph result — it is actually Sedoglavic 2017
(arXiv:1712.07935), a general-ring algebraic construction unrelated to
flip-graph search and not GF(2)-specific. It sits 2 ranks above the real
frontier (249→248); an entire day's siege from a seed AT 250 (~1.5 trillion
moves, zero descents) only shows Sedoglavic's construction is a local optimum
for our move set — it says nothing about flip-graph reachability of 249/248.

Two published thresholds exist per rectangular size on the 8/9 frontier —
see the campaign memory for the ⟨8,8,9⟩/⟨8,9,9⟩/⟨9,9,9⟩ soft-target map if
resuming that hunt; not reproduced here since it's speculative/unverified
territory, not a settled finding.

## What's been tried, exhaustively, and does NOT break any record

This is the single most valuable section — every one of these was tested to
real scale (billions to trillions of moves) and produced a clean, repeatable
negative. Don't re-attempt any of these without a genuinely new idea:

- **Plain random-walk flip-graph** (flip + natural reduction + restart-to-best):
  reaches 23/47/93/153 reliably, does not go below.
- **Greedy reducing-move** (always take a guaranteed ≥2-factor reduction):
  actively **regresses** — traps in local minima faster than pure random walk
  (3×3→24/25 instead of 23, 4×4→53/64). Reducing moves must be *accidental*,
  not scheduled; even 1/20 greedy frequency measurably hurts.
  Do not add greedy reduction "for speed" — it breaks quality.
- **Higher-order bucket reduction** (Gaussian-elim refactor of any term group
  sharing a factor, not just the trivial zero/dup case): fully implemented,
  verified correct, **conclusively neutral** — same walls (95/161 in the
  pre-correction record numbering) hold even with the complete reduction
  repertoire in the loop.
- **Zero-sum motif injection** (splice a naive⊗Strassen 15-term zero-sum patch
  into a random 2×2 subblock, for non-local escape structure): neutral.
- **Structured plus-moves + edge-constraint hierarchy** (Arai 2024 policy,
  full implementation): matches records reliably from naive, does not beat
  them from a record-seed.
- **Symmetric-quotient search** (C₃ rotation symmetry `(i,j,k)→(j,k,i)`, no
  transpose): reaches the same records via a much smaller (exhaustible) state
  space; the symmetric rank-23 component for 3×3 was **fully exhausted** — no
  path to 22 exists via symmetric moves from that component.
- **3×3 → 22 definitive negative**: ~1.5 trillion moves, full move-set stack
  (free walk + structured plus + bucket reduction + motif injection), 22
  appeared zero times while 23 appeared 300k+ times. Consistent with the
  symmetric exhaustion above. This is why Laderman-23 has held since 1976.
- **All-size 60-minute fleet sweep**: ~3 trillion moves total across 3×3/4×4/5×5,
  every wall held exactly at the recorded rank.
- **777-siege from a rank-250 seed**: ~1.5 trillion moves, zero descents —
  see the correction above for why this doesn't actually test the real
  248-frontier.
- **Meta flip-graph (Kauers–Wood cross-format edges)**: built and validated
  (extension/projection edges, round-tripped tensor-valid across format
  changes) — but **does not target the square records**. (5,5,5)=93 and
  (6,6,6)=153 are the symmetric flip-graph's own results, used as the
  meta-flip's *seeds*, not its target. The meta-flip improves the
  **rectangular vicinity** around the squares ((4,5,6)=90, (5,5,7)=127,
  (5,6,7)=150) — hunting a square-record improvement with it is mis-aimed.
- **Naive 1-thread-per-walker CUDA port** (RunPod B200, faithful port of the
  Mac fleet's kernel): only **1.7×** the 18-core Mac fleet's throughput
  (184M moves/s vs 108M/s) — each GPU thread is ~6500× slower than a CPU
  thread. GPU-hostile: ~3.8KB mutable state per walker in local memory (low
  occupancy) plus branchy, divergent O(rank) scans every move. **Throughput
  was never the lever** for this class of workload — see the next section
  for what actually moved the needle instead.

**Overall conclusion as of 2026-07-03**: the walls are structural, not a
tuning or throughput problem. Every buildable lever on top of the *same*
move-family (flip + plus + reduction, in any combination or schedule) lands
on the same ranks. The one technique that ever changed the game was
**symmetry** (made 3×3 exhaustible) — cancellation patterns *are* symmetries,
which is presumably why human/RL-found algorithms (Strassen, Laderman,
AlphaTensor) look the way they do.

## GPU: what actually works

The naive CUDA-style port above is a dead end, but a **threadgroup-memory
redesign** on Metal is not:

- **`flipgraph_gpu_tg.w`** (device-mem baseline is `flipgraph_gpu.w`):
  caching each walker's scheme in on-chip threadgroup shared memory
  (`gpu.shared_i32`, coalesced layout `sus[term*32+ltid]`) instead of device
  memory took a 4096-walker × 120K-step dispatch from 93s → 24s → 8s
  (~11.6×). The two levers: gate the O(rank²) duplicate-check to every 8th
  step (93→24s; zero-check must stay every step — it's the main reduction
  mechanism), then move to threadgroup memory (24→8s; thread-*private*
  arrays were slower — too big, register spill + occupancy loss).
- Sidecar `.metal` emission gotcha: it emits alongside whatever
  `TUNGSTEN_LL_PATH` points at (not `--ll`, which returns before emitting);
  the host reads it back via `read_file`.

### Latest addition: `cal2zone` schedule ported to GPU

Built `flipgraph_gpu_cal2zone.w` — same threadgroup-memory kernel design,
but with the actual `cal2zone` band-escalation schedule (see below) ported
to per-GPU-thread state, replacing an earlier margin/leash heuristic and a
separately-tried best-of-N candidate-scoring variant. Findings from that
detour, kept here so they aren't re-discovered the hard way:

- **Best-of-N candidate scoring (O(rank²) per step) was a dead end on GPU.**
  Scanning every candidate and scoring by pressure (the Phase-0-validated
  CPU technique) works on CPU because a single thread doing extra work per
  step is cheap; on GPU it cuts the achievable step count by ~64× for the
  same wall-clock budget, starving the schedule of the raw step volume it
  needs to ever escalate past the first couple of bands. Reverted to plain
  first-found selection (O(rank) per step) — the GPU's actual edge over a
  CPU fleet is parallel *breadth* (thousands of independent attempts), not
  smarter per-step choices.
- **Duplicate-check optimization hypothesis was empirically wrong.** Tried
  replacing the periodic O(rank²) all-pairs duplicate scan with an O(rank)
  check of just the 1-2 slots touched that step (a duplicate can only newly
  appear at a just-modified slot — sound reasoning) done every step instead
  of periodically. Measured: removing duplicate-checking *entirely* gave
  the *same* round timing as the original design; the new "optimization"
  was if anything marginally slower. Duplicate-checking was never the
  bottleneck at these rank sizes (O(rank) per step for the candidate scan
  and the zero-check dominate). Kept the new version anyway — it's more
  *correct* (catches duplicates the same step instead of letting `rank` sit
  wrong for up to 64 steps), just not a speed win. Worth revisiting a real
  hash-table (O(1) amortized, matching what the CPU side already does via
  hash chains) only if this becomes the actual bottleneck at larger sizes —
  it needs more shared memory, which is already the tight constraint here.
- **Re-seeding cadence vs. schedule persistence.** The relay design re-seeds
  every GPU thread from the CPU fleet's current-best file every round. If
  the schedule's own state (current band, self-calibrated threshold, cycle
  counter) also resets on every re-seed, it never gets far enough to
  escalate past band 1-2 in a short round. Fixed by separating "refresh the
  working scheme" (every round) from "reset the schedule state" (only ever
  via the schedule's own internal trigger) — a `firstinit` flag distinct
  from `doinit`, with schedule state persisting in the device `st` buffer
  across dispatches.
- **A verification-gating bug produced a phantom "better than known-optimal"
  reading twice** (GPU log briefly showed rank 22 for 3×3, below the known
  23 optimum, and separately rank 46 for 4×4 below 47). Root cause: the
  displayed running-minimum (`globalbest`) was updated *before* the
  correctness check ran, not gated the same way the actual write/report
  path is. Confirmed harmless both times — nothing was ever written to the
  shared best-file or communicated to the CPU side, since `verify_buf`
  silently rejects the bad candidate (some GPU thread's rank counter
  occasionally reports a too-low value that doesn't correspond to an actual
  valid decomposition, at a low but nonzero rate — contained by
  verification every time observed, root cause not yet tracked down).
  Fixed the display gating; the underlying rare bad-counter case is worth
  root-causing if it recurs at a rate that matters.

## Performance engineering (CPU walker)

- **Bucketed hash-chain core** (`bucket_gen.py`): replaced every O(rank) or
  O(rank²) linear scan (partner-find, duplicate-check, pressure) with hash
  chains (three doubly-linked chains keyed by u-/v-/w-mask; free-list slot
  reuse; dense LIVE array for uniform random pick). This was the single
  biggest walker throughput lever: **3M → 47M moves/s** (~15×) at rank 250,
  further tuned to ~56M moves/s.
- Mixed raw-ABI calling convention (typed-array params + raw scalars) killed
  most remaining `w_int`/boxing churn at call boundaries.
- Explicit `-> f(...) (types...) ret_type` return-type declarations on
  generated functions avoid inferred-nil return types that would otherwise
  box every consuming operation.
- **OOM lesson**: compiled Tungsten binaries have no GC — `TUNGSTEN_FREE`
  only frees provably non-escaping values, so any per-move escaping
  allocation leaks linearly. A 17-walker fleet OOM'd a 128GB box in 26
  minutes this way (wide masks ≥2^47 boxed a heap bigint per flip, never
  freed). Before any long fleet run, measure one walker's RSS slope for 60s
  and make sure slope × walker-count × planned-hours stays well under RAM.

## The `cal2zone` CPU schedule

Erik's spec, implemented in `bucket_gen.py`'s `adaptive_esc="cal2zone"` mode:

- Every walker starts at **band 1**.
- **Work zone** (band ≤ `wthr`, starting at 7): escalate +1 band every 2B
  moves.
- **Wander zone** (band > `wthr`): escalate +12 bands every 500M moves.
- Past band 60: sawtooth back to band 1 (a "cycle"). Two full cycles with no
  descent → fresh RNG, and (if the run started from naive) a full reset of
  the working scheme back to naive.
- `wthr` self-calibrates **up-only**: any descent sets
  `wthr = max(wthr, descent_band + 1)`.
- Any descent resets that walker's band back to 1 immediately — successes
  reset to cheap/tight exploration; only being *stuck* earns a walker the
  right to wander into expensive high bands.

Run architecture: 18 CPU walkers (this schedule) + one GPU cal2zone kernel,
all re-seeding from a shared coordinator's current-best file each round
(`relay_coordinator.py`), sequenced 2 hours per format
(3×3×3 → 4×4×4 → 5×5×5 → 6×6×6) by `overnight_orchestrator.py`. Every
walker/GPU thread that matches or beats the known record for its size saves
its full decomposition to `benchmarks/matmul/metaflip/records/<format>/`
(never overwriting — multiple distinct record-rank decompositions accumulate
per format, since same-rank schemes can still differ structurally).

Early results this run: 3×3×3 confirmed 23 within a minute; 4×4×4 confirmed
47 within ~9 minutes; 5×5×5 in progress. GPU has not yet landed a genuine
verified win over the CPU fleet in this configuration (consistent with the
"throughput isn't the lever, and best-of-N isn't worth its per-step cost on
GPU" findings above) — it correctly rides along and re-attempts from
whatever the CPU fleet finds.

## Auxiliary datasets

- `sweep_shape/{r3,r5,r5best}.csv` + `slot{,5}.sh`: an earlier (2026-07-03)
  band-calibration sweep — bands 1-30 × 16 seeds each on 3×3 and 5×5,
  recording rank-found per (band, seed). Rescued from `~/.mmwork` (no
  previous durable home). Informed, but is not identical to, the later
  `cal2zone` band-zone design above.
- `matmul_5x5_rank93_gf2.txt`: a verified, independently-found rank-93
  decomposition of ⟨5,5,5⟩ over GF(2) (predates the record table correction
  above but the rank-93 finding itself was never in question).

## Corrections (superseded claims, kept for context)

- "⟨7,7,7⟩ = 250 is the GF(2) record" — **wrong**, see the record table note
  above (Sedoglavic 2017, not flip-graph, not GF(2)-specific).
- "5×5 record is 95" / "94 is the barrier" — an earlier session's
  literature check found 95/94 based on an incomplete record lookup; the
  verified, corrected record is 93 (Moosbauer-Poole), reflected in the table
  above. Anything referencing "95" or "94" for 5×5 elsewhere in old session
  logs is from before this correction.
