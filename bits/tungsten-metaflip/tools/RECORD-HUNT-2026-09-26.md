# GF(2) record hunt, 2026-09-26/27

A cold campaign outside the live fleet. Every counted tensor was expanded
against the complete matrix-multiplication tensor in Python (package gate),
and every claimed new rank also passed `tools/verify_tensor.rb`. Comparison
sources and their pitfalls are in `PUBLIC-TERNARY-GF2-SCREEN-2026-09-26.md`;
`tools/gf2_record_board.py` implements the classification. Nothing here is an
optimality or completed-novelty claim.

## Scoreboard (2026-09-27)

Shapes with a verified local witness: **1686**. Below every listed rank in any
ring (Lille digest `cd87163`, Perminov `b28490ca`, fmm-schemes `e2f5c2e`,
matmulcatalog `b944258` without commutative entries): **545**. Tied: 539.
Below every listed GF(2)-valid scheme but not a rational one: 197 (an upper
bound: the Lille digest carries no field information).

| Origin of the best witness | Below every listed rank |
|---|---:|
| July block-47 certificates (restored from `47ad44dc5^`) | 146 |
| September certificates in `tools/certificates/` | 143 |
| Closure materializations (block sums/Kronecker products of verified leaves) | 177 |
| matmulcatalog recipes replayed over GF(2), then walked | 37 |
| One-coordinate projections of July certificates | 33 |
| Directed walks from public ternary seeds and closure outputs | 7 |
| Live fleet checkpoints (7×7×7/247, 9×9×9/482) | 2 |

Closure products are mechanical consequences of already-public leaves (for
example AlphaTensor's GF(2) 4×4×4/47 times a Perminov scheme). Count them
separately from searched results. The rank-only closure over the final board
has **no** remaining lead, i.e. it converged.

## matmulcatalog derived recipes over GF(2)

373 shapes had a matmulcatalog "derived" F2-stamped recipe strictly below the
Lille and Perminov ranks and below our board. Replaying the lineage operations
(Atom, OrientAs, Recombination, SerendipitousProduct, concatenations,
projections, Kronecker) over GF(2) produced **263 exact tensors**; 22 came out
below the catalogue's own rank (for example 12×20×22: 3001 versus 3061). The
other **110 cannot reach the stamped rank over GF(2)**: each depends on a leaf
whose cheapest catalogue scheme is valid over Q/F3 but not F2 (largest
effects: 3×3×6 is 40 over Q but 42 over GF(2), 30 targets; 3×3×8 55/56, 13;
2×4×5 32/33, 11; 3×6×6 80/82, 9). The catalogue's F2 field inference
therefore over-claims for those recipes; comparisons against its F2 minima
are conservative.

Directed walks (two 40M passes, 100M continuations, then per-shape iterative
deepening until two stalled rounds) lowered 20 of the 263. Together with the
22 materialization gains, **37 shapes** are below every listed rank, e.g.
21×30×32/10795 (listed 10860), 12×20×22/3001 (3061), 10×25×29/4237 (4278),
8×14×24/1645 (1667), 8×22×32/3308 (3328), 8×16×22/1700 (1710).

matmulcatalog has no licence, so under the release rule in `THIRD_PARTY.md`
none of these tensors is bundled. They, the replay code, logs and board are
kept in the live store:
`~/.tungsten/metaflip/experiments/record-hunt-20260926/artifacts-snapshot2.tar.gz`
(SHA-256 `4ec7b6e56794e00968e0f81652839c9b23b78a655dd2ea82a6d62139b8fbd8b7`;
snapshot 1 `04fbdfd282a02e39834e21c0591a5d15b72673d58890e0aedcb3a5ad50f9ee96`).

## Finite negatives

- A 200M-move pass over all 281 Perminov seeds of rank at least 450 found no
  shape beyond the six from the 40M screen.
- 162 alternative near-best Perminov seeds (`--alternatives 2`) produced only
  ties (5×12×13/537, 9×9×11/594).
- Four 200M continuations and two-round auto-loop basis rewrites of the ten
  public-ternary records improved only 11×16×16 (1750→1748).
- The 110 above-catalogue matmulcatalog replays: five 40M drops, none below
  the listed ranks (closest 8×21×32/3223 versus Lille 3220).
- The fleet's baseline packed walker also reaches 9×9×9/482 within 90 s from
  Perminov's 486, so that basin does not favour the directed walker.

## Still open

- The 186 July certificates exist only in Git history and the local-only
  results repository; archive them before any history purge (a 10.3 MB
  staged tarball, SHA-256 `46ff91ca…`, awaits approval to upload).
- Register the July certificates and today's witnesses in the wide loop's
  price universe so September-style campaigns start from the strongest
  parents.
- Promotion into `tungsten-metaflip-results` needs the prior-art audit and
  attribution review required by its `RECORD_POLICY.md`.
