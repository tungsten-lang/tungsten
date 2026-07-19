# Pivot — pivot tables from a DataFrame
#
#     df.pivot(:city, :product, :sales)              # agg defaults to :sum
#     Pivot.table(df, :city, :product, :sales, :mean)
#
# Rows are the unique index values and columns the unique column values,
# both in first-seen order (Array#sort is not portable across engines).
# Each cell aggregates the `values` entries where index and column match;
# empty cells are nil. The result's data columns are NAMED BY the raw
# column values (e.g. the string "a"), so read them back with the same
# value: `p.column_values("a")`.
#
# agg: :sum, :mean, :median, :min, :max, :count, :first, :last
+ Pivot
  -> .table(df, index_col, columns_col, values_col, agg = :sum)
    ivals = df.column_values(index_col)
    cvals = df.column_values(columns_col)
    vvals = df.column_values(values_col)

    row_keys = []
    ivals.each -> (v)
      row_keys.push(v) if !row_keys.include?(v)
    col_keys = []
    cvals.each -> (v)
      col_keys.push(v) if !col_keys.include?(v)

    pairs = [[index_col, row_keys]]
    col_keys.each -> (ck)
      cells = []
      row_keys.each -> (rk)
        bucket = []
        i = 0
        ivals.each -> (iv)
          bucket.push(vvals[i]) if iv == rk && cvals[i] == ck
          i += 1
        if bucket.size == 0
          cells.push(nil)
        else
          cells.push(Pivot.aggregate(bucket, agg))
      pairs.push([ck, cells])
    DataFrame.new(pairs)

  # Aggregate an array of cell values by name.
  #
  # NOTE: sequential block-ifs assigning `out` — `return Stats.sum(...)`
  # under an if (modifier or block form) segfaults the interpreter today
  # when the returned value is a cross-class static call.
  -> .aggregate(values, agg)
    out = nil
    if agg == :sum
      out = Stats.sum(values)
    if agg == :mean
      out = Stats.mean(values)
    if agg == :median
      out = Stats.median(values)
    if agg == :count
      out = values.size
    if agg == :min
      out = Stats.min(values)
    if agg == :max
      out = Stats.max(values)
    if agg == :first
      out = values[0]
    if agg == :last
      out = values[values.size - 1]
    out
