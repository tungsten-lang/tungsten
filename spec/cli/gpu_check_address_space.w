# Metal device helpers cannot accept threadgroup memory through an ordinary
# array parameter; the address space must be part of a future source contract.

## f32[]: values
## f32: ret
@gpu fn first_value(values)
  values[0]

## i32: marker
@gpu fn invalid_shared_argument(marker)
  tile = gpu.shared_f32(4)
  value = first_value(tile) ## f32
