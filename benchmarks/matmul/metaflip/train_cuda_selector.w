# Offline Koala experiment for the CUDA 7x7 launch scheduler.
#
# The CUDA campaign writes one `CUDA777_EPOCH` row after every exact-gated
# launch. This trainer predicts objective-useful launches (globally competitive
# exact endpoints or same-source door advances), rather than raw novelty.
# It reconstructs only features that were known before the launch, removes
# exact duplicate log rows, uses the first 60% of every run for training, the
# next 20% for model selection, and the final 20% for a strictly later test.
# The exported classifier is standalone Tungsten source; Metaflip does not
# acquire a runtime dependency on Koala.
#
#   bin/tungsten compile benchmarks/matmul/metaflip/train_cuda_selector.w \
#     --out /tmp/train-cuda-selector --release --lto --fast
#   /tmp/train-cuda-selector ~/.tungsten/metaflip/cloud \
#     /tmp/metaflip_cuda_selector.w

use ../../../bits/tungsten-koala/lib/koala
use core/dir

CUDA_SELECTOR_FEATURES = [
  :role,
  :source,
  :partner_mode,
  :seed_density,
  :density_gap,
  :fleet_density,
  :epoch_phase,
  :planned_attempts_m,
  :role_visits,
  :role_novel,
  :role_best,
  :source_generation,
  :source_visits,
  :source_novel,
  :source_useful,
  :source_best,
  :prior_novel_per_million
]

-> ffks_sorted_strings(values)
  out = []
  values.each -> (value)
    slot = out.size
    out.push(value)
    while slot > 0 && out[slot] < out[slot - 1]
      tmp = out[slot - 1]
      out[slot - 1] = out[slot]
      out[slot] = tmp
      slot -= 1
  out

-> ffks_run_logs(root)
  out = []
  pending = [root]
  while pending.size > 0
    path = pending.pop
    if Dir.directory?(path)
      Dir.entries(path).each -> (name)
        child = path + "/" + name
        if Dir.directory?(child)
          pending.push(child)
        elsif name == "run.log"
          out.push(child)
  ffks_sorted_strings(out)

-> ffks_token(line, key)
  prefix = key + "="
  out = nil
  line.split(" ").each -> (token)
    if out == nil && token.starts_with?(prefix)
      out = token.slice(prefix.size, token.size - prefix.size)
  out

-> ffks_int(line, key, fallback = 0)
  token = ffks_token(line, key)
  token == nil ? fallback : token.to_i

-> ffks_role_id(role)
  return 0 if role == "leader"
  return 1 if role == "original"
  return 2 if role == "descendant"
  0 - 1

-> ffks_scheme_part(line, key, marker)
  token = ffks_token(line, key)
  return 0 if token == nil
  at = token.index(marker)
  return 0 if at == nil
  token.slice(at + marker.size, token.size - at - marker.size).to_i

-> ffks_stat_value(segment, key, fallback = 0)
  out = fallback
  segment.split(",").each -> (token)
    if token.starts_with?(key)
      tail = token.slice(key.size, token.size - key.size)
      out = tail.to_i if tail != "-"
  out

-> ffks_role_segment(line, role_id)
  token = ffks_token(line, "role_stats")
  return nil if token == nil
  parts = token.split(";")
  return nil if role_id < 0 || role_id >= parts.size
  segment = parts[role_id]
  colon = segment.index(":")
  return nil if colon == nil
  segment.slice(colon + 1, segment.size - colon - 1)

-> ffks_source_segment(line, role_id, source)
  field = ""
  field = "original_sources" if role_id == 1
  field = "descendant_sources" if role_id == 2
  return nil if field == ""
  token = ffks_token(line, field)
  return nil if token == nil || token == ""
  wanted = source.to_s + ":"
  out = nil
  token.split(";").each -> (segment)
    if out == nil && segment.starts_with?(wanted)
      out = segment.slice(wanted.size, segment.size - wanted.size)
  out

-> ffks_exact_novel(line)
  result = ffks_token(line, "result")
  (result == "exact-novel" || result == "fleet-best") ? 1 : 0

-> ffks_label(line)
  # New logs expose the scheduler's exact credit signal. Older campaign logs
  # predate that field; a same-source replacement or a fleet-best endpoint is
  # a conservative, directly observable subset of the same objective.
  explicit = ffks_token(line, "epoch_objective_useful")
  return explicit.to_i if explicit != nil
  result = ffks_token(line, "result")
  return 1 if result == "fleet-best"
  ffks_int(line, "epoch_door_source_replace") == 1 ? 1 : 0

-> ffks_features(line)
  role_id = ffks_role_id(ffks_token(line, "role"))
  return nil if role_id < 0
  source = ffks_int(line, "source")
  mode = ffks_int(line, "mode")
  epoch = ffks_int(line, "epoch")
  seed_density = ffks_scheme_part(line, "seed", "/d")
  fleet_density = ffks_scheme_part(line, "fleet_best", "/d")
  attempts_m = ffks_int(line, "attempts") / 1000000
  label = ffks_label(line)
  novel = ffks_exact_novel(line)

  role_segment = ffks_role_segment(line, role_id)
  role_visits = 0
  role_novel = 0
  role_best = 0
  if role_segment != nil
    role_visits = ffks_stat_value(role_segment, "v")
    role_novel = ffks_stat_value(role_segment, "n")
    role_best = ffks_stat_value(role_segment, "b")
  role_visits -= 1 if role_visits > 0
  role_novel -= 1 if novel == 1 && role_novel > 0
  result = ffks_token(line, "result")
  role_best -= 1 if result == "fleet-best" && role_best > 0

  source_segment = ffks_source_segment(line, role_id, source)
  source_generation = 0
  source_visits = 0
  source_novel = 0
  source_useful = 0
  source_best = 0
  if source_segment != nil
    source_generation = ffks_stat_value(source_segment, "g")
    source_visits = ffks_stat_value(source_segment, "v")
    source_novel = ffks_stat_value(source_segment, "n")
    source_useful = ffks_stat_value(source_segment, "u")
    source_best = ffks_stat_value(source_segment, "b")
  source_visits -= 1 if source_visits > 0
  source_novel -= 1 if novel == 1 && source_novel > 0
  source_useful -= 1 if label == 1 && source_useful > 0
  source_best -= 1 if result == "fleet-best" && source_best > 0

  epoch_novel = ffks_int(line, "harvest_epoch_novel")
  total_novel = ffks_int(line, "harvest_total_novel") - epoch_novel
  epoch_completed = ffks_int(line, "harvest_epoch_completed")
  total_completed = ffks_int(line, "harvest_total_completed") - epoch_completed
  total_novel = 0 if total_novel < 0
  total_completed = 0 if total_completed < 0
  prior_rate = total_novel * 1000000 / (total_completed + 1)

  [
    role_id,
    source,
    mode,
    seed_density,
    seed_density - fleet_density,
    fleet_density,
    epoch % 4,
    attempts_m,
    role_visits,
    role_novel,
    role_best,
    source_generation,
    source_visits,
    source_novel,
    source_useful,
    source_best,
    prior_rate
  ]

-> ffks_epoch_lines(path, seen)
  text = read_file(path)
  out = []
  if text != nil
    text.split("\n").each -> (line)
      if line.starts_with?("CUDA777_EPOCH ") && !seen.has_key?(line)
        features = ffks_features(line)
        if features != nil
          seen[line] = true
          out.push({ x: features, y: ffks_label(line) })
  out

-> ffks_append_partition(rows, train_x, train_y, valid_x, valid_y, test_x, test_y)
  count = rows.size
  i = 0
  while i < count
    bucket = i * 5 / count
    if bucket < 3
      train_x.push(rows[i][:x])
      train_y.push(rows[i][:y])
    elsif bucket == 3
      valid_x.push(rows[i][:x])
      valid_y.push(rows[i][:y])
    else
      test_x.push(rows[i][:x])
      test_y.push(rows[i][:y])
    i += 1

-> ffks_metrics(model, x, y)
  preds = model.predict(x)
  probs = model.predict_proba(x, 1)
  tp = 0
  tn = 0
  fp = 0
  false_negative = 0
  predicted_positive = 0
  probability_sum = 0.to_f
  i = 0
  while i < y.size
    actual = y[i]
    predicted = preds[i]
    probability_sum += probs[i]
    if predicted == 1
      predicted_positive += 1
      if actual == 1
        tp += 1
      else
        fp += 1
    else
      if actual == 1
        false_negative += 1
      else
        tn += 1
    i += 1
  precision = tp.to_f / (tp + fp).to_f if tp + fp > 0
  precision = 0.to_f if tp + fp == 0
  recall = tp.to_f / (tp + false_negative).to_f if tp + false_negative > 0
  recall = 0.to_f if tp + false_negative == 0
  specificity = tn.to_f / (tn + fp).to_f if tn + fp > 0
  specificity = 0.to_f if tn + fp == 0
  f1 = 0.to_f
  f1 = 2.to_f * precision * recall / (precision + recall) if precision + recall > 0.to_f
  accuracy = (tp + tn).to_f / y.size.to_f
  {
    accuracy: accuracy,
    precision: precision,
    recall: recall,
    specificity: specificity,
    balanced_accuracy: (recall + specificity) / 2.to_f,
    f1: f1,
    coverage: predicted_positive.to_f / y.size.to_f,
    mean_probability: probability_sum / y.size.to_f,
    tp: tp,
    tn: tn,
    fp: fp,
    false_negative: false_negative
  }

-> ffks_metric_line(name, metrics)
  body = "CUDA_SELECTOR_METRIC split=" + name
  body += " accuracy=" + metrics[:accuracy].to_s
  body += " precision=" + metrics[:precision].to_s
  body += " recall=" + metrics[:recall].to_s
  body += " specificity=" + metrics[:specificity].to_s
  body += " balanced_accuracy=" + metrics[:balanced_accuracy].to_s
  body += " f1=" + metrics[:f1].to_s
  body += " coverage=" + metrics[:coverage].to_s
  body += " mean_probability=" + metrics[:mean_probability].to_s
  body += " tp=" + metrics[:tp].to_s
  body += " tn=" + metrics[:tn].to_s
  body += " fp=" + metrics[:fp].to_s
  body += " fn=" + metrics[:false_negative].to_s
  body

-> ffks_positive_rate(labels)
  positives = 0
  labels.each -> (label)
    positives += label
  positives.to_f / labels.size.to_f

-> ffks_balanced_weights(labels)
  positives = 0
  labels.each -> (label)
    positives += label
  negatives = labels.size - positives
  positive_weight = 1.to_f
  if positives > 0
    positive_weight = negatives.to_f / positives.to_f
    # The historical proxy is sparse. Fully balancing it lets a handful of
    # old events dominate every split, so retain a bounded minority boost.
    positive_weight = 16.to_f if positive_weight > 16.to_f
  out = []
  labels.each -> (label)
    out.push(label == 1 ? positive_weight : 1.to_f)
  out

-> ffks_model_report(name, model, train_x, train_y, valid_x, valid_y, test_x, test_y, elapsed_ms)
  << "CUDA_SELECTOR_MODEL name=" + name + " train_ms=" + elapsed_ms.to_s
  << ffks_metric_line(name + "-train", ffks_metrics(model, train_x, train_y))
  << ffks_metric_line(name + "-valid", ffks_metrics(model, valid_x, valid_y))
  << ffks_metric_line(name + "-test", ffks_metrics(model, test_x, test_y))

-> ffks_importance_report(name, values)
  if values != nil
    order = []
    i = 0
    while i < values.size
      order.push(i)
      slot = order.size - 1
      while slot > 0 && values[order[slot]] > values[order[slot - 1]]
        tmp = order[slot - 1]
        order[slot - 1] = order[slot]
        order[slot] = tmp
        slot -= 1
      i += 1
    limit = order.size
    limit = 8 if limit > 8
    i = 0
    while i < limit
      feature = order[i]
      << "CUDA_SELECTOR_IMPORTANCE model=" + name + " rank=" + (i + 1).to_s + " feature=" + CUDA_SELECTOR_FEATURES[feature].to_s + " value=" + values[feature].to_s
      i += 1

args = argv()
root = args.size > 0 ? args[0] : "/Users/erik/.tungsten/metaflip/cloud"
output = args.size > 1 ? args[1] : "/tmp/metaflip_cuda_selector.w"
paths = ffks_run_logs(root)
seen = {}
train_x = []
train_y = []
valid_x = []
valid_y = []
test_x = []
test_y = []
used_files = 0
paths.each -> (path)
  rows = ffks_epoch_lines(path, seen)
  if rows.size >= 10
    ffks_append_partition(rows, train_x, train_y, valid_x, valid_y, test_x, test_y)
    used_files += 1

if train_x.size == 0 || valid_x.size == 0 || test_x.size == 0
  << "CUDA_SELECTOR_FAIL no usable chronological corpus under " + root
  exit(1)

data_line = "CUDA_SELECTOR_DATA files=" + used_files.to_s
data_line += " train=" + train_x.size.to_s
data_line += " valid=" + valid_x.size.to_s
data_line += " test=" + test_x.size.to_s
data_line += " train_positive=" + ffks_positive_rate(train_y).to_s
data_line += " valid_positive=" + ffks_positive_rate(valid_y).to_s
data_line += " test_positive=" + ffks_positive_rate(test_y).to_s
<< data_line

train_weights = ffks_balanced_weights(train_y)
best = nil
best_depth = 0
best_leaf = 0
best_score = 0.to_f
best_f1 = 0.to_f
depth = 2
while depth <= 6
  [8, 16, 32].each -> (leaf)
    model = DecisionTreeClassifier.new(depth, leaf * 2, leaf, :gini)
    model.fit(train_x, train_y, train_weights)
    metrics = ffks_metrics(model, valid_x, valid_y)
    test_metrics = ffks_metrics(model, test_x, test_y)
    # F1 is the primary selector; balanced accuracy breaks practical ties.
    score = metrics[:f1] * 1000.to_f + metrics[:balanced_accuracy]
    candidate_line = "CUDA_SELECTOR_CANDIDATE depth=" + depth.to_s
    candidate_line += " leaf=" + leaf.to_s
    candidate_line += " nodes=" + model.node_count.to_s
    candidate_line += " f1=" + metrics[:f1].to_s
    candidate_line += " precision=" + metrics[:precision].to_s
    candidate_line += " recall=" + metrics[:recall].to_s
    candidate_line += " balanced_accuracy=" + metrics[:balanced_accuracy].to_s
    candidate_line += " test_f1=" + test_metrics[:f1].to_s
    candidate_line += " test_precision=" + test_metrics[:precision].to_s
    candidate_line += " test_recall=" + test_metrics[:recall].to_s
    << candidate_line
    if best == nil || score > best_score
      best = model
      best_depth = depth
      best_leaf = leaf
      best_score = score
    best_f1 = metrics[:f1] if metrics[:f1] > best_f1
  depth += 1

# Prefer the smallest deployment tree within one F1 point of the validation
# winner.  The model is a soft prior, not a gate; a tiny stable tree is more
# valuable than spending dozens of branches to chase noise in one campaign.
target_f1 = best_f1 - 0.01
compact_found = false
depth = 2
while depth <= 6 && !compact_found
  [8, 16, 32].each -> (leaf)
    if !compact_found
      model = DecisionTreeClassifier.new(depth, leaf * 2, leaf, :gini)
      model.fit(train_x, train_y, train_weights)
      metrics = ffks_metrics(model, valid_x, valid_y)
      if metrics[:f1] >= target_f1
        best = model
        best_depth = depth
        best_leaf = leaf
        compact_found = true
  depth += 1

chosen_line = "CUDA_SELECTOR_CHOSEN depth=" + best_depth.to_s
chosen_line += " leaf=" + best_leaf.to_s
chosen_line += " nodes=" + best.node_count.to_s
chosen_line += " tree_depth=" + best.depth.to_s
<< chosen_line
<< ffks_metric_line("train", ffks_metrics(best, train_x, train_y))
<< ffks_metric_line("valid", ffks_metrics(best, valid_x, valid_y))
<< ffks_metric_line("test", ffks_metrics(best, test_x, test_y))

artifact = DecisionTreeExport.export(best, CUDA_SELECTOR_FEATURES, :metaflip_cuda_launch_useful)
if artifact == nil || !write_file(output, artifact[:source])
  << "CUDA_SELECTOR_FAIL cannot export " + output
  exit(1)
export_line = "CUDA_SELECTOR_EXPORT path=" + output
export_line += " schema=" + artifact[:schema_checksum].to_s
export_line += " features=" + artifact[:feature_names].size.to_s
<< export_line
best.tree_lines.each -> (line)
  << "CUDA_SELECTOR_TREE " + line

# Compare the compact interpretable tree with small nonlinear ensembles. The
# test tail remains reporting-only: candidate complexity is chosen from the
# validation tranche, just like the tree above.
ffks_importance_report("tree", best.feature_importances)

forest_best = nil
forest_best_name = ""
forest_best_score = 0.to_f
[[24, 4, 8], [24, 6, 8], [40, 6, 16]].each -> (cfg)
  started = ccall_nobox("__w_clock_ms")
  forest = RandomForestClassifier.new(cfg[0], :sqrt, cfg[1], cfg[2], 19071)
  forest.fit(train_x, train_y, train_weights)
  elapsed_ms = ccall_nobox("__w_clock_ms") - started
  name = "forest" + cfg[0].to_s + "-d" + cfg[1].to_s + "-l" + cfg[2].to_s
  ffks_model_report(name, forest, train_x, train_y, valid_x, valid_y, test_x, test_y, elapsed_ms)
  metrics = ffks_metrics(forest, valid_x, valid_y)
  score = metrics[:f1] * 1000.to_f + metrics[:balanced_accuracy]
  if forest_best == nil || score > forest_best_score
    forest_best = forest
    forest_best_name = name
    forest_best_score = score

if forest_best != nil
  ffks_importance_report(forest_best_name, forest_best.feature_importances)

[[24, 2, 8], [40, 2, 16], [24, 3, 16]].each -> (cfg)
  started = ccall_nobox("__w_clock_ms")
  boost = GradientBoostingClassifier.new(cfg[0], 1.to_f / 10.to_f, cfg[1], cfg[2])
  boost.fit(train_x, train_y, train_weights)
  elapsed_ms = ccall_nobox("__w_clock_ms") - started
  name = "boost" + cfg[0].to_s + "-d" + cfg[1].to_s + "-l" + cfg[2].to_s
  ffks_model_report(name, boost, train_x, train_y, valid_x, valid_y, test_x, test_y, elapsed_ms)
