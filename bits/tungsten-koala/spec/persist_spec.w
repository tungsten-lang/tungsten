# Persistence specs — Persist.dumps / Persist.loads, on the
# tungsten-spec framework.
#
# Run from the repo root (both engines, exit 0 = green):
#   bin/tungsten bits/tungsten-koala/spec/persist_spec.w
#   bin/tungsten -o /tmp/persist_spec bits/tungsten-koala/spec/persist_spec.w && /tmp/persist_spec
#
# THE PROPERTY UNDER TEST is not "dumps produced a string" — it is that a
# LOADED MODEL PREDICTS IDENTICALLY TO THE SAVED ONE. Every estimator, both
# transformers-in-a-chain and standalone, and a nested Pipeline are fitted,
# dumped, loaded, and their predictions compared EXACTLY (string equality on
# the joined prediction arrays — a serialization test, not a numerics test,
# so no tolerance is allowed anywhere in this file).
#
# Predictions are compared via `join` rather than `to_s`: compiled Array `==`
# is identity, and Array#to_s of STRINGS differs between the engines.
# Hyperparameters are compared per key, never as a whole-hash string, because
# hash key order is not portable. No float literal appears here.

use spec
use koala

# --- Shared fixtures -------------------------------------------------
#
# One two-feature frame drives every estimator: integer-valued, so the
# hand-checkable parts stay exact, but wide enough that a tree finds real
# splits and a ridge fit produces coefficients whose decimal form does NOT
# round-trip (which is the whole reason the format exists).

+ Fx
  -> .frame
    DataFrame.new([[:x, [1, 2, 3, 4, 5, 6, 7, 8]], [:z, [2, 1, 4, 3, 6, 5, 8, 7]]])

  -> .targets
    out = [3, 5, 8, 9, 12, 13, 17, 18]
    out

  -> .labels
    out = ["a", "a", "a", "b", "b", "b", "b", "a"]
    out

  # Rows the fit never saw — a loaded model has to agree on UNSEEN input,
  # not merely reproduce its training set.
  -> .queries
    out = [[2, 3], [5, 5], [7, 1], [3, 8]]
    out

  # A model dumped and loaded back, in one step.
  -> .cycle(model)
    Persist.loads(Persist.dumps(model))

  # Predictions as one comparable string.
  -> .preds(model)
    out = nil
    p = model.predict(Fx.queries)
    out = p.join(",") if p != nil
    out

describe "Persist format" ->
  it "stamps the payload with a name and a version" ->
    model = LinearRegression.new
    model.fit(Fx.frame, Fx.targets)
    text = Persist.dumps(model)
    expect(text.split("\n")[0]).to eq("koala-model 1")
    expect(Persist.header).to eq("koala-model 1")
    expect(Persist.version).to eq(1)

  it "names the saved class on the payload's object line" ->
    model = KMeans.new(2)
    model.fit(Fx.frame)
    expect(Persist.dumps(model).split("\n")[1]).to eq("o KMeans")

  it "is deterministic — the same model dumps to the same text twice" ->
    model = DecisionTreeClassifier.new(3)
    model.fit(Fx.frame, Fx.labels)
    expect(Persist.dumps(model)).to eq(Persist.dumps(model))

  it "round-trips a hard float through its readable decimal" ->
    v = 1.to_f / 3.to_f
    # Float#to_s now prints the full f64 (%.17g), so its decimal already
    # round-trips exactly on BOTH engines — persist stores that decimal.
    expect(v.to_s.to_f == v).to be_true
    lines = []
    lines.push(Persist.float_line(v))
    res = Persist.decode(lines, 0)
    expect(res[:ok]).to be_true
    expect(res[:v] == v).to be_true

  it "round-trips every awkward float exactly" ->
    vals = []
    vals.push(1.to_f / 3.to_f)
    vals.push(Math.sqrt(2.to_f))
    vals.push(0.to_f - (22.to_f / 7.to_f))
    vals.push(Math.exp(1.to_f))
    vals.push(Math.log(7.to_f) / 3.to_f)
    vals.push(1.to_f / 7.to_f * (1.to_f / 13.to_f))
    vals.push(0.to_f)
    vals.push(0.to_f - (5.to_f / 2.to_f))
    vals.push(123456789.to_f / 1000.to_f)
    exact = 0
    vals.each -> (v)
      lines = []
      lines.push(Persist.float_line(v))
      res = Persist.decode(lines, 0)
      exact += 1 if res[:ok] && res[:v] == v
    expect(exact).to eq(9)

  it "keeps a readable decimal when it provably round-trips" ->
    expect(Persist.float_line(5.to_f / 2.to_f)).to eq("d 2.5")
    expect(Persist.float_line(0.to_f)).to eq("d 0")

  it "writes the readable decimal now that Float#to_s round-trips" ->
    # %.17g makes every finite f64's decimal round-trip, so float_line
    # takes the "d" (decimal) branch; the "b" (exact-bits) branch remains
    # as a guard should to_s ever lose precision again.
    expect(Persist.float_line(1.to_f / 3.to_f).slice(0, 1)).to eq("d")

  it "escapes backslashes and newlines so a node stays on one line" ->
    raw = "a\\b\nc"
    esc = Persist.escape_text(raw)
    expect(esc.include?("\n")).to be_false
    expect(Persist.unescape_text(esc)).to eq(raw)

  it "round-trips a label carrying a newline through a whole model" ->
    frame = DataFrame.new([[:x, [1, 2, 3, 4]]])
    labels = ["one\ntwo", "one\ntwo", "b\\c", "b\\c"]
    model = KNNClassifier.new(1)
    model.fit(frame, labels)
    back = Fx.cycle(model)
    expect(back.predict([[1], [4]]).join("~")).to eq(model.predict([[1], [4]]).join("~"))
    expect(back.predict([[4]])[0]).to eq("b\\c")

describe "Persist round-trip: LinearRegression" ->
  it "predicts identically after a plain OLS fit" ->
    model = LinearRegression.new
    model.fit(Fx.frame, Fx.targets)
    back = Fx.cycle(model)
    expect(back).not_to be_nil
    expect(back.fitted?).to be_true
    expect(Fx.preds(back)).to eq(Fx.preds(model))

  it "predicts identically after a ridge fit, to the last bit" ->
    model = LinearRegression.new(1.to_f / 3.to_f)
    model.fit(Fx.frame, Fx.targets)
    back = Fx.cycle(model)
    expect(Fx.preds(back)).to eq(Fx.preds(model))
    expect(back.coefficients[0] == model.coefficients[0]).to be_true
    expect(back.coefficients[1] == model.coefficients[1]).to be_true
    expect(back.intercept == model.intercept).to be_true

  it "preserves the hyperparameters and the estimator identity" ->
    model = LinearRegression.new(7)
    model.fit(Fx.frame, Fx.targets)
    back = Fx.cycle(model)
    expect(back.params[:alpha]).to eq(7)
    expect(back.estimator_name).to eq("LinearRegression")
    expect(back.persist_name).to eq("LinearRegression")
    expect(back.supervised?).to be_true

describe "Persist round-trip: KNNClassifier" ->
  it "predicts identically — the stored training set survives" ->
    model = KNNClassifier.new(3)
    model.fit(Fx.frame, Fx.labels)
    back = Fx.cycle(model)
    expect(back.fitted?).to be_true
    expect(Fx.preds(back)).to eq(Fx.preds(model))
    expect(back.params[:k]).to eq(3)

describe "Persist round-trip: LogisticRegression" ->
  it "predicts identically, probabilities included" ->
    model = LogisticRegression.new
    model.fit(Fx.frame, Fx.labels)
    back = Fx.cycle(model)
    expect(back.fitted?).to be_true
    expect(Fx.preds(back)).to eq(Fx.preds(model))
    expect(back.predict_proba(Fx.queries).join(",")).to eq(model.predict_proba(Fx.queries).join(","))

  it "preserves the learning rate, the epochs and the class order" ->
    model = LogisticRegression.new(1.to_f / 4.to_f, 40)
    model.fit(Fx.frame, Fx.labels)
    back = Fx.cycle(model)
    expect(back.params[:learning_rate] == model.params[:learning_rate]).to be_true
    expect(back.params[:epochs]).to eq(40)
    expect(back.classes.join(",")).to eq(model.classes.join(","))

describe "Persist round-trip: GaussianNB" ->
  it "predicts identically — priors, means and variances all survive" ->
    model = GaussianNB.new
    model.fit(Fx.frame, Fx.labels)
    back = Fx.cycle(model)
    expect(back.fitted?).to be_true
    expect(Fx.preds(back)).to eq(Fx.preds(model))
    expect(back.epsilon == model.epsilon).to be_true
    expect(back.params[:var_smoothing] == model.params[:var_smoothing]).to be_true

describe "Persist round-trip: KMeans" ->
  it "assigns identical clusters — the unsupervised case" ->
    model = KMeans.new(2)
    model.fit(Fx.frame)
    back = Fx.cycle(model)
    expect(back.fitted?).to be_true
    expect(back.supervised?).to be_false
    expect(Fx.preds(back)).to eq(Fx.preds(model))
    expect(back.inertia == model.inertia).to be_true
    expect(back.labels.join(",")).to eq(model.labels.join(","))
    expect(back.params[:k]).to eq(2)

describe "Persist round-trip: DecisionTreeClassifier" ->
  it "predicts identically — the recursive node structure survives" ->
    model = DecisionTreeClassifier.new(3)
    model.fit(Fx.frame, Fx.labels)
    back = Fx.cycle(model)
    expect(back.fitted?).to be_true
    expect(Fx.preds(back)).to eq(Fx.preds(model))

  it "reproduces the fitted tree's exact shape and thresholds" ->
    model = DecisionTreeClassifier.new(3)
    model.fit(Fx.frame, Fx.labels)
    back = Fx.cycle(model)
    expect(back.depth).to eq(model.depth)
    expect(back.node_count).to eq(model.node_count)
    expect(back.leaf_count).to eq(model.leaf_count)
    expect(back.tree_lines.join("|")).to eq(model.tree_lines.join("|"))
    expect(back.tree[:threshold] == model.tree[:threshold]).to be_true
    expect(back.tree[:left][:leaf]).to eq(model.tree[:left][:leaf])
    expect(back.predict_proba(Fx.queries, "a").join(",")).to eq(model.predict_proba(Fx.queries, "a").join(","))

  it "preserves all four hyperparameters and the class order" ->
    model = DecisionTreeClassifier.new(2, 3, 2, :entropy)
    model.fit(Fx.frame, Fx.labels)
    back = Fx.cycle(model)
    expect(back.params[:max_depth]).to eq(2)
    expect(back.params[:min_samples_split]).to eq(3)
    expect(back.params[:min_samples_leaf]).to eq(2)
    expect(back.params[:criterion].to_s).to eq("entropy")
    expect(back.classes.join(",")).to eq(model.classes.join(","))
    expect(Fx.preds(back)).to eq(Fx.preds(model))

  it "keeps an unlimited max_depth unlimited" ->
    model = DecisionTreeClassifier.new
    model.fit(Fx.frame, Fx.labels)
    back = Fx.cycle(model)
    expect(back.params[:max_depth]).to be_nil
    expect(Fx.preds(back)).to eq(Fx.preds(model))

describe "Persist round-trip: DecisionTreeRegressor" ->
  it "predicts identical piecewise-constant values" ->
    model = DecisionTreeRegressor.new(3)
    model.fit(Fx.frame, Fx.targets)
    back = Fx.cycle(model)
    expect(back.fitted?).to be_true
    expect(Fx.preds(back)).to eq(Fx.preds(model))
    expect(back.tree_lines.join("|")).to eq(model.tree_lines.join("|"))

  it "survives a weighted fit — the leaf means are floats, not counts" ->
    model = DecisionTreeRegressor.new(2)
    model.fit(Fx.frame, Fx.targets, [2, 1, 1, 3, 1, 1, 2, 1])
    back = Fx.cycle(model)
    expect(Fx.preds(back)).to eq(Fx.preds(model))
    expect(back.tree[:impurity] == model.tree[:impurity]).to be_true

describe "Persist round-trip: transformers" ->
  it "replays a Scaler's training mean and std" ->
    scale = Scaler.new(:standard)
    scale.fit(Fx.frame)
    back = Fx.cycle(scale)
    expect(back.fitted?).to be_true
    expect(back.transform(Fx.frame).column_values(:x).join(",")).to eq(scale.transform(Fx.frame).column_values(:x).join(","))
    expect(back.params[:kind].to_s).to eq("standard")
    expect(back.learned_params.size).to eq(scale.learned_params.size)

  it "replays an Imputer's training fill values" ->
    frame = DataFrame.new([[:x, [1, nil, 4, 7]]])
    fill = Imputer.new(:mean)
    fill.fit(frame)
    back = Fx.cycle(fill)
    expect(back.transform(frame).column_values(:x).join(",")).to eq(fill.transform(frame).column_values(:x).join(","))
    expect(back.params[:strategy].to_s).to eq("mean")

  it "replays an Encoder's first-seen category order" ->
    frame = DataFrame.new([[:c, ["red", "blue", "red", nil]]])
    enc = Encoder.new(:one_hot)
    enc.fit(frame)
    back = Fx.cycle(enc)
    expect(back.categories(:c).join(",")).to eq(enc.categories(:c).join(","))
    expect(back.transform(frame).column_names.join(",")).to eq(enc.transform(frame).column_names.join(","))
    expect(back.params[:kind].to_s).to eq("one_hot")

  it "keeps a column restriction" ->
    scale = Scaler.new(:min_max, [:x])
    scale.fit(Fx.frame)
    back = Fx.cycle(scale)
    expect(back.params[:columns].join(",")).to eq("x")
    expect(back.transform(Fx.frame).column_values(:z).join(",")).to eq("2,1,4,3,6,5,8,7")

describe "Persist round-trip: Pipeline" ->
  it "predicts identically on unseen rows — the steps' learned state survives" ->
    pipe = Pipeline.new([
      [:impute, Imputer.new(:mean)],
      [:scale, Scaler.new(:standard)],
      [:model, LinearRegression.new]
    ])
    pipe.fit(Fx.frame, Fx.targets)
    back = Fx.cycle(pipe)
    expect(back).not_to be_nil
    expect(back.fitted?).to be_true
    expect(Fx.preds(back)).to eq(Fx.preds(pipe))
    expect(back.names.join(",")).to eq("impute,scale,model")
    expect(back.size).to eq(3)

  it "keeps the whole tunable surface addressable after a load" ->
    pipe = Pipeline.new([[:scale, Scaler.new(:standard)], [:model, LinearRegression.new(2)]])
    pipe.fit(Fx.frame, Fx.targets)
    back = Fx.cycle(pipe)
    expect(back.params["model.alpha"]).to eq(2)
    expect(back.params.key?("scale.kind")).to be_true
    expect(back.step(:scale).fitted?).to be_true
    expect(back.supervised?).to be_true
    expect(back.supports_sample_weight?).to be_true

  it "nests — a Pipeline inside a Pipeline, tailed by a tree" ->
    inner = Pipeline.new([[:scale, Scaler.new(:min_max)]])
    outer = Pipeline.new([[:inner, inner], [:tree, DecisionTreeClassifier.new(2)]])
    outer.fit(Fx.frame, Fx.labels)
    back = Fx.cycle(outer)
    expect(back).not_to be_nil
    expect(Fx.preds(back)).to eq(Fx.preds(outer))
    expect(back.step(:inner).persist_name).to eq("Pipeline")
    expect(back.step(:tree).persist_name).to eq("DecisionTreeClassifier")

  it "scores identically to the model it was saved from" ->
    pipe = Pipeline.new([[:scale, Scaler.new(:standard)], [:model, LinearRegression.new]])
    pipe.fit(Fx.frame, Fx.targets)
    back = Fx.cycle(pipe)
    expect(back.score(Fx.frame, Fx.targets) == pipe.score(Fx.frame, Fx.targets)).to be_true

  it "carries a transformer-only chain, which has no predict" ->
    pipe = Pipeline.new([Imputer.new(:mean), Scaler.new(:standard)])
    pipe.fit_transform(Fx.frame)
    back = Fx.cycle(pipe)
    expect(back.fitted?).to be_true
    expect(back.supervised?).to be_false
    expect(back.predict(Fx.queries)).to be_nil
    expect(back.transform(Fx.frame).column_values(:x).join(",")).to eq(pipe.transform(Fx.frame).column_values(:x).join(","))

describe "Persist guards" ->
  it "refuses to dump an UNFITTED model" ->
    expect(Persist.dumps(LinearRegression.new)).to be_nil
    expect(Persist.dumps(Scaler.new(:standard))).to be_nil
    expect(Persist.dumps(Pipeline.new([Scaler.new(:standard)]))).to be_nil

  it "refuses to dump something that is not a koala model" ->
    expect(Persist.dumps(nil)).to be_nil
    expect(Persist.dumps(5)).to be_nil
    expect(Persist.dumps("a string")).to be_nil
    expect(Persist.dumps(DataFrame.new([[:x, [1]]]))).to be_nil

  it "answers nil for input that is not a payload" ->
    expect(Persist.loads(nil)).to be_nil
    expect(Persist.loads("")).to be_nil
    expect(Persist.loads("garbage")).to be_nil
    expect(Persist.loads(7)).to be_nil

  it "answers nil for a missing or unknown VERSION" ->
    model = LinearRegression.new
    model.fit(Fx.frame, Fx.targets)
    text = Persist.dumps(model)
    expect(Persist.loads(text.split("koala-model 1").join("koala-model 2"))).to be_nil
    expect(Persist.loads(text.split("koala-model 1").join("koala-model"))).to be_nil
    expect(Persist.loads(text.split("koala-model 1").join(""))).to be_nil

  it "still loads a payload that picked up a trailing newline" ->
    model = LinearRegression.new
    model.fit(Fx.frame, Fx.targets)
    text = Persist.dumps(model)
    expect(Fx.preds(Persist.loads(text + "\n"))).to eq(Fx.preds(model))
    expect(Fx.preds(Persist.loads(text + "\n\n"))).to eq(Fx.preds(model))

  it "answers nil for an unknown class name" ->
    model = LinearRegression.new
    model.fit(Fx.frame, Fx.targets)
    text = Persist.dumps(model)
    expect(Persist.loads(text.split("o LinearRegression").join("o Nonesuch"))).to be_nil

  it "answers nil for TRUNCATED input" ->
    model = DecisionTreeClassifier.new(3)
    model.fit(Fx.frame, Fx.labels)
    lines = Persist.dumps(model).split("\n")
    kept = []
    i = 0
    lines.each -> (line)
      kept.push(line) if i < lines.size - 1
      i += 1
    expect(Persist.loads(kept.join("\n"))).to be_nil
    expect(Persist.loads(lines[0])).to be_nil

  it "answers nil for CORRUPT input" ->
    model = LinearRegression.new
    model.fit(Fx.frame, Fx.targets)
    text = Persist.dumps(model)
    # trailing junk after a complete model
    expect(Persist.loads(text + "\ni 9")).to be_nil
    # a count that promises more nodes than the stream holds
    expect(Persist.loads(text.split("h 3").join("h 9"))).to be_nil
    # a number that is not one
    expect(Persist.loads(text.split("i 0").join("i zero"))).to be_nil
    # an object whose state is not a hash
    expect(Persist.loads(text.split("h 3").join("i 3"))).to be_nil

  it "does NOT silently mis-load a payload saved by a different class" ->
    lin = LinearRegression.new
    lin.fit(Fx.frame, Fx.targets)
    knn = KNNClassifier.new(3)
    knn.fit(Fx.frame, Fx.labels)
    lin_text = Persist.dumps(lin)
    knn_text = Persist.dumps(knn)
    # Relabel a LinearRegression body as a KNNClassifier and vice versa: the
    # loader checks that the state carries ITS OWN learned fields, so both
    # come back nil rather than as a model that answers predictions.
    expect(Persist.loads(lin_text.split("o LinearRegression").join("o KNNClassifier"))).to be_nil
    expect(Persist.loads(knn_text.split("o KNNClassifier").join("o LinearRegression"))).to be_nil
    expect(Persist.loads(lin_text.split("o LinearRegression").join("o DecisionTreeRegressor"))).to be_nil
    expect(Persist.loads(lin_text.split("o LinearRegression").join("o Pipeline"))).to be_nil
    # ... while the honest payloads still load as exactly what they are.
    expect(Persist.loads(lin_text).persist_name).to eq("LinearRegression")
    expect(Persist.loads(knn_text).persist_name).to eq("KNNClassifier")

  it "does not mis-load a transformer payload as another transformer" ->
    scale = Scaler.new(:standard)
    scale.fit(Fx.frame)
    text = Persist.dumps(scale)
    expect(Persist.loads(text.split("o Scaler").join("o Encoder"))).to be_nil
    expect(Persist.loads(text.split("o Scaler").join("o Imputer"))).to be_nil

describe "Persist in a workflow" ->
  it "trains once and serves many — a saved model needs no training data" ->
    trained = Pipeline.new([[:scale, Scaler.new(:standard)], [:model, LinearRegression.new]])
    trained.fit(Fx.frame, Fx.targets)
    shipped = Persist.dumps(trained)
    expect(shipped.size > 0).to be_true
    # A fresh process would have only `shipped` — no frame, no targets.
    served = Persist.loads(shipped)
    expect(served.predict(Fx.queries).join(",")).to eq(trained.predict(Fx.queries).join(","))
    # ... and re-dumping what was served reproduces the payload byte for byte.
    expect(Persist.dumps(served)).to eq(shipped)

  it "survives two full cycles unchanged" ->
    model = GaussianNB.new
    model.fit(Fx.frame, Fx.labels)
    once = Fx.cycle(model)
    twice = Fx.cycle(once)
    expect(Fx.preds(twice)).to eq(Fx.preds(model))
    expect(Persist.dumps(twice)).to eq(Persist.dumps(model))

spec_summary
