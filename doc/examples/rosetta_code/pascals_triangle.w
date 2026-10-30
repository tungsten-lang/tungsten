# Pascal's triangle

-> pascals_triangle(rows)
  row = [1]
  r = 0
  while r < rows
    << row.join(" ")
    next_row = [1]
    i = 0
    while i < row.size - 1
      next_row.push(row[i] + row[i + 1])
      i += 1
    next_row.push(1)
    row = next_row
    r += 1

pascals_triangle(8)

## expect stdout
## 1
## 1 1
## 1 2 1
## 1 3 3 1
## 1 4 6 4 1
## 1 5 10 10 5 1
## 1 6 15 20 15 6 1
## 1 7 21 35 35 21 7 1
