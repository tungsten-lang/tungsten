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
# guaranteed across engines. No float literals appear here: floats
# cross engine boundaries unreliably, so every float derives from the
# data via .to_f (the stats.w convention).
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
# NOTE: locals are hoisted from ivars before any `-> (x)` block — the
# interpreter cannot resolve @ivars from a block body.
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
  -> fit(df)
    frame = Estimator.frame(df)
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
        clean = Stats.clean(values)
        names.push(name)
        if kind == :min_max
          a.push(Stats.min(clean))
          b.push(Stats.max(clean))
        else
          a.push(Stats.mean(clean))
          b.push(Stats.std(clean))
    @fit_names = names
    @fit_a = a
    @fit_b = b
    @fitted = true
    self

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

  -> fit_transform(df)
    self.fit(df)
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
