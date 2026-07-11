# Native WTensor smoke (forces blas_bridge for link pre-rebuild).
# Run: bin/tungsten -o /tmp/wt spec/sci/wtensor_spec.w && /tmp/wt

use core/blas
use core/tensor

# @w_tensor_ pulls tensor_bridge.c after stage-1 rebuild.
t = Tensor.w_zeros([2, 3])
<< Tensor.w_rank(t)
sh = Tensor.w_shape(t)
<< sh[0]
<< sh[1]
Tensor.w_set(t, [0, 0], ~1.5)
Tensor.w_set(t, [1, 2], ~9.0)
<< Tensor.w_at(t, [0, 0])
<< Tensor.w_at(t, [1, 2])
<< "WTENSOR_OK"
