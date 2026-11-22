# blade/js/b_date — Date. Local time comes from the system zone (/etc/localtime, TZif v2:
# transitions, then the POSIX TZ footer rule for later years), read once.

MS_PER_DAY = ~86400000.0

+ JsTzRule
  rw :std_off, :dst_off, :has_dst, :start, :fin, :std_name, :dst_name
  -> new
    @std_off = 0
    @dst_off = 0
    @has_dst = false
    @start = nil
    @fin = nil
    @std_name = "UTC"
    @dst_name = "UTC"

+ JsTz
  rw :times, :offsets, :isdst, :names, :rule, :loaded
  -> new
    @times = []
    @offsets = []
    @isdst = []
    @names = []
    @rule = nil
    @loaded = false

JS_TZ = [nil]

-> js_tz
  t = JS_TZ[0]
  return t if t != nil
  t = JsTz.new
  JS_TZ[0] = t
  begin
    js_tz_load(t, "/etc/localtime")
  rescue e
    t.rule = JsTzRule.new
  t

-> js_be32(s, i)
  v = (s.byte_at(i) << 24) | (s.byte_at(i + 1) << 16) | (s.byte_at(i + 2) << 8) | s.byte_at(i + 3)
  v >= 2147483648 ? v - 4294967296 : v

-> js_be64(s, i)
  hi = js_be32(s, i)
  lo = js_be32(s, i + 4)
  lo = lo + 4294967296 if lo < 0
  hi * 4294967296 + lo

-> js_tz_load(t, path)
  s = File.read(path)
  return nil if s.size < 44 || s.slice(0, 4) != "TZif"
  ver = s.byte_at(4)
  # v1 header
  isutc = js_be32(s, 20)
  isstd = js_be32(s, 24)
  leap = js_be32(s, 28)
  timecnt = js_be32(s, 32)
  typecnt = js_be32(s, 36)
  charcnt = js_be32(s, 40)
  p = 44
  wide = false
  if ver >= 50
    # skip the v1 block to the v2 header
    p = p + timecnt * 4 + timecnt + typecnt * 6 + charcnt + leap * 8 + isstd + isutc
    return nil if s.slice(p, 4) != "TZif"
    isutc = js_be32(s, p + 20)
    isstd = js_be32(s, p + 24)
    leap = js_be32(s, p + 28)
    timecnt = js_be32(s, p + 32)
    typecnt = js_be32(s, p + 36)
    charcnt = js_be32(s, p + 40)
    p = p + 44
    wide = true
  tsz = wide ? 8 : 4
  times = []
  k = 0
  while k < timecnt
    times.push(wide ? js_be64(s, p + k * tsz) : js_be32(s, p + k * tsz))
    k += 1
  p = p + timecnt * tsz
  idx = []
  k = 0
  while k < timecnt
    idx.push(s.byte_at(p + k))
    k += 1
  p = p + timecnt
  types = []
  k = 0
  while k < typecnt
    types.push([js_be32(s, p + k * 6), s.byte_at(p + k * 6 + 4), s.byte_at(p + k * 6 + 5)])
    k += 1
  p = p + typecnt * 6
  chars = s.slice(p, charcnt)
  p = p + charcnt + leap * (wide ? 12 : 8) + isstd + isutc
  k = 0
  while k < timecnt
    ty = types[idx[k]]
    t.times.push(times[k] * 1000)
    t.offsets.push(ty[0])
    t.isdst.push(ty[1] != 0)
    e = chars.index(js_chr(0), ty[2])
    t.names.push(e == nil ? "" : chars.slice(ty[2], e - ty[2]))
    k += 1
  if wide && p < s.size
    nl = s.index("\n", p + 1)
    footer = nl == nil ? "" : s.slice(p + 1, nl - p - 1)
    t.rule = js_tz_parse_rule(footer)
  if t.rule == nil
    r = JsTzRule.new
    if typecnt > 0
      r.std_off = types[0][0]
      r.dst_off = types[0][0]
    t.rule = r
  t.loaded = true
  nil

# POSIX TZ: STDoffset[DST[offset][,start[/time],end[/time]]] with Mm.w.d rules.
-> js_tz_parse_rule(f)
  r = JsTzRule.new
  return nil if f.size == 0
  i = 0
  nm = js_tz_name(f, i)
  r.std_name = nm[0]
  i = nm[1]
  off = js_tz_offset(f, i)
  r.std_off = 0 - off[0]
  i = off[1]
  r.dst_off = r.std_off
  return r if i >= f.size
  nm = js_tz_name(f, i)
  r.dst_name = nm[0]
  i = nm[1]
  r.has_dst = true
  r.dst_off = r.std_off + 3600
  if i < f.size && f.byte_at(i) != 44
    off = js_tz_offset(f, i)
    r.dst_off = 0 - off[0]
    i = off[1]
  if i < f.size && f.byte_at(i) == 44
    parts = f.slice(i + 1, f.size - i - 1).split(",")
    r.start = js_tz_date_rule(parts[0]) if parts.size > 0
    r.fin = js_tz_date_rule(parts[1]) if parts.size > 1
  r.has_dst = false if r.start == nil || r.fin == nil
  r

-> js_tz_name(f, i)
  if i < f.size && f.byte_at(i) == 60
    e = f.index(">", i)
    return [f.slice(i + 1, e - i - 1), e + 1]
  st = i
  while i < f.size && ((f.byte_at(i) >= 65 && f.byte_at(i) <= 90) || (f.byte_at(i) >= 97 && f.byte_at(i) <= 122))
    i += 1
  [f.slice(st, i - st), i]

# [seconds, next index] for [+-]hh[:mm[:ss]]
-> js_tz_offset(f, i)
  sign = 1
  if i < f.size && (f.byte_at(i) == 43 || f.byte_at(i) == 45)
    sign = -1 if f.byte_at(i) == 45
    i += 1
  parts = [0, 0, 0]
  k = 0
  while k < 3 && i < f.size && f.byte_at(i) >= 48 && f.byte_at(i) <= 57
    v = 0
    while i < f.size && f.byte_at(i) >= 48 && f.byte_at(i) <= 57
      v = v * 10 + (f.byte_at(i) - 48)
      i += 1
    parts[k] = v
    k += 1
    if i < f.size && f.byte_at(i) == 58
      i += 1
    else
      break
  [sign * (parts[0] * 3600 + parts[1] * 60 + parts[2]), i]

# Mm.w.d[/time] → [month, week, wday, seconds]
-> js_tz_date_rule(s)
  return nil if s == nil || s.size == 0 || s.byte_at(0) != 77
  slash = s.index("/")
  body = slash == nil ? s.slice(1, s.size - 1) : s.slice(1, slash - 1)
  secs = 7200
  if slash != nil
    o = js_tz_offset(s, slash + 1)
    secs = o[0]
  p = body.split(".")
  return nil if p.size != 3
  [p[0].to_i, p[1].to_i, p[2].to_i, secs]

# Day number (days since epoch) of the rule's date in year y.
-> js_tz_rule_day(rule, y)
  m = rule[0]
  w = rule[1]
  d = rule[2]
  first = js_days_from_civil(y, m, 1)
  wd = js_mod_i(first + 4, 7)
  day = first + js_mod_i(d - wd, 7)
  day = day + (w - 1) * 7
  if w == 5
    nd = js_days_in_month(y, m)
    while day - first >= nd
      day -= 7
  day

# UTC offset in seconds at UTC time t (ms).
-> js_tz_offset_at(t_ms)
  tz = js_tz()
  ts = tz.times
  n = ts.size
  if n > 0 && t_ms < ts[n - 1]
    lo = 0
    hi = n - 1
    return tz.offsets[0] if t_ms < ts[0]
    while lo < hi
      mid = (lo + hi + 1) / 2
      if ts[mid] <= t_ms
        lo = mid
      else
        hi = mid - 1
    return tz.offsets[lo]
  js_tz_rule_offset(tz.rule, t_ms)

-> js_tz_rule_offset(r, t_ms)
  return 0 if r == nil
  return r.std_off if !r.has_dst
  days = js_floor_div_i(t_ms.to_i, 86400000)
  y = js_civil_from_days(days)[0]
  s = js_tz_rule_day(r.start, y) * 86400 + r.start[3] - r.std_off
  e = js_tz_rule_day(r.fin, y) * 86400 + r.fin[3] - r.dst_off
  tsec = js_floor_div_i(t_ms.to_i, 1000)
  in_dst = s < e ? (tsec >= s && tsec < e) : (tsec >= s || tsec < e)
  in_dst ? r.dst_off : r.std_off

-> js_tz_name_at(t_ms)
  tz = js_tz()
  r = tz.rule
  off = js_tz_offset_at(t_ms)
  return r.dst_name if r != nil && r.has_dst && off == r.dst_off
  r == nil ? "UTC" : r.std_name

# LocalTZA for a UTC time (ms Float).
-> js_local_offset_ms(t)
  return ~0.0 if t != t
  js_tz_offset_at(t) * ~1000.0

# UTC(t) for a local time t: guess with the offset at t, then refine.
-> js_utc_of_local(t)
  return t if t != t
  o1 = js_local_offset_ms(t)
  u = t - o1
  o2 = js_local_offset_ms(u)
  return u if o1 == o2
  t - o2

-> js_local_of_utc(t)
  t + js_local_offset_ms(t)

# ---- calendar arithmetic (proleptic Gregorian, days since 1970-01-01) ----

-> js_floor_div_i(a, b)
  q = a / b
  q -= 1 if (a % b != 0) && ((a < 0) != (b < 0))
  q

-> js_mod_i(a, b)
  r = a % b
  r < 0 ? r + b : r

-> js_days_from_civil(y, m, d)
  y2 = m <= 2 ? y - 1 : y
  era = js_floor_div_i(y2, 400)
  yoe = y2 - era * 400
  mp = m > 2 ? m - 3 : m + 9
  doy = (153 * mp + 2) / 5 + d - 1
  doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468

-> js_civil_from_days(z0)
  z = z0 + 719468
  era = js_floor_div_i(z, 146097)
  doe = z - era * 146097
  yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  y = yoe + era * 400
  doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  mp = (5 * doy + 2) / 153
  d = doy - (153 * mp + 2) / 5 + 1
  m = mp < 10 ? mp + 3 : mp - 9
  [m <= 2 ? y + 1 : y, m, d]

-> js_days_in_month(y, m)
  return 29 if m == 2 && (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0))
  return 28 if m == 2
  return 30 if m == 4 || m == 6 || m == 9 || m == 11
  31

# MakeDay / MakeDate / MakeTime with Float arguments (spec §21.4.1).
-> js_make_time(h, mi, s, ms)
  return js_nan() if !(js_finite?(h) && js_finite?(mi) && js_finite?(s) && js_finite?(ms))
  js_math_trunc(h) * ~3600000.0 + js_math_trunc(mi) * ~60000.0 + js_math_trunc(s) * ~1000.0 + js_math_trunc(ms)

-> js_make_day(y, m, d)
  return js_nan() if !(js_finite?(y) && js_finite?(m) && js_finite?(d))
  yi = js_math_trunc(y)
  mi = js_math_trunc(m)
  di = js_math_trunc(d)
  ym = yi + Math.floor(mi / ~12.0)
  return js_nan() if ym.abs > ~400000.0
  mn = mi - Math.floor(mi / ~12.0) * ~12.0
  days = js_days_from_civil(ym.to_i, mn.to_i + 1, 1)
  days + ~0.0 + di - ~1.0

-> js_make_date(day, time)
  return js_nan() if !(js_finite?(day) && js_finite?(time))
  tv = day * MS_PER_DAY + time
  return js_nan() if !js_finite?(tv)
  tv

-> js_time_clip(t)
  return js_nan() if !js_finite?(t) || t.abs > ~8.64e15
  js_math_trunc(t) + ~0.0

# [y, m (0-11), d, h, mi, s, ms, weekday] for a time value t (ms, already local or UTC).
-> js_date_fields(t)
  ti = t.to_i
  days = js_floor_div_i(ti, 86400000)
  ms_in_day = ti - days * 86400000
  ymd = js_civil_from_days(days)
  wd = js_mod_i(days + 4, 7)
  [ymd[0], ymd[1] - 1, ymd[2], ms_in_day / 3600000, (ms_in_day / 60000) % 60, (ms_in_day / 1000) % 60, ms_in_day % 1000, wd]

# ---- Date objects ----

-> js_this_time(v)
  js_throw_type("this is not a Date object.") if !(v.is_a?(JsObject) && v.cls == "Date")
  v.internal

-> js_date_valid?(v)
  v.is_a?(JsObject) && v.cls == "Date" && v.internal == v.internal

# Date.now's clock: nil for the system clock, else a closure answering ms (Blade's
# deterministic rendering mode installs a virtual clock here: blade/determinism).
JS_CLOCK_HOOK = [nil]

-> js_date_now
  h = JS_CLOCK_HOOK[0]
  return h.call() if h != nil
  Instant.now.unix_ms + ~0.0

-> js_date_ctor(args, nt)
  r = JS_REALM[0]
  if nt == nil
    return js_date_to_string(js_date_now())
  tv = js_nan()
  if args.size == 0
    tv = js_date_now()
  elsif args.size == 1
    v = args[0]
    if v.is_a?(JsObject) && v.cls == "Date"
      tv = v.internal
    else
      p = js_to_primitive(v)
      if p.is_a?(String)
        tv = js_date_parse(p)
      else
        tv = js_time_clip(js_to_number(p))
  else
    nums = args.map(->(a) js_to_number(a))
    y = nums[0]
    if y == y
      yi = js_math_trunc(y)
      y = yi + ~1900.0 if yi >= ~0.0 && yi <= ~99.0
    m = nums[1]
    d = nums.size > 2 ? nums[2] : ~1.0
    h = nums.size > 3 ? nums[3] : ~0.0
    mi = nums.size > 4 ? nums[4] : ~0.0
    s = nums.size > 5 ? nums[5] : ~0.0
    ms = nums.size > 6 ? nums[6] : ~0.0
    tv = js_time_clip(js_utc_of_local(js_make_date(js_make_day(y, m, d), js_make_time(h, mi, s, ms))))
  o = JsObject.new(r.proto_from(nt, "Date"), "Date")
  o.internal = tv
  o

-> js_date_utc(args)
  nums = args.map(->(a) js_to_number(a))
  y = nums.size > 0 ? nums[0] : js_nan()
  if y == y
    yi = js_math_trunc(y)
    y = yi + ~1900.0 if yi >= ~0.0 && yi <= ~99.0
  m = nums.size > 1 ? nums[1] : ~0.0
  d = nums.size > 2 ? nums[2] : ~1.0
  h = nums.size > 3 ? nums[3] : ~0.0
  mi = nums.size > 4 ? nums[4] : ~0.0
  s = nums.size > 5 ? nums[5] : ~0.0
  ms = nums.size > 6 ? nums[6] : ~0.0
  js_time_clip(js_make_date(js_make_day(y, m, d), js_make_time(h, mi, s, ms)))

JS_DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
JS_MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

-> js_pad2(n)
  n < 10 ? "0" + n.to_s : n.to_s

-> js_pad3(n)
  n < 10 ? "00" + n.to_s : (n < 100 ? "0" + n.to_s : n.to_s)

-> js_year_str(y)
  return (y < 0 ? "-" : "") + js_pad4(y.abs) if y < 0 || y < 1000
  y.to_s

-> js_pad4(n)
  s = n.to_s
  while s.size < 4
    s = "0" + s
  s

-> js_date_iso(t)
  raise JsThrow.new(js_range_error("Invalid time value")) if t != t
  f = js_date_fields(t)
  y = f[0]
  ys = (y >= 0 && y <= 9999) ? js_pad4(y) : ((y < 0 ? "-" : "+") + js_pad6(y.abs))
  ys + "-" + js_pad2(f[1] + 1) + "-" + js_pad2(f[2]) + "T" + js_pad2(f[3]) + ":" + js_pad2(f[4]) + ":" + js_pad2(f[5]) + "." + js_pad3(f[6]) + "Z"

-> js_pad6(n)
  s = n.to_s
  while s.size < 6
    s = "0" + s
  s

-> js_tz_suffix(t)
  off = (js_local_offset_ms(t) / ~60000.0).to_i
  sign = off >= 0 ? "+" : "-"
  a = off.abs
  "GMT" + sign + js_pad2(a / 60) + js_pad2(a % 60) + " (" + js_tz_long_name(t) + ")"

-> js_tz_long_name(t)
  n = js_tz_name_at(t)
  return "Eastern Daylight Time" if n == "EDT"
  return "Eastern Standard Time" if n == "EST"
  return "Central Daylight Time" if n == "CDT"
  return "Central Standard Time" if n == "CST"
  return "Mountain Daylight Time" if n == "MDT"
  return "Mountain Standard Time" if n == "MST"
  return "Pacific Daylight Time" if n == "PDT"
  return "Pacific Standard Time" if n == "PST"
  return "Coordinated Universal Time" if n == "UTC" || n == "GMT" || n == ""
  n

-> js_date_date_part(lt)
  f = js_date_fields(lt)
  JS_DAY_NAMES[f[7]] + " " + JS_MONTH_NAMES[f[1]] + " " + js_pad2(f[2]) + " " + js_year_str(f[0])

-> js_date_time_part(lt, t)
  f = js_date_fields(lt)
  js_pad2(f[3]) + ":" + js_pad2(f[4]) + ":" + js_pad2(f[5]) + " " + js_tz_suffix(t)

-> js_date_to_string(t)
  return "Invalid Date" if t != t
  lt = js_local_of_utc(t)
  js_date_date_part(lt) + " " + js_date_time_part(lt, t)

-> js_date_utc_string(t)
  return "Invalid Date" if t != t
  f = js_date_fields(t)
  JS_DAY_NAMES[f[7]] + ", " + js_pad2(f[2]) + " " + JS_MONTH_NAMES[f[1]] + " " + js_year_str(f[0]) + " " + js_pad2(f[3]) + ":" + js_pad2(f[4]) + ":" + js_pad2(f[5]) + " GMT"

-> js_date_locale_string(t, kind)
  return "Invalid Date" if t != t
  lt = js_local_of_utc(t)
  f = js_date_fields(lt)
  date = (f[1] + 1).to_s + "/" + f[2].to_s + "/" + f[0].to_s
  h = f[3] % 12
  h = 12 if h == 0
  time = h.to_s + ":" + js_pad2(f[4]) + ":" + js_pad2(f[5]) + " " + (f[3] < 12 ? "AM" : "PM")
  return date if kind == :date
  return time if kind == :time
  date + ", " + time

# Date.parse: ISO 8601 (the spec's format), then the toString/toUTCString forms and the
# common RFC 2822-ish shapes browsers accept.
-> js_date_parse(s0)
  s = s0.strip
  v = js_date_parse_iso(s)
  return v if v != nil
  js_date_parse_loose(s)

-> js_digits_at(s, i, n)
  return -1 if i + n > s.size
  v = 0
  k = 0
  while k < n
    b = s.byte_at(i + k)
    return -1 if b < 48 || b > 57
    v = v * 10 + (b - 48)
    k += 1
  v

-> js_date_parse_iso(s)
  i = 0
  n = s.size
  sign = 1
  y = 0
  if n > 0 && (s.byte_at(0) == 43 || s.byte_at(0) == 45)
    sign = s.byte_at(0) == 45 ? -1 : 1
    y = js_digits_at(s, 1, 6)
    return nil if y < 0
    return js_nan() if sign == -1 && y == 0
    i = 7
  else
    y = js_digits_at(s, 0, 4)
    return nil if y < 0
    i = 4
  y = y * sign
  mo = 1
  d = 1
  if i < n && s.byte_at(i) == 45
    mo = js_digits_at(s, i + 1, 2)
    return nil if mo < 0
    i += 3
    if i < n && s.byte_at(i) == 45
      d = js_digits_at(s, i + 1, 2)
      return nil if d < 0
      i += 3
  h = 0
  mi = 0
  sec = 0
  ms = 0
  date_only = true
  if i < n && (s.byte_at(i) == 84 || s.byte_at(i) == 116 || s.byte_at(i) == 32)
    date_only = false
    h = js_digits_at(s, i + 1, 2)
    return nil if h < 0 || i + 3 >= n || s.byte_at(i + 3) != 58
    mi = js_digits_at(s, i + 4, 2)
    return nil if mi < 0
    i += 6
    if i < n && s.byte_at(i) == 58
      sec = js_digits_at(s, i + 1, 2)
      return nil if sec < 0
      i += 3
      if i < n && (s.byte_at(i) == 46 || s.byte_at(i) == 44)
        i += 1
        st = i
        frac = 0
        digits = 0
        while i < n && s.byte_at(i) >= 48 && s.byte_at(i) <= 57
          if digits < 3
            frac = frac * 10 + (s.byte_at(i) - 48)
          digits += 1
          i += 1
        return nil if digits == 0
        while digits < 3
          frac = frac * 10
          digits += 1
        ms = frac
  off = nil
  if i < n
    c = s.byte_at(i)
    if c == 90 || c == 122
      off = 0
      i += 1
    elsif c == 43 || c == 45
      oh = js_digits_at(s, i + 1, 2)
      return nil if oh < 0
      j = i + 3
      j += 1 if j < n && s.byte_at(j) == 58
      om = js_digits_at(s, j, 2)
      return nil if om < 0
      off = (oh * 60 + om) * (c == 45 ? -1 : 1)
      i = j + 2
  return nil if i != n
  return js_nan() if mo < 1 || mo > 12 || d < 1 || d > js_days_in_month(y, mo) || h > 24 || mi > 59 || sec > 59 || (h == 24 && (mi > 0 || sec > 0 || ms > 0))
  t = js_days_from_civil(y, mo, d) * ~86400000.0 + (h * 3600000 + mi * 60000 + sec * 1000 + ms)
  if off != nil
    t = t - off * ~60000.0
  elsif !date_only
    t = js_utc_of_local(t)
  js_time_clip(t)

-> js_date_parse_loose(s)
  toks = []
  cur = ""
  i = 0
  while i < s.size
    b = s.byte_at(i)
    if b == 32 || b == 44 || b == 9
      toks.push(cur) if cur.size > 0
      cur = ""
    elsif b == 40
      e = s.index(")", i)
      i = e == nil ? s.size : e
      toks.push(cur) if cur.size > 0
      cur = ""
    else
      cur = cur + s.slice(i, 1)
    i += 1
  toks.push(cur) if cur.size > 0
  y = nil
  mo = nil
  d = nil
  h = 0
  mi = 0
  sec = 0
  off = nil
  pm = nil
  toks.each ->(t0)
    t = t0.downcase
    mi_idx = JS_MONTH_NAMES.map(->(m) m.downcase).index(t.size >= 3 ? t.slice(0, 3) : t)
    if mi_idx != nil && t.size >= 3 && (t.byte_at(0) < 48 || t.byte_at(0) > 57)
      mo = mi_idx + 1
    elsif t.index(":") != nil
      parts = t.split(":")
      h = parts[0].to_i
      mi = parts.size > 1 ? parts[1].to_i : 0
      sec = parts.size > 2 ? parts[2].to_i : 0
    elsif t == "am" || t == "pm"
      pm = t == "pm"
    elsif t.starts_with?("gmt") || t.starts_with?("utc") || t == "z"
      off = 0
      rest = t.slice(3, t.size - 3)
      if rest.size >= 3 && (rest.byte_at(0) == 43 || rest.byte_at(0) == 45)
        v = rest.slice(1, rest.size - 1).sub(":", "").to_i
        off = (v / 100 * 60 + v % 100) * (rest.byte_at(0) == 45 ? -1 : 1)
    elsif (t.byte_at(0) == 43 || t.byte_at(0) == 45) && t.size >= 5
      v = t.slice(1, t.size - 1).sub(":", "").to_i
      off = (v / 100 * 60 + v % 100) * (t.byte_at(0) == 45 ? -1 : 1)
    elsif t.index("/") != nil
      p = t.split("/")
      if p.size == 3
        mo = p[0].to_i
        d = p[1].to_i
        y = p[2].to_i
    elsif t.size > 0 && t.byte_at(0) >= 48 && t.byte_at(0) <= 57
      v = t.to_i
      if t.size >= 3 || v > 31
        y = v
      elsif d == nil
        d = v
      else
        y = v
  return js_nan() if y == nil || mo == nil
  d = 1 if d == nil
  y = y + 1900 if y < 50 && false
  y = y + 2000 if y < 50
  y = y + 1900 if y >= 50 && y < 100
  if pm != nil
    h = h % 12
    h += 12 if pm
  return js_nan() if mo < 1 || mo > 12 || d < 1 || d > 31
  t = js_days_from_civil(y, mo, d) * ~86400000.0 + (h * 3600000 + mi * 60000 + sec * 1000)
  if off != nil
    t = t - off * ~60000.0
  else
    t = js_utc_of_local(t)
  js_time_clip(t)

# Getter: field index into js_date_fields, local or UTC.
-> js_date_get(this, idx, local)
  t = js_this_time(this)
  return js_nan() if t != t
  lt = local ? js_local_of_utc(t) : t
  js_date_fields(lt)[idx] + ~0.0

# Setter: which = :ms :s :mi :h :d :m :y; args set that field and the finer ones after it.
-> js_date_set(this, which, args, local)
  t = js_this_time(this)
  nums = args.map(->(a) js_to_number(a))
  if t != t
    if which != :y
      return js_nan()
    t = ~0.0
    lt = ~0.0
  else
    lt = local ? js_local_of_utc(t) : t
  f = js_date_fields(lt)
  y = f[0] + ~0.0
  m = f[1] + ~0.0
  d = f[2] + ~0.0
  h = f[3] + ~0.0
  mi = f[4] + ~0.0
  s = f[5] + ~0.0
  ms = f[6] + ~0.0
  a0 = nums.size > 0 ? nums[0] : js_nan()
  if which == :ms
    ms = a0
  elsif which == :s
    s = a0
    ms = nums[1] if nums.size > 1
  elsif which == :mi
    mi = a0
    s = nums[1] if nums.size > 1
    ms = nums[2] if nums.size > 2
  elsif which == :h
    h = a0
    mi = nums[1] if nums.size > 1
    s = nums[2] if nums.size > 2
    ms = nums[3] if nums.size > 3
  elsif which == :d
    d = a0
  elsif which == :m
    m = a0
    d = nums[1] if nums.size > 1
  else
    y = a0
    m = nums[1] if nums.size > 1
    d = nums[2] if nums.size > 2
  nt = js_make_date(js_make_day(y, m, d), js_make_time(h, mi, s, ms))
  nt = js_utc_of_local(nt) if local
  nt = js_time_clip(nt)
  this.internal = nt
  nt

-> js_date_to_primitive(this, hint)
  js_throw_type("Date.prototype\[Symbol.toPrimitive] called on non-object") if !this.is_a?(JsObject)
  h = js_to_string(hint) if hint.is_a?(String)
  js_throw_type("Invalid hint: " + js_to_display(hint)) if !(hint == "string" || hint == "default" || hint == "number")
  order = hint == "number" ? ["valueOf", "toString"] : ["toString", "valueOf"]
  order.each ->(nm)
    f = this.get(nm, this)
    if f.is_a?(JsObject) && f.callable?
      v = js_call(f, this, [])
      return v if !v.is_a?(JsObject)
  js_throw_type("Cannot convert object to primitive value")

-> js_date_to_json(this)
  o = js_to_object(this)
  tv = js_to_primitive(o, "number")
  return JS_NULL if tv.is_a?(Float) && !js_finite?(tv)
  js_call_method(o, "toISOString", [])

js_install(->(r) js_install_date(r))

-> js_install_date(r)
  dp = JsObject.new(r.object_proto, "Object")
  dc = r.constructor("Date", 7, ->(this, args, nt) js_date_ctor(args, nt), dp)
  r.method(dc, "now", 0, ->(this, args, nt) js_date_now())
  r.method(dc, "parse", 1, ->(this, args, nt) js_date_parse(js_to_string(js_arg(args, 0))))
  r.method(dc, "UTC", 7, ->(this, args, nt) js_date_utc(args))
  names = [["FullYear", 0], ["Month", 1], ["Date", 2], ["Hours", 3], ["Minutes", 4], ["Seconds", 5], ["Milliseconds", 6], ["Day", 7]]
  names.each ->(p)
    js_install_date_getter(r, dp, p[0], p[1])
  r.method(dp, "getTime", 0, ->(this, args, nt) js_this_time(this))
  r.method(dp, "valueOf", 0, ->(this, args, nt) js_this_time(this))
  r.method(dp, "getYear", 0, ->(this, args, nt) js_date_get(this, 0, true) - ~1900.0)
  r.method(dp, "getTimezoneOffset", 0, ->(this, args, nt) js_date_tz_offset(this))
  sets = [["Milliseconds", :ms, 1], ["Seconds", :s, 2], ["Minutes", :mi, 3], ["Hours", :h, 4], ["Date", :d, 1], ["Month", :m, 2], ["FullYear", :y, 3]]
  sets.each ->(p)
    js_install_date_setter(r, dp, p[0], p[1], p[2])
  r.method(dp, "setTime", 1, ->(this, args, nt) js_date_set_time(this, js_arg(args, 0)))
  r.method(dp, "setYear", 1, ->(this, args, nt) js_date_set_year(this, js_arg(args, 0)))
  r.method(dp, "toISOString", 0, ->(this, args, nt) js_date_iso(js_this_time(this)))
  r.method(dp, "toJSON", 1, ->(this, args, nt) js_date_to_json(this))
  r.method(dp, "toString", 0, ->(this, args, nt) js_date_to_string(js_this_time(this)))
  r.method(dp, "toDateString", 0, ->(this, args, nt) js_date_only_string(js_this_time(this)))
  r.method(dp, "toTimeString", 0, ->(this, args, nt) js_time_only_string(js_this_time(this)))
  us = r.method(dp, "toUTCString", 0, ->(this, args, nt) js_date_utc_string(js_this_time(this)))
  dp.define("toGMTString", us, BUILTIN_ATTRS)
  r.method(dp, "toLocaleString", 0, ->(this, args, nt) js_date_locale_string(js_this_time(this), :both))
  r.method(dp, "toLocaleDateString", 0, ->(this, args, nt) js_date_locale_string(js_this_time(this), :date))
  r.method(dp, "toLocaleTimeString", 0, ->(this, args, nt) js_date_locale_string(js_this_time(this), :time))
  tp = r.native("\[Symbol.toPrimitive]", 1, ->(this, args, nt) js_date_to_primitive(this, js_arg(args, 0)))
  dp.define(SYM_TO_PRIMITIVE, tp, ATTR_C)
  nil

-> js_install_date_getter(r, dp, nm, idx)
  r.method(dp, "get" + nm, 0, ->(this, args, nt) js_date_get(this, idx, true))
  r.method(dp, "getUTC" + nm, 0, ->(this, args, nt) js_date_get(this, idx, false))

-> js_install_date_setter(r, dp, nm, which, arity)
  r.method(dp, "set" + nm, arity, ->(this, args, nt) js_date_set(this, which, args, true))
  r.method(dp, "setUTC" + nm, arity, ->(this, args, nt) js_date_set(this, which, args, false))

-> js_date_tz_offset(this)
  t = js_this_time(this)
  return js_nan() if t != t
  ~0.0 - js_local_offset_ms(t) / ~60000.0

-> js_date_set_time(this, v)
  js_this_time(this)
  t = js_time_clip(js_to_number(v))
  this.internal = t
  t

-> js_date_set_year(this, v)
  t = js_this_time(this)
  y = js_to_number(v)
  if y != y
    this.internal = js_nan()
    return js_nan()
  yi = js_math_trunc(y)
  yi = yi + ~1900.0 if yi >= ~0.0 && yi <= ~99.0
  js_date_set(this, :y, [yi], true)

-> js_date_only_string(t)
  return "Invalid Date" if t != t
  js_date_date_part(js_local_of_utc(t))

-> js_time_only_string(t)
  return "Invalid Date" if t != t
  js_date_time_part(js_local_of_utc(t), t)
