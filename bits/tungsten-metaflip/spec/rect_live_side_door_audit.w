# Read-only audit for a rectangular leader plus an arbitrary number of exact
# side-door files.  This is intentionally separate from campaign code: it is
# useful for inspecting a live checkpoint copy without mutating the archive.

use ../lib/metaflip/rect/portfolio

-> ffrlsd_fail(label) (String) i64
  << "FAIL rect_live_side_door_audit: " + label
  exit(1)
  0

-> ffrlsd_parse_dimension(part) (String) i64
  value = part.to_i() ## i64
  if value < 1
    return 0
  value

args = argv()
if args.size() < 3
  z = ffrlsd_fail("usage: SHAPE LEADER SIDE...") ## i64

parts = args[0].downcase.split("x")
if parts.size() != 3
  z = ffrlsd_fail("shape=" + args[0]) ## i64
n = ffrlsd_parse_dimension(parts[0]) ## i64
m = ffrlsd_parse_dimension(parts[1]) ## i64
p = ffrlsd_parse_dimension(parts[2]) ## i64
if n < 1 || m < 1 || p < 1
  z = ffrlsd_fail("shape=" + args[0]) ## i64

capacity = ffr_default_capacity(n, m, p) ## i64
states = []
i = 1 ## i64
while i < args.size()
  state = i64[ffr_state_size(capacity)]
  rank = ffr_load_scheme_cap(state, args[i], n, m, p, capacity, 610001 + i * 104729, 4, 4, 250000, 50000) ## i64
  if rank < 1 || ffr_verify_best_exact(state, n, m, p) != 1
    z = ffrlsd_fail("inexact path=" + args[i]) ## i64
  states.push(state)
  i += 1

leader = states[0]
i = 0
while i < states.size()
  state = states[i]
  label = "leader"
  if i > 0
    label = "side" + (i - 1).to_s()
  << "RECT_LIVE_DOOR shape=" + args[0] + " label=" + label + " rank=" + ffr_best_rank(state).to_s() + " bits=" + ffr_best_bits(state).to_s() + " signature=" + ffrda_structural_signature(state).to_s() + " leader_distance=" + ffrda_best_distance(leader, state).to_s()
  i += 1

i = 0
while i < states.size()
  j = i + 1 ## i64
  while j < states.size()
    << "RECT_LIVE_DISTANCE shape=" + args[0] + " left=" + i.to_s() + " right=" + j.to_s() + " distance=" + ffrda_best_distance(states[i], states[j]).to_s()
    j += 1
  i += 1

<< "PASS rect_live_side_door_audit shape=" + args[0] + " states=" + states.size().to_s()
