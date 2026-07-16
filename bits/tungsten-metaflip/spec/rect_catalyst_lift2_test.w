use ../lib/metaflip/strategies/rect_catalyst_lift2

-> ffrcl2t_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL rectangular catalyst lift-2: "+label
    exit(1)
  1

# Three collinear terms whose U factors XOR to one are an exact 3 -> 1
# replacement.  The source receives a duplicate doublet; the target receives
# the zero line {2,3,6,7}.  The compiler must resolve the equal-rank middle
# word and prove both cleanup directions.
source_u=i64[3];source_v=i64[3];source_w=i64[3]
source_u[0]=2;source_v[0]=2;source_w[0]=2
source_u[1]=4;source_v[1]=2;source_w[1]=2
source_u[2]=7;source_v[2]=2;source_w[2]=2
target_u=i64[1];target_v=i64[1];target_w=i64[1]
target_u[0]=1;target_v[0]=2;target_w[0]=2
shape=i64[3];shape[0]=4;shape[1]=4;shape[2]=4
limits=i64[3];limits[0]=6;limits[1]=4096;limits[2]=64
source_aug_u=i64[5];source_aug_v=i64[5];source_aug_w=i64[5]
target_aug_u=i64[5];target_aug_v=i64[5];target_aug_w=i64[5]
recipe=i64[ffrcl2_recipe_size()]
path_recipe=i64[ffrep_recipe_size()]
stats=i64[ffrcl2_stats_size()]
controls=i64[11]
controls[0]=2;controls[1]=1;controls[2]=2
controls[3]=0;controls[4]=0
controls[5]=2;controls[6]=3;controls[7]=6
controls[8]=1;controls[9]=1;controls[10]=2

z=ffrcl2t_expect("base 3-to-1 exact",ffrep_local_exact_shape(source_u,source_v,source_w,3,target_u,target_v,target_w,1,4,4,4)==1)
found=ffrcl2_compile_explicit(source_u,source_v,source_w,3,target_u,target_v,target_w,1,shape,limits,controls,source_aug_u,source_aug_v,source_aug_w,target_aug_u,target_aug_v,target_aug_w,recipe,path_recipe,stats) ## i64
z=ffrcl2t_expect("catalyst word found",found>0 && stats[15]==1 && recipe[27]==1)
z=ffrcl2t_expect("zero gadgets exact",ffrcl2_line_zero(recipe)==1 && stats[1]>0 && recipe[26]==1)
z=ffrcl2t_expect("forward and undo cleanups",stats[9]==1 && stats[10]==1 && stats[14]==2)

replay_u=i64[5];replay_v=i64[5];replay_w=i64[5];meta=i64[ffrep_replay_meta_size()]
replayed=ffrep_replay_forward(source_aug_u,source_aug_v,source_aug_w,5,target_aug_u,target_aug_v,target_aug_w,5,path_recipe,replay_u,replay_v,replay_w,meta) ## i64
strip_u=i64[3];strip_v=i64[3];strip_w=i64[3]
stripped=ffrcl2_strip_target(replay_u,replay_v,replay_w,replayed,recipe,strip_u,strip_v,strip_w) ## i64
z=ffrcl2t_expect("explicit target strip",stripped==1 && fftc_terms_same_set(strip_u,strip_v,strip_w,1,target_u,target_v,target_w,1)==1)
undone=ffrep_replay_undo(source_aug_u,source_aug_v,source_aug_w,5,target_aug_u,target_aug_v,target_aug_w,5,path_recipe,replay_u,replay_v,replay_w,meta) ## i64
stripped=ffrcl2_strip_source(replay_u,replay_v,replay_w,undone,recipe,strip_u,strip_v,strip_w)
z=ffrcl2t_expect("explicit source strip",stripped==3 && fftc_terms_same_set(strip_u,strip_v,strip_w,3,source_u,source_v,source_w,3)==1)

# Add two untouched spectators to exercise the practical 5 -> 3 envelope used
# by the direct rectangular k-XOR scout.
source5_u=i64[5];source5_v=i64[5];source5_w=i64[5]
target3_u=i64[3];target3_v=i64[3];target3_w=i64[3]
i=0 ## i64
while i<3
  source5_u[i]=source_u[i];source5_v[i]=source_v[i];source5_w[i]=source_w[i]
  i+=1
target3_u[0]=target_u[0];target3_v[0]=target_v[0];target3_w[0]=target_w[0]
source5_u[3]=1;source5_v[3]=1;source5_w[3]=1
source5_u[4]=3;source5_v[4]=3;source5_w[4]=3
target3_u[1]=1;target3_v[1]=1;target3_w[1]=1
target3_u[2]=3;target3_v[2]=3;target3_w[2]=3
source7_u=i64[7];source7_v=i64[7];source7_w=i64[7]
target7_u=i64[7];target7_v=i64[7];target7_w=i64[7]
recipe5=i64[ffrcl2_recipe_size()];path5=i64[ffrep_recipe_size()];stats5=i64[ffrcl2_stats_size()]
found5=ffrcl2_compile_explicit(source5_u,source5_v,source5_w,5,target3_u,target3_v,target3_w,3,shape,limits,controls,source7_u,source7_v,source7_w,target7_u,target7_v,target7_w,recipe5,path5,stats5) ## i64
z=ffrcl2t_expect("five-to-three catalyst word",found5>0 && stats5[15]==1 && stats5[9]==1 && stats5[10]==1)

# The same local algorithm must survive the full direct-scout envelopes. Add
# one and then two more inert spectators, reaching nine simultaneous labels
# for 7 -> 5 without changing the three-edge middle word.
source6_u=i64[6];source6_v=i64[6];source6_w=i64[6]
target4_u=i64[4];target4_v=i64[4];target4_w=i64[4]
i=0
while i<5
  source6_u[i]=source5_u[i];source6_v[i]=source5_v[i];source6_w[i]=source5_w[i]
  i+=1
i=0
while i<3
  target4_u[i]=target3_u[i];target4_v[i]=target3_v[i];target4_w[i]=target3_w[i]
  i+=1
source6_u[5]=5;source6_v[5]=5;source6_w[5]=5
target4_u[3]=5;target4_v[3]=5;target4_w[3]=5
source8_u=i64[8];source8_v=i64[8];source8_w=i64[8]
target8_u=i64[8];target8_v=i64[8];target8_w=i64[8]
recipe6=i64[ffrcl2_recipe_size()];path6=i64[ffrep_recipe_size()];stats6=i64[ffrcl2_stats_size()]
found6=ffrcl2_compile_explicit(source6_u,source6_v,source6_w,6,target4_u,target4_v,target4_w,4,shape,limits,controls,source8_u,source8_v,source8_w,target8_u,target8_v,target8_w,recipe6,path6,stats6) ## i64
z=ffrcl2t_expect("six-to-four catalyst word",found6>0 && recipe6[9]==3 && stats6[15]==1 && stats6[9]==1 && stats6[10]==1)

source7_u=i64[7];source7_v=i64[7];source7_w=i64[7]
target5_u=i64[5];target5_v=i64[5];target5_w=i64[5]
i=0
while i<6
  source7_u[i]=source6_u[i];source7_v[i]=source6_v[i];source7_w[i]=source6_w[i]
  i+=1
i=0
while i<4
  target5_u[i]=target4_u[i];target5_v[i]=target4_v[i];target5_w[i]=target4_w[i]
  i+=1
source7_u[6]=9;source7_v[6]=9;source7_w[6]=9
target5_u[4]=9;target5_v[4]=9;target5_w[4]=9
source9_u=i64[9];source9_v=i64[9];source9_w=i64[9]
target9_u=i64[9];target9_v=i64[9];target9_w=i64[9]
recipe7=i64[ffrcl2_recipe_size()];path7=i64[ffrep_recipe_size()];stats7=i64[ffrcl2_stats_size()]
found7=ffrcl2_compile_explicit(source7_u,source7_v,source7_w,7,target5_u,target5_v,target5_w,5,shape,limits,controls,source9_u,source9_v,source9_w,target9_u,target9_v,target9_w,recipe7,path7,stats7) ## i64
z=ffrcl2t_expect("seven-to-five nine-label word",found7>0 && recipe7[9]==3 && stats7[15]==1 && stats7[9]==1 && stats7[10]==1)

# Enumeration and the resolved word are deterministic.
repeat_source=i64[5];repeat_source_v=i64[5];repeat_source_w=i64[5]
repeat_target=i64[5];repeat_target_v=i64[5];repeat_target_w=i64[5]
repeat_recipe=i64[ffrcl2_recipe_size()];repeat_path=i64[ffrep_recipe_size()];repeat_stats=i64[ffrcl2_stats_size()]
repeated=ffrcl2_compile_explicit(source_u,source_v,source_w,3,target_u,target_v,target_w,1,shape,limits,controls,repeat_source,repeat_source_v,repeat_source_w,repeat_target,repeat_target_v,repeat_target_w,repeat_recipe,repeat_path,repeat_stats) ## i64
z=ffrcl2t_expect("deterministic result",repeated==found && repeat_stats[0]==stats[0] && repeat_stats[5]==stats[5])
i=0
while i<ffrcl2_recipe_size()
  z=ffrcl2t_expect("deterministic recipe "+i.to_s(),repeat_recipe[i]==recipe[i])
  i+=1
i=0
while i<ffrep_recipe_size()
  z=ffrcl2t_expect("deterministic path "+i.to_s(),repeat_path[i]==path_recipe[i])
  i+=1

# Endpoint-first mode must discover the lower-rank target and move word from
# the source alone.  Candidate five in the deterministic source-derived
# catalyst family is the planted V=1 doublet, but the test only depends on an
# independently replayed exact close within the declared finite envelope.
goal_target_u=i64[1];goal_target_v=i64[1];goal_target_w=i64[1]
goal_source_u=i64[5];goal_source_v=i64[5];goal_source_w=i64[5]
goal_aug_u=i64[5];goal_aug_v=i64[5];goal_aug_w=i64[5]
goal_recipe=i64[ffrcl2_recipe_size()]
goal_path=i64[ffrep_recipe_size()]
goal_stats=i64[ffrcl2_goal_stats_size()]
goal_limits=i64[4];goal_limits[0]=4;goal_limits[1]=4096;goal_limits[2]=8;goal_limits[3]=1
goal_found=ffrcl2_goal_search(source_u,source_v,source_w,3,shape,goal_limits,goal_target_u,goal_target_v,goal_target_w,goal_source_u,goal_source_v,goal_source_w,goal_aug_u,goal_aug_v,goal_aug_w,goal_recipe,goal_path,goal_stats) ## i64
z=ffrcl2t_expect("goal search found rank two close",goal_found==1 && goal_stats[13]==1 && goal_recipe[27]==1)
z=ffrcl2t_expect("goal search exact target",ffrep_local_exact_shape(source_u,source_v,source_w,3,goal_target_u,goal_target_v,goal_target_w,1,4,4,4)==1)
z=ffrcl2t_expect("goal search reversible word",goal_stats[10]==1 && goal_stats[11]==1 && ffrcl2_line_zero(goal_recipe)==1)
z=ffrcl2t_expect("goal search bounded telemetry",goal_stats[0]<=8 && goal_stats[1]>0 && goal_stats[18]>0 && goal_stats[7]>=1 && goal_stats[7]<=4)

# A depth-zero, noncollinear control traverses the complete basis/live/XOR
# catalyst family.  Besides proving a bounded negative, this guards every
# ordinal decoder rather than returning on the planted early hit above.
negative_u=i64[3];negative_v=i64[3];negative_w=i64[3]
negative_u[0]=1;negative_v[0]=1;negative_w[0]=1
negative_u[1]=2;negative_v[1]=2;negative_w[1]=2
negative_u[2]=4;negative_v[2]=4;negative_w[2]=4
negative_target_u=i64[1];negative_target_v=i64[1];negative_target_w=i64[1]
negative_source_u=i64[5];negative_source_v=i64[5];negative_source_w=i64[5]
negative_aug_u=i64[5];negative_aug_v=i64[5];negative_aug_w=i64[5]
negative_recipe=i64[ffrcl2_recipe_size()];negative_path=i64[ffrep_recipe_size()];negative_stats=i64[ffrcl2_goal_stats_size()]
negative_limits=i64[4];negative_limits[0]=0;negative_limits[1]=16;negative_limits[2]=4096;negative_limits[3]=0
negative_found=ffrcl2_goal_search(negative_u,negative_v,negative_w,3,shape,negative_limits,negative_target_u,negative_target_v,negative_target_w,negative_source_u,negative_source_v,negative_source_w,negative_aug_u,negative_aug_v,negative_aug_w,negative_recipe,negative_path,negative_stats) ## i64
z=ffrcl2t_expect("complete catalyst family negative",negative_found==0 && negative_stats[13]==0 && negative_stats[0]>20 && negative_stats[0]==negative_stats[1])

<< "PASS rect_catalyst_lift2_test paths="+recipe[9].to_s()+","+recipe5[9].to_s()+","+recipe6[9].to_s()+","+recipe7[9].to_s()+" goal="+goal_stats[14].to_s()+"/"+goal_stats[15].to_s()+"@"+goal_stats[7].to_s()+" family="+negative_stats[0].to_s()+" states9="+stats7[6].to_s()+"/"+stats7[7].to_s()
