# CPU Tensor path (no Metal device required).
# Run: bin/tungsten -o /tmp/tcpu spec/sci/tensor_cpu_spec.w && /tmp/tcpu
# (compiled: uses f32_array + sgemm)

use core/blas
use core/tensor

t = Tensor.zeros([2, 3])
<< t.device
<< t.shape[0]
<< t.shape[1]
t.set([0, 0], ~1.0)
t.set([0, 1], ~2.0)
t.set([1, 0], ~3.0)
t.set([1, 1], ~4.0)
<< t.at([0, 0])
<< t.at([1, 1])

a = Tensor.zeros([2, 2])
a.set([0, 0], ~1.0)
a.set([0, 1], ~2.0)
a.set([1, 0], ~3.0)
a.set([1, 1], ~4.0)
b = Tensor.zeros([2, 2])
b.set([0, 0], ~5.0)
b.set([0, 1], ~6.0)
b.set([1, 0], ~7.0)
b.set([1, 1], ~8.0)
c = a.matmul(b)
<< c.at([0, 0])
<< c.at([1, 1])

# Both packed layouts are explicit element-stride views over the same CPU
# buffer. Their logical values differ, and transpose only swaps shape/stride:
# the mutation below is visible through the original row-major view.
raw = f32_array(6)
i = 0
while i < 6
  raw[i] = (i + 1).to_f
  i = i + 1
row_major = Tensor.wrap_cpu(raw, Tensor.f32, [2, 3], Tensor.packed_strides([2, 3]), 0)
column_major = Tensor.wrap_cpu(raw, Tensor.f32, [2, 3], Tensor.column_major_strides([2, 3]), 0)
<< row_major.at([0, 1])
<< column_major.at([0, 1])
transposed = row_major.transpose
<< transposed.shape[0]
<< transposed.shape[1]
<< transposed.at([1, 0])
transposed.set([2, 1], ~99.0)
<< row_major.at([1, 2])
<< column_major.at([1, 2])
<< transposed.contiguous?

# Core owns rectangular row packing and f64 BLAS too; tabular adapters can use
# this without reimplementing f64_array / dgemm flattening.
f64_rows = Tensor.from_rows([[1, 2], [3, 4]], Tensor.f64)
<< f64_rows.dtype
<< f64_rows.to_rows[1][0]
f64_product = f64_rows.matmul(f64_rows)
<< f64_product.dtype
<< f64_product.at([0, 0])
<< f64_product.at([1, 1])
<< "TENSOR_CPU_OK"
