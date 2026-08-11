# Gradient boosting specs.
#
# Run from the repository root on both engines:
#   bin/tungsten bits/tungsten-koala/spec/gradient_boosting_spec.w
#   bin/tungsten compile bits/tungsten-koala/spec/gradient_boosting_spec.w \
#     --out /tmp/koala-gradient-boosting-spec
#   /tmp/koala-gradient-boosting-spec

use spec
use koala
use support

+ BoostFx
  -> .quadratic_x
    [[0 - 10], [0 - 9], [0 - 8], [0 - 7], [0 - 6],
     [0 - 5], [0 - 4], [0 - 3], [0 - 2], [0 - 1],
     [0], [1], [2], [3], [4], [5], [6], [7], [8], [9], [10]]

  -> .quadratic_y
    out = []
    BoostFx.quadratic_x.each -> (row)
      out.push(row[0] * row[0])
    out

  -> .binary_x
    [[0, 0], [0, 1], [1, 0], [1, 1],
     [8, 8], [8, 9], [9, 8], [9, 9]]

  -> .binary_y
    [:cold, :cold, :cold, :cold, :hot, :hot, :hot, :hot]

  -> .multiclass_x
    [[0, 0], [0, 1], [1, 0],
     [10, 10], [10, 11], [11, 10],
     [20, 0], [20, 1], [21, 0]]

  -> .multiclass_y
    [:a, :a, :a, :b, :b, :b, :c, :c, :c]

  -> .rate
    1.to_f / 10.to_f

-> boost_close(a, b)
  LinAlg.fabs(a.to_f - b.to_f) < 1.to_f / 1000000000.to_f

describe "GradientBoostingRegressor" ->
  it "fits a nonlinear quadratic with additive shallow trees" ->
    model = GradientBoostingRegressor.new(60, BoostFx.rate, 2)
    expect(model.fit(BoostFx.quadratic_x, BoostFx.quadratic_y)).not_to be_nil
    expect(model.fitted?).to be_true
    expect(model.trees.size).to eq(60)
    expect(model.train_scores.size).to eq(60)
    expect(model.score(BoostFx.quadratic_x, BoostFx.quadratic_y) > 99.to_f / 100.to_f).to be_true

  it "makes one unshrunk stage exactly the corresponding regression tree" ->
    x = [[0], [1], [10], [11]]
    y = [1, 1, 9, 9]
    tree = DecisionTreeRegressor.new(1)
    tree.fit(x, y)
    boosted = GradientBoostingRegressor.new(1, 1, 1)
    boosted.fit(x, y)
    expect(boosted.predict(x).to_s).to eq(tree.predict(x).to_s)
    expect(boost_close(boosted.train_scores[0], 0)).to be_true

  it "reduces training MSE stage by stage" ->
    model = GradientBoostingRegressor.new(20, BoostFx.rate, 1)
    model.fit(BoostFx.quadratic_x, BoostFx.quadratic_y)
    monotone = true
    i = 1
    while i < model.train_scores.size
      monotone = false if model.train_scores[i] > model.train_scores[i - 1]
      i += 1
    expect(monotone).to be_true
    expect(model.train_scores[19] < model.train_scores[0]).to be_true

  it "exposes every staged prediction prefix without refitting" ->
    model = GradientBoostingRegressor.new(6, BoostFx.rate, 2)
    model.fit(BoostFx.quadratic_x, BoostFx.quadratic_y)
    stages = model.staged_predict([[0], [5]])
    expect(stages.size).to eq(6)
    expect(stages[5].to_s).to eq(model.predict([[0], [5]]).to_s)
    expect(stages[0].to_s == stages[5].to_s).to be_false

  it "honors integer sample weights like row duplication" ->
    x = [[0], [1], [4], [5]]
    y = [0, 1, 16, 25]
    weighted = GradientBoostingRegressor.new(8, BoostFx.rate, 1)
    duplicated = GradientBoostingRegressor.new(8, BoostFx.rate, 1)
    weighted.fit(x, y, [2, 1, 1, 1])
    duplicated.fit([[0], [0], [1], [4], [5]], [0, 0, 1, 16, 25])
    query = [[0], [2], [5]]
    expect(weighted.predict(query).to_s).to eq(duplicated.predict(query).to_s)
    expect(weighted.initial_prediction == duplicated.initial_prediction).to be_true

  it "composes in a preprocessing Pipeline" ->
    pipe = Pipeline.new([
      [:scale, Scaler.new(:standard)],
      [:boost, GradientBoostingRegressor.new(20, BoostFx.rate, 2)]
    ])
    expect(pipe.fit(BoostFx.quadratic_x, BoostFx.quadratic_y)).not_to be_nil
    expect(pipe.score(BoostFx.quadratic_x, BoostFx.quadratic_y) > 9.to_f / 10.to_f).to be_true
    expect(pipe.params["boost.n_estimators"]).to eq(20)

  it "cross-validates and grid-searches through the estimator contract" ->
    x = [[0], [1], [2], [3], [4], [5], [6], [7], [8], [9], [10], [11]]
    y = [0, 1, 4, 9, 16, 25, 36, 49, 64, 81, 100, 121]
    scores = CrossValidation.cross_val_score(
      GradientBoostingRegressor.new(20, BoostFx.rate, 2), x, y, 3
    )
    expect(scores.size).to eq(3)
    grid = GridSearch.new(
      GradientBoostingRegressor.new(1, BoostFx.rate, 1),
      { n_estimators: [1, 20] },
      3
    )
    expect(grid.fit(x, y)).not_to be_nil
    expect(grid.best_params[:n_estimators]).to eq(20)
    expect(grid.best_estimator.fitted?).to be_true

  it "is deterministic and persists exact predictions" ->
    one = GradientBoostingRegressor.new(12, BoostFx.rate, 2)
    two = GradientBoostingRegressor.new(12, BoostFx.rate, 2)
    one.fit(BoostFx.quadratic_x, BoostFx.quadratic_y)
    two.fit(BoostFx.quadratic_x, BoostFx.quadratic_y)
    expect(Persist.dumps(one)).to eq(Persist.dumps(two))
    back = Persist.loads(Persist.dumps(one))
    expect(back.predict(BoostFx.quadratic_x).to_s).to eq(one.predict(BoostFx.quadratic_x).to_s)
    expect(back.train_scores.to_s).to eq(one.train_scores.to_s)

  it "exposes tunable constructor parameters on a fresh clone" ->
    model = GradientBoostingRegressor.new(20, BoostFx.rate, 2, 3)
    clone = model.with_params({ n_estimators: 7, max_depth: 1 })
    expect(model.params[:n_estimators]).to eq(20)
    expect(clone.params[:n_estimators]).to eq(7)
    expect(clone.params[:max_depth]).to eq(1)
    expect(clone.params[:min_samples_leaf]).to eq(3)
    expect(clone.fitted?).to be_false
    expect(clone.estimator_name).to eq("GradientBoostingRegressor")

describe "GradientBoostingClassifier binary loss" ->
  it "fits opaque classes and emits normalized probability rows" ->
    model = GradientBoostingClassifier.new(20, BoostFx.rate, 2)
    expect(model.fit(BoostFx.binary_x, BoostFx.binary_y)).not_to be_nil
    expect(model.classes.join(",")).to eq("cold,hot")
    expect(model.predict(BoostFx.binary_x).join(",")).to eq(BoostFx.binary_y.join(","))
    probs = model.predict_proba([[0, 0], [9, 9]])
    expect(probs.size).to eq(2)
    expect(boost_close(Stats.sum(probs[0]), 1)).to be_true
    expect(boost_close(Stats.sum(probs[1]), 1)).to be_true
    expect(model.predict_proba([[0, 0]], :hot)[0] < 1.to_f / 2.to_f).to be_true
    expect(model.predict_proba([[9, 9]], :hot)[0] > 1.to_f / 2.to_f).to be_true

  it "uses weighted log odds as its initial raw score" ->
    model = GradientBoostingClassifier.new(1, BoostFx.rate, 1)
    model.fit([[0], [1], [2], [3]], [:a, :a, :b, :b], [1, 1, 3, 1])
    expect(boost_close(model.initial_raw, Math.log(2.to_f))).to be_true

  it "reduces binomial log loss over stages" ->
    model = GradientBoostingClassifier.new(12, BoostFx.rate, 1)
    model.fit(BoostFx.binary_x, BoostFx.binary_y)
    expect(model.train_scores[11] < model.train_scores[0]).to be_true
    expect(boost_close(
      model.log_loss(BoostFx.binary_x, BoostFx.binary_y),
      model.train_scores[11]
    )).to be_true

  it "honors classification sample weights like duplication" ->
    x = [[0], [1], [8], [9]]
    y = [:a, :a, :b, :b]
    weighted = GradientBoostingClassifier.new(6, BoostFx.rate, 1)
    duplicated = GradientBoostingClassifier.new(6, BoostFx.rate, 1)
    weighted.fit(x, y, [2, 1, 1, 1])
    duplicated.fit([[0], [0], [1], [8], [9]], [:a, :a, :a, :b, :b])
    query = [[0], [4], [9]]
    expect(weighted.predict_proba(query).to_s).to eq(duplicated.predict_proba(query).to_s)

  it "forwards through Pipeline and calibration" ->
    pipe = Pipeline.new([
      Scaler.new(:standard),
      GradientBoostingClassifier.new(8, BoostFx.rate, 1)
    ])
    expect(pipe.fit(BoostFx.binary_x, BoostFx.binary_y)).not_to be_nil
    expect(pipe.predict_proba([[0, 0]]).size).to eq(1)
    calibrated = CalibratedClassifierCV.new(
      GradientBoostingClassifier.new(5, BoostFx.rate, 1), :sigmoid, 2
    )
    expect(calibrated.fit(BoostFx.binary_x, BoostFx.binary_y)).not_to be_nil
    expect(calibrated.predict([[0, 0], [9, 9]]).join(",")).to eq("cold,hot")

describe "GradientBoostingClassifier multiclass loss" ->
  it "grows one tree per class per stage and predicts all classes" ->
    model = GradientBoostingClassifier.new(20, BoostFx.rate, 2)
    expect(model.fit(BoostFx.multiclass_x, BoostFx.multiclass_y)).not_to be_nil
    expect(model.classes.join(",")).to eq("a,b,c")
    expect(model.trees.size).to eq(20)
    expect(model.trees[0].size).to eq(3)
    expect(model.predict(BoostFx.multiclass_x).join(",")).to eq(BoostFx.multiclass_y.join(","))
    expect(model.score(BoostFx.multiclass_x, BoostFx.multiclass_y).to_s).to eq("1")

  it "returns softmax rows and per-class columns" ->
    model = GradientBoostingClassifier.new(10, BoostFx.rate, 2)
    model.fit(BoostFx.multiclass_x, BoostFx.multiclass_y)
    probs = model.predict_proba([[0, 0], [10, 10], [20, 0]])
    expect(probs.size).to eq(3)
    probs.each -> (row)
      expect(row.size).to eq(3)
      expect(boost_close(Stats.sum(row), 1)).to be_true
    expect(model.predict_proba([[0, 0]], :a)[0] > model.predict_proba([[0, 0]], :b)[0]).to be_true
    expect(model.predict_proba([[0, 0]], :missing)).to be_nil

  it "returns binary vectors and multiclass rows from decision_function" ->
    binary = GradientBoostingClassifier.new(2, BoostFx.rate, 1)
    binary.fit(BoostFx.binary_x, BoostFx.binary_y)
    multi = GradientBoostingClassifier.new(2, BoostFx.rate, 1)
    multi.fit(BoostFx.multiclass_x, BoostFx.multiclass_y)
    expect(type(binary.decision_function([[0, 0]])[0])).to eq("Float")
    expect(multi.decision_function([[0, 0]])[0].size).to eq(3)

  it "exposes staged logits, probabilities, and labels" ->
    model = GradientBoostingClassifier.new(6, BoostFx.rate, 2)
    model.fit(BoostFx.multiclass_x, BoostFx.multiclass_y)
    raw = model.staged_decision_function([[0, 0], [10, 10]])
    probs = model.staged_predict_proba([[0, 0], [10, 10]])
    preds = model.staged_predict([[0, 0], [10, 10]])
    expect(raw.size).to eq(6)
    expect(probs.size).to eq(6)
    expect(preds.size).to eq(6)
    expect(raw[5].to_s).to eq(model.decision_function([[0, 0], [10, 10]]).to_s)
    expect(probs[5].to_s).to eq(model.predict_proba([[0, 0], [10, 10]]).to_s)
    expect(preds[5].join(",")).to eq(model.predict([[0, 0], [10, 10]]).join(","))

  it "cross-validates a three-class reference problem" ->
    model = GradientBoostingClassifier.new(10, BoostFx.rate, 2)
    scores = CrossValidation.cross_val_score(
      model, BoostFx.multiclass_x, BoostFx.multiclass_y, StratifiedKFold.new(3)
    )
    expect(scores.to_s).to eq("\[1, 1, 1\]")
    expect(model.fitted?).to be_false

  it "persists multiclass logits, trees, and exact probabilities" ->
    model = GradientBoostingClassifier.new(8, BoostFx.rate, 2)
    model.fit(BoostFx.multiclass_x, BoostFx.multiclass_y)
    back = Persist.loads(Persist.dumps(model))
    expect(back).not_to be_nil
    expect(back.classes.join(",")).to eq("a,b,c")
    expect(back.predict_proba(BoostFx.multiclass_x).to_s).to eq(model.predict_proba(BoostFx.multiclass_x).to_s)
    expect(back.decision_function([[0, 0]]).to_s).to eq(model.decision_function([[0, 0]]).to_s)

  it "is model-agnostically inspectable by permutation importance" ->
    model = GradientBoostingClassifier.new(10, BoostFx.rate, 2)
    model.fit(BoostFx.multiclass_x, BoostFx.multiclass_y)
    result = PermutationImportance.compute(
      model, BoostFx.multiclass_x, BoostFx.multiclass_y, 4, 42
    )
    expect(result).not_to be_nil
    expect(result.importances_mean.size).to eq(2)

describe "GradientBoosting validation" ->
  it "returns nil before fit and on invalid query widths" ->
    reg = GradientBoostingRegressor.new
    clf = GradientBoostingClassifier.new
    expect(reg.predict([[1]])).to be_nil
    expect(clf.predict([[1]])).to be_nil
    reg.fit([[0], [1]], [0, 1])
    clf.fit([[0], [1]], [:a, :b])
    expect(reg.predict([[1, 2]])).to be_nil
    expect(clf.predict_proba([[1, 2]])).to be_nil

  it "rejects invalid hyperparameters without fitting" ->
    x = [[0], [1], [2], [3]]
    y = [0, 1, 4, 9]
    expect(GradientBoostingRegressor.new(0).fit(x, y)).to be_nil
    expect(GradientBoostingRegressor.new(2, 0).fit(x, y)).to be_nil
    expect(GradientBoostingRegressor.new(2, BoostFx.rate, 0 - 1).fit(x, y)).to be_nil
    expect(GradientBoostingRegressor.new(2, BoostFx.rate, 1, 0).fit(x, y)).to be_nil

  it "rejects empty, ragged, nonnumeric, and misaligned regression data" ->
    model = GradientBoostingRegressor.new(2)
    expect(model.fit(nil, [1])).to be_nil
    expect(model.fit([[1]], nil)).to be_nil
    expect(model.fit([], [])).to be_nil
    expect(model.fit([[1], [2, 3]], [1, 2])).to be_nil
    expect(model.fit([["x"], ["y"]], [1, 2])).to be_nil
    expect(model.fit([[1], [2]], ["x", "y"])).to be_nil
    expect(model.fit([[1], [2]], [1])).to be_nil

  it "requires at least two classifier classes after zero-weight rows drop" ->
    x = [[0], [1], [8], [9]]
    y = [:a, :a, :b, :b]
    expect(GradientBoostingClassifier.new(2).fit(x, [:a, :a, :a, :a])).to be_nil
    expect(GradientBoostingClassifier.new(2).fit(x, y, [1, 1, 0, 0])).to be_nil

  it "invalidates learned state after a failed refit" ->
    reg = GradientBoostingRegressor.new(2)
    reg.fit([[0], [1], [2]], [0, 1, 4])
    expect(reg.fitted?).to be_true
    expect(reg.fit([[0], [1]], [0])).to be_nil
    expect(reg.fitted?).to be_false
    expect(reg.predict([[1]])).to be_nil

  it "rejects malformed scoring labels and weights" ->
    model = GradientBoostingClassifier.new(2)
    model.fit(BoostFx.binary_x, BoostFx.binary_y)
    expect(model.score(BoostFx.binary_x, [:cold])).to be_nil
    expect(model.score(BoostFx.binary_x, BoostFx.binary_y, [1])).to be_nil

spec_summary
