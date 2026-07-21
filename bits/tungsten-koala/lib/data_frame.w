# DataFrame — ordered named columns of equal length
#
# Columns are ordered [name, values] pairs (a hash would lose column order):
#
#     df = DataFrame.new([
#       [:name, ["Alice", "Bob", "Carol"]],
#       [:age,  [30, 25, 35]]
#     ])
#
# NOTE: inside `-> (x)` blocks this file deliberately uses locals hoisted
# from ivars — the interpreter cannot resolve @ivars from a block body.

+ DataFrame
  ro :names   # ordered column names
  ro :cols    # parallel array of value arrays

  -> new(columns)
    names = []
    cols = []
    columns.each -> (pair)
      names.push(pair[0])
      cols.push(pair[1])
    @names = names
    @cols = cols

  # --- Shape ---

  -> row_count
    return 0 if @cols.size == 0
    @cols[0].size

  -> col_count
    @names.size

  -> shape
    [self.row_count, self.col_count]

  -> empty?
    self.row_count == 0

  -> column_names
    @names

  # --- Column access ---

  -> col_index(name)
    idx = -1
    i = 0
    @names.each -> (n)
      idx = i if n == name
      i += 1
    idx

  -> column_values(name)
    i = self.col_index(name)
    return nil if i == -1
    @cols[i]

  -> column(name)
    vals = self.column_values(name)
    return nil if vals == nil
    Series.new(vals, name)

  -> [](name)
    self.column(name)

  -> select_columns(wanted)
    all_names = @names
    all_cols = @cols
    pairs = []
    wanted.each -> (n)
      i = -1
      j = 0
      all_names.each -> (m)
        i = j if m == n
        j += 1
      pairs.push([n, all_cols[i]]) if i != -1
    DataFrame.new(pairs)

  # --- Rows ---

  # All rows as hashes of column name -> value.
  -> to_rows
    names = @names
    cols = @cols
    out = []
    self.row_count.times -> (i)
      h = {}
      j = 0
      names.each -> (n)
        h[n] = cols[j][i]
        j += 1
      out.push(h)
    out

  # Row i as a hash of column name -> value.
  -> row(i)
    h = {}
    j = 0
    names = @names
    cols = @cols
    names.each -> (n)
      h[n] = cols[j][i]
      j += 1
    h

  -> take(indices)
    names = @names
    cols = @cols
    pairs = []
    j = 0
    names.each -> (n)
      vals = cols[j]
      picked = []
      indices.each -> (i)
        picked.push(vals[i])
      pairs.push([n, picked])
      j += 1
    DataFrame.new(pairs)

  # Filter rows: the block receives each row as a hash.
  #
  #     adults = df.where -> (row) row[:age] >= 18
  -> where(&)
    rows = self.to_rows
    keep = []
    i = 0
    rows.each -> (r)
      keep.push(i) if &(r)
      i += 1
    self.take(keep)

  -> head(n = 5)
    limit = n
    limit = self.row_count if self.row_count < n
    idx = []
    limit.times -> (i)
      idx.push(i)
    self.take(idx)

  # --- Grouping ---

  -> group_by(col)
    GroupBy.new(self, col)

  # --- Combining / reshaping ---

  # Merge with another frame on a key column (see join.w).
  #
  #     df.join(other, :id)           # inner join
  #     df.join(other, :id, :left)    # left join
  -> join(other, key, how = :inner)
    Join.perform(self, other, key, how)

  # Pivot table (see pivot.w).
  #
  #     df.pivot(:city, :product, :sales)          # agg defaults to :sum
  #     df.pivot(:city, :product, :sales, :mean)
  -> pivot(index_col, columns_col, values_col, agg = :sum)
    Pivot.table(self, index_col, columns_col, values_col, agg)

  # --- Conversion ---

  # Numeric columns (Stats.numeric?) as a Matrix, one row per frame
  # row, column order preserved; string/symbol columns are skipped.
  # nil when the frame has no numeric column. nil cells pass through
  # unchanged — run an Imputer first if the Matrix feeds arithmetic.
  -> to_matrix
    cols = @cols
    keep = []
    i = 0
    cols.each -> (c)
      keep.push(i) if Stats.numeric?(c)
      i += 1
    out = nil
    if keep.size > 0
      rows = []
      self.row_count.times -> (r)
        row = []
        keep.each -> (j)
          row.push(cols[j][r])
        rows.push(row)
      out = Matrix.new(rows)
    out

  # --- Summary ---

  # Per-column summary statistics, pandas-style. Returns a DataFrame
  # whose leading :statistic column labels the rows count / mean / std /
  # min / 25% / 50% / 75% / max, with one further column per NUMERIC
  # source column, in column order (non-numeric columns are skipped, as
  # pandas' default describe does). count is the non-nil count; std is
  # the sample standard deviation (n - 1 denominator), matching pandas;
  # the quartiles use linear-interpolation percentiles (Stats.percentile,
  # so the 50% row equals the median). An empty frame, or one with no
  # numeric column, yields just the :statistic column.
  #
  # NOTE: locals hoisted from ivars before the block; no early return.
  -> describe
    names = @names
    cols = @cols
    labels = ["count", "mean", "std", "min", "25%", "50%", "75%", "max"]
    pairs = [[:statistic, labels]]
    i = 0
    names.each -> (n)
      c = cols[i]
      if Stats.numeric?(c)
        stats = []
        stats.push(Stats.clean(c).size)
        stats.push(Stats.mean(c))
        stats.push(Stats.std(c))
        stats.push(Stats.min(c).to_f)
        stats.push(Stats.percentile(c, 25))
        stats.push(Stats.percentile(c, 50))
        stats.push(Stats.percentile(c, 75))
        stats.push(Stats.max(c).to_f)
        pairs.push([n, stats])
      i += 1
    DataFrame.new(pairs)

  # --- Display ---

  -> to_s
    names = @names
    cols = @cols
    lines = []
    lines.push("DataFrame [self.row_count] rows x [self.col_count] cols")
    header = []
    names.each -> (n)
      header.push(n.to_s)
    lines.push(header.join(", "))
    self.row_count.times -> (i)
      cells = []
      cols.each -> (c)
        cells.push(c[i].to_s)
      lines.push(cells.join(", "))
    lines.join("\n")
