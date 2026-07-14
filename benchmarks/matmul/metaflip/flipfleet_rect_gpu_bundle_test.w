use flipfleet_rect_gpu_bundle

-> ffrgb_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

z = ffrgb_expect("supported 334", ffrgb_supported(3, 3, 4) == 1)
z = ffrgb_expect("supported 335", ffrgb_supported(3, 3, 5) == 1)
z = ffrgb_expect("supported 344", ffrgb_supported(3, 4, 4) == 1)
z = ffrgb_expect("supported 345", ffrgb_supported(3, 4, 5) == 1)
z = ffrgb_expect("supported 355", ffrgb_supported(3, 5, 5) == 1)
z = ffrgb_expect("supported 445", ffrgb_supported(4, 4, 5) == 1)
z = ffrgb_expect("CPU-only 455", ffrgb_supported(4, 5, 5) == 0 && ffrp_supported(4, 5, 5) == 1)
z = ffrgb_expect("CPU-only 446", ffrgb_supported(4, 4, 6) == 0 && ffrp_supported(4, 4, 6) == 1)
z = ffrgb_expect("CPU-only 457", ffrgb_supported(4, 5, 7) == 0 && ffrp_supported(4, 5, 7) == 1)
z = ffrgb_expect("reject square", ffrgb_supported(3, 3, 3) == 0)
z = ffrgb_expect("334 geometry", ffrgb_cap(3, 3, 4) == 68 && ffrgb_shared_bytes(3, 3, 4) == 13056 && ffrgb_geometry_valid(3, 3, 4) == 1)
z = ffrgb_expect("335 geometry", ffrgb_cap(3, 3, 5) == 77 && ffrgb_shared_bytes(3, 3, 5) == 14784 && ffrgb_geometry_valid(3, 3, 5) == 1)
z = ffrgb_expect("344 geometry", ffrgb_cap(3, 4, 4) == 80 && ffrgb_shared_bytes(3, 4, 4) == 15360 && ffrgb_geometry_valid(3, 4, 4) == 1)
z = ffrgb_expect("345 geometry", ffrgb_cap(3, 4, 5) == 92 && ffrgb_shared_bytes(3, 4, 5) == 17664 && ffrgb_geometry_valid(3, 4, 5) == 1)
z = ffrgb_expect("355 geometry", ffrgb_cap(3, 5, 5) == 107 && ffrgb_shared_bytes(3, 5, 5) == 20544 && ffrgb_geometry_valid(3, 5, 5) == 1)
z = ffrgb_expect("445 geometry", ffrgb_cap(4, 4, 5) == 112 && ffrgb_shared_bytes(4, 4, 5) == 21504 && ffrgb_geometry_valid(4, 4, 5) == 1)
z = ffrgb_expect("lane rounding", ffrgb_round_lanes(3, 3, 4, 271) == 256 && ffrgb_round_lanes(3, 3, 4, 15) == 0)
z = ffrgb_expect("source path", ffrgb_source_path("/repo", 3, 3, 4) == "/repo/benchmarks/matmul/metaflip/rect_gpu/cal2zone_334.w")
z = ffrgb_expect("345 source path", ffrgb_source_path("/repo", 3, 4, 5) == "/repo/benchmarks/matmul/metaflip/rect_gpu/cal2zone_345.w")
z = ffrgb_expect("metal path", ffrgb_metal_path("", 3, 4, 4) == "benchmarks/matmul/metaflip/rect_gpu/cal2zone_344.metal")
build = ffrgb_build_command("/repo", 3, 3, 4, "/tmp/rect")
z = ffrgb_expect("build selects 334", build.include?("cal2zone_334.w") && build.include?("/tmp/rect"))
build445 = ffrgb_build_command("/repo", 4, 4, 5, "/tmp/rect445")
z = ffrgb_expect("build selects 445", build445.include?("cal2zone_445.w") && build445.include?("/tmp/rect445"))
build345 = ffrgb_build_command("/repo", 3, 4, 5, "/tmp/rect345")
z = ffrgb_expect("build selects 345", build345.include?("cal2zone_345.w") && build345.include?("/tmp/rect345"))
cmd = ffrgb_epoch_command("/repo", "/tmp/rect", 3, 4, 4, "seed file", "best file", "", 37, 1000, 8, 4, 500, 100, 7, 271, "", 999, 2)
z = ffrgb_expect("epoch dims", cmd.include?(" 3 4 4 "))
z = ffrgb_expect("epoch rounds lanes", cmd.include?(" 256 ") && cmd.include?(" 256 2 "))
z = ffrgb_expect("epoch cached metallib", cmd.ends_with?(" '/tmp/rect.metallib'"))
z = ffrgb_expect("persistent mailbox", ffpg_launch_command(cmd, "/tmp/cmd", "/tmp/ack").ends_with?(" '/tmp/cmd' '/tmp/ack'"))
z = ffrgb_expect("epoch quotes paths", cmd.include?("'seed file'") && cmd.include?("'best file'"))
z = ffrgb_expect("reject short geometry", ffrgb_epoch_command("/repo", "/tmp/rect", 3, 3, 4, "s", "b", "", 28, 1, 1, 1, 1, 1, 1, 15, "", 1, 1) == "")

<< "PASS flipfleet rectangular GPU bundle"
