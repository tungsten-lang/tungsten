# Sparse benchmarks

`iterative_solve.w` times portable conjugate gradient on an `n` by `n` 1-D
Dirichlet Laplacian with `3n-2` stored entries. Construction and validation are
outside the timed region. The exact solution is all ones, so the benchmark
reports both the residual and maximum solution error.

```sh
bin/tungsten -o /tmp/sparse_iter benchmarks/sparse/iterative_solve.w
/tmp/sparse_iter 10000 jacobi
/tmp/sparse_iter 10000 ichol0
```

This is a regression benchmark for the non-densifying Core path. It is not a
claim of parity with SciPy or Julia sparse kernels. Canonical public CSR remains
ordinary Tungsten storage; each solve makes an O(rows + nnz) typed `i64`/`f64`
copy. The timed region includes that copy and all preconditioner construction,
but excludes matrix construction and validation.

Measured on Apple M5 Max, Darwin arm64, 2026-08-03, native build. Five-run
medians are reported at n=1,000; n=5,000 is one run because the boxed baseline
alone takes about 18 seconds.

| implementation | n | nnz | iterations | elapsed | residual | max error |
|---|---:|---:|---:|---:|---:|---:|
| boxed CSR/workspace + Jacobi baseline | 1,000 | 2,998 | 500 | 718 ms | 3.78e-12 | 6.91e-14 |
| typed solve-local CSR/workspace + Jacobi | 1,000 | 2,998 | 500 | 9 ms | 3.82e-13 | 3.44e-14 |
| typed solve-local CSR/workspace + IC(0) | 1,000 | 2,998 | 1 | 6 ms | 6.35e-15 | 5.42e-13 |
| boxed CSR/workspace + Jacobi baseline | 5,000 | 14,998 | 2,500 | 18,100 ms | 5.89e-11 | 5.27e-13 |
| typed solve-local CSR/workspace + Jacobi | 5,000 | 14,998 | 2,500 | 241 ms | 5.23e-12 | 1.79e-13 |
| typed solve-local CSR/workspace + IC(0) | 5,000 | 14,998 | 1 | 30 ms | 1.30e-14 | 4.10e-12 |

The typed Jacobi candidate is 79.8x faster at n=1,000 and 75.1x at n=5,000
without changing iteration count or tolerance. IC(0) is exact for this
tridiagonal pattern, so its one-iteration result is useful regression evidence,
not a claim about general sparse systems. The maximum solution error grows to
4.10e-12 at n=5,000 under IC(0), while the residual remains 1.30e-14 and the
requested 1e-8 relative tolerance is comfortably met.
