# Jacobi symbol

-> jacobi(a, n)
  a = a % n
  result = 1
  while a != 0
    while a % 2 == 0
      a /= 2
      r = n % 8
      if r == 3 || r == 5
        result = -result
    tmp = a
    a = n
    n = tmp
    if a % 4 == 3 && n % 4 == 3
      result = -result
    a = a % n
  if n == 1
    result
  else
    0

mods = [1, 3, 5, 7, 9, 11]
mods.each -> (n)
  row = []
  (0..10).each -> (a)
    row.push(jacobi(a, n).to_s)
  joined = row.join(" ")
  << "n=[n]: [joined]"

## expect stdout
## n=1: 1 1 1 1 1 1 1 1 1 1 1
## n=3: 0 1 -1 0 1 -1 0 1 -1 0 1
## n=5: 0 1 -1 -1 1 0 1 -1 -1 1 0
## n=7: 0 1 1 -1 1 -1 -1 0 1 1 -1
## n=9: 0 1 1 0 1 1 0 1 1 0 1
## n=11: 0 1 -1 1 1 1 -1 -1 -1 1 -1
