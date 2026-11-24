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
    wire_postprocess_linear(mod, rename_map, global_rename, false, mod[:incremental_core_cache_hit] == true)
    rewrite_known_name_maps(mod, rename_map)
    if mod[:incremental_core_cache_hit] != true
      i = 0
      while i < mod[:functions].size()
        func = mod[:functions][i]
        replacement = rename_map_get(rename_map, func[:name])
        if replacement != nil
          func[:name] = replacement
          func[:llvm_internal] = true
        i += 1
  if mod[:incremental_core_cache_hit] != true
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
        op = wire_kind(inst)
        field = incremental_core_cache_inst_string_field(op)
        if field != nil
          sid = wire_get(inst, field)
          if sid != nil
            live[sid] = true
        elsif op == :switch_i64
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
  library_boundary = mod[:incremental_library_cache_string_count]
  if library_boundary == nil
    library_boundary = 0
  library_compact_count = 0
  si = 0
  while si < strings.size()
    entry = strings[si]
    old_id = entry[:id]
    if live[old_id] == true
      new_id = compact.size()
      remap[old_id] = new_id
      compact.push({id: new_id, text: entry[:text]})
      by_text[entry[:text]] = new_id
      if old_id < library_boundary
        library_compact_count = compact.size()
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
        op = wire_kind(inst)
        field = incremental_core_cache_inst_string_field(op)
        if field != nil
          old_id = wire_get(inst, field)
          if old_id != nil && remap[old_id] != old_id
            wire_set(inst, field, remap[old_id])
        elsif op == :switch_i64
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
  mod[:incremental_library_cache_compact_string_count] = library_compact_count
  mod[:string_ids_by_text] = by_text
  mod[:next_string] = compact.size()
  # content_hash_pass has already consumed its semantic string index; do not
  # leave the old-id view available to later tooling.
  mod[:string_index] = nil
  nil

-> wire_leaf_param_index(operand, param_regs)
  if operand == nil
    return -2
  n = param_regs.size()
  i = 0
  while i < n
    if operand == param_regs[i]
      return i
    i += 1
  if operand.starts_with?("%")
    return -2
  -1

-> wire_inline_map_operand(idx, lit_val, args)
  if idx >= 0
    return wire_sequence_get(args, idx)
  lit_val

-> wire_leaf_all_i64_params?(func)
  ptypes = func[:param_types]
  if ptypes == nil
    return true
  i = 0
  n = ptypes.size()
  while i < n
    pt = ptypes[i]
    if pt != nil && pt != "i64"
      return false
    i += 1
  true

-> wire_inline_tiny_leaves(mod)
  fns = mod[:functions]
  n_fns = fns.size()
  candidates = {}
  fi = 0
  while fi < n_fns
    func = fns[fi]
    if func[:return_type] == "i64" && (func[:extra_params] == nil || func[:extra_params].size() == 0) && func[:noinline] != true && func[:is_memoized] != true && func[:blocks].size() == 1 && wire_leaf_all_i64_params?(func)
      params = func[:params]
      n_params = params.size()
      param_regs = []
      pi = 0
      while pi < n_params
        param_regs.push(llvm_param_reg(params[pi]))
        pi += 1
      instrs = func[:blocks][0][:instructions]
      n_instrs = instrs.size()
      if n_instrs == 1 && wire_kind(instrs[0]) == :ret_i64
        rv = wire_get(instrs[0], :value)
        pidx = wire_leaf_param_index(rv, param_regs)
        if pidx >= -1
          candidates[func[:name]] = {kind: :passthrough, arity: n_params, pidx: pidx, val: rv}
      elsif n_instrs == 2 && wire_kind(instrs[1]) == :ret_i64
        op0 = instrs[0]
        k0 = wire_kind(op0)
        t0 = wire_get(op0, :temp)
        if t0 != nil && wire_get(instrs[1], :value) == t0
          if k0 in (:add_i64 :sub_i64 :mul_i64 :and_i64 :or_i64 :xor_i64 :shl_i64 :ashr_i64 :lshr_i64)
            lhs = wire_get(op0, :lhs)
            rhs = wire_get(op0, :rhs)
            l_idx = wire_leaf_param_index(lhs, param_regs)
            r_idx = wire_leaf_param_index(rhs, param_regs)
            if l_idx >= -1 && r_idx >= -1
              candidates[func[:name]] = {kind: :binop, arity: n_params, op: k0, l_idx: l_idx, lhs: lhs, r_idx: r_idx, rhs: rhs}
          elsif k0 == :ivar_get_idx
            sr = wire_get(op0, :self_reg)
            off = wire_get(op0, :offset)
            sr_idx = wire_leaf_param_index(sr, param_regs)
            if sr_idx >= -1 && off != nil
              candidates[func[:name]] = {kind: :ivar_get_idx, arity: n_params, sr_idx: sr_idx, self_reg: sr, offset: off}
          elsif k0 == :ivar_set_idx
            sr = wire_get(op0, :self_reg)
            v0 = wire_get(op0, :value)
            off = wire_get(op0, :offset)
            sr_idx = wire_leaf_param_index(sr, param_regs)
            v_idx = wire_leaf_param_index(v0, param_regs)
            if sr_idx >= -1 && v_idx >= -1 && off != nil
              candidates[func[:name]] = {kind: :ivar_set_idx, arity: n_params, sr_idx: sr_idx, self_reg: sr, v_idx: v_idx, val: v0, offset: off}
          elsif k0 == :nanbox_int
            raw = wire_get(op0, :raw)
            r_idx = wire_leaf_param_index(raw, param_regs)
            if r_idx >= -1
              candidates[func[:name]] = {kind: :nanbox_int, arity: n_params, r_idx: r_idx, raw: raw}
          elsif k0 == :nanunbox_int
            boxed = wire_get(op0, :boxed)
            b_idx = wire_leaf_param_index(boxed, param_regs)
            if b_idx >= -1
              candidates[func[:name]] = {kind: :nanunbox_int, arity: n_params, b_idx: b_idx, boxed: boxed}
          elsif k0 in (:ta_size_raw :ta_cap_raw :zext_i1_i64 :zext_i32_i64 :zext_i16_i64 :ctpop_i64 :cttz_i64)
            v0 = wire_get(op0, :value)
            v_idx = wire_leaf_param_index(v0, param_regs)
            if v_idx >= -1
              candidates[func[:name]] = {kind: :unop, arity: n_params, op: k0, v_idx: v_idx, val: v0}
          elsif k0 == :call_direct_i64
            inner_name = wire_get(op0, :name)
            inner_args = wire_get(op0, :args)
            is_core = func[:incremental_core_candidate] == true || func[:incremental_core_frozen] == true
            is_rt = inner_name != nil && (inner_name.starts_with?("w_") || inner_name.starts_with?("__w_"))
            if inner_name != nil && inner_name != func[:name] && wire_get(op0, :call_conv) == nil && inner_args != nil && (!is_core || is_rt)
              a_idxs = []
              a_lits = []
              all_ok = true
              ai = 0
              na = wire_sequence_size(inner_args)
              while ai < na
                av = wire_sequence_get(inner_args, ai)
                aidx = wire_leaf_param_index(av, param_regs)
                if aidx < -1
                  all_ok = false
                  break
                a_idxs.push(aidx)
                a_lits.push(av)
                ai += 1
              if all_ok
                raw_atypes = wire_get(op0, :arg_types)
                atypes = nil
                if raw_atypes != nil
                  atypes = []
                  ti = 0
                  nt = wire_sequence_size(raw_atypes)
                  while ti < nt
                    atypes.push(wire_sequence_get(raw_atypes, ti))
                    ti += 1
                candidates[func[:name]] = {kind: :call_direct, arity: n_params, inner_name: inner_name, arg_idxs: a_idxs, arg_lits: a_lits, arg_types: atypes}
    fi += 1
  if candidates.size() == 0
    return 0
  inlined = 0
  fi = 0
  while fi < n_fns
    func = fns[fi]
    if func[:incremental_core_frozen] != true
      blocks = func[:blocks]
      n_blocks = blocks.size()
      bi = 0
      while bi < n_blocks
        instrs = blocks[bi][:instructions]
        n_instrs = instrs.size()
        ii = 0
        while ii < n_instrs
          inst = instrs[ii]
          if wire_kind(inst) == :call_direct_i64
            callee = wire_get(inst, :name)
            cand = candidates[callee]
            if cand != nil && callee != func[:name] && wire_get(inst, :arg_types) == nil && wire_get(inst, :call_conv) == nil
              args = wire_get(inst, :args)
              temp = wire_get(inst, :temp)
              if args != nil && temp != nil && wire_sequence_size(args) == cand[:arity]
                ckind = cand[:kind]
                if ckind == :passthrough
                  mv = wire_inline_map_operand(cand[:pidx], cand[:val], args)
                  instrs[ii] = wire_make_add_i64("0", mv, temp)
                  inlined += 1
                elsif ckind == :binop
                  ml = wire_inline_map_operand(cand[:l_idx], cand[:lhs], args)
                  mr = wire_inline_map_operand(cand[:r_idx], cand[:rhs], args)
                  bkid = ccall_nobox("w_numeric_to_i64", wire_kind_id(cand[:op]))
                  instrs[ii] = ccall_rawargs("w_wire_packed_3", bkid, ml, mr, temp)
                  inlined += 1
                elsif ckind == :ivar_get_idx
                  msr = wire_inline_map_operand(cand[:sr_idx], cand[:self_reg], args)
                  instrs[ii] = wire_make_ivar_get_idx(cand[:offset], msr, temp)
                  inlined += 1
                elsif ckind == :ivar_set_idx
                  msr = wire_inline_map_operand(cand[:sr_idx], cand[:self_reg], args)
                  mv = wire_inline_map_operand(cand[:v_idx], cand[:val], args)
                  instrs[ii] = wire_make_ivar_set_idx(cand[:offset], msr, temp, mv)
                  inlined += 1
                elsif ckind == :nanbox_int
                  mr = wire_inline_map_operand(cand[:r_idx], cand[:raw], args)
                  instrs[ii] = wire_make_nanbox_int(mr, temp, next_temp(func))
                  inlined += 1
                elsif ckind == :nanunbox_int
                  mb = wire_inline_map_operand(cand[:b_idx], cand[:boxed], args)
                  instrs[ii] = wire_make_nanunbox_int(mb, temp, next_temp(func))
                  inlined += 1
                elsif ckind == :unop
                  mv = wire_inline_map_operand(cand[:v_idx], cand[:val], args)
                  instrs[ii] = wire_make_dynamic_2(cand[:op], :temp, temp, :value, mv)
                  inlined += 1
                elsif ckind == :call_direct
                  a_idxs = cand[:arg_idxs]
                  a_lits = cand[:arg_lits]
                  na = a_idxs.size()
                  mapped_args = []
                  ai = 0
                  while ai < na
                    mapped_args.push(wire_inline_map_operand(a_idxs[ai], a_lits[ai], args))
                    ai += 1
                  instrs[ii] = wire_make_call_direct_i64(cand[:arg_types], mapped_args, nil, wire_get(inst, :loc_site_id), cand[:inner_name], wire_get(inst, :src_col), wire_get(inst, :src_line), temp)
                  inlined += 1
          ii += 1
        bi += 1
    fi += 1
  inlined

-> wire_i64_arg1_types?(atypes)
  if atypes == nil
    return true
  wire_sequence_size(atypes) == 1 && wire_sequence_get(atypes, 0) == "i64"

-> wire_decimal_in_range?(s, lo, hi)
  if s == nil || type(s) != "String"
    return false
  n = s.size()
  if n == 0 || n > 19
    return false
  start = 0
  if s.byte_at(0) == 45
    if n == 1
      return false
    start = 1
  i = start
  while i < n
    b = s.byte_at(i)
    if b < 48 || b > 57
      return false
    i += 1
  v = s.to_i()
  v >= lo && v <= hi

-> wire_elim_box_unbox_roundtrips_fn(func)
  blocks = func[:blocks]
  n_blocks = blocks.size()
  i64_box_src = {}
  u64_box_src = {}
  f64_box_src = {}
  proven_i48 = {}
  proven_u47 = {}
  box_count = 0
  int_box_count = 0
  bi = 0
  while bi < n_blocks
    instrs = blocks[bi][:instructions]
    n_instrs = instrs.size()
    ii = 0
    while ii < n_instrs
      inst = instrs[ii]
      op = wire_kind(inst)
      if op == :sext_i32_i64 || op == :sext_i16_i64 || op == :sext_i8_i64
        t = wire_get(inst, :temp)
        if t != nil
          proven_i48[t] = true
      elsif op == :zext_i32_i64 || op == :zext_i16_i64 || op == :zext_i8_i64 || op == :zext_i1_i64 || op == :array_size_raw || op == :ta_size_raw || op == :ta_cap_raw || op == :ctpop_i64 || op == :cttz_i64 || op == :ctlz_i64
        t = wire_get(inst, :temp)
        if t != nil
          proven_i48[t] = true
          proven_u47[t] = true
      elsif op == :and_i64
        t = wire_get(inst, :temp)
        if t != nil
          lv = wire_get(inst, :left)
          rv = wire_get(inst, :right)
          if wire_decimal_in_range?(lv, 0, 140737488355327) || wire_decimal_in_range?(rv, 0, 140737488355327)
            proven_i48[t] = true
            proven_u47[t] = true
      elsif op == :lshr_i64
        t = wire_get(inst, :temp)
        if t != nil && wire_decimal_in_range?(wire_get(inst, :right), 17, 63)
          proven_i48[t] = true
          proven_u47[t] = true
      elsif op == :ashr_i64
        t = wire_get(inst, :temp)
        if t != nil && wire_decimal_in_range?(wire_get(inst, :right), 16, 63)
          proven_i48[t] = true
      elsif op == :select_i64
        t = wire_get(inst, :temp)
        if t != nil
          tv = wire_get(inst, :then_val)
          fv = wire_get(inst, :else_val)
          t_u47 = proven_u47[tv] == true || wire_decimal_in_range?(tv, 0, 140737488355327)
          f_u47 = proven_u47[fv] == true || wire_decimal_in_range?(fv, 0, 140737488355327)
          if t_u47 && f_u47
            proven_i48[t] = true
            proven_u47[t] = true
          elsif (proven_i48[tv] == true || is_i48_decimal_literal?(tv, true)) && (proven_i48[fv] == true || is_i48_decimal_literal?(fv, true))
            proven_i48[t] = true
      elsif op == :call_direct_i64
        nm = wire_get(inst, :name)
        if nm != nil
          if (nm == "__w_string_byte_length_fast" || nm == "w_node_kind_extern") && wire_get(inst, :src_line) == nil
            t = wire_get(inst, :temp)
            if t != nil
              proven_i48[t] = true
              proven_u47[t] = true
          elsif (nm == "__w_int_fast" || nm == "w_u64") && wire_i64_arg1_types?(wire_get(inst, :arg_types)) && wire_get(inst, :src_line) == nil
            args = wire_get(inst, :args)
            if args != nil && wire_sequence_size(args) == 1
              t = wire_get(inst, :temp)
              a0 = wire_sequence_get(args, 0)
              if t != nil && a0 != nil
                if nm == "__w_int_fast"
                  i64_box_src[t] = a0
                else
                  u64_box_src[t] = a0
                box_count += 1
                int_box_count += 1
      elsif op == :nanbox_int
        t = wire_get(inst, :temp)
        raw = wire_get(inst, :raw)
        if t != nil && raw != nil && (proven_i48[raw] == true || is_i48_decimal_literal?(raw, true))
          i64_box_src[t] = raw
          box_count += 1
      elsif op == :nanbox_float
        t = wire_get(inst, :temp)
        raw = wire_get(inst, :raw)
        if t != nil && raw != nil
          f64_box_src[t] = raw
          box_count += 1
      ii += 1
    bi += 1
  if box_count == 0
    return 0

  subst = {}
  cand_boxes = {}
  eliminated = 0
  bi = 0
  while bi < n_blocks
    instrs = blocks[bi][:instructions]
    n_instrs = instrs.size()
    new_instrs = nil
    ii = 0
    while ii < n_instrs
      inst = instrs[ii]
      op = wire_kind(inst)
      drop = false
      if op == :call_direct_i64
        nm = wire_get(inst, :name)
        if nm != nil && (nm == "__w_to_i64_fast" || nm == "w_to_i64" || nm == "__w_cast_i64_fast" || nm == "w_cast_i64" || nm == "w_to_u64" || nm == "w_cast_u64") && wire_i64_arg1_types?(wire_get(inst, :arg_types)) && wire_get(inst, :src_line) == nil
          args = wire_get(inst, :args)
          if args != nil && wire_sequence_size(args) == 1
            a0 = wire_sequence_get(args, 0)
            src = (nm == "w_to_u64" || nm == "w_cast_u64") ? u64_box_src[a0] : i64_box_src[a0]
            if src != nil
              subst[wire_get(inst, :temp)] = src
              cand_boxes[a0] = true
              drop = true
              eliminated += 1
      elsif op == :nanunbox_float
        b0 = wire_get(inst, :boxed)
        src = f64_box_src[b0]
        if src != nil
          subst[wire_get(inst, :temp)] = src
          cand_boxes[b0] = true
          drop = true
          eliminated += 1
      if drop
        if new_instrs == nil
          new_instrs = []
          ci = 0
          while ci < ii
            new_instrs.push(instrs[ci])
            ci += 1
      elsif new_instrs != nil
        new_instrs.push(inst)
      ii += 1
    if new_instrs != nil
      blocks[bi][:instructions] = new_instrs
    bi += 1

  if eliminated > 0
    resolved = resolve_subst_chains(subst)
    rcount = resolved.size()
    live_boxes = {}
    bi = 0
    while bi < n_blocks
      instrs = blocks[bi][:instructions]
      n_instrs = instrs.size()
      ii = 0
      while ii < n_instrs
        inst = wire_try_fold_box_call(func, apply_subst(instrs[ii], resolved, rcount))
        instrs[ii] = inst
        wire_mark_used_temps(inst, cand_boxes, live_boxes)
        ii += 1
      bi += 1

    # Remove any box instruction whose temp now has zero remaining uses.
    if live_boxes.size() < cand_boxes.size()
      bi = 0
      while bi < n_blocks
        instrs = blocks[bi][:instructions]
        n_instrs = instrs.size()
        new_instrs = nil
        ii = 0
        while ii < n_instrs
          inst = instrs[ii]
          op = wire_kind(inst)
          dead_box = false
          if op == :call_direct_i64 || op == :nanbox_float || op == :nanbox_int
            t = wire_get(inst, :temp)
            if t != nil && cand_boxes[t] == true && live_boxes[t] != true
              dead_box = true
              eliminated += 1
          if dead_box
            if new_instrs == nil
              new_instrs = []
              ci = 0
              while ci < ii
                new_instrs.push(instrs[ci])
                ci += 1
          elsif new_instrs != nil
            new_instrs.push(inst)
          ii += 1
        if new_instrs != nil
          blocks[bi][:instructions] = new_instrs
        bi += 1

  # Narrow remaining `__w_int_fast` / `w_u64` calls whose operand is provably
  # within signed 48-bit range directly to `:nanbox_int` (zero branch, zero
  # BigInt slow path, and invisible to `int_temp_release`).
  if int_box_count > 0 && proven_i48.size() > 0
    bi = 0
    while bi < n_blocks
      instrs = blocks[bi][:instructions]
      n_instrs = instrs.size()
      ii = 0
      while ii < n_instrs
        inst = instrs[ii]
        if wire_kind(inst) == :call_direct_i64 && wire_i64_arg1_types?(wire_get(inst, :arg_types)) && wire_get(inst, :src_line) == nil
          nm = wire_get(inst, :name)
          if nm == "__w_int_fast" || nm == "w_u64"
            args = wire_get(inst, :args)
            if args != nil && wire_sequence_size(args) == 1
              a0 = wire_sequence_get(args, 0)
              ok = nm == "__w_int_fast" ? proven_i48[a0] == true : proven_u47[a0] == true
              if ok
                t = wire_get(inst, :temp)
                if t != nil
                  instrs[ii] = wire_make_nanbox_int(a0, t, next_temp(func))
                  eliminated += 1
        ii += 1
      bi += 1
  eliminated

-> wire_elim_box_unbox_roundtrips(mod)
  fns = mod[:functions]
  n_fns = fns.size()
  total = 0
  fi = 0
  while fi < n_fns
    func = fns[fi]
    if func[:blocks].size() > 0 && func[:incremental_core_frozen] != true
      total += wire_elim_box_unbox_roundtrips_fn(func)
    fi += 1
  total

-> compile(ast, source_path, verbose = false, frame_pointers = false, sidemap_path = nil, release_mode = false, fast_mode = false, build_defines = nil, math_mode = :precise, no_static_slab = false, source_manifest = nil)
  compile_started_at = clock()

  lower_started_at = clock()
  auto_closed_world = auto_closed_world_enabled?(ast)
  mod = lower_ast(ast, source_path, verbose, fast_mode, build_defines, math_mode, no_static_slab, source_manifest, release_mode, auto_closed_world)
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
  cfg_jobs = cfg_parallel_job_count(mod)
  cfg_prepared = nil
  if cfg_jobs > 1
    cfg_prepared = cfg_parallel_prepare(mod, cfg_jobs)
    mod[:parallel_cfg_jobs] = cfg_jobs
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    if func[:blocks].size() > 0 && func[:incremental_core_frozen] != true
      # CFG/dominator/frontier construction exists only for mem2reg. Check
      # the two cheap eligibility conditions first: roughly half of the
      # self-hosted compiler's functions have no promotable slots, so eagerly
      # analyzing every function wastes most of this phase's work.
      if cfg_prepared != nil
        promotable = cfg_prepared[:promotables][fi]
        analysis = cfg_prepared[:analyses][fi]
        if analysis != nil
          if ssa_report != nil && ssa_report != ""
            ssa_converted.push(func[:name])
          func[:cfg_analysis] = analysis
          ssa_convert(func, analysis, nil, promotable, cfg_prepared[:pruned_promotables][fi])
      else
        promotable = find_promotable_vars(func)
        if promotable.size() > 0
          if ssa_report != nil && ssa_report != ""
            ssa_converted.push(func[:name])
          analysis = analyze_function(func)
          func[:cfg_analysis] = analysis
          ssa_convert(func, analysis, nil, promotable)
      prune_empty_blocks(func)
    fi += 1
  if ssa_report != nil && ssa_report != ""
    write_file(ssa_report, ssa_converted.sort().join("\n") + "\n")
  if (release_mode && env("TUNGSTEN_WIRE_INLINE") != "0") || env("TUNGSTEN_WIRE_INLINE") == "1"
    mod[:wire_inlined_calls] = wire_inline_tiny_leaves(mod)
  if env("TUNGSTEN_BOX_ELIM") != "0"
    mod[:wire_box_roundtrips_eliminated] = wire_elim_box_unbox_roundtrips(mod)
  t_cfg = clock() - cfg_started_at

  # Escape summaries first: ownership consults mod[:fn_escs] to avoid
  # pinning a caller's argument (or a guarded `Cls.new` result) as escaped
  # when the callee provably never retains that parameter.
  esc_started_at = clock()
  # Dead global writes (ownership.w): read by mark_escapes and the releases.
  write_only_globals(mod)
  escape_pass(mod)
  t_escape = clock() - esc_started_at
  # Integer releases (ownership.w) rely on core Integer semantics; a module
  # that never sets this (a pass run on its own) gets none of them.
  mod[:integer_contract_intact] = !integer_contract_reopened?(mod)
  mod[:container_contract_intact] = !container_contract_reopened?(mod)
  # Fresh heap results (ownership.w): ownership_analyze treats calls to these
  # functions as producers, so it must run first.
  fresh_heap_returns(mod)

  ownership_started_at = clock()
  ownership_jobs = ownership_parallel_job_count(mod)
  if ownership_jobs > 1
    ownership_pass_parallel(mod, ownership_jobs)
    mod[:parallel_ownership_jobs] = ownership_jobs
  else
    ownership_pass(mod)
  t_ownership = clock() - ownership_started_at

  t_free = 0
  if env("TUNGSTEN_FREE") != "0"
    free_started_at = clock()
    free_insertion_pass(mod)
    t_free = clock() - free_started_at

  hash_started_at = clock()
  content_hash_pass(mod, verbose, release_mode, sidemap_path != nil && env("TUNGSTEN_SIDEMAP") != "0")
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
    library_file_profile = incremental_library_cache_file_profile_text(mod)
    if library_file_profile != nil
      << library_file_profile
    if env("TUNGSTEN_CACHE_TIMINGS") == "1"
      core_load = mod[:incremental_core_cache_load_seconds]
      if core_load != nil && core_load > 0
        << fmt_elapsed(core_load) + " load Core graph"
      library_load = mod[:incremental_library_cache_load_seconds]
      if library_load != nil && library_load > 0
        << fmt_elapsed(library_load) + " load library graph"
    << core_reachability_verbose_text(mod)
    target_cache_text = target_probe_cache_verbose_text()
    if target_cache_text != nil
      << target_cache_text
    if mod[:function_emit_cache_hits] != nil && (mod[:function_emit_cache_hits] > 0 || mod[:function_emit_cache_misses] > 0)
      function_emit_text = "  function emit cache: " + mod[:function_emit_cache_hits].to_s() + " hits, " + mod[:function_emit_cache_misses].to_s() + " misses, " + mod[:function_emit_cache_bypasses].to_s() + " bypassed"
      if mod[:function_emit_disk_cache_status] != nil
        function_emit_text = function_emit_text + "; disk " + mod[:function_emit_disk_cache_status].to_s()
      if mod[:function_emit_library_disk_cache_status] != nil
        function_emit_text = function_emit_text + ", library " + mod[:function_emit_library_disk_cache_status].to_s()
      << function_emit_text
    if mod[:parallel_function_emit_jobs] != nil
      << "  function emit workers: " + mod[:parallel_function_emit_jobs].to_s() + " deterministic threads"
    if mod[:parallel_cfg_jobs] != nil
      << "  cfg analysis workers: " + mod[:parallel_cfg_jobs].to_s() + " deterministic threads"
    if mod[:parallel_ownership_jobs] != nil
      << "  ownership workers: " + mod[:parallel_ownership_jobs].to_s() + " deterministic threads"
    if mod[:content_hash_skipped_count] > 0
      << "  content hash work set: " + mod[:content_hash_function_count].to_s() + "/" + (mod[:content_hash_function_count] + mod[:content_hash_skipped_count]).to_s() + " functions (" + mod[:content_hash_skipped_count].to_s() + " cached)"
    << fmt_elapsed(t_lower) + " lowering to wire"
    << fmt_elapsed(t_cfg) + " cfg+ssa"
    << fmt_elapsed(t_ownership) + " ownership"
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
