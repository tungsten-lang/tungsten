# 08 — Re-score against the latest public tables, and a dated prior-art check

Run on **2026-09-29** (all times UTC). Upstream clones made at 21:33:36Z; the four remote heads were re-checked at
23:47:56Z and had not moved. The papers were fetched between 21:40:04Z and 23:47:15Z (`W/upstream-latest/arxiv/manifest.json`).
The web searches were run on the same evening.
`W` = `/Users/erik/.tungsten/metaflip/experiments/record-hunt-20260926/work`.

Every number below is printed by one of the scripts saved next to this file:

| script | what it does |
|---|---|
| `08-rescore-latest.py` | Part A: imports `gf2_record_board.public_tables`, reproduces the pinned comparators, re-scores against the latest heads, and writes `W/paper-data/rescore_latest.tsv` |
| `08-fetch-literature.py` | fetches abstract page, PDF (latest version, then `pdftotext -layout`) and HTML for every paper into `W/upstream-latest/arxiv/<id>/` |
| `08-literature-check.py` | parses every table row of Perminov's three rank papers from the text (checking row counts against the counts the papers state); decodes and verifies Medley et al.'s rank-245 scheme; re-checks each of the 878 transcribed rows against the line it cites; gives overlaps (a)/(b)/(c) |
| `08-literature-data.py` | data only: the 878 rows transcribed from 46 other sources, 34 of which carry rank rows (quote, line, page, stated field). 2508.01748 was read by hand; its quotes in B.24 cite `paper.txt` lines |
| `08-composition-closure.py` | ranks reachable from listed or published GF(2)-valid ranks by direct sums, Kronecker products and Strassen on unequal blocks; also matmulcatalog's `cited-bounds.json` and `derived-from-cited-bounds.json` |
| `08-serendipitous-check.py` | rebuilds matmulcatalog's serendipitous-product rank claims over GF(2) from the named FMM base schemes and verifies them exactly |
| `08-composition-verify.py` | builds every composition of **explicit published** scheme files that is at or below one of our ranks, and verifies each one exactly |
| `08-crosscheck-release-verifier.py` | re-verifies 9 of the superseding schemes with the release's own verifier (`screen_top_two_projection_children.exact`), plus a negative control |
| `08-consolidate.py` | Section C: one flag per record |

## Summary

* **(A) The re-score changes nothing that matters.** Against the latest heads, reproduced with the release's own
  `public_tables()`, the 795 records split as before: 733 `below_all`, 62 `gf2_valid_only`. No record becomes a tie
  or goes above. Two margins shrink: 11x11x17 (comparator 1314 → 1313) and 16x16x31 (4474 → 4460). Both come from the
  Lille digest commit `fd0fccf` (2026-09-29T11:24Z).
* **(B/C) The scoring rule misses a lot of GF(2)-valid prior art.** It reads only four tables. It does not read
  F2-only schemes published outside them: Arai et al.'s ⟨4,5,5⟩:73, Kauers–Wood's Z2-only ⟨4,5,6⟩:89, Medley et al.'s
  ⟨7,7,7⟩:245, and Perminov's Z2 table. It does not read matmulcatalog's own `cited-bounds.json`. It does not compose
  the schemes it does list.
  * Superseded, with a verified scheme: we built GF(2) schemes below our rank for **80 records**, and every one verifies
    exactly over GF(2). All come from published files and published constructions. Nine of them also pass the release's
    own verifier.
    * 43 are rebuilt serendipitous products (Perminov, arXiv:2606.02480) whose rank claims matmulcatalog has carried
      since 2026-06-16. This file was present in the revision we scored.
    * 36 are elementary compositions of published explicit schemes. 5 of these use only schemes that the tables
      themselves list.
    * One is Medley et al.'s 7x7x7:245.
  * **7 more records are superseded by rank claims only**, which we did not rebuild.
  * **112 records equal an elementary composition of published schemes.** For 105 of these we built and verified the
    composition. Most carry `chain = closure product`: they are compositions, not search results.
  * **9 further `below_all` records** (16 counting overlaps) have a characteristic-0 (Q) catalogue claim below our rank.
    Their "below every listed rank in any ring" label is contradicted, though their GF(2) claim is not.
  * Records untouched by all of this: **587** (560 `below_all`, 27 `gf2_valid_only`), plus 9 that carry only the Q caveat.
* **Direct literature overlap is small.** Two cases:
  * Medley et al. (arXiv:2609.17533) report ⟨7,7,7⟩ over F2 with **245 < our 247**. We decoded their Appendix-A scheme
    and verified it.
  * Perminov (arXiv:2511.20317, Table 3) reports ⟨4,4,8⟩ over Z2 with **94 = ours**.

  No other listed paper states a rank at or below ours for one of our shapes. The prior art that matters is in
  compositions, and in one public catalogue file.

---

## (A) Re-score against the latest public tables

### A.1 Sources

| source | pinned (scored 2026-09-29) | latest head (fresh clone under `W/upstream-latest/`) | commits after the pin |
|---|---|---|---|
| Lille `fmm_digest` (`fmm_sota.json`) | `9f26324b` 2026-09-28T12:05:25+02:00 | `f5c2b2620ea0b342dd1c40909f28686e176d0af0` 2026-09-29T17:11:40+02:00 | `fd0fccf` 2026-09-29T13:24:38+02:00 "add new Perminov's tensor decomposition (his 613599b6…)"; `f5c2b26` "add new Witteveen's tensor decomposition (his 8fa0f2a0…)" |
| matmulcatalog (`docs/catalog.json`) | `f0c2ba9e` 2026-09-29T04:10:00Z | `5a306526e9c95d92871629f93798081d99100920` 2026-09-29T18:06:47Z | `525632e`, `51522c9`, `5a30652` "Sync reference catalogs + import Perminov schemes" (catalog.json 9556 → 9561 schemes) |
| FastMatrixMultiplication (`schemes/` file names) | `613599b6` 2026-09-28T19:29:41+03:00 | `ac13ca8855fbaf0154ba9e3b84dfbffd2681c9b7` 2026-09-29T20:55:12+03:00 (17:55Z) | `f9f91b2` "add new schemes from @MerlijnW70"; `853bd4b`, `ac13ca8` "add rediscovered Hopcroft-Kerr with ternary coefficients (ZT)" |
| fmm-schemes (`*.json` names) | `8fa0f2a0` 2026-09-27T20:31:09+02:00 | `8fa0f2a0b0d3d3ae070acabe24b99774a1c5e1a9` (unchanged, "Release 1.1") | none |

The fresh clones are `fmm`, `matmulcatalog`, `fmm_digest` and `fmm-schemes`. FMM and matmulcatalog are blob-less; the other
two are full. The files read at each revision are in `W/upstream-latest/extracted/` (`fmm_sota_<rev>.json`,
`mmc_catalog_<rev>.json`). All four pins are ancestors of the new heads.

### A.2 Method, and proof that it is the release rule

`08-rescore-latest.py` imports `gf2_record_board` from `/Users/erik/tungsten-mf-ternary/bits/tungsten-metaflip/tools`
(last changed in `a138832e`). It calls `public_tables(args)` unchanged and applies the class rule of `main()`.

1. **Pinned reproduction.** The inputs are the exact ones of 2026-09-29:
   * `W/upstream/fmm_digest/fmm_sota.json` (sha256 `4ad61b48…`, as in `comparators.json`);
   * `W/mmc_catalog_0929.json` (sha256 `cc2ba618…`);
   * `git ls-tree` of `W/upstream/fmm` at `613599b6`;
   * the `W/upstream/merlijn` working tree (clean; its `*.json` glob equals `git ls-tree`).

   `best_listed_any_ring`, `best_listed_gf2_valid` and the class re-derive for **795/795 rows, 0 disagreements**.
   With `GIT_NO_LAZY_FETCH=1` nothing was fetched into the pinned clones.
2. **Fresh clones at the pins give the identical tables.** This holds for the whole tables (5456 any-ring shapes, 2166
   GF(2)-valid shapes), per source and merged. The merged table is always the key-wise minimum of the four single-source
   tables.
3. **Latest.** The same function at the four heads.
4. **Attribution.** We rebuilt the single-source tables at every commit after each pin. Each moved comparator is
   attributed to the source and the first commit that reached it.

### A.3 Results

* Classes at the latest heads: `below_all` 733, `gf2_valid_only` 62. Transitions: 733 `below_all → below_all`,
  62 `gf2_valid_only → gf2_valid_only`.
* **No longer records: none.** No tie, no above, no `no_public_rank`, and no comparator went up.
* **Margins that shrank: 2.** In both, `gf2_valid` is unchanged and the class stays `below_all`.

| shape | ours | any-ring comparator: pinned → latest | supplier | first commit |
|---|---|---|---|---|
| 11x11x17 | 1312 | 1314 → 1313 | Lille digest | `fd0fccffa2` 2026-09-29T13:24:38+02:00 |
| 16x16x31 | 4346 | 4474 → 4460 | Lille digest | `fd0fccffa2` 2026-09-29T13:24:38+02:00 |

* **What moved, per source**, as counts of shapes whose single-source minimum changed from pin to latest head:

| source | any-ring: lower / new (all shapes) | GF(2)-valid: lower / new (all shapes) | among our 795: lower | supplied a combined comparator |
|---|---|---|---|---|
| Lille digest | 13 / 0 | – | 7 | 2 (11x11x17, 16x16x31) |
| FastMatrixMultiplication | 7 / 1 | 7 / 1 | 0 | 0 |
| matmulcatalog | 0 / 0 | 0 / 0 | 0 | 0 |
| fmm-schemes | 0 / 0 | 0 / 0 | 0 | 0 |

None of the FMM changes touches one of our shapes:
* `f9f91b2` adds the MerlijnW70 schemes. It puts 20 files under `schemes/known/`, which the rule excludes and
  fmm-schemes already supplied, and 5 files under `results/ZT`: 2x12x15, 2x13x15, 2x13x16, 2x14x16, 2x15x16.
* `853bd4b` and `ac13ca8` add Hopcroft–Kerr ZT files for 2×9…2×16 formats.

Our 2×n×m records are all 2x4xn or 2x5xn.

* The per-record table is in `W/paper-data/rescore_latest.tsv` (795 rows, sha256 `75e33d85…`). Its columns are old
  and new comparator, class, margins, the per-source values at the latest heads, the new suppliers, and the moving
  commit. A second run at 2026-09-30T00:13:45Z reproduced it byte for byte.

### A.4 The 7x7x7 rank-247 record: what each source lists now

These values are the same at the pins and at the latest heads.

* **Lille digest:** 249.
* **matmulcatalog** `catalog.json`:
  * any ring 249: "Strassen (recursive)", fields F3/Q/R/C, `curated/section7/7x7x7-r249-…`, and a derived stub.
  * F2-valid 250: "Perminov 2023", ZT, `known/section7/7x7x7-r250-perminov_ZT-9eecf8e.json`.
  * Waksman 1970 rank 235 is commutative, so the rule excludes it.
* **FastMatrixMultiplication:** 250 ZT (`schemes/results/ZT/7x7x7_m250_ZT.json` and an addition-reduced copy). No Z or
  Q file is lower.
* **fmm-schemes:** no 7x7x7 file.
* **None of the four tables lists** Perminov's Z2 rank 248 (arXiv:2511.20317 Table 3) or Medley et al.'s F2 rank 245
  (arXiv:2609.17533). The 245 is below our 247 (B.1).

### A.5 What the scoring rule does not see

The rule compares against minima over four specific inputs. It therefore does not see:

1. **F2-only schemes published outside those tables.**
   * Arai et al. ⟨4,5,5⟩:73 (matmulcatalog lists 76).
   * Kauers–Wood's Z2-only schemes, e.g. ⟨4,5,6⟩:89 and ⟨3,8,8⟩:145 (the tables list 90 and 146).
   * Medley 245.
   * Perminov's Z2 table.
2. **FMM files under `schemes/known/`,** which the rule excludes. For our shapes this changed nothing: including them
   (closure L1 in `08-composition-closure.py`) changes the composed bound of 0 of the 795 records.
3. **matmulcatalog's `docs/cited-bounds.json` and `docs/derived-from-cited-bounds.json`.** These are rank claims without
   factor matrices, kept beside `catalog.json` in the same repository.
4. **Compositions** (direct sums, Kronecker products, Strassen on blocks) of the schemes the tables do list.

Sections B and C quantify each of these.

---

## (B) Literature check (run 2026-09-29)

**Method.**

* `08-fetch-literature.py` stored, for every paper:
  * the abstract page (`abs.html`, which carries the submission history);
  * the latest PDF (`paper.pdf`), converted with `pdftotext -layout` (`paper.txt`);
  * the arXiv HTML where one exists.
* **Perminov's three rank papers** are parsed from the text by the regular expressions in `08-literature-check.py`.
  That is 770 table rows, and each table's row count equals the count the paper states: 8, 24, 30, 40, 72 / 79, 93, 68,
  29 / 13, 207, 84, 23.
* **The other sources** were read in full and every result table transcribed: 878 rows from 46 sources (`08-literature-data.py`).
  * Each row carries the line and page it was read from and a verbatim quote.
  * `08-literature-check.py` re-reads that line and aborts on any mismatch. All 878 pass.
* **GF(2) validity** is taken only from the paper's own statement. A row counts when the paper states characteristic 2,
  Z2, F2, ternary or integer coefficients, any ring or field, or odd denominators. "Not stated" is never counted, so 417
  of the 878 rows are GF(2)-valid.
* **Overlap categories** used below:
  * (a) a GF(2)-valid rank ≤ ours for one of our 795 shapes;
  * (b) a GF(2)-valid rank below the comparator we used, `best_listed_gf2_valid`, or `best_listed_any_ring` when that is empty;
  * (c) a characteristic-0-only rank below ours.
* Pages are counted from the form feeds of `paper.txt` and match the printed page numbers.
* Quotes are verbatim from `paper.txt`, with runs of whitespace collapsed.
* The per-paper extraction was split across three helper agents. Every row they returned is re-verified by the script
  above, and the conclusions below are checked against it.

### B.1 arXiv:2609.17533: Medley, Gokul, Luu, Manolios, "GPU-Accelerated Search for Fast Matrix Multiplication over F2" (read in full)

v1, submitted Mon 22 Jun 2026 (the id is from the September 2026 announcement); `abs.html`: "[Submitted on 22 Jun 2026]".
Full text: https://arxiv.org/pdf/2609.17533 (23 pp.).

* **Reports.**
  * GPU flip-graph search: warp-level matching, and "generalized multi-summand flips".
  * A theorem that over F2 the directed flip graph is strongly connected with only flip and plus edges (Thm 3.4, p. 5).
  * **⟨7,7,7⟩ over F2 with 245 multiplications**, three below the previous record 248 (Perminov [7]).
  * Only other ranks: the rank-47 ⟨4,4,4⟩ rediscovered in ablations (Fig. 5), and cited records (5×5: 93, 4×4: 47).
  * Fig. 3 and Fig. 4 report throughput and rank reduction in 60 s, not records.
* **Range and field.** Square n ≤ 8, F2 only.
* **Overlap.** **7x7x7: 245 < ours 247 → superseded.** The scheme is printed in Appendix A (zlib + base32, p. 22) with a
  checker. `08-literature-check.py` decodes it from `paper.txt` and verifies all 245 terms against M⟨7⟩ over F2, with
  its own code. `08-crosscheck-release-verifier.py` verifies it again with the release verifier. It is category (a),
  and also (b) against both comparators (249 and 250).
* **Quotes.**
  * p. 1, l. 24 (abstract): "a way to multiply 7 × 7 matrices over F2 using 245 multiplications, a"
  * p. 1, ll. 32–33: "the current records for multiplying 5 × 5, 6 × 6, and 7 × 7 matrices over F2 were found via flip graph search [6, 7]."
  * p. 20, l. 994: "found a decomposition of the 7 × 7 × 7 matrix multiplication tensor over F2 of"
  * p. 22, l. 1046: "BEGIN-RANK245-7X7X7-ZLIB-BASE32"

### B.2 arXiv:2511.20317: Perminov, "Fast Matrix Multiplication via Ternary Meta Flip Graphs"

v2, 29 Nov 2025 (15 pp.).

* **Reports.**
  * GPU ternary meta flip graph.
  * Table 1: 8 ZT rediscoveries of Q-only ranks.
  * Table 2: 24 ZT rediscoveries.
  * **Table 3: 30 rank improvements over Z2.**
  * Table 4: 40 addition counts.
  * Table 5: 72 near-optimal ZT schemes.
* **Range and field.** "(2, 2, 2) to (8, 8, 8) with additional schemes where max(n, m, p) ≤ 16 and total matrix elements ≤ 64"
  (p. 11, ll. 650–651). Tables 1, 2, 4 and 5 are ZT (plus the Q/Z of the best-known column); Table 3 is Z2 only.
* **Overlap.** Our shapes 4x4x8, 7x7x7, 4x4x14 and 4x4x15 appear.
  * **(a): 4x4x8, Z2 rank 94 = ours 94 → matched** (Table 3).
  * (b): 4x4x8 94 is below both comparators we used (95 any ring, 96 GF(2)). 7x7x7 248 is below 249/250 but above our 247.
  * The other tables list these shapes above our ranks, so there is no (c) either:
    * Tables 1 and 4: 96 for 4x4x8;
    * Table 5 (best listed ring / ZT): 165/169 for 4x4x14, 177/181 for 4x4x15, and 249/250 for 7x7x7.
* **Quotes.**
  * p. 1, l. 29 (abstract): "…and 30 rank improvements in the binary field."
  * p. 12, l. 716: "Table 3: New discoveries in binary field (Z2 )"
  * p. 12, l. 729: "(4, 4, 8) 96 94"
  * p. 12, l. 731: "(7, 7, 7) 249 248"

### B.3 arXiv:2603.02398: Perminov, "Fast Matrix Multiplication in Small Formats: Discovering New Schemes with an Open-Source Flip Graph Framework"

v1, 2 Mar 2026 (15 pp.).

* **Reports.**
  * A framework over Z2, Z3 and ZT.
  * Table 1: 79 improved ranks, each with its ring.
  * Table 2: 93 ZT rediscoveries.
  * Table 3: 68 Z rediscoveries.
  * Table 4: 29 formats below Strassen's exponent.
* **Range and field.** All 680 formats up to 16×16×16. Ranks are given in ZT, Z or Q; no Z2-only rank is tabulated:
  "Schemes discovered in Z2 or Z3 are valid only over fields of characteristic 2 or 3 respectively" (p. 7, l. 386).
* **Overlap.** Table 1 names 19 of our shapes, Table 2 names 7 and Table 4 names 5.
  * No (a) and no (b). All these ranks are FMM files, so they are already in the comparators.
  * (c), Q below ours: 9x11x13 835 (Table 1, p. 10, l. 554), 12x12x14 1240 (l. 579), 12x12x15 1280 (Table 4, p. 15, l. 864).
    All three are `gf2_valid_only` records, so the class already concedes a lower Q rank.
* **Quotes.**
  * p. 1, ll. 25–26: "The framework supports multiple coefficient rings – binary (Z2 ), modular ternary (Z3 ) and integer ternary (ZT = {−1, 0, 1})"
  * p. 10, l. 546: "Table 1: Improved ranks for matrix multiplication formats"

### B.4 arXiv:2606.02480: Perminov, "Meta Flip Graph meets Serendipitous Product: new Fast Matrix Multiplication results"

v2, 5 Jun 2026 (15 pp.).

* **Reports.**
  * The serendipitous product (Smith; Sedoglavic) combined with the meta flip graph.
  * Table 1: 13 example products.
  * Table 2: 207 improved ranks (ZT or Q).
  * Table 3: 84 ZT rediscoveries.
  * Table 4: 23 new sub-Strassen-exponent schemes.
  * The base schemes are in FMM `schemes/results/serendipitous_base/`. The one used for 3x14x18,
    `3x7x9_m141_076164eb…`, was added in FMM `7969191` on 2026-06-08.
* **Range and field.** Formats n ≤ m ≤ p ≤ 16 only: "such that the resulting dimensions … do not exceed 16 × 16 × 16"
  (p. 9, l. 563). ZT or Q per row.
* **Overlap.** Table 2 names 34 of our shapes.
  * No (a) and no (b).
  * (c): 10 Q ranks below ours, all on `gf2_valid_only` records. They are 9x10x14 808, 8x8x15 628, 11x12x16 1278,
    11x13x16 1446, 12x12x14 1234, 12x13x14 1370, 12x13x15 1442, 8x12x13 781, 12x14x16 1617 and 8x12x14 843
    (p. 11, ll. 675–727).
* **Why it still matters.** The construction is a published recipe:

  > "The serendipitous product construction, introduced by Smith [18] and generalized by Sedoglavic [2], combines two
  > matrix multiplication schemes (n1 , m1 , p1 : r1 ) and (n2 , m2 , p2 : r2 ) to obtain a scheme for the format
  > (n1 n2 , m1 m2 , p1 p2 : rs ) whose rank can be lower than the naive (Kronecker) product r1 · r2 ."
  > (p. 4, ll. 222–224)

  matmulcatalog applied it beyond 16 and recorded the resulting rank claims (B.22). We rebuilt them (C).
* **Quotes.**
  * p. 4, ll. 236 and 253: "Each term ⟨Ni n2 , Mi m2 , Pi p2 ⟩ is realized using the best known scheme for that format", "where R(N, M, P ) denotes the best known rank for format (N, M, P )."

### B.5 arXiv:2512.21980: Perminov, "A 58-Addition, Rank-23 Scheme for General 3x3 Matrix Multiplication"

v1, 26 Dec 2025.

* **Reports.** One ⟨3,3,3⟩ rank-23 scheme, ternary, with 58 additions.
* **Range and field.** 3×3 only, any ring.
* **Overlap.** None.
* **Quote.** p. 1, l. 23: "non-commutative rings, achieving a rank-23 scheme with only 58 scalar additions."

### B.6 arXiv:2512.13365: Perminov, "Parallel Heuristic Exploration for Additive Complexity Reduction in Fast Matrix Multiplication"

v2, 21 Dec 2025.

* **Reports.** Addition counts for 149 known ternary schemes (Tables 1–6). It gives no new ranks.
* **Range and field.** Formats up to 8×8×8 and ≤ 16 on a side; ZT.
* **Overlap.** Our shapes appear with ranks above ours, so there is no (a), (b) or (c):
  * 4x4x8: 96 (Table 1, p. 9, l. 509: "4×4×8 96 973 …");
  * 4x4x14: 169 and 4x4x15: 181 (Table 2, ll. 532–533);
  * 7x7x7: 250 (l. 541).
* **Quote.** p. 1, l. 27: "Tested on 149 ternary-coefficient schemes, the method achieves lower addition"

### B.7 arXiv:2510.19787: Kauers, Wood, "Exploring the Meta Flip Graph for Matrix Multiplication"

v1, 22 Oct 2025.

* **Reports.** About thirty improved formats, summarised in Fig. 4 (28 rows), all with max side ≤ 8.
* **Field.** Everything was found mod 2. Most schemes lift to Z. Seven only lift to Q with odd denominators, which are
  still GF(2)-valid. (4,5,6), (3,7,8) and (3,8,8) are Z2-only.
* **Overlap.** None of our shapes is in Fig. 4. Our only shapes with max side ≤ 8 are 4x4x8 and 7x7x7; 7x7x7 appears
  only in a reference title (250).
* **Relevance through compositions.** The Z2-only ⟨4,5,6⟩:89 files are in the paper's data repository
  (github.com/mkauers/matrix-multiplication, commit `12c26b29`, 2026-05-29). They verify over F2 and enter 6 of the
  verified below-our-rank compositions in C: 13x19x21, 13x19x22, 13x20x21, 13x20x22, 16x19x22 and 16x20x24.
* **Quotes.**
  * p. 1, l. 15: "graphs, we present here improved rank bounds for about thirty matrix formats."
  * p. 9, l. 434 (Fig. 4, the (4,5,6) row): "456 90 = > > 89 > > = = = = 89 89 ="
  * p. 10, ll. 473–474: "For the formats (4, 5, 6), (3, 7, 8) and (3, 8, 8), the improvement appears to work only over Z2 ."
  * p. 10, ll. 483–484: "The multiplication schemes announced in this article are publicly available at https:// github.com/mkauers/matrix-multiplication."

### B.8 arXiv:2602.11041: Kauers, Moosbauer, Wood, "Exploiting the Structure in Tensor Decompositions for Matrix Multiplication"

v3, 21 May 2026.

* **Reports.** Exponent improvements (6×6: 2.8075 → 2.8019). Table 1 has 20 structured decompositions found over Z2 and
  lifted; Table 2 has 10 that are Z2-only. The implied ranks match known ones, all with max side ≤ 8. The only large
  explicit bound is ⟨216,216,216⟩ ≤ 3581065.
* **Overlap.** None.
* **Quotes.**
  * p. 5, l. 279: "⟨216, 216, 216⟩ ≤ ⟨3581065⟩."
  * p. 14, l. 923: "New decompositions found for various matrix multiplication tensors ⟨𝑛, 𝑚, 𝑝⟩, only valid for 𝐾 = ℤ2 ."

### B.9 arXiv:2502.04514: Moosbauer, Poole, "Flip Graphs with Symmetry and New Matrix Multiplication Schemes"

v1, 6 Feb 2025.

* **Reports.** ⟨5,5,5⟩:93 and ⟨6,6,6⟩:153, found over F2 with symmetry and lifted to Z. Both are valid over all fields.
* **Overlap.** None directly. The 93 enters the composition 20x20x20 = 4x4x4:47 ⊗ 5x5x5:93 = 4371 < ours 4451 (C).
* **Quotes.**
  * p. 1, l. 13: "5×5 matrices using 93 multiplications and 6×6 matrices using 153 multiplications over arbitrary ground"
  * p. 8, l. 398: "All schemes we found could be lifted to coefficients in Z as described in Section 6."

### B.10 arXiv:2312.16960: Arai, Ichikawa, Hukushima, "Adaptive Flip Graph Algorithm for Matrix Multiplication"

v2, 16 Mar 2024 (ISSAC '24).

* **Reports.** Table 1 lists 20 formats with all sides ≤ 5, in characteristic 2. The new ranks are **⟨4,5,5⟩:73**
  (was 76) and **⟨5,5,5⟩:94**.
* **Field.** "we restricted matrix multiplication schemes to ground fields of characteristic two, 𝐾 = Z2" (p. 5, ll. 321–322).
  The schemes are at github.com/Yamato-Arai/adap (commit `fe7b2040`, 2024-06-03). We cloned them; 73 terms and 94 terms
  both verify over F2.
* **Overlap.** None directly. But **⟨4,5,5⟩:73 is in none of the four comparator tables**: matmulcatalog's best F2 entry
  for ⟨4,5,5⟩ is 76. Composed with listed schemes it supersedes **32 of our records**. Examples:
  * 4x5x15 = 73 + 146 = 219 < 220;
  * 16x20x20 = 47·73 = 3431 < 3572;
  * 20x20x25 = 73² = 5329 < 5442;
  * 25x30x32 = 73·170 = 12410 < 12665.
* **Quotes.**
  * p. 1, ll. 35–37 (abstract; the two-column text interleaves another column on each line): "a 5 × 5 matrix from 76 to 73, and that from 95 to 94 for a 5 × 5 matrix" / "multiplied by another 5 × 5 matrix. These results are obtained in" / "characteristic two."
  * p. 6, l. 402 (Table 1): "(4, 5, 5) [2] 76 76 76 – 73"
  * p. 6, l. 435: "are explicitly shown in https://github.com/Yamato-Arai/adap."

### B.11 arXiv:2306.00882: Kauers, Moosbauer, "Some New Non-Commutative Matrix Multiplication Algorithms of Size (n,m,6)"

v1, 1 Jun 2023.

* **Reports.** An unlabelled table (p. 3, 15 rows) of all (n,m,6) with n, m ≤ 6, found over Z2. Some are stated
  integer, or valid in any characteristic. A star marks fractional coefficients: (3,3,6):40 is in Z[1/2].
* **Overlap.** None; the largest format is 6×6×6.
* **Quotes.**
  * p. 3, l. 119: "format naive best our"
  * p. 9, l. 982: "Electronic versions of these schemes as well as schemes for other formats (n, m, 6) over K = Z2 are"

### B.12 arXiv:2108.09520: the listed id is not a matrix-multiplication paper

The id resolves to Cha, Chiang, Sasaki, "Inference in high-dimensional regression models without the exact or L^p
sparsity" (econ.EM). p. 1, l. 9: "arXiv:2108.09520v2 [econ.EM] 31 Dec 2022".

The arXiv API lists six Kauers–Moosbauer papers. The only 2021–22 one not already on the list is **arXiv:2206.00550,
"A Normal Form for Matrix Multiplication Schemes"** (v1, 1 Jun 2022). We fetched and checked it:
* it is a methods paper on a normal form for scheme equivalence;
* it has no new ranks;
* Table 1 (p. 4, l. 176) is "Strassen’s Algorithm";
* no overlap.

### B.13 arXiv:2511.10786: Khoruzhii, Gelß, Pokutta, "Faster Algorithms for Structured Matrix Multiplication via Flip Graph Search"

v2, 30 Nov 2025 (ISSAC 2026).

* **Reports.** Structured products (A·Aᵀ, triangular, symmetric inputs) for n ≤ 5. General matrix multiplication
  appears only in the "gg" row of Table 3: ⟨4,4,4⟩ 47 over F2 (49 over F3 and Z), ⟨5,5,5⟩ 97.
* **Overlap.** None.
* **Quotes.**
  * p. 6, l. 508: "Table 3: Ranks of discovered schemes for structured matrix multiplication."
  * p. 7, l. 515: "gg 8 7 7 7 - 27 23 23 23 - 64 47 49 49 - 125 97 124 97 -"

### B.14 arXiv:2503.05467: Ikenmeyer, Moosbauer, "Strassen's algorithm via orbit flip graphs"

v1, 7 Mar 2025, 3 pp.

* **Reports.** A short proof that the rank of ⟨2,2,2⟩ is at most 7, over any field.
* **Overlap.** None.
* **Quote.** p. 1, ll. 11–12: "the rank of the 2 by 2 matrix multiplication tensor is at most 7."

### B.15 arXiv:2506.22113: Wood, "Exploring Commutative Matrix Multiplication Schemes via Flip Graphs"

v1, 27 Jun 2025.

* **Reports.** *Commutative* schemes over F2 up to 5×5 (40 rows). These are not bilinear ranks and are not comparable
  with our records.
* **Overlap.** None.
* **Quote.** p. 1, l. 12: "gorithms in the commutative setting by adapting the flip graph technique:"

### B.16 arXiv:2210.04045: Kauers, Moosbauer, "The FBHHRBNRSSSHK-Algorithm for Multiplication in Z2^{5×5} is still not the end of the story"

v3, 13 Oct 2022.

* **Reports.** ⟨5,5,5⟩:95 and ⟨4,4,4⟩:47, both in characteristic 2.
* **Overlap.** None.
* **Quotes.**
  * p. 1, ll. 10–11: "matrices over Z2 with only 96 multiplications, two fewer than the previous record, we present an algo-" / "rithm that does the job with only 95 multiplications."
  * p. 1, l. 52: "be matrices with coefficients in a ring R of characteristic 2."

### B.17 arXiv:2212.01175: Kauers, Moosbauer, "Flip Graphs for Matrix Multiplication"

v1, 2 Dec 2022 (ISSAC '23).

* **Reports.** Table 1 (p. 10) covers all formats with sides ≤ 5 over K = Z2 or any field. New entries:
  * (4,4,5): 60 over Z2, 62 over any field;
  * (5,5,5): 95 over Z2, 97 over any field.
* **Overlap.** None directly. The Z2 60 enters two exact matches in C:
  * 8x8x10 = Strassen ⊗ 4x4x5:60 = 420 = ours;
  * 8x8x9 = 381 = ours, by Strassen on 4+4 / 4+4 / 4+5 blocks.
* **Quotes.**
  * p. 10, l. 554: "Table 1. Comparison between best known rank and the rank we found"
  * l. 549: "(4, 4, 5) Z2 63 [8] 60"
  * l. 546: "(4, 4, 4) Z2 47 [8] 47"

### B.18 arXiv:2506.13131: Novikov et al., "AlphaEvolve: A coding agent for scientific and algorithmic discovery"

v1, 16 Jun 2025.

* **Reports.** Table 2 (16 rows) and Table 3 (54 rows) give ⟨m,n,p⟩ ranks up to ⟨2,2,16⟩ and ⟨6,6,6⟩. The entries are
  integer or half-integer; ⟨3,4,7⟩, ⟨4,4,4⟩ and ⟨4,4,8⟩ are complex.
* **Overlap.** 4x4x8: AlphaEvolve's 96 is complex-valued and above ours 94. No (a), (b) or (c).
* **Quote.** p. 9, l. 489: "⟨4, 4, 8⟩ 98 [95] 96"

### B.19 arXiv:2506.13242: Dumas, Pernet, Sedoglavic, "A non-commutative algorithm for multiplying 4x4 matrices using 48 non-complex multiplications"

v7, 27 Jul 2026.

* **Reports.** ⟨4,4,4⟩:48 and ⟨3,4,7⟩:63 with rational coefficients, not valid in characteristic 2.
* **Overlap.** None.
* **Quote.** p. 1, l. 32: "any ring except those of characteristic 2."

### B.20 arXiv:2101.12568: Sedoglavic, Smirnov, "The tensor rank of 5x5 matrices multiplication is bounded by 98 and its border rank by 89"

v2, 1 Feb 2021.

* **Reports.** ⟨3,5,5⟩:58, giving 5×5:98, 10×10:686 and 15×15:2088. The paper states no field.
* **Overlap.** 15x15x15: 2088 is above ours (2006). No overlap.
* **Quotes.**
  * p. 1, l. 16: "(resp. 10 × 10, 15 × 15) matrices using 98 (resp. 686, 2088) multi-"
  * p. 5, l. 383: "⟨15 × 15 × 15 : 2088⟩ = ⟨3 × 5 × 5 : 58⟩ ⊗ ⟨5 × 3 × 3 : 36⟩."

### B.21 GitHub big-brain-zaru/FastMatrixF2 (README)

HEAD `5fd32f680acf2a7708ea6a2d40d10f7e7537957c`, 2026-09-18.

* **Reports.** Over F2 only:
  * a second, inequivalent ⟨4,4,4⟩:47;
  * rigidity results;
  * large same-rank families at 5×5:93 and 6×6:153.
* **Overlap.** None.
* **Quotes.**
  * README l. 10: "Headline result: a second, inequivalent rank-47 scheme for 4×4 matrix multiplication over F₂"
  * README l. 18: "No published record is improved. The rank-46 question for 4×4 over F₂ remains open."

### B.22 matmulcatalog `docs/cited-bounds.json`: public rank claims the scoring rule never read

This is not a paper. It is a file in one of the four scored repositories, and it carries literature-derived rank claims.

* **What the file is.** Its own description reads: "Upper-bound RANK CLAIMS from the literature without accompanying
  factor matrices. See GenerateCitedBounds.java for sources." It has 6524 entries. Its blob `7bbf2fc4…` is **identical
  at every revision** from `0a9f83a` ("Reset project", committer date 2026-06-16T14:48:54+04:00), through the scored
  pin `f0c2ba9e`, to the latest `5a306526`. So it was public before our campaign and present in the revision we scored.
  The rule reads only `docs/catalog.json`.
* **What it contains.**
  * 971 entries are "Perminov 2026 (serendipitous)", with `source_paper_url` arXiv:2606.02480 and a
    `source_scheme_url` naming an FMM `serendipitous_base` file.
  * Their formats have max side 18–32. Field Z: 873; Q: 98. All have `scheme_provided: false`.
  * A typical note reads "improves Perminov curr_rank 562; large scheme not copied — reconstruct from base (s1) + s2 at source_scheme_url".
  * The same values appear as the `perminov` column (`perminov_published: false`) of `docs/comparison/us-vs-fmm-vs-perminov-F2.json`,
    at 31 of our shapes.
* **At or below our rank on our shapes.** 69 non-commutative claims in all:
  * 51 Perminov claims with field Z: 48 below ours, 3 equal;
  * 16 Perminov claims with field Q, all below ours;
  * two R/Q/Z claims at 20x20x20, "DIS 2009 (Pan trilinear aggregation framework)" 4340 and "Smith 2002" 4380.
* **We rebuilt them** (`08-serendipitous-check.py --with-q --rich`). For every Z claim we used the named FMM base scheme,
  reduced it mod 2, found bud blocks (single-type and mixed rectangles) and built the product as in arXiv:2606.02480 §2.6.
  The auxiliary schemes came from published explicit files. Every product was **verified exactly over GF(2)**.
  * **43** of the 51 Z claims give a verified scheme **strictly below our rank**: 35 at or below the claimed rank, 8 above
    the claim but still below ours. Some rebuilds even beat the claim, for example 13x32x32 at 7450 against a claim of
    7474, because GF(2) allows F2-only auxiliary schemes.
  * **4** give exactly our rank: 4x15x27, 4x27x30, 8x18x27 and 11x16x27.
  * **4** stay above our rank: 4x14x20, 9x9x18, 10x12x25 and 13x16x21. 10x12x25 is superseded anyway, by 25·73 = 1825
    (B.23). 9x9x18 is claimed at 913, and that fits only the Q-only ⟨3,3,6⟩:40 as second factor: 23·40 = 920 before bud
    savings. With the best GF(2)-valid ⟨3,3,6⟩:42 the plain product is 23·42 = 966, and our rebuild reaches 951.
  * The 16 Q claims cannot be rebuilt over GF(2), because their base schemes have fractional coefficients. They remain
    characteristic-0 claims.
* **Two other catalogue files.**
  * `docs/derived-from-cited-bounds.json` (formula-derived, "verified: false") has F2 bounds equal to ours at 8x8x9 (381)
    and 8x8x10 (420). We rebuilt both and verified them (B.23).
  * Three records are superseded only through catalogue-derived "stub" entries of `catalog.json` that we did not
    materialise: 12x22x24 (via 6x12x24:1029), 12x24x25 (via 9x12x24:1515) and 16x19x30 (via 4x16x28:1155). They are
    flagged S2 in C.

### B.23 Elementary compositions of published schemes

`08-composition-closure.py` computes the smallest rank reachable by direct sums, Kronecker products and Strassen's
algorithm on unequal 2×2×2 block splits. A product's operands are zero-padded block combinations, truncated to the rows,
inner size and columns the product actually needs; 36 support patterns come from Strassen's scheme under sandwiching
and symmetries. It starts from three bases:

| base | contents |
|---|---|
| L0 | the rule's own GF(2) table |
| L1 | L0 plus FMM `schemes/known` |
| L2 | L1 plus the GF(2)-valid rank claims of the papers above |

| closure | below our rank | equal to our rank |
|---|---|---|
| L0: sums and products of the rule's own GF(2) table | 4 (12x22x24, 12x24x25, 20x20x20, 20x20x24) | 121 |
| L0 + Strassen | 7 (adds 8x8x15, 16x23x31, 16x24x31) | 124 |
| L2 + Strassen (with paper rank claims) | 42 | 115 |

`08-composition-verify.py` then does the same from **explicit published files only**: FMM, matmulcatalog explicit F2
files, the Kauers–Wood repository, Arai et al.'s repository and Medley's appendix. Every composition at or below our
rank is built and verified.

* **39 records are strictly below our rank. All 39 are verified.**
* **107 are equal. All 107 are verified.**
* The run took 293 s.
* The main new ingredients are:
  * Arai's ⟨4,5,5⟩:73, used in 32 of the 39;
  * AlphaTensor's F2 ⟨4,4,4⟩:47 (as listed by matmulcatalog), in 20;
  * Kauers–Moosbauer's F2 ⟨4,4,5⟩:60, in 7;
  * Kauers–Wood's Z2-only ⟨4,5,6⟩:89, in 6.
* Examples:
  * 20x20x20 = 47·93 = 4371 against our 4451;
  * 20x20x24 = 47·110 = 5170 against our 5202;
  * 8x8x15 = 7x8x8:302 (Strassen on AlphaTensor F2 blocks) ⊕ 8x8x8:329 = 631 against our 632;
  * 4x4x8 = 47 + 47 = 94, equal to ours.

**Independent check.** `08-crosscheck-release-verifier.py` re-verifies nine of the superseding schemes with the
release's own `exact()`. They are 7x7x7:245, 4x5x15:219, 8x8x15:631, 16x20x20:3431, 20x20x25:5329, 13x19x21:3147 and
8x8x9:381, plus the serendipitous 3x14x18:560 and 7x14x20:1265. All agree. The negative control also behaves: both
verifiers reject a scheme with one flipped coefficient in U, V or W, or with one term dropped.

### B.24 Further papers found by search (2026-09-29)

**Searches.** I ran nine WebSearch queries:
1. flip graph / new schemes 2026;
2. tensor rank GF(2) new upper bounds 2026;
3. "over F2" / "characteristic two" flip graph;
4. 2607–2609 rectangular formats;
5. meta flip graph with Z2 lifting;
6. RL or evolutionary tensor decomposition GF(2);
7. "245 multiplications" 7x7 F2;
8. Kauers / Moosbauer / Wood 2026;
9. "Faster search for tensor decomposition over finite fields".

A helper agent ran 7 more WebSearch queries and 12 arXiv-API queries. These covered `all:"flip graph" AND all:matrix`,
`ti:"matrix multiplication"` with rank or scheme, the authors Perminov, Kauers, Moosbauer, Sedoglavic, Heule, Hukushima,
Wood and Khoruzhii, "tensor rank" / finite field / F2 / GF(2) / characteristic 2, AlphaTensor / AlphaEvolve / bilinear
complexity, and SAT. It also chased references across all fetched texts. In all, 28 further arXiv papers were fetched and checked, with
their quotes verified: 26 from the searches, 2206.00550 (B.12) and 2508.01748. Two more, 2601.05272 and 2607.15069,
were read from their arXiv API abstracts.

**Papers with rank upper bounds.**

* **arXiv:2606.13408**, Lacelle, "A catalog of fast matrix multiplication algorithms with exhaustive derivations"
  (v3, 14 Aug 2026). This is the matmulcatalog paper.
  * Its printed comparisons are over Q (snapshot 2026-07-12) and R/Q. The v3 PDF has no F2 table.
  * It names 9 of our shapes, all at ranks above ours.
  * Its only values below ours are closed-form ⟨20,20,20⟩ bounds, and the paper states no field for them.
    p. 16, l. 867: "term is itself a best-of several Pan-family closed forms: (n3 + 12n2 + 11n)/3 (Islam 2009 [7]" gives 4340.
    p. 16, l. 876 (LITA): "(4N 3 +45N 2 +116N +84)/12 for even N …" gives 4367.
  * Our 20x20x20 (4451) is superseded anyway (4371, verified).
* **arXiv:2508.01748**, Schwartz, Zwecher, "Towards Faster Feasible Matrix Multiplication by Trilinear Aggregation"
  (v1, 3 Aug 2025).
  * Table 1 (p. 4) gives cube ranks for n0 ≥ 28 (28: 10550, 30: 12688, 32: 15096); none is our shape.
  * Table 4 (p. 22, l. 1282), "20 12089 44 12166 154 12133 1540 4378 484 8.419", gives ⟨20,20,20⟩ with 4378 < 4451.
    The field is not stated: W has 1540 coefficients outside {−1,0,1}.
  * The paper itself notes (p. 3, ll. 124–125): "Some of the feasible algorithms are applicable only to certain fields,
    such as a ⟨4, 4, 4; 47⟩-algorithm [24] and a ⟨4, 4, 5; 60⟩-algorithm [35] that work over Z2 ."
* **arXiv:2505.05896**, Kauers, Wood, "Consequences of the Moosbauer-Poole Algorithms" (v1, 9 May 2025). Formats
  (4,5,5) to (6,7,7), integer schemes lifted from Z2 (one is Z2-only). No overlap. p. 1, l. 22: "schemes as starting
  points, we found improved matrix multiplication schemes for various rectangular".

**No new rank; ring, additions or accuracy only. No overlap.**

* 2602.13171: Moran, Schwartz, Yuan, complex to rational coefficients.
* 3×3 rank-23 papers: 2604.27645, 2609.32388, 2609.06588, 2607.28676, and 2607.29291 (Palladinos, F2 SAT certificates).
  2601.05272 was seen through the arXiv API only.
* 4×4:48 papers, over rings containing 1/2: 2609.12027, 2603.18699 and 2609.13596. 2607.15069 was seen through the API only.
* Others: 2506.19405, 2502.12390, 2404.16699 and 2609.26077.

**Not about matrix-multiplication upper bounds.** 2505.09824, 2401.06857, 2605.12295, 2602.21797, 2608.27434 and 2605.06057.

**Lower bounds only.** 2609.14393, 2603.07280, 2609.22054, 2609.06725 and 2609.18722. All 15 of our ⟨2,p,n⟩ ranks are at
or above the bound nm + 2·max(n,m) of 2609.14393.

---

## (C) Records to flag as superseded or matched by prior art

`08-consolidate.py` gives each record the first flag that applies:

| flag | meaning | records | below_all | gf2_valid_only |
|---|---|---|---|---|
| **S1** | superseded, and verified: a GF(2) scheme below our rank that we **built from published files and checked exactly** | **80** | 65 | 15 |
| **S2** | superseded by a **rank claim only** (paper or catalogue), not rebuilt | **7** | 6 | 1 |
| **M1** | matched, and verified: our rank is **exactly** that of a composition of published schemes, built and checked | **105** | 88 | 17 |
| **M2** | matched by a rank claim only | **7** | 5 | 2 |
| **Q** | not superseded over GF(2), but a characteristic-0 (Q) catalogue claim is below our rank, which contradicts the `below_all` label | **9** | 9 | – |
| none | no prior art found at or below our rank | **587** | 560 | 27 |

How the S1 schemes were obtained:
* 43 are serendipitous products rebuilt from FMM base schemes (B.22).
* 36 are compositions of explicit published files (B.23).
* 1 is Medley's 7x7x7:245.

In the M1 group, 102 matches are compositions and 3 are serendipitous products. 16 `below_all` records carry a lower Q
claim in all; 7 of them also carry an S1 or M1 flag, which is why the Q row counts only 9.
Nearly all M1/M2 records are our own `closure product` chains: 95 of the 107 exact explicit matches in B.23. So they
are compositions the paper already built, not search discoveries.

Superseded records (S1 + S2 = 87), by shape. Every row of the tables below carries the construction or the source:

* **S1 (80):** 3x14x18, 3x14x27, 4x5x14, 4x5x15, 4x5x16, 4x5x27, 4x5x28, 4x11x24, 4x20x27, 4x26x32, 6x16x26,
  6x20x20, 6x32x32, **7x7x7**, 7x12x20, 7x14x20, 7x20x21, 8x8x15, 8x8x30, 8x24x26, 8x27x32, 8x32x32, 9x16x32,
  9x20x32, 10x11x21, 10x12x25, 10x15x21, 10x16x25, 10x18x24, 10x18x25, 10x24x26, 10x24x27, 10x27x28, 10x27x30,
  10x28x28, 11x14x20, 11x16x21, 11x16x30, 11x21x32, 11x24x32, 11x27x28, 12x13x28, 12x13x32, 12x15x20, 12x20x25,
  12x20x30, 13x15x20, 13x15x22, 13x16x18, 13x16x30, 13x19x21, 13x19x22, 13x20x21, 13x20x22, 13x20x27, 13x32x32,
  15x15x21, 15x16x25, 15x16x31, 15x19x19, 15x20x32, 16x19x22, 16x20x20, 16x20x21, 16x20x22, 16x20x24, 16x20x25,
  16x20x30, 16x23x31, 16x24x31, 16x25x28, 16x25x31, 16x26x30, 16x31x31, 17x20x20, 20x20x20, 20x20x24, 20x20x25,
  20x25x32, 25x30x32.
* **S2 (7):** 4x14x20 (claim 736), 9x9x18 (913), 11x16x27 (2780; our rebuild only reaches 2825, our rank),
  12x22x24 (3567), 12x24x25 (4053), 13x16x21 (2571), 16x19x30 (5199).

Caution on S2: the 9x9x18 claim of 913 is doubtful over GF(2), because it fits only the Q-only ⟨3,3,6⟩:40 (B.22).
The other six rest on catalogue claims (or catalogue stubs) that we did not rebuild.

### C.S1 superseded, verified scheme built by us

| shape | ours | class | prior | how (smallest first) | our chain |
|---|---|---|---|---|---|
| 3x14x18 | 561 | below_all | 560 | serendipitous product <3,7,9> x <1,2,2> of FMM 3x7x9_m141_076164eb11b2f..; bud blocks 1 x <3x1x2> | matmulcatalog replay -> walk |
| 3x14x27 | 842 | below_all | 840 | serendipitous product <3,7,9> x <1,2,3> of FMM 3x7x9_m141_db6384fced8e1..; bud blocks 2 x <3x1x1> | closure product |
| 4x5x14 | 206 | gf2_valid_only | 205 | composition: 4x5x14:205=(4x5x5:73[Arai 455:73] (+) 4x5x9:132[FMM-ZT]) | closure product |
| 4x5x15 | 220 | below_all | 219 | composition: 4x5x15:219=(4x5x5:73[Arai 455:73] (+) 4x5x10:146[FMM-ZT]) | closure product |
| 4x5x16 | 234 | below_all | 233 | composition: 4x5x16:233=(4x5x5:73[Arai 455:73] (+) 4x5x11:160[FMM-ZT]) | closure product |
| 4x5x27 | 394 | below_all | 393 | composition: 4x5x27:393=(4x5x5:73[Arai 455:73] (+) 4x5x22:320=(4x5x5:73[Arai 455:73] (+) 4x5x17:247=(4x5x5:73[Arai 455:73] (+) 4x5x12:174[FMM-ZT]))) | closure product |
| 4x5x28 | 408 | below_all | 407 | composition: 4x5x28:407=(4x5x5:73[Arai 455:73] (+) 4x5x23:334=(4x5x11:160[FMM-ZT] (+) 4x5x12:174[FMM-ZT])) | closure product |
| 4x11x24 | 720 | below_all | 716 | serendipitous product <2,3,11> x <2,8,1> of FMM 2x3x11_m55_f7a29b60b3ee9..; bud blocks 1 x <1x1x2>, 7 x <1x1x3>, 8 x <1x1x4> | matmulcatalog replay -> walk |
| 4x20x27 | 1384 | gf2_valid_only | 1375 | serendipitous product <2,4,9> x <2,5,3> of FMM 2x4x9_m58_00bb4c5b01ed5e..; bud blocks 24 x <1x1x2>, 1 x <2x1x1> | closure product |
| 4x26x32 | 2121 | below_all | 2112 | serendipitous product <2,4,13> x <2,8,2> of FMM 2x4x13_m84_e0fd00fee2bf6..; bud blocks 16 x <1x1x3>, 8 x <1x1x4> | closure product |
| 6x16x26 | 1533 | below_all | 1528 | serendipitous product <2,4,13> x <3,4,2> of FMM 2x4x13_m84_e0fd00fee2bf6..; bud blocks 16 x <1x1x3>, 8 x <1x1x4> | closure product |
| 6x20x20 | 1494 | below_all | 1485 | serendipitous product <3,5,10> x <2,4,2> of FMM 3x5x10_m115_a4e068d59342..; bud blocks 31 x <1x1x2>, 15 x <1x1x3>, 2 x <2x1x2> | matmulcatalog replay |
| 6x32x32 | 3701 | gf2_valid_only | 3690 | serendipitous product <3,4,16> x <2,8,2> of FMM 3x4x16_m147_99a01de9ddee..; bud blocks 15 x <1x1x2>, 39 x <1x1x3> | closure product |
| 7x7x7 | 247 | below_all | 245 | Medley et al. arXiv:2609.17533 App. A (F2) | live fleet checkpoint |
| 7x12x20 | 1088 | below_all | 1081 | serendipitous product <2,4,7> x <6,5,1> of FMM 2x4x7_m46_e09c7dfeefbf3e..; bud blocks 23 x <1x1x2> | July certificate -> projection -> walk |
| 7x14x20 | 1282 | below_all | 1265 | serendipitous product <2,4,7> x <7,5,1> of FMM 2x4x7_m46_e09c7dfeefbf3e..; bud blocks 23 x <1x1x2> | matmulcatalog replay -> projection -> walk |
| 7x20x21 | 1877 | below_all | 1846 | serendipitous product <3,4,7> x <7,5,1> of FMM 3x4x7_m68_afca9a1afadc0b..; bud blocks 20 x <1x1x2>, 9 x <1x1x3> | matmulcatalog replay -> walk |
| 8x8x15 | 632 | gf2_valid_only | 631 | composition: 8x8x15:631=(7x8x8:302=Strassen((3, 4), (4, 4), (4, 4))(4x4x4:47[AlphaTensor-F2], 3x4x4:38[AlphaTensor-F2], 4x4x4:47[AlphaTensor-F2], 3x4x4:38[AlphaTensor-F2], 4x4x4:47[AlphaTensor-F2], 3x4x4:38[AlphaTensor-F2], 4x4x4:47[AlphaTensor-F2]) (+) 8x8x8:329=(2x2x2:7[mmc] (x) 4x4x4:47[AlphaTensor-F2])) | closure product -> projection -> walk |
| 8x8x30 | 1225 | below_all | 1215 | serendipitous product <2,2,6> x <4,4,5> of FMM 2x2x6_m21_f0cb325cf2e6a7..; bud blocks 9 x <1x1x2> | closure product |
| 8x24x26 | 2932 | below_all | 2930 | serendipitous product <2,3,13> x <4,8,2> of FMM 2x3x13_m65_2b88a550754ac..; bud blocks 15 x <1x1x4>, 1 x <1x1x5> | closure product |
| 8x27x32 | 4024 | below_all | 4018 | serendipitous product <2,3,16> x <4,9,2> of FMM 2x3x16_m80_80f2e138a23b9..; bud blocks 1 x <1x1x3>, 1 x <1x1x4>, 11 x <1x1x5>, 3 x <1x1x6> | matmulcatalog replay -> walk |
| 8x32x32 | 4649 | gf2_valid_only | 4602 | serendipitous product <2,4,8> x <4,8,4> of FMM 2x4x8_m51_4f8823917d1632..; bud blocks 24 x <1x1x2> | matmulcatalog replay |
| 9x16x32 | 2742 | below_all | 2676 | serendipitous product <3,4,16> x <3,4,2> of FMM 3x4x16_m147_99a01de9ddee..; bud blocks 15 x <1x1x2>, 39 x <1x1x3> | matmulcatalog replay |
| 9x20x32 | 3393 | gf2_valid_only | 3357 | serendipitous product <3,4,16> x <3,5,2> of FMM 3x4x16_m147_99a01de9ddee..; bud blocks 15 x <1x1x2>, 39 x <1x1x3> | matmulcatalog replay |
| 10x11x21 | 1458 | gf2_valid_only | 1432 | serendipitous product <2,3,11> x <5,7,1> of FMM 2x3x11_m55_f59d3d4580ef7..; bud blocks 1 x <1x1x2>, 11 x <1x1x3>, 4 x <1x1x5> | matmulcatalog replay -> walk |
| 10x12x25 | 1836 | below_all | 1825 | composition: 10x12x25:1825=(2x3x5:25[HK71] (x) 4x5x5:73[Arai 455:73]) | committed certificate |
| 10x15x21 | 1900 | below_all | 1899 | serendipitous product <5,5,7> x <3,2,3> of FMM 5x5x7_m127_4eb22c620327f..; bud blocks 6 x <1x2x1> | matmulcatalog replay |
| 10x16x25 | 2412 | gf2_valid_only | 2409 | composition: 10x16x25:2409=(2x4x5:33[HK71] (x) 4x5x5:73[Arai 455:73]) | committed certificate -> projection -> walk |
| 10x18x24 | 2546 | below_all | 2540 | serendipitous product <5,6,8> x <2,3,3> of FMM 5x6x8_m170_69e0daa26da5e..; bud blocks 4 x <2x1x1>, 1 x <2x1x2> | matmulcatalog replay |
| 10x18x25 | 2687 | below_all | 2655 | serendipitous product <3,5,10> x <6,5,1> of FMM 3x5x10_m115_58c6134ed31e..; bud blocks 31 x <1x1x2>, 15 x <1x1x3>, 2 x <1x1x4> | matmulcatalog replay -> walk |
| 10x24x26 | 3696 | gf2_valid_only | 3628 | serendipitous product <2,4,13> x <5,6,2> of FMM 2x4x13_m84_e0fd00fee2bf6..; bud blocks 16 x <1x1x3>, 8 x <1x1x4> | closure product |
| 10x24x27 | 3797 | below_all | 3770 | serendipitous product <2,4,9> x <5,6,3> of FMM 2x4x9_m58_02bdf2eacce8f4..; bud blocks 18 x <1x1x2>, 6 x <1x1x3> | matmulcatalog replay -> walk |
| 10x27x28 | 4435 | below_all | 4390 | serendipitous product <2,4,9> x <5,7,3> of FMM 2x4x9_m58_00bb4c5b01ed5e..; bud blocks 24 x <1x1x2> | matmulcatalog replay -> projection -> walk |
| 10x27x30 | 4752 | below_all | 4748 | serendipitous product <2,5,9> x <5,6,3> of FMM 2x5x9_m73_47f39587c21563..; bud blocks 23 x <1x1x2>, 2 x <1x1x3>, 4 x <1x1x4> | matmulcatalog replay |
| 10x28x28 | 4537 | below_all | 4524 | serendipitous product <5,7,7> x <2,4,4> of FMM 5x7x7_m176_fa24218eda7a1..; bud blocks 4 x <1x1x2>, 3 x <1x2x1>, 7 x <2x1x1>, 1 x <4x1x1> | matmulcatalog replay |
| 11x14x20 | 1920 | below_all | 1896 | serendipitous product <2,4,11> x <7,5,1> of FMM 2x4x11_m72_c1ded329417b6..; bud blocks 4 x <1x1x2>, 18 x <1x1x3>, 2 x <1x1x5> | July certificate -> projection -> walk |
| 11x16x21 | 2221 | below_all | 2216 | serendipitous product <3,4,11> x <7,4,1> of FMM 3x4x11_m104_075e9ae9269f..; bud blocks 1 x <1x1x2>, 14 x <1x1x3>, 15 x <1x1x4> | committed certificate |
| 11x16x30 | 3105 | below_all | 3077 | serendipitous product <3,4,11> x <10,4,1> of FMM 3x4x11_m104_075e9ae9269f..; bud blocks 1 x <1x1x2>, 14 x <1x1x3>, 15 x <1x1x4> | committed certificate |
| 11x21x32 | 4362 | below_all | 4295 | serendipitous product <3,4,11> x <7,8,1> of FMM 3x4x11_m104_075e9ae9269f..; bud blocks 1 x <1x1x2>, 14 x <1x1x3>, 15 x <1x1x4> | closure product -> projection -> walk |
| 11x24x32 | 4866 | below_all | 4830 | serendipitous product <3,4,11> x <8,8,1> of FMM 3x4x11_m104_075e9ae9269f..; bud blocks 1 x <1x1x2>, 14 x <1x1x3>, 15 x <1x1x4> | closure product |
| 11x27x28 | 4889 | below_all | 4878 | serendipitous product <3,4,11> x <9,7,1> of FMM 3x4x11_m104_075e9ae9269f..; bud blocks 1 x <1x1x2>, 14 x <1x1x3>, 15 x <1x1x4> | July certificate -> projection |
| 12x13x28 | 2596 | below_all | 2583 | serendipitous product <3,4,13> x <4,7,1> of FMM 3x4x13_m123_f0956bad0813..; bud blocks 12 x <1x1x3>, 3 x <1x1x4>, 15 x <1x1x5> | closure product |
| 12x13x32 | 2952 | below_all | 2928 | serendipitous product <3,4,13> x <4,8,1> of FMM 3x4x13_m123_f0956bad0813..; bud blocks 12 x <1x1x3>, 3 x <1x1x4>, 15 x <1x1x5> | closure product |
| 12x15x20 | 2121 | below_all | 2117 | composition: 12x15x20:2117=(3x3x4:29[AlphaTensor-F2] (x) 4x5x5:73[Arai 455:73]) | July certificate |
| 12x20x25 | 3436 | below_all | 3431 | composition: 12x20x25:3431=(3x4x5:47[AlphaTensor-F2] (x) 4x5x5:73[Arai 455:73]) | closure product |
| 12x20x30 | 4031 | below_all | 3942 | composition: 12x20x30:3942=(3x4x6:54[Perminov-ZT] (x) 4x5x5:73[Arai 455:73]) | closure product -> projection -> walk |
| 13x15x20 | 2321 | below_all | 2310 | serendipitous product <3,4,13> x <5,5,1> of FMM 3x4x13_m123_f0956bad0813..; bud blocks 12 x <1x1x3>, 3 x <1x1x4>, 15 x <1x1x5> | July certificate |
| 13x15x22 | 2595 | below_all | 2592 | serendipitous product <2,3,13> x <11,5,1> of FMM 2x3x13_m65_168e89abc94ef..; bud blocks 1 x <1x1x2>, 12 x <1x1x4>, 3 x <1x1x5> | committed certificate -> projection -> walk |
| 13x16x18 | 2250 | below_all | 2202 | serendipitous product <3,4,13> x <6,4,1> of FMM 3x4x13_m123_f0956bad0813..; bud blocks 12 x <1x1x3>, 3 x <1x1x4>, 15 x <1x1x5> | closure product |
| 13x16x30 | 3658 | below_all | 3623 | serendipitous product <3,4,13> x <10,4,1> of FMM 3x4x13_m123_1fbde9a51611..; bud blocks 10 x <1x1x3>, 7 x <1x1x4>, 13 x <1x1x5> | closure product |
| 13x19x21 | 3153 | below_all | 3147 | composition: 13x19x21:3147=Strassen((6, 7), (9, 10), (10, 11))(7x10x11:518=Strassen((3, 4), (5, 5), (5, 6))(4x5x6:89[KW-Z2 456], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x6:89[KW-Z2 456]), 6x10x11:446[FMM-ZT], 7x10x10:466=Strassen((3, 4), (5, 5), (5, 5))(4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x5:73[Arai 455:73]), 6x9x11:407[FMM-Z], 7x9x10:429=Strassen((3, 4), (4, 5), (5, 5))(4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x5:73[Arai 455:73], 3x4x5:47[AlphaTensor-F2], 4x4x5:60[KM-F2], 3x5x5:58[AlphaTensor-F2], 4x4x5:60[KM-F2]), 6x10x10:406=(2x2x2:7[mmc] (x) 3x5x5:58[AlphaTensor-F2]), 7x9x11:475=Strassen((3, 4), (4, 5), (5, 6))(4x5x6:89[KW-Z2 456], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x4x6:54[Perminov-ZT], 4x4x5:60[KM-F2], 3x5x5:58[AlphaTensor-F2], 4x4x6:73[Perminov-ZT])) | closure product |
| 13x19x22 | 3286 | below_all | 3285 | composition: 13x19x22:3285=Strassen((6, 7), (9, 10), (11, 11))(7x10x11:518=Strassen((3, 4), (5, 5), (5, 6))(4x5x6:89[KW-Z2 456], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x6:89[KW-Z2 456]), 6x10x11:446[FMM-ZT], 7x10x11:518=Strassen((3, 4), (5, 5), (5, 6))(4x5x6:89[KW-Z2 456], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x6:89[KW-Z2 456]), 6x9x11:407[FMM-Z], 7x9x11:475=Strassen((3, 4), (4, 5), (5, 6))(4x5x6:89[KW-Z2 456], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x4x6:54[Perminov-ZT], 4x4x5:60[KM-F2], 3x5x5:58[AlphaTensor-F2], 4x4x6:73[Perminov-ZT]), 6x10x11:446[FMM-ZT], 7x9x11:475=Strassen((3, 4), (4, 5), (5, 6))(4x5x6:89[KW-Z2 456], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x4x6:54[Perminov-ZT], 4x4x5:60[KM-F2], 3x5x5:58[AlphaTensor-F2], 4x4x6:73[Perminov-ZT])) | closure product |
| 13x20x21 | 3274 | below_all | 3165 | serendipitous product <3,4,13> x <7,5,1> of FMM 3x4x13_m123_f0956bad0813..; bud blocks 12 x <1x1x3>, 3 x <1x1x4>, 15 x <1x1x5> | closure product |
| 13x20x22 | 3414 | below_all | 3410 | composition: 13x20x22:3410=Strassen((6, 7), (10, 10), (11, 11))(7x10x11:518=Strassen((3, 4), (5, 5), (5, 6))(4x5x6:89[KW-Z2 456], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x6:89[KW-Z2 456]), 6x10x11:446[FMM-ZT], 7x10x11:518=Strassen((3, 4), (5, 5), (5, 6))(4x5x6:89[KW-Z2 456], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x6:89[KW-Z2 456]), 6x10x11:446[FMM-ZT], 7x10x11:518=Strassen((3, 4), (5, 5), (5, 6))(4x5x6:89[KW-Z2 456], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x6:89[KW-Z2 456]), 6x10x11:446[FMM-ZT], 7x10x11:518=Strassen((3, 4), (5, 5), (5, 6))(4x5x6:89[KW-Z2 456], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x5x6:68[AlphaEvolve], 4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x6:89[KW-Z2 456])) | closure product |
| 13x20x27 | 4075 | below_all | 4035 | serendipitous product <3,4,13> x <9,5,1> of FMM 3x4x13_m123_f0956bad0813..; bud blocks 12 x <1x1x3>, 3 x <1x1x4>, 15 x <1x1x5> | committed certificate |
| 13x32x32 | 7502 | below_all | 7450 | serendipitous product <2,2,13> x <16,16,1> of FMM 2x2x13_m47_caa900503e2e5..; bud blocks 1 x <1x1x5>, 3 x <1x1x6>, 3 x <1x1x8> | closure product -> projection -> walk |
| 15x15x21 | 2793 | gf2_valid_only | 2782 | serendipitous product <3,3,7> x <5,5,3> of FMM 3x3x7_m49_6b28e31f65936b..; bud blocks 10 x <1x1x2> | matmulcatalog replay -> walk |
| 15x16x25 | 3457 | below_all | 3431 | composition: 15x16x25:3431=(3x4x5:47[AlphaTensor-F2] (x) 4x5x5:73[Arai 455:73]) | closure product |
| 15x16x31 | 4211 | below_all | 4182 | composition: 15x16x31:4182=(1x15x16:240[naive] (+) 15x16x30:3942=(3x4x6:54[Perminov-ZT] (x) 4x5x5:73[Arai 455:73])) | closure product |
| 15x19x19 | 3225 | below_all | 3210 | composition: 15x19x19:3210=Strassen((7, 8), (9, 10), (9, 10))(8x10x10:511=(2x2x2:7[mmc] (x) 4x5x5:73[Arai 455:73]), 7x10x10:466=Strassen((3, 4), (5, 5), (5, 5))(4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x5:73[Arai 455:73]), 8x9x9:432[FMM-ZT], 7x9x10:429=Strassen((3, 4), (4, 5), (5, 5))(4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x5:73[Arai 455:73], 3x4x5:47[AlphaTensor-F2], 4x4x5:60[KM-F2], 3x5x5:58[AlphaTensor-F2], 4x4x5:60[KM-F2]), 8x10x10:511=(2x2x2:7[mmc] (x) 4x5x5:73[Arai 455:73]), 7x9x10:429=Strassen((3, 4), (4, 5), (5, 5))(4x5x5:73[Arai 455:73], 3x5x5:58[AlphaTensor-F2], 4x5x5:73[Arai 455:73], 3x4x5:47[AlphaTensor-F2], 4x4x5:60[KM-F2], 3x5x5:58[AlphaTensor-F2], 4x4x5:60[KM-F2]), 8x9x9:432[FMM-ZT]) | July certificate |
| 15x20x32 | 5400 | below_all | 5329 | composition: 15x20x32:5329=(3x4x8:73[Perminov-ZT] (x) 4x5x5:73[Arai 455:73]) | closure product |
| 16x19x22 | 3892 | below_all | 3863 | composition: 16x19x22:3863=Strassen((8, 8), (9, 10), (11, 11))(8x10x11:575=Strassen((4, 4), (5, 5), (5, 6))(4x5x6:89[KW-Z2 456], 4x5x6:89[KW-Z2 456], 4x5x5:73[Arai 455:73], 4x5x6:89[KW-Z2 456], 4x5x5:73[Arai 455:73], 4x5x5:73[Arai 455:73], 4x5x6:89[KW-Z2 456]), 8x10x11:575=Strassen((4, 4), (5, 5), (5, 6))(4x5x6:89[KW-Z2 456], 4x5x6:89[KW-Z2 456], 4x5x5:73[Arai 455:73], 4x5x6:89[KW-Z2 456], 4x5x5:73[Arai 455:73], 4x5x5:73[Arai 455:73], 4x5x6:89[KW-Z2 456]), 8x10x11:575=Strassen((4, 4), (5, 5), (5, 6))(4x5x6:89[KW-Z2 456], 4x5x6:89[KW-Z2 456], 4x5x5:73[Arai 455:73], 4x5x6:89[KW-Z2 456], 4x5x5:73[Arai 455:73], 4x5x5:73[Arai 455:73], 4x5x6:89[KW-Z2 456]), 8x9x11:521[FMM-ZT], 8x9x11:521[FMM-ZT], 8x10x11:575=Strassen((4, 4), (5, 5), (5, 6))(4x5x6:89[KW-Z2 456], 4x5x6:89[KW-Z2 456], 4x5x5:73[Arai 455:73], 4x5x6:89[KW-Z2 456], 4x5x5:73[Arai 455:73], 4x5x5:73[Arai 455:73], 4x5x6:89[KW-Z2 456]), 8x9x11:521[FMM-ZT]) | closure product |
| 16x20x20 | 3572 | below_all | 3431 | composition: 16x20x20:3431=(4x4x4:47[AlphaTensor-F2] (x) 4x5x5:73[Arai 455:73]) | July certificate |
| 16x20x21 | 3840 | below_all | 3751 | composition: 16x20x21:3751=(1x16x20:320[naive] (+) 16x20x20:3431=(4x4x4:47[AlphaTensor-F2] (x) 4x5x5:73[Arai 455:73])) | closure product -> projection -> walk |
| 16x20x22 | 3976 | below_all | 3925 | composition: 16x20x22:3925=(2x16x20:494=(2x5x16:126[FMM-Z] (+) 2x15x16:368[FMM-Z]) (+) 16x20x20:3431=(4x4x4:47[AlphaTensor-F2] (x) 4x5x5:73[Arai 455:73])) | closure product -> projection -> walk |
| 16x20x24 | 4230 | below_all | 4183 | composition: 16x20x24:4183=(4x4x4:47[AlphaTensor-F2] (x) 4x5x6:89[KW-Z2 456]) | closure product |
| 16x20x25 | 4470 | below_all | 4380 | composition: 16x20x25:4380=(4x4x5:60[KM-F2] (x) 4x5x5:73[Arai 455:73]) | matmulcatalog replay |
| 16x20x30 | 5335 | below_all | 5329 | composition: 16x20x30:5329=(10x16x20:1898=(2x4x4:26[HK71] (x) 4x5x5:73[Arai 455:73]) (+) 16x20x20:3431=(4x4x4:47[AlphaTensor-F2] (x) 4x5x5:73[Arai 455:73])) | closure product -> projection -> walk |
| 16x23x31 | 6355 | below_all | 6344 | composition: 16x23x31:6344=Strassen((8, 8), (11, 12), (15, 16))(8x12x16:940=(2x3x4:20[HK71] (x) 4x4x4:47[AlphaTensor-F2]), 8x12x15:900=(2x3x3:15[HK71] (x) 4x4x5:60[KM-F2]), 8x12x16:940=(2x3x4:20[HK71] (x) 4x4x4:47[AlphaTensor-F2]), 8x11x15:859[FMM-ZT], 8x11x16:906[fmm-schemes], 8x12x16:940=(2x3x4:20[HK71] (x) 4x4x4:47[AlphaTensor-F2]), 8x11x15:859[FMM-ZT]) | closure product -> projection -> walk |
| 16x24x31 | 6487 | below_all | 6460 | composition: 16x24x31:6460=Strassen((8, 8), (12, 12), (15, 16))(8x12x16:940=(2x3x4:20[HK71] (x) 4x4x4:47[AlphaTensor-F2]), 8x12x16:940=(2x3x4:20[HK71] (x) 4x4x4:47[AlphaTensor-F2]), 8x12x15:900=(2x3x3:15[HK71] (x) 4x4x5:60[KM-F2]), 8x12x16:940=(2x3x4:20[HK71] (x) 4x4x4:47[AlphaTensor-F2]), 8x12x15:900=(2x3x3:15[HK71] (x) 4x4x5:60[KM-F2]), 8x12x15:900=(2x3x3:15[HK71] (x) 4x4x5:60[KM-F2]), 8x12x16:940=(2x3x4:20[HK71] (x) 4x4x4:47[AlphaTensor-F2])) | closure product -> projection -> walk |
| 16x25x28 | 6223 | below_all | 6218 | composition: 16x25x28:6218=(3x16x25:889=(3x10x16:355[FMM-ZT] (+) 3x15x16:534[FMM-ZT]) (+) 16x25x25:5329=(4x5x5:73[Arai 455:73] (x) 4x5x5:73[Arai 455:73])) | committed certificate |
| 16x25x31 | 6873 | below_all | 6829 | composition: 16x25x31:6829=(6x16x25:1500=(1x6x16:96[naive] (+) 6x16x24:1404=(2x4x4:26[HK71] (x) 3x4x6:54[Perminov-ZT])) (+) 16x25x25:5329=(4x5x5:73[Arai 455:73] (x) 4x5x5:73[Arai 455:73])) | closure product -> projection -> walk |
| 16x26x30 | 6923 | gf2_valid_only | 6878 | serendipitous product <3,4,13> x <10,4,2> of FMM 3x4x13_m119_4fbf255e27f0..; bud blocks 45 x <1x1x2>, 9 x <1x1x3> | closure product |
| 16x31x31 | 8294 | below_all | 8256 | composition: 16x31x31:8256=Strassen((8, 8), (15, 16), (15, 16))(8x16x16:1222=(2x4x4:26[HK71] (x) 4x4x4:47[AlphaTensor-F2]), 8x15x16:1200=(2x3x4:20[HK71] (x) 4x4x5:60[KM-F2]), 8x16x16:1222=(2x4x4:26[HK71] (x) 4x4x4:47[AlphaTensor-F2]), 8x15x15:1095=(2x3x3:15[HK71] (x) 4x5x5:73[Arai 455:73]), 8x15x16:1200=(2x3x4:20[HK71] (x) 4x4x5:60[KM-F2]), 8x16x16:1222=(2x4x4:26[HK71] (x) 4x4x4:47[AlphaTensor-F2]), 8x15x15:1095=(2x3x3:15[HK71] (x) 4x5x5:73[Arai 455:73])) | closure product -> projection -> walk |
| 17x20x20 | 3844 | below_all | 3831 | composition: 17x20x20:3831=(1x20x20:400[naive] (+) 16x20x20:3431=(4x4x4:47[AlphaTensor-F2] (x) 4x5x5:73[Arai 455:73])) | July certificate |
| 20x20x20 | 4451 | gf2_valid_only | 4371 | composition: 20x20x20:4371=(4x4x4:47[AlphaTensor-F2] (x) 5x5x5:93[Perminov-ZT]) | July certificate -> projection |
| 20x20x24 | 5202 | gf2_valid_only | 5170 | composition: 20x20x24:5170=(4x4x4:47[AlphaTensor-F2] (x) 5x5x6:110[Perminov-ZT]) | July certificate -> projection |
| 20x20x25 | 5442 | gf2_valid_only | 5329 | composition: 20x20x25:5329=(4x5x5:73[Arai 455:73] (x) 4x5x5:73[Arai 455:73]) | July certificate |
| 20x25x32 | 8630 | below_all | 8614 | composition: 20x25x32:8614=(4x5x8:118[Perminov-ZT] (x) 4x5x5:73[Arai 455:73]) | closure product |
| 25x30x32 | 12665 | gf2_valid_only | 12410 | composition: 25x30x32:12410=(4x5x5:73[Arai 455:73] (x) 5x6x8:170[Perminov-ZT]) | July certificate -> projection -> walk |

### C.S2 superseded, rank claim only

| shape | ours | class | prior | how (smallest first) | our chain |
|---|---|---|---|---|---|
| 4x14x20 | 753 | gf2_valid_only | 736 | matmulcatalog cited-bounds (Perminov 2026 (serendipitous); Z; no factor matrices) | matmulcatalog replay -> walk |
| 9x9x18 | 915 | below_all | 913 | matmulcatalog cited-bounds (Perminov 2026 (serendipitous); Z; no factor matrices) | matmulcatalog replay |
| 11x16x27 | 2825 | below_all | 2780 | matmulcatalog cited-bounds (Perminov 2026 (serendipitous); Z; no factor matrices) | committed certificate |
| 12x22x24 | 3601 | below_all | 3567 | composition of listed / published GF(2) ranks (L2S): 12x22x24:3567=(6x12x24:1029[matmulcatalog:unknown] (+) 12x16x24:2538=(3x4x6:54[matmulcatalog:Kauers & Wood 2025 / FMM:ZT / arXiv:2511.20317 Table 5 (best known, as listed) line 804 (Z)] (x) 4x4x4:47[matmulcatalog:AlphaTensor / arXiv:2210.04045 in text line 28 (ring R of characteristic 2) / arXiv:221 | committed certificate |
| 12x24x25 | 4080 | below_all | 4053 | composition of listed / published GF(2) ranks (L2S): 12x24x25:4053=(9x12x24:1515[matmulcatalog:unknown] (+) 12x16x24:2538=(3x4x6:54[matmulcatalog:Kauers & Wood 2025 / FMM:ZT / arXiv:2511.20317 Table 5 (best known, as listed) line 804 (Z)] (x) 4x4x4:47[matmulcatalog:AlphaTensor / arXiv:2210.04045 in text line 28 (ring R of characteristic 2) / arXiv:221 | closure product |
| 13x16x21 | 2582 | below_all | 2571 | matmulcatalog cited-bounds (Perminov 2026 (serendipitous); Z; no factor matrices) | committed certificate -> projection -> walk |
| 16x19x30 | 5206 | below_all | 5199 | composition of listed / published GF(2) ranks (L2S): 16x19x30:5199=(4x16x30:1257=(2x4x16:102[matmulcatalog:FMM-Lille / arXiv:2512.13365 Table 1 line 497 (ZT = {-1,0,1} (ternary; valid over any r)] (+) 4x16x28:1155[matmulcatalog:unknown]) (+) 15x16x30:3942=(3x4x6:54[matmulcatalog:Kauers & Wood 2025 / FMM:ZT / arXiv:2511.20317 Table 5 (best known, as li | closure product |

### C.M1 matched, verified

| shape | ours | class | prior | how (smallest first) | our chain |
|---|---|---|---|---|---|
| 2x4x17 | 109 | gf2_valid_only | 109 | composition: 2x4x17:109=(2x4x4:26[HK71] (+) 2x4x13:83[FMM-ZT]) | closure product |
| 2x4x18 | 115 | gf2_valid_only | 115 | composition: 2x4x18:115=(2x4x7:45[Perminov-ZT] (+) 2x4x11:70[FMM-ZT]) | closure product |
| 2x4x20 | 128 | gf2_valid_only | 128 | composition: 2x4x20:128=(2x4x4:26[HK71] (+) 2x4x16:102=(2x4x8:51[AlphaEvolve] (+) 2x4x8:51[AlphaEvolve])) | closure product |
| 2x4x21 | 134 | gf2_valid_only | 134 | composition: 2x4x21:134=(2x4x8:51[AlphaEvolve] (+) 2x4x13:83[FMM-ZT]) | closure product |
| 2x4x24 | 153 | gf2_valid_only | 153 | composition: 2x4x24:153=(2x4x8:51[AlphaEvolve] (+) 2x4x16:102=(2x4x8:51[AlphaEvolve] (+) 2x4x8:51[AlphaEvolve])) | closure product |
| 2x4x27 | 172 | gf2_valid_only | 172 | composition: 2x4x27:172=(2x4x8:51[AlphaEvolve] (+) 2x4x19:121=(2x4x8:51[AlphaEvolve] (+) 2x4x11:70[FMM-ZT])) | closure product |
| 2x4x28 | 179 | gf2_valid_only | 179 | composition: 2x4x28:179=(2x4x4:26[HK71] (+) 2x4x24:153=(2x4x8:51[AlphaEvolve] (+) 2x4x16:102=(2x4x8:51[AlphaEvolve] (+) 2x4x8:51[AlphaEvolve]))) | closure product |
| 2x4x29 | 185 | gf2_valid_only | 185 | composition: 2x4x29:185=(2x4x7:45[Perminov-ZT] (+) 2x4x22:140=(2x4x11:70[FMM-ZT] (+) 2x4x11:70[FMM-ZT])) | closure product |
| 2x4x31 | 198 | gf2_valid_only | 198 | composition: 2x4x31:198=(2x4x4:26[HK71] (+) 2x4x27:172=(2x4x8:51[AlphaEvolve] (+) 2x4x19:121=(2x4x8:51[AlphaEvolve] (+) 2x4x11:70[FMM-ZT]))) | closure product |
| 2x4x32 | 204 | gf2_valid_only | 204 | composition: 2x4x32:204=(2x4x8:51[AlphaEvolve] (+) 2x4x24:153=(2x4x8:51[AlphaEvolve] (+) 2x4x16:102=(2x4x8:51[AlphaEvolve] (+) 2x4x8:51[AlphaEvolve]))) | closure product |
| 2x5x17 | 134 | gf2_valid_only | 134 | composition: 2x5x17:134=(2x5x5:40[HK71] (+) 2x5x12:94=(2x5x6:47[AlphaEvolve] (+) 2x5x6:47[AlphaEvolve])) | closure product |
| 2x5x22 | 173 | gf2_valid_only | 173 | composition: 2x5x22:173=(2x5x6:47[AlphaEvolve] (+) 2x5x16:126[FMM-Z]) | closure product |
| 2x5x23 | 181 | gf2_valid_only | 181 | composition: 2x5x23:181=(2x5x5:40[HK71] (+) 2x5x18:141=(2x5x6:47[AlphaEvolve] (+) 2x5x12:94=(2x5x6:47[AlphaEvolve] (+) 2x5x6:47[AlphaEvolve]))) | closure product |
| 2x5x28 | 220 | gf2_valid_only | 220 | composition: 2x5x28:220=(2x5x6:47[AlphaEvolve] (+) 2x5x22:173=(2x5x6:47[AlphaEvolve] (+) 2x5x16:126[FMM-Z])) | closure product |
| 2x5x29 | 228 | gf2_valid_only | 228 | composition: 2x5x29:228=(2x5x5:40[HK71] (+) 2x5x24:188=(2x5x6:47[AlphaEvolve] (+) 2x5x18:141=(2x5x6:47[AlphaEvolve] (+) 2x5x12:94=(2x5x6:47[AlphaEvolve] (+) 2x5x6:47[AlphaEvolve])))) | closure product |
| 4x4x8 | 94 | below_all | 94 | composition: 4x4x8:94=(4x4x4:47[AlphaTensor-F2] (+) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 4x4x14 | 162 | below_all | 162 | composition: 4x4x14:162=(4x4x4:47[AlphaTensor-F2] (+) 4x4x10:115[FMM-ZT]) | closure product |
| 4x4x15 | 175 | below_all | 175 | composition: 4x4x15:175=(4x4x5:60[KM-F2] (+) 4x4x10:115[FMM-ZT]) | closure product |
| 4x4x24 | 277 | below_all | 277 | composition: 4x4x24:277=(4x4x4:47[AlphaTensor-F2] (+) 4x4x20:230=(4x4x10:115[FMM-ZT] (+) 4x4x10:115[FMM-ZT])) | closure product |
| 4x4x25 | 290 | below_all | 290 | composition: 4x4x25:290=(4x4x5:60[KM-F2] (+) 4x4x20:230=(4x4x10:115[FMM-ZT] (+) 4x4x10:115[FMM-ZT])) | closure product |
| 4x15x27 | 1065 | below_all | 1065 | serendipitous product <2,3,9> x <2,5,3> of FMM 2x3x9_m45_6ae2c908a899e4..; bud blocks 16 x <1x1x2>, 2 x <1x1x4> | matmulcatalog replay -> walk |
| 4x27x30 | 2033 | below_all | 2033 | serendipitous product <2,6,9> x <2,5,3> of FMM 2x6x9_m86_e4fd94c67073c6..; bud blocks 39 x <1x1x2> | matmulcatalog replay |
| 8x8x9 | 381 | below_all | 381 | composition: 8x8x9:381=Strassen((4, 4), (4, 4), (4, 5))(4x4x5:60[KM-F2], 4x4x5:60[KM-F2], 4x4x4:47[AlphaTensor-F2], 4x4x5:60[KM-F2], 4x4x4:47[AlphaTensor-F2], 4x4x4:47[AlphaTensor-F2], 4x4x5:60[KM-F2]) | closure product -> projection |
| 8x8x10 | 420 | below_all | 420 | composition: 8x8x10:420=(2x2x2:7[mmc] (x) 4x4x5:60[KM-F2]) | closure product |
| 8x8x16 | 658 | below_all | 658 | composition: 8x8x16:658=(8x8x8:329=(2x2x2:7[mmc] (x) 4x4x4:47[AlphaTensor-F2]) (+) 8x8x8:329=(2x2x2:7[mmc] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 8x8x27 | 1107 | below_all | 1107 | composition: 8x8x27:1107=(7x8x8:302=Strassen((3, 4), (4, 4), (4, 4))(4x4x4:47[AlphaTensor-F2], 3x4x4:38[AlphaTensor-F2], 4x4x4:47[AlphaTensor-F2], 3x4x4:38[AlphaTensor-F2], 4x4x4:47[AlphaTensor-F2], 3x4x4:38[AlphaTensor-F2], 4x4x4:47[AlphaTensor-F2]) (+) 8x8x20:805=(2x2x2:7[mmc] (x) 4x4x10:115[FMM-ZT])) | closure product -> projection -> walk |
| 8x8x28 | 1134 | below_all | 1134 | composition: 8x8x28:1134=(8x8x8:329=(2x2x2:7[mmc] (x) 4x4x4:47[AlphaTensor-F2]) (+) 8x8x20:805=(2x2x2:7[mmc] (x) 4x4x10:115[FMM-ZT])) | closure product |
| 8x8x29 | 1186 | below_all | 1186 | composition: 8x8x29:1186=(8x8x9:381=Strassen((4, 4), (4, 4), (4, 5))(4x4x5:60[KM-F2], 4x4x5:60[KM-F2], 4x4x4:47[AlphaTensor-F2], 4x4x5:60[KM-F2], 4x4x4:47[AlphaTensor-F2], 4x4x4:47[AlphaTensor-F2], 4x4x5:60[KM-F2]) (+) 8x8x20:805=(2x2x2:7[mmc] (x) 4x4x10:115[FMM-ZT])) | closure product -> projection |
| 8x12x12 | 705 | below_all | 705 | composition: 8x12x12:705=(2x3x3:15[HK71] (x) 4x4x4:47[AlphaTensor-F2]) | committed certificate |
| 8x12x16 | 940 | below_all | 940 | composition: 8x12x16:940=(2x3x4:20[HK71] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 8x12x17 | 1036 | below_all | 1036 | composition: 8x12x17:1036=(1x8x12:96[naive] (+) 8x12x16:940=(2x3x4:20[HK71] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 8x12x20 | 1175 | below_all | 1175 | composition: 8x12x20:1175=(2x3x5:25[HK71] (x) 4x4x4:47[AlphaTensor-F2]) | July certificate |
| 8x16x16 | 1222 | below_all | 1222 | composition: 8x16x16:1222=(2x4x4:26[HK71] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 8x16x17 | 1350 | below_all | 1350 | composition: 8x16x17:1350=(1x8x16:128[naive] (+) 8x16x16:1222=(2x4x4:26[HK71] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 8x16x18 | 1422 | below_all | 1422 | composition: 8x16x18:1422=(2x8x16:200=(2x6x8:75[Perminov-ZT] (+) 2x8x10:125[FMM-ZT]) (+) 8x16x16:1222=(2x4x4:26[HK71] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 8x16x24 | 1833 | below_all | 1833 | composition: 8x16x24:1833=(2x4x6:39[HK71] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 8x16x28 | 2115 | below_all | 2115 | composition: 8x16x28:2115=(2x4x7:45[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 8x16x29 | 2243 | below_all | 2243 | composition: 8x16x29:2243=(1x8x16:128[naive] (+) 8x16x28:2115=(2x4x7:45[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 8x16x32 | 2397 | below_all | 2397 | composition: 8x16x32:2397=(2x4x8:51[AlphaEvolve] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 8x18x27 | 2334 | below_all | 2334 | serendipitous product <2,6,9> x <4,3,3> of FMM 2x6x9_m86_e4fd94c67073c6..; bud blocks 39 x <1x1x2>, 1 x <1x2x1> | matmulcatalog replay |
| 8x20x20 | 1880 | below_all | 1880 | composition: 8x20x20:1880=(2x5x5:40[HK71] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 8x20x21 | 2040 | below_all | 2040 | composition: 8x20x21:2040=(1x8x20:160[naive] (+) 8x20x20:1880=(2x5x5:40[HK71] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 8x20x24 | 2209 | below_all | 2209 | composition: 8x20x24:2209=(2x5x6:47[AlphaEvolve] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 8x20x25 | 2369 | below_all | 2369 | composition: 8x20x25:2369=(1x8x20:160[naive] (+) 8x20x24:2209=(2x5x6:47[AlphaEvolve] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 8x20x26 | 2459 | below_all | 2459 | composition: 8x20x26:2459=(2x8x20:250=(2x6x8:75[Perminov-ZT] (+) 2x8x14:175[FMM-Z]) (+) 8x20x24:2209=(2x5x6:47[AlphaEvolve] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 8x20x28 | 2585 | below_all | 2585 | composition: 8x20x28:2585=(2x5x7:55[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 8x20x30 | 2820 | below_all | 2820 | composition: 8x20x30:2820=(2x5x6:47[AlphaEvolve] (x) 4x4x5:60[KM-F2]) | closure product |
| 8x20x32 | 2961 | below_all | 2961 | composition: 8x20x32:2961=(2x5x8:63[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 8x21x24 | 2401 | below_all | 2401 | composition: 8x21x24:2401=(1x8x24:192[naive] (+) 8x20x24:2209=(2x5x6:47[AlphaEvolve] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 8x21x28 | 2809 | below_all | 2809 | composition: 8x21x28:2809=(1x8x28:224[naive] (+) 8x20x28:2585=(2x5x7:55[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 8x22x24 | 2509 | below_all | 2509 | composition: 8x22x24:2509=(2x8x24:300=(2x6x8:75[Perminov-ZT] (+) 2x8x18:225=(2x6x8:75[Perminov-ZT] (+) 2x8x12:150[FMM-ZT])) (+) 8x20x24:2209=(2x5x6:47[AlphaEvolve] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 8x24x24 | 2632 | below_all | 2632 | composition: 8x24x24:2632=(2x6x6:56[KM-F2] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 8x24x25 | 2820 | below_all | 2820 | composition: 8x24x25:2820=(2x5x6:47[AlphaEvolve] (x) 4x4x5:60[KM-F2]) | closure product |
| 8x24x28 | 3102 | below_all | 3102 | composition: 8x24x28:3102=(2x6x7:66[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 8x24x32 | 3525 | below_all | 3525 | composition: 8x24x32:3525=(2x6x8:75[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 8x25x28 | 3300 | below_all | 3300 | composition: 8x25x28:3300=(2x5x7:55[Perminov-ZT] (x) 4x4x5:60[KM-F2]) | closure product |
| 8x28x28 | 3572 | below_all | 3572 | composition: 8x28x28:3572=(2x7x7:76[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 8x28x29 | 3796 | below_all | 3796 | composition: 8x28x29:3796=(1x8x28:224[naive] (+) 8x28x28:3572=(2x7x7:76[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 10x12x12 | 900 | gf2_valid_only | 900 | composition: 10x12x12:900=(2x3x3:15[HK71] (x) 4x4x5:60[KM-F2]) | closure product |
| 12x12x16 | 1363 | below_all | 1363 | composition: 12x12x16:1363=(3x3x4:29[AlphaTensor-F2] (x) 4x4x4:47[AlphaTensor-F2]) | July certificate |
| 12x12x20 | 1692 | below_all | 1692 | composition: 12x12x20:1692=(3x3x5:36[AlphaTensor-F2] (x) 4x4x4:47[AlphaTensor-F2]) | July certificate |
| 12x12x28 | 2303 | below_all | 2303 | composition: 12x12x28:2303=(3x3x7:49[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 12x12x32 | 2632 | below_all | 2632 | composition: 12x12x32:2632=(3x3x8:56[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 12x16x16 | 1786 | below_all | 1786 | composition: 12x16x16:1786=(3x4x4:38[AlphaTensor-F2] (x) 4x4x4:47[AlphaTensor-F2]) | July certificate |
| 12x16x20 | 2209 | below_all | 2209 | composition: 12x16x20:2209=(3x4x5:47[AlphaTensor-F2] (x) 4x4x4:47[AlphaTensor-F2]) | July certificate |
| 12x16x24 | 2538 | below_all | 2538 | composition: 12x16x24:2538=(3x4x6:54[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 12x16x25 | 2730 | below_all | 2730 | composition: 12x16x25:2730=(1x12x16:192[naive] (+) 12x16x24:2538=(3x4x6:54[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 12x16x26 | 2834 | below_all | 2834 | composition: 12x16x26:2834=(2x12x16:296[FMM-known] (+) 12x16x24:2538=(3x4x6:54[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 12x16x28 | 3008 | below_all | 3008 | composition: 12x16x28:3008=(3x4x7:64[FMM-ZT] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 12x16x30 | 3240 | below_all | 3240 | composition: 12x16x30:3240=(3x4x6:54[Perminov-ZT] (x) 4x4x5:60[KM-F2]) | closure product |
| 12x16x32 | 3431 | below_all | 3431 | composition: 12x16x32:3431=(3x4x8:73[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 12x17x24 | 2826 | below_all | 2826 | composition: 12x17x24:2826=(1x12x24:288[naive] (+) 12x16x24:2538=(3x4x6:54[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 12x20x20 | 2726 | below_all | 2726 | composition: 12x20x20:2726=(3x5x5:58[AlphaTensor-F2] (x) 4x4x4:47[AlphaTensor-F2]) | July certificate |
| 12x20x24 | 3196 | below_all | 3196 | composition: 12x20x24:3196=(3x5x6:68[AlphaEvolve] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 12x20x28 | 3713 | below_all | 3713 | composition: 12x20x28:3713=(3x5x7:79[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 12x20x32 | 4230 | below_all | 4230 | composition: 12x20x32:4230=(3x5x8:90[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 12x25x28 | 4740 | below_all | 4740 | composition: 12x25x28:4740=(3x5x7:79[Perminov-ZT] (x) 4x4x5:60[KM-F2]) | closure product |
| 12x28x28 | 5217 | below_all | 5217 | composition: 12x28x28:5217=(3x7x7:111[Perminov-ZT] (x) 4x4x4:47[AlphaTensor-F2]) | closure product |
| 15x16x24 | 3240 | below_all | 3240 | composition: 15x16x24:3240=(3x4x6:54[Perminov-ZT] (x) 4x4x5:60[KM-F2]) | closure product |
| 15x16x26 | 3608 | below_all | 3608 | composition: 15x16x26:3608=(2x15x16:368[FMM-Z] (+) 15x16x24:3240=(3x4x6:54[Perminov-ZT] (x) 4x4x5:60[KM-F2])) | closure product |
| 15x16x28 | 3840 | below_all | 3840 | composition: 15x16x28:3840=(3x4x7:64[FMM-ZT] (x) 4x4x5:60[KM-F2]) | closure product |
| 16x16x20 | 2820 | below_all | 2820 | composition: 16x16x20:2820=(4x4x4:47[AlphaTensor-F2] (x) 4x4x5:60[KM-F2]) | July certificate |
| 16x16x22 | 3181 | below_all | 3181 | composition: 16x16x22:3181=(6x16x16:972[FMM-ZT] (+) 16x16x16:2209=(4x4x4:47[AlphaTensor-F2] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 16x16x24 | 3431 | below_all | 3431 | composition: 16x16x24:3431=(8x16x16:1222=(2x4x4:26[HK71] (x) 4x4x4:47[AlphaTensor-F2]) (+) 16x16x16:2209=(4x4x4:47[AlphaTensor-F2] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 16x16x25 | 3589 | below_all | 3589 | composition: 16x16x25:3589=(9x16x16:1380[FMM-Z] (+) 16x16x16:2209=(4x4x4:47[AlphaTensor-F2] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 16x16x28 | 3995 | below_all | 3995 | composition: 16x16x28:3995=(12x16x16:1786=(3x4x4:38[AlphaTensor-F2] (x) 4x4x4:47[AlphaTensor-F2]) (+) 16x16x16:2209=(4x4x4:47[AlphaTensor-F2] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 16x16x32 | 4418 | below_all | 4418 | composition: 16x16x32:4418=(16x16x16:2209=(4x4x4:47[AlphaTensor-F2] (x) 4x4x4:47[AlphaTensor-F2]) (+) 16x16x16:2209=(4x4x4:47[AlphaTensor-F2] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 16x20x28 | 4888 | below_all | 4888 | composition: 16x20x28:4888=(4x4x4:47[AlphaTensor-F2] (x) 4x5x7:104[Perminov-ZT]) | closure product |
| 16x20x32 | 5546 | below_all | 5546 | composition: 16x20x32:5546=(4x4x4:47[AlphaTensor-F2] (x) 4x5x8:118[Perminov-ZT]) | closure product |
| 16x24x24 | 4935 | below_all | 4935 | composition: 16x24x24:4935=(2x2x2:7[mmc] (x) 8x12x12:705=(2x3x3:15[HK71] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 16x24x28 | 5781 | below_all | 5781 | composition: 16x24x28:5781=(4x4x4:47[AlphaTensor-F2] (x) 4x6x7:123[Perminov-ZT]) | closure product |
| 16x24x32 | 6580 | below_all | 6580 | composition: 16x24x32:6580=(2x2x2:7[mmc] (x) 8x12x16:940=(2x3x4:20[HK71] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |
| 16x28x28 | 6768 | below_all | 6768 | composition: 16x28x28:6768=(4x4x4:47[AlphaTensor-F2] (x) 4x7x7:144[Perminov-ZT]) | closure product |
| 16x28x32 | 7567 | below_all | 7567 | composition: 16x28x32:7567=(4x4x4:47[AlphaTensor-F2] (x) 4x7x8:161[Perminov-ZT]) | closure product |
| 16x32x32 | 8460 | below_all | 8460 | composition: 16x32x32:8460=(4x4x4:47[AlphaTensor-F2] (x) 4x8x8:180[Perminov-ZT]) | closure product |
| 20x20x32 | 6768 | below_all | 6768 | composition: 20x20x32:6768=(4x4x4:47[AlphaTensor-F2] (x) 5x5x8:144[Perminov-ZT]) | closure product |
| 20x21x25 | 5829 | gf2_valid_only | 5829 | composition: 20x21x25:5829=(1x20x25:500[naive] (+) 20x20x25:5329=(4x5x5:73[Arai 455:73] (x) 4x5x5:73[Arai 455:73])) | committed certificate |
| 20x24x24 | 6110 | below_all | 6110 | composition: 20x24x24:6110=(4x4x4:47[AlphaTensor-F2] (x) 5x6x6:130[Perminov-ZT]) | closure product |
| 20x24x28 | 7050 | below_all | 7050 | composition: 20x24x28:7050=(4x4x4:47[AlphaTensor-F2] (x) 5x6x7:150[Perminov-ZT]) | closure product |
| 20x24x32 | 7990 | below_all | 7990 | composition: 20x24x32:7990=(4x4x4:47[AlphaTensor-F2] (x) 5x6x8:170[Perminov-ZT]) | closure product |
| 20x28x28 | 8272 | below_all | 8272 | composition: 20x28x28:8272=(4x4x4:47[AlphaTensor-F2] (x) 5x7x7:176[Perminov-ZT]) | closure product |
| 20x28x29 | 8832 | below_all | 8832 | composition: 20x28x29:8832=(1x20x28:560[naive] (+) 20x28x28:8272=(4x4x4:47[AlphaTensor-F2] (x) 5x7x7:176[Perminov-ZT])) | closure product |
| 20x28x32 | 9588 | below_all | 9588 | composition: 20x28x32:9588=(4x4x4:47[AlphaTensor-F2] (x) 5x7x8:204[Perminov-ZT]) | closure product |
| 20x32x32 | 10800 | below_all | 10800 | composition: 20x32x32:10800=(4x8x8:180[Perminov-ZT] (x) 4x4x5:60[KM-F2]) | closure product |
| 24x32x32 | 12502 | below_all | 12502 | composition: 24x32x32:12502=(2x2x2:7[mmc] (x) 12x16x16:1786=(3x4x4:38[AlphaTensor-F2] (x) 4x4x4:47[AlphaTensor-F2])) | closure product |

### C.M2 matched, rank claim only

| shape | ours | class | prior | how (smallest first) | our chain |
|---|---|---|---|---|---|
| 3x22x28 | 1364 | gf2_valid_only | 1364 | composition of listed / published GF(2) ranks (L2S): 3x22x28:1364=(3x4x22:200=(3x4x4:38[matmulcatalog:Smirnov 2013 / matmulcatalog:unknown / matmulcatalog:AlphaTensor] (+) 3x4x18:162=(3x4x6:54[matmulcatalog:Kauers & Wood 2025 / FMM:ZT / arXiv:2511.20317 Table 5 (best known, as listed) line 804 (Z)] (+) 3x4x12:108[matmulcatalog:FMM-Lille / FMM:ZT / arX | closure product |
| 3x25x32 | 1750 | gf2_valid_only | 1750 | composition of listed / published GF(2) ranks (L2S): 3x25x32:1750=(2x3x25:125[matmulcatalog:Hopcroft-Kerr 1971 (constructive, this work) / matmulcatalog:unknown] (+) 3x25x30:1625[matmulcatalog:unknown]) | closure product |
| 12x20x26 | 3566 | below_all | 3566 | composition of listed / published GF(2) ranks (L2S): 12x20x26:3566=(2x12x20:370[matmulcatalog:Hopcroft-Kerr 1971 (constructive, this work)] (+) 12x20x24:3196=(3x5x6:68[matmulcatalog:unknown / matmulcatalog:AlphaEvolve / FMM:ZT] (x) 4x4x4:47[matmulcatalog:AlphaTensor / arXiv:2210.04045 in text line 28 (ring R of characteristic 2) / arXiv:2210.04045 in  | closure product |
| 16x20x26 | 4634 | below_all | 4634 | composition of listed / published GF(2) ranks (L2S): 16x20x26:4634=(6x16x20:1203[matmulcatalog:unknown] (+) 16x20x20:3431=(4x4x4:47[matmulcatalog:AlphaTensor / arXiv:2210.04045 in text line 28 (ring R of characteristic 2) / arXiv:2210.04045 in text line 52 (ring R of characteristic 2)] (x) 4x5x5:73[arXiv:2312.16960 Table 1 line 402 (characteristic 2 ( | committed certificate |
| 16x26x28 | 6467 | below_all | 6467 | composition of listed / published GF(2) ranks (L2S): 16x26x28:6467=(2x16x28:686[matmulcatalog:Hopcroft-Kerr 1971 (constructive, this work)] (+) 16x24x28:5781=(4x4x4:47[matmulcatalog:AlphaTensor / arXiv:2210.04045 in text line 28 (ring R of characteristic 2) / arXiv:2210.04045 in text line 52 (ring R of characteristic 2)] (x) 4x6x7:123[matmulcatalog:Ka | closure product |
| 20x26x32 | 8966 | below_all | 8966 | composition of listed / published GF(2) ranks (L2S): 20x26x32:8966=(2x20x32:976[matmulcatalog:Hopcroft-Kerr 1971 (constructive, this work)] (+) 20x24x32:7990=(4x4x4:47[matmulcatalog:AlphaTensor / arXiv:2210.04045 in text line 28 (ring R of characteristic 2) / arXiv:2210.04045 in text line 52 (ring R of characteristic 2)] (x) 5x6x8:170[matmulcatalog:Ka | closure product |
| 20x29x32 | 10060 | below_all | 10060 | composition of listed / published GF(2) ranks (L2S): 20x29x32:10060=(5x20x32:2070[matmulcatalog:unknown] (+) 20x24x32:7990=(4x4x4:47[matmulcatalog:AlphaTensor / arXiv:2210.04045 in text line 28 (ring R of characteristic 2) / arXiv:2210.04045 in text line 52 (ring R of characteristic 2)] (x) 5x6x8:170[matmulcatalog:Kauers & Wood 2025 / FMM:ZT / arXiv:2 | closure product |

### C.Q class caveat (below_all contradicted by a characteristic-0 claim)

| shape | ours | class | prior | how (smallest first) | our chain |
|---|---|---|---|---|---|
| 8x15x32 | 2318 | below_all | 2295 | matmulcatalog cited-bounds (Perminov 2026 (serendipitous); Q) | closure product -> projection -> walk |
| 8x18x24 | 2059 | below_all | 2040 | matmulcatalog cited-bounds (Perminov 2026 (serendipitous); Q) | committed certificate |
| 11x12x20 | 1618 | below_all | 1605 | matmulcatalog cited-bounds (Perminov 2026 (serendipitous); Q) | July certificate -> projection |
| 11x15x24 | 2357 | below_all | 2347 | matmulcatalog cited-bounds (Perminov 2026 (serendipitous); Q) | committed certificate |
| 11x15x28 | 2774 | below_all | 2719 | matmulcatalog cited-bounds (Perminov 2026 (serendipitous); Q) | committed certificate -> projection -> walk |
| 11x20x21 | 2730 | below_all | 2719 | matmulcatalog cited-bounds (Perminov 2026 (serendipitous); Q) | July certificate |
| 11x21x24 | 3287 | below_all | 3225 | matmulcatalog cited-bounds (Perminov 2026 (serendipitous); Q) | closure product -> projection -> walk |
| 11x21x28 | 3829 | below_all | 3784 | matmulcatalog cited-bounds (Perminov 2026 (serendipitous); Q) | closure product |
| 12x14x26 | 2600 | below_all | 2590 | matmulcatalog cited-bounds (Perminov 2026 (serendipitous); Q) | committed certificate -> projection -> walk |

---

## (D) Recommended wording for the caveat paragraph

> **Scope of the record claims (prior-art audit of 2026-09-29).** We call a rank a record when it lies below every rank
> listed, on 2026-09-29, in four public tables: Sedoglavic's catalogue (fmm_digest `9f26324b`), matmulcatalog
> (`f0c2ba9e`, `docs/catalog.json`), FastMatrixMultiplication (`613599b6`) and fmm-schemes (`8fa0f2a0`). Re-scoring
> against the latest revisions of all four (fmm_digest `f5c2b262`, matmulcatalog `5a306526`, FastMatrixMultiplication
> `ac13ca88`, fmm-schemes unchanged; heads re-checked 2026-09-29, 23:48 UTC) changes no classification.
>
> Those tables are not an exhaustive record of GF(2)-valid prior art, and an audit found three omissions:
> 1. schemes published outside them that are valid only in characteristic 2: Arai, Ichikawa and Hukushima's
>    ⟨4,5,5⟩ of rank 73 [2312.16960], Kauers and Wood's ⟨4,5,6⟩ of rank 89 [2510.19787], and Medley et al.'s ⟨7,7,7⟩
>    of rank 245 [2609.17533];
> 2. rank claims obtained with Perminov's serendipitous product [2606.02480] and recorded, without factor matrices, in
>    matmulcatalog's `cited-bounds.json` since June 2026;
> 3. elementary compositions (direct sums, Kronecker products, Strassen's algorithm on unequal blocks) of listed schemes.
>
> From these we built explicit GF(2) schemes, each verified exactly, of rank strictly below ours for **80** of our
> shapes; for **7** more, published rank claims are below ours. **We withdraw these 87 shapes.** For **112** further
> shapes our rank equals that of an elementary composition of published schemes. We report these as composition bounds,
> not as new search results. For **16** shapes that we label as below every listed rank in any ring, the same catalogue
> records a lower characteristic-0 (rational) rank claim; for those, only the GF(2) comparison stands.
>
> Of the 795 shapes, **596** remain below every published GF(2)-valid bound we could find or build on 2026-09-29.
> Neither they nor the others are optimality claims, and this search for prior art was not exhaustive.

If the paper keeps the 795 count in its title or abstract, it should say "795 shapes below every rank listed in four
public tables" and give the 87 / 112 / 596 breakdown right after it. The superseded shapes follow from compositions a
reader can check in minutes, for example Arai et al.'s F2 rank 73 composed with AlphaTensor's F2 rank 47.

---

## Appendix: reproduction and files

These commands were run on 2026-09-29 from `W/paper-notes`. Each `…` stands for the file written by the step before.

```
python3 08-rescore-latest.py            > rescore.json              # Part A; writes W/paper-data/rescore_latest.tsv (3 s)
python3 08-fetch-literature.py [--only ID …]                         # papers -> W/upstream-latest/arxiv (≈4 min for 20)
python3 08-literature-check.py --json L.json                         # 770 parsed + 878 transcribed rows, Medley check
python3 08-composition-closure.py       > C.json                     # closures L0/L1/L2 (+Strassen), catalogue claims (≈40 s)
python3 08-serendipitous-check.py --with-q --rich > S.json           # 67 catalogue claims rebuilt and verified (≈90 s)
python3 08-composition-verify.py --all  > X.json                     # explicit sweep, 146 schemes built and verified (≈5 min)
python3 08-crosscheck-release-verifier.py                            # 9 schemes through the release verifier (≈20 min)
python3 08-consolidate.py --rescore rescore.json --literature L.json --closure C.json --serendipity S.json --sweep X.json
```

Created under `W/upstream-latest/` (and nothing anywhere else except this note, the `08-*.py` scripts and
`W/paper-data/rescore_latest.tsv`):

* Fresh clones, as listed in A.1: `fmm`, `matmulcatalog`, `fmm_digest`, `fmm-schemes`.
* `extracted/`: the files read at each revision.
* `arxiv/<id>/`: 48 papers with `abs.html`, `paper.pdf`, `paper.txt`, `paper.html` and `meta.json`, plus `manifest.json`.
* `FastMatrixF2`: `5fd32f68`.
* `adap`: `fe7b2040`.
* `mkauers-matrix-multiplication`: `12c26b29`.
* Scheme files read locally instead of through lazy blob fetches:
  * `fmm-tree-ac13ca8855/` (1.7 GB), the `schemes/**/*.json` and `known/meta_flip_graph` files of FMM at `ac13ca8855`,
    from GitHub's codeload tarball. Three files spot-checked against the git blobs are identical.
  * `mmc-tree-5a306526e9c9/` (0.7 GB), the explicit scheme files of matmulcatalog at `5a306526`.
  * Both trees can be deleted; the scripts then fall back to lazy `git show`.
* The FMM clone also holds a partial checkout of `schemes/results` and `schemes/known`, made while trying to prefetch blobs.

Nothing was written into the release directory or the repository. The pinned clones (`W/upstream/*`) have unchanged
HEADs, refs, objects and working trees. One thing did change there: my first inspection ran `git status`, which
refreshed the stat cache in `.git/index` of `fmm`, `fmm_digest` and `merlijn` at 21:32:30Z. No tracked content changed.
`08-rescore-latest.py` now uses `git --no-optional-locks status`, so it cannot repeat this.
