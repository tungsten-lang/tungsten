# Exact GF(2) rank campaigns with inner dimension two

## Claim boundary

This directory generalizes the quotient-rank argument used to close
`<3,2,4>` to every GF(2) matrix-multiplication tensor `<a,2,c>`.  It contains
an exact direct-rank encoding, an independently decoded SAT-model audit, an
exhaustive fixed-term symmetry split, and a checked-proof replay path.

The finite-geometry branch now gives three complete checked exact-rank
results over GF(2):

```text
R(<2,2,3>) = 11,  R(<2,2,4>) = 14,  R(<2,3,3>) = 15.
```

It also gives the new checked interval
`17 <= R(<2,2,5>) <= 18`; the lower-bound replay is
`n225_verify_wang.py`, and the upper endpoint is the exact local `3+2` block
composition.  [`N225_RANK18_CAMPAIGN.md`](N225_RANK18_CAMPAIGN.md) identifies
the exact child-rank obstruction in the current Wang tree and gives the
complete, resumable 43-shard direct rank-17 closure campaign.

For the next primitive case, the rigorous interval remains
`19 <= R(<2,2,6>) <= 21`.  [`N226_RANK20_CAMPAIGN.md`](N226_RANK20_CAMPAIGN.md)
pins the complete 43-shard direct rank-19 campaign, its exact generation and
resume commands, measured RREF/no-RREF/dual/polarity portfolio behavior, and
the strict proof-acceptance boundary.  No current rank-19 shard is solved.

The neighboring shape `<2,3,5>` is no longer at the analytic lower bound.
[`../proof_n235/`](../proof_n235/) contains a verifier-accepted 31-orbit Wang
table, a multiplicity-aware capacity CNF with CakeML-checked XLRUP proof, and
an independent incidence replay proving
`23 <= R_GF(2)(<2,3,5>) <= 25`.  It is kept in its own package because its
inner dimension is three rather than two.

[`SMALL_PRIMITIVE_FRONTIER.md`](SMALL_PRIMITIVE_FRONTIER.md) records the
certificate hashes, complete orbit covers, exact upper schemes, bounded
follow-up experiments, and pinned verifier replay commands.  The larger
direct-rank objective remains open: `<5,2,4>` rank 32, cyclically equivalent
to `<2,4,5>`, has not been excluded.  That campaign has 148 shards; every
shard must be proved UNSAT and formally checked before claiming rank at least
33.  A timeout or a finite FlipFleet miss is not a proof.

The encodings were validated on `<2,2,2>`: the rank-seven control is SAT and
its decoded factors reconstruct every tensor coefficient, while all five
rank-six coarse shards are UNSAT.  Their FRAT-XOR logs were elaborated to
XLRUP and accepted by the CakeML `cake_xlrup` checker.  This re-establishes a
known result and tests the proof path; it is not a new theorem.

## Universal quotient condition

Regroup the first two factor spaces as

```text
(F2^a tensor F2^2) tensor (F2^2 tensor F2^c)
  = Q tensor R,   dim(Q)=a*c, dim(R)=4.
```

The `a*c` target slices span

```text
K = Q tensor <I_2>.
```

Let `S` be the span of the `r` displayed `A_t tensor B_t` columns.  Exactness
requires `K` to be a subspace of `S`.  Projecting through
`R -> R/<I_2>` therefore gives

```text
rank(pi(S)) = dim(S)-a*c <= r-a*c.
```

No rank-one hypothesis is used here.  In coordinates `(i,k)`, the three
quotient entries of term `t` are

```text
A[i,0] B[0,k] + A[i,1] B[1,k]
A[i,0] B[1,k]
A[i,1] B[0,k].
```

For a hypothetical rank-32 `<5,2,4>` decomposition this is a `60 x 32`
binary matrix of rank at most **12**.  Both proof encodings can factor this
matrix as `U L`; an exact RREF gauge on `L` removes its `GL(12,2)` freedom.

## Exact direct-rank encoding

[`inner2_direct_rank_xnf.py`](inner2_direct_rank_xnf.py) is the recommended
solver input.  It keeps tensor parity equations as native XOR constraints for
CryptoMiniSat and uses ordinary Tseitin CNF for products.  The optional
`--quotient-rank` factorization is redundant with exactness but substantially
strengthens propagation.

[`inner2_direct_rank_opb.py`](inner2_direct_rank_opb.py) emits the same exact
span problem as pseudo-Boolean constraints and includes the quotient
factorization by default.  It is useful for a RoundingSat/VeriPB proof route,
although RoundingSat was much colder than CryptoMiniSat in the current probes.

In either encoding:

1. binary matrices `A_t` and `B_t` define the adjacent factors;
2. `D_t=A_t tensor B_t` is encoded with AND gates;
3. binary `C_t[i,k]` coefficients express each target slice as a sum of the
   `D_t` columns; and
4. every one of the `4*a*c*a*c` tensor coefficients is constrained exactly.

The formula means rank **at most** `r`: a term may have zero `C_t` and act as
padding.  Fixed-term campaign shards always fix a nonzero `C_0`, which is safe
because any actual decomposition has a used term that can be moved to slot
zero.

`--lex-terms` is an optional term-permutation symmetry break.  It leaves the
fixed term zero alone and sorts the complete `(A_t,B_t,C_t)` bit vectors of
terms `1..r-1`.  This is equisatisfiable: all unfixed summands can be permuted
together, including zero-`C` padding terms.  With quotient strengthening, the
projected matrix columns are permuted at the same time and `L` can simply be
put back into its unique RREF gauge for the new column order.  Term zero cannot
in general be included in the ordering because its prescribed orbit
representative need not be the lexicographically first summand.

For cyclic `<a,2,2>` orientations, `--dual-inner2-quotient` adds the second
independent inner-two quotient constraint on `B_t tensor C_t`.  It is a
redundant consequence of exactness, just like the primary `A_t tensor B_t`
constraint, and is retained as an optional solver portfolio arm.  The
rank-seven Strassen control remains SAT and independently reconstructs with
both constraints.  The complete `<5,2,2>` measurements and commands are in
[`N225_RANK18_CAMPAIGN.md`](N225_RANK18_CAMPAIGN.md).

[`inner2_direct_rank_audit.py`](inner2_direct_rank_audit.py) reads either
RoundingSat `xN` models or integer DIMACS models, independently reconstructs
all target slices, recomputes the quotient rank, and reports the fixed-factor
invariants.

## Exhaustive fixed-term shards

The ranks of `A_0` and `B_0` lie in `{1,2}`.  Matrix ranks classify the pair
under the matrix-multiplication isotropy except when both ranks are one.  In
that case, writing `A=x y^T` and `B=p z^T`, the contraction `y^T p` is an
additional GF(2) invariant.  Thus the exact coarse cover has five cases:

```text
a1_b1_p0
a1_b1_p1
a1_b2
a2_b1
a2_b2
```

There are five cases, not four.  Omitting either rank-one pairing would make
an UNSAT conclusion incomplete.

Fixing `A_0` and `B_0` leaves a large stabilizer acting on the nonzero third
factor.  [`inner2_stabilizer_orbits.py`](inner2_stabilizer_orbits.py) derives
elementary generators for that action and exactly enumerates every orbit.
For `<5,2,4>` the split is:

| coarse case | nonzero C orbits | covered C values | orbit-list SHA-256 |
|---|---:|---:|---|
| `a1_b1_p0` | 17 | 1,048,575 | `c156d45e70a58464d1d465d3739d567513d0fb047bcd665b3d7928dcd7aa341f` |
| `a1_b1_p1` | 17 | 1,048,575 | `c156d45e70a58464d1d465d3739d567513d0fb047bcd665b3d7928dcd7aa341f` |
| `a1_b2` | 31 | 1,048,575 | `461d5477b4d3f3e9c09bb1afe1730eb77d273a2df0ceb5e164e89c835779401d` |
| `a2_b1` | 36 | 1,048,575 | `1d75ce548608cfbcb3b5232f60a50e0ad313308c6ba2dac9167ddb94364e5012` |
| `a2_b2` | 47 | 1,048,575 | `a04dcf578de060cf6af8a3dd50d1715c17d1a582cd8668fb3069c4113bde8ee8` |

The total is 148 formulas.  Enumeration takes about 16.3 seconds and 46 MB
maximum RSS on the M5 Max host.  The unit test also brute-forces the full
`GL(2,2)^3` stabilizer and checks that the generated and brute-force orbit
partitions agree for every `<2,2,2>` coarse case.

Generate the complete quotient-strengthened XNF campaign with:

```sh
python3 inner2_generate_campaign.py /tmp/n524-r32 \
  --a 5 --c 4 --terms 32
```

The manifest pins every formula hash and records the finite coverage.  Use
`--enumerate-only` to audit the split without writing roughly 700 MB of
quotient-strengthened formulas.  `--without-quotient-rank` emits the smaller
exact formulas for a propagation comparison.  `--case` and `--orbit-index`
are probe controls; a manifest made with either restriction is deliberately
marked `coverage_complete=false`.  Add `--lex-terms` to generate the optional
ordered formulas; it is intentionally not the default because the short
solver comparison below did not establish a proof-time win.

## Proof production and acceptance

For each formula, produce and elaborate a proof with pinned builds of
CryptoMiniSat and FRAT-XOR:

```sh
cryptominisat5 --verb 0 --threads 1 FORMULA.xnf FORMULA.frat
frat-xor elab FORMULA.frat FORMULA.xnf FORMULA.xlrup
```

Only an UNSAT solver result with a successfully elaborated proof counts.
After all 148 XLRUP files exist, replay the complete set with:

```sh
python3 inner2_verify_xnf_campaign.py \
  /tmp/n524-r32/manifest.json /tmp/n524-r32/proofs \
  --checker /path/to/cake_xlrup \
  --output /tmp/n524-r32/checked-proofs.json
```

The verifier independently rebuilds the 148-orbit cover, checks every formula
hash and size, requires one exact `s VERIFIED UNSAT` from CakeML for every
XLRUP file, rejects warning/error/failure diagnostics, and hashes the checked
proof set.  On Apple Silicon, run the x86-64 CakeML checker through a small
`linux/amd64` Docker wrapper and pass that wrapper as `--checker`.

For a serial, hash-gated, resumable CryptoMiniSat campaign, use
[`inner2_run_xnf_campaign.py`](inner2_run_xnf_campaign.py).  It keeps every
transcript, advances seeds across attempts, independently audits SAT models,
and labels solver-only UNSAT results as unchecked.  Minimum-rank-only guards
such as `--nonzero-c` require `--known-lower-bound` equal to the term count;
the runner and final verifier accept the guarded `<5,2,2>` rank-17 campaign
only after hash-auditing the pinned checked `<2,2,5>` Wang certificate.

## Feasibility audit

The old constrained-subspace search was compiled at upstream commit
`efd22070269157e65aaf8d61a21da253a4000c61` for `<2,4,5>`.  Its 86 symmetry
orbits were generated in 0.47 seconds.  A checked 100,000-node backtracking
pass took 155.43 seconds and about 1.20 GB peak RSS, and Wang's verifier
accepted the resulting certificate with root lower bound 25.  The rank-one
and rank-two singleton orbits reached 24 and 25.  This is rigorous but weaker
than Bläser's existing algebraic-closure lower bound 28 for `<2,4,5>`, so it
does not force a useful factor type in a hypothetical rank-32 decomposition.

Current exact-encoding measurements are:

| target/shard | variables | clauses/PB constraints | XORs | bytes | solver result |
|---|---:|---:|---:|---:|---|
| `<5,2,4>`, r32 lean XNF | 54,976 | 161,362 | 1,600 | 2,835,562 | CryptoMiniSat indeterminate after 30 CPU s |
| `<5,2,4>`, r32 quotient XNF | 80,144 | 252,814 | 4,160 | 4,563,876 | CryptoMiniSat indeterminate after 30 CPU s |
| `<5,2,4>`, r32 quotient OPB | 94,544 | 255,194 | n/a | 9,161,206 | RoundingSat indeterminate after 10 s |
| `<4,2,4>`, r23 lean XNF | 25,760 | 75,134 | 1,024 | 1,284,056 | all five coarse shards indeterminate after 60 CPU s each |
| `<4,2,4>`, r23 quotient XNF | 34,514 | 104,650 | 2,496 | 1,852,863 | representative indeterminate after 60 CPU s |
| `<3,2,5>`, r22 quotient XNF | 29,685 | 90,047 | 2,220 | 1,586,587 | representative indeterminate after 60 CPU s |

The lex encoding itself was exhaustively checked on all assignments of a
two-bit comparator.  As end-to-end controls, CryptoMiniSat 5.14.7 found the
`<2,2,2>` rank-seven `a1_b1_p1` formula SAT both with and without lex ordering,
and found every one of the five rank-six coarse formulas UNSAT in both modes.
The lex-enabled SAT model was independently decoded: all tensor coefficients
matched, quotient rank was three (the cap), all seven terms were used, and
the six unfixed term vectors were sorted.

A matched one-thread probe on the M5 Max used the `a2_b2`, residual-C orbit
zero (`C=1`) quotient/RREF shard.  Each arm received three CryptoMiniSat seeds
and 10 CPU seconds per seed; all twelve runs remained indeterminate.  Counts
below are three-run arithmetic means, so they measure search behavior rather
than proof progress:

| target | lex | variables | CNF clauses | XNF bytes | conflicts / 10 s | decisions / 10 s | propagations / 10 s |
|---|---:|---:|---:|---:|---:|---:|---:|
| `<4,2,4>`, r23 | no | 34,514 | 104,666 | 1,853,034 | 148,482 | 667,338 | 156.7M |
| `<4,2,4>`, r23 | yes | 35,186 | 108,677 | 1,933,387 | 167,502 | 553,788 | 156.0M |
| `<5,2,4>`, r32 | no | 80,144 | 252,834 | 4,564,079 | 87,326 | 823,391 | 219.0M |
| `<5,2,4>`, r32 | yes | 81,284 | 259,644 | 4,701,539 | 118,209 | 742,503 | 263.7M |

Lex ordering therefore costs 1.4--2.0% more variables and 2.7--3.8% more CNF
clauses.  It produced 13% and 35% more conflicts in these short probes, but
fewer decisions and no solved shard.  That is enough to retain it as a
portfolio option, not enough to enable it campaign-wide.

Fixing the first residual-C orbit did not close any of the five sampled
`<5,2,4>` or `<4,2,4>` families in the same short windows.  These are honest
feasibility negatives, not lower bounds.  They show that the 148-way split is
a real distributed proof campaign rather than a laptop-instant result.

The most defensible next run is a staged portfolio: solve the smallest C
orbits of `<4,2,4>` first to calibrate proof-size tails, then allocate the
large host to all 148 `<5,2,4>` shards with per-shard resume and proof logging.
Do not discard a hard shard merely because its orbit is small; completeness
requires every orbit.

## Wang `<2,4,4>` 86-orbit CPU campaign

There is a second, complementary route for the smaller rectangular target.
At Wang's pinned upstream revision
`efd22070269157e65aaf8d61a21da253a4000c61`, choosing matrix dimensions
`N0=2,N1=4,N2=4` makes the constrained side eight-dimensional. The upstream
enumerator gives exactly **86** symmetry orbits, distributed by constraint
dimension as `1,2,8,17,30,17,8,2,1`. This is a much smaller campaign than the
134 fixed-first-term SAT shards, and its degenerate/backtracking dependencies
are shared through one dynamic-programming certificate.

The rigorous status is still

```text
23 <= R_GF(2)(<2,4,4>) <= 26.
```

The lower endpoint is the existing algebraic bound; rank 26 is realized by
the exact catalogue leaf. A verifier-accepted Wang checkpoint below 24 does
not weaken the independent lower bound of 23, and a bounded search miss does
not raise it. The interval changes only if Wang's verifier accepts a complete
certificate whose unconstrained root is at least 24 (or an independent proof
does so).

[`inner2_wang_n244_campaign.py`](inner2_wang_n244_campaign.py) drives the
pinned CPU implementation without copying or modifying upstream search code.
It checks the Git revision, compiles all three mains with the `<2,4,4>`
defines, audits the complete 86-orbit protobuf, keeps the `.pb.txt` and `.btp`
files paired, replays Wang's verifier after each search pass, and produces
hash-pinned paired snapshots. On macOS it enables the already-needed
`-fno-lto` build workaround by default.

Clone and pin upstream, then build and enumerate:

```sh
git clone https://github.com/wcgbg/tensor-rank-lower-bound.git \
  /tmp/tensor-rank-lower-bound
git -C /tmp/tensor-rank-lower-bound checkout \
  efd22070269157e65aaf8d61a21da253a4000c61

export WANG_TENSOR_RANK=/tmp/tensor-rank-lower-bound
python3 inner2_wang_n244_campaign.py \
  --work-dir /tmp/wang-n244 build
python3 inner2_wang_n244_campaign.py \
  --work-dir /tmp/wang-n244 enumerate
```

The practical first pass caps forced-product enumeration and spends the CPU
budget on the other three techniques:

```sh
python3 inner2_wang_n244_campaign.py \
  --work-dir /tmp/wang-n244 search \
  --fresh --step-limit 100000 --max-map-size 3000000 \
  --forced-product-max-iterations-log2 0
```

This cap is not a heuristic truncation of a recorded forced-product proof. In
the pinned implementation, a cap of zero returns before enumeration as soon
as the candidate count exceeds one. Flattening remains on, degenerate
reduction remains on, and backtracking remains on. Any proof they emit is
reconstructed by the unchanged verifier. One-candidate forced-product cases
remain enabled and are also recomputed by that verifier. Wang's own CLI
default is still `24`; omit the wrapper cap with
`--use-upstream-forced-product-default` if a machine should pay for those
enumerations. In particular, do not use the default for an accidental `2^32`
pass merely to reproduce a proof type that the cheaper portfolio does not
need.

Resume by rerunning `search` without `--fresh`, normally with a larger step
limit. The live certificate must be updated **in place**: Wang's searcher
loads the backtracking archive derived from its output filename, so moving a
protobuf without its sibling `.btp` silently severs the checkpoint pair. The
wrapper enforces the in-place name and verifies the pair after the pass:

```sh
python3 inner2_wang_n244_campaign.py \
  --work-dir /tmp/wang-n244 search --step-limit 1000000

python3 inner2_wang_n244_campaign.py \
  --work-dir /tmp/wang-n244 snapshot \
  /tmp/wang-n244/snapshots/after-1m.pb.txt
```

`snapshot` first runs the unchanged upstream verifier, refuses to overwrite an
existing snapshot, copies each file through a temporary name and atomic
rename, then writes a JSON manifest last. The manifest pins both SHA-256
hashes, the orbit count, upstream revision, and root bound; its presence marks
a complete pair. A standalone replay is:

```sh
python3 inner2_wang_n244_campaign.py \
  --work-dir /tmp/wang-n244 verify
python3 inner2_wang_n244_campaign.py \
  --work-dir /tmp/wang-n244 audit
```

The CPU/Mac validation used the pinned source and the commands above. The
three-binary cold Bazel build completed in 97.3 seconds; enumeration reported
all 86 orbits. A fresh 1,000-node smoke produced a verifier-accepted root 20,
the 100,000-node pass raised it to 21, and a resumed 1,000,000-node pass stayed
at 21. The last pass had 44 recorded backtracking proofs and the verifier
accepted the complete protobuf/BTP pair. These are useful plumbing and
feasibility checks, but both 20 and 21 are weaker than the independent bound
23, so they do not change `23..26`.

The pinned upstream has no tracked CUDA lower-bound backend, so no CUDA result
is claimed here and no speculative CUDA code is vendored. If such a backend
is later imported, its rectangular template/link audit must explicitly cover
all three cyclic orientations `<2,4,4>`, `<4,4,2>`, and `<4,2,4>`, plus the
non-CUDA stub used by CPU-only builds. That is future work and must be tested
on an actual CUDA host; this Apple-Silicon run cannot validate it.

## Tests

```sh
python3 test_inner2_direct_rank.py -v
python3 test_inner2_wang_n244_campaign.py -v
python3 n223_verify_wang.py --audit-only
python3 n224_verify_wang.py --audit-only
python3 n233_verify_wang.py --audit-only
python3 n225_verify_wang.py --audit-only
python3 -m py_compile *.py
```

The tests cover rank normal forms, exhaustive lex and not-equal truth tables,
an independently audited Strassen model, five-shard distinction, fixed-C
encoding, guarded-campaign prerequisite replay, campaign cardinality, and brute stabilizer agreement on
`<2,2,2>`. The Wang campaign tests pin the compile-time orientation and
forced-product cap semantics, reject incomplete orbit covers and unpaired
backtracking archives, and round-trip paired checkpoint snapshots.
