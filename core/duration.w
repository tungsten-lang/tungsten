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
  -> .parse(string)
    s = ("" + string).strip
    if s.starts_with?("P") || s.starts_with?("p") || s.starts_with?("-P") || s.starts_with?("+P")
      return Duration.parse_iso(s)
    Duration.parse_compact(s)

  -> .parse_compact(string)
    raw = ("" + string).strip
    total_months = 0
    total_ms = 0
    total_ns = 0
    has_calendar = false
    has_ns = false
    pos = 0
    chars = raw.chars
    while pos < chars.size
      num_str = ""
      while pos < chars.size && chars[pos] >= "0" && chars[pos] <= "9"
        num_str = num_str + chars[pos]
        pos += 1
      num = num_str.to_i
      if pos + 1 < chars.size && chars[pos] == "m" && chars[pos + 1] == "o"
        total_months += num
        has_calendar = true
        pos += 2
      elsif pos + 1 < chars.size && chars[pos] == "m" && chars[pos + 1] == "s"
        total_ms += num
        pos += 2
      elsif pos + 1 < chars.size && chars[pos] == "n" && chars[pos + 1] == "s"
        total_ns += num
        has_ns = true
        pos += 2
      elsif pos < chars.size && chars[pos] == "y"
        total_months += num * 12
        has_calendar = true
        pos += 1
      elsif pos < chars.size && chars[pos] == "w"
        total_ms += num * 604_800_000
        pos += 1
      elsif pos < chars.size && chars[pos] == "d"
        total_ms += num * 86_400_000
        pos += 1
      elsif pos < chars.size && chars[pos] == "h"
        total_ms += num * 3_600_000
        pos += 1
      elsif pos < chars.size && chars[pos] == "m"
        total_ms += num * 60_000
        pos += 1
      elsif pos < chars.size && chars[pos] == "s"
        total_ms += num * 1_000
        pos += 1
      else
        raise "Invalid duration unit at position [pos] in '[raw]'"
    if has_calendar || (!has_ns && total_ms > 0)
      return Duration.__from_months_ms(total_months, total_ms)
    if has_ns || total_ns > 0
      return Duration.__scale_unit(1ns, total_ns + total_ms * 1_000_000, 0ns)
    Duration.__from_months_ms(0, total_ms)

  -> .parse_iso(string)
    raw = ("" + string).strip
    raise "Invalid ISO 8601 duration: '[raw]'" if !raw.starts_with?("P") && !raw.starts_with?("p")
    pos = 1
    in_time = false
    total_months = 0
    total_ms = 0
    chars = raw.chars
    while pos < chars.size
      if chars[pos] == "T" || chars[pos] == "t"
        in_time = true
        pos += 1
        next
      num_str = ""
      while pos < chars.size && chars[pos] >= "0" && chars[pos] <= "9"
        num_str = num_str + chars[pos]
        pos += 1
      num = num_str.to_i
      raise "Invalid ISO 8601 duration: '[raw]'" if pos >= chars.size
      u = chars[pos]
      pos += 1
      if !in_time
        if u == "Y" || u == "y"
          total_months += num * 12
        elsif u == "M" || u == "m"
          total_months += num
        elsif u == "W" || u == "w"
          total_ms += num * 604_800_000
        elsif u == "D" || u == "d"
          total_ms += num * 86_400_000
        else
          raise "Invalid ISO 8601 date unit '[u]' in '[raw]'"
      else
        if u == "H" || u == "h"
          total_ms += num * 3_600_000
        elsif u == "M" || u == "m"
          total_ms += num * 60_000
        elsif u == "S" || u == "s"
          total_ms += num * 1_000
        else
          raise "Invalid ISO 8601 time unit '[u]' in '[raw]'"
    Duration.__from_months_ms(total_months, total_ms)

  -> .of_months(months)
    Duration.__from_months_ms(months.to_i, 0)

  -> .of_seconds(seconds)
    Duration.__from_months_ms(0, (seconds * 1_000).to_i)

  -> .zero
    0h0m

  -> .__scale_unit(unit, n, zero_val)
    rem = n.to_i
    return zero_val if rem <= 0
    acc = zero_val
    cur = unit
    while rem > 0
      if (rem & 1) != 0
        acc = acc + cur
      rem = rem >> 1
      if rem > 0
        cur = cur + cur
    acc

  -> .__from_months_ms(months, ms)
    m = months.to_i
    millis = ms.to_i
    if m == 0 && millis == 0
      return 0h0m
    res = 0h0m
    if m > 0
      res = res + Duration.__scale_unit(1mo, m, 0mo)
    elsif m < 0
      res = res - Duration.__scale_unit(1mo, 0 - m, 0mo)
    if millis > 0
      res = res + Duration.__scale_unit(1ms, millis, 0ms)
    res

  # ---- accessors ----
  -> .__split_components(s)
    raw = ("" + s).strip
    neg = false
    if raw.starts_with?("-")
      neg = true
      raw = raw.slice(1, raw.size - 1)
    total_months = 0
    total_ms = 0
    pos = 0
    chars = raw.chars
    while pos < chars.size
      num_str = ""
      while pos < chars.size && ((chars[pos] >= "0" && chars[pos] <= "9") || chars[pos] == ".")
        num_str = num_str + chars[pos]
        pos += 1
      num = num_str.include?(".") ? (num_str.to_f * 1_000).to_i : num_str.to_i
      is_frac = num_str.include?(".")
      if pos + 1 < chars.size && chars[pos] == "m" && chars[pos + 1] == "o"
        total_months += num
        pos += 2
      elsif pos + 1 < chars.size && chars[pos] == "m" && chars[pos + 1] == "s"
        total_ms += num
        pos += 2
      elsif pos + 1 < chars.size && chars[pos] == "n" && chars[pos + 1] == "s"
        pos += 2
      elsif pos < chars.size && chars[pos] == "y"
        total_months += num * 12
        pos += 1
      elsif pos < chars.size && chars[pos] == "w"
        total_ms += is_frac ? num * 604_800 : num * 604_800_000
        pos += 1
      elsif pos < chars.size && chars[pos] == "d"
        total_ms += is_frac ? num * 86_400 : num * 86_400_000
        pos += 1
      elsif pos < chars.size && chars[pos] == "h"
        total_ms += is_frac ? num * 3_600 : num * 3_600_000
        pos += 1
      elsif pos < chars.size && chars[pos] == "m"
        total_ms += is_frac ? num * 60 : num * 60_000
        pos += 1
      elsif pos < chars.size && chars[pos] == "s"
        total_ms += is_frac ? num : num * 1_000
        pos += 1
      else
        pos += 1
    if neg
      return [0 - total_months, 0 - total_ms]
    [total_months, total_ms]

  -> months
    Duration.__split_components(self.to_s)[0]

  -> seconds
    ms = Duration.__split_components(self.to_s)[1]
    ms % 1_000 == 0 ? (ms / 1_000) : Rational.new(ms, 1_000)

  -> total_months
    self.months

  -> total_seconds
    self.seconds

  -> calendar?
    self.months != 0

  -> fixed?
    self.months == 0

  # ---- arithmetic ----
  -> +(other)
  -> -(other)

  -> apply_months(date)
    m = self.months
    return date if m == 0
    total = date.year * 12 + (date.month - 1) + m
    ny = total / 12
    rem = total - ny * 12
    if rem < 0
      ny -= 1
      rem += 12
    nm = rem + 1
    probe = Date.new(ny, nm, 1)
    dim = probe.days_in_month
    nd = date.day > dim ? dim : date.day
    Date.new(ny, nm, nd, date.hour, date.minute, date.second, date.tz)

  # ---- comparison ----
  -> <=>(other)
  -> ==(other)
  -> hash

  # ---- formatting ----
  -> to_s
  -> iso8601
    parts = Duration.__split_components(self.to_s)
    m = parts[0]
    ms = parts[1]
    out = "P"
    if m > 0
      yrs = m / 12
      mos = m % 12
      out = out + "[yrs]Y" if yrs > 0
      out = out + "[mos]M" if mos > 0
    sec = ms / 1_000
    days = sec / 86_400
    rem = sec % 86_400
    out = out + "[days]D" if days > 0
    if rem > 0 || (m == 0 && days == 0)
      out = out + "T"
      hrs = rem / 3_600
      mins = (rem % 3_600) / 60
      secs = rem % 60
      out = out + "[hrs]H" if hrs > 0
      out = out + "[mins]M" if mins > 0
      out = out + "[secs]S" if secs > 0 || (hrs == 0 && mins == 0)
    out

  -> inspect
    self.to_s
