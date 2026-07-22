# Rolling — trailing-window calculations over a Series
#
#     s = Series.new([1, 2, 3, 4, 5], "v")
#     s.rolling(3).sum         # => Series [1, 3, 6, 9, 12]
#     s.rolling(3, 3).sum      # => Series [nil, nil, 6, 9, 12]
#
# Window i covers the last `window` values ending at index i. nils are
# dropped from each window; a cell is nil until the window holds at least
# `min_periods` non-nil values (default 1; pandas defaults to `window` —
# pass it explicitly for that behavior).
+ Rolling
  ro :series
  ro :window
  ro :min_periods

  -> new(series, window, min_periods = 1)
    @series = series
    @window = window
    @min_periods = min_periods

  # Apply f — a lambda over an array of the window's non-nil values —
  # at every position of the series.
  -> apply(f)
    values = @series.to_a
    width = @window
    needed = @min_periods
    out = []
    values.size.times -> (i)
      start = i - width + 1
      start = 0 if start < 0
      win = []
      span = i - start + 1
      span.times -> (k)
        v = values[start + k]
        win.push(v) if v != nil
      if win.size >= needed
        out.push(f.call(win))
      else
        out.push(nil)
    Series.new(out, @series.name)

  -> sum
    f = -> (w) Stats.sum(w)
    self.apply(f)

  -> mean
    f = -> (w) Stats.mean(w)
    self.apply(f)

  -> median
    f = -> (w) Stats.median(w)
    self.apply(f)

  -> min
    f = -> (w) Stats.min(w)
    self.apply(f)

  -> max
    f = -> (w) Stats.max(w)
    self.apply(f)

  -> std
    f = -> (w) Stats.std(w)
    self.apply(f)

  -> var
    f = -> (w) Stats.var(w)
    self.apply(f)

  # Count of non-nil values in each window.
  -> count
    f = -> (w) w.size
    self.apply(f)
