# Instant — millisecond-precision UTC timestamp (core/instant.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/instant_spec.w
#   bin/tungsten -o /tmp/instant_spec spec/core/instant_spec.w && /tmp/instant_spec
#
# Interpreter lane: the compiled build of core/instant.w fails (see BUG below).

use core/instant

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# BUG: `use core/instant` fails to compile: "Unknown trait 'BitOrdered'". The trait file
# core/traits/bit_ordered.w exists, but it is missing from the `auto` manifest in core/tungsten.w
# (only Comparable/Enumerable/Printable/Inspectable/Debuggable are registered), so the compiled
# lane never autoloads it. Adding `auto :BitEqual, "traits/bit_equal"` and
# `auto :BitOrdered, "traits/bit_ordered"` there fixes it.
# Repro: printf 'use core/instant\n<< 1\n' > /tmp/i.w && bin/tungsten -o /tmp/i /tmp/i.w

i = Instant.new
check("constructs", type(i) == "Instant")
check("is_a? Instant", i.is_a?(Instant))
check("class name", i.class_name == "Instant")
check("== reflexive", i == i)

# BUG: every Instant constructor and accessor is undefined (interpreter): now, epoch, parse, from_seconds,
# from_millis, from_nanos, from_date_time, millis, seconds, nanos, wvalue_bits, to_date, to_date_time, to_time,
# utc, +, -, within?, ==, to_s, iso8601, rfc3339, unix_ms; the constants EPOCH_MILLIS / MILLIS_PER_SECOND too.
# check("epoch millis", Instant.epoch.millis == 0)
# check("from_millis", Instant.from_millis(1500).seconds == 3/2)
# check("from_seconds", Instant.from_seconds(90).millis == 90000)
# check("from_nanos truncates to ms", Instant.from_nanos(1500000).millis == 1)
# check("parse iso", Instant.parse("1970-01-02T00:00:00Z").millis == 86400000)
# check("parse unix ms", Instant.parse("1000").millis == 1000)
# check("negative epoch", Instant.from_millis(-1).to_s == "1969-12-31T23:59:59.999Z")
# check("to_s", Instant.from_millis(86400123).to_s == "1970-01-02T00:00:00.123Z")
# check("unix_ms", Instant.from_millis(42).unix_ms == 42)
# check("ordering", Instant.from_millis(1).before?(Instant.from_millis(2)))
# check("after?", Instant.from_millis(2).after?(Instant.from_millis(1)))
# check("==", Instant.from_millis(5) == Instant.from_millis(5))
# check("hash", Instant.from_millis(5).hash == Instant.from_millis(5).hash)
# check("to_date", Instant.from_millis(86400000).to_date == 1970-01-02)
# check("now is after epoch", Instant.now.after?(Instant.epoch))
# check("constants", Instant.MILLIS_PER_SECOND == 1000 && Instant.EPOCH_MILLIS == 0)

<< "ALL PASS instant_spec ([passed.load()] checks)"
