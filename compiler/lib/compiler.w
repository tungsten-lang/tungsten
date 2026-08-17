# Compiler — orchestrates the WIRE pipeline: AST -> lower -> emit
# Entry point for all compilation. Replaces the old Codegen class.

use lowering
use return_inference
use cfg
use ownership
use escape
use content_hash
use core_reachability
use emitter
use target

# Cached Core symbols cannot depend on a program-wide content-hash pass. Make
# their original names LLVM-safe once, then replay the exact mapping into each
# fresh user overlay before that overlay is hashed and compacted.
-> incremental_core_cache_prepare_names(mod)
  if mod[:incremental_core_cache_key] == nil
    return nil
  rename_map = nil
  entry = mod[:incremental_core_cache_entry]
  if entry != nil
    rename_map = entry[:name_map]
  if rename_map == nil
    rename_map = {}
    i = 0
    while i < mod[:functions].size()
      func = mod[:functions][i]
      if func[:incremental_core_candidate] == true
        safe = llvm_safe_name(func[:name])
        if safe != func[:name]
          rename_map_put(rename_map, func[:name], safe)
      i += 1

  if rename_map.keys().size() > 0
    global_rename = build_memo_global_rename(mod, rename_map)
    rewrite_references(mod, rename_map, global_rename)
    rewrite_known_name_maps(mod, rename_map)
    i = 0
    while i < mod[:functions].size()
      func = mod[:functions][i]
      replacement = rename_map_get(rename_map, func[:name])
      if replacement != nil
        func[:name] = replacement
        func[:llvm_internal] = true
      i += 1
  i = 0
  while i < mod[:functions].size()
    func = mod[:functions][i]
    if func[:incremental_core_candidate] == true
      func[:incremental_core_hash_source_name] = func[:name]
    i += 1
  mod[:incremental_core_cache_name_map] = rename_map
  nil

-> fmt_elapsed(seconds)
  # Format as " X.XXXs" right-aligned in 7 chars
  if seconds < ~0.001
    return " 0.000s"
  s = seconds.to_s()
  # Ensure dot exists
  if s.index(".") == nil
    s = s + ".000"
  # Truncate to 3 decimal places
  parts = s.split(".")
  whole = parts[0]
  frac = parts[1]
  if frac == nil
    frac = "000"
  if frac.size() > 3
    frac = frac.slice(0, 3)
  while frac.size() < 3
    frac = frac + "0"
  result = whole + "." + frac + "s"
  while result.size() < 7
    result = " " + result
  result

-> strip_enhanced_stacktrace_metadata(mod)
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    bi = 0
    while bi < func[:blocks].size()
      block = func[:blocks][bi]
      instrs = block[:instructions]
      new_instrs = []
      ii = 0
      while ii < instrs.size()
        inst = instrs[ii]
        if wire_kind(inst) != :call_loc_set_col
          if wire_get(inst, :src_line) != nil
            wire_set(inst, :src_line, nil)
          if wire_get(inst, :src_col) != nil
            wire_set(inst, :src_col, nil)
          if wire_get(inst, :loc_site_id) != nil
            wire_set(inst, :loc_site_id, nil)
          new_instrs.push(inst)
        ii += 1
      block[:instructions] = new_instrs
      bi += 1
    fi += 1

# Release metadata stripping can make source-file strings (and occasionally
# other diagnostic-only literals) dead after lowering has already assigned
# module string ids. Leaving those entries in the static slab is not just
# bloat: stage 0 and the native compiler can discover diagnostic locations at
# different moments, shifting every later slab slot and breaking the
# stage-1/stage-2 byte fixed point even though the live WIRE is identical.
# Compact and remap the six instruction fields that carry module string ids.
# Debug builds deliberately skip this pass so their location/backtrace data is
# retained exactly as lowered.
-> compact_live_module_strings(mod)
  live = {}
  # Cached Core instructions retain their canonical prefix ids across batch
  # members. Keep the complete prefix even when release metadata stripping
  # makes one of its diagnostic strings dead in this particular module.
  core_prefix = mod[:incremental_core_string_count]
  if core_prefix == nil
    core_prefix = 0
  prefix_id = 0
  while prefix_id < core_prefix
    live[prefix_id] = true
    prefix_id += 1
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    bi = 0
    while bi < func[:blocks].size()
      instrs = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instrs.size()
        inst = instrs[ii]
        if inst[:string_id] != nil
          live[inst[:string_id]] = true
        if inst[:str_id] != nil
          live[inst[:str_id]] = true
        if inst[:name_str_id] != nil
          live[inst[:name_str_id]] = true
        if inst[:method_str_id] != nil
          live[inst[:method_str_id]] = true
        if inst[:file_str_id] != nil
          live[inst[:file_str_id]] = true
        if inst[:ivar_str_id] != nil
          live[inst[:ivar_str_id]] = true
        cases = wire_get(inst, :cases)
        if cases != nil
          ci = 0
          while ci < wire_sequence_size(cases)
            case_item = wire_sequence_get(cases, ci)
            if case_item[:string_id] != nil
              live[case_item[:string_id]] = true
            ci += 1
        ii += 1
      bi += 1
    fi += 1

  remap = {}
  compact = []
  by_text = {}
  strings = mod[:strings]
  si = 0
  while si < strings.size()
    entry = strings[si]
    old_id = entry[:id]
    if live[old_id] == true
      new_id = compact.size()
      remap[old_id] = new_id
      compact.push({id: new_id, text: entry[:text]})
      by_text[entry[:text]] = new_id
    si += 1

  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    bi = 0
    while bi < func[:blocks].size()
      instrs = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instrs.size()
        inst = instrs[ii]
        if inst[:string_id] != nil && remap[inst[:string_id]] != inst[:string_id]
          inst[:string_id] = remap[inst[:string_id]]
        if inst[:str_id] != nil && remap[inst[:str_id]] != inst[:str_id]
          inst[:str_id] = remap[inst[:str_id]]
        if inst[:name_str_id] != nil && remap[inst[:name_str_id]] != inst[:name_str_id]
          inst[:name_str_id] = remap[inst[:name_str_id]]
        if inst[:method_str_id] != nil && remap[inst[:method_str_id]] != inst[:method_str_id]
          inst[:method_str_id] = remap[inst[:method_str_id]]
        if inst[:file_str_id] != nil && remap[inst[:file_str_id]] != inst[:file_str_id]
          inst[:file_str_id] = remap[inst[:file_str_id]]
        if inst[:ivar_str_id] != nil && remap[inst[:ivar_str_id]] != inst[:ivar_str_id]
          inst[:ivar_str_id] = remap[inst[:ivar_str_id]]
        cases = wire_get(inst, :cases)
        if cases != nil
          ci = 0
          while ci < wire_sequence_size(cases)
            case_item = wire_sequence_get(cases, ci)
            if case_item[:string_id] != nil && remap[case_item[:string_id]] != case_item[:string_id]
              case_item[:string_id] = remap[case_item[:string_id]]
            ci += 1
        ii += 1
      bi += 1
    fi += 1

  mod[:strings] = compact
  mod[:string_ids_by_text] = by_text
  mod[:next_string] = compact.size()
  # content_hash_pass has already consumed its semantic string index; do not
  # leave the old-id view available to later tooling.
  mod[:string_index] = nil
  nil

-> compile(ast, source_path, verbose = false, frame_pointers = false, sidemap_path = nil, release_mode = false, fast_mode = false, build_defines = nil, math_mode = :precise, no_static_slab = false, source_manifest = nil)
  compile_started_at = clock()

  lower_started_at = clock()
  mod = lower_ast(ast, source_path, verbose, fast_mode, build_defines, math_mode, no_static_slab, source_manifest, release_mode)
  incremental_core_cache_prepare_names(mod)
  t_lower = clock() - lower_started_at

  # A persistent Core hit is already immutable and post-mid-end. Discover its
  # closed-world live closure before the remaining whole-module analyses, then
  # run those analyses over the program plus reachable Core only. Cold misses
  # deliberately retain the full cohort so the published cache entry is ready
  # for a different program on its first reuse.
  full_pipeline_functions = nil
  if env("TUNGSTEN_EARLY_CORE_REACHABILITY") != "0" && mod[:incremental_core_cache_hit] == true
    core_reachability_prepare(mod, false)
    early_functions = core_reachability_emission_functions(mod)
    if early_functions != nil
      full_pipeline_functions = mod[:functions]
      # The symbol sidemap is a complete cached-Core provenance artifact even
      # when codegen analyzes only the live slice. Preserve its metadata input
      # without putting dead bodies back into hash/call-graph work.
      mod[:content_hash_info_functions] = full_pipeline_functions
      mod[:functions] = early_functions
      mod[:core_reachability_early] = true

  cfg_started_at = clock()
  # B8 detector: TUNGSTEN_SSA_REPORT=<path> dumps every function mem2reg
  # actually converts (overflow-checked gate passed AND promotable slots
  # exist), one name per line. Guard-elision work can remove a function's
  # last *_i48_checked op, silently flipping has_overflow_checked and
  # newly running SSA on code it never ran on — and stage identity cannot
  # catch that (both stages agree on the mis-lowering). Diff this dump
  # across the change; any new member is newly SSA-converted.
  ssa_report = env("TUNGSTEN_SSA_REPORT")
  ssa_converted = []
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    if func[:blocks].size() > 0 && func[:incremental_core_frozen] != true
      # CFG/dominator/frontier construction exists only for mem2reg. Check
      # the two cheap eligibility conditions first: roughly half of the
      # self-hosted compiler's functions have no promotable slots, so eagerly
      # analyzing every function wastes most of this phase's work.
      if !has_overflow_checked(func)
        promotable = find_promotable_vars(func)
        if promotable.keys().size() > 0
          if ssa_report != nil && ssa_report != ""
            ssa_converted.push(func[:name])
          analysis = analyze_function(func)
          func[:cfg_analysis] = analysis
          ssa_convert(func, analysis, nil, promotable)
      prune_empty_blocks(func)
    fi += 1
  if ssa_report != nil && ssa_report != ""
    write_file(ssa_report, ssa_converted.sort().join("\n") + "\n")
  t_cfg = clock() - cfg_started_at

  ownership_pass(mod)

  esc_started_at = clock()
  escape_pass(mod)
  t_escape = clock() - esc_started_at

  t_free = 0
  if env("TUNGSTEN_FREE") != "0"
    free_started_at = clock()
    free_insertion_pass(mod)
    t_free = clock() - free_started_at

  hash_started_at = clock()
  content_hash_pass(mod, verbose, release_mode)
  mod[:content_hash_info_functions] = nil
  t_hash = clock() - hash_started_at

  if mod[:core_reachability_early] == true
    # content_hash_pass may replace the live function Array after deduplication
    # and symbol compaction. Preserve that final slice and filter method-table
    # registrations now, at the same post-hash semantic point as before.
    mod[:core_reachability_emit_functions] = mod[:functions]
    core_reachability_filter_current_registrations(mod, full_pipeline_functions, mod[:functions])
  else
    core_reachability_prepare(mod)

  mod[:enhanced_stacktraces] = true
  # Debug executables promise source-level backtrace frames, not merely a
  # walkable physical stack. The emitter pairs frame pointers with noinline
  # and disabled sibling-call elimination for this mode.
  mod[:preserve_debug_frames] = frame_pointers && !release_mode
  if release_mode
    if env("TUNGSTEN_LINEAR_WIRE_POSTPROCESS") == "0"
      strip_enhanced_stacktrace_metadata(mod)
      compact_live_module_strings(mod)
    else
      finish_release_wire_postprocess(mod)
    mod[:enhanced_stacktraces] = false

  target_started_at = clock()
  llvm_target = detect_llvm_target()
  t_target = clock() - target_started_at
  mod[:llvm_datalayout] = llvm_target[:datalayout]
  mod[:llvm_triple] = llvm_target[:triple]
  mod[:llvm_fn_attrs] = llvm_target[:fn_attrs]

  emit_started_at = clock()
  all_functions = mod[:functions]
  emit_functions = core_reachability_emission_functions(mod)
  if emit_functions != nil
    mod[:functions] = emit_functions
  ir = emit_artifact(mod, frame_pointers)
  mod[:functions] = all_functions
  core_reachability_restore_full_graph(mod)
  if full_pipeline_functions != nil
    mod[:functions] = full_pipeline_functions
  t_emit = clock() - emit_started_at

  # Store only after every destructive pass and the emitter have finished.
  # Cache hits point at this immutable, post-pass representation.
  incremental_core_cache_finalize(mod)

  if sidemap_path != nil
    sidemap_text = mod[:symbol_sidemap_text]
    if sidemap_text != nil
      write_file(sidemap_path, sidemap_text)

  t_total = clock() - compile_started_at

  if verbose
    << ""
    << incremental_core_cache_verbose_text(mod)
    << incremental_library_cache_verbose_text(mod)
    << core_reachability_verbose_text(mod)
    target_cache_text = target_probe_cache_verbose_text()
    if target_cache_text != nil
      << target_cache_text
    if mod[:function_emit_cache_hits] != nil && (mod[:function_emit_cache_hits] > 0 || mod[:function_emit_cache_misses] > 0)
      function_emit_text = "  function emit cache: " + mod[:function_emit_cache_hits].to_s() + " hits, " + mod[:function_emit_cache_misses].to_s() + " misses, " + mod[:function_emit_cache_bypasses].to_s() + " bypassed"
      if mod[:function_emit_disk_cache_status] != nil
        function_emit_text = function_emit_text + "; disk " + mod[:function_emit_disk_cache_status].to_s()
      << function_emit_text
    if mod[:parallel_function_emit_jobs] != nil
      << "  function emit workers: " + mod[:parallel_function_emit_jobs].to_s() + " deterministic threads"
    if mod[:content_hash_skipped_count] > 0
      << "  content hash work set: " + mod[:content_hash_function_count].to_s() + "/" + (mod[:content_hash_function_count] + mod[:content_hash_skipped_count]).to_s() + " functions (" + mod[:content_hash_skipped_count].to_s() + " cached)"
    << fmt_elapsed(t_lower) + " lowering to wire"
    << fmt_elapsed(t_cfg) + " cfg+ssa"
    << fmt_elapsed(t_escape) + " escape"
    if t_free > 0
      << fmt_elapsed(t_free) + " free insertion"
    << fmt_elapsed(t_hash) + " content hash"
    << fmt_elapsed(t_target) + " target detect"
    << fmt_elapsed(t_emit) + " emit llvm ir"
    << "------- ------------------"
    << fmt_elapsed(t_total) + " TOTAL COMPILE TIME"
    << ""

    # Escape summary
    fn_escs = mod[:fn_escs]
    if fn_escs != nil
      esc_keys = fn_escs.keys()
      n_pure = 0
      n_no_escape = 0
      ei = 0
      while ei < esc_keys.size()
        summary = fn_escs[esc_keys[ei]]
        if summary[:pure] == true
          n_pure += 1
        escs = summary[:escs]
        if escs != nil
          all_local = true
          pi = 0
          while pi < escs.size()
            if escs[pi] == true
              all_local = false
            pi += 1
          if all_local
            n_no_escape += 1
        ei += 1
      << "  " + mod[:functions].size().to_s() + " functions (" + n_no_escape.to_s() + " no escapees, " + n_pure.to_s() + " pure)"

    # Content hash summary
    dedup_count = mod[:fn_dedup_count]
    if dedup_count != nil && dedup_count > 0
      << "  " + dedup_count.to_s() + " functions deduped"
    symbol_count = mod[:fn_symbol_count]
    if symbol_count != nil && symbol_count > 0
      << "  " + symbol_count.to_s() + " function symbols compacted"

    # String/symbol summary
    strings = mod[:strings]
    if strings != nil
      n_sso = 0
      n_slab = 0
      n_heap = 0
      si = 0
      while si < strings.size()
        blen = strings[si][:text].size()
        if blen <= 5
          n_sso += 1
        elsif blen <= 61
          n_slab += 1
        else
          n_heap += 1
        si += 1
      << "  " + strings.size().to_s() + " strings (" + n_sso.to_s() + " inline, " + n_slab.to_s() + " slab, " + n_heap.to_s() + " heap)"

      if env("DEBUG_STRINGS") == "1"
        # Build live string ID set by scanning all instructions
        live_ids = {}
        fi = 0
        while fi < mod[:functions].size()
          func = mod[:functions][fi]
          bi = 0
          while bi < func[:blocks].size()
            instrs = func[:blocks][bi][:instructions]
            ii = 0
            while ii < instrs.size()
              inst = instrs[ii]
              if wire_get(inst, :string_id) != nil
                live_ids[wire_get(inst, :string_id)] = true
              if wire_get(inst, :str_id) != nil
                live_ids[wire_get(inst, :str_id)] = true
              if wire_get(inst, :name_str_id) != nil
                live_ids[wire_get(inst, :name_str_id)] = true
              if wire_get(inst, :method_str_id) != nil
                live_ids[wire_get(inst, :method_str_id)] = true
              ii += 1
            bi += 1
          fi += 1
        << ""
        si = 0
        while si < strings.size()
          text = strings[si][:text]
          alive = live_ids[strings[si][:id]] == true
          if alive
            << "  live: " + text
          else
            << "  DEAD: " + text
          si += 1

  ir

-> compile_to_wire(ast, source_path, verbose = false, fast_mode = false, math_mode = :precise, source_manifest = nil)
  lower_ast(ast, source_path, verbose, fast_mode, nil, math_mode, false, source_manifest, false)
