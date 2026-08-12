# Metal's 32 KiB baseline accepts this allocation; WGSL's portable 16 KiB
# baseline does not: 5000*4 = 20000 bytes.

## i32: marker
@gpu fn excessive_wgsl_shared_total(marker)
  tile = gpu.shared_f32(5000)
  tile[0] = 1.0
