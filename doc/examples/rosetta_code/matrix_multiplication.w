# Matrix multiplication

-> mat_mul(a, b)
  rows_a = a.length
  cols_a = a[0].length
  cols_b = b[0].length
  result = []
  i = 0
  while i < rows_a
    row = []
    j = 0
    while j < cols_b
      sum = 0
      k = 0
      while k < cols_a
        sum += a[i][k] * b[k][j]
        k += 1
      row.push(sum)
      j += 1
    result.push(row)
    i += 1
  result

a = [[1, 2], [3, 4]]
b = [[5, 6], [7, 8]]
result = mat_mul(a, b)
result.each { |row| puts row }

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten matrix_multiplication.w`
## expect stdout
## [19, 22]
## [43, 50]
