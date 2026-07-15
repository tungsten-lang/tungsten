# Projective-line matrix-pencil tunnel

Status: exact pure-Tungsten research operator, positive structural result on
5x5, **not scheduled**.  It found no rank or density record, and a matched
continuation showed that the new endpoints promptly rejoin the source basin.

## Identity

Choose one factor axis and a two-dimensional GF(2) subspace.  Its three
nonzero projective points are `a`, `b`, and `a+b`.  A maximal live subtotal on
that line can be grouped as

```text
a tensor A + b tensor B + (a+b) tensor C.
```

Using `(a,b)` as the line basis gives the two matrix slices

```text
X = A + C
Y = B + C.
```

Conversely, every decomposition whose first factors stay on this line is
specified by one complementary matrix `D`:

```text
A' = X + D
B' = Y + D
C' = D.
```

Its exact CP cost is therefore

```text
rank(X+D) + rank(Y+D) + rank(D).
```

`flipfleet_matrix_pencil.w` enumerates `D` and factors the three winning
matrices at minimal GF(2) matrix rank.  This couples all three factor buckets;
running Gaussian reduction independently on `A`, `B`, and `C` tests only the
single original choice `D=C`.

The search is complete inside the combined left/right factor spans.  This is
also complete among arbitrary ambient `D`: project an arbitrary candidate
onto those two spans.  The projection fixes `X` and `Y`, and applying linear
maps to a matrix cannot increase any of the three ranks.

Every materialized subtotal passes an exhaustive ambient local-tensor gate.
The splice helper applies GF(2) symmetric-difference semantics, reconstructs a
fresh worker state, and then checks all `n^6` matrix-multiplication
coefficients.  Hashes are not used for admission.

## Why this is new coverage

The complete span-refactor lane exhausts selected windows only through four
terms.  The pencil operator consumes the **maximal five-term line bucket** at
once.  The real 5x5 endpoints have term-set distances eight and ten; one
ordinary pair flip can change at most four terms.  The operation is also not
ordinary shared-factor reduction: all audited source line buckets already
have `rank(A)+rank(B)+rank(C)=5`.

The planted regression makes the distinction explicit.  Five terms with
colour-matrix ranks `1+2+2` encode one rank-one tensor.  Independent bucket
reduction leaves all five; the coupled `D` search returns one term.  The local
distance is six, and embedding that presentation into Strassen produces an
exact rank-11 shoulder that the operator returns to rank seven under a full
`2^6` coefficient gate.

## Exact archive audit

The regular path exhausts at most 20 coordinate cells.  For 25-cell (5x5)
pencils, the audit builds a complete 128 MiB `i32` matrix-rank table once and
then evaluates each `D` with three table reads.  Building all 33,554,432 ranks
took 2.034 seconds on the development machine.

| archive | maximal line bucket | k>=5 pencils | exhaustive result |
|---|---:|---:|---|
| 4x4 r49/d432 | 3 | 0 | no applicable window |
| 4x4 r47/d450 | 3 | 0 | no applicable window |
| 5x5 r93/d1155 | 5 | 3 | three changed rank-neutral optima; all full-gated; maximum distance 8 |
| 5x5 r93/d968 | 5 | 10 | three changed 20-cell optima, maximum distance 10; seven 25-cell optima unchanged |
| 6x6 r153/d2508 | 5 | 18 | all 603,979,776 `D` choices covered; no changed optimum |
| 6x6 r153/d1860 | 5 | 12 | all 402,653,184 `D` choices covered; no changed optimum |

The 25-cell run covered about 1.25 billion `D` evaluations across all six
archives.  It found zero exact-gate failures and zero rank drops; none of the
maximum-distance representatives selected from the six changed 5x5 lines
improved density.  Those endpoints are genuine neutral tunnels, not objective
wins.

## Matched continuation and scheduling decision

The farthest d1155 endpoint starts at rank 93, density 1163, term-set distance
eight.  It was compared against the original r93/d1155 presentation and a
serialized one-pair r93/d1158 restart.  Twelve fixed worker seeds received 25
million moves per arm, for 900 million total moves.

| arm | rank drops | final best | distinct final best sets | best updates |
|---|---:|---:|---:|---:|
| source | 0 | r93/d1155 in all 12 | 1 | 12 |
| pencil | 0 | r93/d1155 in all 12 | 1 | 72 |
| one-pair control | 0 | r93/d1155 in all 12 | 2 | 38 |

Every paired source/pencil result tied.  The six extra best updates per pencil
trial are the neutral endpoint unwinding back to the source objective, not new
fertility.  Therefore this operator remains an offline audit and regression;
it is **not** assigned a CPU lane and is not added to the GPU pool.

## Reproduction

From the repository root:

```sh
bin/tungsten -o /tmp/ff-matrix-pencil-test \
  benchmarks/matmul/metaflip/flipfleet_matrix_pencil_test.w \
  --release --native --lto
/tmp/ff-matrix-pencil-test

bin/tungsten -o /tmp/ff-matrix-pencil-bench \
  benchmarks/matmul/metaflip/flipfleet_matrix_pencil_bench.w \
  --release --native --lto
/tmp/ff-matrix-pencil-bench 20
/tmp/ff-matrix-pencil-bench 25

bin/tungsten -o /tmp/ff-matrix-pencil-continuation \
  benchmarks/matmul/metaflip/flipfleet_matrix_pencil_continuation_bench.w \
  --release --native --lto
/tmp/ff-matrix-pencil-continuation 12 25000000
```

The benchmark is CPU-only.  It does not launch Metal work, mutate campaign
files, or touch the TUI.
