# Time — time-of-day value (no date component).
#
# Source syntax: `12:30:45`, `12:30:45.123`, `12:30:00Z`, `14:30:45+01:00`.
# The literal needs seconds, so it stays distinct from a hash pair.
# A bare clock is naive (TZ_NAIVE). `Z` and a numeric offset make it aware.
# `Time.parse` also accepts `09:30` and `12:30+05:30`.
# The offset is seconds east of UTC. Arithmetic wraps at 24h and ignores
# nominal months. Second 60 is accepted only as 23:59:60.
+ Time
  is Comparable
  is BitOrdered

  SECONDS_PER_DAY = 86_400
  NANOS_PER_SECOND = 1_000_000_000
  NANOS_PER_DAY = 86_400_000_000_000
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

  ro :nanos, :tz_offset

  -> new(@nanos = 0, @tz_offset = -1)

  -> tz_offset
    @tz_offset

  -> .SECONDS_PER_DAY
    86_400

  -> .NANOS_PER_SECOND
    1_000_000_000

  -> .NANOS_PER_DAY
    86_400_000_000_000

  -> .TZ_NAIVE
    -1

  -> .ISO8601_FORMAT
    "%H:%M:%S"

  -> .ISO8601_TZ_FORMAT
    "%H:%M:%S%:z"

  -> .RFC3339_FORMAT
    "%H:%M:%S%:z"

  -> .SHORT_FORMAT
    "%H:%M"

  -> .TWELVE_FORMAT
    "%I:%M %p"

  -> .TWELVE_SEC_FORMAT
    "%I:%M:%S %p"

  -> .parse(string)
    text = string.to_s().strip()
    tz = -1
    body = text
    if text.ends_with?("Z") || text.ends_with?("z")
      tz = 0
      body = text.slice(0, text.size() - 1)
    else
      sign_at = Time.__tz_sign_at(text)
      if sign_at != nil
        tz = Time.__offset_seconds(text.slice(sign_at, text.size() - sign_at))
        body = text.slice(0, sign_at)
    parts = body.split(":")
    if parts.size() < 2
      raise "Time.parse: expected hh:mm[:ss], got [text]"
    hour = parts[0].to_i()
    minute = parts[1].to_i()
    second = 0
    fraction = 0
    if parts.size() > 2
      sec = parts[2]
      dot = sec.index(".")
      if dot != nil
        fraction = Time.__fraction_nanos(sec.slice(dot + 1, sec.size() - dot - 1))
        sec = sec.slice(0, dot)
      second = sec.to_i()
    Time.of(hour, minute, second, fraction, tz)

  -> .now
    ms = Instant.now.millis
    sod = ms % 86_400_000
    if sod < 0
      sod = sod + 86_400_000
    sec = sod / 1_000
    frac = (sod % 1_000) * 1_000_000
    Time.of(sec / 3_600, (sec % 3_600) / 60, sec % 60, frac, 0)

  -> .midnight
    Time.new(0, -1)

  -> .noon
    Time.new(12 * 3_600 * 1_000_000_000, -1)

  # `fraction` is nanoseconds past the whole second, 0..999_999_999.
  # `tz` is seconds east of UTC, or TZ_NAIVE.
  -> .of(hour, minute, second = 0, fraction = 0, tz = -1)
    if hour < 0 || hour > 23
      raise "Time hour out of range"
    if minute < 0 || minute > 59
      raise "Time minute out of range"
    if second < 0 || second > 60
      raise "Time second out of range"
    if second == 60 && (hour != 23 || minute != 59)
      raise "Second 60 is only valid as 23:59:60"
    if fraction < 0 || fraction >= 1_000_000_000
      raise "Time fraction out of range"
    if tz != -1 && (tz < -64_800 || tz > 64_800)
      raise "Time offset out of range"
    nanos = ((hour * 60 + minute) * 60 + second) * 1_000_000_000 + fraction
    Time.new(nanos, tz)

  -> nanoseconds
    @nanos

  -> naive?
    @tz_offset == -1

  -> aware?
    @tz_offset != -1

  -> hour
    if @nanos >= 86_400_000_000_000
      return 23
    @nanos / (3_600 * 1_000_000_000)

  -> minute
    if @nanos >= 86_400_000_000_000
      return 59
    (@nanos / (60 * 1_000_000_000)) % 60

  -> second
    if @nanos >= 86_400_000_000_000
      return 60
    (@nanos / 1_000_000_000) % 60

  -> fraction
    if @nanos >= 86_400_000_000_000
      return @nanos - 86_400_000_000_000
    @nanos % 1_000_000_000

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
    self.nanoseconds / 1_000_000_000

  # Replace the offset tag. The clock digits stay put.
  -> with_tz(offset)
    off = offset
    if offset == :utc
      off = 0
    Time.new(@nanos, off)

  # Move the clock from the current offset into `offset`. A naive Time
  # has no origin, so this only attaches the tag.
  -> in_zone(offset)
    off = offset
    if offset == :utc
      off = 0
    if naive?
      return Time.new(@nanos, off)
    Time.new(Time.__wrap(@nanos + (off - @tz_offset) * 1_000_000_000), off)

  -> to_utc
    if naive? || @tz_offset == 0
      return Time.new(@nanos, 0)
    Time.new(Time.__wrap(@nanos - @tz_offset * 1_000_000_000), 0)

  # Duration, time Quantity, or a number of seconds. Wraps modulo 24h.
  # Nominal months have no meaning on a clock face.
  -> +(other)
    Time.new(Time.__wrap(@nanos + Time.__delta_nanos(other)), @tz_offset)

  # Time - Time is a seconds Quantity. Anything else shifts the clock.
  -> -(other)
    if other.class_name == "Time"
      return Time.__seconds_quantity(@nanos - other.nanoseconds)
    Time.new(Time.__wrap(@nanos - Time.__delta_nanos(other)), @tz_offset)

  # Low 47 bits are nanoseconds since midnight. The offset, biased by
  # +1 so naive is 0, occupies the bits above that. Naive clocks therefore
  # order by time of day.
  -> wvalue_bits
    ns = @nanos ## i64
    tz = (@tz_offset + 1) ## i64
    mask = 140_737_488_355_327 ## i64
    ((tz << 47) | (ns & mask)) ## i64

  -> hash
    self.wvalue_bits

  -> ==(other)
    other.is_a?(Time) && @nanos == other.nanoseconds && @tz_offset == other.tz_offset

  -> <=>(other)
    return nil if !other.is_a?(Time)
    self.wvalue_bits <=> other.wvalue_bits

  -> business_hours?(start, ending)
    self >= start && self < ending

  -> between?(start, ending)
    self >= start && self <= ending

  -> to_s
    out = StringBuffer()
    Time.__append_2(out, self.hour)
    out << ":"
    Time.__append_2(out, self.minute)
    out << ":"
    Time.__append_2(out, self.second)
    frac = self.fraction
    if frac != 0
      out << "."
      Time.__append_frac(out, frac)
    if !naive?
      Time.__append_tz(out, @tz_offset)
    out.to_s()

  -> .__append_2(out, n)
    out << "0123456789"[n / 10]
    out << "0123456789"[n % 10]

  -> .__append_frac(out, frac)
    digits = 9
    while frac % 10 == 0
      frac = frac / 10
      digits = digits - 1
    div = 1
    k = 1
    while k < digits
      div = div * 10
      k += 1
    while digits > 0
      out << "0123456789"[frac / div]
      frac = frac % div
      div = div / 10
      digits = digits - 1

  -> .__append_tz(out, off)
    n = off
    if n < 0
      out << "-"
      n = 0 - n
    else
      out << "+"
    Time.__append_2(out, n / 3_600)
    out << ":"
    Time.__append_2(out, (n % 3_600) / 60)
    ss = n % 60
    if ss != 0
      out << ":"
      Time.__append_2(out, ss)

  -> iso8601
    self.strftime("%H:%M:%S")

  -> rfc3339
    self.strftime("%H:%M:%S%:z")

  -> inspect
    self.to_s

  # %H %k %I %l %M %S %L %N %p %P %z %:z %Z %% %n %t
  -> strftime(format)
    fmt = format.to_s()
    out = StringBuffer()
    i = 0
    n = fmt.size()
    while i < n
      c = fmt[i]
      if c != "%"
        out << c
        i += 1
      else
        i += 1
        colon = false
        if i < n && fmt[i] == ":"
          colon = true
          i += 1
        if i >= n
          out << "%"
        else
          out << self.__piece(fmt[i], colon)
          i += 1
    out.to_s()

  -> __piece(spec, colon)
    if spec == "H"
      return Time.__pad(self.hour, 2)
    if spec == "k"
      return Time.__pad_space(self.hour, 2)
    if spec == "I"
      return Time.__pad(self.hour_12, 2)
    if spec == "l"
      return Time.__pad_space(self.hour_12, 2)
    if spec == "M"
      return Time.__pad(self.minute, 2)
    if spec == "S"
      return Time.__pad(self.second, 2)
    if spec == "L"
      return Time.__pad(self.fraction / 1_000_000, 3)
    if spec == "N"
      return Time.__pad(self.fraction, 9)
    if spec == "p"
      if self.pm?
        return "PM"
      return "AM"
    if spec == "P"
      if self.pm?
        return "pm"
      return "am"
    if spec == "z"
      if naive?
        return ""
      return Time.__tz_suffix(@tz_offset, colon)
    if spec == "Z"
      if @tz_offset == 0
        return "UTC"
      return ""
    if spec == "%"
      return "%"
    if spec == "n"
      return "\n"
    if spec == "t"
      return "\t"
    "%" + spec

  -> .__wrap(ns) (i64) i64
    day = 86_400_000_000_000
    r = ns % day
    if r < 0
      r = r + day
    r

  -> .__delta_nanos(other)
    if other.is_a?(Int) || other.is_a?(Integer)
      return other * 1_000_000_000
    kind = other.class_name
    if kind == "Duration"
      return Time.__duration_nanos(other$value ## i64)
    if kind == "Quantity"
      return Time.__quantity_nanos(other)
    if kind == "Time"
      raise "add Time with -, which returns the clock difference"
    raise "cannot shift a Time by [kind]"

  # Packed duration word. Nominal months are not a clock-face shift.
  -> .__duration_nanos(bits) (i64) i64
    tag = ((bits >> 48) ## i64) & 65_535
    if tag != 65_535
      raise "Time cannot shift by a heap duration"
    mode = ((bits >> 47) ## i64) & 1
    if mode == 0
      return ((bits << 17) ## i64) >> 17
    months = ((bits >> 32) & 32_767) ## i64
    if months >= 16_384
      months = months - 32_768
    if months != 0
      raise "cannot add a Duration with nominal months to a Time"
    ms = (bits & 4_294_967_295) ## i64
    ms * 1_000_000

  -> .__quantity_nanos(q)
    factor = Time.__unit_nanos(q.unit_name)
    if factor < 0
      raise "cannot shift a Time by [q.unit_name]"
    b = q.value$value ## i64
    sig = ((b >> 7) & 549_755_813_887) ## i64
    if sig >= 274_877_906_944
      sig = sig - 549_755_813_888
    scale = (b & 127) ## i64
    if scale >= 64
      scale = scale - 128
    Time.__scaled(sig, scale, factor)

  -> .__unit_nanos(name)
    if name == "ns"
      return 1
    if name == "us" || name == "µs"
      return 1_000
    if name == "ms"
      return 1_000_000
    if name == "s"
      return 1_000_000_000
    if name == "min"
      return 60 * 1_000_000_000
    if name == "h"
      return 3_600 * 1_000_000_000
    if name == "d"
      return 86_400_000_000_000
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

  -> .__seconds_quantity(diff_ns) (i64)
    if diff_ns % 1_000_000_000 == 0
      return (diff_ns / 1_000_000_000) * (1 s)
    diff_ns * (1 ns)

  -> .__tz_sign_at(text)
    i = text.size() - 1
    while i > 2
      c = text[i]
      if c == "+" || c == "-"
        return i
      i -= 1
    nil

  -> .__offset_seconds(text)
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
    secs = 0
    if parts.size() > 1
      mins = parts[1].to_i()
    if parts.size() > 2
      secs = parts[2].to_i()
    sign * (hours * 3_600 + mins * 60 + secs)

  -> .__fraction_nanos(digits)
    if digits.size() == 0
      return 0
    padded = digits
    if padded.size() > 9
      padded = padded.slice(0, 9)
    while padded.size() < 9
      padded = padded + "0"
    padded.to_i()

  -> .__trim_frac(frac) (i64) string
    text = Time.__pad(frac, 9)
    while text.size() > 1 && text.ends_with?("0")
      text = text.slice(0, text.size() - 1)
    text

  -> .__tz_suffix(off, colon)
    sign = "+"
    n = off
    if n < 0
      sign = "-"
      n = 0 - n
    hh = Time.__pad(n / 3_600, 2)
    mm = Time.__pad((n % 3_600) / 60, 2)
    ss = n % 60
    if colon
      if ss != 0
        return sign + hh + ":" + mm + ":" + Time.__pad(ss, 2)
      return sign + hh + ":" + mm
    if ss != 0
      return sign + hh + mm + Time.__pad(ss, 2)
    sign + hh + mm

  -> .__pad(n, width) (i64 i64) string
    s = n.to_s()
    while s.size() < width
      s = "0" + s
    s

  -> .__pad_space(n, width) (i64 i64) string
    s = n.to_s()
    while s.size() < width
      s = " " + s
    s
