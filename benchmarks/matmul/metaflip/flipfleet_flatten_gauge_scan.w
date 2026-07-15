# Bounded real-frontier scanner for the flattening-gauge research operator.
#
# Usage:
#   flipfleet_flatten_gauge_scan seed.txt n k samples depth beam
#
# It applies the actual pure-Tungsten beam engine to deterministic windows on
# all three flattenings and reports rank-neutral, shoulder, rank-drop, and
# same-rank density-improvement frequencies.  It does not mutate the seed.

use metaflip_worker
use flipfleet_flatten_gauge

args = argv()
if args.size() < 6
  << "usage: flipfleet_flatten_gauge_scan seed.txt n k samples depth beam"
  exit(2)

seed_path = args[0]
n = args[1].to_i() ## i64
k = args[2].to_i() ## i64
samples = args[3].to_i() ## i64
depth = args[4].to_i() ## i64
beam = args[5].to_i() ## i64
if n < 3 || n > 7 || k < 2 || k > 16 || samples < 1 || depth < 1 || depth > 4 || beam < 1 || beam > 32
  << "invalid scan bounds"
  exit(2)

capacity = ffw_default_capacity(n) ## i64
state = i64[ffw_state_size(capacity)]
rank = ffw_load_scheme_cap(state,seed_path,n,capacity,190081,0,1,1,1) ## i64
if rank < k || ffw_verify_current_exact(state,n) == 0
  << "invalid exact seed"
  exit(2)
all_u = i64[capacity]
all_v = i64[capacity]
all_w = i64[capacity]
z = ffw_export_current(state,all_u,all_v,all_w) ## i64

probes = 0 ## i64
hits = 0 ## i64
drops = 0 ## i64
neutral = 0 ## i64
shoulders = 0 ## i64
density_better = 0 ## i64
collision_moves = 0 ## i64
collision_terms = 0 ## i64
expanded = 0 ## i64
best_delta = 1000 ## i64
best_density_delta = 1000000000 ## i64
rng = 7640891576956012809 ## i64
sample = 0 ## i64
while sample < samples
  selected = i64[16]
  chosen = 0 ## i64
  while chosen < k
    rng = rng * 6364136223846793005 + 1442695040888963407
    candidate = (rng ^ (rng >> 29)) & 9223372036854775807 ## i64
    candidate = candidate % rank
    duplicate = 0 ## i64
    j = 0 ## i64
    while j < chosen
      if selected[j] == candidate
        duplicate = 1
      j += 1
    if duplicate == 0
      selected[chosen] = candidate
      chosen += 1
  source = i64[48]
  old_density = 0 ## i64
  i = 0 ## i64
  while i < k
    source[i*3] = all_u[selected[i]]
    source[i*3+1] = all_v[selected[i]]
    source[i*3+2] = all_w[selected[i]]
    old_density += ffw_popcount(source[i*3]) + ffw_popcount(source[i*3+1]) + ffw_popcount(source[i*3+2])
    i += 1
  flatten_axis = 0 ## i64
  while flatten_axis < 3
    config = i64[4]
    config[0] = k
    config[1] = flatten_axis
    config[2] = depth
    config[3] = beam
    replacement = i64[768]
    external_u = i64[capacity]
    external_v = i64[capacity]
    external_w = i64[capacity]
    external_count = 0 ## i64
    position = 0 ## i64
    while position < rank
      if ffc_position_in(selected,k,position) == 0
        external_u[external_count] = all_u[position]
        external_v[external_count] = all_v[position]
        external_w[external_count] = all_w[position]
        external_count += 1
      position += 1
    meta = i64[8]
    made = ffgr_search_compact_packed(source,config,external_u,external_v,external_w,external_count,replacement,meta) ## i64
    probes += 1
    expanded += meta[2]
    if made > 0
      hits += 1
      replacement_u = i64[256]
      replacement_v = i64[256]
      replacement_w = i64[256]
      z = ffgr_unpack(replacement,made,replacement_u,replacement_v,replacement_w) ## i64
      external_collisions = 0 ## i64
      external_density = 0 ## i64
      replacement_index = 0 ## i64
      while replacement_index < made
        position = 0 ## i64
        while position < rank
          if ffc_position_in(selected,k,position) == 0
            if ffc_same_term(replacement_u[replacement_index],replacement_v[replacement_index],replacement_w[replacement_index],all_u[position],all_v[position],all_w[position]) == 1
              external_collisions += 1
              external_density += ffw_popcount(all_u[position]) + ffw_popcount(all_v[position]) + ffw_popcount(all_w[position])
          position += 1
        replacement_index += 1
      if external_collisions > 0
        collision_moves += 1
        collision_terms += external_collisions
      delta = made - k - 2*external_collisions ## i64
      density_delta = meta[5] - old_density - 2*external_density ## i64
      if delta < best_delta
        best_delta = delta
      if delta == 0 && density_delta < best_density_delta
        best_density_delta = density_delta
      if delta < 0
        drops += 1
      if delta == 0
        neutral += 1
        if density_delta < 0
          density_better += 1
      if delta > 0
        shoulders += 1
    flatten_axis += 1
  sample += 1

if best_delta == 1000
  best_delta = 0
if best_density_delta == 1000000000
  best_density_delta = 0
<< "FLATTEN_GAUGE_SCAN n=" + n.to_s() + " rank=" + rank.to_s() + " k=" + k.to_s() + " samples=" + samples.to_s() + " depth=" + depth.to_s() + " beam=" + beam.to_s() + " probes=" + probes.to_s() + " hits=" + hits.to_s() + " drops=" + drops.to_s() + " neutral=" + neutral.to_s() + " shoulders=" + shoulders.to_s() + " density_better=" + density_better.to_s() + " collision_moves=" + collision_moves.to_s() + " collision_terms=" + collision_terms.to_s() + " best_delta=" + best_delta.to_s() + " best_density_delta=" + best_density_delta.to_s() + " expanded=" + expanded.to_s()
