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

cluster_x = [[0, 0], [0, 1], [1, 0], [1, 1],
             [10, 10], [10, 11], [11, 10], [11, 11]]
km = KMeans.new(2)
km.fit(cluster_x)
<< "two_box_silhouette," + Metrics.silhouette_score(cluster_x, km.labels).to_s
