# Symmetry-aware meta-flip graph for matrix multiplication (GF(2))

A from-scratch implementation of the **meta flip graph** (Kauers & Wood, arXiv:2510.19787)
layered on the **symmetric flip graph** (Moosbauer & Poole, arXiv:2502.04514) — the method
class that produced the current records for several matmul tensor formats.

## Files

| file | what it is |
|---|---|
| `metaflip_proto.py`  | base flip graph (flip / reduction / structured plus), Python reference |
| `metaflip_proto2.py` | rectangular (n,m,p) formats + cross-format extension/projection edges, Python |
| `rect_gen.py`        | generates a rectangular (n,m,p) energy-walk search in **Tungsten** (3-dim verify) |
| `xfmt_test.w`        | Tungsten round-trip test of the cross-format edges (each step tensor-verified) |
| `meta_gen.py`        | generates the full **meta-walk** in Tungsten, seeded from the MP-93 (5,5,5) record |
| `matmul_bench.cu`    | B200 GPU benchmark of the flip-graph search |
| `matmul_5x5_rank93_gf2.txt` | a verified, independently-found rank-93 decomposition of <5,5,5> over GF(2) |
| `flipfleet.py`       | exact-gated coordinator; generates/compiles the hot Tungsten CPU and GPU walkers |
| `sym_start.py`       | exact diagonal-partition starts for target-aligned symmetric search |
| `sym_escape.py`      | standalone generic/C3 split and polarization escape identities |
| `escape_portfolio.py` | exact mixed-family/depth-two escape banks with independent verification |
| `hybrid_escape.py` | staged C3 Tungsten walk → exact symmetry break → ordinary Tungsten/Metal walk |
| `identity_miner.py` | tensor-signature miner for 3-, 4-, and primitive 5-term zero circuits |
| `mitm_surgery.py` | exact-gated restricted k→k−1 local surgery by XOR meet-in-the-middle |
| `../flipgraph_gpu_cal2zone.w` | Tungsten/Metal cal2zone walker with exact split-escape portfolios |
| `../flipgraph_gpu_simdgroup.w` | cooperative one-scheme-per-SIMDgroup Tungsten/Metal walker |
| `../zoo/gpu_cal2zone_gen.py` | dimension/mask-width specializer, including native-i64 6×6 kernels |
| `matmul_3x3_rank23_d139_gf2.txt` | exact rank-23, density-139 cooperative-GPU cost leader |
| `matmul_3x3_rank23_d159_gf2.txt` | mined-escape intermediate that opened the new 3×3 basin |
| `matmul_4x4_rank47_d450_gf2.txt` | exact rank-47, density-450 default 4×4 frontier seed |
| `matmul_5x5_rank93_d1155_gf2.txt` | exact rank-93, density-1155 GPU escape-portfolio cost leader |
| `matmul_5x5_rank93_d1168_gf2.txt` | prior exact rank-93 cost leader from the CPU escape campaign |
| `matmul_5x5_rank93_d1191_gf2.txt` | prior exact C3 rank-93 symmetry-escape seed |
| `matmul_6x6_rank153_d2508_gf2.txt` | exact rank-153, density-2508 cooperative-GPU cost leader |

## The construction

The base flip graph searches one fixed format (n,m,p). The **meta** flip graph glues all
per-format graphs together with two cross-format edges:
- **extension** (n,m,p)→(n,m,p+1): re-index the v/w masks one column wider, append the n·m
  naive terms that compute the new output column. Rank jumps by n·m.
- **projection** (n,m,p)→(n,m,p−1): zero the last B-column, drop the last C-column, prune
  vanished terms. Rank drops.

A search can then route *through a neighboring format* to reach reductions the current
format's flip-graph component does not contain.

## Build status

1. ✅ Rectangular (n,m,p) walk + 3-dimension verify
2. ✅ Cross-format edges — Python and compiled `xfmt_test.w` round-trips are
   tensor-valid on the current compiler
3. ✅ Meta-walk loop (Algorithm 1 policy + extend/project + per-format best tracking)
4. 🔶 Effectiveness — see findings

## Phase-4 findings (important, to avoid re-aiming wrong)

- **The engine is correct.** It routes between formats and reduces (e.g. (5,5,4) down to 78
  from the projected MP-93), staying tensor-valid throughout.
- **The square records are NOT meta-flip targets.** (5,5,5)=93 and (6,6,6)=153 are
  Moosbauer–Poole's *symmetric-flip* results, used as the meta-flip's *seeds*. The meta-flip
  improves the **rectangular vicinity** — (4,5,6)=90, (5,5,7)=127, (5,6,7)=150 — not the
  square records. Hunting (5,5,5)→92 with this tool is mis-aimed.
- **Two gaps to the literature's results:** the per-format search here is the *base* flip
  graph; MP/Kauers–Wood used the more powerful **symmetric** flip graph. And the extension
  direction is **flip-poor** (appended naive column terms barely flip), so re-extended
  schemes resist reduction; the projection direction reduces well.

## Realistic next sprint (record-chasing campaign)

1. Add the **symmetric per-format layer** (C₃ for n=5, C₃×ℤ₂ for n=6).  Abstractly
   this cyclically rotates the three trace/common-space factors; in the local
   row-major A/B/C mask convention it is `(u,v,w)→(v,wᵀ,uᵀ)`.  The separate
   reversal generator still has characteristic-2 connectivity caveats.
2. Target **rectangular** formats; validate by reproducing a known improvement ((4,5,6)=90).
3. Per-format budget ≈ 100000·n·m·p moves (millions), across a fleet.

## Current square campaign driver

Use `flipfleet.py`, rather than the older hard-coded native `flipfleet.w`, for
new 3×3–6×6 runs.  It exact-verifies before adoption, retains the actual best
scheme, ingests same-rank tie snapshots into an exact-gated diversity archive,
keeps a bounded max-min sample of term-set-separated frontier seeds, cycles through the
least-used restart seeds, quarantines persistent invalid dumps, and preserves
island diversity.  Every distinct exact frontier snapshot surfaced to the
coordinator remains durable on disk even if it is not retained in memory.
At equal rank, `best.txt` and status track the sparsest observed representative
(and therefore the lowest no-CSE base-case operation count); diversity storage
remains separate from that rank-then-density leader.

The filename is slightly misleading about the performance boundary: Python is
only the low-frequency coordinator (process supervision, durable archive, and
exact adoption gate).  `bucket_gen.py` emits the complete move loop as
Tungsten, and FlipFleet compiles it with `--release --native --fast --lto`.
There is no Python in the per-move path.  With `--gpu`, the host relay and the
Metal kernel are also generated Tungsten; Python only polls the resulting
candidate file.  The older all-in-one `flipfleet.w` is not the authoritative
driver because its coordination policy and adoption semantics are weaker.

Record-mode walkers use a mixed dwell portfolio by default (`250m,1b,10b`
moves per band).  This makes some islands recycle through separated seeds on a
campaign timescale while retaining deep 10B-band probes.  Override it with
`--record-band-moves`, for example `--record-band-moves 50m,250m,2b`.

```sh
# Reproduce 3×3 from naive.
python3 benchmarks/matmul/metaflip/flipfleet.py \
  --size 3 --walkers 12 --strategy independent --secs 60

# Push from the tracked exact-valid 5×5 record.
python3 benchmarks/matmul/metaflip/flipfleet.py \
  --size 5 --seed record --walkers 12 --strategy islands --stop-on-record

# Generate the Moosbauer--Poole 5×5 start and the rank-92-aligned component.
python3 benchmarks/matmul/metaflip/sym_start.py 5 '1,5;2,4;3' > /tmp/mp5.txt
python3 benchmarks/matmul/metaflip/sym_start.py 5 '1,2,4,5;3' > /tmp/target92.txt
```

The authors' reference solver freezes the invariant diagonal cubes; in that
implementation their count fixes rank modulo three.  Its published three-cube
5×5 run can reach 93 and then 90, while the two-cube start is aligned with 92.
The local `sym_gen2*` prototypes do not freeze singleton orbits, so a plus move
or an ordinary flip involving a one-hot singleton can change their fixed-orbit
count and residue.

### Exact escape identities

In the local row-major storage convention, let
`rho(u,v,w)=(v,w^T,u^T)`, `O(t)={t,rho(t),rho^2(t)}`, and
`C(x)=(x,x,x^T)`.  `sym_escape.py` exposes four deterministic, parity-toggled
identities; every emitted scheme is bounds-checked and reconstructed against
the full matrix-multiplication tensor.

| kind | eligibility and identity | usual effect |
|---|---|---|
| `split` | any term: `(a,b,c)+(y,b,c)+(a+y,b,c)=0`, or V/W analogue | generic +1 escape; works on the non-C3 3×3/4×4 records |
| `break` | the same split, restricted to a fixed cube `C(x)` | nominal +1; deliberately loses C3 |
| `orbit-split` | `C(x)+O(y,x,x^T)+O(x+y,x,x^T)=0` | nominal +5; removes one fixed cube and preserves C3 |
| `polarize` | `C(x)+C(y)+C(x+y)+O_c(x,x,y)+O_c(x,y,y)=0`, where `O_c(a,b,c)=O(a,b,c^T)` | preserves C3 and changes fixed-count/rank residue |

All sums are over GF(2): duplicates cancel, so the actual rank delta is always
reported rather than assumed.  Collision-free polarization is +7; the 5×5/6×6
record bridges happened to be +5 because an existing cube cancelled.  A fixed
parameter identity is self-inverse, although rerunning automatic selection can
choose a different identity.

```sh
# Open the ordinary flip graph from a frozen symmetric waypoint.
python3 benchmarks/matmul/metaflip/sym_escape.py bridge waypoint.txt 4 \
  --kind break > thawed.txt

# Stay C3-closed but remove the fixed orbit; emit a sym_gen2-compatible seed.
python3 benchmarks/matmul/metaflip/sym_escape.py bridge waypoint.txt 4 \
  --kind orbit-split --format usvw > c3-thawed.txt
```

Without `--part`, generic splits draw from the same live factor axis while C3
toggles draw from the transpose-identified common-space pool.  Selection is
deterministic by output rank, shared-factor connectivity, density, and
mask/axis tie breaks.  `--part 0x...` fixes the common-space part.  The much
more expensive `--exhaustive` scans every nonzero part and is limited to n≤4.
Schemes go to stdout; before/after diagnostics go to stderr.

### Escape-enabled FlipFleet

The same identities are integrated into `flipfleet.py` as opt-in launch
excursions.  Selected startup walkers and genuine `CYCLEOUT` restarts receive
one transformed seed; the coordinator deliberately keeps its lower-rank
`initial`, `best.txt`, and diversity archive unchanged.  Escapes never stack,
and are not applied to strict-improvement migration, invalid-worker quarantine,
or an ordinary process exit.  Nominal higher-rank escape seeds stay outside
frontier bookkeeping.  If parity collisions make a generated seed tie or beat
the frontier, its published worker dump is exact-gated and adopted normally.

```sh
# 3×3/4×4 records have no fixed C3 cube: use the generic +1 split.
python3 benchmarks/matmul/metaflip/flipfleet.py \
  --size 4 --seed record --walkers 12 --escape-kind split \
  --escape-at both --escape-every 2 --stop-on-record

# The C3 record profiles have three fixed cubes.
python3 benchmarks/matmul/metaflip/flipfleet.py \
  --size 5 --seed c3-record --walkers 12 --escape-kind orbit-split \
  --escape-at both --escape-every 2 --stop-on-record

# Keep startup on the C3 record and inject polarization only after cycle-outs.
python3 benchmarks/matmul/metaflip/flipfleet.py \
  --size 6 --seed c3-record --escape-kind polarize --escape-at cycleout
```

`--escape-every N` gives a deterministic escaped/base portfolio (the default
is every second eligible launch).  The feature is currently square-only.
`break` needs a fixed cube; `orbit-split` and `polarize` additionally require a
C3-closed base.  An ineligible startup configuration fails before compilation;
an ineligible dynamic archive seed is launched unmodified and logged as
`ESCAPE SKIP`.  Every generated escape is exact-gated before launch.  Events
record the trigger, walker, kind, ranks, fixed counts, C3 state, selected
factor/cube, part, axis, and base digest; `status.json` exposes configuration
and applied/bypassed/skipped counters.  The native worker is an ordinary,
non-quotient walker, so C3
preservation describes the injected seed, not all subsequent states.

Recovery respects an enabled escape profile: a requested `c3-record` is not
silently replaced by a lower-density non-C3 tie from the same run directory.

### Mixed, staged, and mined escapes

`escape_portfolio.py` generalizes the single-split launch portfolio to exact
variable-rank seed banks.  Its default mix covers `split`, `break`,
`orbit-split`, and `polarize`, plus normalized depth-two compositions.  Complete
term sets are parity-canonicalized and independently reconstructed before they
are serialized.  The tracked 5×5 and 6×6 banks each contain 48 exact slots,
split between C3-closed and symmetry-breaking states.  See
[`ESCAPE_PORTFOLIO.md`](ESCAPE_PORTFOLIO.md) for their recipes and real M5 Max
handoff measurements.

`hybrid_escape.py` gives those banks two hot-loop routes.  The `run` command
does a generated C3 Tungsten walk, applies an exact fixed-cube break, and then
hands the result to a generated ordinary Tungsten walker.  The `metal` command
materializes any variable-rank bank slot into a generated Metal relay.  Python
only coordinates stages and independently verifies handoffs; it is not in
either move loop.

`identity_miner.py` hashes expanded rank-one tensor signatures to discover
three-term splits, four-term rectangles, and primitive five-term circuits via
a disjoint pair/triple join.  A small eight-subset, 180-candidate pass found
12/7/115 non-factor-constant five-circuits for 4×4/5×5/6×6 respectively.  For
3×3 it instead found a distance-five multi-split escape with the same +1 rank
cost as an ordinary distance-three split.  Mined outputs can be novelty-sampled
directly into the verified bank format:

```sh
python3 identity_miner.py matmul_4x4_rank47_d450_gf2.txt 4 \
  --bank /tmp/mined-4.jsonl --bank-count 48
python3 escape_portfolio.py verify /tmp/mined-4.jsonl
```

`mitm_surgery.py` is the complementary rank-decreasing scout.  It selects a
local k-term piece, builds a finite family from live factors and pairwise XORs,
and joins tensor signatures to seek a k−1 replacement (up to 5→4).  Every hit
is spliced and fully reconstructed.  Pair joins use a linear 128-bit XOR
projection and full-signature collision checks; on the 6×6/pool-700 control
this reduced peak RSS from about 955 MB to 91 MB.  Initial bounded passes missed on all four
current records (3×3: 32 subsets/pool 700; 4×4: 16/pool 500; 5×5 and 6×6:
8/pool 500).  Those finite-family misses are useful campaign data, not lower
bounds or general local-minimality proofs.

### GPU exact-escape scout

`--gpu` now gives the GPU a complementary job instead of cloning the CPU
fleet's current leader.  At every GPU reseed, the Tungsten host constructs a
portfolio of exact generic split identities from `best.txt`; lane `tid` starts
from portfolio slot `tid % N`.  The transformation is a launch-only +1
excursion, so it breaks out of a frozen C3/symmetric component without adding
work to the hot loop.  Returned candidates pass FlipFleet's normal full tensor
verification before archive admission or migration.

```sh
# 5×5: 4096 lanes distributed across 256 exact symmetry-breaking basins.
python3 benchmarks/matmul/metaflip/flipfleet.py \
  --size 5 --seed record --walkers 12 --gpu --gpu-escapes 256

# 6×6: generated native-i64 Metal masks (36 factor bits).
python3 benchmarks/matmul/metaflip/flipfleet.py \
  --size 6 --seed record --walkers 12 --gpu --gpu-escapes 256
```

Set `--gpu-escapes 1` for the historical all-lanes-from-one-seed behavior.
`--gpu-walkers` and `--gpu-steps` control breadth and dispatch length.  The
generator chooses i32 masks through 30 bits and i64 above that, then reduces
walkers per threadgroup until the three scheme arrays fit Metal's 32 KiB
threadgroup-memory limit.  This required a small Tungsten addition:
`gpu.shared_i64` plus `metal_buffer_{read,write}_i64`.  Rebuild the compiler
before the first 6×6 GPU run.

This also fixes an old 5×5 bias: plus moves used `% 65535`, sampling only 16
of the 25 factor bits.  They now sample the full `2^25-1` mask range.  The
portfolio selection happens only at reseed and adds no per-move branching.
SAT remains a CPU-side proof/search tool here: the existing 4×4 surgery model
cannot solve even its known rank-47 SAT control quickly, so moving that model
to the GPU is currently a larger solver project with a worse evidence base
than spending GPU width on independent exact basins.

The first on-device M5 Max validation chained the 6×6 frontier from density
2574 → 2559 → 2528 → 2516 → **2512** in three improving 102.4M-move rounds
(1,024 lanes × 100k moves, 256 exact split escapes); a fourth identical round
was neutral.  Every intermediate and the final scheme passed independent full
tensor reconstruction.  The final rank-153 scheme has 2,323 no-CSE operations
and became the default `--seed record` profile for 6×6 before the later
cooperative-SIMDgroup improvement below.  This is cost history, not a
tensor-rank record.

The matching 5×5 validation chained density 1168 → 1160 → 1157 → **1155**
under the same 1,024-lane × 100k-move, 256-escape rounds; its fourth round was
also neutral.  Productive rounds took 3.64–3.71 seconds.  The final exact
rank-93 scheme has 1,037 no-CSE operations, remains C3-closed with three fixed
cubes, and is now both the `record` and `c3-record` default.

The cooperative SIMD-group prototype gives one complete scheme to one Apple
32-lane SIMDgroup and stripes partner, cancellation, duplicate, density, and
copy scans across the lanes.  In a fair 512M-step A/B, cooperative scan reached
351.4M steps/s on 5×5, while maintained hash chains reached 313.3M steps/s on
6×6.  Scan was 50% faster than hashing at 5×5; hashing was 9.5% faster at 6×6,
so the generator selects the lookup family by size.  The 6×6 run also improved
the exact rank-153 cost leader from density 2512 to **2508** (2,319 no-CSE
operations).  Full measurements and reproduction commands are in
[`../zoo/gpu_simdgroup_results.md`](../zoo/gpu_simdgroup_results.md).

For longer campaigns, `--gpu-policy adaptive` partitions the generated
Tungsten/Metal relay into rank, density, escape, and novelty roles.  A bounded
exact-gated Pareto archive tracks density, flip connectivity, and term-set
distance; its retained schemes force-reseed the novelty role.  UCB-style
allocation moves whole threadgroups while preserving a one-group exploration
floor for every role.  The existing single relay remains the default and the
short 3×3 A/B only established correct feedback/reallocation, not a search
speedup.

The first native campaign from a mined five-way 3×3 split was productive: a
distance-five rank-24 escape returned to 23 within one second and reached exact
density **159** in a 30-second/four-walker run (5.25B moves).  That is 127
no-CSE operations versus the previous tracked seed's density 266; it did not
find rank 22.  The analogous 4×4 primitive-five-circuit run returned to rank
47/density 450 and found no rank-46 or cost improvement; a direct 4.096B-step
cooperative-GPU pass on the d450 frontier was also neutral.  Chaining the new
3×3 seed through the cooperative GPU then reduced 159 → 144 → **139** in two
productive 4.096B-step rounds of about 9.2 seconds each; a third round was
neutral.  The final exact scheme uses 107 no-CSE operations.  None of the
12.288B chained cooperative attempts found rank 22.  Two newly mined d139
escapes (rank 26/distance 5 and rank 30/distance 9) then received another
8.192B attempts; both returned to the same rank-23/d139 frontier without 22.

The tracked 5×5/6×6 record components have now been attacked directly with
these bridges.  Unconstrained C3 walks spent 6B moves per size and returned to
93/153 but found no 92/152.  Polarization plus one ordinary C3 flip constructs
exact target-residue waypoints at ranks 95 and 155; hard fixed-count-two walks
spent another 6B moves per size and remained at those ranks.  A softer 3B-move
5×5 policy traversed every fixed count from zero through three while only
accepting exact-gated fixed-count-two improvements, but also remained at 95.
These are bounded search negatives, not lower bounds; full budgets and rollback
validation are recorded in `FINDINGS.md`.

The original escape campaign produced
`matmul_5x5_rank93_d1191_gf2.txt`, an independently exact C3 rank-93 scheme
with density 1191 and 21 shared-factor pairs.  The integrated orbit-split fleet
then produced exact non-C3 rank 93 at density **1168** and 1,050 no-CSE
operations; the later GPU portfolio reduced this to density 1155, now the
default cost leader.  It is also C3-closed, so `--seed c3-record` now selects
the same density-1155 scheme; density 1191 remains as campaign history.  None
is a tensor-rank record.

## Broader context

This sits inside a larger search effort: across a full toolkit (symmetric quotient, hybrid
basin+burst, reduction-pressure energy walk, GL(n,2) conjugated-ensemble seeding), the
compiled search **matches** the records 3×3=23, 4×4=47, 5×5=93, 6×6=153 but **breaks none** —
the 5×5→92 wall remains empirically stubborn under the tested methods (four
methods × the sampled GL-orbit basins all hit 93). A naive CUDA port on a B200
was only 1.7× the Mac fleet; throughput is not the lever. The
meta-flip is the genuine *method* direction, now built and verified — the record-chasing
itself is the campaign above.

The rigorous GF(2) interval for 3×3 is now **20 ≤ R ≤ 23**: Wang's 2026
certificate raises the lower bound from 19 to 20.  The larger square lower
bounds remain 34, 53, and 76 for 4×4, 5×5, and 6×6.  Search exhaustion or local
SAT surgery in this directory is not a global tensor-rank lower bound.

**See [`FINDINGS.md`](FINDINGS.md) for the full consolidated campaign log** — every
exhaustively-tested-negative result (don't re-try these), the GPU threadgroup-memory design
and its debugging history, the `cal2zone` band-escalation schedule, and the overnight
CPU+GPU relay run's live infrastructure (`overnight_orchestrator.py`, `bin/`, `runs/`,
`records/`).
