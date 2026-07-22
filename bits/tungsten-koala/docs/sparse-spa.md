# Sparse matrix algebra (SPA) in Koala

See `doc/scientific-computing/sparse.md` in the Tungsten monorepo root.

Summary:

- **SPA lives in `core/sparse`** (`SparseMatrix`: CSR / COO, pure SpMV,
  Accelerate SparseBLAS when linked). Koala does **not** reimplement it.
- Koala's old `lib/sparse.w` draft (BSR/ELL/auto-format sketches) is in
  `attic/drafts/sparse.w` for archaeology only.
- **One-hot** is `lib/encoder.w` (`Encoder.new(:one_hot, …)`).
- DataFrame helpers (`DataFrame#to_sparse`, dense↔sparse) land as thin
  wrappers over `SparseMatrix.from_dense` / `.to_dense`.
- Future: CG / GMRES iterative solvers on CSR (core or koala, TBD).
