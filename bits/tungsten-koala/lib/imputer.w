# Imputer — fill missing (nil) cells with the fit/transform pattern
#
#     imp = Imputer.new(:mean)               # per-column mean
#     imp = Imputer.new(:median, [:x])       # only column :x
#     imp = Imputer.new(:constant, nil, 0)   # every nil -> 0
#
# Strategies: :mean, :median (Stats over the non-nil values), :mode
# (most frequent non-nil value, first-seen tie break — works for
# strings too), :constant (the fill_value argument). Fill values are
# learned at fit time and reused for every transform — imputing a test
# frame uses the TRAINING statistics. columns = nil fits every column;
# a column whose fill value comes out nil (e.g. all-nil under :mean)
# passes through unchanged, and :mean/:median skip non-numeric columns
# (see fit). transform before fit returns nil.
#
# INPUT is a DataFrame, or anything Estimator.frame accepts — a Matrix,
# an array of row arrays, or a flat single-feature array, whose columns
# are then named x0, x1, … positionally. The output is always a
# DataFrame. That coercion is what lets an Imputer ride inside a
# cross-validated or grid-searched Pipeline, where x reaches the steps as
# plain ROWS.
#
# Fitted state lives in parallel arrays (@fit_names / @fit_fills) —
# hash iteration order is not guaranteed across engines.
#
# --- Tunable (see lib/estimator_base.w) ---
#
#     imp.params                              # => { strategy: :mean, columns: nil, fill_value: nil }
#     imp.with_params({ strategy: :median })  # => a NEW, UNFITTED Imputer
#
# `params` reports the CONSTRUCTOR knobs — the three a search varies —
# and `with_params` returns a fresh unfitted clone with the overrides
# applied, leaving the receiver untouched. Answering both is the whole
# entry fee for Pipeline's tunable surface, so an Imputer named :impute
# in a chain contributes "impute.strategy" and a grid search can pick
# the fill rule the way it picks a model's alpha.
#
# WHAT FIT LEARNED IS `learned_params`, NOT `params` — the per-column
# [name, fill] pairs answer to their own name, because `params` means
# "what you set" everywhere else in koala.
#
# SAMPLE WEIGHTS: optional trailing argument on fit —
# `imp.fit(df, [2, 1, 1])`. :mean uses the weighted mean of non-nil
# cells; :median / :mode still use the unweighted rule but only on
# rows with positive weight (zero-weight rows are dropped before the
# statistic); :constant ignores weights. Unusable weight vector => nil.
+ Imputer
  is Tunable

  ro :strategy
  ro :columns
  ro :fill_value

  -> new(strategy = :mean, columns = nil, fill_value = nil)
    @strategy = strategy
    @columns = columns
    @fill_value = fill_value
    @fitted = false
    @fit_names = []
    @fit_fills = []

  -> fitted?
    @fitted

  # Learn per-column fill values from df (only @columns when given).
  # :mean and :median never fit a non-numeric column (Stats.numeric?):
  # averaging strings is meaningless, so a mixed frame imputes cleanly
  # with columns = nil. :mode and :constant fit any column.
  # Optional sample_weight: see header. Unusable weights => nil.
  -> fit(df, sample_weight = nil)
    frame = Estimator.frame(df)
    n = frame.row_count
    wts = nil
    ok = true
    if sample_weight != nil
      wts = Estimator.weight_values(sample_weight, n)
      ok = false if wts == nil
    out = nil
    if ok
      strategy = @strategy
      fill_value = @fill_value
      wanted = @columns
      wanted = frame.column_names if wanted == nil
      needs_numeric = false
      needs_numeric = true if strategy == :mean
      needs_numeric = true if strategy == :median
      names = []
      fills = []
      wanted.each -> (name)
        values = frame.column_values(name)
        usable = false
        usable = true if values != nil
        if usable && needs_numeric
          usable = Stats.numeric?(values)
        if usable
          names.push(name)
          fills.push(Imputer.fill_for(strategy, values, fill_value, wts))
      @fit_names = names
      @fit_fills = fills
      @fitted = true
      out = self
    out

  # New DataFrame with nils replaced by fitted fills; nil before fit.
  -> transform(df)
    out = nil
    if @fitted
      frame = Estimator.frame(df)
      fit_names = @fit_names
      fit_fills = @fit_fills
      pairs = []
      frame.column_names.each -> (name)
        values = frame.column_values(name)
        i = -1
        j = 0
        fit_names.each -> (n)
          i = j if n == name
          j += 1
        fill = nil
        fill = fit_fills[i] if i != -1
        if fill == nil
          pairs.push([name, values])
        else
          filled = []
          values.each -> (v)
            if v == nil
              filled.push(fill)
            else
              filled.push(v)
          pairs.push([name, filled])
      out = DataFrame.new(pairs)
    out

  -> fit_transform(df, sample_weight = nil)
    self.fit(df, sample_weight)
    self.transform(df)

  # --- Tunable contract (see lib/estimator_base.w) ---

  # The hyperparameters a search varies — the constructor's own knobs,
  # never the fill values fit learned (those are learned_params).
  -> params
    { strategy: @strategy, columns: @columns, fill_value: @fill_value }

  # A NEW, UNFITTED Imputer with `overrides` applied; self is left
  # untouched. Unmentioned keys carry over, so with_params(params)
  # round-trips, and an explicit nil value really does clear a knob (key
  # presence, not value, decides).
  -> with_params(overrides)
    Imputer.new(Estimator.opt(overrides, :strategy, @strategy), Estimator.opt(overrides, :columns, @columns), Estimator.opt(overrides, :fill_value, @fill_value))

  # What fit LEARNED, as ordered [name, fill] pairs. Distinct from
  # `params` above, which reports the knobs you set.
  -> learned_params
    fit_names = @fit_names
    fit_fills = @fit_fills
    out = []
    i = 0
    fit_names.each -> (n)
      out.push([n, fit_fills[i]])
      i += 1
    out

  # The fill value a strategy learns from one column's values.
  # Optional weights: :mean uses weighted_mean_clean; :median/:mode
  # drop zero-weight rows then run the plain statistic; :constant
  # ignores weights.
  #
  # NOTE: sequential block-ifs assigning `out` — `return Stats.mean(...)`
  # under an if segfaults the interpreter when the returned value is a
  # cross-class static call (same as Pivot.aggregate).
  -> .fill_for(strategy, values, fill_value, weights = nil)
    out = nil
    if strategy == :mean
      out = Estimator.weighted_mean_clean(values, weights)
    if strategy == :median
      out = Stats.median(Imputer.positive_weight_values(values, weights))
    if strategy == :mode
      out = Stats.mode(Imputer.positive_weight_values(values, weights))
    if strategy == :constant
      out = fill_value
    out

  # values restricted to rows with positive weight (or the full column
  # when weights is nil). Nils stay in so Stats.clean still applies.
  -> .positive_weight_values(values, weights)
    out = values
    if weights != nil
      kept = []
      i = 0
      values.each -> (v)
        kept.push(v) if weights[i] > 0.to_f
        i += 1
      out = kept
    out

  # --- Persistence (see lib/persist.w) ---

  -> persist_name
    "Imputer"

  # The learned per-column fill values, so a loaded Imputer fills a test
  # frame from the TRAINING statistics exactly as the saved one did.
  -> to_state
    { strategy: @strategy, columns: @columns, fill_value: @fill_value, fit_names: @fit_names, fit_fills: @fit_fills }

  -> .load_state(st)
    out = nil
    ok = st != nil
    ok = st[:strategy] != nil && st[:fit_names] != nil && st[:fit_fills] != nil if ok
    if ok
      model = Imputer.new(st[:strategy], st[:columns], st[:fill_value])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @fit_names = st[:fit_names]
    @fit_fills = st[:fit_fills]
    @fitted = true
    self
