# Tungsten Data

_**Think of koalas as a slightly friendlier version of python's pandas.**_

## Working today

```tungsten
use koala

df = DataFrame.new([
  [:name, ["Alice", "Bob", "Carol"]],
  [:dept, ["eng", "sales", "eng"]],
  [:salary, [80, 65, 95]]
])

df[:salary].mean                     # => 80.0
df.where -> (row) row[:salary] > 70  # => 2-row DataFrame
df.group_by(:dept).mean(:salary)     # => DataFrame [dept, salary]

Metrics.rmse([2, 4, 6], [1, 5, 7])   # => 1
```

Live modules: `Series`, `DataFrame`, `GroupBy`, `Stats`, `Metrics`
(constructors take ordered `[name, values]` pairs — column order is
preserved, which a hash would not guarantee).

Verify with `bin/tungsten bits/tungsten-koala/spec/smoke.w` — it passes
both interpreted and compiled.

The remaining files under `lib/` (matrix, linalg, tensor, pipelines,
encoders, io, ...) are unported design drafts and are not loaded by
`use koala` yet.
