# PermutationImportance — model-agnostic feature inspection
#
# Measure how much a fitted model's score falls when one input column is
# independently shuffled:
#
#     result = PermutationImportance.compute(model, x, y, 10, 42)
#     result.feature_names       # original DataFrame names, or x0 / x1 / ...
#     result.importances_mean    # one mean score decrease per feature
#     result.importances_std     # population standard deviation per feature
#     result.to_df               # a compact, named summary
#
# This is deliberately an ABLATION measure rather than an estimator-specific
# coefficient or tree statistic. It therefore works unchanged for every model
# answering koala's Estimable contract, including Pipelines and unsupervised
# estimators. Inputs are normalized through Estimator.frame, not
# Estimator.feature_rows: preserving the original DataFrame is what lets a
# mixed numeric/categorical ColumnTransformer Pipeline be inspected without
# silently dropping its categorical columns.
#
# All koala scores are higher-is-better (regression R2, classification
# accuracy, KMeans negative inertia), so an importance is always:
#
#     baseline_score - score_with_one_column_permuted
#
# Negative values are retained. They are useful evidence that shuffling a
# feature happened to help on this sample, not an error to clamp away.
#
# Randomness uses the same MINSTD stream as Splitter / CrossValidation.
# A single stream advances across features and repeats, so the same integer
# seed is byte-deterministic on both engines while every ablation receives a
# fresh permutation.
+ PermutationImportance
  ro :baseline_score
  ro :feature_names
  ro :importances
  ro :importances_mean
  ro :importances_std
  ro :n_repeats
  ro :seed

  -> new(baseline_score, feature_names, importances, means, stds, n_repeats, seed)
    @baseline_score = baseline_score
    @feature_names = feature_names
    @importances = importances
    @importances_mean = means
    @importances_std = stds
    @n_repeats = n_repeats
    @seed = seed

  # A DataFrame whose rows are features in their original input order.
  -> to_df
    DataFrame.new([
      [:feature, @feature_names],
      [:importance_mean, @importances_mean],
      [:importance_std, @importances_std]
    ])

  # Compute repeated permutation importances for an already-fitted model.
  # `y` is required for supervised estimators and ignored for unsupervised
  # ones. sample_weight changes scoring only; the estimator is never refit.
  # Invalid shapes, contracts, or parameters return nil, matching the rest
  # of koala's model-selection surface.
  -> .compute(model, x, y = nil, n_repeats = 5, seed = 42, sample_weight = nil)
    out = nil
    ok = model != nil
    ok = model.respond_to?("fitted?") if ok
    ok = model.fitted? if ok
    ok = model.respond_to?("supervised?") if ok
    ok = model.respond_to?("score") if ok
    ok = type(n_repeats) == "Integer" && n_repeats > 0 if ok
    ok = type(seed) == "Integer" if ok

    frame = nil
    frame = Estimator.frame(x) if ok
    ok = frame != nil if ok
    ok = frame.respond_to?("valid?") && frame.valid? if ok
    ok = frame.row_count > 1 && frame.col_count > 0 if ok
    names = []
    names = frame.column_names if ok
    ok = PermutationImportance.unique_names?(names) if ok

    yvals = nil
    if ok && model.supervised?
      ok = y != nil
      yvals = Estimator.target_values(y) if ok
      ok = yvals != nil && yvals.size == frame.row_count if ok

    weights = nil
    if ok && sample_weight != nil
      weights = Estimator.weight_values(sample_weight, frame.row_count)
      ok = weights != nil

    baseline = nil
    baseline = Estimator.score_model(model, frame, yvals, weights) if ok
    ok = baseline != nil if ok

    if ok
      all = []
      means = []
      stds = []
      state = seed % 2147483647
      state = 1 if state <= 0

      names.size.times -> (feature_index)
        values = []
        n_repeats.times -> (repeat_index)
          state = (state * 48271) % 2147483647
          order = Splitter.indices(frame.row_count, state)
          permuted = PermutationImportance.permuted_frame(frame, feature_index, order)
          score = Estimator.score_model(model, permuted, yvals, weights)
          ok = false if score == nil
          values.push(baseline.to_f - score.to_f) if score != nil

        if ok
          mean = Stats.mean(values)
          means.push(mean)
          stds.push(PermutationImportance.population_std(values, mean))
          all.push(values)

      if ok
        copied_names = []
        names.each -> (name)
          copied_names.push(name)
        out = PermutationImportance.new(
          baseline, copied_names, all, means, stds, n_repeats, seed
        )
    out

  # Copy a frame and reorder exactly one column. Column names, order, cell
  # types, and all untouched values survive exactly.
  -> .permuted_frame(frame, feature_index, order)
    pairs = []
    names = frame.column_names
    i = 0
    names.each -> (name)
      source = frame.column_values(name)
      values = []
      if i == feature_index
        order.each -> (row_index)
          values.push(source[row_index])
      else
        source.each -> (value)
          values.push(value)
      pairs.push([name, values])
      i += 1
    DataFrame.new(pairs)

  -> .population_std(values, mean)
    total = 0.to_f
    values.each -> (value)
      delta = value.to_f - mean.to_f
      total += delta * delta
    Math.sqrt(total / values.size.to_f)

  -> .unique_names?(names)
    unique = true
    seen = []
    names.each -> (name)
      unique = false if seen.include?(name)
      seen.push(name)
    unique
