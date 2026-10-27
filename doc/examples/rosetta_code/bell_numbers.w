# Bell numbers

-> bell_numbers(count)
  if count <= 0
    return []
  result = [1]
  row = [1]
  i = 1
  while i < count
    next_row = [row[row.size - 1]]
    j = 0
    while j < row.size
      next_row.push(next_row[j] + row[j])
      j += 1
    result.push(next_row[0])
    row = next_row
    i += 1
  result

<< bell_numbers(15)

## expect stdout
## [1, 1, 2, 5, 15, 52, 203, 877, 4140, 21147, 115975, 678570, 4213597, 27644437, 190899322]
