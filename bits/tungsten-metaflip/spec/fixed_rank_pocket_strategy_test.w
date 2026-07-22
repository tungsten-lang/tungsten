use ../lib/metaflip/strategies/fixed_rank_pocket
use ../lib/metaflip/fleet/cpu_experiments
use ../lib/metaflip/fleet/basins

-> ffpat_expect(label,condition) (String bool) i64
  if !condition
    << "FAIL fixed-rank pocket " + label
    exit(1)
  1

# Count and lookup cannot alias when exactly one ticket exists.
one_u=i64[3]
one_v=i64[3]
one_w=i64[3]
one_u[0]=1
one_u[1]=1
one_u[2]=2
one_v[0]=2
one_v[1]=4
one_v[2]=8
one_w[0]=16
one_w[1]=32
one_w[2]=64
ticket_out=i64[3]
ffpat_expect("one-ticket count",ffpa_ticket_count(one_u,one_v,one_w,3)==1)
ffpat_expect("one-ticket hit",ffpa_ticket(one_u,one_v,one_w,3,0,ticket_out)==1 && ticket_out[0]==0 && ticket_out[1]==1 && ticket_out[2]==0)
ffpat_expect("one-ticket out-of-range miss",ffpa_ticket(one_u,one_v,one_w,3,1,ticket_out)==0)

root=__DIR__+"/../lib/metaflip/seeds/gf2/"
capacity=320 ## i64
state_size=ffw_state_size(capacity) ## i64
c013_path=root+"matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt"
leader_path=root+"matmul_7x7_rank247_d3094_three_flip_density_gf2.txt"
closure_path=root+"matmul_7x7_rank247_d3496_fixed_rank_pocket_greedy_closure_gf2.txt"

c013=i64[state_size]
rank=ffw_load_scheme_cap(c013,c013_path,7,capacity,77007,4,1,25000000,6250000) ## i64
ffpat_expect("C013 load",rank==247 && ffw_best_bits(c013)==3554)
meta=i64[15]
applied=ffpa_apply_ticket(c013,8,5,5,512,12,meta) ## i64
ffpat_expect("C013 ticket eight applies",applied==1 && meta[5]==8 && meta[6]==4 && meta[7]==3 && meta[8]==10)
ffpat_expect("C013 endpoint",ffw_best_rank(c013)==247 && ffw_best_bits(c013)==3546 && ffw_verify_best_exact(c013,7)==1)
ffpat_expect("C013 bounded telemetry",meta[0]==19 && meta[1]==36000 && meta[9]==0 && meta[13]==43 && meta[14]==8)

gated=i64[state_size]
rank=ffw_load_scheme_cap(gated,c013_path,7,capacity,77007,4,1,25000000,6250000)
applied=ffpa_apply_ticket(gated,8,5,5,512,4,meta)
ffpat_expect("barrier four no-op",applied==0 && meta[5]==0 && meta[10]>0 && ffw_best_bits(gated)==3554 && ffw_verify_best_exact(gated,7)==1)
applied=ffpa_apply_ticket(gated,8,5,5,4097,12,meta)
ffpat_expect("resident arena bound fails closed",applied==0 && meta[0]==0 && ffw_best_bits(gated)==3554 && ffw_verify_best_exact(gated,7)==1)

# The production closure first consumes the cheap ordinal-1 prefix, then
# rescans every ticket after each strict adoption. It must converge to the
# packaged d3496 replay certificate, not merely the first d3546 tunnel.
leased=i64[state_size]
rank=ffw_load_scheme_cap(leased,c013_path,7,capacity,77011,4,1,25000000,6250000)
controls=i64[7]
setup=i64[7]
arm=ffcr_apply_arm_measured(leased,9,25000000,6250000,controls,setup) ## i64
ffpat_expect("canonical cadence arm",ffcr_arm_count()==11 && ffcr_arm_name(9)=="fixed-pocket" && arm==9)
ffpat_expect("lease greedy closure",ffw_best_rank(leased)==247 && ffw_best_bits(leased)==3496 && ffw_verify_best_exact(leased,7)==1)
ffpat_expect("lease setup telemetry",setup[0]==0 && setup[1]==58 && setup[2]==7 && setup[3]==219 && setup[4]==7 && setup[5]==26992 && setup[6]==31614912)

packaged=i64[state_size]
rank=ffw_load_scheme_cap(packaged,closure_path,7,capacity,77013,4,1,25000000,6250000)
ffpat_expect("packaged d3496",rank==247 && ffw_best_bits(packaged)==3496 && ffw_verify_best_exact(packaged,7)==1)
ffpat_expect("closure certificate identity",ffbi_best_id(leased)==ffbi_best_id(packaged))

# The prefix is an optimization, not hidden recipe data: a target-free full
# greedy scan from C013 reaches the identical endpoint, but spends ~19M more
# local proposals. This pins both completeness and the measured prepass value.
no_prefix=i64[state_size]
rank=ffw_load_scheme_cap(no_prefix,c013_path,7,capacity,77015,4,1,25000000,6250000)
closure_meta=i64[19]
applied=ffpa_apply_greedy_closure(no_prefix,8,0,8,64,5,5,512,12,closure_meta)
ffpat_expect("prefix-free closure",applied==1 && closure_meta[5]==58 && closure_meta[6]==7 && closure_meta[7]==0 && closure_meta[17]==1 && ffw_best_bits(no_prefix)==3496 && ffw_verify_best_exact(no_prefix,7)==1)
ffpat_expect("prefix-free identity",ffbi_best_id(no_prefix)==ffbi_best_id(packaged))
ffpat_expect("prefix saves work",closure_meta[1]>setup[6]+18000000 && closure_meta[13]>setup[3])
no_prefix_proposals=closure_meta[1] ## i64

# Invalid lease bounds and a no-gain leader scan are algebraically immutable.
invalid=i64[state_size]
rank=ffw_load_scheme_cap(invalid,c013_path,7,capacity,77017,4,1,25000000,6250000)
invalid_id=ffbi_best_id(invalid) ## i64
applied=ffpa_apply_greedy_closure(invalid,33,4,5,64,5,5,512,12,closure_meta)
ffpat_expect("closure bound fails closed",applied==0 && closure_meta[17]==3 && ffbi_best_id(invalid)==invalid_id && ffw_best_bits(invalid)==3554 && ffw_verify_best_exact(invalid,7)==1)
pulls=i64[ffcr_arm_count()]
exposure=i64[ffcr_arm_count()]
novel=i64[ffcr_arm_count()]
returns=i64[ffcr_arm_count()]
drops=i64[ffcr_arm_count()]
density=i64[ffcr_arm_count()]
recorded=ffcr_record_lease(9,setup[6],0,0,setup[0],setup[1],pulls,exposure,novel,returns,drops,density) ## i64
ffpat_expect("lease reward includes setup",recorded==9 && pulls[9]==1 && exposure[9]==31614912 && density[9]==58)

# The current density leader has the same 43-ticket surface but no productive
# bounded endpoint. Scanning a complete rotation remains a cold, cheap no-op.
leader=i64[state_size]
rank=ffw_load_scheme_cap(leader,leader_path,7,capacity,77009,4,1,25000000,6250000)
ffpat_expect("leader load",rank==247 && ffw_best_bits(leader)==3094)
leader_u=i64[capacity]
leader_v=i64[capacity]
leader_w=i64[capacity]
ffw_export_best(leader,leader_u,leader_v,leader_w)
leader_tickets=ffpa_ticket_count(leader_u,leader_v,leader_w,247) ## i64
ffpat_expect("leader tickets",leader_tickets==43)
total_states=0 ## i64
total_proposals=0 ## i64
ticket=0 ## i64
while ticket<leader_tickets
  applied=ffpa_apply_ticket(leader,ticket,5,5,512,12,meta)
  ffpat_expect("leader ticket no-op",applied==0)
  total_states+=meta[0]
  total_proposals+=meta[1]
  ticket+=1
ffpat_expect("leader remains exact",ffw_best_rank(leader)==247 && ffw_best_bits(leader)==3094 && ffw_verify_best_exact(leader,7)==1)
ffpat_expect("leader scan bounded",total_states<10000 && total_proposals<10000000)

leader_id=ffbi_best_id(leader) ## i64
applied=ffpa_apply_greedy_closure(leader,8,4,5,64,5,5,512,12,closure_meta)
ffpat_expect("leader closure immutable",applied==0 && closure_meta[5]==0 && closure_meta[6]==0 && closure_meta[17]==1 && ffbi_best_id(leader)==leader_id && ffw_best_bits(leader)==3094 && ffw_verify_best_exact(leader,7)==1)

<< "fixed_rank_pocket_strategy_test: pass C013=3554->3496 steps="+setup[2].to_s()+" prefix-proposals="+setup[6].to_s()+" full-proposals="+no_prefix_proposals.to_s()+" leader-tickets="+leader_tickets.to_s()+" leader-states="+total_states.to_s()+" leader-proposals="+total_proposals.to_s()
