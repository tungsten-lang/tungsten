# Stirling numbers of the first kind

-> stirling1_row(n)
  row = [1]
  i = 1
  while i <= n
    next_row = [0]
    j = 1
    while j < row.size
      next_row.push(row[j - 1] + (i - 1) * row[j])
      j += 1
    next_row.push(1)
    row = next_row
    i += 1
  row

(0..7).each -> (n)
  << "n=[n]: [stirling1_row(n)]"

## expect stdout
## n=0: [1]
## n=1: [0, 1]
## n=2: [0, 1, 1]
## n=3: [0, 2, 3, 1]
## n=4: [0, 6, 11, 6, 1]
## n=5: [0, 24, 50, 35, 10, 1]
## n=6: [0, 120, 274, 225, 85, 15, 1]
## n=7: [0, 720, 1764, 1624, 735, 175, 21, 1]
