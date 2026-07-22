# Sample-weight specs — the `sample_weight` argument threaded through
# koala's estimator contract: weighted fits, weighted metrics, weighted
# cross-validation, and the estimator that deliberately refuses weights.
#
# Run from the repo root (both engines, exit 0 = green):
#   bin/tungsten bits/tungsten-koala/spec/sample_weight_spec.w
#   bin/tungsten -o /tmp/sw_spec bits/tungsten-koala/spec/sample_weight_spec.w && /tmp/sw_spec
#
# ============================================================
# THE HEADLINE PROPERTY: integer weights ARE duplication
# ============================================================
#
# Almost every way of getting sample weights wrong shows up as a
# disagreement between
#
#     model.fit(rows, y, [2, 1, 1])          # row 0 counts twice
#     model.fit([r0, r0, r1, r2], [y0, y0, y1, y2])
#
# — a forgotten weight in a denominator, an unweighted mean inside a
# weighted variance, a zero-weight row that still seeds a centroid or
# still claims a class prior. So the equivalence is asserted for EVERY
# estimator that accepts weights, on data chosen so the weighting
# genuinely changes the answer (a test that passes because the fit is
# exact either way proves nothing, so each case also asserts that the
# weighted model DIFFERS from the unweighted one).
#
# The two other invariants are asserted alongside it: all-1s weights
# reproduce the unweighted fit, and a 0 weight removes a row.
#
# Comparisons are through LinAlg.fabs against a data-derived tolerance
# (1e-9), because weighting and duplicating sum the same terms in a
# different ORDER — the results are equal in exact arithmetic and agree
# to ~1e-15 in doubles, not bit for bit. Where a value is exactly
# representable it is also asserted as a string. No float literal
# appears anywhere (they corrupt later call arguments on both engines);
# every float derives from integers via .to_f.

use spec
use koala

# --- helpers (spec-local; prefixed sw_ to stay out of koala's way) ---

# |a - b| as a float.
-> sw_gap(a, b)
  LinAlg.fabs(a.to_f - b.to_f)

# The tolerance every float comparison below uses: 1e-9, derived from
# integers.
-> sw_tol
  1.to_f / 1000000000.to_f

# Are two numeric arrays the same length and equal elementwise to within
# sw_tol? (Compiled Array `==` is identity, so arrays are never compared
# directly.)
-> sw_near(a, b)
  tol = sw_tol
  same = a != nil && b != nil
  same = a.size == b.size if same
  if same
    i = 0
    a.each -> (v)
      same = false if sw_gap(v, b[i]) > tol
      i += 1
  same

# The same, for an array of arrays (centroids, per-class means).
-> sw_near_rows(a, b)
  same = a != nil && b != nil
  same = a.size == b.size if same
  if same
    i = 0
    a.each -> (r)
      same = false if !sw_near(r, b[i])
      i += 1
  same

# `rows` with row i repeated counts[i] times — the dataset an integer
# weight vector is supposed to be indistinguishable from.
-> sw_expand(rows, counts)
  out = []
  i = 0
  rows.each -> (r)
    reps = counts[i]
    reps.times -> (t)
      out.push(r)
    i += 1
  out

describe "Estimator.weight_values (the one definition of a weight vector)" ->
  it "accepts a plain array, a Series and a Vector, as floats" ->
    expect(Estimator.weight_values([2, 1, 1], 3).join(",")).to eq("2,1,1")
    expect(Estimator.weight_values(Series.new([2, 1, 1], :w), 3).join(",")).to eq("2,1,1")
    expect(Estimator.weight_values(Vector.new([2, 1, 1]), 3).join(",")).to eq("2,1,1")

  it "returns nil — never raises — for every unusable vector" ->
    # wrong length (both directions)
    expect(Estimator.weight_values([1, 1], 3)).to be_nil
    expect(Estimator.weight_values([1, 1, 1, 1], 3)).to be_nil
    # empty
    expect(Estimator.weight_values([], 3)).to be_nil
    expect(Estimator.weight_values([], 0)).to be_nil
    # negative
    expect(Estimator.weight_values([1, 0 - 1, 1], 3)).to be_nil
    # a nil entry
    expect(Estimator.weight_values([1, nil, 1], 3)).to be_nil
    # every row dropped leaves nothing to learn from
    expect(Estimator.weight_values([0, 0, 0], 3)).to be_nil

  it "keeps a zero entry (it drops exactly one row)" ->
    expect(Estimator.weight_values([0, 1, 2], 3).join(",")).to eq("0,1,2")

  it "totals to the count when unweighted, and to the sum when weighted" ->
    expect(Estimator.weight_total(nil, 4)).to eq(4)
    expect(Estimator.weight_total([2.to_f, 1.to_f, 1.to_f], 3).to_s).to eq("4")

  it "drops zero-weight rows, keeping rows / targets / weights aligned" ->
    rows = [[1], [2], [3]]
    trimmed = Estimator.drop_zero_weights(rows, [:a, :b, :c], [1.to_f, 0.to_f, 2.to_f])
    expect(trimmed[:rows].size).to eq(2)
    expect(trimmed[:rows][0][0]).to eq(1)
    expect(trimmed[:rows][1][0]).to eq(3)
    expect(trimmed[:targets].join(",")).to eq("a,c")
    expect(trimmed[:weights].join(",")).to eq("1,2")

  it "passes unweighted and all-positive input straight through" ->
    rows = [[1], [2]]
    plain = Estimator.drop_zero_weights(rows, [:a, :b], nil)
    expect(plain[:weights]).to be_nil
    expect(plain[:rows].size).to eq(2)
    live = Estimator.drop_zero_weights(rows, [:a, :b], [1.to_f, 2.to_f])
    expect(live[:rows].size).to eq(2)
    expect(live[:targets].join(",")).to eq("a,b")

  it "keeps a nil target nil (an unsupervised fit has none)" ->
    trimmed = Estimator.drop_zero_weights([[1], [2]], nil, [0.to_f, 1.to_f])
    expect(trimmed[:targets]).to be_nil
    expect(trimmed[:rows].size).to eq(1)

  it "subsets a per-row vector in the caller's index order" ->
    expect(Estimator.subset([10, 20, 30, 40], [3, 0]).join(",")).to eq("40,10")
    expect(Estimator.subset(nil, [0, 1])).to be_nil

# --- Weighted metrics ---
#
# Every value here is hand-computed, and each is also checked against the
# duplicated dataset it stands for.
describe "Weighted metrics" ->
  it "weights accuracy by sum(w * hit) / sum(w)" ->
    preds = [1, 0, 1]
    act = [1, 0, 0]
    # rows 0 and 1 are correct: (2 + 1) / 4
    expect(Metrics.accuracy(preds, act, [2, 1, 1]).to_s).to eq("0.75")
    # ... which is exactly the duplicated dataset's accuracy
    expect(Metrics.accuracy([1, 1, 0, 1], [1, 1, 0, 0]).to_s).to eq("0.75")
    # all-1s is the unweighted number
    expect(Metrics.accuracy(preds, act, [1, 1, 1]).to_s).to eq(Metrics.accuracy(preds, act).to_s)

  it "weights mse / rmse / mae by sum(w * e) / sum(w)" ->
    preds = [1, 2, 3]
    act = [1, 2, 4]
    # squared errors 0, 0, 1 under weights 2, 1, 1 => 1 / 4
    expect(Metrics.mse(preds, act, [2, 1, 1]).to_s).to eq("0.25")
    expect(Metrics.rmse(preds, act, [2, 1, 1]).to_s).to eq("0.5")
    expect(Metrics.mae(preds, act, [2, 1, 1]).to_s).to eq("0.25")
    expect(Metrics.mse([1, 1, 2, 3], [1, 1, 2, 4]).to_s).to eq("0.25")

  it "weights r2's residuals AND its baseline mean" ->
    preds = [1, 2, 3]
    act = [1, 2, 4]
    # weighted mean of act under [2,1,1] is 8/4 = 2, so
    # ss_tot = 2*1 + 0 + 4 = 6, ss_res = 1, r2 = 1 - 1/6
    expect(Metrics.r2(preds, act, [2, 1, 1]).to_s).to eq("0.833333")
    expect(Metrics.r2([1, 1, 2, 3], [1, 1, 2, 4]).to_s).to eq("0.833333")
    # ... and it is NOT the unweighted number, so the weights really bit
    expect(Metrics.r2(preds, act).to_s).to eq(Metrics.r2(preds, act).to_s)
    expect(sw_gap(Metrics.r2(preds, act, [2, 1, 1]), Metrics.r2(preds, act)) > sw_tol).to be_true

  it "weights precision / recall / f1 / fbeta by their confusion cells" ->
    # actual has 2 positives (rows 0, 1); the model catches row 0 and
    # false-alarms on row 2.
    preds = [1, 0, 1]
    act = [1, 1, 0]
    w = [1, 3, 1]
    # weighted TP = 1, FN = 3, FP = 1
    expect(Metrics.precision(preds, act, 1, w).to_s).to eq("0.5")
    expect(Metrics.recall(preds, act, 1, w).to_s).to eq("0.25")
    # ... which the duplicated dataset agrees with
    expect(Metrics.precision([1, 0, 0, 0, 1], [1, 1, 1, 1, 0]).to_s).to eq("0.5")
    expect(Metrics.recall([1, 0, 0, 0, 1], [1, 1, 1, 1, 0]).to_s).to eq("0.25")
    # f1 = 2 * .5 * .25 / .75 = 1/3; fbeta(beta=1) is the same number
    expect(sw_gap(Metrics.f1(preds, act, 1, w), 1.to_f / 3.to_f) < sw_tol).to be_true
    expect(Metrics.fbeta(preds, act, 1, 1, w).to_s).to eq(Metrics.f1(preds, act, 1, w).to_s)
    # and unweighted they are the plain numbers
    expect(Metrics.precision(preds, act).to_s).to eq("0.5")
    expect(Metrics.recall(preds, act).to_s).to eq("0.5")
    expect(Metrics.precision(preds, act, 1, [1, 1])).to be_nil
    expect(Metrics.f1(preds, act, 1, [1, 1])).to be_nil
    expect(Metrics.fbeta(preds, act, 1, 1, [1, 1])).to be_nil

  it "is a no-op under all-1s weights, for every weighted metric" ->
    preds = [1, 2, 3, 5]
    act = [1, 3, 3, 4]
    ones = [1, 1, 1, 1]
    expect(Metrics.accuracy(preds, act, ones).to_s).to eq(Metrics.accuracy(preds, act).to_s)
    expect(Metrics.mse(preds, act, ones).to_s).to eq(Metrics.mse(preds, act).to_s)
    expect(Metrics.rmse(preds, act, ones).to_s).to eq(Metrics.rmse(preds, act).to_s)
    expect(Metrics.mae(preds, act, ones).to_s).to eq(Metrics.mae(preds, act).to_s)
    expect(Metrics.r2(preds, act, ones).to_s).to eq(Metrics.r2(preds, act).to_s)
    expect(Metrics.precision(preds, act, 1, ones).to_s).to eq(Metrics.precision(preds, act).to_s)
    expect(Metrics.recall(preds, act, 1, ones).to_s).to eq(Metrics.recall(preds, act).to_s)
    expect(Metrics.f1(preds, act, 1, ones).to_s).to eq(Metrics.f1(preds, act).to_s)
    expect(Metrics.fbeta(preds, act, 2, 1, ones).to_s).to eq(Metrics.fbeta(preds, act, 2).to_s)

  it "drops a zero-weight row from every weighted metric" ->
    # the fourth row is a disaster, and weight 0 makes it vanish
    preds = [1, 2, 3, 99]
    act = [1, 2, 3, 0]
    keep = [1, 1, 1, 0]
    expect(Metrics.mse(preds, act, keep).to_s).to eq("0")
    expect(Metrics.mae(preds, act, keep).to_s).to eq("0")
    expect(Metrics.accuracy(preds, act, keep).to_s).to eq("1")

  it "returns nil for an unusable weight vector, never a raise" ->
    preds = [1, 2, 3]
    act = [1, 2, 4]
    expect(Metrics.accuracy(preds, act, [1, 1])).to be_nil
    expect(Metrics.mse(preds, act, [1, 0 - 1, 1])).to be_nil
    expect(Metrics.rmse(preds, act, [])).to be_nil
    expect(Metrics.mae(preds, act, [0, 0, 0])).to be_nil
    expect(Metrics.r2(preds, act, [1, 1, 1, 1])).to be_nil

# --- LinearRegression: weighted least squares ---
describe "LinearRegression sample_weight (weighted least squares)" ->
  it "matches the hand-computed WLS solution" ->
    # x = 0..3, y = [0,1,2,5], w = [2,1,1,1]:
    #   sum w = 5, sum wx = 6, sum wx^2 = 14, sum wy = 8, sum wxy = 20
    #   slope = (5*20 - 6*8) / (5*14 - 36) = 52/34 = 26/17
    #   intercept = (8 - 6*26/17) / 5 = -4/17
    x = [[0], [1], [2], [3]]
    y = [0, 1, 2, 5]
    model = LinearRegression.new
    expect(model.fit(x, y, [2, 1, 1, 1]) != nil).to be_true
    expect(sw_gap(model.coefficients[0], 26.to_f / 17.to_f) < sw_tol).to be_true
    expect(sw_gap(model.intercept, 0.to_f - 4.to_f / 17.to_f) < sw_tol).to be_true

  it "gives EXACTLY the row-duplicated fit (OLS)" ->
    x = [[0], [1], [2], [3]]
    y = [0, 1, 2, 5]
    counts = [2, 1, 1, 1]
    weighted = LinearRegression.new
    weighted.fit(x, y, counts)
    dup = LinearRegression.new
    dup.fit(sw_expand(x, counts), sw_expand(y, counts))
    expect(sw_near(weighted.coefficients, dup.coefficients)).to be_true
    expect(sw_gap(weighted.intercept, dup.intercept) < sw_tol).to be_true
    # and the weighting genuinely moved the model
    plain = LinearRegression.new
    plain.fit(x, y)
    expect(sw_gap(weighted.coefficients[0], plain.coefficients[0]) > sw_tol).to be_true

  it "gives EXACTLY the row-duplicated fit (ridge, alpha > 0)" ->
    x = [[0], [1], [2], [3]]
    y = [0, 1, 2, 5]
    counts = [3, 1, 1, 2]
    weighted = LinearRegression.new(2)
    weighted.fit(x, y, counts)
    dup = LinearRegression.new(2)
    dup.fit(sw_expand(x, counts), sw_expand(y, counts))
    expect(sw_near(weighted.coefficients, dup.coefficients)).to be_true
    expect(sw_gap(weighted.intercept, dup.intercept) < sw_tol).to be_true

  it "is a no-op under all-1s weights" ->
    x = [[0], [1], [2], [3]]
    y = [0, 1, 2, 5]
    plain = LinearRegression.new
    plain.fit(x, y)
    ones = LinearRegression.new
    ones.fit(x, y, [1, 1, 1, 1])
    expect(ones.coefficients.to_s).to eq(plain.coefficients.to_s)
    expect(ones.intercept.to_s).to eq(plain.intercept.to_s)

  it "drops a zero-weight row entirely" ->
    x = [[0], [1], [2], [3], [4]]
    y = [3, 5, 7, 9, 1000]
    dropped = LinearRegression.new
    dropped.fit(x, y, [1, 1, 1, 1, 0])
    without = LinearRegression.new
    without.fit([[0], [1], [2], [3]], [3, 5, 7, 9])
    expect(sw_near(dropped.coefficients, without.coefficients)).to be_true
    expect(sw_gap(dropped.intercept, without.intercept) < sw_tol).to be_true
    # exact here: y = 3 + 2x on the surviving rows
    expect(dropped.coefficients.to_s).to eq("\[2\]")
    expect(dropped.intercept.to_s).to eq("3")

  it "returns nil (and stays unfitted) for an unusable weight vector" ->
    x = [[0], [1], [2], [3]]
    y = [0, 1, 2, 5]
    model = LinearRegression.new
    expect(model.fit(x, y, [1, 1])).to be_nil
    expect(model.fitted?).to be_false
    expect(model.fit(x, y, [])).to be_nil
    expect(model.fit(x, y, [1, 0 - 1, 1, 1])).to be_nil
    expect(model.fit(x, y, [0, 0, 0, 0])).to be_nil
    expect(model.fitted?).to be_false

  it "returns nil when the surviving rows cannot determine the fit" ->
    # two features, but only one row left after the zeros
    x = [[0, 0], [1, 2], [2, 4]]
    y = [1, 2, 3]
    expect(LinearRegression.new.fit(x, y, [1, 0, 0])).to be_nil

  it "weights score's R2 too" ->
    x = [[0], [1], [2], [3]]
    y = [0, 1, 2, 5]
    counts = [2, 1, 1, 1]
    model = LinearRegression.new
    model.fit(x, y, counts)
    dup = LinearRegression.new
    dup.fit(sw_expand(x, counts), sw_expand(y, counts))
    weighted_score = model.score(x, y, counts)
    expect(sw_gap(weighted_score, dup.score(sw_expand(x, counts), sw_expand(y, counts))) < sw_tol).to be_true
    expect(model.score(x, y, [1, 1])).to be_nil

# --- LogisticRegression: weighted gradient ---
describe "LogisticRegression sample_weight (weighted gradient)" ->
  it "gives the row-duplicated fit, epoch for epoch" ->
    x = [[0], [1], [2], [3]]
    y = [0, 0, 1, 1]
    counts = [3, 1, 1, 2]
    weighted = LogisticRegression.new(1, 40)
    weighted.fit(x, y, counts)
    dup = LogisticRegression.new(1, 40)
    dup.fit(sw_expand(x, counts), sw_expand(y, counts))
    expect(sw_near(weighted.coefficients, dup.coefficients)).to be_true
    expect(sw_gap(weighted.intercept, dup.intercept) < sw_tol).to be_true
    # the weighting really changed the boundary
    plain = LogisticRegression.new(1, 40)
    plain.fit(x, y)
    expect(sw_gap(weighted.intercept, plain.intercept) > sw_tol).to be_true

  it "is a no-op under all-1s weights" ->
    x = [[0], [1], [2], [3]]
    y = [0, 0, 1, 1]
    plain = LogisticRegression.new(1, 25)
    plain.fit(x, y)
    ones = LogisticRegression.new(1, 25)
    ones.fit(x, y, [1, 1, 1, 1])
    expect(ones.coefficients.to_s).to eq(plain.coefficients.to_s)
    expect(ones.intercept.to_s).to eq(plain.intercept.to_s)

  it "drops a zero-weight row, including from the class list" ->
    # the :c row is weighted out, so what is left is binary and fittable
    x = [[0], [1], [2]]
    y = [:a, :b, :c]
    model = LogisticRegression.new(1, 10)
    expect(model.fit(x, y)).to be_nil
    expect(model.fit(x, y, [1, 1, 0]) != nil).to be_true
    expect(model.classes.join(",")).to eq("a,b")

  it "returns nil for an unusable weight vector" ->
    x = [[0], [1], [2], [3]]
    y = [0, 0, 1, 1]
    model = LogisticRegression.new(1, 5)
    expect(model.fit(x, y, [1, 1, 1])).to be_nil
    expect(model.fit(x, y, [0 - 1, 1, 1, 1])).to be_nil
    expect(model.fitted?).to be_false

  it "weights score's accuracy" ->
    x = [[0], [1], [2], [3]]
    y = [0, 0, 1, 1]
    model = LogisticRegression.new(1, 200)
    model.fit(x, y)
    expect(model.score(x, y, [1, 1, 1, 1]).to_s).to eq(model.score(x, y).to_s)

# --- GaussianNB: weighted priors, means, variances ---
describe "GaussianNB sample_weight (weighted priors / means / variances)" ->
  it "gives the row-duplicated fit for every learned quantity" ->
    x = [[1, 1], [2, 1], [8, 9], [9, 8], [10, 10]]
    y = [:lo, :lo, :hi, :hi, :hi]
    counts = [3, 1, 1, 1, 2]
    weighted = GaussianNB.new
    weighted.fit(x, y, counts)
    dup = GaussianNB.new
    dup.fit(sw_expand(x, counts), sw_expand(y, counts))
    expect(weighted.classes.join(",")).to eq(dup.classes.join(","))
    expect(sw_near(weighted.class_counts, dup.class_counts)).to be_true
    expect(sw_near(weighted.class_priors, dup.class_priors)).to be_true
    expect(sw_near_rows(weighted.means, dup.means)).to be_true
    expect(sw_near_rows(weighted.variances, dup.variances)).to be_true
    expect(sw_gap(weighted.epsilon, dup.epsilon) < sw_tol).to be_true
    # and the weighting moved the priors away from the unweighted fit
    plain = GaussianNB.new
    plain.fit(x, y)
    expect(sw_gap(weighted.class_priors[0], plain.class_priors[0]) > sw_tol).to be_true

  it "reports class_counts as total WEIGHT and priors as its share" ->
    x = [[1], [2], [8], [9]]
    y = [:lo, :lo, :hi, :hi]
    model = GaussianNB.new
    model.fit(x, y, [3, 1, 1, 1])
    # lo carries 4 of the 6 total weight
    expect(model.class_counts.join(",")).to eq("4,2")
    expect(sw_gap(model.class_priors[0], 2.to_f / 3.to_f) < sw_tol).to be_true
    expect(sw_gap(model.class_priors[1], 1.to_f / 3.to_f) < sw_tol).to be_true

  it "is a no-op under all-1s weights" ->
    x = [[1, 1], [2, 1], [8, 9], [9, 8]]
    y = [:lo, :lo, :hi, :hi]
    plain = GaussianNB.new
    plain.fit(x, y)
    ones = GaussianNB.new
    ones.fit(x, y, [1, 1, 1, 1])
    expect(ones.class_counts.to_s).to eq(plain.class_counts.to_s)
    expect(ones.class_priors.to_s).to eq(plain.class_priors.to_s)
    expect(ones.means.to_s).to eq(plain.means.to_s)
    expect(ones.variances.to_s).to eq(plain.variances.to_s)

  it "makes a class that carries no weight disappear entirely" ->
    x = [[1], [2], [50]]
    y = [:lo, :lo, :odd]
    model = GaussianNB.new
    model.fit(x, y, [1, 1, 0])
    expect(model.classes.join(",")).to eq("lo")
    expect(model.class_counts.join(",")).to eq("2")
    expect(model.predict([[50]]).join(",")).to eq("lo")

  it "returns nil for an unusable weight vector" ->
    x = [[1], [2], [8], [9]]
    y = [:lo, :lo, :hi, :hi]
    model = GaussianNB.new
    expect(model.fit(x, y, [1, 1, 1])).to be_nil
    expect(model.fit(x, y, [1, 1, 1, 0 - 2])).to be_nil
    expect(model.fitted?).to be_false

# --- DecisionTreeClassifier: weighted impurity and leaf votes ---
describe "DecisionTreeClassifier sample_weight (weighted impurity)" ->
  it "takes the HEAVIEST class at a leaf, not the most numerous" ->
    # max_depth 0 makes the root itself the leaf, so this reads the leaf
    # rule directly: 1 x :a against 2 x :b is :b, but weight 3 flips it.
    x = [[0], [1], [2]]
    y = [:a, :b, :b]
    plain = DecisionTreeClassifier.new(0)
    plain.fit(x, y)
    expect(plain.predict([[0]]).join(",")).to eq("b")
    heavy = DecisionTreeClassifier.new(0)
    heavy.fit(x, y, [3, 1, 1])
    expect(heavy.predict([[0]]).join(",")).to eq("a")
    dup = DecisionTreeClassifier.new(0)
    dup.fit(sw_expand(x, [3, 1, 1]), sw_expand(y, [3, 1, 1]))
    expect(dup.predict([[0]]).join(",")).to eq("a")
    # the leaf's class distribution is counts / total WEIGHT
    expect(sw_near(heavy.predict_proba([[0]])[0], dup.predict_proba([[0]])[0])).to be_true
    expect(sw_gap(heavy.predict_proba([[0]], :a)[0], 3.to_f / 5.to_f) < sw_tol).to be_true

  it "grows the row-duplicated TREE — shape, splits and probabilities" ->
    x = [[0, 0], [1, 0], [0, 1], [1, 1], [2, 2], [3, 3]]
    y = [0, 0, 1, 1, 1, 0]
    counts = [2, 1, 1, 3, 1, 1]
    grid = [[0, 0], [1, 0], [0, 1], [1, 1], [2, 2], [3, 3], [2, 0]]
    weighted = DecisionTreeClassifier.new(2)
    weighted.fit(x, y, counts)
    dup = DecisionTreeClassifier.new(2)
    dup.fit(sw_expand(x, counts), sw_expand(y, counts))
    expect(weighted.depth).to eq(dup.depth)
    expect(weighted.leaf_count).to eq(dup.leaf_count)
    expect(weighted.tree[:feature]).to eq(dup.tree[:feature])
    expect(sw_gap(weighted.tree[:threshold], dup.tree[:threshold]) < sw_tol).to be_true
    expect(sw_gap(weighted.tree[:impurity], dup.tree[:impurity]) < sw_tol).to be_true
    expect(weighted.predict(grid).join(",")).to eq(dup.predict(grid).join(","))
    expect(sw_near(weighted.predict_proba(grid, 1), dup.predict_proba(grid, 1))).to be_true

  it "is a no-op under all-1s weights" ->
    x = [[0, 0], [1, 0], [0, 1], [1, 1], [2, 2], [3, 3]]
    y = [0, 0, 1, 1, 1, 0]
    plain = DecisionTreeClassifier.new
    plain.fit(x, y)
    ones = DecisionTreeClassifier.new
    ones.fit(x, y, [1, 1, 1, 1, 1, 1])
    expect(ones.tree_lines.join(" | ")).to eq(plain.tree_lines.join(" | "))

  it "drops a zero-weight row from the tree AND from the class list" ->
    x = [[0], [1], [2]]
    y = [:a, :a, :outlier]
    model = DecisionTreeClassifier.new
    model.fit(x, y, [1, 1, 0])
    expect(model.classes.join(",")).to eq("a")
    expect(model.tree[:leaf]).to be_true
    expect(model.tree[:n]).to eq(2)
    expect(model.predict([[2]]).join(",")).to eq("a")

  it "returns nil for an unusable weight vector" ->
    x = [[0], [1], [2], [3]]
    y = [0, 0, 1, 1]
    model = DecisionTreeClassifier.new
    expect(model.fit(x, y, [1, 1, 1])).to be_nil
    expect(model.fit(x, y, [0, 0, 0, 0])).to be_nil
    expect(model.fitted?).to be_false

describe "DecisionTreeRegressor sample_weight (weighted MSE)" ->
  it "gives the row-duplicated tree's predictions" ->
    x = [[0], [1], [2], [3], [4]]
    y = [1, 2, 3, 10, 11]
    counts = [4, 1, 1, 1, 2]
    grid = [[0], [1], [2], [3], [4]]
    weighted = DecisionTreeRegressor.new(1)
    weighted.fit(x, y, counts)
    dup = DecisionTreeRegressor.new(1)
    dup.fit(sw_expand(x, counts), sw_expand(y, counts))
    expect(sw_gap(weighted.tree[:threshold], dup.tree[:threshold]) < sw_tol).to be_true
    expect(sw_gap(weighted.tree[:impurity], dup.tree[:impurity]) < sw_tol).to be_true
    expect(sw_near(weighted.predict(grid), dup.predict(grid))).to be_true

  it "predicts the WEIGHTED mean at a leaf" ->
    # root-only tree: mean of [1, 5] under weights [3, 1] is 8/4 = 2
    model = DecisionTreeRegressor.new(0)
    model.fit([[0], [1]], [1, 5], [3, 1])
    expect(model.predict([[0]]).join(",")).to eq("2")

  it "is a no-op under all-1s weights" ->
    x = [[0], [1], [2], [3], [4]]
    y = [1, 2, 3, 10, 11]
    plain = DecisionTreeRegressor.new(2)
    plain.fit(x, y)
    ones = DecisionTreeRegressor.new(2)
    ones.fit(x, y, [1, 1, 1, 1, 1])
    expect(ones.tree_lines.join(" | ")).to eq(plain.tree_lines.join(" | "))

  it "weights score's R2" ->
    x = [[0], [1], [2], [3]]
    y = [1, 2, 3, 10]
    model = DecisionTreeRegressor.new(1)
    model.fit(x, y)
    expect(model.score(x, y, [1, 1, 1, 1]).to_s).to eq(model.score(x, y).to_s)
    expect(model.score(x, y, [1, 1])).to be_nil

# --- KMeans: weighted centroids ---
describe "KMeans sample_weight (weighted centroids)" ->
  it "puts a centroid at the WEIGHTED mean" ->
    # one cluster over [0] and [10] with weights 3 and 1: 10/4 = 2.5
    model = KMeans.new(1)
    model.fit([[0], [10]], [3, 1])
    expect(model.centroids[0][0].to_s).to eq("2.5")
    # inertia is the weighted sum of squares: 3*6.25 + 1*56.25 = 75
    expect(model.inertia.to_s).to eq("75")

  it "gives the row-duplicated clustering" ->
    x = [[0, 0], [1, 0], [4, 4], [5, 4], [9, 9]]
    counts = [3, 1, 1, 2, 1]
    weighted = KMeans.new(2)
    weighted.fit(x, counts)
    dup = KMeans.new(2)
    dup.fit(sw_expand(x, counts))
    expect(sw_near_rows(weighted.centroids, dup.centroids)).to be_true
    expect(sw_gap(weighted.inertia, dup.inertia) < sw_tol).to be_true
    # and the weighting moved the centroids
    plain = KMeans.new(2)
    plain.fit(x)
    expect(sw_near_rows(weighted.centroids, plain.centroids)).to be_false

  it "is a no-op under all-1s weights" ->
    x = [[0, 0], [2, 0], [0, 2], [2, 2], [10, 10], [12, 10], [10, 12], [12, 12]]
    plain = KMeans.new(2)
    plain.fit(x)
    ones = KMeans.new(2)
    ones.fit(x, [1, 1, 1, 1, 1, 1, 1, 1])
    expect(ones.centroids.to_s).to eq(plain.centroids.to_s)
    expect(ones.inertia.to_s).to eq(plain.inertia.to_s)
    expect(ones.labels.join(",")).to eq(plain.labels.join(","))
    expect(ones.n_iter).to eq(plain.n_iter)

  it "never SEEDS a centroid from a zero-weight row, but still labels it" ->
    # the first row is weighted out; init must start from row 1, exactly
    # as the duplicated dataset (which has no row 0 at all) does.
    x = [[0, 0], [10, 10], [11, 11]]
    model = KMeans.new(2)
    model.fit(x, [0, 1, 1])
    expect(model.labels.size).to eq(3)
    expect(model.centroids.size).to eq(2)
    dup = KMeans.new(2)
    dup.fit([[10, 10], [11, 11]])
    expect(sw_near_rows(model.centroids, dup.centroids)).to be_true
    # a zero-weight row contributes nothing to inertia
    expect(model.inertia.to_s).to eq(dup.inertia.to_s)

  it "returns nil when too few rows carry weight for k clusters" ->
    model = KMeans.new(3)
    expect(model.fit([[0], [1], [2]], [1, 1, 0])).to be_nil
    expect(model.fitted?).to be_false

  it "returns nil for an unusable weight vector" ->
    model = KMeans.new(2)
    expect(model.fit([[0], [1], [2]], [1, 1])).to be_nil
    expect(model.fit([[0], [1], [2]], [1, 1, 0 - 1])).to be_nil
    expect(model.fitted?).to be_false

  it "weights score's negated inertia" ->
    x = [[0], [10]]
    model = KMeans.new(1)
    model.fit(x)
    # centroid 5; weighted -inertia under [3,1] is -(3*25 + 1*25) = -100
    expect(model.score(x, [3, 1]).to_s).to eq("-100")
    expect(model.score(x, [1, 1]).to_s).to eq(model.score(x).to_s)
    expect(model.score(x, [1, 1, 1])).to be_nil

# --- KNNClassifier: the deliberate refusal ---
describe "KNNClassifier sample_weight (deliberately unsupported)" ->
  it "says so through the contract" ->
    expect(KNNClassifier.new(1).supports_sample_weight?).to be_false

  it "returns nil from fit rather than silently ignoring the weights" ->
    x = [[0], [1], [10], [11]]
    y = [0, 0, 1, 1]
    model = KNNClassifier.new(1)
    expect(model.fit(x, y, [2, 1, 1, 1])).to be_nil
    expect(model.fitted?).to be_false
    # even an all-1s vector is refused: the answer is "not supported",
    # not "supported when it happens not to matter"
    expect(model.fit(x, y, [1, 1, 1, 1])).to be_nil
    # and the unweighted fit is untouched
    expect(model.fit(x, y) != nil).to be_true
    expect(model.fitted?).to be_true

  it "still honours weights in score, where they are well defined" ->
    x = [[0], [1], [10], [11]]
    y = [0, 0, 1, 1]
    model = KNNClassifier.new(1)
    model.fit(x, y)
    wrong = [0, 0, 1, 0]
    # unweighted 3/4; with the mistaken row weighted 3x, 3/6
    expect(model.score(x, wrong).to_s).to eq("0.75")
    expect(model.score(x, wrong, [1, 1, 1, 3]).to_s).to eq("0.5")
    expect(model.score(x, wrong, [1, 1])).to be_nil

# --- The contract itself ---
describe "The sample-weight contract" ->
  it "every estimator answers supports_sample_weight?, correctly" ->
    models = []
    models.push(LinearRegression.new)
    models.push(KNNClassifier.new(1))
    models.push(LogisticRegression.new(1, 5))
    models.push(GaussianNB.new)
    models.push(DecisionTreeClassifier.new)
    models.push(DecisionTreeRegressor.new)
    models.push(KMeans.new(2))
    missing = []
    models.each -> (m)
      missing.push(m.estimator_name) if !m.respond_to?("supports_sample_weight?")
    expect(missing.join(",")).to eq("")
    yes = []
    models.each -> (m)
      yes.push(m.estimator_name) if m.supports_sample_weight?
    # everything but KNNClassifier, matching scikit-learn
    expect(yes.join(",")).to eq("LinearRegression,LogisticRegression,GaussianNB,DecisionTreeClassifier,DecisionTreeRegressor,KMeans")

  it "dispatches weights generically through fit_model / score_model" ->
    x = [[0], [1], [2], [3]]
    y = [0, 1, 2, 5]
    w = [2.to_f, 1.to_f, 1.to_f, 1.to_f]
    direct = LinearRegression.new
    direct.fit(x, y, w)
    generic = LinearRegression.new
    expect(Estimator.fit_model(generic, x, y, w) != nil).to be_true
    expect(sw_near(generic.coefficients, direct.coefficients)).to be_true
    expect(sw_gap(Estimator.score_model(generic, x, y, w), direct.score(x, y, w)) < sw_tol).to be_true
    # unsupervised gets the weights in the ONE argument its fit has
    km = KMeans.new(1)
    expect(Estimator.fit_model(km, [[0], [10]], nil, [3.to_f, 1.to_f]) != nil).to be_true
    expect(km.centroids[0][0].to_s).to eq("2.5")

  it "leaves the three-argument dispatch byte-identical" ->
    x = [[0], [1], [2], [3]]
    y = [0, 1, 2, 5]
    plain = LinearRegression.new
    plain.fit(x, y)
    generic = LinearRegression.new
    Estimator.fit_model(generic, x, y)
    expect(generic.coefficients.to_s).to eq(plain.coefficients.to_s)
    expect(generic.intercept.to_s).to eq(plain.intercept.to_s)

  it "a Pipeline delegates supports_sample_weight? to its tail" ->
    expect(Pipeline.new([Scaler.new(:standard), LinearRegression.new]).supports_sample_weight?).to be_true
    expect(Pipeline.new([Scaler.new(:standard), KNNClassifier.new(1)]).supports_sample_weight?).to be_false
    expect(Pipeline.new([Scaler.new(:standard)]).supports_sample_weight?).to be_false

  it "a Pipeline threads weights to its estimator tail" ->
    x = [[0], [1], [2], [3]]
    y = [0, 1, 2, 5]
    counts = [2, 1, 1, 1]
    pipe = Pipeline.new([Imputer.new(:mean), LinearRegression.new])
    expect(pipe.fit(x, y, counts) != nil).to be_true
    tail = pipe[1]
    direct = LinearRegression.new
    direct.fit(x, y, counts)
    expect(sw_near(tail.coefficients, direct.coefficients)).to be_true
    expect(sw_gap(pipe.score(x, y, counts), direct.score(x, y, counts)) < sw_tol).to be_true

  it "a GridSearch reports and threads them" ->
    expect(GridSearch.new(KNNClassifier.new(1), { k: [1] }, 2).supports_sample_weight?).to be_false
    expect(GridSearch.new(DecisionTreeClassifier.new, { max_depth: [1] }, 2).supports_sample_weight?).to be_true

# --- Cross-validation ---
describe "Cross-validation with sample_weight" ->
  it "subsets the weights per fold, in the fold's own index order" ->
    # LeaveOneOut on 4 rows: each fold trains on 3 and tests on 1, so a
    # weight that lands on the wrong row would change every score.
    x = [[0], [1], [2], [3]]
    y = [0, 1, 2, 5]
    counts = [2, 1, 1, 1]
    scores = CrossValidation.cross_val_score(LinearRegression.new, x, y, LeaveOneOut.new, nil, counts)
    expect(scores.size).to eq(4)
    # each fold's weighted fit equals the same fold fitted by hand
    hand = []
    4.times -> (drop)
      tr_x = []
      tr_y = []
      tr_w = []
      j = 0
      x.each -> (r)
        if j != drop
          tr_x.push(r)
          tr_y.push(y[j])
          tr_w.push(counts[j])
        j += 1
      m = LinearRegression.new
      m.fit(tr_x, tr_y, tr_w)
      s = nil
      s = m.score([x[drop]], [y[drop]], [counts[drop]]) if m != nil
      hand.push(s)
    expect(sw_near(scores, hand)).to be_true

  it "is a no-op under all-1s weights" ->
    x = [[0], [1], [2], [3], [4], [5]]
    y = [0, 1, 2, 5, 4, 6]
    ones = [1, 1, 1, 1, 1, 1]
    plain = CrossValidation.cross_val_score(LinearRegression.new, x, y, 3)
    same = CrossValidation.cross_val_score(LinearRegression.new, x, y, 3, nil, ones)
    expect(sw_near(same, plain)).to be_true

  it "actually changes the mean when the weights are not uniform" ->
    x = [[0], [1], [2], [3], [4], [5]]
    y = [0, 1, 2, 9, 4, 6]
    heavy = [1, 1, 1, 5, 1, 1]
    plain = CrossValidation.cross_val_mean(LinearRegression.new, x, y, 3)
    tilted = CrossValidation.cross_val_mean(LinearRegression.new, x, y, 3, nil, heavy)
    expect(sw_gap(plain, tilted) > sw_tol).to be_true

  it "carries weights into an unsupervised run too" ->
    x = [[0], [1], [10], [11], [20], [21]]
    scores = CrossValidation.cross_val_score(KMeans.new(2), x, nil, 3, nil, [1, 1, 1, 1, 1, 1])
    plain = CrossValidation.cross_val_score(KMeans.new(2), x, nil, 3)
    expect(sw_near(scores, plain)).to be_true

  it "scores every fold nil for an estimator that refuses weights" ->
    x = [[0], [1], [10], [11]]
    y = [0, 0, 1, 1]
    scores = CrossValidation.cross_val_score(KNNClassifier.new(1), x, y, 2, nil, [2, 1, 1, 1])
    expect(scores.size).to eq(2)
    expect(scores[0]).to be_nil
    expect(scores[1]).to be_nil
    expect(CrossValidation.cross_val_mean(KNNClassifier.new(1), x, y, 2, nil, [2, 1, 1, 1])).to be_nil

  it "returns nil for an unusable weight vector" ->
    x = [[0], [1], [2], [3]]
    y = [0, 1, 2, 5]
    expect(CrossValidation.cross_val_score(LinearRegression.new, x, y, 2, nil, [1, 1])).to be_nil
    expect(CrossValidation.cross_val_score(LinearRegression.new, x, y, 2, nil, [1, 1, 0 - 1, 1])).to be_nil
    expect(CrossValidation.cross_val_mean(LinearRegression.new, x, y, 2, nil, [])).to be_nil

  it "reaches GridSearch through the same argument" ->
    x = [[0], [1], [2], [3], [10], [11], [12], [13]]
    y = [0, 0, 0, 0, 1, 1, 1, 1]
    gs = GridSearch.new(DecisionTreeClassifier.new, { max_depth: [1, 2] }, 2)
    expect(gs.fit(x, y, [2, 1, 1, 1, 1, 1, 1, 2]) != nil).to be_true
    expect(gs.best_score != nil).to be_true
    expect(gs.best_estimator.fitted?).to be_true

spec_summary
