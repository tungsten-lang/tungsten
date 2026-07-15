# CFG — Control Flow Graph construction, dominator tree, and SSA conversion
# Operates on WIRE functions post-lowering.

use runtime_types
use wire

# Skip SSA conversion for functions that contain overflow-checked instructions.
# These instructions expand into multiple LLVM blocks during emission,
# making the WIRE CFG not match the LLVM CFG. SSA phi nodes would reference
# wrong predecessor labels.

-> has_overflow_checked(func)
  bi = 0
  while bi < func[:blocks].size()
    instrs = func[:blocks][bi][:instructions]
    ii = 0
    while ii < instrs.size()
      op = instrs[ii][:op]
      if op in (:add_i48_checked :sub_i48_checked :mul_i48_checked)
        return true
      ii += 1
    bi += 1
  false

# Build CFG for a single function: label→index map, successor/predecessor lists.

-> build_cfg(func)
  blocks = func[:blocks]
  n = blocks.size()

  # Pass 1: label → block index
  label_map = {}
  i = 0
  while i < n
    label_map[blocks[i][:label]] = i
    i += 1

  # Pass 2: edges from terminators
  succs = {}
  preds = {}
  i = 0
  while i < n
    succs[i] = []
    preds[i] = []
    i += 1

  i = 0
  while i < n
    instrs = blocks[i][:instructions]
    if instrs.size() > 0
      last = instrs[instrs.size() - 1]
      op = last[:op]
      if op == :br
        target = label_map[last[:label]]
        if target != nil
          succs[i].push(target)
          preds[target].push(i)
      elsif op == :cond_br
        then_idx = label_map[last[:then_label]]
        else_idx = label_map[last[:else_label]]
        if then_idx != nil
          succs[i].push(then_idx)
          preds[then_idx].push(i)
        if else_idx != nil
          succs[i].push(else_idx)
          preds[else_idx].push(i)
      elsif op == :switch_i64
        default_idx = label_map[last[:default_label]]
        if default_idx != nil
          succs[i].push(default_idx)
          preds[default_idx].push(i)
        cases = last[:cases]
        ci = 0
        while ci < cases.size()
          target_idx = label_map[cases[ci][:label]]
          if target_idx != nil
            succs[i].push(target_idx)
            preds[target_idx].push(i)
          ci += 1
    i += 1

  {label_map: label_map, succs: succs, preds: preds, num_blocks: n}

# Iterative DFS postorder, then reverse for RPO.

-> compute_rpo(cfg)
  n = cfg[:num_blocks]
  visited = {}
  postorder = []

  # Iterative DFS using explicit stack
  # Stack entries: [block_index, child_cursor]
  stack = [[0, 0]]
  visited[0] = true

  while stack.size() > 0
    top = stack[stack.size() - 1]
    node = top[0]
    cursor = top[1]
    children = cfg[:succs][node]

    if cursor < children.size()
      # Advance cursor
      top[1] = cursor + 1
      child = children[cursor]
      if visited[child] != true
        visited[child] = true
        stack.push([child, 0])
    else
      # All children visited, emit postorder
      stack.pop()
      postorder.push(node)

  # Reverse for RPO
  rpo = []
  i = postorder.size() - 1
  while i >= 0
    rpo.push(postorder[i])
    i -= 1

  # Block → RPO index
  rpo_index = {}
  i = 0
  while i < rpo.size()
    rpo_index[rpo[i]] = i
    i += 1

  {order: rpo, index: rpo_index}

# Walk dominator tree up from a and b until they meet.

-> dom_intersect(idom, rpo_idx, a, b)
  fa = a
  fb = b
  while fa != fb
    while rpo_idx[fa] > rpo_idx[fb]
      fa = idom[fa]
    while rpo_idx[fb] > rpo_idx[fa]
      fb = idom[fb]
  fa

# Immediate dominators (Cooper-Harvey-Kennedy iterative algorithm).

-> compute_dominators(cfg)
  n = cfg[:num_blocks]
  rpo_data = compute_rpo(cfg)
  rpo = rpo_data[:order]
  rpo_idx = rpo_data[:index]

  # idom[entry] = entry, rest = -1
  idom = []
  i = 0
  while i < n
    idom.push(-1)
    i += 1
  idom[0] = 0

  changed = true
  while changed
    changed = false
    ri = 1
    while ri < rpo.size()
      b = rpo[ri]
      p = cfg[:preds][b]
      # First processed predecessor
      new_idom = -1
      pi = 0
      while pi < p.size()
        if idom[p[pi]] != -1
          new_idom = p[pi]
          break
        pi += 1
      # Intersect with other processed predecessors
      pi = 0
      while pi < p.size()
        if p[pi] != new_idom && idom[p[pi]] != -1
          new_idom = dom_intersect(idom, rpo_idx, new_idom, p[pi])
        pi += 1
      if new_idom != -1 && idom[b] != new_idom
        idom[b] = new_idom
        changed = true
      ri += 1

  idom

# Dominance frontiers from idom array.

-> compute_dominance_frontiers(cfg, idom)
  n = cfg[:num_blocks]
  df = {}
  df_seen = {}
  i = 0
  while i < n
    df[i] = []
    df_seen[i] = {}
    i += 1

  i = 0
  while i < n
    p = cfg[:preds][i]
    if p.size() >= 2
      pi = 0
      while pi < p.size()
        runner = p[pi]
        while runner != idom[i] && runner != -1
          if df_seen[runner][i] != true
            df_seen[runner][i] = true
            df[runner].push(i)
          runner = idom[runner]
        pi += 1
    i += 1

  df

# Loop back-edges: (a → b) where b dominates a.

-> find_loop_back_edges(cfg, idom)
  edges = []
  n = cfg[:num_blocks]
  i = 0
  while i < n
    s = cfg[:succs][i]
    si = 0
    while si < s.size()
      target = s[si]
      runner = i
      while runner != 0 && runner != target
        runner = idom[runner]
      if runner == target
        edges.push({header: target, tail: i})
      si += 1
    i += 1
  edges

# Full analysis for one function.

-> analyze_function(func)
  cfg = build_cfg(func)
  idom = compute_dominators(cfg)
  df = compute_dominance_frontiers(cfg, idom)
  # Loop back-edges had no consumer; keep the analysis shape stable without
  # walking every CFG edge and dominator chain solely to fill an unused key.
  {cfg: cfg, idom: idom, dominance_frontiers: df, loops: []}

# ── SSA Conversion (mem2reg) ──────────────────────────────────────────

# Identify var_slots that can be promoted to SSA registers.
# A slot is promotable if it's only accessed via store_i64 and load_i64
# (not via pointer operations like store_ptr, load_ptr, gep_array, or calls).

-> find_promotable_vars(func)
  slots = func[:var_slots]
  if slots == nil
    return {}
  # Don't promote vars in the top-level function (they have global stores)
  if func[:is_toplevel] == true
    return {}
  # Start assuming all are promotable
  promotable = {}
  slot_names = slots.keys().sort()
  si = 0
  while si < slot_names.size()
    name = slot_names[si]
    ptr = slots[name]
    slot_type = nil
    if func[:var_slot_types] != nil
      slot_type = func[:var_slot_types][name]
    if name.starts_with?("__sc_result.")
      promotable[ptr] = false
    elsif ptr.starts_with?("%v") && (slot_type == nil || slot_type == "i64")
      promotable[ptr] = true
    si += 1

  # Scan all instructions for non-load/store uses of slot pointers
  bi = 0
  while bi < func[:blocks].size()
    instrs = func[:blocks][bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      op = inst[:op]
      # store_i64 and load_i64 are OK — skip them
      if op != :store_i64 && op != :load_i64
        # Check if any slot pointer appears in any field of this instruction
        if op == :store_ptr && promotable[inst[:dest]] == true
          promotable[inst[:dest]] = false
        if op == :load_ptr && promotable[inst[:ptr]] == true
          promotable[inst[:ptr]] = false
        if op == :ptr_to_i64 && promotable[inst[:value]] == true
          promotable[inst[:value]] = false
        # Call args: if a slot pointer is passed, it's address-taken
        if inst[:args] != nil
          ai = 0
          while ai < inst[:args].size()
            if promotable[inst[:args][ai]] == true
              promotable[inst[:args][ai]] = false
            ai += 1
      ii += 1
    bi += 1

  # Return set of promotable pointer names
  result = {}
  slot_names = slots.keys().sort()
  si = 0
  while si < slot_names.size()
    ptr = slots[slot_names[si]]
    if promotable[ptr] == true
      result[ptr] = slot_names[si]
    si += 1
  result

# Find which blocks define (store to) each promotable variable.

-> find_var_defs(func, promotable)
  defs = {}  # ptr → [block_index, ...]
  bi = 0
  while bi < func[:blocks].size()
    instrs = func[:blocks][bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      if inst[:op] == :store_i64
        if promotable[inst[:ptr]] != nil
          ptr = inst[:ptr]
          if defs[ptr] == nil
            defs[ptr] = []
          defs[ptr].push(bi)
      ii += 1
    bi += 1
  defs

# Place phi nodes at dominance frontiers for each variable.
# Returns phi_placements: block_index → [{ptr, temp}, ...]

-> place_phi_nodes(func, promotable, var_defs, df)
  placements = {}  # block_index → [ptr, ...]
  ptrs = promotable.keys().sort()
  pi = 0
  while pi < ptrs.size()
    ptr = ptrs[pi]
    vd = var_defs[ptr]
    if vd != nil
      vd_set = {}
      # Worklist: blocks that define this var
      worklist = []
      di = 0
      while di < vd.size()
        worklist.push(vd[di])
        vd_set[vd[di]] = true
        di += 1
      placed = {}  # blocks where phi already placed
      wi = 0
      while wi < worklist.size()
        block_idx = worklist[wi]
        frontiers = df[block_idx]
        if frontiers != nil
          fi = 0
          while fi < frontiers.size()
            fb = frontiers[fi]
            if placed[fb] != true
              placed[fb] = true
              if placements[fb] == nil
                placements[fb] = []
              placements[fb].push(ptr)
              # If this block didn't already define the var, add to worklist
              if vd_set[fb] != true
                worklist.push(fb)
            fi += 1
        wi += 1
    pi += 1
  placements

# Rename variables: walk dominator tree, replace store/load with SSA values.
# Inserts phi_ssa instructions at block starts and fills in incoming values.

-> ssa_rename(func, cfg_analysis, promotable, phi_placements)
  cfg = cfg_analysis[:cfg]
  idom = cfg_analysis[:idom]
  blocks = func[:blocks]
  n = blocks.size()
  rename_profile = nil
  if cfg_analysis[:ssa_rename_profile] != nil
    rename_profile = cfg_analysis[:ssa_rename_profile]

  # Build dominator tree children (for DFS traversal)
  setup_started_at = nil
  if rename_profile != nil
    setup_started_at = clock()
  dom_children = {}
  i = 0
  while i < n
    dom_children[i] = []
    i += 1
  i = 1
  while i < n
    if idom[i] != -1 && idom[i] != i
      dom_children[idom[i]].push(i)
    i += 1

  # current_def[ptr] = stack of current SSA values
  current_def = {}
  ptrs = promotable.keys().sort()
  pi = 0
  while pi < ptrs.size()
    current_def[ptrs[pi]] = []
    pi += 1

  # phi_temps[block_index] = {ptr → temp_name}
  phi_temps = {}

  # Pre-assign temps for all phi nodes
  bi = 0
  while bi < n
    if phi_placements[bi] != nil
      phi_temps[bi] = {}
      pphi = phi_placements[bi]
      ppi = 0
      while ppi < pphi.size()
        ptr = pphi[ppi]
        temp = next_temp(func)
        phi_temps[bi][ptr] = temp
        ppi += 1
    bi += 1
  if rename_profile != nil
    rename_profile[:setup_secs] = rename_profile[:setup_secs] + (clock() - setup_started_at)

  # phi_incoming[block_index] = {ptr → [value, label, value, label, ...]}
  phi_incoming = {}

  # Function-wide load-elimination subst (temp → replacement value).
  # SSA temp names are unique within a function and are only defined once,
  # so a substitution recorded in any block remains valid for every other
  # block. Lowering may capture a load's temp name and reference it in a
  # later block (e.g. `receiver_reg` for an array iter passed into the body
  # block); without function-wide substitution, the cross-block use stays
  # as the eliminated load's name and LLVM verifier rejects with
  # "use of undefined value '%tN'".
  subst = {}
  subst_count = 0

  # DFS walk of dominator tree (iterative)
  # Stack entries: [block_index, phase]
  # phase 0: process block, push children
  # phase 1: pop definitions (restore stacks)
  stack = [[0, 0]]
  stack_push_counts = {}  # block_index → {ptr → push_count}
  visited = {}

  while stack.size() > 0
    top = stack[stack.size() - 1]
    block_idx = top[0]
    phase = top[1]

    if phase == 1
      # Restore definition stacks
      restore_started_at = nil
      if rename_profile != nil
        restore_started_at = clock()
      stack.pop()
      pushes = stack_push_counts[block_idx]
      if pushes != nil
        dptrs = pushes.keys().sort()
        di = 0
        while di < dptrs.size()
          dp = dptrs[di]
          to_pop = pushes[dp]
          while to_pop > 0
            current_def[dp].pop()
            to_pop -= 1
          di += 1
      if rename_profile != nil
        rename_profile[:restore_secs] = rename_profile[:restore_secs] + (clock() - restore_started_at)
      next

    # Phase 0: process this block
    if visited[block_idx] == true
      stack.pop()
      next
    top[1] = 1  # mark for phase 1 on return
    visited[block_idx] = true

    pushes = {}
    stack_push_counts[block_idx] = pushes

    # Push phi definitions
    if phi_temps[block_idx] != nil
      pphi = phi_placements[block_idx]
      ppi = 0
      while ppi < pphi.size()
        ptr = pphi[ppi]
        temp = phi_temps[block_idx][ptr]
        current_def[ptr].push(temp)
        pushes[ptr] = 1
        ppi += 1

    # Process instructions: replace stores and loads with direct substitution.
    # The substitution map is function-wide (declared above the DFS) so
    # cross-block uses of eliminated load temps get rewritten when those
    # blocks are visited.
    instrs = blocks[block_idx][:instructions]
    new_instrs = []
    instrs_started_at = nil
    if rename_profile != nil
      instrs_started_at = clock()
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      # Apply pending substitutions to this instruction
      if subst_count > 0
        inst = apply_subst(inst, subst, subst_count)
      op = inst[:op]

      if op == :store_i64 && promotable[inst[:ptr]] != nil
        # Store to promotable var: push new definition, skip instruction
        ptr = inst[:ptr]
        current_def[ptr].push(inst[:value])
        push_count = pushes[ptr]
        if push_count == nil
          pushes[ptr] = 1
        else
          pushes[ptr] = push_count + 1
      elsif op == :load_i64 && promotable[inst[:ptr]] != nil
        # Load from promotable var: substitute directly, skip instruction
        ptr = inst[:ptr]
        def_stack = current_def[ptr]
        if def_stack.size() > 0
          subst[inst[:temp]] = def_stack[def_stack.size() - 1]
        else
          subst[inst[:temp]] = w_nil.to_s()
        subst_count += 1
      else
        new_instrs.push(inst)
      ii += 1
    if rename_profile != nil
      rename_profile[:instr_secs] = rename_profile[:instr_secs] + (clock() - instrs_started_at)

    blocks[block_idx][:instructions] = new_instrs

    # Fill in phi incoming values for successor blocks
    successors = cfg[:succs][block_idx]
    incoming_started_at = nil
    if rename_profile != nil
      incoming_started_at = clock()
    si = 0
    while si < successors.size()
      succ = successors[si]
      if phi_temps[succ] != nil
        if phi_incoming[succ] == nil
          phi_incoming[succ] = {}
        pphi = phi_placements[succ]
        ppi = 0
        while ppi < pphi.size()
          ptr = pphi[ppi]
          def_stack = current_def[ptr]
          val = w_nil.to_s()
          if def_stack.size() > 0
            val = def_stack[def_stack.size() - 1]
          if phi_incoming[succ][ptr] == nil
            phi_incoming[succ][ptr] = []
          phi_incoming[succ][ptr].push(val)
          phi_incoming[succ][ptr].push(blocks[block_idx][:label])
          ppi += 1
      si += 1
    if rename_profile != nil
      rename_profile[:incoming_secs] = rename_profile[:incoming_secs] + (clock() - incoming_started_at)

    # Push children in reverse order (so leftmost child is processed first)
    children = dom_children[block_idx]
    ci = children.size() - 1
    while ci >= 0
      child = children[ci]
      if visited[child] != true
        stack.push([child, 0])
      ci -= 1

  # Conservatively rewrite any unreachable blocks too. They are outside the
  # dominator walk, so leaving promotable load/store pairs behind would make
  # the emitter skip allocas while still emitting raw %vN references.
  # Uses a separate per-block subst (`u_subst`) — unreachable blocks can't
  # observe the function-wide subst from the DFS path, and any temps they
  # reference would be undefined anyway.
  bi = 0
  while bi < n
    if visited[bi] != true
      instrs = blocks[bi][:instructions]
      new_instrs = []
      u_subst = {}
      u_subst_count = 0
      local_defs = {}
      ii = 0
      while ii < instrs.size()
        inst = instrs[ii]
        if u_subst_count > 0
          inst = apply_subst(inst, u_subst, u_subst_count)
        op = inst[:op]
        if op == :store_i64 && promotable[inst[:ptr]] != nil
          local_defs[inst[:ptr]] = inst[:value]
        elsif op == :load_i64 && promotable[inst[:ptr]] != nil
          val = local_defs[inst[:ptr]]
          if val == nil
            val = w_nil.to_s()
          u_subst[inst[:temp]] = val
          u_subst_count += 1
        else
          new_instrs.push(inst)
        ii += 1
      blocks[bi][:instructions] = new_instrs
    bi += 1

  # Insert phi_ssa instructions at block starts (validate incoming count)
  emit_phi_started_at = nil
  if rename_profile != nil
    emit_phi_started_at = clock()
  bi = 0
  while bi < n
    if phi_temps[bi] != nil
      pphi = phi_placements[bi]
      pred_count = cfg[:preds][bi].size()
      phi_instrs = []
      ppi = 0
      while ppi < pphi.size()
        ptr = pphi[ppi]
        temp = phi_temps[bi][ptr]
        incoming = []
        if phi_incoming[bi] != nil && phi_incoming[bi][ptr] != nil
          incoming = phi_incoming[bi][ptr]
        # Always emit phi if there are incoming values
        if incoming.size() > 0
          phi_instrs.push({op: :phi_ssa, temp: temp, incoming: incoming})
        ppi += 1
      # Prepend phi instructions before existing block instructions
      old_instrs = blocks[bi][:instructions]
      new_block_instrs = []
      pii = 0
      while pii < phi_instrs.size()
        new_block_instrs.push(phi_instrs[pii])
        pii += 1
      oii = 0
      while oii < old_instrs.size()
        new_block_instrs.push(old_instrs[oii])
        oii += 1
      blocks[bi][:instructions] = new_block_instrs
    bi += 1
  if rename_profile != nil
    rename_profile[:emit_phi_secs] = rename_profile[:emit_phi_secs] + (clock() - emit_phi_started_at)

  # Mark promoted vars so emitter skips their allocas
  func[:promoted_vars] = promotable

# Top-level SSA conversion entry point.

-> ssa_convert(func, cfg_analysis, profile = nil, precomputed_promotable = nil)
  promotable = precomputed_promotable
  if promotable == nil
    # Standalone callers retain the original safety checks. The main compiler
    # precomputes these before building the otherwise-unneeded CFG.
    if has_overflow_checked(func)
      return nil
    promotable_started_at = nil
    if profile != nil
      promotable_started_at = clock()
    promotable = find_promotable_vars(func)
    if profile != nil
      profile[:promotable_secs] = profile[:promotable_secs] + (clock() - promotable_started_at)
  if promotable.keys().size() == 0
    return nil
  if profile != nil
    profile[:ssa_functions] = profile[:ssa_functions] + 1
    profile[:promotable_var_count] = profile[:promotable_var_count] + promotable.keys().size()
  var_defs_started_at = nil
  if profile != nil
    var_defs_started_at = clock()
  var_defs = find_var_defs(func, promotable)
  if profile != nil
    profile[:var_defs_secs] = profile[:var_defs_secs] + (clock() - var_defs_started_at)
  df = cfg_analysis[:dominance_frontiers]
  phi_started_at = nil
  if profile != nil
    phi_started_at = clock()
  phi_placements = place_phi_nodes(func, promotable, var_defs, df)

  # This mem2reg pass is intentionally conservative: the rename step can
  # substitute straight-line load/store traffic safely, but phi placement is
  # not yet live-in pruned. If a slot needs a merge phi, leave that slot in
  # memory until the phi pass grows proper liveness; otherwise a phi temp can
  # be pushed as the current def and later skipped during emission.
  if phi_placements.keys().size() > 0
    phi_ptrs = {}
    phi_blocks = phi_placements.keys()
    pbi = 0
    while pbi < phi_blocks.size()
      pptrs = phi_placements[phi_blocks[pbi]]
      ppi = 0
      while ppi < pptrs.size()
        phi_ptrs[pptrs[ppi]] = true
        ppi += 1
      pbi += 1

    pruned = {}
    pkeys = promotable.keys().sort()
    pi = 0
    while pi < pkeys.size()
      ptr = pkeys[pi]
      if phi_ptrs[ptr] != true
        pruned[ptr] = promotable[ptr]
      pi += 1

    promotable = pruned
    if promotable.keys().size() == 0
      return nil

    # Phi placement is independent per variable. Every variable with a phi
    # was just removed, so the retained set cannot acquire a new placement;
    # rescanning definitions/frontiers only rediscovers the empty set.
    phi_placements = {}

  if profile != nil
    profile[:phi_secs] = profile[:phi_secs] + (clock() - phi_started_at)
    phi_blocks = phi_placements.keys().sort()
    profile[:phi_block_count] = profile[:phi_block_count] + phi_blocks.size()
    pbi = 0
    while pbi < phi_blocks.size()
      profile[:phi_count] = profile[:phi_count] + phi_placements[phi_blocks[pbi]].size()
      pbi += 1
  # Debug: log phi placements for functions with promotable vars
  rename_started_at = nil
  if profile != nil
    if profile[:rename_profile] == nil
      profile[:rename_profile] = {
        setup_secs: 0,
        restore_secs: 0,
        instr_secs: 0,
        incoming_secs: 0,
        emit_phi_secs: 0
      }
    cfg_analysis[:ssa_rename_profile] = profile[:rename_profile]
    rename_started_at = clock()
  ssa_rename(func, cfg_analysis, promotable, phi_placements)
  if profile != nil
    profile[:rename_secs] = profile[:rename_secs] + (clock() - rename_started_at)
    cfg_analysis[:ssa_rename_profile] = nil
  nil
