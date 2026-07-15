# Exact rank-three residual repair for `<2,2,5>`

## Purpose

A unit-floor worm state has seventeen nonzero terms `S` and exact residual
`G = T + S` of Hamming weight one.  Replacing three old terms by at most three
new terms closes the rank-17 scheme precisely when

```text
y1 + y2 + y3 = G + xi + xj + xk.
```

[`flipfleet_rect_three_term_repair.w`](flipfleet_rect_three_term_repair.w)
recognizes the tensor rank of the right side whenever it is at most three and
materializes a decomposition.  The recognizer and the corpus scanner are pure
Tungsten.  This is an offline exact audit; it does not alter the production
kernel pool, rectangular profile, or TUI.

## Complete recognizer

Let `d` be the dimension of the carrier's U-flattening slice space.  Tensor
rank is at least `d`, so `d > 3` rejects immediately.  The remaining cases are
complete over GF(2):

- `d=1`: the carrier is one U factor times a V-by-W matrix.  Row-space
  elimination factors that matrix at rank zero through three.
- `d=2`, repeated U factor: among the three bases
  `(A,B)`, `(A,A+B)`, and `(B,A+B)`, one coordinate matrix has rank at most
  two and the other has rank one.  All three choices are tested.
- `d=2`, three distinct U factors: they must be
  `alpha,beta,alpha+beta`.  Therefore `A=X+Z` and `B=Y+Z` for rank-one
  matrices `X,Y,Z`.  If either coordinate matrix has rank two, every possible
  `Z` is one of the nine outer products formed from its three nonzero column-
  space vectors and three nonzero row-space vectors.  If an input has rank
  one, the exact shared-left/shared-right enumeration has 2,044 candidates for
  the 10-by-10 matrices used here.  Every proposed `Z`, `A+Z`, and `B+Z` is
  rank-one gated.
- `d=3`: the seven nonzero combinations of three slice matrices are factored
  once.  All 168 ordered GL(3,2) bases are then tested; tensor rank three is
  equivalent to one basis containing three rank-one matrices.  U factors are
  recovered by the inverse basis coordinates, solved directly over the eight
  possible coefficient words.

No heuristic or candidate cap appears in these cases.  Returned terms are
rebuilt into the original carrier before a caller may use them.

## Validation

[`flipfleet_rect_three_term_repair_test.w`](flipfleet_rect_three_term_repair_test.w)
contains planted controls for matrix-rank-three `d=1`, both `d=2` relation
types, a nontrivial `d=3` basis change, a `d=3` space whose full 168 bases
reject, and a flattening-rank-four rejection.  It also removes three terms
from the real exact d84 scheme, recognizes their carrier, reinserts the
returned terms, and independently passes the complete `FFBCScheme` tensor
reconstruction.

The regression additionally supplies an exhaustive independent oracle on the
entire 4-by-2-by-2 tensor space.  It enumerates all 135 nonzero rank-one
tensors, marks every sum of zero through three distinct terms, and compares
the recognizer on all 65,536 carriers.  Every positive decomposition rebuilds
exactly and every negative carrier rejects.

Build the validation and corpus scan with:

```sh
bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_rect_three_term_repair_test.w \
  -o /tmp/ff-rect-three-term-repair-test
/tmp/ff-rect-three-term-repair-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_rect_three_term_repair_bench.w \
  -o /tmp/ff-rect-three-term-repair-bench
/tmp/ff-rect-three-term-repair-bench \
  /tmp/flipfleet_225_floor_manifest.tsv
```

## Complete saved-floor audit

The input manifest came from the matched 72-million-proposal d84 and d88
worms documented in [`RESIDUAL_WORM_225.md`](RESIDUAL_WORM_225.md).  Its
SHA-256 is
`999c001f8a7fb6b0e63eacb6db6d73e2997493e6fc8b574ce2a77b34735c7045`.
The scanner reparses every state, checks all factor bounds, reconstructs all
400 tensor coefficients, verifies the declared residual cell, and recomputes
the manifest term hash.

The manifest contains 633 serialized entries.  Hash-prefiltered, full
51-factor comparison finds 77 repeated entries across deletion archives,
leaving 556 distinct ordered term lists.  Every one of their `C(17,3)=680`
old-term triples was tested:

| measurement | result |
|---|---:|
| serialized entries validated | 633 |
| exact duplicate entries | 77 |
| unique unit-floor states | 556 |
| unique state/triple carriers | 378,080 |
| U-flattening dimension 0 / 1 | 0 / 0 |
| U-flattening dimension 2 | 15,461 |
| U-flattening dimension 3 | 209,602 |
| U-flattening dimension at least 4 | 153,017 |
| two-dimensional basis choices | 46,383 |
| GL(3,2) bases tested | 35,213,136 |
| weight-three `Z` candidates tested | 32,463 |
| rank-at-most-three carriers | **0** |
| exact rank-17 children | **0** |
| recognizer, rebuild, or gate failures | 0 |
| release/LTO scan time on this host | 433 ms |

A deliberately redundant scan of all 633 serialized entries also tested all
430,440 triples and returned zero, agreeing with the deduplicated result.
The deduplicated transcript SHA-256 is
`3ed361d7686e0d9f85e097df8d17ffaf0043f418e195756da0940d58f2ffd1be`.

Because no carrier was recognized, there was no real child to materialize or
publish; the benchmark's planted real-scheme test nevertheless exercises the
independent FFBC admission boundary.  This is a useful complete negative for
three-old-term repair on the saved floor corpus, but it supplies no reward
signal for production scheduling.  A next repair must correlate at least four
old terms, change the residual before closing it, or generate a genuinely new
unit-floor component.
