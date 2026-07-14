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
| `flipfleet_native.w` | authoritative pure-Tungsten 3×3–7×7 and rectangular-profile CPU/GPU fleet; square and rectangular campaigns share the native TUI |
| `flipfleet_rect_campaign.w` | first-class sticky-island coordinator for the nine allowlisted rectangular `--tensor` profiles from `3x3x4` through CPU-only `4x5x7` |
| `metaflip_worker.w` | runtime-generic exact CPU worker used in-process by the native fleet |
| `flipfleet_escape.w` | exact generic/fixed/C3/composed escape identities over shared i64 buffers |
| `flipfleet_bank_policy.w` | native structural shoulder banks, least-used replay/success attribution, and nondominated archive policy |
| `flipfleet_gpu_bundle.w` / `gpu_bundle/` | checked-in generic adaptive GPU workers |
| `flipfleet_c3_bundle.w` / `c3_bundle/` | checked-in C3-preserving GPU workers |
| `flipfleet_simd_bundle.w` / `simd_bundle/` | checked-in cooperative SIMD-group workers |
| `flipfleet_mitm_lane.w` | bounded pure-Tungsten/Metal 5→4 surgery engine |
| `flipfleet_constraint_pool.w` / `flipfleet_kxor_pool.w` / `flipfleet_differential_pool.w` | projected-defect/proof scouts, exact 6→5 through 9→8 joins, live circuits, and one-child parent differential |
| `flipfleet_archive_nullspace.w` / `flipfleet_partial_automorphism.w` | exact archive-difference nullspace hybrids and bounded swap/GL-shear automorphism splices |
| `flipfleet_span_refactor.w` / `flipfleet_span_refactor_pool.w` | complete exact 3/4-term factor-span refactors with 27/64-bit Metal joins and full-tensor admission |
| `flipfleet_low_rank_shear_search.w` / `flipfleet_low_rank_shear_pool.w` | exact q=2 rank-1/rank-2 correction absorption, with regular Metal tuple enumeration and full host admission |
| `flipfleet_kernel_pool.w` / `flipfleet_map_elites.w` / `flipfleet_rank_debt.w` | pool rotation, contextual scheduling, MAP-Elites, and return-hazard policy |
| `flipfleet_persistent_gpu.w` / `flipfleet_metallib_cache.w` | persistent generic/rectangular GPU command loop and offline Metal-library cache |
| `flipfleet_basin_identity.w` / `flipfleet_lineage.w` | symmetry-canonical basin telemetry and delayed GPU→CPU descendant rewards |
| `flipfleet_cpu_experiments.w` | one-island online parameter racer; the worker also exposes the one-island accepted-state cycle watch |
| `flipfleet_d3.w` / `d3_bundle/` | standalone bounded 6×6 C3×Z2 experiment, retained off the default schedule |
| `flipfleet_profiles.w` / `flipfleet_gpu_policy.w` | native tensor-specific CPU doors, zones, GPU weights, and adaptation |
| `flipfleet_sedoglavic.w` | pure-Tungsten rectangular-leaf composer with exhaustive input/output gates |
| `flipfleet_block_composer.w` / `flipfleet_block_compose.w` | pure-Tungsten wide-factor support-aware composer and all-S3 CLI |
| `flipfleet_block_formula_scan.w` / `flipfleet_block_formula_scan_wide.w` / `flipfleet_block_formula_scan_cross.w` / `flipfleet_block_variant_scan.w` | reproducible legacy, continuous 12--32, cross-band, exact-tie, and same-rank-leaf scans |
| `catalog_gf2_import.py` | offline dense-catalog importer with W-order correction and independent GF(2) reconstruction |
| `block_composition_cross_audit.tsv` / `block_composition_cross_audit_sources.tsv` | persisted 20/21 seam comparison and pinned source revisions/digest |
| `block_composition_smallblock_audit.tsv` / `block_composition_smallblock_audit_sources.tsv` | bounded size-1/2/9 frontier audit, field-aware comparisons, and pinned leaf hashes |
| `verify_block_composition_records.py` / `block_composition_independent_audit.tsv` | independent sparse-parity reconstruction of every manifest certificate |
| `BLOCK_COMPOSITION.md` / `BLOCK_COMPOSITION_RECORDS.md` | composer design, reproducible commands, hashes, and dated apparent-record comparisons |
| `FLIPFLEET_MOVE_LAB.md` | exact span/shear identities, measured evidence, and the prioritized next move families |
| `flipfleet_tui.w` | native single-screen campaign dashboard helpers |
| `flipfleet.py` | historical Python coordinator retained for experiment replay, not new campaigns |
| `sym_start.py`       | exact diagonal-partition starts for target-aligned symmetric search |
| `sym_escape.py`      | standalone generic/C3 split and polarization escape identities |
| `escape_portfolio.py` | exact mixed-family/depth-two escape banks with independent verification |
| `hybrid_escape.py` | staged C3 Tungsten walk → exact symmetry break → ordinary Tungsten/Metal walk |
| `identity_miner.py` | tensor-signature miner for 3-, 4-, and primitive 5-term zero circuits |
| `mitm_surgery.py` | exact-gated restricted k→k−1 local surgery by XOR meet-in-the-middle |
| `gpu_mitm_surgery.py` / `gpu_mitm_worker.w` | historical Python-adapted Metal surgery experiment |
| `simdgroup_relay.py` | development adapter used before the checked-in native SIMD bundle |
| `c3_gpu_relay.py` / `c3_gpu_worker_gen.py` | development adapter/generator for the checked-in C3 bundle |
| `tensor_profiles.py` | Python reference mirror of the tensor-profile evidence |
| `../flipgraph_gpu_cal2zone.w` | Tungsten/Metal cal2zone walker with exact split-escape portfolios |
| `../flipgraph_gpu_simdgroup.w` | cooperative one-scheme-per-SIMDgroup Tungsten/Metal walker |
| `../zoo/gpu_cal2zone_gen.py` | dimension/mask-width specializer, including raw-i64-safe 6×6/7×7 kernels |
| `matmul_3x3_rank23_d139_gf2.txt` | exact rank-23, density-139 cooperative-GPU cost leader |
| `matmul_3x3_rank23_d159_gf2.txt` | mined-escape intermediate that opened the new 3×3 basin |
| `matmul_4x4_rank47_d450_gf2.txt` | exact rank-47, density-450 default 4×4 frontier seed |
| `matmul_4x4_rank47_d677_flips_gf2.txt` | independent exact rank-47 Kauers–Moosbauer/Flips orbit retained for 4×4 basin diversity |
| `matmul_5x5_rank93_d1155_gf2.txt` | exact rank-93, density-1155 GPU escape-portfolio cost leader |
| `matmul_5x5_rank93_d1168_gf2.txt` | prior exact rank-93 cost leader from the CPU escape campaign |
| `matmul_5x5_rank93_d1191_gf2.txt` | prior exact C3 rank-93 symmetry-escape seed |
| `matmul_6x6_rank153_d2502_gf2.txt` | exact C3 rank-153, density-2502 current cost leader from the native mixed CPU fleet |
| `matmul_6x6_rank153_d2508_gf2.txt` | prior cooperative-SIMD density leader, retained for attribution and replay |
| `matmul_3x3x4_rank29_gf2.txt` / `matmul_3x4x4_rank38_gf2.txt` | exact rectangular leaves used by the 7×7 subfleets and composer |
| `matmul_3x3x5_rank36_d287_gf2.txt` / `matmul_3x3x5_rank36_d304_gf2.txt` / `matmul_3x4x5_rank47_d386_gf2.txt` / `matmul_3x5x5_rank58_d518_gf2.txt` | exact composition leaves and rectangular-campaign density leaders; d287 is the current 3x3x5 default and d304 is retained provenance |
| `matmul_4x4x5_rank60_gf2.txt` / `matmul_4x4x5_rank60_d919_gf2.txt` | imported exact rank-60 rectangular record and its native-GPU density-919 campaign descendant |
| `matmul_4x5x5_rank76_gf2.txt` / `matmul_4x4x6_rank73_gf2.txt` / `matmul_4x5x7_rank104_catalog_gf2.txt` / `matmul_4x5x7_rank104_d1160_gf2.txt` | exact CPU-ready rectangular composition/product leaves; d1160 is the rank-104 4x5x7 campaign default |
| `matmul_7x7_rank248_d2952_sedoglavic_gf2.txt` | exact rank-248 default, the lowest-density saved block placement |
| `matmul_7x7_rank248_d2958_sedoglavic_gf2.txt` | canonical reproducible rank-248 block placement |
| `matmul_7x7_rank248_d3015_connectivity_sedoglavic_gf2.txt` | distinct rank-248 placement selected for additional cross-seam shared factors |

Rectangular CPU/GPU run commands, exact targets, and upstream licensing are in
[`RECTANGULAR_CAMPAIGNS.md`](RECTANGULAR_CAMPAIGNS.md).

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

## Authoritative square campaign driver

`flipfleet.w` is the thin public entry point for `flipfleet_native.w`, the
campaign implementation.  The coordinator, CPU
walkers, exact escape construction, adaptive policy, candidate adoption,
durable checkpointing, and dashboard are all Tungsten.  GPU runtime inputs are
checked-in dimension-specialized Tungsten/Metal assets; no Python process or
source generator participates in a campaign.

Build once from any directory in the checkout:

```sh
ROOT="$(git rev-parse --show-toplevel)"
TUNGSTEN_LL_PATH=/tmp/flipfleet-native.ll \
  "$ROOT/bin/tungsten" compile --release --lto \
  -o /tmp/flipfleet-native \
  "$ROOT/benchmarks/matmul/metaflip/flipfleet.w"
```

At runtime the fleet walks upward from the current directory to locate the
checkout, so its default exact seeds and GPU worker compiler do not depend on
where inside the repository it was launched.  When launching from outside the
checkout, pass `--repo-root /path/to/tungsten`.

Select the square format with `--tensor 3x3` through `--tensor 7x7`.  Every
size loads its tracked exact rank/density leader.  The current 6×6 default is
rank 153 at density **2502** (2,313 no-CSE operations); it independently
reconstructs the complete tensor and is C3-closed.  The earlier density-2508
file remains the attributed cooperative-SIMD milestone.  The 7×7 default is
the exhaustively verified rank-248, density-2952 Sedoglavic/Strassen-pad
composition. Its independently searched 3×3×4 and 3×4×4 leaves also run as
dedicated rectangular subfleets and recompose immediately after an improvement.
The signed-i64 factor ABI makes 7×7 the current maximum square size.

The GPU is on by default and the policy is adaptive.  `--no-gpu` is the
CPU-only control; `--rebuild-gpu` forces recompilation of the checked-in
workers.  Cached workers and their offline-compiled metallibs are rebuilt
automatically when their Tungsten source or Metal sidecar is newer.  With the
default one-round epochs, stable generic and rectangular roles retain their
Metal process/pipeline through a command mailbox; rotating roles still use
bounded children but load the same cache.  The native TUI is on by default.  Use
`--no-tui` for ordinary progress output or `--quiet` for an unattended run.  `--status PATH` and
`--best PATH` select the durable key/value heartbeat and exact best-scheme
checkpoint.

By default the status path is unique to the run, while the exact best path is
stable per tensor (`flipfleet_NxN_best.txt`) so a later campaign can recover
the frontier.  `--run-tag TAG` controls the per-run scratch/status namespace.
Certificate and heartbeat updates use temp-file plus atomic rename; malformed
existing best checkpoints are never silently overwritten.

```sh
# Default: sticky mixed CPU islands, adaptive GPU portfolio, native TUI.
/tmp/flipfleet-native --tensor 3x3 --secs 60

# Current 6×6 cost frontier; GPU is already enabled.
/tmp/flipfleet-native --tensor 6x6 --secs 3600

# CPU-only control with the same native sticky doors and exact escape banks.
/tmp/flipfleet-native --tensor 6x6 --no-gpu --secs 3600

# Default exact 7×7 rank-248 seed, direct plus rectangular GPU lanes.
/tmp/flipfleet-native --tensor 7x7 --secs 3600

# First-class 4×4×5 campaign: sticky CPU islands plus its specialized GPU.
/tmp/flipfleet-native --tensor 4x4x5 --secs 3600

# Additional exact block-composition leaves, each with CPU and Metal lanes.
/tmp/flipfleet-native --tensor 3x3x5 --secs 3600
/tmp/flipfleet-native --tensor 3x4x5 --secs 3600
/tmp/flipfleet-native --tensor 3x5x5 --secs 3600

# These larger rectangular leaves currently have CPU islands only. Requesting
# the default GPU reports that capability and continues without DEGRADED.
/tmp/flipfleet-native --tensor 4x5x5 --secs 3600
/tmp/flipfleet-native --tensor 4x4x6 --secs 3600
/tmp/flipfleet-native --tensor 4x5x7 --no-gpu --secs 3600
```

Rectangular dispatch deliberately does not borrow lanes from a 7×7 run:
`4x4x5`, `4x5x5`, `4x4x6`, and `4x5x7` cannot improve the 7×7 block formula. Run them
as their own `--tensor` campaigns, then feed their durable
`flipfleet_NxMxP_best.txt` checkpoints to the wide block composer. Rectangular
campaigns emit `RECT_CAPABILITY`, `RECT_STATUS`, and `RECT_RESULT` lines plus
an atomic schema-1 status file; the square TUI is unchanged.

When `-J`/`--walkers` is omitted, FlipFleet detects active host CPUs and uses
`max(1, CPUs-4)` walkers for both GPU and CPU-only campaigns, reserving four
threads for coordination and child-host work. On the 18-core M5 Max the
default is 14. An explicit `-J` always wins.

Every candidate that can affect the fleet passes exhaustive coefficient
reconstruction.  The rank-then-density leader is monotonic and separate from
the bounded max-min archive.  Invalid CPU or GPU candidates are quarantined;
GPU hosts exact-gate before writing and the coordinator gates again before
adoption.

CPU threads deliberately knock on different doors instead of all following
one leader. Tensor-specific sticky assignments cover leader exploitation,
max-min frontier replay across every checked-in exact same-rank scheme, exact
best+1 and best+2 shoulders, C3-preserving
seeds, mixed algebraic escapes, and the original anchor.  Each thread also
keeps one of four work/wander zones, so remote-basin turnover and deep probes
coexist:

| tensor | short | balanced | high-band | marathon |
|---|---:|---:|---:|---:|
| 3x3 | `25m / 6.25m` | `125m / 25m` | `625m / 125m` | `2.5b / 250m` |
| 4x4 | `50m / 12.5m` | `250m / 50m` | `1.25b / 250m` | `5b / 500m` |
| 5x5, 6x6 | `100m / 25m` | `500m / 100m` | `2.5b / 500m` | `10b / 1b` |
| 7x7 | `200m / 50m` | `1b / 200m` | `5b / 1b` | `20b / 2b` |

The values are `work / wander` moves and are evidence-guided starting points,
not claimed optima. The base mixed door pattern has twelve positions and is
fully represented whenever the detected `CPUs-4` default is at least twelve;
additional walkers continue the tensor-specific pattern. `--cpu-work-moves` and `--cpu-wander-moves`
accept four comma-separated move counts (including `k`, `m`, and `b`
suffixes).  `--migrate` controls how many leader/frontier islands follow a
strict rank drop; it defaults to one rather than collapsing the fleet.

One island is the frozen-core/fringe control.  Its constrained partner search
is about five times slower than an ordinary 5×5 flip, so it uses an adaptive
time-balanced step quota rather than forcing every island to wait for the same
move count.  CPU row rates use each thread's own elapsed time.  On the current
18-core development machine this changed the 12-island 5×5 throughput from
about 139M to 532M moves/s while retaining the control lane.

The best+1 and best+2 banks are not FIFO lists.  Admission is capped per
label-independent factor-reuse signature, then favors term-set separation;
restarts select the least-used slots and attribute successful returns to the
source slot.  `--cpu-near-size`, `--cpu-near-signature-quota`,
`--cpu-symmetry-seeds`, and `--archive-size` expose their bounded capacities.
The C3 branch has an independent leader, so a denser C3 waypoint can continue
walking and later feed orbit, polarization, or symmetry-breaking stages even
when it is not the ordinary fleet best.

The TUI shows the honest best-known-construction-UB/baseline objective, every
CPU island's sticky door and zone, adaptive GPU lane/reward/failure telemetry, exact archive and
shoulder health, exposure-normalized CPU cohort yield, and a wall-time rank
timeline.  Its health line exposes degraded GPU coverage rather than hiding a
missing engine.

Pressing space starts a fresh naive frontier: it replaces the in-memory and
durable fleet best, resets the rank/density history and wall-time rank timeline,
rebuilds best-relative banks, and discards results from GPU launches belonging
to the previous frontier generation.  `w` remains the explicit record-anchor
reseed and does not clear the current fleet best.

The continuously active native GPU engines are generic cal2zone rank, density,
split, and novelty roles, the separate exact+C3-preserving engine, and the
cooperative SIMD-group engine.  The rotating GPU kernel pool contains
projected R−1 search, exact 5→4 through 9→8 joins, live primitive 5+
zero-circuit mining, complete exact three/four-term factor-span refactors, one
distant-parent differential child, lifted identities, contraction
lower-bound scouting, XOR-SAT cube search, fixed-cube break, orbit split,
polarization, and two-identity composition.  Up to three independent pool
workers run concurrently: one constraint/lower-bound kernel, one exact-surgery
kernel, and one algebraic escape/walk kernel.  The TUI highlights every live
child while retaining one aggregate pool telemetry row.  Faster family slots
refill independently; after the dedicated GPU roles drain they keep working
until the pool's barrier-anchor launches finish, then all children meet at the
clean adaptive-reallocation barrier.  Each engine runs finite
epochs and returns through the same native reward/reallocation path.  A build
or launch failure is visible as degraded coverage without hiding sibling pool workers;
bounded exponential retry can restore the role at a later epoch instead of
permanently deleting one transiently failed approach.

The adaptive score uses measured worker wall time in 32-lane/100 ms exposure
quanta, rather than treating unequal generic, C3, SIMD, and pool launches as
equivalent epochs.  C3 walking, orbit split, and polarization have distinct
exact seed banks and fail closed if the required C3 component is unavailable.

`--secs` is a soft CPU scheduling horizon: after it expires the coordinator
still joins the current finite GPU epochs and exact-gates their last results.
Hard process-group cancellation awaits a native asynchronous-process API; keep
`--gpu-steps` and `--gpu-epoch-rounds` bounded for short interactive runs.

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

The same identities run directly inside `flipfleet_native.w` through
`flipfleet_escape.w`.  At startup and after a new strict frontier, the native
coordinator constructs exact generic splits, fixed-cube breaks, C3 orbit
splits, polarizations, and two-split compositions in shared `i64[]` buffers.
Collision cancellation is part of the move, so the actual rank delta is used.

Mixed CPU doors rotate this variable-rank bank while leader, frontier,
best+1/best+2, symmetry, and anchor doors retain independent sources.  C3
escapes must also pass closure verification before entering the symmetry bank.
Every seed passes exhaustive tensor reconstruction before launch, and every
returned candidate passes the coordinator gate again.  Higher-rank escape
states never masquerade as a new fleet best.

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

### Heterogeneous adaptive GPU fleet

The GPU is enabled by default and adaptive scheduling is the native policy.
It divides 32-lane quanta across six continuously active roles—rank-first
high-band walking, same-rank density grinding, true C3-preserving walking,
generic split, archive novelty, and cooperative SIMD-group walking—plus the
rotating kernel pool.  After each bounded epoch, exposure-normalized reward
moves the non-pool quanta toward useful exact candidates.

The split lane retains the wide internal +1 portfolio (`tid % N`).  Break,
orbit, polarization, and composition now rotate inside the pool rather than
holding four permanent diversity floors.  The C3 role mutates complete cyclic
orbits on every Metal step and maintains its own rank-then-density branch
leader, even when that leader is denser than the ordinary fleet best.  The
rank, density, and SIMD roles continue to attack the fleet-wide best.
Returned candidates pass the normal independent full-tensor gate; C3 outputs
also pass a separate closure gate.

The novelty role is seeded from a true bounded nondominated archive rather
than the rank/density leader list.  It retains the lowest returned frontier
rank, then trades off density, flip-pair connectivity, and minimum term-set
distance from the retained set.
Whole-role success is still judged by exact returned candidates, so adaptive
allocation can shift GPU width without merging these distinct seed sources.
`--gpu-novelty-size` controls the archive bound.

The continuous-role relative weights, in role order
`rank/density/C3/split/break/orbit/polarize/compose/novelty/SIMD/pool`, are:

| tensor | relative weights | evidence basis |
|---|---|---|
| 3×3 | `18/15/0/12/0/0/0/0/10/25/5` | mined escape plus cooperative SIMD produced d139 |
| 4×4 | `20/5/0/15/0/0/0/0/15/10/15` | record is isolated; direct SIMD/small surgery were neutral |
| 5×5 | `15/15/12/6/0/0/0/0/7/15/4` | C3/density productive; scan SIMD measured fastest |
| 6×6 | `16/16/6/7/0/0/0/0/8/16/4` | hash SIMD produced d2508; native mixed CPU then produced d2502 |
| 7×7 | `18/10/10/8/0/0/0/0/8/12/4` | diverse extrapolation from the exact naive baseline |

The pool selects one ready kernel per constraint/proof, exact-surgery, and
algebraic-escape family, then fairly water-fills three eighths of configured
lanes up to 1536.  Host-heavy 5→4 MITM is capped at 512, the bounded small XOR
joins and primitive miner at 256, and 8→7/9→8 at 128.  Exact archive-nullspace
crossover (with primitive-five fallback) is a single CPU child capped at one logical quantum;
span-3 is capped at 256 while span-4 charges 128 but runs one memory-bounded
complete neighborhood;
low-rank shear is enabled for 5×5–7×7 at 256/128 logical lanes, based on a
real 5×5 non-one-flip exact hit at source pair 504;
the unused quanta return to the six stable roles for those epochs.  Pool details,
exact-admission rules, and planted smokes are in
[`GPU_KERNEL_POOL.md`](GPU_KERNEL_POOL.md).

The algebra, measured triangle-shear edge, and next move families are tracked
separately in [`FLIPFLEET_MOVE_LAB.md`](FLIPFLEET_MOVE_LAB.md).

The July 13 search-control pass also added symmetry-canonical basin IDs,
GPU→CPU delayed lineage rewards, a one-island CPU parameter racer, and a
separate one-island accepted-state cycle watch.  A bounded 6×6 C3×Z2 worker
was measured but deliberately left out of the default and rotating pool: it
ran at about 59% of C3 throughput and found neither rank 152 nor a density
improvement.  Implementation details, measurements, and the boundary between
live evidence and planted validation are consolidated in
[`FLIPFLEET_SEARCH_EXPERIMENTS.md`](FLIPFLEET_SEARCH_EXPERIMENTS.md).

```sh
# Defaults: mixed CPU starts + adaptive heterogeneous GPU.
/tmp/flipfleet-native --tensor 5x5

# Override CPU/GPU breadth and epoch size; 6×6 uses native-i64 Metal factors.
/tmp/flipfleet-native --tensor 6x6 --walkers 12 \
  --gpu-walkers 8192 --gpu-steps 50000 --gpu-epoch-rounds 2

# CPU-only comparison.
/tmp/flipfleet-native --tensor 5x5 --no-gpu
```

The CPU rank column is `rCURRENT/rBEST` (`r95/r93` means a walker whose live
excursion is rank 95 and whose lifetime island best is rank 93, even across
seed rotations). `#NNNNN` is an
order-independent digest of the live term set, and `dN` is its raw term-set
distance from the fleet leader. The Diversity
section reports active unique term sets, minimum pair distance, leader clones,
and mean leader distance, so equal `r93` labels no longer imply or conceal
basin convergence.

`--gpu-walkers`, `--gpu-steps`, and `--gpu-epoch-rounds` control native breadth
and epoch length.  Checked-in specializations use i32 masks through 5×5 and
i64 at 6×6/7×7, with legal threadgroup geometries.  The 7×7 hosts use raw typed
buffer views so bit-48 masks never cross a boxed-integer narrowing path.

This also fixes an old 5×5 bias: plus moves used `% 65535`, sampling only 16
of the 25 factor bits.  They now sample the full `2^25-1` mask range.  The
portfolio selection happens only at reseed and adds no per-move branching.
SAT remains a CPU-side proof/search tool here: the existing 4×4 surgery model
cannot solve even its known rank-47 SAT control quickly, so moving that model
to the GPU is currently a larger solver project with a worse evidence base
than spending GPU width on independent exact basins.

The campaign runtime does not invoke the historical Python coordinator,
identity miner, relay generators, or SAT prototypes.  The identity miner and
SAT scripts remain offline research tools: useful identities are admitted as
exact schemes, while regular partial-tensor enumeration used during a live
campaign is the checked-in pure-Tungsten/Metal rotating pool.  Thus “pure
Tungsten” describes the complete FlipFleet campaign path, not a claim that
every exploratory analysis script in this directory has been rewritten.

The first on-device M5 Max validation chained the 6×6 frontier from density
2574 → 2559 → 2528 → 2516 → **2512** in three improving 102.4M-move rounds
(1,024 lanes × 100k moves, 256 exact split escapes); a fourth identical round
was neutral.  Every intermediate and the final scheme passed independent full
tensor reconstruction.  The final rank-153 scheme has 2,323 no-CSE operations
and became the tracked 6×6 density leader before the later cooperative-SIMD
and native mixed-CPU improvements below.  This is cost history, not a
tensor-rank record.

The matching 5×5 validation chained density 1168 → 1160 → 1157 → **1155**
under the same 1,024-lane × 100k-move, 256-escape rounds; its fourth round was
also neutral.  Productive rounds took 3.64–3.71 seconds.  The final exact
rank-93 scheme has 1,037 no-CSE operations, remains C3-closed with three fixed
cubes, and is the native ordinary/C3 default.

The cooperative SIMD-group prototype gives one complete scheme to one Apple
32-lane SIMDgroup and stripes partner, cancellation, duplicate, density, and
copy scans across the lanes.  In a fair 512M-step A/B, cooperative scan reached
351.4M steps/s on 5×5, while maintained hash chains reached 313.3M steps/s on
6×6.  Scan was 50% faster than hashing at 5×5; hashing was 9.5% faster at 6×6,
so the checked-in bundle selects the lookup family by size.  The 6×6 run also
improved the then-current rank-153 cost leader from density 2512 to **2508**
(2,319 no-CSE operations).  Full measurements and reproduction commands are in
[`../zoo/gpu_simdgroup_results.md`](../zoo/gpu_simdgroup_results.md).

The subsequent pure-Tungsten mixed CPU fleet reduced that same rank-153
frontier to density **2502**, or **2,313 no-CSE operations**.  Independent full
tensor reconstruction accepted the file; it is duplicate-free, C3-closed with
three fixed cubes, and has SHA-256
`df2750d583ce256321ad59a799171497d3b734fd5db7cc4190b852630c2a03d1`.
`matmul_6x6_rank153_d2502_gf2.txt` is now the cost/default leader.  The d2508
asset remains tracked as the cooperative-SIMD milestone.  Neither result
changes the rank-153 upper bound.

The adaptive policy is now the default.  Its expanded role set incorporates
the later measured results rather than treating C3 as universally best.  C3
gets no default share on the asymmetric 3×3/4×4 record seeds, a material but
minority share on 5×5, a smaller share on 6×6 after neutral bounded C3 probes,
and a conservative exploratory share for the naive 7×7 baseline.  Cooperative
SIMD gets the largest specialized share on 3×3 and remains substantial on
5×5/6×6 because it produced d139 and the historical d2508 milestone.  The
later d2502 successor is evidence that independent mixed CPU doors still add
basin diversity.  The isolated
4×4 frontier emphasizes deeper compositions, novelty, and MITM.  These are
starting fractions, not frozen conclusions: live exact-candidate rewards
adjust them.

The checked-in pure-Tungsten MITM engine searches bounded 5→4 replacements.
Metal enumerates pair sums and probes complementary halves; fingerprint hits
and complete spliced schemes are exhaustively verified.  Its planted 3×3
smoke succeeds, and the native coordinator advances its subset offset across
finite adaptive epochs.  See
[`FLIPFLEET_MITM_NATIVE.md`](FLIPFLEET_MITM_NATIVE.md).

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
default cost leader.  It is also C3-closed, so the native ordinary and C3
profiles use the same density-1155 scheme; density 1191 remains as campaign
history.  None is a tensor-rank record.

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
