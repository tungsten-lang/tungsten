# Emitter instruction dispatcher — keeps opcode-family workers independently
# reviewable while preserving one render_instruction entry point.

-> render_instruction(inst, string_wvs, used_ptr_ids, phi_label_redirects = nil, fp_flags = "", arm64_target = true, windows_target = false, volatile_slots = false, emit_blockaddress_sites = true)
  rendered = render_runtime_instruction(inst, string_wvs, used_ptr_ids, phi_label_redirects, fp_flags, arm64_target, windows_target, volatile_slots, emit_blockaddress_sites)
  if rendered != nil
    return rendered
  rendered = render_numeric_instruction(inst, string_wvs, used_ptr_ids, phi_label_redirects, fp_flags, arm64_target, windows_target, volatile_slots)
  if rendered != nil
    return rendered
  "; UNKNOWN WIRE OP: " + wire_kind(inst).to_s()

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

-> append_call_method_i64(out, inst, emit_blockaddress_sites)
  args = wire_get(inst, :args)
  argc = wire_sequence_size(args)
  t = wire_get(inst, :temp)
  ic_id = wire_get(inst, :ic_id).to_s()
  name_val = wire_get(inst, :method_name_val)
  recv = wire_get(inst, :receiver)
  out << t
  out << ".ic = getelementptr inbounds \[24 x i8], ptr @.ic, i64 "
  out << ic_id
  out << "\n  "
  dv_temp = t
  devirt_fn = wire_get(inst, :devirt_fn)
  construct_fn = wire_get(inst, :construct_fn)
  if devirt_fn != nil
    out << t
    out << ".same = call i1 @__w_guard_class(i64 "
    out << recv
    out << ", ptr @class."
    out << llvm_safe_name(wire_get(inst, :devirt_class).gsub(":", "__"))
    out << ")\n  br i1 "
    out << t
    out << ".same, label %dv."
    out << ic_id
    out << ".d, label %dv."
    out << ic_id
    out << ".s\ndv."
    out << ic_id
    out << ".d:\n  "
    out << t
    out << ".dv = call i64 @"
    out << devirt_fn
    out << "(i64 "
    out << recv
    di = 0
    while di < argc
      out << ", i64 "
      out << wire_sequence_get(args, di)
      di += 1
    out << ")\n  br label %dv."
    out << ic_id
    out << ".done\ndv."
    out << ic_id
    out << ".s:\n  "
    dv_temp = t + ".sv"
  elsif construct_fn != nil
    out << t
    out << ".cw = load i64, ptr @class."
    out << llvm_safe_name(wire_get(inst, :construct_class).gsub(":", "__"))
    out << "\n  "
    out << t
    out << ".same = icmp eq i64 "
    out << recv
    out << ", "
    out << t
    out << ".cw\n  br i1 "
    out << t
    out << ".same, label %dv."
    out << ic_id
    out << ".d, label %dv."
    out << ic_id
    out << ".s\ndv."
    out << ic_id
    out << ".d:\n  "
    allocator = wire_get(inst, :construct_recycle) == true ? "w_object_recycle_or_new" : "w_object_new"
    out << t
    out << ".dv = call i64 @"
    out << allocator
    out << "(i64 "
    out << recv
    out << ")\n  "
    out << t
    out << ".init = call i64 @"
    out << construct_fn
    out << "(i64 "
    out << t
    out << ".dv"
    di = 0
    while di < argc
      out << ", i64 "
      out << wire_sequence_get(args, di)
      di += 1
    out << ")\n  br label %dv."
    out << ic_id
    out << ".done\ndv."
    out << ic_id
    out << ".s:\n  "
    dv_temp = t + ".sv"
  src_line = wire_get(inst, :src_line)
  call_keyword = src_line != nil ? "notail call" : "call"
  if fast_size_call?(inst)
    out << dv_temp
    out << " = "
    out << call_keyword
    out << " i64 @w_fast_size(i64 "
    out << recv
    out << ", ptr "
    out << t
    out << ".ic)"
  elsif fast_to_s_call?(inst)
    out << dv_temp
    out << " = "
    out << call_keyword
    out << " i64 @w_fast_to_s(i64 "
    out << recv
    out << ", ptr "
    out << t
    out << ".ic)"
  elsif argc == 0
    out << dv_temp
    out << " = "
    out << call_keyword
    out << " i64 @w_method_call_cached_0(i64 "
    out << recv
    out << ", i64 "
    out << name_val
    out << ", ptr "
    out << t
    out << ".ic)"
  elsif sym_idx_get_call?(inst)
    out << dv_temp
    out << " = "
    out << call_keyword
    out << " i64 @w_fast_sym_get(i64 "
    out << recv
    out << ", i64 "
    out << wire_sequence_get(args, 0)
    out << ", ptr "
    out << t
    out << ".ic)"
  elsif sym_idx_set_call?(inst)
    out << dv_temp
    out << " = "
    out << call_keyword
    out << " i64 @w_fast_sym_set(i64 "
    out << recv
    out << ", i64 "
    out << wire_sequence_get(args, 0)
    out << ", i64 "
    out << wire_sequence_get(args, 1)
    out << ", ptr "
    out << t
    out << ".ic)"
  elsif fast_idx_get_call?(inst)
    out << dv_temp
    out << " = "
    out << call_keyword
    out << " i64 @w_fast_idx_get(i64 "
    out << recv
    out << ", i64 "
    out << wire_sequence_get(args, 0)
    out << ", ptr "
    out << t
    out << ".ic)"
  elsif fast_idx_set_call?(inst)
    out << dv_temp
    out << " = "
    out << call_keyword
    out << " i64 @w_fast_idx_set(i64 "
    out << recv
    out << ", i64 "
    out << wire_sequence_get(args, 0)
    out << ", i64 "
    out << wire_sequence_get(args, 1)
    out << ", ptr "
    out << t
    out << ".ic)"
  elsif fast_push_call?(inst)
    out << dv_temp
    out << " = "
    out << call_keyword
    out << " i64 @w_fast_push(i64 "
    out << recv
    out << ", i64 "
    out << wire_sequence_get(args, 0)
    out << ", ptr "
    out << t
    out << ".ic)"
  elsif scalar_source_one_call?(inst)
    out << dv_temp
    out << " = "
    out << call_keyword
    out << " i64 @w_method_call_cached_1(i64 "
    out << recv
    out << ", i64 "
    out << name_val
    out << ", i64 "
    out << wire_sequence_get(args, 0)
    out << ", ptr "
    out << t
    out << ".ic)"
  elsif scalar_source_two_call?(inst)
    out << dv_temp
    out << " = "
    out << call_keyword
    out << " i64 @w_method_call_cached_2(i64 "
    out << recv
    out << ", i64 "
    out << name_val
    out << ", i64 "
    out << wire_sequence_get(args, 0)
    out << ", i64 "
    out << wire_sequence_get(args, 1)
    out << ", ptr "
    out << t
    out << ".ic)"
  elsif argc == 1
    out << dv_temp
    out << " = "
    out << call_keyword
    out << " i64 @w_method_call_cached_1_any(i64 "
    out << recv
    out << ", i64 "
    out << name_val
    out << ", i64 "
    out << wire_sequence_get(args, 0)
    out << ", ptr "
    out << t
    out << ".ic)"
  elsif argc == 2
    out << dv_temp
    out << " = "
    out << call_keyword
    out << " i64 @w_method_call_cached_2_any(i64 "
    out << recv
    out << ", i64 "
    out << name_val
    out << ", i64 "
    out << wire_sequence_get(args, 0)
    out << ", i64 "
    out << wire_sequence_get(args, 1)
    out << ", ptr "
    out << t
    out << ".ic)"
  elsif argc == 3
    out << dv_temp
    out << " = "
    out << call_keyword
    out << " i64 @w_method_call_cached_3_any(i64 "
    out << recv
    out << ", i64 "
    out << name_val
    out << ", i64 "
    out << wire_sequence_get(args, 0)
    out << ", i64 "
    out << wire_sequence_get(args, 1)
    out << ", i64 "
    out << wire_sequence_get(args, 2)
    out << ", ptr "
    out << t
    out << ".ic)"
  else
    t_args = wire_get(inst, :temp_args_val)
    i = 0
    while i < argc
      if i == 0
        out << "store i64 "
        out << wire_sequence_get(args, i)
        out << ", ptr %__mcall_args, align 8\n  "
      else
        idx_s = i.to_s()
        out << t_args
        out << "."
        out << idx_s
        out << " = getelementptr inbounds i64, ptr %__mcall_args, i32 "
        out << idx_s
        out << "\n  store i64 "
        out << wire_sequence_get(args, i)
        out << ", ptr "
        out << t_args
        out << "."
        out << idx_s
        out << ", align 8\n  "
      i += 1
    out << dv_temp
    out << " = "
    out << call_keyword
    out << " i64 @w_method_call_cached(i64 "
    out << recv
    out << ", i64 "
    out << name_val
    out << ", ptr %__mcall_args, i32 "
    out << argc.to_s()
    out << ", ptr "
    out << t
    out << ".ic)"
  if emit_blockaddress_sites && src_line != nil
    out << "\n  br label %cs."
    out << ic_id
    out << ".ret\ncs."
    out << ic_id
    out << ".ret:"
  if devirt_fn != nil || construct_fn != nil
    out << "\n  br label %dv."
    out << ic_id
    out << ".done\ndv."
    out << ic_id
    out << ".done:\n  "
    out << t
    out << " = phi i64 \["
    out << t
    out << ".dv, %dv."
    out << ic_id
    out << ".d], \["
    out << t
    out << ".sv, %"
    if emit_blockaddress_sites && src_line != nil
      out << "cs."
      out << ic_id
      out << ".ret"
    else
      out << "dv."
      out << ic_id
      out << ".s"
    out << "]"
  true

-> append_typed_array_get_inline(out, inst)
  bits = wire_get(inst, :bits)
  if bits == nil
    bits = 64
  if bits == 4
    return false
  t = wire_get(inst, :temp)
  s = wire_get(inst, :s)
  s0 = wire_sequence_get(s, 0)
  s1 = wire_sequence_get(s, 1)
  s2 = wire_sequence_get(s, 2)
  s3 = wire_sequence_get(s, 3)
  s4 = wire_sequence_get(s, 4)
  s5 = wire_sequence_get(s, 5)
  s6 = wire_sequence_get(s, 6)
  s7 = wire_sequence_get(s, 7)
  s8 = wire_sequence_get(s, 8)
  s9 = wire_sequence_get(s, 9)
  arr = wire_get(inst, :arr)
  idx = wire_get(inst, :idx)
  idx_raw = wire_get(inst, :idx_raw)
  signed = wire_get(inst, :signed)
  if signed == nil
    signed = true
  th = tbaa_header_suffix()
  te = tbaa_elem_suffix()
  asuf = alias_scope_suffix(inst)
  out << s0
  out << " = and i64 "
  out << arr
  out << ", 140737488355312\n  "
  out << s1
  out << " = inttoptr i64 "
  out << s0
  out << " to ptr\n  "
  out << s2
  out << " = getelementptr i8, ptr "
  out << s1
  out << ", i64 16\n  "
  out << s3
  out << " = load ptr, ptr "
  out << s2
  out << ", align 8"
  out << th
  out << "\n  "
  out << s4
  out << " = getelementptr i8, ptr "
  out << s1
  out << ", i64 4\n  "
  out << s5
  out << ".raw32 = load i32, ptr "
  out << s4
  out << ", align 4"
  out << th
  out << "\n  "
  out << s5
  out << " = sext i32 "
  out << s5
  out << ".raw32 to i64\n  "
  if idx_raw == true
    out << s8
    out << " = add i64 "
    out << s5
    out << ", "
    out << idx
    out << "\n  "
  else
    out << s6
    out << " = shl i64 "
    out << idx
    out << ", 16\n  "
    out << s7
    out << " = ashr i64 "
    out << s6
    out << ", 16\n  "
    out << s8
    out << " = add i64 "
    out << s5
    out << ", "
    out << s7
    out << "\n  "
  if bits == 64 || (bits != 32 && bits != 16 && bits != 8)
    out << s9
    out << " = getelementptr i64, ptr "
    out << s3
    out << ", i64 "
    out << s8
    out << "\n  "
    out << t
    out << " = load i64, ptr "
    out << s9
    out << ", align 8"
    out << te
    out << asuf
  else
    bstr = bits.to_s()
    astr = bits == 32 ? "4" : (bits == 16 ? "2" : "1")
    out << s9
    out << " = getelementptr i"
    out << bstr
    out << ", ptr "
    out << s3
    out << ", i64 "
    out << s8
    out << "\n  "
    out << t
    out << ".raw = load i"
    out << bstr
    out << ", ptr "
    out << s9
    out << ", align "
    out << astr
    out << te
    out << asuf
    out << "\n  "
    out << t
    out << (signed == true ? " = sext i" : " = zext i")
    out << bstr
    out << " "
    out << t
    out << ".raw to i64"
  true

-> append_typed_array_set_inline(out, inst)
  bits = wire_get(inst, :bits)
  if bits == nil
    bits = 64
  if bits == 4
    return false
  t = wire_get(inst, :temp)
  s = wire_get(inst, :s)
  s0 = wire_sequence_get(s, 0)
  s1 = wire_sequence_get(s, 1)
  s2 = wire_sequence_get(s, 2)
  s3 = wire_sequence_get(s, 3)
  s4 = wire_sequence_get(s, 4)
  s5 = wire_sequence_get(s, 5)
  s6 = wire_sequence_get(s, 6)
  s7 = wire_sequence_get(s, 7)
  s8 = wire_sequence_get(s, 8)
  s9 = wire_sequence_get(s, 9)
  arr = wire_get(inst, :arr)
  idx = wire_get(inst, :idx)
  idx_raw = wire_get(inst, :idx_raw)
  val = wire_get(inst, :value)
  th = tbaa_header_suffix()
  te = tbaa_elem_suffix()
  asuf = alias_scope_suffix(inst)
  out << s0
  out << " = and i64 "
  out << arr
  out << ", 140737488355312\n  "
  out << s1
  out << " = inttoptr i64 "
  out << s0
  out << " to ptr\n  "
  out << s2
  out << " = getelementptr i8, ptr "
  out << s1
  out << ", i64 16\n  "
  out << s3
  out << " = load ptr, ptr "
  out << s2
  out << ", align 8"
  out << th
  out << "\n  "
  out << s4
  out << " = getelementptr i8, ptr "
  out << s1
  out << ", i64 4\n  "
  out << s5
  out << ".raw32 = load i32, ptr "
  out << s4
  out << ", align 4"
  out << th
  out << "\n  "
  out << s5
  out << " = sext i32 "
  out << s5
  out << ".raw32 to i64\n  "
  if idx_raw == true
    out << s6
    out << " = add i64 0, 0\n  "
    out << s7
    out << " = add i64 "
    out << idx
    out << ", 0\n  "
    out << s8
    out << " = add i64 "
    out << s5
    out << ", "
    out << idx
    out << "\n  "
  else
    out << s6
    out << " = shl i64 "
    out << idx
    out << ", 16\n  "
    out << s7
    out << " = ashr i64 "
    out << s6
    out << ", 16\n  "
    out << s8
    out << " = add i64 "
    out << s5
    out << ", "
    out << s7
    out << "\n  "
  if bits == 64 || (bits != 32 && bits != 16 && bits != 8)
    out << s9
    out << " = getelementptr i64, ptr "
    out << s3
    out << ", i64 "
    out << s8
    out << "\n  store i64 "
    out << val
    out << ", ptr "
    out << s9
    out << ", align 8"
    out << te
    out << asuf
    out << "\n  "
  else
    bstr = bits.to_s()
    astr = bits == 32 ? "4" : (bits == 16 ? "2" : "1")
    out << s9
    out << " = getelementptr i"
    out << bstr
    out << ", ptr "
    out << s3
    out << ", i64 "
    out << s8
    out << "\n  "
    out << t
    out << ".trunc = trunc i64 "
    out << val
    out << " to i"
    out << bstr
    out << "\n  store i"
    out << bstr
    out << " "
    out << t
    out << ".trunc, ptr "
    out << s9
    out << ", align "
    out << astr
    out << te
    out << asuf
    out << "\n  "
  out << t
  out << " = add i64 "
  out << val
  out << ", 0"
  true

-> append_class_add_method_direct(out, inst, is_static, string_wvs, used_ptr_ids)
  add_fn = is_static ? "w_class_add_static_method_wv" : "w_class_add_method_wv"
  arity_s = wire_get(inst, :arity).to_s()
  splat_idx = wire_get(inst, :splat_index)
  min_arity = wire_get(inst, :min_arity)
  mode = 0
  if splat_idx != nil && splat_idx >= 0
    add_fn = is_static ? "w_class_add_static_method_splat_wv" : "w_class_add_method_splat_wv"
    mode = 1
  elsif min_arity != nil && min_arity < wire_get(inst, :arity)
    add_fn = is_static ? "w_class_add_static_method_range_wv" : "w_class_add_method_range_wv"
    mode = 2
  mid = wire_get(inst, :method_str_id)
  swv = nil
  if string_wvs != nil
    swv = string_wvs[mid]
  ct = wire_get(inst, :class_temp)
  if swv == nil
    if used_ptr_ids == nil
      return false
    used_ptr_ids[mid] = true
    sfx = is_static ? ".smname" : ".mname"
    out << ct
    out << sfx
    out << " = getelementptr inbounds \["
    out << wire_get(inst, :method_byte_len).to_s()
    out << " x i8], ptr @.str."
    out << mid.to_s()
    out << ", i32 0, i32 0\n  "
    out << ct
    out << sfx
    out << ".wv = call i64 @w_string(ptr "
    out << ct
    out << sfx
    out << ")\n  call void @"
    out << add_fn
    out << "(i64 "
    out << ct
    out << ", i64 "
    out << ct
    out << sfx
    out << ".wv, ptr @"
  else
    out << "call void @"
    out << add_fn
    out << "(i64 "
    out << ct
    out << ", i64 "
    out << llvm_wvalue_literal(swv)
    out << ", ptr @"
  out << wire_get(inst, :fn_name)
  out << ", i32 "
  out << arity_s
  if mode == 1
    out << ", i32 "
    out << min_arity.to_s()
    out << ", i32 "
    out << splat_idx.to_s()
  elsif mode == 2
    out << ", i32 "
    out << min_arity.to_s()
  out << ")"
  true

-> append_instruction_direct(out, inst, phi_label_redirects = nil, string_wvs = nil, used_ptr_ids = nil, emit_blockaddress_sites = true)
  op = wire_kind(inst)

  # `case` lowers to equality checks, not a jump table. Keep the direct
  # renderer ordered by observed WIRE frequency from the compiler, parser,
  # lexer, formatter, content-hash, build-command, and emitter workloads.
  case op
  when :call_direct_i64
    name = wire_get(inst, :name)
    if name.size() >= 6 && name.byte_at(0) == 119 && name.byte_at(1) == 95
      if name in ("w_node_kind_extern" "w_is_node_extern" "w_node_alloc" "w_node_field_load" "w_node_field_store")
        return false
      # Narrow-parameter constructors need operand truncation (ordinary renderer).
      if narrow_runtime_param_types(name) != nil
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
    if emit_blockaddress_sites && wire_get(inst, :src_line) != nil && wire_get(inst, :loc_site_id) != nil
      ret_lbl = "csd." + wire_get(inst, :loc_site_id).to_s() + ".ret"
      out << "\n  br label %"
      out << ret_lbl
      out << "\n"
      out << ret_lbl
      out << ":"
    true
  when :load_i64
    out << wire_get(inst, :temp)
    out << " = load i64, ptr "
    out << wire_get(inst, :ptr)
    out << ", align 8"
    out << range_metadata_suffix(inst, "i64")
    true
  when :store_i64
    out << "store i64 "
    out << wire_get(inst, :value)
    out << ", ptr "
    out << wire_get(inst, :ptr)
    out << ", align 8"
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
  when :call_method_i64
    append_call_method_i64(out, inst, emit_blockaddress_sites)
  when :call_loc_set_col
    if used_ptr_ids == nil
      return false
    fid = wire_get(inst, :file_str_id)
    used_ptr_ids[fid] = true
    tp = wire_get(inst, :temp_ptr)
    out << tp
    out << " = getelementptr inbounds \["
    out << wire_get(inst, :file_byte_len).to_s()
    out << " x i8], ptr @.str."
    out << fid.to_s()
    out << ", i32 0, i32 0\n  call void @__w_loc_set_col(ptr "
    out << tp
    out << ", i32 "
    out << wire_get(inst, :line).to_s()
    out << ", i32 "
    out << wire_get(inst, :col).to_s()
    out << ")"
    true
  when :truthy_inline
    out << wire_get(inst, :temp)
    out << " = icmp ugt i64 "
    out << wire_get(inst, :value)
    out << ", 1"
    true
  when :phi_ssa
    incoming = wire_get(inst, :incoming)
    out << wire_get(inst, :temp)
    out << " = phi i64 "
    ii = 0
    n_inc = wire_sequence_size(incoming)
    while ii < n_inc
      if ii > 0
        out << ", "
      label = redirect_phi_label(wire_sequence_get(incoming, ii + 1), phi_label_redirects)
      out << "\[ "
      out << wire_sequence_get(incoming, ii)
      out << ", %"
      out << label
      out << " ]"
      ii += 2
    true
  when :string_i64
    sid = wire_get(inst, :string_id)
    swv = nil
    if string_wvs != nil
      swv = string_wvs[sid]
    if swv != nil
      out << wire_get(inst, :temp)
      out << " = or i64 0, "
      out << llvm_wvalue_literal(swv)
      return true
    if used_ptr_ids == nil
      return false
    used_ptr_ids[sid] = true
    tp = wire_get(inst, :temp_ptr)
    out << tp
    out << " = getelementptr inbounds \["
    out << wire_get(inst, :byte_len).to_s()
    out << " x i8], ptr @.str."
    out << sid.to_s()
    out << ", i32 0, i32 0\n  "
    out << wire_get(inst, :temp)
    out << " = call i64 @w_string(ptr "
    out << tp
    out << ")"
    true
  when :symbol_i64
    sid = wire_get(inst, :string_id)
    swv = nil
    if string_wvs != nil
      swv = string_wvs[sid]
    if swv != nil
      out << wire_get(inst, :temp)
      out << " = or i64 "
      out << llvm_wvalue_literal(swv)
      out << ", 1"
      return true
    if used_ptr_ids == nil
      return false
    used_ptr_ids[sid] = true
    tp = wire_get(inst, :temp_ptr)
    t = wire_get(inst, :temp)
    out << tp
    out << " = getelementptr inbounds \["
    out << wire_get(inst, :byte_len).to_s()
    out << " x i8], ptr @.str."
    out << sid.to_s()
    out << ", i32 0, i32 0\n  "
    out << t
    out << ".s = call i64 @w_string(ptr "
    out << tp
    out << ")\n  "
    out << t
    out << " = call i64 @w_str_to_sym(i64 "
    out << t
    out << ".s)"
    true
  when :nanbox_int
    raw_str = wire_get(inst, :raw).to_s()
    ch = raw_str.slice(0, 1)
    if ch != nil && (ch == "-" || (ch >= "0" && ch <= "9"))
      wval = (raw_str.to_i() & 281474976710655) | -1688849860263936
      out << wire_get(inst, :temp)
      out << " = or i64 0, "
      out << llvm_wvalue_literal(wval)
      return true
    out << wire_get(inst, :temp_masked)
    out << " = and i64 "
    out << raw_str
    out << ", "
    out << machine_i64_text(w_payload_mask)
    out << "\n  "
    out << wire_get(inst, :temp)
    out << " = or i64 "
    out << wire_get(inst, :temp_masked)
    out << ", "
    out << machine_i64_text(w_tag_int)
    true
  when :nanbox_bool
    out << wire_get(inst, :temp)
    out << " = select i1 "
    out << wire_get(inst, :value)
    out << ", i64 "
    out << w_true.to_s()
    out << ", i64 "
    out << w_false.to_s()
    true
  when :load_class
    out << wire_get(inst, :temp)
    out << " = load i64, ptr @class."
    out << llvm_safe_name(wire_get(inst, :class_name).gsub(":", "__"))
    true
  when :ivar_get_idx
    t = wire_get(inst, :temp)
    out << t
    out << ".raw = and i64 "
    out << wire_get(inst, :self_reg)
    out << ", -16\n  "
    out << t
    out << ".ptr = inttoptr i64 "
    out << t
    out << ".raw to ptr\n  "
    out << t
    out << ".gep = getelementptr i8, ptr "
    out << t
    out << ".ptr, i64 "
    out << (8 + wire_get(inst, :offset) * 8).to_s()
    out << "\n  "
    out << t
    out << " = load i64, ptr "
    out << t
    out << ".gep, align 8"
    out << tbaa_ivar_suffix()
    true
  when :class_add_method
    append_class_add_method_direct(out, inst, false, string_wvs, used_ptr_ids)
  when :typed_array_get_inline
    append_typed_array_get_inline(out, inst)
  when :load_global
    t = wire_get(inst, :type)
    out << wire_get(inst, :temp)
    out << " = load "
    out << (t == nil ? "i64" : t)
    out << ", ptr @global."
    out << llvm_safe_name(wire_get(inst, :name))
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
  when :scope_push, :scope_pop
    out << "; scope "
    out << op.to_s()
    true
  when :ret_i64
    out << "ret i64 "
    value = wire_get(inst, :value)
    out << (value == nil ? "0" : value.to_s())
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
  when :ivar_set_idx
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    out << t
    out << ".raw = and i64 "
    out << wire_get(inst, :self_reg)
    out << ", -16\n  "
    out << t
    out << ".ptr = inttoptr i64 "
    out << t
    out << ".raw to ptr\n  "
    out << t
    out << ".gep = getelementptr i8, ptr "
    out << t
    out << ".ptr, i64 "
    out << (8 + wire_get(inst, :offset) * 8).to_s()
    out << "\n  store i64 "
    out << v
    out << ", ptr "
    out << t
    out << ".gep, align 8"
    out << tbaa_ivar_suffix()
    out << "\n  "
    out << t
    out << " = add i64 "
    out << v
    out << ", 0"
    true
  when :closure_new
    ba = wire_get(inst, :block_arity)
    out << wire_get(inst, :temp)
    out << " = call i64 @w_closure_new_a(ptr @"
    out << wire_get(inst, :fn_name)
    out << ", ptr "
    out << wire_get(inst, :captures_ptr)
    out << ", i32 "
    out << wire_get(inst, :capture_count).to_s()
    out << ", i32 "
    out << (ba == nil ? "0" : ba.to_s())
    out << ")"
    true
  when :alloca_array
    out << wire_get(inst, :ptr)
    out << " = alloca \["
    out << wire_get(inst, :count).to_s()
    out << " x i64], align 8"
    true
  when :store_global
    t = wire_get(inst, :type)
    out << "store "
    out << (t == nil ? "i64" : t)
    out << " "
    out << wire_get(inst, :value)
    out << ", ptr @global."
    out << llvm_safe_name(wire_get(inst, :name))
    true
  when :array_size_raw
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    lbl = "asz." + t.slice(1, t.size() - 1)
    out << t
    out << ".tg = lshr i64 "
    out << v
    out << ", 45\n  "
    out << t
    out << ".isb = icmp eq i64 "
    out << t
    out << ".tg, 524278\n  br i1 "
    out << t
    out << ".isb, label %"
    out << lbl
    out << ".body, label %"
    out << lbl
    out << ".arr\n"
    out << lbl
    out << ".body:\n  "
    out << t
    out << ".bl = and i64 "
    out << v
    out << ", 2097151\n  br label %"
    out << lbl
    out << ".done\n"
    out << lbl
    out << ".arr:\n  "
    out << t
    out << ".hdr = and i64 "
    out << v
    out << ", 140737488355312\n  "
    out << t
    out << ".hp = inttoptr i64 "
    out << t
    out << ".hdr to ptr\n  "
    out << t
    out << ".szp = getelementptr i8, ptr "
    out << t
    out << ".hp, i64 8\n  "
    out << t
    out << ".sz32 = load i32, ptr "
    out << t
    out << ".szp, align 4"
    out << tbaa_header_suffix()
    out << "\n  "
    out << t
    out << ".sz = sext i32 "
    out << t
    out << ".sz32 to i64\n  br label %"
    out << lbl
    out << ".done\n"
    out << lbl
    out << ".done:\n  "
    out << t
    out << " = phi i64 \["
    out << t
    out << ".bl, %"
    out << lbl
    out << ".body], \["
    out << t
    out << ".sz, %"
    out << lbl
    out << ".arr]"
    true
  when :typed_array_set_inline
    append_typed_array_set_inline(out, inst)
  when :class_add_static_method
    append_class_add_method_direct(out, inst, true, string_wvs, used_ptr_ids)
  when :free_value
    out << "call void @w_value_free(i64 "
    out << wire_get(inst, :value)
    out << ")"
    true
  when :recycle_object
    out << "call void @w_object_recycle(i64 "
    out << wire_get(inst, :value)
    out << ")"
    true
  when :puts_i64
    t = wire_get(inst, :temp)
    if t != nil
      out << t
      out << " = "
    out << "call i64 @w_puts(i64 "
    out << wire_get(inst, :value)
    out << ")"
    true
  when :print_i64
    t = wire_get(inst, :temp)
    if t != nil
      out << t
      out << " = "
    out << "call i64 @w_print(i64 "
    out << wire_get(inst, :value)
    out << ")"
    true
  when :nanunbox_int
    ts = wire_get(inst, :temp_shl)
    out << ts
    out << " = shl i64 "
    out << wire_get(inst, :boxed)
    out << ", 16\n  "
    out << wire_get(inst, :temp)
    out << " = ashr i64 "
    out << ts
    out << ", 16"
    true
  when :nanbox_float
    tb = wire_get(inst, :temp_bits)
    out << tb
    out << " = bitcast double "
    out << wire_get(inst, :raw)
    out << " to i64\n  "
    out << wire_get(inst, :temp)
    out << " = add i64 "
    out << tb
    out << ", "
    out << machine_i64_text(w_double_bias)
    true
  when :nanunbox_float
    tb = wire_get(inst, :temp_bits)
    out << tb
    out << " = sub i64 "
    out << wire_get(inst, :boxed)
    out << ", "
    out << machine_i64_text(w_double_bias)
    out << "\n  "
    out << wire_get(inst, :temp)
    out << " = bitcast i64 "
    out << tb
    out << " to double"
    true
  when :ta_size_raw
    t = wire_get(inst, :temp)
    out << t
    out << ".hdr = and i64 "
    out << wire_get(inst, :value)
    out << ", 140737488355312\n  "
    out << t
    out << ".hp = inttoptr i64 "
    out << t
    out << ".hdr to ptr\n  "
    out << t
    out << ".szp = getelementptr i8, ptr "
    out << t
    out << ".hp, i64 8\n  "
    out << t
    out << ".sz32 = load i32, ptr "
    out << t
    out << ".szp, align 4"
    out << tbaa_header_suffix()
    out << "\n  "
    out << t
    out << " = sext i32 "
    out << t
    out << ".sz32 to i64"
    true
  when :load_double
    out << wire_get(inst, :temp)
    out << " = load double, ptr "
    out << wire_get(inst, :ptr)
    out << ", align 8"
    true
  when :store_double
    out << "store double "
    out << wire_get(inst, :value)
    out << ", ptr "
    out << wire_get(inst, :ptr)
    out << ", align 8"
    true
  when :load_float
    out << wire_get(inst, :temp)
    out << " = load float, ptr "
    out << wire_get(inst, :ptr)
    out << ", align 4"
    true
  when :store_float
    out << "store float "
    out << wire_get(inst, :value)
    out << ", ptr "
    out << wire_get(inst, :ptr)
    out << ", align 4"
    true
  when :class_store
    out << "store i64 "
    out << wire_get(inst, :value)
    out << ", ptr @class."
    out << llvm_safe_name(wire_get(inst, :class_name).gsub(":", "__"))
    true
  when :load_cvar
    out << wire_get(inst, :temp)
    out << " = load i64, ptr @cvar."
    out << llvm_safe_name(wire_get(inst, :cvar_key).gsub(":", "__"))
    true
  when :store_cvar
    out << "store i64 "
    out << wire_get(inst, :value)
    out << ", ptr @cvar."
    out << llvm_safe_name(wire_get(inst, :cvar_key).gsub(":", "__"))
    true
  when :null_ptr
    out << wire_get(inst, :temp)
    out << " = inttoptr i64 0 to ptr"
    true
  when :icmp_ne_i64
    out << wire_get(inst, :temp)
    out << " = icmp ne i64 "
    out << wire_get(inst, :lhs)
    out << ", "
    out << wire_get(inst, :rhs)
    true
  when :phi_i64
    a_label = redirect_phi_label(wire_get(inst, :a_label), phi_label_redirects)
    b_label = redirect_phi_label(wire_get(inst, :b_label), phi_label_redirects)
    out << wire_get(inst, :temp)
    out << " = phi i64 \[ "
    out << wire_get(inst, :a_value)
    out << ", %"
    out << a_label
    out << " ], \[ "
    out << wire_get(inst, :b_value)
    out << ", %"
    out << b_label
    out << " ]"
    true
  when :phi_i1
    a_label = redirect_phi_label(wire_get(inst, :a_label), phi_label_redirects)
    b_label = redirect_phi_label(wire_get(inst, :b_label), phi_label_redirects)
    out << wire_get(inst, :temp)
    out << " = phi i1 \[ "
    out << wire_get(inst, :a_value)
    out << ", %"
    out << a_label
    out << " ], \[ "
    out << wire_get(inst, :b_value)
    out << ", %"
    out << b_label
    out << " ]"
    true
  when :i64_to_ptr
    out << wire_get(inst, :temp)
    out << " = inttoptr i64 "
    out << wire_get(inst, :value)
    out << " to ptr"
    true
  when :load_ptr
    out << wire_get(inst, :temp)
    out << " = load i64, ptr "
    out << wire_get(inst, :ptr)
    out << ", align 8"
    true
  when :store_ptr
    out << "store i64 "
    out << wire_get(inst, :value)
    out << ", ptr "
    out << wire_get(inst, :dest)
    out << ", align 8"
    true
  when :ptr_to_i64
    out << wire_get(inst, :temp)
    out << " = ptrtoint ptr "
    out << wire_get(inst, :value)
    out << " to i64"
    true
  when :add_i64
    append_binary_instruction(out, inst, "add")
  when :and_i64
    append_binary_instruction(out, inst, "and")
  when :not_i1
    out << wire_get(inst, :temp)
    out << " = xor i1 "
    out << wire_get(inst, :value)
    out << ", true"
    true
  when :sub_i64
    append_binary_instruction(out, inst, "sub")
  when :ashr_i64
    append_binary_instruction(out, inst, "ashr")
  when :call_direct_void
    out << call_prefix(inst)
    out << " void @"
    out << wire_get(inst, :name)
    out << "("
    append_call_args(out, wire_get(inst, :args), wire_get(inst, :arg_types))
    out << ")"
    if emit_blockaddress_sites && wire_get(inst, :src_line) != nil && wire_get(inst, :loc_site_id) != nil
      ret_lbl = "csd." + wire_get(inst, :loc_site_id).to_s() + ".ret"
      out << "\n  br label %"
      out << ret_lbl
      out << "\n"
      out << ret_lbl
      out << ":"
    true
  when :unreachable
    out << "unreachable"
    true
  when :shl_i64
    append_binary_instruction(out, inst, "shl")
  when :or_i64
    append_binary_instruction(out, inst, "or")
  when :select_i64
    out << wire_get(inst, :temp)
    out << " = select i1 "
    out << wire_get(inst, :cond)
    out << ", i64 "
    out << wire_get(inst, :then_val)
    out << ", i64 "
    out << wire_get(inst, :else_val)
    true
  when :mul_i64
    append_binary_instruction(out, inst, "mul")
  when :xor_i64
    append_binary_instruction(out, inst, "xor")
  when :urem_i64
    append_binary_instruction(out, inst, "urem")
  when :lshr_i64
    if wire_get(inst, :lhs) == nil
      return false
    append_binary_instruction(out, inst, "lshr")
  when :sdiv_i64
    append_binary_instruction(out, inst, "sdiv")
  when :srem_i64
    append_binary_instruction(out, inst, "srem")
  when :or_i1
    append_binary_instruction(out, inst, "or", "i1")
  when :udiv_i64
    append_binary_instruction(out, inst, "udiv")
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
  when :ret_i32
    out << "ret i32 "
    value = wire_get(inst, :value)
    out << (value == nil ? "0" : value.to_s())
    true
  when :store_i128
    out << "store i128 "
    out << wire_get(inst, :value)
    out << ", ptr "
    out << wire_get(inst, :ptr)
    out << ", align 16"
    true
  when :load_i128
    out << wire_get(inst, :temp)
    out << " = load i128, ptr "
    out << wire_get(inst, :ptr)
    out << ", align 16"
    out << range_metadata_suffix(inst, "i128")
    true
  when :alloca_i64
    out << wire_get(inst, :ptr)
    out << " = alloca i64, align 8"
    true
  when :alloca_i128
    out << wire_get(inst, :ptr)
    out << " = alloca i128, align 16"
    true
  when :and_i1
    append_binary_instruction(out, inst, "and", "i1")
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
  when :ret_void
    out << "ret void"
    true
  else
    false
