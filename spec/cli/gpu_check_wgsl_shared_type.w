# WGSL has no portable 64-bit integer workgroup storage.

## i32: marker
@gpu fn invalid_wgsl_shared_type(marker)
  tile = gpu.shared_i64(8)
