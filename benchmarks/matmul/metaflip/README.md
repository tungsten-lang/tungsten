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

## The construction

The base flip graph searches one fixed format (n,m,p). The **meta** flip graph glues all
per-format graphs together with two cross-format edges:
- **extension** (n,m,p)→(n,m,p+1): re-index the v/w masks one column wider, append the n·m
  naive terms that compute the new output column. Rank jumps by n·m.
- **projection** (n,m,p)→(n,m,p−1): zero the last B-column, drop the last C-column, prune
  vanished terms. Rank drops.

A search can then route *through a neighboring format* to reach reductions the current
format's flip-graph component does not contain.

## Build status — all four phases validated in compiled Tungsten

1. ✅ Rectangular (n,m,p) walk + 3-dimension verify
2. ✅ Cross-format edges — round-tripped (5,5,5)↔(5,5,6)↔(5,5,7), tensor-valid at every step
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

1. Add the **symmetric per-format layer** (C₃ for n=5, C₃×ℤ₂ for n=6 — note: the cyclic
   action is pure rotation `(i,j,k)→(j,k,i)`, **no transpose**; transpose only via the
   reversal generator, which has characteristic-2 connectivity caveats).
2. Target **rectangular** formats; validate by reproducing a known improvement ((4,5,6)=90).
3. Per-format budget ≈ 100000·n·m·p moves (millions), across a fleet.

## Broader context

This sits inside a larger search effort: across a full toolkit (symmetric quotient, hybrid
basin+burst, reduction-pressure energy walk, GL(n,2) conjugated-ensemble seeding), the
compiled search **matches** the records 3×3=23, 4×4=47, 5×5=93, 6×6=153 but **breaks none** —
the 5×5→92 wall is structural (four methods × the full GL-orbit of basins all hit 93). A
naive CUDA port on a B200 was only 1.7× the Mac fleet; throughput is not the lever. The
meta-flip is the genuine *method* direction, now built and verified — the record-chasing
itself is the campaign above.

**See [`FINDINGS.md`](FINDINGS.md) for the full consolidated campaign log** — every
exhaustively-tested-negative result (don't re-try these), the GPU threadgroup-memory design
and its debugging history, the `cal2zone` band-escalation schedule, and the overnight
CPU+GPU relay run's live infrastructure (`overnight_orchestrator.py`, `bin/`, `runs/`,
`records/`).
