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
df.describe                          # => summary frame: count/mean/std/min/25%/50%/75%/max
df[:salary].quantile(75)             # => 3rd-quartile salary (linear interp)

Metrics.rmse([2, 4, 6], [1, 5, 7])   # => 1
Metrics.f1([1, 1, 0], [1, 0, 0])     # => 0.666667 (also precision / recall)
Metrics.classification_report(preds, actual)  # multiclass P/R/F1 + macro/weighted avg

v = Vector.new([1, 2, 3])
v.dot(Vector.new([4, 5, 6]))         # => 32
m = Matrix.new([[2, 1], [1, 3]])
m.matmul(Matrix.identity(2))         # => m
m.solve(Vector.new([5, 10]))         # => Vector [1, 3]
m.det                                # => 5 (0 = singular; nil = not square)
m.inv                                # => Matrix (nil when singular)

# ML preprocessing — fit/transform, sklearn-style
Scaler.new(:standard).fit_transform(df)   # (v-mean)/std; :min_max for 0..1
Encoder.new(:one_hot, [:dept]).fit_transform(df)  # 0/1 "dept_eng" columns
Encoder.new(:label, [:dept])              # category -> first-seen index
Imputer.new(:median).fit_transform(df)    # nil-fill; :mean/:mode/:constant
Splitter.train_test(df, 30)          # => [train, test]; last 30% tests
Splitter.train_test(df, 30, 42)      # seeded shuffle — same seed, same split
pipe = Pipeline.new([Imputer.new(:mean), Scaler.new(:standard)])
pipe.fit_transform(df)               # chained; transform replays train params

# Estimation — LinearRegression, normal equations on LinAlg.solve
model = LinearRegression.new
model.fit([0, 1, 2, 3], [1, 3, 5, 7])  # x: DataFrame | Matrix | Vector |
model.coefficients                   # => [2]     Series | rows | flat array
model.intercept                      # => 1     (y: Series | Vector | array)
model.predict([[5], [6]])            # => [11, 13]
model.score([0, 1], [1, 3])          # => 1 (R² via Metrics.r2)

# Ridge: alpha on the X^T X diagonal — but never the intercept slot.
ridge = LinearRegression.new(12)     # alpha = 0 (default) is exact OLS
ridge.fit([0 - 3, 0 - 1, 1, 3], [0 - 5, 0 - 1, 3, 7])
ridge.coefficients                   # => [1.25]  (OLS slope 2, shrunk)
ridge.intercept                      # => 1       (bias never penalized)
half = LinearRegression.new(1.to_f / 2.to_f)  # fractional alpha: derive it —
                                     # float LITERALS corrupt call arguments
                                     # on both engines (see linear_regression.w)

# Classification — KNNClassifier, majority vote of the k nearest rows
knn = KNNClassifier.new(3)           # k neighbours (defaults to 5, sklearn)
knn.fit([[1, 1], [2, 2], [6, 6], [7, 7]], [:a, :a, :b, :b])
knn.predict([[2, 3], [7, 6]])        # => [:a, :b]  (Euclidean nearest)
knn.score(x_test, y_test)            # => accuracy; labels feed Metrics.f1

# ... or as a pipeline tail: transform features, then fit/predict
pipe = Pipeline.new([Scaler.new(:standard), LinearRegression.new])
pipe.fit(df_features, y)             # nil (unfitted) on collinear features
pipe.predict(test_df)                # scale with train params, then predict
pipe.score(test_df, y_test)          # the estimator's R² on the chain

# Model evaluation — k-fold cross-validation, re-fit per fold
KFold.new(5).split(10)               # 5 contiguous [train, test] index pairs
KFold.new(5, 42).split(10)           # ... over a seeded MINSTD shuffle first
scores = CrossValidation.cross_val_score(LinearRegression.new, x, y, 5)
                                     # => [1, 1, 1, 1, 1]  (per-fold R²)
CrossValidation.cross_val_mean(KNNClassifier.new(3), x, y, 4)  # mean fold score
```

## The train/test workflow, end to end

`examples/workflow.w` is the whole loop in one runnable, self-checking
file — `bin/tungsten bits/tungsten-koala/examples/workflow.w` prints a
fixed transcript and exits 0 on either engine (1 on any drift). Line
by line:

```tungsten
df = DataFrame.new([
  [:sqft,  [8, 6, nil, 11, 5, 9, 12, 7, 10, 6]],
  [:rooms, [2, 1, 3, 3, nil, 2, 4, 2, 3, 1]],
  [:price, [21, 16, 20, 28, 15, 23, 31, 19, 26, 16]]
])
```

An inline frame: two features with a missing cell each, and the target
carried as a third column so a single split keeps x and y row-aligned.
The underlying truth is `price = 3 + 2*sqft + rooms`.

```tungsten
pair = Splitter.train_test(df, 30, 42)
train = pair[0]
test = pair[1]
```

A seeded 30% hold-out. The seeded shuffle is koala's own MINSTD
generator, so seed 42 permutes ten rows to `[0,1,4,3,8,9,7,5,6,2]` on
*both* engines: rows `{0,1,4,3,8,9,7}` train, rows `{5,6,2}` test.

```tungsten
x_train = train.select_columns([:sqft, :rooms])
y_train = train.column_values(:price)
x_test = test.select_columns([:sqft, :rooms])
y_test = test.column_values(:price)
```

Features and target are extracted *after* the split — never split them
separately.

```tungsten
pipe = Pipeline.new([Imputer.new(:mean), Scaler.new(:standard), LinearRegression.new])
pipe.fit(x_train, y_train)
```

One Pipeline: fill the holes with column means, standardize, then fit
the estimator tail. Every statistic — fill means, scaling mean/std,
coefficients — is learned from the seven training rows only.

```tungsten
pipe.score(x_train, y_train)   # => 1
pipe.score(x_test, y_test)     # => 0.979802
```

Scoring transforms the test rows through the *fitted* imputer and
scaler (training statistics, never their own) before predicting. Train
R² is exactly 1: the training rows sit on the true plane (row 4's
missing `rooms` imputes to the train mean 2 — its true value). Test R²
dips to 0.979802 because test row 2's missing `sqft` imputes to the
train mean 53/7 ≈ 7.571 against a true 7, pulling that prediction to
≈ 21.14 against y = 20 — imputation error, made visible by the score.

The example hard-asserts its own transcript and exits 1 on mismatch,
so running it *is* the determinism check.

Live modules: `Series`, `DataFrame`, `GroupBy`, `Stats`, `Metrics`,
`Rolling`, `Join`, `Pivot` (constructors take ordered `[name, values]`
pairs — column order is preserved, which a hash would not guarantee;
`df.describe` returns a pandas-style summary frame — a `:statistic`
column of count/mean/std/min/25%/50%/75%/max labels plus one column per
numeric source column, std being the sample n−1 standard deviation and
the quartiles linear-interpolation percentiles, so the 50% row is the
median; `Stats.percentile(values, p)` and `Series#quantile(p)` take an
integer percent 0..100 and interpolate linearly, matching numpy's
default and pandas),
dense linear algebra: `Vector`, `Matrix`, `LinAlg` (pure Tungsten,
CPU-only; ops with a shape requirement return nil when it is not met),
ML preprocessing: `Scaler`, `Encoder`, `Imputer`, `Splitter`,
`Pipeline` (fit/transform with per-instance fitted state; transform
before fit returns nil; splitting is deterministic — unseeded calls
keep row order, and the seeded shuffle is a built-in MINSTD generator,
so the same seed gives the same split on both engines; `test_pct` is an
integer percent), and estimation: `LinearRegression` (least squares by
normal equations through `LinAlg.solve`, with an internal intercept
column; `new(alpha)` adds ridge regularization — alpha lands on every
X^T X diagonal entry except the intercept's, so alpha = 0 is exact OLS,
alpha > 0 fits even collinear features, and the bias is never shrunk;
alpha is an integer or a *data-derived* float such as `1.to_f / 2.to_f`
— float literals corrupt call arguments on both engines today; x may
be a DataFrame — numeric columns only — a Matrix, a Vector or Series —
one feature column — an array of row arrays, or a flat single-feature
array, and y a Series, Vector, or array; a singular system — collinear
features at alpha = 0 — makes fit return nil and `fitted?` stay false,
and `predict`/`score` return nil before a successful fit), and
classification: `KNNClassifier` (k-nearest-neighbors, koala's companion
classifier to the regression estimator — a lazy learner: `fit` stores
the training rows, `predict` returns the majority label among the k
rows closest in squared-Euclidean distance, `score` is accuracy; it
shares LinearRegression's accepted input shapes and produces the label
arrays that `Metrics.accuracy`/`precision`/`recall`/`f1` consume;
distance and vote ties break deterministically to the earlier training
row, so both engines agree; k defaults to 5). A `Pipeline` whose LAST step is
an estimator is fitted with `pipe.fit(df, y)` and answers
`pipe.predict(x)` / `pipe.score(x, y)` by transforming through every
step but the last. Model evaluation: `KFold` and `CrossValidation`
(k-fold cross-validation — `KFold.new(k).split(n)` returns k
`[train, test]` index pairs, partitioning `0...n` with scikit-learn's
fold sizes: the first `n mod k` folds are one larger, folds are
contiguous blocks unshuffled and a seed shuffles first through
Splitter's MINSTD generator so the same seed gives the same folds on
both engines; `CrossValidation.cross_val_score(model, x, y, k)` re-fits
the estimator on each fold's training rows and returns the array of
held-out scores — the estimators' `.score` is R² for LinearRegression
and accuracy for KNNClassifier — and `cross_val_mean` averages them,
sharing the estimators' accepted input shapes).

Verify with `bin/tungsten bits/tungsten-koala/spec/koala_spec.w`,
`spec/linalg_spec.w`, `spec/preprocessing_spec.w`, and
`spec/estimator_spec.w` (the tungsten-spec suites), `spec/smoke.w`
(framework-free), or the self-checking `examples/workflow.w` — all
pass interpreted and compiled.

The remaining files under `lib/` (tensor, resample, transformer,
estimator, index, sparse, gpu, device) are unported design drafts and
are not loaded by `use koala` yet (see the list in `lib/koala.w`);
estimator.w's linear-regression payoff shipped as
`lib/linear_regression.w`.
