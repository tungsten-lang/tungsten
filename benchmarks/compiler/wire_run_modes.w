# Deterministic workload for comparing cached WIRE-backed `run` with the
# legacy `--interpret` tree-walker. Keep timing outside the program so both
# modes execute byte-identical source and emit byte-identical output.

-> wire_run_step(n)
  n + 1

-> wire_run_wrap(n)
  wire_run_step(n)

iterations = ARGV.size() > 0 ? ARGV[0].to_i() : 500_000
result = 0
i = 0
while i < iterations
  result = wire_run_wrap(result)
  i += 1

raise "wire run benchmark mismatch" if result != iterations
<< result
