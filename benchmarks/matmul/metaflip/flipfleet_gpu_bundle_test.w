use flipfleet_gpu_bundle

failures = 0 ## i64

-> expect(label, condition) i64
  if condition == false || condition == 0
    << "FAIL " + label
    return 1
  0

n = 3 ## i64
while n <= 7
  failures += expect("supported " + n.to_s(), ffb_supported(n))
  failures += expect("geometry " + n.to_s(), ffb_geometry_valid(n))
  failures += expect("naive capacity " + n.to_s(), ffb_cap(n) >= n * n * n + 32)
  failures += expect("32-lane divisibility " + n.to_s(), (32 % ffb_wpg(n)) == 0)
  failures += expect("shared ceiling " + n.to_s(), ffb_shared_bytes(n) <= 32768)
  source = read_file(ffb_source_rel(n))
  metal = read_file(ffb_metal_rel(n))
  failures += expect("source asset " + n.to_s(), source != nil)
  failures += expect("metal asset " + n.to_s(), metal != nil)
  if source != nil
    failures += expect("exact gate " + n.to_s(), source.include?("while ai < ab"))
    failures += expect("bounded epochs " + n.to_s(), source.include?("ROUNDS = av0\[16].to_i()"))
    failures += expect("cached library " + n.to_s(), source.include?("metal_load_library(device, metallibpath)"))
    failures += expect("persistent mailbox " + n.to_s(), source.include?("persistent_command_path") && source.include?("persistent_generation.to_s() + \" done \""))
    failures += expect("persistent crash lease " + n.to_s(), source.include?("persistent_idle_timeout_ms = " + ffpg_worker_idle_timeout_ms().to_s()) && source.include?("persistent_generation.to_s() + \" expired \""))
    failures += expect("replayable internal reject " + n.to_s(), source.include?("verify_buf_error") && source.include?("internal_reject_candidate_path") && source.include?("internal_reject_seed_path") && source.include?("internal_reject_meta_path"))
  if metal != nil
    failures += expect("metal kernel " + n.to_s(), metal.include?("kernel void flipwalk"))
  n += 1

failures += expect("3x3 i32", ffb_mask_bytes(3) == 4)
failures += expect("5x5 i32", ffb_mask_bytes(5) == 4)
failures += expect("6x6 i64", ffb_mask_bytes(6) == 8)
failures += expect("7x7 i64", ffb_mask_bytes(7) == 8)
failures += expect("6x6 lane rounding", ffb_round_lanes(6, 35) == 32)
failures += expect("7x7 lane rounding", ffb_round_lanes(7, 33) == 32)

build = ffb_build_command("/repo path", 7, "/tmp/run/gpu")
failures += expect("native build source", build.include?("cal2zone_777.w"))
failures += expect("quoted root", build.include?("'/repo path'"))
failures += expect("compiler Metal output override", build.include?("TUNGSTEN_METAL_PATH='/tmp/run/gpu.metal'"))
cache_build = ffmc_build_command("/repo path", "/repo path/kernel.metal", "/tmp/run/gpu")
failures += expect("cache resolves downloaded toolchain", cache_build.include?("xcrun --find metal") && !cache_build.include?("-sdk macosx"))
failures += expect("cache publishes atomically", cache_build.include?("/tmp/run/gpu.metallib.tmp.") && cache_build.include?("mv "))
failures += expect("cache uses collision-free temporaries", cache_build.include?("AIR_TMP=") && cache_build.include?("$$"))

epoch = ffb_epoch_command("/repo", "/tmp/gpu", 6, "/tmp/seed", "/tmp/best", "", 152, 100, 20, 8, 80000, 25000, 4, 35, "", 256, 3)
failures += expect("epoch dimension", epoch.include?(" 6 6 6 "))
failures += expect("epoch rounded lanes", epoch.include?(" 32 '' 32 3"))
failures += expect("epoch cached metallib", epoch.ends_with?(" '/tmp/gpu.metallib'"))
persistent = ffpg_launch_command(epoch, "/tmp/commands", "/tmp/acks")
failures += expect("persistent mailbox args", persistent.ends_with?(" '/tmp/commands' '/tmp/acks'"))
failures += expect("persistent mailbox reset", ffpg_prepare_mailboxes("/tmp/ffb-test-command", "/tmp/ffb-test-ack", "test") == 1)
run_command = ffpg_command(7, 1, 20000, 100, 4, 120000, 40000, 6, 32)
failures += expect("persistent command schema", run_command == "7 1 20000 100 4 120000 40000 6 32\n")
failures += expect("persistent crash lease boundary", ffpg_worker_idle_expired(100, 100 + ffpg_worker_idle_timeout_ms() - 1) == 0 && ffpg_worker_idle_expired(100, 100 + ffpg_worker_idle_timeout_ms()) == 1)

if failures > 0
  << "flipfleet_gpu_bundle_test: " + failures.to_s() + " failure(s)"
  exit(1)
if failures == 0
  << "flipfleet_gpu_bundle_test: all checks passed"
