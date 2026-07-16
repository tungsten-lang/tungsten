# Matched continuation for the exact beyond-span-4 doors emitted by
# macro_goal_beam_bench.w. Kept in a separate process so the large beam arena
# cannot affect ordinary-worker measurements.

use ../lib/metaflip/rect

-> ffmgbc_square(source_path, door_path, trials, moves) (String String i64 i64) i64
  n = 5 ## i64
  start_rank = 93 ## i64
  capacity = ffw_default_capacity(n) ## i64
  control_wins = 0 ## i64
  door_wins = 0 ## i64
  ties = 0 ## i64
  control_drops = 0 ## i64
  door_drops = 0 ## i64
  control_best_rank = 1 << 30 ## i64
  door_best_rank = 1 << 30 ## i64
  control_best_density = 1 << 30 ## i64
  door_best_density = 1 << 30 ## i64
  control_sum = 0 ## i64
  door_sum = 0 ## i64
  start_ms = ccall("__w_clock_ms") ## i64
  trial = 0 ## i64
  while trial < trials
    seed = 99101 + trial*1009 ## i64
    control = i64[ffw_state_size(capacity)]
    door = i64[ffw_state_size(capacity)]
    control_start = ffw_load_scheme_cap(control,source_path,n,capacity,seed,4,4,moves / 10,moves / 25) ## i64
    door_start = ffw_load_scheme_cap(door,door_path,n,capacity,seed,4,4,moves / 10,moves / 25) ## i64
    control_exact = ffw_verify_best_exact(control,n) ## i64
    door_exact = ffw_verify_best_exact(door,n) ## i64
    if control_start != start_rank || door_start != start_rank || control_exact != 1 || door_exact != 1
      << "MACRO_GOAL_BEAM_CONTINUE tensor=5x5-d967 error=load"
      return 0
    z = ffw_walk(control,moves) ## i64
    z = ffw_walk(door,moves)
    control_rank = ffw_best_rank(control) ## i64
    door_rank = ffw_best_rank(door) ## i64
    control_density = ffw_best_bits(control) ## i64
    door_density = ffw_best_bits(door) ## i64
    if control_rank < start_rank
      control_drops += 1
    if door_rank < start_rank
      door_drops += 1
    if control_rank < control_best_rank || (control_rank == control_best_rank && control_density < control_best_density)
      control_best_rank = control_rank
      control_best_density = control_density
    if door_rank < door_best_rank || (door_rank == door_best_rank && door_density < door_best_density)
      door_best_rank = door_rank
      door_best_density = door_density
    control_sum += control_density
    door_sum += door_density
    if control_rank < door_rank || (control_rank == door_rank && control_density < door_density)
      control_wins += 1
    if door_rank < control_rank || (door_rank == control_rank && door_density < control_density)
      door_wins += 1
    if control_rank == door_rank && control_density == door_density
      ties += 1
    trial += 1
  elapsed_ms = ccall("__w_clock_ms") - start_ms ## i64
  << "MACRO_GOAL_BEAM_CONTINUE tensor=5x5-d967 trials="+trials.to_s()+" moves_per_arm="+moves.to_s()+" control_wins="+control_wins.to_s()+" door_wins="+door_wins.to_s()+" ties="+ties.to_s()+" control_drops="+control_drops.to_s()+" door_drops="+door_drops.to_s()+" control_best="+control_best_rank.to_s()+"/"+control_best_density.to_s()+" door_best="+door_best_rank.to_s()+"/"+door_best_density.to_s()+" control_mean_density="+(control_sum / trials).to_s()+" door_mean_density="+(door_sum / trials).to_s()+" ms="+elapsed_ms.to_s()
  1

-> ffmgbc_rect(source_path, door_path, trials, moves) (String String i64 i64) i64
  n = 4 ## i64
  m = 4 ## i64
  p = 5 ## i64
  start_rank = 60 ## i64
  capacity = ffr_default_capacity(n,m,p) ## i64
  control_wins = 0 ## i64
  door_wins = 0 ## i64
  ties = 0 ## i64
  control_drops = 0 ## i64
  door_drops = 0 ## i64
  control_best_rank = 1 << 30 ## i64
  door_best_rank = 1 << 30 ## i64
  control_best_density = 1 << 30 ## i64
  door_best_density = 1 << 30 ## i64
  control_sum = 0 ## i64
  door_sum = 0 ## i64
  start_ms = ccall("__w_clock_ms") ## i64
  trial = 0 ## i64
  while trial < trials
    seed = 99301 + trial*1009 ## i64
    control = i64[ffr_state_size(capacity)]
    door = i64[ffr_state_size(capacity)]
    control_start = ffr_load_scheme_cap(control,source_path,n,m,p,capacity,seed,4,4,moves / 10,moves / 25) ## i64
    door_start = ffr_load_scheme_cap(door,door_path,n,m,p,capacity,seed,4,4,moves / 10,moves / 25) ## i64
    if control_start != start_rank || door_start != start_rank || ffr_verify_best_exact(control,n,m,p) != 1 || ffr_verify_best_exact(door,n,m,p) != 1
      << "MACRO_GOAL_BEAM_CONTINUE tensor=4x4x5 error=load"
      return 0
    z = ffr_walk(control,moves) ## i64
    z = ffr_walk(door,moves)
    control_rank = ffr_best_rank(control) ## i64
    door_rank = ffr_best_rank(door) ## i64
    control_density = ffr_best_bits(control) ## i64
    door_density = ffr_best_bits(door) ## i64
    if control_rank < start_rank
      control_drops += 1
    if door_rank < start_rank
      door_drops += 1
    if control_rank < control_best_rank || (control_rank == control_best_rank && control_density < control_best_density)
      control_best_rank = control_rank
      control_best_density = control_density
    if door_rank < door_best_rank || (door_rank == door_best_rank && door_density < door_best_density)
      door_best_rank = door_rank
      door_best_density = door_density
    control_sum += control_density
    door_sum += door_density
    if control_rank < door_rank || (control_rank == door_rank && control_density < door_density)
      control_wins += 1
    if door_rank < control_rank || (door_rank == control_rank && door_density < control_density)
      door_wins += 1
    if control_rank == door_rank && control_density == door_density
      ties += 1
    trial += 1
  elapsed_ms = ccall("__w_clock_ms") - start_ms ## i64
  << "MACRO_GOAL_BEAM_CONTINUE tensor=4x4x5 trials="+trials.to_s()+" moves_per_arm="+moves.to_s()+" control_wins="+control_wins.to_s()+" door_wins="+door_wins.to_s()+" ties="+ties.to_s()+" control_drops="+control_drops.to_s()+" door_drops="+door_drops.to_s()+" control_best="+control_best_rank.to_s()+"/"+control_best_density.to_s()+" door_best="+door_best_rank.to_s()+"/"+door_best_density.to_s()+" control_mean_density="+(control_sum / trials).to_s()+" door_mean_density="+(door_sum / trials).to_s()+" ms="+elapsed_ms.to_s()
  1

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
z = ffmgbc_square(root+"matmul_5x5_rank93_d967_four_split_control_gf2.txt","/tmp/metaflip_macro_goal_beam_5x5-d967_best.txt",8,2000000) ## i64
z = ffmgbc_rect(root+"matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt","/tmp/metaflip_macro_goal_beam_4x4x5_best.txt",8,2000000)
