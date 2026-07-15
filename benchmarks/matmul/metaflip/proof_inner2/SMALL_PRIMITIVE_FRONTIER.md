# Small primitive GF(2) matrix-multiplication frontier

## Three newly closed cases

Complete finite-geometry certificates and exact local schemes now close three
of the one-point gaps exposed by the initial audit:

```text
R_GF(2)(<2,2,3>) = 11.
R_GF(2)(<2,2,4>) = 14.
R_GF(2)(<2,3,3>) = 15.
```

The `<2,2,3>` and `<2,2,4>` certificates each cover all 11
constrained-subspace orbits of a four-dimensional first factor, distributed
as `1,2,5,2,1` in dimensions `4,3,2,1,0`.  The `<2,3,3>` certificate covers
all 31 orbits of its six-dimensional constrained factor, distributed as
`1,2,7,11,7,2,1` in dimensions `6,5,4,3,2,1,0`.  Wang's unchanged verifier at
pinned upstream commit `efd22070269157e65aaf8d61a21da253a4000c61`
reconstructs every flattening, forced-product, degenerate, and backtracking
proof and reports the three unconstrained lower bounds above.  These are
checked finite proofs, not search misses.

The checked artifacts are:

| artifact | SHA-256 |
|---|---|
| `cert_matrix_q02_n223_exact.pb.txt` | `2c8ea187bfd5bdfe3a69d5e88c76009ef7c1783ad93a31bac99fb7c151321477` |
| decoded `cert_matrix_q02_n223_exact.btp.b64` | `0f86b4cb150bea6eace55abc4cc51be2bc985e69814a2b0c2401ac50dd65ba29` |
| `<2,2,3>` rank-11 exact scheme | `0dd21d5506d6e8cacc2bcf063a360584aea9293458efd77db1a2e0cdd126fcb2` |
| `cert_matrix_q02_n224_exact.pb.txt` | `64099bb1cdd9d4de350e559432647dda6d8341ca6c6678ad083b21febbc5e28e` |
| decoded `cert_matrix_q02_n224_exact.btp.b64` | `e3b19f1139d4216ba0918af71dc6741d26d65eae5458efd4263673b95bbebb83` |
| `<2,2,4>` rank-14 exact scheme | `db2154465d292400f254ae76bd54fee9dd1177f252083192715c8d785269d63b` |
| `cert_matrix_q02_n233_exact.pb.txt` | `a25c9c5698378d930589211dc6332aef40b04924934b2f71eb286ca594c386db` |
| decoded `cert_matrix_q02_n233_exact.btp.b64` | `30e2c870d17db4abe78997acc63f207195976145d35bb5a61216a6e0fec7a1b8` |
| `<2,3,3>` rank-15 exact scheme | `03d3957d466e75e42a629462ac112942358e0fdff63d46396da2ed313646d301` |

Replay the structural/hash audit locally:

```sh
python3 proof_inner2/n223_verify_wang.py --audit-only
python3 proof_inner2/n224_verify_wang.py --audit-only
python3 proof_inner2/n233_verify_wang.py --audit-only
```

Replay the proof with a pinned upstream checkout (the script rebuilds the
verifier with the exact `<2,2,3>` compile-time dimensions):

```sh
python3 proof_inner2/n223_verify_wang.py \
  --upstream /path/to/tensor-rank-lower-bound
python3 proof_inner2/n224_verify_wang.py \
  --upstream /path/to/tensor-rank-lower-bound
python3 proof_inner2/n233_verify_wang.py \
  --upstream /path/to/tensor-rank-lower-bound
```

## A new lower bound for `<2,2,5>`

The adjacent case is not closed, but its rigorous interval is now one unit
narrower:

```text
17 <= R_GF(2)(<2,2,5>) <= 18.
```

The same 11-orbit cover is enough. The default forced-product cap of `2^24`
skips one `2^25` enumeration and leaves the root at 16. Raising only that cap
to 25 proves a dimension-two child orbit at rank 15; the existing degenerate
and backtracking steps then prove the unconstrained root at 17. Search took
about 9.2 seconds and unchanged-verifier replay about 7.8 seconds on the M5
Max host. The checked artifacts are
`cert_matrix_q02_n225_lb17.pb.txt` (SHA-256
`b3e389f0006cac583e309a77c2c5600065d540a3d4e4c3022973a6ca89c6d9bb`)
and the decoded `cert_matrix_q02_n225_lb17.btp.b64` archive (SHA-256
`eb7662a537d4e347a7a91218b36d2dc51b707a20c341a91fd1519f3dd1a6d52a`).
Replay it with:

```sh
python3 proof_inner2/n225_verify_wang.py --audit-only
python3 proof_inner2/n225_verify_wang.py \
  --upstream /path/to/tensor-rank-lower-bound
```

The current Wang recursion cannot close the remaining unit. Its decisive
dimension-one child (constraint `0001`) has both a checked lower bound 15 and
an explicit 15-term decomposition, so it is exact; an artificial lift of
that child is precisely what would make the root derive 18. Exhaustive cap-25
forced-product and unlimited root-backtracking reruns cannot evade this
structural wall. [`N225_RANK18_CAMPAIGN.md`](N225_RANK18_CAMPAIGN.md) records
the diagnosis and the complete 43-shard direct rank-17 proof/search campaign.

On the M5 Max host the clean three-binary upstream build took 86 seconds; a
dimension change then rebuilt the three main translation units in about six
seconds.  The `<2,2,3>`, `<2,2,4>`, and `<2,3,3>` proof searches took 0.05,
0.33, and 1.27 seconds respectively.  The largest used 166 MB maximum RSS,
and every verifier replay took less than 0.2 seconds.  A lean direct-rank XNF
probe for `<2,2,3>` was abandoned after 40 seconds because its unfinished
FRAT-XOR trace had already reached roughly 1 GB; the finite-geometry route is
decisively better for these targets.

## A checked lower bound for `<2,3,5>`

The adjacent six-dimensional first-factor case now has the rigorous interval

```text
23 <= R_GF(2)(<2,3,5>) <= 25.
```

The complete cap-25 Wang table reaches root 22, exactly the analytic bound,
with its rank-one and rank-two one-dimensional constraints at 20 and 21.
[`../proof_n235/`](../proof_n235/) adds the missing step.  A multiplicity-aware
capacity CNF over every quotient point raises the rank-two constraint to 22;
its XLRUP proof is accepted by the formally verified CakeML checker.  A
rank-22 global scheme would therefore use only rank-one first factors.  The
independent geometry audit then finds 21 lower-bound-20 subspaces, each
containing three of the 21 rank-one matrices and covering every such matrix
exactly three times.  Their occurrence inequalities sum to the impossible
`66 <= 42`.

The exact rank-25 upper endpoint is the checked mod-2 projection of the public
AlphaTensor scheme, materialized as
`matmul_2x3x5_rank25_d173_alphatensor_zt_mod2_gf2.txt`. Two pure-Tungsten
campaigns independently rediscovered zero-overlap rank-25 presentations at
densities 210 and 278, and a short continuation improved the public basin to
d170. The active d170/d210/d278 restart doors are pairwise disjoint. Both the
Python proof regression and a pure-Tungsten exact gate reconstruct every
coefficient. The earlier direct `3+2` rank-26 block composition remains useful
as replay provenance but is no longer the upper endpoint.

## Audited frontier

For sorted shapes `2 <= a <= b <= c <= 6`, the analytic column is the standard
Blaser bound

```text
ab + ac + bc - a - b - c + 1.
```

The upper column is the best exact GF(2) certificate currently present in
this directory.  A dash means this checkout has no standalone certificate for
that sorted shape; it does not assert that no decomposition is known.  Every
numeric upper endpoint points to a replayable local term list, including the
newly materialized `<2,2,4>`, `<2,2,5>`, `<2,2,6>`, and `<2,3,5>` block
compositions.  The gap is the unresolved gap after applying checked
lower-bound packages, so it can be smaller than `UB - analytic LB`.

| shape | analytic LB | local exact UB | gap | status / best next use |
|---|---:|---:|---:|---|
| `<2,2,2>` | 7 | 7 | 0 | closed (Strassen) |
| `<2,2,3>` | 10 | 11 | 0 | **closed at 11 by checked proof** |
| `<2,2,4>` | 13 | 14 | 0 | **closed at 14 by checked proof** |
| `<2,2,5>` | 16 | 18 | 1 | **checked lower bound 17; active five-door CPU/GPU frontier, exact d84 upper scheme** |
| `<2,2,6>` | 19 | 21 | 2 | active FlipFleet profile from the rank-21 three-Strassen-block composition |
| `<2,3,3>` | 14 | 15 | 0 | **closed at 15 by checked proof** |
| `<2,3,4>` | 18 | 20 | 0 | closed at 20 by `proof_n324/` |
| `<2,3,5>` | 22 | 25 | 2 | **checked lower bound 23 in `proof_n235/`; rank-25 d160 density leader plus three distinct alternate fleet doors; live target 24** |
| `<2,3,6>` | 26 | - | - | no standalone local certificate |
| `<2,4,4>` | 23 | 26 | 3 | active campaign; intentionally not duplicated here |
| `<2,4,5>` | 28 | 33 | 5 | 148-shard direct-rank campaign available |
| `<2,4,6>` | 33 | - | - | no standalone local certificate |
| `<2,5,5>` | 34 | - | - | no standalone local certificate |
| `<2,5,6>` | 40 | - | - | no standalone local certificate |
| `<2,6,6>` | 47 | - | - | no standalone local certificate |
| `<3,3,3>` | 19 | 23 | 4 | square methods dominate |
| `<3,3,4>` | 24 | 29 | 5 | rank-29 local scheme |
| `<3,3,5>` | 29 | 36 | 7 | rank-36 local scheme |
| `<3,3,6>` | 34 | 42 | 8 | rank-42 local scheme |
| `<3,4,4>` | 30 | 38 | 8 | rank-38 local scheme |
| `<3,4,5>` | 36 | 47 | 11 | rank-47 local scheme |
| `<3,4,6>` | 42 | 54 | 12 | rank-54 local scheme |
| `<3,5,5>` | 43 | 58 | 15 | rank-58 local scheme |
| `<3,5,6>` | 50 | 68 | 18 | rank-68 local scheme |
| `<3,6,6>` | 58 | 82 | 24 | rank-82 local scheme |
| `<4,4,4>` | 37 | 47 | 10 | rank-47 local scheme |
| `<4,4,5>` | 44 | 60 | 16 | rank-60 local scheme |
| `<4,4,6>` | 51 | 73 | 22 | rank-73 local scheme |
| `<4,5,5>` | 52 | 76 | 24 | rank-76 local scheme |
| `<4,5,6>` | 60 | 90 | 30 | rank-90 local scheme |
| `<4,6,6>` | 69 | 105 | 36 | rank-105 local scheme |
| `<5,5,5>` | 61 | 93 | 32 | rank-93 local scheme |
| `<5,5,6>` | 70 | 110 | 40 | rank-110 local scheme |
| `<5,6,6>` | 80 | 130 | 50 | rank-130 local scheme |
| `<6,6,6>` | 91 | 153 | 62 | rank-153 local scheme |

Splitting the five output columns of `<2,2,5>` as `3+2` gives the replayable
rank-18 composition from rank-11 and rank-7 leaves. The new checked lower
bound 17 leaves a single unresolved rank. The analogous `<2,2,6>` pass still
produces root 18, weaker than the analytic 19.  For `<2,3,5>`, the standalone
capacity/incidence proof in `proof_n235/` raises the finite-geometry root from
22 to 23 and the materialized `3+2` composition supplies rank 26. `<2,4,4>`
remains the next larger campaign with an existing standalone certificate, but
it is already being attacked separately and is not duplicated here.
