use flipfleet_coupled_dependency_repaint

-> ffcdrt_expect(label, condition) (String bool) i64
  if !condition
    << "COUPLED_DEPENDENCY_REPAINT_FAIL " + label
    exit(1)
  1

relation_u = i64[9]
relation_v = i64[9]
relation_w = i64[9]
count = ffcdr_fill_relation(1,2,4,1,2,1,2,0,relation_u,relation_v,relation_w) ## i64
ffcdrt_expect("relation filled",count == 9)
ffcdrt_expect("primitive exact circuit",ffc_is_primitive_circuit(relation_u,relation_v,relation_w,9) == 1)

# Source is the five-term side of the exact 5 -> 4 rewrite.
source_u = i64[5]
source_v = i64[5]
source_w = i64[5]
i = 0 ## i64
while i < 5
  source_u[i] = relation_u[i]
  source_v[i] = relation_v[i]
  source_w[i] = relation_w[i]
  i += 1
target_u = i64[4]
target_v = i64[4]
target_w = i64[4]
i = 0
while i < 4
  target_u[i] = relation_u[5 + i]
  target_v[i] = relation_v[5 + i]
  target_w[i] = relation_w[5 + i]
  i += 1
ffcdrt_expect("local 5to4 exact",ffgr_replacement_exact(source_u,source_v,source_w,5,target_u,target_v,target_w,4) == 1)

best_u = i64[9]
best_v = i64[9]
best_w = i64[9]
stats = i64[9]
found = ffcdr_scan(source_u,source_v,source_w,5,1,best_u,best_v,best_w,stats) ## i64
ffcdrt_expect("forward source recognized",found == 9 && stats[1] > 0 && stats[4] == -1 && stats[8] == 1)
reduced_u = i64[14]
reduced_v = i64[14]
reduced_w = i64[14]
reduced = ffcis3_apply_circuit(source_u,source_v,source_w,5,best_u,best_v,best_w,9,reduced_u,reduced_v,reduced_w) ## i64
ffcdrt_expect("forward rank drop",reduced == 4)
ffcdrt_expect("forward endpoint exact",ffgr_replacement_exact(source_u,source_v,source_w,5,reduced_u,reduced_v,reduced_w,reduced) == 1)

# The reverse scan recovers a structured +1 shoulder from the four-term side.
reverse_best_u = i64[9]
reverse_best_v = i64[9]
reverse_best_w = i64[9]
reverse_stats = i64[9]
reverse_found = ffcdr_scan(target_u,target_v,target_w,4,1,reverse_best_u,reverse_best_v,reverse_best_w,reverse_stats) ## i64
ffcdrt_expect("reverse target recognized",reverse_found == 9 && reverse_stats[2] > 0 && reverse_stats[4] == 1 && reverse_stats[8] == 1)
raised_u = i64[13]
raised_v = i64[13]
raised_w = i64[13]
raised = ffcis3_apply_circuit(target_u,target_v,target_w,4,reverse_best_u,reverse_best_v,reverse_best_w,9,raised_u,raised_v,raised_w) ## i64
ffcdrt_expect("reverse shoulder",raised == 5)
ffcdrt_expect("reverse endpoint exact",ffgr_replacement_exact(target_u,target_v,target_w,4,raised_u,raised_v,raised_w,raised) == 1)

# Axis permutations are part of the move rather than a caller obligation.
permuted_u = i64[5]
permuted_v = i64[5]
permuted_w = i64[5]
i = 0
while i < 5
  permuted_u[i] = source_w[i]
  permuted_v[i] = source_u[i]
  permuted_w[i] = source_v[i]
  i += 1
perm_best_u = i64[9]
perm_best_v = i64[9]
perm_best_w = i64[9]
perm_stats = i64[9]
perm_found = ffcdr_scan(permuted_u,permuted_v,permuted_w,5,0,perm_best_u,perm_best_v,perm_best_w,perm_stats) ## i64
ffcdrt_expect("axis permutation recognized",perm_found == 9 && perm_stats[4] == -1 && perm_stats[8] == 1)

# Three-anchor mixed-span fitting rediscovers the relation without requiring a
# complete side.  The source has five overlaps, so the retained image drops.
fit_best_u = i64[9]
fit_best_v = i64[9]
fit_best_w = i64[9]
fit_meta = i64[14]
fit_found = ffcdr_fit_search(source_u,source_v,source_w,5,0,0,fit_best_u,fit_best_v,fit_best_w,fit_meta) ## i64
ffcdrt_expect("mixed-span image fit",fit_found == 9 && fit_meta[0] > 0 && fit_meta[3] > 0 && fit_meta[7] > 0 && fit_meta[9] == -1 && fit_meta[13] == 1)

# Corrupting one term must fail the exact local gate.
target_w[0] = target_w[0] ^ 4
ffcdrt_expect("negative exact gate",ffgr_replacement_exact(source_u,source_v,source_w,5,target_u,target_v,target_w,4) == 0)

<< "flipfleet_coupled_dependency_repaint_test: pass primitive=9 source=5 target=4 forward=" + stats[1].to_s() + " reverse=" + reverse_stats[2].to_s()
