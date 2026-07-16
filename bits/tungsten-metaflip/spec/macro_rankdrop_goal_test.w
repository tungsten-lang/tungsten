use ../lib/metaflip/strategies/macro_goal_beam

-> ffmrg_expect(label, condition)
  if !condition
    << "FAIL macro rank-drop goal: " + label
    exit(1)
  1

# Reuse the smallest known split-braid-annihilate fixture.  First obtain its
# exact duplicate close with exhaustive depth-three holonomy; then require the
# endpoint-directed beam to manufacture that same all-factor equality.
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

plant_rank = 0 ## i64
plant_recipe = i64[13]
split_source = 0 ## i64
while split_source < 3 && plant_rank == 0
  split_axis = 0 ## i64
  while split_axis < 3 && plant_rank == 0
    part = 1 ## i64
    while part < 8 && plant_rank == 0
      trial_u = i64[4]
      trial_v = i64[4]
      trial_w = i64[4]
      recipe = i64[13]
      stats = i64[12]
      rank = ffmh_search(source_u,source_v,source_w,3,split_source,split_axis,part,3,20000,trial_u,trial_v,trial_w,recipe,stats) ## i64
      if rank == 2
        plant_rank = rank
        i = 0 ## i64
        while i < 13
          plant_recipe[i] = recipe[i]
          i += 1
      part += 1
    split_axis += 1
  split_source += 1
z = ffmrg_expect("rank-minus-one plant exists", plant_rank == 2)

out_u = i64[4]
out_v = i64[4]
out_w = i64[4]
beam_recipe = i64[20]
beam_stats = i64[16]
beam_rank = ffmgb_search_annihilation(source_u,source_v,source_w,3,plant_recipe[0],plant_recipe[1],plant_recipe[2],plant_recipe[8],plant_recipe[9],1,7,256,out_u,out_v,out_w,beam_recipe,beam_stats) ## i64
z = ffmrg_expect("annihilation beam returns rank minus one", beam_rank == 2)
z = ffmrg_expect("three-equality endpoint reached", beam_stats[14] == 3 && beam_stats[4] > 0)
z = ffmrg_expect("endpoint independently exact", ffmh_local_exact(source_u,source_v,source_w,3,out_u,out_v,out_w,beam_rank) == 1)
z = ffmrg_expect("replay independently exact", beam_stats[12] == 1)

# Audit the Rubik word at the pre-close shoulder.  The requested labels must be
# literally identical, not merely mergeable on two axes.
trace_u = i64[4]
trace_v = i64[4]
trace_w = i64[4]
z = ffmh_copy(source_u,source_v,source_w,3,trace_u,trace_v,trace_w)
trace_rank = ffmh_split_labeled(trace_u,trace_v,trace_w,3,4,beam_recipe[0],beam_recipe[1],beam_recipe[2]) ## i64
step = 0 ## i64
while step < beam_recipe[3]
  z = ffmrg_expect("legal exact prefix " + step.to_s(), fftc_apply_code(trace_u,trace_v,trace_w,trace_rank,beam_recipe[4+step],0-1) == 1 && ffmh_local_exact(source_u,source_v,source_w,3,trace_u,trace_v,trace_w,trace_rank) == 1)
  step += 1
first = beam_recipe[14] ## i64
second = beam_recipe[15] ## i64
z = ffmrg_expect("pre-close pair is duplicate", fftc_same_term(trace_u[first],trace_v[first],trace_w[first],trace_u[second],trace_v[second],trace_w[second]) == 1)
z = ffmrg_expect("duplicate close uses concrete replay axis", beam_recipe[16] == 0)

repeat_u = i64[4]
repeat_v = i64[4]
repeat_w = i64[4]
repeat_recipe = i64[20]
repeat_stats = i64[16]
repeat_rank = ffmgb_search_annihilation(source_u,source_v,source_w,3,plant_recipe[0],plant_recipe[1],plant_recipe[2],plant_recipe[8],plant_recipe[9],1,7,256,repeat_u,repeat_v,repeat_w,repeat_recipe,repeat_stats) ## i64
z = ffmrg_expect("deterministic endpoint", repeat_rank == beam_rank && fftc_terms_same_set(out_u,out_v,out_w,beam_rank,repeat_u,repeat_v,repeat_w,repeat_rank) == 1)
i = 0
while i < 20
  z = ffmrg_expect("deterministic recipe " + i.to_s(), repeat_recipe[i] == beam_recipe[i])
  i += 1

<< "PASS macro rank-drop goal rank=3->" + beam_rank.to_s() + " depth=" + beam_recipe[3].to_s() + " visited=" + beam_stats[13].to_s() + " revisits=" + beam_stats[2].to_s()
