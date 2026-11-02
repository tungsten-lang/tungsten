# A fused indexed update must retain its raw result representation until an
# actual boxed boundary. In particular, an outer ## i64 must not unbox it.

-> check_result(label, actual, expected)
  if actual != expected
    raise "[label]: [actual] != [expected]"

-> annotated_or(a) (i64[]) i64
  one = 1 ## i64
  mask = one << 11 ## i64
  a[0] = (a[0] | mask) ## i64
  a[0]

-> boxed_add(a) (i64[])
  a[0] = a[0] + 7

-> boxed_left_add(a) (i64[])
  a[0] = 7 + a[0]

-> boxed_sub(a) (i64[])
  a[0] = a[0] - 4

-> boxed_mul(a) (i64[])
  a[0] = a[0] * 3

-> boxed_and(a) (i64[])
  a[0] = a[0] & 15

-> boxed_xor(a) (i64[])
  a[0] = a[0] ^ 12

-> boxed_left_shift(a) (i64[])
  a[0] = a[0] << 3

-> boxed_right_shift(a) (i64[])
  a[0] = a[0] >> 2

-> boxed_large(a) (i64[])
  one = 1 ## i64
  high = one << 55 ## i64
  a[0] = a[0] | high

-> boxed_unsigned(a) (u64[])
  one = 1 ## u64
  high = one << 63 ## u64
  a[0] = a[0] | high

-> narrow_signed(a) (i8[])
  a[0] = a[0] - 3

-> narrow_unsigned(a) (u32[])
  a[0] = a[0] | 2147483648

-> narrow_i16(a) (i16[])
  a[0] = a[0] - 5

-> narrow_i32(a) (i32[])
  a[0] = a[0] - 9

-> narrow_u8(a) (u8[])
  a[0] = a[0] | 128

-> narrow_u16(a) (u16[])
  a[0] = a[0] | 32768

a = i64[1]
check_result("annotated result", annotated_or(a), 2048)
check_result("annotated storage", a[0], 2048)
a[0] = 2
check_result("boxed add", boxed_add(a), 9)
check_result("commuted add", boxed_left_add(a), 16)
check_result("boxed subtract", boxed_sub(a), 12)
check_result("boxed multiply", boxed_mul(a), 36)
check_result("boxed and", boxed_and(a), 4)
check_result("boxed xor", boxed_xor(a), 8)
check_result("boxed shift left", boxed_left_shift(a), 64)
check_result("boxed shift right", boxed_right_shift(a), 16)
check_result("full signed word", boxed_large(a), 36028797018963984)
check_result("full signed stored", a[0], 36028797018963984)
u = u64[1]
check_result("full unsigned word", boxed_unsigned(u), 9223372036854775808)
check_result("full unsigned stored", u[0], 9223372036854775808)
s = i8[1]
s[0] = 1
check_result("narrow signed result", narrow_signed(s), -2)
check_result("narrow signed stored", s[0], -2)
b = u32[1]
check_result("narrow unsigned result", narrow_unsigned(b), 2147483648)
check_result("narrow unsigned stored", b[0], 2147483648)
s16 = i16[1]
check_result("i16 result", narrow_i16(s16), -5)
check_result("i16 stored", s16[0], -5)
s32 = i32[1]
check_result("i32 result", narrow_i32(s32), -9)
check_result("i32 stored", s32[0], -9)
u8s = u8[1]
check_result("u8 result", narrow_u8(u8s), 128)
check_result("u8 stored", u8s[0], 128)
u16s = u16[1]
check_result("u16 result", narrow_u16(u16s), 32768)
check_result("u16 stored", u16s[0], 32768)
<< "PASS typed array compound result"
