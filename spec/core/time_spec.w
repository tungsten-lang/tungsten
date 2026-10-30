# Time — time-of-day value (core/time.w).
#
# Run:
#   bin/tungsten spec/core/time_spec.w
#   bin/tungsten run --interpret spec/core/time_spec.w

use core/time

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

t = Time.new
check("constructs", type(t) == "Time")
check("is_a? Time", t.is_a?(Time))
check("class name", t.class_name == "Time")
check("== reflexive", t == t)

check("literal type", type(14:30:00) == "Time")
check("fraction literal", type(12:30:45.123) == "Time")
check("hour", (14:30:45).hour == 14)
check("minute", (14:30:45).minute == 30)
check("second", (14:30:45).second == 45)
check("fraction", (12:30:45.123).fraction == 123000000)
check("nanoseconds", (00:00:01).nanoseconds == 1000000000)
check("naive?", (14:30:00).naive? && !(14:30:00).aware?)
check("zone literal", (12:30:00Z).aware? && (14:30:45+01:00).tz_offset == 3600)
check("hour_12 midnight", Time.midnight.hour_12 == 12)
check("hour_12 afternoon", (14:30:00).hour_12 == 2)
check("am?/pm?", (09:30:00).am? && (14:30:00).pm?)
check("meridiem", (09:30:00).meridiem == :am && (14:30:00).meridiem == :pm)
check("seconds_of_day", (01:00:00).seconds_of_day == 3600)
check("to_s naive", (14:30:45).to_s == "14:30:45")
check("iso8601", (14:30:45).iso8601 == "14:30:45")
check("with_tz", (14:30:45).with_tz(3600).to_s == "14:30:45+01:00")
check("to_utc", (14:30:45).with_tz(3600).to_utc.to_s == "13:30:45+00:00")
check("wraps past midnight", (23:30:00 + 1h0m).to_s == "00:30:00")
check("difference", (14:30:00 - 12:00:00) == 9000 s)
check("ordering", 09:00:00 < 17:00:00)
check("business_hours?", (12:00:00).business_hours?(09:00:00, 17:00:00) && !(17:00:00).business_hours?(09:00:00, 17:00:00))
check("between? inclusive", (17:00:00).between?(09:00:00, 17:00:00))
check("strftime", (14:30:45).strftime("%I:%M %p") == "02:30 PM")
check("constants", Time.SECONDS_PER_DAY == 86400 && Time.NANOS_PER_SECOND == 1000000000 && Time.TZ_NAIVE == -1)
check("midnight", Time.midnight.to_s == "00:00:00")
check("noon", Time.noon.to_s == "12:00:00")
check("of", Time.of(1, 2, 3, 0, -1).to_s == "01:02:03")
check("parse short", Time.parse("09:30").to_s == "09:30:00")
check("parse offset", Time.parse("12:30+05:30").to_s == "12:30:00+05:30")
check("leap second", Time.of(23, 59, 60).to_s == "23:59:60")

<< "ALL PASS time_spec ([passed.load()] checks)"
