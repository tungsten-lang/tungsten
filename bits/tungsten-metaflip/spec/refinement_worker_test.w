use ../lib/metaflip/fleet/refinement

if ARGV.size() == 4 && ARGV[0] == "--refine-batch"
  exit(ffrf_batch(ARGV[1], ffw_parse_decimal_i64(ARGV[2]), ffw_parse_decimal_i64(ARGV[3])))
if ARGV.size() == 2 && ARGV[0] == "--queue-test"
  root = ARGV[1]
  queue = MetaflipRefinement.new(root, System.executable_path())
  cap = ffw_default_capacity(2) ## i64
  state = i64[ffw_state_size(cap)]
  output = i64[ffw_state_size(cap)]
  seed_root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
  z = ffw_load_scheme_cap(state, seed_root + "matmul_2x2_rank7_strassen_gf2.txt", 2, cap, 17, 8, 3, 1000, 2000) ## i64
  if z != 7 || queue.submit(state, 2, 2, 2) != 1 || queue.submit(state, 2, 2, 2) != 0
    << "FAIL queue admission/dedup"
    exit(1)
  z = ffw_load_scheme_cap(state, seed_root + "matmul_2x2_rank7_d36_gl120_gf2.txt", 2, cap, 19, 8, 3, 1000, 2000)
  if z != 7 || queue.submit(state, 2, 2, 2) != 1
    << "FAIL same-rank representation was discarded"
    exit(1)
  z = ffw_init_naive_cap(state, 2, cap, 21, 8, 3, 1000, 2000)
  rank = ffw_toggle(state, 1, 1, 1, state[6]) ## i64
  rank = ffw_toggle(state, 1, 2, 2, rank)
  rank = ffw_toggle(state, 1, 2, 1, rank)
  rank = ffw_toggle(state, 1, 1, 2, rank)
  rank = ffw_toggle(state, 1, 3, 3, rank)
  state[6] = rank
  z = ffw_copy_current_to_best(state)
  if rank != 9 || queue.submit(state, 2, 2, 2) != 1
    << "FAIL rank nonleader was discarded"
    exit(1)
  # Enqueued tasks own complete immutable snapshots, not this mutated state.
  state[state[47]] = 0
  started = ccall("__w_clock_ms") ## i64
  taken = 0 ## i64
  while queue.pending() > 0 && ccall("__w_clock_ms") - started < 10000
    z = queue.poll(ccall("__w_clock_ms"))
    result = queue.take_into(output, 2, 2, 2, cap, 23, 8, 3, 1000, 2000) ## i64
    if result < 0
      << "FAIL queue result verification"
      exit(1)
    if result > 0
      if ffw_verify_best_exact(output, 2) != 1
        exit(1)
      taken += 1
    ccall("__w_sleep", ~0.001)
  stopped = queue.stop() ## i64
  if stopped != 1 || queue.submitted() != 3 || queue.completed() != 3 || queue.duplicates() != 1 || queue.failures() != 0 || queue.cross_shape() == 0 || taken == 0
    << "FAIL background queue " + queue.status_fields() + " taken=" + taken.to_s()
    exit(1)
  # Restart reads the durable cursor and verifies an existing full-term ticket.
  # Simulate a crash between the final ticket, its counter and dedup marker.
  tail_identity = File.read_prefix(root + "/tasks/3", 66).strip()
  ccall("__w_unlink", root + "/submitted")
  ccall("__w_unlink", root + "/by-id/" + tail_identity)
  resumed = MetaflipRefinement.new(root, System.executable_path())
  z = ffw_load_scheme_cap(state, seed_root + "matmul_2x2_rank7_strassen_gf2.txt", 2, cap, 17, 8, 3, 1000, 2000)
  if resumed.submitted() != 3 || resumed.pending() != 0 || resumed.submit(state, 2, 2, 2) != 0 || resumed.duplicates() != 1 || File.read_prefix(root + "/by-id/" + tail_identity, 32) != "3\n"
    << "FAIL durable resume/dedup"
    exit(1)
  z = resumed.stop()
  << "PASS background queue" + queue.status_fields() + " same_shape=" + taken.to_s()
  exit(0)
if ARGV.size() != 0
  exit(2)

capacity = 8 ## i64
work = i64[24]
work[0] = 2
work[capacity] = 3
work[2*capacity] = 4
work[1] = 1
work[capacity+1] = 9
work[2*capacity+1] = 5
work[2] = 1
work[capacity+2] = 2
work[2*capacity+2] = 6
z = ffrf_sort(work, capacity, 3) ## i64
if work[0] != 1 || work[capacity] != 2 || work[2*capacity] != 6 || work[1] != 1 || work[capacity+1] != 9 || work[2] != 2
  << "FAIL canonical term sort"
  exit(1)
blob = ffrf_blob(work, capacity, 3, 2, 2, 2)
if blob != "MFR1 2 2 2 3\n1 2 6\n1 9 5\n2 3 4\n"
  << "FAIL canonical serialization"
  exit(1)
if ffrf_hash_valid(Crypto:SHA256.hexdigest(blob)) != 1 || ffrf_hash_valid("../invalid") != 0 || ffrf_shape_valid(8, 8, 8) != 0
  << "FAIL identity/shape validation"
  exit(1)
cursor = i64[1]
if ffrf_unsigned("9223372036854775807 ", cursor, 32) != 9223372036854775807 || cursor[0] != 20
  << "FAIL 63-bit unsigned parser boundary"
  exit(1)
cursor[0] = 0
if ffrf_unsigned("9223372036854775808 ", cursor, 32) != 0-1
  << "FAIL unsigned parser overflow rejection"
  exit(1)
<< "PASS refinement worker: canonical complete-term identity, bounded shape, input validation"
