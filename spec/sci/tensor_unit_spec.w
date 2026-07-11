# Tensor unit tagging smoke (compiled).
# Run: bin/tungsten -o /tmp/tunit spec/sci/tensor_unit_spec.w && /tmp/tunit

use core/blas
use core/tensor

v = Tensor.zeros_unit("f64", "m/s", [2, 2])
<< v.dtype
<< v.unit
<< v.shape[0]
<< v.shape[1]
v.set([0, 0], ~1.0)
v.set([1, 1], ~2.0)
<< v.at([0, 0])
<< v.at([1, 1])

# same unit: add ok
w = Tensor.zeros_unit("f64", "m/s", [2, 2])
w.set([0, 0], ~3.0)
s = v + w
<< s.unit
<< s.at([0, 0])

# view preserves unit
sl = v.slice(0, 0, 1)
<< sl.unit

# untyped zeros has nil unit
z = Tensor.zeros([2, 2])
# nil prints empty / nil depending on runtime — just exercise path
z.set([0, 0], ~1.0)
<< z.at([0, 0])

<< "TENSOR_UNIT_OK"
