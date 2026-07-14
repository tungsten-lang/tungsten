# Build-and-dispatch integration test for FlipFleet's cached generic worker.
# It uses only 16 lanes and one move, so it is safe beside a live campaign.

use flipfleet_gpu_bundle

av = argv()
root = "."
if av.size() > 0
  root = av[0]
binary = "/tmp/flipfleet_metallib_cache_test_worker"
seed = root + "/benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt"
output = "/tmp/flipfleet_metallib_cache_test_best.txt"
command_path = "/tmp/flipfleet_metallib_cache_test_commands.txt"
ack_path = "/tmp/flipfleet_metallib_cache_test_acks.txt"

if ffb_build(root, 3, binary) != 1
  << "FAIL cached worker build"
  exit(1)
if ffb_metallib_fresh(root, 3, binary) != 1
  << "FAIL cached library freshness"
  exit(1)
if write_file(output, "") == false
  << "FAIL cached worker output"
  exit(1)
if ffpg_prepare_mailboxes(command_path, ack_path, "integration") != 1
  << "FAIL persistent mailbox preparation"
  exit(1)

epoch = ffb_epoch_command(root, binary, 3, seed, output, "", 0, 1, 1, 1, 1, 1, 1, 16, "", 1, 1)
command = ffpg_launch_command(epoch, command_path, ack_path)
worker = Thread.new ->
  system(command)

if ffpg_wait_ack(ack_path, 0, "ready", 5000) != 1
  << "FAIL persistent worker ready"
  exit(1)
persistent_started = ccall("__w_clock_ms") ## i64
generation = 1 ## i64
while generation <= 8
  if ffpg_publish(command_path, ffpg_command(generation, 1, 1, 1, 1, 1, 1, 1, 1), "run" + generation.to_s()) != 1
    << "FAIL persistent command " + generation.to_s()
    exit(1)
  if ffpg_wait_ack(ack_path, generation, "done", 5000) != 1
    << "FAIL persistent epoch " + generation.to_s()
    exit(1)
  generation += 1
persistent_elapsed = ccall("__w_clock_ms") - persistent_started ## i64
if read_file(output) != ""
  << "FAIL persistent command retained a stale candidate"
  exit(1)
if ffpg_publish(command_path, ffpg_command(9, 0, 1, 1, 1, 1, 1, 1, 1), "stop") != 1
  << "FAIL persistent stop command"
  exit(1)
if ffpg_wait_ack(ack_path, 9, "stopped", 5000) != 1
  << "FAIL persistent stop ack"
  exit(1)
worker_ok = worker.join
if worker_ok == false
  << "FAIL persistent process status"
  exit(1)
<< "PASS flipfleet cached persistent worker integration (8 epochs " + persistent_elapsed.to_s() + "ms, avg " + (persistent_elapsed / 8).to_s() + "ms)"
