# Rectangular GF(2) campaigns

FlipFleet has eleven canonical rectangular profiles.  They all use the same
runtime-generic pure-Tungsten CPU worker and exhaustive reconstruction gate;
the six GPU-enabled profiles additionally have checked-in, dimension-
specialized Tungsten/Metal relays with independent `nm`, `mp`, and `np` masks.

| tensor | exact seed | strict target | CPU | Metal | immediate use |
|---|---:|---:|---:|---:|---|
| `3x3x4` | 29 | 28 | yes | yes | each rank saved removes three terms from the 7x7 composition |
| `3x3x5` | 36 | 35 | yes | yes | rank-47 outer block-composition leaf |
| `3x4x4` | 38 | 37 | yes | yes | each rank saved removes three terms from the 7x7 composition |
| `3x4x5` | 47 | 46 | yes | yes | high-leverage leaf in 15x16x17 and related records |
| `3x4x6` | 54 | **53** | yes | no | 1,417 uses across 122 strict audited formulas |
| `3x5x5` | 58 | 57 | yes | yes | rank-47 outer block-composition leaf |
| `4x4x5` | 60 | **59** | yes | **yes** | high-multiplicity leaf in the new block compositions |
| `4x5x5` | 76 | 75 | yes | no | allocation/product leaf scout |
| `4x4x6` | 73 | 72 | yes | no | allocation/product leaf scout |
| `4x5x6` | 90 | **89** | yes | no | 1,683 uses across 169 strict audited formulas |
| `4x5x7` | 104 | **103** | yes | no | highest aggregate sensitivity across the 760 audited formulas |

The allowlist is intentional.  The worker arithmetic is generic for factor
widths below 63 bits, but a shape is not advertised until it has a checked-in
exact frontier and an honest target.  Likewise, a CPU profile does not claim
GPU support until its specialized Metal source and legal shared-memory
geometry are checked in.

## CPU campaign

The normal pure-Tungsten FlipFleet binary now accepts every profile directly.
It keeps independent in-process CPU island states across rounds, exact-gates
each island at harvest, and rebases only one rotating island after an
adoption. This preserves basin diversity while one island follows a new
leader. `3x3x4`, `3x3x5`, `3x4x4`, `3x4x5`, `3x5x5`, and `4x4x5` also launch
their specialized Metal bundles by default;
`3x4x6`, `4x5x5`, `4x4x6`, `4x5x6`, and `4x5x7` report
`gpu=0 reason=cpu-only-profile` and continue on CPU
without marking the campaign degraded. With the default one-round GPU epochs,
the 445 child stays alive through the shared command/ack protocol, retaining
its Metal device, library, pipeline, and buffers across coordinator rounds.

```sh
bin/tungsten -o /tmp/flipfleet \
  benchmarks/matmul/metaflip/flipfleet.w \
  --release --native --fast --lto

/tmp/flipfleet --tensor 4x4x5 --secs 3600
/tmp/flipfleet --tensor 3x3x5 --secs 3600
/tmp/flipfleet --tensor 3x4x5 --secs 3600
/tmp/flipfleet --tensor 3x4x6 --no-gpu --secs 3600
/tmp/flipfleet --tensor 3x5x5 --secs 3600
/tmp/flipfleet --tensor 4x5x5 --secs 3600
/tmp/flipfleet --tensor 4x4x6 --secs 3600
/tmp/flipfleet --tensor 4x5x6 --no-gpu --secs 3600
/tmp/flipfleet --tensor 4x5x7 --no-gpu --secs 3600
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
`flipfleet_<tensor>_best.txt` checkpoint (for example,
`flipfleet_3x4x5_best.txt`). The 346/445/455/446/456/457 lanes are not
silently inserted into a 7x7 campaign: those leaf shapes do not occur in the
exact 7x7 block composition, so doing so would only reduce useful 7x7
throughput.

The standalone one-lane runner remains useful for controlled finite trials:

Build once from the repository root:

```sh
bin/tungsten -o /tmp/flipfleet-rect \
  benchmarks/matmul/metaflip/flipfleet_rect_lane.w \
  --release --native --fast --lto
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
/tmp/flipfleet-rect 3x4x6 record 100000000 346001 /tmp/rect-346-best.txt
/tmp/flipfleet-rect 4x5x5 record 100000000 455001 /tmp/rect-455-best.txt
/tmp/flipfleet-rect 4x4x6 record 100000000 446001 /tmp/rect-446-best.txt
/tmp/flipfleet-rect 4x5x6 record 100000000 456001 /tmp/rect-456-best.txt
/tmp/flipfleet-rect 4x5x7 record 100000000 457001 /tmp/rect-457-best.txt
```

The same binary continues to support `3x3x4` and `3x4x4`.

`3x4x6` and `4x5x6` deliberately remain CPU-only. Their factor widths are
only 12/24/18 and 20/30/24 bits respectively, so the shared-i64 worker needs
no representation extension. No specialized Metal source, capacity, or
threadgroup geometry is claimed until that complete worker is checked in and
independently exact-gated.

## Specialized Metal lanes

All six specialized lanes use 16 walkers per threadgroup and i32 factors.
Their capacities and shared-memory footprints are `334: 68/13,056 B`,
`335: 77/14,784 B`, `344: 80/15,360 B`, `345: 92/17,664 B`,
`355: 107/20,544 B`, and `445: 112/21,504 B`. Each is below Metal's
32 KiB threadgroup limit. Build 445, for example, with its checked-in sidecar:

```sh
TUNGSTEN_LL_PATH=/tmp/cal2zone-445.ll \
  bin/tungsten -o /tmp/cal2zone-445 \
  benchmarks/matmul/metaflip/rect_gpu/cal2zone_445.w \
  --release --native --fast --lto
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

- `matmul_4x4x5_rank60_gf2.txt` is a row-major-mask conversion of
  [`solutions/445-60-mod2.exp`](https://github.com/jakobmoosbauer/flips/blob/main/solutions/445-60-mod2.exp),
  attributed upstream to Kauers--Moosbauer.  The `jakobmoosbauer/flips`
  repository states GPL-3.0-or-later.  Its normalized file has density 957
  and SHA-256 `2329655d5d85a0ec83cbbad53f84d0d063a4cfade8ec7b0c001decdcb3a559db`.
- `matmul_4x4x5_rank60_d919_gf2.txt` is a July 13, 2026 FlipFleet-derived
  exact descendant of that rank-60 seed.  It retains the same rank and is the
  default campaign seed; SHA-256
  `196faff03add76b4b1a86908a5a9d2e13d25aae88afdf17a24dd6ab69875a467`.
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
  one-core 100M-move profile smoke. It is the default campaign seed; SHA-256
  is `60423bde1b1740c68f9e724f9853cde75b7d180f20222567fce91a6e256b9ff1`.
  This is a density improvement from 1163 to 1160 at rank 104, not a rank
  record. No Metal geometry or worker is claimed for this profile.

The July 12, 2026 `solven-eu/matmulcatalog` snapshot was used as an independent
orientation/field cross-check.  Its JSON convention stores W column-major;
the FlipFleet files transpose W to local row-major masks before exhaustive
GF(2) verification.
