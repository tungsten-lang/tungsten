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

spec_summary
