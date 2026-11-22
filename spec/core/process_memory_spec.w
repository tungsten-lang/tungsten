# Process.memory_footprint / memory_limit.
#
# Run: `bin/tungsten spec/core/process_memory_spec.w`

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

check("footprint.positive", Process.memory_footprint > 0)
old = Process.memory_limit
Process.memory_limit = 64 * 1024 * 1024 * 1024
check("limit.set", Process.memory_limit == 64 * 1024 * 1024 * 1024)
Process.memory_limit = 0
check("limit.cleared", Process.memory_limit == 0)
Process.memory_limit = old
<< "process_memory_spec: all passed"
