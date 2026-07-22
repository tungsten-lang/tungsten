# Preprocessing specs — Scaler / Encoder / Imputer / Splitter /
# Pipeline (and Stats.mode), on the tungsten-spec framework.
#
# Run from the repo root (both engines, exit 0 = green):
#   bin/tungsten bits/tungsten-koala/spec/preprocessing_spec.w
#   bin/tungsten -o /tmp/prep_spec bits/tungsten-koala/spec/preprocessing_spec.w && /tmp/prep_spec
#
# Values are hand-computed on integer-friendly inputs so float results
# are exact ([2, 4, 6] standard-scales to exactly [-1, 0, 1]). String
# arrays are compared via join (compiled to_s prints them unquoted);
# nils are element-checked with be_nil (nil stringification differs
# per engine).

use spec
use koala

describe "Stats.mode" ->
  it "returns the most frequent value" ->
    expect(Stats.mode([1, 2, 2, 3])).to eq(2)

  it "breaks ties toward the first-seen value" ->
    expect(Stats.mode([3, 1, 1, 3])).to eq(3)

  it "ignores nils and handles strings" ->
    expect(Stats.mode(["a", nil, "b", "a"])).to eq("a")

  it "returns nil for an all-nil array" ->
    expect(Stats.mode([nil])).to be_nil

describe "Scaler" ->
  it "standard-scales a column to mean 0 and var 1" ->
    df = DataFrame.new([[:x, [2, 4, 6]]])
    sc = Scaler.new(:standard)
    out = sc.fit_transform(df)
    vals = out.column_values(:x)
    expect(vals.join(",")).to eq("-1,0,1")
    expect(Stats.mean(vals).to_s).to eq("0")
    expect(Stats.var(vals).to_s).to eq("1")

  it "min-max scales a column into 0..1" ->
    df = DataFrame.new([[:x, [10, 15, 20]]])
    sc = Scaler.new(:min_max)
    out = sc.fit_transform(df)
    expect(out.column_values(:x).join(",")).to eq("0,0.5,1")

  it "maps a zero-spread column to 0.0" ->
    df = DataFrame.new([[:x, [7, 7, 7]]])
    out = Scaler.new(:min_max).fit_transform(df)
    expect(out.column_values(:x).join(",")).to eq("0,0,0")

  it "keeps nil cells nil" ->
    df = DataFrame.new([[:x, [2, nil, 4, 6]]])
    out = Scaler.new(:standard).fit_transform(df)
    vals = out.column_values(:x)
    expect(vals[0].to_s).to eq("-1")
    expect(vals[1]).to be_nil
    expect(vals[2].to_s).to eq("0")
    expect(vals[3].to_s).to eq("1")

  it "scales only the requested columns" ->
    df = DataFrame.new([[:a, [2, 4, 6]], [:b, [1, 2, 3]]])
    out = Scaler.new(:standard, [:a]).fit_transform(df)
    expect(out.column_values(:a).join(",")).to eq("-1,0,1")
    expect(out.column_values(:b).join(",")).to eq("1,2,3")
    expect(out.column_names.join(",")).to eq("a,b")

  it "reuses training parameters on a new frame" ->
    sc = Scaler.new(:standard)
    sc.fit(DataFrame.new([[:x, [2, 4, 6]]]))
    out = sc.transform(DataFrame.new([[:x, [8, 4]]]))
    expect(out.column_values(:x).join(",")).to eq("2,0")

  it "exposes fitted params as name/a/b triples" ->
    sc = Scaler.new(:standard)
    sc.fit(DataFrame.new([[:x, [2, 4, 6]]]))
    p = sc.params
    expect(p.size).to eq(1)
    expect(p[0][0].to_s).to eq("x")
    expect(p[0][1].to_s).to eq("4")
    expect(p[0][2].to_s).to eq("2")

  it "skips non-numeric columns in a mixed frame" ->
    df = DataFrame.new([
      [:name, ["Alice", "Bob", "Carol"]],
      [:salary, [80, 65, 95]]
    ])
    out = Scaler.new(:min_max).fit_transform(df)
    expect(out.column_values(:name).join(",")).to eq("Alice,Bob,Carol")
    expect(out.column_values(:salary).join(",")).to eq("0.5,0,1")

  it "returns nil from transform before fit" ->
    sc = Scaler.new(:standard)
    expect(sc.fitted?).to be_false
    expect(sc.transform(DataFrame.new([[:x, [1]]]))).to be_nil

describe "Encoder" ->
  it "label-encodes with first-seen category order" ->
    df = DataFrame.new([[:color, ["red", "blue", "red", "green"]]])
    enc = Encoder.new(:label, [:color])
    out = enc.fit_transform(df)
    expect(out.column_values(:color).join(",")).to eq("0,1,0,2")
    expect(enc.categories(:color).join(",")).to eq("red,blue,green")

  it "encodes unseen and nil values to nil" ->
    enc = Encoder.new(:label, [:color])
    enc.fit(DataFrame.new([[:color, ["red", "blue"]]]))
    out = enc.transform(DataFrame.new([[:color, ["purple", "red", nil]]]))
    vals = out.column_values(:color)
    expect(vals[0]).to be_nil
    expect(vals[1]).to eq(0)
    expect(vals[2]).to be_nil

  it "one-hot encodes in place with documented column order" ->
    df = DataFrame.new([
      [:id, [1, 2, 3]],
      [:color, ["red", "blue", "red"]],
      [:z, [7, 8, 9]]
    ])
    out = Encoder.new(:one_hot, [:color]).fit_transform(df)
    expect(out.column_names.join(",")).to eq("id,color_red,color_blue,z")
    expect(out.column_values("color_red").join(",")).to eq("1,0,1")
    expect(out.column_values("color_blue").join(",")).to eq("0,1,0")
    expect(out.column_values(:id).join(",")).to eq("1,2,3")
    expect(out.column_values(:z).join(",")).to eq("7,8,9")

  it "one-hot encodes a nil cell as all zeros" ->
    df = DataFrame.new([[:color, ["red", nil]]])
    out = Encoder.new(:one_hot, [:color]).fit_transform(df)
    expect(out.column_names.join(",")).to eq("color_red")
    expect(out.column_values("color_red").join(",")).to eq("1,0")

  it "returns nil from transform before fit" ->
    enc = Encoder.new(:one_hot, [:color])
    expect(enc.transform(DataFrame.new([[:color, ["red"]]]))).to be_nil

describe "Imputer" ->
  it "fills nils with the column mean" ->
    df = DataFrame.new([[:x, [1, nil, 3]]])
    out = Imputer.new(:mean).fit_transform(df)
    expect(out.column_values(:x).join(",")).to eq("1,2,3")

  it "fills nils with the column median" ->
    df = DataFrame.new([[:x, [1, nil, 3, 100]]])
    out = Imputer.new(:median).fit_transform(df)
    expect(out.column_values(:x).join(",")).to eq("1,3,3,100")

  it "fills nils with the column mode (strings too)" ->
    df = DataFrame.new([[:s, ["a", nil, "b", "a"]]])
    out = Imputer.new(:mode).fit_transform(df)
    expect(out.column_values(:s).join(",")).to eq("a,a,b,a")

  it "fills nils with a constant" ->
    df = DataFrame.new([[:x, [nil, 5]]])
    out = Imputer.new(:constant, nil, 0).fit_transform(df)
    expect(out.column_values(:x).join(",")).to eq("0,5")

  it "leaves an all-nil column unchanged under :mean" ->
    df = DataFrame.new([[:x, [nil, nil]]])
    out = Imputer.new(:mean).fit_transform(df)
    vals = out.column_values(:x)
    expect(vals[0]).to be_nil
    expect(vals[1]).to be_nil

  it "imputes a test frame with TRAINING statistics" ->
    imp = Imputer.new(:mean)
    imp.fit(DataFrame.new([[:x, [2, 4, nil]]]))
    out = imp.transform(DataFrame.new([[:x, [nil, 10]]]))
    expect(out.column_values(:x).join(",")).to eq("3,10")

  it "imputes only the requested columns" ->
    df = DataFrame.new([[:a, [nil, 2]], [:b, [nil, 4]]])
    out = Imputer.new(:mean, [:a]).fit_transform(df)
    expect(out.column_values(:a).join(",")).to eq("2,2")
    expect(out.column_values(:b)[0]).to be_nil

  it "skips non-numeric columns under :mean in a mixed frame" ->
    df = DataFrame.new([[:s, ["a", nil]], [:x, [nil, 4]]])
    out = Imputer.new(:mean).fit_transform(df)
    expect(out.column_values(:s)[1]).to be_nil
    expect(out.column_values(:x).join(",")).to eq("4,4")

  it "returns nil from transform before fit" ->
    imp = Imputer.new(:mean)
    expect(imp.transform(DataFrame.new([[:x, [1]]]))).to be_nil

describe "Splitter" ->
  it "splits head/tail in order when unseeded" ->
    df = DataFrame.new([[:i, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]]])
    pair = Splitter.train_test(df, 30)
    train = pair[0]
    test = pair[1]
    expect(train.row_count).to eq(7)
    expect(test.row_count).to eq(3)
    expect(train.column_values(:i).join(",")).to eq("0,1,2,3,4,5,6")
    expect(test.column_values(:i).join(",")).to eq("7,8,9")

  it "shuffles reproducibly with a seed" ->
    df = DataFrame.new([[:i, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]]])
    pair = Splitter.train_test(df, 30, 42)
    expect(pair[0].column_values(:i).join(",")).to eq("0,1,4,3,8,9,7")
    expect(pair[1].column_values(:i).join(",")).to eq("5,6,2")
    again = Splitter.train_test(df, 30, 42)
    expect(again[0].column_values(:i).join(",")).to eq("0,1,4,3,8,9,7")
    expect(again[1].column_values(:i).join(",")).to eq("5,6,2")

  it "clamps the test percent to 0..100" ->
    df = DataFrame.new([[:i, [0, 1, 2]]])
    none = Splitter.train_test(df, 0)
    expect(none[0].row_count).to eq(3)
    expect(none[1].row_count).to eq(0)
    all = Splitter.train_test(df, 100)
    expect(all[0].row_count).to eq(0)
    expect(all[1].row_count).to eq(3)

  it "splits every nth row deterministically" ->
    df = DataFrame.new([[:i, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]]])
    pair = Splitter.every_nth(df, 3)
    expect(pair[1].column_values(:i).join(",")).to eq("0,3,6,9")
    expect(pair[0].column_values(:i).join(",")).to eq("1,2,4,5,7,8")
    offset = Splitter.every_nth(df, 3, 1)
    expect(offset[1].column_values(:i).join(",")).to eq("1,4,7")

  it "produces identity indices when unseeded" ->
    expect(Splitter.indices(4).join(",")).to eq("0,1,2,3")

describe "Pipeline" ->
  it "chains imputer and scaler end to end" ->
    df = DataFrame.new([[:x, [2, nil, 6]]])
    pipe = Pipeline.new([Imputer.new(:mean), Scaler.new(:standard)])
    expect(pipe.fitted?).to be_false
    out = pipe.fit_transform(df)
    expect(pipe.fitted?).to be_true
    expect(out.column_values(:x).join(",")).to eq("-1,0,1")

  it "replays training parameters on a new frame" ->
    pipe = Pipeline.new([Imputer.new(:mean), Scaler.new(:standard)])
    pipe.fit(DataFrame.new([[:x, [2, nil, 6]]]))
    out = pipe.transform(DataFrame.new([[:x, [8, nil]]]))
    expect(out.column_values(:x).join(",")).to eq("2,0")

  it "exposes its steps" ->
    pipe = Pipeline.new([Imputer.new(:median), Scaler.new(:min_max)])
    expect(pipe.size).to eq(2)
    expect(pipe[0].strategy.to_s).to eq("median")
    expect(pipe[1].kind.to_s).to eq("min_max")

  it "returns nil from transform before fit" ->
    pipe = Pipeline.new([Scaler.new(:standard)])
    expect(pipe.transform(DataFrame.new([[:x, [1]]]))).to be_nil

# Named steps — a chain addressed by meaning, not by position. Names
# normalize to STRINGS (a symbol and a string address the same step),
# so they are compared through join like every other string array.
describe "Pipeline named steps" ->
  it "names steps given as name/step pairs" ->
    pipe = Pipeline.new([[:impute, Imputer.new(:mean)], [:scale, Scaler.new(:standard)]])
    expect(pipe.names.join(",")).to eq("impute,scale")
    expect(pipe.size).to eq(2)
    out = pipe.fit_transform(DataFrame.new([[:x, [2, nil, 6]]]))
    expect(out.column_values(:x).join(",")).to eq("-1,0,1")

  it "addresses a step by symbol, by string and by position alike" ->
    pipe = Pipeline.new([[:impute, Imputer.new(:median)], [:scale, Scaler.new(:min_max)]])
    expect(pipe.step(:scale).kind.to_s).to eq("min_max")
    expect(pipe.step("scale").kind.to_s).to eq("min_max")
    expect(pipe[1].kind.to_s).to eq("min_max")
    expect(pipe.has_step?(:impute)).to be_true
    expect(pipe.has_step?("impute")).to be_true
    expect(pipe.has_step?(:nothing)).to be_false
    expect(pipe.step(:nothing)).to be_nil

  # The bare-array form is unchanged and gets names derived for it: an
  # estimator by its own downcased estimator_name, anything else by its
  # position, so the auto name mirrors pipe[i].
  it "derives names for the bare-array form" ->
    pipe = Pipeline.new([Imputer.new(:mean), Scaler.new(:standard), LinearRegression.new])
    expect(pipe.names.join(",")).to eq("step_0,step_1,linearregression")
    expect(pipe.step("step_0").strategy.to_s).to eq("mean")
    expect(pipe.step("step_1").kind.to_s).to eq("standard")
    expect(pipe.step("linearregression").alpha).to eq(0)
    expect(pipe[0].strategy.to_s).to eq("mean")

  it "de-duplicates a repeated name by suffix" ->
    pipe = Pipeline.new([LinearRegression.new(1), LinearRegression.new(2)])
    expect(pipe.names.join(",")).to eq("linearregression,linearregression_2")
    expect(pipe.step("linearregression").alpha).to eq(1)
    expect(pipe.step("linearregression_2").alpha).to eq(2)
    named = Pipeline.new([[:s, Scaler.new(:standard)], [:s, Scaler.new(:min_max)]])
    expect(named.names.join(",")).to eq("s,s_2")
    expect(named.step(:s).kind.to_s).to eq("standard")
    expect(named.step("s_2").kind.to_s).to eq("min_max")

  it "mixes named and bare entries in one chain" ->
    pipe = Pipeline.new([[:impute, Imputer.new(:mean)], Scaler.new(:standard)])
    expect(pipe.names.join(",")).to eq("impute,step_1")
    expect(pipe.step(:impute).strategy.to_s).to eq("mean")
    out = pipe.fit_transform(DataFrame.new([[:x, [2, nil, 6]]]))
    expect(out.column_values(:x).join(",")).to eq("-1,0,1")

  it "names an empty chain not at all" ->
    pipe = Pipeline.new([])
    expect(pipe.names.join(",")).to eq("")
    expect(pipe.size).to eq(0)

# --- A Pipeline IS an Estimable (lib/estimator_base.w) ---
#
# The point of the whole contract: a chain answers the same interface as
# a bare estimator, so generic tooling drives it without knowing
# pipelines exist. Step parameters are addressed "<step>.<param>", the
# dot chosen because it reads as attribute access, cannot occur inside a
# param name, and nests for free.
#
# The TUNABLE SURFACE is the steps answering BOTH params and
# with_params. koala's transformers answer neither in the hyperparameter
# sense — Scaler#params reports FITTED state, and there is no
# with_params — so they contribute no keys, which is exactly what keeps
# params/with_params round-tripping.
#
# params is compared PER KEY, never as a whole-hash string — hash to_s
# key order differs between the two engines.
describe "Pipeline as an Estimable" ->
  it "answers the whole Estimable contract" ->
    pipe = Pipeline.new([[:scale, Scaler.new(:standard)], [:model, LinearRegression.new]])
    missing = []
    missing.push("fitted?") if !pipe.respond_to?("fitted?")
    missing.push("predict") if !pipe.respond_to?("predict")
    missing.push("supervised?") if !pipe.respond_to?("supervised?")
    missing.push("params") if !pipe.respond_to?("params")
    missing.push("with_params") if !pipe.respond_to?("with_params")
    missing.push("estimator_name") if !pipe.respond_to?("estimator_name")
    expect(missing.join(",")).to eq("")
    expect(pipe.estimator_name).to eq("Pipeline")

  # The fit ARITY is the tail's to decide, which is why a Pipeline
  # declares only `is Estimable` and reports the rest at runtime.
  it "delegates supervised? to the tail step" ->
    expect(Pipeline.new([Scaler.new(:standard), LinearRegression.new]).supervised?).to be_true
    expect(Pipeline.new([Scaler.new(:standard), KNNClassifier.new(1)]).supervised?).to be_true
    expect(Pipeline.new([Scaler.new(:standard), KMeans.new(2)]).supervised?).to be_false
    expect(Pipeline.new([Scaler.new(:standard)]).supervised?).to be_false
    expect(Pipeline.new([]).supervised?).to be_false

  it "flattens step hyperparameters under the step name and a dot" ->
    pipe = Pipeline.new([[:scale, Scaler.new(:standard)], [:model, LinearRegression.new(3)]])
    expect(pipe.params.size).to eq(1)
    expect(pipe.params["model.alpha"]).to eq(3)
    bare = Pipeline.new([Scaler.new(:standard), LinearRegression.new(4)])
    expect(bare.params["linearregression.alpha"]).to eq(4)

  # Scaler answers params (fitted triples) but no with_params, so it is
  # NOT tunable and contributes nothing — reporting a key that
  # with_params could not apply would break the round-trip.
  it "leaves steps outside the hyperparameter contract out of params" ->
    pipe = Pipeline.new([[:scale, Scaler.new(:standard)], [:model, LinearRegression.new(3)]])
    expect(pipe.params.key?("scale.kind")).to be_false
    expect(pipe.params.key?("model.alpha")).to be_true
    expect(Pipeline.new([Scaler.new(:standard), Imputer.new(:mean)]).params.size).to eq(0)

  it "flattens several steps at once, each under its own name" ->
    pipe = Pipeline.new([[:lin, LinearRegression.new(1)], [:clust, KMeans.new(2, 7, 50)]])
    expect(pipe.params.size).to eq(4)
    expect(pipe.params["lin.alpha"]).to eq(1)
    expect(pipe.params["clust.k"]).to eq(2)
    expect(pipe.params["clust.seed"]).to eq(7)
    expect(pipe.params["clust.max_iter"]).to eq(50)

  it "rebuilds the addressed step and leaves the original untouched" ->
    proto = Pipeline.new([[:scale, Scaler.new(:standard)], [:model, LinearRegression.new(2)]])
    tuned = proto.with_params({ "model.alpha" => 10 })
    expect(tuned.params["model.alpha"]).to eq(10)
    expect(tuned.step(:model).alpha).to eq(10)
    expect(proto.params["model.alpha"]).to eq(2)
    expect(proto.step(:model).alpha).to eq(2)
    expect(tuned.names.join(",")).to eq("scale,model")
    expect(tuned.size).to eq(2)

  it "carries unmentioned keys over and ignores keys addressing nothing" ->
    pipe = Pipeline.new([[:lin, LinearRegression.new(1)], [:clust, KMeans.new(2, 7, 50)]])
    tuned = pipe.with_params({ "clust.k" => 5 })
    expect(tuned.params["clust.k"]).to eq(5)
    expect(tuned.params["clust.seed"]).to eq(7)
    expect(tuned.params["clust.max_iter"]).to eq(50)
    expect(tuned.params["lin.alpha"]).to eq(1)
    ignored = pipe.with_params({ "nosuchstep.k" => 9, "clust.nosuchparam" => 9 })
    expect(ignored.params.size).to eq(4)
    expect(ignored.params["clust.k"]).to eq(2)
    rt = pipe.with_params(pipe.params)
    expect(rt.params["clust.k"]).to eq(2)
    expect(rt.params["lin.alpha"]).to eq(1)

  it "returns a fresh UNFITTED pipeline from with_params" ->
    df = DataFrame.new([[:x, [2, 4, 6]]])
    y = [5, 9, 13]
    proto = Pipeline.new([[:scale, Scaler.new(:standard)], [:model, LinearRegression.new]])
    expect(proto.fit(df, y) != nil).to be_true
    expect(proto.fitted?).to be_true
    tuned = proto.with_params({ "model.alpha" => 1 })
    expect(tuned.fitted?).to be_false
    expect(tuned.step(:model).fitted?).to be_false
    expect(tuned.predict(df)).to be_nil
    expect(proto.fitted?).to be_true
    expect(tuned.fit(df, y) != nil).to be_true
    expect(tuned.fitted?).to be_true

  # A pipeline inside a pipeline flattens to "inner.model.alpha" — each
  # level only prefixes its own step name.
  it "nests, flattening an inner pipeline under its own step name" ->
    inner = Pipeline.new([[:model, LinearRegression.new(3)]])
    outer = Pipeline.new([[:pre, Scaler.new(:standard)], [:inner, inner]])
    expect(outer.params.size).to eq(1)
    expect(outer.params["inner.model.alpha"]).to eq(3)
    tuned = outer.with_params({ "inner.model.alpha" => 42 })
    expect(tuned.params["inner.model.alpha"]).to eq(42)
    expect(tuned.step(:inner).step(:model).alpha).to eq(42)
    expect(outer.params["inner.model.alpha"]).to eq(3)

  # The payoff, end to end: a sweep that knows ONLY params /
  # with_params / supervised? tunes a whole chain. It never names
  # Pipeline, Scaler or LinearRegression — Estimator.fit_model and
  # .score_model do the arity dispatch, exactly as they do for a bare
  # estimator. y = 2x + 1 is exact, so plain OLS (alpha 0) wins with
  # R² = 1 and the ridge candidates score lower.
  it "tunes a whole pipeline through the contract alone" ->
    df = DataFrame.new([[:x, [0 - 3, 0 - 1, 1, 3]]])
    y = [0 - 5, 0 - 1, 3, 7]
    proto = Pipeline.new([[:scale, Scaler.new(:standard)], [:model, LinearRegression.new]])
    expect(proto.params.key?("model.alpha")).to be_true
    tried = []
    best_alpha = nil
    best_score = nil
    grid = [0, 1, 10]
    grid.each -> (a)
      cand = proto.with_params({ "model.alpha" => a })
      done = Estimator.fit_model(cand, df, y)
      s = nil
      s = Estimator.score_model(cand, df, y) if done != nil
      if s != nil
        tried.push(a)
        better = false
        better = true if best_score == nil
        better = true if best_score != nil && s > best_score
        if better
          best_score = s
          best_alpha = a
    expect(tried.join(",")).to eq("0,1,10")
    expect(best_alpha).to eq(0)
    expect(best_score.to_s).to eq("1")
    expect(proto.fitted?).to be_false
    expect(proto.params["model.alpha"]).to eq(0)

spec_summary
