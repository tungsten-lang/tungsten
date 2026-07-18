use ../lib/metaflip/fleet/intake

failures = 0 ## i64

-> intake_expect(label, condition) (String bool) i64
  if condition == 0
    << "FAIL large-host intake scheduler: " + label
    return 1
  0

failures += intake_expect("canonical width", ffci_canonical_intake_width() == 12)
failures += intake_expect("small fleet threshold", ffci_wide_fleet_threshold() == 32)
failures += intake_expect("empty budget", ffci_round_budget(0) == 0)
failures += intake_expect("canonical fleet unchanged", ffci_round_budget(12) == 12)
failures += intake_expect("32-wide fleet unchanged", ffci_round_budget(32) == 32)
failures += intake_expect("wide fleet bounded", ffci_round_budget(188) == 12)

# The normal small-host semantics are unchanged: every changed island enters
# the expensive exact-gated coordinator path every round.
slot = 0 ## i64
while slot < 32
  failures += intake_expect("small fleet selects every slot", ffci_should_intake(1, slot, 32, 9, 247, 3200, 247, 3000) == 1)
  slot += 1
failures += intake_expect("unchanged candidate is skipped", ffci_should_intake(0, 0, 12, 0, 246, 1, 247, 3000) == 0)

# On a 188-way host, the ordinary path is exactly twelve slots per round.
# Sixteen rounds cover 192 tickets, hence all islands are inspected and only
# four wraparound islands receive a second ticket.
exposure = i64[188]
selected_total = 0 ## i64
round = 0 ## i64
while round < 16
  selected_round = 0 ## i64
  slot = 0
  while slot < 188
    selected = ffci_rotating_slot(slot, 188, round) ## i64
    if selected == 1
      exposure[slot] = exposure[slot] + 1
      selected_round += 1
      selected_total += 1
    slot += 1
  failures += intake_expect("wide round has exact budget", selected_round == 12)
  round += 1

minimum = exposure[0] ## i64
maximum = exposure[0] ## i64
slot = 1
while slot < exposure.size()
  if exposure[slot] < minimum
    minimum = exposure[slot]
  if exposure[slot] > maximum
    maximum = exposure[slot]
  slot += 1
failures += intake_expect("wide rotation covers every island", minimum >= 1)
failures += intake_expect("wide rotation remains balanced", maximum - minimum <= 1)
failures += intake_expect("wide rotation accounts exact tickets", selected_total == 192)

# Slot 100 is outside round zero's [0, 12) window.  It must still enter
# immediately when either rank or same-rank density can improve the fleet.
failures += intake_expect("rank improvement bypasses window", ffci_should_intake(1, 100, 188, 0, 246, 9999, 247, 3000) == 1)
failures += intake_expect("density improvement bypasses window", ffci_should_intake(1, 100, 188, 0, 247, 2999, 247, 3000) == 1)
failures += intake_expect("noncompetitive candidate waits", ffci_should_intake(1, 100, 188, 0, 247, 3001, 247, 3000) == 0)
failures += intake_expect("equal candidate waits", ffci_should_intake(1, 100, 188, 0, 247, 3000, 247, 3000) == 0)

# Model fleet.w's last-seen contract: a skipped endpoint does not advance its
# observation, so an unchanged endpoint remains pending until its window
# reaches the slot.  Slot 100 first enters the [96, 108) window at round 8.
observed_rank = 248 ## i64
observed_bits = 3200 ## i64
live_rank = 248 ## i64
live_bits = 3199 ## i64
admitted_round = 0 - 1 ## i64
round = 0
while round < 16 && admitted_round < 0
  changed = 0 ## i64
  if live_rank != observed_rank || live_bits != observed_bits
    changed = 1
  if ffci_should_intake(changed, 100, 188, round, live_rank, live_bits, 247, 3000) == 1
    admitted_round = round
    observed_rank = live_rank
    observed_bits = live_bits
  round += 1
failures += intake_expect("steady skipped endpoint remains pending", admitted_round == 8)
failures += intake_expect("observation advances only on admission", observed_rank == live_rank && observed_bits == live_bits)

# A tight scalar benchmark catches accidental O(J^2) policy regressions and
# reports the intended reduction in expensive coordinator admissions.
benchmark_start = ccall("__w_clock_ms") ## i64
checksum = 0 ## i64
iteration = 0 ## i64
while iteration < 100000
  slot = 0
  while slot < 188
    checksum += ffci_rotating_slot(slot, 188, iteration)
    slot += 1
  iteration += 1
benchmark_ms = ccall("__w_clock_ms") - benchmark_start ## i64
failures += intake_expect("benchmark selection count", checksum == 1200000)

if failures > 0
  exit(1)
<< "PASS large-host intake width=12 coverage=" + minimum.to_s() + ".." + maximum.to_s() + " admissions=188->12 policy_18.8M=" + benchmark_ms.to_s() + "ms"
