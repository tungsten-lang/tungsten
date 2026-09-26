# GF(2) screen of public ternary and integer schemes

Public ternary (ZT) and integer (Z) schemes reduce modulo two to exact GF(2)
decompositions of the same rank. Perminov's framework explores a *ternary*
flip graph, and fmm-schemes publishes ZT results, so neither search visits
states that exist only over GF(2). A cheap directed GF(2) walk from each
public scheme is therefore a direct test for GF(2)-only slack.

`tools/screen_public_ternary_gf2.py` automates it:

```sh
git clone --filter=blob:none --no-checkout \
  https://github.com/dronperminov/FastMatrixMultiplication fmm
python3 tools/screen_public_ternary_gf2.py seeds --repo fmm --out seeds \
  --url https://github.com/dronperminov/FastMatrixMultiplication [--alternatives 2]
tungsten -o wide-rect-walk --release tools/wide_rect_walk.w
python3 tools/screen_public_ternary_gf2.py walk --seeds seeds/seeds.json \
  --walker ./wide-rect-walk --out walks.jsonl --steps 40000000 --jobs 8
```

The ring comes from the file-name suffix, never the directory: a
`serendipitous_base` file can be `_Q`. Rational files are never converted and
every seed passes a full tensor expansion; the walker checks input and output
again. `spec/public_ternary_gf2_test.py` covers the public W layout (C[k][i]),
mod-2 cancellation, and ring gates. Walks are deterministic in
(seed, steps, nonce): the 10×13×14 walk replays byte-for-byte.

## Results (2026-09-26)

- Perminov `b28490ca`, best integer scheme per shape with largest side 5..16:
  629 seeds, no mod-2 cancellations. One 40M-move walk each dropped **6**
  shapes. Through rank 480 nothing dropped; every drop was at rank 486 or
  above (9×9×9, 9×10×14, 10×13×14, 10×14×16, 11×15×15, 11×16×16).
- fmm-schemes `e2f5c2e` (17 ZT records published 2026-09-24): two 100M walks
  each dropped **7** of 17: 11×13×15 1364→1363, 13×14×16 1811→1807,
  8×11×16 909→906, 9×14×16 1269→1267, 9×11×13 840→839, 11×15×16 1647→1645,
  11×16×16 1749→1748.
- Four 200M continuations of each first-round drop mostly tied; 11×16×16
  improved 1750→1748. Two-round auto-loop basis rewrites of 10×13×14/r1150
  tied in their first walks.

Ten retained shapes, with comparisons and replay, are in
`certificates/public-ternary-gf2-walks-20260926/`. Three are below every
listed rank in any ring: **9×9×9/482, 10×13×14/1150, 11×13×15/1363**. Seven
are below every listed GF(2)-valid scheme while a rational scheme with even
denominators is lower. These are apparent upper bounds under
`RECORD_POLICY.md`, not optimality or completed-novelty claims.

## Comparator pitfalls found

- **Integer schemes count.** 11×15×16/r1645 beats fmm-schemes' ZT 1647 but not
  Perminov's Z 1629; 10×14×16/r1417 beats Perminov's ZT 1418 but not
  fmm-schemes' ZT 1416. Compare against every ZT/Z source, not one tracker.
- **Check denominators, not folder names.** Every rational scheme below a
  retained rank was downloaded and checked: all use 1/2, 1/4 or 1/8.
- **Exclude commutative algorithms.** matmulcatalog lists 9×9×9 at 473 from
  Waksman (1970), flagged `commutative`; it is not a bilinear tensor
  decomposition and does not bound GF(2) tensor rank.
- **GF(2)-specific public results look like leads.** 4×4×4/47 (AlphaTensor),
  4×4×5/60 (Kauers–Moosbauer), 8×8×8/329 and 16×16×16/2209 are below the Lille
  digest but listed by matmulcatalog as F2 schemes.

`tools/gf2_record_board.py` classifies every verified local witness against
the Lille digest, matmulcatalog (non-commutative, F2 vs any field),
FastMatrixMultiplication rings, and extra FMM-format repositories.

## Price-universe gap: the July block-47 corpus

The 186 exact July block-47 certificates listed in
`benchmarks/matmul/metaflip/block_composition_records.tsv` were removed from
the tree in `47ad44dc5` (repository size) and are not in the
`metaflip-archives` release catalogue. They survive in Git history
(`git show 47ad44dc5^:benchmarks/matmul/metaflip/<file>`) and in the
local-only results corpus. The wide auto loop prices only checked-in
certificates, packaged seeds and `archived-exact-prices.json`, so it never
sees them: several September leads are dominated by July results (for
example 15×17×19, September r2963 against the July certificate r2862; a
20M directed walk lowers that certificate to r2860). 160 of the 186 remain
below the 2026-09-25 Lille digest. Archive them before any history purge and
register them as a priced source.
