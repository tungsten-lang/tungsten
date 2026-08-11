# Learned missing-value routing for trees and forests.
#
# Run from the repository root on both engines:
#   bin/tungsten bits/tungsten-koala/spec/decision_tree_missing_spec.w
#   bin/tungsten compile bits/tungsten-koala/spec/decision_tree_missing_spec.w \
#     --out /tmp/koala-decision-tree-missing-spec
#   /tmp/koala-decision-tree-missing-spec

use spec
use koala

-> tree_nan
  infinity = 1.to_f
  1100.times -> (i)
    infinity *= 2.to_f
  infinity - infinity

describe "DecisionTree learned missing routing" ->
  it "summarizes validated query batches for the numeric fast path" ->
    nan = tree_nan
    expect(DecisionTree.row_status([[0, 1], [2, 3]], true, 2)).to eq(0)
    expect(DecisionTree.row_status([[0, nil], [2, nan]], true, 2)).to eq(1)
    expect(DecisionTree.row_status([], true, 2)).to eq(0)
    expect(DecisionTree.row_status([[0]], true, 2)).to eq(-1)
    expect(DecisionTree.row_status([[0, "x"]], true, 2)).to eq(-1)

  it "sorts observed values first and keeps nil and NaN stable at the end" ->
    nan = tree_nan
    rows = [[nil], [2], [nan], [1], [2]]
    expect(DecisionTree.sorted_feature_indices(rows, 0).join(",")).to eq("3,1,4,0,2")
    expect(DecisionTree.missing?(nil)).to be_true
    expect(DecisionTree.missing?(nan)).to be_true
    expect(DecisionTree.usable_feature?(nan)).to be_true
    late_rows = [[2], [1], [2], [nil], [nan]]
    expect(DecisionTree.sorted_feature_indices(late_rows, 0).join(",")).to eq("1,0,2,3,4")

  it "learns missing-left for classification exactly like sklearn" ->
    nan = tree_nan
    x = [[0], [1], [8], [9], [nil], [nan]]
    model = DecisionTreeClassifier.new(1)
    model.fit(x, [0, 0, 1, 1, 0, 0])
    expect(model.tree[:threshold]).to eq(4.5)
    expect(model.tree[:missing_left]).to be_true
    expect(model.predict([[nil], [nan], [0], [9]]).join(",")).to eq("0,0,0,1")
    expect(model.score(x, [0, 0, 1, 1, 0, 0])).to eq(1)

  it "learns missing-right for classification exactly like sklearn" ->
    nan = tree_nan
    x = [[0], [1], [8], [9], [nil], [nan]]
    model = DecisionTreeClassifier.new(1)
    model.fit(x, [0, 0, 1, 1, 1, 1])
    expect(model.tree[:threshold]).to eq(4.5)
    expect(model.tree[:missing_left]).to be_false
    expect(model.predict([[nil], [nan], [0], [9]]).join(",")).to eq("1,1,0,1")

  it "matches weighted multiclass entropy missing routing from sklearn" ->
    x = [[0], [1], [2], [8], [9], [nil], [tree_nan]]
    y = [0, 1, 1, 2, 2, 0, 3]
    weights = [1, 2, 1, 3, 1, 2, 4]
    model = DecisionTreeClassifier.new(1, 2, 1, :entropy)
    model.fit(x, y, weights)
    expect(model.tree[:threshold]).to eq(0.5)
    expect(model.tree[:missing_left]).to be_true
    expect(model.tree[:gain] > 0.999999999.to_f).to be_true
    expect(model.predict([[nil], [tree_nan], [0], [9]]).join(",")).to eq("3,3,3,2")

  it "sends unseen missing values to the larger child, ties right" ->
    left = DecisionTreeClassifier.new(1)
    left.fit([[0], [1], [2], [8]], [0, 0, 0, 1])
    expect(left.tree[:missing_left]).to be_true
    expect(left.predict([[nil]])[0]).to eq(0)

    right = DecisionTreeClassifier.new(1)
    right.fit([[0], [8], [9], [10]], [0, 1, 1, 1])
    expect(right.tree[:missing_left]).to be_false
    expect(right.predict([[nil]])[0]).to eq(1)

    tied = DecisionTreeClassifier.new(1)
    tied.fit([[0], [1], [8], [9]], [0, 0, 1, 1])
    expect(tied.tree[:missing_left]).to be_false
    expect(tied.predict([[nil]])[0]).to eq(1)

  it "learns either direction for regression with nil and NaN" ->
    nan = tree_nan
    x = [[0], [1], [8], [9], [nil], [nan]]
    left = DecisionTreeRegressor.new(1)
    left.fit(x, [0, 0, 10, 10, 0, 0])
    expect(left.tree[:threshold]).to eq(4.5)
    expect(left.tree[:missing_left]).to be_true
    expect(left.predict([[nil], [nan]]).join(",")).to eq("0,0")

    right = DecisionTreeRegressor.new(1)
    right.fit(x, [0, 0, 10, 10, 10, 10])
    expect(right.tree[:missing_left]).to be_false
    expect(right.predict([[nil], [nan]]).join(",")).to eq("10,10")

  it "counts missing rows toward min_samples_leaf in their learned child" ->
    x = [[0], [1], [8], [9], [10], [nil], [nil]]
    model = DecisionTreeClassifier.new(1, 2, 3)
    model.fit(x, [0, 0, 1, 1, 1, 0, 0])
    expect(model.node_count).to eq(3)
    expect(model.tree[:missing_left]).to be_true
    expect(model.tree[:left][:n]).to eq(4)
    expect(model.tree[:right][:n]).to eq(3)

  it "keeps weighted missing routing equivalent to duplicated rows" ->
    x = [[0], [1], [8], [9], [nil]]
    y = [0, 0, 1, 1, 0]
    weighted = DecisionTreeClassifier.new(2)
    weighted.fit(x, y, [1, 1, 1, 1, 2])
    duplicated = DecisionTreeClassifier.new(2)
    duplicated.fit([[0], [1], [8], [9], [nil], [nil]], [0, 0, 1, 1, 0, 0])
    expect(weighted.tree[:missing_left]).to eq(duplicated.tree[:missing_left])
    expect(weighted.tree[:threshold]).to eq(duplicated.tree[:threshold])
    expect(weighted.predict([[nil], [0], [9]]).join(",")).to eq(duplicated.predict([[nil], [0], [9]]).join(","))

    weighted_reg = DecisionTreeRegressor.new(2)
    weighted_reg.fit(x, [0, 0, 10, 10, 0], [1, 1, 1, 1, 2])
    duplicated_reg = DecisionTreeRegressor.new(2)
    duplicated_reg.fit([[0], [1], [8], [9], [nil], [nil]], [0, 0, 10, 10, 0, 0])
    expect(weighted_reg.tree[:missing_left]).to eq(duplicated_reg.tree[:missing_left])
    expect(weighted_reg.predict([[nil], [0], [9]]).join(",")).to eq(duplicated_reg.predict([[nil], [0], [9]]).join(","))

  it "persists and prunes the learned direction without inference drift" ->
    x = [[0], [1], [8], [9], [nil], [nil]]
    model = DecisionTreeClassifier.new(nil, nil, nil, :gini, 0.001)
    model.fit(x, [0, 0, 1, 1, 0, 0])
    again = DecisionTreeClassifier.load_state(model.to_state)
    expect(again.tree[:missing_left]).to eq(model.tree[:missing_left])
    expect(again.predict([[nil], [0], [9]]).join(",")).to eq(model.predict([[nil], [0], [9]]).join(","))

  it "flows through deterministic classification and regression forests" ->
    nan = tree_nan
    x = [[0], [1], [8], [9], [nil], [nan]]
    clf = RandomForestClassifier.new(1, :all, 1, 1, 7, :gini, false)
    clf.fit(x, [0, 0, 1, 1, 0, 0])
    expect(clf.trees[0][:missing_left]).to be_true
    expect(clf.predict([[nil], [nan], [9]]).join(",")).to eq("0,0,1")

    reg = RandomForestRegressor.new(1, :all, 1, 1, 7, :mse, false)
    reg.fit(x, [0, 0, 10, 10, 10, 10])
    expect(reg.trees[0][:missing_left]).to be_false
    expect(reg.predict([[nil], [nan], [0]]).join(",")).to eq("10,10,0")

    queries = []
    40.times -> (i)
      cell = i % 10
      cell = nil if i % 7 == 0
      cell = nan if i % 11 == 0
      queries.push([cell])
    expected_probabilities = []
    expected_column = []
    expected_labels = []
    expected_means = []
    queries.each -> (row)
      probability = RandomForest.vote_row(clf.trees, row, clf.classes.size)
      expected_probabilities.push(probability)
      expected_column.push(probability[0])
      expected_labels.push(clf.classes[RandomForest.argmax(probability)])
      expected_means.push(RandomForest.mean_row(reg.trees, row))
    expect(clf.predict_proba(queries).to_s).to eq(expected_probabilities.to_s)
    expect(clf.predict_proba(queries, clf.classes[0]).to_s).to eq(expected_column.to_s)
    expect(clf.predict(queries).to_s).to eq(expected_labels.to_s)
    expect(reg.predict(queries).to_s).to eq(expected_means.to_s)

    numeric_queries = []
    40.times -> (i)
      numeric_queries.push([i % 10])
    numeric_probabilities = []
    numeric_column = []
    numeric_labels = []
    numeric_means = []
    numeric_queries.each -> (row)
      probability = RandomForest.vote_row(clf.trees, row, clf.classes.size)
      numeric_probabilities.push(probability)
      numeric_column.push(probability[0])
      numeric_labels.push(clf.classes[RandomForest.argmax(probability)])
      numeric_means.push(RandomForest.mean_row(reg.trees, row))
    expect(clf.predict_proba(numeric_queries).to_s).to eq(numeric_probabilities.to_s)
    expect(clf.predict_proba(numeric_queries, clf.classes[0]).to_s).to eq(numeric_column.to_s)
    expect(clf.predict(numeric_queries).to_s).to eq(numeric_labels.to_s)
    expect(reg.predict(numeric_queries).to_s).to eq(numeric_means.to_s)

  it "rejects nonnumeric and infinite cells while accepting missing cells" ->
    infinity = 1.to_f
    1100.times -> (i)
      infinity *= 2.to_f
    expect(DecisionTreeClassifier.new.fit([[nil], [1]], [0, 1]) != nil).to be_true
    expect(DecisionTreeClassifier.new.fit([["x"], [1]], [0, 1])).to be_nil
    expect(DecisionTreeClassifier.new.fit([[infinity], [1]], [0, 1])).to be_nil
    model = DecisionTreeClassifier.new
    model.fit([[0], [1]], [0, 1])
    expect(model.predict([["x"]])).to be_nil
    expect(model.predict([[infinity]])).to be_nil

  it "keeps numeric and missing flat prediction paths equivalent to descent" ->
    model = DecisionTreeClassifier.new(2)
    model.fit([[0], [1], [8], [9], [nil]], [0, 0, 1, 1, 0])
    numeric = []
    missing = []
    40.times -> (i)
      numeric.push([i % 10])
      cell = i % 10
      cell = nil if i % 7 == 0
      missing.push([cell])
    expect(DecisionTree.batch_predictions(model.tree, numeric, false).to_s).to eq(model.predict(numeric).to_s)
    expect(DecisionTree.batch_predictions(model.tree, missing, true).to_s).to eq(model.predict(missing).to_s)
    expected_probabilities = []
    expected_column = []
    missing.each -> (row)
      probability = DecisionTree.proba_of(DecisionTree.descend(model.tree, row))
      expected_probabilities.push(probability)
      expected_column.push(probability[1])
    expect(model.predict_proba(missing).to_s).to eq(expected_probabilities.to_s)
    expect(model.predict_proba(missing, 1).to_s).to eq(expected_column.to_s)

spec_summary
