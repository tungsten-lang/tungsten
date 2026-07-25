# Machine-readable side of benchmarks/reference_sklearn.py.

use koala

xor_x = [[0, 0], [0, 1], [1, 0], [1, 1]]
xor_y = [0, 1, 1, 0]
raw = LogisticRegression.new(1, 2000)
raw.fit(xor_x, xor_y)
poly = Pipeline.new([PolynomialFeatures.new(2), LogisticRegression.new(1, 2000)])
poly.fit(xor_x, xor_y)
<< "xor_raw_accuracy," + raw.score(xor_x, xor_y).to_s
<< "xor_poly_accuracy," + poly.score(xor_x, xor_y).to_s
xor_boost = GradientBoostingClassifier.new(20, 1.to_f / 10.to_f, 2)
xor_boost.fit(xor_x, xor_y)
<< "xor_boost_accuracy," + xor_boost.score(xor_x, xor_y).to_s
<< "xor_boost_log_loss," + xor_boost.log_loss(xor_x, xor_y).to_s

quad_x = [0 - 7, 0 - 6, 0 - 5, 0 - 4, 0 - 3, 0 - 2, 0 - 1, 0, 1, 2, 3, 4, 5, 6, 7]
quad_y = []
quad_x.each -> (v)
  quad_y.push(3 * v * v + 2 * v + 1)
quad = Pipeline.new([PolynomialFeatures.new(2), LinearRegression.new])
<< "quadratic_cv_mean," + CrossValidation.cross_val_mean(quad, quad_x, quad_y, 3).to_s
quadratic_stump = DecisionTreeRegressor.new(1)
quadratic_stump.fit(quad_x, quad_y)
quadratic_boost = GradientBoostingRegressor.new(60, 1.to_f / 10.to_f, 2)
quadratic_boost.fit(quad_x, quad_y)
<< "quadratic_stump_r2," + quadratic_stump.score(quad_x, quad_y).to_s
<< "quadratic_boost_r2," + quadratic_boost.score(quad_x, quad_y).to_s

class_x = [[0, 0], [0, 1], [1, 0],
           [10, 10], [10, 11], [11, 10],
           [20, 0], [20, 1], [21, 0]]
class_y = [:a, :a, :a, :b, :b, :b, :c, :c, :c]
nb = GaussianNB.new
<< "multiclass_nb_cv_mean," + CrossValidation.cross_val_mean(nb, class_x, class_y, StratifiedKFold.new(3)).to_s
class_boost = GradientBoostingClassifier.new(20, 1.to_f / 10.to_f, 2)
<< "multiclass_boost_cv_mean," + CrossValidation.cross_val_mean(class_boost, class_x, class_y, StratifiedKFold.new(3)).to_s
class_boost.fit(class_x, class_y)
<< "multiclass_boost_log_loss," + class_boost.log_loss(class_x, class_y).to_s

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
softmax = LogisticRegression.new(1, 100)
softmax.fit(softmax_x, softmax_y)
center_probs = softmax.predict_proba([[0, 0, 0], [0, 0, 0], [0, 0, 0]])
<< "multiclass_logreg_cv_mean," + CrossValidation.cross_val_mean(LogisticRegression.new(1, 100), softmax_x, softmax_y, StratifiedKFold.new(3)).to_s
<< "multiclass_center_log_loss," + Metrics.multiclass_log_loss(center_probs, [:a, :b, :c], softmax.classes).to_s

# Canonical Iris measurements (the first 20 rows of each target class),
# scaled by 10 to keep the fixture integer-exact. Stratified five-fold CV
# exercises real overlapping multiclass data rather than a synthetic-only
# separation.
iris_x = [[51, 35, 14, 2], [49, 30, 14, 2], [47, 32, 13, 2], [46, 31, 15, 2], [50, 36, 14, 2], [54, 39, 17, 4], [46, 34, 14, 3], [50, 34, 15, 2], [44, 29, 14, 2], [49, 31, 15, 1], [54, 37, 15, 2], [48, 34, 16, 2], [48, 30, 14, 1], [43, 30, 11, 1], [58, 40, 12, 2], [57, 44, 15, 4], [54, 39, 13, 4], [51, 35, 14, 3], [57, 38, 17, 3], [51, 38, 15, 3], [70, 32, 47, 14], [64, 32, 45, 15], [69, 31, 49, 15], [55, 23, 40, 13], [65, 28, 46, 15], [57, 28, 45, 13], [63, 33, 47, 16], [49, 24, 33, 10], [66, 29, 46, 13], [52, 27, 39, 14], [50, 20, 35, 10], [59, 30, 42, 15], [60, 22, 40, 10], [61, 29, 47, 14], [56, 29, 36, 13], [67, 31, 44, 14], [56, 30, 45, 15], [58, 27, 41, 10], [62, 22, 45, 15], [56, 25, 39, 11], [63, 33, 60, 25], [58, 27, 51, 19], [71, 30, 59, 21], [63, 29, 56, 18], [65, 30, 58, 22], [76, 30, 66, 21], [49, 25, 45, 17], [73, 29, 63, 18], [67, 25, 58, 18], [72, 36, 61, 25], [65, 32, 51, 20], [64, 27, 53, 19], [68, 30, 55, 21], [57, 25, 50, 20], [58, 28, 51, 24], [64, 32, 53, 23], [65, 30, 55, 18], [77, 38, 67, 22], [77, 26, 69, 23], [60, 22, 50, 15]]
iris_y = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]
iris_cv = StratifiedKFold.new(5)
iris_logreg = Pipeline.new([Scaler.new(:standard), LogisticRegression.new])
iris_knn = Pipeline.new([Scaler.new(:standard), KNNClassifier.new(3)])
<< "iris_logreg_cv_mean," + CrossValidation.cross_val_mean(iris_logreg, iris_x, iris_y, iris_cv).to_s
<< "iris_gaussian_nb_cv_mean," + CrossValidation.cross_val_mean(GaussianNB.new, iris_x, iris_y, iris_cv).to_s
<< "iris_knn_cv_mean," + CrossValidation.cross_val_mean(iris_knn, iris_x, iris_y, iris_cv).to_s

# Mixed numeric/categorical classification. Age repeats once per city and
# contains no class signal; city alone determines the label. This exercises
# DataFrame-preserving CV plus parallel scaling and one-hot encoding.
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
mixed_cv = StratifiedKFold.new(3)
numeric_only = Pipeline.new([
  ColumnTransformer.new([[:num, Scaler.new(:standard), [:age]]]),
  LogisticRegression.new(1, 300)
])
mixed_columns = Pipeline.new([
  ColumnTransformer.new([
    [:num, Scaler.new(:standard), [:age]],
    [:cat, Encoder.new(:one_hot), [:city]]
  ]),
  LogisticRegression.new(1, 300)
])
<< "mixed_numeric_only_cv_mean," + CrossValidation.cross_val_mean(numeric_only, mixed_x, mixed_y, mixed_cv).to_s
<< "mixed_column_transform_cv_mean," + CrossValidation.cross_val_mean(mixed_columns, mixed_x, mixed_y, mixed_cv).to_s
mixed_columns.fit(mixed_x, mixed_y)
mixed_importance = PermutationImportance.compute(
  mixed_columns, mixed_x, mixed_y, 20, 42
)
<< "mixed_permutation_age," + mixed_importance.importances_mean[0].to_s
<< "mixed_permutation_city," + mixed_importance.importances_mean[1].to_s

# KNN weighting parity. Uniform 3-NN lets two far class-b rows outvote the
# nearby class-a row at x=1; inverse Euclidean distance reverses that error.
# The probability and regression prediction are exact 12/19 and 31/19,
# distinguishing inverse distance from the old inverse-squared bug.
knn_train_x = [[0], [4], [5]]
knn_class_y = [:a, :b, :b]
knn_test_x = [[1], [9.to_f / 2.to_f]]
knn_test_y = [:a, :b]
knn_uniform = KNNClassifier.new(3, :uniform)
knn_uniform.fit(knn_train_x, knn_class_y)
knn_distance = KNNClassifier.new(3, :distance)
knn_distance.fit(knn_train_x, knn_class_y)
<< "knn_uniform_accuracy," + knn_uniform.score(knn_test_x, knn_test_y).to_s
<< "knn_distance_accuracy," + knn_distance.score(knn_test_x, knn_test_y).to_s
<< "knn_distance_class_a_probability," + knn_distance.predict_proba([[1]], :a)[0].to_s
knn_regression = KNeighborsRegressor.new(3, :distance)
knn_regression.fit(knn_train_x, [0, 4, 5])
<< "knn_regressor_distance_prediction," + knn_regression.predict([[1]])[0].to_s
knn_duplicate = KNeighborsRegressor.new(3, :distance)
knn_duplicate.fit([[0], [0], [10]], [2, 4, 10])
<< "knn_regressor_duplicate_prediction," + knn_duplicate.predict([[0]])[0].to_s

# Held-out probability calibration on the overlapping Versicolor/Virginica
# half of Iris. Train on the first 20 examples of each class (already in the
# fixture above), then test on the next 20. An unconstrained tree emits hard
# 0/1 leaf probabilities; cross-fitted sigmoid and isotonic calibration must
# sharply reduce held-out log loss, and isotonic must reduce Brier error too.
cal_train_x = []
cal_train_y = []
i = 20
while i < iris_x.size
  cal_train_x.push(iris_x[i])
  cal_train_y.push(iris_y[i])
  i += 1
cal_test_x = [[59, 32, 48, 18], [61, 28, 40, 13], [63, 25, 49, 15], [61, 28, 47, 12], [64, 29, 43, 13], [66, 30, 44, 14], [68, 28, 48, 14], [67, 30, 50, 17], [60, 29, 45, 15], [57, 26, 35, 10], [55, 24, 38, 11], [55, 24, 37, 10], [58, 27, 39, 12], [60, 27, 51, 16], [54, 30, 45, 15], [60, 34, 45, 16], [67, 31, 47, 15], [63, 23, 44, 13], [56, 30, 41, 13], [55, 25, 40, 13], [69, 32, 57, 23], [56, 28, 49, 20], [77, 28, 67, 20], [63, 27, 49, 18], [67, 33, 57, 21], [72, 32, 60, 18], [62, 28, 48, 18], [61, 30, 49, 18], [64, 28, 56, 21], [72, 30, 58, 16], [74, 28, 61, 19], [79, 38, 64, 20], [64, 28, 56, 22], [63, 28, 51, 15], [61, 26, 56, 14], [77, 30, 61, 23], [63, 34, 56, 24], [64, 31, 55, 18], [60, 30, 48, 18], [69, 31, 54, 21]]
cal_test_y = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
              2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]
raw_tree = DecisionTreeClassifier.new
raw_tree.fit(cal_train_x, cal_train_y)
sigmoid_tree = CalibratedClassifierCV.new(DecisionTreeClassifier.new, :sigmoid, 5)
sigmoid_tree.fit(cal_train_x, cal_train_y)
isotonic_tree = CalibratedClassifierCV.new(DecisionTreeClassifier.new, :isotonic, 5)
isotonic_tree.fit(cal_train_x, cal_train_y)
raw_tree_scores = raw_tree.predict_proba(cal_test_x, 2)
sigmoid_tree_scores = sigmoid_tree.predict_proba(cal_test_x, 2)
isotonic_tree_scores = isotonic_tree.predict_proba(cal_test_x, 2)
<< "iris_tree_raw_log_loss," + Metrics.log_loss(raw_tree_scores, cal_test_y, 2).to_s
<< "iris_tree_sigmoid_log_loss," + Metrics.log_loss(sigmoid_tree_scores, cal_test_y, 2).to_s
<< "iris_tree_isotonic_log_loss," + Metrics.log_loss(isotonic_tree_scores, cal_test_y, 2).to_s
<< "iris_tree_raw_brier," + Metrics.brier_score(raw_tree_scores, cal_test_y, 2).to_s
<< "iris_tree_isotonic_brier," + Metrics.brier_score(isotonic_tree_scores, cal_test_y, 2).to_s

cluster_x = [[0, 0], [0, 1], [1, 0], [1, 1],
             [10, 10], [10, 11], [11, 10], [11, 11]]
km = KMeans.new(2)
km.fit(cluster_x)
<< "two_box_silhouette," + Metrics.silhouette_score(cluster_x, km.labels).to_s
