# Emitter — renders WIRE IR to LLVM IR text
# Takes a WIRE module (from lowering) and produces a complete .ll file.

use runtime_types
use hashing

# -- String escaping --

-> escape_llvm_string(s)
  result = StringBuffer(s.size())
  i = 0
  chars = s.chars()
  while i < chars.size()
    ch = chars[i]
    case ch
    when "\\"
      result << "\\5C"
    when "\""
      result << "\\22"
    when "\n"
      result << "\\0A"
    when "\r"
      result << "\\0D"
    when "\t"
      result << "\\09"
    else
      result << ch
    i += 1
  result.to_s()

-> utf8_byte_length(s)
  n = 0
  i = 0
  chars = s.chars()
  while i < chars.size()
    ch = chars[i]
    code = ch.ord()
    if code < 128
      n += 1
    elsif code < 2048
      n += 2
    elsif code < 65536
      n += 3
    else
      n += 4
    i += 1
  n

-> llvm_wvalue_literal(value)
  u = value.to_i()
  if u < 0
    wrap = 1
    i = 0
    while i < 64
      wrap = wrap * 2
      i += 1
    u = u + wrap
  hex_chars = "0123456789ABCDEF"
  out = StringBuffer(19)
  out << "u0x"
  shift = 60
  while shift >= 0
    out << hex_chars.slice((u >> shift) & 15, 1)
    shift -= 4
  out.to_s()

-> append_llvm_hex_byte(out, byte)
  b = byte ## u64
  hi = (b >> 4) & 15 ## u64
  lo = b & 15 ## u64
  hex_chars = "0123456789abcdef"
  out << "\\"
  out << hex_chars.slice(hi, 1)
  out << hex_chars.slice(lo, 1)

-> append_llvm_bytes_slice(out, bytes, offset, count)
  i = 0
  while i < count
    byte = bytes[offset + i]
    case byte
    when 92
      out << "\\5C"
    when 34
      out << "\\22"
    when 10
      out << "\\0A"
    when 13
      out << "\\0D"
    when 9
      out << "\\09"
    when 32..126
      out << byte.chr()
    else
      append_llvm_hex_byte(out, byte)
    i += 1

# -- String constants --

# Compute SSO-5 WValue for a string ≤5 bytes.
-> sso5_wvalue(text)
  byte_len = utf8_byte_length(text)
  v = w_tag_stringsym + byte_len * 2
  bytes = text.bytes()
  i = 0
  while i < byte_len
    v = v + bytes[i] * (1 << (4 + 8 * i))
    i += 1
  v

# Build a static slab map: string_id → pre-computed WValue.
# SSO-5 strings (≤5 bytes) become inline i64 constants.
# Medium strings (6-61 bytes) get slab slot indices.
# Large strings (>61 bytes) keep the runtime w_string() call.
#
# `no_slab` (REPL/JIT snippets): a snippet's slab slot INDICES are relative to
# the snippet's own slab, but a JIT'd snippet runs against the HOST's already-
# initialized slab (w_slab_init_static is idempotent), so baked indices mis-
# resolve. With no_slab we skip slab assignment for 6-61 byte strings so they
# fall through to the runtime w_string() path — interned into the live host slab
# (or heap if frozen), which is correct regardless of the host's slab layout.
# SSO-5 (inline) and >61 byte (already runtime) strings are unaffected.
-> build_string_wvalues(strings, no_slab = false)
  wvalues = {}  # string_id → i64 WValue (or nil for large strings)
  next_slot = 1  # slot 0 is reserved sentinel
  slab_entries = []  # [{id, text, slot_index, nslots}, ...]

  i = 0
  while i < strings.size()
    s = strings[i]
    byte_len = utf8_byte_length(s[:text])
    if byte_len <= 5
      # SSO-5: inline WValue constant
      wvalues[s[:id]] = sso5_wvalue(s[:text])
    elsif byte_len <= 61 && !no_slab
      nslots = 1
      if byte_len > 29
        nslots = 2
      slot_index = next_slot
      next_slot = next_slot + nslots
      wv = w_tag_stringsym + 12 + slot_index * 16
      wvalues[s[:id]] = wv
      slab_entries.push({id: s[:id], text: s[:text], slot: slot_index, nslots: nslots, byte_len: byte_len})
    i += 1

  {wvalues: wvalues, slab_entries: slab_entries, total_slots: next_slot}

# Emit only the string constants that were actually used via raw ptr access in
# the emitted IR, plus the packed static slab data.
-> emit_string_constants(strings, slab_info, needed_ptr_ids)
  out = StringBuffer(strings.size() * 48)
  lbr = "\["
  rbr = "]"
  # Emit only strings still referenced via getelementptr/raw ptr APIs.
  i = 0
  while i < strings.size()
    s = strings[i]
    id = s[:id]
    if needed_ptr_ids[id] == true
      text = s[:text]
      escaped = escape_llvm_string(text)
      byte_len = utf8_byte_length(text) + 1
      out << "@.str."
      out << id.to_s()
      out << " = private unnamed_addr constant "
      out << lbr
      out << byte_len.to_s()
      out << " x i8"
      out << rbr
      out << " c\""
      out << escaped
      out << "\\00\"\n"
    i += 1

  # Emit static slab data as a global byte array
  slab_entries = slab_info[:slab_entries]
  total_slots = slab_info[:total_slots]
  if slab_entries.size() > 0
    total_bytes = total_slots * 32
    out << "\n; Static string slab: "
    out << slab_entries.size().to_s()
    out << " strings, "
    out << total_slots.to_s()
    out << " slots ("
    out << total_bytes.to_s()
    out << " bytes)\n"
    out << "@__static_slab = private constant "
    out << lbr
    out << total_bytes.to_s()
    out << " x i8"
    out << rbr
    out << " c\""
    # Build slab byte array: slot 0 is zeroed (sentinel), then each string's slot(s)
    # Slot 0: 32 zero bytes
    si = 0
    while si < 32
      out << "\\00"
      si += 1
    # Each slab entry: flags + length + payload bytes + zero-fill
    ei = 0
    while ei < slab_entries.size()
      entry = slab_entries[ei]
      byte_len = entry[:byte_len]
      nslots = entry[:nslots]
      bytes = entry[:text].bytes()
      flags = 1
      if nslots == 2
        flags = 3
      append_llvm_hex_byte(out, flags)
      append_llvm_hex_byte(out, byte_len)
      first_len = byte_len
      if first_len > 30
        first_len = 30
      append_llvm_bytes_slice(out, bytes, 0, first_len)
      remaining = 30 - first_len
      ri = 0
      while ri < remaining
        out << "\\00"
        ri += 1
      if nslots == 2
        second_len = byte_len - first_len
        append_llvm_bytes_slice(out, bytes, first_len, second_len)
        remaining2 = 32 - second_len
        ri2 = 0
        while ri2 < remaining2
          out << "\\00"
          ri2 += 1
      ei += 1
    out << "\", align 8\n"

  out.to_s()

# -- Runtime declarations --

-> declare_runtime
  out = StringBuffer(4096)
  wv = "i64"
  wv2 = join_arg_types2(wv, wv)
  wv3 = join_arg_types3(wv, wv, wv)
  wv4 = join_arg_types4(wv, wv, wv, wv)
  wv5 = wv4 + ", " + wv
  i32_wv = join_arg_types2("i32", wv)
  i64_wv = join_arg_types2("i64", wv)
  ptr_wv = join_arg_types2("ptr", wv)
  wv_ptr = join_arg_types2(wv, "ptr")
  wv_i32 = join_arg_types2(wv, "i32")
  ptr_ptr = join_arg_types2("ptr", "ptr")
  ptr_ptr_wv = join_arg_types3("ptr", "ptr", wv)
  ptr_ptr_i32 = join_arg_types3("ptr", "ptr", "i32")
  ptr_ptr_i32_wv = join_arg_types4("ptr", "ptr", "i32", wv)
  wv_ptr_wv = join_arg_types3(wv, "ptr", wv)
  wv_i32_wv = join_arg_types3(wv, "i32", wv)
  wv_ptr_ptr_i32 = join_arg_types4(wv, "ptr", "ptr", "i32")
  wv2_ptr_i32 = join_arg_types4(wv, wv, "ptr", "i32")

  # Core value constructors
  out << declare_fn("w_int", wv, "i64")
  out << declare_fn("w_to_i64", "i64", wv)
  out << declare_fn("w_u64", wv, "i64")
  out << declare_fn("w_to_u64", "i64", wv)
  out << declare_fn("w_i128", wv, "i128")
  out << declare_fn("w_to_i128", "i128", wv)
  out << declare_fn("w_u128", wv, "i128")
  out << declare_fn("w_to_u128", "i128", wv)
  out << declare_fn_attrs("w_bool", wv, "i64", "nounwind willreturn memory(none) speculatable alwaysinline")
  out << declare_fn_attrs("w_nil", wv, "", "nounwind willreturn memory(none) speculatable alwaysinline")
  out << declare_fn("w_string", wv, "ptr")
  out << declare_fn("w_str_to_sym", wv, wv)
  out << declare_fn("w_regex_new", wv, wv2)
  out << declare_fn("w_regex_match", wv, wv2)
  out << declare_fn("w_regex_capture", wv, wv)
  out << declare_fn_attrs("w_float", wv, "double", "nounwind willreturn memory(none) speculatable alwaysinline")
  out << declare_fn("w_decimal", wv, "i64, i32")

  # Domain type constructors
  out << declare_fn("w_currency", wv, "i32, i64, i32")
  out << declare_fn("w_quantity", wv, "i32, i64, i32")
  out << declare_fn("w_duration_ns", wv, "i64")
  out << declare_fn("w_duration_months_ms", wv, "i32, i32")
  out << declare_fn("w_date", wv, "i32, i32, i32, i32, i32, i32, i32")
  out << declare_fn("w_ipv4", wv, "i32, i32, i32, i32, i32")
  out << declare_fn("w_uuid_from_hex", wv, "ptr")
  out << declare_fn("w_ipv6_from_string", wv, "ptr, i32")
  out << declare_fn("w_rational", wv, "i32, i32")
  out << declare_fn("w_box_char", wv, "i32")
  out << declare_fn("w_color", wv, "i32, i32, i32, i32")
  out << declare_fn("w_register_unit", "void", "i32, ptr")
  out << declare_fn("w_register_unit_wv", "void", i32_wv)

  # Arithmetic
  out << declare_fn("w_add", wv, wv2)
  out << declare_fn("w_sub", wv, wv2)
  out << declare_fn("w_mul", wv, wv2)
  out << declare_fn("w_pow", wv, wv2)
  out << declare_fn("w_div", wv, wv2)
  out << declare_fn("w_mod", wv, wv2)
  out << declare_fn("w_neg", wv, wv)
  out << declare_fn("w_bit_and", wv, wv2)
  out << declare_fn("w_bit_or", wv, wv2)
  out << declare_fn("w_bit_xor", wv, wv2)
  out << declare_fn("w_bit_shl", wv, wv2)
  out << declare_fn("w_bit_shr", wv, wv2)

  # Comparison
  out << declare_fn("w_eq", wv, wv2)
  out << declare_fn("w_neq", wv, wv2)
  out << declare_fn("w_lt", wv, wv2)
  out << declare_fn("w_gt", wv, wv2)
  out << declare_fn("w_lte", wv, wv2)
  out << declare_fn("w_gte", wv, wv2)

  # I/O
  out << declare_fn("w_puts", wv, wv)
  out << declare_fn("w_print", wv, wv)
  out << declare_fn("w_to_s", wv, wv)
  out << declare_fn("w_str_concat", wv, wv2)
  out << declare_fn("w_str_append", wv, wv2)
  out << declare_fn("w_slab_freeze_safe", wv, "")
  out << "declare void @w_value_free(i64)\n"
  out << "declare void @w_slab_init_static(ptr, i32)\n"
  out << "declare void @__w_loc_set_col(ptr, i32, i32)\n"
  out << declare_fn("w_int_to_hex_str", wv, "i64")
  out << declare_fn_attrs("w_truthy", "i64", wv, "nounwind willreturn memory(none) speculatable alwaysinline")

  # Arrays — bare polymorphic constructor and the typed/sized form
  out << declare_fn("w_array_new_empty", wv, "")
  out << declare_fn("w_array_new", wv, "i64, i64")
  out << declare_fn("w_range_pow_sum", wv, "i64, i64, i64, i64")
  out << declare_fn("w_array_reuse_or_new", wv, "ptr")
  out << declare_fn("w_fused_out_reuse_or_new", wv, "ptr, i64, i64")
  out << declare_fn("w_array_push", wv, wv2)
  out << declare_fn("w_array_get", wv, wv2)
  out << declare_fn("w_array_get_i64", wv, "i64, i64")
  out << declare_fn("w_array_idx_i64", wv, "i64, i64")
  out << declare_fn("w_array_set", wv, wv3)
  out << declare_fn("w_array_set_i64", wv, "i64, i64, i64")
  out << declare_fn("w_array_size", wv, wv)
  out << declare_fn("w_array_pop", wv, wv)
  out << declare_fn("w_array_shift", wv, wv)
  out << declare_fn("w_array_cap", wv, wv)

  # Bool arrays
  out << declare_fn("w_bool_array_new", wv, "i64")
  out << declare_fn("w_bool_array_get", wv, wv2)
  out << declare_fn("w_bool_array_set", wv, wv3)
  # Phase 4e dot-prefix elementwise operators (.+ .- .* ./ .| .& .^ .<< .>>)
  out << declare_fn("w_array_add_elem", wv, wv2)
  out << declare_fn("w_array_sub_elem", wv, wv2)
  out << declare_fn("w_array_mul_elem", wv, wv2)
  out << declare_fn("w_array_div_elem", wv, wv2)
  out << declare_fn("w_array_bor_elem", wv, wv2)
  out << declare_fn("w_array_band_elem", wv, wv2)
  out << declare_fn("w_array_bxor_elem", wv, wv2)
  out << declare_fn("w_array_shl_elem", wv, wv2)
  out << declare_fn("w_array_shr_elem", wv, wv2)
  out << declare_fn("w_array_min_signed", wv, wv)
  out << declare_fn("w_array_min_unsigned", wv, wv)
  out << declare_fn("w_array_min_float", wv, wv)
  out << declare_fn("w_array_max_signed", wv, wv)
  out << declare_fn("w_array_max_unsigned", wv, wv)
  out << declare_fn("w_array_max_float", wv, wv)
  out << declare_fn("w_array_sum_signed", wv, wv)
  out << declare_fn("w_array_sum_unsigned", wv, wv)
  out << declare_fn("w_array_sum_float", wv, wv)
  out << declare_fn("w_array_fastsum_float", wv, wv)
  out << declare_fn("w_array_sumsq_float", wv, wv)
  out << declare_fn("w_array_dot_i8", wv, wv2)
  out << declare_fn("w_array_dot_float", wv, wv2)
  out << declare_fn("w_array_matvec_i8", wv, wv4)
  out << declare_fn("w_array_matmul_i8", wv, wv5)
  out << declare_fn("w_array_cross_float", wv, wv2)
  out << declare_fn("w_array_scale_float", wv, wv2)
  out << declare_fn("w_array_scale_float_bang", wv, wv2)
  out << declare_fn("w_array_cos_signed", wv, wv)
  out << declare_fn("w_array_cos_unsigned", wv, wv)
  out << declare_fn("w_array_cos_float", wv, wv)
  out << declare_fn("w_array_sin_signed", wv, wv)
  out << declare_fn("w_array_sin_unsigned", wv, wv)
  out << declare_fn("w_array_sin_float", wv, wv)
  out << declare_fn("w_array_sqrt_signed", wv, wv)
  out << declare_fn("w_array_sqrt_unsigned", wv, wv)
  out << declare_fn("w_array_sqrt_float", wv, wv)
  out << declare_fn("w_bool_array_size", wv, wv)

  # String builtins
  out << declare_fn("w_string_index", wv, wv3)
  out << declare_fn("w_string_rindex", wv, wv3)
  out << declare_fn("w_string_repeat", wv, wv2)
  out << declare_fn("w_string_count", wv, wv2)

  # Hashes
  out << declare_fn("w_hash_new", wv, "")
  out << declare_fn("w_hash_reuse_or_new", wv, "ptr")
  out << declare_fn("w_hash_set", wv, wv3)
  out << declare_fn("w_hash_get", wv, wv2)
  out << declare_fn("w_hash_has_key", wv, wv2)
  out << declare_fn("w_hash_keys", wv, wv)
  out << declare_fn("w_hash_values", wv, wv)
  out << declare_fn("w_hash_delete", wv, wv2)

  # Method dispatch
  out << declare_fn("w_method_call", wv, wv3)
  out << declare_fn("w_method_call_fast", wv, wv2_ptr_i32)
  out << declare_fn("w_method_call_cached", wv, join_arg_types5(wv, wv, "ptr", "i32", "ptr"))
  out << declare_fn("w_method_call_cached_0", wv, join_arg_types3(wv, wv, "ptr"))
  out << declare_fn("w_method_call_cached_1", wv, join_arg_types4(wv, wv, wv, "ptr"))
  out << declare_fn("w_value_is_a", wv, wv2)

  # Classes / objects
  out << declare_fn("w_class_new", wv, ptr_wv)
  out << declare_fn("w_class_new_wv", wv, wv2)
  out << declare_fn("w_class_add_method", "void", wv_ptr_ptr_i32)
  out << declare_fn("w_class_add_method_wv", "void", wv2_ptr_i32)
  out << declare_fn("w_class_add_static_method", "void", wv_ptr_ptr_i32)
  out << declare_fn("w_class_add_static_method_wv", "void", wv2_ptr_i32)
  out << declare_fn("w_type_class_register_wv", "void", i32_wv)
  out << declare_fn("w_node_kind_class_register_wv", "void", i32_wv)
  out << declare_fn("w_object_new", wv, wv)
  out << declare_fn("w_ivar_get", wv, wv_ptr)
  out << declare_fn("w_ivar_get_wv", wv, wv2)
  out << declare_fn("w_ivar_set", wv, wv_ptr_wv)
  out << declare_fn("w_ivar_set_wv", wv, wv3)
  out << declare_fn("w_ivar_get_idx", wv, wv_i32)
  out << declare_fn("w_ivar_set_idx", wv, wv_i32_wv)

  # PR #2 Phase 2: AST slab node primitives. w_node_alloc returns a
  # W_PACKED_NODE WValue for a freshly bumped arena slot; the field
  # load/store helpers do offset arithmetic on the encoded (sc, off)
  # pair inside the WValue. LTO inlines these at the call site.
  # i64 arg types match how ccall_nobox emits args on the call boundary.
  out << declare_fn("w_node_alloc", wv, "i64, i64")
  out << declare_fn("w_node_field_load", wv, "i64, i64")
  out << declare_fn("w_node_field_store", "void", "i64, i64, i64")
  out << declare_fn("w_ast_sparse_set", wv, "i64, i64, i64")
  out << declare_fn("w_ast_sparse_get", wv, "i64, i64")
  out << declare_fn("w_ast_sparse_copy", wv, "i64, i64")
  out << declare_fn("w_ast_intern_node", wv, "i64, i64")
  out << declare_fn("w_ast_intern_str_of", wv, "i64")
  out << declare_fn("w_ast_freeze_if_array", wv, "i64")
  out << declare_fn("w_node_arena_reset", "void", "")
  out << declare_fn("w_ast_schema_hash_compute", "i64", "")
  out << declare_fn("w_class_add_ivar", "i32", wv_ptr)
  out << declare_fn("w_class_add_ivar_wv", "i32", wv2)

  # Closures
  out << declare_fn("w_closure_new", wv, ptr_ptr_i32)
  out << declare_fn("w_closure_call_0", wv, wv)
  out << declare_fn("w_closure_call_1", wv, wv2)
  out << declare_fn("w_closure_call_2", wv, wv3)

  # Goroutines
  out << declare_fn("w_goroutine_spawn", wv, wv)
  out << declare_fn("w_goroutine_yield", "void", "")
  out << declare_fn("w_scheduler_run", "void", "")

  # Exceptions
  out << declare_fn("w_exception_push", "ptr", "")
  out << declare_fn("w_exception_pop", "void", "")
  out << declare_fn_noreturn("w_raise", "void", wv)
  out << declare_fn("w_exception_error", wv, "")
  out << declare_fn("w_block_return_push", "ptr", "")
  out << declare_fn("w_block_return_pop", "void", "ptr")
  out << declare_fn("w_block_return_value", wv, "ptr")
  out << declare_fn_noreturn("w_block_return_signal", "void", i64_wv)
  out << declare_fn_attrs("setjmp", "i32", "ptr", "nounwind returns_twice")

  # Memoization
  out << declare_fn("w_memo_init", "ptr", "ptr")
  out << declare_fn("w_memo_lookup", wv, "ptr, ptr, i32")
  out << declare_fn("w_memo_store", "void", ptr_ptr_i32_wv)
  out << declare_fn("w_memo_save", "void", ptr_ptr)
  out << declare_fn("__w_memo_call0_i64", wv, ptr_ptr)
  out << declare_fn("__w_memo_call1_i64", wv, ptr_ptr_wv)
  out << declare_fn("__w_memo_call2_i64", wv, join_arg_types4("ptr", "ptr", wv, wv))

  # Threads
  out << declare_fn("w_thread_spawn", wv, wv)
  out << declare_fn("w_thread_spawn_slots", wv, wv)
  out << declare_fn("w_thread_join", wv, wv)

  # Channels
  out << declare_fn("w_chan_new", wv, "i64")
  out << declare_fn("w_chan_send", wv, wv2)
  out << declare_fn("w_chan_recv", wv, wv)
  out << declare_fn("w_chan_close", wv, wv)

  # Argv / clock / primality
  out << declare_fn("w_argv_init", "void", "i32, ptr")
  out << declare_fn("__w_type", wv, wv)
  out << declare_fn_noreturn("__w_exit", wv, wv)
  out << declare_fn("__w_argv", wv, "")
  out << declare_fn("w_executable_path", wv, "")
  out << declare_fn("w_executable_dir", wv, "")
  out << declare_fn("w_runtime_dir", wv, "")
  out << declare_fn("__w_read_file", wv, wv)
  out << declare_fn("__w_read_file_bytes", wv, wv)
  out << declare_fn("__w_file_exists", wv, wv)
  out << declare_fn("__w_write_file", wv, wv2)
  out << declare_fn("__w_file_mmap", wv, wv)
  out << declare_fn("__w_mmap_length", wv, wv)
  out << declare_fn("__w_mmap_byte_at", wv, wv2)
  out << declare_fn("__w_mmap_close", wv, wv)
  out << declare_fn("__w_mmap_as_typed", wv, wv2)

  # Math.* libm wrappers
  out << declare_fn("w_math_exp", wv, wv)
  out << declare_fn("w_math_log", wv, wv)
  out << declare_fn("w_math_sin", wv, wv)
  out << declare_fn("w_math_cos", wv, wv)
  out << declare_fn("w_math_tan", wv, wv)
  out << declare_fn("w_math_sqrt", wv, wv)
  out << declare_fn("w_math_floor", wv, wv)
  out << declare_fn("w_math_ceil", wv, wv)
  out << declare_fn("w_math_round", wv, wv)
  out << declare_fn("w_math_abs", wv, wv)
  out << declare_fn("w_math_pow", wv, wv2)
  out << declare_fn("w_math_ldexp", wv, wv2)
  out << declare_fn("w_math_atan2", wv, wv2)

  # Raw libm — targets of :call_libm_f64 (the Math.* fast path on unboxed
  # operands). memory(none) is required for the loop vectorizer to widen
  # these to -fveclib SIMD variants (_simd_sin_d2 & co.) — a call that may
  # write memory only gets scalarized inside the vector loop. It is safe
  # here even where libm sets errno on range errors (glibc exp/log/pow):
  # Tungsten exposes no errno surface, so that write is never observable.
  libm_attrs = "nounwind willreturn memory(none)"
  dd = join_arg_types2("double", "double")
  out << declare_fn_attrs("sin", "double", "double", libm_attrs)
  out << declare_fn_attrs("cos", "double", "double", libm_attrs)
  out << declare_fn_attrs("tan", "double", "double", libm_attrs)
  out << declare_fn_attrs("exp", "double", "double", libm_attrs)
  out << declare_fn_attrs("log", "double", "double", libm_attrs)
  out << declare_fn_attrs("sqrt", "double", "double", libm_attrs)
  out << declare_fn_attrs("floor", "double", "double", libm_attrs)
  out << declare_fn_attrs("ceil", "double", "double", libm_attrs)
  out << declare_fn_attrs("round", "double", "double", libm_attrs)
  out << declare_fn_attrs("fabs", "double", "double", libm_attrs)
  out << declare_fn_attrs("pow", "double", dd, libm_attrs)
  out << declare_fn_attrs("atan2", "double", dd, libm_attrs)

  # Float bit-cast
  out << declare_fn("w_float_from_u32_bits", wv, wv)
  out << declare_fn("w_float_to_u32_bits", wv, wv)
  out << declare_fn("w_float_from_u64_bits", wv, wv)
  out << declare_fn("w_float_to_u64_bits", wv, wv)
  out << declare_fn("__w_system", wv, wv)
  out << declare_fn("__w_capture", wv, wv)
  out << declare_fn("__w_argv_count", wv, "")
  out << declare_fn("__w_argv_at", wv, wv)
  out << declare_fn("__w_clock_ms", wv, "")
  out << declare_fn("__w_sleep_ms", wv, wv)
  out << declare_fn("__w_clock", wv, "")
  out << declare_fn("__w_prime_aks", wv, wv)

  # Direct built-in constructors (skip method dispatch)
  out << declare_fn("w_response_new_wv", wv, wv2)
  out << declare_fn("w_strbuf_new", wv, wv)
  out << declare_fn("w_strbuf_reuse_or_new", wv, "ptr, i64")
  out << declare_fn("w_array_recycle_or_new_empty", wv, "")
  out << declare_fn("w_hash_recycle_or_new", wv, "")
  out << declare_fn("w_hash_reuse_and_drain_or_new", wv, "ptr")
  out << declare_fn("w_array_recycle_or_new", wv, "i64, i64")
  out << declare_fn("w_array_reuse_or_new_empty", wv, "ptr")
  out << declare_fn("w_strbuf_recycle_or_new", wv, "i64")
  out << declare_fn("w_array_recycle_public", "void", wv)
  out << declare_fn("w_hash_recycle", "void", wv)
  out << declare_fn("w_array_recycle", "void", wv)
  out << declare_fn("w_strbuf_recycle", "void", wv)
  out << declare_fn("w_cleanup_push", "void", "i64, ptr")
  out << declare_fn("w_cleanup_pop", "void", "")
  out << declare_fn("w_array_copy_range", wv, wv4)

  out.to_s()

-> declare_fn(name, ret_type, arg_types_str)
  declare_fn_attrs(name, ret_type, arg_types_str, "nounwind")

-> declare_fn_noreturn(name, ret_type, arg_types_str)
  declare_fn_attrs(name, ret_type, arg_types_str, "noreturn cold nounwind")

-> declare_fn_attrs(name, ret_type, arg_types_str, attrs)
  out = StringBuffer(ret_type.size() + name.size() + arg_types_str.size() + attrs.size() + 20)
  out << "declare "
  out << ret_type
  out << " @"
  out << name
  out << "("
  out << arg_types_str
  out << ") "
  out << attrs
  out << "\n"
  out.to_s()

-> join_arg_types2(lhs, rhs)
  out = StringBuffer(lhs.size() + rhs.size() + 2)
  out << lhs
  out << ", "
  out << rhs
  out.to_s()

-> join_arg_types3(a, b, c)
  out = StringBuffer(a.size() + b.size() + c.size() + 4)
  out << a
  out << ", "
  out << b
  out << ", "
  out << c
  out.to_s()

-> join_arg_types4(a, b, c, d)
  out = StringBuffer(a.size() + b.size() + c.size() + d.size() + 6)
  out << a
  out << ", "
  out << b
  out << ", "
  out << c
  out << ", "
  out << d
  out.to_s()

-> join_arg_types5(a, b, c, d, e)
  out = StringBuffer(a.size() + b.size() + c.size() + d.size() + e.size() + 8)
  out << a
  out << ", "
  out << b
  out << ", "
  out << c
  out << ", "
  out << d
  out << ", "
  out << e
  out.to_s()

# -- Runtime declaration filtering --

# Extract function name from a declare line: "declare i64 @w_foo(...)" → "w_foo"
-> runtime_decl_name(line)
  at = line.index("@")
  if at == nil
    return nil
  tail = line.slice(at + 1, line.size() - at - 1)
  lparen = tail.index("(")
  if lparen == nil
    return nil
  tail.slice(0, lparen)

# Filter runtime declarations to only those in the used_fns set.
# Inline fast-path helpers for raw-index array reads, emitted as private
# alwaysinline IR functions so LLVM folds the polymorphic-array (ebits=65)
# fast path into every call site without needing LTO. Packed body refs,
# typed arrays, and out-of-bounds indexes branch to the full runtime
# decoders, which own those semantics. Layout facts (tag nibble 0xA, ebits
# at +1, start at +4, size at +8, slots ptr at +16) are locked by the
# _Static_asserts in runtime.h.
-> array_fast_helpers_ir()
  # NOTE: written as explicit `out <<` appends, not a `<<~` heredoc: this is
  # compiler source, which the C VM stage-0 bootstrap (implementations/c) must
  # parse, and that lexer has no heredoc support. Heredocs work only in the
  # self-hosted compiler and user programs.
  out = StringBuffer(2200)
  out << "define private i64 @__w_array_get_i64_fast(i64 %arr, i64 %i) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << "  %hi = lshr i64 %arr, 48\n"
  out << "  %lo0 = icmp eq i64 %hi, 0\n"
  out << "  %ge16 = icmp uge i64 %arr, 16\n"
  out << "  %obj = and i1 %lo0, %ge16\n"
  out << "  %sub = and i64 %arr, 15\n"
  out << "  %isarr = icmp eq i64 %sub, 10\n"
  out << "  %objarr = and i1 %obj, %isarr\n"
  out << "  br i1 %objarr, label %hdr, label %slow\n"
  out << "hdr:\n"
  out << "  %base = and i64 %arr, -16\n"
  out << "  %p = inttoptr i64 %base to ptr\n"
  out << "  %ebp = getelementptr i8, ptr %p, i64 1\n"
  out << "  %eb = load i8, ptr %ebp, align 1\n"
  out << "  %is65 = icmp eq i8 %eb, 65\n"
  out << "  br i1 %is65, label %rng, label %slow\n"
  out << "rng:\n"
  out << "  %szp = getelementptr i8, ptr %p, i64 8\n"
  out << "  %sz32 = load i32, ptr %szp, align 4\n"
  out << "  %sz = sext i32 %sz32 to i64\n"
  out << "  %neg = icmp slt i64 %i, 0\n"
  out << "  %iw = add i64 %i, %sz\n"
  out << "  %ix = select i1 %neg, i64 %iw, i64 %i\n"
  out << "  %inb = icmp ult i64 %ix, %sz\n"
  out << "  br i1 %inb, label %fast, label %slow\n"
  out << "fast:\n"
  out << "  %stp = getelementptr i8, ptr %p, i64 4\n"
  out << "  %st32 = load i32, ptr %stp, align 4\n"
  out << "  %st = sext i32 %st32 to i64\n"
  out << "  %eff = add i64 %st, %ix\n"
  out << "  %slp = getelementptr i8, ptr %p, i64 16\n"
  out << "  %slots = load ptr, ptr %slp, align 8\n"
  out << "  %ep = getelementptr i64, ptr %slots, i64 %eff\n"
  out << "  %v = load i64, ptr %ep, align 8\n"
  out << "  ret i64 %v\n"
  out << "slow:\n"
  out << "  %sv = call i64 @w_array_get_i64(i64 %arr, i64 %i)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out << "define private i64 @__w_array_idx_i64_fast(i64 %arr, i64 %i) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << "  %hi = lshr i64 %arr, 48\n"
  out << "  %lo0 = icmp eq i64 %hi, 0\n"
  out << "  %ge16 = icmp uge i64 %arr, 16\n"
  out << "  %obj = and i1 %lo0, %ge16\n"
  out << "  %sub = and i64 %arr, 15\n"
  out << "  %isarr = icmp eq i64 %sub, 10\n"
  out << "  %objarr = and i1 %obj, %isarr\n"
  out << "  br i1 %objarr, label %hdr, label %slow\n"
  out << "hdr:\n"
  out << "  %base = and i64 %arr, -16\n"
  out << "  %p = inttoptr i64 %base to ptr\n"
  out << "  %ebp = getelementptr i8, ptr %p, i64 1\n"
  out << "  %eb = load i8, ptr %ebp, align 1\n"
  out << "  %is65 = icmp eq i8 %eb, 65\n"
  out << "  br i1 %is65, label %fast, label %slow\n"
  out << "fast:\n"
  out << "  %stp = getelementptr i8, ptr %p, i64 4\n"
  out << "  %st32 = load i32, ptr %stp, align 4\n"
  out << "  %st = sext i32 %st32 to i64\n"
  out << "  %eff = add i64 %st, %i\n"
  out << "  %slp = getelementptr i8, ptr %p, i64 16\n"
  out << "  %slots = load ptr, ptr %slp, align 8\n"
  out << "  %ep = getelementptr i64, ptr %slots, i64 %eff\n"
  out << "  %v = load i64, ptr %ep, align 8\n"
  out << "  ret i64 %v\n"
  out << "slow:\n"
  out << "  %sv = call i64 @w_array_idx_i64(i64 %arr, i64 %i)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out.to_s()

# Inline comparison fast paths, same private-alwaysinline scheme as the
# array helpers below: when BOTH operands are immediate Ints (tag 0xFFFA),
# the compare folds to an inline icmp at the call site; anything else
# (floats, BigInts, strings, chars, decimals) calls the runtime operator,
# which owns the full type ladder. eq/neq compare full bits (equal tags
# make payload equality bit equality); ordered compares sign-extend the
# 48-bit payloads first.
-> cmp_fast_helper_ir(fast_name, slow_name, pred, sext_payload)
  out = StringBuffer(760)
  out << "define private i64 @" + fast_name + "(i64 %a, i64 %b) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << "  %ta = lshr i64 %a, 48\n"
  out << "  %ia = icmp eq i64 %ta, 65530\n"
  out << "  %tb = lshr i64 %b, 48\n"
  out << "  %ib = icmp eq i64 %tb, 65530\n"
  out << "  %both = and i1 %ia, %ib\n"
  out << "  br i1 %both, label %fast, label %slow\n"
  out << "fast:\n"
  if sext_payload
    out << "  %sa = shl i64 %a, 16\n"
    out << "  %pa = ashr i64 %sa, 16\n"
    out << "  %sb = shl i64 %b, 16\n"
    out << "  %pb = ashr i64 %sb, 16\n"
    out << "  %c = icmp " + pred + " i64 %pa, %pb\n"
  else
    out << "  %c = icmp " + pred + " i64 %a, %b\n"
  out << "  %r = select i1 %c, i64 2, i64 1\n"
  out << "  ret i64 %r\n"
  out << "slow:\n"
  out << "  %sv = call i64 @" + slow_name + "(i64 %a, i64 %b)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out.to_s()

-> filter_runtime_decls(decls, used_fns)
  lines = decls.split("\n")
  out = StringBuffer(decls.size())
  i = 0
  while i < lines.size()
    line = lines[i]
    if line != ""
      name = runtime_decl_name(line)
      if name != nil && used_fns[name] == true
        out << line
        out << "\n"
    i += 1
  out.to_s()

-> function_attr_text(frame_pointers, host_fn_attrs)
  out = StringBuffer(160)
  out << "nounwind"
  if host_fn_attrs != nil && host_fn_attrs != ""
    out << " "
    out << host_fn_attrs
  if frame_pointers
    # `nounwind` lets LLVM drop unwind tables, so emitted fns get no
    # .eh_frame CFI — fine on macOS (backtrace() walks frame pointers) but
    # fatal on Linux, where glibc's backtrace()/_Unwind_Backtrace can only
    # step through frames that carry CFI. Without it the unwind dies at the
    # first Tungsten frame and outer fn-meta frames never show. `uwtable`
    # forces async unwind tables (matching clang's Linux default) so
    # --frame-pointers yields a full backtrace on both platforms.
    out << " uwtable \"frame-pointer\"=\"all\""
  out.to_s()

-> function_attr_group_id(attr_groups, attr_text)
  ids = attr_groups[:ids]
  existing = ids[attr_text]
  if existing != nil
    return existing
  texts = attr_groups[:texts]
  id = texts.size()
  ids[attr_text] = id
  texts.push(attr_text)
  id

-> emit_function_attr_groups(attr_groups)
  texts = attr_groups[:texts]
  if texts == nil || texts.size() == 0
    return ""
  out = StringBuffer(texts.size() * 180 + 16)
  out << "\n"
  i = 0
  while i < texts.size()
    out << "attributes #"
    out << i.to_s()
    out << " = { "
    out << texts[i]
    out << " }\n"
    i += 1
  out.to_s()

-> call_prefix(inst)
  prefix = "call"
  if inst[:src_line] != nil
    prefix = "notail call"
  cc = inst[:call_conv]
  if cc != nil && cc != ""
    prefix = prefix + " " + cc
  prefix

-> range_metadata_suffix(inst, llvm_type)
  low = inst[:range_low]
  high = inst[:range_high]
  if low == nil || high == nil
    return ""
  ", !range !{" + llvm_type + " " + low.to_s() + ", " + llvm_type + " " + high.to_s() + "}"

-> direct_range_metadata_suffix(llvm_type, low, high)
  ", !range !{" + llvm_type + " " + low.to_s() + ", " + llvm_type + " " + high.to_s() + "}"

-> wvalue_int_range_metadata_suffix(low, high)
  direct_range_metadata_suffix("i64", w_tag_int + low, w_tag_int + high)

-> wvalue_bool_range_metadata_suffix()
  direct_range_metadata_suffix("i64", w_false, w_true + 1)

-> wvalue_char_range_metadata_suffix()
  # Char WValues are the 0xFFFC tag with subtype 11 (bits 47..46).
  subtype_span = 70368744177664
  direct_range_metadata_suffix("i64", w_tag_char + subtype_span * 3, w_tag_char + subtype_span * 4)

-> wvalue_bool_call?(name)
  name in ("w_bool" "w_eq" "w_neq" "w_lt" "w_gt" "w_lte" "w_gte" "__w_eq_fast" "__w_neq_fast" "__w_lt_fast" "__w_gt_fast" "__w_lte_fast" "__w_gte_fast" "w_hash_has_key" "__w_file_exists" "__w_write_file" "w_ipv4_in_cidr")

-> known_call_range_metadata_suffix(inst, llvm_type)
  suffix = range_metadata_suffix(inst, llvm_type)
  if suffix != ""
    return suffix
  if llvm_type == "i64"
    name = inst[:name]
    if name == "w_truthy"
      return direct_range_metadata_suffix("i64", 0, 2)
    if name == "w_box_char"
      return wvalue_char_range_metadata_suffix()
    if wvalue_bool_call?(name)
      return wvalue_bool_range_metadata_suffix()
  ""

-> w_int_call_with_range(temp, raw, low, high)
  temp + " = call i64 @w_int(i64 " + raw + ")" + wvalue_int_range_metadata_suffix(low, high)

# Lowering sets this bit only for an exact source-class receiver whose own
# method table contains the one-argument target. Native and unknown receivers
# retain the established pointer-plus-count dispatch ABI.
-> scalar_source_one_call?(inst)
  inst[:op] == :call_method_i64 && inst[:args] != nil && inst[:args].size() == 1 && inst[:scalar_source_argc1] == true

# Return the runtime function names that an instruction will reference when rendered.
-> runtime_fns_for_inst(inst, string_wvs = nil)
  case inst[:op]
  when :call_direct_i64, :call_direct_i128, :call_direct_void, :call_direct_ptr
    # w_node_field_store renders as inline slab IR when the offset is a
    # literal, and that IR calls the array-freeze helper directly — the
    # helper never appears as an instruction, so declare it alongside.
    if inst[:name] == "w_node_field_store"
      return ["w_node_field_store", "w_ast_freeze_if_array"]
    [inst[:name]]
  when :slab_alloc_init
    # The intrinsic's emitted IR calls w_node_alloc (cap-exhausted slow
    # path) and w_ast_freeze_if_array (field freeze pre-pass) as raw
    # strings — neither appears as a :call_direct instruction.
    ["w_node_alloc", "w_ast_freeze_if_array"]
  when :call_direct_i64_ptr1, :call_direct_void_ptr1
    [inst[:name]]
  when :call_libm_f64
    [inst[:name]]
  when :call_loc_set_col
    ["__w_loc_set_col"]
  when :call_reuse_or_new_array
    ["w_array_reuse_or_new_empty"]
  when :call_reuse_or_new_hash
    ["w_hash_reuse_or_new"]
  when :call_reuse_or_new_typed
    ["w_array_reuse_or_new"]
  when :call_fused_out_reuse
    ["w_fused_out_reuse_or_new"]
  when :call_reuse_or_new_strbuf
    ["w_strbuf_reuse_or_new"]
  when :call_reuse_and_drain_or_new_hash
    ["w_hash_reuse_and_drain_or_new"]
  when :call_recycle_or_new_array
    ["w_array_recycle_or_new_empty"]
  when :call_recycle_or_new_hash
    ["w_hash_recycle_or_new"]
  when :call_recycle_or_new_typed
    ["w_array_recycle_or_new"]
  when :call_recycle_or_new_strbuf
    ["w_strbuf_recycle_or_new"]
  when :call_recycle_array
    ["w_array_recycle_public"]
  when :call_recycle_hash
    ["w_hash_recycle"]
  when :call_recycle_typed
    ["w_array_recycle"]
  when :call_recycle_strbuf
    ["w_strbuf_recycle"]
  when :cleanup_push_array
    ["w_cleanup_push", "w_array_recycle_public"]
  when :cleanup_push_hash
    ["w_cleanup_push", "w_hash_recycle"]
  when :cleanup_push_typed
    ["w_cleanup_push", "w_array_recycle"]
  when :cleanup_push_strbuf
    ["w_cleanup_push", "w_strbuf_recycle"]
  when :cleanup_pop
    ["w_cleanup_pop"]

  when :puts_i64
    ["w_puts"]
  when :print_i64
    ["w_print"]
  when :argv_init
    ["w_argv_init"]

  when :string_i64
    ["w_string"]
  when :symbol_i64
    ["w_string", "w_str_to_sym"]
  when :view_load_byte, :view_load_bit
    # Dynamic byte/bit views still produce language Integers directly.
    ["w_int"]
  when :view_load_field, :view_load_inline_byte
    # Named fields stay in their declared machine representation; lowering
    # inserts boxing only when the value crosses a WValue boundary.
    []
  when :register_unit
    if string_wvs != nil && string_wvs[inst[:str_id]] != nil
      ["w_register_unit_wv"]
    else
      ["w_string", "w_register_unit_wv"]

  when :class_new, :builtin_class_init
    if string_wvs != nil && string_wvs[inst[:name_str_id]] != nil
      ["w_class_new_wv"]
    else
      ["w_string", "w_class_new_wv"]
  when :class_add_method
    if string_wvs != nil && string_wvs[inst[:method_str_id]] != nil
      ["w_class_add_method_wv"]
    else
      ["w_string", "w_class_add_method_wv"]
  when :class_add_static_method
    if string_wvs != nil && string_wvs[inst[:method_str_id]] != nil
      ["w_class_add_static_method_wv"]
    else
      ["w_string", "w_class_add_static_method_wv"]
  when :class_add_ivar
    if string_wvs != nil && string_wvs[inst[:ivar_str_id]] != nil
      ["w_class_add_ivar_wv"]
    else
      ["w_string", "w_class_add_ivar_wv"]

  when :ivar_get
    if string_wvs != nil && string_wvs[inst[:str_id]] != nil
      ["w_ivar_get_wv"]
    else
      ["w_string", "w_ivar_get_wv"]
  when :ivar_set
    if string_wvs != nil && string_wvs[inst[:str_id]] != nil
      ["w_ivar_set_wv"]
    else
      ["w_string", "w_ivar_set_wv"]

  when :call_method_i64
    if inst[:args].size() == 0
      ["w_method_call_cached_0"]
    elsif scalar_source_one_call?(inst)
      ["w_method_call_cached_1"]
    else
      ["w_method_call_cached"]
  when :closure_new
    ["w_closure_new"]
  when :free_value
    ["w_value_free"]

  when :memo_init
    ["w_memo_init"]
  when :memo_call0_i64
    ["__w_memo_call0_i64"]
  when :memo_call1_i64
    ["__w_memo_call1_i64"]
  when :memo_call2_i64
    ["__w_memo_call2_i64"]

  when :setjmp
    ["setjmp"]

  when :const_decimal
    ["w_decimal"]
  when :const_currency
    ["w_currency"]
  when :const_quantity
    ["w_quantity"]
  when :const_duration_ns
    ["w_duration_ns"]
  when :const_duration_months_ms
    ["w_duration_months_ms"]
  when :const_uuid
    ["w_uuid_from_hex"]
  when :const_date
    ["w_date"]
  when :const_ipv4
    ["w_ipv4"]
  when :const_ipv6
    ["w_ipv6_from_string"]
  when :const_rational
    ["w_rational"]
  when :const_char
    ["w_box_char"]
  when :const_color
    ["w_color"]
  when :type_class_register
    ["w_type_class_register_wv"]
  when :node_kind_class_register
    ["w_node_kind_class_register_wv"]

  when :add_i48_checked, :sub_i48_checked, :mul_i48_checked
    [inst[:rt_fallback]]
  when :add_i48_guarded, :sub_i48_guarded, :mul_i48_guarded
    [inst[:rt_fallback]]
  else
    nil

# -- Emit a complete LLVM IR artifact --

# -- Call-site metadata table for runtime column-level error reporting --
#
# Companion to the fn-meta table: records (file, line, col) for every
# method-dispatch site that carries source-loc info. The lowering splits
# each such call into its own basic block labelled `cs.<ic_id>.ret`; we
# emit `blockaddress(@fn, %cs.N.ret)` as the lookup key. At error time,
# the innermost PC captured by `backtrace()` should land on (or right
# after) that block's first instruction, so the runtime can resolve
# the exact dispatch that failed.

-> collect_call_sites(mod)
  sites = []
  files = {}
  next_file_id = 0
  fi = 0
  while fi < mod[:functions].size()
    f = mod[:functions][fi]
    fn_path = f[:source_path]
    if fn_path == nil
      fn_path = "<unknown>"
    bi = 0
    while bi < f[:blocks].size()
      blk = f[:blocks][bi]
      ii = 0
      while ii < blk[:instructions].size()
        inst = blk[:instructions][ii]
        if inst[:src_line] != nil
          ret_label = nil
          if inst[:op] == :call_method_i64
            ret_label = "cs." + inst[:ic_id].to_s() + ".ret"
          elsif inst[:op] in (:call_direct_void :call_direct_i64) && inst[:loc_site_id] != nil
            ret_label = "csd." + inst[:loc_site_id].to_s() + ".ret"
          if ret_label != nil
            file_id = files[fn_path]
            if file_id == nil
              file_id = next_file_id
              files[fn_path] = file_id
              next_file_id = next_file_id + 1
            col_val = inst[:src_col]
            if col_val == nil
              col_val = 0
            sites.push({
              fn_name: f[:name],
              ret_label: ret_label,
              file_id: file_id,
              line: inst[:src_line],
              col: col_val
            })
        ii += 1
      bi += 1
    fi += 1
  {sites: sites, files: files}

-> emit_call_site_table(mod)
  info = collect_call_sites(mod)
  sites = info[:sites]
  files = info[:files]
  out = StringBuffer(sites.size() * 120 + 512)
  lbr = "\["
  rbr = "]"

  # One private constant per unique source file path.
  file_keys = files.keys()
  # Build id-sorted key list so emission order matches id values.
  id_to_key = {}
  fi = 0
  while fi < file_keys.size()
    k = file_keys[fi]
    id_to_key[files[k]] = k
    fi += 1
  fi = 0
  while fi < file_keys.size()
    k = id_to_key[fi]
    bl = utf8_byte_length(k) + 1
    out << "@.wcs.file."
    out << fi.to_s()
    out << " = private unnamed_addr constant "
    out << lbr
    out << bl.to_s()
    out << " x i8"
    out << rbr
    out << " c\""
    out << escape_llvm_string(k)
    out << "\\00\", align 1\n"
    fi += 1
  if file_keys.size() > 0
    out << "\n"

  # The call-site array.
  out << "@__w_call_site = constant "
  out << lbr
  out << sites.size().to_s()
  out << " x { ptr, ptr, i32, i32 }"
  out << rbr
  if sites.size() == 0
    out << " zeroinitializer\n"
  else
    out << " "
    out << lbr
    out << "\n"
    si = 0
    while si < sites.size()
      s = sites[si]
      out << "  { ptr, ptr, i32, i32 } { ptr blockaddress(@"
      out << s[:fn_name]
      out << ", %"
      out << s[:ret_label]
      out << "), ptr @.wcs.file."
      out << s[:file_id].to_s()
      out << ", i32 "
      out << s[:line].to_s()
      out << ", i32 "
      out << s[:col].to_s()
      out << " }"
      if si < sites.size() - 1
        out << ","
      out << "\n"
      si += 1
    out << rbr
    out << "\n"
  out << "@__w_call_site_count = constant i32 "
  out << sites.size().to_s()
  out << "\n\n"

  out.to_s()

# -- Function metadata table for runtime backtrace formatting --
#
# Emits a sorted-at-init `__w_fn_meta` array of {ptr fn, ptr file, ptr name,
# i32 line, i32 kind} rows — one per lowered function. Runtime walks the C
# backtrace, binary-searches by PC, and prints e.g. `Foo#bar (game.w:54)`
# instead of the mangled `__wy_…` symbol. All metadata is sourced from
# fields the lowering already attaches to each fn dict (:source_method,
# :source_class, :source_path, :source_line, :source_kind), so this pass
# is a read-only consumer.

-> fn_meta_kind_to_int(kind)
  if kind == :method
    1
  elsif kind == :static_method
    2
  elsif kind == :fn_def
    3
  elsif kind == :block
    4
  elsif kind == :entry
    5
  elsif kind == :static_wrapper
    6
  else
    0

-> fn_meta_display_name(f)
  name = f[:source_method]
  if name == nil
    name = f[:original_name]
  if name == nil
    name = f[:name]
  klass = f[:source_class]
  kind = f[:source_kind]
  if klass != nil && klass != ""
    if kind in (:static_method :static_wrapper)
      klass + "." + name
    else
      klass + "#" + name
  elsif kind == :block
    "block in " + name
  else
    name

-> emit_fn_meta_table(mod)
  fns = mod[:functions]
  out = StringBuffer(fns.size() * 200 + 256)
  lbr = "\["
  rbr = "]"

  # Per-fn private string constants for display name + source file.
  i = 0
  while i < fns.size()
    f = fns[i]
    display = fn_meta_display_name(f)
    file_str = f[:source_path]
    if file_str == nil
      file_str = "<unknown>"
    name_bl = utf8_byte_length(display) + 1
    file_bl = utf8_byte_length(file_str) + 1

    out << "@.wfm."
    out << i.to_s()
    out << ".n = private unnamed_addr constant "
    out << lbr
    out << name_bl.to_s()
    out << " x i8"
    out << rbr
    out << " c\""
    out << escape_llvm_string(display)
    out << "\\00\", align 1\n"

    out << "@.wfm."
    out << i.to_s()
    out << ".f = private unnamed_addr constant "
    out << lbr
    out << file_bl.to_s()
    out << " x i8"
    out << rbr
    out << " c\""
    out << escape_llvm_string(file_str)
    out << "\\00\", align 1\n"
    i += 1
  if fns.size() > 0
    out << "\n"

  # The meta table itself.
  out << "@__w_fn_meta = constant "
  out << lbr
  out << fns.size().to_s()
  out << " x { ptr, ptr, ptr, i32, i32 }"
  out << rbr
  if fns.size() == 0
    out << " zeroinitializer\n"
  else
    out << " "
    out << lbr
    out << "\n"
    i = 0
    while i < fns.size()
      f = fns[i]
      line = f[:source_line]
      if line == nil
        if f[:source_kind] == :entry
          line = 1
        else
          line = 0
      kind_int = fn_meta_kind_to_int(f[:source_kind])
      out << "  { ptr, ptr, ptr, i32, i32 } { ptr @"
      out << f[:name]
      out << ", ptr @.wfm."
      out << i.to_s()
      out << ".f, ptr @.wfm."
      out << i.to_s()
      out << ".n, i32 "
      out << line.to_s()
      out << ", i32 "
      out << kind_int.to_s()
      out << " }"
      if i < fns.size() - 1
        out << ","
      out << "\n"
      i += 1
    out << rbr
    out << "\n"
  out << "@__w_fn_meta_count = constant i32 "
  out << fns.size().to_s()
  out << "\n\n"

  out.to_s()

-> emit_stacktrace_llvm_used()
  "@llvm.used = appending global \[4 x ptr] \[ptr @__w_fn_meta, ptr @__w_fn_meta_count, ptr @__w_call_site, ptr @__w_call_site_count], section \"llvm.metadata\"\n\n"

-> address_taken_function_for_inst(inst)
  op = inst[:op]
  if op in (:class_add_method :class_add_static_method :closure_new)
    return inst[:fn_name]
  if op in (:memo_call0_i64 :memo_call1_i64 :memo_call2_i64)
    return inst[:fn_name]
  nil

-> collect_address_taken_functions(mod)
  taken = {}
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    bi = 0
    while bi < func[:blocks].size()
      instrs = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instrs.size()
        fname = address_taken_function_for_inst(instrs[ii])
        if fname != nil
          taken[fname] = true
        ii += 1
      bi += 1
    fi += 1
  taken

-> internal_fastcc_candidate?(func, address_taken)
  if func[:llvm_internal] != true
    return false
  if func[:is_toplevel] == true
    return false
  if func[:return_type] != "i64"
    return false
  if address_taken[func[:name]] == true
    return false
  true

-> fastcc_direct_call_op?(op)
  op in (:call_direct_i64 :call_direct_i128 :call_direct_void :call_direct_ptr :call_direct_i64_ptr1 :call_direct_void_ptr1)

-> apply_fastcc_plan(mod)
  if env("TUNGSTEN_LLVM_FASTCC") != "1"
    mod[:fastcc_count] = 0
    return nil

  address_taken = collect_address_taken_functions(mod)
  fastcc_names = {}
  count = 0
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    if internal_fastcc_candidate?(func, address_taken)
      func[:call_conv] = "fastcc"
      fastcc_names[func[:name]] = true
      count += 1
    fi += 1

  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    bi = 0
    while bi < func[:blocks].size()
      instrs = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instrs.size()
        inst = instrs[ii]
        if fastcc_direct_call_op?(inst[:op]) && fastcc_names[inst[:name]] == true
          inst[:call_conv] = "fastcc"
        ii += 1
      bi += 1
    fi += 1

  mod[:fastcc_count] = count
  nil

-> emit_artifact(mod, frame_pointers = false)
  datalayout = mod[:llvm_datalayout]
  triple = mod[:llvm_triple]

  header = "; Tungsten compiled module (WIRE pipeline)\n"
  if datalayout != ""
    header = header + "target datalayout = \"" + datalayout + "\"\n"
  if triple != ""
    header = header + "target triple = \"" + triple + "\"\n"
  header = header + "\n"

  # Build static slab and string WValue map before dependency collection so
  # runtime declarations match the path render_instruction will actually emit.
  slab_info = build_string_wvalues(mod[:strings], mod[:no_static_slab] == true)
  mod[:string_wvalues] = slab_info[:wvalues]

  # ccall foreign function declarations — collect all call_direct_i64 targets,
  # then declare any that aren't already in the runtime declarations or
  # defined as module functions.
  known_fns = {}
  # Collect all function names defined in this module
  fi = 0
  while fi < mod[:functions].size()
    known_fns[mod[:functions][fi][:name]] = true
    fi += 1
  # Collect all call targets that need declarations, and track used runtime functions
  ccall_needed = {}
  used_runtime_fns = {}
  fi = 0
  while fi < mod[:functions].size()
    wfunc = mod[:functions][fi]
    bi = 0
    while bi < wfunc[:blocks].size()
      blk = wfunc[:blocks][bi]
      ii = 0
      while ii < blk[:instructions].size()
        inst = blk[:instructions][ii]
        if inst[:op] == :call_direct_i64 && inst[:name] != nil
          iname = inst[:name]
          if !known_fns.has_key?(iname) && !ccall_needed.has_key?(iname)
            ccall_needed[iname] = inst[:args].size()
        fns = runtime_fns_for_inst(inst, mod[:string_wvalues])
        if fns != nil
          ri = 0
          while ri < fns.size()
            used_runtime_fns[fns[ri]] = true
            ri += 1
        ii += 1
      bi += 1
    fi += 1
  globals_out = StringBuffer(4096)

  # Memo table globals
  memo_tables = mod[:fn_memo_tables]
  if memo_tables != nil
    memo_keys = mod[:used_memo_table_order]
    if memo_keys == nil
      memo_keys = memo_tables.keys().sort()
    emitted_memo_globals = {}
    emitted_memo_global_count = 0
    mk = 0
    while mk < memo_keys.size()
      global_name = memo_tables[memo_keys[mk]]
      if global_name != nil && emitted_memo_globals[global_name] != true
        emitted_memo_globals[global_name] = true
        emitted_memo_global_count += 1
        globals_out << "@"
        globals_out << global_name
        globals_out << " = internal global ptr null\n"
      mk += 1
    if emitted_memo_global_count > 0
      globals_out << "\n"

  # Class globals
  classes = mod[:known_classes]
  if classes != nil
    class_keys = classes.keys().sort()
    ck = 0
    while ck < class_keys.size()
      globals_out << "@class."
      globals_out << class_keys[ck].gsub(":", "__")
      globals_out << " = internal global i64 0\n"
      ck += 1
    if class_keys.size() > 0
      globals_out << "\n"

  # Top-level variable globals
  #
  # A var declared `NAME = INT_LIT ## i64` with a single top-level
  # assignment is emitted as `internal constant i64 N`. The store at
  # module-init time was skipped in lowering, and every `load i64, ptr
  # @global.NAME` folds to the literal during LLVM optimization.
  tlv = mod[:top_level_vars]
  if tlv != nil
    const_values = mod[:top_level_const_values]
    if const_values == nil
      const_values = {}
    var_types = mod[:top_level_var_types]
    if var_types == nil
      var_types = {}
    tlv_keys = tlv.keys().sort()
    ti = 0
    while ti < tlv_keys.size()
      nm = tlv_keys[ti]
      globals_out << "@global."
      globals_out << nm
      cv = const_values[nm]
      if cv != nil
        globals_out << " = internal constant i64 "
        # llvm_wvalue_literal formats as `u0xHEX16`, which LLVM accepts
        # for global initializers and avoids signed-overflow issues for
        # values > 2^63 (e.g. AST_NIL = u0xFFFE60CC00000000).
        globals_out << llvm_wvalue_literal(cv)
        globals_out << "\n"
      else
        # Match the storage width to the var's machine type. u128/i128
        # vars (`## u128` / `## i128` annotation) need an i128 global;
        # otherwise stores from i128 arithmetic produce IR with a type
        # mismatch (store i64 %iN where %iN is i128).
        gty = "i64"
        vt = var_types[nm]
        if vt == :i128 || vt == :u128
          gty = "i128"
        globals_out << " = internal global "
        globals_out << gty
        globals_out << " 0\n"
      ti += 1
    if tlv_keys.size() > 0
      globals_out << "\n"

  # Class variable globals. The cvar key is `ClassName.var_name`;
  # when the class is namespace-qualified (e.g. `Tungsten:Carbide:
  # Application`), the colons would land in the LLVM identifier
  # name, which is illegal. Mangle `:` → `__` to match the class-
  # global mangling above.
  cvg = mod[:cvar_globals]
  if cvg != nil
    cvg_keys = cvg.keys().sort()
    ci = 0
    while ci < cvg_keys.size()
      globals_out << "@cvar."
      globals_out << cvg_keys[ci].gsub(":", "__")
      globals_out << " = internal global i64 0\n"
      ci += 1
    if cvg_keys.size() > 0
      globals_out << "\n"

  # Inline cache: one 24-byte slot per method call site and native thread.
  # A shared cache races during first-use publication (type/fn/arity are three
  # independent fields), which can send a concurrent Thread.new call through
  # the wrong ABI.  Per-thread ICs also avoid polymorphic cache ping-pong.
  ic_count = mod[:next_ic]
  if ic_count > 0
    globals_out << "@.ic = internal thread_local global \["
    globals_out << ic_count.to_s()
    globals_out << " x \[24 x i8]] zeroinitializer, align 8\n\n"

  # Phase 5g (post-Phase-6h): compile-time SmallArray constants. Each
  # entry is a private LLVM constant matching the WSmallArray header
  # layout (ebits, size) followed by inline byte slots. Subtag is
  # W_SUBTAG_SMALL_ARRAY=9, so the load site OR's 9 into the ptrtoint
  # to produce a boxed WValue. align 16 keeps the low nibble clear so
  # the OR can serve as the boxing operation.
  sa_consts = mod[:small_array_consts]
  if sa_consts != nil && sa_consts.size() > 0
    sci = 0
    while sci < sa_consts.size()
      c = sa_consts[sci]
      total = 2 + c[:size]
      globals_out << c[:name]
      globals_out << " = private constant ["
      globals_out << total.to_s()
      globals_out << " x i8] c\""
      append_llvm_hex_byte(globals_out, c[:ebits])     # ebits (e.g. 8)
      append_llvm_hex_byte(globals_out, c[:size])      # element count
      bi = 0
      while bi < c[:bytes].size()
        append_llvm_hex_byte(globals_out, c[:bytes][bi])
        bi += 1
      globals_out << "\", align 16\n"
      sci += 1
    globals_out << "\n"

  # Call-site reuse allocation slots — thread-local, one per site.
  # Each slot caches the per-thread allocation; first call populates it,
  # subsequent calls on the same thread reuse and reset.
  rsites = mod[:reuse_sites]
  if rsites != nil && rsites.size() > 0
    ri = 0
    while ri < rsites.size()
      globals_out << "@"
      globals_out << rsites[ri]
      globals_out << " = internal thread_local global i64 0, align 8\n"
      ri += 1
    globals_out << "\n"

  used_ptr_ids = {}
  attr_groups = {ids: {}, texts: []}
  fn_out = StringBuffer(4096)
  apply_fastcc_plan(mod)

  # Function-level float fast-math flag string from math_mode.
  # :fast   → "fast " (all fast-math: reassoc, nnan, ninf, nsz, arcp, afn, contract)
  # :precise (default) → "" (lowering emits llvm.fmuladd.f64 for a*b+c peephole;
  #            no blanket contract flag — matches C -ffp-contract=on semantics)
  # :strict → "" (bare IEEE 754; no peephole FMA either)
  # Per-instruction :fp_flags in the instruction hash overrides this for
  # @fastmath / @strictmath block scopes.
  fp_flags = ""
  if mod[:math_mode] == :fast
    fp_flags = "fast "

  # Functions
  i = 0
  while i < mod[:functions].size()
    mod[:functions][i][:fp_flags] = fp_flags
    fn_out << emit_function(mod[:functions][i], mod[:string_wvalues], slab_info, used_ptr_ids, frame_pointers, mod[:llvm_fn_attrs], attr_groups)
    fn_out << "\n"
    i += 1

  # String constants that still need raw ptr access; slab emitted as constant array
  strings_out = emit_string_constants(mod[:strings], slab_info, used_ptr_ids)
  if strings_out != ""
    strings_out = strings_out + "\n"

  # w_slab_init_static is emitted directly in emit_function, not via an instruction
  if slab_info != nil && slab_info[:slab_entries].size() > 0
    used_runtime_fns["w_slab_init_static"] = true

  decls_out = filter_runtime_decls(declare_runtime(), used_runtime_fns)
  # Slab-AST runtime globals: always emit as external declarations so
  # the inline-IR :slab_node_get_idx / :slab_node_set_idx ops can
  # reference them without per-emit-site duplication. `[` is escaped
  # because Tungsten string interpolation uses `[expr]`; `]` doesn't
  # need escaping. The linker resolves the symbols against
  # runtime/runtime.c (compiled stages) or
  # implementations/c/src/node_arena.c (C VM stage 0).
  # …but only when this module actually touches the arena (inline slab-alloc
  # fast paths / node field access). Plain programs emit neither the externs
  # nor any init call — the runtime arena is lazy (offset 0 reserved on first
  # growth inside w_node_alloc).
  if fn_out.to_s().index("@g_node_arena") != nil
    decls_out = "@g_node_arena = external global \[4 x { ptr, i32, i32 }]\n@g_node_stride = external constant \[4 x i32]\n\n" + decls_out
  if decls_out != ""
    decls_out = decls_out + "\n"

  # Inline array-read fast paths: inject the private alwaysinline helper
  # definitions (plus their slow-path externs, unless already declared)
  # before the auto-declare loop below — its decls_out dedupe then skips
  # re-declaring the helper names.
  if ccall_needed.has_key?("__w_array_get_i64_fast") || ccall_needed.has_key?("__w_array_idx_i64_fast")
    if decls_out.index("@w_array_get_i64(") == nil
      decls_out = decls_out + "declare i64 @w_array_get_i64(i64, i64) nounwind\n"
    if decls_out.index("@w_array_idx_i64(") == nil
      decls_out = decls_out + "declare i64 @w_array_idx_i64(i64, i64) nounwind\n"
    decls_out = decls_out + array_fast_helpers_ir() + "\n"

  # Inline comparison fast paths — same injection scheme, one helper per
  # comparison actually used by this module.
  cmp_fast_specs = [
    ["__w_eq_fast", "w_eq", "eq", false],
    ["__w_neq_fast", "w_neq", "ne", false],
    ["__w_lt_fast", "w_lt", "slt", true],
    ["__w_gt_fast", "w_gt", "sgt", true],
    ["__w_lte_fast", "w_lte", "sle", true],
    ["__w_gte_fast", "w_gte", "sge", true]
  ]
  cfi = 0
  while cfi < cmp_fast_specs.size()
    cf = cmp_fast_specs[cfi]
    if ccall_needed.has_key?(cf[0])
      if decls_out.index("@" + cf[1] + "(") == nil
        decls_out = decls_out + "declare i64 @" + cf[1] + "(i64, i64) nounwind\n"
      decls_out = decls_out + cmp_fast_helper_ir(cf[0], cf[1], cf[2], cf[3]) + "\n"
    cfi += 1

  # Emit declarations for call targets not defined in this module. The
  # already-declared check was a decls_out.index(search_str) — a full strstr
  # over the growing declaration string PER ccall target, i.e. O(targets x
  # decls length). Scan the declaration/definition lines once into a name set
  # (the declared name is the first @token on a `declare`/`define` line) and
  # test membership in O(1) instead; emit_artifact was a top compile fn and
  # this strstr its hottest leaf.
  declared_names = {}
  decl_lines = decls_out.split("\n")
  dli = 0
  while dli < decl_lines.size()
    dl = decl_lines[dli]
    if dl.starts_with?("declare") || dl.starts_with?("define")
      at = dl.index("@")
      if at != nil
        paren = dl.index("(")
        if paren != nil && paren > at
          declared_names[dl.slice(at + 1, paren - at - 1)] = true
    dli += 1
  ccall_keys = ccall_needed.keys().sort()
  ck = 0
  while ck < ccall_keys.size()
    iname = ccall_keys[ck]
    if !known_fns.has_key?(iname) && !declared_names.has_key?(iname)
      argc = ccall_needed[iname]
      params = []
      pi = 0
      while pi < argc
        params.push("i64")
        pi += 1
      decls_out = decls_out + "declare i64 @" + iname + "(" + params.join(", ") + ") nounwind\n"
      declared_names[iname] = true
    ck += 1
  if decls_out != ""
    decls_out = decls_out + "\n"

  fn_meta_out = ""
  call_site_out = ""
  llvm_used_out = ""
  if mod[:enhanced_stacktraces] != false
    fn_meta_out = emit_fn_meta_table(mod)
    call_site_out = emit_call_site_table(mod)
    llvm_used_out = emit_stacktrace_llvm_used()

  attr_groups_out = emit_function_attr_groups(attr_groups)

  header + decls_out + globals_out.to_s() + strings_out + fn_out.to_s() + fn_meta_out + call_site_out + llvm_used_out + attr_groups_out

# -- Emit a single function --

-> hidden_exit_label_for_inst(inst)
  op = inst[:op]
  if op in (:add_i48_checked :sub_i48_checked :mul_i48_checked)
    return "ovf.merge." + inst[:block_id].to_s()
  if op in (:add_i48_guarded :sub_i48_guarded :mul_i48_guarded)
    return "g.done." + inst[:block_id].to_s()
  # Method-dispatch call sites carrying source-loc info split the block so
  # their return address is addressable via blockaddress(@fn, %cs.N.ret).
  if op == :call_method_i64 && inst[:src_line] != nil
    return "cs." + inst[:ic_id].to_s() + ".ret"
  # Direct-call fallible sites (w_raise, w_array_get, w_array_set) use the
  # loc_site_id namespace since they don't have an ic_id.
  if op in (:call_direct_void :call_direct_i64) && inst[:src_line] != nil && inst[:loc_site_id] != nil
    return "csd." + inst[:loc_site_id].to_s() + ".ret"
  nil

-> build_phi_label_redirects(f)
  redirect = {}
  bi = 0
  while bi < f[:blocks].size()
    blk = f[:blocks][bi]
    exit_label = blk[:label]
    ii = 0
    while ii < blk[:instructions].size()
      hidden = hidden_exit_label_for_inst(blk[:instructions][ii])
      if hidden != nil
        exit_label = hidden
      ii += 1
    if exit_label != blk[:label]
      redirect[blk[:label]] = exit_label
    bi += 1
  redirect

-> redirect_phi_label(label, redirect)
  if redirect == nil
    return label
  current = label
  seen = {}
  while current != nil && redirect[current] != nil && seen[current] != true
    seen[current] = true
    current = redirect[current]
  if current == nil
    return label
  current

-> emit_function(f, string_wvs, slab_info, used_ptr_ids, frame_pointers = false, host_fn_attrs = "", attr_groups = nil)
  out = StringBuffer(4096)
  ret_ty = f[:return_type]
  attr_text = function_attr_text(frame_pointers, host_fn_attrs)
  attr_id = nil
  if attr_groups != nil
    attr_id = function_attr_group_id(attr_groups, attr_text)
  out << "define "
  if f[:llvm_internal] == true
    out << "internal "
  if f[:call_conv] != nil && f[:call_conv] != ""
    out << f[:call_conv]
    out << " "
  out << ret_ty
  out << " @"
  out << f[:name]
  out << "("
  out << emit_param_signature(f)
  out << ")"
  if attr_id != nil
    out << " #"
    out << attr_id.to_s()
  else
    out << " "
    out << attr_text
  out << " {\n"

  # Entry block: allocas for all var slots, then instructions
  lbr = "\["
  rbr = "]"
  # Pre-scan for max method call arg count (needed for scratch alloca)
  max_mcall_argc = 0
  bi = 0
  while bi < f[:blocks].size()
    blk = f[:blocks][bi]
    ji = 0
    while ji < blk[:instructions].size()
      inst = blk[:instructions][ji]
      if inst[:op] == :call_method_i64 && inst[:args] != nil
        argc = inst[:args].size()
        needs_scratch = argc > 0 && !scalar_source_one_call?(inst)
        if needs_scratch && argc > max_mcall_argc
          max_mcall_argc = argc
      ji += 1
    bi += 1

  fp_flags = f[:fp_flags]
  if fp_flags == nil
    fp_flags = ""

  # Emit all blocks — always emit entry block label so SSA phi nodes can reference it
  slots = f[:var_slots]
  slot_types = f[:var_slot_types]
  promoted = f[:promoted_vars]
  phi_label_redirects = build_phi_label_redirects(f)
  i = 0
  while i < f[:blocks].size()
    blk = f[:blocks][i]
    out << blk[:label]
    out << ":\n"
    # Entry block: emit allocas for non-promoted var slots
    if i == 0
      if slots != nil
        slot_names = slots.keys().sort()
        j = 0
        while j < slot_names.size()
          ptr = slots[slot_names[j]]
          if ptr.starts_with?("%v") && (promoted == nil || promoted[ptr] == nil)
            slot_type = "i64"
            if slot_types != nil && slot_types[slot_names[j]] != nil
              slot_type = slot_types[slot_names[j]]
            out << "  "
            out << ptr
            out << " = alloca "
            out << slot_type
            if slot_type == "i128"
              out << ", align 16\n"
            else
              out << ", align 8\n"
          j += 1
      if max_mcall_argc > 0
        out << "  %__mcall_args = alloca i64, i32 "
        out << max_mcall_argc.to_s()
        out << ", align 8\n"
      # Inject static slab init at start of main, before any string ops
      if f[:name] == "main" && slab_info != nil && slab_info[:slab_entries].size() > 0
        out << "  call void @w_slab_init_static(ptr @__static_slab, i32 "
        out << slab_info[:total_slots].to_s()
        out << ")\n"
      # (The AST-node arena init call is gone: the arena is lazy — offset 0
      # is reserved on first growth inside w_node_alloc, so a NULL base just
      # routes the first inline alloc through the slow path.)
    # Emit instructions in block
    j = 0
    while j < blk[:instructions].size()
      out << "  "
      out << render_instruction(blk[:instructions][j], string_wvs, used_ptr_ids, phi_label_redirects, fp_flags)
      out << "\n"
      j += 1
    i += 1

  out << "}\n"
  out.to_s()

-> emit_param_signature(f)
  parts = []
  # Extra params first (e.g. ptr %__captures for block functions)
  if f[:extra_params] != nil
    i = 0
    while i < f[:extra_params].size()
      ep = f[:extra_params][i]
      parts.push(ep[:type] + " " + ep[:name])
      i += 1
  i = 0
  while i < f[:params].size()
    parts.push("i64 %" + f[:params][i])
    i += 1
  parts.join(", ")

# -- Instruction rendering --

-> render_guarded_i48(inst)
  bid = inst[:block_id].to_s()
  t = inst[:temp]
  ltag = t + ".ltag"
  lis_int = t + ".lisint"
  rtag = t + ".rtag"
  ris_int = t + ".risint"
  both_int = t + ".bothint"
  lhs_shl = t + ".lhs.shl"
  lhs_raw = t + ".lhs.raw"
  rhs_shl = t + ".rhs.shl"
  rhs_raw = t + ".rhs.raw"
  raw = t + ".raw"
  over = t + ".over"
  under = t + ".under"
  ovf = t + ".ovf"
  masked = t + ".masked"
  boxed = t + ".fast"
  slow = t + ".slow"
  out = StringBuffer(768)
  out << ltag + " = and i64 " + inst[:lhs] + ", " + w_tag_mask.to_s() + "\n  "
  out << lis_int + " = icmp eq i64 " + ltag + ", " + w_tag_int.to_s() + "\n  "
  out << rtag + " = and i64 " + inst[:rhs] + ", " + w_tag_mask.to_s() + "\n  "
  out << ris_int + " = icmp eq i64 " + rtag + ", " + w_tag_int.to_s() + "\n  "
  out << both_int + " = and i1 " + lis_int + ", " + ris_int + "\n  "
  out << "br i1 " + both_int + ", label %g.ok." + bid + ", label %g.rt." + bid + "\n"
  out << "g.ok." + bid + ":\n  "
  out << lhs_shl + " = shl i64 " + inst[:lhs] + ", 16\n  "
  out << lhs_raw + " = ashr i64 " + lhs_shl + ", 16\n  "
  out << rhs_shl + " = shl i64 " + inst[:rhs] + ", 16\n  "
  out << rhs_raw + " = ashr i64 " + rhs_shl + ", 16\n  "

  op = inst[:op]
  if op in (:add_i48_guarded :sub_i48_guarded)
    arith_op = "add"
    if op == :sub_i48_guarded
      arith_op = "sub"
    out << raw + " = " + arith_op + " i64 " + lhs_raw + ", " + rhs_raw + "\n  "
    out << over + " = icmp sgt i64 " + raw + ", 140737488355327\n  "
    out << under + " = icmp slt i64 " + raw + ", -140737488355328\n  "
    out << ovf + " = or i1 " + over + ", " + under + "\n  "
  else
    pair = t + ".pair"
    i64ovf = t + ".i64ovf"
    rovf = t + ".rovf"
    out << pair + " = call {i64, i1} @llvm.smul.with.overflow.i64(i64 " + lhs_raw + ", i64 " + rhs_raw + ")\n  "
    out << raw + " = extractvalue {i64, i1} " + pair + ", 0\n  "
    out << i64ovf + " = extractvalue {i64, i1} " + pair + ", 1\n  "
    out << over + " = icmp sgt i64 " + raw + ", 140737488355327\n  "
    out << under + " = icmp slt i64 " + raw + ", -140737488355328\n  "
    out << rovf + " = or i1 " + over + ", " + under + "\n  "
    out << ovf + " = or i1 " + i64ovf + ", " + rovf + "\n  "

  out << "br i1 " + ovf + ", label %g.rt." + bid + ", label %g.box." + bid + "\n"
  out << "g.box." + bid + ":\n  "
  out << masked + " = and i64 " + raw + ", " + w_payload_mask.to_s() + "\n  "
  out << boxed + " = or i64 " + masked + ", " + w_tag_int.to_s() + "\n  "
  out << "br label %g.done." + bid + "\n"
  out << "g.rt." + bid + ":\n  "
  # `Math.trap` mode: the slow (overflow / non-int-operand) path aborts via
  # the LLVM trap intrinsic instead of calling the BigInt-promoting runtime.
  # g.rt terminates with `unreachable`, so g.done has the single g.box
  # predecessor and its phi has one incoming value.
  if inst[:trap] == true
    out << "call void @llvm.trap()\n  "
    out << "unreachable\n"
    out << "g.done." + bid + ":\n  "
    out << t + " = phi i64 \[" + boxed + ", %g.box." + bid + "]"
  else
    out << slow + " = call i64 @" + inst[:rt_fallback] + "(i64 " + inst[:lhs] + ", i64 " + inst[:rhs] + ")\n  "
    out << "br label %g.done." + bid + "\n"
    out << "g.done." + bid + ":\n  "
    out << t + " = phi i64 \[" + boxed + ", %g.box." + bid + "], \[" + slow + ", %g.rt." + bid + "]"
  out.to_s()

-> render_instruction(inst, string_wvs, used_ptr_ids, phi_label_redirects = nil, fp_flags = "")
  op = inst[:op]

  case op
  # Memory
  when :alloca_i64
    inst[:ptr] + " = alloca i64, align 8"
  when :alloca_i128
    inst[:ptr] + " = alloca i128, align 16"
  when :store_i64
    "store i64 " + inst[:value] + ", ptr " + inst[:ptr] + ", align 8"
  when :store_i128
    "store i128 " + inst[:value] + ", ptr " + inst[:ptr] + ", align 16"
  when :store_float
    "store float " + inst[:value] + ", ptr " + inst[:ptr] + ", align 4"
  when :store_double
    "store double " + inst[:value] + ", ptr " + inst[:ptr] + ", align 8"
  when :load_i64
    inst[:temp] + " = load i64, ptr " + inst[:ptr] + ", align 8" + range_metadata_suffix(inst, "i64")
  when :load_float
    inst[:temp] + " = load float, ptr " + inst[:ptr] + ", align 4"
  when :load_double
    inst[:temp] + " = load double, ptr " + inst[:ptr] + ", align 8"
  when :load_u8_ptr
    p = inst[:temp] + ".p"
    ep = inst[:temp] + ".ep"
    b = inst[:temp] + ".b"
    p + " = inttoptr i64 " + inst[:ptr] + " to ptr\n  " + ep + " = getelementptr i8, ptr " + p + ", i64 " + inst[:index] + "\n  " + b + " = load i8, ptr " + ep + ", align 1" + range_metadata_suffix(inst, "i8") + "\n  " + inst[:temp] + " = zext i8 " + b + " to i64"
  when :store_u8_ptr
    p = inst[:temp] + ".p"
    ep = inst[:temp] + ".ep"
    b = inst[:temp] + ".b"
    p + " = inttoptr i64 " + inst[:ptr] + " to ptr\n  " + ep + " = getelementptr i8, ptr " + p + ", i64 " + inst[:index] + "\n  " + b + " = trunc i64 " + inst[:value] + " to i8\n  store i8 " + b + ", ptr " + ep + ", align 1\n  " + inst[:temp] + " = zext i8 " + b + " to i64"
  when :load_u32_ptr
    p = inst[:temp] + ".p"
    ep = inst[:temp] + ".ep"
    w = inst[:temp] + ".w"
    p + " = inttoptr i64 " + inst[:ptr] + " to ptr\n  " + ep + " = getelementptr i8, ptr " + p + ", i64 " + inst[:index] + "\n  " + w + " = load i32, ptr " + ep + ", align 1" + range_metadata_suffix(inst, "i32") + "\n  " + inst[:temp] + " = zext i32 " + w + " to i64"
  when :load_u64_ptr
    p = inst[:temp] + ".p"
    ep = inst[:temp] + ".ep"
    p + " = inttoptr i64 " + inst[:ptr] + " to ptr\n  " + ep + " = getelementptr i8, ptr " + p + ", i64 " + inst[:index] + "\n  " + inst[:temp] + " = load i64, ptr " + ep + ", align 1" + range_metadata_suffix(inst, "i64")
  when :ptr_slot_get
    p = inst[:temp] + ".p"
    ep = inst[:temp] + ".ep"
    slot_type = inst[:slot_type]
    if slot_type == "w64" || slot_type == "i64" || slot_type == "u64"
      p + " = inttoptr i64 " + inst[:ptr] + " to ptr\n  " + ep + " = getelementptr i64, ptr " + p + ", i64 " + inst[:index] + "\n  " + inst[:temp] + " = load i64, ptr " + ep + ", align 8"
    elsif slot_type == "u8" || slot_type == "i8"
      b = inst[:temp] + ".b"
      p + " = inttoptr i64 " + inst[:ptr] + " to ptr\n  " + ep + " = getelementptr i8, ptr " + p + ", i64 " + inst[:index] + "\n  " + b + " = load i8, ptr " + ep + ", align 1\n  " + inst[:temp] + " = zext i8 " + b + " to i64"
    else
      p + " = inttoptr i64 " + inst[:ptr] + " to ptr\n  " + ep + " = getelementptr i64, ptr " + p + ", i64 " + inst[:index] + "\n  " + inst[:temp] + " = load i64, ptr " + ep + ", align 8"
  when :load_i128
    inst[:temp] + " = load i128, ptr " + inst[:ptr] + ", align 16" + range_metadata_suffix(inst, "i128")

  # Integer arithmetic
  when :add_i64
    inst[:temp] + " = add i64 " + inst[:lhs] + ", " + inst[:rhs]
  when :sub_i64
    inst[:temp] + " = sub i64 " + inst[:lhs] + ", " + inst[:rhs]
  when :mul_i64
    inst[:temp] + " = mul i64 " + inst[:lhs] + ", " + inst[:rhs]
  when :sdiv_i64
    inst[:temp] + " = sdiv i64 " + inst[:lhs] + ", " + inst[:rhs]
  when :udiv_i64
    inst[:temp] + " = udiv i64 " + inst[:lhs] + ", " + inst[:rhs]
  when :srem_i64
    inst[:temp] + " = srem i64 " + inst[:lhs] + ", " + inst[:rhs]
  when :urem_i64
    inst[:temp] + " = urem i64 " + inst[:lhs] + ", " + inst[:rhs]
  when :add_i128
    inst[:temp] + " = add i128 " + inst[:lhs] + ", " + inst[:rhs]
  when :sub_i128
    inst[:temp] + " = sub i128 " + inst[:lhs] + ", " + inst[:rhs]
  when :mul_i128
    inst[:temp] + " = mul i128 " + inst[:lhs] + ", " + inst[:rhs]
  when :mulhi_u64
    # high 64 bits of the unsigned 64x64->128 product. LLVM lowers this to a
    # single UMULH on arm64 / MULX on x86 — the carry-primitive `mulhi`.
    t = inst[:temp]
    o = StringBuffer(192)
    o << t + ".az = zext i64 " + inst[:lhs] + " to i128\n  "
    o << t + ".bz = zext i64 " + inst[:rhs] + " to i128\n  "
    o << t + ".pp = mul i128 " + t + ".az, " + t + ".bz\n  "
    o << t + ".hs = lshr i128 " + t + ".pp, 64\n  "
    o << t + " = trunc i128 " + t + ".hs to i64"
    o.to_s()
  when :addcarry_u64
    # carry-out (0/1) of a + b via i128 widening: ((zext a + zext b) >> 64).
    # LLVM keeps the carry in the flag and chains these as ADDS/ADCS instead of
    # materialising it with CMP/CSET. Carry-primitive `addcarry`.
    t = inst[:temp]
    o = StringBuffer(192)
    o << t + ".az = zext i64 " + inst[:lhs] + " to i128\n  "
    o << t + ".bz = zext i64 " + inst[:rhs] + " to i128\n  "
    o << t + ".sm = add i128 " + t + ".az, " + t + ".bz\n  "
    o << t + ".hs = lshr i128 " + t + ".sm, 64\n  "
    o << t + " = trunc i128 " + t + ".hs to i64"
    o.to_s()
  when :subborrow_u64
    # borrow-out (0/1) of a - b via i128: ((zext a - zext b) >> 127). When a<b the
    # i128 difference is negative (sign bit set) -> 1, else 0. LLVM chains these as
    # SUBS/SBCS. Carry-primitive `subborrow`.
    t = inst[:temp]
    o = StringBuffer(192)
    o << t + ".az = zext i64 " + inst[:lhs] + " to i128\n  "
    o << t + ".bz = zext i64 " + inst[:rhs] + " to i128\n  "
    o << t + ".df = sub i128 " + t + ".az, " + t + ".bz\n  "
    o << t + ".hs = lshr i128 " + t + ".df, 127\n  "
    o << t + " = trunc i128 " + t + ".hs to i64"
    o.to_s()
  when :asm_add_test
    # POC: prove LLVM inline asm emits/links/runs. a+b via an aarch64 ADD.
    inst[:temp] + " = call i64 asm sideeffect \"add ${0:x}, ${1:x}, ${2:x}\", \"=r,r,r\"(i64 " + inst[:lhs] + ", i64 " + inst[:rhs] + ")"
  when :arr_data_ptr
    # raw data-base pointer (as i64) of a u64[]: header tag-mask, +16, load ptr.
    t = inst[:temp]
    t + ".ar = and i64 " + inst[:arr] + ", -16\n  " + t + ".bp = inttoptr i64 " + t + ".ar to ptr\n  " + t + ".gp = getelementptr i8, ptr " + t + ".bp, i64 16\n  " + t + ".pp = load ptr, ptr " + t + ".gp\n  " + t + " = ptrtoint ptr " + t + ".pp to i64"
  when :asm_add_n
    # GMP-shape flag-threaded adc loop: out[i]=a[i]+b[i] over n limbs, carry kept
    # in the flag across iterations (sub/cbnz don't clobber C). Returns final carry.
    t = inst[:temp]
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Acmn xzr, xzr\\0A1:\\0Aldr x10, \[x13], #8\\0Aldr x11, \[x14], #8\\0Aadcs x12, x10, x11\\0Astr x12, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Acset ${0:x}, cs"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}\"(i64 " + inst[:ap] + ", i64 " + inst[:bp] + ", i64 " + inst[:outp] + ", i64 " + inst[:n] + ")"
  when :asm_neon_umull
    # POC: NEON 2-lane umull loop. out[2i,2i+1] = a[i].lanes * b[i].lanes (u32->u64).
    # All via memory + GPR pointer operands; NEON work internal (v-reg clobbers).
    t = inst[:temp]
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0A1:\\0Ald1 {v1.2s}, \[x13], #8\\0Ald1 {v2.2s}, \[x14], #8\\0Aumull v0.2d, v1.2s, v2.2s\\0Ast1 {v0.2d}, \[x15], #16\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{memory},~{cc}\"(i64 " + inst[:ap] + ", i64 " + inst[:bp] + ", i64 " + inst[:outp] + ", i64 " + inst[:n] + ")"
  when :asm_neon_redc
    # NEON 2-lane Montgomery REDC: out[i] = REDC(a[i]*b[i]) mod p=998244353, R=2^32.
    # ninv=998244351. t=a*b; m=(t mod R)*ninv mod R; t=(t+m*p)>>32; if t>=p t-=p.
    t = inst[:temp]
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Amov w10, #1\\0Amovk w10, #15232, lsl #16\\0Adup v5.2s, w10\\0Auxtl v7.2d, v5.2s\\0Amov w11, #65535\\0Amovk w11, #15231, lsl #16\\0Adup v6.2s, w11\\0A1:\\0Ald1 {v1.2s}, \[x13], #8\\0Ald1 {v2.2s}, \[x14], #8\\0Aumull v0.2d, v1.2s, v2.2s\\0Axtn v3.2s, v0.2d\\0Amul v3.2s, v3.2s, v6.2s\\0Aumull v4.2d, v3.2s, v5.2s\\0Aadd v0.2d, v0.2d, v4.2d\\0Aushr v0.2d, v0.2d, #32\\0Asub v8.2d, v0.2d, v7.2d\\0Acmhs v16.2d, v0.2d, v7.2d\\0Abit v0.16b, v8.16b, v16.16b\\0Axtn v0.2s, v0.2d\\0Ast1 {v0.2s}, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x11},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{v16},~{memory},~{cc}\"(i64 " + inst[:ap] + ", i64 " + inst[:bp] + ", i64 " + inst[:outp] + ", i64 " + inst[:n] + ")"
  when :asm_neon_redc4
    # NEON 4-lane Montgomery REDC: out lanes = REDC(a*b) mod p=998244353, R=2^32.
    # Processes 4 u32 lanes (= 2 u64 elements) per iter via umull+umull2. n = #pairs.
    # ninv=998244351. t=a*b; m=(t&mask)*ninv&mask; t=(t+m*p)>>32; if t>=p t-=p.
    t = inst[:temp]
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Amov w10, #1\\0Amovk w10, #15232, lsl #16\\0Adup v5.4s, w10\\0Auxtl v7.2d, v5.2s\\0Amov w11, #65535\\0Amovk w11, #15231, lsl #16\\0Adup v6.4s, w11\\0A1:\\0Ald1 {v1.4s}, \[x13], #16\\0Ald1 {v2.4s}, \[x14], #16\\0Aumull v0.2d, v1.2s, v2.2s\\0Aumull2 v17.2d, v1.4s, v2.4s\\0Axtn v3.2s, v0.2d\\0Amul v3.2s, v3.2s, v6.2s\\0Aumull v4.2d, v3.2s, v5.2s\\0Aadd v0.2d, v0.2d, v4.2d\\0Aushr v0.2d, v0.2d, #32\\0Asub v8.2d, v0.2d, v7.2d\\0Acmhs v16.2d, v0.2d, v7.2d\\0Abit v0.16b, v8.16b, v16.16b\\0Axtn v18.2s, v17.2d\\0Amul v18.2s, v18.2s, v6.2s\\0Aumull v19.2d, v18.2s, v5.2s\\0Aadd v17.2d, v17.2d, v19.2d\\0Aushr v17.2d, v17.2d, #32\\0Asub v20.2d, v17.2d, v7.2d\\0Acmhs v21.2d, v17.2d, v7.2d\\0Abit v17.16b, v20.16b, v21.16b\\0Axtn v0.2s, v0.2d\\0Axtn2 v0.4s, v17.2d\\0Ast1 {v0.4s}, \[x15], #16\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x11},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{v16},~{v17},~{v18},~{v19},~{v20},~{v21},~{memory},~{cc}\"(i64 " + inst[:ap] + ", i64 " + inst[:bp] + ", i64 " + inst[:outp] + ", i64 " + inst[:n] + ")"
  when :asm_neon_madd4
    # NEON 4-lane modular add mod p=998244353: out=a+b; if out>=p out-=p. 4 u32/iter.
    # inputs < p, sum < 2p < 2^31 so 32-bit lane add cannot overflow. n = #pairs.
    t = inst[:temp]
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Amov w10, #1\\0Amovk w10, #15232, lsl #16\\0Ains v5.s\[0], w10\\0Ains v5.s\[1], w10\\0Ains v5.s\[2], w10\\0Ains v5.s\[3], w10\\0A1:\\0Ald1 {v1.4s}, \[x13], #16\\0Ald1 {v2.4s}, \[x14], #16\\0Aadd v0.4s, v1.4s, v2.4s\\0Acmhs v4.4s, v0.4s, v5.4s\\0Aand v6.16b, v4.16b, v5.16b\\0Asub v0.4s, v0.4s, v6.4s\\0Ast1 {v0.4s}, \[x15], #16\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{v4},~{v5},~{v6},~{memory},~{cc}\"(i64 " + inst[:ap] + ", i64 " + inst[:bp] + ", i64 " + inst[:outp] + ", i64 " + inst[:n] + ")"
  when :asm_neon_msub4
    # NEON 4-lane modular sub mod p=998244353: r=a-b; if a<b r+=p. 4 u32/iter.
    # use: d=a-b (u32 wrap); if a<b (cmhi b>a) add p. n = #pairs.
    t = inst[:temp]
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Amov w10, #1\\0Amovk w10, #15232, lsl #16\\0Adup v5.4s, w10\\0A1:\\0Ald1 {v1.4s}, \[x13], #16\\0Ald1 {v2.4s}, \[x14], #16\\0Asub v0.4s, v1.4s, v2.4s\\0Acmhi v4.4s, v2.4s, v1.4s\\0Aand v6.16b, v4.16b, v5.16b\\0Aadd v0.4s, v0.4s, v6.4s\\0Ast1 {v0.4s}, \[x15], #16\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{v4},~{v5},~{v6},~{memory},~{cc}\"(i64 " + inst[:ap] + ", i64 " + inst[:bp] + ", i64 " + inst[:outp] + ", i64 " + inst[:n] + ")"
  when :asm_neon_ntt_stage
    # Whole-butterfly NEON DIT NTT stage, mod p=998244353, Montgomery, R=2^32.
    # v = coeffs as 4xu32/16B; stw = per-stage twiddles (u32, len=half). For each of
    # nblocks blocks: a=block base, b=a+half; for halfq groups of 4: t=REDC(b,w);
    # store a+t at a, a-t at b. ALL in vector regs (load->modmul->add/sub->store).
    # operands: ${1}=v ${2}=stw ${3}=nblocks ${4}=halfq.  half_bytes=halfq*16.
    t = inst[:temp]
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x9, ${3:x}\\0Amov x10, ${4:x}\\0Alsl x11, x10, #4\\0Amov w12, #1\\0Amovk w12, #15232, lsl #16\\0Adup v5.4s, w12\\0Auxtl v7.2d, v5.2s\\0Amov w12, #65535\\0Amovk w12, #15231, lsl #16\\0Adup v6.4s, w12\\0A2:\\0Amov x15, x13\\0Aadd x16, x13, x11\\0Amov x17, x14\\0Amov x8, x10\\0A3:\\0Ald1 {v1.4s}, \[x15]\\0Ald1 {v2.4s}, \[x16]\\0Ald1 {v9.4s}, \[x17], #16\\0Aumull v0.2d, v2.2s, v9.2s\\0Aumull2 v10.2d, v2.4s, v9.4s\\0Axtn v3.2s, v0.2d\\0Amul v3.2s, v3.2s, v6.2s\\0Aumull v4.2d, v3.2s, v5.2s\\0Aadd v0.2d, v0.2d, v4.2d\\0Aushr v0.2d, v0.2d, #32\\0Asub v8.2d, v0.2d, v7.2d\\0Acmhs v11.2d, v0.2d, v7.2d\\0Abit v0.16b, v8.16b, v11.16b\\0Axtn v12.2s, v10.2d\\0Amul v12.2s, v12.2s, v6.2s\\0Aumull v13.2d, v12.2s, v5.2s\\0Aadd v10.2d, v10.2d, v13.2d\\0Aushr v10.2d, v10.2d, #32\\0Asub v14.2d, v10.2d, v7.2d\\0Acmhs v15.2d, v10.2d, v7.2d\\0Abit v10.16b, v14.16b, v15.16b\\0Axtn v0.2s, v0.2d\\0Axtn2 v0.4s, v10.2d\\0Aadd v16.4s, v1.4s, v0.4s\\0Acmhs v17.4s, v16.4s, v5.4s\\0Aand v18.16b, v17.16b, v5.16b\\0Asub v16.4s, v16.4s, v18.4s\\0Asub v19.4s, v1.4s, v0.4s\\0Acmhi v20.4s, v0.4s, v1.4s\\0Aand v21.16b, v20.16b, v5.16b\\0Aadd v19.4s, v19.4s, v21.4s\\0Ast1 {v16.4s}, \[x15], #16\\0Ast1 {v19.4s}, \[x16], #16\\0Asub x8, x8, #1\\0Acbnz x8, 3b\\0Aadd x13, x13, x11, lsl #1\\0Asub x9, x9, #1\\0Acbnz x9, 2b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{v9},~{v10},~{v11},~{v12},~{v13},~{v14},~{v15},~{v16},~{v17},~{v18},~{v19},~{v20},~{v21},~{memory},~{cc}\"(i64 " + inst[:vp] + ", i64 " + inst[:twp] + ", i64 " + inst[:nb] + ", i64 " + inst[:hq] + ")"
  when :asm_gold_stage
    # Scalar Goldilocks radix-4 DIF NTT stage. P=2^64-2^32+1, ep=2^32-1.
    # ${1}=v ${2}=stw ${3}=nblocks ${4}=q.  block = 4*q coeffs = q*32 bytes.
    # Reduced register footprint (indexed loads, 3 scratch). Regs:
    #  x1=block base, x2=stw ptr, x3=stw base, x4=block ctr, x5=q (group reload),
    #  x6=qbytes(q*8), x7=group ctr, x8=i0 ptr, x9=2*qbytes, x10=3*qbytes,
    #  x12=ep, x13=pp(=P); coeffs/y in x14..x17; t0=x19 t1=x20 t2=x21 d=x22
    #  t3=x23; scratch x24,x25,x26 (x26 also holds w/prod in mul phase).
    # i1..i3 via indexed addressing [x8,x6]/[x8,x9]/[x8,x10].
    t = inst[:temp]
    asmt = "mov x1, ${1:x}\\0Amov x3, ${2:x}\\0Amov x4, ${3:x}\\0Amov x5, ${4:x}\\0Alsl x6, x5, #3\\0Alsl x9, x5, #4\\0Aadd x10, x9, x6\\0Amovz x12, #65535\\0Amovk x12, #65535, lsl #16\\0Amovz x13, #1\\0Amovk x13, #65535, lsl #32\\0Amovk x13, #65535, lsl #48\\0A2:\\0Amov x8, x1\\0Amov x2, x3\\0Amov x7, x5\\0A3:\\0Aldr x14, \[x8]\\0Aldr x15, \[x8, x6]\\0Aldr x16, \[x8, x9]\\0Aldr x17, \[x8, x10]\\0Aadds x19, x14, x16\\0Acsel x24, x12, xzr, cs\\0Aadd x19, x19, x24\\0Asubs x24, x19, x13\\0Acsel x19, x24, x19, hs\\0Asubs x20, x14, x16\\0Acsel x24, x13, xzr, cc\\0Aadd x20, x20, x24\\0Aadds x21, x15, x17\\0Acsel x24, x12, xzr, cs\\0Aadd x21, x21, x24\\0Asubs x24, x21, x13\\0Acsel x21, x24, x21, hs\\0Asubs x22, x15, x17\\0Acsel x24, x13, xzr, cc\\0Aadd x22, x22, x24\\0Alsl x24, x22, #48\\0Aubfx x25, x22, #16, #48\\0Alsr x26, x25, #32\\0Aand x25, x25, x12\\0Asubs x23, x24, x26\\0Acsel x24, x12, xzr, cc\\0Asub x23, x23, x24\\0Alsl x24, x25, #32\\0Asub x24, x24, x25\\0Aadds x23, x23, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x23, x23, x24\\0Asubs x24, x23, x13\\0Acsel x23, x24, x23, hs\\0Aadds x14, x19, x21\\0Acsel x24, x12, xzr, cs\\0Aadd x14, x14, x24\\0Asubs x24, x14, x13\\0Acsel x14, x24, x14, hs\\0Aadds x15, x20, x23\\0Acsel x24, x12, xzr, cs\\0Aadd x15, x15, x24\\0Asubs x24, x15, x13\\0Acsel x15, x24, x15, hs\\0Asubs x16, x19, x21\\0Acsel x24, x13, xzr, cc\\0Aadd x16, x16, x24\\0Asubs x17, x20, x23\\0Acsel x24, x13, xzr, cc\\0Aadd x17, x17, x24\\0Astr x14, \[x8]\\0Aldr x26, \[x2]\\0Amul x25, x15, x26\\0Aumulh x26, x15, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x25, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x25, x25, x24\\0Asubs x24, x25, x13\\0Acsel x25, x24, x25, hs\\0Astr x25, \[x8, x6]\\0Aldr x26, \[x2, #8]\\0Amul x25, x16, x26\\0Aumulh x26, x16, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x25, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x25, x25, x24\\0Asubs x24, x25, x13\\0Acsel x25, x24, x25, hs\\0Astr x25, \[x8, x9]\\0Aldr x26, \[x2, #16]\\0Amul x25, x17, x26\\0Aumulh x26, x17, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x25, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x25, x25, x24\\0Asubs x24, x25, x13\\0Acsel x25, x24, x25, hs\\0Astr x25, \[x8, x10]\\0Aadd x8, x8, #8\\0Aadd x2, x2, #24\\0Asubs x7, x7, #1\\0Acbnz x7, 3b\\0Aadd x1, x1, x6, lsl #2\\0Asubs x4, x4, #1\\0Acbnz x4, 2b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x1},~{x2},~{x3},~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{x19},~{x20},~{x21},~{x22},~{x23},~{x24},~{x25},~{x26},~{memory},~{cc}\"(i64 " + inst[:vp] + ", i64 " + inst[:twp] + ", i64 " + inst[:nb] + ", i64 " + inst[:hq] + ")"
  when :asm_gold_stage_inv
    # Scalar Goldilocks radix-4 DIT (inverse) NTT stage. P=2^64-2^32+1, ep=2^32-1.
    # ${1}=v ${2}=stw ${3}=iv ${4}=nblocks ${5}=q.  block = 4*q coeffs.
    #  x1=block base, x2=stw ptr, x3=stw base, x4=block ctr, x5=q, x6=qbytes,
    #  x7=group ctr, x8=i0 ptr, x9=2*qbytes, x10=3*qbytes, x11=iinv,
    #  x12=ep, x13=pp; coeffs a0..a3 in x14..x17; t0=x19 t1=x20 t2=x21 d=x22
    #  t3=x23; scratch x24,x25,x26.  Twiddle FIRST (in place), then combine.
    t = inst[:temp]
    asmt = "mov x1, ${1:x}\\0Amov x3, ${2:x}\\0Aldr x11, \[${3:x}]\\0Amov x4, ${4:x}\\0Alsl x6, ${5:x}, #3\\0Alsl x9, x6, #1\\0Aadd x10, x9, x6\\0Amovz x12, #65535\\0Amovk x12, #65535, lsl #16\\0Amovz x13, #1\\0Amovk x13, #65535, lsl #32\\0Amovk x13, #65535, lsl #48\\0A2:\\0Amov x8, x1\\0Amov x2, x3\\0Alsr x7, x6, #3\\0A3:\\0Aldr x14, \[x8]\\0Aldr x15, \[x8, x6]\\0Aldr x16, \[x8, x9]\\0Aldr x17, \[x8, x10]\\0Aldr x26, \[x2]\\0Amul x25, x15, x26\\0Aumulh x26, x15, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x15, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x15, x15, x24\\0Asubs x24, x15, x13\\0Acsel x15, x24, x15, hs\\0Aldr x26, \[x2, #8]\\0Amul x25, x16, x26\\0Aumulh x26, x16, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x16, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x16, x16, x24\\0Asubs x24, x16, x13\\0Acsel x16, x24, x16, hs\\0Aldr x26, \[x2, #16]\\0Amul x25, x17, x26\\0Aumulh x26, x17, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x17, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x17, x17, x24\\0Asubs x24, x17, x13\\0Acsel x17, x24, x17, hs\\0Aadds x19, x14, x16\\0Acsel x24, x12, xzr, cs\\0Aadd x19, x19, x24\\0Asubs x24, x19, x13\\0Acsel x19, x24, x19, hs\\0Asubs x20, x14, x16\\0Acsel x24, x13, xzr, cc\\0Aadd x20, x20, x24\\0Aadds x21, x15, x17\\0Acsel x24, x12, xzr, cs\\0Aadd x21, x21, x24\\0Asubs x24, x21, x13\\0Acsel x21, x24, x21, hs\\0Asubs x22, x15, x17\\0Acsel x24, x13, xzr, cc\\0Aadd x22, x22, x24\\0Amul x25, x22, x11\\0Aumulh x26, x22, x11\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x23, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x23, x23, x24\\0Asubs x24, x23, x13\\0Acsel x23, x24, x23, hs\\0Aadds x14, x19, x21\\0Acsel x24, x12, xzr, cs\\0Aadd x14, x14, x24\\0Asubs x24, x14, x13\\0Acsel x14, x24, x14, hs\\0Astr x14, \[x8]\\0Aadds x15, x20, x23\\0Acsel x24, x12, xzr, cs\\0Aadd x15, x15, x24\\0Asubs x24, x15, x13\\0Acsel x15, x24, x15, hs\\0Astr x15, \[x8, x6]\\0Asubs x16, x19, x21\\0Acsel x24, x13, xzr, cc\\0Aadd x16, x16, x24\\0Astr x16, \[x8, x9]\\0Asubs x17, x20, x23\\0Acsel x24, x13, xzr, cc\\0Aadd x17, x17, x24\\0Astr x17, \[x8, x10]\\0Aadd x8, x8, #8\\0Aadd x2, x2, #24\\0Asubs x7, x7, #1\\0Acbnz x7, 3b\\0Aadd x1, x1, x6, lsl #2\\0Asubs x4, x4, #1\\0Acbnz x4, 2b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,~{x1},~{x2},~{x3},~{x4},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{x19},~{x20},~{x21},~{x22},~{x23},~{x24},~{x25},~{x26},~{memory},~{cc}\"(i64 " + inst[:vp] + ", i64 " + inst[:twp] + ", i64 " + inst[:ivp] + ", i64 " + inst[:nb] + ", i64 " + inst[:hq] + ")"
  when :asm_neon_gadd2
    # NEON 2-lane Goldilocks add: out[i] lanes = gadd(a,b) mod P=2^64-2^32+1.
    # r=a+b; if r<a (overflow) r+=ep(0xFFFFFFFF); if r>=pp(2^64-ep) r-=pp. 2 u64/op.
    t = inst[:temp]
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Amovz w10, #65535\\0Amovk w10, #65535, lsl #16\\0Adup v7.2d, x10\\0Amovz x11, #1\\0Amovk x11, #65535, lsl #32\\0Amovk x11, #65535, lsl #48\\0Adup v6.2d, x11\\0A1:\\0Ald1 {v1.2d}, \[x13], #16\\0Ald1 {v2.2d}, \[x14], #16\\0Aadd v0.2d, v1.2d, v2.2d\\0Acmhi v3.2d, v1.2d, v0.2d\\0Aand v4.16b, v3.16b, v7.16b\\0Aadd v0.2d, v0.2d, v4.2d\\0Acmhs v5.2d, v0.2d, v6.2d\\0Aand v8.16b, v5.16b, v6.16b\\0Asub v0.2d, v0.2d, v8.2d\\0Ast1 {v0.2d}, \[x15], #16\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x11},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{memory},~{cc}\"(i64 " + inst[:ap] + ", i64 " + inst[:bp] + ", i64 " + inst[:outp] + ", i64 " + inst[:n] + ")"
  when :asm_add_no
    # offset add_n: out[oo..]=a[ao..]+b[bo..] over n limbs; ptr = base + off<<3 in
    # asm. GMP-shape flag-threaded adc. Returns carry. (basecase for the Toom ladder)
    t = inst[:temp]
    asmt = "add x15, ${1:x}, ${2:x}, lsl #3\\0Aadd x13, ${3:x}, ${4:x}, lsl #3\\0Aadd x14, ${5:x}, ${6:x}, lsl #3\\0Amov x9, ${7:x}\\0Acmn xzr, xzr\\0A1:\\0Aldr x10, \[x13], #8\\0Aldr x11, \[x14], #8\\0Aadcs x12, x10, x11\\0Astr x12, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Acset ${0:x}, cs"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,r,r,~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}\"(i64 " + inst[:outp] + ", i64 " + inst[:ooff] + ", i64 " + inst[:ap] + ", i64 " + inst[:aoff] + ", i64 " + inst[:bp] + ", i64 " + inst[:boff] + ", i64 " + inst[:n] + ")"
  when :asm_sub_no
    # offset sub_n: out[oo..]=a[ao..]-b[bo..]; GMP-shape sbcs. Returns borrow.
    t = inst[:temp]
    asmt = "add x15, ${1:x}, ${2:x}, lsl #3\\0Aadd x13, ${3:x}, ${4:x}, lsl #3\\0Aadd x14, ${5:x}, ${6:x}, lsl #3\\0Amov x9, ${7:x}\\0Asubs xzr, xzr, xzr\\0A1:\\0Aldr x10, \[x13], #8\\0Aldr x11, \[x14], #8\\0Asbcs x12, x10, x11\\0Astr x12, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Acset ${0:x}, cc"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,r,r,~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}\"(i64 " + inst[:outp] + ", i64 " + inst[:ooff] + ", i64 " + inst[:ap] + ", i64 " + inst[:aoff] + ", i64 " + inst[:bp] + ", i64 " + inst[:boff] + ", i64 " + inst[:n] + ")"
  when :asm_addmul1
    # offset addmul_1: out[oo..] += a[ao..]*bsc; GMP __gmpn_addmul_1; returns carry.
    # x14=out ptr, x13=a ptr, x3=bsc, x9=n, x15=carry.
    t = inst[:temp]
    asmt = "add x14, ${1:x}, ${2:x}, lsl #3\\0Aadd x13, ${3:x}, ${4:x}, lsl #3\\0Amov x3, ${5:x}\\0Amov x9, ${6:x}\\0Amov x15, #0\\0A1:\\0Aldr x4, \[x13], #8\\0Amul x8, x4, x3\\0Aumulh x12, x4, x3\\0Aadds x8, x8, x15\\0Aadc x12, x12, xzr\\0Aldr x5, \[x14]\\0Aadds x8, x5, x8\\0Aadc x15, x12, xzr\\0Astr x8, \[x14], #8\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, x15"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,r,~{x3},~{x4},~{x5},~{x8},~{x9},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}\"(i64 " + inst[:outp] + ", i64 " + inst[:ooff] + ", i64 " + inst[:ap] + ", i64 " + inst[:aoff] + ", i64 " + inst[:bsc] + ", i64 " + inst[:n] + ")"
  when :asm_mulbase
    # GMP mpn_mul_basecase as ONE asm block: out[oo..oo+na+nb) = a[ao..]*b[bo..].
    # row 0 = mul_1, rows 1..na-1 = addmul_1. One call/basecase (no per-row spill).
    # x16=out base, x17=a ptr, x7=b base; inner: x2=b ptr,x4=out ptr,x5=nb,x15=carry.
    t = inst[:temp]
    asmt = "add x16, ${1:x}, ${2:x}, lsl #3\\0Aadd x17, ${3:x}, ${4:x}, lsl #3\\0Aadd x7, ${5:x}, ${6:x}, lsl #3\\0Aldr x6, \[x17], #8\\0Amov x2, x7\\0Amov x4, x16\\0Amov x5, ${8:x}\\0Amov x15, #0\\0A1:\\0Aldr x10, \[x2], #8\\0Amul x8, x10, x6\\0Aumulh x12, x10, x6\\0Aadds x8, x8, x15\\0Aadc x15, x12, xzr\\0Astr x8, \[x4], #8\\0Asubs x5, x5, #1\\0Abne 1b\\0Astr x15, \[x4]\\0Asubs x3, ${7:x}, #1\\0Amov x14, x16\\0A2:\\0Acbz x3, 3f\\0Aadd x14, x14, #8\\0Aldr x6, \[x17], #8\\0Amov x2, x7\\0Amov x4, x14\\0Amov x5, ${8:x}\\0Amov x15, #0\\0A4:\\0Aldr x10, \[x2], #8\\0Amul x8, x10, x6\\0Aumulh x12, x10, x6\\0Aadds x8, x8, x15\\0Aadc x12, x12, xzr\\0Aldr x9, \[x4]\\0Aadds x8, x9, x8\\0Aadc x15, x12, xzr\\0Astr x8, \[x4], #8\\0Asubs x5, x5, #1\\0Abne 4b\\0Astr x15, \[x4]\\0Asub x3, x3, #1\\0Ab 2b\\0A3:\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,r,r,r,~{x2},~{x3},~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x12},~{x14},~{x15},~{x16},~{x17},~{memory},~{cc}\"(i64 " + inst[:outp] + ", i64 " + inst[:ooff] + ", i64 " + inst[:ap] + ", i64 " + inst[:aoff] + ", i64 " + inst[:bp] + ", i64 " + inst[:boff] + ", i64 " + inst[:na] + ", i64 " + inst[:nb] + ")"
  when :sdiv_i128
    inst[:temp] + " = sdiv i128 " + inst[:lhs] + ", " + inst[:rhs]
  when :udiv_i128
    inst[:temp] + " = udiv i128 " + inst[:lhs] + ", " + inst[:rhs]
  when :srem_i128
    inst[:temp] + " = srem i128 " + inst[:lhs] + ", " + inst[:rhs]
  when :urem_i128
    inst[:temp] + " = urem i128 " + inst[:lhs] + ", " + inst[:rhs]

  # Checked i48 arithmetic with overflow branch to bigint
  when :add_i48_checked, :sub_i48_checked
    intrinsic = "llvm.sadd.with.overflow.i64"
    if op == :sub_i48_checked
      intrinsic = "llvm.ssub.with.overflow.i64"
    bid = inst[:block_id].to_s()
    t = inst[:temp]
    pair = t + ".pair"
    raw = t + ".raw"
    i64ovf = t + ".i64ovf"
    over = t + ".over"
    under = t + ".under"
    rovf = t + ".rovf"
    ovf = t + ".ovf"
    masked = t + ".masked"
    boxed = t + ".fast"
    slow = t + ".slow"
    out = StringBuffer(384)
    out << pair + " = call {i64, i1} @" + intrinsic + "(i64 " + inst[:lhs] + ", i64 " + inst[:rhs] + ")\n  "
    out << raw + " = extractvalue {i64, i1} " + pair + ", 0\n  "
    out << i64ovf + " = extractvalue {i64, i1} " + pair + ", 1\n  "
    out << over + " = icmp sgt i64 " + raw + ", 140737488355327\n  "
    out << under + " = icmp slt i64 " + raw + ", -140737488355328\n  "
    out << rovf + " = or i1 " + over + ", " + under + "\n  "
    out << ovf + " = or i1 " + i64ovf + ", " + rovf + "\n  "
    out << "br i1 " + ovf + ", label %ovf.slow." + bid + ", label %ovf.fast." + bid + "\n"
    out << "ovf.fast." + bid + ":\n  "
    out << masked + " = and i64 " + raw + ", 281474976710655\n  "
    out << boxed + " = or i64 " + masked + ", -1688849860263936\n  "
    out << "br label %ovf.merge." + bid + "\n"
    out << "ovf.slow." + bid + ":\n  "
    out << slow + " = call i64 @" + inst[:rt_fallback] + "(i64 " + inst[:lhs_boxed] + ", i64 " + inst[:rhs_boxed] + ")\n  "
    out << "br label %ovf.merge." + bid + "\n"
    out << "ovf.merge." + bid + ":\n  "
    out << t + " = phi i64 \[" + boxed + ", %ovf.fast." + bid + "], \[" + slow + ", %ovf.slow." + bid + "]"
    out.to_s()

  when :mul_i48_checked
    bid = inst[:block_id].to_s()
    t = inst[:temp]
    pair = t + ".pair"
    raw = t + ".raw"
    i64ovf = t + ".i64ovf"
    over = t + ".over"
    under = t + ".under"
    rovf = t + ".rovf"
    ovf = t + ".ovf"
    masked = t + ".masked"
    boxed = t + ".fast"
    slow = t + ".slow"
    out = StringBuffer(384)
    out << pair + " = call {i64, i1} @llvm.smul.with.overflow.i64(i64 " + inst[:lhs] + ", i64 " + inst[:rhs] + ")\n  "
    out << raw + " = extractvalue {i64, i1} " + pair + ", 0\n  "
    out << i64ovf + " = extractvalue {i64, i1} " + pair + ", 1\n  "
    out << over + " = icmp sgt i64 " + raw + ", 140737488355327\n  "
    out << under + " = icmp slt i64 " + raw + ", -140737488355328\n  "
    out << rovf + " = or i1 " + over + ", " + under + "\n  "
    out << ovf + " = or i1 " + i64ovf + ", " + rovf + "\n  "
    out << "br i1 " + ovf + ", label %ovf.slow." + bid + ", label %ovf.fast." + bid + "\n"
    out << "ovf.fast." + bid + ":\n  "
    out << masked + " = and i64 " + raw + ", 281474976710655\n  "
    out << boxed + " = or i64 " + masked + ", -1688849860263936\n  "
    out << "br label %ovf.merge." + bid + "\n"
    out << "ovf.slow." + bid + ":\n  "
    out << slow + " = call i64 @" + inst[:rt_fallback] + "(i64 " + inst[:lhs_boxed] + ", i64 " + inst[:rhs_boxed] + ")\n  "
    out << "br label %ovf.merge." + bid + "\n"
    out << "ovf.merge." + bid + ":\n  "
    out << t + " = phi i64 \[" + boxed + ", %ovf.fast." + bid + "], \[" + slow + ", %ovf.slow." + bid + "]"
    out.to_s()

  # Guarded i48 arithmetic: inline fast path for boxed ints, runtime fallback otherwise.
  when :add_i48_guarded, :sub_i48_guarded, :mul_i48_guarded
    render_guarded_i48(inst)

  # Bitwise
  when :and_i64
    inst[:temp] + " = and i64 " + inst[:lhs] + ", " + inst[:rhs]
  when :or_i64
    inst[:temp] + " = or i64 " + inst[:lhs] + ", " + inst[:rhs]
  when :xor_i64
    inst[:temp] + " = xor i64 " + inst[:lhs] + ", " + inst[:rhs]
  when :shl_i64
    inst[:temp] + " = shl i64 " + inst[:lhs] + ", " + inst[:rhs]
  when :ashr_i64
    inst[:temp] + " = ashr i64 " + inst[:lhs] + ", " + inst[:rhs]
  when :lshr_i64
    inst[:temp] + " = lshr i64 " + inst[:lhs] + ", " + inst[:rhs]
  when :and_i128
    inst[:temp] + " = and i128 " + inst[:lhs] + ", " + inst[:rhs]
  when :or_i128
    inst[:temp] + " = or i128 " + inst[:lhs] + ", " + inst[:rhs]
  when :xor_i128
    inst[:temp] + " = xor i128 " + inst[:lhs] + ", " + inst[:rhs]
  when :shl_i128
    inst[:temp] + " = shl i128 " + inst[:lhs] + ", " + inst[:rhs]
  when :ashr_i128
    inst[:temp] + " = ashr i128 " + inst[:lhs] + ", " + inst[:rhs]
  when :lshr_i128
    if inst[:lhs] != nil
      inst[:temp] + " = lshr i128 " + inst[:lhs] + ", " + inst[:rhs]
    elsif inst[:shift] != nil
      inst[:temp] + " = lshr i128 " + inst[:value] + ", " + inst[:shift].to_s()
    else
      "; UNKNOWN WIRE OP: " + op.to_s()

  # Comparison
  when :icmp_i64
    inst[:temp] + " = icmp " + inst[:pred] + " i64 " + inst[:lhs] + ", " + inst[:rhs]
  when :truthy_inline
    inst[:temp] + " = icmp ugt i64 " + inst[:value] + ", 1"
  when :icmp_ne_zero
    inst[:temp] + " = icmp ne i64 " + inst[:value] + ", 0"
  when :icmp_ne_i64
    inst[:temp] + " = icmp ne i64 " + inst[:lhs] + ", " + inst[:rhs]
  when :icmp_i128
    inst[:temp] + " = icmp " + inst[:pred] + " i128 " + inst[:lhs] + ", " + inst[:rhs]

  # Boolean
  when :and_i1
    inst[:temp] + " = and i1 " + inst[:lhs] + ", " + inst[:rhs]
  when :or_i1
    inst[:temp] + " = or i1 " + inst[:lhs] + ", " + inst[:rhs]
  when :not_i1
    inst[:temp] + " = xor i1 " + inst[:value] + ", true"

  # Cast
  when :zext_i1_i64
    inst[:temp] + " = zext i1 " + inst[:value] + " to i64"
  when :trunc_i64_i32
    inst[:temp] + " = trunc i64 " + inst[:value] + " to i32"
  when :sext_i64_i128
    inst[:temp] + " = sext i64 " + inst[:value] + " to i128"
  when :zext_i32_i64
    inst[:temp] + " = zext i32 " + inst[:value] + " to i64"
  when :select_i64
    inst[:temp] + " = select i1 " + inst[:cond] + ", i64 " + inst[:then_val] + ", i64 " + inst[:else_val]

  # NaN-boxing
  when :nanbox_int
    raw = inst[:raw]
    ch = raw.slice(0, 1)
    if ch != nil && (ch == "-" || (ch >= "0" && ch <= "9"))
      wval = (raw.to_i() & 281474976710655) | -1688849860263936
      lit = llvm_wvalue_literal(wval)
      inst[:temp_masked] + " = or i64 0, " + lit + "\n  " + inst[:temp] + " = or i64 0, " + lit
    else
      inst[:temp_masked] + " = and i64 " + raw + ", " + w_payload_mask.to_s() + "\n  " + inst[:temp] + " = or i64 " + inst[:temp_masked] + ", " + w_tag_int.to_s()
  when :nanunbox_int
    inst[:temp_shl] + " = shl i64 " + inst[:boxed] + ", 16\n  " + inst[:temp] + " = ashr i64 " + inst[:temp_shl] + ", 16"
  when :nanbox_bool
    inst[:temp] + " = select i1 " + inst[:value] + ", i64 " + w_true.to_s() + ", i64 " + w_false.to_s()
  when :nanunbox_float
    inst[:temp_bits] + " = sub i64 " + inst[:boxed] + ", " + w_double_bias.to_s() + "\n  " + inst[:temp] + " = bitcast i64 " + inst[:temp_bits] + " to double"
  when :nanbox_float
    inst[:temp_bits] + " = bitcast double " + inst[:raw] + " to i64\n  " + inst[:temp] + " = add i64 " + inst[:temp_bits] + ", " + w_double_bias.to_s()

  # Raw float value plumbing
  when :fpext_f32_f64
    inst[:temp] + " = fpext float " + inst[:value] + " to double"
  when :fptrunc_f64_f32
    inst[:temp] + " = fptrunc double " + inst[:value] + " to float"
  when :fptosi_f64_i64
    inst[:temp] + " = fptosi double " + inst[:value] + " to i64"
  when :bitcast_i64_f64
    inst[:temp] + " = bitcast i64 " + inst[:value] + " to double"
  when :bitcast_f64_i64
    inst[:temp] + " = bitcast double " + inst[:value] + " to i64"
  when :bitcast_i32_f32
    inst[:temp] + " = bitcast i32 " + inst[:value] + " to float"
  when :bitcast_f32_i32
    inst[:temp] + " = bitcast float " + inst[:value] + " to i32"

  # Float arithmetic — inst[:fp_flags] overrides the function-level default for
  # @fastmath / @strictmath block scopes; nil means use the function default.
  when :fadd_f64
    f = inst[:fp_flags]
    f = fp_flags if f == nil
    inst[:temp] + " = fadd " + f + "double " + inst[:lhs] + ", " + inst[:rhs]
  when :fsub_f64
    f = inst[:fp_flags]
    f = fp_flags if f == nil
    inst[:temp] + " = fsub " + f + "double " + inst[:lhs] + ", " + inst[:rhs]
  when :fmul_f64
    f = inst[:fp_flags]
    f = fp_flags if f == nil
    inst[:temp] + " = fmul " + f + "double " + inst[:lhs] + ", " + inst[:rhs]
  when :fdiv_f64
    f = inst[:fp_flags]
    f = fp_flags if f == nil
    inst[:temp] + " = fdiv " + f + "double " + inst[:lhs] + ", " + inst[:rhs]
  when :frem_f64
    inst[:temp] + " = frem double " + inst[:lhs] + ", " + inst[:rhs]

  # FMA peephole: emitted by lowering/ops.w for a*b+c / a*b-c in precise mode.
  # This is the llvm.fmuladd intrinsic: "fuse if target supports it" — always
  # maps to a single hardware FMA on targets that have one (ARM, x86 AVX2+).
  # Operands ride on :lhs (a) / :rhs (b) / :value (c) — the three field names
  # already known to apply_subst (mem2reg) and content_hash. Using novel keys
  # would make the mul/add operands invisible to those operand-walkers, so a
  # promoted-away load would leave the fmuladd referencing a deleted temp.
  when :fmuladd_f64
    inst[:temp] + " = call double @llvm.fmuladd.f64(double " + inst[:lhs] + ", double " + inst[:rhs] + ", double " + inst[:value] + ")"
  # Explicit `fma(a,b,c)` — llvm.fma.f64 is ALWAYS a true fused multiply-add
  # (single rounding), unlike fmuladd's "contract if profitable". Same
  # lhs/rhs/value operand fields for mem2reg/content-hash safety.
  when :fma_f64
    inst[:temp] + " = call double @llvm.fma.f64(double " + inst[:lhs] + ", double " + inst[:rhs] + ", double " + inst[:value] + ")"
  # Raw libm call — Math.* fast path on unboxed operands (lowering/
  # method_call.w). Unary rides on :value, binary (pow/atan2) on :lhs/:rhs —
  # all three field names are walked by apply_subst and content_hash, so
  # mem2reg promotion of the operand loads stays correct (see :fmuladd_f64).
  when :call_libm_f64
    if inst[:value] != nil
      inst[:temp] + " = call double @" + inst[:name] + "(double " + inst[:value] + ")"
    else
      inst[:temp] + " = call double @" + inst[:name] + "(double " + inst[:lhs] + ", double " + inst[:rhs] + ")"

  # Fused-elementwise loop ops (lowering/ops.w try_fuse_elementwise). The
  # header decode is hoisted out of the fused loop deliberately: the loop
  # body the fuser emits contains no push/clear/realloc, so slots/start are
  # invariant for its duration — unlike typed_array_get_inline sites, which
  # must re-read them per access. Operands ride on :value/:ptr/:index only
  # (fields apply_subst and content_hash already walk).
  when :ta_f64_elems_ptr
    t = inst[:temp]
    v = inst[:value]
    parts = StringBuffer(420)
    parts << t + ".hdr = and i64 " + v + ", -16\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".slp = getelementptr i8, ptr " + t + ".hp, i64 16\n  "
    parts << t + ".slots = load ptr, ptr " + t + ".slp, align 8\n  "
    parts << t + ".stp = getelementptr i8, ptr " + t + ".hp, i64 4\n  "
    parts << t + ".st32 = load i32, ptr " + t + ".stp, align 4\n  "
    parts << t + ".st = sext i32 " + t + ".st32 to i64\n  "
    parts << t + " = getelementptr double, ptr " + t + ".slots, i64 " + t + ".st"
    parts.to_s()
  when :ta_size_raw
    t = inst[:temp]
    v = inst[:value]
    parts = StringBuffer(240)
    parts << t + ".hdr = and i64 " + v + ", -16\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".szp = getelementptr i8, ptr " + t + ".hp, i64 8\n  "
    parts << t + ".sz32 = load i32, ptr " + t + ".szp, align 4\n  "
    parts << t + " = sext i32 " + t + ".sz32 to i64"
    parts.to_s()
  when :load_f64_at
    t = inst[:temp]
    t + ".p = getelementptr double, ptr " + inst[:ptr] + ", i64 " + inst[:index] + "\n  " + t + " = load double, ptr " + t + ".p, align 8"
  when :store_f64_at
    t = inst[:temp]
    t + " = getelementptr double, ptr " + inst[:ptr] + ", i64 " + inst[:index] + "\n  store double " + inst[:value] + ", ptr " + t + ", align 8"
  # f32 variants: 4-byte stride, fpext on load / fptrunc on store so the
  # fused per-element computation stays in f64 (matching the CPU kernels,
  # which read f32 elements into doubles).
  when :load_f32_at
    t = inst[:temp]
    t + ".p = getelementptr float, ptr " + inst[:ptr] + ", i64 " + inst[:index] + "\n  " + t + ".f32 = load float, ptr " + t + ".p, align 4\n  " + t + " = fpext float " + t + ".f32 to double"
  when :store_f32_at
    t = inst[:temp]
    t + ".tr = fptrunc double " + inst[:value] + " to float\n  " + t + " = getelementptr float, ptr " + inst[:ptr] + ", i64 " + inst[:index] + "\n  store float " + t + ".tr, ptr " + t + ", align 4"
  when :load_i64_at
    t = inst[:temp]
    t + ".p = getelementptr i64, ptr " + inst[:ptr] + ", i64 " + inst[:index] + "\n  " + t + " = load i64, ptr " + t + ".p, align 8"
  # Element-0 address of a typed array as a raw i64 — the arg block handed
  # to w_fused_parallel_run / w_fused_gpu_run. 8-byte stride (i64 blocks).
  when :ta_data_addr
    t = inst[:temp]
    v = inst[:value]
    parts = StringBuffer(400)
    parts << t + ".hdr = and i64 " + v + ", -16\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".slp = getelementptr i8, ptr " + t + ".hp, i64 16\n  "
    parts << t + ".slots = load ptr, ptr " + t + ".slp, align 8\n  "
    parts << t + ".stp = getelementptr i8, ptr " + t + ".hp, i64 4\n  "
    parts << t + ".st32 = load i32, ptr " + t + ".stp, align 4\n  "
    parts << t + ".st = sext i32 " + t + ".st32 to i64\n  "
    parts << t + ".ep = getelementptr i64, ptr " + t + ".slots, i64 " + t + ".st\n  "
    parts << t + " = ptrtoint ptr " + t + ".ep to i64"
    parts.to_s()
  # f32 element-pointer decode (float stride) — sibling of :ta_f64_elems_ptr.
  when :ta_f32_elems_ptr
    t = inst[:temp]
    v = inst[:value]
    parts = StringBuffer(420)
    parts << t + ".hdr = and i64 " + v + ", -16\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".slp = getelementptr i8, ptr " + t + ".hp, i64 16\n  "
    parts << t + ".slots = load ptr, ptr " + t + ".slp, align 8\n  "
    parts << t + ".stp = getelementptr i8, ptr " + t + ".hp, i64 4\n  "
    parts << t + ".st32 = load i32, ptr " + t + ".stp, align 4\n  "
    parts << t + ".st = sext i32 " + t + ".st32 to i64\n  "
    parts << t + " = getelementptr float, ptr " + t + ".slots, i64 " + t + ".st"
    parts.to_s()
  when :inttoptr_i64
    inst[:temp] + " = inttoptr i64 " + inst[:value] + " to ptr"
  # Address of a module function as raw i64 — passed to the runtime fused
  # partitioner, which calls it back as int64_t(*)(int64_t,int64_t,int64_t).
  when :fn_addr_i64
    inst[:temp] + " = ptrtoint ptr @" + inst[:name] + " to i64"
  when :fneg_f64
    inst[:temp] + " = fneg double " + inst[:value]

  # Float comparison — fp_flags only applies for fast mode (nnan changes predicate semantics)
  when :fcmp_f64
    f = inst[:fp_flags]
    f = fp_flags if f == nil
    cmp_flags = f == "fast " ? "fast " : ""
    inst[:temp] + " = fcmp " + cmp_flags + inst[:pred] + " double " + inst[:lhs] + ", " + inst[:rhs]

  # i128 operations
  when :zext_i64_i128
    inst[:temp] + " = zext i64 " + inst[:value] + " to i128"
  when :trunc_i128_i64
    inst[:temp] + " = trunc i128 " + inst[:value] + " to i64"

  # Inline bool array get: load byte, add 1 -> W_FALSE(1) or W_TRUE(2)
  when :bool_array_get_byte_inline
    t = inst[:temp]
    arr = inst[:arr]
    idx = inst[:idx]
    ap = t + ".ap"
    ap_p = t + ".app"
    dg = t + ".dg"
    dp = t + ".dp"
    ep = t + ".ep"
    byte = t + ".byte"
    ext = t + ".ext"
    out = StringBuffer(256)
    out << ap + " = and i64 " + arr + ", -16\n  "
    out << ap_p + " = inttoptr i64 " + ap + " to ptr\n  "
    out << dg + " = getelementptr i8, ptr " + ap_p + ", i64 8\n  "
    out << dp + " = load ptr, ptr " + dg + "\n  "
    out << ep + " = getelementptr i8, ptr " + dp + ", i64 " + idx + "\n  "
    out << byte + " = load i8, ptr " + ep + ", align 1, !range !{i8 0, i8 2}\n  "
    out << ext + " = zext i8 " + byte + " to i64\n  "
    out << t + " = add i64 " + ext + ", 1"
    out.to_s()

  # Inline bool array set: store (val - 1) as byte. W_TRUE(2)->1, W_FALSE(1)->0
  when :bool_array_set_byte_inline
    t = inst[:temp]
    arr = inst[:arr]
    idx = inst[:idx]
    val = inst[:val]
    ap = t + ".ap"
    ap_p = t + ".app"
    dg = t + ".dg"
    dp = t + ".dp"
    ep = t + ".ep"
    sub = t + ".sub"
    byte_val = t + ".bv"
    out = StringBuffer(256)
    out << ap + " = and i64 " + arr + ", -16\n  "
    out << ap_p + " = inttoptr i64 " + ap + " to ptr\n  "
    out << dg + " = getelementptr i8, ptr " + ap_p + ", i64 8\n  "
    out << dp + " = load ptr, ptr " + dg + "\n  "
    out << ep + " = getelementptr i8, ptr " + dp + ", i64 " + idx + "\n  "
    out << sub + " = sub i64 " + val + ", 1\n  "
    out << byte_val + " = trunc i64 " + sub + " to i8\n  "
    out << "store i8 " + byte_val + ", ptr " + ep + "\n  "
    out << t + " = add i64 " + val + ", 0"
    out.to_s()

  # Inline bool array get (bit-packed): unbox ptr, load data, bit test.
  # Phase 4f WArray-merge layout: slots ptr at offset 16, start i32 at
  # offset 4 (matching typed_array_get_inline). Pre-merge this read from
  # offset 8, which now points at size/cap and produces a garbage pointer.
  when :bool_array_get_inline
    t = inst[:temp]
    arr = inst[:arr]
    idx = inst[:idx]
    ap = t + ".ap"
    ap_p = t + ".app"
    dg = t + ".dg"
    dp = t + ".dp"
    sg = t + ".sg"
    s32 = t + ".s32"
    s64 = t + ".s64"
    abs_idx = t + ".abs"
    bi = t + ".bi"
    bit64 = t + ".bit64"
    bit8 = t + ".bit8"
    mask = t + ".mask"
    ep = t + ".ep"
    byte = t + ".byte"
    masked = t + ".masked"
    is_set = t + ".is_set"
    out = StringBuffer(384)
    out << ap + " = and i64 " + arr + ", -16\n  "
    out << ap_p + " = inttoptr i64 " + ap + " to ptr\n  "
    out << dg + " = getelementptr i8, ptr " + ap_p + ", i64 16\n  "
    out << dp + " = load ptr, ptr " + dg + ", align 8\n  "
    out << sg + " = getelementptr i8, ptr " + ap_p + ", i64 4\n  "
    out << s32 + " = load i32, ptr " + sg + ", align 4\n  "
    out << s64 + " = sext i32 " + s32 + " to i64\n  "
    out << abs_idx + " = add i64 " + s64 + ", " + idx + "\n  "
    out << bi + " = lshr i64 " + abs_idx + ", 3\n  "
    out << bit64 + " = and i64 " + abs_idx + ", 7\n  "
    out << bit8 + " = trunc i64 " + bit64 + " to i8\n  "
    out << mask + " = shl i8 1, " + bit8 + "\n  "
    out << ep + " = getelementptr i8, ptr " + dp + ", i64 " + bi + "\n  "
    out << byte + " = load i8, ptr " + ep + "\n  "
    out << masked + " = and i8 " + byte + ", " + mask + "\n  "
    # Two output flavors. With as_i1 the inline op leaves `t` as the
    # raw bit (`icmp ne i8 masked, 0`) — `if !bits[i]` / `while bits[i]`
    # consumers can branch on it directly. Without, we wrap in a select
    # to produce the W_TRUE/W_FALSE WValue. The lowering picks as_i1
    # when it knows the caller wants a boolean (truthy-elision); other
    # call sites get the WValue form and ensure_i64_value re-boxes if
    # needed.
    if inst[:as_i1] == true
      out << t + " = icmp ne i8 " + masked + ", 0"
    else
      out << is_set + " = icmp ne i8 " + masked + ", 0\n  "
      out << t + " = select i1 " + is_set + ", i64 " + w_true.to_s() + ", i64 " + w_false.to_s()
    out.to_s()

  # Inline bool array set: val is guaranteed W_TRUE(2) or W_FALSE(1) by lowering.
  # Same offset fix as bool_array_get_inline above (slots ptr at offset 16,
  # start i32 at offset 4 — Phase 4f WArray-merge layout).
  when :bool_array_set_inline
    t = inst[:temp]
    arr = inst[:arr]
    idx = inst[:idx]
    val = inst[:val]
    ap = t + ".ap"
    ap_p = t + ".app"
    dg = t + ".dg"
    dp = t + ".dp"
    sg = t + ".sg"
    s32 = t + ".s32"
    s64 = t + ".s64"
    abs_idx = t + ".abs"
    bi = t + ".bi"
    bit64 = t + ".bit64"
    bit8 = t + ".bit8"
    mask = t + ".mask"
    ep = t + ".ep"
    byte = t + ".byte"
    set_bit = t + ".set"
    inv_mask = t + ".inv"
    cleared = t + ".clr"
    with_bit = t + ".wbit"
    new_byte = t + ".nb"
    out = StringBuffer(416)
    out << ap + " = and i64 " + arr + ", -16\n  "
    out << ap_p + " = inttoptr i64 " + ap + " to ptr\n  "
    out << dg + " = getelementptr i8, ptr " + ap_p + ", i64 16\n  "
    out << dp + " = load ptr, ptr " + dg + ", align 8\n  "
    out << sg + " = getelementptr i8, ptr " + ap_p + ", i64 4\n  "
    out << s32 + " = load i32, ptr " + sg + ", align 4\n  "
    out << s64 + " = sext i32 " + s32 + " to i64\n  "
    out << abs_idx + " = add i64 " + s64 + ", " + idx + "\n  "
    out << bi + " = lshr i64 " + abs_idx + ", 3\n  "
    out << bit64 + " = and i64 " + abs_idx + ", 7\n  "
    out << bit8 + " = trunc i64 " + bit64 + " to i8\n  "
    out << mask + " = shl i8 1, " + bit8 + "\n  "
    out << ep + " = getelementptr i8, ptr " + dp + ", i64 " + bi + "\n  "
    out << byte + " = load i8, ptr " + ep + "\n  "
    out << set_bit + " = icmp ugt i64 " + val + ", 1\n  "
    out << inv_mask + " = xor i8 " + mask + ", -1\n  "
    out << cleared + " = and i8 " + byte + ", " + inv_mask + "\n  "
    out << with_bit + " = or i8 " + cleared + ", " + mask + "\n  "
    out << new_byte + " = select i1 " + set_bit + ", i8 " + with_bit + ", i8 " + cleared + "\n  "
    out << "store i8 " + new_byte + ", ptr " + ep + "\n  "
    out << t + " = add i64 " + val + ", 0"
    out.to_s()

  # Int to float conversion
  when :sitofp_i64_f64
    inst[:temp] + " = sitofp i64 " + inst[:value] + " to double"
  when :uitofp_i64_f64
    inst[:temp] + " = uitofp i64 " + inst[:value] + " to double"
  when :sitofp_i128_f64
    inst[:temp] + " = sitofp i128 " + inst[:value] + " to double"
  when :uitofp_i128_f64
    inst[:temp] + " = uitofp i128 " + inst[:value] + " to double"

  # Float
  when :const_float
    bits_temp = inst[:temp] + ".bits"
    bits_temp + " = bitcast double " + inst[:value] + " to i64\n  " + inst[:temp] + " = add i64 " + bits_temp + ", " + w_double_bias.to_s()
  when :const_decimal
    inst[:temp] + " = call i64 @w_decimal(i64 " + inst[:sig].to_s() + ", i32 " + inst[:scale].to_s() + ")"
  when :const_currency
    inst[:temp] + " = call i64 @w_currency(i32 " + inst[:symbol_id].to_s() + ", i64 " + inst[:sig].to_s() + ", i32 " + inst[:scale].to_s() + ")"
  when :const_quantity
    inst[:temp] + " = call i64 @w_quantity(i32 " + inst[:unit_id].to_s() + ", i64 " + inst[:sig].to_s() + ", i32 " + inst[:scale].to_s() + ")"
  when :const_duration_ns
    inst[:temp] + " = call i64 @w_duration_ns(i64 " + inst[:ns].to_s() + ")"
  when :const_duration_months_ms
    inst[:temp] + " = call i64 @w_duration_months_ms(i32 " + inst[:months].to_s() + ", i32 " + inst[:ms].to_s() + ")"

  when :const_uuid
    used_ptr_ids[inst[:string_id]] = true
    lbr = "\["
    rbr = "]"
    bl = inst[:byte_len].to_s()
    inst[:temp_ptr] + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + inst[:string_id].to_s() + ", i32 0, i32 0\n  " + inst[:temp] + " = call i64 @w_uuid_from_hex(ptr " + inst[:temp_ptr] + ")"

  when :const_date
    inst[:temp] + " = call i64 @w_date(i32 " + inst[:year].to_s() + ", i32 " + inst[:month].to_s() + ", i32 " + inst[:day].to_s() + ", i32 " + inst[:hour].to_s() + ", i32 " + inst[:min].to_s() + ", i32 " + inst[:sec].to_s() + ", i32 " + inst[:tz].to_s() + ")"

  when :const_ipv4
    inst[:temp] + " = call i64 @w_ipv4(i32 " + inst[:a].to_s() + ", i32 " + inst[:b].to_s() + ", i32 " + inst[:c].to_s() + ", i32 " + inst[:d].to_s() + ", i32 " + inst[:cidr].to_s() + ")"

  when :const_ipv6
    used_ptr_ids[inst[:string_id]] = true
    lbr = "\["
    rbr = "]"
    bl = inst[:byte_len].to_s()
    inst[:temp_ptr] + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + inst[:string_id].to_s() + ", i32 0, i32 0\n  " + inst[:temp] + " = call i64 @w_ipv6_from_string(ptr " + inst[:temp_ptr] + ", i32 " + inst[:cidr].to_s() + ")"

  when :const_rational
    inst[:temp] + " = call i64 @w_rational(i32 " + inst[:num].to_s() + ", i32 " + inst[:den].to_s() + ")"

  when :const_char
    inst[:temp] + " = call i64 @w_box_char(i32 " + inst[:codepoint].to_s() + ")" + wvalue_char_range_metadata_suffix()

  when :const_color
    inst[:temp] + " = call i64 @w_color(i32 " + inst[:r].to_s() + ", i32 " + inst[:g].to_s() + ", i32 " + inst[:b].to_s() + ", i32 " + inst[:a].to_s() + ")"

  # View access: load byte from raw object pointer
  when :view_load_byte
    ptr_raw = inst[:temp] + ".ptr"
    byte_ptr = inst[:temp] + ".bp"
    byte_val = inst[:temp] + ".b"
    ptr_raw + " = and i64 " + inst[:ptr] + ", -16\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + inst[:temp] + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + inst[:index] + "\n  " + byte_val + " = load i8, ptr " + inst[:temp] + ".gep\n  " + inst[:temp] + ".zext = zext i8 " + byte_val + " to i64\n  " + w_int_call_with_range(inst[:temp], inst[:temp] + ".zext", 0, 256)

  # Fixed inline u8[N] field: load at the statically known field offset plus
  # the caller-checked dynamic index. No hidden bounds branch is emitted.
  when :view_load_inline_byte
    ptr_raw = inst[:temp] + ".ptr"
    byte_ptr = inst[:temp] + ".bp"
    byte_val = inst[:temp] + ".b"
    ptr_raw + " = and i64 " + inst[:ptr] + ", -16\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + inst[:temp] + ".base = getelementptr i8, ptr " + byte_ptr + ", i64 " + inst[:offset].to_s() + "\n  " + inst[:temp] + ".gep = getelementptr i8, ptr " + inst[:temp] + ".base, i64 " + inst[:index] + "\n  " + byte_val + " = load i8, ptr " + inst[:temp] + ".gep\n  " + inst[:temp] + " = zext i8 " + byte_val + " to i64"

  # View access: load bit from raw object pointer
  when :view_load_bit
    ptr_raw = inst[:temp] + ".ptr"
    byte_ptr = inst[:temp] + ".bp"
    byte_idx = inst[:temp] + ".bidx"
    bit_idx = inst[:temp] + ".bitidx"
    byte_val = inst[:temp] + ".b"
    shifted = inst[:temp] + ".sh"
    masked = inst[:temp] + ".m"
    ptr_raw + " = and i64 " + inst[:ptr] + ", -16\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + byte_idx + " = lshr i64 " + inst[:index] + ", 3\n  " + inst[:temp] + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + byte_idx + "\n  " + byte_val + " = load i8, ptr " + inst[:temp] + ".gep\n  " + bit_idx + " = and i64 " + inst[:index] + ", 7\n  " + bit_idx + ".trunc = trunc i64 " + bit_idx + " to i8\n  " + shifted + " = lshr i8 " + byte_val + ", " + bit_idx + ".trunc\n  " + masked + " = and i8 " + shifted + ", 1\n  " + inst[:temp] + ".zext = zext i8 " + masked + " to i64\n  " + w_int_call_with_range(inst[:temp], inst[:temp] + ".zext", 0, 2)

  # View field: load a named field at known offset/size from raw object pointer
  when :view_load_field
    ptr_raw = inst[:temp] + ".ptr"
    byte_ptr = inst[:temp] + ".bp"
    ftype = inst[:field_type]
    offset = inst[:offset].to_s()
    size = inst[:size]
    extension = ftype.starts_with?("i") ? "sext" : "zext"
    if ftype.starts_with?("*")
      # Pointer field: load ptr, then ptrtoint
      ptr_raw + " = and i64 " + inst[:ptr] + ", -16\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + inst[:temp] + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + inst[:temp] + ".p = load ptr, ptr " + inst[:temp] + ".gep\n  " + inst[:temp] + " = ptrtoint ptr " + inst[:temp] + ".p to i64"
    elsif ftype == "f32"
      ptr_raw + " = and i64 " + inst[:ptr] + ", -16\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + inst[:temp] + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + inst[:temp] + " = load float, ptr " + inst[:temp] + ".gep, align 1"
    elsif ftype == "f64"
      ptr_raw + " = and i64 " + inst[:ptr] + ", -16\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + inst[:temp] + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + inst[:temp] + " = load double, ptr " + inst[:temp] + ".gep, align 1"
    elsif size == 1
      ptr_raw + " = and i64 " + inst[:ptr] + ", -16\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + inst[:temp] + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + inst[:temp] + ".b = load i8, ptr " + inst[:temp] + ".gep, align 1\n  " + inst[:temp] + " = " + extension + " i8 " + inst[:temp] + ".b to i64"
    elsif size == 2
      ptr_raw + " = and i64 " + inst[:ptr] + ", -16\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + inst[:temp] + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + inst[:temp] + ".h = load i16, ptr " + inst[:temp] + ".gep, align 1\n  " + inst[:temp] + " = " + extension + " i16 " + inst[:temp] + ".h to i64"
    elsif size == 4
      ptr_raw + " = and i64 " + inst[:ptr] + ", -16\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + inst[:temp] + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + inst[:temp] + ".w = load i32, ptr " + inst[:temp] + ".gep, align 1\n  " + inst[:temp] + " = " + extension + " i32 " + inst[:temp] + ".w to i64"
    else
      # 8 bytes (i64)
      ptr_raw + " = and i64 " + inst[:ptr] + ", -16\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + inst[:temp] + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + inst[:temp] + " = load i64, ptr " + inst[:temp] + ".gep"

  # View base: extract raw pointer from object
  when :view_base_ptr
    inst[:temp] + " = and i64 " + inst[:value] + ", -16"

  # Register custom unit: call w_register_unit(i32 id, ptr name)
  when :register_unit
    swv = nil
    if string_wvs != nil
      swv = string_wvs[inst[:str_id]]
    if swv != nil
      "call void @w_register_unit_wv(i32 " + inst[:unit_id].to_s() + ", i64 " + llvm_wvalue_literal(swv) + ")"
    else
      used_ptr_ids[inst[:str_id]] = true
      lbr = "\["
      rbr = "]"
      bl = inst[:byte_len].to_s()
      tmp = "%reg.unit." + inst[:unit_id].to_s()
      tmp + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + inst[:str_id].to_s() + ", i32 0, i32 0\n  " + tmp + ".wv = call i64 @w_string(ptr " + tmp + ")\n  call void @w_register_unit_wv(i32 " + inst[:unit_id].to_s() + ", i64 " + tmp + ".wv)"

  # String
  when :string_i64
    swv = nil
    if string_wvs != nil
      swv = string_wvs[inst[:string_id]]
    if swv != nil
      inst[:temp] + " = or i64 0, " + llvm_wvalue_literal(swv)
    else
      used_ptr_ids[inst[:string_id]] = true
      lbr = "\["
      rbr = "]"
      bl = inst[:byte_len].to_s()
      inst[:temp_ptr] + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + inst[:string_id].to_s() + ", i32 0, i32 0\n  " + inst[:temp] + " = call i64 @w_string(ptr " + inst[:temp_ptr] + ")"

  # Symbol: string WValue with bit 0 set
  when :symbol_i64
    swv = nil
    if string_wvs != nil
      swv = string_wvs[inst[:string_id]]
    if swv != nil
      inst[:temp] + " = or i64 " + llvm_wvalue_literal(swv) + ", 1"
    else
      used_ptr_ids[inst[:string_id]] = true
      lbr = "\["
      rbr = "]"
      bl = inst[:byte_len].to_s()
      inst[:temp_ptr] + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + inst[:string_id].to_s() + ", i32 0, i32 0\n  " + inst[:temp] + ".s = call i64 @w_string(ptr " + inst[:temp_ptr] + ")\n  " + inst[:temp] + " = call i64 @w_str_to_sym(i64 " + inst[:temp] + ".s)"

  # Slab-AST constructor fusion (fix #3). Inline bump + N field stores
  # against the same slot address — no per-field re-derivation of the
  # slot pointer from the W_PACKED_NODE encoding.
  when :slab_alloc_init
    t = inst[:temp]
    kind = inst[:kind]
    sc = inst[:sc]
    fields = inst[:fields]
    nf = fields.size()
    lbr = "\["
    label_fast = "sai_" + t.slice(1, t.size() - 1) + "_fast"
    label_slow = "sai_" + t.slice(1, t.size() - 1) + "_slow"
    label_merge = "sai_" + t.slice(1, t.size() - 1) + "_merge"
    parts = StringBuffer(1200 + nf * 200)
    # Freeze array-valued fields into the AST extra arena before the
    # store — child lists live arena-side (w_ast_freeze_if_array is a
    # tag-check passthrough for everything else). Emitted in the entry
    # block so the frozen temps dominate both the fast and slow stores.
    fi = 0
    while fi < nf
      parts << t + ".fz" + fi.to_s() + " = call i64 @w_ast_freeze_if_array(i64 " + fields[fi] + ")\n  "
      fi += 1
    parts << t + ".cursor_p = getelementptr inbounds " + lbr + "4 x { ptr, i32, i32 }], ptr @g_node_arena, i64 0, i64 " + sc + ", i32 1\n  "
    parts << t + ".cursor = load i32, ptr " + t + ".cursor_p, align 4\n  "
    parts << t + ".cap_p = getelementptr inbounds " + lbr + "4 x { ptr, i32, i32 }], ptr @g_node_arena, i64 0, i64 " + sc + ", i32 2\n  "
    parts << t + ".cap = load i32, ptr " + t + ".cap_p, align 4\n  "
    parts << t + ".has_room = icmp ult i32 " + t + ".cursor, " + t + ".cap\n  "
    parts << "br i1 " + t + ".has_room, label %" + label_fast + ", label %" + label_slow + "\n"
    parts << label_fast + ":\n  "
    parts << t + ".new_cursor = add i32 " + t + ".cursor, 1\n  "
    parts << "store i32 " + t + ".new_cursor, ptr " + t + ".cursor_p, align 4\n  "
    parts << t + ".base_p = getelementptr inbounds " + lbr + "4 x { ptr, i32, i32 }], ptr @g_node_arena, i64 0, i64 " + sc + ", i32 0\n  "
    parts << t + ".base = load ptr, ptr " + t + ".base_p, align 8\n  "
    parts << t + ".stride_p = getelementptr inbounds " + lbr + "4 x i32], ptr @g_node_stride, i64 0, i64 " + sc + "\n  "
    parts << t + ".stride32 = load i32, ptr " + t + ".stride_p, align 4\n  "
    parts << t + ".stride = zext i32 " + t + ".stride32 to i64\n  "
    parts << t + ".cursor64 = zext i32 " + t + ".cursor to i64\n  "
    parts << t + ".slot_off = mul i64 " + t + ".cursor64, " + t + ".stride\n  "
    parts << t + ".slot_addr = getelementptr i8, ptr " + t + ".base, i64 " + t + ".slot_off\n  "
    fi = 0
    while fi < nf
      parts << t + ".fp" + fi.to_s() + " = getelementptr i8, ptr " + t + ".slot_addr, i64 " + (fi * 8).to_s() + "\n  "
      parts << "store i64 " + t + ".fz" + fi.to_s() + ", ptr " + t + ".fp" + fi.to_s() + ", align 8\n  "
      fi += 1
    parts << t + ".sc_shifted = shl i64 " + sc + ", 34\n  "
    parts << t + ".kind_shifted = shl i64 " + kind + ", 36\n  "
    parts << t + ".p1 = or i64 " + t + ".sc_shifted, " + t + ".cursor64\n  "
    parts << t + ".p2 = or i64 " + t + ".kind_shifted, " + t + ".p1\n  "
    parts << t + ".fast_result = or i64 u0xFFFE600000000000, " + t + ".p2\n  "
    parts << "br label %" + label_merge + "\n"
    parts << label_slow + ":\n  "
    parts << t + ".slow_node = call i64 @w_node_alloc(i64 " + kind + ", i64 " + sc + ")\n  "
    parts << t + ".s.off = and i64 " + t + ".slow_node, 4294967295\n  "
    parts << t + ".s.base_p = getelementptr inbounds " + lbr + "4 x { ptr, i32, i32 }], ptr @g_node_arena, i64 0, i64 " + sc + ", i32 0\n  "
    parts << t + ".s.base = load ptr, ptr " + t + ".s.base_p, align 8\n  "
    parts << t + ".s.stride_p = getelementptr inbounds " + lbr + "4 x i32], ptr @g_node_stride, i64 0, i64 " + sc + "\n  "
    parts << t + ".s.stride32 = load i32, ptr " + t + ".s.stride_p, align 4\n  "
    parts << t + ".s.stride = zext i32 " + t + ".s.stride32 to i64\n  "
    parts << t + ".s.slot_off = mul i64 " + t + ".s.off, " + t + ".s.stride\n  "
    parts << t + ".s.slot_addr = getelementptr i8, ptr " + t + ".s.base, i64 " + t + ".s.slot_off\n  "
    fi = 0
    while fi < nf
      parts << t + ".s.fp" + fi.to_s() + " = getelementptr i8, ptr " + t + ".s.slot_addr, i64 " + (fi * 8).to_s() + "\n  "
      parts << "store i64 " + t + ".fz" + fi.to_s() + ", ptr " + t + ".s.fp" + fi.to_s() + ", align 8\n  "
      fi += 1
    parts << "br label %" + label_merge + "\n"
    parts << label_merge + ":\n  "
    parts << t + " = phi i64 " + lbr + " " + t + ".fast_result, %" + label_fast + " ], " + lbr + " " + t + ".slow_node, %" + label_slow + " ]"
    return parts.to_s()

  # Direct function calls. When carrying src_line, the call is rendered
  # `notail` and followed by a BB split (csd.N.ret) so the return address
  # is addressable for the __w_call_site lookup.
  when :call_direct_i64
    # Slab-AST intrinsic: w_node_alloc(kind, sc) — emit an inline bump
    # against @g_node_arena with a cmp/branch fallback to the runtime
    # @w_node_alloc on cap exhaustion (which grows + bumps). With fix #1's
    # constant-folded KIND_*/SC_* globals, LLVM collapses the kind/sc
    # shifts and OR into a single constant + bump in the fast path.
    #
    # Layout: per-arena struct is {ptr base, i32 cursor, i32 cap}.
    # Indices 1 and 2 reach cursor/cap respectively.
    #
    # Slab-AST intrinsic: w_node_field_load(node, offset) / w_node_field_store(
    # node, offset, value) — when the offset arg is a literal (which it always
    # is in ast.w call sites), emit inline LLVM IR that walks the
    # @g_node_arena slab directly instead of calling out to the runtime
    # helper. LLVM can then CSE the @g_node_arena base load across multiple
    # field accesses of the same node and fold the offset arithmetic into a
    # GEP. The args list is already lowered by the generic ccall_nobox path
    # in lowering/calls.w; the int-literal offset reaches here as a raw
    # decimal string because lower_int returns typed_value(:raw_int,
    # val.to_s()) without emitting an instruction.
    # Slab-AST intrinsic: w_node_kind_extern(v) → (v >> 36) & 0xFF.
    # Extracts the 8-bit kind field from a W_PACKED_NODE WValue (full
    # tier; compact-tier kinds have prefix=1 and live at >> 39, but no
    # compact kinds are populated yet so this fast path covers all
    # current usage). Called by ast_kind on every ast_get hot-path.
    if inst[:name] == "w_node_kind_extern" && inst[:args].size() == 1
      t = inst[:temp]
      v = inst[:args][0]
      return t + ".k_sh = lshr i64 " + v + ", 36\n  " + t + " = and i64 " + t + ".k_sh, 255"
    # Slab-AST intrinsic: w_is_node_extern(v) → 1 if v is a W_PACKED_NODE
    # (W_TAG_PACKED with subtype 3), 0 otherwise. (v >> 45) == 0x7FFF3
    # exploits the contiguous tag+subtype layout: 0xFFFE << 3 | 3.
    if inst[:name] == "w_is_node_extern" && inst[:args].size() == 1
      t = inst[:temp]
      v = inst[:args][0]
      parts = StringBuffer(180)
      parts << t + ".upper = lshr i64 " + v + ", 45\n  "
      parts << t + ".is_node = icmp eq i64 " + t + ".upper, 524275\n  "
      parts << t + " = zext i1 " + t + ".is_node to i64"
      return parts.to_s()
    if inst[:name] == "w_node_alloc" && inst[:args].size() == 2
      t = inst[:temp]
      kind_in = inst[:args][0]
      sc_in = inst[:args][1]
      lbr = "\["
      label_fast = "wna_" + t.slice(1, t.size() - 1) + "_fast"
      label_slow = "wna_" + t.slice(1, t.size() - 1) + "_slow"
      label_merge = "wna_" + t.slice(1, t.size() - 1) + "_merge"
      parts = StringBuffer(1040)
      # Defensive unbox: kind/sc here may carry the raw_int nanbox tag
      # (0xFFFA…) when they come from a runtime expression rather than a
      # literal KIND_*/SC_* global — e.g. ast_deep_clone's
      # `sc = sc_for_kind(kid)`, where the result is a `## i64` value
      # boxed into a general WValue local. The arena index (sc) and the
      # kind-shift below assume clean machine ints; an un-stripped tag
      # made sc into a huge GEP index and SEGV'd. Masking the low 48 bits
      # extracts the value and is idempotent for already-clean small
      # ints (kind ≤ 142, sc ≤ 3).
      kind = t + ".kind_clean"
      sc = t + ".sc_clean"
      parts << kind + " = and i64 " + kind_in + ", 281474976710655\n  "
      parts << sc + " = and i64 " + sc_in + ", 281474976710655\n  "
      parts << t + ".cursor_p = getelementptr inbounds " + lbr + "4 x { ptr, i32, i32 }], ptr @g_node_arena, i64 0, i64 " + sc + ", i32 1\n  "
      parts << t + ".cursor = load i32, ptr " + t + ".cursor_p, align 4\n  "
      parts << t + ".cap_p = getelementptr inbounds " + lbr + "4 x { ptr, i32, i32 }], ptr @g_node_arena, i64 0, i64 " + sc + ", i32 2\n  "
      parts << t + ".cap = load i32, ptr " + t + ".cap_p, align 4\n  "
      parts << t + ".has_room = icmp ult i32 " + t + ".cursor, " + t + ".cap\n  "
      parts << "br i1 " + t + ".has_room, label %" + label_fast + ", label %" + label_slow + "\n"
      parts << label_fast + ":\n  "
      parts << t + ".new_cursor = add i32 " + t + ".cursor, 1\n  "
      parts << "store i32 " + t + ".new_cursor, ptr " + t + ".cursor_p, align 4\n  "
      parts << t + ".cursor64 = zext i32 " + t + ".cursor to i64\n  "
      parts << t + ".sc_shifted = shl i64 " + sc + ", 34\n  "
      parts << t + ".kind_shifted = shl i64 " + kind + ", 36\n  "
      parts << t + ".p1 = or i64 " + t + ".sc_shifted, " + t + ".cursor64\n  "
      parts << t + ".p2 = or i64 " + t + ".kind_shifted, " + t + ".p1\n  "
      parts << t + ".fast_result = or i64 u0xFFFE600000000000, " + t + ".p2\n  "
      parts << "br label %" + label_merge + "\n"
      parts << label_slow + ":\n  "
      parts << t + ".slow_result = call i64 @w_node_alloc(i64 " + kind + ", i64 " + sc + ")\n  "
      parts << "br label %" + label_merge + "\n"
      parts << label_merge + ":\n  "
      parts << t + " = phi i64 " + lbr + " " + t + ".fast_result, %" + label_fast + " ], " + lbr + " " + t + ".slow_result, %" + label_slow + " ]"
      return parts.to_s()
    slab_intrinsic = false
    if inst[:name] == "w_node_field_load" || inst[:name] == "w_node_field_store"
      if inst[:args].size() >= 2
        first_char = inst[:args][1][0]
        if first_char != "%"
          slab_intrinsic = true
    if slab_intrinsic
      t = inst[:temp]
      n = inst[:args][0]
      ivar_byte = (inst[:args][1].to_i() * 8).to_s()
      lbr = "\["
      parts = StringBuffer(460)
      parts << t + ".off = and i64 " + n + ", 4294967295\n  "
      # Size-class lives at bits 34-35 in W_PACKED_NODE (W_NODE_SCLASS_SHIFT
      # = W_NODE_OFFSET_BITS + W_NODE_RESERVED_BITS = 32 + 2 = 34). Bits
      # 32-33 are reserved and always zero, so the prior `lshr ..., 32`
      # read zero as the sclass and looked up SC_2's stride / arena
      # regardless of the node's actual class.
      parts << t + ".sc_sh = lshr i64 " + n + ", 34\n  "
      parts << t + ".sc = and i64 " + t + ".sc_sh, 3\n  "
      parts << t + ".stride_p = getelementptr inbounds " + lbr + "4 x i32], ptr @g_node_stride, i64 0, i64 " + t + ".sc\n  "
      parts << t + ".stride32 = load i32, ptr " + t + ".stride_p, align 4\n  "
      parts << t + ".stride = zext i32 " + t + ".stride32 to i64\n  "
      parts << t + ".scaled = mul i64 " + t + ".off, " + t + ".stride\n  "
      parts << t + ".full = add i64 " + t + ".scaled, " + ivar_byte + "\n  "
      parts << t + ".base_p = getelementptr inbounds " + lbr + "4 x { ptr, i32, i32 }], ptr @g_node_arena, i64 0, i64 " + t + ".sc, i32 0\n  "
      parts << t + ".base = load ptr, ptr " + t + ".base_p, align 8\n  "
      parts << t + ".gep = getelementptr i8, ptr " + t + ".base, i64 " + t + ".full"
      if inst[:name] == "w_node_field_load"
        parts << "\n  " + t + " = load i64, ptr " + t + ".gep, align 8"
      else
        # Freeze array values into the AST extra arena on the inline
        # store path too — mirrors the C-side w_node_field_store hook.
        parts << "\n  " + t + ".fz = call i64 @w_ast_freeze_if_array(i64 " + inst[:args][2] + ")"
        parts << "\n  store i64 " + t + ".fz, ptr " + t + ".gep, align 8"
        parts << "\n  " + t + " = add i64 " + t + ".fz, 0"
      return parts.to_s()
    args_str = render_call_args(inst[:args], inst[:arg_types])
    base = inst[:temp] + " = " + call_prefix(inst) + " i64 @" + inst[:name] + "(" + args_str + ")" + known_call_range_metadata_suffix(inst, "i64")
    if inst[:src_line] != nil && inst[:loc_site_id] != nil
      ret_lbl = "csd." + inst[:loc_site_id].to_s() + ".ret"
      base + "\n  br label %" + ret_lbl + "\n" + ret_lbl + ":"
    else
      base
  when :call_direct_i128
    args_str = render_call_args(inst[:args], inst[:arg_types])
    inst[:temp] + " = " + call_prefix(inst) + " i128 @" + inst[:name] + "(" + args_str + ")"
  when :call_direct_i64_ptr1
    inst[:temp] + " = " + call_prefix(inst) + " i64 @" + inst[:name] + "(ptr " + inst[:arg] + ")"

  # Phase 5g (post-Phase-6h): load a compile-time SmallArray constant.
  # The named global is a private LLVM constant emitted at module scope
  # (see the small-array-consts emission pass; align 16). W_SUBTAG_SMALL_
  # ARRAY = 9, so the box is `(ptr & ~0xF) | 9`. Because the global is
  # 16-byte aligned the low nibble is already zero and a plain `or 9`
  # suffices.
  when :small_array_const_load
    inst[:temp] + ".raw = ptrtoint ptr " + inst[:const_name] + " to i64\n  " + inst[:temp] + " = or i64 " + inst[:temp] + ".raw, 9"

  # Phase 6d (post-Phase-6h): allocate a SmallArray on the stack via
  # LLVM `alloca`. `total_bytes` is the WSmallArray header (2) + payload
  # bytes for the literal's ebits and size. The lowering follows up with
  # a ptrtoint and a call to w_small_array_init to stamp the header and
  # apply the W_SUBTAG_SMALL_ARRAY box. align 16 keeps the low nibble
  # clear so the runtime's box can OR the subtag in safely.
  when :small_array_alloca
    inst[:temp_ptr] + " = alloca \[" + inst[:total_bytes].to_s() + " x i8\], align 16"
  when :call_direct_void
    args_str = render_call_args(inst[:args], inst[:arg_types])
    base = call_prefix(inst) + " void @" + inst[:name] + "(" + args_str + ")"
    if inst[:src_line] != nil && inst[:loc_site_id] != nil
      ret_lbl = "csd." + inst[:loc_site_id].to_s() + ".ret"
      base + "\n  br label %" + ret_lbl + "\n" + ret_lbl + ":"
    else
      base

  # Source-loc hook fired before noreturn Tungsten calls (w_raise).
  # Writes (file, line, col) to thread-locals so the error formatter
  # recovers precise location even when the side-table misses.
  when :call_loc_set_col
    used_ptr_ids[inst[:file_str_id]] = true
    lbr = "\["
    rbr = "]"
    bl = inst[:file_byte_len].to_s()
    inst[:temp_ptr] + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + inst[:file_str_id].to_s() + ", i32 0, i32 0\n  call void @__w_loc_set_col(ptr " + inst[:temp_ptr] + ", i32 " + inst[:line].to_s() + ", i32 " + inst[:col].to_s() + ")"
  when :call_direct_void_ptr1
    call_prefix(inst) + " void @" + inst[:name] + "(ptr " + inst[:arg] + ")"
  when :call_direct_ptr
    args_str = render_call_args(inst[:args], inst[:arg_types])
    inst[:temp] + " = " + call_prefix(inst) + " ptr @" + inst[:name] + "(" + args_str + ")"

  # Call-site reuse allocation — per-site thread-local slot, reused across
  # calls. First call allocates and stores in the slot; subsequent calls
  # reset length and return the cached buffer. Zero malloc steady-state.
  when :call_reuse_or_new_array
    inst[:temp] + " = call i64 @w_array_reuse_or_new_empty(ptr @" + inst[:slot] + ")"
  when :call_reuse_or_new_hash
    inst[:temp] + " = call i64 @w_hash_reuse_or_new(ptr @" + inst[:slot] + ")"
  when :call_reuse_or_new_typed
    inst[:temp] + " = call i64 @w_array_reuse_or_new(ptr @" + inst[:slot] + ", i64 " + inst[:bits].to_s() + ", i64 " + inst[:cap] + ")"
  when :call_fused_out_reuse
    inst[:temp] + " = call i64 @w_fused_out_reuse_or_new(ptr @" + inst[:slot] + ", i64 " + inst[:bits].to_s() + ", i64 " + inst[:cap] + ")"
  when :call_reuse_or_new_strbuf
    inst[:temp] + " = call i64 @w_strbuf_reuse_or_new(ptr @" + inst[:slot] + ", i64 " + inst[:cap] + ")"
  when :call_reuse_and_drain_or_new_hash
    inst[:temp] + " = call i64 @w_hash_reuse_and_drain_or_new(ptr @" + inst[:slot] + ")"

  # Recycle pool allocation (## recycle): pop from thread-local pool or alloc.
  when :call_recycle_or_new_array
    inst[:temp] + " = call i64 @w_array_recycle_or_new_empty()"
  when :call_recycle_or_new_hash
    inst[:temp] + " = call i64 @w_hash_recycle_or_new()"
  when :call_recycle_or_new_typed
    inst[:temp] + " = call i64 @w_array_recycle_or_new(i64 " + inst[:bits].to_s() + ", i64 " + inst[:cap] + ")"
  when :call_recycle_or_new_strbuf
    inst[:temp] + " = call i64 @w_strbuf_recycle_or_new(i64 " + inst[:cap] + ")"

  # Recycle return-to-pool (emitted at scope exit for ## recycle vars).
  when :call_recycle_array
    "call void @w_array_recycle_public(i64 " + inst[:value] + ")"
  when :call_recycle_hash
    "call void @w_hash_recycle(i64 " + inst[:value] + ")"
  when :call_recycle_typed
    "call void @w_array_recycle(i64 " + inst[:value] + ")"
  when :call_recycle_strbuf
    "call void @w_strbuf_recycle(i64 " + inst[:value] + ")"

  # Cleanup stack push/pop for exception-safe recycle. Push after alloc,
  # pop just before the normal-path recycle fires. On w_raise, any entries
  # above the enclosing exception frame's saved cleanup_depth are invoked.
  when :cleanup_push_array
    "call void @w_cleanup_push(i64 " + inst[:value] + ", ptr @w_array_recycle_public)"
  when :cleanup_push_hash
    "call void @w_cleanup_push(i64 " + inst[:value] + ", ptr @w_hash_recycle)"
  when :cleanup_push_typed
    "call void @w_cleanup_push(i64 " + inst[:value] + ", ptr @w_array_recycle)"
  when :cleanup_push_strbuf
    "call void @w_cleanup_push(i64 " + inst[:value] + ", ptr @w_strbuf_recycle)"
  when :cleanup_pop
    "call void @w_cleanup_pop()"

  # Exception handling
  when :setjmp
    inst[:temp] + " = call i32 @setjmp(ptr " + inst[:buf] + ")"
  when :icmp_eq_i32
    inst[:temp] + " = icmp eq i32 " + inst[:lhs] + ", " + inst[:rhs]

  # Method dispatch (dynamic) — inline-cached via w_method_call_cached.
  # When the call carries source-loc info, split the basic block so the
  # return address is addressable via blockaddress(@fn, %cs.N.ret). Same
  # pattern the overflow-check ops use (see :add_i48_checked).
  when :call_method_i64
    argc = inst[:args].size()
    ic_ptr = inst[:temp] + ".ic"
    ic_id = inst[:ic_id].to_s()
    ic_gep = ic_ptr + " = getelementptr inbounds \[24 x i8], ptr @.ic, i64 " + ic_id + "\n  "
    ic_arg = ", ptr " + ic_ptr
    name_val = inst[:method_name_val]
    parts = StringBuffer(128 + argc * 64)
    parts << ic_gep
    # `notail` prevents LLVM from collapsing the call+ret pair into a tail
    # call when we need a real return address for the call-site lookup.
    # Without this, -O3 converts `call + br + ret` into a `b` (unconditional
    # branch) and the block-address we emit into @__w_call_site never matches
    # any PC captured by `backtrace()`.
    call_keyword = "call"
    if inst[:src_line] != nil
      call_keyword = "notail call"
    if argc == 0
      parts << inst[:temp] + " = " + call_keyword + " i64 @w_method_call_cached_0(i64 " + inst[:receiver] + ", i64 " + name_val + ic_arg + ")"
    elsif scalar_source_one_call?(inst)
      parts << inst[:temp] + " = " + call_keyword + " i64 @w_method_call_cached_1(i64 " + inst[:receiver] + ", i64 " + name_val + ", i64 " + inst[:args][0] + ic_arg + ")"
    else
      stack_arr = "%__mcall_args"
      i = 0
      while i < argc
        if i == 0
          slot = stack_arr
        else
          slot = inst[:temp_args_val] + "." + i.to_s()
          parts << slot + " = getelementptr inbounds i64, ptr " + stack_arr + ", i32 " + i.to_s() + "\n  "
        parts << "store i64 " + inst[:args][i] + ", ptr " + slot + ", align 8\n  "
        i += 1
      parts << inst[:temp] + " = " + call_keyword + " i64 @w_method_call_cached(i64 " + inst[:receiver] + ", i64 " + name_val + ", ptr " + stack_arr + ", i32 " + argc.to_s() + ic_arg + ")"
    if inst[:src_line] != nil
      ret_lbl = "cs." + ic_id + ".ret"
      parts << "\n  br label %"
      parts << ret_lbl
      parts << "\n"
      parts << ret_lbl
      parts << ":"
    parts.to_s()

  # Control flow
  when :br
    "br label %" + inst[:label]
  when :cond_br
    "br i1 " + inst[:cond] + ", label %" + inst[:then_label] + ", label %" + inst[:else_label]
  when :switch_i64
    cases = inst[:cases]
    is_symbol = inst[:is_symbol]
    out = StringBuffer(96 + cases.size() * 48)
    out << "switch i64 " + inst[:value] + ", label %" + inst[:default_label] + " \[\n"
    i = 0
    while i < cases.size()
      c = cases[i]
      # Case key resolution: cases with :string_id are medium-length
      # (6-61 byte) symbol or string arms whose slab WValue isn't
      # known until build_string_wvalues assigns the slot. Resolve
      # via string_wvs at emit time. For symbol switches, OR in the
      # `| 1` symbol bit; for string switches, keep the bare slab
      # WValue. SSO-5 keys already have the symbol bit (or not)
      # baked into their literal value at lowering time.
      key_text = nil
      sid = c[:string_id]
      if sid != nil
        swv = nil
        if string_wvs != nil
          swv = string_wvs[sid]
        if swv == nil
          # Heap-mode string (>61 bytes): WValue isn't compile-time
          # known. The case lowering's guard should have rejected
          # this; if we reach here it's a bug — bail to a value
          # that will never match the subject.
          key_text = "0"
        else
          if is_symbol == true
            key_text = llvm_wvalue_literal(swv + 1)
          else
            key_text = llvm_wvalue_literal(swv)
      else
        key_text = c[:value].to_s()
      out << "    i64 " + key_text + ", label %" + c[:label] + "\n"
      i += 1
    out << "  ]"
    out.to_s()
  when :ret_i64
    "ret i64 " + inst[:value]
  when :ret_i32
    "ret i32 " + inst[:value]
  when :ret_void
    "ret void"
  when :unreachable
    "unreachable"

  # Phi
  when :phi_i1
    lbr = "\["
    rbr = "]"
    a_label = redirect_phi_label(inst[:a_label], phi_label_redirects)
    b_label = redirect_phi_label(inst[:b_label], phi_label_redirects)
    inst[:temp] + " = phi i1 " + lbr + " " + inst[:a_value] + ", %" + a_label + " " + rbr + ", " + lbr + " " + inst[:b_value] + ", %" + b_label + " " + rbr
  when :phi_i64
    lbr = "\["
    rbr = "]"
    a_label = redirect_phi_label(inst[:a_label], phi_label_redirects)
    b_label = redirect_phi_label(inst[:b_label], phi_label_redirects)
    inst[:temp] + " = phi i64 " + lbr + " " + inst[:a_value] + ", %" + a_label + " " + rbr + ", " + lbr + " " + inst[:b_value] + ", %" + b_label + " " + rbr

  # Argv init (main preamble)
  when :argv_init
    "call void @w_argv_init(i32 %argc, ptr %argv)"

  # I/O
  when :puts_i64
    if inst[:temp] != nil
      inst[:temp] + " = call i64 @w_puts(i64 " + inst[:value] + ")"
    else
      "call i64 @w_puts(i64 " + inst[:value] + ")"
  when :print_i64
    if inst[:temp] != nil
      inst[:temp] + " = call i64 @w_print(i64 " + inst[:value] + ")"
    else
      "call i64 @w_print(i64 " + inst[:value] + ")"

  # Memoization
  when :memo_init
    inst[:temp] + " = call ptr @w_memo_init(ptr null)"
  when :store_memo_ptr
    "store ptr " + inst[:value] + ", ptr @" + inst[:global]
  when :load_memo_ptr
    inst[:temp] + " = load ptr, ptr @" + inst[:global]
  when :memo_call0_i64
    inst[:temp] + " = call i64 @__w_memo_call0_i64(ptr " + inst[:table] + ", ptr @" + inst[:fn_name] + ")"
  when :memo_call1_i64
    inst[:temp] + " = call i64 @__w_memo_call1_i64(ptr " + inst[:table] + ", ptr @" + inst[:fn_name] + ", i64 " + inst[:args][0] + ")"
  when :memo_call2_i64
    inst[:temp] + " = call i64 @__w_memo_call2_i64(ptr " + inst[:table] + ", ptr @" + inst[:fn_name] + ", i64 " + inst[:args][0] + ", i64 " + inst[:args][1] + ")"

  # Classes
  when :class_new
    swv = nil
    if string_wvs != nil
      swv = string_wvs[inst[:name_str_id]]
    if swv != nil
      super_arg = nil
      if inst[:super_reg] != nil
        super_arg = inst[:super_reg]
      else
        super_arg = w_nil.to_s()
      inst[:temp] + " = call i64 @w_class_new_wv(i64 " + llvm_wvalue_literal(swv) + ", i64 " + super_arg + ")"
    else
      used_ptr_ids[inst[:name_str_id]] = true
      lbr = "\["
      rbr = "]"
      bl = inst[:name_byte_len].to_s()
      parts = StringBuffer(160)
      parts << inst[:temp] + ".ptr = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + inst[:name_str_id].to_s() + ", i32 0, i32 0\n  "
      parts << inst[:temp] + ".name = call i64 @w_string(ptr " + inst[:temp] + ".ptr)\n  "
      super_arg = nil
      if inst[:super_reg] != nil
        super_arg = inst[:super_reg]
      else
        super_arg = w_nil.to_s()
      parts << inst[:temp] + " = call i64 @w_class_new_wv(i64 " + inst[:temp] + ".name, i64 " + super_arg + ")"
      parts.to_s()
  when :class_store
    "store i64 " + inst[:value] + ", ptr @class." + inst[:class_name].gsub(":", "__")
  when :type_class_register
    "call void @w_type_class_register_wv(i32 " + inst[:dispatch_key].to_s() + ", i64 " + inst[:class_temp] + ")"
  when :node_kind_class_register
    "call void @w_node_kind_class_register_wv(i32 " + inst[:kind_id].to_s() + ", i64 " + inst[:class_temp] + ")"
  when :class_add_method
    swv = nil
    if string_wvs != nil
      swv = string_wvs[inst[:method_str_id]]
    if swv != nil
      "call void @w_class_add_method_wv(i64 " + inst[:class_temp] + ", i64 " + llvm_wvalue_literal(swv) + ", ptr @" + inst[:fn_name] + ", i32 " + inst[:arity].to_s() + ")"
    else
      used_ptr_ids[inst[:method_str_id]] = true
      lbr = "\["
      rbr = "]"
      bl = inst[:method_byte_len].to_s()
      parts = StringBuffer(160)
      parts << inst[:class_temp] + ".mname = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + inst[:method_str_id].to_s() + ", i32 0, i32 0\n  "
      parts << inst[:class_temp] + ".mname.wv = call i64 @w_string(ptr " + inst[:class_temp] + ".mname)\n  "
      parts << "call void @w_class_add_method_wv(i64 " + inst[:class_temp] + ", i64 " + inst[:class_temp] + ".mname.wv, ptr @" + inst[:fn_name] + ", i32 " + inst[:arity].to_s() + ")"
      parts.to_s()
  when :class_add_static_method
    swv = nil
    if string_wvs != nil
      swv = string_wvs[inst[:method_str_id]]
    if swv != nil
      "call void @w_class_add_static_method_wv(i64 " + inst[:class_temp] + ", i64 " + llvm_wvalue_literal(swv) + ", ptr @" + inst[:fn_name] + ", i32 " + inst[:arity].to_s() + ")"
    else
      used_ptr_ids[inst[:method_str_id]] = true
      lbr = "\["
      rbr = "]"
      bl = inst[:method_byte_len].to_s()
      parts = StringBuffer(160)
      parts << inst[:class_temp] + ".smname = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + inst[:method_str_id].to_s() + ", i32 0, i32 0\n  "
      parts << inst[:class_temp] + ".smname.wv = call i64 @w_string(ptr " + inst[:class_temp] + ".smname)\n  "
      parts << "call void @w_class_add_static_method_wv(i64 " + inst[:class_temp] + ", i64 " + inst[:class_temp] + ".smname.wv, ptr @" + inst[:fn_name] + ", i32 " + inst[:arity].to_s() + ")"
      parts.to_s()
  when :load_class
    inst[:temp] + " = load i64, ptr @class." + inst[:class_name].gsub(":", "__")
  when :store_global
    t = inst[:type]
    if t == nil
      t = "i64"
    "store " + t + " " + inst[:value] + ", ptr @global." + inst[:name]
  when :load_global
    t = inst[:type]
    if t == nil
      t = "i64"
    inst[:temp] + " = load " + t + ", ptr @global." + inst[:name]
  when :store_cvar
    "store i64 " + inst[:value] + ", ptr @cvar." + inst[:cvar_key].gsub(":", "__")
  when :load_cvar
    inst[:temp] + " = load i64, ptr @cvar." + inst[:cvar_key].gsub(":", "__")
  when :typed_array_get_inline
    # Inline typed array read: unmask → slots ptr (off 16) → start i32 (off 4) → GEP → load → ext
    # Phase 4 i32 demote moved offsets: slots 32→16, start 8→4. Start is now
    # i32 and gets sign-extended before being added to the unboxed index.
    # Offsets locked by _Static_assert in runtime.h.
    t = inst[:temp]
    s = inst[:s]
    arr = inst[:arr]
    idx = inst[:idx]
    idx_raw = inst[:idx_raw]
    bits = inst[:bits]
    if bits == nil
      bits = 64
    signed = inst[:signed]
    if signed == nil
      signed = true
    parts = StringBuffer(700)
    parts << s[0] + " = and i64 " + arr + ", -16\n  "               # unmask
    parts << s[1] + " = inttoptr i64 " + s[0] + " to ptr\n  "      # struct ptr
    parts << s[2] + " = getelementptr i8, ptr " + s[1] + ", i64 16\n  "  # &slots
    parts << s[3] + " = load ptr, ptr " + s[2] + ", align 8\n  "    # slots ptr — re-read each access: realloc (push/unshift past cap, clear) moves it, so NOT invariant
    parts << s[4] + " = getelementptr i8, ptr " + s[1] + ", i64 4\n  "  # &start
    parts << s[5] + ".raw32 = load i32, ptr " + s[4] + ", align 4\n  "  # start (i32) — re-read: shift/unshift move it, so NOT invariant
    parts << s[5] + " = sext i32 " + s[5] + ".raw32 to i64\n  "    # start (i64 for GEP arithmetic)
    if idx_raw == true
      # Raw index — use directly, fill unused scratch with dummy values
      parts << s[6] + " = add i64 0, 0\n  "
      parts << s[7] + " = add i64 0, 0\n  "
      parts << s[8] + " = add i64 " + s[5] + ", " + idx + "\n  "
    else
      parts << s[6] + " = shl i64 " + idx + ", 16\n  "
      parts << s[7] + " = ashr i64 " + s[6] + ", 16\n  "
      parts << s[8] + " = add i64 " + s[5] + ", " + s[7] + "\n  "
    if bits == 64
      parts << s[9] + " = getelementptr i64, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      parts << t + " = load i64, ptr " + s[9] + ", align 8"
    elsif bits == 32
      parts << s[9] + " = getelementptr i32, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i32, ptr " + s[9] + ", align 4\n  "
      if signed == true
        parts << t + " = sext i32 " + raw + " to i64"
      else
        parts << t + " = zext i32 " + raw + " to i64"
    elsif bits == 16
      parts << s[9] + " = getelementptr i16, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i16, ptr " + s[9] + ", align 2\n  "
      if signed == true
        parts << t + " = sext i16 " + raw + " to i64"
      else
        parts << t + " = zext i16 " + raw + " to i64"
    elsif bits == 8
      parts << s[9] + " = getelementptr i8, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i8, ptr " + s[9] + ", align 1\n  "
      if signed == true
        parts << t + " = sext i8 " + raw + " to i64"
      else
        parts << t + " = zext i8 " + raw + " to i64"
    elsif bits == 4
      byte_idx = t + ".byteidx"
      raw8 = t + ".raw8"
      raw64 = t + ".raw64"
      slot = t + ".slot"
      shift = t + ".shift"
      shifted = t + ".shifted"
      nibble = t + ".nibble"
      parts << byte_idx + " = lshr i64 " + s[8] + ", 1\n  "
      parts << s[9] + " = getelementptr i8, ptr " + s[3] + ", i64 " + byte_idx + "\n  "
      parts << raw8 + " = load i8, ptr " + s[9] + ", align 1\n  "
      parts << raw64 + " = zext i8 " + raw8 + " to i64\n  "
      parts << slot + " = and i64 " + s[8] + ", 1\n  "
      parts << shift + " = shl i64 " + slot + ", 2\n  "
      parts << shifted + " = lshr i64 " + raw64 + ", " + shift + "\n  "
      parts << nibble + " = and i64 " + shifted + ", 15\n  "
      if signed == true
        signbits = t + ".signbits"
        parts << signbits + " = shl i64 " + nibble + ", 60\n  "
        parts << t + " = ashr i64 " + signbits + ", 60"
      else
        parts << t + " = add i64 " + nibble + ", 0"
    else
      parts << s[9] + " = getelementptr i64, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      parts << t + " = load i64, ptr " + s[9] + ", align 8"
    parts.to_s()
  when :typed_array_set_inline
    # Inline typed array write: same Phase 4 i32-offset shift as get.
    t = inst[:temp]
    s = inst[:s]
    arr = inst[:arr]
    idx = inst[:idx]
    idx_raw = inst[:idx_raw]
    val = inst[:value]
    bits = inst[:bits]
    if bits == nil
      bits = 64
    parts = StringBuffer(700)
    parts << s[0] + " = and i64 " + arr + ", -16\n  "
    parts << s[1] + " = inttoptr i64 " + s[0] + " to ptr\n  "
    parts << s[2] + " = getelementptr i8, ptr " + s[1] + ", i64 16\n  "  # &slots (Phase 4: was 32)
    parts << s[3] + " = load ptr, ptr " + s[2] + ", align 8\n  "    # slots ptr — re-read each access: realloc (push/unshift past cap, clear) moves it, so NOT invariant
    parts << s[4] + " = getelementptr i8, ptr " + s[1] + ", i64 4\n  "   # &start (Phase 4: was 8)
    parts << s[5] + ".raw32 = load i32, ptr " + s[4] + ", align 4\n  "   # start (i32) — re-read: shift/unshift move it, so NOT invariant
    parts << s[5] + " = sext i32 " + s[5] + ".raw32 to i64\n  "
    if idx_raw == true
      parts << s[6] + " = add i64 0, 0\n  "
      parts << s[7] + " = add i64 " + idx + ", 0\n  "
      parts << s[8] + " = add i64 " + s[5] + ", " + idx + "\n  "
    else
      parts << s[6] + " = shl i64 " + idx + ", 16\n  "
      parts << s[7] + " = ashr i64 " + s[6] + ", 16\n  "
      parts << s[8] + " = add i64 " + s[5] + ", " + s[7] + "\n  "
    if bits == 64
      parts << s[9] + " = getelementptr i64, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      parts << "store i64 " + val + ", ptr " + s[9] + ", align 8\n  "
    elsif bits == 32
      parts << s[9] + " = getelementptr i32, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      tr = t + ".trunc"
      parts << tr + " = trunc i64 " + val + " to i32\n  "
      parts << "store i32 " + tr + ", ptr " + s[9] + ", align 4\n  "
    elsif bits == 16
      parts << s[9] + " = getelementptr i16, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      tr = t + ".trunc"
      parts << tr + " = trunc i64 " + val + " to i16\n  "
      parts << "store i16 " + tr + ", ptr " + s[9] + ", align 2\n  "
    elsif bits == 8
      parts << s[9] + " = getelementptr i8, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      tr = t + ".trunc"
      parts << tr + " = trunc i64 " + val + " to i8\n  "
      parts << "store i8 " + tr + ", ptr " + s[9] + ", align 1\n  "
    elsif bits == 4
      byte_idx = t + ".byteidx"
      raw8 = t + ".raw8"
      raw64 = t + ".raw64"
      slot = t + ".slot"
      shift = t + ".shift"
      mask = t + ".mask"
      clear_mask = t + ".clear_mask"
      cleared = t + ".cleared"
      nibble = t + ".nibble"
      shifted = t + ".shifted"
      merged = t + ".merged"
      tr = t + ".trunc"
      parts << byte_idx + " = lshr i64 " + s[8] + ", 1\n  "
      parts << s[9] + " = getelementptr i8, ptr " + s[3] + ", i64 " + byte_idx + "\n  "
      parts << raw8 + " = load i8, ptr " + s[9] + ", align 1\n  "
      parts << raw64 + " = zext i8 " + raw8 + " to i64\n  "
      parts << slot + " = and i64 " + s[8] + ", 1\n  "
      parts << shift + " = shl i64 " + slot + ", 2\n  "
      parts << mask + " = shl i64 15, " + shift + "\n  "
      parts << clear_mask + " = xor i64 " + mask + ", 255\n  "
      parts << cleared + " = and i64 " + raw64 + ", " + clear_mask + "\n  "
      parts << nibble + " = and i64 " + val + ", 15\n  "
      parts << shifted + " = shl i64 " + nibble + ", " + shift + "\n  "
      parts << merged + " = or i64 " + cleared + ", " + shifted + "\n  "
      parts << tr + " = trunc i64 " + merged + " to i8\n  "
      parts << "store i8 " + tr + ", ptr " + s[9] + ", align 1\n  "
    else
      parts << s[9] + " = getelementptr i64, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      parts << "store i64 " + val + ", ptr " + s[9] + ", align 8\n  "
    # No size-grow update: T[N] / Array.new constructors set size == cap
    # at allocation, and the inline `[]=` path is only emitted when the
    # store stays within that preallocated range.
    parts << t + " = add i64 " + val + ", 0"
    parts.to_s()

  # Fused inline compound op: `arr[i] = arr[i] OP X`. Emits one pointer
  # chain (untag, slots ptr, start) and one GEP, then load + op + store
  # in the slot's native width. Lifted from typed_array_set_inline; only
  # emitted for integer typed-arrays in widths 8/16/32/64.
  when :typed_array_compound_op_inline
    t = inst[:temp]
    s = inst[:s]
    arr = inst[:arr]
    idx = inst[:idx]
    idx_raw = inst[:idx_raw]
    val = inst[:value]
    compound_op = inst[:compound_op]
    bits = inst[:bits]
    if bits == nil
      bits = 64
    signed = inst[:signed]
    if signed == nil
      signed = false
    llvm_op = nil
    case compound_op
    when :PLUS
      llvm_op = "add"
    when :MINUS
      llvm_op = "sub"
    when :STAR
      llvm_op = "mul"
    when :PIPE
      llvm_op = "or"
    when :AMPERSAND
      llvm_op = "and"
    when :CARET
      llvm_op = "xor"
    when :LSHIFT
      llvm_op = "shl"
    when :RSHIFT
      if signed == true
        llvm_op = "ashr"
      else
        llvm_op = "lshr"
    parts = StringBuffer(700)
    parts << s[0] + " = and i64 " + arr + ", -16\n  "
    parts << s[1] + " = inttoptr i64 " + s[0] + " to ptr\n  "
    parts << s[2] + " = getelementptr i8, ptr " + s[1] + ", i64 16\n  "
    parts << s[3] + " = load ptr, ptr " + s[2] + ", align 8\n  "
    parts << s[4] + " = getelementptr i8, ptr " + s[1] + ", i64 4\n  "
    parts << s[5] + ".raw32 = load i32, ptr " + s[4] + ", align 4\n  "
    parts << s[5] + " = sext i32 " + s[5] + ".raw32 to i64\n  "
    if idx_raw == true
      parts << s[6] + " = add i64 0, 0\n  "
      parts << s[7] + " = add i64 0, 0\n  "
      parts << s[8] + " = add i64 " + s[5] + ", " + idx + "\n  "
    else
      parts << s[6] + " = shl i64 " + idx + ", 16\n  "
      parts << s[7] + " = ashr i64 " + s[6] + ", 16\n  "
      parts << s[8] + " = add i64 " + s[5] + ", " + s[7] + "\n  "
    if bits == 64
      parts << s[9] + " = getelementptr i64, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      parts << t + ".loaded = load i64, ptr " + s[9] + ", align 8\n  "
      parts << t + ".res = " + llvm_op + " i64 " + t + ".loaded, " + val + "\n  "
      parts << "store i64 " + t + ".res, ptr " + s[9] + ", align 8\n  "
      parts << t + " = add i64 " + t + ".res, 0"
    elsif bits == 32
      parts << s[9] + " = getelementptr i32, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      parts << t + ".loaded = load i32, ptr " + s[9] + ", align 4\n  "
      parts << t + ".v32 = trunc i64 " + val + " to i32\n  "
      parts << t + ".res32 = " + llvm_op + " i32 " + t + ".loaded, " + t + ".v32\n  "
      parts << "store i32 " + t + ".res32, ptr " + s[9] + ", align 4\n  "
      if signed == true
        parts << t + " = sext i32 " + t + ".res32 to i64"
      else
        parts << t + " = zext i32 " + t + ".res32 to i64"
    elsif bits == 16
      parts << s[9] + " = getelementptr i16, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      parts << t + ".loaded = load i16, ptr " + s[9] + ", align 2\n  "
      parts << t + ".v16 = trunc i64 " + val + " to i16\n  "
      parts << t + ".res16 = " + llvm_op + " i16 " + t + ".loaded, " + t + ".v16\n  "
      parts << "store i16 " + t + ".res16, ptr " + s[9] + ", align 2\n  "
      if signed == true
        parts << t + " = sext i16 " + t + ".res16 to i64"
      else
        parts << t + " = zext i16 " + t + ".res16 to i64"
    elsif bits == 8
      parts << s[9] + " = getelementptr i8, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      parts << t + ".loaded = load i8, ptr " + s[9] + ", align 1\n  "
      parts << t + ".v8 = trunc i64 " + val + " to i8\n  "
      parts << t + ".res8 = " + llvm_op + " i8 " + t + ".loaded, " + t + ".v8\n  "
      parts << "store i8 " + t + ".res8, ptr " + s[9] + ", align 1\n  "
      if signed == true
        parts << t + " = sext i8 " + t + ".res8 to i64"
      else
        parts << t + " = zext i8 " + t + ".res8 to i64"
    else
      parts << s[9] + " = getelementptr i64, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      parts << t + ".loaded = load i64, ptr " + s[9] + ", align 8\n  "
      parts << t + ".res = " + llvm_op + " i64 " + t + ".loaded, " + val + "\n  "
      parts << "store i64 " + t + ".res, ptr " + s[9] + ", align 8\n  "
      parts << t + " = add i64 " + t + ".res, 0"
    parts.to_s()

  # BigArray inline read. Layout differs from WArray: the boxed value is a
  # generic object whose C struct carries a type byte at offset 0, i64
  # start/size/cap fields, and slots at offset 32. No bounds check here:
  # this is the unchecked `[]` path, and lowered each supplies in-range indices.
  when :big_array_get_inline
    t = inst[:temp]
    s = inst[:s]
    arr = inst[:arr]
    idx = inst[:idx]
    idx_raw = inst[:idx_raw]
    bits = inst[:bits]
    if bits == nil
      bits = 64
    signed = inst[:signed]
    if signed == nil
      signed = true
    parts = StringBuffer(700)
    parts << s[0] + " = and i64 " + arr + ", -16\n  "                # unmask
    parts << s[1] + " = inttoptr i64 " + s[0] + " to ptr\n  "       # WBigArray*
    parts << s[2] + " = getelementptr i8, ptr " + s[1] + ", i64 32\n  "
    parts << s[3] + " = load ptr, ptr " + s[2] + ", align 8\n  "     # slots
    parts << s[4] + " = getelementptr i8, ptr " + s[1] + ", i64 8\n  "
    parts << s[5] + " = load i64, ptr " + s[4] + ", align 8\n  "     # start
    if idx_raw == true
      parts << s[6] + " = add i64 " + s[5] + ", " + idx + "\n  "
    else
      parts << s[6] + ".sl = shl i64 " + idx + ", 16\n  "
      parts << s[6] + ".as = ashr i64 " + s[6] + ".sl, 16\n  "
      parts << s[6] + " = add i64 " + s[5] + ", " + s[6] + ".as\n  "
    if bits == 64
      parts << s[7] + " = getelementptr i64, ptr " + s[3] + ", i64 " + s[6] + "\n  "
      parts << t + " = load i64, ptr " + s[7] + ", align 8"
    elsif bits == 32
      parts << s[7] + " = getelementptr i32, ptr " + s[3] + ", i64 " + s[6] + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i32, ptr " + s[7] + ", align 4\n  "
      if signed == true
        parts << t + " = sext i32 " + raw + " to i64"
      else
        parts << t + " = zext i32 " + raw + " to i64"
    elsif bits == 16
      parts << s[7] + " = getelementptr i16, ptr " + s[3] + ", i64 " + s[6] + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i16, ptr " + s[7] + ", align 2\n  "
      if signed == true
        parts << t + " = sext i16 " + raw + " to i64"
      else
        parts << t + " = zext i16 " + raw + " to i64"
    elsif bits == 8
      parts << s[7] + " = getelementptr i8, ptr " + s[3] + ", i64 " + s[6] + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i8, ptr " + s[7] + ", align 1\n  "
      if signed == true
        parts << t + " = sext i8 " + raw + " to i64"
      else
        parts << t + " = zext i8 " + raw + " to i64"
    elsif bits == 4
      byte_idx = t + ".byteidx"
      raw8 = t + ".raw8"
      raw64 = t + ".raw64"
      slot = t + ".slot"
      shift = t + ".shift"
      shifted = t + ".shifted"
      nibble = t + ".nibble"
      parts << byte_idx + " = lshr i64 " + s[6] + ", 1\n  "
      parts << s[7] + " = getelementptr i8, ptr " + s[3] + ", i64 " + byte_idx + "\n  "
      parts << raw8 + " = load i8, ptr " + s[7] + ", align 1\n  "
      parts << raw64 + " = zext i8 " + raw8 + " to i64\n  "
      parts << slot + " = and i64 " + s[6] + ", 1\n  "
      parts << shift + " = shl i64 " + slot + ", 2\n  "
      parts << shifted + " = lshr i64 " + raw64 + ", " + shift + "\n  "
      parts << nibble + " = and i64 " + shifted + ", 15\n  "
      if signed == true
        signbits = t + ".signbits"
        parts << signbits + " = shl i64 " + nibble + ", 60\n  "
        parts << t + " = ashr i64 " + signbits + ", 60"
      else
        parts << t + " = add i64 " + nibble + ", 0"
    else
      parts << s[7] + " = getelementptr i64, ptr " + s[3] + ", i64 " + s[6] + "\n  "
      parts << t + " = load i64, ptr " + s[7] + ", align 8"
    parts.to_s()

  # Phase 6f (post-Phase-6h): SmallArray inline read. Layout differs
  # from WArray — slots are INLINE at offset 2 (header is just ebits +
  # size), no separate ptr load, no `start` shift. The index is kept as
  # a full i64 for the GEP: a `trunc … to i8` here silently maps any
  # index 128..255 to a NEGATIVE offset (signed i8 wrap), addressing
  # BEFORE the struct. No bounds check — caller proved [0, size).
  when :small_array_get_inline
    t = inst[:temp]
    s = inst[:s]
    arr = inst[:arr]
    idx = inst[:idx]
    idx_raw = inst[:idx_raw]
    bits = inst[:bits]
    if bits == nil
      bits = 8
    signed = inst[:signed]
    if signed == nil
      signed = false
    parts = StringBuffer(400)
    parts << s[0] + " = and i64 " + arr + ", -16\n  "                  # unmask
    parts << s[1] + " = inttoptr i64 " + s[0] + " to ptr\n  "          # struct ptr
    parts << s[2] + " = getelementptr i8, ptr " + s[1] + ", i64 2\n  " # &slots[0]
    if idx_raw == true
      parts << s[3] + " = add i64 " + idx + ", 0\n  "                  # raw index (i64)
    else
      parts << s[3] + ".sl = shl i64 " + idx + ", 16\n  "
      parts << s[3] + " = ashr i64 " + s[3] + ".sl, 16\n  "            # unbox → i64
    if bits == 64
      parts << s[4] + " = getelementptr i64, ptr " + s[2] + ", i64 " + s[3] + "\n  "
      parts << t + " = load i64, ptr " + s[4] + ", align 1"
    elsif bits == 32
      parts << s[4] + " = getelementptr i32, ptr " + s[2] + ", i64 " + s[3] + "\n  "
      parts << t + ".raw = load i32, ptr " + s[4] + ", align 1\n  "
      if signed == true
        parts << t + " = sext i32 " + t + ".raw to i64"
      else
        parts << t + " = zext i32 " + t + ".raw to i64"
    elsif bits == 16
      parts << s[4] + " = getelementptr i16, ptr " + s[2] + ", i64 " + s[3] + "\n  "
      parts << t + ".raw = load i16, ptr " + s[4] + ", align 1\n  "
      if signed == true
        parts << t + " = sext i16 " + t + ".raw to i64"
      else
        parts << t + " = zext i16 " + t + ".raw to i64"
    elsif bits == 8
      parts << s[4] + " = getelementptr i8, ptr " + s[2] + ", i64 " + s[3] + "\n  "
      parts << t + ".raw = load i8, ptr " + s[4] + ", align 1\n  "
      if signed == true
        parts << t + " = sext i8 " + t + ".raw to i64"
      else
        parts << t + " = zext i8 " + t + ".raw to i64"
    elsif bits == 4
      # 4-bit packed: byte_idx = idx >> 1; nibble at slot bit 0/1.
      byte_idx = t + ".byteidx"
      raw8 = t + ".raw8"
      raw64 = t + ".raw64"
      slot = t + ".slot"
      shift = t + ".shift"
      shifted = t + ".shifted"
      nibble = t + ".nibble"
      parts << byte_idx + " = lshr i64 " + s[3] + ", 1\n  "
      parts << s[4] + " = getelementptr i8, ptr " + s[2] + ", i64 " + byte_idx + "\n  "
      parts << raw8 + " = load i8, ptr " + s[4] + ", align 1\n  "
      parts << raw64 + " = zext i8 " + raw8 + " to i64\n  "
      parts << slot + " = and i64 " + s[3] + ", 1\n  "
      parts << shift + " = shl i64 " + slot + ", 2\n  "
      parts << shifted + " = lshr i64 " + raw64 + ", " + shift + "\n  "
      parts << nibble + " = and i64 " + shifted + ", 15\n  "
      if signed == true
        signbits = t + ".signbits"
        parts << signbits + " = shl i64 " + nibble + ", 60\n  "
        parts << t + " = ashr i64 " + signbits + ", 60"
      else
        parts << t + " = add i64 " + nibble + ", 0"
    else
      parts << s[4] + " = getelementptr i64, ptr " + s[2] + ", i64 " + s[3] + "\n  "
      parts << t + " = load i64, ptr " + s[4] + ", align 1"
    parts.to_s()

  # Phase 6f: SmallArray inline write — same layout shortcuts as get.
  # Index kept as a full i64 (see get: an i8 trunc would address before
  # the struct for indices 128..255). No size update (SmallArray is
  # fixed-size by construction).
  when :small_array_set_inline
    t = inst[:temp]
    s = inst[:s]
    arr = inst[:arr]
    idx = inst[:idx]
    idx_raw = inst[:idx_raw]
    val = inst[:value]
    bits = inst[:bits]
    if bits == nil
      bits = 8
    parts = StringBuffer(400)
    parts << s[0] + " = and i64 " + arr + ", -16\n  "
    parts << s[1] + " = inttoptr i64 " + s[0] + " to ptr\n  "
    parts << s[2] + " = getelementptr i8, ptr " + s[1] + ", i64 2\n  "
    if idx_raw == true
      parts << s[3] + " = add i64 " + idx + ", 0\n  "
    else
      parts << s[3] + ".sl = shl i64 " + idx + ", 16\n  "
      parts << s[3] + " = ashr i64 " + s[3] + ".sl, 16\n  "
    if bits == 64
      parts << s[4] + " = getelementptr i64, ptr " + s[2] + ", i64 " + s[3] + "\n  "
      parts << "store i64 " + val + ", ptr " + s[4] + ", align 1\n  "
    elsif bits == 32
      tr = t + ".tr"
      parts << s[4] + " = getelementptr i32, ptr " + s[2] + ", i64 " + s[3] + "\n  "
      parts << tr + " = trunc i64 " + val + " to i32\n  "
      parts << "store i32 " + tr + ", ptr " + s[4] + ", align 1\n  "
    elsif bits == 16
      tr = t + ".tr"
      parts << s[4] + " = getelementptr i16, ptr " + s[2] + ", i64 " + s[3] + "\n  "
      parts << tr + " = trunc i64 " + val + " to i16\n  "
      parts << "store i16 " + tr + ", ptr " + s[4] + ", align 1\n  "
    elsif bits == 8
      tr = t + ".tr"
      parts << s[4] + " = getelementptr i8, ptr " + s[2] + ", i64 " + s[3] + "\n  "
      parts << tr + " = trunc i64 " + val + " to i8\n  "
      parts << "store i8 " + tr + ", ptr " + s[4] + ", align 1\n  "
    elsif bits == 4
      # 4-bit pack: read-modify-write of the nibble at slot bit 0/1.
      byte_idx = t + ".byteidx"
      raw8 = t + ".raw8"
      raw64 = t + ".raw64"
      slot = t + ".slot"
      shift = t + ".shift"
      mask = t + ".mask"
      clear_mask = t + ".clear"
      cleared = t + ".cleared"
      nibble = t + ".nibble"
      shifted = t + ".shifted"
      merged = t + ".merged"
      tr = t + ".tr"
      parts << byte_idx + " = lshr i64 " + s[3] + ", 1\n  "
      parts << s[4] + " = getelementptr i8, ptr " + s[2] + ", i64 " + byte_idx + "\n  "
      parts << raw8 + " = load i8, ptr " + s[4] + ", align 1\n  "
      parts << raw64 + " = zext i8 " + raw8 + " to i64\n  "
      parts << slot + " = and i64 " + s[3] + ", 1\n  "
      parts << shift + " = shl i64 " + slot + ", 2\n  "
      parts << mask + " = shl i64 15, " + shift + "\n  "
      parts << clear_mask + " = xor i64 " + mask + ", 255\n  "
      parts << cleared + " = and i64 " + raw64 + ", " + clear_mask + "\n  "
      parts << nibble + " = and i64 " + val + ", 15\n  "
      parts << shifted + " = shl i64 " + nibble + ", " + shift + "\n  "
      parts << merged + " = or i64 " + cleared + ", " + shifted + "\n  "
      parts << tr + " = trunc i64 " + merged + " to i8\n  "
      parts << "store i8 " + tr + ", ptr " + s[4] + ", align 1\n  "
    else
      parts << s[4] + " = getelementptr i64, ptr " + s[2] + ", i8 " + s[3] + "\n  "
      parts << "store i64 " + val + ", ptr " + s[4] + ", align 1\n  "
    # Define result so SSA refs to t are valid.
    parts << t + " = add i64 " + val + ", 0"
    parts.to_s()

  when :array_get_inline
    # Inline WArray read: unmask → slots (off 16) → start i32 (off 4) → unbox idx → GEP → load
    # Offsets locked by _Static_assert in runtime.h (Phase 2 rename: items → slots).
    t = inst[:temp]
    s = inst[:s]
    arr = inst[:arr]
    idx = inst[:idx]
    parts = StringBuffer(500)
    parts << s[0] + " = and i64 " + arr + ", -16\n  "               # unmask
    parts << s[1] + " = inttoptr i64 " + s[0] + " to ptr\n  "      # struct ptr
    parts << s[2] + ".field = getelementptr i8, ptr " + s[1] + ", i64 16\n  "  # &slots
    parts << s[2] + " = load ptr, ptr " + s[2] + ".field, align 8\n  "   # slots ptr
    parts << s[3] + " = getelementptr i8, ptr " + s[1] + ", i64 4\n  "  # &start
    parts << s[4] + " = load i32, ptr " + s[3] + ", align 4\n  "   # start (i32)
    parts << s[5] + " = sext i32 " + s[4] + " to i64\n  "          # start (i64)
    parts << s[6] + " = shl i64 " + idx + ", 16\n  "                # unbox idx
    parts << s[7] + " = ashr i64 " + s[6] + ", 16\n  "              # sign-extend
    parts << s[8] + " = add i64 " + s[5] + ", " + s[7] + "\n  "   # effective idx
    parts << s[9] + " = getelementptr i64, ptr " + s[2] + ", i64 " + s[8] + "\n  "  # elem ptr
    parts << t + " = load i64, ptr " + s[9] + ", align 8"           # load element
    parts.to_s()
  when :builtin_class_init
    swv = nil
    if string_wvs != nil
      swv = string_wvs[inst[:name_str_id]]
    if swv != nil
      cn = inst[:class_name].gsub(":", "__")
      parts = StringBuffer(128)
      parts << "%" + cn + ".cls = call i64 @w_class_new_wv(i64 " + llvm_wvalue_literal(swv) + ", i64 " + w_nil.to_s() + ")\n  "
      parts << "store i64 %" + cn + ".cls, ptr @class." + cn
      parts.to_s()
    else
      used_ptr_ids[inst[:name_str_id]] = true
      lbr = "\["
      rbr = "]"
      bl = inst[:name_byte_len].to_s()
      cn = inst[:class_name].gsub(":", "__")
      parts = StringBuffer(192)
      parts << "%" + cn + ".ptr = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + inst[:name_str_id].to_s() + ", i32 0, i32 0\n  "
      parts << "%" + cn + ".name = call i64 @w_string(ptr %" + cn + ".ptr)\n  "
      parts << "%" + cn + ".cls = call i64 @w_class_new_wv(i64 %" + cn + ".name, i64 " + w_nil.to_s() + ")\n  "
      parts << "store i64 %" + cn + ".cls, ptr @class." + cn
      parts.to_s()

  # Instance variables
  when :ivar_get
    swv = nil
    if string_wvs != nil
      swv = string_wvs[inst[:str_id]]
    if swv != nil
      inst[:temp] + " = call i64 @w_ivar_get_wv(i64 " + inst[:self_reg] + ", i64 " + llvm_wvalue_literal(swv) + ")"
    else
      used_ptr_ids[inst[:str_id]] = true
      lbr = "\["
      rbr = "]"
      bl = inst[:byte_len].to_s()
      parts = StringBuffer(160)
      parts << inst[:temp_ptr] + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + inst[:str_id].to_s() + ", i32 0, i32 0\n  "
      parts << inst[:temp_ptr] + ".wv = call i64 @w_string(ptr " + inst[:temp_ptr] + ")\n  "
      parts << inst[:temp] + " = call i64 @w_ivar_get_wv(i64 " + inst[:self_reg] + ", i64 " + inst[:temp_ptr] + ".wv)"
      parts.to_s()
  when :ivar_set
    swv = nil
    if string_wvs != nil
      swv = string_wvs[inst[:str_id]]
    if swv != nil
      inst[:temp] + " = call i64 @w_ivar_set_wv(i64 " + inst[:self_reg] + ", i64 " + llvm_wvalue_literal(swv) + ", i64 " + inst[:value] + ")"
    else
      used_ptr_ids[inst[:str_id]] = true
      lbr = "\["
      rbr = "]"
      bl = inst[:byte_len].to_s()
      parts = StringBuffer(160)
      parts << inst[:temp_ptr] + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + inst[:str_id].to_s() + ", i32 0, i32 0\n  "
      parts << inst[:temp_ptr] + ".wv = call i64 @w_string(ptr " + inst[:temp_ptr] + ")\n  "
      parts << inst[:temp] + " = call i64 @w_ivar_set_wv(i64 " + inst[:self_reg] + ", i64 " + inst[:temp_ptr] + ".wv, i64 " + inst[:value] + ")"
      parts.to_s()
  when :ivar_get_idx
    byte_offset = (8 + inst[:offset] * 8).to_s
    t = inst[:temp]
    sr = inst[:self_reg]
    parts = StringBuffer(160)
    parts << t + ".raw = and i64 " + sr + ", -16\n  "
    parts << t + ".ptr = inttoptr i64 " + t + ".raw to ptr\n  "
    parts << t + ".gep = getelementptr i8, ptr " + t + ".ptr, i64 " + byte_offset + "\n  "
    parts << t + " = load i64, ptr " + t + ".gep, align 8"
    parts.to_s()
  when :slab_node_get_idx
    # PR #2 Phase 2: read one slab slot from an AST node.
    # Unused — the active slab field path is the :call_direct_i64
    # branch above that special-cases inst[:name] == "w_node_field_load".
    inst[:temp] + " = call i64 @w_node_field_load(i64 " + inst[:node] + ", i64 " + inst[:offset].to_s() + ")"
  when :slab_node_set_idx
    # PR #2 Phase 2: write one slab slot. Unused; see :slab_node_get_idx
    # note above.
    t = inst[:temp]
    parts = StringBuffer(192)
    parts << "call void @w_node_field_store(i64 " + inst[:node] + ", i64 " + inst[:offset].to_s() + ", i64 " + inst[:value] + ")\n  "
    parts << t + " = add i64 " + inst[:value] + ", 0"
    parts.to_s()
  when :ivar_set_idx
    byte_offset = (8 + inst[:offset] * 8).to_s()
    t = inst[:temp]
    sr = inst[:self_reg]
    parts = StringBuffer(192)
    parts << t + ".raw = and i64 " + sr + ", -16\n  "
    parts << t + ".ptr = inttoptr i64 " + t + ".raw to ptr\n  "
    parts << t + ".gep = getelementptr i8, ptr " + t + ".ptr, i64 " + byte_offset + "\n  "
    parts << "store i64 " + inst[:value] + ", ptr " + t + ".gep, align 8\n  "
    parts << t + " = add i64 " + inst[:value] + ", 0"
    parts.to_s()
  when :class_add_ivar
    swv = nil
    if string_wvs != nil
      swv = string_wvs[inst[:ivar_str_id]]
    if swv != nil
      "call i32 @w_class_add_ivar_wv(i64 " + inst[:class_temp] + ", i64 " + llvm_wvalue_literal(swv) + ")"
    else
      used_ptr_ids[inst[:ivar_str_id]] = true
      lbr = "\["
      rbr = "]"
      bl = inst[:ivar_byte_len].to_s()
      ivar_ptr = inst[:class_temp] + ".ivar_name"
      parts = StringBuffer(160)
      parts << ivar_ptr + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + inst[:ivar_str_id].to_s() + ", i32 0, i32 0\n  "
      parts << ivar_ptr + ".wv = call i64 @w_string(ptr " + ivar_ptr + ")\n  "
      parts << "call i32 @w_class_add_ivar_wv(i64 " + inst[:class_temp] + ", i64 " + ivar_ptr + ".wv)"
      parts.to_s()

  # Closures
  when :null_ptr
    inst[:temp] + " = inttoptr i64 0 to ptr"
  when :ptr_to_i64
    inst[:temp] + " = ptrtoint ptr " + inst[:value] + " to i64"
  when :i64_to_ptr
    inst[:temp] + " = inttoptr i64 " + inst[:value] + " to ptr"
  when :closure_new
    inst[:temp] + " = call i64 @w_closure_new(ptr @" + inst[:fn_name] + ", ptr " + inst[:captures_ptr] + ", i32 " + inst[:capture_count].to_s() + ")"
  when :alloca_array
    lbr = "\["
    rbr = "]"
    inst[:ptr] + " = alloca " + lbr + inst[:count].to_s() + " x i64" + rbr + ", align 8"
  when :gep_array
    lbr = "\["
    rbr = "]"
    inst[:temp] + " = getelementptr inbounds " + lbr + inst[:count].to_s() + " x i64" + rbr + ", ptr " + inst[:base] + ", i32 0, i32 " + inst[:index].to_s()
  when :store_ptr
    "store i64 " + inst[:value] + ", ptr " + inst[:dest] + ", align 8"
  when :load_ptr
    inst[:temp] + " = load i64, ptr " + inst[:ptr] + ", align 8"

  # SSA phi with N inputs (from mem2reg)
  when :phi_ssa
    lbr = "\["
    rbr = "]"
    incoming = inst[:incoming]
    parts = StringBuffer(incoming.size() * 32 + 24)
    parts << inst[:temp] + " = phi i64 "
    ii = 0
    while ii < incoming.size()
      if ii > 0
        parts << ", "
      label = redirect_phi_label(incoming[ii + 1], phi_label_redirects)
      parts << lbr + " " + incoming[ii] + ", %" + label + " " + rbr
      ii += 2
    parts.to_s()

  # Free a non-escaped heap value at scope exit
  when :free_value
    "call void @w_value_free(i64 " + inst[:value] + ")"

  # Scope markers — pseudo-instructions for ownership analysis, no codegen
  when :scope_push, :scope_pop
    "; scope " + op.to_s()

  else
    "; UNKNOWN WIRE OP: " + op.to_s()

# -- Helpers --

-> render_call_args(args, arg_types = nil)
  parts = []
  i = 0
  while i < args.size()
    arg_type = "i64"
    if arg_types != nil && arg_types[i] != nil
      arg_type = arg_types[i]
    parts.push(arg_type + " " + args[i])
    i += 1
  parts.join(", ")

-> render_method_call_args_setup(inst)
  args = inst[:args]
  if args.size() == 0
    return inst[:temp_args_val] + " = call i64 @w_array_new_empty()\n  "
  out = StringBuffer(args.size() * 48 + 32)
  out << inst[:temp_args_val] + " = call i64 @w_array_new_empty()\n  "
  i = 0
  while i < args.size()
    out << "call i64 @w_array_push(i64 " + inst[:temp_args_val] + ", i64 " + args[i] + ")\n  "
    i += 1
  out.to_s()
