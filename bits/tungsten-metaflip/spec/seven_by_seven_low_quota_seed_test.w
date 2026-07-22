use ../lib/metaflip/fleet/seven_by_seven
use ../lib/metaflip/fleet/frontier
use ../lib/metaflip/seeds/catalog

failures = 0 ## i64

-> ff7lq_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL 7x7 low-quota seed: " + label
    return 1
  0

-> ff7lq_contains(paths, wanted) i64
  i = 0 ## i64
  while i < paths.size()
    if paths[i] == wanted
      return 1
    i += 1
  0

runtime_root = __DIR__ + "/../lib/metaflip"
relative = "seeds/gf2/matmul_7x7_rank247_d3542_c013_runpod_cuda_epoch1965_g6417_gf2.txt"
old_relative = "seeds/gf2/matmul_7x7_rank247_d3538_peterson_2026_runpod_cuda_epoch27_novelty_gf2.txt"
capacity = 320 ## i64
state_size = ffw_state_size(capacity) ## i64

configured = ffp_low_quota_seed_paths(7)
failures += ff7lq_expect("exactly one configured experimental novelty door", configured.size() == 1 && configured[0] == relative)
failures += ff7lq_expect("door is not a hot frontier source", ff7lq_contains(ffp_frontier_seed_paths(7), relative) == 0)
explicit = ffp_experimental_seed_paths(7)
failures += ff7lq_expect("replaced sources remain explicit provenance", explicit.size() == 4 && ff7lq_contains(explicit, "seeds/gf2/matmul_7x7_rank247_d3496_fixed_rank_pocket_greedy_closure_gf2.txt") == 1 && ff7lq_contains(explicit, "seeds/gf2/matmul_7x7_rank247_d3492_outer_isotropy_c013_cuda_epoch67_gf2.txt") == 1 && ff7lq_contains(explicit, old_relative) == 1 && ff7lq_contains(explicit, "seeds/gf2/matmul_7x7_rank247_d3096_affine_code_cuda_epoch3306_gf2.txt") == 1)
failures += ff7lq_expect("other tensor sizes have no low-quota artifact", ffp_low_quota_seed_paths(6).size() == 0)

candidate = i64[state_size]
candidate_rank = ffw_load_scheme_cap(candidate, runtime_root + "/" + relative, 7, capacity, 92701, 0, 1, 1, 1) ## i64
failures += ff7lq_expect("Runpod epoch-1965 artifact is exact rank 247/d3542", candidate_rank == 247 && ffw_best_bits(candidate) == 3542 && ffw_verify_best_exact(candidate, 7) == 1)
old_candidate = i64[state_size]
old_rank = ffw_load_scheme_cap(old_candidate, runtime_root + "/" + old_relative, 7, capacity, 92703, 0, 1, 1, 1) ## i64
failures += ff7lq_expect("replaced epoch-27 artifact remains exact provenance", old_rank == 247 && ffw_best_bits(old_candidate) == 3538 && ffw_verify_best_exact(old_candidate, 7) == 1 && ffn_distance(candidate, old_candidate) == 66)

# Reproduce startup archive admission. The ordinary 16-slot max-min archive
# must remain unchanged; the novelty source is appended only after freezing.
frontier = ffp_frontier_seed_paths(7)
archive = []
archive_counters = i64[3]
i = 0 ## i64
while i < frontier.size()
  state = i64[state_size]
  rank = ffw_load_scheme_cap(state, runtime_root + "/" + frontier[i], 7, capacity, 92801 + i * 17, 0, 1, 1, 1) ## i64
  failures += ff7lq_expect("frontier source " + i.to_s() + " exact-loads", rank == 247 && ffw_verify_best_exact(state, 7) == 1)
  if rank == 247
    z = ffn_archive_add(archive, state, 16, 4, archive_counters) ## i64
  i += 1
failures += ff7lq_expect("production archive stays at its existing cap", archive.size() == 16)

nearest = 999999999 ## i64
present = 0 ## i64
i = 0
while i < archive.size()
  distance = ffn_distance(archive[i], candidate) ## i64
  if distance < nearest
    nearest = distance
  if distance == 0
    present = 1
  i += 1
failures += ff7lq_expect("d3542 remains outside the hot archive", present == 0 && nearest == 42)

sources = []
i = 0
while i < archive.size()
  sources.push(archive[i])
  i += 1
leader = archive[0]
added = ff7_append_low_quota_sources(runtime_root, configured, sources, leader, 7, capacity, state_size, 0, 1, 1, 1, 92901) ## i64
failures += ff7lq_expect("one cold source is appended after archive freeze", added == 1 && sources.size() == 17 && ffn_distance(sources[16], candidate) == 0)
again = ff7_append_low_quota_sources(runtime_root, configured, sources, leader, 7, capacity, state_size, 0, 1, 1, 1, 93001) ## i64
failures += ff7lq_expect("repeated append is duplicate-safe", again == 0 && sources.size() == 17)

# The existing finite scheduler is the quota: every source receives 30 of 510
# cold escape tickets, and the experiment gets no CPU island or hot GPU slot.
exposure = i64[sources.size()]
decoded = i64[3]
ticket = 0 ## i64
target = fffeb_schedule_target(sources.size()) ## i64
while ticket < target
  ok = fffeb_schedule_decode(ticket, sources.size(), decoded) ## i64
  if ok == 1
    exposure[decoded[0]] += 1
  ticket += 1
balanced = 1 ## i64
i = 0
while i < exposure.size()
  if exposure[i] != 30
    balanced = 0
  i += 1
failures += ff7lq_expect("cold schedule grants exactly 1/17 source share", target == 510 && exposure[16] == 30 && balanced == 1)
z = fffeb_schedule_decode(16, sources.size(), decoded) ## i64
failures += ff7lq_expect("experiment is reached once in the first 17-minute source rotation", z == 1 && decoded[0] == 16 && decoded[1] == 1 && decoded[2] == 0)

fleet_source = read_file(runtime_root + "/fleet.w")
failures += ff7lq_expect("all frozen-generation rebuilds append the cold inventory", fleet_source != nil && fleet_source.split("ff7_append_low_quota_sources(").size() == 4)

if failures > 0
  exit(1)
<< "PASS 7x7 low-quota seed rank=247 density=3542 archive=16 cold=1 share=1/17 old-gap=66 hot-gap=42 exact=1"
