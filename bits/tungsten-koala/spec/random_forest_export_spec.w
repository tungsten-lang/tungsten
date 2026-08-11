# RandomForestExport specs — standalone Tungsten soft-vote / mean predictors.
#
# Run from the repository root in both engines:
#   bin/tungsten bits/tungsten-koala/spec/random_forest_export_spec.w
#   bin/tungsten compile bits/tungsten-koala/spec/random_forest_export_spec.w \
#     --out /tmp/koala_forest_export_spec
#   /tmp/koala_forest_export_spec

use spec
use koala

# Compiled copies of the source produced by the deterministic fixtures below.
# These functions deliberately have no Koala dependency in their bodies.
-> forest_fixture_tree_0(features, totals)
  if features[0] != nil && (type(features[0]) != "Float" || features[0] == features[0]) && features[0].to_f <= ~6.5
    totals[0] += ~1.0
    totals[1] += ~0.0
  else
    totals[0] += ~0.0
    totals[1] += ~1.0

-> forest_fixture_tree_1(features, totals)
  if features[0] != nil && (type(features[0]) != "Float" || features[0] == features[0]) && features[0].to_f <= ~6.5
    totals[0] += ~1.0
    totals[1] += ~0.0
  else
    totals[0] += ~0.0
    totals[1] += ~1.0

-> forest_fixture_tree_2(features, totals)
  if features[0] != nil && (type(features[0]) != "Float" || features[0] == features[0]) && features[0].to_f <= ~6.5
    totals[0] += ~0.75
    totals[1] += ~0.25
  else
    totals[0] += ~0.0
    totals[1] += ~1.0

-> forest_fixture_predict_proba(features, feature_schema_checksum)
  raise "forest_fixture_predict_proba: feature schema checksum mismatch" if feature_schema_checksum != 1496648082
  raise "forest_fixture_predict_proba: expected 1 feature" if features.size != 1
  i = 0
  while i < features.size
    cell = features[i]
    kind = type(cell)
    valid = cell == nil || kind == "Integer" || (kind == "Float" && (cell != cell || cell - cell == 0.to_f))
    return nil if !valid
    i += 1
  totals = []
  2.times -> (c)
    totals.push(0.to_f)
  forest_fixture_tree_0(features, totals)
  forest_fixture_tree_1(features, totals)
  forest_fixture_tree_2(features, totals)
  divisor = ~3.0
  c = 0
  while c < totals.size
    totals[c] = totals[c] / divisor
    c += 1
  totals

-> forest_fixture(features, feature_schema_checksum)
  probabilities = forest_fixture_predict_proba(features, feature_schema_checksum)
  return nil if probabilities == nil
  best = 0
  c = 1
  while c < probabilities.size
    best = c if probabilities[c] > probabilities[best]
    c += 1
  return 0 if best == 0
  1

# The compact form of the same fitted classifier, also copied from the
# generated artifact so both engines compile and execute its constant arrays.
COMPACT_FOREST_ROOTS = [0, 1, 2]
COMPACT_FOREST_FEATURES = [0, 0, 0]
COMPACT_FOREST_THRESHOLDS = [~6.5, ~6.5, ~6.5]
COMPACT_FOREST_MISSING_LEFT = [false, false, false]
COMPACT_FOREST_LEFT = [-1, -3, -5]
COMPACT_FOREST_RIGHT = [-2, -4, -6]
COMPACT_FOREST_PROBABILITY_0 = [~1.0, ~0.0, ~1.0, ~0.0, ~0.75, ~0.0]
COMPACT_FOREST_PROBABILITY_1 = [~0.0, ~1.0, ~0.0, ~1.0, ~0.25, ~1.0]

-> compact_forest_accumulate(features, totals, root)
  index = root
  while index >= 0
    value = features[COMPACT_FOREST_FEATURES[index]]
    if value == nil || (type(value) == "Float" && value != value)
      go_left = COMPACT_FOREST_MISSING_LEFT[index]
    else
      go_left = value.to_f <= COMPACT_FOREST_THRESHOLDS[index]
    if go_left
      index = COMPACT_FOREST_LEFT[index]
    else
      index = COMPACT_FOREST_RIGHT[index]
  leaf = 0 - index - 1
  totals[0] += COMPACT_FOREST_PROBABILITY_0[leaf]
  totals[1] += COMPACT_FOREST_PROBABILITY_1[leaf]

-> compact_forest_predict_proba(features, feature_schema_checksum)
  raise "compact_forest_predict_proba: feature schema checksum mismatch" if feature_schema_checksum != 872449085
  raise "compact_forest_predict_proba: expected 1 feature" if features.size != 1
  i = 0
  while i < features.size
    cell = features[i]
    kind = type(cell)
    valid = cell == nil || kind == "Integer" || (kind == "Float" && (cell != cell || cell - cell == 0.to_f))
    return nil if !valid
    i += 1
  totals = []
  2.times -> (c)
    totals.push(0.to_f)
  t = 0
  while t < COMPACT_FOREST_ROOTS.size
    compact_forest_accumulate(features, totals, COMPACT_FOREST_ROOTS[t])
    t += 1
  divisor = ~3.0
  c = 0
  while c < totals.size
    totals[c] = totals[c] / divisor
    c += 1
  totals

-> compact_forest(features, feature_schema_checksum)
  probabilities = compact_forest_predict_proba(features, feature_schema_checksum)
  return nil if probabilities == nil
  best = 0
  c = 1
  while c < probabilities.size
    best = c if probabilities[c] > probabilities[best]
    c += 1
  return 0 if best == 0
  1

# The class-arm portion of the String/Symbol artifacts. Their probability
# bodies are byte-for-byte equivalent to the numeric fixture because class
# indices, not labels, drive every tree.
-> forest_text_fixture(features, feature_schema_checksum)
  probabilities = forest_fixture_predict_proba(features, feature_schema_checksum)
  return nil if probabilities == nil
  best = 0
  c = 1
  while c < probabilities.size
    best = c if probabilities[c] > probabilities[best]
    c += 1
  return "even\[arm\]" if best == 0
  "odd\[arm\]".to_sym

-> compact_forest_text_fixture(features, feature_schema_checksum)
  probabilities = compact_forest_predict_proba(features, feature_schema_checksum)
  return nil if probabilities == nil
  best = 0
  c = 1
  while c < probabilities.size
    best = c if probabilities[c] > probabilities[best]
    c += 1
  return "even\[arm\]" if best == 0
  "odd\[arm\]".to_sym

-> regression_forest_fixture_tree_0(features)
  if features[0] == nil || (type(features[0]) == "Float" && features[0] != features[0]) || features[0].to_f <= ~5.0
    ~10.0
  else
    ~43.799999999999997

-> regression_forest_fixture_tree_1(features)
  if features[0] == nil || (type(features[0]) == "Float" && features[0] != features[0]) || features[0].to_f <= ~5.0
    ~10.0
  else
    ~46.399999999999999

-> regression_forest_fixture_tree_2(features)
  if features[0] == nil || (type(features[0]) == "Float" && features[0] != features[0]) || features[0].to_f <= ~4.0
    ~9.0
  else
    ~45.75

-> regression_forest_fixture(features, feature_schema_checksum)
  raise "regression_forest_fixture: feature schema checksum mismatch" if feature_schema_checksum != 1496648082
  raise "regression_forest_fixture: expected 1 feature" if features.size != 1
  i = 0
  while i < features.size
    cell = features[i]
    kind = type(cell)
    valid = cell == nil || kind == "Integer" || (kind == "Float" && (cell != cell || cell - cell == 0.to_f))
    return nil if !valid
    i += 1
  total = 0.to_f
  total += regression_forest_fixture_tree_0(features)
  total += regression_forest_fixture_tree_1(features)
  total += regression_forest_fixture_tree_2(features)
  total / ~3.0

-> forest_export_nan
  infinity = 1.to_f
  1100.times -> (i)
    infinity *= 2.to_f
  infinity - infinity

-> forest_export_classifier
  x = [[0], [1], [2], [3], [4], [5], [6], [7], [nil]]
  y = [0, 1, 0, 1, 0, 1, 0, 1, 1]
  RandomForestClassifier.new(3, :all, 1, 1, 7, :gini, true).fit(x, y)

-> forest_export_regressor
  x = [[0], [1], [2], [3], [4], [5], [6], [7], [nil]]
  y = [0, 1, 4, 9, 16, 25, 36, 49, 20]
  RandomForestRegressor.new(3, :all, 1, 1, 7, :mse, true).fit(x, y)

describe "RandomForestExport standalone Tungsten source" ->
  it "exports deterministic classifier metadata, tree helpers and soft voting" ->
    model = forest_export_classifier
    artifact = RandomForestExport.export(model, [:x], :forest_fixture)
    again = RandomForestExport.export(model, ["x"], "forest_fixture")
    expect(artifact != nil).to be_true
    expect(artifact[:format]).to eq("koala-random-forest-source")
    expect(artifact[:schema_version]).to eq(1)
    expect(artifact[:schema_checksum]).to eq(1496648082)
    expect(artifact[:forest_kind]).to eq("classifier")
    expect(artifact[:tree_count]).to eq(3)
    expect(artifact[:feature_names]).to eq(["x"])
    expect(artifact[:source]).to eq(again[:source])
    expect(artifact[:source].include?("-> forest_fixture_tree_2(features, totals)")).to be_true
    expect(artifact[:source].include?("    totals\[0\] += ~0.75")).to be_true
    expect(artifact[:source].include?("forest_fixture_tree_2(features, totals)")).to be_true
    expect(artifact[:source].include?("best = c if probabilities\[c\] > probabilities\[best\]")).to be_true

  it "makes compiled classifier labels and probabilities match the live forest" ->
    model = forest_export_classifier
    queries = [[nil], [forest_export_nan], [0], [3], [7]]
    live_labels = model.predict(queries)
    exported_labels = []
    exported_probabilities = []
    compact_labels = []
    compact_probabilities = []
    queries.each -> (row)
      exported_labels.push(forest_fixture(row, 1496648082))
      exported_probabilities.push(forest_fixture_predict_proba(row, 1496648082))
      compact_labels.push(compact_forest(row, 872449085))
      compact_probabilities.push(compact_forest_predict_proba(row, 872449085))
    expect(exported_labels.to_s).to eq(live_labels.to_s)
    expect(exported_probabilities.to_s).to eq(model.predict_proba(queries).to_s)
    expect(compact_labels.to_s).to eq(live_labels.to_s)
    expect(compact_probabilities.to_s).to eq(model.predict_proba(queries).to_s)

  it "exports a regression mean with exact round-trip leaf values" ->
    model = forest_export_regressor
    artifact = RandomForestExport.export(
      model, [:x], :regression_forest_fixture
    )
    expect(artifact != nil).to be_true
    expect(artifact[:forest_kind]).to eq("regressor")
    expect(artifact[:source].include?("~43.799999999999997")).to be_true
    expect(artifact[:source].include?("total / ~3.0")).to be_true
    queries = [[nil], [forest_export_nan], [0], [3], [7]]
    live = model.predict(queries)
    same = true
    queries.each_with_index -> (row, i)
      same = false if regression_forest_fixture(row, 1496648082) != live[i]
    expect(same).to be_true

  it "enforces the generated feature ABI and input contract" ->
    expect(-> () forest_fixture([0], 1496648081)).to raise_error
    expect(-> () forest_fixture([], 1496648082)).to raise_error
    expect(-> () forest_fixture([0, 1], 1496648082)).to raise_error
    expect(forest_fixture(["bad"], 1496648082)).to be_nil
    infinity = 1.to_f
    1100.times -> (i)
      infinity *= 2.to_f
    expect(forest_fixture([infinity], 1496648082)).to be_nil

  it "changes its checksum when feature order drifts" ->
    two_feature = RandomForestClassifier.new(
      2, :all, 1, 1, 3, :gini, false
    ).fit([[0, 1], [1, 0]], [0, 1])
    original = RandomForestExport.export(two_feature, [:left, :right], :route)
    reordered = RandomForestExport.export(two_feature, [:right, :left], :route)
    expect(original[:schema_checksum] == reordered[:schema_checksum]).to be_false
    expect(original[:schema_checksum] == DecisionTreeExport.schema_checksum(["left", "right"])).to be_false

  it "exports String and Symbol labels through unrolled and compact soft voting" ->
    x = [[0], [1], [2], [3], [4], [5], [6], [7], [nil]]
    even = "even\[arm\]"
    odd = "odd\[arm\]".to_sym
    y = [even, odd, even, odd, even, odd, even, odd, odd]
    model = RandomForestClassifier.new(
      3, :all, 1, 1, 7, :gini, true
    ).fit(x, y)
    unrolled = RandomForestExport.export(
      model, [:x], :forest_text_fixture
    )
    compact = RandomForestExport.export_compact(
      model, [:x], :compact_forest_text_fixture
    )
    expect(unrolled != nil).to be_true
    expect(compact != nil).to be_true
    expect(unrolled[:source].include?(DecisionTreeExport.prediction_literal(even))).to be_true
    expect(unrolled[:source].include?(DecisionTreeExport.prediction_literal(odd))).to be_true
    expect(compact[:source].include?(DecisionTreeExport.prediction_literal(even))).to be_true
    expect(compact[:source].include?(DecisionTreeExport.prediction_literal(odd))).to be_true
    queries = [[nil], [forest_export_nan], [0], [3], [7]]
    live = model.predict(queries)
    compiled_unrolled = []
    compiled_compact = []
    queries.each -> (row)
      compiled_unrolled.push(forest_text_fixture(row, 1496648082))
      compiled_compact.push(compact_forest_text_fixture(row, 872449085))
    expect(compiled_unrolled.to_s).to eq(live.to_s)
    expect(compiled_compact.to_s).to eq(live.to_s)
    expect(compiled_unrolled[0].is_a?(Symbol)).to be_true
    expect(compiled_unrolled[2].is_a?(String)).to be_true

  it "refuses unfitted, malformed and unsupported-label forests" ->
    expect(RandomForestExport.export(RandomForestClassifier.new, [:x])).to be_nil
    model = forest_export_classifier
    expect(RandomForestExport.export(model, nil)).to be_nil
    expect(RandomForestExport.export(model, [:x, :y])).to be_nil
    expect(RandomForestExport.export(model, [:x], "bad-name")).to be_nil
    unsupported = RandomForestClassifier.new(
      2, :all, 1, 1, 3, :gini, false
    ).fit([[0], [1]], ["left", "bad" + 1.chr])
    expect(RandomForestExport.export(unsupported, [:x])).to be_nil

  it "provides a source convenience and a safe default function name" ->
    model = forest_export_regressor
    artifact = RandomForestExport.export(model, [:x])
    expect(artifact[:function_name]).to eq("koala_forest_predict")
    expect(RandomForestExport.source(model, [:x])).to eq(artifact[:source])

  it "offers a deterministic compact classifier layout over flat constants" ->
    model = forest_export_classifier
    artifact = RandomForestExport.export_compact(
      model, [:x], :compact_forest
    )
    again = RandomForestExport.export_compact(
      model, ["x"], "compact_forest"
    )
    expect(artifact[:format]).to eq("koala-random-forest-compact-source")
    expect(artifact[:forest_kind]).to eq("classifier")
    expect(artifact[:tree_count]).to eq(3)
    expect(artifact[:node_count]).to eq(9)
    expect(artifact[:split_count]).to eq(3)
    expect(artifact[:leaf_count]).to eq(6)
    expect(artifact[:schema_checksum] == 1496648082).to be_false
    expect(artifact[:source]).to eq(again[:source])
    expect(artifact[:source].include?("COMPACT_FOREST_ROOTS = \[0, 1, 2\]")).to be_true
    expect(artifact[:source].include?("-> compact_forest_accumulate(features, totals, root)")).to be_true
    expect(artifact[:source].include?("while index >= 0")).to be_true
    expect(RandomForestExport.source_compact(model, [:x], :compact_forest)).to eq(artifact[:source])

  it "compacts regression values and keeps the same refusal contract" ->
    model = forest_export_regressor
    artifact = RandomForestExport.export_compact(
      model, [:x], :compact_regression
    )
    expect(artifact[:forest_kind]).to eq("regressor")
    expect(artifact[:node_count]).to eq(9)
    expect(artifact[:split_count]).to eq(3)
    expect(artifact[:leaf_count]).to eq(6)
    expect(artifact[:source].include?("COMPACT_REGRESSION_VALUES = \[")).to be_true
    expect(artifact[:source].include?("-> compact_regression_tree_value(features, root)")).to be_true
    unsupported = RandomForestClassifier.new(
      2, :all, 1, 1, 3, :gini, false
    ).fit([[0], [1]], ["left", "bad" + 1.chr])
    expect(RandomForestExport.export_compact(unsupported, [:x])).to be_nil

spec_summary
