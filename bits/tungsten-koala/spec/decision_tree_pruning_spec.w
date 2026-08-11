# Split-time impurity regularization and minimal cost-complexity pruning specs
# for trees and forests.
#
# Run from the repository root on both engines:
#   bin/tungsten bits/tungsten-koala/spec/decision_tree_pruning_spec.w
#   bin/tungsten compile bits/tungsten-koala/spec/decision_tree_pruning_spec.w \
#     --out /tmp/koala-decision-tree-pruning-spec
#   /tmp/koala-decision-tree-pruning-spec

use spec
use koala

-> pruning_close(left, right)
  delta = left.to_f - right.to_f
  delta = 0.to_f - delta if delta < 0.to_f
  delta < 1.to_f / 1000000000000.to_f

+ PruningFx
  -> .leaf(weight, impurity, prediction)
    { leaf: true, feature: nil, threshold: nil, gain: nil,
      left: nil, right: nil, n: weight, weight: weight, depth: 0,
      impurity: impurity, counts: nil, prediction: prediction }

  # Root leaf risk is 10*0.5 = 5. The left branch's leaf risk is 4*0.5 = 2;
  # its two children are pure, so its effective alpha is 2/10 = 0.2.
  # Once that branch collapses, the root's effective alpha is
  # (5 - 2)/(2 - 1)/10 = 0.3.
  -> .known_tree
    a = PruningFx.leaf(2, 0, 0)
    b = PruningFx.leaf(2, 0, 1)
    c = PruningFx.leaf(6, 0, 1)
    left = { leaf: false, feature: 1, threshold: 0.5, gain: 0.5,
             left: a, right: b, n: 4, weight: 4, depth: 1,
             impurity: 0.5, counts: nil, prediction: 0 }
    { leaf: false, feature: 0, threshold: 0.5, gain: 0.3,
      left: left, right: c, n: 10, weight: 10, depth: 0,
      impurity: 0.5, counts: nil, prediction: 1 }

  -> .classification
    x = [[0, 0], [0, 1], [1, 0], [1, 1],
         [2, 0], [2, 1], [3, 0], [3, 1],
         [4, 0], [4, 1], [5, 0], [5, 1]]
    y = [:a, :a, :a, :b, :a, :b, :b, :a, :b, :b, :b, :a]
    { x: x, y: y }

  -> .regression
    x = [[0, 0], [0, 1], [1, 0], [1, 1],
         [2, 0], [2, 1], [3, 0], [3, 1]]
    y = [0, 0, 1, 2, 8, 9, 10, 12]
    { x: x, y: y }

  -> .same_tree?(left, right)
    ok = left[:leaf] == right[:leaf]
    if ok && left[:leaf]
      ok = left[:prediction] == right[:prediction]
    if ok && !left[:leaf]
      ok = left[:feature] == right[:feature]
      ok = left[:threshold] == right[:threshold] if ok
      ok = PruningFx.same_tree?(left[:left], right[:left]) if ok
      ok = PruningFx.same_tree?(left[:right], right[:right]) if ok
    ok

describe "DecisionTree minimal cost-complexity pruning" ->
  it "requires the sklearn root-weighted minimum impurity decrease" ->
    x = [[0], [1], [2], [3]]
    y = [0, 0, 1, 1]
    half = 1.to_f / 2.to_f
    exact = DecisionTreeClassifier.new(nil, nil, nil, :gini, 0, half)
    blocked = DecisionTreeClassifier.new(
      nil, nil, nil, :gini, 0, half + 1.to_f / 1000.to_f
    )
    exact.fit(x, y)
    blocked.fit(x, y)
    expect(exact.node_count).to eq(3)
    expect(blocked.node_count).to eq(1)

    # XOR's root gain is zero. The compatibility default still grows it,
    # while any positive floor prevents speculative zero-gain structure.
    xor_x = [[0, 0], [0, 1], [1, 0], [1, 1]]
    xor_y = [0, 1, 1, 0]
    expect(DecisionTreeClassifier.new.fit(xor_x, xor_y).node_count).to eq(7)
    floor = DecisionTreeClassifier.new(
      nil, nil, nil, :gini, 0, 1.to_f / 1000000.to_f
    )
    floor.fit(xor_x, xor_y)
    expect(floor.node_count).to eq(1)

  it "applies the same minimum to regression and sample weights" ->
    x = [[0], [1], [2], [3]]
    y = [0, 2, 4, 6]
    exact = DecisionTreeRegressor.new(nil, nil, nil, :mse, 0, 4)
    blocked = DecisionTreeRegressor.new(nil, nil, nil, :mse, 0, 4.001)
    exact.fit(x, y)
    blocked.fit(x, y)
    expect(exact.node_count).to eq(3)
    expect(blocked.node_count).to eq(1)

    fx = PruningFx.classification
    min_gain = 1.to_f / 100.to_f
    weighted = DecisionTreeClassifier.new(
      nil, nil, nil, :gini, 0, min_gain
    )
    duplicated = DecisionTreeClassifier.new(
      nil, nil, nil, :gini, 0, min_gain
    )
    weighted.fit(fx[:x], fx[:y], [2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
    dx = [fx[:x][0]]
    dy = [fx[:y][0]]
    fx[:x].each_with_index -> (row, i)
      dx.push(row)
      dy.push(fx[:y][i])
    duplicated.fit(dx, dy)
    expect(PruningFx.same_tree?(weighted.tree, duplicated.tree)).to be_true

  it "uses root-normalized weakest-link alpha exactly" ->
    below = PruningFx.known_tree
    DecisionTree.prune(below, 0.199)
    expect(DecisionTree.node_count(below)).to eq(5)

    branch = PruningFx.known_tree
    DecisionTree.prune(branch, 0.2)
    expect(DecisionTree.node_count(branch)).to eq(3)
    expect(branch[:left][:leaf]).to be_true
    expect(branch[:leaf]).to be_false

    root = PruningFx.known_tree
    DecisionTree.prune(root, 0.3)
    expect(DecisionTree.node_count(root)).to eq(1)
    expect(root[:prediction]).to eq(1)

  it "makes alpha zero an exact no-pruning compatibility path" ->
    tree = PruningFx.known_tree
    DecisionTree.prune(tree, 0)
    expect(DecisionTree.node_count(tree)).to eq(5)

  it "reports the exact weakest-link path without mutating its source" ->
    tree = PruningFx.known_tree
    path = DecisionTree.pruning_path(tree)
    expect(path[:ccp_alphas].size).to eq(3)
    expect(pruning_close(path[:ccp_alphas][1], 0.2)).to be_true
    expect(pruning_close(path[:ccp_alphas][2], 0.3)).to be_true
    expect(pruning_close(path[:impurities][0], 0)).to be_true
    expect(pruning_close(path[:impurities][1], 0.2)).to be_true
    expect(pruning_close(path[:impurities][2], 0.5)).to be_true
    expect(DecisionTree.node_count(tree)).to eq(5)

  it "monotonically simplifies a fitted classifier" ->
    fx = PruningFx.classification
    full = DecisionTreeClassifier.new
    light = DecisionTreeClassifier.new(nil, nil, nil, :gini, 0.01)
    heavy = DecisionTreeClassifier.new(nil, nil, nil, :gini, 1)
    full.fit(fx[:x], fx[:y])
    light.fit(fx[:x], fx[:y])
    heavy.fit(fx[:x], fx[:y])
    expect(light.node_count <= full.node_count).to be_true
    expect(light.leaf_count <= full.leaf_count).to be_true
    expect(heavy.node_count).to eq(1)
    expect(heavy.leaf_count).to eq(1)

  it "supports regression, weights, and row-duplication equivalence" ->
    fx = PruningFx.regression
    weighted = DecisionTreeRegressor.new(nil, nil, nil, :mse, 0.01)
    duplicated = DecisionTreeRegressor.new(nil, nil, nil, :mse, 0.01)
    weighted.fit(fx[:x], fx[:y], [2, 1, 1, 1, 1, 1, 1, 1])
    dx = [fx[:x][0]]
    dy = [fx[:y][0]]
    fx[:x].each_with_index -> (row, i)
      if i == 0
        dx.push(row)
        dy.push(fx[:y][i])
      else
        dx.push(row)
        dy.push(fx[:y][i])
    duplicated.fit(dx, dy)
    expect(PruningFx.same_tree?(weighted.tree, duplicated.tree)).to be_true
    expect(weighted.predict(fx[:x]).join(",")).to eq(duplicated.predict(fx[:x]).join(","))

  it "round-trips params and persistence and rejects negative regularization" ->
    model = DecisionTreeClassifier.new(4, 3, 2, :entropy, 0.02, 0.003)
    expect(model.params[:ccp_alpha]).to eq(0.02)
    expect(model.params[:min_impurity_decrease]).to eq(~0.003)
    expect(pruning_close(model.with_params({ ccp_alpha: 0.1 }).ccp_alpha, 0.1)).to be_true
    expect(pruning_close(model.with_params({ min_impurity_decrease: 0.2 }).min_impurity_decrease, 0.2)).to be_true
    fx = PruningFx.classification
    model.fit(fx[:x], fx[:y])
    again = DecisionTreeClassifier.load_state(model.to_state)
    expect(pruning_close(again.ccp_alpha, 0.02)).to be_true
    expect(again.min_impurity_decrease).to eq(~0.003)
    expect(again.tree_lines.join("|")).to eq(model.tree_lines.join("|"))
    expect(DecisionTreeClassifier.new(nil, nil, nil, :gini, 0 - 1).fit(fx[:x], fx[:y])).to be_nil
    expect(DecisionTreeRegressor.new(nil, nil, nil, :mse, 0 - 1).fit([[0], [1]], [0, 1])).to be_nil
    expect(DecisionTreeClassifier.new(nil, nil, nil, :gini, 0, 0 - 1).fit(fx[:x], fx[:y])).to be_nil
    expect(DecisionTreeRegressor.new(nil, nil, nil, :mse, 0, 0 - 1).fit([[0], [1]], [0, 1])).to be_nil

  it "grows monotone classifier and regressor paths without fitting self" ->
    clf_fx = PruningFx.classification
    clf = DecisionTreeClassifier.new
    path = clf.cost_complexity_pruning_path(clf_fx[:x], clf_fx[:y])
    expect(clf.fitted?).to be_false
    expect(path[:ccp_alphas].size).to eq(path[:impurities].size)
    expect(path[:ccp_alphas][0]).to eq(0)
    i = 1
    while i < path[:ccp_alphas].size
      expect(path[:ccp_alphas][i] >= path[:ccp_alphas][i - 1]).to be_true
      expect(path[:impurities][i] >= path[:impurities][i - 1]).to be_true
      i += 1

    reg_fx = PruningFx.regression
    reg = DecisionTreeRegressor.new
    rpath = reg.cost_complexity_pruning_path(reg_fx[:x], reg_fx[:y])
    expect(reg.fitted?).to be_false
    expect(rpath[:ccp_alphas].size).to eq(rpath[:impurities].size)
    expect(reg.cost_complexity_pruning_path([], [])).to be_nil

describe "DecisionTree minimum weighted leaf mass" ->
  it "matches sklearn's root-weight fraction for classification and regression" ->
    x = [[0], [1], [2], [3], [4], [5]]
    weights = [8, 1, 1, 1, 1, 1]
    fraction = 3.to_f / 10.to_f

    clf = DecisionTreeClassifier.new(3, 2, 1, :gini, 0, 0, fraction)
    clf.fit(x, [0, 0, 0, 1, 0, 1], weights)
    expect(clf.node_count).to eq(3)
    expect(clf.tree[:threshold]).to eq(1.5)
    expect(clf.predict(x).join(",")).to eq("0,0,0,0,0,0")

    reg = DecisionTreeRegressor.new(3, 2, 1, :mse, 0, 0, fraction)
    reg.fit(x, [0, 0, 0, 10, 0, 10], weights)
    expect(reg.node_count).to eq(3)
    expect(reg.tree[:threshold]).to eq(1.5)
    expect(reg.predict(x).join(",")).to eq("0,0,5,5,5,5")

  it "counts learned missing assignments toward the weighted floor" ->
    x = [[0], [1], [8], [9], [nil], [nil]]
    fraction = 1.to_f / 2.to_f
    left = DecisionTreeClassifier.new(1, 2, 1, :gini, 0, 0, fraction)
    right = DecisionTreeClassifier.new(1, 2, 1, :gini, 0, 0, fraction)
    left.fit(x, [0, 0, 1, 1, 0, 0])
    right.fit(x, [0, 0, 1, 1, 1, 1])
    expect(left.tree[:threshold]).to eq(0.5)
    expect(left.tree[:missing_left]).to be_true
    expect(right.tree[:threshold]).to eq(8.5)
    expect(right.tree[:missing_left]).to be_false
    expect(left.tree[:left][:weight]).to eq(3)
    expect(left.tree[:right][:weight]).to eq(3)
    expect(right.tree[:left][:weight]).to eq(3)
    expect(right.tree[:right][:weight]).to eq(3)

  it "keeps integer sample weights equivalent to duplicated rows" ->
    x = [[0], [1], [2], [3], [4], [5]]
    y = [0, 0, 0, 1, 0, 1]
    weights = [8, 1, 1, 1, 1, 1]
    dx = []
    dy = []
    8.times -> (i)
      dx.push(x[0])
      dy.push(y[0])
    i = 1
    while i < x.size
      dx.push(x[i])
      dy.push(y[i])
      i += 1
    fraction = 3.to_f / 10.to_f
    weighted = DecisionTreeClassifier.new(
      3, 2, 1, :gini, 0, 0, fraction
    ).fit(x, y, weights)
    duplicated = DecisionTreeClassifier.new(
      3, 2, 1, :gini, 0, 0, fraction
    ).fit(dx, dy)
    expect(PruningFx.same_tree?(weighted.tree, duplicated.tree)).to be_true

  it "round-trips the knob and rejects fractions outside zero through one half" ->
    fraction = 3.to_f / 10.to_f
    model = DecisionTreeClassifier.new(4, 3, 2, :entropy, 0.02, 0.003, fraction)
    expect(model.params[:min_weight_fraction_leaf]).to eq(fraction)
    expect(model.with_params({
      min_weight_fraction_leaf: 1.to_f / 4.to_f
    }).min_weight_fraction_leaf).to eq(1.to_f / 4.to_f)
    model.fit([[0], [1], [2], [3]], [0, 0, 1, 1])
    again = DecisionTreeClassifier.load_state(model.to_state)
    expect(again.min_weight_fraction_leaf).to eq(fraction)
    expect(again.tree_lines.join("|")).to eq(model.tree_lines.join("|"))

    bad_low = DecisionTreeClassifier.new(
      nil, nil, nil, :gini, 0, 0, 0.to_f - 1.to_f / 100.to_f
    )
    bad_high = DecisionTreeRegressor.new(
      nil, nil, nil, :mse, 0, 0, 0.5001
    )
    expect(bad_low.fit([[0], [1]], [0, 1])).to be_nil
    expect(bad_high.fit([[0], [1]], [0, 1])).to be_nil

describe "RandomForest minimal cost-complexity pruning" ->
  it "keeps split-time regularization identical to a one-tree fit" ->
    fx = PruningFx.classification
    tree = DecisionTreeClassifier.new(nil, nil, nil, :gini, 0, 0.02)
    forest = RandomForestClassifier.new(
      1, :all, nil, 1, 7, :gini, false, 0, 0.02
    )
    tree.fit(fx[:x], fx[:y])
    forest.fit(fx[:x], fx[:y])
    lines = DecisionTree.render(forest.trees[0], "", [])
    expect(lines.join("|")).to eq(tree.tree_lines.join("|"))
    again = RandomForestClassifier.load_state(forest.to_state)
    expect(again.min_impurity_decrease).to eq(0.02)
    expect(again.params[:min_impurity_decrease]).to eq(0.02)

  it "keeps a deterministic one-tree forest identical to its tree" ->
    fx = PruningFx.classification
    tree = DecisionTreeClassifier.new(nil, nil, nil, :gini, 0.01)
    forest = RandomForestClassifier.new(1, :all, nil, 1, 7, :gini, false, 0.01)
    tree.fit(fx[:x], fx[:y])
    forest.fit(fx[:x], fx[:y])
    lines = DecisionTree.render(forest.trees[0], "", [])
    expect(lines.join("|")).to eq(tree.tree_lines.join("|"))

  it "prunes every classifier and regressor tree and persists the knob" ->
    clf_fx = PruningFx.classification
    clf = RandomForestClassifier.new(3, :all, nil, 1, 7, :gini, false, 1)
    clf.fit(clf_fx[:x], clf_fx[:y])
    clf.trees.each -> (tree)
      expect(DecisionTree.node_count(tree)).to eq(1)
    expect(clf.feature_importances.join(",")).to eq("0,0")

    reg_fx = PruningFx.regression
    reg = RandomForestRegressor.new(3, :all, nil, 1, 11, :mse, false, 100)
    reg.fit(reg_fx[:x], reg_fx[:y])
    reg.trees.each -> (tree)
      expect(DecisionTree.node_count(tree)).to eq(1)
    again = RandomForestRegressor.load_state(reg.to_state)
    expect(again.ccp_alpha).to eq(100)
    expect(again.params[:ccp_alpha]).to eq(100)

  it "rejects negative alpha for either forest kind" ->
    fx = PruningFx.classification
    bad = RandomForestClassifier.new(2, :all, nil, 1, 3, :gini, false, 0 - 1)
    expect(bad.fit(fx[:x], fx[:y])).to be_nil
    reg = RandomForestRegressor.new(2, :all, nil, 1, 3, :mse, false, 0 - 1)
    expect(reg.fit([[0], [1]], [0, 1])).to be_nil
    bad_gain = RandomForestClassifier.new(
      2, :all, nil, 1, 3, :gini, false, 0, 0 - 1
    )
    expect(bad_gain.fit(fx[:x], fx[:y])).to be_nil
    bad_reg_gain = RandomForestRegressor.new(
      2, :all, nil, 1, 3, :mse, false, 0, 0 - 1
    )
    expect(bad_reg_gain.fit([[0], [1]], [0, 1])).to be_nil

spec_summary
