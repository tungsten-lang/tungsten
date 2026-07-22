# Lasso / ElasticNet specs — L1 and L1+L2 regularized linear regression by
# coordinate descent, on the tungsten-spec framework.
#
# Run from the repo root (both engines, exit 0 = green):
#   bin/tungsten bits/tungsten-koala/spec/regularized_linear_spec.w
#   bin/tungsten -o /tmp/rl bits/tungsten-koala/spec/regularized_linear_spec.w && /tmp/rl
#
# --- SOURCE OF TRUTH ---
#
# Every reference number below is scikit-learn 1.9.0 output, produced with
# `Lasso(alpha=a, max_iter=100000, tol=1e-12)` and
# `ElasticNet(alpha=a, l1_ratio=l, ...)` on the same integer datasets, and
# printed with "%.15g". koala uses scikit-learn's objective term for term
# — including the 1/(2*n_samples) on the data-fit half — so the values are
# directly comparable with NO reparameterization anywhere in this file.
# The one place the parameterizations differ is against RIDGE, and that
# difference is scikit-learn's own: `Ridge` does not scale its data term,
# so `ElasticNet(a, l1_ratio=0)` equals `Ridge(n*a)` in sklearn exactly as
# `ElasticNet.new(a, 0)` equals `LinearRegression.new(n*a)` here. Both
# equalities are asserted below.
#
# --- HOW FLOATS ARE COMPARED ---
#
# Never via to_s: `Float#to_s` prints six significant digits on both
# engines and does not round-trip. Reference values are built by INTEGER
# DIVISION (`dec(1961904761905, 1000000000000)`), which carries 13
# significant digits and needs no float literal — a float literal anywhere
# in a program corrupts later method-call arguments on both engines, and
# the interpreter's integers are 48-bit, so no numerator here exceeds
# 1e13. Comparisons are by `max_error(...) < near` with near = 1e-9,
# roughly three decades looser than the 1e-12/1e-13 the fits actually
# achieve and four tighter than the references' own precision.
#
# EXCEPT for the sparsity claims, which are not tolerance comparisons at
# all: an L1 coefficient that has been thresholded out is asserted
# `== 0.to_f`, EXACTLY. That is the whole point of the L1 penalty and the
# one thing ridge cannot do, so it is tested as an exact identity.
#
# Weighted-vs-duplicated equality is also exact (`==` element by element),
# because the two fits are the same computation on the same numbers.
use spec
use koala

# --- helpers ---

# num/den as a float, built without a float literal. Keep num <= 1e13:
# the interpreter's integers are 48-bit.
-> dec(num, den)
  num.to_f / den.to_f

# The comparison tolerance, 1e-9.
-> near
  1.to_f / 1000000000.to_f

# The fit tolerance the reference runs used, 1e-12.
-> tight
  1.to_f / 1000000000000.to_f

# The sweep cap the reference runs used.
-> sweeps
  100000

# Largest absolute difference between two numeric arrays.
-> max_error(got, want)
  worst = 0.to_f
  n = got.size
  i = 0
  while i < n
    d = LinAlg.fabs(got[i].to_f - want[i].to_f)
    worst = d if d > worst
    i += 1
  worst

# A fitted model as one array — its coefficients, then its intercept —
# which is the shape max_error compares.
-> fit_vector(model)
  out = []
  model.coefficients.each -> (c)
    out.push(c)
  out.push(model.intercept)
  out

# Element-for-element EXACT equality of two float arrays (compiled
# Array == is identity, and to_s loses digits).
-> same_floats?(a, b)
  ok = a != nil && b != nil
  ok = a.size == b.size if ok
  if ok
    n = a.size
    i = 0
    while i < n
      ok = false if a[i] != b[i]
      i += 1
  ok

# DS1 — six samples, two correlated features, a target that is NOT an
# exact linear function of them (so OLS has residuals and every
# coefficient is genuinely estimated). cond of the design is 13.4:
# well-conditioned, so "alpha = 0 reproduces OLS" is a statement about
# the plumbing and not about conditioning.
-> ds1_x
  out = [[1, 2], [2, 1], [3, 4], [4, 3], [5, 7], [6, 5]]
  out

-> ds1_y
  out = [5, 4, 11, 9, 18, 14]
  out

# DS2 — eight samples where feature 0 carries the signal (y is very
# nearly 2*x0 + 1) and feature 1 is an unrelated scatter over 1..9 that
# carries almost none. OLS gives feature 1 a small but nonzero slope
# (0.00901287553648069); lasso deletes it.
-> ds2_x
  out = [[1, 5], [2, 3], [3, 8], [4, 1], [5, 9], [6, 2], [7, 6], [8, 4]]
  out

-> ds2_y
  out = [3, 5, 8, 9, 11, 14, 15, 17]
  out

describe "Lasso" ->
  # y = 2x + 1 exactly on one feature, so every number here is a short
  # decimal scikit-learn reproduces exactly: alpha = 0 gives (2, 1),
  # alpha = 0.5 gives (1.9, 1.5), alpha = 2 gives (1.6, 3).
  it "fits, predicts and scores a single-feature target" ->
    x = [[2], [4], [6], [8]]
    y = [5, 9, 13, 17]
    m = Lasso.new(0, sweeps, tight)
    expect(m.fit(x, y) != nil).to be_true
    expect(m.fitted?).to be_true
    want = []
    want.push(2)
    want.push(1)
    expect(max_error(fit_vector(m), want) < near).to be_true
    preds = m.predict([[10], [12]])
    got = []
    got.push(21)
    got.push(25)
    expect(max_error(preds, got) < near).to be_true
    expect(LinAlg.fabs(m.score(x, y) - 1.to_f) < near).to be_true

    half = Lasso.new(1.to_f / 2.to_f, sweeps, tight)
    half.fit(x, y)
    want = []
    want.push(dec(19, 10))
    want.push(dec(3, 2))
    expect(max_error(fit_vector(half), want) < near).to be_true

    two = Lasso.new(2, sweeps, tight)
    two.fit(x, y)
    want = []
    want.push(dec(16, 10))
    want.push(3)
    expect(max_error(fit_vector(two), want) < near).to be_true

  # THE PLUMBING PIN. alpha = 0 removes the penalty entirely, so
  # coordinate descent must land on the ordinary least squares solution —
  # the one LinearRegression computes by Householder QR through a
  # completely different route (a design matrix with an intercept column,
  # no centering, no iteration). Agreement to 1e-9 says the centering,
  # the intercept recovery and the residual bookkeeping are all right.
  #
  # The residual disagreement is 3.4e-12, which is also what scikit-learn's
  # own Lasso(alpha=0) differs from its LinearRegression by
  # (0.487964989062446 vs 0.487964989059082) — the cost of iterating to a
  # closed-form answer, not a koala defect.
  it "reproduces OLS at alpha = 0" ->
    x = ds1_x
    y = ds1_y
    ols = LinearRegression.new
    expect(ols.fit(x, y) != nil).to be_true
    m = Lasso.new(0, sweeps, tight)
    expect(m.fit(x, y) != nil).to be_true
    expect(max_error(fit_vector(m), fit_vector(ols)) < near).to be_true

    # ... and against scikit-learn's LinearRegression, independently
    want = []
    want.push(dec(4879649890591, 10000000000000))
    want.push(dec(2122538293217, 1000000000000))
    want.push(dec(6761487964989, 10000000000000))
    expect(max_error(fit_vector(m), want) < near).to be_true

  # scikit-learn 1.9.0, Lasso(alpha=a, max_iter=100000, tol=1e-12):
  #   DS1 a=0.1  -> 0.459080962804231, 2.11663019693424, b 0.798905908092971
  #   DS1 a=0.5  -> 0.343544857771371, 2.09299781181392, b 1.28993435448251
  #   DS1 a=1    -> 0.199124726480295, 2.06345733041351, b 1.90371991246942
  it "matches scikit-learn's coefficients" ->
    x = ds1_x
    y = ds1_y
    m = Lasso.new(1.to_f / 10.to_f, sweeps, tight)
    m.fit(x, y)
    want = []
    want.push(dec(4590809628042, 10000000000000))
    want.push(dec(2116630196934, 1000000000000))
    want.push(dec(7989059080930, 10000000000000))
    expect(max_error(fit_vector(m), want) < near).to be_true

    m = Lasso.new(1.to_f / 2.to_f, sweeps, tight)
    m.fit(x, y)
    want = []
    want.push(dec(3435448577714, 10000000000000))
    want.push(dec(2092997811814, 1000000000000))
    want.push(dec(1289934354483, 1000000000000))
    expect(max_error(fit_vector(m), want) < near).to be_true

    m = Lasso.new(1, sweeps, tight)
    m.fit(x, y)
    want = []
    want.push(dec(1991247264803, 10000000000000))
    want.push(dec(2063457330414, 1000000000000))
    want.push(dec(1903719912469, 1000000000000))
    expect(max_error(fit_vector(m), want) < near).to be_true

  # THE SPARSITY PROOF, and the reason this file exists beside
  # linear_regression.w. DS2's feature 1 is nearly uninformative: OLS
  # gives it 0.00901287553648069 and a small alpha only shrinks that
  # (sklearn Lasso a=0.05 -> 0.00163090128755364). Push alpha to 0.2 and
  # it is not small — it is GONE, exactly zero, while the informative
  # feature 0 survives at 1.96190476190476 (sklearn's value).
  #
  # RIDGE AT THE SAME EFFECTIVE STRENGTH CANNOT DO THIS. koala's ridge
  # alpha for the same penalty weight is n*a = 8*0.2 = 1.6, and
  # LinearRegression.new(1.6) returns 0.00747420194811457 for the same
  # feature — smaller than OLS, still there, and still there for every
  # alpha short of infinity. Shrinkage is not selection.
  it "drives an uninformative feature to EXACTLY zero, where ridge cannot" ->
    x = ds2_x
    y = ds2_y
    m = Lasso.new(1.to_f / 5.to_f, sweeps, tight)
    expect(m.fit(x, y) != nil).to be_true
    expect(m.coefficients[1] == 0.to_f).to be_true       # EXACT, not "small"
    want = []
    want.push(dec(1961904761905, 1000000000000))
    want.push(0)
    want.push(dec(1421428571429, 1000000000000))
    expect(max_error(fit_vector(m), want) < near).to be_true
    expect(m.coefficients[0] > 1.to_f).to be_true        # the signal survives

    # the same feature under ridge at the equivalent strength: nonzero
    r = LinearRegression.new(8.to_f / 5.to_f)
    expect(r.fit(x, y) != nil).to be_true
    expect(r.coefficients[1] == 0.to_f).to be_false
    expect(r.coefficients[1] > 0.to_f).to be_true
    ridge_want = []
    ridge_want.push(dec(1926776931237, 1000000000000))
    ridge_want.push(dec(7474201948115, 1000000000000) / 1000.to_f)
    ridge_want.push(dec(1544001350178, 1000000000000))
    expect(max_error(fit_vector(r), ridge_want) < near).to be_true

    # a SMALL alpha only shrinks it — sparsity is a threshold effect
    small = Lasso.new(1.to_f / 20.to_f, sweeps, tight)
    small.fit(x, y)
    expect(small.coefficients[1] == 0.to_f).to be_false
    want = []
    want.push(dec(1990515021459, 1000000000000))
    want.push(dec(1630901287554, 1000000000000) / 1000.to_f)
    want.push(dec(1284935622318, 1000000000000))
    expect(max_error(fit_vector(small), want) < near).to be_true

  # Past a finite alpha EVERY coefficient is thresholded out and the model
  # is the (weighted) mean of y — the intercept, which the penalty never
  # touches. sklearn Lasso(alpha=50) on DS2: coef [0, 0], intercept 10.25,
  # and 10.25 is exactly mean(y2) = 82/8.
  it "collapses to the intercept once alpha is large enough" ->
    x = ds2_x
    y = ds2_y
    m = Lasso.new(50, sweeps, tight)
    expect(m.fit(x, y) != nil).to be_true
    expect(m.coefficients[0] == 0.to_f).to be_true
    expect(m.coefficients[1] == 0.to_f).to be_true
    expect(m.intercept == dec(41, 4)).to be_true         # exactly mean(y)
    preds = m.predict([[1, 5], [8, 4]])
    expect(preds[0] == dec(41, 4)).to be_true
    expect(preds[1] == dec(41, 4)).to be_true

  # p > n: three samples, five features. OLS has no unique answer and
  # LinearRegression correctly refuses; the L1 penalty makes the problem
  # well posed and lasso answers with a SPARSE fit — one surviving
  # feature out of five. sklearn Lasso(alpha=0.5):
  #   [0, 0.173076923076923, -0, -0, -0], intercept 1.53846153846154
  it "fits more features than samples, which OLS must refuse" ->
    x = [[1, 2, 3, 4, 5], [2, 1, 4, 3, 6], [3, 5, 1, 2, 4]]
    y = [1, 2, 3]
    expect(LinearRegression.new.fit(x, y)).to be_nil
    m = Lasso.new(1.to_f / 2.to_f, sweeps, tight)
    expect(m.fit(x, y) != nil).to be_true
    zeros = 0
    m.coefficients.each -> (c)
      zeros += 1 if c == 0.to_f
    expect(zeros).to eq(4)
    want = []
    want.push(0)
    want.push(dec(1730769230769, 1000000000000) / 10.to_f)
    want.push(0)
    want.push(0)
    want.push(0)
    want.push(dec(1538461538462, 1000000000000))
    expect(max_error(fit_vector(m), want) < near).to be_true

  it "answers the Estimable / SupervisedEstimator contract" ->
    missing = []
    models = [Lasso.new, ElasticNet.new]
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
      missing.push(m.estimator_name + ".persist_name") if !m.respond_to?("persist_name")
      missing.push(m.estimator_name + ".to_state") if !m.respond_to?("to_state")
      missing.push(m.estimator_name + ".restore_state") if !m.respond_to?("restore_state")
    expect(missing.join(",")).to eq("")
    expect(Lasso.new.estimator_name).to eq("Lasso")
    expect(Lasso.new.supervised?).to be_true
    expect(Lasso.new.supports_sample_weight?).to be_true
    expect(Lasso.new.fitted?).to be_false
    expect(Lasso.new.l1_ratio).to eq(1)

  # params is the knobs alone — never the learned coefficients — and
  # with_params CLONES rather than mutating. Compared PER KEY: hash to_s
  # key order differs between the engines.
  it "reports only hyperparameters, and clones through with_params" ->
    m = Lasso.new(7, 250, tight)
    expect(m.params[:alpha]).to eq(7)
    expect(m.params[:max_iter]).to eq(250)
    expect(m.params[:tol] == tight).to be_true
    expect(m.params.size).to eq(3)
    expect(m.params.key?(:coefficients)).to be_false

    m.fit(ds1_x, ds1_y)
    clone = m.with_params({ alpha: 2 })
    expect(clone.params[:alpha]).to eq(2)
    expect(clone.params[:max_iter]).to eq(250)           # unmentioned carries over
    expect(clone.fitted?).to be_false                    # a clone is UNFITTED
    expect(m.params[:alpha]).to eq(7)                    # self is untouched
    expect(m.fitted?).to be_true

    # with_params(params) round-trips
    again = m.with_params(m.params)
    expect(again.params[:alpha]).to eq(7)
    expect(again.params[:max_iter]).to eq(250)
    expect(again.params[:tol] == tight).to be_true

    # sklearn's defaults: alpha 1, 1000 sweeps, tol 1e-4
    d = Lasso.new
    expect(d.params[:alpha]).to eq(1)
    expect(d.params[:max_iter]).to eq(1000)
    expect(d.params[:tol] == dec(1, 10000)).to be_true

  # The bit's shape-error convention: nil, never a raise — extended to
  # the hyperparameters, which can be as unusable as the data.
  it "returns nil for unusable shapes and unusable knobs" ->
    x = ds1_x
    y = ds1_y
    expect(Lasso.new.fit([], [])).to be_nil
    expect(Lasso.new.fit(x, [1, 2])).to be_nil                    # misaligned
    expect(Lasso.new.fit([[1, 2], [3]], [1, 2])).to be_nil        # ragged
    expect(Lasso.new(0 - 1).fit(x, y)).to be_nil                  # negative alpha
    expect(Lasso.new(1, 0).fit(x, y)).to be_nil                   # no sweeps
    expect(Lasso.new(1, 1000, 0 - tight).fit(x, y)).to be_nil     # negative tol

    # A nil ARGUMENT selects the constructor default on both engines, so
    # a hyperparameter can never actually arrive nil through `new` or
    # `with_params`. The solver still guards it, because fit_state is
    # callable directly.
    expect(Lasso.new(nil).params[:alpha]).to eq(1)
    expect(ElasticNetSolver.usable_params?(nil, 1, 1000, tight)).to be_false
    expect(ElasticNetSolver.fit_state(x, y, nil, nil, 1, 1000, tight)).to be_nil
    expect(ElasticNetSolver.fit_state(x, y, nil, 1, nil, 1000, tight)).to be_nil

    # a rejected fit leaves the model unfitted, and unfitted is nil-safe
    m = Lasso.new(0 - 1)
    m.fit(x, y)
    expect(m.fitted?).to be_false
    expect(m.coefficients).to be_nil
    expect(m.n_iter).to be_nil
    expect(m.predict(x)).to be_nil
    expect(m.score(x, y)).to be_nil

    # a fitted model still refuses a query of the wrong width
    good = Lasso.new(1, sweeps, tight)
    good.fit(x, y)
    expect(good.predict([[1, 2, 3]])).to be_nil
    expect(good.score([[1, 2, 3]], [1])).to be_nil
    expect(good.n_iter > 0).to be_true

  # THE DEFINITION OF CORRECTNESS for weights (lib/estimator_base.w): an
  # integer weight vector is indistinguishable from duplicating each row
  # that many times. Here that is EXACT — the same arithmetic on the same
  # numbers — because the 1/(2W) normalization uses the total WEIGHT, not
  # the row count. sklearn agrees value for value (its Lasso rescales
  # sample_weight to sum to n_samples, which is the same normalization).
  it "weights a row exactly like duplicating it" ->
    x = ds1_x
    y = ds1_y
    w = Lasso.new(1.to_f / 2.to_f, sweeps, tight)
    expect(w.fit(x, y, [2, 1, 1, 1, 1, 1]) != nil).to be_true
    dup = Lasso.new(1.to_f / 2.to_f, sweeps, tight)
    dup.fit([[1, 2], [1, 2], [2, 1], [3, 4], [4, 3], [5, 7], [6, 5]], [5, 5, 4, 11, 9, 18, 14])
    expect(same_floats?(w.coefficients, dup.coefficients)).to be_true
    expect(w.intercept == dup.intercept).to be_true

    # ... and it is scikit-learn's weighted answer
    want = []
    want.push(dec(4371946964444, 10000000000000))
    want.push(dec(2047801814373, 1000000000000))
    want.push(dec(1033496161896, 1000000000000))
    expect(max_error(fit_vector(w), want) < near).to be_true

    # all ones is a NO-OP, bit for bit
    plain = Lasso.new(1.to_f / 2.to_f, sweeps, tight)
    plain.fit(x, y)
    ones = Lasso.new(1.to_f / 2.to_f, sweeps, tight)
    ones.fit(x, y, [1, 1, 1, 1, 1, 1])
    expect(same_floats?(plain.coefficients, ones.coefficients)).to be_true
    expect(plain.intercept == ones.intercept).to be_true

    # a ZERO weight drops the row entirely
    dropped = Lasso.new(1.to_f / 2.to_f, sweeps, tight)
    dropped.fit(x, y, [0, 1, 1, 1, 1, 1])
    without = Lasso.new(1.to_f / 2.to_f, sweeps, tight)
    without.fit([[2, 1], [3, 4], [4, 3], [5, 7], [6, 5]], [4, 11, 9, 18, 14])
    expect(same_floats?(dropped.coefficients, without.coefficients)).to be_true
    expect(dropped.intercept == without.intercept).to be_true

    # an unusable weight vector is a nil fit, not a silent unweighted one
    expect(Lasso.new.fit(x, y, [1, 1])).to be_nil
    expect(Lasso.new.fit(x, y, [0, 0, 0, 0, 0, 0])).to be_nil
    expect(Lasso.new.fit(x, y, [1, 1, 1, 1, 1, 0 - 1])).to be_nil

    # weighted score is the weighted R²
    s = w.score(x, y, [2, 1, 1, 1, 1, 1])
    expect(s != nil).to be_true
    expect(s == dup.score([[1, 2], [1, 2], [2, 1], [3, 4], [4, 3], [5, 7], [6, 5]], [5, 5, 4, 11, 9, 18, 14])).to be_true
    expect(Lasso.new(1, sweeps, tight).fit(x, y).score(x, y, [1, 1])).to be_nil

  # No seed, no random coordinate order, no line search: two fits of the
  # same model on the same data are bit-identical, and the accepted shapes
  # all reach the same numbers.
  it "is deterministic, and takes every accepted input shape" ->
    x = ds1_x
    y = ds1_y
    a = Lasso.new(1.to_f / 2.to_f, sweeps, tight)
    a.fit(x, y)
    b = Lasso.new(1.to_f / 2.to_f, sweeps, tight)
    b.fit(x, y)
    expect(same_floats?(a.coefficients, b.coefficients)).to be_true
    expect(a.intercept == b.intercept).to be_true
    expect(a.n_iter).to eq(b.n_iter)

    # refitting the SAME instance lands in the same place
    a.fit(x, y)
    expect(same_floats?(a.coefficients, b.coefficients)).to be_true

    # Matrix, DataFrame and Series inputs coerce to the identical fit
    viam = Lasso.new(1.to_f / 2.to_f, sweeps, tight)
    viam.fit(Matrix.new(x), Vector.new(y))
    expect(same_floats?(viam.coefficients, b.coefficients)).to be_true
    expect(viam.intercept == b.intercept).to be_true

    df = DataFrame.new([[:a, [1, 2, 3, 4, 5, 6]], [:b, [2, 1, 4, 3, 7, 5]]])
    viadf = Lasso.new(1.to_f / 2.to_f, sweeps, tight)
    viadf.fit(df, Series.new(y, "y"))
    expect(same_floats?(viadf.coefficients, b.coefficients)).to be_true
    expect(viadf.intercept == b.intercept).to be_true
    expect(max_error(viadf.predict(df), b.predict(x)) == 0.to_f).to be_true

describe "ElasticNet" ->
  # Lasso IS ElasticNet at l1_ratio = 1 — the same solver, called with the
  # same numbers — so the two must agree BIT FOR BIT, not to a tolerance.
  it "is Lasso at l1_ratio = 1" ->
    x = ds1_x
    y = ds1_y
    l = Lasso.new(1.to_f / 2.to_f, sweeps, tight)
    l.fit(x, y)
    e = ElasticNet.new(1.to_f / 2.to_f, 1, sweeps, tight)
    e.fit(x, y)
    expect(same_floats?(l.coefficients, e.coefficients)).to be_true
    expect(l.intercept == e.intercept).to be_true
    expect(l.n_iter).to eq(e.n_iter)

    # ... including the sparsity, on DS2
    l2 = Lasso.new(1.to_f / 5.to_f, sweeps, tight)
    l2.fit(ds2_x, ds2_y)
    e2 = ElasticNet.new(1.to_f / 5.to_f, 1, sweeps, tight)
    e2.fit(ds2_x, ds2_y)
    expect(same_floats?(l2.coefficients, e2.coefficients)).to be_true
    expect(e2.coefficients[1] == 0.to_f).to be_true

  # THE RIDGE END OF THE FAMILY. l1_ratio = 0 leaves a pure L2 penalty, so
  # the fit must be the ridge one linear_regression.w computes in closed
  # form — at the alpha the two parameterizations agree on.
  #
  # PARAMETERIZATION, explicitly. koala's ElasticNet objective (sklearn's)
  # scales the data term by 1/(2*n); koala's Ridge (sklearn's Ridge) does
  # not scale it at all. Multiplying through by 2n:
  #
  #     ElasticNet.new(a, 0)  ==  LinearRegression.new(n * a)
  #
  # so on DS1 (n = 6) alpha 0.1 here is ridge alpha 0.6 there, and alpha
  # 0.5 here is ridge alpha 3. This is scikit-learn's own relationship
  # between ElasticNet and Ridge, verified against both:
  #   sklearn ElasticNet(0.1, l1_ratio=0) -> 0.563414725911454, 2.01888709131268, b 0.792129124496762
  #   sklearn Ridge(0.6)                  -> 0.563414725911434, 2.01888709131269, b 0.792129124496784
  it "is ridge at l1_ratio = 0, at alpha scaled by the sample count" ->
    x = ds1_x
    y = ds1_y
    e = ElasticNet.new(1.to_f / 10.to_f, 0, sweeps, tight)
    expect(e.fit(x, y) != nil).to be_true
    r = LinearRegression.new(6.to_f / 10.to_f)
    r.fit(x, y)
    expect(max_error(fit_vector(e), fit_vector(r)) < near).to be_true

    want = []
    want.push(dec(5634147259114, 10000000000000))
    want.push(dec(2018887091313, 1000000000000))
    want.push(dec(7921291244968, 10000000000000))
    expect(max_error(fit_vector(e), want) < near).to be_true
    expect(max_error(fit_vector(r), want) < near).to be_true

    # a second alpha, so the n-scaling is pinned and not a coincidence
    e = ElasticNet.new(1.to_f / 2.to_f, 0, sweeps, tight)
    e.fit(x, y)
    r = LinearRegression.new(3)
    r.fit(x, y)
    expect(max_error(fit_vector(e), fit_vector(r)) < near).to be_true
    want = []
    want.push(dec(7110980622431, 10000000000000))
    want.push(dec(1745155607751, 1000000000000))
    want.push(dec(1278919553729, 1000000000000))
    expect(max_error(fit_vector(e), want) < near).to be_true

    # and a pure L2 penalty NEVER zeroes a coefficient, whatever alpha
    big = ElasticNet.new(500, 0, sweeps, tight)
    big.fit(ds2_x, ds2_y)
    expect(big.coefficients[0] == 0.to_f).to be_false
    expect(big.coefficients[1] == 0.to_f).to be_false

  # scikit-learn 1.9.0, ElasticNet(alpha=a, l1_ratio=l, max_iter=100000,
  # tol=1e-12):
  #   DS1 a=0.1 l=0.5  -> 0.514918424357829, 2.06465325290302, b 0.794056920769853
  #   DS1 a=0.5 l=0.5  -> 0.578378378380152, 1.87567567567453, b 1.26486486486285
  #   DS1 a=1   l=0.25 -> 0.695509822264684, 1.60617399438677, b 1.84307764265546
  #   DS2 a=0.5 l=0.7  -> 1.87962962962963, 0,                b 1.79166666666667
  it "matches scikit-learn's mixed-penalty coefficients" ->
    x = ds1_x
    y = ds1_y
    m = ElasticNet.new(1.to_f / 10.to_f, 1.to_f / 2.to_f, sweeps, tight)
    m.fit(x, y)
    want = []
    want.push(dec(5149184243578, 10000000000000))
    want.push(dec(2064653252903, 1000000000000))
    want.push(dec(7940569207699, 10000000000000))
    expect(max_error(fit_vector(m), want) < near).to be_true

    m = ElasticNet.new(1.to_f / 2.to_f, 1.to_f / 2.to_f, sweeps, tight)
    m.fit(x, y)
    want = []
    want.push(dec(5783783783802, 10000000000000))
    want.push(dec(1875675675675, 1000000000000))
    want.push(dec(1264864864863, 1000000000000))
    expect(max_error(fit_vector(m), want) < near).to be_true

    m = ElasticNet.new(1, 1.to_f / 4.to_f, sweeps, tight)
    m.fit(x, y)
    want = []
    want.push(dec(6955098222647, 10000000000000))
    want.push(dec(1606173994387, 1000000000000))
    want.push(dec(1843077642655, 1000000000000))
    expect(max_error(fit_vector(m), want) < near).to be_true

    # a mixed penalty still SELECTS: the L1 share alone does the zeroing
    m = ElasticNet.new(1.to_f / 2.to_f, 7.to_f / 10.to_f, sweeps, tight)
    m.fit(ds2_x, ds2_y)
    expect(m.coefficients[1] == 0.to_f).to be_true
    want = []
    want.push(dec(1879629629630, 1000000000000))
    want.push(0)
    want.push(dec(1791666666667, 1000000000000))
    expect(max_error(fit_vector(m), want) < near).to be_true

  it "reproduces OLS at alpha = 0 whatever the mixture" ->
    x = ds1_x
    y = ds1_y
    ols = LinearRegression.new
    ols.fit(x, y)
    mixes = [0, 1, 1.to_f / 3.to_f, 1.to_f / 2.to_f, 1]
    worst = 0.to_f
    mixes.each -> (mix)
      m = ElasticNet.new(0, mix, sweeps, tight)
      m.fit(x, y)
      d = max_error(fit_vector(m), fit_vector(ols))
      worst = d if d > worst
    expect(worst < near).to be_true

  it "reports both knobs, and tunes them through with_params" ->
    m = ElasticNet.new(3, 1.to_f / 4.to_f, 250, tight)
    expect(m.estimator_name).to eq("ElasticNet")
    expect(m.params[:alpha]).to eq(3)
    expect(m.params[:l1_ratio] == dec(1, 4)).to be_true
    expect(m.params[:max_iter]).to eq(250)
    expect(m.params.size).to eq(4)

    clone = m.with_params({ l1_ratio: 1 })
    expect(clone.params[:l1_ratio]).to eq(1)
    expect(clone.params[:alpha]).to eq(3)                # unmentioned carries over
    expect(m.params[:l1_ratio] == dec(1, 4)).to be_true  # self untouched

    again = m.with_params(m.params)
    expect(again.params[:alpha]).to eq(3)
    expect(again.params[:l1_ratio] == dec(1, 4)).to be_true
    expect(again.params[:max_iter]).to eq(250)

    # sklearn's defaults: alpha 1, l1_ratio 0.5, 1000 sweeps, tol 1e-4
    d = ElasticNet.new
    expect(d.params[:alpha]).to eq(1)
    expect(d.params[:l1_ratio] == dec(1, 2)).to be_true
    expect(d.params[:max_iter]).to eq(1000)
    expect(d.params[:tol] == dec(1, 10000)).to be_true

  it "returns nil for an l1_ratio outside 0..1 and the shared shape errors" ->
    x = ds1_x
    y = ds1_y
    expect(ElasticNet.new(1, 2).fit(x, y)).to be_nil
    expect(ElasticNet.new(1, 0 - 1).fit(x, y)).to be_nil
    expect(ElasticNet.new(0 - 1, 1.to_f / 2.to_f).fit(x, y)).to be_nil
    # a nil l1_ratio is "use the default", not an error (see Lasso above)
    expect(ElasticNet.new(1, nil).params[:l1_ratio] == dec(1, 2)).to be_true
    expect(ElasticNetSolver.fit_state(x, y, nil, 1, 2, 1000, tight)).to be_nil
    expect(ElasticNet.new(1, 1.to_f / 2.to_f).fit([], [])).to be_nil
    expect(ElasticNet.new(1, 1.to_f / 2.to_f).fit(x, [1, 2])).to be_nil
    m = ElasticNet.new(1, 2)
    m.fit(x, y)
    expect(m.fitted?).to be_false
    expect(m.predict(x)).to be_nil
    expect(m.score(x, y)).to be_nil
    # the endpoints THEMSELVES are legal — 0 and 1 are ridge and lasso
    expect(ElasticNet.new(1, 0).fit(x, y) != nil).to be_true
    expect(ElasticNet.new(1, 1).fit(x, y) != nil).to be_true

  it "weights a row exactly like duplicating it" ->
    x = ds1_x
    y = ds1_y
    w = ElasticNet.new(1.to_f / 2.to_f, 1.to_f / 2.to_f, sweeps, tight)
    w.fit(x, y, [2, 1, 1, 1, 1, 1])
    dup = ElasticNet.new(1.to_f / 2.to_f, 1.to_f / 2.to_f, sweeps, tight)
    dup.fit([[1, 2], [1, 2], [2, 1], [3, 4], [4, 3], [5, 7], [6, 5]], [5, 5, 4, 11, 9, 18, 14])
    expect(same_floats?(w.coefficients, dup.coefficients)).to be_true
    expect(w.intercept == dup.intercept).to be_true

    # sklearn ElasticNet(0.5, 0.5, sample_weight=[2,1,1,1,1,1])
    want = []
    want.push(dec(6521606538401, 10000000000000))
    want.push(dec(1827849104936, 1000000000000))
    want.push(dec(1112012442437, 1000000000000))
    expect(max_error(fit_vector(w), want) < near).to be_true

describe "Lasso / ElasticNet persistence" ->
  # A saved model must predict IDENTICALLY to the one that was saved —
  # element for element, exactly, not to a tolerance. The koala format
  # encodes an f64 as its own bits for precisely this reason, so the
  # round-trip below goes through the REAL payload (Persist.dumps text,
  # Persist's decoder) rather than handing the state hash across in
  # memory.
  #
  it "saves and reloads a fitted Lasso exactly" ->
    x = ds2_x
    y = ds2_y
    m = Lasso.new(1.to_f / 5.to_f, sweeps, tight)
    m.fit(x, y)
    expect(m.persist_name).to eq("Lasso")

    text = Persist.dumps(m)
    expect(text != nil).to be_true
    lines = Persist.payload_lines(text)
    expect(lines[0]).to eq(Persist.header)
    expect(lines[1]).to eq("o Lasso")

    back = Persist.loads(text)
    expect(back != nil).to be_true
    expect(back.fitted?).to be_true
    expect(back.params[:alpha] == m.params[:alpha]).to be_true
    expect(back.n_iter).to eq(m.n_iter)
    expect(same_floats?(back.coefficients, m.coefficients)).to be_true
    expect(back.intercept == m.intercept).to be_true
    expect(same_floats?(back.predict(x), m.predict(x))).to be_true
    expect(back.coefficients[1] == 0.to_f).to be_true     # the zero survives

    # an UNFITTED model has nothing to save
    expect(Persist.dumps(Lasso.new)).to be_nil

  it "saves and reloads a fitted ElasticNet exactly" ->
    x = ds1_x
    y = ds1_y
    m = ElasticNet.new(1.to_f / 2.to_f, 1.to_f / 4.to_f, sweeps, tight)
    m.fit(x, y)
    expect(m.persist_name).to eq("ElasticNet")

    text = Persist.dumps(m)
    expect(text != nil).to be_true
    lines = Persist.payload_lines(text)
    expect(lines[1]).to eq("o ElasticNet")
    back = Persist.loads(text)
    expect(back != nil).to be_true
    expect(back.params[:l1_ratio] == m.params[:l1_ratio]).to be_true
    expect(same_floats?(back.predict(x), m.predict(x))).to be_true
    expect(Persist.dumps(ElasticNet.new)).to be_nil

  # The guard that stops a payload written by a DIFFERENT estimator from
  # loading as one of these and quietly answering predictions.
  it "refuses a state that is not its own" ->
    expect(Lasso.load_state(nil)).to be_nil
    expect(Lasso.load_state({})).to be_nil
    expect(ElasticNet.load_state(nil)).to be_nil
    expect(ElasticNet.load_state({})).to be_nil

    lr = LinearRegression.new(2)
    lr.fit(ds1_x, ds1_y)
    expect(Lasso.load_state(lr.to_state)).to be_nil      # no max_iter / tol
    expect(ElasticNet.load_state(lr.to_state)).to be_nil

    l = Lasso.new(1, sweeps, tight)
    l.fit(ds1_x, ds1_y)
    expect(ElasticNet.load_state(l.to_state)).to be_nil  # no l1_ratio

    # ... and the mirror image: Lasso's keys are a strict SUBSET of
    # ElasticNet's, so the guard is the key ElasticNet writes and Lasso
    # never does. Without it a relabelled ElasticNet body would load as a
    # Lasso reporting l1_ratio 1 over mixed-penalty coefficients.
    e = ElasticNet.new(1, 1.to_f / 4.to_f, sweeps, tight)
    e.fit(ds1_x, ds1_y)
    expect(Lasso.load_state(e.to_state)).to be_nil
    expect(ElasticNet.load_state(e.to_state) != nil).to be_true
    expect(Lasso.load_state(l.to_state) != nil).to be_true

    # a truncated state of its own is refused too
    st = l.to_state
    st[:coefficients] = nil
    expect(Lasso.load_state(st)).to be_nil

describe "Lasso / ElasticNet composition" ->
  # Nothing in Pipeline, GridSearch or CrossValidation names a concrete
  # estimator: they dispatch through the Estimable contract alone. These
  # are the proofs that the two new classes really are on it.
  it "runs as a Pipeline tail" ->
    df = DataFrame.new([[:a, [1, 2, 3, 4, 5, 6]], [:b, [2, 1, 4, 3, 7, 5]]])
    y = ds1_y
    pipe = Pipeline.new([Scaler.new(:standard), Lasso.new(1.to_f / 2.to_f, sweeps, tight)])
    expect(pipe.predict(df)).to be_nil
    expect(pipe.fit(df, y) != nil).to be_true
    expect(pipe.fitted?).to be_true
    expect(pipe[1].fitted?).to be_true
    preds = pipe.predict(df)
    expect(preds != nil).to be_true
    expect(preds.size).to eq(6)
    expect(pipe.score(df, y) != nil).to be_true
    expect(pipe.supervised?).to be_true
    expect(pipe.supports_sample_weight?).to be_true

    # the tail's knobs join the pipeline's search space, dotted
    expect(pipe.params["lasso.alpha"] == dec(1, 2)).to be_true
    tuned = pipe.with_params({ "lasso.alpha": 4 })
    expect(tuned.params["lasso.alpha"]).to eq(4)

    enet_pipe = Pipeline.new([[:scale, Scaler.new(:standard)], [:net, ElasticNet.new(1, 1.to_f / 2.to_f, sweeps, tight)]])
    expect(enet_pipe.fit(df, y) != nil).to be_true
    expect(enet_pipe.params["net.l1_ratio"] == dec(1, 2)).to be_true

  it "is searched by GridSearch over alpha" ->
    x = ds2_x
    y = ds2_y
    gs = GridSearch.new(Lasso.new(1, sweeps, tight), { alpha: [0, 1, 10] }, 4)
    expect(gs.size).to eq(3)
    expect(gs.fit(x, y) != nil).to be_true
    expect(gs.fitted?).to be_true
    expect(gs.best_params[:alpha] != nil).to be_true
    expect(gs.best_score != nil).to be_true
    expect(gs.results.size).to eq(3)
    expect(gs.results[0][:rank]).to eq(1)
    expect(gs.best_estimator.fitted?).to be_true
    expect(gs.best_estimator.estimator_name).to eq("Lasso")
    expect(gs.predict(x) != nil).to be_true

    # the sweep keeps the tightened tol/max_iter it was seeded with
    expect(gs.best_estimator.params[:max_iter]).to eq(sweeps)

  it "searches an ElasticNet's alpha and l1_ratio together" ->
    x = ds2_x
    y = ds2_y
    grid = { alpha: [0, 1], l1_ratio: [0, 1] }
    gs = GridSearch.new(ElasticNet.new(1, 1.to_f / 2.to_f, sweeps, tight), grid, 4)
    expect(gs.size).to eq(4)
    expect(gs.fit(x, y) != nil).to be_true
    expect(gs.best_params.key?(:alpha)).to be_true
    expect(gs.best_params.key?(:l1_ratio)).to be_true
    expect(gs.best_estimator.estimator_name).to eq("ElasticNet")
    seen = []
    gs.results.each -> (r)
      seen.push(r[:params][:alpha].to_s + "/" + r[:params][:l1_ratio].to_s)
    expect(seen.size).to eq(4)

  it "cross-validates, weighted and not" ->
    x = ds2_x
    y = ds2_y
    scores = CrossValidation.cross_val_score(Lasso.new(1.to_f / 5.to_f, sweeps, tight), x, y, 4)
    expect(scores != nil).to be_true
    expect(scores.size).to eq(4)
    expect(CrossValidation.cross_val_mean(Lasso.new(1.to_f / 5.to_f, sweeps, tight), x, y, 4) != nil).to be_true

    ew = CrossValidation.cross_val_score(ElasticNet.new(1, 1.to_f / 2.to_f, sweeps, tight), x, y, 4, nil, [2, 1, 1, 1, 1, 1, 1, 1])
    expect(ew != nil).to be_true
    expect(ew.size).to eq(4)
    expect(CrossValidation.cross_val_score(Lasso.new, x, [1, 2], 4)).to be_nil

spec_summary
