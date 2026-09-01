# Focused correctness and performance probes for the perf30 dense campaign.
#
# Compile once per revision, then select a mode:
#   dense_tensor_campaign cpu-ops
#   dense_tensor_campaign view-oracle
#   dense_tensor_campaign metadata [iterations]
#   dense_tensor_campaign view-matmul [iterations]
#   dense_tensor_campaign unary [iterations]
#   dense_tensor_campaign reductions [iterations]
#   dense_tensor_campaign axis-reductions [iterations]
#   dense_tensor_campaign blas1-scalar [iterations]
#   dense_tensor_campaign blas1-native [iterations]
#   dense_tensor_campaign blas2-scalar [iterations]
#   dense_tensor_campaign blas2-native [iterations]

use core/blas
use core/tensor

-> assert_close(actual, expected, label)
  delta = actual - expected
  delta = ~0.0 - delta if delta < ~0.0
  raise label + ": got " + actual.to_s + ", expected " + expected.to_s if delta > ~0.00001

-> filled_tensor(rows, cols, dtype)
  data = dtype == Tensor.f64 ? f64_array(rows * cols) : f32_array(rows * cols)
  i = 0
  while i < rows * cols
    data[i] = ((i % 97) + 1).to_f / ~97.0
    i += 1
  Tensor.wrap_cpu(data, dtype, [rows, cols], [cols, 1], 0)

-> scalar_dot_f64(a, b, n)
  total = ~0.0
  i = 0
  while i < n
    total += a[i] * b[i]
    i += 1
  total

-> scalar_gemv_f64(a, x, y, rows, cols)
  i = 0
  while i < rows
    total = ~0.0
    j = 0
    while j < cols
      total += a[i * cols + j] * x[j]
      j += 1
    y[i] = total
    i += 1
  y

mode = ARGV[0]
raise "mode required" if mode == nil

if mode == "cpu-ops"
  x = filled_tensor(2, 3, Tensor.f64)
  scaled = x.scale(~2.0)
  assert_close(scaled.at([1, 2]), ~12.0 / ~97.0, "scale")
  root = scaled.sqrt
  assert_close(root.at([0, 0]), Math.sqrt(~2.0 / ~97.0), "sqrt")
  sums = x.sum_axis(1)
  assert_close(sums.at([0]), ~6.0 / ~97.0, "sum_axis row 0")
  assert_close(sums.at([1]), ~15.0 / ~97.0, "sum_axis row 1")
  maxima = x.max_axis(1)
  assert_close(maxima.at([1]), ~6.0 / ~97.0, "max_axis")
  means = x.mean_axis(1)
  assert_close(means.at([0]), ~2.0 / ~97.0, "mean_axis")
  probabilities = x.softmax(1)
  assert_close(probabilities.sum_axis(1).at([0]), ~1.0, "softmax row 0")
  assert_close(probabilities.sum_axis(1).at([1]), ~1.0, "softmax row 1")
  << "CPU_OPS_OK"
elsif mode == "view-oracle"
  raw = f64_array(8)
  i = 0
  while i < 8
    raw[i] = (i + 1).to_f
    i += 1
  whole = Tensor.wrap_cpu(raw, Tensor.f64, [4, 2], [2, 1], 0)
  view = whole.slice(0, 1, 2)
  ident = Tensor.from_rows([[~1.0, ~0.0], [~0.0, ~1.0]], Tensor.f64)
  product = view.matmul(ident)
  assert_close(product.at([0, 0]), ~3.0, "offset matmul 00")
  assert_close(product.at([0, 1]), ~4.0, "offset matmul 01")
  assert_close(product.at([1, 0]), ~5.0, "offset matmul 10")
  assert_close(product.at([1, 1]), ~6.0, "offset matmul 11")
  left_base = Tensor.from_rows([[~1.0, ~2.0, ~3.0], [~4.0, ~5.0, ~6.0]], Tensor.f64)
  left_t = left_base.transpose
  right = Tensor.from_rows([[~7.0, ~8.0], [~9.0, ~10.0]], Tensor.f64)
  left_t_product = left_t.matmul(right)
  assert_close(left_t_product.at([0, 0]), ~43.0, "left transpose 00")
  assert_close(left_t_product.at([2, 1]), ~84.0, "left transpose 21")
  packed_left = Tensor.from_rows([[~1.0, ~2.0], [~3.0, ~4.0], [~5.0, ~6.0]], Tensor.f64)
  right_base = Tensor.from_rows([[~7.0, ~9.0], [~8.0, ~10.0]], Tensor.f64)
  right_t_product = packed_left.matmul(right_base.transpose)
  assert_close(right_t_product.at([0, 0]), ~25.0, "right transpose 00")
  assert_close(right_t_product.at([2, 1]), ~100.0, "right transpose 21")
  << "VIEW_ORACLE_OK"
elsif mode == "metadata"
  iterations = ARGV[1] == nil ? 1000000 : ARGV[1].to_i
  x = filled_tensor(8, 16, Tensor.f64)
  checksum = 0
  t0 = clock()
  i = 0
  while i < iterations
    checksum += x.size
    checksum += 1 if x.contiguous?
    i += 1
  elapsed = clock() - t0
  << "METADATA ns/op=" + (elapsed * ~1000000000.0 / iterations).round(2).to_s + " checksum=" + checksum.to_s
elsif mode == "view-matmul"
  iterations = ARGV[1] == nil ? 20 : ARGV[1].to_i
  # The logical left operand is 192x128, represented as the zero-copy
  # transpose of a packed 128x192 tensor. The old route materializes that
  # view on every matmul call before entering dgemm.
  left = filled_tensor(128, 192, Tensor.f64).transpose
  right = filled_tensor(128, 160, Tensor.f64)
  product = nil
  t0 = clock()
  i = 0
  while i < iterations
    product = left.matmul(right)
    i += 1
  elapsed = clock() - t0
  raise "view matmul produced wrong shape" if product.shape != [192, 160]
  << "VIEW_MATMUL ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + product.at([0, 0]).round(6).to_s
elsif mode == "unary"
  iterations = ARGV[1] == nil ? 20 : ARGV[1].to_i
  x = filled_tensor(256, 256, Tensor.f64)
  y = nil
  t0 = clock()
  i = 0
  while i < iterations
    y = x.exp
    i += 1
  elapsed = clock() - t0
  assert_close(y.at([0, 0]), Math.exp(~1.0 / ~97.0), "unary exp")
  << "UNARY ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s
elsif mode == "reductions"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  x = filled_tensor(256, 256, Tensor.f64)
  checksum = ~0.0
  t0 = clock()
  i = 0
  while i < iterations
    checksum += x.sum
    i += 1
  elapsed = clock() - t0
  << "REDUCTIONS ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + checksum.round(3).to_s
elsif mode == "axis-reductions"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  x = filled_tensor(256, 256, Tensor.f64)
  sums = nil
  maxima = nil
  t0 = clock()
  i = 0
  while i < iterations
    sums = x.sum_axis(1)
    maxima = x.max_axis(1)
    i += 1
  elapsed = clock() - t0
  assert_close(sums.at([0]), ~118.13402061855675, "axis sum")
  assert_close(maxima.at([0]), ~1.0, "axis max")
  << "AXIS_REDUCTIONS ms/pair=" + (elapsed * ~1000.0 / iterations).round(3).to_s
elsif mode == "blas1-scalar"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  n = 65536
  a = f64_array(n)
  b = f64_array(n)
  i = 0
  while i < n
    a[i] = ((i % 97) + 1).to_f / ~97.0
    b[i] = ((i % 89) + 1).to_f / ~89.0
    i += 1
  answer = ~0.0
  t0 = clock()
  i = 0
  while i < iterations
    answer = scalar_dot_f64(a, b, n)
    i += 1
  elapsed = clock() - t0
  << "BLAS1_SCALAR ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + answer.round(6).to_s
elsif mode == "blas1-native"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  n = 65536
  a = f64_array(n)
  b = f64_array(n)
  i = 0
  while i < n
    a[i] = ((i % 97) + 1).to_f / ~97.0
    b[i] = ((i % 89) + 1).to_f / ~89.0
    i += 1
  answer = ~0.0
  t0 = clock()
  i = 0
  while i < iterations
    answer = ddot(a, b, n)
    i += 1
  elapsed = clock() - t0
  << "BLAS1_NATIVE ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + answer.round(6).to_s + " norm=" + dnrm2(a, n).round(6).to_s
elsif mode == "blas2-scalar"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  rows = 512
  cols = 512
  a = f64_array(rows * cols)
  x = f64_array(cols)
  y = f64_array(rows)
  i = 0
  while i < rows * cols
    a[i] = ((i % 97) + 1).to_f / ~97.0
    i += 1
  i = 0
  while i < cols
    x[i] = ((i % 89) + 1).to_f / ~89.0
    i += 1
  t0 = clock()
  i = 0
  while i < iterations
    scalar_gemv_f64(a, x, y, rows, cols)
    i += 1
  elapsed = clock() - t0
  << "BLAS2_SCALAR ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + y[0].round(6).to_s
elsif mode == "blas2-native"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  rows = 512
  cols = 512
  a = f64_array(rows * cols)
  x = f64_array(cols)
  y = f64_array(rows)
  i = 0
  while i < rows * cols
    a[i] = ((i % 97) + 1).to_f / ~97.0
    i += 1
  i = 0
  while i < cols
    x[i] = ((i % 89) + 1).to_f / ~89.0
    i += 1
  t0 = clock()
  i = 0
  while i < iterations
    dgemv(a, x, y, rows, cols)
    i += 1
  elapsed = clock() - t0
  << "BLAS2_NATIVE ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + y[0].round(6).to_s
else
  raise "unknown mode: " + mode
