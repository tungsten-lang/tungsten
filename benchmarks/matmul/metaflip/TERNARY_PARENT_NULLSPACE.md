# Signed two-parent nullspace splicing

This experiment asks whether two exact strict-ternary matrix-multiplication
schemes hide proper signed subrelations, rather than only the tautological
whole-parent difference.  It found a large, exact family of rank-neutral
splices, but no rank drop.  The continuation evidence supports using the move
at archive cadence for diversity, not as a default hot-loop move.

## Exact representation and admission boundary

A strict ternary term is stored as six masks

```
U+ U- V+ V- W+ W-
```

with disjoint positive/negative supports.  `U` and `V` are gauge-canonical
(leading coefficient positive), while `W` carries the total term sign.  Two
terms are equal only when all six masks are equal.  Negation swaps `W+` and
`W-`; it is not legal to erase the sign while hashing or deduplicating.

For exact parents `A` and `B`, the audit removes collision-free common signed
terms and forms the reduced column relation

```
A_remaining + (-B_remaining) = 0.
```

Every imported archive is independently integer-gated, gauge-canonical, and
free of duplicate signed terms.  A candidate proper relation must pass a full
integer coefficient reconstruction before it can be materialized.  The
materializer replaces the selected `A` columns by the corresponding selected
`B` columns, cancels only exact opposite signed tensors, and runs the normal
strict-ternary exhaustive verifier.

## Why the modular screen is proof-safe

Let `M` be the integer matrix whose columns are the reduced signed rank-one
tensors.  For deterministic diagonal coordinate weights `D_q`, the audit
forms, modulo a prime,

```
G_q = M^T D_q M.
```

Every row of every `G_q` lies in the row space of `M`.  The rank of vertically
stacked `G_q` matrices is therefore a lower bound on `rank(M)`, never a
probabilistic upper estimate.  No column hashes are used.  The audit uses 12
fixed polynomial weight profiles independently modulo 1,000,003 and
1,000,033.

The all-ones vector is known to be in `ker(M)`.  Thus a screened rank of
`columns-1` proves that the whole-parent difference is the only rational
relation.  When the screen leaves nullity `k`, the audit integer-gates `k`
independent binary basis relations.  In every positive case below those basis
supports are disjoint and cover the entire reduced union.  Consequently:

- their `2^k` subset unions are all exact integer relations;
- the exact nullity is at least `k`;
- the Gram lower bound makes the exact nullity at most `k`;
- hence this is the complete nullspace, not a sample;
- zero and the whole-parent relation are the only non-proper members, giving
  exactly `2^k-2` proper splices.

The combined parent term sets also contain no opposite pairs.  Materialized
rank is therefore exactly

```
parent rank - selected A terms + selected B terms.
```

Enumerating this formula over each complete relation cube proves that none of
the 6,228 proper splices drops rank.

## Bounded archive result

`flipfleet_ternary_parent_nullspace_local_audit.w` covers the closest local
lineages in the current 5x5, 6x6, and 7x7 strict-ternary archive.

| Pair | Reduced columns | Common terms | Gram rank | Exact nullity | Proper exact splices | Rank drops |
|---|---:|---:|---:|---:|---:|---:|
| 5x5 d1249 walk / d1245 GPU | 4 | 91 | 3 | 1 | 0 | 0 |
| 5x5 d1248 GL3 / d1245 GPU | 4 | 91 | 3 | 1 | 0 | 0 |
| 5x5 d1249 walk / d1248 GL3 | 6 | 90 | 5 | 1 | 0 | 0 |
| 5x5 d997 shear / d967 shear-GPU | 32 | 77 | 26 | 6 | 62 | 0 |
| 6x6 d1938 shear / d1931 shear-GPU | 12 | 147 | 9 | 3 | 6 | 0 |
| 6x6 d1931 shear-GPU / d1931 symmetry | 12 | 147 | 9 | 3 | 6 | 0 |
| 6x6 d1938 shear / d1931 symmetry | 16 | 145 | 12 | 4 | 14 | 0 |
| 6x6 Kauers / d2502 walk | 48 | 129 | 36 | 12 | 4,094 | 0 |
| 7x7 Dronperminov / d3069 door | 64 | 218 | 53 | 11 | 2,046 | 0 |
| **Total** | | | | | **6,228** | **0** |

Both primes produced the same rank in every pair.

## Continuation and basin-diversity evidence

The audit materializes one local basis splice and one maximally balanced
splice from every nontrivial cube, for 12 strict children.  Every child is a
different signed term multiset from both parents.  The broad representatives
have these exact left/right replacement distances:

- 5x5 union-32: `8/8` from each parent;
- 6x6 union-16: `4/4` from each parent;
- 6x6 union-48: `12/12` from each parent;
- 7x7 union-64: `16/16` from each parent.

At one million ordinary ternary walk steps per child:

- 0/12 reduced rank;
- 5/12 improved their own starting density;
- 0/12 beat the sparser of their two parents.

Notable near-misses were the balanced 6x6 union-48 child, which moved from
`d2534` to `d2508` versus parent `d2502`, and the balanced 7x7 child, which
moved from `d3017` to `d3002` versus the sparser parent `d2966`.  These are
genuinely new signed presentations, but this bounded test does not prove they
occupy disconnected flip-graph components.

The complete run (including 12 million continuation steps) took 9.46 seconds
and 6.9 MB peak RSS on the audit machine.  The proof scan without long
continuations took 0.63 seconds and 6.3 MB peak RSS.  As a control on audit
engineering, the first dense `n^6` coefficient-row elimination prototype was
terminated while still processing its first pair after 102 seconds at
66,246,048 KiB RSS; repeatedly reducing dependent full rows exposed a
pathological allocation/compute path.  The stacked Gram construction removes
that path while preserving a rigorous rank lower bound.  Separately, eagerly
materializing every proper child through the 6x6
union-48 pair constructed 4,182 verified schemes and required about 94
seconds before the 7x7 pair was stopped; the disjoint-cube certificate gives
the same exhaustive conclusion without that redundant work.

## Policy conclusion

Signed two-parent nullspace splicing is useful as an offline or low-frequency
archive-cadence escape:

1. choose nearby exact parents;
2. construct the collision-free signed reduced union;
3. recover and integer-gate a disjoint relation basis;
4. sample balanced combinations, not only single basis moves;
5. feed the resulting exact rank-neutral presentations to independent walks.

The 5/12 self-density response shows that the presentations are not inert,
but the 0/12 parent-best result is not enough evidence for default CPU or GPU
lanes.  Reconsider promotion only if a larger balanced-combination sample
beats its best parent or produces a rank drop.

## Reproduction

```sh
bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_parent_nullspace_test.w \
  -o /tmp/fftpns-test
/tmp/fftpns-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_ternary_parent_nullspace_local_audit.w \
  -o /tmp/fftpns-local
/tmp/fftpns-local
```

Representative certificates and improved continuation certificates are
written under `/tmp/ternary-parent-local-*`.
