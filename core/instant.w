# Instant — millisecond-precision timestamp (tag 0xFFFB).
#
# A point in absolute time (UTC), independent of any calendar or clock
# face. Useful for log entries, event sourcing, monotonic ordering, and
# "when did this happen?" queries that don't care about local time.
#
# Wvalue layout: signed milliseconds-since-Unix-epoch (1970-01-01T00:00:00Z)
# in low bits. Bit-order matches chronological order, so Instant supports
# the BitOrdered trait for O(1) <=>.
#
# Distinct from:
#   Date       — calendar day, no time-of-day
#   Time       — time-of-day, no date
#   DateTime   — calendar + clock, may carry zone info
#   Duration   — span, not a point
+ Instant
  is Comparable
  is BitOrdered

  EPOCH_MILLIS = 0
  MILLIS_PER_SECOND = 1_000

  - data
    millis i64                 # ms since Unix epoch, signed (negative = pre-1970)

  # ---- construction ----
  -> parse(string)              # accepts ISO 8601 datetime, RFC 3339, Unix-ms numeric
  -> now                        # current wall-clock instant
  -> epoch                      # 1970-01-01T00:00:00Z
  -> from_seconds(seconds)
  -> from_millis(millis)
  -> from_nanos(nanos)
  -> from_date_time(dt)         # converts a DateTime (with tz) to Instant

  # ---- accessors ----
  -> millis                     # ms since epoch
  -> seconds                    # rational seconds since epoch
  -> nanos                      # ns since epoch (within i64 range)

  -> wvalue_bits
  -> hash
    self.wvalue_bits

  # ---- conversion ----
  -> to_date                    # truncate to UTC date
  -> to_date_time(zone)         # localize to a tz, return DateTime
  -> to_time(zone)              # localize, return Time-of-day component
  -> utc                        # alias for to_date_time(UTC)

  # ---- arithmetic ----
  # Instant + Duration          → Instant      (months OK; calendar-stable)
  # Instant + Quantity[time]    → Instant
  # Instant - Instant           → Quantity[time]   (delta in seconds)
  # Instant - Duration          → Instant
  -> +(other)
  -> -(other)

  # ---- predicates ----
  -> before?(other)
    self < other
  -> after?(other)
    self > other
  -> within?(span, of)          # |self - of| <= span

  # ---- comparison ----
  -> ==(other)

  # ---- formatting ----
  -> to_s                       # "2026-05-05T14:32:09.123Z"
  -> iso8601
  -> rfc3339
  -> unix_ms                    # alias for millis (numeric)
  -> inspect
    self.to_s
