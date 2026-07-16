# Bounded real-seed screen for the four-line rank-debt catalyst.
#
# Usage:
#   rect_catalyst_lift2_bench SEED N M P Q WINDOWS DEPTH NODES CATALYSTS MIN_DEPTH OUT
#
# Every local close is replayed in both directions, spliced into the complete
# decomposition with GF(2) cancellation, and independently verified against
# the full rectangular matrix-multiplication tensor before it is written.

use ../lib/metaflip/rect
use ../lib/metaflip/kernels/rect_kxor
use ../lib/metaflip/strategies/rect_catalyst_lift2

-> ffrcl2b_selected(selected, count, value) (i64[] i64 i64) i64
  i=0 ## i64
  while i<count
    if selected[i]==value
      return 1
    i+=1
  0

-> ffrcl2b_capture(us, vs, ws, selected, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  i=0 ## i64
  while i<count
    out_u[i]=us[selected[i]]
    out_v[i]=vs[selected[i]]
    out_w[i]=ws[selected[i]]
    i+=1
  count

-> ffrcl2b_toggle(us, vs, ws, count, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  found=0-1 ## i64
  i=0 ## i64
  while i<count && found<0
    if us[i]==u && vs[i]==v && ws[i]==w
      found=i
    i+=1
  if found>=0
    last=count-1 ## i64
    us[found]=us[last]
    vs[found]=vs[last]
    ws[found]=ws[last]
    return count-1
  if count>=capacity
    return 0-count-1
  us[count]=u
  vs[count]=v
  ws[count]=w
  count+1

-> ffrcl2b_splice(us, vs, ws, rank, selected, selected_count, local_u, local_v, local_w, local_count, out_u, out_v, out_w, capacity) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  count=0 ## i64
  i=0 ## i64
  while i<rank
    if ffrcl2b_selected(selected,selected_count,i)==0
      count=ffrcl2b_toggle(out_u,out_v,out_w,count,capacity,us[i],vs[i],ws[i])
      if count<0
        return 0
    i+=1
  i=0
  while i<local_count
    count=ffrcl2b_toggle(out_u,out_v,out_w,count,capacity,local_u[i],local_v[i],local_w[i])
    if count<0
      return 0
    i+=1
  count

args=argv()
if args.size() != 11
  << "usage: rect_catalyst_lift2_bench SEED N M P Q WINDOWS DEPTH NODES CATALYSTS MIN_DEPTH OUT"
  exit(2)

seed_path=args[0]
n=args[1].to_i() ## i64
m=args[2].to_i() ## i64
p=args[3].to_i() ## i64
q=args[4].to_i() ## i64
windows=args[5].to_i() ## i64
depth_limit=args[6].to_i() ## i64
node_cap=args[7].to_i() ## i64
catalyst_cap=args[8].to_i() ## i64
min_depth=args[9].to_i() ## i64
output_path=args[10]
if q<3 || q>7 || windows<1
  << "FAIL rect_catalyst_lift2_bench invalid plan"
  exit(2)

capacity=ffr_default_capacity(n,m,p) ## i64
state=i64[ffr_state_size(capacity)]
rank=ffr_load_scheme_cap(state,seed_path,n,m,p,capacity,19421+n+m+p,0,1,1,1) ## i64
if rank<q || ffr_verify_best_exact(state,n,m,p) != 1
  << "FAIL rect_catalyst_lift2_bench seed"
  exit(1)
us=i64[capacity];vs=i64[capacity];ws=i64[capacity]
z=ffw_export_best(state,us,vs,ws) ## i64

shape=i64[3];shape[0]=n*m;shape[1]=m*p;shape[2]=n*p
limits=i64[4];limits[0]=depth_limit;limits[1]=node_cap;limits[2]=catalyst_cap;limits[3]=min_depth
searches=0 ## i64
local_hits=0 ## i64
full_gates=0 ## i64
full_hits=0 ## i64
gate_failures=0 ## i64
catalysts=0 ## i64
states=0 ## i64
codes=0 ## i64
legal=0 ## i64
revisits=0 ## i64
lines=0 ## i64
capped=0 ## i64
scanned=0 ## i64
best_rank=rank ## i64
best_depth=0-1 ## i64
started=ccall("__w_clock_ms") ## i64
window=0 ## i64
while window<windows
  selected=i64[q]
  chosen=ffrx_choose_subset(us,vs,ws,rank,q,window*17,selected) ## i64
  if chosen==q
    local_u=i64[q];local_v=i64[q];local_w=i64[q]
    z=ffrcl2b_capture(us,vs,ws,selected,q,local_u,local_v,local_w)
    target_u=i64[q-2];target_v=i64[q-2];target_w=i64[q-2]
    source_aug_u=i64[q+2];source_aug_v=i64[q+2];source_aug_w=i64[q+2]
    target_aug_u=i64[q+2];target_aug_v=i64[q+2];target_aug_w=i64[q+2]
    recipe=i64[ffrcl2_recipe_size()]
    path_recipe=i64[ffrep_recipe_size()]
    stats=i64[ffrcl2_goal_stats_size()]
    searches+=1
    out_count=ffrcl2_goal_search(local_u,local_v,local_w,q,shape,limits,target_u,target_v,target_w,source_aug_u,source_aug_v,source_aug_w,target_aug_u,target_aug_v,target_aug_w,recipe,path_recipe,stats) ## i64
    catalysts+=stats[0]
    states+=stats[1]
    codes+=stats[2]
    legal+=stats[3]
    revisits+=stats[4]
    lines+=stats[5]
    capped+=stats[12]
    scanned+=stats[18]
    if out_count==q-2 && stats[13]==1
      local_hits+=1
      candidate_u=i64[capacity];candidate_v=i64[capacity];candidate_w=i64[capacity]
      candidate_rank=ffrcl2b_splice(us,vs,ws,rank,selected,q,target_u,target_v,target_w,out_count,candidate_u,candidate_v,candidate_w,capacity) ## i64
      if candidate_rank>0
        child=i64[ffr_state_size(capacity)]
        loaded=ffr_init_terms_cap(child,candidate_u,candidate_v,candidate_w,candidate_rank,n,m,p,capacity,19621+window,0,1,1,1) ## i64
        is_exact=0 ## i64
        if loaded==candidate_rank
          is_exact=ffr_verify_best_exact(child,n,m,p)
        full_gates+=1
        if is_exact != 1
          gate_failures+=1
        if is_exact==1
          full_hits+=1
          if candidate_rank<best_rank
            best_rank=candidate_rank
            best_depth=stats[7]
            dumped=ffr_dump_best(child,output_path) ## i64
            << "RECT_CATALYST2_HIT rank="+candidate_rank.to_s()+" depth="+stats[7].to_s()+" window="+window.to_s()+" catalyst="+stats[14].to_s()+" node="+stats[15].to_s()+" output="+output_path
  window+=1
elapsed=ccall("__w_clock_ms")-started ## i64
<< "RECT_CATALYST2 rank="+rank.to_s()+" q="+q.to_s()+" windows="+windows.to_s()+" searches="+searches.to_s()+" catalysts="+catalysts.to_s()+" states="+states.to_s()+" codes="+codes.to_s()+" legal="+legal.to_s()+" revisits="+revisits.to_s()+" scanned="+scanned.to_s()+" lines="+lines.to_s()+" capped="+capped.to_s()+" local_hits="+local_hits.to_s()+" gates="+full_gates.to_s()+" gate_fail="+gate_failures.to_s()+" full_hits="+full_hits.to_s()+" best_rank="+best_rank.to_s()+" best_depth="+best_depth.to_s()+" ms="+elapsed.to_s()
