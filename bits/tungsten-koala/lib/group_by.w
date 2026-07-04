# GroupBy — split-apply-combine operations on DataFrames

in Tungsten:Koala

+ GroupBy
  ro :source
  ro :keys
  ro :groups  # lazy — computed on first access

  -> new(@source, @keys)
    @groups = nil

  # Aggregate grouped data.
  #
  #     df.group_by(:department).agg(
  #       avg_salary: mean(:salary),
  #       headcount:  count(:name),
  #       max_age:    max(:age)
  #     )
  -> agg(**aggregations)
    result_columns = {}
    @keys.each -> (key)
      result_columns[key] = self.computed_groups.keys.map(-> (g) g[key])

    aggregations.each -> (result_name, agg_fn)
      result_columns[result_name] = self.computed_groups.map -> (group_key, indices)
        values = indices.map(-> (i) @source.store[agg_fn.column].to_a[i])
        agg_fn.apply(values)

    DataFrame.new(**result_columns)

  # Count rows per group.
  -> count
    result = {}
    @keys.each -> (key)
      result[key] = self.computed_groups.keys.map(-> (g) g[key])
    result[:count] = self.computed_groups.values.map(&:size)
    DataFrame.new(**result)

  # Sum a column per group.
  -> sum(col)
    self.apply_simple(col, -> (values) values.sum)

  # Mean a column per group.
  -> mean(col)
    self.apply_simple(col, -> (values) values.sum.to_f / values.size)

  # Max / min per group.
  -> max(col) self.apply_simple(col, -> (values) values.max)
  -> min(col) self.apply_simple(col, -> (values) values.min)

  # Apply a custom function to each group.
  #
  #     df.group_by(:dept).apply -> (group_df)
  #       group_df.assign(rank: group_df[:score].rank)
  -> apply(&block)
    frames = self.computed_groups.map -> (_, indices)
      group_df = @source.take(indices)
      block.call(group_df)
    # Concatenate all result frames
    frames.reduce(-> (a, b) a.concat(b))

  # Iterate over groups.
  -> each(&block)
    self.computed_groups.each -> (key, indices)
      block.call(key, @source.take(indices))

  -> size self.computed_groups.size

  [private]

  -> computed_groups
    @groups ||= begin
      groups = {}
      @source.row_count.times -> (i)
        key = @keys.map(-> (k) [k, @source.store[k].to_a[i]]).to_h
        groups[key] ||= []
        groups[key].push(i)
      groups

  -> apply_simple(col, fn)
    result = {}
    @keys.each -> (key)
      result[key] = self.computed_groups.keys.map(-> (g) g[key])
    result[col] = self.computed_groups.map -> (_, indices)
      values = indices.map(-> (i) @source.store[col].to_a[i])
      fn.call(values)
    DataFrame.new(**result)


# Aggregation function descriptors — used in .agg() calls
+ AggFn
  ro :column
  ro :func

  -> new(@column, @func)
  -> apply(values) @func.call(values)

# Convenience constructors for agg expressions:
#   df.group_by(:dept).agg(avg_salary: mean(:salary))
-> mean(col)  AggFn.new(col, -> (vs) vs.sum.to_f / vs.size)
-> sum(col)   AggFn.new(col, -> (vs) vs.sum)
-> count(col) AggFn.new(col, -> (vs) vs.reject(&:nil?).size)
-> max(col)   AggFn.new(col, -> (vs) vs.max)
-> min(col)   AggFn.new(col, -> (vs) vs.min)
-> std(col)   AggFn.new(col, -> (vs) Stats.std(vs))
-> var(col)   AggFn.new(col, -> (vs) Stats.var(vs))
-> median(col) AggFn.new(col, -> (vs) Stats.median(vs))
-> first(col) AggFn.new(col, -> (vs) vs.first)
-> last(col)  AggFn.new(col, -> (vs) vs.last)
