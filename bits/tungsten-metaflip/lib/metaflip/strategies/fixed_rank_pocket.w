# Autonomous fixed-rank flip-pocket escape.
#
# Each ticket starts at one legal equal-factor pair.  A frozen term may enter
# the pocket only through a legal flip with a live pocket term, so selection
# follows the factor-overlap graph created by the word itself.  Bounded BFS
# retains density-debt intermediates atomically; only the exact endpoint is
# reloaded into the worker.  This is a cold coordinator/lease-start strategy,
# never part of the per-move hot path.

use ../scheme

-> ffpa_compare(au,av,aw,bu,bv,bw) (i64 i64 i64 i64 i64 i64) i64
  if au < bu
    return 0 - 1
  if au > bu
    return 1
  if av < bv
    return 0 - 1
  if av > bv
    return 1
  if aw < bw
    return 0 - 1
  if aw > bw
    return 1
  0

-> ffpa_sort_terms(us,vs,ws,count) (i64[] i64[] i64[] i64) i64
  i = 1 ## i64
  while i < count
    u=us[i] ## i64
    v=vs[i] ## i64
    w=ws[i] ## i64
    j=i ## i64
    while j>0 && ffpa_compare(u,v,w,us[j-1],vs[j-1],ws[j-1])<0
      us[j]=us[j-1]
      vs[j]=vs[j-1]
      ws[j]=ws[j-1]
      j-=1
    us[j]=u
    vs[j]=v
    ws[j]=w
    i+=1
  1

-> ffpa_sort_origins(origins,count) (i64[] i64) i64
  i=1 ## i64
  while i<count
    value=origins[i] ## i64
    j=i ## i64
    while j>0 && origins[j-1]>value
      origins[j]=origins[j-1]
      j-=1
    origins[j]=value
    i+=1
  1

-> ffpa_origin_has(origins,base,count,value) (i64[] i64 i64 i64) i64
  i=0 ## i64
  while i<count
    if origins[base+i]==value
      return 1
    i+=1
  0

-> ffpa_copy_terms(su,sv,sw,sbase,du,dv,dw,dbase,count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64) i64
  i=0 ## i64
  while i<count
    du[dbase+i]=su[sbase+i]
    dv[dbase+i]=sv[sbase+i]
    dw[dbase+i]=sw[sbase+i]
    i+=1
  count

-> ffpa_density(us,vs,ws,base,count) (i64[] i64[] i64[] i64 i64) i64
  result=0 ## i64
  i=0 ## i64
  while i<count
    result+=ffw_popcount(us[base+i])+ffw_popcount(vs[base+i])+ffw_popcount(ws[base+i])
    i+=1
  result

-> ffpa_terms_equal(au,av,aw,abase,bu,bv,bw,bbase,count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64) i64
  i=0 ## i64
  while i<count
    if au[abase+i]!=bu[bbase+i] || av[abase+i]!=bv[bbase+i] || aw[abase+i]!=bw[bbase+i]
      return 0
    i+=1
  1

-> ffpa_flip_neighbor(su,sv,sw,sbase,count,left,right,axis,ou,ov,ow) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[]) i64
  if left<0 || right<=left || right>=count || axis<0 || axis>2
    return 0
  ui=su[sbase+left] ## i64
  vi=sv[sbase+left] ## i64
  wi=sw[sbase+left] ## i64
  uj=su[sbase+right] ## i64
  vj=sv[sbase+right] ## i64
  wj=sw[sbase+right] ## i64
  if axis==0 && ui!=uj
    return 0
  if axis==1 && vi!=vj
    return 0
  if axis==2 && wi!=wj
    return 0
  au=ui ## i64
  av=vi ## i64
  aw=wi ## i64
  bu=ui ## i64
  bv=vi ## i64
  bw=wj ## i64
  if axis==0
    aw=wi^wj
    bv=vi^vj
  if axis==1
    aw=wi^wj
    bu=ui^uj
  if axis==2
    av=vi^vj
    bu=ui^uj
    bv=vj
    bw=wi
  if au==0 || av==0 || aw==0 || bu==0 || bv==0 || bw==0
    return 0
  at=0 ## i64
  i=0 ## i64
  while i<count
    if i!=left && i!=right
      ou[at]=su[sbase+i]
      ov[at]=sv[sbase+i]
      ow[at]=sw[sbase+i]
      at+=1
    i+=1
  ou[at]=au
  ov[at]=av
  ow[at]=aw
  at+=1
  ou[at]=bu
  ov[at]=bv
  ow[at]=bw
  at+=1
  ffpa_sort_terms(ou,ov,ow,at)
  i=1
  while i<at
    if ou[i]==ou[i-1] && ov[i]==ov[i-1] && ow[i]==ow[i-1]
      return 0
    i+=1
  at

-> ffpa_ticket_count(us,vs,ws,count) (i64[] i64[] i64[] i64) i64
  total=0 ## i64
  left=0 ## i64
  while left<count-1
    right=left+1 ## i64
    while right<count
      if us[left]==us[right]
        total+=1
      if vs[left]==vs[right]
        total+=1
      if ws[left]==ws[right]
        total+=1
      right+=1
    left+=1
  total

# Success is exactly 1 and miss exactly 0; count is deliberately separate so
# a one-ticket source cannot alias an out-of-range lookup.
-> ffpa_ticket(us,vs,ws,count,wanted,out) (i64[] i64[] i64[] i64 i64 i64[]) i64
  seen=0 ## i64
  left=0 ## i64
  while left<count-1
    right=left+1 ## i64
    while right<count
      axis=0 ## i64
      while axis<3
        equal=0 ## i64
        if axis==0 && us[left]==us[right]
          equal=1
        if axis==1 && vs[left]==vs[right]
          equal=1
        if axis==2 && ws[left]==ws[right]
          equal=1
        if equal==1
          if seen==wanted
            out[0]=left
            out[1]=right
            out[2]=axis
            return 1
          seen+=1
        axis+=1
      right+=1
    left+=1
  0

-> ffpa_frozen_collision(su,sv,sw,source_count,origins,origin_count,cu,cv,cw,count) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64) i64
  i=0 ## i64
  while i<count
    slot=0 ## i64
    while slot<source_count
      if ffpa_origin_has(origins,0,origin_count,slot)==0
        if cu[i]==su[slot] && cv[i]==sv[slot] && cw[i]==sw[slot]
          return 1
      slot+=1
    i+=1
  0

-> ffpa_state_equal(states_u,states_v,states_w,states_origins,base,state_count,cu,cv,cw,origins,count) (i64[] i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64) i64
  if state_count!=count || ffpa_terms_equal(states_u,states_v,states_w,base,cu,cv,cw,0,count)!=1
    return 0
  i=0 ## i64
  while i<count
    if states_origins[base+i]!=origins[i]
      return 0
    i+=1
  1

-> ffpa_hash_mix(hash,value) (i64 i64) i64
  x=value^(value>>21)^(value>>42) ## i64
  ((hash^x)*2654435761+40503)&9223372036854775807

-> ffpa_state_hash(us,vs,ws,tbase,origins,obase,count) (i64[] i64[] i64[] i64 i64[] i64 i64) i64
  hash=ffpa_hash_mix(1469598103934665603,count) ## i64
  i=0 ## i64
  while i<count
    hash=ffpa_hash_mix(hash,origins[obase+i]+1)
    hash=ffpa_hash_mix(hash,us[tbase+i])
    hash=ffpa_hash_mix(hash,vs[tbase+i])
    hash=ffpa_hash_mix(hash,ws[tbase+i])
    i+=1
  hash

-> ffpa_seen(states_u,states_v,states_w,states_origins,counts,stride,cu,cv,cw,origins,count,hash,heads,nexts,mask) (i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64 i64[] i64[] i64) i64
  cursor=heads[hash&mask] ## i64
  while cursor!=0
    state=cursor-1 ## i64
    if ffpa_state_equal(states_u,states_v,states_w,states_origins,state*stride,counts[state],cu,cv,cw,origins,count)==1
      return state
    cursor=nexts[state]
  0-1

-> ffpa_link(heads,nexts,mask,state,hash) (i64[] i64[] i64 i64 i64) i64
  bucket=hash&mask ## i64
  nexts[state]=heads[bucket]
  heads[bucket]=state+1
  1

# stats: states, proposals, legal, duplicates, frozen collisions, best gain,
# best depth, best terms, max edge rise, cap exhausted, barrier prunes,
# endpoint density, replaced-source density.
-> ffpa_search(su,sv,sw,source_count,ticket,max_terms,max_depth,max_states,max_edge_uphill,endpoint_u,endpoint_v,endpoint_w,endpoint_origins,stats) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  i=0 ## i64
  while i<stats.size()
    stats[i]=0
    i+=1
  if source_count<2 || max_terms<2 || max_terms>8 || max_depth<1 || max_states<1 || stats.size()<13
    return 0
  ticket_info=i64[3]
  if ffpa_ticket(su,sv,sw,source_count,ticket,ticket_info)!=1
    return 0
  stride=max_terms ## i64
  states_u=i64[max_states*stride]
  states_v=i64[max_states*stride]
  states_w=i64[max_states*stride]
  states_origins=i64[max_states*stride]
  counts=i64[max_states]
  depths=i64[max_states]
  densities=i64[max_states]
  source_densities=i64[max_states]
  max_rises=i64[max_states]
  hash_capacity=16 ## i64
  while hash_capacity<max_states*2
    hash_capacity*=2
  heads=i64[hash_capacity]
  nexts=i64[max_states]
  hash_mask=hash_capacity-1 ## i64

  left=ticket_info[0] ## i64
  right=ticket_info[1] ## i64
  states_u[0]=su[left]
  states_v[0]=sv[left]
  states_w[0]=sw[left]
  states_u[1]=su[right]
  states_v[1]=sv[right]
  states_w[1]=sw[right]
  ffpa_sort_terms(states_u,states_v,states_w,2)
  states_origins[0]=left
  states_origins[1]=right
  ffpa_sort_origins(states_origins,2)
  counts[0]=2
  densities[0]=ffpa_density(states_u,states_v,states_w,0,2)
  source_densities[0]=densities[0]
  root_hash=ffpa_state_hash(states_u,states_v,states_w,0,states_origins,0,2) ## i64
  ffpa_link(heads,nexts,hash_mask,0,root_hash)
  total=1 ## i64
  head=0 ## i64
  best=0 ## i64
  stats[0]=1
  scratch_u=i64[max_terms]
  scratch_v=i64[max_terms]
  scratch_w=i64[max_terms]
  scratch_origins=i64[max_terms]
  input_u=i64[max_terms]
  input_v=i64[max_terms]
  input_w=i64[max_terms]

  while head<total
    count=counts[head] ## i64
    base=head*stride ## i64
    if depths[head]<max_depth
      pair_left=0 ## i64
      while pair_left<count-1
        pair_right=pair_left+1 ## i64
        while pair_right<count
          axis=0 ## i64
          while axis<3
            stats[1]=stats[1]+1
            made=ffpa_flip_neighbor(states_u,states_v,states_w,base,count,pair_left,pair_right,axis,scratch_u,scratch_v,scratch_w) ## i64
            if made==count
              stats[2]=stats[2]+1
              i=0
              while i<count
                scratch_origins[i]=states_origins[base+i]
                i+=1
              candidate_density=ffpa_density(scratch_u,scratch_v,scratch_w,0,count) ## i64
              rise=candidate_density-densities[head] ## i64
              allowed=1 ## i64
              if max_edge_uphill>=0 && rise>max_edge_uphill
                allowed=0
                stats[10]=stats[10]+1
              if allowed==1 && ffpa_frozen_collision(su,sv,sw,source_count,scratch_origins,count,scratch_u,scratch_v,scratch_w,count)==1
                allowed=0
                stats[4]=stats[4]+1
              if allowed==1
                candidate_hash=ffpa_state_hash(scratch_u,scratch_v,scratch_w,0,scratch_origins,0,count) ## i64
                prior=ffpa_seen(states_u,states_v,states_w,states_origins,counts,stride,scratch_u,scratch_v,scratch_w,scratch_origins,count,candidate_hash,heads,nexts,hash_mask) ## i64
                if prior>=0
                  stats[3]=stats[3]+1
                if prior<0
                  if total>=max_states
                    stats[9]=1
                  if total<max_states
                    target_base=total*stride ## i64
                    ffpa_copy_terms(scratch_u,scratch_v,scratch_w,0,states_u,states_v,states_w,target_base,count)
                    i=0
                    while i<count
                      states_origins[target_base+i]=scratch_origins[i]
                      i+=1
                    counts[total]=count
                    depths[total]=depths[head]+1
                    densities[total]=candidate_density
                    source_densities[total]=source_densities[head]
                    max_rises[total]=max_rises[head]
                    if rise>max_rises[total]
                      max_rises[total]=rise
                    gain=source_densities[total]-candidate_density ## i64
                    best_gain=source_densities[best]-densities[best] ## i64
                    if gain>best_gain
                      best=total
                    ffpa_link(heads,nexts,hash_mask,total,candidate_hash)
                    total+=1
                    stats[0]=total
            axis+=1
          pair_right+=1
        pair_left+=1

      if count<max_terms
        local=0 ## i64
        while local<count
          source_slot=0 ## i64
          while source_slot<source_count
            if ffpa_origin_has(states_origins,base,count,source_slot)==0
              ffpa_copy_terms(states_u,states_v,states_w,base,input_u,input_v,input_w,0,count)
              input_u[count]=su[source_slot]
              input_v[count]=sv[source_slot]
              input_w[count]=sw[source_slot]
              i=0
              while i<count
                scratch_origins[i]=states_origins[base+i]
                i+=1
              scratch_origins[count]=source_slot
              ffpa_sort_origins(scratch_origins,count+1)
              axis=0
              while axis<3
                stats[1]=stats[1]+1
                made=ffpa_flip_neighbor(input_u,input_v,input_w,0,count+1,local,count,axis,scratch_u,scratch_v,scratch_w) ## i64
                if made==count+1
                  stats[2]=stats[2]+1
                  candidate_density=ffpa_density(scratch_u,scratch_v,scratch_w,0,count+1) ## i64
                  candidate_source_density=source_densities[head]+ffw_popcount(su[source_slot])+ffw_popcount(sv[source_slot])+ffw_popcount(sw[source_slot]) ## i64
                  parent_delta=densities[head]-source_densities[head] ## i64
                  candidate_delta=candidate_density-candidate_source_density ## i64
                  rise=candidate_delta-parent_delta ## i64
                  allowed=1 ## i64
                  if max_edge_uphill>=0 && rise>max_edge_uphill
                    allowed=0
                    stats[10]=stats[10]+1
                  if allowed==1 && ffpa_frozen_collision(su,sv,sw,source_count,scratch_origins,count+1,scratch_u,scratch_v,scratch_w,count+1)==1
                    allowed=0
                    stats[4]=stats[4]+1
                  if allowed==1
                    candidate_hash=ffpa_state_hash(scratch_u,scratch_v,scratch_w,0,scratch_origins,0,count+1) ## i64
                    prior=ffpa_seen(states_u,states_v,states_w,states_origins,counts,stride,scratch_u,scratch_v,scratch_w,scratch_origins,count+1,candidate_hash,heads,nexts,hash_mask) ## i64
                    if prior>=0
                      stats[3]=stats[3]+1
                    if prior<0
                      if total>=max_states
                        stats[9]=1
                      if total<max_states
                        target_base=total*stride ## i64
                        ffpa_copy_terms(scratch_u,scratch_v,scratch_w,0,states_u,states_v,states_w,target_base,count+1)
                        i=0
                        while i<count+1
                          states_origins[target_base+i]=scratch_origins[i]
                          i+=1
                        counts[total]=count+1
                        depths[total]=depths[head]+1
                        densities[total]=candidate_density
                        source_densities[total]=candidate_source_density
                        max_rises[total]=max_rises[head]
                        if rise>max_rises[total]
                          max_rises[total]=rise
                        gain=candidate_source_density-candidate_density ## i64
                        best_gain=source_densities[best]-densities[best] ## i64
                        if gain>best_gain
                          best=total
                        ffpa_link(heads,nexts,hash_mask,total,candidate_hash)
                        total+=1
                        stats[0]=total
                axis+=1
            source_slot+=1
          local+=1
    head+=1

  best_count=counts[best] ## i64
  best_base=best*stride ## i64
  ffpa_copy_terms(states_u,states_v,states_w,best_base,endpoint_u,endpoint_v,endpoint_w,0,best_count)
  i=0
  while i<best_count
    endpoint_origins[i]=states_origins[best_base+i]
    i+=1
  stats[5]=source_densities[best]-densities[best]
  stats[6]=depths[best]
  stats[7]=best_count
  stats[8]=max_rises[best]
  stats[11]=densities[best]
  stats[12]=source_densities[best]
  stats[5]

# Apply one ticket to the worker's exact best. Returns 1 only when a strictly
# lower-density exact fixed-rank endpoint replaces the state; misses and
# rejected endpoints leave the represented decomposition unchanged (the usual
# exact-check/export counters may advance). `meta` receives search stats plus
# [13]=ticket count and [14]=selected ticket.
-> ffpa_apply_ticket(state,ticket,max_terms,max_depth,max_states,max_edge_uphill,meta) (i64[] i64 i64 i64 i64 i64 i64[]) i64
  if meta.size()>=15
    i=0 ## i64
    while i<meta.size()
      meta[i]=0
      i+=1
  # Keep the resident API deliberately narrower than the offline search API:
  # no unbounded barrier, depth, or arena can be smuggled into a fleet lease.
  if ffw_valid(state)!=1 || ffw_best_rank(state)<2 || meta.size()<15 || max_terms<2 || max_terms>8 || max_depth<1 || max_depth>8 || max_states<1 || max_states>4096 || max_edge_uphill<0 || max_edge_uphill>64
    return 0
  n=state[2] ## i64
  capacity=state[4] ## i64
  rank=ffw_best_rank(state) ## i64
  if ffw_verify_best_exact(state,n)!=1
    return 0
  source_u=i64[capacity]
  source_v=i64[capacity]
  source_w=i64[capacity]
  if ffw_export_best(state,source_u,source_v,source_w)!=rank
    return 0
  tickets=ffpa_ticket_count(source_u,source_v,source_w,rank) ## i64
  i=0
  while i<meta.size()
    meta[i]=0
    i+=1
  meta[13]=tickets
  if tickets<1
    return 0
  selected=ticket%tickets ## i64
  if selected<0
    selected+=tickets
  meta[14]=selected
  endpoint_u=i64[max_terms]
  endpoint_v=i64[max_terms]
  endpoint_w=i64[max_terms]
  origins=i64[max_terms]
  gain=ffpa_search(source_u,source_v,source_w,rank,selected,max_terms,max_depth,max_states,max_edge_uphill,endpoint_u,endpoint_v,endpoint_w,origins,meta) ## i64
  meta[13]=tickets
  meta[14]=selected
  if gain<=0
    return 0
  candidate_u=i64[capacity]
  candidate_v=i64[capacity]
  candidate_w=i64[capacity]
  at=0 ## i64
  slot=0 ## i64
  while slot<rank
    if ffpa_origin_has(origins,0,meta[7],slot)==0
      candidate_u[at]=source_u[slot]
      candidate_v[at]=source_v[slot]
      candidate_w[at]=source_w[slot]
      at+=1
    slot+=1
  i=0
  while i<meta[7]
    candidate_u[at]=endpoint_u[i]
    candidate_v[at]=endpoint_v[i]
    candidate_w[at]=endpoint_w[i]
    at+=1
    i+=1
  if at!=rank
    return 0
  seed=state[8]&4611686018427387903 ## i64
  dslack=state[17] ## i64
  cycles=state[15] ## i64
  workq=state[18] ## i64
  wanderq=state[19] ## i64
  loaded=ffw_init_terms_cap(state,candidate_u,candidate_v,candidate_w,rank,n,capacity,seed,dslack,cycles,workq,wanderq) ## i64
  if loaded!=rank || ffw_verify_best_exact(state,n)!=1
    # Identity-generated endpoints should never fail. Restore the exact source
    # anyway so a compiler/runtime regression remains fail-closed.
    restored=ffw_init_terms_cap(state,source_u,source_v,source_w,rank,n,capacity,seed,dslack,cycles,workq,wanderq) ## i64
    return 0
  1

# Scan the complete current ticket surface without mutating `state`, select
# the largest strict density gain (lowest ticket ordinal breaks a tie), then
# atomically load and independently exact-gate that one endpoint.  A miss or
# failed endpoint restores/leaves the exact source byte-for-byte in algebraic
# content.  `max_tickets` is a hard per-round coordinator-work cap.
#
# meta keeps the single-ticket ABI in [0..14], except that [0..4], [9], and
# [10] are totals over the scan. Additional fields are:
#   [15] tickets searched, [16] exact rejects, [17] endpoint applied.
-> ffpa_apply_best_ticket(state,max_terms,max_depth,max_states,max_edge_uphill,max_tickets,meta) (i64[] i64 i64 i64 i64 i64 i64[]) i64
  i=0 ## i64
  while i<meta.size()
    meta[i]=0
    i+=1
  if ffw_valid(state)!=1 || ffw_best_rank(state)<2 || meta.size()<18 || max_terms<2 || max_terms>8 || max_depth<1 || max_depth>8 || max_states<1 || max_states>4096 || max_edge_uphill<0 || max_edge_uphill>64 || max_tickets<1 || max_tickets>256
    return 0
  n=state[2] ## i64
  capacity=state[4] ## i64
  rank=ffw_best_rank(state) ## i64
  if ffw_verify_best_exact(state,n)!=1
    return 0
  source_u=i64[capacity]
  source_v=i64[capacity]
  source_w=i64[capacity]
  if ffw_export_best(state,source_u,source_v,source_w)!=rank
    return 0
  tickets=ffpa_ticket_count(source_u,source_v,source_w,rank) ## i64
  meta[13]=tickets
  if tickets<1
    return 0
  searched=tickets ## i64
  if searched>max_tickets
    searched=max_tickets

  endpoint_u=i64[max_terms]
  endpoint_v=i64[max_terms]
  endpoint_w=i64[max_terms]
  origins=i64[max_terms]
  best_u=i64[max_terms]
  best_v=i64[max_terms]
  best_w=i64[max_terms]
  best_origins=i64[max_terms]
  stats=i64[15]
  best_stats=i64[15]
  best_gain=0 ## i64
  best_ticket=0-1 ## i64
  total_states=0 ## i64
  total_proposals=0 ## i64
  total_legal=0 ## i64
  total_duplicates=0 ## i64
  total_collisions=0 ## i64
  total_caps=0 ## i64
  total_prunes=0 ## i64
  ticket=0 ## i64
  while ticket<searched
    gain=ffpa_search(source_u,source_v,source_w,rank,ticket,max_terms,max_depth,max_states,max_edge_uphill,endpoint_u,endpoint_v,endpoint_w,origins,stats) ## i64
    total_states+=stats[0]
    total_proposals+=stats[1]
    total_legal+=stats[2]
    total_duplicates+=stats[3]
    total_collisions+=stats[4]
    total_caps+=stats[9]
    total_prunes+=stats[10]
    if gain>best_gain
      best_gain=gain
      best_ticket=ticket
      i=0
      while i<15
        best_stats[i]=stats[i]
        i+=1
      i=0
      while i<stats[7]
        best_u[i]=endpoint_u[i]
        best_v[i]=endpoint_v[i]
        best_w[i]=endpoint_w[i]
        best_origins[i]=origins[i]
        i+=1
    ticket+=1

  meta[0]=total_states
  meta[1]=total_proposals
  meta[2]=total_legal
  meta[3]=total_duplicates
  meta[4]=total_collisions
  meta[5]=best_gain
  if best_gain>0
    meta[6]=best_stats[6]
    meta[7]=best_stats[7]
    meta[8]=best_stats[8]
    meta[11]=best_stats[11]
    meta[12]=best_stats[12]
  meta[9]=total_caps
  meta[10]=total_prunes
  meta[13]=tickets
  meta[14]=best_ticket
  meta[15]=searched
  if best_gain<=0
    return 0

  candidate_u=i64[capacity]
  candidate_v=i64[capacity]
  candidate_w=i64[capacity]
  at=0 ## i64
  slot=0 ## i64
  while slot<rank
    if ffpa_origin_has(best_origins,0,best_stats[7],slot)==0
      candidate_u[at]=source_u[slot]
      candidate_v[at]=source_v[slot]
      candidate_w[at]=source_w[slot]
      at+=1
    slot+=1
  i=0
  while i<best_stats[7]
    candidate_u[at]=best_u[i]
    candidate_v[at]=best_v[i]
    candidate_w[at]=best_w[i]
    at+=1
    i+=1
  if at!=rank
    return 0
  seed=state[8]&4611686018427387903 ## i64
  dslack=state[17] ## i64
  cycles=state[15] ## i64
  workq=state[18] ## i64
  wanderq=state[19] ## i64
  loaded=ffw_init_terms_cap(state,candidate_u,candidate_v,candidate_w,rank,n,capacity,seed,dslack,cycles,workq,wanderq) ## i64
  expected_bits=ffpa_density(source_u,source_v,source_w,0,rank)-best_gain ## i64
  if loaded!=rank || ffw_verify_best_exact(state,n)!=1 || ffw_best_bits(state)!=expected_bits
    restored=ffw_init_terms_cap(state,source_u,source_v,source_w,rank,n,capacity,seed,dslack,cycles,workq,wanderq) ## i64
    meta[16]=meta[16]+1
    return 0
  meta[17]=1
  1

# Bounded productive-word closure for the cold fixed-pocket racer arm.  The
# cheap ordinal-1 prefix is a measured optimization for C013: three 4,419-
# proposal searches replace three complete ~6.3M-proposal ticket scans.  Once
# ordinal 1 stops improving, complete strict-gain rescans discover the deeper
# barrier closures.  No fixed recipe or target certificate participates.
#
# `max_steps`, `prefix_limit`, `max_full_rounds`, and `max_tickets` jointly
# cap every lease.  The production call uses 8/4/5/64, so at most 324 ticket
# searches occur and the normal worker hot loop is untouched.
#
# meta:
#   [0] states, [1] proposals, [2] legal, [3] duplicates,
#   [4] frozen collisions, [5] density gain, [6] applied steps,
#   [7] prefix steps, [8] maximum barrier, [9] cap exhaustions,
#   [10] barrier prunes, [11] endpoint density, [12] source density,
#   [13] ticket searches, [14] last selected ticket, [15] full rounds,
#   [16] exact rejects, [17] stop (1=no gain,2=limit,3=invalid),
#   [18] largest ticket surface.
-> ffpa_apply_greedy_closure(state,max_steps,prefix_limit,max_full_rounds,max_tickets,max_terms,max_depth,max_states,max_edge_uphill,meta) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  i=0 ## i64
  while i<meta.size()
    meta[i]=0
    i+=1
  if ffw_valid(state)!=1 || ffw_best_rank(state)<2 || meta.size()<19 || max_steps<1 || max_steps>32 || prefix_limit<0 || prefix_limit>32 || max_full_rounds<1 || max_full_rounds>32 || max_tickets<1 || max_tickets>256
    if meta.size()>17
      meta[17]=3
    return 0
  n=state[2] ## i64
  capacity=state[4] ## i64
  rank=ffw_best_rank(state) ## i64
  if ffw_verify_best_exact(state,n)!=1
    meta[17]=3
    return 0
  root_u=i64[capacity]
  root_v=i64[capacity]
  root_w=i64[capacity]
  if ffw_export_best(state,root_u,root_v,root_w)!=rank
    meta[17]=3
    return 0
  root_density=ffw_best_bits(state) ## i64
  root_seed=state[8]&4611686018427387903 ## i64
  root_dslack=state[17] ## i64
  root_cycles=state[15] ## i64
  root_workq=state[18] ## i64
  root_wanderq=state[19] ## i64
  meta[12]=root_density
  steps=0 ## i64
  prefix_steps=0 ## i64
  full_rounds=0 ## i64
  stopped=0 ## i64

  # Deterministic cheap prefix. A miss is only the handoff to the full scan.
  prefix_try=0 ## i64
  while prefix_try<prefix_limit && steps<max_steps && stopped==0
    one=i64[15]
    applied=ffpa_apply_ticket(state,1,max_terms,max_depth,max_states,max_edge_uphill,one) ## i64
    meta[0]+=one[0]
    meta[1]+=one[1]
    meta[2]+=one[2]
    meta[3]+=one[3]
    meta[4]+=one[4]
    meta[9]+=one[9]
    meta[10]+=one[10]
    meta[13]+=1
    if one[13]>meta[18]
      meta[18]=one[13]
    if applied==1
      steps+=1
      prefix_steps+=1
      meta[14]=one[14]
      if one[8]>meta[8]
        meta[8]=one[8]
    else
      stopped=1
    prefix_try+=1

  # A prefix miss does not end the closure; it starts globally greedy scans.
  stopped=0
  while full_rounds<max_full_rounds && steps<max_steps && stopped==0
    scan=i64[18]
    applied=ffpa_apply_best_ticket(state,max_terms,max_depth,max_states,max_edge_uphill,max_tickets,scan) ## i64
    meta[0]+=scan[0]
    meta[1]+=scan[1]
    meta[2]+=scan[2]
    meta[3]+=scan[3]
    meta[4]+=scan[4]
    meta[9]+=scan[9]
    meta[10]+=scan[10]
    meta[13]+=scan[15]
    meta[16]+=scan[16]
    if scan[13]>meta[18]
      meta[18]=scan[13]
    full_rounds+=1
    if applied==1
      steps+=1
      meta[14]=scan[14]
      if scan[8]>meta[8]
        meta[8]=scan[8]
    else
      stopped=1

  meta[6]=steps
  meta[7]=prefix_steps
  meta[15]=full_rounds
  meta[11]=ffw_best_bits(state)
  meta[5]=root_density-meta[11]
  if stopped==1
    meta[17]=1
  else
    meta[17]=2
  if ffw_best_rank(state)!=rank || ffw_verify_best_exact(state,n)!=1 || meta[5]<0
    restored=ffw_init_terms_cap(state,root_u,root_v,root_w,rank,n,capacity,root_seed,root_dslack,root_cycles,root_workq,root_wanderq) ## i64
    meta[16]+=1
    meta[17]=3
    return 0
  if steps>0
    return 1
  0
