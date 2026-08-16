# Compiler — orchestrates the WIRE pipeline: AST -> lower -> emit
# Entry point for all compilation. Replaces the old Codegen class.

use lowering
use return_inference
use cfg
use ownership
use escape
use content_hash
use emitter
use target

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
        if inst[:op] != :call_loc_set_col
          inst[:src_line] = nil
          inst[:src_col] = nil
          inst[:loc_site_id] = nil
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
        cases = inst[:cases]
        if cases != nil
          ci = 0
          while ci < cases.size()
            if cases[ci][:string_id] != nil
              live[cases[ci][:string_id]] = true
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
        if inst[:string_id] != nil
          inst[:string_id] = remap[inst[:string_id]]
        if inst[:str_id] != nil
          inst[:str_id] = remap[inst[:str_id]]
        if inst[:name_str_id] != nil
          inst[:name_str_id] = remap[inst[:name_str_id]]
        if inst[:method_str_id] != nil
          inst[:method_str_id] = remap[inst[:method_str_id]]
        if inst[:file_str_id] != nil
          inst[:file_str_id] = remap[inst[:file_str_id]]
        if inst[:ivar_str_id] != nil
          inst[:ivar_str_id] = remap[inst[:ivar_str_id]]
        cases = inst[:cases]
        if cases != nil
          ci = 0
          while ci < cases.size()
            if cases[ci][:string_id] != nil
              cases[ci][:string_id] = remap[cases[ci][:string_id]]
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

-> compile(ast, source_path, verbose = false, frame_pointers = false, sidemap_path = nil, release_mode = false, fast_mode = false, build_defines = nil, math_mode = :precise, no_static_slab = false)
  compile_started_at = clock()

  lower_started_at = clock()
  mod = lower_ast(ast, source_path, verbose, fast_mode, build_defines, math_mode, no_static_slab)
  t_lower = clock() - lower_started_at

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
    if func[:blocks].size() > 0
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
  content_hash_pass(mod, verbose)
  t_hash = clock() - hash_started_at

  mod[:enhanced_stacktraces] = true
  # Debug executables promise source-level backtrace frames, not merely a
  # walkable physical stack. The emitter pairs frame pointers with noinline
  # and disabled sibling-call elimination for this mode.
  mod[:preserve_debug_frames] = frame_pointers && !release_mode
  if release_mode
    strip_enhanced_stacktrace_metadata(mod)
    compact_live_module_strings(mod)
    mod[:enhanced_stacktraces] = false

  target_started_at = clock()
  llvm_target = detect_llvm_target()
  t_target = clock() - target_started_at
  mod[:llvm_datalayout] = llvm_target[:datalayout]
  mod[:llvm_triple] = llvm_target[:triple]
  mod[:llvm_fn_attrs] = llvm_target[:fn_attrs]

  emit_started_at = clock()
  ir = emit_artifact(mod, frame_pointers)
  t_emit = clock() - emit_started_at

  if sidemap_path != nil
    sidemap_text = mod[:symbol_sidemap_text]
    if sidemap_text != nil
      write_file(sidemap_path, sidemap_text)

  t_total = clock() - compile_started_at

  if verbose
    << ""
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
              if inst[:string_id] != nil
                live_ids[inst[:string_id]] = true
              if inst[:str_id] != nil
                live_ids[inst[:str_id]] = true
              if inst[:name_str_id] != nil
                live_ids[inst[:name_str_id]] = true
              if inst[:method_str_id] != nil
                live_ids[inst[:method_str_id]] = true
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

-> compile_to_wire(ast, source_path, verbose = false, fast_mode = false, math_mode = :precise)
  lower_ast(ast, source_path, verbose, fast_mode, nil, math_mode)
