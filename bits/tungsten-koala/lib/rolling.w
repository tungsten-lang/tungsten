# Rolling — rolling window calculations for Series

in Tungsten:Koala

+ Rolling
  ro :series
  ro :window
  ro :min_periods

  -> new(@series, window:, min_periods: 1)
    @window = window
    @min_periods = min_periods

  # Rolling mean.
  -> mean self.apply(-> (w) w.sum.to_f / w.size)

  # Rolling sum.
  -> sum self.apply(-> (w) w.sum)

  # Rolling standard deviation.
  -> std self.apply(-> (w) Stats.std(w))

  # Rolling variance.
  -> var self.apply(-> (w) Stats.var(w))

  # Rolling min.
  -> min self.apply(-> (w) w.min)

  # Rolling max.
  -> max self.apply(-> (w) w.max)

  # Rolling median.
  -> median self.apply(-> (w) Stats.median(w))

  # Rolling count of non-nil values.
  -> count self.apply(-> (w) w.reject(&:nil?).size)

  # Apply a custom function over the rolling window.
  -> apply(fn)
    values = @series.to_a
    result = values.size.times.map -> (i)
      start = [0, i - @window + 1].max
      window = values[start..i].reject(&:nil?)
      if window.size >= @min_periods
        fn.call(window)
      else
        nil
    Series.new(result, name: @series.name)
