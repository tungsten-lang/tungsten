# Matched one-CPU continuation from the shallowest new length-three endpoint,
# the shallowest admitted length-two endpoint, and an unmodified control.
# Each arm retains the source as its durable objective; only the live work-zone
# presentation differs.

use flipfleet_ternary_index_word3

-> fftiw3b_run(label,path,n,w2physical,w2d1,w2s1,w2c1,w2d2,w2s2,w2c2,w3physical,w3d1,w3s1,w3c1,w3d2,w3s2,w3c2,w3d3,w3s3,w3c3,steps,trials) (String String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  capacity = fft_default_capacity(n) ## i64
  source = i64[fft_state_size(capacity)]
  rank = fft_load_seed(source,path,n,capacity,2026072020+n,4) ## i64
  if rank < 1
    << "WORD3_BENCH_FAIL load " + label
    return 0 - 1
  start_density = source[21] ## i64
  gain = i64[3]
  drops = i64[3]
  changed = i64[3]
  accepted = i64[3]
  wins = i64[3]
  live_w2_w3 = 0 ## i64
  w2_debt = 0 ## i64
  w3_debt = 0 ## i64
  trial = 0 ## i64
  while trial < trials
    seed = 2026072100 + 1009*n + 7919*trial ## i64
    control = i64[fft_state_size(capacity)]
    word2 = i64[fft_state_size(capacity)]
    word3 = i64[fft_state_size(capacity)]
    if fft_clone_gated_seed(control,source,seed,4) < 1 || fft_clone_gated_seed(word2,source,seed,4) < 1 || fft_clone_gated_seed(word3,source,seed,4) < 1
      return 0 - 1
    if fftiw2_raw(word2,w2physical,w2d1,w2s1,w2c1,w2d2,w2s2,w2c2) != 2
      return 0 - 1
    if fftiw3_raw(word3,w3physical,w3d1,w3s1,w3c1,w3d2,w3s2,w3c2,w3d3,w3s3,w3c3) != 2
      return 0 - 1
    if trial == 0
      w2_debt = word2[20] - start_density
      w3_debt = word3[20] - start_density
      if fft_current_exact_error(word2) != 0 || fft_current_exact_error(word3) != 0
        return 0 - 1

    control_drop = fft_walk(control,steps) ## i64
    word2_drop = fft_walk(word2,steps) ## i64
    word3_drop = fft_walk(word3,steps) ## i64
    if control_drop < 0 || word2_drop < 0 || word3_drop < 0
      return 0 - 1
    drops[0] += control_drop
    drops[1] += word2_drop
    drops[2] += word3_drop
    cg = start_density-control[21] ## i64
    w2g = start_density-word2[21] ## i64
    w3g = start_density-word3[21] ## i64
    gain[0] += cg
    gain[1] += w2g
    gain[2] += w3g
    accepted[0] += control[10]
    accepted[1] += word2[10]
    accepted[2] += word3[10]
    if control[6] < rank || cg > 0
      changed[0] += 1
    if word2[6] < rank || w2g > 0
      changed[1] += 1
    if word3[6] < rank || w3g > 0
      changed[2] += 1
    best_rank = control[6] ## i64
    best_density = control[21] ## i64
    if word2[6] < best_rank || (word2[6] == best_rank && word2[21] < best_density)
      best_rank = word2[6]
      best_density = word2[21]
    if word3[6] < best_rank || (word3[6] == best_rank && word3[21] < best_density)
      best_rank = word3[6]
      best_density = word3[21]
    if control[6] == best_rank && control[21] == best_density
      wins[0] += 1
    if word2[6] == best_rank && word2[21] == best_density
      wins[1] += 1
    if word3[6] == best_rank && word3[21] == best_density
      wins[2] += 1
    if word2[5] != word3[5] || word2[20] != word3[20] || fft_current_fingerprint(word2) != fft_current_fingerprint(word3)
      live_w2_w3 += 1
    if trial == 0
      if fft_current_exact_error(control) != 0 || fft_current_exact_error(word2) != 0 || fft_current_exact_error(word3) != 0
        return 0 - 1
    trial += 1
  << "WORD3_CONT tensor=" + label + " trials=" + trials.to_s() + " steps=" + steps.to_s() + " debt=" + w3_debt.to_s() + "/" + w2_debt.to_s() + " gain=" + gain[2].to_s() + "/" + gain[1].to_s() + "/" + gain[0].to_s() + " best_ties=" + wins[2].to_s() + "/" + wins[1].to_s() + "/" + wins[0].to_s() + " changed=" + changed[2].to_s() + "/" + changed[1].to_s() + "/" + changed[0].to_s() + " drops=" + drops[2].to_s() + "/" + drops[1].to_s() + "/" + drops[0].to_s() + " accepted=" + accepted[2].to_s() + "/" + accepted[1].to_s() + "/" + accepted[0].to_s() + " live_w2_w3=" + live_w2_w3.to_s()
  1

steps = 1000000 ## i64
trials = 12 ## i64
if ARGV.size() > 0
  steps = ARGV[0].to_i()
if ARGV.size() > 1
  trials = ARGV[1].to_i()
if steps < 1 || trials < 1
  << "usage: flipfleet_ternary_index_word3_bench [steps-per-arm] [trials]"
  exit(2)

root = "benchmarks/matmul/metaflip/"
z = fftiw3b_run("4x4-r49-d432",root+"matmul_4x4_rank49_dronperminov_ternary.txt",4,2,0,3,0-1,0,1,0-1,2,0,3,0-1,1,0,0-1,0,1,1,steps,trials) ## i64
if z > 0
  z = fftiw3b_run("5x5-r93-d967",root+"matmul_5x5_rank93_d967_index_shear_gpu_ternary.txt",5,1,3,1,0-1,3,4,0-1,1,1,3,0-1,3,1,1,1,4,1,steps,trials)
if z > 0
  z = fftiw3b_run("6x6-r153-d1931",root+"matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt",6,1,3,4,1,3,1,1,0,4,3,0-1,3,1,0-1,3,4,1,steps,trials)
if z < 1
  << "FAIL ternary index word3 matched continuation"
  exit(1)
<< "PASS ternary index word3 matched continuation"
