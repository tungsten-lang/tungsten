# Stirling numbers of the second kind

-> stirling2_row(n)
  row = [1]
  i = 1
  while i <= n
    next_row = [0]
    j = 1
    while j < row.size
      next_row.push(j * row[j] + row[j - 1])
      j += 1
    next_row.push(1)
    row = next_row
    i += 1
  row

(0..7).each -> (n)
  << "n=[n]: [stirling2_row(n)]"

## expect stdout
## n=0: [1]
## n=1: [0, 1]
## n=2: [0, 1, 1]
## n=3: [0, 1, 3, 1]
## n=4: [0, 1, 7, 6, 1]
## n=5: [0, 1, 15, 25, 10, 1]
## n=6: [0, 1, 31, 90, 65, 15, 1]
## n=7: [0, 1, 63, 301, 350, 140, 21, 1]
