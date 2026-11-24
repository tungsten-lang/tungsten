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
  out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ADD_I64_TEMP)
  out << " = "
  out << opcode
  out << " "
  out << llvm_type
  out << " "
  out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ADD_I64_LHS)
  out << ", "
  out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ADD_I64_RHS)
  true

-> append_call_method_i64(out, inst, emit_blockaddress_sites)
  args = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_METHOD_I64_ARGS)
  argc = wire_sequence_size(args)
  t = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_METHOD_I64_TEMP)
  ic_id = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_METHOD_I64_IC_ID).to_s()
  name_val = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_METHOD_I64_METHOD_NAME_VAL)
  recv = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_METHOD_I64_RECEIVER)
  out << t
  out << ".ic = getelementptr inbounds \[24 x i8], ptr @.ic, i64 "
  out << ic_id
  out << "\n  "
  dv_temp = t
  devirt_fn = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_METHOD_I64_DEVIRT_FN)
  construct_fn = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_METHOD_I64_CONSTRUCT_FN)
  if devirt_fn != nil
    out << t
    out << ".same = call i1 @__w_guard_class(i64 "
    out << recv
    out << ", ptr @class."
    out << llvm_safe_name(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_METHOD_I64_DEVIRT_CLASS).gsub(":", "__"))
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
    out << llvm_safe_name(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_METHOD_I64_CONSTRUCT_CLASS).gsub(":", "__"))
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
  src_line = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_METHOD_I64_SRC_LINE)
  call_keyword = src_line != nil ? "notail call" : "call"
  fb_fn = fast_builtin_runtime_fn(inst, argc)
  if fb_fn != nil
    out << dv_temp
    out << " = "
    out << call_keyword
    out << " i64 @"
    out << fb_fn
    out << "(i64 "
    out << recv
    if argc >= 1
      out << ", i64 "
      out << wire_sequence_get(args, 0)
    if argc >= 2
      out << ", i64 "
      out << wire_sequence_get(args, 1)
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
    t_args = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_METHOD_I64_TEMP_ARGS_VAL)
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
  bits = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPED_ARRAY_GET_INLINE_BITS)
  if bits == nil
    bits = 64
  if bits == 4
    return false
  t = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPED_ARRAY_GET_INLINE_TEMP)
  s = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPED_ARRAY_GET_INLINE_S)
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
  arr = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPED_ARRAY_GET_INLINE_ARR)
  idx = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPED_ARRAY_GET_INLINE_IDX)
  idx_raw = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPED_ARRAY_GET_INLINE_IDX_RAW)
  signed = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPED_ARRAY_GET_INLINE_SIGNED)
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
  bits = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPED_ARRAY_SET_INLINE_BITS)
  if bits == nil
    bits = 64
  if bits == 4
    return false
  t = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPED_ARRAY_SET_INLINE_TEMP)
  s = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPED_ARRAY_SET_INLINE_S)
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
  arr = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPED_ARRAY_SET_INLINE_ARR)
  idx = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPED_ARRAY_SET_INLINE_IDX)
  idx_raw = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPED_ARRAY_SET_INLINE_IDX_RAW)
  val = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPED_ARRAY_SET_INLINE_VALUE)
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
  arity_val = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLASS_ADD_METHOD_ARITY)
  arity_s = arity_val.to_s()
  splat_idx = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLASS_ADD_METHOD_SPLAT_INDEX)
  min_arity = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLASS_ADD_METHOD_MIN_ARITY)
  mode = 0
  if splat_idx != nil && splat_idx >= 0
    add_fn = is_static ? "w_class_add_static_method_splat_wv" : "w_class_add_method_splat_wv"
    mode = 1
  elsif min_arity != nil && min_arity < arity_val
    add_fn = is_static ? "w_class_add_static_method_range_wv" : "w_class_add_method_range_wv"
    mode = 2
  mid = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLASS_ADD_METHOD_METHOD_STR_ID)
  swv = nil
  if string_wvs != nil
    swv = string_wvs[mid]
  ct = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLASS_ADD_METHOD_CLASS_TEMP)
  if swv == nil
    if used_ptr_ids == nil
      return false
    used_ptr_ids[mid] = true
    sfx = is_static ? ".smname" : ".mname"
    out << ct
    out << sfx
    out << " = getelementptr inbounds \["
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLASS_ADD_METHOD_METHOD_BYTE_LEN).to_s()
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
  out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLASS_ADD_METHOD_FN_NAME)
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
  kid = ccall_nobox("w_wire_kind_extern", inst) ## i64

  # Constant-folded WIRE_KIND_* integer arms lower to an LLVM switch jump table.
  case kid
  when WIRE_KIND_CALL_DIRECT_I64
    name = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_NAME)
    if name.size() >= 6 && name.byte_at(0) == 119 && name.byte_at(1) == 95
      if name in ("w_node_kind_extern" "w_is_node_extern" "w_node_alloc" "w_node_field_load" "w_node_field_store" "w_wire_kind_extern" "w_is_wire_extern" "w_wire_slot_load")
        return false
      # Narrow-parameter constructors need operand truncation (ordinary renderer).
      if narrow_runtime_param_types(name) != nil
        return false
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_TEMP)
    out << " = "
    out << call_prefix(inst)
    out << " i64 @"
    out << name
    out << "("
    append_call_args(out, ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_ARGS), ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_ARG_TYPES))
    out << ")"
    out << known_call_range_metadata_suffix(inst, "i64")
    if emit_blockaddress_sites && ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_SRC_LINE) != nil && ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_LOC_SITE_ID) != nil
      ret_lbl = "csd." + ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_LOC_SITE_ID).to_s() + ".ret"
      out << "\n  br label %"
      out << ret_lbl
      out << "\n"
      out << ret_lbl
      out << ":"
    true
  when WIRE_KIND_LOAD_I64
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_I64_TEMP)
    out << " = load i64, ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_I64_PTR)
    out << ", align 8"
    out << range_metadata_suffix(inst, "i64")
    true
  when WIRE_KIND_STORE_I64
    out << "store i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_I64_VALUE)
    out << ", ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_I64_PTR)
    out << ", align 8"
    true
  when WIRE_KIND_BR
    unroll_count = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_BR_UNROLL_COUNT)
    if ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_BR_NOVEC) == true || (unroll_count != nil && unroll_count > 0)
      return false
    out << "br label %"
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_BR_LABEL)
    true
  when WIRE_KIND_COND_BR
    out << "br i1 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_COND_BR_COND)
    out << ", label %"
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_COND_BR_THEN_LABEL)
    out << ", label %"
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_COND_BR_ELSE_LABEL)
    prof = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_COND_BR_PROF)
    if prof == :likely
      out << ", !prof !31411"
    elsif prof == :unlikely
      out << ", !prof !31412"
    true
  when WIRE_KIND_CALL_METHOD_I64
    append_call_method_i64(out, inst, emit_blockaddress_sites)
  when WIRE_KIND_CALL_LOC_SET_COL
    if used_ptr_ids == nil
      return false
    fid = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_LOC_SET_COL_FILE_STR_ID)
    used_ptr_ids[fid] = true
    tp = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_LOC_SET_COL_TEMP_PTR)
    out << tp
    out << " = getelementptr inbounds \["
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_LOC_SET_COL_FILE_BYTE_LEN).to_s()
    out << " x i8], ptr @.str."
    out << fid.to_s()
    out << ", i32 0, i32 0\n  call void @__w_loc_set_col(ptr "
    out << tp
    out << ", i32 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_LOC_SET_COL_LINE).to_s()
    out << ", i32 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_LOC_SET_COL_COL).to_s()
    out << ")"
    true
  when WIRE_KIND_TRUTHY_INLINE
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TRUTHY_INLINE_TEMP)
    out << " = icmp ugt i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TRUTHY_INLINE_VALUE)
    out << ", 1"
    true
  when WIRE_KIND_PHI_SSA
    incoming = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PHI_SSA_INCOMING)
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PHI_SSA_TEMP)
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
  when WIRE_KIND_STRING_I64
    sid = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STRING_I64_STRING_ID)
    swv = nil
    if string_wvs != nil
      swv = string_wvs[sid]
    if swv != nil
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STRING_I64_TEMP)
      out << " = or i64 0, "
      out << llvm_wvalue_literal(swv)
      return true
    if used_ptr_ids == nil
      return false
    used_ptr_ids[sid] = true
    tp = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STRING_I64_TEMP_PTR)
    out << tp
    out << " = getelementptr inbounds \["
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STRING_I64_BYTE_LEN).to_s()
    out << " x i8], ptr @.str."
    out << sid.to_s()
    out << ", i32 0, i32 0\n  "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STRING_I64_TEMP)
    out << " = call i64 @w_string(ptr "
    out << tp
    out << ")"
    true
  when WIRE_KIND_SYMBOL_I64
    sid = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SYMBOL_I64_STRING_ID)
    swv = nil
    if string_wvs != nil
      swv = string_wvs[sid]
    if swv != nil
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SYMBOL_I64_TEMP)
      out << " = or i64 "
      out << llvm_wvalue_literal(swv)
      out << ", 1"
      return true
    if used_ptr_ids == nil
      return false
    used_ptr_ids[sid] = true
    tp = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SYMBOL_I64_TEMP_PTR)
    t = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SYMBOL_I64_TEMP)
    out << tp
    out << " = getelementptr inbounds \["
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SYMBOL_I64_BYTE_LEN).to_s()
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
  when WIRE_KIND_NANBOX_INT
    raw_str = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANBOX_INT_RAW).to_s()
    ch = raw_str.slice(0, 1)
    if ch != nil && (ch == "-" || (ch >= "0" && ch <= "9"))
      wval = (raw_str.to_i() & 281474976710655) | -1688849860263936
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANBOX_INT_TEMP)
      out << " = or i64 0, "
      out << llvm_wvalue_literal(wval)
      return true
    tm = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANBOX_INT_TEMP_MASKED)
    out << tm
    out << " = and i64 "
    out << raw_str
    out << ", "
    out << machine_i64_text(w_payload_mask)
    out << "\n  "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANBOX_INT_TEMP)
    out << " = or i64 "
    out << tm
    out << ", "
    out << machine_i64_text(w_tag_int)
    true
  when WIRE_KIND_NANBOX_BOOL
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANBOX_BOOL_TEMP)
    out << " = select i1 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANBOX_BOOL_VALUE)
    out << ", i64 "
    out << w_true.to_s()
    out << ", i64 "
    out << w_false.to_s()
    true
  when WIRE_KIND_LOAD_CLASS
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_CLASS_TEMP)
    out << " = load i64, ptr @class."
    out << llvm_safe_name(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_CLASS_CLASS_NAME).gsub(":", "__"))
    true
  when WIRE_KIND_IVAR_GET_IDX
    t = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_GET_IDX_TEMP)
    out << t
    out << ".raw = and i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_GET_IDX_SELF_REG)
    out << ", -16\n  "
    out << t
    out << ".ptr = inttoptr i64 "
    out << t
    out << ".raw to ptr\n  "
    out << t
    out << ".gep = getelementptr i8, ptr "
    out << t
    out << ".ptr, i64 "
    out << (8 + ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_GET_IDX_OFFSET) * 8).to_s()
    out << "\n  "
    out << t
    out << " = load i64, ptr "
    out << t
    out << ".gep, align 8"
    out << tbaa_ivar_suffix()
    true
  when WIRE_KIND_CLASS_ADD_METHOD
    append_class_add_method_direct(out, inst, false, string_wvs, used_ptr_ids)
  when WIRE_KIND_TYPED_ARRAY_GET_INLINE
    append_typed_array_get_inline(out, inst)
  when WIRE_KIND_LOAD_GLOBAL
    t = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_GLOBAL_TYPE)
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_GLOBAL_TEMP)
    out << " = load "
    out << (t == nil ? "i64" : t)
    out << ", ptr @global."
    out << llvm_safe_name(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_GLOBAL_NAME))
    true
  when WIRE_KIND_GEP_ARRAY
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_GEP_ARRAY_TEMP)
    out << " = getelementptr inbounds \["
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_GEP_ARRAY_COUNT).to_s()
    out << " x i64], ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_GEP_ARRAY_BASE)
    out << ", i32 0, i32 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_GEP_ARRAY_INDEX).to_s()
    true
  when WIRE_KIND_SCOPE_PUSH
    out << "; scope scope_push"
    true
  when WIRE_KIND_SCOPE_POP
    out << "; scope scope_pop"
    true
  when WIRE_KIND_RET_I64
    out << "ret i64 "
    value = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_RET_I64_VALUE)
    out << (value == nil ? "0" : value.to_s())
    true
  when WIRE_KIND_ICMP_I64
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ICMP_I64_TEMP)
    out << " = icmp "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ICMP_I64_PRED)
    out << " i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ICMP_I64_LHS)
    out << ", "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ICMP_I64_RHS)
    true
  when WIRE_KIND_IVAR_SET_IDX
    t = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_SET_IDX_TEMP)
    v = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_SET_IDX_VALUE)
    out << t
    out << ".raw = and i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_SET_IDX_SELF_REG)
    out << ", -16\n  "
    out << t
    out << ".ptr = inttoptr i64 "
    out << t
    out << ".raw to ptr\n  "
    out << t
    out << ".gep = getelementptr i8, ptr "
    out << t
    out << ".ptr, i64 "
    out << (8 + ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_SET_IDX_OFFSET) * 8).to_s()
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
  when WIRE_KIND_CLOSURE_NEW
    ba = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLOSURE_NEW_BLOCK_ARITY)
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLOSURE_NEW_TEMP)
    out << " = call i64 @w_closure_new_a(ptr @"
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLOSURE_NEW_FN_NAME)
    out << ", ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLOSURE_NEW_CAPTURES_PTR)
    out << ", i32 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLOSURE_NEW_CAPTURE_COUNT).to_s()
    out << ", i32 "
    out << (ba == nil ? "0" : ba.to_s())
    out << ")"
    true
  when WIRE_KIND_ALLOCA_ARRAY
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ALLOCA_ARRAY_PTR)
    out << " = alloca \["
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ALLOCA_ARRAY_COUNT).to_s()
    out << " x i64], align 8"
    true
  when WIRE_KIND_STORE_GLOBAL
    t = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_GLOBAL_TYPE)
    out << "store "
    out << (t == nil ? "i64" : t)
    out << " "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_GLOBAL_VALUE)
    out << ", ptr @global."
    out << llvm_safe_name(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_GLOBAL_NAME))
    true
  when WIRE_KIND_ARRAY_SIZE_RAW
    t = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ARRAY_SIZE_RAW_TEMP)
    v = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ARRAY_SIZE_RAW_VALUE)
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
  when WIRE_KIND_TYPED_ARRAY_SET_INLINE
    append_typed_array_set_inline(out, inst)
  when WIRE_KIND_CLASS_ADD_STATIC_METHOD
    append_class_add_method_direct(out, inst, true, string_wvs, used_ptr_ids)
  when WIRE_KIND_FREE_VALUE
    out << "call void @w_value_free(i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FREE_VALUE_VALUE)
    out << ")"
    true
  when WIRE_KIND_RECYCLE_OBJECT
    out << "call void @w_object_recycle(i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_RECYCLE_OBJECT_VALUE)
    out << ")"
    true
  when WIRE_KIND_PUTS_I64
    t = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PUTS_I64_TEMP)
    if t != nil
      out << t
      out << " = "
    out << "call i64 @w_puts(i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PUTS_I64_VALUE)
    out << ")"
    true
  when WIRE_KIND_PRINT_I64
    t = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PRINT_I64_TEMP)
    if t != nil
      out << t
      out << " = "
    out << "call i64 @w_print(i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PRINT_I64_VALUE)
    out << ")"
    true
  when WIRE_KIND_NANUNBOX_INT
    ts = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANUNBOX_INT_TEMP_SHL)
    out << ts
    out << " = shl i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANUNBOX_INT_BOXED)
    out << ", 16\n  "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANUNBOX_INT_TEMP)
    out << " = ashr i64 "
    out << ts
    out << ", 16"
    true
  when WIRE_KIND_NANBOX_FLOAT
    tb = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANBOX_FLOAT_TEMP_BITS)
    out << tb
    out << " = bitcast double "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANBOX_FLOAT_RAW)
    out << " to i64\n  "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANBOX_FLOAT_TEMP)
    out << " = add i64 "
    out << tb
    out << ", "
    out << machine_i64_text(w_double_bias)
    true
  when WIRE_KIND_NANUNBOX_FLOAT
    tb = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANUNBOX_FLOAT_TEMP_BITS)
    out << tb
    out << " = sub i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANUNBOX_FLOAT_BOXED)
    out << ", "
    out << machine_i64_text(w_double_bias)
    out << "\n  "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NANUNBOX_FLOAT_TEMP)
    out << " = bitcast i64 "
    out << tb
    out << " to double"
    true
  when WIRE_KIND_TA_SIZE_RAW
    t = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TA_SIZE_RAW_TEMP)
    out << t
    out << ".hdr = and i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TA_SIZE_RAW_VALUE)
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
  when WIRE_KIND_LOAD_DOUBLE
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_DOUBLE_TEMP)
    out << " = load double, ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_DOUBLE_PTR)
    out << ", align 8"
    true
  when WIRE_KIND_STORE_DOUBLE
    out << "store double "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_DOUBLE_VALUE)
    out << ", ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_DOUBLE_PTR)
    out << ", align 8"
    true
  when WIRE_KIND_LOAD_FLOAT
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_FLOAT_TEMP)
    out << " = load float, ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_FLOAT_PTR)
    out << ", align 4"
    true
  when WIRE_KIND_STORE_FLOAT
    out << "store float "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_FLOAT_VALUE)
    out << ", ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_FLOAT_PTR)
    out << ", align 4"
    true
  when WIRE_KIND_CLASS_STORE
    out << "store i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLASS_STORE_VALUE)
    out << ", ptr @class."
    out << llvm_safe_name(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLASS_STORE_CLASS_NAME).gsub(":", "__"))
    true
  when WIRE_KIND_LOAD_CVAR
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_CVAR_TEMP)
    out << " = load i64, ptr @cvar."
    out << llvm_safe_name(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_CVAR_CVAR_KEY).gsub(":", "__"))
    true
  when WIRE_KIND_STORE_CVAR
    out << "store i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_CVAR_VALUE)
    out << ", ptr @cvar."
    out << llvm_safe_name(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_CVAR_CVAR_KEY).gsub(":", "__"))
    true
  when WIRE_KIND_NULL_PTR
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NULL_PTR_TEMP)
    out << " = inttoptr i64 0 to ptr"
    true
  when WIRE_KIND_ICMP_NE_I64
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ICMP_NE_I64_TEMP)
    out << " = icmp ne i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ICMP_NE_I64_LHS)
    out << ", "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ICMP_NE_I64_RHS)
    true
  when WIRE_KIND_PHI_I64
    a_label = redirect_phi_label(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PHI_I64_A_LABEL), phi_label_redirects)
    b_label = redirect_phi_label(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PHI_I64_B_LABEL), phi_label_redirects)
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PHI_I64_TEMP)
    out << " = phi i64 \[ "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PHI_I64_A_VALUE)
    out << ", %"
    out << a_label
    out << " ], \[ "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PHI_I64_B_VALUE)
    out << ", %"
    out << b_label
    out << " ]"
    true
  when WIRE_KIND_PHI_I1
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
  when WIRE_KIND_I64_TO_PTR
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_I64_TO_PTR_TEMP)
    out << " = inttoptr i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_I64_TO_PTR_VALUE)
    out << " to ptr"
    true
  when WIRE_KIND_LOAD_PTR
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_PTR_TEMP)
    out << " = load i64, ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_PTR_PTR)
    out << ", align 8"
    true
  when WIRE_KIND_STORE_PTR
    out << "store i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_PTR_VALUE)
    out << ", ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_PTR_DEST)
    out << ", align 8"
    true
  when WIRE_KIND_PTR_TO_I64
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PTR_TO_I64_TEMP)
    out << " = ptrtoint ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PTR_TO_I64_VALUE)
    out << " to i64"
    true
  when WIRE_KIND_ADD_I64
    append_binary_instruction(out, inst, "add")
  when WIRE_KIND_AND_I64
    append_binary_instruction(out, inst, "and")
  when WIRE_KIND_NOT_I1
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NOT_I1_TEMP)
    out << " = xor i1 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NOT_I1_VALUE)
    out << ", true"
    true
  when WIRE_KIND_SUB_I64
    append_binary_instruction(out, inst, "sub")
  when WIRE_KIND_ASHR_I64
    append_binary_instruction(out, inst, "ashr")
  when WIRE_KIND_CALL_DIRECT_VOID
    out << call_prefix(inst)
    out << " void @"
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_VOID_NAME)
    out << "("
    append_call_args(out, ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_VOID_ARGS), wire_get(inst, :arg_types))
    out << ")"
    if emit_blockaddress_sites && wire_get(inst, :src_line) != nil && wire_get(inst, :loc_site_id) != nil
      ret_lbl = "csd." + wire_get(inst, :loc_site_id).to_s() + ".ret"
      out << "\n  br label %"
      out << ret_lbl
      out << "\n"
      out << ret_lbl
      out << ":"
    true
  when WIRE_KIND_UNREACHABLE
    out << "unreachable"
    true
  when WIRE_KIND_SHL_I64
    append_binary_instruction(out, inst, "shl")
  when WIRE_KIND_OR_I64
    append_binary_instruction(out, inst, "or")
  when WIRE_KIND_SELECT_I64
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SELECT_I64_TEMP)
    out << " = select i1 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SELECT_I64_COND)
    out << ", i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SELECT_I64_THEN_VAL)
    out << ", i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SELECT_I64_ELSE_VAL)
    true
  when WIRE_KIND_MUL_I64
    append_binary_instruction(out, inst, "mul")
  when WIRE_KIND_XOR_I64
    append_binary_instruction(out, inst, "xor")
  when WIRE_KIND_UREM_I64
    append_binary_instruction(out, inst, "urem")
  when WIRE_KIND_LSHR_I64
    if ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LSHR_I64_LHS) == nil
      return false
    append_binary_instruction(out, inst, "lshr")
  when WIRE_KIND_SDIV_I64
    append_binary_instruction(out, inst, "sdiv")
  when WIRE_KIND_SREM_I64
    append_binary_instruction(out, inst, "srem")
  when WIRE_KIND_OR_I1
    append_binary_instruction(out, inst, "or", "i1")
  when WIRE_KIND_UDIV_I64
    append_binary_instruction(out, inst, "udiv")
  when WIRE_KIND_CALL_DIRECT_I64_PTR1
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_PTR1_TEMP)
    out << " = "
    out << call_prefix(inst)
    out << " i64 @"
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_PTR1_NAME)
    out << "(ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_PTR1_ARG)
    out << ")"
    true
  when WIRE_KIND_RET_I32
    out << "ret i32 "
    value = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_RET_I32_VALUE)
    out << (value == nil ? "0" : value.to_s())
    true
  when WIRE_KIND_STORE_I128
    out << "store i128 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_I128_VALUE)
    out << ", ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_I128_PTR)
    out << ", align 16"
    true
  when WIRE_KIND_LOAD_I128
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_I128_TEMP)
    out << " = load i128, ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_I128_PTR)
    out << ", align 16"
    out << range_metadata_suffix(inst, "i128")
    true
  when WIRE_KIND_ALLOCA_I64
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ALLOCA_I64_PTR)
    out << " = alloca i64, align 8"
    true
  when WIRE_KIND_ALLOCA_I128
    out << wire_get(inst, :ptr)
    out << " = alloca i128, align 16"
    true
  when WIRE_KIND_AND_I1
    append_binary_instruction(out, inst, "and", "i1")
  when WIRE_KIND_ICMP_NE_ZERO
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ICMP_NE_ZERO_TEMP)
    out << " = icmp ne i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ICMP_NE_ZERO_VALUE)
    out << ", 0"
    true
  when WIRE_KIND_ZEXT_I1_I64
    out << wire_get(inst, :temp)
    out << " = zext i1 "
    out << wire_get(inst, :value)
    out << " to i64"
    true
  when WIRE_KIND_TRUNC_I64_I32
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TRUNC_I64_I32_TEMP)
    out << " = trunc i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TRUNC_I64_I32_VALUE)
    out << " to i32"
    true
  when WIRE_KIND_RET_VOID
    out << "ret void"
    true
  when WIRE_KIND_CONST_FLOAT
    t = wire_get(inst, :temp)
    out << t
    out << ".bits = bitcast double "
    out << wire_get(inst, :value)
    out << " to i64\n  "
    out << t
    out << " = add i64 "
    out << t
    out << ".bits, "
    out << machine_i64_text(w_double_bias)
    true
  when WIRE_KIND_BIGINT_LITERAL_I64
    sid = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_BIGINT_LITERAL_I64_STRING_ID)
    used_ptr_ids[sid] = true
    tp = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_BIGINT_LITERAL_I64_TEMP_PTR)
    out << tp
    out << " = getelementptr inbounds \["
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_BIGINT_LITERAL_I64_BYTE_LEN).to_s()
    out << " x i8], ptr @.str."
    out << sid.to_s()
    out << ", i32 0, i32 0\n  "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_BIGINT_LITERAL_I64_TEMP)
    out << " = call i64 @w_bigint_literal_cached(ptr "
    out << tp
    out << ", ptr @.bigint.literal."
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_BIGINT_LITERAL_I64_SLOT_ID).to_s()
    out << ")"
    true
  when WIRE_KIND_CALL_DIRECT_I128
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I128_TEMP)
    out << " = "
    out << call_prefix(inst)
    out << " i128 @"
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I128_NAME)
    out << "("
    append_call_args(out, ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I128_ARGS), ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I128_ARG_TYPES))
    out << ")"
    true
  when WIRE_KIND_CALL_DIRECT_VOID_PTR1
    out << call_prefix(inst)
    out << " void @"
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_VOID_PTR1_NAME)
    out << "(ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_VOID_PTR1_ARG)
    out << ")"
    true
  when WIRE_KIND_CALL_DIRECT_PTR
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_PTR_TEMP)
    out << " = "
    out << call_prefix(inst)
    out << " ptr @"
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_PTR_NAME)
    out << "("
    append_call_args(out, ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_PTR_ARGS), wire_get(inst, :arg_types))
    out << ")"
    true
  when WIRE_KIND_CLEANUP_POP
    out << "call void @w_cleanup_pop()"
    true
  when WIRE_KIND_SETJMP
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SETJMP_TEMP)
    out << " = call i32 @"
    out << (windows_target ? "setjmp" : "_setjmp")
    out << "(ptr "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SETJMP_BUF)
    out << ")"
    true
  when WIRE_KIND_ICMP_EQ_I32
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ICMP_EQ_I32_TEMP)
    out << " = icmp eq i32 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ICMP_EQ_I32_LHS)
    out << ", "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_ICMP_EQ_I32_RHS)
    true
  when WIRE_KIND_ARGV_INIT
    out << "call void @w_argv_init(i32 %argc, ptr %argv)"
    true
  when WIRE_KIND_TYPE_CLASS_REGISTER
    out << "call void @w_type_class_register_wv(i32 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPE_CLASS_REGISTER_DISPATCH_KEY).to_s()
    out << ", i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_TYPE_CLASS_REGISTER_CLASS_TEMP)
    out << ")"
    true
  when WIRE_KIND_NODE_KIND_CLASS_REGISTER
    out << "call void @w_node_kind_class_register_wv(i32 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NODE_KIND_CLASS_REGISTER_KIND_ID).to_s()
    out << ", i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_NODE_KIND_CLASS_REGISTER_CLASS_TEMP)
    out << ")"
    true
  when WIRE_KIND_CLASS_NEW
    sid = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLASS_NEW_NAME_STR_ID)
    swv = string_wvs != nil ? string_wvs[sid] : nil
    sr = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLASS_NEW_SUPER_REG)
    super_arg = sr != nil ? sr : w_nil.to_s()
    t = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLASS_NEW_TEMP)
    if swv != nil
      out << t
      out << " = call i64 @w_class_new_wv(i64 "
      out << llvm_wvalue_literal(swv)
      out << ", i64 "
      out << super_arg
      out << ")"
    else
      used_ptr_ids[sid] = true
      out << t
      out << ".ptr = getelementptr inbounds \["
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CLASS_NEW_NAME_BYTE_LEN).to_s()
      out << " x i8], ptr @.str."
      out << sid.to_s()
      out << ", i32 0, i32 0\n  "
      out << t
      out << ".name = call i64 @w_string(ptr "
      out << t
      out << ".ptr)\n  "
      out << t
      out << " = call i64 @w_class_new_wv(i64 "
      out << t
      out << ".name, i64 "
      out << super_arg
      out << ")"
    true
  when WIRE_KIND_BUILTIN_CLASS_INIT
    sid = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_BUILTIN_CLASS_INIT_NAME_STR_ID)
    swv = string_wvs != nil ? string_wvs[sid] : nil
    cn = llvm_safe_name(ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_BUILTIN_CLASS_INIT_CLASS_NAME).gsub(":", "__"))
    if swv != nil
      out << "%"
      out << cn
      out << ".cls = call i64 @w_class_new_wv(i64 "
      out << llvm_wvalue_literal(swv)
      out << ", i64 "
      out << w_nil.to_s()
      out << ")\n  store i64 %"
      out << cn
      out << ".cls, ptr @class."
      out << cn
    else
      used_ptr_ids[sid] = true
      out << "%"
      out << cn
      out << ".ptr = getelementptr inbounds \["
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_BUILTIN_CLASS_INIT_NAME_BYTE_LEN).to_s()
      out << " x i8], ptr @.str."
      out << sid.to_s()
      out << ", i32 0, i32 0\n  %"
      out << cn
      out << ".name = call i64 @w_string(ptr %"
      out << cn
      out << ".ptr)\n  %"
      out << cn
      out << ".cls = call i64 @w_class_new_wv(i64 %"
      out << cn
      out << ".name, i64 "
      out << w_nil.to_s()
      out << ")\n  store i64 %"
      out << cn
      out << ".cls, ptr @class."
      out << cn
    true
  when WIRE_KIND_IVAR_GET
    sid = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_GET_STR_ID)
    swv = string_wvs != nil ? string_wvs[sid] : nil
    if swv != nil
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_GET_TEMP)
      out << " = call i64 @w_ivar_get_wv(i64 "
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_GET_SELF_REG)
      out << ", i64 "
      out << llvm_wvalue_literal(swv)
      out << ")"
    else
      used_ptr_ids[sid] = true
      tp = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_GET_TEMP_PTR)
      out << tp
      out << " = getelementptr inbounds \["
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_GET_BYTE_LEN).to_s()
      out << " x i8], ptr @.str."
      out << sid.to_s()
      out << ", i32 0, i32 0\n  "
      out << tp
      out << ".wv = call i64 @w_string(ptr "
      out << tp
      out << ")\n  "
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_GET_TEMP)
      out << " = call i64 @w_ivar_get_wv(i64 "
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_GET_SELF_REG)
      out << ", i64 "
      out << tp
      out << ".wv)"
    true
  when WIRE_KIND_IVAR_SET
    sid = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_SET_STR_ID)
    swv = string_wvs != nil ? string_wvs[sid] : nil
    if swv != nil
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_SET_TEMP)
      out << " = call i64 @w_ivar_set_wv(i64 "
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_SET_SELF_REG)
      out << ", i64 "
      out << llvm_wvalue_literal(swv)
      out << ", i64 "
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_SET_VALUE)
      out << ")"
    else
      used_ptr_ids[sid] = true
      tp = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_SET_TEMP_PTR)
      out << tp
      out << " = getelementptr inbounds \["
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_SET_BYTE_LEN).to_s()
      out << " x i8], ptr @.str."
      out << sid.to_s()
      out << ", i32 0, i32 0\n  "
      out << tp
      out << ".wv = call i64 @w_string(ptr "
      out << tp
      out << ")\n  "
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_SET_TEMP)
      out << " = call i64 @w_ivar_set_wv(i64 "
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_SET_SELF_REG)
      out << ", i64 "
      out << tp
      out << ".wv, i64 "
      out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_IVAR_SET_VALUE)
      out << ")"
    true
  when WIRE_KIND_SWITCH_I64
    cases = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SWITCH_I64_CASES)
    is_symbol = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SWITCH_I64_IS_SYMBOL)
    out << "switch i64 "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SWITCH_I64_VALUE)
    out << ", label %"
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SWITCH_I64_DEFAULT_LABEL)
    out << " \[\n"
    nc = wire_sequence_size(cases)
    ci = 0
    while ci < nc
      c = wire_sequence_get(cases, ci)
      sid = c[:string_id]
      if sid != nil
        swv = string_wvs != nil ? string_wvs[sid] : nil
        if swv == nil
          key_text = "0"
        elsif is_symbol == true
          key_text = llvm_wvalue_literal(swv + 1)
        else
          key_text = llvm_wvalue_literal(swv)
      else
        key_text = c[:value].to_s()
      out << "    i64 "
      out << key_text
      out << ", label %"
      out << c[:label]
      out << "\n"
      ci += 1
    out << "  ]"
    true
  when WIRE_KIND_FADD_F64
    f = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FADD_F64_FP_FLAGS)
    if f == nil
      f = fp_flags
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FADD_F64_TEMP)
    out << " = fadd "
    out << f
    out << "double "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FADD_F64_LHS)
    out << ", "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FADD_F64_RHS)
    true
  when WIRE_KIND_FSUB_F64
    f = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FSUB_F64_FP_FLAGS)
    if f == nil
      f = fp_flags
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FSUB_F64_TEMP)
    out << " = fsub "
    out << f
    out << "double "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FSUB_F64_LHS)
    out << ", "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FSUB_F64_RHS)
    true
  when WIRE_KIND_FMUL_F64
    f = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FMUL_F64_FP_FLAGS)
    if f == nil
      f = fp_flags
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FMUL_F64_TEMP)
    out << " = fmul "
    out << f
    out << "double "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FMUL_F64_LHS)
    out << ", "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FMUL_F64_RHS)
    true
  when WIRE_KIND_FDIV_F64
    f = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FDIV_F64_FP_FLAGS)
    if f == nil
      f = fp_flags
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FDIV_F64_TEMP)
    out << " = fdiv "
    out << f
    out << "double "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FDIV_F64_LHS)
    out << ", "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FDIV_F64_RHS)
    true
  when WIRE_KIND_FREM_F64
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FREM_F64_TEMP)
    out << " = frem double "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FREM_F64_LHS)
    out << ", "
    out << ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_FREM_F64_RHS)
    true
  else
    false
