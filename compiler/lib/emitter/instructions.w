# Emitter instruction dispatcher — keeps opcode-family workers independently
# reviewable while preserving one render_instruction entry point.

-> render_instruction(inst, string_wvs, used_ptr_ids, phi_label_redirects = nil, fp_flags = "", arm64_target = true, windows_target = false)
  rendered = render_numeric_instruction(inst, string_wvs, used_ptr_ids, phi_label_redirects, fp_flags, arm64_target, windows_target)
  if rendered != nil
    return rendered
  render_runtime_instruction(inst, string_wvs, used_ptr_ids, phi_label_redirects, fp_flags, arm64_target, windows_target)

# Append common fixed-shape instructions straight into the function buffer.
# Complex instructions retain the ordinary renderer below; this fast path is
# intentionally limited to forms whose output has no render-order side state.
-> append_call_args(out, args, arg_types = nil)
  i = 0
  while i < wire_sequence_size(args)
    if i > 0
      out << ", "
    arg_type = "i64"
    if arg_types != nil && wire_sequence_get(arg_types, i) != nil
      arg_type = wire_sequence_get(arg_types, i)
    out << arg_type
    out << " "
    out << wire_sequence_get(args, i)
    i += 1
  nil

-> append_binary_instruction(out, inst, opcode, llvm_type = "i64")
  out << wire_get(inst, :temp)
  out << " = "
  out << opcode
  out << " "
  out << llvm_type
  out << " "
  out << wire_get(inst, :lhs)
  out << ", "
  out << wire_get(inst, :rhs)
  true

-> append_instruction_direct(out, inst, phi_label_redirects = nil)
  op = wire_kind(inst)
  case op
  when :alloca_i64
    out << wire_get(inst, :ptr)
    out << " = alloca i64, align 8"
    true
  when :alloca_i128
    out << wire_get(inst, :ptr)
    out << " = alloca i128, align 16"
    true
  when :store_i64
    out << "store i64 "
    out << wire_get(inst, :value)
    out << ", ptr "
    out << wire_get(inst, :ptr)
    out << ", align 8"
    true
  when :store_i128
    out << "store i128 "
    out << wire_get(inst, :value)
    out << ", ptr "
    out << wire_get(inst, :ptr)
    out << ", align 16"
    true
  when :load_i64
    out << wire_get(inst, :temp)
    out << " = load i64, ptr "
    out << wire_get(inst, :ptr)
    out << ", align 8"
    out << range_metadata_suffix(inst, "i64")
    true
  when :load_i128
    out << wire_get(inst, :temp)
    out << " = load i128, ptr "
    out << wire_get(inst, :ptr)
    out << ", align 16"
    out << range_metadata_suffix(inst, "i128")
    true
  when :add_i64
    append_binary_instruction(out, inst, "add")
  when :sub_i64
    append_binary_instruction(out, inst, "sub")
  when :mul_i64
    append_binary_instruction(out, inst, "mul")
  when :sdiv_i64
    append_binary_instruction(out, inst, "sdiv")
  when :udiv_i64
    append_binary_instruction(out, inst, "udiv")
  when :srem_i64
    append_binary_instruction(out, inst, "srem")
  when :urem_i64
    append_binary_instruction(out, inst, "urem")
  when :and_i64
    append_binary_instruction(out, inst, "and")
  when :or_i64
    append_binary_instruction(out, inst, "or")
  when :xor_i64
    append_binary_instruction(out, inst, "xor")
  when :shl_i64
    append_binary_instruction(out, inst, "shl")
  when :ashr_i64
    append_binary_instruction(out, inst, "ashr")
  when :lshr_i64
    if wire_get(inst, :lhs) == nil
      return false
    append_binary_instruction(out, inst, "lshr")
  when :and_i1
    append_binary_instruction(out, inst, "and", "i1")
  when :or_i1
    append_binary_instruction(out, inst, "or", "i1")
  when :not_i1
    out << wire_get(inst, :temp)
    out << " = xor i1 "
    out << wire_get(inst, :value)
    out << ", true"
    true
  when :icmp_i64
    out << wire_get(inst, :temp)
    out << " = icmp "
    out << wire_get(inst, :pred)
    out << " i64 "
    out << wire_get(inst, :lhs)
    out << ", "
    out << wire_get(inst, :rhs)
    true
  when :truthy_inline
    out << wire_get(inst, :temp)
    out << " = icmp ugt i64 "
    out << wire_get(inst, :value)
    out << ", 1"
    true
  when :icmp_ne_zero
    out << wire_get(inst, :temp)
    out << " = icmp ne i64 "
    out << wire_get(inst, :value)
    out << ", 0"
    true
  when :zext_i1_i64
    out << wire_get(inst, :temp)
    out << " = zext i1 "
    out << wire_get(inst, :value)
    out << " to i64"
    true
  when :trunc_i64_i32
    out << wire_get(inst, :temp)
    out << " = trunc i64 "
    out << wire_get(inst, :value)
    out << " to i32"
    true
  when :select_i64
    out << wire_get(inst, :temp)
    out << " = select i1 "
    out << wire_get(inst, :cond)
    out << ", i64 "
    out << wire_get(inst, :then_val)
    out << ", i64 "
    out << wire_get(inst, :else_val)
    true
  when :ptr_to_i64
    out << wire_get(inst, :temp)
    out << " = ptrtoint ptr "
    out << wire_get(inst, :value)
    out << " to i64"
    true
  when :i64_to_ptr
    out << wire_get(inst, :temp)
    out << " = inttoptr i64 "
    out << wire_get(inst, :value)
    out << " to ptr"
    true
  when :gep_array
    out << wire_get(inst, :temp)
    out << " = getelementptr inbounds \["
    out << wire_get(inst, :count).to_s()
    out << " x i64], ptr "
    out << wire_get(inst, :base)
    out << ", i32 0, i32 "
    out << wire_get(inst, :index).to_s()
    true
  when :store_ptr
    out << "store i64 "
    out << wire_get(inst, :value)
    out << ", ptr "
    out << wire_get(inst, :dest)
    out << ", align 8"
    true
  when :load_ptr
    out << wire_get(inst, :temp)
    out << " = load i64, ptr "
    out << wire_get(inst, :ptr)
    out << ", align 8"
    true
  when :call_direct_i64
    name = wire_get(inst, :name)
    if name in ("w_node_kind_extern" "w_is_node_extern" "w_node_alloc" "w_node_field_load" "w_node_field_store")
      return false
    out << wire_get(inst, :temp)
    out << " = "
    out << call_prefix(inst)
    out << " i64 @"
    out << name
    out << "("
    append_call_args(out, wire_get(inst, :args), wire_get(inst, :arg_types))
    out << ")"
    out << known_call_range_metadata_suffix(inst, "i64")
    if wire_get(inst, :src_line) != nil && wire_get(inst, :loc_site_id) != nil
      ret_lbl = "csd." + wire_get(inst, :loc_site_id).to_s() + ".ret"
      out << "\n  br label %"
      out << ret_lbl
      out << "\n"
      out << ret_lbl
      out << ":"
    true
  when :call_direct_i64_ptr1
    out << wire_get(inst, :temp)
    out << " = "
    out << call_prefix(inst)
    out << " i64 @"
    out << wire_get(inst, :name)
    out << "(ptr "
    out << wire_get(inst, :arg)
    out << ")"
    true
  when :call_direct_void
    out << call_prefix(inst)
    out << " void @"
    out << wire_get(inst, :name)
    out << "("
    append_call_args(out, wire_get(inst, :args), wire_get(inst, :arg_types))
    out << ")"
    if wire_get(inst, :src_line) != nil && wire_get(inst, :loc_site_id) != nil
      ret_lbl = "csd." + wire_get(inst, :loc_site_id).to_s() + ".ret"
      out << "\n  br label %"
      out << ret_lbl
      out << "\n"
      out << ret_lbl
      out << ":"
    true
  when :br
    unroll_count = wire_get(inst, :unroll_count)
    if wire_get(inst, :novec) == true || (unroll_count != nil && unroll_count > 0)
      return false
    out << "br label %"
    out << wire_get(inst, :label)
    true
  when :cond_br
    out << "br i1 "
    out << wire_get(inst, :cond)
    out << ", label %"
    out << wire_get(inst, :then_label)
    out << ", label %"
    out << wire_get(inst, :else_label)
    if wire_get(inst, :prof) == :likely
      out << ", !prof !31411"
    elsif wire_get(inst, :prof) == :unlikely
      out << ", !prof !31412"
    true
  when :ret_i64
    out << "ret i64 "
    value = wire_get(inst, :value)
    out << (value == nil ? "0" : value.to_s())
    true
  when :ret_i32
    out << "ret i32 "
    value = wire_get(inst, :value)
    out << (value == nil ? "0" : value.to_s())
    true
  when :ret_void
    out << "ret void"
    true
  when :unreachable
    out << "unreachable"
    true
  when :scope_push, :scope_pop
    out << "; scope "
    out << op.to_s()
    true
  else
    false
