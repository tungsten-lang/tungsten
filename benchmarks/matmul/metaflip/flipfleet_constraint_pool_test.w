use flipfleet_constraint_pool_lib

-> ffpc_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)

command = ffpc_epoch_command("/repo path", "/tmp/constraint worker", "/tmp/seed", "/tmp/out", 7, 2, 256, 20000, 9)
ffpc_expect("quoted seed", command.include?("'/tmp/seed'"))
ffpc_expect("cached library", command.ends_with?(" '/tmp/constraint worker.metallib'"))
ffpc_expect("checked-in sidecar", command.include?("flipfleet_constraint_pool.metal"))
<< "flipfleet_constraint_pool_test: all checks passed"
