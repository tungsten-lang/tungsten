use flipfleet_frozen_fringe_sat_pool_lib
use flipfleet_frozen_fringe_sat_bundle

-> fffspt_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)

root = "/repo with spaces" ## String
binary = "/tmp/frozen sat worker" ## String
seed = "/tmp/exact seed" ## String
output = "/tmp/frozen sat output" ## String
build = fffsb_build_command(root, binary) ## String
fffspt_expect("build source", build.include?("flipfleet_frozen_fringe_sat_pool.w"))
fffspt_expect("release native build", build.include?("--release") && build.include?("--native") && build.include?("--fast") && build.include?("--lto"))
fffspt_expect("quoted build paths", build.include?("'/repo with spaces'") && build.include?("'/tmp/frozen sat worker'"))

epoch = fffsb_epoch_command(root, binary, seed, output, 17, 23) ## String
fffspt_expect("epoch command", epoch.include?("'/tmp/exact seed' '/tmp/frozen sat output' 17 23"))
fffspt_expect("same input/output rejected", fffsb_epoch_command(root, binary, seed, seed, 17, 23) == "")
fffspt_expect("zero timeout rejected", fffsb_epoch_command(root, binary, seed, output, 0, 23) == "")
fffspt_expect("negative nonce rejected", fffsb_epoch_command(root, binary, seed, output, 17, 0 - 1) == "")
fffspt_expect("solver command from PATH", fffsp_solver_command() == "cryptominisat5 --verb 0")
fffspt_expect("solver has graceful deadline", fffsp_timed_solver_command(17) == "cryptominisat5 --verb 0 --maxtime 17")
fffspt_expect("status labels", fffsp_status_label(1) == "sat" && fffsp_status_label(0 - 1) == "unsat" && fffsp_status_label(0 - 2) == "timeout-or-process")

# A failing injected solver is an ordinary bounded miss.  It must not publish
# even if a stale output existed before the epoch.
real_seed = "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt" ## String
miss_output = "/tmp/flipfleet_frozen_fringe_sat_pool_test.out" ## String
z = write_file(miss_output, "stale\n")
meta = i64[16]
miss = fffsp_run_with_solver(real_seed, miss_output, 1, 29, "/usr/bin/false", meta) ## i64
fffspt_expect("process failure is clean miss", miss == 0 && meta[9] == 0 - 2)
fffspt_expect("miss publishes no output", read_file(miss_output) == nil)
fffspt_expect("query was clustered 16 to 15", meta[0] == 1 && meta[1] == 16 && meta[2] == 15)
fffspt_expect("bounded exact query dimensions", meta[6] > 0 && meta[6] <= 4096 && meta[7] > 0 && meta[8] > 0)

<< "flipfleet frozen-fringe SAT pool tests passed cells=" + meta[6].to_s() + " vars=" + meta[7].to_s() + " clauses=" + meta[8].to_s()
