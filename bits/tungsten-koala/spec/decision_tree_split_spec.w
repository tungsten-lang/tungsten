# Decision-tree sorted split-sweep specs.
#
# Run from the repository root on both engines:
#   bin/tungsten bits/tungsten-koala/spec/decision_tree_split_spec.w
#   bin/tungsten compile bits/tungsten-koala/spec/decision_tree_split_spec.w \
#     --out /tmp/koala-decision-tree-split-spec
#   /tmp/koala-decision-tree-split-spec

use spec
use koala
use support

+ TreeSplitReference
  # The pre-optimization candidate search, retained only as a small-fixture
  # oracle. It repartitions at every threshold and deliberately has the old
  # O(features * rows^2) shape.
  -> .brute(rows, ys, wts, cfg, parent_imp)
    k = cfg[:k]
    min_leaf = cfg[:min_leaf]
    crit = cfg[:crit]
    nd = Estimator.weight_total(wts, rows.size).to_f
    tol = parent_imp / 1000000000000.to_f
    best = nil
    best_gain = 0.to_f
    features = DecisionTree.split_features(cfg)
    features.each -> (feature)
      column = []
      rows.each -> (row)
        column.push(row[feature].to_f)
      unique = DecisionTree.sorted_unique(column)
      candidate = 0
      while candidate < unique.size - 1
        threshold = (unique[candidate] + unique[candidate + 1]) / 2.to_f
        part = DecisionTree.partition(rows, ys, wts, feature, threshold)
        left_n = part[:lr].size
        right_n = part[:rr].size
        if left_n >= min_leaf && right_n >= min_leaf
          left_weights = part[:lws]
          right_weights = part[:rws]
          left_total = Estimator.weight_total(left_weights, left_n)
          right_total = Estimator.weight_total(right_weights, right_n)
          left_impurity = DecisionTree.impurity(
            part[:ly], DecisionTree.node_counts(part[:ly], k, left_weights),
            left_total, crit, left_weights
          )
          right_impurity = DecisionTree.impurity(
            part[:ry], DecisionTree.node_counts(part[:ry], k, right_weights),
            right_total, crit, right_weights
          )
          gain = parent_imp
          gain -= (left_total.to_f / nd) * left_impurity
          gain -= (right_total.to_f / nd) * right_impurity
          if best == nil || gain > best_gain + tol
            best_gain = gain
            best = { feature: feature, threshold: threshold, gain: gain }
        candidate += 1
    best

  -> .classification_parent(ys, k, wts, criterion)
    total = Estimator.weight_total(wts, ys.size)
    DecisionTree.impurity(
      ys, DecisionTree.node_counts(ys, k, wts), total, criterion, wts
    )

  -> .regression_parent(ys, wts)
    DecisionTree.impurity(ys, nil, Estimator.weight_total(wts, ys.size), "mse", wts)

  -> .same_split?(fast, slow)
    ok = fast != nil && slow != nil
    ok = fast[:feature] == slow[:feature] if ok
    ok = fast[:threshold] == slow[:threshold] if ok
    if ok
      delta = fast[:gain] - slow[:gain]
      delta = 0.to_f - delta if delta < 0.to_f
      ok = delta < 1.to_f / 1000000000.to_f
    ok

describe "DecisionTree sorted feature sweep" ->
  it "stable-sorts feature indices by value and original row order" ->
    rows = [[2, 9], [1, 8], [2, 7], [0, 6], [1, 5]]
    expect(DecisionTree.sorted_feature_indices(rows, 0).join(",")).to eq("3,1,4,0,2")
    expect(DecisionTree.sorted_feature_indices(rows, 1).join(",")).to eq("4,3,2,1,0")

  it "matches brute-force multiclass gini across duplicates and ties" ->
    rows = [[2, 0], [0, 3], [1, 2], [2, 1], [0, 4], [3, 0], [1, 3], [3, 1]]
    ys = [0, 1, 2, 0, 1, 2, 2, 0]
    cfg = { k: 3, min_leaf: 1, crit: "gini", nf: 2 }
    parent = TreeSplitReference.classification_parent(ys, 3, nil, "gini")
    fast = DecisionTree.best_split(rows, ys, nil, cfg, parent)
    slow = TreeSplitReference.brute(rows, ys, nil, cfg, parent)
    expect(TreeSplitReference.same_split?(fast, slow)).to be_true

  it "matches brute-force entropy and its deterministic tie break" ->
    rows = [[0, 0], [0, 1], [1, 0], [1, 1],
            [2, 2], [2, 3], [3, 2], [3, 3]]
    ys = [0, 1, 1, 0, 2, 2, 2, 2]
    cfg = { k: 3, min_leaf: 1, crit: "entropy", nf: 2 }
    parent = TreeSplitReference.classification_parent(ys, 3, nil, "entropy")
    fast = DecisionTree.best_split(rows, ys, nil, cfg, parent)
    slow = TreeSplitReference.brute(rows, ys, nil, cfg, parent)
    expect(TreeSplitReference.same_split?(fast, slow)).to be_true

  it "matches weighted brute-force classification" ->
    rows = [[0], [1], [2], [3], [4], [5]]
    ys = [0, 1, 0, 1, 1, 0]
    weights = [1.to_f, 3.to_f, 2.to_f, 1.to_f, 4.to_f, 2.to_f]
    cfg = { k: 2, min_leaf: 1, crit: "gini", nf: 1 }
    parent = TreeSplitReference.classification_parent(ys, 2, weights, "gini")
    fast = DecisionTree.best_split(rows, ys, weights, cfg, parent)
    slow = TreeSplitReference.brute(rows, ys, weights, cfg, parent)
    expect(TreeSplitReference.same_split?(fast, slow)).to be_true

  it "matches weighted brute force with eight classes for gini and entropy" ->
    rows = []
    ys = []
    weights = []
    32.times -> (i)
      rows.push([(i * 7) % 31, (i * 13 + 5) % 29, (i * i + 3) % 23])
      ys.push((i * 5 + i / 7) % 8)
      weights.push(((i * 3) % 5 + 1).to_f)
    ["gini", "entropy"].each -> (criterion)
      cfg = { k: 8, min_leaf: 2, crit: criterion, nf: 3 }
      parent = TreeSplitReference.classification_parent(ys, 8, weights, criterion)
      fast = DecisionTree.best_split(rows, ys, weights, cfg, parent)
      slow = TreeSplitReference.brute(rows, ys, weights, cfg, parent)
      expect(TreeSplitReference.same_split?(fast, slow)).to be_true

  it "matches brute-force regression while preserving exact pure-child gain" ->
    rows = [[0], [1], [10], [11]]
    ys = [1.to_f, 1.to_f, 9.to_f, 9.to_f]
    cfg = { k: 0, min_leaf: 1, crit: "mse", nf: 1 }
    parent = TreeSplitReference.regression_parent(ys, nil)
    fast = DecisionTree.best_split(rows, ys, nil, cfg, parent)
    slow = TreeSplitReference.brute(rows, ys, nil, cfg, parent)
    expect(TreeSplitReference.same_split?(fast, slow)).to be_true
    expect(fast[:gain]).to eq(16)

  it "matches weighted brute-force regression" ->
    rows = [[0, 4], [1, 3], [2, 2], [3, 1], [4, 0], [5, 5]]
    ys = [1.to_f, 2.to_f, 8.to_f, 9.to_f, 10.to_f, 20.to_f]
    weights = [1.to_f, 2.to_f, 1.to_f, 3.to_f, 1.to_f, 2.to_f]
    cfg = { k: 0, min_leaf: 2, crit: "mse", nf: 2 }
    parent = TreeSplitReference.regression_parent(ys, weights)
    fast = DecisionTree.best_split(rows, ys, weights, cfg, parent)
    slow = TreeSplitReference.brute(rows, ys, weights, cfg, parent)
    expect(TreeSplitReference.same_split?(fast, slow)).to be_true

  it "retains small regression differences on a large target offset" ->
    rows = [[0], [1], [2], [3], [4], [5]]
    base = 1000000000.to_f
    ys = [base, base + 1.to_f, base + 2.to_f,
          base + 20.to_f, base + 21.to_f, base + 22.to_f]
    cfg = { k: 0, min_leaf: 1, crit: "mse", nf: 1 }
    parent = TreeSplitReference.regression_parent(ys, nil)
    fast = DecisionTree.best_split(rows, ys, nil, cfg, parent)
    slow = TreeSplitReference.brute(rows, ys, nil, cfg, parent)
    expect(fast[:feature]).to eq(slow[:feature])
    expect(fast[:threshold]).to eq(slow[:threshold])
    expect(fast[:gain] > 99.to_f).to be_true
    expect(fast[:threshold]).to eq(5.to_f / 2.to_f)

  it "materializes child rows, labels, and weights only for the winner" ->
    rows = [[0, 9], [1, 8], [2, 7], [8, 2], [9, 1], [10, 0]]
    ys = [0, 0, 0, 1, 1, 1]
    weights = [1.to_f, 2.to_f, 1.to_f, 1.to_f, 3.to_f, 1.to_f]
    cfg = { k: 2, min_leaf: 1, crit: "gini", nf: 2 }
    parent = TreeSplitReference.classification_parent(ys, 2, weights, "gini")
    best = DecisionTree.best_split(rows, ys, weights, cfg, parent)
    expect(best[:lr].size + best[:rr].size).to eq(rows.size)
    expect(best[:ly].size + best[:ry].size).to eq(ys.size)
    expect(best[:lws].size + best[:rws].size).to eq(weights.size)
    expect(best[:lr].size).to eq(3)

  it "skips child index maps when no presorted recursion consumes them" ->
    rows = [[0], [1], [8], [9]]
    ys = [0, 0, 1, 1]
    mapped = DecisionTree.partition(rows, ys, nil, 0, 4.5)
    lean = DecisionTree.partition(rows, ys, nil, 0, 4.5, false, false)
    expect(mapped[:left_indices].join(",")).to eq("0,1")
    expect(mapped[:right_indices].join(",")).to eq("2,3")
    expect(lean[:left_indices]).to be_nil
    expect(lean[:right_indices]).to be_nil
    expect(lean[:lr].size).to eq(mapped[:lr].size)
    expect(lean[:rr].size).to eq(mapped[:rr].size)

  it "keeps full classifier and regressor predictions unchanged" ->
    classifier = DecisionTreeClassifier.new
    classifier.fit([[0, 0], [0, 1], [1, 0], [1, 1]], [:a, :b, :b, :a])
    expect(classifier.predict([[0, 0], [0, 1], [1, 0], [1, 1]]).join(",")).to eq("a,b,b,a")
    expect(classifier.tree[:feature]).to eq(0)
    regressor = DecisionTreeRegressor.new(1)
    regressor.fit([[0], [1], [10], [11]], [1, 1, 9, 9])
    expect(regressor.predict([[0], [1], [10], [11]]).join(",")).to eq("1,1,9,9")
    expect(regressor.tree[:gain]).to eq(16)

  it "projects large batches to flat arrays without making the public tree stale" ->
    model = DecisionTreeClassifier.new(1)
    model.fit([[0], [1], [8], [9]], [0, 0, 1, 1])
    queries = []
    40.times -> (i)
      queries.push([i % 10])
    expected = []
    expected_probabilities = []
    queries.each -> (row)
      leaf = DecisionTree.descend(model.tree, row)
      expected.push(leaf[:prediction])
      expected_probabilities.push(DecisionTree.proba_of(leaf))
    expect(model.predict(queries).join(",")).to eq(expected.join(","))
    probabilities = model.predict_proba(queries)
    expect(probabilities.to_s).to eq(expected_probabilities.to_s)
    expected_column = []
    expected_probabilities.each -> (row)
      expected_column.push(row[1])
    expect(model.predict_proba(queries, 1).to_s).to eq(expected_column.to_s)
    second_probability = probabilities[1][0]
    probabilities[0][0] = 123.to_f
    expect(probabilities[1][0]).to eq(second_probability)

    # `tree` remains the source of truth: the next batch rebuilds its compact
    # program and observes an intentional mutation immediately.
    model.tree[:left][:prediction] = 7
    expect(model.predict(queries)[0]).to eq(7)
    expect(model.predict([[0]])[0]).to eq(7)
    model.tree[:left][:counts] = [0, 2]
    expect(model.predict_proba(queries)[0].to_s).to eq("\[0, 1\]")

    regressor = DecisionTreeRegressor.new(2)
    regressor.fit([[0], [1], [2], [8], [9], [10]], [0, 1, 2, 8, 9, 10])
    regression_expected = []
    queries.each -> (row)
      regression_expected.push(DecisionTree.descend(regressor.tree, row)[:prediction])
    expect(regressor.predict(queries).join(",")).to eq(regression_expected.join(","))

spec_summary
