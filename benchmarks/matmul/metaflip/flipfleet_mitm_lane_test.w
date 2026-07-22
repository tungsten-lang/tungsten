use flipfleet_mitm_lane_lib

failures = 0 ## i64

-> ffmt_check(label, condition) i64
  if condition == false || condition == 0
    << "FAIL " + label
    return 1
  0

n = 3 ## i64
while n <= 7
  failures += ffmt_check("plan dimension " + n.to_s(), ffm_plan_valid(n, 4, 180, 2, 0))
  n += 1
failures += ffmt_check("reject dimension", ffm_plan_valid(8, 4, 180, 2, 0) == 0)
failures += ffmt_check("reject unbounded subsets", ffm_plan_valid(5, 17, 180, 2, 0) == 0)
failures += ffmt_check("reject unbounded pool", ffm_plan_valid(5, 4, 701, 2, 0) == 0)
failures += ffmt_check("logical work", ffm_plan_threads(4, 180) == 129600)
build_command = ffm_build_command("/repo path", "/tmp/mitm worker")
failures += ffmt_check("native build command", build_command.include?("flipfleet_mitm_lane.w") && !build_command.include?("python"))
epoch_command = ffm_epoch_command("/repo path", "/tmp/mitm worker", "/tmp/seed file", "/tmp/out file", 6, 4, 180, 2, 12)
failures += ffmt_check("native epoch command", epoch_command.include?("'/tmp/seed file'") && epoch_command.include?(" 6 4 180 2 12") && !epoch_command.include?("python"))
failures += ffmt_check("native cached library", epoch_command.ends_with?(" '/tmp/mitm worker.metallib'"))

# Cross-language reference vector from xor_fingerprint(expand((3,5,9),9,9,9)).
words = i64[4]
z = ffm_fingerprint(3, 5, 9, 9, words) ## i64
failures += ffmt_check("fingerprint word 0", words[0] == 2359305)
failures += ffmt_check("fingerprint word 1", words[1] == 0)
failures += ffmt_check("fingerprint word 2", words[2] == 1179648)
failures += ffmt_check("fingerprint word 3", words[3] == 72)

# A 7x7 reference vector exercises positions far beyond the first 128-bit
# chunk and guards the rotation/folding arithmetic at the i64 factor limit.
z = ffm_fingerprint(281474976710659, 1099511627781, 4294967305, 49, words)
failures += ffmt_check("fingerprint 7x7 word 0", words[0] == 1029)
failures += ffmt_check("fingerprint 7x7 word 1", words[1] == 473)
failures += ffmt_check("fingerprint 7x7 word 2", words[2] == 1207959576)
failures += ffmt_check("fingerprint 7x7 word 3", words[3] == 2281729132)

seed = "benchmarks/matmul/metaflip/mitm_planted_3x3_rank28_gf2.txt"
state = ffm_load_exact(seed, 3)
failures += ffmt_check("planted seed exact", state != nil)
if state != nil
  cap = ffw_default_capacity(3) ## i64
  us = i64[cap]
  vs = i64[cap]
  ws = i64[cap]
  rank = ffw_export_best(state, us, vs, ws) ## i64
  selected = i64[5]
  selected[0] = 0
  selected[1] = 1
  selected[2] = 2
  selected[3] = 3
  selected[4] = 4
  cu = i64[64]
  cv = i64[64]
  cw = i64[64]
  count = ffm_candidates(us, vs, ws, rank, selected, 64, 2, cu, cv, cw) ## i64
  failures += ffmt_check("bounded candidates", count >= 4 && count <= 64)
  replacement = i64[4]
  wanted_u = i64[4]
  wanted_v = i64[4]
  wanted_w = i64[4]
  wanted_u[0] = 256
  wanted_v[0] = 256
  wanted_w[0] = 256
  wanted_u[1] = 1
  wanted_v[1] = 1
  wanted_w[1] = 1
  wanted_u[2] = 1
  wanted_v[2] = 2
  wanted_w[2] = 2
  wanted_u[3] = 1
  wanted_v[3] = 4
  wanted_w[3] = 4
  found = 0 ## i64
  want = 0 ## i64
  while want < 4
    i = 0 ## i64
    while i < count
      if cu[i] == wanted_u[want] && cv[i] == wanted_v[want] && cw[i] == wanted_w[want]
        replacement[want] = i
        found += 1
        i = count
      else
        i += 1
    want += 1
  failures += ffmt_check("replacement family", found == 4)
  if found == 4
    failures += ffmt_check("local exact gate", ffm_local_exact(us, vs, ws, selected, cu, cv, cw, replacement, 3))
    saved = replacement[0] ## i64
    replacement[0] = replacement[1]
    failures += ffmt_check("local collision rejection", ffm_local_exact(us, vs, ws, selected, cu, cv, cw, replacement, 3) == 0)
    replacement[0] = saved
    output = "/tmp/flipfleet_mitm_lane_test_hit.txt"
    output_rank = ffm_accept_and_dump(us, vs, ws, rank, selected, cu, cv, cw, replacement, 3, output) ## i64
    failures += ffmt_check("full exact reconstruction", output_rank == 27)
    reloaded = ffm_load_exact(output, 3)
    failures += ffmt_check("written scheme exact", reloaded != nil && ffw_best_rank(reloaded) == 27)
  failures += ffmt_check("refuse seed overwrite", ffm_search(seed, seed, 3, 1, 4, 0, 0, "unused.metal") == 0 - 3)

if failures > 0
  << "flipfleet_mitm_lane_test: " + failures.to_s() + " failure(s)"
  exit(1)
<< "flipfleet_mitm_lane_test: all native checks passed"
