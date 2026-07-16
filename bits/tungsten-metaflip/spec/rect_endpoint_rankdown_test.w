use ../lib/metaflip/strategies/rect_endpoint_rankdown
use ../lib/metaflip/rect

-> fferdt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL rectangular endpoint rank-down: " + label
    exit(1)
  1

source_u = i64[6]
source_v = i64[6]
source_w = i64[6]
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
source_u[4]=12
source_v[4]=256
source_w[4]=258
source_u[5]=12
source_v[5]=2048
source_w[5]=2064

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

z = fferdt_expect("local 6-to-5 relation",ffrep_local_exact_shape(source_u,source_v,source_w,6,target_u,target_v,target_w,5,4,14,14) == 1)
recipe = i64[fferd_recipe_size()]
stats = i64[fferd_stats_size()]
macro_length = fferd_search(source_u,source_v,source_w,6,target_u,target_v,target_w,5,4,14,14,2,1,2,4,4096,recipe,stats) ## i64
z = fferdt_expect("compiled flip plus merge",macro_length == 2 && recipe[4] == 1 && stats[19] == 1)

replay_u = i64[5]
replay_v = i64[5]
replay_w = i64[5]
meta = i64[fferd_meta_size()]
replayed = fferd_replay_forward(source_u,source_v,source_w,6,target_u,target_v,target_w,5,recipe,replay_u,replay_v,replay_w,meta) ## i64
z = fferdt_expect("forward word and cleanup exact",replayed == 5 && meta[0] == 1 && meta[1] == 1 && meta[8] == 1 && meta[9] == 1 && meta[10] == 1 && meta[11] == 1)
z = fferdt_expect("forward reaches requested replacement",fftc_terms_same_set(replay_u,replay_v,replay_w,5,target_u,target_v,target_w,5) == 1)

undo_u = i64[6]
undo_v = i64[6]
undo_w = i64[6]
undone = fferd_replay_undo(source_u,source_v,source_w,6,target_u,target_v,target_w,5,recipe,undo_u,undo_v,undo_w,meta) ## i64
z = fferdt_expect("resolved undo reaches source",undone == 6 && meta[0] == 1 && meta[1] == 1 && meta[9] == 1 && meta[10] == 1 && meta[11] == 1 && fftc_terms_same_set(undo_u,undo_v,undo_w,6,source_u,source_v,source_w,6) == 1)

# Graft the replayed local word into the exact packaged r26 shoulder.  The
# result must be the complete r25 matrix-multiplication tensor, not merely an
# isolated local identity.
n = 2 ## i64
m = 2 ## i64
p = 7 ## i64
capacity = ffr_default_capacity(n,m,p) ## i64
shoulder = i64[ffr_state_size(capacity)]
root = __DIR__ + "/../lib/metaflip"
shoulder_rank = ffr_load_scheme_cap(shoulder,root+"/seeds/gf2/matmul_2x2x7_rank26_isotropy_split_plus1_gf2.txt",n,m,p,capacity,99701,0,1,1,1) ## i64
z = fferdt_expect("exact packaged shoulder",shoulder_rank == 26 && ffr_verify_best_exact(shoulder,n,m,p) == 1)
full_u = i64[capacity]
full_v = i64[capacity]
full_w = i64[capacity]
z = fferdt_expect("shoulder export",ffw_export_best(shoulder,full_u,full_v,full_w) == 26)
selected = i64[26]
selected[4]=1
selected[5]=1
selected[8]=1
selected[10]=1
selected[17]=1
selected[18]=1
candidate_u = i64[capacity]
candidate_v = i64[capacity]
candidate_w = i64[capacity]
candidate_rank = 0 ## i64
i = 0 ## i64
while i < 26
  if selected[i] == 0
    candidate_u[candidate_rank] = full_u[i]
    candidate_v[candidate_rank] = full_v[i]
    candidate_w[candidate_rank] = full_w[i]
    candidate_rank += 1
  i += 1
i = 0
while i < replayed
  candidate_u[candidate_rank] = replay_u[i]
  candidate_v[candidate_rank] = replay_v[i]
  candidate_w[candidate_rank] = replay_w[i]
  candidate_rank += 1
  i += 1
candidate = i64[ffr_state_size(capacity)]
loaded = ffr_init_terms_cap(candidate,candidate_u,candidate_v,candidate_w,candidate_rank,n,m,p,capacity,99703,0,1,1,1) ## i64
z = fferdt_expect("replayed full r25 certificate",candidate_rank == 25 && loaded == 25 && ffr_verify_best_exact(candidate,n,m,p) == 1)

auto_recipe = i64[fferd_recipe_size()]
auto_stats = i64[fferd_auto_stats_size()]
auto_length = fferd_search_auto(source_u,source_v,source_w,6,target_u,target_v,target_w,5,4,14,14,4,4096,64,auto_recipe,auto_stats) ## i64
z = fferdt_expect("automatic cleanup scaffold",auto_length == 2 && auto_recipe[4] == 1 && auto_recipe[29] == 2 && auto_recipe[30] == 1 && auto_stats[20] > 0 && auto_stats[21] > 0 && auto_stats[23] > 0)
z = fferdt_expect("automatic recipe replays",fferd_replay_forward(source_u,source_v,source_w,6,target_u,target_v,target_w,5,auto_recipe,replay_u,replay_v,replay_w,meta) == 5 && meta[11] == 1)

repeat_recipe = i64[fferd_recipe_size()]
repeat_stats = i64[fferd_stats_size()]
repeat_length = fferd_search(source_u,source_v,source_w,6,target_u,target_v,target_w,5,4,14,14,2,1,2,4,4096,repeat_recipe,repeat_stats) ## i64
z = fferdt_expect("deterministic compile",repeat_length == macro_length)
i = 0
while i < fferd_recipe_size()
  z = fferdt_expect("deterministic recipe " + i.to_s(),repeat_recipe[i] == recipe[i])
  i += 1

<< "PASS rectangular endpoint rank-down path="+recipe[4].to_s()+"+merge full_rank="+loaded.to_s()+" states="+stats[0].to_s()+"/"+stats[1].to_s()+" auto="+auto_stats[20].to_s()+"/"+auto_stats[21].to_s()
