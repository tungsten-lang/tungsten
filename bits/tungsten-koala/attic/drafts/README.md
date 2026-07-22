# Unported design drafts (not loaded)

These files do **not** parse as modern dual-engine Tungsten (kwargs,
`case X => Type`, `**options`, class vars, etc.) and are **not** in
`lib/koala.w`. Kept only as design notes.

| File | Fate |
| --- | --- |
| `estimator.w` | Superseded by `lib/estimator_base.w` + concrete estimators. |
| `tensor.w` / `gpu.w` / `device.w` | Use `core/tensor` + Metal; do not reimplement. |
| `sparse.w` | Use `core/sparse` (`SparseMatrix`); koala may add DataFrame helpers only. |
| `transformer.w` | Ideas for ColumnSelector / PolynomialFeatures — re-port when needed. |
| `index.w` / `resample.w` | Future DataFrame labels / time-series. |

See `docs/ROADMAP.md`.
