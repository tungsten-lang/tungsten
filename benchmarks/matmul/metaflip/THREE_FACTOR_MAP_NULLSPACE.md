# Cubic three-factor map tunnel

## Identity and escape recipe

This move closes the raw-map seam left after the one- and two-factor audits.
Choose linear maps `A`, `B`, and `C` on the three factor spaces. For every
live rank-one term `t = u tensor v tensor w`, form the complete delta

```text
d(t) = t XOR (A u tensor B v tensor C w).
```

If a selected support `S` satisfies

```text
XOR(t in S) d(t) = 0,
```

then `XOR(S) = XOR((A tensor B tensor C)S)`, so replacing all selected terms
by their three-factor images is exact. This is the whole proof; the runtime
still reconstructs every coefficient of the complete matrix-multiplication
tensor before admitting an endpoint.

Writing `A=I+a`, `B=I+b`, and `C=I+c` shows why this is not one of the
previous raw-map workers. The delta has three linear terms, three bilinear
terms, and the cubic term

```text
a u tensor b v tensor c w.
```

The cubic term is absent from every one-factor row and cannot be recovered by
XORing the three two-factor rows. The executable plant is stronger than that
formal distinction: its selected five positions are not a dependency under
any of the three one-factor or three two-factor proper submaps.

The bounded recipe is:

1. choose elementary swap, shear, delete, or fold maps independently on
   `U`, `V`, and `W`, using high/low support coordinates;
2. pack each complete old-XOR-image delta into the exact `n^6` coefficient
   space and eliminate the full matrix;
3. reject a dependency when its selected term set is merely permuted by the
   product map;
4. atomically replace the remaining selected terms, omit zero images, and
   parity-cancel duplicate triples; and
5. rebuild and independently verify the complete tensor before scoring rank,
   density, or archive novelty.

`flipfleet_three_factor_map_nullspace.w` is the pure-Tungsten implementation.
The test uses the shear `h: bit1 ^= bit0`, which exchanges projective points
`1` and `3` and fixes `2`. The disjoint five-term sets

```text
S = {(1,1,1), (1,1,2), (1,2,1), (1,2,2), (3,1,1)}
h^3(S) = {(3,3,3), (3,3,2), (3,2,3), (3,2,2), (1,3,3)}
```

have the same tensor sum. Adding both sides to Strassen creates an exact
rank-17 shoulder; transforming only `S` creates five duplicate pairs and
returns to independently full-gated rank seven. Singular-map zero omission
has a separate regression.

## Real-frontier audit

The benchmark tests all `4^3 = 64` operation-family triples and eight
support-guided coordinate variants, hence 512 complete kernels per door. Two
structurally different archived doors were tested at each size from 3x3
through 7x7:

| tensor doors | kernels | delta rows | nullspace basis vectors | changed basis endpoints |
|---|---:|---:|---:|---:|
| 3x3 d139 / d159 | 1,024 | 23,552 | 8,505 | 0 |
| 4x4 d450 / d677 | 1,024 | 48,128 | 16,648 | 0 |
| 5x5 d968 / d1155 | 1,024 | 95,232 | 48,023 | 0 |
| 6x6 d1860 / d2502 | 1,024 | 156,672 | 85,874 | 0 |
| 7x7 d3098 / d3554 | 1,024 | 252,928 | 176,711 | 0 |
| **total** | **5,120** | **576,512** | **335,761** | **0** |

There were zero algebraic-relation failures and zero gate failures. Every
basis vector selected a term set already invariant under its product map.
That closes the complete kernel for each tested plan, not just the printed
basis: invariant selected sets are closed under symmetric difference, so any
XOR of invariant basis vectors is invariant as well.

The 3x3--6x6 pass took 0.93 wall seconds and peaked at 14.0 MB. Individual
6x6 doors sustained 1,450--1,651 complete kernels/second (221,915--252,696
term rows/second). The two 7x7 doors took 1.66 wall seconds together, peaked
at 18.6 MB, and sustained 591--690 kernels/second. These timings include
scheme loading and full source gates; no candidate admission work was needed.

## Disposition

Keep the operator and planted rank-drop regression as an offline audit, but
allocate no CPU or GPU pool share. The complete sampled kernels produced no
changed real endpoint, so more lanes would only enumerate set permutations.
Revisit only when a structurally new archive appears or when a non-elementary,
support-derived product map supplies a reason to expect a kernel outside the
invariant-set subspace. This change does not touch the TUI.

## Reproduce

```sh
bin/tungsten -o /tmp/ff3m-test \
  benchmarks/matmul/metaflip/flipfleet_three_factor_map_nullspace_test.w \
  --release --native --fast --lto
/tmp/ff3m-test

bin/tungsten -o /tmp/ff3m-bench \
  benchmarks/matmul/metaflip/flipfleet_three_factor_map_nullspace_bench.w \
  --release --native --fast --lto
/tmp/ff3m-bench 0 8
/tmp/ff3m-bench 7 8
```
