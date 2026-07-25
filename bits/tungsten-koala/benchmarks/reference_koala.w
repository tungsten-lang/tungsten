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

quad_x = [0 - 7, 0 - 6, 0 - 5, 0 - 4, 0 - 3, 0 - 2, 0 - 1, 0, 1, 2, 3, 4, 5, 6, 7]
quad_y = []
quad_x.each -> (v)
  quad_y.push(3 * v * v + 2 * v + 1)
quad = Pipeline.new([PolynomialFeatures.new(2), LinearRegression.new])
<< "quadratic_cv_mean," + CrossValidation.cross_val_mean(quad, quad_x, quad_y, 3).to_s

class_x = [[0, 0], [0, 1], [1, 0],
           [10, 10], [10, 11], [11, 10],
           [20, 0], [20, 1], [21, 0]]
class_y = [:a, :a, :a, :b, :b, :b, :c, :c, :c]
nb = GaussianNB.new
<< "multiclass_nb_cv_mean," + CrossValidation.cross_val_mean(nb, class_x, class_y, StratifiedKFold.new(3)).to_s

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

cluster_x = [[0, 0], [0, 1], [1, 0], [1, 1],
             [10, 10], [10, 11], [11, 10], [11, 11]]
km = KMeans.new(2)
km.fit(cluster_x)
<< "two_box_silhouette," + Metrics.silhouette_score(cluster_x, km.labels).to_s
