# End-to-end 6 -> 5 catalyst-lift control on the exact 2x5x6 scheme used by
# the rectangular k-XOR positive fixture. No GPU or k-XOR source is imported:
# this independently builds the rank-48 split shoulder, compiles its known
# local reduction into a fixed-rank word, strips the triangle, and full-gates
# the reconstructed rank-47 certificate.

use ../lib/metaflip/strategies/rect_catalyst_lift
use ../lib/metaflip/rect

-> ffrclrt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL rectangular catalyst lift integration: " + label
    exit(1)
  1

n=2 ## i64
m=5 ## i64
p=6 ## i64
root=__DIR__+"/../lib/metaflip"
seed_path=root+"/seeds/gf2/matmul_2x5x6_rank47_catalog_gf2.txt"
capacity=ffr_default_capacity(n,m,p) ## i64
base=i64[ffr_state_size(capacity)]
base_rank=ffr_load_scheme_cap(base,seed_path,n,m,p,capacity,99001,0,1,1,1) ## i64
z=ffrclrt_expect("base certificate",base_rank==47 && ffr_verify_best_exact(base,n,m,p)==1)
us=i64[capacity]
vs=i64[capacity]
ws=i64[capacity]
z=ffrclrt_expect("base export",ffw_export_best(base,us,vs,ws)==base_rank)

split_index=0-1 ## i64
split_axis=0-1 ## i64
i=0 ## i64
while i<base_rank && split_index<0
  if ffw_popcount(us[i])>1
    split_index=i
    split_axis=0
  if split_index<0 && ffw_popcount(vs[i])>1
    split_index=i
    split_axis=1
  if split_index<0 && ffw_popcount(ws[i])>1
    split_index=i
    split_axis=2
  i+=1
z=ffrclrt_expect("splittable base term",split_index>=0)
factor=us[split_index] ## i64
if split_axis==1
  factor=vs[split_index]
if split_axis==2
  factor=ws[split_index]
first_part=factor & (0 - factor) ## i64
second_part=factor ^ first_part ## i64
z=ffrclrt_expect("nonzero split",first_part>0 && second_part>0)

shoulder_u=i64[capacity]
shoulder_v=i64[capacity]
shoulder_w=i64[capacity]
shoulder_rank=0 ## i64
i=0
while i<base_rank
  if i != split_index
    shoulder_u[shoulder_rank]=us[i]
    shoulder_v[shoulder_rank]=vs[i]
    shoulder_w[shoulder_rank]=ws[i]
    shoulder_rank+=1
  i+=1
child_a=shoulder_rank ## i64
shoulder_u[shoulder_rank]=us[split_index]
shoulder_v[shoulder_rank]=vs[split_index]
shoulder_w[shoulder_rank]=ws[split_index]
z=ffrcl_axis_set(shoulder_u,shoulder_v,shoulder_w,shoulder_rank,split_axis,first_part)
shoulder_rank+=1
child_b=shoulder_rank ## i64
shoulder_u[shoulder_rank]=us[split_index]
shoulder_v[shoulder_rank]=vs[split_index]
shoulder_w[shoulder_rank]=ws[split_index]
z=ffrcl_axis_set(shoulder_u,shoulder_v,shoulder_w,shoulder_rank,split_axis,second_part)
shoulder_rank+=1
z=ffrclrt_expect("rank-48 shoulder",shoulder_rank==base_rank+1)
shoulder_state=i64[ffr_state_size(capacity)]
loaded=ffr_init_terms_cap(shoulder_state,shoulder_u,shoulder_v,shoulder_w,shoulder_rank,n,m,p,capacity,99003,0,1,1,1) ## i64
z=ffrclrt_expect("shoulder full gate",loaded==shoulder_rank && ffr_verify_best_exact(shoulder_state,n,m,p)==1)

source_count=6 ## i64
target_count=5 ## i64
source_u=i64[source_count]
source_v=i64[source_count]
source_w=i64[source_count]
target_u=i64[target_count]
target_v=i64[target_count]
target_w=i64[target_count]
source_u[0]=shoulder_u[child_a]
source_v[0]=shoulder_v[child_a]
source_w[0]=shoulder_w[child_a]
source_u[1]=shoulder_u[child_b]
source_v[1]=shoulder_v[child_b]
source_w[1]=shoulder_w[child_b]
target_u[0]=us[split_index]
target_v[0]=vs[split_index]
target_w[0]=ws[split_index]
i=0
while i<4
  source_u[i+2]=shoulder_u[i]
  source_v[i+2]=shoulder_v[i]
  source_w[i+2]=shoulder_w[i]
  target_u[i+1]=shoulder_u[i]
  target_v[i+1]=shoulder_v[i]
  target_w[i+1]=shoulder_w[i]
  i+=1
shape=i64[3]
shape[0]=n*m
shape[1]=m*p
shape[2]=n*p
z=ffrclrt_expect("known 6-to-5 local equality",ffrep_local_exact_shape(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,shape[0],shape[1],shape[2])==1)

limits=i64[3]
limits[0]=4
limits[1]=4096
limits[2]=8
source_aug_u=i64[8]
source_aug_v=i64[8]
source_aug_w=i64[8]
target_aug_u=i64[8]
target_aug_v=i64[8]
target_aug_w=i64[8]
recipe=i64[ffrcl_recipe_size()]
path_recipe=i64[ffrep_recipe_size()]
stats=i64[ffrcl_stats_size()]
start=ccall("__w_clock_ms") ## i64
found=ffrcl_search(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,shape,limits,source_aug_u,source_aug_v,source_aug_w,target_aug_u,target_aug_v,target_aug_w,recipe,path_recipe,stats) ## i64
elapsed=ccall("__w_clock_ms")-start ## i64
z=ffrclrt_expect("real 6-to-5 word",found==2 && stats[15]==1 && stats[11]==1 && stats[12]==1)
z=ffrclrt_expect("eight-label lifted gates",ffrep_local_exact_shape(source_u,source_v,source_w,source_count,source_aug_u,source_aug_v,source_aug_w,8,shape[0],shape[1],shape[2])==1 && ffrep_local_exact_shape(target_u,target_v,target_w,target_count,target_aug_u,target_aug_v,target_aug_w,8,shape[0],shape[1],shape[2])==1)

replay_u=i64[8]
replay_v=i64[8]
replay_w=i64[8]
replay_meta=i64[ffrep_replay_meta_size()]
replayed=ffrep_replay_forward(source_aug_u,source_aug_v,source_aug_w,8,target_aug_u,target_aug_v,target_aug_w,8,path_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
stripped_u=i64[6]
stripped_v=i64[6]
stripped_w=i64[6]
stripped=ffrcl_strip_target(replay_u,replay_v,replay_w,replayed,recipe,stripped_u,stripped_v,stripped_w) ## i64
z=ffrclrt_expect("forward strips to known five",stripped==target_count && fftc_terms_same_set(stripped_u,stripped_v,stripped_w,stripped,target_u,target_v,target_w,target_count)==1)

# Remove the selected six terms from the exact shoulder and insert the five
# independently replayed terms. This reconstructs a complete lower-rank
# certificate without borrowing the already-loaded base state for admission.
result_u=i64[capacity]
result_v=i64[capacity]
result_w=i64[capacity]
result_rank=0 ## i64
i=0
while i<shoulder_rank
  selected=0 ## i64
  if i==child_a || i==child_b || i<4
    selected=1
  if selected==0
    result_u[result_rank]=shoulder_u[i]
    result_v[result_rank]=shoulder_v[i]
    result_w[result_rank]=shoulder_w[i]
    result_rank+=1
  i+=1
i=0
while i<stripped
  result_u[result_rank]=stripped_u[i]
  result_v[result_rank]=stripped_v[i]
  result_w[result_rank]=stripped_w[i]
  result_rank+=1
  i+=1
z=ffrclrt_expect("lower-rank reconstruction count",result_rank==base_rank)
result_state=i64[ffr_state_size(capacity)]
loaded=ffr_init_terms_cap(result_state,result_u,result_v,result_w,result_rank,n,m,p,capacity,99007,0,1,1,1) ## i64
z=ffrclrt_expect("lower-rank full rectangular gate",loaded==base_rank && ffr_verify_best_exact(result_state,n,m,p)==1)
checked_u=i64[capacity]
checked_v=i64[capacity]
checked_w=i64[capacity]
z=ffrclrt_expect("lower-rank export",ffw_export_best(result_state,checked_u,checked_v,checked_w)==base_rank)
z=ffrclrt_expect("recovers base certificate term set",fftc_terms_same_set(checked_u,checked_v,checked_w,base_rank,us,vs,ws,base_rank)==1)

undone=ffrep_replay_undo(source_aug_u,source_aug_v,source_aug_w,8,target_aug_u,target_aug_v,target_aug_w,8,path_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
stripped=ffrcl_strip_source(replay_u,replay_v,replay_w,undone,recipe,stripped_u,stripped_v,stripped_w)
z=ffrclrt_expect("undo strips to six-term shoulder fringe",stripped==source_count && fftc_terms_same_set(stripped_u,stripped_v,stripped_w,stripped,source_u,source_v,source_w,source_count)==1)

# A deliberately tiny arena records whether the same valid word was found
# before the cap or from a capped partial tree; either outcome must replay.
tiny_limits=i64[3]
tiny_limits[0]=10
tiny_limits[1]=16
tiny_limits[2]=1
tiny_recipe=i64[ffrcl_recipe_size()]
tiny_path=i64[ffrep_recipe_size()]
tiny_stats=i64[ffrcl_stats_size()]
tiny=ffrcl_search(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,shape,tiny_limits,source_aug_u,source_aug_v,source_aug_w,target_aug_u,target_aug_v,target_aug_w,tiny_recipe,tiny_path,tiny_stats) ## i64
if tiny>0
  z=ffrclrt_expect("tiny-arena hit still exact",tiny_stats[11]==1 && tiny_stats[12]==1 && tiny_stats[15]==1)
z=ffrclrt_expect("tiny arena reports capped path trees",tiny_stats[6]==1)

<< "PASS rect_catalyst_lift_rect_test rank="+base_rank.to_s()+" path="+found.to_s()+" candidates="+stats[2].to_s()+" states="+stats[8].to_s()+"/"+stats[9].to_s()+" legal="+stats[10].to_s()+" capped_calls="+stats[6].to_s()+" ms="+elapsed.to_s()+" tiny_found="+tiny.to_s()+" tiny_capped="+tiny_stats[6].to_s()
