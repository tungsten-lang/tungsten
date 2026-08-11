# Model-agnostic permutation-importance specs.
#
# Run from the repository root on both engines:
#   bin/tungsten bits/tungsten-koala/spec/permutation_importance_spec.w
#   bin/tungsten compile bits/tungsten-koala/spec/permutation_importance_spec.w \
#     --out /tmp/koala-permutation-importance-spec
#   /tmp/koala-permutation-importance-spec

use spec
use koala
use support

+ ImportanceFx
  -> .regression_frame
    DataFrame.new([
      [:signal, [0, 1, 2, 3, 4, 5, 6, 7]],
      [:constant, [7, 7, 7, 7, 7, 7, 7, 7]]
    ])

  -> .regression_y
    [0, 2, 4, 6, 8, 10, 12, 14]

  # Age repeats once for every city and carries no class information.
  # The label is exactly the categorical predicate city == "blue".
  -> .mixed
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

  -> .mixed_classifier
    prep = ColumnTransformer.new([
      [:num, Scaler.new(:standard), [:age]],
      [:cat, Encoder.new(:one_hot), [:city]]
    ])
    Pipeline.new([
      [:prep, prep],
      [:model, LogisticRegression.new(1, 300)]
    ])

-> importance_close(a, b)
  LinAlg.fabs(a.to_f - b.to_f) < 1.to_f / 1000000000.to_f

describe "PermutationImportance result" ->
  it "reports score decreases, original names, and repeat shape" ->
    x = ImportanceFx.regression_frame
    y = ImportanceFx.regression_y
    model = LinearRegression.new(1)
    model.fit(x, y)
    result = PermutationImportance.compute(model, x, y, 7, 42)
    expect(result).not_to be_nil
    expect(result.feature_names.join(",")).to eq("signal,constant")
    expect(result.importances.size).to eq(2)
    expect(result.importances[0].size).to eq(7)
    expect(result.n_repeats).to eq(7)
    expect(result.seed).to eq(42)
    expect(result.importances_mean[0] > 0.to_f).to be_true
    expect(importance_close(result.importances_mean[1], 0)).to be_true
    expect(importance_close(result.importances_std[1], 0)).to be_true

  it "provides a named DataFrame summary in source-column order" ->
    x = ImportanceFx.regression_frame
    y = ImportanceFx.regression_y
    model = LinearRegression.new(1)
    model.fit(x, y)
    result = PermutationImportance.compute(model, x, y, 3, 7)
    summary = result.to_df
    expect(summary.column_names.join(",")).to eq("feature,importance_mean,importance_std")
    expect(summary.column_values(:feature).join(",")).to eq("signal,constant")
    expect(summary.column_values(:importance_mean).size).to eq(2)
    expect(summary.valid?).to be_true

  it "uses positional x names for plain row arrays" ->
    x = [[0, 7], [1, 7], [2, 7], [3, 7], [4, 7], [5, 7]]
    y = [0, 2, 4, 6, 8, 10]
    model = LinearRegression.new(1)
    model.fit(x, y)
    result = PermutationImportance.compute(model, x, y, 2, 9)
    expect(result.feature_names.join(",")).to eq("x0,x1")

  it "computes population standard deviation for every repeat vector" ->
    x = ImportanceFx.regression_frame
    y = ImportanceFx.regression_y
    model = LinearRegression.new(1)
    model.fit(x, y)
    result = PermutationImportance.compute(model, x, y, 6, 21)
    expected = PermutationImportance.population_std(
      result.importances[0], Stats.mean(result.importances[0])
    )
    expect(importance_close(result.importances_std[0], expected)).to be_true

describe "PermutationImportance determinism" ->
  it "is byte-deterministic for the same seed" ->
    x = ImportanceFx.regression_frame
    y = ImportanceFx.regression_y
    model = LinearRegression.new(1)
    model.fit(x, y)
    one = PermutationImportance.compute(model, x, y, 8, 123)
    two = PermutationImportance.compute(model, x, y, 8, 123)
    expect(one.importances.to_s).to eq(two.importances.to_s)
    expect(one.importances_mean.to_s).to eq(two.importances_mean.to_s)
    expect(one.importances_std.to_s).to eq(two.importances_std.to_s)

  it "advances to different permutations for a different seed" ->
    x = ImportanceFx.regression_frame
    y = ImportanceFx.regression_y
    model = LinearRegression.new(1)
    model.fit(x, y)
    one = PermutationImportance.compute(model, x, y, 8, 2)
    two = PermutationImportance.compute(model, x, y, 8, 99)
    expect(one.importances[0].to_s == two.importances[0].to_s).to be_false

  it "does not mutate predictions or fitted state" ->
    x = ImportanceFx.regression_frame
    y = ImportanceFx.regression_y
    model = LinearRegression.new(1)
    model.fit(x, y)
    before = model.predict(x).to_s
    PermutationImportance.compute(model, x, y, 5, 42)
    expect(model.fitted?).to be_true
    expect(model.predict(x).to_s).to eq(before)

describe "PermutationImportance across estimator families" ->
  it "inspects a mixed categorical ColumnTransformer Pipeline" ->
    data = ImportanceFx.mixed
    model = ImportanceFx.mixed_classifier
    model.fit(data[:x], data[:y])
    before = model.predict(data[:x]).join(",")
    result = PermutationImportance.compute(model, data[:x], data[:y], 12, 42)
    expect(result.feature_names.join(",")).to eq("age,city")
    expect(result.baseline_score.to_s).to eq("1")
    expect(importance_close(result.importances_mean[0], 0)).to be_true
    expect(result.importances_mean[1] > 1.to_f / 4.to_f).to be_true
    expect(model.predict(data[:x]).join(",")).to eq(before)

  it "works for a distance-weighted nearest-neighbor classifier" ->
    x = [[0, 0], [0, 1], [1, 0], [9, 9], [9, 10], [10, 9]]
    y = [:low, :low, :low, :high, :high, :high]
    model = KNNClassifier.new(3, :distance)
    model.fit(x, y)
    result = PermutationImportance.compute(model, x, y, 5, 5)
    expect(result).not_to be_nil
    expect(result.baseline_score.to_s).to eq("1")
    expect(result.importances_mean.size).to eq(2)

  it "uses an unsupervised estimator's higher-is-better score" ->
    x = [[0, 0, 7], [0, 0, 7], [1, 1, 7],
         [9, 9, 7], [10, 10, 7], [10, 10, 7]]
    model = KMeans.new(2, 42, 100)
    model.fit(x)
    result = PermutationImportance.compute(model, x, nil, 8, 17)
    expect(result).not_to be_nil
    expect(result.importances_mean[0] > 0.to_f).to be_true
    expect(result.importances_mean[1] > 0.to_f).to be_true
    expect(importance_close(result.importances_mean[2], 0)).to be_true

  it "supports sample-weighted scoring without refitting" ->
    x = ImportanceFx.regression_frame
    y = ImportanceFx.regression_y
    weights = [5, 1, 1, 1, 1, 1, 1, 1]
    model = LinearRegression.new(1)
    model.fit(x, y)
    result = PermutationImportance.compute(model, x, y, 4, 42, weights)
    expect(result).not_to be_nil
    expect(importance_close(result.baseline_score, model.score(x, y, weights))).to be_true
    expect(model.fitted?).to be_true

  it "retains a negative importance when permutation improves test score" ->
    x = [[0], [1], [2], [3], [4], [5], [6], [7]]
    trained_y = [0, 2, 4, 6, 8, 10, 12, 14]
    reversed_y = [14, 12, 10, 8, 6, 4, 2, 0]
    model = LinearRegression.new
    model.fit(x, trained_y)
    result = PermutationImportance.compute(model, x, reversed_y, 12, 42)
    expect(result.importances_mean[0] < 0.to_f).to be_true

describe "PermutationImportance validation" ->
  it "requires a fitted estimator contract" ->
    x = ImportanceFx.regression_frame
    y = ImportanceFx.regression_y
    expect(PermutationImportance.compute(nil, x, y)).to be_nil
    expect(PermutationImportance.compute(LinearRegression.new, x, y)).to be_nil
    expect(PermutationImportance.compute(Scaler.new, x, y)).to be_nil

  it "rejects zero repeats" ->
    x = ImportanceFx.regression_frame
    y = ImportanceFx.regression_y
    model = LinearRegression.new(1)
    model.fit(x, y)
    expect(PermutationImportance.compute(model, x, y, 0, 42)).to be_nil

  it "uses the declared default when the caller passes nil for seed" ->
    x = ImportanceFx.regression_frame
    y = ImportanceFx.regression_y
    model = LinearRegression.new(1)
    model.fit(x, y)
    result = PermutationImportance.compute(model, x, y, 2, nil)
    expect(result.seed).to eq(42)

  it "rejects non-integer repeats" ->
    x = ImportanceFx.regression_frame
    y = ImportanceFx.regression_y
    model = LinearRegression.new(1)
    model.fit(x, y)
    expect(PermutationImportance.compute(model, x, y, 2.to_f, 42)).to be_nil

  it "rejects empty, one-row, ragged, duplicate-name, and target-misaligned data" ->
    x = ImportanceFx.regression_frame
    y = ImportanceFx.regression_y
    model = LinearRegression.new(1)
    model.fit(x, y)
    expect(PermutationImportance.compute(model, [], [], 2, 42)).to be_nil
    expect(PermutationImportance.compute(model, [[1, 7]], [1], 2, 42)).to be_nil
    ragged = DataFrame.new([[:a, [1, 2]], [:b, [3]]])
    expect(PermutationImportance.compute(model, ragged, [1, 2], 2, 42)).to be_nil
    duplicate = DataFrame.new([[:a, [1, 2]], [:a, [3, 4]]])
    expect(PermutationImportance.compute(model, duplicate, [1, 2], 2, 42)).to be_nil
    expect(PermutationImportance.compute(model, x, [1, 2], 2, 42)).to be_nil

  it "rejects unusable scoring weights" ->
    x = ImportanceFx.regression_frame
    y = ImportanceFx.regression_y
    model = LinearRegression.new(1)
    model.fit(x, y)
    expect(PermutationImportance.compute(model, x, y, 2, 42, [1])).to be_nil
    expect(PermutationImportance.compute(model, x, y, 2, 42, [0, 0, 0, 0, 0, 0, 0, 0])).to be_nil

spec_summary
