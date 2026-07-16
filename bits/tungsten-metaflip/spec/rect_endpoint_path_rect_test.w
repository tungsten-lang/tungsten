use ../lib/metaflip/strategies/rect_endpoint_path
use ../lib/metaflip/rect

-> ffreprit_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL rectangular endpoint path integration: " + label
    exit(1)
  1

-> ffreprit_depth_one(source_u, source_v, source_w, target_u, target_v, target_w) (i64[] i64[] i64[] i64[] i64[] i64[]) i64
  count = 2 ## i64
  node_cap = 64 ## i64
  states_u = i64[node_cap*count]
  states_v = i64[node_cap*count]
  states_w = i64[node_cap*count]
  parents = i64[node_cap]
  depths = i64[node_cap]
  hashes = i64[node_cap]
  table = i64[ffrep_table_size(node_cap)]
  meta = i64[6]
  nodes = ffrep_build_tree(source_u,source_v,source_w,count,1,node_cap,states_u,states_v,states_w,parents,depths,hashes,table,meta) ## i64
  if meta[4] != 0
    return 0
  i = 0 ## i64
  while i < nodes
    if depths[i] == 1
      z = ffrep_copy_slot(states_u,states_v,states_w,i*count,count,target_u,target_v,target_w,0) ## i64
      return 1
    i += 1
  0

-> ffreprit_collides(us, vs, ws, rank, skip0, skip1, tu, tv, tw) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[]) i64
  t = 0 ## i64
  while t < 2
    i = 0 ## i64
    while i < rank
      if i != skip0 && i != skip1
        if us[i] == tu[t] && vs[i] == tv[t] && ws[i] == tw[t]
          return 1
      i += 1
    t += 1
  if tu[0] == tu[1] && tv[0] == tv[1] && tw[0] == tw[1]
    return 1
  0

n = 2 ## i64
m = 5 ## i64
p = 6 ## i64
udim = n*m ## i64
vdim = m*p ## i64
wdim = n*p ## i64
root = __DIR__ + "/../lib/metaflip"
seed_path = root + "/seeds/gf2/matmul_2x5x6_rank47_catalog_gf2.txt"
capacity = ffr_default_capacity(n,m,p) ## i64
base = i64[ffr_state_size(capacity)]
rank = ffr_load_scheme_cap(base,seed_path,n,m,p,capacity,97001,0,1,1,1) ## i64
z = ffreprit_expect("base certificate",rank == 47 && ffr_verify_best_exact(base,n,m,p) == 1)
us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
exported = ffw_export_best(base,us,vs,ws) ## i64
z = ffreprit_expect("base export",exported == rank)

source_u = i64[2]
source_v = i64[2]
source_w = i64[2]
target_u = i64[2]
target_v = i64[2]
target_w = i64[2]
target_full_u = i64[capacity]
target_full_v = i64[capacity]
target_full_w = i64[capacity]
candidate = i64[ffr_state_size(capacity)]
selected0 = 0 - 1 ## i64
selected1 = 0 - 1 ## i64
first = 0 ## i64
while first < rank-1 && selected0 < 0
  second = first + 1 ## i64
  while second < rank && selected0 < 0
    source_u[0] = us[first]
    source_v[0] = vs[first]
    source_w[0] = ws[first]
    source_u[1] = us[second]
    source_v[1] = vs[second]
    source_w[1] = ws[second]
    z = ffrep_sort_slot(source_u,source_v,source_w,0,2)
    made = ffreprit_depth_one(source_u,source_v,source_w,target_u,target_v,target_w) ## i64
    if made == 1 && ffreprit_collides(us,vs,ws,rank,first,second,target_u,target_v,target_w) == 0
      i = 0 ## i64
      while i < rank
        target_full_u[i] = us[i]
        target_full_v[i] = vs[i]
        target_full_w[i] = ws[i]
        i += 1
      target_full_u[first] = target_u[0]
      target_full_v[first] = target_v[0]
      target_full_w[first] = target_w[0]
      target_full_u[second] = target_u[1]
      target_full_v[second] = target_v[1]
      target_full_w[second] = target_w[1]
      loaded = ffr_init_terms_cap(candidate,target_full_u,target_full_v,target_full_w,rank,n,m,p,capacity,97003,0,1,1,1) ## i64
      if loaded == rank && ffr_verify_best_exact(candidate,n,m,p) == 1
        selected0 = first
        selected1 = second
    second += 1
  first += 1
z = ffreprit_expect("real certificate exposes a local endpoint",selected0 >= 0 && selected1 >= 0)
z = ffreprit_expect("shape-aware local gate",ffrep_local_exact_shape(source_u,source_v,source_w,2,target_u,target_v,target_w,2,udim,vdim,wdim) == 1)

recipe = i64[ffrep_recipe_size()]
stats = i64[ffrep_stats_size()]
found = ffrep_search_same_rank(source_u,source_v,source_w,2,target_u,target_v,target_w,2,udim,vdim,wdim,1,256,recipe,stats) ## i64
z = ffreprit_expect("compiler returns shortest word",found == 1 && stats[15] == 1 && stats[11] == 1 && stats[12] == 1)
replay_u = i64[2]
replay_v = i64[2]
replay_w = i64[2]
meta = i64[ffrep_replay_meta_size()]
replayed = ffrep_replay_forward(source_u,source_v,source_w,2,target_u,target_v,target_w,2,recipe,replay_u,replay_v,replay_w,meta) ## i64
z = ffreprit_expect("forward prefixes exact",replayed == 2 && meta[0] == 1 && meta[1] == 1 && meta[2] == 1 && meta[3] == 1)

# Reconstruct the complete target from the independently replayed local word
# and demand the rectangular matrix-multiplication certificate, not merely the
# local relation.
i = 0
while i < rank
  target_full_u[i] = us[i]
  target_full_v[i] = vs[i]
  target_full_w[i] = ws[i]
  i += 1
target_full_u[selected0] = replay_u[0]
target_full_v[selected0] = replay_v[0]
target_full_w[selected0] = replay_w[0]
target_full_u[selected1] = replay_u[1]
target_full_v[selected1] = replay_v[1]
target_full_w[selected1] = replay_w[1]
loaded = ffr_init_terms_cap(candidate,target_full_u,target_full_v,target_full_w,rank,n,m,p,capacity,97007,0,1,1,1) ## i64
z = ffreprit_expect("replayed full rectangular certificate",loaded == rank && ffr_verify_best_exact(candidate,n,m,p) == 1)

undone = ffrep_replay_undo(source_u,source_v,source_w,2,target_u,target_v,target_w,2,recipe,replay_u,replay_v,replay_w,meta) ## i64
z = ffreprit_expect("undo prefixes exact",undone == 2 && meta[0] == 1 && meta[1] == 1 && meta[2] == 1 && meta[3] == 1)
z = ffreprit_expect("undo returns selected source",fftc_terms_same_set(source_u,source_v,source_w,2,replay_u,replay_v,replay_w,2) == 1)

<< "PASS rect_endpoint_path_rect_test pair="+selected0.to_s()+","+selected1.to_s()+" states="+stats[0].to_s()+"/"+stats[1].to_s()+" path="+found.to_s()
