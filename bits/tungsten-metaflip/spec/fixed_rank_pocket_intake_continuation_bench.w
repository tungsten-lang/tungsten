use ../lib/metaflip/scheme

# Matched continuation fertility check for two arbitrary exact 7x7 archive
# artifacts.  Density alone is not enough to promote a restart root: the
# endpoint must also remain competitive after ordinary Metaflip walking.
if ARGV.size() < 2
  << "usage: fixed_rank_pocket_intake_continuation_bench LEFT RIGHT [TRIALS] [STEPS]"
  exit(2)

left_path = ARGV[0]
right_path = ARGV[1]
trials = 24 ## i64
steps = 1000000 ## i64
if ARGV.size() > 2
  trials = ARGV[2].to_i()
if ARGV.size() > 3
  steps = ARGV[3].to_i()
if trials < 1 || trials > 10000 || steps < 1
  << "FIXED_RANK_POCKET_INTAKE_CONTINUATION_FAIL invalid-budget"
  exit(2)

capacity = 320 ## i64
template_size = ffw_state_size(capacity) ## i64
left_template = i64[template_size]
right_template = i64[template_size]
left_rank = ffw_load_scheme_cap(left_template, left_path, 7, capacity, 290001, 4, 1, steps, steps / 4) ## i64
right_rank = ffw_load_scheme_cap(right_template, right_path, 7, capacity, 290003, 4, 1, steps, steps / 4) ## i64
if left_rank != 247 || right_rank != 247 || ffw_verify_best_exact(left_template, 7) != 1 || ffw_verify_best_exact(right_template, 7) != 1
  << "FIXED_RANK_POCKET_INTAKE_CONTINUATION_FAIL load-or-exact"
  exit(1)

left_wins = 0 ## i64
right_wins = 0 ## i64
ties = 0 ## i64
left_sum = 0 ## i64
right_sum = 0 ## i64
left_min = 999999999 ## i64
right_min = 999999999 ## i64
started = ccall("__w_clock_ms") ## i64
trial = 0 ## i64
while trial < trials
  seed = 300001 + trial * 104729 ## i64
  left = i64[template_size]
  right = i64[template_size]
  if ffw_reseed_from(left, left_template, seed) != 247 || ffw_reseed_from(right, right_template, seed) != 247
    << "FIXED_RANK_POCKET_INTAKE_CONTINUATION_FAIL reseed"
    exit(1)
  ffw_walk(left, steps)
  ffw_walk(right, steps)
  if ffw_verify_best_exact(left, 7) != 1 || ffw_verify_best_exact(right, 7) != 1
    << "FIXED_RANK_POCKET_INTAKE_CONTINUATION_FAIL trial-exact"
    exit(1)
  lb = ffw_best_bits(left) ## i64
  rb = ffw_best_bits(right) ## i64
  left_sum += lb
  right_sum += rb
  if lb < left_min
    left_min = lb
  if rb < right_min
    right_min = rb
  if ffw_best_rank(left) < ffw_best_rank(right) || (ffw_best_rank(left) == ffw_best_rank(right) && lb < rb)
    left_wins += 1
  elsif ffw_best_rank(right) < ffw_best_rank(left) || (ffw_best_rank(right) == ffw_best_rank(left) && rb < lb)
    right_wins += 1
  else
    ties += 1
  trial += 1
elapsed = ccall("__w_clock_ms") - started ## i64

<< "FIXED_RANK_POCKET_INTAKE_CONTINUATION trials=" + trials.to_s() + " steps=" + steps.to_s() + " wins-left/right/tie=" + left_wins.to_s() + "/" + right_wins.to_s() + "/" + ties.to_s() + " start-density=" + ffw_best_bits(left_template).to_s() + "/" + ffw_best_bits(right_template).to_s() + " min=" + left_min.to_s() + "/" + right_min.to_s() + " avg=" + (left_sum / trials).to_s() + "/" + (right_sum / trials).to_s() + " elapsed-ms=" + elapsed.to_s()
