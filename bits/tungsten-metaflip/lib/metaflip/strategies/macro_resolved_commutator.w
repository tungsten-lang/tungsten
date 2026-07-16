# Target-resolved setup/trigger/cleanup macros over labelled ordinary flips.
#
# A literal word A B A is only a conjugate when the second A remains the
# inverse partial flip after B.  That condition is uncommon on real schemes.
# This strategy keeps the Rubik-style contract while resolving the inverse
# word in the state where it is needed:
#
#   setup A C; trigger B; cleanup X Y.
#
# A must displace a caller-selected anchor.  C grows the connected active
# ribbon.  B must make one requested focus-factor substitution which was not
# present before the trigger.  The bounded cleanup search accepts only X,Y
# that restore the complete anchor term while retaining the focus change.
# Every edge is an exact rank-neutral pair flip; replay independently gates
# the final local tensor and both semantic postconditions.
# The five-edge form is a cheap control.  The seven-edge form below is the
# first tested form capable of changing five labels after restoring the
# anchor.  Both remain offline after density-matched continuation tests.
#
# Recipe (20 words):
#   0 version, 1 length (=5), 2..6 A/C/B/X/Y codes,
#   7 focus, 8 axis, 9 target, 10 anchor, 11 rank,
#   12 endpoint distance, 13 density delta, 14 pair-pressure delta,
#   15 active-label mask, 16 maximum intermediate density debt,
#   17..19 reserved.
#
# Stats (20 words):
#   0 structural A candidates, 1 legal A, 2 legal C,
#   3 legal triggers, 4 trigger target hits, 5 legal X, 6 cleanup Y tried,
#   7 anchor restores, 8 changed endpoints, 9 exact endpoints,
#   10 retained endpoints, 11 best distance, 12 best density delta,
#   13 best pressure delta, 14 replay exact, 15 cap reached,
#   16 trigger states, 17 focus-preserving cleanup states,
#   18 maximum intermediate density debt, 19 reserved.

use macro_holonomy

-> ffrc_clear(values, count) (i64[] i64) i64
  i=0 ## i64
  while i<count
    values[i]=0
    i+=1
  count

-> ffrc_term_equal(us,vs,ws,left,other_u,other_v,other_w,right) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  fftc_same_term(us[left],vs[left],ws[left],other_u[right],other_v[right],other_w[right])

-> ffrc_pair_mask(pair) (i64[]) i64
  (1<<pair[0]) | (1<<pair[1])

# Grow one connected ribbon edge and require it to introduce a fresh label.
-> ffrc_grow(mask,pair) (i64 i64[]) i64
  pair_mask=ffrc_pair_mask(pair) ## i64
  if (pair_mask & mask)==0 || (pair_mask & (0-mask-1))==0
    return 0
  mask | pair_mask

-> ffrc_pair_has(pair,label) (i64[] i64) i64
  if pair[0]==label || pair[1]==label
    return 1
  0

-> ffrc_distinct(us,vs,ws,count) (i64[] i64[] i64[] i64) i64
  i=0 ## i64
  while i<count
    j=i+1 ## i64
    while j<count
      if fftc_same_term(us[i],vs[i],ws[i],us[j],vs[j],ws[j])==1
        return 0
      j+=1
    i+=1
  1

-> ffrc_target(us,vs,ws,focus,axis,target) (i64[] i64[] i64[] i64 i64 i64) i64
  if focus<0 || focus>=us.size() || axis<0 || axis>2 || target<=0
    return 0
  if ffmh_axis_get(us,vs,ws,focus,axis)==target
    return 1
  0

-> ffrc_better(distance,density_delta,pressure_delta,stats) (i64 i64 i64 i64[]) i64
  if stats[10]==0
    return 1
  if distance>stats[11]
    return 1
  if distance<stats[11]
    return 0
  if density_delta<stats[12]
    return 1
  if density_delta>stats[12]
    return 0
  if pressure_delta>stats[13]
    return 1
  0

-> ffrc_replay(source_u,source_v,source_w,count,recipe,out_u,out_v,out_w,meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if count<4 || count>6 || recipe.size()<20 || meta.size()<8
    return 0
  if recipe[0] != 1 || recipe[1] != 5 || recipe[11] != count
    return 0
  focus=recipe[7] ## i64
  axis=recipe[8] ## i64
  target=recipe[9] ## i64
  anchor=recipe[10] ## i64
  if focus<0 || focus>=count || anchor<0 || anchor>=count || focus==anchor || axis<0 || axis>2 || target<=0
    return 0
  z=ffrc_clear(meta,8) ## i64
  us=i64[count];vs=i64[count];ws=i64[count]
  z=ffmh_copy(source_u,source_v,source_w,count,us,vs,ws)
  source_density=fftc_density(source_u,source_v,source_w,count) ## i64
  max_debt=0 ## i64
  step=0 ## i64
  while step<5
    if fftc_apply_code(us,vs,ws,count,recipe[2+step],0-1) != 1
      return 0
    debt=fftc_density(us,vs,ws,count)-source_density ## i64
    if debt>max_debt
      max_debt=debt
    step+=1
  exact=ffmh_local_exact(source_u,source_v,source_w,count,us,vs,ws,count) ## i64
  changed=ffmh_distance(source_u,source_v,source_w,count,us,vs,ws,count) ## i64
  target_hit=ffrc_target(us,vs,ws,focus,axis,target) ## i64
  anchor_restored=ffrc_term_equal(us,vs,ws,anchor,source_u,source_v,source_w,anchor) ## i64
  meta[0]=exact
  if changed>0
    meta[1]=1
  meta[2]=target_hit
  meta[3]=anchor_restored
  meta[4]=changed
  meta[5]=fftc_density(us,vs,ws,count)-source_density
  meta[6]=ffmh_pair_pressure(us,vs,ws,count)-ffmh_pair_pressure(source_u,source_v,source_w,count)
  meta[7]=max_debt
  if exact != 1 || changed<1 || target_hit != 1 || anchor_restored != 1 || ffrc_distinct(us,vs,ws,count)==0
    return 0
  z=ffmh_copy(us,vs,ws,count,out_u,out_v,out_w)
  count

-> ffrc_consider(source_u,source_v,source_w,count,candidate_u,candidate_v,candidate_w,config,out_u,out_v,out_w,recipe,stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  focus=config[5] ## i64
  axis=config[6] ## i64
  target=config[7] ## i64
  anchor=config[8] ## i64
  if ffrc_target(candidate_u,candidate_v,candidate_w,focus,axis,target)==0
    return 0
  stats[17]+=1
  if ffrc_term_equal(candidate_u,candidate_v,candidate_w,anchor,source_u,source_v,source_w,anchor)==0
    return 0
  stats[7]+=1
  distance=ffmh_distance(source_u,source_v,source_w,count,candidate_u,candidate_v,candidate_w,count) ## i64
  if distance<1 || ffrc_distinct(candidate_u,candidate_v,candidate_w,count)==0
    return 0
  stats[8]+=1
  if ffmh_local_exact(source_u,source_v,source_w,count,candidate_u,candidate_v,candidate_w,count) != 1
    return 0
  stats[9]+=1
  density_delta=fftc_density(candidate_u,candidate_v,candidate_w,count)-fftc_density(source_u,source_v,source_w,count) ## i64
  pressure_delta=ffmh_pair_pressure(candidate_u,candidate_v,candidate_w,count)-ffmh_pair_pressure(source_u,source_v,source_w,count) ## i64
  if ffrc_better(distance,density_delta,pressure_delta,stats)==0
    return 1
  z=ffmh_copy(candidate_u,candidate_v,candidate_w,count,out_u,out_v,out_w) ## i64
  recipe[0]=1; recipe[1]=5
  i=0 ## i64
  while i<5
    recipe[2+i]=config[i]
    i+=1
  recipe[7]=focus; recipe[8]=axis; recipe[9]=target; recipe[10]=anchor
  recipe[11]=count; recipe[12]=distance; recipe[13]=density_delta; recipe[14]=pressure_delta
  recipe[15]=config[9]; recipe[16]=config[10]
  stats[10]+=1
  stats[11]=distance;stats[12]=density_delta;stats[13]=pressure_delta
  1

# Enumerate connected setup/trigger words and resolve a two-edge cleanup.
# `max_cleanup` bounds legal Y candidates, which dominate the cost.
-> ffrc_search_target(source_u,source_v,source_w,count,focus,axis,target,anchor,max_cleanup,out_u,out_v,out_w,recipe,stats) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if count<4 || count>6 || focus<0 || focus>=count || anchor<0 || anchor>=count || focus==anchor || axis<0 || axis>2 || target<=0 || max_cleanup<1
    return 0
  if out_u.size()<count || out_v.size()<count || out_w.size()<count || recipe.size()<20 || stats.size()<20
    return 0
  if ffrc_target(source_u,source_v,source_w,focus,axis,target)==1
    return 0
  z=ffrc_clear(recipe,20) ## i64
  z=ffrc_clear(stats,20)
  code_count=fftc_code_count(count) ## i64
  s1u=i64[count];s1v=i64[count];s1w=i64[count]
  s2u=i64[count];s2v=i64[count];s2w=i64[count]
  s3u=i64[count];s3v=i64[count];s3w=i64[count]
  s4u=i64[count];s4v=i64[count];s4w=i64[count]
  s5u=i64[count];s5v=i64[count];s5w=i64[count]
  pa=i64[3];pc=i64[3];pb=i64[3];px=i64[3];py=i64[3]
  config=i64[11]
  config[5]=focus;config[6]=axis;config[7]=target;config[8]=anchor
  source_density=fftc_density(source_u,source_v,source_w,count) ## i64
  a=0 ## i64
  while a<code_count && stats[6]<max_cleanup
    if ffmh_decode_code(a,count,pa)==1 && ffrc_pair_has(pa,anchor)==1
      stats[0]+=1
      z=ffmh_copy(source_u,source_v,source_w,count,s1u,s1v,s1w)
      if fftc_apply_code(s1u,s1v,s1w,count,a,0-1)==1
        if ffrc_term_equal(s1u,s1v,s1w,anchor,source_u,source_v,source_w,anchor)==0
          stats[1]+=1
          mask1=ffrc_pair_mask(pa) ## i64
          c=0 ## i64
          while c<code_count && stats[6]<max_cleanup
            if c != a && ffmh_decode_code(c,count,pc)==1
              mask2=ffrc_grow(mask1,pc) ## i64
              if mask2 != 0
                z=ffmh_copy(s1u,s1v,s1w,count,s2u,s2v,s2w)
                if fftc_apply_code(s2u,s2v,s2w,count,c,0-1)==1
                  stats[2]+=1
                  b=0 ## i64
                  while b<code_count && stats[6]<max_cleanup
                    if b != c && ffmh_decode_code(b,count,pb)==1 && ffrc_pair_has(pb,focus)==1 && (ffrc_pair_mask(pb)&mask2) != 0
                      z=ffmh_copy(s2u,s2v,s2w,count,s3u,s3v,s3w)
                      if ffrc_target(s3u,s3v,s3w,focus,axis,target)==0
                        if fftc_apply_code(s3u,s3v,s3w,count,b,0-1)==1
                          stats[3]+=1
                          if ffrc_target(s3u,s3v,s3w,focus,axis,target)==1
                            stats[4]+=1
                            stats[16]+=1
                            debt1=fftc_density(s1u,s1v,s1w,count)-source_density ## i64
                            debt2=fftc_density(s2u,s2v,s2w,count)-source_density ## i64
                            debt3=fftc_density(s3u,s3v,s3w,count)-source_density ## i64
                            max_debt=debt1 ## i64
                            if debt2>max_debt
                              max_debt=debt2
                            if debt3>max_debt
                              max_debt=debt3
                            x=0 ## i64
                            while x<code_count && stats[6]<max_cleanup
                              if ffmh_decode_code(x,count,px)==1 && (ffrc_pair_mask(px)&mask2) != 0
                                z=ffmh_copy(s3u,s3v,s3w,count,s4u,s4v,s4w)
                                if fftc_apply_code(s4u,s4v,s4w,count,x,0-1)==1
                                  stats[5]+=1
                                  y=0 ## i64
                                  while y<code_count && stats[6]<max_cleanup
                                    if ffmh_decode_code(y,count,py)==1 && (ffrc_pair_mask(py)&mask2) != 0
                                      stats[6]+=1
                                      z=ffmh_copy(s4u,s4v,s4w,count,s5u,s5v,s5w)
                                      if fftc_apply_code(s5u,s5v,s5w,count,y,0-1)==1
                                        debt4=fftc_density(s4u,s4v,s4w,count)-source_density ## i64
                                        debt5=fftc_density(s5u,s5v,s5w,count)-source_density ## i64
                                        endpoint_debt=max_debt ## i64
                                        if debt4>endpoint_debt
                                          endpoint_debt=debt4
                                        if debt5>endpoint_debt
                                          endpoint_debt=debt5
                                        config[0]=a;config[1]=c;config[2]=b;config[3]=x;config[4]=y
                                        config[9]=mask2;config[10]=endpoint_debt
                                        z=ffrc_consider(source_u,source_v,source_w,count,s5u,s5v,s5w,config,out_u,out_v,out_w,recipe,stats)
                                    y+=1
                              x+=1
                    b+=1
            c+=1
    a+=1
  if stats[6]>=max_cleanup
    stats[15]=1
  if stats[9]<1
    return 0
  meta=i64[8]
  replayed=ffrc_replay(source_u,source_v,source_w,count,recipe,out_u,out_v,out_w,meta) ## i64
  if replayed != count || meta[0] != 1 || meta[1] != 1 || meta[2] != 1 || meta[3] != 1
    stats[14]=0
    return 0
  stats[14]=1
  if meta[7]>stats[18]
    stats[18]=meta[7]
  count

# Three-edge setup and state-resolved three-edge cleanup.  The longer word
# can change five live labels after restoring the anchor and is therefore
# capable of escaping the complete <=4-term span-refactor neighborhood by
# support alone.
#
# Recipe (24 words): version (=2), length (=7), A/C/D/B/X/Y/Z codes,
# focus, axis, target, anchor, rank, distance, density delta, pressure delta,
# active mask, maximum density debt, remaining reserved.
# Stats (24 words): 0 A candidates; 1..4 legal A/C/D/B; 5 trigger hits;
# 6/7 legal X/Y; 8 Z tried; 9 anchor restores; 10 changed; 11 exact;
# 12 retained best updates; 13..15 best distance/density/pressure;
# 16 reserved; 17 replay exact; 18 cap reached; 19 trigger states;
# 20 focus-preserving cleanup states; 21..23 reserved.

-> ffrc7_replay(source_u,source_v,source_w,count,recipe,out_u,out_v,out_w,meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if count<5 || count>7 || recipe.size()<24 || meta.size()<8
    return 0
  if recipe[0] != 2 || recipe[1] != 7 || recipe[13] != count
    return 0
  focus=recipe[9] ## i64
  axis=recipe[10] ## i64
  target=recipe[11] ## i64
  anchor=recipe[12] ## i64
  if focus<0 || focus>=count || anchor<0 || anchor>=count || focus==anchor || axis<0 || axis>2 || target<=0
    return 0
  z=ffrc_clear(meta,8) ## i64
  us=i64[count];vs=i64[count];ws=i64[count]
  z=ffmh_copy(source_u,source_v,source_w,count,us,vs,ws)
  source_density=fftc_density(source_u,source_v,source_w,count) ## i64
  max_debt=0 ## i64
  step=0 ## i64
  while step<7
    if fftc_apply_code(us,vs,ws,count,recipe[2+step],0-1) != 1
      return 0
    debt=fftc_density(us,vs,ws,count)-source_density ## i64
    if debt>max_debt
      max_debt=debt
    step+=1
  exact=ffmh_local_exact(source_u,source_v,source_w,count,us,vs,ws,count) ## i64
  distance=ffmh_distance(source_u,source_v,source_w,count,us,vs,ws,count) ## i64
  target_hit=ffrc_target(us,vs,ws,focus,axis,target) ## i64
  anchor_restored=ffrc_term_equal(us,vs,ws,anchor,source_u,source_v,source_w,anchor) ## i64
  meta[0]=exact
  if distance>0
    meta[1]=1
  meta[2]=target_hit;meta[3]=anchor_restored;meta[4]=distance
  meta[5]=fftc_density(us,vs,ws,count)-source_density
  meta[6]=ffmh_pair_pressure(us,vs,ws,count)-ffmh_pair_pressure(source_u,source_v,source_w,count)
  meta[7]=max_debt
  if exact != 1 || distance<1 || target_hit != 1 || anchor_restored != 1 || ffrc_distinct(us,vs,ws,count)==0
    return 0
  z=ffmh_copy(us,vs,ws,count,out_u,out_v,out_w)
  count

-> ffrc7_consider(source_u,source_v,source_w,count,candidate_u,candidate_v,candidate_w,config,out_u,out_v,out_w,recipe,stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  focus=config[7] ## i64
  axis=config[8] ## i64
  target=config[9] ## i64
  anchor=config[10] ## i64
  if ffrc_target(candidate_u,candidate_v,candidate_w,focus,axis,target)==0
    return 0
  stats[20]+=1
  if ffrc_term_equal(candidate_u,candidate_v,candidate_w,anchor,source_u,source_v,source_w,anchor)==0
    return 0
  stats[9]+=1
  distance=ffmh_distance(source_u,source_v,source_w,count,candidate_u,candidate_v,candidate_w,count) ## i64
  if distance<1 || ffrc_distinct(candidate_u,candidate_v,candidate_w,count)==0
    return 0
  stats[10]+=1
  if ffmh_local_exact(source_u,source_v,source_w,count,candidate_u,candidate_v,candidate_w,count) != 1
    return 0
  stats[11]+=1
  density_delta=fftc_density(candidate_u,candidate_v,candidate_w,count)-fftc_density(source_u,source_v,source_w,count) ## i64
  pressure_delta=ffmh_pair_pressure(candidate_u,candidate_v,candidate_w,count)-ffmh_pair_pressure(source_u,source_v,source_w,count) ## i64
  better=0 ## i64
  if stats[12]==0 || distance>stats[13]
    better=1
  if distance==stats[13] && density_delta<stats[14]
    better=1
  if distance==stats[13] && density_delta==stats[14] && pressure_delta>stats[15]
    better=1
  if better==0
    return 1
  z=ffmh_copy(candidate_u,candidate_v,candidate_w,count,out_u,out_v,out_w) ## i64
  recipe[0]=2;recipe[1]=7
  i=0 ## i64
  while i<7
    recipe[2+i]=config[i]
    i+=1
  recipe[9]=focus;recipe[10]=axis;recipe[11]=target;recipe[12]=anchor
  recipe[13]=count;recipe[14]=distance;recipe[15]=density_delta;recipe[16]=pressure_delta
  recipe[17]=config[11];recipe[18]=config[12]
  stats[12]+=1;stats[13]=distance;stats[14]=density_delta;stats[15]=pressure_delta
  1

-> ffrc7_search_target(source_u,source_v,source_w,count,focus,axis,target,anchor,max_cleanup,out_u,out_v,out_w,recipe,stats) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if count<5 || count>7 || focus<0 || focus>=count || anchor<0 || anchor>=count || focus==anchor || axis<0 || axis>2 || target<=0 || max_cleanup<1
    return 0
  if out_u.size()<count || out_v.size()<count || out_w.size()<count || recipe.size()<24 || stats.size()<24
    return 0
  if ffrc_target(source_u,source_v,source_w,focus,axis,target)==1
    return 0
  z=ffrc_clear(recipe,24) ## i64
  z=ffrc_clear(stats,24)
  code_count=fftc_code_count(count) ## i64
  s1u=i64[count];s1v=i64[count];s1w=i64[count]
  s2u=i64[count];s2v=i64[count];s2w=i64[count]
  s3u=i64[count];s3v=i64[count];s3w=i64[count]
  s4u=i64[count];s4v=i64[count];s4w=i64[count]
  s5u=i64[count];s5v=i64[count];s5w=i64[count]
  s6u=i64[count];s6v=i64[count];s6w=i64[count]
  s7u=i64[count];s7v=i64[count];s7w=i64[count]
  pa=i64[3];pc=i64[3];pd=i64[3];pb=i64[3];px=i64[3];py=i64[3];pz=i64[3]
  config=i64[13]
  config[7]=focus;config[8]=axis;config[9]=target;config[10]=anchor
  source_density=fftc_density(source_u,source_v,source_w,count) ## i64
  a=0 ## i64
  while a<code_count && stats[8]<max_cleanup
    if ffmh_decode_code(a,count,pa)==1 && ffrc_pair_has(pa,anchor)==1
      stats[0]+=1
      z=ffmh_copy(source_u,source_v,source_w,count,s1u,s1v,s1w)
      if fftc_apply_code(s1u,s1v,s1w,count,a,0-1)==1 && ffrc_term_equal(s1u,s1v,s1w,anchor,source_u,source_v,source_w,anchor)==0
        stats[1]+=1
        mask1=ffrc_pair_mask(pa) ## i64
        c=0 ## i64
        while c<code_count && stats[8]<max_cleanup
          if c != a && ffmh_decode_code(c,count,pc)==1
            mask2=ffrc_grow(mask1,pc) ## i64
            if mask2 != 0
              z=ffmh_copy(s1u,s1v,s1w,count,s2u,s2v,s2w)
              if fftc_apply_code(s2u,s2v,s2w,count,c,0-1)==1
                stats[2]+=1
                d=0 ## i64
                while d<code_count && stats[8]<max_cleanup
                  if d != c && ffmh_decode_code(d,count,pd)==1
                    mask3=ffrc_grow(mask2,pd) ## i64
                    if mask3 != 0
                      z=ffmh_copy(s2u,s2v,s2w,count,s3u,s3v,s3w)
                      if fftc_apply_code(s3u,s3v,s3w,count,d,0-1)==1
                        stats[3]+=1
                        b=0 ## i64
                        while b<code_count && stats[8]<max_cleanup
                          if b != d && ffmh_decode_code(b,count,pb)==1 && ffrc_pair_has(pb,focus)==1 && (ffrc_pair_mask(pb)&mask3) != 0
                            z=ffmh_copy(s3u,s3v,s3w,count,s4u,s4v,s4w)
                            if ffrc_target(s4u,s4v,s4w,focus,axis,target)==0 && fftc_apply_code(s4u,s4v,s4w,count,b,0-1)==1
                              stats[4]+=1
                              if ffrc_target(s4u,s4v,s4w,focus,axis,target)==1
                                stats[5]+=1;stats[19]+=1
                                debt1=fftc_density(s1u,s1v,s1w,count)-source_density ## i64
                                debt2=fftc_density(s2u,s2v,s2w,count)-source_density ## i64
                                debt3=fftc_density(s3u,s3v,s3w,count)-source_density ## i64
                                debt4=fftc_density(s4u,s4v,s4w,count)-source_density ## i64
                                max_debt=debt1 ## i64
                                if debt2>max_debt
                                  max_debt=debt2
                                if debt3>max_debt
                                  max_debt=debt3
                                if debt4>max_debt
                                  max_debt=debt4
                                x=0 ## i64
                                while x<code_count && stats[8]<max_cleanup
                                  if ffmh_decode_code(x,count,px)==1 && (ffrc_pair_mask(px)&mask3) != 0
                                    z=ffmh_copy(s4u,s4v,s4w,count,s5u,s5v,s5w)
                                    if fftc_apply_code(s5u,s5v,s5w,count,x,0-1)==1
                                      stats[6]+=1
                                      y=0 ## i64
                                      while y<code_count && stats[8]<max_cleanup
                                        if ffmh_decode_code(y,count,py)==1 && (ffrc_pair_mask(py)&mask3) != 0
                                          z=ffmh_copy(s5u,s5v,s5w,count,s6u,s6v,s6w)
                                          if fftc_apply_code(s6u,s6v,s6w,count,y,0-1)==1
                                            stats[7]+=1
                                            zz=0 ## i64
                                            while zz<code_count && stats[8]<max_cleanup
                                              if ffmh_decode_code(zz,count,pz)==1 && (ffrc_pair_mask(pz)&mask3) != 0
                                                stats[8]+=1
                                                z=ffmh_copy(s6u,s6v,s6w,count,s7u,s7v,s7w)
                                                if fftc_apply_code(s7u,s7v,s7w,count,zz,0-1)==1
                                                  endpoint_debt=max_debt ## i64
                                                  debt5=fftc_density(s5u,s5v,s5w,count)-source_density ## i64
                                                  debt6=fftc_density(s6u,s6v,s6w,count)-source_density ## i64
                                                  debt7=fftc_density(s7u,s7v,s7w,count)-source_density ## i64
                                                  if debt5>endpoint_debt
                                                    endpoint_debt=debt5
                                                  if debt6>endpoint_debt
                                                    endpoint_debt=debt6
                                                  if debt7>endpoint_debt
                                                    endpoint_debt=debt7
                                                  config[0]=a;config[1]=c;config[2]=d;config[3]=b
                                                  config[4]=x;config[5]=y;config[6]=zz
                                                  config[11]=mask3;config[12]=endpoint_debt
                                                  z=ffrc7_consider(source_u,source_v,source_w,count,s7u,s7v,s7w,config,out_u,out_v,out_w,recipe,stats)
                                              zz+=1
                                        y+=1
                                  x+=1
                          b+=1
                  d+=1
          c+=1
    a+=1
  if stats[8]>=max_cleanup
    stats[18]=1
  if stats[11]<1
    return 0
  meta=i64[8]
  replayed=ffrc7_replay(source_u,source_v,source_w,count,recipe,out_u,out_v,out_w,meta) ## i64
  if replayed != count || meta[0] != 1 || meta[1] != 1 || meta[2] != 1 || meta[3] != 1
    stats[17]=0
    return 0
  stats[17]=1
  count
