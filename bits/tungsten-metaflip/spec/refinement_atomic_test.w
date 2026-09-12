# Shared cross-shape slots must publish whole payloads even when every
# concurrent campaign uses the same writer role ("intake").
use core/system
use ../lib/metaflip/fleet/refinement_artifacts

-> atomic_expect(label, ok) (String bool) i64
  if !ok
    << "FAIL refinement atomic: " + label
    exit(1)
  1

scratch = capture("mktemp -d /tmp/metaflip-atomic-test-XXXXXX").strip()
z = atomic_expect("scratch", scratch != "")
path = scratch + "/feedback_00.txt"
legacy = path + ".tmp.intake"
z = write_file(legacy, "another writer owns this inode")
z = atomic_expect("publish", ffrf_atomic(path, "first", "intake") == 1)
z = atomic_expect("never reuse another writer temp", read_file(legacy) == "another writer owns this inode")

payloads = ["first"]
lane = 0 ## i64
while lane < 4
  payloads.push(("writer-" + lane.to_s() + "\n") * (2048 + lane * 1024))
  lane += 1
starts = Channel.new(4)
done = Channel.new(4)
threads = []
-> atomic_writer(path, payload, starts, done)
  Thread.new ->
    z = starts.recv()
    writes = 0 ## i64
    ok = 1 ## i64
    while writes < 64
      if ffrf_atomic(path, payload, "intake") != 1
        ok = 0
      writes += 1
    done.send(ok)
    true
lane = 0
while lane < 4
  threads.push(atomic_writer(path, payloads[lane + 1], starts, done))
  starts.send(1)
  lane += 1
finished = 0 ## i64
while finished < 4
  z = atomic_expect("reader only sees complete payloads", payloads.include?(read_file(path)))
  result = done.try_receive()
  if result.received?()
    z = atomic_expect("every writer publishes", result.value() == 1)
    finished += 1
lane = 0
while lane < 4
  joined = ccall("w_thread_join_release", threads[lane])
  lane += 1
z = atomic_expect("final payload complete", payloads.include?(read_file(path)))
z = File.mkdir_p(scratch + "/blocked")
z = atomic_expect("failed rename reported", ffrf_atomic(scratch + "/blocked", "cannot replace directory", "intake") == 0)
z = atomic_expect("no sibling temps leaked", capture("find " + ffls_shell_quote(scratch) + " -type f | wc -l").strip().to_i() == 2)
z = system("rm -rf " + ffls_shell_quote(scratch))
<< "PASS refinement atomic: 256 concurrent publications, unique sibling temps"
