use flipfleet_rect_gpu_bundle

-> ffrgb_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

z = ffrgb_expect("supported 225", ffrgb_supported(2, 2, 5) == 1)
z = ffrgb_expect("supported 234", ffrgb_supported(2, 3, 4) == 1)
z = ffrgb_expect("supported 235", ffrgb_supported(2, 3, 5) == 1)
z = ffrgb_expect("supported 245", ffrgb_supported(2, 4, 5) == 1)
z = ffrgb_expect("supported 256", ffrgb_supported(2, 5, 6) == 1)
z = ffrgb_expect("supported 334", ffrgb_supported(3, 3, 4) == 1)
z = ffrgb_expect("supported 335", ffrgb_supported(3, 3, 5) == 1)
z = ffrgb_expect("supported 344", ffrgb_supported(3, 4, 4) == 1)
z = ffrgb_expect("supported 345", ffrgb_supported(3, 4, 5) == 1)
z = ffrgb_expect("supported 355", ffrgb_supported(3, 5, 5) == 1)
z = ffrgb_expect("supported 445", ffrgb_supported(4, 4, 5) == 1)
z = ffrgb_expect("CPU-only 455", ffrgb_supported(4, 5, 5) == 0 && ffrp_supported(4, 5, 5) == 1)
z = ffrgb_expect("CPU-only 446", ffrgb_supported(4, 4, 6) == 0 && ffrp_supported(4, 4, 6) == 1)
z = ffrgb_expect("CPU-only 457", ffrgb_supported(4, 5, 7) == 0 && ffrp_supported(4, 5, 7) == 1)
z = ffrgb_expect("CPU-only next sensitivity tranche", ffrgb_supported(3, 4, 7) == 0 && ffrp_supported(3, 4, 7) == 1 && ffrgb_supported(3, 5, 6) == 0 && ffrp_supported(3, 5, 6) == 1 && ffrgb_supported(3, 5, 7) == 0 && ffrp_supported(3, 5, 7) == 1 && ffrgb_supported(4, 5, 8) == 0 && ffrp_supported(4, 5, 8) == 1 && ffrgb_supported(4, 6, 6) == 0 && ffrp_supported(4, 6, 6) == 1 && ffrgb_supported(4, 6, 8) == 0 && ffrp_supported(4, 6, 8) == 1)
z = ffrgb_expect("reject square", ffrgb_supported(3, 3, 3) == 0)
z = ffrgb_expect("225 geometry", ffrgb_cap(2, 2, 5) == 64 && ffrgb_shared_bytes(2, 2, 5) == 12288 && ffrgb_geometry_valid(2, 2, 5) == 1)
z = ffrgb_expect("234 geometry", ffrgb_cap(2, 3, 4) == 64 && ffrgb_shared_bytes(2, 3, 4) == 12288 && ffrgb_geometry_valid(2, 3, 4) == 1)
z = ffrgb_expect("235 geometry", ffrgb_cap(2, 3, 5) == 68 && ffrgb_seedcap(2, 3, 5) == 68 && ffrgb_wpg(2, 3, 5) == 16 && ffrgb_shared_bytes(2, 3, 5) == 13056 && ffrgb_geometry_valid(2, 3, 5) == 1)
z = ffrgb_expect("245 geometry", ffrgb_cap(2, 4, 5) == 80 && ffrgb_shared_bytes(2, 4, 5) == 15360 && ffrgb_geometry_valid(2, 4, 5) == 1)
z = ffrgb_expect("256 geometry", ffrgb_cap(2, 5, 6) == 92 && ffrgb_seedcap(2, 5, 6) == 92 && ffrgb_wpg(2, 5, 6) == 16 && ffrgb_shared_bytes(2, 5, 6) == 17664 && ffrgb_geometry_valid(2, 5, 6) == 1)
z = ffrgb_expect("334 geometry", ffrgb_cap(3, 3, 4) == 68 && ffrgb_shared_bytes(3, 3, 4) == 13056 && ffrgb_geometry_valid(3, 3, 4) == 1)
z = ffrgb_expect("335 geometry", ffrgb_cap(3, 3, 5) == 77 && ffrgb_shared_bytes(3, 3, 5) == 14784 && ffrgb_geometry_valid(3, 3, 5) == 1)
z = ffrgb_expect("344 geometry", ffrgb_cap(3, 4, 4) == 80 && ffrgb_shared_bytes(3, 4, 4) == 15360 && ffrgb_geometry_valid(3, 4, 4) == 1)
z = ffrgb_expect("345 geometry", ffrgb_cap(3, 4, 5) == 92 && ffrgb_shared_bytes(3, 4, 5) == 17664 && ffrgb_geometry_valid(3, 4, 5) == 1)
z = ffrgb_expect("355 geometry", ffrgb_cap(3, 5, 5) == 107 && ffrgb_shared_bytes(3, 5, 5) == 20544 && ffrgb_geometry_valid(3, 5, 5) == 1)
z = ffrgb_expect("445 geometry", ffrgb_cap(4, 4, 5) == 112 && ffrgb_shared_bytes(4, 4, 5) == 21504 && ffrgb_geometry_valid(4, 4, 5) == 1)
z = ffrgb_expect("lane rounding", ffrgb_round_lanes(3, 3, 4, 271) == 256 && ffrgb_round_lanes(3, 3, 4, 15) == 0)
z = ffrgb_expect("235 lane rounding", ffrgb_round_lanes(2, 3, 5, 271) == 256 && ffrgb_round_lanes(2, 3, 5, 15) == 0)
z = ffrgb_expect("256 lane rounding", ffrgb_round_lanes(2, 5, 6, 271) == 256 && ffrgb_round_lanes(2, 5, 6, 15) == 0)
z = ffrgb_expect("source path", ffrgb_source_path("/repo", 3, 3, 4) == "/repo/benchmarks/matmul/metaflip/rect_gpu/cal2zone_334.w")
z = ffrgb_expect("225 source path", ffrgb_source_path("/repo", 2, 2, 5) == "/repo/benchmarks/matmul/metaflip/rect_gpu/cal2zone_225.w")
z = ffrgb_expect("234 source path", ffrgb_source_path("/repo", 2, 3, 4) == "/repo/benchmarks/matmul/metaflip/rect_gpu/cal2zone_234.w")
z = ffrgb_expect("235 source and metal paths", ffrgb_source_path("/repo", 2, 3, 5) == "/repo/benchmarks/matmul/metaflip/rect_gpu/cal2zone_235.w" && ffrgb_metal_path("", 2, 3, 5) == "benchmarks/matmul/metaflip/rect_gpu/cal2zone_235.metal")
z = ffrgb_expect("245 metal path", ffrgb_metal_path("", 2, 4, 5) == "benchmarks/matmul/metaflip/rect_gpu/cal2zone_245.metal")
z = ffrgb_expect("256 source and metal paths", ffrgb_source_path("/repo", 2, 5, 6) == "/repo/benchmarks/matmul/metaflip/rect_gpu/cal2zone_256.w" && ffrgb_metal_path("", 2, 5, 6) == "benchmarks/matmul/metaflip/rect_gpu/cal2zone_256.metal")
z = ffrgb_expect("345 source path", ffrgb_source_path("/repo", 3, 4, 5) == "/repo/benchmarks/matmul/metaflip/rect_gpu/cal2zone_345.w")
z = ffrgb_expect("metal path", ffrgb_metal_path("", 3, 4, 4) == "benchmarks/matmul/metaflip/rect_gpu/cal2zone_344.metal")
build = ffrgb_build_command("/repo", 3, 3, 4, "/tmp/rect")
z = ffrgb_expect("build selects 334", build.include?("cal2zone_334.w") && build.include?("/tmp/rect"))
build225 = ffrgb_build_command("/repo", 2, 2, 5, "/tmp/rect225")
z = ffrgb_expect("build selects 225", build225.include?("cal2zone_225.w") && build225.include?("/tmp/rect225"))
build445 = ffrgb_build_command("/repo", 4, 4, 5, "/tmp/rect445")
z = ffrgb_expect("build selects 445", build445.include?("cal2zone_445.w") && build445.include?("/tmp/rect445"))
build345 = ffrgb_build_command("/repo", 3, 4, 5, "/tmp/rect345")
z = ffrgb_expect("build selects 345", build345.include?("cal2zone_345.w") && build345.include?("/tmp/rect345"))
build234 = ffrgb_build_command("/repo", 2, 3, 4, "/tmp/rect234")
z = ffrgb_expect("build selects 234", build234.include?("cal2zone_234.w") && build234.include?("/tmp/rect234"))
build235 = ffrgb_build_command("/repo", 2, 3, 5, "/tmp/rect235")
z = ffrgb_expect("build selects 235", build235.include?("cal2zone_235.w") && build235.include?("/tmp/rect235"))
build245 = ffrgb_build_command("/repo", 2, 4, 5, "/tmp/rect245")
z = ffrgb_expect("build selects 245", build245.include?("cal2zone_245.w") && build245.include?("/tmp/rect245"))
build256 = ffrgb_build_command("/repo", 2, 5, 6, "/tmp/rect256")
z = ffrgb_expect("build selects 256", build256.include?("cal2zone_256.w") && build256.include?("/tmp/rect256"))
cmd = ffrgb_epoch_command("/repo", "/tmp/rect", 3, 4, 4, "seed file", "best file", "", 37, 1000, 8, 4, 500, 100, 7, 271, "", 999, 2)
z = ffrgb_expect("epoch dims", cmd.include?(" 3 4 4 "))
z = ffrgb_expect("epoch rounds lanes", cmd.include?(" 256 ") && cmd.include?(" 256 2 "))
z = ffrgb_expect("epoch cached metallib", cmd.ends_with?(" '/tmp/rect.metallib'"))
z = ffrgb_expect("persistent mailbox", ffpg_launch_command(cmd, "/tmp/cmd", "/tmp/ack").ends_with?(" '/tmp/cmd' '/tmp/ack'"))
cmd235 = ffrgb_epoch_command("/repo", "/tmp/rect235", 2, 3, 5, "seed", "best", "", 24, 20000, 200, 4, 50000, 20000, 7, 271, "", 999, 1)
z = ffrgb_expect("235 epoch policy", cmd235.include?(" 2 3 5 ") && cmd235.include?(" 256 ") && cmd235.include?(" 256 1 ") && cmd235.ends_with?(" '/tmp/rect235.metallib'"))
cmd256 = ffrgb_epoch_command("/repo", "/tmp/rect256", 2, 5, 6, "seed", "best", "", 46, 20000, 200, 4, 50000, 20000, 7, 271, "", 999, 1)
z = ffrgb_expect("256 epoch policy", cmd256.include?(" 2 5 6 ") && cmd256.include?(" 256 ") && cmd256.include?(" 256 1 ") && cmd256.ends_with?(" '/tmp/rect256.metallib'"))
rect_lease_dims = i64[33]
rect_lease_dims[0] = 2
rect_lease_dims[1] = 3
rect_lease_dims[2] = 4
rect_lease_dims[3] = 2
rect_lease_dims[4] = 4
rect_lease_dims[5] = 5
rect_lease_dims[6] = 3
rect_lease_dims[7] = 3
rect_lease_dims[8] = 4
rect_lease_dims[9] = 3
rect_lease_dims[10] = 3
rect_lease_dims[11] = 5
rect_lease_dims[12] = 3
rect_lease_dims[13] = 4
rect_lease_dims[14] = 4
rect_lease_dims[15] = 3
rect_lease_dims[16] = 4
rect_lease_dims[17] = 5
rect_lease_dims[18] = 3
rect_lease_dims[19] = 5
rect_lease_dims[20] = 5
rect_lease_dims[21] = 4
rect_lease_dims[22] = 4
rect_lease_dims[23] = 5
rect_lease_dims[24] = 2
rect_lease_dims[25] = 2
rect_lease_dims[26] = 5
rect_lease_dims[27] = 2
rect_lease_dims[28] = 3
rect_lease_dims[29] = 5
rect_lease_dims[30] = 2
rect_lease_dims[31] = 5
rect_lease_dims[32] = 6
rect_lease_i = 0 ## i64
while rect_lease_i < 11
  rect_lease_source = read_file(ffrgb_source_rel(rect_lease_dims[rect_lease_i * 3], rect_lease_dims[rect_lease_i * 3 + 1], rect_lease_dims[rect_lease_i * 3 + 2]))
  z = ffrgb_expect("persistent crash lease " + rect_lease_i.to_s(), rect_lease_source != nil && rect_lease_source.include?("persistent_idle_timeout_ms = " + ffpg_worker_idle_timeout_ms().to_s()) && rect_lease_source.include?("persistent_generation.to_s() + \" expired \""))
  rect_lease_i += 1
z = ffrgb_expect("epoch quotes paths", cmd.include?("'seed file'") && cmd.include?("'best file'"))
z = ffrgb_expect("reject short geometry", ffrgb_epoch_command("/repo", "/tmp/rect", 3, 3, 4, "s", "b", "", 28, 1, 1, 1, 1, 1, 1, 15, "", 1, 1) == "")

z = ffrgb_expect("rect MITM allowlist", ffrmw_supported(2, 2, 5) == 1 && ffrmw_supported(2, 3, 4) == 1 && ffrmw_supported(2, 3, 5) == 1 && ffrmw_supported(2, 4, 5) == 1 && ffrmw_supported(2, 5, 6) == 1 && ffrmw_supported(3, 3, 4) == 0)
z = ffrgb_expect("rect MITM measured pools", ffrmw_pool(2, 2, 5) == 384 && ffrmw_pool(2, 3, 4) == 256 && ffrmw_pool(2, 3, 5) == 384 && ffrmw_pool(2, 4, 5) == 384 && ffrmw_pool(2, 5, 6) == 384)
z = ffrgb_expect("rect MITM single cadence", ffrmw_due(0, 0) == 1 && ffrmw_due(7, 0) == 0 && ffrmw_due(8, 0) == 1)
z = ffrgb_expect("rect MITM portfolio cadence", ffrmw_due(0, 1) == 1 && ffrmw_due(1, 1) == 0)
z = ffrgb_expect("rect MITM epoch parsing", ffrmw_epoch_from_tag("run_245_e17") == 17 && ffrmw_launch_number("run_245_e17", 0, 1) == 17)
z = ffrgb_expect("rect MITM rotation", ffrmw_nearby(0) == 0 && ffrmw_nearby(1) == 4 && ffrmw_nearby(2) == 8 && ffrmw_offset(9) == 32)
mitm_build = ffrmw_build_command("/repo path", "/tmp/rect mitm")
z = ffrgb_expect("rect MITM native build", mitm_build.include?("flipfleet_rect_mitm_lane.w") && mitm_build.include?("TUNGSTEN_METAL_PATH") && !mitm_build.include?("python"))
mitm_cmd = ffrmw_epoch_command("/repo", "/tmp/rect-mitm", "seed file", "out file", 2, 4, 5, 16, 384, 8, 64)
z = ffrgb_expect("rect MITM epoch ABI", mitm_cmd.include?("'seed file' 'out file' 2x4x5 16 384 8 64 ''") && mitm_cmd.ends_with?("'/tmp/rect-mitm.metallib'") && !mitm_cmd.include?("python"))
mitm_235_cmd = ffrmw_epoch_command("/repo", "/tmp/rect-mitm", "seed", "out", 2, 3, 5, 16, 384, 4, 32)
z = ffrgb_expect("235 MITM epoch ABI", mitm_235_cmd.include?("'seed' 'out' 2x3x5 16 384 4 32 ''"))
mitm_256_cmd = ffrmw_epoch_command("/repo", "/tmp/rect-mitm", "seed", "out", 2, 5, 6, 16, 384, 8, 64)
z = ffrgb_expect("256 MITM epoch ABI", mitm_256_cmd.include?("'seed' 'out' 2x5x6 16 384 8 64 ''"))
z = ffrgb_expect("rect MITM rejects other shapes", ffrmw_epoch_command("/repo", "/tmp/rect-mitm", "s", "o", 3, 3, 4, 16, 256, 0, 0) == "")

<< "PASS flipfleet rectangular GPU bundle"
