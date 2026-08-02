# Writable native-data view fields. A matching `$field = value` inside a
# class method must update implicit `self` directly, return the converted raw
# field value, and emit no runtime helper call.
#
# Run:
#   bin/tungsten compile spec/compiler/view_field_store_spec.w \
#     --out /tmp/view-field-store --release --native --fast
#   /tmp/view-field-store

use ../../core/numeric/big_int
use ../../compiler/lib/lowering
use ../../compiler/lib/emitter

-> check(name, condition)
  if !condition
    << "FAIL writable view field: " + name
    exit(1)
  << "PASS writable view field " + name

+ BigInt
  # WBigint.length is a signed i32 at byte offset 4. Restrict the test values
  # to +/-1 so the mutated object remains a valid one-limb BigInt.
  -> __store_size_for_spec(value) (i64) i64
    $size = value

number = -1_000_000_000_000_000 ## BigInt
check("signed i32 read before store", number$size == -1)
stored_positive = number.__store_size_for_spec(1)
check("store expression returns converted value", stored_positive == 1)
check("signed i32 read after positive store", number$size == 1)
check("positive object remains valid", number == 1_000_000_000_000_000)
stored_negative = number.__store_size_for_spec(-1)
check("negative store expression remains signed", stored_negative == -1)
check("signed i32 read after negative store", number$size == -1)
check("negative object remains valid", number == -1_000_000_000_000_000)

# Pin the LLVM shape for signed/unsigned 32-bit and signed/unsigned 64-bit
# fields. Narrow stores return the post-truncation value with the declaration's
# extension rule; 64-bit stores preserve all bits directly.
i32_inst = {
  op: :view_store_field, temp: "%signed", ptr: "%self", value: "%next",
  offset: 4, size: 4, field_type: "i32"
}
u32_inst = {
  op: :view_store_field, temp: "%unsigned", ptr: "%self", value: "%next",
  offset: 8, size: 4, field_type: "u32"
}
i64_inst = {
  op: :view_store_field, temp: "%wide.s", ptr: "%self", value: "%next",
  offset: 16, size: 8, field_type: "i64"
}
u64_inst = {
  op: :view_store_field, temp: "%wide.u", ptr: "%self", value: "%next",
  offset: 24, size: 8, field_type: "u64"
}

i32_ir = render_instruction(i32_inst, nil, {}, nil, "")
u32_ir = render_instruction(u32_inst, nil, {}, nil, "")
i64_ir = render_instruction(i64_inst, nil, {}, nil, "")
u64_ir = render_instruction(u64_inst, nil, {}, nil, "")

# 140737488355312 = 0x00007FFF_FFFF_FFF0: strips the subtag nibble AND the
# top-17 tag/sign bits, because BigInt receivers ride the 0xFFF8 top-level
# tag (v4) rather than object space.
check("store masks the NaN-box tag and subtag", i32_ir.include?("%signed.ptr = and i64 %self, 140737488355312"))
check("signed i32 exact gep", i32_ir.include?("getelementptr i8, ptr %signed.bp, i64 4"))
check("signed i32 truncates", i32_ir.include?("%signed.w = trunc i64 %next to i32"))
check("signed i32 stores unaligned", i32_ir.include?("store i32 %signed.w, ptr %signed.gep, align 1"))
check("signed i32 result sign-extends", i32_ir.include?("%signed = sext i32 %signed.w to i64"))
check("unsigned u32 result zero-extends", u32_ir.include?("%unsigned = zext i32 %unsigned.w to i64"))
check("signed i64 stores all bits", i64_ir.include?("store i64 %next, ptr %wide.s.gep, align 1"))
check("signed i64 preserves raw result", i64_ir.include?("%wide.s = or i64 %next, 0"))
check("unsigned u64 stores all bits", u64_ir.include?("store i64 %next, ptr %wide.u.gep, align 1"))
check("unsigned u64 preserves raw result", u64_ir.include?("%wide.u = or i64 %next, 0"))
check("view store needs no runtime symbols", runtime_fns_for_inst(i32_inst).empty?())
check("i128 is outside one-word store width", type_size("i128") > 8)
i128_rejected = false
begin
  render_instruction({
    op: :view_store_field, temp: "%too.wide", ptr: "%self", value: "%next",
    offset: 32, size: 16, field_type: "i128"
  }, nil, {}, nil, "")
rescue error
  i128_rejected = error.to_s.include?("wider than 64 bits")
check("emitter rejects i128 whole-field store", i128_rejected)

<< "PASS writable native-data view-field stores"
