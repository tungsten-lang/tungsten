use flipfleet_kernel_shear_rankdrop

-> ffksrt_expect(label, condition) (String bool) i64
  if !condition
    << "KERNEL_SHEAR_RANKDROP_FAIL " + label
    exit(1)
  1

# Split one Strassen term into two terms with the same V/W factors.  The
# zero-admitting kernel dependency must restore the exact rank-seven scheme.
n = 2 ## i64
capacity = 32 ## i64
base = i64[ffw_state_size(capacity)]
base_rank = ffw_load_scheme_cap(base, "benchmarks/matmul/metaflip/matmul_2x2_rank7_strassen_gf2.txt", n, capacity, 99101, 0, 1, 1, 1) ## i64
ffksrt_expect("base exact", base_rank == 7 && ffw_verify_current_exact(base, n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
ffksrt_expect("base export", ffw_export_current(base, base_u, base_v, base_w) == base_rank)

x = 1 ## i64
while x == base_u[0] || (base_u[0] ^ x) == 0
  x = x << 1
shoulder_rank = base_rank + 1 ## i64
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
shoulder_u[0] = base_u[0] ^ x
shoulder_v[0] = base_v[0]
shoulder_w[0] = base_w[0]
shoulder_u[1] = x
shoulder_v[1] = base_v[0]
shoulder_w[1] = base_w[0]
i = 1 ## i64
while i < base_rank
  shoulder_u[i + 1] = base_u[i]
  shoulder_v[i + 1] = base_v[i]
  shoulder_w[i + 1] = base_w[i]
  i += 1
ffksrt_expect("split shoulder local exact", fftc_local_exact(base_u, base_v, base_w, base_rank, shoulder_u, shoulder_v, shoulder_w, shoulder_rank) == 1)

axes = i64[shoulder_rank]
i = 0
while i < shoulder_rank
  axes[i] = 0
  i += 1
out_u = i64[capacity]
out_v = i64[capacity]
out_w = i64[capacity]
meta = i64[16]
found = ffksr_find_best_bounded(shoulder_u, shoulder_v, shoulder_w, shoulder_rank, axes, n * n, 0, out_u, out_v, out_w, meta) ## i64
ffksrt_expect("rank drop found", found == 7 && meta[4] >= 1 && meta[9] + meta[10] >= 1)
check = i64[ffw_state_size(capacity)]
loaded = ffw_init_terms_cap(check, out_u, out_v, out_w, found, n, capacity, 99201, 0, 1, 1, 1) ## i64
ffksrt_expect("full exact rank seven", loaded == 7 && ffw_verify_current_exact(check, n) == 1)
<< "flipfleet_kernel_shear_rankdrop_test: all checks passed dependencies=" + meta[2].to_s() + " rankdrops=" + meta[4].to_s() + " zeros=" + meta[9].to_s() + " duplicate_pairs=" + meta[10].to_s()
