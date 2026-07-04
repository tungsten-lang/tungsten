# Time — time-of-day literal (no date component).
#
# Source syntax: `12:30:45`, `09:30`, `12:30:45.123`, `12:30+05:30`, `12:30Z`.
# Distinct from DateTime (no date) and Duration (not relative). Useful for
# schedules, alarms, business-hours checks, recurring events.
#
# Wvalue layout: nanoseconds-since-midnight in low bits + tz-offset in high
# bits. Bit-order matches chronological order within a single naive day, so
# Time can include the BitOrdered trait for O(1) <=>.
+ Time
  is Comparable
  is BitOrdered

  SECONDS_PER_DAY = 86_400
  NANOS_PER_SECOND = 1_000_000_000
  TZ_NAIVE = -1

  ISO8601_FORMAT    = "%H:%M:%S"
  ISO8601_TZ_FORMAT = "%H:%M:%S%:z"
  RFC3339_FORMAT    = "%H:%M:%S%:z"
  SHORT_FORMAT      = "%H:%M"
  TWELVE_FORMAT     = "%I:%M %p"
  TWELVE_SEC_FORMAT = "%I:%M:%S %p"

  - data
    nanos i64
    tz_offset i32

  # ---- construction (class-level entry points) ----
  -> parse(string)
  -> now
  -> midnight
  -> noon
  -> of(hour, minute, second, fraction, tz)

  # ---- accessors ----
  -> hour
  -> minute
  -> second
  -> fraction
  -> nanoseconds
  -> tz_offset

  -> naive?
    @tz_offset == TZ_NAIVE

  -> aware?
    @tz_offset != TZ_NAIVE

  -> hour_12
    h = self.hour
    if h == 0
      12
    elsif h > 12
      h - 12
    else
      h

  -> am?
    self.hour < 12

  -> pm?
    self.hour >= 12

  -> meridiem
    self.am? ? :am : :pm

  -> seconds_of_day
    self.nanoseconds / NANOS_PER_SECOND

  # ---- timezone ----
  -> with_tz(offset)
  -> to_utc
  -> in_zone(offset)

  # ---- arithmetic ----
  # Time + Duration            → Time (wraps mod 24h)
  # Time + Quantity[time]      → Time (wraps mod 24h)
  # Time - Time                → Quantity[time]
  # Time - Duration            → Time (wraps mod 24h)
  -> +(other)
  -> -(other)

  # ---- comparison (delegated to BitOrdered via wvalue_bits) ----
  -> wvalue_bits

  -> hash
    self.wvalue_bits

  # ---- predicates ----
  -> business_hours?(start, ending)
    self >= start && self < ending

  -> between?(start, ending)
    self >= start && self <= ending

  # ---- formatting ----
  -> to_s
    self.naive? ? self.strftime(ISO8601_FORMAT) : self.strftime(ISO8601_TZ_FORMAT)

  -> iso8601
    self.strftime(ISO8601_FORMAT)

  -> rfc3339
    self.strftime(RFC3339_FORMAT)

  -> inspect
    self.to_s

  # Formats the time-of-day per `strftime`. Honors the same directives as
  # Date#strftime that apply to time-only values:
  #
  #   %H — hour (00..23)            %k — hour ( 0..23) blank-padded
  #   %I — hour (01..12)            %l — hour ( 1..12) blank-padded
  #   %M — minute (00..59)
  #   %S — second (00..59)
  #   %L — millisecond (000..999)
  #   %N — nanosecond (default 9 digits)
  #   %p — AM/PM uppercase
  #   %P — am/pm lowercase
  #   %z — ±hhmm tz offset (e.g. -0500)
  #   %:z — ±hh:mm tz offset (e.g. -05:00)
  #   %Z — tz abbrev (UTC, PST, …) — naive Times produce "" here
  #   %%, %n, %t — literal %, newline, tab
  -> strftime(format)
