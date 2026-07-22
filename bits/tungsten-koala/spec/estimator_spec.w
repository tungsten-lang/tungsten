# Estimator specs — LinearRegression (Householder QR least squares for
# OLS, penalized normal equations for ridge — both on LinAlg),
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
use support

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
    expect(model.intercept.to_s).to be_num("3")
    expect(model.coefficients.to_s).to be_nums("\[1, 2\]")
    expect(model.predict([[1, 1], [4, 3]]).to_s).to be_nums("\[6, 13\]")
    expect(model.score(x, y).to_s).to be_num("1")

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
    expect(model.intercept.to_s).to be_num("3")
    expect(model.coefficients.to_s).to be_nums("\[1, 2\]")
    expect(model.predict(Matrix.new([[1, 1]])).to_s).to be_nums("\[6\]")
    expect(model.score(df, y).to_s).to be_num("1")

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
    expect(model.intercept.to_s).to be_num("1")
    expect(model.coefficients.to_s).to be_nums("\[1\]")
    expect(model.predict([[1, 2]])).to be_nil

# The reason fit's OLS path (alpha = 0) goes through Householder QR on
# the design matrix instead of Gaussian elimination on X^T X. Forming
# X^T X squares the condition number; QR never forms it. See the
# LinAlg-level head-to-head in spec/linalg_spec.w.
describe "LinearRegression OLS numerics (QR vs the normal equations)" ->
  # A Vandermonde design on clustered nodes — features [t, t^2] for
  # t = 1, 1.001, ..., 1.005 — with y placed EXACTLY on the plane
  # 3 + t + 2t^2. The residual is zero and the true coefficients are
  # known, so any error the estimator reports is arithmetic loss.
  # cond(X) is about 1.7e6; cond(X^T X) about 2.9e12.
  #
  # Measured on both engines: the QR fit is off by 6.9e-11, while the
  # normal equations this file's estimator used to run are off by
  # 5.3e-4 on the very same design — SEVEN orders of magnitude, and a
  # difference that shows up in the sixth printed digit of a slope.
  # Both routes are computed here, so the spec proves the improvement
  # rather than asserting it.
  it "recovers a known plane from an ill-conditioned design" ->
    d = 1.to_f / 1000.to_f
    rows = []
    ys = []
    design = []
    6.times -> (i)
      t = 1.to_f + i.to_f * d
      row = []
      row.push(t)
      row.push(t * t)
      rows.push(row)
      ys.push(3.to_f + t + 2.to_f * t * t)
      # the same design matrix fit builds internally: leading all-ones
      # intercept column, then the features
      dr = []
      dr.push(1.to_f)
      dr.push(t)
      dr.push(t * t)
      design.push(dr)

    model = LinearRegression.new
    r = model.fit(rows, ys)
    expect(r != nil).to be_true
    # to a numeric tolerance the fit is simply exact
    expect(model.intercept.to_s).to be_num("3")
    expect(model.coefficients.to_s).to be_nums("\[1, 2\]")

    qerr = LinAlg.fabs(model.intercept - 3.to_f)
    q0 = LinAlg.fabs(model.coefficients[0] - 1.to_f)
    q1 = LinAlg.fabs(model.coefficients[1] - 2.to_f)
    qerr = q0 if q0 > qerr
    qerr = q1 if q1 > qerr

    # The OLD route, rebuilt by hand on the same design matrix: the
    # normal equations X^T X beta = X^T y through Gaussian elimination.
    xm = Matrix.new(design)
    xt = xm.transpose
    nb = LinAlg.solve(xt.matmul(xm), xt.matvec(Vector.new(ys))).to_a
    nerr = LinAlg.fabs(nb[0] - 3.to_f)
    n0 = LinAlg.fabs(nb[1] - 1.to_f)
    n1 = LinAlg.fabs(nb[2] - 2.to_f)
    nerr = n0 if n0 > nerr
    nerr = n1 if n1 > nerr

    tight = 1.to_f / 100000000.to_f
    loose = 1.to_f / 1000000.to_f
    expect(qerr < tight).to be_true             # what fit does now
    expect(nerr > loose).to be_true             # what fit used to do
    expect(qerr * 1000.to_f < nerr).to be_true  # three decades better, at least

  # Ill-conditioned is NOT the same as rank-deficient: the design above
  # keeps its smallest QR pivot at 2.5e-6 of the column norm, six
  # decades above LinAlg.rank_tol, so it fits. An exactly dependent
  # column still comes back nil — the contract is unchanged.
  it "still separates ill-conditioned from rank-deficient" ->
    d = 1.to_f / 1000.to_f
    rows = []
    ys = []
    6.times -> (i)
      t = 1.to_f + i.to_f * d
      row = []
      row.push(t)
      row.push(t * t)
      rows.push(row)
      ys.push(t)
    expect(LinearRegression.new.fit(rows, ys) != nil).to be_true
    expect(LinearRegression.new.fit([[1, 2], [2, 4], [3, 6]], [1, 2, 3])).to be_nil

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

describe "LogisticRegression" ->
  # Weights start at zero, so sigmoid(0) = 0.5 makes the FIRST gradient
  # step exact — no transcendental. On x = [[0], [1]], y = [0, 1] with
  # learning rate 1 and one epoch the weight gradient is
  # (0.5*0 + (0.5 - 1)*1) / 2 = -0.25, so w steps to [0.25] and b to 0.
  it "takes the exact hand-computed first gradient step (lr = 1, 1 epoch)" ->
    model = LogisticRegression.new(1, 1)
    expect(model.fitted?).to be_false
    r = model.fit([[0], [1]], [0, 1])
    expect(r != nil).to be_true
    expect(model.fitted?).to be_true
    expect(model.coefficients.to_s).to eq("\[0.25\]")
    expect(model.intercept.to_s).to eq("0")
    expect(model.classes.to_s).to eq("\[0, 1\]")
    # probabilities: sigmoid(0) is exactly 0.5, sigmoid(0.25) within tol.
    probs = model.predict_proba([[0], [1]])
    expect(probs[0].to_s).to eq("0.5")
    ref = 1.to_f / (1.to_f + Math.exp(0.to_f - (1.to_f / 4.to_f)))
    tol = 1.to_f / 1000000.to_f
    expect(LinAlg.fabs(probs[1] - ref) < tol).to be_true

  # Two well-separated clusters (class 0 near the origin, class 1 near
  # (3,3)) are linearly separable, so batch gradient descent at the
  # defaults drives training accuracy to 1 and pushes every probability
  # to the correct side of 0.5, staying strictly inside (0, 1).
  it "separates two clusters and scores 1 at the defaults" ->
    x = [[0, 0], [1, 0], [0, 1], [3, 3], [4, 3], [3, 4]]
    y = [0, 0, 0, 1, 1, 1]
    model = LogisticRegression.new
    model.fit(x, y)
    expect(model.predict(x).to_s).to eq("\[0, 0, 0, 1, 1, 1\]")
    expect(model.score(x, y).to_s).to eq("1")
    probs = model.predict_proba(x)
    half = 1.to_f / 2.to_f
    expect(probs[0] > 0.to_f).to be_true
    expect(probs[0] < half).to be_true
    expect(probs[5] > half).to be_true
    expect(probs[5] < 1.to_f).to be_true

  # Labels are opaque: fit maps the two distinct labels to 0/1 by
  # first-seen order and predict returns those originals, so the output
  # flows straight into Metrics.accuracy like KNNClassifier's.
  it "maps two opaque labels to 0/1 and returns the originals" ->
    x = [[0, 0], [1, 0], [0, 1], [3, 3], [4, 3], [3, 4]]
    y = [:a, :a, :a, :b, :b, :b]
    model = LogisticRegression.new
    model.fit(x, y)
    expect(model.classes.to_s).to eq("\[a, b\]")
    preds = model.predict([[0, 0], [4, 4]])
    expect(preds.to_s).to eq("\[a, b\]")
    expect(Metrics.accuracy(preds, [:a, :b]).to_s).to eq("1")
    expect(Metrics.accuracy(preds, [:b, :b]).to_s).to eq("0.5")

  # Same accepted shapes as LinearRegression / KNNClassifier through the
  # shared feature_rows / target_values: DataFrame (numeric columns only —
  # :name is skipped), Series / Vector single-feature columns.
  it "accepts DataFrame, Series and Vector inputs" ->
    df = DataFrame.new([
      [:name, ["p", "q", "r", "s", "t", "u"]],
      [:f1, [0, 1, 0, 8, 9, 8]],
      [:f2, [0, 0, 1, 8, 8, 9]]
    ])
    labels = Series.new([:lo, :lo, :lo, :hi, :hi, :hi], :cls)
    model = LogisticRegression.new
    model.fit(df, labels)
    test = DataFrame.new([[:name, ["a", "b"]], [:f1, [1, 9]], [:f2, [0, 8]]])
    expect(model.predict(test).to_s).to eq("\[lo, hi\]")
    expect(model.score(df, labels).to_s).to eq("1")
    xs = Series.new([0, 1, 2, 20, 21, 22], :x)
    ms = LogisticRegression.new
    ms.fit(xs, [0, 0, 0, 1, 1, 1])
    expect(ms.predict(Vector.new([1, 21])).to_s).to eq("\[0, 1\]")

  # Binary only: a y with one distinct label, or three or more, makes fit
  # return nil and leaves fitted? false.
  it "requires exactly two classes" ->
    expect(LogisticRegression.new.fit([[1], [2]], [0, 0])).to be_nil
    m = LogisticRegression.new
    expect(m.fit([[1], [2], [3]], [0, 1, 2])).to be_nil
    expect(m.fitted?).to be_false

  # Unusable shapes and premature calls all return nil and leave fitted?
  # false — the bit's shape-error convention, matching LinearRegression.
  it "returns nil for unusable shapes and before fit" ->
    model = LogisticRegression.new
    expect(model.predict([[1, 2]])).to be_nil
    expect(model.predict_proba([[1, 2]])).to be_nil
    expect(model.score([[1, 2]], [0])).to be_nil
    expect(model.fit([], [])).to be_nil
    expect(model.fit([[1, 2], [3]], [0, 1])).to be_nil
    expect(model.fit([[1], [2]], [0, 1, 1])).to be_nil
    expect(model.fitted?).to be_false
    r = model.fit([[0], [1]], [0, 1])
    expect(r != nil).to be_true
    expect(model.predict([[1, 2]])).to be_nil

  # The payoff of predict_proba: its scores feed Metrics.roc_auc for
  # threshold-free evaluation. The two clusters are linearly separable, so
  # the fitted probabilities rank every class-1 row above every class-0
  # row — a perfect ranking, AUC exactly 1 — while the hard-label accuracy
  # (score) is also 1. Opaque labels pass their positive label as
  # pos_label, exactly as predict_proba scores classes[1].
  it "feeds predict_proba into Metrics.roc_auc (AUC 1 on separable data)" ->
    x = [[0, 0], [1, 0], [0, 1], [3, 3], [4, 3], [3, 4]]
    y = [0, 0, 0, 1, 1, 1]
    model = LogisticRegression.new
    model.fit(x, y)
    expect(Metrics.roc_auc(model.predict_proba(x), y).to_s).to eq("1")
    ys = [:a, :a, :a, :b, :b, :b]
    ms = LogisticRegression.new
    ms.fit(x, ys)
    expect(Metrics.roc_auc(ms.predict_proba(x), ys, :b).to_s).to eq("1")

describe "GaussianNB" ->
  # Closed-form fit — no iteration, no seed. Two classes of two rows each:
  # class 0 = [[1,2],[3,4]] (means [2,3]), class 1 = [[11,12],[13,14]]
  # (means [12,13]); every within-class POPULATION variance (n denominator,
  # numpy's np.var — NOT Stats.var's n-1) is 1. Priors are 2/4 = 0.5 each.
  # epsilon_ = var_smoothing * max column variance over all four rows:
  # each column is [1,3,11,13] / [2,4,12,14] about its mean 7 / 8, giving
  # (36+16+16+36)/4 = 26, so epsilon = 1e-9 * 26 = 2.6e-8 and every
  # variance is 1.000000026 — "1" at printing precision.
  it "fits closed-form priors, means and variances (hand-computed)" ->
    model = GaussianNB.new
    expect(model.fitted?).to be_false
    r = model.fit([[1, 2], [3, 4], [11, 12], [13, 14]], [0, 0, 1, 1])
    expect(r != nil).to be_true
    expect(model.fitted?).to be_true
    expect(model.classes.to_s).to eq("\[0, 1\]")
    expect(model.class_counts.to_s).to eq("\[2, 2\]")
    expect(model.class_priors.to_s).to eq("\[0.5, 0.5\]")
    expect(model.means.to_s).to eq("\[\[2, 3\], \[12, 13\]\]")
    expect(model.variances.to_s).to be_nums("\[\[1, 1\], \[1, 1\]\]")
    expect(model.epsilon.to_s).to be_num("2.6e-08")
    expect(model.var_smoothing.to_s).to be_num("1e-09")

  # jll(c) = log P(c) - 0.5*sum_j log(2*pi*var) - 0.5*sum_j (x-mean)^2/var.
  # At the class-0 mean [2,3]: log(0.5) - log(2*pi*1) - 0 = -0.693147 -
  # 1.837877 = -2.53102, and the class-1 term adds -0.5*(100+100) = -100
  # for -102.531. Row [7,8] sits exactly between the two means, so both
  # log likelihoods are bit-identical and the posteriors tie at 0.5.
  it "classifies by argmax of the joint log likelihood" ->
    model = GaussianNB.new
    model.fit([[1, 2], [3, 4], [11, 12], [13, 14]], [0, 0, 1, 1])
    q = [[2, 3], [12, 13], [7, 8]]
    jll = model.joint_log_likelihood(q)
    expect(jll[0].to_s).to be_nums("\[-2.53102, -102.531\]")
    expect(jll[1].to_s).to be_nums("\[-102.531, -2.53102\]")
    expect(jll[2].to_s).to be_nums("\[-27.531, -27.531\]")
    probs = model.predict_proba(q)
    expect(probs[2].to_s).to be_nums("\[0.5, 0.5\]")
    expect(probs[0][0].to_s).to be_num("1")
    # an exact argmax tie breaks to the first-seen class
    expect(model.predict(q).to_s).to eq("\[0, 1, 0\]")
    expect(model.score([[1, 2], [3, 4], [11, 12], [13, 14]], [0, 0, 1, 1]).to_s).to be_num("1")

  # The scikit-learn GaussianNB documentation example verbatim:
  # X = [[-1,-1],[-2,-1],[-3,-2],[1,1],[2,1],[3,2]], y = [1,1,1,2,2,2],
  # clf.predict([[-0.8, -1]]) -> [1]. Means are [-2,-4/3] and [2,4/3],
  # population variances 2/3 and 2/9 (+epsilon 4.66667e-9).
  it "reproduces the scikit-learn documentation example" ->
    x = [[0 - 1, 0 - 1], [0 - 2, 0 - 1], [0 - 3, 0 - 2], [1, 1], [2, 1], [3, 2]]
    y = [1, 1, 1, 2, 2, 2]
    model = GaussianNB.new
    model.fit(x, y)
    expect(model.means.to_s).to be_nums("\[\[-2, -1.33333\], \[2, 1.33333\]\]")
    expect(model.variances.to_s).to be_nums("\[\[0.666667, 0.222222\], \[0.666667, 0.222222\]\]")
    expect(model.epsilon.to_s).to be_num("4.66667e-09")
    q = [[0.to_f - 8.to_f / 10.to_f, 0 - 1]]
    expect(model.joint_log_likelihood(q).to_s).to be_nums("\[\[-2.90625, -19.7063\]\]")
    expect(model.predict(q).to_s).to eq("\[1\]")
    expect(model.score(x, y).to_s).to be_num("1")

  # One feature, symmetric: class a = [-1,1] (mean 0), class b = [3,5]
  # (mean 4), both variance 1, equal priors. With shared variances the
  # two-class softmax IS a sigmoid of the log-odds -0.5*((x-4)^2 - x^2),
  # so at x = 2 the classes tie exactly and at x = 0 the log-odds are -8.
  it "returns posteriors that sum to 1 and a flat column for one label" ->
    model = GaussianNB.new
    model.fit([0 - 1, 1, 3, 5], [:a, :a, :b, :b])
    expect(model.classes.to_s).to eq("\[a, b\]")
    expect(model.means.to_s).to eq("\[\[0\], \[4\]\]")
    probs = model.predict_proba([0, 2, 4])
    expect(probs[1].to_s).to eq("\[0.5, 0.5\]")
    tol = 1.to_f / 1000000.to_f
    ref = 1.to_f / (1.to_f + Math.exp(8.to_f))
    expect(LinAlg.fabs(probs[0][1] - ref) < tol).to be_true
    expect(LinAlg.fabs(probs[0][0] + probs[0][1] - 1.to_f) < tol).to be_true
    # a pos_label picks one class's column out, ready for roc_auc / log_loss
    expect(model.predict_proba([0, 2, 4], :b).to_s).to be_nums("\[0.00033535, 0.5, 0.999665\]")
    expect(model.predict_proba([0, 2, 4], :zz)).to be_nil
    expect(model.predict([0, 2, 4]).to_s).to eq("\[a, a, b\]")

  # A feature that never varies has variance 0, which would divide by
  # zero. epsilon (= var_smoothing * the largest column variance) is added
  # to every variance instead: feature 2 is a constant 5, so its variance
  # is exactly epsilon = 1e-9 * 26 = 2.6e-8 and the fit stays finite. When
  # EVERY feature is constant the reference variance is 0 too, so epsilon
  # falls back to var_smoothing itself (scikit-learn yields nan here);
  # both classes then tie and predict returns the first-seen label.
  it "smooths zero-variance features instead of dividing by zero" ->
    model = GaussianNB.new
    model.fit([[0, 5], [2, 5], [10, 5], [12, 5]], [0, 0, 1, 1])
    expect(model.epsilon.to_s).to be_num("2.6e-08")
    expect(model.variances.to_s).to be_nums("\[\[1, 2.6e-08\], \[1, 2.6e-08\]\]")
    expect(model.joint_log_likelihood([[1, 5]])[0].to_s).to be_nums("\[6.20156, -43.7984\]")
    expect(model.predict([[1, 5], [11, 5]]).to_s).to eq("\[0, 1\]")
    flat = GaussianNB.new
    flat.fit([5, 5, 5, 5], [0, 0, 1, 1])
    expect(flat.epsilon.to_s).to be_num("1e-09")
    expect(flat.variances.to_s).to be_nums("\[\[1e-09\], \[1e-09\]\]")
    expect(flat.predict_proba([5, 9]).to_s).to be_nums("\[\[0.5, 0.5\], \[0.5, 0.5\]\]")
    expect(flat.predict([5, 9]).to_s).to eq("\[0, 0\]")
    # var_smoothing is the knob (data-derived, never a float literal):
    # 0.01 * 26 = 0.26 lands on every variance, 1 -> 1.26 and 0 -> 0.26.
    loud = GaussianNB.new(1.to_f / 100.to_f)
    loud.fit([[0, 5], [2, 5], [10, 5], [12, 5]], [0, 0, 1, 1])
    expect(loud.epsilon.to_s).to be_num("0.26")
    expect(loud.variances.to_s).to be_nums("\[\[1.26, 0.26\], \[1.26, 0.26\]\]")
    expect(loud.predict([[1, 5], [11, 5]]).to_s).to eq("\[0, 1\]")

  # Multiclass out of the box — no one-vs-rest wrapper, the argmax just
  # ranges over three classes — so predict feeds Metrics.classification_report
  # directly. Three well-separated groups of two rows each: priors 1/3.
  it "classifies three classes and feeds the classification report" ->
    x = [[0, 0], [1, 0], [10, 10], [11, 10], [0, 20], [1, 20]]
    y = [0, 0, 1, 1, 2, 2]
    model = GaussianNB.new
    model.fit(x, y)
    expect(model.classes.to_s).to eq("\[0, 1, 2\]")
    expect(model.class_counts.to_s).to eq("\[2, 2, 2\]")
    expect(model.class_priors.to_s).to be_nums("\[0.333333, 0.333333, 0.333333\]")
    expect(model.means.to_s).to be_nums("\[\[0.5, 0\], \[10.5, 10\], \[0.5, 20\]\]")
    preds = model.predict([[0, 1], [10, 11], [1, 19]])
    expect(preds.to_s).to eq("\[0, 1, 2\]")
    expect(model.predict_proba([[0, 1]])[0].to_s).to be_nums("\[1, 0, 0\]")
    expect(model.score(x, y).to_s).to eq("1")
    rep = Metrics.classification_report(model.predict(x), y)
    expect(rep.accuracy.to_s).to eq("1")
    expect(rep.macro_f1.to_s).to eq("1")

  # Same accepted shapes as the other estimators through the shared
  # feature_rows / target_values: DataFrame (numeric columns only — :name
  # is skipped), Matrix, Series / Vector single-feature columns.
  it "accepts DataFrame, Matrix, Series and Vector inputs" ->
    df = DataFrame.new([
      [:name, ["p", "q", "r", "s"]],
      [:f1, [1, 3, 11, 13]],
      [:f2, [2, 4, 12, 14]]
    ])
    labels = Series.new([:lo, :lo, :hi, :hi], :cls)
    model = GaussianNB.new
    model.fit(df, labels)
    expect(model.classes.to_s).to eq("\[lo, hi\]")
    expect(model.means.to_s).to eq("\[\[2, 3\], \[12, 13\]\]")
    test = DataFrame.new([[:name, ["a", "b"]], [:f1, [2, 12]], [:f2, [3, 13]]])
    expect(model.predict(test).to_s).to eq("\[lo, hi\]")
    expect(model.predict(Matrix.new([[2, 3], [12, 13]])).to_s).to eq("\[lo, hi\]")
    expect(model.score(df, labels).to_s).to eq("1")
    xs = Series.new([0 - 1, 1, 3, 5], :x)
    ms = GaussianNB.new
    ms.fit(xs, [0, 0, 1, 1])
    expect(ms.predict(Vector.new([0, 4])).to_s).to eq("\[0, 1\]")

  # The payoff of predict_proba(x, label): a threshold-free score column
  # for Metrics.roc_auc / Metrics.log_loss. Two OVERLAPPING 1-D classes,
  # [0,1] and [2,3], means 0.5 / 2.5 and variances 0.25 — shared, so the
  # posterior is a sigmoid of -0.5*((x-2.5)^2 - (x-0.5)^2)/0.25 = 8x - 12.
  # At x = 1 that is -4, P(1) = 1/(1+e^4) = 0.0179862. The ranking is still
  # perfect (AUC 1) and the log loss is the small 0.00907804.
  it "feeds predict_proba into Metrics.roc_auc and Metrics.log_loss" ->
    x = [0, 1, 2, 3]
    y = [0, 0, 1, 1]
    model = GaussianNB.new
    model.fit(x, y)
    expect(model.means.to_s).to be_nums("\[\[0.5\], \[2.5\]\]")
    expect(model.variances.to_s).to be_nums("\[\[0.25\], \[0.25\]\]")
    scores = model.predict_proba(x, 1)
    expect(scores.to_s).to be_nums("\[6.14417e-06, 0.0179862, 0.982014, 0.999994\]")
    tol = 1.to_f / 1000000.to_f
    ref = 1.to_f / (1.to_f + Math.exp(4.to_f))
    expect(LinAlg.fabs(scores[1] - ref) < tol).to be_true
    expect(Metrics.roc_auc(scores, y).to_s).to eq("1")
    expect(Metrics.log_loss(scores, y).to_s).to be_num("0.00907804")
    expect(model.predict(x).to_s).to eq("\[0, 0, 1, 1\]")

  # Unusable shapes and premature calls all return nil and leave fitted?
  # false — the bit's shape-error convention, matching the estimators. A
  # single class is FINE here (unlike LogisticRegression): a generative
  # model with one class is degenerate but well defined.
  it "returns nil for unusable shapes and before fit" ->
    model = GaussianNB.new
    expect(model.predict([[1, 2]])).to be_nil
    expect(model.predict_proba([[1, 2]])).to be_nil
    expect(model.joint_log_likelihood([[1, 2]])).to be_nil
    expect(model.score([[1, 2]], [0])).to be_nil
    expect(model.fit([], [])).to be_nil
    expect(model.fit([[1, 2], [3]], [0, 1])).to be_nil
    expect(model.fit([[1], [2]], [0, 1, 1])).to be_nil
    expect(model.fitted?).to be_false
    r = model.fit([[1, 2], [3, 4], [11, 12], [13, 14]], [0, 0, 1, 1])
    expect(r != nil).to be_true
    expect(model.predict([[1, 2, 3]])).to be_nil
    expect(model.predict_proba([[1, 2, 3]])).to be_nil
    one = GaussianNB.new
    expect(one.fit([[1], [2]], [0, 0]) != nil).to be_true
    expect(one.predict([[1]]).to_s).to eq("\[0\]")

# --- DecisionTreeClassifier (lib/decision_tree.w) ---
#
# Every tree below is worked out BY HAND in its comment — the chosen
# feature, the chosen threshold and the gain that chose it — and then
# asserted, so these specs test the SPLIT SEARCH and not merely that it
# runs. Gini of a node is 1 - sum p_c^2; a split's gain is
# imp(node) - (nl/n)*imp(left) - (nr/n)*imp(right); candidate thresholds
# are midpoints between adjacent DISTINCT sorted values.
describe "DecisionTreeClassifier" ->
  # x = [[0,0],[1,0],[0,10],[1,10]] with labels lo,lo,hi,hi — they follow
  # feature 1 exactly and ignore feature 0. Root gini = 0.5.
  #   feature 0 @ 0.5: both sides are {lo,hi}, gini 0.5 each -> gain 0
  #   feature 1 @ 5:   left {lo,lo} gini 0, right {hi,hi} gini 0 -> gain 0.5
  # so the root MUST be feature 1 at the midpoint of 0 and 10, and both
  # children are pure leaves.
  it "splits a clean axis-aligned separation at the midpoint (hand-computed)" ->
    x = [[0, 0], [1, 0], [0, 10], [1, 10]]
    y = [:lo, :lo, :hi, :hi]
    model = DecisionTreeClassifier.new
    expect(model.fitted?).to be_false
    r = model.fit(x, y)
    expect(r != nil).to be_true
    expect(model.fitted?).to be_true
    expect(model.classes.join(",")).to eq("lo,hi")
    expect(model.n_features).to eq(2)
    expect(model.tree[:leaf]).to be_false
    expect(model.tree[:feature]).to eq(1)
    expect(model.tree[:threshold].to_s).to eq("5")
    expect(model.tree[:impurity].to_s).to eq("0.5")
    expect(model.tree[:gain].to_s).to eq("0.5")
    expect(model.tree[:n]).to eq(4)
    expect(model.tree[:depth]).to eq(0)
    # both children are PURE leaves, one per class
    expect(model.tree[:left][:leaf]).to be_true
    expect(model.tree[:left][:prediction].to_s).to eq("lo")
    expect(model.tree[:left][:impurity].to_s).to eq("0")
    expect(model.tree[:right][:prediction].to_s).to eq("hi")
    expect(model.depth).to eq(1)
    expect(model.node_count).to eq(3)
    expect(model.leaf_count).to eq(2)
    expect(model.tree_lines.join(" | ")).to eq("x1 <= 5 |   leaf: lo (n=2) |   leaf: hi (n=2)")
    # perfect separation -> accuracy 1, and unseen rows follow the same rule
    expect(model.predict(x).join(",")).to eq("lo,lo,hi,hi")
    expect(model.score(x, y).to_s).to eq("1")
    expect(model.predict([[99, 4], [0 - 7, 6]]).join(",")).to eq("lo,hi")

  # Ties are broken by the DOCUMENTED rule: lowest feature index first,
  # then lowest threshold.
  #
  # FEATURE tie — x = [[0,0],[1,1]], y = [0,1]. Feature 0 @ 0.5 and
  # feature 1 @ 0.5 both separate perfectly (gain 0.5); feature 0 wins.
  #
  # THRESHOLD tie — x = [[0],[1],[2],[3]], y = [0,1,0,1]. Root gini 0.5.
  #   @ 0.5: right {1,0,1} gini 4/9, weighted 1/3 -> gain 1/6
  #   @ 1.5: both sides {0,1} gini 0.5             -> gain 0
  #   @ 2.5: left {0,1,0} gini 4/9, weighted 1/3   -> gain 1/6
  # 0.5 and 2.5 tie, so the LOWEST threshold, 0.5, is taken.
  it "breaks a gain tie by lowest feature index, then lowest threshold" ->
    ft = DecisionTreeClassifier.new
    ft.fit([[0, 0], [1, 1]], [0, 1])
    expect(ft.tree[:feature]).to eq(0)
    expect(ft.tree[:threshold].to_s).to eq("0.5")
    expect(ft.tree[:gain].to_s).to eq("0.5")
    tt = DecisionTreeClassifier.new(1)
    tt.fit([[0], [1], [2], [3]], [0, 1, 0, 1])
    expect(tt.tree[:feature]).to eq(0)
    expect(tt.tree[:threshold].to_s).to eq("0.5")
    expect(tt.tree[:gain].to_s).to be_num("0.166667")
    # three-way tie across features — x0 @ 5.5, x1 @ 5 and x1 @ 15 all buy
    # exactly 1/3 of the root's 2/3 gini, so feature 0 takes it
    mx = [[0, 0], [1, 0], [10, 10], [11, 10], [0, 20], [1, 20]]
    my = [0, 0, 1, 1, 2, 2]
    mt = DecisionTreeClassifier.new(1)
    mt.fit(mx, my)
    expect(mt.tree[:impurity].to_s).to be_num("0.666667")
    expect(mt.tree[:feature]).to eq(0)
    expect(mt.tree[:threshold].to_s).to eq("5.5")
    expect(mt.tree[:gain].to_s).to be_num("0.333333")

  # max_depth caps the number of EDGES from the root: 1 is a decision
  # STUMP (one test, two leaves), 0 is a single leaf that always predicts
  # the training majority. x = [[0],[1],[2],[10],[11],[12]] with three 0s
  # then three 1s splits perfectly at the midpoint of 2 and 10.
  it "behaves as a stump at max_depth = 1 and a single leaf at 0" ->
    x = [[0], [1], [2], [10], [11], [12]]
    y = [0, 0, 0, 1, 1, 1]
    stump = DecisionTreeClassifier.new(1)
    stump.fit(x, y)
    expect(stump.depth).to eq(1)
    expect(stump.node_count).to eq(3)
    expect(stump.leaf_count).to eq(2)
    expect(stump.tree[:threshold].to_s).to eq("6")
    expect(stump.tree[:gain].to_s).to eq("0.5")
    expect(stump.score(x, y).to_s).to eq("1")
    expect(stump.tree_lines.join(" | ")).to eq("x0 <= 6 |   leaf: 0 (n=3) |   leaf: 1 (n=3)")
    # an UNCAPPED tree on this data finds the same single split — nothing
    # is left to gain once both sides are pure
    full = DecisionTreeClassifier.new
    full.fit(x, y)
    expect(full.tree_lines.join(" | ")).to eq(stump.tree_lines.join(" | "))
    # max_depth 0: the root IS the leaf; 3 vs 3 ties to the first-seen label
    root = DecisionTreeClassifier.new(0)
    root.fit(x, y)
    expect(root.tree[:leaf]).to be_true
    expect(root.depth).to eq(0)
    expect(root.node_count).to eq(1)
    expect(root.tree[:counts].to_s).to eq("\[3, 3\]")
    expect(root.tree[:prediction]).to eq(0)
    expect(root.predict([[0], [12]]).to_s).to eq("\[0, 0\]")
    expect(root.score(x, y).to_s).to eq("0.5")

  # XOR is the classic case a SINGLE axis-aligned cut cannot touch: every
  # split of [[0,0],[0,1],[1,0],[1,1]] / [0,1,1,0] leaves both sides at
  # gini 0.5, so every gain is exactly 0. A zero-gain split is still taken
  # when it is the best on offer (scikit-learn's min_impurity_decrease = 0),
  # and the two children then separate it perfectly — depth 2, accuracy 1.
  it "reaches accuracy 1 on XOR by taking a zero-gain split" ->
    x = [[0, 0], [0, 1], [1, 0], [1, 1]]
    y = [0, 1, 1, 0]
    model = DecisionTreeClassifier.new
    model.fit(x, y)
    expect(model.tree[:feature]).to eq(0)
    expect(model.tree[:threshold].to_s).to eq("0.5")
    expect(model.tree[:gain].to_s).to eq("0")
    expect(model.depth).to eq(2)
    expect(model.leaf_count).to eq(4)
    expect(model.score(x, y).to_s).to eq("1")
    expect(model.predict(x).to_s).to eq("\[0, 1, 1, 0\]")
    # a stump, by contrast, cannot beat chance here
    expect(DecisionTreeClassifier.new(1).fit(x, y).score(x, y).to_s).to eq("0.5")

  # predict_proba is the LEAF's class distribution, counts / n in `classes`
  # order. x = [[0],[1],[2],[3]], y = [0,1,0,1] capped at depth 1 splits at
  # 0.5 (see the tie spec): the left leaf holds {0} -> [1, 0], the right
  # leaf {1,0,1} -> [1/3, 2/3] and predicts the majority 1.
  it "reports the leaf class distribution from predict_proba" ->
    x = [[0], [1], [2], [3]]
    y = [0, 1, 0, 1]
    model = DecisionTreeClassifier.new(1)
    model.fit(x, y)
    expect(model.tree[:left][:counts].to_s).to eq("\[1, 0\]")
    expect(model.tree[:right][:counts].to_s).to eq("\[1, 2\]")
    expect(model.tree[:right][:impurity].to_s).to be_num("0.444444")
    expect(model.tree[:right][:prediction]).to eq(1)
    probs = model.predict_proba(x)
    expect(probs[0].to_s).to eq("\[1, 0\]")
    expect(probs[1].to_s).to be_nums("\[0.333333, 0.666667\]")
    # every row sums to 1
    tol = 1.to_f / 1000000.to_f
    expect(LinAlg.fabs(probs[1][0] + probs[1][1] - 1.to_f) < tol).to be_true
    # a pos_label picks one class's column out, ready for roc_auc / log_loss
    expect(model.predict_proba(x, 1).to_s).to be_nums("\[0, 0.666667, 0.666667, 0.666667\]")
    expect(model.predict_proba(x, 99)).to be_nil
    expect(model.predict(x).to_s).to eq("\[0, 1, 1, 1\]")
    expect(model.score(x, y).to_s).to eq("0.75")
    # a perfectly separating tree gives hard 0/1 posteriors that feed the
    # ROC / log-loss work directly
    sep = DecisionTreeClassifier.new
    sep.fit([[0], [1], [2], [3]], [0, 0, 1, 1])
    expect(sep.predict_proba([[0], [1], [2], [3]], 1).to_s).to eq("\[0, 0, 1, 1\]")
    expect(Metrics.roc_auc(sep.predict_proba([[0], [1], [2], [3]], 1), [0, 0, 1, 1]).to_s).to eq("1")

  # Multiclass with no wrapper — the majority vote just ranges over three
  # classes — so predict feeds Metrics.classification_report directly. The
  # root is the three-way tie above (feature 0 @ 5.5); its left child holds
  # the four rows of classes 0 and 2, which feature 1 @ 10 separates.
  it "classifies three classes and feeds the classification report" ->
    x = [[0, 0], [1, 0], [10, 10], [11, 10], [0, 20], [1, 20]]
    y = [0, 0, 1, 1, 2, 2]
    model = DecisionTreeClassifier.new
    model.fit(x, y)
    expect(model.classes.to_s).to eq("\[0, 1, 2\]")
    expect(model.tree_lines.join(" | ")).to eq("x0 <= 5.5 |   x1 <= 10 |     leaf: 0 (n=2) |     leaf: 2 (n=2) |   leaf: 1 (n=2)")
    expect(model.depth).to eq(2)
    expect(model.leaf_count).to eq(3)
    expect(model.predict([[0, 1], [10, 11], [1, 19]]).to_s).to eq("\[0, 1, 2\]")
    expect(model.predict_proba([[0, 1]])[0].to_s).to eq("\[1, 0, 0\]")
    expect(model.score(x, y).to_s).to eq("1")
    rep = Metrics.classification_report(model.predict(x), y)
    expect(rep.accuracy.to_s).to eq("1")
    expect(rep.macro_f1.to_s).to eq("1")

  # :entropy is a real alternative criterion, not a relabelling of gini —
  # it picks a DIFFERENT split on the same data. Four rows, four classes:
  # entropy = log2(4) = 2 bits, gini = 1 - 4*(1/4)^2 = 0.75.
  #   @ 0.5: entropy weighted (3/4)*log2(3) = 1.189 -> gain 0.811
  #          gini    weighted (3/4)*(2/3)   = 0.5   -> gain 0.25
  #   @ 1.5: entropy weighted 1             -> gain 1     (best)
  #          gini    weighted 0.5           -> gain 0.25  (ties @ 0.5)
  # so entropy takes 1.5 outright while gini ties and keeps the lower 0.5.
  it "supports entropy as a selectable criterion" ->
    x = [[0], [1], [2], [3]]
    y = [0, 1, 2, 3]
    ent = DecisionTreeClassifier.new(1, nil, nil, :entropy)
    ent.fit(x, y)
    expect(ent.criterion.to_s).to eq("entropy")
    expect(ent.tree[:impurity].to_s).to eq("2")
    expect(ent.tree[:threshold].to_s).to eq("1.5")
    expect(ent.tree[:gain].to_s).to eq("1")
    gini = DecisionTreeClassifier.new(1, nil, nil, :gini)
    gini.fit(x, y)
    expect(gini.tree[:impurity].to_s).to eq("0.75")
    expect(gini.tree[:threshold].to_s).to eq("0.5")
    expect(gini.tree[:gain].to_s).to be_num("0.25")
    # a balanced two-class node is exactly 1 bit, and both criteria agree
    # on the perfectly separating split
    bx = [[0], [1], [2], [10], [11], [12]]
    by = [0, 0, 0, 1, 1, 1]
    b = DecisionTreeClassifier.new(nil, nil, nil, :entropy)
    b.fit(bx, by)
    expect(b.tree[:impurity].to_s).to eq("1")
    expect(b.tree[:gain].to_s).to eq("1")
    expect(b.tree[:threshold].to_s).to eq("6")
    expect(b.score(bx, by).to_s).to eq("1")
    # ... and an unknown criterion is a fit ERROR, never a silent fallback
    expect(DecisionTreeClassifier.new(nil, nil, nil, :bogus).fit(bx, by)).to be_nil
    expect(DecisionTreeClassifier.new(nil, nil, nil, :mse).fit(bx, by)).to be_nil

  # The three "cannot split" shapes all end in a LEAF rather than a raise:
  # a pure node (nothing to gain), an all-constant feature set (no distinct
  # values, hence no candidate threshold at all), and a single class.
  it "makes a leaf of a pure node, a constant feature and a single class" ->
    single = DecisionTreeClassifier.new
    single.fit([[1], [2]], [5, 5])
    expect(single.tree[:leaf]).to be_true
    expect(single.tree[:impurity].to_s).to eq("0")
    expect(single.classes.to_s).to eq("\[5\]")
    expect(single.tree[:prediction]).to eq(5)
    expect(single.predict_proba([[9]]).to_s).to eq("\[\[1\]\]")
    expect(single.score([[1], [2]], [5, 5]).to_s).to eq("1")
    # every feature constant: no threshold exists, so the root stays a leaf
    # and predicts the tied first-seen label
    flat = DecisionTreeClassifier.new
    flat.fit([[3], [3]], [0, 1])
    expect(flat.tree[:leaf]).to be_true
    expect(flat.tree[:counts].to_s).to eq("\[1, 1\]")
    expect(flat.tree[:impurity].to_s).to eq("0.5")
    expect(flat.tree[:prediction]).to eq(0)
    expect(flat.predict_proba([[3]]).to_s).to eq("\[\[0.5, 0.5\]\]")
    expect(flat.score([[3], [3]], [0, 1]).to_s).to eq("0.5")
    # a constant feature ALONGSIDE a useful one is simply skipped
    mixed = DecisionTreeClassifier.new
    mixed.fit([[0, 5], [1, 5], [10, 5], [11, 5]], [0, 0, 1, 1])
    expect(mixed.tree[:feature]).to eq(0)
    expect(mixed.tree[:threshold].to_s).to eq("5.5")
    expect(mixed.depth).to eq(1)

  # min_samples_split stops a SMALL node being split at all;
  # min_samples_leaf makes a split INADMISSIBLE when either side would be
  # too small — which can force a worse-gaining split to be chosen.
  # x = [[0],[1],[2],[3]], y = [0,0,0,1], root gini 0.375.
  #   @ 2.5: sides 3/1, perfect       -> gain 0.375  (the default winner)
  #   @ 1.5: sides 2/2, right gini 0.5 -> gain 0.125
  #   @ 0.5: sides 1/3
  # With min_samples_leaf = 2 only 1.5 survives, so that is what is taken.
  it "respects min_samples_split and min_samples_leaf" ->
    x = [[0], [1], [2], [3]]
    y = [0, 0, 0, 1]
    base = DecisionTreeClassifier.new
    base.fit(x, y)
    expect(base.tree[:impurity].to_s).to eq("0.375")
    expect(base.tree[:threshold].to_s).to eq("2.5")
    expect(base.tree[:gain].to_s).to eq("0.375")
    expect(base.score(x, y).to_s).to eq("1")
    leafy = DecisionTreeClassifier.new(nil, nil, 2)
    leafy.fit(x, y)
    expect(leafy.tree[:threshold].to_s).to eq("1.5")
    expect(leafy.tree[:gain].to_s).to eq("0.125")
    expect(leafy.tree_lines.join(" | ")).to eq("x0 <= 1.5 |   leaf: 0 (n=2) |   leaf: 0 (n=2)")
    expect(leafy.score(x, y).to_s).to eq("0.75")
    # a node smaller than min_samples_split is never split — 4 < 5
    tight = DecisionTreeClassifier.new(nil, 5)
    tight.fit(x, y)
    expect(tight.tree[:leaf]).to be_true
    expect(tight.node_count).to eq(1)
    # both are clamped to their legal minimum, so params always reports
    # the value actually in force and with_params round-trips
    clamped = DecisionTreeClassifier.new(nil, 1, 0)
    expect(clamped.min_samples_split).to eq(2)
    expect(clamped.min_samples_leaf).to eq(1)
    expect(clamped.params[:min_samples_split]).to eq(2)

  # Nothing here is random — no bootstrap, no feature subsampling, no seed
  # — so the fitted tree is a pure function of the data. The two trees are
  # compared as their full rendered structure, not just their predictions.
  it "fits an IDENTICAL tree from the same data twice" ->
    x = [[0, 0], [1, 0], [0, 1], [1, 1], [10, 10], [11, 10], [10, 11], [11, 11]]
    y = [0, 0, 0, 0, 1, 1, 1, 1]
    a = DecisionTreeClassifier.new
    a.fit(x, y)
    b = DecisionTreeClassifier.new
    b.fit(x, y)
    expect(a.tree_lines.join(" | ")).to eq(b.tree_lines.join(" | "))
    # ... and it is this exact structure on BOTH engines
    expect(a.tree_lines.join(" | ")).to eq("x0 <= 5.5 |   leaf: 0 (n=4) |   leaf: 1 (n=4)")
    expect(a.node_count).to eq(b.node_count)
    expect(a.predict(x).to_s).to eq(b.predict(x).to_s)
    # a clone made through the contract fits the same tree too
    c = a.with_params(a.params)
    c.fit(x, y)
    expect(c.tree_lines.join(" | ")).to eq(a.tree_lines.join(" | "))

  # Same accepted shapes as the other estimators, through the shared
  # Estimator.feature_rows / .target_values: DataFrame (numeric columns
  # only — :name is skipped), Matrix, Series / Vector single-feature columns.
  it "accepts DataFrame, Matrix, Series and Vector inputs" ->
    df = DataFrame.new([
      [:name, ["p", "q", "r", "s"]],
      [:f1, [0, 1, 10, 11]],
      [:f2, [0, 1, 10, 11]]
    ])
    labels = Series.new([:lo, :lo, :hi, :hi], :cls)
    model = DecisionTreeClassifier.new
    model.fit(df, labels)
    expect(model.classes.join(",")).to eq("lo,hi")
    expect(model.n_features).to eq(2)
    expect(model.predict(Matrix.new([[0, 0], [11, 11]])).join(",")).to eq("lo,hi")
    expect(model.score(df, labels).to_s).to eq("1")
    flat = DecisionTreeClassifier.new
    flat.fit(Series.new([0, 1, 10, 11], :x), [0, 0, 1, 1])
    expect(flat.predict(Vector.new([0, 11])).to_s).to eq("\[0, 1\]")

  # Unusable shapes and premature calls all return nil and leave fitted?
  # false — the bit's shape-error convention, matching the estimators.
  it "returns nil for unusable shapes and before fit" ->
    model = DecisionTreeClassifier.new
    expect(model.predict([[1, 2]])).to be_nil
    expect(model.predict_proba([[1, 2]])).to be_nil
    expect(model.apply([[1, 2]])).to be_nil
    expect(model.score([[1, 2]], [0])).to be_nil
    expect(model.tree).to be_nil
    expect(model.classes).to be_nil
    expect(model.depth).to be_nil
    expect(model.node_count).to be_nil
    expect(model.tree_lines).to be_nil
    expect(model.fit([], [])).to be_nil
    expect(model.fit([[1, 2], [3]], [0, 1])).to be_nil
    expect(model.fit([[1], [2]], [0, 1, 1])).to be_nil
    expect(model.fitted?).to be_false
    r = model.fit([[1, 2], [3, 4], [11, 12], [13, 14]], [0, 0, 1, 1])
    expect(r != nil).to be_true
    # a query row of the wrong width is nil, not a crash
    expect(model.predict([[1, 2, 3]])).to be_nil
    expect(model.predict_proba([[1]])).to be_nil
    expect(model.score([[1, 2, 3]], [0])).to be_nil

# --- DecisionTreeRegressor (the same machinery, MSE criterion) ---
#
# Impurity is the POPULATION variance of the targets and a leaf predicts
# their MEAN, so `score` is R² (Metrics.r2) like LinearRegression's.
describe "DecisionTreeRegressor" ->
  # x = [[0],[1],[10],[11]], y = [1,1,9,9]. Root mean 5, variance
  # (16+16+16+16)/4 = 16.
  #   @ 0.5:  weighted (3/4)*var([1,9,9]) = (3/4)*(128/9) = 10.667 -> gain 5.333
  #   @ 5.5:  both sides constant, variance 0                     -> gain 16
  #   @ 10.5: mirror of 0.5                                       -> gain 5.333
  # so the root splits at 5.5 and both leaves are exact.
  it "splits on variance and predicts the leaf mean (hand-computed)" ->
    x = [[0], [1], [10], [11]]
    y = [1, 1, 9, 9]
    model = DecisionTreeRegressor.new
    expect(model.fitted?).to be_false
    expect(model.fit(x, y) != nil).to be_true
    expect(model.criterion.to_s).to eq("mse")
    expect(model.tree[:impurity].to_s).to eq("16")
    expect(model.tree[:threshold].to_s).to eq("5.5")
    expect(model.tree[:gain].to_s).to eq("16")
    expect(model.tree[:left][:prediction].to_s).to eq("1")
    expect(model.tree[:right][:prediction].to_s).to eq("9")
    expect(model.tree_lines.join(" | ")).to eq("x0 <= 5.5 |   leaf: 1 (n=2) |   leaf: 9 (n=2)")
    expect(model.score(x, y).to_s).to eq("1")
    # PIECEWISE CONSTANT: a query between the two boxes takes its side's
    # mean, it does not interpolate
    expect(model.predict([[0], [5], [6], [11]]).to_s).to eq("\[1, 1, 9, 9\]")

  # y = 2x on x = 0..3: root mean 3, variance (9+1+1+9)/4 = 5.
  #   @ 0.5: weighted (3/4)*var([2,4,6]) = (3/4)*(8/3) = 2 -> gain 3
  #   @ 1.5: var([0,2]) = var([4,6]) = 1, weighted 1       -> gain 4  (best)
  #   @ 2.5: mirror of 0.5                                 -> gain 3
  # Uncapped it memorizes all four points; the STUMP predicts 1 and 5,
  # leaving SS_res = 4 against SS_tot = 20, so R² = 0.8.
  it "grows to exact leaves, and a stump scores the R² it earns" ->
    x = [[0], [1], [2], [3]]
    y = [0, 2, 4, 6]
    full = DecisionTreeRegressor.new
    full.fit(x, y)
    expect(full.tree[:impurity].to_s).to eq("5")
    expect(full.tree[:threshold].to_s).to eq("1.5")
    expect(full.tree[:gain].to_s).to eq("4")
    expect(full.depth).to eq(2)
    expect(full.leaf_count).to eq(4)
    expect(full.predict(x).to_s).to eq("\[0, 2, 4, 6\]")
    expect(full.score(x, y).to_s).to eq("1")
    stump = DecisionTreeRegressor.new(1)
    stump.fit(x, y)
    expect(stump.predict(x).to_s).to eq("\[1, 1, 5, 5\]")
    expect(stump.score(x, y).to_s).to be_num("0.8")
    # max_depth 0 predicts the global mean, which is exactly R² = 0
    root = DecisionTreeRegressor.new(0)
    root.fit(x, y)
    expect(root.tree[:prediction].to_s).to eq("3")
    expect(root.score(x, y).to_s).to eq("0")

  it "returns nil for a classifier criterion, unusable shapes and before fit" ->
    x = [[0], [1], [10], [11]]
    y = [1, 1, 9, 9]
    expect(DecisionTreeRegressor.new(nil, nil, nil, :gini).fit(x, y)).to be_nil
    expect(DecisionTreeRegressor.new(nil, nil, nil, :entropy).fit(x, y)).to be_nil
    # :variance is accepted as an alias of :mse
    expect(DecisionTreeRegressor.new(nil, nil, nil, :variance).fit(x, y) != nil).to be_true
    model = DecisionTreeRegressor.new
    expect(model.predict([[1]])).to be_nil
    expect(model.score([[1]], [1])).to be_nil
    expect(model.tree).to be_nil
    expect(model.depth).to be_nil
    expect(model.fit([], [])).to be_nil
    expect(model.fit([[1, 2], [3]], [1, 2])).to be_nil
    expect(model.fit([[1], [2]], [1, 2, 3])).to be_nil
    expect(model.fitted?).to be_false
    expect(model.fit(x, y) != nil).to be_true
    expect(model.predict([[1, 2]])).to be_nil

# --- The trees against the estimator contract (lib/estimator_base.w) ---
#
# The same enforcement the five older estimators get: the trees really
# answer every contract method, report the right arity, keep learned state
# out of `params`, and clone correctly. params is compared PER KEY — hash
# to_s key order differs between the two engines.
describe "Decision tree estimator contract" ->
  it "is answered by both trees" ->
    models = [DecisionTreeClassifier.new, DecisionTreeRegressor.new]
    missing = []
    models.each -> (m)
      missing.push(m.estimator_name + ".fitted?") if !m.respond_to?("fitted?")
      missing.push(m.estimator_name + ".fit") if !m.respond_to?("fit")
      missing.push(m.estimator_name + ".predict") if !m.respond_to?("predict")
      missing.push(m.estimator_name + ".score") if !m.respond_to?("score")
      missing.push(m.estimator_name + ".supervised?") if !m.respond_to?("supervised?")
      missing.push(m.estimator_name + ".supports_sample_weight?") if !m.respond_to?("supports_sample_weight?")
      missing.push(m.estimator_name + ".params") if !m.respond_to?("params")
      missing.push(m.estimator_name + ".with_params") if !m.respond_to?("with_params")
      missing.push(m.estimator_name + ".estimator_name") if !m.respond_to?("estimator_name")
    expect(missing.join(",")).to eq("")
    names = []
    models.each -> (m)
      names.push(m.estimator_name)
    expect(names.join(",")).to eq("DecisionTreeClassifier,DecisionTreeRegressor")
    expect(DecisionTreeClassifier.new.supervised?).to be_true
    expect(DecisionTreeRegressor.new.supervised?).to be_true
    expect(DecisionTreeClassifier.new.fitted?).to be_false

  it "reports all four hyperparameters and nothing learned" ->
    m = DecisionTreeClassifier.new(3, 4, 2, :entropy)
    expect(m.params.size).to eq(4)
    expect(m.params[:max_depth]).to eq(3)
    expect(m.params[:min_samples_split]).to eq(4)
    expect(m.params[:min_samples_leaf]).to eq(2)
    expect(m.params[:criterion].to_s).to eq("entropy")
    # the defaults: unlimited depth, sklearn's 2 / 1, gini
    d = DecisionTreeClassifier.new
    expect(d.params[:max_depth]).to be_nil
    expect(d.params[:min_samples_split]).to eq(2)
    expect(d.params[:min_samples_leaf]).to eq(1)
    expect(d.params[:criterion].to_s).to eq("gini")
    expect(DecisionTreeRegressor.new.params[:criterion].to_s).to eq("mse")
    # fitting adds no key — the tree itself never leaks into the search space
    m.fit([[0], [1], [10], [11]], [0, 0, 1, 1])
    expect(m.fitted?).to be_true
    expect(m.params.size).to eq(4)
    expect(m.params[:max_depth]).to eq(3)

  it "round-trips params through with_params and clones unfitted" ->
    drift = []
    models = [DecisionTreeClassifier.new(3, 4, 2, :entropy), DecisionTreeRegressor.new(2)]
    models.each -> (m)
      copy = m.with_params(m.params)
      before = m.params
      after = copy.params
      drift.push(m.estimator_name + ".size") if before.size != after.size
      before.each -> (k, v)
        drift.push(m.estimator_name + "." + k.to_s) if after[k].to_s != v.to_s
    expect(drift.join(",")).to eq("")
    # unmentioned keys carry over on a partial override
    proto = DecisionTreeClassifier.new(3, 4, 2, :entropy)
    part = proto.with_params({ max_depth: 9 })
    expect(part.params[:max_depth]).to eq(9)
    expect(part.params[:min_samples_split]).to eq(4)
    expect(part.params[:criterion].to_s).to eq("entropy")
    # key PRESENCE decides — an explicit nil max_depth means "unlimited"
    expect(proto.with_params({ max_depth: nil }).params[:max_depth]).to be_nil
    expect(proto.params[:max_depth]).to eq(3)
    # the clone is FRESH and UNFITTED, and fitting it leaves self alone
    x = [[0], [1], [10], [11]]
    y = [0, 0, 1, 1]
    proto.fit(x, y)
    clone = proto.with_params({ max_depth: 1 })
    expect(clone.fitted?).to be_false
    expect(clone.tree).to be_nil
    expect(clone.predict(x)).to be_nil
    clone.fit(x, y)
    expect(proto.params[:max_depth]).to eq(3)
    expect(proto.fitted?).to be_true

  # The payoff of conforming: generic tooling drives a tree without naming
  # it. CrossValidation dispatches through supervised?, GridSearch tunes
  # max_depth through params / with_params, and a Pipeline exposes the tree's
  # knobs as "tree.max_depth" with no code in pipeline.w aware trees exist.
  it "cross-validates, grid-searches and pipelines through the contract alone" ->
    x = [[0, 0], [1, 0], [0, 1], [1, 1], [10, 10], [11, 10], [10, 11], [11, 11]]
    y = [0, 0, 0, 0, 1, 1, 1, 1]
    expect(Estimator.fit_model(DecisionTreeClassifier.new, x, y) != nil).to be_true
    expect(CrossValidation.cross_val_mean(DecisionTreeClassifier.new, x, y, 4).to_s).to eq("1")
    gs = GridSearch.new(DecisionTreeClassifier.new, { max_depth: [1, 2] }, 4)
    expect(gs.size).to eq(2)
    expect(gs.fit(x, y) != nil).to be_true
    # both depths separate these two blobs perfectly, so the tie goes to the
    # FIRST candidate in enumeration order — the simpler max_depth 1
    expect(gs.best_params[:max_depth]).to eq(1)
    expect(gs.best_score.to_s).to eq("1")
    expect(gs.best_estimator.estimator_name).to eq("DecisionTreeClassifier")
    expect(gs.best_estimator.fitted?).to be_true
    expect(gs.best_estimator.depth).to eq(1)
    ranked = ""
    gs.results.each -> (e)
      ranked += e[:params][:max_depth].to_s + ":" + e[:score].to_s + ":" + e[:rank].to_s + " "
    expect(ranked).to eq("1:1:1 2:1:2 ")
    # the criterion is searchable too
    gc = GridSearch.new(DecisionTreeClassifier.new, { criterion: [:gini, :entropy] }, 4)
    expect(gc.fit(x, y) != nil).to be_true
    expect(gc.best_params[:criterion].to_s).to eq("gini")

  it "works as a Pipeline tail and exposes its knobs to the search" ->
    df = DataFrame.new([[:f, [0, 1, 10, 11]]])
    y = [0, 0, 1, 1]
    pipe = Pipeline.new([[:scale, Scaler.new(:standard)], [:tree, DecisionTreeClassifier.new(2)]])
    expect(pipe.names.join(",")).to eq("scale,tree")
    expect(pipe.supervised?).to be_true
    expect(pipe.predict(df)).to be_nil
    expect(pipe.fit(df, y) != nil).to be_true
    expect(pipe.predict(df).to_s).to eq("\[0, 0, 1, 1\]")
    expect(pipe.score(df, y).to_s).to eq("1")
    # all four tree knobs joined the pipeline's search space, dotted
    keys = []
    pipe.params.keys.each -> (k)
      keys.push(k.to_s)
    expect(keys.include?("tree.max_depth")).to be_true
    expect(keys.include?("tree.criterion")).to be_true
    expect(pipe.params["tree.max_depth"]).to eq(2)
    tuned = pipe.with_params({ "tree.max_depth" => 1 })
    expect(tuned.params["tree.max_depth"]).to eq(1)
    expect(tuned.fitted?).to be_false
    expect(pipe.params["tree.max_depth"]).to eq(2)

describe "KFold" ->
  # Shuffle-free folds are contiguous blocks of 0...n, scikit-learn's
  # KFold(shuffle=False): 10 samples in 5 folds are five [0,1] .. [8,9]
  # test slices, each fold's train set the other eight indices in order.
  it "partitions 0...n into k contiguous folds (shuffle-free)" ->
    folds = KFold.new(5).split(10)
    expect(folds.size).to eq(5)
    expect(folds[0][1].to_s).to eq("\[0, 1\]")
    expect(folds[0][0].to_s).to eq("\[2, 3, 4, 5, 6, 7, 8, 9\]")
    expect(folds[4][1].to_s).to eq("\[8, 9\]")

  # scikit-learn puts the remainder in the FIRST folds: n=10, k=3 gives
  # fold sizes 4, 3, 3 (floor 3, one extra on fold 0); every index lands
  # in exactly one test fold.
  it "makes the first n mod k folds larger, like scikit-learn" ->
    folds = KFold.new(3).split(10)
    expect(folds[0][1].to_s).to eq("\[0, 1, 2, 3\]")
    expect(folds[1][1].to_s).to eq("\[4, 5, 6\]")
    expect(folds[2][1].to_s).to eq("\[7, 8, 9\]")
    f7 = KFold.new(3).split(7)
    expect(f7[0][1].size).to eq(3)
    expect(f7[1][1].size).to eq(2)
    expect(f7[2][1].size).to eq(2)

  it "returns nil when k is out of range" ->
    expect(KFold.new(1).split(10)).to be_nil
    expect(KFold.new(11).split(10)).to be_nil
    expect(KFold.new(3).split(0)).to be_nil

  # A seed shuffles the indices first through koala's MINSTD generator
  # (Splitter.indices) — seed 42 permutes 0..9 to [0,1,4,3,8,9,7,5,6,2],
  # the same permutation Splitter documents — then folds them contiguously,
  # so the same seed gives the same folds on both engines.
  it "shuffles deterministically with a seed" ->
    folds = KFold.new(5, 42).split(10)
    expect(folds[1][1].to_s).to eq("\[4, 3\]")
    expect(folds[2][1].to_s).to eq("\[8, 9\]")
    again = KFold.new(5, 42).split(10)
    expect(folds[3][1].to_s).to eq(again[3][1].to_s)

describe "CrossValidation" ->
  # y = 2x + 1 is exactly linear, so every 8-row training fold recovers
  # slope 2 / intercept 1 and predicts its two held-out rows exactly:
  # R² = 1 on all five folds, and on their mean.
  it "scores each fold of an exact linear fit as 1" ->
    x = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    y = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19]
    scores = CrossValidation.cross_val_score(LinearRegression.new, x, y, 5)
    expect(scores.size).to eq(5)
    expect(scores.to_s).to eq("\[1, 1, 1, 1, 1\]")
    expect(CrossValidation.cross_val_mean(LinearRegression.new, x, y, 5).to_s).to eq("1")

  # Two separated clusters, k = 1 nearest neighbour, three contiguous
  # folds: each held-out point's nearest surviving training point shares
  # its class, so every fold's accuracy is 1 (hand-checked against the
  # squared-Euclidean distances in cross_validation.w).
  it "cross-validates a classifier by accuracy" ->
    x = [[1, 1], [2, 2], [3, 3], [6, 6], [7, 7], [8, 8]]
    y = [0, 0, 0, 1, 1, 1]
    scores = CrossValidation.cross_val_score(KNNClassifier.new(1), x, y, 3)
    expect(scores.to_s).to eq("\[1, 1, 1\]")
    expect(CrossValidation.cross_val_mean(KNNClassifier.new(1), x, y, 3).to_s).to eq("1")

  it "returns nil for unusable inputs" ->
    m = LinearRegression.new
    expect(CrossValidation.cross_val_score(m, [1, 2, 3], [1, 2])).to be_nil
    expect(CrossValidation.cross_val_score(m, [1, 2, 3], [1, 2, 3], 5)).to be_nil
    expect(CrossValidation.cross_val_mean(m, [1, 2, 3], [1, 2], 2)).to be_nil
    # a supervised estimator still REQUIRES its y
    expect(CrossValidation.cross_val_score(m, [1, 2, 3], nil, 2)).to be_nil

  # Unsupervised CV: no y at all. Fit and score go through
  # Estimator.fit_model / .score_model, so KMeans gets fit(rows) / score(rows).
  #
  # HAND-COMPUTED, both folds. The 8 rows interleave two unit squares —
  # one at the origin, one at (10, 10) — so each contiguous 2-fold split
  # trains on one full sample of both clusters:
  #   fold 0 trains on [1,0], [11,10], [1,1], [11,11] -> centroids
  #   [1, 0.5] and [11, 10.5]; its held-out rows [0,0], [10,10], [0,1],
  #   [10,11] each sit (1, 0.5) from their centre -> 1 + 0.25 = 1.25 each,
  #   inertia 5, score -5. Fold 1 is the mirror image, also -5.
  it "cross-validates an unsupervised estimator with no y" ->
    x = [[0, 0], [10, 10], [0, 1], [10, 11], [1, 0], [11, 10], [1, 1], [11, 11]]
    scores = CrossValidation.cross_val_score(KMeans.new(2), x, nil, 2)
    expect(scores.size).to eq(2)
    expect(scores.to_s).to eq("\[-5, -5\]")
    expect(CrossValidation.cross_val_mean(KMeans.new(2), x, nil, 2).to_s).to eq("-5")

  # A fold whose re-fit FAILS must not be scored: the estimator still
  # carries the previous fold's state, so scoring it would quietly report
  # the wrong model. Collinear features are singular at alpha = 0.
  it "records nil for a fold whose fit fails, and never scores stale state" ->
    x = [[1, 2], [2, 4], [3, 6], [4, 8], [5, 10], [6, 12]]
    y = [1, 2, 3, 4, 5, 6]
    scores = CrossValidation.cross_val_score(LinearRegression.new(0), x, y, 3)
    expect(scores.size).to eq(3)
    expect(scores[0]).to be_nil
    expect(scores[2]).to be_nil
    expect(CrossValidation.cross_val_mean(LinearRegression.new(0), x, y, 3)).to be_nil
    # ridge at alpha = 1 is non-singular on the same data
    expect(CrossValidation.cross_val_mean(LinearRegression.new(1), x, y, 3) != nil).to be_true

describe "KMeans" ->
  # Two 2x2 boxes far apart. Default init takes the first two DISTINCT
  # rows ([0,0], [2,0]) as centroids; Lloyd converges in two iterations
  # to the natural clusters. Hand-computed (matches scikit-learn KMeans
  # with this fixed init, n_init=1): centroids [[1,1],[11,11]], labels
  # [0,0,0,0,1,1,1,1], inertia exactly 16 (each point sqrt(2) from its
  # centroid, squared 2, times eight points), n_iter 2.
  it "clusters two separated boxes to the hand-computed reference" ->
    x = [[0, 0], [2, 0], [0, 2], [2, 2], [10, 10], [12, 10], [10, 12], [12, 12]]
    model = KMeans.new(2)
    expect(model.fitted?).to be_false
    r = model.fit(x)
    expect(r != nil).to be_true
    expect(model.fitted?).to be_true
    expect(model.labels.to_s).to eq("\[0, 0, 0, 0, 1, 1, 1, 1\]")
    expect(model.centroids.to_s).to eq("\[\[1, 1\], \[11, 11\]\]")
    expect(model.inertia.to_s).to eq("16")
    expect(model.n_iter.to_s).to eq("2")

  # predict assigns fresh rows to the nearest fitted centroid; a row
  # whose width differs from the fitted feature count returns nil.
  it "assigns new rows to the nearest centroid" ->
    x = [[0, 0], [2, 0], [0, 2], [2, 2], [10, 10], [12, 10], [10, 12], [12, 12]]
    model = KMeans.new(2)
    model.fit(x)
    expect(model.predict([[1, 1], [11, 11], [0, 0], [12, 12]]).to_s).to eq("\[0, 1, 0, 1\]")
    expect(model.predict([[1, 2, 3]])).to be_nil

  # fit_predict returns the training labels in one call; score is the
  # NEGATED within-cluster sum of squares (sklearn's convention), so on
  # the training rows it is -inertia = -16.
  it "fit_predicts and scores as negative inertia" ->
    x = [[0, 0], [2, 0], [0, 2], [2, 2], [10, 10], [12, 10], [10, 12], [12, 12]]
    expect(KMeans.new(2).fit_predict(x).to_s).to eq("\[0, 0, 0, 0, 1, 1, 1, 1\]")
    model = KMeans.new(2)
    model.fit(x)
    expect(model.score(x).to_s).to eq("-16")

  # Same accepted shapes as the estimators, via the shared feature_rows:
  # a DataFrame (numeric columns only — :name is skipped) and a flat
  # single-feature array both cluster. df centroids [[0.5,0.5],[10.5,10.5]],
  # inertia 2 (each of four points 0.5 from its centroid in each of two
  # dims: 0.25+0.25 = 0.5, times four).
  it "accepts DataFrame and flat-array inputs" ->
    df = DataFrame.new([
      [:name, ["a", "b", "c", "d"]],
      [:f1, [0, 1, 10, 11]],
      [:f2, [0, 1, 10, 11]]
    ])
    dm = KMeans.new(2)
    dm.fit(df)
    expect(dm.labels.to_s).to eq("\[0, 0, 1, 1\]")
    expect(dm.centroids.to_s).to eq("\[\[0.5, 0.5\], \[10.5, 10.5\]\]")
    expect(dm.inertia.to_s).to eq("2")
    fm = KMeans.new(2)
    fm.fit([0, 1, 2, 100, 101, 102])
    expect(fm.labels.to_s).to eq("\[0, 0, 0, 1, 1, 1\]")
    expect(fm.centroids.to_s).to eq("\[\[1\], \[101\]\]")

  # k = 1 collapses every row into one cluster whose centroid is the
  # global mean; the eight box corners mean to (6, 6).
  it "puts every row in one cluster at the global mean when k = 1" ->
    x = [[0, 0], [2, 0], [0, 2], [2, 2], [10, 10], [12, 10], [10, 12], [12, 12]]
    model = KMeans.new(1)
    model.fit(x)
    expect(model.centroids.to_s).to eq("\[\[6, 6\]\]")
    expect(model.labels.to_s).to eq("\[0, 0, 0, 0, 0, 0, 0, 0\]")

  # The only randomness in k-means is the initial centroids, so a seed
  # makes the whole clustering reproducible: koala shuffles the rows
  # through Splitter's MINSTD generator, then seeds from the first k
  # distinct. Same seed, byte-identical labels/centroids/inertia; and on
  # separable data every valid init recovers the same partition (inertia
  # 16, invariant to which cluster is numbered 0).
  it "is deterministic under a seed" ->
    x = [[0, 0], [2, 0], [0, 2], [2, 2], [10, 10], [12, 10], [10, 12], [12, 12]]
    a = KMeans.new(2, 42)
    a.fit(x)
    b = KMeans.new(2, 42)
    b.fit(x)
    expect(a.labels.to_s).to eq(b.labels.to_s)
    expect(a.centroids.to_s).to eq(b.centroids.to_s)
    expect(a.inertia.to_s).to eq(b.inertia.to_s)
    expect(a.inertia.to_s).to eq("16")

  # Unusable shapes and premature calls all return nil and leave fitted?
  # false — the bit's shape-error convention, matching the estimators.
  it "returns nil for unusable shapes and before fit" ->
    expect(KMeans.new(2).fit([])).to be_nil
    expect(KMeans.new(9).fit([[1, 1], [2, 2]])).to be_nil
    expect(KMeans.new(2).fit([[1, 2], [3]])).to be_nil
    expect(KMeans.new(0).fit([[1, 1], [2, 2]])).to be_nil
    model = KMeans.new(2)
    expect(model.predict([[1, 1]])).to be_nil
    expect(model.score([[1, 1]])).to be_nil
    expect(model.fitted?).to be_false
    expect(KMeans.new.k).to eq(8)

# --- The estimator contract (lib/estimator_base.w) ---
#
# `is Estimable` / `is SupervisedEstimator` / `is UnsupervisedEstimator`
# DECLARE conformance but the engines do not enforce it — a class naming a
# trait it does not satisfy still compiles. These specs are the enforcement:
# they walk ALL FIVE estimators and assert each really answers the contract,
# reports the right arity through supervised?, and clones correctly.
#
# params is compared PER KEY (params[:alpha]), never as a whole-hash string —
# hash to_s key order differs between the two engines.
describe "Estimator contract" ->
  it "is answered by all five estimators" ->
    models = [LinearRegression.new, KNNClassifier.new, LogisticRegression.new, GaussianNB.new, KMeans.new]
    expect(models.size).to eq(5)
    missing = []
    models.each -> (m)
      missing.push(m.estimator_name + ".fitted?") if !m.respond_to?("fitted?")
      missing.push(m.estimator_name + ".fit") if !m.respond_to?("fit")
      missing.push(m.estimator_name + ".predict") if !m.respond_to?("predict")
      missing.push(m.estimator_name + ".score") if !m.respond_to?("score")
      missing.push(m.estimator_name + ".supervised?") if !m.respond_to?("supervised?")
      missing.push(m.estimator_name + ".supports_sample_weight?") if !m.respond_to?("supports_sample_weight?")
      missing.push(m.estimator_name + ".params") if !m.respond_to?("params")
      missing.push(m.estimator_name + ".with_params") if !m.respond_to?("with_params")
      missing.push(m.estimator_name + ".estimator_name") if !m.respond_to?("estimator_name")
    expect(missing.join(",")).to eq("")

  it "names every estimator (type() is not reliable interpreted)" ->
    names = []
    models = [LinearRegression.new, KNNClassifier.new, LogisticRegression.new, GaussianNB.new, KMeans.new]
    models.each -> (m)
      names.push(m.estimator_name)
    expect(names.join(",")).to eq("LinearRegression,KNNClassifier,LogisticRegression,GaussianNB,KMeans")

  it "starts every estimator unfitted" ->
    unfitted = true
    models = [LinearRegression.new, KNNClassifier.new, LogisticRegression.new, GaussianNB.new, KMeans.new]
    models.each -> (m)
      unfitted = false if m.fitted?
    expect(unfitted).to be_true

  # The four supervised learners take fit(x, y); KMeans alone takes fit(x).
  it "declares supervised? — true for the four, false for KMeans" ->
    expect(LinearRegression.new.supervised?).to be_true
    expect(KNNClassifier.new.supervised?).to be_true
    expect(LogisticRegression.new.supervised?).to be_true
    expect(GaussianNB.new.supervised?).to be_true
    expect(KMeans.new.supervised?).to be_false

  it "reports only hyperparameters from params, never learned state" ->
    expect(LinearRegression.new(12).params[:alpha]).to eq(12)
    expect(LinearRegression.new(12).params.size).to eq(1)
    expect(KNNClassifier.new(3).params[:k]).to eq(3)
    expect(KNNClassifier.new(3).params.size).to eq(1)
    expect(LogisticRegression.new(nil, 40).params[:epochs]).to eq(40)
    expect(LogisticRegression.new(nil, 40).params.size).to eq(2)
    expect(GaussianNB.new.params.size).to eq(1)
    expect(KMeans.new(2, 7, 50).params[:k]).to eq(2)
    expect(KMeans.new(2, 7, 50).params[:seed]).to eq(7)
    expect(KMeans.new(2, 7, 50).params[:max_iter]).to eq(50)
    expect(KMeans.new(2, 7, 50).params.size).to eq(3)

  # params still reports the CONSTRUCTOR knobs after a fit — learned state
  # (coefficients, centroids) never leaks into the search space.
  it "keeps params free of learned state after fitting" ->
    m = LinearRegression.new(12)
    m.fit([[0, 0], [2, 0], [0, 2], [2, 2]], [3, 5, 7, 9])
    expect(m.fitted?).to be_true
    expect(m.params.size).to eq(1)
    expect(m.params[:alpha]).to eq(12)
    km = KMeans.new(2)
    km.fit([[0, 0], [2, 0], [10, 10], [12, 12]])
    expect(km.fitted?).to be_true
    expect(km.params.size).to eq(3)
    expect(km.params[:k]).to eq(2)

  # with_params(params) must be the identity on the hyperparameters.
  it "round-trips params through with_params for all five" ->
    drift = []
    models = [LinearRegression.new(12), KNNClassifier.new(3), LogisticRegression.new(nil, 40), GaussianNB.new, KMeans.new(2, 7, 50)]
    models.each -> (m)
      copy = m.with_params(m.params)
      before = m.params
      after = copy.params
      drift.push(m.estimator_name + ".size") if before.size != after.size
      before.each -> (k, v)
        drift.push(m.estimator_name + "." + k.to_s) if after[k].to_s != v.to_s
    expect(drift.join(",")).to eq("")

  it "carries unmentioned keys over on a partial override" ->
    m = KMeans.new(2, 7, 50)
    c = m.with_params({ k: 4 })
    expect(c.params[:k]).to eq(4)
    expect(c.params[:seed]).to eq(7)
    expect(c.params[:max_iter]).to eq(50)
    l = LogisticRegression.new(nil, 40).with_params({ epochs: 5 })
    expect(l.params[:epochs]).to eq(5)
    expect(l.params[:learning_rate].to_s).to eq(LogisticRegression.new.learning_rate.to_s)

  # Key PRESENCE decides, not the value — so an explicit nil clears a knob.
  it "applies an override whose value is nil" ->
    m = KMeans.new(2, 7, 50)
    expect(m.params[:seed]).to eq(7)
    expect(m.with_params({ seed: nil }).params[:seed]).to be_nil
    expect(m.with_params({ seed: nil }).params[:k]).to eq(2)
    expect(m.params[:seed]).to eq(7)

  it "returns a FRESH UNFITTED clone from with_params, leaving self alone" ->
    x = [[0, 0], [2, 0], [0, 2], [2, 2]]
    y = [3, 5, 7, 9]
    m = LinearRegression.new(12)
    m.fit(x, y)
    expect(m.fitted?).to be_true
    c = m.with_params({ alpha: 3 })
    expect(c.fitted?).to be_false
    expect(c.alpha).to eq(3)
    expect(c.coefficients).to be_nil
    expect(c.predict(x)).to be_nil
    # the original keeps its own hyperparameter AND its fitted state
    expect(m.alpha).to eq(12)
    expect(m.fitted?).to be_true
    expect(m.predict(x) != nil).to be_true
    # fitting the clone does not disturb the original
    c.fit(x, y)
    expect(c.fitted?).to be_true
    expect(m.alpha).to eq(12)
    expect(m.params[:alpha]).to eq(12)

  it "returns an unfitted clone for every estimator" ->
    fitted_clones = []
    models = [LinearRegression.new(12), KNNClassifier.new(3), LogisticRegression.new(nil, 40), GaussianNB.new, KMeans.new(2, 7, 50)]
    models.each -> (m)
      c = m.with_params({})
      fitted_clones.push(m.estimator_name) if c.fitted?
    expect(fitted_clones.join(",")).to eq("")

  # An empty override hash is a plain clone of the hyperparameters.
  it "clones unchanged from an empty override hash" ->
    expect(LinearRegression.new(12).with_params({}).params[:alpha]).to eq(12)
    expect(KNNClassifier.new(3).with_params({}).params[:k]).to eq(3)
    expect(KMeans.new(2, 7, 50).with_params({}).params[:max_iter]).to eq(50)

describe "Estimator input coercion" ->
  # Coercion is defined ONCE on the neutral base — no estimator depends on a
  # concrete sibling for it any more.
  it "normalizes every accepted x shape from the neutral base" ->
    expect(Estimator.feature_rows([1, 2, 3]).to_s).to eq("\[\[1\], \[2\], \[3\]\]")
    expect(Estimator.feature_rows([[1, 2], [3, 4]]).to_s).to eq("\[\[1, 2\], \[3, 4\]\]")
    expect(Estimator.feature_rows([]).to_s).to eq("\[\]")
    expect(Estimator.feature_rows(Matrix.new([[1, 2], [3, 4]])).to_s).to eq("\[\[1, 2\], \[3, 4\]\]")
    df = DataFrame.new([[:a, [1, 2]], [:b, [3, 4]]])
    expect(Estimator.feature_rows(df).to_s).to eq("\[\[1, 3\], \[2, 4\]\]")

  it "normalizes every accepted y shape from the neutral base" ->
    expect(Estimator.target_values([1, 2]).to_s).to eq("\[1, 2\]")
    expect(Estimator.target_values(Series.new([1, 2])).to_s).to eq("\[1, 2\]")
    expect(Estimator.target_values(Vector.new([1, 2])).to_s).to eq("\[1, 2\]")

  # LinearRegression.feature_rows / .target_values are kept as delegating
  # aliases so callers written before the move keep working.
  it "keeps the LinearRegression aliases delegating" ->
    expect(LinearRegression.feature_rows([1, 2]).to_s).to eq(Estimator.feature_rows([1, 2]).to_s)
    expect(LinearRegression.feature_rows([[1, 2]]).to_s).to eq(Estimator.feature_rows([[1, 2]]).to_s)
    expect(LinearRegression.target_values([1, 2]).to_s).to eq(Estimator.target_values([1, 2]).to_s)
    expect(LinearRegression.target_values(Series.new([3, 4])).to_s).to eq("\[3, 4\]")

  it "reads an override with Estimator.opt by key presence" ->
    expect(Estimator.opt({ alpha: 9 }, :alpha, 1)).to eq(9)
    expect(Estimator.opt({ beta: 9 }, :alpha, 1)).to eq(1)
    expect(Estimator.opt({}, :alpha, 1)).to eq(1)
    expect(Estimator.opt(nil, :alpha, 1)).to eq(1)
    expect(Estimator.opt({ alpha: nil }, :alpha, 1)).to be_nil

describe "Estimator arity-safe dispatch" ->
  # What supervised? is FOR: generic tooling fits and scores without knowing
  # which arity a given estimator takes.
  it "fits and scores a supervised estimator through fit_model" ->
    x = [[0, 0], [2, 0], [0, 2], [2, 2]]
    y = [3, 5, 7, 9]
    m = Estimator.fit_model(LinearRegression.new, x, y)
    expect(m != nil).to be_true
    expect(m.fitted?).to be_true
    expect(Estimator.score_model(m, x, y).to_s).to eq("1")

  it "fits and scores an unsupervised estimator through fit_model" ->
    x = [[0, 0], [2, 0], [0, 2], [2, 2], [10, 10], [12, 10], [10, 12], [12, 12]]
    m = Estimator.fit_model(KMeans.new(2), x, nil)
    expect(m != nil).to be_true
    expect(m.fitted?).to be_true
    expect(m.inertia.to_s).to eq("16")
    # sklearn's convention: score is -inertia, so the y argument is ignored
    expect(Estimator.score_model(m, x, nil).to_s).to eq("-16")

  it "dispatches across all five without knowing their arity" ->
    x = [[0, 0], [2, 0], [0, 2], [2, 2]]
    y = [3, 5, 7, 9]
    labels = [0, 0, 1, 1]
    failures = []
    models = [LinearRegression.new, KNNClassifier.new(1), KMeans.new(2)]
    targets = [y, labels, nil]
    i = 0
    models.each -> (m)
      f = Estimator.fit_model(m, x, targets[i])
      failures.push(m.estimator_name) if f == nil
      failures.push(m.estimator_name + ".score") if Estimator.score_model(m, x, targets[i]) == nil
      i += 1
    expect(failures.join(",")).to eq("")

# --- GridSearch (lib/grid_search.w) ---
#
# The reference winners below are HAND-COMPUTED, never read back off the
# implementation, so the assertions test the SEARCH and not its plumbing:
#
#   * KNN grid — x = [0,1,2,3, 10,11,12,13], labels [0,0,0,0, 1,1,1,1],
#     4 contiguous folds (test pairs [0,1] [2,3] [4,5] [6,7]). At k = 1
#     and k = 3 every held-out point's neighbours are all its own class,
#     so accuracy is 1 on all four folds. At k = 5 the six training rows
#     always include four of the OTHER class, so every vote flips and
#     accuracy is 0 on all four folds. Winner: k = 1 (or whichever of
#     1 / 3 is enumerated first), score exactly 1; k = 5 scores 0.
#   * Ridge grid — y = 2x + 1 on x = 0..7, 4 folds. Each 6-row training
#     fold recovers the exact line, so alpha = 0 predicts its held-out
#     pair exactly: R² = 1 on every fold. alpha = 100 shrinks the slope
#     to near nothing and scores far below. Winner: alpha = 0, score 1.
#   * Collinear grid — x = [[i, 2i]], 3 folds. X^T X is singular, so
#     alpha = 0 CANNOT FIT: every fold is nil and the candidate's mean is
#     nil. alpha = 1 is non-singular. Winner: alpha = 1, and alpha = 0
#     ranks last with a nil score.
#   * KMeans grid — the interleaved two-square data from the
#     CrossValidation block, 2 folds: k = 2 scores -5, k = 1 scores -205
#     (both hand-computed there and above).
#
# Whole-hash to_s is never asserted (key order differs between engines) —
# params are read per key.
describe "GridSearch grid enumeration" ->
  # Pure functions of the grid: no estimator, no data, no CV.
  it "enumerates the cartesian product with sorted keys, last varying fastest" ->
    cands = GridSearch.candidates({ b: [1, 2], a: [3, 4] })
    expect(cands.size).to eq(4)
    sig = ""
    cands.each -> (h)
      sig += h[:a].to_s + "/" + h[:b].to_s + " "
    expect(sig).to eq("3/1 3/2 4/1 4/2 ")

  # The order must NOT depend on hash iteration order: the same literal
  # yields .keys in one order interpreted and another compiled.
  it "orders keys by name, never by hash iteration order" ->
    expect(GridSearch.grid_keys({ zebra: 1, alpha: 2, mid: 3 }).join(",")).to eq("alpha,mid,zebra")
    expect(GridSearch.grid_keys({ alpha: 1, mid: 2, zebra: 3 }).join(",")).to eq("alpha,mid,zebra")
    expect(GridSearch.grid_keys({}).size).to eq(0)
    expect(GridSearch.grid_keys(nil)).to be_nil

  it "preserves each value list's given order" ->
    vs = ""
    GridSearch.candidates({ k: [5, 1, 3] }).each -> (h)
      vs += h[:k].to_s + ","
    expect(vs).to eq("5,1,3,")

  it "expands a two-key grid over both axes" ->
    cands = GridSearch.candidates({ epochs: [10, 20], learning_rate: [1, 2, 3] })
    expect(cands.size).to eq(6)
    sig = ""
    cands.each -> (h)
      sig += h[:learning_rate].to_s + "@" + h[:epochs].to_s + " "
    expect(sig).to eq("1@10 2@10 3@10 1@20 2@20 3@20 ")

  it "takes a bare value as a one-element list" ->
    cands = GridSearch.candidates({ k: 3 })
    expect(cands.size).to eq(1)
    expect(cands[0][:k]).to eq(3)

  it "returns nil for a nil, empty, or empty-valued grid" ->
    expect(GridSearch.candidates(nil)).to be_nil
    expect(GridSearch.candidates({})).to be_nil
    expect(GridSearch.candidates({ k: [] })).to be_nil
    expect(GridSearch.candidates({ k: [1], j: [] })).to be_nil

describe "GridSearch (supervised)" ->
  # k = 1 is enumerated SECOND, so a winner of 1 proves the search really
  # compares scores rather than keeping the first candidate.
  it "elects the k that must win even when enumerated last" ->
    x = [0, 1, 2, 3, 10, 11, 12, 13]
    y = [0, 0, 0, 0, 1, 1, 1, 1]
    gs = GridSearch.new(KNNClassifier.new, { k: [5, 1] }, 4)
    expect(gs.fitted?).to be_false
    expect(gs.size).to eq(2)
    r = gs.fit(x, y)
    expect(r != nil).to be_true
    expect(gs.fitted?).to be_true
    expect(gs.best_params[:k]).to eq(1)
    expect(gs.best_score.to_s).to eq("1")
    expect(gs.results.size).to eq(2)
    expect(gs.results[0][:params][:k]).to eq(1)
    expect(gs.results[0][:rank]).to eq(1)
    expect(gs.results[1][:params][:k]).to eq(5)
    expect(gs.results[1][:score].to_s).to eq("0")
    expect(gs.results[1][:rank]).to eq(2)

  # k = 1 and k = 3 both score exactly 1. The winner must be whichever the
  # grid lists FIRST — reversing the list reverses the winner, which no
  # value-based tie-break could do.
  it "breaks a tie toward the first candidate in enumeration order" ->
    x = [0, 1, 2, 3, 10, 11, 12, 13]
    y = [0, 0, 0, 0, 1, 1, 1, 1]
    a = GridSearch.new(KNNClassifier.new, { k: [1, 3, 5] }, 4)
    a.fit(x, y)
    expect(a.best_params[:k]).to eq(1)
    b = GridSearch.new(KNNClassifier.new, { k: [3, 1, 5] }, 4)
    b.fit(x, y)
    expect(b.best_params[:k]).to eq(3)
    # ranking is STABLE: the tied pair keeps enumeration order, 5 sinks
    order = ""
    b.results.each -> (e)
      order += e[:params][:k].to_s + e[:rank].to_s + " "
    expect(order).to eq("31 12 53 ")

  it "elects alpha = 0 on a perfectly linear fit (R² exactly 1)" ->
    x = [0, 1, 2, 3, 4, 5, 6, 7]
    y = [1, 3, 5, 7, 9, 11, 13, 15]
    gs = GridSearch.new(LinearRegression.new, { alpha: [100, 0] }, 4)
    gs.fit(x, y)
    expect(gs.best_params[:alpha]).to eq(0)
    expect(gs.best_score.to_s).to eq("1")
    expect(gs.results[1][:params][:alpha]).to eq(100)
    expect(gs.results[1][:score] < gs.best_score).to be_true

  # alpha = 0 is singular here — it scores nil on every fold — so ridge
  # must win, and the unscorable candidate must still be reported.
  it "ranks a nil-scoring candidate last and never lets it win" ->
    x = [[1, 2], [2, 4], [3, 6], [4, 8], [5, 10], [6, 12]]
    y = [1, 2, 3, 4, 5, 6]
    gs = GridSearch.new(LinearRegression.new, { alpha: [0, 1] }, 3)
    gs.fit(x, y)
    expect(gs.best_params[:alpha]).to eq(1)
    expect(gs.best_score != nil).to be_true
    expect(gs.results[0][:params][:alpha]).to eq(1)
    expect(gs.results[1][:params][:alpha]).to eq(0)
    expect(gs.results[1][:score]).to be_nil
    expect(gs.results[1][:rank]).to eq(2)

  it "refits the winner on the full data and delegates predict / score" ->
    x = [0, 1, 2, 3, 10, 11, 12, 13]
    y = [0, 0, 0, 0, 1, 1, 1, 1]
    gs = GridSearch.new(KNNClassifier.new, { k: [5, 1] }, 4)
    gs.fit(x, y)
    best = gs.best_estimator
    expect(best != nil).to be_true
    expect(best.fitted?).to be_true
    expect(best.k).to eq(1)
    expect(best.estimator_name).to eq("KNNClassifier")
    expect(gs.predict([0, 13]).to_s).to eq("\[0, 1\]")
    expect(gs.score(x, y).to_s).to eq("1")
    expect(gs.estimator_name).to eq("GridSearch(KNNClassifier)")

  it "leaves best_estimator nil when refit is false" ->
    x = [0, 1, 2, 3, 10, 11, 12, 13]
    y = [0, 0, 0, 0, 1, 1, 1, 1]
    gs = GridSearch.new(KNNClassifier.new, { k: [1, 3] }, 4, nil, false)
    expect(gs.fit(x, y) != nil).to be_true
    expect(gs.best_params[:k]).to eq(1)
    expect(gs.results.size).to eq(2)
    expect(gs.best_estimator).to be_nil
    expect(gs.predict(x)).to be_nil
    expect(gs.score(x, y)).to be_nil

  # Candidates are clones: the prototype is never fitted or re-tuned.
  it "never mutates the prototype estimator" ->
    x = [0, 1, 2, 3, 10, 11, 12, 13]
    y = [0, 0, 0, 0, 1, 1, 1, 1]
    proto = KNNClassifier.new(7)
    gs = GridSearch.new(proto, { k: [1, 3] }, 4)
    gs.fit(x, y)
    expect(proto.k).to eq(7)
    expect(proto.fitted?).to be_false

describe "GridSearch (unsupervised)" ->
  # No y anywhere: fit(x) alone. KMeans reports supervised? false, so
  # CrossValidation calls fit(rows) / score(rows) through the contract's
  # arity-safe dispatch — GridSearch itself has no idea which kind it holds.
  it "searches an unsupervised estimator with no y" ->
    x = [[0, 0], [10, 10], [0, 1], [10, 11], [1, 0], [11, 10], [1, 1], [11, 11]]
    gs = GridSearch.new(KMeans.new(2), { k: [1, 2] }, 2)
    r = gs.fit(x)
    expect(r != nil).to be_true
    expect(gs.best_params[:k]).to eq(2)
    expect(gs.best_score.to_s).to eq("-5")
    expect(gs.results[1][:params][:k]).to eq(1)
    expect(gs.results[1][:score].to_s).to eq("-205")
    expect(gs.best_estimator.fitted?).to be_true
    expect(gs.best_estimator.estimator_name).to eq("KMeans")

  # Unmentioned params carry over from the prototype through with_params.
  it "carries the prototype's other params into every candidate" ->
    x = [[0, 0], [10, 10], [0, 1], [10, 11], [1, 0], [11, 10], [1, 1], [11, 11]]
    gs = GridSearch.new(KMeans.new(2, 7, 50), { k: [1, 2] }, 2)
    gs.fit(x)
    expect(gs.best_estimator.max_iter).to eq(50)
    expect(gs.best_estimator.seed).to eq(7)

describe "GridSearch determinism" ->
  # Same seed, same grid, twice -> identical params, scores AND ranks.
  it "reproduces identical results for the same seed" ->
    x = [0, 1, 2, 3, 10, 11, 12, 13]
    y = [0, 0, 0, 0, 1, 1, 1, 1]
    first = ""
    a = GridSearch.new(KNNClassifier.new, { k: [1, 3, 5] }, 4, 42)
    a.fit(x, y)
    a.results.each -> (e)
      first += e[:params][:k].to_s + ":" + e[:score].to_s + ":" + e[:rank].to_s + " "
    second = ""
    b = GridSearch.new(KNNClassifier.new, { k: [1, 3, 5] }, 4, 42)
    b.fit(x, y)
    b.results.each -> (e)
      second += e[:params][:k].to_s + ":" + e[:score].to_s + ":" + e[:rank].to_s + " "
    expect(first).to eq(second)
    # ... and it is this exact string on BOTH engines
    expect(first).to eq("1:1:1 3:1:2 5:0.5:3 ")
    expect(a.best_params[:k]).to eq(b.best_params[:k])
    expect(a.best_score.to_s).to eq(b.best_score.to_s)

  it "reports size and candidates before fit" ->
    gs = GridSearch.new(KNNClassifier.new, { k: [1, 3, 5] }, 4)
    expect(gs.size).to eq(3)
    expect(gs.candidates.size).to eq(3)
    expect(gs.candidates[0][:k]).to eq(1)
    expect(gs.fitted?).to be_false
    expect(gs.results).to be_nil
    expect(gs.best_params).to be_nil
    expect(gs.best_score).to be_nil
    expect(gs.best_estimator).to be_nil

describe "GridSearch degenerate input" ->
  # A typo'd param would otherwise be swallowed by with_params and report
  # a "winner" that never varied — so the grid's keys are checked against
  # the estimator's own params.
  it "returns nil for a param the estimator does not have" ->
    x = [0, 1, 2, 3, 10, 11, 12, 13]
    y = [0, 0, 0, 0, 1, 1, 1, 1]
    gs = GridSearch.new(KNNClassifier.new, { bogus: [1, 2] }, 4)
    expect(gs.fit(x, y)).to be_nil
    expect(gs.fitted?).to be_false
    expect(gs.best_params).to be_nil
    expect(gs.results).to be_nil
    # one good key alongside one bad one is still rejected
    mixed = GridSearch.new(KNNClassifier.new, { k: [1], bogus: [2] }, 4)
    expect(mixed.fit(x, y)).to be_nil

  it "returns nil for an empty grid" ->
    x = [0, 1, 2, 3, 10, 11, 12, 13]
    y = [0, 0, 0, 0, 1, 1, 1, 1]
    gs = GridSearch.new(KNNClassifier.new, {}, 4)
    expect(gs.size).to eq(0)
    expect(gs.candidates).to be_nil
    expect(gs.fit(x, y)).to be_nil
    expect(gs.fitted?).to be_false
    nilg = GridSearch.new(KNNClassifier.new, nil, 4)
    expect(nilg.fit(x, y)).to be_nil
    expect(nilg.size).to eq(0)

  it "returns nil for misaligned x / y and for k out of range" ->
    x = [0, 1, 2, 3, 10, 11, 12, 13]
    y = [0, 0, 0, 0, 1, 1, 1, 1]
    mis = GridSearch.new(KNNClassifier.new, { k: [1] }, 4)
    expect(mis.fit(x, [0, 1])).to be_nil
    expect(mis.fitted?).to be_false
    big = GridSearch.new(KNNClassifier.new, { k: [1] }, 99)
    expect(big.fit(x, y)).to be_nil
    one = GridSearch.new(KNNClassifier.new, { k: [1] }, 1)
    expect(one.fit(x, y)).to be_nil
    empty = GridSearch.new(KNNClassifier.new, { k: [1] }, 4)
    expect(empty.fit([], [])).to be_nil

spec_summary
