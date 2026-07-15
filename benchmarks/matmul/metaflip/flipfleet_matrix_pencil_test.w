use flipfleet_matrix_pencil

-> ffmpt_expect(label, condition) (String bool) i64
  if !condition
    << "MATRIX_PENCIL_TEST_FAIL " + label
    exit(1)
  1

# Rank primitives and a complete 2x2-coordinate D table.
ffmpt_expect("zero matrix rank",ffmp_matrix_rank(0,2,2) == 0)
ffmpt_expect("identity matrix rank",ffmp_matrix_rank(9,2,2) == 2)
ffmpt_expect("rank-one matrix",ffmp_matrix_rank(15,2,2) == 1)
rank_table = i32[16]
ffmpt_expect("rank table built",ffmp_fill_rank_table(2,2,rank_table) == 16 && rank_table[9] == 2)

# Planted whole-pencil control.  The five source terms sum to one term:
#   p*(e2 e2') + q*I + (p+q)*I = p*(e1 e1').
# Each of the three colour matrices is already rank-minimal (1+2+2), so an
# independent shared-factor Gaussian pass leaves five terms.  The D search
# sees the cross-colour cancellation and returns one term.  Set distance six
# proves this is not any single pair flip, and k=5 lies beyond span-4.
line = i64[3]
ffmpt_expect("line canonicalized",ffmp_line_sort(9,2,11,line) == 1 && line[0] == 2 && line[1] == 9 && line[2] == 11)
su = i64[5]
sv = i64[5]
sw = i64[5]
su[0] = 9
sv[0] = 2
sw[0] = 2
su[1] = 2
sv[1] = 9
sw[1] = 9
su[2] = 2
sv[2] = 2
sw[2] = 2
su[3] = 11
sv[3] = 9
sw[3] = 9
su[4] = 11
sv[4] = 2
sw[4] = 2
out_u = i64[32]
out_v = i64[32]
out_w = i64[32]
meta = i64[14]
made = ffmp_optimize_group(su,sv,sw,5,0,line,4,rank_table,out_u,out_v,out_w,meta) ## i64
ffmpt_expect("planted rank drop",made == 1 && meta[5] == 5 && meta[6] == 1)
ffmpt_expect("planted local exact",meta[10] == 1 && meta[11] == 0)
ffmpt_expect("planted non-pair distance",meta[12] == 6)
ffmpt_expect("planted expected term",out_u[0] == 9 && out_v[0] == 9 && out_w[0] == 9)

# Embed the planted five-term presentation in the exact 2x2 Strassen scheme,
# then require the operator's fresh worker reconstruction to pass the complete
# n^6 MMT gate and recover rank seven.
n = 2 ## i64
capacity = ffw_default_capacity(n) ## i64
strassen = i64[ffw_state_size(capacity)]
rank = ffw_load_scheme_cap(strassen,"benchmarks/matmul/metaflip/matmul_2x2_rank7_strassen_gf2.txt",n,capacity,71101,0,1,1,1) ## i64
ffmpt_expect("Strassen source exact",rank == 7 && ffw_verify_current_exact(strassen,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
ffmpt_expect("Strassen export",ffw_export_current(strassen,base_u,base_v,base_w) == 7)
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
shoulder_count = 0 ## i64
i = 0 ## i64
while i < rank
  if !(base_u[i] == 9 && base_v[i] == 9 && base_w[i] == 9)
    shoulder_u[shoulder_count] = base_u[i]
    shoulder_v[shoulder_count] = base_v[i]
    shoulder_w[shoulder_count] = base_w[i]
    shoulder_count += 1
  i += 1
i = 0
while i < 5
  shoulder_u[shoulder_count] = su[i]
  shoulder_v[shoulder_count] = sv[i]
  shoulder_w[shoulder_count] = sw[i]
  shoulder_count += 1
  i += 1
shoulder = i64[ffw_state_size(capacity)]
shoulder_rank = ffw_init_terms_cap(shoulder,shoulder_u,shoulder_v,shoulder_w,shoulder_count,n,capacity,71103,0,1,1,1) ## i64
ffmpt_expect("planted shoulder full exact",shoulder_rank == 11 && ffw_verify_current_exact(shoulder,n) == 1)
captured_u = i64[capacity]
captured_v = i64[capacity]
captured_w = i64[capacity]
selected = i64[capacity]
captured = ffmp_capture_line(shoulder_u,shoulder_v,shoulder_w,shoulder_count,0,line,selected,captured_u,captured_v,captured_w) ## i64
ffmpt_expect("maximal planted line captured",captured == 5)
full_out_u = i64[32]
full_out_v = i64[32]
full_out_w = i64[32]
full_meta = i64[14]
full_made = ffmp_optimize_group(captured_u,captured_v,captured_w,captured,0,line,4,rank_table,full_out_u,full_out_v,full_out_w,full_meta) ## i64
ffmpt_expect("full planted pencil optimized",full_made == 1 && full_meta[12] == 6)
recovered = i64[ffw_state_size(capacity)]
recovered_rank = ffmp_splice_state(shoulder,selected,captured,full_out_u,full_out_v,full_out_w,full_made,recovered,71107) ## i64
ffmpt_expect("full n6 gate",recovered_rank == 7 && ffw_verify_current_exact(recovered,n) == 1)

# Real evidence beyond span-4: the d1155 5x5 archive has one five-term line
# on each factor axis.  This axis-V pencil has a distinct rank-five optimum at
# term-set distance eight.  It is rank neutral, but demonstrates a genuine
# whole-pencil tunnel on a live record presentation and passes the full gate.
n5 = 5 ## i64
capacity5 = ffw_default_capacity(n5) ## i64
source5 = i64[ffw_state_size(capacity5)]
rank5 = ffw_load_scheme_cap(source5,"benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt",n5,capacity5,71201,0,1,1,1) ## i64
ffmpt_expect("real 5x5 source exact",rank5 == 93 && ffw_verify_current_exact(source5,n5) == 1)
all5_u = i64[capacity5]
all5_v = i64[capacity5]
all5_w = i64[capacity5]
ffw_export_current(source5,all5_u,all5_v,all5_w)
line5 = i64[3]
line5[0] = 168965
line5[1] = 5248005
line5[2] = 5406720
selected5 = i64[capacity5]
source5_u = i64[capacity5]
source5_v = i64[capacity5]
source5_w = i64[capacity5]
captured5 = ffmp_capture_line(all5_u,all5_v,all5_w,rank5,1,line5,selected5,source5_u,source5_v,source5_w) ## i64
ffmpt_expect("real five-term line",captured5 == 5)
no_table5 = i32[1]
out5_u = i64[32]
out5_v = i64[32]
out5_w = i64[32]
meta5 = i64[14]
made5 = ffmp_optimize_group(source5_u,source5_v,source5_w,captured5,1,line5,20,no_table5,out5_u,out5_v,out5_w,meta5) ## i64
ffmpt_expect("real neutral pencil",made5 == 5 && meta5[5] == 5 && meta5[6] == 5 && meta5[8] != meta5[7])
ffmpt_expect("real beyond-pair distance",meta5[12] == 8)
endpoint5 = i64[ffw_state_size(capacity5)]
endpoint5_rank = ffmp_splice_state(source5,selected5,captured5,out5_u,out5_v,out5_w,made5,endpoint5,71203) ## i64
ffmpt_expect("real 5x5 full n6 gate",endpoint5_rank == 93 && ffw_verify_current_exact(endpoint5,n5) == 1)

<< "flipfleet_matrix_pencil_test: pass planted=5->1 distance=" + meta[12].to_s() + " full=11->" + recovered_rank.to_s() + " real5x5=r" + endpoint5_rank.to_s() + "/distance" + meta5[12].to_s()
