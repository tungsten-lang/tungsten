# Each declaration fits Metal's workgroup-memory limit independently, but the
# aggregate does not: 5000*4 + 4000*4 = 36000 > 32768 bytes.

## i32: marker
@gpu fn excessive_shared_total(marker)
  first = gpu.shared_f32(5000)
  second = gpu.shared_i32(4000)
  first[0] = 1.0
  second[0] = 1
