use flipfleet_ternary_index_shear

-> fftist_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

root = "benchmarks/matmul/metaflip/"

# The first 5x5 descent step and its exact inverse exercise all of the atomic
# machinery independently of the deterministic closure.
capacity5 = fft_default_capacity(5) ## i64
roundtrip = i64[fft_state_size(capacity5)]
rank = fft_load_seed(roundtrip,root + "matmul_5x5_rank93_d1248_gl3_ternary.txt",5,capacity5,2026071481,3) ## i64
z = fftist_expect("5x5 source gates",rank == 93 && roundtrip[21] == 1248) ## i64
source_fingerprint = fft_current_fingerprint(roundtrip) ## i64
result = fft_index_shear_apply(roundtrip,0,2,3,0-1,0-1) ## i64
z = fftist_expect("5x5 exact index shear improves by sixty",result == 1 && roundtrip[20] == 1188 && roundtrip[21] == 1188)
z = fftist_expect("5x5 sheared endpoint exact",fft_verify_current_exact(roundtrip) == 1 && fft_verify_best_exact(roundtrip) == 1)
result = fft_index_shear_apply(roundtrip,0,2,3,1,1)
z = fftist_expect("inverse shear restores source",result == 1 && roundtrip[20] == 1248 && fft_current_fingerprint(roundtrip) == source_fingerprint)
z = fftist_expect("inverse-restored source exact",fft_verify_current_exact(roundtrip) == 1)

# Fixed points can still have legal denser isotropy doors.  They are not
# production rewards, but dumping the shallowest doors makes a bounded
# downstream GPU-closing experiment reproducible.
door5 = i64[fft_state_size(capacity5)]
rank = fft_load_seed(door5,root + "matmul_5x5_rank93_d967_index_shear_gpu_ternary.txt",5,capacity5,2026071482,3)
z = fftist_expect("5x5 fixed-point door seed gates",rank == 93 && door5[21] == 967)
door_delta = fft_index_shear_shallow_positive_door(door5,8) ## i64
z = fftist_expect("5x5 shallow denser isotropy door",door_delta == 7 && door5[20] == 974 && door5[21] == 967 && fft_verify_current_exact(door5) == 1)
z = fftist_expect("5x5 shallow door dumps",fft_dump_current(door5,"/tmp/matmul_5x5_rank93_d974_index_wander_ternary.txt") == 93)

capacity6 = fft_default_capacity(6) ## i64
door6 = i64[fft_state_size(capacity6)]
rank = fft_load_seed(door6,root + "matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt",6,capacity6,2026071483,3)
z = fftist_expect("6x6 fixed-point door seed gates",rank == 153 && door6[21] == 1931)
door_delta = fft_index_shear_shallow_positive_door(door6,8)
z = fftist_expect("6x6 shallow denser isotropy door",door_delta == 6 && door6[20] == 1937 && door6[21] == 1931 && fft_verify_current_exact(door6) == 1)
z = fftist_expect("6x6 shallow door dumps",fft_dump_current(door6,"/tmp/matmul_6x6_rank153_d1937_index_wander_ternary.txt") == 153)

capacity4 = fft_default_capacity(4) ## i64
no_door4 = i64[fft_state_size(capacity4)]
rank = fft_load_seed(no_door4,root + "matmul_4x4_rank49_dronperminov_ternary.txt",4,capacity4,2026071484,3)
z = fftist_expect("4x4 shallow-door control gates",rank == 49 && no_door4[21] == 432)
z = fftist_expect("4x4 has no symmetry door within cap eight",fft_index_shear_shallow_positive_door(no_door4,8) == 0 && no_door4[20] == 432)

# Steepest closure produces two large, independently integer-gated orbit
# presentations.  These are useful search doors even though rank is unchanged.
paths = [
  root + "matmul_4x4_rank49_dronperminov_ternary.txt",
  root + "matmul_5x5_rank93_d1248_gl3_ternary.txt",
  root + "matmul_6x6_rank153_d2502_ternary_walk.txt",
  root + "matmul_7x7_rank250_dronperminov_ternary.txt",
  root + "matmul_7x7_rank250_d3069_ternary_door.txt",
  root + "matmul_5x5_rank93_d1245_ternary_gpu.txt",
  root + "matmul_5x5_rank93_d967_index_shear_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d2148_kauers_index_shear_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d2148_kauers_r153_index_shear_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d1935_uphill_gpu_ternary.txt",
  root + "matmul_6x6_rank153_d1931_symmetry_escape_ternary.txt"
]
dimensions = [4,5,6,7,7,5,5,6,6,6,6,6]
start_densities = [432,1248,2502,2966,3069,1245,967,1931,2148,2148,1935,1931]
want_densities = [432,997,1938,2966,3069,994,967,1931,1953,1953,1931,1931]
want_steps = [0,10,11,0,0,10,0,0,3,3,1,0]
i = 0 ## i64
while i < paths.size()
  n = dimensions[i] ## i64
  capacity = fft_default_capacity(n) ## i64
  state = i64[fft_state_size(capacity)]
  rank = fft_load_seed(state,paths[i],n,capacity,2026071490+i,3) ## i64
  z = fftist_expect("control seed gates",rank > 0 && state[21] == start_densities[i])
  steps = fft_index_shear_directed_descent(state) ## i64
  z = fftist_expect("directed index-shear closure count",steps == want_steps[i])
  z = fftist_expect("directed index-shear closure density",state[21] == want_densities[i] && state[20] == want_densities[i])
  z = fftist_expect("directed index-shear endpoint exact",fft_verify_current_exact(state) == 1 && fft_verify_best_exact(state) == 1)
  z = fftist_expect("directed index-shear fixed point",fft_index_shear_directed_descent(state) == 0 && state[21] == want_densities[i])
  if i == 1
    z = fftist_expect("5x5 index-shear certificate dumps",fft_dump_best(state,"/tmp/matmul_5x5_rank93_d997_index_shear_ternary.txt") == 93)
  if i == 2
    z = fftist_expect("6x6 index-shear certificate dumps",fft_dump_best(state,"/tmp/matmul_6x6_rank153_d1938_index_shear_ternary.txt") == 153)
  i += 1

<< "PASS ternary index-shear normalization: 5x5 d1248->d997 and GPU d967 fixed; 6x6 d2502->d1938, old/new d1931 fixed, d2148->d1953, uphill GPU d1935->new d1931; 4x4/7x7 controls fixed"
