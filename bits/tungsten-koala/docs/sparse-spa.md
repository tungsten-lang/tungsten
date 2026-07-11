# Sparse matrix algebra (SPA) in Koala

See `doc/scientific-computing/sparse.md` in the Tungsten monorepo root.

Summary:

- **SPA lives here** (`lib/sparse.w`), not in `core/`
- Formats: COO / CSR / CSC / BSR / ELL + auto
- **One-hot** is `lib/encoder.w` (`Encoder.new(:one_hot, …)`), not SparseMatrix
- Future: CG / GMRES iterative solvers on CSR
