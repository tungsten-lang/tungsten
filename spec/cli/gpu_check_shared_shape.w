# Workgroup arrays require a positive, static element count.

## i32: marker
@gpu fn invalid_shared_shape(marker)
  tile = gpu.shared_f32(0)
