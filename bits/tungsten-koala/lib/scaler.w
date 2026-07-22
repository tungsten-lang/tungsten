# Scaler — feature scaling with the fit/transform pattern
#
#     sc = Scaler.new(:standard)             # or :min_max
#     out = sc.fit_transform(df)             # scale every numeric column
#     sc = Scaler.new(:min_max, [:a, :b])    # scale only these columns
#
# :standard maps a fitted column to (v - mean) / std — Stats.std, the
# sample (n - 1) deviation — so an exactly-spaced column like [2, 4, 6]
# scales to [-1, 0, 1]. :min_max maps to (v - min) / (max - min) into
# [0, 1]. A zero-spread column scales to 0.0 everywhere; nil cells stay
# nil; columns that were not fitted pass through unchanged. transform
# before fit returns nil (the shape-error convention).
#
# INPUT is a DataFrame, or anything Estimator.frame accepts — a Matrix,
# an array of row arrays, or a flat single-feature array, whose columns
# are then named x0, x1, … positionally. The output is always a
# DataFrame. That coercion is what lets a Scaler ride inside a
# cross-validated or grid-searched Pipeline, where x reaches the steps as
# plain ROWS (CrossValidation coerces before the model sees it).
#
# Fitted state lives in parallel arrays (@fit_names / @fit_a / @fit_b,
# where a/b is mean/std or min/max) — hash iteration order is not
# guaranteed across engines. Every float derives from the data via .to_f
# — a bare decimal literal is a Decimal and does not coerce with Float.
#
# --- Tunable (see lib/estimator_base.w) ---
#
#     sc.params                             # => { kind: :standard, columns: nil }
#     sc.with_params({ kind: :min_max })    # => a NEW, UNFITTED Scaler
#
# `params` reports the CONSTRUCTOR knobs — the two a search varies — and
# `with_params` returns a fresh unfitted clone with the overrides applied,
# leaving the receiver untouched. Answering both is the whole entry fee
# for Pipeline's tunable surface, so a Scaler named :scale in a chain
# contributes "scale.kind" / "scale.columns" and GridSearch can select
# the scaling ITSELF alongside the model's hyperparameters — with no code
# in lib/pipeline.w or lib/grid_search.w aware of scaling.
#
# WHAT FIT LEARNED IS `learned_params`, NOT `params` — the per-column
# [name, a, b] triples answer to their own name, because `params` means
# "what you set" everywhere else in koala and fitted state must never
# leak into a search space that cannot rebuild it.
#
# SAMPLE WEIGHTS: optional trailing argument on fit —
# `sc.fit(df, [2, 1, 1])` — so a Pipeline can centre on the weighted
# mean and divide by the weighted sample std (or min/max over positive-
# weight rows). An unusable vector returns nil and leaves fitted?
# false. Integer weights match row-duplication for :standard (same
# definition as Estimator.weighted_mean / weighted_sample_std).
+ Scaler
  is Tunable

  ro :kind
  ro :columns

  -> new(kind = :standard, columns = nil)
    @kind = kind
    @columns = columns
    @fitted = false
    @fit_names = []
    @fit_a = []
    @fit_b = []

  -> fitted?
    @fitted

  # Learn per-column parameters from df (only @columns when given).
  # Non-numeric columns (strings, symbols — Stats.numeric?) are never
  # fitted, even when requested: scaling them is meaningless, so a
  # mixed frame scales cleanly with columns = nil.
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
      kind = @kind
      wanted = @columns
      wanted = frame.column_names if wanted == nil
      names = []
      a = []
      b = []
      wanted.each -> (name)
        values = frame.column_values(name)
        usable = false
        usable = Stats.numeric?(values) if values != nil
        if usable
          names.push(name)
          if kind == :min_max
            ext = Estimator.weighted_extrema(values, wts)
            if ext == nil
              a.push(0.to_f)
              b.push(0.to_f)
            else
              a.push(ext[0])
              b.push(ext[1])
          else
            a.push(Estimator.weighted_mean_clean(values, wts))
            b.push(Estimator.weighted_sample_std(values, wts))
      @fit_names = names
      @fit_a = a
      @fit_b = b
      @fitted = true
      out = self
    out

  # New DataFrame with fitted columns scaled; nil before fit.
  -> transform(df)
    out = nil
    if @fitted
      frame = Estimator.frame(df)
      kind = @kind
      fit_names = @fit_names
      fit_a = @fit_a
      fit_b = @fit_b
      pairs = []
      frame.column_names.each -> (name)
        values = frame.column_values(name)
        i = -1
        j = 0
        fit_names.each -> (n)
          i = j if n == name
          j += 1
        if i == -1
          pairs.push([name, values])
        else
          pa = fit_a[i]
          pb = fit_b[i]
          scaled = []
          values.each -> (v)
            if v == nil
              scaled.push(nil)
            else
              scaled.push(Scaler.scale_value(kind, v, pa, pb))
          pairs.push([name, scaled])
      out = DataFrame.new(pairs)
    out

  -> fit_transform(df, sample_weight = nil)
    self.fit(df, sample_weight)
    self.transform(df)

  # --- Tunable contract (see lib/estimator_base.w) ---

  # The hyperparameters a search varies — the constructor's own knobs,
  # never the mean/std fit learned (those are learned_params).
  -> params
    { kind: @kind, columns: @columns }

  # A NEW, UNFITTED Scaler with `overrides` applied; self is left
  # untouched. Unmentioned keys carry over, so with_params(params)
  # round-trips, and an explicit `{ columns: nil }` really does widen a
  # column-restricted scaler back to every numeric column (key presence,
  # not value, decides).
  -> with_params(overrides)
    Scaler.new(Estimator.opt(overrides, :kind, @kind), Estimator.opt(overrides, :columns, @columns))

  # What fit LEARNED, as ordered [name, a, b] triples
  # (a/b = mean/std for :standard, min/max for :min_max). Distinct from
  # `params` above, which reports the knobs you set.
  -> learned_params
    fit_names = @fit_names
    fit_a = @fit_a
    fit_b = @fit_b
    out = []
    i = 0
    fit_names.each -> (n)
      out.push([n, fit_a[i], fit_b[i]])
      i += 1
    out

  # Scale one value under fitted params a/b (mean/std or min/max).
  -> .scale_value(kind, v, a, b)
    out = nil
    if kind == :min_max
      range = b.to_f - a.to_f
      if range == 0.to_f
        out = 0.to_f
      else
        out = (v.to_f - a.to_f) / range
    else
      s = b.to_f
      if s == 0.to_f
        out = 0.to_f
      else
        out = (v.to_f - a.to_f) / s
    out

  # --- Persistence (see lib/persist.w) ---

  -> persist_name
    "Scaler"

  # The parallel fitted arrays go across as they are — a loaded Scaler
  # replays the TRAINING mean/std (or min/max), which is the whole point
  # of saving a transformer rather than re-fitting one.
  -> to_state
    { kind: @kind, columns: @columns, fit_names: @fit_names, fit_a: @fit_a, fit_b: @fit_b }

  -> .load_state(st)
    out = nil
    ok = st != nil
    ok = st[:kind] != nil && st[:fit_names] != nil if ok
    ok = st[:fit_a] != nil && st[:fit_b] != nil if ok
    if ok
      model = Scaler.new(st[:kind], st[:columns])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @fit_names = st[:fit_names]
    @fit_a = st[:fit_a]
    @fit_b = st[:fit_b]
    @fitted = true
    self
