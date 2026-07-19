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

df[:salary].rolling(2).mean          # => Series of trailing-window means
df.join(other, :dept)                # => inner join (:left for left join)
df.pivot(:dept, :name, :salary)      # => pivot table, agg defaults to :sum

Metrics.rmse([2, 4, 6], [1, 5, 7])   # => 1

v = Vector.new([1, 2, 3])
v.dot(Vector.new([4, 5, 6]))         # => 32
m = Matrix.new([[2, 1], [1, 3]])
m.matmul(Matrix.identity(2))         # => m
m.solve(Vector.new([5, 10]))         # => Vector [1, 3]
m.det                                # => 5 (0 = singular; nil = not square)
m.inv                                # => Matrix (nil when singular)
```

Live modules: `Series`, `DataFrame`, `GroupBy`, `Stats`, `Metrics`,
`Rolling`, `Join`, `Pivot` (constructors take ordered `[name, values]`
pairs — column order is preserved, which a hash would not guarantee),
plus dense linear algebra: `Vector`, `Matrix`, `LinAlg` (pure Tungsten,
CPU-only; ops with a shape requirement return nil when it is not met).

Verify with `bin/tungsten bits/tungsten-koala/spec/koala_spec.w` and
`spec/linalg_spec.w` (the tungsten-spec suites) or `spec/smoke.w`
(framework-free) — all pass interpreted and compiled.

The remaining files under `lib/` (tensor, pipelines, encoders, ...) are
unported design drafts and are not loaded by `use koala` yet (see the
list in `lib/koala.w`).
