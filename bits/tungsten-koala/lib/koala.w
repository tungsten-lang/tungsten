# Koala — data science and machine learning for Tungsten
# A friendlier pandas: Series, DataFrame, group_by, stats, metrics,
# and dense linear algebra (Vector / Matrix / LinAlg).

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

# The remaining modules under lib/ (tensor, resample, pipeline,
# transformer, estimator, scaler, encoder, imputer, splitter, index,
# sparse, gpu, device) are unported design drafts — they do not parse
# as Tungsten yet and are not loaded. Port one into the manifest above
# only after `bin/tungsten -c` passes on it AND it runs on both engines
# (spec coverage in spec/koala_spec.w or spec/linalg_spec.w).

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
