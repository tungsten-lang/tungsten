# GroupBy — split-apply-combine on a single DataFrame column
#
#     df.group_by(:dept).mean(:salary)   # => DataFrame [dept, salary]
#     df.group_by(:dept).count           # => DataFrame [dept, count]

+ GroupBy
  ro :df
  ro :col
  ro :group_keys   # distinct key values, first-seen order
  ro :buckets      # parallel array of row-index arrays

  -> new(df, col)
    @df = df
    @col = col
    gkeys = []
    buckets = []
    values = df.column_values(col)
    i = 0
    values.each -> (v)
      pos = -1
      j = 0
      gkeys.each -> (k)
        pos = j if k == v
        j += 1
      if pos == -1
        gkeys.push(v)
        buckets.push([i])
      else
        buckets[pos].push(i)
      i += 1
    @group_keys = gkeys
    @buckets = buckets

  -> size
    @group_keys.size

  -> keys
    @group_keys

  -> count
    counts = []
    @buckets.each -> (b)
      counts.push(b.size)
    DataFrame.new([[@col, @group_keys], [:count, counts]])

  # Aggregate a column per group with a lambda over each group's values.
  -> aggregate(col, f)
    vals = @df.column_values(col)
    out = []
    @buckets.each -> (b)
      group_vals = []
      b.each -> (i)
        group_vals.push(vals[i])
      out.push(f.call(group_vals))
    DataFrame.new([[@col, @group_keys], [col, out]])

  -> sum(col)
    f = -> (vs) Stats.sum(vs)
    self.aggregate(col, f)

  -> mean(col)
    f = -> (vs) Stats.mean(vs)
    self.aggregate(col, f)

  -> min(col)
    f = -> (vs) Stats.min(vs)
    self.aggregate(col, f)

  -> max(col)
    f = -> (vs) Stats.max(vs)
    self.aggregate(col, f)
