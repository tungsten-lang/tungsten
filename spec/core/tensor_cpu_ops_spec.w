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
