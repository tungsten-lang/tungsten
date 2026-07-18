# Deterministic restart-seed scheduling for rectangular CPU islands.
#
# A single rectangular campaign keeps its island states alive between rounds,
# but the multi-shape portfolio intentionally reconstructs them at every epoch
# boundary.  The old coordinator reused the same literal RNG seeds on every
# reconstruction, so an unchanged checkpoint replayed the exact same walks.
# These helpers salt only portfolio restarts; nonce zero preserves standalone
# campaign replay byte-for-byte.

-> ffrcb_mix(value) (i64) i64
  mask = 9223372036854775807 ## i64
  mixed = value & mask ## i64
  mixed = (mixed ^ (mixed >> 29)) & mask
  mixed = (mixed * 6364136223846793005 + 1442695040888963407) & mask
  mixed = (mixed ^ (mixed >> 31)) & mask
  if mixed < 1
    mixed = 1
  mixed

# Stable identity for one shape segment. Segment zero is the base quota;
# positive segments are straggler-fill restarts within the same epoch.
-> ffrcb_portfolio_nonce(epoch, shape_slot, segment) (i64 i64 i64) i64
  if epoch < 0
    epoch = 0
  if shape_slot < 0
    shape_slot = 0
  if segment < 0
    segment = 0
  raw = (epoch + 1) * 1000003 ## i64
  raw = raw ^ ((shape_slot + 1) * 9176)
  raw = raw ^ ((segment + 1) * 65537)
  ffrcb_mix(raw)

# Derive one worker seed while retaining the historical stream for nonce zero.
# The base literal already distinguishes initialization roles; lane and door
# keep different islands separated even if a future caller reuses a base.
-> ffrcb_seed(base, restart_nonce, lane, door) (i64 i64 i64 i64) i64
  if restart_nonce == 0
    return base
  if lane < 0
    lane = 0
  if door < 0
    door = 0
  raw = base ^ restart_nonce ## i64
  raw = raw ^ ((lane + 1) * 104729)
  raw = raw ^ ((door + 1) * 13007)
  ffrcb_mix(raw)

# Historical mixed-nonce selector retained for deterministic before/after
# coverage audits. Production portfolio children use the low-discrepancy
# ticket below; nonce zero still describes the standalone leader schedule.
-> ffrcb_door_choice(restart_nonce, choices) (i64 i64) i64
  if restart_nonce == 0 || choices < 2
    return 0
  ffrcb_mix(restart_nonce ^ 7046029254386353131) % choices

# Low-discrepancy door ticket for one portfolio segment. Keep this separate
# from the mixed restart nonce: the nonce should retain high-entropy proposal
# streams, while the ticket must cover every leader/built-in/saved door in a
# bounded prefix. Shape-slot staggering prevents all one-worker children from
# selecting the same role in the same portfolio epoch. Positive fill segments
# advance to another door without perturbing the base epoch cycle.
-> ffrcb_portfolio_door_ticket(epoch, shape_slot, segment) (i64 i64 i64) i64
  if epoch < 0
    epoch = 0
  if shape_slot < 0
    shape_slot = 0
  if segment < 0
    segment = 0
  epoch + shape_slot + segment

# A negative ticket means the historical standalone schedule (leader). For a
# portfolio ticket, consecutive epochs differ by one, so every full `choices`
# window visits each door exactly once and every prefix has imbalance <= 1.
-> ffrcb_scheduled_door_choice(ticket, choices) (i64 i64) i64
  if ticket < 0 || choices < 2
    return 0
  ticket % choices

# Start a multiworker side-door window at the next nonoverlapping block when
# possible. The historical +1 offset made adjacent portfolio epochs repeat
# `walkers-2` of their side roles; multiplying the bounded ticket by the
# window width exposes all roles in ceil(choices / width) epochs while
# retaining exact long-run balance. One/two-worker schedules are unchanged.
-> ffrcb_multiworker_door_offset(ticket, choices, walkers) (i64 i64 i64) i64
  if ticket < 0 || choices < 2 || walkers < 2
    return 0
  width = walkers - 1 ## i64
  if width > choices
    width = choices
  base = ffrcb_scheduled_door_choice(ticket, choices) ## i64
  (base * width) % choices

# A plateau with no repeated factor on any axis has no ordinary pair-flip
# edge. Alternate exact +1/+2 braided shoulders across lanes, and reverse the
# parity on each portfolio restart, so a one-worker child also sees both debt
# depths. A negative ticket preserves deterministic standalone lane ordering.
-> ffrcb_initial_debt_depth(partnerable_incidences, lane, ticket) (i64 i64 i64) i64
  if partnerable_incidences > 0
    return 0
  if lane < 0
    lane = 0
  phase = 0 ## i64
  if ticket >= 0
    phase = ticket & 1
  1 + ((lane + phase) & 1)
