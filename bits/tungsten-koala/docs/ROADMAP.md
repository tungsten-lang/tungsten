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
| `transformer.w` | **Mostly shipped:** `PolynomialFeatures`, `ColumnSelector`, and the more capable parallel `ColumnTransformer` are Tunable, persistent Pipeline steps. `FunctionTransformer` remains. |
| `index.w` | **Port later** as simple row labels (Range/Array); no multi-index. |
| `resample.w` | **Port later** once time columns exist; ffill/bfill TODOs stay on the list. |

Moved originals live under `attic/drafts/` for archaeology only — not loaded.

## Work packages (order)

1. **Foundation** — Bitfile truth, attic drafts, docs, stale Persist specs.
2. **I/O** — CSV (string + File when compiled), JSON table via `tungsten-json` / core JSON.
3. **Contract honesty** — weighted Scaler/Imputer; unsupervised Pipeline tails; `supports_sample_weight?` accuracy.
4. **Sparse + matmul** — core SparseMatrix facade; BLAS-backed matmul.
5. **LinAlg** — rank-revealing QR, rank, thin SVD/Cholesky as pure follow-ons.
6. **Estimators** — multiclass logistic (shipped); KNN regressor + distance weights; feature selection; SVM; gradient boosting.
7. **Trees** — Gini/MSE feature importances; tree export; permutation importance (ablation).
8. **Calibration** — `CalibratedClassifierCV` (Platt / isotonic). **Shipped.**
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
  unfitted, refuses a partial mean when any fold fails, and preserves
  DataFrame schemas so categorical columns reach fold-local preprocessing.
- Pipeline stops on transformer fit/transform failure, invalidates itself
  after a failed re-fit, and passes y to supervised transformers such as
  `SelectKBest`.
- `PolynomialFeatures` shipped with degree, bias, interaction-only,
  feature names, tuning, Pipeline composition, and persistence.
- `LogisticRegression` now retains its binary sigmoid path while adding
  stable multinomial softmax, probability matrices / class columns, raw
  decision scores, multiclass log loss, weights, persistence, CV,
  Pipeline, and GridSearch support.
- `CalibratedClassifierCV` now cross-fits sigmoid/Platt or weighted
  isotonic calibrators around bare classifiers and preprocessing
  Pipelines; binary and multiclass probabilities, sample weights,
  GridSearch, custom splitters, calibration curves/ECE/MCE, and exact
  persistence are covered on both engines.
- `ColumnSelector` and sklearn-style `ColumnTransformer` now compose
  named numeric/categorical branches, nested transformer Pipelines,
  supervised and weighted transforms, drop/passthrough remainder policy,
  collision-safe feature names, nested tuning, GridSearch, CV,
  calibration, strict schemas, and exact persistence.
- `KNNClassifier` now supports uniform or inverse-Euclidean-distance
  voting, first-seen classes, full/per-class probabilities, calibration,
  nested tuning, and persistence. `KNeighborsRegressor` uses the same
  corrected distance rule and averages duplicate exact matches like
  sklearn.
- A live scikit-learn 1.9.0 differential now covers twenty-two numerical
  outcomes, three calibration-quality ratios, and two capability gains
  across
  nonlinear classification, polynomial regression, multiclass
  classification/probability scoring, a canonical Iris subset,
  heterogeneous preprocessing, held-out probability calibration, and
  clustering. The categorical branch improves mixed-data CV accuracy
  from 0.667 to 1.0 and distance-weighted KNN improves its reference
  accuracy from 0.5 to 1.0 in both implementations. On held-out Iris, Koala
  sigmoid/isotonic log loss is 0.353/0.251 against sklearn's 0.346/0.258;
  both cut the raw tree loss by over 86%.
- 17 interpreted and compiled spec suites cover 697 examples; the
  framework-free smoke test adds 405 checks on each engine.

## Highest-leverage next tranche

1. Broader sklearn differentials on standard tabular datasets plus
   wall-clock and memory baselines.
2. Gradient boosting and permutation importance before widening into GPU
   execution.
3. SVM classification and probability calibration.
4. A persistable named-operation alternative to arbitrary-closure
   `FunctionTransformer`.

## Compiler / runtime fixes koala depends on

See `docs/compiler-issues.md`. Until those land, koala keeps its workarounds
(no float literals, hoist `@` before blocks, assign-then-return for bare tails).

## Done when

- Specs green on **both** engines for every loaded module.
- Persist.loads round-trips every Estimable/Tunable with bit-identical predict.
- README + Bitfile match reality.
- No unported draft still sitting in `lib/` pretending to be API.
