+ Table
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
    if positions.size == 1 && @rows > 0 && @rows <= 65536 && type(@cols[positions[0]][0]) == "Int"
      col = @cols[positions[0]] ## Array
      packed = []
      ok = true
      i = 0
      while i < @rows
        v = col[i]
        if type(v) != "Int" || v < -1_000_000_000 || v > 1_000_000_000
          ok = false
          break
        vi = v ## i64
        if descending
          packed.push((-vi) * 65536 + i)
        else
          packed.push(vi * 65536 + i)
        i += 1
      if ok
        ordered_p = packed.sort ## Array
        idxs = []
        i = 0
        while i < @rows
          oi = ordered_p[i] ## i64
          idxs.push(oi & 65535)
          i += 1
        return __rows_at(idxs)
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
    if positions.size == 1
      col = @cols[positions[0]] ## Array
      group_labels = []
      bucket_list = []
      buckets = {}
      i = 0
      while i < @rows
        v = col[i]
        b = buckets[v]
        if b == nil
          b = [i]
          buckets[v] = b
          group_labels.push(v)
          bucket_list.push(b)
        else
          ba = b ## Array
          ba.push(i)
        i += 1
      groups = []
      i = 0
      while i < bucket_list.size
        groups.push(__rows_at(bucket_list[i]))
        i += 1
      return TableGroups.new(keys, group_labels, groups)
    order = []
    labels = {}
    buckets = {}
    i = 0
    while i < @rows
      sig = __signature(positions, i)
      b = buckets[sig]
      if b == nil
        b = [i]
        buckets[sig] = b
        order.push(sig)
        label = []
        j = 0
        while j < positions.size
          label.push(@cols[positions[j]][i])
          j += 1
        labels[sig] = label
      else
        ba = b ## Array
        ba.push(i)
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
    left_rows = []
    right_rows = []
    if keys.size == 1
      lcol = @cols[left_pos[0]] ## Array
      rcol = other.column(keys[0]) ## Array
      rsize = other.size
      i = 0
      while i < rsize
        v = rcol[i]
        b = right_index[v]
        if b == nil
          right_index[v] = [i]
        else
          ba = b ## Array
          ba.push(i)
        i += 1
      i = 0
      while i < @rows
        v = lcol[i]
        matches = right_index[v]
        if matches != nil
          m_arr = matches ## Array
          msize = m_arr.size
          k = 0
          while k < msize
            left_rows.push(i)
            right_rows.push(m_arr[k])
            k += 1
        elsif kind == :left
          left_rows.push(i)
          right_rows.push(-1)
        i += 1
    else
      i = 0
      while i < other.size
        sig = other.__signature(right_pos, i)
        b = right_index[sig]
        if b == nil
          right_index[sig] = [i]
        else
          ba = b ## Array
          ba.push(i)
        i += 1
      i = 0
      while i < @rows
        sig = __signature(left_pos, i)
        matches = right_index[sig]
        if matches != nil
          m_arr = matches ## Array
          k = 0
          while k < m_arr.size
            left_rows.push(i)
            right_rows.push(m_arr[k])
            k += 1
        elsif kind == :left
          left_rows.push(i)
          right_rows.push(-1)
        i += 1
    n_left = left_rows.size
    cols = []
    j = 0
    while j < @names.size
      src_col = @cols[j] ## Array
      col = []
      i = 0
      while i < n_left
        col.push(src_col[left_rows[i]])
        i += 1
      cols.push(col)
      j += 1
    j = 0
    while j < carried.size
      source = other.column(carried[j]) ## Array
      col = []
      i = 0
      while i < n_left
        ri = right_rows[i] ## i64
        if ri < 0
          col.push(nil)
        else
          col.push(source[ri])
        i += 1
      cols.push(col)
      j += 1
    t = Table.build(names, cols, nil)
    t.__set_rows(n_left)
    t

  -> inner_join(other, key)
    join(other, key, :inner)

  -> left_join(other, key)
    join(other, key, :left)

