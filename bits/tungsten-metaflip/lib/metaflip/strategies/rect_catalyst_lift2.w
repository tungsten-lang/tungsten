# Offline catalyst lift for a known exact q -> q-2 rectangular replacement.
#
# A fixed-rank ordinary-flip word cannot connect term lists whose cardinality
# differs by two.  Add zero tensors of different labelled sizes:
#
#   source: C + C                                  (two labels)
#   target: X(a) + X(b) + X(c) + X(a^b^c)          (four labels)
#
# The four target terms share two factors, so their XOR is zero on the third
# axis.  Source q+2 and target (q-2)+4 therefore have equal cardinality and the
# endpoint BFS can compile a state-dependent word between them.  Forward
# replay strips the four-term line; undo strips the source doublet.
#
# This is a genuine Rubik-style catalyst: the extra labels are temporary setup
# debt chosen to make a requested endpoint reachable.  It remains offline and
# bounded to q<=7, hence at most nine simultaneous labels.
#
# Recipe (28 words):
#   0 version (=2), 1 source q, 2 target q-2,
#   3 source catalyst index, 4 target anchor/endpoint node, 5 line axis,
#   6/7/8 line factors b/c/d, 9 middle path length,
#   10..12 source catalyst triple,
#   13..24 four target line triples,
#   25 candidate ordinal, 26 input/lift exact, 27 success.
# Stats (16 words):
#   0 candidates, 1 exact lifts, 2 path calls, 3 path hits,
#   4 capped calls, 5 retained path length, 6/7 forward/back states,
#   8 legal edges, 9 forward strip/replay, 10 undo strip/replay,
#   11 input local exact, 12 candidate cap reached, 13 zero-path hit,
#   14 final local gates, 15 success.

use rect_catalyst_lift

-> ffrcl2_recipe_size() i64
  28

-> ffrcl2_stats_size() i64
  16

-> ffrcl2_goal_stats_size() i64
  20

# Locate a nondegenerate four-term projective line in one canonical state.
# The four terms share two factors and have four distinct nonzero factors on
# the remaining axis whose XOR is zero.
-> ffrcl2_find_line(us, vs, ws, offset, count, line) (i64[] i64[] i64[] i64 i64 i64[]) i64
  if line.size() < 5 || count < 4
    return 0
  a=0 ## i64
  while a<count-3
    b=a+1 ## i64
    while b<count-2
      c=b+1 ## i64
      while c<count-1
        d=c+1 ## i64
        while d<count
          axis=0 ## i64
          while axis<3
            ok=1 ## i64
            other=0 ## i64
            while other<3
              if other != axis
                va=us[offset+a] ## i64
                vb=us[offset+b] ## i64
                vc=us[offset+c] ## i64
                vd=us[offset+d] ## i64
                if other==1
                  va=vs[offset+a]
                  vb=vs[offset+b]
                  vc=vs[offset+c]
                  vd=vs[offset+d]
                if other==2
                  va=ws[offset+a]
                  vb=ws[offset+b]
                  vc=ws[offset+c]
                  vd=ws[offset+d]
                if va != vb || va != vc || va != vd
                  ok=0
              other+=1
            fa=us[offset+a] ## i64
            fb=us[offset+b] ## i64
            fc=us[offset+c] ## i64
            fd=us[offset+d] ## i64
            if axis==1
              fa=vs[offset+a]
              fb=vs[offset+b]
              fc=vs[offset+c]
              fd=vs[offset+d]
            if axis==2
              fa=ws[offset+a]
              fb=ws[offset+b]
              fc=ws[offset+c]
              fd=ws[offset+d]
            if (fa^fb^fc^fd) != 0 || fa==fb || fa==fc || fa==fd || fb==fc || fb==fd || fc==fd
              ok=0
            if ok==1
              line[0]=a
              line[1]=b
              line[2]=c
              line[3]=d
              line[4]=axis
              return 1
            axis+=1
          d+=1
        c+=1
      b+=1
    a+=1
  0

-> ffrcl2_copy_without_line(us, vs, ws, offset, count, line, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  out_count=0 ## i64
  i=0 ## i64
  while i<count
    removed=0 ## i64
    j=0 ## i64
    while j<4
      if i==line[j]
        removed=1
      j+=1
    if removed==0
      out_u[out_count]=us[offset+i]
      out_v[out_count]=vs[offset+i]
      out_w[out_count]=ws[offset+i]
      out_count+=1
    i+=1
  out_count

-> ffrcl2_terms_unique(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  i=0 ## i64
  while i<count-1
    j=i+1 ## i64
    while j<count
      if us[i]==us[j] && vs[i]==vs[j] && ws[i]==ws[j]
        return 0
      j+=1
    i+=1
  1

-> ffrcl2_path_from_tree(states_u, states_v, states_w, parents, depths, node, count, udim, vdim, wdim, path_recipe) (i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[]) i64
  depth=depths[node] ## i64
  if depth<0 || depth>ffrep_max_depth() || path_recipe.size()<ffrep_recipe_size()
    return 0
  chain=i64[depth+1]
  pos=depth ## i64
  current=node ## i64
  while pos>=0
    chain[pos]=current
    current=parents[current]
    pos-=1
  if chain[0] != 0
    return 0
  z=ffrep_fill(path_recipe,ffrep_recipe_size(),0-1) ## i64
  path_recipe[0]=1
  path_recipe[1]=0
  path_recipe[2]=count
  path_recipe[3]=count
  path_recipe[4]=depth
  path_recipe[5]=udim
  path_recipe[6]=vdim
  path_recipe[7]=wdim
  step=0 ## i64
  while step<depth
    forward=ffrep_find_transition(states_u,states_v,states_w,chain[step]*count,states_u,states_v,states_w,chain[step+1]*count,count) ## i64
    reverse=ffrep_find_transition(states_u,states_v,states_w,chain[depth-step]*count,states_u,states_v,states_w,chain[depth-step-1]*count,count) ## i64
    if forward<0 || reverse<0
      return 0
    path_recipe[8+step]=forward
    path_recipe[18+step]=reverse
    step+=1
  depth

-> ffrcl2_line_zero(recipe) (i64[]) i64
  if recipe.size() < ffrcl2_recipe_size()
    return 0
  axis = recipe[5] ## i64
  if axis < 0 || axis > 2
    return 0
  i = 0 ## i64
  factor_xor = 0 ## i64
  while i < 4
    base = 13 + i*3 ## i64
    if recipe[base] <= 0 || recipe[base+1] <= 0 || recipe[base+2] <= 0
      return 0
    factor_xor = factor_xor ^ recipe[base+axis]
    if i > 0
      other = 0 ## i64
      while other < 3
        if other != axis && recipe[base+other] != recipe[13+other]
          return 0
        other += 1
    i += 1
  if factor_xor != 0
    return 0
  1

-> ffrcl2_strip_source(aug_u, aug_v, aug_w, aug_count, recipe, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  if recipe.size() < ffrcl2_recipe_size() || recipe[0] != 2 || aug_count != recipe[1]+2
    return 0
  scratch_u=i64[aug_count];scratch_v=i64[aug_count];scratch_w=i64[aug_count]
  z=ffrep_copy_slot(aug_u,aug_v,aug_w,0,aug_count,scratch_u,scratch_v,scratch_w,0) ## i64
  count=ffrcl_remove_once(scratch_u,scratch_v,scratch_w,aug_count,recipe[10],recipe[11],recipe[12]) ## i64
  if count < 0
    return 0
  count=ffrcl_remove_once(scratch_u,scratch_v,scratch_w,count,recipe[10],recipe[11],recipe[12])
  if count != recipe[1] || out_u.size()<count || out_v.size()<count || out_w.size()<count
    return 0
  z=ffrep_sort_slot(scratch_u,scratch_v,scratch_w,0,count)
  z=ffrep_copy_slot(scratch_u,scratch_v,scratch_w,0,count,out_u,out_v,out_w,0)
  count

-> ffrcl2_strip_target(aug_u, aug_v, aug_w, aug_count, recipe, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  if recipe.size() < ffrcl2_recipe_size() || recipe[0] != 2 || aug_count != recipe[2]+4 || ffrcl2_line_zero(recipe)==0
    return 0
  scratch_u=i64[aug_count];scratch_v=i64[aug_count];scratch_w=i64[aug_count]
  z=ffrep_copy_slot(aug_u,aug_v,aug_w,0,aug_count,scratch_u,scratch_v,scratch_w,0) ## i64
  count=aug_count ## i64
  i=0 ## i64
  while i<4
    base=13+i*3 ## i64
    count=ffrcl_remove_once(scratch_u,scratch_v,scratch_w,count,recipe[base],recipe[base+1],recipe[base+2])
    if count<0
      return 0
    i+=1
  if count != recipe[2] || out_u.size()<count || out_v.size()<count || out_w.size()<count
    return 0
  z=ffrep_sort_slot(scratch_u,scratch_v,scratch_w,0,count)
  z=ffrep_copy_slot(scratch_u,scratch_v,scratch_w,0,count,out_u,out_v,out_w,0)
  count

-> ffrcl2_identity_recipe(count, udim, vdim, wdim, recipe) (i64 i64 i64 i64 i64[]) i64
  z=ffrep_fill(recipe,ffrep_recipe_size(),0-1) ## i64
  recipe[0]=1
  recipe[1]=0
  recipe[2]=count
  recipe[3]=count
  recipe[4]=0
  recipe[5]=udim
  recipe[6]=vdim
  recipe[7]=wdim
  1

-> ffrcl2_search(source_u, source_v, source_w, source_count, target_u, target_v, target_w, target_count, shape, limits, source_aug_u, source_aug_v, source_aug_w, target_aug_u, target_aug_v, target_aug_w, recipe, path_recipe, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if source_count<3 || source_count>7 || target_count != source_count-2 || target_count<1
    return 0
  if shape.size()<3 || limits.size()<3 || recipe.size()<ffrcl2_recipe_size() || path_recipe.size()<ffrep_recipe_size() || stats.size()<ffrcl2_stats_size()
    return 0
  aug_count=source_count+2 ## i64
  if aug_count>ffrep_max_count() || source_aug_u.size()<aug_count || source_aug_v.size()<aug_count || source_aug_w.size()<aug_count || target_aug_u.size()<aug_count || target_aug_v.size()<aug_count || target_aug_w.size()<aug_count
    return 0
  udim=shape[0] ## i64
  vdim=shape[1] ## i64
  wdim=shape[2] ## i64
  max_depth=limits[0] ## i64
  node_cap=limits[1] ## i64
  candidate_cap=limits[2] ## i64
  if max_depth<1 || max_depth>ffrep_max_depth() || node_cap<16 || node_cap>65536 || candidate_cap<1 || candidate_cap>4096
    return 0
  z=ffrep_fill(recipe,ffrcl2_recipe_size(),0-1) ## i64
  z=ffrep_fill(path_recipe,ffrep_recipe_size(),0-1)
  z=ffrep_clear(stats,ffrcl2_stats_size())
  if ffrep_local_exact_shape(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,udim,vdim,wdim) != 1
    return 0
  stats[11]=1

  found=0 ## i64
  attempts=0 ## i64
  catalyst=0 ## i64
  while catalyst<source_count && found==0 && attempts<candidate_cap
    anchor=0 ## i64
    while anchor<target_count && found==0 && attempts<candidate_cap
      axis=0 ## i64
      while axis<3 && found==0 && attempts<candidate_cap
        width=udim ## i64
        if axis==1
          width=vdim
        if axis==2
          width=wdim
        a=ffrcl_axis_get(target_u,target_v,target_w,anchor,axis) ## i64
        bbit=0 ## i64
        while bbit<width && found==0 && attempts<candidate_cap
          b=1<<bbit ## i64
          cbit=bbit+1 ## i64
          while cbit<width && found==0 && attempts<candidate_cap
            c=1<<cbit ## i64
            d=a^b^c ## i64
            if a > 0 && b > 0 && c > 0 && d > 0 && a != b && a != c && a != d && b != c && b != d && c != d
              attempts+=1
              stats[0]+=1
              z=ffrep_copy_slot(source_u,source_v,source_w,0,source_count,source_aug_u,source_aug_v,source_aug_w,0)
              source_aug_u[source_count]=source_u[catalyst]
              source_aug_v[source_count]=source_v[catalyst]
              source_aug_w[source_count]=source_w[catalyst]
              source_aug_u[source_count+1]=source_u[catalyst]
              source_aug_v[source_count+1]=source_v[catalyst]
              source_aug_w[source_count+1]=source_w[catalyst]
              z=ffrep_copy_slot(target_u,target_v,target_w,0,target_count,target_aug_u,target_aug_v,target_aug_w,0)
              factors=i64[4]
              factors[0]=a
              factors[1]=b
              factors[2]=c
              factors[3]=d
              li=0 ## i64
              while li<4
                slot=target_count+li ## i64
                target_aug_u[slot]=target_u[anchor]
                target_aug_v[slot]=target_v[anchor]
                target_aug_w[slot]=target_w[anchor]
                z=ffrcl_axis_set(target_aug_u,target_aug_v,target_aug_w,slot,axis,factors[li])
                li+=1
              lift_exact=ffrep_local_exact_shape(source_u,source_v,source_w,source_count,source_aug_u,source_aug_v,source_aug_w,aug_count,udim,vdim,wdim) ## i64
              if lift_exact==1
                lift_exact=ffrep_local_exact_shape(target_u,target_v,target_w,target_count,target_aug_u,target_aug_v,target_aug_w,aug_count,udim,vdim,wdim)
              if lift_exact==1
                lift_exact=ffrep_local_exact_shape(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count,udim,vdim,wdim)
              if lift_exact==1
                stats[1]+=1
                trial_recipe=i64[ffrep_recipe_size()]
                trial_stats=i64[ffrep_stats_size()]
                same=fftc_terms_same_set(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count) ## i64
                trial=0 ## i64
                if same==1
                  z=ffrcl2_identity_recipe(aug_count,udim,vdim,wdim,trial_recipe)
                  stats[13]+=1
                if same==0
                  stats[2]+=1
                  trial=ffrep_search_same_rank(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count,udim,vdim,wdim,max_depth,node_cap,trial_recipe,trial_stats)
                  if trial_stats[10] != 0
                    stats[4]+=1
                if same==1 || trial>0
                  recipe[0]=2
                  recipe[1]=source_count
                  recipe[2]=target_count
                  recipe[3]=catalyst
                  recipe[4]=anchor
                  recipe[5]=axis
                  recipe[6]=b
                  recipe[7]=c
                  recipe[8]=d
                  recipe[9]=trial
                  recipe[10]=source_u[catalyst]
                  recipe[11]=source_v[catalyst]
                  recipe[12]=source_w[catalyst]
                  li=0
                  while li<4
                    recipe[13+li*3]=target_aug_u[target_count+li]
                    recipe[14+li*3]=target_aug_v[target_count+li]
                    recipe[15+li*3]=target_aug_w[target_count+li]
                    li+=1
                  recipe[25]=attempts
                  recipe[26]=1
                  pi=0 ## i64
                  while pi<ffrep_recipe_size()
                    path_recipe[pi]=trial_recipe[pi]
                    pi+=1
                  replay_u=i64[aug_count];replay_v=i64[aug_count];replay_w=i64[aug_count];replay_meta=i64[ffrep_replay_meta_size()]
                  replayed=ffrep_replay_forward(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count,path_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
                  stripped_u=i64[source_count];stripped_v=i64[source_count];stripped_w=i64[source_count]
                  stripped=0 ## i64
                  if replayed==aug_count
                    stripped=ffrcl2_strip_target(replay_u,replay_v,replay_w,aug_count,recipe,stripped_u,stripped_v,stripped_w)
                  if stripped==target_count && fftc_terms_same_set(stripped_u,stripped_v,stripped_w,stripped,target_u,target_v,target_w,target_count)==1 && ffrep_local_exact_shape(source_u,source_v,source_w,source_count,stripped_u,stripped_v,stripped_w,stripped,udim,vdim,wdim)==1
                    stats[9]=1
                    stats[14]+=1
                  undone=ffrep_replay_undo(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count,path_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
                  stripped=0
                  if undone==aug_count
                    stripped=ffrcl2_strip_source(replay_u,replay_v,replay_w,aug_count,recipe,stripped_u,stripped_v,stripped_w)
                  if stripped==source_count && fftc_terms_same_set(stripped_u,stripped_v,stripped_w,stripped,source_u,source_v,source_w,source_count)==1 && ffrep_local_exact_shape(target_u,target_v,target_w,target_count,stripped_u,stripped_v,stripped_w,stripped,udim,vdim,wdim)==1
                    stats[10]=1
                    stats[14]+=1
                  if stats[9]==1 && stats[10]==1
                    stats[3]+=1
                    stats[5]=trial
                    stats[6]=trial_stats[0]
                    stats[7]=trial_stats[1]
                    stats[8]=trial_stats[4]
                    stats[15]=1
                    recipe[27]=1
                    found=trial+1
            cbit+=1
          bbit+=1
        axis+=1
      anchor+=1
    catalyst+=1
  if found==0 && attempts>=candidate_cap
    stats[12]=1
  found

# Compile one caller-supplied catalyst and four-line cleanup.  This is the
# endpoint-first entry point used when a goal search has already identified a
# promising line; the bounded enumerator above remains a convenience family,
# not a completeness claim.
-> ffrcl2_compile_explicit(source_u, source_v, source_w, source_count, target_u, target_v, target_w, target_count, shape, limits, controls, source_aug_u, source_aug_v, source_aug_w, target_aug_u, target_aug_v, target_aug_w, recipe, path_recipe, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if controls.size() < 11
    return 0
  catalyst_u=controls[0] ## i64
  catalyst_v=controls[1] ## i64
  catalyst_w=controls[2] ## i64
  anchor=controls[3] ## i64
  line_axis=controls[4] ## i64
  line_a=controls[5] ## i64
  line_b=controls[6] ## i64
  line_c=controls[7] ## i64
  line_template_u=controls[8] ## i64
  line_template_v=controls[9] ## i64
  line_template_w=controls[10] ## i64
  if source_count < 3 || source_count > 7 || target_count != source_count-2 || target_count < 1 || anchor < 0 || anchor >= target_count || line_axis < 0 || line_axis > 2
    return 0
  if shape.size()<3 || limits.size()<2 || recipe.size()<ffrcl2_recipe_size() || path_recipe.size()<ffrep_recipe_size() || stats.size()<ffrcl2_stats_size()
    return 0
  aug_count=source_count+2 ## i64
  if aug_count>ffrep_max_count() || source_aug_u.size()<aug_count || source_aug_v.size()<aug_count || source_aug_w.size()<aug_count || target_aug_u.size()<aug_count || target_aug_v.size()<aug_count || target_aug_w.size()<aug_count
    return 0
  udim=shape[0] ## i64
  vdim=shape[1] ## i64
  wdim=shape[2] ## i64
  max_depth=limits[0] ## i64
  node_cap=limits[1] ## i64
  if max_depth<1 || max_depth>ffrep_max_depth() || node_cap<16 || node_cap>65536
    return 0
  line_d=line_a^line_b^line_c ## i64
  width=udim ## i64
  if line_axis==1
    width=vdim
  if line_axis==2
    width=wdim
  if catalyst_u<=0 || catalyst_v<=0 || catalyst_w<=0 || ffrep_factor_fits(catalyst_u,udim)==0 || ffrep_factor_fits(catalyst_v,vdim)==0 || ffrep_factor_fits(catalyst_w,wdim)==0
    return 0
  if ffrep_factor_fits(line_template_u,udim)==0 || ffrep_factor_fits(line_template_v,vdim)==0 || ffrep_factor_fits(line_template_w,wdim)==0
    return 0
  if line_a<=0 || line_b<=0 || line_c<=0 || line_d<=0 || ffrep_factor_fits(line_a,width)==0 || ffrep_factor_fits(line_b,width)==0 || ffrep_factor_fits(line_c,width)==0 || ffrep_factor_fits(line_d,width)==0
    return 0
  if line_a==line_b || line_a==line_c || line_a==line_d || line_b==line_c || line_b==line_d || line_c==line_d
    return 0
  z=ffrep_fill(recipe,ffrcl2_recipe_size(),0-1) ## i64
  z=ffrep_fill(path_recipe,ffrep_recipe_size(),0-1)
  z=ffrep_clear(stats,ffrcl2_stats_size())
  if ffrep_local_exact_shape(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,udim,vdim,wdim) != 1
    return 0
  stats[11]=1
  stats[0]=1
  z=ffrep_copy_slot(source_u,source_v,source_w,0,source_count,source_aug_u,source_aug_v,source_aug_w,0)
  source_aug_u[source_count]=catalyst_u
  source_aug_v[source_count]=catalyst_v
  source_aug_w[source_count]=catalyst_w
  source_aug_u[source_count+1]=catalyst_u
  source_aug_v[source_count+1]=catalyst_v
  source_aug_w[source_count+1]=catalyst_w
  z=ffrep_copy_slot(target_u,target_v,target_w,0,target_count,target_aug_u,target_aug_v,target_aug_w,0)
  factors=i64[4]
  factors[0]=line_a
  factors[1]=line_b
  factors[2]=line_c
  factors[3]=line_d
  li=0 ## i64
  while li<4
    slot=target_count+li ## i64
    target_aug_u[slot]=line_template_u
    target_aug_v[slot]=line_template_v
    target_aug_w[slot]=line_template_w
    z=ffrcl_axis_set(target_aug_u,target_aug_v,target_aug_w,slot,line_axis,factors[li])
    li+=1
  lift_exact=ffrep_local_exact_shape(source_u,source_v,source_w,source_count,source_aug_u,source_aug_v,source_aug_w,aug_count,udim,vdim,wdim) ## i64
  if lift_exact==1
    lift_exact=ffrep_local_exact_shape(target_u,target_v,target_w,target_count,target_aug_u,target_aug_v,target_aug_w,aug_count,udim,vdim,wdim)
  if lift_exact==1
    lift_exact=ffrep_local_exact_shape(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count,udim,vdim,wdim)
  if lift_exact != 1
    return 0
  stats[1]=1
  same=fftc_terms_same_set(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count) ## i64
  trial=0 ## i64
  trial_stats=i64[ffrep_stats_size()]
  if same==1
    z=ffrcl2_identity_recipe(aug_count,udim,vdim,wdim,path_recipe)
    stats[13]=1
  if same==0
    stats[2]=1
    trial=ffrep_search_same_rank(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count,udim,vdim,wdim,max_depth,node_cap,path_recipe,trial_stats)
    if trial_stats[10] != 0
      stats[4]=1
    if trial<1
      return 0
  recipe[0]=2
  recipe[1]=source_count
  recipe[2]=target_count
  recipe[3]=0-1
  recipe[4]=anchor
  recipe[5]=line_axis
  recipe[6]=line_b
  recipe[7]=line_c
  recipe[8]=line_d
  recipe[9]=trial
  recipe[10]=catalyst_u
  recipe[11]=catalyst_v
  recipe[12]=catalyst_w
  li=0
  while li<4
    recipe[13+li*3]=target_aug_u[target_count+li]
    recipe[14+li*3]=target_aug_v[target_count+li]
    recipe[15+li*3]=target_aug_w[target_count+li]
    li+=1
  recipe[25]=1
  recipe[26]=1
  replay_u=i64[aug_count];replay_v=i64[aug_count];replay_w=i64[aug_count];replay_meta=i64[ffrep_replay_meta_size()]
  replayed=ffrep_replay_forward(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count,path_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
  stripped_u=i64[source_count];stripped_v=i64[source_count];stripped_w=i64[source_count]
  stripped=0 ## i64
  if replayed==aug_count
    stripped=ffrcl2_strip_target(replay_u,replay_v,replay_w,aug_count,recipe,stripped_u,stripped_v,stripped_w)
  if stripped==target_count && fftc_terms_same_set(stripped_u,stripped_v,stripped_w,stripped,target_u,target_v,target_w,target_count)==1 && ffrep_local_exact_shape(source_u,source_v,source_w,source_count,stripped_u,stripped_v,stripped_w,stripped,udim,vdim,wdim)==1
    stats[9]=1
    stats[14]+=1
  undone=ffrep_replay_undo(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count,path_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
  stripped=0
  if undone==aug_count
    stripped=ffrcl2_strip_source(replay_u,replay_v,replay_w,aug_count,recipe,stripped_u,stripped_v,stripped_w)
  if stripped==source_count && fftc_terms_same_set(stripped_u,stripped_v,stripped_w,stripped,source_u,source_v,source_w,source_count)==1 && ffrep_local_exact_shape(target_u,target_v,target_w,target_count,stripped_u,stripped_v,stripped_w,stripped,udim,vdim,wdim)==1
    stats[10]=1
    stats[14]+=1
  if stats[9] != 1 || stats[10] != 1
    return 0
  stats[3]=1
  stats[5]=trial
  stats[6]=trial_stats[0]
  stats[7]=trial_stats[1]
  stats[8]=trial_stats[4]
  stats[15]=1
  recipe[27]=1
  trial+1

# Search for the endpoint instead of requiring the q -> q-2 replacement in
# advance.  Each source-derived catalyst adds a cancelling doublet, one BFS
# tree enumerates the fixed-cardinality orbit, and every visited state is
# scanned for a removable four-term zero line.  A hit therefore supplies both
# the lower-rank target and the exact setup/trigger/cleanup word.
#
# Limits: maximum depth, node cap per catalyst, catalyst candidate cap, and
# optional minimum endpoint depth (zero by default).  A positive minimum lets
# experiments exclude direct gadget cleanup and measure genuine middle words.
# Goal stats (20 words):
#   0 catalysts, 1 total states, 2 codes, 3 legal, 4 revisits,
#   5 zero lines, 6 exact closes, 7 retained depth, 8 target rank,
#   9 density improvement, 10 forward replay, 11 undo replay,
#   12 capped trees, 13 success, 14 catalyst ordinal, 15 endpoint node,
#   16 input fit, 17 largest tree, 18 states scanned, 19 unique target.
-> ffrcl2_goal_search(source_u, source_v, source_w, source_count, shape, limits, target_u, target_v, target_w, source_aug_u, source_aug_v, source_aug_w, target_aug_u, target_aug_v, target_aug_w, recipe, path_recipe, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if source_count<3 || source_count>7 || shape.size()<3 || limits.size()<3
    return 0
  target_count=source_count-2 ## i64
  aug_count=source_count+2 ## i64
  if target_u.size()<target_count || target_v.size()<target_count || target_w.size()<target_count
    return 0
  if source_aug_u.size()<aug_count || source_aug_v.size()<aug_count || source_aug_w.size()<aug_count || target_aug_u.size()<aug_count || target_aug_v.size()<aug_count || target_aug_w.size()<aug_count
    return 0
  if recipe.size()<ffrcl2_recipe_size() || path_recipe.size()<ffrep_recipe_size() || stats.size()<ffrcl2_goal_stats_size()
    return 0
  udim=shape[0] ## i64
  vdim=shape[1] ## i64
  wdim=shape[2] ## i64
  max_depth=limits[0] ## i64
  node_cap=limits[1] ## i64
  candidate_cap=limits[2] ## i64
  min_depth=0 ## i64
  if limits.size()>3
    min_depth=limits[3]
  if max_depth<0 || max_depth>ffrep_max_depth() || min_depth<0 || min_depth>max_depth || node_cap<16 || node_cap>65536 || candidate_cap<1 || candidate_cap>4096
    return 0
  z=ffrep_fill(recipe,ffrcl2_recipe_size(),0-1) ## i64
  z=ffrep_fill(path_recipe,ffrep_recipe_size(),0-1)
  z=ffrep_clear(stats,ffrcl2_goal_stats_size())
  if ffrep_terms_fit(source_u,source_v,source_w,source_count,udim,vdim,wdim)==0
    return 0
  stats[16]=1

  states_u=i64[node_cap*aug_count]
  states_v=i64[node_cap*aug_count]
  states_w=i64[node_cap*aug_count]
  parents=i64[node_cap]
  depths=i64[node_cap]
  hashes=i64[node_cap]
  table=i64[ffrep_table_size(node_cap)]
  tree_meta=i64[6]
  line=i64[5]
  replay_u=i64[aug_count]
  replay_v=i64[aug_count]
  replay_w=i64[aug_count]
  replay_meta=i64[ffrep_replay_meta_size()]
  stripped_u=i64[source_count]
  stripped_v=i64[source_count]
  stripped_w=i64[source_count]

  found=0 ## i64
  attempts=0 ## i64
  max_width=udim ## i64
  if vdim>max_width
    max_width=vdim
  if wdim>max_width
    max_width=wdim
  pair_count=(source_count*(source_count-1)) / 2 ## i64
  basis_phases=3*max_width ## i64
  live_phases=3*source_count ## i64
  xor_phases=3*pair_count ## i64
  total_phases=1+basis_phases+live_phases+xor_phases ## i64
  # Enumerate phases outside source labels.  The former source-major order
  # spent a small candidate cap almost entirely on label zero; this Latin
  # rotation covers every label and all three axes before going deeper.
  phase=0 ## i64
  while phase<total_phases && found==0 && attempts<candidate_cap
    catalyst_index=0 ## i64
    while catalyst_index<source_count && found==0 && attempts<candidate_cap
      catalyst_u=source_u[catalyst_index] ## i64
      catalyst_v=source_v[catalyst_index] ## i64
      catalyst_w=source_w[catalyst_index] ## i64
      valid=1 ## i64
      if phase>0 && phase<=basis_phases
        basis_code=phase-1 ## i64
        bit=basis_code / 3 ## i64
        tweak_axis=(catalyst_index+(basis_code%3))%3 ## i64
        width=udim ## i64
        if tweak_axis==1
          width=vdim
        if tweak_axis==2
          width=wdim
        if bit>=width
          valid=0
        if valid==1
          replacement=1<<bit ## i64
          current=catalyst_u ## i64
          if tweak_axis==1
            current=catalyst_v
          if tweak_axis==2
            current=catalyst_w
          if current==replacement
            valid=0
          if tweak_axis==0
            catalyst_u=replacement
          if tweak_axis==1
            catalyst_v=replacement
          if tweak_axis==2
            catalyst_w=replacement
      if phase>basis_phases && phase<=basis_phases+live_phases
        live_code=phase-1-basis_phases ## i64
        donor=live_code / 3 ## i64
        tweak_axis=(catalyst_index+(live_code%3))%3
        replacement=ffrcl_axis_get(source_u,source_v,source_w,donor,tweak_axis) ## i64
        current=ffrcl_axis_get(source_u,source_v,source_w,catalyst_index,tweak_axis) ## i64
        if replacement==current
          valid=0
        if tweak_axis==0
          catalyst_u=replacement
        if tweak_axis==1
          catalyst_v=replacement
        if tweak_axis==2
          catalyst_w=replacement
      if phase>basis_phases+live_phases
        xor_code=phase-1-basis_phases-live_phases ## i64
        pair_ordinal=xor_code / 3 ## i64
        tweak_axis=(catalyst_index+(xor_code%3))%3
        pair_left=0 ## i64
        remaining=pair_ordinal ## i64
        while pair_left<source_count-1 && remaining>=source_count-pair_left-1
          pair_choices=source_count-pair_left-1 ## i64
          remaining-=pair_choices
          pair_left+=1
        pair_right=pair_left+1+remaining ## i64
        if pair_left>=source_count-1 || pair_right>=source_count
          valid=0
        if valid==1
          replacement=ffrcl_axis_get(source_u,source_v,source_w,pair_left,tweak_axis)^ffrcl_axis_get(source_u,source_v,source_w,pair_right,tweak_axis)
          current=ffrcl_axis_get(source_u,source_v,source_w,catalyst_index,tweak_axis)
          if replacement==0 || replacement==current
            valid=0
          if tweak_axis==0
            catalyst_u=replacement
          if tweak_axis==1
            catalyst_v=replacement
          if tweak_axis==2
            catalyst_w=replacement
      if valid==1
        attempts+=1
        stats[0]+=1
        z=ffrep_copy_slot(source_u,source_v,source_w,0,source_count,source_aug_u,source_aug_v,source_aug_w,0)
        source_aug_u[source_count]=catalyst_u
        source_aug_v[source_count]=catalyst_v
        source_aug_w[source_count]=catalyst_w
        source_aug_u[source_count+1]=catalyst_u
        source_aug_v[source_count+1]=catalyst_v
        source_aug_w[source_count+1]=catalyst_w
        nodes=ffrep_build_tree(source_aug_u,source_aug_v,source_aug_w,aug_count,max_depth,node_cap,states_u,states_v,states_w,parents,depths,hashes,table,tree_meta) ## i64
        stats[1]+=tree_meta[0]
        stats[2]+=tree_meta[1]
        stats[3]+=tree_meta[2]
        stats[4]+=tree_meta[3]
        stats[12]+=tree_meta[4]
        if nodes>stats[17]
          stats[17]=nodes
        node=0 ## i64
        while node<nodes && found==0
          stats[18]+=1
          offset=node*aug_count ## i64
          if depths[node]>=min_depth && ffrcl2_find_line(states_u,states_v,states_w,offset,aug_count,line)==1
            stats[5]+=1
            copied=ffrcl2_copy_without_line(states_u,states_v,states_w,offset,aug_count,line,target_u,target_v,target_w) ## i64
            if copied==target_count && ffrep_local_exact_shape(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,udim,vdim,wdim)==1
              stats[6]+=1
              z=ffrep_copy_slot(states_u,states_v,states_w,offset,aug_count,target_aug_u,target_aug_v,target_aug_w,0)
              depth=ffrcl2_path_from_tree(states_u,states_v,states_w,parents,depths,node,aug_count,udim,vdim,wdim,path_recipe) ## i64
              if ffrep_recipe_valid(path_recipe)==1
                z=ffrep_fill(recipe,ffrcl2_recipe_size(),0-1)
                recipe[0]=2
                recipe[1]=source_count
                recipe[2]=target_count
                recipe[3]=catalyst_index
                recipe[4]=node
                recipe[5]=line[4]
                recipe[9]=depth
                recipe[10]=catalyst_u
                recipe[11]=catalyst_v
                recipe[12]=catalyst_w
                li=0 ## i64
                while li<4
                  term=offset+line[li] ## i64
                  recipe[13+li*3]=states_u[term]
                  recipe[14+li*3]=states_v[term]
                  recipe[15+li*3]=states_w[term]
                  li+=1
                recipe[6]=ffrcl_axis_get(states_u,states_v,states_w,offset+line[1],line[4])
                recipe[7]=ffrcl_axis_get(states_u,states_v,states_w,offset+line[2],line[4])
                recipe[8]=ffrcl_axis_get(states_u,states_v,states_w,offset+line[3],line[4])
                recipe[25]=attempts
                recipe[26]=1
                replayed=ffrep_replay_forward(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count,path_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
                stripped=0 ## i64
                if replayed==aug_count
                  stripped=ffrcl2_strip_target(replay_u,replay_v,replay_w,aug_count,recipe,stripped_u,stripped_v,stripped_w)
                if stripped==target_count && fftc_terms_same_set(stripped_u,stripped_v,stripped_w,target_count,target_u,target_v,target_w,target_count)==1
                  stats[10]=1
                undone=ffrep_replay_undo(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count,path_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
                stripped=0
                if undone==aug_count
                  stripped=ffrcl2_strip_source(replay_u,replay_v,replay_w,aug_count,recipe,stripped_u,stripped_v,stripped_w)
                if stripped==source_count && fftc_terms_same_set(stripped_u,stripped_v,stripped_w,source_count,source_u,source_v,source_w,source_count)==1
                  stats[11]=1
                if stats[10]==1 && stats[11]==1 && ffrcl2_line_zero(recipe)==1
                  recipe[27]=1
                  stats[7]=depth
                  stats[8]=target_count
                  stats[9]=fftc_density(source_u,source_v,source_w,source_count)-fftc_density(target_u,target_v,target_w,target_count)
                  stats[13]=1
                  stats[14]=attempts
                  stats[15]=node
                  stats[19]=ffrcl2_terms_unique(target_u,target_v,target_w,target_count)
                  found=target_count
          node+=1
      catalyst_index+=1
    phase+=1
  found
