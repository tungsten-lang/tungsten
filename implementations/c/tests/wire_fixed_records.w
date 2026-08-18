function_fields = [
  :name, :original_name, :params, :extra_params, :return_type, :is_toplevel,
  :blocks, :var_slots, :var_slot_types, :next_temp, :next_label, :next_var,
  :next_scope, :loop_stack, :eh_depth, :ensure_stack, :case_stack,
  :scope_recycle_stack, :recycle_vars, :dynamic_method_calls,
  :dynamic_method_call_keys, :reflective_method_access, :is_memoized,
  :exit_label, :result_slot
]
block_fields = [:label, :instructions]

f = ccall_rawargs("w_wire_function_record_new", function_fields,
                  "probe", [], "i64", false, [])
b = ccall_rawargs("w_wire_block_record_new", block_fields, "__entry")
f[:blocks].push(b)

<< f[:name]
<< f[:original_name]
<< f[:next_temp]
<< f[:blocks].size()
<< f[:blocks][0][:label]
<< f[:blocks][0][:instructions].size()

sequence = ccall_rawargs("w_wire_sequence_from_array", ["i64"])
<< type(sequence)
<< sequence.size()
<< sequence[0]
