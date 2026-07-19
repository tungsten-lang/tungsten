use flipfleet_kernel_line_fiber

-> ffklft_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL kernel-line fiber: " + label
    exit(1)
  1

-> ffklft_fill6(us, vs, ws, values) (i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < 6
    us[i] = values[i*3]
    vs[i] = values[i*3+1]
    ws[i] = values[i*3+2]
    i += 1
  z = ffklf_sort(us,vs,ws,6) ## i64
  6

-> ffklft_same_slot(left_u, left_v, left_w, left_offset, right_u, right_v, right_w, right_offset, count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if left_u[left_offset+i] != right_u[right_offset+i] || left_v[left_offset+i] != right_v[right_offset+i] || left_w[left_offset+i] != right_w[right_offset+i]
      return 0
    i += 1
  1

# Exhaust the fixed-rank ordinary-flip component. Canonical term sorting makes
# full state comparison collision-free; the fixture's component has only three
# states, so cap exhaustion would be a test failure rather than a search miss.
-> ffklft_component(source_u, source_v, source_w, count, target_u, target_v, target_w, cap, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[]) i64
  states_u = i64[cap*count]
  states_v = i64[cap*count]
  states_w = i64[cap*count]
  i = 0 ## i64
  while i < count
    states_u[i] = source_u[i]
    states_v[i] = source_v[i]
    states_w[i] = source_w[i]
    i += 1
  z = ffklf_sort(states_u,states_v,states_w,count) ## i64
  nodes = 1 ## i64
  cursor = 0 ## i64
  code_count = fftc_code_count(count) ## i64
  child_u = i64[count]
  child_v = i64[count]
  child_w = i64[count]
  found_target = 0 ## i64
  while cursor < nodes
    code = 0 ## i64
    while code < code_count
      stats[1] = stats[1] + 1
      i = 0
      while i < count
        child_u[i] = states_u[cursor*count+i]
        child_v[i] = states_v[cursor*count+i]
        child_w[i] = states_w[cursor*count+i]
        i += 1
      if fftc_apply_code(child_u,child_v,child_w,count,code,0-1) == 1
        stats[2] = stats[2] + 1
        z = ffklf_sort(child_u,child_v,child_w,count)
        if ffklf_distinct(child_u,child_v,child_w,count) == 1
          if fftc_terms_same_set(child_u,child_v,child_w,count,target_u,target_v,target_w,count) == 1
            found_target = 1
          seen = 0 ## i64
          slot = 0 ## i64
          while slot < nodes && seen == 0
            if ffklft_same_slot(states_u,states_v,states_w,slot*count,child_u,child_v,child_w,0,count) == 1
              seen = 1
            slot += 1
          if seen == 0
            if nodes >= cap
              stats[3] = 1
              stats[0] = nodes
              stats[4] = found_target
              return nodes
            i = 0
            while i < count
              states_u[nodes*count+i] = child_u[i]
              states_v[nodes*count+i] = child_v[i]
              states_w[nodes*count+i] = child_w[i]
              i += 1
            nodes += 1
      code += 1
    cursor += 1
  stats[0] = nodes
  stats[4] = found_target
  nodes

source_u = i64[16]
source_v = i64[16]
source_w = i64[16]
source_values = i64[18]
source_values[0]=1; source_values[1]=2; source_values[2]=6
source_values[3]=2; source_values[4]=11; source_values[5]=11
source_values[6]=5; source_values[7]=8; source_values[8]=1
source_values[9]=6; source_values[10]=3; source_values[11]=8
source_values[12]=8; source_values[13]=1; source_values[14]=3
source_values[15]=8; source_values[16]=4; source_values[17]=15
z = ffklft_fill6(source_u,source_v,source_w,source_values) ## i64

target_u = i64[16]
target_v = i64[16]
target_w = i64[16]
# This is the deterministic physical matrix factorization emitted by
# ffsm_rank_factor_matrix for target residual rows (0,5,15,10).
target_values = i64[18]
target_values[0]=8; target_values[1]=10; target_values[2]=5
target_values[3]=8; target_values[4]=12; target_values[5]=15
target_values[6]=9; target_values[7]=2; target_values[8]=6
target_values[9]=10; target_values[10]=11; target_values[11]=11
target_values[12]=13; target_values[13]=8; target_values[14]=1
target_values[15]=14; target_values[16]=3; target_values[17]=8
z = ffklft_fill6(target_u,target_v,target_w,target_values)

z = ffklft_expect("source distinct",ffklf_distinct(source_u,source_v,source_w,6)==1)
z = ffklft_expect("target distinct",ffklf_distinct(target_u,target_v,target_w,6)==1)
z = ffklft_expect("independent local equality",fftc_local_exact(source_u,source_v,source_w,6,target_u,target_v,target_w,6)==1)
z = ffklft_expect("distance twelve",ffklf_distance(source_u,source_v,source_w,6,target_u,target_v,target_w,6)==12)

# Proper subsets must cross a rank barrier: ten residuals have rank three and
# four have rank four. Only the simultaneous four-lift word returns to rank 6.
rank3 = 0 ## i64
rank4 = 0 ## i64
mask = 1 ## i64
while mask < 16
  selected = i64[4]
  selected_count = 0 ## i64
  ordinal = 0 ## i64
  while ordinal < 4
    if ((mask >> ordinal) & 1) != 0
      selected[selected_count] = ordinal
      selected_count += 1
    ordinal += 1
  out_u = i64[16]
  out_v = i64[16]
  out_w = i64[16]
  meta = i64[12]
  endpoint_rank = ffklf_materialize(source_u,source_v,source_w,6,0,8,selected,selected_count,out_u,out_v,out_w,meta) ## i64
  z = ffklft_expect("subset exact " + mask.to_s(),endpoint_rank>0 && meta[6]==1 && meta[0]==4 && meta[10]==1)
  if mask < 15
    z = ffklft_expect("proper subset debt " + mask.to_s(),endpoint_rank>=7)
    if meta[2] == 3
      rank3 += 1
    if meta[2] == 4
      rank4 += 1
  else
    z = ffklft_expect("full word rank neutral",endpoint_rank==6 && meta[2]==2)
    z = ffklft_expect("full word distance",meta[5]==12)
    z = ffklft_expect("deterministic endpoint",fftc_terms_same_set(out_u,out_v,out_w,6,target_u,target_v,target_w,6)==1)
  mask += 1
z = ffklft_expect("barrier census",rank3==10 && rank4==4)

# The fixed-rank ordinary component is genuinely exhausted, not merely sampled.
component_stats = i64[5]
component = ffklft_component(source_u,source_v,source_w,6,target_u,target_v,target_w,64,component_stats) ## i64
z = ffklft_expect("ordinary component exact size",component==3 && component_stats[0]==3)
z = ffklft_expect("ordinary component uncapped",component_stats[3]==0)
z = ffklft_expect("target outside ordinary component",component_stats[4]==0)

# Store the changed support as a zero relation. Applying the same recipe twice
# must be a literal inverse; mixed/corrupt recipes fail before state mutation.
forward_u = i64[16]
forward_v = i64[16]
forward_w = i64[16]
replay = i64[8]
forward_rank = ffklf_apply_relation(source_u,source_v,source_w,6,16,source_u,source_v,source_w,6,target_u,target_v,target_w,6,forward_u,forward_v,forward_w,replay) ## i64
z = ffklft_expect("forward replay",forward_rank==6 && replay[5]==1 && fftc_terms_same_set(forward_u,forward_v,forward_w,6,target_u,target_v,target_w,6)==1)
undo_u = i64[16]
undo_v = i64[16]
undo_w = i64[16]
undo_rank = ffklf_apply_relation(forward_u,forward_v,forward_w,6,16,source_u,source_v,source_w,6,target_u,target_v,target_w,6,undo_u,undo_v,undo_w,replay) ## i64
z = ffklft_expect("inverse replay",undo_rank==6 && replay[0]==1 && replay[5]==1 && fftc_terms_same_set(undo_u,undo_v,undo_w,6,source_u,source_v,source_w,6)==1)

bad_selected = i64[2]
bad_selected[0] = 0
bad_selected[1] = 0
bad_u = i64[16]
bad_v = i64[16]
bad_w = i64[16]
bad_meta = i64[12]
z = ffklft_expect("duplicate ordinal rejected",ffklf_materialize(source_u,source_v,source_w,6,0,8,bad_selected,2,bad_u,bad_v,bad_w,bad_meta)==0)
z = ffklft_expect("zero kernel rejected",ffklf_materialize(source_u,source_v,source_w,6,0,0,bad_selected,1,bad_u,bad_v,bad_w,bad_meta)==0)
corrupt_w = i64[16]
i = 0 ## i64
while i < 6
  corrupt_w[i] = target_w[i]
  i += 1
corrupt_w[0] = corrupt_w[0] ^ 1
z = ffklft_expect("corrupt relation rejected",ffklf_apply_relation(source_u,source_v,source_w,6,16,source_u,source_v,source_w,6,target_u,target_v,corrupt_w,6,bad_u,bad_v,bad_w,replay)==0)

<< "PASS kernel_line_fiber_test component=" + component.to_s() + " barrier=10xR3+4xR4 distance=12"
