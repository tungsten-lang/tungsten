# Probability calibration specs.
#
# Run from the repository root on both engines:
#   bin/tungsten bits/tungsten-koala/spec/calibration_spec.w
#   bin/tungsten compile bits/tungsten-koala/spec/calibration_spec.w \
#     --out /tmp/koala-calibration-spec && /tmp/koala-calibration-spec

use spec
use koala
use support

+ CalibrationFixture
  # A clean threshold problem with six examples of each class. Three-fold
  # stratification gives every calibration fold two positives and two
  # negatives, so Platt's two priors are both observable.
  -> .binary_x
    [[0], [1], [2], [3], [4], [5], [6], [7], [8], [9], [10], [11]]

  -> .binary_y
    [:cold, :cold, :cold, :cold, :cold, :cold,
     :hot, :hot, :hot, :hot, :hot, :hot]

  -> .multiclass_x
    [[1, 0, 0], [1, 0, 0], [1, 0, 0], [1, 0, 0], [1, 0, 0], [1, 0, 0],
     [0, 1, 0], [0, 1, 0], [0, 1, 0], [0, 1, 0], [0, 1, 0], [0, 1, 0],
     [0, 0, 1], [0, 0, 1], [0, 0, 1], [0, 0, 1], [0, 0, 1], [0, 0, 1]]

  -> .multiclass_y
    [:a, :a, :a, :a, :a, :a,
     :b, :b, :b, :b, :b, :b,
     :c, :c, :c, :c, :c, :c]

-> calibration_close(a, b)
  LinAlg.fabs(a.to_f - b.to_f) < 1.to_f / 1000000000.to_f

describe "CalibrationCurve" ->
  it "matches the hand-computed two-bin reliability diagram" ->
    curve = Metrics.calibration_curve(
      [1.to_f / 10.to_f, 2.to_f / 10.to_f, 8.to_f / 10.to_f, 9.to_f / 10.to_f],
      [0, 1, 1, 1],
      2
    )
    expect(curve.prob_true.to_s).to be_nums("\[0.5, 1\]")
    expect(curve.prob_pred.to_s).to be_nums("\[0.15, 0.85\]")
    expect(curve.counts.join(",")).to eq("2,2")
    expect(curve.weight_sums.join(",")).to eq("2,2")
    expect(calibration_close(curve.ece, 1.to_f / 4.to_f)).to be_true
    expect(calibration_close(curve.mce, 35.to_f / 100.to_f)).to be_true

  it "omits empty bins and supports quantile bins" ->
    scores = [1.to_f / 100.to_f, 2.to_f / 100.to_f, 3.to_f / 100.to_f,
              7.to_f / 10.to_f, 8.to_f / 10.to_f, 9.to_f / 10.to_f]
    curve = Metrics.calibration_curve(scores, [0, 0, 1, 1, 1, 1], 2, :quantile)
    expect(curve.strategy).to eq("quantile")
    expect(curve.counts.join(",")).to eq("3,3")
    expect(curve.prob_true.to_s).to be_nums("\[0.333333, 1\]")

  it "weights bin means and ECE" ->
    scores = [1.to_f / 10.to_f, 2.to_f / 10.to_f, 8.to_f / 10.to_f, 9.to_f / 10.to_f]
    curve = Metrics.calibration_curve(scores, [0, 1, 1, 1], 2, :uniform, 1, [3, 1, 1, 1])
    expect(curve.prob_true.to_s).to be_nums("\[0.25, 1\]")
    expect(curve.prob_pred.to_s).to be_nums("\[0.125, 0.85\]")
    expect(curve.weight_sums.join(",")).to eq("4,2")
    expect(calibration_close(curve.ece, 2.to_f / 15.to_f)).to be_true
    expect(calibration_close(
      Metrics.expected_calibration_error(scores, [0, 1, 1, 1], 2, :uniform, 1, [3, 1, 1, 1]),
      2.to_f / 15.to_f
    )).to be_true

  it "rejects malformed probabilities, bins, strategies, and weights" ->
    expect(Metrics.calibration_curve([], [], 2)).to be_nil
    expect(Metrics.calibration_curve([0, 1], [0], 2)).to be_nil
    expect(Metrics.calibration_curve([0 - 1, 1], [0, 1], 2)).to be_nil
    expect(Metrics.calibration_curve([0, 2], [0, 1], 2)).to be_nil
    expect(Metrics.calibration_curve([0, 1], [0, 1], 0)).to be_nil
    expect(Metrics.calibration_curve([0, 1], [0, 1], 2, :bogus)).to be_nil
    expect(Metrics.calibration_curve([0, 1], [0, 1], 2, :uniform, 1, [1])).to be_nil

describe "Platt sigmoid calibrator" ->
  it "maps a balanced constant score to one half" ->
    state = Calibration.fit_sigmoid([0, 0, 0, 0], [0, 0, 1, 1], nil)
    expect(state[:kind]).to eq("sigmoid")
    expect(calibration_close(Calibration.apply_calibrator(state, 0), 1.to_f / 2.to_f)).to be_true

  it "is monotone and honors integer weights like duplication" ->
    scores = [0 - 2, 0 - 1, 1, 2]
    targets = [0, 0, 1, 1]
    weighted = Calibration.fit_sigmoid(scores, targets, [2.to_f, 1.to_f, 1.to_f, 1.to_f])
    duplicated = Calibration.fit_sigmoid([0 - 2, 0 - 2, 0 - 1, 1, 2], [0, 0, 0, 1, 1], nil)
    expect(calibration_close(weighted[:slope], duplicated[:slope])).to be_true
    expect(calibration_close(weighted[:intercept], duplicated[:intercept])).to be_true
    lo = Calibration.apply_calibrator(weighted, 0 - 2)
    hi = Calibration.apply_calibrator(weighted, 2)
    expect(lo < hi).to be_true

describe "Isotonic calibrator" ->
  it "pools adjacent violations by their weighted mean" ->
    state = Calibration.fit_isotonic([0, 1, 2, 3], [0, 1, 0, 1], nil)
    expect(state[:x_thresholds].join(",")).to eq("0,1,2,3")
    expect(state[:y_thresholds].to_s).to be_nums("\[0, 0.5, 0.5, 1\]")
    expect(calibration_close(Calibration.apply_calibrator(state, 0 - 10), 0)).to be_true
    expect(calibration_close(Calibration.apply_calibrator(state, 3), 1)).to be_true
    expect(calibration_close(Calibration.apply_calibrator(state, 3.to_f / 2.to_f), 1.to_f / 2.to_f)).to be_true

  it "matches row duplication under integer weights" ->
    weighted = Calibration.fit_isotonic([0, 1, 2], [0, 1, 0], [1.to_f, 2.to_f, 1.to_f])
    duplicated = Calibration.fit_isotonic([0, 1, 1, 2], [0, 1, 1, 0], nil)
    expect(weighted[:x_thresholds].join(",")).to eq(duplicated[:x_thresholds].join(","))
    expect(weighted[:y_thresholds].to_s).to be_nums(duplicated[:y_thresholds].to_s)

describe "Pipeline probabilistic forwarding" ->
  it "forwards classes, probabilities, and decision scores through transforms" ->
    pipe = Pipeline.new([Scaler.new(:standard), LogisticRegression.new(1, 100)])
    pipe.fit(CalibrationFixture.binary_x, CalibrationFixture.binary_y)
    expect(pipe.classes.join(",")).to eq("cold,hot")
    expect(pipe.predict_proba([[2]], :hot).size).to eq(1)
    expect(pipe.decision_function([[2]]).size).to eq(1)

  it "returns nil when the estimator tail has no probability API" ->
    pipe = Pipeline.new([Scaler.new(:standard), LinearRegression.new])
    pipe.fit([0, 1, 2, 3], [0, 1, 2, 3])
    expect(pipe.classes).to be_nil
    expect(pipe.predict_proba([1])).to be_nil
    expect(pipe.decision_function([1])).to be_nil

describe "CalibratedClassifierCV" ->
  it "cross-fits a binary sigmoid calibrator and returns normalized probabilities" ->
    model = CalibratedClassifierCV.new(DecisionTreeClassifier.new(2), :sigmoid, 3)
    expect(model.fit(CalibrationFixture.binary_x, CalibrationFixture.binary_y) != nil).to be_true
    expect(model.fitted?).to be_true
    expect(model.classes.join(",")).to eq("cold,hot")
    expect(model.calibrated_models.size).to eq(3)
    probs = model.predict_proba([[2], [9]])
    expect(probs.size).to eq(2)
    expect(calibration_close(probs[0][0] + probs[0][1], 1)).to be_true
    expect(calibration_close(probs[1][0] + probs[1][1], 1)).to be_true
    expect(model.predict_proba([[2], [9]], :hot).size).to eq(2)
    expect(model.predict([[2], [9]]).join(",")).to eq("cold,hot")
    expect(model.score(CalibrationFixture.binary_x, CalibrationFixture.binary_y) > 9.to_f / 10.to_f).to be_true

  it "cross-fits isotonic calibration" ->
    model = CalibratedClassifierCV.new(DecisionTreeClassifier.new(2), :isotonic, 3)
    expect(model.fit(CalibrationFixture.binary_x, CalibrationFixture.binary_y) != nil).to be_true
    probs = model.predict_proba([[2], [9]])
    expect(probs[0][0] > probs[0][1]).to be_true
    expect(probs[1][1] > probs[1][0]).to be_true

  it "calibrates multiclass one-vs-rest and normalizes each row" ->
    model = CalibratedClassifierCV.new(GaussianNB.new, :sigmoid, 3)
    expect(model.fit(CalibrationFixture.multiclass_x, CalibrationFixture.multiclass_y) != nil).to be_true
    probs = model.predict_proba([[1, 0, 0], [0, 1, 0], [0, 0, 1]])
    expect(probs.size).to eq(3)
    expect(probs[0].size).to eq(3)
    expect(calibration_close(Stats.sum(probs[0]), 1)).to be_true
    expect(model.predict([[1, 0, 0], [0, 1, 0], [0, 0, 1]]).join(",")).to eq("a,b,c")
    expect(model.log_loss(CalibrationFixture.multiclass_x, CalibrationFixture.multiclass_y) != nil).to be_true

  it "wraps a preprocessing Pipeline without losing probability metadata" ->
    base = Pipeline.new([
      [:scale, Scaler.new(:standard)],
      [:tree, DecisionTreeClassifier.new(2)]
    ])
    model = CalibratedClassifierCV.new(base, :sigmoid, 3)
    expect(model.fit(CalibrationFixture.binary_x, CalibrationFixture.binary_y) != nil).to be_true
    expect(model.predict([[1], [10]]).join(",")).to eq("cold,hot")
    expect(model.calibrated_models[0][:model].classes.join(",")).to eq("cold,hot")
    loaded = Persist.loads(Persist.dumps(model))
    expect(loaded != nil).to be_true
    expect(loaded.predict_proba([[1], [10]]).to_s).to eq(model.predict_proba([[1], [10]]).to_s)

  it "is itself a Pipeline tail and cross-validates as an estimator" ->
    tail = CalibratedClassifierCV.new(DecisionTreeClassifier.new(2), :sigmoid, 2)
    pipe = Pipeline.new([Scaler.new(:standard), tail])
    expect(pipe.fit(CalibrationFixture.binary_x, CalibrationFixture.binary_y) != nil).to be_true
    expect(pipe.predict_proba([[1], [10]]).size).to eq(2)
    scores = CrossValidation.cross_val_score(
      CalibratedClassifierCV.new(DecisionTreeClassifier.new(2), :sigmoid, 2),
      CalibrationFixture.binary_x,
      CalibrationFixture.binary_y,
      StratifiedKFold.new(3)
    )
    expect(scores.size).to eq(3)
    expect(scores[0] != nil && scores[1] != nil && scores[2] != nil).to be_true

  it "exposes base parameters to GridSearch and returns fresh clones" ->
    proto = CalibratedClassifierCV.new(DecisionTreeClassifier.new(2), :sigmoid, 2)
    expect(proto.params[:method]).to eq("sigmoid")
    expect(proto.params["estimator.max_depth"]).to eq(2)
    clone = proto.with_params({ method: :isotonic, "estimator.max_depth": 1 })
    expect(clone.fitted?).to be_false
    expect(clone.method).to eq("isotonic")
    expect(clone.estimator.params[:max_depth]).to eq(1)
    search = GridSearch.new(proto, { "estimator.max_depth": [1, 2] }, StratifiedKFold.new(2))
    expect(search.fit(CalibrationFixture.binary_x, CalibrationFixture.binary_y) != nil).to be_true
    expect(search.best_estimator.fitted?).to be_true

  it "threads valid sample weights into base fits and calibrators" ->
    ones = []
    CalibrationFixture.binary_y.size.times -> (i)
      ones.push(1)
    plain = CalibratedClassifierCV.new(DecisionTreeClassifier.new(2), :sigmoid, 3)
    weighted = CalibratedClassifierCV.new(DecisionTreeClassifier.new(2), :sigmoid, 3)
    plain.fit(CalibrationFixture.binary_x, CalibrationFixture.binary_y)
    weighted.fit(CalibrationFixture.binary_x, CalibrationFixture.binary_y, ones)
    expect(plain.predict_proba([[2], [9]]).to_s).to be_nums(weighted.predict_proba([[2], [9]]).to_s)
    expect(weighted.score(CalibrationFixture.binary_x, CalibrationFixture.binary_y, ones) != nil).to be_true

  it "round-trips the complete fold ensemble through persistence" ->
    model = CalibratedClassifierCV.new(DecisionTreeClassifier.new(2), :sigmoid, 3)
    model.fit(CalibrationFixture.binary_x, CalibrationFixture.binary_y)
    before = model.predict_proba([[2], [5], [9]])
    loaded = Persist.loads(Persist.dumps(model))
    expect(loaded != nil).to be_true
    expect(loaded.predict([[2], [5], [9]]).join(",")).to eq(model.predict([[2], [5], [9]]).join(","))
    expect(loaded.predict_proba([[2], [5], [9]]).to_s).to be_nums(before.to_s)
    expect(loaded.params["estimator.max_depth"]).to eq(2)

  it "rejects malformed persisted calibrator state" ->
    model = CalibratedClassifierCV.new(DecisionTreeClassifier.new(2), :sigmoid, 3)
    model.fit(CalibrationFixture.binary_x, CalibrationFixture.binary_y)
    state = model.to_state
    state[:calibrated_models][0][:calibrators][1] = {
      kind: "sigmoid",
      slope: "not numeric",
      intercept: 0.to_f
    }
    expect(CalibratedClassifierCV.load_state(state)).to be_nil
    bad_isotonic = {
      kind: "isotonic",
      x_thresholds: [0, 1],
      y_thresholds: [1.to_f, 0.to_f]
    }
    expect(Calibration.valid_calibrator_state?(bad_isotonic, "isotonic")).to be_false

  it "invalidates on bad contracts instead of exposing stale state" ->
    model = CalibratedClassifierCV.new(DecisionTreeClassifier.new(2), :sigmoid, 3)
    model.fit(CalibrationFixture.binary_x, CalibrationFixture.binary_y)
    expect(model.fit([[0], [1]], [0, 0])).to be_nil
    expect(model.fitted?).to be_false
    expect(model.predict([[0]])).to be_nil
    expect(CalibratedClassifierCV.new(DecisionTreeClassifier.new, :bogus, 2).fit(
      CalibrationFixture.binary_x,
      CalibrationFixture.binary_y
    )).to be_nil
    expect(CalibratedClassifierCV.new(DecisionTreeClassifier.new, :sigmoid, 1).fit(
      CalibrationFixture.binary_x,
      CalibrationFixture.binary_y
    )).to be_nil
    expect(CalibratedClassifierCV.new(LinearRegression.new, :sigmoid, 2).fit(
      CalibrationFixture.binary_x,
      CalibrationFixture.binary_y
    )).to be_nil
    expect(CalibratedClassifierCV.new(DecisionTreeClassifier.new, :sigmoid, 3).fit(
      CalibrationFixture.binary_x,
      CalibrationFixture.binary_y,
      [1]
    )).to be_nil

spec_summary
