# Full-column affine decoder for `<2,2,5>`

## Claim boundary

This is an exact search inside one finite rank-one-term dictionary. It has not
found a rank-17 scheme and does not prove that the dictionary is rank-17-free.
The global checked interval remains

```text
17 <= R_GF(2)(<2,2,5>) <= 18.
```

The fixed dictionary is the union of the five production rank-18 doors and
the 32-parent maximin block-local archive. It has 625 unique terms. Their
400-bit tensor columns have rank 212 and nullity 413.

## Why this is not the old even-parent affine lane

The prior odd-parent affine descent generated zero only by XORing even-rank
exact parents. Every such generator has even cardinality, so that lane cannot
change rank parity and cannot reach rank 17.

[`flipfleet_225_affine_decoder_lib.w`](flipfleet_225_affine_decoder_lib.w)
instead computes the **complete tensor-column kernel** of the 625 columns. Its
systematic basis has 184 odd-weight rows among 413, so it does not have the
even-parent obstruction. Every GPU move is an actual 400-coefficient
tensor-zero relation. A GPU result of weight at most 18 is reconstructed as a
scheme and passed through the independent full tensor gate before it can be
written.

## Three complementary decoders

### Complete coefficient shells

The CPU exhausts the anchor plus every single and pair of basis rows. The GPU
then exhausts every sorted triple. A regular `413^3` launch avoids uploading a
large tuple table; only the `a<b<c` sixth performs the ten-word SWAR popcount.
A two-pass minimum/winner protocol prevents a racy weight/index publication.

On the checked-in archive:

```text
single/pair candidates       85,491
sorted triple candidates     11,655,686
regular GPU threads          70,444,997
minimum rank                 18
rank-17 results              0
gate failures                0
```

The CPU pair shell takes 0--1 ms. Warm device passes take roughly 9--22 ms
for both triple kernels together; the first cold measurement took 41 ms.

### Sparse-relation rank-band walk

The natural systematic basis is unusually useful as a move alphabet:

```text
basis row weight             min 4, max 82, average 36.668
pair-XOR relation weight <=4 88
                         <=6 183
                         <=8 724
                        <=12 1,424
                        <=16 2,333
```

The default experimental pool contains all 413 basis rows and all 2,333
pair-XOR relations of weight at most 16. Each Metal lane starts from one of 37
independently exact rank-18 archive masks. Equal and downhill moves are always
accepted; small uphill moves are temperature-gated but may not cross the rank
band. Stalled lanes rotate origins. Exactness is therefore invariant even
during an uphill escape.

Eight matched 2.048-billion-proposal arms varied bands 22--28 and pair caps
8--24. Together they tested 16.384 billion moves at 1.30--1.58 billion
proposals/s. None reached rank 17. The walker did, however, reach rank-18
words at distance 36 from the lane's home origin and distance 22 from every
one of the 37 supplied origins. This is real same-rank basin tunnelling, not a
rank improvement. Four 100-million-move ordinary FlipFleet continuations from
representative endpoints found no rank drop; one improved density 94 to 93,
still behind the production d84 door. The decoder therefore remains offline.

### Random information-set restarts

For every restart, the host randomly permutes the 625 columns, rebuilds a
systematic kernel basis, maps it back to stable dictionary coordinates, and
derives the unique affine solution supported only on the 212 pivot columns.
That is the Prange origin. CPU radius zero through two plus the GPU radius-
three shell around this origin is the Lee--Brickell `p=3` decoder. Centering
the shell on the systematic solution is essential; centering it on a known
rank-18 word is merely a small coefficient walk and is not information-set
decoding.

Completed independent sweeps are:

| restarts | exact affine candidates | elapsed | best | gated rank-18 returns |
|---:|---:|---:|---:|---:|
| 1,024 | 12,022,966,272 | 7.696 s | 18 | 38 |
| 8,192 | 96,183,730,176 | 48.116 s | 18 | 270 |
| 16,384 | 192,367,460,352 | 83.924 s | 18 | 573 |
| 32,768 | 384,734,920,704 | 166.055 s | 18 | 1,120 |

The combined **685,309,077,504** candidates produced 2,001 independently
gated rank-18 returns, no rank 17, and no relation or exact-gate failure.
Large warm sweeps sustained 2.0--2.32 billion affine candidates/s. Their
minimum Prange-only word had weight 19; allowing one, two, or three free
coordinates repeatedly recovered exact weight 18.

This complements rather than replaces SAT. The exact XOR plus `<=17`
CryptoMiniSat instance remained indeterminate after 300 CPU seconds and about
2.34 million conflicts. The GPU decoder evaluates far more structured
candidate words per second, but a completed bounded shell is not an UNSAT
certificate and candidate counts are not comparable to SAT conflicts.

## Correctness and replay

[`flipfleet_225_affine_decoder_test.w`](flipfleet_225_affine_decoder_test.w)
checks all 413 natural basis rows as exact tensor-zero relations, pins the
dictionary rank/nullity and sparse-pool counts, verifies all 37 origins, and
materializes a random Prange solution through the full tensor gate. Its device
controls include a planted affine-code rank drop and a triple-only planted
drop, which jointly exercise the rank-band state update, SWAR popcount, and
two-pass winner protocol. The generated Metal sidecar also compiles to AIR and
a metallib with the installed standalone Metal toolchain.

```sh
TUNGSTEN_METAL_PATH=benchmarks/matmul/metaflip/rect_gpu/affine_decoder_225.metal \
  bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_225_affine_decoder_test.w \
  --out /tmp/ff225-affine-test

/tmp/ff225-affine-test \
  benchmarks/matmul/metaflip/rect_gpu/affine_decoder_225.metal

TUNGSTEN_METAL_PATH=/tmp/ff225-affine.metal \
  bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_225_affine_decoder_bench.w \
  --out /tmp/ff225-affine-bench

# metal lanes steps band pair-cap output nonce reset-steps ISD-restarts
/tmp/ff225-affine-bench /tmp/ff225-affine.metal \
  64 100 24 16 /tmp/ff225-affine-best.txt 119001 128 8192
```

No TUI, native-fleet policy, or default GPU-pool allocation is changed by
this experiment. A production allocation would be justified by a rank-17 hit
or by demonstrated downstream objective reward from its distant rank-18
endpoints; neither has occurred yet.
