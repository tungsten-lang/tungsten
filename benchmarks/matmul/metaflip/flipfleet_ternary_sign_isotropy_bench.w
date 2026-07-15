# Matched continuation audit for the diagonal sign isotropy.  For each trial,
# the control and signed clone receive the same RNG seed and move budget.  The
# signed clone starts from an exact rank/density-identical conjugate.  This
# measures whether gauge canonicalization provides useful practical diversity
# despite the underlying local move graphs being sign-conjugate.

use flipfleet_ternary_sign_isotropy

-> fftsib_run(label,path,n,steps,trials) (String String i64 i64 i64) i64
  capacity = fft_default_capacity(n) ## i64
  source = i64[fft_state_size(capacity)]
  rank = fft_load_seed(source,path,n,capacity,2026071611+n,4) ## i64
  if rank < 1
    << "FAIL load " + label + " " + path
    return 0 - 1
  start_density = source[21] ## i64
  masks = i64[3]
  control_gain = 0 ## i64
  signed_gain = 0 ## i64
  control_drops = 0 ## i64
  signed_drops = 0 ## i64
  signed_wins = 0 ## i64
  control_wins = 0 ## i64
  ties = 0 ## i64
  conjugate_returns = 0 ## i64
  conjugate_walks = 0 ## i64
  accepted_control = 0 ## i64
  accepted_signed = 0 ## i64
  telemetry_mismatches = 0 ## i64
  changed_control = 0 ## i64
  changed_signed = 0 ## i64
  trial = 0 ## i64
  while trial < trials
    seed = 2026071700 + 1009*n + 7919*trial ## i64
    control = i64[fft_state_size(capacity)]
    signed = i64[fft_state_size(capacity)]
    if fft_clone_gated_seed(control,source,seed,4) < 1 || fft_clone_gated_seed(signed,source,seed,4) < 1
      return 0 - 1
    source_fp = fft_current_fingerprint(control) ## i64
    z = fftsi_trial_masks(n,trial,masks) ## i64
    if fftsi_raw(signed,masks[0],masks[1],masks[2]) != 1
      return 0 - 1
    signed_start_fp = fft_current_fingerprint(signed) ## i64
    if signed_start_fp == source_fp || signed[20] != start_density
      return 0 - 1
    # Promote the exact conjugate as this island's objective without charging
    # an n^6 gate inside the timed continuation.
    z = fft_copy_current_to_best(signed)

    cd = fft_walk(control,steps) ## i64
    sd = fft_walk(signed,steps) ## i64
    if cd < 0 || sd < 0
      return 0 - 1
    control_drops += cd
    signed_drops += sd
    accepted_control += control[10]
    accepted_signed += signed[10]
    if control[10] != signed[10] || control[11] != signed[11] || control[13] != signed[13] || control[15] != signed[15] || control[17] != signed[17]
      telemetry_mismatches += 1
    cg = start_density - control[21] ## i64
    sg = start_density - signed[21] ## i64
    control_gain += cg
    signed_gain += sg
    if control[6] < rank || cg > 0
      changed_control += 1
    if signed[6] < rank || sg > 0
      changed_signed += 1
    if signed[6] < control[6] || (signed[6] == control[6] && signed[21] < control[21])
      signed_wins += 1
    elsif control[6] < signed[6] || (control[6] == signed[6] && control[21] < signed[21])
      control_wins += 1
    else
      ties += 1

    # Compare the live endpoints before either best restore.  Equality after
    # inverse conjugation means every accepted/rejected step—not merely the
    # objective—was a re-labeling of the control walk.
    control_live_fp = fft_current_fingerprint(control) ## i64
    control_live_rank = control[5] ## i64
    control_live_density = control[20] ## i64
    signed_live_rank = signed[5] ## i64
    signed_live_density = signed[20] ## i64
    z = fftsi_raw(signed,masks[0],masks[1],masks[2])
    if z != 1
      return 0 - 1
    if signed_live_rank == control_live_rank && signed_live_density == control_live_density && fft_current_fingerprint(signed) == control_live_fp
      conjugate_walks += 1

    # Compare the durable endpoints after mapping the signed result back to
    # the control coordinate signs.  Equality here exposes pure re-labeling.
    z = fft_restore_best(control)
    z = fft_restore_best(signed)
    control_fp = fft_current_fingerprint(control) ## i64
    z = fftsi_raw(signed,masks[0],masks[1],masks[2])
    if z != 1
      return 0 - 1
    if fft_current_fingerprint(signed) == control_fp
      conjugate_returns += 1
    if trial == 0
      if fft_current_exact_error(control) != 0 || fft_current_exact_error(signed) != 0
        return 0 - 1
    trial += 1

  << label + " trials=" + trials.to_s() + " steps=" + steps.to_s() + " control_gain=" + control_gain.to_s() + " signed_gain=" + signed_gain.to_s() + " wins=" + signed_wins.to_s() + "/" + control_wins.to_s() + "/" + ties.to_s() + " changed=" + changed_signed.to_s() + "/" + changed_control.to_s() + " drops=" + signed_drops.to_s() + "/" + control_drops.to_s() + " accepted=" + accepted_signed.to_s() + "/" + accepted_control.to_s() + " telemetry_mismatch=" + telemetry_mismatches.to_s() + " conjugate_walks=" + conjugate_walks.to_s() + " conjugate_returns=" + conjugate_returns.to_s()
  1

steps = 1000000 ## i64
trials = 12 ## i64
if ARGV.size() > 0
  steps = ARGV[0].to_i()
if ARGV.size() > 1
  trials = ARGV[1].to_i()
if steps < 1 || trials < 1
  << "usage: flipfleet_ternary_sign_isotropy_bench [steps-per-arm] [trials]"
  exit(2)

asset_root = "benchmarks/matmul/metaflip/"
z = fftsib_run("4x4",asset_root+"matmul_4x4_rank49_dronperminov_ternary.txt",4,steps,trials) ## i64
if z > 0
  z = fftsib_run("5x5",asset_root+"matmul_5x5_rank93_d967_index_shear_gpu_ternary.txt",5,steps,trials)
if z > 0
  z = fftsib_run("6x6",asset_root+"matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt",6,steps,trials)
if z < 1
  << "FAIL ternary diagonal sign-isotropy matched benchmark"
  exit(1)
<< "PASS ternary diagonal sign-isotropy matched benchmark"
