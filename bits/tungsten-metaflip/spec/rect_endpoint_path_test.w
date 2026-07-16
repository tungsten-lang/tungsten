use ../lib/metaflip/strategies/rect_endpoint_path

-> ffrept_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL rectangular endpoint path: " + label
    exit(1)
  1

-> ffrept_copy(source_u, source_v, source_w, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  ffrep_copy_slot(source_u,source_v,source_w,0,count,out_u,out_v,out_w,0)

# Build one exact BFS arena, then retain the first state at the requested
# shortest depth. This makes depths 2/4/6 genuine distance controls rather
# than merely planted words with a possible shorter solution.
-> ffrept_target_at_depth(root_u, root_v, root_w, count, wanted_depth, node_cap, out_u, out_v, out_w, tree_meta) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  states_u = i64[node_cap*count]
  states_v = i64[node_cap*count]
  states_w = i64[node_cap*count]
  parents = i64[node_cap]
  depths = i64[node_cap]
  hashes = i64[node_cap]
  table = i64[ffrep_table_size(node_cap)]
  nodes = ffrep_build_tree(root_u,root_v,root_w,count,wanted_depth,node_cap,states_u,states_v,states_w,parents,depths,hashes,table,tree_meta) ## i64
  i = 0 ## i64
  while i < nodes
    if depths[i] == wanted_depth
      z = ffrep_copy_slot(states_u,states_v,states_w,i*count,count,out_u,out_v,out_w,0) ## i64
      return 1
    i += 1
  0

# Four labelled terms obtained by the split used by the exact holonomy
# fixture: (1,2,2) becomes (2,2,2)+(3,2,2). The unequal rectangular widths
# deliberately include a 30-bit V axis even though this compact fixture
# occupies only low bits.
count = 4 ## i64
source_u = i64[count]
source_v = i64[count]
source_w = i64[count]
source_u[0] = 2
source_v[0] = 2
source_w[0] = 2
source_u[1] = 6
source_v[1] = 2
source_w[1] = 5
source_u[2] = 1
source_v[2] = 7
source_w[2] = 2
source_u[3] = 3
source_v[3] = 2
source_w[3] = 2
z = ffrep_sort_slot(source_u,source_v,source_w,0,count) ## i64

udim = 10 ## i64
vdim = 30 ## i64
wdim = 12 ## i64
z = ffrept_expect("source factors fit rectangular widths",ffrep_terms_fit(source_u,source_v,source_w,count,udim,vdim,wdim) == 1)

targets_u = i64[count*3]
targets_v = i64[count*3]
targets_w = i64[count*3]
depths_wanted = i64[3]
depths_wanted[0] = 2
depths_wanted[1] = 4
depths_wanted[2] = 6
ordinal = 0 ## i64
while ordinal < 3
  target_u = i64[count]
  target_v = i64[count]
  target_w = i64[count]
  tree_meta = i64[6]
  planted = ffrept_target_at_depth(source_u,source_v,source_w,count,depths_wanted[ordinal],65536,target_u,target_v,target_w,tree_meta) ## i64
  << "RECT_ENDPOINT_PATH_FIXTURE depth="+depths_wanted[ordinal].to_s()+" planted="+planted.to_s()+" nodes="+tree_meta[0].to_s()+" legal="+tree_meta[2].to_s()+" capped="+tree_meta[4].to_s()+" reached="+tree_meta[5].to_s()
  z = ffrept_expect("target exists at depth "+depths_wanted[ordinal].to_s(),planted == 1 && tree_meta[4] == 0)
  z = ffrept_expect("planted target shape-exact "+depths_wanted[ordinal].to_s(),ffrep_local_exact_shape(source_u,source_v,source_w,count,target_u,target_v,target_w,count,udim,vdim,wdim) == 1)

  # Reverse the presentation to ensure endpoint matching is a multiset
  # operation rather than a dependence on caller label order.
  perm_u = i64[count]
  perm_v = i64[count]
  perm_w = i64[count]
  i = 0 ## i64
  while i < count
    perm_u[i] = target_u[count-1-i]
    perm_v[i] = target_v[count-1-i]
    perm_w[i] = target_w[count-1-i]
    i += 1

  recipe = i64[ffrep_recipe_size()]
  stats = i64[ffrep_stats_size()]
  found = ffrep_search_same_rank(source_u,source_v,source_w,count,perm_u,perm_v,perm_w,count,udim,vdim,wdim,depths_wanted[ordinal],32768,recipe,stats) ## i64
  z = ffrept_expect("find exact shortest depth "+depths_wanted[ordinal].to_s(),found == depths_wanted[ordinal] && stats[7] == found && stats[15] == 1)
  z = ffrept_expect("search replay/undo gates "+depths_wanted[ordinal].to_s(),stats[11] == 1 && stats[12] == 1 && stats[13] == 1)
  << "RECT_ENDPOINT_PATH_SEARCH depth="+found.to_s()+" forward_states="+stats[0].to_s()+" backward_states="+stats[1].to_s()+" legal="+stats[4].to_s()+" revisits="+stats[5].to_s()+" capped="+stats[10].to_s()

  replay_u = i64[count]
  replay_v = i64[count]
  replay_w = i64[count]
  replay_meta = i64[ffrep_replay_meta_size()]
  replayed = ffrep_replay_forward(source_u,source_v,source_w,count,perm_u,perm_v,perm_w,count,recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
  z = ffrept_expect("forward prefix gates "+depths_wanted[ordinal].to_s(),replayed == count && replay_meta[0] == found && replay_meta[1] == found && replay_meta[2] == 1 && replay_meta[3] == 1)
  undone = ffrep_replay_undo(source_u,source_v,source_w,count,perm_u,perm_v,perm_w,count,recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
  z = ffrept_expect("undo prefix gates "+depths_wanted[ordinal].to_s(),undone == count && replay_meta[0] == found && replay_meta[1] == found && replay_meta[2] == 1 && replay_meta[3] == 1)

  if ordinal == 2
    repeat_recipe = i64[ffrep_recipe_size()]
    repeat_stats = i64[ffrep_stats_size()]
    repeated = ffrep_search_same_rank(source_u,source_v,source_w,count,perm_u,perm_v,perm_w,count,udim,vdim,wdim,depths_wanted[ordinal],32768,repeat_recipe,repeat_stats) ## i64
    z = ffrept_expect("deterministic depth-six result",repeated == found && repeat_stats[0] == stats[0] && repeat_stats[1] == stats[1])
    i = 0
    while i < ffrep_recipe_size()
      z = ffrept_expect("deterministic recipe word "+i.to_s(),repeat_recipe[i] == recipe[i])
      i += 1

  i = 0
  while i < count
    targets_u[ordinal*count+i] = target_u[i]
    targets_v[ordinal*count+i] = target_v[i]
    targets_w[ordinal*count+i] = target_w[i]
    i += 1
  ordinal += 1

# The depth-six endpoint must not be reported inside depth five.
short_recipe = i64[ffrep_recipe_size()]
short_stats = i64[ffrep_stats_size()]
# The depth-six target occupies the third flat slot.
depth6_u = i64[count]
depth6_v = i64[count]
depth6_w = i64[count]
z = ffrep_copy_slot(targets_u,targets_v,targets_w,2*count,count,depth6_u,depth6_v,depth6_w,0)
short = ffrep_search_same_rank(source_u,source_v,source_w,count,depth6_u,depth6_v,depth6_w,count,udim,vdim,wdim,5,32768,short_recipe,short_stats) ## i64
z = ffrept_expect("depth bound is respected",short == 0 && short_stats[10] == 0)

# A tiny state envelope may return only a clearly marked capped miss.
cap_recipe = i64[ffrep_recipe_size()]
cap_stats = i64[ffrep_stats_size()]
capped = ffrep_search_same_rank(source_u,source_v,source_w,count,depth6_u,depth6_v,depth6_w,count,udim,vdim,wdim,6,16,cap_recipe,cap_stats) ## i64
z = ffrept_expect("bounded arena reports cap",capped == 0 && cap_stats[10] == 1)

# A changed but tensor-inequivalent target is rejected before graph search.
bad_u = i64[count]
bad_v = i64[count]
bad_w = i64[count]
z = ffrept_copy(source_u,source_v,source_w,count,bad_u,bad_v,bad_w)
bad_u[0] = bad_u[0] ^ 2
bad_recipe = i64[ffrep_recipe_size()]
bad_stats = i64[ffrep_stats_size()]
bad = ffrep_search_same_rank(source_u,source_v,source_w,count,bad_u,bad_v,bad_w,count,udim,vdim,wdim,6,32768,bad_recipe,bad_stats) ## i64
z = ffrept_expect("inequivalent endpoint rejected",bad == 0 && bad_stats[13] == 0)

<< "PASS rect_endpoint_path_test depths=2,4,6 capped="+cap_stats[10].to_s()
