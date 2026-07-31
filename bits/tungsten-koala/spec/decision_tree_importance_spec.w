# Decision-tree and random-forest impurity-importance specs.
#
# Run from the repository root on both engines:
#   bin/tungsten bits/tungsten-koala/spec/decision_tree_importance_spec.w
#   bin/tungsten compile \
#     bits/tungsten-koala/spec/decision_tree_importance_spec.w \
#     --out /tmp/koala-decision-tree-importance-spec
#   /tmp/koala-decision-tree-importance-spec

use spec
use koala

-> importance_close(a, b)
  delta = a.to_f - b.to_f
  delta = 0.to_f - delta if delta < 0.to_f
  delta < 1.to_f / 1000000000.to_f

describe "DecisionTree feature importances" ->
  it "is nil before fit and zero for a classification stump" ->
    model = DecisionTreeClassifier.new(0)
    expect(model.feature_importances).to be_nil
    model.fit([[0, 1], [1, 0]], [:a, :b])
    values = model.feature_importances
    expect(values.size).to eq(2)
    expect(values.join(",")).to eq("0,0")

  it "assigns all importance to the only informative classifier feature" ->
    x = [[0, 9, 2], [1, 8, 2], [2, 7, 2],
         [8, 6, 2], [9, 5, 2], [10, 4, 2]]
    model = DecisionTreeClassifier.new
    model.fit(x, [:lo, :lo, :lo, :hi, :hi, :hi])
    values = model.feature_importances
    expect(values.size).to eq(3)
    expect(values[0]).to eq(1)
    expect(values[1]).to eq(0)
    expect(values[2]).to eq(0)

  it "uses weighted impurity decrease at every classifier node" ->
    # This explicit tree avoids depending on the grower's choice while
    # pinning the definition: f0 gets 10*0.2, f1 gets 4*0.5.
    leaf = { leaf: true }
    child = { leaf: false, feature: 1, gain: 0.5, weight: 4, left: leaf, right: leaf }
    root = { leaf: false, feature: 0, gain: 0.2, weight: 10, left: child, right: leaf }
    values = DecisionTree.feature_importances(root, 3)
    expect(importance_close(values[0], 0.5)).to be_true
    expect(importance_close(values[1], 0.5)).to be_true
    expect(values[2]).to eq(0)

  it "reports normalized MSE decrease for regression" ->
    x = [[0, 9], [1, 8], [2, 7], [8, 6], [9, 5], [10, 4]]
    model = DecisionTreeRegressor.new
    model.fit(x, [1, 1, 1, 9, 9, 9])
    values = model.feature_importances
    expect(values.size).to eq(2)
    expect(values[0]).to eq(1)
    expect(values[1]).to eq(0)
    expect(importance_close(values[0] + values[1], 1)).to be_true

  it "survives persistence because it is derived from the tree" ->
    model = DecisionTreeClassifier.new
    model.fit([[0, 9], [1, 8], [8, 7], [9, 6]], [:a, :a, :b, :b])
    again = DecisionTreeClassifier.load_state(model.to_state)
    expect(again.feature_importances.join(",")).to eq(model.feature_importances.join(","))

describe "RandomForest feature importances" ->
  it "is nil before fit and zero for an all-stump forest" ->
    model = RandomForestClassifier.new(3, :all, 0, 1, 7, :gini, false)
    expect(model.feature_importances).to be_nil
    model.fit([[0, 1], [1, 0]], [:a, :b])
    expect(model.feature_importances.join(",")).to eq("0,0")

  it "matches a single deterministic classification tree" ->
    x = [[0, 9, 3], [1, 8, 3], [2, 7, 3],
         [8, 6, 3], [9, 5, 3], [10, 4, 3]]
    y = [:lo, :lo, :lo, :hi, :hi, :hi]
    tree = DecisionTreeClassifier.new
    forest = RandomForestClassifier.new(1, :all, nil, 1, 11, :gini, false)
    tree.fit(x, y)
    forest.fit(x, y)
    expect(forest.feature_importances.join(",")).to eq(tree.feature_importances.join(","))

  it "normalizes the ensemble mean and exposes unused features as zero" ->
    x = [[0, 0, 5], [0, 1, 5], [1, 0, 5], [1, 1, 5],
         [8, 8, 5], [8, 9, 5], [9, 8, 5], [9, 9, 5]]
    y = [0, 0, 0, 0, 1, 1, 1, 1]
    model = RandomForestClassifier.new(7, :all, nil, 1, 23, :gini, true)
    model.fit(x, y)
    values = model.feature_importances
    expect(values.size).to eq(3)
    expect(importance_close(values[0] + values[1] + values[2], 1)).to be_true
    expect(values[2]).to eq(0)

  it "supports regression forests and persists without extra state" ->
    x = [[0, 9], [1, 8], [2, 7], [8, 6], [9, 5], [10, 4]]
    model = RandomForestRegressor.new(5, :all, nil, 1, 31, :mse, true)
    model.fit(x, [1, 1, 1, 9, 9, 9])
    values = model.feature_importances
    expect(importance_close(values[0] + values[1], 1)).to be_true
    again = RandomForestRegressor.load_state(model.to_state)
    expect(again.feature_importances.join(",")).to eq(values.join(","))
