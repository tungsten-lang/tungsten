# Kernel support-vector classifier specs.
#
# Run from the repository root on both engines:
#   bin/tungsten bits/tungsten-koala/spec/svc_spec.w
#   bin/tungsten compile bits/tungsten-koala/spec/svc_spec.w \
#     --out /tmp/koala-svc-spec && /tmp/koala-svc-spec

use spec
use koala
use support

+ SVCFixture
  -> .xor_x
    [[0 - 1, 0 - 1], [0 - 1, 1], [1, 0 - 1], [1, 1]]

  -> .xor_y
    [:same, :different, :different, :same]

  -> .repeated_xor_x
    [[0 - 1, 0 - 1], [0 - 1, 1], [1, 0 - 1], [1, 1],
     [0 - 1, 0 - 1], [0 - 1, 1], [1, 0 - 1], [1, 1],
     [0 - 1, 0 - 1], [0 - 1, 1], [1, 0 - 1], [1, 1]]

  -> .repeated_xor_y
    [:same, :different, :different, :same,
     :same, :different, :different, :same,
     :same, :different, :different, :same]

  -> .multiclass_x
    [[0 - 3, 0 - 3], [0 - 3, 0 - 2], [0 - 2, 0 - 3], [0 - 2, 0 - 2],
     [2, 2], [2, 3], [3, 2], [3, 3],
     [2, 0 - 3], [2, 0 - 2], [3, 0 - 3], [3, 0 - 2]]

  -> .multiclass_y
    [:west, :west, :west, :west,
     :north, :north, :north, :north,
     :south, :south, :south, :south]

  -> .threshold_x
    [[0], [1], [2], [3], [4], [5], [6], [7], [8], [9], [10], [11]]

  -> .threshold_y
    [:cold, :cold, :cold, :cold, :cold, :cold,
     :hot, :hot, :hot, :hot, :hot, :hot]

-> svc_close(a, b)
  LinAlg.fabs(a.to_f - b.to_f) < 1.to_f / 1000000000.to_f

describe "SVC kernels and binary margin" ->
  it "computes linear, RBF, and polynomial kernels" ->
    left = [1, 2]
    right = [3, 4]
    expect(SupportVectorMachine.kernel_value(
      left, right, { kernel: "linear", gamma: 1, degree: 2, coef0: 0 }
    )).to eq(11)
    expect(svc_close(SupportVectorMachine.kernel_value(
      left, left, { kernel: "rbf", gamma: 2, degree: 2, coef0: 0 }
    ), 1)).to be_true
    expect(SupportVectorMachine.kernel_value(
      left, right, { kernel: "poly", gamma: 2, degree: 2, coef0: 1 }
    )).to eq(529)

  it "matches sklearn gamma auto and scale definitions" ->
    rows = [[0, 0], [2, 2]]
    expect(svc_close(SupportVectorMachine.resolved_gamma(:auto, rows), 1.to_f / 2.to_f)).to be_true
    expect(svc_close(SupportVectorMachine.resolved_gamma(:scale, rows), 1.to_f / 2.to_f)).to be_true
    expect(svc_close(SupportVectorMachine.resolved_gamma(:scale, [[7, 7], [7, 7]]), 1)).to be_true

  it "solves the hand-computed two-point hard margin" ->
    model = SVC.new(1, :linear)
    expect(model.fit([[0 - 1], [1]], [:left, :right])).not_to be_nil
    expect(model.support_indices.join(",")).to eq("0,1")
    expect(model.dual_coef[0].to_s).to be_nums("\[-0.5, 0.5\]")
    expect(model.intercept[0].to_s).to be_num("0")
    expect(model.decision_function([[0 - 1], [1]]).to_s).to be_nums("\[-1, 1\]")
    expect(model.predict([[0 - 1], [1]]).join(",")).to eq("left,right")

  it "fits an ordinary separable binary problem with opaque labels" ->
    x = [[0 - 3], [0 - 2], [0 - 1], [1], [2], [3]]
    y = [:cold, :cold, :cold, :hot, :hot, :hot]
    model = SVC.new(1, :linear)
    expect(model.fit(x, y)).not_to be_nil
    expect(model.classes.join(",")).to eq("cold,hot")
    expect(model.predict(x).join(",")).to eq(y.join(","))
    expect(model.score(x, y)).to eq(1)
    expect(model.decision_function([[0 - 2]])[0] < 0.to_f).to be_true
    expect(model.decision_function([[2]])[0] > 0.to_f).to be_true

  it "fits contradictory duplicate rows at the soft-margin box boundary" ->
    model = SVC.new(1, :linear)
    expect(model.fit([[0], [0]], [:left, :right])).not_to be_nil
    expect(model.support_indices.join(",")).to eq("0,1")
    expect(model.dual_coef[0].to_s).to be_nums("\[-1, 1\]")
    expect(model.decision_function([[0]])[0]).to eq(0)
    expect(model.score([[0], [0]], [:left, :right])).to eq(1.to_f / 2.to_f)

  it "uses an RBF boundary to solve XOR" ->
    linear = SVC.new(10, :linear)
    rbf = SVC.new(10, :rbf, 1)
    linear.fit(SVCFixture.xor_x, SVCFixture.xor_y)
    rbf.fit(SVCFixture.xor_x, SVCFixture.xor_y)
    expect(linear.score(SVCFixture.xor_x, SVCFixture.xor_y) < 1.to_f).to be_true
    expect(rbf.score(SVCFixture.xor_x, SVCFixture.xor_y)).to eq(1)
    expect(rbf.predict(SVCFixture.xor_x).join(",")).to eq(SVCFixture.xor_y.join(","))

  it "supports polynomial nonlinear boundaries" ->
    model = SVC.new(10, :poly, 1, 2, 1)
    expect(model.fit(SVCFixture.xor_x, SVCFixture.xor_y)).not_to be_nil
    expect(model.score(SVCFixture.xor_x, SVCFixture.xor_y)).to eq(1)

  it "is deterministic across complete model payloads" ->
    one = SVC.new(10, :rbf, 1)
    two = SVC.new(10, :rbf, 1)
    one.fit(SVCFixture.xor_x, SVCFixture.xor_y)
    two.fit(SVCFixture.xor_x, SVCFixture.xor_y)
    expect(Persist.dumps(one)).to eq(Persist.dumps(two))

  it "honors integer sample weights exactly like row duplication" ->
    x = [[0 - 2], [0 - 1], [1], [2]]
    y = [:left, :left, :right, :right]
    weighted = SVC.new(1, :linear)
    duplicated = SVC.new(1, :linear)
    weighted.fit(x, y, [2, 1, 1, 1])
    duplicated.fit([[0 - 2], [0 - 2], [0 - 1], [1], [2]],
                   [:left, :left, :left, :right, :right])
    expect(Persist.dumps(weighted)).to eq(Persist.dumps(duplicated))

describe "SVC multiclass and framework integration" ->
  it "fits one binary model for every class pair" ->
    model = SVC.new(2, :linear)
    expect(model.fit(SVCFixture.multiclass_x, SVCFixture.multiclass_y)).not_to be_nil
    expect(model.classes.join(",")).to eq("west,north,south")
    expect(model.estimators.size).to eq(3)
    expect(model.decision_function([[0 - 3, 0 - 3]])[0].size).to eq(3)
    expect(model.predict(SVCFixture.multiclass_x).join(",")).to eq(SVCFixture.multiclass_y.join(","))
    expect(model.score(SVCFixture.multiclass_x, SVCFixture.multiclass_y)).to eq(1)

  it "cross-validates a multiclass support-vector model" ->
    scores = CrossValidation.cross_val_score(
      SVC.new(2, :linear),
      SVCFixture.multiclass_x,
      SVCFixture.multiclass_y,
      StratifiedKFold.new(4)
    )
    expect(scores.size).to eq(4)
    expect(Stats.mean(scores) > 9.to_f / 10.to_f).to be_true

  it "selects RBF over linear through GridSearch on XOR" ->
    grid = GridSearch.new(
      SVC.new(10, :linear, 1),
      { kernel: [:linear, :rbf] },
      StratifiedKFold.new(3)
    )
    expect(grid.fit(SVCFixture.repeated_xor_x, SVCFixture.repeated_xor_y)).not_to be_nil
    expect(grid.best_params[:kernel]).to eq(:rbf)
    expect(grid.best_estimator.score(SVCFixture.repeated_xor_x, SVCFixture.repeated_xor_y)).to eq(1)

  it "composes with preprocessing in a Pipeline" ->
    pipe = Pipeline.new([
      [:scale, Scaler.new(:standard)],
      [:svc, SVC.new(2, :linear)]
    ])
    expect(pipe.fit(SVCFixture.multiclass_x, SVCFixture.multiclass_y)).not_to be_nil
    expect(pipe.predict(SVCFixture.multiclass_x).join(",")).to eq(SVCFixture.multiclass_y.join(","))
    expect(pipe.decision_function([[0 - 3, 0 - 3]])[0].size).to eq(3)
    expect(pipe.params["svc.c"]).to eq(2)

  it "calibrates binary margins into cross-fitted probabilities" ->
    calibrated = CalibratedClassifierCV.new(SVC.new(1, :linear), :sigmoid, 3)
    expect(calibrated.fit(SVCFixture.threshold_x, SVCFixture.threshold_y)).not_to be_nil
    probs = calibrated.predict_proba([[2], [9]])
    expect(probs.size).to eq(2)
    expect(svc_close(Stats.sum(probs[0]), 1)).to be_true
    expect(svc_close(Stats.sum(probs[1]), 1)).to be_true
    expect(calibrated.predict([[2], [9]]).join(",")).to eq("cold,hot")

  it "works with model-agnostic permutation importance" ->
    model = SVC.new(2, :linear)
    model.fit(SVCFixture.multiclass_x, SVCFixture.multiclass_y)
    result = PermutationImportance.compute(
      model, SVCFixture.multiclass_x, SVCFixture.multiclass_y, 4, 42
    )
    expect(result).not_to be_nil
    expect(result.importances_mean.size).to eq(2)
    expect(result.importances_mean[0] > 0.to_f).to be_true
    expect(result.importances_mean[1] > 0.to_f).to be_true

  it "persists binary and multiclass margins exactly" ->
    binary = SVC.new(10, :rbf, 1)
    binary.fit(SVCFixture.xor_x, SVCFixture.xor_y)
    binary_back = Persist.loads(Persist.dumps(binary))
    expect(binary_back.predict(SVCFixture.xor_x).to_s).to eq(binary.predict(SVCFixture.xor_x).to_s)
    expect(binary_back.decision_function(SVCFixture.xor_x).to_s).to eq(binary.decision_function(SVCFixture.xor_x).to_s)
    multi = SVC.new(2, :linear)
    multi.fit(SVCFixture.multiclass_x, SVCFixture.multiclass_y)
    multi_back = Persist.loads(Persist.dumps(multi))
    expect(multi_back.decision_function(SVCFixture.multiclass_x).to_s).to eq(
      multi.decision_function(SVCFixture.multiclass_x).to_s
    )

  it "exposes tunable constructor parameters on fresh clones" ->
    model = SVC.new(2, :rbf, :auto, 4, 1, 1.to_f / 100.to_f, 50)
    clone = model.with_params({ c: 7, kernel: :poly, degree: 2 })
    expect(model.params[:c]).to eq(2)
    expect(clone.params[:c]).to eq(7)
    expect(clone.params[:kernel]).to eq(:poly)
    expect(clone.params[:gamma]).to eq(:auto)
    expect(clone.params[:degree]).to eq(2)
    expect(clone.fitted?).to be_false
    expect(clone.estimator_name).to eq("SVC")
    expect(clone.supervised?).to be_true
    expect(clone.supports_sample_weight?).to be_true

describe "SVC validation" ->
  it "returns nil before fit and for malformed query widths" ->
    model = SVC.new
    expect(model.predict([[1]])).to be_nil
    expect(model.decision_function([[1]])).to be_nil
    model.fit([[0], [1]], [:a, :b])
    expect(model.predict([[1, 2]])).to be_nil
    expect(model.score([[0], [1]], [:a])).to be_nil

  it "rejects invalid hyperparameters" ->
    x = [[0], [1]]
    y = [:a, :b]
    expect(SVC.new(0).fit(x, y)).to be_nil
    expect(SVC.new(1, :unknown).fit(x, y)).to be_nil
    expect(SVC.new(1, :rbf, 0).fit(x, y)).to be_nil
    expect(SVC.new(1, :poly, 1, 0).fit(x, y)).to be_nil
    expect(SVC.new(1, :rbf, 1, 3, "bad").fit(x, y)).to be_nil
    expect(SVC.new(1, :rbf, 1, 3, 0, 0).fit(x, y)).to be_nil
    expect(SVC.new(1, :rbf, 1, 3, 0, 1, 0).fit(x, y)).to be_nil

  it "rejects empty, ragged, nonnumeric, misaligned, and one-class data" ->
    expect(SVC.new.fit([], [])).to be_nil
    expect(SVC.new.fit([[0], [1, 2]], [:a, :b])).to be_nil
    expect(SVC.new.fit([["x"], ["y"]], [:a, :b])).to be_nil
    expect(SVC.new.fit([[0], [1]], [:a])).to be_nil
    expect(SVC.new.fit([[0], [1]], [:a, :a])).to be_nil

  it "rejects malformed weights and classes removed by zero weights" ->
    x = [[0], [1], [2]]
    y = [:a, :a, :b]
    expect(SVC.new.fit(x, y, [1, 1])).to be_nil
    expect(SVC.new.fit(x, y, [1, 0 - 1, 1])).to be_nil
    expect(SVC.new.fit(x, y, [1, 1, 0])).to be_nil

  it "invalidates learned state after a failed refit" ->
    model = SVC.new(1, :linear)
    model.fit([[0 - 1], [1]], [:a, :b])
    expect(model.fitted?).to be_true
    expect(model.fit([[0]], [:a])).to be_nil
    expect(model.fitted?).to be_false
    expect(model.predict([[0]])).to be_nil
