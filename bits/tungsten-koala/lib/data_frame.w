# DataFrame — ordered named columns of equal length
#
# Columns are ordered [name, values] pairs (a hash would lose column order):
#
#     df = DataFrame.new([
#       [:name, ["Alice", "Bob", "Carol"]],
#       [:age,  [30, 25, 35]]
#     ])

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

  # --- I/O (CSV) ---
  #
  # String-only on purpose: `File` is undefined on the interpreter
  # (docs/compiler-issues.md), so path helpers would be compiled-only
  # and dual-engine-hostile. Callers with File write the string:
  #
  #     text = df.to_csv_string
  #     df2  = DataFrame.from_csv_string(text)
  #     File.write("out.csv", text)          # compiled
  #     df3  = DataFrame.from_csv_string(File.read("out.csv"))
  #
  # Round-trip is text fidelity for cells, not float bit-exactness
  # (use Persist for models). RFC-ish: commas separate; fields with
  # comma / quote / newline are double-quoted; quotes doubled inside.
  # First row is the header. Empty field -> nil. Integers and plain
  # floats parse as numbers; everything else stays a String.

  -> to_csv_string
    names = @names
    cols = @cols
    lines = []
    header = []
    names.each -> (n)
      header.push(DataFrame.csv_escape(n.to_s))
    lines.push(header.join(","))
    self.row_count.times -> (i)
      cells = []
      cols.each -> (c)
        cells.push(DataFrame.csv_escape_cell(c[i]))
      lines.push(cells.join(","))
    lines.join("\n")

  -> .from_csv_string(text)
    out = nil
    if text != nil && type(text) == "String" && text.size > 0
      rows = DataFrame.csv_parse_rows(text)
      if rows.size > 0
        header = rows[0]
        pairs = []
        j = 0
        header.each -> (h)
          col = []
          i = 1
          while i < rows.size
            row = rows[i]
            cell = nil
            cell = row[j] if j < row.size
            col.push(DataFrame.csv_parse_cell(cell))
            i += 1
          pairs.push([DataFrame.csv_header_name(h), col])
          j += 1
        out = DataFrame.new(pairs)
    out

  # Header cell → column name. Simple identifiers become Symbols so
  # df[:age] works after a round-trip; anything else stays a String.
  -> .csv_header_name(h)
    out = ""
    out = h.to_s if h != nil
    simple = out.size > 0
    i = 0
    while i < out.size && simple
      c = out[i]
      ok = false
      ok = true if c >= "a" && c <= "z"
      ok = true if c >= "A" && c <= "Z"
      ok = true if c >= "0" && c <= "9"
      ok = true if c == "_"
      simple = false if !ok
      i += 1
    out = out.to_sym if simple
    out

  # Escape a header or already-string cell for CSV.
  -> .csv_escape(s)
    t = s
    t = "" if t == nil
    t = t.to_s
    need = false
    need = true if t.include?(",")
    need = true if t.include?("\"")
    need = true if t.include?("\n")
    need = true if t.include?("\r")
    out = t
    if need
      out = "\"" + t.split("\"").join("\"\"") + "\""
    out

  -> .csv_escape_cell(v)
    out = ""
    if v == nil
      out = ""
    else
      out = DataFrame.csv_escape(v.to_s)
    out

  # Split text into rows of field strings (no type coercion).
  -> .csv_parse_rows(text)
    rows = []
    row = []
    field = ""
    in_q = false
    i = 0
    n = text.size
    while i < n
      ch = text[i]
      if in_q
        if ch == "\""
          nxt = ""
          nxt = text[i + 1] if i + 1 < n
          if nxt == "\""
            field = field + "\""
            i += 1
          else
            in_q = false
        else
          field = field + ch
      else
        if ch == "\""
          in_q = true
        else
          if ch == ","
            row.push(field)
            field = ""
          else
            if ch == "\n"
              row.push(field)
              rows.push(row)
              row = []
              field = ""
            else
              if ch == "\r"
                # swallow; \r\n handled by ignoring \r
                0
              else
                field = field + ch
      i += 1
    # last field / row (no trailing newline)
    row.push(field)
    # drop a final empty row produced only by a trailing newline
    if row.size == 1 && row[0] == "" && rows.size > 0
      0
    else
      rows.push(row)
    rows

  # "" -> nil; integer text -> Integer; plain float text -> Float;
  # else String. Leading/trailing space is kept for non-numbers.
  -> .csv_parse_cell(s)
    out = nil
    if s != nil && s != ""
      t = type(s)
      raw = s
      raw = s.to_s if t != "String"
      # integer?
      is_int = true
      j = 0
      m = raw.size
      if m == 0
        is_int = false
      if m > 0 && (raw[0] == "-" || raw[0] == "+")
        j = 1
        is_int = false if m == 1
      while j < m && is_int
        c = raw[j]
        is_int = false if c < "0" || c > "9"
        j += 1
      if is_int
        out = raw.to_i
      else
        # float: digits with one dot, optional leading sign
        is_f = true
        dots = 0
        j = 0
        if m == 0
          is_f = false
        if m > 0 && (raw[0] == "-" || raw[0] == "+")
          j = 1
          is_f = false if m == 1
        while j < m && is_f
          c = raw[j]
          if c == "."
            dots += 1
            is_f = false if dots > 1
          else
            is_f = false if c < "0" || c > "9"
          j += 1
        is_f = false if dots != 1
        if is_f
          out = raw.to_f
        else
          out = raw
    out

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
