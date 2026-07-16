use ../lib/metaflip/strategies/macro_double_annihilation

-> ffmdat_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL macro double annihilation: " + label
    exit(1)
  1

# The source is a two-term tensor plus a four-point zero line with one overlap:
#
#   target = (1,1,1) + (1,2,2)
#   zero   = (1,1,1) + (2,1,1) + (4,1,1) + (7,1,1)
#   source = (1,2,2) + (2,1,1) + (4,1,1) + (7,1,1).
#
# The selected setup splits U=1 as 2+3 and U=2 as 1+3.  Its root contains only
# one duplicate class.  A three-edge state-dependent trigger manufactures the
# two prescribed doublets (3,3,2)^2 and (7,1,1)^2; neither cleanup is ready at
# the root.  On the canonical six-label states the resolved word is
# 36/40/35 = (2->3,U), (2->4,V), (2->1,W); its separately resolved undo is
# 35/40/36.  Cancelling both doublets leaves a changed exact rank-two
# presentation.
source_u = i64[4]
source_v = i64[4]
source_w = i64[4]
source_u[0] = 1
source_v[0] = 2
source_w[0] = 2
source_u[1] = 2
source_v[1] = 1
source_w[1] = 1
source_u[2] = 4
source_v[2] = 1
source_w[2] = 1
source_u[3] = 7
source_v[3] = 1
source_w[3] = 1

target_u = i64[2]
target_v = i64[2]
target_w = i64[2]
target_u[0] = 1
target_v[0] = 1
target_w[0] = 1
target_u[1] = 1
target_v[1] = 2
target_w[1] = 2

shape = i64[3]
shape[0] = 3
shape[1] = 2
shape[2] = 2
z = ffmdat_expect("source and rank-two target are exact",ffrep_local_exact_shape(source_u,source_v,source_w,4,target_u,target_v,target_w,2,3,2,2) == 1) ## i64

setup = i64[6]
setup[0] = 0
setup[1] = 0
setup[2] = 2
setup[3] = 1
setup[4] = 0
setup[5] = 1
goals = i64[6]
goals[0] = 3
goals[1] = 3
goals[2] = 2
goals[3] = 7
goals[4] = 1
goals[5] = 1
limits = i64[3]
limits[0] = 1
limits[1] = 4
limits[2] = 4096

out_u = i64[6]
out_v = i64[6]
out_w = i64[6]
recipe = i64[72]
stats = i64[20]
rank = ffmda_search(source_u,source_v,source_w,4,setup,goals,shape,limits,1,out_u,out_v,out_w,recipe,stats) ## i64
z = ffmdat_expect("prescribed double close returns rank two",rank == 2 && recipe[35] == 2) ## i64
z = ffmdat_expect("three-edge trigger word",recipe[8] == 3)
z = ffmdat_expect("cleanup is manufactured, not present at setup",stats[17] == 0)
z = ffmdat_expect("both replays retained",stats[10] == 1 && stats[11] == 1 && stats[19] == 1)
z = ffmdat_expect("rank-two endpoint exact",ffrep_local_exact_shape(source_u,source_v,source_w,4,out_u,out_v,out_w,rank,3,2,2) == 1)

# Audit every forward prefix against the original local tensor.
trace_u = i64[6]
trace_v = i64[6]
trace_w = i64[6]
z = ffmdat_expect("setup builds R+2 shoulder",ffmda_build_root(source_u,source_v,source_w,4,setup,trace_u,trace_v,trace_w) == 6)
z = ffrep_sort_slot(trace_u,trace_v,trace_w,0,6)
step = 0 ## i64
while step < recipe[8]
  z = ffmdat_expect("forward edge legal " + step.to_s(),fftc_apply_code(trace_u,trace_v,trace_w,6,recipe[9+step],0-1) == 1)
  z = ffrep_sort_slot(trace_u,trace_v,trace_w,0,6)
  z = ffmdat_expect("forward prefix exact " + step.to_s(),ffrep_local_exact_shape(source_u,source_v,source_w,4,trace_u,trace_v,trace_w,6,3,2,2) == 1)
  step += 1
z = ffmdat_expect("prescribed cleanup ready",ffmda_goal_hit(trace_u,trace_v,trace_w,0,6,goals) == 1)

forward_u = i64[6]
forward_v = i64[6]
forward_w = i64[6]
forward_meta = i64[8]
forward_rank = ffmda_replay_forward(source_u,source_v,source_w,4,recipe,forward_u,forward_v,forward_w,forward_meta) ## i64
z = ffmdat_expect("forward replay exact",forward_rank == 2 && forward_meta[7] == 1 && fftc_terms_same_set(out_u,out_v,out_w,2,forward_u,forward_v,forward_w,2) == 1)
z = ffmdat_expect("every forward prefix gated",forward_meta[1] == recipe[8])

undo_u = i64[4]
undo_v = i64[4]
undo_w = i64[4]
undo_meta = i64[8]
undo_rank = ffmda_replay_undo(source_u,source_v,source_w,4,out_u,out_v,out_w,2,recipe,undo_u,undo_v,undo_w,undo_meta) ## i64
z = ffmdat_expect("undo replay exact",undo_rank == 4 && undo_meta[7] == 1 && fftc_terms_same_set(source_u,source_v,source_w,4,undo_u,undo_v,undo_w,4) == 1)
z = ffmdat_expect("every undo prefix gated",undo_meta[1] == recipe[8])

repeat_u = i64[6]
repeat_v = i64[6]
repeat_w = i64[6]
repeat_recipe = i64[72]
repeat_stats = i64[20]
workspace_u = i64[limits[2]*6]
workspace_v = i64[limits[2]*6]
workspace_w = i64[limits[2]*6]
workspace_parents = i64[limits[2]]
workspace_depths = i64[limits[2]]
workspace_hashes = i64[limits[2]]
workspace_table = i64[ffrep_table_size(limits[2])]
repeat_rank = ffmda_search_workspace(source_u,source_v,source_w,4,setup,goals,shape,limits,1,workspace_u,workspace_v,workspace_w,workspace_parents,workspace_depths,workspace_hashes,workspace_table,repeat_u,repeat_v,repeat_w,repeat_recipe,repeat_stats) ## i64
z = ffmdat_expect("prescribed search is deterministic",repeat_rank == rank && fftc_terms_same_set(out_u,out_v,out_w,rank,repeat_u,repeat_v,repeat_w,repeat_rank) == 1)
i = 0 ## i64
while i < 72
  z = ffmdat_expect("deterministic recipe " + i.to_s(),repeat_recipe[i] == recipe[i])
  i += 1

tampered = i64[72]
i = 0
while i < 72
  tampered[i] = recipe[i]
  i += 1
tampered[19] = 0 - 1
z = ffmdat_expect("invalid reverse word rejected",ffmda_replay_undo(source_u,source_v,source_w,4,out_u,out_v,out_w,2,tampered,undo_u,undo_v,undo_w,undo_meta) == 0)

# Discovery mode must still freeze concrete goals into the recipe.
auto_u = i64[6]
auto_v = i64[6]
auto_w = i64[6]
auto_recipe = i64[72]
auto_stats = i64[20]
auto_rank = ffmda_search(source_u,source_v,source_w,4,setup,goals,shape,limits,0,auto_u,auto_v,auto_w,auto_recipe,auto_stats) ## i64
z = ffmdat_expect("discovery mode returns exact rank two",auto_rank == 2 && auto_recipe[41] == 1 && auto_stats[14] == 0)
concrete_goals = i64[6]
z = ffmda_recipe_goal(auto_recipe,concrete_goals)
z = ffmdat_expect("discovered recipe has concrete goals",ffmda_goal_distinct(concrete_goals) == 1)

# A concrete goal absent from the bounded tree is a clean miss.
bad_goals = i64[6]
bad_goals[0] = 6
bad_goals[1] = 3
bad_goals[2] = 3
bad_goals[3] = 7
bad_goals[4] = 3
bad_goals[5] = 2
bad_recipe = i64[72]
bad_stats = i64[20]
bad_rank = ffmda_search(source_u,source_v,source_w,4,setup,bad_goals,shape,limits,1,auto_u,auto_v,auto_w,bad_recipe,bad_stats) ## i64
z = ffmdat_expect("wrong prescribed cleanup is rejected",bad_rank == 0 && bad_stats[19] == 0)

<< "PASS macro_double_annihilation_test rank=4->" + rank.to_s() + " depth=" + recipe[8].to_s() + " forward=" + recipe[9].to_s() + "," + recipe[10].to_s() + "," + recipe[11].to_s() + " undo=" + recipe[19].to_s() + "," + recipe[20].to_s() + "," + recipe[21].to_s() + " nodes=" + stats[0].to_s() + " legal=" + stats[2].to_s() + " root_ready=" + stats[17].to_s()
