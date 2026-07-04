# Resample — time-series resampling operations

in Tungsten:Koala

+ Resample
  ro :source
  ro :time_col
  ro :freq

  # Create a resampler.
  #
  #     df.resample(:timestamp, freq: :daily)
  #     df.resample(:date, freq: "1h")
  -> new(@source, @time_col, freq:)
    @freq = freq

  # Aggregate by time bucket.
  -> agg(**aggregations)
    buckets = self.build_buckets
    result_columns = { @time_col => buckets.keys }

    aggregations.each -> (name, agg_fn)
      result_columns[name] = buckets.map -> (_, indices)
        values = indices.map(-> (i) @source.store[agg_fn.column].to_a[i])
        agg_fn.apply(values)

    DataFrame.new(**result_columns)

  -> mean(col) self.simple_agg(col, -> (vs) vs.sum.to_f / vs.size)
  -> sum(col)  self.simple_agg(col, -> (vs) vs.sum)
  -> count     self.build_buckets.map(-> (k, v) [k, v.size]).to_h
  -> first(col) self.simple_agg(col, -> (vs) vs.first)
  -> last(col) self.simple_agg(col, -> (vs) vs.last)

  # Forward-fill missing time periods.
  -> ffill
    # TODO: fill gaps in time series
    self

  # Backward-fill missing time periods.
  -> bfill
    # TODO: fill gaps in time series
    self

  [private]

  -> build_buckets
    times = @source.store[@time_col].to_a
    buckets = {}
    times.each_with_index -> (t, i)
      bucket = self.truncate_time(t, @freq)
      buckets[bucket] ||= []
      buckets[bucket].push(i)
    buckets

  -> truncate_time(time, freq)
    case freq
    => :yearly, "1y"   -> Time.new(time.year, 1, 1)
    => :monthly, "1M"  -> Time.new(time.year, time.month, 1)
    => :weekly, "1w"   -> time - time.wday * 86_400
    => :daily, "1d"    -> Time.new(time.year, time.month, time.day)
    => :hourly, "1h"   -> Time.new(time.year, time.month, time.day, time.hour)
    => :minutely, "1m" -> Time.new(time.year, time.month, time.day, time.hour, time.min)

  -> simple_agg(col, fn)
    buckets = self.build_buckets
    result = {}
    result[@time_col] = buckets.keys
    result[col] = buckets.map -> (_, indices)
      values = indices.map(-> (i) @source.store[col].to_a[i])
      fn.call(values)
    DataFrame.new(**result)
