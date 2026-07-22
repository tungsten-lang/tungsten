# Global sleep(): links and honors Int / Decimal / Float durations.
#
# Regression for the 2026-07-22 fix: bare `sleep(n)` lowered to `__w_sleep`,
# which did not exist in the runtime — every program calling sleep() failed
# at LINK time. (`__w_sleep_ms` via ccall was the workaround.)
#
# Run: `bin/tungsten -o /tmp/gs spec/core/global_sleep_spec.w && /tmp/gs`

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

check("sleep.zero", sleep(0) == 0)

t0 = clock()
sleep(0.05)
t1 = clock()
check("sleep.decimal", t1 - t0 >= ~0.04)

sleep(~0.05)
t2 = clock()
check("sleep.float", t2 - t1 >= ~0.04)

check("sleep.int.returns", sleep(0) == 0)
