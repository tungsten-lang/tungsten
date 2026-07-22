# Encoder — categorical encoding with the fit/transform pattern
#
#     enc = Encoder.new(:label, [:color])    # category -> index
#     enc = Encoder.new(:one_hot, [:color])  # category -> 0/1 columns
#
# Categories are collected at fit time in FIRST-SEEN order (Array#sort
# is not portable across engines — the Pivot convention) and nil is
# never a category.
#
# :label replaces each fitted column with the category's index; a nil
# or never-seen value encodes to nil. :one_hot replaces each fitted
# column IN PLACE with one 0/1 column per category, named
# "<col>_<cat>" (string names, like Pivot's value-named columns), in
# category order; a nil cell is 0 in every category column. Surrounding
# column order is preserved. columns = nil encodes every column.
# transform before fit returns nil.
#
# INPUT is a DataFrame, or anything Estimator.frame accepts — a Matrix,
# an array of row arrays, or a flat single-feature array, whose columns
# are then named x0, x1, … positionally. The output is always a
# DataFrame. That coercion is what lets an Encoder ride inside a
# cross-validated or grid-searched Pipeline, where x reaches the steps as
# plain ROWS.
#
# Fitted state lives in parallel arrays (@fit_names / @fit_cats) — hash
# iteration order is not guaranteed across engines; `categories(name)`
# reads it back per column.
#
# --- Tunable (see lib/estimator_base.w) ---
#
#     enc.params                            # => { kind: :label, columns: nil }
#     enc.with_params({ kind: :one_hot })   # => a NEW, UNFITTED Encoder
#
# `params` reports the CONSTRUCTOR knobs — the two a search varies — and
# `with_params` returns a fresh unfitted clone with the overrides
# applied, leaving the receiver untouched. Answering both is the whole
# entry fee for Pipeline's tunable surface, so an Encoder named :encode
# in a chain contributes "encode.kind" and a grid search can choose
# label-vs-one-hot the way it chooses a model's alpha.
+ Encoder
  is Tunable

  ro :kind
  ro :columns

  -> new(kind = :label, columns = nil)
    @kind = kind
    @columns = columns
    @fitted = false
    @fit_names = []
    @fit_cats = []

  -> fitted?
    @fitted

  # Collect first-seen category lists from df (only @columns when given).
  -> fit(df)
    frame = Estimator.frame(df)
    wanted = @columns
    wanted = frame.column_names if wanted == nil
    names = []
    cats = []
    wanted.each -> (name)
      values = frame.column_values(name)
      if values != nil
        seen = []
        values.each -> (v)
          seen.push(v) if v != nil && !seen.include?(v)
        names.push(name)
        cats.push(seen)
    @fit_names = names
    @fit_cats = cats
    @fitted = true
    self

  # The fitted category list for a column; nil when it was not fitted.
  -> categories(name)
    fit_names = @fit_names
    i = -1
    j = 0
    fit_names.each -> (n)
      i = j if n == name
      j += 1
    return nil if i == -1
    @fit_cats[i]

  # New DataFrame with fitted columns encoded; nil before fit.
  -> transform(df)
    out = nil
    if @fitted
      frame = Estimator.frame(df)
      kind = @kind
      fit_names = @fit_names
      fit_cats = @fit_cats
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
          cats = fit_cats[i]
          if kind == :one_hot
            cats.each -> (cat)
              flags = []
              values.each -> (v)
                if v == cat
                  flags.push(1)
                else
                  flags.push(0)
              pairs.push([name.to_s + "_" + cat.to_s, flags])
          else
            codes = []
            values.each -> (v)
              codes.push(Encoder.code_for(cats, v))
            pairs.push([name, codes])
      out = DataFrame.new(pairs)
    out

  -> fit_transform(df)
    self.fit(df)
    self.transform(df)

  # --- Tunable contract (see lib/estimator_base.w) ---

  # The hyperparameters a search varies — the constructor's own knobs,
  # never the categories fit collected (those are categories(name)).
  -> params
    { kind: @kind, columns: @columns }

  # A NEW, UNFITTED Encoder with `overrides` applied; self is left
  # untouched. Unmentioned keys carry over, so with_params(params)
  # round-trips, and an explicit `{ columns: nil }` really does widen a
  # column-restricted encoder back to every column (key presence, not
  # value, decides).
  -> with_params(overrides)
    Encoder.new(Estimator.opt(overrides, :kind, @kind), Estimator.opt(overrides, :columns, @columns))

  # Index of v in the category list; nil when v is nil or unseen.
  -> .code_for(cats, v)
    out = nil
    if v != nil
      i = 0
      cats.each -> (c)
        out = i if c == v
        i += 1
    out

  # --- Persistence (see lib/persist.w) ---

  -> persist_name
    "Encoder"

  # The first-seen category lists — the ORDER is the encoding, so it has
  # to survive: a loaded Encoder must map the same category to the same
  # index (and the same one-hot column) as the saved one.
  -> to_state
    { kind: @kind, columns: @columns, fit_names: @fit_names, fit_cats: @fit_cats }

  -> .load_state(st)
    out = nil
    ok = st != nil
    ok = st[:kind] != nil && st[:fit_names] != nil && st[:fit_cats] != nil if ok
    if ok
      model = Encoder.new(st[:kind], st[:columns])
      out = model.restore_state(st)
    out

  -> restore_state(st)
    @fit_names = st[:fit_names]
    @fit_cats = st[:fit_cats]
    @fitted = true
    self
