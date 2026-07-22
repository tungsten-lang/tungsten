use ../lib/metaflip/fleet/seven_by_seven
use ../lib/metaflip/seeds/rect
use ../lib/metaflip/rect

failures = 0 ## i64

-> ff7rs_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL 7x7 rectangular seed rotation: " + label
    return 1
  0

root = __DIR__ + "/../lib/metaflip/"
ns = [3, 3]
ms = [3, 4]
ps = [4, 4]
wanted = ["matmul_3x3x4_rank29_d249_peterson_2026_aws_disjoint_gf2.txt",
          "matmul_3x4x4_rank38_d310_peterson_2026_aws_disjoint_gf2.txt"]

component = 0 ## i64
while component < 2
  n = ns[component] ## i64
  m = ms[component] ## i64
  p = ps[component] ## i64
  count = ffrp_frontier_seed_count(n, m, p) ## i64
  failures += ff7rs_expect("component " + component.to_s() + " has multiple registered doors", count > 1)
  seen = i64[count]
  wanted_seen = 0 ## i64
  launch_number = 0 ## i64
  while launch_number < 20
    slot = ff7_rect_seed_choice(component, launch_number, count) ## i64
    repeat = ff7_rect_seed_choice(component, launch_number, count) ## i64
    failures += ff7rs_expect("selection is deterministic", slot == repeat)
    failures += ff7rs_expect("registered slot is bounded", slot >= 0 && slot < count)
    seen[slot] += 1
    rel = ffrp_frontier_seed_rel(n, m, p, slot)
    failures += ff7rs_expect("registered slot resolves to a path", rel != "")
    if rel.ends_with?(wanted[component])
      wanted_seen = 1
    capacity = ffr_default_capacity(n, m, p) ## i64
    state = i64[ffr_state_size(capacity)]
    rank = ffr_load_scheme_cap(state, root + rel, n, m, p, capacity, 88001 + component * 1009 + launch_number * 17, 4, 4, 1000, 250) ## i64
    failures += ff7rs_expect("scheduled door " + slot.to_s() + " exact-loads", rank > 0 && ffr_verify_best_exact(state, n, m, p) == 1)
    launch_number += 1
  slot = 0
  while slot < count
    expected = 20 / count ## i64
    failures += ff7rs_expect("registered door " + slot.to_s() + " has balanced exposure", seen[slot] == expected)
    slot += 1
  failures += ff7rs_expect("AWS disjoint door is reachable", wanted_seen == 1)
  component += 1

failures += ff7rs_expect("334 first window is an exact cycle", ff7_rect_seed_choice(0, 0, 4) == 0 && ff7_rect_seed_choice(0, 1, 4) == 1 && ff7_rect_seed_choice(0, 2, 4) == 2 && ff7_rect_seed_choice(0, 3, 4) == 3)
failures += ff7rs_expect("344 first window is staggered", ff7_rect_seed_choice(1, 0, 5) == 1 && ff7_rect_seed_choice(1, 1, 5) == 2 && ff7_rect_seed_choice(1, 2, 5) == 3 && ff7_rect_seed_choice(1, 3, 5) == 4 && ff7_rect_seed_choice(1, 4, 5) == 0)

# Guard the integration point: the pure scheduling policy above must actually
# select the state passed to all embedded component launches, not be dead test
# scaffolding beside a hard-coded seed.
fleet_source = read_file(__DIR__ + "/../lib/metaflip/fleet.w")
failures += ff7rs_expect("embedded fleet reads the registered corpus size", fleet_source != nil && fleet_source.include?("ffrp_frontier_seed_count(rn, rm, rp)"))
failures += ff7rs_expect("embedded fleet retains exact registered states", fleet_source != nil && fleet_source.include?("rect_registered_seeds") && fleet_source.include?(".push(registered_state)"))
failures += ff7rs_expect("every embedded launch consults the selector", fleet_source != nil && fleet_source.split("ff7_rect_seed_choice(rect_component").size() == 4)

if failures > 0
  << "7x7 rectangular seed rotation: " + failures.to_s() + " failure(s)"
  exit(1)

<< "PASS 7x7 rectangular seed rotation 334=5/door 344=4/door live-best=slot0 aws-doors=reachable"
