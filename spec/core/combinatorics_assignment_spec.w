# spec: compiled
# Assignment (core/combinatorics/assignment.w): exact min-cost assignment with an
# LP-duality optimality certificate, checked against brute force over all permutations.

use combinatorics

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

# Brute-force minimum over every injective row -> column map.
-> brute(matrix, row, used, m)
  return 0 if row == matrix.size
  best = nil
  j = 0
  while j < m
    if !used[j]
      used[j] = true
      c = matrix[row][j] + brute(matrix, row + 1, used, m)
      used[j] = false
      best = c if best == nil || c < best
    j += 1
  best

a = Assignment.minimize([[4, 1, 3], [2, 0, 5], [3, 2, 2]])
check("classic 3x3 total", a.total == 5)
check("classic 3x3 certificate", a.verified?)
check("duality gap closes", a.total == a.dual_objective)

neg = Assignment.minimize([[-7, -2], [-3, -9]])
check("negated weights maximise", neg.total == -16 && neg.verified?)

wide = Assignment.minimize([[9, 2, 7, 8], [6, 4, 3, 7], [5, 8, 1, 8]])
check("rectangular 3x4", wide.total == brute([[9, 2, 7, 8], [6, 4, 3, 7], [5, 8, 1, 8]], 0, [false, false, false, false], 4) && wide.verified?)

# Pseudo-random matrices, every one against brute force.
state = 12345
ok = true
trial = 0
while trial < 40
  n = 2 + trial % 4
  m = n + trial % 3
  matrix = []
  i = 0
  while i < n
    row = []
    j = 0
    while j < m
      state = (state * 1103515245 + 12345) % 2147483648
      row.push(state % 41 - 20)
      j += 1
    matrix.push(row)
    i += 1
  r = Assignment.minimize(matrix)
  used = Array.new(m, false)
  ok = false if r.total != brute(matrix, 0, used, m) || !r.verified?
  trial += 1
check("40 random matrices match brute force with valid certificates", ok)

bad = Assignment.minimize([[1, 2], [2, 1]])
raised = false
begin
  Assignment.minimize([[1, 2], [3, 4], [5, 6]])
rescue e
  raised = true
check("more rows than columns is rejected", raised)
