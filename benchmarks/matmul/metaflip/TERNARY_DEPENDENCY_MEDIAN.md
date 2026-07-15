# Signed dependency-median audit

## Exact integer identity

Write five selected rank-one terms along one tensor axis as

```text
f_i tensor M_i,                  M_i = l_i tensor r_i.
```

The strict-ternary analogue of the GF(2) five-bucket move is not an XOR
circuit. It requires an actual integer unit relation

```text
sum_i s_i f_i = 0,              s_i in {-1,+1}.
```

For either `delta` sign and any strict rank-one complementary matrix
`D = y tensor z`, replace every selected slice by

```text
M_i' = M_i + delta*s_i*D.
```

Then

```text
sum_i f_i tensor M_i'
  = sum_i f_i tensor M_i
    + delta * (sum_i s_i f_i) tensor D
  = sum_i f_i tensor M_i.
```

This proof is over the integers. No support projection or mod-2 inference is
used.

The endpoint remains in the strict `{-1,0,1}` alphabet. If `l_i = a*y` for
`a` in `{-1,+1}`, the builder first tries

```text
l_i tensor r_i + c*y tensor z
  = l_i tensor (r_i + c*a*z),    c = delta*s_i.
```

It emits that one-term form only when the vector sum is nonzero and strict.
The symmetric shared-right-factor formula is handled the same way. Otherwise
the always-valid two-term form is retained. Exact opposite rank-one terms are
cancelled globally after the replacement. Every selected result is then
loaded through `fft_init_terms`, which performs the complete `n^6` integer
matrix-multiplication reconstruction.

The implemented scope is deliberately the unit-coefficient case. A general
rational five-circuit can have coefficients other than `+/-1`; after primitive
integer scaling, a coefficient of magnitude greater than one cannot be one
strict rank-one term. Repeating that term is exact but incurs a different,
usually much larger rank-debt problem. It is not silently treated as this
median move.

## Complete unit-relation enumeration

`flipfleet_ternary_dependency_median.w` avoids an `R^5` scan:

1. For every pair of terms, it records both signed sums up to overall sign.
2. For every triple, it tests all four signed sums up to overall sign.
3. Two deterministic modular linear hashes select chained pair buckets.
4. Every hash collision is compared at every signed vector coordinate.
5. The recovered five coefficients are checked again over the integers, and
   relations with a zero proper subsum using those coefficients are rejected.

The two hashes can create extra collision work but cannot discard an equal
pair/triple sum. `circuit_cap=0` is therefore complete for the stated signed
unit relations. The proper-subsum test is not a broader claim that each proper
subset is linearly independent over Q with arbitrary coefficients; that
stronger condition is unnecessary for exactness.

## Regression

`flipfleet_ternary_dependency_median_test.w` contains four independent
guards:

- a planted unit relation whose five strict slices refactor to four, checked
  coefficient by coefficient over the local integer tensor;
- exhaustive signed pair/triple discovery counts equal a direct 16-sign brute
  force on the planted and negative tiny systems;
- a GF(2) five-circuit (`1 xor 3 xor 5 xor 9 xor 14 = 0`) that has no signed
  unit relation and is correctly rejected;
- the planted equality added as a zero relation to Laderman, producing an
  exact rank-32 shoulder that the move returns to rank 23. Both shoulder and
  recovered matrix-multiplication schemes pass the full integer gate.

## Real-frontier audit

The table reports complete `circuit_cap=0` searches. `qualified` counts exact
algebraic endpoints whose five-slice rank debt is at most two; only the best
endpoint is made durable, full-gated, and measured for term-set distance.

| seed | unit relations | qualified | best gated endpoint | source distance | search time |
|---|---:|---:|---:|---:|---:|
| 4x4 r49/d432 | 515 | 0 | none within +2 | - | 5 ms |
| 4x4 r49/d432, debt +8 | 515 | 25,750 | r52/d442 | 7 | 35 ms |
| 5x5 r93/d967 | 1,835 | 814 | r95/d973 | 6 | 25 ms |
| 5x5 r93/d997 | 1,756 | 1,240 | r94/d1001 | 7 | 22 ms |
| 6x6 r153/d1931, original | 4,578 | 1,210 | r155/d1939 | 6 | 121 ms |
| 6x6 r153/d1931, symmetry escape | 4,540 | 1,296 | r155/d1939 | 6 | 124 ms |
| 7x7 r250/d2966 | 5,995 | 1,262 | r251/d2982 | 7 | 554 ms |
| 7x7 r250/d3069 door | 5,446 | 1,177 | r251/d3060 | 7 | 555 ms |

The other five default 5x5 presentations and nine additional 6x6 archive
presentations were also exhaustively scanned. Their ranges were 1,563--1,803
unit relations and 938--1,240 qualified shoulders at 5x5, and 3,634--4,710
relations and 996--3,256 shoulders at 6x6. Their best endpoints had rank debt
+1 or +2. Across the entire audited default/archive set there was no
rank-neutral endpoint and no rank drop.

## Matched continuation

The best median shoulder was compared with an ordinary exact split shoulder
at the same starting rank. Both arms retained the untouched parent as their
durable best and used identical walk seeds. The controlled runs comprised 168
million aggregate ordinary moves:

| source | trials x moves/arm | median vs split | objective result |
|---|---:|---:|---|
| 4x4 d432 | 12 x 1M | 0 / 0, 12 ties | no rank/density win |
| 5x5 d967 | 12 x 1M | 0 / 0, 12 ties | no rank/density win |
| 5x5 d997 | 12 x 1M | 6 / 6 | both improved the parent; neither beat d967 |
| 6x6 d1931, two basins | 24 x 1M | 0 / 0, 24 ties | no rank/density win |
| 7x7 d2966 | 12 x 1M | 0 / 0, 12 ties | no rank/density win |
| 7x7 d3069 door | 12 x 1M | 4 / 8 | both improved the door; neither beat d2966 |

On the d3069 door the median and split bests ended at average term-set
distances 62 and 60 from the parent. Thus the signed median does create a
slightly different live route, but the split arm won eight of twelve objective
comparisons. That is diversity evidence, not value evidence.

The measured policy is therefore **offline only**. The move is sound, fast,
and reaches exact changed shoulders, but it does not receive a production CPU
cadence or GPU-pool lane until it beats the existing split control on an
objective or produces a rank-neutral endpoint.

## Reproduction

```sh
bin/tungsten compile benchmarks/matmul/metaflip/flipfleet_ternary_dependency_median_test.w \
  --out /tmp/flipfleet-ternary-dependency-median-test --release --fast --lto
/tmp/flipfleet-ternary-dependency-median-test

bin/tungsten compile benchmarks/matmul/metaflip/flipfleet_ternary_dependency_median_bench.w \
  --out /tmp/flipfleet-ternary-dependency-median-bench --release --fast --lto

/tmp/flipfleet-ternary-dependency-median-bench \
  benchmarks/matmul/metaflip/matmul_7x7_rank250_d3069_ternary_door.txt \
  7 0 2 1000000 12
```

No Tungsten syntax or compiler extension was required.
