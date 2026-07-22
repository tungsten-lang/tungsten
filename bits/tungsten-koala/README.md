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
Metrics.fbeta(preds, actual, 2)      # => f1 with recall weighted beta times
Metrics.classification_report(preds, actual)  # multiclass P/R/F1 + macro/micro/weighted avg
Metrics.balanced_accuracy(preds, actual)      # => macro recall — accuracy that skew can't fool
Metrics.matthews_corrcoef(preds, actual)      # => MCC, the imbalanced-binary metric of choice
Metrics.cohen_kappa(preds, actual)   # => agreement corrected for chance
Metrics.roc_auc(scores, actual)      # => 0.75  area under the ROC curve
Metrics.roc_curve(scores, actual)    # => RocCurve: .fpr / .tpr / .thresholds / .auc
Metrics.average_precision(scores, actual)     # => PR-AUC — the right curve when positives are rare
Metrics.precision_recall_curve(scores, actual) # => .precision / .recall / .thresholds
Metrics.log_loss(scores, actual)     # => 0.216162  binary cross-entropy (log loss)
Metrics.brier_score(scores, actual)  # => 0.0375  BOUNDED calibration error
Metrics.silhouette_score(x, labels)  # => cluster quality — the metric KMeans lacked

v = Vector.new([1, 2, 3])
v.dot(Vector.new([4, 5, 6]))         # => 32
m = Matrix.new([[2, 1], [1, 3]])
m.matmul(Matrix.identity(2))         # => m
m.solve(Vector.new([5, 10]))         # => Vector [1, 3]
m.det                                # => 5 (0 = singular; nil = not square)
m.inv                                # => Matrix (nil when singular)
m.qr                                 # => { q:, r: } reduced Householder QR
tall = Matrix.new([[1, 0], [1, 1], [1, 2], [1, 3]])
tall.lstsq([0, 1, 2, 5])             # => Vector [-0.4, 1.6]  least squares

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

# Dimensionality reduction — PCA, a transformer (one-sided Jacobi, not covariance)
pca = PCA.new(2)                     # keep the top 2 principal directions
scores = pca.fit_transform([[0 - 2, 1], [0 - 1, 0 - 1], [0, 0], [1, 0 - 1], [2, 1]])
scores.column_names                  # => ["pc0", "pc1"]  a DataFrame of scores
pca.explained_variance               # => Vector [2.5, 1]  sigma^2 / (n - 1)
pca.explained_variance_ratio         # => Vector [0.714286, 0.285714]  share each keeps
pca.components                       # a 2x2 Matrix, one unit-norm direction per row
pca.inverse_transform(scores)        # DataFrame back in the original coordinates
PCA.new(2, true)                     # whiten: rescale scores to unit variance

# Estimation — LinearRegression, Householder QR least squares
model = LinearRegression.new
model.fit([0, 1, 2, 3], [1, 3, 5, 7])  # x: DataFrame | Matrix | Vector |
model.coefficients                   # => [2]     Series | rows | flat array
model.intercept                      # => 1     (y: Series | Vector | array)
model.predict([[5], [6]])            # => [11, 13]
model.score([0, 1], [1, 3])          # => 1 (R² via Metrics.r2)

# Ridge: alpha on the X^T X diagonal — but never the intercept slot.
ridge = LinearRegression.new(12)     # alpha = 0 (default) is plain OLS, by QR
ridge.fit([0 - 3, 0 - 1, 1, 3], [0 - 5, 0 - 1, 3, 7])
ridge.coefficients                   # => [1.25]  (OLS slope 2, shrunk)
ridge.intercept                      # => 1       (bias never penalized)
half = LinearRegression.new(1.to_f / 2.to_f)  # fractional alpha: derive it —
                                     # float LITERALS corrupt call arguments
                                     # on both engines (see linear_regression.w)

# Lasso / ElasticNet — L1 and L1+L2: where ridge SHRINKS, lasso SELECTS
las = Lasso.new(1.to_f / 5.to_f)     # alpha 0.2 — derive floats; a literal corrupts args
las.fit([[1, 5], [2, 3], [3, 8], [4, 1], [5, 9], [6, 2], [7, 6], [8, 4]],
        [3, 5, 8, 9, 11, 14, 15, 17])   # feature 1 is noise
las.coefficients                     # => [1.9619, 0]  junk slope thresholded EXACTLY to 0
las.intercept                        # => 1.42143  intercept never penalized (centering)
las.n_iter                           # => 2   coordinate-descent sweeps to converge
Lasso.new.l1_ratio                   # => 1   Lasso IS ElasticNet(alpha, 1)
ElasticNet.new(1, 1.to_f / 2.to_f)   # (alpha, l1_ratio); new(a, 0) == LinearRegression.new(n*a)

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

# Classification — DecisionTreeClassifier, CART: greedy axis-aligned splits
dt = DecisionTreeClassifier.new      # gini, unlimited depth (see below for knobs)
dt.fit([[0, 0], [1, 0], [0, 10], [1, 10]], [:lo, :lo, :hi, :hi])
dt.tree[:feature]                    # => 1     the split feature it CHOSE
dt.tree[:threshold]                  # => 5     midpoint of the two x1 values
dt.tree[:gain]                       # => 0.5   impurity decrease it bought
dt.depth                             # => 1     .node_count / .leaf_count too
dt.tree_lines                        # => the fitted tree, READABLE:
                                     #    ["x1 <= 5", "  leaf: lo (n=2)",
                                     #                "  leaf: hi (n=2)"]
dt.predict([[99, 4], [-7, 6]])       # => [:lo, :hi]   the original labels
dt.predict_proba(x_test)             # => the LEAF's class distribution per row
dt.predict_proba(x_test, :hi)        # => flat P(:hi) column, for roc_auc
dt.score(x_test, y_test)             # => accuracy; three+ classes, no wrapper
DecisionTreeClassifier.new(3, 5, 2, :entropy)
                                     # max_depth, min_samples_split,
                                     # min_samples_leaf, criterion — all four
                                     # are tunable `params`

# Regression — DecisionTreeRegressor, the same tree on an MSE criterion
rt = DecisionTreeRegressor.new(1)    # a regression STUMP
rt.fit([[0], [1], [2], [3]], [0, 2, 4, 6])
rt.predict([[0], [3]])               # => [1, 5]   PIECEWISE CONSTANT leaf means
rt.score(x_test, y_test)             # => R², like LinearRegression's

# Ensemble — RandomForestClassifier: bagged CART + per-split feature subsampling
rf = RandomForestClassifier.new(50, :sqrt, nil, 1, 42)  # n_estimators, max_features, depth, leaf, seed
rf.fit([[0, 0], [1, 0], [0, 1], [1, 1], [10, 10], [11, 10], [10, 11], [11, 11]],
       [:a, :a, :a, :a, :b, :b, :b, :b])
rf.predict_proba([[0, 0]])[0]        # => [0.98, 0.02]  MEAN of the trees' leaf distributions
rf.oob_score                         # out-of-bag accuracy — a free holdout, no second split
rf.tree_count                        # => 50   trees that grew (rf.trees are the roots)
RandomForestRegressor.new(50, nil, nil, 1, 42)   # MSE trees; max_features defaults to :all
RandomForestClassifier.new(1, :all, nil, 1, 0, nil, false)  # == the DecisionTree, node for node

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

# Clustering — DBSCAN, density-based (koala's SECOND unsupervised learner)
rows = [[0, 0], [0, 1], [1, 0], [1, 1], [10, 10], [10, 11], [11, 10], [11, 11], [50, 50]]
db = DBSCAN.new(2, 3)                # eps = 2, min_samples = 3 (eps has NO default)
db.fit_predict(rows)                 # => [0, 0, 0, 0, 1, 1, 1, 1, -1]  -1 = noise (outlier)
db.n_clusters                        # => 2   DISCOVERED, not supplied like KMeans's k
db.core_sample_indices               # => [0, 1, 2, 3, 4, 5, 6, 7]  the dense-region rows
db.predict([[1, 2], [9, 10], [5, 5], [50, 50]])  # => [0, 1, -1, -1]  nearest CORE within eps
db.score(rows)                       # => 0.919526  silhouette over the non-noise rows
DBSCAN.new(2, 3, "manhattan")        # metric: euclidean (default) | manhattan | chebyshev

# Model evaluation — k-fold cross-validation, re-fit per fold
KFold.new(5).split(10)               # 5 contiguous [train, test] index pairs
KFold.new(5, 42).split(10)           # ... over a seeded MINSTD shuffle first
scores = CrossValidation.cross_val_score(LinearRegression.new, x, y, 5)
                                     # => [1, 1, 1, 1, 1]  (per-fold R²)
CrossValidation.cross_val_mean(KNNClassifier.new(3), x, y, 4)  # mean fold score
CrossValidation.cross_val_score(KMeans.new(2), x, nil, 2)      # unsupervised: no y

# Six splitters — pass ANY of them where the fold count goes
StratifiedKFold.new(3).split(y)      # every fold keeps y's class mix
LeaveOneOut.new.split(4)             # n folds, one held-out row each
GroupKFold.new(2).split(groups)      # no group spans train and test
TimeSeriesSplit.new(3).split(12)     # expanding window, never the future
TimeSeriesSplit.new(3, 1).split(12)  # ... with a 1-row gap before each test
ShuffleSplit.new(5, 30, 42).split(10)  # 5 seeded random 30% hold-outs
CrossValidation.cross_val_score(KNNClassifier.new(1), x, y, StratifiedKFold.new(3))
GridSearch.new(KNNClassifier.new, { k: [1, 3] }, StratifiedKFold.new(3))

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

# The estimator contract — one uniform interface, whatever the model
m.supervised?                        # => true; false for KMeans / DBSCAN (unsupervised)
m.supports_sample_weight?            # => true; false for KNNClassifier alone
m.estimator_name                     # => "LinearRegression"
m.params                             # => { alpha: 12 }  hyperparameters ONLY
m.with_params({ alpha: 3 })          # => a NEW, UNFITTED clone; m untouched
Estimator.feature_rows(x)            # the one definition of every x shape
Estimator.target_values(y)           # ... and every y shape
Estimator.fit_model(m, rows, yvals)  # arity-safe: fit(x,y) or fit(x)
Estimator.score_model(m, rows, yvals)

# Sample weights — an optional trailing argument, sklearn-style
m.fit(x, y, [2, 1, 1])               # row 0 counts twice
m.score(x, y, [2, 1, 1])             # ... and is scored that way
Metrics.accuracy(preds, act, w)      # weighted metrics, same convention
CrossValidation.cross_val_score(m, x, y, 5, nil, w)   # subset per fold

# Model persistence — a fitted model survives the process
text = Persist.dumps(m)              # a self-contained String; nil if unfitted
m2 = Persist.loads(text)             # the model back; nil on anything corrupt
m2.predict(x) == m.predict(x)        # IDENTICAL, to the last bit
Persist.dumps(pipe)                  # works for a whole Pipeline, nested
```

## The estimator contract

Every estimator — the linear and regularized regressors, the
classifiers, the tree and forest ensembles, and the two clustering
algorithms — answers one declared interface, defined in
`lib/estimator_base.w`:

| trait | methods | who |
| --- | --- | --- |
| `Tunable` | `params` `with_params(overrides)` | Scaler, Imputer, Encoder, PCA (and every Estimable, which restates the pair) |
| `Estimable` | `fitted?` `predict(x)` `supervised?` `supports_sample_weight?` `params` `with_params(overrides)` `estimator_name` | every estimator below, plus `Pipeline` |
| `SupervisedEstimator` | `fit(x, y, sample_weight)` `score(x, y, sample_weight)` | LinearRegression, Lasso, ElasticNet, KNNClassifier, LogisticRegression, GaussianNB, DecisionTreeClassifier, DecisionTreeRegressor, RandomForestClassifier, RandomForestRegressor |
| `UnsupervisedEstimator` | `fit(x, sample_weight)` `score(x, sample_weight)` | KMeans, DBSCAN |

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
is `spec/estimator_spec.w`, which walks them all and asserts each really
answers every contract method.

`supervised?` exists because fit's ARITY genuinely differs — KMeans takes
`fit(x)`, the rest take `fit(x, y)`. `Estimator.fit_model` /
`.score_model` do that dispatch for you, so generic tooling never has to
guess.

`params` reports only the CONSTRUCTOR knobs a search varies (`alpha`;
`k`; `learning_rate` / `epochs`; `var_smoothing`; `max_depth` /
`min_samples_split` / `min_samples_leaf` / `criterion`; `k` / `seed` /
`max_iter`) and never learned state — coefficients, centroids and the
fitted tree stay out of the search space, before and after a fit. `with_params` **clones**: it
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

## Sample weights

Every `fit` and every `score` takes an optional trailing `sample_weight`
— a per-row importance vector, scikit-learn's
`fit(X, y, sample_weight=None)`:

```tungsten
model.fit(x, y)                  # unweighted — unchanged, forever
model.fit(x, y, [2, 1, 1])       # row 0 counts twice
model.score(x, y, [2, 1, 1])     # ... and is scored that way
```

That is how you handle **imbalanced classes** (up-weight the rare one),
**importance-weighted data** (a row that stands for a thousand
customers), and **bootstrap resampling** — the last being the thing a
random forest is built out of.

### Integer weights ARE duplication

The definition of correctness, and what `spec/sample_weight_spec.w`
asserts for every estimator that takes weights:

```tungsten
model.fit([r0, r1, r2], [y0, y1, y2], [2, 1, 1])
model.fit([r0, r0, r1, r2], [y0, y0, y1, y2])   # the SAME model
```

It follows that a weight of **0 drops a row** and that an all-1s vector
is a **no-op** — both asserted too. `Estimator.drop_zero_weights` makes
the zero case structural rather than something each estimator
re-derives, so a dropped row cannot seed a k-means centroid, claim a
naive-Bayes prior, or shift the first-seen class order.

An unusable vector — wrong length, empty, negative, or summing to zero —
makes `fit` return **nil** and leaves `fitted?` false, the bit's
shape-error convention. Nothing raises. Validation lives in one place,
`Estimator.weight_values`, and accepts a plain array, a `Series` or a
`Vector`, exactly as a target does.

### Who supports them, and who says no

| estimator | weighted | how |
| --- | --- | --- |
| `LinearRegression` | yes | weighted least squares — rows and targets scaled by `sqrt(w)` through the same Householder QR; ridge inherits it as `(X^T W X + alpha*I') beta = X^T W y` |
| `LogisticRegression` | yes | weighted gradient: `sum_i w_i (p_i - t_i) x_i`, over `sum(w)` |
| `GaussianNB` | yes | weighted priors, means and variances (`class_counts` becomes total weight) |
| `DecisionTreeClassifier` | yes | weighted impurity, weighted split scoring, heaviest-class leaves |
| `DecisionTreeRegressor` | yes | weighted MSE, weighted-mean leaves |
| `KMeans` | yes | weighted centroids and weighted inertia; zero-weight rows never seed a centroid but are still labelled |
| `KNNClassifier` | **no** | `fit` returns nil rather than ignoring them |

`KNNClassifier` follows scikit-learn, whose `KNeighborsClassifier` has no
`sample_weight` either: `fit` stores the training set unchanged, so there
is nowhere for a weight to be absorbed, and weighting the neighbour VOTE
would be a different algorithm (sklearn's `weights=`, a hyperparameter
over distance). Rather than silently ignore them, `fit` answers nil and
`supports_sample_weight?` says so up front — the weights twin of
`supervised?`, and machine-readable for the same reason:

```tungsten
KNNClassifier.new(3).supports_sample_weight?     # => false
LinearRegression.new.supports_sample_weight?     # => true
Pipeline.new([Scaler.new(:standard), KNNClassifier.new(1)])
  .supports_sample_weight?                       # => false (delegates to the tail)
```

Its `score` still takes weights — a weighted accuracy is well defined
whatever produced the labels, which is scikit-learn's split too.

### Weighted metrics

`Metrics.accuracy`, `precision`, `recall`, `f1`, `fbeta`, `mse`, `rmse`,
`mae` and `r2` all take an optional trailing weight vector, matching
scikit-learn's semantics — otherwise `score(x, y, w)` would have nothing
to compute. `r2` weights its BASELINE as well as its residuals (the
weighted mean of `y`, not the plain one); the classification metrics turn
each confusion cell into a sum of weights. An unusable vector returns
nil.

```tungsten
Metrics.accuracy([1, 0, 1], [1, 0, 0], [2, 1, 1])   # => 0.75
Metrics.r2([1, 2, 3], [1, 2, 4], [2, 1, 1])         # => 0.833333
```

### Through the generic tooling

Weights ride the contract, so `CrossValidation` and `GridSearch` thread
them with no new concept: `Estimator.fit_model` /
`.score_model` grew one optional argument, and a fold's weight vector is
that fold's indices applied to the full one (`Estimator.subset`, in the
fold's own index order).

```tungsten
CrossValidation.cross_val_score(model, x, y, 5, nil, w)
CrossValidation.cross_val_mean(model, x, y, StratifiedKFold.new(3), nil, w)
GridSearch.new(DecisionTreeClassifier.new, { max_depth: [1, 2] }, 3).fit(x, y, w)
Pipeline.new([Imputer.new(:mean), LinearRegression.new]).fit(x, y, w)
```

The splitter never sees the weights — a fold is chosen by position, class
or group, never by importance — so a weighted run splits identically to
an unweighted one and differs only in what each fold learns and reports.
An estimator that refuses weights fails every fold's fit and scores nil
throughout: loudly wrong rather than quietly unweighted.

**Two limits, stated rather than hidden.** A `Pipeline` passes weights to
its ESTIMATOR TAIL only — `Scaler` and `Imputer` are fitted unweighted,
because neither takes a weight vector yet (scikit-learn's
`StandardScaler` does). And a tree's `min_samples_split` /
`min_samples_leaf` still count ROWS, matching scikit-learn (which spells
the weighted version `min_weight_fraction_leaf`, a separate knob), so
they are the one place a weighted fit and its duplicated twin can
legitimately differ — and only when those knobs are moved off their
defaults.

## Decision trees

`DecisionTreeClassifier` is koala's non-parametric, piecewise-constant
learner. Where `LinearRegression` fits one global hyperplane,
`KNNClassifier` defers everything to query time, `LogisticRegression`
iterates to a single boundary and `GaussianNB` assumes a generative
Gaussian per class, a tree recursively cuts the feature space with
axis-aligned half-planes (`x[j] <= t`) and predicts a constant inside each
box. It needs no scaling, no distance metric and no learning rate, it is
multiclass from the start — and, unlike every other estimator here, the
fitted model is **readable**.

### The algorithm (CART, greedy, top-down)

At each node, over every feature and every candidate threshold, the rows
split into `x[j] <= t` and `x[j] > t`, scored by the impurity decrease:

```
gain = imp(node) - (n_left/n) * imp(left) - (n_right/n) * imp(right)
```

The best-gaining split is taken and both sides recurse. `criterion`
selects the impurity:

| criterion | formula | estimator |
| --- | --- | --- |
| `:gini` (default) | `1 - sum_c p_c^2` | DecisionTreeClassifier |
| `:entropy` | `-sum_c p_c log2 p_c` | DecisionTreeClassifier |
| `:mse` (default) | population variance | DecisionTreeRegressor |

They are genuinely different objectives, not a relabelling. On four rows
of four distinct classes, entropy takes the balanced middle split
outright (gain 1 bit) while gini ties across two candidates and keeps the
lower threshold.

Candidate thresholds are the **midpoints between adjacent DISTINCT sorted
values** of that feature inside that node (scikit-learn's rule). Midpoints
put the boundary in the gap, so a query landing between two training
values is classified by the nearer side; taking only distinct values means
a **constant feature offers no threshold at all** rather than a degenerate
empty split.

A node becomes a leaf when it is pure, when `n < min_samples_split`, when
`depth == max_depth`, or when no admissible split exists. Its prediction
is the majority class (classifier) or the mean target (regressor).

### Determinism is a guarantee, and the tie-break rule is documented

There is no bootstrap, no feature subsampling and no seed: the fitted tree
is a **pure function of the training data**, identical run to run and
engine to engine. The one place a choice could wobble is a tie in gain, so
the rule is stated and enforced:

> Features are scanned in **ascending index** order, and each feature's
> thresholds in **ascending value** order; a candidate replaces the
> incumbent only when it is **strictly** better. Ties therefore break to
> the **lowest feature index**, then to the **lowest threshold**.

"Strictly better" is measured against a *relative* tolerance
(`gain > best + imp(node)/1e12`), so two mathematically equal gains
reached by different summation orders cannot swap the winner on a
last-bit difference.

A **zero-gain split is still taken** when it is the best on offer
(scikit-learn's `min_impurity_decrease = 0.0`). That is what lets a tree
learn XOR: no single axis-aligned cut of `[[0,0],[0,1],[1,0],[1,1]]`
improves gini at all, but splitting anyway lets the two children separate
it perfectly at depth 2. Only the *absence* of any admissible split makes
a leaf.

### The fitted tree is an inspectable structure

A node is a plain hash, and an internal node holds its children directly —
so you can assert the fitted shape, not just its predictions:

```tungsten
model = DecisionTreeClassifier.new
model.fit([[0, 0], [1, 0], [0, 10], [1, 10]], [:lo, :lo, :hi, :hi])

model.tree[:feature]             # => 1        the split feature
model.tree[:threshold]           # => 5        midpoint of 0 and 10
model.tree[:impurity]            # => 0.5      gini before the split
model.tree[:gain]                # => 0.5      what the split bought
model.tree[:n]                   # => 4        rows that reached this node
model.tree[:left][:prediction]   # => :lo      the `<=` child
model.tree[:left][:counts]       # => [2, 0]   rows per class, `classes` order

model.depth                      # => 1   edges to the deepest leaf
model.node_count                 # => 3
model.leaf_count                 # => 2
model.tree_lines.join("\n")
# x1 <= 5
#   leaf: lo (n=2)
#   leaf: hi (n=2)
```

`predict_proba` is that leaf's class distribution, `counts / n`, so it
pairs with `Metrics.roc_auc` and `Metrics.log_loss` exactly as
`GaussianNB`'s does — `predict_proba(x, label)` hands over the flat
column.

### Hyperparameters — all four are real, tunable `params`

| param | default | meaning |
| --- | --- | --- |
| `max_depth` | `nil` | unlimited; `0` = a single leaf, `1` = a decision stump |
| `min_samples_split` | `2` | a node smaller than this is never split |
| `min_samples_leaf` | `1` | a split leaving a side smaller than this is inadmissible |
| `criterion` | `:gini` / `:mse` | see the table above |

`min_samples_leaf` can *change the answer*, not merely prune: on
`x = 0,1,2,3` with `y = 0,0,0,1` the perfect split at 2.5 leaves one row
on the right, so a floor of 2 rejects it and the weaker 1.5 split (gain
0.125) is taken instead. Both floors are clamped to their legal minimum in
the **constructor**, so `params` always reports the value actually in
force and `m.with_params(m.params)` is the identity.

Because they are ordinary `params`, they round-trip through `with_params`
and the rest of koala tunes them with no code aware trees exist:

```tungsten
gs = GridSearch.new(DecisionTreeClassifier.new, { max_depth: [1, 2, 3] }, 4)
gs.fit(x, y)
gs.best_params                   # => { max_depth: 1 }
gs.best_estimator.depth          # => 1

pipe = Pipeline.new([[:scale, Scaler.new(:standard)],
                     [:tree, DecisionTreeClassifier.new(2)]])
pipe.params["tree.max_depth"]    # => 2   dotted, alongside "scale.kind"
```

An unknown criterion makes `fit` return `nil` rather than silently
falling back — `:gini` on a regressor and `:mse` on a classifier are both
refused. Everything else follows the bit's convention: an empty `x`, a
ragged `x`, a `y` whose size mismatches, a query row of the wrong width,
or any call before a successful fit returns `nil` and never raises.

### DecisionTreeRegressor

The same machinery with variance as the criterion and the mean target at
each leaf, so `score` is R² and `CrossValidation` / `GridSearch` rank it
exactly like `LinearRegression`. Predictions are **piecewise constant** —
a fully grown tree interpolates nothing, it memorizes the training means
of its boxes, which is precisely why `max_depth` is worth searching:

```tungsten
rt = DecisionTreeRegressor.new(1)          # a stump on y = 2x, x = 0..3
rt.fit([[0], [1], [2], [3]], [0, 2, 4, 6])
rt.predict([[0], [1], [2], [3]])           # => [1, 1, 5, 5]
rt.score([[0], [1], [2], [3]], [0, 2, 4, 6])  # => 0.8   (SS_res 4 of SS_tot 20)
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

## Cross-validation splitters

A cross-validation score is only as honest as the folds it averages, and
plain `KFold` — contiguous blocks of `0...n` — is honest about far less
than it looks. `lib/cross_validation.w` carries six splitters, each
answering one shared contract, and `cross_val_score` takes any of them
in the same argument that used to take a fold count.

| Splitter | What it guarantees | The leak it closes |
| --- | --- | --- |
| `KFold.new(k, seed)` | k contiguous folds, sklearn's fold sizes | — (the baseline) |
| `StratifiedKFold.new(k, seed)` | every fold keeps each class's proportion | a fold with **none** of a class |
| `LeaveOneOut.new` | n folds, one held-out row each | small-n bias (the k = n limit) |
| `GroupKFold.new(k, groups)` | a group is never split across a fold | training on the **same subject** you test |
| `TimeSeriesSplit.new(k, gap)` | train is a prefix, test the block after | **reading tomorrow's newspaper** |
| `ShuffleSplit.new(reps, pct, seed)` | reps independent random hold-outs | too few / too rigid draws |

**`StratifiedKFold` is the one classification actually needs.** With
sorted or imbalanced labels, KFold's contiguous folds are a trap: for
`y = [0,0,0,0,0,0,1,1,1]` and `k = 3` the third fold tests **only** class
1 while training on **zero** examples of it, and nothing warns you. Run
1-NN on two well-separated clusters through both and the fold scores are
`[1, 1, 0]` under `KFold` and `[1, 1, 1]` under `StratifiedKFold` — the
difference is entirely the splitter, not the model.

Stratification deals each class's rows round-robin across the folds, but
the deal for the next class **resumes where the last one stopped**
instead of restarting at fold 0. That rotation is what keeps fold sizes
even: three classes of four into three folds gives 4/4/4, where
restarting each class at fold 0 would give a lopsided 6/3/3. Fold sizes
therefore match scikit-learn's.

### One contract: `folds(n, y)` — and why `split` differs

Every splitter answers `Splitting`: a single method `folds(n, y)`
returning `[train, test]` index pairs, or nil. That is the whole entry
fee — a splitter written **outside** koala works with `cross_val_score`
with no registration.

Each splitter also keeps its own natural `split`, and those signatures
deliberately differ, because the splitters genuinely need different
things: `KFold#split(n)`, `LeaveOneOut#split(n)`,
`TimeSeriesSplit#split(n)` and `ShuffleSplit#split(n)` need only the
sample **count**, `StratifiedKFold#split(y)` needs the **labels**, and
`GroupKFold#split(groups)` needs each row's **group**. Hiding that behind
one uniform `split(n, y, groups)` would be a lie — it would suggest
KFold consults the labels (it does not) and that stratification is free
(it is not). So the natural API stays honest about its inputs and
`folds(n, y)` is the thin adapter on top. A row's group is not its
target, so `GroupKFold` takes groups at **construction**
(`GroupKFold.new(k, groups)`), which is where `folds` reads them.

```tungsten
CrossValidation.cross_val_score(model, x, y, 5)      # a fold count — unchanged
CrossValidation.cross_val_score(model, x, y, 5, 42)  # ... seeded
CrossValidation.cross_val_score(model, x, y, StratifiedKFold.new(5))
CrossValidation.cross_val_score(model, x, y, GroupKFold.new(3, groups))
CrossValidation.cross_val_score(model, x, y, TimeSeriesSplit.new(4))
```

An integer `cv` is exactly the original behaviour; anything answering
`folds(n, y)` is used instead, and `seed` is then ignored (a splitter
carries its own seeding, and a second seed here could only contradict
it). The test is behavioural — `respond_to?("folds")` — the same
duck-typing `Estimator.frame` uses, because `type(obj)` on an instance
returns `"Hash"` interpreted and could not tell a splitter from a hash.
Because `GridSearch` hands its `k` straight through,
`GridSearch.new(est, grid, StratifiedKFold.new(3))` searches on
stratified folds with **no change to `lib/grid_search.w`**.

An unsupervised model may still be given a `y`: the estimator never sees
it (`Estimator.fit_model` passes `fit(rows)` on its own arity), but the
**splitter** does — which is what lets a clustering run be stratified by
a label it is not allowed to learn from.

### Determinism, and nil for degenerate input

Same inputs and same seed give byte-identical folds on **both engines**.
Three rules make that true: classes and groups are collected in
**first-appearance** order by scanning the rows (a hash is used only for
O(1) lookup, keyed by `label.to_s`, and `.keys` is never enumerated,
because its order differs between engines); ordering uses hand-rolled
**stable** sorts, never `Array#sort`; and all shuffling goes through the
one MINSTD generator in `Splitter.indices`. `ShuffleSplit` derives each
repetition's seed by **advancing** that stream rather than using
`seed + r`, whose MINSTD orbit would be nearly identical.

No splitter ever raises. nil comes back for `k < 2`, `k > n`, a `y` or
`groups` length that disagrees with `n`, a class with fewer than `k`
members (`StratifiedKFold` will not pretend a split is stratified when
one class cannot reach every fold), fewer than `k` distinct groups, too
few rows for `k + 1` time blocks, and a percentage that rounds to an
empty test or empty train set. A stratified request without labels is
nil too — quietly *un*stratifying it is the bug the class exists to
prevent.

`spec/cross_validation_spec.w` asserts exact fold membership for every
hand-computed case above, the class proportions in every fold, and the
KFold-vs-StratifiedKFold contrast end to end.

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

## Model persistence

A fitted model used to die with the process. `Persist` (lib/persist.w)
turns one into text and back:

```tungsten
pipe = Pipeline.new([Scaler.new(:standard), LinearRegression.new])
pipe.fit(x_train, y_train)

text = Persist.dumps(pipe)          # a self-contained String
# ... store `text` wherever you like ...
served = Persist.loads(text)        # a fitted Pipeline, ready to predict

served.predict(x_test)              # exactly what `pipe` would have said
```

Every fitted koala object round-trips: every estimator, the
transformers, and a `Pipeline` of any of them nested to any depth —
including a decision tree's recursive node structure, which needs no
special case because a node is a plain hash and the format encodes
hashes.

**The guarantee is exactness.** A loaded model predicts *identically* to
the saved one, element for element — not to a tolerance. That is what
decides the format. `Float#to_s` prints six significant digits on both
engines, so `(1.to_f / 3.to_f).to_s.to_f` is **not** the value it came
from, and there is no printf-style formatter here to ask for more. A
decimal payload — and therefore a JSON one — would silently round every
coefficient and move every tree threshold, and a threshold that moves by
one ulp routes a query row down the other branch and predicts a
different *label*. So a float is written as its own bits:

```
koala-model 1
o LinearRegression
h 3
y alpha
i 0
y coefficients
a 1
b 0 2 134217727 67108861     # (-1)^0 * (hi/2^27 + lo/2^53) * 2^2
y intercept
b 1 2 111848106 44739235
```

The mantissa is normalized by exact halving and split across two
integers because the interpreter's integers are 48-bit and a 53-bit
mantissa does not fit in one. A value whose short decimal *provably*
round-trips (checked, not assumed) stays readable as `d 2.5` instead.

Hash keys are emitted sorted, so **a payload is byte-identical on both
engines** — a model trained under the interpreter loads under the
compiler and predicts the same thing.

There are **no file helpers**, deliberately: `File` and `IO` are
undefined on the interpreter and exist only compiled, so a
`Persist.save(model, path)` would work on one engine and raise on the
other. Writing the string is the caller's job. A payload that picked up
a trailing newline on the way through a file still loads.

Nothing raises. `dumps` answers nil for an **unfitted** model (there is
no state to write) and for anything that is not a koala model; `loads`
answers nil for a missing or unknown version stamp, an unknown class
name, truncated input, trailing junk, and a state that does not carry
what its class needs — which is the guard that stops a payload written
by a *different* estimator from loading as a model that quietly answers
predictions:

```tungsten
Persist.dumps(LinearRegression.new)                  # => nil, never fitted
Persist.loads("garbage")                             # => nil
Persist.loads(lin_text.split("o LinearRegression")
                      .join("o KNNClassifier"))      # => nil, not mis-loaded
```

See `spec/persist_spec.w` for the fit / dump / load / compare proof on
every estimator, on both engines.

## Regularized linear models: Lasso and ElasticNet

`LinearRegression` already carries OLS (`alpha = 0`, Householder QR) and
ridge (`alpha > 0`, an L2 penalty on the normal equations); both are
closed-form because L2 is differentiable everywhere. `Lasso` (L1) and
`ElasticNet` (L1 + L2) complete the family with the one thing ridge
cannot do. L1 is not differentiable at zero, and that kink is the whole
point: it makes the optimum *land on* zero for a whole set of
coefficients rather than merely near it. Ridge hands an irrelevant
feature a small nonzero slope forever; lasso hands it 0, and the feature
is gone. That is feature **selection**, a genuinely different capability
from shrinkage — which is why it is its own estimator and not another
branch of `LinearRegression`.

### Where ridge shrinks, lasso selects

On a design whose second feature is unrelated scatter, `alpha = 0.2`
drives that coefficient to *exactly* zero while the signal survives —
where ridge at the equivalent strength only shrinks it:

```tungsten
x = [[1, 5], [2, 3], [3, 8], [4, 1], [5, 9], [6, 2], [7, 6], [8, 4]]
y = [3, 5, 8, 9, 11, 14, 15, 17]                # feature 1 is noise

Lasso.new(1.to_f / 5.to_f).fit(x, y).coefficients               # => [1.9619, 0]
LinearRegression.new(8.to_f / 5.to_f).fit(x, y).coefficients[1]  # => 0.0074742
```

The zero is a literal `0.to_f`, not a small number that prints as zero —
`spec/regularized_linear_spec.w` asserts `== 0.to_f`, exactly. The
surviving coefficient is `1.96190476190476`, scikit-learn's value to
twelve digits; ridge at the same effective strength (koala's ridge alpha
is `n * alpha = 8 * 0.2 = 1.6`) leaves the junk feature at
`0.00747420194811457` — smaller than OLS, still there, and still there
for every alpha short of infinity. Shrinkage is not selection.

### The algorithm, and what `alpha` means

The solver is cyclic coordinate descent with soft-thresholding: holding
every other coefficient fixed, the objective in one coefficient is a
one-dimensional quadratic plus `lambda * |w_j|`, whose exact minimizer is
a closed-form soft-threshold. There is no learning rate, no step size, no
random coordinate order and no seed, so a fit is determinate and
byte-identical on both engines. The intercept is never penalized: `x`
and `y` are centered by their (weighted) means, descent runs with no
intercept column, and the bias is read back afterwards — the closed-form
elimination of an unpenalized intercept, not an approximation.

The objective is scikit-learn's term for term, *including* the
`1/(2 n_samples)` on the data-fit half, so koala's `alpha` means exactly
what scikit-learn's does and every reference number in the spec is a
scikit-learn 1.9 value. It does **not** mean the same thing as ridge's
alpha, because ridge does not scale its data term. Multiplying the
ElasticNet objective through by `2W` gives the exact bridge:

    ElasticNet.new(a, 0)  ==  LinearRegression.new(n * a)

with `n` the sample count (`W`, the total sample weight, when weighted) —
scikit-learn's own relationship between its `ElasticNet` and `Ridge`, and
the spec asserts both halves agree with sklearn. `Lasso.new(a)` is
`ElasticNet.new(a, 1)` running the identical solver; `Lasso` exists for
its name, its l1_ratio-free `params` surface and its persist tag, exactly
as scikit-learn's `Lasso` is an `ElasticNet` pinned at `l1_ratio = 1`.

### p > n, and what is refused

`fit` returns nil — never raises — for an empty or ragged `x`, a
mismatched `y`, an unusable weight vector, a negative `alpha`, an
`l1_ratio` outside `[0, 1]`, `max_iter < 1`, or a negative `tol`. It does
**not** refuse collinear features or fewer samples than features: with
`alpha > 0` the penalized objective is strictly convex where it matters,
and `p > n` is the case lasso was invented for — where OLS must return
nil, lasso answers a sparse fit (one surviving feature of five, in the
spec's `p > n` case). `sample_weight` is exact: an integer weight vector
is the same model as duplicating each row that many times, because the
`1/(2W)` normalization divides by the total weight, not the row count.

## Random forests

`RandomForestClassifier` and `RandomForestRegressor` are koala's first
**ensemble** learners: where `lib/decision_tree.w` grows one CART tree, a
forest grows many and averages them. A fully grown tree has low bias and
enormous variance — it will carve a box around a single mislabelled row —
and variance is exactly what averaging destroys. But averaging *identical*
trees destroys nothing, so the trees have to disagree, and a forest
manufactures disagreement twice:

- **bootstrap** — each tree is grown on `n` rows drawn with replacement
  from the `n` training rows, so each sees a different ~63% of them;
- **per-split feature subsampling** — at *every* node, only a random
  `max_features`-sized subset of the features is even considered.

The second is what makes it a forest rather than N copies. Bagging alone
leaves one dominant feature at the root of nearly every tree, so the
trees stay correlated and the mean barely moves; hiding that feature from
a random majority of the nodes forces the weaker features into play, and
decorrelated errors are what a mean can actually cancel.

### The bootstrap is a `sample_weight` vector

Drawing row `i` exactly `n_i` times and fitting is, for this tree
machinery, the *identical* tree that `sample_weight[i] = n_i` produces —
every weighted term is the unweighted term times an integer (koala's
definition of weight correctness). So a resample costs one float vector
rather than a copy of the data, the caller's own `sample_weight` composes
by simple multiplication, and the rows drawn *zero* times fall out as
that tree's **out-of-bag** set for free. Predicting each row with only
the trees that did not see it gives `oob_score` — a held-out accuracy
(classifier) or R² (regressor) over the whole training set with no split,
no second fit and no cross-validation loop. It is nil when nothing was
left out (`bootstrap: false`).

### One tree, node for node

Switch off *both* sources of randomness and grow a single tree, and the
result is not merely similar to a `DecisionTreeClassifier` — it is the
same tree, node for node, because it runs the same `DecisionTree.build`
over the same config:

```tungsten
RandomForestClassifier.new(1, :all, nil, 1, 0, nil, false)
# ... predicts exactly what DecisionTreeClassifier.new does
```

`spec/random_forest_spec.w` asserts that against the *rendered* tree, not
just the predictions: if bagging, subsampling and averaging are wired
correctly, turning them all off has to land back on the tree they were
built from. On noisy training data scored against a clean test set the
ensemble earns its keep — the classifier goes `0.75 → 0.875` and the
regressor R² `0.419 → 0.597` against their own single deep tree, which
memorizes the flipped rows a forest votes away.

### Hyperparameters (seven, all tunable `params`)

`n_estimators`, `max_features`, `max_depth`, `min_samples_leaf`, `seed`,
`criterion` and `bootstrap`. `max_features` is a symbol or an integer,
never a fraction — `:sqrt` (the classifier default), `:log2`, `:all`
(plain bagging, and the regressor default), or a count clamped to
`1..n_features` — because a float hyperparameter cannot survive `params`,
`with_params`, a grid search and a Persist payload by decimal text, and
the symbols mean what scikit-learn's strings mean. Every draw comes from
one seeded MINSTD stream (the one `Splitter` and `KFold` use), so the same
seed and rows give a byte-identical forest — same thresholds, same
predictions, same payload — on both engines; a nil seed is the fixed
default stream, not entropy, because a forest nobody can reproduce is not
a model. `min_samples_leaf` is clamped in the constructor so
`with_params(params)` is the identity, while `n_estimators < 1`, an
unknown `criterion` or an unknown `max_features` make `fit` return nil
rather than silently fall back. They round-trip through `with_params`, so
`GridSearch` tunes them and a `Pipeline` exposes them as
`"forest.n_estimators"`.

## Principal component analysis

`PCA` is koala's dimensionality reduction — a *transformer*, so it slots
into a `Pipeline` ahead of any estimator. `fit` mean-centers the data and
extracts the top-k orthonormal directions of greatest variance;
`transform` projects rows onto them into a DataFrame of `pc0, pc1, …`.

### One-sided Jacobi, not the covariance

The textbook route forms the covariance `C = X_c^T X_c / (n - 1)` and
eigendecomposes it — and that is the trap the Householder least-squares
work already escaped in `lib/linalg.w`. Forming `X^T X` squares the
condition number: a design with `cond(X) = 1e6` hands the eigensolver a
matrix at `1e12` and burns twelve of f64's ~sixteen digits before the
first rotation, and the damage lands exactly on the small trailing
components PCA exists to reveal. So koala applies the orthogonalization to
`X_c` *itself* — one-sided Jacobi, the classical high-relative-accuracy
SVD (Demmel & Veselić): plane rotations sweep across pairs of columns
until every pair is orthogonal, the singular values come out as the
converged column norms, and squaring happens only inside the choice of a
rotation angle, never in a reported quantity.

That is measured, not asserted. `spec/pca_spec.w` fits a design whose two
variances are 18 decades apart: forming the covariance rounds the smaller
back to *exactly zero*, while one-sided Jacobi on the same f64 data
recovers it to about eight significant digits — eight correct digits
against none, on both engines. Jacobi also survives rank deficiency where
a non-pivoting QR (`LinAlg.qr`) returns nil: a constant column, a
duplicated feature and a rank-1 cloud are ordinary inputs, a dependent
column simply converges to a zero norm, and the components stay *exactly*
orthonormal at any rank because they are a product of plane rotations on
the identity.

### Signs, variances, and whitening

An eigenvector is defined only up to sign, so an unpinned sign falls out
of whatever rounding the rotations produced and differs run to run. koala
pins it on the *loadings*: every component is negated, if needed, so its
largest-magnitude entry is positive (ties to the lowest index). Because
the rule reads only `components`, not the sample order, a re-fit on
shuffled rows is bit-identical. (scikit-learn pins the sign on the scores
instead; the two agree on most data and are exact negations where they
differ — documented, and the spec compares against sklearn with koala's
rule applied.)

`explained_variance` is `sigma^2 / (n - 1)`, the same denominator
`Stats.var` and scikit-learn use, so an axis-aligned dataset reports its
own column variances. `explained_variance_ratio` divides by the *whole*
trace — the variance over all `min(n, p)` components — so a full-rank
fit's ratios sum to 1 and a truncated fit reports the fraction of the
original variance it kept. `whiten: true` divides each score column by
`sqrt(explained_variance)` for unit-variance, decorrelated output, and
`inverse_transform` undoes it exactly (a zero-variance component is left
alone, never divided by zero).

```tungsten
pca = PCA.new(2)
scores = pca.fit_transform([[0 - 2, 1], [0 - 1, 0 - 1], [0, 0], [1, 0 - 1], [2, 1]])
scores.column_names               # => ["pc0", "pc1"]
pca.explained_variance            # => Vector [2.5, 1]
pca.explained_variance_ratio      # => Vector [0.714286, 0.285714]
```

`n_components` is the one tunable knob; `params` reports it and `whiten`,
while the mean, components and variances answer to `learned_params`,
because `params` means "what you set" everywhere in koala. A PCA named
`:pca` in a chain therefore contributes `"pca.n_components"` /
`"pca.whiten"` to a `GridSearch` with no code in `pipeline.w` or
`grid_search.w` aware PCA exists.

## Density clustering: DBSCAN

`DBSCAN` is koala's second unsupervised learner, after `KMeans`, and its
complement. `KMeans` needs `k` up front, minimizes squared distance to
`k` centroids — so it can only carve space into `k` *convex* cells — and
forces every row into a cluster, so one far point drags a centroid and
there is no way to say "noise". DBSCAN drops all three assumptions: it
grows clusters by **density** (a region is a cluster when points are
packed closely enough, whatever *shape* it has), discovers the cluster
count from the data, and labels anything not dense enough `-1`. The price
is a different pair of knobs — `eps` (how close counts as close) and
`min_samples` (how many neighbours make a region dense) — and no notion
of a cluster centre at all. `eps` has no default on purpose: it is the one
number DBSCAN's behaviour turns on, and scikit-learn's `0.5` is wrong for
almost every dataset.

### The case KMeans cannot solve

Two concentric rings share a centroid, so no assignment of ring-to-cluster
is a k-means fixed point — the two centroids would coincide and every
distance would tie — and KMeans provably slices *across* both rings
instead. DBSCAN separates them exactly, because each ring is
density-connected to itself and to nothing else. The honest caveat,
asserted in `spec/dbscan_spec.w` rather than hidden: the silhouette
rewards compact, roughly spherical clusters, so on the rings it *prefers*
the wrong answer — it scores KMeans's slicing split `0.295` over DBSCAN's
correct inner/outer split `0.083`. `score` is a defensible default
objective (a real internal index, so `eps` and `min_samples` are
searchable), not an oracle.

```tungsten
rows = [[0, 0], [0, 1], [1, 0], [1, 1], [10, 10], [10, 11], [11, 10], [11, 11], [50, 50]]
db = DBSCAN.new(2, 3)                     # eps = 2, min_samples = 3
db.fit_predict(rows)                      # => [0, 0, 0, 0, 1, 1, 1, 1, -1]
db.n_clusters                             # => 2   discovered, not supplied
db.core_sample_indices                    # => [0, 1, 2, 3, 4, 5, 6, 7]
```

### Determinism, and two documented sklearn divergences

DBSCAN's output is famously order-sensitive on *border* rows — a non-core
row inside two clusters' reach could go either way. koala pins it: cluster
numbering follows the ascending index of each component's first core
sample, and a border row joins the **lowest-numbered** adjacent cluster
(scikit-learn's answer too, stated as a rule about the output). Core
samples are never ambiguous, so a fit is a pure function of the row order,
byte-identical across runs and engines; permuting the input rows may move
a border row, exactly as in scikit-learn.

Two deviations from scikit-learn are deliberate and spec'd:

- **`predict` is defined**, where scikit-learn offers only `fit_predict`.
  A density model has no natural out-of-sample rule, so rather than fake
  one, koala states it: each row goes to the cluster of the nearest core
  sample within `eps`, else `-1`. A training core or noise row always
  agrees with `labels`; a border row can disagree (`fit` gives it the
  lowest-numbered adjacent cluster, `predict` the nearest), and that gap
  is called out rather than hidden. `fit_predict` returns the real DBSCAN
  answer for the training set and is the method to use there.
- **A zero-weight row can never be core.** A weight is how many times a
  row counts toward a neighbourhood, so an integer vector equals row
  duplication. scikit-learn derives core-ness from the weighted sum alone,
  so a weight-0 row can still be core and bridge two clusters into one —
  which the dataset with that row *deleted* would never do. koala refuses
  that: a row not in the sample must not change the answer, so weight 0
  drops the row (though it is still labelled, one entry per input row).
  With all-positive weights the two agree byte for byte.

`metric` is `"euclidean"` (default), `"manhattan"` or `"chebyshev"`, a
real hyperparameter a search can vary; euclidean stays on squared
distances so integer inputs are exact. An empty or ragged `x`, `eps <= 0`,
`min_samples < 1`, an unknown metric or an unusable weight vector make
`fit` return nil.

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
CPU-only; ops with a shape requirement return nil when it is not met;
square systems go through Gaussian elimination with partial pivoting —
`det` / `solve` / `inv` — while least squares goes through Householder
QR: `qr` returns the reduced factorization `{ q:, r: }` with `q`'s
columns orthonormal and `q.matmul(r)` the input, and `lstsq(b)` solves
the overdetermined system by back substitution through `r`. QR never
forms `X^T X`, so it does not square the condition number the way the
normal equations do — on the clustered Vandermonde design in
`spec/linalg_spec.w` that is a max coefficient error of 6.9e-11 against
the normal equations' 5.3e-4, seven orders of magnitude. Householder
reflections rather than Gram-Schmidt: each reflection is exactly
orthogonal to working precision, which is the property that survives
badly clustered columns. This QR is not rank-revealing — there is no
column pivoting — so a numerically dependent column returns nil rather
than being worked around, with `LinAlg.rank_tol` (1e-12, relative to
the column norm) separating "dependent" from "merely ill-conditioned"
with six decades of margin either side),
ML preprocessing: `Scaler`, `Encoder`, `Imputer`, `Splitter`,
`Pipeline` (fit/transform with per-instance fitted state; transform
before fit returns nil; steps may be named as `[name, step]` pairs and
addressed with `step(:name)` / `names` / `has_step?` alongside the
positional `pipe[i]`, and a Pipeline itself answers `Estimable`, so its
steps' hyperparameters flatten to `"step.param"` keys a generic search
can tune — see *Pipelines* above; splitting is deterministic — unseeded calls
keep row order, and the seeded shuffle is a built-in MINSTD generator,
so the same seed gives the same split on both engines; `test_pct` is an
integer percent), and estimation: `LinearRegression` (least squares
with an internal intercept column, through one of two solvers chosen by
alpha: plain OLS (alpha = 0, the default) runs `LinAlg.lstsq` —
Householder QR on the design matrix itself, so an ill-conditioned
design keeps roughly twice as many correct digits as the normal
equations would — while `new(alpha)` with alpha > 0 adds ridge
regularization on the penalized normal equations through
`LinAlg.solve`, where alpha lands on every X^T X diagonal entry except
the intercept's. Ridge stays on that route deliberately: the penalty is
*defined* on X^T X, and it is what makes the system positive definite.
So alpha > 0 fits even collinear features, and the bias is never shrunk;
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
`actual` are misaligned or empty.

**When the classes are IMBALANCED, accuracy lies.** A classifier that
always answers the majority class scores 0.8 on a 4:1 split while having
learned nothing, and `f1` — which never looks at the true negatives —
can be talked up the same way. Four metrics say what actually happened.
`Metrics.fbeta(predictions, actual, beta, pos_label)` is `f1` with a
knob: `(1+β²)PR / (β²P+R)`, where β is how many times as much a unit of
recall is worth as a unit of precision — β = 2 when a MISSED positive is
the expensive error (fraud, screening), β = ½ when the false alarm is,
β = 1 exactly `f1` and β = 0 exactly `precision`.
`Metrics.balanced_accuracy` is the unweighted mean of the per-class
recalls, so every class counts the same however rare it is and the
majority-class classifier lands on its true 0.5 rather than 0.8; it is
the `ClassificationReport`'s macro recall, exposed as a scalar.
`Metrics.matthews_corrcoef` (MCC) is the correlation between the
predicted and the true labels, in `[-1, 1]` — 1 perfect, 0 chance, -1
inverted — and is the metric of choice for imbalanced binary problems
because ALL FOUR confusion cells enter it symmetrically, so no amount of
majority class can inflate it. `Metrics.cohen_kappa` answers the related
question "how much of this accuracy was EARNED?", discounting the
agreement two independent labelers with these class frequencies would
reach by chance: `(p_o - p_e) / (1 - p_e)`. All four take PREDICTIONS
first (the `accuracy` / `precision` / `f1` order), all but `fbeta` are
multiclass, and all return nil for a misaligned or empty pair. Where
scikit-learn's degenerate cases yield `nan` (a single class present),
koala emits 0 — it never returns a nan. The report gains the third
average scikit-learn offers: `rep.micro_precision` / `micro_recall` /
`micro_f1` pool every class's TP/FP/FN into ONE table and score that
once, so each SAMPLE weighs equally rather than each class; for
single-label multiclass all three provably equal the accuracy, and
`rep.micro_counts` shows the pooled `[TP, FP, FN]` they come from.

`Metrics.precision_recall_curve(scores, actual, pos_label)` returns a
`PrecisionRecallCurve` — `.precision` / `.recall` / `.thresholds` and
`.average_precision` — and **it, not the ROC curve, is the one to read
when positives are rare.** Both curves are built from the same TP/FP
counts, but ROC divides the false positives by the number of NEGATIVES,
so a large negative class dilutes them; precision divides by what the
model actually FLAGGED, which no amount of negatives shrinks. One
positive among ten, ranked second, scores a comfortable ROC-AUC of
0.888889 and an average precision of 0.5 — same data, and only the
second number is honest about the false positive. `Metrics.average_precision`
is that area directly, scikit-learn's `average_precision_score`: a STEP
sum `Σ (Rₙ - Rₙ₋₁)·Pₙ` rather than a trapezoid, since interpolating
between two PR operating points claims performance that is not
achievable. Read it against the POSITIVE RATE, which is its chance
baseline (an AP of 0.5 is excellent on a 1% positive class and terrible
on a balanced one) — not against `roc_auc`'s flat 0.5. Its layout
follows scikit-learn exactly and so differs from `RocCurve`'s: points
run in ASCENDING threshold order with a closing `(recall 0, precision 1)`
point that has no threshold, making the curve arrays one longer than
`.thresholds`. Unlike `roc_curve` it survives a single present class.
`Metrics.brier_score(scores, actual, pos_label)` is `mean((p - y)²)`,
log loss's BOUNDED sibling: both measure calibration rather than
ranking, but log loss is unbounded and one confident miss can dominate
it, while the Brier score's worst case per row is 1 — 0 perfect, 0.25 a
constant coin flip, 1 confidently wrong throughout. Two models that rank
identically (`roc_auc` 1 for both) separate cleanly under it, 0.00025
for the confident one against 0.18125 for the hedging one. Optimize log
loss; REPORT the Brier score.

Finally, `Metrics.silhouette_score(x, labels)` is koala's first
UNSUPERVISED metric, and the question `KMeans` previously could not be
asked. `KMeans` reports `inertia`, the within-cluster sum of squares —
but inertia falls monotonically as k rises, so it can rank two fits at
the SAME k and nothing more; it can never say whether a clustering is
any good, or choose k. The silhouette scores each row
`(b - a) / max(a, b)`, where a is its mean distance to the rest of its
own cluster and b the smallest mean distance to any other, and averages:
near 1 the rows sit deep inside well-separated clusters, near 0 they
straddle boundaries, and NEGATIVE means they are closer to a different
cluster than to their own — assigned wrong. Because it normalizes
cohesion by separation it is comparable across different k, which is how
k gets chosen: fit for k = 2, 3, 4, … and keep the best silhouette.

```
m = KMeans.new(3).fit(x)
Metrics.silhouette_score(x, m.labels)
```

`x` is the row data (an array of feature arrays, or a flat array of
numbers for a single feature) and `labels` the cluster assignment per
row, any values at all. Rows alone in their cluster score 0
(scikit-learn's rule — there is no within-cluster distance to compare
against), and the score is nil when the cluster count is not in
`2 .. n_rows - 1` (one cluster has nothing to separate from, n clusters
leaves every row a singleton) or the inputs do not line up.
scikit-learn raises there; koala returns nil.

A `Pipeline` whose LAST step is
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
sharing the estimators' accepted input shapes; that fourth argument also
takes a SPLITTER — `StratifiedKFold` (class proportions preserved in
every fold, the one classification needs), `LeaveOneOut`, `GroupKFold`
(no group spans train and test), `TimeSeriesSplit` (expanding window,
never trains on the future) or `ShuffleSplit` (repeated seeded
hold-outs) — anything answering `folds(n, y)`). Clustering: `KMeans`
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
