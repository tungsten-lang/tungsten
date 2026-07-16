# Offline catalyst lift for a known exact q -> q-1 rectangular replacement.
#
# A fixed-rank ordinary-flip word cannot directly connect lists of different
# cardinality. This compiler adds two different zero gadgets:
#
#   source: an identical rank-one doublet C+C;
#   target: a projective line X(a)+X(b)+X(a^b).
#
# Both lifted lists have q+2 labels and the same local tensor. The existing
# endpoint-word compiler then searches between them unchanged. On replay the
# target triangle is stripped; on undo the source doublet is stripped.
#
# The bounded gadget family is anchored on a source pair whose merge is a
# literal target term. For a merge on axis A, choose either child as pivot,
# one transverse axis B, and a nonzero basis mask d != the shared B factor.
# The source doublet is the merged parent with B=d. The target triangle uses
# the pivot on A, the untouched third factor, and B factors d, b, d^b.
#
# Limits: source q=2..7, lifted q+2<=9, path depth<=10. This is deliberately
# offline and performs no file I/O or scheduling.
#
# Lift recipe (28 words):
#   0 version, 1 source q, 2 target q-1, 3/4 source merge labels,
#   5 merge axis, 6 pivot label, 7 transverse axis, 8 target parent label,
#   9 path length, 10..12 source catalyst triple,
#   13..21 target triangle triples, 22..24 U/V/W widths,
#   25 candidate ordinal, 26 reserved, 27 success.
#
# Stats (16 words):
#   0 source pairs, 1 parent matches, 2 gadget candidates,
#   3 independently shape-exact lifts, 4 path calls, 5 path hits,
#   6 capped path calls, 7 retained path length, 8/9 forward/back states,
#   10 legal edges, 11 forward strip/replay, 12 undo strip/replay,
#   13 base local exact, 14 candidate cap reached, 15 success.

use rect_endpoint_path

-> ffrcl_recipe_size() i64
  28

-> ffrcl_stats_size() i64
  16

-> ffrcl_axis_get(us, vs, ws, index, axis) (i64[] i64[] i64[] i64 i64) i64
  value = us[index] ## i64
  if axis == 1
    value = vs[index]
  if axis == 2
    value = ws[index]
  value

-> ffrcl_axis_set(us, vs, ws, index, axis, value) (i64[] i64[] i64[] i64 i64 i64) i64
  if axis == 0
    us[index] = value
  if axis == 1
    vs[index] = value
  if axis == 2
    ws[index] = value
  value

-> ffrcl_pair_mergeable(us, vs, ws, first, second, axis) (i64[] i64[] i64[] i64 i64 i64) i64
  if first < 0 || second < 0 || first == second || axis < 0 || axis > 2
    return 0
  if axis != 0 && us[first] != us[second]
    return 0
  if axis != 1 && vs[first] != vs[second]
    return 0
  if axis != 2 && ws[first] != ws[second]
    return 0
  if ffrcl_axis_get(us,vs,ws,first,axis) == ffrcl_axis_get(us,vs,ws,second,axis)
    return 0
  1

-> ffrcl_find_term(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if us[i] == u && vs[i] == v && ws[i] == w
      return i
    i += 1
  0 - 1

-> ffrcl_remove_once(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  position = ffrcl_find_term(us,vs,ws,count,u,v,w) ## i64
  if position < 0
    return 0 - 1
  last = count - 1 ## i64
  us[position] = us[last]
  vs[position] = vs[last]
  ws[position] = ws[last]
  last

-> ffrcl_triangle_zero(recipe) (i64[]) i64
  if recipe.size() < ffrcl_recipe_size()
    return 0
  u0=recipe[13];v0=recipe[14];w0=recipe[15]
  u1=recipe[16];v1=recipe[17];w1=recipe[18]
  u2=recipe[19];v2=recipe[20];w2=recipe[21]
  if u0 <= 0 || v0 <= 0 || w0 <= 0 || u1 <= 0 || v1 <= 0 || w1 <= 0 || u2 <= 0 || v2 <= 0 || w2 <= 0
    return 0
  if v0 == v1 && v0 == v2 && w0 == w1 && w0 == w2 && (u0 ^ u1 ^ u2) == 0
    return 1
  if u0 == u1 && u0 == u2 && w0 == w1 && w0 == w2 && (v0 ^ v1 ^ v2) == 0
    return 1
  if u0 == u1 && u0 == u2 && v0 == v1 && v0 == v2 && (w0 ^ w1 ^ w2) == 0
    return 1
  0

-> ffrcl_strip_source(aug_u, aug_v, aug_w, aug_count, recipe, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  if recipe.size() < ffrcl_recipe_size() || recipe[0] != 1 || recipe[1] < 2 || aug_count != recipe[1] + 2
    return 0
  if out_u.size() < recipe[1] || out_v.size() < recipe[1] || out_w.size() < recipe[1]
    return 0
  scratch_u=i64[aug_count];scratch_v=i64[aug_count];scratch_w=i64[aug_count]
  z=ffrep_copy_slot(aug_u,aug_v,aug_w,0,aug_count,scratch_u,scratch_v,scratch_w,0) ## i64
  count=ffrcl_remove_once(scratch_u,scratch_v,scratch_w,aug_count,recipe[10],recipe[11],recipe[12]) ## i64
  if count < 0
    return 0
  count=ffrcl_remove_once(scratch_u,scratch_v,scratch_w,count,recipe[10],recipe[11],recipe[12])
  if count != recipe[1]
    return 0
  z=ffrep_sort_slot(scratch_u,scratch_v,scratch_w,0,count)
  z=ffrep_copy_slot(scratch_u,scratch_v,scratch_w,0,count,out_u,out_v,out_w,0)
  count

-> ffrcl_strip_target(aug_u, aug_v, aug_w, aug_count, recipe, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  if recipe.size() < ffrcl_recipe_size() || recipe[0] != 1 || recipe[2] < 1 || aug_count != recipe[2] + 3 || ffrcl_triangle_zero(recipe) == 0
    return 0
  if out_u.size() < recipe[2] || out_v.size() < recipe[2] || out_w.size() < recipe[2]
    return 0
  scratch_u=i64[aug_count];scratch_v=i64[aug_count];scratch_w=i64[aug_count]
  z=ffrep_copy_slot(aug_u,aug_v,aug_w,0,aug_count,scratch_u,scratch_v,scratch_w,0) ## i64
  count=ffrcl_remove_once(scratch_u,scratch_v,scratch_w,aug_count,recipe[13],recipe[14],recipe[15]) ## i64
  if count < 0
    return 0
  count=ffrcl_remove_once(scratch_u,scratch_v,scratch_w,count,recipe[16],recipe[17],recipe[18])
  if count < 0
    return 0
  count=ffrcl_remove_once(scratch_u,scratch_v,scratch_w,count,recipe[19],recipe[20],recipe[21])
  if count != recipe[2]
    return 0
  z=ffrep_sort_slot(scratch_u,scratch_v,scratch_w,0,count)
  z=ffrep_copy_slot(scratch_u,scratch_v,scratch_w,0,count,out_u,out_v,out_w,0)
  count

-> ffrcl_search(source_u, source_v, source_w, source_count, target_u, target_v, target_w, target_count, shape, limits, source_aug_u, source_aug_v, source_aug_w, target_aug_u, target_aug_v, target_aug_w, recipe, path_recipe, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if source_count < 2 || source_count > 7 || target_count != source_count-1
    return 0
  if shape.size() < 3 || limits.size() < 3 || recipe.size() < ffrcl_recipe_size() || path_recipe.size() < ffrep_recipe_size() || stats.size() < ffrcl_stats_size()
    return 0
  aug_count=source_count+2 ## i64
  if source_aug_u.size()<aug_count || source_aug_v.size()<aug_count || source_aug_w.size()<aug_count || target_aug_u.size()<aug_count || target_aug_v.size()<aug_count || target_aug_w.size()<aug_count
    return 0
  udim=shape[0] ## i64
  vdim=shape[1] ## i64
  wdim=shape[2] ## i64
  max_depth=limits[0] ## i64
  node_cap=limits[1] ## i64
  candidate_cap=limits[2] ## i64
  if max_depth<1 || max_depth>ffrep_max_depth() || node_cap<16 || node_cap>65536 || candidate_cap<1 || candidate_cap>256
    return 0
  z=ffrep_fill(recipe,ffrcl_recipe_size(),0-1) ## i64
  z=ffrep_fill(path_recipe,ffrep_recipe_size(),0-1)
  z=ffrep_clear(stats,ffrcl_stats_size())
  if ffrep_local_exact_shape(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,udim,vdim,wdim) != 1
    return 0
  stats[13]=1

  found=0 ## i64
  attempts=0 ## i64
  first=0 ## i64
  while first<source_count-1 && found==0 && attempts<candidate_cap
    second=first+1 ## i64
    while second<source_count && found==0 && attempts<candidate_cap
      stats[0]+=1
      merge_axis=0 ## i64
      while merge_axis<3 && found==0 && attempts<candidate_cap
        if ffrcl_pair_mergeable(source_u,source_v,source_w,first,second,merge_axis)==1
          parent_u=source_u[first] ## i64
          parent_v=source_v[first] ## i64
          parent_w=source_w[first] ## i64
          merged=ffrcl_axis_get(source_u,source_v,source_w,first,merge_axis) ^ ffrcl_axis_get(source_u,source_v,source_w,second,merge_axis) ## i64
          if merge_axis==0
            parent_u=merged
          if merge_axis==1
            parent_v=merged
          if merge_axis==2
            parent_w=merged
          parent_index=ffrcl_find_term(target_u,target_v,target_w,target_count,parent_u,parent_v,parent_w) ## i64
          if parent_index>=0
            stats[1]+=1
            pivot_choice=0 ## i64
            while pivot_choice<2 && found==0 && attempts<candidate_cap
              pivot=first ## i64
              if pivot_choice==1
                pivot=second
              transverse=0 ## i64
              while transverse<3 && found==0 && attempts<candidate_cap
                if transverse != merge_axis
                  width=udim ## i64
                  if transverse==1
                    width=vdim
                  if transverse==2
                    width=wdim
                  shared=ffrcl_axis_get(source_u,source_v,source_w,first,transverse) ## i64
                  bit=0 ## i64
                  while bit<width && found==0 && attempts<candidate_cap
                    d=1<<bit ## i64
                    if d != shared && (d ^ shared) != 0
                      attempts+=1
                      stats[2]+=1
                      z=ffrep_copy_slot(source_u,source_v,source_w,0,source_count,source_aug_u,source_aug_v,source_aug_w,0)
                      catalyst_slot=source_count ## i64
                      source_aug_u[catalyst_slot]=parent_u
                      source_aug_v[catalyst_slot]=parent_v
                      source_aug_w[catalyst_slot]=parent_w
                      z=ffrcl_axis_set(source_aug_u,source_aug_v,source_aug_w,catalyst_slot,transverse,d)
                      source_aug_u[catalyst_slot+1]=source_aug_u[catalyst_slot]
                      source_aug_v[catalyst_slot+1]=source_aug_v[catalyst_slot]
                      source_aug_w[catalyst_slot+1]=source_aug_w[catalyst_slot]

                      z=ffrep_copy_slot(target_u,target_v,target_w,0,target_count,target_aug_u,target_aug_v,target_aug_w,0)
                      triangle0=target_count ## i64
                      triangle1=target_count+1 ## i64
                      triangle2=target_count+2 ## i64
                      target_aug_u[triangle0]=source_u[pivot]
                      target_aug_v[triangle0]=source_v[pivot]
                      target_aug_w[triangle0]=source_w[pivot]
                      target_aug_u[triangle1]=source_u[pivot]
                      target_aug_v[triangle1]=source_v[pivot]
                      target_aug_w[triangle1]=source_w[pivot]
                      target_aug_u[triangle2]=source_u[pivot]
                      target_aug_v[triangle2]=source_v[pivot]
                      target_aug_w[triangle2]=source_w[pivot]
                      z=ffrcl_axis_set(target_aug_u,target_aug_v,target_aug_w,triangle0,transverse,d)
                      z=ffrcl_axis_set(target_aug_u,target_aug_v,target_aug_w,triangle1,transverse,shared)
                      z=ffrcl_axis_set(target_aug_u,target_aug_v,target_aug_w,triangle2,transverse,d ^ shared)

                      lift_exact=ffrep_local_exact_shape(source_u,source_v,source_w,source_count,source_aug_u,source_aug_v,source_aug_w,aug_count,udim,vdim,wdim) ## i64
                      if lift_exact==1
                        lift_exact=ffrep_local_exact_shape(target_u,target_v,target_w,target_count,target_aug_u,target_aug_v,target_aug_w,aug_count,udim,vdim,wdim)
                      if lift_exact==1
                        lift_exact=ffrep_local_exact_shape(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count,udim,vdim,wdim)
                      if lift_exact==1
                        stats[3]+=1
                        trial_path=i64[ffrep_recipe_size()]
                        path_stats=i64[ffrep_stats_size()]
                        stats[4]+=1
                        trial=ffrep_search_same_rank(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count,udim,vdim,wdim,max_depth,node_cap,trial_path,path_stats) ## i64
                        if path_stats[10] != 0
                          stats[6]+=1
                        if trial>0
                          recipe[0]=1
                          recipe[1]=source_count
                          recipe[2]=target_count
                          recipe[3]=first
                          recipe[4]=second
                          recipe[5]=merge_axis
                          recipe[6]=pivot
                          recipe[7]=transverse
                          recipe[8]=parent_index
                          recipe[9]=trial
                          recipe[10]=source_aug_u[catalyst_slot]
                          recipe[11]=source_aug_v[catalyst_slot]
                          recipe[12]=source_aug_w[catalyst_slot]
                          recipe[13]=target_aug_u[triangle0]
                          recipe[14]=target_aug_v[triangle0]
                          recipe[15]=target_aug_w[triangle0]
                          recipe[16]=target_aug_u[triangle1]
                          recipe[17]=target_aug_v[triangle1]
                          recipe[18]=target_aug_w[triangle1]
                          recipe[19]=target_aug_u[triangle2]
                          recipe[20]=target_aug_v[triangle2]
                          recipe[21]=target_aug_w[triangle2]
                          recipe[22]=udim
                          recipe[23]=vdim
                          recipe[24]=wdim
                          recipe[25]=attempts
                          recipe[27]=0
                          path_word=0 ## i64
                          while path_word<ffrep_recipe_size()
                            path_recipe[path_word]=trial_path[path_word]
                            path_word+=1

                          replay_u=i64[aug_count];replay_v=i64[aug_count];replay_w=i64[aug_count];replay_meta=i64[ffrep_replay_meta_size()]
                          replayed=ffrep_replay_forward(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count,path_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
                          stripped_u=i64[source_count];stripped_v=i64[source_count];stripped_w=i64[source_count]
                          stripped=0 ## i64
                          if replayed==aug_count
                            stripped=ffrcl_strip_target(replay_u,replay_v,replay_w,aug_count,recipe,stripped_u,stripped_v,stripped_w)
                          if stripped==target_count && fftc_terms_same_set(stripped_u,stripped_v,stripped_w,stripped,target_u,target_v,target_w,target_count)==1
                            stats[11]=1
                          undone=ffrep_replay_undo(source_aug_u,source_aug_v,source_aug_w,aug_count,target_aug_u,target_aug_v,target_aug_w,aug_count,path_recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
                          stripped=0
                          if undone==aug_count
                            stripped=ffrcl_strip_source(replay_u,replay_v,replay_w,aug_count,recipe,stripped_u,stripped_v,stripped_w)
                          if stripped==source_count && fftc_terms_same_set(stripped_u,stripped_v,stripped_w,stripped,source_u,source_v,source_w,source_count)==1
                            stats[12]=1
                          if stats[11]==1 && stats[12]==1
                            recipe[27]=1
                            stats[5]+=1
                            stats[7]=trial
                            stats[8]=path_stats[0]
                            stats[9]=path_stats[1]
                            stats[10]=path_stats[4]
                            stats[15]=1
                            found=trial
                    bit+=1
                transverse+=1
              pivot_choice+=1
        merge_axis+=1
      second+=1
    first+=1
  if found==0 && attempts>=candidate_cap
    stats[14]=1
  found
