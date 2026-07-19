# Join — merge two DataFrames on a key column
#
#     Join.inner(left, right, :id)
#     left.join(right, :id)            # inner join
#     left.join(right, :id, :left)     # left join
#
# v1: single-column key, :inner and :left only. Result columns are the
# left frame's columns in order, then the right frame's columns except
# the key; a right column whose name collides with a left column is
# suffixed "_right". A left join fills nil into right columns for
# unmatched left rows. Matching is a linear scan (fine for small frames,
# same trade-off as GroupBy).
+ Join
  # Inner join: one result row per (left row, matching right row) pair.
  -> .inner(left, right, key)
    self.perform(left, right, key, :inner)

  # Left join: every left row appears; unmatched right cells are nil.
  -> .left(left, right, key)
    self.perform(left, right, key, :left)

  -> .perform(left, right, key, how)
    left_keys = left.column_values(key)
    right_keys = right.column_values(key)
    keep_unmatched = how == :left

    left_idx = []
    right_idx = []   # nil marks an unmatched left row (left join)
    i = 0
    left_keys.each -> (k)
      matched = false
      j = 0
      right_keys.each -> (rk)
        if rk == k
          left_idx.push(i)
          right_idx.push(j)
          matched = true
        j += 1
      if !matched && keep_unmatched
        left_idx.push(i)
        right_idx.push(nil)
      i += 1

    pairs = []
    left_names = left.column_names
    left_names.each -> (n)
      vals = left.column_values(n)
      picked = []
      left_idx.each -> (li)
        picked.push(vals[li])
      pairs.push([n, picked])

    right.column_names.each -> (n)
      if n != key
        vals = right.column_values(n)
        picked = []
        right_idx.each -> (rj)
          if rj == nil
            picked.push(nil)
          else
            picked.push(vals[rj])
        label = n
        label = "[n]_right" if left_names.include?(n)
        pairs.push([label, picked])

    DataFrame.new(pairs)
