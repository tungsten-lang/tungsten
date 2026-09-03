# Time — time-of-day value (core/time.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/time_spec.w
#   bin/tungsten -o /tmp/time_spec spec/core/time_spec.w && /tmp/time_spec
#
# Interpreter lane: the compiled build of core/time.w fails (see BUG below).

use core/time

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# BUG: `use core/time` fails to compile: "Unknown trait 'BitOrdered'". core/traits/bit_ordered.w
# exists but is not registered in the `auto` manifest in core/tungsten.w, so the compiled lane
# never autoloads it. Repro: printf 'use core/time\n<< 1\n' > /tmp/t.w && bin/tungsten -o /tmp/t /tmp/t.w

t = Time.new
check("constructs", type(t) == "Time")
check("is_a? Time", t.is_a?(Time))
check("class name", t.class_name == "Time")

# BUG: `t == t` raises "undefined method '<=>'" — Time is `is Comparable` but supplies no <=>
# body and no runtime intrinsic, so even reflexive equality is unavailable (interpreter).
# check("== reflexive", t == t)

# BUG: the documented time-of-day literal `14:30:00` evaluates to a Date ("0000-00-00T14:30:00Z"), not a Time,
# and the short form `09:30` / `12:30+05:30` / `12:30Z` do not parse at all (interpreter)
# check("literal type", type(14:30:00) == "Time")
# check("short literal", type(09:30) == "Time")
# BUG: Time.parse / .now / .midnight / .noon / .of and the accessors hour / minute / second / fraction / nanoseconds /
# tz_offset / wvalue_bits / with_tz / to_utc / in_zone / strftime / + / - are bodyless with no runtime implementation
# check("hour", 14:30:45.hour == 14)
# check("minute", 14:30:45.minute == 30)
# check("second", 14:30:45.second == 45)
# check("fraction", 12:30:45.123.fraction == 123000000)
# check("nanoseconds", 00:00:01.nanoseconds == 1000000000)
# check("naive?", 14:30:00.naive? && !14:30:00.aware?)
# check("hour_12 midnight", Time.midnight.hour_12 == 12)
# check("hour_12 afternoon", 14:30:00.hour_12 == 2)
# check("am?/pm?", 09:30:00.am? && 14:30:00.pm?)
# check("meridiem", 09:30:00.meridiem == :am && 14:30:00.meridiem == :pm)
# check("seconds_of_day", 01:00:00.seconds_of_day == 3600)
# check("to_s naive", 14:30:45.to_s == "14:30:45")
# check("iso8601", 14:30:45.iso8601 == "14:30:45")
# check("with_tz", 14:30:45.with_tz(3600).to_s == "14:30:45+01:00")
# check("to_utc", 14:30:45.with_tz(3600).to_utc.to_s == "13:30:45+00:00")
# check("wraps past midnight", (23:30:00 + 1h0m).to_s == "00:30:00")
# check("difference", (14:30:00 - 12:00:00) == 9000 s)
# check("ordering", 09:00:00 < 17:00:00)
# check("business_hours?", 12:00:00.business_hours?(09:00:00, 17:00:00) && !17:00:00.business_hours?(09:00:00, 17:00:00))
# check("between? inclusive", 17:00:00.between?(09:00:00, 17:00:00))
# check("strftime", 14:30:45.strftime("%I:%M %p") == "02:30 PM")
# check("constants", Time.SECONDS_PER_DAY == 86400 && Time.NANOS_PER_SECOND == 1000000000 && Time.TZ_NAIVE == -1)
# check("midnight", Time.midnight.to_s == "00:00:00")
# check("noon", Time.noon.to_s == "12:00:00")
# check("of", Time.of(1, 2, 3, 0, -1).to_s == "01:02:03")

<< "ALL PASS time_spec ([passed.load()] checks)"
