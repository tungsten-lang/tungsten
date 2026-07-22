# System class methods resolve in compiled binaries.
#
# Regression for the 2026-07-22 fix: `System` was missing from the core
# auto table (core/tungsten.w), so the constant resolved to nil in compiled
# programs and `System.cpu_count` died with "undefined method for nil".
#
# Run: `bin/tungsten -o /tmp/scc spec/core/system_cpu_count_spec.w && /tmp/scc`

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

n = System.cpu_count
check("system.cpu_count.positive", n >= 1)
check("system.cpu_count.sane", n <= 4096)

p = System.executable_path
check("system.executable_path.nonempty", p.size() > 0)
