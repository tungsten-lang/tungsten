use ../lib/metaflip/strategies/macro_commutator
use ../lib/metaflip/strategies/macro_holonomy

-> ffcct_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL macro commutator: " + label
    exit(1)
  1

# Find a concrete target-directed conjugate/commutator on the same small
# exact fixture used by the first-generation holonomy test.
source_u = i64[3]
source_v = i64[3]
source_w = i64[3]
source_u[0] = 1
source_u[1] = 6
source_u[2] = 1
source_v[0] = 2
source_v[1] = 2
source_v[2] = 7
source_w[0] = 2
source_w[1] = 5
source_w[2] = 2

found = 0 ## i64
winning_u = i64[3]
winning_v = i64[3]
winning_w = i64[3]
winning_recipe = i64[14]
winning_stats = i64[12]
focus = 0 ## i64
while focus < 3 && found == 0
  axis = 0 ## i64
  while axis < 3 && found == 0
    target_term = 0 ## i64
    while target_term < 3 && found == 0
      target = ffmh_axis_get(source_u,source_v,source_w,target_term,axis) ## i64
      if target != ffmh_axis_get(source_u,source_v,source_w,focus,axis)
        trial_u = i64[3]
        trial_v = i64[3]
        trial_w = i64[3]
        recipe = i64[14]
        stats = i64[12]
        rank = ffcc_search_target(source_u,source_v,source_w,3,focus,axis,target,20000,trial_u,trial_v,trial_w,recipe,stats) ## i64
        if rank > 0
          found = rank
          z = ffmh_copy(trial_u,trial_v,trial_w,rank,winning_u,winning_v,winning_w) ## i64
          i = 0 ## i64
          while i < 14
            winning_recipe[i] = recipe[i]
            i += 1
          i = 0
          while i < 12
            winning_stats[i] = stats[i]
            i += 1
      target_term += 1
    axis += 1
  focus += 1

z = ffcct_expect("finds target-directed endpoint",found == 3 && winning_stats[11] == 1) ## i64
z = ffcct_expect("rank debt stays zero",winning_recipe[6] == 3)
z = ffcct_expect("changed and locally exact",winning_recipe[7] > 0 && ffmh_local_exact(source_u,source_v,source_w,3,winning_u,winning_v,winning_w,3) == 1)
z = ffcct_expect("chosen structural change made",ffcc_target_hit(winning_u,winning_v,winning_w,winning_recipe[3],winning_recipe[4],winning_recipe[5]) == 1)

# Audit all prefixes: setup, trigger, unsetup, and optional trigger inverse are
# exact, remain rank three, and replay byte-for-byte as a term set.
trace_u = i64[3]
trace_v = i64[3]
trace_w = i64[3]
z = ffmh_copy(source_u,source_v,source_w,3,trace_u,trace_v,trace_w)
z = ffcct_expect("setup legal",fftc_apply_code(trace_u,trace_v,trace_w,3,winning_recipe[1],0-1) == 1)
z = ffcct_expect("setup exact",ffmh_local_exact(source_u,source_v,source_w,3,trace_u,trace_v,trace_w,3) == 1)
z = ffcct_expect("trigger legal",fftc_apply_code(trace_u,trace_v,trace_w,3,winning_recipe[2],0-1) == 1)
z = ffcct_expect("trigger exact",ffmh_local_exact(source_u,source_v,source_w,3,trace_u,trace_v,trace_w,3) == 1)
z = ffcct_expect("unsetup legal",fftc_apply_code(trace_u,trace_v,trace_w,3,winning_recipe[1],0-1) == 1)
z = ffcct_expect("unsetup exact",ffmh_local_exact(source_u,source_v,source_w,3,trace_u,trace_v,trace_w,3) == 1)
if winning_recipe[0] == 4
  z = ffcct_expect("commutator close legal",fftc_apply_code(trace_u,trace_v,trace_w,3,winning_recipe[2],0-1) == 1)
  z = ffcct_expect("commutator close exact",ffmh_local_exact(source_u,source_v,source_w,3,trace_u,trace_v,trace_w,3) == 1)

replay_u = i64[3]
replay_v = i64[3]
replay_w = i64[3]
replay_meta = i64[6]
replayed = ffcc_replay(source_u,source_v,source_w,3,winning_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
z = ffcct_expect("deterministic replay",replayed == 3 && replay_meta[0] == 1 && replay_meta[1] == 1 && replay_meta[2] == 1)
z = ffcct_expect("replay endpoint",fftc_terms_same_set(winning_u,winning_v,winning_w,3,replay_u,replay_v,replay_w,3) == 1)

bad_recipe = i64[14]
i = 0 ## i64
while i < 14
  bad_recipe[i] = winning_recipe[i]
  i += 1
bad_recipe[5] = 0
z = ffcct_expect("bad target rejected",ffcc_replay(source_u,source_v,source_w,3,bad_recipe,replay_u,replay_v,replay_w,replay_meta) == 0)

<< "macro_commutator_test: length=" + winning_recipe[0].to_s() + " distance=" + winning_recipe[7].to_s() + " density_delta=" + winning_recipe[8].to_s() + " pressure_delta=" + winning_recipe[9].to_s() + " exact_hits=" + winning_stats[7].to_s()
