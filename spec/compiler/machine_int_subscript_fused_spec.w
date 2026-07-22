# Fused machine-int subscript capture: `x = recv[i] ## i64/u64` on an
# untyped receiver lowers to w_index_raw_i64/u64 (typed integer arrays load
# raw — no boxed temporary) instead of generic dispatch + w_to_i64/u64,
# whose dead bignum box (element > 2^48) leaked one allocation per read
# (2026-07-22; ~1 GB/s in a real search loop). Every receiver below must
# behave exactly as the old path did — the fast path only exists for typed
# integer arrays; poly arrays, Hash, and custom [] overloads still take
# dynamic dispatch inside the helper. OOB and non-integer results keep
# their old coercion errors (same w_to_* call on the same value).
#
# Run: `bin/tungsten -o /tmp/msf spec/compiler/machine_int_subscript_fused_spec.w && /tmp/msf`

+ OffsetBox
  -> new(@base) ro
  -> [](i)
    @base + i

-> read_i(recv, i)
  v = recv[i] ## i64
  v

-> read_u(recv, i)
  v = recv[i] ## u64
  v

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

cell = i64[4]
cell[0] = 88172645463325252
cell[1] = 0 - 5
check("fused.typed_big_u64", read_u(cell, 0) == 88172645463325252)
check("fused.typed_negative_elem", read_i(cell, 1) == 0 - 5)
check("fused.negative_index_wraps", read_u(cell, 0 - 4) == 88172645463325252)

sum = 0 ## u64
j = 0 ## i64
while j < 100_000
  sum = sum + (read_u(cell, 0) ## u64)
  j += 1
check("fused.loop_stable", sum != 0)

h = {7 => 123456789012345678}
check("fused.hash_receiver", read_i(h, 7) == 123456789012345678)

poly = [1, 340282366920938463463374607431768211456, 3]
check("fused.poly_bignum_low64", read_u(poly, 1) == 0)

bx = OffsetBox.new(100)
check("fused.custom_overload", read_i(bx, 11) == 111)

u8s = u8[3]
u8s[2] = 200
check("fused.small_elem_array", read_i(u8s, 2) == 200)
