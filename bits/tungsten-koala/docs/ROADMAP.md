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
| `transformer.w` | **Partly shipped:** `PolynomialFeatures` is now a Tunable, persistent Pipeline step with sklearn-compatible ordering. `ColumnSelector` / `FunctionTransformer` remain. |
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

## Verified progress (2026-07-25)

- Correctness boundaries now reject empty/misaligned metric inputs, mixed
  numeric columns, out-of-range percentiles, ragged table operations, and
  invalid rolling/join/pivot contracts with nil rather than a crash or a
  misleading score.
- Cross-validation fits a fresh clone per fold, leaves its prototype
  unfitted, and refuses a partial mean when any fold fails.
- Pipeline stops on transformer fit/transform failure, invalidates itself
  after a failed re-fit, and passes y to supervised transformers such as
  `SelectKBest`.
- `PolynomialFeatures` shipped with degree, bias, interaction-only,
  feature names, tuning, Pipeline composition, and persistence.
- A live scikit-learn 1.9.0 differential now covers five outcomes across
  nonlinear classification, polynomial regression, multiclass
  classification, and clustering; all five agree (within the last float
  digit for silhouette).
- 14 interpreted and compiled spec suites cover 623 examples; the
  framework-free smoke test adds 376 checks on each engine.

## Highest-leverage next tranche

1. Multiclass logistic regression with stable softmax and `predict_proba`.
2. Probability calibration (`CalibratedClassifierCV`) and calibration
   curves, measured by log loss and Brier score.
3. `ColumnSelector` / `FunctionTransformer`, then mixed numeric/categorical
   column pipelines.
4. Broader sklearn differentials on standard tabular datasets plus
   wall-clock and memory baselines.
5. Gradient boosting and permutation importance before widening into GPU
   execution.

## Compiler / runtime fixes koala depends on

See `docs/compiler-issues.md`. Until those land, koala keeps its workarounds
(no float literals, hoist `@` before blocks, assign-then-return for bare tails).

## Done when

- Specs green on **both** engines for every loaded module.
- Persist.loads round-trips every Estimable/Tunable with bit-identical predict.
- README + Bitfile match reality.
- No unported draft still sitting in `lib/` pretending to be API.
