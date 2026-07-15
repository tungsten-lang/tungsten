use flipfleet_block_leaf_pool

# Post-embedding parity comparison for the deterministic formula-minimising
# recipe selected for each rank-47 outer.  Inputs are exact-gated once at load;
# the research-only materialiser then avoids reconstructing all 84 leaves for
# each of the 1,154 rows.  Any reported rank winner must still be replayed by
# the authoritative ffbc_compose_oriented_recipe gate before publication.

-> ffbo47_compose_prechecked(outer, alloc_n, alloc_m, alloc_p, leaves) (FFBCScheme i64[] i64[] i64[] Array)
  cum_n = ffbc_cumulative(alloc_n)
  cum_m = ffbc_cumulative(alloc_m)
  cum_p = ffbc_cumulative(alloc_p)
  target_n = cum_n[alloc_n.size()] ## i64
  target_m = cum_m[alloc_m.size()] ## i64
  target_p = cum_p[alloc_p.size()] ## i64
  ue = i64[2]
  ve = i64[2]
  we = i64[2]
  choice = i64[2]
  nominal = 0 ## i64
  term = 0 ## i64
  while term < outer.rank()
    ffbc_extent(outer.us(), term * outer.uw(), outer.n(), outer.m(), alloc_n, alloc_m, ue)
    ffbc_extent(outer.vs(), term * outer.vw(), outer.m(), outer.p(), alloc_m, alloc_p, ve)
    ffbc_extent(outer.ws(), term * outer.ww(), outer.n(), outer.p(), alloc_n, alloc_p, we)
    sn = ue[0] ## i64
    if we[0] < sn
      sn = we[0]
    sm = ue[1] ## i64
    if ve[0] < sm
      sm = ve[0]
    sp = ve[1] ## i64
    if we[1] < sp
      sp = we[1]
    if sn > 0 && sm > 0 && sp > 0
      if ffbc_find_leaf(leaves, sn, sm, sp, choice) != 1
        return nil
      nominal += leaves[choice[0]].rank()
    term += 1
  if nominal < 1
    return nil

  result = FFBCScheme.new(target_n, target_m, target_p, nominal)
  table_capacity = 16 ## i64
  while table_capacity < nominal * 4
    table_capacity *= 2
  slots = i64[table_capacity]
  active = i64[nominal]
  unique_rank = 0 ## i64
  nonzero_terms = 0 ## i64

  term = 0
  while term < outer.rank()
    ffbc_extent(outer.us(), term * outer.uw(), outer.n(), outer.m(), alloc_n, alloc_m, ue)
    ffbc_extent(outer.vs(), term * outer.vw(), outer.m(), outer.p(), alloc_m, alloc_p, ve)
    ffbc_extent(outer.ws(), term * outer.ww(), outer.n(), outer.p(), alloc_n, alloc_p, we)
    sn = ue[0]
    if we[0] < sn
      sn = we[0]
    sm = ue[1]
    if ve[0] < sm
      sm = ve[0]
    sp = ve[1]
    if we[1] < sp
      sp = we[1]
    if sn > 0 && sm > 0 && sp > 0
      if ffbc_find_leaf(leaves, sn, sm, sp, choice) != 1
        return nil
      leaf = leaves[choice[0]]
      code = choice[1] ## i64
      local_u = i64[ffbc_words(sn * sm)]
      local_v = i64[ffbc_words(sm * sp)]
      local_w = i64[ffbc_words(sn * sp)]
      global_u = i64[result.uw()]
      global_v = i64[result.vw()]
      global_w = i64[result.ww()]
      lt = 0 ## i64
      while lt < leaf.rank()
        ffbc_orient_term(leaf, lt, code, local_u, local_v, local_w)
        ffbc_embed(outer.us(), term * outer.uw(), outer.n(), outer.m(), alloc_n, alloc_m, cum_n, cum_m, local_u, sn, sm, target_m, global_u)
        ffbc_embed(outer.vs(), term * outer.vw(), outer.m(), outer.p(), alloc_m, alloc_p, cum_m, cum_p, local_v, sm, sp, target_p, global_v)
        ffbc_embed(outer.ws(), term * outer.ww(), outer.n(), outer.p(), alloc_n, alloc_p, cum_n, cum_p, local_w, sn, sp, target_p, global_w)
        if ffbc_factor_zero(global_u, 0, global_u.size()) != 1 && ffbc_factor_zero(global_v, 0, global_v.size()) != 1 && ffbc_factor_zero(global_w, 0, global_w.size()) != 1
          nonzero_terms += 1
        unique_rank = ffbc_toggle_term(result, global_u, global_v, global_w, slots, active, unique_rank)
        if unique_rank < 0
          return nil
        lt += 1
    term += 1
  final_rank = ffbc_compact(result, active, unique_rank) ## i64
  result.set_compose_audit(nominal, nominal - nonzero_terms, unique_rank, nonzero_terms - final_rank)
  result

-> ffbo47_formula_tie_count(outer, target_n, target_m, target_p, leaves, formula_rank) (FFBCScheme i64 i64 i64 Array i64)
  codes = i64[6]
  codes[0] = 0
  codes[1] = 4
  codes[2] = 5
  codes[3] = 3
  codes[4] = 1
  codes[5] = 2
  seen_n = i64[6]
  seen_m = i64[6]
  seen_p = i64[6]
  seen_count = 0 ## i64
  source_dims = i64[3]
  count = 0 ## i64
  ci = 0 ## i64
  while ci < 6
    code = codes[ci] ## i64
    ffbc_source_dims_for_orientation(code, target_n, target_m, target_p, source_dims)
    duplicate = 0 ## i64
    si = 0 ## i64
    while si < seen_count
      if seen_n[si] == source_dims[0] && seen_m[si] == source_dims[1] && seen_p[si] == source_dims[2]
        duplicate = 1
      si += 1
    if duplicate == 0
      seen_n[seen_count] = source_dims[0]
      seen_m[seen_count] = source_dims[1]
      seen_p[seen_count] = source_dims[2]
      seen_count += 1
      nas = ffbc_balanced_allocations(source_dims[0], outer.n())
      mas = ffbc_balanced_allocations(source_dims[1], outer.m())
      pas = ffbc_balanced_allocations(source_dims[2], outer.p())
      ni = 0 ## i64
      while ni < nas.size()
        mi = 0 ## i64
        while mi < mas.size()
          pi = 0 ## i64
          while pi < pas.size()
            if ffbc_score_allocation(outer, nas[ni], mas[mi], pas[pi], leaves) == formula_rank
              count += 1
            pi += 1
          mi += 1
        ni += 1
    ci += 1
  count

# Exhaust all formula-minimising balanced allocation/S3 ties using the
# prechecked parity materialiser.  The returned recipe extends the standard
# eight fields with exact rank, mapped-zero count, and duplicate cancellation.
-> ffbo47_best_prechecked_formula_tie(outer, target_n, target_m, target_p, leaves, formula_rank) (FFBCScheme i64 i64 i64 Array i64)
  codes = i64[6]
  codes[0] = 0
  codes[1] = 4
  codes[2] = 5
  codes[3] = 3
  codes[4] = 1
  codes[5] = 2
  seen_n = i64[6]
  seen_m = i64[6]
  seen_p = i64[6]
  seen_count = 0 ## i64
  source_dims = i64[3]
  best = nil
  best_rank = 0x7fffffff ## i64
  ci = 0 ## i64
  while ci < 6
    code = codes[ci] ## i64
    ffbc_source_dims_for_orientation(code, target_n, target_m, target_p, source_dims)
    duplicate = 0 ## i64
    si = 0 ## i64
    while si < seen_count
      if seen_n[si] == source_dims[0] && seen_m[si] == source_dims[1] && seen_p[si] == source_dims[2]
        duplicate = 1
      si += 1
    if duplicate == 0
      seen_n[seen_count] = source_dims[0]
      seen_m[seen_count] = source_dims[1]
      seen_p[seen_count] = source_dims[2]
      seen_count += 1
      nas = ffbc_balanced_allocations(source_dims[0], outer.n())
      mas = ffbc_balanced_allocations(source_dims[1], outer.m())
      pas = ffbc_balanced_allocations(source_dims[2], outer.p())
      ni = 0 ## i64
      while ni < nas.size()
        mi = 0 ## i64
        while mi < mas.size()
          pi = 0 ## i64
          while pi < pas.size()
            if ffbc_score_allocation(outer, nas[ni], mas[mi], pas[pi], leaves) == formula_rank
              candidate = ffbo47_compose_prechecked(outer, nas[ni], mas[mi], pas[pi], leaves)
              if candidate == nil
                return nil
              if candidate.rank() < best_rank
                best_rank = candidate.rank()
                best = [nas[ni], mas[mi], pas[pi], formula_rank,
                        source_dims[0], source_dims[1], source_dims[2], code,
                        candidate.rank(), candidate.compose_zero_terms(),
                        candidate.compose_parity_reduction()]
            pi += 1
          mi += 1
        ni += 1
    ci += 1
  best

root = "benchmarks/matmul/metaflip/"
outer450 = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
outer677 = ffbc_load_exact(root + "matmul_4x4_rank47_d677_flips_gf2.txt", 4, 4, 4, 128)
leaves = ffbcp_stable_2_to_8(root)
if outer450 == nil || outer677 == nil || leaves.size() != 84
  << "invalid outer or incomplete 2--8 leaf pool"
  exit(1)

av = argv()
tie_exact_mode = 0 ## i64
if av.size() == 2 && av[0] == "tie-exact"
  tie_exact_mode = 1
if av.size() > 2 || (av.size() == 1 && av[0] != "tie-count") || (av.size() == 2 && tie_exact_mode != 1)
  << "usage: flipfleet-block-outer47-small-cross-exact; modes: tie-count or tie-exact N"
  exit(1)
if av.size() == 1
  << "target\tformula_rank\tformula_minimising_ties"
  total_ties = 0 ## i64
  max_ties = 0 ## i64
  counted = 0 ## i64
  cn = 8 ## i64
  while cn <= 11
    cm = cn ## i64
    while cm <= 32
      cp = cm ## i64
      while cp <= 32
        recipe = ffbc_best_oriented_balanced_recipe(outer450, cn, cm, cp, leaves)
        if recipe == nil
          << "missing d450 recipe"
          exit(1)
        tie_count = ffbo47_formula_tie_count(outer450, cn, cm, cp, leaves, recipe[3]) ## i64
        target = cn.to_s() + "x" + cm.to_s() + "x" + cp.to_s()
        << target + "\t" + recipe[3].to_s() + "\t" + tie_count.to_s()
        total_ties += tie_count
        if tie_count > max_ties
          max_ties = tie_count
        counted += 1
        cp += 1
      cm += 1
    cn += 1
  << "SUMMARY\tchecked=" + counted.to_s() + "\ttotal_ties=" + total_ties.to_s() + "\tmax_ties=" + max_ties.to_s()
  exit(0)
if tie_exact_mode == 1
  only_n = av[1].to_i() ## i64
  if only_n < 8 || only_n > 11
    << "tie-exact N requires N in 8..11"
    exit(1)
  << "target\tformula_rank\texact_best_rank\treduction\tzero_terms\tparity_reduction\talloc_n\talloc_m\talloc_p\tsource\ts3_code"
  exact_checked = 0 ## i64
  improved = 0 ## i64
  max_reduction = 0 ## i64
  em = only_n ## i64
  while em <= 32
    ep = em ## i64
    while ep <= 32
      recipe = ffbc_best_oriented_balanced_recipe(outer450, only_n, em, ep, leaves)
      if recipe == nil
        << "missing d450 recipe"
        exit(1)
      best = ffbo47_best_prechecked_formula_tie(outer450, only_n, em, ep, leaves, recipe[3])
      if best == nil
        << "formula-tie exact scan failed"
        exit(1)
      reduction = best[3] - best[8] ## i64
      if reduction > 0
        improved += 1
        if reduction > max_reduction
          max_reduction = reduction
      target = only_n.to_s() + "x" + em.to_s() + "x" + ep.to_s()
      row = target + "\t" + best[3].to_s() + "\t" + best[8].to_s() + "\t" + reduction.to_s()
      row = row + "\t" + best[9].to_s() + "\t" + best[10].to_s()
      row = row + "\t" + best[0].join(",") + "\t" + best[1].join(",") + "\t" + best[2].join(",")
      row = row + "\t" + best[4].to_s() + "x" + best[5].to_s() + "x" + best[6].to_s() + "\t" + best[7].to_s()
      << row
      exact_checked += 1
      ep += 1
    em += 1
  << "SUMMARY\tn=" + only_n.to_s() + "\tchecked=" + exact_checked.to_s() + "\timproved=" + improved.to_s() + "\tmax_reduction=" + max_reduction.to_s()
  exit(0)

checked = 0 ## i64
formula_wins = 0 ## i64
exact_wins = 0 ## i64
reductions450 = 0 ## i64
reductions677 = 0 ## i64
max_reduction450 = 0 ## i64
max_reduction677 = 0 ## i64
<< "target\td450_formula\td450_exact\td450_reduction\td677_formula\td677_exact\td677_reduction\td677_exact_gain"
n = 8 ## i64
while n <= 11
  m = n ## i64
  while m <= 32
    p = m ## i64
    while p <= 32
      recipe450 = ffbc_best_oriented_balanced_recipe(outer450, n, m, p, leaves)
      recipe677 = ffbc_best_oriented_balanced_recipe(outer677, n, m, p, leaves)
      if recipe450 == nil || recipe677 == nil
        << "missing recipe"
        exit(1)
      exact450 = ffbo47_compose_prechecked(outer450, recipe450[0], recipe450[1], recipe450[2], leaves)
      exact677 = ffbo47_compose_prechecked(outer677, recipe677[0], recipe677[1], recipe677[2], leaves)
      if exact450 == nil || exact677 == nil
        << "prechecked composition failed"
        exit(1)
      reduction450 = recipe450[3] - exact450.rank() ## i64
      reduction677 = recipe677[3] - exact677.rank() ## i64
      gain = exact450.rank() - exact677.rank() ## i64
      if recipe677[3] < recipe450[3]
        formula_wins += 1
      if gain > 0
        exact_wins += 1
      if reduction450 > 0
        reductions450 += 1
        if reduction450 > max_reduction450
          max_reduction450 = reduction450
      if reduction677 > 0
        reductions677 += 1
        if reduction677 > max_reduction677
          max_reduction677 = reduction677
      target = n.to_s() + "x" + m.to_s() + "x" + p.to_s()
      row = target + "\t" + recipe450[3].to_s() + "\t" + exact450.rank().to_s() + "\t" + reduction450.to_s()
      row = row + "\t" + recipe677[3].to_s() + "\t" + exact677.rank().to_s() + "\t" + reduction677.to_s() + "\t" + gain.to_s()
      << row
      checked += 1
      p += 1
    m += 1
  n += 1
if checked != 1154
  << "expected 1154 targets, got " + checked.to_s()
  exit(1)
<< "SUMMARY\tchecked=" + checked.to_s() + "\tformula_wins=" + formula_wins.to_s() + "\texact_wins=" + exact_wins.to_s() + "\td450_reductions=" + reductions450.to_s() + "\td677_reductions=" + reductions677.to_s() + "\tmax_d450_reduction=" + max_reduction450.to_s() + "\tmax_d677_reduction=" + max_reduction677.to_s()
