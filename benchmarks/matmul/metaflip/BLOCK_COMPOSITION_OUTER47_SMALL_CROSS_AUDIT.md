# Rank-47 outer variants and exact small-cross tie closure

Status date: 2026-07-14. All constructions in this note are over GF(2).

This audit asks whether the support pattern of the alternate rank-47
`4x4x4` scheme `matmul_4x4_rank47_d677_flips_gf2.txt` improves the complete
8--11-by-32 block-composition seam. It also closes a separate weakness in the
original formula scan: a formula-minimizing balanced allocation can embed
some leaf terms as zero, and a different allocation tied at the same formula
rank can expose more such removals.

Both rank-47 outers and all 84 sorted 2--8 leaves are reconstructed exactly
before scoring. The d450 calculation is additionally replayed row-for-row
against `block_composition_small_cross_scan.tsv`; the scanner aborts on one
rank or target mismatch.

## Alternate d677 support result

Across all 1,154 sorted targets `8 <= n <= 11`, `n <= m <= p <= 32`, d677
has **zero formula wins**, 217 ties, and 937 losses against d450. Its largest
loss is 166 terms. Materializing the deterministic formula-minimizer for both
outers still gives **zero d677 exact-rank wins**:

| outer | selected recipes below formula rank | largest reduction |
|---|---:|---:|
| d450 | 107 / 1,154 | 12 |
| d677 | 285 / 1,154 | 6 |

The extra d677 removals never recover its formula deficit. The full tables are
`block_composition_outer47_small_cross_formula.tsv` (SHA-256
`2b8e728efb7ad339ca7dfb8d3c693b3bbdaadd12c6f7ef932a28da92f26a9b08`)
and `block_composition_outer47_small_cross_selected_exact.tsv` (SHA-256
`da047d93c0ba61a05054ccf338f5ab6accb656e0436963ef8152936ca4eb0b3c`).
The alternate outer therefore stays offline; d450 remains the production
rank-47 outer for this band.

## Exhaustive balanced tie materialization

The d450 scan contains 14,362 formula-minimizing balanced allocation/S3
recipes, between 1 and 72 per target. Every one was parity-materialized. This
improves 158 targets below formula rank, with a maximum reduction of 12; 53
targets improve beyond the deterministic first formula-minimizer. Every
reduction is a mapped-zero removal. Duplicate-term parity contributes zero on
all 1,154 best tied recipes.

`block_composition_outer47_small_cross_tie_count.tsv` records every tie count
(SHA-256
`cc0b7584258d1aa4992e5b384908ac7098056094913d7fa5b3399d74e607a508`),
and `block_composition_outer47_small_cross_tie_exact.tsv` records the exact
winner and recipe for every target (SHA-256
`addce3944cfaea76c6f8ee102568e3990e5ab6933867109c39971cc854baad08`).

The closure exposes seven additional strict GF(2) certificates relative to
the original balanced materialization set:

| target | formula | exact | pinned GF(2) | gain | cause |
|---|---:|---:|---:|---:|---|
| 10x16x26 | 2510 | **2509** | 2527 | 18 | tied recipe, one mapped zero |
| 10x22x23 | 3073 | **3071** | 3072 | 1 | two mapped zeros; crosses loss to win |
| 11x15x25 | 2478 | **2476** | 2514 | 38 | two mapped zeros |
| 11x15x26 | 2597 | **2593** | 2617 | 24 | four mapped zeros |
| 11x15x27 | 2700 | **2694** | 2703 | 9 | six mapped zeros |
| 11x17x19 | 2194 | **2190** | 2205 | 15 | four mapped zeros |
| 11x19x19 | 2442 | **2430** | 2462 | 32 | twelve mapped zeros |

Seven more exact upper bounds have no pinned explicit/reducible GF(2)
comparator, so they are deliberately labelled **uncovered**, not records.
Each is nevertheless below every pinned numerical comparator:

| target | formula | exact | best pinned numerical rank |
|---|---:|---:|---:|
| 11x13x26 | 2273 | **2272** | 2295 |
| 11x13x27 | 2361 | **2359** | 2393 |
| 11x14x25 | 2336 | **2335** | 2361 |
| 11x14x26 | 2443 | **2441** | 2452 |
| 11x14x27 | 2543 | **2539** | 2555 |
| 11x26x29 | 4901 | **4900** | 4915 |
| 11x27x29 | 5084 | **5082** | 5098 |

The independent ordered-allocation closure contributes two further strict
certificates: 10x16x16 rank **1558** (pinned GF(2) 1578; also below the pinned
characteristic-zero 1560) and 10x16x17 rank **1694** (pinned universal/GF(2)
1696). Its complete field-aware table is
`block_composition_small_cross_unbalanced_full_audit.tsv`, SHA-256
`c93cddba33af6d6a89c44e67c6934f301e6c83c9c467ee12245d157fdefb1908`.

## Certificate gates and final accounting

All sixteen promotions in this follow-up were serialized, reloaded, and
reconstructed by the pure-Tungsten wide-factor gate. The complete manifest
then passed a separate Python sparse-parity reconstruction under Apple Python
3.9 and Homebrew Python with byte-identical output. The final audit covers
186 certificates, 683,804 rank-one terms, and 113,590,185 expanded `(U,V)`
support pairs:

- manifest SHA-256:
  `d0a6e50c02a60f5b73688b4d9e6ffd90438efba4fea86c4c550b19d5e0420d22`;
- independent-audit SHA-256:
  `796f5f3cf7b1cd65551cb19d6aca85d3c6028710e6776a6de879a0626b050b2c`;
- classification: **176 strict apparent GF(2) records, one co-record, and
  nine uncovered exact upper bounds**.

Every artifact/source hash is pinned in
`block_composition_outer47_small_cross_sources.tsv`.

## Replay

```sh
bin/tungsten compile --release --lto \
  -o /tmp/outer47-formula \
  benchmarks/matmul/metaflip/flipfleet_block_outer47_small_cross_scan.w
/tmp/outer47-formula > /tmp/outer47-formula.tsv

bin/tungsten compile --release --lto \
  -o /tmp/outer47-exact \
  benchmarks/matmul/metaflip/flipfleet_block_outer47_small_cross_exact.w
/tmp/outer47-exact > /tmp/outer47-selected-exact.tsv
/tmp/outer47-exact tie-count > /tmp/outer47-tie-count.tsv
for n in 8 9 10 11; do
  /tmp/outer47-exact tie-exact "$n" > "/tmp/outer47-tie-exact-$n.tsv"
done

python3 benchmarks/matmul/metaflip/verify_block_composition_records.py \
  -j 4 --audit /tmp/block-composition-independent.tsv
```
