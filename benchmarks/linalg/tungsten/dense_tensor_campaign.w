# Focused correctness and performance probes for the perf30 dense campaign.
#
# Compile once per revision, then select a mode:
#   dense_tensor_campaign cpu-ops
#   dense_tensor_campaign view-oracle
#   dense_tensor_campaign metadata [iterations]
#   dense_tensor_campaign unary [iterations]
#   dense_tensor_campaign reductions [iterations]

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
else
  raise "unknown mode: " + mode
