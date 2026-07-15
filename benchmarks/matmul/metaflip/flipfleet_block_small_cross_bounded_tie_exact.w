use flipfleet_block_leaf_pool

# Exhaustive exact-cancellation closure for every formula-minimising ordered
# 2--8 allocation and unique S3 source orientation under the exact d450
# rank-47 <4,4,4> outer.  Unlike the selected-recipe unbalanced audit, this
# checks every allocation tied at the global bounded formula minimum.
#
# Count all near-comparator targets without materialising schemes:
#   ffbc-bounded-ties count MAX_GAP
# Exact-close one target (and write a certificate automatically on a win):
#   ffbc-bounded-ties exact NxMxP

-> ffbsbte_parse_dims(text, dims) (String i64[]) i64
  fields = text.split("x")
  if fields.size() != 3
    return 0
  i = 0 ## i64
  while i < 3
    dims[i] = fields[i].to_i()
    if dims[i] < 8 || dims[i] > 32
      return 0
    i += 1
  if dims[0] > dims[1] || dims[1] > dims[2] || dims[0] > 11
    return 0
  1

-> ffbsbte_score_codes(u_codes, v_codes, w_codes, leaf_ranks, stride, rank, mas_count, pas_count, ni, mi, pi) (i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64) i64
  u_base = (ni * mas_count + mi) * rank ## i64
  v_base = (mi * pas_count + pi) * rank ## i64
  w_base = (ni * pas_count + pi) * rank ## i64
  score = 0 ## i64
  term = 0 ## i64
  while term < rank && score >= 0
    ue = u_codes[u_base + term] ## i64
    ve = v_codes[v_base + term] ## i64
    we = w_codes[w_base + term] ## i64
    sn = ue & 255 ## i64
    wn = we & 255 ## i64
    if wn < sn
      sn = wn
    sm = (ue >> 8) & 255 ## i64
    vm = ve & 255 ## i64
    if vm < sm
      sm = vm
    sp = (ve >> 8) & 255 ## i64
    wp = (we >> 8) & 255 ## i64
    if wp < sp
      sp = wp
    leaf_rank = leaf_ranks[(sn * stride + sm) * stride + sp] ## i64
    if leaf_rank < 0
      score = 0 - 1
    else
      score += leaf_rank
    term += 1
  score

# Research-only materialiser for inputs already exact-gated at process start.
# Rank-changing winners are re-run through ffbc_compose_oriented_recipe and
# ffbc_verify_exact before output or serialization.
-> ffbsbte_compose_prechecked(outer, alloc_n, alloc_m, alloc_p, leaves) (FFBCScheme i64[] i64[] i64[] Array)
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
  result.set_compose_audit(nominal, nominal - nonzero_terms, unique_rank,
                           nonzero_terms - final_rank)
  result

# Return [tie_count, best_exact_rank, zero_terms, parity_reduction, alloc_n,
# alloc_m, alloc_p, source_n, source_m, source_p, s3_code].  In count-only
# mode the recipe fields remain unset and no composition scratch is allocated.
-> ffbsbte_scan_target(outer, leaves, target_n, target_m, target_p, formula_rank, exact_mode) (FFBCScheme Array i64 i64 i64 i64 i64 i64)
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
  leaf_ranks = ffbc_leaf_rank_table(leaves, 8)
  stride = 9 ## i64
  rank = outer.rank() ## i64
  tie_count = 0 ## i64
  best_rank = 0x7fffffff ## i64
  best_zero = 0 ## i64
  best_parity = 0 ## i64
  best_an = nil
  best_am = nil
  best_ap = nil
  best_sn = 0 ## i64
  best_sm = 0 ## i64
  best_sp = 0 ## i64
  best_code = 0 ## i64

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
      nas = ffbc_bounded_allocations(source_dims[0], outer.n(), 2, 8)
      mas = ffbc_bounded_allocations(source_dims[1], outer.m(), 2, 8)
      pas = ffbc_bounded_allocations(source_dims[2], outer.p(), 2, 8)
      u_codes = ffbc_pair_extent_codes(outer.us(), outer.uw(), outer.n(), outer.m(), nas, mas, rank)
      v_codes = ffbc_pair_extent_codes(outer.vs(), outer.vw(), outer.m(), outer.p(), mas, pas, rank)
      w_codes = ffbc_pair_extent_codes(outer.ws(), outer.ww(), outer.n(), outer.p(), nas, pas, rank)
      ni = 0 ## i64
      while ni < nas.size()
        mi = 0 ## i64
        while mi < mas.size()
          pi = 0 ## i64
          while pi < pas.size()
            score = ffbsbte_score_codes(u_codes, v_codes, w_codes, leaf_ranks,
                                        stride, rank, mas.size(), pas.size(),
                                        ni, mi, pi) ## i64
            if score >= 0 && score < formula_rank
              # The checked-in bounded scan supplies the claimed global
              # minimum.  Replaying every triple here must never undercut it.
              return nil
            if score == formula_rank
              tie_count += 1
              if exact_mode == 1
                candidate = ffbsbte_compose_prechecked(outer, nas[ni], mas[mi], pas[pi], leaves)
                if candidate == nil || candidate.compose_nominal() != formula_rank
                  return nil
                if candidate.rank() < best_rank
                  best_rank = candidate.rank()
                  best_zero = candidate.compose_zero_terms()
                  best_parity = candidate.compose_parity_reduction()
                  best_an = nas[ni]
                  best_am = mas[mi]
                  best_ap = pas[pi]
                  best_sn = source_dims[0]
                  best_sm = source_dims[1]
                  best_sp = source_dims[2]
                  best_code = code
            pi += 1
          mi += 1
        ni += 1
    ci += 1
  if tie_count < 1 || (exact_mode == 1 && best_an == nil)
    return nil
  [tie_count, best_rank, best_zero, best_parity, best_an, best_am, best_ap,
   best_sn, best_sm, best_sp, best_code]

-> ffbsbte_status(baseline, rank) (i64 i64)
  if rank < baseline
    return "win"
  if rank == baseline
    return "tie"
  "loss"

root = "benchmarks/matmul/metaflip/"
outer = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
leaves = ffbcp_stable_2_to_8(root)
audit = read_file(root + "block_composition_small_cross_unbalanced_full_audit.tsv")
if outer == nil || leaves.size() != 84 || audit == nil
  << "invalid outer, leaf pool, or bounded audit"
  exit(1)

av = argv()
if av.size() != 2 || (av[0] != "count" && av[0] != "exact")
  << "usage: ffbc-bounded-ties count MAX_GAP | exact NxMxP"
  exit(1)

lines = audit.split("\n")
if av[0] == "count"
  max_gap = av[1].to_i() ## i64
  if max_gap < 0 || max_gap > 128
    << "MAX_GAP must be in 0..128"
    exit(1)
  << "target\tformula_rank\tf2_baseline\tformula_gap\tformula_minimising_ties"
  selected = 0 ## i64
  total_ties = 0 ## i64
  i = 1 ## i64
  while i < lines.size()
    if lines[i].size() > 0
      fields = lines[i].split("\t")
      if fields.size() != 21
        << "malformed audit row " + i.to_s()
        exit(1)
      if fields[5].size() > 0
        formula_rank = fields[2].to_i() ## i64
        baseline = fields[5].to_i() ## i64
        gap = formula_rank - baseline ## i64
        if gap >= 0 && gap <= max_gap
          dims = i64[3]
          if ffbsbte_parse_dims(fields[0], dims) != 1
            << "malformed target " + fields[0]
            exit(1)
          result = ffbsbte_scan_target(outer, leaves, dims[0], dims[1], dims[2], formula_rank, 0)
          if result == nil
            << "tie count failed " + fields[0]
            exit(1)
          << fields[0] + "\t" + formula_rank.to_s() + "\t" + baseline.to_s() + "\t" + gap.to_s() + "\t" + result[0].to_s()
          total_ties += result[0]
          selected += 1
    i += 1
  << "SUMMARY\tmax_gap=" + max_gap.to_s() + "\tselected=" + selected.to_s() + "\ttotal_ties=" + total_ties.to_s()
  exit(0)

target = av[1]
target_fields = nil
i = 1 ## i64
while i < lines.size()
  if lines[i].size() > 0
    fields = lines[i].split("\t")
    if fields.size() == 21 && fields[0] == target
      target_fields = fields
  i += 1
if target_fields == nil || target_fields[5].size() == 0
  << "target lacks a pinned GF(2) comparator: " + target
  exit(1)
dims = i64[3]
if ffbsbte_parse_dims(target, dims) != 1
  << "invalid target " + target
  exit(1)
formula_rank = target_fields[2].to_i() ## i64
baseline = target_fields[5].to_i() ## i64
best = ffbsbte_scan_target(outer, leaves, dims[0], dims[1], dims[2], formula_rank, 1)
if best == nil
  << "bounded tie exact scan failed " + target
  exit(1)
recipe = [best[4], best[5], best[6], formula_rank,
          best[7], best[8], best[9], best[10]]
checked = ffbc_compose_oriented_recipe(outer, dims[0], dims[1], dims[2], leaves, recipe)
if checked == nil || ffbc_verify_exact(checked) != 1 || checked.rank() != best[1]
  << "authoritative exact gate failed " + target
  exit(1)

certificate = "-"
if checked.rank() < baseline
  certificate = "matmul_" + target + "_rank" + checked.rank().to_s() + "_block47_bounded_tie_gf2.txt"
  if ffbc_write(root + certificate, checked) != checked.rank()
    << "certificate write failed " + certificate
    exit(1)
  reloaded = ffbc_load_exact(root + certificate, dims[0], dims[1], dims[2], checked.rank() + 1)
  if reloaded == nil || reloaded.rank() != checked.rank()
    << "certificate reload failed " + certificate
    exit(1)

header = "target\tformula_rank\texact_best_rank\treduction\tf2_baseline\tformula_gap\texact_gap\tstatus\tformula_minimising_ties"
header = header + "\tzero_terms\tparity_reduction\talloc_n\talloc_m\talloc_p\tsource\ts3_code\tcertificate"
<< header
row = target + "\t" + formula_rank.to_s() + "\t" + checked.rank().to_s()
row = row + "\t" + (formula_rank - checked.rank()).to_s() + "\t" + baseline.to_s()
row = row + "\t" + (formula_rank - baseline).to_s() + "\t" + (checked.rank() - baseline).to_s()
row = row + "\t" + ffbsbte_status(baseline, checked.rank()) + "\t" + best[0].to_s()
row = row + "\t" + best[2].to_s() + "\t" + best[3].to_s()
row = row + "\t" + best[4].join(",") + "\t" + best[5].join(",") + "\t" + best[6].join(",")
row = row + "\t" + best[7].to_s() + "x" + best[8].to_s() + "x" + best[9].to_s()
row = row + "\t" + best[10].to_s() + "\t" + certificate
<< row
<< "SUMMARY\ttarget=" + target + "\tchecked=1\tties=" + best[0].to_s() + "\tstatus=" + ffbsbte_status(baseline, checked.rank())
