# Reference ML problems — self-checking end-to-end Koala pipelines.
#
# Run on either engine:
#   bin/tungsten run bits/tungsten-koala/examples/reference_ml.w
#   bin/tungsten compile bits/tungsten-koala/examples/reference_ml.w --out /tmp/koala-reference
#   /tmp/koala-reference
#
# These are small, deterministic capability probes, not claims about
# large-scale throughput: nonlinear classification, exact polynomial
# regression under cross-validation, multiclass classification with
# stratification, cross-fitted probability calibration around a preprocessing
# Pipeline, and unsupervised cluster-quality evaluation.

use koala

lines = []
ok = true

# 1. XOR: raw logistic regression is linear and reaches only 50%.
# Degree-2 PolynomialFeatures adds the interaction needed to solve it.
xor_x = [[0, 0], [0, 1], [1, 0], [1, 1]]
xor_y = [0, 1, 1, 0]
raw = LogisticRegression.new(1, 2000)
raw.fit(xor_x, xor_y)
xor_pipe = Pipeline.new([
  [:poly, PolynomialFeatures.new(2)],
  [:model, LogisticRegression.new(1, 2000)]
])
xor_pipe.fit(xor_x, xor_y)
raw_score = raw.score(xor_x, xor_y)
poly_score = xor_pipe.score(xor_x, xor_y)
lines.push("xor raw accuracy " + raw_score.to_s)
lines.push("xor polynomial accuracy " + poly_score.to_s)
ok = false if raw_score.to_s != "0.5"
ok = false if poly_score.to_s != "1"

# 2. Exact quadratic regression: every fold fits y = 3x^2 + 2x + 1
# through a degree-2 expansion and gets R² 1 on held-out rows.
quad_x = [0 - 7, 0 - 6, 0 - 5, 0 - 4, 0 - 3, 0 - 2, 0 - 1, 0, 1, 2, 3, 4, 5, 6, 7]
quad_y = []
quad_x.each -> (v)
  quad_y.push(3 * v * v + 2 * v + 1)
quad_pipe = Pipeline.new([PolynomialFeatures.new(2), LinearRegression.new])
quad_scores = CrossValidation.cross_val_score(quad_pipe, quad_x, quad_y, 3)
lines.push("quadratic polynomial CV " + quad_scores.to_s)
ok = false if quad_scores.to_s != "\[1, 1, 1\]"
ok = false if quad_pipe.fitted?

# 3. Three well-separated classes. Stratified folds keep one point from
# each class in every test fold; GaussianNB classifies all nine correctly.
class_x = [[0, 0], [0, 1], [1, 0],
           [10, 10], [10, 11], [11, 10],
           [20, 0], [20, 1], [21, 0]]
class_y = [:a, :a, :a, :b, :b, :b, :c, :c, :c]
class_scores = CrossValidation.cross_val_score(
  GaussianNB.new, class_x, class_y, StratifiedKFold.new(3)
)
lines.push("multiclass GaussianNB CV " + class_scores.to_s)
ok = false if class_scores.to_s != "\[1, 1, 1\]"

# 4. A balanced three-class linear problem. Multinomial LogisticRegression
# fits through stable softmax, cross-validates perfectly, and assigns the
# all-zero center equal probability for every class.
softmax_x = []
softmax_y = []
6.times -> (i)
  softmax_x.push([1, 0, 0])
  softmax_y.push(:a)
6.times -> (i)
  softmax_x.push([0, 1, 0])
  softmax_y.push(:b)
6.times -> (i)
  softmax_x.push([0, 0, 1])
  softmax_y.push(:c)
softmax_scores = CrossValidation.cross_val_score(
  LogisticRegression.new(1, 100),
  softmax_x,
  softmax_y,
  StratifiedKFold.new(3)
)
softmax = LogisticRegression.new(1, 100)
softmax.fit(softmax_x, softmax_y)
center = softmax.predict_proba([[0, 0, 0]])
lines.push("multiclass LogisticRegression CV " + softmax_scores.to_s)
lines.push("multiclass center probabilities " + center[0].to_s)
ok = false if softmax_scores.to_s != "\[1, 1, 1\]"
ok = false if center[0].size != 3
center[0].each -> (p)
  ok = false if LinAlg.fabs(p - 1.to_f / 3.to_f) > 1.to_f / 1000000.to_f

# 5. A cross-fitted sigmoid calibrator wraps a full preprocessing Pipeline,
# preserving class metadata and returning normalized held-out probabilities.
cal_x = [[0], [1], [2], [3], [4], [5], [6], [7], [8], [9], [10], [11]]
cal_y = [:cold, :cold, :cold, :cold, :cold, :cold,
         :hot, :hot, :hot, :hot, :hot, :hot]
cal_base = Pipeline.new([
  [:scale, Scaler.new(:standard)],
  [:tree, DecisionTreeClassifier.new(2)]
])
calibrated = CalibratedClassifierCV.new(cal_base, :sigmoid, 3)
calibrated.fit(cal_x, cal_y)
cal_probs = calibrated.predict_proba([[2], [9]])
lines.push("calibrated Pipeline probabilities " + cal_probs.to_s)
ok = false if calibrated.predict([[2], [9]]).join(",") != "cold,hot"
cal_probs.each -> (row)
  ok = false if LinAlg.fabs(Stats.sum(row) - 1.to_f) > 1.to_f / 1000000.to_f

# 6. Two compact boxes ten units apart. KMeans recovers the two groups;
# silhouette checks separation independently of the training objective.
cluster_x = [[0, 0], [0, 1], [1, 0], [1, 1],
             [10, 10], [10, 11], [11, 10], [11, 11]]
km = KMeans.new(2)
km.fit(cluster_x)
silhouette = Metrics.silhouette_score(cluster_x, km.labels)
lines.push("two-box KMeans silhouette " + silhouette.to_s)
ok = false if silhouette < 9.to_f / 10.to_f

<< lines.join("\n")
if !ok
  << "REFERENCE ML: FAILED"
  exit(1)
<< "REFERENCE ML: OK"
