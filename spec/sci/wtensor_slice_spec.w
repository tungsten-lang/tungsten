# WTensor view / slice0 smoke.
# Run: bin/tungsten -o /tmp/wts spec/sci/wtensor_slice_spec.w && /tmp/wts

use core/blas
use core/tensor

# 4×3 matrix filled row-major 0..11
t = Tensor.w_zeros([4, 3])
r = 0
while r < 4
  c = 0
  while c < 3
    Tensor.w_set(t, [r, c], (r * 3 + c) + ~0.0)
    c = c + 1
  r = r + 1

# slice rows [1,3) → 2×3 with values starting at 3
v = Tensor.w_slice0(t, 1, 3)
<< Tensor.w_rank(v)
sh = Tensor.w_shape(v)
<< sh[0]
<< sh[1]
<< Tensor.w_at(v, [0, 0])
<< Tensor.w_at(v, [0, 2])
<< Tensor.w_at(v, [1, 0])

# view: skip first 3 elems (row0), shape [3,3] → rows 1-3
w = Tensor.w_view(t, 3, [3, 3])
<< Tensor.w_at(w, [0, 0])
<< Tensor.w_at(w, [2, 2])

# parent mutation visible through view
Tensor.w_set(t, [1, 0], ~99.0)
<< Tensor.w_at(v, [0, 0])

<< "WTENSOR_SLICE_OK"
