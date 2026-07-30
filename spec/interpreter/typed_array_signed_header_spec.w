# The tree walker must preserve signed i32/i64 identity in the native typed
# array header.  Keep sizes above the SmallArray promotion ceiling so this is
# explicitly a heap-array decoder regression.

i32_values = i32[256]
i32_values[0] = -2147483648
i32_values[255] = -1
if i32_values[0] != -2147483648 || i32_values[255] != -1
  << "FAIL interpreter i32 signed header"
  exit 1

i64_values = i64[256]
i64_values[0] = -281474976710779
i64_values[255] = -1
if i64_values[0] != -281474976710779 || i64_values[255] != -1
  << "FAIL interpreter i64 signed header"
  exit 1

<< "PASS interpreter typed-array signed headers"
