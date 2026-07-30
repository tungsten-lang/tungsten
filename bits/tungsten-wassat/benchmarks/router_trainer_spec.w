# Compiled tests for the offline Wassat router trainer.
#
#   bin/tungsten -o /tmp/router_trainer_spec \
#     bits/tungsten-wassat/benchmarks/router_trainer_spec.w
#   /tmp/router_trainer_spec

use spec
use ./router_trainer
use ./fixtures/router_tiny_expected

-> router_tiny_csv_path
  __DIR__ + "/fixtures/router_training_tiny.csv"

describe "offline Wassat RouterTrainer" ->
  it "loads the exact metadata plus static-feature CSV ABI and rejects group leakage" ->
    expect(RouterTrainer.decimal_text?("-1.9875005818903446e-05")).to be_true
    expect(RouterTrainer.decimal_text?("1E+3")).to be_true
    expect(RouterTrainer.decimal_text?("1e")).to be_false
    expect(RouterTrainer.decimal_text?("e3")).to be_false

    loaded = RouterTrainer.load_csv(router_tiny_csv_path)
    expect(loaded[:ok]).to be_true
    expect(loaded[:rows].size).to eq(16)
    expect(loaded[:feature_names].size).to eq(31)
    expect(loaded[:feature_names][0]).to eq("nvars")
    expect(loaded[:feature_names][21]).to eq("clause_span_sum")
    expect(loaded[:feature_names][22]).to eq("exact_one_sketch_candidates")
    expect(loaded[:feature_names][30]).to eq("variable_occurrence_hhi_ppm")
    expect(RouterTrainer.feature_schema_valid?).to be_true
    expect(RouterTrainer.feature_schema_version).to eq(2)
    expect(RouterTrainer.feature_schema_checksum).to eq(944208648)
    expect(RouterTrainer.extractor_schema_sha256).to eq(
      "6c74c4ea6a670c9ff8aab655baa60243d4f34c2869d3accd91d9924afea244ca"
    )
    expect(loaded[:split_counts].to_s).to eq("\[8, 4, 4\]")
    expect(loaded[:family_counts].to_s).to eq("\[4, 2, 2\]")

    bounded_fields = read_file(router_tiny_csv_path).split("\n")[1].split(",")
    bounded_fields[29] = "1000001"
    bounded = RouterTrainer.parse_row(bounded_fields, 2)
    expect(bounded[:ok]).to be_false
    expect(bounded[:error].include?("bounded maximum")).to be_true

    leaked = loaded[:rows]
    leaked[1][:split] = "validation"
    checked = RouterTrainer.validate_rows(leaked)
    expect(checked[:ok]).to be_false
    expect(checked[:error].include?("leaks across")).to be_true

    inconsistent = RouterTrainer.load_csv(router_tiny_csv_path)[:rows]
    i = 0
    while inconsistent[i][:label] != 1
      i += 1
    inconsistent[i][:utility] = 0.to_f
    checked = RouterTrainer.validate_rows(inconsistent)
    expect(checked[:ok]).to be_false
    expect(checked[:error].include?("requires positive utility")).to be_true

  it "trains every candidate, selects without test leakage, and clears the conservative gate" ->
    loaded = RouterTrainer.load_csv(router_tiny_csv_path)
    result = RouterTrainer.train(loaded[:rows])
    expect(result[:ok]).to be_true
    expect(result[:candidates].size).to eq(7)
    names = []
    result[:candidates].each -> (candidate)
      names.push(candidate[:name])
      expect(candidate[:fitted]).to be_true
      expect(candidate[:validation_metrics] != nil).to be_true
      # Test metrics never exist on candidate records: only the locked winner
      # is evaluated after selection.
      expect(candidate[:test_metrics]).to be_nil
    expect(names).to eq([
      "tree_depth_2",
      "tree_depth_3",
      "tree_depth_4",
      "forest_9_depth_3",
      "linear_svc",
      "logistic",
      "elastic_l2_alpha_1"
    ])
    expect(result[:selected][:name]).to eq("tree_depth_2")
    expect(result[:selected_validation_metrics][:utility_capture].to_s).to eq("1")
    expect(result[:selected_test_metrics][:utility_capture].to_s).to eq("1")
    expect(result[:selected_test_metrics][:weighted_accuracy].to_s).to eq("1")
    expect(result[:selected_test_metrics][:false_disable_cost].to_s).to eq("0")
    expect(result[:gate][:passed]).to be_true
    expect(result[:export] != nil).to be_true
    baseline_metrics = result[:baselines][:chosen_metrics]
    no_gain = RouterTrainer.tree_gate(result[:selected], baseline_metrics, baseline_metrics)
    expect(no_gain[:passed]).to be_false
    expect(no_gain[:reason].include?("below 0.01")).to be_true
    forest_gate = RouterTrainer.tree_gate(
      result[:candidates][3],
      result[:candidates][3][:validation_metrics],
      baseline_metrics
    )
    expect(forest_gate[:passed]).to be_false
    expect(forest_gate[:reason].include?("not an exportable")).to be_true

  it "reproduces and executes the checked-in standalone generated source" ->
    loaded = RouterTrainer.load_csv(router_tiny_csv_path)
    result = RouterTrainer.train(loaded[:rows])
    expected_source = read_file(__DIR__ + "/fixtures/router_tiny_expected.w")
    expect(result[:export][:source]).to eq(expected_source)
    expect(result[:export][:schema_checksum]).to eq(944208648)
    expect(result[:feature_schema_version]).to eq(2)
    expect(result[:feature_schema_checksum]).to eq(944208648)
    expect(result[:extractor_schema_sha256]).to eq(
      "6c74c4ea6a670c9ff8aab655baa60243d4f34c2869d3accd91d9924afea244ca"
    )
    expect(wassat_formula_router_schema_version).to eq(1)
    expect(wassat_formula_router_feature_count).to eq(31)
    test_rows = RouterTrainer.rows_for_split(loaded[:rows], "test")
    predictions = []
    test_rows.each -> (row)
      predictions.push(wassat_formula_router(row[:features], 944208648))
    expect(predictions.to_s).to eq(RouterTrainer.labels_of(test_rows).to_s)
    expect(-> () wassat_formula_router(test_rows[0][:features], 944208647)).to raise_error
    expect(-> () wassat_formula_router([1, 2], 944208648)).to raise_error
