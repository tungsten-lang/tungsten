# Online return/survival statistics for variable-rank seed tiers.

-> ffrd_tier(debt) (i64) i64
  tier = debt ## i64
  if tier < 0
    tier = 0
  if tier > 3
    tier = 3
  tier

-> ffrd_launch(debt, launches) (i64 i64[]) i64
  tier = ffrd_tier(debt) ## i64
  launches[tier] = launches[tier] + 1
  tier

-> ffrd_finish(debt, returned, moves, returns, failures, exposure) (i64 i64 i64 i64[] i64[] i64[]) i64
  tier = ffrd_tier(debt) ## i64
  if returned != 0
    returns[tier] = returns[tier] + 1
  if returned == 0
    failures[tier] = failures[tier] + 1
  spent = moves ## i64
  if spent < 0
    spent = 0
  exposure[tier] = exposure[tier] + spent
  tier

# Until eight completed trials, preserve the evidence-guided tensor profile.
# Afterwards shorten tiers returning below 12.5%, and deepen tiers returning
# above 50%.  Bounds prevent a noisy campaign from creating pathological dwell.
-> ffrd_budget(base, debt, returns, failures) (i64 i64 i64[] i64[]) i64
  tier = ffrd_tier(debt) ## i64
  completed = returns[tier] + failures[tier] ## i64
  budget = base ## i64
  if completed >= 8
    if returns[tier] * 8 < completed
      budget = base / 2
    if returns[tier] * 2 > completed
      budget = base + base / 2
  minimum = base / 4 ## i64
  maximum = base * 2 ## i64
  if budget < minimum
    budget = minimum
  if budget > maximum
    budget = maximum
  if budget < 1
    budget = 1
  budget
