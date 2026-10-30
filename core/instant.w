# Instant — millisecond-precision UTC timestamp.
#
# A point on the absolute timeline, independent of any calendar or clock
# face. Milliseconds since 1970-01-01T00:00:00Z, about 2491 BC through
# 6431 AD (signed 48-bit). The runtime also packs that count in tag
# 0xFFF8. A packed word and an Instant with the same count compare equal,
# and BitOrdered orders by the count.
#
# Distinct from:
#   Date     — civil day, and the packed datetime carrier
#   Time     — time-of-day, no date
#   Duration — span, not a point
+ Instant
  is Comparable
  is BitOrdered

  EPOCH_MILLIS = 0
  MILLIS_PER_SECOND = 1_000
  NANOS_PER_MILLI = 1_000_000
  MILLIS_PER_DAY = 86_400_000
  # 48-bit two's complement, matching w_box_instant.
  MILLIS_MIN = -140_737_488_355_328
  MILLIS_MAX = 140_737_488_355_327

  - data
    millis i64

  -> new(@millis = 0)

  -> .EPOCH_MILLIS
    0

  -> .MILLIS_PER_SECOND
    1_000

  -> .epoch
    Instant.new(0)

  -> .from_millis(millis)
    n = millis.to_i()
    if n < -140_737_488_355_328 || n > 140_737_488_355_327
      raise "Instant millis out of range"
    Instant.new(n)

  -> .from_seconds(seconds)
    Instant.from_millis(seconds * 1_000)

  # Truncates toward zero. 1_500_000 ns is 1 ms; 1_999_999 ns is 1 ms.
  -> .from_nanos(nanos)
    Instant.from_millis(nanos / 1_000_000)

  -> .now
    # w_instant_now is the packed UTC word. millis accepts that word.
    Instant.from_millis(ccall("w_instant_now").millis)

  # Whole-millisecond text ("1000", "-1") or an ISO-8601 / RFC 3339
  # datetime. A numeric offset is converted to UTC. A date with no clock
  # is midnight UTC.
  -> .parse(string)
    text = string.to_s().strip()
    if Instant.__integer_text?(text)
      return Instant.from_millis(text.to_i())
    Instant.__parse_iso(text)

  # Packed Date (including a datetime literal) converted to UTC.
  # Nominal months are not involved: the civil fields are one instant.
  -> .from_date_time(dt)
    if dt.class_name == "Instant"
      return dt
    if dt.class_name != "Date"
      raise "Instant.from_date_time expects a Date"
    days = Instant.__civil_to_days(dt.year, dt.month, dt.day)
    secs = days * 86_400 + dt.hour * 3_600 + dt.minute * 60 + dt.second - dt.tz * 60
    Instant.from_millis(secs * 1_000)

  # Heap Instants store @millis. Tag 0xFFF8 is the same count packed
  # into a word (w_box_instant); read that payload instead of a field.
  -> millis
    bits = $value ## i64
    tag = ((bits >> 48) ## i64) & 65_535
    if tag == 65_528
      payload = bits & 281_474_976_710_655
      if payload >= 140_737_488_355_328
        return payload - 281_474_976_710_656
      return payload
    @millis

  -> unix_ms
    millis

  -> seconds
    Rational.new(millis, 1_000)

  -> nanos
    millis * 1_000_000

  -> wvalue_bits
    millis

  -> hash
    millis

  -> ==(other)
    other.is_a?(Instant) && millis == other.millis

  -> <=>(other)
    return nil if !other.is_a?(Instant)
    @millis <=> other.millis

  -> to_date
    parts = Instant.__civil_sod(millis)
    Date.new(parts[0], parts[1], parts[2])

  # Local clock as a Time. `zone` is a UTC offset in seconds; nil keeps
  # the UTC clock and leaves the Time naive.
  -> to_time(zone = nil)
    off = 0
    tag = Time.TZ_NAIVE
    if zone != nil
      off = zone
      tag = zone
    parts = Instant.__civil_sod(millis + off * 1_000)
    Time.of(parts[3], parts[4], parts[5], parts[6] * 1_000_000, tag)

  # Date is the packed datetime. `zone` is a UTC offset in seconds and
  # must land on a Date timezone (whole minutes, 15-minute steps, or
  # Amsterdam +00:20).
  -> to_date_time(zone = 0)
    if zone % 60 != 0
      raise "Instant timezone must be a whole number of minutes"
    off = zone
    parts = Instant.__civil_sod(millis + off * 1_000)
    Date.new(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], off / 60)

  -> utc
    to_date_time(0)

  # `instant + int` is a millisecond shift. `instant - instant` is a
  # seconds Quantity (or milliseconds, when the difference is not whole
  # seconds). The runtime's w_sub still returns a nanosecond Duration for
  # direct C callers; Tungsten infix uses this method. Nominal months move
  # the UTC calendar date and clamp the day.
  -> +(other)
    Instant.from_millis(millis + Instant.__shift_millis(millis, other))

  -> -(other)
    if other.class_name == "Instant"
      return Instant.__seconds_quantity(millis - other.millis)
    Instant.from_millis(millis - Instant.__shift_millis(millis, other))

  -> before?(other)
    self < other

  -> after?(other)
    self > other

  # `span` is milliseconds (an integer), a Duration, or a time Quantity.
  -> within?(span, of)
    if of.class_name != "Instant"
      raise "Instant#within? expects an Instant"
    diff = millis - of.millis
    if diff < 0
      diff = 0 - diff
    diff <= Instant.__shift_millis(of.millis, span)

  -> to_s
    parts = Instant.__civil_sod(millis)
    y = parts[0]
    out = StringBuffer()
    if y < 0
      out << "-"
      y = 0 - y
    out << Instant.__pad(y, 4)
    out << "-"
    out << Instant.__pad(parts[1], 2)
    out << "-"
    out << Instant.__pad(parts[2], 2)
    out << "T"
    out << Instant.__pad(parts[3], 2)
    out << ":"
    out << Instant.__pad(parts[4], 2)
    out << ":"
    out << Instant.__pad(parts[5], 2)
    frac = parts[6]
    if frac != 0
      out << "."
      out << Instant.__pad(frac, 3)
    out << "Z"
    out.to_s()

  -> iso8601
    to_s

  -> rfc3339
    to_s

  -> inspect
    to_s

  -> .__integer_text?(text)
    n = text.size()
    if n == 0
      return false
    i = 0
    if text[0] == "-"
      i = 1
    if i >= n
      return false
    while i < n
      c = text[i]
      if c < "0" || c > "9"
        return false
      i += 1
    true

  -> .__parse_iso(text)
    s = text
    if s.ends_with?("Z") || s.ends_with?("z")
      s = s.slice(0, s.size() - 1)
      off_min = 0
    else
      off_min = 0
      sign_at = Instant.__tz_sign_at(s)
      if sign_at != nil
        off_min = Instant.__offset_minutes(s.slice(sign_at, s.size() - sign_at))
        s = s.slice(0, sign_at)
    t_at = s.index("T")
    if t_at == nil
      t_at = s.index("t")
    if t_at == nil
      t_at = s.index(" ")
    date_part = s
    time_part = "00:00:00"
    if t_at != nil
      date_part = s.slice(0, t_at)
      time_part = s.slice(t_at + 1, s.size() - t_at - 1)
    ymd = date_part.split("-")
    if ymd.size() != 3
      raise "Instant.parse: expected YYYY-MM-DD, got [text]"
    clock = Instant.__hms_millis(time_part)
    days = Instant.__civil_to_days(ymd[0].to_i(), ymd[1].to_i(), ymd[2].to_i())
    Instant.from_millis(days * 86_400_000 + clock - off_min * 60_000)

  -> .__tz_sign_at(text)
    i = text.size() - 1
    while i > 9
      c = text[i]
      if c == "+" || c == "-"
        return i
      i -= 1
    nil

  -> .__offset_minutes(text)
    sign = 1
    body = text
    if text.starts_with?("-")
      sign = -1
      body = text.slice(1, text.size() - 1)
    elsif text.starts_with?("+")
      body = text.slice(1, text.size() - 1)
    parts = body.split(":")
    hours = parts[0].to_i()
    mins = 0
    if parts.size() > 1
      mins = parts[1].to_i()
    sign * (hours * 60 + mins)

  -> .__hms_millis(text)
    parts = text.split(":")
    if parts.size() < 2
      raise "Instant.parse: expected hh:mm[:ss], got [text]"
    hour = parts[0].to_i()
    minute = parts[1].to_i()
    second = 0
    frac = 0
    if parts.size() > 2
      sec = parts[2]
      dot = sec.index(".")
      if dot != nil
        frac = Instant.__frac_millis(sec.slice(dot + 1, sec.size() - dot - 1))
        sec = sec.slice(0, dot)
      second = sec.to_i()
    if hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 60
      raise "Instant.parse: clock out of range"
    ((hour * 60 + minute) * 60 + second) * 1_000 + frac

  -> .__frac_millis(digits)
    if digits.size() == 0
      return 0
    padded = digits
    if padded.size() > 3
      padded = padded.slice(0, 3)
    while padded.size() < 3
      padded = padded + "0"
    padded.to_i()

  -> .__shift_millis(origin, other)
    if other.is_a?(Int) || other.is_a?(Integer)
      return other
    kind = other.class_name
    if kind == "Duration"
      return Instant.__duration_millis(origin, other$value ## i64)
    if kind == "Quantity"
      return Instant.__quantity_millis(other)
    raise "cannot shift an Instant by [kind]"

  -> .__duration_millis(origin, bits) (i64 i64) i64
    tag = ((bits >> 48) ## i64) & 65_535
    if tag != 65_535
      raise "Instant cannot shift by a heap duration"
    mode = ((bits >> 47) ## i64) & 1
    if mode == 0
      ns = ((bits << 17) ## i64) >> 17
      return ns / 1_000_000
    months = ((bits >> 32) & 32_767) ## i64
    if months >= 16_384
      months = months - 32_768
    ms = (bits & 4_294_967_295) ## i64
    if months == 0
      return ms
    parts = Instant.__civil_sod(origin)
    shifted = Instant.__add_months(parts[0], parts[1], parts[2], months)
    sod = parts[3] * 3_600_000 + parts[4] * 60_000 + parts[5] * 1_000 + parts[6]
    day_ms = Instant.__civil_to_days(shifted[0], shifted[1], shifted[2]) * 86_400_000
    day_ms + sod + ms - origin

  -> .__quantity_millis(q)
    factor = Instant.__unit_millis(q.unit_name)
    if factor < 0
      raise "cannot shift an Instant by [q.unit_name]"
    b = q.value$value ## i64
    sig = ((b >> 7) & 549_755_813_887) ## i64
    if sig >= 274_877_906_944
      sig = sig - 549_755_813_888
    scale = (b & 127) ## i64
    if scale >= 64
      scale = scale - 128
    Instant.__scaled(sig, scale, factor)

  -> .__unit_millis(name)
    if name == "ns"
      return 0
    if name == "us" || name == "µs"
      return 0
    if name == "ms"
      return 1
    if name == "s"
      return 1_000
    if name == "min"
      return 60_000
    if name == "h"
      return 3_600_000
    if name == "d"
      return 86_400_000
    -1

  -> .__scaled(sig, scale, factor) (i64 i64 i64) i64
    n = sig ## i64
    f = factor ## i64
    k = 0
    if scale >= 0
      while k < scale
        n = n * 10
        k += 1
      return n * f
    while k < (0 - scale)
      if f % 10 == 0
        f = f / 10
      else
        n = n / 10
      k += 1
    n * f

  -> .__add_months(y, m, d, months) (i64 i64 i64 i64)
    total = y * 12 + (m - 1) + months
    ny = Instant.__floor_div(total, 12)
    nm = total - ny * 12 + 1
    dim = Instant.__month_length(ny, nm)
    nd = d
    if nd > dim
      nd = dim
    [ny, nm, nd]

  -> .__seconds_quantity(diff_ms) (i64)
    if diff_ms % 1_000 == 0
      return (diff_ms / 1_000) * (1 s)
    diff_ms * (1 ms)

  -> .__floor_div(a, b) (i64 i64) i64
    q = (a / b) ## i64
    r = (a % b) ## i64
    if r != 0 && ((a < 0 && b > 0) || (a > 0 && b < 0))
      return q - 1
    q

  -> .__month_length(y, m) (i64 i64) i64
    if m == 2
      leap = (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)
      if leap
        return 29
      return 28
    if m == 4 || m == 6 || m == 9 || m == 11
      return 30
    31

  # [year, month, day, hour, minute, second, millisecond]
  -> .__civil_sod(ms) (i64)
    days = Instant.__floor_div(ms, 86_400_000)
    sod = (ms - days * 86_400_000) ## i64
    hour = (sod / 3_600_000) ## i64
    rem = (sod % 3_600_000) ## i64
    minute = (rem / 60_000) ## i64
    rem = (rem % 60_000) ## i64
    second = (rem / 1_000) ## i64
    frac = (rem % 1_000) ## i64
    ymd = Instant.__days_to_civil(days)
    [ymd[0], ymd[1], ymd[2], hour, minute, second, frac]

  # Howard Hinnant civil_from_days, proleptic Gregorian, epoch 1970-01-01.
  -> .__days_to_civil(days) (i64)
    z = (days + 719_468) ## i64
    era = Instant.__floor_div(z, 146_097)
    doe = (z - era * 146_097) ## i64
    yoe = ((doe - doe / 1460 + doe / 36524 - doe / 146096) / 365) ## i64
    y = (yoe + era * 400) ## i64
    doy = (doe - (365 * yoe + yoe / 4 - yoe / 100)) ## i64
    mp = ((5 * doy + 2) / 153) ## i64
    d = (doy - (153 * mp + 2) / 5 + 1) ## i64
    m = mp + 3
    if mp >= 10
      m = mp - 9
      y = y + 1
    [y, m, d]

  -> .__civil_to_days(y, m, d) (i64 i64 i64) i64
    yy = y ## i64
    if m <= 2
      yy = yy - 1
    era = Instant.__floor_div(yy, 400)
    yoe = (yy - era * 400) ## i64
    madj = m + 9
    if m > 2
      madj = m - 3
    doy = ((153 * madj + 2) / 5 + d - 1) ## i64
    doe = (yoe * 365 + yoe / 4 - yoe / 100 + doy) ## i64
    (era * 146_097 + doe - 719_468) ## i64

  -> .__pad(n, width) (i64 i64) string
    s = n.to_s()
    while s.size() < width
      s = "0" + s
    s
