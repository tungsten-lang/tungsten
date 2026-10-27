# N-queens problem

-> count_n_queens(n)
  cols = []
  i = 0
  while i < n
    cols.push(-1)
    i += 1

  -> safe?(cols, row, col)
    r = 0
    while r < row
      c = cols[r]
      if c == col || c - col == r - row || col - c == r - row
        return false
      r += 1
    true

  -> solve(cols, row, n)
    if row == n
      return 1
    total = 0
    col = 0
    while col < n
      if safe?(cols, row, col)
        cols[row] = col
        total += solve(cols, row + 1, n)
      col += 1
    total

  solve(cols, 0, n)

(1..8).each -> (n)
  << "N=[n]: [count_n_queens(n)] solutions"

## expect stdout
## N=1: 1 solutions
## N=2: 0 solutions
## N=3: 0 solutions
## N=4: 2 solutions
## N=5: 10 solutions
## N=6: 4 solutions
## N=7: 40 solutions
## N=8: 92 solutions
