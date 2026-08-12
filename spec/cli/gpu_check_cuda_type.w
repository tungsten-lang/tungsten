# Types represented only by Metal must fail before an invalid CUDA sidecar is
# passed to nvcc.

## mat4: transform
@gpu fn unsupported_cuda_parameter(transform)
  value = 1 ## i32
