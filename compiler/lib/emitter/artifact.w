# Emitter artifact orchestration — module and function rendering.

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
  novec_md_state[:refs] = {}
  ewscope_md_state[:ids] = {}
  mod[:parallel_function_emit_jobs] = nil

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
            ccall_needed[iname] = wire_sequence_size(wire_get(inst, :args))
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
  function_emit_hits_start = function_emit_cache_state[:hits]
  function_emit_misses_start = function_emit_cache_state[:misses]
  function_emit_bypasses_start = function_emit_cache_state[:bypasses]
  # Release-only by design. Debug builds retain the direct rendering path so
  # frame/backtrace metadata remains independent of this optimization.
  function_emit_cache_enabled = env("TUNGSTEN_FUNCTION_EMIT_CACHE") != "0" && mod[:enhanced_stacktraces] == false && mod[:incremental_core_cache_key] != nil
  arm64_target = emit_target_is_arm64(mod)
  windows_target = emit_target_is_windows(mod)

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
  function_emit_cache_bucket_value = nil
  function_emit_library_cache_bucket_value = nil
  if function_emit_cache_enabled
    function_emit_cache_bucket_value = function_emit_cache_bucket(mod, frame_pointers, mod[:llvm_fn_attrs], arm64_target, windows_target, mod[:preserve_debug_frames] == true, fp_flags)
    function_emit_library_cache_bucket_value = function_emit_library_cache_bucket(mod, frame_pointers, mod[:llvm_fn_attrs], arm64_target, windows_target, mod[:preserve_debug_frames] == true, fp_flags)

  # Functions. A cached rendered-Core bucket already removes most work and is
  # process-global, so it stays on its proven serial path. Otherwise frozen
  # functions may render on private worker buffers after metadata ids are
  # assigned deterministically in source order.
  parallel_function_jobs = emitter_parallel_job_count(mod, function_emit_cache_bucket_value)
  if parallel_function_jobs > 1
    emitter_prepare_parallel_metadata(mod[:functions], fp_flags)
    function_attr_group_id(attr_groups, function_attr_text(frame_pointers, mod[:llvm_fn_attrs], mod[:preserve_debug_frames] == true))
    parallel_rendered = emitter_render_functions_parallel(mod[:functions], mod[:string_wvalues], slab_info, frame_pointers, mod[:llvm_fn_attrs], attr_groups, arm64_target, windows_target, mod[:preserve_debug_frames] == true, parallel_function_jobs)
    i = 0
    while i < parallel_rendered[:texts].size()
      fn_out << parallel_rendered[:texts][i]
      fn_out << "\n"
      function_emit_cache_merge_ptr_ids(used_ptr_ids, parallel_rendered[:ptr_ids][i])
      i += 1
    function_emit_cache_state[:bypasses] = function_emit_cache_state[:bypasses] + mod[:functions].size()
    mod[:parallel_function_emit_jobs] = parallel_function_jobs

  i = 0
  while parallel_function_jobs == 1 && i < mod[:functions].size()
    mod[:functions][i][:fp_flags] = fp_flags
    selected_emit_bucket = function_emit_cache_select_bucket(mod[:functions][i], function_emit_cache_bucket_value, function_emit_library_cache_bucket_value)
    fn_out << emit_function_with_cache(mod[:functions][i], mod[:string_wvalues], slab_info, used_ptr_ids, frame_pointers, mod[:llvm_fn_attrs], attr_groups, arm64_target, windows_target, mod[:preserve_debug_frames] == true, selected_emit_bucket)
    fn_out << "\n"
    i += 1
  function_emit_cache_publish(function_emit_cache_bucket_value)
  function_emit_cache_publish(function_emit_library_cache_bucket_value)
  mod[:function_emit_cache_hits] = function_emit_cache_state[:hits] - function_emit_hits_start
  mod[:function_emit_cache_misses] = function_emit_cache_state[:misses] - function_emit_misses_start
  mod[:function_emit_cache_bypasses] = function_emit_cache_state[:bypasses] - function_emit_bypasses_start
  if function_emit_cache_bucket_value != nil
    mod[:function_emit_disk_cache_status] = function_emit_cache_bucket_value[:persistent_status]
  if function_emit_library_cache_bucket_value != nil
    mod[:function_emit_library_disk_cache_status] = function_emit_library_cache_bucket_value[:persistent_status]

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
  # the same table. Exact arithmetic seams use these values so a user reopen
  # retains ordinary method-table precedence.
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
    # Test only the new size before tail-chaining to the retained sqr@4
    # dispatcher, keeping the two outlined levels separate.
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
  # a parser-level annotation. The marker stays an LLVM comment inside the
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
        argc = wire_sequence_size(wire_get(inst, :args))
        needs_scratch = argc > 0 && !scalar_source_call?(inst)
        if needs_scratch && argc > max_mcall_argc
          max_mcall_argc = argc
      ji += 1
    bi += 1

  fp_flags = f[:fp_flags]
  if fp_flags == nil
    fp_flags = ""
  direct_buffer_emit = env("TUNGSTEN_DIRECT_BUFFER_EMIT") != "0"

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
      inst = blk[:instructions][j]
      if !direct_buffer_emit || !append_instruction_direct(out, inst, phi_label_redirects)
        out << render_instruction(inst, string_wvs, used_ptr_ids, phi_label_redirects, fp_flags, arm64_target, windows_target)
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
