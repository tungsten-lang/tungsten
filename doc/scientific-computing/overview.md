# Scientific computing

Flat under `core/` (no `core/sci/` namespace):

| Module | Role |
|--------|------|
| `tensor.w` | multi-D dense — **CPU** `Tensor.zeros([m,n])` + Metal path |
| `linalg.w` | dense LA (nested lists) + BLAS |
| `sparse.w` | **SparseMatrix** CSR/COO; SpMV + Apple Sparse Solvers (QR/Cholesky) |
| `fft.w` | pure radix-2 DFT |
| `special.w` / `stats.w` | specials + distributions |
| `solve.w` / `optim.w` / `interpolate.w` | ODE / opt / interp |
| `autodiff.w` | Dual + Tape |
| `blas.w` | Accelerate BLAS1/2/3 + vDSP |
| `mlx.w` | MLX GPU opt-in: GEMM + elementwise + reduce + softmax + FFT + RNG |
| `plot.w` | **Plot** sparklines |
| `io.w` | SciIO — CSV/FITS/Zarr/MAT/**TH5** (not full HDF5); no system lib deps |
| `cuda.w` | CUDA host surface |

**Tensor** = language multi-D type. **WTensor** = C struct header (like WArray).
**TH5C/TH5D** = Tungsten native “HDF5-signature + simple body” — not full HDF5.

## Quick checks (prefer **compiled** `-o` for sci specs)

```
bin/tungsten -o /tmp/tcpu spec/sci/tensor_cpu_spec.w && /tmp/tcpu     # TENSOR_CPU_OK
bin/tungsten -o /tmp/tunit spec/sci/tensor_unit_spec.w && /tmp/tunit   # TENSOR_UNIT_OK
bin/tungsten -o /tmp/spmv spec/sci/sparse_accel_spec.w && /tmp/spmv    # SPARSE_ACCEL_OK
bin/tungsten -o /tmp/ssol spec/sci/sparse_solve_spec.w && /tmp/ssol    # SPARSE_SOLVE_OK
bin/tungsten -o /tmp/wt   spec/sci/wtensor_spec.w && /tmp/wt            # WTENSOR_OK
bin/tungsten -o /tmp/wts  spec/sci/wtensor_slice_spec.w && /tmp/wts     # WTENSOR_SLICE_OK
bin/tungsten -o /tmp/ion  spec/sci/io_native_spec.w && /tmp/ion         # IO_NATIVE_OK
bin/tungsten -o /tmp/fmts spec/sci/formats_spec.w && /tmp/fmts          # FORMATS_OK
bash benchmarks/mlx/smoke_ops.sh                                       # MLX_OPS_OK (needs mlx-c)
```

Link gating (stage-1 rebuild): `@w_sparse_` → SparseBLAS+Solvers, `@w_tensor_` → tensor_bridge, `@w_sci_` → sci_io_native, `@w_blas_` → blas_bridge.

Large multi-module programs can hit a compiler SSA name-clash (`t0`); keep specs focused.

Docs: `tensor-vs-array.md`, `wtensor.md`, `sparse.md`, `io.md` (TH5 honesty), `units.md`.
