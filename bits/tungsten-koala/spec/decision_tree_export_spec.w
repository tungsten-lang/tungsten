# DecisionTreeExport specs — deterministic standalone Tungsten source for a
# fitted DecisionTreeClassifier.
#
# Run from the repo root (both engines, exit 0 = green):
#   bin/tungsten bits/tungsten-koala/spec/decision_tree_export_spec.w
#   bin/tungsten -o /tmp/koala_tree_export_spec bits/tungsten-koala/spec/decision_tree_export_spec.w
#   /tmp/koala_tree_export_spec

use spec
use koala
use support

# This is the exact source expected from the XOR export below. Keeping a
# source-level copy in the spec makes both engines compile and execute the
# generated shape; the exact-string assertion ties it to the exporter.
-> koala_export_fixture_schema_version
  2

-> koala_export_fixture_schema_checksum
  1020595888

-> koala_export_fixture_feature_count
  2

-> koala_export_fixture(features, feature_schema_checksum)
  raise "koala_export_fixture: feature schema checksum mismatch" if feature_schema_checksum != 1020595888
  raise "koala_export_fixture: expected 2 features" if features.size != 2
  i = 0
  while i < features.size
    cell = features[i]
    kind = type(cell)
    valid = cell == nil || kind == "Int" || (kind == "Float" && (cell != cell || cell - cell == 0.to_f))
    return nil if !valid
    i += 1
  if features[0] != nil && (type(features[0]) != "Float" || features[0] == features[0]) && features[0].to_f <= ~0.5
    if features[1] != nil && (type(features[1]) != "Float" || features[1] == features[1]) && features[1].to_f <= ~0.5
      0
    else
      1
  else
    if features[1] != nil && (type(features[1]) != "Float" || features[1] == features[1]) && features[1].to_f <= ~0.5
      1
    else
      0

# A second compiled copy exercises the round-trip f64 spellings rather than
# only binary-exact halves and Integer arm ids.
-> koala_export_float_fixture(features, feature_schema_checksum)
  raise "koala_export_float_fixture: feature schema checksum mismatch" if feature_schema_checksum != 726313283
  raise "koala_export_float_fixture: expected 1 feature" if features.size != 1
  i = 0
  while i < features.size
    cell = features[i]
    kind = type(cell)
    valid = cell == nil || kind == "Int" || (kind == "Float" && (cell != cell || cell - cell == 0.to_f))
    return nil if !valid
    i += 1
  if features[0] != nil && (type(features[0]) != "Float" || features[0] == features[0]) && features[0].to_f <= ~0.73809523809523803
    ~0.33333333333333331
  else
    ~0.14285714285714285

-> koala_export_missing_left_fixture(features, feature_schema_checksum)
  raise "koala_export_missing_left_fixture: feature schema checksum mismatch" if feature_schema_checksum != 1177105481
  raise "koala_export_missing_left_fixture: expected 1 feature" if features.size != 1
  i = 0
  while i < features.size
    cell = features[i]
    kind = type(cell)
    valid = cell == nil || kind == "Int" || (kind == "Float" && (cell != cell || cell - cell == 0.to_f))
    return nil if !valid
    i += 1
  if features[0] == nil || (type(features[0]) == "Float" && features[0] != features[0]) || features[0].to_f <= ~4.5
    0
  else
    1

-> koala_export_missing_right_fixture(features, feature_schema_checksum)
  raise "koala_export_missing_right_fixture: feature schema checksum mismatch" if feature_schema_checksum != 1177105481
  raise "koala_export_missing_right_fixture: expected 1 feature" if features.size != 1
  i = 0
  while i < features.size
    cell = features[i]
    kind = type(cell)
    valid = cell == nil || kind == "Int" || (kind == "Float" && (cell != cell || cell - cell == 0.to_f))
    return nil if !valid
    i += 1
  if features[0] != nil && (type(features[0]) != "Float" || features[0] == features[0]) && features[0].to_f <= ~4.5
    0
  else
    1

# Compiled copy of the String/Symbol label arms emitted by the shared literal
# encoder. Brackets are escaped so they remain data, never interpolation.
-> koala_export_text_fixture(features, feature_schema_checksum)
  raise "koala_export_text_fixture: feature schema checksum mismatch" if feature_schema_checksum != 726313283
  raise "koala_export_text_fixture: expected 1 feature" if features.size != 1
  i = 0
  while i < features.size
    cell = features[i]
    kind = type(cell)
    valid = cell == nil || kind == "Int" || (kind == "Float" && (cell != cell || cell - cell == 0.to_f))
    return nil if !valid
    i += 1
  if features[0] != nil && (type(features[0]) != "Float" || features[0] == features[0]) && features[0].to_f <= ~0.5
    "left\[arm\]\n\"quoted\"\\"
  else
    "right\[arm\]".to_sym

-> export_nan
  infinity = 1.to_f
  1100.times -> (i)
    infinity *= 2.to_f
  infinity - infinity

describe "DecisionTreeExport standalone Tungsten source" ->
  it "emits deterministic nested source whose compiled predictions match the fitted tree" ->
    x = [[0, 0], [0, 1], [1, 0], [1, 1]]
    y = [0, 1, 1, 0]
    model = DecisionTreeClassifier.new
    model.fit(x, y)

    artifact = DecisionTreeExport.export(model, [:x0, :x1], :koala_export_fixture)
    again = DecisionTreeExport.export(model, ["x0", "x1"], "koala_export_fixture")
    expect(artifact != nil).to be_true
    expect(artifact[:format]).to eq("koala-decision-tree-source")
    expect(artifact[:schema_version]).to eq(2)
    expect(artifact[:schema_checksum]).to eq(1020595888)
    expect(artifact[:feature_names]).to eq(["x0", "x1"])
    expect(artifact[:function_name]).to eq("koala_export_fixture")
    expect(artifact[:source]).to eq(again[:source])

    expected = [
      "# Generated by Koala DecisionTreeExport; do not edit.",
      "# schema-version: 2",
      "# schema-checksum: 1020595888",
      "# feature-order: 0=x0, 1=x1",
      "",
      "-> koala_export_fixture_schema_version",
      "  2",
      "",
      "-> koala_export_fixture_schema_checksum",
      "  1020595888",
      "",
      "-> koala_export_fixture_feature_count",
      "  2",
      "",
      "-> koala_export_fixture(features, feature_schema_checksum)",
      "  raise \"koala_export_fixture: feature schema checksum mismatch\" if feature_schema_checksum != 1020595888",
      "  raise \"koala_export_fixture: expected 2 features\" if features.size != 2",
      "  i = 0",
      "  while i < features.size",
      "    cell = features\[i\]",
      "    kind = type(cell)",
      "    valid = cell == nil || kind == \"Int\" || (kind == \"Float\" && (cell != cell || cell - cell == 0.to_f))",
      "    return nil if !valid",
      "    i += 1",
      "  if features\[0\] != nil && (type(features\[0\]) != \"Float\" || features\[0\] == features\[0\]) && features\[0\].to_f <= ~0.5",
      "    if features\[1\] != nil && (type(features\[1\]) != \"Float\" || features\[1\] == features\[1\]) && features\[1\].to_f <= ~0.5",
      "      0",
      "    else",
      "      1",
      "  else",
      "    if features\[1\] != nil && (type(features\[1\]) != \"Float\" || features\[1\] == features\[1\]) && features\[1\].to_f <= ~0.5",
      "      1",
      "    else",
      "      0",
      ""
    ].join("\n")
    expect(artifact[:source]).to eq(expected)
    expect(DecisionTreeExport.source(model, [:x0, :x1], :koala_export_fixture)).to eq(expected)

    exported_predictions = []
    x.each -> (row)
      exported_predictions.push(koala_export_fixture(row, artifact[:schema_checksum]))
    expect(exported_predictions.to_s).to eq(model.predict(x).to_s)
    expect(koala_export_fixture_schema_version).to eq(artifact[:schema_version])
    expect(koala_export_fixture_feature_count).to eq(artifact[:feature_names].size)

  it "requires the caller to present the feature schema checksum and exact width" ->
    expect(-> () koala_export_fixture([0, 0], 1020595887)).to raise_error
    expect(-> () koala_export_fixture([0], 1020595888)).to raise_error
    expect(-> () koala_export_fixture([0, 0, 0], 1020595888)).to raise_error
    expect(koala_export_fixture(["x", 0], 1020595888)).to be_nil

  it "changes the schema checksum when ordered feature names drift" ->
    model = DecisionTreeClassifier.new
    model.fit([[0, 0], [1, 1]], [0, 1])
    original = DecisionTreeExport.export(model, [:variables, :clauses], :select_arm)
    reordered = DecisionTreeExport.export(model, [:clauses, :variables], :select_arm)
    renamed = DecisionTreeExport.export(model, [:variables, :literal_count], :select_arm)
    expect(original != nil).to be_true
    expect(reordered != nil).to be_true
    expect(renamed != nil).to be_true
    expect(original[:schema_checksum] != reordered[:schema_checksum]).to be_true
    expect(original[:schema_checksum] != renamed[:schema_checksum]).to be_true
    expect(original[:source] != reordered[:source]).to be_true
    expect(original[:source].include?("# feature-order: 0=variables, 1=clauses")).to be_true
    expect(reordered[:source].include?("# feature-order: 0=clauses, 1=variables")).to be_true

  it "validates model fit, ordered names, uniqueness, width, and function name" ->
    unfitted = DecisionTreeClassifier.new
    expect(DecisionTreeExport.export(unfitted, [:x])).to be_nil

    model = DecisionTreeClassifier.new
    model.fit([[0, 0], [1, 1]], [0, 1])
    expect(DecisionTreeExport.export(model, nil)).to be_nil
    expect(DecisionTreeExport.export(model, "x0,x1")).to be_nil
    expect(DecisionTreeExport.export(model, [:x])).to be_nil
    expect(DecisionTreeExport.export(model, [:x, :x])).to be_nil
    expect(DecisionTreeExport.export(model, [:x, "bad-name"])).to be_nil
    expect(DecisionTreeExport.export(model, [:x, ""])).to be_nil
    expect(DecisionTreeExport.export(model, [:x, 7])).to be_nil
    expect(DecisionTreeExport.export(model, [:x0, :x1], :BadName)).to be_nil
    expect(DecisionTreeExport.export(model, [:x0, :x1], "bad-name")).to be_nil
    expect(DecisionTreeExport.export(model, [:x0, :x1], "if")).to be_nil
    expect(DecisionTreeExport.export(model, [:x0, :x1], 7)).to be_nil

    defaulted = DecisionTreeExport.export(model, [:x0, :x1])
    expect(defaulted[:function_name]).to eq("koala_tree_predict")
    expect(defaulted[:source].include?("-> koala_tree_predict(features, feature_schema_checksum)")).to be_true

  it "emits round-trip f64 classifier and regressor predictions" ->
    third = 1.to_f / 3.to_f
    seventh = 1.to_f / 7.to_f
    expect(DecisionTreeExport.float_literal(6.to_f)).to eq("~6.0")
    expect(DecisionTreeExport.float_literal(third)).to eq("~0.33333333333333331")
    expect(DecisionTreeExport.float_literal(seventh).slice(0, 1)).to eq("~")
    expect(DecisionTreeExport.float_literal(seventh).slice(1, 64).to_f == seventh).to be_true

    numeric = DecisionTreeClassifier.new
    numeric.fit([[third], [seventh + 1.to_f]], [third, seventh])
    artifact = DecisionTreeExport.export(numeric, [:ratio], :numeric_tree)
    expect(artifact != nil).to be_true
    threshold_literal = DecisionTreeExport.float_literal(numeric.tree[:threshold])
    expect(artifact[:source].include?("features\[0\].to_f <= " + threshold_literal)).to be_true
    expect(artifact[:source].include?(DecisionTreeExport.float_literal(third))).to be_true
    expect(artifact[:source].include?(DecisionTreeExport.float_literal(seventh))).to be_true
    compiled_predictions = [
      koala_export_float_fixture([third], 726313283),
      koala_export_float_fixture([seventh + 1.to_f], 726313283)
    ]
    expect(compiled_predictions.to_s).to eq(numeric.predict([[third], [seventh + 1.to_f]]).to_s)

    classifier_artifact = DecisionTreeExport.export(
      numeric, [:ratio], :koala_export_float_fixture
    )
    regression = DecisionTreeRegressor.new(1)
    regression.fit([[third], [seventh + 1.to_f]], [third, seventh])
    regression_artifact = DecisionTreeExport.export(
      regression, [:ratio], :koala_export_float_fixture
    )
    expect(regression_artifact != nil).to be_true
    expect(regression_artifact[:source]).to eq(classifier_artifact[:source])
    expect(compiled_predictions.to_s).to eq(regression.predict([[third], [seventh + 1.to_f]]).to_s)

  it "exports escaped String and Symbol labels without source interpolation" ->
    left_label = "left\[arm\]\n" + 34.chr + "quoted" + 34.chr + 92.chr
    right_label = "right\[arm\]".to_sym
    model = DecisionTreeClassifier.new
    model.fit([[0], [1]], [left_label, right_label])
    artifact = DecisionTreeExport.export(
      model, [:ratio], :koala_export_text_fixture
    )
    expect(artifact != nil).to be_true
    expect(artifact[:source].include?(DecisionTreeExport.prediction_literal(left_label))).to be_true
    expect(artifact[:source].include?(DecisionTreeExport.prediction_literal(right_label))).to be_true
    expect(DecisionTreeExport.prediction_literal(right_label).include?(".to_sym")).to be_true
    compiled = [
      koala_export_text_fixture([0], 726313283),
      koala_export_text_fixture([1], 726313283)
    ]
    expect(compiled.to_s).to eq(model.predict([[0], [1]]).to_s)
    expect(compiled[0].is_a?(String)).to be_true
    expect(compiled[1].is_a?(Symbol)).to be_true

  it "refuses unsupported labels and nonfinite numeric predictions" ->
    unsupported = DecisionTreeClassifier.new
    unsupported.fit([[0], [1]], ["ok", "bad" + 1.chr])
    expect(DecisionTreeExport.export(unsupported, [:x], :unsupported_tree)).to be_nil
    expect(DecisionTreeExport.string_literal("bad" + 1.chr)).to be_nil

    infinity = 1.to_f
    1100.times -> (i)
      infinity *= 2.to_f
    expect(DecisionTreeExport.prediction_literal(infinity)).to be_nil
    expect(DecisionTreeExport.prediction_literal(infinity - infinity)).to be_nil
    numeric = DecisionTreeRegressor.new(1)
    numeric.fit([[0], [1]], [0, 1])
    numeric.tree[:threshold] = infinity
    expect(DecisionTreeExport.export(numeric, [:ratio], :nonfinite_tree)).to be_nil

  it "exports learned nil and NaN routing in both directions" ->
    x = [[0], [1], [8], [9], [nil], [nil]]
    left = DecisionTreeClassifier.new.fit(x, [0, 0, 1, 1, 0, 0])
    right = DecisionTreeClassifier.new.fit(x, [0, 0, 1, 1, 1, 1])
    left_artifact = DecisionTreeExport.export(left, [:missing_x], :koala_export_missing_left_fixture)
    right_artifact = DecisionTreeExport.export(right, [:missing_x], :koala_export_missing_right_fixture)
    expect(left_artifact != nil).to be_true
    expect(right_artifact != nil).to be_true
    expect(left.tree[:missing_left]).to be_true
    expect(right.tree[:missing_left]).to be_false
    expect(left_artifact[:source].include?("features\[0\] == nil ||")).to be_true
    expect(right_artifact[:source].include?("features\[0\] != nil &&")).to be_true

    queries = [[nil], [export_nan], [0], [9]]
    left_predictions = []
    right_predictions = []
    queries.each -> (row)
      left_predictions.push(koala_export_missing_left_fixture(row, left_artifact[:schema_checksum]))
      right_predictions.push(koala_export_missing_right_fixture(row, right_artifact[:schema_checksum]))
    expect(left_predictions.to_s).to eq(left.predict(queries).to_s)
    expect(right_predictions.to_s).to eq(right.predict(queries).to_s)

    regression = DecisionTreeRegressor.new(1)
    regression.fit(x, [0, 0, 1, 1, 0, 0])
    regression_artifact = DecisionTreeExport.export(
      regression, [:missing_x], :koala_export_missing_left_fixture
    )
    expect(regression_artifact != nil).to be_true
    expect(regression_artifact[:source].include?("features\[0\] == nil ||")).to be_true
    expect(regression_artifact[:source].include?("    ~0.0")).to be_true
    expect(regression_artifact[:source].include?("    ~1.0")).to be_true
    regression_predictions = regression.predict(queries)
    same_predictions = true
    i = 0
    while i < left_predictions.size
      same_predictions = false if left_predictions[i].to_f != regression_predictions[i]
      i += 1
    expect(same_predictions).to be_true

    infinity = 1.to_f
    1100.times -> (i)
      infinity *= 2.to_f
    expect(koala_export_missing_left_fixture([infinity], left_artifact[:schema_checksum])).to be_nil
    expect(koala_export_missing_right_fixture([infinity], right_artifact[:schema_checksum])).to be_nil

spec_summary
