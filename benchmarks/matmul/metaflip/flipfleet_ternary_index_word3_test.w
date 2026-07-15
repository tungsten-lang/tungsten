use flipfleet_ternary_index_word3

-> fftiw3t_expect(label,condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

-> fftiw3t_fixture(label,path,n,rank,physical,d1,s1,c1,d2,s2,c2,d3,s3,c3,debt,seed) (String String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  capacity = fft_default_capacity(n) ## i64
  state = i64[fft_state_size(capacity)]
  z = fftiw3t_expect(label+" load",fft_load_seed(state,path,n,capacity,seed,4) == rank) ## i64
  source_fp = fft_current_fingerprint(state) ## i64
  source_density = state[20] ## i64
  z = fftiw3t_expect(label+" reduced",fftiw3_reduction_reason(n,d1,s1,c1,d2,s2,c2,d3,s3,c3) == 0)
  result = fftiw3_raw(state,physical,d1,s1,c1,d2,s2,c2,d3,s3,c3) ## i64
  z = fftiw3t_expect(label+" atomic endpoint",result == 2)
  z = fftiw3t_expect(label+" exact changed endpoint",state[20] == source_density+debt && fft_current_fingerprint(state) != source_fp && fft_current_exact_error(state) == 0)
  result = fftiw3_inverse_raw(state,physical,d1,s1,c1,d2,s2,c2,d3,s3,c3)
  z = fftiw3t_expect(label+" atomic inverse",result == 2)
  z = fftiw3t_expect(label+" exact round trip",state[20] == source_density && fft_current_fingerprint(state) == source_fp && fft_current_exact_error(state) == 0)
  1

root = "benchmarks/matmul/metaflip/"
z = fftiw3t_fixture("4x4",root+"matmul_4x4_rank49_dronperminov_ternary.txt",4,49,2,0,3,0-1,1,0,0-1,0,1,1,72,2026072011) ## i64
z = fftiw3t_fixture("5x5",root+"matmul_5x5_rank93_d967_index_shear_gpu_ternary.txt",5,93,1,1,3,0-1,3,1,1,1,4,1,24,2026072012)
z = fftiw3t_fixture("6x6",root+"matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt",6,153,0,4,3,0-1,3,1,0-1,3,4,1,76,2026072013)
<< "PASS ternary atomic index word3: exhaustive-audit fixtures are bidirectional, exact integer endpoints with exact inverses"
