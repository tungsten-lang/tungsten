# Repeated MTLTensor face lookup over one stable Tensor allocation.

use core/tensor

iterations = ARGV[0] == nil ? 10000 : ARGV[0].to_i
device = metal_device()
tensor = Tensor.zeros(device, Tensor.f32, [64, 64])
face = tensor.metal_tensor
first = face
started = clock()
i = 0
while i < iterations
  face = tensor.metal_tensor
  i += 1
elapsed = clock() - started
raise "metal tensor face missing" if face == nil
raise "metal tensor face was not cached" if face != first

# An in-place metadata mutation must invalidate the snapshot rather than
# return a stale descriptor.
whole = Tensor.zeros(device, Tensor.f32, [65, 64])
view = whole.slice(0, 0, 64)
before = view.metal_tensor
view.shape[0] = 63
after = view.metal_tensor
raise "metal tensor cache survived shape mutation" if before == after
<< "METAL_TENSOR_FACE ns/op=" + (elapsed * ~1000000000.0 / iterations).round(2).to_s + " cache=ok invalidation=ok"
