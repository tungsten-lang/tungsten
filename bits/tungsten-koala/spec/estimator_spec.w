# Estimator specs — LinearRegression (normal equations on LinAlg),
# ridge regularization (the alpha parameter), Vector/Series feature
# input, DataFrame#to_matrix, and the Pipeline estimator tail, on the
# tungsten-spec framework.
#
# Run from the repo root (both engines, exit 0 = green):
#   bin/tungsten bits/tungsten-koala/spec/estimator_spec.w
#   bin/tungsten -o /tmp/est_spec bits/tungsten-koala/spec/estimator_spec.w && /tmp/est_spec
#
# Exact-string cases are hand-computed on inputs whose Gaussian
# elimination stays binary-exact: symmetric x makes X^T X diagonal
# (x = [-3,-1,1,3] gives [[4,0],[0,20]]), and the two-feature grid
# divides only by powers of two — so whole floats print bare ("2").
# The deliberately inexact fit (slope 1.6, intercept -0.4, R² = 32/35
# — verified by hand from XtX = [[4,6],[6,14]], Xty = [8,20]) is
# compared through LinAlg.fabs against a data-derived tolerance:
# float literals do not cross method boundaries reliably interpreted,
# so every float below derives from integers via .to_f.

use spec
use koala

describe "LinearRegression" ->
  it "recovers y = 2x + 1 exactly from a flat x array" ->
    x = [0 - 3, 0 - 1, 1, 3]
    y = [0 - 5, 0 - 1, 3, 7]
    model = LinearRegression.new
    expect(model.fitted?).to be_false
    r = model.fit(x, y)
    expect(r != nil).to be_true
    expect(model.fitted?).to be_true
    expect(model.intercept.to_s).to eq("1")
    expect(model.coefficients.to_s).to eq("\[2\]")
    expect(model.predict([5, 0, 0 - 2]).to_s).to eq("\[11, 1, -3\]")
    expect(model.score(x, y).to_s).to eq("1")

  it "recovers multi-feature coefficients (y = 3 + x1 + 2*x2)" ->
    x = [[0, 0], [2, 0], [0, 2], [2, 2]]
    y = [3, 5, 7, 9]
    model = LinearRegression.new
    model.fit(x, y)
    expect(model.intercept.to_s).to eq("3")
    expect(model.coefficients.to_s).to eq("\[1, 2\]")
    expect(model.predict([[1, 1], [4, 3]]).to_s).to eq("\[6, 13\]")
    expect(model.score(x, y).to_s).to eq("1")

  it "matches the hand-computed inexact fit within tolerance" ->
    x = [0, 1, 2, 3]
    y = [0, 1, 2, 5]
    model = LinearRegression.new
    model.fit(x, y)
    tol = 1.to_f / 1000000.to_f
    slope = model.coefficients[0]
    expect(LinAlg.fabs(slope - 16.to_f / 10.to_f) < tol).to be_true
    expect(LinAlg.fabs(model.intercept - (0.to_f - 4.to_f / 10.to_f)) < tol).to be_true
    r2 = model.score(x, y)
    expect(LinAlg.fabs(r2 - 32.to_f / 35.to_f) < tol).to be_true
    expect(r2 < 1.to_f).to be_true

  it "accepts DataFrame x (numeric columns only), Series y, Matrix predict" ->
    df = DataFrame.new([
      [:name, ["a", "b", "c", "d"]],
      [:x1, [0, 2, 0, 2]],
      [:x2, [0, 0, 2, 2]]
    ])
    y = Series.new([3, 5, 7, 9], :target)
    model = LinearRegression.new
    model.fit(df, y)
    expect(model.intercept.to_s).to eq("3")
    expect(model.coefficients.to_s).to eq("\[1, 2\]")
    expect(model.predict(Matrix.new([[1, 1]])).to_s).to eq("\[6\]")
    expect(model.score(df, y).to_s).to eq("1")

  it "returns nil (and stays unfitted) for collinear features" ->
    x = [[1, 2], [2, 4], [3, 6]]
    y = [1, 2, 3]
    model = LinearRegression.new
    expect(model.fit(x, y)).to be_nil
    expect(model.fitted?).to be_false
    expect(model.coefficients).to be_nil
    expect(model.intercept).to be_nil
    expect(model.predict([[1, 2]])).to be_nil
    expect(model.score(x, y)).to be_nil

  it "accepts Vector and Series x as single-feature columns" ->
    xs = Series.new([0 - 3, 0 - 1, 1, 3], :x)
    y = [0 - 5, 0 - 1, 3, 7]
    model = LinearRegression.new
    r = model.fit(xs, y)
    expect(r != nil).to be_true
    expect(model.intercept.to_s).to eq("1")
    expect(model.coefficients.to_s).to eq("\[2\]")
    expect(model.predict(Vector.new([5, 0, 0 - 2])).to_s).to eq("\[11, 1, -3\]")
    m2 = LinearRegression.new
    m2.fit(Vector.new([0 - 3, 0 - 1, 1, 3]), Vector.new(y))
    expect(m2.coefficients.to_s).to eq("\[2\]")
    expect(m2.score(xs, y).to_s).to eq("1")

  it "returns nil for unusable shapes" ->
    model = LinearRegression.new
    expect(model.fit([[1], [2]], [1, 2, 3])).to be_nil
    expect(model.fit([], [])).to be_nil
    expect(model.fit([[1, 2], [3]], [1, 2])).to be_nil
    expect(model.fitted?).to be_false
    r = model.fit([0 - 1, 0, 1], [0, 1, 2])
    expect(r != nil).to be_true
    expect(model.intercept.to_s).to eq("1")
    expect(model.coefficients.to_s).to eq("\[1\]")
    expect(model.predict([[1, 2]])).to be_nil

describe "Ridge regression (LinearRegression alpha)" ->
  # Hand-computed exact case, alpha = 12 on the symmetric x above:
  #   X = [[1,-3],[1,-1],[1,1],[1,3]]   (all-ones intercept column)
  #   X^T X = [[4, 0], [0, 20]]         (Σx = 0, Σx² = 9+1+1+9 = 20)
  #   X^T y = [Σy, Σxy] = [4, 40]
  # Ridge penalizes ONLY the feature diagonal (never the intercept):
  #   X^T X + 12*I' = [[4, 0], [0, 32]]
  #   beta = [4/4, 40/32] = [1, 1.25]
  # Both divisions are by powers of two, so the floats are binary-exact
  # and print bare. Shrinkage is visible: the OLS slope 2 shrinks to
  # 1.25, while the (unpenalized) intercept stays exactly 1 — Σx = 0
  # keeps X^T X diagonal, decoupling it from the slope.
  it "shrinks the slope but not the intercept (alpha = 12, hand-computed)" ->
    x = [0 - 3, 0 - 1, 1, 3]
    y = [0 - 5, 0 - 1, 3, 7]
    model = LinearRegression.new(12)
    expect(model.alpha.to_s).to eq("12")
    r = model.fit(x, y)
    expect(r != nil).to be_true
    expect(model.intercept.to_s).to eq("1")
    expect(model.coefficients.to_s).to eq("\[1.25\]")
    expect(model.predict([[4]]).to_s).to eq("\[6\]")

  # The deliberately-collinear input OLS rejects, alpha = 1:
  #   x = [[1,2],[2,4],[3,6]], y = [1,2,3]
  #   X = [[1,1,2],[1,2,4],[1,3,6]]
  #   X^T X = [[3,6,12],[6,14,28],[12,28,56]]   (singular: col3 = 2*col2)
  #   X^T X + I' = [[3,6,12],[6,15,28],[12,28,57]], det = 33 — invertible
  #   X^T y = [6, 14, 28]
  # Elimination: R2-2R1 -> [0,3,4|2]; R3-4R1 -> [0,4,9|4];
  # R3-(4/3)R2 -> [0,0,11/3|4/3] => b2 = 4/11; then 3*b1 = 2 - 16/11
  # => b1 = 2/11; then 3*b0 = 6 - 12/11 - 48/11 => b0 = 2/11.
  #   beta = [2/11, 2/11, 4/11]
  #   predictions = [12/11, 2, 32/11], R² = 1 - (2/121)/2 = 120/121
  # Elevenths are not binary-exact, so compare through a tolerance.
  it "fits the collinear input that plain OLS rejects (alpha = 1)" ->
    x = [[1, 2], [2, 4], [3, 6]]
    y = [1, 2, 3]
    model = LinearRegression.new(1)
    r = model.fit(x, y)
    expect(r != nil).to be_true
    expect(model.fitted?).to be_true
    tol = 1.to_f / 1000000.to_f
    expect(LinAlg.fabs(model.intercept - 2.to_f / 11.to_f) < tol).to be_true
    expect(LinAlg.fabs(model.coefficients[0] - 2.to_f / 11.to_f) < tol).to be_true
    expect(LinAlg.fabs(model.coefficients[1] - 4.to_f / 11.to_f) < tol).to be_true
    preds = model.predict(x)
    expect(preds.size).to eq(3)
    expect(LinAlg.fabs(preds[0] - 12.to_f / 11.to_f) < tol).to be_true
    expect(LinAlg.fabs(preds[1] - 2.to_f) < tol).to be_true
    expect(LinAlg.fabs(preds[2] - 32.to_f / 11.to_f) < tol).to be_true
    expect(LinAlg.fabs(model.score(x, y) - 120.to_f / 121.to_f) < tol).to be_true

  # Fractional alpha comes from integer .to_f division (NEVER a float
  # literal — see the honesty note in linear_regression.w): alpha = 1/2
  # penalizes the symmetric system to [[4, 0], [0, 20.5]], so the slope
  # is 40/20.5 = 80/41 and the intercept stays exactly 4/4 = 1.
  it "accepts a data-derived fractional alpha" ->
    x = [0 - 3, 0 - 1, 1, 3]
    y = [0 - 5, 0 - 1, 3, 7]
    model = LinearRegression.new(1.to_f / 2.to_f)
    r = model.fit(x, y)
    expect(r != nil).to be_true
    expect(model.intercept.to_s).to eq("1")
    tol = 1.to_f / 1000000.to_f
    expect(LinAlg.fabs(model.coefficients[0] - 80.to_f / 41.to_f) < tol).to be_true

  it "defaults to alpha = 0 — plain OLS, collinear still nil" ->
    model = LinearRegression.new
    expect(model.alpha.to_s).to eq("0")
    expect(model.fit([[1, 2], [2, 4], [3, 6]], [1, 2, 3])).to be_nil
    expect(model.fitted?).to be_false

describe "DataFrame#to_matrix" ->
  it "keeps numeric columns in order and skips the rest" ->
    df = DataFrame.new([
      [:name, ["a", "b"]],
      [:x, [1, 2]],
      [:y, [3, 4]]
    ])
    m = df.to_matrix
    expect(m.to_a.to_s).to eq("\[\[1, 3\], \[2, 4\]\]")
    expect(m.shape.to_s).to eq("\[2, 2\]")
    expect(m.to_matrix.to_a.to_s).to eq(m.to_a.to_s)

  it "returns nil when no column is numeric" ->
    expect(DataFrame.new([[:s, ["a", "b"]]]).to_matrix).to be_nil

describe "Pipeline estimator tail" ->
  it "fits Scaler -> LinearRegression and predicts through the chain" ->
    df = DataFrame.new([[:x, [2, 4, 6]]])
    y = [5, 9, 13]
    pipe = Pipeline.new([Scaler.new(:standard), LinearRegression.new])
    expect(pipe.predict(df)).to be_nil
    r = pipe.fit(df, y)
    expect(r != nil).to be_true
    expect(pipe.fitted?).to be_true
    lr = pipe[1]
    expect(lr.intercept.to_s).to eq("9")
    expect(lr.coefficients.to_s).to eq("\[4\]")
    expect(pipe.predict(DataFrame.new([[:x, [4, 8]]])).to_s).to eq("\[9, 17\]")
    expect(pipe.score(df, y).to_s).to eq("1")

  it "propagates an estimator fit failure" ->
    df = DataFrame.new([[:a, [1, 2, 3]], [:b, [2, 4, 6]]])
    y = [1, 2, 3]
    pipe = Pipeline.new([Scaler.new(:standard), LinearRegression.new])
    expect(pipe.fit(df, y)).to be_nil
    expect(pipe.fitted?).to be_false
    expect(pipe.predict(df)).to be_nil
    expect(pipe.score(df, y)).to be_nil

  it "keeps transformer-only pipelines predict-free" ->
    df = DataFrame.new([[:x, [2, 4, 6]]])
    pipe = Pipeline.new([Scaler.new(:standard)])
    pipe.fit(df)
    expect(pipe.fitted?).to be_true
    expect(pipe.predict(df)).to be_nil
    expect(pipe.score(df, [1, 2, 3])).to be_nil
    expect(pipe.transform(df).column_values(:x).join(",")).to eq("-1,0,1")

describe "KNNClassifier" ->
  # Two well-separated 2-D clusters, symbol-labelled. Squared Euclidean
  # distances are exact on integer inputs, so each query's three nearest
  # are unambiguous:
  #   (2,3): (2,2) d²=1, (3,3) d²=1, (1,1) d²=5  -> all :a
  #   (7,6): (6,6) d²=1, (7,7) d²=1, (8,8) d²=5  -> all :b
  it "classifies by majority vote of the k nearest (k = 3)" ->
    x = [[1, 1], [2, 2], [3, 3], [6, 6], [7, 7], [8, 8]]
    y = [:a, :a, :a, :b, :b, :b]
    model = KNNClassifier.new(3)
    expect(model.k).to eq(3)
    expect(model.fitted?).to be_false
    r = model.fit(x, y)
    expect(r != nil).to be_true
    expect(model.fitted?).to be_true
    expect(model.predict([[2, 3], [7, 6]]).to_s).to eq("\[a, b\]")
    expect(model.score(x, y).to_s).to eq("1")

  # k defaults to 5 (scikit-learn's n_neighbors). At k = 1 the model is
  # a pure memorizer: every training row's nearest neighbour is itself
  # (distance 0), so training accuracy is exactly 1.
  it "defaults k to 5 and memorizes the training set at k = 1" ->
    expect(KNNClassifier.new.k).to eq(5)
    x = [[0], [1], [2], [10], [11], [12]]
    y = [0, 0, 0, 1, 1, 1]
    one = KNNClassifier.new(1)
    one.fit(x, y)
    expect(one.score(x, y).to_s).to eq("1")

  # A genuine 2-1 vote (query (4,4): nearest three are (3,3) and (2,2)
  # of class 0 against (6,6) of class 1 -> 0), and integer labels flow
  # straight into the binary metrics from Metrics.
  it "takes the majority label and feeds Metrics.accuracy" ->
    x = [[1, 1], [2, 2], [3, 3], [6, 6], [7, 7], [8, 8]]
    y = [0, 0, 0, 1, 1, 1]
    model = KNNClassifier.new(3)
    model.fit(x, y)
    expect(model.predict([[4, 4]]).to_s).to eq("\[0\]")
    preds = model.predict([[2, 3], [7, 6]])
    expect(Metrics.accuracy(preds, [0, 1]).to_s).to eq("1")
    expect(Metrics.accuracy(preds, [1, 1]).to_s).to eq("0.5")

  # Distance ties break to the lower training index (a strict `<` keeps
  # the first-seen minimum): (1,0):a and (0,1):b are both d²=1 from the
  # origin, so k = 1 returns :a, the earlier row.
  it "breaks distance ties toward the earlier training row" ->
    model = KNNClassifier.new(1)
    model.fit([[1, 0], [0, 1], [5, 5]], [:a, :b, :a])
    expect(model.predict([[0, 0]]).to_s).to eq("\[a\]")

  # Same accepted shapes as LinearRegression, through the shared
  # feature_rows / target_values: DataFrame (numeric columns only —
  # :name is skipped), Series/Vector single-feature columns.
  it "accepts DataFrame, Series and Vector inputs" ->
    df = DataFrame.new([
      [:name, ["p", "q", "r", "s"]],
      [:f1, [0, 0, 9, 9]],
      [:f2, [0, 1, 9, 8]]
    ])
    labels = Series.new([:lo, :lo, :hi, :hi], :cls)
    model = KNNClassifier.new(1)
    model.fit(df, labels)
    test = DataFrame.new([[:name, ["t", "u"]], [:f1, [1, 8]], [:f2, [0, 9]]])
    expect(model.predict(test).to_s).to eq("\[lo, hi\]")
    expect(model.score(df, labels).to_s).to eq("1")
    xs = Series.new([0, 1, 2, 20, 21, 22], :x)
    ms = KNNClassifier.new(3)
    ms.fit(xs, [0, 0, 0, 1, 1, 1])
    expect(ms.predict(Vector.new([1, 21])).to_s).to eq("\[0, 1\]")

  # Unusable shapes and premature calls all return nil and leave fitted?
  # false — the bit's shape-error convention, matching LinearRegression.
  it "returns nil for unusable shapes and before fit" ->
    model = KNNClassifier.new(3)
    expect(model.predict([[1, 2]])).to be_nil
    expect(model.score([[1, 2]], [0])).to be_nil
    expect(model.fit([], [])).to be_nil
    expect(model.fit([[1, 2], [3]], [0, 1])).to be_nil
    expect(model.fit([[1], [2]], [0, 1, 2])).to be_nil
    expect(model.fitted?).to be_false
    r = model.fit([[1, 2], [3, 4]], [:x, :y])
    expect(r != nil).to be_true
    expect(model.predict([[1]])).to be_nil

spec_summary
