# Unsupervised pipeline tails + weighted transformers.
#
#   bin/tungsten bits/tungsten-koala/spec/pipeline_unsup_spec.w

use spec
use koala

describe "Pipeline unsupervised tail" ->
  it "fits scale then KMeans without y and predicts" ->
    x = [[0, 0], [0, 1], [10, 10], [11, 10]]
    pipe = Pipeline.new([
      [:scale, Scaler.new(:standard)],
      [:km, KMeans.new(2, 42)]
    ])
    expect(pipe.supervised?).to be_false
    expect(pipe.fit(x) != nil).to be_true
    expect(pipe.fitted?).to be_true
    labels = pipe.predict(x)
    expect(labels != nil).to be_true
    expect(labels.size).to eq(4)
    # two tight pairs → two clusters, same label within each pair
    expect(labels[0] == labels[1]).to be_true
    expect(labels[2] == labels[3]).to be_true
    expect(labels[0] == labels[2]).to be_false

  it "scores an unsupervised chain (negated inertia)" ->
    x = [[0, 0], [0, 1], [10, 10], [11, 10]]
    pipe = Pipeline.new([Scaler.new(:standard), KMeans.new(2, 1)])
    pipe.fit(x)
    s = pipe.score(x)
    expect(s != nil).to be_true
    expect(s < 0.to_f).to be_true

describe "Weighted Scaler / Imputer" ->
  it "centres on the weighted mean" ->
    df = DataFrame.new([[:x, [1, 2, 3]]])
    sc = Scaler.new(:standard)
    expect(sc.fit(df, [2, 1, 1]) != nil).to be_true
    # mean = (2*1 + 2 + 3) / 4 = 1.75
    lp = sc.learned_params
    expect(lp[0][1].to_s).to eq("1.75")

  it "weighted mean equals unweighted after row duplication" ->
    df = DataFrame.new([[:x, [1, 2, 3]]])
    sc_w = Scaler.new(:standard)
    sc_w.fit(df, [2, 1, 1])
    df_d = DataFrame.new([[:x, [1, 1, 2, 3]]])
    sc_d = Scaler.new(:standard)
    sc_d.fit(df_d)
    expect(sc_w.learned_params[0][1] == sc_d.learned_params[0][1]).to be_true
    expect(sc_w.learned_params[0][2] == sc_d.learned_params[0][2]).to be_true

  it "Imputer mean respects weights" ->
    df = DataFrame.new([[:x, [1, 3, nil]]])
    imp = Imputer.new(:mean)
    imp.fit(df, [1, 3, 1])
    # weighted mean of non-nil: (1*1 + 3*3) / (1+3) = 10/4 = 2.5
    expect(imp.learned_params[0][1].to_s).to eq("2.5")

  it "Pipeline passes weights into Scaler and the tail" ->
    x = [[0], [1], [2], [10]]
    y = [0, 1, 2, 10]
    pipe = Pipeline.new([
      [:scale, Scaler.new(:standard)],
      [:model, LinearRegression.new]
    ])
    expect(pipe.fit(x, y, [1, 1, 1, 1]) != nil).to be_true
    expect(pipe.score(x, y) != nil).to be_true

spec_summary
