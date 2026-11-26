# runtime/b_temporal_core — TC39 Temporal Core Infrastructure:
# Exact arbitrary-precision nanosecond & rounding arithmetic, ISO 8601 proleptic Gregorian math,
# strict RFC 9557 / Temporal ISO 8601 parser & serializer, IANA/offset TimeZone engine (via ICU 78),
# and ECMA-262 Temporal option/unit validation helpers.

in JS

# ---- Exact BigInt Nanosecond & Limit Constants ----

TM_NS_US   = 1000 ## int
TM_NS_MS   = 1000000 ## int
TM_NS_SEC  = 1000000000 ## int
TM_NS_MIN  = 60000000000 ## int
TM_NS_HOUR = 3600000000000 ## int
TM_NS_DAY  = 86400000000000 ## int

TM_MAX_EPOCH_NS = 8640000000000000000000 ## int
TM_MIN_EPOCH_NS = -8640000000000000000000 ## int
TM_MAX_ISO_NS   = TM_MAX_EPOCH_NS + TM_NS_DAY
TM_MIN_ISO_NS   = TM_MIN_EPOCH_NS - TM_NS_DAY
TM_MAX_TIME_NS  = (9007199254740992 ## int) * (1000000000 ## int)

# ---- Exact Arbitrary-Precision Integer & Rounding Helpers ----

-> tm_abs_i(a)
  a < (0 ## int) ? ((0 ## int) - a) : a

-> tm_sgn_i(a)
  return 1 if a > (0 ## int)
  return -1 if a < (0 ## int)
  0

-> tm_floor_div(a, b)
  # Assumes b > 0
  q = a / b
  r = a % b
  r < (0 ## int) ? (q - (1 ## int)) : q

-> tm_floor_mod(a, b)
  # Assumes b > 0
  r = a % b
  r < (0 ## int) ? (r + b) : r

# Exact integer division rounding num / den (den > 0) under all 9 TC39 Temporal rounding modes!
-> tm_round_div(num, den, mode)
  # Exact quotient toward zero (trunc) and remainder r with same sign as num
  q = num / den
  r = num % den
  return q if r == (0 ## int)
  neg = num < (0 ## int)
  ar = neg ? ((0 ## int) - r) : r
  # Half comparison: 2 * |r| vs den
  r2 = ar + ar
  if mode == "trunc"
    return q
  elsif mode == "expand"
    return neg ? (q - (1 ## int)) : (q + (1 ## int))
  elsif mode == "floor"
    return neg ? (q - (1 ## int)) : q
  elsif mode == "ceil"
    return neg ? q : (q + (1 ## int))
  elsif mode == "halfExpand"
    if r2 >= den
      return neg ? (q - (1 ## int)) : (q + (1 ## int))
    return q
  elsif mode == "halfTrunc"
    if r2 > den
      return neg ? (q - (1 ## int)) : (q + (1 ## int))
    return q
  elsif mode == "halfCeil"
    if r2 > den
      return neg ? (q - (1 ## int)) : (q + (1 ## int))
    elsif r2 == den
      return neg ? q : (q + (1 ## int))
    return q
  elsif mode == "halfFloor"
    if r2 > den
      return neg ? (q - (1 ## int)) : (q + (1 ## int))
    elsif r2 == den
      return neg ? (q - (1 ## int)) : q
    return q
  elsif mode == "halfEven"
    if r2 > den
      return neg ? (q - (1 ## int)) : (q + (1 ## int))
    elsif r2 == den
      even = (q % (2 ## int)) == (0 ## int)
      return q if even
      return neg ? (q - (1 ## int)) : (q + (1 ## int))
    return q
  q

-> tm_round_to_inc(val, inc, mode)
  tm_round_div(val, inc, mode) * inc

# Unsigned rounding (for Temporal.Instant timestamps: trunc/expand are relative to Big Bang -Infinity, NOT 1970 epoch!)
-> tm_round_unsigned_to_inc(val, inc, mode)
  umode = mode
  if mode == "trunc"
    umode = "floor"
  elsif mode == "expand"
    umode = "ceil"
  elsif mode == "halfTrunc"
    umode = "halfFloor"
  elsif mode == "halfExpand"
    umode = "halfCeil"
  tm_round_div(val, inc, umode) * inc

# ToPrimitiveAndRequireString ( argument ) — throws TypeError if primitive is not a String!
-> tm_to_prim_require_str(v)
  return v if js_string?(v)
  prim = js_to_primitive(v, "string")
  return prim if js_string?(prim)
  js_throw_type("Expected a string value")

# Negate a rounding mode (NegateRoundingMode)
-> tm_negate_rmode(mode)
  return "floor" if mode == "ceil"
  return "ceil" if mode == "floor"
  return "halfFloor" if mode == "halfCeil"
  return "halfCeil" if mode == "halfFloor"
  mode

# Safe float from BigInt (exact up to 2^53, avoids -0)
-> tm_int_to_num(v)
  return ~0.0 if v == (0 ## int)
  if v >= (-9007199254740991 ## int) && v <= (9007199254740991 ## int)
    return v.to_i + ~0.0
  # Convert via string for huge values
  js_to_number(js_bigint_to_string(JS:BigIntValue.new(v), nil))

# Exact IEEE-754 float64 of rational num / den (## int / ## int), single rounding to nearest even!
-> tm_bit_len(n)
  return 0 if n <= (0 ## int)
  # Fast bit length via binary search / halving by 32-bit chunks
  bits = 0
  x = n
  p32 = 4294967296 ## int
  while x >= p32
    x = x / p32
    bits += 32
  xi = x.to_i
  while xi > 0
    xi = xi >> 1
    bits += 1
  bits

-> tm_pow2_i(k)
  return (1 ## int) if k <= 0
  r = 1 ## int
  b = 2 ## int
  e = k
  while e > 0
    r = r * b if (e & 1) != 0
    b = b * b
    e = e >> 1
  r

-> tm_scale_pow2_f(val, exp)
  x = val
  e = exp
  while e > 0
    if e >= 32
      x = x * ~4294967296.0
      e -= 32
    else
      x = x * ~2.0
      e -= 1
  while e < 0
    if e <= -32
      x = x / ~4294967296.0
      e += 32
    else
      x = x * ~0.5
      e += 1
  x

-> tm_exact_div_to_num(num, den)
  return ~0.0 if num == (0 ## int)
  neg = (num < (0 ## int)) != (den < (0 ## int))
  a = tm_abs_i(num)
  b = tm_abs_i(den)
  la = tm_bit_len(a)
  lb = tm_bit_len(b)
  # Want 2^52 <= (a * 2^shift) / b < 2^53
  shift = 53 - (la - lb)
  n = shift >= 0 ? (a * tm_pow2_i(shift)) : a
  d = shift >= 0 ? b : (b * tm_pow2_i(0 - shift))
  p52 = 4503599627370496 ## int
  p53 = 9007199254740992 ## int
  while n < p52 * d
    n = n * (2 ## int)
    shift += 1
  while n >= p53 * d
    d = d * (2 ## int)
    shift -= 1
  q = n / d
  r = n % d
  r2 = r * (2 ## int)
  if r2 > d || (r2 == d && (q % (2 ## int)) != (0 ## int))
    q = q + (1 ## int)
    if q == p53
      q = p52
      shift -= 1
  val = tm_scale_pow2_f(q.to_i + ~0.0, 0 - shift)
  neg ? (~0.0 - val) : val

# ToIntegerWithTruncation ( argument ) — returns ## int
-> tm_to_int_trunc(v)
  js_throw_type("Cannot convert BigInt or Symbol to integer") if v.is_a?(JS:BigIntValue) || v.is_a?(JS:Symbol)
  n = js_to_number(v)
  js_throw_range("Expected finite number") if !js_finite?(n)
  t = js_math_trunc(n)
  return 0 ## int if t == ~0.0
  js_bi_from_num(t).v

# ToPositiveIntegerWithTruncation ( argument ) — returns ## int >= 1
-> tm_to_pos_int_trunc(v)
  iv = tm_to_int_trunc(v)
  js_throw_range("Expected positive integer") if iv <= (0 ## int)
  iv

# ToIntegerIfIntegral ( argument ) — returns ## int
-> tm_to_int_integral(v)
  js_throw_type("Cannot convert BigInt or Symbol to integer") if v.is_a?(JS:BigIntValue) || v.is_a?(JS:Symbol)
  n = js_to_number(v)
  js_throw_range("Expected integral finite number") if !js_finite?(n) || js_math_trunc(n) != n
  return 0 ## int if n == ~0.0
  js_bi_from_num(n).v

# ---- Exact ISO 8601 Proleptic Gregorian Calendar Math ----

-> tm_iso_leap?(y)
  (tm_floor_mod(y ## int, 4 ## int) == (0 ## int)) &&
    (tm_floor_mod(y ## int, 100 ## int) != (0 ## int) || tm_floor_mod(y ## int, 400 ## int) == (0 ## int))

TM_ISO_MDAYS = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

-> tm_iso_days_in_month(y, m)
  return 29 if m == 2 && tm_iso_leap?(y)
  TM_ISO_MDAYS[m]

-> tm_iso_days_in_year(y)
  tm_iso_leap?(y) ? 366 : 365

# Howard Hinnant exact civil date -> days since 1970-01-01 (returns ## int)
-> tm_epoch_days(y, m, d)
  yi = y ## int
  mi = m ## int
  di = d ## int
  yi = yi - (1 ## int) if mi <= (2 ## int)
  era = tm_floor_div(yi, 400 ## int)
  yoe = yi - era * (400 ## int)
  mp = mi > (2 ## int) ? (mi - (3 ## int)) : (mi + (9 ## int))
  doy = ((153 ## int) * mp + (2 ## int)) / (5 ## int) + di - (1 ## int)
  doe = yoe * (365 ## int) + yoe / (4 ## int) - yoe / (100 ## int) + doy
  era * (146097 ## int) + doe - (719468 ## int)

# Howard Hinnant exact days since 1970-01-01 -> [y, m, d] (all Int)
-> tm_ymd_from_days(z)
  zi = (z ## int) + (719468 ## int)
  era = tm_floor_div(zi, 146097 ## int)
  doe = zi - era * (146097 ## int)
  yoe = (doe - doe / (1460 ## int) + doe / (36524 ## int) - doe / (146096 ## int)) / (365 ## int)
  y = yoe + era * (400 ## int)
  doy = doe - ((365 ## int) * yoe + yoe / (4 ## int) - yoe / (100 ## int))
  mp = ((5 ## int) * doy + (2 ## int)) / (153 ## int)
  d = doy - ((153 ## int) * mp + (2 ## int)) / (5 ## int) + (1 ## int)
  m = mp < (10 ## int) ? (mp + (3 ## int)) : (mp - (9 ## int))
  y = y + (1 ## int) if m <= (2 ## int)
  [y.to_i, m.to_i, d.to_i]

# ISO DayOfWeek: 1 = Monday .. 7 = Sunday
-> tm_iso_dow(y, m, d)
  # 1970-01-01 was Thursday (4)
  (tm_floor_mod(tm_epoch_days(y, m, d) + (3 ## int), 7 ## int)).to_i + 1

# ISO DayOfYear: 1..366
-> tm_iso_doy(y, m, d)
  (tm_epoch_days(y, m, d) - tm_epoch_days(y, 1, 1)).to_i + 1

# ISO WeekOfYear & YearOfWeek -> [week, year_of_week]
-> tm_iso_week_info(y, m, d)
  doy = tm_iso_doy(y, m, d)
  dow = tm_iso_dow(y, m, d)
  # Thursday of the same ISO week determines the week-year
  w = (doy - dow + 10) / 7
  if w < 1
    # Belongs to last week of y - 1
    py = y - 1
    pw = tm_iso_weeks_in_year(py)
    return [pw, py]
  wy = tm_iso_weeks_in_year(y)
  if w > wy
    return [1, y + 1]
  [w, y]

-> tm_iso_weeks_in_year(y)
  # A year has 53 ISO weeks iff Jan 1 is Thursday (4) or leap year starting Wednesday (3)
  jan1 = tm_iso_dow(y, 1, 1)
  (jan1 == 4 || (jan1 == 3 && tm_iso_leap?(y))) ? 53 : 52

-> tm_iso_date_valid?(y, m, d)
  return false if m < 1 || m > 12 || d < 1
  d <= tm_iso_days_in_month(y, m)

-> tm_time_valid?(h, mi, s, ms, us, ns)
  h >= 0 && h <= 23 && mi >= 0 && mi <= 59 && s >= 0 && s <= 59 &&
    ms >= 0 && ms <= 999 && us >= 0 && us <= 999 && ns >= 0 && ns <= 999

-> tm_constrain_time(h, mi, s, ms, us, ns, overflow)
  if overflow == "reject"
    js_throw_range("Time field out of range") if !tm_time_valid?(h, mi, s, ms, us, ns)
    return [h, mi, s, ms, us, ns]
  # Constrain: negative values STILL throw RangeError!
  js_throw_range("Negative time field") if h < 0 || mi < 0 || s < 0 || ms < 0 || us < 0 || ns < 0
  [
    h > 23 ? 23 : h,
    mi > 59 ? 59 : mi,
    s > 59 ? 59 : s,
    ms > 999 ? 999 : ms,
    us > 999 ? 999 : us,
    ns > 999 ? 999 : ns
  ]

-> tm_constrain_iso_date(y, m, d, overflow)
  if overflow == "reject"
    js_throw_range("ISO date out of range") if !tm_iso_date_valid?(y, m, d)
    return [y, m, d]
  js_throw_range("Invalid month or day") if m < 1 || d < 1
  m = 12 if m > 12
  dm = tm_iso_days_in_month(y, m)
  d = dm if d > dm
  [y, m, d]

-> tm_iso_epoch_ns(y, m, d, h, mi, s, ms, us, ns)
  days = tm_epoch_days(y, m, d)
  t = (h ## int) * TM_NS_HOUR + (mi ## int) * TM_NS_MIN + (s ## int) * TM_NS_SEC +
      (ms ## int) * TM_NS_MS + (us ## int) * TM_NS_US + (ns ## int)
  days * TM_NS_DAY + t

-> tm_iso_dt_from_epoch_ns(epoch_ns)
  days = tm_floor_div(epoch_ns, TM_NS_DAY)
  rem = epoch_ns - days * TM_NS_DAY
  ymd = tm_ymd_from_days(days)
  h = (rem / TM_NS_HOUR).to_i
  rem = rem % TM_NS_HOUR
  mi = (rem / TM_NS_MIN).to_i
  rem = rem % TM_NS_MIN
  s = (rem / TM_NS_SEC).to_i
  rem = rem % TM_NS_SEC
  ms = (rem / TM_NS_MS).to_i
  rem = rem % TM_NS_MS
  us = (rem / TM_NS_US).to_i
  ns = (rem % TM_NS_US).to_i
  [ymd[0], ymd[1], ymd[2], h, mi, s, ms, us, ns]

# ISODateTimeWithinLimits ( exact spec check: strictly within [-8.64e21 - 8.64e13, +8.64e21 + 8.64e13] )
-> tm_iso_dt_within_limits?(y, m, d, h, mi, s, ms, us, ns)
  return false if y < -271821 || y > 275760
  ns_v = tm_iso_epoch_ns(y, m, d, h, mi, s, ms, us, ns)
  ns_v > TM_MIN_ISO_NS && ns_v < TM_MAX_ISO_NS

-> tm_iso_date_within_limits?(y, m, d)
  tm_iso_dt_within_limits?(y, m, d, 12, 0, 0, 0, 0, 0)

-> tm_iso_ym_within_limits?(y, m)
  return false if y < -271821 || y > 275760
  return false if y == -271821 && m < 4
  return false if y == 275760 && m > 9
  true

-> tm_epoch_ns_valid?(ns)
  ns >= TM_MIN_EPOCH_NS && ns <= TM_MAX_EPOCH_NS

# BalanceTime -> [delta_days(## int), h, mi, s, ms, us, ns]
-> tm_balance_time(h, mi, s, ms, us, ns)
  tot = (h ## int) * TM_NS_HOUR + (mi ## int) * TM_NS_MIN + (s ## int) * TM_NS_SEC +
        (ms ## int) * TM_NS_MS + (us ## int) * TM_NS_US + (ns ## int)
  days = tm_floor_div(tot, TM_NS_DAY)
  rem = tot - days * TM_NS_DAY
  oh = (rem / TM_NS_HOUR).to_i
  rem = rem % TM_NS_HOUR
  omi = (rem / TM_NS_MIN).to_i
  rem = rem % TM_NS_MIN
  os = (rem / TM_NS_SEC).to_i
  rem = rem % TM_NS_SEC
  oms = (rem / TM_NS_MS).to_i
  rem = rem % TM_NS_MS
  ous = (rem / TM_NS_US).to_i
  ons = (rem % TM_NS_US).to_i
  [days, oh, omi, os, oms, ous, ons]

# BalanceISODate ( y, m, d ) -> [y, m, d] (all ## int inputs ok, returns Int array)
-> tm_balance_iso_date(y, m, d)
  # Balance month into year first
  m0 = (m ## int) - (1 ## int)
  by = (y ## int) + tm_floor_div(m0, 12 ## int)
  bm = tm_floor_mod(m0, 12 ## int).to_i + 1
  ed = tm_epoch_days(by, bm, 1) + ((d ## int) - (1 ## int))
  tm_ymd_from_days(ed)

# AddISODate ( y, m, d, dy, dmo, dw, dd, overflow ) -> [y, m, d]
-> tm_add_iso_date(y, m, d, dy, dmo, dw, dd, overflow)
  # Add years and months, balance month, constrain/reject day, then add weeks*7 + days
  ny = (y ## int) + (dy ## int)
  nm0 = (m ## int) - (1 ## int) + (dmo ## int)
  by = ny + tm_floor_div(nm0, 12 ## int)
  bm = tm_floor_mod(nm0, 12 ## int).to_i + 1
  js_throw_range("Date out of range") if by < (-271825 ## int) || by > (275765 ## int)
  byi = by.to_i
  reg = tm_constrain_iso_date(byi, bm, d, overflow)
  total_d = (dw ## int) * (7 ## int) + (dd ## int)
  ed = tm_epoch_days(reg[0], reg[1], reg[2]) + total_d
  js_throw_range("Date out of range") if ed < (-100000005 ## int) || ed > (100000005 ## int)
  res = tm_ymd_from_days(ed)
  js_throw_range("Date out of range") if !tm_iso_date_within_limits?(res[0], res[1], res[2])
  res

# DifferenceISODate ( y1, m1, d1, y2, m2, d2, largest_unit ) -> [years, months, weeks, days] (all Int)
# Exact ECMA-262 Temporal §3.5.12 algorithm (never counts end-of-month clamping as a full month/year!)
-> tm_diff_iso_date(y1, m1, d1, y2, m2, d2, largest_unit)
  ed1 = tm_epoch_days(y1, m1, d1)
  ed2 = tm_epoch_days(y2, m2, d2)
  diff_d = (ed2 - ed1).to_i
  return [0, 0, 0, 0] if diff_d == 0
  return [0, 0, 0, diff_d] if largest_unit == "day"
  if largest_unit == "week"
    w = diff_d / 7
    r = diff_d - w * 7
    return [0, 0, w, r]
  sign = diff_d > 0 ? 1 : -1
  years = 0
  if largest_unit == "year"
    years = y2 - y1
    if sign > 0
      if m2 < m1 || (m2 == m1 && d2 < d1)
        years -= 1
    else
      if m2 > m1 || (m2 == m1 && d2 > d1)
        years += 1
  # Compute unclamped months from (y1 + years, m1, d1) to (y2, m2, d2)
  months = (y2 - (y1 + years)) * 12 + (m2 - m1)
  if sign > 0 && d2 < d1
    months -= 1
  elsif sign < 0 && d2 > d1
    months += 1
  # Compute remaining days from BalanceISODate(y1 + years, m1 + months, d1) (clamped) to (y2, m2, d2)
  bm0 = (y1 + years) * 12 + (m1 - 1) + months
  my = tm_floor_div(bm0 ## int, 12 ## int).to_i
  mm = tm_floor_mod(bm0 ## int, 12 ## int).to_i + 1
  dm = tm_iso_days_in_month(my, mm)
  md = d1 > dm ? dm : d1
  days = (ed2 - tm_epoch_days(my, mm, md)).to_i
  [years, months, 0, days]

# ---- ISO 8601 String Formatting Helpers ----

-> tm_pad2(n)
  n < 10 ? ("0" + n.to_s) : n.to_s

-> tm_pad3(n)
  return "00" + n.to_s if n < 10
  return "0" + n.to_s if n < 100
  n.to_s

-> tm_pad4(n)
  s = n.to_s
  while s.size < 4
    s = "0" + s
  s

-> tm_pad6(n)
  s = n.to_s
  while s.size < 6
    s = "0" + s
  s

-> tm_fmt_iso_year(y)
  return "-" + tm_pad6(-y) if y < 0
  return "+" + tm_pad6(y) if y > 9999
  tm_pad4(y)

-> tm_fmt_iso_date(y, m, d)
  tm_fmt_iso_year(y) + "-" + tm_pad2(m) + "-" + tm_pad2(d)

-> tm_fmt_subsec(ms, us, ns, prec)
  # prec: :auto or 0..9
  return "" if prec == 0
  tot = ms * 1000000 + us * 1000 + ns
  if prec == :auto
    return "" if tot == 0
    s = tm_pad3(ms) + tm_pad3(us) + tm_pad3(ns)
    e = s.size
    while e > 0 && s.byte_at(e - 1) == 48
      e -= 1
    return "." + s.slice(0, e)
  s = tm_pad3(ms) + tm_pad3(us) + tm_pad3(ns)
  "." + s.slice(0, prec)

-> tm_fmt_time(h, mi, s, ms, us, ns, prec)
  return tm_pad2(h) + ":" + tm_pad2(mi) if prec == :minute
  tm_pad2(h) + ":" + tm_pad2(mi) + ":" + tm_pad2(s) + tm_fmt_subsec(ms, us, ns, prec)

# Format a timezone offset in nanoseconds -> "±HH:MM" or "±HH:MM:SS[.fffffffff]"
-> tm_fmt_offset_ns(off_ns)
  sign = off_ns < (0 ## int) ? "-" : "+"
  a = tm_abs_i(off_ns)
  hh = (a / TM_NS_HOUR).to_i
  rem = a % TM_NS_HOUR
  mi = (rem / TM_NS_MIN).to_i
  rem = rem % TM_NS_MIN
  base = sign + tm_pad2(hh) + ":" + tm_pad2(mi)
  return base if rem == (0 ## int)
  sc = (rem / TM_NS_SEC).to_i
  rem = rem % TM_NS_SEC
  base = base + ":" + tm_pad2(sc)
  return base if rem == (0 ## int)
  ms = (rem / TM_NS_MS).to_i
  rem = rem % TM_NS_MS
  us = (rem / TM_NS_US).to_i
  ns = (rem % TM_NS_US).to_i
  base + tm_fmt_subsec(ms, us, ns, :auto)

-> tm_fmt_cal_ann(cal, show_cal)
  return "" if show_cal == "never"
  return "" if show_cal == "auto" && cal == "iso8601"
  return "\[!u-ca=" + cal + "]" if show_cal == "critical"
  "\[u-ca=" + cal + "]"

# ---- Strict RFC 9557 / Temporal ISO 8601 String Parser ----

-> tm_is_digit?(b)
  b >= 48 && b <= 57

-> tm_is_ascii_lower?(b)
  b >= 97 && b <= 122

-> tm_is_ascii_alpha?(b)
  (b >= 65 && b <= 90) || (b >= 97 && b <= 122)

# Parse ASCII '+' (43) or '-' (45) at index `i`. (Per final TC39 Temporal spec, U+2212 is NOT allowed!)
-> tm_parse_sign(s, i)
  return nil if i >= s.size
  c = s.byte_at(i)
  return [1, i + 1] if c == 43
  return [-1, i + 1] if c == 45
  nil

# Parse exact `k` ASCII digits at `i`. Returns [int_val, i + k] or nil.
-> tm_parse_digits(s, i, k)
  return nil if i + k > s.size
  v = 0
  j = 0
  while j < k
    b = s.byte_at(i + j)
    return nil if b < 48 || b > 57
    v = v * 10 + (b - 48)
    j += 1
  [v, i + k]

# Parse optional fractional digits ('.' or ',') 1..9 digits -> [ns_int_0_to_999999999, next_i] or [0, i] or nil (if malformed)
-> tm_parse_frac(s, i)
  return [0, i, false] if i >= s.size
  c = s.byte_at(i)
  return [0, i, false] if c != 46 && c != 44
  i += 1
  st = i
  while i < s.size && tm_is_digit?(s.byte_at(i))
    i += 1
  ln = i - st
  return nil if ln == 0 || ln > 9
  fstr = s.slice(st, ln)
  while fstr.size < 9
    fstr = fstr + "0"
  [fstr.to_i, i, true]

# Parse UTC Offset at `i`: ±HH | ±HHMM | ±HH:MM | ±HHMMSS[.frac] | ±HH:MM:SS[.frac]
# allow_submin: if false, reject seconds/fraction!
# Returns [offset_ns(## int), has_seconds_bool, next_i] or nil
-> tm_parse_utc_offset(s, i, allow_submin = true)
  sp = tm_parse_sign(s, i)
  return nil if sp == nil
  sgn = sp[0]
  j = sp[1]
  hp = tm_parse_digits(s, j, 2)
  return nil if hp == nil
  hh = hp[0]
  return nil if hh > 23
  j = hp[1]
  mi = 0
  sc = 0
  sub_ns = 0
  has_sec = false
  if j < s.size
    c = s.byte_at(j)
    if c == 58 # ':'
      j += 1
      mp = tm_parse_digits(s, j, 2)
      return nil if mp == nil
      mi = mp[0]
      return nil if mi > 59
      j = mp[1]
      if j < s.size && s.byte_at(j) == 58
        return nil if !allow_submin
        j += 1
        scp = tm_parse_digits(s, j, 2)
        return nil if scp == nil
        sc = scp[0]
        return nil if sc > 59
        j = scp[1]
        has_sec = true
        fp = tm_parse_frac(s, j)
        return nil if fp == nil
        sub_ns = fp[0]
        j = fp[1]
    elsif tm_is_digit?(c)
      mp = tm_parse_digits(s, j, 2)
      return nil if mp == nil
      mi = mp[0]
      return nil if mi > 59
      j = mp[1]
      if j < s.size && tm_is_digit?(s.byte_at(j))
        return nil if !allow_submin
        scp = tm_parse_digits(s, j, 2)
        return nil if scp == nil
        sc = scp[0]
        return nil if sc > 59
        j = scp[1]
        has_sec = true
        fp = tm_parse_frac(s, j)
        return nil if fp == nil
        sub_ns = fp[0]
        j = fp[1]
  tot = (hh ## int) * TM_NS_HOUR + (mi ## int) * TM_NS_MIN + (sc ## int) * TM_NS_SEC + (sub_ns ## int)
  tot = (0 ## int) - tot if sgn < 0
  [tot, has_sec, j]

# Parse TimeSpec at `i`: HH | HH:MM | HHMM | HH:MM:SS[.frac] | HHMMSS[.frac]
# Returns [h, mi, s, ms, us, ns, next_i, has_colon_or_len] or nil
-> tm_parse_time_spec(s, i, allow_hour_only = true)
  hp = tm_parse_digits(s, i, 2)
  return nil if hp == nil
  h = hp[0]
  return nil if h > 23
  j = hp[1]
  mi = 0
  sc = 0
  sub_ns = 0
  extended = false
  has_min = false
  if j < s.size && s.byte_at(j) == 58
    extended = true
    j += 1
    mp = tm_parse_digits(s, j, 2)
    return nil if mp == nil
    mi = mp[0]
    return nil if mi > 59
    j = mp[1]
    has_min = true
    if j < s.size && s.byte_at(j) == 58
      j += 1
      sp = tm_parse_digits(s, j, 2)
      return nil if sp == nil
      sc = sp[0]
      return nil if sc > 60
      sc = 59 if sc == 60
      j = sp[1]
      fp = tm_parse_frac(s, j)
      return nil if fp == nil
      sub_ns = fp[0]
      j = fp[1]
  elsif j < s.size && tm_is_digit?(s.byte_at(j))
    mp = tm_parse_digits(s, j, 2)
    return nil if mp == nil
    mi = mp[0]
    return nil if mi > 59
    j = mp[1]
    has_min = true
    if j < s.size && tm_is_digit?(s.byte_at(j))
      sp = tm_parse_digits(s, j, 2)
      return nil if sp == nil
      sc = sp[0]
      return nil if sc > 60
      sc = 59 if sc == 60
      j = sp[1]
      fp = tm_parse_frac(s, j)
      return nil if fp == nil
      sub_ns = fp[0]
      j = fp[1]
  else
    return nil if !allow_hour_only
  ms = sub_ns / 1000000
  us = (sub_ns / 1000) % 1000
  ns = sub_ns % 1000
  [h, mi, sc, ms, us, ns, j, extended, has_min]

# Parse RFC 9557 bracketed annotations starting at `i` until end of string!
# Returns [tz_ann_str_or_nil, tz_crit_bool, cal_ann_str_or_nil] or throws RangeError!
-> tm_parse_annotations(s, i)
  n = s.size
  tz_ann = nil
  tz_crit = false
  cal_ann = nil
  cal_crit = false
  seen_cal = false
  first = true
  while i < n
    js_throw_range("Unexpected character in ISO string: " + s) if s.byte_at(i) != 91 # '['
    close = s.index("]", i + 1)
    js_throw_range("Unclosed annotation bracket in ISO string: " + s) if close == nil
    inner = s.slice(i + 1, close - i - 1)
    js_throw_range("Empty annotation in ISO string") if inner.size == 0
    crit = false
    if inner.byte_at(0) == 33 # '!'
      crit = true
      inner = inner.slice(1, inner.size - 1)
      js_throw_range("Empty critical annotation") if inner.size == 0
    eq = inner.index("=")
    if eq == nil
      # TimeZone annotation (ONLY allowed as the very first bracketed annotation!)
      js_throw_range("TimeZone annotation must appear first: " + s) if !first
      # Validate TZ annotation syntax: offset (no sub-minute!) OR IANA TZName
      if tm_parse_sign(inner, 0) != nil
        op = tm_parse_utc_offset(inner, 0, false)
        js_throw_range("Invalid offset timezone annotation: " + inner) if op == nil || op[2] != inner.size
      else
        js_throw_range("Invalid timezone annotation: " + inner) if !tm_valid_iana_syntax?(inner)
      tz_ann = inner
      tz_crit = crit
    else
      # Key=Value annotation
      key = inner.slice(0, eq)
      val = inner.slice(eq + 1, inner.size - eq - 1)
      js_throw_range("Invalid annotation key: " + key) if !tm_valid_ann_key?(key)
      js_throw_range("Invalid annotation value: " + val) if !tm_valid_ann_val?(val)
      if key == "u-ca"
        if !seen_cal
          cal_ann = val
          cal_crit = crit
          seen_cal = true
        else
          # Duplicate u-ca annotation: throws RangeError if either is critical!
          js_throw_range("Duplicate critical calendar annotation") if crit || cal_crit
      else
        js_throw_range("Unknown critical annotation: " + key) if crit
    first = false
    i = close + 1
  [tz_ann, tz_crit, cal_ann]

-> tm_valid_ann_key?(k)
  return false if k.size == 0 || !k.ascii?
  c0 = k.byte_at(0)
  return false if !(tm_is_ascii_lower?(c0) || c0 == 95)
  i = 1
  while i < k.size
    c = k.byte_at(i)
    return false if !(tm_is_ascii_lower?(c) || tm_is_digit?(c) || c == 95 || c == 45)
    i += 1
  true

-> tm_valid_ann_val?(v)
  return false if v.size == 0 || !v.ascii?
  parts = v.split("-")
  i = 0
  while i < parts.size
    p = parts[i]
    return false if p.size == 0 || !intl_alnum?(p)
    i += 1
  true

-> tm_valid_iana_syntax?(s)
  return false if s.size == 0 || !s.ascii?
  parts = s.split("/")
  i = 0
  while i < parts.size
    p = parts[i]
    return false if p.size == 0 || p == "." || p == ".."
    c0 = p.byte_at(0)
    return false if !(tm_is_ascii_alpha?(c0) || c0 == 95 || c0 == 46)
    j = 1
    while j < p.size
      c = p.byte_at(j)
      return false if !(tm_is_ascii_alpha?(c) || tm_is_digit?(c) || c == 95 || c == 46 || c == 43 || c == 45)
      j += 1
    i += 1
  true

# Parse full ISO date (YYYY-MM-DD, ±YYYYYY-MM-DD, YYYYMMDD, ±YYYYYYMMDD) at index `i`.
# Returns [y, m, d, next_i, extended_bool] or nil
-> tm_parse_date_part(s, i)
  sp = tm_parse_sign(s, i)
  y = 0
  j = i
  if sp != nil
    dp = tm_parse_digits(s, sp[1], 6)
    return nil if dp == nil
    # Reject -000000!
    return nil if sp[0] < 0 && dp[0] == 0
    y = sp[0] * dp[0]
    j = dp[1]
  else
    dp = tm_parse_digits(s, j, 4)
    return nil if dp == nil
    y = dp[0]
    j = dp[1]
  return nil if j >= s.size
  extended = false
  if s.byte_at(j) == 45
    extended = true
    j += 1
    mp = tm_parse_digits(s, j, 2)
    return nil if mp == nil
    m = mp[0]
    j = mp[1]
    return nil if j >= s.size || s.byte_at(j) != 45
    j += 1
    ddp = tm_parse_digits(s, j, 2)
    return nil if ddp == nil
    d = ddp[0]
    j = ddp[1]
  else
    mp = tm_parse_digits(s, j, 2)
    return nil if mp == nil
    m = mp[0]
    j = mp[1]
    ddp = tm_parse_digits(s, j, 2)
    return nil if ddp == nil
    d = ddp[0]
    j = ddp[1]
  return nil if !tm_iso_date_valid?(y, m, d)
  [y, m, d, j, extended]

# Master ISO DateTime string parser!
# Returns Hash: { y:, m:, d:, has_time:, h:, mi:, s:, ms:, us:, ns:,
#                 z_flag:, off_ns:, off_has_sec:, tz_ann:, tz_crit:, cal_ann: }
# Throws RangeError on invalid syntax.
-> tm_parse_iso_datetime(str)
  dp = tm_parse_date_part(str, 0)
  js_throw_range("Invalid ISO date-time string: " + str) if dp == nil
  y = dp[0]
  m = dp[1]
  d = dp[2]
  i = dp[3]
  has_time = false
  h = 0
  mi = 0
  sc = 0
  ms = 0
  us = 0
  ns = 0
  z_flag = false
  off_ns = nil
  off_has_sec = false
  n = str.size
  if i < n
    c = str.byte_at(i)
    if c == 84 || c == 116 || c == 32 # 'T', 't', ' '
      i += 1
      tp = tm_parse_time_spec(str, i, true)
      js_throw_range("Invalid time in ISO string: " + str) if tp == nil
      has_time = true
      h = tp[0]
      mi = tp[1]
      sc = tp[2]
      ms = tp[3]
      us = tp[4]
      ns = tp[5]
      i = tp[6]
      # Optional Z or UTC offset (ONLY valid when time is present!)
      if i < n
        c2 = str.byte_at(i)
        if c2 == 90 || c2 == 122 # 'Z', 'z'
          z_flag = true
          i += 1
        elsif tm_parse_sign(str, i) != nil
          op = tm_parse_utc_offset(str, i, true)
          js_throw_range("Invalid UTC offset in ISO string: " + str) if op == nil
          off_ns = op[0]
          off_has_sec = op[1]
          i = op[2]
  ann = tm_parse_annotations(str, i)
  {
    "y" => y, "m" => m, "d" => d,
    "has_time" => has_time, "h" => h, "mi" => mi, "s" => sc, "ms" => ms, "us" => us, "ns" => ns,
    "z" => z_flag, "off_ns" => off_ns, "off_has_sec" => off_has_sec,
    "tz_ann" => ann[0], "tz_crit" => ann[1], "cal_ann" => ann[2]
  }

# Parse TemporalTimeString -> [h, mi, s, ms, us, ns] (throws RangeError if invalid or Z present!)
-> tm_parse_iso_time(str)
  js_throw_range("Empty time string") if str.size == 0
  # Try full DateTime string first (if it starts with YYYY-MM-DD / ±YYYYYY...)
  c0 = str.byte_at(0)
  if c0 == 84 || c0 == 116 # leading 'T' or 't'
    tp = tm_parse_time_spec(str, 1, true)
    js_throw_range("Invalid time string: " + str) if tp == nil
    i = tp[6]
    if i < str.size
      c2 = str.byte_at(i)
      js_throw_range("UTC designator Z not allowed in PlainTime string") if c2 == 90 || c2 == 122
      if tm_parse_sign(str, i) != nil
        op = tm_parse_utc_offset(str, i, true)
        js_throw_range("Invalid offset in time string: " + str) if op == nil
        i = op[2]
    tm_parse_annotations(str, i)
    return [tp[0], tp[1], tp[2], tp[3], tp[4], tp[5]]
  # Check if full date-time (must have a time part and NO Z!)
  dp = tm_parse_date_part(str, 0)
  if dp != nil
    r = tm_parse_iso_datetime(str)
    js_throw_range("PlainTime string must contain a time component") if !r["has_time"]
    js_throw_range("UTC designator Z not allowed in PlainTime string") if r["z"]
    return [r["h"], r["mi"], r["s"], r["ms"], r["us"], r["ns"]]
  # Otherwise bare TimeSpec! Per Temporal grammar, reject strings ambiguous with DateYearMonth (YYYY-MM) or DateMonthDay (MM-DD / MMDD / YYYYMM)!
  tp = tm_parse_time_spec(str, 0, true)
  js_throw_range("Invalid time string: " + str) if tp == nil
  i = tp[6]
  has_colon = tp[7]
  has_min = tp[8]
  has_off_or_ann = i < str.size
  # Reject ambiguous bare 4-digit (MMDD) or 6-digit (YYYYMM) when no colon and no offset/annotation:
  # Wait: per spec, 4 digits HHMM is valid PlainTime UNLESS it's valid MMDD (e.g. 0101..1231) and has no offset/ann!
  # Actually per TC39 Temporal ParseTemporalTimeString:
  # Lookahead excludes DateMonthDay (MMDD with 01<=MM<=12, 01<=DD<=daysInMonth(1972,MM)) AND DateYearMonth (YYYYMM)!
  # Reject ambiguous bare YYYY-MM (e.g. "2021-12" or "2021-12[-12:00]"), MM-DD, MMDD, YYYYMM when no leading T and no colon!
  if !has_colon
    br = str.index("\[")
    core_len = br != nil ? br : str.size
    if core_len == 7 && str.byte_at(4) == 45
      # YYYY-MM parsed as HHMM + offset -MM -> ambiguous with DateSpecYearMonth!
      mm = str.slice(5, 2).to_i
      js_throw_range("Ambiguous YYYY-MM string requires T prefix: " + str) if mm >= 1 && mm <= 12
    elsif core_len == 5 && str.byte_at(2) == 45
      # MM-DD parsed as HH + offset -DD -> ambiguous with DateSpecMonthDay!
      mm = str.slice(0, 2).to_i
      dd = str.slice(3, 2).to_i
      js_throw_range("Ambiguous MM-DD string requires T prefix: " + str) if mm >= 1 && mm <= 12 && dd >= 1 && dd <= tm_iso_days_in_month(1972, mm)
    elsif i == core_len
      if core_len == 4
        mm = str.slice(0, 2).to_i
        dd = str.slice(2, 2).to_i
        js_throw_range("Ambiguous MMDD/HHMM string: " + str) if mm >= 1 && mm <= 12 && dd >= 1 && dd <= tm_iso_days_in_month(1972, mm)
      elsif core_len == 6
        mm = str.slice(4, 2).to_i
        js_throw_range("Ambiguous YYYYMM/HHMMSS string: " + str) if mm >= 1 && mm <= 12
  if i < str.size
    c2 = str.byte_at(i)
    js_throw_range("UTC designator Z not allowed in PlainTime string") if c2 == 90 || c2 == 122
    if tm_parse_sign(str, i) != nil
      op = tm_parse_utc_offset(str, i, true)
      js_throw_range("Invalid offset in time string: " + str) if op == nil
      i = op[2]
  tm_parse_annotations(str, i)
  [tp[0], tp[1], tp[2], tp[3], tp[4], tp[5]]

# Parse TemporalYearMonthString -> [y, m, d, cal_ann_or_nil, has_day_bool]
-> tm_parse_iso_ym(str)
  js_throw_range("Empty YearMonth string") if str.size == 0
  # Try full date-time first
  dp = tm_parse_date_part(str, 0)
  if dp != nil
    r = tm_parse_iso_datetime(str)
    js_throw_range("UTC designator Z not allowed in PlainYearMonth string") if r["z"]
    return [r["y"], r["m"], r["d"], r["cal_ann"], true]
  # Parse DateSpecYearMonth: YYYY-MM | YYYYMM | ±YYYYYY-MM | ±YYYYYYMM + optional annotations
  sp = tm_parse_sign(str, 0)
  y = 0
  i = 0
  if sp != nil
    yp = tm_parse_digits(str, sp[1], 6)
    js_throw_range("Invalid YearMonth string: " + str) if yp == nil || (sp[0] < 0 && yp[0] == 0)
    y = sp[0] * yp[0]
    i = yp[1]
  else
    yp = tm_parse_digits(str, 0, 4)
    js_throw_range("Invalid YearMonth string: " + str) if yp == nil
    y = yp[0]
    i = yp[1]
  i += 1 if i < str.size && str.byte_at(i) == 45
  mp = tm_parse_digits(str, i, 2)
  js_throw_range("Invalid YearMonth string: " + str) if mp == nil
  m = mp[0]
  js_throw_range("Invalid month in YearMonth string: " + str) if m < 1 || m > 12
  i = mp[1]
  ann = tm_parse_annotations(str, i)
  [y, m, 1, ann[2], false]

# Parse TemporalMonthDayString -> [y_or_nil, m, d, cal_ann_or_nil]
-> tm_parse_iso_md(str)
  js_throw_range("Empty MonthDay string") if str.size == 0
  # Try full date-time first
  dp = tm_parse_date_part(str, 0)
  if dp != nil
    r = tm_parse_iso_datetime(str)
    js_throw_range("UTC designator Z not allowed in PlainMonthDay string") if r["z"]
    return [r["y"], r["m"], r["d"], r["cal_ann"]]
  # Parse DateSpecMonthDay: [--]MM-DD | [--]MMDD + optional annotations
  i = 0
  if str.starts_with?("--")
    i = 2
  mp = tm_parse_digits(str, i, 2)
  js_throw_range("Invalid MonthDay string: " + str) if mp == nil
  m = mp[0]
  i = mp[1]
  i += 1 if i < str.size && str.byte_at(i) == 45
  ddp = tm_parse_digits(str, i, 2)
  js_throw_range("Invalid MonthDay string: " + str) if ddp == nil
  d = ddp[0]
  i = ddp[1]
  js_throw_range("Invalid MonthDay date: " + str) if !tm_iso_date_valid?(1972, m, d)
  ann = tm_parse_annotations(str, i)
  [nil, m, d, ann[2]]

# ---- TimeZone Engine (IANA via ICU 78 + Fixed Offset) ----

# Parse an offset timezone ID string strictly (NO seconds/fraction! ±HH:MM, ±HHMM, ±HH, with U+2212 allowed)
# Returns [canon_id_str, offset_ns(## int)] or nil
-> tm_parse_tz_offset_id(s)
  op = tm_parse_utc_offset(s, 0, false)
  return nil if op == nil || op[2] != s.size
  off_ns = op[0]
  # Canonical offset TZ ID normalizes -00:00 -> +00:00
  off_ns = (0 ## int) if off_ns == (0 ## int)
  [tm_fmt_offset_ns(off_ns), off_ns]

# Validate & normalize a Temporal TimeZone identifier (IANA or fixed offset). Returns canonical-cased tz_id string or throws RangeError.
-> tm_resolve_tz_id(tz_str)
  # Check offset first (supports U+2212!)
  off = tm_parse_tz_offset_id(tz_str)
  return off[0] if off != nil
  # Check IANA name (case-insensitive via intl_tz_ci_map!)
  iana = intl_lookup_iana_tz(tz_str)
  return iana if iana != nil
  js_throw_range("Invalid Temporal time zone identifier: " + tz_str)

# Parse TemporalTimeZoneIdentifier (direct TZ ID OR RFC 9557 ISO string!)
-> tm_parse_tz_arg(val)
  if js_special?(val, "Temporal.ZonedDateTime")
    return val.internal[1]
  js_throw_type("Time zone must be a string or Temporal.ZonedDateTime") if !js_string?(val)
  # Try direct offset TZ ID first
  off = tm_parse_tz_offset_id(val)
  return off[0] if off != nil
  # Try direct IANA TZ ID
  iana = intl_lookup_iana_tz(val)
  return iana if iana != nil
  # Try parsing as RFC 9557 ISO string!
  r = tm_parse_iso_datetime(val)
  if r["tz_ann"] != nil
    return tm_resolve_tz_id(r["tz_ann"])
  return "UTC" if r["z"]
  if r["off_ns"] != nil
    js_throw_range("Sub-minute offset cannot be used as time zone identifier: " + val) if r["off_has_sec"]
    on = r["off_ns"]
    on = (0 ## int) if on == (0 ## int)
    return tm_fmt_offset_ns(on)
  js_throw_range("ISO string missing time zone identifier: " + val)

-> tm_tz_is_offset?(tz_id)
  tz_id.size > 0 && (tz_id.byte_at(0) == 43 || tz_id.byte_at(0) == 45)

-> tm_tz_fixed_offset_ns(tz_id)
  return nil if !tm_tz_is_offset?(tz_id)
  op = tm_parse_utc_offset(tz_id, 0, false)
  op != nil ? op[0] : (0 ## int)

# IANA 2024b primary zone overrides where ICU's CLDR canonical ID still keeps POSIX/legacy IDs separate
TM_TZ_PRIMARY_OVERRIDES = {
  "CET" => "Europe/Brussels",
  "CST6CDT" => "America/Chicago",
  "EET" => "Europe/Athens",
  "EST" => "America/Panama",
  "EST5EDT" => "America/New_York",
  "HST" => "Pacific/Honolulu",
  "MET" => "Europe/Brussels",
  "MST" => "America/Phoenix",
  "MST7MDT" => "America/Denver",
  "PST8PDT" => "America/Los_Angeles",
  "WET" => "Europe/Lisbon",
  "Etc/GMT+0" => "UTC",
  "Etc/GMT-0" => "UTC",
  "Etc/Greenwich" => "UTC"
}

# Canonical primary ID for TimeZoneEquals (UTC / Etc/UTC / Etc/GMT / GMT -> "UTC", Asia/Calcutta -> "Asia/Kolkata")
-> tm_tz_primary_id(tz_id)
  return tz_id if tm_tz_is_offset?(tz_id)
  return TM_TZ_PRIMARY_OVERRIDES[tz_id] if TM_TZ_PRIMARY_OVERRIDES.has_key?(tz_id)
  return "UTC" if tz_id == "UTC" || tz_id == "Etc/UTC" || tz_id == "Etc/GMT" || tz_id == "GMT" || tz_id == "Etc/GMT0" || tz_id == "Etc/UCT" || tz_id == "Etc/Universal" || tz_id == "Etc/Zulu" || tz_id == "UCT" || tz_id == "Universal" || tz_id == "Zulu" || tz_id == "Greenwich" || tz_id == "GMT+0" || tz_id == "GMT-0" || tz_id == "GMT0"
  iana = icu_iana_tz(tz_id)
  if iana != nil && iana.size > 0 && iana != "Etc/Unknown"
    return TM_TZ_PRIMARY_OVERRIDES[iana] if TM_TZ_PRIMARY_OVERRIDES.has_key?(iana)
    return "UTC" if iana == "Etc/UTC" || iana == "Etc/GMT" || iana == "Etc/GMT0" || iana == "Etc/GMT+0" || iana == "Etc/GMT-0"
    return iana
  tz_id

-> tm_tz_equals?(tz1, tz2)
  return true if tz1 == tz2
  tm_tz_primary_id(tz1) == tm_tz_primary_id(tz2)

# Cache open ICU UCalendar handles per IANA timezone ID (for ISO offset/transition queries)
TM_TZ_CAL_CACHE = {}

-> tm_tz_icu_cal(tz_id)
  c = TM_TZ_CAL_CACHE[tz_id]
  return c if c != nil
  fn_open = icu_sym("ucal_open")
  ut = icu_to_u16(tz_id)
  tba = ut[0]
  lb = icu_cstr("en@calendar=iso8601")
  eb = icu_err_buf()
  cal = icu_c5(fn_open, icu_ptr(tba), ut[1], icu_ptr(lb), 0, icu_ptr(eb))
  tba.size
  lb.size
  ec = icu_err_code(eb)
  eb.size
  return 0 if cal == 0 || ec > 0
  # Make proleptic Gregorian!
  fn_sgc = icu_sym("ucal_setGregorianChange")
  eb2 = icu_err_buf()
  icu_c_pdp(fn_sgc, cal, wvalue_bits(~-100000000000000000000.0) ## i64, icu_ptr(eb2))
  eb2.size
  TM_TZ_CAL_CACHE[tz_id] = cal
  cal

# Get exact timezone offset in nanoseconds (## int) at `epoch_ns`
-> tm_tz_get_offset_ns(tz_id, epoch_ns)
  return 0 ## int if tz_id == "UTC" || tz_id == "Etc/UTC" || tz_id == "Etc/GMT" || tz_id == "GMT"
  fo = tm_tz_fixed_offset_ns(tz_id)
  return fo if fo != nil
  cal = tm_tz_icu_cal(tz_id)
  return 0 ## int if cal == 0
  ms_i = tm_floor_div(epoch_ns, TM_NS_MS)
  ms_f = tm_int_to_num(ms_i)
  fn_setm = icu_sym("ucal_setMillis")
  fn_get = icu_sym("ucal_get")
  eb = icu_err_buf()
  icu_c_pdp(fn_setm, cal, wvalue_bits(ms_f) ## i64, icu_ptr(eb))
  icu_err_reset(eb)
  zo = icu_sext32(icu_c3(fn_get, cal, 15, icu_ptr(eb))) # UCAL_ZONE_OFFSET = 15 (ms)
  icu_err_reset(eb)
  doff = icu_sext32(icu_c3(fn_get, cal, 16, icu_ptr(eb))) # UCAL_DST_OFFSET = 16 (ms)
  eb.size
  ((zo + doff) ## int) * TM_NS_MS

# Get next (dir > 0) or previous (dir < 0) timezone transition as exact epochNs (## int) or nil!
-> tm_tz_get_transition(tz_id, epoch_ns, dir)
  return nil if tm_tz_is_offset?(tz_id)
  return nil if tz_id == "UTC" || tz_id == "Etc/UTC" || tz_id == "Etc/GMT" || tz_id == "GMT"
  cal = tm_tz_icu_cal(tz_id)
  return nil if cal == 0
  # Note: ICU works at ms granularity! Handle sub-ms remainder carefully:
  # If epoch_ns has sub-ms > 0:
  #   - for previous (dir < 0): a transition AT floor(epoch_ns / 1e6) ms IS strictly before epoch_ns! -> PREVIOUS_INCLUSIVE (3)
  #   - for next (dir > 0): a transition AT floor(epoch_ns / 1e6) ms is NOT after epoch_ns -> NEXT (0)
  ms_i = tm_floor_div(epoch_ns, TM_NS_MS)
  sub = epoch_ns - ms_i * TM_NS_MS
  tr_type = 0 # NEXT = 0, NEXT_INCLUSIVE = 1, PREVIOUS = 2, PREVIOUS_INCLUSIVE = 3
  if dir > 0
    tr_type = 0
  else
    tr_type = sub > (0 ## int) ? 3 : 2
  fn_setm = icu_sym("ucal_setMillis")
  fn_tr = icu_sym("ucal_getTimeZoneTransitionDate")
  eb = icu_err_buf()
  db = ByteArray.new(8)
  cur_ms = tm_int_to_num(ms_i)
  # Loop in case ICU has a no-op transition (same total offset before and after — Temporal skips non-offset-changing transitions!)
  tries = 0
  while tries < 8
    icu_err_reset(eb)
    icu_c_pdp(fn_setm, cal, wvalue_bits(cur_ms) ## i64, icu_ptr(eb))
    icu_err_reset(eb)
    ok = icu_c4(fn_tr, cal, tr_type, icu_ptr(db), icu_ptr(eb)) & 255
    ec = icu_err_code(eb)
    break if ok == 0 || ec > 0
    tr_ms = tm_load_f64_i64(icu_ptr(db), 0)
    tr_ns = (tr_ms ## int) * TM_NS_MS
    break if !tm_epoch_ns_valid?(tr_ns)
    # Verify total offset actually changed across tr_ns!
    off_b = tm_tz_get_offset_ns(tz_id, tr_ns - (1 ## int))
    off_a = tm_tz_get_offset_ns(tz_id, tr_ns)
    if off_b != off_a
      db.size
      eb.size
      return tr_ns
    cur_ms = tr_ms + ~0.0
    tr_type = dir > 0 ? 0 : 2
    tries += 1
  db.size
  eb.size
  nil

fn tm_load_f64_i64(addr, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    %d = load double, ptr %q, align 8
    %r = fptosi double %d to i64
    ret i64 %r
  IR

# GetPossibleInstantsFor ( tz_id, iso_dt ) -> Array of 0, 1, or 2 exact epochNs (## int)
-> tm_tz_possible_instants(tz_id, y, m, d, h, mi, s, ms, us, ns)
  local_ns = tm_iso_epoch_ns(y, m, d, h, mi, s, ms, us, ns)
  fo = tm_tz_fixed_offset_ns(tz_id)
  if fo != nil
    return [local_ns - fo]
  if tz_id == "UTC" || tz_id == "Etc/UTC" || tz_id == "Etc/GMT" || tz_id == "GMT"
    return [local_ns]
  # Probe offsets 1 day before and 1 day after (handles DST shifts & up to 24h dateline jumps!)
  off_lo = tm_tz_get_offset_ns(tz_id, local_ns - TM_NS_DAY)
  off_hi = tm_tz_get_offset_ns(tz_id, local_ns + TM_NS_DAY)
  cands = [local_ns - off_lo]
  if off_hi != off_lo
    c2 = local_ns - off_hi
    if c2 < cands[0]
      cands = [c2, cands[0]]
    else
      cands.push(c2)
  # Also check if there is an intermediate offset in the 48h window
  off_mid = tm_tz_get_offset_ns(tz_id, local_ns - off_lo)
  if off_mid != off_lo && off_mid != off_hi
    cm = local_ns - off_mid
    cands.push(cm)
  # Filter to instants `t` where t + offset(t) == local_ns, sorted ascending, deduplicated!
  out = []
  i = 0
  while i < cands.size
    t = cands[i]
    if t + tm_tz_get_offset_ns(tz_id, t) == local_ns
      out.push(t) if !out.include?(t)
    i += 1
  if out.size == 2 && out[0] > out[1]
    tmp = out[0]
    out[0] = out[1]
    out[1] = tmp
  out

# DisambiguatePossibleInstants ( tz_id, iso_dt, disambig ) -> exact epochNs (## int)
-> tm_tz_disambiguate(tz_id, y, m, d, h, mi, s, ms, us, ns, disambig)
  poss = tm_tz_possible_instants(tz_id, y, m, d, h, mi, s, ms, us, ns)
  if poss.size == 1
    res = poss[0]
    js_throw_range("Instant out of valid Temporal range") if !tm_epoch_ns_valid?(res)
    return res
  if poss.size >= 2
    js_throw_range("Ambiguous local time in time zone " + tz_id) if disambig == "reject"
    res = disambig == "later" ? poss[poss.size - 1] : poss[0]
    js_throw_range("Instant out of valid Temporal range") if !tm_epoch_ns_valid?(res)
    return res
  # Gap (0 possible instants)!
  js_throw_range("Skipped local time in time zone " + tz_id) if disambig == "reject"
  local_ns = tm_iso_epoch_ns(y, m, d, h, mi, s, ms, us, ns)
  # Per Temporal DisambiguatePossibleInstants:
  # Check offset 1 day before and 1 day after (clamped to valid epochNs range!)
  t_before = local_ns - TM_NS_DAY
  t_before = TM_MIN_EPOCH_NS if t_before < TM_MIN_EPOCH_NS
  t_after = local_ns + TM_NS_DAY
  t_after = TM_MAX_EPOCH_NS if t_after > TM_MAX_EPOCH_NS
  off_before = tm_tz_get_offset_ns(tz_id, t_before)
  off_after = tm_tz_get_offset_ns(tz_id, t_after)
  gap = off_after - off_before
  if disambig == "earlier"
    shifted = local_ns - gap
    dt = tm_iso_dt_from_epoch_ns(shifted)
    p2 = tm_tz_possible_instants(tz_id, dt[0], dt[1], dt[2], dt[3], dt[4], dt[5], dt[6], dt[7], dt[8])
    res = p2.size > 0 ? p2[0] : (local_ns - off_before)
    js_throw_range("Instant out of valid Temporal range") if !tm_epoch_ns_valid?(res)
    return res
  else
    # "compatible" or "later"
    shifted = local_ns + gap
    dt = tm_iso_dt_from_epoch_ns(shifted)
    p2 = tm_tz_possible_instants(tz_id, dt[0], dt[1], dt[2], dt[3], dt[4], dt[5], dt[6], dt[7], dt[8])
    res = p2.size > 0 ? p2[p2.size - 1] : (local_ns - off_after)
    js_throw_range("Instant out of valid Temporal range") if !tm_epoch_ns_valid?(res)
    return res

# InterpretISODateTimeOffset ( y, m, d, h, mi, s, ms, us, ns, offset_behavior, off_ns, tz_id, disambig, offset_opt, match_exact )
# offset_behavior: :option, :exact, :wall
-> tm_interpret_iso_dt_offset(y, m, d, h, mi, s, ms, us, ns, off_beh, off_ns, tz_id, disambig, offset_opt, match_exact)
  if off_beh == :wall || offset_opt == "ignore"
    return tm_tz_disambiguate(tz_id, y, m, d, h, mi, s, ms, us, ns, disambig)
  if off_beh == :exact || offset_opt == "use"
    res = tm_iso_epoch_ns(y, m, d, h, mi, s, ms, us, ns) - off_ns
    js_throw_range("Instant out of valid Temporal range") if !tm_epoch_ns_valid?(res)
    return res
  # offset_opt is "reject" or "prefer": per InterpretISODateTimeOffset, wall-clock date must satisfy CheckISODaysRange!
  ed_wall = tm_epoch_days(y, m, d)
  js_throw_range("Wall-clock date outside representable range") if ed_wall < (-100000000 ## int) || ed_wall > (100000000 ## int)
  poss = tm_tz_possible_instants(tz_id, y, m, d, h, mi, s, ms, us, ns)
  local_ns = tm_iso_epoch_ns(y, m, d, h, mi, s, ms, us, ns)
  i = 0
  while i < poss.size
    cand = poss[i]
    cand_off = local_ns - cand
    if cand_off == off_ns
      js_throw_range("Instant out of valid Temporal range") if !tm_epoch_ns_valid?(cand)
      return cand
    if !match_exact
      # Round cand_off to nearest minute (halfExpand) and compare!
      rounded_off = tm_round_to_inc(cand_off, TM_NS_MIN, "halfExpand")
      if rounded_off == off_ns
        js_throw_range("Instant out of valid Temporal range") if !tm_epoch_ns_valid?(cand)
        return cand
    i += 1
  if offset_opt == "prefer"
    return tm_tz_disambiguate(tz_id, y, m, d, h, mi, s, ms, us, ns, disambig)
  js_throw_range("UTC offset does not match time zone " + tz_id)

# ---- Shared Temporal Unit & Options Helpers ----

TM_UNIT_SINGULAR = {
  "year" => "year", "years" => "year",
  "month" => "month", "months" => "month",
  "week" => "week", "weeks" => "week",
  "day" => "day", "days" => "day",
  "hour" => "hour", "hours" => "hour",
  "minute" => "minute", "minutes" => "minute",
  "second" => "second", "seconds" => "second",
  "millisecond" => "millisecond", "milliseconds" => "millisecond",
  "microsecond" => "microsecond", "microseconds" => "microsecond",
  "nanosecond" => "nanosecond", "nanoseconds" => "nanosecond"
}

TM_UNIT_RANK = {
  "year" => 0, "month" => 1, "week" => 2, "day" => 3,
  "hour" => 4, "minute" => 5, "second" => 6,
  "millisecond" => 7, "microsecond" => 8, "nanosecond" => 9
}

TM_UNIT_NS = {
  "day" => TM_NS_DAY,
  "hour" => TM_NS_HOUR,
  "minute" => TM_NS_MIN,
  "second" => TM_NS_SEC,
  "millisecond" => TM_NS_MS,
  "microsecond" => TM_NS_US,
  "nanosecond" => 1 ## int
}

TM_UNIT_MAX_INC = {
  "hour" => 24,
  "minute" => 60,
  "second" => 60,
  "millisecond" => 1000,
  "microsecond" => 1000,
  "nanosecond" => 1000
}

TM_ROUND_MODES = [
  "ceil", "floor", "expand", "trunc",
  "halfCeil", "halfFloor", "halfExpand", "halfTrunc", "halfEven"
]

-> tm_get_options_obj(opts)
  return js_new_object(nil) if opts == nil
  return opts if js_object?(opts)
  js_throw_type("Temporal options must be an object")

-> tm_get_option(opts, prop, type, values, fallback)
  v = jget(opts, prop)
  if v == nil
    js_throw_range("Required option '" + prop + "' missing") if fallback == :required
    return fallback
  if type == :boolean
    return js_truthy(v)
  s = js_to_string(v)
  if values != nil && !values.include?(s)
    js_throw_range("Invalid value '" + s + "' for option '" + prop + "'")
  s

# GetTemporalUnitValuedOption ( opts, key, allowed_group, default_val, extra_vals = nil )
# allowed_group: :date, :time, :datetime, :instant, :any (defer group check when reading multiple options!)
-> tm_get_unit(opts, key, group, default_val, allow_auto = false)
  v = jget(opts, key)
  if v == nil
    js_throw_range("Option '" + key + "' is required") if default_val == :required
    return default_val
  s = js_to_string(v)
  return "auto" if allow_auto && s == "auto"
  js_throw_range("Invalid unit '" + s + "' for '" + key + "'") if !TM_UNIT_SINGULAR.has_key?(s)
  u = TM_UNIT_SINGULAR[s]
  tm_validate_unit_group(u, group) if group != :any
  u

-> tm_validate_unit_group(u, group)
  return if u == nil || u == "auto"
  rk = TM_UNIT_RANK[u]
  if group == :date
    js_throw_range("Time unit not allowed: " + u) if rk > 3
  elsif group == :time
    js_throw_range("Date unit not allowed: " + u) if rk < 4
  elsif group == :instant
    js_throw_range("Unit not allowed for Instant: " + u) if rk < 4
  nil

-> tm_get_rounding_increment(opts)
  v = jget(opts, "roundingIncrement")
  return 1 if v == nil
  n = js_to_number(v)
  js_throw_range("Invalid roundingIncrement") if !js_finite?(n)
  iv = js_math_trunc(n)
  js_throw_range("roundingIncrement out of range") if iv < ~1.0 || iv > ~1000000000.0
  iv.to_i

-> tm_validate_rounding_inc(inc, max_v, inclusive)
  js_throw_range("roundingIncrement out of range") if inc < 1
  if inclusive
    js_throw_range("roundingIncrement exceeds maximum") if inc > max_v
  else
    js_throw_range("roundingIncrement exceeds maximum") if inc >= max_v
  js_throw_range("roundingIncrement must divide " + max_v.to_s) if (max_v % inc) != 0
  inc

-> tm_get_rounding_mode(opts, default_val = "halfExpand")
  tm_get_option(opts, "roundingMode", :string, TM_ROUND_MODES, default_val)

-> tm_get_overflow(opts)
  tm_get_option(opts, "overflow", :string, ["constrain", "reject"], "constrain")

-> tm_get_disambig(opts)
  tm_get_option(opts, "disambiguation", :string, ["compatible", "earlier", "later", "reject"], "compatible")

-> tm_get_offset_opt(opts, default_val = "reject")
  tm_get_option(opts, "offset", :string, ["prefer", "use", "ignore", "reject"], default_val)

-> tm_get_show_cal(opts)
  tm_get_option(opts, "calendarName", :string, ["auto", "always", "never", "critical"], "auto")

-> tm_get_show_tz(opts)
  tm_get_option(opts, "timeZoneName", :string, ["auto", "never", "critical"], "auto")

-> tm_get_show_off(opts)
  tm_get_option(opts, "offset", :string, ["auto", "never"], "auto")

# GetDifferenceSettings ( op, opts, unit_group, disallowed_units, fallback_smallest, smallest_largest_default )
# Reads options in EXACT alphabetical order per Temporal spec:
# largestUnit, roundingIncrement, roundingMode, smallestUnit!
# Returns [smallest_unit, largest_unit, r_mode, r_inc]
-> tm_get_diff_settings(op, opts_arg, unit_group, disallowed, fallback_smallest, smallest_largest_def)
  opts = tm_get_options_obj(opts_arg)
  # Read & coerce ALL 4 options BEFORE validating unit group / disallowed / ordering!
  lu = tm_get_unit(opts, "largestUnit", :any, "auto", true)
  r_inc = tm_get_rounding_increment(opts)
  r_mode = tm_get_rounding_mode(opts, "trunc")
  su = tm_get_unit(opts, "smallestUnit", :any, fallback_smallest, false)
  tm_validate_unit_group(lu, unit_group)
  tm_validate_unit_group(su, unit_group)
  if disallowed != nil
    js_throw_range("Disallowed largestUnit: " + lu) if lu != "auto" && disallowed.include?(lu)
    js_throw_range("Disallowed smallestUnit: " + su) if disallowed.include?(su)
  if lu == "auto"
    lu = TM_UNIT_RANK[smallest_largest_def] < TM_UNIT_RANK[su] ? smallest_largest_def : su
  js_throw_range("largestUnit must be >= smallestUnit") if TM_UNIT_RANK[lu] > TM_UNIT_RANK[su]
  # Validate roundingIncrement against smallestUnit (maximum for time units, 1e9 for date units? No: date units allow any int 1..1e9!)
  if TM_UNIT_MAX_INC.has_key?(su)
    tm_validate_rounding_inc(r_inc, TM_UNIT_MAX_INC[su], false)
  r_mode = tm_negate_rmode(r_mode) if op == :since
  [su, lu, r_mode, r_inc]

# GetStringForFractionalSecondDigits & GetTemporalFractionalSecondDigitsOption
# Reads in exact alphabetical order for toString options:
# [calendarName], fractionalSecondDigits, [offset], roundingMode, smallestUnit, [timeZoneName]
-> tm_get_frac_sec_digits(opts)
  v = jget(opts, "fractionalSecondDigits")
  return :auto if v == nil
  if !js_number?(v)
    s = js_to_string(v)
    return :auto if s == "auto"
    js_throw_range("Invalid fractionalSecondDigits: " + s)
  js_throw_range("Invalid fractionalSecondDigits") if !js_finite?(v)
  d = js_math_floor(v).to_i
  js_throw_range("fractionalSecondDigits out of range") if d < 0 || d > 9
  d

# Resolve [precision, unit, inc] from (digits, smallest_unit) per ToSecondsStringPrecisionRecord
-> tm_sec_str_prec(digits, su)
  if su != nil
    return [:minute, "minute", 1] if su == "minute"
    return [0, "second", 1] if su == "second"
    return [3, "millisecond", 1] if su == "millisecond"
    return [6, "microsecond", 1] if su == "microsecond"
    return [9, "nanosecond", 1] if su == "nanosecond"
    js_throw_range("Invalid smallestUnit for toString: " + su)
  return [:auto, "nanosecond", 1] if digits == :auto
  return [0, "second", 1] if digits == 0
  return [digits, "millisecond", 10 ** (3 - digits)] if digits <= 3
  return [digits, "microsecond", 10 ** (6 - digits)] if digits <= 6
  [digits, "nanosecond", 10 ** (9 - digits)]

# Normalize roundTo argument (string or options object) -> [smallest_unit, r_inc, r_mode]
-> tm_parse_round_to(arg, group, allow_day = false)
  js_throw_type("round argument is required") if arg == nil
  if js_string?(arg)
    opts = js_new_object(nil)
    opts.define("smallestUnit", arg, ATTR_W + ATTR_E + ATTR_C)
  elsif js_object?(arg)
    opts = arg
  else
    js_throw_type("round argument must be a string or object")
  r_inc = tm_get_rounding_increment(opts)
  r_mode = tm_get_rounding_mode(opts, "halfExpand")
  su = tm_get_unit(opts, "smallestUnit", allow_day ? :datetime : group, :required, false)
  if allow_day
    js_throw_range("Invalid unit for round: " + su) if TM_UNIT_RANK[su] < 3
  [su, r_inc, r_mode]

# Exact current system epochNanoseconds (ms precision via Date.now * 1e6)
-> tm_now_epoch_ns
  js_bi_from_num(js_date_now()).v * TM_NS_MS

-> js_to_bigint(v)
  js_to_bigint_from(v, false)
