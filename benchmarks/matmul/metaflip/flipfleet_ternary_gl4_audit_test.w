use flipfleet_ternary_worker

-> fftg4a_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

-> fftg4a_max_shared_factor_group(st) (i64[]) i64
  best = 0 ## i64
  axis = 0 ## i64
  while axis < 3
    first = 0 ## i64
    while first < st[5]
      count = 0 ## i64
      candidate = 0 ## i64
      while candidate < st[5]
        if fft_pair_relation(st,axis,first,candidate) != 0
          count += 1
        candidate += 1
      if count > best
        best = count
      first += 1
    axis += 1
  best

# A direct shared-factor GL(4) subtotal refactor needs at least four terms in
# one projective-factor bucket.  None of the pinned rank-best presentations
# has such a bucket, so a production GL4 probe would be a guaranteed miss.
root = "benchmarks/matmul/metaflip/"
paths = [
  root + "matmul_4x4_rank49_dronperminov_ternary.txt",
  root + "matmul_5x5_rank93_d1248_gl3_ternary.txt",
  root + "matmul_6x6_rank153_d2502_ternary_walk.txt",
  root + "matmul_7x7_rank250_dronperminov_ternary.txt",
  root + "matmul_7x7_rank250_d3069_ternary_door.txt",
  root + "matmul_5x5_rank93_d967_index_shear_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt"
]
dimensions = [4,5,6,7,7,5,6]
expected_maxima = [1,3,2,3,3,3,2]
i = 0 ## i64
while i < paths.size()
  n = dimensions[i] ## i64
  capacity = fft_default_capacity(n) ## i64
  state = i64[fft_state_size(capacity)]
  rank = fft_load_seed(state,paths[i],n,capacity,2026071580+i,3) ## i64
  z = fftg4a_expect("GL4 audit seed integer-gates",rank > 0) ## i64
  maximum = fftg4a_max_shared_factor_group(state) ## i64
  z = fftg4a_expect("pinned seed shared-factor maximum",maximum == expected_maxima[i] && maximum < 4)
  i += 1

<< "PASS ternary GL4 audit: pinned 4x4/5x5/6x6/7x7 projective-factor maxima 1/3/2/3; direct four-term lane inapplicable"
