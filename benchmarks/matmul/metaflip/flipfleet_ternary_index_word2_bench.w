# Matched one-CPU continuation from the shallowest atomic length-two index
# word versus the unmodified real-frontier leader.  The source remains the
# durable objective in the tunnel arm; the denser exact endpoint is only its
# starting work-zone presentation.

use flipfleet_ternary_index_word2

-> fftiw2b_run(label,path,n,physical,d1,s1,c1,d2,s2,c2,steps,trials) (String String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  capacity = fft_default_capacity(n) ## i64
  source = i64[fft_state_size(capacity)]
  rank = fft_load_seed(source,path,n,capacity,2026071820+n,4) ## i64
  if rank < 1
    << "WORD2_BENCH_FAIL load " + label
    return 0 - 1
  start_density = source[21] ## i64
  control_gain = 0 ## i64
  tunnel_gain = 0 ## i64
  control_drops = 0 ## i64
  tunnel_drops = 0 ## i64
  tunnel_wins = 0 ## i64
  control_wins = 0 ## i64
  ties = 0 ## i64
  changed_control = 0 ## i64
  changed_tunnel = 0 ## i64
  live_diverse = 0 ## i64
  accepted_control = 0 ## i64
  accepted_tunnel = 0 ## i64
  debt = 0 ## i64
  trial = 0 ## i64
  while trial < trials
    seed = 2026071900 + 1009*n + 7919*trial ## i64
    control = i64[fft_state_size(capacity)]
    tunnel = i64[fft_state_size(capacity)]
    if fft_clone_gated_seed(control,source,seed,4) < 1 || fft_clone_gated_seed(tunnel,source,seed,4) < 1
      return 0 - 1
    result = fftiw2_raw(tunnel,physical,d1,s1,c1,d2,s2,c2) ## i64
    if result != 2
      return 0 - 1
    if trial == 0
      debt = tunnel[20] - start_density
      if fft_current_exact_error(tunnel) != 0
        return 0 - 1

    cd = fft_walk(control,steps) ## i64
    td = fft_walk(tunnel,steps) ## i64
    if cd < 0 || td < 0
      return 0 - 1
    control_drops += cd
    tunnel_drops += td
    accepted_control += control[10]
    accepted_tunnel += tunnel[10]
    cg = start_density - control[21] ## i64
    tg = start_density - tunnel[21] ## i64
    control_gain += cg
    tunnel_gain += tg
    if control[6] < rank || cg > 0
      changed_control += 1
    if tunnel[6] < rank || tg > 0
      changed_tunnel += 1
    if tunnel[6] < control[6] || (tunnel[6] == control[6] && tunnel[21] < control[21])
      tunnel_wins += 1
    elsif control[6] < tunnel[6] || (control[6] == tunnel[6] && control[21] < tunnel[21])
      control_wins += 1
    else
      ties += 1
    if tunnel[5] != control[5] || tunnel[20] != control[20] || fft_current_fingerprint(tunnel) != fft_current_fingerprint(control)
      live_diverse += 1
    if trial == 0
      if fft_current_exact_error(control) != 0 || fft_current_exact_error(tunnel) != 0
        return 0 - 1
    trial += 1
  << "WORD2_CONT tensor=" + label + " trials=" + trials.to_s() + " steps=" + steps.to_s() + " debt=" + debt.to_s() + " gain=" + tunnel_gain.to_s() + "/" + control_gain.to_s() + " wins=" + tunnel_wins.to_s() + "/" + control_wins.to_s() + "/" + ties.to_s() + " changed=" + changed_tunnel.to_s() + "/" + changed_control.to_s() + " drops=" + tunnel_drops.to_s() + "/" + control_drops.to_s() + " accepted=" + accepted_tunnel.to_s() + "/" + accepted_control.to_s() + " live_diverse=" + live_diverse.to_s()
  1

steps = 1000000 ## i64
trials = 12 ## i64
if ARGV.size() > 0
  steps = ARGV[0].to_i()
if ARGV.size() > 1
  trials = ARGV[1].to_i()
if steps < 1 || trials < 1
  << "usage: flipfleet_ternary_index_word2_bench [steps-per-arm] [trials]"
  exit(2)

root = "benchmarks/matmul/metaflip/"
z = fftiw2b_run("4x4-r49-d432",root+"matmul_4x4_rank49_dronperminov_ternary.txt",4,2,0,3,0-1,0,1,0-1,steps,trials) ## i64
if z > 0
  z = fftiw2b_run("5x5-r93-d967",root+"matmul_5x5_rank93_d967_index_shear_gpu_ternary.txt",5,1,3,1,0-1,3,4,0-1,steps,trials)
if z > 0
  z = fftiw2b_run("6x6-r153-d1931",root+"matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt",6,1,3,4,1,3,1,1,steps,trials)
if z < 1
  << "FAIL ternary index word2 matched continuation"
  exit(1)
<< "PASS ternary index word2 matched continuation"
