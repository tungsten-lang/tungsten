# BigInt exact-width source seams selected while assembling an LLVM artifact.

bigint_exact_seams_cache = {rows: nil}

-> bigint_binary_exact_seams
  cached = bigint_exact_seams_cache[:rows]
  if cached != nil
    return cached
  rows = [
    ["__bigint_sub1_1_raw", "__w_bigint_sub1_1_src", "subtraction", "sub1@1", :require_bigint_sub1_1_src, :minus, ""],
    ["__bigint_sub1_2_raw", "__w_bigint_sub1_2_src", "subtraction", "sub1@2", :require_bigint_sub1_2_src, :minus, " alwaysinline"],
    ["__bigint_mul1_1_raw", "__w_bigint_mul1_1_src", "multiplication", "mul1@1", :require_bigint_mul1_1_src, :times, " alwaysinline"],
    ["__bigint_sqr2_raw", "__w_bigint_sqr2_src", "squaring", "sqr@2", :require_bigint_sqr2_src, :times, " alwaysinline"],
    ["__bigint_sqr3_raw", "__w_bigint_sqr3_src", "squaring", "sqr@3", :require_bigint_sqr3_src, :times, " alwaysinline"],
    ["__bigint_sqr4_raw", "__w_bigint_sqr4_src", "squaring", "sqr@4", :require_bigint_sqr4_src, :times, " alwaysinline"],
    ["__bigint_sqr5_raw", "__w_bigint_sqr5_src", "squaring", "sqr@5", :require_bigint_sqr5_src, :times, " alwaysinline"],
    ["__bigint_sqr6_raw", "__w_bigint_sqr6_src", "squaring", "sqr@6", :require_bigint_sqr6_src, :times, " alwaysinline"],
    ["__bigint_sqr7_raw", "__w_bigint_sqr7_src", "squaring", "sqr@7", :require_bigint_sqr7_src, :times, " alwaysinline"],
    ["__bigint_sqr8_raw", "__w_bigint_sqr8_src", "squaring", "sqr@8", :require_bigint_sqr8_src, :times, " alwaysinline"],
    ["__bigint_sqr16_raw", "__w_bigint_sqr16_src", "squaring", "sqr@16", :require_bigint_sqr16_src, :times, " alwaysinline"],
    ["__bigint_mul2_raw", "__w_bigint_mul2_src", "multiplication", "mul@2", :require_bigint_mul2_src, :times, " alwaysinline"],
    ["__bigint_mul3_raw", "__w_bigint_mul3_src", "multiplication", "mul@3", :require_bigint_mul3_src, :times, " alwaysinline"],
    ["__bigint_mul4_raw", "__w_bigint_mul4_src", "multiplication", "mul@4", :require_bigint_mul4_src, :times, " alwaysinline"],
    ["__bigint_mul5_raw", "__w_bigint_mul5_src", "multiplication", "mul@5", :require_bigint_mul5_src, :times, " alwaysinline"],
    ["__bigint_mul6_raw", "__w_bigint_mul6_src", "multiplication", "mul@6", :require_bigint_mul6_src, :times, " alwaysinline"],
    ["__bigint_mul7_raw", "__w_bigint_mul7_src", "multiplication", "mul@7", :require_bigint_mul7_src, :times, " alwaysinline"],
    ["__bigint_mul8_raw", "__w_bigint_mul8_src", "multiplication", "mul@8", :require_bigint_mul8_src, :times, " alwaysinline"],
    ["__bigint_mul12_raw", "__w_bigint_mul12_src", "multiplication", "mul@12", :require_bigint_mul12_src, :times, " alwaysinline"],
    ["__bigint_mul15_raw", "__w_bigint_mul15_src", "multiplication", "mul@15", :require_bigint_mul15_src, :times, " alwaysinline"],
    ["__bigint_mul16_raw", "__w_bigint_mul16_src", "multiplication", "mul@16", :require_bigint_mul16_src, :times, " alwaysinline"],
    ["__bigint_mul17_raw", "__w_bigint_mul17_src", "multiplication", "mul@17", :require_bigint_mul17_src, :times, " alwaysinline"],
    ["__bigint_mul21_raw", "__w_bigint_mul21_src", "multiplication", "mul@21", :require_bigint_mul21_src, :times, " alwaysinline"],
    ["__bigint_mul24_raw", "__w_bigint_mul24_src", "multiplication", "mul@24", :require_bigint_mul24_src, :times, " alwaysinline"],
    ["__bigint_mul1_2_raw", "__w_bigint_mul1_2_src", "multiplication", "mul1@2", :require_bigint_mul1_2_src, :times, " noinline"],
    ["__bigint_mul1_3_raw", "__w_bigint_mul1_3_src", "multiplication", "mul1@3", :require_bigint_mul1_3_src, :times, " noinline"],
    ["__bigint_mul1_4_raw", "__w_bigint_mul1_4_src", "multiplication", "mul1@4", :require_bigint_mul1_4_src, :times, " noinline"],
    ["__bigint_mul1_5_raw", "__w_bigint_mul1_5_src", "multiplication", "mul1@5", :require_bigint_mul1_5_src, :times, " noinline"],
    ["__bigint_mul1_6_raw", "__w_bigint_mul1_6_src", "multiplication", "mul1@6", :require_bigint_mul1_6_src, :times, " noinline"],
    ["__bigint_mul1_7_raw", "__w_bigint_mul1_7_src", "multiplication", "mul1@7", :require_bigint_mul1_7_src, :times, " noinline"],
    ["__bigint_mul1_8_raw", "__w_bigint_mul1_8_src", "multiplication", "mul1@8", :require_bigint_mul1_8_src, :times, " noinline"],
    ["__bigint_mul1_16_raw", "__w_bigint_mul1_16_src", "multiplication", "mul1@16", :require_bigint_mul1_16_src, :times, " alwaysinline"],
    ["__bigint_mul1_24_raw", "__w_bigint_mul1_24_src", "multiplication", "mul1@24", :require_bigint_mul1_24_src, :times, " alwaysinline"],
    ["__bigint_mul1_32_raw", "__w_bigint_mul1_32_src", "multiplication", "mul1@32", :require_bigint_mul1_32_src, :times, " alwaysinline"],
    ["__bigint_mul1_40_raw", "__w_bigint_mul1_40_src", "multiplication", "mul1@40", :require_bigint_mul1_40_src, :times, " alwaysinline"],
    ["__bigint_mul1_48_raw", "__w_bigint_mul1_48_src", "multiplication", "mul1@48", :require_bigint_mul1_48_src, :times, " alwaysinline"],
    ["__bigint_mul1_64_raw", "__w_bigint_mul1_64_src", "multiplication", "mul1@64", :require_bigint_mul1_64_src, :times, " alwaysinline"]
  ]
  bigint_exact_seams_cache[:rows] = rows
  rows

-> emit_bigint_exact_seams(mod, fn_out, known_fns, used_runtime_fns, seam_decls, bigint_minus_reopened_fn, bigint_times_reopened_fn)
  bigint_core_loaded = false
  raw_fn_by_method = {}
  raw_count_by_method = {}
  bigint_isqrt_fn = nil

  fns = mod[:functions]
  fi = 0
  fn_count = fns.size()
  while fi < fn_count
    f = fns[fi]
    src_class = f[:source_class]
    src_method = f[:source_method]
    if src_class == "BigInt"
      bigint_core_loaded = true
      if f[:source_kind] == :method && src_method == "isqrt" && f[:overload_dispatcher] != true
        bigint_isqrt_fn = f
    elsif src_class == nil && src_method != nil && src_method.starts_with?("__bigint_")
      prev_count = raw_count_by_method[src_method]
      raw_count_by_method[src_method] = (prev_count == nil ? 0 : prev_count) + 1
      raw_fn_by_method[src_method] = f
    fi += 1

  seams = bigint_binary_exact_seams()
  si = 0
  seam_count = seams.size()
  while si < seam_count
    entry = seams[si]
    raw_helper = entry[0]
    seam_name = entry[1]
    category_noun = entry[2]
    label = entry[3]
    require_key = entry[4]
    reopened_kind = entry[5]
    inline_attr = entry[6]

    matches = raw_count_by_method[raw_helper]
    if matches != nil && matches > 1
      << "error: " + raw_helper + " is reserved for native BigInt " + category_noun
      exit(1)
    helper_fn = raw_fn_by_method[raw_helper]
    if bigint_core_loaded && mod[require_key] == true && helper_fn == nil
      << "error: required native BigInt " + label + " helper is missing; " + seam_name + " would bind the weak C bootstrap default"
      exit(1)

    reopened_fn = reopened_kind == :minus ? bigint_minus_reopened_fn : bigint_times_reopened_fn
    target = reopened_fn != nil ? reopened_fn : helper_fn
    if target != nil
      signature_ok = target[:params] != nil && target[:params].size() == 2
      if reopened_fn == nil
        signature_ok = signature_ok && target[:source_kind] == :fn_def
        signature_ok = signature_ok && target[:raw_i64_signature] == true
        signature_ok = signature_ok && target[:raw_return_type] == :i64
      if !signature_ok
        << "error: invalid native BigInt " + label + " seam target"
        exit(1)
      cc = ""
      if target[:call_conv] != nil && target[:call_conv] != ""
        cc = target[:call_conv] + " "
      attrs = " nounwind"
      if reopened_fn == nil && inline_attr != ""
        attrs += inline_attr
      fn_out << "define i64 @" + seam_name + "(i64 %a, i64 %b)" + attrs + " {\n"
      fn_out << "  %r = tail call " + cc + "i64 @" + target[:name] + "(i64 %a, i64 %b)\n"
      fn_out << "  ret i64 %r\n"
      fn_out << "}\n\n"
      used_runtime_fns[seam_name] = false
      known_fns[seam_name] = true
    elsif used_runtime_fns[seam_name] == true
      seam_decls << "declare i64 @" + seam_name + "(i64, i64) nounwind\n"

    si += 1

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

  big_compare_matches = raw_count_by_method["__bigint_compare_raw"]
  if big_compare_matches != nil && big_compare_matches > 1
    << "error: __bigint_compare_raw is reserved for the native BigInt comparator"
    exit(1)
  big_compare_fn = raw_fn_by_method["__bigint_compare_raw"]
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
