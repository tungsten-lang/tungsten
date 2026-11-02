# Regex AST analysis, bytecode compiler, jump/split optimization, and prefilter construction.
# Included by core/regex.w after core/regex/unicode.w.

-> __regex_emit(op_in, a_in, b_in, emit_ctx_in, emit_state_in)
  emit_ctx = emit_ctx_in ## Array
  emit_state = emit_state_in ## i64[]
  id = emit_state[0] ## i64
  ops = emit_ctx[0] ## i64[]
  if id >= ops.size()
    cap = (ops.size() * 2) ## i64
    ops2 = i64[cap]
    aa2 = i64[cap]
    bb2 = i64[cap]
    aa0 = emit_ctx[1] ## i64[]
    bb0 = emit_ctx[2] ## i64[]
    i = 0 ## i64
    while i < id
      ops2[i] = ops[i]
      aa2[i] = aa0[i]
      bb2[i] = bb0[i]
      i = i + 1
    emit_ctx[0] = ops2
    emit_ctx[1] = aa2
    emit_ctx[2] = bb2
    ops = ops2
  aa = emit_ctx[1] ## i64[]
  bb = emit_ctx[2] ## i64[]
  ops[id] = op_in ## i64
  aa[id] = a_in ## i64
  bb[id] = b_in ## i64
  emit_state[0] = id + 1
  id

-> __regex_set_split(s_in, pref_in, alt_in, greedy, emit_ctx_in)
  emit_ctx = emit_ctx_in ## Array
  s = s_in ## i64
  pref = pref_in ## i64
  alt = alt_in ## i64
  aa = emit_ctx[1] ## i64[]
  bb = emit_ctx[2] ## i64[]
  if greedy
    aa[s] = pref
    bb[s] = alt
  else
    aa[s] = alt
    bb[s] = pref

-> __regex_single_consuming(node_in, ast_k_in)
  node = node_in ## i64
  if node < 0
    return false
  ast_k = ast_k_in ## i64[]
  k = ast_k[node] ## i64
  k == 1 || k == 2 || k == 3 || k == 4 || k == 5 || k == 21 || k == 22

-> __regex_compile_node(node_in, emit_ctx_in, emit_state_in, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  node = node_in ## i64
  if node < 0
    return nil
  emit_ctx = emit_ctx_in ## Array
  emit_state = emit_state_in ## i64[]
  ast_k = ast_k_in ## i64[]
  ast_a = ast_a_in ## i64[]
  ast_b = ast_b_in ## i64[]
  ast_c = ast_c_in ## i64[]
  ast_next = ast_next_in ## i64[]
  k = ast_k[node] ## i64
  a = ast_a[node] ## i64
  b = ast_b[node] ## i64
  c = ast_c[node] ## i64
  if k == 1
    __regex_emit(1, a, 0, emit_ctx, emit_state)
  elsif k == 2
    __regex_emit(18, a, b, emit_ctx, emit_state)
  elsif k == 3
    __regex_emit(19, a, b, emit_ctx, emit_state)
  elsif k == 4
    __regex_emit(2, a == 1 ? -1 : (nl_in ## i64), 0, emit_ctx, emit_state)
  elsif k == 21
    __regex_emit(11, a, b, emit_ctx, emit_state)
  elsif k == 22
    __regex_emit(17, a, b, emit_ctx, emit_state)
  elsif k == 5
    __regex_emit(3, a, 0, emit_ctx, emit_state)
  elsif k == 6
    __regex_emit(8, 0, 0, emit_ctx, emit_state)
  elsif k == 7
    __regex_emit(9, 0, 0, emit_ctx, emit_state)
  elsif k == 8
    __regex_emit(20, a, 0, emit_ctx, emit_state)
  elsif k == 9
    __regex_emit(7, 0, 0, emit_ctx, emit_state)
  elsif k == 10
    __regex_emit(24, a, 0, emit_ctx, emit_state)
  elsif k == 11
    g = __regex_resolve_group_ref(a, ngroup_in, ref_names_in, group_names_in) ## i64
    if g <= 0
      raise "invalid backreference group"
    __regex_emit(21, g, ignore_case ? 1 : 0, emit_ctx, emit_state)
  elsif k == 12
    g = __regex_resolve_group_ref(a, ngroup_in, ref_names_in, group_names_in) ## i64
    call_pc = __regex_emit(22, 0, g, emit_ctx, emit_state)
    subcalls = emit_ctx[3] ## Array
    subcalls.push([call_pc, g])
  elsif k == 13
    __regex_emit(10, a, 0, emit_ctx, emit_state)
  elsif k == 14
    cur = a
    while cur >= 0
      __regex_compile_node(cur, emit_ctx, emit_state, ast_k, ast_a, ast_b, ast_c, ast_next, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
      cur = ast_next[cur] ## i64
  elsif k == 15
    if b >= 0
      __regex_emit(7, b * 2, 0, emit_ctx, emit_state)
      __regex_compile_node(a, emit_ctx, emit_state, ast_k, ast_a, ast_b, ast_c, ast_next, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
      __regex_emit(7, b * 2 + 1, 0, emit_ctx, emit_state)
    else
      __regex_compile_node(a, emit_ctx, emit_state, ast_k, ast_a, ast_b, ast_c, ast_next, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  elsif k == 23
    if b == 5
      ak = ast_k[a] ## i64
      if ak == 18 && ast_b[a] == 1 && __regex_single_consuming(ast_a[a], ast_k)
        __regex_compile_plus(ast_a[a], 2, emit_ctx, emit_state, ast_k, ast_a, ast_b, ast_c, ast_next, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
        return nil
      if ak == 17 && ast_b[a] == 1 && __regex_single_consuming(ast_a[a], ast_k)
        __regex_compile_star(ast_a[a], 2, emit_ctx, emit_state, ast_k, ast_a, ast_b, ast_c, ast_next, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
        return nil
    min_l = 0 ## i64
    max_e = 0 ## i64
    if b == 3 || b == 4
      bnds = __regex_ast_length_bounds(a, ast_k, ast_a, ast_b, ast_c, ast_next) ## i64
      min_l = bnds >> 16
      max_e = bnds & 65535
    enc = (min_l << 20) | (max_e << 4) | b
    apc = __regex_emit(25, 0, enc, emit_ctx, emit_state) ## i64
    __regex_compile_node(a, emit_ctx, emit_state, ast_k, ast_a, ast_b, ast_c, ast_next, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
    __regex_emit(26, (b == 3 || b == 4) ? 1 : 0, 0, emit_ctx, emit_state)
    aa_l = emit_ctx[1] ## i64[]
    aa_l[apc] = emit_state[0] ## i64
  elsif k == 16
    __regex_compile_alt(a, emit_ctx, emit_state, ast_k, ast_a, ast_b, ast_c, ast_next, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  elsif k == 17
    __regex_compile_star(a, b, emit_ctx, emit_state, ast_k, ast_a, ast_b, ast_c, ast_next, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  elsif k == 18
    __regex_compile_plus(a, b, emit_ctx, emit_state, ast_k, ast_a, ast_b, ast_c, ast_next, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  elsif k == 19
    __regex_compile_opt(a, b != 0, emit_ctx, emit_state, ast_k, ast_a, ast_b, ast_c, ast_next, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  elsif k == 20
    __regex_compile_rep(a, b, c, emit_ctx, emit_state, ast_k, ast_a, ast_b, ast_c, ast_next, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)

-> __regex_compile_alt(head_in, emit_ctx_in, emit_state_in, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  emit_ctx = emit_ctx_in ## Array
  emit_state = emit_state_in ## i64[]
  cur = head_in ## i64
  ast_next = ast_next_in ## i64[]
  nxt = ast_next[cur] ## i64
  if nxt < 0
    __regex_compile_node(cur, emit_ctx, emit_state, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
    return nil
  s = __regex_emit(6, 0, 0, emit_ctx, emit_state) ## i64
  aa_a = emit_ctx[1] ## i64[]
  aa_a[s] = emit_state[0] ## i64
  __regex_compile_node(cur, emit_ctx, emit_state, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  j = __regex_emit(5, 0, 0, emit_ctx, emit_state) ## i64
  bb_a = emit_ctx[2] ## i64[]
  bb_a[s] = emit_state[0] ## i64
  __regex_compile_alt(nxt, emit_ctx, emit_state, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  aa_a = emit_ctx[1] ## i64[]
  aa_a[j] = emit_state[0] ## i64

-> __regex_compile_star(child, mode_in, emit_ctx_in, emit_state_in, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  emit_ctx = emit_ctx_in ## Array
  emit_state = emit_state_in ## i64[]
  mode = mode_in ## i64
  greedy = mode != 0
  if __regex_single_consuming(child, ast_k_in)
    op = 14
    if mode == 0
      op = 15
    elsif mode == 2
      op = 16
    rep = __regex_emit(op, 0, 0, emit_ctx, emit_state) ## i64
    body = emit_state[0] ## i64
    __regex_compile_node(child, emit_ctx, emit_state, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
    aa_r = emit_ctx[1] ## i64[]
    bb_r = emit_ctx[2] ## i64[]
    aa_r[rep] = body
    bb_r[rep] = emit_state[0] ## i64
    return nil
  if __regex_nullable(child, ast_k_in, ast_a_in, ast_b_in, ast_next_in)
    g = emit_state[1] ## i64
    emit_state[1] = g + 1
    l1 = emit_state[0] ## i64
    s = __regex_emit(6, 0, 0, emit_ctx, emit_state) ## i64
    __regex_emit(12, g, 0, emit_ctx, emit_state)
    __regex_compile_node(child, emit_ctx, emit_state, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
    __regex_emit(13, g, 0, emit_ctx, emit_state)
    __regex_emit(5, l1, 0, emit_ctx, emit_state)
    l3 = emit_state[0] ## i64
    __regex_set_split(s, l1 + 1, l3, greedy, emit_ctx)
    return nil
  l1 = emit_state[0] ## i64
  s = __regex_emit(6, 0, 0, emit_ctx, emit_state) ## i64
  __regex_compile_node(child, emit_ctx, emit_state, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  __regex_emit(5, l1, 0, emit_ctx, emit_state)
  l3 = emit_state[0] ## i64
  __regex_set_split(s, l1 + 1, l3, greedy, emit_ctx)

-> __regex_compile_plus(child, mode_in, emit_ctx_in, emit_state_in, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  emit_ctx = emit_ctx_in ## Array
  emit_state = emit_state_in ## i64[]
  mode = mode_in ## i64
  if __regex_single_consuming(child, ast_k_in) || __regex_nullable(child, ast_k_in, ast_a_in, ast_b_in, ast_next_in)
    __regex_compile_node(child, emit_ctx, emit_state, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
    __regex_compile_star(child, mode, emit_ctx, emit_state, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
    return nil
  l1 = emit_state[0] ## i64
  __regex_compile_node(child, emit_ctx, emit_state, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  s = __regex_emit(6, 0, 0, emit_ctx, emit_state) ## i64
  __regex_set_split(s, l1, emit_state[0] ## i64, mode != 0, emit_ctx)

-> __regex_compile_opt(child, greedy, emit_ctx_in, emit_state_in, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  emit_ctx = emit_ctx_in ## Array
  emit_state = emit_state_in ## i64[]
  s = __regex_emit(6, 0, 0, emit_ctx, emit_state) ## i64
  l1 = emit_state[0] ## i64
  __regex_compile_node(child, emit_ctx, emit_state, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  __regex_set_split(s, l1, emit_state[0] ## i64, greedy, emit_ctx)

-> __regex_compile_rep(child_in, lo_in, c_enc_in, emit_ctx_in, emit_state_in, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  child = child_in ## i64
  lo = lo_in ## i64
  c_enc = c_enc_in ## i64
  greedy = (c_enc & 1) != 0
  hi = c_enc >> 1
  i = 0 ## i64
  while i < lo
    __regex_compile_node(child, emit_ctx_in, emit_state_in, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
    i = i + 1
  if hi < 0
    __regex_compile_star(child, greedy ? 1 : 0, emit_ctx_in, emit_state_in, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  else
    emit_ctx = emit_ctx_in ## Array
    emit_state = emit_state_in ## i64[]
    extra = hi - lo
    # Every optional exit ends the repetition, avoiding duplicate failure paths.
    splits = i64[extra]
    i = 0
    while i < extra
      split = __regex_emit(6, 0, 0, emit_ctx, emit_state) ## i64
      splits[i] = split
      first = emit_state[0] ## i64
      __regex_compile_node(child, emit_ctx, emit_state, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
      __regex_set_split(split, first, 0, greedy, emit_ctx)
      i += 1
    finish = emit_state[0] ## i64
    aa = emit_ctx[1] ## i64[]
    bb = emit_ctx[2] ## i64[]
    i = 0
    while i < extra
      if greedy
        bb[splits[i]] = finish
      else
        aa[splits[i]] = finish
      i += 1

-> __regex_compile_subroutines(emit_ctx_in, emit_state_in, group_asts_in, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
  emit_ctx = emit_ctx_in ## Array
  emit_state = emit_state_in ## i64[]
  subcalls = emit_ctx[3] ## Array
  ng = (ngroup_in ## i64) + 1
  sub_pcs = i64[ng]
  si = 0 ## i64
  while si < ng
    sub_pcs[si] = -1
    si = si + 1
  gasts = group_asts_in ## i64[]
  sci = 0 ## i64
  sc_len = subcalls.size() ## i64
  while sci < sc_len
    entry = subcalls[sci] ## Array
    call_pc = entry[0] ## i64
    g = entry[1] ## i64
    if sub_pcs[g] < 0
      sub_pcs[g] = emit_state[0] ## i64
      if g > 0
        __regex_emit(7, g * 2, 0, emit_ctx, emit_state)
        __regex_compile_node(gasts[g], emit_ctx, emit_state, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
        __regex_emit(7, g * 2 + 1, 0, emit_ctx, emit_state)
      else
        __regex_compile_node(gasts[0], emit_ctx, emit_state, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in, nl_in, ignore_case, ngroup_in, ref_names_in, group_names_in)
      __regex_emit(23, 0, 0, emit_ctx, emit_state)
    aa_s = emit_ctx[1] ## i64[]
    bb_s = emit_ctx[2] ## i64[]
    aa_s[call_pc] = sub_pcs[g]
    bb_s[call_pc] = g
    subcalls = emit_ctx[3] ## Array
    sc_len = subcalls.size() ## i64
    sci = sci + 1


-> __regex_ast_length_bounds(node_in, ast_k_in, ast_a_in, ast_b_in, ast_c_in, ast_next_in)
  node = node_in ## i64
  if node < 0
    return 0
  ast_k = ast_k_in ## i64[]
  ast_a = ast_a_in ## i64[]
  ast_b = ast_b_in ## i64[]
  ast_c = ast_c_in ## i64[]
  ast_next = ast_next_in ## i64[]
  k = ast_k[node] ## i64
  if k == 1 || k == 2 || k == 3 || k == 4 || k == 5 || k == 21 || k == 22
    return 65537
  if k == 6 || k == 7 || k == 8 || k == 13 || k == 9
    return 0
  if k == 23
    if ast_b[node] == 5
      return __regex_ast_length_bounds(ast_a[node], ast_k, ast_a, ast_b, ast_c, ast_next)
    return 0
  if k == 15
    return __regex_ast_length_bounds(ast_a[node], ast_k, ast_a, ast_b, ast_c, ast_next)
  if k == 14
    sum_min = 0 ## i64
    sum_max = 0 ## i64
    cur = ast_a[node] ## i64
    while cur >= 0
      cb = __regex_ast_length_bounds(cur, ast_k, ast_a, ast_b, ast_c, ast_next) ## i64
      cmin = cb >> 16
      cmax = cb & 65535
      sum_min = sum_min + cmin
      if sum_min > 65534
        sum_min = 65534
      if sum_max == 65535 || cmax == 65535
        sum_max = 65535
      else
        sum_max = sum_max + cmax
        if sum_max > 65534
          sum_max = 65535
      cur = ast_next[cur] ## i64
    return (sum_min << 16) | sum_max
  if k == 16
    cur = ast_a[node] ## i64
    if cur < 0
      return 0
    fb = __regex_ast_length_bounds(cur, ast_k, ast_a, ast_b, ast_c, ast_next) ## i64
    best_min = fb >> 16
    best_max = fb & 65535
    cur = ast_next[cur] ## i64
    while cur >= 0
      cb = __regex_ast_length_bounds(cur, ast_k, ast_a, ast_b, ast_c, ast_next) ## i64
      cmin = cb >> 16
      cmax = cb & 65535
      if cmin < best_min
        best_min = cmin
      if best_max == 65535 || cmax == 65535
        best_max = 65535
      elsif cmax > best_max
        best_max = cmax
      cur = ast_next[cur] ## i64
    return (best_min << 16) | best_max
  if k == 19
    cb = __regex_ast_length_bounds(ast_a[node], ast_k, ast_a, ast_b, ast_c, ast_next) ## i64
    return cb & 65535
  if k == 17
    return 65535
  if k == 18
    cb = __regex_ast_length_bounds(ast_a[node], ast_k, ast_a, ast_b, ast_c, ast_next) ## i64
    return ((cb >> 16) << 16) | 65535
  if k == 20
    cb = __regex_ast_length_bounds(ast_a[node], ast_k, ast_a, ast_b, ast_c, ast_next) ## i64
    cmin = cb >> 16
    cmax = cb & 65535
    lo = ast_b[node] ## i64
    hi = (ast_c[node] ## i64) >> 1
    rmin = lo * cmin
    if rmin > 65534
      rmin = 65534
    rmax = 65535 ## i64
    if hi >= 0 && cmax < 65535
      rmax = hi * cmax
      if rmax > 65534
        rmax = 65535
    return (rmin << 16) | rmax
  if k == 10
    return 131071
  65535

-> __regex_nullable(node_in, ast_k_in, ast_a_in, ast_b_in, ast_next_in)
  node = node_in ## i64
  if node < 0
    return true
  ast_k = ast_k_in ## i64[]
  ast_a = ast_a_in ## i64[]
  ast_b = ast_b_in ## i64[]
  ast_next = ast_next_in ## i64[]
  k = ast_k[node] ## i64
  if k == 1 || k == 2 || k == 3 || k == 4 || k == 5 || k == 21 || k == 22 || k == 10
    return false
  if k == 17 || k == 19
    return true
  if k == 6 || k == 7 || k == 13 || k == 8 || k == 9 || k == 11 || k == 12
    return true
  if k == 23
    if ast_b[node] == 5
      return __regex_nullable(ast_a[node], ast_k, ast_a, ast_b, ast_next)
    return true
  if k == 18 || k == 15
    return __regex_nullable(ast_a[node], ast_k, ast_a, ast_b, ast_next)
  if k == 14
    cur = ast_a[node] ## i64
    while cur >= 0
      if !__regex_nullable(cur, ast_k, ast_a, ast_b, ast_next)
        return false
      cur = ast_next[cur] ## i64
    return true
  if k == 16
    cur = ast_a[node] ## i64
    while cur >= 0
      if __regex_nullable(cur, ast_k, ast_a, ast_b, ast_next)
        return true
      cur = ast_next[cur] ## i64
    return false
  if k == 20
    return ast_b[node] == 0 || __regex_nullable(ast_a[node], ast_k, ast_a, ast_b, ast_next)
  false

-> __regex_find_required_lit(node_in, ast_k_in, ast_a_in, ast_b_in, ast_next_in)
  node = node_in ## i64
  if node < 0
    return -1
  ast_k = ast_k_in ## i64[]
  ast_a = ast_a_in ## i64[]
  ast_b = ast_b_in ## i64[]
  ast_next = ast_next_in ## i64[]
  k = ast_k[node] ## i64
  if k == 1
    return ast_a[node]
  if k == 15 || k == 18
    return __regex_find_required_lit(ast_a[node], ast_k, ast_a, ast_b, ast_next)
  if k == 23 && (ast_b[node] == 1 || ast_b[node] == 5)
    return __regex_find_required_lit(ast_a[node], ast_k, ast_a, ast_b, ast_next)
  if k == 20 && ast_b[node] >= 1
    return __regex_find_required_lit(ast_a[node], ast_k, ast_a, ast_b, ast_next)
  if k == 14
    cur = ast_a[node] ## i64
    best = -1 ## i64
    while cur >= 0
      r = __regex_find_required_lit(cur, ast_k, ast_a, ast_b, ast_next) ## i64
      if r >= 0
        best = r
      cur = ast_next[cur] ## i64
    return best
  -1

-> __regex_branch_can_start_with(pc_in, ch_in, depth_in, ops_in, args_a_in, branches_in)
  depth = depth_in ## i64
  if depth > 8
    return true
  ops = ops_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  op_n = ops.size() ## i64
  pc = pc_in ## i64
  ch = ch_in ## i64
  while pc < op_n
    op = ops[pc] ## i64
    if op == 7 || op == 12 || op == 13
      pc = pc + 1
    elsif op == 5
      pc = args_a[pc] ## i64
    elsif op == 1
      return args_a[pc] == ch
    elsif op == 18
      return args_a[pc] == ch || branches[pc] == ch
    elsif op == 17
      return ch >= args_a[pc] && ch <= branches[pc]
    elsif op == 11
      if branches[pc] == 0
        return (ch & args_a[pc]) != 0
      return (ch & args_a[pc]) == 0
    elsif op == 6 || op == 27
      tpc_b = args_a[pc] ## i64
      top_b = ops[tpc_b] ## i64
      if top_b == 1
        if args_a[tpc_b] == ch
          return true
      elsif top_b == 18
        if args_a[tpc_b] == ch || branches[tpc_b] == ch
          return true
      elsif __regex_branch_can_start_with(tpc_b, ch, depth + 1, ops, args_a, branches)
        return true
      pc = branches[pc] ## i64
    else
      return true
  true

-> __regex_can_upgrade_rep_nb(tpc_in, npc_in, depth_in, ops_in, args_a_in, branches_in, nl_in, cls_bm_in, classes_in)
  if depth_in > 4
    return false
  ops = ops_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  tpc = tpc_in ## i64
  npc = npc_in ## i64
  while npc < ops.size() && ops[npc] == 7 && args_a[npc] != 0
    npc = npc + 1
  if npc >= ops.size()
    return false
  nop = ops[npc] ## i64
  if nop == 4 || (nop == 26 && args_a[npc] == 0)
    return true
  if nop == 20 && args_a[npc] == 2
    return true
  if nop == 9 && !__regex_consume_at(tpc, nl_in, ops, args_a, branches, cls_bm_in, classes_in)
    return true
  if nop == 1
    return !__regex_consume_at(tpc, args_a[npc], ops, args_a, branches, cls_bm_in, classes_in)
  if nop == 18
    return !__regex_consume_at(tpc, args_a[npc], ops, args_a, branches, cls_bm_in, classes_in) && !__regex_consume_at(tpc, branches[npc], ops, args_a, branches, cls_bm_in, classes_in)
  if nop == 25 && (branches[npc] & 15) == 1 && npc + 1 < ops.size() && ops[npc + 1] == 1
    return !__regex_consume_at(tpc, args_a[npc + 1], ops, args_a, branches, cls_bm_in, classes_in)
  if nop == 11 && branches[npc] == 0 && ops[tpc] == 11 && branches[tpc] == 0
    m1 = args_a[tpc] ## i64
    m2 = args_a[npc] ## i64
    return (m1 & m2) == 0 && ((m1 | m2) & 4) != 0
  if nop == 6
    return __regex_can_upgrade_rep_nb(tpc, args_a[npc], depth_in + 1, ops, args_a, branches, nl_in, cls_bm_in, classes_in) && __regex_can_upgrade_rep_nb(tpc, branches[npc], depth_in + 1, ops, args_a, branches, nl_in, cls_bm_in, classes_in)
  false

-> __regex_collect_second_ascii(pc_in, depth_in, bm_in, ops_in, args_a_in, branches_in)
  depth = depth_in ## i64
  if depth > 16
    return false
  ops = ops_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  bm = bm_in ## i64[]
  op_n = ops.size() ## i64
  pc = pc_in ## i64
  while pc < op_n
    op = ops[pc] ## i64
    if op == 7
      pc = pc + 1
    elsif op == 5
      pc = args_a[pc] ## i64
    elsif op == 6 || op == 27
      if !__regex_collect_second_ascii(args_a[pc], depth + 1, bm, ops, args_a, branches)
        return false
      pc = branches[pc] ## i64
    elsif op == 1 || op == 18
      pc2 = pc + 1
      while pc2 < op_n && (ops[pc2] == 7 || ops[pc2] == 5)
        if ops[pc2] == 5
          pc2 = args_a[pc2] ## i64
        else
          pc2 = pc2 + 1
      if pc2 >= op_n
        return false
      op2 = ops[pc2] ## i64
      one = 1 ## i64
      if op2 == 1
        cp2 = (args_a[pc2] >> 25) & 2097151
        if cp2 >= 128
          return false
        blk2 = 4 + (cp2 >> 5)
        bm[blk2] = bm[blk2] | (one << (cp2 & 31))
        return true
      if op2 == 18
        cp2a = (args_a[pc2] >> 25) & 2097151
        cp2b = (branches[pc2] >> 25) & 2097151
        if cp2a >= 128 || cp2b >= 128
          return false
        blk2a = 4 + (cp2a >> 5)
        blk2b = 4 + (cp2b >> 5)
        bm[blk2a] = bm[blk2a] | (one << (cp2a & 31))
        bm[blk2b] = bm[blk2b] | (one << (cp2b & 31))
        return true
      return false
    else
      return false
  false

-> __regex_optimize_ops(ops_in, args_a_in, branches_in, nl_in, cls_bm_in, classes_in)
  ops = ops_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  op_n = ops.size() ## i64
  jpc = (op_n - 1) ## i64
  while jpc >= 0
    jop = ops[jpc] ## i64
    if jop == 5
      jt = args_a[jpc] ## i64
      while jt < op_n && ops[jt] == 5 && args_a[jt] != jt
        jt = args_a[jt] ## i64
      args_a[jpc] = jt
    elsif jop == 6
      jt = args_a[jpc] ## i64
      while jt < op_n && ops[jt] == 5 && args_a[jt] != jt
        jt = args_a[jt] ## i64
      args_a[jpc] = jt
      jb = branches[jpc] ## i64
      while jb < op_n && ops[jb] == 5 && args_a[jb] != jb
        jb = args_a[jb] ## i64
      branches[jpc] = jb
    jpc = jpc - 1
  opc = 0 ## i64
  while opc < op_n
    if ops[opc] == 14
      if __regex_can_upgrade_rep_nb(args_a[opc], branches[opc], 0, ops, args_a, branches, nl_in, cls_bm_in, classes_in)
        ops[opc] = 16
    elsif ops[opc] == 6 && args_a[opc] > opc && branches[opc] > opc
      tpc_s = args_a[opc] ## i64
      bpc_s = branches[opc] ## i64
      top_s = ops[tpc_s] ## i64
      if top_s == 1 && !__regex_branch_can_start_with(bpc_s, args_a[tpc_s], 0, ops, args_a, branches)
        ops[opc] = 27
      elsif top_s == 18 && !__regex_branch_can_start_with(bpc_s, args_a[tpc_s], 0, ops, args_a, branches) && !__regex_branch_can_start_with(bpc_s, branches[tpc_s], 0, ops, args_a, branches)
        ops[opc] = 27
    opc = opc + 1
  nil

-> __regex_analyze_linear_mode(ops_in, args_a_in, branches_in, has_subcall)
  if has_subcall
    return 0
  ops = ops_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  op_n = ops.size() ## i64
  linear = 1 ## i64
  nsplit = 0 ## i64
  nsave = 0 ## i64
  n_rep_g = 0 ## i64
  save_after_rep_g = false
  has_back_jmp = false
  has_bref = false
  has_assert = false
  lpc = 0 ## i64
  while lpc < op_n
    lop = ops[lpc] ## i64
    if lop == 15 || lop == 12 || lop == 22 || lop == 23 || lop == 24 || lop == 26
      linear = 0
    elsif lop == 14
      n_rep_g = n_rep_g + 1
    elsif lop == 25
      tpc_l = args_a[lpc] ## i64
      kind_l = (branches[lpc] & 15) ## i64
      if kind_l >= 1 && kind_l <= 4 && ((tpc_l == lpc + 3 && ops[lpc + 1] == 1 && ops[lpc + 2] == 26) || (tpc_l == lpc + 4 && ops[lpc + 1] == 1 && ops[lpc + 2] == 1 && ops[lpc + 3] == 26))
        has_assert = true
        lpc = tpc_l - 1
      else
        linear = 0
    elsif lop == 21
      has_bref = true
    elsif lop == 5 && args_a[lpc] <= lpc
      linear = 0
    elsif lop == 6
      if args_a[lpc] <= lpc || branches[lpc] <= lpc
        has_back_jmp = true
      nsplit = nsplit + 1
    elsif lop == 7
      nsave = nsave + 1
      if n_rep_g > 0 && (lpc != op_n - 2 || args_a[lpc] != 1)
        save_after_rep_g = true
    lpc = lpc + 1
  if n_rep_g > 1 || save_after_rep_g
    linear = 0
  elsif n_rep_g == 1 && (nsplit > 0 || has_back_jmp || has_bref || has_assert)
    linear = 0
  elsif linear == 1 && (nsplit > 0 || has_back_jmp || has_bref)
    if !has_assert && nsplit <= 16 && nsave <= 6
      linear = 2
    else
      linear = 0
  linear

-> __regex_detect_flag_exact_match(ops_in, args_a_in, branches_in, lit_anchored_in, lead_rep_nb_in, linear_in, ncap_in)
  ops = ops_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  op_n = ops.size() ## i64
  lit_anchored = lit_anchored_in ## i64
  lead_rep_nb = lead_rep_nb_in ## i64
  linear = linear_in ## i64
  ncap = ncap_in ## i64
  exact = 0 ## i64
  cap_fast = 0 ## i64
  if lit_anchored == 0 && (op_n == 4 || (lead_rep_nb == 1 && op_n == 6))
    exact = 1
  elsif lit_anchored == 0 && lead_rep_nb == 1 && op_n == 9 && ops[1] == 11 && branches[1] == 0 && ops[4] == 25 && args_a[4] == 7 && (branches[4] & 15) == 1 && ops[5] == 1 && ops[6] == 26 && args_a[6] == 0 && ops[7] == 7 && ops[8] == 4 && (args_a[5] & args_a[1]) == 0
    exact = 9
  elsif lit_anchored == 0 && lead_rep_nb == 1 && op_n == 10 && ops[1] == 11 && branches[1] == 0 && ops[4] == 25 && args_a[4] == 8 && (branches[4] & 15) == 2 && ops[5] == 1 && ops[6] == 1 && ops[7] == 26 && args_a[7] == 0 && ops[8] == 7 && ops[9] == 4
    exact = 10
  elsif lit_anchored == 0 && op_n == 10 && ops[0] == 7 && ops[1] == 25 && args_a[1] == 4 && (branches[1] & 15) == 4 && ops[2] == 1 && ops[3] == 26 && ops[4] == 10 && args_a[4] == 1 && ops[5] == 11 && args_a[5] == 1 && branches[5] == 0 && ops[6] == 16 && args_a[6] == 7 && branches[6] == 8 && ops[7] == 11 && args_a[7] == 1 && branches[7] == 0 && ops[8] == 7 && ops[9] == 4
    exact = 11
  elsif lit_anchored == 0 && lead_rep_nb == 1 && ops[1] == 11 && branches[1] == 0 && ops[4] == 1 && (args_a[4] & args_a[1]) == 0 && ops[5] == 11 && branches[5] == 0 && ((op_n == 8 && ops[6] == 7 && ops[7] == 4) || (op_n == 10 && ops[6] == 16 && args_a[6] == 7 && branches[6] == 8 && ops[7] == 11 && args_a[7] == args_a[5] && branches[7] == 0 && ops[8] == 7 && ops[9] == 4))
    exact = 15
  elsif lit_anchored == 0 && linear == 1 && op_n >= 5 && ops[0] == 7 && ops[op_n - 2] == 7 && ops[op_n - 1] == 4
    if ncap == 4 && op_n == 19 && ops[1] == 7 && args_a[1] == 2 && ops[2] == 11 && args_a[2] == 1 && branches[2] == 0 && ops[3] == 11 && args_a[3] == 1 && branches[3] == 0 && ops[4] == 11 && args_a[4] == 1 && branches[4] == 0 && ops[5] == 11 && args_a[5] == 1 && branches[5] == 0 && ops[6] == 7 && args_a[6] == 3 && ops[7] == 1 && ops[8] == 7 && args_a[8] == 4 && ops[9] == 11 && args_a[9] == 1 && branches[9] == 0 && ops[10] == 11 && args_a[10] == 1 && branches[10] == 0 && ops[11] == 7 && args_a[11] == 5 && ops[12] == 1 && ops[13] == 7 && args_a[13] == 6 && ops[14] == 11 && args_a[14] == 1 && branches[14] == 0 && ops[15] == 11 && args_a[15] == 1 && branches[15] == 0 && ops[16] == 7 && args_a[16] == 7 && args_a[17] == 1
      cap_fast = 2
    ok8 = true
    mi8 = 1 ## i64
    end8 = (op_n - 2) ## i64
    while mi8 < end8
      mop8 = ops[mi8] ## i64
      if mop8 != 1 && !(mop8 == 11 && branches[mi8] == 0)
        ok8 = false
        break
      mi8 = mi8 + 1
    if ok8
      exact = 8
  (cap_fast << 8) | exact

-> __regex_build_bm9_exact(pfs_buf_in, pfs_len_in, ops_in, args_a_in, branches_in, lit_anchored_in, linear_in)
  pfs_buf = pfs_buf_in ## i64[]
  pfs_len = pfs_len_in ## i64
  ops = ops_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  op_n = ops.size() ## i64
  bm0 = 0 ## i64
  bm1 = 0 ## i64
  bm2 = 0 ## i64
  bm3 = 0 ## i64
  one = 1 ## i64
  si = 0 ## i64
  while si < pfs_len
    scp = (pfs_buf[si] >> 25) & 2097151
    if scp >= 128
      return nil
    sh = scp & 31
    bit = one << sh
    blk = scp >> 5
    if blk == 0
      bm0 = bm0 | bit
    elsif blk == 1
      bm1 = bm1 | bit
    elsif blk == 2
      bm2 = bm2 | bit
    else
      bm3 = bm3 | bit
    si = si + 1
  bm9 = i64[41]
  bm9[0] = bm0
  bm9[1] = bm1
  bm9[2] = bm2
  bm9[3] = bm3
  bm9[4] = 0
  bm9[5] = 0
  bm9[6] = 0
  bm9[7] = 0
  bm9[40] = 0
  if __regex_collect_second_ascii(0, 0, bm9, ops, args_a, branches)
    exact = 0 ## i64
    if lit_anchored_in == 0 && linear_in == 1 && ops[0] == 7 && ops[op_n - 2] == 7 && ops[op_n - 1] == 4
      ok6 = true
      has1 = false
      has18 = false
      mi6 = 1 ## i64
      end6 = (op_n - 2) ## i64
      while mi6 < end6
        mop6 = ops[mi6] ## i64
        if mop6 == 27
          if args_a[mi6] != mi6 + 1
            ok6 = false
            break
        elsif mop6 == 5
          if args_a[mi6] != end6
            ok6 = false
            break
        elsif mop6 == 1
          has1 = true
        elsif mop6 == 18
          if (args_a[mi6] | 1074233368) != (branches[mi6] | 1074233368)
            ok6 = false
            break
          has18 = true
        else
          ok6 = false
          break
        mi6 = mi6 + 1
      if ok6 && (has1 != has18)
        b_idx = 8 ## i64
        while b_idx < 40
          bm9[b_idx] = 0
          b_idx = b_idx + 1
        bpc = 1 ## i64
        uniq6 = true
        while bpc < end6
          if ops[bpc] == 27
            spc6 = bpc + 1
            epc6 = (branches[bpc] - 1) ## i64
            bpc = branches[bpc] ## i64
          else
            spc6 = bpc
            epc6 = end6
            bpc = end6
          c6_idx = 8 + ((args_a[spc6] >> 25) & 31)
          if bm9[c6_idx] != 0 || epc6 - spc6 < 2
            uniq6 = false
            break
          bm9[c6_idx] = (epc6 << 16) | spc6
        if uniq6
          exact = (has1 ? 6 : 7) ## i64
    bm9[40] = 9 | (exact << 8)
    return bm9
  if pfs_len == 2
    bm9[40] = 6
    return bm9
  bm9[40] = 8
  bm9

-> __regex_literal_prefix(ops_in, args_a_in, branches_in, empty_prefix_in, multiline, anchored_box_in)
  lit = empty_prefix_in ## i64[]
  ops = ops_in ## i64[]
  aa = args_a_in ## i64[]
  bb = branches_in ## i64[]
  anchored_box = anchored_box_in ## i64[]
  op_n = ops.size() ## i64
  pc = 0 ## i64
  anchored_box[0] = 0
  while pc < op_n
    op = ops[pc] ## i64
    if op == 1
      if lit.size() == 0
        lit = i64[0]
      lit.push(aa[pc])
      pc = pc + 1
    elsif op == 7 || op == 12 || op == 13
      pc = pc + 1
    elsif lit.size() == 0 && op == 20 && aa[pc] == 1
      anchored_box[0] = 1
      pc += 1
    elsif lit.size() == 0 && op == 8
      pc += 1
    elsif op == 25 && (bb[pc] & 15) == 5
      pc = pc + 1
    elsif op == 26 && aa[pc] == 0
      pc = pc + 1
    else
      pc = op_n
  lit

-> __regex_collect_first(pc_in, seen_in, ops_in, args_a_in, branches_in, pf_set_in, cls_bm_in, classes_in, ascii_only, state_in)
  ops = ops_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  seen = seen_in ## i64[]
  pfs = pf_set_in ## i64[]
  state = state_in ## i64[]
  pc = pc_in ## i64
  while true
    if seen[pc] != 0
      return nil
    seen[pc] = 1
    op = ops[pc] ## i64
    if op == 7 || op == 12 || op == 13 || op == 8 || op == 10
      pc = pc + 1
    elsif op == 20 && (args_a[pc] == 1 || args_a[pc] == 4)
      pc = pc + 1
    elsif op == 25
      if (branches[pc] & 15) == 5
        pc = pc + 1
      else
        pc = args_a[pc] ## i64
    elsif op == 26 && args_a[pc] == 0
      pc = pc + 1
    elsif op == 5
      pc = args_a[pc] ## i64
    elsif op == 6 || op == 27 || op == 14 || op == 15 || op == 16
      __regex_collect_first(args_a[pc], seen, ops, args_a, branches, pfs, cls_bm_in, classes_in, ascii_only, state)
      pc = branches[pc] ## i64
    elsif op == 1
      pfl = state[2] ## i64
      if pfl < pfs.size()
        pfs[pfl] = args_a[pc]
        state[2] = pfl + 1
      else
        state[0] = 0
      return nil
    elsif op == 18
      pfl = state[2] ## i64
      if pfl + 1 < pfs.size()
        pfs[pfl] = args_a[pc]
        pfs[pfl + 1] = branches[pc]
        state[2] = pfl + 2
      else
        state[0] = 0
      return nil
    elsif op == 11
      if branches[pc] == 0
        state[3] = (state[3] ## i64) | args_a[pc]
      else
        state[0] = 0
      return nil
    elsif op == 3
      if ascii_only && cls_bm_in != nil
        cbm = cls_bm_in ## i64[]
        cbase = (args_a[pc] ## i64) * 6
        state[4] = (state[4] ## i64) | cbm[cbase]
        state[5] = (state[5] ## i64) | cbm[cbase + 1]
        state[6] = (state[6] ## i64) | cbm[cbase + 2]
        state[7] = (state[7] ## i64) | cbm[cbase + 3]
        state[8] = (state[8] ## i64) + 1
      else
        cls_arr = classes_in ## Array
        cls_cf = cls_arr[args_a[pc]] ## i64[]
        if cls_cf[0] == 0 && cls_cf[1] == 0 && cls_cf[2] == 0 && cls_cf[3] == 0 && cls_cf[4] == 0 && cls_cf.size() >= 7
          c_min = cls_cf[5] ## i64
          c_max = cls_cf[6] ## i64
          cri = 7 ## i64
          while cri < cls_cf.size()
            if cls_cf[cri] < c_min
              c_min = cls_cf[cri]
            if cls_cf[cri + 1] > c_max
              c_max = cls_cf[cri + 1]
            cri = cri + 2
          if state[9] == 0
            state[10] = c_min
            state[11] = c_max
            state[9] = 1
          elsif c_min != state[10] || c_max != state[11]
            state[9] = 2
            state[0] = 0
        else
          state[0] = 0
      return nil
    elsif op == 17
      if state[9] == 0
        state[10] = args_a[pc]
        state[11] = branches[pc]
        state[9] = 1
      elsif args_a[pc] != state[10] || branches[pc] != state[11]
        state[9] = 2
        state[0] = 0
      return nil
    elsif op == 19
      if state[12] == 0
        state[13] = args_a[pc]
        state[14] = branches[pc]
        state[12] = 1
      elsif args_a[pc] != state[13] || branches[pc] != state[14]
        state[12] = 2
        state[0] = 0
      return nil
    elsif op == 4
      state[1] = 1
      return nil
    else
      state[0] = 0
      return nil

-> __regex_classify_prefilter(ops_in, args_a_in, branches_in, pfs_buf_in, state_in, lit_anchored_in, lead_rep_nb_in, lead_after_char_in, linear_in, ncap_in, ascii_only)
  ops = ops_in ## i64[]
  args_a = args_a_in ## i64[]
  branches = branches_in ## i64[]
  pfs_buf = pfs_buf_in ## i64[]
  state = state_in ## i64[]
  op_n = ops.size() ## i64
  lit_anchored = lit_anchored_in ## i64
  lead_rep_nb = lead_rep_nb_in ## i64
  lead_after_char = lead_after_char_in ## i64
  linear = linear_in ## i64
  pfs_len = state[2] ## i64
  pf_flag = state[3] ## i64
  pf_bm0 = state[4] ## i64
  pf_bm1 = state[5] ## i64
  pf_bm2 = state[6] ## i64
  pf_bm3 = state[7] ## i64
  pf_cls_cnt = state[8] ## i64
  pf_range_cnt = state[9] ## i64
  pf_lo = state[10] ## i64
  pf_hi = state[11] ## i64
  pf_cat_cnt = state[12] ## i64
  pf_cat_mask = state[13] ## i64
  pf_cat_neg = state[14] ## i64
  state[0] = 0
  state[1] = 0
  state[2] = pf_flag
  state[3] = 0
  state[4] = 0
  if op_n >= 5 && ops[0] == 7 && args_a[0] == 0 && ops[1] == 25 && (branches[1] & 15) == 3 && args_a[1] == 4 && ops[2] == 1 && ops[3] == 26
    state[0] = 10
    state[1] = args_a[2]
    if lit_anchored == 0 && ops[4] == 11 && branches[4] == 0 && ((op_n == 7 && ops[5] == 7 && ops[6] == 4) || (op_n == 9 && ops[5] == 16 && args_a[5] == 6 && branches[5] == 7 && ops[6] == 11 && args_a[6] == args_a[4] && branches[6] == 0 && ops[7] == 7 && ops[8] == 4))
      state[3] = 14
    return nil
  if pf_cls_cnt > 0
    if pfs_len == 0 && pf_flag == 0 && pf_range_cnt == 0 && pf_cat_cnt == 0 && lead_after_char < 0
      bm8 = i64[4]
      bm8[0] = pf_bm0
      bm8[1] = pf_bm1
      bm8[2] = pf_bm2
      bm8[3] = pf_bm3
      state[0] = 8
      state[1] = (pf_bm0 | pf_bm1 | pf_bm2 | pf_bm3) ## i64
      if lit_anchored == 0 && (op_n == 4 || (lead_rep_nb == 1 && op_n == 6))
        state[3] = 2
      return bm8
    if lit_anchored == 0 && lead_after_char >= 0 && lead_rep_nb == 1 && linear == 1 && ascii_only && op_n == 15 && ops[1] == 3 && ops[5] == 3 && ops[6] == 16 && ops[7] == 3 && args_a[5] == args_a[7] && ops[8] == 1 && ops[9] == 3 && ops[10] == 3 && args_a[9] == args_a[10] && ops[11] == 16 && ops[12] == 3 && args_a[9] == args_a[12] && ops[13] == 7 && ops[14] == 4
      state[3] = 5
    elsif lit_anchored == 0 && lead_after_char >= 0 && lead_rep_nb == 1 && linear == 1 && ascii_only && op_n == 10 && ops[1] == 3 && ops[4] == 1 && ops[5] == 17 && ops[6] == 16 && args_a[6] == 7 && branches[6] == 8 && ops[7] == 17 && args_a[7] == args_a[5] && branches[7] == branches[5] && ops[8] == 7 && ops[9] == 4
      state[3] = 12
    return nil
  if pf_cat_cnt > 0
    if pf_cat_cnt == 1 && pfs_len == 0 && pf_flag == 0 && pf_range_cnt == 0
      state[0] = 7
      state[1] = pf_cat_mask
      state[2] = pf_cat_neg
      if lit_anchored == 0 && op_n == 7 && ops[1] == 19 && ops[2] == 19 && ops[3] == 16 && args_a[3] == 4 && branches[3] == 5 && ops[4] == 19 && args_a[4] == args_a[2] && branches[4] == branches[2] && branches[1] == 0 && branches[2] == 0 && args_a[1] < 1073741824 && args_a[2] < 1073741824
        state[3] = 4
    return nil
  if pf_range_cnt > 0
    if pf_range_cnt == 1 && pfs_len == 0 && pf_flag == 0
      state[0] = 5
      state[1] = pf_lo
      state[2] = pf_hi
      if lit_anchored == 0 && (op_n == 4 || (lead_rep_nb == 1 && op_n == 6))
        state[3] = 3
    return nil
  if pfs_len == 0 && pf_flag == 0
    return nil
  if pf_flag != 0 && pfs_len == 0
    state[0] = 2
    state[1] = pf_flag
    fe = __regex_detect_flag_exact_match(ops, args_a, branches, lit_anchored, lead_rep_nb, linear, ncap_in) ## i64
    state[3] = fe & 255
    if (fe >> 8) != 0
      state[4] = fe >> 8
    return nil
  if pf_flag == 0 && pfs_len == 1
    state[0] = 1
    state[1] = pfs_buf[0]
    return nil
  if pf_flag == 0
    bm9 = __regex_build_bm9_exact(pfs_buf, pfs_len, ops, args_a, branches, lit_anchored, linear)
    if bm9 != nil
      b9 = bm9 ## i64[]
      btag = b9[40] ## i64
      bkind = btag & 255
      if bkind == 9
        state[0] = 9
        state[1] = (b9[0] | b9[1] | b9[2] | b9[3]) ## i64
        state[2] = (b9[4] | b9[5] | b9[6] | b9[7]) ## i64
        state[3] = btag >> 8
        return b9
      if bkind == 6
        state[0] = 6
        state[1] = pfs_buf[0]
        state[2] = pfs_buf[1]
        return nil
      state[0] = 8
      state[1] = (b9[0] | b9[1] | b9[2] | b9[3]) ## i64
      return b9
  if pf_flag == 0 && pfs_len == 2
    state[0] = 6
    state[1] = pfs_buf[0]
    state[2] = pfs_buf[1]
    return nil
  pfs_copy = i64[pfs_len]
  si_copy = 0 ## i64
  while si_copy < pfs_len
    pfs_copy[si_copy] = pfs_buf[si_copy]
    si_copy = si_copy + 1
  state[0] = 3
  pfs_copy

