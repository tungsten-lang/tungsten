use core/linalg

-> expect(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> policy_spec_matrix(rows, columns, salt)
  out = []
  i = 0
  while i < rows
    row = []
    j = 0
    while j < columns
      row.push((((i * 17 + j * 13 + salt) % 7) - 3).to_f)
      j += 1
    out.push(row)
    i += 1
  out

-> policy_spec_reference(a, b, m, k, n)
  out = LinAlg.zeros(m, n)
  i = 0
  while i < m
    j = 0
    while j < n
      sum = ~0.0
      t = 0
      while t < k
        sum += a[i][t] * b[t][j]
        t += 1
      out[i][j] = sum
      j += 1
    i += 1
  out

-> policy_spec_exact?(actual, expected)
  return false if actual.size() != expected.size()
  i = 0
  while i < actual.size()
    return false if actual[i].size() != expected[i].size()
    j = 0
    while j < actual[i].size()
      return false if actual[i][j] != expected[i][j]
      j += 1
    i += 1
  true

expect("linalg.matmul route tiny square", LinAlg.matmul_route(4, 4, 4) == :scalar)
expect("linalg.matmul route below square crossover", LinAlg.matmul_route(7, 7, 7) == :scalar)
expect("linalg.matmul route crossover square", LinAlg.matmul_route(8, 8, 8) == :accelerate)
expect("linalg.matmul route dot", LinAlg.matmul_route(1, 8192, 1) == :scalar)
expect("linalg.matmul route scale", LinAlg.matmul_route(1, 1, 4096) == :scalar)
expect("linalg.matmul route marginal outer", LinAlg.matmul_route(16, 1, 16) == :scalar)
expect("linalg.matmul route outer", LinAlg.matmul_route(32, 1, 32) == :accelerate)
expect("linalg.matmul route narrow outer", LinAlg.matmul_route(2, 1, 128) == :scalar)
expect("linalg.matmul route larger narrow outer", LinAlg.matmul_route(2, 1, 512) == :scalar)
expect("linalg.matmul route marginal row product", LinAlg.matmul_route(1, 48, 48) == :scalar)
expect("linalg.matmul route row product", LinAlg.matmul_route(1, 64, 64) == :accelerate)
expect("linalg.matmul route dot-like row", LinAlg.matmul_route(1, 1024, 4) == :scalar)
expect("linalg.matmul route tall skinny", LinAlg.matmul_route(128, 4, 4) == :accelerate)
expect("linalg.matmul route short wide", LinAlg.matmul_route(4, 4, 128) == :accelerate)
expect("linalg.matmul route long narrow contraction", LinAlg.matmul_route(2, 256, 2) == :scalar)
expect("linalg.matmul route skinny below", LinAlg.matmul_route(4, 16, 4) == :scalar)
expect("linalg.matmul route inner-two below", LinAlg.matmul_route(8, 2, 8) == :scalar)
expect("linalg.matmul route column-two below", LinAlg.matmul_route(96, 2, 2) == :scalar)
expect("linalg.matmul route column-two crossover", LinAlg.matmul_route(128, 2, 2) == :accelerate)

shapes = [[6, 6, 6], [7, 7, 7], [32, 1, 32], [1, 64, 64], [128, 2, 2], [2, 128, 2]]
shape_index = 0
while shape_index < shapes.size()
  shape = shapes[shape_index]
  m = shape[0]
  k = shape[1]
  n = shape[2]
  a = policy_spec_matrix(m, k, 1)
  b = policy_spec_matrix(k, n, 2)
  actual = LinAlg.matmul(a, b)
  expected = policy_spec_reference(a, b, m, k, n)
  expect("linalg.matmul exact " + m.to_s + "x" + k.to_s + "x" + n.to_s, policy_spec_exact?(actual, expected))
  shape_index += 1
