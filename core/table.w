# Table — a column-oriented, labeled two-dimensional data structure.
#
# A Table is a list of named columns of equal length, plus an optional row
# index. Each column is an ordinary polymorphic Array, so cells may hold any
# value and arithmetic stays exact wherever the language is exact (Decimal
# literals stay Decimal, Int sums stay Int).
#
#   t = Table.new({:name => ["ada", "grace"], :age => [36, 45]})
#   t[:age]                 # => [36, 45]
#   t.row(0)                # => {name: "ada", age: 36}
#   t.at(1, :name)          # => "grace"
#   t.where -> (r) r[:age] > 40
#   t.sort_by(:age, true)
#   t.group_by(:city).mean(:age)
#   t.join(other, :id, :left)
#
# Column names are normalized to Symbols on the way in, so `t[:age]` and
# `t["age"]` name the same column.
#
# Design notes
# ------------
# * No trait is mixed in. `Comparable` would need a total order on tables,
#   which does not exist; `Enumerable`'s block-taking `select`/`sort_by`/
#   `group_by`/`count` collide with the column-name-taking methods of the same
#   name here, and the two engines resolve that collision differently. Row
#   iteration is offered directly: `each_row`, `map_rows`, `find_row`,
#   `reduce_rows`, and `to_a` (an Array of row Hashes, which *is* Enumerable).
# * Every table owns its column storage: constructors copy the arrays handed
#   to them and `column`/`[]` hand back copies, so `push` (the one mutator) can
#   never corrupt a table derived from another one.
# * `with_column(name, values)` and `compute_column(name, &)` are separate
#   methods: a two-argument overload whose second form is a block cannot be
#   told apart from the value form on either engine.
# * The pandas surface entries that need an external system — to_clipboard,
#   to_excel, to_gbq, plot — and to_sparse/to_dense, which need a sparse
#   representation Tungsten does not have, are deliberately absent rather than
#   present as stubs. `to_sql` renders INSERT statements and is implemented.
#
# Engine limitations worked around here (all reported, none fixable from core)
# ---------------------------------------------------------------------------
# * `t << row` never reaches a user-defined `<<`; both engines lower the infix
#   form to an addition. Use `t.push(row)` or `t.<<(row)`.
# * A Symbol *literal* handed to a method named `select`, `reject`, `map` or
#   `count` is rewritten into a block by the compiled front end, so
#   `t.select(:age)` and `groups.count(:pay)` raise there. Pass a list, a
#   String, or a Symbol held in a variable.
# * On the compiled engine an exception raised inside a constructor whose
#   parameters carry defaults or keywords escapes the caller's `begin`/
#   `rescue`; `new` therefore spells out its no-argument and one-argument
#   arities so that construction errors stay catchable.
#
# @see Record
# @see CSV
# @see pandas.DataFrame

use core/csv
use core/file

+ Table

  # ---------------------------------------------------------------- build --

  # data may be:
  #   nil                     — an empty table
  #   Hash                    — column name => Array of values
  #   Array of Hash           — row records (column order is first-seen order)
  #   Array of Array          — positional rows; needs `columns:`
  #   Table                   — a copy
  # index:   Array of row labels, one per row
  # columns: Array of column names selecting and ordering the result
  #
  # The no-argument and one-argument arities are spelled out rather than
  # folded into a defaulted parameter list on purpose: on the compiled engine
  # an exception raised inside a constructor whose parameters carry defaults
  # or keywords escapes the caller's `begin`/`rescue`, so the construction
  # errors below would be uncatchable there. Only the keyword form still has
  # that engine limitation.
  -> new
    __initialize(nil, nil, nil)

  -> new(data)
    __initialize(data, nil, nil)

  -> new(data, index: nil, columns: nil)
    __initialize(data, index, columns)

  -> __initialize(data, index, columns)
    @names = []
    @cols = []
    @rows = 0
    @index = nil
    __load(data, columns)
    __set_index(index)
    self

  -> .from_columns(hash)
    Table.new(hash)

  -> .from_rows(rows)
    Table.new(rows)

  -> .from_rows(rows, names)
    Table.new(rows, columns: names)

  -> .from_records(rows)
    Table.new(rows)

  -> .empty
    Table.new

  # Parse a complete CSV document. The first record supplies the column names
  # unless `headers:` is false, in which case columns are named c0, c1, ...
  # With `infer:` true (the default) integer- and decimal-looking fields are
  # converted, empty fields become nil, and everything else stays a String.
  -> .from_csv(text, separator: ",", headers: true, infer: true)
    records = CSV.parse(text, separator)
    if records.size == 0
      return Table.new
    names = []
    start = 0
    if headers
      head = records[0]
      i = 0
      while i < head.size
        names.push(Table.normalize_name(head[i]))
        i += 1
      start = 1
    else
      i = 0
      while i < records[0].size
        names.push(Table.normalize_name("c" + i.to_s))
        i += 1
    cols = []
    j = 0
    while j < names.size
      cols.push([])
      j += 1
    n_records = records.size
    n_names = names.size
    r = start
    while r < n_records
      record = records[r] ## Array
      rec_size = record.size
      # A trailing newline yields one empty record; drop it rather than
      # inventing a row of nils.
      if rec_size == 1 && record[0] == "" && n_names > 1
        r += 1
        next
      j = 0
      while j < n_names
        raw = nil
        if j < rec_size
          raw = record[j]
        col_j = cols[j] ## Array
        col_j.push(Table.parse_field(raw, infer))
        j += 1
      r += 1
    Table.build(names, cols, nil)

  # Read a CSV file from disk.
  -> .load(path)
    Table.from_csv(File.read(path))

  -> .load(path, separator)
    Table.from_csv(File.read(path), separator: separator)

  # Internal constructor: adopts `cols` without copying. Callers must hand
  # over freshly built arrays.
  -> .build(names, cols, index)
    t = Table.new
    t.__adopt(names, cols, index)
    t

  -> __adopt(names, cols, index)
    @names = names
    @cols = cols
    @rows = 0
    if cols.size > 0
      @rows = cols[0].size
    @index = index
    self

  # ------------------------------------------------------------- normalize --

  -> .normalize_name(name)
    t = type(name)
    return name if t == "Symbol"
    return name.to_sym if t == "String"
    raise "Table column names must be a Symbol or a String, got " + t

  -> .normalize_column(name, values)
    if type(values) != "Array"
      raise "Table column '" + name.to_s + "' must be an Array, got " + type(values)
    values.dup

  -> .parse_field(raw, infer)
    return nil if raw == nil
    return raw if !infer
    s = raw ## String
    view = ccall("w_string_bytes_view", s) ## u8[]
    n = view.size ## i64
    return nil if n == 0
    if view[0] <= 32 || view[n - 1] <= 32
      s = s.strip
      view = ccall("w_string_bytes_view", s) ## u8[]
      n = view.size ## i64
      return nil if n == 0
    kind = Table.numeric_literal_b(view, n)
    return s.to_i if kind == :int
    return s.to_d if kind == :decimal
    raw

  # :int, :decimal or :none — a hand scanner, because String#to_i and
  # String#to_d both answer 0 for a non-numeric string and so cannot be used
  # to decide whether a field is a number at all.
  -> .numeric_literal(s)
    str = s ## String
    view = ccall("w_string_bytes_view", str) ## u8[]
    n = view.size ## i64
    return :none if n == 0
    Table.numeric_literal_b(view, n)

  -> .numeric_literal_b(view, len)
    v = view ## u8[]
    n = len ## i64
    return :none if n == 0
    i = 0
    lead = v[0]
    if lead == 45 || lead == 43
      i = 1
    digits = 0
    dots = 0
    while i < n
      b = v[i]
      if b >= 48 && b <= 57
        digits += 1
      elsif b == 46
        dots += 1
      else
        return :none
      i += 1
    return :none if digits == 0
    return :int if dots == 0
    return :decimal if dots == 1
    :none

  -> .numeric?(v)
    t = type(v)
    return true if t == "Int"
    return true if t == "Decimal"
    return true if t == "Float"
    return true if t == "BigInt"
    return true if t == "BigDecimal"
    return true if t == "Rational"
    false

  -> .truthy?(v)
    return false if v == nil
    return false if v == false
    true

  # Cell rendering shared by to_s, to_csv and the group signatures. nil is the
  # empty string; everything else is its own to_s.
  -> .render(v)
    return "" if v == nil
    v.to_s

  -> .name_list(names)
    out = ""
    i = 0
    while i < names.size
      out += ", " if i > 0
      out += names[i].to_s
      i += 1
    out

  # --------------------------------------------------------------- loading --

  -> __load(data, columns)
    if data != nil
      t = type(data)
      if t == "Hash"
        __load_columns(data)
      elsif t == "Array"
        __load_array(data)
      elsif t == "Table"
        __load_columns(data.to_h)
      else
        raise "Table.new expects a Hash of columns or an Array of rows, got " + t
    __apply_columns(columns)
    self

  -> __load_columns(hash)
    keys = hash.keys
    i = 0
    while i < keys.size
      key = Table.normalize_name(keys[i])
      col = Table.normalize_column(key, hash[keys[i]])
      if @names.size == 0
        @rows = col.size
      elsif col.size != @rows
        raise "Table column '" + key.to_s + "' has " + col.size.to_s + " rows, expected " + @rows.to_s
      if __pos(key) >= 0
        raise "Table column '" + key.to_s + "' is defined twice"
      @names.push(key)
      @cols.push(col)
      i += 1
    self

  -> __load_array(rows)
    return self if rows.size == 0
    first = rows[0]
    return __load_row_hashes(rows) if type(first) == "Hash"
    return __load_row_arrays(rows) if type(first) == "Array"
    raise "Table rows must be Hashes or Arrays, got " + type(first)

  -> __load_row_hashes(rows)
    seen = {}
    i = 0
    while i < rows.size
      row = rows[i]
      if type(row) != "Hash"
        raise "Table row " + i.to_s + " must be a Hash, got " + type(row)
      keys = row.keys
      j = 0
      while j < keys.size
        key = Table.normalize_name(keys[j])
        if !seen.has_key?(key)
          seen[key] = true
          @names.push(key)
          @cols.push([])
        j += 1
      i += 1
    i = 0
    while i < rows.size
      j = 0
      while j < @names.size
        @cols[j].push(Table.lookup(rows[i], @names[j]))
        j += 1
      i += 1
    @rows = rows.size
    self

  # Positional rows: names arrive later through `columns:`, so park the widest
  # row's arity as c0..cN and let __apply_columns rename.
  -> __load_row_arrays(rows)
    width = 0
    i = 0
    while i < rows.size
      if type(rows[i]) != "Array"
        raise "Table row " + i.to_s + " must be an Array, got " + type(rows[i])
      width = rows[i].size if rows[i].size > width
      i += 1
    j = 0
    while j < width
      @names.push(Table.normalize_name("c" + j.to_s))
      @cols.push([])
      j += 1
    i = 0
    while i < rows.size
      row = rows[i]
      j = 0
      while j < width
        value = nil
        value = row[j] if j < row.size
        @cols[j].push(value)
        j += 1
      i += 1
    @rows = rows.size
    self

  # A row Hash may be keyed by Symbol or by String; accept either.
  -> .lookup(row, key)
    return row[key] if row.has_key?(key)
    s = key.to_s
    return row[s] if row.has_key?(s)
    nil

  # `columns:` either renames positional columns (same count, currently c0..cN)
  # or selects and orders named ones.
  -> __apply_columns(columns)
    return self if columns == nil
    wanted = []
    i = 0
    while i < columns.size
      wanted.push(Table.normalize_name(columns[i]))
      i += 1
    Table.check_unique(wanted)
    if wanted.size == @names.size && __all_positional?
      @names = wanted
      return self
    names = []
    cols = []
    i = 0
    while i < wanted.size
      pos = __pos(wanted[i])
      if pos < 0
        raise "Table has no column '" + wanted[i].to_s + "'; columns are " + Table.name_list(@names)
      names.push(wanted[i])
      cols.push(@cols[pos])
      i += 1
    @names = names
    @cols = cols
    self

  -> __all_positional?
    i = 0
    while i < @names.size
      return false if @names[i] != Table.normalize_name("c" + i.to_s)
      i += 1
    true

  -> .check_unique(names)
    i = 0
    while i < names.size
      j = i + 1
      while j < names.size
        raise "Table column '" + names[i].to_s + "' is listed twice" if names[i] == names[j]
        j += 1
      i += 1
    names

  -> __set_index(index)
    return self if index == nil
    if type(index) != "Array"
      raise "Table index must be an Array, got " + type(index)
    if index.size != @rows
      raise "Table index has " + index.size.to_s + " labels, expected " + @rows.to_s
    @index = index.dup
    self

  # ----------------------------------------------------------- shape/meta --

  -> size
    @rows

  -> length
    @rows

  -> row_count
    @rows

  -> column_count
    @names.size

  -> width
    @names.size

  -> dimensions
    [@rows, @names.size]

  -> shape
    [@rows, @names.size]

  -> columns
    @names.dup

  -> column_names
    @names.dup

  -> keys
    @names.dup

  # Row-major cell values, one Array per row.
  -> values
    out = []
    i = 0
    while i < @rows
      row = []
      j = 0
      while j < @names.size
        row.push(@cols[j][i])
        j += 1
      out.push(row)
      i += 1
    out

  -> index
    return @index.dup if @index != nil
    out = []
    i = 0
    while i < @rows
      out.push(i)
      i += 1
    out

  -> axes
    [index, @names.dup]

  -> blank?
    @rows == 0

  -> empty?
    @rows == 0

  -> covers?(name)
    __pos(Table.normalize_name(name)) >= 0

  -> has_column?(name)
    covers?(name)

  -> info
    out = "Table: " + @rows.to_s + " rows, " + @names.size.to_s + " columns"
    wide = 0
    i = 0
    while i < @names.size
      wide = @names[i].to_s.size if @names[i].to_s.size > wide
      i += 1
    j = 0
    while j < @names.size
      col = @cols[j]
      kind = "Nil"
      filled = 0
      i = 0
      while i < @rows
        if col[i] != nil
          filled += 1
          kind = type(col[i]) if kind == "Nil"
        i += 1
      out += "\n  " + @names[j].to_s.rpad(wide) + "  " + kind.rpad(8) + " " + filled.to_s + " non-nil"
      j += 1
    out

  # ---------------------------------------------------------------- access --

  -> __pos(key)
    i = 0
    while i < @names.size
      return i if @names[i] == key
      i += 1
    -1

  -> __require(name)
    key = Table.normalize_name(name)
    pos = __pos(key)
    if pos < 0
      raise "Table has no column '" + key.to_s + "'; columns are " + Table.name_list(@names)
    pos

  -> __require_row(i)
    if type(i) != "Int"
      raise "Table row index must be an Int, got " + type(i)
    at = i
    at = @rows + at if at < 0
    if at < 0 || at >= @rows
      raise "Table row index " + i.to_s + " is out of range (" + @rows.to_s + " rows)"
    at

  # An Int selects a row, a name selects a column, an Array of names selects a
  # sub-table.
  -> [](key)
    t = type(key)
    return row(key) if t == "Int"
    return select(key) if t == "Array"
    column(key)

  -> column(name)
    @cols[__require(name)].dup

  -> row(i)
    at = __require_row(i)
    out = {}
    j = 0
    while j < @names.size
      out[@names[j]] = @cols[j][at]
      j += 1
    out

  -> at(i)
    row(i)

  -> at(i, name)
    @cols[__require(name)][__require_row(i)]

  -> first
    return nil if @rows == 0
    row(0)

  -> last
    return nil if @rows == 0
    row(@rows - 1)

  -> xs(i)
    row(i)

  -> head
    head(5)

  -> head(n)
    count = n
    count = @rows if count > @rows
    count = 0 if count < 0
    __rows_at(Table.span(0, count))

  -> tail
    tail(5)

  -> tail(n)
    count = n
    count = @rows if count > @rows
    count = 0 if count < 0
    __rows_at(Table.span(@rows - count, count))

  -> take(n)
    head(n)

  # Int drops leading rows; a name or Array of names drops columns.
  -> drop(arg)
    return __drop_rows(arg) if type(arg) == "Int"
    except(arg)

  -> __drop_rows(n)
    start = n
    start = 0 if start < 0
    start = @rows if start > @rows
    __rows_at(Table.span(start, @rows - start))

  # Positional row range, both ends inclusive.
  -> between(low, high)
    a = low
    b = high
    a = 0 if a < 0
    b = @rows - 1 if b > @rows - 1
    return __rows_at([]) if a > b
    __rows_at(Table.span(a, b - a + 1))

  -> truncate(before, after)
    between(before, after)

  -> .span(start, count)
    out = []
    i = 0
    while i < count
      out.push(start + i)
      i += 1
    out

  -> slice(start, count)
    a = start
    a = 0 if a < 0
    n = count
    n = @rows - a if a + n > @rows
    n = 0 if n < 0
    __rows_at(Table.span(a, n))

  # n rows drawn without replacement. `sample(n, seed)` is reproducible.
  # Four bytes of entropy: enough to shuffle with, and small enough that the
  # seed stays an Int rather than promoting to a BigInt the i64 mixer cannot
  # take.
  -> sample(n)
    seed = 0
    bytes = Random.bytes(4)
    i = 0
    while i < bytes.size
      seed = seed * 256 + bytes[i]
      i += 1
    sample(n, seed + 1)

  -> sample(n, seed)
    count = n
    count = @rows if count > @rows
    count = 0 if count < 0
    pool = Table.span(0, @rows)
    state = seed
    state = 1 if state == 0
    picked = []
    i = 0
    while i < count
      state = Table.next_random(state)
      pick = i + state % (pool.size - i)
      swap = pool[pick]
      pool[pick] = pool[i]
      pool[i] = swap
      picked.push(swap)
      i += 1
    __rows_at(picked)

  # xorshift64* — deterministic, and every state is reachable from any seed.
  -> .next_random(state)
    x = state ## i64
    x = x ^ (x << 13)
    x = x ^ ((x >> 7) & 144_115_188_075_855_871)
    x = x ^ (x << 17)
    x & 4_611_686_018_427_387_903

  -> __rows_at(idxs)
    idx_arr = idxs ## Array
    n_idxs = idx_arr.size
    cols = []
    j = 0
    n_cols = @names.size
    while j < n_cols
      col = @cols[j] ## Array
      out = []
      i = 0
      while i < n_idxs
        out.push(col[idx_arr[i]])
        i += 1
      cols.push(out)
      j += 1
    labels = nil
    if @index != nil
      idx_src = @index ## Array
      labels = []
      i = 0
      while i < n_idxs
        labels.push(idx_src[idx_arr[i]])
        i += 1
    t = Table.build(@names.dup, cols, labels)
    t.__set_rows(n_idxs)
    t

  # Keeps @rows honest for a zero-column table.
  -> __set_rows(n)
    @rows = n
    self

  # ------------------------------------------------------------ projection --

  -> __key_list(key)
    if type(key) == "Array"
      out = []
      i = 0
      while i < key.size
        out.push(Table.normalize_name(key[i]))
        i += 1
      return out
    [Table.normalize_name(key)]

  # Columns, by name or list of names. Row filtering lives in `where`.
  #
  # Prefer the list form. A bare Symbol *literal* handed to a method named
  # `select` is rewritten into a block by the compiled front end before user
  # dispatch happens, so `t.select(:age)` raises there while `t.select([:age])`,
  # `t.select("age")` and `t.select(name_held_in_a_variable)` all work.
  -> select(names)
    wanted = Table.check_unique(__key_list(names))
    cols = []
    i = 0
    while i < wanted.size
      cols.push(@cols[__require(wanted[i])].dup)
      i += 1
    t = Table.build(wanted, cols, __index_copy)
    t.__set_rows(@rows)
    t

  -> except(names)
    unwanted = __key_list(names)
    i = 0
    while i < unwanted.size
      __require(unwanted[i])
      i += 1
    keep = []
    j = 0
    while j < @names.size
      keep.push(@names[j]) if !Table.member?(unwanted, @names[j])
      j += 1
    select(keep)

  -> drop_columns(names)
    except(names)

  -> .member?(list, value)
    i = 0
    while i < list.size
      return true if list[i] == value
      i += 1
    false

  -> rename(mapping)
    keys = mapping.keys
    names = @names.dup
    i = 0
    while i < keys.size
      pos = __require(keys[i])
      names[pos] = Table.normalize_name(mapping[keys[i]])
      i += 1
    j = 0
    while j < names.size
      k = j + 1
      while k < names.size
        raise "Table rename would produce two columns named '" + names[j].to_s + "'" if names[j] == names[k]
        k += 1
      j += 1
    cols = []
    j = 0
    while j < @cols.size
      cols.push(@cols[j].dup)
      j += 1
    t = Table.build(names, cols, __index_copy)
    t.__set_rows(@rows)
    t

  -> __index_copy
    return nil if @index == nil
    @index.dup


use core/table/transform
use core/table/analytics

# The result of Table#group_by: the grouping key columns, one label per group,
# and one Table per group. Aggregations fold every group down to a single row
# and return a Table keyed by the grouping columns.
+ TableGroups
  -> new(keys, labels, groups)
    @keys = keys
    @labels = labels
    @groups = groups
    self

  -> size
    @groups.size

  -> length
    @groups.size

  -> keys
    @keys.dup

  -> labels
    @labels.dup

  -> groups
    @groups.dup

  -> tables
    @groups.dup

  -> [](label)
    i = 0
    while i < @labels.size
      return @groups[i] if @labels[i] == label
      i += 1
    nil

  -> has_key?(label)
    i = 0
    while i < @labels.size
      return true if @labels[i] == label
      i += 1
    false

  -> to_h
    out = {}
    i = 0
    while i < @labels.size
      out[@labels[i]] = @groups[i]
      i += 1
    out

  -> each(&)
    i = 0
    while i < @labels.size
      &(@labels[i], @groups[i])
      i += 1
    self

  # Rows per group, as a :count column.
  -> count
    __build([[:count, nil, :count]])

  # Non-nil cells of one column per group. Pass the name as a String or from a
  # variable: a bare Symbol *literal* handed to a method named `count` is
  # rewritten into a block by the compiled front end before user dispatch.
  -> count(name)
    __build([[Table.normalize_name(name), Table.normalize_name(name), :count]])

  -> sum(name)
    __build([[Table.normalize_name(name), Table.normalize_name(name), :sum]])

  -> mean(name)
    __build([[Table.normalize_name(name), Table.normalize_name(name), :mean]])

  -> min(name)
    __build([[Table.normalize_name(name), Table.normalize_name(name), :min]])

  -> max(name)
    __build([[Table.normalize_name(name), Table.normalize_name(name), :max]])

  -> median(name)
    __build([[Table.normalize_name(name), Table.normalize_name(name), :median]])

  -> product(name)
    __build([[Table.normalize_name(name), Table.normalize_name(name), :product]])

  -> variance(name)
    __build([[Table.normalize_name(name), Table.normalize_name(name), :variance]])

  # agg({:salary => :mean, :bonus => :sum}) — one output column per entry,
  # named after the source column.
  -> agg(specs)
    names = specs.keys
    plan = []
    i = 0
    while i < names.size
      key = Table.normalize_name(names[i])
      plan.push([key, key, specs[names[i]]])
      i += 1
    __build(plan)

  # plan entries are [output name, source column or nil, aggregation]
  -> __build(plan)
    names = @keys.dup
    cols = []
    j = 0
    while j < @keys.size
      col = []
      i = 0
      while i < @labels.size
        if @keys.size == 1
          col.push(@labels[i])
        else
          col.push(@labels[i][j])
        i += 1
      cols.push(col)
      j += 1
    k = 0
    while k < plan.size
      entry = plan[k]
      out_name = entry[0]
      out_name = Table.normalize_name(out_name.to_s + "_agg") if Table.member?(names, out_name)
      names.push(out_name)
      col = []
      i = 0
      while i < @groups.size
        col.push(@groups[i].__agg(entry[1], entry[2]))
        i += 1
      cols.push(col)
      k += 1
    t = Table.build(names, cols, nil)
    t.__set_rows(@labels.size)
    t

  -> to_s
    "TableGroups(" + Table.name_list(@keys) + ": " + @groups.size.to_s + " groups)"

  -> inspect
    to_s
