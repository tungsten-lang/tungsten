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
