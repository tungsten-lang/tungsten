# GF(2) `<3,2,4>` constrained lower-bound proof

## Status and claim boundary

This package records two completed, independently replayed constrained results
and one completed global consequence:

> For the published `n324` constrained-subspace orbit 29, represented by the
> rank-two `3x2` form `6`, the GF(2) tensor-rank lower bound is **19**, improving
> the published lower bound 18.

The capacity CNF was proved UNSAT, elaborated from FRAT-XOR to XLRUP, and
accepted by the formally verified CakeML `cake_xlrup` checker.

> After permuting the factors to `<2,4,3>`, the one-dimensional constraint
> represented by the rank-two `2x4` form `18` has GF(2) constrained rank at
> least **19**, improving its verified-certificate lower bound 18.

The second result is covered by 46 disjoint pseudo-Boolean shards. Every shard
was proved UNSAT by current RoundingSat and replayed by VeriPB 3.0.2 without an
assumption rule, warning, or other diagnostic.

> The unconstrained GF(2) matrix-multiplication tensor `<3,2,4>` has tensor
> rank **20**.

The quotient-rank argument below reduces the remaining rank-19 question to six
pseudo-Boolean instances.  All six are UNSAT.  Their deletion-free proof logs
were replayed by VeriPB 3.0.2 in forced checked-deletion mode without a warning
or error.  The known rank-20 decomposition supplies the matching upper bound.

## Pinned input

- Upstream prover: <https://github.com/wcgbg/tensor-rank-lower-bound>
- Upstream commit: `efd22070269157e65aaf8d61a21da253a4000c61`
- `cert_matrix_q02_n324.pb.txt` SHA-256:
  `b1926bac436850d6c43c1c909a4bdfd9c84a073ed14b6359635944dfd694316d`
- `cert_matrix_q02_n324.btp` SHA-256:
  `875f7ce52ad6afc9ffbab70269cbaca25cdf205174da2c8e2edec2af5aff2e4d`
- FRAT-XOR: <https://github.com/meelgroup/frat-xor>
- FRAT-XOR commit: `855f3d0ae45fe37c3ad29e4a8ef56e62e1b5e4ad`
- CryptoMiniSat version: 5.14.7

The replay scripts require Python 3.10 or newer (`int.bit_count` is used).
The Python replay code imports no Wang search or verifier implementation. It
parses only the constrained representatives and lower bounds in the published
text certificate.

## Independent finite-geometry replay

[`n324_common.py`](n324_common.py) reconstructs the action

```text
GL(3,2) x GL(2,2), order 168 * 6 = 1,008,
```

on the six-dimensional `3x2` first-factor space. It checks that:

1. the certificate contains exactly 31 constrained-subspace orbits;
2. expanding those orbits covers all 2,825 subspaces of `F_2^6` exactly once,
   with a consistent lower bound and orbit index;
3. nonzero one-dimensional constraints have two orbits: orbit 28 contains the
   21 rank-one matrices, and orbit 29 contains the 42 rank-two matrices;
4. the unconstrained orbit 30 has the published lower bound 19.

Run the structural replay and emit its machine-readable summary with:

```sh
python3 verify_structure.py CERT.pb.txt --btp CERT.btp \
  --summary /tmp/n324-summary.json --isotropy-samples 100
```

Add `--audit-residual` to independently re-enumerate the 48, 80, and 98
residual `(B,C)` pair orbits used by the SAT shards. That audit is exact but is
the slowest Python step.

## Orbit-29 capacity proof

Let `S=<6>`, whose published lower bound is 18. The quotient `F_2^6/S` has 31
nonzero points. An open depth-18 substitution state is duplicate-free: a
duplicate already supplies enough occurrences plus a certified constrained
lower bound to close the state.

For every subspace `U` containing `S`, an open set `X` must satisfy

```text
|X intersect (U/S)| <= 18 - certified_lower_bound(U).
```

Conversely, these inequalities characterize an open set: for any occurrence
subset, choose the subspace it spans. There are 374 such containing subspaces.
[`orbit29_capacity.py`](orbit29_capacity.py) encodes all 374 inequalities and
`|X| >= 18` using Sinz sequential counters. The result has 10,657 variables
and 20,320 clauses.

The largest open set has size 17. One independently checked witness is:

```text
11 17 19 24 25 26 27 33 35 41 43 49 50 51 56 57 59
```

The checked proof artifacts are:

| Artifact | SHA-256 |
|---|---|
| Capacity CNF | `96d7b3b591b7e15edd79fa4e5c5b9a98efdee49da0aeaecaa1802b19fd922de4` |
| CryptoMiniSat FRAT-XOR | `0a71b7a9c4b5c202cff70bea1fc2981500a2609f054f627cb2ade4bab4f43828` |
| Elaborated XLRUP | `a5ce61305607af51d84da7bc4336048e2c79148e2adb031c0a458aff05fe3932` |

Measured on the M5 Max host:

| Stage | Wall time | Peak RSS/result |
|---|---:|---:|
| CryptoMiniSat UNSAT | 0.26 s | 8,896,512 bytes |
| `frat-xor elab` | 0.32 s | 9,764,864 bytes |
| `cake_xlrup` in linux/amd64 Docker | 0.30 s | 31,096,832-byte Docker process RSS; `s VERIFIED UNSAT` |

Regenerate and check the capacity proof with:

```sh
python3 orbit29_capacity.py CERT.pb.txt /tmp/n324-orbit29.cnf
shasum -a 256 /tmp/n324-orbit29.cnf

cryptominisat5 --verb 0 --threads 1 \
  /tmp/n324-orbit29.cnf /tmp/n324-orbit29.frat

frat-xor elab /tmp/n324-orbit29.frat \
  /tmp/n324-orbit29.cnf /tmp/n324-orbit29.xlrup

cake_xlrup /tmp/n324-orbit29.cnf /tmp/n324-orbit29.xlrup
```

The supplied `cake_xlrup.S` is x86-64 assembly. On an Arm Mac, compile and run
it inside a linux/amd64 container. The checker build used for the recorded run
was equivalent to:

```sh
gcc basis_ffi.c cake_xlrup.S -o cake_xlrup -std=c99 \
  -DCML_HEAP_SIZE=4096 -DCML_STACK_SIZE=4096
```

## Rotated `<2,4,3>` rank-two capacity proof

Permuting the tensor factors makes the original `2x4` B mode the constrained
factor of Wang's `<2,4,3>` problem.  At upstream prover commit
`efd22070269157e65aaf8d61a21da253a4000c61`, a complete search certificate has
86 constrained-subspace orbits.  Wang's independent verifier accepted all 86
orbits and the BTP tree and reported root lower bound 18.  Orbit 84 is the
one-dimensional rank-two constraint `<18>`, also with certificate lower bound
18.

Pinned artifacts:

| Artifact | SHA-256 |
|---|---|
| `cert_matrix_q02_n243_search.pb.txt` | `7f7edeebaa8c54f9b392caf8b3a615c1dc1648ff4533e23ee3df7d8118496886` |
| `cert_matrix_q02_n243_search.btp` | `aca7d1985d90af3c3121b1f4cc5cf24dff2ae922a7d4544a415ff2c8b238ceba` |
| Capacity table | `0e5343d8b0f0c9f8581fcf07677aa05a97f969a8c0f86a5431ed3aa86376d2b2` |
| RoundingSat `d4edbf7` x86-64 binary | `cf115250c7539000b39b950d53ddf9d1dfd4ca0d004caf52038a116e7efe3ed5` |
| VeriPB 3.0.2 binary, source `bfe2b6232da70f4dd74aa73d3932da2f42479ff5` | `ab85d4a75ca24e8917c4f812e337756e69790ca5e836294a7c5f3a77a26dadb6` |

[`n243_independent_audit.py`](n243_independent_audit.py) imports no Wang code.
It expands the 86 representatives under `GL(2,2) x GL(4,2)` and verifies exact,
single-orbit coverage of all 417,199 subspaces of `F_2^8`, including the exact
Gaussian-binomial count in every dimension.  It then independently rebuilds
all 29,212 subspaces containing `<18>` and checks the 28,480 nontrivial
capacity inequalities over the 127 nonzero quotient points.

[`n243_capacity_shards.py`](n243_capacity_shards.py) independently enumerates
the 576-element stabilizer of `<18>`, verifies that every capacity inequality
is invariant under it, and derives six quotient-point orbits.  A root shard
fixes the first occupied orbit representative and zeros all prior orbits.  The
two hard roots are partitioned once more under their representative
stabilizers into 20 and 22 child shards.  Thus the checked proof cover is
exactly those 42 child shards plus root shards 2 through 5: 46 disjoint,
exhaustive cases.  The two aggregate root files are not members of the proof
cover.

The selected OPBs total 127,966,166 bytes; their proofs total 411,824,811
bytes.  [`n243_capacity_manifest.sha256`](n243_capacity_manifest.sha256) pins
every one of the 46 OPBs and 46 proofs.  The largest proof is 253,202,206 bytes
and was solved in 552 seconds on the M5 Max host.  The full Wang certificate
replay took 304.83 seconds wall time; the independent Python geometry/table
audit took 102.12 seconds and about 111 MB RSS.

Rebuild the shards and replay the proof set with:

```sh
python3 n243_independent_audit.py CERT.pb.txt CAPACITY.table
python3 n243_capacity_shards.py CAPACITY.table /tmp/n243-opb

# Run RoundingSat d4edbf7 with --proof-log once for every child OPB and for
# root OPBs 02, 03, 04, and 05.  Put the resulting .pbp files in /tmp/n243-pbp.
python3 n243_verify_proofs.py /tmp/n243-opb /tmp/n243-pbp \
  --veripb /path/to/veripb \
  --emit-manifest /tmp/replayed.sha256
cmp /tmp/replayed.sha256 n243_capacity_manifest.sha256
```

The acceptance rule is deliberately stricter than solver exit status: all 46
proofs must have a terminal `conclusion UNSAT`, contain no assumption rule,
make VeriPB exit successfully with exactly one `s VERIFIED UNSATISFIABLE`, and
produce no warning, unjustified-assumption, assumption, error, or failure
diagnostic.  An older RoundingSat proof format containing LP `a` lines is not a
valid artifact for this result, even if a checker otherwise reaches an UNSAT
line.

The capacity UNSAT raises the constrained bound for `<18>` from 18 to 19.
Therefore a rank-19 `<3,2,4>` decomposition cannot contain a rank-two B factor:
remove that occurrence, permute the factors, and the remaining constrained
problem needs at least 19 terms, for a total of at least 20.  Consequently all
19 B factors in any rank-19 counterexample must be rank-one, selected from the
45 nonzero rank-one `2x4` forms.  **This lemma does not prove those B factors
are distinct.** The rank-one `<2,4>` constraint currently has only a verified
lower bound 17, so repetitions remain part of the global residual problem.

## Rank-one B occurrence bounds and residual cases

The same `<2,4,3>` certificate gives a stronger family of necessary
conditions than the singleton bound.  For every B subspace `U` with certified
constrained lower bound `L(U)`, any hypothetical rank-19 decomposition obeys

```text
number of terms with B in U <= 19 - L(U).
```

Remove those terms and project the remaining decomposition through `B/U` to
obtain the inequality.  Intersecting every certified subspace with the 45
rank-one `2x4` forms and keeping the strongest duplicate-free inequality gives
56,724 occurrence rows.  In particular each exact rank-one B form can occur at
most twice.  [`n243_independent_audit.py`](n243_independent_audit.py) emits the
table with `--occurrence-table`; the recorded table SHA-256 is
`751c521c24e9f5e87085f4ed3e781edba71ae0c66a97cdbd0088a2e2d3b7f1f8`.

[`n324_rankone_b_assignment_opb.py`](n324_rankone_b_assignment_opb.py) combines
those 56,724 inequalities with 42 full-B-span conditions coming from rank-two
A contractions.  Fixing one B value at a canonical retained A term leaves two
orbits in each missing-A case:

| Missing A | Fixed-B representatives | Orbit sizes |
|---|---|---|
| `(1,2)` | `1, 17` | `30 + 15` |
| `(1,4)` | `1, 16` | `30 + 15` |
| `(1,8)` | `1, 17` | `30 + 15` |

[`n324_b_orbit_audit.py`](n324_b_orbit_audit.py) independently expands the
actions and checks disjoint coverage of all 45 rank-one B forms.  These six PB
shards are necessary conditions only: a SAT assignment still has to admit C
factors solving all 576 tensor equations.

## Experimental Gaussian-Benders closure

For a necessary B assignment, the C factors form a 576-by-228 linear system
over GF(2).  If it is inconsistent, Gaussian elimination returns a left-null
selector `y` with `y M = 0` and `y target = 1`.  For term `t`, define

```text
Allowed_t = { B : y annihilates every C column of A_t tensor B }.
```

Every exact decomposition must choose at least one `B_t` outside its
`Allowed_t`; otherwise `y` would annihilate the entire left side while pairing
to one with the target.  This yields a sound one-hot PB cut.  The rejected
source is only one point in the excluded Cartesian product, so one Gaussian
dependency commonly removes a much larger B-assignment region.

[`n324_benders_cut.py`](n324_benders_cut.py) emits the clauses and serializes
the complete `y` selector and every `Allowed_t` table.
[`n324_verify_benders_archive.py`](n324_verify_benders_archive.py) is a separate
checker: it reconstructs the tensor system without importing the cut
generator, checks all occurrence/span conditions and earlier cuts, proves each
left-null relation, rebuilds each Allowed table and PB line byte-for-byte, and
binds every witness/table to SHA-256 entries in a replay manifest.  With
`--checked-instance`, it writes the cumulative OPB only *after* all external
cut lemmas pass.  This ordering matters because VeriPB otherwise sees learned
cuts as unproved input axioms.

The current exploratory campaign rejected 300 necessary assignments, 50 in
each of the six symmetry shards, and independently audited 7,831 learned cuts.
Each exact C system was inconsistent, but every shard still returned a new SAT
necessary assignment after its accumulated cuts.  Thus the cuts are useful
pruning lemmas, not an UNSAT result.  Across the 220 timed native runs, solve
times ranged from 1.50 to 15.19 seconds (median 3.25 seconds) and did not grow
monotonically with cut count.  The aggregate replay manifest has SHA-256
`2d3db41a4f7f83407a7e2e25516531dd398323b42981f436b629dd6c14c0385d`.
A monolithic exact 13,647-variable, 99,424-constraint OPB also reached a
120-second native time limit.  These measurements do **not** change the global
bound.

The cut generator also has an optional affine-left-null tunnel,
`--affine-samples`.  It adds homogeneous dependencies to a known `y target=1`
witness and therefore samples other sound points in the full left-null affine
space.  On a matched 25-model `(1,2), B=1` continuation, 512 samples/model
filled all 64 cut slots and accumulated 2,292 cuts by model 50 versus 1,295 for
the direct Gaussian witnesses.  Solver time fell from 5.01 to 3.09 seconds per
model on average; generating the sampled cuts cost about 1.08 seconds/model,
so the measured end-to-end effect was modestly positive.  It still found a new
SAT necessary assignment at model 50 and is therefore retained as an option,
not presented as a closure.

### Twelve-block reformulation and optimized witnesses

The apparent 576-by-228 C system is a coordinate permutation of twelve copies
of the same 48-by-19 coefficient matrix

```text
M[:,t] = A_t tensor B_t.
```

The twelve right-hand sides are the fixed target slices, and C feasibility is
exactly the assertion that every slice lies in `span{A_t tensor B_t}`.  This
structure was implicit in the original variable layout—the observed ranks
were multiples of twelve—but the first cut generator did not exploit it for
witness optimization.

[`n324_block_equivalence_audit.py`](n324_block_equivalence_audit.py)
independently checked all 300 archived models.  Every 48-by-19 block had rank
19; the full rank was exactly `12 * 19 = 228`; and the complete sets of
contradiction selectors emitted by block and full Gaussian elimination were
identical.  The same equivalence is now asserted by the generator and covered
by the regression tests.

`--block-restarts` searches the 28-dimensional homogeneous left-null coset of
each inconsistent target slice using coordinate descent.  On a fixed source,
512 random full-space samples found a best 224-literal clause, while four block
restarts found a 96-literal clause in 0.81 seconds.  In a matched ten-model
continuation from the same 50-model checkpoint, direct witnesses accumulated
1,544 cuts and averaged 4.30 seconds/solve; four block restarts accumulated
1,935 cuts and averaged 2.71 seconds/solve.  Both branches remained SAT as
necessary-B problems and every C system remained inconsistent.  Including cut
generation, the block strategy was a modest net win and is the preferred
bounded witness optimizer, but it is not a lower-bound proof.

Audit a campaign directory with:

```sh
python3 n324_block_equivalence_audit.py WORK --missing 1 2
```

### Residual-symmetry orbit lifts

The full residual groups preserving the fixed A support, canonical A term,
and fixed B representative have orders:

| Shard | Full group | Direct cuts | Order-8 lifted cuts | Result |
|---|---:|---:|---:|---|
| `(1,2), B=1` | 32,256 | 1,295 | 8,046 | SAT |
| `(1,2), B=17` | 64,512 | 1,306 | 8,027 | SAT |
| `(1,4), B=1` | 10,752 | 1,295 | 8,285 | SAT |
| `(1,4), B=16` | 21,504 | 1,324 | 8,282 | SAT |
| `(1,8), B=1` | 5,376 | 1,288 | 7,449 | SAT |
| `(1,8), B=17` | 10,752 | 1,323 | 8,466 | 60 s time limit |

Full orbit closure is impractical: among the first 100 cuts of the first
shard, the median individual orbit had size 1,680 and the maximum had size
32,256.  A deterministic order-8 subgroup gives a bounded lift of *every*
audited cut, for 48,555 clauses across all six shards.

[`n324_benders_orbit_lift.py`](n324_benders_orbit_lift.py) transforms both the
Allowed table and the dual witness `y' = T^-T y`.
[`n324_verify_orbit_lift.py`](n324_verify_orbit_lift.py) independently
re-enumerates the full residual group, checks the selected subgroup, recomputes
every Allowed table and cut from its serialized witness, verifies direct-cut
coverage, and proves subgroup closure byte-for-byte.  Five lifted shards still
returned SAT necessary assignments with inconsistent C systems; the sixth
timed out and supplies no conclusion.  The five SAT models were not related to
their direct counterparts by the selected subgroup and shared only one to
three of nineteen termwise B values, so orbit lifting does change basin
diversity.  Solve time was mixed and sometimes much worse, so this remains an
optional diversity pass rather than the default.

```sh
python3 n324_benders_orbit_lift.py WORK cuts.opb witnesses.jsonl lift.json \
  --missing 1 2 --fixed-b 1 --generator-count 2 --max-cuts 10000
python3 n324_verify_orbit_lift.py lift.json
```

Run the regression boundary checks with:

```sh
python3 test_n324_benders.py -v
```

They include a planted consistent C system, for which witness extraction must
refuse; exact 48-row/576-row equivalence checks; affine-witness checks; and an
inconsistent source whose emitted clause is checked to be violated exactly on
its recorded Cartesian Allowed region.  Audit an archive and construct a
solver-ready instance with:

```sh
python3 n324_verify_benders_archive.py BASE.opb OCCURRENCE.table WORK \
  WORK/manifest.json --missing 1 2 --fixed-b 1 \
  --checked-instance WORK/checked.opb
```

## Quotient-rank closure of the rank-19 residual

Write each now-forced rank-one pair as

```text
A_t = x_t tensor y_t,       B_t = p_t tensor z_t.
```

After reordering coordinates,

```text
A_t tensor B_t = (x_t tensor z_t) tensor (y_t tensor p_t)
                in Q tensor R,
dim Q = 12, dim R = 4.
```

The twelve matrix-multiplication target slices span
`K = Q tensor <I_2>`.  Quotient `R` by `<I_2>` and let `pi` denote the induced
map on `Q tensor R`.  In a hypothetical rank-19 decomposition the nineteen
columns `A_t tensor B_t` are independent.  Indeed, if a nonempty set `D` of
them summed to zero, choose `t0` in `D`, replace every
`C_t` for `t in D - {t0}` by `C_t + C_t0`, and remove term `t0`.  This leaves
the tensor unchanged and gives at most eighteen terms, contradicting the
already checked lower bound 19.

Thus their span `S` has dimension 19.  Exactness puts all twelve target slices
in `S`, so `K` is a subspace of `S` and

```text
rank pi(S) = dim S - dim(S intersect K) = 19 - 12 = 7.
```

For rank-one `A_t,B_t`, the quotient column is the explicit 36-bit vector

```text
(x_t tensor z_t) tensor pi(y_t tensor p_t).
```

[`n324_quotient_rank_opb.py`](n324_quotient_rank_opb.py) appends the exact
condition `rank(V) <= 7` to each necessary-B instance.  It factors the selected
36-by-19 matrix as `V = U L`, with seven columns in `U`.  The seven rows of
`L` are forced into reduced row-echelon form to remove the `GL(7,2)` gauge.
This is equisatisfiable with rank at most seven: one direction is immediate;
in the other direction, extend the row space of any rank-`r <= 7` matrix to a
seven-dimensional subspace, take its unique RREF basis as `L`, and express the
rows of `V` through it to obtain `U`.  Reordering columns before choosing the
RREF gauge preserves satisfiability.  The two hard `(1,8)` cases use the
fixed canonical term first; this changes only that gauge order.

The six formulas each have 7,529 variables and 86,487 constraints.  They use
the untouched necessary-B bases, not experimental Gaussian-Benders clauses.
RoundingSat 2 at commit `d4edbf7` proved every formula UNSAT.  All unchecked
deletion commands were removed from the proof logs; retaining constraints is
sound.  VeriPB 3.0.2 then replayed each log with
`--force-checked-deletion`, without a warning or error.

| Missing A | Fixed B | RREF order | Proof bytes | Result |
|---|---:|---|---:|---|
| `(1,2)` | 1 | natural | 159,429,598 | verified UNSAT |
| `(1,2)` | 17 | natural | 27,613,854 | verified UNSAT |
| `(1,4)` | 1 | natural | 359,919,856 | verified UNSAT |
| `(1,4)` | 16 | natural | 362,935,753 | verified UNSAT |
| `(1,8)` | 1 | canonical first | 254,909,338 | verified UNSAT |
| `(1,8)` | 17 | canonical first | 83,396,029 | verified UNSAT |

[`n324_quotient_rank_manifest.json`](n324_quotient_rank_manifest.json) records
every formula/proof hash and the pinned solver/checker hashes.
[`n324_verify_quotient_proofs.py`](n324_verify_quotient_proofs.py) regenerates
the six OPBs byte-for-byte, checks the three missing-A by two fixed-B orbit
cover, rejects proof logs containing unchecked deletions, reruns VeriPB, and
rewrites the manifest.  The independent planted audit exercises ranks zero
through seven as SAT and rank eight as UNSAT under two column orders:

```sh
python3 n324_quotient_encoding_audit.py --solver /path/to/roundingsat
python3 test_n324_quotient_rank.py -v
python3 n324_verify_quotient_proofs.py OCCURRENCE.table ARTIFACTS \
  n324_quotient_rank_manifest.json \
  --solver /path/to/roundingsat --veripb /path/to/veripb
```

The same quotient geometry gives useful lazy cuts.  Any eight independent
selected quotient columns yield an eight-term nogood.  The stronger
dual-triangular form chooses functionals `ell_i(c_j) = delta_ij` and, for an
ordering of the eight terms, allows every candidate whose earlier evaluations
are zero and diagonal evaluation is one.  Each Cartesian box remains
independent, so its single PB inequality is sound.  In the measured archive,
one such cut commonly excluded between 75 million and 537 million complete
eight-coordinate choices.  These cuts were useful experimentally but are not
needed by the six final proofs.

## Root dependency profile

With the published lower bounds, the sound multiset-orbit traversal had these
open frontiers:

| Depth | Open orbit states |
|---:|---:|
| 1 | 2 |
| 2 | 10 |
| 3 | 77 |
| 4 | 708 |
| 5 | 6,347 |
| 6 | 45,168 |
| 7 | 225,721 |
| 8 | 719,036 |

At depth eight there were 3,224,003 unique nonduplicate child orbits. Of the
719,036 open states, improving orbit 29 from 18 to 19 closes 718,733. The
remaining 303 depend on orbit 28, but orbit 28 has a known rank-18
decomposition and therefore cannot be improved.

After inserting the now-proved orbit-29 increment, the open root frontiers are:

```text
depth:  1  2  3  4   5    6    7    8    9   10
open:   1  3  9 21  48  105  190  303  420  488
```

The substitution/capacity inequalities alone cannot close the root. Their
maximum open size is 19; one checked witness is:

```text
2 4 5 8 10 12 15 16 17 20 21 32 34 40 42 48 51 60 63
```

## Reduction of the global rank-19 question

Assume for contradiction that `<3,2,4>` has a 19-term decomposition.

1. A rank-two first factor is impossible: its one occurrence plus the proved
   orbit-29 lower bound 19 gives the root target 20.
2. A repeated rank-one first factor is impossible: two occurrences plus the
   exact orbit-28 lower bound 18 gives 20.
3. Therefore the 19 first factors are distinct elements of the 21 rank-one
   `3x2` matrices.
4. The two missing rank-one points have exactly three orbits under
   `GL(3,2) x GL(2,2)`, represented by `(1,2)`, `(1,4)`, and `(1,8)`.

This reduces rank 19 to three fixed-A bilinear systems.  The older generic-B
normalization below remains a useful independent fallback; the rank-one-B
lemma above gives the smaller current residual.

There is still a `GL(4,2)` action on the shared four-dimensional index. The
stabilizer of each missing pair supplies additional `GL(3,2) x GL(2,2)`
symmetry. Fixing the most symmetric retained A factor gives:

| Missing A pair | Fixed A | Point stabilizer | Canonical `(B,C)` pairs |
|---|---:|---:|---:|
| `(1,2)` | 3 | 48 | 48 |
| `(1,4)` | 5 | 16 | 80 |
| `(1,8)` | 15 | 8 | 98 |

The four possible nonzero `2x4` B normal forms collapse to three cases per
missing pair under the residual action. Thus there are nine aggregate XNF
instances. Fully fixing C produces 48 + 80 + 98 = 226 disjoint proof shards.

Generate them and verify their checked-in hashes with:

```sh
python3 fixed_a_shards.py /tmp/n324-shards --mode all
(cd /tmp/n324-shards && shasum -a 256 -c /path/to/residual_shards.sha256)
```

[`residual_shards.sha256`](residual_shards.sha256) contains the nine aggregate
and 226 split-instance hashes. [`summary.json`](summary.json) records the
finite-geometry witnesses and current claim status in machine-readable form.

Every shard encodes nonzero B and C factors, AND Tseitin variables, and all 576
native XOR coefficient equations for Wang's `<3,2,4>` orientation. A SAT shard
would be a rank-19 decomposition and must be decoded and checked directly. A
global lower-bound claim requires UNSAT for every shard, proof elaboration and
checking for every result, plus an independent manifest-level coverage audit.
