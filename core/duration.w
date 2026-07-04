# Duration — time span (tag 0xFFFF). Two-component representation:
#
#   @months  — integer count of nominal months. Used for calendar-aware
#              arithmetic where the actual duration depends on the date
#              (e.g., "1 month from January 31" → February 28 or 29).
#   @seconds — Rational count of fixed-length seconds, including any
#              sub-second precision. Used for clock-aware arithmetic.
#
# Two duration instances may be incompatible if one has only @months and
# the other only @seconds — division of mixed durations raises.
#
# Source syntax:
#   compact: `1d2h30m`, `5y6mo`, `2.5h`            — order-validated
#   ISO 8601: `P1DT2H30M`, `PT5H`, `P1Y6M`        — full standard
#
# Bridges to Quantity[time]:
#   Duration with @months == 0 can be added to or subtracted from
#   Quantity[time], and vice versa. Mixing months with Quantity errors
#   because months are calendar-dependent.
+ Duration
  is Comparable

  - data
    months i64
    seconds rational

  # ---- compact syntax: 1y, 1mo, 1w, 1d, 1h, 1m, 1s, 1ms, 1µs, 1ns ----
  UNIT_SECONDS_W   = 604_800
  UNIT_SECONDS_D   = 86_400
  UNIT_SECONDS_H   = 3_600
  UNIT_SECONDS_M   = 60
  UNIT_SECONDS_S   = 1
  UNIT_MONTHS_Y    = 12
  UNIT_MONTHS_MO   = 1

  # ---- construction ----
  -> parse(string)              # routes between parse_compact and parse_iso
  -> parse_compact(string)      # `2h15m30s`
  -> parse_iso(string)          # `P1DT2H30M`
  -> of_months(months)
  -> of_seconds(seconds)
  -> zero

  # ---- accessors ----
  -> months                     # signed integer; 0 for fixed-only durations
  -> seconds                    # signed Rational; 0 for nominal-only durations
  -> total_months
    self.months                  # alias
  -> total_seconds
    self.seconds

  -> calendar?                  # has nominal months — calendar-dependent
    self.months != 0
  -> fixed?                     # has only seconds — clock-precise
    self.months == 0

  # ---- arithmetic ----
  # Duration + Duration         → Duration
  # Duration + Date / DateTime  → Date / DateTime (delegated)
  # Duration + Quantity[time]   → Duration       (months must be 0)
  # Duration - Duration         → Duration
  # Duration * Numeric          → Duration       (scales both months and seconds)
  # Duration * Quantity         → Quantity        (treats self as Quantity[time])
  # Duration / Duration         → Rational        (only when same kind)
  # Duration / Numeric          → Duration
  # Duration / Quantity[time]   → Rational
  # Operator forms (+, -, *, /, unary -) are implemented at the runtime
  # level — the parser handles `*` and `/` specially for arity-method names.
  -> +(other)
  -> -(other)

  -> apply_months(date)         # adds @months to a Date in calendar-aware way

  # ---- comparison ----
  -> <=>(other)
  -> ==(other)
  -> hash

  # ---- formatting ----
  -> to_s                       # "1d2h30m" compact form
  -> iso8601                    # "P1DT2H30M"
  -> inspect
    self.to_s
