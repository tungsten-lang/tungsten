# Bounded CPU experimentation policy.  Exactly one island races these arms;
# the rest of the CPU fleet keeps its stable profile.

use ../scheme
use ../strategies/fixed_rank_pocket

-> ffcr_arm_count() i64
  11

-> ffcr_arm_name(arm) (i64)
  names = ["baseline", "quick-narrow", "slow-deep", "flip-only", "dense-work", "fast-band", "short-splits", "marathon", "four-split", "fixed-pocket", "axis-sweep"]
  names[arm % names.size()]

# controls is the seven-word ffw_walk_tuned ABI; quotas receives work/wander.
-> ffcr_fill_arm(arm, base_work, base_wander, controls, quotas) (i64 i64 i64 i64[] i64[]) i64
  selected = arm % ffcr_arm_count() ## i64
  # Baseline: preserve the production worker's current behavior.
  controls[0] = 2000
  controls[1] = 6
  controls[2] = 300000
  controls[3] = 1
  controls[4] = 12
  controls[5] = 7
  controls[6] = 60
  quotas[0] = base_work
  quotas[1] = base_wander
  if selected == 1
    controls[0] = 500
    controls[1] = 4
    controls[2] = 150000
    controls[4] = 8
    controls[5] = 6
    controls[6] = 48
    quotas[0] = base_work / 4
    quotas[1] = base_wander / 4
  if selected == 2
    controls[0] = 8000
    controls[2] = 600000
    controls[4] = 16
    controls[5] = 8
    controls[6] = 72
    quotas[0] = base_work * 2
    quotas[1] = base_wander * 2
  if selected == 3
    controls[0] = 0
    controls[1] = 3
    controls[3] = 2
    quotas[0] = base_work / 2
    quotas[1] = base_wander / 2
  if selected == 4
    controls[0] = 1000
    controls[1] = 8
    controls[2] = 200000
    controls[4] = 6
    controls[5] = 9
    controls[6] = 54
    quotas[1] = base_wander / 2
  if selected == 5
    controls[0] = 4000
    controls[1] = 2
    controls[2] = 100000
    controls[3] = 2
    controls[4] = 18
    controls[5] = 5
    controls[6] = 72
  if selected == 6
    controls[0] = 250
    controls[2] = 600000
    controls[4] = 4
    controls[5] = 10
    controls[6] = 40
    quotas[0] = base_work / 4
    quotas[1] = base_wander / 4
  if selected == 7
    controls[0] = 16000
    controls[1] = 10
    controls[2] = 1200000
    controls[4] = 24
    controls[5] = 6
    controls[6] = 84
    quotas[0] = base_work * 2
    quotas[1] = base_wander * 2
  # The only measured density improvement in the three-anchor continuation
  # study came from its ordinary four-split control (5x5 r93/d968 -> d967).
  # Keep that evidence in exactly one bounded racer lane: open a +4 shoulder
  # once at lease start, then let the ordinary tuned walker try to close it.
  if selected == 8
    controls[0] = 2000
    controls[1] = 6
    controls[2] = 600000
    controls[4] = 12
    controls[5] = 7
    controls[6] = 60
    quotas[0] = base_work
    quotas[1] = base_wander
  # One bounded productive-word closure at lease start, then the ordinary
  # tuned walker continues from the exact endpoint. A cheap ordinal-1 prefix
  # is followed by strict-gain complete ticket rescans. The 8-step/4-prefix/
  # 5-round/64-ticket cap keeps this cold racer arm negligible fleet-wide;
  # misses are decomposition-preserving and adaptive reward controls exposure.
  if selected == 9
    controls[0] = 2000
    controls[1] = 6
    controls[2] = 300000
    controls[4] = 12
    controls[5] = 7
    controls[6] = 60
    quotas[0] = base_work
    quotas[1] = base_wander
  # Matched-wall-time record-plateau trials found that reusing a selected term
  # after an empty first axis raises legal/accepted flips per second on all
  # tested sizes (3x3 +31%, 5x5 +36%, 7x7 +19%). The negative cadence is
  # an internal cpu_pool dispatch tag; the axis-sweep walker restores its
  # magnitude and therefore retains the ordinary 1-in-2000 wander split.
  if selected == 10
    controls[0] = 0 - 2000
    controls[1] = 6
    controls[2] = 300000
    controls[4] = 12
    controls[5] = 7
    controls[6] = 60
    quotas[0] = base_work
    quotas[1] = base_wander
  if quotas[0] < 1
    quotas[0] = 1
  if quotas[1] < 1
    quotas[1] = 1
  selected

# setup telemetry: rank drop, density gain, pocket steps, ticket searches,
# last selected ticket, retained pocket states, pocket proposals. The fleet
# folds proposal count into exposure and direct gain into lease reward.
-> ffcr_apply_arm_measured(state, arm, base_work, base_wander, controls, setup) (i64[] i64 i64 i64 i64[] i64[]) i64
  i=0 ## i64
  while i<setup.size()
    setup[i]=0
    i+=1
  before_rank=ffw_best_rank(state) ## i64
  before_bits=ffw_best_bits(state) ## i64
  quotas = i64[2]
  selected = ffcr_fill_arm(arm, base_work, base_wander, controls, quotas) ## i64
  # A zero-edge state cannot benefit from alternate-axis retries.  Keep the
  # arm label/reward accounting stable but dispatch its lease through the
  # ordinary walker until another exact setup creates factor reuse.
  if selected == 10 && ffw_partnerable_incidences(state) == 0
    controls[0] = 2000
  z = ffw_set_zone_quotas(state, quotas[0], quotas[1]) ## i64
  state[11] = controls[5]
  state[41] = controls[6]
  if selected == 8
    # Splits are rejected above best+band.  A seed starts with a randomized
    # band in 1..4, so make the arm's promised +4 shoulder reachable.
    if state[10] < 4
      state[10] = 4
    target_rank = ffw_current_rank(state) + 4 ## i64
    tries = 0 ## i64
    while ffw_current_rank(state) < target_rank && tries < 16384
      z = ffw_try_split(state) ## i64
      tries += 1
  if selected == 9
    pocket_meta = i64[19]
    pocket_applied = ffpa_apply_greedy_closure(state, 8, 4, 5, 64, 5, 5, 512, 12, pocket_meta) ## i64
    if setup.size()>=7
      setup[2]=pocket_meta[6]
      setup[3]=pocket_meta[13]
      setup[4]=pocket_meta[14]
      setup[5]=pocket_meta[0]
      setup[6]=pocket_meta[1]
  after_rank=ffw_best_rank(state) ## i64
  after_bits=ffw_best_bits(state) ## i64
  if setup.size()>=2
    if after_rank<before_rank
      setup[0]=before_rank-after_rank
    if after_rank==before_rank && after_bits<before_bits
      setup[1]=before_bits-after_bits
  selected

-> ffcr_apply_arm(state, arm, base_work, base_wander, controls) (i64[] i64 i64 i64 i64[]) i64
  setup=i64[7]
  ffcr_apply_arm_measured(state,arm,base_work,base_wander,controls,setup)

# Untried arms rotate first.  Afterwards rank drops dominate, canonical basin
# yield is positive, and return-to-origin hazard is explicitly negative.
-> ffcr_select_arm(epoch, pulls, exposure, novel, returns, drops, density) (i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  count = ffcr_arm_count() ## i64
  offset = 0 ## i64
  while offset < count
    arm = (epoch + offset) % count ## i64
    if pulls[arm] == 0
      return arm
    offset += 1
  best = 0 ## i64
  best_score = 0 - 9223372036854775807 ## i64
  arm = 0
  while arm < count
    move_units = exposure[arm] / 1000000 + 1 ## i64
    utility = drops[arm] * 2000000 + density[arm] * 250000 + novel[arm] * 100000 - returns[arm] * 75000 ## i64
    score = utility / move_units + 50000 / (pulls[arm] + 1) ## i64
    if score > best_score
      best = arm
      best_score = score
    arm += 1
  best

-> ffcr_record_lease(arm, moves, novel_yield, returned, rank_drop, density_gain, pulls, exposure, novel, returns, drops, density) (i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  selected = arm % ffcr_arm_count() ## i64
  pulls[selected] = pulls[selected] + 1
  if moves > 0
    exposure[selected] = exposure[selected] + moves
  if novel_yield != 0
    novel[selected] = novel[selected] + 1
  if returned != 0
    returns[selected] = returns[selected] + 1
  if rank_drop > 0
    drops[selected] = drops[selected] + rank_drop
  if density_gain > 0
    density[selected] = density[selected] + density_gain
  selected
