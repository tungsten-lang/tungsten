# Join — merge operations for DataFrames

in Tungsten:Koala

+ Join
  # Perform a join between two DataFrames.
  #
  #     merged = Join.perform(left, right, on: :id, how: :inner)
  #     merged = Join.perform(left, right, on: [:dept_id, :region], how: :left)
  -> .perform(left, right, on:, how: :inner)
    on = [on] unless on.is_a?(Array)
    on = on.map(&:to_sym)

    # Build index on right side for fast lookup
    right_index = {}
    right.row_count.times -> (i)
      key = on.map(-> (col) right.store[col].to_a[i])
      right_index[key] ||= []
      right_index[key].push(i)

    left_indices  = []
    right_indices = []

    # Scan left side
    left.row_count.times -> (i)
      key = on.map(-> (col) left.store[col].to_a[i])
      matches = right_index[key]

      case how
      => :inner ->
        if matches
          matches.each -> (j)
            left_indices.push(i)
            right_indices.push(j)
      => :left ->
        if matches
          matches.each -> (j)
            left_indices.push(i)
            right_indices.push(j)
        else
          left_indices.push(i)
          right_indices.push(nil)
      => :right ->
        if matches
          matches.each -> (j)
            left_indices.push(i)
            right_indices.push(j)
      => :outer ->
        if matches
          matches.each -> (j)
            left_indices.push(i)
            right_indices.push(j)
        else
          left_indices.push(i)
          right_indices.push(nil)

    # For right/outer joins, add unmatched right rows
    if how == :right || how == :outer
      matched_right = right_indices.reject(&:nil?).to_set
      right.row_count.times -> (j)
        unless matched_right.include?(j)
          left_indices.push(nil)
          right_indices.push(j)

    # Build result columns
    result = {}

    # Left columns
    left.columns.each -> (col)
      left_data = left.store[col].to_a
      result[col] = left_indices.map(-> (i) i ? left_data[i] : nil)

    # Right columns (skip join keys — already included from left)
    right_cols = right.columns.reject(-> (c) on.include?(c))
    right_cols.each -> (col)
      # Suffix if name collision
      result_name = left.columns.include?(col) ? "[col]_right".to_sym : col
      right_data = right.store[col].to_a
      result[result_name] = right_indices.map(-> (j) j ? right_data[j] : nil)

    # Fill join keys from right side for nil left rows (right/outer joins)
    if how == :right || how == :outer
      on.each -> (col)
        left_data  = left.store[col].to_a
        right_data = right.store[col].to_a
        result[col] = left_indices.zip(right_indices).map -> (li, ri)
          li ? left_data[li] : right_data[ri]

    DataFrame.new(**result)
