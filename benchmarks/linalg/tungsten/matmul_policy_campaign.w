# Shape sweep for the nested-list LinAlg.matmul routing policy.
#
# Build once and compare the exact same operands through the scalar reference,
# staged Accelerate dgemm, and public auto-routed implementations:
#   matmul_policy_campaign oracle M K N
#   matmul_policy_campaign scalar M K N ITERATIONS
#   matmul_policy_campaign blas   M K N ITERATIONS
#   matmul_policy_campaign auto   M K N ITERATIONS

use core/linalg

-> policy_matrix(rows, columns, salt)
  out = []
  i = 0
  while i < rows
    row = []
    j = 0
    while j < columns
      # Small integral f64 values make the scalar and BLAS reductions exactly
      # comparable: every product and every tested sum is exactly representable.
      value = ((i * 17 + j * 13 + salt) % 7) - 3
      row.push(value.to_f)
      j += 1
    out.push(row)
    i += 1
  out

-> policy_scalar(a, b, m, k, n)
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

-> policy_blas(a, b, m, k, n)
  fa = ccall("w_array_new_aligned", -64, m * k)
  i = 0
  while i < m
    row = a[i]
    base = i * k
    j = 0
    while j < k
      fa[base + j] = row[j] + ~0.0
      j += 1
    i += 1

  fb = ccall("w_array_new_aligned", -64, k * n)
  i = 0
  while i < k
    row = b[i]
    base = i * n
    j = 0
    while j < n
      fb[base + j] = row[j] + ~0.0
      j += 1
    i += 1

  fc = ccall("w_array_new_aligned", -64, m * n)
  ccall("w_blas_dgemm_nn", fa, fb, fc, m, n, k)
  out = []
  i = 0
  while i < m
    row = []
    base = i * n
    j = 0
    while j < n
      row.push(fc[base + j])
      j += 1
    out.push(row)
    i += 1
  out

-> policy_checksum(matrix)
  sum = ~0.0
  i = 0
  while i < matrix.size()
    row = matrix[i]
    j = 0
    while j < row.size()
      sum += row[j]
      j += 1
    i += 1
  sum

-> policy_assert_exact(actual, expected, m, n)
  i = 0
  while i < m
    j = 0
    while j < n
      if actual[i][j] != expected[i][j]
        raise "matmul mismatch at " + i.to_s + "," + j.to_s + ": " + actual[i][j].to_s + " != " + expected[i][j].to_s
      j += 1
    i += 1
  true

mode = ARGV[0]
raise "mode required" if mode == nil
m = ARGV[1].to_i
k = ARGV[2].to_i
n = ARGV[3].to_i
iterations = ARGV[4] == nil ? 1 : ARGV[4].to_i
raise "positive dimensions required" if m <= 0 || k <= 0 || n <= 0
raise "positive iterations required" if iterations <= 0

a = policy_matrix(m, k, 1)
b = policy_matrix(k, n, 2)

if mode == "oracle"
  reference = policy_scalar(a, b, m, k, n)
  accelerated = policy_blas(a, b, m, k, n)
  automatic = LinAlg.matmul(a, b)
  policy_assert_exact(accelerated, reference, m, n)
  policy_assert_exact(automatic, reference, m, n)
  << "ORACLE_OK m=" + m.to_s + " k=" + k.to_s + " n=" + n.to_s + " checksum=" + policy_checksum(reference).to_s
else
  result = nil
  # Warm all runtime and Accelerate initialization before timing.
  if mode == "scalar"
    result = policy_scalar(a, b, m, k, n)
  elsif mode == "blas"
    result = policy_blas(a, b, m, k, n)
  elsif mode == "auto"
    result = LinAlg.matmul(a, b)
  else
    raise "unknown mode: " + mode
  end

  started = clock()
  i = 0
  while i < iterations
    if mode == "scalar"
      result = policy_scalar(a, b, m, k, n)
    elsif mode == "blas"
      result = policy_blas(a, b, m, k, n)
    else
      result = LinAlg.matmul(a, b)
    end
    i += 1
  elapsed = clock() - started
  ns = elapsed * ~1000000000.0 / iterations
  << "MATMUL_POLICY mode=" + mode + " m=" + m.to_s + " k=" + k.to_s + " n=" + n.to_s + " iterations=" + iterations.to_s + " ns=" + ns.round(1).to_s + " checksum=" + policy_checksum(result).to_s
end
