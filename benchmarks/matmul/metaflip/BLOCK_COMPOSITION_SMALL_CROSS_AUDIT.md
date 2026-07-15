# Complete two-wide leaf pool and the 8--11 small-cross audit

Status date: 2026-07-14. Every construction in this note is over GF(2).
The numerical comparisons to characteristic zero or another field do not turn
the formulas into all-field algorithms: the rank-47 outer used here is
GF(2)-only.

## The omitted seam

The original block campaign was complete for sorted leaf shapes 3--8 and for
balanced targets 12--32. It separately checked the small cube 8--11 with the
`222` and `223` leaves. Those ranges leave a real seam: a target such as
`11x20x32` induces leaves `2xa xb`, with `a,b` as large as eight. The production
composer previously knew only a sparse subset of those shapes and therefore
could not score the balanced recipe at all.

The leaf pool now contains one exact certificate for every sorted shape

```text
2 <= a <= b <= 8 in <2,a,b>   (28 shapes)
3 <= a <= b <= c <= 8         (56 shapes)
```

for 84 shapes total. Eighteen missing two-wide certificates were imported from
verified entries in `matmulcatalog` at commit
`0320f745d87e46c36259b03add05307429941680`. The importer corrects the
catalogue's transposed W convention, reduces integral coefficients modulo two,
and reconstructs every target tensor before writing. A second audit loaded all
28 two-wide files, checked dimensions and factor bounds, rejected duplicates,
and independently reconstructed every coefficient. Their ranks match the best
pinned GF(2)/integer rank for all 28 shapes.

The machine-readable leaf audit is
[`block_composition_2wide_leaf_audit.tsv`](block_composition_2wide_leaf_audit.tsv),
SHA-256 `2fa70b2612cdab2c9e4938ce0300396e445ca273af43605e77600fde58330dcf`.
Source JSON paths, revisions, source hashes, imported-file hashes, and code
hashes are pinned in
[`block_composition_small_cross_audit_sources.tsv`](block_composition_small_cross_audit_sources.tsv).

## Complete balanced scan

`flipfleet_block_formula_scan_small_cross.w` scans all 1,154 sorted targets

```text
8 <= n <= 11,  n <= m <= p <= 32
```

through every balanced allocation and every unique S3 source orientation. It
loads and exact-gates all 84 leaves before scoring. The raw table is
[`block_composition_small_cross_scan.tsv`](block_composition_small_cross_scan.tsv),
SHA-256 `1c9dce45aada5646a3de470ed05515175e4529c49769a41c82c5df5977bc86bd`.
An independent implementation replayed all 1,154 formula ranks from the 47
outer support triples and the 84 leaf ranks, with zero mismatches.

The field-aware comparison is
[`block_composition_small_cross_audit.tsv`](block_composition_small_cross_audit.tsv),
LF-normalized SHA-256
`a4e9145f987e0906bae5de6a16462dc0e29ff20e4bad29f4715ae0603819dba3`.
It is generated deterministically by
[`block_composition_small_cross_audit.py`](block_composition_small_cross_audit.py)
from the balanced scan and three pinned tables: matmulcatalog's `catalog.json`
and `cited-bounds.json`, plus FastMatrixMultiplication's `status.json`.  The
generator uses only the Python 3.9 standard library and writes explicit LF
line endings.

The classifier rejects commutative-only catalog entries.  The conservative
GF(2) comparison admits catalog schemes explicitly marked `F2` and exact FMM
`Z`/`ZT` schemes that reduce modulo two.  The universal comparison admits
noncommutative integral identities; the characteristic-zero comparison admits
`Z`, `Q`, `R`, and `C`; and the any-field numerical comparison admits every
field class.  Equal ranks are resolved by the stable order explicit FMM,
numerical-only bound, explicit catalog scheme, then lexical source path.

For byte compatibility, numerical-only bounds retain the audit's historical
`fmm-lille-pinned:<shape URL>` label.  This is a coarse comparison label, not
the claim's complete attribution.  Actual source, algorithm, field, and year
come from the pinned `cited-bounds.json`; its SHA-256 is recorded in
[`block_composition_small_cross_audit_sources.tsv`](block_composition_small_cross_audit_sources.tsv).
The result is:

| comparison | win | tie | loss | no pinned comparator |
|---|---:|---:|---:|---:|
| explicit/reducible GF(2) | **129** | 2 | 382 | 641 |
| universal integer, numerical only | 130 | 1 | 382 | 641 |
| characteristic zero, numerical only | 303 | 3 | 848 | 0 |
| any field, numerical only | 302 | 4 | 848 | 0 |

There are zero new all-field formulas in those latter three rows. A separate
control loaded an exact signed rank-49 `<4,4,4>` outer and the best universal
2--8 leaf ranks, then rescanned all 1,154 targets. It produced zero wins against
any pinned baseline. The negative table is
[`block_composition_small_cross_allfield49.tsv`](block_composition_small_cross_allfield49.tsv).

## Materialized records

The twenty largest conservative GF(2) gains were materialized, serialized,
reloaded, and reconstructed by the independent Tungsten verifier. None relied
on post-embedding cancellation: exact rank equalled formula rank in all twenty.

| target | new exact rank | pinned GF(2) rank | gain |
|---|---:|---:|---:|
| 11x28x28 | **4937** | 5120 | **183** |
| 11x20x32 | **4014** | 4160 | 146 |
| 11x20x28 | **3521** | 3655 | 134 |
| 11x20x29 | **3685** | 3813 | 128 |
| 11x20x31 | **3940** | 4063 | 123 |
| 11x20x27 | **3447** | 3559 | 112 |
| 11x20x30 | **3822** | 3933 | 111 |
| 11x20x25 | **3192** | 3302 | 110 |
| 11x20x24 | **3028** | 3128 | 100 |
| 11x20x26 | **3329** | 3428 | 99 |
| 8x19x32 | **2865** | 2958 | 93 |
| 8x20x31 | **2897** | 2990 | 93 |
| 11x20x21 | **2730** | 2816 | 86 |
| 8x19x28 | **2505** | 2590 | 85 |
| 11x20x23 | **2961** | 3046 | 85 |
| 11x20x22 | **2854** | 2932 | 78 |
| 8x17x32 | **2589** | 2663 | 74 |
| 11x21x21 | **2892** | 2964 | 72 |
| 8x19x24 | **2145** | 2216 | 71 |
| 8x17x28 | **2275** | 2345 | 70 |

All comparator files are verified catalog constructions explicitly valid over
`F2,F3,Z,Q,R,C`; their exact paths are in the audit TSV. The certificates and
SHA-256 hashes are in the central
[`block_composition_records.tsv`](block_composition_records.tsv) manifest.

Two smaller records make the direct value of the new `<2,3,5>` leaf visible:
`8x11x20` uses it 39 times and improves 1138 to exact **1119**; `8x12x20`
uses it in all 47 outer terms and improves 1192 to exact **1175**. Repeating
both constructions with each of the five checked-in rank-25 `<2,3,5>` doors
(densities 160, 170, 173, 210, and 278) preserved ranks 1119 and 1175 in all
ten cases. The d160 fleet leader is the stable production choice, but the rank
claims do not depend on that presentation.

Two further exact upper bounds, `11x16x31` rank 3195 and `11x16x32` rank 3255,
numerically improve the best pinned any-field values by 92 and 118 but have no
explicit/reducible GF(2) comparator in the pinned sources. They are retained in
the manifest and labelled uncovered rather than counted among the 129 strict
GF(2) wins.

## Replay

From the repository root:

```sh
python3 benchmarks/matmul/metaflip/block_composition_small_cross_audit.py \
  --self-test

python3 benchmarks/matmul/metaflip/block_composition_small_cross_audit.py \
  --catalog "$MATMULCATALOG/docs/catalog.json" \
  --cited-bounds "$MATMULCATALOG/docs/cited-bounds.json" \
  --status "$FAST_MATRIX_MULTIPLICATION/schemes/status.json" \
  --require-pinned \
  --check benchmarks/matmul/metaflip/block_composition_small_cross_audit.tsv \
  --output /tmp/block_composition_small_cross_audit.tsv

cmp /tmp/block_composition_small_cross_audit.tsv \
  benchmarks/matmul/metaflip/block_composition_small_cross_audit.tsv

bin/tungsten compile --release --lto -o /tmp/ffbc-small-cross \
  benchmarks/matmul/metaflip/flipfleet_block_formula_scan_small_cross.w
/tmp/ffbc-small-cross > /tmp/ffbc-small-cross.tsv

bin/tungsten compile --release --lto -o /tmp/ffbc-leaf-test \
  benchmarks/matmul/metaflip/flipfleet_block_leaf_pool_test.w
/tmp/ffbc-leaf-test

bin/tungsten compile --release --lto -o /tmp/ffbc-compose \
  benchmarks/matmul/metaflip/flipfleet_block_compose.w
/tmp/ffbc-compose 11x28x28 /tmp/11x28x28.txt

bin/tungsten compile --release --lto -o /tmp/ffbc-verify \
  benchmarks/matmul/metaflip/flipfleet_block_verify.w
/tmp/ffbc-verify /tmp/11x28x28.txt 11x28x28
```

`flipfleet_block_small_cross_unbalanced_scan.w` exhausts every ordered 2--8
allocation for the 129 strict balanced winners. Its scorer precomputes the
pairwise U/V/W support extents and uses a dense oriented leaf-rank table; a
reference-equivalence test preserves the original traversal and first-minimum
tie rule. The complete release run took 195.92 seconds and 5.55 GB peak RSS,
versus more than two hours without completing the first buffered full pass.
The memory is process-lifetime scratch in this offline scanner, not a live
fleet allocation.

Exactly one target improves: `10x16x16` changes from balanced formula rank
1570 to formula and exact rank **1558** under allocation
`2,2,2,4 | 4,4,4,4 | 4,4,4,4`. This beats the pinned reducible GF(2)/integer
rank 1578 by 20 and the best pinned characteristic-zero numerical rank 1560
by two, while remaining a GF(2)-specific construction. The complete 129-row
closure is
[`block_composition_small_cross_unbalanced_audit.tsv`](block_composition_small_cross_unbalanced_audit.tsv),
SHA-256 `5dac1d08b844a7eb82e532933d25b4c208f61e8efea2b850c5c6e3ebc00abf0b`.
The focused unbalanced pass remains deliberately separate from the production
balanced default.

A sharded follow-up then applied the same exhaustive scorer to all 1,154
small-cross rows, including balanced ties, losses, and targets without a
pinned GF(2) comparator. Eight shards took 124--141 seconds each; four-at-a-
time execution bounds retained scratch while closing the table in two waves.
Thirty-eight formulas improve by 345 aggregate terms, with a maximum reduction
of 54. Most remain behind their comparators. One balanced loss becomes a new
strict result: `10x16x17` falls from formula 1698 to formula and exact rank
**1694**, beating the pinned universal integer/GF(2) rank 1696 by two.
Together with `10x16x16`, these are the only new numerical comparator wins
created by unbalancing; the latter was already a GF(2) formula win but now also
beats the pinned characteristic-zero value.

The complete field-aware closure is
[`block_composition_small_cross_unbalanced_full_audit.tsv`](block_composition_small_cross_unbalanced_full_audit.tsv),
SHA-256 `c93cddba33af6d6a89c44e67c6934f301e6c83c9c467ee12245d157fdefb1908`.
Every row retains the selected allocation, source ordering, S3 code, and
recomputed GF(2), universal, characteristic-zero, and any-field disposition.

All 38 improved layouts were then materialized and passed the complete tensor
gate. Two receive additional duplicate-parity cancellation—10x11x11 drops
844→840 and 10x15x15 drops 1454→1452—but both remain behind their pinned
baselines. The two comparator wins materialize exactly at formula rank, so no
claim relies on an estimated cancellation. The exact closure is
[`block_composition_small_cross_unbalanced_exact_audit.tsv`](block_composition_small_cross_unbalanced_exact_audit.tsv),
SHA-256 `62dbf60cf73598e990d612725df80028f705dd1a336ee2cd8c8a7c36783328d9`.

## Exhaustive bounded formula-tie closure

The selected-recipe exact pass above leaves one narrow loophole: another
ordered 2--8 allocation, or another unique S3 source orientation, can tie the
global bounded formula minimum but lose fewer terms when embedded. The
pure-Tungsten
[`flipfleet_block_small_cross_bounded_tie_exact.w`](flipfleet_block_small_cross_bounded_tie_exact.w)
now replays every allocation triple with the fast extent-table scorer, aborts
if any triple undercuts the pinned bounded minimum, and parity-materializes
**every** formula-minimizing tie. Each target runs in a separate process to
bound the research runtime's process-lifetime scratch. The winning recipe is
then rebuilt through `ffbc_compose_oriented_recipe`, checked by
`ffbc_verify_exact`, serialized on a comparator win, reloaded, and checked
again.

The initial formula-gap-0--2 pass covers 11 targets and 73 tied recipes. The
completed gap-0--12 pass covers **56 targets and 648 tied recipes**, with one
to 60 recipes per target. Only two targets fall below formula rank, both by
two mapped-zero terms and neither by duplicate parity:

| target | formula | exact | pinned GF(2) | result |
|---|---:|---:|---:|---|
| 10x14x16 | 1426 | 1424 | 1418 | remains six behind |
| 10x22x23 | 3073 | 3071 | 3072 | repeats the already-published balanced-tie win via a different minimizing recipe |

The two formula co-records, 8x8x8 rank 329 and 8x11x15 rank 859, receive no
embedding reduction. Thus this exhaustive extension finds **no new numerical
record** beyond the balanced-tie campaign and closes the most promising
unbalanced cancellation seam through a 12-term deficit. The alternate
10x22x23 presentation is retained as an independently exact archive door at
[`matmul_10x22x23_rank3071_block47_bounded_tie_gf2.txt`](matmul_10x22x23_rank3071_block47_bounded_tie_gf2.txt),
SHA-256 `a078b1f00fbeb005d69c701f8c32f69c60ac27057a27c22b5dcbc44c542e7390`;
it is not counted again in the central record manifest.

The complete 56-row closure is
[`block_composition_small_cross_bounded_tie_exact_audit.tsv`](block_composition_small_cross_bounded_tie_exact_audit.tsv),
SHA-256 `a96aae2d81452f1fc73ac88c7d274b337168ccc893226524781fac2104eb04b9`.
On the M5 Max reference host, formula counting through gap 2 took 7.5 seconds;
counting through gap 12 took 28.5 seconds. Four-way exact materialization took
15.7 seconds wall time (57.9 aggregate user seconds, 3.74 seconds maximum for
one target). The dedicated regression
[`flipfleet_block_small_cross_bounded_tie_test.w`](flipfleet_block_small_cross_bounded_tie_test.w)
reconstructs both reduced recipes and the serialized certificate, and pins
all row, tie, disposition, and cancellation totals.

```sh
bin/tungsten compile --release --lto -o /tmp/ffbc-bounded-ties \
  benchmarks/matmul/metaflip/flipfleet_block_small_cross_bounded_tie_exact.w
/tmp/ffbc-bounded-ties count 12

# Run each target emitted by count mode in a fresh process; concatenate the
# one data row from each exact invocation in version-sort order.
/tmp/ffbc-bounded-ties exact 10x14x16
/tmp/ffbc-bounded-ties exact 10x22x23

bin/tungsten compile --release --lto -o /tmp/ffbc-bounded-tie-test \
  benchmarks/matmul/metaflip/flipfleet_block_small_cross_bounded_tie_test.w
/tmp/ffbc-bounded-tie-test
```

## Rank-47 support and balanced-tie closure

The alternate exact rank-47 d677 outer was also scanned over all 1,154
targets with the complete leaf pool. It produces zero formula wins (217 ties,
937 losses) and zero selected-recipe exact wins against d450, so it remains an
offline control. Exhausting all 14,362 d450 formula-minimizing balanced
allocation/S3 ties is more useful: mapped-zero pruning strengthens seven
strict certificates and seven uncovered upper bounds, while duplicate parity
never contributes. Together with the two ordered-allocation winners above,
the small-cross campaign now contributes 40 checked-in certificates: 31
strict apparent GF(2) records and nine uncovered upper bounds.

The complete tables, hashes, promoted ranks, exact-gate counts, and replay
commands are in
[`BLOCK_COMPOSITION_OUTER47_SMALL_CROSS_AUDIT.md`](BLOCK_COMPOSITION_OUTER47_SMALL_CROSS_AUDIT.md).
