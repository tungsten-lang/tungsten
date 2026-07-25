# ColumnSelector / ColumnTransformer specs.
#
# Run from the repo root on both engines:
#   bin/tungsten bits/tungsten-koala/spec/column_transformer_spec.w
#   bin/tungsten -o /tmp/column_transformer_spec bits/tungsten-koala/spec/column_transformer_spec.w
#   /tmp/column_transformer_spec

use spec
use koala

+ MixedFx
  -> .small
    DataFrame.new([
      [:age, [10, 20, 30]],
      [:city, ["red", "blue", "red"]],
      [:id, [101, 102, 103]]
    ])

  -> .small_prep(remainder = :passthrough, verbose = true)
    ColumnTransformer.new([
      [:num, Scaler.new(:standard), [:age]],
      [:cat, Encoder.new(:one_hot), [:city]]
    ], remainder, verbose)

  # Age repeats once for every city, so it carries no class information.
  # The label is exactly the categorical predicate city == "blue".
  -> .classification
    ages = []
    cities = []
    labels = []
    6.times -> (i)
      ages.push(i + 1)
      cities.push("red")
      labels.push(0)
      ages.push(i + 1)
      cities.push("blue")
      labels.push(1)
      ages.push(i + 1)
      cities.push("green")
      labels.push(0)
    {
      x: DataFrame.new([[:age, ages], [:city, cities]]),
      y: labels
    }

  -> .classifier
    prep = ColumnTransformer.new([
      [:num, Scaler.new(:standard), [:age]],
      [:cat, Encoder.new(:one_hot), [:city]]
    ])
    Pipeline.new([
      [:prep, prep],
      [:model, LogisticRegression.new(1, 300)]
    ])

describe "ColumnSelector" ->
  it "keeps requested columns in requested order" ->
    pick = ColumnSelector.new([:city, :age])
    out = pick.fit_transform(MixedFx.small)
    expect(out.column_names.join(",")).to eq("city,age")
    expect(out.column_values(:city).join(",")).to eq("red,blue,red")
    expect(pick.get_feature_names_out.join(",")).to eq("city,age")

  it "drops requested columns and preserves source order" ->
    pick = ColumnSelector.new([:city], :drop)
    out = pick.fit_transform(MixedFx.small)
    expect(out.column_names.join(",")).to eq("age,id")

  it "accepts row arrays through positional x names" ->
    pick = ColumnSelector.new(["x1"])
    out = pick.fit_transform([[1, 2], [3, 4]])
    expect(out.column_names.join(",")).to eq("x1")
    expect(out.column_values("x1").join(",")).to eq("2,4")

  it "requires an exact transform schema" ->
    pick = ColumnSelector.new([:age])
    pick.fit(MixedFx.small)
    reordered = DataFrame.new([
      [:city, ["red"]],
      [:age, [10]],
      [:id, [101]]
    ])
    expect(pick.transform(reordered)).to be_nil
    expect(pick.transform(DataFrame.new([[:age, [10]], [:city, ["red"]]]))).to be_nil

  it "rejects missing, duplicate, empty-result, and invalid selections" ->
    expect(ColumnSelector.new([:missing]).fit(MixedFx.small)).to be_nil
    expect(ColumnSelector.new([:age, :age]).fit(MixedFx.small)).to be_nil
    expect(ColumnSelector.new([], :keep).fit(MixedFx.small)).to be_nil
    expect(ColumnSelector.new([:age, :city, :id], :drop).fit(MixedFx.small)).to be_nil
    expect(ColumnSelector.new([:age], :bogus).fit(MixedFx.small)).to be_nil

  it "is tunable, clones fresh, and persists its learned schema" ->
    pick = ColumnSelector.new([:age])
    pick.fit(MixedFx.small)
    clone = pick.with_params({ columns: [:city], mode: :keep })
    expect(clone.fitted?).to be_false
    expect(clone.params[:columns].join(",")).to eq("city")
    back = Persist.loads(Persist.dumps(pick))
    expect(back.transform(MixedFx.small).column_names.join(",")).to eq("age")

describe "ColumnTransformer composition" ->
  it "fits numeric and categorical branches in parallel" ->
    prep = MixedFx.small_prep
    out = prep.fit_transform(MixedFx.small)
    expect(out.column_names.join(",")).to eq("num__age,cat__city_red,cat__city_blue,remainder__id")
    expect(out.column_values("num__age").join(",")).to eq("-1,0,1")
    expect(out.column_values("cat__city_red").join(",")).to eq("1,0,1")
    expect(out.column_values("cat__city_blue").join(",")).to eq("0,1,0")
    expect(out.column_values("remainder__id").join(",")).to eq("101,102,103")
    expect(prep.get_feature_names_out.join(",")).to eq(out.column_names.join(","))

  it "drops unassigned columns by default" ->
    out = MixedFx.small_prep(:drop).fit_transform(MixedFx.small)
    expect(out.column_names.join(",")).to eq("num__age,cat__city_red,cat__city_blue")
    expect(out.column_values("remainder__id")).to be_nil

  it "supports explicit passthrough and drop branches" ->
    prep = ColumnTransformer.new([
      [:raw, :passthrough, [:age]],
      [:ignored, :drop, [:city]]
    ], :passthrough)
    out = prep.fit_transform(MixedFx.small)
    expect(out.column_names.join(",")).to eq("raw__age,remainder__id")
    expect(out.column_values("raw__age").join(",")).to eq("10,20,30")

  it "uses all-zero one-hot columns for an unseen category" ->
    prep = MixedFx.small_prep(:drop)
    prep.fit(MixedFx.small)
    query = DataFrame.new([[:age, [40]], [:city, ["green"]], [:id, [104]]])
    out = prep.transform(query)
    expect(out.column_names.join(",")).to eq("num__age,cat__city_red,cat__city_blue")
    expect(out.column_values("cat__city_red")[0]).to eq(0)
    expect(out.column_values("cat__city_blue")[0]).to eq(0)

  it "can keep raw feature names only when they remain unique" ->
    prep = MixedFx.small_prep(:drop, false)
    expect(prep.fit(MixedFx.small)).not_to be_nil
    expect(prep.get_feature_names_out.join(",")).to eq("age,city_red,city_blue")
    collision = ColumnTransformer.new([
      [:left, :passthrough, [:age]],
      [:right, :passthrough, [:age]]
    ], :drop, false)
    expect(collision.fit(MixedFx.small)).to be_nil

  it "requires an exact input schema and invalidates a failed refit" ->
    prep = MixedFx.small_prep
    expect(prep.fit(MixedFx.small)).not_to be_nil
    reordered = DataFrame.new([
      [:city, ["red"]],
      [:age, [10]],
      [:id, [101]]
    ])
    expect(prep.transform(reordered)).to be_nil
    expect(prep.fit(DataFrame.new([[:age, [10]], [:id, [101]]]))).to be_nil
    expect(prep.fitted?).to be_false
    expect(prep.transform(MixedFx.small)).to be_nil

  it "rejects malformed specs, missing columns, and empty output" ->
    expect(ColumnTransformer.new([[:bad, Scaler.new, [:missing]]]).fit(MixedFx.small)).to be_nil
    expect(ColumnTransformer.new([[:bad, Scaler.new]]).fit(MixedFx.small)).to be_nil
    expect(ColumnTransformer.new([[:dup, Scaler.new, [:age]], [:dup, Encoder.new, [:city]]]).fit(MixedFx.small)).to be_nil
    expect(ColumnTransformer.new([[:all, :drop, [:age, :city, :id]]]).fit(MixedFx.small)).to be_nil
    expect(ColumnTransformer.new([], :bogus).fit(MixedFx.small)).to be_nil
    estimator_pipe = Pipeline.new([Scaler.new, LogisticRegression.new])
    expect(ColumnTransformer.new([[:bad, estimator_pipe, [:age]]]).fit(MixedFx.small)).to be_nil

  it "supports a nested transformer Pipeline branch" ->
    frame = DataFrame.new([
      [:a, [2, nil, 6]],
      [:city, ["red", "blue", "red"]]
    ])
    numeric = Pipeline.new([
      [:fill, Imputer.new(:mean)],
      [:scale, Scaler.new(:standard)]
    ])
    prep = ColumnTransformer.new([
      [:num, numeric, [:a]],
      [:cat, Encoder.new(:one_hot), [:city]]
    ])
    out = prep.fit_transform(frame)
    expect(out.column_names.join(",")).to eq("num__a,cat__city_red,cat__city_blue")
    expect(out.column_values("num__a").join(",")).to eq("-1,0,1")
    expect(prep.named_transformer(:num).fitted?).to be_true

  it "forwards y through a nested supervised transformer Pipeline" ->
    frame = DataFrame.new([
      [:signal, [0, 1, 10, 11, 2, 12]],
      [:noise, [1, 2, 1, 2, 1, 2]]
    ])
    y = ["a", "a", "b", "b", "a", "b"]
    branch = Pipeline.new([
      [:select, SelectKBest.new(1, :f_classif)],
      [:scale, Scaler.new(:standard)]
    ])
    prep = ColumnTransformer.new([[:chosen, branch, [:signal, :noise]]])
    out = prep.fit_transform(frame, y)
    expect(out.column_names.join(",")).to eq("chosen__signal")

  it "forwards sample weights to weighted branches" ->
    frame = DataFrame.new([[:x, [0, 10, 10]]])
    prep = ColumnTransformer.new([[:num, Scaler.new(:standard), [:x]]])
    prep.fit(frame, nil, [10, 1, 1])
    mean = prep.named_transformer(:num).learned_params[0][1]
    expect(mean < 2.to_f).to be_true
    expect(ColumnTransformer.new([[:num, Scaler.new, [:x]]]).fit(frame, nil, [1, 2])).to be_nil

describe "ColumnTransformer in model-selection workflows" ->
  it "exposes nested parameters and rebuilds a fresh transformer" ->
    prep = MixedFx.small_prep
    expect(prep.params.key?("num.kind")).to be_true
    expect(prep.params.key?("cat.kind")).to be_true
    clone = prep.with_params({ "num.kind": :min_max, "cat.kind": :label, remainder: :drop })
    expect(clone.fitted?).to be_false
    expect(clone.named_transformer(:num).kind.to_s).to eq("min_max")
    expect(clone.named_transformer(:cat).kind.to_s).to eq("label")
    expect(clone.remainder).to eq("drop")

  it "fits and predicts as the preprocessing step of a Pipeline" ->
    fx = MixedFx.classification
    pipe = MixedFx.classifier
    expect(pipe.fit(fx[:x], fx[:y])).not_to be_nil
    expect(pipe.score(fx[:x], fx[:y]).to_s).to eq("1")
    expect(pipe.predict_proba(fx[:x]).size).to eq(18)
    expect(pipe.params.key?("prep.cat.kind")).to be_true

  it "preserves categorical DataFrames through cross-validation" ->
    fx = MixedFx.classification
    full = CrossValidation.cross_val_mean(MixedFx.classifier, fx[:x], fx[:y], StratifiedKFold.new(3))
    numeric = Pipeline.new([
      ColumnTransformer.new([[:num, Scaler.new(:standard), [:age]]]),
      LogisticRegression.new(1, 300)
    ])
    numeric_score = CrossValidation.cross_val_mean(numeric, fx[:x], fx[:y], StratifiedKFold.new(3))
    expect(full.to_s).to eq("1")
    expect(numeric_score < full).to be_true

  it "lets GridSearch tune preprocessing and the estimator together" ->
    fx = MixedFx.classification
    search = GridSearch.new(
      MixedFx.classifier,
      { "prep.cat.kind": [:label, :one_hot], "model.epochs": [100, 300] },
      StratifiedKFold.new(3)
    )
    expect(search.size).to eq(4)
    expect(search.fit(fx[:x], fx[:y])).not_to be_nil
    expect(search.best_score.to_s).to eq("1")
    expect(search.best_estimator.step(:prep).fitted?).to be_true

  it "can be calibrated without losing the mixed feature schema" ->
    fx = MixedFx.classification
    calibrated = CalibratedClassifierCV.new(MixedFx.classifier, :sigmoid, 3)
    expect(calibrated.fit(fx[:x], fx[:y])).not_to be_nil
    probs = calibrated.predict_proba(fx[:x])
    expect(probs.size).to eq(18)
    expect(calibrated.predict(fx[:x]).join(",")).to eq(fx[:y].join(","))
    weights = []
    18.times -> (i)
      weights.push(1)
    weights[0] = 0
    weighted = CalibratedClassifierCV.new(MixedFx.classifier, :sigmoid, 3)
    expect(weighted.fit(fx[:x], fx[:y], weights)).not_to be_nil
    expect(weighted.predict(fx[:x]).size).to eq(18)

  it "round-trips standalone and inside a fitted Pipeline" ->
    prep = MixedFx.small_prep
    prep.fit(MixedFx.small)
    back = Persist.loads(Persist.dumps(prep))
    expect(back.get_feature_names_out.join(",")).to eq(prep.get_feature_names_out.join(","))
    expect(back.transform(MixedFx.small).column_names.join(",")).to eq(prep.transform(MixedFx.small).column_names.join(","))

    fx = MixedFx.classification
    pipe = MixedFx.classifier
    pipe.fit(fx[:x], fx[:y])
    loaded = Persist.loads(Persist.dumps(pipe))
    expect(loaded.predict(fx[:x]).join(",")).to eq(pipe.predict(fx[:x]).join(","))

describe "ColumnTransformer persistence guards" ->
  it "rejects malformed selector and transformer state" ->
    selector = ColumnSelector.new([:age])
    selector.fit(MixedFx.small)
    selector_state = selector.to_state
    selector_state[:output_names] = []
    expect(ColumnSelector.load_state(selector_state)).to be_nil

    prep = MixedFx.small_prep
    prep.fit(MixedFx.small)
    state = prep.to_state
    state[:output_names] = []
    expect(ColumnTransformer.load_state(state)).to be_nil

spec_summary
