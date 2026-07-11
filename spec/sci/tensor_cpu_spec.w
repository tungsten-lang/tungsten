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
<< "TENSOR_CPU_OK"
