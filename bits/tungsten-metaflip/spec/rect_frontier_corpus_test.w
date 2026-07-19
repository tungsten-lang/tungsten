# The public results corpus keeps exact rank-R/R+1/R+2 rectangular doors for
# basin diversity.  This regression proves that every runtime copy remains an
# exact decomposition, that each profile exposes the intended rank strata,
# and that no registered door aliases another term set.  Isotropy-parent
# shoulders must also remain far from the runtime density leader; otherwise a
# future archive refresh could silently replace them with trivial split debt.

use ../lib/metaflip/rect/doors

-> ffrfct_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

root = __DIR__ + "/../lib/metaflip/" ## String
labels = ["3x3x4","3x4x4","2x3x5","3x4x5","4x5x5","5x6x7"]
ns = [3,3,2,3,4,5]
ms = [3,4,3,4,5,6]
ps = [4,4,5,5,5,7]
expected_doors = [3,4,6,4,4,4]
expected_r = [1,2,4,2,2,2]
expected_r1 = [1,1,1,1,1,1]
expected_r2 = [1,1,1,1,1,1]
# Minimum exact term-set symmetric difference from slot-zero for R+1/R+2.
minimum_shoulder_distance = [59,77,44,94,153,301]

total = 0 ## i64
shape = 0 ## i64
while shape < labels.size()
  n = ns[shape] ## i64
  m = ms[shape] ## i64
  p = ps[shape] ## i64
  leader_rank = ffrp_record_rank(n,m,p) ## i64
  count = ffrp_frontier_seed_count(n,m,p) ## i64
  z = ffrfct_expect(labels[shape]+" door count",count == expected_doors[shape])
  capacity = ffr_default_capacity(n,m,p) ## i64
  doors = []
  strata = i64[3]
  slot = 0 ## i64
  while slot < count
    rel = ffrp_frontier_seed_rel(n,m,p,slot)
    z = ffrfct_expect(labels[shape]+" slot "+slot.to_s()+" path",rel != "")
    state = i64[ffr_state_size(capacity)]
    rank = ffr_load_scheme_cap(state,root+rel,n,m,p,capacity,77001+shape*1009+slot*17,4,4,1000,250) ## i64
    z = ffrfct_expect(labels[shape]+" slot "+slot.to_s()+" rank band",rank >= leader_rank && rank <= leader_rank+2)
    z = ffrfct_expect(labels[shape]+" slot "+slot.to_s()+" exact best",ffr_verify_best_exact(state,n,m,p) == 1)
    z = ffrfct_expect(labels[shape]+" slot "+slot.to_s()+" exact current",ffr_verify_current_exact(state,n,m,p) == 1)
    strata[rank-leader_rank] += 1

    prior = 0 ## i64
    while prior < doors.size()
      z = ffrfct_expect(labels[shape]+" unique slots "+prior.to_s()+"/"+slot.to_s(),ffrda_same_best(doors[prior],state) == 0)
      prior += 1
    if slot > 0
      distance = ffrda_best_distance(doors[0],state) ## i64
      z = ffrfct_expect(labels[shape]+" slot "+slot.to_s()+" nonzero leader distance",distance > 0)
      if rank > leader_rank
        z = ffrfct_expect(labels[shape]+" slot "+slot.to_s()+" shoulder distance",distance >= minimum_shoulder_distance[shape])
    doors.push(state)
    total += 1
    slot += 1

  z = ffrfct_expect(labels[shape]+" rank-R count",strata[0] == expected_r[shape])
  z = ffrfct_expect(labels[shape]+" rank-R+1 count",strata[1] == expected_r1[shape])
  z = ffrfct_expect(labels[shape]+" rank-R+2 count",strata[2] == expected_r2[shape])
  shape += 1

z = ffrfct_expect("total registered corpus doors",total == 25)
<< "PASS rectangular frontier corpus exact=25 shapes=6 strata=R/R+1/R+2 uniqueness=full leader-distance=gated"
