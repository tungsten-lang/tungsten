# Cooperative SIMD-group flip walker

`flipgraph_gpu_simdgroup.w` assigns one decomposition to one 32-lane Apple
SIMDgroup.  It stripes partner, zero, touched-duplicate, density, and copy scans
over the lanes, preserving the scalar walker's rotated first-match semantics via
`simd_min`.  Every emitted result is exhaustively checked against every tensor
coefficient (15,625 cells for 5x5; 46,656 for 6x6) before it is written.

The optional hash mode maintains three shared-memory collision-chain tables.
Ordinary flips update two links, split moves update four, and the table is
rebuilt only after rank-changing zero/duplicate cancellation.  Both modes use
the same RNG, schedule, buffers, and dispatch shape and produced byte-identical
results in the A/B below.

The Tungsten host accepts both rank-header bare dumps and the repository's
`R u v w` decomposition format.  This matters for the tracked 4x4 seed; an
early probe parsed its leading `R` as rank zero, and the exhaustive output gate
correctly refused to write a candidate.  The dual-format parser now has a real
4x4 Metal smoke (`rank 47, density 450, verify_full=1`).

## M5 Max measurements

Each row is 1,024 independent SIMDgroup trajectories, 100,000 moves per
dispatch, five dispatches: 512,000,000 attempted scheme steps.  `trajectory/s`
is the progress of one long search path, not aggregate lane operations.

| Size | Partner lookup | Time | Aggregate steps/s | Trajectory/s | Result |
|---|---:|---:|---:|---:|---:|
| 5x5 i32 | cooperative scan | 1.457 s | 351,407,000 | 343,170 | rank 93, d1155 |
| 5x5 i32 | hash chain | 2.185 s | 234,324,942 | 228,832 | rank 93, d1155 |
| 6x6 i64 | cooperative scan | 1.790 s | 286,033,519 | 279,329 | rank 153, d2508 |
| 6x6 i64 | hash chain | 1.634 s | 313,341,493 | 305,997 | rank 153, d2508 |

The scan is the clear 5x5 choice (50% more throughput than hash), while the
larger 6x6 rank makes the hash table worthwhile (9.5% more throughput).  This
is now the generator default: scan through 5x5, hash from 6x6 upward.  A
separate kernel per mode would also avoid reserving unused hash
memory in the 5x5 scan specialization.

The cooperative 6x6 run improved the tracked rank-153 frontier from density
2512 to 2508.  The exact asset is
`metaflip/matmul_6x6_rank153_d2508_gf2.txt`, SHA-256
`994ac8e19b5bf2104ef3294ee31c83606e65aaaff9b888b9bba3d9468a2f3209`.

## Reproduction

```sh
TUNGSTEN_LL_PATH=/tmp/fgsimd555.ll \
  bin/tungsten -o /tmp/fgsimd555 \
  benchmarks/matmul/flipgraph_gpu_simdgroup.w

/tmp/fgsimd555 \
  benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt \
  /tmp/fgsimd-scan5.txt 1024 100000 5 4 0

/tmp/fgsimd555 \
  benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt \
  /tmp/fgsimd-hash5.txt 1024 100000 5 4 1

python3 benchmarks/matmul/zoo/gpu_simdgroup_gen.py \
  6 168 /tmp/fgsimd666.w /tmp/fgsimd666.ll
TUNGSTEN_LL_PATH=/tmp/fgsimd666.ll \
  bin/tungsten -o /tmp/fgsimd666 /tmp/fgsimd666.w

/tmp/fgsimd666 \
  benchmarks/matmul/metaflip/matmul_6x6_rank153_d2512_gf2.txt \
  /tmp/fgsimd-scan6.txt 1024 100000 5 4 0

/tmp/fgsimd666 \
  benchmarks/matmul/metaflip/matmul_6x6_rank153_d2512_gf2.txt \
  /tmp/fgsimd-hash6.txt 1024 100000 5 4 1
```

Mode 0 is cooperative scan; mode 1 is the maintained hash chain.  The current
host counters are signed i32 and therefore intended for bounded dispatch sets
below roughly two billion attempted steps per trajectory.
