# Apparent GF(2) block-composition records

Status date: 2026-07-14.

The manifest contains 186 exact noncommutative bilinear algorithms over GF(2):
176 strict apparent GF(2) records, one public GF(2) co-record, and nine exact
upper bounds whose pinned sources contain no explicit or reducible GF(2)
comparator.  The explicitly labeled 12x12x14 entry beats the strongest pinned
GF(2) certificate but not a lower rational construction.
"Apparent" is intentional: a current catalogue and repository scan is strong
evidence, not an exhaustive proof that no uncatalogued result exists.  These
algorithms must not be advertised as arbitrary-field or integer-ring records.

## Construction and novelty boundary

The support-aware recombination method is established, not new.  The public
[AlphaTensor implementation](https://github.com/google-deepmind/alphatensor/blob/main/recombination/recombination.py)
describes its generalized construction and credits Sedoglavic (2017) and
Drevet--Islam--Schost (2011).  Rank-47 4x4x4 outer schemes, the constituent
2--8 leaves, allocation search, and symmetry machinery are also public prior
art.  The apparently new part here is this particular campaign: retaining the
six support-distinct tensor-slot orientations of the sparse outer scheme,
scanning every formula-minimizing allocation/orientation tie, exhaustively
screening ordered 3--8 block allocations at the wide frontier, materializing
the resulting wide factors, and exact-gating post-embedding zero pruning and
duplicate-parity cancellation.

Each certificate was exact-gated by the pure-Tungsten wide-factor verifier;
the complete manifest was then reloaded and reconstructed again by that same
implementation.  A separate
[Python sparse-parity verifier](verify_block_composition_records.py), sharing
no verifier code with the Tungsten path, independently reconstructed every
coefficient of all 186 tensors.  Its deterministic per-certificate results are
in [`block_composition_independent_audit.tsv`](block_composition_independent_audit.tsv).
Reproducible recipes and
SHA-256 hashes are stored in [`block_composition_records.tsv`](block_composition_records.tsv);
the corresponding allocations are retained in that manifest.  The original
12--20 queue also retains its source orientation in
[`block_composition_opportunities.tsv`](block_composition_opportunities.tsv),
while the small-cross recipes and field-aware comparisons are in
[`block_composition_small_cross_audit.tsv`](block_composition_small_cross_audit.tsv).

The prior-art scan used the live FMM-Lille table (version
`ba70cfdde999efa9b59ad234edf9e32dc6602255`) and current public revisions of
[FastMatrixMultiplication](https://github.com/dronperminov/FastMatrixMultiplication/commit/e0ec7db),
[matmulcatalog](https://github.com/solven-eu/matmulcatalog/commit/0320f745d87e46c36259b03add05307429941680),
[AlphaTensor](https://github.com/google-deepmind/alphatensor/commit/1949163),
and [Flips](https://github.com/jakobmoosbauer/flips/commit/e31a0a0), plus the
current [fmm-17-32](https://github.com/lserafin/fmm-17-32/commit/deb0a6c5c6571c17c4fba27f34ded6af62d77ef0) rectangular
certificates.  The refreshed audit canonicalized every target over all six S3
tensor-slot permutations and compared both field-agnostic ranks and explicitly
GF(2)-valid ranks.  No equal or better GF(2) certificate was found for the
176 strict entries.  The 16x16x16 rank-2209 construction ties a public GF(2)
Kronecker certificate and is deliberately labeled a co-record.

The latest promoted rows are `<13,13,20>` at exact rank **2052**,
`<13,19,19>` at **2822**, `<14,19,20>` at **3130**, `<15,15,16>` at **2074**,
and `<15,15,17>` at **2262**.  Their live FMM-Lille values are 2109, 2880,
3187, 2132, and 2320.  The 13x19x19 construction falls from a rank-2826
formula to 2822 after duplicate-parity compaction; the others materialize at
their formula ranks.  Their SHA-256 hashes are recorded in the manifest.  The
15x15x17 claim is field-qualified: a rank-2260 construction exists over
F3/Q/R/C, but its rank-40 `3x3x6` leaf is invalid over F2, where the audited
leaf rank is 42.

Two further promotions bring the manifest to 100: `<13,14,20>` at exact rank
**2203** and `<14,17,19>` at **2703**.  The latter is selected from source
`<14,19,17>` through S3 code 5 and falls from formula rank 2705 after two
post-embedding removals.

The next queue audit materialized nine more strict records, bringing the
manifest to 109.  Four have stronger pinned `fmm-17-32` comparators than their
live FMM-Lille rows: `<12,13,20>` rank **1868** improves integer rank 1871 by
3, `<14,16,18>` rank **2376** improves 2415 by 39, `<15,16,18>` rank **2490**
improves 2523 by 33, and `<16,18,20>` rank **3284** improves 3300 by 16.  The
remaining five improve their strongest audited same-shape values by 21--50.
The tempting `<13,16,18>` rank-2223 formula was rejected from the manifest
because the pinned integer rank-2217 certificate is stronger.

A final exhaustive pass through the original 12--20 queue materialized 37
further strict GF(2) records, bringing the manifest to 146 and leaving only
two rejected formulas.  Thirty-five of these additions are numerically below
every S3-normalized pinned comparator.  Two are field-qualified: rank **1850**
for `<12,15,17>` and rank **1890** for `<13,13,18>` improve their live GF(2)
frontiers by 10 and 3, while lower rank-1836 and rank-1871 catalogue stubs are
explicitly limited to F3/Q/R/C.  The two formulas still outside the manifest,
`<13,16,18>` rank 2223 and `<13,18,20>` rank 2776, lose to verified integer
ranks 2217 and 2736.
The complete 48-row closure, including conservative comparators, field labels,
the two rejections, and three gains corrected against serendipitous integer
formulas, is machine-readable in
[`block_composition_queue_closure_audit.tsv`](block_composition_queue_closure_audit.tsv).

Completing every sorted two-wide leaf `<2,a,b>` for `2 <= a <= b <= 8`
opened the previously omitted 8--11-by-32 seam.  The balanced small-cross scan
found 129 conservative GF(2) formula wins.  Twenty-two were materialized as
strict exact records, including 11x28x28 rank **4937** (gain 183), 11x20x32
rank **4014** (gain 146), and the direct `<2,3,5>` propagations 8x11x20 rank
**1119** and 8x12x20 rank **1175**.  Two additional exact upper bounds,
11x16x31 rank **3195** and 11x16x32 rank **3255**, beat every pinned numerical
value but are conservatively labelled uncovered because no pinned comparator
is explicitly valid or reducible over GF(2).  The complete 1,154-target audit,
the 24 promoted certificates, and the zero-win universal rank-49 control are
documented in
[`BLOCK_COMPOSITION_SMALL_CROSS_AUDIT.md`](BLOCK_COMPOSITION_SMALL_CROSS_AUDIT.md).

Exact materialization of every balanced formula tie, plus the exhaustive
ordered-allocation closure, adds sixteen more small-cross certificates. Nine
are strict: 10x16x16 rank **1558**, 10x16x17 rank **1694**, 10x16x26 rank
**2509**, 10x22x23 rank **3071**, 11x15x25 rank **2476**, 11x15x26 rank
**2593**, 11x15x27 rank **2694**, 11x17x19 rank **2190**, and 11x19x19 rank
**2430**. Seven additional exact upper bounds beat every pinned numerical
comparator but remain labelled uncovered because no pinned comparator is
explicitly valid or reducible over GF(2). The alternate d677 rank-47 outer has
zero formula or exact wins; the complete negative control and promotion audit
are in
[`BLOCK_COMPOSITION_OUTER47_SMALL_CROSS_AUDIT.md`](BLOCK_COMPOSITION_OUTER47_SMALL_CROSS_AUDIT.md).

## Exact saved certificates

| Target | Exact GF(2) rank | Live FMM rank | Gain | Certificate |
|---|---:|---:|---:|---|
| 12x12x14 | **1251** | [1234 over Q](https://fmm.univ-lille.fr/12x12x14.html) | -17 numerical; **+9 vs GF(2)** | [`matmul_12x12x14_rank1251_block47_unbalanced_gf2.txt`](matmul_12x12x14_rank1251_block47_unbalanced_gf2.txt) |
| 12x12x16 | **1363** | [1380](https://fmm.univ-lille.fr/12x12x16.html) | 17 | [`matmul_12x12x16_rank1363_block47_gf2.txt`](matmul_12x12x16_rank1363_block47_gf2.txt) |
| 12x12x17 | **1475** | [1502](https://fmm.univ-lille.fr/12x12x17.html) | 27 | [`matmul_12x12x17_rank1475_block47_gf2.txt`](matmul_12x12x17_rank1475_block47_gf2.txt) |
| 12x12x19 | **1636** | [1663](https://fmm.univ-lille.fr/12x12x19.html) | 27 | [`matmul_12x12x19_rank1636_block47_gf2.txt`](matmul_12x12x19_rank1636_block47_gf2.txt) |
| 12x12x20 | **1692** | [1710](https://fmm.univ-lille.fr/12x12x20.html) | 18 | [`matmul_12x12x20_rank1692_block47_gf2.txt`](matmul_12x12x20_rank1692_block47_gf2.txt) |
| 12x13x16 | **1507** | [1509](https://fmm.univ-lille.fr/12x13x16.html) | 2 | [`matmul_12x13x16_rank1507_block47_gf2.txt`](matmul_12x13x16_rank1507_block47_gf2.txt) |
| 12x13x17 | **1627** | [1655](https://fmm.univ-lille.fr/12x13x17.html) | 28 | [`matmul_12x13x17_rank1627_block47_gf2.txt`](matmul_12x13x17_rank1627_block47_gf2.txt) |
| 12x13x19 | **1804** | [1833](https://fmm.univ-lille.fr/12x13x19.html) | 29 | [`matmul_12x13x19_rank1804_block47_gf2.txt`](matmul_12x13x19_rank1804_block47_gf2.txt) |
| 12x13x20 | **1868** | [1913](https://fmm.univ-lille.fr/12x13x20.html) | 45 vs Lille; 3 vs verified integer rank 1871 | [`matmul_12x13x20_rank1868_block47_gf2.txt`](matmul_12x13x20_rank1868_block47_gf2.txt) |
| 12x14x17 | **1752** | [1770](https://fmm.univ-lille.fr/12x14x17.html) | 18 | [`matmul_12x14x17_rank1752_block47_gf2.txt`](matmul_12x14x17_rank1752_block47_gf2.txt) |
| 12x14x19 | **1943** | [1964](https://fmm.univ-lille.fr/12x14x19.html) | 21 | [`matmul_12x14x19_rank1943_block47_gf2.txt`](matmul_12x14x19_rank1943_block47_gf2.txt) |
| 12x14x20 | **2011** | [2016](https://fmm.univ-lille.fr/12x14x20.html) | 5 | [`matmul_12x14x20_rank2011_block47_gf2.txt`](matmul_12x14x20_rank2011_block47_gf2.txt) |
| 12x15x16 | **1714** | [1725](https://fmm.univ-lille.fr/12x15x16.html) | 11 | [`matmul_12x15x16_rank1714_block47_gf2.txt`](matmul_12x15x16_rank1714_block47_gf2.txt) |
| 12x15x17 | **1850** | [1860](https://fmm.univ-lille.fr/12x15x17.html) | **+10 vs GF(2)**; -14 vs rank 1836 over F3/Q/R/C | [`matmul_12x15x17_rank1850_block47_gf2.txt`](matmul_12x15x17_rank1850_block47_gf2.txt) |
| 12x15x20 | **2121** | [2132](https://fmm.univ-lille.fr/12x15x20.html) | 11 | [`matmul_12x15x20_rank2121_block47_gf2.txt`](matmul_12x15x20_rank2121_block47_gf2.txt) |
| 12x16x16 | **1786** | [1815](https://fmm.univ-lille.fr/12x16x16.html) | 29 | [`matmul_12x16x16_rank1786_block47_gf2.txt`](matmul_12x16x16_rank1786_block47_gf2.txt) |
| 12x16x17 | **1930** | [1982](https://fmm.univ-lille.fr/12x16x17.html) | 52 vs Lille; 50 vs catalog rank 1980 | [`matmul_12x16x17_rank1930_block47_gf2.txt`](matmul_12x16x17_rank1930_block47_gf2.txt) |
| 12x16x19 | **2137** | [2196](https://fmm.univ-lille.fr/12x16x19.html) | 59 | [`matmul_12x16x19_rank2137_block47_gf2.txt`](matmul_12x16x19_rank2137_block47_gf2.txt) |
| 12x16x20 | **2209** | [2256](https://fmm.univ-lille.fr/12x16x20.html) | 47 | [`matmul_12x16x20_rank2209_block47_gf2.txt`](matmul_12x16x20_rank2209_block47_gf2.txt) |
| 12x17x17 | **2082** | [2114](https://fmm.univ-lille.fr/12x17x17.html) | 32 | [`matmul_12x17x17_rank2082_block47_gf2.txt`](matmul_12x17x17_rank2082_block47_gf2.txt) |
| 12x17x19 | **2305** | [2348](https://fmm.univ-lille.fr/12x17x19.html) | 43 | [`matmul_12x17x19_rank2305_block47_gf2.txt`](matmul_12x17x19_rank2305_block47_gf2.txt) |
| 12x17x20 | **2385** | [2449](https://fmm.univ-lille.fr/12x17x20.html) | 64 | [`matmul_12x17x20_rank2385_block47_gf2.txt`](matmul_12x17x20_rank2385_block47_gf2.txt) |
| 12x19x19 | **2563** | [2604](https://fmm.univ-lille.fr/12x19x19.html) | 41 | [`matmul_12x19x19_rank2563_block47_gf2.txt`](matmul_12x19x19_rank2563_block47_gf2.txt) |
| 12x19x20 | **2638** | [2704](https://fmm.univ-lille.fr/12x19x20.html) | 66 | [`matmul_12x19x20_rank2638_block47_gf2.txt`](matmul_12x19x20_rank2638_block47_gf2.txt) |
| 12x20x20 | **2726** | [2784](https://fmm.univ-lille.fr/12x20x20.html) | 58 | [`matmul_12x20x20_rank2726_block47_gf2.txt`](matmul_12x20x20_rank2726_block47_gf2.txt) |
| 13x13x13 | **1402** | [1421](https://fmm.univ-lille.fr/13x13x13.html) | 19 | [`matmul_13x13_rank1402_block47_gf2.txt`](matmul_13x13_rank1402_block47_gf2.txt) |
| 13x13x14 | **1501** | [1511](https://fmm.univ-lille.fr/13x13x14.html) | 10 | [`matmul_13x13x14_rank1501_block47_gf2.txt`](matmul_13x13x14_rank1501_block47_gf2.txt) |
| 13x13x15 | **1582** | [1605](https://fmm.univ-lille.fr/13x13x15.html) | 23 | [`matmul_13x13x15_rank1582_block47_gf2.txt`](matmul_13x13x15_rank1582_block47_gf2.txt) |
| 13x13x16 | **1648** | [1704](https://fmm.univ-lille.fr/13x13x16.html) | 56 | [`matmul_13x13x16_rank1648_block47_gf2.txt`](matmul_13x13x16_rank1648_block47_gf2.txt) |
| 13x13x17 | **1778** | [1812](https://fmm.univ-lille.fr/13x13x17.html) | 34 | [`matmul_13x13x17_rank1778_block47_gf2.txt`](matmul_13x13x17_rank1778_block47_gf2.txt) |
| 13x13x18 | **1890** | [1893](https://fmm.univ-lille.fr/13x13x18.html) | **+3 vs GF(2)**; -19 vs rank 1871 over F3/Q/R/C | [`matmul_13x13x18_rank1890_block47_gf2.txt`](matmul_13x13x18_rank1890_block47_gf2.txt) |
| 13x13x19 | **1978** | [2017](https://fmm.univ-lille.fr/13x13x19.html) | 39 | [`matmul_13x13x19_rank1978_block47_gf2.txt`](matmul_13x13x19_rank1978_block47_gf2.txt) |
| 13x13x20 | **2052** | [2109](https://fmm.univ-lille.fr/13x13x20.html) | 57 vs Lille; 47 vs verified rank 2099 | [`matmul_13x13x20_rank2052_block47_gf2.txt`](matmul_13x13x20_rank2052_block47_gf2.txt) |
| 13x14x16 | **1763** | [1796](https://fmm.univ-lille.fr/13x14x16.html) | 33 | [`matmul_13x14x16_rank1763_block47_gf2.txt`](matmul_13x14x16_rank1763_block47_gf2.txt) |
| 13x14x17 | **1907** | [1939](https://fmm.univ-lille.fr/13x14x17.html) | 32 | [`matmul_13x14x17_rank1907_block47_gf2.txt`](matmul_13x14x17_rank1907_block47_gf2.txt) |
| 13x14x19 | **2125** | [2155](https://fmm.univ-lille.fr/13x14x19.html) | 30 | [`matmul_13x14x19_rank2125_block47_gf2.txt`](matmul_13x14x19_rank2125_block47_gf2.txt) |
| 13x14x20 | **2203** | [2259](https://fmm.univ-lille.fr/13x14x20.html) | 56 vs Lille; 33 vs verified integer rank 2236 | [`matmul_13x14x20_rank2203_block47_gf2.txt`](matmul_13x14x20_rank2203_block47_gf2.txt) |
| 13x15x15 | **1796** | [1797](https://fmm.univ-lille.fr/13x15x15.html) | 1 | [`matmul_13x15x15_rank1796_block47_gf2.txt`](matmul_13x15x15_rank1796_block47_gf2.txt) |
| 13x15x16 | **1858** | [1885](https://fmm.univ-lille.fr/13x15x16.html) | 27 | [`matmul_13x15x16_rank1858_block47_gf2.txt`](matmul_13x15x16_rank1858_block47_gf2.txt) |
| 13x15x17 | **2008** | [2041](https://fmm.univ-lille.fr/13x15x17.html) | 33 | [`matmul_13x15x17_rank2008_block47_gf2.txt`](matmul_13x15x17_rank2008_block47_gf2.txt) |
| 13x15x19 | **2252** | [2268](https://fmm.univ-lille.fr/13x15x19.html) | 16 | [`matmul_13x15x19_rank2252_block47_gf2.txt`](matmul_13x15x19_rank2252_block47_gf2.txt) |
| 13x15x20 | **2321** | [2385](https://fmm.univ-lille.fr/13x15x20.html) | 64 | [`matmul_13x15x20_rank2321_block47_gf2.txt`](matmul_13x15x20_rank2321_block47_gf2.txt) |
| 13x16x16 | **1930** | [2022](https://fmm.univ-lille.fr/13x16x16.html) | 92 | [`matmul_13x16x16_rank1930_block47_gf2.txt`](matmul_13x16x16_rank1930_block47_gf2.txt) |
| 13x16x17 | **2090** | [2164](https://fmm.univ-lille.fr/13x16x17.html) | 74 | [`matmul_13x16x17_rank2090_block47_gf2.txt`](matmul_13x16x17_rank2090_block47_gf2.txt) |
| 13x16x19 | **2329** | [2414](https://fmm.univ-lille.fr/13x16x19.html) | 85 | [`matmul_13x16x19_rank2329_block47_gf2.txt`](matmul_13x16x19_rank2329_block47_gf2.txt) |
| 13x16x20 | **2417** | [2521](https://fmm.univ-lille.fr/13x16x20.html) | 104 | [`matmul_13x16x20_rank2417_block47_gf2.txt`](matmul_13x16x20_rank2417_block47_gf2.txt) |
| 13x17x17 | **2259** | [2320](https://fmm.univ-lille.fr/13x17x17.html) | 61 | [`matmul_13x17x17_rank2259_block47_gf2.txt`](matmul_13x17x17_rank2259_block47_gf2.txt) |
| 13x17x18 | **2401** | [2404](https://fmm.univ-lille.fr/13x17x18.html) | 3 | [`matmul_13x17x18_rank2401_block47_gf2.txt`](matmul_13x17x18_rank2401_block47_gf2.txt) |
| 13x17x19 | **2516** | [2586](https://fmm.univ-lille.fr/13x17x19.html) | 70 | [`matmul_13x17x19_rank2516_block47_gf2.txt`](matmul_13x17x19_rank2516_block47_gf2.txt) |
| 13x17x20 | **2613** | [2697](https://fmm.univ-lille.fr/13x17x20.html) | 84 | [`matmul_13x17x20_rank2613_block47_gf2.txt`](matmul_13x17x20_rank2613_block47_gf2.txt) |
| 13x19x19 | **2822** | [2880](https://fmm.univ-lille.fr/13x19x19.html) | 58 | [`matmul_13x19x19_rank2822_block47_gf2.txt`](matmul_13x19x19_rank2822_block47_gf2.txt) |
| 13x19x20 | **2906** | [3001](https://fmm.univ-lille.fr/13x19x20.html) | 95 | [`matmul_13x19x20_rank2906_block47_gf2.txt`](matmul_13x19x20_rank2906_block47_gf2.txt) |
| 13x20x20 | **3014** | [3130](https://fmm.univ-lille.fr/13x20x20.html) | 116 | [`matmul_13x20x20_rank3014_block47_gf2.txt`](matmul_13x20x20_rank3014_block47_gf2.txt) |
| 14x14x16 | **1881** | [1931](https://fmm.univ-lille.fr/14x14x16.html) | 50 | [`matmul_14x14x16_rank1881_block47_gf2.txt`](matmul_14x14x16_rank1881_block47_gf2.txt) |
| 14x14x17 | **2035** | [2054](https://fmm.univ-lille.fr/14x14x17.html) | 19 | [`matmul_14x14x17_rank2035_block47_gf2.txt`](matmul_14x14x17_rank2035_block47_gf2.txt) |
| 14x14x19 | **2276** | [2288](https://fmm.univ-lille.fr/14x14x19.html) | 12 | [`matmul_14x14x19_rank2276_block47_gf2.txt`](matmul_14x14x19_rank2276_block47_gf2.txt) |
| 14x14x20 | **2364** | [2408](https://fmm.univ-lille.fr/14x14x20.html) | 44 vs Lille; 21 vs verified rank 2385 | [`matmul_14x14x20_rank2364_block47_gf2.txt`](matmul_14x14x20_rank2364_block47_gf2.txt) |
| 14x15x16 | **1975** | [2016](https://fmm.univ-lille.fr/14x15x16.html) | 41 | [`matmul_14x15x16_rank1975_block47_gf2.txt`](matmul_14x15x16_rank1975_block47_gf2.txt) |
| 14x15x17 | **2145** | [2158](https://fmm.univ-lille.fr/14x15x17.html) | 13 | [`matmul_14x15x17_rank2145_block47_gf2.txt`](matmul_14x15x17_rank2145_block47_gf2.txt) |
| 14x15x20 | **2486** | [2514](https://fmm.univ-lille.fr/14x15x20.html) | 28 vs Lille; 16 vs integer formula 2502 | [`matmul_14x15x20_rank2486_block47_gf2.txt`](matmul_14x15x20_rank2486_block47_gf2.txt) |
| 14x16x16 | **2041** | [2128](https://fmm.univ-lille.fr/14x16x16.html) | 87 | [`matmul_14x16x16_rank2041_block47_unbalanced_gf2.txt`](matmul_14x16x16_rank2041_block47_unbalanced_gf2.txt) |
| 14x16x17 | **2223** | [2306](https://fmm.univ-lille.fr/14x16x17.html) | 83 | [`matmul_14x16x17_rank2223_block47_gf2.txt`](matmul_14x16x17_rank2223_block47_gf2.txt) |
| 14x16x18 | **2376** | [2428](https://fmm.univ-lille.fr/14x16x18.html) | 52 vs Lille; 39 vs verified integer rank 2415 | [`matmul_14x16x18_rank2376_block47_gf2.txt`](matmul_14x16x18_rank2376_block47_gf2.txt) |
| 14x16x19 | **2490** | [2581](https://fmm.univ-lille.fr/14x16x19.html) | 91 | [`matmul_14x16x19_rank2490_block47_gf2.txt`](matmul_14x16x19_rank2490_block47_gf2.txt) |
| 14x16x20 | **2586** | [2695](https://fmm.univ-lille.fr/14x16x20.html) | 109 | [`matmul_14x16x20_rank2586_block47_gf2.txt`](matmul_14x16x20_rank2586_block47_gf2.txt) |
| 14x17x17 | **2409** | [2456](https://fmm.univ-lille.fr/14x17x17.html) | 47 | [`matmul_14x17x17_rank2409_block47_gf2.txt`](matmul_14x17x17_rank2409_block47_gf2.txt) |
| 14x17x18 | **2576** | [2596](https://fmm.univ-lille.fr/14x17x18.html) | 20 | [`matmul_14x17x18_rank2576_block47_gf2.txt`](matmul_14x17x18_rank2576_block47_gf2.txt) |
| 14x17x19 | **2703** | [2759](https://fmm.univ-lille.fr/14x17x19.html) | 56 vs Lille; 50 vs registered rank 2753 | [`matmul_14x17x19_rank2703_block47_gf2.txt`](matmul_14x17x19_rank2703_block47_gf2.txt) |
| 14x17x20 | **2802** | [2879](https://fmm.univ-lille.fr/14x17x20.html) | 77 | [`matmul_14x17x20_rank2802_block47_gf2.txt`](matmul_14x17x20_rank2802_block47_gf2.txt) |
| 14x18x19 | **2878** | [2890](https://fmm.univ-lille.fr/14x18x19.html) | 12 | [`matmul_14x18x19_rank2878_block47_gf2.txt`](matmul_14x18x19_rank2878_block47_gf2.txt) |
| 14x19x19 | **3037** | [3056](https://fmm.univ-lille.fr/14x19x19.html) | 19 | [`matmul_14x19x19_rank3037_block47_gf2.txt`](matmul_14x19x19_rank3037_block47_gf2.txt) |
| 14x19x20 | **3130** | [3187](https://fmm.univ-lille.fr/14x19x20.html) | 57 | [`matmul_14x19x20_rank3130_block47_gf2.txt`](matmul_14x19x20_rank3130_block47_gf2.txt) |
| 14x20x20 | **3248** | [3276](https://fmm.univ-lille.fr/14x20x20.html) | 28 vs Lille; 9 vs integer formula 3257 | [`matmul_14x20x20_rank3248_block47_gf2.txt`](matmul_14x20x20_rank3248_block47_gf2.txt) |
| 15x15x15 | **2008** | [2058](https://fmm.univ-lille.fr/15x15x15.html) | 50 | [`matmul_15x15_rank2008_block47_gf2.txt`](matmul_15x15_rank2008_block47_gf2.txt) |
| 15x15x16 | **2074** | [2132](https://fmm.univ-lille.fr/15x15x16.html) | 58 | [`matmul_15x15x16_rank2074_block47_gf2.txt`](matmul_15x15x16_rank2074_block47_gf2.txt) |
| 15x15x17 | **2262** | [2320](https://fmm.univ-lille.fr/15x15x17.html) | **+58 vs GF(2)**; -2 vs rank 2260 over F3/Q/R/C | [`matmul_15x15x17_rank2262_block47_gf2.txt`](matmul_15x15x17_rank2262_block47_gf2.txt) |
| 15x15x20 | **2627** | [2664](https://fmm.univ-lille.fr/15x15x20.html) | 37 vs Lille; 14 vs integer formula 2641 | [`matmul_15x15x20_rank2627_block47_gf2.txt`](matmul_15x15x20_rank2627_block47_gf2.txt) |
| 15x16x16 | **2137** | [2262](https://fmm.univ-lille.fr/15x16x16.html) | 125 | [`matmul_15x16x16_rank2137_block47_gf2.txt`](matmul_15x16x16_rank2137_block47_gf2.txt) |
| 15x16x17 | **2329** | [2448](https://fmm.univ-lille.fr/15x16x17.html) | 119 | [`matmul_15x16x17_rank2329_block47_gf2.txt`](matmul_15x16x17_rank2329_block47_gf2.txt) |
| 15x16x18 | **2490** | [2538](https://fmm.univ-lille.fr/15x16x18.html) | 48 vs Lille; 33 vs verified integer rank 2523 | [`matmul_15x16x18_rank2490_block47_gf2.txt`](matmul_15x16x18_rank2490_block47_gf2.txt) |
| 15x16x19 | **2629** | [2747](https://fmm.univ-lille.fr/15x16x19.html) | 118 | [`matmul_15x16x19_rank2629_block47_gf2.txt`](matmul_15x16x19_rank2629_block47_gf2.txt) |
| 15x16x20 | **2716** | [2834](https://fmm.univ-lille.fr/15x16x20.html) | 118 | [`matmul_15x16x20_rank2716_block47_gf2.txt`](matmul_15x16x20_rank2716_block47_gf2.txt) |
| 15x17x17 | **2532** | [2622](https://fmm.univ-lille.fr/15x17x17.html) | 90 | [`matmul_15x17x17_rank2532_block47_gf2.txt`](matmul_15x17x17_rank2532_block47_gf2.txt) |
| 15x17x18 | **2709** | [2720](https://fmm.univ-lille.fr/15x17x18.html) | 11 | [`matmul_15x17x18_rank2709_block47_gf2.txt`](matmul_15x17x18_rank2709_block47_gf2.txt) |
| 15x17x19 | **2862** | [2934](https://fmm.univ-lille.fr/15x17x19.html) | 72 | [`matmul_15x17x19_rank2862_block47_gf2.txt`](matmul_15x17x19_rank2862_block47_gf2.txt) |
| 15x17x20 | **2952** | [3069](https://fmm.univ-lille.fr/15x17x20.html) | 117 | [`matmul_15x17x20_rank2952_block47_gf2.txt`](matmul_15x17x20_rank2952_block47_gf2.txt) |
| 15x19x19 | **3225** | [3260](https://fmm.univ-lille.fr/15x19x19.html) | 35 | [`matmul_15x19x19_rank3225_block47_gf2.txt`](matmul_15x19x19_rank3225_block47_gf2.txt) |
| 15x19x20 | **3321** | [3409](https://fmm.univ-lille.fr/15x19x20.html) | 88 | [`matmul_15x19x20_rank3321_block47_gf2.txt`](matmul_15x19x20_rank3321_block47_gf2.txt) |
| 15x20x20 | **3428** | [3500](https://fmm.univ-lille.fr/15x20x20.html) | 72 | [`matmul_15x20x20_rank3428_block47_gf2.txt`](matmul_15x20x20_rank3428_block47_gf2.txt) |
| 16x16x16 | **2209** | [2304](https://fmm.univ-lille.fr/16x16x16.html) | 95 | [`matmul_16x16_rank2209_block47_gf2.txt`](matmul_16x16_rank2209_block47_gf2.txt) |
| 16x16x17 | **2417** | [2560](https://fmm.univ-lille.fr/16x16x17.html) | 143 | [`matmul_16x16x17_rank2417_block47_gf2.txt`](matmul_16x16x17_rank2417_block47_gf2.txt) |
| 16x16x18 | **2586** | [2696](https://fmm.univ-lille.fr/16x16x18.html) | 110 | [`matmul_16x16x18_rank2586_block47_gf2.txt`](matmul_16x16x18_rank2586_block47_gf2.txt) |
| 16x16x19 | **2716** | [2838](https://fmm.univ-lille.fr/16x16x19.html) | 122 | [`matmul_16x16x19_rank2716_block47_gf2.txt`](matmul_16x16x19_rank2716_block47_gf2.txt) |
| 16x16x20 | **2820** | [2928](https://fmm.univ-lille.fr/16x16x20.html) | 108 | [`matmul_16x16x20_rank2820_block47_gf2.txt`](matmul_16x16x20_rank2820_block47_gf2.txt) |
| 16x17x17 | **2637** | [2738](https://fmm.univ-lille.fr/16x17x17.html) | 101 | [`matmul_16x17x17_rank2637_block47_gf2.txt`](matmul_16x17x17_rank2637_block47_gf2.txt) |
| 16x17x18 | **2818** | [2884](https://fmm.univ-lille.fr/16x17x18.html) | 66 | [`matmul_16x17x18_rank2818_block47_gf2.txt`](matmul_16x17x18_rank2818_block47_gf2.txt) |
| 16x17x19 | **2960** | [3066](https://fmm.univ-lille.fr/16x17x19.html) | 106 | [`matmul_16x17x19_rank2960_block47_gf2.txt`](matmul_16x17x19_rank2960_block47_gf2.txt) |
| 16x17x20 | **3076** | [3209](https://fmm.univ-lille.fr/16x17x20.html) | 133 | [`matmul_16x17x20_rank3076_block47_gf2.txt`](matmul_16x17x20_rank3076_block47_gf2.txt) |
| 16x18x19 | **3162** | [3204](https://fmm.univ-lille.fr/16x18x19.html) | 42 | [`matmul_16x18x19_rank3162_block47_gf2.txt`](matmul_16x18x19_rank3162_block47_gf2.txt) |
| 16x18x20 | **3284** | [3328](https://fmm.univ-lille.fr/16x18x20.html) | 44 vs Lille; 16 vs verified integer rank 3300 | [`matmul_16x18x20_rank3284_block47_gf2.txt`](matmul_16x18x20_rank3284_block47_gf2.txt) |
| 16x19x19 | **3335** | [3408](https://fmm.univ-lille.fr/16x19x19.html) | 73 | [`matmul_16x19x19_rank3335_block47_gf2.txt`](matmul_16x19x19_rank3335_block47_gf2.txt) |
| 16x19x20 | **3444** | [3558](https://fmm.univ-lille.fr/16x19x20.html) | 114 | [`matmul_16x19x20_rank3444_block47_gf2.txt`](matmul_16x19x20_rank3444_block47_gf2.txt) |
| 16x20x20 | **3572** | [3648](https://fmm.univ-lille.fr/16x20x20.html) | 76 | [`matmul_16x20x20_rank3572_block47_gf2.txt`](matmul_16x20x20_rank3572_block47_gf2.txt) |
| 17x17x17 | **2867** | [2930](https://fmm.univ-lille.fr/17x17x17.html) | 63 | [`matmul_17x17_rank2867_block47_gf2.txt`](matmul_17x17_rank2867_block47_gf2.txt) |
| 17x17x18 | **3058** | [3080](https://fmm.univ-lille.fr/17x17x18.html) | 22 | [`matmul_17x17x18_rank3058_block47_gf2.txt`](matmul_17x17x18_rank3058_block47_gf2.txt) |
| 17x17x19 | **3210** | [3266](https://fmm.univ-lille.fr/17x17x19.html) | 56 | [`matmul_17x17x19_rank3210_block47_gf2.txt`](matmul_17x17x19_rank3210_block47_gf2.txt) |
| 17x17x20 | **3336** | [3420](https://fmm.univ-lille.fr/17x17x20.html) | 84 | [`matmul_17x17x20_rank3336_block47_gf2.txt`](matmul_17x17x20_rank3336_block47_gf2.txt) |
| 17x18x19 | **3420** | [3430](https://fmm.univ-lille.fr/17x18x19.html) | 10 | [`matmul_17x18x19_rank3420_block47_gf2.txt`](matmul_17x18x19_rank3420_block47_gf2.txt) |
| 17x18x20 | **3548** | [3568](https://fmm.univ-lille.fr/17x18x20.html) | 20 | [`matmul_17x18x20_rank3548_block47_gf2.txt`](matmul_17x18x20_rank3548_block47_gf2.txt) |
| 17x19x19 | **3598** | [3637](https://fmm.univ-lille.fr/17x19x19.html) | 39 | [`matmul_17x19x19_rank3598_block47_gf2.txt`](matmul_17x19x19_rank3598_block47_gf2.txt) |
| 17x19x20 | **3712** | [3800](https://fmm.univ-lille.fr/17x19x20.html) | 88 | [`matmul_17x19x20_rank3712_block47_gf2.txt`](matmul_17x19x20_rank3712_block47_gf2.txt) |
| 17x20x20 | **3844** | [3972](https://fmm.univ-lille.fr/17x20x20.html) | 128 | [`matmul_17x20x20_rank3844_block47_gf2.txt`](matmul_17x20x20_rank3844_block47_gf2.txt) |
| 18x19x19 | **3812** | [3816](https://fmm.univ-lille.fr/18x19x19.html) | 4 | [`matmul_18x19x19_rank3812_block47_gf2.txt`](matmul_18x19x19_rank3812_block47_gf2.txt) |
| 18x20x20 | **4065** | [4159](https://fmm.univ-lille.fr/18x20x20.html) | 94 | [`matmul_18x20x20_rank4065_block47_gf2.txt`](matmul_18x20x20_rank4065_block47_gf2.txt) |
| 19x19x19 | **3993** | [4016](https://fmm.univ-lille.fr/19x19x19.html) | 23 | [`matmul_19x19_rank3993_block47_gf2.txt`](matmul_19x19_rank3993_block47_gf2.txt) |
| 19x19x20 | **4117** | [4194](https://fmm.univ-lille.fr/19x19x20.html) | 77 | [`matmul_19x19x20_rank4117_block47_gf2.txt`](matmul_19x19x20_rank4117_block47_gf2.txt) |
| 19x20x20 | **4235** | [4258](https://fmm.univ-lille.fr/19x20x20.html) | 23 | [`matmul_19x20x20_rank4235_block47_gf2.txt`](matmul_19x20x20_rank4235_block47_gf2.txt) |
| 19x20x21 | **4495** | [4637](https://fmm.univ-lille.fr/19x20x21.html) | 142 | [`matmul_19x20x21_rank4495_block47_gf2.txt`](matmul_19x20x21_rank4495_block47_gf2.txt) |
| 19x20x32 | **6560** | [6780](https://fmm.univ-lille.fr/19x20x32.html) | 220 | [`matmul_19x20x32_rank6560_block47_gf2.txt`](matmul_19x20x32_rank6560_block47_gf2.txt) |
| 20x20x21 | **4643** | [4740](https://fmm.univ-lille.fr/20x20x21.html) | 97 | [`matmul_20x20x21_rank4643_block47_gf2.txt`](matmul_20x20x21_rank4643_block47_gf2.txt) |
| 20x20x25 | **5442** | [5632](https://fmm.univ-lille.fr/20x20x25.html) | 190 | [`matmul_20x20x25_rank5442_block47_gf2.txt`](matmul_20x20x25_rank5442_block47_gf2.txt) |
| 20x21x32 | **7184** | [7440](https://fmm.univ-lille.fr/20x21x32.html) | 256 | [`matmul_20x21x32_rank7184_block47_gf2.txt`](matmul_20x21x32_rank7184_block47_gf2.txt) |
| 20x22x28 | **6636** | [6867](https://fmm.univ-lille.fr/20x22x28.html) | 231 | [`matmul_20x22x28_rank6636_block47_gf2.txt`](matmul_20x22x28_rank6636_block47_gf2.txt) |
| 20x23x27 | **6729** | [6962](https://fmm.univ-lille.fr/20x23x27.html) | 233 | [`matmul_20x23x27_rank6729_block47_gf2.txt`](matmul_20x23x27_rank6729_block47_gf2.txt) |
| 20x23x28 | **6866** | [7100](https://fmm.univ-lille.fr/20x23x28.html) | 234 | [`matmul_20x23x28_rank6866_block47_gf2.txt`](matmul_20x23x28_rank6866_block47_gf2.txt) |
| 20x23x29 | **7174** | [7421](https://fmm.univ-lille.fr/20x23x29.html) | 247 | [`matmul_20x23x29_rank7174_block47_gf2.txt`](matmul_20x23x29_rank7174_block47_gf2.txt) |
| 20x23x32 | **7782** | [8040](https://fmm.univ-lille.fr/20x23x32.html) | 258 | [`matmul_20x23x32_rank7782_block47_gf2.txt`](matmul_20x23x32_rank7782_block47_gf2.txt) |
| 20x24x29 | **7370** | [7632](https://fmm.univ-lille.fr/20x24x29.html) | 262 | [`matmul_20x24x29_rank7370_block47_gf2.txt`](matmul_20x24x29_rank7370_block47_gf2.txt) |
| 20x24x31 | **7830** | [8070](https://fmm.univ-lille.fr/20x24x31.html) | 240 | [`matmul_20x24x31_rank7830_block47_gf2.txt`](matmul_20x24x31_rank7830_block47_gf2.txt) |
| 20x25x31 | **8342** | [8570](https://fmm.univ-lille.fr/20x25x31.html) | 228 | [`matmul_20x25x31_rank8342_block47_gf2.txt`](matmul_20x25x31_rank8342_block47_gf2.txt) |
| 21x23x28 | **7354** | [7562](https://fmm.univ-lille.fr/) | 208 | [`matmul_21x23x28_rank7354_block47_gf2.txt`](matmul_21x23x28_rank7354_block47_gf2.txt) |
| 21x23x32 | **8282** | [8464](https://fmm.univ-lille.fr/) | 182 | [`matmul_21x23x32_rank8282_block47_gf2.txt`](matmul_21x23x32_rank8282_block47_gf2.txt) |
| 21x25x31 | **8876** | [9040](https://fmm.univ-lille.fr/) | 164 | [`matmul_21x25x31_rank8876_block47_gf2.txt`](matmul_21x25x31_rank8876_block47_gf2.txt) |
| 21x25x32 | **9066** | [9260](https://fmm.univ-lille.fr/) | 194 | [`matmul_21x25x32_rank9066_block47_gf2.txt`](matmul_21x25x32_rank9066_block47_gf2.txt) |
| 21x28x28 | **8848** | [9054](https://fmm.univ-lille.fr/) | 206 | [`matmul_21x28x28_rank8848_block47_gf2.txt`](matmul_21x28x28_rank8848_block47_gf2.txt) |
| 23x32x32 | **12214** | [12432](https://fmm.univ-lille.fr/) | 218 | [`matmul_23x32x32_rank12214_block47_gf2.txt`](matmul_23x32x32_rank12214_block47_gf2.txt) |
| 25x31x32 | **12966** | [13169](https://fmm.univ-lille.fr/) | 203 | [`matmul_25x31x32_rank12966_block47_gf2.txt`](matmul_25x31x32_rank12966_block47_gf2.txt) |
| 25x32x32 | **13206** | [13533](https://fmm.univ-lille.fr/) | 327 | [`matmul_25x32x32_rank13206_block47_gf2.txt`](matmul_25x32x32_rank13206_block47_gf2.txt) |
| 26x29x32 | **12714** | [12928](https://fmm.univ-lille.fr/) | 214 | [`matmul_26x29x32_rank12714_block47_unbalanced_gf2.txt`](matmul_26x29x32_rank12714_block47_unbalanced_gf2.txt) |
| 26x31x31 | **13112** | [13280](https://fmm.univ-lille.fr/) | 168 | [`matmul_26x31x31_rank13112_block47_unbalanced_gf2.txt`](matmul_26x31x31_rank13112_block47_unbalanced_gf2.txt) |
| 26x31x32 | **13295** | [13643](https://fmm.univ-lille.fr/) | 348 | [`matmul_26x31x32_rank13295_block47_unbalanced_gf2.txt`](matmul_26x31x32_rank13295_block47_unbalanced_gf2.txt) |
| 26x32x32 | **13510** | [13957](https://fmm.univ-lille.fr/) | 447 | [`matmul_26x32x32_rank13510_block47_unbalanced_gf2.txt`](matmul_26x32x32_rank13510_block47_unbalanced_gf2.txt) |
| 27x31x32 | **13851** | [14143](https://fmm.univ-lille.fr/) | 292 | [`matmul_27x31x32_rank13851_block47_unbalanced_gf2.txt`](matmul_27x31x32_rank13851_block47_unbalanced_gf2.txt) |
| 27x32x32 | **13999** | [14340](https://fmm.univ-lille.fr/) | 341 | [`matmul_27x32x32_rank13999_block47_unbalanced_gf2.txt`](matmul_27x32x32_rank13999_block47_unbalanced_gf2.txt) |
| 28x31x32 | **14123** | [14462](https://fmm.univ-lille.fr/) | 339 | [`matmul_28x31x32_rank14123_block47_unbalanced_gf2.txt`](matmul_28x31x32_rank14123_block47_unbalanced_gf2.txt) |
| 28x32x32 | **14271** | [14596](https://fmm.univ-lille.fr/) | 325 | [`matmul_28x32x32_rank14271_block47_unbalanced_gf2.txt`](matmul_28x32x32_rank14271_block47_unbalanced_gf2.txt) |

The largest saved improvement against the live FMM table is 447
multiplications for 26x32x32.  Several other gains exceed 300.  The FMM column
is a stable, linkable baseline, not the sole novelty test: the audit also
checked stronger recent entries in `matmulcatalog` and `fmm-17-32`.
For example, `matmulcatalog` publishes a stronger
[rank-4154 construction for 19x19x20](https://github.com/solven-eu/matmulcatalog/blob/0320f745d87e46c36259b03add05307429941680/src/main/resources/schemes/derived/section20/19x19x20-r4154-derived-014511d.json)
than the rank-4194 FMM baseline shown in the table; the saved rank-4117
certificate still improves that strongest audited same-shape rank by 37.

The same S3- and field-normalized audit was applied to the 12--20 records.
`matmulcatalog` has stronger baselines than the FMM table for five of them:
15x17x19 rank 2921, 15x20x20 rank 3494, 13x15x20 rank 2382,
12x16x19 rank 2186, and 12x20x20 rank 2781.  The saved ranks still improve
those strongest audited same-shape ranks by 59, 66, 61, 49, and 55,
respectively.  No matching certificate in any S3 orientation appears in the
current `fmm-17-32` scheme set.

For 13x13x20, the strongest materialized same-shape scheme in the refreshed
sources is rank 2099 and explicitly includes F2; rank 2052 improves it by 47.
The catalogue's rank-2098 value is an unmaterialized Q-only search prediction,
not a certificate, and the new GF(2) rank is still 46 lower numerically.  For
14x19x20, the materialized all-field baseline is rank 3187; an unmaterialized
Q-only prediction is 3166, while the saved rank 3130 remains below both.
Lower generalized-Waksman counts for these shapes assume commutative scalar
multiplication and are not noncommutative tensor-rank comparators.

For 13x14x20, the strongest concrete comparator is an independently reverified
integer rank-2236 scheme in `fmm-17-32`; the catalogue's rank-2237 search value
is unmaterialized.  Rank 2203 improves the exact scheme by 33.  For 14x17x19,
the registered rank-2753/2755 lineages omit F2 and contain no explicit factor
arrays, while the unmaterialized search prediction is 2740.  The exact rank
2703 certificate is below all of those numerical values; its conservative
GF(2) margin is 56 against the live FMM value 2759.

For the wide 21--32 additions, the audit used the lower rank displayed by the
live FMM main table whenever an older per-shape detail page disagreed.  The
`fmm-17-32` snapshot contains one stronger same-shape baseline, rank 9240 for
21x25x32; rank 9066 still improves it by 174.  No other equal or lower scheme
for these ten targets was found in that repository, matmulcatalog, or
FastMatrixMultiplication.  Their 5--8 leaf inputs all carry explicit `F2`
metadata; the rank-329 `888` leaf is GF(2)-specific, so none of these claims is
silently promoted to characteristic zero.

The later ordered-allocation pass found that the balanced restriction was
material at the top of the range.  For total 26, for example, the split
`6,6,6,8` can cost much less on this outer support pattern than any permutation
of `6,6,7,7`.  Eight exact certificates were saved; two replace earlier
balanced certificates and six add shapes to the manifest.  Against the
strongest S3-normalized pinned source, their gains are 386 (26x32x32), 348
(26x31x32), 325 (28x32x32), 316 (28x31x32), 212 (26x29x32), 202
(27x31x32), 168 (26x31x31), and 161 (27x32x32).  Recipes, hashes, and exact
baseline paths are in
[`block_composition_unbalanced_audit.tsv`](block_composition_unbalanced_audit.tsv),
with revisions in
[`block_composition_unbalanced_audit_sources.tsv`](block_composition_unbalanced_audit_sources.tsv).
Recursive compositions beyond dimension 32 were not promoted: the audited
sources provide no comparable complete >32 frontier, so exactness alone would
not support a record claim.

The bounded small-block follow-up tested every sorted 12--20 target with a
size-1 or size-2 block, and every sorted 26--32 target with a forced size-9
block.  Size 9 never improved a formula; its closest result lost by 33.  The
small-block pass produced exact rank 2041 for 14x16x16, replacing the saved
rank 2047, plus exact rank 1251 for 12x12x14.  Public constructive
Hopcroft--Kerr ranks 15, 20, and 26 supply the required `233`, `234`, and `244`
leaves.  Source JSON, converted-leaf, recipe, and certificate hashes are in
[`block_composition_smallblock_audit.tsv`](block_composition_smallblock_audit.tsv)
and
[`block_composition_smallblock_audit_sources.tsv`](block_composition_smallblock_audit_sources.tsv).

The continuous 12--32 scan exposed a previously omitted 20/21 cross-band.
The thirteen saved cross-band rows are exact and strict after the same audit.
Where a stronger non-FMM baseline exists, the audited gains remain positive:
20x24x29 improves catalog rank 7600 by 230; 20x21x32 improves the integer
`fmm-17-32` rank 7410 by 226; 20x22x28 improves its rank 6859 by 223;
20x20x25 improves catalog rank 5611 by 169; and 19x20x21 improves catalog
rank 4596 by 101.  The complete comparison and its pinned source revisions are
[`block_composition_cross_audit.tsv`](block_composition_cross_audit.tsv) and
[`block_composition_cross_audit_sources.tsv`](block_composition_cross_audit_sources.tsv).

Four rows require explicit labels.  The 16x16x16 rank-2209 certificate is an
independent co-record: `matmulcatalog` already publishes the exact GF(2)
[47-squared construction](https://github.com/solven-eu/matmulcatalog/blob/0320f745d87e46c36259b03add05307429941680/src/main/resources/schemes/derived/section16/16x16x16-r2209-derived-d9d28d8.json).
The 12x12x14 rank-1251 certificate improves the strongest pinned GF(2) rank
1260 by nine, but rational ranks 1234 and 1240 and a characteristic-3 rank
1248 are lower.  Likewise, the 18x19x19 rank-3812 certificate is a strict
apparent GF(2) record, but not an unqualified numerical record: a
[rank-3798 certificate](https://github.com/solven-eu/matmulcatalog/blob/0320f745d87e46c36259b03add05307429941680/src/main/resources/schemes/derived/section19/18x19x19-r3798-derived-d5c7e56.json)
exists over Q and does not reduce to a valid GF(2) scheme.  Finally,
15x15x17 rank 2262 improves the audited GF(2) value 2320, while a rank-2260
scheme over F3/Q/R/C has no F2-valid reduction.  Of the 176 strict GF(2)
entries, 171 also beat every audited same-shape rank numerically.

The exact-tie scan is broader still.  Among all 165 sorted shapes with
dimensions 12 through 20, 116 formula ranks beat the live FMM rank.  Exact
zero pruning adds two more wins, for 118 candidates total.  The separate
21--32 slice covers 364 shapes and found 130 preliminary formula wins; its ten
largest refreshed strict gains are included here.  The complete 3--8-leaf
scanner covers all 1,771 sorted shapes from 12 through 32.  Its 1,242-shape
cross-band slice has 840 live-FMM wins, of which 760 beat every audited
numerical baseline.  The ten largest audited gains and three requested seam
examples are saved here.  The 146 legacy rows above and 40 small-cross rows
are materialized, hashed, and manifest-gated; the remaining two rejected
12--20 formulas are listed with
their reproducible recipes in
[`block_composition_opportunities.tsv`](block_composition_opportunities.tsv).
Their prior-art dispositions are explicit in
[`block_composition_queue_closure_audit.tsv`](block_composition_queue_closure_audit.tsv).
The broader unmaterialized cross-band formulas remain in the persisted audit
rather than being mislabeled as exact-best queue entries.

## Reproduce and verify

Build the pure-Tungsten composer and materialize a target:

```sh
bin/tungsten compile --release --lto \
  -o /tmp/flipfleet-block-compose \
  benchmarks/matmul/metaflip/flipfleet_block_compose.w
/tmp/flipfleet-block-compose 15x16x17 /tmp/r15x16x17.txt
```

Exhaust every ordered 3--8 allocation and S3 source ordering, then exact-gate
the selected recipe:

```sh
bin/tungsten compile --release --native --lto \
  -o /tmp/flipfleet-block-unbalanced-compose \
  benchmarks/matmul/metaflip/flipfleet_block_unbalanced_compose.w
/tmp/flipfleet-block-unbalanced-compose 26x32x32 /tmp/r26x32x32.txt
```

Reproduce the formula and exact-tie scans:

```sh
bin/tungsten compile --release --lto \
  -o /tmp/flipfleet-block-formula-scan \
  benchmarks/matmul/metaflip/flipfleet_block_formula_scan.w
/tmp/flipfleet-block-formula-scan > /tmp/formula.tsv

bin/tungsten compile --release --lto \
  -o /tmp/flipfleet-block-formula-scan-wide \
  benchmarks/matmul/metaflip/flipfleet_block_formula_scan_wide.w
/tmp/flipfleet-block-formula-scan-wide > /tmp/formula-wide.tsv

bin/tungsten compile --release --lto \
  -o /tmp/flipfleet-block-formula-scan-cross \
  benchmarks/matmul/metaflip/flipfleet_block_formula_scan_cross.w
/tmp/flipfleet-block-formula-scan-cross > /tmp/formula-cross.tsv

bin/tungsten compile --release --lto \
  -o /tmp/flipfleet-block-variant-scan \
  benchmarks/matmul/metaflip/flipfleet_block_variant_scan.w
/tmp/flipfleet-block-variant-scan stabletable > /tmp/exact.tsv
```

Reload and exact-gate every saved record:

```sh
bin/tungsten compile --release --lto \
  -o /tmp/flipfleet-block-records-test \
  benchmarks/matmul/metaflip/flipfleet_block_records_test.w
/tmp/flipfleet-block-records-test
```

The implementation details, leaf provenance, and explicit-allocation syntax
are documented in [`BLOCK_COMPOSITION.md`](BLOCK_COMPOSITION.md).
