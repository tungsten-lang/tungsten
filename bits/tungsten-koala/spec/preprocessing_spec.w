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

# A pipeline step answering fit/transform and NOTHING of the Tunable
# pair. koala no longer ships one — Scaler, Imputer and Encoder all
# became Tunable — so the "step outside the hyperparameter contract"
# case, which Pipeline must keep out of its params and carry by
# reference, is exercised through this stub.
+ PassThrough
  -> new
    @fitted = false

  -> fitted?
    @fitted

  -> fit(df)
    @fitted = true
    self

  -> transform(df)
    df

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

  # What FIT learned answers to learned_params — NOT to params, which
  # reports the constructor knobs (see "Scaler is Tunable" below). The
  # two were one method once, and the fitted meaning lost: `params` means
  # "what you set" everywhere else in koala, and a Pipeline flattening a
  # step's `params` into its search space must never be handed state that
  # `with_params` cannot rebuild.
  it "exposes what fit learned as name/a/b triples" ->
    sc = Scaler.new(:standard)
    sc.fit(DataFrame.new([[:x, [2, 4, 6]]]))
    p = sc.learned_params
    expect(p.size).to eq(1)
    expect(p[0][0].to_s).to eq("x")
    expect(p[0][1].to_s).to eq("4")
    expect(p[0][2].to_s).to eq("2")

  it "learns nothing before fit" ->
    expect(Scaler.new(:standard).learned_params.size).to eq(0)

  # The transformers address columns BY NAME, but CrossValidation and
  # GridSearch coerce x to plain ROW ARRAYS before the model sees it —
  # so a Scaler inside a searched pipeline is handed rows, not a frame.
  # Estimator.frame names such columns x0, x1, … positionally.
  it "accepts plain row arrays, naming the columns positionally" ->
    out = Scaler.new(:standard).fit_transform([[2, 10], [4, 15], [6, 20]])
    expect(out.column_names.join(",")).to eq("x0,x1")
    expect(out.column_values("x0").join(",")).to eq("-1,0,1")
    expect(out.column_values("x1").join(",")).to eq("-1,0,1")

  it "accepts a flat array as one single-feature column" ->
    out = Scaler.new(:min_max).fit_transform([10, 15, 20])
    expect(out.column_names.join(",")).to eq("x0")
    expect(out.column_values("x0").join(",")).to eq("0,0.5,1")

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

  # Same split as Scaler's: the learned fill values answer to
  # learned_params, leaving `params` free to mean the knobs you set.
  it "exposes what fit learned as name/fill pairs" ->
    imp = Imputer.new(:mean)
    imp.fit(DataFrame.new([[:x, [2, 4, nil]]]))
    p = imp.learned_params
    expect(p.size).to eq(1)
    expect(p[0][0].to_s).to eq("x")
    expect(p[0][1].to_s).to eq("3")

  it "accepts plain row arrays, naming the columns positionally" ->
    out = Imputer.new(:mean).fit_transform([[2, 1], [nil, 3], [4, nil]])
    expect(out.column_names.join(",")).to eq("x0,x1")
    expect(out.column_values("x0").join(",")).to eq("2,3,4")
    expect(out.column_values("x1").join(",")).to eq("1,3,2")

# --- The Tunable contract (lib/estimator_base.w) ---
#
# Scaler / Imputer / Encoder carry REAL hyperparameters — the knobs their
# constructors take — so they answer `params` / `with_params`, the pair
# `trait Tunable` names. They stop there: a transformer has no predict
# and no fit ARITY to declare, so `Estimable` would be a lie for it.
#
# That pair is the whole entry fee for Pipeline's tunable surface, which
# is why "scale.kind" and "impute.strategy" become searchable below with
# no change to lib/pipeline.w or lib/grid_search.w.
#
# `params` is compared PER KEY, never as a whole-hash string — hash to_s
# key order differs between the engines. Nor is `estimator_name` added:
# the auto-naming of a BARE step reads it, so a Scaler answering it would
# silently rename "step_0" to "scaler".
describe "Transformers are Tunable" ->
  it "reports the constructor knobs as params" ->
    expect(Scaler.new(:min_max).params[:kind].to_s).to eq("min_max")
    expect(Scaler.new(:standard).params.size).to eq(2)
    expect(Scaler.new(:standard, [:a]).params[:columns].join(",")).to eq("a")
    expect(Scaler.new(:standard).params[:columns]).to be_nil
    expect(Imputer.new(:median).params[:strategy].to_s).to eq("median")
    expect(Imputer.new(:constant, nil, 7).params[:fill_value]).to eq(7)
    expect(Imputer.new(:mean).params.size).to eq(3)
    expect(Encoder.new(:one_hot).params[:kind].to_s).to eq("one_hot")
    expect(Encoder.new(:label, [:c]).params[:columns].join(",")).to eq("c")
    expect(Encoder.new(:label).params.size).to eq(2)

  it "declares the Tunable pair and nothing beyond it" ->
    missing = []
    extra = []
    steps = [Scaler.new(:standard), Imputer.new(:mean), Encoder.new(:label)]
    steps.each -> (s)
      missing.push("params") if !s.respond_to?("params")
      missing.push("with_params") if !s.respond_to?("with_params")
      extra.push("estimator_name") if s.respond_to?("estimator_name")
      extra.push("predict") if s.respond_to?("predict")
    expect(missing.join(",")).to eq("")
    expect(extra.join(",")).to eq("")

  # The clone semantics the whole search machinery leans on: overrides
  # applied, unmentioned keys carried, receiver untouched, result UNFITTED.
  it "clones fresh and UNFITTED from with_params, leaving self alone" ->
    sc = Scaler.new(:standard, [:a])
    sc.fit(DataFrame.new([[:a, [2, 4, 6]]]))
    expect(sc.fitted?).to be_true
    clone = sc.with_params({ kind: :min_max })
    expect(clone.kind.to_s).to eq("min_max")
    expect(clone.columns.join(",")).to eq("a")
    expect(clone.fitted?).to be_false
    expect(clone.learned_params.size).to eq(0)
    expect(sc.kind.to_s).to eq("standard")
    expect(sc.fitted?).to be_true

  it "clones an Imputer and an Encoder the same way" ->
    imp = Imputer.new(:mean)
    imp.fit(DataFrame.new([[:x, [2, nil]]]))
    ic = imp.with_params({ strategy: :constant, fill_value: 0 })
    expect(ic.strategy.to_s).to eq("constant")
    expect(ic.fill_value).to eq(0)
    expect(ic.fitted?).to be_false
    expect(imp.strategy.to_s).to eq("mean")
    expect(imp.fitted?).to be_true
    enc = Encoder.new(:label, [:c])
    enc.fit(DataFrame.new([[:c, ["a", "b"]]]))
    ec = enc.with_params({ kind: :one_hot })
    expect(ec.kind.to_s).to eq("one_hot")
    expect(ec.columns.join(",")).to eq("c")
    expect(ec.fitted?).to be_false
    expect(ec.categories(:c)).to be_nil
    expect(enc.kind.to_s).to eq("label")

  # Round-trip: with_params(params) reproduces the receiver's settings —
  # the property that lets Pipeline report a key it can also apply.
  it "round-trips through with_params(params)" ->
    sc = Scaler.new(:min_max, [:a, :b])
    rt = sc.with_params(sc.params)
    expect(rt.kind.to_s).to eq("min_max")
    expect(rt.columns.join(",")).to eq("a,b")
    imp = Imputer.new(:constant, [:x], 9)
    irt = imp.with_params(imp.params)
    expect(irt.strategy.to_s).to eq("constant")
    expect(irt.columns.join(",")).to eq("x")
    expect(irt.fill_value).to eq(9)
    enc = Encoder.new(:one_hot, [:c])
    ert = enc.with_params(enc.params)
    expect(ert.kind.to_s).to eq("one_hot")
    expect(ert.columns.join(",")).to eq("c")

  # Key PRESENCE decides, not the value — so an explicit nil really does
  # widen a column-restricted transformer back to every column.
  it "applies an override whose value is nil" ->
    widened = Scaler.new(:standard, [:a]).with_params({ columns: nil })
    expect(widened.columns).to be_nil
    expect(widened.kind.to_s).to eq("standard")
    out = widened.fit_transform(DataFrame.new([[:a, [2, 4, 6]], [:b, [2, 4, 6]]]))
    expect(out.column_values(:b).join(",")).to eq("-1,0,1")

  # The clone is a working transformer, not just a settings carrier.
  it "produces a clone that fits and transforms under the new setting" ->
    df = DataFrame.new([[:x, [10, 15, 20]]])
    proto = Scaler.new(:standard)
    tuned = proto.with_params({ kind: :min_max })
    expect(tuned.fit_transform(df).column_values(:x).join(",")).to eq("0,0.5,1")
    expect(proto.fit_transform(df).column_values(:x).join(",")).to eq("-1,0,1")

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
# with_params, and koala's bundled transformers now do (trait Tunable),
# so a Scaler named :scale contributes "scale.kind" / "scale.columns" and
# the PREPROCESSING is searchable alongside the model. That took no
# change to lib/pipeline.w — the rule was always stated in terms of the
# two methods, never a class. A step answering neither (PassThrough,
# above) is still excluded and carried by reference: reporting a key that
# with_params could not apply would break the round-trip.
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
    expect(pipe.params.size).to eq(3)
    expect(pipe.params["model.alpha"]).to eq(3)
    bare = Pipeline.new([Scaler.new(:standard), LinearRegression.new(4)])
    expect(bare.params["linearregression.alpha"]).to eq(4)

  # The gap this closed: the transformers are Tunable, so PREPROCESSING
  # joins the search space under its own step name. No class is named in
  # lib/pipeline.w — the surface is defined by the two methods alone.
  it "includes the transformer steps in params" ->
    pipe = Pipeline.new([[:scale, Scaler.new(:min_max)], [:model, LinearRegression.new(3)]])
    expect(pipe.params.key?("scale.kind")).to be_true
    expect(pipe.params["scale.kind"].to_s).to eq("min_max")
    expect(pipe.params.key?("scale.columns")).to be_true
    expect(pipe.params.key?("model.alpha")).to be_true
    pre = Pipeline.new([[:impute, Imputer.new(:median)], [:encode, Encoder.new(:one_hot)]])
    expect(pre.params.size).to eq(5)
    expect(pre.params["impute.strategy"].to_s).to eq("median")
    expect(pre.params["encode.kind"].to_s).to eq("one_hot")

  # ... and a transformer-only chain retunes and round-trips like any
  # other Estimable, with no estimator in sight.
  it "retunes a transformer-only chain" ->
    pre = Pipeline.new([[:impute, Imputer.new(:mean)], [:scale, Scaler.new(:standard)]])
    tuned = pre.with_params({ "impute.strategy" => :constant, "impute.fill_value" => 0, "scale.kind" => :min_max })
    expect(tuned.step(:impute).strategy.to_s).to eq("constant")
    expect(tuned.step(:impute).fill_value).to eq(0)
    expect(tuned.step(:scale).kind.to_s).to eq("min_max")
    expect(pre.step(:impute).strategy.to_s).to eq("mean")
    expect(pre.step(:scale).kind.to_s).to eq("standard")
    out = tuned.fit_transform(DataFrame.new([[:x, [nil, 10, 20]]]))
    expect(out.column_values(:x).join(",")).to eq("0,0.5,1")
    rt = pre.with_params(pre.params)
    expect(rt.params["impute.strategy"].to_s).to eq("mean")
    expect(rt.params["scale.kind"].to_s).to eq("standard")

  # A step answering NEITHER half stays out of the hash and is carried by
  # reference — the exclusion rule the surface has always rested on.
  it "leaves steps outside the hyperparameter contract out of params" ->
    pipe = Pipeline.new([[:pass, PassThrough.new], [:model, LinearRegression.new(3)]])
    expect(pipe.params.size).to eq(1)
    expect(pipe.params.key?("pass.kind")).to be_false
    expect(pipe.params.key?("model.alpha")).to be_true
    expect(Pipeline.new([PassThrough.new, PassThrough.new]).params.size).to eq(0)

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
    expect(outer.params.size).to eq(3)
    expect(outer.params["pre.kind"].to_s).to eq("standard")
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

# --- The payoff: GridSearch tunes the PREPROCESSING too ---
#
# One grid, two steps: the scaler's `kind` and the model's `alpha`,
# searched together by the stock GridSearch. Neither lib/grid_search.w
# nor lib/pipeline.w knows a Scaler exists — the transformers simply
# answer `params` / `with_params` now, and the tunable surface picked
# them up.
#
# THE WINNER, HAND-VERIFIED. Ridge shrinks the fitted slope by
# S / (S + alpha), where S is the training column's centred sum of
# squares AFTER scaling — so the scaler chosen decides how hard the same
# alpha bites. :standard divides by the sample std, leaving S = n - 1;
# :min_max divides by the range, leaving S = (n - 1) * std^2 / range^2.
# For x = +/-1, +/-3, +/-5, +/-7 the std is sqrt(24) ~ 4.9 and the range
# is 14, so min_max leaves S ~ 7 * 24/196 = 0.857 against standard's 7.
# Shrinkage (1.0 = no shrinkage = the exact y = 2x + 1 line = R^2 1):
#
#   alpha 1  / :standard  7/8      = 0.875   <- best
#   alpha 1  / :min_max   0.857/1.857 = 0.462
#   alpha 10 / :standard  7/17     = 0.412
#   alpha 10 / :min_max   0.857/10.857 = 0.079
#
# so the ranking is decided by BOTH knobs, and the search reproduces
# exactly that order. The winner is the SECOND candidate enumerated, not
# the first, so it cannot be the tie-break default; and it differs from
# the prototype (min_max, alpha 10) in BOTH parameters, so neither was
# carried over untouched.
describe "GridSearch tunes preprocessing and model together" ->
  it "searches a scaler param and a model param in one grid" ->
    df = DataFrame.new([[:x, [0 - 7, 0 - 5, 0 - 3, 0 - 1, 1, 3, 5, 7]]])
    y = [0 - 13, 0 - 9, 0 - 5, 0 - 1, 3, 7, 11, 15]
    proto = Pipeline.new([[:scale, Scaler.new(:min_max)], [:model, LinearRegression.new(10)]])
    expect(proto.params.key?("scale.kind")).to be_true
    expect(proto.params.key?("model.alpha")).to be_true

    gs = GridSearch.new(proto, { "scale.kind" => [:min_max, :standard], "model.alpha" => [1, 10] }, 2)
    expect(gs.size).to eq(4)

    # Enumeration order: keys sorted by NAME ("model.alpha" < "scale.kind"),
    # each value list as given, LAST key varying fastest.
    enumerated = []
    gs.candidates.each -> (c)
      enumerated.push(c["model.alpha"].to_s + "/" + c["scale.kind"].to_s)
    expect(enumerated.join(" ")).to eq("1/min_max 1/standard 10/min_max 10/standard")

    expect(gs.fit(df, y) != nil).to be_true
    expect(gs.fitted?).to be_true
    expect(gs.best_params["model.alpha"]).to eq(1)
    expect(gs.best_params["scale.kind"].to_s).to eq("standard")

    ranked = []
    gs.results.each -> (row)
      ranked.push(row[:params]["model.alpha"].to_s + "/" + row[:params]["scale.kind"].to_s)
    expect(ranked.join(" ")).to eq("1/standard 1/min_max 10/standard 10/min_max")
    expect(gs.results[0][:rank]).to eq(1)
    expect(gs.best_score > gs.results[1][:score]).to be_true

    # The refit winner is a working Pipeline carrying BOTH winning knobs.
    best = gs.best_estimator
    expect(best.estimator_name).to eq("Pipeline")
    expect(best.step(:scale).kind.to_s).to eq("standard")
    expect(best.step(:model).alpha).to eq(1)
    expect(best.fitted?).to be_true
    expect(gs.predict(df).size).to eq(8)

    # The prototype is never mutated — not its knobs, not its fitted state.
    expect(proto.step(:scale).kind.to_s).to eq("min_max")
    expect(proto.step(:model).alpha).to eq(10)
    expect(proto.fitted?).to be_false

  # The key check that makes the search above meaningful: GridSearch
  # verifies every grid key against estimator.params, so "scale.kind"
  # being accepted is proof the Scaler really is on the tunable surface —
  # and a typo in the STEP or the PARAM is still caught loudly-by-nil.
  it "still rejects a grid key no step exposes" ->
    df = DataFrame.new([[:x, [0 - 7, 0 - 5, 0 - 3, 0 - 1, 1, 3, 5, 7]]])
    y = [0 - 13, 0 - 9, 0 - 5, 0 - 1, 3, 7, 11, 15]
    proto = Pipeline.new([[:scale, Scaler.new(:min_max)], [:model, LinearRegression.new]])
    bad_param = GridSearch.new(proto, { "scale.nosuchknob" => [1, 2] }, 2)
    expect(bad_param.fit(df, y)).to be_nil
    expect(bad_param.fitted?).to be_false
    bad_step = GridSearch.new(proto, { "nosuchstep.kind" => [:standard] }, 2)
    expect(bad_step.fit(df, y)).to be_nil

  # Preprocessing alone is searchable too — the imputer's strategy is a
  # hyperparameter like any other. :constant with fill 0 leaves the two
  # known rows exact and the missing one far off; :mean fills the column
  # mean, so it wins on held-out R^2.
  it "searches an imputer strategy against a model param" ->
    df = DataFrame.new([[:x, [2, 4, nil, 8, 10, 12, 14, 16]]])
    y = [5, 9, 13, 17, 21, 25, 29, 33]
    proto = Pipeline.new([
      [:impute, Imputer.new(:constant, nil, 0)],
      [:scale, Scaler.new(:standard)],
      [:model, LinearRegression.new]
    ])
    expect(proto.params.key?("impute.strategy")).to be_true
    gs = GridSearch.new(proto, { "impute.strategy" => [:constant, :mean], "model.alpha" => [0, 1] }, 2)
    expect(gs.size).to eq(4)
    expect(gs.fit(df, y) != nil).to be_true
    expect(gs.best_params["impute.strategy"].to_s).to eq("mean")
    expect(gs.best_estimator.step(:impute).strategy.to_s).to eq("mean")
    expect(proto.step(:impute).strategy.to_s).to eq("constant")

spec_summary
