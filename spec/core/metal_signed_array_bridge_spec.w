# Signed i32/i64 arrays use distinct ebits codes (33/66), but their Metal
# buffers retain ordinary 4/8-byte element widths.

use core/metal

device = metal_device()

i32_values = i32[3]
i32_values[0] = -1
i32_buffer = metal_buffer_for(device, i32_values)
if metal_buffer_length(i32_buffer) != 12
  << "FAIL Metal i32 array width"
  exit 1

i64_values = i64[3]
i64_values[0] = -281474976710779
i64_buffer = metal_buffer_for(device, i64_values)
if metal_buffer_length(i64_buffer) != 24
  << "FAIL Metal i64 array width"
  exit 1

<< "PASS Metal signed array bridge"
