# DataFrame — the core data structure
# Columnar storage backed by Apache Arrow. No confusing index alignment,
# no SettingWithCopyWarning, no .iloc/.loc split. Just data.

in Tungsten:Koala

+ DataFrame
  ro :columns    # ordered list of column names (symbols)
  ro :store      # { name => Arrow:ChunkedArray }
  ro :index

  # Create a DataFrame from keyword columns.
  #
  #     df = DataFrame.new(
  #       name:   ["Alice", "Bob", "Carol"],
  #       age:    [30, 25, 35],
  #       salary: [80_000, 65_000, 95_000]
  #     )
  -> new(**columns)
    @columns = columns.keys
    @store   = columns.map -> (name, values)
      [name, Arrow:ChunkedArray.from(values)]
    .to_h
    @index = Index.new(self.row_count)
    self.validate!

  # Create from an array of row hashes.
  #
  #     df = DataFrame.from_rows([
  #       { name: "Alice", age: 30 },
  #       { name: "Bob",   age: 25 }
  #     ])
  -> .from_rows(rows)
    return self.new if rows.empty?
    cols = rows.first.keys
    data = cols.map -> (col)
      [col, rows.map(-> (row) row[col])]
    self.new(**data.to_h)

  # Create from an Arrow Table (zero-copy).
  -> .from_arrow(table)
    columns = table.column_names.map(&:to_sym)
    store = columns.map -> (name)
      [name, table.column(name)]
    .to_h
    df = self.allocate
    df.instance_set(:columns, columns)
    df.instance_set(:store, store)
    df.instance_set(:index, Index.new(table.num_rows))
    df

  # --- Properties ---

  -> row_count
    return 0 if @store.empty?
    @store.values.first.size

  -> col_count   @columns.size
  -> shape       [self.row_count, self.col_count]
  -> empty?      self.row_count == 0
  -> dtypes      @store.map(-> (name, arr) [name, arr.type]).to_h
  -> column_names @columns.dup

  # --- Column access ---

  # Access a column as a Series.
  #
  #     df[:name]       # => Series
  #     df["age"]       # => Series
  -> [](col)
    col = col.to_sym
    <! KeyError, "Column '[col]' not found" unless @store.key?(col)
    Series.new(@store[col].to_a, name: col, dtype: @store[col].type, index: @index)

  # Access multiple columns.
  #
  #     df[:name, :age]  # => DataFrame with two columns
  -> [](*cols)
    return self[cols.first] if cols.size == 1
    self.select(*cols)

  # --- Selection ---

  # Select specific columns — returns a new DataFrame.
  #
  #     df.select(:name, :age)
  -> select(*cols)
    cols = cols.map(&:to_sym)
    new_store = cols.map(-> (c) [c, @store[c]]).to_h
    self.class.from_store(new_store)

  # Drop columns.
  #
  #     df.drop(:salary)
  -> drop(*cols)
    cols = cols.map(&:to_sym)
    remaining = @columns.reject(-> (c) cols.include?(c))
    self.select(*remaining)

  # Rename columns.
  #
  #     df.rename(name: :full_name, age: :years)
  -> rename(**mapping)
    new_cols = @columns.map(-> (c) mapping[c] || c)
    new_store = @columns.zip(new_cols).map -> (old, new_name)
      [new_name, @store[old]]
    .to_h
    self.class.from_store(new_store)

  # --- Filtering ---

  # Filter rows by conditions.
  #
  #     df.where(age: 25..35)
  #     df.where(active: true, role: "admin")
  #     df.where -> (row) row.salary > 70_000
  -> where(conditions = nil, &block)
    case
    => block
      mask = self.row_count.times.map -> (i)
        row = self.row_at(i)
        block.call(row)
      self.apply_mask(mask)
    => conditions
      mask = Array.new(self.row_count, true)
      conditions.each -> (col, value)
        col_data = @store[col.to_sym].to_a
        case value
        => Range ->
          self.row_count.times(-> (i) mask[i] &&= value.include?(col_data[i]))
        => Array ->
          self.row_count.times(-> (i) mask[i] &&= value.include?(col_data[i]))
        => _ ->
          self.row_count.times(-> (i) mask[i] &&= col_data[i] == value)
      self.apply_mask(mask)

  # Head / tail.
  -> head(n = 5) self.slice(0, [n, self.row_count].min)
  -> tail(n = 5) self.slice([self.row_count - n, 0].max, self.row_count)
  -> first       self.head(1)
  -> last        self.tail(1)

  # Sample random rows.
  -> sample(n = 1, replace: false)
    indices = if replace
      n.times.map(-> Random.int(0, self.row_count))
    else
      (0...self.row_count).to_a.shuffle.take(n)
    self.take(indices)

  # --- Sorting ---

  # Sort by one or more columns.
  #
  #     df.sort_by(:age)
  #     df.sort_by(:age, :desc)
  #     df.sort_by(:department, :asc, :salary, :desc)
  -> sort_by(*args)
    # Parse args into (column, direction) pairs
    sort_keys = []
    i = 0
    loop
      break if i >= args.size
      col = args[i]
      dir = (args[i + 1].is_a?(Symbol) && [:asc, :desc].include?(args[i + 1])) ? args[i + 1] : :asc
      sort_keys.push([col.to_sym, dir])
      i += (dir == args[i + 1]) ? 2 : 1

    indices = (0...self.row_count).to_a.sort_by -> (idx)
      sort_keys.map -> (col, dir)
        val = @store[col].to_a[idx]
        dir == :desc ? ReverseSortKey.new(val) : val

    self.take(indices)

  # --- Grouping ---

  # Group by one or more columns.
  #
  #     df.group_by(:department)
  #       .agg(
  #         avg_salary: mean(:salary),
  #         headcount:  count(:name),
  #         max_age:    max(:age)
  #       )
  -> group_by(*cols)
    GroupBy.new(self, cols.map(&:to_sym))

  # --- Joins ---

  # Join with another DataFrame.
  #
  #     merged = employees.join(departments, on: :dept_id, how: :left)
  -> join(other, on:, how: :inner)
    Join.perform(self, other, on: on, how: how)

  # Shorthand joins.
  -> inner_join(other, on:) self.join(other, on: on, how: :inner)
  -> left_join(other, on:)  self.join(other, on: on, how: :left)
  -> right_join(other, on:) self.join(other, on: on, how: :right)
  -> outer_join(other, on:) self.join(other, on: on, how: :outer)

  # --- Pivot ---

  # Pivot table.
  #
  #     df.pivot(index: :date, columns: :product, values: :sales, agg: :sum)
  -> pivot(index:, columns:, values:, agg: :sum)
    Pivot.create(self, index: index, columns: columns, values: values, agg: agg)

  # --- Mutation ---

  # Add or update a column. Returns a new DataFrame.
  #
  #     df.assign(bonus: df[:salary] * 0.1)
  #     df.assign(full_name: -> (row) "[row.first] [row.last]")
  -> assign(**new_columns)
    new_store = @store.dup
    new_columns.each -> (name, source)
      values = case source
      => Series  -> source.values.to_a
      => Array   -> source
      => Proc    -> self.row_count.times.map(-> (i) source.call(self.row_at(i)))
      new_store[name.to_sym] = Arrow:ChunkedArray.from(values)
    self.class.from_store(new_store)

  # Apply a function to a column.
  -> transform(col, &block)
    values = @store[col.to_sym].to_a.map(&block)
    self.assign(**{ col.to_sym => values })

  # Drop rows with nil values.
  -> dropna(subset: nil)
    cols = subset ? subset.map(&:to_sym) : @columns
    mask = self.row_count.times.map -> (i)
      cols.all?(-> (c) @store[c].to_a[i] != nil)
    self.apply_mask(mask)

  # Fill nil values.
  -> fillna(value = nil, **column_values)
    new_store = @store.dup
    if value
      @columns.each -> (col)
        arr = new_store[col].to_a.map(-> (v) v || value)
        new_store[col] = Arrow:ChunkedArray.from(arr)
    column_values.each -> (col, fill)
      arr = new_store[col].to_a.map(-> (v) v || fill)
      new_store[col] = Arrow:ChunkedArray.from(arr)
    self.class.from_store(new_store)

  # --- Aggregation ---

  -> describe
    @columns.map -> (col)
      s = self[col]
      [col, {
        count:  s.count,
        mean:   s.mean,
        std:    s.std,
        min:    s.min,
        q25:    s.percentile(25),
        median: s.median,
        q75:    s.percentile(75),
        max:    s.max
      }]
    .to_h

  # --- IO ---

  -> to_csv(path = nil, **options)   IO:CSV.write(self, path, **options)
  -> to_parquet(path, **options)     IO:Parquet.write(self, path, **options)
  -> to_json(path = nil, **options)  IO:JSON.write(self, path, **options)
  -> to_excel(path, **options)       IO:Excel.write(self, path, **options)
  -> to_arrow                        self.to_arrow_table
  -> to_sql(table, conn, **options)  IO:SQL.write(self, table, conn, **options)

  -> to_huggingface(repo, **options)
    IO:HuggingFace.push_to_hub(self, repo, **options)

  # --- Conversion ---

  -> to_a
    self.row_count.times.map(-> (i) self.row_at(i))

  -> to_h
    @store.map(-> (name, arr) [name, arr.to_a]).to_h

  -> to_matrix(columns: nil)
    cols = columns ? columns.map(&:to_sym) : @columns
    rows = self.row_count.times.map -> (i)
      cols.map(-> (c) @store[c].to_a[i])
    Matrix.new(rows)

  -> to_arrow_table
    Arrow:Table.new(@store)

  # Piping support — every operation returns a new DataFrame,
  # so `|>` chains work naturally.
  #
  #     result = Koala.read_csv("data.csv")
  #       |> where(active: true)
  #       |> select(:name, :score, :grade)
  #       |> sort_by(:score, :desc)
  #       |> head(10)

  -> to_s
    lines = ["DataFrame [self.row_count] rows × [self.col_count] columns"]
    lines.push(@columns.map(-> (c) c.to_s.rjust(12)).join(" "))
    lines.push("-" * (@columns.size * 13))
    display = [self.row_count, 10].min
    display.times -> (i)
      row = @columns.map -> (c)
        @store[c].to_a[i].to_s.rjust(12)
      lines.push(row.join(" "))
    lines.push("  ... [self.row_count - 10] more rows") if self.row_count > 10
    lines.join("\n")

  # --- Internal ---

  -> .from_store(store)
    df = self.allocate
    df.instance_set(:columns, store.keys)
    df.instance_set(:store, store)
    df.instance_set(:index, Index.new(store.values.first&.size || 0))
    df

  [private]

  -> validate!
    return if @store.empty?
    expected = @store.values.first.size
    @store.each -> (name, arr)
      <! ShapeError, "Column '[name]' has [arr.size] rows, expected [expected]" unless arr.size == expected

  -> row_at(i)
    Row.new(@columns.map(-> (c) [c, @store[c].to_a[i]]).to_h)

  -> apply_mask(mask)
    new_store = @store.map -> (name, arr)
      values = arr.to_a
      filtered = mask.each_with_index
        .select(-> (keep, _) keep)
        .map(-> (_, i) values[i])
      [name, Arrow:ChunkedArray.from(filtered)]
    .to_h
    self.class.from_store(new_store)

  -> slice(from, to)
    indices = (from...to).to_a
    self.take(indices)

  -> take(indices)
    new_store = @store.map -> (name, arr)
      values = arr.to_a
      [name, Arrow:ChunkedArray.from(indices.map(-> (i) values[i]))]
    .to_h
    self.class.from_store(new_store)


# Row — a single row accessed by column name
+ Row
  -> new(@data)
  -> [](col)         @data[col.to_sym]
  -> method_missing(name, *) @data[name] || super
  -> to_h            @data.dup
  -> to_s            @data.to_s

# Helper for descending sort
+ ReverseSortKey
  -> new(@value)
  -> <=>(other) other.value <=> @value

+ ShapeError < Error
+ KeyError < Error
