use ../lib/metaflip/strategies/rect_endpoint_rankdown2
use ../lib/metaflip/rect

-> fferd2t_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL rectangular endpoint rank-down-2: " + label
    exit(1)
  1

-> fferd2t_full_control(label, full_u, full_v, full_w, full_rank, target_count, capacity, cleanup_order) (String i64[] i64[] i64[] i64 i64 i64 i64) i64
  source_count = target_count + 2 ## i64
  local_target_u = i64[target_count]
  local_target_v = i64[target_count]
  local_target_w = i64[target_count]
  z = ffrep_copy_slot(full_u,full_v,full_w,0,target_count,local_target_u,local_target_v,local_target_w,0) ## i64

  # Split two different target terms along U with the same part.  Their first
  # children then share U=1, so code zero is a deliberate ordinary flip that
  # moves the lifted endpoint one edge away.  The compiler must resolve that
  # state-dependent edge before either cleanup merge is legal.
  scaffold = i64[fferd2_recipe_size()]
  scaffold[29] = 0
  scaffold[30] = 0
  scaffold[31] = 1
  scaffold[32] = 1
  scaffold[33] = 0
  scaffold[34] = 1
  scaffold[35] = cleanup_order
  lift_u = i64[source_count]
  lift_v = i64[source_count]
  lift_w = i64[source_count]
  z = fferd2t_expect(label+" builds double lift",fferd2_build_lift(local_target_u,local_target_v,local_target_w,target_count,scaffold,lift_u,lift_v,lift_w) == source_count)
  local_source_u = i64[source_count]
  local_source_v = i64[source_count]
  local_source_w = i64[source_count]
  z = ffrep_copy_slot(lift_u,lift_v,lift_w,0,source_count,local_source_u,local_source_v,local_source_w,0)
  z = fferd2t_expect(label+" planted trigger legal",fftc_apply_code(local_source_u,local_source_v,local_source_w,source_count,0,0-1) == 1)
  z = fferd2t_expect(label+" planted trigger changes endpoint",fftc_terms_same_set(local_source_u,local_source_v,local_source_w,source_count,lift_u,lift_v,lift_w,source_count) == 0)
  z = fferd2t_expect(label+" planted local relation exact",ffrep_local_exact_shape(local_source_u,local_source_v,local_source_w,source_count,local_target_u,local_target_v,local_target_w,target_count,10,30,12) == 1)

  recipe = i64[fferd2_recipe_size()]
  stats = i64[fferd2_stats_size()]
  macro_length = fferd2_search(local_source_u,local_source_v,local_source_w,source_count,local_target_u,local_target_v,local_target_w,target_count,10,30,12,0,0,1,1,0,1,cleanup_order,2,4096,recipe,stats) ## i64
  z = fferd2t_expect(label+" compiles trigger plus two merges",macro_length == 3 && recipe[4] == 1 && stats[17] == 1 && stats[18] == 1 && stats[19] == 1 && stats[20] == 1 && stats[21] == 1 && stats[22] == 1 && stats[23] == 1)

  auto_recipe = i64[fferd2_recipe_size()]
  auto_stats = i64[fferd2_auto_stats_size()]
  auto_length = fferd2_search_auto(local_source_u,local_source_v,local_source_w,source_count,local_target_u,local_target_v,local_target_w,target_count,10,30,12,2,4096,128,auto_recipe,auto_stats) ## i64
  z = fferd2t_expect(label+" automatic double-cleanup scaffold",auto_length == 3 && auto_recipe[4] == 1 && auto_stats[19] == 1 && auto_stats[24] > 0 && auto_stats[25] > 0 && auto_stats[26] > 1 && auto_stats[29] > 0)
  if target_count == 5
    auto_repeat_recipe = i64[fferd2_recipe_size()]
    auto_repeat_stats = i64[fferd2_auto_stats_size()]
    auto_repeat_length = fferd2_search_auto(local_source_u,local_source_v,local_source_w,source_count,local_target_u,local_target_v,local_target_w,target_count,10,30,12,2,4096,128,auto_repeat_recipe,auto_repeat_stats) ## i64
    z = fferd2t_expect(label+" automatic scaffold deterministic length",auto_repeat_length == auto_length)
    j = 0 ## i64
    while j < fferd2_recipe_size()
      z = fferd2t_expect(label+" automatic scaffold deterministic recipe "+j.to_s(),auto_repeat_recipe[j] == auto_recipe[j])
      j += 1
    j = 0
    while j < fferd2_auto_stats_size()
      z = fferd2t_expect(label+" automatic scaffold deterministic stats "+j.to_s(),auto_repeat_stats[j] == auto_stats[j])
      j += 1
    capped_recipe = i64[fferd2_recipe_size()]
    capped_stats = i64[fferd2_auto_stats_size()]
    capped_length = fferd2_search_auto(local_source_u,local_source_v,local_source_w,source_count,local_target_u,local_target_v,local_target_w,target_count,10,30,12,2,4096,1,capped_recipe,capped_stats) ## i64
    z = fferd2t_expect(label+" automatic scaffold obeys cap",capped_stats[24] == 1 && capped_stats[31] == 1)

  replay_u = i64[target_count]
  replay_v = i64[target_count]
  replay_w = i64[target_count]
  forward_meta = i64[fferd2_meta_size()]
  replayed = fferd2_replay_forward(local_source_u,local_source_v,local_source_w,source_count,local_target_u,local_target_v,local_target_w,target_count,recipe,replay_u,replay_v,replay_w,forward_meta) ## i64
  z = fferd2t_expect(label+" verifies every forward prefix",replayed == target_count && forward_meta[0] == recipe[4] && forward_meta[1] == recipe[4] && forward_meta[8] == 1 && forward_meta[9] == 1 && forward_meta[10] == 1 && forward_meta[11] == 1 && forward_meta[12] == 1 && forward_meta[13] == 1)
  undo_u = i64[source_count]
  undo_v = i64[source_count]
  undo_w = i64[source_count]
  undo_meta = i64[fferd2_meta_size()]
  undone = fferd2_replay_undo(local_source_u,local_source_v,local_source_w,source_count,local_target_u,local_target_v,local_target_w,target_count,recipe,undo_u,undo_v,undo_w,undo_meta) ## i64
  z = fferd2t_expect(label+" verifies every reverse prefix",undone == source_count && undo_meta[0] == recipe[4] && undo_meta[1] == recipe[4] && undo_meta[8] == 1 && undo_meta[9] == 1 && undo_meta[10] == 1 && undo_meta[11] == 1 && undo_meta[12] == 1 && undo_meta[13] == 1 && fftc_terms_same_set(undo_u,undo_v,undo_w,source_count,local_source_u,local_source_v,local_source_w,source_count) == 1)
  auto_meta = i64[fferd2_meta_size()]
  z = fferd2t_expect(label+" automatic recipe replays",fferd2_replay_forward(local_source_u,local_source_v,local_source_w,source_count,local_target_u,local_target_v,local_target_w,target_count,auto_recipe,replay_u,replay_v,replay_w,auto_meta) == target_count && auto_meta[13] == 1)

  # Graft the local relation into the complete packaged rank-47 scheme.  Both
  # sides are independently initialized and exhaustively verified, proving a
  # full rank-49 -> rank-47 2x5x6 certificate control.
  full_source_u = i64[capacity]
  full_source_v = i64[capacity]
  full_source_w = i64[capacity]
  full_source_count = 0 ## i64
  i = target_count ## i64
  while i < full_rank
    full_source_u[full_source_count] = full_u[i]
    full_source_v[full_source_count] = full_v[i]
    full_source_w[full_source_count] = full_w[i]
    full_source_count += 1
    i += 1
  z = ffrep_copy_slot(local_source_u,local_source_v,local_source_w,0,source_count,full_source_u,full_source_v,full_source_w,full_source_count)
  full_source_count += source_count
  source_state = i64[ffr_state_size(capacity)]
  source_loaded = ffr_init_terms_cap(source_state,full_source_u,full_source_v,full_source_w,full_source_count,2,5,6,capacity,99501+target_count,0,1,1,1) ## i64
  z = fferd2t_expect(label+" full rank-49 source exact",full_source_count == full_rank + 2 && source_loaded == full_rank + 2 && ffr_verify_best_exact(source_state,2,5,6) == 1)

  full_replay_u = i64[capacity]
  full_replay_v = i64[capacity]
  full_replay_w = i64[capacity]
  full_replay_count = 0 ## i64
  i = target_count
  while i < full_rank
    full_replay_u[full_replay_count] = full_u[i]
    full_replay_v[full_replay_count] = full_v[i]
    full_replay_w[full_replay_count] = full_w[i]
    full_replay_count += 1
    i += 1
  z = ffrep_copy_slot(replay_u,replay_v,replay_w,0,target_count,full_replay_u,full_replay_v,full_replay_w,full_replay_count)
  full_replay_count += target_count
  replay_state = i64[ffr_state_size(capacity)]
  replay_loaded = ffr_init_terms_cap(replay_state,full_replay_u,full_replay_v,full_replay_w,full_replay_count,2,5,6,capacity,99601+target_count,0,1,1,1) ## i64
  z = fferd2t_expect(label+" full rank-47 replay exact",full_replay_count == full_rank && replay_loaded == full_rank && ffr_verify_best_exact(replay_state,2,5,6) == 1)
  << "RECT_ENDPOINT_RANKDOWN2_FULL control="+label+" local="+source_count.to_s()+"to"+target_count.to_s()+" path="+recipe[4].to_s()+" auto="+auto_stats[24].to_s()+"/"+auto_stats[25].to_s()+" descriptors="+auto_stats[26].to_s()+" full="+source_loaded.to_s()+"to"+replay_loaded.to_s()
  macro_length

# Start with the real six-to-five local replacement used by the one-rank
# compiler, then split one unchanged target term.  The resulting 7 -> 5 word
# has a genuine state-dependent middle flip followed by two named merges.
source_u = i64[7]
source_v = i64[7]
source_w = i64[7]
target_u = i64[5]
target_v = i64[5]
target_w = i64[5]

source_u[0]=2
source_v[0]=128
source_w[0]=129
source_u[1]=2
source_v[1]=512
source_w[1]=516
source_u[2]=4
source_v[2]=2
source_w[2]=768
source_u[3]=4
source_v[3]=256
source_w[3]=768
source_u[4]=4
source_v[4]=256
source_w[4]=258
source_u[5]=8
source_v[5]=256
source_w[5]=258
source_u[6]=12
source_v[6]=2048
source_w[6]=2064

target_u[0]=2
target_v[0]=512
target_w[0]=645
target_u[1]=2
target_v[1]=640
target_w[1]=129
target_u[2]=4
target_v[2]=258
target_w[2]=768
target_u[3]=12
target_v[3]=256
target_w[3]=258
target_u[4]=12
target_v[4]=2048
target_w[4]=2064

z = fferd2t_expect("local 7-to-5 relation",ffrep_local_exact_shape(source_u,source_v,source_w,7,target_u,target_v,target_w,5,4,14,14) == 1)
recipe = i64[fferd2_recipe_size()]
stats = i64[fferd2_stats_size()]
macro_length = fferd2_search(source_u,source_v,source_w,7,target_u,target_v,target_w,5,4,14,14,2,1,2,3,0,4,0,4,4096,recipe,stats) ## i64
z = fferd2t_expect("compiled flip plus two merges",macro_length == 3 && recipe[4] == 1 && stats[19] == 1 && stats[20] == 1 && stats[21] == 1 && stats[22] == 1 && stats[23] == 1)

replay_u = i64[5]
replay_v = i64[5]
replay_w = i64[5]
meta = i64[fferd2_meta_size()]
replayed = fferd2_replay_forward(source_u,source_v,source_w,7,target_u,target_v,target_w,5,recipe,replay_u,replay_v,replay_w,meta) ## i64
z = fferd2t_expect("forward word and cleanup exact",replayed == 5 && meta[0] == 1 && meta[1] == 1 && meta[8] == 1 && meta[9] == 1 && meta[10] == 1 && meta[11] == 1 && meta[12] == 1 && meta[13] == 1)
z = fferd2t_expect("forward reaches requested replacement",fftc_terms_same_set(replay_u,replay_v,replay_w,5,target_u,target_v,target_w,5) == 1)

undo_u = i64[7]
undo_v = i64[7]
undo_w = i64[7]
undone = fferd2_replay_undo(source_u,source_v,source_w,7,target_u,target_v,target_w,5,recipe,undo_u,undo_v,undo_w,meta) ## i64
z = fferd2t_expect("resolved undo reaches source",undone == 7 && meta[0] == 1 && meta[1] == 1 && meta[11] == 1 && meta[12] == 1 && meta[13] == 1 && fftc_terms_same_set(undo_u,undo_v,undo_w,7,source_u,source_v,source_w,7) == 1)

# Removing the inert final spectator gives a 6 -> 4 control with the same
# non-empty middle word.
recipe64 = i64[fferd2_recipe_size()]
stats64 = i64[fferd2_stats_size()]
length64 = fferd2_search(source_u,source_v,source_w,6,target_u,target_v,target_w,4,4,14,14,2,1,2,3,0,4,0,4,4096,recipe64,stats64) ## i64
z = fferd2t_expect("6-to-4 compiled",length64 == 3 && recipe64[4] == 1 && stats64[19] == 1)
out64_u = i64[4]
out64_v = i64[4]
out64_w = i64[4]
z = fferd2t_expect("6-to-4 replay",fferd2_replay_forward(source_u,source_v,source_w,6,target_u,target_v,target_w,4,recipe64,out64_u,out64_v,out64_w,meta) == 4 && meta[13] == 1)

# The minimum 5 -> 3 plumbing control is already the double-lifted endpoint;
# it therefore compiles the identity middle word followed by two exact merges.
small_target_u = i64[3]
small_target_v = i64[3]
small_target_w = i64[3]
small_target_u[0]=3
small_target_v[0]=5
small_target_w[0]=9
small_target_u[1]=6
small_target_v[1]=10
small_target_w[1]=12
small_target_u[2]=7
small_target_v[2]=11
small_target_w[2]=13
small_recipe = i64[fferd2_recipe_size()]
small_recipe[0]=1
small_recipe[1]=0
small_recipe[2]=5
small_recipe[3]=5
small_recipe[4]=0
small_recipe[5]=4
small_recipe[6]=4
small_recipe[7]=4
small_recipe[28]=2
small_recipe[29]=0
small_recipe[30]=0
small_recipe[31]=1
small_recipe[32]=1
small_recipe[33]=1
small_recipe[34]=2
small_recipe[35]=1
small_source_u = i64[5]
small_source_v = i64[5]
small_source_w = i64[5]
z = fferd2t_expect("5-to-3 planted lift",fferd2_build_lift(small_target_u,small_target_v,small_target_w,3,small_recipe,small_source_u,small_source_v,small_source_w) == 5)
small_stats = i64[fferd2_stats_size()]
length53 = fferd2_search(small_source_u,small_source_v,small_source_w,5,small_target_u,small_target_v,small_target_w,3,4,4,4,0,0,1,1,1,2,1,4,4096,small_recipe,small_stats) ## i64
z = fferd2t_expect("5-to-3 identity middle",length53 == 2 && small_recipe[4] == 0 && small_stats[19] == 1)
out53_u = i64[3]
out53_v = i64[3]
out53_w = i64[3]
z = fferd2t_expect("5-to-3 replay",fferd2_replay_forward(small_source_u,small_source_v,small_source_w,5,small_target_u,small_target_v,small_target_w,3,small_recipe,out53_u,out53_v,out53_w,meta) == 3 && meta[13] == 1)

repeat_recipe = i64[fferd2_recipe_size()]
repeat_stats = i64[fferd2_stats_size()]
repeat_length = fferd2_search(source_u,source_v,source_w,7,target_u,target_v,target_w,5,4,14,14,2,1,2,3,0,4,0,4,4096,repeat_recipe,repeat_stats) ## i64
z = fferd2t_expect("deterministic compile",repeat_length == macro_length)
i = 0 ## i64
while i < fferd2_recipe_size()
  z = fferd2t_expect("deterministic recipe "+i.to_s(),repeat_recipe[i] == recipe[i])
  i += 1

# Repeat all three rewrite arities inside the complete packaged 2x5x6 tensor.
# Each planted source has rank 49; the compiled macro restores the verified
# rank-47 certificate through a non-empty middle word and both cleanups.
full_n = 2 ## i64
full_m = 5 ## i64
full_p = 6 ## i64
full_capacity = ffr_default_capacity(full_n,full_m,full_p) ## i64
full_state = i64[ffr_state_size(full_capacity)]
full_root = __DIR__ + "/../lib/metaflip"
full_rank = ffr_load_scheme_cap(full_state,full_root+"/seeds/gf2/matmul_2x5x6_rank47_catalog_gf2.txt",full_n,full_m,full_p,full_capacity,99401,0,1,1,1) ## i64
z = fferd2t_expect("packaged 2x5x6 rank-47 target exact",full_rank == 47 && ffr_verify_best_exact(full_state,full_n,full_m,full_p) == 1)
full_u = i64[full_capacity]
full_v = i64[full_capacity]
full_w = i64[full_capacity]
z = fferd2t_expect("packaged 2x5x6 export",ffw_export_best(full_state,full_u,full_v,full_w) == full_rank)
full75 = fferd2t_full_control("full 7-to-5",full_u,full_v,full_w,full_rank,5,full_capacity,0) ## i64
full64 = fferd2t_full_control("full 6-to-4",full_u,full_v,full_w,full_rank,4,full_capacity,1) ## i64
full53 = fferd2t_full_control("full 5-to-3",full_u,full_v,full_w,full_rank,3,full_capacity,0) ## i64
z = fferd2t_expect("all full controls use non-empty middle words",full75 == 3 && full64 == 3 && full53 == 3)

<< "PASS rectangular endpoint rank-down-2 path="+recipe[4].to_s()+"+2merges controls=7to5,6to4,5to3 full=2x5x6/r49->r47 states="+stats[0].to_s()+"/"+stats[1].to_s()
