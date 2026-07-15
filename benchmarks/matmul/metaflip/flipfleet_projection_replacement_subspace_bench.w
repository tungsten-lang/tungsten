use flipfleet_projection_replacement
use metaflip_worker
use flipfleet_block_composer

-> ffprs_expect(label, condition) (String bool) i64
  if !condition
    << "PROJECTION_SUBSPACE_FAIL " + label
    exit(1)
  1

-> ffprs_distance(left_u, left_v, left_w, left_rank, right_u, right_v, right_w, right_rank) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  distance = 0 ## i64
  i = 0 ## i64
  while i < left_rank
    found = 0 ## i64
    j = 0 ## i64
    while j < right_rank
      if left_u[i] == right_u[j] && left_v[i] == right_v[j] && left_w[i] == right_w[j]
        found = 1
      j += 1
    if found == 0
      distance += 1
    i += 1
  i = 0
  while i < right_rank
    found = 0
    j = 0
    while j < left_rank
      if right_u[i] == left_u[j] && right_v[i] == left_v[j] && right_w[i] == left_w[j]
        found = 1
      j += 1
    if found == 0
      distance += 1
    i += 1
  distance

-> ffprs_store_mask(mask, data, base, words) (i64 i64[] i64 i64) i64
  data[base] = mask & 1073741823
  if words > 1
    data[base + 1] = (mask >> 30) & 1073741823
  1

-> ffprs_write_scheme(path, us, vs, ws, rank, n) (String i64[] i64[] i64[] i64 i64) i64
  scheme = FFBCScheme.new(n, n, n, rank)
  t = 0 ## i64
  while t < rank
    ffprs_store_mask(us[t], scheme.us(), t * scheme.uw(), scheme.uw())
    ffprs_store_mask(vs[t], scheme.vs(), t * scheme.vw(), scheme.vw())
    ffprs_store_mask(ws[t], scheme.ws(), t * scheme.ww(), scheme.ww())
    t += 1
  scheme.set_rank(rank)
  if ffbc_verify_exact(scheme) != 1
    return 0
  ffbc_write(path, scheme)

-> ffprs_scan(root, source_path, n, seed) (String String i64 i64) i64
  capacity = 1024 ## i64
  state = i64[ffw_state_size(capacity)]
  source_rank = ffw_load_scheme_cap(state, root + source_path, n, capacity, seed, 6, 4, 100000, 25000) ## i64
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  exported = ffw_export_best(state, source_u, source_v, source_w) ## i64
  ffprs_expect("source", source_rank > 0 && exported == source_rank && ffw_verify_best_exact(state, n) == 1)

  lower = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
  ffprs_expect("lower", lower != nil && lower.rank() == 7)
  lower_u = i64[16]
  lower_v = i64[16]
  lower_w = i64[16]
  t = 0 ## i64
  while t < lower.rank()
    lower_u[t] = lower.us()[t * lower.uw()]
    lower_v[t] = lower.vs()[t * lower.vw()]
    lower_w[t] = lower.ws()[t * lower.ww()]
    t += 1

  projected_u = i64[capacity]
  projected_v = i64[capacity]
  projected_w = i64[capacity]
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  meta = i64[8]
  best_rank = 1 << 30 ## i64
  best_distance = 0 - 1 ## i64
  best_projected = 0 ## i64
  best_canceled = 0 ## i64
  best_i0 = 0 ## i64
  best_i1 = 1 ## i64
  best_j0 = 0 ## i64
  best_j1 = 1 ## i64
  best_k0 = 0 ## i64
  best_k1 = 1 ## i64
  placements = 0 ## i64
  neutral_nontrivial = 0 ## i64
  i0 = 0 ## i64
  while i0 < n
    i1 = i0 + 1 ## i64
    while i1 < n
      j0 = 0 ## i64
      while j0 < n
        j1 = j0 + 1 ## i64
        while j1 < n
          k0 = 0 ## i64
          while k0 < n
            k1 = k0 + 1 ## i64
            while k1 < n
              rank = ffpr_splice2_indexed(source_u, source_v, source_w, source_rank, lower_u, lower_v, lower_w, lower.rank(), n, i0, i1, j0, j1, k0, k1, projected_u, projected_v, projected_w, out_u, out_v, out_w, capacity, 0, meta) ## i64
              ffprs_expect("placement", rank > 0)
              placements += 1
              distance = 0 ## i64
              if rank <= best_rank || rank == source_rank
                distance = ffprs_distance(source_u, source_v, source_w, source_rank, out_u, out_v, out_w, rank)
              if rank == source_rank && distance > 0
                neutral_nontrivial += 1
              if rank < best_rank || (rank == best_rank && distance > best_distance)
                best_rank = rank
                best_distance = distance
                best_projected = meta[1]
                best_canceled = meta[6]
                best_i0 = i0
                best_i1 = i1
                best_j0 = j0
                best_j1 = j1
                best_k0 = k0
                best_k1 = k1
              k1 += 1
            k0 += 1
          j1 += 1
        j0 += 1
      i1 += 1
    i0 += 1

  verified = ffpr_splice2_indexed(source_u, source_v, source_w, source_rank, lower_u, lower_v, lower_w, lower.rank(), n, best_i0, best_i1, best_j0, best_j1, best_k0, best_k1, projected_u, projected_v, projected_w, out_u, out_v, out_w, capacity, 1, meta) ## i64
  ffprs_expect("best exact", verified == best_rank && meta[7] == 1)
  verified_distance = ffprs_distance(source_u, source_v, source_w, source_rank, out_u, out_v, out_w, verified) ## i64
  ffprs_expect("distance stable", verified_distance == best_distance)
  if best_distance > 0 && verified - source_rank <= 6
    output = "/tmp/matmul_" + n.to_s() + "x" + n.to_s() + "_rank" + verified.to_s() + "_projection_subspace_gf2.txt"
    ffprs_expect("write shoulder", ffprs_write_scheme(output, out_u, out_v, out_w, verified, n) == verified)
    << "PROJECTION_SUBSPACE_SHOULDER output=" + output
    t = 0
    while t < verified
      found = 0 ## i64
      s = 0 ## i64
      while s < source_rank
        if out_u[t] == source_u[s] && out_v[t] == source_v[s] && out_w[t] == source_w[s]
          found = 1
        s += 1
      if found == 0
        << "PROJECTION_SUBSPACE_CIRCUIT R " + out_u[t].to_s() + " " + out_v[t].to_s() + " " + out_w[t].to_s()
      t += 1
  << "PROJECTION_SUBSPACE size=" + n.to_s() + " placements=" + placements.to_s() + " source=" + source_rank.to_s() + " best=" + best_rank.to_s() + " debt=" + (best_rank - source_rank).to_s() + " distance=" + best_distance.to_s() + " neutral-novel=" + neutral_nontrivial.to_s() + " projected=" + best_projected.to_s() + " canceled=" + best_canceled.to_s() + " I=" + best_i0.to_s() + "," + best_i1.to_s() + " J=" + best_j0.to_s() + "," + best_j1.to_s() + " K=" + best_k0.to_s() + "," + best_k1.to_s() + " source-file=" + source_path
  best_rank - source_rank

root = "benchmarks/matmul/metaflip/"
best_debt = ffprs_scan(root, "matmul_4x4_rank47_d450_gf2.txt", 4, 91001) ## i64
debt = ffprs_scan(root, "matmul_5x5_rank93_d968_global_isotropy_gf2.txt", 5, 91101) ## i64
if debt < best_debt
  best_debt = debt
debt = ffprs_scan(root, "matmul_6x6_rank153_d1860_global_isotropy_gf2.txt", 6, 91201)
if debt < best_debt
  best_debt = debt
debt = ffprs_scan(root, "matmul_7x7_rank247_d3098_global_isotropy_gf2.txt", 7, 91301)
if debt < best_debt
  best_debt = debt
debt = ffprs_scan(root, "matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt", 7, 91401)
if debt < best_debt
  best_debt = debt
<< "PROJECTION_SUBSPACE_SUMMARY cases=5 best-debt=" + best_debt.to_s()
