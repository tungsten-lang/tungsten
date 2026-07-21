# Koala — data science and machine learning for Tungsten
# A friendlier pandas: Series, DataFrame, group_by, stats, metrics,
# dense linear algebra (Vector / Matrix / LinAlg), ML preprocessing
# (Scaler / Encoder / Imputer / Splitter / Pipeline), estimation
# (LinearRegression — fit / predict / score with optional ridge alpha,
# alone or as a Pipeline tail; KNNClassifier — k-nearest-neighbors
# classification, the companion classifier to Metrics.accuracy / f1), and
# model evaluation (KFold / CrossValidation — k-fold cross-validation
# that re-fits an estimator on each fold and averages the held-out score).

use version
use stats
use series
use data_frame
use group_by
use metrics
use rolling
use join
use pivot
use vector
use matrix
use linalg
use linear_regression
use knn
use scaler
use encoder
use imputer
use splitter
use pipeline
use cross_validation

# The remaining modules under lib/ (tensor, resample, transformer,
# estimator, index, sparse, gpu, device) are unported design drafts —
# they do not parse as Tungsten yet and are not loaded. estimator.w's
# linear-regression payoff shipped as linear_regression.w above, and
# its k-NN sketch shipped as knn.w; the draft stays only as the sketch
# for the logistic / decision-tree follow-ups. Port a draft into the
# manifest above only after
# `bin/tungsten -c` passes on it AND it runs on both engines (spec
# coverage in spec/*.w).

+ Koala
  # Create a DataFrame from ordered [name, values] column pairs.
  #
  #     df = Koala.frame([
  #       [:name, ["Alice", "Bob"]],
  #       [:age,  [30, 25]]
  #     ])
  -> .frame(columns)
    DataFrame.new(columns)

  # Create a Series from values.
  -> .series(values, name = "series")
    Series.new(values, name)

  # Create a Vector from values.
  -> .vector(values)
    Vector.new(values)

  # Create a Matrix from nested row arrays.
  -> .matrix(rows)
    Matrix.new(rows)
