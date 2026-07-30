# Offline formula-router training support.
#
# This file is intentionally outside Wassat's runtime library. It loads Koala
# only for an offline, compiled training executable and leaves the competition
# solver free of an ML runtime dependency.
#
# Input is deliberately simple, unquoted CSV with one row per instance:
#
#   instance_sha256,family_id,split,label,utility,weight,<31 static features>
#
# `split` is one of train/validation/test and is trusted only after this loader
# proves that a family and an instance occur in exactly one split. `label` is a
# binary Integer arm id (0 baseline, 1 treatment). `utility` is the signed
# paired delta `baseline PAR-2 - treatment PAR-2`: positive favours treatment,
# negative favours baseline. `weight` is a positive sampling or importance
# weight. See router_trainer.md for the exact cost semantics and limitations.
#
# Every model receives the same train-only sample weights. Tree models use the
# raw integer features. Linear models use a weighted standardization fitted on
# train only. Predictions are scored externally with the same classification,
# utility/regret, false-disable, and family-macro metrics; estimator `.score`
# is never used as a substitute for the routing objective.

use ../../tungsten-koala/lib/koala

+ RouterTrainer
  -> .metadata_names
    ["instance_sha256", "family_id", "split", "label", "utility", "weight"]

  # Must stay byte-for-byte ordered with FEATURE_NAMES in router_dataset.py.
  -> .feature_names
    [
      "nvars",
      "nclauses",
      "nlits",
      "used_vars",
      "max_clause",
      "units",
      "binary",
      "ternary",
      "width4",
      "width5_7",
      "width8_plus",
      "positive_literals",
      "negative_literals",
      "horn_clauses",
      "dual_horn_clauses",
      "all_positive_clauses",
      "all_negative_clauses",
      "variable_degree_max",
      "variable_degree_p50",
      "variable_degree_p90",
      "variable_degree_p99",
      "clause_span_sum",
      "exact_one_sketch_candidates",
      "exact_one_sketch_pair_coverage_ppm",
      "exact_one_sketch_full_groups",
      "binary_graph_edges",
      "binary_graph_vertices",
      "binary_graph_degree_max",
      "variable_occurrence_top1_ppm",
      "variable_occurrence_top10_ppm",
      "variable_occurrence_hhi_ppm"
    ]

  # Explicitly pinned beside the ordered feature construction. The computed
  # Koala checksum is verified before loading or training, so an accidental
  # reorder/rename cannot silently consume or export a mismatched dataset.
  -> .feature_schema_version
    2

  -> .feature_schema_checksum
    944208648

  -> .extractor_schema_sha256
    "6c74c4ea6a670c9ff8aab655baa60243d4f34c2869d3accd91d9924afea244ca"

  -> .feature_schema_valid?
    DecisionTreeExport.schema_checksum(RouterTrainer.feature_names) == RouterTrainer.feature_schema_checksum

  -> .csv_columns
    out = []
    RouterTrainer.metadata_names.each -> (name)
      out.push(name)
    RouterTrainer.feature_names.each -> (name)
      out.push(name)
    out

  -> .index_of(values, wanted)
    found = -1
    i = 0
    while i < values.size && found < 0
      found = i if values[i] == wanted
      i += 1
    found

  -> .unsigned_integer_text?(text)
    ok = text != nil && text.size > 0
    i = 0
    while i < text.size
      byte = text.bytes[i]
      ok = false if byte < 48 || byte > 57
      i += 1
    ok

  # Canonical enough for an audit CSV: optional sign, digits, at most one
  # decimal point, and an optional signed decimal exponent. Python's CSV
  # producer legitimately chooses exponent notation for small paired deltas,
  # so refusing it would make router_labels.py output unloadable. Non-finite
  # and locale-specific spellings remain refused.
  -> .decimal_text?(text)
    ok = text != nil && text.size > 0
    i = 0
    if ok && (text.slice(0, 1) == "+" || text.slice(0, 1) == "-")
      i = 1
      ok = false if text.size == 1
    dot = false
    digit = false
    while ok && i < text.size && text.bytes[i] != 69 && text.bytes[i] != 101
      byte = text.bytes[i]
      if byte >= 48 && byte <= 57
        digit = true
      elsif byte == 46 && !dot
        dot = true
      else
        ok = false
      i += 1
    ok = false if !digit
    if ok && i < text.size
      i += 1
      if i < text.size && (text.bytes[i] == 43 || text.bytes[i] == 45)
        i += 1
      exponent_digit = false
      while i < text.size
        byte = text.bytes[i]
        if byte >= 48 && byte <= 57
          exponent_digit = true
        else
          ok = false
        i += 1
      ok = false if !exponent_digit
    ok && i == text.size

  -> .hex_sha256?(text)
    ok = text != nil && text.size == 64
    i = 0
    while i < text.size
      byte = text.bytes[i]
      hex = (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
      ok = false if !hex
      i += 1
    ok

  -> .finite?(value)
    value == value && value - value == 0.to_f

  -> .bounded_feature_max(name)
    maximum = nil
    maximum = 4096 if name == "exact_one_sketch_candidates"
    maximum = 1000000 if name == "exact_one_sketch_pair_coverage_ppm"
    maximum = 4096 if name == "exact_one_sketch_full_groups"
    maximum = 1000000 if name == "variable_occurrence_top1_ppm"
    maximum = 1000000 if name == "variable_occurrence_top10_ppm"
    maximum = 1000000 if name == "variable_occurrence_hhi_ppm"
    maximum

  -> .parse_row(fields, line_number)
    expected = RouterTrainer.csv_columns.size
    if fields.size != expected
      return { ok: false, error: "line " + line_number.to_s + ": expected " + expected.to_s + " columns, got " + fields.size.to_s }
    sha = fields[0].strip
    family = fields[1].strip
    split = fields[2].strip
    label_text = fields[3].strip
    utility_text = fields[4].strip
    weight_text = fields[5].strip
    if !RouterTrainer.hex_sha256?(sha)
      return { ok: false, error: "line " + line_number.to_s + ": instance_sha256 must be 64 lowercase hex characters" }
    if family == ""
      return { ok: false, error: "line " + line_number.to_s + ": family_id is empty" }
    if split != "train" && split != "validation" && split != "test"
      return { ok: false, error: "line " + line_number.to_s + ": split must be train, validation, or test" }
    if !RouterTrainer.unsigned_integer_text?(label_text)
      return { ok: false, error: "line " + line_number.to_s + ": label must be binary Integer 0 or 1" }
    if !RouterTrainer.decimal_text?(utility_text)
      return { ok: false, error: "line " + line_number.to_s + ": utility must be a plain decimal" }
    if !RouterTrainer.decimal_text?(weight_text)
      return { ok: false, error: "line " + line_number.to_s + ": weight must be a plain decimal" }
    utility = utility_text.to_f
    weight = weight_text.to_f
    if !RouterTrainer.finite?(utility)
      return { ok: false, error: "line " + line_number.to_s + ": utility must be finite" }
    if !RouterTrainer.finite?(weight) || weight <= 0.to_f
      return { ok: false, error: "line " + line_number.to_s + ": weight must be finite and positive" }
    label = label_text.to_i
    if label != 0 && label != 1
      return { ok: false, error: "line " + line_number.to_s + ": label must be binary Integer 0 or 1" }
    if label == 1 && utility <= 0.to_f
      return { ok: false, error: "line " + line_number.to_s + ": treatment label 1 requires positive utility" }
    features = []
    i = 6
    while i < fields.size
      text = fields[i].strip
      name = RouterTrainer.feature_names[i - 6]
      if !RouterTrainer.unsigned_integer_text?(text)
        return { ok: false, error: "line " + line_number.to_s + ": feature " + name + " must be a nonnegative Integer" }
      value = text.to_i
      features.push(value)
      maximum = RouterTrainer.bounded_feature_max(name)
      if maximum != nil && value > maximum
        return { ok: false, error: "line " + line_number.to_s + ": feature " + name + " exceeds bounded maximum " + maximum.to_s }
      i += 1
    candidates = features[22]
    full_groups = features[24]
    if full_groups > candidates
      return { ok: false, error: "line " + line_number.to_s + ": exact-one full groups exceed sampled candidates" }
    if features[25] > features[6]
      return { ok: false, error: "line " + line_number.to_s + ": binary graph edges exceed binary clauses" }
    if features[26] > features[3] || features[26] > features[0]
      return { ok: false, error: "line " + line_number.to_s + ": binary graph vertices exceed used or declared variables" }
    {
      ok: true,
      row: {
        instance_sha256: sha,
        family_id: family,
        split: split,
        label: label,
        utility: utility,
        weight: weight,
        features: features
      }
    }

  -> .load_csv_text(text)
    if text == nil
      return { ok: false, error: "CSV text is nil" }
    if !RouterTrainer.feature_schema_valid?
      return {
        ok: false,
        error: "router feature schema checksum drift: expected " +
          RouterTrainer.feature_schema_checksum.to_s + ", computed " +
          DecisionTreeExport.schema_checksum(RouterTrainer.feature_names).to_s
      }
    lines = text.split("\n")
    header = nil
    rows = []
    line_number = 0
    lines.each -> (raw)
      line_number += 1
      line = raw.strip
      if line != ""
        if line.include?("\"")
          return { ok: false, error: "line " + line_number.to_s + ": quoted CSV is not supported" }
        fields = line.split(",")
        if header == nil
          header = fields
        else
          parsed = RouterTrainer.parse_row(fields, line_number)
          return parsed if !parsed[:ok]
          rows.push(parsed[:row])
    if header == nil
      return { ok: false, error: "CSV is empty" }
    expected = RouterTrainer.csv_columns
    if header.size != expected.size
      return { ok: false, error: "CSV header has " + header.size.to_s + " columns; expected " + expected.size.to_s }
    i = 0
    while i < expected.size
      if header[i].strip != expected[i]
        return { ok: false, error: "CSV header column " + i.to_s + " must be " + expected[i] + ", got " + header[i].strip }
      i += 1
    if rows.size == 0
      return { ok: false, error: "CSV has no data rows" }
    checked = RouterTrainer.validate_rows(rows)
    return checked if !checked[:ok]
    {
      ok: true,
      rows: rows,
      feature_names: RouterTrainer.feature_names,
      family_counts: checked[:family_counts],
      split_counts: checked[:split_counts]
    }

  -> .load_csv(path)
    text = read_file(path)
    if text == nil
      return { ok: false, error: "could not read CSV: " + path }
    RouterTrainer.load_csv_text(text)

  # Group leakage is a hard error. The caller may choose the split assignment,
  # but cannot accidentally place siblings from one family on both sides.
  -> .validate_rows(rows)
    shas = []
    families = []
    family_splits = []
    split_counts = [0, 0, 0]
    ok = true
    error = nil
    rows.each -> (row)
      sha = row[:instance_sha256]
      if shas.include?(sha)
        ok = false
        error = "duplicate instance_sha256: " + sha
      shas.push(sha) if ok
      split = row[:split]
      split_index = 0
      split_index = 1 if split == "validation"
      split_index = 2 if split == "test"
      split_counts[split_index] += 1
      if row[:label] != 0 && row[:label] != 1
        ok = false
        error = "label must be binary Integer 0 or 1"
      elsif row[:label] == 1 && row[:utility] <= 0.to_f
        ok = false
        error = "treatment label 1 requires positive utility"
      fi = RouterTrainer.index_of(families, row[:family_id])
      if fi < 0
        families.push(row[:family_id])
        family_splits.push(split)
      elsif family_splits[fi] != split
        ok = false
        error = "family " + row[:family_id] + " leaks across " + family_splits[fi] + " and " + split
    if ok && (split_counts[0] == 0 || split_counts[1] == 0 || split_counts[2] == 0)
      ok = false
      error = "train, validation, and test must each contain at least one row"
    train_labels = []
    if ok
      rows.each -> (row)
        train_labels.push(row[:label]) if row[:split] == "train" && !train_labels.include?(row[:label])
      if train_labels.size != 2 || !train_labels.include?(0) || !train_labels.include?(1)
        ok = false
        error = "training split must contain both binary labels 0 and 1"
    if ok
      rows.each -> (row)
        if row[:split] != "train" && !train_labels.include?(row[:label])
          ok = false
          error = row[:split] + " contains label " + row[:label].to_s + " absent from training"
    if !ok
      return { ok: false, error: error }
    family_counts = [0, 0, 0]
    i = 0
    while i < families.size
      index = 0
      index = 1 if family_splits[i] == "validation"
      index = 2 if family_splits[i] == "test"
      family_counts[index] += 1
      i += 1
    { ok: true, family_counts: family_counts, split_counts: split_counts }

  -> .rows_for_split(rows, split)
    out = []
    rows.each -> (row)
      out.push(row) if row[:split] == split
    out

  -> .features_of(rows)
    out = []
    rows.each -> (row)
      values = []
      row[:features].each -> (value)
        values.push(value)
      out.push(values)
    out

  -> .labels_of(rows)
    out = []
    rows.each -> (row)
      out.push(row[:label])
    out

  -> .weights_of(rows)
    out = []
    rows.each -> (row)
      out.push(row[:weight])
    out

  -> .training_classes(rows)
    out = []
    rows.each -> (row)
      label = row[:label]
      out.push(label) if !out.include?(label)
    out

  # Weighted standardization, fitted ONLY on train. Constant features use a
  # scale of one and therefore remain zero after centering.
  -> .fit_scale(rows)
    width = rows[0][:features].size
    means = []
    width.times -> (j)
      means.push(0.to_f)
    total_weight = 0.to_f
    rows.each -> (row)
      weight = row[:weight]
      total_weight += weight
      j = 0
      while j < width
        means[j] += weight * row[:features][j].to_f
        j += 1
    j = 0
    while j < width
      means[j] /= total_weight
      j += 1
    variances = []
    width.times -> (k)
      variances.push(0.to_f)
    rows.each -> (row)
      weight = row[:weight]
      j = 0
      while j < width
        delta = row[:features][j].to_f - means[j]
        variances[j] += weight * delta * delta
        j += 1
    scales = []
    j = 0
    while j < width
      variance = variances[j] / total_weight
      scale = 1.to_f
      scale = Math.sqrt(variance) if variance > 0.to_f
      scales.push(scale)
      j += 1
    { means: means, scales: scales }

  -> .transform_rows(rows, scale)
    out = []
    rows.each -> (row)
      values = []
      j = 0
      while j < row[:features].size
        values.push((row[:features][j].to_f - scale[:means][j]) / scale[:scales][j])
        j += 1
      out.push(values)
    out

  -> .nearest_classes(values, classes)
    out = []
    values.each -> (value)
      best = classes[0]
      best_distance = LinAlg.fabs(value.to_f - best.to_f)
      i = 1
      while i < classes.size
        distance = LinAlg.fabs(value.to_f - classes[i].to_f)
        if distance < best_distance
          best = classes[i]
          best_distance = distance
        i += 1
      out.push(best)
    out

  -> .constant_predictions(rows, label)
    out = []
    rows.each -> (row)
      out.push(label)
    out

  -> .weighted_majority_label(rows, classes)
    totals = []
    classes.each -> (label)
      totals.push(0.to_f)
    rows.each -> (row)
      index = RouterTrainer.index_of(classes, row[:label])
      totals[index] += row[:weight]
    best = 0
    i = 1
    while i < totals.size
      best = i if totals[i] > totals[best]
      i += 1
    classes[best]

  # Classification and routing cost metrics for signed treatment delta.
  # Predicting arm 0 realizes zero utility; predicting arm 1 realizes the
  # signed `baseline PAR-2 - treatment PAR-2` delta. Oracle utility is the
  # positive part of that delta. Regret = oracle - realized, so enabling a
  # harmful treatment is penalized without inventing a second cost column.
  -> .evaluate(rows, predictions, classes)
    if predictions == nil || predictions.size != rows.size
      return nil
    total_weight = 0.to_f
    weighted_correct = 0.to_f
    correct = 0
    oracle_utility = 0.to_f
    realized_utility = 0.to_f
    false_disable_cost = 0.to_f
    false_disable_count = 0
    i = 0
    while i < rows.size
      row = rows[i]
      prediction = predictions[i]
      weight = row[:weight]
      delta = weight * row[:utility]
      total_weight += weight
      oracle_utility += delta if delta > 0.to_f
      if prediction == row[:label]
        correct += 1
        weighted_correct += weight
      realized_utility += delta if prediction == 1
      if row[:label] != 0 && prediction == 0
        false_disable_cost += delta
        false_disable_count += 1
      i += 1
    macro_f1 = 0.to_f
    classes.each -> (label)
      tp = 0.to_f
      fp = 0.to_f
      missed = 0.to_f
      i = 0
      while i < rows.size
        actual = rows[i][:label]
        predicted = predictions[i]
        tp += 1.to_f if actual == label && predicted == label
        fp += 1.to_f if actual != label && predicted == label
        missed += 1.to_f if actual == label && predicted != label
        i += 1
      precision = 0.to_f
      recall = 0.to_f
      precision = tp / (tp + fp) if tp + fp > 0.to_f
      recall = tp / (tp + missed) if tp + missed > 0.to_f
      f1 = 0.to_f
      f1 = 2.to_f * precision * recall / (precision + recall) if precision + recall > 0.to_f
      macro_f1 += f1
    macro_f1 /= classes.size.to_f
    utility_capture = 1.to_f
    if oracle_utility > 0.to_f
      utility_capture = realized_utility / oracle_utility
    elsif realized_utility < 0.to_f
      utility_capture = 0.to_f
    regret = oracle_utility - realized_utility

    families = []
    rows.each -> (row)
      families.push(row[:family_id]) if !families.include?(row[:family_id])
    family_accuracy = 0.to_f
    family_utility_capture = 0.to_f
    family_regret = 0.to_f
    families.each -> (family)
      family_weight = 0.to_f
      family_correct = 0.to_f
      family_oracle = 0.to_f
      family_realized = 0.to_f
      i = 0
      while i < rows.size
        if rows[i][:family_id] == family
          weight = rows[i][:weight]
          delta = weight * rows[i][:utility]
          family_weight += weight
          family_oracle += delta if delta > 0.to_f
          family_realized += delta if predictions[i] == 1
          if predictions[i] == rows[i][:label]
            family_correct += weight
        i += 1
      family_accuracy += family_correct / family_weight
      capture = 1.to_f
      if family_oracle > 0.to_f
        capture = family_realized / family_oracle
      elsif family_realized < 0.to_f
        capture = 0.to_f
      family_utility_capture += capture
      family_regret += (family_oracle - family_realized) / family_weight
    family_accuracy /= families.size.to_f
    family_utility_capture /= families.size.to_f
    family_regret /= families.size.to_f
    {
      rows: rows.size,
      families: families.size,
      accuracy: correct.to_f / rows.size.to_f,
      weighted_accuracy: weighted_correct / total_weight,
      macro_f1: macro_f1,
      oracle_utility: oracle_utility,
      realized_utility: realized_utility,
      realized_utility_per_weight: realized_utility / total_weight,
      utility_capture: utility_capture,
      regret: regret,
      regret_per_weight: regret / total_weight,
      false_disable_count: false_disable_count,
      false_disable_cost: false_disable_cost,
      false_disable_per_weight: false_disable_cost / total_weight,
      family_accuracy: family_accuracy,
      family_utility_capture: family_utility_capture,
      family_regret_per_weight: family_regret
    }

  # Family-macro regret is primary so a large generator family cannot elect
  # the router by row count. Row-weighted regret/utility, false-disable cost,
  # and classification metrics provide deterministic tie-breaks.
  -> .better_metrics?(candidate, incumbent)
    if incumbent == nil
      return true
    tolerance = 1.to_f / 1000000000000.to_f
    fields = [
      [:family_regret_per_weight, 0 - 1],
      [:regret_per_weight, 0 - 1],
      [:family_utility_capture, 1],
      [:utility_capture, 1],
      [:realized_utility_per_weight, 1],
      [:false_disable_per_weight, 0 - 1],
      [:family_accuracy, 1],
      [:weighted_accuracy, 1],
      [:macro_f1, 1]
    ]
    i = 0
    while i < fields.size
      key = fields[i][0]
      direction = fields[i][1]
      delta = (candidate[key] - incumbent[key]) * direction.to_f
      return true if delta > tolerance
      return false if delta < 0.to_f - tolerance
      i += 1
    false

  -> .fit_candidate(name, model, raw_train, scaled_train, labels, weights, uses_scaled, regression, exportable)
    x = raw_train
    x = scaled_train if uses_scaled
    weight_support = model.supports_sample_weight?
    fitted = nil
    fitted = model.fit(x, labels, weights) if weight_support
    {
      name: name,
      model: model,
      fitted: fitted != nil,
      weight_support: weight_support,
      uses_scaled: uses_scaled,
      regression: regression,
      exportable: exportable
    }

  -> .candidate_predictions(candidate, raw_rows, scaled_rows, classes)
    out = nil
    if candidate[:fitted]
      x = raw_rows
      x = scaled_rows if candidate[:uses_scaled]
      values = candidate[:model].predict(x)
      if values != nil
        out = values
        out = RouterTrainer.nearest_classes(values, classes) if candidate[:regression]
    out

  -> .validation_baselines(train_rows, validation_rows, classes)
    majority = RouterTrainer.weighted_majority_label(train_rows, classes)
    zero_predictions = RouterTrainer.constant_predictions(validation_rows, 0)
    majority_predictions = RouterTrainer.constant_predictions(validation_rows, majority)
    zero_metrics = RouterTrainer.evaluate(validation_rows, zero_predictions, classes)
    majority_metrics = RouterTrainer.evaluate(validation_rows, majority_predictions, classes)
    chosen_name = "fixed_arm_0"
    chosen_label = 0
    chosen_metrics = zero_metrics
    if RouterTrainer.better_metrics?(majority_metrics, zero_metrics)
      chosen_name = "train_weighted_majority"
      chosen_label = majority
      chosen_metrics = majority_metrics
    {
      chosen_name: chosen_name,
      chosen_label: chosen_label,
      chosen_metrics: chosen_metrics,
      fixed_arm_0: zero_metrics,
      train_weighted_majority: majority_metrics,
      majority_label: majority
    }

  # A deployable tree must be the validation-selected model, improve utility
  # capture by at least one percentage point over the stronger conservative
  # baseline, not regress family regret or weighted accuracy, and not add
  # false-disable cost.
  -> .tree_gate(candidate, validation_metrics, baseline_metrics)
    if candidate == nil || !candidate[:exportable]
      return { passed: false, reason: "validation-selected model is not an exportable DecisionTreeClassifier" }
    min_gain = 1.to_f / 100.to_f
    utility_gain = validation_metrics[:utility_capture] - baseline_metrics[:utility_capture]
    if utility_gain < min_gain
      return { passed: false, reason: "validation utility capture gain is below 0.01" }
    tolerance = 1.to_f / 1000000000000.to_f
    if validation_metrics[:family_utility_capture] + tolerance < baseline_metrics[:family_utility_capture]
      return { passed: false, reason: "validation family utility capture regresses baseline" }
    if validation_metrics[:weighted_accuracy] + tolerance < baseline_metrics[:weighted_accuracy]
      return { passed: false, reason: "validation weighted accuracy regresses baseline" }
    if validation_metrics[:false_disable_cost] > baseline_metrics[:false_disable_cost] + tolerance
      return { passed: false, reason: "validation false-disable cost exceeds baseline" }
    { passed: true, reason: "selected tree clears conservative validation baseline" }

  -> .train(rows)
    if !RouterTrainer.feature_schema_valid?
      return { ok: false, error: "router feature schema checksum drift" }
    checked = RouterTrainer.validate_rows(rows)
    return checked if !checked[:ok]
    train_rows = RouterTrainer.rows_for_split(rows, "train")
    validation_rows = RouterTrainer.rows_for_split(rows, "validation")
    test_rows = RouterTrainer.rows_for_split(rows, "test")
    classes = RouterTrainer.training_classes(train_rows)
    raw_train = RouterTrainer.features_of(train_rows)
    raw_validation = RouterTrainer.features_of(validation_rows)
    raw_test = RouterTrainer.features_of(test_rows)
    labels = RouterTrainer.labels_of(train_rows)
    weights = RouterTrainer.weights_of(train_rows)
    scale = RouterTrainer.fit_scale(train_rows)
    scaled_train = RouterTrainer.transform_rows(train_rows, scale)
    scaled_validation = RouterTrainer.transform_rows(validation_rows, scale)
    scaled_test = RouterTrainer.transform_rows(test_rows, scale)

    candidates = []
    candidates.push(RouterTrainer.fit_candidate(
      "tree_depth_2", DecisionTreeClassifier.new(2, 2, 1, :gini),
      raw_train, scaled_train, labels, weights, false, false, true
    ))
    candidates.push(RouterTrainer.fit_candidate(
      "tree_depth_3", DecisionTreeClassifier.new(3, 2, 1, :gini),
      raw_train, scaled_train, labels, weights, false, false, true
    ))
    candidates.push(RouterTrainer.fit_candidate(
      "tree_depth_4", DecisionTreeClassifier.new(4, 2, 1, :gini),
      raw_train, scaled_train, labels, weights, false, false, true
    ))
    candidates.push(RouterTrainer.fit_candidate(
      "forest_9_depth_3", RandomForestClassifier.new(9, :sqrt, 3, 1, 1729, :gini, true),
      raw_train, scaled_train, labels, weights, false, false, false
    ))
    candidates.push(RouterTrainer.fit_candidate(
      "linear_svc", SVC.new(1, :linear, :scale, 3, 0, 1.to_f / 1000.to_f, 1000),
      raw_train, scaled_train, labels, weights, true, false, false
    ))
    candidates.push(RouterTrainer.fit_candidate(
      "logistic", LogisticRegression.new(1.to_f / 10.to_f, 500),
      raw_train, scaled_train, labels, weights, true, false, false
    ))
    candidates.push(RouterTrainer.fit_candidate(
      "elastic_l2_alpha_1", ElasticNet.new(1, 0, 1000),
      raw_train, scaled_train, labels, weights, true, true, false
    ))

    baselines = RouterTrainer.validation_baselines(train_rows, validation_rows, classes)
    selected = nil
    selected_metrics = nil
    candidates.each -> (candidate)
      validation_predictions = RouterTrainer.candidate_predictions(
        candidate, raw_validation, scaled_validation, classes
      )
      metrics = RouterTrainer.evaluate(validation_rows, validation_predictions, classes)
      candidate[:validation_metrics] = metrics
      if metrics != nil && RouterTrainer.better_metrics?(metrics, selected_metrics)
        selected = candidate
        selected_metrics = metrics

    if selected == nil
      return { ok: false, error: "every candidate failed to fit or predict validation" }

    # Selection is now locked. Test predictions are computed only for the
    # winner and the two already-defined baselines; no candidate can observe
    # these values.
    selected_test_predictions = RouterTrainer.candidate_predictions(
      selected, raw_test, scaled_test, classes
    )
    selected_test_metrics = RouterTrainer.evaluate(test_rows, selected_test_predictions, classes)
    majority_test = RouterTrainer.constant_predictions(test_rows, baselines[:majority_label])
    zero_test = RouterTrainer.constant_predictions(test_rows, 0)
    baseline_test_predictions = zero_test
    baseline_test_predictions = majority_test if baselines[:chosen_name] == "train_weighted_majority"
    baseline_test_metrics = RouterTrainer.evaluate(test_rows, baseline_test_predictions, classes)

    gate = RouterTrainer.tree_gate(selected, selected_metrics, baselines[:chosen_metrics])
    export = nil
    if gate[:passed]
      export = DecisionTreeExport.export(
        selected[:model],
        RouterTrainer.feature_names,
        :wassat_formula_router
      )
      if export == nil
        gate = { passed: false, reason: "DecisionTreeExport refused the selected fitted tree" }
      elsif export[:schema_checksum] != RouterTrainer.feature_schema_checksum
        export = nil
        gate = { passed: false, reason: "DecisionTreeExport feature schema checksum drift" }

    {
      ok: true,
      feature_names: RouterTrainer.feature_names,
      feature_schema_version: RouterTrainer.feature_schema_version,
      feature_schema_checksum: RouterTrainer.feature_schema_checksum,
      extractor_schema_sha256: RouterTrainer.extractor_schema_sha256,
      split_counts: checked[:split_counts],
      family_counts: checked[:family_counts],
      classes: classes,
      scale: scale,
      baselines: baselines,
      candidates: candidates,
      selected: selected,
      selected_validation_metrics: selected_metrics,
      selected_test_metrics: selected_test_metrics,
      baseline_test_metrics: baseline_test_metrics,
      gate: gate,
      export: export
    }

  -> .metric_line(prefix, metrics)
    out = prefix
    out += " accuracy=" + metrics[:accuracy].to_s
    out += " weighted_accuracy=" + metrics[:weighted_accuracy].to_s
    out += " macro_f1=" + metrics[:macro_f1].to_s
    out += " realized_utility=" + metrics[:realized_utility].to_s
    out += " utility_capture=" + metrics[:utility_capture].to_s
    out += " regret=" + metrics[:regret].to_s
    out += " false_disable=" + metrics[:false_disable_cost].to_s
    out += " family_utility_capture=" + metrics[:family_utility_capture].to_s
    out += " family_regret_per_weight=" + metrics[:family_regret_per_weight].to_s
    out

  -> .report(result)
    lines = []
    if !result[:ok]
      lines.push("router training failed: " + result[:error])
      return lines
    lines.push(
      "dataset rows train=" + result[:split_counts][0].to_s +
      " validation=" + result[:split_counts][1].to_s +
      " test=" + result[:split_counts][2].to_s +
      " families=" + result[:family_counts].join("/") +
      " features=" + result[:feature_names].size.to_s
    )
    baselines = result[:baselines]
    lines.push(RouterTrainer.metric_line(
      "validation baseline fixed_arm_0",
      baselines[:fixed_arm_0]
    ))
    lines.push(RouterTrainer.metric_line(
      "validation baseline train_weighted_majority(label=" + baselines[:majority_label].to_s + ")",
      baselines[:train_weighted_majority]
    ))
    result[:candidates].each -> (candidate)
      if candidate[:validation_metrics] == nil
        failure = "fit_or_predict_failed"
        failure = "sample_weight_unsupported" if !candidate[:weight_support]
        lines.push("validation " + candidate[:name] + " " + failure)
      else
        lines.push(RouterTrainer.metric_line(
          "validation " + candidate[:name],
          candidate[:validation_metrics]
        ))
    selected = result[:selected]
    lines.push("selected_on_train_validation=" + selected[:name])
    lines.push(RouterTrainer.metric_line(
      "locked_test selected=" + selected[:name],
      result[:selected_test_metrics]
    ))
    lines.push(RouterTrainer.metric_line(
      "locked_test conservative_baseline=" + baselines[:chosen_name],
      result[:baseline_test_metrics]
    ))
    lines.push(
      "export_gate=" + result[:gate][:passed].to_s +
      " reason=" + result[:gate][:reason]
    )
    if result[:export] != nil
      lines.push(
        "export schema_version=" + result[:export][:schema_version].to_s +
        " schema_checksum=" + result[:export][:schema_checksum].to_s +
        " function=" + result[:export][:function_name]
      )
    lines
