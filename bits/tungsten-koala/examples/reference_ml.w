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
# stratification, mixed numeric/categorical preprocessing, distance-weighted
# nearest neighbours, binary/multiclass gradient boosting, model-agnostic
# permutation importance, linear/RBF support-vector classification,
# cross-fitted probability calibration around a preprocessing Pipeline,
# and unsupervised cluster-quality evaluation.

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
boosted_xor = GradientBoostingClassifier.new(20, 1.to_f / 10.to_f, 2)
boosted_xor.fit(xor_x, xor_y)
boosted_xor_score = boosted_xor.score(xor_x, xor_y)
lines.push("xor raw accuracy " + raw_score.to_s)
lines.push("xor polynomial accuracy " + poly_score.to_s)
lines.push("xor boosted accuracy " + boosted_xor_score.to_s)
ok = false if raw_score.to_s != "0.5"
ok = false if poly_score.to_s != "1"
ok = false if boosted_xor_score.to_s != "1"
linear_svc = SVC.new(10, :linear, 1)
rbf_svc = SVC.new(10, :rbf, 1)
linear_svc.fit(xor_x, xor_y)
rbf_svc.fit(xor_x, xor_y)
linear_svc_score = linear_svc.score(xor_x, xor_y)
rbf_svc_score = rbf_svc.score(xor_x, xor_y)
lines.push("xor SVC linear/RBF accuracy " + linear_svc_score.to_s + "/" + rbf_svc_score.to_s)
lines.push("xor SVC support vectors " + rbf_svc.support_vectors.size.to_s)
ok = false if linear_svc_score.to_s != "0.5"
ok = false if rbf_svc_score.to_s != "1"
ok = false if rbf_svc.support_vectors.size != 4

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
quad_stump = DecisionTreeRegressor.new(1)
quad_stump.fit(quad_x, quad_y)
quad_boost = GradientBoostingRegressor.new(60, 1.to_f / 10.to_f, 2)
quad_boost.fit(quad_x, quad_y)
lines.push("quadratic stump/boost R2 " + quad_stump.score(quad_x, quad_y).to_s + "/" + quad_boost.score(quad_x, quad_y).to_s)
ok = false if quad_boost.score(quad_x, quad_y) - quad_stump.score(quad_x, quad_y) < 1.to_f / 2.to_f

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
class_boost = GradientBoostingClassifier.new(20, 1.to_f / 10.to_f, 2)
class_boost_scores = CrossValidation.cross_val_score(
  class_boost, class_x, class_y, StratifiedKFold.new(3)
)
class_boost.fit(class_x, class_y)
lines.push("multiclass GradientBoosting CV " + class_boost_scores.to_s)
lines.push("multiclass GradientBoosting log loss " + class_boost.log_loss(class_x, class_y).to_s)
ok = false if class_boost_scores.to_s != "\[1, 1, 1\]"
ok = false if class_boost.log_loss(class_x, class_y) > 1.to_f / 10.to_f
class_svc_scores = CrossValidation.cross_val_score(
  SVC.new(2, :linear), class_x, class_y, StratifiedKFold.new(3)
)
lines.push("multiclass SVC CV " + class_svc_scores.to_s)
ok = false if class_svc_scores.to_s != "\[1, 1, 1\]"

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

# 5. A heterogeneous DataFrame where the number is deliberately uninformative:
# only the one-hot city branch can solve it. CV must preserve the DataFrame
# schema until ColumnTransformer selects and composes its parallel branches.
mixed_age = []
mixed_city = []
mixed_y = []
6.times -> (i)
  mixed_age.push(i + 1)
  mixed_city.push("red")
  mixed_y.push(0)
  mixed_age.push(i + 1)
  mixed_city.push("blue")
  mixed_y.push(1)
  mixed_age.push(i + 1)
  mixed_city.push("green")
  mixed_y.push(0)
mixed_x = DataFrame.new([[:age, mixed_age], [:city, mixed_city]])
mixed_pipe = Pipeline.new([
  [:prep, ColumnTransformer.new([
    [:num, Scaler.new(:standard), [:age]],
    [:cat, Encoder.new(:one_hot), [:city]]
  ])],
  [:model, LogisticRegression.new(1, 300)]
])
mixed_scores = CrossValidation.cross_val_score(
  mixed_pipe, mixed_x, mixed_y, StratifiedKFold.new(3)
)
lines.push("mixed ColumnTransformer CV " + mixed_scores.to_s)
ok = false if mixed_scores.to_s != "\[1, 1, 1\]"
mixed_pipe.fit(mixed_x, mixed_y)
mixed_importance = PermutationImportance.compute(
  mixed_pipe, mixed_x, mixed_y, 12, 42
)
lines.push(
  "mixed permutation importance " +
  mixed_importance.feature_names.join(",") + " " +
  mixed_importance.importances_mean.to_s
)
ok = false if mixed_importance.feature_names.join(",") != "age,city"
ok = false if LinAlg.fabs(mixed_importance.importances_mean[0]) > 1.to_f / 1000000000.to_f
ok = false if mixed_importance.importances_mean[1] <= 1.to_f / 4.to_f

# 6. Distance-weighted KNN fixes a majority-vote error and exposes calibrated
# class probabilities; the regressor uses the same inverse-Euclidean rule.
knn_train_x = [[0], [4], [5]]
knn_test_x = [[1], [9.to_f / 2.to_f]]
knn_test_y = [:a, :b]
knn_uniform = KNNClassifier.new(3)
knn_uniform.fit(knn_train_x, [:a, :b, :b])
knn_distance = KNNClassifier.new(3, :distance)
knn_distance.fit(knn_train_x, [:a, :b, :b])
knn_uniform_accuracy = knn_uniform.score(knn_test_x, knn_test_y)
knn_distance_accuracy = knn_distance.score(knn_test_x, knn_test_y)
knn_probability = knn_distance.predict_proba([[1]], :a)[0]
knn_regression = KNeighborsRegressor.new(3, :distance)
knn_regression.fit(knn_train_x, [0, 4, 5])
knn_regression_prediction = knn_regression.predict([[1]])[0]
lines.push("KNN uniform/distance accuracy " + knn_uniform_accuracy.to_s + "/" + knn_distance_accuracy.to_s)
lines.push("KNN distance class-a probability " + knn_probability.to_s)
lines.push("KNN regression prediction " + knn_regression_prediction.to_s)
ok = false if knn_uniform_accuracy.to_s != "0.5"
ok = false if knn_distance_accuracy.to_s != "1"
ok = false if LinAlg.fabs(knn_probability - 12.to_f / 19.to_f) > 1.to_f / 1000000000000.to_f
ok = false if LinAlg.fabs(knn_regression_prediction - 31.to_f / 19.to_f) > 1.to_f / 1000000000000.to_f

# 7. A cross-fitted sigmoid calibrator wraps a full preprocessing Pipeline,
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

# 8. Two compact boxes ten units apart. KMeans recovers the two groups;
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
