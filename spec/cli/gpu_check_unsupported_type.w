# Unsupported parameter types must fail in `tungsten -c`, before Metal/CUDA.

## string: input
@gpu fn unsupported_param_type(input)
  value = 1 ## i32
