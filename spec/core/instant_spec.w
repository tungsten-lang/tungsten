# Instant — millisecond-precision UTC timestamp (core/instant.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/instant_spec.w
#   bin/tungsten -o /tmp/instant_spec spec/core/instant_spec.w && /tmp/instant_spec

use core/instant

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

i = Instant.new
check("constructs", type(i) == "Instant")
check("is_a? Instant", i.is_a?(Instant))
check("class name", i.class_name == "Instant")
check("== reflexive", i == i)

check("epoch millis", Instant.epoch.millis == 0)
check("from_millis", Instant.from_millis(1500).seconds == 3/2)
check("from_seconds", Instant.from_seconds(90).millis == 90000)
check("from_nanos truncates to ms", Instant.from_nanos(1500000).millis == 1)
check("parse iso", Instant.parse("1970-01-02T00:00:00Z").millis == 86400000)
check("parse unix ms", Instant.parse("1000").millis == 1000)
check("negative epoch", Instant.from_millis(-1).to_s == "1969-12-31T23:59:59.999Z")
check("to_s", Instant.from_millis(86400123).to_s == "1970-01-02T00:00:00.123Z")
check("unix_ms", Instant.from_millis(42).unix_ms == 42)
check("ordering", Instant.from_millis(1).before?(Instant.from_millis(2)))
check("after?", Instant.from_millis(2).after?(Instant.from_millis(1)))
check("==", Instant.from_millis(5) == Instant.from_millis(5))
check("hash", Instant.from_millis(5).hash == Instant.from_millis(5).hash)
check("to_date", Instant.from_millis(86400000).to_date == 1970-01-02)
check("now is after epoch", Instant.now.after?(Instant.epoch) && Instant.now.millis > 1_700_000_000_000)
check("constants", Instant.MILLIS_PER_SECOND == 1000 && Instant.EPOCH_MILLIS == 0)
check("plus duration", (Instant.epoch + 1h0m).millis == 3600000)
check("plus millis", (Instant.from_millis(86400000) + 1000).millis == 86401000)
check("within", Instant.from_millis(1500).within?(1s, Instant.from_millis(1000)))
check("month clamps", (Instant.parse("1970-01-31T00:00:00Z") + 1mo).to_s == "1970-02-28T00:00:00Z")
check("minus instant", (Instant.from_millis(5000) - Instant.from_millis(2000)) == 3 s)
check("minus millis quantity", (Instant.from_millis(1500) - Instant.from_millis(0)) == 1500 ms)

<< "ALL PASS instant_spec ([passed.load()] checks)"
