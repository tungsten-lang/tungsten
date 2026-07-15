# Six-bucket projective-circuit move

`flipfleet_projective_circuit6.w` implements the next exact GF(2)
dependency-median move after the five-bucket circuit.  It is intentionally an
offline scout: the measured frontiers do not justify another hot CPU or GPU
pool lane.

## Identity and search

For a minimal six-factor dependency

```text
f0 ^ f1 ^ f2 ^ f3 ^ f4 ^ f5 = 0,
```

XORing the same rank-one matrix `D = y tensor z` into all six associated
matrix slices preserves the tensor:

```text
sum_i f_i tensor (M_i ^ D)
  = sum_i f_i tensor M_i ^ (sum_i f_i) tensor D
  = sum_i f_i tensor M_i.
```

Each live `M_i` is rank one.  The replacement `M_i ^ D` has rank zero, one,
or two and is factored explicitly.  Duplicate global terms cancel by XOR.
The implementation tries all 36 choices of `y` and `z` drawn from the six
selected complementary factors.  Their local debt is at most four; retaining
the full neighborhood is necessary because collisions with unselected terms
can reduce that debt.

A direct five-index scan would cost `O(r^5)`.  Instead, the worker stores
triple XORs in a chained hash table.  For sorted logical positions
`a<b<c<d<e<f`, the canonical split

```text
(a,b,c) | (d,e,f)
```

has equal triple XORs exactly when the six factors sum to zero.  Requiring
`c<d` reports every six-set once.  Independence of the first five factors is
then checked exhaustively; with the zero-sum relation this is equivalent to
minimality.  Dependency discovery is `O(r^3 + XOR matches)`; exact endpoint
construction then scores 36 medians per admitted circuit.  The complete
rank-247 audit used about 104 MB.  `triple_cap=0` is complete; a positive cap
bounds stored/scanned triples per axis.  `circuit_cap` bounds admitted minimal
circuits, and `nonce` rotates axes and logical labels for deterministic
archive coverage.

## Soundness tests

`flipfleet_projective_circuit6_test.w` covers:

- a planted minimal rank-five factor circuit with a `6 -> 5` endpoint;
- automatic discovery of that endpoint by triple matching;
- rejection of a nonminimal dependency and exact triple-cap accounting;
- an eleven-term zero relation embedded ahead of the exact 3x3 rank-23
  scheme, producing an independently verified rank-34 shoulder;
- bounded rediscovery of the planted circuit, restoration to rank 23, and a
  full `n^6` matrix-multiplication tensor gate.

The generic benchmark also full-gates its retained endpoint.  When an output
path is supplied it serializes, reparses, and gates the endpoint again.

```sh
bin/tungsten compile benchmarks/matmul/metaflip/flipfleet_projective_circuit6_test.w \
  --out /tmp/ffpc6-test --release --fast --lto
/tmp/ffpc6-test

bin/tungsten compile benchmarks/matmul/metaflip/flipfleet_projective_circuit6_bench.w \
  --out /tmp/ffpc6-bench --release --fast --lto
/tmp/ffpc6-bench SEED N TRIPLE_CAP CIRCUIT_CAP NONCE [OUTPUT]

bin/tungsten compile benchmarks/matmul/metaflip/flipfleet_projective_circuit6_continuation_bench.w \
  --out /tmp/ffpc6-cont --release --fast --lto
/tmp/ffpc6-cont 12 5000000
```

## Frontier audit

The current sparse leaders received complete all-axis searches.  Together
they contain 74,971 minimal six-circuits and generated 2,698,956 exact
endpoint occurrences.  Every retained best passed the full tensor gate;
representative endpoints were also serialized, reparsed, and gated.  No
rank-neutral or rank-lowering endpoint occurred.

| tensor | source | circuits | endpoints | best endpoint | distance | search | drops | neutral |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 4x4 | r47/d450 | 1,515 | 54,540 | r51/d460 | 8 | 64 ms | 0 | 0 |
| 5x5 | r93/d968 | 7,659 | 275,724 | r95/d984 | 8 | 1.16 s | 0 | 0 |
| 6x6 | r153/d1860 | 24,237 | 872,532 | r155/d1884 | 8 | 8.24 s | 0 | 0 |
| 7x7 | r247/d3098 | 41,560 | 1,496,160 | r249/d3109 | 10 | 32.18 s | 0 | 0 |

The result is not an artifact of unusually sparse leaders.  A second complete
audit used the d677, d1155, d2502, and d3554 doors.  It covered 74,011 minimal
circuits and 2,664,396 endpoint occurrences: 57,420 on 4x4, 256,716 on 5x5,
852,552 on 6x6, and 1,497,708 on 7x7.  Again there were zero neutral endpoints
and zero drops; best ranks were `+4,+2,+2,+2`.  Across both complete audits,
5,363,352 exact endpoint occurrences produced no neutral or lowering move.

## Matched continuation

The shallowest real result was the 5x5 rank-95/d984 endpoint at term-set
distance eight.  `flipfleet_projective_circuit6_continuation_bench.w`
compared it with two ordinary splits from the same leader using identical
worker seeds.  Twelve trials at five million moves per arm (120 million moves
total) gave:

```text
returns             12 / 12
rank wins            0 / 0
density wins         0 / 0
matched outcomes     5 / 6 / 1   (circuit / splits / ties)
descendant distance 16 / 13      (average from source)
```

The six-circuit shoulder does preserve somewhat more archive diversity, but
it did not convert that distance into rank or density reward and narrowly
lost the matched objective 5-6 with one tie.  Therefore it is retained as a
pure-Tungsten offline archive scout and regression, not integrated into the
default CPU/GPU pool.
Reconsider it if a new frontier yields a neutral endpoint, a `+1` shoulder,
or a positive matched-continuation reward.
