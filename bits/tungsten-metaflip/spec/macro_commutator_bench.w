# Decision benchmark for five-label setup-ribbon conjugates/commutators.

use ../lib/metaflip/rect
use ../lib/metaflip/strategies/macro_commutator
use ../lib/metaflip/strategies/macro_resolved_commutator
use ../lib/metaflip/strategies/low_rank_shear

-> ffccb_selected(selected, count, value) (i64[] i64 i64) i64
  i=0 ## i64
  while i<count
    if selected[i]==value
      return 1
    i+=1
  0

-> ffccb_window(us,vs,ws,rank,nonce,count,selected) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  if rank<count || count<5 || selected.size()<count
    return 0
  selected[0]=(nonce*97+13)%rank
  made=1 ## i64
  while made<count
    best=0-1 ## i64
    best_score=0-1 ## i64
    offset=(nonce*53+made*17)%rank ## i64
    ci=0 ## i64
    while ci<rank
      candidate=(offset+ci)%rank ## i64
      if ffccb_selected(selected,made,candidate)==0
        score=0 ## i64
        si=0 ## i64
        while si<made
          axis=0 ## i64
          while axis<3
            cf=ffmh_axis_get(us,vs,ws,candidate,axis) ## i64
            if cf==ffmh_axis_get(us,vs,ws,selected[si],axis)
              score+=8
            sj=si+1 ## i64
            while sj<made
              if cf==(ffmh_axis_get(us,vs,ws,selected[si],axis)^ffmh_axis_get(us,vs,ws,selected[sj],axis))
                score+=2
              sj+=1
            axis+=1
          si+=1
        if score>best_score
          best_score=score
          best=candidate
      ci+=1
    if best<0
      return 0
    selected[made]=best
    made+=1
  count

-> ffccb_capture(us,vs,ws,selected,count,out_u,out_v,out_w) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  i=0 ## i64
  while i<count
    out_u[i]=us[selected[i]]
    out_v[i]=vs[selected[i]]
    out_w[i]=ws[selected[i]]
    i+=1
  count

-> ffccb_toggle(us,vs,ws,count,capacity,u,v,w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  i=0 ## i64
  while i<count
    if fftc_same_term(us[i],vs[i],ws[i],u,v,w)==1
      last=count-1 ## i64
      us[i]=us[last]; vs[i]=vs[last]; ws[i]=ws[last]
      return count-1
    i+=1
  if count>=capacity || u==0 || v==0 || w==0
    return 0-count-1
  us[count]=u; vs[count]=v; ws[count]=w
  count+1

-> ffccb_splice(us,vs,ws,rank,selected,k,local_u,local_v,local_w,local_count,out_u,out_v,out_w,capacity) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  count=0 ## i64
  i=0 ## i64
  while i<rank
    if ffccb_selected(selected,k,i)==0
      count=ffccb_toggle(out_u,out_v,out_w,count,capacity,us[i],vs[i],ws[i])
      if count<0
        return 0
    i+=1
  i=0
  while i<local_count
    count=ffccb_toggle(out_u,out_v,out_w,count,capacity,local_u[i],local_v[i],local_w[i])
    if count<0
      return 0
    i+=1
  count

-> ffccb_in_span(values,count,value) (i64[] i64 i64) i64
  basis=i64[count]
  basis_count=ffsr_make_basis(values,count,basis) ## i64
  span=i64[1<<basis_count]
  span_count=ffsr_enumerate_span(basis,basis_count,span) ## i64
  ffsr_contains(span,span_count,value)

-> ffccb_span4_covered(source_u,source_v,source_w,source_count,out_u,out_v,out_w,out_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  used=i64[out_count]
  du=i64[source_count]; dv=i64[source_count]; dw=i64[source_count]
  ou=i64[out_count]; ov=i64[out_count]; ow=i64[out_count]
  ds=0 ## i64
  i=0 ## i64
  while i<source_count
    found=0-1 ## i64
    j=0 ## i64
    while j<out_count && found<0
      if used[j]==0 && fftc_same_term(source_u[i],source_v[i],source_w[i],out_u[j],out_v[j],out_w[j])==1
        found=j
      j+=1
    if found>=0
      used[found]=1
    else
      du[ds]=source_u[i]; dv[ds]=source_v[i]; dw[ds]=source_w[i]; ds+=1
    i+=1
  od=0 ## i64
  i=0
  while i<out_count
    if used[i]==0
      ou[od]=out_u[i]; ov[od]=out_v[i]; ow[od]=out_w[i]; od+=1
    i+=1
  if ds==2 && od==2
    return fflrs_is_one_flip(du,dv,dw,2,ou,ov,ow)
  supported=0 ## i64
  if ds==3 && od>=2 && od<=4
    supported=1
  if ds==4 && (od==3 || od==4)
    supported=1
  if supported==0
    return 0
  i=0
  while i<od
    if ffccb_in_span(du,ds,ou[i])==0 || ffccb_in_span(dv,ds,ov[i])==0 || ffccb_in_span(dw,ds,ow[i])==0
      return 0
    i+=1
  1

-> ffccb_fingerprint(us,vs,ws,count) (i64[] i64[] i64[] i64) i64
  fp=0 ## i64
  i=0 ## i64
  while i<count
    fp=fp^ffw_term_zobrist(us[i],vs[i],ws[i])
    i+=1
  fp

-> ffccb_unique(values,count,value) (i64[] i64 i64) i64
  i=0 ## i64
  while i<count
    if values[i]==value
      return count
    i+=1
  if count<values.size()
    values[count]=value
    return count+1
  count

-> ffccb_run(label,path,n,m,p,rectangular,windows,max_sequences) (String String i64 i64 i64 i64 i64 i64) i64
  capacity=ffw_default_capacity(n) ## i64
  if rectangular!=0
    capacity=ffr_default_capacity(n,m,p)
  state=i64[ffw_state_size(capacity)]
  rank=0 ## i64
  if rectangular==0
    rank=ffw_load_scheme_cap(state,path,n,capacity,93001,0,1,1,1)
    if rank<1 || ffw_verify_best_exact(state,n)!=1
      << "MACRO_COMMUTATOR tensor="+label+" error=load"
      return 0
  else
    rank=ffr_load_scheme_cap(state,path,n,m,p,capacity,93001,0,1,1,1)
    if rank<1 || ffr_verify_best_exact(state,n,m,p)!=1
      << "MACRO_COMMUTATOR tensor="+label+" error=load"
      return 0
  us=i64[capacity]; vs=i64[capacity]; ws=i64[capacity]
  z=ffw_export_best(state,us,vs,ws)
  source_density=fftc_density(us,vs,ws,rank) ## i64
  attempts=0 ## i64
  hits=0 ## i64
  exact=0 ## i64
  span4=0 ## i64
  beyond=0 ## i64
  density_wins=0 ## i64
  best_density=source_density ## i64
  max_distance=0 ## i64
  sequences=0 ## i64
  inverse_closes=0 ## i64
  changed_endpoints=0 ## i64
  target_endpoints=0 ## i64
  simple_sequences=0 ## i64
  simple_hits=0 ## i64
  simple_span4=0 ## i64
  simple_beyond=0 ## i64
  resolved_attempts=0 ## i64
  resolved_cleanup=0 ## i64
  resolved_hits=0 ## i64
  resolved_exact=0 ## i64
  resolved_span4=0 ## i64
  resolved_beyond=0 ## i64
  resolved_density_wins=0 ## i64
  resolved_best_density=source_density ## i64
  resolved_max_distance=0 ## i64
  resolved_fingerprints=i64[windows*120+1]
  resolved_unique=0 ## i64
  resolved6_attempts=0 ## i64
  resolved6_cleanup=0 ## i64
  resolved6_hits=0 ## i64
  resolved6_exact=0 ## i64
  resolved6_beyond=0 ## i64
  resolved6_density_wins=0 ## i64
  resolved6_best_density=source_density ## i64
  resolved6_max_distance=0 ## i64
  resolved7_attempts=0 ## i64
  resolved7_cleanup=0 ## i64
  resolved7_hits=0 ## i64
  resolved7_exact=0 ## i64
  resolved7_beyond=0 ## i64
  resolved7_density_wins=0 ## i64
  resolved7_best_density=source_density ## i64
  resolved7_max_distance=0 ## i64
  selected=i64[5];lu=i64[5];lv=i64[5];lw=i64[5]
  simple_u=i64[5];simple_v=i64[5];simple_w=i64[5]
  simple_recipe=i64[14];simple_stats=i64[12]
  resolved_u=i64[5];resolved_v=i64[5];resolved_w=i64[5]
  resolved_recipe=i64[20];resolved_stats=i64[20]
  out_u=i64[5];out_v=i64[5];out_w=i64[5]
  recipe=i64[18];stats=i64[14]
  candidate_u=i64[capacity];candidate_v=i64[capacity];candidate_w=i64[capacity]
  child=i64[ffw_state_size(capacity)]
  resolved_candidate_u=i64[capacity];resolved_candidate_v=i64[capacity];resolved_candidate_w=i64[capacity]
  resolved_child=i64[ffw_state_size(capacity)]
  selected6=i64[6];l6u=i64[6];l6v=i64[6];l6w=i64[6]
  r6u=i64[6];r6v=i64[6];r6w=i64[6];r6recipe=i64[20];r6stats=i64[20]
  r6candidate_u=i64[capacity];r6candidate_v=i64[capacity];r6candidate_w=i64[capacity]
  r6child=i64[ffw_state_size(capacity)]
  selected7=i64[6];l7u=i64[6];l7v=i64[6];l7w=i64[6]
  r7u=i64[6];r7v=i64[6];r7w=i64[6];r7recipe=i64[24];r7stats=i64[24]
  r7candidate_u=i64[capacity];r7candidate_v=i64[capacity];r7candidate_w=i64[capacity]
  r7child=i64[ffw_state_size(capacity)]
  fingerprints=i64[windows*30+1]
  unique=0 ## i64
  first_recipe=i64[18]
  first_beyond=0 ## i64
  start=ccall("__w_clock_ms") ## i64
  wi=0 ## i64
  while wi<windows
    z=ffccb_window(us,vs,ws,rank,wi,5,selected)
    z=ffccb_capture(us,vs,ws,selected,5,lu,lv,lw)
    focus=0 ## i64
    while focus<5
      axis=0 ## i64
      while axis<3
        other=0 ## i64
        while other<5
          mode=0 ## i64
          while mode<2
            target=ffmh_axis_get(lu,lv,lw,other,axis) ## i64
            if mode==1
              target=target^ffmh_axis_get(lu,lv,lw,focus,axis)
            focus_factor = ffmh_axis_get(lu,lv,lw,focus,axis) ## i64
            if target > 0 && target != focus_factor
              attempts+=1
              simple_count=ffcc_search_target(lu,lv,lw,5,focus,axis,target,10000,simple_u,simple_v,simple_w,simple_recipe,simple_stats) ## i64
              simple_sequences+=simple_stats[0]
              if simple_count==5 && simple_stats[11]==1
                simple_hits+=1
                if ffccb_span4_covered(lu,lv,lw,5,simple_u,simple_v,simple_w,5)==1
                  simple_span4+=1
                else
                  simple_beyond+=1
              anchor=0 ## i64
              while anchor<5
                if anchor != focus && label != "2x2x9"
                  resolved_attempts+=1
                  resolved_count=ffrc_search_target(lu,lv,lw,5,focus,axis,target,anchor,max_sequences,resolved_u,resolved_v,resolved_w,resolved_recipe,resolved_stats) ## i64
                  resolved_cleanup+=resolved_stats[6]
                  if resolved_count==5 && resolved_stats[14]==1
                    resolved_hits+=1
                    resolved_covered=ffccb_span4_covered(lu,lv,lw,5,resolved_u,resolved_v,resolved_w,5) ## i64
                    if resolved_covered==1
                      resolved_span4+=1
                    else
                      resolved_beyond+=1
                    resolved_rank=ffccb_splice(us,vs,ws,rank,selected,5,resolved_u,resolved_v,resolved_w,5,resolved_candidate_u,resolved_candidate_v,resolved_candidate_w,capacity) ## i64
                    resolved_loaded=0 ## i64
                    resolved_verified=0 ## i64
                    if rectangular==0
                      resolved_loaded=ffw_init_terms_cap(resolved_child,resolved_candidate_u,resolved_candidate_v,resolved_candidate_w,resolved_rank,n,capacity,95001+resolved_hits,0,1,1,1)
                      if resolved_loaded==resolved_rank
                        resolved_verified=ffw_verify_best_exact(resolved_child,n)
                    else
                      resolved_loaded=ffr_init_terms_cap(resolved_child,resolved_candidate_u,resolved_candidate_v,resolved_candidate_w,resolved_rank,n,m,p,capacity,95001+resolved_hits,0,1,1,1)
                      if resolved_loaded==resolved_rank
                        resolved_verified=ffr_verify_best_exact(resolved_child,n,m,p)
                    if resolved_verified==1
                      resolved_exact+=1
                      resolved_unique=ffccb_unique(resolved_fingerprints,resolved_unique,ffccb_fingerprint(resolved_candidate_u,resolved_candidate_v,resolved_candidate_w,resolved_rank))
                      resolved_density=fftc_density(resolved_candidate_u,resolved_candidate_v,resolved_candidate_w,resolved_rank) ## i64
                      if resolved_density<resolved_best_density
                        resolved_best_density=resolved_density
                      if resolved_rank==rank && resolved_density<source_density
                        resolved_density_wins+=1
                      if resolved_recipe[12]>resolved_max_distance
                        resolved_max_distance=resolved_recipe[12]
                anchor+=1
              out_count=ffcc3_search_target(lu,lv,lw,5,focus,axis,target,max_sequences,out_u,out_v,out_w,recipe,stats) ## i64
              sequences+=stats[0]
              inverse_closes+=stats[5]
              changed_endpoints+=stats[7]
              target_endpoints+=stats[8]
              if out_count==5 && stats[11]==1
                hits+=1
                covered=ffccb_span4_covered(lu,lv,lw,5,out_u,out_v,out_w,5) ## i64
                if covered==1
                  span4+=1
                else
                  beyond+=1
                candidate_rank=ffccb_splice(us,vs,ws,rank,selected,5,out_u,out_v,out_w,5,candidate_u,candidate_v,candidate_w,capacity) ## i64
                loaded=0 ## i64
                verified=0 ## i64
                if rectangular==0
                  loaded=ffw_init_terms_cap(child,candidate_u,candidate_v,candidate_w,candidate_rank,n,capacity,94001+hits,0,1,1,1)
                  if loaded==candidate_rank
                    verified=ffw_verify_best_exact(child,n)
                else
                  loaded=ffr_init_terms_cap(child,candidate_u,candidate_v,candidate_w,candidate_rank,n,m,p,capacity,94001+hits,0,1,1,1)
                  if loaded==candidate_rank
                    verified=ffr_verify_best_exact(child,n,m,p)
                if verified==1
                  exact+=1
                  unique=ffccb_unique(fingerprints,unique,ffccb_fingerprint(candidate_u,candidate_v,candidate_w,candidate_rank))
                  density=fftc_density(candidate_u,candidate_v,candidate_w,candidate_rank) ## i64
                  if density<best_density
                    best_density=density
                  if candidate_rank==rank && density<source_density
                    density_wins+=1
                  if recipe[9]>max_distance
                    max_distance=recipe[9]
                  if covered==0 && first_beyond==0
                    first_beyond=1
                    ri=0 ## i64
                    while ri<18
                      first_recipe[ri]=recipe[ri]
                      ri+=1
            mode+=1
          other+=1
        axis+=1
      focus+=1
    wi+=1
  # Six labels allow five changed terms after restoring the anchor.  This is
  # the first resolved word that can leave a complete <=4-term span-refactor
  # neighborhood, so report it separately from the five-label control above.
  wi=0
  while wi<windows && label != "2x2x9"
    z=ffccb_window(us,vs,ws,rank,1000+wi,6,selected6)
    z=ffccb_capture(us,vs,ws,selected6,6,l6u,l6v,l6w)
    focus6=0 ## i64
    while focus6<6
      axis6=0 ## i64
      while axis6<3
        other6=0 ## i64
        while other6<6
          mode6=0 ## i64
          while mode6<2
            target6=ffmh_axis_get(l6u,l6v,l6w,other6,axis6) ## i64
            if mode6==1
              target6=target6^ffmh_axis_get(l6u,l6v,l6w,focus6,axis6)
            if target6 > 0 && target6 != ffmh_axis_get(l6u,l6v,l6w,focus6,axis6)
              anchor6=0 ## i64
              while anchor6<6
                if anchor6 != focus6
                  resolved6_attempts+=1
                  r6count=ffrc_search_target(l6u,l6v,l6w,6,focus6,axis6,target6,anchor6,max_sequences,r6u,r6v,r6w,r6recipe,r6stats) ## i64
                  resolved6_cleanup+=r6stats[6]
                  if r6count==6 && r6stats[14]==1
                    resolved6_hits+=1
                    r6covered=ffccb_span4_covered(l6u,l6v,l6w,6,r6u,r6v,r6w,6) ## i64
                    if r6covered==0
                      resolved6_beyond+=1
                    r6rank=ffccb_splice(us,vs,ws,rank,selected6,6,r6u,r6v,r6w,6,r6candidate_u,r6candidate_v,r6candidate_w,capacity) ## i64
                    r6loaded=0 ## i64
                    r6verified=0 ## i64
                    if rectangular==0
                      r6loaded=ffw_init_terms_cap(r6child,r6candidate_u,r6candidate_v,r6candidate_w,r6rank,n,capacity,96001+resolved6_hits,0,1,1,1)
                      if r6loaded==r6rank
                        r6verified=ffw_verify_best_exact(r6child,n)
                    else
                      r6loaded=ffr_init_terms_cap(r6child,r6candidate_u,r6candidate_v,r6candidate_w,r6rank,n,m,p,capacity,96001+resolved6_hits,0,1,1,1)
                      if r6loaded==r6rank
                        r6verified=ffr_verify_best_exact(r6child,n,m,p)
                    if r6verified==1
                      resolved6_exact+=1
                      r6density=fftc_density(r6candidate_u,r6candidate_v,r6candidate_w,r6rank) ## i64
                      if r6density<resolved6_best_density
                        resolved6_best_density=r6density
                      if r6rank==rank && r6density<source_density
                        resolved6_density_wins+=1
                      if r6recipe[12]>resolved6_max_distance
                        resolved6_max_distance=r6recipe[12]
                anchor6+=1
            mode6+=1
          other6+=1
        axis6+=1
      focus6+=1
    wi+=1
  # Decision sample for the seven-edge word.  Stop after sixteen endpoints;
  # each call has a larger one-million cleanup envelope, so this measures
  # whether the additional support actually buys a new neighborhood.
  wi=0
  while wi<windows && resolved7_hits<16 && label != "2x2x9"
    z=ffccb_window(us,vs,ws,rank,2000+wi,6,selected7)
    z=ffccb_capture(us,vs,ws,selected7,6,l7u,l7v,l7w)
    focus7=0 ## i64
    while focus7<6 && resolved7_hits<16
      axis7=0 ## i64
      while axis7<3 && resolved7_hits<16
        other7=0 ## i64
        while other7<6 && resolved7_hits<16
          mode7=0 ## i64
          while mode7<2 && resolved7_hits<16
            target7=ffmh_axis_get(l7u,l7v,l7w,other7,axis7) ## i64
            if mode7==1
              target7=target7^ffmh_axis_get(l7u,l7v,l7w,focus7,axis7)
            if target7 > 0 && target7 != ffmh_axis_get(l7u,l7v,l7w,focus7,axis7)
              anchor7=0 ## i64
              while anchor7<6 && resolved7_hits<16
                if anchor7 != focus7
                  resolved7_attempts+=1
                  r7count=ffrc7_search_target(l7u,l7v,l7w,6,focus7,axis7,target7,anchor7,1000000,r7u,r7v,r7w,r7recipe,r7stats) ## i64
                  resolved7_cleanup+=r7stats[8]
                  if r7count==6 && r7stats[17]==1
                    resolved7_hits+=1
                    r7covered=ffccb_span4_covered(l7u,l7v,l7w,6,r7u,r7v,r7w,6) ## i64
                    if r7covered==0
                      resolved7_beyond+=1
                    r7rank=ffccb_splice(us,vs,ws,rank,selected7,6,r7u,r7v,r7w,6,r7candidate_u,r7candidate_v,r7candidate_w,capacity) ## i64
                    r7loaded=0 ## i64
                    r7verified=0 ## i64
                    if rectangular==0
                      r7loaded=ffw_init_terms_cap(r7child,r7candidate_u,r7candidate_v,r7candidate_w,r7rank,n,capacity,97001+resolved7_hits,0,1,1,1)
                      if r7loaded==r7rank
                        r7verified=ffw_verify_best_exact(r7child,n)
                    else
                      r7loaded=ffr_init_terms_cap(r7child,r7candidate_u,r7candidate_v,r7candidate_w,r7rank,n,m,p,capacity,97001+resolved7_hits,0,1,1,1)
                      if r7loaded==r7rank
                        r7verified=ffr_verify_best_exact(r7child,n,m,p)
                    if r7verified==1
                      resolved7_exact+=1
                      r7density=fftc_density(r7candidate_u,r7candidate_v,r7candidate_w,r7rank) ## i64
                      if r7density<resolved7_best_density
                        resolved7_best_density=r7density
                      if r7rank==rank && r7density<source_density
                        resolved7_density_wins+=1
                      if r7recipe[14]>resolved7_max_distance
                        resolved7_max_distance=r7recipe[14]
                anchor7+=1
            mode7+=1
          other7+=1
        axis7+=1
      focus7+=1
    wi+=1
  elapsed=ccall("__w_clock_ms")-start ## i64
  << "MACRO_COMMUTATOR tensor="+label+" rank="+rank.to_s()+" density="+source_density.to_s()+" windows="+windows.to_s()+" targets="+attempts.to_s()+" simple_sequences="+simple_sequences.to_s()+" simple_hits="+simple_hits.to_s()+" simple_span4="+simple_span4.to_s()+" simple_beyond_span4="+simple_beyond.to_s()+" ribbon_sequences="+sequences.to_s()+" inverse_closes="+inverse_closes.to_s()+" changed="+changed_endpoints.to_s()+" target_endpoints="+target_endpoints.to_s()+" hits="+hits.to_s()+" exact="+exact.to_s()+" unique="+unique.to_s()+" span4="+span4.to_s()+" beyond_span4="+beyond.to_s()+" density_wins="+density_wins.to_s()+" best_density="+best_density.to_s()+" max_distance="+max_distance.to_s()+" resolved_attempts="+resolved_attempts.to_s()+" resolved_cleanup="+resolved_cleanup.to_s()+" resolved_hits="+resolved_hits.to_s()+" resolved_exact="+resolved_exact.to_s()+" resolved_unique="+resolved_unique.to_s()+" resolved_span4="+resolved_span4.to_s()+" resolved_beyond="+resolved_beyond.to_s()+" resolved_density_wins="+resolved_density_wins.to_s()+" resolved_best_density="+resolved_best_density.to_s()+" resolved_max_distance="+resolved_max_distance.to_s()+" resolved6_attempts="+resolved6_attempts.to_s()+" resolved6_cleanup="+resolved6_cleanup.to_s()+" resolved6_hits="+resolved6_hits.to_s()+" resolved6_exact="+resolved6_exact.to_s()+" resolved6_beyond="+resolved6_beyond.to_s()+" resolved6_density_wins="+resolved6_density_wins.to_s()+" resolved6_best_density="+resolved6_best_density.to_s()+" resolved6_max_distance="+resolved6_max_distance.to_s()+" resolved7_attempts="+resolved7_attempts.to_s()+" resolved7_cleanup="+resolved7_cleanup.to_s()+" resolved7_hits="+resolved7_hits.to_s()+" resolved7_exact="+resolved7_exact.to_s()+" resolved7_beyond="+resolved7_beyond.to_s()+" resolved7_density_wins="+resolved7_density_wins.to_s()+" resolved7_best_density="+resolved7_best_density.to_s()+" resolved7_max_distance="+resolved7_max_distance.to_s()+" first_length="+first_recipe[0].to_s()+" first_recipe="+first_recipe[1].to_s()+","+first_recipe[2].to_s()+","+first_recipe[3].to_s()+","+first_recipe[4].to_s()+" ms="+elapsed.to_s()
  1

root=__DIR__+"/../lib/metaflip/seeds/gf2/"
z=ffccb_run("5x5x5",root+"matmul_5x5_rank93_d967_four_split_control_gf2.txt",5,5,5,0,24,40000) ## i64
z=ffccb_run("2x2x9",root+"matmul_2x2x9_rank32_d156_perminov_2025_gf2.txt",2,2,9,1,4,40000)
