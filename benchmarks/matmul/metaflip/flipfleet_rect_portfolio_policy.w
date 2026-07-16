# Adaptive CPU portfolio policy for independent rectangular FlipFleet shapes.
#
# The policy is coordinator-agnostic and performs no I/O or process control.
# A caller supplies one row per shape:
#
#   ready              CPU campaign can launch now
#   gpu_capable        a separate GPU implementation can cover this shape
#   rank_drops         cumulative exact rank improvements
#   density_gains      cumulative same-rank bits removed
#   leverage           downstream formula occurrences/impact units
#   exposure           cumulative CPU allocation quanta
#   failures           cumulative launch/runtime failures
#
# Every ready shape gets a one-thread starvation floor when J permits. If J is
# smaller than the ready set, a deterministic epoch-rotating window gets the
# floors, so no fixed prefix monopolizes a small machine. Remaining threads
# are assigned by a D'Hondt divisor over integer adaptive scores. This gives
# exact conservation without floating point or nondeterministic sampling.

-> ffrpp_default_shape_count() i64
  9

-> ffrpp_default_base_weight(shape) (i64) i64
  # A rank-17 hit at 225 would close a rigorously certified one-term gap.
  if shape == 225
    return 40
  if shape == 226
    return 24
  if shape == 234
    return 8
  if shape == 245
    return 8
  # The updated two-wide audit makes 256 the leading small-cross primitive:
  # one saved rank propagates through 10 saved and 49 strict audited formulas.
  if shape == 256
    return 30
  if shape == 457
    return 32
  if shape == 346
    return 24
  if shape == 347
    return 26
  if shape == 456
    return 28
  if shape == 445
    return 18
  if shape == 334
    return 8
  if shape == 344
    return 10
  if shape == 335
    return 8
  if shape == 345
    return 16
  if shape == 355
    return 12
  if shape == 356
    return 25
  if shape == 357
    return 23
  if shape == 455
    return 20
  if shape == 446
    return 22
  if shape == 458
    return 24
  if shape == 466
    return 22
  if shape == 467
    return 31
  if shape == 468
    return 22
  if shape == 567
    return 27
  8

-> ffrpp_default_leverage(shape) (i64) i64
  # The primitive-gap rows use mathematical-closure priority units rather than
  # downstream block-formula occurrences. 225 is the only certified one-term
  # gap in this portfolio and therefore belongs in the default mix.
  if shape == 225
    return 2500
  if shape == 226
    return 400
  # Neither older tiny shape occurs in the current materialized/audited
  # block-formula set. Keep the minimum positive score for explicit campaigns.
  if shape == 234 || shape == 245
    return 1
  # 82 guaranteed saved plus 652 strict-audit terms become downstream gains.
  if shape == 256
    return 734
  if shape == 457
    return 2043
  if shape == 346
    return 1679
  if shape == 347
    return 1458
  if shape == 456
    return 1683
  if shape == 445
    return 1411
  if shape == 334
    return 3
  if shape == 344
    return 258
  if shape == 335
    return 112
  if shape == 345
    return 709
  if shape == 355
    return 485
  if shape == 356
    return 1638
  if shape == 357
    return 1223
  if shape == 455
    return 950
  if shape == 446
    return 1106
  if shape == 458
    return 1325
  if shape == 466
    return 1176
  if shape == 467
    return 2002
  if shape == 468
    return 1202
  if shape == 567
    return 1579
  1

-> ffrpp_default_gpu_capable(shape) (i64) i64
  if shape == 256 || shape == 445 || shape == 334 || shape == 344
    return 1
  0

-> ffrpp_shape_name(shape) (i64)
  a = shape / 100 ## i64
  b = (shape / 10) % 10 ## i64
  c = shape % 10 ## i64
  a.to_s() + "x" + b.to_s() + "x" + c.to_s()

-> ffrpp_fill_defaults(shapes, ready, gpu_capable, leverage) (i64[] i64[] i64[] i64[]) i64
  count = ffrpp_default_shape_count() ## i64
  if shapes.size() < count || ready.size() < count || gpu_capable.size() < count || leverage.size() < count
    return 0
  shapes[0] = 225
  shapes[1] = 457
  shapes[2] = 346
  shapes[3] = 456
  shapes[4] = 446
  shapes[5] = 445
  shapes[6] = 256
  shapes[7] = 347
  shapes[8] = 356
  i = 0 ## i64
  while i < count
    ready[i] = 1
    gpu_capable[i] = ffrpp_default_gpu_capable(shapes[i])
    leverage[i] = ffrpp_default_leverage(shapes[i])
    i += 1
  count

-> ffrpp_clamp(value, low, high) (i64 i64 i64) i64
  if value < low
    return low
  if value > high
    return high
  value

-> ffrpp_inputs_fit(count, shapes, ready, gpu_capable, rank_drops, density_gains, leverage, exposure, failures, allocation, scores) i64
  if count < 1
    return 0
  if shapes.size() < count || ready.size() < count || gpu_capable.size() < count
    return 0
  if rank_drops.size() < count || density_gains.size() < count || leverage.size() < count
    return 0
  if exposure.size() < count || failures.size() < count
    return 0
  if allocation.size() < count || scores.size() < count
    return 0
  1

# Scores are deliberately bounded below 4e9. Rank drops dominate density,
# density dominates static leverage, and exposure converts both observations
# to yield. Underexposed shapes receive an exploration term based on aggregate
# portfolio exposure. GPU-capable shapes retain CPU coverage but receive 3/4
# of the score because another engine can cover part of their search space.
-> ffrpp_score(shape, gpu_capable, rank_drops, density_gains, leverage, exposure, failures, total_exposure, count) (i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  drops = ffrpp_clamp(rank_drops, 0, 100000) ## i64
  density = ffrpp_clamp(density_gains, 0, 1000000000) ## i64
  impact = ffrpp_clamp(leverage, 0, 1000000) ## i64
  seen = ffrpp_clamp(exposure, 0, 1000000000000) ## i64
  fail = ffrpp_clamp(failures, 0, 31) ## i64
  aggregate = ffrpp_clamp(total_exposure, 0, 4000000000000) ## i64

  base = ffrpp_default_base_weight(shape) * 10000 ## i64
  static_value = impact * 100 ## i64
  empirical = (drops * 5000000 + density * 1000) / (seen + 1) ## i64
  if empirical > 2000000000
    empirical = 2000000000
  # A completely fresh portfolio follows the audited defaults. Exploration
  # appears only after some campaign has actually accumulated exposure, then
  # strongly pulls genuinely underexposed siblings back into the mix.
  exploration = (aggregate * 200000) / (seen + 1) ## i64
  if exploration > 2000000
    exploration = 2000000
  score = base + static_value + empirical + exploration ## i64
  if gpu_capable != 0
    score = (score * 3) / 4
  # A ready campaign in backoff should be marked not-ready. This softer
  # penalty handles historical failures without permanently starving it.
  divisor = 1 + fail ## i64
  if divisor > 8
    divisor = 8
  score = score / divisor
  if score < 1
    score = 1
  if score > 4000000000
    score = 4000000000
  score

-> ffrpp_ready_count(ready, count) (i64[] i64) i64
  total = 0 ## i64
  i = 0 ## i64
  while i < count
    if ready[i] != 0
      total += 1
    i += 1
  total

-> ffrpp_sum(values, count) (i64[] i64) i64
  total = 0 ## i64
  i = 0 ## i64
  while i < count
    total += values[i]
    i += 1
  total

# Allocate `total_j` CPU workers. Returns total_j when at least one shape is
# ready, zero when none are ready/total_j is zero, and -1 for malformed arrays.
-> ffrpp_allocate(total_j, epoch, shapes, ready, gpu_capable, rank_drops, density_gains, leverage, exposure, failures, allocation, scores) i64
  count = shapes.size() ## i64
  if ffrpp_inputs_fit(count, shapes, ready, gpu_capable, rank_drops, density_gains, leverage, exposure, failures, allocation, scores) == 0
    return 0 - 1
  i = 0 ## i64
  while i < count
    allocation[i] = 0
    scores[i] = 0
    i += 1
  if total_j <= 0
    return 0
  live = ffrpp_ready_count(ready, count) ## i64
  if live == 0
    return 0

  total_exposure = 0 ## i64
  i = 0
  while i < count
    if ready[i] != 0
      total_exposure += ffrpp_clamp(exposure[i], 0, 1000000000000)
    i += 1
  i = 0
  while i < count
    if ready[i] != 0
      scores[i] = ffrpp_score(shapes[i], gpu_capable[i], rank_drops[i], density_gains[i], leverage[i], exposure[i], failures[i], total_exposure, live)
    i += 1

  used = 0 ## i64
  # Hard floor when capacity permits; otherwise rotate a window through the
  # ready-only ordinal sequence. This is independent of unavailable entries.
  if total_j >= live
    i = 0
    while i < count
      if ready[i] != 0
        allocation[i] = 1
        used += 1
      i += 1
  else
    start = epoch % live ## i64
    if start < 0
      start += live
    slot = 0 ## i64
    while slot < total_j
      wanted = (start + slot) % live ## i64
      ordinal = 0 ## i64
      i = 0
      found = 0
      while i < count && found == 0
        if ready[i] != 0
          if ordinal == wanted
            allocation[i] = 1
            used += 1
            found = 1
          ordinal += 1
        i += 1
      slot += 1

  # D'Hondt: maximize score/(allocation+1), cross-multiplied exactly. Rotate
  # equal-score tie priority by epoch to avoid a permanent array-order bias.
  tie_start = epoch % count ## i64
  if tie_start < 0
    tie_start += count
  while used < total_j
    best = 0 - 1 ## i64
    i = 0
    while i < count
      if ready[i] != 0
        if best < 0
          best = i
        else
          left = scores[i] * (allocation[best] + 1) ## i64
          right = scores[best] * (allocation[i] + 1) ## i64
          if left > right
            best = i
          if left == right
            i_key = (i - tie_start + count) % count ## i64
            best_key = (best - tie_start + count) % count ## i64
            if i_key < best_key
              best = i
      i += 1
    if best < 0
      return used
    allocation[best] = allocation[best] + 1
    used += 1
  used

-> ffrpp_allocation_valid(total_j, ready, allocation, count) (i64 i64[] i64[] i64) i64
  if ready.size() < count || allocation.size() < count
    return 0
  live = ffrpp_ready_count(ready, count) ## i64
  expected = total_j ## i64
  if total_j <= 0 || live == 0
    expected = 0
  i = 0 ## i64
  while i < count
    if allocation[i] < 0
      return 0
    if ready[i] == 0 && allocation[i] != 0
      return 0
    if total_j >= live && live > 0 && ready[i] != 0 && allocation[i] < 1
      return 0
    i += 1
  if ffrpp_sum(allocation, count) != expected
    return 0
  1

-> ffrpp_report(epoch, shapes, ready, gpu_capable, allocation, scores) (i64 i64[] i64[] i64[] i64[] i64[])
  count = shapes.size() ## i64
  body = "RECT_PORTFOLIO epoch=" + epoch.to_s() + " total=" + ffrpp_sum(allocation, count).to_s() ## String
  i = 0 ## i64
  while i < count
    body = body + " " + ffrpp_shape_name(shapes[i]) + ":j" + allocation[i].to_s()
    body = body + ",score" + scores[i].to_s() + ",ready" + ready[i].to_s() + ",gpu" + gpu_capable[i].to_s()
    i += 1
  body
