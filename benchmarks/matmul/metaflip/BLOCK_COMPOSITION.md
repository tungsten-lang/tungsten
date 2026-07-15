# Support-aware block composition

`flipfleet_block_composer.w` is a pure-Tungsten constructive implementation of
support-aware outer recombination over GF(2).  It accepts any exact outer
`<a,b,c>` scheme, three per-axis block allocations, and a pool of exact leaf
schemes.  For each outer product it:

1. computes the maximum allocated row/column size touched by each outer
   factor;
2. takes the common-axis minima to obtain the effective leaf shape;
3. selects and S3-orients the lowest-rank supplied leaf;
4. embeds the leaf across every supported outer block, truncating coordinates
   outside that block;
5. drops mapped zero products and cancels duplicate triples over GF(2); and
6. exactly reconstructs the complete target tensor before writing anything.

This generalises the fixed 7x7 Sedoglavic composer.  In particular it handles
rectangular targets and outer schemes other than Strassen.

## Wide factors

FlipFleet's live 3x3--7x7 walkers store one factor in a signed `i64`.  That is
not enough for these certificates: a 19x19 factor has 361 coordinates.
The composer instead stores every factor in a flattened `i64[]` of 30-bit
limbs.  The conservative limb width keeps shifts positive and makes conversion
between limbs and decimal overflow-safe.

Certificate files retain the interoperable

```
R <decimal-U-mask> <decimal-V-mask> <decimal-W-mask>
```

format.  Parsing and printing operate directly on the limbs; they do not use
boxed wide integers or wide `String#to_i` conversions.  Exact verification
accumulates one chunked C mask for every `(A-coordinate,B-coordinate)` pair,
then compares every slice with the matrix-multiplication tensor.  Its cost is
proportional to `sum |U_t||V_t|`, rather than the naive `n^6 * rank` loop.

## CLI

Build from the repository root:

```sh
bin/tungsten compile --release --lto \
  -o /tmp/flipfleet-block-compose \
  benchmarks/matmul/metaflip/flipfleet_block_compose.w
```

With no allocation arguments, the CLI scans all balanced four-way placements
for every unique S3 ordering of the requested target.  It first finds the
lowest support-aware formula rank, then materializes every recipe tied at that
rank and chooses the lowest exact rank after zero pruning.  It emits the
winner under the requested dimensions and exact-verifies it:

```sh
/tmp/flipfleet-block-compose 13x13 /tmp/r13.txt
/tmp/flipfleet-block-compose 15x16x17 /tmp/r15x16x17.txt
/tmp/flipfleet-block-compose 16x16x17 /tmp/r16x16x17.txt
/tmp/flipfleet-block-compose 19x19 /tmp/r19.txt
```

`NxN` means the square tensor `<N,N,N>`.  Rectangular tensor notation is
`NxMxP`.  For example, the default 15x16x17 scan selects source 16x15x17 at
formula and exact rank 2329, then applies S3 code 4 to emit the requested
15x16x17 certificate.  An explicit recipe can be supplied after the output
path; explicit mode keeps the given target ordering and allocations unchanged:

```sh
/tmp/flipfleet-block-compose 15x15 /tmp/r15.txt \
  3,4,4,4 4,4,4,3 3,4,4,4
```

The library entry points `ffbc_compose`, `ffbc_score_allocation`,
`ffbc_best_exact_oriented_balanced_recipe`, `ffbc_bounded_allocations`,
`ffbc_best_oriented_bounded_recipe`, and `ffbc_compose_files` accept
arbitrary allocations or expose the same exact-tie selector.  A missing induced
leaf shape is reported as unsupported instead of silently padding it.
`ffbc_orient_scheme` materialises any of the six exact S3-equivalent tensor
orientations, allowing a target-order scan to publish its best construction
under a canonical shape.

## Saved exact constructions

The machine-readable recipes and hashes are in
`block_composition_records.tsv`.  Current highlights are:

| target | formula | exact | cancellation |
|---|---:|---:|---:|
| 12x16x19 | 2137 | **2137** | 0 |
| 12x20x20 | 2726 | **2726** | 0 |
| 13x13x13 | 1402 | **1402** | 0 |
| 13x13x14 | 1501 | **1501** | 0 |
| 13x13x15 | 1582 | **1582** | 0 |
| 13x13x16 | 1651 | **1648** | 3 post-embedding removals |
| 13x13x20 | 2052 | **2052** | 0 |
| 13x14x20 | 2203 | **2203** | 0 |
| 13x15x15 | 1798 | **1796** | 2 post-embedding removals |
| 13x17x19 | 2516 | **2516** | 0 |
| 13x19x19 | 2826 | **2822** | 4 duplicate-parity removals |
| 13x20x20 | 3014 | **3014** | 0 |
| 14x19x20 | 3130 | **3130** | 0 |
| 14x17x19 | 2705 | **2703** | 2 post-embedding removals |
| 15x15x15 | 2014 | **2008** | 6 mapped zero terms |
| 15x15x16 | 2074 | **2074** | 0 |
| 15x15x17 | 2262 | **2262** | 0 |
| 15x16x16 | 2137 | **2137** | 0 |
| 15x16x17 | 2329 | **2329** | 0 |
| 15x16x19 | 2629 | **2629** | 0 |
| 15x16x20 | 2716 | **2716** | 0 |
| 15x17x20 | 2952 | **2952** | 0 |
| 15x20x20 | 3428 | **3428** | 0 |
| 16x16x17 | 2417 | **2417** | 0 |
| 16x16x19 | 2716 | **2716** | 0 |
| 16x17x18 | 2818 | **2818** | 0 |
| 16x17x20 | 3076 | **3076** | 0 |
| 17x17x17 | 2867 | **2867** | 0 |
| 17x18x19 | 3422 | **3420** | 2 mapped zero terms |
| 17x20x20 | 3844 | **3844** | 0 |
| 18x19x19 | 3820 | **3812** | 8 post-embedding removals |
| 19x19x19 | 4005 | **3993** | 12 mapped zero terms |
| 19x20x20 | 4235 | **4235** | 0 |
| 19x20x21 | 4495 | **4495** | 0 |
| 19x20x32 | 6560 | **6560** | 0 |
| 20x20x21 | 4643 | **4643** | 0 |
| 20x20x25 | 5442 | **5442** | 0 |
| 20x21x32 | 7184 | **7184** | 0 |
| 20x22x28 | 6636 | **6636** | 0 |
| 20x23x27 | 6729 | **6729** | 0 |
| 20x23x28 | 6866 | **6866** | 0 |
| 20x23x29 | 7174 | **7174** | 0 |
| 20x23x32 | 7782 | **7782** | 0 |
| 20x24x29 | 7370 | **7370** | 0 |
| 20x24x31 | 7830 | **7830** | 0 |
| 20x25x31 | 8342 | **8342** | 0 |
| 21x23x28 | 7354 | **7354** | 0 |
| 21x23x32 | 8282 | **8282** | 0 |
| 21x25x31 | 8876 | **8876** | 0 |
| 21x25x32 | 9066 | **9066** | 0 |
| 21x28x28 | 8848 | **8848** | 0 |
| 23x32x32 | 12214 | **12214** | 0 |
| 25x31x32 | 12966 | **12966** | 0 |
| 25x32x32 | 13206 | **13206** | 0 |
| 26x29x32 | 12714 | **12714** | 0 |
| 26x31x31 | 13112 | **13112** | 0 |
| 26x31x32 | 13295 | **13295** | 0 |
| 26x32x32 | 13510 | **13510** | 0 |
| 27x31x32 | 13851 | **13851** | 0 |
| 27x32x32 | 13999 | **13999** | 0 |
| 28x31x32 | 14123 | **14123** | 0 |
| 28x32x32 | 14271 | **14271** | 0 |

The full 186-certificate manifest is in
[`block_composition_records.tsv`](block_composition_records.tsv), and the two
unmaterialized formulas rejected by the pinned prior-art scan are in
[`block_composition_opportunities.tsv`](block_composition_opportunities.tsv).
The final 48-row promotion/rejection audit is in
[`block_composition_queue_closure_audit.tsv`](block_composition_queue_closure_audit.tsv).
These are exact GF(2) upper-bound certificates.  Calling one a world record
also requires a current prior-art/catalog comparison; exactness alone does not
establish novelty.

The complete two-wide extension additionally scans all 1,154 sorted targets
with one dimension 8--11 and the others up to 32.  Balanced-tie and ordered-
allocation closure bring its contribution to 31 strict apparent GF(2) records
and nine conservatively unclassified exact upper bounds;
the formulas, field-aware comparisons, hashes, and zero-win universal control
are in
[`BLOCK_COMPOSITION_SMALL_CROSS_AUDIT.md`](BLOCK_COMPOSITION_SMALL_CROSS_AUDIT.md).

## Leaf provenance

The `333`, `334`, `344`, and `444` leaves are existing FlipFleet exact seeds.
The remaining leaves were converted, without algebraic modification, from
field-F2 factor arrays in the July 12, 2026 `solven-eu/matmulcatalog` snapshot.
The newly imported small rectangular leaves are:

- `3x3x5-r36-alphatensor_F2-a36eef6.json` (density 317), converted to
  `matmul_3x3x5_rank36_gf2.txt`;
- `3x4x5-r47-alphatensor_F2-6ff64e1.json` (density 396), converted to
  `matmul_3x4x5_rank47_gf2.txt`; and
- `3x5x5-r58-alphatensor_F2-84728a0.json` (density 544), converted to
  `matmul_3x5x5_rank58_gf2.txt`.

The canonical 4/5 sources are:

- `4x4x5-r60-flips_mod2-e7a8ee8.json`, source recorded there as
  Kauers--Moosbauer 2023;
- `4x5x5-r76-alphatensor_F2-d3a75ba.json`;
- `5x5x5-r93-alphaevolve-9728dd0.json`; and
- the two retained rank-93 Kauers catalog variants.

The 21--32 extension adds the complete set of 20 sorted GF(2) leaf ranks over
block sizes 5--8.  Nineteen converted catalog leaves are checked in alongside
FlipFleet's stronger rank-248 `777` certificate.  Six catalog entries (`556`,
`557`, `588`, `668`, `688`, and `888`) are exact derived constructions; the
other thirteen are explicit catalog atoms.  All nineteen source JSON files
declare `F2` validity at matmulcatalog commit `0320f745`; `888` rank 329 is
GF(2)-specific, while the other converted leaves also declare characteristic-
zero validity.  The imported text files retain only their GF(2) reductions,
so the resulting wide certificates are deliberately field-specific.

The JSON catalog stores W in transposed output order.  The checked-in text
leaves transpose its `p x n` W coordinates into FlipFleet's row-major `n x p`
convention.  Every converted leaf is independently exact-gated by the
Tungsten loader before it can participate in a composition.

The cross-band extension fills the 27 shapes that were missing between those
two overlapping ranges.  Twenty-six are explicit catalog atoms and `4x6x8`
rank 140 is a catalog-derived exact scheme.  All declare `F2`; only `3x3x6`
rank 42 is GF(2)-specific.  `catalog_gf2_import.py` performs the dense import,
W-order correction, and an independent parity reconstruction before writing.

The complete two-wide audit retains the public constructive Hopcroft--Kerr
`2x3x3`, `2x3x4`, and `2x4x4` schemes and imports the other missing catalog
atoms needed to cover every sorted `<2,a,b>` with `2 <= a <= b <= 8`.
Eighteen newly imported files complete that family.  Their catalog fields,
source hashes, dimensions, factor bounds, duplicate checks, and independent
GF(2) reconstructions are pinned in
[`block_composition_2wide_leaf_audit.tsv`](block_composition_2wide_leaf_audit.tsv).

The production CLI pool is therefore complete for 84 sorted shapes: all 28
two-wide shapes and all 56 shapes over sizes 3--8.  This lets the same rank-47
outer construct both the balanced 12--32 region and the previously omitted
8--11 small-cross seam.  Every default leaf is exact-gated
at load time before it can affect scoring or composition.  Stable catalog
baselines precede optional exact
`flipfleet_4x4x5_best.txt` and `flipfleet_4x5x5_best.txt` durable campaign
checkpoints.  Equal-rank checkpoints therefore cannot regrade reproducible
compositions, while a genuine lower-rank checkpoint feeds later compositions
automatically.  A missing checkpoint leaves the catalog unchanged; a present
malformed checkpoint aborts rather than being ignored.

The rectangular campaigns initially reduced same-rank leaf density from
317/396/544 to 304/386/518. An exhaustive 1,857-recipe comparison found no
lower composed rank from those three variants; the d518 leaf made three exact
minima worse by one or two terms. A later live CPU campaign improved 335 again
to d287, which is now the search default. The reproducible composer and the
historical tie scan intentionally retain their catalog/d304 inputs until d287
receives its own exact-tie comparison.

## Full scans

`flipfleet_block_formula_scan.w` emits all 165 formula-best recipes for sorted
targets 12 through 20.  `flipfleet_block_variant_scan.w stabletable` evaluates
every formula-minimizing allocation/S3 tie and emits exact-best recipes.  Its
`tiecompare` mode repeats the historical scan with the d304/d386/d518 leaf
variants; d304 remains pinned there even though the live 335 search seed is
now d287.
`flipfleet_block_formula_scan_wide.w` independently exact-gates the complete
3--8 pool and emits all 1,771 sorted targets from 12 through 32.  The focused
`flipfleet_block_formula_scan_cross.w` emits the 1,242 targets that straddle
20/21.  Of those, 840 formulas beat the live FMM table and 760 remain strict
numerical improvements after S3-normalized comparison with matmulcatalog and
fmm-17-32.  The ten largest audited cross-band gains plus three representative
seam cases are materialized in the manifest.  The earlier 21--32 slice found
130 formula improvements; its ten largest refreshed gains are also saved.
The complete 840-row comparison is persisted in
[`block_composition_cross_audit.tsv`](block_composition_cross_audit.tsv), with
the exact source revisions and artifact digest in
[`block_composition_cross_audit_sources.tsv`](block_composition_cross_audit_sources.tsv).

The follow-up bounded pass removes the balanced-allocation restriction.  It
enumerates every ordered four-part allocation with entries in 3--8 and every
unique S3 source ordering.  This matters at the upper edge: concentrating the
slack in one outer block can avoid expensive supported leaf extents.  Eight
exact audited certificates are saved, including rank 13510 for 26x32x32
(balanced rank 13778) and rank 14271 for 28x32x32 (balanced rank 14570).
The reproducible exact tool is `flipfleet_block_unbalanced_compose.w`; the
complete saved comparison is
[`block_composition_unbalanced_audit.tsv`](block_composition_unbalanced_audit.tsv).

A second bounded pass tested leaf sizes outside the original 3--8 interval.
Forcing a size-9 block on every one of the 84 sorted targets from 26 through
32 never helped; the closest formula still lost by 33 multiplications.  The
complete 165-target 12--20 pass with a size-1 or size-2 block found two strict
formula improvements and one tie.  Exact materialization retained both wins:
rank 2041 replaces rank 2047 for 14x16x16, and rank 1251 for 12x12x14 beats
the strongest pinned GF(2) certificate, rank 1260.  The latter does not beat
the public rank-1234 rational construction and is therefore explicitly a
GF(2)-only apparent record.  The tied 14x14x16 recipe materialized at rank
1885 and was discarded because the existing cancellation-aware recipe has
rank 1881.  The recipes, field-aware comparisons, source hashes, and negative
size-9 result are pinned in
[`block_composition_smallblock_audit.tsv`](block_composition_smallblock_audit.tsv)
and
[`block_composition_smallblock_audit_sources.tsv`](block_composition_smallblock_audit_sources.tsv).

Recursive use of these outputs as leaves can mechanically reach dimensions
above 32, but the pinned Lille digest and the two scheme repositories used by
this audit do not provide a comparable complete frontier there.  No >32 result
is therefore labeled a record in this campaign.  Multilevel materialization is
best revisited with an explicit external baseline rather than manufacturing
large certificates whose novelty cannot be assessed.

For comparison, complete-pool scans with rank-23 `3x3`, seven support-distinct
rank-93 `5x5`, and rank-247 `7x7` outers produced no formula that beat the
rank-47 outer and the audited baseline simultaneously.  The expanded 5x5 pass
checks all 1,140 sorted targets from 15 through 32 against a pinned public
frontier.  It finds 11 formula wins over the rank-47 outer but no effective
win; the closest public/local miss is 30 terms at `15x20x30`.  Its inputs,
source revisions, diversity measurements, and replay command are in
[`BLOCK_COMPOSITION_OUTER5_AUDIT.md`](BLOCK_COMPOSITION_OUTER5_AUDIT.md).
Rank 47 remains the production outer.

### Balanced 8--11 closure

The production composer now loads the already exact-gated rank-7 `2x2x2` and
rank-11 `2x2x3` leaves, closing the only balanced four-way seam below the
original 3--8 leaf scan.  Every one of the 20 sorted targets with dimensions
8 through 11 was materialized and reconstructed exactly.  None improved the
audited frontier.  The `8x8x8` result is rank 329, reproducing the existing
public GF(2) construction; every other result loses even to the lower live
FMM main-table value.  The closest strict miss is `8x11x11`, exact rank 645
versus 641.  Post-embedding compaction removes up to six terms on the larger
targets (`11x11x11` falls from formula 925 to exact 919), but not enough to
change the conclusion.

Loading the two leaves is backward-stable: a fresh `13x13x13` composition is
byte-identical to the saved rank-1402 certificate (SHA-256
`f97d8d69de4881a13704901925ef16ec4aac2feb24fb94aed59fce2f391da1d4`).
The small closure therefore stays available for explicit compositions without
perturbing any 12--32 recipe.
The complete negative table is
[`block_composition_small8_11_audit.tsv`](block_composition_small8_11_audit.tsv).

The rank-247 conclusion is now reproducible rather than qualitative.
`flipfleet_block_outer7_scan.w` specializes balanced seven-part scoring to
the outer's six row/column support masks per term.  It uses the repository's
exact-gated 3--8 leaves, dimension-one flattening constructions, and the
verified explicit-F2 `<2,a,b>` ranks at pinned matmulcatalog revision
`0320f745`.  The latter are rank-only inputs to formula comparison; they are
never used to materialize a certificate without a checked-in leaf.

Three bounded target sets were tested:

- all then-current 93 saved exact rows in `block_composition_records.tsv` (35 seconds);
- all 287 sorted targets within the homogeneous bands 7--13, 14--20, 21--27,
  and 28--32 (100 seconds including the rank-47 comparison); and
- all 1,252 sorted targets from 7 through 32 having at least one dimension
  divisible by seven (32 seconds for the seven-way formula scan).

The 93-row exact-record comparison had zero wins and zero ties.  Its closest
loss was `13x13x14`, rank 1594 versus the saved rank 1501.  Across the 207
homogeneous-band rows with dimensions at least 12, there were no wins over the
rank-47 formula and only the associative ties `14^3 = 1729` and
`28^3 = 11609`; both already lose to stronger public constructions.  The
small-band cases where the seven-way formula beat the rank-47 formula all
lost to the pinned public frontier except `7^3 = 247`, which is the outer
itself and therefore not a new composition result.  The complete
multiple-of-seven surface had zero wins after taking the better of the
rank-47 formula and exact GF(2) column-block sums of the pinned `7x7xk`,
`k <= 16`, schemes.  Its only ties were the associative `7^3`, `14^3`, and
`28^3` rows; the closest strict losses were 18 products at `7x7x8` and
`7x7x9`.  This direct-sum guard matters: 23 `7x7xk` rows beat the rank-47
formula alone, but none beat the stronger exact GF(2) block sum.

Full materialization of representative 21x21x21, 24x24x24, and 27x27x27
recipes returned exact ranks 5681, 8471, and 11033, identical to their formula
ranks: no zero-term or parity cancellation was hiding behind the comparison.
Finally, up to eight coordinate-descent passes of single-unit block transfers
were tried on the closest rows.  Only `14x14x16` improved, from 2077 to 2072,
still 191 products behind the saved rank 1881.  This closes the useful local
unbalanced neighborhood without assigning any production width to the
rank-247 outer.

```sh
bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_block_outer7_scan.w \
  -o /tmp/outer7-scan
/tmp/outer7-scan selftest
/tmp/outer7-scan records > /tmp/outer7-records.tsv
/tmp/outer7-scan bands > /tmp/outer7-bands.tsv
/tmp/outer7-scan multiples > /tmp/outer7-multiples.tsv
/tmp/outer7-scan neighbor 14x14x16 8
```

### Alternate 7x7 block closure

The rank-247 discovery depends on weighting the complete Strassen outer orbit,
so the neighboring split families were checked explicitly rather than assumed
inferior. `flipfleet_outer_unbalanced7_formula_bench.w` scores all 46,656
combinations of `GL(2,2)^3` image and ordered two-block allocations summing to
seven. Using the audited GF(2) leaf table through size six, the best formulas
involving `6+1`, `5+2`, and `4+3` are 263, 256, and 248. The 1,008 recipes at
the competitive `5+2` threshold were then composed and fully reconstructed;
all stayed rank 256, with zero support truncations and zero parity reductions.

`flipfleet_outer_3x3_split_bench.w` is a structurally independent control: a
rank-23 3x3 outer, `3+2+2` allocations, and exact ranks 7/11/15/23 for the
2--3 leaves. Its 27 placements and bounded exact `GL(3,2)^3` descents bottom
out at rank 273. The rank-11 `2x2x3` leaf is converted from the catalog's
verified AlphaTensor F2 scheme and independently reconstructed by the importer.

```sh
bin/tungsten compile --release --lto \
  -o /tmp/ffbc-formula-scan \
  benchmarks/matmul/metaflip/flipfleet_block_formula_scan.w
/tmp/ffbc-formula-scan > /tmp/formula.tsv

bin/tungsten compile --release --lto \
  -o /tmp/ffbc-formula-scan-wide \
  benchmarks/matmul/metaflip/flipfleet_block_formula_scan_wide.w
/tmp/ffbc-formula-scan-wide > /tmp/formula-wide.tsv

bin/tungsten compile --release --lto \
  -o /tmp/ffbc-formula-scan-cross \
  benchmarks/matmul/metaflip/flipfleet_block_formula_scan_cross.w
/tmp/ffbc-formula-scan-cross > /tmp/formula-cross.tsv

bin/tungsten compile --release --lto \
  -o /tmp/ffbc-variant-scan \
  benchmarks/matmul/metaflip/flipfleet_block_variant_scan.w
/tmp/ffbc-variant-scan stabletable > /tmp/exact.tsv

bin/tungsten compile --release --native --lto \
  -o /tmp/ffbc-unbalanced \
  benchmarks/matmul/metaflip/flipfleet_block_unbalanced_compose.w
/tmp/ffbc-unbalanced 26x32x32 /tmp/r26x32x32.txt
```

## Tests

```sh
bin/tungsten compile --release --lto \
  -o /tmp/flipfleet-block-composer-test \
  benchmarks/matmul/metaflip/flipfleet_block_composer_test.w
/tmp/flipfleet-block-composer-test
```

The test covers wide decimal round-tripping, all six exact scheme
orientations, exact rank-7 Strassen input, generic 7x7 rank 248 composition,
13x13 rank 1402, 15x15 nominal-to-exact 2014-to-2008 cancellation, all ten
legacy 3--5 leaves, the all-S3 15x16x17 rank-2329 selection, the 12x18x18
formula-tie improvement from 2342 to 2340, equal-rank checkpoint stability,
rectangular certificate reload, and full exact reconstruction.
The allocation unit checks also pin the 146 ordered 3--8 splits of total 22.

Reload and independently exact-gate every certificate named by the manifest:

```sh
bin/tungsten compile --release --lto \
  -o /tmp/flipfleet-block-records-test \
  benchmarks/matmul/metaflip/flipfleet_block_records_test.w
/tmp/flipfleet-block-records-test
```

A separate Python implementation reconstructs the full GF(2) tensor without
importing or invoking the Tungsten verifier.  It also checks target and
filename dimensions, ranks, manifest hashes, allocations, and duplicate
targets:

```sh
python3 benchmarks/matmul/metaflip/verify_block_composition_records.py \
  -j 4 \
  --audit benchmarks/matmul/metaflip/block_composition_independent_audit.tsv
```

The checked-in [independent audit](block_composition_independent_audit.tsv)
records all 186 successful sparse-parity reconstructions.  Apple Python 3.9
and Homebrew Python produced the same byte-for-byte TSV (SHA-256
`796f5f3cf7b1cd65551cb19d6aca85d3c6028710e6776a6de879a0626b050b2c`),
covering 683,804 terms and 113,590,185 expanded `(U,V)` support pairs.
