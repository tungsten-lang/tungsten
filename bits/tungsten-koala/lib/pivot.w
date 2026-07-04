# Pivot — pivot table operations

in Tungsten:Koala

+ Pivot
  # Create a pivot table from a DataFrame.
  #
  #     df.pivot(index: :date, columns: :product, values: :sales, agg: :sum)
  -> .create(df, index:, columns:, values:, agg: :sum)
    index   = index.to_sym
    columns = columns.to_sym
    values  = values.to_sym

    # Get unique index and column values
    index_vals  = df[index].unique.to_a.sort
    column_vals = df[columns].unique.to_a.sort

    # Build the aggregation function
    agg_fn = case agg
    => :sum    -> -> (vs) vs.sum
    => :mean   -> -> (vs) vs.sum.to_f / vs.size
    => :count  -> -> (vs) vs.size
    => :min    -> -> (vs) vs.min
    => :max    -> -> (vs) vs.max
    => :first  -> -> (vs) vs.first
    => :last   -> -> (vs) vs.last
    => Proc    -> agg

    # Group data
    groups = {}
    df.row_count.times -> (i)
      idx_val = df.store[index].to_a[i]
      col_val = df.store[columns].to_a[i]
      val     = df.store[values].to_a[i]
      key = [idx_val, col_val]
      groups[key] ||= []
      groups[key].push(val)

    # Build result columns
    result = { index => index_vals }
    column_vals.each -> (cv)
      col_name = cv.to_s.to_sym
      result[col_name] = index_vals.map -> (iv)
        group = groups[[iv, cv]]
        group ? agg_fn.call(group) : nil

    DataFrame.new(**result)
