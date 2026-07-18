# From local flips to wide matrix multiplication

*Draft status: 2026-07-17. All rank claims in this article are over GF(2)
unless stated otherwise.*

The latest phase of the matrix-multiplication project produced several very
different kinds of result, and keeping them separate is essential:

| result | strongest evidence | what it establishes |
|---|---|---|
| 3x3 rank is at least 20 | official proof certificate, independently replayed | a rigorous lower bound, due to Chengu Wang |
| `<3,2,4>` rank is exactly 20 | two constrained mode lemmas plus six quotient-rank pseudo-Boolean proofs, independently replayed | a new exact GF(2) tensor rank, closing the former 19--20 gap |
| 186 saved block compositions | two separate complete tensor reconstructions and pinned certificate hashes | exact GF(2) upper bounds; 176 are strict apparent GF(2) records, one is a co-record, and nine lack a pinned GF(2) comparator |
| 7x7 rank 247, current saved density 3094 | exhaustive weighted-outer orbit scan plus independent exact reconstructions; later density endpoints are full-gated | an exact GF(2) upper bound, improving the audited public rank-248 frontier |
| 4x4 remained at rank 47 after 988.5 billion fleet-reported moves | a completed diversified search campaign | a large search negative, **not** a lower bound |

The lower-bound result closes the bottom of an interval. The compositions
lower its top for many rectangular formats. FlipFleet searches for still
smaller upper bounds, but a failed search cannot raise a lower bound. Those
three statements can look similar on a dashboard; mathematically they are not.

## Rank, in one equation

The matrix-multiplication tensor for multiplying an `n x m` matrix by an
`m x p` matrix is

$$
M_{n,m,p} = \sum_{i=1}^{n}\sum_{j=1}^{m}\sum_{k=1}^{p}
e_{ij} \otimes e_{jk} \otimes e_{ik}.
$$

A rank-*R* bilinear algorithm writes that tensor as

$$
M_{n,m,p} = \sum_{t=1}^{R} U_t \otimes V_t \otimes W_t.
$$

Each summand corresponds to one scalar multiplication of a linear combination
of entries from the left matrix by a linear combination from the right matrix;
`W_t` says where to accumulate the product. Finding such a decomposition proves
an **upper** bound `rank(M) <= R`. Proving that no decomposition with fewer than
*R* terms can exist proves a **lower** bound. The latter is much harder.

GF(2) makes the representation pleasantly concrete. Each factor is a bit set,
addition is XOR, and two identical tensor products cancel. It also fixes the
scope: a construction whose correctness uses mod-2 cancellation is not thereby
an algorithm over the rationals, integers, or arbitrary fields.

## Replaying the new 3x3 lower bound

Chengu Wang's July 2026 revision of
[Automated Lower Bounds for Bilinear Complexity over Finite Fields](https://arxiv.org/abs/2603.07280)
raises the GF(2) lower bound for 3x3 matrix multiplication from 19 to 20. The
paper's framework classifies constraint subspaces under rank-preserving
symmetries, combines several lower-bound techniques by dynamic programming,
and emits a certificate checked by a smaller trusted verifier.

This project did not discover that theorem. It reproduced it. At upstream
revision `efd22070269157e65aaf8d61a21da253a4000c61`, the official Git-LFS
objects had SHA-256 hashes

```text
25595a883ce877eecd802139ff4e07646e154b2797ad6fe7f9ec737ab0c6135d  certificate
4e824eb13c235e69045881d173d8ababe622421055a238005afce413aabe3289  proof archive
```

and the official verifier reported

```text
UNCONSTRAINED TENSOR RANK LOWER BOUND: 20
OK
```

A clean non-LTO build took 6.55 seconds on the audit machine. The non-LTO
qualification is mundane but useful for reproduction: Apple-Clang LTO objects
hit an unrelated stack-probing limitation in `ld64.lld` on this host. The proof
artifacts themselves were unchanged. The exact command line, dependency chain,
and trust boundary are recorded in
[the lower-bound audit](../../benchmarks/matmul/metaflip/proof_orbit/README.md),
and the verifier is in Wang's
[public repository](https://github.com/wcgbg/tensor-rank-lower-bound).

The known GF(2) interval is therefore now

```text
20 <= rank(<3,3,3>) <= 23.
```

Our exploratory attempts did not prove 21. Search caps, unresolved proof-tree
frontiers, and timeouts are not refutations; 20 remains the rigorous endpoint.

## Closing `<3,2,4>` at rank 20

The smaller rectangular tensor `<3,2,4>` had a one-term gap:

```text
19 <= rank(<3,2,4>) <= 20.
```

Wang's certificate already made one strong reduction. If a hypothetical
rank-19 decomposition is viewed through its `3x2` factors, every one of those
factors must be rank one and all 19 must be distinct. We separately permuted
the tensor to `<2,4,3>` and audited the `2x4` factor mode. The published search
certificate assigns lower bound 18 to a one-dimensional constraint generated
by a rank-two `2x4` form. Complete finite-geometry expansion covers all 417,199
subspaces of `F_2^8` exactly once; 29,212 contain that base constraint and
produce 28,480 nontrivial capacity inequalities over 127 quotient points.

The residual capacity problem was split by the 576-element stabilizer into 46
disjoint cases. Current RoundingSat proved each case UNSAT, and VeriPB 3.0.2
replayed all 46 with an UNSAT conclusion, no assumption rule, and no warning or
unjustified diagnostic. The selected OPBs total 127,966,166 bytes and their
proofs total 411,824,811 bytes; the largest proof took 552 seconds to produce.
An independent Python audit imports no search code from Wang's implementation.

The resulting constrained lower bound is 19. Therefore a rank-19
`<3,2,4>` decomposition cannot contain a rank-two factor on this second axis:
that one occurrence plus a residual lower bound of 19 would require at least
20 terms. Combined with the earlier reduction, any remaining counterexample
must have 19 distinct rank-one `3x2` factors and 19 rank-one `2x4` factors.

That last residual is now closed by a quotient-rank lemma. Write
`A_t=x_t tensor y_t` and `B_t=p_t tensor z_t`, then reorder
`A_t tensor B_t` as `(x_t tensor z_t) tensor (y_t tensor p_t)`. The twelve
target slices are `Q tensor <I_2>`. The nineteen columns must be independent:
any dependence lets one absorb a selected `C` factor into the other terms and
delete a term, contradicting the already checked lower bound 19. Quotienting
the four-dimensional second factor by `<I_2>` therefore leaves a 36-by-19
column matrix of rank exactly `19-12=7`.

An exact pseudo-Boolean factorization `V=UL`, with the seven rows of `L` in
RREF, imposed this necessary rank cap on the six remaining fixed-B symmetry
cases. All six untouched instances are UNSAT. RoundingSat proof logs total
1,248,204,428 bytes; after unchecked deletion commands were removed, VeriPB
3.0.2 replayed all six in forced checked-deletion mode with no warning or
error. Planted matrices of ranks zero through seven are SAT in the encoding,
rank eight is UNSAT, and both natural and reversed column orders pass. The
known rank-20 construction gives the matching upper bound:

```text
rank_GF(2)(<3,2,4>) = 20.
```

The scripts, coverage construction, hashes, strict proof-acceptance rule, and
machine-readable claim status are in
[the `<3,2,4>` proof package](../../benchmarks/matmul/metaflip/proof_n324/README.md).

## Block composition: using a small algorithm as an outer skeleton

The most productive upper-bound work did not come from asking FlipFleet to walk
directly on a 20x23x32 tensor. It came from **block composition**: use a sparse
small algorithm to specify which blocks interact, then substitute the best
available rectangular algorithm into each of its terms.

The construction itself is established prior art. Generalized recombination
appears in the public
[AlphaTensor implementation](https://github.com/google-deepmind/alphatensor/blob/main/recombination/recombination.py),
which credits earlier work by Sedoglavic and by Drevet, Islam, and Schost. The
new work here is the systematic GF(2) campaign around a rank-47 4x4 outer
scheme: all support-distinct tensor-axis orientations, a complete leaf pool,
balanced allocation scans, wide exact materialization, and a dated prior-art
audit.

Suppose the target dimensions are divided into four block sizes:

```text
n = n0 + n1 + n2 + n3
m = m0 + m1 + m2 + m3
p = p0 + p1 + p2 + p3.
```

An outer rank-47 algorithm for `<4,4,4>` has 47 terms. In outer term `t`, let
`supp(U_t)`, `supp(V_t)`, and `supp(W_t)` identify the A, B, and output blocks
touched by its three factors. The effective first leaf dimension is

$$
n_t = \min\left(
  \max_{(i,j)\in\operatorname{supp}(U_t)} n_i,
  \max_{(i,k)\in\operatorname{supp}(W_t)} n_i
\right).
$$

The other two are analogous:

$$
m_t = \min\left(
  \max_{(i,j)\in\operatorname{supp}(U_t)} m_j,
  \max_{(j,k)\in\operatorname{supp}(V_t)} m_j
\right),
$$

$$
p_t = \min\left(
  \max_{(j,k)\in\operatorname{supp}(V_t)} p_k,
  \max_{(i,k)\in\operatorname{supp}(W_t)} p_k
\right).
$$

If `rho(a,b,c)` is the rank of the selected exact leaf for `<a,b,c>`, the
support-aware formula has rank at most

$$
\sum_{t=1}^{47} \rho(n_t,m_t,p_t).
$$

This is sharper than choosing one leaf from the largest block dimensions and
using it 47 times. A sparse outer term often sees only smaller blocks, and the
two factors sharing an axis need only their common effective extent. The
composer embeds the chosen leaf into every supported block, truncates padded
coordinates, drops zero products, and cancels duplicate triples in pairs.
Consequently the materialized exact rank can be smaller than the formula rank:
the 15x15x15 construction falls from formula rank 2014 to exact rank 2008, for
example.

Every one of these operations is constructive. There is no heuristic leap from
the score to an algorithm: after selecting a recipe, the composer writes all
three factors of every term and reconstructs the complete target tensor. A
separate sparse-parity implementation then reconstructs it again without using
the composer's verifier code.

## A one-term 7x7 win hidden inside the outer orbit

The same support-aware viewpoint produced a smaller but especially clean
result at 7x7. Start with Strassen's exact rank-7 decomposition of the 2x2
outer tensor. Split each of the three coordinate axes into blocks of sizes 4
and 3, and substitute the exact GF(2) ranks 47, 29, 38, and 23 required by an
outer term's effective rectangular support. The familiar untransformed recipe
has nominal rank 248.

The crucial observation is that the outer decomposition is not a single
presentation. `GL(2,2)` has six elements, so independent exact basis changes
on its three logical axes give only `6^3 = 216` outer images. Combining those
with the eight placements of the 4/3 blocks leaves just 1,728 recipes—small
enough to exhaust, materialize, and verify rather than sample.

Of the 1,728 recipes, 480 tie at nominal rank 248. Every tie was materialized
and fully reconstructed. Forty-eight produce exact rank **247**. In each of
those 48 cases, support truncation maps exactly one substituted leaf product
to a zero factor; the other 247 products are distinct and no duplicate-parity
cancellation occurs. The winning lexicographic recipe uses outer image codes
`(I,A,B)` and allocation mask 3. A follow-up audit materialized all 1,728
recipes, including nominally worse ones, and obtained the exact histogram
`247:48, 248:432, 250:480, 251:720, 253:48`. Thus no hidden rank 246 was being
masked by the formula scorer.

The retained certificate is
`matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt`, SHA-256
`cb18a91b28e9e8b452dde46f69d876638a5af733c1d419ea77185da1c2487ea3`.
It passed the Tungsten full tensor gate, a serialize/reparse/full-gate cycle,
an independent dense Python reconstruction, and a separate sparse-parity
reconstruction. The minimum-formula scan took 20.73 seconds and about 71 MB
peak RSS; the all-recipe closure took 85.10 seconds. The public catalogues
audited on 2026-07-14 showed rank 248 as their best discoverable GF(2) 7x7
entry. A fresh audit of
[FastMatrixMultiplication](https://github.com/dronperminov/FastMatrixMultiplication)
at commit `e0ec7db4cb7d7ca41abbb2c6e3bd8c7de75c7c64` (2026-07-05) reports rank
249 over `Q` and rank 250 over `ZT`/`Z`, with no binary-field 7x7 entry.
Thus 247 remains a candidate current GF(2) world record while external
catalogue and reviewer checks continue; the repository comparison is evidence,
not a proof that no unpublished scheme exists.

For review, `catalog_gf2_export.py` emits the same construction in dense public
JSON form with the output-transpose `W` convention. The checked-in
`matmul_7x7_rank247_d3554_outer_isotropy_gf2.json` has SHA-256
`3bab7abfd9f21b406572dc274e5fa656e69a512bcf9a6ecb258c24a4ef6a6c7b`.
The exporter reconstructs the tensor before serialization, reparses and
reconstructs the serialized factors, and the unmodified
FastMatrixMultiplication `Scheme.load(path, validate=True)` independently
accepts it as `n=[7,7,7]`, rank 247, `z2=True`.

This also suggests a useful search operator: **weighted outer-isotropy
tunneling**. An exact basis move on a small outer skeleton can change which
nonuniform leaves and truncated coordinates its terms encounter, creating
rank-neutral or rank-lowering endpoints that ordinary term-local flips never
visit. Because the outer orbit is tiny, it is practical to maintain several
distant exact rank-247 images as restart doors rather than following one
leader.

### A four-flip trace hides a better three-flip endpoint

A later NUMA-local CPU campaign did not lower rank 247, but it exposed a
useful example of sequence-aware density search. Starting from the exact
density-3096 frontier, one shard reported density 3095 after
735,308,184,180 child moves. The raw checkpoint passed both the pure-Tungsten
and independent host coefficient gates. Its term set differs from d3096 by
five removed and five added terms.

Reconstructing that delta showed that it is exactly four ordinary legal
flips. The following is a commuting reconstruction, not a claim that the AWS
walker performed the flips in this order. Tuples are `(U,V,W)` masks in
decimal, and every intermediate was independently reconstructed as the full
7x7 matrix-multiplication tensor.

1. Shared `W=269484032`:
   `(2203335041024,87961198665728,269484032)` and
   `(2164278273,35651650,269484032)` become
   `(2203335041024,87961234317378,269484032)` and
   `(2205465764865,35651650,269484032)`. Density `3096 -> 3103`.
2. Shared `V=87961234317378`:
   `(16777216,87961234317378,278921216)` and
   `(2203335041024,87961234317378,269484032)` become
   `(16777216,87961234317378,11534336)` and
   `(2203318263808,87961234317378,269484032)`. Density `3103 -> 3102`.
3. Shared `W=269484032`:
   `(2203318263808,87961234317378,269484032)` and
   `(2205465764865,35651650,269484032)` become
   `(2203318263808,87961198665728,269484032)` and
   `(2147501057,35651650,269484032)`. Density `3102 -> 3094`.
4. A disjoint shared-`U=2199023255552` flip replaces
   `(2199023255552,17592186044416,467197129033448)` and
   `(2199023255552,422212532174880,141836999987232)` with
   `(2199023255552,17592186044416,327559152309960)` and
   `(2199023255552,439804718219296,141836999987232)`. It worsens density
   `3094 -> 3095` and is therefore omitted from the retained endpoint.

The first three flips give an exact rank-247, density-3094 scheme with 244 of
247 terms shared with d3096. Its axis densities are `1020/1022/1052`, versus
`1022/1022/1052` for d3096. A deterministic pure-Tungsten replay used the
production flip formula and full-gated all four intermediates; its three-flip
term set exactly matches the retained d3094 certificate, and its four-flip
term set exactly matches the AWS d3095 checkpoint. The affected rank-three
component has eight ordinary-flip states, of which d3094 is density-minimal;
an exhaustive immediate-flip scan found no further density win or rank drop.

This is the small, concrete version of the Rubik's-cube intuition behind move
words. The profitable three-move word must first accept a seven-bit density
debt before its closing move pays back eight. Ranking only individual moves
would reject the entrance. Conversely, retaining every step of a useful word
without auditing its prefixes would have kept the unnecessary fourth move and
missed one more density bit.

The same delta also suggested a more general exact crossover.  If two exact
schemes represent the same tensor, their symmetric difference is a zero
tensor.  Join two delta terms when their Cartesian supports overlap on every
axis; disconnected graph components then touch disjoint coefficient cells,
so each component is independently a zero relation.  The d3096/d3095
difference splits into components of sizes six and four, and toggling the
six-term component yields d3094 directly.  The pure-Tungsten implementation
full-gates both parents, every relation, all children, and its winner, taking
about 1.5--1.7 ms on this 7x7 fixture.  Metaflip now applies this
support-component peel only to rare same-rank density intake and to its single
cross-parent differential worker, before the general nullspace fallback.
Thus the discovery became a reusable tunneling move without adding overhead
to ordinary CPU or GPU move loops.

The complete cloud follow-up was a useful negative control.  Six sharded CPU
phases executed 11.494 trillion supervised 7x7 moves, including 3.724 trillion
after d3094 became the seed frontier, without reaching rank 246 or density
below 3094.  A five-root A40 campaign added 1.196 trillion CUDA attempts and
93.616 billion compatible-partner checks, also with no lower endpoint and zero
exact rejects or ECC errors.  These totals measure the bounded campaigns; they
are evidence about the tested portfolio, not a lower-bound proof.

### Exact tunnels that replace the entire 247-term support

The rank-247 construction also exposed a larger escape mechanism that does
not appear on the normalized 4×4, 5×5, or 6×6 frontiers. For an exact tensor
automorphism `phi`, associate each term `t` with its complete coefficient
delta `t XOR phi(t)`. Any nullspace vector of these `n^6`-bit rows identifies
an arbitrary-cardinality subset that may be transformed atomically while the
represented tensor stays unchanged. Every candidate is parity-compacted and
then reconstructed as the complete matrix-multiplication tensor; endpoints
equal to the source or to the whole-scheme automorphism image are discarded.

All 189 elementary swaps and transvections at 7×7 yielded 155 exact basis
endpoints, 144 of them beyond the older two-to-four-term enumerator. A
depth-four projected closure then checked all 2,069 masks reached by its beam,
materialized 2,009 full-exact endpoints, and found 1,040 graph-unique nodes.
None lowered rank or improved density, but two rank-247/density-3098 nodes
share zero terms with the density leader: their term-set distance is 494, the
maximum possible for two 247-term sets. They are mutually distance 316.

Those two maximum-distance certificates are now durable restart doors, and a
retained-workspace pure-Tungsten finder generates further exact endpoints at
low cadence in the live coordinator. Across every rotated generator start it
found a genuine endpoint in 39 ms on average (p95 58 ms, maximum 97 ms). This
is not a new rank result, but it is concrete evidence that the apparent local
plateau contains algebraically exact tunnels into term-disjoint basins rather
than only shallow variants of one leader.

## What the scan found

The leaf library is complete for 84 sorted shapes: all 28 two-wide shapes
`<2,a,b>` through eight and all 56 shapes whose dimensions lie between 3 and
8. Each leaf is exact-gated before it can influence a score. The
rank-47 outer scan then covers all 1,771 sorted targets with dimensions from 12
through 32. A focused scan of the 1,242 shapes crossing the 20/21 boundary found
the following:

- 840 formula ranks below the corresponding live FMM-Lille value;
- 760 still below the strongest numerical value found after S3-normalized
  comparison with pinned revisions of matmulcatalog and `fmm-17-32`, as well as
  FastMatrixMultiplication, AlphaTensor, and Flips; and
- 146 selected recipes materialized as exact checked-in certificates in that
  original 12--32 campaign.

The 760 count is an audit of reproducible formulas, not a claim that 760
certificate files have already been materialized. The later balanced,
exact-cancellation, and unbalanced small-cross closure adds 40 certificates,
bringing the fully materialized set to 186. Of those, 176 are strict
**apparent GF(2) records**, one is a known GF(2) co-record, and nine exact
upper bounds have no pinned explicit or reducible GF(2) comparator. The word
“apparent” matters: a repository and catalogue search is strong evidence, not a
proof that an uncatalogued construction does not exist.

The completed two-wide pool closes a seam the original 12--32 scan did not
touch: all 1,154 sorted targets whose smallest dimension is 8--11 and whose
other dimensions are at most 32. Against conservative explicit or
integer-reducible GF(2) comparators, 129 formulas win, two tie, 382 lose, and
641 have no pinned comparator. Twenty-two strict wins were materialized, led
by 11x28x28 rank **4937** (gain 183) and 11x20x32 rank **4014** (gain 146).
The rank-25 `<2,3,5>` leaf also propagates directly to 8x11x20 rank **1119**
and 8x12x20 rank **1175**. Two additional exact upper bounds—11x16x31 rank
**3195** and 11x16x32 rank **3255**—beat every pinned numerical value but are
conservatively left unclassified. Repeating the entire scan with a universal
signed rank-49 outer produced zero wins, so these new formulas remain
explicitly GF(2)-specific.

Exact materialization then found information formula scoring misses. Exhausting
all 14,362 formula-minimizing balanced allocation/S3 ties shows that mapped-
zero pruning turns the nominal rank-3073 10x22x23 formula into exact rank
**3071**, beating the pinned GF(2) rank 3072, and strengthens six other strict
results. Seven more zero-pruned upper bounds beat every pinned numerical value
but remain unclassified for lack of a GF(2) comparator. No best tied recipe
uses duplicate-parity cancellation. Finally, an exhaustive ordered
2--8 allocation scan over all 1,154 targets found 38 formula improvements:
10x16x16 reaches exact rank **1558** (20 below its GF(2) baseline and two
below the pinned characteristic-zero value), while 10x16x17 reaches exact rank
**1694**, two below a universal integer/GF(2) construction. Exact-gating all
38 improved layouts found no further hidden comparator win.

Some representative exact results are:

| target | saved rank | strongest audited value | numerical gain |
|---|---:|---:|---:|
| 26x32x32 | **13510** | 13896 | 386 |
| 25x32x32 | **13206** | 13533 | 327 |
| 20x23x32 | **7782** | 8040 | 258 |
| 20x23x29 | **7174** | 7421 | 247 |
| 20x24x31 | **7830** | 8070 | 240 |
| 23x32x32 | **12214** | 12432 | 218 |
| 19x20x21 | **4495** | 4596 | 101 |
| 13x19x19 | **2822** | 2880 | 58 |
| 15x15x16 | **2074** | 2132 | 58 |
| 13x13x20 | **2052** | 2099 | 47 |
| 14x19x20 | **3130** | 3187 | 57 |
| 13x14x20 | **2203** | 2236 | 33 |
| 14x17x19 | **2703** | 2753 | 50 |
| 12x19x19 | **2563** | 2604 | 41 |
| 14x15x16 | **1975** | 2016 | 41 |
| 17x19x19 | **3598** | 3637 | 39 |

An intermediate queue replay added nine exact records between dimensions 12 and 20.
Their closest pinned competitors make this a useful guard against comparing
only with a headline table: rank 1868 for `<12,13,20>` beats a verified
integer rank-1871 scheme by three; ranks 2376, 2490, and 3284 for
`<14,16,18>`, `<15,16,18>`, and `<16,18,20>` beat verified integer schemes by
39, 33, and 16. A rank-2223 `<13,16,18>` composition was reconstructed exactly
but deliberately rejected from the manifest because `fmm-17-32` already
contains rank 2217. Exactness is the admission gate for an upper bound, not by
itself evidence of novelty.

The final exhaustive replay of the original queue promoted another 37 strict
GF(2) records. Thirty-five are below every audited same-shape value
numerically. The other two are intentionally field-qualified: rank 1850 for
`<12,15,17>` and rank 1890 for `<13,13,18>` beat the live GF(2) values by 10
and 3, while lower catalogue stubs at 1836 and 1871 explicitly support only
F3/Q/R/C. Only two queue formulas remain unmaterialized, because verified
integer schemes are already stronger: rank 2217 for `<13,16,18>` and rank
2736 for `<13,18,20>`. This closes the queue on comparator quality rather than
on an arbitrary certificate count. The machine-readable
[queue-closure audit](../../benchmarks/matmul/metaflip/block_composition_queue_closure_audit.tsv)
records every disposition and the three conservative gains corrected against
serendipitous integer formulas.

The saved 15x15x17 construction is exact rank 2262 and improves the audited
GF(2) frontier 2320 by 58. It is not an all-fields numerical record:
matmulcatalog has rank 2260 over F3/Q/R/C, built from a rank-40 `3x3x6` leaf
that is invalid over F2. The best audited F2-valid leaf has rank 42, exactly
accounting for the two-term field gap.

The largest new gain came from dropping the balanced-allocation restriction.
For 26x32x32, the outer row allocation `6 + 6 + 6 + 8` scores much better than
any permutation of `6 + 6 + 7 + 7`, while the other two axes use four blocks
of size 8. Ordered allocation and all six tensor-axis orientations give exact
rank 13510, improving the strongest pinned same-shape value by 386. The bounded
follow-up saved eight such certificates: six new target shapes and two strict
replacements for earlier balanced constructions. Their recipes, strongest
same-shape sources, gains, and hashes are in the
[ordered-allocation audit](../../benchmarks/matmul/metaflip/block_composition_unbalanced_audit.tsv).

The second exact rank-47 orbit is valuable search diversity but not a better
composition skeleton. Using the density-677 Flips scheme as the outer gave
zero wins, 371 ties, and 1,400 losses against the density-450 outer over all
1,771 balanced targets; its mean penalty was 61.2 multiplications. An
exhaustive ordered-allocation comparison on the eight audited upper-edge
targets likewise gave zero wins, three ties, and five losses. The exact ties
included 26x32x32 at rank 13510, but none justified another certificate. The
reproducible comparison is
[`flipfleet_block_outer_variant_scan.w`](../../benchmarks/matmul/metaflip/flipfleet_block_outer_variant_scan.w).

The complete two-wide small-cross control reaches the same conclusion for the
previously omitted seam: d677 has zero formula wins, 217 ties, and 937 losses
against d450 across all 1,154 targets, and zero wins after materializing the
selected recipes. Its full formula/exact tables and the exhaustive d450 tie
closure are documented in
[`BLOCK_COMPOSITION_OUTER47_SMALL_CROSS_AUDIT.md`](../../benchmarks/matmul/metaflip/BLOCK_COMPOSITION_OUTER47_SMALL_CROSS_AUDIT.md).

The lower seam is closed as well. Adding the already verified rank-7 `2x2x2`
and rank-11 `2x2x3` leaves lets the same composer materialize all 20 balanced
targets from dimensions 8 through 11. All are exact, but none is new:
`8x8x8` reproduces the public GF(2) rank 329, and the closest other result is
`8x11x11` rank 645 against the live rank 641. The added leaves leave the
saved 12--32 recipes byte-for-byte unchanged.
The finite comparison is recorded in the
[8--11 closure audit](../../benchmarks/matmul/metaflip/block_composition_small8_11_audit.tsv).

A bounded follow-up then allowed one block of size 1 or 2. It found exact rank
2041 for 14x16x16, six below the previous saved construction and 87 below the
best public numerical value. It also found rank 1251 for 12x12x14. That result
is a GF(2)-only apparent record: it improves the strongest pinned GF(2) rank
1260 by nine, while public rational ranks 1234 and 1240 remain numerically
lower. A companion scan forcing a size-9 block on all 84 sorted upper-frontier
targets found no improvement; the closest formula lost by 33. The field-aware
results and pinned source hashes are in the
[small-block audit](../../benchmarks/matmul/metaflip/block_composition_smallblock_audit.tsv).

For the 20x23x32 example, the allocations are

```text
n: 5 + 5 + 5 + 5
m: 6 + 6 + 6 + 5
p: 8 + 8 + 8 + 8.
```

Support-aware substitution into the 47 outer terms gives rank 7782, compared
with 8040 in the audited catalogues. That is an exact GF(2) upper bound once the
certificate reconstructs the tensor; calling it a world record should wait for
independent review and catalogue acceptance.

The implementation had to leave the fleet's convenient one-`i64` factor
representation behind. A factor for a 32x32 matrix needs 1,024 bits. The
pure-Tungsten composer stores factors in arrays of 30-bit limbs, performs
decimal conversion without boxed wide integers, and verifies by accumulating
chunked output masks. Each of the 186 manifest entries was reloaded and
exact-gated as a batch. A second verifier, implemented independently in Python,
reconstructed every coefficient of all 186 tensors by grouping each term's `U`
and `V` support and XORing its complete `W` mask. It checked 683,804 rank-one
terms and 113,590,185 grouped parity updates. Apple Python 3.9 and Homebrew
Python produced the same deterministic audit, SHA-256
`796f5f3cf7b1cd65551cb19d6aca85d3c6028710e6776a6de879a0626b050b2c`;
a rehashed one-bit mutation was rejected at the exact mismatching coordinate.
Its deterministic results are in the
[independent audit](../../benchmarks/matmul/metaflip/block_composition_independent_audit.tsv),
and its implementation is
[`verify_block_composition_records.py`](../../benchmarks/matmul/metaflip/verify_block_composition_records.py).
Recipes and SHA-256 hashes are in the
[certificate manifest](../../benchmarks/matmul/metaflip/block_composition_records.tsv);
the full method and reproduction commands are in
[the composition note](../../benchmarks/matmul/metaflip/BLOCK_COMPOSITION.md),
and the dated novelty assessment is in
[the apparent-record report](../../benchmarks/matmul/metaflip/BLOCK_COMPOSITION_RECORDS.md).

## Turning FlipFleet into a research instrument

Meanwhile, the search engine itself changed substantially. The public entry
point remains
[`flipfleet.w`](../../benchmarks/matmul/metaflip/flipfleet.w), but its campaign
path is now native Tungsten: coordinator, CPU walkers, exact escape banks,
adaptive scheduling, persistent-worker control, checkpoints, and TUI. Python
programs in the directory are research and conversion tools, not part of a
normal fleet run.

The important change is not a longer list of moves; it is preserving genuinely
different opportunities to use them.

- CPU islands keep sticky assignments to leader, frontier, rank+1, rank+2,
  symmetry, mixed-escape, and anchor doors. A rank drop migrates only a small
  part of the fleet instead of making every worker follow the leader.
- Exact best+1 and best+2 shoulders survive in bounded banks. A max-min archive
  keeps separated same-rank schemes instead of retaining only the densest or
  most recent one.
- The 4x4 frontier now begins with two provably different rank-47 GL/S3 orbits:
  the density-450 AlphaTensor representative and a density-677 scheme converted
  from Flips. Their factor-rank invariants differ, so the distinction is more
  than a random seed or term ordering.
- The adaptive GPU schedule combines continuous walking roles with a rotating
  pool of generic and algebraic escapes, projected-defect scouts, MITM and
  staged XOR surgery, archive novelty, and cooperative SIMD. GPU candidates are
  exact-gated again by the coordinator before admission.
- A symmetry-canonical basin identity, MAP-Elites niches, and delayed lineage
  credit let the scheduler reward an escape whose useful rank reduction appears
  only after a later CPU continuation.

There was also less glamorous hardening. CPU walkers now use a persistent
in-process worker pool rather than paying repeated thread/process setup costs.
Metal libraries are freshness-checked and cached; stable workers keep their
device, pipeline, queue, and buffers across a mailbox protocol. Tiny control
commands fell from roughly 122 ms with source compilation to 15--19 ms on the
persistent path. Thread startup, dispatch initialization, cancellation, child
process groups, bounded joins, and final exact persistence were stress-tested
because a world-record search that occasionally attributes a result to the
wrong worker is not a research instrument.

The implementation and evidence classification are documented in
[FlipFleet search experiments](../../benchmarks/matmul/metaflip/FLIPFLEET_SEARCH_EXPERIMENTS.md)
and the consolidated
[campaign findings](../../benchmarks/matmul/metaflip/FINDINGS.md).

## The 4x4 rank-46 campaign

The first long run of the hardened two-basin 4x4 profile completed after 9,002
seconds:

| metric | final value |
|---|---:|
| fleet-reported moves | 988,501,306,802 |
| average reported rate | 109.8 million moves/s |
| best | rank 47, density 450 |
| exact frontier archive | 2 schemes |
| retained rank+1 / rank+2 shoulders | 32 / 32 |
| GPU degraded epochs | 0 |
| exact-verification rejects | 0 |

The post-run logs also rule out a misleadingly simple diagnosis. The generic
split role alternated almost perfectly between the density-450 and density-677
parents, and the novelty role overwhelmingly used the second orbit. This was
not twelve copies following one leader. Six pool walks reported a *nominal*
rank 46 inside their heuristic state, but none passed full tensor
reconstruction, none was admitted by the coordinator, and none is a record.
Those near misses exposed an observability gap. The next-build instrumentation
now retains the raw seed and candidate, worker round, physical-slot launch
nonce, and deterministic first mismatching tensor coordinate whenever a
nominal-at-target candidate fails the exact gate. The coordinator freezes that
bundle atomically before reusing the slot; the rejected candidate is still
never admitted or rewarded.

It found no rank 46. That is useful operational evidence: the mixed CPU/GPU
portfolio can run for 2.5 hours without collapsing its two starting basins,
degrading its GPU path, leaking workers, or admitting a false candidate. It is
not evidence that rank 46 is impossible. The rigorous interval remains

```text
34 <= rank(<4,4,4>) <= 47.
```

The evidence also changed the 4x4 GPU allocation. The constraint/lower-bound
family had 6,731 launches without an exact candidate, whereas exact surgery
returned useful local identities and generic escape produced all six nominal
near misses. Future 1,536-lane pool epochs therefore keep a 128-lane constraint
floor and return the excess to surgery and generic escape. The full fleet,
generated 4x4 and raw-`i64` 7x7 workers, focused contract tests, and 4x4 exact
self-test all pass. The already-running follow-up campaign remains on its
original binary rather than being restarted merely to pick up diagnostics.

The first follow-up therefore changes the experiment rather than merely
changing its random seed. Twelve independent CPU doors use twice as much
wander time, density slack 8, eight algebraic cycles, a 128-entry near-rank
bank, and a 64-entry GPU novelty archive. The 4,096 adaptive GPU lanes remain
focused on 4x4, while two spare CPU lanes independently search for a rank-35
`<3,3,5>` leaf. A one-rank leaf improvement would be reusable in many of the
wide constructions above, so this is a portfolio bet rather than a distraction
from the square target. The live leaf campaign has not reached rank 35, but at
80.3 billion moves it had reduced the exact rank-36 seed density from 304 to
287 with zero rejects. That checked certificate is now the default 3x3x5 seed;
it is useful same-rank progress, not a new rank bound.

A sensitivity pass now quantifies that leverage instead of guessing it. It
first reproduces every stored formula, then counts the outer terms affected by
each possible one-rank leaf improvement. The best immediately supported target
is 4x4x5: rank 59 would affect 1,411 occurrences in 113 saved-or-audited
formulas, with 109 guaranteed improvements and three additional shadows. The
strategic maximum is 4x5x7: rank 103 would improve 200 audited formulas by
2,043 aggregate multiplications. FlipFleet now accepts `--tensor 4x5x7` as a
pure-Tungsten CPU profile. Its exact rank-104 catalog seed first improved from
density 1163 to 1160, then a whole-scheme GL tunnel and matched CPU walk reached
d1089 while two legacy controls stayed fixed. The new default and the d1160
legacy door have no terms in common. That is a density/basin improvement, not a
rank record. The full dependency counts are in the
[leaf-sensitivity audit](../../benchmarks/matmul/metaflip/BLOCK_COMPOSITION_LEAF_SENSITIVITY.md).

That GL result generalized. A dimension-generic pure-Tungsten tool now applies
and complete-gates rectangular whole-scheme isotropies, reparses its output,
and gates it again. Ten more record-rank profiles kept large density gains in
matched 25-million-move screens: 2x4x5 d246→d241, 3x4x6 d826→d488, 3x4x7
d576→d519, 4x4x6 d704→d690, 4x5x6 d975→d907, 4x5x7 d1160→d1089, 4x5x8
d1729→d1283, 4x6x7 d1860→d1406, 4x6x8 d1748→d1560, and 5x6x7
d2329→d1875. Each default alternates with a term-set-distant legacy door across
implicit CPU islands; explicit `--seed` runs remain single-source controls.

Completing all 28 two-wide leaves exposed a second primitive target with
unusually high downstream leverage. Improving `<2,5,6>` from rank 47 to 46
would save 82 guaranteed terms across ten stored certificates and 652 more
terms across 49 strict audited formulas, with three additional shadows crossing
to records. FlipFleet now has a first-class pure-Tungsten profile, a
capacity-92 Metal worker, and an exact 5-to-4 MITM lane for that gap. A
complete-gated orbit-door scan also found a second rank-47/d438 presentation
at term-set distance 94 from the catalog seed—the maximum possible, so the two
doors share no term. CPU islands alternate them, while half the Metal epochs
rotate the nonleader door instead of following one basin exclusively.

The highest-leverage 4x4x5 campaign received the same treatment. Global
isotropy moved the rank-60 d919 seed to a zero-overlap d655 presentation, and
six independently replayed shared-factor 2-for-2 flips reached d628. A matched
5.05-billion-move d919 run remained at d919. Across 43.75 billion bounded CPU
moves over the imported, legacy, GL, continuation, and mixed-bank arms, no rank
59 scheme appeared and every exact-reject counter remained zero. The d919/d628
symmetric difference has nullity one—only the full 60-for-60 relation—so a raw
two-parent differential has no proper subrelation to exploit.

A bounded short-word follow-up found a genuinely third door. Among 65,536
complete parent-pair eliminations, a two-generator d655 image had nullity three
against d628; a proper 57-for-57 relation produced rank 60/d679. Two matched
100-million-move continuations independently reached d662 while d628 controls
stayed fixed. The saved d662 scheme is distance 106 from d628 and 120 from
d919, and both of those union differences have nullity one. It therefore adds
basin diversity without pretending that another immediate parent splice is
available. A follow-up short-word sweep from d662 brought the totals to 40,960
exact images, 81,920 complete pair eliminations, and 1,285 proper splices; it
found neither a rank drop nor a density improvement over d628. No short-word
splice or continuation reached rank 59. This is useful negative guidance, not
a rank-60 lower bound.

Even the exhaustive statements currently available are local: the complete
ordinary-flip closures at rank at most 48 around the two saved rank-47 orbits
contain 3,210 and 2,139 states, respectively, and neither reaches 46. The long
campaign explores beyond those closures through shoulders and escape moves, but
it is still a search rather than a proof.

That distinction changes what “keep going” should mean. Another trillion
homogeneous flips in the same component is less attractive than a campaign that
spends compute on new exact rectangular leaves, materially different rank-47
parents, deeper local surgery, or a certificate-producing lower-bound engine.
The fleet is now designed to keep all of those doors open.

## Exact affine tunnels and the primitive gap

The rank-247 result turned the archive itself into an algebraic search space.
Over GF(2), the symmetric difference of any odd number of exact presentations
of the same tensor is exact. Complete Gray-code enumeration made that statement
finite for the current banks: all 4,096 endpoints for 5x5, all 256 for 6x6, and
all 2,048 for 7x7 were independently reconstructed coefficient by coefficient.
There were no gate failures. The larger odd combinations did not improve the
triple/five Pareto frontier, but they supplied four new rank-153 6x6 restart
doors and a rank-247/density-3098 7x7 door at term-set distance 40.

A broader decoder used 164 exact-zero archive generators over 12,227 possible
rank-one terms. Its 7x7 code has dimension 163. Strict single/pair descent and
4,194,240 tempered `k=16` codewords did not find rank 246, despite accepting
1,252 uphill steps and 49 cube escapes. They did find another exact
rank-247/density-3098 presentation 398 terms from its source and at least 56
terms from every one of the 165 generating inputs. Its SHA-256 is
`4a959727e6016a41f44e717270e08d33474154e842e1343c8d0b92380b8df795`, and an
independent Python reconstruction accepts every coefficient. It is retained as
a low-cadence restart door, not as evidence for rank 246.

The same algebra suggested a still more general move. If `Z=A XOR B` is an
archive zero relation, then `(P tensor Q tensor R)Z` is zero for arbitrary
linear factor maps. First and second finite differences localize those images:
on 7x7 their average sizes fell to about 108 and 51 terms. Planted Strassen
controls opened exact rank-10/rank-9 shoulders and closed both back to rank 7.
The real bounded audit covered 10,764 direct images and 42,120 derivatives on
7x7 with zero gate failures, but no rank drop, density win, or useful neutral
endpoint. The move is algebraically sound and empirically infertile on the
current leaders, so it remains offline.

The smallest primitive rectangle `<2,3,4>` over GF(2) is now resolved at rank
20. Before the quotient insight, its exact-C feasibility problem decomposed
into twelve identical 48x19 linear blocks. Across 300 archived necessary-B
models, the reduced extractor and former 576x228 system produced exactly the
same contradiction witnesses. Block-coset separation reduced matched solver
time from 4.30 to 2.71 seconds per model; residual-symmetry lifting expanded
7,831 audited cuts to 48,555 independently checked clauses, but did not close
the cases. Those experiments remain useful history: the quotient argument is
what turned the residual into six proof-sized rank-cap instances and closed
all of them.

The same lower-bound branch has now closed three still smaller primitive
cases. Complete finite-geometry certificates give
`R_GF(2)(<2,2,3>)=11`, `R_GF(2)(<2,2,4>)=14`, and
`R_GF(2)(<2,3,3>)=15`. The certificates cover all 11, 11, and 31 constrained
subspace orbits, respectively. We decoded their BTP archives, checked their
SHA-256 digests and orbit distributions independently, rebuilt Wang's
unchanged verifier at pinned commit `efd2207`, and replayed all three final
claims. Separate coefficient-by-coefficient reconstruction accepts the
matching rank-11, rank-14, and rank-15 upper schemes. These are equality
proofs, not negative search reports.

The next case moved as well. For `<2,2,5>`, the default `2^24`
forced-product cap skipped one child calculation. Raising it to `2^25`
proved that child at rank 15 and lifted the unconstrained root from 16 to 17.
Wang's unchanged verifier replayed the complete 11-orbit certificate and the
33,554,432-case forced-product proof, leaving the one-unit interval
`17 <= R_GF(2)(<2,2,5>) <= 18`. The analogous `<2,2,6>` run remains weaker
than its analytic lower bound, so its checked interval stays 19 through 21.

The next primitive rectangle now has a checked improvement as well:

```text
23 <= R_GF(2)(<2,3,5>) <= 25.
```

The lower endpoint combines Wang's complete 31-orbit constrained-subspace
certificate, a multiplicity-aware quotient-capacity CNF for decompositions
containing a rank-two first factor, and an independent 21-row incidence
contradiction for the all-rank-one case. CryptoMiniSat's proof was elaborated
to XLRUP and replayed by the formally verified CakeML checker. An independent
audit expands the certificate to all 2,825 subspaces, regenerates the CNF byte
for byte, and reconstructs the incidence count. This is a finite proof, not a
failed search.

The rank-25 upper endpoint was already public through AlphaTensor; FlipFleet
independently rediscovered two term-disjoint rank-25 presentations and then
found lower-density d170 and d160 doors. All five checked presentations pass
independent coefficient reconstruction. The live pure-Tungsten profile uses
four distinct CPU restart doors, a specialized 4,096-lane Metal worker, and an
exact 5→4 MITM lane while targeting rank 24. A two-hour `2x2x5` campaign and
the continuing `2x3x5` campaign are search evidence only; neither can raise
the proved endpoint without a complete certificate.

`<2,2,5>` and `<2,2,6>` are now first-class pure-Tungsten FlipFleet profiles rather
than proof-only entries. `--tensor 2x2x5` starts from the exact rank-18 upper
scheme and searches explicitly for rank 17; `--tensor 2x2x6` starts at rank
21 and targets 20. The first two-second, two-island `<2,2,5>` campaign made no
rank drop but reduced the exact upper presentation from density 95 to 88 over
68 million moves with zero rejected candidates. A 4,096-restart whole-scheme
GL scout from the original block presentation then produced a zero-overlap
d92 door. Once that door entered the sticky-island mix, 3.17 billion moves
reached d84. Two independent tensor reconstruction paths accept the d84
scheme (SHA-256 `bdce32ca89b5598e470fade86855904c283149ee4ec47d46fe6275afbd80225e`).
The final d84/d88 bank has zero shared terms; its 36 tensor columns have rank
35, so the sole parent-difference dependency is the complete 18-versus-18
relation and there is no smaller differential splice. Implicit campaigns
rotate both doors across sticky CPU islands.

A second construction acts independently on the rank-11 `<2,2,3>` and rank-7
Strassen leaves before embedding the `3+2` split. All 4,096 tested block-local
GL compositions were exact. The selected d92 member has 16 equal-factor pairs
and zero overlap with both main doors; unlike the d84/d88 pair, its union with
d84 has nullity two and exposes a proper 11-versus-11 splice to another exact
d84 presentation. An 800-million-move matched screen found no rank or density
win, so these are recorded as third and fourth diversity doors, not as a rank
result.

The repaired rectangular GPU engine supplied a fifth door from a place the
fleet-wide leader could not reach directly. Alternating GPU epochs onto the
block-d92 island returned through d89 and d86 to another exact d84 scheme. It
is only distance ten from the block parent but distance 28 from the original
d84 leader and shares no term with d88. The host reconstructed all 400 tensor
coefficients before adopting it. Expanding the deterministic block audit to
all five doors then exhausted 52,575 nullspace relations across 20,479
nonidentical unions. It produced 32,096 proper exact rank-18 hybrids and no
rank-17 projection. The operational gain is therefore basin connectivity,
not a new rank claim: nonleader GPU epochs can make useful discoveries that a
leader-only accelerator schedule systematically misses.

Keeping both complementary nullspace children closes those five doors to a
seven-scheme exact component, but a 1.12-billion-move matched continuation did
not make either child fertile. We therefore pushed beyond pairwise differences:
the joint-union affine solver allows a subset to take terms from three or more
parents at once. Across the five doors plus every single deterministic block
parent, then every pair and triple in a 32-parent maximin archive, it exhausted
11,942,176 affine masks. It independently reconstructed all 232,978 weight-18
occurrences and found no weight-17 subset. This is not a lower-bound proof over
all possible rank-one terms, but it sharply separates a closed, infertile
algebraic component from the next search frontier: low-weight decoding over a
much larger term union.

The adjacent `<2,2,6>` upper scheme received the analogous complete audit.
Independently conjugating all three Strassen leaves produced 4,096 exact
rank-21 parents. Every nonidentical parent/baseline union and every pair in a
32-parent diverse archive had exactly three independent relations, the three
choices of which complete leaf presentation to use. Enumerating all 31,654
relations yielded 27,132 proper exact rank-21 hybrids and no rank-20
projection. This closes that finite tunnel family without claiming a lower
bound. One r21/d108 parent is nevertheless operationally useful: it shares no
term with the baseline while preserving its density and equal-factor-pair
count. A matched 100-million-move arm remained exact r21/d108 but reached a
different equal-density best, whereas the baseline arm retained its start, so
the endpoint now rotates as the second `<2,2,6>` CPU door.

Multi-parent affine search later removed a subtle caveat in that conclusion.
It checked more than 52 million correlated masks formed from two retained
doors and up to three archive parents, finding only rank-21 exact subsets. Four
triple unions were too high-nullity for direct enumeration, but their geometry
made a stronger argument possible: every one of the 86,016 generated term
occurrences belongs to exactly one of three disjoint two-column Strassen
blocks. Restriction to each block needs at least seven terms, by the checked
rank of `<2,2,2>`, so the entire deterministic dictionary needs at least 21.
No amount of recombining those block-local terms can yield rank 20; a successful
move must introduce a term that couples output blocks.

The `<2,2,5>` residual was then attacked with complete local recognizers rather
than another sampled walk. Across 556 distinct unit-floor states, every one of
378,080 old-term triples was tested through 35,213,136 `GL(3,2)` bases and
32,463 completing matrices; none had tensor rank at most three. The companion
two-term and unit-to-unit audits likewise found no rank-17 closure or bridge.
This is a finite negative for the archived residual corpus, not a global lower
bound, but it rules out the most natural correlated repairs around all observed
unit-floor cells.

The first 4,096-lane Metal run also paid for its exact host gate: it exposed a
duplicate-compaction error that could leave one equal GF(2) term while removing
an unrelated term. No invalid candidate was published. The kernel now orders
the duplicate indices and performs two independent tail deletions, higher slot
first. Every generated square and rectangular worker was refreshed from that
template, and the corrected `2x2x5` engine completed 8.192 billion device moves
with zero internal rejection. The lesson is pleasantly concrete: accelerator
breadth is useful only when the independent coefficient gate is allowed to
disagree loudly with it.

The two larger primitive rectangles can now spend GPU time on more than
generic walks. Dimension-specialized Metal workers cover `<2,3,4>` and
`<2,4,5>`, and a new
rectangular 5-to-4 meet-in-the-middle lane passes an end-to-end planted
rank-21-to-20 recovery. Profiling that lane exposed a shared hash-clustering
bug: replacing a shift-only table hash with full-word rotations and avalanche
mixing reduced a representative 2x4x5 table build from 3.1--3.8 seconds to
85--130 milliseconds, while the planted dispatch fell from 126 to 6--7
milliseconds. Finite frontier sweeps examined 108,128,448 candidate pairs for
`<2,3,4>` and 94,291,520 for `<2,4,5>`, with no exact reject and no rank 19 or
32 result. For `<2,3,4>`, the new proof now explains why rank 19 was absent;
the sweep itself remains search coverage rather than part of that proof.

One further independent 4x4 control spent 219.024 billion CPU moves in one
hour from the second rank-47 orbit. It ended at exact rank 47/density 450 and
found no rank 46. Together with the longer mixed campaign, this retires one
more homogeneous basin without turning either run into an impossibility claim.

The latest move audit added two useful boundaries. A complete projective-line
matrix-pencil refactor evaluates
`min_D rank(D)+rank(X+D)+rank(Y+D)`: a planted five-term subtotal collapses to
one term, and six real 5x5 buckets have exact rank-neutral alternatives at
term-set distance up to ten. A matched 900-million-move continuation found no
rank or density advantage, so the operator remains an offline tunnel rather
than occupying a production lane. Three-anchor images of primitive 10--12-term
zero circuits likewise pass planted full-tensor controls, but 249 million real
fits over 4x4--6x6 produced only positive-rank shoulders and no useful neutral
edge.

Two wider finite-geometric identities sharpened that boundary. Affine-cube
polarization exchanges eight Segre cube corners for six direction-permutation
terms; its planted 8-to-6 and full-tensor controls pass, but exhaustive leader
closures on 4x4--6x6 never reached a neutral or `+2` shoulder. The Fano-plane
four-bucket operator did find three exact neutral endpoints—one on 5x5 and two
on 7x7—at term-set distances six and eight. It therefore adds genuine
one-step coverage beyond the span-4 and line-pencil operators, but bounded
flatten-gauge already reproduces the tiny planted circuit and matched
600-million-move continuations lost to their sources. Both remain offline;
novel algebra without objective reward is not enough to consume fleet lanes.

The control arm was more informative. Four ordinary exact splits followed by
five million moves found a new 5x5 rank-93/density-967 presentation, improving
the former d968 density leader. Both the Tungsten full gate and an independent
reconstruction accept its certificate, whose SHA-256 is
`c80233c763939feac7940d60e343c0cba1c88a5d55b6d635b6ff379b9193149f`.
That evidence is now represented by one bounded CPU racer arm: at most one
island opens a +4 shoulder at a lease boundary, while the rest of the fleet
keeps its stable basin-diverse profile. The TUI and GPU portfolio are unchanged.

## What comes next

The composition results have the clearest near-term publication path:

1. submit the independently reconstructed certificates, recipes, field
   restrictions, hashes, and audit for public catalogue review;
2. have an external reviewer reproduce the audit in a clean environment;
3. publish the complete 186-certificate manifest, preserving the distinction
   between 176 strict comparisons, one co-record, and nine uncovered GF(2)
   comparisons, plus the two explicit comparator-based queue rejections; and
4. improve heavily reused rectangular leaves, where one rank reduction can
   propagate through many larger targets at once.

For square rank search, the priority is diversity with accountability: track
which basin and escape produced each descendant, cap expensive surgery modes,
and promote a method only when it returns exact useful candidates. For lower
bounds, Wang's certificate machinery points toward stabilizer-orbit pruning;
blindly expanding the existing DFS budget is unlikely to move the 3x3 bound to
21 or make 4x4 tractable.

The broader lesson is that “matrix-multiplication progress” is not one kind of
event. A checked proof raises the floor. An exact decomposition lowers the
ceiling. A failed campaign maps the terrain between them. This phase produced
an independently replayed 3x3 lower bound, four closed primitive exact ranks,
one additional primitive lower-bound improvement,
over a hundred exact new ceilings pending external acceptance, and a much more
trustworthy way to search the remaining gap.

## 2026-07-15: durable rectangular doors and audited search boundaries

Rectangular campaigns now preserve a bounded side archive instead of forgetting
useful nonleader endpoints whenever the monotonic best does not change. Up to
four side doors live beside each best checkpoint. Live exact endpoints are
snapshotted before the monotonic island bests, written by temporary-file rename,
and admitted again only after full rectangular reconstruction. A retained door
must be distinct from the leader and the other doors and have rank from the
leader through leader plus two. Portfolio restarts rotate those doors without
moving lane zero away from the leader; malformed slots are isolated, and a
deliberate naive reset clears the entire side archive before publishing its new
schoolbook checkpoint.

The exact import and adoption gate was also reorganized from coefficient-major
rescanning to support-major accumulation. An audit accepted all 106 packaged
GF(2) seeds (57 square and 49 rectangular), rejected 424 controlled
corruptions, exercised the bit-63/last-word boundary, and agreed with an
independent sparse reconstruction. Three whole-manifest timing repetitions put
the new path at 15.3--15.5 milliseconds versus 0.85--0.87 seconds for the old
path, a 55--56x aggregate speedup while preserving first-mismatch semantics.
The scheme hot-path regression also completed 30,000 square and 30,000
rectangular flips plus 200 splits of each kind, with periodic exact and density
checks and successful rectangular adoption.

Two same-rank density leaders were promoted to packaged defaults:
`<3,4,4>` rank 38/density 280, SHA-256
`a08fc5382ac7da3e0fd09b3c1e389138feada0f91a6be5a0e06e75aa07668855`,
and `<4,5,6>` rank 90/density 906, SHA-256
`ba4a024752247b156b92bebe0a5bdfb644e44f3702323896bcb3a785625abdaa`.
The older exact presentations remain available as restart doors; these are
density improvements, not rank records. A separate target campaign then spent
about 19.3 billion aggregate moves across `<2,5,6>`, `<3,4,6>`, `<4,4,5>`,
and `<4,5,7>`. It had zero exact rejects and found neither a rank nor a density
gain. That is substantial search evidence around four useful leaves, not a
lower-bound argument.

A deliberately Rubik-like split-braid-merge macro tested whether a labelled
term could be split, braided through exact pair flips at rank `R+1`, and merged
through a different pair back at rank `R`. The bounded audit produced 209
full-gated endpoints beyond ordinary one-flip and span-4 coverage with zero gate
failures, but no rank win. Its only density wins came from the superseded 5x5
d983 source (to d980 in five-term windows and d979 in six-term windows); the
current 5x5 d967 leader and the rectangular leaders did not improve. The operator is
therefore retained as a deterministic offline replay and does not enter the
production scheduler.

The rectangular nonflip audit reached the same allocation decision by a
different route. Triangle shear, low-rank shear, span refactor, and flatten
gauge were tested on `<2,5,6>`, `<3,4,6>`, `<4,4,5>`, and `<4,5,7>`. The
families produced 280 changed exact endpoints with zero gate failures, but no
rank or density improvement; 416 million paired continuation moves likewise
found no rank drop. These are useful negative search results, not impossibility
proofs, so the four families remain offline rather than consuming rectangular
fleet lanes.

Finally, every generated generic and rectangular GPU worker now guards the
missing-equal-factor case before duplicate compaction: a failed partner scan is
mapped to the rank sentinel, so it cannot index slot `-1`. Package defaults now
enable adaptive GPU scheduling at 8,192 walkers and 40,000 steps per epoch,
the measured occupancy/dispatch balance on the reference M5 Max; both remain
CLI controls. Rectangular portfolios use 16 base rounds per allocation epoch
and let faster shapes take one-round straggler fills while the slowest base
quota completes. The combined change makes exact gates cheaper, keeps valuable
basins durable, and spends accelerator work more deliberately without
weakening certificate admission.

Archive selection now spends those four side slots on actual basin coverage.
It gathers every exact unique endpoint before truncation, reserves any present
`R`, `R+1`, and `R+2` bands, and fills the remainder by deterministic max-min
term-set distance from the leader and already selected doors. Fingerprints are
only a prefilter; equality is confirmed against complete term sets. In an
adversarial regression, four nearby rank-`R+1` endpoints were all distance 3,
while a prior distance-37 door survived input reversal and the three rank bands
remained represented. Selection cost 15 microseconds for 22 candidates and is
paid only when an island exits.

The rectangular 5-to-4 MITM process now overlaps the ordinary CPU and Metal
walkers from an immutable round-start snapshot. Joining and exact adoption
remain at the epoch barrier. On `<2,5,6>`, a matched 4,096-lane plus 16-by-384
MITM epoch fell from a 1.43-second sequential median to 0.99 seconds, a 30.8%
wall-time reduction, while retaining rank 47/density 438, checking 1,176,576
pairs, and reporting zero failures or rejects. Worker joins now have bounded
kill-and-reap behavior, and completed work is charged to per-shape and total
move counters even if a later segment gate fails. A 120-second four-shape
portfolio control completed 28 epochs without a rank or density change.

The next Rubik-style control also clarified the analogy's limit. Ordinary
tensor flips are conditional partial involutions, not globally available group
generators: after a trigger move, a syntactic inverse setup can cease to be
legal. Exhaustive `ABA`/`ABAB` commutators on the current 5x5 and 4x4x5 leaders
returned 284 and 444 exact endpoints respectively, but every endpoint was
already covered by a span-4 refactor. Longer setup-trigger-inverse ribbons
tested 202,368 and 842,112 trigger positions without a close. These macros stay
as offline exact regressions; deliberate sequences need a state-dependent
goal search, not a blind group commutator.

A third-generation macro made that state-dependent search explicit. After a
labelled split it chose a different intended merge pair and axis, then beam
searched connected exact flips using merge readiness, mismatch bits, target
pressure, and exact canonical visited-state deduplication. Depth-5-through-8
search found ten beyond-span-4 endpoints on each of 5x5 and 4x4x5, all accepted
by the full tensor gate; 2x5x6 produced none. Novelty still did not predict
fertility: the best 5x5 endpoint worsened d967 to d975 and lost all eight
matched two-million-move continuations, while the best 4x4x5 endpoint started
at d641 versus d628 and tied all eight continuations after both arms returned
to d628. The three-shape scan took about 0.56 seconds but peaked near 305 MB.
This operator also remains offline. The positive result is methodological:
targeted move words can cross the measured local envelope, but promotion must
depend on downstream objective value rather than path novelty alone.

Targeting a chosen core term reached the same boundary more directly. The
search recomputed the best merge partner and axis at every partial state, then
required the close to absorb the selected label and remove its original rank-one
triple. Novelty mode found six beyond-span-4 5x5 endpoints and four on 4x4x5,
with every target-removal and full-tensor gate passing. The best doors were
d975 versus d967 and d640 versus d628. The former lost all eight matched
two-million-move continuations; the latter tied all eight after ordinary moves
returned both arms to d628. Objective mode collapsed back to span-4-covered
rewrites, and 2x5x6 again produced no close. This fourth macro remains offline:
it proves a requested local change can be synthesized, but not that the changed
core opens a fertile basin.

The rectangular coordinator now avoids writing an internal child status file
more than five times per second; standalone cadence and terminal writes remain
unchanged. On matched 128-million-move 4x5x7 runs, wall median fell from 4.55
to 4.36 seconds (4.2%) and CPU time from 2.95 to 2.68 seconds (9.2%), largely
by reducing system time from 0.37 to 0.11 seconds. Parent telemetry now carries
CPU moves, GPU moves, and MITM attempts/pairs/time separately, per shape and in
total, while preserving the combined counter. Joined children cannot be counted
twice, failed-segment work remains visible, and naive reset clears every field.

A five-minute four-shape campaign then performed 30,507,167,270 CPU moves,
96,247,680,000 GPU moves, and 105,891,840 MITM pairs in 90 concurrent launches.
All four leaders and all 16 retained side doors independently verified; there
were zero failures or rejects. `<2,5,6>` stayed r47/d438, `<4,4,5>` r60/d628,
`<3,4,6>` r54/d488, and `<4,5,7>` r104/d1089.

The previously CPU-only `<2,2,6>` profile now has a generated 12-KB-threadgroup
Metal cal2zone lane and the rectangular 5-to-4 MITM lane. A 16-lane packaged
build/dispatch gate passed, and a 100-round control executed 32.768 billion GPU
moves in 45.32 seconds without a rank-20 or same-rank density result. One MITM
pass checked 1,176,576 complementary pairs in 0.52 seconds with no hit. The
shape is nevertheless added to the default rectangular mix as a distinct,
underexplored rank-21 frontier; these negative controls are far smaller than
the mature `<2,2,5>` campaign.

GPU coverage then expanded to three high-leverage shapes already present in
the default rectangular portfolio. `<3,4,6>` runs at roughly 301M moves/s with
CAP104 and 19,968 threadgroup bytes; `<3,4,7>` at roughly 252M/s with CAP116
and 22,272 bytes; and `<3,5,6>` at roughly 229M/s with CAP122 and 23,424 bytes.
Each figure is a packaged 8,192-by-40,000 replay, and each worker also passed a
cold 16-lane build/Metal smoke with complete host reconstruction and no reject.
The 30-bit `<3,5,6>` path was exercised by a real seed with bit 29 set, not a
reduced-mask fixture. These short runs left r54/d488, r64/d519, and r68/d634
unchanged; the result is broader useful GPU allocation, not a new bound.

The parent coordinator now distinguishes MITM failures from cal2zone failures.
A real injected MITM failure degrades parent health and remains in monotone
telemetry without backing off an otherwise healthy walking relay. A later clean
accelerator epoch may recover current health without erasing the historical
counter. A separate straggler-fill campaign committed exactly 25M moves across
its joined segments, confirming that live, base, fill, and terminal snapshots
are not replayed into the total.

The most literal useful descendant of the Rubik analogy is endpoint-first,
rather than word-first. A new offline rectangular k-XOR engine asks for a
specific local rank reduction—six terms to five or seven to six—enumerates a
bounded factor closure, hash-joins complementary halves on Metal, and admits
the result only after exhaustive local and full-tensor checks with unequal
factor widths. In a constructed control, splitting one term of exact
`<2,5,6>` r47 produced an exact r48 shoulder; each join found one candidate
and recovered an independently verified r47 certificate. This demonstrates a
real prescribed local change, not merely a random exact walk.

It did not earn production time. Across 128 unique 6-to-5 subsets on each of
the `<2,5,6>`, `<3,4,6>`, and `<4,4,5>` frontiers, 1.061 billion canonical
queries produced no fingerprint hit at all. Reusable GPU scratch kept peak RSS
near 45 MB and per-frontier wall time to 3.4--6.3 seconds, so the engine is
technically practical; the triple/triple 7-to-6 variant is slower and remains
host-table-bound. Both are retained as offline exact tools. The next Rubik-like
step is to discover a useful endpoint first and only then synthesize or replay
an ordinary-move path, rather than treating conditional flips as global group
generators.

A final relocation test exposed a compiler bug beneath the package resolver:
native `__DIR__` retained a relative source-directory spelling. A Metaflip
binary compiled from `bin/metaflip.w` could consequently fail to find its
runtime or development compiler when moved and launched elsewhere. Native
lowering now embeds the canonical absolute source directory for `__DIR__`,
without changing `__FILE__`. The end-to-end test compiled from a relative path,
moved the executable to `/tmp`, launched from an unrelated directory with all
Metaflip/Tungsten overrides removed and no `tungsten` on `PATH`, rebuilt its
worker and Metal library cold, and completed a verified 32-lane epoch with no
GPU degradation. Relocated package-layout and CPU self-tests passed as well.

## 2026-07-15: deliberate rectangular moves and the 2-wide frontier

The next rectangular pass made `<2,2,7>`, `<2,2,8>`, and `<2,2,9>` first-class
fronts.  The first two start from exact r25/d132 and r28/d160 GF(2)
certificates normalized from FastMatrixMultiplication revision
`e0ec7db4cb7d7ca41abbb2c6e3bd8c7de75c7c64`; because the source catalogue
does not name an unambiguous original discoverer, their attribution remains the
matmulcatalog contributors.  Exact factor splits by Erik Peterson (2026) add
r26/d135 and r27/d137 shoulders for `<2,2,7>`, and r29/d165 and r30/d169 for
`<2,2,8>`.  The public `<2,2,9>` corpus now contains Perminov's r32/d156
certificate, two same-rank coordinate permutations, and one exact `R+1` and
`R+2` split shoulder from each parent.  Alternate presentations and synthetic
shoulders are diversity seeds, not new algorithms or improved records.

This gave the default rectangular campaign 13 shapes:
`225,226,227,228,229,457,346,456,446,445,256,347,356`.  Twelve default CPU
workers cover twelve different shapes and rotate the omitted thirteenth each
epoch.  The hot query path batches the two widest unequal factor spaces, which
raised 229 throughput from 27.128 to 29.367 M moves/s (8.25%) without changing
5x5 throughput or memory growth.  Removing the coordinator's final-child sleep
reduced a matched three-shape 10M control from 0.47 to 0.42 seconds (10.6%).

GPU diversity was audited rather than inferred from nominal lane count.  The
former low-bit LCG mask exposed a strong cross-lane lattice and remapped zero
to one, doubling one factor's probability.  All 18 workers now apply unsigned
PCG RXS-M-XS and reject zero exactly.  A 300K accepted four-bit test used
19,754 retries, had frequency range 528, and covered every one of the 225
adjacent nonzero pairs; measured folded correlation contracted from about
+/-0.565 to +/-0.014.  Aggregate runtime was unchanged (26.97 versus 27.05
seconds).  The nominal split-door portfolio had also collapsed because target
and donor were affine in the same lane id: 8,192 227 lanes represented at most
about 75 doors.  Mixing donor-factor splits with systematic nonzero-mask
enumeration produced 5,201/5,441 distinct 227 doors in two epochs and
5,507/5,776 228 doors.  Thirty-two reconstructed examples passed exact gates,
and a source-consistency guard covered all 18 worker copies.

The expanded campaigns did not improve an objective.  `<2,2,5>` consumed
32.768B GPU moves at r18/d84.  `<2,2,7>` consumed at least 68.8B GPU plus
4.070B CPU moves at r25/d132; `<2,2,8>` consumed 36.0448B plus 3.950B at
r28/d160; and `<2,2,9>` consumed 32.768B plus 4.030B at r32/d156.  The CPU
runs rotated through exact `R`, `R+1`, and `R+2` shoulders.  None changed rank
or same-rank density.  These numbers describe searched neighborhoods; they do
not prove that a lower rank is impossible.

The prescribed-change experiment then screened five doors—227, 228, and the
base, cycle, and reverse 229 presentations—with both 6-to-5 and 7-to-6 k-XOR
joins.  A selector fix raised realized coverage from 163/256 to 256/256 subsets.
Each 6-to-5 run issued 2,397,077,504 canonical queries, and each 7-to-6 run
297,287,680, for 13.4718B queries overall.  The collision-complete probes made
6,970 and 24,840 fingerprint/local checks respectively, but no candidate
satisfied local tensor equality or reached a full certificate gate.  All ten
outputs were empty while planted rank-drop and collision controls passed.
Sparse table compaction cut the matched 227 6-to-5 wall time 24.5%, from
45.328 to 34.211 seconds.  K-XOR is therefore a functioning exact local
rewrite compiler, but still an offline tool rather than a productive lane.

The Rubik-style work reached a similar conclusion with explicit move words.
A literal `A C D B D C A` ribbon and a resolved `A C D B X Y Z` word preserve
the tensor through replay; the latter chooses its cleanup against the
post-trigger state.  On 5x5 r93, 16/16 selected endpoints passed the full gate,
11 were outside complete four-term-span coverage, and term-set distance reached
10.  A focused 229 r32 run returned 40/40 full-gated beyond-span-4 endpoints,
ten unique, also at distance at most 10.  Yet eight matched 20M-move trials per
arm favored neither escape: the 5x5 macro arm had zero wins versus two ordinary
wins and six ties, while 229 had zero versus one and seven ties.  Neither
dropped rank, and the macro arms retained fewer final basins.  The focused
implementation now peaks at 296 MB rather than 4.01 GB, but novelty without
continuation value does not justify production allocation.

One supporting profiler failure was fixed along the way: native
`tungsten symbolicate` used Ruby's `rstrip`, which is not a Tungsten string
method, on stdin backtraces.  Switching to `rtrim` restored both stdin and
direct-token symbolication.  The scientific bottom line is intentionally
narrow: this pass produced no new exact rank record, no density record, and no
lower-bound proof.  It produced better-provenanced restart strata, genuinely
more diverse and unbiased GPU lanes, faster rectangular execution, and two
audited ways to ask for a specific local transformation.

## A deliberate rank drop is a goal, not a random walk

The latest pass sharpened the Rubik's-cube analogy.  A cube algorithm names a
specific local effect and permits a temporary disturbance that its remaining
moves repair.  For tensor schemes, ordinary flips are conditional rather than
global generators, so copying a formal commutator is unreliable.  The useful
translation is instead: choose the endpoint condition first, then compile an
exact state-dependent word or replacement that realizes it.

One beam-search macro starts from an exact rank-`R+1` split and searches for two
labelled terms that become identical on all three factors.  Their cancellation
would end at rank at most `R-1`.  A planted rank-3-to-rank-2 example succeeds at
depth two and replays with every intermediate tensor exact.  Real searches on
227 r25, 229 r32, and 3x3 r23 checked 78, 81, and 88 windows through depth eight
without reaching the goal.  This is useful negative evidence: the goal is
well-defined and the compiler works, but the tested local envelopes contain no
such word.

There is now also a constructive answer when an endpoint has already been
found.  The endpoint compiler splits the intended `k-1` target term back to
`k`, uses bidirectional exact search to resolve the state-dependent middle
word, then performs the prescribed merge.  On the real 227 control it produced
the shortest two-step algorithm: flip
`(2,128,129),(2,512,516)` to
`(2,512,645),(2,640,129)`, then merge
`(4,2,768),(4,256,768)` along V to `(4,258,768)`.  The reverse word and every
prefix are exact, and grafting the replay into the packaged r26 shoulder
independently verifies the complete r25 tensor.  This endpoint is still only
an ordinary neighboring basin, but the experiment proves that a GPU-discovered
local replacement can be converted into a replayable Rubik-style algorithm.

The complementary endpoint-first method is rectangular k-XOR surgery.  It
enumerates replacement factors, hash-joins complementary halves on Metal,
checks the entire local tensor, then reconstructs and verifies the complete
matrix-multiplication certificate.  New `7->5`, `6->4`, and `5->3` objectives would turn
an artificial `R+1` shoulder directly into `R-1`.  Planted double-split
2x5x6 controls recovered the original exact r47 scheme for both objectives,
and adversarial hash-collision tests proved that a false early collision cannot
hide a later valid replacement.

The real screens found no record.  A 6-to-4 pass tested 18,825,216 canonical
pair queries on each of 227, 228, and 229; only 227 reached local checking, and
none reached the full gate.  A deeper 227 7-to-5 pass issued 2.397 billion
canonical triple queries in 14.978 seconds; all 70 fingerprint hits failed
before complete verification.  The still cheaper 5-to-3 pass issued 18.825
million canonical pair queries per 227/228/229 front and finished in
246/256/284 ms; it likewise produced no full candidate.  One earlier rank-25 endpoint was traced exactly
to a single ordinary U-pivot flip, so it is retained only as a replayable engine
control.  The direct engines therefore stay offline instead of consuming fleet
lanes merely because they are novel.

The surrounding search became both faster and more honest about diversity.
CPU basin roles now use a balanced round-robin ticket independent of restart
randomness, and side archives measure distance from all exact checked-in
frontiers rather than only the current leader.  Multiworker door windows also
advance by their side-worker width: a five-worker 229 run now exposes all eight
saved/built-in side roles in two epochs instead of only five.  The packaged 229 profile now
really includes r32, r33, and r34 doors, matching the public corpus.  On the
GPU, removing a variable remainder, skipping duplicate work for unmatched
proposals, and halving six signed-coordinate remainder operations preserved
byte-identical endpoints while improving the generated rectangular workers in
three measured stages.  A plausible CPU fallback that
created 25% more accepted transitions per second was rejected after equal-wall
continuations showed fewer useful updates; motion and fertility are not the
same objective.

A final 120-second 227/228/229 campaign performed 82.84 billion exact search
moves with no CPU, GPU, MITM, internal, or certificate-gate failure.  It ended
at r25/d132, r28/d160, and r32/d156 respectively.  There is no new record or
lower-bound proof in this pass.  Equal 4.096-billion-move GPU controls on the
wider 346, 347, and 356 fronts likewise left r54/d488, r64/d519, and r68/d634
unchanged with zero reject.  The durable result is a cleaner experimental
platform: balanced doors, verified rank-debt seeds, faster equivalent kernels,
and deliberate rank-drop mechanisms whose negative results can be interpreted
without confusing an implementation gap with mathematical impossibility.

## Closing two rank debts at once

The next experiment pushed the cube-algorithm analogy one step further.  A
useful tensor algorithm should name not just a different presentation but a
specific cleanup effect.  Two exact compilers now ask for a net two-rank drop
after a temporary disturbance, and both resolve every forward and reverse move
against the state in which it is actually applied.

The first adds a cancelling catalyst pair `C+C`, walks at fixed rank, and looks
for a four-term zero line: four terms sharing two factors, with the four
remaining factors XORing to zero.  Deleting that line turns the temporary
`R+2` shoulder into an `R-2` endpoint.  Constructed tests verify `3->1`,
`5->3`, `6->4`, and `7->5`, including a nontrivial three-flip close.  The real
screen was unambiguous but negative.  Depth-three searches across all 21
rectangular fronts and a deeper 227/228/229 census visited 68,702,987 exact
orbit states and found no such line.  This rules out only those bounded setup
families; it proves no tensor-rank lower bound.

The second compiler splits two different terms, follows a state-dependent
ordinary-flip word, and asks the endpoint to contain exactly two copies of each
of two distinct rank-one terms.  Cancelling both doublets changes `R+2` to
`R-2`.  A small exact fixture compiles the three-move word `36,40,35` and the
separately resolved undo `35,40,36`, with every prefix verified.  Across 3,072
real setup searches on 225, 227, 229, 256, 346, 445, 456, and 457, the engine
visited 11,721,598 states and admitted 46,936,086 legal edges without finding
a two-doublet endpoint.  A reusable BFS arena made this negative screen cheap:
about 7.7 seconds and 24.56 MB peak RSS, versus roughly 2.927 GB for the first
allocation-heavy prototype.

The complementary GPU survey asked for the same net effect without requiring
an ordinary-flip path.  Global `5->3`, `6->4`, and `7->5` k-XOR screens covered
48,128 bounded subsets, 1.156 billion table tuples, and 11.478 billion query
tuples.  Only six fingerprints reached local checking, all on 227 `6->4`, and
all failed exact equality.  No complete certificate was constructed.  The
evidence now agrees across three formulations—direct replacement, catalyst
cleanup, and paired annihilation—but agreement among bounded misses still is
not an impossibility proof.

Search engineering improved around those experiments.  Specialized GPU
workers for 446, 456, and the full-width `i64` 457 front make every shape in
the default 13-front portfolio GPU-capable; equal 2.048-billion-move searches
left r73/d690, r90/d906, and r104/d1089 unchanged.  Runtime Metal can compile
the generated MSL when the optional offline toolchain is absent.  On the CPU,
rectangular islands now retain their OS threads across epochs and reload their
state slots at each barrier, while the portfolio parses each child snapshot in
one pass.  The latter reduced a 50,000-parse control from 1,231 to 33 ms and
from 948.4 to 2.36 MB of allocation.

This work also closed a compiler bootstrap gap exposed by the compact macro
source. Ordinary `moves/10` division and numeric `/N` method arity are now
unambiguous, `!=` no longer becomes an identifier suffix, and the C bootstrap
implements the needed positional arguments, nested type hints, packed numeric
conversion, and hash deletion. The final stage mismatch was not cosmetic:
`StringBuffer#size` had been intercepted by a generic fast path and returned
zero, causing stage 1 to lose every element of `%w[...]` literals. Correcting
that dispatch and its build dependency restored byte-identical stage-1 and
stage-2 LLVM in a forced full rebuild.

This stage therefore adds no world record, density record, or lower-bound
certificate.  Its contribution is a sharper experimental instrument: all
default fronts can use the GPU, campaign coordination costs less, and a
requested `R -> R-2` change can be expressed in three independently exact ways
before compute is committed to it.

The natural next experiment is endpoint-first rather than a deeper blind
word search: archive low-weight error syndromes from near-miss k-XOR joins,
repair one or two spectator terms with a small CPU SAT or set-cover solve, and
send only exact repaired replacements to the rank-two word compiler. That
pipeline concentrates compute on the missing endpoint, then uses the
Rubik-style machinery for what it now demonstrably does well—compiling and
verifying the path.

## 2026-07-17: a rectangular density win and wider side archives

A 188-vCPU rectangular portfolio produced a new density leader for
`<2,2,7>` over GF(2): rank 25, density 128, improving the packaged density-132
catalog presentation at the same rank. The first exact portfolio barrier
reported d128 at 25.469 billion cumulative shape-specific CPU moves, so 25.469
billion is an upper bound on the discovery cost. The immediately preceding
barrier was d130 at 25.357 billion moves, bounding the final d130-to-d128
reporting interval by 112 million moves. The campaign later harvested the same
certificate after 92.683 billion moves on that shape and 1.509 trillion moves
across all thirteen fronts, with zero CPU, accelerator, MITM, or exact-gate
failure. Those later totals are continuation work, not the cost of finding the
scheme.

The d128 certificate passed independent full reconstruction of all 784 tensor
coefficients. Its SHA-256 is
`bf071351b20e442a1d3b532bff5bf534a1b22b00ac75f657c3da4c2265d5515c`.
It is at symmetric term-set distance 42 from d132 and has a different
structural signature. Metaflip therefore uses d128 as the hot default while
retaining d132 as a same-rank restart door beside the existing rank-26 and
rank-27 controlled-debt shoulders. This is a density record inside the search
corpus, not a tensor-rank improvement or lower-bound proof.

The same run exposed a diversity bottleneck on the wider fronts. With only
four persisted side doors, a 15-lane 4x6x7 child had six distinct starting
sources—leader, one checked-in nonleader, and four saved doors—so the other
lanes repeated those basins. A controlled cap-4/cap-8 replay began from
identical checkpoints and trajectories. In the first 7.5 million moves the
larger archive retained eight independently exact, structurally distinct
doors; after twelve additional 30-million-move continuations it still held all
eight, including several presentations at support distance 246 from the
leader. The matched final tranche took 599 ms with four slots and 606 ms with
eight. A second 4x6x6 control filled all eight slots in 28 million moves and
was slightly faster (422 versus 429 ms); 3x4x6 generated only four eligible
doors, so unused capacity remained empty rather than admitting weak or
inexact states. Rectangular checkpoints now persist up to eight exact side
doors, raising the full 4x6x7 child from six to ten distinct initial sources
without forcing every shape to manufacture eight.
