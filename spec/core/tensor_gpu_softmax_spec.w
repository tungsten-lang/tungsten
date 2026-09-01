# Cooperative Tensor GPU softmax correctness and shape-policy coverage.

use core/tensor

-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> close?(actual, expected, tolerance)
  (actual - expected).abs <= tolerance

-> make_gpu_tensor(rows, cols)
  device = metal_device()
  data = metal_array(-32, rows * cols)
  i = 0
  while i < rows * cols
    data[i] = (((i * 13 + i / cols * 17) % 257) - 128).to_f / ~17.0
    i += 1
  [Tensor.from_array(device, data, Tensor.f32, [rows, cols]), data]

# 257 columns enters the cooperative selector and also exercises a partial
# final lane stride. Compare representative cells against a double reference.
pair = make_gpu_tensor(3, 257)
x = pair[0]
input = pair[1]
y = x.softmax(1)
max_error = ~0.0
max_sum_error = ~0.0
r = 0
while r < 3
  mx = input[r * 257]
  c = 1
  while c < 257
    value = input[r * 257 + c]
    mx = value if value > mx
    c += 1
  sm = ~0.0
  c = 0
  while c < 257
    sm += Math.exp(input[r * 257 + c] - mx)
    c += 1
  row_sum = ~0.0
  c = 0
  while c < 257
    got = y.at([r, c])
    expected = Math.exp(input[r * 257 + c] - mx) / sm
    error = (got - expected).abs
    max_error = error if error > max_error
    row_sum += got
    c += 1
  sum_error = (row_sum - ~1.0).abs
  max_sum_error = sum_error if sum_error > max_sum_error
  r += 1
check("tensor.gpu.softmax cooperative values", max_error < ~0.000002)
check("tensor.gpu.softmax cooperative row sums", max_sum_error < ~0.00001)

# Short rows keep the serial path. Both routes remain directly callable so
# their numerical contract can be checked at the crossover boundary.
short_pair = make_gpu_tensor(4, 128)
short_x = short_pair[0]
serial = short_x.gpu_softmax_rows_serial()
cooperative = short_x.gpu_softmax_rows_parallel(64)
max_pair_error = ~0.0
i = 0
while i < 4 * 128
  row = i / 128
  col = i % 128
  error = (serial.at([row, col]) - cooperative.at([row, col])).abs
  max_pair_error = error if error > max_pair_error
  i += 1
check("tensor.gpu.softmax serial cooperative parity", max_pair_error < ~0.000002)
check("tensor.gpu.softmax selector short row", close?(short_x.softmax(1).at([2, 31]), serial.at([2, 31]), ~0.0000001))
