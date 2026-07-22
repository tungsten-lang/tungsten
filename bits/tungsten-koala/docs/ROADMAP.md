# Koala roadmap (approved 2026-07-22)

Approved program to grow `bits/tungsten-koala` into a complete tabular ML stack
on Tungsten, reusing **core** primitives instead of reinventing them.

## Architectural decisions

| Decision | Choice |
| --- | --- |
| Arrow | **Drop.** Bitfile claim was aspirational; storage stays ordered columns. |
| Dense multi-D / GPU | **Wire to `core/tensor`** (+ Metal faces). Delete koala's draft Tensor/GPU. |
| Sparse | **Use `core/sparse`** (`SparseMatrix` CSR/COO, SpMV, Accelerate). Thin koala facade only for DataFrame interop. |
| Dense matmul | Route large `Matrix.matmul` through **`core/blas`** (`dgemm`/`sgemm`) when compiled; pure path stays default for small / interpreter. |
| Measurement `core/calibration` | Unrelated (GUM/VIM units). ML calibration is **new** `CalibratedClassifierCV` in koala. |

## Draft cleanup

| Draft | Action |
| --- | --- |
| `estimator.w` | **Delete.** Superseded by `estimator_base.w`; sketch already shipped (lasso etc.). |
| `tensor.w`, `gpu.w`, `device.w` | **Delete.** Replaced by `core/tensor` + Metal; parallel Device invents a second world. |
| `sparse.w` | **Delete** as implementation; replace with thin re-export / DataFrame helpers over `core/sparse`. |
| `transformer.w` | **Keep ideas, port cleanly:** `ColumnSelector`, `FunctionTransformer`, `PolynomialFeatures` as Tunable steps in real Tungsten (no kwargs / `case =>`). |
| `index.w` | **Port later** as simple row labels (Range/Array); no multi-index. |
| `resample.w` | **Port later** once time columns exist; ffill/bfill TODOs stay on the list. |

Moved originals live under `attic/drafts/` for archaeology only — not loaded.

## Work packages (order)

1. **Foundation** — Bitfile truth, attic drafts, docs, stale Persist specs.
2. **I/O** — CSV (string + File when compiled), JSON table via `tungsten-json` / core JSON.
3. **Contract honesty** — weighted Scaler/Imputer; unsupervised Pipeline tails; `supports_sample_weight?` accuracy.
4. **Sparse + matmul** — core SparseMatrix facade; BLAS-backed matmul.
5. **LinAlg** — rank-revealing QR, rank, thin SVD/Cholesky as pure follow-ons.
6. **Estimators** — multiclass logistic; KNN regressor + distance weights; feature selection; SVM; gradient boosting.
7. **Trees** — Gini/MSE feature importances; tree export; permutation importance (ablation).
8. **Calibration** — `CalibratedClassifierCV` (Platt / isotonic).
9. **DataFrame parity** — multi-key group_by, value_counts, sort, drop_duplicates, melt, fillna, masks.
10. **Time series** — shift, lag, gap-aware resample.
11. **PG** — optional `DataFrame.from_sql` via `tungsten-pg`.
12. **Benchmarks** — sklearn differential + wall-clock suite.
13. **Parallel CV / GridSearch** + more examples.
14. **GPU path** — DataFrame/Matrix → `Tensor` for large ops (compiled-only).

## Compiler / runtime fixes koala depends on

See `docs/compiler-issues.md`. Until those land, koala keeps its workarounds
(no float literals, hoist `@` before blocks, assign-then-return for bare tails).

## Done when

- Specs green on **both** engines for every loaded module.
- Persist.loads round-trips every Estimable/Tunable with bit-identical predict.
- README + Bitfile match reality.
- No unported draft still sitting in `lib/` pretending to be API.
