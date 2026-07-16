use ../lib/metaflip/rect/portfolio

# Focused child-status parser regression and microbenchmark.  With an optional
# positive iteration count, the second argument selects legacy, batch, or both.

body = "schema=1 mode=rect producer_state=running sequence=37 tensor=4x5x7 record=99 record_known=1 target=98 best_rank=97 best_bits=2468 wr_gap=-2 wr_status=beats cpu_lanes=12 cpu_moves=123456789 cpu_ms=4567 gpu_requested=1 gpu_supported=1 gpu_ready=1 gpu_lanes=512 gpu_moves=987654321 gpu_ms=3456 gpu_failures=2 exact_rejects=3 elapsed=19 cpu_epoch_steps=1000000 cpu_seed_nonce=41 cpu_door_ticket=9 gpu_degraded=1 gpu_internal_rejects=4 gpu_seed_source=frontier gpu_door_adoptions=5 mitm_supported=1 mitm_ready=1 mitm_attempts=6 mitm_pairs=1176576 mitm_ms=130 mitm_failures=7 side_archive_cap=24 side_archive_loaded=8 side_archive_seeded=9 side_archive_saved=10 side_archive_rejects=11 side_archive_write_failures=12\n"

args = argv()
iterations = 0 ## i64
if args.size() > 0
  iterations = args[0].to_i() ## i64
mode = "both"
if args.size() > 1
  mode = args[1].strip().downcase

keys = ["sequence", "cpu_moves", "gpu_moves", "cpu_ms", "gpu_ms", "mitm_attempts", "mitm_pairs", "mitm_ms", "mitm_failures", "gpu_failures", "gpu_degraded", "exact_rejects", "side_archive_loaded", "side_archive_seeded", "side_archive_saved", "side_archive_rejects", "side_archive_write_failures", "best_rank", "best_bits"]
expected = i64[19]
expected[0] = 37
expected[1] = 123456789
expected[2] = 987654321
expected[3] = 4567
expected[4] = 3456
expected[5] = 6
expected[6] = 1176576
expected[7] = 130
expected[8] = 7
expected[9] = 2
expected[10] = 1
expected[11] = 3
expected[12] = 8
expected[13] = 9
expected[14] = 10
expected[15] = 11
expected[16] = 12
expected[17] = 97
expected[18] = 2468
values = i64[19]
seen = ffrpo_parse_child_status(body, values) ## i64
failures = 0 ## i64
i = 0 ## i64
while i < 19
  legacy = ffrpo_status_i64(body, keys[i], 0 - 999) ## i64
  parsed = ffrpo_parsed_status_i64(values, seen, i, 0 - 999) ## i64
  if legacy != expected[i] || parsed != expected[i]
    << "FAIL child status field=" + keys[i] + " legacy=" + legacy.to_s() + " parsed=" + parsed.to_s() + " expected=" + expected[i].to_s()
    failures += 1
  i += 1

# Match the legacy helper on first-duplicate, malformed, signed, prefix, token
# stripping, missing-field, and embedded-newline behavior.
edge = "\t cpu_moves=bad cpu_moves=44 gpu_moves=-17 gpu_ms=+22 cpu_moves_extra=91 sequence=5 "
edge_seen = ffrpo_parse_child_status(edge, values) ## i64
if ffrpo_parsed_status_i64(values, edge_seen, 1, 701) != ffrpo_status_i64(edge, "cpu_moves", 701)
  << "FAIL first duplicate or malformed value semantics"
  failures += 1
if ffrpo_parsed_status_i64(values, edge_seen, 2, 702) != ffrpo_status_i64(edge, "gpu_moves", 702)
  << "FAIL negative value semantics"
  failures += 1
if ffrpo_parsed_status_i64(values, edge_seen, 4, 703) != ffrpo_status_i64(edge, "gpu_ms", 703)
  << "FAIL positive-sign value semantics"
  failures += 1
if ffrpo_parsed_status_i64(values, edge_seen, 12, 704) != 704
  << "FAIL missing field fallback semantics"
  failures += 1
embedded = "cpu_moves=12junk\nsequence=99"
embedded_seen = ffrpo_parse_child_status(embedded, values) ## i64
if ffrpo_parsed_status_i64(values, embedded_seen, 1, 705) != ffrpo_status_i64(embedded, "cpu_moves", 705)
  << "FAIL suffix to_i semantics"
  failures += 1
if ffrpo_parsed_status_i64(values, embedded_seen, 0, 706) != ffrpo_status_i64(embedded, "sequence", 706)
  << "FAIL literal-space token semantics"
  failures += 1
nil_seen = ffrpo_parse_child_status(nil, values) ## i64
if ffrpo_parsed_status_i64(values, nil_seen, 1, 707) != 707
  << "FAIL nil body fallback semantics"
  failures += 1

if failures != 0
  exit(1)

if iterations > 0 && mode != "batch"
  checksum = 0 ## i64
  started = ccall("__w_clock_ms") ## i64
  i = 0 ## i64
  while i < iterations
    checksum += ffrpo_status_i64(body, "sequence", 0)
    checksum += ffrpo_status_i64(body, "cpu_moves", 0)
    checksum += ffrpo_status_i64(body, "gpu_moves", 0)
    checksum += ffrpo_status_i64(body, "cpu_ms", 0)
    checksum += ffrpo_status_i64(body, "gpu_ms", 0)
    checksum += ffrpo_status_i64(body, "mitm_attempts", 0)
    checksum += ffrpo_status_i64(body, "mitm_pairs", 0)
    checksum += ffrpo_status_i64(body, "mitm_ms", 0)
    checksum += ffrpo_status_i64(body, "mitm_failures", 0)
    checksum += ffrpo_status_i64(body, "gpu_failures", 0)
    checksum += ffrpo_status_i64(body, "gpu_degraded", 0)
    checksum += ffrpo_status_i64(body, "exact_rejects", 0)
    checksum += ffrpo_status_i64(body, "side_archive_loaded", 0)
    checksum += ffrpo_status_i64(body, "side_archive_seeded", 0)
    checksum += ffrpo_status_i64(body, "side_archive_saved", 0)
    checksum += ffrpo_status_i64(body, "side_archive_rejects", 0)
    checksum += ffrpo_status_i64(body, "side_archive_write_failures", 0)
    checksum += ffrpo_status_i64(body, "best_rank", 0)
    checksum += ffrpo_status_i64(body, "best_bits", 0)
    i += 1
  elapsed = ccall("__w_clock_ms") - started ## i64
  << "RECT_STATUS_PARSE_BENCH legacy_ms=" + elapsed.to_s() + " iterations=" + iterations.to_s() + " checksum=" + checksum.to_s()

if iterations > 0 && mode != "legacy"
  checksum = 0 ## i64
  started = ccall("__w_clock_ms") ## i64
  i = 0 ## i64
  while i < iterations
    batch_seen = ffrpo_parse_child_status(body, values) ## i64
    slot = 0 ## i64
    while slot < 19
      checksum += ffrpo_parsed_status_i64(values, batch_seen, slot, 0)
      slot += 1
    i += 1
  elapsed = ccall("__w_clock_ms") - started ## i64
  << "RECT_STATUS_PARSE_BENCH batch_ms=" + elapsed.to_s() + " iterations=" + iterations.to_s() + " checksum=" + checksum.to_s()

<< "PASS rectangular child-status parser"
