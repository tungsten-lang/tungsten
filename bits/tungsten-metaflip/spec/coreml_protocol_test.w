# Focused coordinator state machine test, linked without the fleet entrypoint.
use ../lib/metaflip/fleet/coreml

# The class consumes these fleet-owned IO seams; no worker pool is needed here.
-> ffn_atomic_write(path, body, tag) (String String String) i64
  temporary = path + ".tmp." + tag
  if write_file(temporary, body)
    if ccall("__w_rename", temporary, path)
      return 1
  0

-> ffn_thread_join_bounded(thread, timeout_ms) i64
  joined = thread.join(1000)
  if joined == false
    z = thread.kill
  z = ccall("w_thread_join_release", thread)
  if joined == true
    return 1
  0

-> ffcm_test_expect(label, condition)
  if !condition
    << "FAIL " + label
    exit(1)
  1

-> ffcm_test_wait_file(path, limit_ms)
  started = clock_ms()
  while clock_ms() - started < limit_ms
    value = read_file(path)
    if value != nil && value != ""
      return value
    z = ccall("__w_sleep_ms", 5)
  ""

args = argv()
if args.size() != 3
  << "coreml_protocol_test DIRECTORY MOCK_HELPER MODE"
  exit(2)
directory = args[0]
helper = args[1]
mode = args[2]

valid_scores = ["0", "1.25", "-4", "+3", ".5", "5.", "1e-4", "-2E+3"]
invalid_scores = ["", ".", "+", "NaN", "nan", "Inf", "1junk", "1 2", " 1", "1e", "1e+", "1.2.3"]
i = 0
while i < valid_scores.size()
  z = ffcm_test_expect("valid score grammar " + valid_scores[i], ffcm_numeric_score(valid_scores[i]) == 1)
  i += 1
i = 0
while i < invalid_scores.size()
  z = ffcm_test_expect("invalid score grammar " + invalid_scores[i], ffcm_numeric_score(invalid_scores[i]) == 0)
  i += 1

# Exact 2x2 naive states are sufficient for the generic advisory state machine.
# The actual 5x5 restriction belongs to the separate CLI integration test.
a = i64[ffw_state_size(32)]
b = i64[ffw_state_size(32)]
z = ffw_init_naive_cap(a, 2, 32, 100, 0, 100, 100, 100) ## i64
z = ffw_init_naive_cap(b, 2, 32, 200, 0, 100, 100, 100)
# Give B a distinguishable but still exact term ordering. Reseeding changes
# RNG metadata, so identify the recommendation by its certificate content.
axis = 0
while axis < 3
  offset = b[47 + axis]
  temporary = b[offset]
  b[offset] = b[offset + 1]
  b[offset + 1] = temporary
  axis += 1
if mode == "corrupt"
  b[b[47]] = b[b[47]] ^ 4
near = [a, b]
empty = []
coordinator = MetaflipCoreML.new(mode, helper, 1, "cpuOnly", directory, "protocol")
z = coordinator.poll(near, empty, 7, 0)
if mode == "snapshot"
  # Mutable bank storage may be recycled as soon as submission returns.
  b[b[47]] = 0

if mode == "crash"
  marker = ffcm_test_wait_file(directory + "/mock.done", 1000)
  ccall("__w_sleep_ms", 50)
  z = coordinator.poll(near, empty, 7, 100)
  z = ffcm_test_expect("helper crash fails closed", coordinator.failures == 1 && coordinator.batches == 0)
elsif mode == "timeout"
  ccall("__w_sleep_ms", 50)
  z = coordinator.poll(near, empty, 7, 31100)
  z = ffcm_test_expect("bounded response timeout", coordinator.failures == 1 && coordinator.batches == 0)
else
  response = ffcm_test_wait_file(directory + "/coreml-response.tsv", 1000)
  z = ffcm_test_expect("mock response arrived", response != "")
  z = coordinator.poll(near, empty, 7, 100)
  if mode == "stale" || mode == "future"
    z = ffcm_test_expect("wrong epoch is not admitted", coordinator.batches == 0 && coordinator.failures == 0)
    request = read_file(directory + "/coreml-request.tsv")
    header = request.split("\n")[0]
    z = ffn_atomic_write(directory + "/coreml-response.tsv", header + "\n0\t0.25\n1\t1.25\n", "corrected")
    z = coordinator.poll(near, empty, 7, 200)
  if mode == "valid" || mode == "stale" || mode == "future" || mode == "corrupt" || mode == "snapshot"
    z = ffcm_test_expect("valid epoch admitted exactly once", coordinator.batches == 1 && coordinator.failures == 0)
    z = coordinator.poll(near, empty, 7, 300)
    z = ffcm_test_expect("duplicate response is not replayed", coordinator.batches == 1)
    if mode == "snapshot"
      # A second submission reuses pending storage while the first ready batch
      # is still eligible. It must not overwrite the ready snapshot pool.
      z = coordinator.poll(near, empty, 7, 2100)
    i = 0
    while i < 3
      choice = coordinator.take(1, 7)
      z = ffcm_test_expect("three exploration leases remain unguided", choice == nil)
      i += 1
    choice = coordinator.take(1, 7)
    if mode == "corrupt"
      z = ffcm_test_expect("model cannot bypass exact gate", choice == nil && coordinator.failures == 1 && coordinator.uses == 0)
    else
      z = ffcm_test_expect("fourth lease chooses highest score snapshot", choice != nil && ffw_read_best_u(choice, 0) == 2 && coordinator.uses == 1)
    z = coordinator.invalidate()
    i = 0
    while i < 4
      z = ffcm_test_expect("invalidation drops ready choices", coordinator.take(1, 7) == nil)
      i += 1
  else
    z = ffcm_test_expect("bad score rejected", coordinator.batches == 0 && coordinator.failures == 1)
    i = 0
    while i < 4
      z = ffcm_test_expect("bad score cannot seed a lane", coordinator.take(1, 7) == nil)
      i += 1

z = coordinator.stop()
z = ffcm_test_expect("helper joined after stop", z == 1)
z = ffcm_test_expect("stop marker written", read_file(directory + "/coreml-request.tsv.stop") == "stop\n")
<< "PASS CoreML protocol " + mode
