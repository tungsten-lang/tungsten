# Exact minimum-cost assignment (the Hungarian method, shortest augmenting paths).
#
# Given an integer cost matrix with `rows` rows and `columns` columns, rows <= columns,
# assign every row to a distinct column so the total cost is least. Costs are exact
# integers (BigInt-safe: no floating point anywhere), so the result carries an exact
# LP-duality certificate: row potentials u and column potentials v with
#
#     u[i] + v[j] <= cost[i][j]      for every cell          (dual feasibility)
#     u[i] + v[j] == cost[i][j]      for every assigned cell (complementary slackness)
#
# and then  sum(cost of assigned cells) == sum(u) + sum(v),  which proves optimality
# independently of the search that produced it. `verified?` re-checks exactly this.
#
# To maximise a weight, pass negated weights. To let a row stay unmatched at some
# price, add one private "stay" column per row with that price.
#
# Complexity is O(rows * rows * columns) with O(rows + columns) extra space beyond the
# matrix.

+ Assignment
  ro :cost_matrix, :assigned, :row_potential, :column_potential

  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .validate(matrix)
    raise "assignment needs a non-empty matrix" if matrix.size == 0
    width = matrix[0].size
    raise "assignment needs at least as many columns as rows" if width < matrix.size
    matrix.each ->(row)
      raise "assignment matrix must be rectangular" if row.size != width
      row.each ->(c)
        raise "assignment costs must be integers" if !Assignment.integer?(c)

  # Minimum-cost assignment of every row to a distinct column.
  -> .minimize(matrix)
    Assignment.validate(matrix)
    n = matrix.size
    m = matrix[0].size
    u = Array.new(n + 1, 0)
    v = Array.new(m + 1, 0)
    owner = Array.new(m + 1, 0)       # owner[j] = 1-based row matched to column j, 0 = free
    way = Array.new(m + 1, 0)
    row = 1
    while row <= n
      owner[0] = row
      j0 = 0
      minv = Array.new(m + 1, nil)    # nil = +infinity
      used = Array.new(m + 1, false)
      searching = true
      while searching
        used[j0] = true
        i0 = owner[j0]
        delta = nil
        j1 = 0
        j = 1
        while j <= m
          if !used[j]
            cur = matrix[i0 - 1][j - 1] - u[i0] - v[j]
            if minv[j] == nil || cur < minv[j]
              minv[j] = cur
              way[j] = j0
            if delta == nil || minv[j] < delta
              delta = minv[j]
              j1 = j
          j += 1
        j = 0
        while j <= m
          if used[j]
            u[owner[j]] = u[owner[j]] + delta
            v[j] = v[j] - delta
          else
            minv[j] = minv[j] - delta if minv[j] != nil
          j += 1
        j0 = j1
        searching = false if owner[j0] == 0
      while j0 != 0
        j1 = way[j0]
        owner[j0] = owner[j1]
        j0 = j1
      row += 1
    assigned = Array.new(n, -1)
    j = 1
    while j <= m
      assigned[owner[j] - 1] = j - 1 if owner[j] != 0
      j += 1
    Assignment.new(matrix, assigned, u.drop(1), v.drop(1))

  -> new(@cost_matrix, @assigned, @row_potential, @column_potential)

  -> size
    @assigned.size

  # Total cost of the assignment.
  -> total
    sum = 0
    i = 0
    while i < @assigned.size
      sum += @cost_matrix[i][@assigned[i]]
      i += 1
    sum

  # Dual objective sum(u) + sum(v); equals `total` exactly when the assignment is optimal.
  -> dual_objective
    sum = 0
    @row_potential.each ->(x) sum += x
    @column_potential.each ->(x) sum += x
    sum

  # Re-check the optimality certificate from scratch. Returns true or raises.
  -> verified?
    n = @cost_matrix.size
    m = @cost_matrix[0].size
    seen = Array.new(m, false)
    i = 0
    while i < n
      j = @assigned[i]
      raise "row [i] is unassigned" if j < 0
      raise "column [j] assigned twice" if seen[j]
      seen[j] = true
      raise "slackness fails at ([i], [j])" if @row_potential[i] + @column_potential[j] != @cost_matrix[i][j]
      k = 0
      while k < m
        raise "dual infeasible at ([i], [k])" if @row_potential[i] + @column_potential[k] > @cost_matrix[i][k]
        k += 1
      i += 1
    raise "duality gap: total [total] != dual [dual_objective]" if total != dual_objective
    true
