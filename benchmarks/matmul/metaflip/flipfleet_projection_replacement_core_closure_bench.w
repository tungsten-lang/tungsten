# Exhaustive coordinate-core projection/replacement closure for d>=3.
# This complements the specialized 2x2 scan and tests every coordinate subset
# on each contracted index domain, including alternate same-rank lower schemes.

use flipfleet_projection_replacement
use flipfleet_global_isotropy
use flipfleet_block_composer
use metaflip_worker

-> ffprcc_expect(label, condition) (String bool) i64
  if !condition
    << "PROJECTION_CORE_CLOSURE_FAIL " + label
    exit(1)
  1

-> ffprcc_build_combos(n, d, combos) (i64 i64 i64[]) i64
  count = 0 ## i64
  mask = 0 ## i64
  while mask < (1 << n)
    if ffw_popcount(mask) == d
      at = 0 ## i64
      bit = 0 ## i64
      while bit < n
        if ((mask >> bit) & 1) != 0
          combos[count * d + at] = bit
          at += 1
        bit += 1
      count += 1
    mask += 1
  count

-> ffprcc_copy_combo(combos, ordinal, d, out) (i64[] i64 i64 i64[]) i64
  x = 0 ## i64
  while x < d
    out[x] = combos[ordinal * d + x]
    x += 1
  d

-> ffprcc_store_mask(mask, data, base, words) (i64 i64[] i64 i64) i64
  data[base] = mask & 1073741823
  if words > 1
    data[base + 1] = (mask >> 30) & 1073741823
  1

-> ffprcc_write(path, us, vs, ws, rank, n) (String i64[] i64[] i64[] i64 i64) i64
  scheme = FFBCScheme.new(n, n, n, rank)
  t = 0 ## i64
  while t < rank
    ffprcc_store_mask(us[t], scheme.us(), t * scheme.uw(), scheme.uw())
    ffprcc_store_mask(vs[t], scheme.vs(), t * scheme.vw(), scheme.vw())
    ffprcc_store_mask(ws[t], scheme.ws(), t * scheme.ww(), scheme.ww())
    t += 1
  scheme.set_rank(rank)
  if ffbc_verify_exact(scheme) != 1
    return 0
  ffbc_write(path, scheme)

-> ffprcc_case(root, source_path, lower_path, n, d, seed) (String String String i64 i64 i64) i64
  capacity = 1024 ## i64
  source_state = i64[ffw_state_size(capacity)]
  source_rank = ffw_load_scheme_cap(source_state, root + source_path, n, capacity, seed, 6, 4, 100000, 25000) ## i64
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  exported = ffw_export_best(source_state, source_u, source_v, source_w) ## i64
  ffprcc_expect("source", source_rank > 0 && exported == source_rank && ffw_verify_best_exact(source_state, n) == 1)

  lower_state = i64[ffw_state_size(capacity)]
  lower_rank = ffw_load_scheme_cap(lower_state, root + lower_path, d, capacity, seed + 1, 6, 4, 100000, 25000) ## i64
  lower_u = i64[capacity]
  lower_v = i64[capacity]
  lower_w = i64[capacity]
  lower_exported = ffw_export_best(lower_state, lower_u, lower_v, lower_w) ## i64
  ffprcc_expect("lower", lower_rank > 0 && lower_exported == lower_rank && ffw_verify_best_exact(lower_state, d) == 1)

  combos = i64[256]
  combo_count = ffprcc_build_combos(n, d, combos) ## i64
  ffprcc_expect("combos", combo_count > 0 && combo_count * d <= combos.size())
  indices_i = i64[7]
  indices_j = i64[7]
  indices_k = i64[7]
  projected_u = i64[capacity]
  projected_v = i64[capacity]
  projected_w = i64[capacity]
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  meta = i64[8]

  placements = 0 ## i64
  trivial = 0 ## i64
  neutral_novel = 0 ## i64
  best_rank = 1 << 30 ## i64
  best_distance = 0 - 1 ## i64
  best_projected = 0 ## i64
  best_canceled = 0 ## i64
  best_a = 0 ## i64
  best_b = 0 ## i64
  best_c = 0 ## i64
  a = 0 ## i64
  while a < combo_count
    ffprcc_copy_combo(combos, a, d, indices_i)
    b = 0 ## i64
    while b < combo_count
      ffprcc_copy_combo(combos, b, d, indices_j)
      c = 0 ## i64
      while c < combo_count
        ffprcc_copy_combo(combos, c, d, indices_k)
        rank = ffpr_splice_indexed(source_u, source_v, source_w, source_rank, lower_u, lower_v, lower_w, lower_rank, n, d, indices_i, indices_j, indices_k, projected_u, projected_v, projected_w, out_u, out_v, out_w, capacity, 0, meta) ## i64
        ffprcc_expect("placement", rank > 0)
        placements += 1
        if rank <= best_rank || rank == source_rank
          distance = ffgir_term_set_distance(source_u, source_v, source_w, source_rank, out_u, out_v, out_w, rank) ## i64
          if distance == 0
            trivial += 1
          else
            if rank == source_rank
              neutral_novel += 1
            if rank < best_rank || (rank == best_rank && distance > best_distance)
              best_rank = rank
              best_distance = distance
              best_projected = meta[1]
              best_canceled = meta[6]
              best_a = a
              best_b = b
              best_c = c
        c += 1
      b += 1
    a += 1

  if best_rank == (1 << 30)
    << "PROJECTION_CORE_CLOSURE tensor=" + n.to_s() + " core=" + d.to_s() + " placements=" + placements.to_s() + " source=" + source_rank.to_s() + " novel=0 trivial=" + trivial.to_s() + " source-file=" + source_path + " lower-file=" + lower_path
    return 999

  ffprcc_copy_combo(combos, best_a, d, indices_i)
  ffprcc_copy_combo(combos, best_b, d, indices_j)
  ffprcc_copy_combo(combos, best_c, d, indices_k)
  verified = ffpr_splice_indexed(source_u, source_v, source_w, source_rank, lower_u, lower_v, lower_w, lower_rank, n, d, indices_i, indices_j, indices_k, projected_u, projected_v, projected_w, out_u, out_v, out_w, capacity, 1, meta) ## i64
  ffprcc_expect("best exact", verified == best_rank && meta[7] == 1)
  verified_distance = ffgir_term_set_distance(source_u, source_v, source_w, source_rank, out_u, out_v, out_w, verified) ## i64
  ffprcc_expect("distance", verified_distance == best_distance)
  if verified <= source_rank
    output = "/tmp/matmul_" + n.to_s() + "x" + n.to_s() + "_rank" + verified.to_s() + "_projection_core" + d.to_s() + "_s" + seed.to_s() + "_gf2.txt"
    ffprcc_expect("write", ffprcc_write(output, out_u, out_v, out_w, verified, n) == verified)
    << "PROJECTION_CORE_CLOSURE_OUTPUT " + output
  << "PROJECTION_CORE_CLOSURE tensor=" + n.to_s() + " core=" + d.to_s() + " combos=" + combo_count.to_s() + " placements=" + placements.to_s() + " source=" + source_rank.to_s() + " lower=" + lower_rank.to_s() + " best=" + verified.to_s() + " debt=" + (verified - source_rank).to_s() + " distance=" + verified_distance.to_s() + " neutral-novel=" + neutral_novel.to_s() + " projected=" + best_projected.to_s() + " canceled=" + best_canceled.to_s() + " source-file=" + source_path + " lower-file=" + lower_path
  verified - source_rank

root = "benchmarks/matmul/metaflip/"
p3a = "matmul_3x3_rank23_d139_gf2.txt"
p3b = "matmul_3x3_rank23_d159_gf2.txt"
p4a = "matmul_4x4_rank47_d450_gf2.txt"
p4b = "matmul_4x4_rank47_d677_flips_gf2.txt"
p5a = "matmul_5x5_rank93_d968_global_isotropy_gf2.txt"
p5b = "matmul_5x5_rank93_d1155_gf2.txt"
p6a = "matmul_6x6_rank153_d1860_global_isotropy_gf2.txt"
p6b = "matmul_6x6_rank153_d2502_gf2.txt"
s4 = p4a
s5 = p5a
s6 = p6a
s7a = "matmul_7x7_rank247_d3098_global_isotropy_gf2.txt"
s7b = "matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt"

best_debt = 1 << 30 ## i64
case_count = 0 ## i64
seed = 94001 ## i64

# Full closure for every larger proper core and both retained lower basins.
sources = [s4, s4,
           s5, s5, s5, s5,
           s6, s6, s6, s6, s6, s6,
           s7a, s7a, s7a, s7a, s7a, s7a, s7a, s7a,
           s7b, s7b, s7b, s7b, s7b, s7b, s7b, s7b]
lowers = [p3a, p3b,
          p3a, p3b, p4a, p4b,
          p3a, p3b, p4a, p4b, p5a, p5b,
          p3a, p3b, p4a, p4b, p5a, p5b, p6a, p6b,
          p3a, p3b, p4a, p4b, p5a, p5b, p6a, p6b]
ns = i64[28]
ds = i64[28]
i = 0 ## i64
while i < 2
  ns[i] = 4
  ds[i] = 3
  i += 1
while i < 4
  ns[i] = 5
  ds[i] = 3
  i += 1
while i < 6
  ns[i] = 5
  ds[i] = 4
  i += 1
while i < 8
  ns[i] = 6
  ds[i] = 3
  i += 1
while i < 10
  ns[i] = 6
  ds[i] = 4
  i += 1
while i < 12
  ns[i] = 6
  ds[i] = 5
  i += 1
while i < 28
  ns[i] = 7
  offset = (i - 12) % 8 ## i64
  if offset < 2
    ds[i] = 3
  elsif offset < 4
    ds[i] = 4
  elsif offset < 6
    ds[i] = 5
  else
    ds[i] = 6
  i += 1

i = 0
while i < sources.size()
  debt = ffprcc_case(root, sources[i], lowers[i], ns[i], ds[i], seed + i * 101) ## i64
  if debt < best_debt
    best_debt = debt
  case_count += 1
  i += 1
<< "PROJECTION_CORE_CLOSURE_SUMMARY cases=" + case_count.to_s() + " best-debt=" + best_debt.to_s()
