# Rectangular GF(2) campaigns

FlipFleet has twenty-five canonical rectangular profiles.  They all use the same
runtime-generic pure-Tungsten CPU worker and exhaustive reconstruction gate;
the eleven GPU-enabled profiles additionally have checked-in, dimension-
specialized Tungsten/Metal relays with independent `nm`, `mp`, and `np` masks.

| tensor | exact seed | strict target | CPU | Metal | immediate use |
|---|---:|---:|---:|---:|---|
| `2x2x5` | 18 (d84) | **17** | yes | **yes** | one certified constructive gap; five CPU doors plus specialized cal2zone and exact 5→4 MITM Metal lanes |
| `2x2x6` | 21 (d108) | **20** | yes | no | adjacent primitive campaign with two zero-overlap exact three-Strassen CPU doors |
| `2x3x4` | 20 | **proven optimal** | yes | **yes** | exact GF(2) rank 20; rank-drop lanes are retired, while exact density/basin walking remains available |
| `2x3x5` | 25 (d160) | **24** | yes | **yes** | checked `23 <= R_GF(2) <= 25` interval; four exact CPU doors plus specialized cal2zone and exact 5→4 MITM Metal lanes |
| `2x4x5` | 33 | **32** | yes | **yes** | smallest live field-gap campaign: characteristic-zero rank 32 is explicitly not valid over GF(2) |
| `2x5x6` | 47 (d438) | **46** | yes | **yes** | leading small-cross primitive: one saved rank improves 10 saved and 49 strict-audited formulas; specialized cal2zone and exact 5→4 MITM lanes |
| `3x3x4` | 29 | 28 | yes | yes | each rank saved removes three terms from the 7x7 composition |
| `3x3x5` | 36 | 35 | yes | yes | rank-47 outer block-composition leaf |
| `3x4x4` | 38 | 37 | yes | yes | each rank saved removes three terms from the 7x7 composition |
| `3x4x5` | 47 | 46 | yes | yes | high-leverage leaf in 15x16x17 and related records |
| `3x4x6` | 54 | **53** | yes | no | 1,417 uses across 122 strict audited formulas |
| `3x4x7` | 64 | **63** | yes | no | 1,342 uses across 114 strict audited formulas; known rank-63 schemes exclude GF(2) |
| `3x5x5` | 58 | 57 | yes | yes | rank-47 outer block-composition leaf |
| `3x5x6` | 68 | **67** | yes | no | 1,277 uses across 122 strict audited formulas; four shadow rows cross |
| `3x5x7` | 79 | **78** | yes | no | 1,223 uses across 128 strict audited formulas; three shadow rows cross |
| `4x4x5` | 60 | **59** | yes | **yes** | high-multiplicity leaf in the new block compositions |
| `4x5x5` | 76 | 75 | yes | no | allocation/product leaf scout |
| `4x4x6` | 73 | **72** | yes | no | 1,106 uses across 108 strict audited formulas; eight shadow rows cross |
| `4x5x6` | 90 | **89** | yes | no | 1,683 uses across 169 strict audited formulas |
| `4x5x7` | 104 | **103** | yes | no | highest aggregate sensitivity across the 760 audited formulas |
| `4x5x8` | 118 | **117** | yes | no | 1,325 uses across 110 strict audited formulas; two shadow rows cross |
| `4x6x6` | 105 | **104** | yes | no | 1,176 uses across 116 strict audited formulas; four shadow rows cross |
| `4x6x7` | 123 | **122** | yes | no | 2,002 uses across 185 strict audited formulas; seven shadow rows cross |
| `4x6x8` | 140 | **139** | yes | no | 1,202 uses across 106 strict audited formulas; five shadow rows cross |
| `5x6x7` | 150 | **149** | yes | no | 1,579 uses across 111 strict audited formulas; four shadow rows cross |

The allowlist is intentional.  The worker arithmetic is generic for factor
widths below 63 bits, but a shape is not advertised until it has a checked-in
exact frontier and an honest target.  Likewise, a CPU profile does not claim
GPU support until its specialized Metal source and legal shared-memory
geometry are checked in.

## Adaptive multi-shape portfolio

`--rect` treats `-J` as one total CPU budget and searches several independent
rectangular shapes concurrently. The default portfolio starts with the
certified one-term `2x2x5` gap, then `4x5x7`, `3x4x6`, `4x5x6`, `4x4x6`,
`4x4x5`, `2x5x6`, `3x4x7`, and `3x5x6`; override it with a
duplicate-free list:

```sh
/tmp/flipfleet --rect --secs 86400
/tmp/flipfleet --rect \
  --rect-shapes 4x5x7,4x6x7,4x5x6,5x6x7,3x4x7,3x5x6,4x4x5 \
  -J 188 --rect-epoch-rounds 16 --secs 86400
```

Every ready shape receives a starvation floor when the host has enough
workers. Remaining workers use deterministic adaptive allocation from
downstream composition leverage, rank and density yield per exposure,
underexposure, GPU coverage, and failures. When `J` is smaller than the shape
count, the active floor rotates by epoch instead of permanently favoring the
front of the list.

When the GPU is enabled and a small-`J` rotation would select only CPU-only
shapes, the coordinator moves one already-budgeted CPU slot to a rotating
Metal-capable shape. This host slot keeps the GPU occupied without exceeding
the requested CPU budget.

Shapes run simultaneously during an epoch. Reallocation waits for their exact
round boundaries; the next epoch deliberately refreshes each active shape's
sticky-island population from its own verified checkpoint. This avoids unsafe
live thread migration while preserving independent bests and run-level rank
histories. `--rect-epoch-rounds` controls the **base** work between exact
restarts and defaults to **16** (was 4; range 1–64).

Within an epoch, every shape first runs that base quota. Faster shapes then
keep taking one extra round at a time while their observed average round
wall-time still fits before the predicted finish of the slowest shape's base
quota (straggler-fill). That keeps CPU islands busy instead of idling at the
portfolio join when tensor sizes differ. On large hosts, prefer a higher base
(e.g. 16–32) so reallocation and exact restarts are less frequent.

`--secs` is propagated into every child as the remaining portfolio time. Both
levels stop only at exact rectangular round boundaries, so the limit can
overrun by at most one ordinary worker round rather than a whole portfolio
epoch.

The total `--gpu-walkers` budget is independently split in 16-lane quanta
among shapes with checked-in Metal workers. CPU-only profiles remain eligible
for CPU allocation and never make the portfolio DEGRADED merely because they
lack Metal. `--gpu-policy single` assigns the GPU budget to one currently
highest-scoring GPU shape; the default `adaptive` policy keeps several active.

Mutable state defaults to `--state-dir PATH`, then `METAFLIP_HOME`, then
`$HOME/.tungsten/metaflip`. Each portfolio child uses
`checkpoints/gf2/<tensor>/best.txt` and
`runs/gf2/<tensor>/<run-tag>/status.txt` under that root. With an explicit
`--best PATH`, portfolio children continue to use `PATH.<tensor>`; with an
explicit `--status PATH`, exact child telemetry remains `PATH.<tensor>`. The
parent status has `mode=rect-portfolio`; it receives an in-epoch heartbeat with
live rank, move, exposure, health, and split CPU/GPU failure telemetry. Space
queues an all-shape naive reset at the next exact epoch boundary, atomically
replacing every selected shape checkpoint even when `J` is smaller than the
shape count and clearing portfolio rank histories; q/Ctrl-C drains the active
epoch and stops.

This first live-store migration intentionally leaves cross-process checkpoint
promotion/CAS, ternary campaign state, and `/tmp` worker, metallib, reject, and
scratch caches unchanged. Those need separate ownership and concurrency
policies rather than a path-only migration. The 7×7 rectangular component
checkpoints do use the shared GF(2) live root.

## CPU campaign

The normal pure-Tungsten FlipFleet binary now accepts every profile directly.
It keeps independent in-process CPU island states across rounds, exact-gates
each island at harvest, and rebases only one rotating island after an
adoption. This preserves basin diversity while one island follows a new
leader. `2x2x5`, `2x3x4`, `2x3x5`, `2x4x5`, `2x5x6`, `3x3x4`, `3x3x5`, `3x4x4`, `3x4x5`,
`3x5x5`, and `4x4x5` also launch
their specialized Metal bundles by default;
`3x4x6`, `3x4x7`, `3x5x6`, `3x5x7`, `4x5x5`, `4x4x6`,
`4x5x6`, `4x5x7`, `4x5x8`, `4x6x6`, `4x6x7`, `4x6x8`, and `5x6x7` report
`gpu=0 reason=cpu-only-profile` and continue on CPU
without marking the campaign degraded. With the default one-round GPU epochs,
the 445 child stays alive through the shared command/ack protocol, retaining
its Metal device, library, pipeline, and buffers across coordinator rounds.

The live rank-drop shapes `2x2x5`, `2x3x5`, `2x4x5`, and `2x5x6` also have a low-cadence exact
5 -> 4 MITM child with a measured 384-candidate pool. All test sixteen
five-term windows, rotate nearby depth through 0/4/8 and advance the pair-beam
offset by 32. A single-shape campaign launches it every eight rounds. A
multi-shape child launches it once per default four-round portfolio epoch and
uses the epoch suffix to continue the rotation. `--no-gpu` disables it. The
worker is a bounded child so its Metal buffers are reclaimed at exit, and its
`mitm_attempts`, `mitm_pairs`, `mitm_ms`, and `mitm_failures` counters are
appended to the status file without changing the dashboard.

The `2x2x5` lane was admitted only after an end-to-end device run. With 64
cal2zone walkers, a 20-second coordinator trial completed 57.6M generic GPU
moves plus 14.1M MITM pair probes across twelve windows, with both children
ready, zero GPU failures, zero exact rejects, and an independently replayed
rank-18/d84 result. A wider four-door calibration exhausted 960 windows at
pool 256 and another 960 at pool 384: 101,866,548 complementary pair probes
and 10,782 fingerprint hits crossed the exact local check without finding
rank 17. Pool 384 remains the default because it adds candidate breadth while
keeping each sixteen-window child bounded to well under one second here.

The first 4,096-walker calibration then exposed a duplicate-compaction defect
inside the generated GPU hot loop: cancelling two equal GF(2) terms could
remove one duplicate and one unrelated tail term. The exhaustive host gate
rejected every resulting nominal improvement, so no bad scheme was admitted.
The corrected compactor removes the higher duplicate index first and the lower
index second as independent tail deletions. It was regenerated into all square
and rectangular workers; the fixed 225 asset subsequently completed 100
full-width rounds at 20,000 moves per lane (8,192,000,000 moves) with zero
internal rejects and zero false improvements.

The certified `<2,2,5>` gap also has an offline exact residual-worm prototype.
It keeps exactly 17 nonzero terms and the complete sparse carrier
`G = S XOR T`, with incremental updates checked against periodic full
reconstruction. A planted control closes exactly. The expanded d84/d88 audit
spent 72 million proposals per door and archived 633 collision-safe unit-floor
states. An exhaustive correlated two-term repair then checked all 86,088 old
term pairs; none of the resulting carriers had tensor rank at most two. The
complete rank-at-most-three follow-up then deduplicated the archive to 556
ordered term lists and exhausted all 378,080 old-term triples, 35.2 million
GL(3,2) bases, and 32,463 completing-matrix candidates without a rank-17
child. The worm and both repair depths therefore remain offline; see
`RESIDUAL_WORM_225.md` and `THREE_TERM_REPAIR_225.md`.

```sh
bin/tungsten compile benchmarks/matmul/metaflip/flipfleet.w \
  --out /tmp/flipfleet --release --fast --lto

/tmp/flipfleet --tensor 2x2x5 --secs 3600
/tmp/flipfleet --tensor 2x2x6 --no-gpu --secs 3600
/tmp/flipfleet --tensor 2x3x5 --secs 3600
/tmp/flipfleet --tensor 4x4x5 --secs 3600
/tmp/flipfleet --tensor 2x3x4 --secs 3600
/tmp/flipfleet --tensor 2x4x5 --secs 3600
/tmp/flipfleet --tensor 2x5x6 --secs 3600
/tmp/flipfleet --tensor 3x3x5 --secs 3600
/tmp/flipfleet --tensor 3x4x5 --secs 3600
/tmp/flipfleet --tensor 3x4x6 --no-gpu --secs 3600
/tmp/flipfleet --tensor 3x4x7 --no-gpu --secs 3600
/tmp/flipfleet --tensor 3x5x5 --secs 3600
/tmp/flipfleet --tensor 3x5x6 --no-gpu --secs 3600
/tmp/flipfleet --tensor 3x5x7 --no-gpu --secs 3600
/tmp/flipfleet --tensor 4x5x5 --secs 3600
/tmp/flipfleet --tensor 4x4x6 --secs 3600
/tmp/flipfleet --tensor 4x5x6 --no-gpu --secs 3600
/tmp/flipfleet --tensor 4x5x7 --no-gpu --secs 3600
/tmp/flipfleet --tensor 4x5x8 --no-gpu --secs 3600
/tmp/flipfleet --tensor 4x6x6 --no-gpu --secs 3600
/tmp/flipfleet --tensor 4x6x7 --no-gpu --secs 3600
/tmp/flipfleet --tensor 4x6x8 --no-gpu --secs 3600
/tmp/flipfleet --tensor 5x6x7 --no-gpu --secs 3600
```

Rectangular mode renders the same styled dashboard as square FlipFleet: the
honest objective against the profile record, rank/density sparklines, the CPU
island table, the cal2zone relay row with exposure-normalized reward, and the
wall-time rank timeline, with the same keyboard controls (space = reset the
fleet to a naive frontier, w = reseed the islands on the campaign anchor,
q/Ctrl-C = cooperative stop, twice = force). CPU-only profiles show an
explicit "CPU-only profile" section instead of pretending at a Metal engine.
`--no-tui` keeps the machine-readable `RECT_STATUS` line stream, and the
status file is written either way. Every profile defaults to its own durable
`checkpoints/gf2/<tensor>/best.txt` checkpoint under the live-state root (for
example, `checkpoints/gf2/3x4x5/best.txt`). The
346/347/356/357/445/455/446/456/457/458/
466/467/468/567 lanes are not
silently inserted into a 7x7 campaign: those leaf shapes do not occur in the
exact 7x7 block composition, so doing so would only reduce useful 7x7
throughput.

The single-shape coordinator measures the slowest CPU island and the completed
cal2zone epoch, then boundedly adjusts the *next* CPU tranche toward the Metal
wall time. It never changes live state, preserves the three phase ratios, caps
one update at 4× and the absolute budget at 32× `--steps`, and does nothing on
CPU-only profiles. `cpu_epoch_steps` is recorded in status. On the M5 Max
2x5x6 campaign, the prior 500K barrier tranche covered 5.38B CPU moves in
1,109 seconds (4.85M/s); a 12-second five-island/full-width smoke with the
controller covered 691,272,730 moves (57.6M/s), with exact rank 47/d438 and
zero CPU, GPU, or MITM rejection/failure. This is a scheduling throughput
result, not rank evidence.

The standalone one-lane runner remains useful for controlled finite trials:

Build once from the repository root:

```sh
bin/tungsten compile benchmarks/matmul/metaflip/flipfleet_rect_lane.w \
  --out /tmp/flipfleet-rect --release --fast --lto
```

`record` resolves through the pure-Tungsten profile table.  Every successful
run reloads and exhaustively verifies its seed, walks, verifies the saved best,
and writes ordinary FlipFleet text format.

Finite CPU runs reserve 10% of their moves for focused work, give 70% to the
adaptive work/wander sawtooth, and finish with a guaranteed 20% wander slice.
This makes basin escape independent of the RNG-selected starting band: every
documented 100M-move run exercises both modes and the 2,000-move split cadence.
`RECT_STATUS` reports `work_moves`, `wander_moves`, `split_attempts`, and
accepted `splits` so that coverage is visible rather than inferred.

```sh
/tmp/flipfleet-rect 4x4x5 record 100000000 445001 /tmp/rect-445-best.txt
/tmp/flipfleet-rect 2x3x4 record 100000000 234001 /tmp/rect-234-best.txt
/tmp/flipfleet-rect 2x4x5 record 100000000 245001 /tmp/rect-245-best.txt
/tmp/flipfleet-rect 2x5x6 record 100000000 256001 /tmp/rect-256-best.txt
/tmp/flipfleet-rect 3x4x6 record 100000000 346001 /tmp/rect-346-best.txt
/tmp/flipfleet-rect 3x4x7 record 100000000 347001 /tmp/rect-347-best.txt
/tmp/flipfleet-rect 3x5x6 record 100000000 356001 /tmp/rect-356-best.txt
/tmp/flipfleet-rect 3x5x7 record 100000000 357001 /tmp/rect-357-best.txt
/tmp/flipfleet-rect 4x5x5 record 100000000 455001 /tmp/rect-455-best.txt
/tmp/flipfleet-rect 4x4x6 record 100000000 446001 /tmp/rect-446-best.txt
/tmp/flipfleet-rect 4x5x6 record 100000000 456001 /tmp/rect-456-best.txt
/tmp/flipfleet-rect 4x5x7 record 100000000 457001 /tmp/rect-457-best.txt
/tmp/flipfleet-rect 4x5x8 record 100000000 458001 /tmp/rect-458-best.txt
/tmp/flipfleet-rect 4x6x6 record 100000000 466001 /tmp/rect-466-best.txt
/tmp/flipfleet-rect 4x6x7 record 100000000 467001 /tmp/rect-467-best.txt
/tmp/flipfleet-rect 4x6x8 record 100000000 468001 /tmp/rect-468-best.txt
/tmp/flipfleet-rect 5x6x7 record 100000000 567001 /tmp/rect-567-best.txt
```

The same binary continues to support `3x3x4` and `3x4x4`.

All fourteen profiles marked `Metal=no` deliberately remain CPU-only. The new
347/356/357/458/466/468 factor widths are 12/28/21, 15/30/18, 15/35/21,
20/40/32, 24/36/24, and 24/48/32 bits. The largest factor is therefore still
well below the signed-i64 63-bit ceiling. Admitting p=8 required only widening
the in-memory shape header from three to four bits per axis; scheme files and
factor storage did not change. No specialized Metal source, capacity, or
threadgroup geometry is claimed until that complete worker is checked in and
independently exact-gated.

## Specialized Metal lanes

All eleven specialized lanes use 16 walkers per threadgroup and i32 factors.
Their capacities and shared-memory footprints are `225: 64/12,288 B`,
`234: 64/12,288 B`, `235: 68/13,056 B`, `245: 80/15,360 B`,
`256: 92/17,664 B`, `334: 68/13,056 B`,
`335: 77/14,784 B`, `344: 80/15,360 B`, `345: 92/17,664 B`,
`355: 107/20,544 B`, and `445: 112/21,504 B`. Each is below Metal's
32 KiB threadgroup limit. Build 445, for example, with its checked-in sidecar:

```sh
TUNGSTEN_LL_PATH=/tmp/cal2zone-445.ll \
  bin/tungsten compile benchmarks/matmul/metaflip/rect_gpu/cal2zone_445.w \
  --out /tmp/cal2zone-445 --release --fast --lto
```

One bounded standalone epoch (256 lanes x 10,000 moves) is:

```sh
/tmp/cal2zone-445 \
  benchmarks/matmul/metaflip/matmul_4x4x5_rank60_d919_gf2.txt \
  /tmp/rect-445-gpu.txt 4 4 5 "" 59 \
  10000 1 4 2500 500 7 256 "" 64 1
```

The last arguments are `steps reseed margin workq wanderq wthr lanes live
escapes rounds`.  The host writes a candidate only after reconstructing the
complete rectangular tensor.  A coordinator should adopt the output only if
its `(rank,density)` pair improves the current seed, then use that exact file
for the next epoch.  `flipfleet_rect_gpu_bundle.w` supplies the same build and
epoch ABI to native coordinators. Split-escape portfolios interleave U/V/W
axes, so allocations as small as one 16-lane threadgroup still explore all
three factor directions.

The bring-up chain was itself productive: 2.56M moves reduced the imported
rank-60 seed from density 957 to 930; two 102.4M-move epochs reached 922 and
then **919**.  A 409.6M-move follow-up was neutral.  Every written candidate
passed the relay's complete tensor gate and the independent CPU loader.  This
is a same-rank cost/basin improvement, not rank 59.

The first 335/345/355 integration smokes were also immediately productive.
With one CPU island and 48 Metal lanes at 1,000 moves each, the exact
rank-preserving leaders became 335 d**305**, 345 d**390**, and 355 d**519**.

The 234, 235, 245, and 256 workers compile both their pure-Tungsten host relays and
offline Metal libraries and pass bounded 16-lane x 1,000-move dispatches from
their canonical rank-20, rank-25, rank-33, and rank-47 frontiers. The smokes were neutral and
reported zero internal rejects. Their relays accept both public `R u v w`
catalogue files and FlipFleet's numeric-rank checkpoint spelling, so the
checked-in profile seed can also be replayed directly.

The follow-up production-coordinator controls assigned 4,096 lanes and
completed 4.25984B moves on 234 and 2.4576B moves on 245, again with zero exact
rejects. They remained at rank 20/d130 and rank 33/d246. The 235 profile used
its exact rank-25/d160 leader: a four-round 4,096-lane standalone run covered
1.6384B moves in 5.27 seconds (311M moves/s including process setup under
concurrent GPU load), and an integrated 10.24M-move cal2zone plus 1,176,576-pair
MITM smoke finished with zero failures, exact rejects, or internal rejects.
These finite runs do not prove the live 235/245 targets impossible; they
establish that the new lanes can
consume full adaptive GPU allocations without corrupting their primitive
frontiers.

The 256 admission used capacity 92, leaving 45 terms of variable-rank shoulder
above the rank-47/d438 catalog frontier while consuming only 17,664 of 32,768
threadgroup bytes. A four-round 4,096-lane standalone smoke covered 163.84M
moves in 2.89 seconds including process setup (56.7M moves/s), with no internal
reject or false improvement. Its exact 5→4 companion tested 16 windows, 6,144
candidates, and 1,176,576 complementary pairs at pool 384 in 1.59 seconds,
with no fingerprint hit or exact rejection. The low-cadence lane is therefore
enabled by default; these are admission measurements, not evidence that rank
46 exists.

The one-round native coordinator smoke then exercised both default GPU paths
together: 2,000 CPU moves, 163.84M cal2zone moves in 1,362 reported GPU ms,
and 1,176,576 MITM pairs in 840 ms. It stopped at exact rank 47/d438 with
`gpu_failures=0`, `exact_rejects=0`, `gpu_internal_rejects=0`,
`mitm_failures=0`, and `gpu_degraded=0`.
The GPU independently wrote 335 d305, 345 d392, and 355 d522 after its complete
reconstruction gate; the CPU island supplied the still-sparser 345 and 355
leaders. The coordinator independently exact-gated all three final files.
These improve base-case density, not tensor rank.

Subsequent independent 48-lane verification epochs each ran 48,000 GPU moves
and 1,000 CPU moves.  The GPU produced further exact improvements 335
d305→d**304**, 345 d390→d**386**, and 355 d519→d**518**, with zero exact
rejections. A later live two-island CPU campaign moved the rank-36 335 leader
from d304 to d**287**. The checked-in d287 copy passed the exhaustive
rectangular gate independently; this is a same-rank density improvement, not
rank 35. The d287/d386/d518 files are now the respective campaign defaults.

## Seed provenance and licensing

Scheme files cannot contain comments, so attribution lives here.

- `matmul_2x3x4_rank20_catalog_gf2.txt` is the exact row-major-mask import of
  the verified Hopcroft--Kerr construction in the pinned `0320f745` catalog
  snapshot. It has density 136 and SHA-256
  `12399a40da3e5a043fff4a8445599e879f765d3b17a7a6d5f987e26a0e5e98c8`.
  [Wang's Theorem 2](https://arxiv.org/abs/2603.07280) first certified the
  GF(2) lower bound 19. The independently replayed quotient-rank proof in
  `proof_n324/` now excludes rank 19, establishing exact rank 20.
  This shape has no occurrence in the current materialized/audited local
  block-formula set, so it is an explicit scientific campaign rather than a
  member of the default leverage-weighted portfolio. Its specialized cal2zone
  worker remains useful for density and basin exploration, but the dedicated
  5 -> 4 MITM lane is disabled because a rank drop is now proven impossible.
- `matmul_2x3x5_rank25_d160_fleet_gf2.txt` is the current 235 density default,
  reached by the five-island pure-Tungsten campaign no later than 39.73B
  recorded moves. A separate one-move load/walk/dump replay accepted no move,
  reconstructed the full tensor, and reproduced the file byte for byte. Its
  SHA-256 is
  `48f567ce264b996cb6f1d9ce88296e1830b8a4261830ca3d03fc0a04b04e7be7`.
  It shares three terms with each of d170 and the pinned public d173 scheme
  (term-set distance 44), and zero with the d210/d278 rediscoveries. The older
  d170, d210, and d278 certificates therefore remain genuinely distinct
  restart doors instead of being discarded when the monotonic density best
  advances.
- `matmul_2x4x5_rank33_catalog_gf2.txt` is the exact row-major-mask import of
  the verified Hopcroft--Kerr construction in the pinned `0320f745` catalog
  snapshot. It has density 246 and SHA-256
  `77f5ed66bb5c14d958e20e029680e73d9b5484a250d786df0a38269944da89bb`.
  The catalog's rank-32 AlphaEvolve scheme explicitly excludes GF(2), so it is
  evidence for a useful field-sensitive target, not a seed that can be reduced
  modulo two. The advertised GF(2) target is honestly rank 32.
- `matmul_2x4x5_rank33_d222_fleet_gf2.txt` is the current density default,
  first reached by the pure-Tungsten fleet after the far-GL d241 door opened a
  new basin. Its SHA-256 is
  `fb6d6d0a9ce859695cb8096c0e36fcdbe958190b29d3741d0bdb0c9c90d249a5`.
  The d241 and catalog files remain distinct restart doors rather than being
  discarded when the monotonic best advances.
- `matmul_2x5x6_rank47_catalog_gf2.txt` is the exact GF(2) import of
  `known/section6/2x5x6-r47-alphaevolve-7387644.json` from pinned
  `solven-eu/matmulcatalog@0320f745`. It has density 438 and SHA-256
  `790cc812b08fe84ee6f188447a08e76dd3f771a49514e500fa93aed623d8d841`.
  `flipfleet_256_bound_assets_test.w` independently reconstructs all 3,600
  multiplication-tensor coefficients, checks the 10/30/12-bit factor bounds,
  and pins the strict rank-46 profile target. The downstream sensitivity is
  82 guaranteed terms across ten saved formulas plus 652 across 49 strict audited
  formulas, with three additional shadow records crossing to strict wins.
- `flipfleet_rect_orbit_door_cli.w` separately sampled exact sparse GL words
  and descended each endpoint without discarding equal-density orbit images.
  Its zero-debt 512-sample replay found
  `matmul_2x5x6_rank47_d438_orbit_door_gf2.txt`, an exact rank-47/d438 scheme
  with no terms shared with the catalog leader (term-set distance 94, the
  maximum possible). Its SHA-256 is
  `9db0a90aa042a75dece6ea15a082c34de3f942ce3c90014bf50d25b9e0ec7704`.
  The profile now alternates these two sticky CPU doors and gives the
  nonleader half of the Metal epochs, rather than cloning one presentation
  across the whole fleet.

  A compact deterministic replay needs only the first four samples:

  ```sh
  bin/tungsten compile --release --fast --lto \
    -o /tmp/rect-orbit-door \
    benchmarks/matmul/metaflip/flipfleet_rect_orbit_door_cli.w
  /tmp/rect-orbit-door \
    benchmarks/matmul/metaflip/matmul_2x5x6_rank47_catalog_gf2.txt \
    2 5 6 4 64 0 /tmp/2x5x6-orbit-door.txt
  cmp /tmp/2x5x6-orbit-door.txt \
    benchmarks/matmul/metaflip/matmul_2x5x6_rank47_d438_orbit_door_gf2.txt
  ```
- `matmul_3x3x5_rank36_gf2.txt`, `matmul_3x4x5_rank47_gf2.txt`, and
  `matmul_3x5x5_rank58_gf2.txt` are row-major-mask conversions of the
  AlphaTensor F2 entries `3x3x5-r36-alphatensor_F2-a36eef6.json`,
  `3x4x5-r47-alphatensor_F2-6ff64e1.json`, and
  `3x5x5-r58-alphatensor_F2-84728a0.json` from the July 12, 2026
  [`solven-eu/matmulcatalog`](https://github.com/solven-eu/matmulcatalog)
  snapshot. Their independently recomputed densities are 317, 396, and 544;
  SHA-256 values are `48341773d08e1b1f96f6d7130f04454aa1d7726c8d5fad4e057e8a118f2f582b`,
  `23859d363d0424f8e0589f7283f0bb146d917d42a20d001035f4531ae1e9931a`, and
  `ee74be1107684ca3e48920350f98e6d9b192970712775ccab5b27a4b4765ae05`.
- `matmul_3x3x5_rank36_d304_gf2.txt` is the exact GPU-smoke descendant and
  retained prior campaign seed; SHA-256 is
  `b344c76f7db175a30d8c3e7e28cdf5d3993ddb9045e9de3ea50c3b3723d1395f`.
  `matmul_3x3x5_rank36_d287_gf2.txt` descends from it through the live CPU
  campaign and is the new default; SHA-256 is
  `f749a7ab90b623177b9830d5f490c84446b85dca9de080e42beec80c35bf1a40`.
  Both remain rank 36 and pass the independent rectangular exact gate.
- `matmul_3x4x5_rank47_d386_gf2.txt` and
  `matmul_3x5x5_rank58_d518_gf2.txt` are the exact FlipFleet descendants from
  the unified CPU/GPU smokes and remain their campaign defaults. Their
  SHA-256 values are
  `b6093096f8ad2ccbad9ab24c3b88742c013d409168c900e549fa0e85c6d704c4` and
  `aa9e6732b454b759cdad9d51b24c806ae00096489cc00be5d254514dc0d4917b`.
- `matmul_3x4x6_rank54_catalog_gf2.txt` is the exact rank-54 GF(2) catalog
  frontier from the same pinned `0320f745` snapshot. Its density is 826 and
  SHA-256 is
  `8cd49512a068c5b577dedf43e6c0079e028f395555540ce53e83165b52759ec9`.
  The campaign target is rank 53; one such leaf would improve 122 strict
  audited formulas with 1,417 aggregate term savings, while six additional
  shadow rows would cross their pinned baselines.
- `matmul_3x4x7_rank64_catalog_gf2.txt`,
  `matmul_3x5x6_rank68_catalog_gf2.txt`, and
  `matmul_3x5x7_rank79_d699_gf2.txt` are exact pinned-catalog imports with
  densities 603, 634, and 699. Their SHA-256 values are
  `654e59edf43111be5abb96c025f8def97ed188c778cb8149dc5406d48ee38a6f`,
  `29f7e4a2e151bbe4d5bb0fe320bb760c61c697d3ec1945fd4eabbbcba823708c`,
  and `c138bcb1089a08456c033363819e5235b0712b9488f6c9661d6a5f19d368a5e5`.
  The 3x4x7 rank-63 catalog schemes explicitly exclude GF(2), so 63 is an
  honest field-sensitive target. The exact 100M-move throughput run improved
  347 at the same rank to density 576; the retained legacy door
  `matmul_3x4x7_rank64_d576_gf2.txt` has SHA-256
  `7b3e9209515c78d76f4fa71988fd314933205cf72a6704df3a9d7cf0c672dc38`.

- `matmul_4x4x5_rank60_gf2.txt` is a row-major-mask conversion of
  [`solutions/445-60-mod2.exp`](https://github.com/jakobmoosbauer/flips/blob/main/solutions/445-60-mod2.exp),
  attributed upstream to Kauers--Moosbauer.  The `jakobmoosbauer/flips`
  repository states GPL-3.0-or-later.  Its normalized file has density 957
  and SHA-256 `2329655d5d85a0ec83cbbad53f84d0d063a4cfade8ec7b0c001decdcb3a559db`.
- `matmul_4x4x5_rank60_d919_gf2.txt` is a July 13, 2026 FlipFleet-derived
  exact descendant of that rank-60 seed.  It retains the same rank and is the
  legacy alternate campaign door; SHA-256
  `196faff03add76b4b1a86908a5a9d2e13d25aae88afdf17a24dd6ab69875a467`.
- `matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt` is the July 14, 2026
  default.  A complete-gated whole-scheme rectangular GL descent first moved
  d919 to the zero-overlap
  `matmul_4x4x5_rank60_d655_global_isotropy_gf2.txt` presentation; its
  SHA-256 is
  `581e031ef98b004f302ed45ef63f6337ac3abd403892ab9280c1def70c092535`.
  A one-core continuation then reached d628.  A matched 5.05-billion-move d919 control with the same
  `-d 8 --cycles 10` schedule remained at d919, while the GL seed reached
  d628 with zero exact rejects.  Independent coefficient-parity reconstruction
  accepted all 80 target coefficients and all 60 terms are unique.  Its
  SHA-256 is
  `ea5474eecf79c21daccaf29069064f4ed65e9af069a333efc44cf9f18539a66c`.
  Fresh implicit multiwalker starts alternate d628 and d919 across CPU islands;
  explicit `--seed` experiments do not draw from this two-door bank.

  The d655 -> d628 continuation is itself a short replayable escape path: six
  independent shared-factor 2-for-2 flips.  Each row below removes the two
  terms on the left and adds the two on the right.  Complete tensor
  reconstruction passes after every row, and the density timeline is
  655, 653, 651, 648, 641, 635, 628.

  | Remove | Add |
  |---|---|
  | `(16,132,291720)`, `(16,12953,279332)` | `(16,132,12460)`, `(16,12829,279332)` |
  | `(128,131200,160)`, `(128,968096,36)` | `(128,131200,132)`, `(128,836896,36)` |
  | `(176,4224,12684)`, `(672,4224,12288)` | `(176,4224,396)`, `(528,4224,12288)` |
  | `(2048,363529,5120)`, `(2048,494605,4100)` | `(2048,131076,4100)`, `(2048,363529,1028)` |
  | `(240,4096,20672)`, `(4080,4096,20480)` | `(240,4096,192)`, `(3840,4096,20480)` |
  | `(32768,622705,163840)`, `(32768,753781,131076)` | `(32768,131076,131076)`, `(32768,622705,32772)` |

  A bit-packed linear audit of the complete d919/d628 symmetric difference
  found rank 119 on its 120 rank-one tensors: nullity one, consisting only of
  the full 60-for-60 relation.  Thus a direct raw parent-difference splice has
  no proper subrelation to exploit; future differential work should pair d628
  with a genuinely independent frontier rather than spend cycles on this pair.

### A third 4x4x5 door from short GL words and an exact splice

The follow-up searched for that independent frontier rather than treating raw
term distance as sufficient.  The pure-Tungsten
`flipfleet_rect_short_orbit_scout.w` generated 4,096 deterministic
two-generator and 4,096 three-generator images from each of d628, d655, d919,
and the imported d957 seed.  Every image was audited against both d628 and
d919 by the complete rectangular column eliminator in
`flipfleet_rect_archive_nullspace.w`: 32,768 exact images and 65,536 parent
pair audits in the discovery pass. Of those pairs, 1,140 had nullity greater
than one and therefore admitted a proper splice. None produced rank 59.

The strongest independent path began at d655. Logical scout seed 683 applies
two elementary GL generators and yields an exact rank-60/d685 image at
distance 118 from d628 and 120 from d919. Its d628 union difference has 118
columns, column rank 115, and nullity three. The best proper relation exchanges
57 terms from each side and materializes an exact rank-60/d679 child at
distances 114 and 120 from d628 and d919.

Two matched 100-million-move continuations used `-d 8 --cycles 10` and
`-d 12 --cycles 16`. Both d679 arms reached rank 60/d662; both d628 controls
remained fixed at d628. All four runs had zero exact rejects and no rank drop.
The retained d662 endpoint has 12 equal-factor pairs, distance 106 from d628,
and the maximum distance 120 from d919. Its two union differences have ranks
105/119 and nullity one in both cases, so it is algebraically independent of
the earlier doors: neither pair hides another proper differential splice.
The checked-in certificate is
`matmul_4x4x5_rank60_d662_short_orbit_splice_gf2.txt`, SHA-256
`2fc026e447cb503662f4d214c65ff862c75b45a615024e09c6231dc457781ee8`.

A final identical 4,096-word sweep from d662 added 8,192 exact images and
16,384 anchor-pair audits. It found 145 more proper rank-neutral splices, but
no rank drop and no density improvement over d628. Across discovery and
follow-up the bounded audit therefore covered 40,960 images, 81,920 complete
pair eliminations, and 1,285 proper splices.

`flipfleet_rect_short_orbit_frontier_test.w` deterministically replays the
two-generator d685 image and nullity-three 57-for-57 splice, reconstructs every
saved tensor coefficient, and rechecks the d662 distances and nullity-one
negatives. The d662 file is a third CPU restart door, not the monotonic default:
d628 remains the density leader. These experiments raise the bounded 4x4x5
CPU total from 43.35 to 43.75 billion moves without finding rank 59; that
negative is still not a lower bound.
- `matmul_4x5x5_rank76_gf2.txt` is the modulo-two, row-major-mask conversion
  of `schemes/known/alpha_tensor/4x5x5_m76_ZT.json` from
  [`dronperminov/FastMatrixMultiplication`](https://github.com/dronperminov/FastMatrixMultiplication),
  which attributes the algorithm to AlphaTensor and is MIT-licensed.  It has
  density 700 and SHA-256
  `880e56b3f1025e1c31740c8ddaed0cb0b50a10ee1c18add11fb5e40d135171cd`.
- `matmul_4x4x6_rank73_gf2.txt` is the modulo-two, row-major-mask conversion
  of `schemes/known/meta_flip_graph/446/k0cef5a8da5b948d.m` from the same
  MIT-licensed Perminov repository, with its upstream Kauers--Wood 2025
  attribution retained.  It has density 704 and SHA-256
  `6dbec3749d3d21f1d24538f78c31df7af3bf26b3e03b604c43e7991cd4c63fa0`.
- `matmul_4x5x6_rank90_catalog_gf2.txt` is the exact rank-90 GF(2) catalog
  frontier from the pinned `0320f745` snapshot. Its density is 975 and
  SHA-256 is
  `6c77383ee4b0eb1308b42545ad1ded7b47cfe2abac82e2638e5343b61deeef86`.
  The campaign target is rank 89; one such leaf would improve 169 strict
  audited formulas with 1,683 aggregate term savings, while six additional
  shadow rows would cross their pinned baselines.
- `matmul_4x5x7_rank104_catalog_gf2.txt` is the independently exact-gated
  row-major-mask conversion of the `4x5x7` rank-104 leaf in the July 12, 2026
  `solven-eu/matmulcatalog` snapshot at commit `0320f745`. Its 20/35/28-bit
  factors fit the shared-i64 CPU worker, and its density is 1163; SHA-256 is
  `fc2f160881935aced3c50292513f0a4dac2037501fc1dffcaf5c4de76e7d62c8`.
- `matmul_4x5x7_rank104_d1160_gf2.txt` is the exact descendant produced by the
  one-core 100M-move profile smoke. It is the legacy alternate door; SHA-256
  is `60423bde1b1740c68f9e724f9853cde75b7d180f20222567fce91a6e256b9ff1`.
  This is a density improvement from 1163 to 1160 at rank 104, not a rank
  record. No Metal geometry or worker is claimed for this profile.
- The imported 458/466/468 frontiers are
  `matmul_4x5x8_rank118_d1731_gf2.txt`,
  `matmul_4x6x6_rank105_catalog_gf2.txt`, and
  `matmul_4x6x8_rank140_catalog_gf2.txt`, with exact densities
  1,731/1,199/1,824 and SHA-256 values
  `6d12048c172e6f24cf3ebe798bd5cca93f62c7cbe4402972d1a8cdfd92bf5072`,
  `74a75a5f5b771d8959bdba772a932151d182894902cf6ee035b850482b692370`,
  and `58fa1dfc69e23c8a84944b8ba47105b6a87fd617478b700835f47dedeba5635d`.
  The matched 20M-move benchmark produced independently exact same-rank
  descendants at densities 1,729/1,197/1,748. Those prior campaign seeds are
  `matmul_4x5x8_rank118_d1729_gf2.txt`,
  `matmul_4x6x6_rank105_d1197_gf2.txt`, and
  `matmul_4x6x8_rank140_d1748_gf2.txt`, with SHA-256 values
  `8482c833cfb71835993a38e93d9f087e75050f14063b87d7cd0f6458173ca5e1`,
  `302e917245a7ee65528efca555d5391d857fe8364f264fb57f83f6487ec8ee47`,
  and `e27d8593f8a4b427af5359ae413a95aea00fb0f04a8c4c1ae2bfbe36e225e2ca`.
  The d1,197 466 scheme remains that profile's default; d1,729 and d1,748 are
  now legacy alternate doors. These are cost improvements, not rank records.
- `matmul_4x6x7_rank123_catalog_gf2.txt` and
  `matmul_5x6x7_rank150_catalog_gf2.txt` are exact row-major-mask conversions
  of the pinned catalog frontiers. Their densities are 1,860 and 2,329, and
  their SHA-256 values are
  `f0ded6b5146e81cfd80b87f468c35b4ffbec2d0de0d87cc00eb5259a2371f4de`
  and `dee43e30776cc62b16618cc91b70b5acd400332f362d8b7f1bfe99e56d8da2d0`.
  The strict targets are rank 122 and 149. One-rank improvements would remove
  2,002 and 1,579 terms across the audited winning formulas, respectively.
  Both profiles are CPU-only until specialized Metal workers are checked in.

### Five exact doors for the certified 2x2x5 gap

The checked lower bound 17 and exact rank-18 upper construction make 2x2x5
the highest-priority default rectangular target. The first integrated smoke
reduced the `3+2` block seed from d95 to d88; a zero-overlap whole-scheme GL
door then opened the d84 density basin. The retained d84/d88 pair shares no
term, and its 36 tensor columns have rank 35, so only the full 18-for-18
parent difference exists.

`flipfleet_225_block_gl_bank.w` adds a construction outside that single-image
experiment. It applies unrelated sparse GL words to the exact rank-11
`<2,2,3>` and rank-7 Strassen leaves before embedding the two output-column
blocks. All 4,096 enumerated compositions reconstructed the full 2x2x5
tensor. The selected d92 member has 16 equal-factor pairs and zero overlap
with d84 and d88. Its union with d84 has column rank 34/nullity two; the proper
dependency exchanges eleven terms from each parent and gives the saved second
d84 presentation.

Two 100M-move trials from each of block-d92, splice-d84, d84, and d88—800M
moves total—made no rank or density improvement and had zero exact rejects.
This is not objective evidence, but all four endpoints are exact and occupy
different verified parent-difference geometry, so the profile initially rotated
them as four sticky CPU doors. Their generator and replay files are
`matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt` and
`matmul_2x2x5_rank18_d84_block_splice_gf2.txt`.

After the rectangular GPU duplicate-compaction repair, alternating epochs from
fleet best and nonleader sticky doors made the block-d92 seed productive.  A
4096-lane epoch returned through d89 and d86 to an exact d84 presentation; the
shape-aware host gate accepted it and fed it back only to its source island.
The retained `matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt` has SHA-256
`86b73a254dcafe6e39c1411d183a07cad43083bf5b6818a3f574996d103618a1`.
It is distance 28/36/10/14 from d84/d88/block-d92/splice-d84 respectively,
so it becomes the fifth sticky door rather than replacing the density leader.

The follow-up `flipfleet_225_block_nullspace_scan.w` now exhausts every
dependency in all 4,096 deterministic block parents crossed with all five
doors. Across 20,479 nonidentical unions, nullity was only one through four,
so all 52,575 nonzero combinations were covered without a cap. The scan found
32,096 proper rank-18 relations and no projected or exact rank-17 relation;
15,940 minimum
children passed the independent `ffran_crossover` gate. The most novel r18
hybrid remained a distance-four step from its generated block parent and had
extra nullspace relations with four doors, so it is not retained as a sixth
door. Full results are in `BLOCK_GL_NULLSPACE_225.md`.

Pairwise selection was not the end of that audit. The pure-Tungsten
multi-parent solver deduplicated the joint term union and enumerated the full
affine solution coset, allowing one exact subset to use terms from three or
more schemes. The five-door union itself has 55 columns, rank 51, and only 16
solutions. Extending it by every one of the 4,096 block parents, then by every
pair and triple from a 32-parent maximin archive, visited 11,942,176 affine
masks. All 232,978 masks of weight 18 were independently exact-gated; none had
weight 17. This is a complete negative for those overlapping unions, not a
global lower bound. Replay and the next weight-17 SAT/MITM step are in
`MULTI_PARENT_NULLSPACE_225.md`.

### Three-Strassen block-local closure for 2x2x6

The adjacent 2x2x6 target now has an independently generated second CPU door.
`flipfleet_226_block_gl_parent_lib.w` applies unrelated exact sparse GL words
to all three rank-7 Strassen leaves before their `2+2+2` output-column
embedding. Among 4,096 exact parents, index 7 has rank 21/d108, 21
equal-factor pairs, and maximum term-set distance 42 from the d108 baseline;
the two schemes share no terms. The retained file is
`matmul_2x2x6_rank21_d108_block_local_gl_gf2.txt`, SHA-256
`6c74b5bb150e2e9d6529c00edcd319baaed3d8b53792024c7d0f7d71198b5405`.

The follow-up complete nullspace scan crossed every parent with the baseline
and all 496 pairs in a 32-parent diverse archive. All 4,522 nonempty
42-column differences had nullity three. The tool enumerated 31,654 relations
and independently reconstructed all 27,132 proper hybrids; each remained
exact rank 21, with no rank-20 projection and no capped hull. This finite
nullspace family is therefore retired from the live strategy pool, while the
zero-overlap endpoint rotates as the profile's second sticky CPU door. A
matched 100M+100M ordinary-worker screen left both arms exact r21/d108; the
door arm reached a distinct equal-density presentation while the baseline arm
did not move its best. See `BLOCK_GL_NULLSPACE_226.md` for commands, timing,
and replay details.

## Far-GL rectangular frontier normalization (July 14, 2026)

The dimension-generic pure-Tungsten
`flipfleet_rect_global_isotropy_cli.w` complete-gates a whole-scheme GL image,
runs transvection descent, writes it, reparses it, and gates it again.  Applying
that tunnel across the rectangular portfolio exposed ten additional
record-rank presentations that were substantially sparser than their legacy
doors. Short same-seed CPU screens retained or improved every gain:

| Shape | Legacy density | GL density | Retained density | Legacy distance | Matched 25M result |
|---|---:|---:|---:|---:|---|
| `2x4x5` | 246 | 241 | **241** | 56 | four controls d246; four GL arms d241 |
| `3x4x6` | 826 | 488 | **488** | 108 | four controls d826; four GL arms d488 |
| `3x4x7` | 576 | 519 | **519** | 124 | four controls d576; four GL arms d519 |
| `4x4x6` | 704 | 694 | **690** | 144 | two controls d704; two GL arms d690 |
| `4x5x6` | 975 | 921 | **907** | 180 | two controls d975; two GL arms d907 |
| `4x5x7` | 1,160 | 1,101 | **1,089** | 208 | two controls d1160; two GL arms d1089 |
| `4x5x8` | 1,729 | 1,299 | **1,283** | 236 | controls d1729/d1727/d1727/d1727; GL d1283/d1283/d1284/d1283 |
| `4x6x7` | 1,860 | 1,412 | **1,406** | 246 | four controls d1847; four GL arms d1406 |
| `4x6x8` | 1,748 | 1,560 | **1,560** | 280 | two controls d1748; two GL arms d1560 |
| `5x6x7` | 2,329 | 1,876 | **1,875** | 300 | four controls d2329; four GL arms d1875 |

### Later `2x4x5` fleet density leader

The continuing pure-Tungsten `2x4x5` fleet moved beyond the far-GL d241
frontier and first reached exact rank 33/d222 by 199.6 billion worker moves.
A fresh one-move worker replay independently reconstructed every coefficient
and reproduced the file byte for byte with no accepted move. The retained
certificate is `matmul_2x4x5_rank33_d222_fleet_gf2.txt`, SHA-256
`fb6d6d0a9ce859695cb8096c0e36fcdbe958190b29d3741d0bdb0c9c90d249a5`.

Its overlap with the d241 and catalog doors is 7 and 0 terms respectively,
giving term-set distances 52 and 66. The d222 scheme is now the default; d241
and the catalog presentation remain the second and third sticky doors. This is
a density/basin improvement at rank 33, not a rank-32 result.

Every retained file has the published rank, only nonzero in-range factors,
unique terms, and zero residual slices under an independent rectangular
coefficient-parity reconstruction. No screen found a rank drop.  The files and
SHA-256 values are:

| Far-GL campaign file | SHA-256 |
|---|---|
| `matmul_2x4x5_rank33_d241_gl_frontier_gf2.txt` | `45a74cf6cfb2d0ac8cd4bd7abe024ae8593a652a9d08f969b7691382be351389` |
| `matmul_3x4x6_rank54_d488_gl_frontier_gf2.txt` | `948ee56484fef065ebf0e90775d9dc8e76c714a9139ac167ebbc766efab1b470` |
| `matmul_3x4x7_rank64_d519_gl_frontier_gf2.txt` | `0207f24c72e416eed1f7e05e3d993ded82de3f7e30576205167c717b8cc208f7` |
| `matmul_4x4x6_rank73_d690_gl_frontier_gf2.txt` | `c3d543a4b6ddf6575c2420d6528e99d08619279d8fa426a4313383e915dbda5c` |
| `matmul_4x5x6_rank90_d907_gl_frontier_gf2.txt` | `6ffffef39fc50910827858fa09a2a2d3cb3c6945c8c6ecb62d11db67e418e0ac` |
| `matmul_4x5x7_rank104_d1089_gl_frontier_gf2.txt` | `7927f446a1aff46621d92d9803dd24c3ee151e197bfd80c14f2dab10ba0edbc6` |
| `matmul_4x5x8_rank118_d1283_gl_frontier_gf2.txt` | `7c650619c450ed83ac900d91ca66ceeedb368175ea80355307d9f1331d489d35` |
| `matmul_4x6x7_rank123_d1406_gl_frontier_gf2.txt` | `1e6e60a9b7516a0217594cc12df418a4608a2014e7e18a4faf54a23f5e4ebae1` |
| `matmul_4x6x8_rank140_d1560_global_isotropy_gf2.txt` | `ca9250e48c4b64e55333474d8b3001618056fe4c0b64eaaacbb2563b35bf69a0` |
| `matmul_5x6x7_rank150_d1875_gl_frontier_gf2.txt` | `e3166e8664e9af1bc13a52618413e4e56f771dcdaa94abcf647044ca11c693d4` |

These are density/basin improvements, not tensor-rank records. Implicit
multiwalker starts alternate each far-GL default with its checked-in legacy
door. Explicit `--seed` remains single-source, so controlled comparisons do
not silently acquire a second frontier.

The July 12, 2026 `solven-eu/matmulcatalog` snapshot was used as an independent
orientation/field cross-check.  Its JSON convention stores W column-major;
the FlipFleet files transpose W to local row-major masks before exhaustive
GF(2) verification.
