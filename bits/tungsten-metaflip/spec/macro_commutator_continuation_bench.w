# Matched continuation decision bench for the two macro words that leave the
# complete <=4-term local span neighborhood.  Each macro door is compared to
# both the source and a seven-ordinary-flip endpoint from the same window,
# selected to match the macro's starting density as closely as possible.

use ../lib/metaflip/rect
use ../lib/metaflip/strategies/macro_commutator
use ../lib/metaflip/strategies/macro_resolved_commutator
use ../lib/metaflip/strategies/low_rank_shear

-> ffmccb_selected(selected,count,value) (i64[] i64 i64) i64
  i=0 ## i64
  while i<count
    if selected[i]==value
      return 1
    i+=1
  0

-> ffmccb_window(us,vs,ws,rank,nonce,count,selected) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
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
      if ffmccb_selected(selected,made,candidate)==0
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

-> ffmccb_capture(us,vs,ws,selected,count,out_u,out_v,out_w) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  i=0 ## i64
  while i<count
    out_u[i]=us[selected[i]]
    out_v[i]=vs[selected[i]]
    out_w[i]=ws[selected[i]]
    i+=1
  count

-> ffmccb_toggle(us,vs,ws,count,capacity,u,v,w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  i=0 ## i64
  while i<count
    if fftc_same_term(us[i],vs[i],ws[i],u,v,w)==1
      last=count-1 ## i64
      us[i]=us[last]
      vs[i]=vs[last]
      ws[i]=ws[last]
      return count-1
    i+=1
  if count>=capacity || u==0 || v==0 || w==0
    return 0-count-1
  us[count]=u
  vs[count]=v
  ws[count]=w
  count+1

-> ffmccb_splice(us,vs,ws,rank,selected,k,local_u,local_v,local_w,local_count,out_u,out_v,out_w,capacity) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  count=0 ## i64
  i=0 ## i64
  while i<rank
    if ffmccb_selected(selected,k,i)==0
      count=ffmccb_toggle(out_u,out_v,out_w,count,capacity,us[i],vs[i],ws[i])
      if count<0
        return 0
    i+=1
  i=0
  while i<local_count
    count=ffmccb_toggle(out_u,out_v,out_w,count,capacity,local_u[i],local_v[i],local_w[i])
    if count<0
      return 0
    i+=1
  count

-> ffmccb_in_span(values,count,value) (i64[] i64 i64) i64
  basis=i64[count]
  basis_count=ffsr_make_basis(values,count,basis) ## i64
  span=i64[1<<basis_count]
  span_count=ffsr_enumerate_span(basis,basis_count,span) ## i64
  ffsr_contains(span,span_count,value)

-> ffmccb_span4(source_u,source_v,source_w,source_count,out_u,out_v,out_w,out_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  used=i64[out_count]
  du=i64[source_count]
  dv=i64[source_count]
  dw=i64[source_count]
  ou=i64[out_count]
  ov=i64[out_count]
  ow=i64[out_count]
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
      du[ds]=source_u[i]
      dv[ds]=source_v[i]
      dw[ds]=source_w[i]
      ds+=1
    i+=1
  od=0 ## i64
  i=0
  while i<out_count
    if used[i]==0
      ou[od]=out_u[i]
      ov[od]=out_v[i]
      ow[od]=out_w[i]
      od+=1
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
    if ffmccb_in_span(du,ds,ou[i])==0 || ffmccb_in_span(dv,ds,ov[i])==0 || ffmccb_in_span(dw,ds,ow[i])==0
      return 0
    i+=1
  1

-> ffmccb_word7(source_u,source_v,source_w,count,nonce,out_u,out_v,out_w) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[]) i64
  z=ffmh_copy(source_u,source_v,source_w,count,out_u,out_v,out_w) ## i64
  code_count=fftc_code_count(count) ## i64
  prior=0-1 ## i64
  step=0 ## i64
  while step<7
    start=(nonce*131+step*29)%code_count ## i64
    tried=0 ## i64
    moved=0 ## i64
    while tried<code_count && moved==0
      code=(start+tried)%code_count ## i64
      if code != prior
        if fftc_apply_code(out_u,out_v,out_w,count,code,0-1)==1
          moved=1
          prior=code
      tried+=1
    if moved==0
      return 0
    step+=1
  if ffmh_distance(source_u,source_v,source_w,count,out_u,out_v,out_w,count)<1 || ffmh_local_exact(source_u,source_v,source_w,count,out_u,out_v,out_w,count) != 1
    return 0
  count

# Select the closest-density seven-flip ordinary endpoint on the same window.
-> ffmccb_match_control(us,vs,ws,rank,selected,k,local_u,local_v,local_w,desired_density,capacity,out_u,out_v,out_w) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64 i64 i64[] i64[] i64[]) i64
  trial_u=i64[k]
  trial_v=i64[k]
  trial_w=i64[k]
  full_u=i64[capacity]
  full_v=i64[capacity]
  full_w=i64[capacity]
  best_score=1<<30 ## i64
  best_rank=0 ## i64
  nonce=0 ## i64
  while nonce<256 && best_score>0
    local_count=ffmccb_word7(local_u,local_v,local_w,k,nonce,trial_u,trial_v,trial_w) ## i64
    if local_count==k && ffrc_distinct(trial_u,trial_v,trial_w,k)==1
      full_rank=ffmccb_splice(us,vs,ws,rank,selected,k,trial_u,trial_v,trial_w,k,full_u,full_v,full_w,capacity) ## i64
      if full_rank==rank
        density=fftc_density(full_u,full_v,full_w,full_rank) ## i64
        score=density-desired_density ## i64
        if score<0
          score=0-score
        if score<best_score
          best_score=score
          best_rank=full_rank
          z=ffmh_copy(full_u,full_v,full_w,full_rank,out_u,out_v,out_w)
    nonce+=1
  best_rank

-> ffmccb_fingerprint(us,vs,ws,count) (i64[] i64[] i64[] i64) i64
  fp=0 ## i64
  i=0 ## i64
  while i<count
    fp=fp^ffw_term_zobrist(us[i],vs[i],ws[i])
    i+=1
  fp

-> ffmccb_unique(values,count,value) (i64[] i64 i64) i64
  i=0 ## i64
  while i<count
    if values[i]==value
      return count
    i+=1
  if count<values.size()
    values[count]=value
    return count+1
  count

-> ffmccb_continue(label,n,m,p,rectangular,source_u,source_v,source_w,ordinary_u,ordinary_v,ordinary_w,macro_u,macro_v,macro_w,rank,capacity,trials,moves) (String i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  source_wins=0 ## i64
  ordinary_wins=0 ## i64
  macro_wins=0 ## i64
  ties=0 ## i64
  macro_over_ordinary=0 ## i64
  ordinary_over_macro=0 ## i64
  macro_ordinary_ties=0 ## i64
  source_drops=0 ## i64
  ordinary_drops=0 ## i64
  macro_drops=0 ## i64
  source_sum=0 ## i64
  ordinary_sum=0 ## i64
  macro_sum=0 ## i64
  source_best_rank=1<<30 ## i64
  source_best_density=1<<30 ## i64
  ordinary_best_rank=1<<30 ## i64
  ordinary_best_density=1<<30 ## i64
  macro_best_rank=1<<30 ## i64
  macro_best_density=1<<30 ## i64
  source_fp=i64[trials]
  ordinary_fp=i64[trials]
  macro_fp=i64[trials]
  source_unique=0 ## i64
  ordinary_unique=0 ## i64
  macro_unique=0 ## i64
  export_u=i64[capacity]
  export_v=i64[capacity]
  export_w=i64[capacity]
  source_state=i64[ffw_state_size(capacity)]
  ordinary_state=i64[ffw_state_size(capacity)]
  macro_state=i64[ffw_state_size(capacity)]
  started=ccall("__w_clock_ms") ## i64
  trial=0 ## i64
  while trial<trials
    seed=881001+trial*1009 ## i64
    srank=0 ## i64
    orank=0 ## i64
    mrank=0 ## i64
    if rectangular==0
      srank=ffw_init_terms_cap(source_state,source_u,source_v,source_w,rank,n,capacity,seed,4,4,moves / 10,moves / 25)
      orank=ffw_init_terms_cap(ordinary_state,ordinary_u,ordinary_v,ordinary_w,rank,n,capacity,seed,4,4,moves / 10,moves / 25)
      mrank=ffw_init_terms_cap(macro_state,macro_u,macro_v,macro_w,rank,n,capacity,seed,4,4,moves / 10,moves / 25)
    else
      srank=ffr_init_terms_cap(source_state,source_u,source_v,source_w,rank,n,m,p,capacity,seed,4,4,moves / 10,moves / 25)
      orank=ffr_init_terms_cap(ordinary_state,ordinary_u,ordinary_v,ordinary_w,rank,n,m,p,capacity,seed,4,4,moves / 10,moves / 25)
      mrank=ffr_init_terms_cap(macro_state,macro_u,macro_v,macro_w,rank,n,m,p,capacity,seed,4,4,moves / 10,moves / 25)
    if srank != rank || orank != rank || mrank != rank
      << "MACRO_COMMUTATOR_CONTINUE tensor="+label+" error=init"
      return 0
    if rectangular==0
      z=ffw_walk(source_state,moves)
      z=ffw_walk(ordinary_state,moves)
      z=ffw_walk(macro_state,moves)
    else
      z=ffr_walk(source_state,moves)
      z=ffr_walk(ordinary_state,moves)
      z=ffr_walk(macro_state,moves)
    sr=ffw_best_rank(source_state) ## i64
    sb=ffw_best_bits(source_state) ## i64
    obr=ffw_best_rank(ordinary_state) ## i64
    obb=ffw_best_bits(ordinary_state) ## i64
    mr=ffw_best_rank(macro_state) ## i64
    mb=ffw_best_bits(macro_state) ## i64
    if sr<rank
      source_drops+=1
    if obr<rank
      ordinary_drops+=1
    if mr<rank
      macro_drops+=1
    if sr<source_best_rank || (sr==source_best_rank && sb<source_best_density)
      source_best_rank=sr
      source_best_density=sb
    if obr<ordinary_best_rank || (obr==ordinary_best_rank && obb<ordinary_best_density)
      ordinary_best_rank=obr
      ordinary_best_density=obb
    if mr<macro_best_rank || (mr==macro_best_rank && mb<macro_best_density)
      macro_best_rank=mr
      macro_best_density=mb
    source_sum+=sb
    ordinary_sum+=obb
    macro_sum+=mb
    if sr<obr && sr<mr || (sr==obr && sr==mr && sb<obb && sb<mb)
      source_wins+=1
    else
      if obr<sr && obr<mr || (obr==sr && obr==mr && obb<sb && obb<mb)
        ordinary_wins+=1
      else
        if mr<sr && mr<obr || (mr==sr && mr==obr && mb<sb && mb<obb)
          macro_wins+=1
        else
          ties+=1
    if mr<obr || (mr==obr && mb<obb)
      macro_over_ordinary+=1
    else
      if obr<mr || (obr==mr && obb<mb)
        ordinary_over_macro+=1
      else
        macro_ordinary_ties+=1
    z=ffw_export_best(source_state,export_u,export_v,export_w)
    source_unique=ffmccb_unique(source_fp,source_unique,ffmccb_fingerprint(export_u,export_v,export_w,sr))
    z=ffw_export_best(ordinary_state,export_u,export_v,export_w)
    ordinary_unique=ffmccb_unique(ordinary_fp,ordinary_unique,ffmccb_fingerprint(export_u,export_v,export_w,obr))
    z=ffw_export_best(macro_state,export_u,export_v,export_w)
    macro_unique=ffmccb_unique(macro_fp,macro_unique,ffmccb_fingerprint(export_u,export_v,export_w,mr))
    trial+=1
  elapsed=ccall("__w_clock_ms")-started ## i64
  << "MACRO_COMMUTATOR_CONTINUE tensor="+label+" trials="+trials.to_s()+" moves_per_arm="+moves.to_s()+" source_start_density="+fftc_density(source_u,source_v,source_w,rank).to_s()+" ordinary_start_density="+fftc_density(ordinary_u,ordinary_v,ordinary_w,rank).to_s()+" macro_start_density="+fftc_density(macro_u,macro_v,macro_w,rank).to_s()+" source_wins="+source_wins.to_s()+" ordinary_wins="+ordinary_wins.to_s()+" macro_wins="+macro_wins.to_s()+" ties="+ties.to_s()+" macro_over_ordinary="+macro_over_ordinary.to_s()+" ordinary_over_macro="+ordinary_over_macro.to_s()+" macro_ordinary_ties="+macro_ordinary_ties.to_s()+" source_drops="+source_drops.to_s()+" ordinary_drops="+ordinary_drops.to_s()+" macro_drops="+macro_drops.to_s()+" source_best="+source_best_rank.to_s()+"/"+source_best_density.to_s()+" ordinary_best="+ordinary_best_rank.to_s()+"/"+ordinary_best_density.to_s()+" macro_best="+macro_best_rank.to_s()+"/"+macro_best_density.to_s()+" source_mean_density="+(source_sum / trials).to_s()+" ordinary_mean_density="+(ordinary_sum / trials).to_s()+" macro_mean_density="+(macro_sum / trials).to_s()+" source_unique="+source_unique.to_s()+" ordinary_unique="+ordinary_unique.to_s()+" macro_unique="+macro_unique.to_s()+" ms="+elapsed.to_s()
  1

-> ffmccb_square(root,trials,moves) (String i64 i64) i64
  n=5 ## i64
  capacity=ffw_default_capacity(n) ## i64
  state=i64[ffw_state_size(capacity)]
  path=root+"matmul_5x5_rank93_d967_four_split_control_gf2.txt" ## String
  rank=ffw_load_scheme_cap(state,path,n,capacity,77001,0,1,1,1) ## i64
  us=i64[capacity]
  vs=i64[capacity]
  ws=i64[capacity]
  z=ffw_export_best(state,us,vs,ws)
  macro_u=i64[capacity]
  macro_v=i64[capacity]
  macro_w=i64[capacity]
  ordinary_u=i64[capacity]
  ordinary_v=i64[capacity]
  ordinary_w=i64[capacity]
  found=0 ## i64
  wi=0 ## i64
  while wi<24 && found==0
    selected=i64[6]
    z=ffmccb_window(us,vs,ws,rank,2000+wi,6,selected)
    lu=i64[6]
    lv=i64[6]
    lw=i64[6]
    z=ffmccb_capture(us,vs,ws,selected,6,lu,lv,lw)
    focus=0 ## i64
    while focus<6 && found==0
      axis=0 ## i64
      while axis<3 && found==0
        other=0 ## i64
        while other<6 && found==0
          mode=0 ## i64
          while mode<2 && found==0
            target=ffmh_axis_get(lu,lv,lw,other,axis) ## i64
            if mode==1
              target=target^ffmh_axis_get(lu,lv,lw,focus,axis)
            if target > 0 && target != ffmh_axis_get(lu,lv,lw,focus,axis)
              anchor=0 ## i64
              while anchor<6 && found==0
                if anchor != focus
                  out_u=i64[6]
                  out_v=i64[6]
                  out_w=i64[6]
                  recipe=i64[24]
                  stats=i64[24]
                  out_count=ffrc7_search_target(lu,lv,lw,6,focus,axis,target,anchor,1000000,out_u,out_v,out_w,recipe,stats) ## i64
                  if out_count==6 && stats[17]==1 && ffmccb_span4(lu,lv,lw,6,out_u,out_v,out_w,6)==0
                    full_rank=ffmccb_splice(us,vs,ws,rank,selected,6,out_u,out_v,out_w,6,macro_u,macro_v,macro_w,capacity) ## i64
                    if full_rank==rank
                      desired=fftc_density(macro_u,macro_v,macro_w,rank) ## i64
                      ordinary_rank=ffmccb_match_control(us,vs,ws,rank,selected,6,lu,lv,lw,desired,capacity,ordinary_u,ordinary_v,ordinary_w) ## i64
                      if ordinary_rank==rank
                        found=1
                anchor+=1
            mode+=1
          other+=1
        axis+=1
      focus+=1
    wi+=1
  if found==0
    << "MACRO_COMMUTATOR_CONTINUE tensor=5x5 error=no-door"
    return 0
  check=i64[ffw_state_size(capacity)]
  if ffw_init_terms_cap(check,macro_u,macro_v,macro_w,rank,n,capacity,77003,0,1,1,1) != rank || ffw_verify_best_exact(check,n) != 1
    return 0
  ffmccb_continue("5x5-resolved7",5,5,5,0,us,vs,ws,ordinary_u,ordinary_v,ordinary_w,macro_u,macro_v,macro_w,rank,capacity,trials,moves)

-> ffmccb_rect229(root,trials,moves) (String i64 i64) i64
  n=2 ## i64
  m=2 ## i64
  p=9 ## i64
  capacity=ffr_default_capacity(n,m,p) ## i64
  state=i64[ffr_state_size(capacity)]
  path=root+"matmul_2x2x9_rank32_d156_perminov_2025_gf2.txt" ## String
  rank=ffr_load_scheme_cap(state,path,n,m,p,capacity,77201,0,1,1,1) ## i64
  us=i64[capacity]
  vs=i64[capacity]
  ws=i64[capacity]
  z=ffw_export_best(state,us,vs,ws)
  macro_u=i64[capacity]
  macro_v=i64[capacity]
  macro_w=i64[capacity]
  ordinary_u=i64[capacity]
  ordinary_v=i64[capacity]
  ordinary_w=i64[capacity]
  found=0 ## i64
  wi=0 ## i64
  while wi<24 && found==0
    selected=i64[5]
    z=ffmccb_window(us,vs,ws,rank,wi,5,selected)
    lu=i64[5]
    lv=i64[5]
    lw=i64[5]
    z=ffmccb_capture(us,vs,ws,selected,5,lu,lv,lw)
    focus=0 ## i64
    while focus<5 && found==0
      axis=0 ## i64
      while axis<3 && found==0
        other=0 ## i64
        while other<5 && found==0
          mode=0 ## i64
          while mode<2 && found==0
            target=ffmh_axis_get(lu,lv,lw,other,axis) ## i64
            if mode==1
              target=target^ffmh_axis_get(lu,lv,lw,focus,axis)
            if target > 0 && target != ffmh_axis_get(lu,lv,lw,focus,axis)
              out_u=i64[5]
              out_v=i64[5]
              out_w=i64[5]
              recipe=i64[18]
              stats=i64[14]
              out_count=ffcc3_search_target(lu,lv,lw,5,focus,axis,target,40000,out_u,out_v,out_w,recipe,stats) ## i64
              if out_count==5 && stats[11]==1 && ffmccb_span4(lu,lv,lw,5,out_u,out_v,out_w,5)==0
                full_rank=ffmccb_splice(us,vs,ws,rank,selected,5,out_u,out_v,out_w,5,macro_u,macro_v,macro_w,capacity) ## i64
                if full_rank==rank
                  desired=fftc_density(macro_u,macro_v,macro_w,rank) ## i64
                  ordinary_rank=ffmccb_match_control(us,vs,ws,rank,selected,5,lu,lv,lw,desired,capacity,ordinary_u,ordinary_v,ordinary_w) ## i64
                  if ordinary_rank==rank
                    found=1
            mode+=1
          other+=1
        axis+=1
      focus+=1
    wi+=1
  if found==0
    << "MACRO_COMMUTATOR_CONTINUE tensor=2x2x9 error=no-door"
    return 0
  check=i64[ffr_state_size(capacity)]
  if ffr_init_terms_cap(check,macro_u,macro_v,macro_w,rank,n,m,p,capacity,77203,0,1,1,1) != rank || ffr_verify_best_exact(check,n,m,p) != 1
    return 0
  ffmccb_continue("2x2x9-literal7",n,m,p,1,us,vs,ws,ordinary_u,ordinary_v,ordinary_w,macro_u,macro_v,macro_w,rank,capacity,trials,moves)

root=__DIR__+"/../lib/metaflip/seeds/gf2/"
z=ffmccb_square(root,8,20000000) ## i64
z=ffmccb_rect229(root,8,20000000)
