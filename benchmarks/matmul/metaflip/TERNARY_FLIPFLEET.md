# Ternary FlipFleet

`flipfleet_ternary.w` is a separate, pure-Tungsten CPU/GPU fleet for exact integer
matrix-multiplication decompositions whose factor coefficients lie in
`{-1,0,1}`. It does not alter the GF(2) worker, coordinator, GPU lanes, policy,
or TUI. Its own strict-ternary Metal breadth engine is enabled by default;
`--no-gpu` selects a CPU-only run.

The immediate targets are the one-rank ternary gaps at 4x4 and 7x7: the public
strict-ternary records used here have ranks 49 and 250, while schemes over a
larger integer/rational coefficient alphabet are known at ranks 48 and 249.
The 5x5/r93 and 6x6/r153 imports are controls and additional signed basins.

## Representation and exactness

Each factor uses two disjoint bitmasks `(positive, negative)`. A bit in the
first mask is `+1`, a bit in the second is `-1`, and a bit in neither is zero.
A term therefore occupies six `i64` words. Even 7x7 uses only 49 bits per mask.

Terms have a unique sign gauge: the first nonzero entries of U and V are made
positive and W absorbs the two compensating signs. Every input and every
durable `--best` is checked by a pure-Tungsten verifier that sums integer
coefficients over all `n^6` tensor cells. This is an integer/Q gate, not a
modulo-two gate.

The public text format is:

```text
T n rank
U+ U- V+ V- W+ W-
...
```

All masks are nonnegative decimal integers. `fft_load_seed` requires exactly
six masks per term, rejects overlapping/out-of-range sign masks, applies the
gauge, and runs the exhaustive integer gate before search begins.

## Checked-in catalogue seeds and provenance

`import_ternary_catalog.py` is an independent source-format verifier. It parses
the upstream `.exp` or JSON representation directly, rejects every coefficient
outside `{-1,0,1}`, expands the complete integer tensor, transposes the
upstream dual `c[j,i]` convention into FlipFleet's row-major `C[i,j]`, writes
six masks, reparses them, and expands the serialization again. It shares no
code with the Tungsten gate.

The complete commit, Git blob, source SHA-256, and generated-certificate
SHA-256 audit is in `ternary_catalogue_sources.tsv`. The imported records are:

| tensor | rank | upstream source | pinned commit |
|---|---:|---|---|
| 4x4 | 49 | `dronperminov/FastMatrixMultiplication`, `schemes/results/ZT/4x4x4_m49_ZT.json` | `e0ec7db4cb7d7ca41abbb2c6e3bd8c7de75c7c64` |
| 5x5 | 93 | `mkauers/matrix-multiplication`, `structured/555.exp` | `12c26b29a5458e173813911fb4f2c2865fba841e` |
| 6x6 | 153 | `mkauers/matrix-multiplication`, `structured/666.exp` | same |
| 6x6 | 153 | `mkauers/matrix-multiplication`, `structured/666r153.exp` | same |
| 7x7 | 250 | `dronperminov/FastMatrixMultiplication`, `schemes/results/ZT/7x7x7_m250_ZT.json` | `e0ec7db4cb7d7ca41abbb2c6e3bd8c7de75c7c64` |

The two 6x6 sources are genuinely different: after sign-gauge
canonicalization they share only one rank-one term.

Replay the full pinned source-to-certificate audit when both checkouts are
available:

```sh
python3 benchmarks/matmul/metaflip/import_ternary_catalog.py \
  --verify-manifest benchmarks/matmul/metaflip/ternary_catalogue_sources.tsv \
  --checkout /tmp/matrix-multiplication \
  --checkout /tmp/FastMatrixMultiplication-current
```

## Exact move set

The rank-preserving move is a signed 2x2 basis change. For terms sharing U,

```text
u tensor v tensor w + u tensor v' tensor w'
 = u tensor (v+s v') tensor w
 + u tensor v' tensor (w'-s w),       s in {-1,+1}.
```

The other axes are permutations. A move is rejected if an addition would make
a coefficient `+2` or `-2`, or if an output term has a zero factor.

The rank-changing moves are exact split/combine inverses. The useful split
writes a target factor as `donor + (target-donor)`, making one child share the
donor factor with an existing term. A support-partition split is the fallback.
Combine merges terms sharing two projective factors, including an opposite W
sign. A new donor receives 512 flip attempts before its obvious inverse
combine is enabled. Islands periodically restore their local best after
bounded rank debt.

`flipfleet_ternary_gl3_tunnel.w` adds a genuinely three-term endpoint move.
For three terms sharing a projective factor it writes the remaining subtotal
as `A B` and applies `A' = A M`, `B' = M^-1 B`, where `M` is a unimodular
3x3 integer matrix. Five representatives cover the genuinely three-way
ternary matrix/inverse orbits; source order and all eight input sign gauges
cover their remaining images. Each three-vector sum is formed atomically, so
the endpoint may be ternary even when a two-summand partial sum is `+2` or
`-2`. The fleet samples this move once per 65,536 ordinary moves, with one in
four samples allowed to enter a denser wander door. This cadence keeps the
linear shared-factor probe off the hot path.

The regression contains a three-term subtotal with no legal signed pair flip
on any ordered pair, axis, or sign: its pair-flip component is a singleton.
A nonidentity GL3 endpoint is nevertheless ternary and coefficient-by-
coefficient equal to the source subtotal. Cancellation telemetry alone is not
treated as a connectivity proof; the exhaustive pair probe is what establishes
the planted tunnel.

`flipfleet_ternary_index_shear.w` adds a global isotropy normalization. For
one physical matrix index, it applies the elementary unimodular basis change
`P = I + s E_ab` to one incident factor and `P^-T` to the other. Thus A rows
are paired with C rows, A columns with B rows, and B columns with C columns.
The contracted diagonal pairing—and therefore the entire multiplication
tensor—is unchanged. Every affected coefficient of every term is preflighted
before commit, and an endpoint is rejected if any factor would leave strict
`{-1,0,1}` or become zero. Every accepted shear and every final certificate
therefore remains strict ternary; independent integer reconstruction confirms
the complete `n^6` tensor after the Tungsten gate.

This is an exact global tensor isotropy/normalization, not a new local tensor
identity and not evidence that two decompositions lie in different components
of the unrestricted exact-move graph. It is valuable because it changes the
presentation seen by local pair moves. CPU seed admission performs a
deterministic steepest density descent over all `6*n*(n-1)` signed directed
shears while retaining the raw seed for GPU diversity. The same deterministic
closure runs only once per 8,388,608 ordinary CPU moves. Production never
publishes arbitrary isotropy-orbit novelty: `flipfleet_ternary_seed_variants.w`
may add only the shallowest legal positive shear, with density debt at most
eight, as one non-recursive GPU seed per normalized fingerprint. It is
exhaustively promoted but cannot replace the objective. Every GPU return is
integer-gated and deterministically re-normalized before archive/publication.

`flipfleet_ternary_index_word2.w` crosses strict-alphabet barriers left by the
elementary implementation. It evaluates a length-two word `P = S2 S1` and
the paired `P^-T` action atomically: an intermediate factor may contain
`+2` or `-2`, but every final factor must return to `{-1,0,1}`. The inverse
word is evaluated in reverse order, and both endpoints receive complete
integer reconstruction in the regression. These are not merely faster
versions of two accepted shears. On the current leaders the first generator
is illegal in the forward direction and the first inverse generator is
illegal at the endpoint, so the direct word crosses a bidirectional barrier
in the bounded strict-shear graph.

Exhausting every signed directed length-two word found 16 such changed
endpoints at 4x4/r49-d432, seven at 5x5/r93-d967, and 38 at
6x6/r153-d1931. All are bidirectionally blocked and uphill: there were no
neutral or descending endpoints. The shallowest density debts are +72, +24,
and +69, respectively. Twelve matched five-million-move continuations per
tensor (360 million aggregate moves across both arms) found no rank or density
improvement in either tunnel or control arm; all 36 objective comparisons
tied. The live tunnel and control presentations remained different in 35 of
36 trials, with accepted-move totals 5,309,961/5,318,904,
3,040,704/3,057,428, and 2,603,144/2,613,710. Thus the move has
positive, non-elementary basin-diversity evidence but no objective reward yet.
Production admits only the shallowest endpoint within density debt 96 to CPU
island zero at startup for 4x4--6x6, retaining the original leader as that
island's durable objective. No other CPU island, GPU lane, or hot-loop cadence
uses the move.

`flipfleet_ternary_index_word3.w` extends the same strict-barrier idea to
three elementary physical-index shears evaluated as one atomic word. Both
intermediate presentations may contain coefficients outside
`{-1,0,1}`, while the committed endpoint and exact inverse must be strict.
The audit removes adjacent inverse pairs, canonicalizes commuting generators,
rejects signed-coordinate relabelings, and quotients duplicate group elements
by their complete small-integer matrices. Hash collisions are resolved by
full matrix comparison; the final representative is reconstructed over the
entire integer tensor.

The exhaustive reduced-word audit did not improve the length-two frontier.
At 4x4 it screened 6,528 reduced words (5,992 distinct transforms) and found
86 bidirectional atomic endpoints, 62 new versus length two, with minimum
density debt +72. At 5x5 it screened 26,880 words (24,840 transforms) and
found 218 atomic endpoints, 105 new, with minimum debt +24. At 6x6 it
screened 82,400 words (76,260 transforms) and found 880 atomic endpoints,
634 new, with minimum debt +76. Every atomic endpoint was uphill: there were
no neutral or descending transformations. Thus 4x4 and 5x5 merely tie the
length-two debts, while 6x6 is seven density units worse.

A matched continuation compared the shallowest new word-three endpoint, the
admitted word-two endpoint, and the untouched leader for twelve five-million-
move trials at each tensor (540 million aggregate moves). Every one of the
108 arm objectives tied: no arm found a rank drop or density gain. Word two
and word three retained distinct live presentations in 34 of 36 trials, so
the extra words do reach new basins, but they showed no measurable objective
value. Length three is therefore retained as executable negative evidence and
is not admitted to any production CPU island or GPU pool.

A direct shared-factor GL(4) extension was audited first and deliberately not
added. The maximum projective-factor bucket sizes in the pinned 4x4, 5x5,
6x6, and 7x7 best seeds are respectively 1, 3, 2, and 3, so a four-term lane
would be a guaranteed miss at the objective rank. The pure-Tungsten audit
keeps that negative executable.

`flipfleet_ternary_span_refactor.w` audits a broader local move without a
shared-factor precondition. For a selected three- or four-term subtotal it
enumerates every strict ambient factor made by a coefficient tuple in
`{-1,0,1}^k`, projectively canonicalizes the factor catalogues, and takes all
signed rank-one products. Dual modular tensor evaluations select hash
buckets, but every match is checked over the complete ambient integer
subtotal; chained buckets retain every collision. The resulting bounded
catalogue search is exact and complete for its stated signed generator span.
It supports 3-to-2, fully changed 3-to-3, 4-to-3, and a goal-directed
three-term replacement containing the opposite of an external live term. The
last form cancels globally and can turn a neutral local identity into a
rank-minus-two splice.

The regression recovers all four planted families, including a four-term to
two-term external-cancellation fixture, and closes a split Strassen rank-eight
shoulder back to an exact rank-seven full tensor. Real-frontier evidence is
negative. A 512-window run on each of the pinned 4x4/r49-d432, 5x5/r93-d967,
both 6x6/r153-d1931 basins, and the two 7x7/r250 leaders exhaustively searched
3,072 three-term catalogues for 3-to-2, the first 16 per seed (96 total) for a
disjoint 3-to-3 tunnel and representable external cancellation, and the
smallest four-term catalogue per seed for 4-to-3. The six four-term
joins examined 156,426,570 candidate pairs. There were no replacements of any
of these kinds; none of the 96 collision windows even represented an opposite
external term. This is a finite negative, not a proof about all windows or
larger coefficient spans. With only planted positives, the move remains an
offline audit and consumes no production CPU/GPU cadence.

`flipfleet_ternary_sign_isotropy.w` audits the diagonal signed gauge orbit
that disappears completely over GF(2). Choose signs `d_i`, `e_j`, and `f_k`
for the three physical matrix indices and multiply the A, B, and C factor
coordinates by `d_i e_j`, `e_j f_k`, and `d_i f_k`, respectively. Every
target tensor coefficient receives `d_i^2 e_j^2 f_k^2 = 1`; rank, support,
density, and strict ternarity are invariant. The pure-Tungsten regression
checks the complete integer tensor on Strassen, exercises 18 actions on
Laderman, proves the mask action is involutive after term-gauge
canonicalization, and verifies that every GF(2) support projection is
bit-for-bit unchanged.

This symmetry does diversify the deterministic implementation: canonical
term gauges change which signed branch a fixed RNG bit selects, so matched
live walks were not generally inverse-conjugate and their accepted-move
telemetry differed. It does not enlarge the mathematical move graph, however;
diagonal signs conjugate every strict pair flip, split, and combine to another
legal move of the same rank and density. A bounded matched continuation made
this distinction concrete. For each of the 4x4/r49-d432, 5x5/r93-d967, and
6x6/r153-d1931 leaders, twelve control/sign pairs ran one million moves per
arm (72 million aggregate moves). Neither arm found a rank drop or density
improvement; all 36 comparisons tied. The signed/control accepted-move totals
were 1,062,833/1,057,867, 611,119/599,553, and 524,338/525,775, respectively.
This is useful as an executable negative boundary: sign-only conjugation is
at most RNG-equivalent diversity, not a tunnel out of an infertile component.
It therefore remains offline and consumes no production CPU or GPU lane.

## Fleet CLI

Build and run from anywhere inside the repository:

```sh
bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary.w \
  -o flipfleet-ternary

./flipfleet-ternary --tensor 7x7 --secs 3600
./flipfleet-ternary --tensor 4x4 --moves 500m -J 12
./flipfleet-ternary --tensor 6x6 --seed my_signed_seed.txt \
  --seed another_basin.txt --secs 600 --best six_best.txt --status six_status.txt
```

Supported campaign options are `--tensor 4x4` through `7x7`, repeatable
`--seed`, `--secs`, aggregate `--moves` with `k/m/b` suffixes, `-J`, `--best`,
`--status`, `--archive-prefix`, `--no-gpu`, `--gpu-lanes`, `--gpu-steps`, and
`--gpu-rounds`. With neither time nor move bound the default is one hour. `-J`
defaults to `System.cpu_count - 2`, with a floor of one, leaving room for the
coordinator and the rest of the machine.

Each island has private state and RNG. Publication is the only shared critical
section: a rank or density improvement is exhaustively gated, written through
a temporary file, and atomically renamed over `--best`. Changed equal-rank
returns are also integer-gated and retained in a globally deduplicated archive
of at most sixteen `--archive-prefix` files, because a denser presentation can
still be a valuable restart door. The final executable reparses and gates the
durable winner before returning success. Status is a plain machine-readable
file; this fleet intentionally has no TUI. The separate strict-ternary GPU
architecture, safety contract, and measurements are in `TERNARY_GPU_ENGINE.md`.

Default seed rotation is:

- 4x4: the public rank-49 ZT seed;
- 5x5: d967 (GPU after index normalization), d997, the structurally distinct
  GPU d1245 basin, GL3 d1248, d1249, and the public source;
- 6x6: both distinct d1931 basins, the intermediate d1935 symmetry door,
  d1938, two d2148 normalized-Kauers GPU doors, d2502, and both public sources;
- 7x7: the public rank-250 ZT seed plus the exact d3069 tunnel door.

## Bounded continuation results

Release/native/LTO/fast two-island controls on the development M-series host
gave the following results. Rates include concurrent workload noise. Every
saved endpoint passed both the final Tungsten gate and the independent Python
certificate verifier.

| tensor | aggregate moves | approximate rate | start -> best | rank drops | observed tunnel result |
|---|---:|---:|---:|---:|---|
| 4x4 | 55.1M | 8.08M/s in the 50M run | r49/d432 -> r49/d432 | 0 | no changed best |
| 5x5 | 55.1M + exhaustive GL3 closure | 3.94M/s | r93/d1291 -> r93/d1248 | 0 | walk removed 42 support entries, then GL3 removed one more |
| 6x6 | 55.1M | 2.19M/s | r153/d2574 -> r153/d2502 | 0 | 72 support entries of density removed; exact new basin |
| 7x7 | 60.1M | 1.00M/s | r250/d2966 -> r250/d2966 | 0 | changed r250/d3069 door at term-set distance 64 (32 terms replaced), no better objective |

The original one-hour CPU-only controls subsequently completed much longer
negative continuations. The 4x4 run tested exactly 13,683,163,136 ordinary
moves and retained r49/d432; the 7x7 run tested exactly 1,868,406,784 moves
and retained r250/d2966. Both recorded zero exact rejects and no rank drop.
These totals strengthen the bounded negative result, but do not prove either
local basin exhausted under moves outside the current catalogue.

The useful 5x5 and 6x6 endpoints are checked in as
`matmul_5x5_rank93_d1248_gl3_ternary.txt` (SHA-256
`6072edb746bc661c9fceb1c5b5ed7e9fc62842f300569c294da10e744416c9b6`)
and `matmul_6x6_rank153_d2502_ternary_walk.txt` (SHA-256
`c80d957d609e8fe4c3010c2860c2d75d5686739018647c5b160ec0eabd88a053`).
These are density/door improvements, not lower-rank records.

The deterministic global index normalization then produced much sparser exact
presentations:

| tensor | normalized input | elementary shears | normalized result | certificate SHA-256 |
|---|---:|---:|---:|---|
| 5x5 | r93/d1248 | 10 | r93/d997 | `ab41aa831a566d86a46fcfb52e4d4eafaae6131cb229501704a825b564ab0298` |
| 6x6 | r153/d2502 | 11 | r153/d1938 | `610eadf30fd46004e6898bcb5d01e4776b0062e358af3e3fc39a47fcd101dde7` |

Each normalized endpoint shares zero canonical terms with its input, giving
the maximum term-set symmetric-difference distances 186 and 306. Those large
distances describe presentation change inside a known global isotropy orbit;
they are not a claim of a new exact-move component. The 4x4/r49 seed and both
7x7/r250 seeds are strict-descent fixed points. The d997 and d1938 files pass
both the Tungsten integer gate and the independent Python certificate
expander.

Feeding those normalized presentations to the Metal breadth engine produced
a second compound improvement in 8,388,608 attempts apiece: 5x5 r93/d967
(`d63c756fef192ea7b0fe78bdc5378f2eb3af0f8cf63e6d3fb7b9f8110701c407`)
and 6x6 r153/d1931
(`f58820f4b3c4f71f4a7fd5b2303e30fda382c352d3b059fed74a678072186c37`).
Both GPU endpoints are fixed points of the complete elementary index-shear
descent, independently reconstruct the integer tensor, and are now the first
default seeds. The older d997/d1938 normalized files and d1245 GPU basin remain
in rotation for structural diversity.

The compound process also improved both distinct normalized Kauers 6x6 doors:
d2208 went to two different d2148 GPU endpoints in 8,388,608 attempts each.
They share only two of 153 terms with each other and none with d1931. Each
d2148 endpoint then reopens deterministic index descent and reaches a distinct
d1953 fixed point in three shears. The raw d2148 certificates are default
diversity seeds; CPU admission constructs d1953 and the GPU portfolio receives
both raw and normalized forms automatically. The two d1953 certificates are
retained explicitly (SHA-256 `f0f06c9812ecdec7ca79ebd07a65f296dc044a32a433e0f845f0d60837aa760c`
and `a38623255e9e7269b0d1ab681a2a0b39a48f91d94b4c741d1a3bdda6a6f7fcdd`).
GPU continuations of 134,217,728 attempts per door gated 32 changed exact
basins each with zero rejects but did not improve d1953 or beat d1931.

The capped uphill policy earned production status through a concrete 6x6
tunnel. From the original d1931 fixed point, its shallowest legal global shear
adds six support entries (d1937). A 134,217,728-attempt GPU basis walk reached
d1935, and one deterministic closing shear reached a *different* d1931
presentation. The old and new leaders share 147 of 153 canonical terms
(symmetric-difference distance twelve). The retained intermediate and endpoint
hashes are respectively
`78df6b6f0b08c82d737b3f1940f6442f85ab48e2f0a8550435cd0fe4aa05ef82`
and `39d8782dffd33b988447982bb13632553734da4c5c70b36148670645eeda3801`.
Independent reconstruction accepts both. Follow-up campaigns on the new
d1931 used 134,217,728 mixed attempts and another 134,217,728 downhill-only
attempts, gated 32 and seven changed exact returns, had zero rejects, and found
no density below 1931. The 5x5 capped d974 control likewise stayed d974 over 134,217,728
attempts. Thus the move demonstrably tunnels basins, while the bounded rank-
and density-improvement result remains negative.

The deterministic GL3 closure enumerated all source orders, gauges, and five
matrix representatives after every accepted improvement. From d1249 it found
208 distinct one-step presentations, accepted one d1248 endpoint, and then
proved that endpoint is a strict fixed point for this move catalogue. It
replaces exactly three terms (term-set symmetric-difference distance six); the
minimum remains six under the twelve tested tensor-axis/reversal symmetries.
The particular d1249-to-d1248 endpoint is also reachable by two legal pair
flips, so it is a useful density shortcut rather than evidence of a new 5x5
component. On the current 4x4 and 6x6 seeds there are no shared-factor triples.
The public 7x7 seed has 252 novel GL3 endpoints, but every one is denser by
8--20 support entries, so those are wander doors only.

Paired release builds showed no measurable hot-loop penalty at the 65,536-move
cadence: noisy one-core controls measured 1.72M/s before versus 1.85M/s after
on 10M 5x5 moves, and 0.477M/s versus 0.559M/s on 3M 7x7 moves. These are
guardrail measurements, not performance claims; the relevant result is that
the added scan did not produce a slowdown at this resolution.

The isolated index-shear stress benchmark ran 10,000 back-to-back probes at
about 126k/s (5x5), 80k/s (6x6), and 213k/s (7x7) on the development host,
with every resulting current/best view passing the integer gate. Production
does a deterministic closure only at admission and every 8,388,608 ordinary
moves, so the measured 5--13 microseconds per random preflight makes its
amortized hot-loop cost negligible at that cadence. A one-island integrated
smoke completed 9M moves at both 5x5 and 6x6 with the rare closure firing,
retained d967/d1931, and reported zero failures.

The 7x7 return is retained as
`matmul_7x7_rank250_d3069_ternary_door.txt` (SHA-256
`afde85db4aa5dff10c4e61c77c9e2610a68924407a62813369ec9bd0ef0e22bd`).
It shares 218 of 250 canonical terms with the source, replacing 32 terms; this
is a concrete exact signed tunnel seed rather than telemetry that disappears
at shutdown.

## Independent support-sign lift audit

An adjacent audit used FastMatrixMultiplication's exact CP-SAT support-sign
model at commit `e0ec7db4cb7d7ca41abbb2c6e3bd8c7de75c7c64` as a computational filter:

- the public 4x4/r49 ZT support shadow was feasible/`OPTIMAL` in 0.066 seconds;
- both saved GF(2) 4x4/r47 support orbits were `INFEASIBLE` in 0.073 and 0.233 seconds;
- all four saved GF(2) 7x7/r248 supports and all fourteen saved r247 supports
  were `INFEASIBLE`, with solve time at most 1.59 seconds after model build.

This does **not** constitute a formal UNSAT proof and does not exclude a signed
scheme on another support. It says that assigning ternary signs to those fixed
GF(2) support shadows is not a promising bridge. That negative filter motivates
the separate r250-to-r249 GF(2)-liftability scout instead of spending this CPU
fleet on repeated sign attempts over known incompatible supports.

## Validation

```sh
bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_worker_test.w \
  -o /tmp/flipfleet-ternary-worker-test
/tmp/flipfleet-ternary-worker-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_catalogue_test.w \
  -o /tmp/flipfleet-ternary-catalogue-test
/tmp/flipfleet-ternary-catalogue-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_gl3_tunnel_test.w \
  -o /tmp/flipfleet-ternary-gl3-test
/tmp/flipfleet-ternary-gl3-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_index_shear_test.w \
  -o /tmp/flipfleet-ternary-index-shear-test
/tmp/flipfleet-ternary-index-shear-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_index_word2_test.w \
  -o /tmp/flipfleet-ternary-index-word2-test
/tmp/flipfleet-ternary-index-word2-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_index_word2_audit.w \
  -o /tmp/flipfleet-ternary-index-word2-audit
/tmp/flipfleet-ternary-index-word2-audit

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_index_word2_bench.w \
  -o /tmp/flipfleet-ternary-index-word2-bench
/tmp/flipfleet-ternary-index-word2-bench 5000000 12

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_index_word3_test.w \
  -o /tmp/flipfleet-ternary-index-word3-test
/tmp/flipfleet-ternary-index-word3-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_index_word3_audit.w \
  -o /tmp/flipfleet-ternary-index-word3-audit
/tmp/flipfleet-ternary-index-word3-audit

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_index_word3_bench.w \
  -o /tmp/flipfleet-ternary-index-word3-bench
/tmp/flipfleet-ternary-index-word3-bench 5000000 12

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_seed_variants_test.w \
  -o /tmp/flipfleet-ternary-seed-variants-test
/tmp/flipfleet-ternary-seed-variants-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_gl4_audit_test.w \
  -o /tmp/flipfleet-ternary-gl4-audit-test
/tmp/flipfleet-ternary-gl4-audit-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_span_refactor_test.w \
  -o /tmp/flipfleet-ternary-span-test
/tmp/flipfleet-ternary-span-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_span_refactor_bench.w \
  -o /tmp/flipfleet-ternary-span-bench
/tmp/flipfleet-ternary-span-bench 512

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_dependency_median_test.w \
  -o /tmp/flipfleet-ternary-dependency-median-test
/tmp/flipfleet-ternary-dependency-median-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_dependency_median_bench.w \
  -o /tmp/flipfleet-ternary-dependency-median-bench
/tmp/flipfleet-ternary-dependency-median-bench \
  benchmarks/matmul/metaflip/matmul_7x7_rank250_d3069_ternary_door.txt \
  7 0 2 1000000 12
```

The worker test gates Strassen-7, Laderman-23, exact split/combine and signed
basis moves, a 20,000-move walk, and the 49th coordinate of a naive 7x7 seed.
The catalogue test gates all upstream and continuation certificates, verifies
the two 6x6 basins differ, and tests malformed-parser rejection.
The GL3 test checks every matrix/inverse pair, the planted singleton pair-flip
component, complete local-tensor preservation, the d1249-to-d1248 fixed-point
descent, distance six, and negative strict-descent controls at 4x4, 6x6, and
7x7. The index-shear test checks exact inverse restoration, the complete
d997/d1938 descents, the GPU d967/d1931 fixed points, and integer gates at all
four dimensions. The atomic word-two regression checks planted forward and
inverse strict barriers, changed-support endpoints, exact restoration, and
admission minima on all three 4x4--6x6 leaders; its exhaustive audit and
matched continuation keep the bounded diversity/no-objective result
reproducible. The seed-variant test expands nine raw 6x6 defaults into
nine CPU-normalized and exactly fifteen fingerprint-unique GPU raw,
normalized, and capped-shallow seeds; it gates every seed and proves CPU
variants are closure fixed points. The GL4 audit proves the direct lane cannot fire on any
pinned best seed because every shared-factor bucket has size below four. The
signed-span regression proves planted rank-changing and cancellation moves,
then its benchmark keeps the bounded 4x4--7x7 negative reproducible.

## Signed archive-nullspace splicing

`flipfleet_ternary_parent_nullspace.w` treats nearby exact signed schemes as a
joint integer column system rather than projecting away signs. Twelve fixed
weighted-Gram profiles over each of two primes give a proof-safe lower bound on
column rank; every surviving binary relation is then checked over the full
integer tensor before materialization. The bounded 5x5--7x7 audit proves 6,228
proper exact rank-neutral splices and materializes twelve representative
children. Five improved their own starting density over one million walk steps,
but none beat its better parent or dropped rank. It is consequently retained
for offline/low-cadence archive diversity, not the default hot path. Full
method, pair table, runtime, and commands are in
`TERNARY_PARENT_NULLSPACE.md`.

## Signed five-factor dependency median

`flipfleet_ternary_dependency_median.w` is the integer-safe counterpart of the
GF(2) five-bucket move. It requires an actual relation
`sum s_i f_i = 0` with every `s_i` equal to `+1` or `-1`; modulo-two support
circuits are insufficient and have a dedicated negative regression. Signed
pair sums are hash-matched against signed triple sums, every collision and
relation is checked coefficient by coefficient, and every durable endpoint
passes the complete integer matrix-multiplication gate.

Complete default/archive audits found thousands of real unit relations and
many exact changed shoulders, including `+1` endpoints at 5x5 and 7x7, but no
rank-neutral endpoint or rank drop. Across 168 million matched continuation
moves, the median never established an advantage over ordinary exact split
shoulders; on the 7x7 d3069 diversity door it lost 4-to-8. The move therefore
remains an offline executable audit and consumes no production CPU cadence or
GPU lane. The proof, full table, planted 5-to-4 and Laderman 32-to-23 controls,
and replay commands are in `TERNARY_DEPENDENCY_MEDIAN.md`.

## Current limits

- CPU islands plus an optional strict-ternary Metal breadth engine; GPU is on
  by default and `--no-gpu` disables it. See `TERNARY_GPU_ENGINE.md`.
- Square 4x4 through 7x7 in the fleet CLI. The underlying two-mask worker also
  supports 2x2 and 3x3 for tests.
- Coefficients outside `{-1,0,1}` and rational denominators are intentionally
  unsupported; they need a wider coefficient representation.
- Partner discovery is a linear scan. The measured rates are adequate for a
  scout, but an indexed shared-factor table is the next clear CPU optimization
  if 4x4/7x7 campaigns begin returning useful basins.
- No Tungsten syntax or compiler extension was required.
