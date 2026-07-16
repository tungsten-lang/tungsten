use ../lib/metaflip/strategies/macro_goal_beam

-> ffmgbt_expect(label, condition)
  if !condition
    << "FAIL macro goal beam: " + label
    exit(1)
  1

# Reuse the small exact fixture that established split-braid-merge holonomy,
# then ask the deeper beam for that explicitly labelled alternate close.
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
dfs_recipe = i64[13]
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
        i = 0 ## i64
        while i < 13
          dfs_recipe[i] = recipe[i]
          i += 1
      part += 1
    split_axis += 1
  split_source += 1
z = ffmgbt_expect("fixture exposes alternate merge",found > 0)

direct_pair = 0 ## i64
if dfs_recipe[10] == dfs_recipe[1]
  if (dfs_recipe[8] == dfs_recipe[0] && dfs_recipe[9] == 3) || (dfs_recipe[9] == dfs_recipe[0] && dfs_recipe[8] == 3)
    direct_pair = 1
z = ffmgbt_expect("target is not setup inverse",direct_pair == 0)

out_u = i64[4]
out_v = i64[4]
out_w = i64[4]
beam_recipe = i64[20]
beam_stats = i64[16]
beam_rank = ffmgb_search(source_u,source_v,source_w,3,dfs_recipe[0],dfs_recipe[1],dfs_recipe[2],dfs_recipe[8],dfs_recipe[9],dfs_recipe[10],3,7,256,out_u,out_v,out_w,beam_recipe,beam_stats) ## i64
z = ffmgbt_expect("goal beam finds exact close",beam_rank > 0 && beam_stats[12] == 1 && beam_stats[6] > 0)
z = ffmgbt_expect("endpoint exact",ffmh_local_exact(source_u,source_v,source_w,3,out_u,out_v,out_w,beam_rank) == 1)
z = ffmgbt_expect("canonical dedup active",beam_stats[2] > 0 && beam_stats[13] > 1)
z = ffmgbt_expect("specified merge replayed",beam_recipe[14] == dfs_recipe[8] && beam_recipe[15] == dfs_recipe[9] && beam_recipe[16] == dfs_recipe[10])

deep_u = i64[4]
deep_v = i64[4]
deep_w = i64[4]
deep_recipe = i64[20]
deep_stats = i64[16]
deep_rank = ffmgb_search(source_u,source_v,source_w,3,dfs_recipe[0],dfs_recipe[1],dfs_recipe[2],dfs_recipe[8],dfs_recipe[9],dfs_recipe[10],5,7,256,deep_u,deep_v,deep_w,deep_recipe,deep_stats) ## i64
z = ffmgbt_expect("depth-five shoulder path closes",deep_rank > 0 && deep_recipe[3] >= 5 && deep_stats[12] == 1)
z = ffmgbt_expect("depth-five endpoint exact",ffmh_local_exact(source_u,source_v,source_w,3,deep_u,deep_v,deep_w,deep_rank) == 1)

replay_u = i64[4]
replay_v = i64[4]
replay_w = i64[4]
replay_meta = i64[4]
replayed = ffmgb_replay(source_u,source_v,source_w,3,beam_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
z = ffmgbt_expect("deterministic replay full-gates",replayed == beam_rank && replay_meta[0] == 1 && replay_meta[1] == 1)
z = ffmgbt_expect("replay term set",fftc_terms_same_set(out_u,out_v,out_w,beam_rank,replay_u,replay_v,replay_w,replayed) == 1)

# Run the same search twice. Hash-table insertion and beam tie breaks must not
# depend on allocation addresses or arrival instability.
second_u = i64[4]
second_v = i64[4]
second_w = i64[4]
second_recipe = i64[20]
second_stats = i64[16]
second_rank = ffmgb_search(source_u,source_v,source_w,3,dfs_recipe[0],dfs_recipe[1],dfs_recipe[2],dfs_recipe[8],dfs_recipe[9],dfs_recipe[10],3,7,256,second_u,second_v,second_w,second_recipe,second_stats) ## i64
z = ffmgbt_expect("repeat returns same endpoint",second_rank == beam_rank && fftc_terms_same_set(out_u,out_v,out_w,beam_rank,second_u,second_v,second_w,second_rank) == 1)
i = 0
while i < 20
  z = ffmgbt_expect("repeat recipe word "+i.to_s(),second_recipe[i] == beam_recipe[i])
  i += 1

# The literal split inverse is deliberately outside this move family.
bad_u = i64[4]
bad_v = i64[4]
bad_w = i64[4]
bad_recipe = i64[20]
bad_stats = i64[16]
bad = ffmgb_search(source_u,source_v,source_w,3,0,0,2,0,3,0,1,5,32,bad_u,bad_v,bad_w,bad_recipe,bad_stats) ## i64
z = ffmgbt_expect("direct setup merge rejected",bad == 0)

<< "macro_goal_beam_test: exact rank="+beam_rank.to_s()+" depth="+beam_recipe[3].to_s()+" distance="+beam_recipe[18].to_s()+" visited="+beam_stats[13].to_s()+" revisits="+beam_stats[2].to_s()
