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
# Fitted state lives in parallel arrays (@fit_names / @fit_fills) —
# hash iteration order is not guaranteed across engines.
#
# NOTE: locals are hoisted from ivars before any `-> (x)` block — the
# interpreter cannot resolve @ivars from a block body.
+ Imputer
  ro :strategy

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
  -> fit(df)
    strategy = @strategy
    fill_value = @fill_value
    wanted = @columns
    wanted = df.column_names if wanted == nil
    needs_numeric = false
    needs_numeric = true if strategy == :mean
    needs_numeric = true if strategy == :median
    names = []
    fills = []
    wanted.each -> (name)
      values = df.column_values(name)
      usable = false
      usable = true if values != nil
      if usable && needs_numeric
        usable = Stats.numeric?(values)
      if usable
        names.push(name)
        fills.push(Imputer.fill_for(strategy, values, fill_value))
    @fit_names = names
    @fit_fills = fills
    @fitted = true
    self

  # New DataFrame with nils replaced by fitted fills; nil before fit.
  -> transform(df)
    out = nil
    if @fitted
      fit_names = @fit_names
      fit_fills = @fit_fills
      pairs = []
      df.column_names.each -> (name)
        values = df.column_values(name)
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

  -> fit_transform(df)
    self.fit(df)
    self.transform(df)

  # Fitted fill values as ordered [name, fill] pairs.
  -> params
    fit_names = @fit_names
    fit_fills = @fit_fills
    out = []
    i = 0
    fit_names.each -> (n)
      out.push([n, fit_fills[i]])
      i += 1
    out

  # The fill value a strategy learns from one column's values.
  #
  # NOTE: sequential block-ifs assigning `out` — `return Stats.mean(...)`
  # under an if segfaults the interpreter when the returned value is a
  # cross-class static call (same as Pivot.aggregate).
  -> .fill_for(strategy, values, fill_value)
    out = nil
    if strategy == :mean
      out = Stats.mean(values)
    if strategy == :median
      out = Stats.median(values)
    if strategy == :mode
      out = Stats.mode(values)
    if strategy == :constant
      out = fill_value
    out
