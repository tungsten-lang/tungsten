use flipfleet_ternary_index_word2

-> fftiw2t_expect(label,condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

root = "benchmarks/matmul/metaflip/"

# The shallowest 4x4 barrier word found by the exhaustive audit.  Its first
# elementary shear is illegal on the source; the complete two-generator word
# is final-strict and exact, and the first inverse generator is likewise
# illegal on the endpoint.  Thus neither direction can traverse this word one
# strict elementary step at a time.
capacity4 = fft_default_capacity(4) ## i64
state4 = i64[fft_state_size(capacity4)]
z = fftiw2t_expect("load 4x4 leader",fft_load_seed(state4,root+"matmul_4x4_rank49_dronperminov_ternary.txt",4,capacity4,2026071811,4) == 49) ## i64
fp4 = fft_current_fingerprint(state4) ## i64
d4 = state4[20] ## i64
z = fftiw2t_expect("4x4 first elementary intermediate illegal",fft_index_shear_raw(state4,2,0,3,0-1) == 0)
z = fftiw2t_expect("failed elementary preflight is atomic",fft_current_fingerprint(state4) == fp4 && state4[20] == d4)
z = fftiw2t_expect("4x4 atomic word admitted",fftiw2_raw(state4,2,0,3,0-1,0,1,0-1) == 2)
z = fftiw2t_expect("4x4 atomic endpoint changed support density",state4[20] == d4 + 72 && fft_current_fingerprint(state4) != fp4)
z = fftiw2t_expect("4x4 atomic endpoint integer exact",fft_current_exact_error(state4) == 0)
atomic_fp4 = fft_current_fingerprint(state4) ## i64
z = fftiw2t_expect("4x4 first inverse elementary illegal",fft_index_shear_raw(state4,2,0,1,1) == 0)
z = fftiw2t_expect("failed inverse preflight leaves endpoint",fft_current_fingerprint(state4) == atomic_fp4)
z = fftiw2t_expect("4x4 atomic inverse admitted",fftiw2_inverse_raw(state4,2,0,3,0-1,0,1,0-1) == 2)
z = fftiw2t_expect("4x4 inverse restores canonical source",state4[20] == d4 && fft_current_fingerprint(state4) == fp4 && fft_current_exact_error(state4) == 0)

# Repeat the planted barrier/inverse gate on the shallowest 5x5 and 6x6 real
# leaders.  These fixtures also protect the row/column pairing specifications
# for the other two physical indices.
capacity5 = fft_default_capacity(5) ## i64
state5 = i64[fft_state_size(capacity5)]
z = fftiw2t_expect("load 5x5 leader",fft_load_seed(state5,root+"matmul_5x5_rank93_d967_index_shear_gpu_ternary.txt",5,capacity5,2026071812,4) == 93)
fp5 = fft_current_fingerprint(state5) ## i64
d5 = state5[20] ## i64
z = fftiw2t_expect("5x5 first elementary illegal",fft_index_shear_raw(state5,1,3,1,0-1) == 0)
z = fftiw2t_expect("5x5 atomic word admitted",fftiw2_raw(state5,1,3,1,0-1,3,4,0-1) == 2)
z = fftiw2t_expect("5x5 exact changed endpoint",state5[20] == d5 + 24 && fft_current_fingerprint(state5) != fp5 && fft_current_exact_error(state5) == 0)
z = fftiw2t_expect("5x5 inverse restores",fftiw2_inverse_raw(state5,1,3,1,0-1,3,4,0-1) == 2 && state5[20] == d5 && fft_current_fingerprint(state5) == fp5)

capacity6 = fft_default_capacity(6) ## i64
state6 = i64[fft_state_size(capacity6)]
z = fftiw2t_expect("load 6x6 leader",fft_load_seed(state6,root+"matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt",6,capacity6,2026071813,4) == 153)
fp6 = fft_current_fingerprint(state6) ## i64
d6 = state6[20] ## i64
z = fftiw2t_expect("6x6 first elementary illegal",fft_index_shear_raw(state6,1,3,4,1) == 0)
z = fftiw2t_expect("6x6 atomic word admitted",fftiw2_raw(state6,1,3,4,1,3,1,1) == 2)
z = fftiw2t_expect("6x6 exact changed endpoint",state6[20] == d6 + 69 && fft_current_fingerprint(state6) != fp6 && fft_current_exact_error(state6) == 0)
z = fftiw2t_expect("6x6 inverse restores",fftiw2_inverse_raw(state6,1,3,4,1,3,1,1) == 2 && state6[20] == d6 && fft_current_fingerprint(state6) == fp6)

# Admission helper reproduces the exhaustive audit minima while retaining the
# original exact best objective behind each denser work-zone door.
door4 = i64[fft_state_size(capacity4)]
z = fftiw2t_expect("clone 4x4 admission source",fft_clone_gated_seed(door4,state4,2026071814,4) == 49)
door_meta = i64[4]
z = fftiw2t_expect("4x4 shallow atomic admission",fftiw2_shallow_atomic_door(door4,96,door_meta) == 1 && door_meta[0] == 72 && door_meta[2] == 16 && door4[20] == 504 && door4[21] == 432)
z = fftiw2t_expect("4x4 admitted door exact",fft_current_exact_error(door4) == 0)

door5 = i64[fft_state_size(capacity5)]
z = fftiw2t_expect("clone 5x5 admission source",fft_clone_gated_seed(door5,state5,2026071815,4) == 93)
z = fftiw2t_expect("5x5 shallow atomic admission",fftiw2_shallow_atomic_door(door5,96,door_meta) == 1 && door_meta[0] == 24 && door_meta[2] == 7 && door5[20] == 991 && door5[21] == 967)
z = fftiw2t_expect("5x5 admitted door exact",fft_current_exact_error(door5) == 0)

door6 = i64[fft_state_size(capacity6)]
z = fftiw2t_expect("clone 6x6 admission source",fft_clone_gated_seed(door6,state6,2026071816,4) == 153)
z = fftiw2t_expect("6x6 shallow atomic admission",fftiw2_shallow_atomic_door(door6,96,door_meta) == 1 && door_meta[0] == 69 && door_meta[2] == 38 && door6[20] == 2000 && door6[21] == 1931)
z = fftiw2t_expect("6x6 admitted door exact",fft_current_exact_error(door6) == 0)

<< "PASS ternary atomic index word2: planted bidirectional strict barriers at 4x4/5x5/6x6, exact integer endpoints, exact inverses"
