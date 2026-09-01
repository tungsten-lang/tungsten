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
expect("tensor.cpu.sum packed", close?(x.sum, ~21.0))
expect("tensor.cpu.max packed", close?(x.max, ~6.0))
column_sums = x.sum_axis(0)
expect("tensor.cpu.sum_axis fallback", close?(column_sums.at([0]), ~5.0) && close?(column_sums.at([2]), ~9.0))

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

into_storage = f64_array(8)
i = 0
while i < 8
  into_storage[i] = ~99.0
  i += 1
i = 2
while i < 6
  into_storage[i] = ~10.0
  i += 1
into_view = Tensor.wrap_cpu(into_storage, Tensor.f64, [2, 2], [2, 1], 2)
into_return = view.matmul_into(identity, into_view, ~2.0, ~0.5)
expect("tensor.cpu.matmul_into scaled", close?(into_view.at([0, 0]), ~11.0) && close?(into_view.at([1, 1]), ~17.0))
expect("tensor.cpu.matmul_into offset", close?(into_storage[0], ~99.0) && close?(into_storage[7], ~99.0))
expect("tensor.cpu.matmul_into identity", into_return.buffer == into_storage)

left_base = Tensor.from_rows([[~1.0, ~2.0, ~3.0], [~4.0, ~5.0, ~6.0]], Tensor.f64)
right = Tensor.from_rows([[~7.0, ~8.0], [~9.0, ~10.0]], Tensor.f64)
transpose_product = left_base.transpose.matmul(right)
expect("tensor.cpu.matmul left transpose", close?(transpose_product.at([0, 0]), ~43.0) && close?(transpose_product.at([2, 1]), ~84.0))

packed_left = Tensor.from_rows([[~1.0, ~2.0], [~3.0, ~4.0], [~5.0, ~6.0]], Tensor.f64)
right_base = Tensor.from_rows([[~7.0, ~9.0], [~8.0, ~10.0]], Tensor.f64)
right_transpose_product = packed_left.matmul(right_base.transpose)
expect("tensor.cpu.matmul right transpose", close?(right_transpose_product.at([0, 0]), ~25.0) && close?(right_transpose_product.at([2, 1]), ~100.0))

transpose_into = Tensor.zeros_cpu(Tensor.f64, [3, 2])
left_base.transpose.matmul_into(right, transpose_into, ~1.0, ~0.0)
expect("tensor.cpu.matmul_into transpose", close?(transpose_into.at([0, 0]), ~43.0) && close?(transpose_into.at([2, 1]), ~84.0))

expect("tensor.packed_strides rank 3", Tensor.packed_strides([2, 3, 4]) == [12, 4, 1])
expect("tensor.contiguous rejects short strides", !Tensor.wrap_cpu(storage, Tensor.f64, [2, 2], [2], 0).contiguous?)
offset_rows = view.to_rows
expect("tensor.to_rows honors offset", close?(offset_rows[0][0], ~3.0) && close?(offset_rows[1][1], ~6.0))
expect("tensor.cpu.sum offset", close?(view.sum, ~18.0))
expect("tensor.cpu.max offset", close?(view.max, ~6.0))
expect("tensor.cpu.sum strided fallback", close?(left_base.transpose.sum, ~21.0))

f32_values = Tensor.from_rows([[~1.0, ~2.0], [~3.0, ~4.0]], Tensor.f32)
f32_sums = f32_values.sum_axis(1)
expect("tensor.cpu.f32 reductions", close?(f32_values.sum, ~10.0) && close?(f32_values.max, ~4.0) && close?(f32_sums.at([1]), ~7.0))
f32_probabilities = f32_values.softmax(1)
expect("tensor.cpu.f32 softmax backend", f32_probabilities.device == :cpu)
expect("tensor.cpu.f32 softmax values", close?(f32_probabilities.sum_axis(1).at([0]), ~1.0))

# Large f32 shapes meet the GPU work threshold but CPU WArrays must remain on
# the CPU reference lane rather than being bound as MTLBuffers.
large_f32_left = Tensor.zeros_cpu(Tensor.f32, [4096])
large_f32_right = Tensor.zeros_cpu(Tensor.f32, [4096])
large_f32_sum = large_f32_left + large_f32_right
expect("tensor.cpu.f32 large binop backend", large_f32_sum.device == :cpu)
expect("tensor.cpu.f32 large binop value", close?(large_f32_sum.at([4095]), ~0.0))

f32_into = Tensor.zeros_cpu(Tensor.f32, [2, 2])
f32_values.matmul_into(f32_values, f32_into, ~1.0, ~0.0)
expect("tensor.cpu.f32 matmul_into", close?(f32_into.at([0, 0]), ~7.0) && close?(f32_into.at([1, 1]), ~22.0))
f32_integer_into = Tensor.zeros_cpu(Tensor.f32, [2, 2])
f32_values.matmul_into(f32_values, f32_integer_into, 1, 0)
expect("tensor.cpu.f32 matmul_into integer scalars", close?(f32_integer_into.at([0, 0]), ~7.0) && close?(f32_integer_into.at([1, 1]), ~22.0))

f64_integer_into = Tensor.zeros_cpu(Tensor.f64, [2, 2])
identity.matmul_into(identity, f64_integer_into, 1, 0)
expect("tensor.cpu.f64 matmul_into integer scalars", close?(f64_integer_into.at([0, 0]), ~1.0) && close?(f64_integer_into.at([1, 1]), ~1.0))

# Distinct slice objects can still share and overlap one backing allocation.
# The native boundary must reject that alias before CBLAS overwrites an input.
overlap_storage = f64_array(8)
i = 0
while i < 8
  overlap_storage[i] = (i + 1).to_f
  i += 1
overlap_left = Tensor.wrap_cpu(overlap_storage.slice(0, 4), Tensor.f64, [2, 2], [2, 1], 0)
overlap_out = Tensor.wrap_cpu(overlap_storage.slice(2, 4), Tensor.f64, [2, 2], [2, 1], 0)
overlap_rejected = false
begin
  overlap_left.matmul_into(identity, overlap_out, ~1.0, ~0.0)
rescue err
  overlap_rejected = true
expect("tensor.cpu.matmul_into overlapping slices rejected", overlap_rejected)

unary_storage = f64_array(6)
unary_storage[0] = ~-9.0
unary_storage[1] = ~-4.0
unary_storage[2] = ~-1.0
unary_storage[3] = ~0.0
unary_storage[4] = ~2.0
unary_storage[5] = ~3.0
unary_whole = Tensor.wrap_cpu(unary_storage, Tensor.f64, [3, 2], [2, 1], 0)
unary_view = unary_whole.slice(0, 1, 2)
expect("tensor.cpu.unary neg offset", close?(unary_view.neg.at([0, 0]), ~1.0) && close?(unary_view.neg.at([1, 1]), ~-3.0))
expect("tensor.cpu.unary relu", close?(unary_view.relu.at([0, 0]), ~0.0) && close?(unary_view.relu.at([1, 0]), ~2.0))
expect("tensor.cpu.unary abs", close?(unary_view.abs.at([0, 0]), ~1.0) && close?(unary_view.abs.at([1, 1]), ~3.0))
expect("tensor.cpu.unary sqrt", close?(unary_view.abs.sqrt.at([1, 0]), Math.sqrt(~2.0)))
expect("tensor.cpu.unary square", close?(unary_view.square.at([0, 0]), ~1.0) && close?(unary_view.square.at([1, 1]), ~9.0))
expect("tensor.cpu.unary exp", close?(unary_view.exp.at([0, 1]), ~1.0) && close?(unary_view.exp.at([1, 0]), Math.exp(~2.0)))
expect("tensor.cpu.unary strided fallback", close?(unary_whole.transpose.abs.at([0, 1]), ~1.0))

f32_exp = f32_values.exp
expect("tensor.cpu.f32 unary", close?(f32_exp.at([0, 0]), Math.exp(~1.0)) && close?(f32_exp.at([1, 1]), Math.exp(~4.0)))

# Native paths preserve the scalar reference's exact IEEE order/sign contract.
zero_storage = f64_array(1)
zero_storage[0] = ~0.0
zero_tensor = Tensor.wrap_cpu(zero_storage, Tensor.f64, [1], [1], 0)
expect("tensor.cpu.neg preserves positive zero",
       ccall("w_float_to_u64_bits", zero_tensor.neg.at([0])) == 0)

cancellation_storage = f64_array(8)
cancellation_storage[0] = ~1.0e16
cancellation_storage[1] = ~1.0
cancellation_storage[2] = ~-1.0e16
cancellation_storage[3] = ~1.0
cancellation_storage[4] = ~1.0e16
cancellation_storage[5] = ~1.0
cancellation_storage[6] = ~-1.0e16
cancellation_storage[7] = ~1.0
cancellation = Tensor.wrap_cpu(
  cancellation_storage, Tensor.f64, [2, 4], [4, 1], 0)
cancellation_rows = cancellation.sum_axis(1)
expect("tensor.cpu.sum preserves left-fold order", cancellation.sum == ~1.0)
expect("tensor.cpu.sum_axis preserves left-fold order",
       cancellation_rows.at([0]) == ~1.0 && cancellation_rows.at([1]) == ~1.0)
