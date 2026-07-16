use ../lib/metaflip/strategies/rect_catalyst_lift

-> ffrclt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL rectangular catalyst lift: " + label
    exit(1)
  1

source_u=i64[2]
source_v=i64[2]
source_w=i64[2]
source_u[0]=2
source_v[0]=2
source_w[0]=2
source_u[1]=3
source_v[1]=2
source_w[1]=2
target_u=i64[1]
target_v=i64[1]
target_w=i64[1]
target_u[0]=1
target_v[0]=2
target_w[0]=2
shape=i64[3]
shape[0]=10
shape[1]=30
shape[2]=12
limits=i64[3]
limits[0]=4
limits[1]=256
limits[2]=8
source_aug_u=i64[4]
source_aug_v=i64[4]
source_aug_w=i64[4]
target_aug_u=i64[4]
target_aug_v=i64[4]
target_aug_w=i64[4]
recipe=i64[ffrcl_recipe_size()]
path_recipe=i64[ffrep_recipe_size()]
stats=i64[ffrcl_stats_size()]
found=ffrcl_search(source_u,source_v,source_w,2,target_u,target_v,target_w,1,shape,limits,source_aug_u,source_aug_v,source_aug_w,target_aug_u,target_aug_v,target_aug_w,recipe,path_recipe,stats) ## i64
z=ffrclt_expect("two-to-one catalyst word",found==2 && stats[15]==1 && recipe[9]==2)
z=ffrclt_expect("base and lifted exact gates",stats[13]==1 && stats[3]>0)
z=ffrclt_expect("forward and undo strip gates",stats[11]==1 && stats[12]==1)
z=ffrclt_expect("source is a canceling doublet lift",source_aug_u[2]==source_aug_u[3] && source_aug_v[2]==source_aug_v[3] && source_aug_w[2]==source_aug_w[3])
z=ffrclt_expect("target is a zero triangle lift",ffrcl_triangle_zero(recipe)==1)
z=ffrclt_expect("source lift shape exact",ffrep_local_exact_shape(source_u,source_v,source_w,2,source_aug_u,source_aug_v,source_aug_w,4,shape[0],shape[1],shape[2])==1)
z=ffrclt_expect("target lift shape exact",ffrep_local_exact_shape(target_u,target_v,target_w,1,target_aug_u,target_aug_v,target_aug_w,4,shape[0],shape[1],shape[2])==1)

replay_u=i64[4]
replay_v=i64[4]
replay_w=i64[4]
replay_meta=i64[ffrep_replay_meta_size()]
replayed=ffrep_replay_forward(source_aug_u,source_aug_v,source_aug_w,4,target_aug_u,target_aug_v,target_aug_w,4,path_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
stripped_u=i64[2]
stripped_v=i64[2]
stripped_w=i64[2]
stripped=ffrcl_strip_target(replay_u,replay_v,replay_w,replayed,recipe,stripped_u,stripped_v,stripped_w) ## i64
z=ffrclt_expect("explicit forward strip",stripped==1 && fftc_terms_same_set(stripped_u,stripped_v,stripped_w,1,target_u,target_v,target_w,1)==1)
undone=ffrep_replay_undo(source_aug_u,source_aug_v,source_aug_w,4,target_aug_u,target_aug_v,target_aug_w,4,path_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
stripped=ffrcl_strip_source(replay_u,replay_v,replay_w,undone,recipe,stripped_u,stripped_v,stripped_w)
z=ffrclt_expect("explicit undo strip",stripped==2 && fftc_terms_same_set(stripped_u,stripped_v,stripped_w,2,source_u,source_v,source_w,2)==1)

# Repeat byte-for-byte to pin enumeration and endpoint-word determinism.
repeat_source_u=i64[4];repeat_source_v=i64[4];repeat_source_w=i64[4]
repeat_target_u=i64[4];repeat_target_v=i64[4];repeat_target_w=i64[4]
repeat_recipe=i64[ffrcl_recipe_size()]
repeat_path=i64[ffrep_recipe_size()]
repeat_stats=i64[ffrcl_stats_size()]
repeated=ffrcl_search(source_u,source_v,source_w,2,target_u,target_v,target_w,1,shape,limits,repeat_source_u,repeat_source_v,repeat_source_w,repeat_target_u,repeat_target_v,repeat_target_w,repeat_recipe,repeat_path,repeat_stats) ## i64
z=ffrclt_expect("deterministic result",repeated==found && repeat_stats[2]==stats[2] && repeat_stats[8]==stats[8] && repeat_stats[9]==stats[9])
i=0 ## i64
while i<ffrcl_recipe_size()
  z=ffrclt_expect("deterministic lift recipe "+i.to_s(),repeat_recipe[i]==recipe[i])
  i+=1
i=0
while i<ffrep_recipe_size()
  z=ffrclt_expect("deterministic path recipe "+i.to_s(),repeat_path[i]==path_recipe[i])
  i+=1

# The known gadget requires two flips. A depth-one/candidate-one run is a
# clean bounded miss and reports exhaustion of its catalyst budget.
short_limits=i64[3]
short_limits[0]=1
short_limits[1]=64
short_limits[2]=1
short_recipe=i64[ffrcl_recipe_size()]
short_path=i64[ffrep_recipe_size()]
short_stats=i64[ffrcl_stats_size()]
short=ffrcl_search(source_u,source_v,source_w,2,target_u,target_v,target_w,1,shape,short_limits,source_aug_u,source_aug_v,source_aug_w,target_aug_u,target_aug_v,target_aug_w,short_recipe,short_path,short_stats) ## i64
z=ffrclt_expect("bounded depth miss",short==0 && short_stats[2]==1 && short_stats[14]==1 && short_stats[15]==0)

bad_target_u=i64[1]
bad_target_v=i64[1]
bad_target_w=i64[1]
bad_target_u[0]=5
bad_target_v[0]=2
bad_target_w[0]=2
bad_stats=i64[ffrcl_stats_size()]
bad=ffrcl_search(source_u,source_v,source_w,2,bad_target_u,bad_target_v,bad_target_w,1,shape,limits,source_aug_u,source_aug_v,source_aug_w,target_aug_u,target_aug_v,target_aug_w,short_recipe,short_path,bad_stats) ## i64
z=ffrclt_expect("inequivalent replacement rejected",bad==0 && bad_stats[13]==0)

# Nine-label envelope: a 7 -> 6 replacement has the same merge plus five
# unchanged spectators. This is the cardinality emitted by the 7 -> 6
# rectangular k-XOR scout; the lifted compiler must still find, replay, and
# undo the two-flip word.
source7_u=i64[7];source7_v=i64[7];source7_w=i64[7]
target6_u=i64[6];target6_v=i64[6];target6_w=i64[6]
source7_u[0]=2;source7_v[0]=2;source7_w[0]=2
source7_u[1]=3;source7_v[1]=2;source7_w[1]=2
target6_u[0]=1;target6_v[0]=2;target6_w[0]=2
i=0
while i<5
  spectator=1<<(i+2) ## i64
  source7_u[i+2]=spectator
  source7_v[i+2]=spectator
  source7_w[i+2]=spectator
  target6_u[i+1]=spectator
  target6_v[i+1]=spectator
  target6_w[i+1]=spectator
  i+=1
source9_u=i64[9];source9_v=i64[9];source9_w=i64[9]
target9_u=i64[9];target9_v=i64[9];target9_w=i64[9]
recipe9=i64[ffrcl_recipe_size()]
path9=i64[ffrep_recipe_size()]
stats9=i64[ffrcl_stats_size()]
found9=ffrcl_search(source7_u,source7_v,source7_w,7,target6_u,target6_v,target6_w,6,shape,limits,source9_u,source9_v,source9_w,target9_u,target9_v,target9_w,recipe9,path9,stats9) ## i64
z=ffrclt_expect("seven-to-six nine-label word",found9==2 && recipe9[1]==7 && recipe9[2]==6 && stats9[15]==1)
z=ffrclt_expect("nine-label forward and undo gates",stats9[3]>0 && stats9[11]==1 && stats9[12]==1)
replay9_u=i64[9];replay9_v=i64[9];replay9_w=i64[9];replay9_meta=i64[ffrep_replay_meta_size()]
replayed9=ffrep_replay_forward(source9_u,source9_v,source9_w,9,target9_u,target9_v,target9_w,9,path9,replay9_u,replay9_v,replay9_w,replay9_meta) ## i64
stripped7_u=i64[7];stripped7_v=i64[7];stripped7_w=i64[7]
stripped9=ffrcl_strip_target(replay9_u,replay9_v,replay9_w,replayed9,recipe9,stripped7_u,stripped7_v,stripped7_w) ## i64
z=ffrclt_expect("nine-label strip",stripped9==6 && fftc_terms_same_set(stripped7_u,stripped7_v,stripped7_w,6,target6_u,target6_v,target6_w,6)==1)

<< "PASS rect_catalyst_lift_test path="+found.to_s()+" path7="+found9.to_s()+" candidates="+stats[2].to_s()+" states="+stats[8].to_s()+"/"+stats[9].to_s()+" legal="+stats[10].to_s()
