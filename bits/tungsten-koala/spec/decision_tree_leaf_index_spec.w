# Stable leaf-index specs for trees and forests.
#
# Run from the repository root on both engines:
#   bin/tungsten bits/tungsten-koala/spec/decision_tree_leaf_index_spec.w
#   bin/tungsten compile bits/tungsten-koala/spec/decision_tree_leaf_index_spec.w \
#     --out /tmp/koala-decision-tree-leaf-index-spec
#   /tmp/koala-decision-tree-leaf-index-spec

use spec
use koala

-> leaf_index_rows
  [[0], [1], [2], [3], [4], [5]]

describe "DecisionTree leaf indices" ->
  it "uses sklearn's zero-based preorder numbering for classification" ->
    rows = leaf_index_rows
    model = DecisionTreeClassifier.new.fit(
      rows, [0, 0, 1, 1, 2, 2]
    )
    expect(model.node_count).to eq(5)
    expect(model.leaf_indices(rows).to_s).to eq("\[1, 1, 3, 3, 4, 4\]")
    expect(type(model.apply(rows)[0])).to eq("Hash")

  it "uses the same numbering for regression" ->
    rows = leaf_index_rows
    model = DecisionTreeRegressor.new.fit(
      rows, [0, 0, 10, 10, 20, 20]
    )
    expect(model.node_count).to eq(5)
    expect(model.leaf_indices(rows).to_s).to eq("\[1, 1, 3, 3, 4, 4\]")

  it "numbers a stump at zero and updates after pruning" ->
    rows = leaf_index_rows
    stump = DecisionTreeClassifier.new(0).fit(
      rows, [0, 0, 1, 1, 2, 2]
    )
    pruned = DecisionTreeClassifier.new(
      nil, nil, nil, nil, 1
    ).fit(rows, [0, 0, 1, 1, 2, 2])
    expect(stump.leaf_indices(rows).to_s).to eq("\[0, 0, 0, 0, 0, 0\]")
    expect(pruned.leaf_indices(rows).to_s).to eq("\[0, 0, 0, 0, 0, 0\]")

  it "follows learned missing directions" ->
    rows = [[0], [1], [8], [9], [nil], [nil]]
    left = DecisionTreeClassifier.new.fit(rows, [0, 0, 1, 1, 0, 0])
    right = DecisionTreeClassifier.new.fit(rows, [0, 0, 1, 1, 1, 1])
    expect(left.leaf_indices(rows).to_s).to eq("\[1, 1, 2, 2, 1, 1\]")
    expect(right.leaf_indices(rows).to_s).to eq("\[1, 1, 2, 2, 2, 2\]")

  it "tracks an intentional public-tree mutation" ->
    rows = leaf_index_rows
    model = DecisionTreeClassifier.new.fit(
      rows, [0, 0, 1, 1, 2, 2]
    )
    expect(model.leaf_indices([[2]])[0]).to eq(3)
    model.tree[:threshold] = 7.to_f / 2.to_f
    expect(model.leaf_indices([[2]])[0]).to eq(1)

  it "survives persistence without renumbering" ->
    rows = leaf_index_rows
    model = DecisionTreeClassifier.new.fit(
      rows, [0, 0, 1, 1, 2, 2]
    )
    loaded = Persist.loads(Persist.dumps(model))
    expect(loaded.leaf_indices(rows).to_s).to eq(
      model.leaf_indices(rows).to_s
    )

  it "returns nil before fit or on invalid rows and accepts an empty batch" ->
    model = DecisionTreeClassifier.new
    expect(model.leaf_indices([[0]])).to be_nil
    model.fit(leaf_index_rows, [0, 0, 1, 1, 2, 2])
    expect(model.leaf_indices([[0, 1]])).to be_nil
    expect(model.leaf_indices([["bad"]])).to be_nil
    expect(model.leaf_indices([]).to_s).to eq("\[\]")

describe "RandomForest leaf indices" ->
  it "returns one preorder ID per sample and tree" ->
    rows = leaf_index_rows
    forest = RandomForestClassifier.new(
      1, :all, nil, 1, 42, :gini, false
    ).fit(rows, [0, 0, 1, 1, 2, 2])
    expect(forest.leaf_indices(rows).to_s).to eq(
      "\[\[1\], \[1\], \[3\], \[3\], \[4\], \[4\]\]"
    )

  it "keeps sample-major shape for multiple classifier trees" ->
    rows = leaf_index_rows
    forest = RandomForestClassifier.new(3, :all, 3, 1, 42).fit(
      rows, [0, 0, 1, 1, 2, 2]
    )
    indices = forest.leaf_indices(rows)
    expect(indices.size).to eq(rows.size)
    indices.each -> (row)
      expect(row.size).to eq(3)
    forest.trees.each_with_index -> (tree, t)
      direct = DecisionTree.batch_leaf_indices(tree, rows)
      rows.size.times -> (i)
        expect(indices[i][t]).to eq(direct[i])

  it "supports regression and the same invalid-input contract" ->
    rows = leaf_index_rows
    forest = RandomForestRegressor.new(
      1, :all, nil, 1, 42, :mse, false
    ).fit(rows, [0, 0, 10, 10, 20, 20])
    expect(forest.leaf_indices(rows).to_s).to eq(
      "\[\[1\], \[1\], \[3\], \[3\], \[4\], \[4\]\]"
    )
    expect(RandomForestRegressor.new.leaf_indices(rows)).to be_nil
    expect(forest.leaf_indices([[0, 1]])).to be_nil
    expect(forest.leaf_indices([]).to_s).to eq("\[\]")
