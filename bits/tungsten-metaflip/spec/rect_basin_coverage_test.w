use ../lib/metaflip/rect/basins
use ../lib/metaflip/rect/doors
use ../lib/metaflip/seeds/rect

-> ffrbct_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

-> ffrbct_legacy_counts(shape_slot, choices, epochs) (i64 i64 i64)
  counts = i64[choices]
  epoch = 0 ## i64
  while epoch < epochs
    nonce = ffrcb_portfolio_nonce(epoch, shape_slot, 0) ## i64
    choice = ffrcb_door_choice(nonce, choices) ## i64
    counts[choice] += 1
    epoch += 1
  counts

-> ffrbct_scheduled_counts(shape_slot, choices, epochs) (i64 i64 i64)
  counts = i64[choices]
  epoch = 0 ## i64
  while epoch < epochs
    ticket = ffrcb_portfolio_door_ticket(epoch, shape_slot, 0) ## i64
    choice = ffrcb_scheduled_door_choice(ticket, choices) ## i64
    counts[choice] += 1
    epoch += 1
  counts

-> ffrbct_spread(counts) (i64[]) i64
  if counts.size() < 1
    return 0
  minimum = counts[0] ## i64
  maximum = counts[0] ## i64
  i = 1 ## i64
  while i < counts.size()
    if counts[i] < minimum
      minimum = counts[i]
    if counts[i] > maximum
      maximum = counts[i]
    i += 1
  maximum - minimum

-> ffrbct_all(counts, expected) (i64[] i64) i64
  i = 0 ## i64
  while i < counts.size()
    if counts[i] != expected
      return 0
    i += 1
  1

-> ffrbct_text(counts) (i64[])
  out = ""
  i = 0 ## i64
  while i < counts.size()
    if i > 0
      out = out + "/"
    out = out + counts[i].to_s()
    i += 1
  out

-> ffrbct_multiworker_counts(shape_slot, choices, walkers, epochs, blocked) (i64 i64 i64 i64 i64)
  counts = i64[choices]
  epoch = 0 ## i64
  while epoch < epochs
    ticket = ffrcb_portfolio_door_ticket(epoch, shape_slot, 0) ## i64
    offset = ffrcb_scheduled_door_choice(ticket, choices) ## i64
    if blocked != 0
      offset = ffrcb_multiworker_door_offset(ticket, choices, walkers)
    lane = 1 ## i64
    while lane < walkers
      counts[(offset + lane - 1) % choices] += 1
      lane += 1
    epoch += 1
  counts

-> ffrbct_seen(counts) (i64[]) i64
  seen = 0 ## i64
  i = 0 ## i64
  while i < counts.size()
    if counts[i] > 0
      seen += 1
    i += 1
  seen

-> ffrbct_budget_counts(choices, walkers, ticket) (i64 i64 i64)
  counts = i64[choices]
  side_budget = ffrcb_side_lane_budget(walkers, choices) ## i64
  if side_budget > 0
    offset = ffrcb_multiworker_door_offset(ticket, choices, side_budget + 1) ## i64
    lane = 1 ## i64
    while lane <= side_budget
      counts[(offset + lane - 1) % choices] += 1
      lane += 1
  counts

z = ffrbct_expect("J1 keeps its one scheduled lane outside the multiworker budget", ffrcb_side_lane_budget(1, 8) == 0)
z = ffrbct_expect("J2 keeps one leader and one side lane", ffrcb_side_lane_budget(2, 8) == 1)
z = ffrbct_expect("J5 retains four side lanes when doors exceed width", ffrcb_side_lane_budget(5, 8) == 4)
z = ffrbct_expect("J14 covers twelve sides and keeps two leaders", ffrcb_side_lane_budget(14, 12) == 12)
z = ffrbct_expect("J15 covers nine sides and keeps six leaders", ffrcb_side_lane_budget(15, 9) == 9)
z = ffrbct_expect("J64 splits surplus width evenly", ffrcb_side_lane_budget(64, 2) == 32 && ffrcb_side_lane_budget(64, 12) == 32)

wide_side_counts = [3,4,5,3,3,3]
wide_shape = 0 ## i64
while wide_shape < wide_side_counts.size()
  side_count = wide_side_counts[wide_shape] ## i64
  side_budget = ffrcb_side_lane_budget(64, side_count) ## i64
  counts = ffrbct_budget_counts(side_count, 64, wide_shape)
  z = ffrbct_expect("J64 shape " + wide_shape.to_s() + " keeps 32 leader lanes", 64 - side_budget == 32)
  z = ffrbct_expect("J64 shape " + wide_shape.to_s() + " uses 32 side lanes", side_budget == 32)
  z = ffrbct_expect("J64 shape " + wide_shape.to_s() + " reaches every side", ffrbct_seen(counts) == side_count)
  z = ffrbct_expect("J64 shape " + wide_shape.to_s() + " balances side exposure", ffrbct_spread(counts) <= 1)
  wide_shape += 1

# In the default portfolio, 2x2x7, 2x2x8, and 2x2x9 occupy slots 2, 3, 4.
# Before any durable side doors exist p7/p8 choose among leader/R+1/R+2.
# The mixed-nonce selector was reachable but badly imbalanced in short
# prefixes: p7 did not schedule its R+1 door once in the first six epochs.
legacy_p7_three = ffrbct_legacy_counts(2, 3, 6)
z = ffrbct_expect("captured p7 three-door plateau skew", legacy_p7_three[0] == 4 && legacy_p7_three[1] == 0 && legacy_p7_three[2] == 2)

# p9 additionally preserves two independent rank-32 doors, so its checked-in
# profile has five choices before any durable side archive exists. The old
# selector missed one of those doors entirely in its first two full windows.
p9_initial_choices = ffrp_frontier_seed_count(2, 2, 9) ## i64
legacy_p9_five = ffrbct_legacy_counts(4, p9_initial_choices, 10)
z = ffrbct_expect("229 profile exposes five checked-in doors", p9_initial_choices == 5)
z = ffrbct_expect("captured p9 five-door plateau skew", legacy_p9_five[0] == 4 && legacy_p9_five[1] == 3 && legacy_p9_five[2] == 0 && legacy_p9_five[3] == 1 && legacy_p9_five[4] == 2)

# Under the legacy four-slot archive p7/p8 had seven choices. The old p7
# schedule still completely missed one door after 28 base epochs; p8 heavily
# favored one door. Retain these measurements as an executable audit.
legacy_p7_seven = ffrbct_legacy_counts(2, 7, 28)
legacy_p8_seven = ffrbct_legacy_counts(3, 7, 28)
z = ffrbct_expect("captured p7 seven-door plateau skew", legacy_p7_seven[0] == 3 && legacy_p7_seven[1] == 0 && legacy_p7_seven[2] == 3 && legacy_p7_seven[3] == 7 && legacy_p7_seven[4] == 4 && legacy_p7_seven[5] == 5 && legacy_p7_seven[6] == 6)
z = ffrbct_expect("captured p8 seven-door plateau skew", legacy_p8_seven[0] == 6 && legacy_p8_seven[1] == 2 && legacy_p8_seven[2] == 9 && legacy_p8_seven[3] == 2 && legacy_p8_seven[4] == 2 && legacy_p8_seven[5] == 2 && legacy_p8_seven[6] == 5)

slot = 2 ## i64
while slot <= 3
  scheduled_three = ffrbct_scheduled_counts(slot, 3, 6)
  scheduled_seven = ffrbct_scheduled_counts(slot, 7, 28)
  z = ffrbct_expect("two balanced three-door cycles slot " + slot.to_s(), ffrbct_all(scheduled_three, 2) == 1)
  z = ffrbct_expect("four balanced seven-door cycles slot " + slot.to_s(), ffrbct_all(scheduled_seven, 4) == 1)

  # Any complete base-epoch window covers each door once, not only windows
  # aligned to epoch zero.
  start = 0 ## i64
  while start < 19
    window = i64[7]
    offset = 0 ## i64
    while offset < 7
      ticket = ffrcb_portfolio_door_ticket(start + offset, slot, 0) ## i64
      choice = ffrcb_scheduled_door_choice(ticket, 7) ## i64
      window[choice] += 1
      offset += 1
    z = ffrbct_expect("complete sliding window slot " + slot.to_s() + " start " + start.to_s(), ffrbct_all(window, 1) == 1)
    start += 1

  # Straggler-fill serials advance through different doors in the same way.
  fills = i64[7]
  segment = 0 ## i64
  while segment < 7
    ticket = ffrcb_portfolio_door_ticket(11, slot, segment) ## i64
    choice = ffrcb_scheduled_door_choice(ticket, 7) ## i64
    fills[choice] += 1
    segment += 1
  z = ffrbct_expect("fill segments cover every door slot " + slot.to_s(), ffrbct_all(fills, 1) == 1)
  slot += 1

# Four legacy durable doors expanded p9's five checked-in choices to nine.
# Retain the exact old trace as a regression for the low-discrepancy ticket.
p9_full_choices = p9_initial_choices + 4 ## i64
legacy_p9_nine = ffrbct_legacy_counts(4, p9_full_choices, 36)
scheduled_p9_five = ffrbct_scheduled_counts(4, p9_initial_choices, 10)
scheduled_p9_nine = ffrbct_scheduled_counts(4, p9_full_choices, 36)
z = ffrbct_expect("captured p9 nine-door plateau skew", legacy_p9_nine[0] == 6 && legacy_p9_nine[1] == 3 && legacy_p9_nine[2] == 4 && legacy_p9_nine[3] == 4 && legacy_p9_nine[4] == 7 && legacy_p9_nine[5] == 6 && legacy_p9_nine[6] == 3 && legacy_p9_nine[7] == 1 && legacy_p9_nine[8] == 2)
z = ffrbct_expect("two balanced p9 five-door cycles", ffrbct_all(scheduled_p9_five, 2) == 1)
z = ffrbct_expect("four balanced p9 nine-door cycles", ffrbct_all(scheduled_p9_nine, 4) == 1)

start = 0
while start < 19
  window = i64[p9_full_choices]
  offset = 0 ## i64
  while offset < p9_full_choices
    ticket = ffrcb_portfolio_door_ticket(start + offset, 4, 0) ## i64
    choice = ffrcb_scheduled_door_choice(ticket, p9_full_choices) ## i64
    window[choice] += 1
    offset += 1
  z = ffrbct_expect("complete p9 sliding window start " + start.to_s(), ffrbct_all(window, 1) == 1)
  start += 1

p9_fills = i64[p9_full_choices]
segment = 0
while segment < p9_full_choices
  ticket = ffrcb_portfolio_door_ticket(11, 4, segment) ## i64
  choice = ffrcb_scheduled_door_choice(ticket, p9_full_choices) ## i64
  p9_fills[choice] += 1
  segment += 1
z = ffrbct_expect("p9 fill segments cover every door", ffrbct_all(p9_fills, 1) == 1)

# With the legacy four persisted doors, p9 had eight side choices beside the leader. A
# five-worker child assigns four side roles per epoch. The old +1 window
# repeated three roles at the next restart and needed five epochs to expose all
# eight; block stepping covers all eight in two and is exactly balanced in
# four. Lane zero remains the independent leader in both schedules.
p9_old_two = ffrbct_multiworker_counts(4, 8, 5, 2, 0)
p9_new_two = ffrbct_multiworker_counts(4, 8, 5, 2, 1)
p9_new_four = ffrbct_multiworker_counts(4, 8, 5, 4, 1)
z = ffrbct_expect("old p9 J5 window exposes only five side doors", ffrbct_seen(p9_old_two) == 5)
z = ffrbct_expect("blocked p9 J5 window exposes all side doors", ffrbct_seen(p9_new_two) == 8)
z = ffrbct_expect("blocked p9 J5 windows stay balanced", ffrbct_all(p9_new_four, 2) == 1)

# The production eight-slot archive expands p7 to twelve total starts (the
# d128 leader, retained d132 same-rank door, and +1/+2 shoulders) and p9 to
# thirteen. Complete windows remain exactly balanced. At the active cloud
# widths, one child epoch touches every nonleader source: J14 covers all twelve
# p9 side doors, and J15 covers all nine side doors of a profile such as 4x6x7
# that has one checked-in nonleader plus the eight persisted doors.
current_p7_choices = ffrp_frontier_seed_count(2, 2, 7) + ffrda_cap() ## i64
current_p9_choices = ffrp_frontier_seed_count(2, 2, 9) + ffrda_cap() ## i64
current_p7 = ffrbct_scheduled_counts(2, current_p7_choices, current_p7_choices * 4)
current_p9 = ffrbct_scheduled_counts(4, current_p9_choices, current_p9_choices * 4)
z = ffrbct_expect("eight-slot p7 choices", current_p7_choices == 12 && ffrbct_all(current_p7, 4) == 1)
z = ffrbct_expect("eight-slot p9 choices", current_p9_choices == 13 && ffrbct_all(current_p9, 4) == 1)
p9_current_side = current_p9_choices - 1 ## i64
p9_current_workers = ffrbct_multiworker_counts(4, p9_current_side, 14, 1, 1)
z = ffrbct_expect("J14 reaches every p9 side door", ffrbct_seen(p9_current_workers) == p9_current_side)
p467_current_side = ffrp_frontier_seed_count(4, 6, 7) - 1 + ffrda_cap() ## i64
p467_current_workers = ffrbct_multiworker_counts(2, p467_current_side, 15, 1, 1)
z = ffrbct_expect("J15 reaches every p467 side door", p467_current_side == 9 && ffrbct_seen(p467_current_workers) == p467_current_side)

# Two workers have a one-door window, so their exact historical schedule and
# replay remain unchanged.
epoch = 0
while epoch < 31
  ticket = ffrcb_portfolio_door_ticket(epoch, 4, 0) ## i64
  z = ffrbct_expect("J2 schedule unchanged epoch " + epoch.to_s(), ffrcb_multiworker_door_offset(ticket, 8, 2) == ffrcb_scheduled_door_choice(ticket, 8))
  epoch += 1

# Scheduling never replaces the independently mixed nonce used to seed the
# actual proposal trajectory.
nonce0 = ffrcb_portfolio_nonce(0, 2, 0) ## i64
nonce1 = ffrcb_portfolio_nonce(1, 2, 0) ## i64
z = ffrbct_expect("restart entropy remains epoch-distinct", nonce0 != nonce1)
z = ffrbct_expect("restart streams remain epoch-distinct", ffrcb_seed(82001, nonce0, 0, 2) != ffrcb_seed(82001, nonce1, 0, 0))
z = ffrbct_expect("standalone schedule remains leader", ffrcb_scheduled_door_choice(0 - 1, 7) == 0)

scheduled_p7_seven = ffrbct_scheduled_counts(2, 7, 28)
scheduled_p8_seven = ffrbct_scheduled_counts(3, 7, 28)
<< "PASS rectangular basin coverage old-p7=" + ffrbct_text(legacy_p7_seven) + " new-p7=" + ffrbct_text(scheduled_p7_seven) + " old-p8=" + ffrbct_text(legacy_p8_seven) + " new-p8=" + ffrbct_text(scheduled_p8_seven) + " old-p9=" + ffrbct_text(legacy_p9_nine) + " new-p9=" + ffrbct_text(scheduled_p9_nine)
