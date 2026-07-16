use ../lib/metaflip/strategies/macro_core_rewrite

-> ffmcrt_expect(label, condition)
  if !condition
    << "FAIL macro core rewrite: " + label
    exit(1)
  1

# Small exact holonomy fixture.  The test does not prescribe a final partner:
# it asks the state-dependent constraint search to absorb one chosen label.
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
found_target = 0 ## i64
found_split = 0 ## i64
found_axis = 0 ## i64
found_part = 0 ## i64
saved_recipe = i64[20]
saved_stats = i64[16]
saved_u = i64[4]
saved_v = i64[4]
saved_w = i64[4]
target = 0 ## i64
while target < 3 && found == 0
  split_source = 0 ## i64
  while split_source < 3 && found == 0
    split_axis = 0 ## i64
    while split_axis < 3 && found == 0
      part = 1 ## i64
      while part < 8 && found == 0
        out_u = i64[4]
        out_v = i64[4]
        out_w = i64[4]
        recipe = i64[20]
        stats = i64[16]
        rank = ffmcr_search(source_u,source_v,source_w,3,target,split_source,split_axis,part,3,7,256,0,out_u,out_v,out_w,recipe,stats) ## i64
        if rank > 0
          found = rank
          found_target = target
          found_split = split_source
          found_axis = split_axis
          found_part = part
          z = ffmh_copy(out_u,out_v,out_w,rank,saved_u,saved_v,saved_w) ## i64
          i = 0 ## i64
          while i < 20
            saved_recipe[i] = recipe[i]
            i += 1
          i = 0
          while i < 16
            saved_stats[i] = stats[i]
            i += 1
        part += 1
      split_axis += 1
    split_source += 1
  target += 1

z = ffmcrt_expect("constraint search finds close",found > 0 && saved_stats[12] == 1)
z = ffmcrt_expect("endpoint exact",ffmh_local_exact(source_u,source_v,source_w,3,saved_u,saved_v,saved_w,found) == 1)
z = ffmcrt_expect("chosen term absent",ffmcr_contains_term(saved_u,saved_v,saved_w,0,found,source_u[found_target],source_v[found_target],source_w[found_target]) == 0)
z = ffmcrt_expect("close absorbs target label",saved_recipe[14] == found_target)
z = ffmcrt_expect("canonical dedup active",saved_stats[2] > 0 && saved_stats[13] > 1)

replay_u = i64[4]
replay_v = i64[4]
replay_w = i64[4]
replay_meta = i64[4]
replayed = ffmcr_replay(source_u,source_v,source_w,3,found_target,saved_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
z = ffmcrt_expect("replay exact and target-free",replayed == found && replay_meta[0] == 1)
z = ffmcrt_expect("replay term set",fftc_terms_same_set(saved_u,saved_v,saved_w,found,replay_u,replay_v,replay_w,replayed) == 1)

repeat_u = i64[4]
repeat_v = i64[4]
repeat_w = i64[4]
repeat_recipe = i64[20]
repeat_stats = i64[16]
repeat_rank = ffmcr_search(source_u,source_v,source_w,3,found_target,found_split,found_axis,found_part,3,7,256,0,repeat_u,repeat_v,repeat_w,repeat_recipe,repeat_stats) ## i64
z = ffmcrt_expect("deterministic endpoint",repeat_rank == found && fftc_terms_same_set(saved_u,saved_v,saved_w,found,repeat_u,repeat_v,repeat_w,repeat_rank) == 1)
i = 0
while i < 20
  z = ffmcrt_expect("deterministic recipe "+i.to_s(),repeat_recipe[i] == saved_recipe[i])
  i += 1

<< "macro_core_rewrite_test: target="+found_target.to_s()+" rank="+found.to_s()+" depth="+saved_recipe[3].to_s()+" distance="+saved_recipe[18].to_s()+" visited="+saved_stats[13].to_s()+" revisits="+saved_stats[2].to_s()
