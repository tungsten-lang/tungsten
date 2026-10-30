# A time literal autoloads Time. This file does not name Time or use core/time.
#
# Run:
#   bin/tungsten spec/core/time_literal_spec.w
#   bin/tungsten run --interpret spec/core/time_literal_spec.w

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

check("bare type", type(14:30:00) == "Time")
check("bare hour", (14:30:45).hour == 14)
check("bare to_s", (14:30:45).to_s == "14:30:45")
check("method call", 14:30:45.hour == 14)
check("zone", (14:30:45+01:00).tz_offset == 3600)

<< "ALL PASS time_literal_spec ([passed.load()] checks)"
