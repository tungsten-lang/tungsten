use flipfleet_projection_replacement
use metaflip_worker

-> ffprb_expect(label, condition) (String bool) i64
  if !condition
    << "PROJECTION_REPLACEMENT_FAIL " + label
    exit(1)
  1

-> ffprb_case(root, source_path, lower_path, n, d, seed) (String String String i64 i64 i64) i64
  capacity = 1024 ## i64
  source_state = i64[ffw_state_size(capacity)]
  source_rank = ffw_load_scheme_cap(source_state, root + source_path, n, capacity, seed, 6, 4, 100000, 25000) ## i64
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  exported = ffw_export_best(source_state, source_u, source_v, source_w) ## i64
  ffprb_expect("source exact " + source_path, source_rank > 0 && exported == source_rank && ffw_verify_best_exact(source_state, n) == 1)

  lower_state = i64[ffw_state_size(capacity)]
  lower_rank = ffw_load_scheme_cap(lower_state, root + lower_path, d, capacity, seed + 17, 6, 4, 100000, 25000) ## i64
  lower_u = i64[capacity]
  lower_v = i64[capacity]
  lower_w = i64[capacity]
  lower_exported = ffw_export_best(lower_state, lower_u, lower_v, lower_w) ## i64
  ffprb_expect("lower exact " + lower_path, lower_rank > 0 && lower_exported == lower_rank && ffw_verify_best_exact(lower_state, d) == 1)

  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  meta = i64[8]
  result = ffpr_splice(source_u, source_v, source_w, source_rank, lower_u, lower_v, lower_w, lower_rank, n, d, out_u, out_v, out_w, capacity, meta) ## i64
  ffprb_expect("splice exact " + source_path + "/" + lower_path, result > 0 && meta[7] == 1 && ffpbr_verify_exact(out_u, out_v, out_w, result, n, n, n) == 1)
  << "PROJECTION_REPLACEMENT size=" + n.to_s() + " core=" + d.to_s() + " source=" + source_rank.to_s() + " projected=" + meta[1].to_s() + " lower=" + lower_rank.to_s() + " final=" + result.to_s() + " debt=" + meta[4].to_s() + " project-zero=" + meta[5].to_s() + " canceled=" + meta[6].to_s() + " source-file=" + source_path + " lower-file=" + lower_path
  meta[4]

root = "benchmarks/matmul/metaflip/"
p2 = "matmul_2x2_rank7_strassen_gf2.txt"
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
seed = 81001 ## i64

# Small frontiers and both same-rank lower-core families where available.
sources = [s4, s4,
           s5, s5, s5, s5, s5,
           s6, s6, s6, s6, s6, s6,
           s7a, s7a, s7a, s7a, s7a, s7a, s7a, s7a, s7a,
           s7b, s7b, s7b, s7b, s7b, s7b, s7b, s7b, s7b]
lowers = [p2, p3a,
          p2, p3a, p3b, p4a, p4b,
          p2, p3a, p4a, p4b, p5a, p5b,
          p2, p3a, p3b, p4a, p4b, p5a, p5b, p6a, p6b,
          p2, p3a, p3b, p4a, p4b, p5a, p5b, p6a, p6b]
ns = i64[31]
ds = i64[31]
i = 0 ## i64
while i < 2
  ns[i] = 4
  i += 1
while i < 7
  ns[i] = 5
  i += 1
while i < 13
  ns[i] = 6
  i += 1
while i < 31
  ns[i] = 7
  i += 1
ds[0] = 2
ds[1] = 3
ds[2] = 2
ds[3] = 3
ds[4] = 3
ds[5] = 4
ds[6] = 4
ds[7] = 2
ds[8] = 3
ds[9] = 4
ds[10] = 4
ds[11] = 5
ds[12] = 5
i = 13
while i < 31
  offset = (i - 13) % 9 ## i64
  if offset == 0
    ds[i] = 2
  elsif offset == 1 || offset == 2
    ds[i] = 3
  elsif offset == 3 || offset == 4
    ds[i] = 4
  elsif offset == 5 || offset == 6
    ds[i] = 5
  else
    ds[i] = 6
  i += 1

i = 0
while i < sources.size()
  debt = ffprb_case(root, sources[i], lowers[i], ns[i], ds[i], seed + i * 101) ## i64
  if debt < best_debt
    best_debt = debt
  case_count += 1
  i += 1

<< "PROJECTION_REPLACEMENT_SUMMARY cases=" + case_count.to_s() + " best-debt=" + best_debt.to_s()
