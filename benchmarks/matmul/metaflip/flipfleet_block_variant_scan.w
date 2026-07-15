use flipfleet_block_composer

# Reproducible research harness for exact allocation ties and same-rank leaf
# variants.  It never changes the production CLI pool or record manifest.
#
# Build from the repository root, then emit the complete exact-best table:
#   bin/tungsten compile --release --lto -o /tmp/ffbc-variant-scan \
#     benchmarks/matmul/metaflip/flipfleet_block_variant_scan.w
#   /tmp/ffbc-variant-scan stabletable > /tmp/exact.tsv
# `tiecompare` exhaustively compares stable leaves with d304/d386/d518.

-> ffbc_variant_add(root, path, n, m, p, leaves)
  leaf = ffbc_load_exact(root + path, n, m, p, 128)
  if leaf == nil
    << "invalid leaf " + path
    exit(1)
  leaves.push(leaf)
  1

-> ffbc_variant_pool(root, mode)
  leaves = []
  ffbc_variant_add(root, "matmul_3x3_rank23_d139_gf2.txt", 3, 3, 3, leaves)
  ffbc_variant_add(root, "matmul_3x3x4_rank29_gf2.txt", 3, 3, 4, leaves)
  leaf335 = "matmul_3x3x5_rank36_gf2.txt"
  if mode == "335" || mode == "all"
    leaf335 = "matmul_3x3x5_rank36_d304_gf2.txt"
  ffbc_variant_add(root, leaf335, 3, 3, 5, leaves)
  ffbc_variant_add(root, "matmul_3x4x4_rank38_gf2.txt", 3, 4, 4, leaves)
  leaf345 = "matmul_3x4x5_rank47_gf2.txt"
  if mode == "345" || mode == "all"
    leaf345 = "matmul_3x4x5_rank47_d386_gf2.txt"
  ffbc_variant_add(root, leaf345, 3, 4, 5, leaves)
  leaf355 = "matmul_3x5x5_rank58_gf2.txt"
  if mode == "355" || mode == "all"
    leaf355 = "matmul_3x5x5_rank58_d518_gf2.txt"
  ffbc_variant_add(root, leaf355, 3, 5, 5, leaves)
  ffbc_variant_add(root, "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, leaves)
  ffbc_variant_add(root, "matmul_4x4x5_rank60_catalog_gf2.txt", 4, 4, 5, leaves)
  ffbc_variant_add(root, "matmul_4x5x5_rank76_catalog_gf2.txt", 4, 5, 5, leaves)
  ffbc_variant_add(root, "matmul_5x5_rank93_catalog_alphaevolve_gf2.txt", 5, 5, 5, leaves)
  leaves

# The production composer exact-gates every invocation.  During an exhaustive
# tie scan all inputs have already passed that gate, so this research-only
# twin skips the repeated input/output reconstruction.  Every rank-changing
# winner is re-materialised through ffbc_compose before it is reported.
-> ffbc_variant_compose_prechecked(outer, alloc_n, alloc_m, alloc_p, leaves)
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
        unique_rank = ffbc_toggle_term(result, global_u, global_v, global_w, slots, active, unique_rank)
        if unique_rank < 0
          return nil
        lt += 1
    term += 1
  ffbc_compact(result, active, unique_rank)
  result

av = argv()
if av.size() != 1
  << "usage: flipfleet_block_variant_scan <stable|335|345|355|all|compare|count|tiecompare|stabletable>"
  exit(1)
mode = av[0]
if mode != "stable" && mode != "335" && mode != "345" && mode != "355" && mode != "all" && mode != "compare" && mode != "count" && mode != "tiecompare" && mode != "stabletable"
  << "invalid mode " + mode
  exit(1)

root = "benchmarks/matmul/metaflip/"
leaves = nil
pools = []
labels = []
if mode == "compare" || mode == "tiecompare" || mode == "stabletable"
  labels = ["stable", "335", "345", "355", "all"]
  if mode == "stabletable"
    labels = ["stable"]
  li = 0 ## i64
  while li < labels.size()
    pools.push(ffbc_variant_pool(root, labels[li]))
    li += 1
  leaves = pools[0]
else
  leaves = ffbc_variant_pool(root, mode)
  if mode == "count"
    leaves = ffbc_variant_pool(root, "stable")
outer = leaves[6]
if mode == "stabletable"
  << "target\tformula_rank\texact_best_rank\talloc_n\talloc_m\talloc_p\tsource\ts3_code"
n = 12 ## i64
while n <= 20
  m = n ## i64
  while m <= 20
    p = m ## i64
    while p <= 20
      recipe = ffbc_best_oriented_balanced_recipe(outer, n, m, p, leaves)
      if recipe == nil
        << mode + " " + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " unsupported"
        exit(1)
      if mode == "count" || mode == "tiecompare" || mode == "stabletable"
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
        tie_count = 0 ## i64
        chosen_rank = 0 ## i64
        best_ranks = i64[5]
        best_an = [nil, nil, nil, nil, nil]
        best_am = [nil, nil, nil, nil, nil]
        best_ap = [nil, nil, nil, nil, nil]
        best_sn = i64[5]
        best_sm = i64[5]
        best_sp = i64[5]
        best_code = i64[5]
        if mode == "tiecompare" || mode == "stabletable"
          chosen_source = ffbc_variant_compose_prechecked(pools[0][6], recipe[0], recipe[1], recipe[2], pools[0])
          if chosen_source == nil
            << "chosen prechecked composition failed"
            exit(1)
          chosen_rank = chosen_source.rank()
          li = 0
          while li < best_ranks.size()
            best_ranks[li] = 0x7fffffff
            li += 1
        ci = 0 ## i64
        while ci < 6
          code = codes[ci] ## i64
          ffbc_source_dims_for_orientation(code, n, m, p, source_dims)
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
                  score = ffbc_score_allocation(outer, nas[ni], mas[mi], pas[pi], leaves) ## i64
                  if score == recipe[3]
                    tie_count += 1
                    if mode == "tiecompare" || mode == "stabletable"
                      li = 0
                      while li < pools.size()
                        candidate = ffbc_variant_compose_prechecked(pools[li][6], nas[ni], mas[mi], pas[pi], pools[li])
                        if candidate == nil
                          << labels[li] + " prechecked composition failed"
                          exit(1)
                        if candidate.rank() < best_ranks[li]
                          best_ranks[li] = candidate.rank()
                          best_an[li] = nas[ni]
                          best_am[li] = mas[mi]
                          best_ap[li] = pas[pi]
                          best_sn[li] = source_dims[0]
                          best_sm[li] = source_dims[1]
                          best_sp[li] = source_dims[2]
                          best_code[li] = code
                        li += 1
                  pi += 1
                mi += 1
              ni += 1
          ci += 1
        if mode == "count"
          << n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " " + recipe[3].to_s() + " " + tie_count.to_s()
        elsif mode == "stabletable"
          checked = ffbc_compose(pools[0][6], best_an[0], best_am[0], best_ap[0], pools[0])
          if checked == nil || checked.rank() != best_ranks[0]
            << "stable winning recipe failed exact recheck"
            exit(1)
          row = n.to_s() + "x" + m.to_s() + "x" + p.to_s()
          row = row + "\t" + recipe[3].to_s() + "\t" + best_ranks[0].to_s()
          row = row + "\t" + best_an[0].join(",") + "\t" + best_am[0].join(",") + "\t" + best_ap[0].join(",")
          row = row + "\t" + best_sn[0].to_s() + "x" + best_sm[0].to_s() + "x" + best_sp[0].to_s()
          << row + "\t" + best_code[0].to_s()
        else
          different = 0 ## i64
          if best_ranks[0] != chosen_rank
            different = 1
          li = 1
          while li < best_ranks.size()
            if best_ranks[li] != best_ranks[0]
              different = 1
            li += 1
          if different == 1
            li = 0
            while li < best_ranks.size()
              checked = ffbc_compose(pools[li][6], best_an[li], best_am[li], best_ap[li], pools[li])
              if checked == nil || checked.rank() != best_ranks[li]
                << labels[li] + " winning recipe failed exact recheck"
                exit(1)
              li += 1
            << n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " f" + recipe[3].to_s() + " chosen=" + chosen_rank.to_s() + " best-stable=" + best_ranks[0].to_s() + " 335=" + best_ranks[1].to_s() + " 345=" + best_ranks[2].to_s() + " 355=" + best_ranks[3].to_s() + " all=" + best_ranks[4].to_s() + " ties=" + tie_count.to_s()
            li = 0
            while li < best_ranks.size()
              << "  " + labels[li] + " src=" + best_sn[li].to_s() + "x" + best_sm[li].to_s() + "x" + best_sp[li].to_s() + " c" + best_code[li].to_s() + " " + best_an[li].join("") + "/" + best_am[li].join("") + "/" + best_ap[li].join("")
              li += 1
      elsif mode == "compare"
        ranks = i64[pools.size()]
        li = 0
        while li < pools.size()
          source = ffbc_compose(pools[li][6], recipe[0], recipe[1], recipe[2], pools[li])
          if source == nil
            << labels[li] + " " + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " invalid"
            exit(1)
          ranks[li] = source.rank()
          li += 1
        different = 0 ## i64
        li = 1
        while li < ranks.size()
          if ranks[li] != ranks[0]
            different = 1
          li += 1
        if different == 1
          << n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " f" + recipe[3].to_s() + " stable=" + ranks[0].to_s() + " 335=" + ranks[1].to_s() + " 345=" + ranks[2].to_s() + " 355=" + ranks[3].to_s() + " all=" + ranks[4].to_s() + " src=" + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s() + " c" + recipe[7].to_s() + " " + recipe[0].join("") + "/" + recipe[1].join("") + "/" + recipe[2].join("")
      else
        source = ffbc_compose(outer, recipe[0], recipe[1], recipe[2], leaves)
        if source == nil
          << mode + " " + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " invalid"
          exit(1)
        << mode + " " + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " " + recipe[3].to_s() + " " + source.rank().to_s() + " " + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s() + " c" + recipe[7].to_s() + " " + recipe[0].join("") + "/" + recipe[1].join("") + "/" + recipe[2].join("")
      p += 1
    m += 1
  if mode == "compare" || mode == "tiecompare"
    << "finished n=" + n.to_s()
  n += 1
