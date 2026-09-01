# CPU Tensor output-allocation and numeric-operation regression coverage.

use core/blas
use core/tensor

-> expect(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> close?(actual, expected)
  delta = actual - expected
  delta = ~0.0 - delta if delta < ~0.0
  delta < ~0.00001

raw = f64_array(6)
i = 0
while i < 6
  raw[i] = (i + 1).to_f
  i += 1
x = Tensor.wrap_cpu(raw, Tensor.f64, [2, 3], [3, 1], 0)

scaled = x.scale(~2.0)
expect("tensor.cpu.scale backend", scaled.device == :cpu)
expect("tensor.cpu.scale value", close?(scaled.at([1, 2]), ~12.0))

root = scaled.sqrt
expect("tensor.cpu.sqrt backend", root.device == :cpu)
expect("tensor.cpu.sqrt value", close?(root.at([0, 0]), Math.sqrt(~2.0)))

sums = x.sum_axis(1)
maxima = x.max_axis(1)
means = x.mean_axis(1)
expect("tensor.cpu.sum_axis", close?(sums.at([1]), ~15.0))
expect("tensor.cpu.max_axis", close?(maxima.at([1]), ~6.0))
expect("tensor.cpu.mean_axis", close?(means.at([0]), ~2.0))

probabilities = x.softmax(1)
row_sums = probabilities.sum_axis(1)
expect("tensor.cpu.softmax backend", probabilities.device == :cpu)
expect("tensor.cpu.softmax row 0", close?(row_sums.at([0]), ~1.0))
expect("tensor.cpu.softmax row 1", close?(row_sums.at([1]), ~1.0))

# Packed slices carry a nonzero storage offset. GEMM must not silently bind the
# base array, and a packed transpose should not need a materialization copy.
storage = f64_array(8)
i = 0
while i < 8
  storage[i] = (i + 1).to_f
  i += 1
whole = Tensor.wrap_cpu(storage, Tensor.f64, [4, 2], [2, 1], 0)
view = whole.slice(0, 1, 2)
identity = Tensor.from_rows([[~1.0, ~0.0], [~0.0, ~1.0]], Tensor.f64)
view_product = view.matmul(identity)
expect("tensor.cpu.matmul offset", close?(view_product.at([0, 0]), ~3.0) && close?(view_product.at([1, 1]), ~6.0))

left_base = Tensor.from_rows([[~1.0, ~2.0, ~3.0], [~4.0, ~5.0, ~6.0]], Tensor.f64)
right = Tensor.from_rows([[~7.0, ~8.0], [~9.0, ~10.0]], Tensor.f64)
transpose_product = left_base.transpose.matmul(right)
expect("tensor.cpu.matmul left transpose", close?(transpose_product.at([0, 0]), ~43.0) && close?(transpose_product.at([2, 1]), ~84.0))

packed_left = Tensor.from_rows([[~1.0, ~2.0], [~3.0, ~4.0], [~5.0, ~6.0]], Tensor.f64)
right_base = Tensor.from_rows([[~7.0, ~9.0], [~8.0, ~10.0]], Tensor.f64)
right_transpose_product = packed_left.matmul(right_base.transpose)
expect("tensor.cpu.matmul right transpose", close?(right_transpose_product.at([0, 0]), ~25.0) && close?(right_transpose_product.at([2, 1]), ~100.0))

expect("tensor.packed_strides rank 3", Tensor.packed_strides([2, 3, 4]) == [12, 4, 1])
expect("tensor.contiguous rejects short strides", !Tensor.wrap_cpu(storage, Tensor.f64, [2, 2], [2], 0).contiguous?)
offset_rows = view.to_rows
expect("tensor.to_rows honors offset", close?(offset_rows[0][0], ~3.0) && close?(offset_rows[1][1], ~6.0))
