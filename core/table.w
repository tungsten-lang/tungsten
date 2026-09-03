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
    r = start
    while r < records.size
      record = records[r]
      # A trailing newline yields one empty record; drop it rather than
      # inventing a row of nils.
      if record.size == 1 && record[0] == "" && names.size > 1
        r += 1
        next
      j = 0
      while j < names.size
        raw = nil
        if j < record.size
          raw = record[j]
        cols[j].push(Table.parse_field(raw, infer))
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
    s = raw.strip
    return nil if s == ""
    kind = Table.numeric_literal(s)
    return s.to_i if kind == :int
    return s.to_d if kind == :decimal
    raw

  # :int, :decimal or :none — a hand scanner, because String#to_i and
  # String#to_d both answer 0 for a non-numeric string and so cannot be used
  # to decide whether a field is a number at all.
  -> .numeric_literal(s)
    n = s.size
    return :none if n == 0
    i = 0
    lead = s[0]
    if lead == "-" || lead == "+"
      i = 1
    digits = 0
    dots = 0
    while i < n
      ch = s[i]
      if "0123456789".contains?(ch)
        digits += 1
      elsif ch == "."
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
    cols = []
    j = 0
    while j < @names.size
      col = @cols[j]
      out = []
      i = 0
      while i < idxs.size
        out.push(col[idxs[i]])
        i += 1
      cols.push(out)
      j += 1
    labels = nil
    if @index != nil
      labels = []
      i = 0
      while i < idxs.size
        labels.push(@index[idxs[i]])
        i += 1
    t = Table.build(@names.dup, cols, labels)
    t.__set_rows(idxs.size)
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

  # ------------------------------------------------------------- iteration --

  -> each_row(&)
    i = 0
    while i < @rows
      &(row(i))
      i += 1
    self

  -> each(&)
    __each_row(-> (r) &(r))

  -> __each_row(callback)
    i = 0
    while i < @rows
      callback.call(row(i))
      i += 1
    self

  -> map_rows(&)
    __map_rows(-> (r) &(r))

  -> __map_rows(callback)
    out = []
    i = 0
    while i < @rows
      out.push(callback.call(row(i)))
      i += 1
    out

  -> find_row(&)
    __find_row(-> (r) &(r))

  -> __find_row(callback)
    i = 0
    while i < @rows
      candidate = row(i)
      return candidate if Table.truthy?(callback.call(candidate))
      i += 1
    nil

  -> reduce_rows(init, &)
    acc = init
    i = 0
    while i < @rows
      acc = &(acc, row(i))
      i += 1
    acc

  # Rows for which the block is truthy.
  -> where(&)
    __where(-> (r) &(r), true)

  -> filter(&)
    __where(-> (r) &(r), true)

  -> query(&)
    __where(-> (r) &(r), true)

  -> exclude(&)
    __where(-> (r) &(r), false)

  -> __where(callback, keep)
    idxs = []
    i = 0
    while i < @rows
      hit = Table.truthy?(callback.call(row(i)))
      idxs.push(i) if hit == keep
      i += 1
    __rows_at(idxs)

  # ---------------------------------------------------------------- order --

  -> sort_by(key)
    sort_by(key, false)

  -> sort_by(key, descending)
    keys = __key_list(key)
    positions = []
    i = 0
    while i < keys.size
      positions.push(__require(keys[i]))
      i += 1
    decorated = []
    i = 0
    while i < @rows
      cell = []
      j = 0
      while j < positions.size
        cell.push(@cols[positions[j]][i])
        j += 1
      # A unique tiebreak keeps the sort stable. Reversing a run ordered by
      # `n - 1 - i` restores the original order inside equal keys, so the
      # descending sort is stable too.
      if descending
        cell.push(@rows - 1 - i)
      else
        cell.push(i)
      cell.push(i)
      decorated.push(cell)
      i += 1
    ordered = decorated.sort
    ordered = ordered.reverse if descending
    idxs = []
    i = 0
    while i < ordered.size
      cell = ordered[i]
      idxs.push(cell[cell.size - 1])
      i += 1
    __rows_at(idxs)

  # Lexicographic across every column, left to right.
  -> sort
    return self.copy if @names.size == 0
    sort_by(@names.dup, false)

  -> reverse
    idxs = []
    i = @rows - 1
    while i >= 0
      idxs.push(i)
      i -= 1
    __rows_at(idxs)

  # Distinct rows, first occurrence wins.
  -> uniq
    seen = {}
    idxs = []
    i = 0
    while i < @rows
      sig = __row_signature(i)
      if !seen.has_key?(sig)
        seen[sig] = true
        idxs.push(i)
      i += 1
    __rows_at(idxs)

  # Length-prefixed and type-tagged so "1" (String) and 1 (Int) never collide.
  -> __row_signature(i)
    positions = []
    j = 0
    while j < @names.size
      positions.push(j)
      j += 1
    __signature(positions, i)

  -> __signature(positions, i)
    out = ""
    j = 0
    while j < positions.size
      v = @cols[positions[j]][i]
      s = Table.render(v)
      out += type(v) + ":" + s.size.to_s + ":" + s + ";"
      j += 1
    out

  # --------------------------------------------------------------- columns --

  -> map_column(name, &)
    __map_column(name, -> (v) &(v))

  -> __map_column(name, callback)
    pos = __require(name)
    cols = []
    j = 0
    while j < @cols.size
      if j == pos
        out = []
        i = 0
        while i < @rows
          out.push(callback.call(@cols[j][i]))
          i += 1
        cols.push(out)
      else
        cols.push(@cols[j].dup)
      j += 1
    t = Table.build(@names.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  # Add or replace a column from an Array of values (or a scalar, broadcast).
  -> with_column(name, values)
    key = Table.normalize_name(name)
    col = nil
    if type(values) == "Array"
      if values.size != @rows && @names.size > 0
        raise "Table column '" + key.to_s + "' has " + values.size.to_s + " rows, expected " + @rows.to_s
      col = values.dup
    else
      col = []
      i = 0
      while i < @rows
        col.push(values)
        i += 1
    __replace_column(key, col)

  # Add or replace a column computed from each row. Separate from
  # `with_column` on purpose: a two-argument overload whose second form is a
  # block cannot be told apart from the value form on either engine.
  -> compute_column(name, &)
    key = Table.normalize_name(name)
    __replace_column(key, __map_rows(-> (r) &(r)))

  -> __replace_column(key, col)
    names = @names.dup
    cols = []
    j = 0
    while j < @cols.size
      cols.push(@cols[j].dup)
      j += 1
    pos = __pos(key)
    if pos >= 0
      cols[pos] = col
    else
      names.push(key)
      cols.push(col)
    t = Table.build(names, cols, __index_copy)
    t.__set_rows(col.size)
    t

  # Column-wise transform: the block receives (name, values) and returns the
  # replacement Array.
  -> apply(&)
    __apply_columns_block(-> (n, v) &(n, v))

  -> __apply_columns_block(callback)
    cols = []
    j = 0
    while j < @names.size
      out = callback.call(@names[j], @cols[j].dup)
      if type(out) != "Array"
        raise "Table#apply must return an Array for column '" + @names[j].to_s + "', got " + type(out)
      if out.size != @rows
        raise "Table#apply returned " + out.size.to_s + " values for column '" + @names[j].to_s + "', expected " + @rows.to_s
      cols.push(out)
      j += 1
    t = Table.build(@names.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  # Cells for which the block (name, value) is truthy become nil.
  -> mask(&)
    __mask(-> (n, v) &(n, v))

  -> __mask(callback)
    cols = []
    j = 0
    while j < @names.size
      out = []
      i = 0
      while i < @rows
        v = @cols[j][i]
        if Table.truthy?(callback.call(@names[j], v))
          out.push(nil)
        else
          out.push(v)
        i += 1
      cols.push(out)
      j += 1
    t = Table.build(@names.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  -> replace(old, new)
    cols = []
    j = 0
    while j < @names.size
      out = []
      i = 0
      while i < @rows
        v = @cols[j][i]
        if v == old
          out.push(new)
        else
          out.push(v)
        i += 1
      cols.push(out)
      j += 1
    t = Table.build(@names.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  -> copy
    cols = []
    j = 0
    while j < @cols.size
      cols.push(@cols[j].dup)
      j += 1
    t = Table.build(@names.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  # ------------------------------------------------------------- reshaping --

  # New table with `other`'s rows after self's. `other` may be a Table, a row
  # Hash, or an Array of rows.
  -> append(other)
    addition = other
    addition = Table.new([other]) if type(other) == "Hash"
    addition = Table.new(other) if type(other) == "Array"
    if type(addition) != "Table"
      raise "Table#append expects a Table, a Hash row or an Array of rows, got " + type(other)
    names = @names.dup
    i = 0
    other_names = addition.columns
    while i < other_names.size
      names.push(other_names[i]) if !Table.member?(names, other_names[i])
      i += 1
    cols = []
    j = 0
    while j < names.size
      col = []
      if covers?(names[j])
        col = @cols[__pos(names[j])].dup
      else
        k = 0
        while k < @rows
          col.push(nil)
          k += 1
      if addition.covers?(names[j])
        extra = addition.column(names[j])
        k = 0
        while k < extra.size
          col.push(extra[k])
          k += 1
      else
        k = 0
        while k < addition.size
          col.push(nil)
          k += 1
      cols.push(col)
      j += 1
    t = Table.build(names, cols, nil)
    t.__set_rows(@rows + addition.size)
    t

  # The one mutator: push a row (Hash or Array) onto this table in place.
  # Spell it `t.push(row)` or `t.<<(row)`. The infix `t << row` form does not
  # reach a user-defined `<<` on either engine today — both lower it to an
  # addition — so it raises rather than appending.
  -> push(row)
    self.<<(row)

  -> <<(row)
    t = type(row)
    if t == "Hash"
      if @names.size == 0
        keys = row.keys
        i = 0
        while i < keys.size
          @names.push(Table.normalize_name(keys[i]))
          @cols.push([])
          i += 1
      j = 0
      while j < @names.size
        @cols[j].push(Table.lookup(row, @names[j]))
        j += 1
    elsif t == "Array"
      if row.size != @names.size
        raise "Table row has " + row.size.to_s + " values, expected " + @names.size.to_s
      j = 0
      while j < @names.size
        @cols[j].push(row[j])
        j += 1
    else
      raise "Table << expects a Hash or an Array row, got " + t
    @index.push(@rows) if @index != nil
    @rows += 1
    self

  # Columns become rows. The index labels supply the new column names.
  -> transpose
    labels = index
    names = [:column]
    cols = [@names.dup]
    i = 0
    while i < @rows
      names.push(Table.normalize_name(Table.render(labels[i])))
      col = []
      j = 0
      while j < @names.size
        col.push(@cols[j][i])
        j += 1
      cols.push(col)
      i += 1
    t = Table.build(names, cols, nil)
    t.__set_rows(@names.size)
    t

  # 1x1 becomes the cell, one column becomes the Array, one row becomes the
  # row Hash; anything else stays a Table.
  -> squeeze
    return @cols[0][0] if @names.size == 1 && @rows == 1
    return @cols[0].dup if @names.size == 1
    return row(0) if @rows == 1
    self

  # Move values down by n rows (up for a negative n), filling with nil.
  -> shift
    shift(1)

  -> shift(n)
    cols = []
    j = 0
    while j < @names.size
      col = @cols[j]
      out = []
      i = 0
      while i < @rows
        from = i - n
        if from < 0 || from >= @rows
          out.push(nil)
        else
          out.push(col[from])
        i += 1
      cols.push(out)
      j += 1
    t = Table.build(@names.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  # Reorder/expand rows by index label; unknown labels give an all-nil row.
  -> reindex(labels)
    current = index
    at_label = {}
    i = 0
    while i < current.size
      sig = type(current[i]) + ":" + Table.render(current[i])
      at_label[sig] = i if !at_label.has_key?(sig)
      i += 1
    cols = []
    j = 0
    while j < @names.size
      cols.push([])
      j += 1
    i = 0
    while i < labels.size
      sig = type(labels[i]) + ":" + Table.render(labels[i])
      at = -1
      at = at_label[sig] if at_label.has_key?(sig)
      j = 0
      while j < @names.size
        if at < 0
          cols[j].push(nil)
        else
          cols[j].push(@cols[j][at])
        j += 1
      i += 1
    t = Table.build(@names.dup, cols, labels.dup)
    t.__set_rows(labels.size)
    t

  -> with_index(labels)
    t = copy
    t.__set_index_public(labels)
    t

  -> __set_index_public(labels)
    __set_index(labels)

  # Both tables widened to the union of their columns, missing cells nil.
  -> align(other)
    names = @names.dup
    other_names = other.columns
    i = 0
    while i < other_names.size
      names.push(other_names[i]) if !Table.member?(names, other_names[i])
      i += 1
    [__widen(names), other.__widen(names)]

  -> __widen(names)
    cols = []
    j = 0
    while j < names.size
      if covers?(names[j])
        cols.push(@cols[__pos(names[j])].dup)
      else
        col = []
        i = 0
        while i < @rows
          col.push(nil)
          i += 1
        cols.push(col)
      j += 1
    t = Table.build(names.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  # Bucket every n consecutive rows. Numeric columns are aggregated (:mean by
  # default); other columns take the bucket's first value.
  -> resample(n)
    resample(n, :mean)

  -> resample(n, agg)
    raise "Table#resample needs a positive bucket size, got " + n.to_s if n < 1
    names = @names.dup
    cols = []
    j = 0
    while j < names.size
      cols.push([])
      j += 1
    start = 0
    while start < @rows
      stop = start + n
      stop = @rows if stop > @rows
      j = 0
      while j < names.size
        window = []
        i = start
        while i < stop
          window.push(@cols[j][i])
          i += 1
        if Table.numeric_window?(window)
          cols[j].push(Table.reduce_window(window, agg))
        else
          cols[j].push(window[0])
        j += 1
      start = stop
    t = Table.build(names, cols, nil)
    buckets = @rows / n
    buckets += 1 if @rows % n != 0
    t.__set_rows(buckets)
    t

  -> .numeric_window?(window)
    seen = false
    i = 0
    while i < window.size
      if window[i] != nil
        return false if !Table.numeric?(window[i])
        seen = true
      i += 1
    seen

  -> .reduce_window(window, agg)
    values = []
    i = 0
    while i < window.size
      values.push(window[i]) if window[i] != nil
      i += 1
    Table.reduce_values(values, agg)

  -> .reduce_values(values, agg)
    return values.size if agg == :count
    return nil if values.size == 0
    return Table.sum_values(values) if agg == :sum
    return Table.mean_values(values) if agg == :mean
    return Table.min_values(values) if agg == :min
    return Table.max_values(values) if agg == :max
    return Table.product_values(values) if agg == :product
    return Table.median_values(values) if agg == :median
    return Table.variance_values(values) if agg == :variance
    return values[0] if agg == :first
    return values[values.size - 1] if agg == :last
    raise "Unknown aggregation '" + agg.to_s + "'; use sum, mean, min, max, count, product, median, variance, first or last"

  # Fill nil cells in numeric columns: interior gaps linearly, leading and
  # trailing gaps with the nearest known value.
  -> interpolate
    cols = []
    j = 0
    while j < @names.size
      col = @cols[j]
      if __numeric_column?(j)
        cols.push(Table.interpolate_column(col))
      else
        cols.push(col.dup)
      j += 1
    t = Table.build(@names.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  -> .interpolate_column(col)
    out = col.dup
    n = out.size
    i = 0
    while i < n
      if out[i] == nil
        before = i - 1
        while before >= 0 && out[before] == nil
          before -= 1
        after = i + 1
        while after < n && col[after] == nil
          after += 1
        if before < 0 && after >= n
          i += 1
          next
        if before < 0
          out[i] = col[after]
        elsif after >= n
          out[i] = out[before]
        else
          span = after - before
          step = (col[after] - out[before] + 0.to_d) / span
          out[i] = out[before] + step * (i - before)
      i += 1
    out

  # value_name's cells laid out by index_name (rows) and column_name (columns).
  -> pivot(index_name, column_name, value_name)
    ipos = __require(index_name)
    cpos = __require(column_name)
    vpos = __require(value_name)
    row_labels = []
    row_at = {}
    col_labels = []
    col_at = {}
    i = 0
    while i < @rows
      rsig = type(@cols[ipos][i]) + ":" + Table.render(@cols[ipos][i])
      if !row_at.has_key?(rsig)
        row_at[rsig] = row_labels.size
        row_labels.push(@cols[ipos][i])
      csig = type(@cols[cpos][i]) + ":" + Table.render(@cols[cpos][i])
      if !col_at.has_key?(csig)
        col_at[csig] = col_labels.size
        col_labels.push(@cols[cpos][i])
      i += 1
    names = [Table.normalize_name(index_name)]
    cols = [row_labels.dup]
    j = 0
    while j < col_labels.size
      blank = []
      k = 0
      while k < row_labels.size
        blank.push(nil)
        k += 1
      names.push(Table.normalize_name(Table.render(col_labels[j])))
      cols.push(blank)
      j += 1
    i = 0
    while i < @rows
      rsig = type(@cols[ipos][i]) + ":" + Table.render(@cols[ipos][i])
      csig = type(@cols[cpos][i]) + ":" + Table.render(@cols[cpos][i])
      cols[col_at[csig] + 1][row_at[rsig]] = @cols[vpos][i]
      i += 1
    t = Table.build(names, cols, nil)
    t.__set_rows(row_labels.size)
    t

  # ---------------------------------------------------------------- groups --

  -> group_by(key)
    keys = __key_list(key)
    positions = []
    i = 0
    while i < keys.size
      positions.push(__require(keys[i]))
      i += 1
    order = []
    labels = {}
    buckets = {}
    i = 0
    while i < @rows
      sig = __signature(positions, i)
      if !buckets.has_key?(sig)
        buckets[sig] = []
        order.push(sig)
        label = nil
        if positions.size == 1
          label = @cols[positions[0]][i]
        else
          label = []
          j = 0
          while j < positions.size
            label.push(@cols[positions[j]][i])
            j += 1
        labels[sig] = label
      buckets[sig].push(i)
      i += 1
    group_labels = []
    groups = []
    i = 0
    while i < order.size
      group_labels.push(labels[order[i]])
      groups.push(__rows_at(buckets[order[i]]))
      i += 1
    TableGroups.new(keys, group_labels, groups)

  # ----------------------------------------------------------------- joins --

  -> join(other, key)
    join(other, key, :inner)

  -> join(other, key, kind)
    if kind != :inner && kind != :left
      raise "Table#join supports :inner and :left, got " + kind.to_s
    keys = __key_list(key)
    left_pos = []
    right_pos = []
    i = 0
    while i < keys.size
      left_pos.push(__require(keys[i]))
      right_pos.push(other.__require(keys[i]))
      i += 1
    carried = []
    other_names = other.columns
    i = 0
    while i < other_names.size
      carried.push(other_names[i]) if !Table.member?(keys, other_names[i])
      i += 1
    names = @names.dup
    i = 0
    while i < carried.size
      out_name = carried[i]
      out_name = Table.normalize_name(out_name.to_s + "_right") if Table.member?(@names, out_name)
      names.push(out_name)
      i += 1
    right_index = {}
    i = 0
    while i < other.size
      sig = other.__signature(right_pos, i)
      right_index[sig] = [] if !right_index.has_key?(sig)
      right_index[sig].push(i)
      i += 1
    left_rows = []
    right_rows = []
    i = 0
    while i < @rows
      sig = __signature(left_pos, i)
      if right_index.has_key?(sig)
        matches = right_index[sig]
        k = 0
        while k < matches.size
          left_rows.push(i)
          right_rows.push(matches[k])
          k += 1
      elsif kind == :left
        left_rows.push(i)
        right_rows.push(-1)
      i += 1
    cols = []
    j = 0
    while j < @names.size
      col = []
      i = 0
      while i < left_rows.size
        col.push(@cols[j][left_rows[i]])
        i += 1
      cols.push(col)
      j += 1
    j = 0
    while j < carried.size
      source = other.column(carried[j])
      col = []
      i = 0
      while i < right_rows.size
        if right_rows[i] < 0
          col.push(nil)
        else
          col.push(source[right_rows[i]])
        i += 1
      cols.push(col)
      j += 1
    t = Table.build(names, cols, nil)
    t.__set_rows(left_rows.size)
    t

  -> inner_join(other, key)
    join(other, key, :inner)

  -> left_join(other, key)
    join(other, key, :left)

  # ------------------------------------------------------------ statistics --

  -> __numeric_column?(j)
    seen = false
    i = 0
    while i < @rows
      v = @cols[j][i]
      if v != nil
        return false if !Table.numeric?(v)
        seen = true
      i += 1
    seen

  -> numeric_columns
    out = []
    j = 0
    while j < @names.size
      out.push(@names[j]) if __numeric_column?(j)
      j += 1
    out

  -> __values(name)
    pos = __require(name)
    out = []
    i = 0
    while i < @rows
      out.push(@cols[pos][i]) if @cols[pos][i] != nil
      i += 1
    out

  -> __numeric_values(name)
    values = __values(name)
    i = 0
    while i < values.size
      if !Table.numeric?(values[i])
        raise "Table column '" + Table.normalize_name(name).to_s + "' is not numeric"
      i += 1
    values

  # Hash of name => the aggregation applied to every numeric column.
  -> aggregate(agg)
    out = {}
    names = numeric_columns
    i = 0
    while i < names.size
      out[names[i]] = Table.reduce_values(__numeric_values(names[i]), agg)
      i += 1
    out

  -> __agg(name, agg)
    return @rows if name == nil && agg == :count
    Table.reduce_values(__numeric_values(name), agg)

  -> count
    @rows

  -> counts
    out = {}
    j = 0
    while j < @names.size
      out[@names[j]] = counts(@names[j])
      j += 1
    out

  -> counts(name)
    __values(name).size

  -> sum
    aggregate(:sum)

  -> sum(name)
    Table.sum_values(__numeric_values(name))

  -> mean
    aggregate(:mean)

  -> mean(name)
    Table.mean_values(__numeric_values(name))

  -> min
    aggregate(:min)

  -> min(name)
    Table.min_values(__numeric_values(name))

  -> max
    aggregate(:max)

  -> max(name)
    Table.max_values(__numeric_values(name))

  -> median
    aggregate(:median)

  -> median(name)
    Table.median_values(__numeric_values(name))

  -> product
    aggregate(:product)

  -> product(name)
    Table.product_values(__numeric_values(name))

  -> variance
    aggregate(:variance)

  -> variance(name)
    Table.variance_values(__numeric_values(name))

  -> std(name)
    v = variance(name)
    return nil if v == nil
    Math.sqrt(v.to_f)

  # Most frequent value, ties broken by first appearance. Works on any column.
  -> mode
    out = {}
    j = 0
    while j < @names.size
      out[@names[j]] = mode(@names[j])
      j += 1
    out

  -> mode(name)
    values = __values(name)
    return nil if values.size == 0
    order = []
    tally = {}
    i = 0
    while i < values.size
      sig = type(values[i]) + ":" + Table.render(values[i])
      if !tally.has_key?(sig)
        tally[sig] = 0
        order.push(sig)
      tally[sig] = tally[sig] + 1
      i += 1
    best = order[0]
    i = 1
    while i < order.size
      best = order[i] if tally[order[i]] > tally[best]
      i += 1
    i = 0
    while i < values.size
      sig = type(values[i]) + ":" + Table.render(values[i])
      return values[i] if sig == best
      i += 1
    nil

  # q in 0..1, linear interpolation between order statistics.
  -> quantile(q)
    out = {}
    names = numeric_columns
    i = 0
    while i < names.size
      out[names[i]] = quantile(names[i], q)
      i += 1
    out

  -> quantile(name, q)
    values = __numeric_values(name).sort
    return nil if values.size == 0
    n = values.size
    if q <= 0
      return values[0]
    if q >= 1
      return values[n - 1]
    spot = (q + 0.to_d) * (n - 1)
    low = spot.to_i
    high = low + 1
    return values[low] if high >= n
    weight = spot - low
    values[low] + (values[high] - values[low]) * weight

  # 1-based competition ranking: ties share the lowest rank.
  -> rank(name)
    pos = __require(name)
    values = []
    i = 0
    while i < @rows
      values.push(@cols[pos][i])
      i += 1
    ordered = values.dup.sort
    out = []
    i = 0
    while i < values.size
      spot = 0
      k = 0
      while k < ordered.size
        if ordered[k] == values[i]
          spot = k
          k = ordered.size
        else
          k += 1
      out.push(spot + 1)
      i += 1
    out

  -> skew(name)
    values = __numeric_values(name)
    n = values.size
    return nil if n < 3
    m = Table.mean_values(values).to_f
    s2 = 0.0.to_f
    s3 = 0.0.to_f
    i = 0
    while i < n
      d = values[i].to_f - m
      s2 = s2 + d * d
      s3 = s3 + d * d * d
      i += 1
    variance = s2 / (n - 1).to_f
    return nil if variance == 0.0.to_f
    sd = Math.sqrt(variance)
    (n.to_f / ((n - 1).to_f * (n - 2).to_f)) * (s3 / (sd * sd * sd))

  # Excess kurtosis (normal distribution = 0), sample-corrected.
  -> kurtosis(name)
    values = __numeric_values(name)
    n = values.size
    return nil if n < 4
    m = Table.mean_values(values).to_f
    s2 = 0.0.to_f
    s4 = 0.0.to_f
    i = 0
    while i < n
      d = values[i].to_f - m
      s2 = s2 + d * d
      s4 = s4 + d * d * d * d
      i += 1
    variance = s2 / (n - 1).to_f
    return nil if variance == 0.0.to_f
    nf = n.to_f
    scale = (nf * (nf + 1.0.to_f)) / ((nf - 1.0.to_f) * (nf - 2.0.to_f) * (nf - 3.0.to_f))
    tail = (3.0.to_f * (nf - 1.0.to_f) * (nf - 1.0.to_f)) / ((nf - 2.0.to_f) * (nf - 3.0.to_f))
    scale * (s4 / (variance * variance)) - tail

  -> covariance(a, b)
    xs = __numeric_values(a)
    ys = __numeric_values(b)
    if xs.size != ys.size
      raise "Table#covariance needs columns without nil gaps"
    n = xs.size
    return nil if n < 2
    mx = Table.mean_values(xs)
    my = Table.mean_values(ys)
    total = 0.to_d
    i = 0
    while i < n
      total = total + (xs[i] - mx) * (ys[i] - my)
      i += 1
    total / (n - 1)

  -> correlation(a, b)
    cov = covariance(a, b)
    return nil if cov == nil
    sa = std(a)
    sb = std(b)
    return nil if sa == nil || sb == nil
    return nil if sa == 0 || sb == 0
    cov.to_f / (sa * sb)

  # Square matrix over the numeric columns, with a :column label column.
  -> covariance
    __pairwise(:covariance)

  -> correlation
    __pairwise(:correlation)

  -> __pairwise(kind)
    names = numeric_columns
    result_names = [:column]
    cols = [names.dup]
    j = 0
    while j < names.size
      col = []
      i = 0
      while i < names.size
        if kind == :covariance
          col.push(covariance(names[i], names[j]))
        else
          col.push(correlation(names[i], names[j]))
        i += 1
      result_names.push(names[j])
      cols.push(col)
      j += 1
    t = Table.build(result_names, cols, nil)
    t.__set_rows(names.size)
    t

  # Running aggregate down each numeric column (:sum, :product, :min, :max).
  -> cumulative(agg)
    cols = []
    j = 0
    while j < @names.size
      if __numeric_column?(j)
        col = @cols[j]
        out = []
        acc = nil
        i = 0
        while i < @rows
          v = col[i]
          if v == nil
            out.push(acc)
          elsif acc == nil
            acc = v
            out.push(acc)
          else
            acc = Table.combine(acc, v, agg)
            out.push(acc)
          i += 1
        cols.push(out)
      else
        cols.push(@cols[j].dup)
      j += 1
    t = Table.build(@names.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  -> .combine(acc, v, agg)
    return acc + v if agg == :sum
    return acc * v if agg == :product
    if agg == :min
      return v if v < acc
      return acc
    if agg == :max
      return v if v > acc
      return acc
    raise "Unknown cumulative aggregation '" + agg.to_s + "'; use sum, product, min or max"

  # Row-to-row differences in each numeric column; the first n rows are nil.
  -> diff
    diff(1)

  -> diff(n)
    cols = []
    j = 0
    while j < @names.size
      if __numeric_column?(j)
        col = @cols[j]
        out = []
        i = 0
        while i < @rows
          from = i - n
          if from < 0 || from >= @rows || col[i] == nil || col[from] == nil
            out.push(nil)
          else
            out.push(col[i] - col[from])
          i += 1
        cols.push(out)
      else
        cols.push(@cols[j].dup)
      j += 1
    t = Table.build(@names.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  # Numeric columns get equal-width bins (:lower, :upper, :count); anything
  # else gets a frequency table (:value, :count).
  -> histogram(name)
    histogram(name, 10)

  -> histogram(name, bins)
    pos = __require(name)
    if !__numeric_column?(pos)
      return __frequency(pos)
    values = __numeric_values(name)
    if values.size == 0
      t = Table.build([:lower, :upper, :count], [[], [], []], nil)
      return t
    low = Table.min_values(values)
    high = Table.max_values(values)
    span = high - low
    span = 1 if span == 0
    width = (span + 0.to_d) / bins
    lowers = []
    uppers = []
    tally = []
    b = 0
    while b < bins
      lowers.push(low + width * b)
      uppers.push(low + width * (b + 1))
      tally.push(0)
      b += 1
    i = 0
    while i < values.size
      slot = ((values[i] - low + 0.to_d) / width).to_i
      slot = bins - 1 if slot >= bins
      slot = 0 if slot < 0
      tally[slot] = tally[slot] + 1
      i += 1
    t = Table.build([:lower, :upper, :count], [lowers, uppers, tally], nil)
    t.__set_rows(bins)
    t

  -> __frequency(pos)
    order = []
    labels = {}
    tally = {}
    i = 0
    while i < @rows
      v = @cols[pos][i]
      sig = type(v) + ":" + Table.render(v)
      if !tally.has_key?(sig)
        tally[sig] = 0
        labels[sig] = v
        order.push(sig)
      tally[sig] = tally[sig] + 1
      i += 1
    values = []
    counts = []
    i = 0
    while i < order.size
      values.push(labels[order[i]])
      counts.push(tally[order[i]])
      i += 1
    t = Table.build([:value, :count], [values, counts], nil)
    t.__set_rows(order.size)
    t

  # count / mean / min / max for every numeric column, one row per statistic.
  -> describe
    names = numeric_columns
    stats = ["count", "mean", "min", "max"]
    result_names = [:statistic]
    cols = [stats.dup]
    j = 0
    while j < names.size
      values = __numeric_values(names[j])
      col = [values.size, Table.mean_values(values), Table.min_values(values), Table.max_values(values)]
      result_names.push(names[j])
      cols.push(col)
      j += 1
    t = Table.build(result_names, cols, nil)
    t.__set_rows(stats.size)
    t

  -> all
    j = 0
    while j < @names.size
      i = 0
      while i < @rows
        return false if !Table.truthy?(@cols[j][i])
        i += 1
      j += 1
    true

  -> any
    j = 0
    while j < @names.size
      i = 0
      while i < @rows
        return true if Table.truthy?(@cols[j][i])
        i += 1
      j += 1
    false

  # ------------------------------------------------------------- cashflows --

  # Net present value of a cashflow column, one period per row.
  -> npv(rate, name)
    values = __numeric_values(name)
    total = 0.to_d
    discount = 1.to_d
    factor = 1 + rate
    i = 0
    while i < values.size
      total = total + values[i] / discount
      discount = discount * factor
      i += 1
    total

  # Internal rate of return: the rate where npv is zero. Bisection on
  # (-0.999999, 100), nil when the cashflows never change sign.
  -> irr(name)
    values = __numeric_values(name)
    return nil if !Table.signs_change?(values)
    low = -0.999999.to_f
    high = 100.0.to_f
    i = 0
    while i < 200
      mid = (low + high) / 2.0.to_f
      if Table.npv_at(values, mid) > 0.0.to_f
        low = mid
      else
        high = mid
      i += 1
    (low + high) / 2.0.to_f

  # Cashflows dated by day offsets, discounted on a 365-day year.
  -> xnpv(rate, name, days_name)
    values = __numeric_values(name)
    days = __numeric_values(days_name)
    if values.size != days.size
      raise "Table#xnpv needs value and day columns of equal length"
    Table.xnpv_at(values, days, rate.to_f)

  -> xirr(name, days_name)
    values = __numeric_values(name)
    days = __numeric_values(days_name)
    return nil if !Table.signs_change?(values)
    low = -0.999999.to_f
    high = 100.0.to_f
    i = 0
    while i < 200
      mid = (low + high) / 2.0.to_f
      if Table.xnpv_at(values, days, mid) > 0.0.to_f
        low = mid
      else
        high = mid
      i += 1
    (low + high) / 2.0.to_f

  -> .signs_change?(values)
    positive = false
    negative = false
    i = 0
    while i < values.size
      positive = true if values[i] > 0
      negative = true if values[i] < 0
      i += 1
    positive && negative

  -> .npv_at(values, rate)
    total = 0.0.to_f
    discount = 1.0.to_f
    factor = 1.0.to_f + rate
    i = 0
    while i < values.size
      total = total + values[i].to_f / discount
      discount = discount * factor
      i += 1
    total

  -> .xnpv_at(values, days, rate)
    total = 0.0.to_f
    base = 1.0.to_f + rate
    start = days[0].to_f
    i = 0
    while i < values.size
      years = (days[i].to_f - start) / 365.0.to_f
      total = total + values[i].to_f / Math.exp(years * Math.log(base))
      i += 1
    total

  # -------------------------------------------------- column-wise reducers --

  -> .sum_values(values)
    return 0 if values.size == 0
    total = values[0]
    i = 1
    while i < values.size
      total = total + values[i]
      i += 1
    total

  -> .product_values(values)
    return 1 if values.size == 0
    total = values[0]
    i = 1
    while i < values.size
      total = total * values[i]
      i += 1
    total

  # Exact where the language is: the accumulator starts as a Decimal so an Int
  # column never falls into integer division.
  -> .mean_values(values)
    return nil if values.size == 0
    total = 0.to_d
    i = 0
    while i < values.size
      total = total + values[i]
      i += 1
    total / values.size

  -> .min_values(values)
    return nil if values.size == 0
    best = values[0]
    i = 1
    while i < values.size
      best = values[i] if values[i] < best
      i += 1
    best

  -> .max_values(values)
    return nil if values.size == 0
    best = values[0]
    i = 1
    while i < values.size
      best = values[i] if values[i] > best
      i += 1
    best

  -> .median_values(values)
    return nil if values.size == 0
    sorted = values.dup.sort
    n = sorted.size
    return sorted[n / 2] if n % 2 == 1
    (sorted[n / 2 - 1] + sorted[n / 2] + 0.to_d) / 2

  -> .variance_values(values)
    n = values.size
    return nil if n < 2
    m = Table.mean_values(values)
    total = 0.to_d
    i = 0
    while i < n
      d = values[i] - m
      total = total + d * d
      i += 1
    total / (n - 1)

  # ------------------------------------------------------------ arithmetic --

  -> +(other)
    __elementwise(other, :add)

  -> -(other)
    __elementwise(other, :subtract)

  -> *(other)
    __elementwise(other, :multiply)

  -> /(other)
    __elementwise(other, :divide)

  -> %(other)
    __elementwise(other, :mod)

  -> add(other)
    __elementwise(other, :add)

  -> subtract(other)
    __elementwise(other, :subtract)

  -> multiply(other)
    __elementwise(other, :multiply)

  -> divide(other)
    __elementwise(other, :divide)

  -> mod(other)
    __elementwise(other, :mod)

  # A scalar applies to every numeric cell; a Table applies cell by cell and
  # must have the same column names in the same order and the same row count.
  -> __elementwise(other, op)
    scalar = type(other) != "Table"
    if scalar
      if !Table.numeric?(other)
        raise "Table arithmetic needs a number or a Table on the right, got " + type(other)
    else
      if other.columns != @names
        raise "Table arithmetic needs matching columns: " + Table.name_list(@names) + " vs " + Table.name_list(other.columns)
      if other.size != @rows
        raise "Table arithmetic needs matching row counts: " + @rows.to_s + " vs " + other.size.to_s
    cols = []
    j = 0
    while j < @names.size
      col = @cols[j]
      right = nil
      right = other.column(@names[j]) if !scalar
      out = []
      i = 0
      while i < @rows
        left = col[i]
        rv = other
        rv = right[i] if !scalar
        if left == nil || rv == nil || !Table.numeric?(left) || !Table.numeric?(rv)
          out.push(left)
        else
          out.push(Table.apply_op(left, rv, op))
        i += 1
      cols.push(out)
      j += 1
    t = Table.build(@names.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  -> .apply_op(a, b, op)
    return a + b if op == :add
    return a - b if op == :subtract
    return a * b if op == :multiply
    return a / b if op == :divide
    return a % b if op == :mod
    raise "Unknown Table operation '" + op.to_s + "'"

  # Matrix product: self's numeric columns against other's numeric rows. The
  # result's columns are other's.
  -> dot(other)
    left = numeric_columns
    right = other.columns
    if left.size != other.size
      raise "Table#dot needs " + left.size.to_s + " rows on the right, got " + other.size.to_s
    cols = []
    j = 0
    while j < right.size
      rc = other.column(right[j])
      col = []
      i = 0
      while i < @rows
        total = 0
        k = 0
        while k < left.size
          total = total + at(i, left[k]) * rc[k]
          k += 1
        col.push(total)
        i += 1
      cols.push(col)
      j += 1
    t = Table.build(right.dup, cols, __index_copy)
    t.__set_rows(@rows)
    t

  # --------------------------------------------------------------- export --

  -> to_a
    out = []
    i = 0
    while i < @rows
      out.push(row(i))
      i += 1
    out

  -> to_records
    to_a

  -> to_h
    out = {}
    j = 0
    while j < @names.size
      out[@names[j]] = @cols[j].dup
      j += 1
    out

  -> to_csv
    to_csv(",")

  -> to_csv(separator)
    out = ""
    j = 0
    while j < @names.size
      out += separator if j > 0
      out += Table.csv_field(@names[j].to_s, separator)
      j += 1
    out += "\n"
    i = 0
    while i < @rows
      j = 0
      while j < @names.size
        out += separator if j > 0
        out += Table.csv_field(Table.render(@cols[j][i]), separator)
        j += 1
      out += "\n"
      i += 1
    out

  -> .csv_field(s, separator)
    needs = false
    needs = true if s.contains?(separator)
    needs = true if s.contains?("\"")
    needs = true if s.contains?("\n")
    needs = true if s.contains?("\r")
    return s if !needs
    out = "\""
    i = 0
    while i < s.size
      ch = s[i]
      out += "\"" if ch == "\""
      out += ch
      i += 1
    out + "\""

  -> to_json
    out = "\["
    i = 0
    while i < @rows
      out += "," if i > 0
      out += "{"
      j = 0
      while j < @names.size
        out += "," if j > 0
        out += Table.json_string(@names[j].to_s) + ":" + Table.json_value(@cols[j][i])
        j += 1
      out += "}"
      i += 1
    out + "\]"

  -> .json_value(v)
    return "null" if v == nil
    return "true" if v == true
    return "false" if v == false
    return v.to_s if Table.numeric?(v)
    Table.json_string(v.to_s)

  -> .json_string(s)
    out = "\""
    i = 0
    while i < s.size
      ch = s[i]
      if ch == "\""
        out += "\\\""
      elsif ch == "\\"
        out += "\\\\"
      elsif ch == "\n"
        out += "\\n"
      elsif ch == "\r"
        out += "\\r"
      elsif ch == "\t"
        out += "\\t"
      else
        out += ch
      i += 1
    out + "\""

  -> to_html
    out = "<table>\n  <thead>\n    <tr>"
    j = 0
    while j < @names.size
      out += "<th>" + Table.xml_escape(@names[j].to_s) + "</th>"
      j += 1
    out += "</tr>\n  </thead>\n  <tbody>\n"
    i = 0
    while i < @rows
      out += "    <tr>"
      j = 0
      while j < @names.size
        out += "<td>" + Table.xml_escape(Table.render(@cols[j][i])) + "</td>"
        j += 1
      out += "</tr>\n"
      i += 1
    out + "  </tbody>\n</table>"

  -> to_xml
    to_xml("row")

  -> to_xml(row_tag)
    out = "<table>\n"
    i = 0
    while i < @rows
      out += "  <" + row_tag + ">\n"
      j = 0
      while j < @names.size
        tag = @names[j].to_s
        out += "    <" + tag + ">" + Table.xml_escape(Table.render(@cols[j][i])) + "</" + tag + ">\n"
        j += 1
      out += "  </" + row_tag + ">\n"
      i += 1
    out + "</table>"

  -> .xml_escape(s)
    out = ""
    i = 0
    while i < s.size
      ch = s[i]
      if ch == "&"
        out += "&amp;"
      elsif ch == "<"
        out += "&lt;"
      elsif ch == ">"
        out += "&gt;"
      else
        out += ch
      i += 1
    out

  # One INSERT statement per row. Strings are single-quoted with doubled
  # quotes; no connection is opened.
  -> to_sql(table_name)
    out = ""
    i = 0
    while i < @rows
      out += "INSERT INTO " + table_name + " ("
      j = 0
      while j < @names.size
        out += ", " if j > 0
        out += @names[j].to_s
        j += 1
      out += ") VALUES ("
      j = 0
      while j < @names.size
        out += ", " if j > 0
        out += Table.sql_value(@cols[j][i])
        j += 1
      out += ");\n"
      i += 1
    out

  -> .sql_value(v)
    return "NULL" if v == nil
    return v.to_s if Table.numeric?(v)
    return "TRUE" if v == true
    return "FALSE" if v == false
    s = v.to_s
    out = "'"
    i = 0
    while i < s.size
      ch = s[i]
      out += "'" if ch == "'"
      out += ch
      i += 1
    out + "'"

  # -------------------------------------------------------------- printing --

  -> to_s
    return "(0 rows, 0 columns)" if @names.size == 0
    labels = []
    raw = index
    i = 0
    while i < @rows
      labels.push(Table.render(raw[i]))
      i += 1
    label_width = 1
    i = 0
    while i < labels.size
      label_width = labels[i].size if labels[i].size > label_width
      i += 1
    widths = []
    right = []
    cells = []
    j = 0
    while j < @names.size
      w = @names[j].to_s.size
      column_cells = []
      i = 0
      while i < @rows
        s = Table.render(@cols[j][i])
        w = s.size if s.size > w
        column_cells.push(s)
        i += 1
      widths.push(w)
      right.push(__numeric_column?(j))
      cells.push(column_cells)
      j += 1
    line = "#".rpad(label_width)
    j = 0
    while j < @names.size
      if right[j]
        line += " | " + @names[j].to_s.lpad(widths[j])
      else
        line += " | " + @names[j].to_s.rpad(widths[j])
      j += 1
    out = Table.trim_right(line)
    line = Table.dashes(label_width)
    j = 0
    while j < @names.size
      line += "-+-" + Table.dashes(widths[j])
      j += 1
    out += "\n" + line
    i = 0
    while i < @rows
      line = labels[i].rpad(label_width)
      j = 0
      while j < @names.size
        if right[j]
          line += " | " + cells[j][i].lpad(widths[j])
        else
          line += " | " + cells[j][i].rpad(widths[j])
        j += 1
      out += "\n" + Table.trim_right(line)
      i += 1
    out

  -> .dashes(n)
    out = ""
    i = 0
    while i < n
      out += "-"
      i += 1
    out

  -> .trim_right(s)
    stop = s.size
    while stop > 0 && s[stop - 1] == " "
      stop -= 1
    return s if stop == s.size
    out = ""
    i = 0
    while i < stop
      out += s[i]
      i += 1
    out

  -> inspect
    to_s + "\n(" + @rows.to_s + " rows, " + @names.size.to_s + " columns)"

  # ------------------------------------------------------------- equality --

  -> ==(other)
    return false if type(other) != "Table"
    return false if other.columns != @names
    return false if other.size != @rows
    j = 0
    while j < @names.size
      mine = @cols[j]
      theirs = other.column(@names[j])
      i = 0
      while i < @rows
        return false if mine[i] != theirs[i]
        i += 1
      j += 1
    true

  -> eql?(other)
    self == other


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
