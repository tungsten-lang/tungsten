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

Metrics.rmse([2, 4, 6], [1, 5, 7])   # => 1     (also mse / mae / r2)
Metrics.explained_variance(p, actual)# => r2's mean-corrected sibling
Metrics.mape(p, actual)              # => mean absolute PERCENTAGE error
Metrics.median_absolute_error(p, a)  # => median |residual| (outlier-robust)
Metrics.max_error(p, actual)         # => largest single |residual|
Metrics.f1([1, 1, 0], [1, 0, 0])     # => 0.666667 (also precision / recall)
Metrics.classification_report(preds, actual)  # multiclass P/R/F1 + macro/weighted avg
Metrics.roc_auc(scores, actual)      # => 0.75  area under the ROC curve
Metrics.roc_curve(scores, actual)    # => RocCurve: .fpr / .tpr / .thresholds / .auc
Metrics.log_loss(scores, actual)     # => 0.216162  binary cross-entropy (log loss)

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
Scaler.new(:standard).fit_transform([[2, 9], [4, 9]])  # rows too: cols x0, x1
sc.learned_params                    # what FIT learned: [name, mean, std]
sc.params                            # what you SET: { kind:, columns: }
sc.with_params({ kind: :min_max })   # => a NEW, UNFITTED Scaler; sc intact
Splitter.train_test(df, 30)          # => [train, test]; last 30% tests
Splitter.train_test(df, 30, 42)      # seeded shuffle — same seed, same split
pipe = Pipeline.new([Imputer.new(:mean), Scaler.new(:standard)])
pipe.fit_transform(df)               # chained; transform replays train params
named = Pipeline.new([[:fill, Imputer.new(:mean)], [:scale, Scaler.new(:standard)]])
named.step(:scale)                   # by name (symbol or string); named[1] too
named.names                          # => ["fill", "scale"]; has_step?(:scale)

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

# Classification — LogisticRegression, gradient descent on cross-entropy
lr = LogisticRegression.new          # lr = 0.1, 1000 epochs (or new(1, 500))
lr.fit([[0, 0], [1, 0], [3, 3], [4, 3]], [0, 0, 1, 1])
lr.coefficients                      # => per-feature weights (floats)
lr.intercept                         # => bias term (float)
lr.predict([[0, 1], [4, 4]])         # => [0, 1]  (P >= 0.5 -> classes[1])
lr.predict_proba([[0, 1], [4, 4]])   # => P(classes[1]) in (0, 1)
Metrics.roc_auc(lr.predict_proba(x_test), y_test, lr.classes[1])
                                     # => threshold-free ranking quality
lr.classes                           # => two labels, first-seen order
lr.score(x_test, y_test)             # => accuracy; labels feed Metrics.f1
                                     # opaque labels map to 0/1: fit two,
                                     # e.g. [:a, :b], predict returns them

# Classification — GaussianNB, MULTICLASS Gaussian naive Bayes (closed form)
nb = GaussianNB.new                  # var_smoothing = 1e-9 (sklearn's default)
nb.fit([[1, 2], [3, 4], [11, 12], [13, 14]], [0, 0, 1, 1])   # one pass, no epochs
nb.class_priors                      # => [0.5, 0.5]   P(class) = count / n
nb.means                             # => [[2, 3], [12, 13]]   per class/feature
nb.variances                         # => [[1, 1], [1, 1]]     ... + epsilon
nb.epsilon                           # => 2.6e-08  smoothing; no divide-by-zero
nb.joint_log_likelihood([[2, 3]])    # => [[-2.53102, -102.531]]  log P(c)+log p(x|c)
nb.predict_proba([[7, 8]])           # => [[0.5, 0.5]]  per-class, rows sum to 1
nb.predict_proba(x_test, 1)          # => flat P(class 1) column, for roc_auc
nb.predict([[2, 3], [12, 13]])       # => [0, 1]   argmax of the log likelihood
nb.score(x_test, y_test)             # => accuracy; labels feed Metrics.f1
                                     # three+ classes work with no wrapper

# ... or as a pipeline tail: transform features, then fit/predict
pipe = Pipeline.new([[:scale, Scaler.new(:standard)], [:model, LinearRegression.new]])
pipe.fit(df_features, y)             # nil (unfitted) on collinear features
pipe.predict(test_df)                # scale with train params, then predict
pipe.score(test_df, y_test)          # the estimator's R² on the chain

# A Pipeline IS an Estimable — the same six methods as a bare estimator
pipe.estimator_name                  # => "Pipeline"
pipe.supervised?                     # => delegated to the TAIL step
pipe.params                          # => { "scale.kind" => :standard,
                                     #      "scale.columns" => nil,
                                     #      "model.alpha" => 0 }  "step.param"
pipe.with_params({ "model.alpha" => 10 })   # fresh UNFITTED chain; pipe intact

# Clustering — KMeans, Lloyd's algorithm (koala's first UNSUPERVISED learner)
km = KMeans.new(2)                   # k clusters (defaults to 8, sklearn)
km.fit(x)                            # partitions rows; no labels needed
km.labels                            # => cluster index (0..k-1) per row
km.centroids                         # => k centroid rows (floats)
km.inertia                           # => within-cluster sum of squares
km.n_iter                            # => Lloyd iterations to convergence
km.predict([[1, 1], [11, 11]])       # => [0, 1]  nearest-centroid assignment
km.fit_predict(x)                    # fit, then return the training labels
km.score(x)                          # => -inertia (sklearn's convention)
KMeans.new(2, 42)                    # seeded init — same seed, same clustering

# Model evaluation — k-fold cross-validation, re-fit per fold
KFold.new(5).split(10)               # 5 contiguous [train, test] index pairs
KFold.new(5, 42).split(10)           # ... over a seeded MINSTD shuffle first
scores = CrossValidation.cross_val_score(LinearRegression.new, x, y, 5)
                                     # => [1, 1, 1, 1, 1]  (per-fold R²)
CrossValidation.cross_val_mean(KNNClassifier.new(3), x, y, 4)  # mean fold score
CrossValidation.cross_val_score(KMeans.new(2), x, nil, 2)      # unsupervised: no y

# Hyperparameter search — GridSearch, every combination scored by k-fold CV
gs = GridSearch.new(KNNClassifier.new, { k: [1, 3, 5] }, 4)
gs.size                              # => 3   combinations, known before fit
gs.candidates                        # => [{k: 1}, {k: 3}, {k: 5}]  search order
gs.fit(x, y)                         # nil on a bad grid — never raises
gs.best_params                       # => { k: 1 }
gs.best_score                        # => best mean fold score (higher is better)
gs.best_estimator                    # => a KNNClassifier(1) REFIT on all the data
gs.results                           # => [{params:, score:, rank:}, ...] best-first
gs.predict(x_test)                   # delegates to best_estimator
GridSearch.new(km, { k: [2, 3] }, 2).fit(x)        # unsupervised: no y
GridSearch.new(m, grid, 4, 42)                     # seeded folds
GridSearch.new(m, grid, 4, nil, false)             # refit: off
GridSearch.new(pipe, { "scale.kind" => [:standard, :min_max],
                       "model.alpha" => [1, 10] }, 2)  # tune PREPROCESSING
                                     # and the model in ONE grid

# The estimator contract — one uniform interface across all five
m.supervised?                        # => true; false for KMeans alone
m.estimator_name                     # => "LinearRegression"
m.params                             # => { alpha: 12 }  hyperparameters ONLY
m.with_params({ alpha: 3 })          # => a NEW, UNFITTED clone; m untouched
Estimator.feature_rows(x)            # the one definition of every x shape
Estimator.target_values(y)           # ... and every y shape
Estimator.fit_model(m, rows, yvals)  # arity-safe: fit(x,y) or fit(x)
Estimator.score_model(m, rows, yvals)
```

## The estimator contract

Every estimator — `LinearRegression`, `KNNClassifier`,
`LogisticRegression`, `GaussianNB`, `KMeans` — answers one declared
interface, defined in `lib/estimator_base.w`:

| trait | methods | who |
| --- | --- | --- |
| `Tunable` | `params` `with_params(overrides)` | Scaler, Imputer, Encoder (and every Estimable, which restates the pair) |
| `Estimable` | `fitted?` `predict(x)` `supervised?` `params` `with_params(overrides)` `estimator_name` | all five |
| `SupervisedEstimator` | `fit(x, y)` `score(x, y)` | LinearRegression, KNNClassifier, LogisticRegression, GaussianNB |
| `UnsupervisedEstimator` | `fit(x)` `score(x)` | KMeans |

`Tunable` is the hyperparameter half on its own — what a search needs and
nothing more. It exists because koala's transformers carry real
hyperparameters (`kind`, `strategy`, `columns`, `fill_value`) but have no
`predict` and no fit ARITY to declare, so `Estimable` would be a lie for
them. Declaring it is the whole entry fee for a `Pipeline`'s tunable
surface. `Estimable` RESTATES the two methods rather than composing
`Tunable`, because trait composition (`with`) does not run on the
interpreter — the traits here are flat by construction. Nothing tests a
trait NAME: `Pipeline.tunable?` tests the two methods, so both kinds of
step pass without it knowing either name.

A class declares its conformance with `is`:

```tungsten
+ LinearRegression
  is Estimable
  is SupervisedEstimator
```

The traits are FLAT (no `with` composition — that form does not run on
the interpreter) and `is` is a **declaration, not an enforcement**: a
class naming a trait it does not satisfy still compiles. The enforcement
is `spec/estimator_spec.w`, which walks all five and asserts each really
answers every contract method.

`supervised?` exists because fit's ARITY genuinely differs — KMeans takes
`fit(x)`, the rest take `fit(x, y)`. `Estimator.fit_model` /
`.score_model` do that dispatch for you, so generic tooling never has to
guess.

`params` reports only the CONSTRUCTOR knobs a search varies (`alpha`;
`k`; `learning_rate` / `epochs`; `var_smoothing`; `k` / `seed` /
`max_iter`) and never learned state — coefficients and centroids stay out
of the search space, before and after a fit. `with_params` **clones**: it
returns a fresh unfitted instance with the overrides applied and leaves
the receiver alone, so a search fans out from one prototype without
aliasing. Keys you omit carry over, so `m.with_params(m.params)`
round-trips; key PRESENCE decides, so an explicit `{ seed: nil }` really
does clear KMeans's seed.

Two engine gotchas the contract works around: hash `to_s` key order
differs between the engines (compare `params[:alpha]`, never the whole
hash as a string), and `type(obj)` on an instance returns the class name
compiled but `"Hash"` interpreted — which is why the contract carries
`estimator_name`.

Input coercion lives on the neutral `Estimator` base, not on any
estimator: `Estimator.feature_rows(x)` accepts a DataFrame (numeric
columns only), a Matrix, an array of row arrays, or a flat
single-feature array; `Estimator.target_values(y)` accepts a Series, a
Vector, or a plain array. `LinearRegression.feature_rows` /
`.target_values` remain as delegating aliases for callers written before
the move.

`Estimator.frame(x)` is the transformer-side twin: the same input shapes,
coerced the other way, into a DataFrame whose columns are named
`x0`, `x1`, … positionally (a DataFrame passes through untouched). The
transformers address columns BY NAME, but `CrossValidation` — and so
`GridSearch` — coerces `x` to plain ROW ARRAYS before the model sees it,
so a `Scaler` step inside a searched pipeline is handed rows. `frame` is
what makes that work; without it the chain died on `column_names`.

```tungsten
Scaler.new(:standard).fit_transform([[2, 9], [4, 9], [6, 9]])
# => a DataFrame with columns "x0", "x1"
```

## Pipelines

A `Pipeline` chains fit/transform steps into one transformer, fitting
each step on the previous step's output and replaying the *training*
parameters on `transform`. Its last step may instead be an estimator,
which is what makes a whole chain fittable, predictable and scorable as
a unit. Pipelines nest.

### Named steps

Give a step as a `[name, step]` pair and the chain becomes addressable
by meaning rather than by position:

```tungsten
pipe = Pipeline.new([
  [:scale, Scaler.new(:standard)],
  [:model, LinearRegression.new]
])

pipe.step(:scale)        # the Scaler — :scale and "scale" both work
pipe.step("model")       # the LinearRegression
pipe[1]                  # ... which positional access still returns
pipe.names               # => ["scale", "model"]
pipe.has_step?(:model)   # => true
```

The bare-array form is unchanged and gets names derived for it. A step
that answers `estimator_name` is named after it, downcased — sklearn's
`make_pipeline` convention; anything else is named for its POSITION, so
the auto name mirrors `pipe[i]`:

```tungsten
Pipeline.new([Imputer.new(:mean), Scaler.new(:standard), LinearRegression.new]).names
# => ["step_0", "step_1", "linearregression"]
```

Repeats de-duplicate by suffix (`linearregression`,
`linearregression_2`), so every name in a pipeline is unique — which is
what lets the parameter keys below be unambiguous. Names normalize to
STRINGS: one vocabulary, because those keys are strings too.

### A Pipeline IS an Estimable

A Pipeline answers the same `Estimable` contract as a bare estimator —
`fitted?` / `predict` / `supervised?` / `params` / `with_params` /
`estimator_name` — so generic tooling drives a whole chain through
exactly the interface it uses for one model, **without knowing pipelines
exist**:

```tungsten
pipe.params
# => { "scale.kind" => :standard, "scale.columns" => nil,
#      "model.alpha" => 0 }

tuned = pipe.with_params({ "model.alpha" => 10 })   # fresh, UNFITTED
pipe.params["model.alpha"]                          # => 0 — untouched
```

That is the whole payoff: a grid search written against `Estimable`
alone tunes a pipeline the same way it tunes a model.

**The separator is a DOT** — a step's parameters are addressed
`"<step>.<param>"`. The dot reads as what it is (attribute access on a
named step), it cannot occur inside a parameter name, and it nests for
free: a pipeline inside a pipeline flattens to `"inner.model.alpha"`,
because each level only prefixes its own step name. scikit-learn spells
this `__` because a Python keyword argument cannot contain a dot; a
Tungsten hash key is an ordinary string, so the readable separator is
available and is the one used here.

**The tunable surface is exactly the steps answering BOTH `params` and
`with_params`** — the `Tunable` pair. That rule is not a convenience.
`params` and `with_params` have to round-trip
(`p.with_params(p.params)` reproduces `p`), so reporting a key that
`with_params` could not apply would break the contract for every caller.

koala's bundled transformers are `Tunable`, so **the preprocessing is
part of the search space**: a `Scaler` named `:scale` contributes
`"scale.kind"` and `"scale.columns"`, an `Imputer` named `:impute`
contributes `"impute.strategy"` / `"impute.columns"` /
`"impute.fill_value"`, and an `Encoder` contributes `"encode.kind"` /
`"encode.columns"`. Nothing about that is special-cased to a class — the
rule was always stated in terms of the two METHODS, so the transformers
joined the surface with no change to `lib/pipeline.w` or
`lib/grid_search.w` at all. A step answering neither half is still
excluded and carried by reference.

**Learned state is not `params`.** `Scaler#learned_params` (per-column
`[name, mean, std]` triples) and `Imputer#learned_params` (per-column
`[name, fill]` pairs) report what `fit` DISCOVERED; `params` reports what
you SET. Those were one method once, and the fitted meaning lost the
name: `params` means the constructor's knobs everywhere else in koala,
and a `Pipeline` flattening a step's `params` into its search space must
never be handed state that `with_params` cannot rebuild. `Encoder`'s
learned state stays where it was, on `categories(name)`.

`with_params` returns a fresh, UNFITTED Pipeline and leaves the receiver
alone, so a search fans out from one prototype without aliasing. Every
tunable step is rebuilt through its own `with_params` (a fresh unfitted
step, even where no key targeted it); unmentioned keys carry over, and a
key naming no step — or no parameter of it — is ignored rather than
fatal. A step outside the contract cannot be cloned generically and is
carried over by reference: safe for the serial fit-then-use a search
does, since the new pipeline is unfitted and `fit` re-fits every step
from scratch, but two such clones must not be fitted and used
interleaved.

`supervised?` delegates to the TAIL step (false for a transformer-only
chain), which is what tells generic tooling the fit arity to use. A
Pipeline declares only `is Estimable`, and not one of the two arity
traits, precisely because that arity is its tail's to decide at runtime
rather than a property of the class — `Estimator.fit_model` /
`.score_model` read `supervised?` and dispatch. Today the tail estimator
must be a supervised one: fitting without `y` transforms through every
step, which an unsupervised tail has no `transform` for.

## Hyperparameter search

`GridSearch` (`lib/grid_search.w`) is model SELECTION: it scores every
combination of a hyperparameter grid by k-fold cross-validation and keeps
the best, the way scikit-learn's `GridSearchCV` sits above
`cross_val_score`.

```tungsten
gs = GridSearch.new(KNNClassifier.new, { k: [1, 3, 5] }, 4)
gs.fit(x, y)
gs.best_params        # => { k: 1 }
gs.best_score         # => its mean fold score
gs.best_estimator     # => a KNNClassifier(1) refit on ALL the data
gs.results            # => every combination as { params:, score:, rank: }
```

The constructor is
`GridSearch.new(estimator, param_grid, k = 5, seed = nil, refit = true)` —
a PROTOTYPE estimator, a grid of `param => [values]`, the CV fold count,
an optional fold-shuffle seed, and whether to refit the winner. Each
candidate is built with `estimator.with_params(combination)` — a fresh,
UNFITTED clone, so the prototype is never touched and candidates never
alias — and scored with `CrossValidation.cross_val_mean`. Higher always
wins: every koala score follows sklearn's sign convention (R² / accuracy,
and NEGATED inertia for KMeans), so one comparison ranks them all.

**Contract-only, never type-tested.** GridSearch reaches its estimator
through exactly six methods — `params`, `with_params`, `supervised?`,
`fit` / `score` (only via `Estimator.fit_model` / `.score_model`) and
`estimator_name`. It never asks what class it holds, so anything
answering `Estimable` is searchable. A Pipeline is, today, with no code
in `grid_search.w` aware of it:

```tungsten
gs = GridSearch.new(Pipeline.new([LinearRegression.new]),
                    { "linearregression.alpha" => [0, 1] }, 3)
gs.fit(x, y)          # best_estimator is a refit Pipeline
```

**Preprocessing is searchable too.** Because the transformers are
`Tunable`, one grid can vary the scaling and the model together — and
neither `grid_search.w` nor `pipeline.w` contains a line about scaling:

```tungsten
pipe = Pipeline.new([[:scale, Scaler.new(:min_max)],
                     [:model, LinearRegression.new(10)]])
gs = GridSearch.new(pipe, { "scale.kind"  => [:min_max, :standard],
                            "model.alpha" => [1, 10] }, 2)
gs.fit(x, y)
gs.best_params        # => { "scale.kind" => :standard, "model.alpha" => 1 }
gs.best_estimator     # => a refit Pipeline carrying BOTH winning knobs
```

That winner is not arbitrary. Ridge shrinks the fitted slope by
`S / (S + alpha)`, where `S` is the training column's centred sum of
squares *after* scaling — so the scaler decides how hard the same `alpha`
bites. `:standard` divides by the sample std, leaving `S = n - 1`;
`:min_max` divides by the range, leaving `S = (n - 1) * std² / range²`,
which is always smaller. Less shrinkage means a fit closer to the true
line, so `(alpha 1, :standard)` beats `(1, :min_max)` beats
`(10, :standard)` beats `(10, :min_max)` — exactly the ranking the search
reports (`spec/preprocessing_spec.w`, "searches a scaler param and a
model param in one grid"). Note the winner is the SECOND candidate
enumerated, so it is not the tie-break default, and it differs from the
prototype in BOTH knobs.

Grid keys are checked against `estimator.params`, so `"scale.kind"` being
accepted is itself proof the Scaler is on the tunable surface — and a
typo in the step name or the param is still caught loudly-by-nil.

**Supervised and unsupervised.** `fit(x, y)` searches a supervised
estimator, `fit(x)` an unsupervised one — the arity is chosen by the
estimator's own `supervised?`, down in `CrossValidation`, so KMeans needs
no special case. Read the statistics honestly, though: `-inertia` falls
monotonically as k rises, so searching KMeans's `k` by cross-validated
score simply elects the LARGEST k offered. Use it for `max_iter` or
`seed`, and pick k by an elbow criterion.

**Determinism is a guarantee, on both engines.** Candidate order is a
pure function of the grid, never of hash iteration order — which is
genuinely unstable: the same literal yields `.keys` in one order
interpreted and another compiled. So keys are sorted by NAME
(`GridSearch.grid_keys`; symbol `.sort` is *not* used — its order is
neither documented nor lexicographic), each value list keeps the order
you gave it, and the product runs odometer-style with the LAST key
varying fastest — `{ a: [3, 4], b: [1, 2] }` gives a3b1, a3b2, a4b1,
a4b2, matching sklearn's `ParameterGrid`. Ties break to the FIRST
candidate enumerated, and `results` is ranked by a STABLE sort, so equal
scores keep enumeration order. `size` and `candidates` are computed at
construction and read correctly BEFORE `fit`.

**Degenerate input returns nil, never raises** — koala's convention
throughout. `fit` is nil (and `fitted?` stays false) for a nil, empty, or
empty-valued grid; for a grid naming a param the estimator does not
expose (checked against `estimator.params`, so a typo is caught rather
than silently ignored by `with_params`, which would report a "winner"
that never varied); for misaligned `x` / `y` or a k out of range; and
when no candidate scored at all. A SINGLE nil-scoring candidate is not
degenerate — `alpha = 0` on collinear features cannot fit, so it stays in
`results` with a nil score, ranked last, and never wins. With
`refit = false`, `best_estimator` stays nil (sklearn's semantics) while
`best_params` / `best_score` / `results` are unaffected.

`CrossValidation` was widened to make this work: it now fits and scores
through `Estimator.fit_model` / `.score_model` instead of calling
`model.fit(rows, y)` directly, so `y` is optional and an unsupervised
estimator cross-validates correctly rather than not at all. A fold whose
re-fit FAILS is now recorded as nil and not scored — previously it was
scored anyway, silently reporting the PREVIOUS fold's fitted state.

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
before fit returns nil; steps may be named as `[name, step]` pairs and
addressed with `step(:name)` / `names` / `has_step?` alongside the
positional `pipe[i]`, and a Pipeline itself answers `Estimable`, so its
steps' hyperparameters flatten to `"step.param"` keys a generic search
can tune — see *Pipelines* above; splitting is deterministic — unseeded calls
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
row, so both engines agree; k defaults to 5) and `LogisticRegression`
(binary logistic regression — koala's parametric probabilistic
classifier, fitted by full-batch gradient descent on the cross-entropy
loss: `fit` learns weights and a bias minimizing mean cross-entropy of
`sigmoid(w·x + b)` against 0/1 targets, stepping every epoch by
−learning_rate × gradient from zero weights, so the first epoch is exact
— on `[[0],[1]]`/`[0,1]` at learning rate 1 the weight gradient is
−0.25 and `w` becomes `[0.25]`, `b` stays 0. `predict_proba` returns
`P(classes[1])` strictly in (0, 1) — the sigmoid argument is clamped to
±30 so `exp` never overflows — and `predict` thresholds at 0.5 to the
original labels. Labels are opaque and binary: fit collects the two
distinct labels in first-seen order, maps the first to 0 and the second
to 1, and returns those originals, so the output feeds `Metrics.accuracy`
/ `precision` / `recall` / `f1` exactly like KNNClassifier; a y with one
class or three or more makes fit return nil. `new(learning_rate, epochs)`
defaults to 0.1 / 1000 — the default rate is derived as `1.to_f/10.to_f`
because a float literal corrupts call arguments, so a caller wanting a
fractional rate derives it the same way. It shares LinearRegression's
accepted input shapes, and `Math.exp`/`Math.log` agree bit-for-bit on
both engines, so it is deterministic) and `GaussianNB` (koala's
GENERATIVE classifier, the third kind of supervised learner beside
KNNClassifier's lazy/instance-based and LogisticRegression's
discriminative/iterative one. Where those two learn a decision rule,
GaussianNB models how the data was *generated*: assume the features are
conditionally independent given the class and each is normally
distributed, and the fit is CLOSED FORM — one pass for the class priors
`count/n` and the per-class per-feature `means` and `variances`. No
epochs, no learning rate, no seed, so it is exactly determinate. Classify
by Bayes' rule in log space: `joint_log_likelihood` is
`log P(c) − 0.5·Σ log(2π·var) − 0.5·Σ (x−mean)²/var` per class
(scikit-learn's `_joint_log_likelihood`), `predict` takes its argmax —
ties break to the first-seen class — and `predict_proba` normalizes it
through a max-shifted softmax so each row's posteriors sum to 1.
`predict_proba(x)` returns one array per row, one entry per class in
`classes` order; `predict_proba(x, label)` returns that single class's
flat column, ready for `Metrics.roc_auc` / `Metrics.log_loss`, and nil
for a label the fit never saw. Variances are POPULATION (n denominator)
variances, matching numpy's `np.var` — not `Stats.var`'s sample n−1 — and
every one gets `epsilon = var_smoothing × (largest column variance over
all training rows)` added, scikit-learn's variance smoothing: a feature
that never varies inside a class would otherwise divide by zero, and at
the default `var_smoothing = 1e-9` the nudge is invisible at printing
precision. koala adds one thing scikit-learn does not — when EVERY
feature is constant that reference variance is 0 too and sklearn yields
nan, so epsilon falls back to `var_smoothing` itself and the model stays
finite. Labels are opaque and MULTICLASS out of the box — any number of
integer, string, or symbol labels, no one-vs-rest wrapper, collected in
first-seen order (scikit-learn sorts) — so `predict` feeds
`Metrics.accuracy` and `Metrics.classification_report` directly, and a
single class is fine (unlike LogisticRegression, which needs exactly
two). It shares LinearRegression's accepted input shapes. On
scikit-learn's own documentation example — `X =
[[-1,-1],[-2,-1],[-3,-2],[1,1],[2,1],[3,2]]`, `y = [1,1,1,2,2,2]` — it
reproduces `means [[-2,-1.33333],[2,1.33333]]`, `variances
[[0.666667,0.222222],[0.666667,0.222222]]` and `predict([[-0.8,-1]]) =>
[1]`). Both classifiers' probabilities feed
threshold-free evaluation: `Metrics.roc_auc(scores, actual, pos_label)`
is the area under the ROC curve — the probability the model ranks a
random positive above a random negative, crediting ties half (the
Mann-Whitney U statistic), 1 perfect / 0.5 random / 0 inverted — and
`Metrics.roc_curve` returns a `RocCurve` carrying the full step curve's
`.fpr` / `.tpr` / `.thresholds` arrays (one point per distinct score plus
a leading reject-all point, scikit-learn's `drop_intermediate=False`)
plus its `.auc`; both take `scores` (a probabilistic classifier's
`P(positive)`, e.g. `LogisticRegression#predict_proba` or
`GaussianNB#predict_proba(x, label)`) and `actual`,
with `pos_label` naming the positive class (default 1, the
precision/recall convention), and return nil when a class is absent
(AUC undefined) or the arrays are misaligned. `Metrics.auc(x, y)` is the
underlying trapezoidal area under any curve, so `roc_auc == auc(fpr,
tpr)`. `Metrics.log_loss(scores, actual, pos_label)` is the binary
cross-entropy `-mean(y*ln p + (1-y)*ln(1-p))` — the EXACT objective
`LogisticRegression` minimizes and scikit-learn's `log_loss`. Where
`roc_auc` judges only the ranking of the scores, log loss judges their
calibration (how close each probability is to the outcome), so a model
can rank perfectly yet carry a large log loss from under-confident
probabilities; lower is better, 0 a perfectly confident classifier and
`ln 2 ≈ 0.693147` a coin flip. Probabilities are clipped to
`[eps, 1-eps]` (`eps = 1e-15`) so a confidently wrong prediction stays
finite, and — unlike `roc_auc` — a single present class is well-defined
(no negatives to normalize by), so it returns nil only when `scores` and
`actual` are misaligned or empty. A `Pipeline` whose LAST step is
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
sharing the estimators' accepted input shapes). Clustering: `KMeans`
(koala's first UNSUPERVISED learner — it partitions rows into k groups
with no labels at all, by Lloyd's algorithm: seed k centroids, then
repeat ASSIGN-each-row-to-its-nearest-centroid / UPDATE-each-centroid-to-
its-members'-mean until the assignment stops changing (or max_iter,
default 300) — `fit` learns `centroids` / `labels` / `inertia` (the
within-cluster sum of squares, which never increases across steps) /
`n_iter`, `predict` assigns fresh rows to the nearest centroid,
`fit_predict` returns the training labels, and `score` is the negated
inertia, scikit-learn's convention. Determinism — k-means' only
randomness is the initial centroids — is pinned two ways, both
reproducible on both engines: with no seed the centroids are the first
k DISTINCT rows in order, and an integer seed permutes the rows first
through Splitter's MINSTD generator (as `KFold` does) then seeds from
the first k distinct; distance ties in ASSIGN break to the lowest-index
centroid, so the whole clustering is a pure function of the inputs. k
defaults to 8 (scikit-learn's). It shares the estimators' accepted input
shapes through `Estimator.feature_rows` and returns nil for an empty or ragged x,
k < 1, or fewer rows than clusters. On the two 2x2 boxes
`[[0,0],[2,0],[0,2],[2,2],[10,10],[12,10],[10,12],[12,12]]` at k = 2 it
converges in 2 iterations to centroids `[[1,1],[11,11]]`, labels
`[0,0,0,0,1,1,1,1]`, and inertia exactly 16 — matching scikit-learn's
`KMeans` with the same fixed init). Model selection: `GridSearch`
(`lib/grid_search.w` — exhaustive hyperparameter search, the layer above
cross-validation: it enumerates a param grid's cartesian product in an
order that is a pure function of the grid, clones the prototype estimator
once per combination through `with_params`, scores each by k-fold CV, and
reports `best_params` / `best_score` / `best_estimator` (refit on the
full data) plus a ranked `results` table. It touches its estimator only
through the `Estimable` contract, so a Pipeline searches with no code
aware of it, and supervised and unsupervised estimators are dispatched by
their own `supervised?`. Ties break to the first candidate enumerated and
a bad grid returns nil rather than raising).

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
