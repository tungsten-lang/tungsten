# GF(2) reductions of public integer-coefficient schemes

Each lineage starts from a public ternary (ZT) or integer (Z) scheme, reduces
it modulo two, and applies finite directed GF(2) walks
(`tools/wide_rect_walk.w`, deterministic in seed/steps/nonce). Ternary
schemes are valid over every ring, so their authors' flip graphs never visit
GF(2)-only states; a GF(2) walk can. `tools/screen_public_ternary_gf2.py`
generated the seeds and walks; see `../../PUBLIC-TERNARY-GF2-SCREEN-2026-09-26.md`.

Run `python3 verify.py` to check every SHA-256, rank, and complete GF(2)
tensor in Python and Ruby, and the lineage. `--replay-walk BINARY` reruns every
walk and requires byte-identical output; `--source perminov=CLONE --source
merlijn=CLONE` re-derives each public seed from the pinned upstream file.

| Shape | GF(2) rank | Public GF(2)-valid best | Lower public rank (ring) | Seed |
|---|---:|---:|---|---|
| 9×9×9 | **482** | 486 (Perminov ZT) | none | Perminov 486 |
| 10×13×14 | **1150** | 1152 (Perminov ZT/Z/Q, Lille digest) | none | Perminov 1152 |
| 11×13×15 | **1363** | 1364 (fmm-schemes ZT, 2026-09-24) | none | fmm-schemes 1364 |
| 8×11×16 | **906** | 909 (fmm-schemes ZT) | 904 (Q; 1/2, 1/4, 1/8) | fmm-schemes 909 |
| 9×11×13 | **839** | 840 (fmm-schemes ZT) | 835 (Q; 1/2, 1/8) | fmm-schemes 840 |
| 11×15×15 | **1547** | 1548 (Perminov ZT) | 1540 (Q; 1/8) | Perminov 1548 |
| 9×10×14 | **819** | 820 (Perminov Z) | 808 (Q; 1/4, 1/8) | Perminov 820 |
| 13×14×16 | **1807** | 1811 (fmm-schemes ZT) | 1796–1806 (Q; 1/2, 1/4) | fmm-schemes 1811 |
| 9×14×16 | **1267** | 1269 (fmm-schemes ZT) | 1254 (Q; 1/2) | fmm-schemes 1269 |
| 11×16×16 | **1748** | 1749 (fmm-schemes ZT) | 1724 (Q; 1/2, 1/4, 1/8) | Perminov 1752 |

Comparisons were checked on 2026-09-26 against Perminov's
[FastMatrixMultiplication](https://github.com/dronperminov/FastMatrixMultiplication)
(`b28490ca`), [fmm-schemes](https://github.com/MerlijnW70/fmm-schemes)
(`e2f5c2e`), the [Lille catalogue](https://fmm.univ-lille.fr/) digest
(`sedoglavic/fmm_digest` `cd87163`), and
[matmulcatalog](https://github.com/solven-eu/matmulcatalog) (`b944258`,
commutative entries excluded; its 9×9×9 rank 473 is Waksman's commutative
algorithm, not a bilinear decomposition). "Lower public rank" lists schemes
whose coefficients have even denominators, so they do not reduce to GF(2).

The first three ranks are below every rank listed in those sources for any
ring; the other seven are below every listed GF(2)-valid scheme. The 9×9×9
rank was first reached by the live fleet on 2026-09-12 (local checkpoint,
unpublished); this bundle gives it a replayable public-seed lineage. Under
`RECORD_POLICY.md` these are **apparent** GF(2) upper bounds pending a
complete prior-art audit, not optimality claims. Two further walks were not
retained: 10×14×16/r1417 is above fmm-schemes' ZT 1416, and 11×15×16/r1645 is
above Perminov's Z 1629.

Seeds are derived from third-party schemes: Perminov's under the MIT licence
("Andrew I. Perminov and cited algorithm authors") and fmm-schemes' under
CC BY 4.0 (MerlijnW70). The walks transform those tensors; attribution for
the starting schemes stays with their authors.
