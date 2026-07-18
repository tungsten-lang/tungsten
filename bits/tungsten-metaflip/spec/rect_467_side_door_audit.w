# Exact structural and ordinary-walk audit for the 4x6x7 rank-123 frontier.
#
# With no arguments this inspects the two checked-in presentations.  Four
# additional side-door paths may be supplied to reproduce a live archive:
#
#   rect_467_side_door_audit SIDE0 SIDE1 SIDE2 SIDE3
#
# Every input is reconstructed against the complete matrix-multiplication
# tensor before any distance or move statistic is reported.
#
# A bounded preferred-axis fallback was rejected after this audit: it raised
# accepted moves/ms by 5--35% but did not improve planted recovery (leader
# 62/64 baseline versus 61/64 with one or two fallbacks), rank, or consistent
# endpoint distance.  The `eligible`/`any_axis` fields retain the structural
# evidence for that decision without changing the production move stream.

use ../lib/metaflip/rect
use ../lib/metaflip/rect/doors
use ../lib/metaflip/strategies/pooled_exact

-> ffr467_fail(label) (String) i64
  << "FAIL rect_467_side_door_audit: " + label
  exit(1)
  0

-> ffr467_axis(state, axis) (i64[] i64) i64
  rank = state[7] ## i64
  factoro = state[47] ## i64
  if axis == 1
    factoro = state[48]
  if axis == 2
    factoro = state[49]
  eligible = 0 ## i64
  pairs = 0 ## i64
  i = 0 ## i64
  while i < rank
    count = 0 ## i64
    j = 0 ## i64
    while j < rank
      if i != j && state[factoro+i] == state[factoro+j]
        count += 1
      j += 1
    if count > 0
      eligible += 1
      pairs += count
    i += 1
  # Ordered pair count is twice the number of legal unordered flip pairs.
  (eligible << 32) | (pairs / 2)

-> ffr467_density(state) (i64[]) i64
  state[36]

-> ffr467_report(label, path, ordinal) (String String i64) i64
  n = 4 ## i64
  m = 6 ## i64
  p = 7 ## i64
  capacity = ffr_default_capacity(n,m,p) ## i64
  state = i64[ffr_state_size(capacity)]
  rank = ffr_load_scheme_cap(state,path,n,m,p,capacity,467001+ordinal*104729,4,4,250000,50000) ## i64
  valid = 1 ## i64
  if rank != 123
    valid = 0
  exact = ffr_verify_best_exact(state,n,m,p) ## i64
  if exact != 1
    valid = 0
  if valid == 0
    return ffr467_fail(label + " rank/exact path=" + path)
  axis0 = ffr467_axis(state,0) ## i64
  axis1 = ffr467_axis(state,1) ## i64
  axis2 = ffr467_axis(state,2) ## i64
  e0 = axis0 >> 32 ## i64
  e1 = axis1 >> 32 ## i64
  e2 = axis2 >> 32 ## i64
  any = 0 ## i64
  term = 0 ## i64
  while term < 123
    found = 0 ## i64
    scan_axis = 0 ## i64
    while scan_axis < 3 && found == 0
      factoro = state[47+scan_axis] ## i64
      peer = 0 ## i64
      while peer < 123 && found == 0
        if term != peer && state[factoro+term] == state[factoro+peer]
          found = 1
        peer += 1
      scan_axis += 1
    any += found
    term += 1
  << "RECT467_DOOR label="+label+" rank=123 density="+ffr467_density(state).to_s()+" eligible="+e0.to_s()+","+e1.to_s()+","+e2.to_s()+" pairs="+(axis0&4294967295).to_s()+","+(axis1&4294967295).to_s()+","+(axis2&4294967295).to_s()+" any_axis="+any.to_s()+" random_axis_legal_numerator="+(e0+e1+e2).to_s()+" random_axis_legal_denominator=369"

  variant = 0 ## i64
  while variant < 1
    attempts = 0 ## i64
    accepted = 0 ## i64
    rejected = 0 ## i64
    no_partner = 0 ## i64
    splits = 0 ## i64
    split_accepted = 0 ## i64
    drops = 0 ## i64
    density_wins = 0 ## i64
    elapsed = 0 ## i64
    max_current_distance = 0 ## i64
    trial = 0 ## i64
    while trial < 4
      us = i64[capacity]
      vs = i64[capacity]
      ws = i64[capacity]
      exported = ffw_export_best(state,us,vs,ws) ## i64
      work = i64[ffr_state_size(capacity)]
      loaded = ffr_init_terms_cap(work,us,vs,ws,exported,n,m,p,capacity,470001+trial*104729,4,4,250000,50000) ## i64
      if loaded != 123
        return ffr467_fail(label + " trial clone")
      t0 = ccall("__w_clock_ms") ## i64
      z = ffr_work(work,50000) ## i64
      z = ffr_walk(work,350000)
      z = ffr_wander(work,100000)
      elapsed += ccall("__w_clock_ms")-t0
      attempts += work[20]
      accepted += work[21]
      rejected += work[22]
      no_partner += work[23]
      splits += work[27]
      split_accepted += work[28]
      drops += work[24]
      density_wins += work[25]
      endpoint = ffrda_clone_current_exact(work,n,m,p,capacity,480001+variant*100+trial,4,4,250000,50000)
      if endpoint == nil
        return ffr467_fail(label + " endpoint exact")
      distance = ffrda_best_distance(state,endpoint) ## i64
      if distance > max_current_distance
        max_current_distance = distance
      trial += 1
    legal = attempts-no_partner-splits ## i64
    << "RECT467_WALK label="+label+" attempts="+attempts.to_s()+" accepted="+accepted.to_s()+" rejected="+rejected.to_s()+" no_partner="+no_partner.to_s()+" legal_flips="+legal.to_s()+" splits="+splits.to_s()+" split_accepted="+split_accepted.to_s()+" rank_drops="+drops.to_s()+" best_adoptions="+density_wins.to_s()+" max_current_distance="+max_current_distance.to_s()+" ms="+elapsed.to_s()
    variant += 1
  1

-> ffr467_report_distance(left_label, left_path, right_label, right_path, nonce) (String String String String i64) i64
  n = 4 ## i64
  m = 6 ## i64
  p = 7 ## i64
  capacity = ffr_default_capacity(n,m,p) ## i64
  left = i64[ffr_state_size(capacity)]
  right = i64[ffr_state_size(capacity)]
  left_rank = ffr_load_scheme_cap(left,left_path,n,m,p,capacity,490001+nonce*2,4,4,250000,50000) ## i64
  z = ffr_load_scheme_cap(right,right_path,n,m,p,capacity,490002+nonce*2,4,4,250000,50000) ## i64
  left_exact = ffr_verify_best_exact(left,n,m,p) ## i64
  right_exact = ffr_verify_best_exact(right,n,m,p) ## i64
  if left_rank != 123 || right[7] != 123 || left_exact != 1 || right_exact != 1
    return ffr467_fail("distance inputs " + left_label + "/" + right_label)
  << "RECT467_DISTANCE left="+left_label+" right="+right_label+" distance="+ffrda_best_distance(left,right).to_s()
  1

-> ffr467_planted(label, path) (String String) i64
  n = 4 ## i64
  m = 6 ## i64
  p = 7 ## i64
  capacity = ffr_default_capacity(n,m,p) ## i64
  source = i64[ffr_state_size(capacity)]
  source_rank = ffr_load_scheme_cap(source,path,n,m,p,capacity,510001,4,4,250000,50000) ## i64
  if source_rank != 123
    return ffr467_fail(label + " planted source")
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  exported = ffw_export_best(source,source_u,source_v,source_w) ## i64
  if exported != 123
    return ffr467_fail(label + " planted export")

  variant = 0 ## i64
  while variant < 1
    recoveries = 0 ## i64
    exact = 0 ## i64
    attempts = 0 ## i64
    accepted = 0 ## i64
    no_partner = 0 ## i64
    elapsed = 0 ## i64
    trial = 0 ## i64
    while trial < 64
      shoulder_u = i64[capacity]
      shoulder_v = i64[capacity]
      shoulder_w = i64[capacity]
      shoulder_rank = ffpe_plant_split(source_u,source_v,source_w,source_rank,shoulder_u,shoulder_v,shoulder_w,trial*17+3) ## i64
      if shoulder_rank != 124 || ffpe_verify(shoulder_u,shoulder_v,shoulder_w,shoulder_rank,n,m,p) != 1
        return ffr467_fail(label + " planted split")
      work = i64[ffr_state_size(capacity)]
      loaded = ffr_init_terms_cap(work,shoulder_u,shoulder_v,shoulder_w,shoulder_rank,n,m,p,capacity,520001+trial*104729,4,4,250000,50000) ## i64
      if loaded != 124
        return ffr467_fail(label + " planted init")
      t0 = ccall("__w_clock_ms") ## i64
      z = ffr_work(work,1000) ## i64
      z = ffr_walk(work,7000)
      z = ffr_wander(work,2000)
      elapsed += ccall("__w_clock_ms")-t0
      attempts += work[20]
      accepted += work[21]
      no_partner += work[23]
      if work[7] <= 123
        recoveries += 1
      exact += ffr_verify_best_exact(work,n,m,p)
      trial += 1
    << "RECT467_PLANTED label="+label+" trials=64 moves_per_trial=10000 recoveries="+recoveries.to_s()+" exact="+exact.to_s()+" attempts="+attempts.to_s()+" accepted="+accepted.to_s()+" no_partner="+no_partner.to_s()+" ms="+elapsed.to_s()
    variant += 1
  1

args = argv()
if args.size() != 0 && args.size() != 4
  z = ffr467_fail("expected zero or four side-door paths") ## i64

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
paths = []
labels = []
paths.push(root + "matmul_4x6x7_rank123_d1406_gl_frontier_gf2.txt")
labels.push("leader")
paths.push(root + "matmul_4x6x7_rank123_catalog_gf2.txt")
labels.push("catalog")
i = 0 ## i64
while i < args.size()
  paths.push(args[i])
  labels.push("side" + i.to_s())
  i += 1

i = 0
while i < paths.size()
  z = ffr467_report(labels[i],paths[i],i) ## i64
  i += 1

i = 0
nonce = 0 ## i64
while i < paths.size()
  j = i+1 ## i64
  while j < paths.size()
    z = ffr467_report_distance(labels[i],paths[i],labels[j],paths[j],nonce)
    nonce += 1
    j += 1
  i += 1

z = ffr467_planted(labels[0],paths[0]) ## i64
z = ffr467_planted(labels[1],paths[1])

<< "PASS rect_467_side_door_audit"
