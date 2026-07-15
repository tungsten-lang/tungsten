# Generate a distant exact GL-orbit door for a rectangular GF(2) scheme.
#
# Density descent normally keeps only a strictly cheaper endpoint.  That is
# right for choosing a fleet leader, but it discards equal-density (or mildly
# denser) presentations which are useful as independent sticky basins.  This
# offline tool samples deterministic sparse GL words, descends each image,
# and keeps the most distant endpoint within a caller-supplied density debt.
# Every image, endpoint, output, and reparsed output receives the complete
# rectangular tensor gate inherited from flipfleet_rect_global_isotropy.
#
# Usage:
#   flipfleet_rect_orbit_door_cli SEED N M P SAMPLES MAX_STEPS MAX_DEBT OUTPUT

use flipfleet_rect_global_isotropy

arguments = argv()
if arguments.size() != 8
  << "usage: flipfleet_rect_orbit_door_cli SEED N M P SAMPLES MAX_STEPS MAX_DEBT OUTPUT"
  exit(2)

seed_path = arguments[0]
n = arguments[1].to_i() ## i64
m = arguments[2].to_i() ## i64
p = arguments[3].to_i() ## i64
samples = arguments[4].to_i() ## i64
max_steps = arguments[5].to_i() ## i64
max_debt = arguments[6].to_i() ## i64
output_path = arguments[7]

if n < 1 || m < 1 || p < 1 || n*m > 63 || m*p > 63 || n*p > 63
  << "RECT_ORBIT_DOOR_ERROR code=shape"
  exit(2)
if samples < 1 || samples > 16384 || max_steps < 1 || max_steps > 256 || max_debt < 0 || max_debt > 1000000
  << "RECT_ORBIT_DOOR_ERROR code=bounds"
  exit(2)

source = ffbc_load_exact(seed_path,n,m,p,512)
if source == nil || source.rank() < 1 || ffbc_verify_exact(source) != 1
  << "RECT_ORBIT_DOOR_ERROR code=seed path=" + seed_path
  exit(1)

source_density = fflc_density(source) ## i64
best = nil
best_distance = 0 - 1 ## i64
best_density = 0x7fffffff ## i64
best_pairs = 0 - 1 ## i64
best_sample = 0 - 1 ## i64
best_moves = 0 ## i64
eligible = 0 ## i64
gated = 0 ## i64
total_steps = 0 ## i64

sample = 0 ## i64
while sample < samples
  moves = 1 + (sample % 32) ## i64
  image = fflc_sparse_leaf_image(source, 32452843 * (sample + 1) + source.rank() * 49999, moves)
  if image != nil && ffbc_verify_exact(image) == 1
    gated += 1
    local_stats = i64[4]
    candidate = ffrgir_descent(image,max_steps,local_stats)
    total_steps += local_stats[2]
    if candidate != nil && candidate.rank() == source.rank() && ffbc_verify_exact(candidate) == 1
      gated += 1
      density = fflc_density(candidate) ## i64
      if density <= source_density + max_debt
        eligible += 1
        distance = fflc_term_set_distance(source,candidate) ## i64
        pairs = fflc_equal_factor_pairs(candidate) ## i64
        better = 0 ## i64
        if distance > best_distance
          better = 1
        elsif distance == best_distance && density < best_density
          better = 1
        elsif distance == best_distance && density == best_density && pairs > best_pairs
          better = 1
        if better == 1
          best = candidate
          best_distance = distance
          best_density = density
          best_pairs = pairs
          best_sample = sample
          best_moves = moves

  sample += 1

if best == nil || best_distance <= 0 || ffbc_verify_exact(best) != 1
  << "RECT_ORBIT_DOOR_RESULT shape=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " found=0 source_density=" + source_density.to_s() + " max_debt=" + max_debt.to_s() + " samples=" + samples.to_s() + " eligible=" + eligible.to_s() + " gated=" + gated.to_s() + " descent_steps=" + total_steps.to_s()
  exit(3)

if ffbc_write(output_path,best) != best.rank()
  << "RECT_ORBIT_DOOR_ERROR code=write path=" + output_path
  exit(1)
reparsed = ffbc_load_exact(output_path,n,m,p,512)
if reparsed == nil || reparsed.rank() != best.rank() || ffbc_verify_exact(reparsed) != 1
  << "RECT_ORBIT_DOOR_ERROR code=reparse path=" + output_path
  exit(1)
if fflc_density(reparsed) != best_density || fflc_term_set_distance(source,reparsed) != best_distance
  << "RECT_ORBIT_DOOR_ERROR code=descriptor path=" + output_path
  exit(1)

<< "RECT_ORBIT_DOOR_RESULT shape=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " found=1 rank=" + best.rank().to_s() + " source_density=" + source_density.to_s() + " density=" + best_density.to_s() + " debt=" + (best_density-source_density).to_s() + " distance=" + best_distance.to_s() + " equal_factor_pairs=" + best_pairs.to_s() + " sample=" + best_sample.to_s() + " word_moves=" + best_moves.to_s() + " samples=" + samples.to_s() + " eligible=" + eligible.to_s() + " gated=" + gated.to_s() + " descent_steps=" + total_steps.to_s() + " exact=1 reparsed=1 output=" + output_path
