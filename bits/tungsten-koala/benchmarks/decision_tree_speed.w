# Deterministic DecisionTree training/prediction benchmark.
#
# Compile and run from the repository root:
#   bin/tungsten compile bits/tungsten-koala/benchmarks/decision_tree_speed.w \
#     --out /tmp/koala-decision-tree-speed
#   /tmp/koala-decision-tree-speed
#
# This is a scaling probe, not a one-shot marketing number. The generated
# 1,200 x 12 classification table has repeatable nonlinear signal and enough
# distinct values to exercise the split-search hot path. Report node count and
# accuracy beside elapsed time so an accidentally trivial tree cannot look
# fast.

use koala

-> tree_benchmark_rows(n, width)
  rows = []
  labels = []
  i = 0
  while i < n
    row = []
    j = 0
    while j < width
      row.push((i * (37 + j * 2) + j * 101 + i * j * 3) % 1009)
      j += 1
    signal = row[0] + row[3] - row[5]
    label = 0
    label = 1 if signal > 450
    label = 2 if row[7] < 200 && row[1] > 600
    rows.push(row)
    labels.push(label)
    i += 1
  { rows: rows, labels: labels }

-> tree_benchmark_regression_targets(rows)
  targets = []
  rows.each -> (row)
    signal = (row[0] * 2 + row[3] - row[5]).to_f / 7.to_f
    targets.push(signal + (row[7] % 113).to_f)
  targets

fixture = tree_benchmark_rows(1200, 12)
x = fixture[:rows]
y = fixture[:labels]

started = ccall("__w_clock_ms")
model = nil
2.times -> (repeat)
  model = DecisionTreeClassifier.new(8, 2, 2, :gini)
  model.fit(x, y)
train_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
checksum = 0
250.times -> (repeat)
  preds = model.predict(x)
  preds.each -> (label)
    checksum += label
predict_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
leaf_index_checksum = 0
250.times -> (repeat)
  indices = model.leaf_indices(x)
  indices.each -> (index)
    leaf_index_checksum += index
leaf_index_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
last_probabilities = nil
250.times -> (repeat)
  last_probabilities = model.predict_proba(x)
predict_proba_ms = ccall("__w_clock_ms") - started
predict_proba_checksum = 0.to_f
last_probabilities.each -> (row)
  row.each_with_index -> (probability, class_index)
    predict_proba_checksum += probability * (class_index + 1).to_f

started = ccall("__w_clock_ms")
last_probability_column = nil
250.times -> (repeat)
  last_probability_column = model.predict_proba(x, 1)
predict_proba_column_ms = ccall("__w_clock_ms") - started
predict_proba_column_checksum = last_probability_column.sum

importance_checksum = 0.to_f
model.feature_importances.each_with_index -> (importance, feature)
  importance_checksum += importance * (feature + 1).to_f

<< "decision_tree_train_ms," + train_ms.to_s
<< "decision_tree_predict_ms," + predict_ms.to_s
<< "decision_tree_leaf_index_ms," + leaf_index_ms.to_s
<< "decision_tree_leaf_index_checksum," + leaf_index_checksum.to_s
<< "decision_tree_predict_proba_ms," + predict_proba_ms.to_s
<< "decision_tree_predict_proba_checksum," + predict_proba_checksum.to_s
<< "decision_tree_predict_proba_column_ms," + predict_proba_column_ms.to_s
<< "decision_tree_predict_proba_column_checksum," + predict_proba_column_checksum.to_s
<< "decision_tree_nodes," + model.node_count.to_s
<< "decision_tree_accuracy," + model.score(x, y).to_s
<< "decision_tree_checksum," + checksum.to_s
<< "decision_tree_importance_checksum," + importance_checksum.to_s

# Entropy has the same sorted sweep but maintains c*log(c) statistics rather
# than squared counts. Time it separately so a gini-only optimization cannot
# masquerade as a general classification-tree improvement.
started = ccall("__w_clock_ms")
entropy_model = nil
2.times -> (repeat)
  entropy_model = DecisionTreeClassifier.new(8, 2, 2, :entropy)
  entropy_model.fit(x, y)
entropy_train_ms = ccall("__w_clock_ms") - started
<< "decision_tree_entropy_train_ms," + entropy_train_ms.to_s
<< "decision_tree_entropy_nodes," + entropy_model.node_count.to_s
<< "decision_tree_entropy_accuracy," + entropy_model.score(x, y).to_s
<< "decision_tree_entropy_checksum," + entropy_model.predict(x).sum.to_s

# The same workload with a deterministic 7.7% of feature cells missing.
# Keep this separately timed: learned missing routing scores two assignments
# per threshold and should not hide its cost inside the ordinary-tree number.
missing_benchmark_x = []
x.each_with_index -> (row, i)
  missing_row = []
  row.each_with_index -> (value, j)
    cell = value
    cell = nil if (i * 17 + j * 31) % 13 == 0
    missing_row.push(cell)
  missing_benchmark_x.push(missing_row)

started = ccall("__w_clock_ms")
missing_benchmark_model = nil
2.times -> (repeat)
  missing_benchmark_model = DecisionTreeClassifier.new(8, 2, 2, :gini)
  missing_benchmark_model.fit(missing_benchmark_x, y)
missing_train_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
missing_checksum = 0
250.times -> (repeat)
  preds = missing_benchmark_model.predict(missing_benchmark_x)
  preds.each -> (label)
    missing_checksum += label
missing_predict_ms = ccall("__w_clock_ms") - started

<< "decision_tree_missing_train_ms," + missing_train_ms.to_s
<< "decision_tree_missing_predict_ms," + missing_predict_ms.to_s
<< "decision_tree_missing_nodes," + missing_benchmark_model.node_count.to_s
<< "decision_tree_missing_accuracy," + missing_benchmark_model.score(missing_benchmark_x, y).to_s
<< "decision_tree_missing_checksum," + missing_checksum.to_s

# A 50-tree forest on the same fixture. Random generators intentionally differ
# across implementations, so the Python harness gates tree count and training
# quality rather than requiring an impossible node-for-node identity.
started = ccall("__w_clock_ms")
forest_model = RandomForestClassifier.new(50, :sqrt, 8, 2, 42)
forest_model.fit(x, y)
forest_train_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
forest_checksum = 0
10.times -> (repeat)
  preds = forest_model.predict(x)
  preds.each -> (label)
    forest_checksum += label
forest_predict_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
forest_leaf_index_checksum = 0
10.times -> (repeat)
  matrix = forest_model.leaf_indices(x)
  matrix.each -> (row)
    row.each -> (index)
      forest_leaf_index_checksum += index
forest_leaf_index_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
forest_probabilities = nil
10.times -> (repeat)
  forest_probabilities = forest_model.predict_proba(x)
forest_predict_proba_ms = ccall("__w_clock_ms") - started
forest_predict_proba_checksum = 0.to_f
forest_probabilities.each -> (row)
  row.each_with_index -> (probability, class_index)
    forest_predict_proba_checksum += probability * (class_index + 1).to_f

started = ccall("__w_clock_ms")
forest_probability_column = nil
10.times -> (repeat)
  forest_probability_column = forest_model.predict_proba(x, 1)
forest_predict_proba_column_ms = ccall("__w_clock_ms") - started
forest_predict_proba_column_checksum = forest_probability_column.sum

forest_nodes = 0
forest_model.trees.each -> (tree)
  forest_nodes += DecisionTree.node_count(tree)
forest_holdout = tree_benchmark_rows(1600, 12)
forest_test_x = forest_holdout[:rows].slice(1200, 400)
forest_test_y = forest_holdout[:labels].slice(1200, 400)
<< "random_forest_train_ms," + forest_train_ms.to_s
<< "random_forest_predict_ms," + forest_predict_ms.to_s
<< "random_forest_leaf_index_ms," + forest_leaf_index_ms.to_s
<< "random_forest_leaf_index_checksum," + forest_leaf_index_checksum.to_s
<< "random_forest_predict_proba_ms," + forest_predict_proba_ms.to_s
<< "random_forest_predict_proba_checksum," + forest_predict_proba_checksum.to_s
<< "random_forest_predict_proba_column_ms," + forest_predict_proba_column_ms.to_s
<< "random_forest_predict_proba_column_checksum," + forest_predict_proba_column_checksum.to_s
<< "random_forest_tree_count," + forest_model.tree_count.to_s
<< "random_forest_nodes," + forest_nodes.to_s
<< "random_forest_accuracy," + forest_model.score(x, y).to_s
<< "random_forest_test_accuracy," + forest_model.score(forest_test_x, forest_test_y).to_s
<< "random_forest_checksum," + forest_checksum.to_s
<< "random_forest_oob_score," + forest_model.oob_score.to_s

# Same ensemble with a one-percent per-tree bootstrap-weight floor. This is a
# moderate speed/regularization lever, independent of max_samples.
started = ccall("__w_clock_ms")
forest_min_weight = RandomForestClassifier.new(
  50, :sqrt, 8, 2, 42, :gini, true, 0, 0, 2, nil, 1.to_f / 100.to_f
)
forest_min_weight.fit(x, y)
forest_min_weight_train_ms = ccall("__w_clock_ms") - started
forest_min_weight_nodes = 0
forest_min_weight.trees.each -> (tree)
  forest_min_weight_nodes += DecisionTree.node_count(tree)
<< "random_forest_min_weight_001_train_ms," + forest_min_weight_train_ms.to_s
<< "random_forest_min_weight_001_nodes," + forest_min_weight_nodes.to_s
<< "random_forest_min_weight_001_accuracy," + forest_min_weight.score(x, y).to_s
<< "random_forest_min_weight_001_test_accuracy," + forest_min_weight.score(forest_test_x, forest_test_y).to_s
<< "random_forest_min_weight_001_checksum," + forest_min_weight.predict(x).sum.to_s
<< "random_forest_min_weight_001_oob_score," + forest_min_weight.oob_score.to_s

# Same forest with half-size bootstrap draws. This is a training-speed /
# regularization tradeoff, so report held-out quality and node count beside
# time rather than treating a faster but collapsed ensemble as a win.
started = ccall("__w_clock_ms")
forest_half_sample = RandomForestClassifier.new(
  50, :sqrt, 8, 2, 42, :gini, true, 0, 0, 2, 600
)
forest_half_sample.fit(x, y)
forest_half_sample_train_ms = ccall("__w_clock_ms") - started
forest_half_sample_nodes = 0
forest_half_sample.trees.each -> (tree)
  forest_half_sample_nodes += DecisionTree.node_count(tree)
<< "random_forest_half_sample_train_ms," + forest_half_sample_train_ms.to_s
<< "random_forest_half_sample_nodes," + forest_half_sample_nodes.to_s
<< "random_forest_half_sample_accuracy," + forest_half_sample.score(x, y).to_s
<< "random_forest_half_sample_test_accuracy," + forest_half_sample.score(forest_test_x, forest_test_y).to_s
<< "random_forest_half_sample_checksum," + forest_half_sample.predict(x).sum.to_s
<< "random_forest_half_sample_oob_score," + forest_half_sample.oob_score.to_s

# A one-tree, unbootstrapped, all-feature forest is an ordinary tree. This
# isolates the forest's min_samples_split plumbing while retaining an exact
# sklearn CART reference rather than comparing unrelated forest RNG streams.
forest_min_split = RandomForestClassifier.new(
  1, :all, 8, 2, 0, :gini, false, 0, 0, 200
)
forest_min_split.fit(x, y)
<< "random_forest_min_split_nodes," + DecisionTree.node_count(forest_min_split.trees[0]).to_s
<< "random_forest_min_split_accuracy," + forest_min_split.score(x, y).to_s
<< "random_forest_min_split_checksum," + forest_min_split.predict(x).sum.to_s

# Regression-forest counterpart: same rows, deterministic nonlinear numeric
# target, same per-split sqrt feature budget and held-out tail.
regression_y = tree_benchmark_regression_targets(x)
started = ccall("__w_clock_ms")
regression_forest_model = RandomForestRegressor.new(50, :sqrt, 8, 2, 42)
regression_forest_model.fit(x, regression_y)
regression_forest_train_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
regression_forest_checksum = 0.to_f
10.times -> (repeat)
  predictions = regression_forest_model.predict(x)
  predictions.each -> (prediction)
    regression_forest_checksum += prediction
regression_forest_predict_ms = ccall("__w_clock_ms") - started

regression_forest_nodes = 0
regression_forest_model.trees.each -> (tree)
  regression_forest_nodes += DecisionTree.node_count(tree)
regression_test_y = tree_benchmark_regression_targets(forest_test_x)
<< "random_forest_regression_train_ms," + regression_forest_train_ms.to_s
<< "random_forest_regression_predict_ms," + regression_forest_predict_ms.to_s
<< "random_forest_regression_tree_count," + regression_forest_model.tree_count.to_s
<< "random_forest_regression_nodes," + regression_forest_nodes.to_s
<< "random_forest_regression_r2," + regression_forest_model.score(x, regression_y).to_s
<< "random_forest_regression_test_r2," + regression_forest_model.score(forest_test_x, regression_test_y).to_s
<< "random_forest_regression_checksum," + regression_forest_checksum.to_s
<< "random_forest_regression_oob_r2," + regression_forest_model.oob_score.to_s

# Untimed pruning parity probes. These alphas span light regularization,
# material simplification, and the root-only endpoint.
pruned_001 = DecisionTreeClassifier.new(8, 2, 2, :gini, 0.001)
pruned_001.fit(x, y)
pruned_005 = DecisionTreeClassifier.new(8, 2, 2, :gini, 0.005)
pruned_005.fit(x, y)
pruned_020 = DecisionTreeClassifier.new(8, 2, 2, :gini, 0.02)
pruned_020.fit(x, y)
pruned_100 = DecisionTreeClassifier.new(8, 2, 2, :gini, 0.1)
pruned_100.fit(x, y)

<< "decision_tree_ccp_001_nodes," + pruned_001.node_count.to_s
<< "decision_tree_ccp_001_leaves," + pruned_001.leaf_count.to_s
<< "decision_tree_ccp_001_accuracy," + pruned_001.score(x, y).to_s
<< "decision_tree_ccp_005_nodes," + pruned_005.node_count.to_s
<< "decision_tree_ccp_005_leaves," + pruned_005.leaf_count.to_s
<< "decision_tree_ccp_005_accuracy," + pruned_005.score(x, y).to_s
<< "decision_tree_ccp_020_nodes," + pruned_020.node_count.to_s
<< "decision_tree_ccp_020_leaves," + pruned_020.leaf_count.to_s
<< "decision_tree_ccp_020_accuracy," + pruned_020.score(x, y).to_s
<< "decision_tree_ccp_100_nodes," + pruned_100.node_count.to_s
<< "decision_tree_ccp_100_leaves," + pruned_100.leaf_count.to_s
<< "decision_tree_ccp_100_accuracy," + pruned_100.score(x, y).to_s

# Isolate weakest-link path construction from fitting: this is the algorithmic
# cost of cloning and repeatedly simplifying an already-grown tree.
started = ccall("__w_clock_ms")
path = nil
100.times -> (repeat)
  path = DecisionTree.pruning_path(model.tree)
ccp_path_ms = ccall("__w_clock_ms") - started
last = path[:ccp_alphas].size - 1
<< "decision_tree_ccp_path_ms," + ccp_path_ms.to_s
<< "decision_tree_ccp_path_size," + path[:ccp_alphas].size.to_s
<< "decision_tree_ccp_path_first_nonzero," + path[:ccp_alphas][1].to_s
<< "decision_tree_ccp_path_final_alpha," + path[:ccp_alphas][last].to_s
<< "decision_tree_ccp_path_final_impurity," + path[:impurities][last].to_s

# Weighted-leaf regularization: one larger timed fit plus exact weighted and
# missing-route fixtures whose thresholds are pinned against sklearn.
started = ccall("__w_clock_ms")
min_weight_model = nil
2.times -> (repeat)
  min_weight_model = DecisionTreeClassifier.new(
    8, 2, 2, :gini, 0, 0, 1.to_f / 20.to_f
  )
  min_weight_model.fit(x, y)
min_weight_train_ms = ccall("__w_clock_ms") - started
<< "decision_tree_min_weight_005_train_ms," + min_weight_train_ms.to_s
<< "decision_tree_min_weight_005_nodes," + min_weight_model.node_count.to_s
<< "decision_tree_min_weight_005_leaves," + min_weight_model.leaf_count.to_s
<< "decision_tree_min_weight_005_accuracy," + min_weight_model.score(x, y).to_s
<< "decision_tree_min_weight_005_checksum," + min_weight_model.predict(x).sum.to_s

weight_x = [[0], [1], [2], [3], [4], [5]]
weight_values = [8, 1, 1, 1, 1, 1]
weight_fraction = 3.to_f / 10.to_f
weighted_leaf_clf = DecisionTreeClassifier.new(
  3, 2, 1, :gini, 0, 0, weight_fraction
)
weighted_leaf_clf.fit(
  weight_x, [0, 0, 0, 1, 0, 1], weight_values
)
weighted_leaf_reg = DecisionTreeRegressor.new(
  3, 2, 1, :mse, 0, 0, weight_fraction
)
weighted_leaf_reg.fit(
  weight_x, [0, 0, 0, 10, 0, 10], weight_values
)
<< "decision_tree_min_weight_classifier_nodes," + weighted_leaf_clf.node_count.to_s
<< "decision_tree_min_weight_classifier_threshold," + weighted_leaf_clf.tree[:threshold].to_s
<< "decision_tree_min_weight_classifier_checksum," + weighted_leaf_clf.predict(weight_x).sum.to_s
<< "decision_tree_min_weight_regression_nodes," + weighted_leaf_reg.node_count.to_s
<< "decision_tree_min_weight_regression_threshold," + weighted_leaf_reg.tree[:threshold].to_s
<< "decision_tree_min_weight_regression_checksum," + weighted_leaf_reg.predict(weight_x).sum.to_s

min_weight_missing_x = [[0], [1], [8], [9], [nil], [nil]]
half_weight = 1.to_f / 2.to_f
min_weight_missing_left = DecisionTreeClassifier.new(
  1, 2, 1, :gini, 0, 0, half_weight
).fit(min_weight_missing_x, [0, 0, 1, 1, 0, 0])
min_weight_missing_right = DecisionTreeClassifier.new(
  1, 2, 1, :gini, 0, 0, half_weight
).fit(min_weight_missing_x, [0, 0, 1, 1, 1, 1])
<< "decision_tree_min_weight_missing_left_threshold," + min_weight_missing_left.tree[:threshold].to_s
<< "decision_tree_min_weight_missing_left_flag," + (min_weight_missing_left.tree[:missing_left] ? 1 : 0).to_s
<< "decision_tree_min_weight_missing_left_checksum," + min_weight_missing_left.predict(min_weight_missing_x).sum.to_s
<< "decision_tree_min_weight_missing_right_threshold," + min_weight_missing_right.tree[:threshold].to_s
<< "decision_tree_min_weight_missing_right_flag," + (min_weight_missing_right.tree[:missing_left] ? 1 : 0).to_s
<< "decision_tree_min_weight_missing_right_checksum," + min_weight_missing_right.predict(min_weight_missing_x).sum.to_s

# Exact preorder leaf-ID parity fixture. Its five nodes are root 0, left leaf
# 1, right split 2, then leaves 3 and 4.
leaf_index_x = [[0], [1], [2], [3], [4], [5]]
leaf_index_classifier = DecisionTreeClassifier.new.fit(
  leaf_index_x, [0, 0, 1, 1, 2, 2]
)
leaf_index_regressor = DecisionTreeRegressor.new.fit(
  leaf_index_x, [0, 0, 10, 10, 20, 20]
)
leaf_index_missing = DecisionTreeClassifier.new.fit(
  [[0], [1], [8], [9], [nil], [nil]], [0, 0, 1, 1, 0, 0]
)
leaf_index_forest = RandomForestClassifier.new(
  1, :all, nil, 1, 0, :gini, false
).fit(leaf_index_x, [0, 0, 1, 1, 2, 2])
leaf_index_forest_checksum = 0
leaf_index_forest.leaf_indices(leaf_index_x).each -> (row)
  leaf_index_forest_checksum += row.sum
<< "decision_tree_leaf_index_classifier_checksum," + leaf_index_classifier.leaf_indices(leaf_index_x).sum.to_s
<< "decision_tree_leaf_index_regression_checksum," + leaf_index_regressor.leaf_indices(leaf_index_x).sum.to_s
<< "decision_tree_leaf_index_missing_checksum," + leaf_index_missing.leaf_indices([[0], [1], [8], [9], [nil], [nil]]).sum.to_s
<< "random_forest_leaf_index_exact_checksum," + leaf_index_forest_checksum.to_s

# Untimed pre-pruning parity probes. Unlike ccp_alpha these floors reject a
# weak split before its children are grown, using the root-weighted decrease.
gain_001 = DecisionTreeClassifier.new(8, 2, 2, :gini, 0, 0.001)
gain_001.fit(x, y)
started = ccall("__w_clock_ms")
gain_005 = nil
2.times -> (repeat)
  gain_005 = DecisionTreeClassifier.new(8, 2, 2, :gini, 0, 0.005)
  gain_005.fit(x, y)
min_gain_train_ms = ccall("__w_clock_ms") - started
gain_020 = DecisionTreeClassifier.new(8, 2, 2, :gini, 0, 0.02)
gain_020.fit(x, y)

<< "decision_tree_min_gain_005_train_ms," + min_gain_train_ms.to_s
<< "decision_tree_min_gain_001_nodes," + gain_001.node_count.to_s
<< "decision_tree_min_gain_001_leaves," + gain_001.leaf_count.to_s
<< "decision_tree_min_gain_001_accuracy," + gain_001.score(x, y).to_s
<< "decision_tree_min_gain_005_nodes," + gain_005.node_count.to_s
<< "decision_tree_min_gain_005_leaves," + gain_005.leaf_count.to_s
<< "decision_tree_min_gain_005_accuracy," + gain_005.score(x, y).to_s
<< "decision_tree_min_gain_020_nodes," + gain_020.node_count.to_s
<< "decision_tree_min_gain_020_leaves," + gain_020.leaf_count.to_s
<< "decision_tree_min_gain_020_accuracy," + gain_020.score(x, y).to_s

gain_regression_x = [[0], [1], [2], [3]]
gain_regression_y = [0, 2, 4, 6]
gain_regression_exact = DecisionTreeRegressor.new(nil, nil, nil, :mse, 0, 4)
gain_regression_exact.fit(gain_regression_x, gain_regression_y)
gain_regression_blocked = DecisionTreeRegressor.new(
  nil, nil, nil, :mse, 0, 4.to_f + 1.to_f / 10000.to_f
)
gain_regression_blocked.fit(gain_regression_x, gain_regression_y)
<< "decision_tree_min_gain_regression_exact_nodes," + gain_regression_exact.node_count.to_s
<< "decision_tree_min_gain_regression_exact_checksum," + gain_regression_exact.predict(gain_regression_x).sum.to_s
<< "decision_tree_min_gain_regression_blocked_nodes," + gain_regression_blocked.node_count.to_s
<< "decision_tree_min_gain_regression_blocked_checksum," + gain_regression_blocked.predict(gain_regression_x).sum.to_s

# Untimed missing-value parity probes. Both nil and IEEE NaN are missing in
# Koala; scikit-learn's corresponding input is NaN. The fixtures force each
# learned direction plus the larger-child / tie-right inference fallback when
# a fit contains no missing rows.
missing_x = [[0], [1], [8], [9], [nil], [nil]]
missing_left = DecisionTreeClassifier.new.fit(missing_x, [0, 0, 1, 1, 0, 0])
missing_right = DecisionTreeClassifier.new.fit(missing_x, [0, 0, 1, 1, 1, 1])
missing_regression = DecisionTreeRegressor.new.fit(missing_x, [0, 0, 10, 10, 0, 0])

infinity = 1.to_f
1100.times -> (i)
  infinity *= 2.to_f
nan = infinity - infinity
missing_queries = [[nil], [nan], [0], [9]]

<< "decision_tree_missing_left_threshold," + missing_left.tree[:threshold].to_s
<< "decision_tree_missing_left_flag," + (missing_left.tree[:missing_left] ? 1 : 0).to_s
<< "decision_tree_missing_left_checksum," + missing_left.predict(missing_queries).sum.to_s
<< "decision_tree_missing_right_threshold," + missing_right.tree[:threshold].to_s
<< "decision_tree_missing_right_flag," + (missing_right.tree[:missing_left] ? 1 : 0).to_s
<< "decision_tree_missing_right_checksum," + missing_right.predict(missing_queries).sum.to_s
<< "decision_tree_missing_regression_threshold," + missing_regression.tree[:threshold].to_s
<< "decision_tree_missing_regression_flag," + (missing_regression.tree[:missing_left] ? 1 : 0).to_s
<< "decision_tree_missing_regression_checksum," + missing_regression.predict(missing_queries).sum.to_s

fallback_left = DecisionTreeClassifier.new.fit([[0], [1], [9], [10]], [0, 0, 0, 1])
fallback_right = DecisionTreeClassifier.new.fit([[0], [1], [9], [10]], [0, 1, 1, 1])
fallback_tie = DecisionTreeClassifier.new.fit([[0], [1], [8], [9]], [0, 0, 1, 1])
<< "decision_tree_missing_fallback_left_flag," + (fallback_left.tree[:missing_left] ? 1 : 0).to_s
<< "decision_tree_missing_fallback_left_prediction," + fallback_left.predict([[nil]])[0].to_s
<< "decision_tree_missing_fallback_right_flag," + (fallback_right.tree[:missing_left] ? 1 : 0).to_s
<< "decision_tree_missing_fallback_right_prediction," + fallback_right.predict([[nil]])[0].to_s
<< "decision_tree_missing_fallback_tie_flag," + (fallback_tie.tree[:missing_left] ? 1 : 0).to_s
<< "decision_tree_missing_fallback_tie_prediction," + fallback_tie.predict([[nil]])[0].to_s

# Prediction-cost decomposition. These use the already fitted ordinary tree
# after every headline timing, so diagnostics cannot perturb the compared
# train/predict/forest numbers above. The checksums keep every result live.
started = ccall("__w_clock_ms")
validation_checksum = 0
250.times -> (repeat)
  validated = model.query_rows(x)
  validation_checksum += validated.size
validation_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
projection_checksum = 0
250.times -> (repeat)
  program = DecisionTree.prediction_program(model.tree)
  projection_checksum += program[0].size
projection_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
descent_checksum = 0
250.times -> (repeat)
  descent_checksum += DecisionTree.batch_predictions(model.tree, x, false).sum
descent_ms = ccall("__w_clock_ms") - started

<< "decision_tree_validation_ms," + validation_ms.to_s
<< "decision_tree_validation_checksum," + validation_checksum.to_s
<< "decision_tree_projection_ms," + projection_ms.to_s
<< "decision_tree_projection_checksum," + projection_checksum.to_s
<< "decision_tree_descent_ms," + descent_ms.to_s
<< "decision_tree_descent_checksum," + descent_checksum.to_s
