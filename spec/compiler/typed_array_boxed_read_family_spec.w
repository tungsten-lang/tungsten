# Every boxed typed-array read entry point must decode u64/i64 with the same
# signedness.  Keep these arrays above the 255-element stack-promotion cap so
# this exercises the heap/runtime family rather than SmallArray inline loads.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got=" + got + " want=" + want
    exit 1

max = 18446744073709551615 ## u64
next_max = 18446744073709551614 ## u64
near_high = 18446744073709551613 ## u64
high_bit = 9223372036854775808 ## u64
negative = (0 - 281474976710779) ## i64

unsigned = u64[256]
unsigned[0] = max
holder = []
holder.push(unsigned)
hidden_unsigned = holder[0]

check("typed_array.u64_checked_generic", hidden_unsigned[0].to_s(), "18446744073709551615")
check("typed_array.u64_checked_i64", ccall("w_array_get_i64", unsigned, 0).to_s(), "18446744073709551615")
check("typed_array.u64_unchecked_idx", ccall("w_array_idx", unsigned, 0).to_s(), "18446744073709551615")
check("typed_array.u64_unchecked_idx_i64", ccall("w_array_idx_i64", unsigned, 0).to_s(), "18446744073709551615")
check("typed_array.u64_include_max", hidden_unsigned.include?(max).to_s(), "true")
check("typed_array.u64_include_absent_high", hidden_unsigned.include?(near_high).to_s(), "false")

signed = i64[256]
signed[0] = negative
holder.push(signed)
hidden_signed = holder[1]
hash_holder = {"signed": signed}
hash_hidden_signed = hash_holder["signed"]

check("typed_array.i64_checked_generic", hidden_signed[0].to_s(), "-281474976710779")
check("typed_array.i64_checked_hash_alias", hash_hidden_signed[0].to_s(), "-281474976710779")
check("typed_array.i64_checked_i64", ccall("w_array_get_i64", signed, 0).to_s(), "-281474976710779")
check("typed_array.i64_unchecked_idx", ccall("w_array_idx", signed, 0).to_s(), "-281474976710779")

scan_i32 = i32[256]
scan_i32[5] = -1
scan_i32[7] = -1
holder.push(scan_i32)
hidden_scan_i32 = holder[2]
check("typed_array.i32_include_negative", hidden_scan_i32.include?(-1).to_s(), "true")
check("typed_array.i32_count_negative", hidden_scan_i32.count(-1).to_s(), "2")
check("typed_array.i32_find_negative", hidden_scan_i32.find_index(-1).to_s(), "5")
check("typed_array.i32_last_negative", hidden_scan_i32.last_index(-1).to_s(), "7")

scan_u32 = u32[256]
scan_u32[9] = 4294967295
holder.push(scan_u32)
hidden_scan_u32 = holder[3]
check("typed_array.u32_include_rejects_negative", hidden_scan_u32.include?(-1).to_s(), "false")
check("typed_array.u32_count_rejects_negative", hidden_scan_u32.count(-1).to_s(), "0")

deque = u64[256]
deque[0] = max
deque[255] = next_max
check("typed_array.u64_pop", deque.pop.to_s(), "18446744073709551614")
check("typed_array.u64_shift", deque.shift.to_s(), "18446744073709551615")

extrema = u64[256]
i = 0
while i < extrema.size
  extrema[i] = max
  i += 1
extrema[1] = high_bit
holder.push(extrema)
hidden_extrema = holder[4]
check("typed_array.u64_min_high", hidden_extrema.min.to_s(), "9223372036854775808")
check("typed_array.u64_max", hidden_extrema.max.to_s(), "18446744073709551615")

freeze_sentinel = u64[256]
freeze_sentinel[0] = 20 ## u64
frozen_sentinel = ccall("w_freeze", freeze_sentinel)
check("typed_array.u64_freeze_identity", (frozen_sentinel == freeze_sentinel).to_s(), "true")
check("typed_array.u64_freeze_preserves_slot", freeze_sentinel[0].to_s(), "20")

big = BigArray.new(:u64, 1)
big[0] = max
check("big_array.u64_checked", big[0].to_s(), "18446744073709551615")
check("big_array.u64_checked_runtime", ccall("w_big_array_get", big, 0).to_s(), "18446744073709551615")
check("big_array.u64_unchecked_idx", ccall("w_big_array_idx", big, 0).to_s(), "18446744073709551615")
check("big_array.negative_wrap", big[-1].to_s(), "18446744073709551615")
check("big_array.oob_is_nil", (big[1] == nil).to_s(), "true")

big_signed = BigArray.new(:i64, 1)
big_signed[0] = negative
check("big_array.i64_checked", big_signed[0].to_s(), "-281474976710779")

small = SmallArray.new(:u64, 1)
small[0] = max
check("small_array.u64_checked", small[0].to_s(), "18446744073709551615")
check("small_array.u64_checked_runtime", ccall("w_small_array_get", small, 0).to_s(), "18446744073709551615")
check("small_array.u64_unchecked_idx", ccall("w_small_array_idx", small, 0).to_s(), "18446744073709551615")

<< "PASS typed-array boxed read family"
