# Stack-promoted SmallArray loads retain their element's full scalar type at a
# boxing boundary.  In particular, u64/i64 values outside the immediate i48
# payload must go through the unsigned/signed runtime bridges, while w64 slots
# already contain a complete WValue and must not be boxed again.
#
# Run:
#   ruby bin/tungsten.rb spec/compiler/small_array_wide_element_boxing_spec.w
#   bin/tungsten -o /tmp/saweb spec/compiler/small_array_wide_element_boxing_spec.w
#   /tmp/saweb

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> stack_u64_text
  values = u64[1]
  values[0] = 18446744073709551615 ## u64
  values[0].to_s()

-> stack_i64_text
  values = i64[1]
  values[0] = 281474976710779 ## i64
  values[0].to_s()

-> stack_i64_negative_text
  values = i64[1]
  values[0] = (0 - 281474976710779) ## i64
  values[0].to_s()

-> stack_i32_negative_text
  values = i32[1]
  values[0] = -123456789
  values[0].to_s()

-> stack_w64_value
  values = w64[1]
  values[0] = "small-array-w64"
  values[0]

check("small_array.u64_boxes_unsigned", stack_u64_text == "18446744073709551615")
check("small_array.i64_boxes_signed", stack_i64_text == "281474976710779")
check("small_array.i64_boxes_negative", stack_i64_negative_text == "-281474976710779")
check("small_array.i32_boxes_negative", stack_i32_negative_text == "-123456789")
check("small_array.w64_is_already_boxed", stack_w64_value == "small-array-w64")

<< "PASS small-array wide element boxing"
