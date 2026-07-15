# Checked GF(2) lower bound for `<2,3,5>`

## Result and claim boundary

The artifacts in this directory prove

```text
R_GF(2)(<2,3,5>) >= 23.
```

This improves the standard Bläser lower bound 22 by one. A public rank-25
AlphaTensor `{−1,0,1}` construction remains exact after reduction modulo two,
so the resulting rigorous interval is

```text
23 <= R_GF(2)(<2,3,5>) <= 25.
```

The lower endpoint is a complete finite proof, not a search miss.  It combines
one verifier-accepted constrained-subspace certificate, one formally checked
CNF proof, and one independently audited incidence count.

## Proof outline

Orient the tensor so its first factor is the six-dimensional space of 2x3
matrices.  Wang's finite-geometry search has only 31 subspace orbits in this
orientation, distributed as

```text
1, 2, 7, 11, 7, 2, 1
```

in dimensions `6,5,4,3,2,1,0`.  With complete `2^25` forced-product passes,
the unchanged upstream verifier accepts root lower bound 22.  In particular,
the rank-one and rank-two one-dimensional constraint orbits have checked
bounds 20 and 21.

There are two cases for a hypothetical rank-22 decomposition.

1. **A rank-two first factor occurs.**  Quotient by its line `S`.  The other
   21 terms would decompose the tensor constrained by `S`.  The checked CNF
   encodes every possible multiset of 21 nonzero points in `F_2^6/S`.  For
   every one of the 374 subspaces `U` containing `S`, it imposes the necessary
   occurrence inequality

   ```text
   occurrences in U/S <= 21 - certified_lower_bound(U).
   ```

   Singleton inequalities permit 50 ordered occurrence slots over the 31
   quotient points, with capacity histogram `15x1 + 13x2 + 3x3`.  Requiring
   exactly 21 occurrences is UNSAT.  Thus the rank-two constrained orbit has
   rank at least 22, and a global rank-22 decomposition cannot contain a
   rank-two first factor.

2. **All first factors have rank one.**  There are 21 nonzero rank-one 2x3
   matrices over GF(2).  Independent orbit expansion finds 21 certified
   subspaces of lower bound 20, each meeting the rank-one variety in three
   points, with every rank-one point incident to exactly three selected
   subspaces.  In a rank-22 decomposition each selected subspace can contain
   at most `22-20=2` occurrences.  Summing the inequalities would require

   ```text
   3 * 22 <= 21 * 2,
   66 <= 42,
   ```

   a contradiction.

The two matrix ranks exhaust every nonzero 2x3 first factor, so rank 22 is
impossible.  The checked root bound already excludes smaller ranks.

## Why the same shortcut does not yet prove rank 24

The 21 incidence rows also rule out an all-rank-one first-factor list at
hypothetical rank 23: they would require `3*23 <= 21*(23-20)`, or `69 <= 63`.
Thus a rank-23 scheme, if one exists, must use at least one rank-two first
factor.  After fixing such a factor, the checked constrained bound leaves 22
other occurrences.  The direct generalization of the quotient-capacity CNF
is **satisfiable**, not contradictory.  Its compact witness is
`n235_rank2_multiset_r22_model.json` (SHA-256
`c2cb4d1203825fcdb4b688f6144b6d780bab53901b0d0f3e92084773fd546b52`):
22 occurrences on 20 quotient points satisfy all 374 inequalities for
subspaces containing the fixed line, with 28 inequalities tight.

That witness is deliberately pinned as a counterexample to the weaker proof
route.  The quotient model forgets which of the two ambient lifts `x` and
`x+S` each occurrence uses, omits the inequalities for subspaces not
containing `S`, and omits the remaining two tensor-factor equations.  A
stronger necessary system separates the lifts and enforces all 2,825 ambient
subspace inequalities.  It is an open proof probe, not a checked result;
rank 24 must not be claimed unless that stronger system is proved UNSAT with
a replayable certificate (or a different complete argument is supplied).

## Checked upper endpoint and provenance

`matmul_2x3x5_rank25_d173_alphatensor_zt_mod2_gf2.txt` is an independent
row-major-mask conversion of FastMatrixMultiplication's public
`schemes/known/alpha_tensor/2x3x5_m25_ZT.json`, reduced modulo two with the
source's column-major output factor transposed explicitly. The pinned source
checkout is `e0ec7db4cb7d7ca41abbb2c6e3bd8c7de75c7c64`; the source JSON SHA-256 is
`b1cf7a4f468cee8adee675aac1f7565140fd11cc1040bdea202a4f261eb18a74`.
This is a pre-existing rank-25 result, not a FlipFleet rank record.

During integration, two bounded pure-Tungsten campaigns independently
rediscovered rank 25 from the elementary rank-26 block seed. Their d210 and
d278 term lists share zero terms with each other or with the public d173
projection. A subsequent 62M-move continuation reduced the public basin to
d170 by one ordinary flip. A later five-island campaign reached d160 by
39.73B recorded moves. A separate one-move replay reconstructed it exactly
and reproduced the certificate byte for byte. The active restart doors are
therefore d160, d170, and the disjoint d210/d278 schemes; d173 remains pinned
public provenance. Python and pure-Tungsten reconstruction gates check every
coefficient and this term-distance structure. The live strict-improvement
target is rank 24.

## Pinned artifacts

| Artifact | SHA-256 |
|---|---|
| Wang text certificate | `71ecdab1fed0ef331757806b707ad844cac04f057368250a4ea7a5e3920cd2eb` |
| decoded Wang BTP archive | `0688a309bcd26c6ab746870eb6f5cbfb84444d243b01360d5782ee37c5d8439f` |
| multiset-capacity CNF | `453ba646318ff0d336afe7b338ef3dab0cf062bdf1e4ff1e0ce52436f1ec8e65` |
| checked XLRUP proof | `ccc860e7aa18a4754869375f0f6f4bc65e0bb1666b65b1ad6b94b7e50336340e` |
| rank-23 quotient-capacity SAT counterexample | `c2cb4d1203825fcdb4b688f6144b6d780bab53901b0d0f3e92084773fd546b52` |
| FlipFleet rank-25 d160 density leader | `48f567ce264b996cb6f1d9ce88296e1830b8a4261830ca3d03fc0a04b04e7be7` |
| FlipFleet rank-25 d170 public-basin bridge | `31abed1367f41e93a4d35f11cd295b05bc494394793714627d42fff2a26b31df` |
| public AlphaTensor mod-2 rank-25 scheme | `45f7b780775158cbcac4adaef9ba91c0d3010648c780218981873b11c868f182` |
| FlipFleet rank-25 d210 rediscovery | `7b6faf104b1bb0520ef3a266846b0ae087fb965628e1318e9c2a11a85a325613` |
| FlipFleet rank-25 d278 rediscovery | `8d6ea17a0c13686ffd282df65165bd54ce9178f2a7f4fdb2a2d59933dafb4cac` |

The Wang prover/verifier revision is
`efd22070269157e65aaf8d61a21da253a4000c61`.  The SAT run used
CryptoMiniSat 5.14.7.  FRAT-XOR revision
`855f3d0ae45fe37c3ad29e4a8ef56e62e1b5e4ad` elaborated the solver trace to
the checked-in XLRUP proof.  The final replay used the formally verified
CakeML `cake_xlrup` checker.

## Independent replay

The local audit hashes every artifact, transposes the certificate's 2x3
coordinates into an independent 3x2 implementation, expands all 31 orbits to
all 2,825 subspaces of `F_2^6`, regenerates the CNF byte for byte, and rebuilds
the 21-row incidence contradiction. It also independently reconstructs all
five rank-25 upper schemes: d160 shares three terms with d170 and d173,
d170/d173 share 23, and every pair involving d210 or d278 is disjoint:

```sh
cd benchmarks/matmul/metaflip/proof_n235
python3 n235_verify.py --audit-only
python3 test_n235_capacity.py -v
```

Replay the capacity proof with a native `cake_xlrup` binary or an executable
wrapper around it:

```sh
python3 n235_verify.py --checker /path/to/cake_xlrup
```

On Apple Silicon, the supplied CakeML assembly must run in a linux/amd64
container.  A wrapper should mount this checkout read-only and invoke the
x86-64 checker with the two paths it receives.

Replay both the capacity proof and the base finite-geometry certificate with
a pinned upstream checkout:

```sh
python3 n235_verify.py \
  --checker /path/to/cake_xlrup-or-wrapper \
  --upstream /path/to/tensor-rank-lower-bound
```

The verifier rebuild uses compile-time dimensions `N0=2,N1=3,N2=5`.  The
recorded M5 Max run took about 140 seconds to produce the cap-25 Wang
certificate and about 52 seconds to replay it.  The multiset CNF has 23,452
variables and 46,455 clauses; CryptoMiniSat reported UNSAT in 0.25 seconds,
FRAT-XOR elaborated it in 0.09 seconds, and CakeML replay took 0.29 seconds.
