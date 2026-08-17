# Emitter — renders WIRE IR to LLVM IR text
# Takes a WIRE module (from lowering) and produces a complete .ll file.

use runtime_types
use hashing
# LLVM name transliteration (llvm_safe_name) — shared with lowering via
# its own module so `use lib/emitter` STANDALONE (the emitter unit specs)
# is a complete program instead of fabricating dangling `__w_*` symbols
# that only die at link time.
use naming

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
  out << declare_fn_attrs("w_bigint_mul_builtin_exact", wv, wv2, "nounwind")
  out << declare_fn("w_mul", wv, wv2)
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

-> function_attr_text(frame_pointers, host_fn_attrs, preserve_debug_frames = false)
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
  if preserve_debug_frames
    out << " noinline \"disable-tail-calls\"=\"true\""
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
  if wire_get(inst, :src_line) != nil
    prefix = "notail call"
  cc = wire_get(inst, :call_conv)
  if cc != nil && cc != ""
    prefix = prefix + " " + cc
  prefix

-> range_metadata_suffix(inst, llvm_type)
  low = wire_get(inst, :range_low)
  high = wire_get(inst, :range_high)
  if low == nil || high == nil
    return ""
  ", !range !{" + llvm_type + " " + low.to_s() + ", " + llvm_type + " " + high.to_s() + "}"

# TBAA (type-based alias analysis) tags for typed-array access. The WArray
# header (start/size/slots-ptr) and the element data occupy disjoint memory —
# no byte is ever accessed as both — so tagging header loads and element
# loads/stores with distinct sibling TBAA types lets LLVM's LICM hoist the
# invariant header derefs (slots ptr @+16, start @+4) out of a hot loop that
# only reads/writes elements. This is sound even when the array is grown
# inside the loop: `push`/`unshift`/`clear` realloc via a runtime CALL, which
# is a memory barrier LICM will not hoist across, and any inline header store
# is untagged (may-alias-all), so the header load stays pinned exactly where a
# realloc could move slots/start. Node definitions are emitted once per module
# in emit_artifact (tbaa_metadata_defs()). IDs are high to avoid colliding with
# LLVM's auto-numbering of inline (!range) metadata.
-> tbaa_header_suffix()
  ", !tbaa !31416"
-> tbaa_elem_suffix()
  ", !tbaa !31417"
# Object instance-variable slots (WObject payload @ +8 + offset*8) are a distinct
# memory kind from array headers and array element data — an object and an array
# are always separate allocations, so an ivar load never aliases an array store.
# A dedicated TBAA type lets LICM/GVN hoist a `self.field` read across an array
# element store in the same loop (e.g. `arr[i] = self.base + i`). Field-vs-field
# is left may-alias (one scalar tag), which is all we need. `- data` view-field
# access stays UNTAGGED (may-alias-all) so a field reinterpreted through a view is
# never split into two disjoint types.
-> tbaa_ivar_suffix()
  ", !tbaa !31421"
# ebits (element type/width, header byte @+1) is fixed at allocation and never
# changes for an array's lifetime — unlike start/size/slots which realloc moves.
# So an ebits load is genuinely invariant: !invariant.load lets LLVM hoist the
# poly-array kind check out of a hot loop (and even across calls), collapsing
# per-access dispatch on an untyped receiver to a single check.
-> invariant_load_suffix()
  ", !invariant.load !31419"
-> tbaa_metadata_defs()
  o = StringBuffer(256)
  o << "\n!31414 = !{!\"tungsten_tbaa_root\"}\n"
  o << "!31415 = !{!\"warray_data\", !31414}\n"
  o << "!31418 = !{!\"warray_header\", !31414}\n"
  o << "!31416 = !{!31418, !31418, i64 0}\n"
  o << "!31417 = !{!31415, !31415, i64 0}\n"
  o << "!31419 = !{}\n"
  o << "!31420 = !{!\"object_field\", !31414}\n"
  o << "!31421 = !{!31420, !31420, i64 0}\n"
  # Guarded-i48 branch weights: the runtime/bigint arm is the exception.
  # LLVM uses these for block layout (cold code sinks out of the loop
  # body) and register allocation (spills move into the cold block); the
  # CPU's dynamic predictor is unaffected, so a bigint-phase accumulator
  # that takes the "unlikely" arm every pass pays nothing extra.
  o << "!31411 = !{!\"branch_weights\", i32 2000, i32 1}\n"
  o << "!31412 = !{!\"branch_weights\", i32 1, i32 2000}\n"
  o.to_s()

# Per-loop latch metadata (lowering stamps the latch :br):
#   novec:true   — loop-vectorizer opt-out for masked-index while loops
#                  (lowering/analysis.w loop_masked_array_index?)
#   unroll_count — `llvm.loop.unroll.count N` for carry-intrinsic loops
#                  (lowering/analysis.w loop_has_carry_intrinsic?); the
#                  carry flag spills across the back-edge (llvm.org
#                  #74493) and LLVM won't unroll these on its own —
#                  unrolling amortizes the spill (+25% for multi-limb add,
#                  +8% for multiply-accumulate on Apple M5). Vectorization stays
#                  ENABLED for these: novec measured neutral-to-harmful.
# Each marked latch gets its OWN distinct self-referential !llvm.loop node:
# LLVM uses the node as the loop's identity, and sharing one node across loops
# measurably degrades the unroller's output (6.7B vs 8.5B ops/s on the masked
# reduce). IDs run upward from 31423, above the fixed TBAA block; allocation
# follows render order, which is deterministic, so stage identity holds. The
# state is a top-level container mutated in place (rebinding a top-level name
# from a function shadows instead of writing through — see detect_target_memo).
novec_md_state = {kinds: []}

-> latch_loop_md_ref(kind, unroll_count = 0)
  ks = novec_md_state[:kinds]
  k = ks.size()
  ks.push([kind, unroll_count])
  (31423 + k * 2).to_s()

# One shared novec tuple plus a distinct loop node and, when applicable, an
# unroll-count tuple per marked latch. Per-loop tuples allow different tuning
# counts in one emitter process without sharing loop identity. Rendered AFTER
# all functions (emit_artifact's final concat), so the list is final. Emits
# nothing when no loop was marked.
-> novec_loop_md_defs()
  ks = novec_md_state[:kinds]
  n = ks.size()
  if n == 0
    return ""
  o = StringBuffer(64)
  any_novec = false
  i = 0
  while i < n
    kind = ks[i][0]
    if kind == :novec || kind == :both
      any_novec = true
    i += 1
  if any_novec
    o << "!31422 = !{!\"llvm.loop.vectorize.enable\", i1 false}\n"
  i = 0
  while i < n
    entry = ks[i]
    kind = entry[0]
    unroll_count = entry[1]
    id = (31423 + i * 2).to_s()
    unroll_id = (31424 + i * 2).to_s()
    if kind == :both
      o << "!" + unroll_id + " = !{!\"llvm.loop.unroll.count\", i32 " + unroll_count.to_s() + "}\n"
      o << "!" + id + " = distinct !{!" + id + ", !31422, !" + unroll_id + "}\n"
    elsif kind == :unroll
      o << "!" + unroll_id + " = !{!\"llvm.loop.unroll.count\", i32 " + unroll_count.to_s() + "}\n"
      o << "!" + id + " = distinct !{!" + id + ", !" + unroll_id + "}\n"
    else
      o << "!" + id + " = distinct !{!" + id + ", !31422}\n"
    i += 1
  o.to_s()

# Scoped no-alias metadata for fused elementwise workers (lowering stamps the
# loop's source loads / output store with ewscope:<site-id> — see
# fuse_ew_emit_range_loop). The output is the site's fresh malloc, provably
# disjoint from every source, but TBAA can't express it (all elements are
# warray_data), so without this -O3 versions the loop behind per-source
# runtime overlap checks. Per site: one distinct scope in a shared domain,
# referenced through a scope-list node; the store carries `!alias.scope`
# (it writes inside the scope) and the loads carry `!noalias` (they never
# touch the scope's memory). IDs live at 300000+ — far above the TBAA block
# and the novec range (31423+k), which would need ~270k stamped loops to
# collide. Deterministic: sites are numbered in lowering order and the map
# fills in render order.
ewscope_md_state = {ids: {}}

-> ewscope_list_id(sid)
  cached = ewscope_md_state[:ids][sid]
  if cached != nil
    return cached
  k = ewscope_md_state[:ids].size()
  list_id = (300001 + k * 2).to_s()
  ewscope_md_state[:ids][sid] = list_id
  list_id

-> ewscope_store_suffix(inst)
  if wire_get(inst, :ewscope) == nil
    return ""
  ", !alias.scope !" + ewscope_list_id(wire_get(inst, :ewscope))

-> ewscope_load_suffix(inst)
  if wire_get(inst, :ewscope) == nil
    return ""
  ", !noalias !" + ewscope_list_id(wire_get(inst, :ewscope))

-> ewscope_md_defs()
  n = ewscope_md_state[:ids].size()
  if n == 0
    return ""
  o = StringBuffer(96)
  o << "!299999 = distinct !{!299999, !\"tungsten.fusedew\"}\n"
  i = 0
  while i < n
    scope_id = (300000 + i * 2).to_s()
    list_id = (300001 + i * 2).to_s()
    o << "!" + scope_id + " = distinct !{!" + scope_id + ", !299999}\n"
    o << "!" + list_id + " = !{!" + scope_id + "}\n"
    i += 1
  o.to_s()

-> direct_range_metadata_suffix(llvm_type, low, high)
  ", !range !{" + llvm_type + " " + low.to_s() + ", " + llvm_type + " " + high.to_s() + "}"

-> wvalue_int_range_metadata_suffix(low, high)
  low_bits = (w_tag_int + low) ## i64
  high_bits = (w_tag_int + high) ## i64
  direct_range_metadata_suffix("i64", machine_i64_box(low_bits), machine_i64_box(high_bits))

-> wvalue_bool_range_metadata_suffix()
  direct_range_metadata_suffix("i64", w_false, w_true + 1)

-> wvalue_char_range_metadata_suffix()
  # Char WValues are the 0xFFFC tag with subtype 11 (bits 47..46).
  subtype_span = 70368744177664
  low_bits = (w_tag_char + subtype_span * 3) ## i64
  high_bits = (w_tag_char + subtype_span * 4) ## i64
  direct_range_metadata_suffix("i64", machine_i64_box(low_bits), machine_i64_box(high_bits))

-> wvalue_bool_call?(name)
  name in ("w_bool" "w_eq" "w_neq" "w_eq_lit" "w_neq_lit" "w_lt" "w_gt" "w_lte" "w_gte" "__w_eq_fast" "__w_neq_fast" "__w_eq_lit_fast" "__w_neq_lit_fast" "__w_lt_fast" "__w_gt_fast" "__w_lte_fast" "__w_gte_fast" "__w_eq0_big_fast" "__w_lt0_big_fast" "__w_gt0_big_fast" "__w_lte0_big_fast" "__w_gte0_big_fast" "__w_streq_fast" "__w_streq2_fast" "w_hash_has_key" "__w_file_exists" "__w_write_file" "w_ipv4_in_cidr")

-> known_call_range_metadata_suffix(inst, llvm_type)
  suffix = range_metadata_suffix(inst, llvm_type)
  if suffix != ""
    return suffix
  if llvm_type == "i64"
    name = wire_get(inst, :name)
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
  wire_kind(inst) == :call_method_i64 && wire_get(inst, :args) != nil && wire_get(inst, :args).size() == 1 && wire_get(inst, :scalar_source_argc1) == true

-> scalar_source_two_call?(inst)
  wire_kind(inst) == :call_method_i64 && wire_get(inst, :args) != nil && wire_get(inst, :args).size() == 2 && wire_get(inst, :scalar_source_argc2) == true

-> scalar_source_call?(inst)
  scalar_source_one_call?(inst) || scalar_source_two_call?(inst)

# Return the runtime function names that an instruction will reference when rendered.
-> runtime_fns_for_inst(inst, string_wvs = nil)
  case wire_kind(inst)
  when :call_direct_i64, :call_direct_i128, :call_direct_void, :call_direct_ptr
    # w_node_field_store renders as inline slab IR when the offset is a
    # literal, and that IR calls the array-freeze helper directly — the
    # helper never appears as an instruction, so declare it alongside.
    if wire_get(inst, :name) == "w_node_field_store"
      return ["w_node_field_store", "w_ast_freeze_if_array"]
    [wire_get(inst, :name)]
  when :slab_alloc_init
    # The intrinsic's emitted IR calls w_node_alloc (cap-exhausted slow
    # path) and w_ast_freeze_if_array (field freeze pre-pass) as raw
    # strings — neither appears as a :call_direct instruction.
    ["w_node_alloc", "w_ast_freeze_if_array"]
  when :call_direct_i64_ptr1, :call_direct_void_ptr1
    [wire_get(inst, :name)]
  when :bigint_literal_i64
    ["w_bigint_literal_cached"]
  when :call_libm_f64
    [wire_get(inst, :name)]
  when :call_num_to_f64
    ["w_num_to_f64"]
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
  when :view_load_field, :view_store_field, :view_load_inline_byte, :view_load_inline_elem, :view_store_inline_elem
    # Named fields stay in their declared machine representation; lowering
    # inserts boxing only when the value crosses a WValue boundary.
    []
  when :register_unit
    if string_wvs != nil && string_wvs[wire_get(inst, :str_id)] != nil
      ["w_register_unit_wv"]
    else
      ["w_string", "w_register_unit_wv"]

  when :class_new, :builtin_class_init
    if string_wvs != nil && string_wvs[wire_get(inst, :name_str_id)] != nil
      ["w_class_new_wv"]
    else
      ["w_string", "w_class_new_wv"]
  when :class_add_method
    splat_method = wire_get(inst, :splat_index) != nil && wire_get(inst, :splat_index) >= 0
    range_method = wire_get(inst, :min_arity) != nil && wire_get(inst, :min_arity) < wire_get(inst, :arity)
    add_name = splat_method ? "w_class_add_method_splat_wv" : (range_method ? "w_class_add_method_range_wv" : "w_class_add_method_wv")
    if string_wvs != nil && string_wvs[wire_get(inst, :method_str_id)] != nil
      [add_name]
    else
      ["w_string", add_name]
  when :class_add_static_method
    splat_method = wire_get(inst, :splat_index) != nil && wire_get(inst, :splat_index) >= 0
    range_method = wire_get(inst, :min_arity) != nil && wire_get(inst, :min_arity) < wire_get(inst, :arity)
    add_name = splat_method ? "w_class_add_static_method_splat_wv" : (range_method ? "w_class_add_static_method_range_wv" : "w_class_add_static_method_wv")
    if string_wvs != nil && string_wvs[wire_get(inst, :method_str_id)] != nil
      [add_name]
    else
      ["w_string", add_name]
  when :class_add_ivar
    if string_wvs != nil && string_wvs[wire_get(inst, :ivar_str_id)] != nil
      ["w_class_add_ivar_wv"]
    else
      ["w_string", "w_class_add_ivar_wv"]

  when :ivar_get
    if string_wvs != nil && string_wvs[wire_get(inst, :str_id)] != nil
      ["w_ivar_get_wv"]
    else
      ["w_string", "w_ivar_get_wv"]
  when :ivar_set
    if string_wvs != nil && string_wvs[wire_get(inst, :str_id)] != nil
      ["w_ivar_set_wv"]
    else
      ["w_string", "w_ivar_set_wv"]

  when :call_method_i64
    runtime_fns = []
    argc = 0
    if wire_get(inst, :args) != nil
      argc = wire_get(inst, :args).size()
    if argc == 0
      runtime_fns.push("w_method_call_cached_0")
    elsif scalar_source_one_call?(inst)
      runtime_fns.push("w_method_call_cached_1")
    elsif scalar_source_two_call?(inst)
      runtime_fns.push("w_method_call_cached_2")
    else
      runtime_fns.push("w_method_call_cached")
    if wire_get(inst, :construct_fn) != nil
      runtime_fns.push("w_object_new")
    runtime_fns
  when :closure_new
    ["w_closure_new_a"]
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
    # POSIX uses _setjmp (matching the runtime's _longjmp) while Windows uses
    # setjmp. Keep both declarations through filtering; render_instruction
    # selects the target-correct symbol.
    ["setjmp", "_setjmp"]

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
    [wire_get(inst, :rt_fallback)]
  when :add_i48_guarded, :sub_i48_guarded, :mul_i48_guarded
    [wire_get(inst, :rt_fallback)]
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
        if wire_get(inst, :src_line) != nil
          ret_label = nil
          if wire_kind(inst) == :call_method_i64
            ret_label = "cs." + wire_get(inst, :ic_id).to_s() + ".ret"
          elsif wire_kind(inst) in (:call_direct_void :call_direct_i64) && wire_get(inst, :loc_site_id) != nil
            ret_label = "csd." + wire_get(inst, :loc_site_id).to_s() + ".ret"
          if ret_label != nil
            file_id = files[fn_path]
            if file_id == nil
              file_id = next_file_id
              files[fn_path] = file_id
              next_file_id = next_file_id + 1
            col_val = wire_get(inst, :src_col)
            if col_val == nil
              col_val = 0
            sites.push({
              fn_name: f[:name],
              ret_label: ret_label,
              file_id: file_id,
              line: wire_get(inst, :src_line),
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

  # One private constant per unique source file path. Ids are assigned
  # first-seen, so the hash's insertion order IS id order (spec §4.2.3).
  file_keys = files.keys()
  fi = 0
  while fi < file_keys.size()
    k = file_keys[fi]
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
  op = wire_kind(inst)
  if op in (:class_add_method :class_add_static_method :closure_new)
    return wire_get(inst, :fn_name)
  if op in (:memo_call0_i64 :memo_call1_i64 :memo_call2_i64)
    return wire_get(inst, :fn_name)
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
  if func[:incremental_core_candidate] == true || func[:incremental_core_frozen] == true
    return false
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
        if fastcc_direct_call_op?(wire_kind(inst)) && fastcc_names[wire_get(inst, :name)] == true
          wire_set(inst, :call_conv, "fastcc")
        ii += 1
      bi += 1
    fi += 1

  mod[:fastcc_count] = count
  nil

# A direct external call has one physical LLVM contract per symbol. Before
# declarations are rendered, reject WIRE that asks the same symbol to return a
# different type or accept a different physical argument list. This catches
# the historical "first call wins" behavior in ccall_needed, where a later
# mismatch survived lowering and failed only in LLVM (or linked with a wrong C
# ABI when the declaration lived in another translation unit).
-> wire_direct_call_contract(inst)
  op = wire_kind(inst)
  return_type = nil
  arg_types = []
  if op == :call_direct_i64
    return_type = "i64"
  elsif op == :call_direct_i128
    return_type = "i128"
  elsif op == :call_direct_void
    return_type = "void"
  elsif op == :call_direct_ptr
    return_type = "ptr"
  elsif op == :call_direct_i64_ptr1
    return "i64(ptr)"
  elsif op == :call_direct_void_ptr1
    return "void(ptr)"
  else
    return nil

  args = wire_get(inst, :args)
  if args == nil
    args = []
  declared_types = wire_get(inst, :arg_types)
  i = 0
  while i < args.size()
    arg_type = nil
    if declared_types != nil && i < declared_types.size()
      arg_type = declared_types[i]
    if arg_type == nil || arg_type == ""
      arg_type = "i64"
    arg_types.push(arg_type)
    i += 1
  return_type + "(" + arg_types.join(",") + ")"

-> wire_fn_hash_get(fn_hashes, source)
  entry = fn_hashes[source]
  if entry == nil || entry[:source] == nil || entry[:source].size() != source.size() || entry[:source] != source
    return nil
  entry[:hash]

-> wire_hash_symbol_get(hash_symbols, hash)
  entry = hash_symbols[hash]
  if entry == nil || entry[:hash] == nil || entry[:hash].size() != hash.size() || entry[:hash] != hash
    return nil
  entry[:symbol]

-> wire_symbol_origins(mod, symbol)
  out = []
  hashes = mod[:fn_hashes]
  symbols = mod[:fn_hash_symbols]
  if hashes == nil || symbols == nil
    return out
  names = hashes.keys()
  i = 0
  while i < names.size()
    hash = wire_fn_hash_get(hashes, names[i])
    if wire_hash_symbol_get(symbols, hash) == symbol
      out.push(names[i] + "=" + hash)
    i += 1
  out

-> verify_wire_call_contracts(mod)
  contracts = {}
  target_details = {}
  tfi = 0
  while tfi < mod[:functions].size()
    target_func = mod[:functions][tfi]
    target_name = target_func[:original_name]
    if target_name == nil
      target_name = target_func[:name]
    target_arity = 0
    if target_func[:params] != nil
      target_arity = target_func[:params].size()
    target_details[target_func[:name]] = target_name + "/" + target_arity.to_s()
    tfi += 1
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    bi = 0
    while bi < func[:blocks].size()
      instructions = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instructions.size()
        inst = instructions[ii]
        contract = wire_direct_call_contract(inst)
        if contract != nil && wire_get(inst, :name) != nil
          prior = contracts[wire_get(inst, :name)]
          if prior != nil && prior[:contract] != contract
            prior_name = prior[:function]
            current_name = func[:original_name]
            if current_name == nil
              current_name = func[:name]
            target_detail = target_details[wire_get(inst, :name)]
            if target_detail == nil
              target_detail = "external"
            origins = wire_symbol_origins(mod, wire_get(inst, :name))
            origin_detail = ""
            if origins.size() > 0
              origin_detail = "; origins " + origins.join(", ")
            return "WIRE call contract mismatch for @" + wire_get(inst, :name) + " (" + target_detail + origin_detail + "): " + prior[:contract] + " in @" + prior_name + " vs " + contract + " in @" + current_name
          current_name = func[:original_name]
          if current_name == nil
            current_name = func[:name]
          contracts[wire_get(inst, :name)] = {contract: contract, function: current_name}
        ii += 1
      bi += 1
    fi += 1
  nil

-> emit_artifact(mod, frame_pointers = false)
  wire_contract_error = verify_wire_call_contracts(mod)
  if wire_contract_error != nil
    << "error: " + wire_contract_error
    exit(1)

  # Per-module metadata state MUST reset here: both containers are
  # process-global (top-level rebinding from a function would shadow, so
  # they are mutated in place) and survive across compiles in one
  # process. Without the reset, compile-batch's program N re-emits every
  # prior program's loop-metadata nodes (novec bloat) and — worse —
  # ewscope's cache is keyed by mod[:next_fuse_site] ids that restart at
  # 0 per module, so program N's fused loop 0 would REUSE program N-1's
  # !alias.scope/!noalias list: unrelated loops sharing a no-alias scope
  # is a miscompile, not bloat.
  novec_md_state[:kinds] = []
  ewscope_md_state[:ids] = {}

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
        if wire_kind(inst) == :call_direct_i64 && wire_get(inst, :name) != nil
          iname = wire_get(inst, :name)
          if !known_fns.has_key?(iname) && !ccall_needed.has_key?(iname)
            ccall_needed[iname] = wire_get(inst, :args).size()
        if wire_kind(inst) == :call_num_to_f64 && !ccall_needed.has_key?("__w_num_to_f64_fast")
          ccall_needed["__w_num_to_f64_fast"] = 1
        fns = runtime_fns_for_inst(inst, mod[:string_wvalues])
        if fns != nil
          ri = 0
          while ri < fns.size()
            used_runtime_fns[fns[ri]] = true
            ri += 1
        ii += 1
      bi += 1
    # Heap capture cells are materialized at render time (entry-block slot
    # emission), not as WIRE instructions, so the scan above cannot see them.
    if wfunc[:heap_slot_names] != nil
      used_runtime_fns["w_closure_cell_new"] = true
    fi += 1
  globals_out = StringBuffer(4096)

  # Immutable BigInt source literals publish into one process-lifetime slot
  # apiece.  The zero sentinel is W_NIL and cannot be a lowered over-i64
  # literal; the C runtime performs the atomic first-use publication.
  bigint_literal_count = mod[:next_bigint_literal]
  if bigint_literal_count != nil && bigint_literal_count > 0
    bli = 0
    while bli < bigint_literal_count
      globals_out << "@.bigint.literal."
      globals_out << bli.to_s()
      globals_out << " = internal global i64 0, align 8\n"
      bli += 1
    globals_out << "\n"

  # Memo table globals, in first-use order (hash insertion order).
  memo_tables = mod[:fn_memo_tables]
  if memo_tables != nil
    memo_keys = mod[:used_memo_tables]
    if memo_keys == nil
      memo_keys = memo_tables
    memo_keys = memo_keys.keys()
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
    class_keys = classes.keys()
    ck = 0
    while ck < class_keys.size()
      globals_out << "@class."
      globals_out << llvm_safe_name(class_keys[ck].gsub(":", "__"))
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
    tlv_keys = tlv.keys()
    ti = 0
    while ti < tlv_keys.size()
      nm = tlv_keys[ti]
      globals_out << "@global."
      globals_out << llvm_safe_name(nm)
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
    cvg_keys = cvg.keys()
    ci = 0
    while ci < cvg_keys.size()
      globals_out << "@cvar."
      globals_out << llvm_safe_name(cvg_keys[ci].gsub(":", "__"))
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

  # Compile-time SmallArray constants. Each
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
    fn_out << emit_function(mod[:functions][i], mod[:string_wvalues], slab_info, used_ptr_ids, frame_pointers, mod[:llvm_fn_attrs], attr_groups, emit_target_is_arm64(mod), emit_target_is_windows(mod), mod[:preserve_debug_frames] == true)
    fn_out << "\n"
    i += 1

  # Source-routed operator export: wrap the selected content-hash-renamed
  # source body in a STRONG stable-named symbol. The runtime declares the same
  # symbol WEAK with the C kernel as its bootstrap default, so strong-over-weak
  # link resolution selects source and remains transparent to whole-program
  # LTO. A genuinely reopened plain operator wins for its BigInt receiver,
  # exactly as it does in the method table. Complete bitwise arithmetic for
  # the remaining domain uses the reserved raw support helpers below rather
  # than the shape-limited class workers.
  big_op_wrappers = {"+" => "__w_bigint_plus_src", "-" => "__w_bigint_minus_src", "*" => "__w_bigint_times_src", "&" => "__w_bigint_and_src", "|" => "__w_bigint_or_src", "^" => "__w_bigint_xor_src", "/" => "__w_bigint_div_src", "%" => "__w_bigint_mod_src", "<<" => "__w_bigint_shl_src", ">>" => "__w_bigint_shr_src"}
  # B2: the seam target per op, in preference order —
  #   1. the LAST plain-named body (source_method exactly the public operator,
  #      not the synthesized dispatcher): core itself has no such
  #      body, so one existing means a program REOPENED the operator, and
  #      it must win the seam for a BigInt left-hand receiver exactly as it
  #      wins the method table;
  #   2. for &, |, and ^, the complete reserved raw helper;
  #   3. for the remaining ops, the typed overload worker: the fast body
  #      behind the dispatcher gate. The seam binds it DIRECTLY —
  #      bigint_src_shape already proved both operands, so routing
  #      through the dispatcher would re-test what the arm knows.
  # The dispatcher itself is never wrapped (fn[:overload_dispatcher]).
  big_op_worker_names = {"+__ovl_BigInt" => "+", "-__ovl_BigInt" => "-", "*__ovl_BigInt" => "*", "&__ovl_BigInt" => "&", "|__ovl_BigInt" => "|", "^__ovl_BigInt" => "^", "/__ovl_BigInt" => "/", "%__ovl_BigInt" => "%", "<<__ovl_Int" => "<<", ">>__ovl_Int" => ">>"}

  # Full bitwise arithmetic is supplied by root-injected raw-ABI helpers. The
  # names are reserved so application code cannot silently replace support or
  # leave two ambiguous definitions. Validate all three before choosing seam
  # targets: every helper takes two raw i64 WValue bit patterns and returns one
  # raw i64 WValue bit pattern.
  bitwise_raw_helper_ops = {"__bigint_and_raw" => "&", "__bigint_or_raw" => "|", "__bigint_xor_raw" => "^"}
  bitwise_raw_helper_names = {"&" => "__bigint_and_raw", "|" => "__bigint_or_raw", "^" => "__bigint_xor_raw"}
  bitwise_raw_fns = {}
  bitwise_raw_matches = {}
  bitwise_raw_complete = true
  brfi = 0
  while brfi < mod[:functions].size()
    brff = mod[:functions][brfi]
    if brff[:source_class] == nil
      brop = bitwise_raw_helper_ops[brff[:source_method]]
      if brop != nil
        brcount = bitwise_raw_matches[brop]
        if brcount == nil
          brcount = 0
        bitwise_raw_matches[brop] = brcount + 1
        bitwise_raw_fns[brop] = brff
    brfi += 1
  bitwise_bop_keys = ["&", "|", "^"]
  brki = 0
  while brki < bitwise_bop_keys.size()
    brop = bitwise_bop_keys[brki]
    brki += 1
    brname = bitwise_raw_helper_names[brop]
    brmatches = bitwise_raw_matches[brop]
    if brmatches != nil && brmatches > 1
      << "error: " + brname + " is reserved for native BigInt bitwise support"
      exit(1)
    brfn = bitwise_raw_fns[brop]
    if mod[:require_bigint_bitwise_src] == true && brfn == nil
      brmissing = "error: required native BigInt bitwise helper " + brname
      brmissing = brmissing + " is missing; " + big_op_wrappers[brop]
      << brmissing + " would bind the weak C bootstrap default"
      exit(1)
    if brfn == nil
      bitwise_raw_complete = false
    if brfn != nil
      br_signature_ok = brfn[:source_kind] == :fn_def
      br_signature_ok = br_signature_ok && brfn[:raw_i64_signature] == true
      br_signature_ok = br_signature_ok && brfn[:raw_return_type] == :i64
      br_signature_ok = br_signature_ok && brfn[:params] != nil
      if br_signature_ok
        br_signature_ok = brfn[:params].size() == 2
      if !br_signature_ok
        << "error: invalid reserved native BigInt bitwise helper " + brname
        exit(1)

  # Consumed compound assignment has a distinct ABI: the source helper may
  # trade the dead receiver's storage for the result, while the stable public
  # seam uses preserve_mostcc. Compound assignment is language-defined rather
  # than overload dispatch, so no class worker/reopen can replace these three
  # reserved helpers.
  bitwise_mut_raw_helper_ops = {"__bigint_and_mut_raw" => "&", "__bigint_or_mut_raw" => "|", "__bigint_xor_mut_raw" => "^"}
  bitwise_mut_raw_helper_names = {"&" => "__bigint_and_mut_raw", "|" => "__bigint_or_mut_raw", "^" => "__bigint_xor_mut_raw"}
  bitwise_mut_wrappers = {"&" => "__w_bigint_and_mut_src", "|" => "__w_bigint_or_mut_src", "^" => "__w_bigint_xor_mut_src"}
  bitwise_mut_raw_fns = {}
  bitwise_mut_raw_matches = {}
  bmfi = 0
  while bmfi < mod[:functions].size()
    bmff = mod[:functions][bmfi]
    if bmff[:source_class] == nil
      bmop = bitwise_mut_raw_helper_ops[bmff[:source_method]]
      if bmop != nil
        bmcount = bitwise_mut_raw_matches[bmop]
        if bmcount == nil
          bmcount = 0
        bitwise_mut_raw_matches[bmop] = bmcount + 1
        bitwise_mut_raw_fns[bmop] = bmff
    bmfi += 1
  bmki = 0
  while bmki < bitwise_bop_keys.size()
    bmop = bitwise_bop_keys[bmki]
    bmki += 1
    bmname = bitwise_mut_raw_helper_names[bmop]
    bmmatches = bitwise_mut_raw_matches[bmop]
    if bmmatches != nil && bmmatches > 1
      << "error: " + bmname + " is reserved for native consumed BigInt bitwise support"
      exit(1)
    bmfn = bitwise_mut_raw_fns[bmop]
    if mod[:require_bigint_bitwise_mut_src] == true && bmfn == nil
      bmmissing = "error: required native consumed BigInt bitwise helper " + bmname
      bmmissing = bmmissing + " is missing; " + bitwise_mut_wrappers[bmop]
      << bmmissing + " would bind the weak C bootstrap default"
      exit(1)
    if bmfn != nil
      bm_signature_ok = bmfn[:source_kind] == :fn_def
      bm_signature_ok = bm_signature_ok && bmfn[:raw_i64_signature] == true
      bm_signature_ok = bm_signature_ok && bmfn[:raw_return_type] == :i64
      bm_signature_ok = bm_signature_ok && bmfn[:params] != nil
      if bm_signature_ok
        bm_signature_ok = bmfn[:params].size() == 2
      if !bm_signature_ok
        << "error: invalid reserved native consumed BigInt bitwise helper " + bmname
        exit(1)

  # A strong marker distinguishes the complete immutable raw-helper family
  # from older binaries whose same-named operator seams wrapped only partial
  # class workers. Consumed seams fail closed independently above.
  if bitwise_raw_complete
    fn_out << "define i64 @__w_bigint_bitwise_source_complete() nounwind {\n"
    fn_out << "  ret i64 1\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_bitwise_source_complete"] = false
    known_fns["__w_bigint_bitwise_source_complete"] = true

  # Stable consumed seams are preserve_mostcc by contract. The selected raw
  # helper may itself be fastcc after the internal calling-convention plan;
  # spell that convention on the tail call independently of the public ABI.
  bmwi = 0
  while bmwi < bitwise_bop_keys.size()
    bmop = bitwise_bop_keys[bmwi]
    bmwi += 1
    bmfn = bitwise_mut_raw_fns[bmop]
    if bmfn != nil
      bmtarget_cc = ""
      if bmfn[:call_conv] != nil && bmfn[:call_conv] != ""
        bmtarget_cc = bmfn[:call_conv] + " "
      bmwrapper = bitwise_mut_wrappers[bmop]
      fn_out << "define preserve_mostcc i64 @" + bmwrapper + "(i64 %a, i64 %b) nounwind {\n"
      fn_out << "  %r = tail call " + bmtarget_cc + "i64 @" + bmfn[:name] + "(i64 %a, i64 %b)\n"
      fn_out << "  ret i64 %r\n"
      fn_out << "}\n\n"
      used_runtime_fns[bmwrapper] = false
      known_fns[bmwrapper] = true

  big_op_fns = {}
  big_op_worker_fns = {}
  big_op_dispatchers = {}
  bfi = 0
  while bfi < mod[:functions].size()
    bff = mod[:functions][bfi]
    if bff[:source_class] == "BigInt" && bff[:source_kind] == :method
      bfm = bff[:source_method]
      if big_op_wrappers[bfm] != nil
        if bff[:overload_dispatcher] == true
          big_op_dispatchers[bfm] = true
        else
          big_op_fns[bfm] = bff
      elsif big_op_worker_names[bfm] != nil
        big_op_worker_fns[big_op_worker_names[bfm]] = bff
    bfi += 1
  # Preserve the plain-reopen choice before the worker fallback below fills
  # the same table.  The exact positive 1-by-1 subtraction seam uses this
  # value so a user reopen retains ordinary method-table precedence.
  bigint_minus_reopened_fn = big_op_fns["-"]
  bigint_times_reopened_fn = big_op_fns["*"]
  # T3 build assertion: a module that synthesized a BigInt operator
  # dispatcher but yields no seam target has broken the wrapper keying —
  # the strong symbol would silently fall to the runtime's weak C default
  # and the whole migration would revert with every gate reading green.
  bo_keys = big_op_wrappers.keys()
  boi = 0
  while boi < bo_keys.size()
    bop_check = bo_keys[boi]
    if big_op_dispatchers[bop_check] == true && big_op_fns[bop_check] == nil && big_op_worker_fns[bop_check] == nil && bitwise_raw_fns[bop_check] == nil
      << "error: BigInt#" + bop_check + " lowered a dispatcher but no seam target; __w_bigint_*_src would bind the weak C default"
      exit(1)
    # The complete raw helper owns &, |, and ^ unless a plain BigInt operator
    # body genuinely reopens that public method. Do not fall back to the old
    # shape-limited typed worker, which would create a duplicate/partial seam.
    if big_op_fns[bop_check] == nil && bitwise_raw_fns[bop_check] == nil
      big_op_fns[bop_check] = big_op_worker_fns[bop_check]
    boi += 1
  seam_decls = StringBuffer(256)
  # FIXED iteration order, never .keys(): hash iteration order differs
  # between the C VM stage-0 host and the native compiler, and the seam
  # wrappers' emission order otherwise swaps between stage 1 and stage 2
  # (an 8-line byte-identity break that only surfaces under --force).
  bop_keys = ["+", "-", "*", "&", "|", "^", "/", "%", "<<", ">>"]
  bki = 0
  while bki < bop_keys.size()
    bop = bop_keys[bki]
    bki += 1
    bigop = big_op_fns[bop]
    bitwise_raw = bitwise_raw_fns[bop]
    bitwise_reopened = bitwise_raw != nil && bigop != nil
    if bigop == nil
      bigop = bitwise_raw
    if bigop != nil
      bp_cc = ""
      if bigop[:call_conv] != nil && bigop[:call_conv] != ""
        bp_cc = bigop[:call_conv] + " "
      fn_out << "define i64 @" + big_op_wrappers[bop] + "(i64 %a, i64 %b) nounwind {\n"
      if bitwise_reopened
        # The stable bitwise seam accepts the complete integer-pair domain,
        # including `inline op BigInt`. A plain BigInt reopen is an instance
        # override and may only receive a BigInt left-hand receiver; reverse
        # mixed pairs stay on the complete raw helper.
        br_cc = ""
        if bitwise_raw[:call_conv] != nil && bitwise_raw[:call_conv] != ""
          br_cc = bitwise_raw[:call_conv] + " "
        fn_out << "  %a.tag = and i64 %a, -281474976710656\n"
        fn_out << "  %a.is_bigint = icmp eq i64 %a.tag, -1407374883553280\n"
        fn_out << "  br i1 %a.is_bigint, label %reopened, label %raw\n"
        fn_out << "reopened:\n"
        fn_out << "  %r.reopened = tail call " + bp_cc + "i64 @" + bigop[:name] + "(i64 %a, i64 %b)\n"
        fn_out << "  ret i64 %r.reopened\n"
        fn_out << "raw:\n"
        fn_out << "  %r.raw = tail call " + br_cc + "i64 @" + bitwise_raw[:name] + "(i64 %a, i64 %b)\n"
        fn_out << "  ret i64 %r.raw\n"
      else
        fn_out << "  %r = tail call " + bp_cc + "i64 @" + bigop[:name] + "(i64 %a, i64 %b)\n"
        fn_out << "  ret i64 %r\n"
      fn_out << "}\n\n"
      # This module DEFINES the seam, so no declaration may be emitted for
      # it — from the runtime list OR from the ccall auto-declare path,
      # which keys off known_fns (the wrapper is raw text, so register it).
      used_runtime_fns[big_op_wrappers[bop]] = false
      known_fns[big_op_wrappers[bop]] = true
    elsif used_runtime_fns[big_op_wrappers[bop]] == true
      # Direct-lowered call sites exist but this module does not compile
      # BigInt#+/#-; declare the seam so it binds at link time (to the
      # runtime's weak C-kernel default, or to whichever object defines it).
      seam_decls << "declare i64 @" + big_op_wrappers[bop] + "(i64, i64) nounwind\n"

  # Exact positive one-limb subtraction has a narrower stable seam than the
  # complete BigInt#- worker.  w_sub has already proved the two positive
  # one-limb heap shapes before entering it, so the strong Core definition can
  # tail-call the raw source helper without re-running the typed method body.
  # A genuine plain BigInt#- reopen still wins, exactly as for the general
  # __w_bigint_minus_src seam.  Stage0/C-only links bind the runtime's weak
  # exact-C default.
  bigint_sub1_1_fn = nil
  bigint_sub1_1_matches = 0
  bsfi = 0
  while bsfi < mod[:functions].size()
    bsff = mod[:functions][bsfi]
    if bsff[:source_class] == nil && bsff[:source_method] == "__bigint_sub1_1_raw"
      bigint_sub1_1_matches += 1
      bigint_sub1_1_fn = bsff
    bsfi += 1
  if bigint_sub1_1_matches > 1
    << "error: __bigint_sub1_1_raw is reserved for native BigInt subtraction"
    exit(1)
  if mod[:require_bigint_sub1_1_src] == true && bigint_sub1_1_fn == nil
    << "error: required native BigInt sub1@1 helper is missing; __w_bigint_sub1_1_src would bind the weak C bootstrap default"
    exit(1)
  bigint_sub1_1_target = bigint_minus_reopened_fn
  if bigint_sub1_1_target == nil
    bigint_sub1_1_target = bigint_sub1_1_fn
  if bigint_sub1_1_target != nil
    bs_signature_ok = bigint_sub1_1_target[:params] != nil && bigint_sub1_1_target[:params].size() == 2
    if bigint_minus_reopened_fn == nil
      bs_signature_ok = bs_signature_ok && bigint_sub1_1_target[:source_kind] == :fn_def
      bs_signature_ok = bs_signature_ok && bigint_sub1_1_target[:raw_i64_signature] == true
      bs_signature_ok = bs_signature_ok && bigint_sub1_1_target[:raw_return_type] == :i64
    if !bs_signature_ok
      << "error: invalid native BigInt sub1@1 seam target"
      exit(1)
    bs_cc = ""
    if bigint_sub1_1_target[:call_conv] != nil && bigint_sub1_1_target[:call_conv] != ""
      bs_cc = bigint_sub1_1_target[:call_conv] + " "
    fn_out << "define i64 @__w_bigint_sub1_1_src(i64 %a, i64 %b) nounwind {\n"
    fn_out << "  %r = tail call " + bs_cc + "i64 @" + bigint_sub1_1_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_sub1_1_src"] = false
    known_fns["__w_bigint_sub1_1_src"] = true
  elsif used_runtime_fns["__w_bigint_sub1_1_src"] == true
    seam_decls << "declare i64 @__w_bigint_sub1_1_src(i64, i64) nounwind\n"

  # The exact positive 2-by-1 word-subtract port has the same narrow seam
  # contract as sub1@1: w_sub proves the shape, Core supplies the raw worker,
  # and a genuine plain BigInt#- reopen retains precedence over both seams.
  bigint_sub1_2_fn = nil
  bigint_sub1_2_matches = 0
  bstfi = 0
  while bstfi < mod[:functions].size()
    bstff = mod[:functions][bstfi]
    if bstff[:source_class] == nil && bstff[:source_method] == "__bigint_sub1_2_raw"
      bigint_sub1_2_matches += 1
      bigint_sub1_2_fn = bstff
    bstfi += 1
  if bigint_sub1_2_matches > 1
    << "error: __bigint_sub1_2_raw is reserved for native BigInt subtraction"
    exit(1)
  if mod[:require_bigint_sub1_2_src] == true && bigint_sub1_2_fn == nil
    << "error: required native BigInt sub1@2 helper is missing; __w_bigint_sub1_2_src would bind the weak C bootstrap default"
    exit(1)
  bigint_sub1_2_target = bigint_minus_reopened_fn
  if bigint_sub1_2_target == nil
    bigint_sub1_2_target = bigint_sub1_2_fn
  if bigint_sub1_2_target != nil
    bst_signature_ok = bigint_sub1_2_target[:params] != nil && bigint_sub1_2_target[:params].size() == 2
    if bigint_minus_reopened_fn == nil
      bst_signature_ok = bst_signature_ok && bigint_sub1_2_target[:source_kind] == :fn_def
      bst_signature_ok = bst_signature_ok && bigint_sub1_2_target[:raw_i64_signature] == true
      bst_signature_ok = bst_signature_ok && bigint_sub1_2_target[:raw_return_type] == :i64
    if !bst_signature_ok
      << "error: invalid native BigInt sub1@2 seam target"
      exit(1)
    bst_cc = ""
    if bigint_sub1_2_target[:call_conv] != nil && bigint_sub1_2_target[:call_conv] != ""
      bst_cc = bigint_sub1_2_target[:call_conv] + " "
    bst_attrs = " nounwind"
    if bigint_minus_reopened_fn == nil
      bst_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_sub1_2_src(i64 %a, i64 %b)" + bst_attrs + " {\n"
    fn_out << "  %r = tail call " + bst_cc + "i64 @" + bigint_sub1_2_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_sub1_2_src"] = false
    known_fns["__w_bigint_sub1_2_src"] = true
  elsif used_runtime_fns["__w_bigint_sub1_2_src"] == true
    seam_decls << "declare i64 @__w_bigint_sub1_2_src(i64, i64) nounwind\n"

  # Exact positive one-limb multiplication follows the same narrow contract:
  # w_mul proves either two distinct positive one-limb heap operands or C's
  # raw-positive-header one-limb square, Core supplies the raw arithmetic
  # worker, and a genuine plain BigInt#* reopen keeps ordinary method-table
  # precedence. Stage0/C-only links bind the weak exact C default.
  bigint_mul1_1_fn = nil
  bigint_mul1_1_matches = 0
  bm1fi = 0
  while bm1fi < mod[:functions].size()
    bm1ff = mod[:functions][bm1fi]
    if bm1ff[:source_class] == nil && bm1ff[:source_method] == "__bigint_mul1_1_raw"
      bigint_mul1_1_matches += 1
      bigint_mul1_1_fn = bm1ff
    bm1fi += 1
  if bigint_mul1_1_matches > 1
    << "error: __bigint_mul1_1_raw is reserved for native BigInt multiplication"
    exit(1)
  if mod[:require_bigint_mul1_1_src] == true && bigint_mul1_1_fn == nil
    << "error: required native BigInt mul1@1 helper is missing; __w_bigint_mul1_1_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul1_1_target = bigint_times_reopened_fn
  if bigint_mul1_1_target == nil
    bigint_mul1_1_target = bigint_mul1_1_fn
  if bigint_mul1_1_target != nil
    bm1_signature_ok = bigint_mul1_1_target[:params] != nil && bigint_mul1_1_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bm1_signature_ok = bm1_signature_ok && bigint_mul1_1_target[:source_kind] == :fn_def
      bm1_signature_ok = bm1_signature_ok && bigint_mul1_1_target[:raw_i64_signature] == true
      bm1_signature_ok = bm1_signature_ok && bigint_mul1_1_target[:raw_return_type] == :i64
    if !bm1_signature_ok
      << "error: invalid native BigInt mul1@1 seam target"
      exit(1)
    bm1_cc = ""
    if bigint_mul1_1_target[:call_conv] != nil && bigint_mul1_1_target[:call_conv] != ""
      bm1_cc = bigint_mul1_1_target[:call_conv] + " "
    bm1_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bm1_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul1_1_src(i64 %a, i64 %b)" + bm1_attrs + " {\n"
    fn_out << "  %r = tail call " + bm1_cc + "i64 @" + bigint_mul1_1_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul1_1_src"] = false
    known_fns["__w_bigint_mul1_1_src"] = true
  elsif used_runtime_fns["__w_bigint_mul1_1_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul1_1_src(i64, i64) nounwind\n"

  # Pointer-identical positive two-limb square has its own seam rather than
  # borrowing the scalar-word contract. Core supplies the literal square
  # worker, a genuine BigInt#* reopen keeps precedence, and stage0 binds the
  # weak exact C implementation.
  bigint_sqr2_fn = nil
  bigint_sqr2_matches = 0
  bs2fi = 0
  while bs2fi < mod[:functions].size()
    bs2ff = mod[:functions][bs2fi]
    if bs2ff[:source_class] == nil && bs2ff[:source_method] == "__bigint_sqr2_raw"
      bigint_sqr2_matches += 1
      bigint_sqr2_fn = bs2ff
    bs2fi += 1
  if bigint_sqr2_matches > 1
    << "error: __bigint_sqr2_raw is reserved for native BigInt squaring"
    exit(1)
  if mod[:require_bigint_sqr2_src] == true && bigint_sqr2_fn == nil
    << "error: required native BigInt sqr@2 helper is missing; __w_bigint_sqr2_src would bind the weak C bootstrap default"
    exit(1)
  bigint_sqr2_target = bigint_times_reopened_fn
  if bigint_sqr2_target == nil
    bigint_sqr2_target = bigint_sqr2_fn
  if bigint_sqr2_target != nil
    bs2_signature_ok = bigint_sqr2_target[:params] != nil && bigint_sqr2_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bs2_signature_ok = bs2_signature_ok && bigint_sqr2_target[:source_kind] == :fn_def
      bs2_signature_ok = bs2_signature_ok && bigint_sqr2_target[:raw_i64_signature] == true
      bs2_signature_ok = bs2_signature_ok && bigint_sqr2_target[:raw_return_type] == :i64
    if !bs2_signature_ok
      << "error: invalid native BigInt sqr@2 seam target"
      exit(1)
    bs2_cc = ""
    if bigint_sqr2_target[:call_conv] != nil && bigint_sqr2_target[:call_conv] != ""
      bs2_cc = bigint_sqr2_target[:call_conv] + " "
    bs2_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bs2_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_sqr2_src(i64 %a, i64 %b)" + bs2_attrs + " {\n"
    fn_out << "  %r = tail call " + bs2_cc + "i64 @" + bigint_sqr2_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_sqr2_src"] = false
    known_fns["__w_bigint_sqr2_src"] = true
  elsif used_runtime_fns["__w_bigint_sqr2_src"] == true
    seam_decls << "declare i64 @__w_bigint_sqr2_src(i64, i64) nounwind\n"

  # Exact positive three-limb square sibling. Keep a distinct reserved seam
  # so this literal checkpoint can be benchmarked and rolled back without
  # changing the already-retained sqr@2 route.
  bigint_sqr3_fn = nil
  bigint_sqr3_matches = 0
  bs3fi = 0
  while bs3fi < mod[:functions].size()
    bs3ff = mod[:functions][bs3fi]
    if bs3ff[:source_class] == nil && bs3ff[:source_method] == "__bigint_sqr3_raw"
      bigint_sqr3_matches += 1
      bigint_sqr3_fn = bs3ff
    bs3fi += 1
  if bigint_sqr3_matches > 1
    << "error: __bigint_sqr3_raw is reserved for native BigInt squaring"
    exit(1)
  if mod[:require_bigint_sqr3_src] == true && bigint_sqr3_fn == nil
    << "error: required native BigInt sqr@3 helper is missing; __w_bigint_sqr3_src would bind the weak C bootstrap default"
    exit(1)
  bigint_sqr3_target = bigint_times_reopened_fn
  if bigint_sqr3_target == nil
    bigint_sqr3_target = bigint_sqr3_fn
  if bigint_sqr3_target != nil
    bs3_signature_ok = bigint_sqr3_target[:params] != nil && bigint_sqr3_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bs3_signature_ok = bs3_signature_ok && bigint_sqr3_target[:source_kind] == :fn_def
      bs3_signature_ok = bs3_signature_ok && bigint_sqr3_target[:raw_i64_signature] == true
      bs3_signature_ok = bs3_signature_ok && bigint_sqr3_target[:raw_return_type] == :i64
    if !bs3_signature_ok
      << "error: invalid native BigInt sqr@3 seam target"
      exit(1)
    bs3_cc = ""
    if bigint_sqr3_target[:call_conv] != nil && bigint_sqr3_target[:call_conv] != ""
      bs3_cc = bigint_sqr3_target[:call_conv] + " "
    bs3_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bs3_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_sqr3_src(i64 %a, i64 %b)" + bs3_attrs + " {\n"
    fn_out << "  %r = tail call " + bs3_cc + "i64 @" + bigint_sqr3_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_sqr3_src"] = false
    known_fns["__w_bigint_sqr3_src"] = true
  elsif used_runtime_fns["__w_bigint_sqr3_src"] == true
    seam_decls << "declare i64 @__w_bigint_sqr3_src(i64, i64) nounwind\n"

  # Exact positive four-limb square sibling. Keep a distinct reserved seam
  # so the literal C-shaped checkpoint stays independently reversible.
  bigint_sqr4_fn = nil
  bigint_sqr4_matches = 0
  bs4fi = 0
  while bs4fi < mod[:functions].size()
    bs4ff = mod[:functions][bs4fi]
    if bs4ff[:source_class] == nil && bs4ff[:source_method] == "__bigint_sqr4_raw"
      bigint_sqr4_matches += 1
      bigint_sqr4_fn = bs4ff
    bs4fi += 1
  if bigint_sqr4_matches > 1
    << "error: __bigint_sqr4_raw is reserved for native BigInt squaring"
    exit(1)
  if mod[:require_bigint_sqr4_src] == true && bigint_sqr4_fn == nil
    << "error: required native BigInt sqr@4 helper is missing; __w_bigint_sqr4_src would bind the weak C bootstrap default"
    exit(1)
  bigint_sqr4_target = bigint_times_reopened_fn
  if bigint_sqr4_target == nil
    bigint_sqr4_target = bigint_sqr4_fn
  if bigint_sqr4_target != nil
    bs4_signature_ok = bigint_sqr4_target[:params] != nil && bigint_sqr4_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bs4_signature_ok = bs4_signature_ok && bigint_sqr4_target[:source_kind] == :fn_def
      bs4_signature_ok = bs4_signature_ok && bigint_sqr4_target[:raw_i64_signature] == true
      bs4_signature_ok = bs4_signature_ok && bigint_sqr4_target[:raw_return_type] == :i64
    if !bs4_signature_ok
      << "error: invalid native BigInt sqr@4 seam target"
      exit(1)
    bs4_cc = ""
    if bigint_sqr4_target[:call_conv] != nil && bigint_sqr4_target[:call_conv] != ""
      bs4_cc = bigint_sqr4_target[:call_conv] + " "
    bs4_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bs4_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_sqr4_src(i64 %a, i64 %b)" + bs4_attrs + " {\n"
    fn_out << "  %r = tail call " + bs4_cc + "i64 @" + bigint_sqr4_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_sqr4_src"] = false
    known_fns["__w_bigint_sqr4_src"] = true
  elsif used_runtime_fns["__w_bigint_sqr4_src"] == true
    seam_decls << "declare i64 @__w_bigint_sqr4_src(i64, i64) nounwind\n"

  # Exact positive five-limb square sibling. Keep a distinct reserved seam
  # so the literal C-shaped checkpoint stays independently reversible.
  bigint_sqr5_fn = nil
  bigint_sqr5_matches = 0
  bs5fi = 0
  while bs5fi < mod[:functions].size()
    bs5ff = mod[:functions][bs5fi]
    if bs5ff[:source_class] == nil && bs5ff[:source_method] == "__bigint_sqr5_raw"
      bigint_sqr5_matches += 1
      bigint_sqr5_fn = bs5ff
    bs5fi += 1
  if bigint_sqr5_matches > 1
    << "error: __bigint_sqr5_raw is reserved for native BigInt squaring"
    exit(1)
  if mod[:require_bigint_sqr5_src] == true && bigint_sqr5_fn == nil
    << "error: required native BigInt sqr@5 helper is missing; __w_bigint_sqr5_src would bind the weak C bootstrap default"
    exit(1)
  bigint_sqr5_target = bigint_times_reopened_fn
  if bigint_sqr5_target == nil
    bigint_sqr5_target = bigint_sqr5_fn
  if bigint_sqr5_target != nil
    bs5_signature_ok = bigint_sqr5_target[:params] != nil && bigint_sqr5_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bs5_signature_ok = bs5_signature_ok && bigint_sqr5_target[:source_kind] == :fn_def
      bs5_signature_ok = bs5_signature_ok && bigint_sqr5_target[:raw_i64_signature] == true
      bs5_signature_ok = bs5_signature_ok && bigint_sqr5_target[:raw_return_type] == :i64
    if !bs5_signature_ok
      << "error: invalid native BigInt sqr@5 seam target"
      exit(1)
    bs5_cc = ""
    if bigint_sqr5_target[:call_conv] != nil && bigint_sqr5_target[:call_conv] != ""
      bs5_cc = bigint_sqr5_target[:call_conv] + " "
    bs5_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bs5_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_sqr5_src(i64 %a, i64 %b)" + bs5_attrs + " {\n"
    fn_out << "  %r = tail call " + bs5_cc + "i64 @" + bigint_sqr5_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_sqr5_src"] = false
    known_fns["__w_bigint_sqr5_src"] = true
  elsif used_runtime_fns["__w_bigint_sqr5_src"] == true
    seam_decls << "declare i64 @__w_bigint_sqr5_src(i64, i64) nounwind\n"

  # Exact positive six-limb square sibling. Keep a distinct reserved seam
  # so the literal C-shaped checkpoint stays independently reversible.
  bigint_sqr6_fn = nil
  bigint_sqr6_matches = 0
  bs6fi = 0
  while bs6fi < mod[:functions].size()
    bs6ff = mod[:functions][bs6fi]
    if bs6ff[:source_class] == nil && bs6ff[:source_method] == "__bigint_sqr6_raw"
      bigint_sqr6_matches += 1
      bigint_sqr6_fn = bs6ff
    bs6fi += 1
  if bigint_sqr6_matches > 1
    << "error: __bigint_sqr6_raw is reserved for native BigInt squaring"
    exit(1)
  if mod[:require_bigint_sqr6_src] == true && bigint_sqr6_fn == nil
    << "error: required native BigInt sqr@6 helper is missing; __w_bigint_sqr6_src would bind the weak C bootstrap default"
    exit(1)
  bigint_sqr6_target = bigint_times_reopened_fn
  if bigint_sqr6_target == nil
    bigint_sqr6_target = bigint_sqr6_fn
  if bigint_sqr6_target != nil
    bs6_signature_ok = bigint_sqr6_target[:params] != nil && bigint_sqr6_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bs6_signature_ok = bs6_signature_ok && bigint_sqr6_target[:source_kind] == :fn_def
      bs6_signature_ok = bs6_signature_ok && bigint_sqr6_target[:raw_i64_signature] == true
      bs6_signature_ok = bs6_signature_ok && bigint_sqr6_target[:raw_return_type] == :i64
    if !bs6_signature_ok
      << "error: invalid native BigInt sqr@6 seam target"
      exit(1)
    bs6_cc = ""
    if bigint_sqr6_target[:call_conv] != nil && bigint_sqr6_target[:call_conv] != ""
      bs6_cc = bigint_sqr6_target[:call_conv] + " "
    bs6_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bs6_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_sqr6_src(i64 %a, i64 %b)" + bs6_attrs + " {\n"
    fn_out << "  %r = tail call " + bs6_cc + "i64 @" + bigint_sqr6_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_sqr6_src"] = false
    known_fns["__w_bigint_sqr6_src"] = true
  elsif used_runtime_fns["__w_bigint_sqr6_src"] == true
    seam_decls << "declare i64 @__w_bigint_sqr6_src(i64, i64) nounwind\n"

  # Exact positive seven-limb square sibling. Keep a distinct reserved seam
  # so the literal C-shaped checkpoint stays independently reversible.
  bigint_sqr7_fn = nil
  bigint_sqr7_matches = 0
  bs7fi = 0
  while bs7fi < mod[:functions].size()
    bs7ff = mod[:functions][bs7fi]
    if bs7ff[:source_class] == nil && bs7ff[:source_method] == "__bigint_sqr7_raw"
      bigint_sqr7_matches += 1
      bigint_sqr7_fn = bs7ff
    bs7fi += 1
  if bigint_sqr7_matches > 1
    << "error: __bigint_sqr7_raw is reserved for native BigInt squaring"
    exit(1)
  if mod[:require_bigint_sqr7_src] == true && bigint_sqr7_fn == nil
    << "error: required native BigInt sqr@7 helper is missing; __w_bigint_sqr7_src would bind the weak C bootstrap default"
    exit(1)
  bigint_sqr7_target = bigint_times_reopened_fn
  if bigint_sqr7_target == nil
    bigint_sqr7_target = bigint_sqr7_fn
  if bigint_sqr7_target != nil
    bs7_signature_ok = bigint_sqr7_target[:params] != nil && bigint_sqr7_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bs7_signature_ok = bs7_signature_ok && bigint_sqr7_target[:source_kind] == :fn_def
      bs7_signature_ok = bs7_signature_ok && bigint_sqr7_target[:raw_i64_signature] == true
      bs7_signature_ok = bs7_signature_ok && bigint_sqr7_target[:raw_return_type] == :i64
    if !bs7_signature_ok
      << "error: invalid native BigInt sqr@7 seam target"
      exit(1)
    bs7_cc = ""
    if bigint_sqr7_target[:call_conv] != nil && bigint_sqr7_target[:call_conv] != ""
      bs7_cc = bigint_sqr7_target[:call_conv] + " "
    bs7_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bs7_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_sqr7_src(i64 %a, i64 %b)" + bs7_attrs + " {\n"
    fn_out << "  %r = tail call " + bs7_cc + "i64 @" + bigint_sqr7_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_sqr7_src"] = false
    known_fns["__w_bigint_sqr7_src"] = true
  elsif used_runtime_fns["__w_bigint_sqr7_src"] == true
    seam_decls << "declare i64 @__w_bigint_sqr7_src(i64, i64) nounwind\n"

  # Exact positive eight-limb square sibling. Keep a distinct reserved seam
  # so the literal release/LTO C-shaped checkpoint stays independently
  # reversible.
  bigint_sqr8_fn = nil
  bigint_sqr8_matches = 0
  bs8fi = 0
  while bs8fi < mod[:functions].size()
    bs8ff = mod[:functions][bs8fi]
    if bs8ff[:source_class] == nil && bs8ff[:source_method] == "__bigint_sqr8_raw"
      bigint_sqr8_matches += 1
      bigint_sqr8_fn = bs8ff
    bs8fi += 1
  if bigint_sqr8_matches > 1
    << "error: __bigint_sqr8_raw is reserved for native BigInt squaring"
    exit(1)
  if mod[:require_bigint_sqr8_src] == true && bigint_sqr8_fn == nil
    << "error: required native BigInt sqr@8 helper is missing; __w_bigint_sqr8_src would bind the weak C bootstrap default"
    exit(1)
  bigint_sqr8_target = bigint_times_reopened_fn
  if bigint_sqr8_target == nil
    bigint_sqr8_target = bigint_sqr8_fn
  if bigint_sqr8_target != nil
    bs8_signature_ok = bigint_sqr8_target[:params] != nil && bigint_sqr8_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bs8_signature_ok = bs8_signature_ok && bigint_sqr8_target[:source_kind] == :fn_def
      bs8_signature_ok = bs8_signature_ok && bigint_sqr8_target[:raw_i64_signature] == true
      bs8_signature_ok = bs8_signature_ok && bigint_sqr8_target[:raw_return_type] == :i64
    if !bs8_signature_ok
      << "error: invalid native BigInt sqr@8 seam target"
      exit(1)
    bs8_cc = ""
    if bigint_sqr8_target[:call_conv] != nil && bigint_sqr8_target[:call_conv] != ""
      bs8_cc = bigint_sqr8_target[:call_conv] + " "
    bs8_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bs8_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_sqr8_src(i64 %a, i64 %b)" + bs8_attrs + " {\n"
    fn_out << "  %r = tail call " + bs8_cc + "i64 @" + bigint_sqr8_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_sqr8_src"] = false
    known_fns["__w_bigint_sqr8_src"] = true
  elsif used_runtime_fns["__w_bigint_sqr8_src"] == true
    seam_decls << "declare i64 @__w_bigint_sqr8_src(i64, i64) nounwind\n"

  # Exact distinct positive two-by-two-limb multiplication has its own
  # reserved seam. Core supplies the literal C-shaped worker, while a genuine
  # BigInt#* reopen remains the observable open-world target.
  bigint_mul2_fn = nil
  bigint_mul2_matches = 0
  be2fi = 0
  while be2fi < mod[:functions].size()
    be2ff = mod[:functions][be2fi]
    if be2ff[:source_class] == nil && be2ff[:source_method] == "__bigint_mul2_raw"
      bigint_mul2_matches += 1
      bigint_mul2_fn = be2ff
    be2fi += 1
  if bigint_mul2_matches > 1
    << "error: __bigint_mul2_raw is reserved for native BigInt multiplication"
    exit(1)
  if mod[:require_bigint_mul2_src] == true && bigint_mul2_fn == nil
    << "error: required native BigInt mul@2 helper is missing; __w_bigint_mul2_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul2_target = bigint_times_reopened_fn
  if bigint_mul2_target == nil
    bigint_mul2_target = bigint_mul2_fn
  if bigint_mul2_target != nil
    be2_signature_ok = bigint_mul2_target[:params] != nil && bigint_mul2_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      be2_signature_ok = be2_signature_ok && bigint_mul2_target[:source_kind] == :fn_def
      be2_signature_ok = be2_signature_ok && bigint_mul2_target[:raw_i64_signature] == true
      be2_signature_ok = be2_signature_ok && bigint_mul2_target[:raw_return_type] == :i64
    if !be2_signature_ok
      << "error: invalid native BigInt mul@2 seam target"
      exit(1)
    be2_cc = ""
    if bigint_mul2_target[:call_conv] != nil && bigint_mul2_target[:call_conv] != ""
      be2_cc = bigint_mul2_target[:call_conv] + " "
    be2_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      be2_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul2_src(i64 %a, i64 %b)" + be2_attrs + " {\n"
    fn_out << "  %r = tail call " + be2_cc + "i64 @" + bigint_mul2_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul2_src"] = false
    known_fns["__w_bigint_mul2_src"] = true
  elsif used_runtime_fns["__w_bigint_mul2_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul2_src(i64, i64) nounwind\n"

  # Exact positive 2-by-1 multiplication keeps a second narrow seam. w_mul
  # proves and orients the scalar-word shape without changing receiver order;
  # Core supplies the literal raw leaf, while a genuine BigInt#* reopen keeps
  # ordinary open-world precedence.
  bigint_mul1_2_fn = nil
  bigint_mul1_2_matches = 0
  bm2fi = 0
  while bm2fi < mod[:functions].size()
    bm2ff = mod[:functions][bm2fi]
    if bm2ff[:source_class] == nil && bm2ff[:source_method] == "__bigint_mul1_2_raw"
      bigint_mul1_2_matches += 1
      bigint_mul1_2_fn = bm2ff
    bm2fi += 1
  if bigint_mul1_2_matches > 1
    << "error: __bigint_mul1_2_raw is reserved for native BigInt multiplication"
    exit(1)
  if mod[:require_bigint_mul1_2_src] == true && bigint_mul1_2_fn == nil
    << "error: required native BigInt mul1@2 helper is missing; __w_bigint_mul1_2_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul1_2_target = bigint_times_reopened_fn
  if bigint_mul1_2_target == nil
    bigint_mul1_2_target = bigint_mul1_2_fn
  if bigint_mul1_2_target != nil
    bm2_signature_ok = bigint_mul1_2_target[:params] != nil && bigint_mul1_2_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bm2_signature_ok = bm2_signature_ok && bigint_mul1_2_target[:source_kind] == :fn_def
      bm2_signature_ok = bm2_signature_ok && bigint_mul1_2_target[:raw_i64_signature] == true
      bm2_signature_ok = bm2_signature_ok && bigint_mul1_2_target[:raw_return_type] == :i64
    if !bm2_signature_ok
      << "error: invalid native BigInt mul1@2 seam target"
      exit(1)
    bm2_cc = ""
    if bigint_mul1_2_target[:call_conv] != nil && bigint_mul1_2_target[:call_conv] != ""
      bm2_cc = bigint_mul1_2_target[:call_conv] + " "
    bm2_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      # Keep the exact port behind one compact seam call for its fidelity
      # checkpoint. Inlining the complete allocation + fixed kernel here
      # moves the established mul1@3..8 dispatch ladder in w_mul; native-only
      # integration is a separately measured follow-up.
      bm2_attrs += " noinline"
    fn_out << "define i64 @__w_bigint_mul1_2_src(i64 %a, i64 %b)" + bm2_attrs + " {\n"
    fn_out << "  %r = tail call " + bm2_cc + "i64 @" + bigint_mul1_2_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul1_2_src"] = false
    known_fns["__w_bigint_mul1_2_src"] = true
  elsif used_runtime_fns["__w_bigint_mul1_2_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul1_2_src(i64, i64) nounwind\n"

  # Exact positive 3-by-1 multiplication has a distinct C schedule from the
  # two-limb leaf. Keep its source seam separate so this fidelity checkpoint
  # cannot perturb any neighboring scalar-word width.
  bigint_mul1_3_fn = nil
  bigint_mul1_3_matches = 0
  bm3fi = 0
  while bm3fi < mod[:functions].size()
    bm3ff = mod[:functions][bm3fi]
    if bm3ff[:source_class] == nil && bm3ff[:source_method] == "__bigint_mul1_3_raw"
      bigint_mul1_3_matches += 1
      bigint_mul1_3_fn = bm3ff
    bm3fi += 1
  if bigint_mul1_3_matches > 1
    << "error: __bigint_mul1_3_raw is reserved for native BigInt multiplication"
    exit(1)
  if mod[:require_bigint_mul1_3_src] == true && bigint_mul1_3_fn == nil
    << "error: required native BigInt mul1@3 helper is missing; __w_bigint_mul1_3_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul1_3_target = bigint_times_reopened_fn
  if bigint_mul1_3_target == nil
    bigint_mul1_3_target = bigint_mul1_3_fn
  if bigint_mul1_3_target != nil
    bm3_signature_ok = bigint_mul1_3_target[:params] != nil && bigint_mul1_3_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bm3_signature_ok = bm3_signature_ok && bigint_mul1_3_target[:source_kind] == :fn_def
      bm3_signature_ok = bm3_signature_ok && bigint_mul1_3_target[:raw_i64_signature] == true
      bm3_signature_ok = bm3_signature_ok && bigint_mul1_3_target[:raw_return_type] == :i64
    if !bm3_signature_ok
      << "error: invalid native BigInt mul1@3 seam target"
      exit(1)
    bm3_cc = ""
    if bigint_mul1_3_target[:call_conv] != nil && bigint_mul1_3_target[:call_conv] != ""
      bm3_cc = bigint_mul1_3_target[:call_conv] + " "
    bm3_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      # Preserve the exact C-shaped checkpoint behind one compact seam. Any
      # native-only integration or shape fact belongs to the next tranche.
      bm3_attrs += " noinline"
    fn_out << "define i64 @__w_bigint_mul1_3_src(i64 %a, i64 %b)" + bm3_attrs + " {\n"
    fn_out << "  %r = tail call " + bm3_cc + "i64 @" + bigint_mul1_3_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul1_3_src"] = false
    known_fns["__w_bigint_mul1_3_src"] = true
  elsif used_runtime_fns["__w_bigint_mul1_3_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul1_3_src(i64, i64) nounwind\n"

  # Exact positive 4-by-1 multiplication has its own capacity and literal
  # carry schedule. Keep the source seam isolated from neighboring widths.
  bigint_mul1_4_fn = nil
  bigint_mul1_4_matches = 0
  bm4fi = 0
  while bm4fi < mod[:functions].size()
    bm4ff = mod[:functions][bm4fi]
    if bm4ff[:source_class] == nil && bm4ff[:source_method] == "__bigint_mul1_4_raw"
      bigint_mul1_4_matches += 1
      bigint_mul1_4_fn = bm4ff
    bm4fi += 1
  if bigint_mul1_4_matches > 1
    << "error: __bigint_mul1_4_raw is reserved for native BigInt multiplication"
    exit(1)
  if mod[:require_bigint_mul1_4_src] == true && bigint_mul1_4_fn == nil
    << "error: required native BigInt mul1@4 helper is missing; __w_bigint_mul1_4_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul1_4_target = bigint_times_reopened_fn
  if bigint_mul1_4_target == nil
    bigint_mul1_4_target = bigint_mul1_4_fn
  if bigint_mul1_4_target != nil
    bm4_signature_ok = bigint_mul1_4_target[:params] != nil && bigint_mul1_4_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bm4_signature_ok = bm4_signature_ok && bigint_mul1_4_target[:source_kind] == :fn_def
      bm4_signature_ok = bm4_signature_ok && bigint_mul1_4_target[:raw_i64_signature] == true
      bm4_signature_ok = bm4_signature_ok && bigint_mul1_4_target[:raw_return_type] == :i64
    if !bm4_signature_ok
      << "error: invalid native BigInt mul1@4 seam target"
      exit(1)
    bm4_cc = ""
    if bigint_mul1_4_target[:call_conv] != nil && bigint_mul1_4_target[:call_conv] != ""
      bm4_cc = bigint_mul1_4_target[:call_conv] + " "
    bm4_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      # Exact-port checkpoint only. Native-specific call-site integration is
      # measured separately after this seam is committed.
      bm4_attrs += " noinline"
    fn_out << "define i64 @__w_bigint_mul1_4_src(i64 %a, i64 %b)" + bm4_attrs + " {\n"
    fn_out << "  %r = tail call " + bm4_cc + "i64 @" + bigint_mul1_4_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul1_4_src"] = false
    known_fns["__w_bigint_mul1_4_src"] = true
  elsif used_runtime_fns["__w_bigint_mul1_4_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul1_4_src(i64, i64) nounwind\n"

  # Exact positive 5-by-1 multiplication retains the serial C recurrence in
  # a width-specific source seam, isolated from every neighboring arm.
  bigint_mul1_5_fn = nil
  bigint_mul1_5_matches = 0
  bm5fi = 0
  while bm5fi < mod[:functions].size()
    bm5ff = mod[:functions][bm5fi]
    if bm5ff[:source_class] == nil && bm5ff[:source_method] == "__bigint_mul1_5_raw"
      bigint_mul1_5_matches += 1
      bigint_mul1_5_fn = bm5ff
    bm5fi += 1
  if bigint_mul1_5_matches > 1
    << "error: __bigint_mul1_5_raw is reserved for native BigInt multiplication"
    exit(1)
  if mod[:require_bigint_mul1_5_src] == true && bigint_mul1_5_fn == nil
    << "error: required native BigInt mul1@5 helper is missing; __w_bigint_mul1_5_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul1_5_target = bigint_times_reopened_fn
  if bigint_mul1_5_target == nil
    bigint_mul1_5_target = bigint_mul1_5_fn
  if bigint_mul1_5_target != nil
    bm5_signature_ok = bigint_mul1_5_target[:params] != nil && bigint_mul1_5_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bm5_signature_ok = bm5_signature_ok && bigint_mul1_5_target[:source_kind] == :fn_def
      bm5_signature_ok = bm5_signature_ok && bigint_mul1_5_target[:raw_i64_signature] == true
      bm5_signature_ok = bm5_signature_ok && bigint_mul1_5_target[:raw_return_type] == :i64
    if !bm5_signature_ok
      << "error: invalid native BigInt mul1@5 seam target"
      exit(1)
    bm5_cc = ""
    if bigint_mul1_5_target[:call_conv] != nil && bigint_mul1_5_target[:call_conv] != ""
      bm5_cc = bigint_mul1_5_target[:call_conv] + " "
    bm5_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bm5_attrs += " noinline"
    fn_out << "define i64 @__w_bigint_mul1_5_src(i64 %a, i64 %b)" + bm5_attrs + " {\n"
    fn_out << "  %r = tail call " + bm5_cc + "i64 @" + bigint_mul1_5_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul1_5_src"] = false
    known_fns["__w_bigint_mul1_5_src"] = true
  elsif used_runtime_fns["__w_bigint_mul1_5_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul1_5_src(i64, i64) nounwind\n"

  # Exact positive 6-by-1 multiplication extends the serial five-limb C arm
  # by one recurrence step; retain a separate seam and fallback boundary.
  bigint_mul1_6_fn = nil
  bigint_mul1_6_matches = 0
  bm6fi = 0
  while bm6fi < mod[:functions].size()
    bm6ff = mod[:functions][bm6fi]
    if bm6ff[:source_class] == nil && bm6ff[:source_method] == "__bigint_mul1_6_raw"
      bigint_mul1_6_matches += 1
      bigint_mul1_6_fn = bm6ff
    bm6fi += 1
  if bigint_mul1_6_matches > 1
    << "error: __bigint_mul1_6_raw is reserved for native BigInt multiplication"
    exit(1)
  if mod[:require_bigint_mul1_6_src] == true && bigint_mul1_6_fn == nil
    << "error: required native BigInt mul1@6 helper is missing; __w_bigint_mul1_6_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul1_6_target = bigint_times_reopened_fn
  if bigint_mul1_6_target == nil
    bigint_mul1_6_target = bigint_mul1_6_fn
  if bigint_mul1_6_target != nil
    bm6_signature_ok = bigint_mul1_6_target[:params] != nil && bigint_mul1_6_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bm6_signature_ok = bm6_signature_ok && bigint_mul1_6_target[:source_kind] == :fn_def
      bm6_signature_ok = bm6_signature_ok && bigint_mul1_6_target[:raw_i64_signature] == true
      bm6_signature_ok = bm6_signature_ok && bigint_mul1_6_target[:raw_return_type] == :i64
    if !bm6_signature_ok
      << "error: invalid native BigInt mul1@6 seam target"
      exit(1)
    bm6_cc = ""
    if bigint_mul1_6_target[:call_conv] != nil && bigint_mul1_6_target[:call_conv] != ""
      bm6_cc = bigint_mul1_6_target[:call_conv] + " "
    bm6_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bm6_attrs += " noinline"
    fn_out << "define i64 @__w_bigint_mul1_6_src(i64 %a, i64 %b)" + bm6_attrs + " {\n"
    fn_out << "  %r = tail call " + bm6_cc + "i64 @" + bigint_mul1_6_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul1_6_src"] = false
    known_fns["__w_bigint_mul1_6_src"] = true
  elsif used_runtime_fns["__w_bigint_mul1_6_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul1_6_src(i64, i64) nounwind\n"

  # Exact positive 7-by-1 multiplication completes the serial small-width C
  # family; retain a separate seam and weak-bootstrap fallback boundary.
  bigint_mul1_7_fn = nil
  bigint_mul1_7_matches = 0
  bm7fi = 0
  while bm7fi < mod[:functions].size()
    bm7ff = mod[:functions][bm7fi]
    if bm7ff[:source_class] == nil && bm7ff[:source_method] == "__bigint_mul1_7_raw"
      bigint_mul1_7_matches += 1
      bigint_mul1_7_fn = bm7ff
    bm7fi += 1
  if bigint_mul1_7_matches > 1
    << "error: __bigint_mul1_7_raw is reserved for native BigInt multiplication"
    exit(1)
  if mod[:require_bigint_mul1_7_src] == true && bigint_mul1_7_fn == nil
    << "error: required native BigInt mul1@7 helper is missing; __w_bigint_mul1_7_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul1_7_target = bigint_times_reopened_fn
  if bigint_mul1_7_target == nil
    bigint_mul1_7_target = bigint_mul1_7_fn
  if bigint_mul1_7_target != nil
    bm7_signature_ok = bigint_mul1_7_target[:params] != nil && bigint_mul1_7_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bm7_signature_ok = bm7_signature_ok && bigint_mul1_7_target[:source_kind] == :fn_def
      bm7_signature_ok = bm7_signature_ok && bigint_mul1_7_target[:raw_i64_signature] == true
      bm7_signature_ok = bm7_signature_ok && bigint_mul1_7_target[:raw_return_type] == :i64
    if !bm7_signature_ok
      << "error: invalid native BigInt mul1@7 seam target"
      exit(1)
    bm7_cc = ""
    if bigint_mul1_7_target[:call_conv] != nil && bigint_mul1_7_target[:call_conv] != ""
      bm7_cc = bigint_mul1_7_target[:call_conv] + " "
    bm7_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bm7_attrs += " noinline"
    fn_out << "define i64 @__w_bigint_mul1_7_src(i64 %a, i64 %b)" + bm7_attrs + " {\n"
    fn_out << "  %r = tail call " + bm7_cc + "i64 @" + bigint_mul1_7_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul1_7_src"] = false
    known_fns["__w_bigint_mul1_7_src"] = true
  elsif used_runtime_fns["__w_bigint_mul1_7_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul1_7_src(i64, i64) nounwind\n"

  # Exact positive 8-by-1 multiplication owns the separate current-C tiny8
  # schedule and cap-16 result policy behind its own stable seam.
  bigint_mul1_8_fn = nil
  bigint_mul1_8_matches = 0
  bm8fi = 0
  while bm8fi < mod[:functions].size()
    bm8ff = mod[:functions][bm8fi]
    if bm8ff[:source_class] == nil && bm8ff[:source_method] == "__bigint_mul1_8_raw"
      bigint_mul1_8_matches += 1
      bigint_mul1_8_fn = bm8ff
    bm8fi += 1
  if bigint_mul1_8_matches > 1
    << "error: __bigint_mul1_8_raw is reserved for native BigInt multiplication"
    exit(1)
  if mod[:require_bigint_mul1_8_src] == true && bigint_mul1_8_fn == nil
    << "error: required native BigInt mul1@8 helper is missing; __w_bigint_mul1_8_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul1_8_target = bigint_times_reopened_fn
  if bigint_mul1_8_target == nil
    bigint_mul1_8_target = bigint_mul1_8_fn
  if bigint_mul1_8_target != nil
    bm8_signature_ok = bigint_mul1_8_target[:params] != nil && bigint_mul1_8_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bm8_signature_ok = bm8_signature_ok && bigint_mul1_8_target[:source_kind] == :fn_def
      bm8_signature_ok = bm8_signature_ok && bigint_mul1_8_target[:raw_i64_signature] == true
      bm8_signature_ok = bm8_signature_ok && bigint_mul1_8_target[:raw_return_type] == :i64
    if !bm8_signature_ok
      << "error: invalid native BigInt mul1@8 seam target"
      exit(1)
    bm8_cc = ""
    if bigint_mul1_8_target[:call_conv] != nil && bigint_mul1_8_target[:call_conv] != ""
      bm8_cc = bigint_mul1_8_target[:call_conv] + " "
    bm8_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bm8_attrs += " noinline"
    fn_out << "define i64 @__w_bigint_mul1_8_src(i64 %a, i64 %b)" + bm8_attrs + " {\n"
    fn_out << "  %r = tail call " + bm8_cc + "i64 @" + bigint_mul1_8_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul1_8_src"] = false
    known_fns["__w_bigint_mul1_8_src"] = true
  elsif used_runtime_fns["__w_bigint_mul1_8_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul1_8_src(i64, i64) nounwind\n"

  # Unary BigInt#isqrt has the same stable source/weak-C seam contract as the
  # binary operators above. Its source body owns the one- and two-limb leaves
  # and retains the C divide-and-conquer boundary for wider values.
  bigint_isqrt_fn = nil
  bisfi = 0
  while bisfi < mod[:functions].size()
    bisff = mod[:functions][bisfi]
    if bisff[:source_class] == "BigInt" && bisff[:source_kind] == :method && bisff[:source_method] == "isqrt" && bisff[:overload_dispatcher] != true
      # Definitions are in source order. Match ordinary method-table
      # replacement semantics by selecting the last plain body; protected
      # Core programs reject a reopen earlier during contract validation.
      bigint_isqrt_fn = bisff
    bisfi += 1
  if bigint_isqrt_fn != nil
    bis_cc = ""
    if bigint_isqrt_fn[:call_conv] != nil && bigint_isqrt_fn[:call_conv] != ""
      bis_cc = bigint_isqrt_fn[:call_conv] + " "
    fn_out << "define i64 @__w_bigint_isqrt_src(i64 %a) nounwind {\n"
    fn_out << "  %r = tail call " + bis_cc + "i64 @" + bigint_isqrt_fn[:name] + "(i64 %a)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_isqrt_src"] = false
    known_fns["__w_bigint_isqrt_src"] = true
  elsif used_runtime_fns["__w_bigint_isqrt_src"] == true
    seam_decls << "declare i64 @__w_bigint_isqrt_src(i64) nounwind\n"

  # Full BigInt/integer comparison is a raw top-level Tungsten helper rather
  # than a boxed public method. Give its content-hash-renamed body one stable
  # strong symbol so every runtime comparison entry can call it directly.
  # The runtime supplies a weak C oracle/default for stage0. Root loading
  # injects this support function into every production target, so strong-over-
  # weak resolution selects the source implementation without a dispatch or
  # box/unbox hop even when a BigInt entered through an opaque boundary.
  big_compare_fn = nil
  big_compare_matches = 0
  bcfi = 0
  while bcfi < mod[:functions].size()
    bcff = mod[:functions][bcfi]
    if bcff[:source_class] == nil && bcff[:source_method] == "__bigint_compare_raw"
      big_compare_matches += 1
      big_compare_fn = bcff
    bcfi += 1
  if big_compare_matches > 1
    << "error: __bigint_compare_raw is reserved for the native BigInt comparator"
    exit(1)
  if mod[:require_bigint_compare_src] == true && big_compare_fn == nil
    << "error: required native BigInt comparator is missing; __w_bigint_compare_src would bind the weak C bootstrap default"
    exit(1)
  if big_compare_fn != nil
    compare_signature_ok = big_compare_fn[:source_kind] == :fn_def && big_compare_fn[:raw_i64_signature] == true && big_compare_fn[:raw_return_type] == :i64 && big_compare_fn[:params].size() == 2 && big_compare_fn[:embedded_ll] != nil
    if !compare_signature_ok
      << "error: invalid reserved native BigInt comparator definition"
      exit(1)
    bcmp_cc = ""
    if big_compare_fn[:call_conv] != nil && big_compare_fn[:call_conv] != ""
      bcmp_cc = big_compare_fn[:call_conv] + " "
    fn_out << "define i64 @__w_bigint_compare_src(i64 %a, i64 %b) nounwind {\n"
    fn_out << "  %r = tail call " + bcmp_cc + "i64 @" + big_compare_fn[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_compare_src"] = false
    known_fns["__w_bigint_compare_src"] = true

  # String constants that still need raw ptr access; slab emitted as constant array
  strings_out = emit_string_constants(mod[:strings], slab_info, used_ptr_ids)
  if strings_out != ""
    strings_out = strings_out + "\n"

  # w_slab_init_static is emitted directly in emit_function, not via an instruction
  if slab_info != nil && slab_info[:slab_entries].size() > 0
    used_runtime_fns["w_slab_init_static"] = true

  decls_out = filter_runtime_decls(declare_runtime(), used_runtime_fns) + seam_decls.to_s()
  if ccall_needed.has_key?("__w_bigint_sqr4_locked_exact") || ccall_needed.has_key?("__w_bigint_sqr5_locked_exact")
    # Keep the large exact sqr@4 worker and its size test behind one outlined
    # default-path call. Inlining either into the locked caller makes LLVM
    # rebalance the already-measured 1..3 dispatch and clones hundreds of
    # bytes into that hot loop.
    if decls_out.index("@w_bigint_mul_builtin_exact(") == nil
      decls_out = decls_out + "declare i64 @w_bigint_mul_builtin_exact(i64, i64) nounwind\n"
    decls_out = decls_out + <<~IR
      define i64 @__w_bigint_sqr4_locked_exact(i64 %a, i64 %b, i64 %size) nounwind noinline {
      entry:
        %is4 = icmp eq i64 %size, 4
        br i1 %is4, label %four, label %exact
      four:
        %sr = tail call i64 @__w_bigint_sqr4_src(i64 %a, i64 %b)
        ret i64 %sr
      exact:
        %er = tail call i64 @w_bigint_mul_builtin_exact(i64 %a, i64 %b)
        ret i64 %er
      }

    IR
  if ccall_needed.has_key?("__w_bigint_sqr5_locked_exact")
    # Test only the new size before tail-chaining to the byte-for-byte retained
    # sqr@4 dispatcher. Keeping the two outlined levels separate prevents the
    # sqr@5 allocation/call frame from being hoisted onto every default width.
    decls_out = decls_out + <<~IR
      define i64 @__w_bigint_sqr5_locked_exact(i64 %a, i64 %b, i64 %size) nounwind noinline {
      entry:
        %is5 = icmp eq i64 %size, 5
        br i1 %is5, label %five, label %prior
      five:
        %s5 = tail call i64 @__w_bigint_sqr5_src(i64 %a, i64 %b)
        ret i64 %s5
      prior:
        %pr = tail call i64 @__w_bigint_sqr4_locked_exact(i64 %a, i64 %b, i64 %size)
        ret i64 %pr
      }

    IR
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
  if fn_out.to_s().index("@g_ast_store") != nil
    # WAstStore begins with its exact-width node arena; declaring the symbol
    # prefix type keeps the hot GEPs compact while the runtime owns the rest.
    decls_out = "@g_ast_store = external global { ptr, i32, i32 }\n\n" + decls_out
  if decls_out != ""
    decls_out = decls_out + "\n"

  # Inline array-read fast paths: inject the private alwaysinline helper
  # definitions (plus their slow-path externs, unless already declared)
  # before the auto-declare loop below — its decls_out dedupe then skips
  # re-declaring the helper names.
  if ccall_needed.has_key?("__w_array_get_i64_fast") || ccall_needed.has_key?("__w_array_idx_i64_fast")
    # memory(read) on the get/idx slow twins: the fast helpers only load + tail
    # into these, so the function-attrs pass infers the whole inlined helper is
    # read-only and can hoist/CSE `a[i]` reads.
    if decls_out.index("@w_array_get_i64(") == nil
      decls_out = decls_out + "declare i64 @w_array_get_i64(i64, i64) nounwind willreturn memory(read)\n"
    if decls_out.index("@w_array_idx_i64(") == nil
      decls_out = decls_out + "declare i64 @w_array_idx_i64(i64, i64) nounwind willreturn memory(read)\n"
    decls_out = decls_out + array_fast_helpers_ir() + "\n"

  # Inline array-write fast path — separate injection so read-only modules never
  # emit it. Its cold path re-boxes the index and calls the body-safe w_array_set
  # (raises on immutable AST body refs) rather than the WArray-assuming
  # w_array_set_i64, so the general `a[i]=x` site stays sound.
  if ccall_needed.has_key?("__w_array_set_i64_fast")
    if decls_out.index("@w_array_set(") == nil
      decls_out = decls_out + "declare i64 @w_array_set(i64, i64, i64) nounwind\n"
    if decls_out.index("@w_int(") == nil
      decls_out = decls_out + "declare i64 @w_int(i64) nounwind\n"
    decls_out = decls_out + array_set_fast_helper_ir() + "\n"

  # Inline comparison fast paths — same injection scheme, one helper per
  # comparison actually used by this module.
  cmp_fast_specs = [
    ["__w_eq_fast", "w_eq", "eq", false],
    ["__w_neq_fast", "w_neq", "ne", false],
    ["__w_eq_lit_fast", "w_eq_lit", "eq", false],
    ["__w_neq_lit_fast", "w_neq_lit", "ne", false],
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

  # BigInt zero/sign compare fast paths (lowering's `big <op> 0` arm) —
  # same injection scheme, one helper per relation actually used.
  zero_cmp_specs = [
    ["__w_eq0_big_fast", "w_eq", "eq"],
    ["__w_lt0_big_fast", "w_lt", "slt"],
    ["__w_gt0_big_fast", "w_gt", "sgt"],
    ["__w_lte0_big_fast", "w_lte", "sle"],
    ["__w_gte0_big_fast", "w_gte", "sge"]
  ]
  zci = 0
  while zci < zero_cmp_specs.size()
    zc = zero_cmp_specs[zci]
    if ccall_needed.has_key?(zc[0])
      if decls_out.index("@" + zc[1] + "(") == nil
        decls_out = decls_out + "declare i64 @" + zc[1] + "(i64, i64) nounwind\n"
      decls_out = decls_out + bigint_zero_cmp_fast_helper_ir(zc[0], zc[1], zc[2]) + "\n"
    zci += 1

  # Literal string/symbol == fast path (lowering's :EQ/:NEQ literal arm calls
  # __w_streq_fast with the canonical constant as %lit).
  if ccall_needed.has_key?("__w_streq_fast")
    if decls_out.index("@w_eq(") == nil
      decls_out = decls_out + "declare i64 @w_eq(i64, i64) nounwind\n"
    decls_out = decls_out + streq_fast_helper_ir() + "\n"

  # Var-var string == fast path (lowering's :string type-fact arm).
  if ccall_needed.has_key?("__w_streq2_fast")
    if decls_out.index("@w_eq(") == nil
      decls_out = decls_out + "declare i64 @w_eq(i64, i64) nounwind\n"
    decls_out = decls_out + streq2_fast_helper_ir() + "\n"

  # Typed String#[]: the private wrapper guards the memory(none) SSO leaf;
  # only its slab/heap/rope fallback calls the conservatively-declared runtime
  # entry. Never transfer the leaf's attributes to w_string_idx_raw itself.
  if ccall_needed.has_key?("__w_string_idx_fast")
    if decls_out.index("@w_string_idx_raw(") == nil
      decls_out = decls_out + "declare i64 @w_string_idx_raw(i64, i64) nounwind\n"
    decls_out = decls_out + string_idx_fast_helper_ir() + "\n"

  # Typed String#size: unlike subscript, the slow path is itself read-only,
  # so the wrapper may honestly carry memory(read) while its SSO leaf carries
  # the stronger memory(none) contract.
  if ccall_needed.has_key?("__w_string_byte_length_fast")
    if decls_out.index("@w_string_byte_length(") == nil
      decls_out = decls_out + "declare i64 @w_string_byte_length(i64) nounwind willreturn memory(read)\n"
    decls_out = decls_out + string_size_fast_helper_ir() + "\n"

  # Boxed +/- fast paths (op map routes :PLUS/:MINUS to these helpers).
  arith_fast_specs = [
    ["__w_add_fast", "w_add", "add"],
    ["__w_sub_fast", "w_sub", "sub"]
  ]
  afi = 0
  while afi < arith_fast_specs.size()
    af = arith_fast_specs[afi]
    if ccall_needed.has_key?(af[0])
      if decls_out.index("@" + af[1] + "(") == nil
        decls_out = decls_out + "declare i64 @" + af[1] + "(i64, i64) nounwind\n"
      decls_out = decls_out + arith_fast_helper_ir(af[0], af[1], af[2]) + "\n"
    afi += 1

  # Boxed & | ^ / * / << >> fast paths + inline box/unbox wrappers, same
  # injection scheme as the arith helpers above.
  bitop_fast_specs = [
    ["__w_bxor_fast", "w_bit_xor", "xor"],
    ["__w_band_fast", "w_bit_and", "and"],
    ["__w_bor_fast", "w_bit_or", "or"]
  ]
  bfi = 0
  while bfi < bitop_fast_specs.size()
    bf = bitop_fast_specs[bfi]
    if ccall_needed.has_key?(bf[0])
      if decls_out.index("@" + bf[1] + "(") == nil
        decls_out = decls_out + "declare i64 @" + bf[1] + "(i64, i64) nounwind\n"
      decls_out = decls_out + bitop_fast_helper_ir(bf[0], bf[1], bf[2]) + "\n"
    bfi += 1
  if ccall_needed.has_key?("__w_mul_fast")
    if decls_out.index("@w_mul(") == nil
      decls_out = decls_out + "declare i64 @w_mul(i64, i64) nounwind\n"
    decls_out = decls_out + "declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)\n"
    decls_out = decls_out + mul_fast_helper_ir() + "\n"
  divmod_fast_specs = [
    ["__w_div_fast", "w_div", "sdiv"],
    ["__w_mod_fast", "w_mod", "srem"]
  ]
  dfi = 0
  while dfi < divmod_fast_specs.size()
    df = divmod_fast_specs[dfi]
    if ccall_needed.has_key?(df[0])
      if decls_out.index("@" + df[1] + "(") == nil
        decls_out = decls_out + "declare i64 @" + df[1] + "(i64, i64) nounwind\n"
      decls_out = decls_out + divmod_fast_helper_ir(df[0], df[1], df[2]) + "\n"
    dfi += 1
  if ccall_needed.has_key?("__w_shl_fast")
    if decls_out.index("@w_bit_shl(") == nil
      decls_out = decls_out + "declare i64 @w_bit_shl(i64, i64) nounwind\n"
    decls_out = decls_out + shift_fast_helper_ir("__w_shl_fast", "w_bit_shl", true) + "\n"
  if ccall_needed.has_key?("__w_shr_fast")
    if decls_out.index("@w_bit_shr(") == nil
      decls_out = decls_out + "declare i64 @w_bit_shr(i64, i64) nounwind\n"
    decls_out = decls_out + shift_fast_helper_ir("__w_shr_fast", "w_bit_shr", false) + "\n"
  if ccall_needed.has_key?("__w_int_fast")
    if decls_out.index("@w_int(") == nil
      decls_out = decls_out + "declare i64 @w_int(i64) nounwind\n"
    decls_out = decls_out + int_fast_helper_ir() + "\n"
  if ccall_needed.has_key?("__w_to_i64_fast")
    if decls_out.index("@w_to_i64(") == nil
      decls_out = decls_out + "declare i64 @w_to_i64(i64) nounwind\n"
    decls_out = decls_out + to_i64_fast_helper_ir() + "\n"
  if ccall_needed.has_key?("__w_num_to_f64_fast")
    if decls_out.index("@w_num_to_f64(") == nil
      decls_out = decls_out + "declare double @w_num_to_f64(i64) nounwind memory(read)\n"
    decls_out = decls_out + num_to_f64_fast_helper_ir() + "\n"
  if ccall_needed.has_key?("__w_array_lit_store")
    decls_out = decls_out + array_lit_store_helper_ir() + "\n"

  bit_count_intrinsic_specs = [
    ["__w_bit_ctpop_u32", "ctpop", 32, false],
    ["__w_bit_ctpop_u64", "ctpop", 64, false],
    ["__w_bit_ctlz_u32", "ctlz", 32, true],
    ["__w_bit_ctlz_u64", "ctlz", 64, true],
    ["__w_bit_cttz_u32", "cttz", 32, true],
    ["__w_bit_cttz_u64", "cttz", 64, true]
  ]
  bci = 0
  while bci < bit_count_intrinsic_specs.size()
    spec = bit_count_intrinsic_specs[bci]
    if ccall_needed.has_key?(spec[0])
      decls_out = decls_out + bit_count_intrinsic_helper_ir(spec[0], spec[1], spec[2], spec[3]) + "\n"
    bci += 1

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
  ccall_keys = ccall_needed.keys()
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
      # Pure size accessors read one header field, never raise, always return —
      # memory(read) lets LICM hoist/CSE `arr.size` out of loops. These come only
      # through the auto-declare path (no declare_fn entry), so tag them here.
      tail_attrs = "nounwind"
      if iname in ("w_big_array_size" "w_small_array_size")
        tail_attrs = "nounwind willreturn memory(read)"
      decls_out = decls_out + "declare i64 @" + iname + "(" + params.join(", ") + ") " + tail_attrs + "\n"
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

  header + decls_out + globals_out.to_s() + strings_out + fn_out.to_s() + fn_meta_out + call_site_out + llvm_used_out + attr_groups_out + tbaa_metadata_defs() + novec_loop_md_defs() + ewscope_md_defs()

# -- Emit a single function --

-> hidden_exit_label_for_inst(inst, arm64_target = true)
  op = wire_kind(inst)
  # Portable (non-arm64) lowering of the asm-backed carry ops renders a
  # real IR loop whose final block is the instruction's exit.
  if op == :asm_add_no && !arm64_target
    return "ano.exit." + wire_get(inst, :temp).slice(1, wire_get(inst, :temp).size() - 1)
  if op == :asm_sub_no && !arm64_target
    return "sno.exit." + wire_get(inst, :temp).slice(1, wire_get(inst, :temp).size() - 1)
  if op == :asm_add_uneq && !arm64_target
    return "aue.x." + wire_get(inst, :temp).slice(1, wire_get(inst, :temp).size() - 1)
  if op == :asm_sub_uneq && !arm64_target
    return "sue.x." + wire_get(inst, :temp).slice(1, wire_get(inst, :temp).size() - 1)
  if op in (:add_i48_checked :sub_i48_checked :mul_i48_checked)
    return "ovf.merge." + wire_get(inst, :block_id).to_s()
  if op in (:add_i48_guarded :sub_i48_guarded :mul_i48_guarded)
    return "g.done." + wire_get(inst, :block_id).to_s()
  # Method-dispatch call sites carrying source-loc info split the block so
  # their return address is addressable via blockaddress(@fn, %cs.N.ret).
  # A devirtualized site additionally merges its direct and IC arms in a
  # dv.N.done block, which is then the real exit regardless of src_line.
  if op == :call_method_i64 && (wire_get(inst, :devirt_fn) != nil || wire_get(inst, :construct_fn) != nil)
    return "dv." + wire_get(inst, :ic_id).to_s() + ".done"
  if op == :call_method_i64 && wire_get(inst, :src_line) != nil
    return "cs." + wire_get(inst, :ic_id).to_s() + ".ret"
  # Direct-call fallible sites (w_raise, w_array_get, w_array_set) use the
  # loc_site_id namespace since they don't have an ic_id.
  if op in (:call_direct_void :call_direct_i64) && wire_get(inst, :src_line) != nil && wire_get(inst, :loc_site_id) != nil
    return "csd." + wire_get(inst, :loc_site_id).to_s() + ".ret"
  nil

-> build_phi_label_redirects(f, arm64_target = true)
  redirect = {}
  bi = 0
  while bi < f[:blocks].size()
    blk = f[:blocks][bi]
    exit_label = blk[:label]
    ii = 0
    while ii < blk[:instructions].size()
      hidden = hidden_exit_label_for_inst(blk[:instructions][ii], arm64_target)
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

# Embedded `ll` body: the fn's LLVM IR was written by hand in the source.
# Emit the define wrapper with the .w parameter names (all i64: machine ints
# raw, typed arrays as start-corrected element-0 data addresses) and splice
# the text verbatim.  The body owns its control flow and must `ret`.
-> emit_embedded_ll_function(f)
  out = StringBuffer(1024 + f[:embedded_ll].size())
  out << "define internal "
  out << f[:return_type]
  out << " @"
  out << f[:name]
  out << "("
  out << emit_param_signature(f)
  out << ") nounwind"
  # Embedded IR may explicitly request call-site integration without adding
  # a parser-level annotation.  The marker stays an LLVM comment inside the
  # body; the only emitted-code effect is this function attribute.
  inline_marker = f[:embedded_ll].index("; tungsten:alwaysinline") != nil
  noinline_marker = f[:embedded_ll].index("; tungsten:noinline") != nil
  if inline_marker && noinline_marker
    raise "embedded ll function cannot request both alwaysinline and noinline"
  inline_enabled = env("TUNGSTEN_EMBEDDED_LL_INLINE") != "0"
  if noinline_marker
    out << " noinline"
  elsif inline_marker && inline_enabled
    out << " alwaysinline"
  out << " {\n"
  out << f[:embedded_ll]
  if !f[:embedded_ll].ends_with?("\n")
    out << "\n"
  out << "}\n"
  out.to_s()

# Embedded `asm` body: whole-function AArch64 assembly emitted as
# module-level asm under the fn's (Darwin-mangled) symbol, plus a declare so
# raw-ABI call sites link against it.  Parameters arrive per AAPCS64 in
# x0..x7; the body must `ret`.
-> emit_embedded_asm_function(f)
  out = StringBuffer(1024 + f[:embedded_asm].size())
  out << "module asm \".text\"\n"
  out << "module asm \".balign 64\"\n"
  out << "module asm \".globl _" + f[:name] + "\"\n"
  out << "module asm \"_" + f[:name] + ":\"\n"
  lines = f[:embedded_asm].split("\n")
  i = 0
  while i < lines.size()
    line = lines[i]
    if line.strip().size() > 0
      out << "module asm \"" + escape_llvm_string(line) + "\"\n"
    i += 1
  out << "declare "
  out << f[:return_type]
  out << " @"
  out << f[:name]
  out << "("
  parts = []
  j = 0
  while j < f[:params].size()
    parts.push("i64")
    j += 1
  out << parts.join(", ")
  out << ") nounwind\n"
  out.to_s()

# The emitted triple decides per-arch instruction selection (the asm-backed
# carry ops emit hand templates on arm64 and portable IR loops elsewhere).
-> emit_target_is_arm64(mod)
  triple = mod[:llvm_triple]
  if triple == nil
    return true
  triple.index("arm64") != nil || triple.index("aarch64") != nil

-> emit_target_is_windows(mod)
  triple = mod[:llvm_triple]
  if triple == nil
    return false
  triple.index("windows") != nil || triple.index("mingw") != nil || triple.index("msvc") != nil

-> emit_function(f, string_wvs, slab_info, used_ptr_ids, frame_pointers = false, host_fn_attrs = "", attr_groups = nil, arm64_target = true, windows_target = false, preserve_debug_frames = false)
  if f[:embedded_ll] != nil
    return emit_embedded_ll_function(f)
  if f[:embedded_asm] != nil
    return emit_embedded_asm_function(f)
  out = StringBuffer(4096)
  ret_ty = f[:return_type]
  attr_text = function_attr_text(frame_pointers, host_fn_attrs, preserve_debug_frames)
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
      if wire_kind(inst) == :call_method_i64 && wire_get(inst, :args) != nil
        argc = wire_get(inst, :args).size()
        needs_scratch = argc > 0 && !scalar_source_call?(inst)
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
  phi_label_redirects = build_phi_label_redirects(f, arm64_target)
  i = 0
  while i < f[:blocks].size()
    blk = f[:blocks][i]
    out << blk[:label]
    out << ":\n"
    # Entry block: emit allocas for non-promoted var slots
    if i == 0
      if slots != nil
        heap_slots = f[:heap_slot_names]
        slot_names = slots.keys()
        j = 0
        while j < slot_names.size()
          ptr = slots[slot_names[j]]
          if ptr.starts_with?("%v") && (promoted == nil || promoted[ptr] == nil)
            if heap_slots != nil && heap_slots[slot_names[j]] == true
              # Slot captured by an escaping closure: heap cell, not alloca,
              # so the capture's by-reference pointer outlives this frame.
              # The 16-byte zeroed cell covers every slot type incl. i128.
              out << "  "
              out << ptr
              out << " = call ptr @w_closure_cell_new()\n"
            else
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
      out << render_instruction(blk[:instructions][j], string_wvs, used_ptr_ids, phi_label_redirects, fp_flags, arm64_target, windows_target)
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
    parts.push("i64 %" + llvm_safe_name(f[:params][i]))
    i += 1
  parts.join(", ")

# -- Instruction rendering --

-> render_guarded_i48(inst)
  bid = wire_get(inst, :block_id).to_s()
  t = wire_get(inst, :temp)
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
  out << ltag + " = and i64 " + wire_get(inst, :lhs) + ", " + machine_i64_text(w_tag_mask) + "\n  "
  out << lis_int + " = icmp eq i64 " + ltag + ", " + machine_i64_text(w_tag_int) + "\n  "
  out << rtag + " = and i64 " + wire_get(inst, :rhs) + ", " + machine_i64_text(w_tag_mask) + "\n  "
  out << ris_int + " = icmp eq i64 " + rtag + ", " + machine_i64_text(w_tag_int) + "\n  "
  out << both_int + " = and i1 " + lis_int + ", " + ris_int + "\n  "
  out << "br i1 " + both_int + ", label %g.ok." + bid + ", label %g.rt." + bid + ", !prof !31411\n"
  out << "g.ok." + bid + ":\n  "
  out << lhs_shl + " = shl i64 " + wire_get(inst, :lhs) + ", 16\n  "
  out << lhs_raw + " = ashr i64 " + lhs_shl + ", 16\n  "
  out << rhs_shl + " = shl i64 " + wire_get(inst, :rhs) + ", 16\n  "
  out << rhs_raw + " = ashr i64 " + rhs_shl + ", 16\n  "

  op = wire_kind(inst)
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

  # inverted operand order: the UNLIKELY target is first here, so swap the
  # weights by listing the likely count second.
  out << "br i1 " + ovf + ", label %g.rt." + bid + ", label %g.box." + bid + ", !prof !31412\n"
  out << "g.box." + bid + ":\n  "
  out << masked + " = and i64 " + raw + ", " + machine_i64_text(w_payload_mask) + "\n  "
  out << boxed + " = or i64 " + masked + ", " + machine_i64_text(w_tag_int) + "\n  "
  out << "br label %g.done." + bid + "\n"
  out << "g.rt." + bid + ":\n  "
  # `Math.trap` mode: the slow (overflow / non-int-operand) path aborts via
  # the LLVM trap intrinsic instead of calling the BigInt-promoting runtime.
  # g.rt terminates with `unreachable`, so g.done has the single g.box
  # predecessor and its phi has one incoming value.
  if wire_get(inst, :trap) == true
    out << "call void @llvm.trap()\n  "
    out << "unreachable\n"
    out << "g.done." + bid + ":\n  "
    out << t + " = phi i64 \[" + boxed + ", %g.box." + bid + "]"
  else
    # cold sinks the fallback out of the loop body; preserve_mostcc
    # additionally keeps caller-saved registers live across the call so
    # the inline-int phase's loop state never spills. The convention is
    # applied ONLY to the mut entries — they have no other IR callsites,
    # while w_add/w_sub/w_mul are called plain-CC all over the module and
    # a declaration/callsite mismatch is UB. Their C definitions carry
    # __attribute__((preserve_most)) to match.
    cc = ""
    if wire_get(inst, :rt_fallback) in ("w_bigint_add_mut" "w_bigint_sub_mut" "w_bigint_mul_mut" "w_bigint_div_mut" "w_bigint_mod_mut" "w_bigint_and_mut" "w_bigint_or_mut" "w_bigint_xor_mut" "w_bigint_shl_mut" "w_bigint_shr_mut")
      cc = "preserve_mostcc "
    out << slow + " = call " + cc + "i64 @" + wire_get(inst, :rt_fallback) + "(i64 " + wire_get(inst, :lhs) + ", i64 " + wire_get(inst, :rhs) + ") cold\n  "
    out << "br label %g.done." + bid + "\n"
    out << "g.done." + bid + ":\n  "
    out << t + " = phi i64 \[" + boxed + ", %g.box." + bid + "], \[" + slow + ", %g.rt." + bid + "]"
  out.to_s()

-> render_instruction(inst, string_wvs, used_ptr_ids, phi_label_redirects = nil, fp_flags = "", arm64_target = true, windows_target = false)
  op = wire_kind(inst)

  case op
  # Memory
  when :alloca_i64
    wire_get(inst, :ptr) + " = alloca i64, align 8"
  when :alloca_i128
    wire_get(inst, :ptr) + " = alloca i128, align 16"
  when :store_i64
    "store i64 " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :ptr) + ", align 8"
  when :store_i128
    "store i128 " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :ptr) + ", align 16"
  when :store_float
    "store float " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :ptr) + ", align 4"
  when :store_double
    "store double " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :ptr) + ", align 8"
  when :load_i64
    wire_get(inst, :temp) + " = load i64, ptr " + wire_get(inst, :ptr) + ", align 8" + range_metadata_suffix(inst, "i64")
  when :load_float
    wire_get(inst, :temp) + " = load float, ptr " + wire_get(inst, :ptr) + ", align 4"
  when :load_double
    wire_get(inst, :temp) + " = load double, ptr " + wire_get(inst, :ptr) + ", align 8"
  when :load_u8_ptr
    p = wire_get(inst, :temp) + ".p"
    ep = wire_get(inst, :temp) + ".ep"
    b = wire_get(inst, :temp) + ".b"
    p + " = inttoptr i64 " + wire_get(inst, :ptr) + " to ptr\n  " + ep + " = getelementptr i8, ptr " + p + ", i64 " + wire_get(inst, :index) + "\n  " + b + " = load i8, ptr " + ep + ", align 1" + range_metadata_suffix(inst, "i8") + "\n  " + wire_get(inst, :temp) + " = zext i8 " + b + " to i64"
  when :store_u8_ptr
    p = wire_get(inst, :temp) + ".p"
    ep = wire_get(inst, :temp) + ".ep"
    b = wire_get(inst, :temp) + ".b"
    p + " = inttoptr i64 " + wire_get(inst, :ptr) + " to ptr\n  " + ep + " = getelementptr i8, ptr " + p + ", i64 " + wire_get(inst, :index) + "\n  " + b + " = trunc i64 " + wire_get(inst, :value) + " to i8\n  store i8 " + b + ", ptr " + ep + ", align 1\n  " + wire_get(inst, :temp) + " = zext i8 " + b + " to i64"
  when :load_u32_ptr
    p = wire_get(inst, :temp) + ".p"
    ep = wire_get(inst, :temp) + ".ep"
    w = wire_get(inst, :temp) + ".w"
    p + " = inttoptr i64 " + wire_get(inst, :ptr) + " to ptr\n  " + ep + " = getelementptr i8, ptr " + p + ", i64 " + wire_get(inst, :index) + "\n  " + w + " = load i32, ptr " + ep + ", align 1" + range_metadata_suffix(inst, "i32") + "\n  " + wire_get(inst, :temp) + " = zext i32 " + w + " to i64"
  when :load_u64_ptr
    p = wire_get(inst, :temp) + ".p"
    ep = wire_get(inst, :temp) + ".ep"
    p + " = inttoptr i64 " + wire_get(inst, :ptr) + " to ptr\n  " + ep + " = getelementptr i8, ptr " + p + ", i64 " + wire_get(inst, :index) + "\n  " + wire_get(inst, :temp) + " = load i64, ptr " + ep + ", align 1" + range_metadata_suffix(inst, "i64")
  when :ptr_slot_get
    p = wire_get(inst, :temp) + ".p"
    ep = wire_get(inst, :temp) + ".ep"
    slot_type = wire_get(inst, :slot_type)
    if slot_type == "w64" || slot_type == "i64" || slot_type == "u64"
      p + " = inttoptr i64 " + wire_get(inst, :ptr) + " to ptr\n  " + ep + " = getelementptr i64, ptr " + p + ", i64 " + wire_get(inst, :index) + "\n  " + wire_get(inst, :temp) + " = load i64, ptr " + ep + ", align 8"
    elsif slot_type == "u8" || slot_type == "i8"
      b = wire_get(inst, :temp) + ".b"
      p + " = inttoptr i64 " + wire_get(inst, :ptr) + " to ptr\n  " + ep + " = getelementptr i8, ptr " + p + ", i64 " + wire_get(inst, :index) + "\n  " + b + " = load i8, ptr " + ep + ", align 1\n  " + wire_get(inst, :temp) + " = zext i8 " + b + " to i64"
    else
      p + " = inttoptr i64 " + wire_get(inst, :ptr) + " to ptr\n  " + ep + " = getelementptr i64, ptr " + p + ", i64 " + wire_get(inst, :index) + "\n  " + wire_get(inst, :temp) + " = load i64, ptr " + ep + ", align 8"
  when :load_i128
    wire_get(inst, :temp) + " = load i128, ptr " + wire_get(inst, :ptr) + ", align 16" + range_metadata_suffix(inst, "i128")

  # Integer arithmetic
  when :add_i64
    wire_get(inst, :temp) + " = add i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :sub_i64
    wire_get(inst, :temp) + " = sub i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :mul_i64
    wire_get(inst, :temp) + " = mul i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :sdiv_i64
    wire_get(inst, :temp) + " = sdiv i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :udiv_i64
    wire_get(inst, :temp) + " = udiv i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :srem_i64
    wire_get(inst, :temp) + " = srem i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :urem_i64
    wire_get(inst, :temp) + " = urem i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :add_i128
    wire_get(inst, :temp) + " = add i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :sub_i128
    wire_get(inst, :temp) + " = sub i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :mul_i128
    wire_get(inst, :temp) + " = mul i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :mulhi_u64
    # high 64 bits of the unsigned 64x64->128 product. LLVM lowers this to a
    # single UMULH on arm64 / MULX on x86 — the carry-primitive `mulhi`.
    t = wire_get(inst, :temp)
    o = StringBuffer(192)
    o << t + ".az = zext i64 " + wire_get(inst, :lhs) + " to i128\n  "
    o << t + ".bz = zext i64 " + wire_get(inst, :rhs) + " to i128\n  "
    o << t + ".pp = mul i128 " + t + ".az, " + t + ".bz\n  "
    o << t + ".hs = lshr i128 " + t + ".pp, 64\n  "
    o << t + " = trunc i128 " + t + ".hs to i64"
    o.to_s()
  when :addcarry_u64
    # carry-out (0/1) of a + b via i128 widening: ((zext a + zext b) >> 64).
    # LLVM keeps the carry in the flag and chains these as ADDS/ADCS instead of
    # materialising it with CMP/CSET. Carry-primitive `addcarry`.
    t = wire_get(inst, :temp)
    o = StringBuffer(192)
    o << t + ".az = zext i64 " + wire_get(inst, :lhs) + " to i128\n  "
    o << t + ".bz = zext i64 " + wire_get(inst, :rhs) + " to i128\n  "
    o << t + ".sm = add i128 " + t + ".az, " + t + ".bz\n  "
    o << t + ".hs = lshr i128 " + t + ".sm, 64\n  "
    o << t + " = trunc i128 " + t + ".hs to i64"
    o.to_s()
  when :subborrow_u64
    # borrow-out (0/1) of a - b via i128: ((zext a - zext b) >> 127). When a<b the
    # i128 difference is negative (sign bit set) -> 1, else 0. LLVM chains these as
    # SUBS/SBCS. Carry-primitive `subborrow`.
    t = wire_get(inst, :temp)
    o = StringBuffer(192)
    o << t + ".az = zext i64 " + wire_get(inst, :lhs) + " to i128\n  "
    o << t + ".bz = zext i64 " + wire_get(inst, :rhs) + " to i128\n  "
    o << t + ".df = sub i128 " + t + ".az, " + t + ".bz\n  "
    o << t + ".hs = lshr i128 " + t + ".df, 127\n  "
    o << t + " = trunc i128 " + t + ".hs to i64"
    o.to_s()
  when :asm_add_test
    # POC: prove LLVM inline asm emits/links/runs. a+b via an aarch64 ADD.
    wire_get(inst, :temp) + " = call i64 asm sideeffect \"add ${0:x}, ${1:x}, ${2:x}\", \"=r,r,r\"(i64 " + wire_get(inst, :lhs) + ", i64 " + wire_get(inst, :rhs) + ")"
  when :arr_data_ptr
    # raw data-base pointer (as i64) of a u64[]: header tag-mask, +16, load ptr.
    t = wire_get(inst, :temp)
    t + ".ar = and i64 " + wire_get(inst, :arr) + ", 140737488355312\n  " + t + ".bp = inttoptr i64 " + t + ".ar to ptr\n  " + t + ".gp = getelementptr i8, ptr " + t + ".bp, i64 16\n  " + t + ".pp = load ptr, ptr " + t + ".gp\n  " + t + " = ptrtoint ptr " + t + ".pp to i64"
  when :asm_add_n
    # Flag-threaded adc loop: out[i]=a[i]+b[i] over n limbs, carry kept
    # in the flag across iterations (sub/cbnz don't clobber C). Returns final carry.
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Acmn xzr, xzr\\0A1:\\0Aldr x10, \[x13], #8\\0Aldr x11, \[x14], #8\\0Aadcs x12, x10, x11\\0Astr x12, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Acset ${0:x}, cs"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}\"(i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_neon_umull
    # POC: NEON 2-lane umull loop. out[2i,2i+1] = a[i].lanes * b[i].lanes (u32->u64).
    # All via memory + GPR pointer operands; NEON work internal (v-reg clobbers).
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0A1:\\0Ald1 {v1.2s}, \[x13], #8\\0Ald1 {v2.2s}, \[x14], #8\\0Aumull v0.2d, v1.2s, v2.2s\\0Ast1 {v0.2d}, \[x15], #16\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{memory},~{cc}\"(i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_neon_redc
    # NEON 2-lane Montgomery REDC: out[i] = REDC(a[i]*b[i]) mod p=998244353, R=2^32.
    # ninv=998244351. t=a*b; m=(t mod R)*ninv mod R; t=(t+m*p)>>32; if t>=p t-=p.
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Amov w10, #1\\0Amovk w10, #15232, lsl #16\\0Adup v5.2s, w10\\0Auxtl v7.2d, v5.2s\\0Amov w11, #65535\\0Amovk w11, #15231, lsl #16\\0Adup v6.2s, w11\\0A1:\\0Ald1 {v1.2s}, \[x13], #8\\0Ald1 {v2.2s}, \[x14], #8\\0Aumull v0.2d, v1.2s, v2.2s\\0Axtn v3.2s, v0.2d\\0Amul v3.2s, v3.2s, v6.2s\\0Aumull v4.2d, v3.2s, v5.2s\\0Aadd v0.2d, v0.2d, v4.2d\\0Aushr v0.2d, v0.2d, #32\\0Asub v8.2d, v0.2d, v7.2d\\0Acmhs v16.2d, v0.2d, v7.2d\\0Abit v0.16b, v8.16b, v16.16b\\0Axtn v0.2s, v0.2d\\0Ast1 {v0.2s}, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x11},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{v16},~{memory},~{cc}\"(i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_neon_redc4
    # NEON 4-lane Montgomery REDC: out lanes = REDC(a*b) mod p=998244353, R=2^32.
    # Processes 4 u32 lanes (= 2 u64 elements) per iter via umull+umull2. n = #pairs.
    # ninv=998244351. t=a*b; m=(t&mask)*ninv&mask; t=(t+m*p)>>32; if t>=p t-=p.
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Amov w10, #1\\0Amovk w10, #15232, lsl #16\\0Adup v5.4s, w10\\0Auxtl v7.2d, v5.2s\\0Amov w11, #65535\\0Amovk w11, #15231, lsl #16\\0Adup v6.4s, w11\\0A1:\\0Ald1 {v1.4s}, \[x13], #16\\0Ald1 {v2.4s}, \[x14], #16\\0Aumull v0.2d, v1.2s, v2.2s\\0Aumull2 v17.2d, v1.4s, v2.4s\\0Axtn v3.2s, v0.2d\\0Amul v3.2s, v3.2s, v6.2s\\0Aumull v4.2d, v3.2s, v5.2s\\0Aadd v0.2d, v0.2d, v4.2d\\0Aushr v0.2d, v0.2d, #32\\0Asub v8.2d, v0.2d, v7.2d\\0Acmhs v16.2d, v0.2d, v7.2d\\0Abit v0.16b, v8.16b, v16.16b\\0Axtn v18.2s, v17.2d\\0Amul v18.2s, v18.2s, v6.2s\\0Aumull v19.2d, v18.2s, v5.2s\\0Aadd v17.2d, v17.2d, v19.2d\\0Aushr v17.2d, v17.2d, #32\\0Asub v20.2d, v17.2d, v7.2d\\0Acmhs v21.2d, v17.2d, v7.2d\\0Abit v17.16b, v20.16b, v21.16b\\0Axtn v0.2s, v0.2d\\0Axtn2 v0.4s, v17.2d\\0Ast1 {v0.4s}, \[x15], #16\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x11},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{v16},~{v17},~{v18},~{v19},~{v20},~{v21},~{memory},~{cc}\"(i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_neon_madd4
    # NEON 4-lane modular add mod p=998244353: out=a+b; if out>=p out-=p. 4 u32/iter.
    # inputs < p, sum < 2p < 2^31 so 32-bit lane add cannot overflow. n = #pairs.
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Amov w10, #1\\0Amovk w10, #15232, lsl #16\\0Ains v5.s\[0], w10\\0Ains v5.s\[1], w10\\0Ains v5.s\[2], w10\\0Ains v5.s\[3], w10\\0A1:\\0Ald1 {v1.4s}, \[x13], #16\\0Ald1 {v2.4s}, \[x14], #16\\0Aadd v0.4s, v1.4s, v2.4s\\0Acmhs v4.4s, v0.4s, v5.4s\\0Aand v6.16b, v4.16b, v5.16b\\0Asub v0.4s, v0.4s, v6.4s\\0Ast1 {v0.4s}, \[x15], #16\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{v4},~{v5},~{v6},~{memory},~{cc}\"(i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_neon_msub4
    # NEON 4-lane modular sub mod p=998244353: r=a-b; if a<b r+=p. 4 u32/iter.
    # use: d=a-b (u32 wrap); if a<b (cmhi b>a) add p. n = #pairs.
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Amov w10, #1\\0Amovk w10, #15232, lsl #16\\0Adup v5.4s, w10\\0A1:\\0Ald1 {v1.4s}, \[x13], #16\\0Ald1 {v2.4s}, \[x14], #16\\0Asub v0.4s, v1.4s, v2.4s\\0Acmhi v4.4s, v2.4s, v1.4s\\0Aand v6.16b, v4.16b, v5.16b\\0Aadd v0.4s, v0.4s, v6.4s\\0Ast1 {v0.4s}, \[x15], #16\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{v4},~{v5},~{v6},~{memory},~{cc}\"(i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_neon_ntt_stage
    # Whole-butterfly NEON DIT NTT stage, mod p=998244353, Montgomery, R=2^32.
    # v = coeffs as 4xu32/16B; stw = per-stage twiddles (u32, len=half). For each of
    # nblocks blocks: a=block base, b=a+half; for halfq groups of 4: t=REDC(b,w);
    # store a+t at a, a-t at b. ALL in vector regs (load->modmul->add/sub->store).
    # operands: ${1}=v ${2}=stw ${3}=nblocks ${4}=halfq.  half_bytes=halfq*16.
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x9, ${3:x}\\0Amov x10, ${4:x}\\0Alsl x11, x10, #4\\0Amov w12, #1\\0Amovk w12, #15232, lsl #16\\0Adup v5.4s, w12\\0Auxtl v7.2d, v5.2s\\0Amov w12, #65535\\0Amovk w12, #15231, lsl #16\\0Adup v6.4s, w12\\0A2:\\0Amov x15, x13\\0Aadd x16, x13, x11\\0Amov x17, x14\\0Amov x8, x10\\0A3:\\0Ald1 {v1.4s}, \[x15]\\0Ald1 {v2.4s}, \[x16]\\0Ald1 {v9.4s}, \[x17], #16\\0Aumull v0.2d, v2.2s, v9.2s\\0Aumull2 v10.2d, v2.4s, v9.4s\\0Axtn v3.2s, v0.2d\\0Amul v3.2s, v3.2s, v6.2s\\0Aumull v4.2d, v3.2s, v5.2s\\0Aadd v0.2d, v0.2d, v4.2d\\0Aushr v0.2d, v0.2d, #32\\0Asub v8.2d, v0.2d, v7.2d\\0Acmhs v11.2d, v0.2d, v7.2d\\0Abit v0.16b, v8.16b, v11.16b\\0Axtn v12.2s, v10.2d\\0Amul v12.2s, v12.2s, v6.2s\\0Aumull v13.2d, v12.2s, v5.2s\\0Aadd v10.2d, v10.2d, v13.2d\\0Aushr v10.2d, v10.2d, #32\\0Asub v14.2d, v10.2d, v7.2d\\0Acmhs v15.2d, v10.2d, v7.2d\\0Abit v10.16b, v14.16b, v15.16b\\0Axtn v0.2s, v0.2d\\0Axtn2 v0.4s, v10.2d\\0Aadd v16.4s, v1.4s, v0.4s\\0Acmhs v17.4s, v16.4s, v5.4s\\0Aand v18.16b, v17.16b, v5.16b\\0Asub v16.4s, v16.4s, v18.4s\\0Asub v19.4s, v1.4s, v0.4s\\0Acmhi v20.4s, v0.4s, v1.4s\\0Aand v21.16b, v20.16b, v5.16b\\0Aadd v19.4s, v19.4s, v21.4s\\0Ast1 {v16.4s}, \[x15], #16\\0Ast1 {v19.4s}, \[x16], #16\\0Asub x8, x8, #1\\0Acbnz x8, 3b\\0Aadd x13, x13, x11, lsl #1\\0Asub x9, x9, #1\\0Acbnz x9, 2b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{v9},~{v10},~{v11},~{v12},~{v13},~{v14},~{v15},~{v16},~{v17},~{v18},~{v19},~{v20},~{v21},~{memory},~{cc}\"(i64 " + wire_get(inst, :vp) + ", i64 " + wire_get(inst, :twp) + ", i64 " + wire_get(inst, :nb) + ", i64 " + wire_get(inst, :hq) + ")"
  when :asm_gold_stage
    # Scalar Goldilocks radix-4 DIF NTT stage. P=2^64-2^32+1, ep=2^32-1.
    # ${1}=v ${2}=stw ${3}=nblocks ${4}=q.  block = 4*q coeffs = q*32 bytes.
    # Reduced register footprint (indexed loads, 3 scratch). Regs:
    #  x1=block base, x2=stw ptr, x3=stw base, x4=block ctr, x5=q (group reload),
    #  x6=qbytes(q*8), x7=group ctr, x8=i0 ptr, x9=2*qbytes, x10=3*qbytes,
    #  x12=ep, x13=pp(=P); coeffs/y in x14..x17; t0=x19 t1=x20 t2=x21 d=x22
    #  t3=x23; scratch x24,x25,x26 (x26 also holds w/prod in mul phase).
    # i1..i3 via indexed addressing [x8,x6]/[x8,x9]/[x8,x10].
    t = wire_get(inst, :temp)
    asmt = "mov x1, ${1:x}\\0Amov x3, ${2:x}\\0Amov x4, ${3:x}\\0Amov x5, ${4:x}\\0Alsl x6, x5, #3\\0Alsl x9, x5, #4\\0Aadd x10, x9, x6\\0Amovz x12, #65535\\0Amovk x12, #65535, lsl #16\\0Amovz x13, #1\\0Amovk x13, #65535, lsl #32\\0Amovk x13, #65535, lsl #48\\0A2:\\0Amov x8, x1\\0Amov x2, x3\\0Amov x7, x5\\0A3:\\0Aldr x14, \[x8]\\0Aldr x15, \[x8, x6]\\0Aldr x16, \[x8, x9]\\0Aldr x17, \[x8, x10]\\0Aadds x19, x14, x16\\0Acsel x24, x12, xzr, cs\\0Aadd x19, x19, x24\\0Asubs x24, x19, x13\\0Acsel x19, x24, x19, hs\\0Asubs x20, x14, x16\\0Acsel x24, x13, xzr, cc\\0Aadd x20, x20, x24\\0Aadds x21, x15, x17\\0Acsel x24, x12, xzr, cs\\0Aadd x21, x21, x24\\0Asubs x24, x21, x13\\0Acsel x21, x24, x21, hs\\0Asubs x22, x15, x17\\0Acsel x24, x13, xzr, cc\\0Aadd x22, x22, x24\\0Alsl x24, x22, #48\\0Aubfx x25, x22, #16, #48\\0Alsr x26, x25, #32\\0Aand x25, x25, x12\\0Asubs x23, x24, x26\\0Acsel x24, x12, xzr, cc\\0Asub x23, x23, x24\\0Alsl x24, x25, #32\\0Asub x24, x24, x25\\0Aadds x23, x23, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x23, x23, x24\\0Asubs x24, x23, x13\\0Acsel x23, x24, x23, hs\\0Aadds x14, x19, x21\\0Acsel x24, x12, xzr, cs\\0Aadd x14, x14, x24\\0Asubs x24, x14, x13\\0Acsel x14, x24, x14, hs\\0Aadds x15, x20, x23\\0Acsel x24, x12, xzr, cs\\0Aadd x15, x15, x24\\0Asubs x24, x15, x13\\0Acsel x15, x24, x15, hs\\0Asubs x16, x19, x21\\0Acsel x24, x13, xzr, cc\\0Aadd x16, x16, x24\\0Asubs x17, x20, x23\\0Acsel x24, x13, xzr, cc\\0Aadd x17, x17, x24\\0Astr x14, \[x8]\\0Aldr x26, \[x2]\\0Amul x25, x15, x26\\0Aumulh x26, x15, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x25, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x25, x25, x24\\0Asubs x24, x25, x13\\0Acsel x25, x24, x25, hs\\0Astr x25, \[x8, x6]\\0Aldr x26, \[x2, #8]\\0Amul x25, x16, x26\\0Aumulh x26, x16, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x25, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x25, x25, x24\\0Asubs x24, x25, x13\\0Acsel x25, x24, x25, hs\\0Astr x25, \[x8, x9]\\0Aldr x26, \[x2, #16]\\0Amul x25, x17, x26\\0Aumulh x26, x17, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x25, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x25, x25, x24\\0Asubs x24, x25, x13\\0Acsel x25, x24, x25, hs\\0Astr x25, \[x8, x10]\\0Aadd x8, x8, #8\\0Aadd x2, x2, #24\\0Asubs x7, x7, #1\\0Acbnz x7, 3b\\0Aadd x1, x1, x6, lsl #2\\0Asubs x4, x4, #1\\0Acbnz x4, 2b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x1},~{x2},~{x3},~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{x19},~{x20},~{x21},~{x22},~{x23},~{x24},~{x25},~{x26},~{memory},~{cc}\"(i64 " + wire_get(inst, :vp) + ", i64 " + wire_get(inst, :twp) + ", i64 " + wire_get(inst, :nb) + ", i64 " + wire_get(inst, :hq) + ")"
  when :asm_gold_stage_inv
    # Scalar Goldilocks radix-4 DIT (inverse) NTT stage. P=2^64-2^32+1, ep=2^32-1.
    # ${1}=v ${2}=stw ${3}=iv ${4}=nblocks ${5}=q.  block = 4*q coeffs.
    #  x1=block base, x2=stw ptr, x3=stw base, x4=block ctr, x5=q, x6=qbytes,
    #  x7=group ctr, x8=i0 ptr, x9=2*qbytes, x10=3*qbytes, x11=iinv,
    #  x12=ep, x13=pp; coeffs a0..a3 in x14..x17; t0=x19 t1=x20 t2=x21 d=x22
    #  t3=x23; scratch x24,x25,x26.  Twiddle FIRST (in place), then combine.
    t = wire_get(inst, :temp)
    asmt = "mov x1, ${1:x}\\0Amov x3, ${2:x}\\0Aldr x11, \[${3:x}]\\0Amov x4, ${4:x}\\0Alsl x6, ${5:x}, #3\\0Alsl x9, x6, #1\\0Aadd x10, x9, x6\\0Amovz x12, #65535\\0Amovk x12, #65535, lsl #16\\0Amovz x13, #1\\0Amovk x13, #65535, lsl #32\\0Amovk x13, #65535, lsl #48\\0A2:\\0Amov x8, x1\\0Amov x2, x3\\0Alsr x7, x6, #3\\0A3:\\0Aldr x14, \[x8]\\0Aldr x15, \[x8, x6]\\0Aldr x16, \[x8, x9]\\0Aldr x17, \[x8, x10]\\0Aldr x26, \[x2]\\0Amul x25, x15, x26\\0Aumulh x26, x15, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x15, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x15, x15, x24\\0Asubs x24, x15, x13\\0Acsel x15, x24, x15, hs\\0Aldr x26, \[x2, #8]\\0Amul x25, x16, x26\\0Aumulh x26, x16, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x16, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x16, x16, x24\\0Asubs x24, x16, x13\\0Acsel x16, x24, x16, hs\\0Aldr x26, \[x2, #16]\\0Amul x25, x17, x26\\0Aumulh x26, x17, x26\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x17, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x17, x17, x24\\0Asubs x24, x17, x13\\0Acsel x17, x24, x17, hs\\0Aadds x19, x14, x16\\0Acsel x24, x12, xzr, cs\\0Aadd x19, x19, x24\\0Asubs x24, x19, x13\\0Acsel x19, x24, x19, hs\\0Asubs x20, x14, x16\\0Acsel x24, x13, xzr, cc\\0Aadd x20, x20, x24\\0Aadds x21, x15, x17\\0Acsel x24, x12, xzr, cs\\0Aadd x21, x21, x24\\0Asubs x24, x21, x13\\0Acsel x21, x24, x21, hs\\0Asubs x22, x15, x17\\0Acsel x24, x13, xzr, cc\\0Aadd x22, x22, x24\\0Amul x25, x22, x11\\0Aumulh x26, x22, x11\\0Alsr x24, x26, #32\\0Aand x26, x26, x12\\0Asubs x25, x25, x24\\0Acsel x24, x12, xzr, cc\\0Asub x25, x25, x24\\0Alsl x24, x26, #32\\0Asub x24, x24, x26\\0Aadds x23, x25, x24\\0Acsel x24, x12, xzr, cs\\0Aadd x23, x23, x24\\0Asubs x24, x23, x13\\0Acsel x23, x24, x23, hs\\0Aadds x14, x19, x21\\0Acsel x24, x12, xzr, cs\\0Aadd x14, x14, x24\\0Asubs x24, x14, x13\\0Acsel x14, x24, x14, hs\\0Astr x14, \[x8]\\0Aadds x15, x20, x23\\0Acsel x24, x12, xzr, cs\\0Aadd x15, x15, x24\\0Asubs x24, x15, x13\\0Acsel x15, x24, x15, hs\\0Astr x15, \[x8, x6]\\0Asubs x16, x19, x21\\0Acsel x24, x13, xzr, cc\\0Aadd x16, x16, x24\\0Astr x16, \[x8, x9]\\0Asubs x17, x20, x23\\0Acsel x24, x13, xzr, cc\\0Aadd x17, x17, x24\\0Astr x17, \[x8, x10]\\0Aadd x8, x8, #8\\0Aadd x2, x2, #24\\0Asubs x7, x7, #1\\0Acbnz x7, 3b\\0Aadd x1, x1, x6, lsl #2\\0Asubs x4, x4, #1\\0Acbnz x4, 2b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,~{x1},~{x2},~{x3},~{x4},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{x19},~{x20},~{x21},~{x22},~{x23},~{x24},~{x25},~{x26},~{memory},~{cc}\"(i64 " + wire_get(inst, :vp) + ", i64 " + wire_get(inst, :twp) + ", i64 " + wire_get(inst, :ivp) + ", i64 " + wire_get(inst, :nb) + ", i64 " + wire_get(inst, :hq) + ")"
  when :asm_neon_gadd2
    # NEON 2-lane Goldilocks add: out[i] lanes = gadd(a,b) mod P=2^64-2^32+1.
    # r=a+b; if r<a (overflow) r+=ep(0xFFFFFFFF); if r>=pp(2^64-ep) r-=pp. 2 u64/op.
    t = wire_get(inst, :temp)
    asmt = "mov x13, ${1:x}\\0Amov x14, ${2:x}\\0Amov x15, ${3:x}\\0Amov x9, ${4:x}\\0Amovz w10, #65535\\0Amovk w10, #65535, lsl #16\\0Adup v7.2d, x10\\0Amovz x11, #1\\0Amovk x11, #65535, lsl #32\\0Amovk x11, #65535, lsl #48\\0Adup v6.2d, x11\\0A1:\\0Ald1 {v1.2d}, \[x13], #16\\0Ald1 {v2.2d}, \[x14], #16\\0Aadd v0.2d, v1.2d, v2.2d\\0Acmhi v3.2d, v1.2d, v0.2d\\0Aand v4.16b, v3.16b, v7.16b\\0Aadd v0.2d, v0.2d, v4.2d\\0Acmhs v5.2d, v0.2d, v6.2d\\0Aand v8.16b, v5.16b, v6.16b\\0Asub v0.2d, v0.2d, v8.2d\\0Ast1 {v0.2d}, \[x15], #16\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,~{x9},~{x10},~{x11},~{x13},~{x14},~{x15},~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{memory},~{cc}\"(i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_add_no
    # offset add_n: out[oo..]=a[ao..]+b[bo..] over n limbs; ptr = base + off<<3 in
    # asm. Flag-threaded adc returns carry. (basecase for the Toom ladder)
    # Non-arm64 targets get a portable i128-carry IR loop with identical
    # semantics (the arch-gated-kernel contract: WIRE op is the portable
    # boundary, the emitter target-selects the body).
    t = wire_get(inst, :temp)
    if !arm64_target
      bid = t.slice(1, t.size() - 1)
      po = StringBuffer(1024)
      po << t + ".oo3 = shl i64 " + wire_get(inst, :ooff) + ", 3\n  "
      po << t + ".ob = add i64 " + wire_get(inst, :outp) + ", " + t + ".oo3\n  "
      po << t + ".ao3 = shl i64 " + wire_get(inst, :aoff) + ", 3\n  "
      po << t + ".ab = add i64 " + wire_get(inst, :ap) + ", " + t + ".ao3\n  "
      po << t + ".bo3 = shl i64 " + wire_get(inst, :boff) + ", 3\n  "
      po << t + ".bb = add i64 " + wire_get(inst, :bp) + ", " + t + ".bo3\n  "
      po << "br label %ano.pre." + bid + "\n"
      po << "ano.pre." + bid + ":\n  "
      po << "br label %ano.head." + bid + "\n"
      po << "ano.head." + bid + ":\n  "
      po << t + ".i = phi i64 \[ 0, %ano.pre." + bid + " ], \[ " + t + ".i2, %ano.body." + bid + " ]\n  "
      po << t + ".c = phi i64 \[ 0, %ano.pre." + bid + " ], \[ " + t + ".c2, %ano.body." + bid + " ]\n  "
      po << t + ".done = icmp sge i64 " + t + ".i, " + wire_get(inst, :n) + "\n  "
      po << "br i1 " + t + ".done, label %ano.exit." + bid + ", label %ano.body." + bid + "\n"
      po << "ano.body." + bid + ":\n  "
      po << t + ".i8 = shl i64 " + t + ".i, 3\n  "
      po << t + ".aa = add i64 " + t + ".ab, " + t + ".i8\n  "
      po << t + ".ap = inttoptr i64 " + t + ".aa to ptr\n  "
      po << t + ".av = load i64, ptr " + t + ".ap, align 8\n  "
      po << t + ".ba = add i64 " + t + ".bb, " + t + ".i8\n  "
      po << t + ".bpp = inttoptr i64 " + t + ".ba to ptr\n  "
      po << t + ".bv = load i64, ptr " + t + ".bpp, align 8\n  "
      po << t + ".az = zext i64 " + t + ".av to i128\n  "
      po << t + ".bz = zext i64 " + t + ".bv to i128\n  "
      po << t + ".cz = zext i64 " + t + ".c to i128\n  "
      po << t + ".s1 = add i128 " + t + ".az, " + t + ".bz\n  "
      po << t + ".s2 = add i128 " + t + ".s1, " + t + ".cz\n  "
      po << t + ".lo = trunc i128 " + t + ".s2 to i64\n  "
      po << t + ".hi = lshr i128 " + t + ".s2, 64\n  "
      po << t + ".c2 = trunc i128 " + t + ".hi to i64\n  "
      po << t + ".oa = add i64 " + t + ".ob, " + t + ".i8\n  "
      po << t + ".op = inttoptr i64 " + t + ".oa to ptr\n  "
      po << "store i64 " + t + ".lo, ptr " + t + ".op, align 8\n  "
      po << t + ".i2 = add i64 " + t + ".i, 1\n  "
      po << "br label %ano.head." + bid + "\n"
      po << "ano.exit." + bid + ":\n  "
      po << t + " = add i64 " + t + ".c, 0"
      return po.to_s()
    # 4x-unrolled adcs quad loop (ldp/stp paired, ~3 insns/limb vs 5 for
    # the old 1x form — the delta that separated the harness loop from
    # the C kernel's unrolled ladder). Flag audit: lsr/and/sub/cbz/cbnz
    # never touch flags, so the carry threads across quads, across the
    # loop back-edge, and into the 1x remainder untouched.
    asmt = "add x15, ${1:x}, ${2:x}, lsl #3\\0Aadd x13, ${3:x}, ${4:x}, lsl #3\\0Aadd x14, ${5:x}, ${6:x}, lsl #3\\0Amov x9, ${7:x}\\0Acmn xzr, xzr\\0Alsr x8, x9, #2\\0Aand x9, x9, #3\\0Acbz x8, 2f\\0A1:\\0Aldp x10, x11, \[x13], #16\\0Aldp x16, x17, \[x14], #16\\0Aadcs x12, x10, x16\\0Aadcs x16, x11, x17\\0Astp x12, x16, \[x15], #16\\0Aldp x10, x11, \[x13], #16\\0Aldp x16, x17, \[x14], #16\\0Aadcs x12, x10, x16\\0Aadcs x16, x11, x17\\0Astp x12, x16, \[x15], #16\\0Asub x8, x8, #1\\0Acbnz x8, 1b\\0A2:\\0Acbz x9, 4f\\0A3:\\0Aldr x10, \[x13], #8\\0Aldr x11, \[x14], #8\\0Aadcs x12, x10, x11\\0Astr x12, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 3b\\0A4:\\0Acset ${0:x}, cs"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{memory},~{cc}\"(i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :ooff) + ", i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :aoff) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :boff) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_sub_no
    # offset sub_n: out[oo..]=a[ao..]-b[bo..]; flag-threaded sbcs returns borrow.
    # 4x-unrolled quad loop mirroring asm_add_no's: ldp/sbcs/stp pairs with a
    # 1x remainder; lsr/and/sub/cbz/cbnz never touch flags, so the borrow
    # (carry-clear) threads across quads, the back-edge, and the remainder.
    # `subs xzr, xzr, xzr` seeds C=1 (no borrow). Non-arm64 targets get a
    # portable i128 borrow loop with identical semantics.
    t = wire_get(inst, :temp)
    if !arm64_target
      bid = t.slice(1, t.size() - 1)
      po = StringBuffer(1024)
      po << t + ".oo3 = shl i64 " + wire_get(inst, :ooff) + ", 3\n  "
      po << t + ".ob = add i64 " + wire_get(inst, :outp) + ", " + t + ".oo3\n  "
      po << t + ".ao3 = shl i64 " + wire_get(inst, :aoff) + ", 3\n  "
      po << t + ".ab = add i64 " + wire_get(inst, :ap) + ", " + t + ".ao3\n  "
      po << t + ".bo3 = shl i64 " + wire_get(inst, :boff) + ", 3\n  "
      po << t + ".bb = add i64 " + wire_get(inst, :bp) + ", " + t + ".bo3\n  "
      po << "br label %sno.pre." + bid + "\n"
      po << "sno.pre." + bid + ":\n  "
      po << "br label %sno.head." + bid + "\n"
      po << "sno.head." + bid + ":\n  "
      po << t + ".i = phi i64 \[ 0, %sno.pre." + bid + " ], \[ " + t + ".i2, %sno.body." + bid + " ]\n  "
      po << t + ".w = phi i64 \[ 0, %sno.pre." + bid + " ], \[ " + t + ".w2, %sno.body." + bid + " ]\n  "
      po << t + ".done = icmp sge i64 " + t + ".i, " + wire_get(inst, :n) + "\n  "
      po << "br i1 " + t + ".done, label %sno.exit." + bid + ", label %sno.body." + bid + "\n"
      po << "sno.body." + bid + ":\n  "
      po << t + ".i8 = shl i64 " + t + ".i, 3\n  "
      po << t + ".aa = add i64 " + t + ".ab, " + t + ".i8\n  "
      po << t + ".apt = inttoptr i64 " + t + ".aa to ptr\n  "
      po << t + ".av = load i64, ptr " + t + ".apt, align 8\n  "
      po << t + ".ba = add i64 " + t + ".bb, " + t + ".i8\n  "
      po << t + ".bpt = inttoptr i64 " + t + ".ba to ptr\n  "
      po << t + ".bv = load i64, ptr " + t + ".bpt, align 8\n  "
      po << t + ".az = zext i64 " + t + ".av to i128\n  "
      po << t + ".bz = zext i64 " + t + ".bv to i128\n  "
      po << t + ".wz = zext i64 " + t + ".w to i128\n  "
      po << t + ".d1 = sub i128 " + t + ".az, " + t + ".bz\n  "
      po << t + ".d2 = sub i128 " + t + ".d1, " + t + ".wz\n  "
      po << t + ".lo = trunc i128 " + t + ".d2 to i64\n  "
      po << t + ".hb = lshr i128 " + t + ".d2, 127\n  "
      po << t + ".w2 = trunc i128 " + t + ".hb to i64\n  "
      po << t + ".oa = add i64 " + t + ".ob, " + t + ".i8\n  "
      po << t + ".opt = inttoptr i64 " + t + ".oa to ptr\n  "
      po << "store i64 " + t + ".lo, ptr " + t + ".opt, align 8\n  "
      po << t + ".i2 = add i64 " + t + ".i, 1\n  "
      po << "br label %sno.head." + bid + "\n"
      po << "sno.exit." + bid + ":\n  "
      po << t + " = add i64 " + t + ".w, 0"
      return po.to_s()
    asmt = "add x15, ${1:x}, ${2:x}, lsl #3\\0Aadd x13, ${3:x}, ${4:x}, lsl #3\\0Aadd x14, ${5:x}, ${6:x}, lsl #3\\0Amov x9, ${7:x}\\0Asubs xzr, xzr, xzr\\0Alsr x8, x9, #2\\0Aand x9, x9, #3\\0Acbz x8, 2f\\0A1:\\0Aldp x10, x11, \[x13], #16\\0Aldp x16, x17, \[x14], #16\\0Asbcs x12, x10, x16\\0Asbcs x16, x11, x17\\0Astp x12, x16, \[x15], #16\\0Aldp x10, x11, \[x13], #16\\0Aldp x16, x17, \[x14], #16\\0Asbcs x12, x10, x16\\0Asbcs x16, x11, x17\\0Astp x12, x16, \[x15], #16\\0Asub x8, x8, #1\\0Acbnz x8, 1b\\0A2:\\0Acbz x9, 4f\\0A3:\\0Aldr x10, \[x13], #8\\0Aldr x11, \[x14], #8\\0Asbcs x12, x10, x11\\0Astr x12, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 3b\\0A4:\\0Acset ${0:x}, cc"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{memory},~{cc}\"(i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :ooff) + ", i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :aoff) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :boff) + ", i64 " + wire_get(inst, :n) + ")"
  # Fused UNEQUAL-length add: adcs over the shorter operand, then propagate
  # the carry across the longer operand's remaining limbs — one pass, one
  # call. This exists because a source-level tail loop over those remaining
  # limbs runs on the strided view-field path and measured 2.5x against C's
  # single propagate. ${1}=out ${2}=a(longer) ${3}=alen ${4}=b(shorter)
  # ${5}=blen; returns carry-out. `sub` is flag-neutral, so the carry
  # threads from the adcs loop through the propagate loop untouched.
  when :asm_add_uneq
    t = wire_get(inst, :temp)
    if !arm64_target
      bid = t.slice(1, t.size() - 1)
      po = StringBuffer(1400)
      po << t + ".op = inttoptr i64 " + wire_get(inst, :outp) + " to ptr\n  "
      po << t + ".apx = inttoptr i64 " + wire_get(inst, :ap) + " to ptr\n  "
      po << t + ".bpx = inttoptr i64 " + wire_get(inst, :bp) + " to ptr\n  "
      po << "br label %aue.h1." + bid + "\n"
      po << "aue.h1." + bid + ":\n  "
      po << t + ".i = phi i64 \[ 0, %" + wire_get(inst, :entry_label) + " ], \[ " + t + ".i2, %aue.b1." + bid + " ]\n  "
      po << t + ".c = phi i64 \[ 0, %" + wire_get(inst, :entry_label) + " ], \[ " + t + ".c2, %aue.b1." + bid + " ]\n  "
      po << t + ".d1 = icmp sge i64 " + t + ".i, " + wire_get(inst, :nb) + "\n  "
      po << "br i1 " + t + ".d1, label %aue.h2." + bid + ", label %aue.b1." + bid + "\n"
      po << "aue.b1." + bid + ":\n  "
      po << t + ".ag = getelementptr i64, ptr " + t + ".apx, i64 " + t + ".i\n  "
      po << t + ".av = load i64, ptr " + t + ".ag, align 8\n  "
      po << t + ".bg = getelementptr i64, ptr " + t + ".bpx, i64 " + t + ".i\n  "
      po << t + ".bv = load i64, ptr " + t + ".bg, align 8\n  "
      po << t + ".az = zext i64 " + t + ".av to i128\n  "
      po << t + ".bz = zext i64 " + t + ".bv to i128\n  "
      po << t + ".cz = zext i64 " + t + ".c to i128\n  "
      po << t + ".s1 = add i128 " + t + ".az, " + t + ".bz\n  "
      po << t + ".s2 = add i128 " + t + ".s1, " + t + ".cz\n  "
      po << t + ".lo = trunc i128 " + t + ".s2 to i64\n  "
      po << t + ".hi = lshr i128 " + t + ".s2, 64\n  "
      po << t + ".c2 = trunc i128 " + t + ".hi to i64\n  "
      po << t + ".og = getelementptr i64, ptr " + t + ".op, i64 " + t + ".i\n  "
      po << "store i64 " + t + ".lo, ptr " + t + ".og, align 8\n  "
      po << t + ".i2 = add i64 " + t + ".i, 1\n  "
      po << "br label %aue.h1." + bid + "\n"
      po << "aue.h2." + bid + ":\n  "
      po << t + ".j = phi i64 \[ " + t + ".i, %aue.h1." + bid + " ], \[ " + t + ".j2, %aue.b2." + bid + " ]\n  "
      po << t + ".tc = phi i64 \[ " + t + ".c, %aue.h1." + bid + " ], \[ " + t + ".tc2, %aue.b2." + bid + " ]\n  "
      po << t + ".d2 = icmp sge i64 " + t + ".j, " + wire_get(inst, :na) + "\n  "
      po << "br i1 " + t + ".d2, label %aue.x." + bid + ", label %aue.b2." + bid + "\n"
      po << "aue.b2." + bid + ":\n  "
      po << t + ".tag = getelementptr i64, ptr " + t + ".apx, i64 " + t + ".j\n  "
      po << t + ".tav = load i64, ptr " + t + ".tag, align 8\n  "
      po << t + ".ts = add i64 " + t + ".tav, " + t + ".tc\n  "
      po << t + ".tov = icmp ult i64 " + t + ".ts, " + t + ".tav\n  "
      po << t + ".tc2 = zext i1 " + t + ".tov to i64\n  "
      po << t + ".tog = getelementptr i64, ptr " + t + ".op, i64 " + t + ".j\n  "
      po << "store i64 " + t + ".ts, ptr " + t + ".tog, align 8\n  "
      po << t + ".j2 = add i64 " + t + ".j, 1\n  "
      po << "br label %aue.h2." + bid + "\n"
      po << "aue.x." + bid + ":\n  "
      po << t + " = add i64 " + t + ".tc, 0"
      return po.to_s()
    asmt = "mov x15, ${1:x}\\0Amov x13, ${2:x}\\0Amov x14, ${4:x}\\0Amov x9, ${5:x}\\0Amov x8, ${3:x}\\0Asub x8, x8, x9\\0Acmn xzr, xzr\\0Acbz x9, 2f\\0A1:\\0Aldr x10, \[x13], #8\\0Aldr x11, \[x14], #8\\0Aadcs x12, x10, x11\\0Astr x12, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0A2:\\0Acbz x8, 3f\\0A4:\\0Aldr x10, \[x13], #8\\0Aadcs x12, x10, xzr\\0Astr x12, \[x15], #8\\0Asub x8, x8, #1\\0Acbz x8, 3f\\0Ab.cc 5f\\0Ab 4b\\0A5:\\0Acmp x8, #4\\0Ab.lt 6f\\0Aldp x10, x11, \[x13], #16\\0Aldp x16, x17, \[x13], #16\\0Astp x10, x11, \[x15], #16\\0Astp x16, x17, \[x15], #16\\0Asub x8, x8, #4\\0Acbnz x8, 5b\\0Ab 7f\\0A6:\\0Aldr x10, \[x13], #8\\0Astr x10, \[x15], #8\\0Asub x8, x8, #1\\0Acbnz x8, 6b\\0A7:\\0Amov ${0:x}, #0\\0Ab 8f\\0A3:\\0Acset ${0:x}, cs\\0A8:"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{memory},~{cc}\"(i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :na) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :nb) + ")"

  # Fused UNEQUAL-length subtract: sbcs over the shorter operand, then
  # propagate the borrow across the longer operand's remaining limbs.
  # `subs xzr, xzr, xzr` seeds C=1 (no borrow).
  when :asm_sub_uneq
    t = wire_get(inst, :temp)
    if !arm64_target
      bid = t.slice(1, t.size() - 1)
      po = StringBuffer(1400)
      po << t + ".op = inttoptr i64 " + wire_get(inst, :outp) + " to ptr\n  "
      po << t + ".apx = inttoptr i64 " + wire_get(inst, :ap) + " to ptr\n  "
      po << t + ".bpx = inttoptr i64 " + wire_get(inst, :bp) + " to ptr\n  "
      po << "br label %sue.h1." + bid + "\n"
      po << "sue.h1." + bid + ":\n  "
      po << t + ".i = phi i64 \[ 0, %" + wire_get(inst, :entry_label) + " ], \[ " + t + ".i2, %sue.b1." + bid + " ]\n  "
      po << t + ".w = phi i64 \[ 0, %" + wire_get(inst, :entry_label) + " ], \[ " + t + ".w2, %sue.b1." + bid + " ]\n  "
      po << t + ".d1 = icmp sge i64 " + t + ".i, " + wire_get(inst, :nb) + "\n  "
      po << "br i1 " + t + ".d1, label %sue.h2." + bid + ", label %sue.b1." + bid + "\n"
      po << "sue.b1." + bid + ":\n  "
      po << t + ".ag = getelementptr i64, ptr " + t + ".apx, i64 " + t + ".i\n  "
      po << t + ".av = load i64, ptr " + t + ".ag, align 8\n  "
      po << t + ".bg = getelementptr i64, ptr " + t + ".bpx, i64 " + t + ".i\n  "
      po << t + ".bv = load i64, ptr " + t + ".bg, align 8\n  "
      po << t + ".az = zext i64 " + t + ".av to i128\n  "
      po << t + ".bz = zext i64 " + t + ".bv to i128\n  "
      po << t + ".wz = zext i64 " + t + ".w to i128\n  "
      po << t + ".s1 = sub i128 " + t + ".az, " + t + ".bz\n  "
      po << t + ".s2 = sub i128 " + t + ".s1, " + t + ".wz\n  "
      po << t + ".lo = trunc i128 " + t + ".s2 to i64\n  "
      po << t + ".hb = lshr i128 " + t + ".s2, 127\n  "
      po << t + ".w2 = trunc i128 " + t + ".hb to i64\n  "
      po << t + ".og = getelementptr i64, ptr " + t + ".op, i64 " + t + ".i\n  "
      po << "store i64 " + t + ".lo, ptr " + t + ".og, align 8\n  "
      po << t + ".i2 = add i64 " + t + ".i, 1\n  "
      po << "br label %sue.h1." + bid + "\n"
      po << "sue.h2." + bid + ":\n  "
      po << t + ".j = phi i64 \[ " + t + ".i, %sue.h1." + bid + " ], \[ " + t + ".j2, %sue.b2." + bid + " ]\n  "
      po << t + ".tw = phi i64 \[ " + t + ".w, %sue.h1." + bid + " ], \[ " + t + ".tw2, %sue.b2." + bid + " ]\n  "
      po << t + ".d2 = icmp sge i64 " + t + ".j, " + wire_get(inst, :na) + "\n  "
      po << "br i1 " + t + ".d2, label %sue.x." + bid + ", label %sue.b2." + bid + "\n"
      po << "sue.b2." + bid + ":\n  "
      po << t + ".tag = getelementptr i64, ptr " + t + ".apx, i64 " + t + ".j\n  "
      po << t + ".tav = load i64, ptr " + t + ".tag, align 8\n  "
      po << t + ".ts = sub i64 " + t + ".tav, " + t + ".tw\n  "
      po << t + ".tov = icmp ult i64 " + t + ".tav, " + t + ".tw\n  "
      po << t + ".tw2 = zext i1 " + t + ".tov to i64\n  "
      po << t + ".tog = getelementptr i64, ptr " + t + ".op, i64 " + t + ".j\n  "
      po << "store i64 " + t + ".ts, ptr " + t + ".tog, align 8\n  "
      po << t + ".j2 = add i64 " + t + ".j, 1\n  "
      po << "br label %sue.h2." + bid + "\n"
      po << "sue.x." + bid + ":\n  "
      po << t + " = add i64 " + t + ".tw, 0"
      return po.to_s()
    asmt = "mov x15, ${1:x}\\0Amov x13, ${2:x}\\0Amov x14, ${4:x}\\0Amov x9, ${5:x}\\0Amov x8, ${3:x}\\0Asub x8, x8, x9\\0Asubs xzr, xzr, xzr\\0Acbz x9, 2f\\0A1:\\0Aldr x10, \[x13], #8\\0Aldr x11, \[x14], #8\\0Asbcs x12, x10, x11\\0Astr x12, \[x15], #8\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0A2:\\0Acbz x8, 3f\\0A4:\\0Aldr x10, \[x13], #8\\0Asbcs x12, x10, xzr\\0Astr x12, \[x15], #8\\0Asub x8, x8, #1\\0Acbz x8, 3f\\0Ab.cs 5f\\0Ab 4b\\0A5:\\0Acmp x8, #4\\0Ab.lt 6f\\0Aldp x10, x11, \[x13], #16\\0Aldp x16, x17, \[x13], #16\\0Astp x10, x11, \[x15], #16\\0Astp x16, x17, \[x15], #16\\0Asub x8, x8, #4\\0Acbnz x8, 5b\\0Ab 7f\\0A6:\\0Aldr x10, \[x13], #8\\0Astr x10, \[x15], #8\\0Asub x8, x8, #1\\0Acbnz x8, 6b\\0A7:\\0Amov ${0:x}, #0\\0Ab 8f\\0A3:\\0Acset ${0:x}, cc\\0A8:"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{memory},~{cc}\"(i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :na) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :nb) + ")"

  when :asm_addmul1
    # offset addmul_1: out[oo..] += a[ao..]*bsc; returns carry.
    # x14=out ptr, x13=a ptr, x3=bsc, x9=n, x15=carry.
    t = wire_get(inst, :temp)
    if !arm64_target
      bid = t.slice(1, t.size() - 1)
      po = StringBuffer(1200)
      po << t + ".oo3 = shl i64 " + wire_get(inst, :ooff) + ", 3\n  "
      po << t + ".ob = add i64 " + wire_get(inst, :outp) + ", " + t + ".oo3\n  "
      po << t + ".ao3 = shl i64 " + wire_get(inst, :aoff) + ", 3\n  "
      po << t + ".ab = add i64 " + wire_get(inst, :ap) + ", " + t + ".ao3\n  "
      po << t + ".op = inttoptr i64 " + t + ".ob to ptr\n  "
      po << t + ".apx = inttoptr i64 " + t + ".ab to ptr\n  "
      po << "br label %am1.pre." + bid + "\n"
      po << "am1.pre." + bid + ":\n  "
      po << "br label %am1.head." + bid + "\n"
      po << "am1.head." + bid + ":\n  "
      po << t + ".i = phi i64 \[ 0, %am1.pre." + bid + " ], \[ " + t + ".i2, %am1.body." + bid + " ]\n  "
      po << t + ".c = phi i64 \[ 0, %am1.pre." + bid + " ], \[ " + t + ".c2, %am1.body." + bid + " ]\n  "
      po << t + ".done = icmp sge i64 " + t + ".i, " + wire_get(inst, :n) + "\n  "
      po << "br i1 " + t + ".done, label %am1.exit." + bid + ", label %am1.body." + bid + "\n"
      po << "am1.body." + bid + ":\n  "
      po << t + ".ag = getelementptr i64, ptr " + t + ".apx, i64 " + t + ".i\n  "
      po << t + ".av = load i64, ptr " + t + ".ag, align 8\n  "
      po << t + ".og = getelementptr i64, ptr " + t + ".op, i64 " + t + ".i\n  "
      po << t + ".ov = load i64, ptr " + t + ".og, align 8\n  "
      po << t + ".az = zext i64 " + t + ".av to i128\n  "
      po << t + ".bz = zext i64 " + wire_get(inst, :bsc) + " to i128\n  "
      po << t + ".oz = zext i64 " + t + ".ov to i128\n  "
      po << t + ".cz = zext i64 " + t + ".c to i128\n  "
      po << t + ".prod = mul i128 " + t + ".az, " + t + ".bz\n  "
      po << t + ".sum1 = add i128 " + t + ".prod, " + t + ".oz\n  "
      po << t + ".sum2 = add i128 " + t + ".sum1, " + t + ".cz\n  "
      po << t + ".lo = trunc i128 " + t + ".sum2 to i64\n  "
      po << t + ".hi = lshr i128 " + t + ".sum2, 64\n  "
      po << t + ".c2 = trunc i128 " + t + ".hi to i64\n  "
      po << "store i64 " + t + ".lo, ptr " + t + ".og, align 8\n  "
      po << t + ".i2 = add i64 " + t + ".i, 1\n  "
      po << "br label %am1.head." + bid + "\n"
      po << "am1.exit." + bid + ":\n  "
      po << t + " = add i64 " + t + ".c, 0"
      return po.to_s()
    asmt = "add x14, ${1:x}, ${2:x}, lsl #3\\0Aadd x13, ${3:x}, ${4:x}, lsl #3\\0Amov x3, ${5:x}\\0Amov x9, ${6:x}\\0Amov x15, #0\\0A1:\\0Aldr x4, \[x13], #8\\0Amul x8, x4, x3\\0Aumulh x12, x4, x3\\0Aadds x8, x8, x15\\0Aadc x12, x12, xzr\\0Aldr x5, \[x14]\\0Aadds x8, x5, x8\\0Aadc x15, x12, xzr\\0Astr x8, \[x14], #8\\0Asub x9, x9, #1\\0Acbnz x9, 1b\\0Amov ${0:x}, x15"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,r,~{x3},~{x4},~{x5},~{x8},~{x9},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}\"(i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :ooff) + ", i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :aoff) + ", i64 " + wire_get(inst, :bsc) + ", i64 " + wire_get(inst, :n) + ")"
  when :asm_mulbase
    # Schoolbook multiplication as ONE asm block: out[oo..oo+na+nb) = a[ao..]*b[bo..].
    # row 0 = mul_1, rows 1..na-1 = addmul_1. One call/basecase (no per-row spill).
    # x16=out base, x17=a ptr, x7=b base; inner: x2=b ptr,x4=out ptr,x5=nb,x15=carry.
    t = wire_get(inst, :temp)
    if !arm64_target
      bid = t.slice(1, t.size() - 1)
      po = StringBuffer(2400)
      po << t + ".oo3 = shl i64 " + wire_get(inst, :ooff) + ", 3\n  "
      po << t + ".ob = add i64 " + wire_get(inst, :outp) + ", " + t + ".oo3\n  "
      po << t + ".ao3 = shl i64 " + wire_get(inst, :aoff) + ", 3\n  "
      po << t + ".ab = add i64 " + wire_get(inst, :ap) + ", " + t + ".ao3\n  "
      po << t + ".bo3 = shl i64 " + wire_get(inst, :boff) + ", 3\n  "
      po << t + ".bb = add i64 " + wire_get(inst, :bp) + ", " + t + ".bo3\n  "
      po << t + ".op = inttoptr i64 " + t + ".ob to ptr\n  "
      po << t + ".apx = inttoptr i64 " + t + ".ab to ptr\n  "
      po << t + ".bpx = inttoptr i64 " + t + ".bb to ptr\n  "
      po << t + ".total = add i64 " + wire_get(inst, :na) + ", " + wire_get(inst, :nb) + "\n  "
      po << "br label %mb.zero.pre." + bid + "\n"
      po << "mb.zero.pre." + bid + ":\n  "
      po << "br label %mb.zero.head." + bid + "\n"
      po << "mb.zero.head." + bid + ":\n  "
      po << t + ".zi = phi i64 \[ 0, %mb.zero.pre." + bid + " ], \[ " + t + ".zi2, %mb.zero.body." + bid + " ]\n  "
      po << t + ".zdone = icmp sge i64 " + t + ".zi, " + t + ".total\n  "
      po << "br i1 " + t + ".zdone, label %mb.outer.pre." + bid + ", label %mb.zero.body." + bid + "\n"
      po << "mb.zero.body." + bid + ":\n  "
      po << t + ".zg = getelementptr i64, ptr " + t + ".op, i64 " + t + ".zi\n  "
      po << "store i64 0, ptr " + t + ".zg, align 8\n  "
      po << t + ".zi2 = add i64 " + t + ".zi, 1\n  "
      po << "br label %mb.zero.head." + bid + "\n"
      po << "mb.outer.pre." + bid + ":\n  "
      po << "br label %mb.outer.head." + bid + "\n"
      po << "mb.outer.head." + bid + ":\n  "
      po << t + ".i = phi i64 \[ 0, %mb.outer.pre." + bid + " ], \[ " + t + ".i2, %mb.row.done." + bid + " ]\n  "
      po << t + ".odone = icmp sge i64 " + t + ".i, " + wire_get(inst, :na) + "\n  "
      po << "br i1 " + t + ".odone, label %mb.exit." + bid + ", label %mb.row.pre." + bid + "\n"
      po << "mb.row.pre." + bid + ":\n  "
      po << t + ".ag = getelementptr i64, ptr " + t + ".apx, i64 " + t + ".i\n  "
      po << t + ".av = load i64, ptr " + t + ".ag, align 8\n  "
      po << t + ".az = zext i64 " + t + ".av to i128\n  "
      po << "br label %mb.inner.head." + bid + "\n"
      po << "mb.inner.head." + bid + ":\n  "
      po << t + ".j = phi i64 \[ 0, %mb.row.pre." + bid + " ], \[ " + t + ".j2, %mb.inner.body." + bid + " ]\n  "
      po << t + ".c = phi i64 \[ 0, %mb.row.pre." + bid + " ], \[ " + t + ".c2, %mb.inner.body." + bid + " ]\n  "
      po << t + ".idone = icmp sge i64 " + t + ".j, " + wire_get(inst, :nb) + "\n  "
      po << "br i1 " + t + ".idone, label %mb.row.done." + bid + ", label %mb.inner.body." + bid + "\n"
      po << "mb.inner.body." + bid + ":\n  "
      po << t + ".bg = getelementptr i64, ptr " + t + ".bpx, i64 " + t + ".j\n  "
      po << t + ".bv = load i64, ptr " + t + ".bg, align 8\n  "
      po << t + ".oi = add i64 " + t + ".i, " + t + ".j\n  "
      po << t + ".og = getelementptr i64, ptr " + t + ".op, i64 " + t + ".oi\n  "
      po << t + ".ov = load i64, ptr " + t + ".og, align 8\n  "
      po << t + ".bz = zext i64 " + t + ".bv to i128\n  "
      po << t + ".oz = zext i64 " + t + ".ov to i128\n  "
      po << t + ".cz = zext i64 " + t + ".c to i128\n  "
      po << t + ".prod = mul i128 " + t + ".az, " + t + ".bz\n  "
      po << t + ".sum1 = add i128 " + t + ".prod, " + t + ".oz\n  "
      po << t + ".sum2 = add i128 " + t + ".sum1, " + t + ".cz\n  "
      po << t + ".lo = trunc i128 " + t + ".sum2 to i64\n  "
      po << t + ".hi = lshr i128 " + t + ".sum2, 64\n  "
      po << t + ".c2 = trunc i128 " + t + ".hi to i64\n  "
      po << "store i64 " + t + ".lo, ptr " + t + ".og, align 8\n  "
      po << t + ".j2 = add i64 " + t + ".j, 1\n  "
      po << "br label %mb.inner.head." + bid + "\n"
      po << "mb.row.done." + bid + ":\n  "
      po << t + ".ci = add i64 " + t + ".i, " + wire_get(inst, :nb) + "\n  "
      po << t + ".cg = getelementptr i64, ptr " + t + ".op, i64 " + t + ".ci\n  "
      po << "store i64 " + t + ".c, ptr " + t + ".cg, align 8\n  "
      po << t + ".i2 = add i64 " + t + ".i, 1\n  "
      po << "br label %mb.outer.head." + bid + "\n"
      po << "mb.exit." + bid + ":\n  "
      po << t + " = add i64 0, 0"
      return po.to_s()
    asmt = "add x16, ${1:x}, ${2:x}, lsl #3\\0Aadd x17, ${3:x}, ${4:x}, lsl #3\\0Aadd x7, ${5:x}, ${6:x}, lsl #3\\0Aldr x6, \[x17], #8\\0Amov x2, x7\\0Amov x4, x16\\0Amov x5, ${8:x}\\0Amov x15, #0\\0A1:\\0Aldr x10, \[x2], #8\\0Amul x8, x10, x6\\0Aumulh x12, x10, x6\\0Aadds x8, x8, x15\\0Aadc x15, x12, xzr\\0Astr x8, \[x4], #8\\0Asubs x5, x5, #1\\0Abne 1b\\0Astr x15, \[x4]\\0Asubs x3, ${7:x}, #1\\0Amov x14, x16\\0A2:\\0Acbz x3, 3f\\0Aadd x14, x14, #8\\0Aldr x6, \[x17], #8\\0Amov x2, x7\\0Amov x4, x14\\0Amov x5, ${8:x}\\0Amov x15, #0\\0A4:\\0Aldr x10, \[x2], #8\\0Amul x8, x10, x6\\0Aumulh x12, x10, x6\\0Aadds x8, x8, x15\\0Aadc x12, x12, xzr\\0Aldr x9, \[x4]\\0Aadds x8, x9, x8\\0Aadc x15, x12, xzr\\0Astr x8, \[x4], #8\\0Asubs x5, x5, #1\\0Abne 4b\\0Astr x15, \[x4]\\0Asub x3, x3, #1\\0Ab 2b\\0A3:\\0Amov ${0:x}, #0"
    t + " = call i64 asm sideeffect \"" + asmt + "\", \"=r,r,r,r,r,r,r,r,r,~{x2},~{x3},~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x12},~{x14},~{x15},~{x16},~{x17},~{memory},~{cc}\"(i64 " + wire_get(inst, :outp) + ", i64 " + wire_get(inst, :ooff) + ", i64 " + wire_get(inst, :ap) + ", i64 " + wire_get(inst, :aoff) + ", i64 " + wire_get(inst, :bp) + ", i64 " + wire_get(inst, :boff) + ", i64 " + wire_get(inst, :na) + ", i64 " + wire_get(inst, :nb) + ")"
  when :sdiv_i128
    wire_get(inst, :temp) + " = sdiv i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :udiv_i128
    wire_get(inst, :temp) + " = udiv i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :srem_i128
    wire_get(inst, :temp) + " = srem i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :urem_i128
    wire_get(inst, :temp) + " = urem i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)

  # Checked i48 arithmetic with overflow branch to bigint
  when :add_i48_checked, :sub_i48_checked
    intrinsic = "llvm.sadd.with.overflow.i64"
    if op == :sub_i48_checked
      intrinsic = "llvm.ssub.with.overflow.i64"
    bid = wire_get(inst, :block_id).to_s()
    t = wire_get(inst, :temp)
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
    out << pair + " = call {i64, i1} @" + intrinsic + "(i64 " + wire_get(inst, :lhs) + ", i64 " + wire_get(inst, :rhs) + ")\n  "
    out << raw + " = extractvalue {i64, i1} " + pair + ", 0\n  "
    out << i64ovf + " = extractvalue {i64, i1} " + pair + ", 1\n  "
    out << over + " = icmp sgt i64 " + raw + ", 140737488355327\n  "
    out << under + " = icmp slt i64 " + raw + ", -140737488355328\n  "
    out << rovf + " = or i1 " + over + ", " + under + "\n  "
    out << ovf + " = or i1 " + i64ovf + ", " + rovf + "\n  "
    out << "br i1 " + ovf + ", label %ovf.slow." + bid + ", label %ovf.fast." + bid + ", !prof !31412\n"
    out << "ovf.fast." + bid + ":\n  "
    out << masked + " = and i64 " + raw + ", 281474976710655\n  "
    out << boxed + " = or i64 " + masked + ", -1688849860263936\n  "
    out << "br label %ovf.merge." + bid + "\n"
    out << "ovf.slow." + bid + ":\n  "
    out << slow + " = call i64 @" + wire_get(inst, :rt_fallback) + "(i64 " + wire_get(inst, :lhs_boxed) + ", i64 " + wire_get(inst, :rhs_boxed) + ")\n  "
    out << "br label %ovf.merge." + bid + "\n"
    out << "ovf.merge." + bid + ":\n  "
    out << t + " = phi i64 \[" + boxed + ", %ovf.fast." + bid + "], \[" + slow + ", %ovf.slow." + bid + "]"
    out.to_s()

  when :mul_i48_checked
    bid = wire_get(inst, :block_id).to_s()
    t = wire_get(inst, :temp)
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
    out << pair + " = call {i64, i1} @llvm.smul.with.overflow.i64(i64 " + wire_get(inst, :lhs) + ", i64 " + wire_get(inst, :rhs) + ")\n  "
    out << raw + " = extractvalue {i64, i1} " + pair + ", 0\n  "
    out << i64ovf + " = extractvalue {i64, i1} " + pair + ", 1\n  "
    out << over + " = icmp sgt i64 " + raw + ", 140737488355327\n  "
    out << under + " = icmp slt i64 " + raw + ", -140737488355328\n  "
    out << rovf + " = or i1 " + over + ", " + under + "\n  "
    out << ovf + " = or i1 " + i64ovf + ", " + rovf + "\n  "
    out << "br i1 " + ovf + ", label %ovf.slow." + bid + ", label %ovf.fast." + bid + ", !prof !31412\n"
    out << "ovf.fast." + bid + ":\n  "
    out << masked + " = and i64 " + raw + ", 281474976710655\n  "
    out << boxed + " = or i64 " + masked + ", -1688849860263936\n  "
    out << "br label %ovf.merge." + bid + "\n"
    out << "ovf.slow." + bid + ":\n  "
    out << slow + " = call i64 @" + wire_get(inst, :rt_fallback) + "(i64 " + wire_get(inst, :lhs_boxed) + ", i64 " + wire_get(inst, :rhs_boxed) + ")\n  "
    out << "br label %ovf.merge." + bid + "\n"
    out << "ovf.merge." + bid + ":\n  "
    out << t + " = phi i64 \[" + boxed + ", %ovf.fast." + bid + "], \[" + slow + ", %ovf.slow." + bid + "]"
    out.to_s()

  # Guarded i48 arithmetic: inline fast path for boxed ints, runtime fallback otherwise.
  when :add_i48_guarded, :sub_i48_guarded, :mul_i48_guarded
    render_guarded_i48(inst)

  # Bitwise
  when :and_i64
    wire_get(inst, :temp) + " = and i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :or_i64
    wire_get(inst, :temp) + " = or i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :xor_i64
    wire_get(inst, :temp) + " = xor i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :shl_i64
    wire_get(inst, :temp) + " = shl i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :ashr_i64
    wire_get(inst, :temp) + " = ashr i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :lshr_i64
    wire_get(inst, :temp) + " = lshr i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :and_i128
    wire_get(inst, :temp) + " = and i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :or_i128
    wire_get(inst, :temp) + " = or i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :xor_i128
    wire_get(inst, :temp) + " = xor i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :shl_i128
    wire_get(inst, :temp) + " = shl i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :ashr_i128
    wire_get(inst, :temp) + " = ashr i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :lshr_i128
    if wire_get(inst, :lhs) != nil
      wire_get(inst, :temp) + " = lshr i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
    elsif wire_get(inst, :shift) != nil
      wire_get(inst, :temp) + " = lshr i128 " + wire_get(inst, :value) + ", " + wire_get(inst, :shift).to_s()
    else
      "; UNKNOWN WIRE OP: " + op.to_s()

  # Comparison
  when :icmp_i64
    wire_get(inst, :temp) + " = icmp " + wire_get(inst, :pred) + " i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :truthy_inline
    wire_get(inst, :temp) + " = icmp ugt i64 " + wire_get(inst, :value) + ", 1"
  when :icmp_ne_zero
    wire_get(inst, :temp) + " = icmp ne i64 " + wire_get(inst, :value) + ", 0"
  when :icmp_ne_i64
    wire_get(inst, :temp) + " = icmp ne i64 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :icmp_i128
    wire_get(inst, :temp) + " = icmp " + wire_get(inst, :pred) + " i128 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)

  # Boolean
  when :and_i1
    wire_get(inst, :temp) + " = and i1 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :or_i1
    wire_get(inst, :temp) + " = or i1 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :not_i1
    wire_get(inst, :temp) + " = xor i1 " + wire_get(inst, :value) + ", true"

  # Cast
  when :zext_i1_i64
    wire_get(inst, :temp) + " = zext i1 " + wire_get(inst, :value) + " to i64"
  when :trunc_i64_i32
    wire_get(inst, :temp) + " = trunc i64 " + wire_get(inst, :value) + " to i32"
  when :sext_i64_i128
    wire_get(inst, :temp) + " = sext i64 " + wire_get(inst, :value) + " to i128"
  when :zext_i32_i64
    wire_get(inst, :temp) + " = zext i32 " + wire_get(inst, :value) + " to i64"
  when :select_i64
    wire_get(inst, :temp) + " = select i1 " + wire_get(inst, :cond) + ", i64 " + wire_get(inst, :then_val) + ", i64 " + wire_get(inst, :else_val)

  # NaN-boxing
  when :nanbox_int
    raw_str = wire_get(inst, :raw).to_s()
    ch = raw_str.slice(0, 1)
    if ch != nil && (ch == "-" || (ch >= "0" && ch <= "9"))
      wval = (raw_str.to_i() & 281474976710655) | -1688849860263936
      lit = llvm_wvalue_literal(wval)
      wire_get(inst, :temp_masked) + " = or i64 0, " + lit + "\n  " + wire_get(inst, :temp) + " = or i64 0, " + lit
    else
      wire_get(inst, :temp_masked) + " = and i64 " + raw_str + ", " + machine_i64_text(w_payload_mask) + "\n  " + wire_get(inst, :temp) + " = or i64 " + wire_get(inst, :temp_masked) + ", " + machine_i64_text(w_tag_int)
  when :nanunbox_int
    wire_get(inst, :temp_shl) + " = shl i64 " + wire_get(inst, :boxed) + ", 16\n  " + wire_get(inst, :temp) + " = ashr i64 " + wire_get(inst, :temp_shl) + ", 16"
  when :nanbox_bool
    wire_get(inst, :temp) + " = select i1 " + wire_get(inst, :value) + ", i64 " + w_true.to_s() + ", i64 " + w_false.to_s()
  when :nanunbox_float
    wire_get(inst, :temp_bits) + " = sub i64 " + wire_get(inst, :boxed) + ", " + machine_i64_text(w_double_bias) + "\n  " + wire_get(inst, :temp) + " = bitcast i64 " + wire_get(inst, :temp_bits) + " to double"
  when :nanbox_float
    wire_get(inst, :temp_bits) + " = bitcast double " + wire_get(inst, :raw) + " to i64\n  " + wire_get(inst, :temp) + " = add i64 " + wire_get(inst, :temp_bits) + ", " + machine_i64_text(w_double_bias)

  # Raw float value plumbing
  when :fpext_f32_f64
    wire_get(inst, :temp) + " = fpext float " + wire_get(inst, :value) + " to double"
  when :fptrunc_f64_f32
    wire_get(inst, :temp) + " = fptrunc double " + wire_get(inst, :value) + " to float"
  when :fptosi_f64_i64
    wire_get(inst, :temp) + " = fptosi double " + wire_get(inst, :value) + " to i64"
  when :fptoui_f64_i64
    wire_get(inst, :temp) + " = fptoui double " + wire_get(inst, :value) + " to i64"
  when :fptosi_f64_i128
    wire_get(inst, :temp) + " = fptosi double " + wire_get(inst, :value) + " to i128"
  when :fptoui_f64_i128
    wire_get(inst, :temp) + " = fptoui double " + wire_get(inst, :value) + " to i128"
  when :bitcast_i64_f64
    wire_get(inst, :temp) + " = bitcast i64 " + wire_get(inst, :value) + " to double"
  when :bitcast_f64_i64
    wire_get(inst, :temp) + " = bitcast double " + wire_get(inst, :value) + " to i64"
  when :bitcast_i32_f32
    wire_get(inst, :temp) + " = bitcast i32 " + wire_get(inst, :value) + " to float"
  when :bitcast_f32_i32
    wire_get(inst, :temp) + " = bitcast float " + wire_get(inst, :value) + " to i32"

  # IEEE-half (f16) element conversion. Storage is i16; arithmetic is f32.
  # fptrunc/fpext lower to single fcvt instructions on AArch64.
  when :fptrunc_f32_f16
    wire_get(inst, :temp) + " = fptrunc float " + wire_get(inst, :value) + " to half"
  when :fpext_f16_f32
    wire_get(inst, :temp) + " = fpext half " + wire_get(inst, :value) + " to float"
  when :bitcast_f16_i16
    wire_get(inst, :temp) + " = bitcast half " + wire_get(inst, :value) + " to i16"
  when :bitcast_i16_f16
    wire_get(inst, :temp) + " = bitcast i16 " + wire_get(inst, :value) + " to half"
  when :zext_i16_i64
    wire_get(inst, :temp) + " = zext i16 " + wire_get(inst, :value) + " to i64"
  when :trunc_i64_i16
    wire_get(inst, :temp) + " = trunc i64 " + wire_get(inst, :value) + " to i16"

  # Float arithmetic — wire_get(inst, :fp_flags) overrides the function-level default for
  # @fastmath / @strictmath block scopes; nil means use the function default.
  when :fadd_f64
    f = wire_get(inst, :fp_flags)
    f = fp_flags if f == nil
    wire_get(inst, :temp) + " = fadd " + f + "double " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :fsub_f64
    f = wire_get(inst, :fp_flags)
    f = fp_flags if f == nil
    wire_get(inst, :temp) + " = fsub " + f + "double " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :fmul_f64
    f = wire_get(inst, :fp_flags)
    f = fp_flags if f == nil
    wire_get(inst, :temp) + " = fmul " + f + "double " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :fdiv_f64
    f = wire_get(inst, :fp_flags)
    f = fp_flags if f == nil
    wire_get(inst, :temp) + " = fdiv " + f + "double " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)
  when :frem_f64
    wire_get(inst, :temp) + " = frem double " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)

  # FMA peephole: emitted by lowering/ops.w for a*b+c / a*b-c in precise mode.
  # This is the llvm.fmuladd intrinsic: "fuse if target supports it" — always
  # maps to a single hardware FMA on targets that have one (ARM, x86 AVX2+).
  # Operands ride on :lhs (a) / :rhs (b) / :value (c) — the three field names
  # already known to apply_subst (mem2reg) and content_hash. Using novel keys
  # would make the mul/add operands invisible to those operand-walkers, so a
  # promoted-away load would leave the fmuladd referencing a deleted temp.
  when :fmuladd_f64
    wire_get(inst, :temp) + " = call double @llvm.fmuladd.f64(double " + wire_get(inst, :lhs) + ", double " + wire_get(inst, :rhs) + ", double " + wire_get(inst, :value) + ")"
  # Explicit `fma(a,b,c)` — llvm.fma.f64 is ALWAYS a true fused multiply-add
  # (single rounding), unlike fmuladd's "contract if profitable". Same
  # lhs/rhs/value operand fields for mem2reg/content-hash safety.
  when :fma_f64
    wire_get(inst, :temp) + " = call double @llvm.fma.f64(double " + wire_get(inst, :lhs) + ", double " + wire_get(inst, :rhs) + ", double " + wire_get(inst, :value) + ")"
  # Raw libm call — Math.* fast path on unboxed operands (lowering/
  # method_call.w). Unary rides on :value, binary (pow/atan2) on :lhs/:rhs —
  # all three field names are walked by apply_subst and content_hash, so
  # mem2reg promotion of the operand loads stays correct (see :fmuladd_f64).
  when :call_libm_f64
    if wire_get(inst, :value) != nil
      wire_get(inst, :temp) + " = call double @" + wire_get(inst, :name) + "(double " + wire_get(inst, :value) + ")"
    else
      wire_get(inst, :temp) + " = call double @" + wire_get(inst, :name) + "(double " + wire_get(inst, :lhs) + ", double " + wire_get(inst, :rhs) + ")"

  # Numeric->raw-double coercion of a boxed WValue (ensure_raw_f64 fallback):
  # takes an i64 WValue (boxed double / Decimal / Int), returns a raw double.
  # Routed through the alwaysinline helper so the boxed-double case (a :f64
  # param arriving as a WValue, nbody's `dt`) folds to sub+bitcast inline
  # instead of an out-of-line w_num_to_f64 call per use site.
  when :call_num_to_f64
    wire_get(inst, :temp) + " = call double @__w_num_to_f64_fast(i64 " + wire_get(inst, :value) + ")"

  # Fused-elementwise loop ops (lowering/ops.w try_fuse_elementwise). The
  # header decode is hoisted out of the fused loop deliberately: the loop
  # body the fuser emits contains no push/clear/realloc, so slots/start are
  # invariant for its duration — unlike typed_array_get_inline sites, which
  # must re-read them per access. Operands ride on :value/:ptr/:index only
  # (fields apply_subst and content_hash already walk).
  when :ta_f64_elems_ptr
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    parts = StringBuffer(420)
    parts << t + ".hdr = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".slp = getelementptr i8, ptr " + t + ".hp, i64 16\n  "
    parts << t + ".slots = load ptr, ptr " + t + ".slp, align 8" + tbaa_header_suffix() + "\n  "
    parts << t + ".stp = getelementptr i8, ptr " + t + ".hp, i64 4\n  "
    parts << t + ".st32 = load i32, ptr " + t + ".stp, align 4" + tbaa_header_suffix() + "\n  "
    parts << t + ".st = sext i32 " + t + ".st32 to i64\n  "
    parts << t + " = getelementptr double, ptr " + t + ".slots, i64 " + t + ".st"
    parts.to_s()
  when :ta_size_raw
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    parts = StringBuffer(240)
    parts << t + ".hdr = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".szp = getelementptr i8, ptr " + t + ".hp, i64 8\n  "
    parts << t + ".sz32 = load i32, ptr " + t + ".szp, align 4" + tbaa_header_suffix() + "\n  "
    parts << t + " = sext i32 " + t + ".sz32 to i64"
    parts.to_s()
  # `.size` for a statically-:array receiver. Unlike :ta_size_raw (typed
  # arrays — always real WArrays), a :array-typed var can hold a BODY-REF at
  # runtime: an AST child-list packed box (tag 0xFFFE, subtype 6) that quacks
  # like an array — e.g. `args = call_node.args` nil-defaulted with
  # `args = []` keeps the :array static type but carries the packed box. The
  # runtime's w_array_size handles that with a w_is_body check; dropping it
  # segfaulted stage 2 (load through 0xFFFEC…). The body length lives in the
  # box's low 21 bits, so both paths stay inline and call-free — the whole
  # diamond is pure and LICM-hoistable, preserving the fill-loop win.
  when :array_size_raw
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    lbl = "asz." + t.slice(1, t.size() - 1)
    parts = StringBuffer(480)
    parts << t + ".tg = lshr i64 " + v + ", 45\n  "
    parts << t + ".isb = icmp eq i64 " + t + ".tg, 524278\n  "
    parts << "br i1 " + t + ".isb, label %" + lbl + ".body, label %" + lbl + ".arr\n"
    parts << lbl + ".body:\n  "
    parts << t + ".bl = and i64 " + v + ", 2097151\n  "
    parts << "br label %" + lbl + ".done\n"
    parts << lbl + ".arr:\n  "
    parts << t + ".hdr = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".szp = getelementptr i8, ptr " + t + ".hp, i64 8\n  "
    parts << t + ".sz32 = load i32, ptr " + t + ".szp, align 4" + tbaa_header_suffix() + "\n  "
    parts << t + ".sz = sext i32 " + t + ".sz32 to i64\n  "
    parts << "br label %" + lbl + ".done\n"
    parts << lbl + ".done:\n  "
    parts << t + " = phi i64 \[" + t + ".bl, %" + lbl + ".body], \[" + t + ".sz, %" + lbl + ".arr]"
    parts.to_s()
  # Loop-versioning guard (lower_while_versioned): i1 = receiver is a live
  # polymorphic WArray — object space (high 16 bits zero, >= 16), heap
  # subtag 10, header ebits 65. Mirrors __w_array_get_i64_fast's entry
  # checks; the ebits load happens only behind the object-space branch, so
  # the whole test is safe on ANY WValue. Internal labels keep the phi's
  # predecessors self-contained (same trick as :array_size_raw).
  when :poly_array_guard
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    lbl = "pag." + t.slice(1, t.size() - 1)
    parts = StringBuffer(560)
    # v5: W_TAG_ARRAY (0xFFF4 = 65524) — the object-space + subtag pair
    # collapses to one tag compare; ebits load stays behind the branch.
    parts << t + ".hi = lshr i64 " + v + ", 48\n  "
    parts << t + ".o2 = icmp eq i64 " + t + ".hi, 65524\n  "
    parts << "br i1 " + t + ".o2, label %" + lbl + ".hdr, label %" + lbl + ".no\n"
    parts << lbl + ".no:\n  "
    parts << "br label %" + lbl + ".out\n"
    parts << lbl + ".hdr:\n  "
    parts << t + ".base = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".p = inttoptr i64 " + t + ".base to ptr\n  "
    parts << t + ".ebp = getelementptr i8, ptr " + t + ".p, i64 1\n  "
    parts << t + ".eb = load i8, ptr " + t + ".ebp, align 1" + invariant_load_suffix() + "\n  "
    parts << t + ".is65 = icmp eq i8 " + t + ".eb, 65\n  "
    parts << "br label %" + lbl + ".out\n"
    parts << lbl + ".out:\n  "
    parts << t + " = phi i1 \[false, %" + lbl + ".no], \[" + t + ".is65, %" + lbl + ".hdr]"
    parts.to_s()
  # WArray.cap (i32 header field at +12) — same shape/soundness as :ta_size_raw.
  when :ta_cap_raw
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    parts = StringBuffer(240)
    parts << t + ".hdr = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".cpp = getelementptr i8, ptr " + t + ".hp, i64 12\n  "
    parts << t + ".cp32 = load i32, ptr " + t + ".cpp, align 4" + tbaa_header_suffix() + "\n  "
    parts << t + " = sext i32 " + t + ".cp32 to i64"
    parts.to_s()
  # The *_at family carries warray_data TBAA (these are typed-array element
  # accesses) plus per-fusion-site scoped no-alias metadata when lowering
  # stamped ewscope (see ewscope_md_defs above).
  when :load_f64_at
    t = wire_get(inst, :temp)
    t + ".p = getelementptr double, ptr " + wire_get(inst, :ptr) + ", i64 " + wire_get(inst, :index) + "\n  " + t + " = load double, ptr " + t + ".p, align 8" + tbaa_elem_suffix() + ewscope_load_suffix(inst)
  when :store_f64_at
    t = wire_get(inst, :temp)
    t + " = getelementptr double, ptr " + wire_get(inst, :ptr) + ", i64 " + wire_get(inst, :index) + "\n  store double " + wire_get(inst, :value) + ", ptr " + t + ", align 8" + tbaa_elem_suffix() + ewscope_store_suffix(inst)
  # f32 variants: 4-byte stride, fpext on load / fptrunc on store so the
  # fused per-element computation stays in f64 (matching the CPU kernels,
  # which read f32 elements into doubles).
  when :load_f32_at
    t = wire_get(inst, :temp)
    t + ".p = getelementptr float, ptr " + wire_get(inst, :ptr) + ", i64 " + wire_get(inst, :index) + "\n  " + t + ".f32 = load float, ptr " + t + ".p, align 4" + tbaa_elem_suffix() + ewscope_load_suffix(inst) + "\n  " + t + " = fpext float " + t + ".f32 to double"
  when :store_f32_at
    t = wire_get(inst, :temp)
    t + ".tr = fptrunc double " + wire_get(inst, :value) + " to float\n  " + t + " = getelementptr float, ptr " + wire_get(inst, :ptr) + ", i64 " + wire_get(inst, :index) + "\n  store float " + t + ".tr, ptr " + t + ", align 4" + tbaa_elem_suffix() + ewscope_store_suffix(inst)
  when :load_i64_at
    t = wire_get(inst, :temp)
    t + ".p = getelementptr i64, ptr " + wire_get(inst, :ptr) + ", i64 " + wire_get(inst, :index) + "\n  " + t + " = load i64, ptr " + t + ".p, align 8" + tbaa_elem_suffix() + ewscope_load_suffix(inst)
  # Element-0 address of a typed array as a raw i64 — the arg block handed
  # to w_fused_parallel_run / w_fused_gpu_run. 8-byte stride (i64 blocks).
  when :ta_data_addr
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    parts = StringBuffer(400)
    parts << t + ".hdr = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".slp = getelementptr i8, ptr " + t + ".hp, i64 16\n  "
    parts << t + ".slots = load ptr, ptr " + t + ".slp, align 8" + tbaa_header_suffix() + "\n  "
    parts << t + ".stp = getelementptr i8, ptr " + t + ".hp, i64 4\n  "
    parts << t + ".st32 = load i32, ptr " + t + ".stp, align 4" + tbaa_header_suffix() + "\n  "
    parts << t + ".st = sext i32 " + t + ".st32 to i64\n  "
    parts << t + ".ep = getelementptr i64, ptr " + t + ".slots, i64 " + t + ".st\n  "
    parts << t + " = ptrtoint ptr " + t + ".ep to i64"
    parts.to_s()
  # f32 element-pointer decode (float stride) — sibling of :ta_f64_elems_ptr.
  when :ta_f32_elems_ptr
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    parts = StringBuffer(420)
    parts << t + ".hdr = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".slp = getelementptr i8, ptr " + t + ".hp, i64 16\n  "
    parts << t + ".slots = load ptr, ptr " + t + ".slp, align 8" + tbaa_header_suffix() + "\n  "
    parts << t + ".stp = getelementptr i8, ptr " + t + ".hp, i64 4\n  "
    parts << t + ".st32 = load i32, ptr " + t + ".stp, align 4" + tbaa_header_suffix() + "\n  "
    parts << t + ".st = sext i32 " + t + ".st32 to i64\n  "
    parts << t + " = getelementptr float, ptr " + t + ".slots, i64 " + t + ".st"
    parts.to_s()
  # Fixed-width integer sibling of the float element-pointer decoders. The
  # signedness lives on loads, not pointer arithmetic; :type is i8/i16/i32/i64.
  when :ta_int_elems_ptr
    t = wire_get(inst, :temp)
    v = wire_get(inst, :value)
    ty = wire_get(inst, :type)
    parts = StringBuffer(420)
    parts << t + ".hdr = and i64 " + v + ", 140737488355312\n  "
    parts << t + ".hp = inttoptr i64 " + t + ".hdr to ptr\n  "
    parts << t + ".slp = getelementptr i8, ptr " + t + ".hp, i64 16\n  "
    parts << t + ".slots = load ptr, ptr " + t + ".slp, align 8" + tbaa_header_suffix() + "\n  "
    parts << t + ".stp = getelementptr i8, ptr " + t + ".hp, i64 4\n  "
    parts << t + ".st32 = load i32, ptr " + t + ".stp, align 4" + tbaa_header_suffix() + "\n  "
    parts << t + ".st = sext i32 " + t + ".st32 to i64\n  "
    parts << t + " = getelementptr " + ty + ", ptr " + t + ".slots, i64 " + t + ".st"
    parts.to_s()
  when :load_int_at
    t = wire_get(inst, :temp)
    ty = wire_get(inst, :type)
    align = "8"
    if ty == "i8"
      align = "1"
    elsif ty == "i16"
      align = "2"
    elsif ty == "i32"
      align = "4"
    parts = StringBuffer(220)
    parts << t + ".p = getelementptr " + ty + ", ptr " + wire_get(inst, :ptr) + ", i64 " + wire_get(inst, :index) + "\n  "
    if ty == "i64"
      parts << t + " = load i64, ptr " + t + ".p, align " + align + tbaa_elem_suffix() + ewscope_load_suffix(inst)
    else
      parts << t + ".n = load " + ty + ", ptr " + t + ".p, align " + align + tbaa_elem_suffix() + ewscope_load_suffix(inst) + "\n  "
      ext = wire_get(inst, :kind) == :signed ? "sext" : "zext"
      parts << t + " = " + ext + " " + ty + " " + t + ".n to i64"
    parts.to_s()
  when :narrow_i64
    t = wire_get(inst, :temp)
    ty = wire_get(inst, :type)
    ext = wire_get(inst, :kind) == :signed ? "sext" : "zext"
    t + ".tr = trunc i64 " + wire_get(inst, :value) + " to " + ty + "\n  " + t + " = " + ext + " " + ty + " " + t + ".tr to i64"
  when :store_int_at
    t = wire_get(inst, :temp)
    ty = wire_get(inst, :type)
    align = "8"
    if ty == "i8"
      align = "1"
    elsif ty == "i16"
      align = "2"
    elsif ty == "i32"
      align = "4"
    parts = StringBuffer(220)
    stored = wire_get(inst, :value)
    if ty != "i64"
      parts << t + ".tr = trunc i64 " + stored + " to " + ty + "\n  "
      stored = t + ".tr"
    parts << t + " = getelementptr " + ty + ", ptr " + wire_get(inst, :ptr) + ", i64 " + wire_get(inst, :index) + "\n  "
    parts << "store " + ty + " " + stored + ", ptr " + t + ", align " + align + tbaa_elem_suffix() + ewscope_store_suffix(inst)
    parts.to_s()
  when :inttoptr_i64
    wire_get(inst, :temp) + " = inttoptr i64 " + wire_get(inst, :value) + " to ptr"
  # Address of a module function as raw i64 — passed to the runtime fused
  # partitioner, which calls it back as int64_t(*)(int64_t,int64_t,int64_t).
  when :fn_addr_i64
    wire_get(inst, :temp) + " = ptrtoint ptr @" + wire_get(inst, :name) + " to i64"
  when :fneg_f64
    wire_get(inst, :temp) + " = fneg double " + wire_get(inst, :value)

  # Float comparison — fp_flags only applies for fast mode (nnan changes predicate semantics)
  when :fcmp_f64
    f = wire_get(inst, :fp_flags)
    f = fp_flags if f == nil
    cmp_flags = f == "fast " ? "fast " : ""
    wire_get(inst, :temp) + " = fcmp " + cmp_flags + wire_get(inst, :pred) + " double " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)

  # i128 operations
  when :zext_i64_i128
    wire_get(inst, :temp) + " = zext i64 " + wire_get(inst, :value) + " to i128"
  when :trunc_i128_i64
    wire_get(inst, :temp) + " = trunc i128 " + wire_get(inst, :value) + " to i64"

  # Inline bool array get: load byte, add 1 -> W_FALSE(1) or W_TRUE(2)
  when :bool_array_get_byte_inline
    t = wire_get(inst, :temp)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    ap = t + ".ap"
    ap_p = t + ".app"
    dg = t + ".dg"
    dp = t + ".dp"
    ep = t + ".ep"
    byte = t + ".byte"
    ext = t + ".ext"
    out = StringBuffer(256)
    out << ap + " = and i64 " + arr + ", 140737488355312\n  "
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
    t = wire_get(inst, :temp)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    val = wire_get(inst, :val)
    ap = t + ".ap"
    ap_p = t + ".app"
    dg = t + ".dg"
    dp = t + ".dp"
    ep = t + ".ep"
    sub = t + ".sub"
    byte_val = t + ".bv"
    out = StringBuffer(256)
    out << ap + " = and i64 " + arr + ", 140737488355312\n  "
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
  # WArray-merge layout: slots ptr at offset 16, start i32 at
  # offset 4 (matching typed_array_get_inline). Pre-merge this read from
  # offset 8, which now points at size/cap and produces a garbage pointer.
  when :bool_array_get_inline
    t = wire_get(inst, :temp)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
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
    out << ap + " = and i64 " + arr + ", 140737488355312\n  "
    out << ap_p + " = inttoptr i64 " + ap + " to ptr\n  "
    out << dg + " = getelementptr i8, ptr " + ap_p + ", i64 16\n  "
    out << dp + " = load ptr, ptr " + dg + ", align 8" + tbaa_header_suffix() + "\n  "
    out << sg + " = getelementptr i8, ptr " + ap_p + ", i64 4\n  "
    out << s32 + " = load i32, ptr " + sg + ", align 4" + tbaa_header_suffix() + "\n  "
    out << s64 + " = sext i32 " + s32 + " to i64\n  "
    out << abs_idx + " = add i64 " + s64 + ", " + idx + "\n  "
    out << bi + " = lshr i64 " + abs_idx + ", 3\n  "
    out << bit64 + " = and i64 " + abs_idx + ", 7\n  "
    out << bit8 + " = trunc i64 " + bit64 + " to i8\n  "
    out << mask + " = shl i8 1, " + bit8 + "\n  "
    out << ep + " = getelementptr i8, ptr " + dp + ", i64 " + bi + "\n  "
    out << byte + " = load i8, ptr " + ep + tbaa_elem_suffix() + "\n  "
    out << masked + " = and i8 " + byte + ", " + mask + "\n  "
    # Two output flavors. With as_i1 the inline op leaves `t` as the
    # raw bit (`icmp ne i8 masked, 0`) — `if !bits[i]` / `while bits[i]`
    # consumers can branch on it directly. Without, we wrap in a select
    # to produce the W_TRUE/W_FALSE WValue. The lowering picks as_i1
    # when it knows the caller wants a boolean (truthy-elision); other
    # call sites get the WValue form and ensure_i64_value re-boxes if
    # needed.
    if wire_get(inst, :as_i1) == true
      out << t + " = icmp ne i8 " + masked + ", 0"
    else
      out << is_set + " = icmp ne i8 " + masked + ", 0\n  "
      out << t + " = select i1 " + is_set + ", i64 " + w_true.to_s() + ", i64 " + w_false.to_s()
    out.to_s()

  # Inline bool array set: val is guaranteed W_TRUE(2) or W_FALSE(1) by lowering.
  # Same offset fix as bool_array_get_inline above (slots ptr at offset 16,
  # start i32 at offset 4 — WArray-merge layout).
  when :bool_array_set_inline
    t = wire_get(inst, :temp)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    val = wire_get(inst, :val)
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
    out << ap + " = and i64 " + arr + ", 140737488355312\n  "
    out << ap_p + " = inttoptr i64 " + ap + " to ptr\n  "
    out << dg + " = getelementptr i8, ptr " + ap_p + ", i64 16\n  "
    out << dp + " = load ptr, ptr " + dg + ", align 8" + tbaa_header_suffix() + "\n  "
    out << sg + " = getelementptr i8, ptr " + ap_p + ", i64 4\n  "
    out << s32 + " = load i32, ptr " + sg + ", align 4" + tbaa_header_suffix() + "\n  "
    out << s64 + " = sext i32 " + s32 + " to i64\n  "
    out << abs_idx + " = add i64 " + s64 + ", " + idx + "\n  "
    out << bi + " = lshr i64 " + abs_idx + ", 3\n  "
    out << bit64 + " = and i64 " + abs_idx + ", 7\n  "
    out << bit8 + " = trunc i64 " + bit64 + " to i8\n  "
    out << mask + " = shl i8 1, " + bit8 + "\n  "
    out << ep + " = getelementptr i8, ptr " + dp + ", i64 " + bi + "\n  "
    out << byte + " = load i8, ptr " + ep + tbaa_elem_suffix() + "\n  "
    out << set_bit + " = icmp ugt i64 " + val + ", 1\n  "
    out << inv_mask + " = xor i8 " + mask + ", -1\n  "
    out << cleared + " = and i8 " + byte + ", " + inv_mask + "\n  "
    out << with_bit + " = or i8 " + cleared + ", " + mask + "\n  "
    out << new_byte + " = select i1 " + set_bit + ", i8 " + with_bit + ", i8 " + cleared + "\n  "
    out << "store i8 " + new_byte + ", ptr " + ep + tbaa_elem_suffix() + "\n  "
    out << t + " = add i64 " + val + ", 0"
    out.to_s()

  # Int to float conversion
  when :sitofp_i64_f64
    wire_get(inst, :temp) + " = sitofp i64 " + wire_get(inst, :value) + " to double"
  when :uitofp_i64_f64
    wire_get(inst, :temp) + " = uitofp i64 " + wire_get(inst, :value) + " to double"
  when :sitofp_i128_f64
    wire_get(inst, :temp) + " = sitofp i128 " + wire_get(inst, :value) + " to double"
  when :uitofp_i128_f64
    wire_get(inst, :temp) + " = uitofp i128 " + wire_get(inst, :value) + " to double"

  # Float
  when :const_float
    bits_temp = wire_get(inst, :temp) + ".bits"
    bits_temp + " = bitcast double " + wire_get(inst, :value) + " to i64\n  " + wire_get(inst, :temp) + " = add i64 " + bits_temp + ", " + machine_i64_text(w_double_bias)
  when :const_decimal
    wire_get(inst, :temp) + " = call i64 @w_decimal(i64 " + wire_get(inst, :sig).to_s() + ", i32 " + wire_get(inst, :scale).to_s() + ")"
  when :const_currency
    wire_get(inst, :temp) + " = call i64 @w_currency(i32 " + wire_get(inst, :symbol_id).to_s() + ", i64 " + wire_get(inst, :sig).to_s() + ", i32 " + wire_get(inst, :scale).to_s() + ")"
  when :const_quantity
    wire_get(inst, :temp) + " = call i64 @w_quantity(i32 " + wire_get(inst, :unit_id).to_s() + ", i64 " + wire_get(inst, :sig).to_s() + ", i32 " + wire_get(inst, :scale).to_s() + ")"
  when :const_duration_ns
    wire_get(inst, :temp) + " = call i64 @w_duration_ns(i64 " + wire_get(inst, :ns).to_s() + ")"
  when :const_duration_months_ms
    wire_get(inst, :temp) + " = call i64 @w_duration_months_ms(i32 " + wire_get(inst, :months).to_s() + ", i32 " + wire_get(inst, :ms).to_s() + ")"

  when :const_uuid
    used_ptr_ids[wire_get(inst, :string_id)] = true
    lbr = "\["
    rbr = "]"
    bl = wire_get(inst, :byte_len).to_s()
    wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :string_id).to_s() + ", i32 0, i32 0\n  " + wire_get(inst, :temp) + " = call i64 @w_uuid_from_hex(ptr " + wire_get(inst, :temp_ptr) + ")"

  when :const_date
    wire_get(inst, :temp) + " = call i64 @w_date(i32 " + wire_get(inst, :year).to_s() + ", i32 " + wire_get(inst, :month).to_s() + ", i32 " + wire_get(inst, :day).to_s() + ", i32 " + wire_get(inst, :hour).to_s() + ", i32 " + wire_get(inst, :min).to_s() + ", i32 " + wire_get(inst, :sec).to_s() + ", i32 " + wire_get(inst, :tz).to_s() + ")"

  when :const_ipv4
    wire_get(inst, :temp) + " = call i64 @w_ipv4(i32 " + wire_get(inst, :a).to_s() + ", i32 " + wire_get(inst, :b).to_s() + ", i32 " + wire_get(inst, :c).to_s() + ", i32 " + wire_get(inst, :d).to_s() + ", i32 " + wire_get(inst, :cidr).to_s() + ")"

  when :const_ipv6
    used_ptr_ids[wire_get(inst, :string_id)] = true
    lbr = "\["
    rbr = "]"
    bl = wire_get(inst, :byte_len).to_s()
    wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :string_id).to_s() + ", i32 0, i32 0\n  " + wire_get(inst, :temp) + " = call i64 @w_ipv6_from_string(ptr " + wire_get(inst, :temp_ptr) + ", i32 " + wire_get(inst, :cidr).to_s() + ")"

  when :const_rational
    wire_get(inst, :temp) + " = call i64 @w_rational(i32 " + wire_get(inst, :num).to_s() + ", i32 " + wire_get(inst, :den).to_s() + ")"

  when :const_char
    wire_get(inst, :temp) + " = call i64 @w_box_char(i32 " + wire_get(inst, :codepoint).to_s() + ")" + wvalue_char_range_metadata_suffix()

  when :const_color
    wire_get(inst, :temp) + " = call i64 @w_color(i32 " + wire_get(inst, :r).to_s() + ", i32 " + wire_get(inst, :g).to_s() + ", i32 " + wire_get(inst, :b).to_s() + ", i32 " + wire_get(inst, :a).to_s() + ")"

  # View access: load byte from raw object pointer.
  # The receiver mask for EVERY view op is 140737488355312
  # (0x00007FFF_FFFF_FFF0): it strips the low subtag nibble like the old
  # -16 AND the top-17 tag/sign bits, because BigInt receivers now ride a
  # top-level tag (0xFFFB, bit 47 reserved for tag-sign) rather than the
  # object space. Object-space receivers have zero top bits, so the wider
  # mask is a no-op for them. The array/hash/strbuf header derefs elsewhere
  # in this file keep -16: they sit behind subtag guards a bigint cannot
  # pass.
  when :view_load_byte
    ptr_raw = wire_get(inst, :temp) + ".ptr"
    byte_ptr = wire_get(inst, :temp) + ".bp"
    byte_val = wire_get(inst, :temp) + ".b"
    ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + wire_get(inst, :index) + "\n  " + byte_val + " = load i8, ptr " + wire_get(inst, :temp) + ".gep\n  " + wire_get(inst, :temp) + ".zext = zext i8 " + byte_val + " to i64\n  " + w_int_call_with_range(wire_get(inst, :temp), wire_get(inst, :temp) + ".zext", 0, 256)

  # Fixed inline u8[N] field: load at the statically known field offset plus
  # the caller-checked dynamic index. No hidden bounds branch is emitted.
  when :view_load_inline_byte
    ptr_raw = wire_get(inst, :temp) + ".ptr"
    byte_ptr = wire_get(inst, :temp) + ".bp"
    byte_val = wire_get(inst, :temp) + ".b"
    ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".base = getelementptr i8, ptr " + byte_ptr + ", i64 " + wire_get(inst, :offset).to_s() + "\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + wire_get(inst, :temp) + ".base, i64 " + wire_get(inst, :index) + "\n  " + byte_val + " = load i8, ptr " + wire_get(inst, :temp) + ".gep\n  " + wire_get(inst, :temp) + " = zext i8 " + byte_val + " to i64"

  # Widened inline array element (`u64[] limbs` and friends): strided load at
  # field offset + index * element size. i-prefixed elements sign-extend,
  # u-prefixed zero-extend; 64-bit elements load raw. Alignment is the static
  # residue of the field offset, which every element shares. Like the byte
  # form, no hidden bounds branch is emitted — the method owns the check.
  when :view_load_inline_elem
    ptr_raw = wire_get(inst, :temp) + ".ptr"
    byte_ptr = wire_get(inst, :temp) + ".bp"
    bits = (wire_get(inst, :size) * 8).to_s()
    elem_align = (wire_get(inst, :offset) % wire_get(inst, :size)) == 0 ? wire_get(inst, :size).to_s() : "1"
    head = ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".base = getelementptr i8, ptr " + byte_ptr + ", i64 " + wire_get(inst, :offset).to_s() + "\n  " + wire_get(inst, :temp) + ".gep = getelementptr i" + bits + ", ptr " + wire_get(inst, :temp) + ".base, i64 " + wire_get(inst, :index) + "\n  "
    if wire_get(inst, :size) == 8
      head + wire_get(inst, :temp) + " = load i64, ptr " + wire_get(inst, :temp) + ".gep, align " + elem_align
    else
      extension = wire_get(inst, :elem).starts_with?("i") ? "sext" : "zext"
      head + wire_get(inst, :temp) + ".w = load i" + bits + ", ptr " + wire_get(inst, :temp) + ".gep, align " + elem_align + "\n  " + wire_get(inst, :temp) + " = " + extension + " i" + bits + " " + wire_get(inst, :temp) + ".w to i64"

  # Store twin: truncate the raw value to the element width and store at the
  # same strided address; the instruction's temp carries the raw value
  # through so `$f[i] = v` keeps ordinary assignment-expression semantics.
  when :view_store_inline_elem
    ptr_raw = wire_get(inst, :temp) + ".ptr"
    byte_ptr = wire_get(inst, :temp) + ".bp"
    bits = (wire_get(inst, :size) * 8).to_s()
    elem_align = (wire_get(inst, :offset) % wire_get(inst, :size)) == 0 ? wire_get(inst, :size).to_s() : "1"
    head = ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".base = getelementptr i8, ptr " + byte_ptr + ", i64 " + wire_get(inst, :offset).to_s() + "\n  " + wire_get(inst, :temp) + ".gep = getelementptr i" + bits + ", ptr " + wire_get(inst, :temp) + ".base, i64 " + wire_get(inst, :index) + "\n  "
    if wire_get(inst, :size) == 8
      head + "store i64 " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :temp) + ".gep, align " + elem_align + "\n  " + wire_get(inst, :temp) + " = add i64 " + wire_get(inst, :value) + ", 0"
    else
      head + wire_get(inst, :temp) + ".t = trunc i64 " + wire_get(inst, :value) + " to i" + bits + "\n  store i" + bits + " " + wire_get(inst, :temp) + ".t, ptr " + wire_get(inst, :temp) + ".gep, align " + elem_align + "\n  " + wire_get(inst, :temp) + " = add i64 " + wire_get(inst, :value) + ", 0"

  # View access: load bit from raw object pointer
  when :view_load_bit
    ptr_raw = wire_get(inst, :temp) + ".ptr"
    byte_ptr = wire_get(inst, :temp) + ".bp"
    byte_idx = wire_get(inst, :temp) + ".bidx"
    bit_idx = wire_get(inst, :temp) + ".bitidx"
    byte_val = wire_get(inst, :temp) + ".b"
    shifted = wire_get(inst, :temp) + ".sh"
    masked = wire_get(inst, :temp) + ".m"
    ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + byte_idx + " = lshr i64 " + wire_get(inst, :index) + ", 3\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + byte_idx + "\n  " + byte_val + " = load i8, ptr " + wire_get(inst, :temp) + ".gep\n  " + bit_idx + " = and i64 " + wire_get(inst, :index) + ", 7\n  " + bit_idx + ".trunc = trunc i64 " + bit_idx + " to i8\n  " + shifted + " = lshr i8 " + byte_val + ", " + bit_idx + ".trunc\n  " + masked + " = and i8 " + shifted + ", 1\n  " + wire_get(inst, :temp) + ".zext = zext i8 " + masked + " to i64\n  " + w_int_call_with_range(wire_get(inst, :temp), wire_get(inst, :temp) + ".zext", 0, 2)

  # View field: load a named field at known offset/size from raw object pointer
  when :view_load_field
    ptr_raw = wire_get(inst, :temp) + ".ptr"
    byte_ptr = wire_get(inst, :temp) + ".bp"
    ftype = wire_get(inst, :field_type)
    offset = wire_get(inst, :offset).to_s()
    size = wire_get(inst, :size)
    extension = ftype.starts_with?("i") ? "sext" : "zext"
    if ftype.starts_with?("*")
      # Pointer field: load ptr, then ptrtoint
      ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + wire_get(inst, :temp) + ".p = load ptr, ptr " + wire_get(inst, :temp) + ".gep\n  " + wire_get(inst, :temp) + " = ptrtoint ptr " + wire_get(inst, :temp) + ".p to i64"
    elsif ftype == "f32"
      ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + wire_get(inst, :temp) + " = load float, ptr " + wire_get(inst, :temp) + ".gep, align 1"
    elsif ftype == "f64"
      ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + wire_get(inst, :temp) + " = load double, ptr " + wire_get(inst, :temp) + ".gep, align 1"
    elsif size == 1
      ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + wire_get(inst, :temp) + ".b = load i8, ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = " + extension + " i8 " + wire_get(inst, :temp) + ".b to i64"
    elsif size == 2
      ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + wire_get(inst, :temp) + ".h = load i16, ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = " + extension + " i16 " + wire_get(inst, :temp) + ".h to i64"
    elsif size == 4
      ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + wire_get(inst, :temp) + ".w = load i32, ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = " + extension + " i32 " + wire_get(inst, :temp) + ".w to i64"
    else
      # 8 bytes (i64)
      ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + wire_get(inst, :temp) + " = load i64, ptr " + wire_get(inst, :temp) + ".gep"

  # View field: store a scalar at a known native-data offset and return the
  # value converted to the field's declared width. Native layouts can be
  # packed, so every field store deliberately uses align 1 like field loads.
  when :view_store_field
    ptr_raw = wire_get(inst, :temp) + ".ptr"
    byte_ptr = wire_get(inst, :temp) + ".bp"
    ftype = wire_get(inst, :field_type)
    offset = wire_get(inst, :offset).to_s()
    size = wire_get(inst, :size)
    if size > 8
      raise "view_store_field cannot store fields wider than 64 bits"
    extension = ftype.starts_with?("i") ? "sext" : "zext"
    prefix = ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  "
    if ftype.starts_with?("*")
      prefix + wire_get(inst, :temp) + ".p = inttoptr i64 " + wire_get(inst, :value) + " to ptr\n  store ptr " + wire_get(inst, :temp) + ".p, ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = or i64 " + wire_get(inst, :value) + ", 0"
    elsif ftype == "f32"
      prefix + "store float " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = select i1 true, float " + wire_get(inst, :value) + ", float " + wire_get(inst, :value)
    elsif ftype == "f64"
      prefix + "store double " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = select i1 true, double " + wire_get(inst, :value) + ", double " + wire_get(inst, :value)
    elsif size == 1
      prefix + wire_get(inst, :temp) + ".b = trunc i64 " + wire_get(inst, :value) + " to i8\n  store i8 " + wire_get(inst, :temp) + ".b, ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = " + extension + " i8 " + wire_get(inst, :temp) + ".b to i64"
    elsif size == 2
      prefix + wire_get(inst, :temp) + ".h = trunc i64 " + wire_get(inst, :value) + " to i16\n  store i16 " + wire_get(inst, :temp) + ".h, ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = " + extension + " i16 " + wire_get(inst, :temp) + ".h to i64"
    elsif size == 4
      prefix + wire_get(inst, :temp) + ".w = trunc i64 " + wire_get(inst, :value) + " to i32\n  store i32 " + wire_get(inst, :temp) + ".w, ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = " + extension + " i32 " + wire_get(inst, :temp) + ".w to i64"
    else
      prefix + "store i64 " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = or i64 " + wire_get(inst, :value) + ", 0"

  # View base: extract raw pointer from object
  when :view_base_ptr
    wire_get(inst, :temp) + " = and i64 " + wire_get(inst, :value) + ", -16"

  # Register custom unit: call w_register_unit(i32 id, ptr name)
  when :register_unit
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :str_id)]
    if swv != nil
      "call void @w_register_unit_wv(i32 " + wire_get(inst, :unit_id).to_s() + ", i64 " + llvm_wvalue_literal(swv) + ")"
    else
      used_ptr_ids[wire_get(inst, :str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :byte_len).to_s()
      tmp = "%reg.unit." + wire_get(inst, :unit_id).to_s()
      tmp + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :str_id).to_s() + ", i32 0, i32 0\n  " + tmp + ".wv = call i64 @w_string(ptr " + tmp + ")\n  call void @w_register_unit_wv(i32 " + wire_get(inst, :unit_id).to_s() + ", i64 " + tmp + ".wv)"

  # String
  when :string_i64
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :string_id)]
    if swv != nil
      wire_get(inst, :temp) + " = or i64 0, " + llvm_wvalue_literal(swv)
    else
      used_ptr_ids[wire_get(inst, :string_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :byte_len).to_s()
      wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :string_id).to_s() + ", i32 0, i32 0\n  " + wire_get(inst, :temp) + " = call i64 @w_string(ptr " + wire_get(inst, :temp_ptr) + ")"

  # BigInt source literal: pass the executable's constant decimal bytes and
  # its module-local publication slot directly to the runtime.  The steady
  # state is one atomic load plus a recycler-backed copy of the pinned
  # template, preserving explicit alias-visible BigInt bang semantics.
  when :bigint_literal_i64
    used_ptr_ids[wire_get(inst, :string_id)] = true
    lbr = "\["
    rbr = "]"
    bl = wire_get(inst, :byte_len).to_s()
    wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :string_id).to_s() + ", i32 0, i32 0\n  " + wire_get(inst, :temp) + " = call i64 @w_bigint_literal_cached(ptr " + wire_get(inst, :temp_ptr) + ", ptr @.bigint.literal." + wire_get(inst, :slot_id).to_s() + ")"

  # Symbol: string WValue with bit 0 set
  when :symbol_i64
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :string_id)]
    if swv != nil
      wire_get(inst, :temp) + " = or i64 " + llvm_wvalue_literal(swv) + ", 1"
    else
      used_ptr_ids[wire_get(inst, :string_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :byte_len).to_s()
      wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :string_id).to_s() + ", i32 0, i32 0\n  " + wire_get(inst, :temp) + ".s = call i64 @w_string(ptr " + wire_get(inst, :temp_ptr) + ")\n  " + wire_get(inst, :temp) + " = call i64 @w_str_to_sym(i64 " + wire_get(inst, :temp) + ".s)"

  # Slab-AST constructor fusion (fix #3). Inline bump + N field stores
  # against the same slot address — no per-field re-derivation of the
  # slot pointer from the W_PACKED_NODE encoding.
  when :slab_alloc_init
    t = wire_get(inst, :temp)
    kind = wire_get(inst, :kind)
    sc = wire_get(inst, :sc)
    fields = wire_get(inst, :fields)
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
    parts << t + ".cursor_p = getelementptr inbounds { ptr, i32, i32 }, ptr @g_ast_store, i32 0, i32 1\n  "
    parts << t + ".cursor = load i32, ptr " + t + ".cursor_p, align 4\n  "
    parts << t + ".cap_p = getelementptr inbounds { ptr, i32, i32 }, ptr @g_ast_store, i32 0, i32 2\n  "
    parts << t + ".cap = load i32, ptr " + t + ".cap_p, align 4\n  "
    parts << t + ".new_cursor = add i32 " + t + ".cursor, " + nf.to_s() + "\n  "
    parts << t + ".has_room = icmp ule i32 " + t + ".new_cursor, " + t + ".cap\n  "
    parts << "br i1 " + t + ".has_room, label %" + label_fast + ", label %" + label_slow + ", !prof !31411\n"
    parts << label_fast + ":\n  "
    parts << "store i32 " + t + ".new_cursor, ptr " + t + ".cursor_p, align 4\n  "
    parts << t + ".base_p = getelementptr inbounds { ptr, i32, i32 }, ptr @g_ast_store, i32 0, i32 0\n  "
    parts << t + ".base = load ptr, ptr " + t + ".base_p, align 8\n  "
    parts << t + ".cursor64 = zext i32 " + t + ".cursor to i64\n  "
    parts << t + ".slot_addr = getelementptr i64, ptr " + t + ".base, i64 " + t + ".cursor64\n  "
    fi = 0
    while fi < nf
      parts << t + ".fp" + fi.to_s() + " = getelementptr i64, ptr " + t + ".slot_addr, i64 " + fi.to_s() + "\n  "
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
    parts << t + ".s.base_p = getelementptr inbounds { ptr, i32, i32 }, ptr @g_ast_store, i32 0, i32 0\n  "
    parts << t + ".s.base = load ptr, ptr " + t + ".s.base_p, align 8\n  "
    parts << t + ".s.slot_addr = getelementptr i64, ptr " + t + ".s.base, i64 " + t + ".s.off\n  "
    fi = 0
    while fi < nf
      parts << t + ".s.fp" + fi.to_s() + " = getelementptr i64, ptr " + t + ".s.slot_addr, i64 " + fi.to_s() + "\n  "
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
    # against @g_ast_store with a cmp/branch fallback to the runtime
    # @w_node_alloc on cap exhaustion (which grows + bumps). With fix #1's
    # constant-folded KIND_*/SC_* globals, LLVM collapses the kind/sc
    # shifts and OR into a single constant + bump in the fast path.
    #
    # Layout: the exact-width word arena is {ptr base, i32 cursor, i32 cap}.
    # Indices 1 and 2 reach cursor/cap respectively.
    #
    # Slab-AST intrinsic: w_node_field_load(node, offset) / w_node_field_store(
    # node, offset, value) — when the offset arg is a literal (which it always
    # is in ast.w call sites), emit inline LLVM IR that walks the
    # @g_ast_store slab directly instead of calling out to the runtime
    # helper. LLVM can then CSE the @g_ast_store base load across multiple
    # field accesses of the same node and fold the offset arithmetic into a
    # GEP. The args list is already lowered by the generic ccall_nobox path
    # in lowering/calls.w; the int-literal offset reaches here as a raw
    # decimal string because lower_int returns typed_value(:raw_int,
    # val.to_s()) without emitting an instruction.
    # Slab-AST intrinsic: decode the full-tier 8-bit kind or compact-tier
    # 5-bit kind according to prefix bit 44.
    if wire_get(inst, :name) == "w_node_kind_extern" && wire_get(inst, :args).size() == 1
      t = wire_get(inst, :temp)
      v = wire_get(inst, :args)[0]
      parts = StringBuffer(260)
      parts << t + ".prefix_sh = lshr i64 " + v + ", 44\n  "
      parts << t + ".prefix = and i64 " + t + ".prefix_sh, 1\n  "
      parts << t + ".full_sh = lshr i64 " + v + ", 36\n  "
      parts << t + ".full = and i64 " + t + ".full_sh, 255\n  "
      parts << t + ".compact_sh = lshr i64 " + v + ", 39\n  "
      parts << t + ".compact = and i64 " + t + ".compact_sh, 31\n  "
      parts << t + ".is_compact = icmp eq i64 " + t + ".prefix, 1\n  "
      parts << t + " = select i1 " + t + ".is_compact, i64 " + t + ".compact, i64 " + t + ".full"
      return parts.to_s()
    # Slab-AST intrinsic: w_is_node_extern(v) → 1 if v is a W_PACKED_NODE
    # (W_TAG_PACKED with subtype 3), 0 otherwise. (v >> 45) == 0x7FFF3
    # exploits the contiguous tag+subtype layout: 0xFFFE << 3 | 3.
    if wire_get(inst, :name) == "w_is_node_extern" && wire_get(inst, :args).size() == 1
      t = wire_get(inst, :temp)
      v = wire_get(inst, :args)[0]
      parts = StringBuffer(180)
      parts << t + ".upper = lshr i64 " + v + ", 45\n  "
      parts << t + ".is_node = icmp eq i64 " + t + ".upper, 524275\n  "
      parts << t + " = zext i1 " + t + ".is_node to i64"
      return parts.to_s()
    if wire_get(inst, :name) == "w_node_alloc" && wire_get(inst, :args).size() == 2
      t = wire_get(inst, :temp)
      kind_in = wire_get(inst, :args)[0]
      sc_in = wire_get(inst, :args)[1]
      parts = StringBuffer(240)
      # Defensive unbox: kind/sc here may carry the raw_int nanbox tag
      # (0xFFFA…) when they come from a runtime expression rather than a
      # literal KIND_*/SC_* global — e.g. ast_deep_clone's
      # `sc = sc_for_kind(kid)`, where the result is a `## i64` value
      # boxed into a general WValue local. Masking the low 48 bits extracts
      # the value and is idempotent for already-clean small ints.
      kind = t + ".kind_clean"
      sc = t + ".sc_clean"
      parts << kind + " = and i64 " + kind_in + ", 281474976710655\n  "
      parts << sc + " = and i64 " + sc_in + ", 281474976710655\n  "
      parts << t + " = call i64 @w_node_alloc(i64 " + kind + ", i64 " + sc + ")"
      return parts.to_s()
    slab_intrinsic = false
    if wire_get(inst, :name) == "w_node_field_load" || wire_get(inst, :name) == "w_node_field_store"
      if wire_get(inst, :args).size() >= 2
        first_char = wire_get(inst, :args)[1][0]
        if first_char != "%"
          slab_intrinsic = true
    if slab_intrinsic
      t = wire_get(inst, :temp)
      n = wire_get(inst, :args)[0]
      ivar_word = wire_get(inst, :args)[1].to_i().to_s()
      parts = StringBuffer(460)
      parts << t + ".off = and i64 " + n + ", 4294967295\n  "
      parts << t + ".full = add i64 " + t + ".off, " + ivar_word + "\n  "
      parts << t + ".base_p = getelementptr inbounds { ptr, i32, i32 }, ptr @g_ast_store, i32 0, i32 0\n  "
      parts << t + ".base = load ptr, ptr " + t + ".base_p, align 8\n  "
      parts << t + ".gep = getelementptr i64, ptr " + t + ".base, i64 " + t + ".full"
      if wire_get(inst, :name) == "w_node_field_load"
        parts << "\n  " + t + " = load i64, ptr " + t + ".gep, align 8"
      else
        # Freeze array values into the AST extra arena on the inline
        # store path too — mirrors the C-side w_node_field_store hook.
        parts << "\n  " + t + ".fz = call i64 @w_ast_freeze_if_array(i64 " + wire_get(inst, :args)[2] + ")"
        parts << "\n  store i64 " + t + ".fz, ptr " + t + ".gep, align 8"
        parts << "\n  " + t + " = add i64 " + t + ".fz, 0"
      return parts.to_s()
    args_str = render_call_args(wire_get(inst, :args), wire_get(inst, :arg_types))
    base = wire_get(inst, :temp) + " = " + call_prefix(inst) + " i64 @" + wire_get(inst, :name) + "(" + args_str + ")" + known_call_range_metadata_suffix(inst, "i64")
    if wire_get(inst, :src_line) != nil && wire_get(inst, :loc_site_id) != nil
      ret_lbl = "csd." + wire_get(inst, :loc_site_id).to_s() + ".ret"
      base + "\n  br label %" + ret_lbl + "\n" + ret_lbl + ":"
    else
      base
  when :call_direct_i128
    args_str = render_call_args(wire_get(inst, :args), wire_get(inst, :arg_types))
    wire_get(inst, :temp) + " = " + call_prefix(inst) + " i128 @" + wire_get(inst, :name) + "(" + args_str + ")"
  when :call_direct_i64_ptr1
    wire_get(inst, :temp) + " = " + call_prefix(inst) + " i64 @" + wire_get(inst, :name) + "(ptr " + wire_get(inst, :arg) + ")"

  # Load a compile-time SmallArray constant.
  # The named global is a private LLVM constant emitted at module scope
  # (see the small-array-consts emission pass; align 16). W_SUBTAG_SMALL_
  # ARRAY = 9, so the box is `(ptr & ~0xF) | 9`. Because the global is
  # 16-byte aligned the low nibble is already zero and a plain `or 9`
  # suffices.
  when :small_array_const_load
    wire_get(inst, :temp) + ".raw = ptrtoint ptr " + wire_get(inst, :const_name) + " to i64\n  " + wire_get(inst, :temp) + " = or i64 " + wire_get(inst, :temp) + ".raw, 9"

  # Allocate a SmallArray on the stack via
  # LLVM `alloca`. `total_bytes` is the WSmallArray header (2) + payload
  # bytes for the literal's ebits and size. The lowering follows up with
  # a ptrtoint and a call to w_small_array_init to stamp the header and
  # apply the W_SUBTAG_SMALL_ARRAY box. align 16 keeps the low nibble
  # clear so the runtime's box can OR the subtag in safely.
  #
  # The zeroing store is NOT optional. `i64[n]` and `SmallArray.new(:i64, n)`
  # are zero-initialised by contract, and the heap forms get that from
  # calloc — but `alloca` hands back whatever the previous frame at this
  # depth left behind, and w_small_array_init writes only the 2 header
  # bytes. Without this a recursive program reads its own dead frames
  # (proved: spec/compiler/small_array_stack_zero_init_spec.w). LLVM folds
  # the store into a single llvm.memset of total_bytes; the stack path is
  # still the cheaper half of calloc (no malloc, no free).
  when :small_array_alloca
    bytes = wire_get(inst, :total_bytes).to_s()
    wire_get(inst, :temp_ptr) + " = alloca \[" + bytes + " x i8\], align 16\n  store \[" + bytes + " x i8\] zeroinitializer, ptr " + wire_get(inst, :temp_ptr) + ", align 16"
  when :call_direct_void
    args_str = render_call_args(wire_get(inst, :args), wire_get(inst, :arg_types))
    base = call_prefix(inst) + " void @" + wire_get(inst, :name) + "(" + args_str + ")"
    if wire_get(inst, :src_line) != nil && wire_get(inst, :loc_site_id) != nil
      ret_lbl = "csd." + wire_get(inst, :loc_site_id).to_s() + ".ret"
      base + "\n  br label %" + ret_lbl + "\n" + ret_lbl + ":"
    else
      base

  # Source-loc hook fired before noreturn Tungsten calls (w_raise).
  # Writes (file, line, col) to thread-locals so the error formatter
  # recovers precise location even when the side-table misses.
  when :call_loc_set_col
    used_ptr_ids[wire_get(inst, :file_str_id)] = true
    lbr = "\["
    rbr = "]"
    bl = wire_get(inst, :file_byte_len).to_s()
    wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :file_str_id).to_s() + ", i32 0, i32 0\n  call void @__w_loc_set_col(ptr " + wire_get(inst, :temp_ptr) + ", i32 " + wire_get(inst, :line).to_s() + ", i32 " + wire_get(inst, :col).to_s() + ")"
  when :call_direct_void_ptr1
    call_prefix(inst) + " void @" + wire_get(inst, :name) + "(ptr " + wire_get(inst, :arg) + ")"
  when :call_direct_ptr
    args_str = render_call_args(wire_get(inst, :args), wire_get(inst, :arg_types))
    wire_get(inst, :temp) + " = " + call_prefix(inst) + " ptr @" + wire_get(inst, :name) + "(" + args_str + ")"

  # Call-site reuse allocation — per-site thread-local slot, reused across
  # calls. First call allocates and stores in the slot; subsequent calls
  # reset length and return the cached buffer. Zero malloc steady-state.
  when :call_reuse_or_new_array
    wire_get(inst, :temp) + " = call i64 @w_array_reuse_or_new_empty(ptr @" + wire_get(inst, :slot) + ")"
  when :call_reuse_or_new_hash
    wire_get(inst, :temp) + " = call i64 @w_hash_reuse_or_new(ptr @" + wire_get(inst, :slot) + ")"
  when :call_reuse_or_new_typed
    wire_get(inst, :temp) + " = call i64 @w_array_reuse_or_new(ptr @" + wire_get(inst, :slot) + ", i64 " + wire_get(inst, :bits).to_s() + ", i64 " + wire_get(inst, :cap) + ")"
  when :call_fused_out_reuse
    wire_get(inst, :temp) + " = call i64 @w_fused_out_reuse_or_new(ptr @" + wire_get(inst, :slot) + ", i64 " + wire_get(inst, :bits).to_s() + ", i64 " + wire_get(inst, :cap) + ")"
  when :call_reuse_or_new_strbuf
    wire_get(inst, :temp) + " = call i64 @w_strbuf_reuse_or_new(ptr @" + wire_get(inst, :slot) + ", i64 " + wire_get(inst, :cap) + ")"
  when :call_reuse_and_drain_or_new_hash
    wire_get(inst, :temp) + " = call i64 @w_hash_reuse_and_drain_or_new(ptr @" + wire_get(inst, :slot) + ")"

  # Recycle pool allocation (## recycle): pop from thread-local pool or alloc.
  when :call_recycle_or_new_array
    wire_get(inst, :temp) + " = call i64 @w_array_recycle_or_new_empty()"
  when :call_recycle_or_new_hash
    wire_get(inst, :temp) + " = call i64 @w_hash_recycle_or_new()"
  when :call_recycle_or_new_typed
    wire_get(inst, :temp) + " = call i64 @w_array_recycle_or_new(i64 " + wire_get(inst, :bits).to_s() + ", i64 " + wire_get(inst, :cap) + ")"
  when :call_recycle_or_new_strbuf
    wire_get(inst, :temp) + " = call i64 @w_strbuf_recycle_or_new(i64 " + wire_get(inst, :cap) + ")"

  # Recycle return-to-pool (emitted at scope exit for ## recycle vars).
  when :call_recycle_array
    "call void @w_array_recycle_public(i64 " + wire_get(inst, :value) + ")"
  when :call_recycle_hash
    "call void @w_hash_recycle(i64 " + wire_get(inst, :value) + ")"
  when :call_recycle_typed
    "call void @w_array_recycle(i64 " + wire_get(inst, :value) + ")"
  when :call_recycle_strbuf
    "call void @w_strbuf_recycle(i64 " + wire_get(inst, :value) + ")"

  # Cleanup stack push/pop for exception-safe recycle. Push after alloc,
  # pop just before the normal-path recycle fires. On w_raise, any entries
  # above the enclosing exception frame's saved cleanup_depth are invoked.
  when :cleanup_push_array
    "call void @w_cleanup_push(i64 " + wire_get(inst, :value) + ", ptr @w_array_recycle_public)"
  when :cleanup_push_hash
    "call void @w_cleanup_push(i64 " + wire_get(inst, :value) + ", ptr @w_hash_recycle)"
  when :cleanup_push_typed
    "call void @w_cleanup_push(i64 " + wire_get(inst, :value) + ", ptr @w_array_recycle)"
  when :cleanup_push_strbuf
    "call void @w_cleanup_push(i64 " + wire_get(inst, :value) + ", ptr @w_strbuf_recycle)"
  when :cleanup_pop
    "call void @w_cleanup_pop()"

  # Exception handling
  when :setjmp
    jump_name = windows_target ? "setjmp" : "_setjmp"
    wire_get(inst, :temp) + " = call i32 @" + jump_name + "(ptr " + wire_get(inst, :buf) + ")"
  when :icmp_eq_i32
    wire_get(inst, :temp) + " = icmp eq i32 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)

  # Method dispatch (dynamic) — inline-cached via w_method_call_cached.
  # When the call carries source-loc info, split the basic block so the
  # return address is addressable via blockaddress(@fn, %cs.N.ret). Same
  # pattern the overflow-check ops use (see :add_i48_checked).
  when :call_method_i64
    argc = wire_get(inst, :args).size()
    ic_ptr = wire_get(inst, :temp) + ".ic"
    ic_id = wire_get(inst, :ic_id).to_s()
    ic_gep = ic_ptr + " = getelementptr inbounds \[24 x i8], ptr @.ic, i64 " + ic_id + "\n  "
    ic_arg = ", ptr " + ic_ptr
    name_val = wire_get(inst, :method_name_val)
    parts = StringBuffer(128 + argc * 64)
    parts << ic_gep
    # Guarded devirtualization (lowering attaches devirt_fn/devirt_class when
    # the receiver's exact class is statically known): receiver is a WObject
    # (obj space, subtag 4) whose class_id (u16 at +0) equals @class.<C>'s
    # class_id (u16 at +16 in WClass) -> direct call to the method's function
    # symbol; anything else -> the ordinary IC dispatch below. The direct arm
    # skips dispatch entirely and lets LLVM inline small method bodies.
    dv_temp = wire_get(inst, :temp)
    if wire_get(inst, :devirt_fn) != nil
      t = wire_get(inst, :temp)
      lbl = "dv." + ic_id
      parts << t + ".hi = lshr i64 " + wire_get(inst, :receiver) + ", 48\n  "
      parts << t + ".z = icmp eq i64 " + t + ".hi, 0\n  "
      parts << t + ".ge = icmp uge i64 " + wire_get(inst, :receiver) + ", 16\n  "
      parts << t + ".o = and i1 " + t + ".z, " + t + ".ge\n  "
      parts << t + ".sb = and i64 " + wire_get(inst, :receiver) + ", 15\n  "
      parts << t + ".isi = icmp eq i64 " + t + ".sb, 4\n  "
      parts << t + ".oi = and i1 " + t + ".o, " + t + ".isi\n  "
      parts << "br i1 " + t + ".oi, label %" + lbl + ".ck, label %" + lbl + ".s\n"
      parts << lbl + ".ck:\n  "
      parts << t + ".om = and i64 " + wire_get(inst, :receiver) + ", -16\n  "
      parts << t + ".op = inttoptr i64 " + t + ".om to ptr\n  "
      parts << t + ".oc = load i16, ptr " + t + ".op, align 2\n  "
      parts << t + ".cw = load i64, ptr @class." + llvm_safe_name(wire_get(inst, :devirt_class).gsub(":", "__")) + "\n  "
      parts << t + ".cm = and i64 " + t + ".cw, -16\n  "
      parts << t + ".cp = inttoptr i64 " + t + ".cm to ptr\n  "
      parts << t + ".cip = getelementptr i8, ptr " + t + ".cp, i64 16\n  "
      parts << t + ".cc = load i16, ptr " + t + ".cip, align 2\n  "
      parts << t + ".same = icmp eq i16 " + t + ".oc, " + t + ".cc\n  "
      parts << "br i1 " + t + ".same, label %" + lbl + ".d, label %" + lbl + ".s\n"
      parts << lbl + ".d:\n  "
      parts << t + ".dv = call i64 @" + wire_get(inst, :devirt_fn) + "(i64 " + wire_get(inst, :receiver)
      di = 0
      while di < argc
        parts << ", i64 " + wire_get(inst, :args)[di]
        di += 1
      parts << ")\n  "
      parts << "br label %" + lbl + ".done\n"
      parts << lbl + ".s:\n  "
      dv_temp = t + ".sv"
    elsif wire_get(inst, :construct_fn) != nil
      t = wire_get(inst, :temp)
      lbl = "dv." + ic_id
      parts << t + ".cw = load i64, ptr @class." + llvm_safe_name(wire_get(inst, :construct_class).gsub(":", "__")) + "\n  "
      parts << t + ".same = icmp eq i64 " + wire_get(inst, :receiver) + ", " + t + ".cw\n  "
      parts << "br i1 " + t + ".same, label %" + lbl + ".d, label %" + lbl + ".s\n"
      parts << lbl + ".d:\n  "
      parts << t + ".dv = call i64 @w_object_new(i64 " + wire_get(inst, :receiver) + ")\n  "
      parts << t + ".init = call i64 @" + wire_get(inst, :construct_fn) + "(i64 " + t + ".dv"
      di = 0
      while di < argc
        parts << ", i64 " + wire_get(inst, :args)[di]
        di += 1
      parts << ")\n  "
      parts << "br label %" + lbl + ".done\n"
      parts << lbl + ".s:\n  "
      dv_temp = t + ".sv"
    # `notail` prevents LLVM from collapsing the call+ret pair into a tail
    # call when we need a real return address for the call-site lookup.
    # Without this, -O3 converts `call + br + ret` into a `b` (unconditional
    # branch) and the block-address we emit into @__w_call_site never matches
    # any PC captured by `backtrace()`.
    call_keyword = "call"
    if wire_get(inst, :src_line) != nil
      call_keyword = "notail call"
    if argc == 0
      parts << dv_temp + " = " + call_keyword + " i64 @w_method_call_cached_0(i64 " + wire_get(inst, :receiver) + ", i64 " + name_val + ic_arg + ")"
    elsif scalar_source_one_call?(inst)
      parts << dv_temp + " = " + call_keyword + " i64 @w_method_call_cached_1(i64 " + wire_get(inst, :receiver) + ", i64 " + name_val + ", i64 " + wire_get(inst, :args)[0] + ic_arg + ")"
    elsif scalar_source_two_call?(inst)
      parts << dv_temp + " = " + call_keyword + " i64 @w_method_call_cached_2(i64 " + wire_get(inst, :receiver) + ", i64 " + name_val + ", i64 " + wire_get(inst, :args)[0] + ", i64 " + wire_get(inst, :args)[1] + ic_arg + ")"
    else
      stack_arr = "%__mcall_args"
      i = 0
      while i < argc
        if i == 0
          slot = stack_arr
        else
          slot = wire_get(inst, :temp_args_val) + "." + i.to_s()
          parts << slot + " = getelementptr inbounds i64, ptr " + stack_arr + ", i32 " + i.to_s() + "\n  "
        parts << "store i64 " + wire_get(inst, :args)[i] + ", ptr " + slot + ", align 8\n  "
        i += 1
      parts << dv_temp + " = " + call_keyword + " i64 @w_method_call_cached(i64 " + wire_get(inst, :receiver) + ", i64 " + name_val + ", ptr " + stack_arr + ", i32 " + argc.to_s() + ic_arg + ")"
    if wire_get(inst, :src_line) != nil
      ret_lbl = "cs." + ic_id + ".ret"
      parts << "\n  br label %"
      parts << ret_lbl
      parts << "\n"
      parts << ret_lbl
      parts << ":"
    if wire_get(inst, :devirt_fn) != nil || wire_get(inst, :construct_fn) != nil
      t = wire_get(inst, :temp)
      lbl = "dv." + ic_id
      # The slow arm's value is defined in whichever block the IC render
      # left us in: the cs.N.ret continuation when a call-site table entry
      # was emitted, else the dv.N.s block itself.
      slow_pred = lbl + ".s"
      if wire_get(inst, :src_line) != nil
        slow_pred = "cs." + ic_id + ".ret"
      parts << "\n  br label %" + lbl + ".done\n"
      parts << lbl + ".done:\n  "
      parts << t + " = phi i64 \[" + t + ".dv, %" + lbl + ".d], \[" + t + ".sv, %" + slow_pred + "]"
    parts.to_s()

  # Control flow
  when :br
    unroll_count = wire_get(inst, :unroll_count)
    if wire_get(inst, :novec) == true && unroll_count != nil && unroll_count > 0
      "br label %" + wire_get(inst, :label) + ", !llvm.loop !" + latch_loop_md_ref(:both, unroll_count)
    elsif wire_get(inst, :novec) == true
      "br label %" + wire_get(inst, :label) + ", !llvm.loop !" + latch_loop_md_ref(:novec)
    elsif unroll_count != nil && unroll_count > 0
      "br label %" + wire_get(inst, :label) + ", !llvm.loop !" + latch_loop_md_ref(:unroll, unroll_count)
    else
      "br label %" + wire_get(inst, :label)
  when :cond_br
    prof = ""
    if wire_get(inst, :prof) == :likely
      prof = ", !prof !31411"
    elsif wire_get(inst, :prof) == :unlikely
      prof = ", !prof !31412"
    "br i1 " + wire_get(inst, :cond) + ", label %" + wire_get(inst, :then_label) + ", label %" + wire_get(inst, :else_label) + prof

  # i64 add with an overflow flag: temp = sum, temp.ovf = i1. Feeds the
  # sum-chunk accumulator's flush branch; lhs/rhs ride the substituted
  # fields so SSA renames reach them.
  when :sadd_with_overflow
    t = wire_get(inst, :temp)
    t + ".pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 " + wire_get(inst, :lhs) + ", i64 " + wire_get(inst, :rhs) + ")\n  " + t + " = extractvalue {i64, i1} " + t + ".pair, 0\n  " + t + ".ovf = extractvalue {i64, i1} " + t + ".pair, 1"
  when :switch_i64
    cases = wire_get(inst, :cases)
    is_symbol = wire_get(inst, :is_symbol)
    out = StringBuffer(96 + cases.size() * 48)
    out << "switch i64 " + wire_get(inst, :value) + ", label %" + wire_get(inst, :default_label) + " \[\n"
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
    "ret i64 " + (wire_get(inst, :value) == nil ? "0" : wire_get(inst, :value).to_s())
  when :ret_i32
    "ret i32 " + (wire_get(inst, :value) == nil ? "0" : wire_get(inst, :value).to_s())
  when :ret_void
    "ret void"
  when :unreachable
    "unreachable"

  # Phi
  when :phi_i1
    lbr = "\["
    rbr = "]"
    a_label = redirect_phi_label(wire_get(inst, :a_label), phi_label_redirects)
    b_label = redirect_phi_label(wire_get(inst, :b_label), phi_label_redirects)
    wire_get(inst, :temp) + " = phi i1 " + lbr + " " + wire_get(inst, :a_value) + ", %" + a_label + " " + rbr + ", " + lbr + " " + wire_get(inst, :b_value) + ", %" + b_label + " " + rbr
  when :phi_i64
    lbr = "\["
    rbr = "]"
    a_label = redirect_phi_label(wire_get(inst, :a_label), phi_label_redirects)
    b_label = redirect_phi_label(wire_get(inst, :b_label), phi_label_redirects)
    wire_get(inst, :temp) + " = phi i64 " + lbr + " " + wire_get(inst, :a_value) + ", %" + a_label + " " + rbr + ", " + lbr + " " + wire_get(inst, :b_value) + ", %" + b_label + " " + rbr

  # Argv init (main preamble)
  when :argv_init
    "call void @w_argv_init(i32 %argc, ptr %argv)"

  # I/O
  when :puts_i64
    if wire_get(inst, :temp) != nil
      wire_get(inst, :temp) + " = call i64 @w_puts(i64 " + wire_get(inst, :value) + ")"
    else
      "call i64 @w_puts(i64 " + wire_get(inst, :value) + ")"
  when :print_i64
    if wire_get(inst, :temp) != nil
      wire_get(inst, :temp) + " = call i64 @w_print(i64 " + wire_get(inst, :value) + ")"
    else
      "call i64 @w_print(i64 " + wire_get(inst, :value) + ")"

  # Memoization
  when :memo_init
    wire_get(inst, :temp) + " = call ptr @w_memo_init(ptr null)"
  when :store_memo_ptr
    "store ptr " + wire_get(inst, :value) + ", ptr @" + wire_get(inst, :global)
  when :load_memo_ptr
    wire_get(inst, :temp) + " = load ptr, ptr @" + wire_get(inst, :global)
  when :memo_call0_i64
    wire_get(inst, :temp) + " = call i64 @__w_memo_call0_i64(ptr " + wire_get(inst, :table) + ", ptr @" + wire_get(inst, :fn_name) + ")"
  when :memo_call1_i64
    wire_get(inst, :temp) + " = call i64 @__w_memo_call1_i64(ptr " + wire_get(inst, :table) + ", ptr @" + wire_get(inst, :fn_name) + ", i64 " + wire_get(inst, :args)[0] + ")"
  when :memo_call2_i64
    wire_get(inst, :temp) + " = call i64 @__w_memo_call2_i64(ptr " + wire_get(inst, :table) + ", ptr @" + wire_get(inst, :fn_name) + ", i64 " + wire_get(inst, :args)[0] + ", i64 " + wire_get(inst, :args)[1] + ")"

  # Classes
  when :class_new
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :name_str_id)]
    if swv != nil
      super_arg = nil
      if wire_get(inst, :super_reg) != nil
        super_arg = wire_get(inst, :super_reg)
      else
        super_arg = w_nil.to_s()
      wire_get(inst, :temp) + " = call i64 @w_class_new_wv(i64 " + llvm_wvalue_literal(swv) + ", i64 " + super_arg + ")"
    else
      used_ptr_ids[wire_get(inst, :name_str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :name_byte_len).to_s()
      parts = StringBuffer(160)
      parts << wire_get(inst, :temp) + ".ptr = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :name_str_id).to_s() + ", i32 0, i32 0\n  "
      parts << wire_get(inst, :temp) + ".name = call i64 @w_string(ptr " + wire_get(inst, :temp) + ".ptr)\n  "
      super_arg = nil
      if wire_get(inst, :super_reg) != nil
        super_arg = wire_get(inst, :super_reg)
      else
        super_arg = w_nil.to_s()
      parts << wire_get(inst, :temp) + " = call i64 @w_class_new_wv(i64 " + wire_get(inst, :temp) + ".name, i64 " + super_arg + ")"
      parts.to_s()
  when :class_store
    "store i64 " + wire_get(inst, :value) + ", ptr @class." + llvm_safe_name(wire_get(inst, :class_name).gsub(":", "__"))
  when :type_class_register
    "call void @w_type_class_register_wv(i32 " + wire_get(inst, :dispatch_key).to_s() + ", i64 " + wire_get(inst, :class_temp) + ")"
  when :node_kind_class_register
    "call void @w_node_kind_class_register_wv(i32 " + wire_get(inst, :kind_id).to_s() + ", i64 " + wire_get(inst, :class_temp) + ")"
  when :class_add_method
    add_fn = "w_class_add_method_wv"
    add_args = ", i32 " + wire_get(inst, :arity).to_s()
    if wire_get(inst, :splat_index) != nil && wire_get(inst, :splat_index) >= 0
      add_fn = "w_class_add_method_splat_wv"
      add_args += ", i32 " + wire_get(inst, :min_arity).to_s() + ", i32 " + wire_get(inst, :splat_index).to_s()
    elsif wire_get(inst, :min_arity) != nil && wire_get(inst, :min_arity) < wire_get(inst, :arity)
      add_fn = "w_class_add_method_range_wv"
      add_args += ", i32 " + wire_get(inst, :min_arity).to_s()
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :method_str_id)]
    if swv != nil
      "call void @" + add_fn + "(i64 " + wire_get(inst, :class_temp) + ", i64 " + llvm_wvalue_literal(swv) + ", ptr @" + wire_get(inst, :fn_name) + add_args + ")"
    else
      used_ptr_ids[wire_get(inst, :method_str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :method_byte_len).to_s()
      parts = StringBuffer(160)
      parts << wire_get(inst, :class_temp) + ".mname = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :method_str_id).to_s() + ", i32 0, i32 0\n  "
      parts << wire_get(inst, :class_temp) + ".mname.wv = call i64 @w_string(ptr " + wire_get(inst, :class_temp) + ".mname)\n  "
      parts << "call void @" + add_fn + "(i64 " + wire_get(inst, :class_temp) + ", i64 " + wire_get(inst, :class_temp) + ".mname.wv, ptr @" + wire_get(inst, :fn_name) + add_args + ")"
      parts.to_s()
  when :class_add_static_method
    add_fn = "w_class_add_static_method_wv"
    add_args = ", i32 " + wire_get(inst, :arity).to_s()
    if wire_get(inst, :splat_index) != nil && wire_get(inst, :splat_index) >= 0
      add_fn = "w_class_add_static_method_splat_wv"
      add_args += ", i32 " + wire_get(inst, :min_arity).to_s() + ", i32 " + wire_get(inst, :splat_index).to_s()
    elsif wire_get(inst, :min_arity) != nil && wire_get(inst, :min_arity) < wire_get(inst, :arity)
      add_fn = "w_class_add_static_method_range_wv"
      add_args += ", i32 " + wire_get(inst, :min_arity).to_s()
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :method_str_id)]
    if swv != nil
      "call void @" + add_fn + "(i64 " + wire_get(inst, :class_temp) + ", i64 " + llvm_wvalue_literal(swv) + ", ptr @" + wire_get(inst, :fn_name) + add_args + ")"
    else
      used_ptr_ids[wire_get(inst, :method_str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :method_byte_len).to_s()
      parts = StringBuffer(160)
      parts << wire_get(inst, :class_temp) + ".smname = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :method_str_id).to_s() + ", i32 0, i32 0\n  "
      parts << wire_get(inst, :class_temp) + ".smname.wv = call i64 @w_string(ptr " + wire_get(inst, :class_temp) + ".smname)\n  "
      parts << "call void @" + add_fn + "(i64 " + wire_get(inst, :class_temp) + ", i64 " + wire_get(inst, :class_temp) + ".smname.wv, ptr @" + wire_get(inst, :fn_name) + add_args + ")"
      parts.to_s()
  when :load_class
    wire_get(inst, :temp) + " = load i64, ptr @class." + llvm_safe_name(wire_get(inst, :class_name).gsub(":", "__"))
  when :store_global
    t = wire_get(inst, :type)
    if t == nil
      t = "i64"
    "store " + t + " " + wire_get(inst, :value) + ", ptr @global." + llvm_safe_name(wire_get(inst, :name))
  when :load_global
    t = wire_get(inst, :type)
    if t == nil
      t = "i64"
    wire_get(inst, :temp) + " = load " + t + ", ptr @global." + llvm_safe_name(wire_get(inst, :name))
  when :store_cvar
    "store i64 " + wire_get(inst, :value) + ", ptr @cvar." + llvm_safe_name(wire_get(inst, :cvar_key).gsub(":", "__"))
  when :load_cvar
    wire_get(inst, :temp) + " = load i64, ptr @cvar." + llvm_safe_name(wire_get(inst, :cvar_key).gsub(":", "__"))
  when :typed_array_get_inline
    # Inline typed array read: unmask → slots ptr (off 16) → start i32 (off 4) → GEP → load → ext
    # The i32 demote moved offsets: slots 32→16, start 8→4. Start is now
    # i32 and gets sign-extended before being added to the unboxed index.
    # Offsets locked by _Static_assert in runtime.h.
    t = wire_get(inst, :temp)
    s = wire_get(inst, :s)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    idx_raw = wire_get(inst, :idx_raw)
    bits = wire_get(inst, :bits)
    if bits == nil
      bits = 64
    signed = wire_get(inst, :signed)
    if signed == nil
      signed = true
    parts = StringBuffer(700)
    parts << s[0] + " = and i64 " + arr + ", 140737488355312\n  "   # unmask (W_ARRAY_PTR_MASK)
    parts << s[1] + " = inttoptr i64 " + s[0] + " to ptr\n  "      # struct ptr
    parts << s[2] + " = getelementptr i8, ptr " + s[1] + ", i64 16\n  "  # &slots
    parts << s[3] + " = load ptr, ptr " + s[2] + ", align 8" + tbaa_header_suffix() + "\n  "    # slots ptr — re-read each access: realloc (push/unshift past cap, clear) moves it, so NOT invariant. TBAA=header lets LICM hoist it when no realloc is in the loop.
    parts << s[4] + " = getelementptr i8, ptr " + s[1] + ", i64 4\n  "  # &start
    parts << s[5] + ".raw32 = load i32, ptr " + s[4] + ", align 4" + tbaa_header_suffix() + "\n  "  # start (i32) — re-read: shift/unshift move it. TBAA=header, same rationale.
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
      parts << t + " = load i64, ptr " + s[9] + ", align 8" + tbaa_elem_suffix()
    elsif bits == 32
      parts << s[9] + " = getelementptr i32, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i32, ptr " + s[9] + ", align 4" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i32 " + raw + " to i64"
      else
        parts << t + " = zext i32 " + raw + " to i64"
    elsif bits == 16
      parts << s[9] + " = getelementptr i16, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i16, ptr " + s[9] + ", align 2" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i16 " + raw + " to i64"
      else
        parts << t + " = zext i16 " + raw + " to i64"
    elsif bits == 8
      parts << s[9] + " = getelementptr i8, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i8, ptr " + s[9] + ", align 1" + tbaa_elem_suffix() + "\n  "
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
      parts << raw8 + " = load i8, ptr " + s[9] + ", align 1" + tbaa_elem_suffix() + "\n  "
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
      parts << t + " = load i64, ptr " + s[9] + ", align 8" + tbaa_elem_suffix()
    parts.to_s()
  when :typed_array_set_inline
    # Inline typed array write: same i32-offset shift as get.
    t = wire_get(inst, :temp)
    s = wire_get(inst, :s)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    idx_raw = wire_get(inst, :idx_raw)
    val = wire_get(inst, :value)
    bits = wire_get(inst, :bits)
    if bits == nil
      bits = 64
    parts = StringBuffer(700)
    parts << s[0] + " = and i64 " + arr + ", 140737488355312\n  "
    parts << s[1] + " = inttoptr i64 " + s[0] + " to ptr\n  "
    parts << s[2] + " = getelementptr i8, ptr " + s[1] + ", i64 16\n  "  # &slots (i32 demote: was 32)
    parts << s[3] + " = load ptr, ptr " + s[2] + ", align 8" + tbaa_header_suffix() + "\n  "    # slots ptr — re-read each access: realloc (push/unshift past cap, clear) moves it. TBAA=header lets LICM hoist it when no realloc is in the loop.
    parts << s[4] + " = getelementptr i8, ptr " + s[1] + ", i64 4\n  "   # &start (i32 demote: was 8)
    parts << s[5] + ".raw32 = load i32, ptr " + s[4] + ", align 4" + tbaa_header_suffix() + "\n  "   # start (i32) — re-read: shift/unshift move it. TBAA=header, same rationale.
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
      parts << "store i64 " + val + ", ptr " + s[9] + ", align 8" + tbaa_elem_suffix() + "\n  "
    elsif bits == 32
      parts << s[9] + " = getelementptr i32, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      tr = t + ".trunc"
      parts << tr + " = trunc i64 " + val + " to i32\n  "
      parts << "store i32 " + tr + ", ptr " + s[9] + ", align 4" + tbaa_elem_suffix() + "\n  "
    elsif bits == 16
      parts << s[9] + " = getelementptr i16, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      tr = t + ".trunc"
      parts << tr + " = trunc i64 " + val + " to i16\n  "
      parts << "store i16 " + tr + ", ptr " + s[9] + ", align 2" + tbaa_elem_suffix() + "\n  "
    elsif bits == 8
      parts << s[9] + " = getelementptr i8, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      tr = t + ".trunc"
      parts << tr + " = trunc i64 " + val + " to i8\n  "
      parts << "store i8 " + tr + ", ptr " + s[9] + ", align 1" + tbaa_elem_suffix() + "\n  "
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
      parts << raw8 + " = load i8, ptr " + s[9] + ", align 1" + tbaa_elem_suffix() + "\n  "
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
      parts << "store i8 " + tr + ", ptr " + s[9] + ", align 1" + tbaa_elem_suffix() + "\n  "
    else
      parts << s[9] + " = getelementptr i64, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      parts << "store i64 " + val + ", ptr " + s[9] + ", align 8" + tbaa_elem_suffix() + "\n  "
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
    t = wire_get(inst, :temp)
    s = wire_get(inst, :s)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    idx_raw = wire_get(inst, :idx_raw)
    val = wire_get(inst, :value)
    compound_op = wire_get(inst, :compound_op)
    bits = wire_get(inst, :bits)
    if bits == nil
      bits = 64
    signed = wire_get(inst, :signed)
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
    parts << s[0] + " = and i64 " + arr + ", 140737488355312\n  "
    parts << s[1] + " = inttoptr i64 " + s[0] + " to ptr\n  "
    parts << s[2] + " = getelementptr i8, ptr " + s[1] + ", i64 16\n  "
    parts << s[3] + " = load ptr, ptr " + s[2] + ", align 8" + tbaa_header_suffix() + "\n  "
    parts << s[4] + " = getelementptr i8, ptr " + s[1] + ", i64 4\n  "
    parts << s[5] + ".raw32 = load i32, ptr " + s[4] + ", align 4" + tbaa_header_suffix() + "\n  "
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
      parts << t + ".loaded = load i64, ptr " + s[9] + ", align 8" + tbaa_elem_suffix() + "\n  "
      parts << t + ".res = " + llvm_op + " i64 " + t + ".loaded, " + val + "\n  "
      parts << "store i64 " + t + ".res, ptr " + s[9] + ", align 8" + tbaa_elem_suffix() + "\n  "
      parts << t + " = add i64 " + t + ".res, 0"
    elsif bits == 32
      parts << s[9] + " = getelementptr i32, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      parts << t + ".loaded = load i32, ptr " + s[9] + ", align 4" + tbaa_elem_suffix() + "\n  "
      parts << t + ".v32 = trunc i64 " + val + " to i32\n  "
      parts << t + ".res32 = " + llvm_op + " i32 " + t + ".loaded, " + t + ".v32\n  "
      parts << "store i32 " + t + ".res32, ptr " + s[9] + ", align 4" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i32 " + t + ".res32 to i64"
      else
        parts << t + " = zext i32 " + t + ".res32 to i64"
    elsif bits == 16
      parts << s[9] + " = getelementptr i16, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      parts << t + ".loaded = load i16, ptr " + s[9] + ", align 2" + tbaa_elem_suffix() + "\n  "
      parts << t + ".v16 = trunc i64 " + val + " to i16\n  "
      parts << t + ".res16 = " + llvm_op + " i16 " + t + ".loaded, " + t + ".v16\n  "
      parts << "store i16 " + t + ".res16, ptr " + s[9] + ", align 2" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i16 " + t + ".res16 to i64"
      else
        parts << t + " = zext i16 " + t + ".res16 to i64"
    elsif bits == 8
      parts << s[9] + " = getelementptr i8, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      parts << t + ".loaded = load i8, ptr " + s[9] + ", align 1" + tbaa_elem_suffix() + "\n  "
      parts << t + ".v8 = trunc i64 " + val + " to i8\n  "
      parts << t + ".res8 = " + llvm_op + " i8 " + t + ".loaded, " + t + ".v8\n  "
      parts << "store i8 " + t + ".res8, ptr " + s[9] + ", align 1" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i8 " + t + ".res8 to i64"
      else
        parts << t + " = zext i8 " + t + ".res8 to i64"
    else
      parts << s[9] + " = getelementptr i64, ptr " + s[3] + ", i64 " + s[8] + "\n  "
      parts << t + ".loaded = load i64, ptr " + s[9] + ", align 8" + tbaa_elem_suffix() + "\n  "
      parts << t + ".res = " + llvm_op + " i64 " + t + ".loaded, " + val + "\n  "
      parts << "store i64 " + t + ".res, ptr " + s[9] + ", align 8" + tbaa_elem_suffix() + "\n  "
      parts << t + " = add i64 " + t + ".res, 0"
    parts.to_s()

  # BigArray inline read. Layout differs from WArray: the boxed value is a
  # generic object whose C struct carries a type byte at offset 0, i64
  # start/size/cap fields, and slots at offset 32. No bounds check here:
  # this is the unchecked `[]` path, and lowered each supplies in-range indices.
  when :big_array_get_inline
    t = wire_get(inst, :temp)
    s = wire_get(inst, :s)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    idx_raw = wire_get(inst, :idx_raw)
    bits = wire_get(inst, :bits)
    if bits == nil
      bits = 64
    signed = wire_get(inst, :signed)
    if signed == nil
      signed = true
    parts = StringBuffer(700)
    parts << s[0] + " = and i64 " + arr + ", -16\n  "                # unmask
    parts << s[1] + " = inttoptr i64 " + s[0] + " to ptr\n  "       # WBigArray*
    parts << s[2] + " = getelementptr i8, ptr " + s[1] + ", i64 32\n  "
    parts << s[3] + " = load ptr, ptr " + s[2] + ", align 8" + tbaa_header_suffix() + "\n  "     # slots
    parts << s[4] + " = getelementptr i8, ptr " + s[1] + ", i64 8\n  "
    parts << s[5] + " = load i64, ptr " + s[4] + ", align 8" + tbaa_header_suffix() + "\n  "     # start
    if idx_raw == true
      parts << s[6] + " = add i64 " + s[5] + ", " + idx + "\n  "
    else
      parts << s[6] + ".sl = shl i64 " + idx + ", 16\n  "
      parts << s[6] + ".as = ashr i64 " + s[6] + ".sl, 16\n  "
      parts << s[6] + " = add i64 " + s[5] + ", " + s[6] + ".as\n  "
    if bits == 64
      parts << s[7] + " = getelementptr i64, ptr " + s[3] + ", i64 " + s[6] + "\n  "
      parts << t + " = load i64, ptr " + s[7] + ", align 8" + tbaa_elem_suffix()
    elsif bits == 32
      parts << s[7] + " = getelementptr i32, ptr " + s[3] + ", i64 " + s[6] + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i32, ptr " + s[7] + ", align 4" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i32 " + raw + " to i64"
      else
        parts << t + " = zext i32 " + raw + " to i64"
    elsif bits == 16
      parts << s[7] + " = getelementptr i16, ptr " + s[3] + ", i64 " + s[6] + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i16, ptr " + s[7] + ", align 2" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i16 " + raw + " to i64"
      else
        parts << t + " = zext i16 " + raw + " to i64"
    elsif bits == 8
      parts << s[7] + " = getelementptr i8, ptr " + s[3] + ", i64 " + s[6] + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i8, ptr " + s[7] + ", align 1" + tbaa_elem_suffix() + "\n  "
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
      parts << raw8 + " = load i8, ptr " + s[7] + ", align 1" + tbaa_elem_suffix() + "\n  "
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
      parts << t + " = load i64, ptr " + s[7] + ", align 8" + tbaa_elem_suffix()
    parts.to_s()

  # SmallArray inline read. Layout differs
  # from WArray — slots are INLINE at offset 2 (header is just ebits +
  # size), no separate ptr load, no `start` shift. The index is kept as
  # a full i64 for the GEP: a `trunc … to i8` here silently maps any
  # index 128..255 to a NEGATIVE offset (signed i8 wrap), addressing
  # BEFORE the struct. No bounds check — caller proved [0, size).
  when :small_array_get_inline
    t = wire_get(inst, :temp)
    s = wire_get(inst, :s)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    idx_raw = wire_get(inst, :idx_raw)
    bits = wire_get(inst, :bits)
    if bits == nil
      bits = 8
    signed = wire_get(inst, :signed)
    if signed == nil
      signed = false
    # Element alignment. The HEADERFUL WSmallArray has a 2-byte header, so
    # elements sit at offset 2 + k*w — unaligned → align 1. The HEADERLESS form
    # is a raw [payload x i8] alloca (align 16) with elements at offset k*w →
    # naturally aligned; telling LLVM the true alignment is what lets it
    # vectorize a reduction over the buffer (align 1 blocks it).
    ealign = "align 1"
    if wire_get(inst, :headerless) == true
      if bits == 64
        ealign = "align 8"
      elsif bits == 32
        ealign = "align 4"
      elsif bits == 16
        ealign = "align 2"
    parts = StringBuffer(400)
    if wire_get(inst, :headerless) == true
      # Headerless stack SmallArray: arr IS the raw [payload x i8] alloca ptr —
      # slots start at offset 0 (no 2-byte ebits/size header) and there is no
      # box to unmask. The offset-0 GEP just rebinds arr as the slots base so
      # the per-width element GEPs below are unchanged. Keeping arr a raw ptr
      # (never ptrtoint'd) is what lets LLVM SROA promote the alloca.
      parts << s[2] + " = getelementptr i8, ptr " + arr + ", i64 0\n  "
    else
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
      parts << t + " = load i64, ptr " + s[4] + ", " + ealign + tbaa_elem_suffix()
    elsif bits == 32
      parts << s[4] + " = getelementptr i32, ptr " + s[2] + ", i64 " + s[3] + "\n  "
      parts << t + ".raw = load i32, ptr " + s[4] + ", " + ealign + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i32 " + t + ".raw to i64"
      else
        parts << t + " = zext i32 " + t + ".raw to i64"
    elsif bits == 16
      parts << s[4] + " = getelementptr i16, ptr " + s[2] + ", i64 " + s[3] + "\n  "
      parts << t + ".raw = load i16, ptr " + s[4] + ", " + ealign + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i16 " + t + ".raw to i64"
      else
        parts << t + " = zext i16 " + t + ".raw to i64"
    elsif bits == 8
      parts << s[4] + " = getelementptr i8, ptr " + s[2] + ", i64 " + s[3] + "\n  "
      parts << t + ".raw = load i8, ptr " + s[4] + ", align 1" + tbaa_elem_suffix() + "\n  "
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
      parts << raw8 + " = load i8, ptr " + s[4] + ", align 1" + tbaa_elem_suffix() + "\n  "
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
      parts << t + " = load i64, ptr " + s[4] + ", " + ealign + tbaa_elem_suffix()
    parts.to_s()

  # SmallArray inline write — same layout shortcuts as get.
  # Index kept as a full i64 (see get: an i8 trunc would address before
  # the struct for indices 128..255). No size update (SmallArray is
  # fixed-size by construction).
  when :small_array_set_inline
    t = wire_get(inst, :temp)
    s = wire_get(inst, :s)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    idx_raw = wire_get(inst, :idx_raw)
    val = wire_get(inst, :value)
    bits = wire_get(inst, :bits)
    if bits == nil
      bits = 8
    # Element alignment — natural for the headerless (no-header) form, byte for
    # the headerful WSmallArray. See :small_array_get_inline for the rationale.
    ealign = "align 1"
    if wire_get(inst, :headerless) == true
      if bits == 64
        ealign = "align 8"
      elsif bits == 32
        ealign = "align 4"
      elsif bits == 16
        ealign = "align 2"
    parts = StringBuffer(400)
    if wire_get(inst, :headerless) == true
      # Headerless stack SmallArray write: arr is the raw alloca ptr, slots at
      # offset 0, no unmask. See :small_array_get_inline for the rationale.
      parts << s[2] + " = getelementptr i8, ptr " + arr + ", i64 0\n  "
    else
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
      parts << "store i64 " + val + ", ptr " + s[4] + ", " + ealign + tbaa_elem_suffix() + "\n  "
    elsif bits == 32
      tr = t + ".tr"
      parts << s[4] + " = getelementptr i32, ptr " + s[2] + ", i64 " + s[3] + "\n  "
      parts << tr + " = trunc i64 " + val + " to i32\n  "
      parts << "store i32 " + tr + ", ptr " + s[4] + ", " + ealign + tbaa_elem_suffix() + "\n  "
    elsif bits == 16
      tr = t + ".tr"
      parts << s[4] + " = getelementptr i16, ptr " + s[2] + ", i64 " + s[3] + "\n  "
      parts << tr + " = trunc i64 " + val + " to i16\n  "
      parts << "store i16 " + tr + ", ptr " + s[4] + ", " + ealign + tbaa_elem_suffix() + "\n  "
    elsif bits == 8
      tr = t + ".tr"
      parts << s[4] + " = getelementptr i8, ptr " + s[2] + ", i64 " + s[3] + "\n  "
      parts << tr + " = trunc i64 " + val + " to i8\n  "
      parts << "store i8 " + tr + ", ptr " + s[4] + ", align 1" + tbaa_elem_suffix() + "\n  "
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
      parts << raw8 + " = load i8, ptr " + s[4] + ", align 1" + tbaa_elem_suffix() + "\n  "
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
      parts << "store i8 " + tr + ", ptr " + s[4] + ", align 1" + tbaa_elem_suffix() + "\n  "
    else
      parts << s[4] + " = getelementptr i64, ptr " + s[2] + ", i8 " + s[3] + "\n  "
      parts << "store i64 " + val + ", ptr " + s[4] + ", " + ealign + tbaa_elem_suffix() + "\n  "
    # Define result so SSA refs to t are valid.
    parts << t + " = add i64 " + val + ", 0"
    parts.to_s()

  when :array_get_inline
    # Inline WArray read: unmask → slots (off 16) → start i32 (off 4) → unbox idx → GEP → load
    # Offsets locked by _Static_assert in runtime.h (items renamed to slots).
    t = wire_get(inst, :temp)
    s = wire_get(inst, :s)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    parts = StringBuffer(500)
    parts << s[0] + " = and i64 " + arr + ", 140737488355312\n  "   # unmask (W_ARRAY_PTR_MASK)
    parts << s[1] + " = inttoptr i64 " + s[0] + " to ptr\n  "      # struct ptr
    parts << s[2] + ".field = getelementptr i8, ptr " + s[1] + ", i64 16\n  "  # &slots
    parts << s[2] + " = load ptr, ptr " + s[2] + ".field, align 8" + tbaa_header_suffix() + "\n  "   # slots ptr — TBAA=header lets LICM hoist when no realloc call is in the loop
    parts << s[3] + " = getelementptr i8, ptr " + s[1] + ", i64 4\n  "  # &start
    parts << s[4] + " = load i32, ptr " + s[3] + ", align 4" + tbaa_header_suffix() + "\n  "   # start (i32)
    parts << s[5] + " = sext i32 " + s[4] + " to i64\n  "          # start (i64)
    parts << s[6] + " = shl i64 " + idx + ", 16\n  "                # unbox idx
    parts << s[7] + " = ashr i64 " + s[6] + ", 16\n  "              # sign-extend
    parts << s[8] + " = add i64 " + s[5] + ", " + s[7] + "\n  "   # effective idx
    parts << s[9] + " = getelementptr i64, ptr " + s[2] + ", i64 " + s[8] + "\n  "  # elem ptr
    parts << t + " = load i64, ptr " + s[9] + ", align 8" + tbaa_elem_suffix()           # load element
    parts.to_s()
  when :builtin_class_init
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :name_str_id)]
    if swv != nil
      cn = llvm_safe_name(wire_get(inst, :class_name).gsub(":", "__"))
      parts = StringBuffer(128)
      parts << "%" + cn + ".cls = call i64 @w_class_new_wv(i64 " + llvm_wvalue_literal(swv) + ", i64 " + w_nil.to_s() + ")\n  "
      parts << "store i64 %" + cn + ".cls, ptr @class." + cn
      parts.to_s()
    else
      used_ptr_ids[wire_get(inst, :name_str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :name_byte_len).to_s()
      cn = llvm_safe_name(wire_get(inst, :class_name).gsub(":", "__"))
      parts = StringBuffer(192)
      parts << "%" + cn + ".ptr = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :name_str_id).to_s() + ", i32 0, i32 0\n  "
      parts << "%" + cn + ".name = call i64 @w_string(ptr %" + cn + ".ptr)\n  "
      parts << "%" + cn + ".cls = call i64 @w_class_new_wv(i64 %" + cn + ".name, i64 " + w_nil.to_s() + ")\n  "
      parts << "store i64 %" + cn + ".cls, ptr @class." + cn
      parts.to_s()

  # Instance variables
  when :ivar_get
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :str_id)]
    if swv != nil
      wire_get(inst, :temp) + " = call i64 @w_ivar_get_wv(i64 " + wire_get(inst, :self_reg) + ", i64 " + llvm_wvalue_literal(swv) + ")"
    else
      used_ptr_ids[wire_get(inst, :str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :byte_len).to_s()
      parts = StringBuffer(160)
      parts << wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :str_id).to_s() + ", i32 0, i32 0\n  "
      parts << wire_get(inst, :temp_ptr) + ".wv = call i64 @w_string(ptr " + wire_get(inst, :temp_ptr) + ")\n  "
      parts << wire_get(inst, :temp) + " = call i64 @w_ivar_get_wv(i64 " + wire_get(inst, :self_reg) + ", i64 " + wire_get(inst, :temp_ptr) + ".wv)"
      parts.to_s()
  when :ivar_set
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :str_id)]
    if swv != nil
      wire_get(inst, :temp) + " = call i64 @w_ivar_set_wv(i64 " + wire_get(inst, :self_reg) + ", i64 " + llvm_wvalue_literal(swv) + ", i64 " + wire_get(inst, :value) + ")"
    else
      used_ptr_ids[wire_get(inst, :str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :byte_len).to_s()
      parts = StringBuffer(160)
      parts << wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :str_id).to_s() + ", i32 0, i32 0\n  "
      parts << wire_get(inst, :temp_ptr) + ".wv = call i64 @w_string(ptr " + wire_get(inst, :temp_ptr) + ")\n  "
      parts << wire_get(inst, :temp) + " = call i64 @w_ivar_set_wv(i64 " + wire_get(inst, :self_reg) + ", i64 " + wire_get(inst, :temp_ptr) + ".wv, i64 " + wire_get(inst, :value) + ")"
      parts.to_s()
  when :ivar_get_idx
    byte_offset = (8 + wire_get(inst, :offset) * 8).to_s
    t = wire_get(inst, :temp)
    sr = wire_get(inst, :self_reg)
    parts = StringBuffer(160)
    parts << t + ".raw = and i64 " + sr + ", -16\n  "
    parts << t + ".ptr = inttoptr i64 " + t + ".raw to ptr\n  "
    parts << t + ".gep = getelementptr i8, ptr " + t + ".ptr, i64 " + byte_offset + "\n  "
    parts << t + " = load i64, ptr " + t + ".gep, align 8" + tbaa_ivar_suffix()
    parts.to_s()
  when :slab_node_get_idx
    # PR #2: read one slab slot from an AST node.
    # Unused — the active slab field path is the :call_direct_i64
    # branch above that special-cases wire_get(inst, :name) == "w_node_field_load".
    wire_get(inst, :temp) + " = call i64 @w_node_field_load(i64 " + wire_get(inst, :node) + ", i64 " + wire_get(inst, :offset).to_s() + ")"
  when :slab_node_set_idx
    # PR #2: write one slab slot. Unused; see :slab_node_get_idx
    # note above.
    t = wire_get(inst, :temp)
    parts = StringBuffer(192)
    parts << "call void @w_node_field_store(i64 " + wire_get(inst, :node) + ", i64 " + wire_get(inst, :offset).to_s() + ", i64 " + wire_get(inst, :value) + ")\n  "
    parts << t + " = add i64 " + wire_get(inst, :value) + ", 0"
    parts.to_s()
  when :ivar_set_idx
    byte_offset = (8 + wire_get(inst, :offset) * 8).to_s()
    t = wire_get(inst, :temp)
    sr = wire_get(inst, :self_reg)
    parts = StringBuffer(192)
    parts << t + ".raw = and i64 " + sr + ", -16\n  "
    parts << t + ".ptr = inttoptr i64 " + t + ".raw to ptr\n  "
    parts << t + ".gep = getelementptr i8, ptr " + t + ".ptr, i64 " + byte_offset + "\n  "
    parts << "store i64 " + wire_get(inst, :value) + ", ptr " + t + ".gep, align 8" + tbaa_ivar_suffix() + "\n  "
    parts << t + " = add i64 " + wire_get(inst, :value) + ", 0"
    parts.to_s()
  when :class_add_ivar
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :ivar_str_id)]
    if swv != nil
      "call i32 @w_class_add_ivar_wv(i64 " + wire_get(inst, :class_temp) + ", i64 " + llvm_wvalue_literal(swv) + ")"
    else
      used_ptr_ids[wire_get(inst, :ivar_str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :ivar_byte_len).to_s()
      ivar_ptr = wire_get(inst, :class_temp) + ".ivar_name"
      parts = StringBuffer(160)
      parts << ivar_ptr + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :ivar_str_id).to_s() + ", i32 0, i32 0\n  "
      parts << ivar_ptr + ".wv = call i64 @w_string(ptr " + ivar_ptr + ")\n  "
      parts << "call i32 @w_class_add_ivar_wv(i64 " + wire_get(inst, :class_temp) + ", i64 " + ivar_ptr + ".wv)"
      parts.to_s()

  # Closures
  when :null_ptr
    wire_get(inst, :temp) + " = inttoptr i64 0 to ptr"
  when :ptr_to_i64
    wire_get(inst, :temp) + " = ptrtoint ptr " + wire_get(inst, :value) + " to i64"
  when :i64_to_ptr
    wire_get(inst, :temp) + " = inttoptr i64 " + wire_get(inst, :value) + " to ptr"
  when :closure_new
    wire_get(inst, :temp) + " = call i64 @w_closure_new_a(ptr @" + wire_get(inst, :fn_name) + ", ptr " + wire_get(inst, :captures_ptr) + ", i32 " + wire_get(inst, :capture_count).to_s() + ", i32 " + (wire_get(inst, :block_arity) == nil ? 0 : wire_get(inst, :block_arity)).to_s() + ")"
  when :alloca_array
    lbr = "\["
    rbr = "]"
    wire_get(inst, :ptr) + " = alloca " + lbr + wire_get(inst, :count).to_s() + " x i64" + rbr + ", align 8"
  when :gep_array
    lbr = "\["
    rbr = "]"
    wire_get(inst, :temp) + " = getelementptr inbounds " + lbr + wire_get(inst, :count).to_s() + " x i64" + rbr + ", ptr " + wire_get(inst, :base) + ", i32 0, i32 " + wire_get(inst, :index).to_s()
  when :store_ptr
    "store i64 " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :dest) + ", align 8"
  when :load_ptr
    wire_get(inst, :temp) + " = load i64, ptr " + wire_get(inst, :ptr) + ", align 8"

  # SSA phi with N inputs (from mem2reg)
  when :phi_ssa
    lbr = "\["
    rbr = "]"
    incoming = wire_get(inst, :incoming)
    parts = StringBuffer(incoming.size() * 32 + 24)
    parts << wire_get(inst, :temp) + " = phi i64 "
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
    "call void @w_value_free(i64 " + wire_get(inst, :value) + ")"

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
  args = wire_get(inst, :args)
  if args.size() == 0
    return wire_get(inst, :temp_args_val) + " = call i64 @w_array_new_empty()\n  "
  out = StringBuffer(args.size() * 48 + 32)
  out << wire_get(inst, :temp_args_val) + " = call i64 @w_array_new_empty()\n  "
  i = 0
  while i < args.size()
    out << "call i64 @w_array_push(i64 " + wire_get(inst, :temp_args_val) + ", i64 " + args[i] + ")\n  "
    i += 1
  out.to_s()
