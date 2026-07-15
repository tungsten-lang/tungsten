# Focused coverage for the dedicated zero-argument inline-cache entry point.
# The source-level checks exercise native-wrapper caches, exact arity-zero
# source methods, inherited lookup, cache-key changes, nil-filled fallback to
# a larger declared arity, and a reopened class's final method definition.
# The emitter checks ensure only zero-argument calls select the narrow ABI.

use ../../compiler/lib/emitter

-> check(name, got, expected)
  if got != expected
    << "FAIL " + name + ": got=" + got.to_s() + " expected=" + expected.to_s()
    exit(1)
  << "PASS " + name

-> dynamic_size(value)
  value.size()

# Array#size and String#size are native IC entries (cache arity -1). Calling
# both through one untyped site also exercises cache replacement on type-key
# changes before returning to the original receiver type.
check("native array first", dynamic_size([1, 2, 3]), 3)
check("native array hit", dynamic_size([4, 5]), 2)
check("native string miss", dynamic_size("abcd"), 4)
check("native array replacement", dynamic_size([]), 0)

+ ZeroArgDispatchBase
  -> marker
    "base"

  -> optional(value = 73)
    value

+ ZeroArgDispatchChild < ZeroArgDispatchBase
  -> child_only
    true

+ ZeroArgDispatchOverride < ZeroArgDispatchBase
  -> marker
    "override"

-> dynamic_marker(value)
  value.marker()

-> dynamic_optional(value)
  value.optional()

base = ZeroArgDispatchBase.new()
child = ZeroArgDispatchChild.new()
override = ZeroArgDispatchOverride.new()

check("source arity zero first", dynamic_marker(base), "base")
check("source arity zero hit", dynamic_marker(base), "base")
check("inherited method miss", dynamic_marker(child), "base")
check("inherited method hit", dynamic_marker(child), "base")
check("override cache replacement", dynamic_marker(override), "override")
check("source cache replacement", dynamic_marker(base), "base")

# A zero-argument call may resolve to a method with a defaulted parameter.
# Subsequent helper hits must retain the generic dispatcher's W_NIL padding.
check("defaulted parameter first", dynamic_optional(base), 73)
check("defaulted parameter hit", dynamic_optional(base), 73)

+ ZeroArgDispatchReopened
  -> marker
    "old"

+ ZeroArgDispatchReopened
  -> marker
    "new"

reopened = ZeroArgDispatchReopened.new()
check("reopened class final definition", dynamic_marker(reopened), "new")
check("reopened class cached hit", dynamic_marker(reopened), "new")

zero_inst = {
  op: :call_method_i64,
  temp: "%zero",
  temp_args_val: "%zero.args",
  receiver: "%recv",
  method_name_val: "%name",
  args: [],
  ic_id: 2,
  src_line: nil,
  src_col: nil
}
zero_ir = render_instruction(zero_inst, nil, {}, nil, "")
check("zero call emitter helper", zero_ir.include?("@w_method_call_cached_0("), true)
check("zero call omits generic ABI", zero_ir.include?("@w_method_call_cached("), false)

one_inst = {
  op: :call_method_i64,
  temp: "%one",
  temp_args_val: "%one.args",
  receiver: "%recv",
  method_name_val: "%name",
  args: ["%arg"],
  ic_id: 3,
  src_line: nil,
  src_col: nil
}
one_ir = render_instruction(one_inst, nil, {}, nil, "")
check("nonzero call keeps generic ABI", one_ir.include?("@w_method_call_cached("), true)
check("nonzero call omits zero helper", one_ir.include?("@w_method_call_cached_0("), false)

<< "PASS zero-argument cached dispatch"
