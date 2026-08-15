# BigInt exact-width source seams selected while assembling an LLVM artifact.

-> emit_bigint_exact_seams(mod, fn_out, known_fns, used_runtime_fns, seam_decls, bigint_minus_reopened_fn, bigint_times_reopened_fn)
  # The exact limb leaves below (sub1/mul1/sqr*/mul*) live in
  # core/numeric/big_int.w itself, unlike the always-injected compare/bitwise
  # support modules. Their strong seams can only exist when BigInt Core source
  # was loaded into this module; a program that never touches BigInt
  # legitimately binds the runtime's weak exact-C defaults instead. Enforce
  # the native-lane invariants only when some BigInt Core method was lowered
  # here -- that still catches a loader/cache regression dropping the lane
  # from a BigInt-bearing build.
  bigint_core_loaded = false
  bclfi = 0
  while bclfi < mod[:functions].size()
    if mod[:functions][bclfi][:source_class] == "BigInt"
      bigint_core_loaded = true
    bclfi += 1

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
  if bigint_core_loaded && mod[:require_bigint_sub1_1_src] == true && bigint_sub1_1_fn == nil
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
  if bigint_core_loaded && mod[:require_bigint_sub1_2_src] == true && bigint_sub1_2_fn == nil
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
  if bigint_core_loaded && mod[:require_bigint_mul1_1_src] == true && bigint_mul1_1_fn == nil
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
  if bigint_core_loaded && mod[:require_bigint_sqr2_src] == true && bigint_sqr2_fn == nil
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
  if bigint_core_loaded && mod[:require_bigint_sqr3_src] == true && bigint_sqr3_fn == nil
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
  if bigint_core_loaded && mod[:require_bigint_sqr4_src] == true && bigint_sqr4_fn == nil
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
  if bigint_core_loaded && mod[:require_bigint_sqr5_src] == true && bigint_sqr5_fn == nil
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
  if bigint_core_loaded && mod[:require_bigint_sqr6_src] == true && bigint_sqr6_fn == nil
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
  if bigint_core_loaded && mod[:require_bigint_sqr7_src] == true && bigint_sqr7_fn == nil
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
  if bigint_core_loaded && mod[:require_bigint_sqr8_src] == true && bigint_sqr8_fn == nil
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

  # Exact positive sixteen-limb split square. Keep this dedicated C-shaped
  # checkpoint independently reversible and preserve a real BigInt#* reopen.
  bigint_sqr16_fn = nil
  bigint_sqr16_matches = 0
  bs16fi = 0
  while bs16fi < mod[:functions].size()
    bs16ff = mod[:functions][bs16fi]
    if bs16ff[:source_class] == nil && bs16ff[:source_method] == "__bigint_sqr16_raw"
      bigint_sqr16_matches += 1
      bigint_sqr16_fn = bs16ff
    bs16fi += 1
  if bigint_sqr16_matches > 1
    << "error: __bigint_sqr16_raw is reserved for native BigInt squaring"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_sqr16_src] == true && bigint_sqr16_fn == nil
    << "error: required native BigInt sqr@16 helper is missing; __w_bigint_sqr16_src would bind the weak C bootstrap default"
    exit(1)
  bigint_sqr16_target = bigint_times_reopened_fn
  if bigint_sqr16_target == nil
    bigint_sqr16_target = bigint_sqr16_fn
  if bigint_sqr16_target != nil
    bs16_signature_ok = bigint_sqr16_target[:params] != nil && bigint_sqr16_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bs16_signature_ok = bs16_signature_ok && bigint_sqr16_target[:source_kind] == :fn_def
      bs16_signature_ok = bs16_signature_ok && bigint_sqr16_target[:raw_i64_signature] == true
      bs16_signature_ok = bs16_signature_ok && bigint_sqr16_target[:raw_return_type] == :i64
    if !bs16_signature_ok
      << "error: invalid native BigInt sqr@16 seam target"
      exit(1)
    bs16_cc = ""
    if bigint_sqr16_target[:call_conv] != nil && bigint_sqr16_target[:call_conv] != ""
      bs16_cc = bigint_sqr16_target[:call_conv] + " "
    bs16_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bs16_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_sqr16_src(i64 %a, i64 %b)" + bs16_attrs + " {\n"
    fn_out << "  %r = tail call " + bs16_cc + "i64 @" + bigint_sqr16_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_sqr16_src"] = false
    known_fns["__w_bigint_sqr16_src"] = true
  elsif used_runtime_fns["__w_bigint_sqr16_src"] == true
    seam_decls << "declare i64 @__w_bigint_sqr16_src(i64, i64) nounwind\n"

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
  if bigint_core_loaded && mod[:require_bigint_mul2_src] == true && bigint_mul2_fn == nil
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

  # Exact distinct positive three-by-three-limb multiplication follows the
  # same reserved/open-world contract as the adjacent two-limb checkpoint.
  bigint_mul3_fn = nil
  bigint_mul3_matches = 0
  be3fi = 0
  while be3fi < mod[:functions].size()
    be3ff = mod[:functions][be3fi]
    if be3ff[:source_class] == nil && be3ff[:source_method] == "__bigint_mul3_raw"
      bigint_mul3_matches += 1
      bigint_mul3_fn = be3ff
    be3fi += 1
  if bigint_mul3_matches > 1
    << "error: __bigint_mul3_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul3_src] == true && bigint_mul3_fn == nil
    << "error: required native BigInt mul@3 helper is missing; __w_bigint_mul3_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul3_target = bigint_times_reopened_fn
  if bigint_mul3_target == nil
    bigint_mul3_target = bigint_mul3_fn
  if bigint_mul3_target != nil
    be3_signature_ok = bigint_mul3_target[:params] != nil && bigint_mul3_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      be3_signature_ok = be3_signature_ok && bigint_mul3_target[:source_kind] == :fn_def
      be3_signature_ok = be3_signature_ok && bigint_mul3_target[:raw_i64_signature] == true
      be3_signature_ok = be3_signature_ok && bigint_mul3_target[:raw_return_type] == :i64
    if !be3_signature_ok
      << "error: invalid native BigInt mul@3 seam target"
      exit(1)
    be3_cc = ""
    if bigint_mul3_target[:call_conv] != nil && bigint_mul3_target[:call_conv] != ""
      be3_cc = bigint_mul3_target[:call_conv] + " "
    be3_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      be3_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul3_src(i64 %a, i64 %b)" + be3_attrs + " {\n"
    fn_out << "  %r = tail call " + be3_cc + "i64 @" + bigint_mul3_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul3_src"] = false
    known_fns["__w_bigint_mul3_src"] = true
  elsif used_runtime_fns["__w_bigint_mul3_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul3_src(i64, i64) nounwind\n"

  # Exact distinct positive four-by-four-limb multiplication keeps C's tuned
  # row-zero mul_1 call and literal inlined addmul remainder behind the same
  # reserved/open-world contract as the adjacent fixed checkpoints.
  bigint_mul4_fn = nil
  bigint_mul4_matches = 0
  be4fi = 0
  while be4fi < mod[:functions].size()
    be4ff = mod[:functions][be4fi]
    if be4ff[:source_class] == nil && be4ff[:source_method] == "__bigint_mul4_raw"
      bigint_mul4_matches += 1
      bigint_mul4_fn = be4ff
    be4fi += 1
  if bigint_mul4_matches > 1
    << "error: __bigint_mul4_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul4_src] == true && bigint_mul4_fn == nil
    << "error: required native BigInt mul@4 helper is missing; __w_bigint_mul4_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul4_target = bigint_times_reopened_fn
  if bigint_mul4_target == nil
    bigint_mul4_target = bigint_mul4_fn
  if bigint_mul4_target != nil
    be4_signature_ok = bigint_mul4_target[:params] != nil && bigint_mul4_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      be4_signature_ok = be4_signature_ok && bigint_mul4_target[:source_kind] == :fn_def
      be4_signature_ok = be4_signature_ok && bigint_mul4_target[:raw_i64_signature] == true
      be4_signature_ok = be4_signature_ok && bigint_mul4_target[:raw_return_type] == :i64
    if !be4_signature_ok
      << "error: invalid native BigInt mul@4 seam target"
      exit(1)
    be4_cc = ""
    if bigint_mul4_target[:call_conv] != nil && bigint_mul4_target[:call_conv] != ""
      be4_cc = bigint_mul4_target[:call_conv] + " "
    be4_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      be4_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul4_src(i64 %a, i64 %b)" + be4_attrs + " {\n"
    fn_out << "  %r = tail call " + be4_cc + "i64 @" + bigint_mul4_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul4_src"] = false
    known_fns["__w_bigint_mul4_src"] = true
  elsif used_runtime_fns["__w_bigint_mul4_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul4_src(i64, i64) nounwind\n"

  # Exact distinct positive five-by-five-limb multiplication keeps C's tuned
  # mul_1/addmul_1 row primitives and literal schoolbook row order behind the
  # same reserved/open-world contract as the adjacent fixed checkpoints.
  bigint_mul5_fn = nil
  bigint_mul5_matches = 0
  be5fi = 0
  while be5fi < mod[:functions].size()
    be5ff = mod[:functions][be5fi]
    if be5ff[:source_class] == nil && be5ff[:source_method] == "__bigint_mul5_raw"
      bigint_mul5_matches += 1
      bigint_mul5_fn = be5ff
    be5fi += 1
  if bigint_mul5_matches > 1
    << "error: __bigint_mul5_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul5_src] == true && bigint_mul5_fn == nil
    << "error: required native BigInt mul@5 helper is missing; __w_bigint_mul5_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul5_target = bigint_times_reopened_fn
  if bigint_mul5_target == nil
    bigint_mul5_target = bigint_mul5_fn
  if bigint_mul5_target != nil
    be5_signature_ok = bigint_mul5_target[:params] != nil && bigint_mul5_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      be5_signature_ok = be5_signature_ok && bigint_mul5_target[:source_kind] == :fn_def
      be5_signature_ok = be5_signature_ok && bigint_mul5_target[:raw_i64_signature] == true
      be5_signature_ok = be5_signature_ok && bigint_mul5_target[:raw_return_type] == :i64
    if !be5_signature_ok
      << "error: invalid native BigInt mul@5 seam target"
      exit(1)
    be5_cc = ""
    if bigint_mul5_target[:call_conv] != nil && bigint_mul5_target[:call_conv] != ""
      be5_cc = bigint_mul5_target[:call_conv] + " "
    be5_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      be5_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul5_src(i64 %a, i64 %b)" + be5_attrs + " {\n"
    fn_out << "  %r = tail call " + be5_cc + "i64 @" + bigint_mul5_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul5_src"] = false
    known_fns["__w_bigint_mul5_src"] = true
  elsif used_runtime_fns["__w_bigint_mul5_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul5_src(i64, i64) nounwind\n"

  # Exact distinct positive six-by-six-limb multiplication keeps C's tuned
  # mul_1/addmul_1 row primitives and literal schoolbook row order behind the
  # same reserved/open-world contract as the adjacent fixed checkpoints.
  bigint_mul6_fn = nil
  bigint_mul6_matches = 0
  be6fi = 0
  while be6fi < mod[:functions].size()
    be6ff = mod[:functions][be6fi]
    if be6ff[:source_class] == nil && be6ff[:source_method] == "__bigint_mul6_raw"
      bigint_mul6_matches += 1
      bigint_mul6_fn = be6ff
    be6fi += 1
  if bigint_mul6_matches > 1
    << "error: __bigint_mul6_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul6_src] == true && bigint_mul6_fn == nil
    << "error: required native BigInt mul@6 helper is missing; __w_bigint_mul6_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul6_target = bigint_times_reopened_fn
  if bigint_mul6_target == nil
    bigint_mul6_target = bigint_mul6_fn
  if bigint_mul6_target != nil
    be6_signature_ok = bigint_mul6_target[:params] != nil && bigint_mul6_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      be6_signature_ok = be6_signature_ok && bigint_mul6_target[:source_kind] == :fn_def
      be6_signature_ok = be6_signature_ok && bigint_mul6_target[:raw_i64_signature] == true
      be6_signature_ok = be6_signature_ok && bigint_mul6_target[:raw_return_type] == :i64
    if !be6_signature_ok
      << "error: invalid native BigInt mul@6 seam target"
      exit(1)
    be6_cc = ""
    if bigint_mul6_target[:call_conv] != nil && bigint_mul6_target[:call_conv] != ""
      be6_cc = bigint_mul6_target[:call_conv] + " "
    be6_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      be6_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul6_src(i64 %a, i64 %b)" + be6_attrs + " {\n"
    fn_out << "  %r = tail call " + be6_cc + "i64 @" + bigint_mul6_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul6_src"] = false
    known_fns["__w_bigint_mul6_src"] = true
  elsif used_runtime_fns["__w_bigint_mul6_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul6_src(i64, i64) nounwind\n"

  # Exact distinct positive seven-by-seven-limb multiplication keeps C's
  # tuned mul_1/addmul_1 row primitives and literal schoolbook row order
  # behind the adjacent reserved/open-world contracts.
  bigint_mul7_fn = nil
  bigint_mul7_matches = 0
  be7fi = 0
  while be7fi < mod[:functions].size()
    be7ff = mod[:functions][be7fi]
    if be7ff[:source_class] == nil && be7ff[:source_method] == "__bigint_mul7_raw"
      bigint_mul7_matches += 1
      bigint_mul7_fn = be7ff
    be7fi += 1
  if bigint_mul7_matches > 1
    << "error: __bigint_mul7_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul7_src] == true && bigint_mul7_fn == nil
    << "error: required native BigInt mul@7 helper is missing; __w_bigint_mul7_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul7_target = bigint_times_reopened_fn
  if bigint_mul7_target == nil
    bigint_mul7_target = bigint_mul7_fn
  if bigint_mul7_target != nil
    be7_signature_ok = bigint_mul7_target[:params] != nil && bigint_mul7_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      be7_signature_ok = be7_signature_ok && bigint_mul7_target[:source_kind] == :fn_def
      be7_signature_ok = be7_signature_ok && bigint_mul7_target[:raw_i64_signature] == true
      be7_signature_ok = be7_signature_ok && bigint_mul7_target[:raw_return_type] == :i64
    if !be7_signature_ok
      << "error: invalid native BigInt mul@7 seam target"
      exit(1)
    be7_cc = ""
    if bigint_mul7_target[:call_conv] != nil && bigint_mul7_target[:call_conv] != ""
      be7_cc = bigint_mul7_target[:call_conv] + " "
    be7_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      be7_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul7_src(i64 %a, i64 %b)" + be7_attrs + " {\n"
    fn_out << "  %r = tail call " + be7_cc + "i64 @" + bigint_mul7_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul7_src"] = false
    known_fns["__w_bigint_mul7_src"] = true
  elsif used_runtime_fns["__w_bigint_mul7_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul7_src(i64, i64) nounwind\n"

  # Exact distinct positive eight-by-eight-limb multiplication keeps C's
  # fixed bn_mul_eq8_inline decomposition behind the adjacent reserved and
  # open-world contracts.
  bigint_mul8_fn = nil
  bigint_mul8_matches = 0
  be8fi = 0
  while be8fi < mod[:functions].size()
    be8ff = mod[:functions][be8fi]
    if be8ff[:source_class] == nil && be8ff[:source_method] == "__bigint_mul8_raw"
      bigint_mul8_matches += 1
      bigint_mul8_fn = be8ff
    be8fi += 1
  if bigint_mul8_matches > 1
    << "error: __bigint_mul8_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul8_src] == true && bigint_mul8_fn == nil
    << "error: required native BigInt mul@8 helper is missing; __w_bigint_mul8_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul8_target = bigint_times_reopened_fn
  if bigint_mul8_target == nil
    bigint_mul8_target = bigint_mul8_fn
  if bigint_mul8_target != nil
    be8_signature_ok = bigint_mul8_target[:params] != nil && bigint_mul8_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      be8_signature_ok = be8_signature_ok && bigint_mul8_target[:source_kind] == :fn_def
      be8_signature_ok = be8_signature_ok && bigint_mul8_target[:raw_i64_signature] == true
      be8_signature_ok = be8_signature_ok && bigint_mul8_target[:raw_return_type] == :i64
    if !be8_signature_ok
      << "error: invalid native BigInt mul@8 seam target"
      exit(1)
    be8_cc = ""
    if bigint_mul8_target[:call_conv] != nil && bigint_mul8_target[:call_conv] != ""
      be8_cc = bigint_mul8_target[:call_conv] + " "
    be8_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      be8_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul8_src(i64 %a, i64 %b)" + be8_attrs + " {\n"
    fn_out << "  %r = tail call " + be8_cc + "i64 @" + bigint_mul8_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul8_src"] = false
    known_fns["__w_bigint_mul8_src"] = true
  elsif used_runtime_fns["__w_bigint_mul8_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul8_src(i64, i64) nounwind\n"

  # Exact distinct positive twelve-by-twelve-limb multiplication keeps C's
  # fixed bn_mul_eq12 leaf behind the adjacent reserved and open-world
  # contracts.
  bigint_mul12_fn = nil
  bigint_mul12_matches = 0
  be12fi = 0
  while be12fi < mod[:functions].size()
    be12ff = mod[:functions][be12fi]
    if be12ff[:source_class] == nil && be12ff[:source_method] == "__bigint_mul12_raw"
      bigint_mul12_matches += 1
      bigint_mul12_fn = be12ff
    be12fi += 1
  if bigint_mul12_matches > 1
    << "error: __bigint_mul12_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul12_src] == true && bigint_mul12_fn == nil
    << "error: required native BigInt mul@12 helper is missing; __w_bigint_mul12_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul12_target = bigint_times_reopened_fn
  if bigint_mul12_target == nil
    bigint_mul12_target = bigint_mul12_fn
  if bigint_mul12_target != nil
    be12_signature_ok = bigint_mul12_target[:params] != nil && bigint_mul12_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      be12_signature_ok = be12_signature_ok && bigint_mul12_target[:source_kind] == :fn_def
      be12_signature_ok = be12_signature_ok && bigint_mul12_target[:raw_i64_signature] == true
      be12_signature_ok = be12_signature_ok && bigint_mul12_target[:raw_return_type] == :i64
    if !be12_signature_ok
      << "error: invalid native BigInt mul@12 seam target"
      exit(1)
    be12_cc = ""
    if bigint_mul12_target[:call_conv] != nil && bigint_mul12_target[:call_conv] != ""
      be12_cc = bigint_mul12_target[:call_conv] + " "
    be12_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      be12_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul12_src(i64 %a, i64 %b)" + be12_attrs + " {\n"
    fn_out << "  %r = tail call " + be12_cc + "i64 @" + bigint_mul12_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul12_src"] = false
    known_fns["__w_bigint_mul12_src"] = true
  elsif used_runtime_fns["__w_bigint_mul12_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul12_src(i64, i64) nounwind\n"

  # Exact distinct positive fifteen-by-fifteen-limb multiplication keeps C's
  # fixed bn_mul_eq15 leaf behind the adjacent reserved and open-world
  # contracts.
  bigint_mul15_fn = nil
  bigint_mul15_matches = 0
  be15fi = 0
  while be15fi < mod[:functions].size()
    be15ff = mod[:functions][be15fi]
    if be15ff[:source_class] == nil && be15ff[:source_method] == "__bigint_mul15_raw"
      bigint_mul15_matches += 1
      bigint_mul15_fn = be15ff
    be15fi += 1
  if bigint_mul15_matches > 1
    << "error: __bigint_mul15_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul15_src] == true && bigint_mul15_fn == nil
    << "error: required native BigInt mul@15 helper is missing; __w_bigint_mul15_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul15_target = bigint_times_reopened_fn
  if bigint_mul15_target == nil
    bigint_mul15_target = bigint_mul15_fn
  if bigint_mul15_target != nil
    be15_signature_ok = bigint_mul15_target[:params] != nil && bigint_mul15_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      be15_signature_ok = be15_signature_ok && bigint_mul15_target[:source_kind] == :fn_def
      be15_signature_ok = be15_signature_ok && bigint_mul15_target[:raw_i64_signature] == true
      be15_signature_ok = be15_signature_ok && bigint_mul15_target[:raw_return_type] == :i64
    if !be15_signature_ok
      << "error: invalid native BigInt mul@15 seam target"
      exit(1)
    be15_cc = ""
    if bigint_mul15_target[:call_conv] != nil && bigint_mul15_target[:call_conv] != ""
      be15_cc = bigint_mul15_target[:call_conv] + " "
    be15_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      be15_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul15_src(i64 %a, i64 %b)" + be15_attrs + " {\n"
    fn_out << "  %r = tail call " + be15_cc + "i64 @" + bigint_mul15_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul15_src"] = false
    known_fns["__w_bigint_mul15_src"] = true
  elsif used_runtime_fns["__w_bigint_mul15_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul15_src(i64, i64) nounwind\n"

  # Exact distinct positive sixteen-by-sixteen-limb multiplication keeps C's
  # fixed bn_mul_eq16 leaf behind the adjacent reserved and open-world
  # contracts.
  bigint_mul16_fn = nil
  bigint_mul16_matches = 0
  be16fi = 0
  while be16fi < mod[:functions].size()
    be16ff = mod[:functions][be16fi]
    if be16ff[:source_class] == nil && be16ff[:source_method] == "__bigint_mul16_raw"
      bigint_mul16_matches += 1
      bigint_mul16_fn = be16ff
    be16fi += 1
  if bigint_mul16_matches > 1
    << "error: __bigint_mul16_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul16_src] == true && bigint_mul16_fn == nil
    << "error: required native BigInt mul@16 helper is missing; __w_bigint_mul16_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul16_target = bigint_times_reopened_fn
  if bigint_mul16_target == nil
    bigint_mul16_target = bigint_mul16_fn
  if bigint_mul16_target != nil
    be16_signature_ok = bigint_mul16_target[:params] != nil && bigint_mul16_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      be16_signature_ok = be16_signature_ok && bigint_mul16_target[:source_kind] == :fn_def
      be16_signature_ok = be16_signature_ok && bigint_mul16_target[:raw_i64_signature] == true
      be16_signature_ok = be16_signature_ok && bigint_mul16_target[:raw_return_type] == :i64
    if !be16_signature_ok
      << "error: invalid native BigInt mul@16 seam target"
      exit(1)
    be16_cc = ""
    if bigint_mul16_target[:call_conv] != nil && bigint_mul16_target[:call_conv] != ""
      be16_cc = bigint_mul16_target[:call_conv] + " "
    be16_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      be16_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul16_src(i64 %a, i64 %b)" + be16_attrs + " {\n"
    fn_out << "  %r = tail call " + be16_cc + "i64 @" + bigint_mul16_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul16_src"] = false
    known_fns["__w_bigint_mul16_src"] = true
  elsif used_runtime_fns["__w_bigint_mul16_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul16_src(i64, i64) nounwind\n"

  # Exact distinct positive seventeen-by-seventeen-limb multiplication keeps
  # C's fixed bn_mul_eq17 leaf behind the adjacent reserved and open-world
  # contracts.
  bigint_mul17_fn = nil
  bigint_mul17_matches = 0
  be17fi = 0
  while be17fi < mod[:functions].size()
    be17ff = mod[:functions][be17fi]
    if be17ff[:source_class] == nil && be17ff[:source_method] == "__bigint_mul17_raw"
      bigint_mul17_matches += 1
      bigint_mul17_fn = be17ff
    be17fi += 1
  if bigint_mul17_matches > 1
    << "error: __bigint_mul17_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul17_src] == true && bigint_mul17_fn == nil
    << "error: required native BigInt mul@17 helper is missing; __w_bigint_mul17_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul17_target = bigint_times_reopened_fn
  if bigint_mul17_target == nil
    bigint_mul17_target = bigint_mul17_fn
  if bigint_mul17_target != nil
    be17_signature_ok = bigint_mul17_target[:params] != nil && bigint_mul17_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      be17_signature_ok = be17_signature_ok && bigint_mul17_target[:source_kind] == :fn_def
      be17_signature_ok = be17_signature_ok && bigint_mul17_target[:raw_i64_signature] == true
      be17_signature_ok = be17_signature_ok && bigint_mul17_target[:raw_return_type] == :i64
    if !be17_signature_ok
      << "error: invalid native BigInt mul@17 seam target"
      exit(1)
    be17_cc = ""
    if bigint_mul17_target[:call_conv] != nil && bigint_mul17_target[:call_conv] != ""
      be17_cc = bigint_mul17_target[:call_conv] + " "
    be17_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      be17_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul17_src(i64 %a, i64 %b)" + be17_attrs + " {\n"
    fn_out << "  %r = tail call " + be17_cc + "i64 @" + bigint_mul17_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul17_src"] = false
    known_fns["__w_bigint_mul17_src"] = true
  elsif used_runtime_fns["__w_bigint_mul17_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul17_src(i64, i64) nounwind\n"

  # Exact distinct positive twenty-one-by-twenty-one-limb multiplication keeps
  # C's fixed bn_mul_eq21 leaf behind the adjacent reserved and open-world
  # contracts.
  bigint_mul21_fn = nil
  bigint_mul21_matches = 0
  be21fi = 0
  while be21fi < mod[:functions].size()
    be21ff = mod[:functions][be21fi]
    if be21ff[:source_class] == nil && be21ff[:source_method] == "__bigint_mul21_raw"
      bigint_mul21_matches += 1
      bigint_mul21_fn = be21ff
    be21fi += 1
  if bigint_mul21_matches > 1
    << "error: __bigint_mul21_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul21_src] == true && bigint_mul21_fn == nil
    << "error: required native BigInt mul@21 helper is missing; __w_bigint_mul21_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul21_target = bigint_times_reopened_fn
  if bigint_mul21_target == nil
    bigint_mul21_target = bigint_mul21_fn
  if bigint_mul21_target != nil
    be21_signature_ok = bigint_mul21_target[:params] != nil && bigint_mul21_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      be21_signature_ok = be21_signature_ok && bigint_mul21_target[:source_kind] == :fn_def
      be21_signature_ok = be21_signature_ok && bigint_mul21_target[:raw_i64_signature] == true
      be21_signature_ok = be21_signature_ok && bigint_mul21_target[:raw_return_type] == :i64
    if !be21_signature_ok
      << "error: invalid native BigInt mul@21 seam target"
      exit(1)
    be21_cc = ""
    if bigint_mul21_target[:call_conv] != nil && bigint_mul21_target[:call_conv] != ""
      be21_cc = bigint_mul21_target[:call_conv] + " "
    be21_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      be21_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul21_src(i64 %a, i64 %b)" + be21_attrs + " {\n"
    fn_out << "  %r = tail call " + be21_cc + "i64 @" + bigint_mul21_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul21_src"] = false
    known_fns["__w_bigint_mul21_src"] = true
  elsif used_runtime_fns["__w_bigint_mul21_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul21_src(i64, i64) nounwind\n"

  # Exact distinct positive twenty-four-by-twenty-four-limb multiplication
  # keeps C's selected top-level difference-form leaf behind the adjacent
  # reserved and open-world contracts.
  bigint_mul24_fn = nil
  bigint_mul24_matches = 0
  be24fi = 0
  while be24fi < mod[:functions].size()
    be24ff = mod[:functions][be24fi]
    if be24ff[:source_class] == nil && be24ff[:source_method] == "__bigint_mul24_raw"
      bigint_mul24_matches += 1
      bigint_mul24_fn = be24ff
    be24fi += 1
  if bigint_mul24_matches > 1
    << "error: __bigint_mul24_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul24_src] == true && bigint_mul24_fn == nil
    << "error: required native BigInt mul@24 helper is missing; __w_bigint_mul24_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul24_target = bigint_times_reopened_fn
  if bigint_mul24_target == nil
    bigint_mul24_target = bigint_mul24_fn
  if bigint_mul24_target != nil
    be24_signature_ok = bigint_mul24_target[:params] != nil && bigint_mul24_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      be24_signature_ok = be24_signature_ok && bigint_mul24_target[:source_kind] == :fn_def
      be24_signature_ok = be24_signature_ok && bigint_mul24_target[:raw_i64_signature] == true
      be24_signature_ok = be24_signature_ok && bigint_mul24_target[:raw_return_type] == :i64
    if !be24_signature_ok
      << "error: invalid native BigInt mul@24 seam target"
      exit(1)
    be24_cc = ""
    if bigint_mul24_target[:call_conv] != nil && bigint_mul24_target[:call_conv] != ""
      be24_cc = bigint_mul24_target[:call_conv] + " "
    be24_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      be24_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul24_src(i64 %a, i64 %b)" + be24_attrs + " {\n"
    fn_out << "  %r = tail call " + be24_cc + "i64 @" + bigint_mul24_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul24_src"] = false
    known_fns["__w_bigint_mul24_src"] = true
  elsif used_runtime_fns["__w_bigint_mul24_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul24_src(i64, i64) nounwind\n"

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
  if bigint_core_loaded && mod[:require_bigint_mul1_2_src] == true && bigint_mul1_2_fn == nil
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
  if bigint_core_loaded && mod[:require_bigint_mul1_3_src] == true && bigint_mul1_3_fn == nil
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
  if bigint_core_loaded && mod[:require_bigint_mul1_4_src] == true && bigint_mul1_4_fn == nil
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
  if bigint_core_loaded && mod[:require_bigint_mul1_5_src] == true && bigint_mul1_5_fn == nil
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
  if bigint_core_loaded && mod[:require_bigint_mul1_6_src] == true && bigint_mul1_6_fn == nil
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
  if bigint_core_loaded && mod[:require_bigint_mul1_7_src] == true && bigint_mul1_7_fn == nil
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
  if bigint_core_loaded && mod[:require_bigint_mul1_8_src] == true && bigint_mul1_8_fn == nil
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

  # Exact positive 16-by-1 multiplication owns C's cap-32 allocation and
  # fixed scalar kernel behind an independently reversible stable seam.
  bigint_mul1_16_fn = nil
  bigint_mul1_16_matches = 0
  bm16fi = 0
  while bm16fi < mod[:functions].size()
    bm16ff = mod[:functions][bm16fi]
    if bm16ff[:source_class] == nil && bm16ff[:source_method] == "__bigint_mul1_16_raw"
      bigint_mul1_16_matches += 1
      bigint_mul1_16_fn = bm16ff
    bm16fi += 1
  if bigint_mul1_16_matches > 1
    << "error: __bigint_mul1_16_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul1_16_src] == true && bigint_mul1_16_fn == nil
    << "error: required native BigInt mul1@16 helper is missing; __w_bigint_mul1_16_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul1_16_target = bigint_times_reopened_fn
  if bigint_mul1_16_target == nil
    bigint_mul1_16_target = bigint_mul1_16_fn
  if bigint_mul1_16_target != nil
    bm16_signature_ok = bigint_mul1_16_target[:params] != nil && bigint_mul1_16_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bm16_signature_ok = bm16_signature_ok && bigint_mul1_16_target[:source_kind] == :fn_def
      bm16_signature_ok = bm16_signature_ok && bigint_mul1_16_target[:raw_i64_signature] == true
      bm16_signature_ok = bm16_signature_ok && bigint_mul1_16_target[:raw_return_type] == :i64
    if !bm16_signature_ok
      << "error: invalid native BigInt mul1@16 seam target"
      exit(1)
    bm16_cc = ""
    if bigint_mul1_16_target[:call_conv] != nil && bigint_mul1_16_target[:call_conv] != ""
      bm16_cc = bigint_mul1_16_target[:call_conv] + " "
    bm16_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bm16_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul1_16_src(i64 %a, i64 %b)" + bm16_attrs + " {\n"
    fn_out << "  %r = tail call " + bm16_cc + "i64 @" + bigint_mul1_16_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul1_16_src"] = false
    known_fns["__w_bigint_mul1_16_src"] = true
  elsif used_runtime_fns["__w_bigint_mul1_16_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul1_16_src(i64, i64) nounwind\n"

  # Exact positive 24-by-1 multiplication owns C's cap-32 allocation and
  # fixed scalar kernel behind an independently reversible stable seam.
  bigint_mul1_24_fn = nil
  bigint_mul1_24_matches = 0
  bm24fi = 0
  while bm24fi < mod[:functions].size()
    bm24ff = mod[:functions][bm24fi]
    if bm24ff[:source_class] == nil && bm24ff[:source_method] == "__bigint_mul1_24_raw"
      bigint_mul1_24_matches += 1
      bigint_mul1_24_fn = bm24ff
    bm24fi += 1
  if bigint_mul1_24_matches > 1
    << "error: __bigint_mul1_24_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul1_24_src] == true && bigint_mul1_24_fn == nil
    << "error: required native BigInt mul1@24 helper is missing; __w_bigint_mul1_24_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul1_24_target = bigint_times_reopened_fn
  if bigint_mul1_24_target == nil
    bigint_mul1_24_target = bigint_mul1_24_fn
  if bigint_mul1_24_target != nil
    bm24_signature_ok = bigint_mul1_24_target[:params] != nil && bigint_mul1_24_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bm24_signature_ok = bm24_signature_ok && bigint_mul1_24_target[:source_kind] == :fn_def
      bm24_signature_ok = bm24_signature_ok && bigint_mul1_24_target[:raw_i64_signature] == true
      bm24_signature_ok = bm24_signature_ok && bigint_mul1_24_target[:raw_return_type] == :i64
    if !bm24_signature_ok
      << "error: invalid native BigInt mul1@24 seam target"
      exit(1)
    bm24_cc = ""
    if bigint_mul1_24_target[:call_conv] != nil && bigint_mul1_24_target[:call_conv] != ""
      bm24_cc = bigint_mul1_24_target[:call_conv] + " "
    bm24_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bm24_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul1_24_src(i64 %a, i64 %b)" + bm24_attrs + " {\n"
    fn_out << "  %r = tail call " + bm24_cc + "i64 @" + bigint_mul1_24_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul1_24_src"] = false
    known_fns["__w_bigint_mul1_24_src"] = true
  elsif used_runtime_fns["__w_bigint_mul1_24_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul1_24_src(i64, i64) nounwind\n"

  # Exact positive 32-by-1 multiplication owns C's cap-64 allocation and
  # fixed scalar kernel behind an independently reversible stable seam.
  bigint_mul1_32_fn = nil
  bigint_mul1_32_matches = 0
  bm32fi = 0
  while bm32fi < mod[:functions].size()
    bm32ff = mod[:functions][bm32fi]
    if bm32ff[:source_class] == nil && bm32ff[:source_method] == "__bigint_mul1_32_raw"
      bigint_mul1_32_matches += 1
      bigint_mul1_32_fn = bm32ff
    bm32fi += 1
  if bigint_mul1_32_matches > 1
    << "error: __bigint_mul1_32_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul1_32_src] == true && bigint_mul1_32_fn == nil
    << "error: required native BigInt mul1@32 helper is missing; __w_bigint_mul1_32_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul1_32_target = bigint_times_reopened_fn
  if bigint_mul1_32_target == nil
    bigint_mul1_32_target = bigint_mul1_32_fn
  if bigint_mul1_32_target != nil
    bm32_signature_ok = bigint_mul1_32_target[:params] != nil && bigint_mul1_32_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bm32_signature_ok = bm32_signature_ok && bigint_mul1_32_target[:source_kind] == :fn_def
      bm32_signature_ok = bm32_signature_ok && bigint_mul1_32_target[:raw_i64_signature] == true
      bm32_signature_ok = bm32_signature_ok && bigint_mul1_32_target[:raw_return_type] == :i64
    if !bm32_signature_ok
      << "error: invalid native BigInt mul1@32 seam target"
      exit(1)
    bm32_cc = ""
    if bigint_mul1_32_target[:call_conv] != nil && bigint_mul1_32_target[:call_conv] != ""
      bm32_cc = bigint_mul1_32_target[:call_conv] + " "
    bm32_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bm32_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul1_32_src(i64 %a, i64 %b)" + bm32_attrs + " {\n"
    fn_out << "  %r = tail call " + bm32_cc + "i64 @" + bigint_mul1_32_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul1_32_src"] = false
    known_fns["__w_bigint_mul1_32_src"] = true
  elsif used_runtime_fns["__w_bigint_mul1_32_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul1_32_src(i64, i64) nounwind\n"

  # Exact positive 40-by-1 multiplication owns C's cap-64 allocation and
  # fixed scalar kernel behind an independently reversible stable seam.
  bigint_mul1_40_fn = nil
  bigint_mul1_40_matches = 0
  bm40fi = 0
  while bm40fi < mod[:functions].size()
    bm40ff = mod[:functions][bm40fi]
    if bm40ff[:source_class] == nil && bm40ff[:source_method] == "__bigint_mul1_40_raw"
      bigint_mul1_40_matches += 1
      bigint_mul1_40_fn = bm40ff
    bm40fi += 1
  if bigint_mul1_40_matches > 1
    << "error: __bigint_mul1_40_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul1_40_src] == true && bigint_mul1_40_fn == nil
    << "error: required native BigInt mul1@40 helper is missing; __w_bigint_mul1_40_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul1_40_target = bigint_times_reopened_fn
  if bigint_mul1_40_target == nil
    bigint_mul1_40_target = bigint_mul1_40_fn
  if bigint_mul1_40_target != nil
    bm40_signature_ok = bigint_mul1_40_target[:params] != nil && bigint_mul1_40_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bm40_signature_ok = bm40_signature_ok && bigint_mul1_40_target[:source_kind] == :fn_def
      bm40_signature_ok = bm40_signature_ok && bigint_mul1_40_target[:raw_i64_signature] == true
      bm40_signature_ok = bm40_signature_ok && bigint_mul1_40_target[:raw_return_type] == :i64
    if !bm40_signature_ok
      << "error: invalid native BigInt mul1@40 seam target"
      exit(1)
    bm40_cc = ""
    if bigint_mul1_40_target[:call_conv] != nil && bigint_mul1_40_target[:call_conv] != ""
      bm40_cc = bigint_mul1_40_target[:call_conv] + " "
    bm40_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bm40_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul1_40_src(i64 %a, i64 %b)" + bm40_attrs + " {\n"
    fn_out << "  %r = tail call " + bm40_cc + "i64 @" + bigint_mul1_40_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul1_40_src"] = false
    known_fns["__w_bigint_mul1_40_src"] = true
  elsif used_runtime_fns["__w_bigint_mul1_40_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul1_40_src(i64, i64) nounwind\n"

  # Exact positive 48-by-1 multiplication owns C's cap-64 allocation and
  # fixed scalar kernel behind an independently reversible stable seam.
  bigint_mul1_48_fn = nil
  bigint_mul1_48_matches = 0
  bm48fi = 0
  while bm48fi < mod[:functions].size()
    bm48ff = mod[:functions][bm48fi]
    if bm48ff[:source_class] == nil && bm48ff[:source_method] == "__bigint_mul1_48_raw"
      bigint_mul1_48_matches += 1
      bigint_mul1_48_fn = bm48ff
    bm48fi += 1
  if bigint_mul1_48_matches > 1
    << "error: __bigint_mul1_48_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul1_48_src] == true && bigint_mul1_48_fn == nil
    << "error: required native BigInt mul1@48 helper is missing; __w_bigint_mul1_48_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul1_48_target = bigint_times_reopened_fn
  if bigint_mul1_48_target == nil
    bigint_mul1_48_target = bigint_mul1_48_fn
  if bigint_mul1_48_target != nil
    bm48_signature_ok = bigint_mul1_48_target[:params] != nil && bigint_mul1_48_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bm48_signature_ok = bm48_signature_ok && bigint_mul1_48_target[:source_kind] == :fn_def
      bm48_signature_ok = bm48_signature_ok && bigint_mul1_48_target[:raw_i64_signature] == true
      bm48_signature_ok = bm48_signature_ok && bigint_mul1_48_target[:raw_return_type] == :i64
    if !bm48_signature_ok
      << "error: invalid native BigInt mul1@48 seam target"
      exit(1)
    bm48_cc = ""
    if bigint_mul1_48_target[:call_conv] != nil && bigint_mul1_48_target[:call_conv] != ""
      bm48_cc = bigint_mul1_48_target[:call_conv] + " "
    bm48_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bm48_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul1_48_src(i64 %a, i64 %b)" + bm48_attrs + " {\n"
    fn_out << "  %r = tail call " + bm48_cc + "i64 @" + bigint_mul1_48_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul1_48_src"] = false
    known_fns["__w_bigint_mul1_48_src"] = true
  elsif used_runtime_fns["__w_bigint_mul1_48_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul1_48_src(i64, i64) nounwind\n"

  # Exact positive 64-by-1 multiplication owns C's cap-128 allocation and
  # fixed scalar kernel behind an independently reversible stable seam.
  bigint_mul1_64_fn = nil
  bigint_mul1_64_matches = 0
  bm64fi = 0
  while bm64fi < mod[:functions].size()
    bm64ff = mod[:functions][bm64fi]
    if bm64ff[:source_class] == nil && bm64ff[:source_method] == "__bigint_mul1_64_raw"
      bigint_mul1_64_matches += 1
      bigint_mul1_64_fn = bm64ff
    bm64fi += 1
  if bigint_mul1_64_matches > 1
    << "error: __bigint_mul1_64_raw is reserved for native BigInt multiplication"
    exit(1)
  if bigint_core_loaded && mod[:require_bigint_mul1_64_src] == true && bigint_mul1_64_fn == nil
    << "error: required native BigInt mul1@64 helper is missing; __w_bigint_mul1_64_src would bind the weak C bootstrap default"
    exit(1)
  bigint_mul1_64_target = bigint_times_reopened_fn
  if bigint_mul1_64_target == nil
    bigint_mul1_64_target = bigint_mul1_64_fn
  if bigint_mul1_64_target != nil
    bm64_signature_ok = bigint_mul1_64_target[:params] != nil && bigint_mul1_64_target[:params].size() == 2
    if bigint_times_reopened_fn == nil
      bm64_signature_ok = bm64_signature_ok && bigint_mul1_64_target[:source_kind] == :fn_def
      bm64_signature_ok = bm64_signature_ok && bigint_mul1_64_target[:raw_i64_signature] == true
      bm64_signature_ok = bm64_signature_ok && bigint_mul1_64_target[:raw_return_type] == :i64
    if !bm64_signature_ok
      << "error: invalid native BigInt mul1@64 seam target"
      exit(1)
    bm64_cc = ""
    if bigint_mul1_64_target[:call_conv] != nil && bigint_mul1_64_target[:call_conv] != ""
      bm64_cc = bigint_mul1_64_target[:call_conv] + " "
    bm64_attrs = " nounwind"
    if bigint_times_reopened_fn == nil
      bm64_attrs += " alwaysinline"
    fn_out << "define i64 @__w_bigint_mul1_64_src(i64 %a, i64 %b)" + bm64_attrs + " {\n"
    fn_out << "  %r = tail call " + bm64_cc + "i64 @" + bigint_mul1_64_target[:name] + "(i64 %a, i64 %b)\n"
    fn_out << "  ret i64 %r\n"
    fn_out << "}\n\n"
    used_runtime_fns["__w_bigint_mul1_64_src"] = false
    known_fns["__w_bigint_mul1_64_src"] = true
  elsif used_runtime_fns["__w_bigint_mul1_64_src"] == true
    seam_decls << "declare i64 @__w_bigint_mul1_64_src(i64, i64) nounwind\n"

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
