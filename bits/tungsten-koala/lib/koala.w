# Koala — data science and machine learning for Tungsten
# A friendlier pandas: Series, DataFrame, group_by, stats, and metrics.

use version
use stats
use series
use data_frame
use group_by
use metrics

# The remaining modules under lib/ (matrix, vector, tensor, linalg, join,
# pivot, rolling, resample, pipeline, transformer, estimator, scaler,
# encoder, imputer, splitter, index, sparse, gpu, device) are unported
# design drafts — they do not parse as Tungsten yet and are not loaded.
# Port one into the manifest above only after `bin/tungsten -c` passes on it.

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
