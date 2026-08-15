+ Interpreter

  -> dispatch_interpreted_ccall(args)
    if args.size() == 0
      raise "ccall requires a runtime function name"
    cname = "" + args[0]
    case cname
    when "w_atomic_new"
      if args.size() != 2
        raise "w_atomic_new expects one argument"
      return ccall("w_atomic_new", args[1])
    when "w_atomic_increment"
      if args.size() != 2
        raise "w_atomic_increment expects one receiver"
      return ccall("w_atomic_increment", args[1])
    when "w_atomic_decrement"
      if args.size() != 2
        raise "w_atomic_decrement expects one receiver"
      return ccall("w_atomic_decrement", args[1])
    when "w_atomic_get"
      if args.size() != 2
        raise "w_atomic_get expects one receiver"
      return ccall("w_atomic_get", args[1])
    when "w_atomic_set"
      if args.size() != 3
        raise "w_atomic_set expects one receiver and one value"
      return ccall("w_atomic_set", args[1], args[2])
    when "w_atomic_exchange"
      if args.size() != 3
        raise "w_atomic_exchange expects one receiver and one value"
      return ccall("w_atomic_exchange", args[1], args[2])
    when "w_atomic_add"
      if args.size() != 3
        raise "w_atomic_add expects one receiver and one delta"
      return ccall("w_atomic_add", args[1], args[2])
    when "w_atomic_fetch_sub"
      if args.size() != 3
        raise "w_atomic_fetch_sub expects one receiver and one delta"
      return ccall("w_atomic_fetch_sub", args[1], args[2])
    when "w_atomic_cas"
      if args.size() != 4
        raise "w_atomic_cas expects one receiver, expected, and desired"
      return ccall("w_atomic_cas", args[1], args[2], args[3])
    when "w_setenv"
      if args.size() != 3
        raise "w_setenv expects a name and value"
      return ccall("w_setenv", args[1], args[2])
    when "w_unsetenv"
      if args.size() != 2
        raise "w_unsetenv expects a name"
      return ccall("w_unsetenv", args[1])
    when "w_env_keys"
      if args.size() != 1
        raise "w_env_keys expects no arguments"
      return ccall("w_env_keys")
    when "w_env_to_h"
      if args.size() != 1
        raise "w_env_to_h expects no arguments"
      return ccall("w_env_to_h")
    when "__w_file_join"
      if args.size() != 3
        raise "__w_file_join expects two path components"
      return ccall("__w_file_join", args[1], args[2])
    when "__w_file_read_dir"
      if args.size() != 2
        raise "__w_file_read_dir expects one path"
      return ccall("__w_file_read_dir", args[1])
    when "__w_read_file_prefix"
      if args.size() != 3
        raise "__w_read_file_prefix expects a path and byte limit"
      return ccall("__w_read_file_prefix", args[1], args[2])
    when "w_chan_new"
      if args.size() != 2
        raise "w_chan_new expects one capacity"
      return ccall("w_chan_new", args[1])
    when "w_mutex_new"
      if args.size() != 1
        raise "w_mutex_new expects no arguments"
      return ccall("w_mutex_new")
    when "w_mutex_lock"
      if args.size() != 2
        raise "w_mutex_lock expects one receiver"
      return ccall("w_mutex_lock", args[1])
    when "w_mutex_try_lock"
      if args.size() != 2
        raise "w_mutex_try_lock expects one receiver"
      return ccall("w_mutex_try_lock", args[1])
    when "w_mutex_unlock"
      if args.size() != 2
        raise "w_mutex_unlock expects one receiver"
      return ccall("w_mutex_unlock", args[1])
    when "w_mutex_locked"
      if args.size() != 2
        raise "w_mutex_locked expects one receiver"
      return ccall("w_mutex_locked", args[1])
    when "w_chan_new_unbounded"
      if args.size() != 1
        raise "w_chan_new_unbounded expects no arguments"
      return ccall("w_chan_new_unbounded")
    when "w_chan_recv"
      if args.size() != 2
        raise "w_chan_recv expects one receiver"
      return ccall("w_chan_recv", args[1])
    when "w_chan_recv_result"
      if args.size() != 2
        raise "w_chan_recv_result expects one receiver"
      return ccall("w_chan_recv_result", args[1])
    when "w_chan_try_recv_result"
      if args.size() != 2
        raise "w_chan_try_recv_result expects one receiver"
      return ccall("w_chan_try_recv_result", args[1])
    when "w_chan_recv_timeout_result"
      if args.size() != 3
        raise "w_chan_recv_timeout_result expects one receiver and timeout"
      return ccall("w_chan_recv_timeout_result", args[1], args[2])
    when "w_chan_send"
      if args.size() != 3
        raise "w_chan_send expects one receiver and value"
      return ccall("w_chan_send", args[1], args[2])
    when "w_chan_try_send"
      if args.size() != 3
        raise "w_chan_try_send expects one receiver and value"
      return ccall("w_chan_try_send", args[1], args[2])
    when "w_chan_try_send_result"
      if args.size() != 3
        raise "w_chan_try_send_result expects one receiver and value"
      return ccall("w_chan_try_send_result", args[1], args[2])
    when "w_chan_send_timeout"
      if args.size() != 4
        raise "w_chan_send_timeout expects one receiver, value, and timeout"
      return ccall("w_chan_send_timeout", args[1], args[2], args[3])
    when "w_sync_handle_kind_support"
      if args.size() != 2
        raise "w_sync_handle_kind_support expects one value"
      return ccall("w_sync_handle_kind_support", args[1])
    when "w_chan_close"
      if args.size() != 2
        raise "w_chan_close expects one receiver"
      return ccall("w_chan_close", args[1])
    when "__w_sleep"
      if args.size() != 2
        raise "__w_sleep expects one duration"
      return ccall("__w_sleep", args[1])
    when "w_thread_alive"
      if args.size() != 2
        raise "w_thread_alive expects one receiver"
      if interpreted_thread?(args[1])
        return args[1][:ivars]["@__thread_alive"]
      return ccall("w_thread_alive", args[1])
    when "__w_file_mmap"
      if args.size() != 2
        raise "__w_file_mmap expects one argument"
      return ccall("__w_file_mmap", args[1])
    when "__w_mmap_as_typed"
      if args.size() != 3
        raise "__w_mmap_as_typed expects two arguments"
      # The public source leaves pass fixed raw-i64 encodings. Interpreter
      # values are boxed, so make that one mixed-ABI conversion explicit here.
      ebits = ccall_nobox("w_numeric_to_i64", args[2]) ## i64
      return ccall_rawargs("__w_mmap_as_typed", args[1], ebits)
    # The tree walker executes on one host thread, so ordinary typed-array
    # accesses are the exact semantic mirror of these compiled C11 atomics.
    # Keep the narrow allowlist explicit: source cannot turn an arbitrary
    # ccall string into native memory access, while libraries using atomic
    # publication remain interpreter-compatible.
    when "__w_arr_load_acq"
      if args.size() != 3
        raise "__w_arr_load_acq expects an array and index"
      return ccall("w_array_get", args[1], args[2])
    when "__w_arr_store_rel"
      if args.size() != 4
        raise "__w_arr_store_rel expects an array, index, and value"
      z = ccall("w_array_set", args[1], args[2], args[3])
      return nil
    when "__w_arr_fetch_add"
      if args.size() != 4
        raise "__w_arr_fetch_add expects an array, index, and delta"
      old = ccall("w_array_get", args[1], args[2])
      z = ccall("w_array_set", args[1], args[2], old + args[3])
      return old
    when "__w_arr_compare_exchange"
      if args.size() != 5
        raise "__w_arr_compare_exchange expects an array, index, expected, and desired"
      if ccall("w_array_get", args[1], args[2]) == args[3]
        z = ccall("w_array_set", args[1], args[2], args[4])
        return 1
      return 0
    when "__w_arr_try_inc_below"
      if args.size() != 4
        raise "__w_arr_try_inc_below expects an array, index, and limit"
      current = ccall("w_array_get", args[1], args[2])
      if current < args[3]
        current += 1
        z = ccall("w_array_set", args[1], args[2], current)
        return current
      return 0
    when "__w_u32_merge_count"
      if args.size() != 6
        raise "__w_u32_merge_count expects two arrays, two offsets, and a word count"
      return ccall("__w_u32_merge_count", args[1], args[2], args[3], args[4], args[5])
    when "__w_u32_andnot_count"
      if args.size() != 6
        raise "__w_u32_andnot_count expects two arrays, two offsets, and a word count"
      return ccall("__w_u32_andnot_count", args[1], args[2], args[3], args[4], args[5])
    when "__w_u32_fill_flops"
      if args.size() != 2
        raise "__w_u32_fill_flops expects one counts array"
      return ccall("__w_u32_fill_flops", args[1])
    when "__w_u32_flops"
      if args.size() != 2
        raise "__w_u32_flops expects one counts array"
      return ccall("__w_u32_flops", args[1])
    when "w_int"
      # A compiled source method uses w_int only to turn a raw signed i64 into
      # its canonical immediate/BigInt WValue. Integers are already arbitrary
      # precision values in the tree walker, so the exact mirror is identity.
      if args.size() != 2 || !(type(args[1]) in ("Int" "BigInt"))
        raise "w_int expects one Integer argument"
      return args[1]
    when "w_u64"
      # Unsigned machine-word boxing has the same tree-walker representation:
      # Integer values are arbitrary precision already. Keep the explicit
      # boundary so source methods can share their native boxing decision with
      # eval mode, including values above signed i64 max.
      if args.size() != 2 || !(type(args[1]) in ("Int" "BigInt"))
        raise "w_u64 expects one Integer argument"
      return args[1]
    when "w_freeze"
      if args.size() != 2
        raise "w_freeze expects one argument"
      return ccall("w_freeze", args[1])
    when "w_frozen_p"
      if args.size() != 2
        raise "w_frozen_p expects one argument"
      return ccall("w_frozen_p", args[1])
    when "w_num_to_float"
      if args.size() != 2
        raise "w_num_to_float expects one numeric argument"
      return ccall("w_num_to_float", args[1])
    when "w_small_array_new"
      # Narrow fixture/constructor bridge for exercising runtime-backed
      # SmallArray source methods under eval mode. Convert the public WValue
      # arguments back to the raw C ABI explicitly.
      if args.size() != 4
        raise "w_small_array_new expects ebits, size, and bytes pointer"
      ebits = ccall_nobox("w_numeric_to_i64", args[1]) ## i64
      size = ccall_nobox("w_numeric_to_i64", args[2]) ## i64
      bytes = ccall_nobox("w_numeric_to_i64", args[3]) ## i64
      return ccall_rawargs("w_small_array_new", ebits, size, bytes)
    when "w_big_array_view"
      # BigArray views are the public route that can carry the full signed-i64
      # size header patterns needed to verify w_int overflow parity.
      if args.size() != 4
        raise "w_big_array_view expects data pointer, ebits, and length"
      data = ccall_nobox("w_numeric_to_i64", args[1]) ## i64
      ebits = ccall_nobox("w_numeric_to_i64", args[2]) ## i64
      length = ccall_nobox("w_numeric_to_i64", args[3]) ## i64
      return ccall_rawargs("w_big_array_view", data, ebits, length)
    when "w_quantity_unit_name"
      # Unit symbol of a Quantity, nil for any other value. The safe way to
      # test "is this a quantity?" without method dispatch (whose inline
      # caches cannot distinguish the 0xFFFD quantity/decimal box kinds in
      # compiled code) — core/physics relies on it in both engines.
      if args.size() != 2
        raise "w_quantity_unit_name expects one argument"
      return ccall("w_quantity_unit_name", args[1])
    when "w_quantity_value"
      # Bare numeric value (Decimal) of a Quantity — core/quantity.w#value.
      if args.size() != 2
        raise "w_quantity_value expects one argument"
      return ccall("w_quantity_value", args[1])
    when "w_quantity_to_f"
      # Evaluated Float of a Quantity (π-quantities collapse to coeff·π) —
      # core/quantity.w#to_f.
      if args.size() != 2
        raise "w_quantity_to_f expects one argument"
      return ccall("w_quantity_to_f", args[1])
    when "w_quantity_point"
      if args.size() != 3
        raise "w_quantity_point expects a quantity and origin"
      return ccall("w_quantity_point", args[1], args[2])
    when "w_quantity_delta"
      if args.size() != 3
        raise "w_quantity_delta expects a quantity and origin"
      return ccall("w_quantity_delta", args[1], args[2])
    when "w_quantity_point_p"
      if args.size() != 2
        raise "w_quantity_point_p expects one argument"
      return ccall("w_quantity_point_p", args[1])
    when "w_quantity_delta_p"
      if args.size() != 2
        raise "w_quantity_delta_p expects one argument"
      return ccall("w_quantity_delta_p", args[1])
    when "w_quantity_origin"
      if args.size() != 2
        raise "w_quantity_origin expects one argument"
      return ccall("w_quantity_origin", args[1])
    when "w_quantity_equivalent"
      if args.size() != 4
        raise "w_quantity_equivalent expects a quantity, target unit, and bridge"
      return ccall("w_quantity_equivalent", args[1], args[2], args[3])
    when "w_quantity_pipe"
      # Unit attach/convert used by Array#stdev's quantity arm; also maps
      # elementwise over arrays.
      if args.size() != 4
        raise "w_quantity_pipe expects three arguments"
      return ccall("w_quantity_pipe", args[1], args[2], args[3])
    when "w_executable_path"
      if args.size() != 1
        raise "w_executable_path expects no arguments"
      return ccall("w_executable_path")
    when "w_executable_dir"
      if args.size() != 1
        raise "w_executable_dir expects no arguments"
      return ccall("w_executable_dir")
    when "w_cpu_count"
      if args.size() != 1
        raise "w_cpu_count expects no arguments"
      return ccall("w_cpu_count")
    when "w_physical_memory_bytes"
      if args.size() != 1
        raise "w_physical_memory_bytes expects no arguments"
      return ccall("w_physical_memory_bytes")
    when "w_to_s"
      # Source-defined objects exist only in this interpreter environment;
      # native w_to_s cannot see their method table. Route through the tree
      # walker's equivalent only for those objects so core methods retain
      # custom to_s side effects. Native values must keep runtime conversion
      # details such as w_to_s(nil) == "" (distinct from display/inspect nil).
      value = args[1]
      if type(value) == "Hash" && value.has_key?(:rt) && value[:rt] == :object
        return w_to_s(value)
      return ccall("w_to_s", value)
    when "w_rational_numerator"
      if args.size() != 2
        raise "w_rational_numerator expects one Rational"
      return ccall("w_rational_numerator", args[1])
    when "w_rational_denominator"
      if args.size() != 2
        raise "w_rational_denominator expects one Rational"
      return ccall("w_rational_denominator", args[1])
    when "w_strbuf_append"
      return ccall("w_strbuf_append", args[1], args[2])
    when "w_strbuf_to_s"
      return ccall("w_strbuf_to_s", args[1])
    when "w_slab_freeze_safe"
      if args.size() != 1
        raise "w_slab_freeze_safe expects no arguments"
      # Test/support bridge for representation-sensitive source methods. The
      # helper returns a regular WValue and is safe to expose through the same
      # narrow allowlist as StringBuffer storage calls.
      return ccall("w_slab_freeze_safe")
    when "w_hash_has_key"
      # Storage-only Hash membership bridge used by source algorithms that
      # keep their key-equivalence policy in Tungsten. Arity/type checks keep
      # eval mode from turning the ccall string into a fatal native boundary.
      if args.size() != 3
        raise "w_hash_has_key expects two arguments"
      if type(args[1]) != "Hash"
        raise "w_hash_has_key expects a Hash receiver"
      return ccall("w_hash_has_key", args[1], args[2])
    when "w_hash_set"
      if args.size() != 4
        raise "w_hash_set expects three arguments"
      if type(args[1]) != "Hash"
        raise "w_hash_set expects a Hash receiver"
      return ccall("w_hash_set", args[1], args[2], args[3])
    when "w_string_bytes_view"
      return ccall("w_string_bytes_view", args[1])
    when "w_string_chars"
      if args.size() != 2
        raise "w_string_chars expects one argument"
      return ccall("w_string_chars", args[1])
    when "w_base64_encode_input"
      return ccall("w_base64_encode_input", args[1])
    when "w_base64_decode_input"
      return ccall("w_base64_decode_input", args[1])
    when "w_string_from_byte_array"
      return ccall("w_string_from_byte_array", args[1])
    when "w_string_take_byte_array"
      return ccall("w_string_take_byte_array", args[1], args[2])
    when "w_string_reverse"
      return ccall("w_string_reverse", args[1])
    when "w_string_normalize"
      if args.size() != 3
        raise "w_string_normalize expects a receiver and a form"
      nf = ccall_nobox("w_numeric_to_i64", args[2]) ## i64
      return ccall("w_string_normalize", args[1], nf)
    when "w_regex_scan"
      if args.size() != 3
        raise "w_regex_scan expects a regex and a subject"
      return ccall("w_regex_scan", args[1], args[2])
    when "w_regex_new"
      if args.size() != 3
        raise "w_regex_new expects a pattern and options"
      return ccall("w_regex_new", args[1], args[2])
    when "w_class_by_name"
      if args.size() != 2
        raise "w_class_by_name expects one argument"
      # The tree walker's classes are interpreter objects, not runtime
      # WClass registrations — resolve through the interpreter's own
      # registry (autoloading like any constant reference) so `.new` on
      # the result dispatches.
      cn = args[1].to_s
      try_autoload_class(cn)
      ik = @classes[cn]
      if ik != nil
        return ik
      return nil
    when "w_regex_scan_char"
      if args.size() != 5
        raise "w_regex_scan_char expects subject, start, length, and codepoint"
      return ccall("w_regex_scan_char", args[1], args[2], args[3], args[4])
    when "w_regex_scan_flag"
      if args.size() != 5
        raise "w_regex_scan_flag expects subject, start, length, and flag"
      return ccall("w_regex_scan_flag", args[1], args[2], args[3], args[4])
    when "w_string_from_codes"
      if args.size() != 4
        raise "w_string_from_codes expects codes, start, and length"
      return ccall("w_string_from_codes", args[1], args[2], args[3])
    when "w_int_to_str_boxed"
      return ccall("w_int_to_str_boxed", args[1])
    when "w_int_to_str_base_boxed"
      return ccall("w_int_to_str_base_boxed", args[1], args[2])
    when "bigint_powmod_any"
      return ccall("bigint_powmod_any", args[1], args[2], args[3])
    when "w_bigint_gcd"
      return ccall("w_bigint_gcd", args[1], args[2])
    when "w_bigint_lcm"
      return ccall("w_bigint_lcm", args[1], args[2])
    when "w_bigint_prime_q"
      return ccall("w_bigint_prime_q", args[1])
    when "w_bigint_add"
      return ccall("w_bigint_add", args[1], args[2])
    when "w_bigint_sub"
      return ccall("w_bigint_sub", args[1], args[2])
    when "w_bigint_mul_builtin_exact"
      return ccall("w_bigint_mul_builtin_exact", args[1], args[2])
    when "w_bit_and"
      return ccall("w_bit_and", args[1], args[2])
    when "w_bit_or"
      return ccall("w_bit_or", args[1], args[2])
    when "w_bit_xor"
      return ccall("w_bit_xor", args[1], args[2])
    when "w_bigint_div"
      return ccall("w_bigint_div", args[1], args[2])
    when "w_bigint_mod"
      return ccall("w_bigint_mod", args[1], args[2])
    when "w_bigint_shl"
      return ccall("w_bigint_shl", args[1], args[2])
    when "w_bigint_shr"
      return ccall("w_bigint_shr", args[1], args[2])
    when "w_bit_shl"
      return ccall("w_bit_shl", args[1], args[2])
    when "w_bit_shr"
      return ccall("w_bit_shr", args[1], args[2])
    when "w_bigint_to_f"
      return ccall("w_bigint_to_f", args[1])
    when "w_bigint_to_s"
      return ccall("w_bigint_to_s", args[1], args[2])
    when "bigint_isqrt_any"
      return ccall("bigint_isqrt_any", args[1])
    when "w_bigint_mark_shared_value"
      return ccall("w_bigint_mark_shared_value", args[1])
    when "w_bigint_shared_value"
      return ccall("w_bigint_shared_value", args[1])
    when "w_str_to_sym"
      return ccall("w_str_to_sym", args[1])
    when "w_algebra_rewrite_source"
      if args.size() != 2
        raise "w_algebra_rewrite_source expects one argument"
      return ccall("w_algebra_rewrite_source", args[1])

    when "w_date_parse"
      if args.size() != 2
        raise "w_date_parse expects one string"
      return ccall("w_date_parse", args[1])
    when "w_date_new_w"
      if args.size() != 8
        raise "w_date_new_w expects seven fields"
      return ccall("w_date_new_w", args[1], args[2], args[3], args[4],
                   args[5], args[6], args[7])
    when "w_date_today"
      if args.size() != 1
        raise "w_date_today expects no arguments"
      return ccall("w_date_today")
    when "w_ipv4_parse"
      return ccall("w_ipv4_parse", args[1])
    when "w_ipv4_from_octets"
      return ccall("w_ipv4_from_octets", args[1], args[2], args[3], args[4], args[5])
    when "w_ipv4_in_cidr"
      return ccall("w_ipv4_in_cidr", args[1], args[2])
    when "w_ipv6_parse"
      return ccall("w_ipv6_parse", args[1])
    when "w_ipv6_storage_clone"
      return ccall("w_ipv6_storage_clone", args[1], args[2])
    when "w_ipv6_storage_from_words"
      return ccall("w_ipv6_storage_from_words", args[1], args[2], args[3], args[4], args[5])
    when "w_netaddr_ipv6_p"
      return ccall("w_netaddr_ipv6_p", args[1])
    when "w_ipv6_in_cidr"
      return ccall("w_ipv6_in_cidr", args[1], args[2])
    when "w_ip_in_cidr"
      return ccall("w_ip_in_cidr", args[1], args[2])

    when "w_mac_parse"
      return ccall("w_mac_parse", args[1])

    when "w_array_shuffle"
      return ccall("w_array_shuffle", args[1])

    when "w_crypto_random_bytes"
      return ccall("w_crypto_random_bytes", args[1])
    when "w_crypto_md5_bytes"
      return ccall("w_crypto_md5_bytes", args[1])
    when "w_crypto_md5_hex"
      return ccall("w_crypto_md5_hex", args[1])
    when "w_crypto_sha1_bytes"
      return ccall("w_crypto_sha1_bytes", args[1])
    when "w_crypto_sha1_hex"
      return ccall("w_crypto_sha1_hex", args[1])
    when "w_crypto_sha224_bytes"
      return ccall("w_crypto_sha224_bytes", args[1])
    when "w_crypto_sha224_hex"
      return ccall("w_crypto_sha224_hex", args[1])
    when "w_eputs"
      return ccall("w_eputs", args[1])
    when "w_crypto_sha256_bytes"
      return ccall("w_crypto_sha256_bytes", args[1])
    when "w_crypto_sha256_hex"
      return ccall("w_crypto_sha256_hex", args[1])
    when "w_crypto_sha384_bytes"
      return ccall("w_crypto_sha384_bytes", args[1])
    when "w_crypto_sha384_hex"
      return ccall("w_crypto_sha384_hex", args[1])
    when "w_crypto_sha512_bytes"
      return ccall("w_crypto_sha512_bytes", args[1])
    when "w_crypto_sha512_hex"
      return ccall("w_crypto_sha512_hex", args[1])
    when "w_crypto_sha512_224_bytes"
      return ccall("w_crypto_sha512_224_bytes", args[1])
    when "w_crypto_sha512_224_hex"
      return ccall("w_crypto_sha512_224_hex", args[1])
    when "w_crypto_sha512_256_bytes"
      return ccall("w_crypto_sha512_256_bytes", args[1])
    when "w_crypto_sha512_256_hex"
      return ccall("w_crypto_sha512_256_hex", args[1])
    when "w_carr_mul_f64"
      return ccall("w_carr_mul_f64", args[1], args[2])
    when "w_carr_conj_dot_f64"
      return ccall("w_carr_conj_dot_f64", args[1], args[2])
    when "w_carr_scale_f64"
      return ccall("w_carr_scale_f64", args[1], args[2], args[3])
    when "w_crypto_sha3_bytes"
      return ccall("w_crypto_sha3_bytes", args[1], args[2])
    when "w_crypto_sha3_hex"
      return ccall("w_crypto_sha3_hex", args[1], args[2])
    when "w_crypto_shake_bytes"
      return ccall("w_crypto_shake_bytes", args[1], args[2], args[3])
    when "w_crypto_shake_hex"
      return ccall("w_crypto_shake_hex", args[1], args[2], args[3])
    when "w_crypto_crc32"
      return ccall("w_crypto_crc32", args[1])
    when "w_crypto_crc32c"
      return ccall("w_crypto_crc32c", args[1])
    when "w_crypto_aes_gcm_seal"
      return ccall("w_crypto_aes_gcm_seal", args[1], args[2], args[3], args[4])
    when "w_crypto_aes_gcm_open"
      return ccall("w_crypto_aes_gcm_open", args[1], args[2], args[3], args[4])

    when "w_uuid_parse"
      return ccall("w_uuid_parse", args[1])
    when "w_uuid_namespace_nil"
      return ccall("w_uuid_namespace_nil")
    when "w_uuid_namespace_dns"
      return ccall("w_uuid_namespace_dns")
    when "w_uuid_namespace_url"
      return ccall("w_uuid_namespace_url")
    when "w_uuid_namespace_oid"
      return ccall("w_uuid_namespace_oid")
    when "w_uuid_namespace_x500"
      return ccall("w_uuid_namespace_x500")
    when "w_uuid_v1"
      return ccall("w_uuid_v1", args[1])
    when "w_uuid_v2"
      return ccall("w_uuid_v2", args[1])
    when "w_uuid_v3"
      return ccall("w_uuid_v3", args[1], args[2])
    when "w_uuid_v4"
      return ccall("w_uuid_v4")
    when "w_uuid_v5"
      return ccall("w_uuid_v5", args[1], args[2])
    when "w_uuid_v6"
      return ccall("w_uuid_v6")
    when "w_uuid_v7"
      return ccall("w_uuid_v7")
    when "w_uuid_v8"
      return ccall("w_uuid_v8", args[1])
    when "w_uuid_byte"
      return ccall("w_uuid_byte", args[1], args[2])
    when "w_uuid_bytes"
      return ccall("w_uuid_bytes", args[1])
    when "w_uuid_to_s"
      return ccall("w_uuid_to_s", args[1])

    # -- Typed arrays / Tensor / BLAS (core/blas, core/tensor) --
    # Class-side Tensor factories (`Tensor.zeros`) go through f32_array /
    # f64_array → w_array_new_aligned. Only symbols that exist in
    # runtime/runtime.h are listed here.
    when "w_array_new_aligned"
      return ccall("w_array_new_aligned", args[1], args[2])
    when "w_array_memmove_f64"
      return ccall("w_array_memmove_f64", args[1], args[2], args[3])
    when "w_tensor_zeros_f32"
      return ccall("w_tensor_zeros_f32", args[1])
    when "w_tensor_at_f32"
      return ccall("w_tensor_at_f32", args[1], args[2])
    when "w_tensor_set_f32"
      return ccall("w_tensor_set_f32", args[1], args[2], args[3])
    when "w_tensor_shape"
      return ccall("w_tensor_shape", args[1])
    when "w_tensor_rank"
      return ccall("w_tensor_rank", args[1])
    when "w_tensor_view_f32"
      return ccall("w_tensor_view_f32", args[1], args[2], args[3])
    when "w_tensor_slice0_f32"
      return ccall("w_tensor_slice0_f32", args[1], args[2], args[3])
    when "w_blas_sgemm_nn"
      return ccall("w_blas_sgemm_nn", args[1], args[2], args[3], args[4], args[5], args[6])
    when "w_blas_dgemm_nn"
      return ccall("w_blas_dgemm_nn", args[1], args[2], args[3], args[4], args[5], args[6])
    when "w_blas_sgemm_view"
      return ccall("w_blas_sgemm_view", args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10])
    when "w_blas_dgemm_view"
      return ccall("w_blas_dgemm_view", args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10])
    when "w_blas_sgemm_view_scaled"
      return ccall("w_blas_sgemm_view_scaled", args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11], args[12], args[13])
    when "w_blas_dgemm_view_scaled"
      return ccall("w_blas_dgemm_view_scaled", args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11], args[12], args[13])
    when "w_blas_reduce_view"
      return ccall("w_blas_reduce_view", args[1], args[2], args[3], args[4], args[5])
    when "w_blas_reduce_last"
      return ccall("w_blas_reduce_last", args[1], args[2], args[3], args[4], args[5], args[6], args[7])
    when "w_blas_unary_view"
      return ccall("w_blas_unary_view", args[1], args[2], args[3], args[4], args[5], args[6])
    when "w_blas_dot_f64"
      return ccall("w_blas_dot_f64", args[1], args[2], args[3])
    when "w_blas_norm_f64"
      return ccall("w_blas_norm_f64", args[1], args[2])
    when "w_blas_daxpy"
      return ccall("w_blas_daxpy", args[1], args[2], args[3], args[4])
    when "w_blas_dgemv_n"
      return ccall("w_blas_dgemv_n", args[1], args[2], args[3], args[4], args[5])
    when "w_blas_dscal"
      return ccall("w_blas_dscal", args[1], args[2], args[3])
    when "w_blas_dsymv_upper"
      return ccall("w_blas_dsymv_upper", args[1], args[2], args[3], args[4])
    when "w_blas_dsyrk_upper"
      return ccall("w_blas_dsyrk_upper", args[1], args[2], args[3], args[4], args[5], args[6])
    when "w_blas_dtrsm_left_lower"
      return ccall("w_blas_dtrsm_left_lower", args[1], args[2], args[3], args[4], args[5])
    when "w_blas_dgetrf_rowmajor"
      return ccall("w_blas_dgetrf_rowmajor", args[1], args[2], args[3])
    when "w_blas_dgetrs_rowmajor"
      return ccall("w_blas_dgetrs_rowmajor", args[1], args[2], args[3], args[4])
    when "w_blas_dgetrs_many_rowmajor"
      return ccall("w_blas_dgetrs_many_rowmajor", args[1], args[2], args[3], args[4], args[5])
    when "w_blas_dpotrf_lower"
      return ccall("w_blas_dpotrf_lower", args[1], args[2])
    when "w_blas_dpotrs_rowmajor"
      return ccall("w_blas_dpotrs_rowmajor", args[1], args[2], args[3], args[4])
    when "w_blas_dgeqrf_qr"
      return ccall("w_blas_dgeqrf_qr", args[1], args[2], args[3], args[4], args[5])
    when "w_blas_dgeqrf_factor"
      return ccall("w_blas_dgeqrf_factor", args[1], args[2], args[3], args[4])
    when "w_blas_dgeqrf_solve"
      return ccall("w_blas_dgeqrf_solve", args[1], args[2], args[3], args[4], args[5], args[6])
    when "w_blas_dsyev_values"
      return ccall("w_blas_dsyev_values", args[1], args[2], args[3])
    when "w_blas_dgesdd_values"
      return ccall("w_blas_dgesdd_values", args[1], args[2], args[3], args[4])
    when "w_blas_dgelsy"
      return ccall("w_blas_dgelsy", args[1], args[2], args[3], args[4])
    when "w_blas_dgeev"
      # LAPACK eigenvalues bridge (core/linalg.w eigenvalues_lapack).
      return ccall("w_blas_dgeev", args[1], args[2], args[3], args[4])

    # -- Array#csort / #tsort / #skasort / #wolfsort (core/array.w) --
    when "w_array_stable_sort"
      return ccall("w_array_stable_sort", args[1])
    when "w_array_csort"
      return ccall("w_array_csort", args[1])
    when "w_array_csort_range"
      return ccall("w_array_csort_range", args[1], args[2], args[3])
    when "w_array_tsort"
      return ccall("w_array_tsort", args[1])
    when "w_array_skasort"
      return ccall("w_array_skasort", args[1])
    when "w_array_wolfsort"
      return ccall("w_array_wolfsort", args[1])
    when "w_array_ipnsort"
      return ccall("w_array_ipnsort", args[1])

    # -- Array#to_f64 / #to_f32 (core/array.w; %f64[…]/%f32[…] desugar) --
    when "w_array_to_f64"
      return ccall("w_array_to_f64", args[1])
    when "w_array_to_f32"
      return ccall("w_array_to_f32", args[1])

    raise "Unsupported ccall '[cname]' in interpreter"

  -> interpreted_thread?(value)
    if type(value) != "Hash" || !value.has_key?(:rt) || value[:rt] != :object
      return false
    value[:w_class] != nil && value[:w_class][:name] == "Thread" && value[:ivars].has_key?("@__thread_result")

  # Raw-returning C helpers need an explicit tree-walker bridge. Keep this
  # allowlisted like dispatch_interpreted_ccall: eval mode must not turn an
  # arbitrary source-level string into an unrestricted native call.
  -> dispatch_interpreted_ccall_nobox(args)
    if args.size() == 0
      raise "ccall_nobox requires a runtime function name"
    cname = "" + args[0]
    case cname
    when "w_slab_is_frozen"
      if args.size() != 1
        raise "w_slab_is_frozen expects no arguments"
      return ccall("w_int", ccall_nobox("w_slab_is_frozen"))
    when "w_numeric_to_i64"
      if args.size() != 2
        raise "w_numeric_to_i64 expects one argument"
      # The native helper returns an unboxed int64_t. Rebox it explicitly so
      # the interpreter's value model receives an Integer rather than treating
      # the raw bits as an already-tagged WValue.
      return ccall("w_int", ccall_nobox("w_numeric_to_i64", args[1]))
    when "w_parser_chars_equal_ascii"
      if args.size() != 5
        raise "w_parser_chars_equal_ascii expects four arguments"
      off = ccall_nobox("w_numeric_to_i64", args[2]) ## i64
      len = ccall_nobox("w_numeric_to_i64", args[3]) ## i64
      return ccall("w_int", ccall_nobox("w_parser_chars_equal_ascii", args[1], off, len, args[4]))
    when "w_to_i64"
      if args.size() != 2
        raise "w_to_i64 expects one argument"
      # UUID#byte deliberately retains this narrower historical boundary:
      # Int and BigInt are accepted, while other numeric kinds are rejected.
      return ccall("w_int", ccall_nobox("w_to_i64", args[1]))
    when "w_u8_live_data_ptr"
      if args.size() != 2
        raise "w_u8_live_data_ptr expects one argument"
      # Preserve the raw pointer as an interpreter Integer. w_int promotes to
      # BigInt if it exceeds i48; raw_load/store convert it back explicitly.
      return ccall("w_int", ccall_nobox("w_u8_live_data_ptr", args[1]))
    when "w_stringy_c_length"
      if args.size() != 2
        raise "w_stringy_c_length expects one argument"
      # Rebox the raw strlen result for the tree walker's value model. The
      # native helper retains String/Symbol/rope validation and embedded-NUL
      # behavior, so eval and compiled Array#join cross the same boundary.
      return ccall("w_int", ccall_nobox("w_stringy_c_length", args[1]))
    when "w_string_byte_length"
      if args.size() != 2
        raise "w_string_byte_length expects one argument"
      # String#size/length source candidates use the exact stored-byte helper.
      # Rebox its raw i64 result for the tree walker's arbitrary-precision
      # Integer model, just as the compiled source body does explicitly.
      return ccall("w_int", ccall_nobox("w_string_byte_length", args[1]))
    when "w_string_data_ptr"
      if args.size() != 2
        raise "w_string_data_ptr expects one argument"
      # Raw byte pointer of a slab/heap String, reboxed like the u8 data-ptr
      # case above; raw_load/store convert it back explicitly.
      return ccall("w_int", ccall_nobox("w_string_data_ptr", args[1]))
    when "w_string_is_ascii"
      if args.size() != 2
        raise "w_string_is_ascii expects one argument"
      # Stored ASCII content flag (slab/heap/rope) for String#ascii?'s
      # non-inline arm; reboxed so the source body's `== 1` compares Ints.
      return ccall("w_int", ccall_nobox("w_string_is_ascii", args[1]))
    when "w_string_grapheme_next"
      if args.size() != 3
        raise "w_string_grapheme_next expects a receiver and a byte offset"
      gp = ccall_nobox("w_numeric_to_i64", args[2]) ## i64
      return ccall("w_int", ccall_nobox("w_string_grapheme_next", args[1], gp))
    when "w_is_native_regex"
      if args.size() != 2
        raise "w_is_native_regex expects one argument"
      return ccall("w_int", ccall_nobox("w_is_native_regex", args[1]))
    when "w_string_first_byte"
      if args.size() != 2
        raise "w_string_first_byte expects one argument"
      return ccall("w_int", ccall_nobox("w_string_first_byte", args[1]))
    when "__w_bit_ctpop_u32"
      if args.size() != 2
        raise "__w_bit_ctpop_u32 expects one argument"
      x = args[1] & 0xFFFFFFFF
      count = 0
      while x != 0
        x = x & (x - 1)
        count += 1
      return count
    when "__w_u32_merge_count_raw"
      if args.size() != 6
        raise "__w_u32_merge_count_raw expects two arrays, two offsets, and a word count"
      # Eval mode has no raw-int local tier. Reuse the boxed semantic twin;
      # compiled code alone selects the raw-return ABI.
      return ccall("__w_u32_merge_count", args[1], args[2], args[3], args[4], args[5])
    when "__w_u32_copy_raw"
      if args.size() != 6
        raise "__w_u32_copy_raw expects two arrays, two offsets, and a word count"
      # Eval mode carries interpreted Integers as WValues. The native helper
      # performs the same array/range/overlap checks; rebox its raw
      # element-count return for the tree walker.
      doff = ccall_nobox("w_numeric_to_i64", args[2]) ## i64
      soff = ccall_nobox("w_numeric_to_i64", args[4]) ## i64
      words = ccall_nobox("w_numeric_to_i64", args[5]) ## i64
      return ccall("w_int", ccall_nobox(
        "__w_u32_copy_raw", args[1], doff, args[3], soff, words))
    when "__w_u32_andnot_count_raw"
      if args.size() != 6
        raise "__w_u32_andnot_count_raw expects two arrays, two offsets, and a word count"
      return ccall("__w_u32_andnot_count", args[1], args[2], args[3], args[4], args[5])
    when "__w_u32_subset_except_raw"
      if args.size() != 7
        raise "__w_u32_subset_except_raw expects two arrays, two offsets, a word count, and an ignored bit"
      aoff = ccall_nobox("w_numeric_to_i64", args[2]) ## i64
      boff = ccall_nobox("w_numeric_to_i64", args[4]) ## i64
      words = ccall_nobox("w_numeric_to_i64", args[5]) ## i64
      except = ccall_nobox("w_numeric_to_i64", args[6]) ## i64
      return ccall("w_int", ccall_nobox(
        "__w_u32_subset_except_raw", args[1], aoff, args[3], boff,
        words, except))
    when "__w_u32_subset_except_trusted_raw"
      if args.size() != 7
        raise "__w_u32_subset_except_trusted_raw expects two arrays, two offsets, a word count, and an ignored bit"
      # Eval mode does not rely on the native caller's layout proof: preserve
      # checked semantics while exposing the trusted symbol to compiled code.
      aoff = ccall_nobox("w_numeric_to_i64", args[2]) ## i64
      boff = ccall_nobox("w_numeric_to_i64", args[4]) ## i64
      words = ccall_nobox("w_numeric_to_i64", args[5]) ## i64
      except = ccall_nobox("w_numeric_to_i64", args[6]) ## i64
      return ccall("w_int", ccall_nobox(
        "__w_u32_subset_except_raw", args[1], aoff, args[3], boff,
        words, except))
    when "__w_bit_ctpop_u64"
      if args.size() != 2
        raise "__w_bit_ctpop_u64 expects one argument"
      # Built from i48-safe literals, NOT 0xFFFFFFFFFFFFFFFF: the C VM's
      # parser wraps >int64 hex literals while the native parser promotes
      # them to BigInt, so the bare literal lowers differently on the two
      # bootstrap hosts and breaks stage-1/stage-2 byte identity.
      x = args[1] & ((0xFFFFFFFF << 32) | 0xFFFFFFFF)
      count = 0
      while x != 0
        x = x & (x - 1)
        count += 1
      return count
    when "__w_bit_ctlz_u32"
      if args.size() != 2
        raise "__w_bit_ctlz_u32 expects one argument"
      x = args[1] & 0xFFFFFFFF
      return 32 if x == 0
      count = 0
      bit = 0x80000000
      while (x & bit) == 0
        bit = bit >> 1
        count += 1
      return count
    when "__w_bit_ctlz_u64"
      if args.size() != 2
        raise "__w_bit_ctlz_u64 expects one argument"
      x = args[1] & ((0xFFFFFFFF << 32) | 0xFFFFFFFF)
      return 64 if x == 0
      count = 0
      bit = 0x80000000 << 32
      while (x & bit) == 0
        bit = bit >> 1
        count += 1
      return count
    when "__w_bit_cttz_u32"
      if args.size() != 2
        raise "__w_bit_cttz_u32 expects one argument"
      x = args[1] & 0xFFFFFFFF
      return 32 if x == 0
      count = 0
      while (x & 1) == 0
        x = x >> 1
        count += 1
      return count
    when "__w_bit_cttz_u64"
      if args.size() != 2
        raise "__w_bit_cttz_u64 expects one argument"
      # Same i48-safe mask spelling as ctpop_u64 above (stage identity).
      x = args[1] & ((0xFFFFFFFF << 32) | 0xFFFFFFFF)
      return 64 if x == 0
      count = 0
      while (x & 1) == 0
        x = x >> 1
        count += 1
      return count

    raise "Unsupported ccall_nobox '[cname]' in interpreter"

  # Familiar names from other languages, mapped to the Tungsten idiom — only
  # consulted after every real lookup has failed. (The lowering pass keeps its
  # own copy for unknown compiled calls; use-order separates the two files.)
  -> foreign_name_hint(name)
    case name
      "console" => "Tungsten prints with `<<`: << expression"
      "fmt" => "Tungsten prints with `<<`: << expression"
      "System" => "Tungsten prints with `<<`: << expression"
      "std" => "Tungsten prints with `<<`: << expression"
      "len" => "length is a method: value.size()"
      "elif" => "Tungsten spells it `elsif`"
      "lambda" => "blocks are written with `->`: list.map -> item * 2"
      "require" => "Tungsten imports with `use`: use core/tensor"
      "import" => "Tungsten imports with `use`: use core/tensor"
      "null" => "Tungsten's missing value is `nil`"
      "None" => "Tungsten's missing value is `nil`"
      "True" => "Tungsten booleans are lowercase: true"
      "False" => "Tungsten booleans are lowercase: false"
      => nil

  -> callable?(name)
    # Paren-less block-presence queries arrive as bare :var nodes; route them
    # to dispatch_bare_call's handler. `block_given?` remains a compatibility
    # alias for the Tungsten spelling, `block?`.
    if name in ("block?" "block_given?")
      return true
    if is_builtin?(name)
      return true
    if @env.defined?("__method__" + name)
      return true
    implicit_self_method(current_self(), name) != nil

  -> eval_ivar(node)
    obj = current_self()
    if obj == nil || type(obj) != "Hash" || !obj.has_key?(:rt) || obj[:rt] != :object
      raise "Instance variable outside of object context"
    name = ast_get(node, :name)
    if obj[:ivars].has_key?(name)
      return obj[:ivars][name]
    nil

  # Class variables (`@@name`). Stored on the WClass under :cvars (stripped
  # of the `@@` prefix). Resolve the owning class from the method being
  # executed, the class currently under definition, or a class-method self.
  -> cvar_owner_class
    m = @method_stack.last()
    if m != nil && m[:w_class] != nil
      return m[:w_class]
    s = current_self()
    if s != nil && type(s) == "Hash"
      if s.has_key?(:w_class)
        return s[:w_class]
      if s.has_key?(:rt) && s[:rt] == :class
        return s
    if @defining_class != nil
      return @defining_class
    nil

  -> cvar_key(name)
    if name.starts_with?("@@")
      return name.slice(2, name.size() - 2)
    name

  -> eval_cvar(node)
    w_class = cvar_owner_class()
    if w_class == nil
      raise "class variable outside of a class"
    key = cvar_key(ast_get(node, :name))
    if w_class[:cvars] == nil
      return nil
    w_class[:cvars][key]

  -> set_cvar(name, value)
    w_class = cvar_owner_class()
    if w_class == nil
      raise "class variable assignment outside of a class"
    if w_class[:cvars] == nil
      w_class[:cvars] = {}
    w_class[:cvars][cvar_key(name)] = value
    value

  # An unset $global reads as nil (matches Ruby) rather than raising —
  # unlike eval_var's undefined-name error path, since there's no
  # "did you mean a bare method call" ambiguity for a $-sigiled name.
  -> eval_gvar(node)
    name = ast_get(node, :name)
    # Inside a class method body `$value` is the receiver's exact 64-bit
    # WValue, not a process global. The compiled path exposes the same bits as
    # :raw_i64 in lower_gvar; box them here as an unsigned integer so the
    # tree-walker can faithfully evaluate pure-Tungsten bit extraction such
    # as `($value >> 12) & 0xFFFFFFFF` on packed values (IPv4, Token, ...).
    # w_u64 preserves the entire bit pattern by promoting to BigInt when the
    # high tag bits do not fit the immediate Integer payload.
    current_method = @method_stack.last()
    if name == "$value" && current_method != nil && current_method[:w_class] != nil
      return ccall("w_u64", current_self())
    # Bare `$field` inside a method is a direct read from that class's native
    # `- data` layout in compiled code. The tree walker cannot dereference the
    # backing struct itself, so route the same allowlisted scalar fields through
    # the narrow storage bridge used by explicit `receiver$field` reads. This
    # also handles fields whose semantic accessor has the same name (IPv6's
    # public `prefix`, for example), because `$field` bypasses that accessor.
    if name.starts_with?("$") && current_method != nil && current_method[:w_class] != nil
      field = name.slice(1, name.size() - 1)
      if native_data_field_supported?(current_method[:w_class], field)
        return ccall("w_native_data_field", current_self(), field)
    @globals[name]

  # `receiver$field` — read a view-decl field off an explicit receiver.
  # The tree-walker models `- data` layout fields as accessor methods
  # (register_data_field_accessors), so the faithful mirror of the
  # compiled inline struct read is to dispatch the field's accessor on
  # the evaluated receiver. Works for user classes with a data block and
  # for builtins whose field name coincides with a query method (arr$size).
  -> eval_view_field_var(node, env)
    recv = evaluate(ast_get(node, :receiver), env)
    field = ast_get(node, :field)
    # `recv$value` is the raw NaN-boxed word of the receiver — the
    # explicit-receiver twin of bare `$value`. Resolved before any data
    # field or method named `value`, mirroring lower_view_field_var's
    # precedence exactly (without this, `q$value` on a Quantity would
    # dispatch the `value` METHOD and diverge from compiled). w_u64
    # preserves the full bit pattern, promoting to BigInt as needed.
    if field == "value"
      return ccall("w_u64", recv)
    primitive_class = primitive_runtime_class(recv)
    if primitive_class != nil
      # View syntax names the declared storage field directly; it must not
      # depend on a public accessor existing. BigInt intentionally suppresses
      # a public `size` method while retaining the internal `value$size` view.
      if native_data_field_declared?(primitive_class, field)
        if native_data_field_supported?(primitive_class, field)
          return ccall("w_native_data_field", recv, field)
        raise "native data field '[field]' is unavailable in the interpreter"
    dispatch_method(recv, field, [], nil, env)

  # `receiver$field = value` — explicit-receiver native-data store. Keep the
  # interpreter boundary as narrow as the implicit `$field = value` path:
  # only declared fields with a checked runtime setter are writable.
  -> eval_view_field_var_set(node, value, env)
    recv = evaluate(ast_get(node, :receiver), env)
    field = ast_get(node, :field)
    primitive_class = primitive_runtime_class(recv)
    if native_data_field_declared?(primitive_class, field)
      if native_data_field_writable?(primitive_class, field)
        return ccall("w_native_data_field_set", recv, field, value)
      raise "native data field '[field]' is not writable in the interpreter"
    raise "native data field '[field]' is unavailable in the interpreter"
