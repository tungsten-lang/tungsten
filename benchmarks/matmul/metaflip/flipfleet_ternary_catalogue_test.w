use flipfleet_ternary_worker

-> fftct_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

root = "benchmarks/matmul/metaflip/"
paths = [
  root + "matmul_4x4_rank49_dronperminov_ternary.txt",
  root + "matmul_5x5_rank93_kauers_ternary.txt",
  root + "matmul_5x5_rank93_d1249_ternary_walk.txt",
  root + "matmul_5x5_rank93_d1248_gl3_ternary.txt",
  root + "matmul_6x6_rank153_kauers_ternary.txt",
  root + "matmul_6x6_rank153_kauers_r153_ternary.txt",
  root + "matmul_6x6_rank153_d2502_ternary_walk.txt",
  root + "matmul_7x7_rank250_dronperminov_ternary.txt",
  root + "matmul_7x7_rank250_d3069_ternary_door.txt",
  root + "matmul_5x5_rank93_d997_index_shear_ternary.txt",
  root + "matmul_6x6_rank153_d1938_index_shear_ternary.txt",
  root + "matmul_5x5_rank93_d967_index_shear_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt",
  root + "matmul_5x5_rank93_d1245_ternary_gpu.txt",
  root + "matmul_6x6_rank153_d2148_kauers_index_shear_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d2148_kauers_r153_index_shear_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d1953_kauers_compound_ternary.txt",
  root + "matmul_6x6_rank153_d1953_kauers_r153_compound_ternary.txt",
  root + "matmul_6x6_rank153_d1935_uphill_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d1931_symmetry_escape_ternary.txt"
]
dimensions = [4,5,5,5,6,6,6,7,7,5,6,5,6,5,6,6,6,6,6,6]
ranks = [49,93,93,93,153,153,153,250,250,93,153,93,153,93,153,153,153,153,153,153]
fingerprints = i64[paths.size()]
densities = i64[paths.size()]

i = 0 ## i64
while i < paths.size()
  n = dimensions[i] ## i64
  capacity = fft_default_capacity(n) ## i64
  state = i64[fft_state_size(capacity)]
  rank = fft_load_seed(state,paths[i],n,capacity,2026071400+i,3) ## i64
  z = fftct_expect("catalogue seed loads and integer-gates " + paths[i], rank == ranks[i]) ## i64
  z = fftct_expect("catalogue seed has no exact rejection " + paths[i], state[19] == 0)
  term = 0 ## i64
  canonical = 1 ## i64
  while term < rank
    if fft_first_sign(state[state[32]+term],state[state[33]+term]) != 1 || fft_first_sign(state[state[34]+term],state[state[35]+term]) != 1
      canonical = 0
    term += 1
  z = fftct_expect("catalogue seed is gauge canonical " + paths[i], canonical == 1)
  fingerprints[i] = fft_current_fingerprint(state)
  densities[i] = state[21]
  i += 1

z = fftct_expect("the two 6x6 catalogue records are distinct basins", fingerprints[4] != fingerprints[5])
z = fftct_expect("5x5 continuation improved equal-rank density", densities[2] == 1249 && densities[2] < densities[1])
z = fftct_expect("5x5 GL3 continuation improved equal-rank density", densities[3] == 1248 && densities[3] < densities[2])
z = fftct_expect("6x6 continuation improved equal-rank density", densities[6] == 2502 && densities[6] < densities[4] && densities[6] < densities[5])
z = fftct_expect("7x7 tunnel door is distinct and equal-rank", densities[8] == 3069 && fingerprints[8] != fingerprints[7])
z = fftct_expect("5x5 index-shear orbit is a new sparse presentation", densities[9] == 997 && fingerprints[9] != fingerprints[3] && densities[9] < densities[3])
z = fftct_expect("6x6 index-shear orbit is a new sparse presentation", densities[10] == 1938 && fingerprints[10] != fingerprints[6] && densities[10] < densities[6])
z = fftct_expect("5x5 GPU/index-shear compound continuation improved density", densities[11] == 967 && densities[11] < densities[9])
z = fftct_expect("6x6 GPU/index-shear compound continuation improved density", densities[12] == 1931 && densities[12] < densities[10])
z = fftct_expect("5x5 GPU continuation is a distinct retained basin", densities[13] == 1245 && densities[13] < densities[3] && fingerprints[13] != fingerprints[3])
z = fftct_expect("6x6 normalized-Kauers GPU doors are distinct", densities[14] == 2148 && densities[15] == 2148 && fingerprints[14] != fingerprints[15] && fingerprints[14] != fingerprints[12] && fingerprints[15] != fingerprints[12])
z = fftct_expect("6x6 compound d1953 doors are distinct and retained", densities[16] == 1953 && densities[17] == 1953 && fingerprints[16] != fingerprints[17] && fingerprints[16] != fingerprints[12] && fingerprints[17] != fingerprints[12])
z = fftct_expect("6x6 uphill symmetry escape closes to a new d1931 basin", densities[18] == 1935 && densities[19] == 1931 && fingerprints[19] != fingerprints[12] && fingerprints[18] != fingerprints[19])

bad_path = "/tmp/flipfleet_ternary_bad_seed.txt"
wrote = write_file(bad_path, "T 4 1\n1 1 1 0 1 0\n")
z = fftct_expect("malformed fixture written", wrote == true)
bad_state = i64[fft_state_size(fft_default_capacity(4))]
z = fftct_expect("overlapping signed masks rejected", fft_load_seed(bad_state,bad_path,4,fft_default_capacity(4),1,2) < 0)

wrong_state = i64[fft_state_size(fft_default_capacity(5))]
z = fftct_expect("header dimension mismatch rejected", fft_load_seed(wrong_state,paths[0],5,fft_default_capacity(5),1,2) < 0)

text_path = "/tmp/flipfleet_ternary_bad_decimal.txt"
wrote = write_file(text_path, "T 4 1\n1 nope 1 0 1 0\n")
z = fftct_expect("nonnumeric fixture written", wrote == true)
text_state = i64[fft_state_size(fft_default_capacity(4))]
z = fftct_expect("nonnumeric mask rejected", fft_load_seed(text_state,text_path,4,fft_default_capacity(4),1,2) < 0)

<< "PASS ternary catalogue: 4x4/r49 5x5/r93+d967 6x6/r153+d1931 7x7/r250+d3069-door all exact over integers"
