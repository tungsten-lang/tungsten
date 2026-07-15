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

-> compile(ast, source_path, verbose = false, frame_pointers = false, sidemap_path = nil, release_mode = false, fast_mode = false, build_defines = nil, math_mode = :precise, no_static_slab = false)
  compile_started_at = clock()

  lower_started_at = clock()
  mod = lower_ast(ast, source_path, verbose, fast_mode, build_defines, math_mode)
  mod[:no_static_slab] = no_static_slab
  t_lower = clock() - lower_started_at

  cfg_started_at = clock()
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
          analysis = analyze_function(func)
          func[:cfg_analysis] = analysis
          ssa_convert(func, analysis, nil, promotable)
      prune_empty_blocks(func)
    fi += 1
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
  if release_mode
    strip_enhanced_stacktrace_metadata(mod)
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
