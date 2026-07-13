# Native cooperative SIMD-group bundle

These are checked-in, dimension-specialized Tungsten/Metal workers for the
cooperative FlipFleet GPU lane. A native campaign selects them through
`flipfleet_simd_bundle.w`; Python is not invoked while the fleet is running.

| Tensor | CAP | trajectories per hardware lane group | mask | lookup | threadgroup memory |
|---|---:|---:|---:|---|---:|
| 3x3 | 40 | 1 per 32 lanes | i32 | cooperative scan | 4,312 B |
| 4x4 | 80 | 1 per 32 lanes | i32 | cooperative scan | 5,272 B |
| 5x5 | 144 | 1 per 32 lanes | i32 | cooperative scan | 6,808 B |
| 6x6 | 232 | 1 per 32 lanes | i64 | maintained hash | 14,800 B |
| 7x7 | 360 | 1 per 32 lanes | i64 | maintained hash | 19,408 B |

CAP holds the naive decomposition plus at least twelve excursion terms. The
mode split is measured: striped partner scans win through 5x5, while maintained
factor hash chains win at 6x6 and 7x7. The two wider workers use native i64
factor masks; 7x7 additionally keeps decimal parsing and Metal transfers on raw
i64 views so bit 48 cannot cross the boxed-integer path.

Every scheduler epoch has a finite dispatch count. At the end of the epoch the
Tungsten host rejects zero, out-of-range, or duplicate terms, reconstructs every
tensor coordinate over GF(2), and writes the candidate only if that exhaustive
gate succeeds. `SIMDGROUP_RESULT ... verify_full=1` is the machine-readable
adoption signal.

Historically, the 6x6 hash worker moved the rank-153 density frontier from 2512
to 2508 (2,319 no-CSE operations).  That exact asset remains tracked with its
cooperative-SIMD attribution.  The later pure-Tungsten mixed CPU fleet reached
density 2502 (2,313 operations), which is now the default cost leader; this
does not diminish the SIMD result or change tensor rank.

The assets are regenerated deliberately at development time from
`benchmarks/matmul/zoo/gpu_simdgroup_gen.py`. For example:

```sh
python3 benchmarks/matmul/zoo/gpu_simdgroup_gen.py 6 232 \
  benchmarks/matmul/metaflip/simd_bundle/simdgroup_666.w \
  benchmarks/matmul/metaflip/simd_bundle/simdgroup_666.ll
```

Compile once with `TUNGSTEN_LL_PATH` set to a disposable build path. The
compiler refreshes the checked-in `.metal` path named by the generated source;
only `.w` and `.metal` are runtime inputs. Generated `.ll`, `.cu`, binaries,
and sidemaps remain build artifacts.
