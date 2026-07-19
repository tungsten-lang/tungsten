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
# Fitted state lives in parallel arrays (@fit_names / @fit_cats) — hash
# iteration order is not guaranteed across engines.
#
# NOTE: locals are hoisted from ivars before any `-> (x)` block — the
# interpreter cannot resolve @ivars from a block body.
+ Encoder
  ro :kind

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
    wanted = @columns
    wanted = df.column_names if wanted == nil
    names = []
    cats = []
    wanted.each -> (name)
      values = df.column_values(name)
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
      kind = @kind
      fit_names = @fit_names
      fit_cats = @fit_cats
      pairs = []
      df.column_names.each -> (name)
        values = df.column_values(name)
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

  # Index of v in the category list; nil when v is nil or unseen.
  -> .code_for(cats, v)
    out = nil
    if v != nil
      i = 0
      cats.each -> (c)
        out = i if c == v
        i += 1
    out
