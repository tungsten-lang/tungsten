use flipfleet_ternary_seed_variants

-> fftsvt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

root = "benchmarks/matmul/metaflip/"
paths = [
  root + "matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d1931_symmetry_escape_ternary.txt",
  root + "matmul_6x6_rank153_d1935_uphill_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d1938_index_shear_ternary.txt",
  root + "matmul_6x6_rank153_d2148_kauers_index_shear_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d2148_kauers_r153_index_shear_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d2502_ternary_walk.txt",
  root + "matmul_6x6_rank153_kauers_ternary.txt",
  root + "matmul_6x6_rank153_kauers_r153_ternary.txt"
]
capacity = fft_default_capacity(6) ## i64
cpu = []
gpu = []
i = 0 ## i64
while i < paths.size()
  raw = i64[fft_state_size(capacity)]
  rank = fft_load_seed(raw,paths[i],6,capacity,2026071800+i,3) ## i64
  z = fftsvt_expect("raw variant seed integer-gates",rank == 153) ## i64
  result = fftsv_add_variants(cpu,gpu,raw,2026071900+i,3) ## i64
  z = fftsvt_expect("variant expansion succeeds",result >= 0)
  i += 1

z = fftsvt_expect("one CPU-normalized seed per raw input",cpu.size() == 9)
z = fftsvt_expect("raw normalized and capped-door GPU variants deduplicate",gpu.size() == 15)

i = 0
while i < cpu.size()
  z = fftsvt_expect("CPU variant exact",fft_verify_best_exact(cpu[i]) == 1)
  z = fftsvt_expect("CPU variant is index-normalized",fft_index_shear_directed_descent(cpu[i]) == 0)
  i += 1

i = 0
while i < gpu.size()
  z = fftsvt_expect("GPU seed variant exact",fft_verify_best_exact(gpu[i]) == 1)
  j = 0 ## i64
  while j < i
    z = fftsvt_expect("GPU seed fingerprints unique",fft_current_fingerprint(gpu[i]) != fft_current_fingerprint(gpu[j]))
    j += 1
  i += 1

<< "PASS ternary seed variants: 9 raw 6x6 seeds -> 9 CPU-normalized and 15 unique GPU raw/normalized/capped-shallow seeds"
