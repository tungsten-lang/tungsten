use flipfleet_circuit_image_search
use flipfleet_projection_replacement
use flipfleet_global_isotropy
use flipfleet_block_composer

-> ffcisb_expect(label, condition) (String bool) i64
  if !condition
    << "CIRCUIT_IMAGE_SEARCH_BENCH_FAIL " + label
    exit(1)
  1

-> ffcisb_store_mask(mask, data, base, words) (i64 i64[] i64 i64) i64
  data[base] = mask & 1073741823
  if words > 1
    data[base + 1] = (mask >> 30) & 1073741823
  1

-> ffcisb_write(path, us, vs, ws, rank, n) (String i64[] i64[] i64[] i64 i64) i64
  scheme = FFBCScheme.new(n, n, n, rank)
  t = 0 ## i64
  while t < rank
    ffcisb_store_mask(us[t], scheme.us(), t * scheme.uw(), scheme.uw())
    ffcisb_store_mask(vs[t], scheme.vs(), t * scheme.vw(), scheme.vw())
    ffcisb_store_mask(ws[t], scheme.ws(), t * scheme.ww(), scheme.ww())
    t += 1
  scheme.set_rank(rank)
  if ffbc_verify_exact(scheme) != 1
    return 0
  ffbc_write(path, scheme)

-> ffcisb_run(label, path, n, seed) (String String i64 i64) i64
  capacity = 1024 ## i64
  state = i64[ffw_state_size(capacity)]
  source_rank = ffw_load_scheme_cap(state, path, n, capacity, seed, 6, 4, 100000, 25000) ## i64
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  exported = ffw_export_best(state, source_u, source_v, source_w) ## i64
  ffcisb_expect("source " + label, source_rank > 0 && exported == source_rank && ffw_verify_best_exact(state, n) == 1)

  circuit_u = i64[12]
  circuit_v = i64[12]
  circuit_w = i64[12]
  meta = i64[13]
  circuit_count = ffcis_search_pairs(source_u, source_v, source_w, source_rank, 4, circuit_u, circuit_v, circuit_w, meta) ## i64
  ffcisb_expect("search " + label, circuit_count >= 5 && circuit_count <= 9)
  ffcisb_expect("primitive " + label, ffc_is_primitive_circuit(circuit_u, circuit_v, circuit_w, circuit_count) == 1)

  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  out_rank = 0 ## i64
  t = 0 ## i64
  while t < source_rank
    out_rank = ffsdr_toggle_term(out_u, out_v, out_w, out_rank, source_u[t], source_v[t], source_w[t])
    t += 1
  t = 0
  while t < circuit_count
    out_rank = ffsdr_toggle_term(out_u, out_v, out_w, out_rank, circuit_u[t], circuit_v[t], circuit_w[t])
    t += 1
  ffcisb_expect("rank accounting " + label, out_rank == source_rank + meta[8])
  ffcisb_expect("endpoint exact " + label, ffpbr_verify_exact(out_u, out_v, out_w, out_rank, n, n, n) == 1)
  distance = ffgir_term_set_distance(source_u, source_v, source_w, source_rank, out_u, out_v, out_w, out_rank) ## i64
  ffcisb_expect("distance " + label, distance == circuit_count)
  density = ffgir_density(out_u, out_v, out_w, out_rank) ## i64
  ffcisb_expect("density " + label, density == meta[9])
  output = "/tmp/matmul_" + n.to_s() + "x" + n.to_s() + "_rank" + out_rank.to_s() + "_circuit_image_s" + seed.to_s() + "_gf2.txt"
  ffcisb_expect("write " + label, ffcisb_write(output, out_u, out_v, out_w, out_rank, n) == out_rank)
  << "CIRCUIT_IMAGE_SEARCH tensor=" + label + " source=" + source_rank.to_s() + " best=" + out_rank.to_s() + " delta=" + meta[8].to_s() + " distance=" + distance.to_s() + " density=" + density.to_s() + " count=" + circuit_count.to_s() + " overlap=" + meta[11].to_s() + " max-overlap=" + meta[12].to_s() + " attempts=" + meta[0].to_s() + " consistent=" + meta[1].to_s() + " injective=" + meta[2].to_s() + " scored=" + meta[3].to_s() + " drops=" + meta[4].to_s() + " neutral=" + meta[5].to_s() + " plus1=" + meta[6].to_s() + " plus2=" + meta[7].to_s() + " output=" + output
  meta[8]

best_delta = ffcisb_run("4x4-d450", "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt", 4, 95101) ## i64
delta = ffcisb_run("5x5-d968", "benchmarks/matmul/metaflip/matmul_5x5_rank93_d968_global_isotropy_gf2.txt", 5, 95201) ## i64
if delta < best_delta
  best_delta = delta
delta = ffcisb_run("7x7-r247", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt", 7, 95301)
if delta < best_delta
  best_delta = delta
delta = ffcisb_run("4x4-d677", "benchmarks/matmul/metaflip/matmul_4x4_rank47_d677_flips_gf2.txt", 4, 95401)
if delta < best_delta
  best_delta = delta
delta = ffcisb_run("5x5-d1155", "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", 5, 95501)
if delta < best_delta
  best_delta = delta
delta = ffcisb_run("5x5-d1191", "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1191_gf2.txt", 5, 95601)
if delta < best_delta
  best_delta = delta
delta = ffcisb_run("5x5-alphaevolve", "benchmarks/matmul/metaflip/matmul_5x5_rank93_catalog_alphaevolve_gf2.txt", 5, 95701)
if delta < best_delta
  best_delta = delta
delta = ffcisb_run("5x5-kauers-a", "benchmarks/matmul/metaflip/matmul_5x5_rank93_catalog_kauers_a_gf2.txt", 5, 95801)
if delta < best_delta
  best_delta = delta
delta = ffcisb_run("5x5-perminov", "benchmarks/matmul/metaflip/matmul_5x5_rank93_catalog_perminov_c843_gf2.txt", 5, 95901)
if delta < best_delta
  best_delta = delta
delta = ffcisb_run("6x6-catalog", "benchmarks/matmul/metaflip/matmul_6x6_rank153_catalog_gf2.txt", 6, 96001)
if delta < best_delta
  best_delta = delta
delta = ffcisb_run("6x6-d2502", "benchmarks/matmul/metaflip/matmul_6x6_rank153_d2502_gf2.txt", 6, 96101)
if delta < best_delta
  best_delta = delta
delta = ffcisb_run("6x6-c3", "benchmarks/matmul/metaflip/matmul_6x6_rank153_d2574_c3_gf2.txt", 6, 96201)
if delta < best_delta
  best_delta = delta
delta = ffcisb_run("7x7-outer", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt", 7, 96301)
if delta < best_delta
  best_delta = delta
delta = ffcisb_run("7x7-c013", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt", 7, 96401)
if delta < best_delta
  best_delta = delta
delta = ffcisb_run("7x7-c021", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3554_outer_isotropy_c021_m4_gf2.txt", 7, 96501)
if delta < best_delta
  best_delta = delta
delta = ffcisb_run("7x7-c024", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3554_outer_isotropy_c024_m0_gf2.txt", 7, 96601)
if delta < best_delta
  best_delta = delta
<< "CIRCUIT_IMAGE_SEARCH_SUMMARY cases=16 best-delta=" + best_delta.to_s()
