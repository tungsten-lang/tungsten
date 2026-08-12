# Literal accesses to statically sized workgroup arrays are checked before GPU
# source is emitted.

## i32: marker
@gpu fn invalid_shared_index(marker)
  tile = gpu.shared_i32(4)
  tile[4] = marker
