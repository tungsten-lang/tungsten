use flipfleet_affine_code_descent
use flipfleet_partial_automorphism

-> ffacdt_expect(label, condition) (String bool) i64
  if !condition
    << "AFFINE_CODE_DESCENT_FAIL " + label
    exit(1)
  1

n = 2 ## i64
stride = 32 ## i64
bank_count = 3 ## i64
bank_u = i64[bank_count * stride]
bank_v = i64[bank_count * stride]
bank_w = i64[bank_count * stride]
bank_rank = i64[bank_count]

naive = i64[ffw_state_size(stride)]
bank_rank[0] = ffw_init_naive_cap(naive, n, stride, 910001, 0, 1, 1, 1)
z = ffacdt_expect("naive rank eight exact", bank_rank[0] == 8 && ffw_verify_current_exact(naive, n) == 1) ## i64
naive_u = i64[stride]
naive_v = i64[stride]
naive_w = i64[stride]
z = ffacdt_expect("naive export", ffw_export_current(naive, naive_u, naive_v, naive_w) == 8)
i = 0 ## i64
while i < bank_rank[0]
  bank_u[i] = naive_u[i]
  bank_v[i] = naive_v[i]
  bank_w[i] = naive_w[i]
  i += 1

strassen = i64[ffw_state_size(stride)]
bank_rank[1] = ffw_load_scheme_cap(strassen, "benchmarks/matmul/metaflip/matmul_2x2_rank7_strassen_gf2.txt", n, stride, 910003, 0, 1, 1, 1)
z = ffacdt_expect("Strassen exact", bank_rank[1] == 7 && ffw_verify_current_exact(strassen, n) == 1)
strassen_u = i64[stride]
strassen_v = i64[stride]
strassen_w = i64[stride]
z = ffacdt_expect("Strassen export", ffw_export_current(strassen, strassen_u, strassen_v, strassen_w) == 7)
i = 0
while i < bank_rank[1]
  bank_u[stride + i] = strassen_u[i]
  bank_v[stride + i] = strassen_v[i]
  bank_w[stride + i] = strassen_w[i]
  i += 1

# A second, globally transformed exact Strassen presentation ensures both
# single and pair loops are exercised by the planted decoder regression.
bank_rank[2] = 7
out = i64[3]
i = 0
while i < bank_rank[2]
  z = ffacdt_expect("global transform", ffpa_transform_term_kind(strassen_u[i], strassen_v[i], strassen_w[i], n, 0, 0, 0, 1, out) == 1)
  bank_u[2 * stride + i] = out[0]
  bank_v[2 * stride + i] = out[1]
  bank_w[2 * stride + i] = out[2]
  i += 1
transformed = i64[ffw_state_size(stride)]
loaded = ffw_init_terms_cap(transformed, bank_u.slice(2 * stride, stride), bank_v.slice(2 * stride, stride), bank_w.slice(2 * stride, stride), bank_rank[2], n, stride, 910007, 0, 1, 1, 1) ## i64
z = ffacdt_expect("global endpoint exact", loaded == 7 && ffw_verify_current_exact(transformed, n) == 1)

code = FFAffineCode.new(bank_u, bank_v, bank_w, bank_rank, bank_count, stride)
z = ffacdt_expect("code valid", code.valid() == 1)
z = ffacdt_expect("two nonzero generators", code.generator_count() == 2)
z = ffacdt_expect("nontrivial dimension", code.dimension() >= 1 && code.dimension() <= 2)
meta = i64[13]
best_rank = code.search(4, 2, 1, 1, 910009, meta) ## i64
z = ffacdt_expect("planted rank drop", best_rank == 7 && meta[8] == 7)
z = ffacdt_expect("single probes", meta[2] > 0)
z = ffacdt_expect("pair probe", meta[4] == 1)

best_u = i64[stride]
best_v = i64[stride]
best_w = i64[stride]
materialized = code.materialize_best(best_u, best_v, best_w) ## i64
gate = i64[ffw_state_size(stride)]
gated = ffw_init_terms_cap(gate, best_u, best_v, best_w, materialized, n, stride, 910013, 0, 1, 1, 1) ## i64
z = ffacdt_expect("materialized rank", materialized == 7 && gated == 7)
z = ffacdt_expect("full n^6 admission", ffw_verify_current_exact(gate, n) == 1)

# Pure combinatorial 3-opt trap.  Coordinates all have equal density.  The
# affine base is 00101 (rank two), while the three stored endpoints are
# 10110/11001/11111 (rank three/three/five). Every single and pair toggle has
# rank at least two, but toggling all three reaches 10000 (rank one).  This
# isolates the uphill/k-cube logic; the exact-tensor fixture above separately
# establishes that bank differences and final materialization pass n^6.
trap_stride = 8 ## i64
trap_count = 4 ## i64
trap_u = i64[trap_count * trap_stride]
trap_v = i64[trap_count * trap_stride]
trap_w = i64[trap_count * trap_stride]
trap_rank = i64[trap_count]
trap_masks = i64[trap_count]
trap_masks[0] = 5
trap_masks[1] = 22
trap_masks[2] = 25
trap_masks[3] = 31
scheme = 0 ## i64
while scheme < trap_count
  coordinate = 0 ## i64
  while coordinate < 5
    if ((trap_masks[scheme] >> coordinate) & 1) != 0
      position = trap_rank[scheme] ## i64
      trap_u[scheme * trap_stride + position] = 1 << coordinate
      trap_v[scheme * trap_stride + position] = 1
      trap_w[scheme * trap_stride + position] = 1
      trap_rank[scheme] = position + 1
    coordinate += 1
  scheme += 1
trap = FFAffineCode.new(trap_u, trap_v, trap_w, trap_rank, trap_count, trap_stride)
z = ffacdt_expect("3-opt trap valid", trap.valid() == 1 && trap.generator_count() == 3 && trap.dimension() == 3)
strict_meta = i64[13]
strict_rank = trap.search(1, 0, 1, 1, 920001, strict_meta) ## i64
z = ffacdt_expect("strict single/pair local minimum", strict_rank == 2 && strict_meta[3] == 0 && strict_meta[5] == 0 && strict_meta[4] == 3)
trap_current = i64[trap.words()]
ffacd_copy(trap.base(), 0, trap_current, 0, trap.words())
kmeta = i64[8]
k_rank = trap.kopt_step(trap_current, 3, 0, kmeta) ## i64
z = ffacdt_expect("planted 3-opt escape accepted", k_rank == 1 && ffacd_weight(trap_current, 0, trap.words()) == 1 && kmeta[1] == 7 && kmeta[2] == 1)
temper_meta = i64[20]
tempered_rank = trap.search_tempered(4, 4, 16384, 8, 3, 920003, temper_meta) ## i64
z = ffacdt_expect("tempering plus cube recovers plant", tempered_rank == 1 && temper_meta[1] == 16 && temper_meta[8] == 4 && temper_meta[9] == 28)

<< "flipfleet_affine_code_descent_test: pass coordinates=" + code.coordinate_count().to_s() + " generators=" + code.generator_count().to_s() + " dimension=" + code.dimension().to_s() + " best=r" + meta[8].to_s() + "/d" + meta[9].to_s() + " pair_probes=" + meta[4].to_s() + " planted_strict=" + strict_rank.to_s() + " planted_kopt=" + tempered_rank.to_s() + " planted_combos=" + temper_meta[9].to_s()
