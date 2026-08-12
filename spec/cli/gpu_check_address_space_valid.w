# Explicit helper address spaces let shared/thread-local arrays cross a device
# helper boundary without weakening the default device-buffer contract.

## f32[] threadgroup: values
## f32: ret
@gpu fn first_shared_value(values)
  values[0]

## i32[] thread: values
## i32: ret
@gpu fn first_thread_value(values)
  values[0]

## u32[] constant: values
## u32: ret
@gpu fn first_constant_value(values)
  values[0]

## i32: marker
@gpu fn valid_shared_argument(marker)
  tile = gpu.shared_f32(4)
  tile[0] = 7.0
  shared_value = first_shared_value(tile) ## f32
  private_values = i32[4]
  private_values[0] = 9
  thread_value = first_thread_value(private_values) ## i32
  constants = [11, 12] ## u32[]
  constant_value = first_constant_value(constants) ## u32
