# Emitter primitives — string slabs, runtime declarations, and LLVM helpers.

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

-> llvm_wvalue_literal(value)
  bits = value.to_i() ## u64
  "u0x" + ccall("w_int_to_hex_str", bits)

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

-> build_string_wvalues(strings, no_slab = false)
  wvalues = {}  # string_id → i64 WValue (or nil for large strings)
  next_slot = 1  # slot 0 is reserved sentinel
  slab_entries = []  # [{id, text, slot_index, nslots}, ...]
  # Parser/loader strings can carry distinct mode-6 identities despite equal
  # bytes. Hashing those WValues directly lets the module registry admit a
  # duplicate, which violates the slab identity invariant used by optimized
  # string equality. Key buckets by a content digest and resolve the (rare)
  # collision by raw content comparison before assigning final slots.
  canonical_by_digest = {}

  i = 0
  while i < strings.size()
    s = strings[i]
    byte_len = utf8_byte_length(s[:text])
    if byte_len <= 5
      # SSO-5: inline WValue constant
      wvalues[s[:id]] = sso5_wvalue(s[:text])
    elsif byte_len <= 61 && !no_slab
      digest = wyhash64_hex_string(s[:text])
      bucket = canonical_by_digest[digest]
      existing = nil
      if bucket != nil
        bi = 0
        while bi < bucket.size()
          candidate = bucket[bi]
          if ccall("w_string_content_equal", candidate[:text], s[:text])
            existing = candidate
            break
          bi += 1
      if existing != nil
        wvalues[s[:id]] = existing[:wvalue]
      else
        nslots = 1
        if byte_len > 29
          nslots = 2
        slot_index = next_slot
        next_slot = next_slot + nslots
        # Static literals use the canonical slab identity (tag/mode/index).
        # Runtime-created aliases may additionally cache the byte length in
        # bits 28..33; equality and hashing deliberately ignore those bits.
        wv_bits = (w_tag_stringsym + 12 + slot_index * 16) ## i64
        wv = machine_i64_box(wv_bits)
        wvalues[s[:id]] = wv
        slab_entries.push({id: s[:id], text: s[:text], slot: slot_index, nslots: nslots, byte_len: byte_len})
        if bucket == nil
          bucket = []
          canonical_by_digest[digest] = bucket
        bucket.push({text: s[:text], wvalue: wv})
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
  out << declare_fn("w_index_raw_i64", "i64", wv2)
  out << declare_fn("w_index_raw_u64", "i64", wv2)
  out << declare_fn("w_index_set_raw_i64", "i64", join_arg_types3(wv, wv, "i64"))
  out << declare_fn("w_index_set_raw_u64", "i64", join_arg_types3(wv, wv, "i64"))
  out << declare_fn("w_i128", wv, "i128")
  out << declare_fn("w_to_i128", "i128", wv)
  out << declare_fn("w_u128", wv, "i128")
  out << declare_fn("w_to_u128", "i128", wv)
  # `alwaysinline` on a bodiless declare is a no-op (LLVM can't inline a function
  # it has no body for), and these are never called via @w_bool/@w_nil in practice
  # — the emitter already inlines boolean boxing as `select i1 …, 2, 1` and nil as
  # the constant 0. Keep memory(none)+speculatable (those DO optimize any residual
  # call: CSE, hoist, DCE); drop the dead alwaysinline.
  out << declare_fn_attrs("w_bool", wv, "i64", "nounwind willreturn memory(none) speculatable")
  out << declare_fn_attrs("w_nil", wv, "", "nounwind willreturn memory(none) speculatable")
  out << declare_fn("w_string", wv, "ptr")
  out << declare_fn("w_string_content_equal", wv, wv2)
  out << declare_fn("w_str_to_sym", wv, wv)
  out << declare_fn("w_regex_new", wv, wv2)
  out << declare_fn("w_regex_match", wv, wv2)
  out << declare_fn("w_regex_capture", wv, wv)
  # w_float's body (w_box_double) has a NaN-normalization branch — not worth
  # hand-inlining (miscompile risk on the encoding) and it isn't called via
  # @w_float in practice (float boxing lowers inline). Drop the dead alwaysinline.
  out << declare_fn_attrs("w_float", wv, "double", "nounwind willreturn memory(none) speculatable")
  out << declare_fn("w_decimal", wv, "i64, i32")
  out << declare_fn("w_decimal_from_digits", wv, wv3)
  out << declare_fn("w_bigint_literal_cached", wv, "ptr, ptr")
  # Numeric->raw-double coercion for ensure_raw_f64's fallback: converts a boxed
  # double/Decimal/Int correctly (a plain bitcast-unbox only works for a genuine
  # boxed double; a Decimal reinterprets to garbage). memory(read) — a heap
  # Decimal reads its payload.
  out << declare_fn_attrs("w_num_to_f64", "double", wv, "nounwind memory(read)")

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
  out << declare_fn("w_rational_new", wv, wv2)
  out << declare_fn("w_rational_numerator", wv, wv)
  out << declare_fn("w_rational_denominator", wv, wv)
  out << declare_fn("w_box_char", wv, "i32")
  out << declare_fn("w_color", wv, "i32, i32, i32, i32")
  out << declare_fn("w_register_unit", "void", "i32, ptr")
  out << declare_fn("w_register_unit_wv", "void", i32_wv)

  # Arithmetic
  out << declare_fn("w_add", wv, wv2)
  out << declare_fn("w_sub", wv, wv2)
  # Mutate-if-unique (E4 stage 1): guarded-i48 fallbacks for accumulators
  # the mut-candidate analysis proved dead at their compound assignment.
  # preserve_mostcc: matches __attribute__((preserve_most)) on the C
  # definitions and the guarded-fallback callsites (their only callers).
  out << declare_fn_attrs("w_bigint_add_mut", "preserve_mostcc " + wv, wv2, "nounwind cold")
  out << declare_fn_attrs("w_bigint_sub_mut", "preserve_mostcc " + wv, wv2, "nounwind cold")
  # Consumed +/- by an already-decoded positive literal magnitude. The second
  # i64 is raw 1/2, not a boxed WValue; lowering only selects these entries at
  # sites already admitted by the ordinary mutate-if-unique proof.
  out << declare_fn_attrs("w_bigint_add_small_mut", wv, join_arg_types2(wv, "i64"), "nounwind")
  out << declare_fn_attrs("w_bigint_sub_small_mut", wv, join_arg_types2(wv, "i64"), "nounwind")
  out << declare_fn_attrs("w_bigint_mul_mut", "preserve_mostcc " + wv, wv2, "nounwind cold")
  out << declare_fn_attrs("w_bigint_div_mut", "preserve_mostcc " + wv, wv2, "nounwind cold")
  out << declare_fn_attrs("w_bigint_mod_mut", "preserve_mostcc " + wv, wv2, "nounwind cold")
  out << declare_fn_attrs("w_bigint_and_mut", "preserve_mostcc " + wv, wv2, "nounwind cold")
  out << declare_fn_attrs("w_bigint_or_mut", "preserve_mostcc " + wv, wv2, "nounwind cold")
  out << declare_fn_attrs("w_bigint_xor_mut", "preserve_mostcc " + wv, wv2, "nounwind cold")
  out << declare_fn_attrs("w_bigint_shl_mut", "preserve_mostcc " + wv, wv2, "nounwind cold")
  out << declare_fn_attrs("w_bigint_shr_mut", "preserve_mostcc " + wv, wv2, "nounwind cold")
  out << declare_fn_attrs("w_bigint_mod_pow2_mut", "preserve_mostcc " + wv, wv2, "nounwind cold")
  out << declare_fn_attrs("w_bigint_div_pow2_mut", "preserve_mostcc " + wv, wv2, "nounwind cold")
  out << declare_fn_attrs("w_bigint_add_mod_pow2_mut", "preserve_mostcc " + wv, wv3, "nounwind cold")
  out << declare_fn_attrs("w_bigint_addmul_mut", "preserve_mostcc " + wv, wv3, "nounwind cold")
  out << declare_fn_attrs("w_bigint_submul_mut", "preserve_mostcc " + wv, wv3, "nounwind cold")
  out << declare_fn("w_bigint_add_dest", wv, wv3)
  # Word-overwrite destination entries (E4 stage 3): same preserve_mostcc
  # contract as the mut family — the C definitions carry
  # __attribute__((preserve_most)).
  out << declare_fn_attrs("w_bigint_add_word_dest", "preserve_mostcc " + wv, wv3, "nounwind cold")
  out << declare_fn_attrs("w_bigint_sub_word_dest", "preserve_mostcc " + wv, wv3, "nounwind cold")
  out << declare_fn_attrs("w_bigint_mul_word_dest", "preserve_mostcc " + wv, wv3, "nounwind cold")
  out << declare_fn("w_mul", wv, wv2)
  out << declare_fn_attrs("w_bigint_mul_builtin_exact", wv, wv2, "nounwind")
  out << declare_fn("w_pow", wv, wv2)
  out << declare_fn("w_div", wv, wv2)
  out << declare_fn("w_mod", wv, wv2)
  out << declare_fn("w_bigint_mod_pow2", wv, wv2)
  out << declare_fn("w_bigint_div_pow2", wv, wv2)
  # NOTE: the bigint operator seams (__w_bigint_{plus,minus}_src) are
  # deliberately NOT declared here. A module that compiles BigInt#+/#-
  # DEFINES them, and LLVM rejects a declare alongside a define; modules
  # that only call them get the declaration emitted next to the wrapper
  # block in emit_artifact instead.
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
  out << declare_fn("w_type_tables_lock_safe", wv, "")
  out << declare_fn("w_method_tables_lock_safe", wv, "")
  out << "declare void @w_value_free(i64)\n"
  out << "declare void @w_slab_init_static(ptr, i32)\n"
  out << "declare void @w_preflight()\n"
  out << "declare void @__w_loc_set_col(ptr, i32, i32)\n"
  out << declare_fn("w_int_to_hex_str", wv, "i64")
  # Same as w_bool/w_nil: `if`/`while` conditions lower to inline i1 tests, so
  # @w_truthy is never actually called; drop the dead alwaysinline, keep the rest.
  out << declare_fn_attrs("w_truthy", "i64", wv, "nounwind willreturn memory(none) speculatable")

  # Arrays — bare polymorphic constructor and the typed/sized form
  out << declare_fn("w_array_new_empty", wv, "")
  out << declare_fn("w_array_new", wv, "i64, i64")
  out << declare_fn("w_range_pow_sum", wv, "i64, i64, i64, i64")
  out << declare_fn("w_array_reuse_or_new", wv, "ptr, i64, i64")
  out << declare_fn("w_fused_out_reuse_or_new", wv, "ptr, i64, i64")
  out << declare_fn("w_array_push", wv, wv2)
  out << declare_fn("w_array_get", wv, wv2)
  # Pure reads: return W_NIL on OOB, never raise, always return. memory(read)+
  # willreturn lets the function-attrs pass propagate purity up through the
  # inlined __w_array_*_i64_fast helpers, so `a[i]` reads CSE and hoist out of
  # loops that don't write the array.
  #
  # Documented exception: for i64-typed elements whose value exceeds the
  # 47-bit inline-int payload, these return through w_int, which ALLOCATES a
  # BigInt — technically a write. This is deliberate: the allocation is
  # invisible to the caller (fresh, unaliased), so the worst a memory(read)-
  # justified CSE can do is merge two structurally-equal BigInts. Keep the
  # attribute; do not "fix" it by dropping the hoisting win.
  out << declare_fn_attrs("w_array_get_i64", wv, join_arg_types2(wv, "i64"), "nounwind willreturn memory(read)")
  out << declare_fn_attrs("w_array_idx_i64", wv, join_arg_types2(wv, "i64"), "nounwind willreturn memory(read)")
  out << declare_fn("w_array_set", wv, wv3)
  out << declare_fn("w_array_set_i64", wv, join_arg_types3(wv, "i64", wv))
  # `.size`/`.cap` read one header field, never raise — memory(read) lets LICM
  # hoist `arr.size` out of read-only loops and CSE repeated reads.
  out << declare_fn_attrs("w_array_size", wv, wv, "nounwind willreturn memory(read)")
  out << declare_fn("w_array_pop", wv, wv)
  out << declare_fn("w_array_shift", wv, wv)
  out << declare_fn_attrs("w_array_cap", wv, wv, "nounwind willreturn memory(read)")

  # Bool arrays
  out << declare_fn("w_bool_array_new", wv, "i64")
  # Pure read: bit-tests packed storage, returns W_FALSE OOB, never raises or
  # allocates — same hoist/CSE rationale as w_array_get_i64 above (and no
  # BigInt exception here: results are only W_TRUE/W_FALSE).
  out << declare_fn_attrs("w_bool_array_get", wv, wv2, "nounwind willreturn memory(read)")
  out << declare_fn("w_bool_array_set", wv, wv3)
  # Dot-prefix elementwise operators (.+ .- .* ./ .| .& .^ .<< .>>)
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
  out << declare_fn_attrs("w_bool_array_size", wv, wv, "nounwind willreturn memory(read)")

  # String builtins
  # Index/slice/first-byte deliberately stay nounwind-only. Their SSO arms are
  # register-only, but slab/heap inputs read storage and rope inputs flatten,
  # allocate, and cache a result. A whole-function memory(none) or memory(read)
  # contract would therefore let LLVM miscompile valid rope calls. Byte length
  # is the exception: it reads a rope's cached total_len without flattening.
  out << declare_fn("w_string_idx_raw", wv, join_arg_types2(wv, "i64"))
  out << declare_fn("w_string_slice_raw", wv, join_arg_types3(wv, "i64", "i64"))
  out << declare_fn_attrs("w_string_byte_length", "i64", "i64", "nounwind willreturn memory(read)")
  out << declare_fn("w_string_first_byte", "i64", wv)
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
  out << declare_fn("w_method_call_cached_2", wv, join_arg_types5(wv, wv, wv, wv, "ptr"))
  out << declare_fn("w_value_is_a", wv, wv2)

  # Classes / objects
  out << declare_fn("w_class_new", wv, ptr_wv)
  out << declare_fn("w_class_new_wv", wv, wv2)
  out << declare_fn("w_class_add_method", "void", wv_ptr_ptr_i32)
  out << declare_fn("w_class_add_method_wv", "void", wv2_ptr_i32)
  out << declare_fn("w_class_add_method_range_wv", "void", join_arg_types5(wv, wv, "ptr", "i32", "i32"))
  out << declare_fn("w_class_add_method_splat_wv", "void", join_arg_types6(wv, wv, "ptr", "i32", "i32", "i32"))
  out << declare_fn("w_class_add_static_method", "void", wv_ptr_ptr_i32)
  out << declare_fn("w_class_add_static_method_wv", "void", wv2_ptr_i32)
  out << declare_fn("w_class_add_static_method_range_wv", "void", join_arg_types5(wv, wv, "ptr", "i32", "i32"))
  out << declare_fn("w_class_add_static_method_splat_wv", "void", join_arg_types6(wv, wv, "ptr", "i32", "i32", "i32"))
  out << declare_fn("w_type_class_register_wv", "void", i32_wv)
  out << declare_fn("w_node_kind_class_register_wv", "void", i32_wv)
  out << declare_fn("w_object_new", wv, wv)
  out << declare_fn("w_ivar_get", wv, wv_ptr)
  out << declare_fn("w_ivar_get_wv", wv, wv2)
  out << declare_fn("w_ivar_set", wv, wv_ptr_wv)
  out << declare_fn("w_ivar_set_wv", wv, wv3)
  out << declare_fn("w_ivar_get_idx", wv, wv_i32)
  out << declare_fn("w_ivar_set_idx", wv, wv_i32_wv)

  # PR #2: AST slab node primitives. w_node_alloc returns a
  # W_PACKED_NODE WValue for a freshly bumped arena slot; the field
  # load/store helpers do offset arithmetic on the encoded (sc, off)
  # pair inside the WValue. LTO inlines these at the call site.
  # i64 arg types match how ccall_nobox emits args on the call boundary.
  out << declare_fn("w_node_alloc", wv, "i64, i64")
  out << declare_fn("w_node_field_load", wv, join_arg_types2(wv, "i64"))
  out << declare_fn("w_node_field_store", wv, join_arg_types3(wv, "i64", wv))
  out << declare_fn("w_ast_sparse_set", wv, join_arg_types3(wv, "i64", wv))
  out << declare_fn("w_ast_sparse_get", wv, join_arg_types2(wv, "i64"))
  out << declare_fn("w_ast_sparse_copy", wv, wv2)
  out << declare_fn("w_ast_analysis_set", wv, wv2)
  out << declare_fn("w_ast_analysis_get", wv, wv)
  out << declare_fn("w_ast_ivar_offsets_set", wv, wv2)
  out << declare_fn("w_ast_ivar_offsets_get", wv, wv)
  out << declare_fn("w_ast_ivar_count_set", wv, wv2)
  out << declare_fn("w_ast_ivar_count_get", wv, wv)
  out << declare_fn("w_ast_intern_node", wv, i64_wv)
  out << declare_fn("w_ast_intern_str_of", wv, wv)
  out << declare_fn("w_ast_freeze_if_array", wv, wv)
  out << declare_fn("w_ast_body_builder_new", wv, "i64")
  out << declare_fn("w_ast_body_builder_push", wv, join_arg_types3(wv, "i64", wv))
  out << declare_fn("w_ast_body_builder_finish", wv, join_arg_types2(wv, "i64"))
  out << declare_fn("w_node_arena_reset", "void", "")
  out << declare_fn("w_ast_schema_hash_compute", "i64", "")
  # Packed WIRE instruction arena. The handle carries :op as an 8-bit kind;
  # record fields are inline symbol/value pairs in a resettable word arena.
  out << declare_fn("w_wire_alloc", wv, "i64, i64")
  out << declare_fn("w_wire_alloc_reserve", wv, "i64, i64, i64")
  out << declare_fn("w_wire_field_store_at", wv, join_arg_types4(wv, "i64", wv, wv))
  out << declare_fn("w_wire_field_load", wv, wv2)
  out << declare_fn("w_wire_field_load_nil", wv, wv2)
  out << declare_fn("w_wire_field_store", wv, wv3)
  out << declare_fn("w_wire_kind_extern", "i64", wv)
  out << declare_fn("w_is_wire_extern", "i64", wv)
  out << declare_fn("w_wire_store_reset", "i64", "i64")
  out << declare_fn("w_wire_store_mark", "i64", "")
  out << declare_fn("w_wire_clone", wv, wv)
  out << declare_fn("w_wire_sequence_from_array", wv, wv)
  out << declare_fn_attrs("w_wire_sequence_size", "i64", wv,
                          "nounwind willreturn memory(read)")
  out << declare_fn_attrs("w_wire_sequence_get", wv, join_arg_types2(wv, "i64"),
                          "nounwind willreturn memory(read)")
  out << declare_fn_attrs("w_wire_sequence_set", wv, join_arg_types3(wv, "i64", wv),
                          "nounwind willreturn memory(readwrite)")
  out << declare_fn("w_class_add_ivar", "i32", wv_ptr)
  out << declare_fn("w_class_add_ivar_wv", "i32", wv2)

  # Closures
  out << declare_fn("w_closure_new", wv, ptr_ptr_i32)
  out << declare_fn("w_closure_new_a", wv, "ptr, ptr, i32, i32")
  out << declare_fn("w_destructure_index", wv, join_arg_types2(wv, "i64"))
  out << declare_fn("w_closure_cell_new", "ptr", "")
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
  out << declare_fn_attrs("_setjmp", "i32", "ptr", "nounwind returns_twice")

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
  out << declare_fn("w_mutex_new", wv, "")
  out << declare_fn("w_mutex_lock", wv, wv)
  out << declare_fn("w_mutex_try_lock", wv, wv)
  out << declare_fn("w_mutex_unlock", wv, wv)
  out << declare_fn("w_mutex_locked", wv, wv)
  out << declare_fn("w_chan_new", wv, wv)
  out << declare_fn("w_chan_new_unbounded", wv, "")
  out << declare_fn("w_chan_send", wv, wv2)
  out << declare_fn("w_chan_try_send", wv, wv2)
  out << declare_fn("w_chan_try_send_result", wv, wv2)
  out << declare_fn("w_chan_send_timeout", wv, wv3)
  out << declare_fn("w_chan_recv", wv, wv)
  out << declare_fn("w_chan_recv_result", wv, wv)
  out << declare_fn("w_chan_try_recv_result", wv, wv)
  out << declare_fn("w_chan_recv_timeout_result", wv, wv2)
  out << declare_fn("w_sync_handle_kind_support", wv, wv)
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
  out << declare_fn("__w_file_read_dir", wv, wv)
  out << declare_fn("__w_file_join", wv, wv2)
  out << declare_fn("__w_write_file", wv, wv2)
  out << declare_fn("__w_write_file_n", wv, wv3)
  out << declare_fn("__w_file_rm", wv, wv)
  out << declare_fn("__w_file_mmap", wv, wv)
  out << declare_fn("__w_mmap_length", wv, wv)
  out << declare_fn("__w_mmap_byte_at", wv, wv2)
  out << declare_fn("__w_mmap_close", wv, wv)
  out << declare_fn("__w_mmap_as_typed", wv, join_arg_types2(wv, "i64"))

  # Math.* libm wrappers
  out << declare_fn("w_math_exp", wv, wv)
  out << declare_fn("w_math_log", wv, wv)
  out << declare_fn("w_math_expm1", wv, wv)
  out << declare_fn("w_math_log1p", wv, wv)
  out << declare_fn("w_math_sin", wv, wv)
  out << declare_fn("w_math_cos", wv, wv)
  out << declare_fn("w_math_tan", wv, wv)
  out << declare_fn("w_math_asin", wv, wv)
  out << declare_fn("w_math_acos", wv, wv)
  out << declare_fn("w_math_atan", wv, wv)
  out << declare_fn("w_math_cbrt", wv, wv)
  out << declare_fn("w_math_sqrt", wv, wv)
  out << declare_fn("w_math_floor", wv, wv)
  out << declare_fn("w_math_ceil", wv, wv)
  out << declare_fn("w_math_round", wv, wv)
  out << declare_fn("w_math_abs", wv, wv)
  out << declare_fn("w_math_pow", wv, wv2)
  out << declare_fn("w_math_ldexp", wv, wv2)
  out << declare_fn("w_math_atan2", wv, wv2)
  out << declare_fn("w_math_hypot", wv, wv2)
  out << declare_fn("w_math_fma", wv, wv3)

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
  out << declare_fn_attrs("asin", "double", "double", libm_attrs)
  out << declare_fn_attrs("acos", "double", "double", libm_attrs)
  out << declare_fn_attrs("atan", "double", "double", libm_attrs)
  out << declare_fn_attrs("cbrt", "double", "double", libm_attrs)
  out << declare_fn_attrs("exp", "double", "double", libm_attrs)
  out << declare_fn_attrs("log", "double", "double", libm_attrs)
  out << declare_fn_attrs("expm1", "double", "double", libm_attrs)
  out << declare_fn_attrs("log1p", "double", "double", libm_attrs)
  out << declare_fn_attrs("sqrt", "double", "double", libm_attrs)
  out << declare_fn_attrs("floor", "double", "double", libm_attrs)
  out << declare_fn_attrs("ceil", "double", "double", libm_attrs)
  out << declare_fn_attrs("round", "double", "double", libm_attrs)
  out << declare_fn_attrs("fabs", "double", "double", libm_attrs)
  out << declare_fn_attrs("pow", "double", dd, libm_attrs)
  out << declare_fn_attrs("atan2", "double", dd, libm_attrs)
  out << declare_fn_attrs("hypot", "double", dd, libm_attrs)

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
  out << declare_fn("__w_sleep_ms", wv, "i64")
  out << declare_fn("__w_clock", wv, "")
  out << declare_fn("__w_cpu_count", wv, "")
  out << declare_fn("__w_l1d_cache_bytes", wv, "")
  out << declare_fn("__w_l2_cache_bytes", wv, "")
  out << declare_fn("__w_cpus_per_l2", wv, "")
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
  out << declare_fn("w_cleanup_push", "void", wv_ptr)
  out << declare_fn("w_cleanup_pop", "void", "")
  out << declare_fn("w_array_copy_range", wv, wv4)
  out << declare_fn("__w_file_link", wv, wv2)
  out << declare_fn("__w_file_chmod", wv, wv2)
  out << declare_fn("__w_rename", wv, wv2)
  out << declare_fn("__w_temp_file_for", wv, wv)
  out << declare_fn("__w_fsync_path", wv, wv)
  out << declare_fn("__w_fsync_parent", wv, wv)
  out << declare_fn("__w_unlink", wv, wv)
  out << declare_fn("__w_file_unlink_strict", wv, wv)

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

-> join_arg_types6(a, b, c, d, e, f)
  out = StringBuffer(a.size() + b.size() + c.size() + d.size() + e.size() + f.size() + 10)
  out << a
  out << ", "
  out << b
  out << ", "
  out << c
  out << ", "
  out << d
  out << ", "
  out << e
  out << ", "
  out << f
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
  # v5: arrays ride W_TAG_ARRAY (0xFFF4) — the five-instruction object-
  # space + subtag guard collapses to one tag compare (65524 = 0xFFF4).
  out << "  %hi = lshr i64 %arr, 48\n"
  out << "  %objarr = icmp eq i64 %hi, 65524\n"
  out << "  br i1 %objarr, label %hdr, label %slow\n"
  out << "hdr:\n"
  # W_ARRAY_PTR_MASK: strip tag + reserved flag bits (47, 3-0).
  out << "  %base = and i64 %arr, 140737488355312\n"
  out << "  %p = inttoptr i64 %base to ptr\n"
  out << "  %ebp = getelementptr i8, ptr %p, i64 1\n"
  out << "  %eb = load i8, ptr %ebp, align 1" + invariant_load_suffix() + "\n"
  out << "  %is65 = icmp eq i8 %eb, 65\n"
  out << "  br i1 %is65, label %rng, label %slow, !prof !31411\n"
  out << "rng:\n"
  out << "  %szp = getelementptr i8, ptr %p, i64 8\n"
  out << "  %sz32 = load i32, ptr %szp, align 4" + tbaa_header_suffix() + "\n"
  out << "  %sz = sext i32 %sz32 to i64\n"
  out << "  %neg = icmp slt i64 %i, 0\n"
  out << "  %iw = add i64 %i, %sz\n"
  out << "  %ix = select i1 %neg, i64 %iw, i64 %i\n"
  out << "  %inb = icmp ult i64 %ix, %sz\n"
  out << "  br i1 %inb, label %fast, label %slow, !prof !31411\n"
  out << "fast:\n"
  out << "  %stp = getelementptr i8, ptr %p, i64 4\n"
  out << "  %st32 = load i32, ptr %stp, align 4" + tbaa_header_suffix() + "\n"
  out << "  %st = sext i32 %st32 to i64\n"
  out << "  %slp = getelementptr i8, ptr %p, i64 16\n"
  out << "  %slots = load ptr, ptr %slp, align 8" + tbaa_header_suffix() + "\n"
  out << "  %eff = add i64 %st, %ix\n"
  out << "  %ep = getelementptr i64, ptr %slots, i64 %eff\n"
  out << "  %v = load i64, ptr %ep, align 8" + tbaa_elem_suffix() + "\n"
  out << "  ret i64 %v\n"
  out << "slow:\n"
  out << "  %sv = call i64 @w_array_get_i64(i64 %arr, i64 %i)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out << "define private i64 @__w_array_idx_i64_fast(i64 %arr, i64 %i) alwaysinline nounwind {\n"
  out << "entry:\n"
  # v5: arrays ride W_TAG_ARRAY (0xFFF4) — the five-instruction object-
  # space + subtag guard collapses to one tag compare (65524 = 0xFFF4).
  out << "  %hi = lshr i64 %arr, 48\n"
  out << "  %objarr = icmp eq i64 %hi, 65524\n"
  out << "  br i1 %objarr, label %hdr, label %slow\n"
  out << "hdr:\n"
  # W_ARRAY_PTR_MASK: strip tag + reserved flag bits (47, 3-0).
  out << "  %base = and i64 %arr, 140737488355312\n"
  out << "  %p = inttoptr i64 %base to ptr\n"
  out << "  %ebp = getelementptr i8, ptr %p, i64 1\n"
  out << "  %eb = load i8, ptr %ebp, align 1" + invariant_load_suffix() + "\n"
  out << "  %is65 = icmp eq i8 %eb, 65\n"
  out << "  br i1 %is65, label %fast, label %slow, !prof !31411\n"
  out << "fast:\n"
  out << "  %stp = getelementptr i8, ptr %p, i64 4\n"
  out << "  %st32 = load i32, ptr %stp, align 4" + tbaa_header_suffix() + "\n"
  out << "  %st = sext i32 %st32 to i64\n"
  out << "  %eff = add i64 %st, %i\n"
  out << "  %slp = getelementptr i8, ptr %p, i64 16\n"
  out << "  %slots = load ptr, ptr %slp, align 8" + tbaa_header_suffix() + "\n"
  out << "  %ep = getelementptr i64, ptr %slots, i64 %eff\n"
  out << "  %v = load i64, ptr %ep, align 8" + tbaa_elem_suffix() + "\n"
  out << "  ret i64 %v\n"
  out << "slow:\n"
  out << "  %sv = call i64 @w_array_idx_i64(i64 %arr, i64 %i)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out.to_s()

# Inline WArray write fast path — the store-side twin of __w_array_get_i64_fast.
# Fast case (poly array, ebits=65, index in [0,size) after negative-wrap): store
# the boxed value straight into slots[start+ix] and return it. Everything else —
# growth (i in [size,cap)), typed/float/bool arrays, body refs — falls to the
# cold path, which re-boxes the index and calls the body-safe w_array_set so the
# full `[]=` semantics (and the immutable-body raise) are preserved. Only the
# in-bounds poly case is inlined, so no size bump is ever needed inline.
-> array_set_fast_helper_ir()
  out = StringBuffer(1400)
  out << "define private i64 @__w_array_set_i64_fast(i64 %arr, i64 %i, i64 %val) alwaysinline nounwind {\n"
  out << "entry:\n"
  # v5: arrays ride W_TAG_ARRAY (0xFFF4) — the five-instruction object-
  # space + subtag guard collapses to one tag compare (65524 = 0xFFF4).
  out << "  %hi = lshr i64 %arr, 48\n"
  out << "  %objarr = icmp eq i64 %hi, 65524\n"
  out << "  br i1 %objarr, label %hdr, label %slow\n"
  out << "hdr:\n"
  # W_ARRAY_PTR_MASK: strip tag + reserved flag bits (47, 3-0).
  out << "  %base = and i64 %arr, 140737488355312\n"
  out << "  %p = inttoptr i64 %base to ptr\n"
  out << "  %ebp = getelementptr i8, ptr %p, i64 1\n"
  out << "  %eb = load i8, ptr %ebp, align 1" + invariant_load_suffix() + "\n"
  out << "  %is65 = icmp eq i8 %eb, 65\n"
  out << "  br i1 %is65, label %rng, label %slow, !prof !31411\n"
  out << "rng:\n"
  # start/slots load before the bounds branch — same reorder rationale as
  # __w_array_get_i64_fast above (unconditional once kind-checked; hoistable).
  out << "  %szp = getelementptr i8, ptr %p, i64 8\n"
  out << "  %sz32 = load i32, ptr %szp, align 4" + tbaa_header_suffix() + "\n"
  out << "  %sz = sext i32 %sz32 to i64\n"
  out << "  %stp = getelementptr i8, ptr %p, i64 4\n"
  out << "  %st32 = load i32, ptr %stp, align 4" + tbaa_header_suffix() + "\n"
  out << "  %st = sext i32 %st32 to i64\n"
  out << "  %slp = getelementptr i8, ptr %p, i64 16\n"
  out << "  %slots = load ptr, ptr %slp, align 8" + tbaa_header_suffix() + "\n"
  out << "  %neg = icmp slt i64 %i, 0\n"
  out << "  %iw = add i64 %i, %sz\n"
  out << "  %ix = select i1 %neg, i64 %iw, i64 %i\n"
  out << "  %inb = icmp ult i64 %ix, %sz\n"
  out << "  br i1 %inb, label %fast, label %slow, !prof !31411\n"
  out << "fast:\n"
  out << "  %eff = add i64 %st, %ix\n"
  out << "  %ep = getelementptr i64, ptr %slots, i64 %eff\n"
  out << "  store i64 %val, ptr %ep, align 8" + tbaa_elem_suffix() + "\n"
  out << "  ret i64 %val\n"
  out << "slow:\n"
  out << "  %ib = call i64 @w_int(i64 %i)\n"
  out << "  %sv = call i64 @w_array_set(i64 %arr, i64 %ib, i64 %val)\n"
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
-> int_pair_test_ir()
  out = StringBuffer(220)
  out << "  %ta = lshr i64 %a, 48\n"
  out << "  %ia = icmp eq i64 %ta, 65530\n"
  out << "  %tb = lshr i64 %b, 48\n"
  out << "  %ib = icmp eq i64 %tb, 65530\n"
  out << "  %both = and i1 %ia, %ib\n"
  out.to_s()

-> cmp_fast_helper_ir(fast_name, slow_name, pred, sext_payload)
  out = StringBuffer(760)
  out << "define private i64 @" + fast_name + "(i64 %a, i64 %b) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << int_pair_test_ir()
  out << "  br i1 %both, label %fast, label %slow, !prof !31411\n"
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

# `x == <string/symbol literal>` fast path. %lit is always a compile-time-
# constant CANONICAL box (inline mode 0-5 or interned slab mode 6 — >61-byte
# literals lower to runtime temps and never reach this helper), so after
# alwaysinline + constant folding each site is a bit-compare plus a
# canonicality test. Faithful specialization of w_eq's own ladder:
#   bits equal                      -> W_TRUE  (w_eq's a == b arm)
#   x stringy (tag 0xFFF9) mode 0-5 -> W_FALSE (inline values are canonical
#      by bit pattern; mode-6 aliases can differ in cached-length bits, while
#      mode-7 text starts at six bytes)
#   anything else (mode-7 heap/rope strings, ints, objects, ...) -> w_eq,
#      preserving content compares and user-defined == exactly.
# `big <op> 0` fast path for statically-BigInt operands (lowering's zero-
# compare arm; %zero is always the boxed literal 0). The sign of any boxed
# integer is answered without touching magnitude limbs:
#   inline Int (tag 0xFFFA)  -> sign of the sign-extended i48 payload
#   heap BigInt (tag 0xFFFB) -> header signed size COMPOSED with the
#      tag-sign overlay (bit 47) — w_bigint_view's exact rule; a raw header
#      read would answer wrong for negate's overlay-flipped aliases, and a
#      zero magnitude stays non-negative whatever the overlay says because
#      negating size 0 is still 0.
#   anything else -> the ordinary comparison entry, so stale type facts
#      (non-integer values in a :bigint slot) keep full dispatch semantics.
-> bigint_zero_cmp_fast_helper_ir(fast_name, slow_name, pred)
  out = StringBuffer(1200)
  out << "define private i64 @" + fast_name + "(i64 %x, i64 %zero) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << "  %t = lshr i64 %x, 48\n"
  out << "  %isint = icmp eq i64 %t, 65530\n"
  out << "  br i1 %isint, label %int, label %ckbig, !prof !31411\n"
  out << "int:\n"
  out << "  %s = shl i64 %x, 16\n"
  out << "  %p = ashr i64 %s, 16\n"
  out << "  %ci = icmp " + pred + " i64 %p, 0\n"
  out << "  %ri = select i1 %ci, i64 2, i64 1\n"
  out << "  ret i64 %ri\n"
  out << "ckbig:\n"
  out << "  %isbig = icmp eq i64 %t, 65531\n"
  out << "  br i1 %isbig, label %big, label %slow, !prof !31411\n"
  out << "big:\n"
  out << "  %pi = and i64 %x, 140737488355327\n"
  out << "  %bp = inttoptr i64 %pi to ptr\n"
  out << "  %szp = getelementptr inbounds i8, ptr %bp, i64 4\n"
  out << "  %sz = load i32, ptr %szp, align 4\n"
  out << "  %sz64 = sext i32 %sz to i64\n"
  out << "  %ov = and i64 %x, 140737488355328\n"
  out << "  %negd = icmp ne i64 %ov, 0\n"
  out << "  %nsz = sub i64 0, %sz64\n"
  out << "  %eff = select i1 %negd, i64 %nsz, i64 %sz64\n"
  out << "  %cb = icmp " + pred + " i64 %eff, 0\n"
  out << "  %rb = select i1 %cb, i64 2, i64 1\n"
  out << "  ret i64 %rb\n"
  out << "slow:\n"
  out << "  %sv = call i64 @" + slow_name + "(i64 %x, i64 %zero)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out.to_s()

-> streq_fast_helper_ir()
  out = StringBuffer(700)
  out << "define private i64 @__w_streq_fast(i64 %x, i64 %lit) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << "  %eqb = icmp eq i64 %x, %lit\n"
  out << "  br i1 %eqb, label %t, label %c\n"
  out << "t:\n"
  out << "  ret i64 2\n"
  out << "c:\n"
  out << "  %hi = lshr i64 %x, 48\n"
  out << "  %iss = icmp eq i64 %hi, 65529\n"
  out << "  %md = lshr i64 %x, 1\n"
  out << "  %md3 = and i64 %md, 7\n"
  out << "  %nh = icmp ule i64 %md3, 5\n"
  out << "  %canon = and i1 %iss, %nh\n"
  out << "  br i1 %canon, label %f, label %s\n"
  out << "f:\n"
  out << "  ret i64 1\n"
  out << "s:\n"
  out << "  %sv = call i64 @w_eq(i64 %x, i64 %lit)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out.to_s()

# String byte subscript under a :string type fact. The public runtime entry
# remains conservative because its slab/heap/rope fallback accesses memory.
# Keep the SSO-5 calculation in its own fully pure leaf: after the wrapper is
# inlined, LLVM can CSE/hoist/fold this arm without being told that the slow
# arm is pure too.
-> string_idx_fast_helper_ir()
  out = StringBuffer(1250)
  out << "define private i64 @__w_sso_idx(i64 %str, i64 %idx) alwaysinline nounwind willreturn memory(none) speculatable {\n"
  out << "entry:\n"
  out << "  %mode.raw = lshr i64 %str, 1\n"
  out << "  %len = and i64 %mode.raw, 7\n"
  out << "  %negative = icmp slt i64 %idx, 0\n"
  out << "  %from.end = add i64 %idx, %len\n"
  out << "  %effective = select i1 %negative, i64 %from.end, i64 %idx\n"
  out << "  %in.bounds = icmp ult i64 %effective, %len\n"
  out << "  br i1 %in.bounds, label %byte, label %oob\n"
  out << "byte:\n"
  out << "  %shift = shl i64 %effective, 3\n"
  out << "  %lane.raw = lshr i64 %str, %shift\n"
  out << "  %lane = and i64 %lane.raw, 4080\n"
  out << "  %result = or i64 %lane, -1970324836974590\n"
  out << "  ret i64 %result\n"
  out << "oob:\n"
  out << "  ret i64 0\n"
  out << "}\n"
  out << "define private i64 @__w_string_idx_fast(i64 %str, i64 %idx) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << "  %tag = lshr i64 %str, 48\n"
  out << "  %is.stringy = icmp eq i64 %tag, 65529\n"
  out << "  %mode.raw = lshr i64 %str, 1\n"
  out << "  %mode = and i64 %mode.raw, 7\n"
  out << "  %is.inline = icmp ule i64 %mode, 5\n"
  out << "  %is.sso = and i1 %is.stringy, %is.inline\n"
  out << "  br i1 %is.sso, label %fast, label %slow, !prof !31411\n"
  out << "fast:\n"
  out << "  %fv = call i64 @__w_sso_idx(i64 %str, i64 %idx)\n"
  out << "  ret i64 %fv\n"
  out << "slow:\n"
  out << "  %sv = call i64 @w_string_idx_raw(i64 %str, i64 %idx)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out.to_s()

# String byte length under a :string type fact. The pure SSO leaf only
# extracts the mode bits. The wrapper is read-only for every storage mode:
# its fallback reads slab/heap headers or a rope's existing total_len and
# never flattens the rope.
-> string_size_fast_helper_ir()
  out = StringBuffer(700)
  out << "define private i64 @__w_sso_size(i64 %str) alwaysinline nounwind willreturn memory(none) speculatable {\n"
  out << "entry:\n"
  out << "  %mode.raw = lshr i64 %str, 1\n"
  out << "  %len = and i64 %mode.raw, 7\n"
  out << "  ret i64 %len\n"
  out << "}\n"
  out << "define private i64 @__w_string_byte_length_fast(i64 %str) alwaysinline nounwind willreturn memory(read) {\n"
  out << "entry:\n"
  out << "  %tag = lshr i64 %str, 48\n"
  out << "  %is.stringy = icmp eq i64 %tag, 65529\n"
  out << "  %mode.raw = lshr i64 %str, 1\n"
  out << "  %mode = and i64 %mode.raw, 7\n"
  out << "  %is.inline = icmp ule i64 %mode, 5\n"
  out << "  %is.sso = and i1 %is.stringy, %is.inline\n"
  out << "  br i1 %is.sso, label %fast, label %slow, !prof !31411\n"
  out << "fast:\n"
  out << "  %fv = call i64 @__w_sso_size(i64 %str)\n"
  out << "  ret i64 %fv\n"
  out << "slow:\n"
  out << "  %sv = call i64 @w_string_byte_length(i64 %str)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out.to_s()

# Var-var `a == b` under a :string type fact. Faithful w_eq specialization:
#   bits equal                          -> W_TRUE  (w_eq's a == b arm)
#   BOTH inline stringy (mode 0-5)      -> W_FALSE (equal inline content
#      has identical bit representation, so differing bits prove inequality; symbol
#      bit 0 rides in the bits so strings never fold equal to symbols)
#   anything else -> w_eq. One inline side alone is NOT enough: the other
#   side could be a short rope with equal content, which only w_eq resolves.
-> streq2_fast_helper_ir()
  out = StringBuffer(760)
  out << "define private i64 @__w_streq2_fast(i64 %a, i64 %b) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << "  %eqb = icmp eq i64 %a, %b\n"
  out << "  br i1 %eqb, label %t, label %c\n"
  out << "t:\n"
  out << "  ret i64 2\n"
  out << "c:\n"
  out << "  %ha = lshr i64 %a, 48\n"
  out << "  %sa = icmp eq i64 %ha, 65529\n"
  out << "  %ma = lshr i64 %a, 1\n"
  out << "  %ma3 = and i64 %ma, 7\n"
  out << "  %na = icmp ule i64 %ma3, 5\n"
  out << "  %ca = and i1 %sa, %na\n"
  out << "  %hb = lshr i64 %b, 48\n"
  out << "  %sb = icmp eq i64 %hb, 65529\n"
  out << "  %mb = lshr i64 %b, 1\n"
  out << "  %mb3 = and i64 %mb, 7\n"
  out << "  %nb = icmp ule i64 %mb3, 5\n"
  out << "  %cb = and i1 %sb, %nb\n"
  out << "  %canon = and i1 %ca, %cb\n"
  out << "  br i1 %canon, label %f, label %s\n"
  out << "f:\n"
  out << "  ret i64 1\n"
  out << "s:\n"
  out << "  %sv = call i64 @w_eq(i64 %a, i64 %b)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out.to_s()

# Boxed + / - fast path (lowering's op map routes :PLUS/:MINUS here). Both
# operands inline Ints (tag 0xFFFA) -> sign-extended 48-bit payload add/sub
# with an i48 fit check on the result; a fitting result re-boxes inline.
# Overflow (needs BigInt promotion) and every non-int operand — floats,
# BigInts, strings, user-defined + — tail-call the runtime op unchanged.
-> arith_fast_helper_ir(fast_name, slow_name, llvm_op)
  out = StringBuffer(760)
  out << "define private i64 @" + fast_name + "(i64 %a, i64 %b) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << int_pair_test_ir()
  out << "  br i1 %both, label %fast, label %slow, !prof !31411\n"
  out << "fast:\n"
  out << "  %sa = shl i64 %a, 16\n"
  out << "  %pa = ashr i64 %sa, 16\n"
  out << "  %sb = shl i64 %b, 16\n"
  out << "  %pb = ashr i64 %sb, 16\n"
  out << "  %r = " + llvm_op + " i64 %pa, %pb\n"
  out << "  %rs = shl i64 %r, 16\n"
  out << "  %rb = ashr i64 %rs, 16\n"
  out << "  %fit = icmp eq i64 %rb, %r\n"
  out << "  br i1 %fit, label %box, label %slow\n"
  out << "box:\n"
  out << "  %m = and i64 %r, 281474976710655\n"
  out << "  %v = or i64 %m, -1688849860263936\n"
  out << "  ret i64 %v\n"
  out << "slow:\n"
  out << "  %sv = call i64 @" + slow_name + "(i64 %a, i64 %b)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out.to_s()

# Boxed & | ^ fast paths. XOR of two int boxes zeroes the tag (retag after);
# AND/OR of two int boxes PRESERVE the tag (tag&tag = tag|tag = tag), so the
# result is already a valid box — a single instruction. Payload &|^ of two
# sign-extended 48-bit values always fits i48 (sign bits combine the same
# way), so no overflow guard is needed — mirrors bit_binop's both-int arm
# (w_box_int_checked never fires there).
-> bitop_fast_helper_ir(fast_name, slow_name, llvm_op)
  out = StringBuffer(600)
  out << "define private i64 @" + fast_name + "(i64 %a, i64 %b) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << int_pair_test_ir()
  out << "  br i1 %both, label %fast, label %slow, !prof !31411\n"
  out << "fast:\n"
  if llvm_op == "xor"
    out << "  %x = xor i64 %a, %b\n"
    out << "  %m = and i64 %x, 281474976710655\n"
    out << "  %v = or i64 %m, -1688849860263936\n"
  else
    out << "  %v = " + llvm_op + " i64 %a, %b\n"
  out << "  ret i64 %v\n"
  out << "slow:\n"
  out << "  %sv = call i64 @" + slow_name + "(i64 %a, i64 %b)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out.to_s()

# Boxed * fast path: 48-bit payload multiply via llvm.smul.with.overflow
# (payload magnitudes < 2^47, so the i64 product can wrap) plus the i48 fit
# check; overflow promotes through w_mul (BigInt) exactly as before.
-> mul_fast_helper_ir()
  out = StringBuffer(760)
  out << "define private i64 @__w_mul_fast(i64 %a, i64 %b) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << int_pair_test_ir()
  out << "  br i1 %both, label %fast, label %slow, !prof !31411\n"
  out << "fast:\n"
  out << "  %sa = shl i64 %a, 16\n"
  out << "  %pa = ashr i64 %sa, 16\n"
  out << "  %sb = shl i64 %b, 16\n"
  out << "  %pb = ashr i64 %sb, 16\n"
  out << "  %rc = call { i64, i1 } @llvm.smul.with.overflow.i64(i64 %pa, i64 %pb)\n"
  out << "  %r = extractvalue { i64, i1 } %rc, 0\n"
  out << "  %ov = extractvalue { i64, i1 } %rc, 1\n"
  out << "  %rs = shl i64 %r, 16\n"
  out << "  %rb = ashr i64 %rs, 16\n"
  out << "  %fit48 = icmp eq i64 %rb, %r\n"
  out << "  %nov = xor i1 %ov, true\n"
  out << "  %ok = and i1 %fit48, %nov\n"
  out << "  br i1 %ok, label %box, label %slow, !prof !31411\n"
  out << "box:\n"
  out << "  %m = and i64 %r, 281474976710655\n"
  out << "  %v = or i64 %m, -1688849860263936\n"
  out << "  ret i64 %v\n"
  out << "slow:\n"
  out << "  %sv = call i64 @w_mul(i64 %a, i64 %b)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out.to_s()

# Boxed / and % fast paths. Both-inline-Int division is safe in i64 because
# the payload is only i48; the sole promoted quotient (INT48_MIN / -1) fails
# the common i48 fit check and falls back to w_div. A zero divisor also takes
# the slow path so the runtime remains the authority for the exact error.
-> divmod_fast_helper_ir(fast_name, slow_name, llvm_op)
  out = StringBuffer(820)
  out << "define private i64 @" + fast_name + "(i64 %a, i64 %b) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << int_pair_test_ir()
  out << "  br i1 %both, label %ints, label %slow, !prof !31411\n"
  out << "ints:\n"
  out << "  %sb = shl i64 %b, 16\n"
  out << "  %pb = ashr i64 %sb, 16\n"
  out << "  %nz = icmp ne i64 %pb, 0\n"
  out << "  br i1 %nz, label %fast, label %slow, !prof !31411\n"
  out << "fast:\n"
  out << "  %sa = shl i64 %a, 16\n"
  out << "  %pa = ashr i64 %sa, 16\n"
  out << "  %r = " + llvm_op + " i64 %pa, %pb\n"
  out << "  %rs = shl i64 %r, 16\n"
  out << "  %rb = ashr i64 %rs, 16\n"
  out << "  %fit = icmp eq i64 %rb, %r\n"
  out << "  br i1 %fit, label %box, label %slow, !prof !31411\n"
  out << "box:\n"
  out << "  %m = and i64 %r, 281474976710655\n"
  out << "  %v = or i64 %m, -1688849860263936\n"
  out << "  ret i64 %v\n"
  out << "slow:\n"
  out << "  %sv = call i64 @" + slow_name + "(i64 %a, i64 %b)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out.to_s()

# Boxed << / >> fast paths. `<<` is polymorphic (strbuf/string/array append)
# — the both-int tag check routes every non-int LHS to the runtime op
# untouched. shl needs a shift-back equality check (i64 wrap) plus the i48
# fit; overflow promotes via w_bit_shl (bignum_shl). ashr of a 48-bit value
# always fits, so >> only guards the count range; k >= 64 and negative
# counts (huge as unsigned) take the slow path, matching w_bit_shr.
-> shift_fast_helper_ir(fast_name, slow_name, is_shl)
  out = StringBuffer(860)
  out << "define private i64 @" + fast_name + "(i64 %a, i64 %b) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << int_pair_test_ir()
  out << "  br i1 %both, label %cnt, label %slow, !prof !31411\n"
  out << "cnt:\n"
  out << "  %sb = shl i64 %b, 16\n"
  out << "  %k = ashr i64 %sb, 16\n"
  if is_shl
    out << "  %kin = icmp ult i64 %k, 48\n"
  else
    out << "  %kin = icmp ult i64 %k, 64\n"
  out << "  br i1 %kin, label %fast, label %slow\n"
  out << "fast:\n"
  out << "  %sa = shl i64 %a, 16\n"
  out << "  %pa = ashr i64 %sa, 16\n"
  if is_shl
    out << "  %r = shl i64 %pa, %k\n"
    out << "  %back = ashr i64 %r, %k\n"
    out << "  %undo = icmp eq i64 %back, %pa\n"
    out << "  %rs = shl i64 %r, 16\n"
    out << "  %rb = ashr i64 %rs, 16\n"
    out << "  %fit48 = icmp eq i64 %rb, %r\n"
    out << "  %ok = and i1 %undo, %fit48\n"
    out << "  br i1 %ok, label %box, label %slow, !prof !31411\n"
    out << "box:\n"
  else
    out << "  %r = ashr i64 %pa, %k\n"
  out << "  %m = and i64 %r, 281474976710655\n"
  out << "  %v = or i64 %m, -1688849860263936\n"
  out << "  ret i64 %v\n"
  out << "slow:\n"
  out << "  %sv = call i64 @" + slow_name + "(i64 %a, i64 %b)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out.to_s()

# Inline box/unbox wrappers. w_int boxes a raw i64 (BigInt when it exceeds
# i48); w_to_i64 unboxes any integer box (limb-walking BigInts). The fast
# arms cover the ~always case — a fitting value / an inline-int box.
-> int_fast_helper_ir()
  out = StringBuffer(480)
  out << "define private i64 @__w_int_fast(i64 %v) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << "  %rs = shl i64 %v, 16\n"
  out << "  %rb = ashr i64 %rs, 16\n"
  out << "  %fit = icmp eq i64 %rb, %v\n"
  out << "  br i1 %fit, label %box, label %slow\n"
  out << "box:\n"
  out << "  %m = and i64 %v, 281474976710655\n"
  out << "  %r = or i64 %m, -1688849860263936\n"
  out << "  ret i64 %r\n"
  out << "slow:\n"
  out << "  %sv = call i64 @w_int(i64 %v)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out.to_s()

# Array-literal slot store: the literal was just allocated at exact size by
# w_array_new_uninit_sized (fresh, unaliased, start == 0, i < size), so the
# store is a bare slots[i] = val with no grow check or ebits dispatch.
# WArray layout: flags/ebits/pad (8B) start+size (8B at +4/+8) cap (+12),
# slots ptr at +16 (see runtime.h; static-asserted there).
-> array_lit_store_helper_ir()
  out = StringBuffer(480)
  out << "define private i64 @__w_array_lit_store(i64 %arr, i64 %i, i64 %val) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << "  %m = and i64 %arr, 140737488355312\n"
  out << "  %ap = inttoptr i64 %m to ptr\n"
  out << "  %sp = getelementptr inbounds i8, ptr %ap, i64 16\n"
  out << "  %slots = load ptr, ptr %sp\n"
  out << "  %ep = getelementptr inbounds i64, ptr %slots, i64 %i\n"
  out << "  store i64 %val, ptr %ep\n"
  out << "  ret i64 %arr\n"
  out << "}\n"
  out.to_s()

# Boxed-numeric -> raw double. The fast arm unboxes a double-tagged WValue
# (sub bias + bitcast); ints/Decimals/BigInts take the w_num_to_f64 call.
-> num_to_f64_fast_helper_ir()
  out = StringBuffer(480)
  out << "define private double @__w_num_to_f64_fast(i64 %v) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << "  %ub = sub i64 %v, 281474976710656\n"
  out << "  %isd = icmp ule i64 %ub, -4503599627370496\n"
  out << "  br i1 %isd, label %fast, label %slow, !prof !31411\n"
  out << "fast:\n"
  out << "  %d = bitcast i64 %ub to double\n"
  out << "  ret double %d\n"
  out << "slow:\n"
  out << "  %sv = call double @w_num_to_f64(i64 %v)\n"
  out << "  ret double %sv\n"
  out << "}\n"
  out.to_s()

-> to_i64_fast_helper_ir()
  out = StringBuffer(480)
  out << "define private i64 @__w_to_i64_fast(i64 %v) alwaysinline nounwind {\n"
  out << "entry:\n"
  out << "  %hi = lshr i64 %v, 48\n"
  out << "  %isi = icmp eq i64 %hi, 65530\n"
  out << "  br i1 %isi, label %fast, label %slow, !prof !31411\n"
  out << "fast:\n"
  out << "  %s = shl i64 %v, 16\n"
  out << "  %p = ashr i64 %s, 16\n"
  out << "  ret i64 %p\n"
  out << "slow:\n"
  out << "  %sv = call i64 @w_to_i64(i64 %v)\n"
  out << "  ret i64 %sv\n"
  out << "}\n"
  out.to_s()

# Fixed-width bit-count helpers used by core/bit_ops.w. Keep these as private
# always-inline wrappers instead of ordinary runtime calls: the public source
# methods remain interpreter/C-VM compatible through ccall_nobox, while native
# builds expose the exact LLVM operations even at -O0. For ctlz/cttz, false is
# the is_zero_poison flag, so zero has the source-level result 32/64.
-> bit_count_intrinsic_helper_ir(helper_name, intrinsic_name, width, zero_poison_arg)
  llvm_type = "i" + width.to_s()
  out = StringBuffer(420)
  out << "declare " + llvm_type + " @llvm." + intrinsic_name + "." + llvm_type + "(" + llvm_type
  if zero_poison_arg
    out << ", i1 immarg"
  out << ")\n"
  out << "define private i64 @" + helper_name + "(i64 %v) alwaysinline nounwind willreturn memory(none) {\n"
  out << "entry:\n"
  value = "%v"
  if width == 32
    out << "  %v32 = trunc i64 %v to i32\n"
    value = "%v32"
  out << "  %count = call " + llvm_type + " @llvm." + intrinsic_name + "." + llvm_type + "(" + llvm_type + " " + value
  if zero_poison_arg
    out << ", i1 false"
  out << ")\n"
  if width == 32
    out << "  %result = zext i32 %count to i64\n"
    out << "  ret i64 %result\n"
  else
    out << "  ret i64 %count\n"
  out << "}\n"
  out.to_s()
