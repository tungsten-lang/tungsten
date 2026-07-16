use ../lib/metaflip/strategies/macro_holonomy

-> ffmht_expect(label, condition)
  if !condition
    << "FAIL macro holonomy: " + label
    exit(1)
  1

# This three-term fixture also exercises the older labelled-catalyst plant,
# but the move below begins with one nonzero split identity rather than an
# inserted canceling pair.
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
winning_u = i64[4]
winning_v = i64[4]
winning_w = i64[4]
winning_recipe = i64[13]
winning_stats = i64[12]
split_source = 0 ## i64
while split_source < 3 && found == 0
  split_axis = 0 ## i64
  while split_axis < 3 && found == 0
    part = 1 ## i64
    while part < 8 && found == 0
      trial_u = i64[4]
      trial_v = i64[4]
      trial_w = i64[4]
      recipe = i64[13]
      stats = i64[12]
      rank = ffmh_search(source_u,source_v,source_w,3,split_source,split_axis,part,3,20000,trial_u,trial_v,trial_w,recipe,stats) ## i64
      if rank > 0
        found = rank
        z = ffmh_copy(trial_u,trial_v,trial_w,rank,winning_u,winning_v,winning_w) ## i64
        i = 0 ## i64
        while i < 13
          winning_recipe[i] = recipe[i]
          i += 1
        i = 0
        while i < 12
          winning_stats[i] = stats[i]
          i += 1
      part += 1
    split_axis += 1
  split_source += 1

z = ffmht_expect("finds changed exact endpoint",found > 0 && winning_stats[10] == 1 && winning_stats[6] > 0) ## i64
z = ffmht_expect("bounded rank",found <= 3)
z = ffmht_expect("local exactness",fftc_local_exact(source_u,source_v,source_w,3,winning_u,winning_v,winning_w,found) == 1)

# The packed support-major local gate must reject a real coefficient change,
# not merely accept the exact replay path.
broken_u = i64[4]
broken_v = i64[4]
broken_w = i64[4]
z = ffmh_copy(winning_u,winning_v,winning_w,found,broken_u,broken_v,broken_w)
broken_u[0] = broken_u[0] ^ 1
if broken_u[0] == 0
  broken_u[0] = winning_u[0] ^ 2
z = ffmht_expect("local corruption rejected",ffmh_local_exact(source_u,source_v,source_w,3,broken_u,broken_v,broken_w,found) == 0)

direct_pair = 0 ## i64
if winning_recipe[8] == winning_recipe[0] && winning_recipe[9] == 3
  direct_pair = 1
if winning_recipe[9] == winning_recipe[0] && winning_recipe[8] == 3
  direct_pair = 1
z = ffmht_expect("different closing merge",direct_pair == 0 || winning_recipe[10] != winning_recipe[1])

# Audit every labelled intermediate, not just the final splice.  Split and
# each ordered flip must preserve exactly the original local tensor while the
# rank-R+1 shoulder is hidden from objective admission.
trace_u = i64[4]
trace_v = i64[4]
trace_w = i64[4]
z = ffmh_copy(source_u,source_v,source_w,3,trace_u,trace_v,trace_w)
trace_rank = ffmh_split_labeled(trace_u,trace_v,trace_w,3,4,winning_recipe[0],winning_recipe[1],winning_recipe[2]) ## i64
z = ffmht_expect("setup exact",trace_rank == 4 && ffmh_local_exact(source_u,source_v,source_w,3,trace_u,trace_v,trace_w,trace_rank) == 1)
step = 0 ## i64
while step < winning_recipe[3]
  z = ffmht_expect("braid edge legal "+step.to_s(),fftc_apply_code(trace_u,trace_v,trace_w,trace_rank,winning_recipe[4+step],0-1) == 1)
  z = ffmht_expect("braid prefix exact "+step.to_s(),ffmh_local_exact(source_u,source_v,source_w,3,trace_u,trace_v,trace_w,trace_rank) == 1)
  step += 1

replay_u = i64[4]
replay_v = i64[4]
replay_w = i64[4]
replay_meta = i64[5]
replayed = ffmh_replay(source_u,source_v,source_w,3,winning_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
z = ffmht_expect("deterministic replay",replayed == found && replay_meta[0] == 1 && replay_meta[1] == 1)
z = ffmht_expect("replay term set",fftc_terms_same_set(winning_u,winning_v,winning_w,found,replay_u,replay_v,replay_w,replayed) == 1)

# Goal selection changes only which exact endpoint survives enumeration.  It
# must not change the legal braid set or weaken deterministic replay.
ordering_stats = i64[12]
z = ffmh_clear(ordering_stats,12)
ordering_stats[5] = 3
ordering_stats[6] = 10
ordering_stats[7] = 2
ordering_stats[9] = 1
z = ffmht_expect("legacy remains distance first",ffmh_candidate_better_mode(3,8,1,5,0,ordering_stats) == 0)
z = ffmht_expect("density goal overrides distance",ffmh_candidate_better_mode(3,8,1,5,1,ordering_stats) == 1)
z = ffmht_expect("pressure goal overrides density",ffmh_candidate_better_mode(3,8,3,2,2,ordering_stats) == 1)
z = ffmht_expect("density goal rejects pressure-only win",ffmh_candidate_better_mode(3,8,3,2,1,ordering_stats) == 0)
z = ffmht_expect("density goal requires real change",ffmh_goal_satisfied(3,3,0,4,1) == 0 && ffmh_goal_satisfied(3,3,-1,0,1) == 1)
z = ffmht_expect("pressure goal requires real change",ffmh_goal_satisfied(3,3,-4,0,2) == 0 && ffmh_goal_satisfied(3,3,0,1,2) == 1)
z = ffmht_expect("rank drop satisfies every goal",ffmh_goal_satisfied(2,3,5,-5,1) == 1 && ffmh_goal_satisfied(2,3,5,-5,2) == 1)

mode = 1 ## i64
while mode <= 2
  goal_u = i64[4]
  goal_v = i64[4]
  goal_w = i64[4]
  goal_recipe = i64[13]
  goal_stats = i64[12]
  goal_rank = ffmh_search_mode(source_u,source_v,source_w,3,winning_recipe[0],winning_recipe[1],winning_recipe[2],3,20000,mode,goal_u,goal_v,goal_w,goal_recipe,goal_stats) ## i64
  z = ffmht_expect("goal mode exact "+mode.to_s(),goal_rank > 0 && goal_stats[10] == 1 && ffmh_local_exact(source_u,source_v,source_w,3,goal_u,goal_v,goal_w,goal_rank) == 1)
  goal_replay_u = i64[4]
  goal_replay_v = i64[4]
  goal_replay_w = i64[4]
  goal_replay_meta = i64[5]
  goal_replayed = ffmh_replay(source_u,source_v,source_w,3,goal_recipe,goal_replay_u,goal_replay_v,goal_replay_w,goal_replay_meta) ## i64
  z = ffmht_expect("goal mode replay "+mode.to_s(),goal_replayed == goal_rank && goal_replay_meta[0] == 1)
  mode += 1
z = ffmht_expect("invalid goal mode rejected",ffmh_search_mode(source_u,source_v,source_w,3,winning_recipe[0],winning_recipe[1],winning_recipe[2],3,20000,3,replay_u,replay_v,replay_w,winning_recipe,winning_stats) == 0)

# The direct inverse setup is exact but is not admitted as holonomy because it
# returns to the source term set without a connected changed endpoint.
split_u = i64[4]
split_v = i64[4]
split_w = i64[4]
z = ffmh_copy(source_u,source_v,source_w,3,split_u,split_v,split_w) ## i64
split_rank = ffmh_split_labeled(split_u,split_v,split_w,3,4,0,0,2) ## i64
merge_rank = ffmh_merge_labeled(split_u,split_v,split_w,split_rank,0,3,0) ## i64
compact_u = i64[4]
compact_v = i64[4]
compact_w = i64[4]
compact_rank = ffmh_compact(split_u,split_v,split_w,merge_rank,compact_u,compact_v,compact_w) ## i64
z = ffmht_expect("setup inverse exact no-op",compact_rank == 3 && fftc_terms_same_set(source_u,source_v,source_w,3,compact_u,compact_v,compact_w,compact_rank) == 1)

bad_recipe = i64[13]
i = 0 ## i64
while i < 13
  bad_recipe[i] = winning_recipe[i]
  i += 1
bad_recipe[2] = 0
bad_meta = i64[5]
z = ffmht_expect("malformed setup rejected",ffmh_replay(source_u,source_v,source_w,3,bad_recipe,replay_u,replay_v,replay_w,bad_meta) == 0)

<< "macro_holonomy_test: exact split-braid-merge rank=" + found.to_s() + " distance=" + winning_stats[6].to_s() + " depth=" + winning_stats[8].to_s() + " legal_edges=" + winning_stats[1].to_s() + " closures=" + winning_stats[2].to_s()
