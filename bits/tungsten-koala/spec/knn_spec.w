# KNN probability / distance-weighting / regression specs.
#
# Run from the repo root on both engines:
#   bin/tungsten bits/tungsten-koala/spec/knn_spec.w
#   bin/tungsten -o /tmp/knn_spec bits/tungsten-koala/spec/knn_spec.w
#   /tmp/knn_spec

use spec
use koala

describe "KNNClassifier probabilities and weights" ->
  it "keeps the historical uniform majority vote" ->
    model = KNNClassifier.new(3)
    model.fit([[0], [4], [5]], [:a, :b, :b])
    expect(model.predict([[1]]).join(",")).to eq("b")
    expect(model.weight_kind).to eq(:uniform)
    expect(model.classes.join(",")).to eq("a,b")
    expect(model.predict_proba([[1]])[0].join(",")).to eq("0.33333333333333331,0.66666666666666663")

  it "uses inverse Euclidean distance, matching sklearn" ->
    model = KNNClassifier.new(3, :distance)
    model.fit([[0], [4], [5]], [:a, :b, :b])
    probs = model.predict_proba([[1]])[0]
    expect(model.predict([[1]]).join(",")).to eq("a")
    expect(LinAlg.fabs(probs[0] - 12.to_f / 19.to_f) < 1.to_f / 1000000000000.to_f).to be_true
    expect(LinAlg.fabs(probs[1] - 7.to_f / 19.to_f) < 1.to_f / 1000000000000.to_f).to be_true
    expect(LinAlg.fabs(Stats.sum(probs) - 1.to_f) < 1.to_f / 1000000000000.to_f).to be_true

  it "lets only exact matches vote and shares weight across duplicate matches" ->
    model = KNNClassifier.new(3, :distance)
    model.fit([[0], [0], [10]], [:a, :b, :b])
    probs = model.predict_proba([[0]])[0]
    expect(probs.join(",")).to eq("0.5,0.5")
    expect(model.predict([[0]]).join(",")).to eq("a")

  it "returns full rows or one requested class column" ->
    model = KNNClassifier.new(3)
    model.fit([[0], [4], [5]], [:b, :a, :a])
    expect(model.classes.join(",")).to eq("b,a")
    expect(model.predict_proba([[1]], :b).join(",")).to eq("0.33333333333333331")
    expect(model.predict_proba([[1]], :missing)).to be_nil

  it "preserves opaque label identity" ->
    model = KNNClassifier.new(2)
    model.fit([[0], [10]], [:same, "same"])
    expect(model.classes.size).to eq(2)
    expect(model.classes[0]).to eq(:same)
    expect(model.classes[1]).to eq("same")
    expect(model.predict_proba([[0]])[0].join(",")).to eq("0.5,0.5")

  it "rejects invalid hyperparameters and numeric inputs" ->
    expect(KNNClassifier.new(0).fit([[0]], [:a])).to be_nil
    expect(KNNClassifier.new(1, :bogus).fit([[0]], [:a])).to be_nil
    expect(KNNClassifier.new(1).fit([[nil]], [:a])).to be_nil
    expect(KNNClassifier.new(1).fit([["text"]], [:a])).to be_nil
    expect(KNNClassifier.new(1).fit([[0]], [nil])).to be_nil

  it "invalidates learned state after a failed refit" ->
    model = KNNClassifier.new(1)
    model.fit([[0], [1]], [:a, :b])
    expect(model.predict([[0]]).join(",")).to eq("a")
    expect(model.fit([], [])).to be_nil
    expect(model.fitted?).to be_false
    expect(model.predict([[0]])).to be_nil
    expect(model.predict_proba([[0]])).to be_nil

  it "is tunable across k and weight_kind" ->
    model = KNNClassifier.new(3, :distance)
    expect(model.params[:k]).to eq(3)
    expect(model.params[:weight_kind]).to eq(:distance)
    clone = model.with_params({ k: 1, weight_kind: :uniform })
    expect(clone.k).to eq(1)
    expect(clone.weight_kind).to eq(:uniform)
    expect(clone.fitted?).to be_false

  it "exposes probabilities through a preprocessing Pipeline" ->
    pipe = Pipeline.new([
      [:scale, Scaler.new(:standard)],
      [:model, KNNClassifier.new(3, :distance)]
    ])
    x = [[0], [1], [2], [8], [9], [10]]
    y = [:lo, :lo, :lo, :hi, :hi, :hi]
    pipe.fit(x, y)
    expect(pipe.classes.join(",")).to eq("lo,hi")
    expect(pipe.predict_proba([[1]], :lo).size).to eq(1)
    expect(pipe.predict([[1], [9]]).join(",")).to eq("lo,hi")
    expect(pipe.params["model.weight_kind"]).to eq(:distance)

  it "cross-validates, grid-searches, and calibrates through the estimator contract" ->
    x = [[0], [1], [2], [3], [8], [9], [10], [11], [20], [21], [22], [23]]
    y = [:a, :a, :a, :a, :b, :b, :b, :b, :c, :c, :c, :c]
    scores = CrossValidation.cross_val_score(
      KNNClassifier.new(3, :distance), x, y, StratifiedKFold.new(4)
    )
    expect(scores.join(",")).to eq("1,1,1,1")
    search = GridSearch.new(
      KNNClassifier.new(3),
      { k: [1, 3], weight_kind: [:uniform, :distance] },
      StratifiedKFold.new(4)
    )
    expect(search.size).to eq(4)
    expect(search.fit(x, y)).not_to be_nil
    calibrated = CalibratedClassifierCV.new(
      Pipeline.new([Scaler.new(:standard), KNNClassifier.new(3, :distance)]),
      :sigmoid,
      3
    )
    expect(calibrated.fit(x, y)).not_to be_nil
    expect(calibrated.predict_proba([[1], [9], [21]]).size).to eq(3)

  it "persists classes, distance weighting, and exact probabilities" ->
    model = KNNClassifier.new(3, :distance)
    model.fit([[0], [4], [5]], [:a, :b, :b])
    back = Persist.loads(Persist.dumps(model))
    expect(back.classes.join(",")).to eq("a,b")
    expect(back.weight_kind).to eq(:distance)
    expect(back.predict([[1]]).join(",")).to eq("a")
    expect(back.predict_proba([[1]])[0].to_s).to eq(model.predict_proba([[1]])[0].to_s)

  it "loads the pre-weighting persistence state as uniform KNN" ->
    legacy = {
      k: 1,
      train_rows: [[0], [10]],
      train_labels: [:a, :b]
    }
    model = KNNClassifier.load_state(legacy)
    expect(model).not_to be_nil
    expect(model.weight_kind).to eq(:uniform)
    expect(model.classes.join(",")).to eq("a,b")
    expect(model.predict([[9]]).join(",")).to eq("b")

describe "KNeighborsRegressor" ->
  it "averages neighbours under uniform weights" ->
    model = KNeighborsRegressor.new(3)
    expect(model.fit([[0], [4], [5]], [0, 4, 5])).not_to be_nil
    expect(model.predict([[1]])[0].to_s).to eq("3")

  it "uses inverse Euclidean distance, matching sklearn" ->
    model = KNeighborsRegressor.new(3, :distance)
    model.fit([[0], [4], [5]], [0, 4, 5])
    expected = 31.to_f / 19.to_f
    expect(LinAlg.fabs(model.predict([[1]])[0] - expected) < 1.to_f / 1000000000000.to_f).to be_true

  it "averages duplicate exact matches and ignores nonmatches" ->
    model = KNeighborsRegressor.new(3, :distance)
    model.fit([[0], [0], [10]], [2, 4, 10])
    expect(model.predict([[0]])[0].to_s).to eq("3")

  it "rejects invalid contracts and invalidates a failed refit" ->
    model = KNeighborsRegressor.new(2)
    model.fit([[0], [1]], [0, 1])
    expect(model.fit([[0]], [nil])).to be_nil
    expect(model.fitted?).to be_false
    expect(model.predict([[0]])).to be_nil
    expect(KNeighborsRegressor.new(0).fit([[0]], [0])).to be_nil
    expect(KNeighborsRegressor.new(1, :bogus).fit([[0]], [0])).to be_nil

  it "pipelines, cross-validates, and grid-searches both weighting modes" ->
    x = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    y = []
    x.each -> (value)
      y.push(value * value)
    pipe = Pipeline.new([
      [:scale, Scaler.new(:standard)],
      [:model, KNeighborsRegressor.new(2, :distance)]
    ])
    expect(CrossValidation.cross_val_score(pipe, x, y, 3).size).to eq(3)
    search = GridSearch.new(
      KNeighborsRegressor.new(2),
      { k: [1, 2], weight_kind: [:uniform, :distance] },
      3
    )
    expect(search.fit(x, y)).not_to be_nil
    expect(search.size).to eq(4)
    expect(search.best_estimator.fitted?).to be_true

  it "persists its corrected distance rule exactly" ->
    model = KNeighborsRegressor.new(3, :distance)
    model.fit([[0], [4], [5]], [0, 4, 5])
    back = Persist.loads(Persist.dumps(model))
    expect(back.weight_kind).to eq(:distance)
    expect(back.predict([[1]])[0] == model.predict([[1]])[0]).to be_true
    state = model.to_state
    state[:train_targets] = [nil, 4, 5]
    expect(KNeighborsRegressor.load_state(state)).to be_nil

spec_summary
