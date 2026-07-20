# Series — a single named column of values (plain-array backed)
+ Series
  ro :name
  ro :values

  -> new(values, name = "series")
    @values = values
    @name = name

  -> size
    @values.size

  -> empty?
    @values.size == 0

  -> to_a
    @values

  -> [](i)
    @values[i]

  -> first
    @values[0]

  -> last
    @values[@values.size - 1]

  -> head(n = 5)
    limit = n
    limit = @values.size if @values.size < n
    out = []
    limit.times -> (i)
      out.push(@values[i])
    Series.new(out, @name)

  # --- Aggregations ---

  -> sum
    Stats.sum(@values)

  -> mean
    Stats.mean(@values)

  -> median
    Stats.median(@values)

  -> min
    Stats.min(@values)

  -> max
    Stats.max(@values)

  -> std
    Stats.std(@values)

  -> var
    Stats.var(@values)

  -> count
    Stats.clean(@values).size

  # --- Transforms ---

  -> map(&)
    out = []
    @values.each -> (v)
      out.push(&(v))
    Series.new(out, @name)

  -> select(&)
    out = []
    @values.each -> (v)
      out.push(v) if &(v)
    Series.new(out, @name)

  -> unique
    out = []
    @values.each -> (v)
      out.push(v) if !out.include?(v)
    Series.new(out, @name)

  -> fillna(value)
    out = []
    @values.each -> (v)
      if v == nil
        out.push(value)
      else
        out.push(v)
    Series.new(out, @name)

  -> dropna
    Series.new(Stats.clean(@values), @name)

  # --- Windows ---

  # Trailing-window calculations: s.rolling(3).mean (see rolling.w).
  -> rolling(window, min_periods = 1)
    Rolling.new(self, window, min_periods)

  # --- Conversion ---

  # n×1 Matrix — the estimator input convention (see matrix.w): any
  # non-array x answers to_matrix, so a Series is one single-feature
  # column to LinearRegression.feature_rows.
  -> to_matrix
    vals = @values
    rows = []
    vals.each -> (v)
      rows.push([v])
    Matrix.new(rows)

  -> to_s
    "Series([@name], n=[@values.size]): " + @values.to_s
