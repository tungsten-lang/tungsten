# Release stacktrace-metadata compaction

## Static footprint

A read-only census of `/tmp/tungsten-audit.wire` for
`compiler/tungsten.w` found 2,149 functions, 37,611 blocks, and 224,764
instructions. There were 137 `call_loc_set_col` instructions in 137 blocks,
leaving 224,627 retained instructions. Only 274 retained instructions appeared
after a location hook and therefore needed to move during stable compaction.

A retained release LLVM artifact had 36,559 blocks, and its matching debug
artifact had 138 emitted location hooks. The WIRE census is therefore a close
pre-pass proxy: the old algorithm allocates roughly 36.5--37.6 thousand
replacement arrays and pushes roughly 224.6 thousand survivors per release
self-host.

## Correctness fixture

`spec/compiler/strip_stacktrace_metadata_spec.w` passed in both compiled and
interpreter modes. Its 23 assertions cover instruction-array identity,
survivor identity and order, metadata clearing, unrelated-field preservation,
leading/trailing/consecutive/all-marker blocks, empty and marker-free blocks,
and a second idempotent pass.

## V1: eager read/write indices (rejected)

V1 compacted each existing instruction array in place but incremented both a
read and write index for every retained instruction, including all 224,627
survivors in the 37,474 marker-free blocks.

Two isolated roots were copied from the same dirty working tree. The baseline
snapshot restored only the original allocate-and-push implementation; the
candidate kept V1. Each root built a release `tungsten-compiler`. The balanced
runner invoked both executables on the exact same candidate-tree
`compiler/tungsten.w` payload with `--release --emit-ll --verbose`, wrapping
each process in `/usr/bin/time -lp`.

| Pair | Total baseline | Total V1 | Ratio | Wall baseline | Wall V1 | Ratio | User baseline | User V1 | Ratio |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2.661 | 2.711 | 1.019 | 7.820 | 9.060 | 1.159 | 7.390 | 8.290 | 1.122 |
| 2 | 2.671 | 2.820 | 1.056 | 8.510 | 8.620 | 1.013 | 7.970 | 8.070 | 1.013 |
| 3 | 3.336 | 2.581 | 0.774 | 8.940 | 7.810 | 0.874 | 8.210 | 7.420 | 0.904 |
| 4 | 3.004 | 2.755 | 0.917 | 8.630 | 8.870 | 1.028 | 8.050 | 8.270 | 1.027 |
| 5 | 3.230 | 3.025 | 0.937 | 9.500 | 11.710 | 1.233 | 7.990 | 8.470 | 1.060 |
| 6 | 3.421 | 3.534 | 1.033 | 9.350 | 11.160 | 1.194 | 8.260 | 8.570 | 1.038 |
| 7 | 2.519 | 2.613 | 1.037 | 8.000 | 8.750 | 1.094 | 7.510 | 8.180 | 1.089 |
| 8 | 3.118 | 2.878 | 0.923 | 8.480 | 8.950 | 1.055 | 8.020 | 8.350 | 1.041 |
| 9 | 2.718 | 2.881 | 1.060 | 8.120 | 9.050 | 1.115 | 7.620 | 8.520 | 1.118 |
| 10 | 2.909 | 2.739 | 0.942 | 8.840 | 9.280 | 1.050 | 8.260 | 8.630 | 1.045 |

| Metric | Baseline median | V1 median | Paired-ratio median | V1 pair wins |
|---|---:|---:|---:|---:|
| Compiler total | 2.957 s | 2.788 s | 0.980 | 5/10 |
| Real wall | 8.570 s | 9.000 s | 1.075 | 1/10 |
| User CPU | 8.005 s | 8.320 s | 1.043 | 1/10 |

The excluded warmup pair and all ten measured pairs emitted byte-identical
LLVM. V1 nevertheless failed the gate: compiler total missed the required
0.97 ratio, while wall and user CPU showed repeatable regressions. No
independent V1 repeat is warranted.

## V2: lazy compaction (rejected)

V2 performs the normal metadata-clearing scan with only `read_index` until it
finds the first location hook. Marker-free blocks return from that scan without
ever creating or incrementing `write_index`. Only a marker-bearing block enters
the second compaction loop, shifts later survivors, and pops the removed tail.

V2 was built from a fresh pair of snapshots and fresh release compiler
executables; no V1 candidate binary was reused. The same focused fixture passed
in compiled and interpreter modes before the campaign.

| Pair | Total baseline | Total V2 | Ratio | Wall baseline | Wall V2 | Ratio | User baseline | User V2 | Ratio |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2.906 | 2.823 | 0.971438 | 11.23 | 10.92 | 0.972395 | 8.41 | 8.61 | 1.02378 |
| 2 | 2.806 | 3.066 | 1.09266 | 9.96 | 10.39 | 1.04317 | 8.58 | 8.66 | 1.00932 |
| 3 | 3.027 | 2.953 | 0.975553 | 9.88 | 8.97 | 0.907895 | 8.72 | 7.90 | 0.905963 |
| 4 | 3.333 | 3.094 | 0.928293 | 9.90 | 10.42 | 1.05253 | 8.70 | 8.73 | 1.00345 |
| 5 | 3.064 | 2.736 | 0.892950 | 9.00 | 9.46 | 1.05111 | 8.14 | 8.57 | 1.05283 |
| 6 | 2.955 | 2.653 | 0.897800 | 9.21 | 9.54 | 1.03583 | 8.49 | 8.66 | 1.02002 |
| 7 | 2.783 | 2.856 | 1.02623 | 8.00 | 8.90 | 1.11250 | 7.56 | 8.30 | 1.09788 |
| 8 | 2.636 | 2.999 | 1.13771 | 8.09 | 9.14 | 1.12979 | 7.62 | 8.40 | 1.10236 |
| 9 | 2.839 | 2.551 | 0.898556 | 9.21 | 8.80 | 0.955483 | 8.54 | 8.21 | 0.961358 |
| 10 | 2.408 | 2.772 | 1.15116 | 7.89 | 8.94 | 1.13308 | 7.55 | 8.32 | 1.10199 |

| Metric | Baseline median | V2 median | Paired-ratio median | V2 pair wins |
|---|---:|---:|---:|---:|
| Compiler total | 2.873 s | 2.840 s | 0.973 | 6/10 |
| Real wall | 9.210 s | 9.300 s | 1.047 | 3/10 |
| User CPU | 8.450 s | 8.485 s | 1.022 | 2/10 |

The excluded warmup and all ten measured LLVM pairs were byte-identical. V2
still failed the gate: compiler total narrowly missed 0.97, and both wall and
user CPU regressed. The shared compiler therefore retains the original
allocate-and-push implementation; no independent V2 repeat is warranted.
