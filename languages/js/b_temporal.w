# runtime/b_temporal — TC39 Temporal (Part 1):
# Temporal.Now, Temporal.Instant, Temporal.Duration, Temporal.PlainTime,
# Temporal.PlainDate, and Temporal.PlainDateTime.

in JS

# ---- Constructors & Brand Check Helpers ----

-> tm_check(this, cls, what)
  return this.internal if js_special?(this, cls)
  js_throw_type(cls + ".prototype." + what + " called on incompatible receiver")

-> tm_make_instant(ns, proto = nil)
  js_throw_range("Instant epochNanoseconds out of range") if !tm_epoch_ns_valid?(ns)
  p = proto != nil ? proto : js_realm().intrinsic("Temporal.Instant.prototype")
  o = js_new_special(p, "Temporal.Instant")
  o.internal = [ns]
  o

-> tm_make_duration(vals, proto = nil)
  # vals: Array[10] of ## int; quantize to float64-representable integers (IEEE-754 ℝ(𝔽(v))) before IsValidDuration!
  qvals = Array.new(10, 0 ## int)
  sign = 0
  i = 0
  while i < 10
    v = vals[i]
    if v != (0 ## int)
      nf = tm_int_to_num(v)
      js_throw_range("Duration field out of range") if !js_finite?(nf)
      v = js_bi_from_num(nf).v
    qvals[i] = v
    if v > (0 ## int)
      js_throw_range("Mixed signs in Temporal.Duration") if sign < 0
      sign = 1
    elsif v < (0 ## int)
      js_throw_range("Mixed signs in Temporal.Duration") if sign > 0
      sign = -1
    i += 1
  lim32 = 4294967296 ## int
  js_throw_range("Duration years out of range") if tm_abs_i(qvals[0]) >= lim32
  js_throw_range("Duration months out of range") if tm_abs_i(qvals[1]) >= lim32
  js_throw_range("Duration weeks out of range") if tm_abs_i(qvals[2]) >= lim32
  tot_ns = tm_abs_i(qvals[3]) * TM_NS_DAY + tm_abs_i(qvals[4]) * TM_NS_HOUR +
           tm_abs_i(qvals[5]) * TM_NS_MIN + tm_abs_i(qvals[6]) * TM_NS_SEC +
           tm_abs_i(qvals[7]) * TM_NS_MS + tm_abs_i(qvals[8]) * TM_NS_US + tm_abs_i(qvals[9])
  js_throw_range("Duration time out of range") if tot_ns >= TM_MAX_TIME_NS
  p = proto != nil ? proto : js_realm().intrinsic("Temporal.Duration.prototype")
  o = js_new_special(p, "Temporal.Duration")
  o.internal = qvals
  o

-> tm_make_time(h, mi, s, ms, us, ns, proto = nil)
  js_throw_range("Invalid Temporal.PlainTime") if !tm_time_valid?(h, mi, s, ms, us, ns)
  p = proto != nil ? proto : js_realm().intrinsic("Temporal.PlainTime.prototype")
  o = js_new_special(p, "Temporal.PlainTime")
  o.internal = [h, mi, s, ms, us, ns]
  o

-> tm_make_date(y, m, d, cal, proto = nil)
  js_throw_range("Invalid ISO date") if !tm_iso_date_valid?(y, m, d)
  js_throw_range("Date out of Temporal range") if !tm_iso_date_within_limits?(y, m, d)
  p = proto != nil ? proto : js_realm().intrinsic("Temporal.PlainDate.prototype")
  o = js_new_special(p, "Temporal.PlainDate")
  o.internal = [y, m, d, cal]
  o

-> tm_make_dt(y, m, d, h, mi, s, ms, us, ns, cal, proto = nil)
  js_throw_range("Invalid ISO date") if !tm_iso_date_valid?(y, m, d)
  js_throw_range("Invalid time") if !tm_time_valid?(h, mi, s, ms, us, ns)
  js_throw_range("DateTime out of Temporal range") if !tm_iso_dt_within_limits?(y, m, d, h, mi, s, ms, us, ns)
  p = proto != nil ? proto : js_realm().intrinsic("Temporal.PlainDateTime.prototype")
  o = js_new_special(p, "Temporal.PlainDateTime")
  o.internal = [y, m, d, h, mi, s, ms, us, ns, cal]
  o

-> tm_make_ym(y, m, ref_d, cal, proto = nil)
  js_throw_range("Invalid ISO date") if !tm_iso_date_valid?(y, m, ref_d)
  js_throw_range("YearMonth out of Temporal range") if !tm_iso_ym_within_limits?(y, m)
  p = proto != nil ? proto : js_realm().intrinsic("Temporal.PlainYearMonth.prototype")
  o = js_new_special(p, "Temporal.PlainYearMonth")
  o.internal = [y, m, ref_d, cal]
  o

-> tm_make_md(ref_y, m, d, cal, proto = nil)
  js_throw_range("Invalid ISO date") if !tm_iso_date_valid?(ref_y, m, d)
  js_throw_range("MonthDay out of Temporal range") if !tm_iso_date_within_limits?(ref_y, m, d)
  p = proto != nil ? proto : js_realm().intrinsic("Temporal.PlainMonthDay.prototype")
  o = js_new_special(p, "Temporal.PlainMonthDay")
  o.internal = [ref_y, m, d, cal]
  o

-> tm_make_zdt(ns, tz, cal, proto = nil)
  js_throw_range("ZonedDateTime epochNanoseconds out of range") if !tm_epoch_ns_valid?(ns)
  p = proto != nil ? proto : js_realm().intrinsic("Temporal.ZonedDateTime.prototype")
  o = js_new_special(p, "Temporal.ZonedDateTime")
  o.internal = [ns, tz, cal]
  o

# ---- Temporal.Now ----

-> tm_now_tz_id
  icu_default_timezone()

-> tm_now_zdt_iso(tz_arg)
  tz = tz_arg == nil ? tm_now_tz_id() : tm_parse_tz_arg(tz_arg)
  tm_make_zdt(tm_now_epoch_ns(), tz, "iso8601")

-> tm_now_dt_iso(tz_arg)
  tz = tz_arg == nil ? tm_now_tz_id() : tm_parse_tz_arg(tz_arg)
  ns = tm_now_epoch_ns()
  off = tm_tz_get_offset_ns(tz, ns)
  dt = tm_iso_dt_from_epoch_ns(ns + off)
  tm_make_dt(dt[0], dt[1], dt[2], dt[3], dt[4], dt[5], dt[6], dt[7], dt[8], "iso8601")

-> tm_now_date_iso(tz_arg)
  tz = tz_arg == nil ? tm_now_tz_id() : tm_parse_tz_arg(tz_arg)
  ns = tm_now_epoch_ns()
  off = tm_tz_get_offset_ns(tz, ns)
  dt = tm_iso_dt_from_epoch_ns(ns + off)
  tm_make_date(dt[0], dt[1], dt[2], "iso8601")

-> tm_now_time_iso(tz_arg)
  tz = tz_arg == nil ? tm_now_tz_id() : tm_parse_tz_arg(tz_arg)
  ns = tm_now_epoch_ns()
  off = tm_tz_get_offset_ns(tz, ns)
  dt = tm_iso_dt_from_epoch_ns(ns + off)
  tm_make_time(dt[3], dt[4], dt[5], dt[6], dt[7], dt[8])

# ---- Temporal.Instant ----

# ToTemporalInstant ( item ) -> ## int epochNanoseconds
-> tm_to_instant_ns(item)
  if js_special?(item, "Temporal.Instant")
    return item.internal[0]
  if js_special?(item, "Temporal.ZonedDateTime")
    return item.internal[0]
  prim = js_to_primitive(item, "string")
  js_throw_type("Temporal.Instant.from requires a string, Instant, or ZonedDateTime") if !js_string?(prim)
  r = tm_parse_iso_datetime(prim)
  # Instant string MUST have either Z or an explicit UTC offset!
  js_throw_range("Instant string must include Z or UTC offset: " + prim) if !r["z"] && r["off_ns"] == nil
  off = r["z"] ? (0 ## int) : r["off_ns"]
  ns = tm_iso_epoch_ns(r["y"], r["m"], r["d"], r["h"], r["mi"], r["s"], r["ms"], r["us"], r["ns"]) - off
  js_throw_range("Instant epochNanoseconds out of range") if !tm_epoch_ns_valid?(ns)
  ns

-> tm_instant_ctor(args, nt)
  js_throw_type("Constructor Temporal.Instant requires 'new'") if nt == nil
  v = js_to_bigint(js_arg(args, 0))
  ns = v.v
  js_throw_range("Instant epochNanoseconds out of range") if !tm_epoch_ns_valid?(ns)
  tm_make_instant(ns, js_realm().proto_from(nt, "Temporal.Instant"))

-> tm_instant_from_epoch_ms(ms_arg)
  n = js_to_number(ms_arg)
  js_throw_range("epochMilliseconds must be a safe finite integer") if !js_finite?(n) || js_math_trunc(n) != n
  ns = js_bi_from_num(n).v * TM_NS_MS
  tm_make_instant(ns)

-> tm_instant_from_epoch_ns(ns_arg)
  v = js_to_bigint(ns_arg)
  tm_make_instant(v.v)

-> tm_instant_add_sub(this, dur_arg, sign)
  ns = tm_check(this, "Temporal.Instant", sign > 0 ? "add" : "subtract")[0]
  dv = tm_to_duration_vals(dur_arg)
  if dv[0] != (0 ## int) || dv[1] != (0 ## int) || dv[2] != (0 ## int) || dv[3] != (0 ## int)
    js_throw_range("Cannot add calendar units (years/months/weeks/days) to Temporal.Instant")
  delta = dv[4] * TM_NS_HOUR + dv[5] * TM_NS_MIN + dv[6] * TM_NS_SEC +
          dv[7] * TM_NS_MS + dv[8] * TM_NS_US + dv[9]
  delta = (0 ## int) - delta if sign < 0
  tm_make_instant(ns + delta)

# Balance a pure-time nanosecond difference into a Duration with largestUnit in {hour..nanosecond}
-> tm_balance_time_duration(ns_diff, largest_unit)
  neg = ns_diff < (0 ## int)
  a = tm_abs_i(ns_diff)
  rk = TM_UNIT_RANK[largest_unit]
  d = 0 ## int
  h = 0 ## int
  mi = 0 ## int
  s = 0 ## int
  ms = 0 ## int
  us = 0 ## int
  ns = 0 ## int
  if rk <= 3
    d = a / TM_NS_DAY
    a = a % TM_NS_DAY
  if rk <= 4
    h = a / TM_NS_HOUR
    a = a % TM_NS_HOUR
  if rk <= 5
    mi = a / TM_NS_MIN
    a = a % TM_NS_MIN
  if rk <= 6
    s = a / TM_NS_SEC
    a = a % TM_NS_SEC
  if rk <= 7
    ms = a / TM_NS_MS
    a = a % TM_NS_MS
  if rk <= 8
    us = a / TM_NS_US
    a = a % TM_NS_US
  ns = a
  if neg
    d = (0 ## int) - d
    h = (0 ## int) - h
    mi = (0 ## int) - mi
    s = (0 ## int) - s
    ms = (0 ## int) - ms
    us = (0 ## int) - us
    ns = (0 ## int) - ns
  [0 ## int, 0 ## int, 0 ## int, d, h, mi, s, ms, us, ns]

-> tm_instant_diff(this, other_arg, opts_arg, op)
  ns1 = tm_check(this, "Temporal.Instant", op == :until ? "until" : "since")[0]
  ns2 = tm_to_instant_ns(other_arg)
  cfg = tm_get_diff_settings(op, opts_arg, :time, nil, "nanosecond", "second")
  su = cfg[0]
  lu = cfg[1]
  rmode = cfg[2]
  rinc = cfg[3]
  diff = ns2 - ns1
  inc_ns = TM_UNIT_NS[su] * (rinc ## int)
  rounded = tm_round_to_inc(diff, inc_ns, rmode)
  rounded = (0 ## int) - rounded if op == :since
  tm_make_duration(tm_balance_time_duration(rounded, lu))

-> tm_instant_round(this, arg)
  ns = tm_check(this, "Temporal.Instant", "round")[0]
  cfg = tm_parse_round_to(arg, :time, false)
  su = cfg[0]
  rinc = cfg[1]
  rmode = cfg[2]
  # Instant rounding allows increment dividing 86400s (1 day) for any time unit!
  max_inc = (TM_NS_DAY / TM_UNIT_NS[su]).to_i
  tm_validate_rounding_inc(rinc, max_inc, true)
  inc_ns = TM_UNIT_NS[su] * (rinc ## int)
  tm_make_instant(tm_round_unsigned_to_inc(ns, inc_ns, rmode))

-> tm_instant_to_string(this, opts_arg)
  ns = tm_check(this, "Temporal.Instant", "toString")[0]
  opts = tm_get_options_obj(opts_arg)
  # Read ALL options in alphabetical order BEFORE unit-group validation!
  digits = tm_get_frac_sec_digits(opts)
  rmode = tm_get_rounding_mode(opts, "trunc")
  su = tm_get_unit(opts, "smallestUnit", :any, nil, false)
  tz_v = jget(opts, "timeZone")
  tz = tz_v == nil ? nil : tm_parse_tz_arg(tz_v)
  tm_validate_unit_group(su, :time)
  js_throw_range("hour is not valid smallestUnit for Instant.prototype.toString") if su == "hour"
  sp = tm_sec_str_prec(digits, su)
  prec = sp[0]
  unit = sp[1]
  inc = sp[2]
  r_ns = tm_round_unsigned_to_inc(ns, TM_UNIT_NS[unit] * (inc ## int), rmode)
  if tz == nil
    dt = tm_iso_dt_from_epoch_ns(r_ns)
    return tm_fmt_iso_date(dt[0], dt[1], dt[2]) + "T" + tm_fmt_time(dt[3], dt[4], dt[5], dt[6], dt[7], dt[8], prec) + "Z"
  off = tm_tz_get_offset_ns(tz, r_ns)
  dt = tm_iso_dt_from_epoch_ns(r_ns + off)
  # Per Instant.prototype.toString: offset is rounded to nearest minute (halfExpand) if it has sub-minute seconds!
  off_min = tm_round_to_inc(off, TM_NS_MIN, "halfExpand")
  tm_fmt_iso_date(dt[0], dt[1], dt[2]) + "T" + tm_fmt_time(dt[3], dt[4], dt[5], dt[6], dt[7], dt[8], prec) + tm_fmt_offset_ns(off_min)

# ---- Temporal.Duration ----

# Parse ISO duration string -> Array[10] of exact ## int (throws RangeError on invalid!)
-> tm_parse_dur_str(s)
  # Use exact ## int parser (supports arbitrary-precision integers & U+2212 minus!)
  js_throw_range("Invalid duration string: " + s) if s.size < 2
  sp = tm_parse_sign(s, 0)
  sign = sp != nil ? sp[0] : 1
  i = sp != nil ? sp[1] : 0
  n = s.size
  js_throw_range("Invalid duration string: " + s) if i >= n
  cp = s.byte_at(i)
  js_throw_range("Invalid duration string: " + s) if cp != 80 && cp != 112
  i += 1
  js_throw_range("Invalid duration string: " + s) if i >= n
  vals = Array.new(10, 0 ## int)
  in_time = false
  any_comp = false
  any_time = false
  last_d = -1
  last_t = -1
  had_frac = false
  while i < n
    c = s.byte_at(i)
    if c == 84 || c == 116
      js_throw_range("Invalid duration string: " + s) if in_time
      in_time = true
      i += 1
      js_throw_range("Invalid duration string: " + s) if i >= n
      next
    js_throw_range("Invalid duration string: " + s) if had_frac
    dstart = i
    while i < n && tm_is_digit?(s.byte_at(i))
      i += 1
    js_throw_range("Invalid duration string: " + s) if i == dstart || i >= n
    int_str = s.slice(dstart, i - dstart)
    frac_str = nil
    if s.byte_at(i) == 46 || s.byte_at(i) == 44
      js_throw_range("Invalid duration string: " + s) if !in_time
      i += 1
      fstart = i
      while i < n && tm_is_digit?(s.byte_at(i))
        i += 1
      flen = i - fstart
      js_throw_range("Invalid duration string: " + s) if flen == 0 || flen > 9 || i >= n
      frac_str = s.slice(fstart, flen)
      had_frac = true
    des = s.byte_at(i)
    i += 1
    iv = js_parse_int_str(int_str)
    iv = (0 ## int) - iv if sign < 0
    if !in_time
      idx = -1
      if des == 89 || des == 121
        idx = 0
      elsif des == 77 || des == 109
        idx = 1
      elsif des == 87 || des == 119
        idx = 2
      elsif des == 68 || des == 100
        idx = 3
      else
        js_throw_range("Invalid duration string: " + s)
      js_throw_range("Invalid duration string: " + s) if idx <= last_d
      last_d = idx
      vals[idx] = iv
      any_comp = true
    else
      idx = -1
      if des == 72 || des == 104
        idx = 4
      elsif des == 77 || des == 109
        idx = 5
      elsif des == 83 || des == 115
        idx = 6
      else
        js_throw_range("Invalid duration string: " + s)
      js_throw_range("Invalid duration string: " + s) if idx <= last_t
      last_t = idx
      vals[idx] = iv
      if frac_str != nil
        f9 = frac_str
        while f9.size < 9
          f9 = f9 + "0"
        fn = f9.to_i ## int
        if idx == 4
          tot = fn * (3600 ## int)
          mi = tot / TM_NS_MIN
          rem = tot % TM_NS_MIN
          sc = rem / TM_NS_SEC
          rem = rem % TM_NS_SEC
          ms = rem / TM_NS_MS
          rem = rem % TM_NS_MS
          us = rem / TM_NS_US
          ns = rem % TM_NS_US
          if sign < 0
            mi = (0 ## int) - mi
            sc = (0 ## int) - sc
            ms = (0 ## int) - ms
            us = (0 ## int) - us
            ns = (0 ## int) - ns
          vals[5] = mi
          vals[6] = sc
          vals[7] = ms
          vals[8] = us
          vals[9] = ns
        elsif idx == 5
          tot = fn * (60 ## int)
          sc = tot / TM_NS_SEC
          rem = tot % TM_NS_SEC
          ms = rem / TM_NS_MS
          rem = rem % TM_NS_MS
          us = rem / TM_NS_US
          ns = rem % TM_NS_US
          if sign < 0
            sc = (0 ## int) - sc
            ms = (0 ## int) - ms
            us = (0 ## int) - us
            ns = (0 ## int) - ns
          vals[6] = sc
          vals[7] = ms
          vals[8] = us
          vals[9] = ns
        else
          ms = fn / TM_NS_MS
          rem = fn % TM_NS_MS
          us = rem / TM_NS_US
          ns = rem % TM_NS_US
          if sign < 0
            ms = (0 ## int) - ms
            us = (0 ## int) - us
            ns = (0 ## int) - ns
          vals[7] = ms
          vals[8] = us
          vals[9] = ns
      any_comp = true
      any_time = true
  js_throw_range("Invalid duration string: " + s) if !any_comp || (in_time && !any_time)
  vals

# ToTemporalDuration ( item ) -> Array[10] of exact ## int (validated via tm_make_duration)
TM_DUR_ALPHA_FIELDS = [
  ["days", 3], ["hours", 4], ["microseconds", 8], ["milliseconds", 7],
  ["minutes", 5], ["months", 1], ["nanoseconds", 9], ["seconds", 6],
  ["weeks", 2], ["years", 0]
]

-> tm_to_duration_vals(item)
  if js_special?(item, "Temporal.Duration")
    return item.internal.dup
  if js_string?(item)
    vals = tm_parse_dur_str(item)
    return tm_make_duration(vals).internal
  js_throw_type("Temporal.Duration.from requires an object or string") if !js_object?(item)
  vals = Array.new(10, 0 ## int)
  any = false
  i = 0
  while i < 10
    nm = TM_DUR_ALPHA_FIELDS[i][0]
    idx = TM_DUR_ALPHA_FIELDS[i][1]
    v = jget(item, nm)
    if v != nil
      any = true
      vals[idx] = tm_to_int_integral(v)
    i += 1
  js_throw_type("Duration object must have at least one valid duration property") if !any
  tm_make_duration(vals).internal

-> tm_dur_ctor(args, nt)
  js_throw_type("Constructor Temporal.Duration requires 'new'") if nt == nil
  vals = Array.new(10, 0 ## int)
  i = 0
  while i < 10
    a = js_arg(args, i)
    vals[i] = tm_to_int_integral(a) if a != nil
    i += 1
  tm_make_duration(vals, js_realm().proto_from(nt, "Temporal.Duration"))

-> tm_dur_sign(dv)
  i = 0
  while i < 10
    return 1 if dv[i] > (0 ## int)
    return -1 if dv[i] < (0 ## int)
    i += 1
  0

-> tm_dur_default_largest(dv)
  names = ["year", "month", "week", "day", "hour", "minute", "second", "millisecond", "microsecond", "nanosecond"]
  i = 0
  while i < 10
    return names[i] if dv[i] != (0 ## int)
    i += 1
  "nanosecond"

-> tm_dur_with(this, like_arg)
  cur = tm_check(this, "Temporal.Duration", "with")
  js_throw_type("Duration.prototype.with requires an object") if !js_object?(like_arg)
  vals = cur.dup
  any = false
  i = 0
  while i < 10
    nm = TM_DUR_ALPHA_FIELDS[i][0]
    idx = TM_DUR_ALPHA_FIELDS[i][1]
    v = jget(like_arg, nm)
    if v != nil
      any = true
      vals[idx] = tm_to_int_integral(v)
    i += 1
  js_throw_type("Duration.prototype.with requires at least one valid duration property") if !any
  tm_make_duration(vals)

-> tm_dur_negated(this)
  dv = tm_check(this, "Temporal.Duration", "negated")
  out = Array.new(10, 0 ## int)
  i = 0
  while i < 10
    out[i] = (0 ## int) - dv[i]
    i += 1
  tm_make_duration(out)

-> tm_dur_abs(this)
  dv = tm_check(this, "Temporal.Duration", "abs")
  out = Array.new(10, 0 ## int)
  i = 0
  while i < 10
    out[i] = tm_abs_i(dv[i])
    i += 1
  tm_make_duration(out)

# Parse GetTemporalRelativeToOption ( opts ) -> [plain_date_or_nil, zdt_or_nil]
-> tm_get_relative_to(opts)
  v = jget(opts, "relativeTo")
  return [nil, nil] if v == nil
  if js_special?(v, "Temporal.PlainDate")
    return [v, nil]
  if js_special?(v, "Temporal.ZonedDateTime")
    return [nil, v]
  if js_special?(v, "Temporal.PlainDateTime")
    d = v.internal
    return [tm_make_date(d[0], d[1], d[2], d[9]), nil]
  if js_string?(v)
    r = tm_parse_iso_datetime(v)
    cal = r["cal_ann"] != nil ? tm_cal_canon_id(r["cal_ann"]) : "iso8601"
    if r["tz_ann"] != nil
      tz = tm_resolve_tz_id(r["tz_ann"])
      off_beh = r["z"] ? :exact : (r["off_ns"] != nil ? :option : :wall)
      off_ns = r["z"] ? (0 ## int) : r["off_ns"]
      ns = tm_interpret_iso_dt_offset(r["y"], r["m"], r["d"], r["h"], r["mi"], r["s"], r["ms"], r["us"], r["ns"],
                                      off_beh, off_ns, tz, "compatible", "reject", r["off_has_sec"])
      return [nil, tm_make_zdt(ns, tz, cal)]
    js_throw_range("UTC designator Z without time zone annotation not allowed in relativeTo") if r["z"]
    return [tm_make_date(r["y"], r["m"], r["d"], cal), nil]
  js_throw_type("relativeTo must be a string or object") if !js_object?(v)
  # Property bag: read calendar, date fields, time fields, offset, timeZone in spec order!
  cal_v = jget(v, "calendar")
  cal = cal_v == nil ? "iso8601" : tm_to_cal_id(cal_v)
  fields = {}
  dv = jget(v, "day")
  fields["day"] = tm_to_pos_int_trunc(dv).to_i if dv != nil
  if tm_cal_has_eras?(cal)
    ev = jget(v, "era")
    fields["era"] = tm_to_prim_require_str(ev) if ev != nil
    eyv = jget(v, "eraYear")
    fields["eraYear"] = tm_to_int_trunc(eyv).to_i if eyv != nil
  has_t = false
  th = 0
  tus = 0
  tms = 0
  tmi = 0
  tns = 0
  ts = 0
  tv = jget(v, "hour")
  if tv != nil
    has_t = true
    th = tm_to_int_trunc(tv).to_i
  tv = jget(v, "microsecond")
  if tv != nil
    has_t = true
    tus = tm_to_int_trunc(tv).to_i
  tv = jget(v, "millisecond")
  if tv != nil
    has_t = true
    tms = tm_to_int_trunc(tv).to_i
  tv = jget(v, "minute")
  if tv != nil
    has_t = true
    tmi = tm_to_int_trunc(tv).to_i
  mv = jget(v, "month")
  fields["month"] = tm_to_pos_int_trunc(mv).to_i if mv != nil
  mcv = jget(v, "monthCode")
  fields["monthCode"] = tm_parse_mcode_syntax(tm_to_prim_require_str(mcv)) if mcv != nil
  tv = jget(v, "nanosecond")
  if tv != nil
    has_t = true
    tns = tm_to_int_trunc(tv).to_i
  off_v = jget(v, "offset")
  off_ns = nil
  if off_v != nil
    os = tm_to_prim_require_str(off_v)
    op = tm_parse_utc_offset(os, 0, true)
    js_throw_range("Invalid offset in relativeTo: " + os) if op == nil || op[2] != os.size
    off_ns = op[0]
  tv = jget(v, "second")
  if tv != nil
    has_t = true
    ts = tm_to_int_trunc(tv).to_i
  tz_v = jget(v, "timeZone")
  tz = tz_v != nil ? tm_parse_tz_arg(tz_v) : nil
  yv = jget(v, "year")
  fields["year"] = tm_to_int_trunc(yv).to_i if yv != nil
  ymd = tm_cal_fields_to_iso(cal, fields, "constrain", :date)
  if tz != nil
    if has_t
      ct = tm_constrain_time(th, tmi, ts, tms, tus, tns, "constrain")
      off_beh = off_ns != nil ? :option : :wall
      ns = tm_interpret_iso_dt_offset(ymd[0], ymd[1], ymd[2], ct[0], ct[1], ct[2], ct[3], ct[4], ct[5],
                                      off_beh, off_ns, tz, "compatible", "reject", true)
      return [nil, tm_make_zdt(ns, tz, cal)]
    if off_ns != nil
      ns = tm_interpret_iso_dt_offset(ymd[0], ymd[1], ymd[2], 0, 0, 0, 0, 0, 0,
                                      :option, off_ns, tz, "compatible", "reject", true)
      return [nil, tm_make_zdt(ns, tz, cal)]
    ns = tm_zdt_start_of_day_ns(tz, ymd[0], ymd[1], ymd[2])
    return [nil, tm_make_zdt(ns, tz, cal)]
  [tm_make_date(ymd[0], ymd[1], ymd[2], cal), nil]

# Helper: Compute total nanoseconds of duration relative to (plain_date, zdt)!
# Returns [end_ns_or_days, total_ns]
-> tm_dur_time_ns(dv)
  dv[4] * TM_NS_HOUR + dv[5] * TM_NS_MIN + dv[6] * TM_NS_SEC +
  dv[7] * TM_NS_MS + dv[8] * TM_NS_US + dv[9]

-> tm_dur_has_cal_units?(dv)
  dv[0] != (0 ## int) || dv[1] != (0 ## int) || dv[2] != (0 ## int)

# Duration.prototype.add / subtract (no relativeTo — rejects calendar units!)
-> tm_dur_add_sub(this, other_arg, sign)
  d1 = tm_check(this, "Temporal.Duration", sign > 0 ? "add" : "subtract")
  d2 = tm_to_duration_vals(other_arg)
  if tm_dur_has_cal_units?(d1) || tm_dur_has_cal_units?(d2)
    js_throw_range("Duration.prototype.add/subtract does not support years, months, or weeks")
  lu1 = tm_dur_default_largest(d1)
  lu2 = tm_dur_default_largest(d2)
  lu = TM_UNIT_RANK[lu1] < TM_UNIT_RANK[lu2] ? lu1 : lu2
  ns1 = d1[3] * TM_NS_DAY + tm_dur_time_ns(d1)
  ns2 = d2[3] * TM_NS_DAY + tm_dur_time_ns(d2)
  tot = sign > 0 ? (ns1 + ns2) : (ns1 - ns2)
  js_throw_range("Resulting duration out of range") if tm_abs_i(tot) >= TM_MAX_TIME_NS
  tm_make_duration(tm_balance_time_duration(tot, lu))

# Round / balance duration relative to PlainDate or ZonedDateTime (or no relativeTo!)
-> tm_dur_round_relative(dv, su, lu, rinc, rmode, rel_pd, rel_zdt)
  has_cal = tm_dur_has_cal_units?(dv)
  need_rel = has_cal || TM_UNIT_RANK[lu] <= 2 || TM_UNIT_RANK[su] <= 2
  if rel_zdt != nil
    # ZonedDateTime relative rounding!
    z = rel_zdt.internal
    start_ns = z[0]
    tz = z[1]
    cal = z[2]
    end_ns = tm_zdt_add_dur_ns(start_ns, tz, cal, dv, "constrain")
    return tm_zdt_diff_dur_vals(start_ns, end_ns, tz, cal, su, lu, rinc, rmode, true)
  if rel_pd != nil
    # PlainDate relative rounding (midnight in UTC, 24h days)!
    pd = rel_pd.internal
    y1 = pd[0]
    m1 = pd[1]
    d1 = pd[2]
    cal = pd[3]
    # Check if duration is completely zero -> early return (per Temporal spec!)
    t_ns = tm_dur_time_ns(dv)
    if !has_cal && dv[3] == (0 ## int) && t_ns == (0 ## int)
      return Array.new(10, 0 ## int)
    # Converting PlainDate relativeTo to PlainDateTime (00:00:00) must satisfy ISODateTimeWithinLimits!
    js_throw_range("relativeTo PlainDate outside PlainDateTime range") if !tm_iso_dt_within_limits?(y1, m1, d1, 0, 0, 0, 0, 0, 0)
    extra_d = tm_floor_div(t_ns, TM_NS_DAY)
    rem_t = t_ns - extra_d * TM_NS_DAY
    end_ymd = tm_cal_date_add(cal, y1, m1, d1, dv[0], dv[1], dv[2], dv[3] + extra_d, "constrain")
    ns_a = tm_epoch_days(y1, m1, d1) * TM_NS_DAY
    ns_b = tm_epoch_days(end_ymd[0], end_ymd[1], end_ymd[2]) * TM_NS_DAY + rem_t
    tot_ns = ns_b - ns_a
    # Preserve calendar rounding window when dv already carries years/months (TC39 issue #3168)!
    if (dv[0] != (0 ## int) || dv[1] != (0 ## int)) && (su == "year" || su == "month")
      sign = tot_ns >= (0 ## int) ? 1 : -1
      if su == "year"
        yc = dv[0]
        # Advance/retreat yc so [add(yc), add(yc + sign)] brackets ns_b!
        while true
          a1 = tm_cal_date_add(cal, y1, m1, d1, yc, 0 ## int, 0 ## int, 0 ## int, "constrain")
          n1 = tm_epoch_days(a1[0], a1[1], a1[2]) * TM_NS_DAY
          if (sign > 0 && n1 > ns_b) || (sign < 0 && n1 < ns_b)
            yc = yc - (sign ## int)
          else
            a2 = tm_cal_date_add(cal, y1, m1, d1, yc + (sign ## int), 0 ## int, 0 ## int, 0 ## int, "constrain")
            n2 = tm_epoch_days(a2[0], a2[1], a2[2]) * TM_NS_DAY
            if (sign > 0 && n2 <= ns_b) || (sign < 0 && n2 >= ns_b)
              yc = yc + (sign ## int)
            else
              break
        base_q = yc / (rinc ## int)
        base_y = base_q * (rinc ## int)
        next_y = base_y + ((sign * rinc) ## int)
        a1 = tm_cal_date_add(cal, y1, m1, d1, base_y, 0 ## int, 0 ## int, 0 ## int, "constrain")
        a2 = tm_cal_date_add(cal, y1, m1, d1, next_y, 0 ## int, 0 ## int, 0 ## int, "constrain")
        n1 = tm_epoch_days(a1[0], a1[1], a1[2]) * TM_NS_DAY
        n2 = tm_epoch_days(a2[0], a2[1], a2[2]) * TM_NS_DAY
        span = tm_abs_i(n2 - n1)
        ry = span == (0 ## int) ? base_y : (tm_round_div(base_q * span + (ns_b - n1), span, rmode) * (rinc ## int))
        return [ry, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
      # su == "month"
      yc = lu == "year" ? dv[0] : (0 ## int)
      mc = lu == "year" ? dv[1] : dv[1]
      if lu == "month" && dv[0] != (0 ## int)
        # Convert years into months first
        d_mo = tm_cal_date_until(cal, y1, m1, d1, end_ymd[0], end_ymd[1], end_ymd[2], "month")
        mc = d_mo[1] ## int
      while true
        a1 = tm_cal_date_add(cal, y1, m1, d1, yc, mc, 0 ## int, 0 ## int, "constrain")
        n1 = tm_epoch_days(a1[0], a1[1], a1[2]) * TM_NS_DAY
        if (sign > 0 && n1 > ns_b) || (sign < 0 && n1 < ns_b)
          mc = mc - (sign ## int)
        else
          a2 = tm_cal_date_add(cal, y1, m1, d1, yc, mc + (sign ## int), 0 ## int, 0 ## int, "constrain")
          n2 = tm_epoch_days(a2[0], a2[1], a2[2]) * TM_NS_DAY
          if (sign > 0 && n2 <= ns_b) || (sign < 0 && n2 >= ns_b)
            mc = mc + (sign ## int)
          else
            break
      base_q = mc / (rinc ## int)
      base_m = base_q * (rinc ## int)
      next_m = base_m + ((sign * rinc) ## int)
      a1 = tm_cal_date_add(cal, y1, m1, d1, yc, base_m, 0 ## int, 0 ## int, "constrain")
      a2 = tm_cal_date_add(cal, y1, m1, d1, yc, next_m, 0 ## int, 0 ## int, "constrain")
      n1 = tm_epoch_days(a1[0], a1[1], a1[2]) * TM_NS_DAY
      n2 = tm_epoch_days(a2[0], a2[1], a2[2]) * TM_NS_DAY
      span = tm_abs_i(n2 - n1)
      rm = span == (0 ## int) ? base_m : (tm_round_div(base_q * span + (ns_b - n1), span, rmode) * (rinc ## int))
      if lu == "year" && rm != (0 ## int)
        # Re-balance if rm reached a full year
        end_r = tm_cal_date_add(cal, y1, m1, d1, yc, rm, 0 ## int, 0 ## int, "constrain")
        re = tm_cal_date_until(cal, y1, m1, d1, end_r[0], end_r[1], end_r[2], "year")
        return [re[0] ## int, re[1] ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int] if re[0] != yc.to_i && tm_abs_i(re[0] ## int) > tm_abs_i(yc)
      return [yc, rm, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
    # Now compute difference from (y1,m1,d1,0) to (end_ymd, rem_t) with su, lu, rinc, rmode!
    return tm_dt_diff_dur_vals(y1, m1, d1, 0, 0, 0, 0, 0, 0,
                               end_ymd[0], end_ymd[1], end_ymd[2], 0, 0, 0, 0, 0, 0, rem_t,
                               cal, su, lu, rinc, rmode)
  js_throw_range("relativeTo is required when rounding years, months, or weeks") if need_rel
  # Pure days + time (24h days)!
  tot_ns = dv[3] * TM_NS_DAY + tm_dur_time_ns(dv)
  inc_ns = TM_UNIT_NS[su] * (rinc ## int)
  rounded = tm_round_to_inc(tot_ns, inc_ns, rmode)
  js_throw_range("Rounded duration out of range") if tm_abs_i(rounded) >= TM_MAX_TIME_NS
  tm_balance_time_duration(rounded, lu)

-> tm_dur_round(this, arg)
  dv = tm_check(this, "Temporal.Duration", "round")
  js_throw_type("Duration.prototype.round requires an argument") if arg == nil
  if js_string?(arg)
    opts = js_new_object(nil)
    opts.define("smallestUnit", arg, ATTR_W + ATTR_E + ATTR_C)
  elsif js_object?(arg)
    opts = arg
  else
    js_throw_type("Duration.prototype.round argument must be string or object")
  # Read options in exact spec alphabetical order: largestUnit, relativeTo, roundingIncrement, roundingMode, smallestUnit!
  lu_opt = tm_get_unit(opts, "largestUnit", :datetime, nil, true)
  rel = tm_get_relative_to(opts)
  rinc = tm_get_rounding_increment(opts)
  rmode = tm_get_rounding_mode(opts, "halfExpand")
  su_opt = tm_get_unit(opts, "smallestUnit", :datetime, nil, false)
  js_throw_range("At least one of largestUnit or smallestUnit must be provided") if lu_opt == nil && su_opt == nil
  su = su_opt != nil ? su_opt : "nanosecond"
  def_lu = tm_dur_default_largest(dv)
  lu = nil
  if lu_opt == nil || lu_opt == "auto"
    lu = TM_UNIT_RANK[def_lu] < TM_UNIT_RANK[su] ? def_lu : su
  else
    lu = lu_opt
  js_throw_range("largestUnit must be >= smallestUnit") if TM_UNIT_RANK[lu] > TM_UNIT_RANK[su]
  if TM_UNIT_MAX_INC.has_key?(su)
    tm_validate_rounding_inc(rinc, TM_UNIT_MAX_INC[su], false)
  elsif rinc > 1 && lu != su
    js_throw_range("Cannot round to an increment of " + su + " while also balancing to " + lu)
  res = tm_dur_round_relative(dv, su, lu, rinc, rmode, rel[0], rel[1])
  tm_make_duration(res)

-> tm_dur_total(this, arg)
  dv = tm_check(this, "Temporal.Duration", "total")
  js_throw_type("Duration.prototype.total requires an argument") if arg == nil
  if js_string?(arg)
    opts = js_new_object(nil)
    opts.define("unit", arg, ATTR_W + ATTR_E + ATTR_C)
  elsif js_object?(arg)
    opts = arg
  else
    js_throw_type("Duration.prototype.total argument must be string or object")
  # Read options in alphabetical order: relativeTo, unit!
  rel = tm_get_relative_to(opts)
  unit = tm_get_unit(opts, "unit", :datetime, :required, false)
  has_cal = tm_dur_has_cal_units?(dv)
  need_rel = has_cal || TM_UNIT_RANK[unit] <= 2
  t_ns = tm_dur_time_ns(dv)
  is_blank = !has_cal && dv[3] == (0 ## int) && t_ns == (0 ## int)
  if rel[1] != nil
    z = rel[1].internal
    start_ns = z[0]
    tz = z[1]
    cal = z[2]
    end_ns = tm_zdt_add_dur_ns(start_ns, tz, cal, dv, "constrain")
    return tm_zdt_total_in_unit(start_ns, end_ns, tz, cal, unit)
  if rel[0] != nil
    return ~0.0 if is_blank
    pd = rel[0].internal
    y1 = pd[0]
    m1 = pd[1]
    d1 = pd[2]
    cal = pd[3]
    js_throw_range("relativeTo PlainDate outside PlainDateTime range") if !tm_iso_dt_within_limits?(y1, m1, d1, 0, 0, 0, 0, 0, 0)
    extra_d = tm_floor_div(t_ns, TM_NS_DAY)
    rem_t = t_ns - extra_d * TM_NS_DAY
    end_ymd = tm_cal_date_add(cal, y1, m1, d1, dv[0], dv[1], dv[2], dv[3] + extra_d, "constrain")
    # Preserve calendar rounding window when dv already carries years/months (TC39 issue #3168)!
    if (dv[0] != (0 ## int) || dv[1] != (0 ## int)) && (unit == "year" || unit == "month")
      ns1 = tm_epoch_days(y1, m1, d1) * TM_NS_DAY
      ns2 = tm_epoch_days(end_ymd[0], end_ymd[1], end_ymd[2]) * TM_NS_DAY + rem_t
      tot_ns = ns2 - ns1
      return ~0.0 if tot_ns == (0 ## int)
      sign = tot_ns >= (0 ## int) ? 1 : -1
      whole = unit == "year" ? dv[0] : (dv[0] == (0 ## int) ? dv[1] : (tm_cal_date_until(cal, y1, m1, d1, end_ymd[0], end_ymd[1], end_ymd[2], "month")[1] ## int))
      while true
        a1 = unit == "year" ? tm_cal_date_add(cal, y1, m1, d1, whole, 0 ## int, 0 ## int, 0 ## int, "constrain") : tm_cal_date_add(cal, y1, m1, d1, 0 ## int, whole, 0 ## int, 0 ## int, "constrain")
        n1 = tm_epoch_days(a1[0], a1[1], a1[2]) * TM_NS_DAY
        if (sign > 0 && n1 > ns2) || (sign < 0 && n1 < ns2)
          whole = whole - (sign ## int)
        else
          a2 = unit == "year" ? tm_cal_date_add(cal, y1, m1, d1, whole + (sign ## int), 0 ## int, 0 ## int, 0 ## int, "constrain") : tm_cal_date_add(cal, y1, m1, d1, 0 ## int, whole + (sign ## int), 0 ## int, 0 ## int, "constrain")
          n2 = tm_epoch_days(a2[0], a2[1], a2[2]) * TM_NS_DAY
          if (sign > 0 && n2 <= ns2) || (sign < 0 && n2 >= ns2)
            whole = whole + (sign ## int)
          else
            span = tm_abs_i(n2 - n1)
            return tm_int_to_num(whole) if span == (0 ## int)
            return tm_exact_div_to_num(whole * span + (ns2 - n1), span)
    return tm_dt_total_in_unit(y1, m1, d1, end_ymd[0], end_ymd[1], end_ymd[2], rem_t, cal, unit)
  js_throw_range("relativeTo is required for calendar units in Duration.prototype.total") if need_rel
  tot_ns = dv[3] * TM_NS_DAY + t_ns
  tm_exact_div_to_num(tot_ns, TM_UNIT_NS[unit])

-> tm_dur_compare(arg1, arg2, opts_arg)
  d1 = tm_to_duration_vals(arg1)
  d2 = tm_to_duration_vals(arg2)
  opts = tm_get_options_obj(opts_arg)
  rel = tm_get_relative_to(opts)
  # Per Temporal.Duration.compare step 7: identical internal slots immediately return +0 without requiring relativeTo!
  same = true
  si = 0
  while si < 10
    if d1[si] != d2[si]
      same = false
      break
    si += 1
  return ~0.0 if same
  has_cal1 = tm_dur_has_cal_units?(d1)
  has_cal2 = tm_dur_has_cal_units?(d2)
  if rel[0] == nil && rel[1] == nil
    if has_cal1 || has_cal2
      js_throw_range("relativeTo is required when comparing durations with years, months, or weeks")
    n1 = d1[3] * TM_NS_DAY + tm_dur_time_ns(d1)
    n2 = d2[3] * TM_NS_DAY + tm_dur_time_ns(d2)
    return n1 < n2 ? ~-1.0 : (n1 > n2 ? ~1.0 : ~0.0)
  if rel[1] != nil
    if !has_cal1 && !has_cal2 && d1[3] == (0 ## int) && d2[3] == (0 ## int)
      n1 = tm_dur_time_ns(d1)
      n2 = tm_dur_time_ns(d2)
      return n1 < n2 ? ~-1.0 : (n1 > n2 ? ~1.0 : ~0.0)
    z = rel[1].internal
    e1 = tm_zdt_add_dur_ns(z[0], z[1], z[2], d1, "constrain")
    e2 = tm_zdt_add_dur_ns(z[0], z[1], z[2], d2, "constrain")
    return e1 < e2 ? ~-1.0 : (e1 > e2 ? ~1.0 : ~0.0)
  if !has_cal1 && !has_cal2
    n1 = d1[3] * TM_NS_DAY + tm_dur_time_ns(d1)
    n2 = d2[3] * TM_NS_DAY + tm_dur_time_ns(d2)
    return n1 < n2 ? ~-1.0 : (n1 > n2 ? ~1.0 : ~0.0)
  pd = rel[0].internal
  cal = pd[3]
  t1 = tm_dur_time_ns(d1)
  x1 = tm_floor_div(t1, TM_NS_DAY)
  r1 = t1 - x1 * TM_NS_DAY
  t2 = tm_dur_time_ns(d2)
  x2 = tm_floor_div(t2, TM_NS_DAY)
  r2 = t2 - x2 * TM_NS_DAY
  y1 = tm_cal_date_add(cal, pd[0], pd[1], pd[2], d1[0], d1[1], d1[2], d1[3] + x1, "constrain")
  y2 = tm_cal_date_add(cal, pd[0], pd[1], pd[2], d2[0], d2[1], d2[2], d2[3] + x2, "constrain")
  n1 = tm_epoch_days(y1[0], y1[1], y1[2]) * TM_NS_DAY + r1
  n2 = tm_epoch_days(y2[0], y2[1], y2[2]) * TM_NS_DAY + r2
  n1 < n2 ? ~-1.0 : (n1 > n2 ? ~1.0 : ~0.0)

-> tm_dur_to_string(this, opts_arg)
  dv = tm_check(this, "Temporal.Duration", "toString")
  opts = tm_get_options_obj(opts_arg)
  digits = tm_get_frac_sec_digits(opts)
  rmode = tm_get_rounding_mode(opts, "trunc")
  su = tm_get_unit(opts, "smallestUnit", :any, nil, false)
  tm_validate_unit_group(su, :time)
  js_throw_range("smallestUnit for Duration.prototype.toString must be second, millisecond, microsecond, or nanosecond") if su == "hour" || su == "minute"
  sp = tm_sec_str_prec(digits, su)
  prec = sp[0]
  unit = sp[1]
  inc = sp[2]
  # Round & balance time portion up to largestUnit (capped at "day" for durations with date units!)
  cur = dv.dup
  if unit != "nanosecond" || inc != 1
    lu = tm_dur_default_largest(dv)
    lu_rk = TM_UNIT_RANK[lu]
    bal_lu = lu_rk <= 3 ? "day" : (lu_rk < 6 ? lu : "second")
    base_ns = bal_lu == "day" ? (cur[3] * TM_NS_DAY + tm_dur_time_ns(cur)) : (bal_lu == "second" ? (cur[6] * TM_NS_SEC + cur[7] * TM_NS_MS + cur[8] * TM_NS_US + cur[9]) : tm_dur_time_ns(cur))
    r_ns = tm_round_to_inc(base_ns, TM_UNIT_NS[unit] * (inc ## int), rmode)
    js_throw_range("Rounded duration out of range") if tm_abs_i(r_ns) >= TM_MAX_TIME_NS
    bt = tm_balance_time_duration(r_ns, bal_lu)
    if bal_lu == "day"
      cur[3] = bt[3]; cur[4] = bt[4]; cur[5] = bt[5]; cur[6] = bt[6]; cur[7] = bt[7]; cur[8] = bt[8]; cur[9] = bt[9]
    elsif bal_lu == "second"
      cur[6] = bt[6]; cur[7] = bt[7]; cur[8] = bt[8]; cur[9] = bt[9]
    else
      cur[4] = bt[4]; cur[5] = bt[5]; cur[6] = bt[6]; cur[7] = bt[7]; cur[8] = bt[8]; cur[9] = bt[9]
    # Validate rounded duration fits in float64-representable slots & IsValidDuration!
    tm_make_duration(cur)
  sign = tm_dur_sign(cur)
  # Combine seconds + ms + us + ns for ISO serialization
  tot_s_ns = cur[6] * TM_NS_SEC + cur[7] * TM_NS_MS + cur[8] * TM_NS_US + cur[9]
  a_s_ns = tm_abs_i(tot_s_ns)
  sec_int = a_s_ns / TM_NS_SEC
  sub_ns = (a_s_ns % TM_NS_SEC).to_i
  ms_p = sub_ns / 1000000
  us_p = (sub_ns / 1000) % 1000
  ns_p = sub_ns % 1000
  dp = ""
  dp = dp + js_bigint_to_string(JS:BigIntValue.new(tm_abs_i(cur[0])), nil) + "Y" if cur[0] != (0 ## int)
  dp = dp + js_bigint_to_string(JS:BigIntValue.new(tm_abs_i(cur[1])), nil) + "M" if cur[1] != (0 ## int)
  dp = dp + js_bigint_to_string(JS:BigIntValue.new(tm_abs_i(cur[2])), nil) + "W" if cur[2] != (0 ## int)
  dp = dp + js_bigint_to_string(JS:BigIntValue.new(tm_abs_i(cur[3])), nil) + "D" if cur[3] != (0 ## int)
  tp = ""
  tp = tp + js_bigint_to_string(JS:BigIntValue.new(tm_abs_i(cur[4])), nil) + "H" if cur[4] != (0 ## int)
  tp = tp + js_bigint_to_string(JS:BigIntValue.new(tm_abs_i(cur[5])), nil) + "M" if cur[5] != (0 ## int)
  need_s = a_s_ns != (0 ## int) || (dp.size == 0 && tp.size == 0) || prec != :auto
  if need_s
    tp = tp + js_bigint_to_string(JS:BigIntValue.new(sec_int), nil) + tm_fmt_subsec(ms_p, us_p, ns_p, prec) + "S"
  res = (sign < 0 ? "-P" : "P") + dp
  res = res + "T" + tp if tp.size > 0
  res

# ---- Temporal.PlainTime ----

# Read time property bag fields in alphabetical order: hour, microsecond, millisecond, minute, nanosecond, second
# Returns [h, mi, s, ms, us, ns, any_defined_bool]
-> tm_read_time_fields(obj, def_val = 0)
  any = false
  hv = jget(obj, "hour")
  h = def_val
  if hv != nil
    any = true
    h = tm_to_int_trunc(hv).to_i
  usv = jget(obj, "microsecond")
  us = def_val
  if usv != nil
    any = true
    us = tm_to_int_trunc(usv).to_i
  msv = jget(obj, "millisecond")
  ms = def_val
  if msv != nil
    any = true
    ms = tm_to_int_trunc(msv).to_i
  miv = jget(obj, "minute")
  mi = def_val
  if miv != nil
    any = true
    mi = tm_to_int_trunc(miv).to_i
  nsv = jget(obj, "nanosecond")
  ns = def_val
  if nsv != nil
    any = true
    ns = tm_to_int_trunc(nsv).to_i
  sv = jget(obj, "second")
  s = def_val
  if sv != nil
    any = true
    s = tm_to_int_trunc(sv).to_i
  [h, mi, s, ms, us, ns, any]

# ToTemporalTime ( item, overflow ) -> [h, mi, s, ms, us, ns]
-> tm_to_time_fields(item, overflow = "constrain")
  if js_special?(item, "Temporal.PlainTime")
    return item.internal.dup
  if js_special?(item, "Temporal.PlainDateTime")
    d = item.internal
    return [d[3], d[4], d[5], d[6], d[7], d[8]]
  if js_special?(item, "Temporal.ZonedDateTime")
    z = item.internal
    off = tm_tz_get_offset_ns(z[1], z[0])
    dt = tm_iso_dt_from_epoch_ns(z[0] + off)
    return [dt[3], dt[4], dt[5], dt[6], dt[7], dt[8]]
  if js_string?(item)
    return tm_parse_iso_time(item)
  js_throw_type("Invalid argument for Temporal.PlainTime") if !js_object?(item)
  tf = tm_read_time_fields(item, 0)
  js_throw_type("PlainTime object must specify at least one time field") if !tf[6]
  tm_constrain_time(tf[0], tf[1], tf[2], tf[3], tf[4], tf[5], overflow)

-> tm_time_ctor(args, nt)
  js_throw_type("Constructor Temporal.PlainTime requires 'new'") if nt == nil
  h  = js_arg(args, 0) == nil ? 0 : tm_to_int_trunc(js_arg(args, 0)).to_i
  mi = js_arg(args, 1) == nil ? 0 : tm_to_int_trunc(js_arg(args, 1)).to_i
  s  = js_arg(args, 2) == nil ? 0 : tm_to_int_trunc(js_arg(args, 2)).to_i
  ms = js_arg(args, 3) == nil ? 0 : tm_to_int_trunc(js_arg(args, 3)).to_i
  us = js_arg(args, 4) == nil ? 0 : tm_to_int_trunc(js_arg(args, 4)).to_i
  ns = js_arg(args, 5) == nil ? 0 : tm_to_int_trunc(js_arg(args, 5)).to_i
  tm_make_time(h, mi, s, ms, us, ns, js_realm().proto_from(nt, "Temporal.PlainTime"))

-> tm_time_from(item, opts_arg)
  # Per ToTemporalTime: read/parse item BEFORE reading options!
  if js_special?(item, "Temporal.PlainTime")
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    t = item.internal
    return tm_make_time(t[0], t[1], t[2], t[3], t[4], t[5])
  if js_special?(item, "Temporal.PlainDateTime")
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    d = item.internal
    return tm_make_time(d[3], d[4], d[5], d[6], d[7], d[8])
  if js_special?(item, "Temporal.ZonedDateTime")
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    z = item.internal
    off = tm_tz_get_offset_ns(z[1], z[0])
    dt = tm_iso_dt_from_epoch_ns(z[0] + off)
    return tm_make_time(dt[3], dt[4], dt[5], dt[6], dt[7], dt[8])
  if js_string?(item)
    tf = tm_parse_iso_time(item)
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    return tm_make_time(tf[0], tf[1], tf[2], tf[3], tf[4], tf[5])
  js_throw_type("Invalid argument for Temporal.PlainTime") if !js_object?(item)
  tf = tm_read_time_fields(item, 0)
  js_throw_type("PlainTime object must specify at least one time field") if !tf[6]
  opts = tm_get_options_obj(opts_arg)
  ov = tm_get_overflow(opts)
  ct = tm_constrain_time(tf[0], tf[1], tf[2], tf[3], tf[4], tf[5], ov)
  tm_make_time(ct[0], ct[1], ct[2], ct[3], ct[4], ct[5])

-> tm_time_cmp_arr(a, b)
  i = 0
  while i < 6
    return -1 if a[i] < b[i]
    return 1 if a[i] > b[i]
    i += 1
  0

-> tm_time_compare(a, b)
  t1 = tm_to_time_fields(a, "constrain")
  t2 = tm_to_time_fields(b, "constrain")
  tm_time_cmp_arr(t1, t2) + ~0.0

-> tm_time_ns(t)
  (t[0] ## int) * TM_NS_HOUR + (t[1] ## int) * TM_NS_MIN + (t[2] ## int) * TM_NS_SEC +
  (t[3] ## int) * TM_NS_MS + (t[4] ## int) * TM_NS_US + (t[5] ## int)

-> tm_time_add_sub(this, dur_arg, sign)
  t = tm_check(this, "Temporal.PlainTime", sign > 0 ? "add" : "subtract")
  dv = tm_to_duration_vals(dur_arg)
  delta = tm_dur_time_ns(dv)
  delta = (0 ## int) - delta if sign < 0
  b = tm_balance_time(t[0], t[1], t[2], t[3], t[4], (t[5] ## int) + delta)
  tm_make_time(b[1], b[2], b[3], b[4], b[5], b[6])

-> tm_time_with(this, like_arg, opts_arg)
  t = tm_check(this, "Temporal.PlainTime", "with")
  js_throw_type("PlainTime.prototype.with requires an object") if !js_object?(like_arg)
  tm_reject_temporal_like_with(like_arg)
  any = false
  h = t[0]
  mi = t[1]
  s = t[2]
  ms = t[3]
  us = t[4]
  ns = t[5]
  v = jget(like_arg, "hour")
  if v != nil
    any = true
    h = tm_to_int_trunc(v).to_i
  v = jget(like_arg, "microsecond")
  if v != nil
    any = true
    us = tm_to_int_trunc(v).to_i
  v = jget(like_arg, "millisecond")
  if v != nil
    any = true
    ms = tm_to_int_trunc(v).to_i
  v = jget(like_arg, "minute")
  if v != nil
    any = true
    mi = tm_to_int_trunc(v).to_i
  v = jget(like_arg, "nanosecond")
  if v != nil
    any = true
    ns = tm_to_int_trunc(v).to_i
  v = jget(like_arg, "second")
  if v != nil
    any = true
    s = tm_to_int_trunc(v).to_i
  js_throw_type("PlainTime.prototype.with requires at least one time property") if !any
  opts = tm_get_options_obj(opts_arg)
  ov = tm_get_overflow(opts)
  ct = tm_constrain_time(h, mi, s, ms, us, ns, ov)
  tm_make_time(ct[0], ct[1], ct[2], ct[3], ct[4], ct[5])

-> tm_reject_temporal_like_with(obj)
  if js_special?(obj, "Temporal.PlainDate") || js_special?(obj, "Temporal.PlainTime") ||
     js_special?(obj, "Temporal.PlainDateTime") || js_special?(obj, "Temporal.PlainYearMonth") ||
     js_special?(obj, "Temporal.PlainMonthDay") || js_special?(obj, "Temporal.ZonedDateTime") ||
     js_special?(obj, "Temporal.Instant") || js_special?(obj, "Temporal.Duration")
    js_throw_type("Cannot pass a Temporal object directly to with()")
  js_throw_type("calendar property not allowed in with()") if jget(obj, "calendar") != nil
  js_throw_type("timeZone property not allowed in with()") if jget(obj, "timeZone") != nil
  nil

-> tm_time_diff(this, other_arg, opts_arg, op)
  t1 = tm_check(this, "Temporal.PlainTime", op == :until ? "until" : "since")
  t2 = tm_to_time_fields(other_arg, "constrain")
  cfg = tm_get_diff_settings(op, opts_arg, :time, nil, "nanosecond", "hour")
  su = cfg[0]
  lu = cfg[1]
  rmode = cfg[2]
  rinc = cfg[3]
  diff = tm_time_ns(t2) - tm_time_ns(t1)
  inc_ns = TM_UNIT_NS[su] * (rinc ## int)
  rounded = tm_round_to_inc(diff, inc_ns, rmode)
  rounded = (0 ## int) - rounded if op == :since
  tm_make_duration(tm_balance_time_duration(rounded, lu))

-> tm_time_round(this, arg)
  t = tm_check(this, "Temporal.PlainTime", "round")
  cfg = tm_parse_round_to(arg, :time, false)
  su = cfg[0]
  rinc = cfg[1]
  rmode = cfg[2]
  tm_validate_rounding_inc(rinc, TM_UNIT_MAX_INC[su], false)
  r_ns = tm_round_to_inc(tm_time_ns(t), TM_UNIT_NS[su] * (rinc ## int), rmode)
  b = tm_balance_time(0, 0, 0, 0, 0, r_ns)
  tm_make_time(b[1], b[2], b[3], b[4], b[5], b[6])

-> tm_time_to_string(this, opts_arg)
  t = tm_check(this, "Temporal.PlainTime", "toString")
  opts = tm_get_options_obj(opts_arg)
  digits = tm_get_frac_sec_digits(opts)
  rmode = tm_get_rounding_mode(opts, "trunc")
  su = tm_get_unit(opts, "smallestUnit", :time, nil, false)
  js_throw_range("hour is not valid smallestUnit for PlainTime.prototype.toString") if su == "hour"
  sp = tm_sec_str_prec(digits, su)
  prec = sp[0]
  unit = sp[1]
  inc = sp[2]
  r_ns = tm_round_to_inc(tm_time_ns(t), TM_UNIT_NS[unit] * (inc ## int), rmode)
  b = tm_balance_time(0, 0, 0, 0, 0, r_ns)
  tm_fmt_time(b[1], b[2], b[3], b[4], b[5], b[6], prec)

# ---- Temporal.PlainDate ----

# Read calendar date fields from property bag in alphabetical order:
# day, [era, eraYear], month, monthCode, year
-> tm_read_date_fields(obj, cal, need_day = true)
  f = {}
  if need_day
    v = jget(obj, "day")
    f["day"] = tm_to_pos_int_trunc(v).to_i if v != nil
  if tm_cal_has_eras?(cal)
    v = jget(obj, "era")
    f["era"] = tm_to_prim_require_str(v) if v != nil
    v = jget(obj, "eraYear")
    f["eraYear"] = tm_to_int_trunc(v).to_i if v != nil
  v = jget(obj, "month")
  f["month"] = tm_to_pos_int_trunc(v).to_i if v != nil
  v = jget(obj, "monthCode")
  f["monthCode"] = tm_parse_mcode_syntax(tm_to_prim_require_str(v)) if v != nil
  v = jget(obj, "year")
  f["year"] = tm_to_int_trunc(v).to_i if v != nil
  f

# ToTemporalDate ( item, opts_arg ) -> [y, m, d, cal]
-> tm_to_date_vals(item, opts_arg = nil)
  if js_special?(item, "Temporal.PlainDate")
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    return item.internal.dup
  if js_special?(item, "Temporal.PlainDateTime")
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    d = item.internal
    return [d[0], d[1], d[2], d[9]]
  if js_special?(item, "Temporal.ZonedDateTime")
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    z = item.internal
    off = tm_tz_get_offset_ns(z[1], z[0])
    dt = tm_iso_dt_from_epoch_ns(z[0] + off)
    return [dt[0], dt[1], dt[2], z[2]]
  if js_string?(item)
    r = tm_parse_iso_datetime(item)
    js_throw_range("UTC designator Z not allowed in PlainDate string") if r["z"]
    cal = r["cal_ann"] != nil ? tm_cal_canon_id(r["cal_ann"]) : "iso8601"
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    js_throw_range("Date out of Temporal range") if !tm_iso_date_within_limits?(r["y"], r["m"], r["d"])
    return [r["y"], r["m"], r["d"], cal]
  js_throw_type("Invalid argument for Temporal.PlainDate") if !js_object?(item)
  # Read calendar first, then date fields, then options!
  cal_v = jget(item, "calendar")
  cal = cal_v == nil ? "iso8601" : tm_to_cal_id(cal_v)
  fields = tm_read_date_fields(item, cal, true)
  opts = tm_get_options_obj(opts_arg)
  ov = tm_get_overflow(opts)
  ymd = tm_cal_fields_to_iso(cal, fields, ov, :date)
  [ymd[0], ymd[1], ymd[2], cal]

-> tm_date_ctor(args, nt)
  js_throw_type("Constructor Temporal.PlainDate requires 'new'") if nt == nil
  y = tm_to_int_trunc(js_arg(args, 0)).to_i
  m = tm_to_int_trunc(js_arg(args, 1)).to_i
  d = tm_to_int_trunc(js_arg(args, 2)).to_i
  cal_arg = js_arg(args, 3)
  cal = cal_arg == nil ? "iso8601" : tm_cal_canon_id(js_string?(cal_arg) ? cal_arg : js_throw_type("Calendar must be a string"))
  tm_make_date(y, m, d, cal, js_realm().proto_from(nt, "Temporal.PlainDate"))

-> tm_date_cmp_arr(a, b)
  return -1 if a[0] < b[0]
  return 1 if a[0] > b[0]
  return -1 if a[1] < b[1]
  return 1 if a[1] > b[1]
  return -1 if a[2] < b[2]
  return 1 if a[2] > b[2]
  0

-> tm_date_compare(a, b)
  d1 = tm_to_date_vals(a)
  d2 = tm_to_date_vals(b)
  tm_date_cmp_arr(d1, d2) + ~0.0

-> tm_date_add_sub(this, dur_arg, opts_arg, sign)
  d = tm_check(this, "Temporal.PlainDate", sign > 0 ? "add" : "subtract")
  dv = tm_to_duration_vals(dur_arg)
  opts = tm_get_options_obj(opts_arg)
  ov = tm_get_overflow(opts)
  # Balance time units into days (24h)!
  t_ns = tm_dur_time_ns(dv)
  extra_d = t_ns / TM_NS_DAY  # trunc toward zero! (Wait: spec uses BalanceTimeDuration -> trunc toward zero!)
  dy = sign > 0 ? dv[0] : ((0 ## int) - dv[0])
  dmo = sign > 0 ? dv[1] : ((0 ## int) - dv[1])
  dw = sign > 0 ? dv[2] : ((0 ## int) - dv[2])
  dd = sign > 0 ? (dv[3] + extra_d) : ((0 ## int) - (dv[3] + extra_d))
  ymd = tm_cal_date_add(d[3], d[0], d[1], d[2], dy, dmo, dw, dd, ov)
  tm_make_date(ymd[0], ymd[1], ymd[2], d[3])

-> tm_date_with(this, like_arg, opts_arg)
  d = tm_check(this, "Temporal.PlainDate", "with")
  js_throw_type("PlainDate.prototype.with requires an object") if !js_object?(like_arg)
  tm_reject_temporal_like_with(like_arg)
  cal = d[3]
  cur = tm_cal_iso_to_fields(cal, d[0], d[1], d[2])
  # cur = [era, eraYear, year, month, monthCode, day, ...]
  pf = tm_read_date_fields(like_arg, cal, true)
  js_throw_type("PlainDate.prototype.with requires at least one date property") if pf.size == 0
  # MergeCalendarFields (exact Temporal spec!)
  merged = {}
  merged["day"] = pf.has_key?("day") ? pf["day"] : cur[5]
  if pf.has_key?("month") || pf.has_key?("monthCode")
    merged["month"] = pf["month"] if pf.has_key?("month")
    merged["monthCode"] = pf["monthCode"] if pf.has_key?("monthCode")
  else
    merged["monthCode"] = cur[4]
  if pf.has_key?("year") || pf.has_key?("era") || pf.has_key?("eraYear")
    merged["year"] = pf["year"] if pf.has_key?("year")
    merged["era"] = pf["era"] if pf.has_key?("era")
    merged["eraYear"] = pf["eraYear"] if pf.has_key?("eraYear")
  else
    merged["year"] = cur[2]
  opts = tm_get_options_obj(opts_arg)
  ov = tm_get_overflow(opts)
  ymd = tm_cal_fields_to_iso(cal, merged, ov, :date)
  tm_make_date(ymd[0], ymd[1], ymd[2], cal)

# Round a calendar date difference [y, mo, w, d] from (y1, m1, d1) to (y2, m2, d2) with smallestUnit, roundingIncrement, roundingMode!
-> tm_round_date_diff(cal, y1, m1, d1, y2, m2, d2, diff4, su, lu, rinc, rmode)
  y = diff4[0] ## int
  mo = diff4[1] ## int
  w = diff4[2] ## int
  dd = diff4[3] ## int
  return [y, mo, w, dd, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int] if su == "day" && rinc == 1
  if su == "day"
    # Round days by rinc!
    if lu == "day"
      rd = tm_round_to_inc(dd, rinc ## int, rmode)
      return [0 ## int, 0 ## int, 0 ## int, rd, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
    # Round residual days and re-balance? Spec rounds relative to anchor!
    rd = tm_round_to_inc(dd, rinc ## int, rmode)
    return [y, mo, w, rd, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
  # Rounding to week, month, or year!
  ed1 = tm_epoch_days(y1, m1, d1)
  ed2 = tm_epoch_days(y2, m2, d2)
  sign = ed2 >= ed1 ? 1 : -1
  if su == "week"
    # Relative to anchor after y, mo: total remaining days -> weeks!
    anchor = (y != (0 ## int) || mo != (0 ## int)) ? tm_cal_date_add(cal, y1, m1, d1, y, mo, 0 ## int, 0 ## int, "constrain") : [y1, m1, d1]
    rem_d = ed2 - tm_epoch_days(anchor[0], anchor[1], anchor[2])
    rw = tm_round_div(rem_d, (7 * rinc) ## int, rmode) * (rinc ## int)
    return [y, mo, rw, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
  if su == "month"
    # Find bracket [n1, n2] in multiples of rinc months!
    base_q = mo / (rinc ## int)
    base_m = base_q * (rinc ## int)
    a1 = tm_cal_date_add(cal, y1, m1, d1, y, base_m, 0 ## int, 0 ## int, "constrain")
    e1 = tm_epoch_days(a1[0], a1[1], a1[2])
    prog = ed2 - e1 # signed!
    if prog == (0 ## int) && rinc == 1
      rm = base_m
    else
      next_m = base_m + ((sign * rinc) ## int)
      a2 = tm_cal_date_add(cal, y1, m1, d1, y, next_m, 0 ## int, 0 ## int, "constrain")
      e2 = tm_epoch_days(a2[0], a2[1], a2[2])
      span = tm_abs_i(e2 - e1)
      rm = span == (0 ## int) ? base_m : (tm_round_div(base_q * span + prog, span, rmode) * (rinc ## int))
    # Re-balance months into years if largestUnit == "year" and rm reached a full year!
    if lu == "year" && rm != mo
      end_r = tm_cal_date_add(cal, y1, m1, d1, y, rm, 0 ## int, 0 ## int, "constrain")
      re = tm_cal_date_until(cal, y1, m1, d1, end_r[0], end_r[1], end_r[2], "year")
      return [re[0] ## int, re[1] ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
    return [y, rm, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
  # su == "year"
  base_q = y / (rinc ## int)
  base_y = base_q * (rinc ## int)
  a1 = tm_cal_date_add(cal, y1, m1, d1, base_y, 0 ## int, 0 ## int, 0 ## int, "constrain")
  e1 = tm_epoch_days(a1[0], a1[1], a1[2])
  prog = ed2 - e1
  if prog == (0 ## int) && rinc == 1
    ry = base_y
  else
    next_y = base_y + ((sign * rinc) ## int)
    a2 = tm_cal_date_add(cal, y1, m1, d1, next_y, 0 ## int, 0 ## int, 0 ## int, "constrain")
    e2 = tm_epoch_days(a2[0], a2[1], a2[2])
    span = tm_abs_i(e2 - e1)
    ry = span == (0 ## int) ? base_y : (tm_round_div(base_q * span + prog, span, rmode) * (rinc ## int))
  [ry, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]

-> tm_date_diff(this, other_arg, opts_arg, op)
  d1 = tm_check(this, "Temporal.PlainDate", op == :until ? "until" : "since")
  d2 = tm_to_date_vals(other_arg)
  js_throw_range("Cannot compute difference between dates with different calendars") if d1[3] != d2[3]
  cfg = tm_get_diff_settings(op, opts_arg, :date, nil, "day", "day")
  su = cfg[0]
  lu = cfg[1]
  rmode = cfg[2]
  rinc = cfg[3]
  diff4 = tm_cal_date_until(d1[3], d1[0], d1[1], d1[2], d2[0], d2[1], d2[2], lu)
  vals = tm_round_date_diff(d1[3], d1[0], d1[1], d1[2], d2[0], d2[1], d2[2], diff4, su, lu, rinc, rmode)
  if op == :since
    i = 0
    while i < 10
      vals[i] = (0 ## int) - vals[i]
      i += 1
  tm_make_duration(vals)

-> tm_date_to_string(this, opts_arg)
  d = tm_check(this, "Temporal.PlainDate", "toString")
  opts = tm_get_options_obj(opts_arg)
  show_cal = tm_get_show_cal(opts)
  tm_fmt_iso_date(d[0], d[1], d[2]) + tm_fmt_cal_ann(d[3], show_cal)

# ---- Temporal.PlainDateTime ----

-> tm_to_dt_vals(item, opts_arg = nil)
  if js_special?(item, "Temporal.PlainDateTime")
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    return item.internal.dup
  if js_special?(item, "Temporal.PlainDate")
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    d = item.internal
    return [d[0], d[1], d[2], 0, 0, 0, 0, 0, 0, d[3]]
  if js_special?(item, "Temporal.ZonedDateTime")
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    z = item.internal
    off = tm_tz_get_offset_ns(z[1], z[0])
    dt = tm_iso_dt_from_epoch_ns(z[0] + off)
    return [dt[0], dt[1], dt[2], dt[3], dt[4], dt[5], dt[6], dt[7], dt[8], z[2]]
  if js_string?(item)
    r = tm_parse_iso_datetime(item)
    js_throw_range("UTC designator Z not allowed in PlainDateTime string") if r["z"]
    cal = r["cal_ann"] != nil ? tm_cal_canon_id(r["cal_ann"]) : "iso8601"
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    js_throw_range("DateTime out of Temporal range") if !tm_iso_dt_within_limits?(r["y"], r["m"], r["d"], r["h"], r["mi"], r["s"], r["ms"], r["us"], r["ns"])
    return [r["y"], r["m"], r["d"], r["h"], r["mi"], r["s"], r["ms"], r["us"], r["ns"], cal]
  js_throw_type("Invalid argument for Temporal.PlainDateTime") if !js_object?(item)
  cal_v = jget(item, "calendar")
  cal = cal_v == nil ? "iso8601" : tm_to_cal_id(cal_v)
  # Read date + time fields in alphabetical order!
  # day, [era, eraYear], hour, microsecond, millisecond, minute, month, monthCode, nanosecond, second, year
  f = {}
  v = jget(item, "day")
  f["day"] = tm_to_pos_int_trunc(v).to_i if v != nil
  if tm_cal_has_eras?(cal)
    v = jget(item, "era")
    f["era"] = tm_to_prim_require_str(v) if v != nil
    v = jget(item, "eraYear")
    f["eraYear"] = tm_to_int_trunc(v).to_i if v != nil
  h = 0
  us = 0
  ms = 0
  mi = 0
  ns = 0
  s = 0
  v = jget(item, "hour")
  h = tm_to_int_trunc(v).to_i if v != nil
  v = jget(item, "microsecond")
  us = tm_to_int_trunc(v).to_i if v != nil
  v = jget(item, "millisecond")
  ms = tm_to_int_trunc(v).to_i if v != nil
  v = jget(item, "minute")
  mi = tm_to_int_trunc(v).to_i if v != nil
  v = jget(item, "month")
  f["month"] = tm_to_pos_int_trunc(v).to_i if v != nil
  v = jget(item, "monthCode")
  f["monthCode"] = tm_parse_mcode_syntax(tm_to_prim_require_str(v)) if v != nil
  v = jget(item, "nanosecond")
  ns = tm_to_int_trunc(v).to_i if v != nil
  v = jget(item, "second")
  s = tm_to_int_trunc(v).to_i if v != nil
  v = jget(item, "year")
  f["year"] = tm_to_int_trunc(v).to_i if v != nil
  opts = tm_get_options_obj(opts_arg)
  ov = tm_get_overflow(opts)
  ymd = tm_cal_fields_to_iso(cal, f, ov, :date)
  ct = tm_constrain_time(h, mi, s, ms, us, ns, ov)
  js_throw_range("DateTime out of Temporal range") if !tm_iso_dt_within_limits?(ymd[0], ymd[1], ymd[2], ct[0], ct[1], ct[2], ct[3], ct[4], ct[5])
  [ymd[0], ymd[1], ymd[2], ct[0], ct[1], ct[2], ct[3], ct[4], ct[5], cal]

-> tm_dt_ctor(args, nt)
  js_throw_type("Constructor Temporal.PlainDateTime requires 'new'") if nt == nil
  y  = tm_to_int_trunc(js_arg(args, 0)).to_i
  m  = tm_to_int_trunc(js_arg(args, 1)).to_i
  d  = tm_to_int_trunc(js_arg(args, 2)).to_i
  h  = js_arg(args, 3) == nil ? 0 : tm_to_int_trunc(js_arg(args, 3)).to_i
  mi = js_arg(args, 4) == nil ? 0 : tm_to_int_trunc(js_arg(args, 4)).to_i
  s  = js_arg(args, 5) == nil ? 0 : tm_to_int_trunc(js_arg(args, 5)).to_i
  ms = js_arg(args, 6) == nil ? 0 : tm_to_int_trunc(js_arg(args, 6)).to_i
  us = js_arg(args, 7) == nil ? 0 : tm_to_int_trunc(js_arg(args, 7)).to_i
  ns = js_arg(args, 8) == nil ? 0 : tm_to_int_trunc(js_arg(args, 8)).to_i
  ca = js_arg(args, 9)
  cal = ca == nil ? "iso8601" : tm_cal_canon_id(js_string?(ca) ? ca : js_throw_type("Calendar must be a string"))
  tm_make_dt(y, m, d, h, mi, s, ms, us, ns, cal, js_realm().proto_from(nt, "Temporal.PlainDateTime"))

-> tm_dt_cmp_arr(a, b)
  i = 0
  while i < 9
    return -1 if a[i] < b[i]
    return 1 if a[i] > b[i]
    i += 1
  0

-> tm_dt_compare(a, b)
  d1 = tm_to_dt_vals(a)
  d2 = tm_to_dt_vals(b)
  tm_dt_cmp_arr(d1, d2) + ~0.0

-> tm_dt_add_sub(this, dur_arg, opts_arg, sign)
  dt = tm_check(this, "Temporal.PlainDateTime", sign > 0 ? "add" : "subtract")
  dv = tm_to_duration_vals(dur_arg)
  opts = tm_get_options_obj(opts_arg)
  ov = tm_get_overflow(opts)
  t_delta = tm_dur_time_ns(dv)
  t_delta = (0 ## int) - t_delta if sign < 0
  bt = tm_balance_time(dt[3], dt[4], dt[5], dt[6], dt[7], (dt[8] ## int) + t_delta)
  dy  = sign > 0 ? dv[0] : ((0 ## int) - dv[0])
  dmo = sign > 0 ? dv[1] : ((0 ## int) - dv[1])
  dw  = sign > 0 ? dv[2] : ((0 ## int) - dv[2])
  dd  = (sign > 0 ? dv[3] : ((0 ## int) - dv[3])) + bt[0]
  ymd = tm_cal_date_add(dt[9], dt[0], dt[1], dt[2], dy, dmo, dw, dd, ov)
  tm_make_dt(ymd[0], ymd[1], ymd[2], bt[1], bt[2], bt[3], bt[4], bt[5], bt[6], dt[9])

-> tm_dt_with(this, like_arg, opts_arg)
  dt = tm_check(this, "Temporal.PlainDateTime", "with")
  js_throw_type("PlainDateTime.prototype.with requires an object") if !js_object?(like_arg)
  tm_reject_temporal_like_with(like_arg)
  cal = dt[9]
  cur = tm_cal_iso_to_fields(cal, dt[0], dt[1], dt[2])
  pf = {}
  any = false
  h = dt[3]
  mi = dt[4]
  s = dt[5]
  ms = dt[6]
  us = dt[7]
  ns = dt[8]
  v = jget(like_arg, "day")
  if v != nil
    any = true
    pf["day"] = tm_to_pos_int_trunc(v).to_i
  if tm_cal_has_eras?(cal)
    v = jget(like_arg, "era")
    if v != nil
      any = true
      pf["era"] = tm_to_prim_require_str(v)
    v = jget(like_arg, "eraYear")
    if v != nil
      any = true
      pf["eraYear"] = tm_to_int_trunc(v).to_i
  v = jget(like_arg, "hour")
  if v != nil
    any = true
    h = tm_to_int_trunc(v).to_i
  v = jget(like_arg, "microsecond")
  if v != nil
    any = true
    us = tm_to_int_trunc(v).to_i
  v = jget(like_arg, "millisecond")
  if v != nil
    any = true
    ms = tm_to_int_trunc(v).to_i
  v = jget(like_arg, "minute")
  if v != nil
    any = true
    mi = tm_to_int_trunc(v).to_i
  v = jget(like_arg, "month")
  if v != nil
    any = true
    pf["month"] = tm_to_pos_int_trunc(v).to_i
  v = jget(like_arg, "monthCode")
  if v != nil
    any = true
    pf["monthCode"] = tm_parse_mcode_syntax(tm_to_prim_require_str(v))
  v = jget(like_arg, "nanosecond")
  if v != nil
    any = true
    ns = tm_to_int_trunc(v).to_i
  v = jget(like_arg, "second")
  if v != nil
    any = true
    s = tm_to_int_trunc(v).to_i
  v = jget(like_arg, "year")
  if v != nil
    any = true
    pf["year"] = tm_to_int_trunc(v).to_i
  js_throw_type("PlainDateTime.prototype.with requires at least one valid property") if !any
  merged = {}
  merged["day"] = pf.has_key?("day") ? pf["day"] : cur[5]
  if pf.has_key?("month") || pf.has_key?("monthCode")
    merged["month"] = pf["month"] if pf.has_key?("month")
    merged["monthCode"] = pf["monthCode"] if pf.has_key?("monthCode")
  else
    merged["monthCode"] = cur[4]
  if pf.has_key?("year") || pf.has_key?("era") || pf.has_key?("eraYear")
    merged["year"] = pf["year"] if pf.has_key?("year")
    merged["era"] = pf["era"] if pf.has_key?("era")
    merged["eraYear"] = pf["eraYear"] if pf.has_key?("eraYear")
  else
    merged["year"] = cur[2]
  opts = tm_get_options_obj(opts_arg)
  ov = tm_get_overflow(opts)
  ymd = tm_cal_fields_to_iso(cal, merged, ov, :date)
  ct = tm_constrain_time(h, mi, s, ms, us, ns, ov)
  tm_make_dt(ymd[0], ymd[1], ymd[2], ct[0], ct[1], ct[2], ct[3], ct[4], ct[5], cal)

# Core DifferenceISODateTime with rounding & balancing!
-> tm_dt_diff_dur_vals(y1, m1, d1, h1, mi1, s1, ms1, us1, ns1, y2, m2, d2, h2, mi2, s2, ms2, us2, ns2, extra_ns, cal, su, lu, rinc, rmode)
  ns_a = tm_iso_epoch_ns(y1, m1, d1, h1, mi1, s1, ms1, us1, ns1)
  ns_b = tm_iso_epoch_ns(y2, m2, d2, h2, mi2, s2, ms2, us2, ns2) + extra_ns
  tot_ns = ns_b - ns_a
  return Array.new(10, 0 ## int) if tot_ns == (0 ## int)
  rk_lu = TM_UNIT_RANK[lu]
  rk_su = TM_UNIT_RANK[su]
  # Pure time / days (no year/month/week)!
  if rk_lu >= 3 && rk_su >= 3
    inc_ns = TM_UNIT_NS[su] * (rinc ## int)
    r_ns = tm_round_to_inc(tot_ns, inc_ns, rmode)
    return tm_balance_time_duration(r_ns, lu)
  # Has year, month, or week!
  sign = tot_ns >= (0 ## int) ? 1 : -1
  # Adjust end date so time difference has same sign as overall difference!
  t1 = (h1 ## int) * TM_NS_HOUR + (mi1 ## int) * TM_NS_MIN + (s1 ## int) * TM_NS_SEC + (ms1 ## int) * TM_NS_MS + (us1 ## int) * TM_NS_US + (ns1 ## int)
  dt_b = tm_iso_dt_from_epoch_ns(ns_b)
  ey = dt_b[0]
  em = dt_b[1]
  ed = dt_b[2]
  t2 = (dt_b[3] ## int) * TM_NS_HOUR + (dt_b[4] ## int) * TM_NS_MIN + (dt_b[5] ## int) * TM_NS_SEC + (dt_b[6] ## int) * TM_NS_MS + (dt_b[7] ## int) * TM_NS_US + (dt_b[8] ## int)
  t_diff = t2 - t1
  day_adj = 0
  if sign > 0 && t_diff < (0 ## int)
    t_diff = t_diff + TM_NS_DAY
    day_adj = -1
  elsif sign < 0 && t_diff > (0 ## int)
    t_diff = t_diff - TM_NS_DAY
    day_adj = 1
  adj_ymd = day_adj != 0 ? tm_ymd_from_days(tm_epoch_days(ey, em, ed) + (day_adj ## int)) : [ey, em, ed]
  diff4 = tm_cal_date_until(cal, y1, m1, d1, adj_ymd[0], adj_ymd[1], adj_ymd[2], lu)
  # Now round according to su!
  if rk_su >= 4
    # Rounding a time unit (hour..ns): round t_diff, carry any full day into days and re-balance!
    inc_ns = TM_UNIT_NS[su] * (rinc ## int)
    rt = tm_round_to_inc(t_diff, inc_ns, rmode)
    carry_d = rt / TM_NS_DAY
    rem_t = rt % TM_NS_DAY
    if carry_d != (0 ## int)
      # Re-compute date diff with adjusted target date!
      new_end = tm_ymd_from_days(tm_epoch_days(adj_ymd[0], adj_ymd[1], adj_ymd[2]) + carry_d)
      diff4 = tm_cal_date_until(cal, y1, m1, d1, new_end[0], new_end[1], new_end[2], lu)
    bt = tm_balance_time_duration(rem_t, "hour")
    return [diff4[0] ## int, diff4[1] ## int, diff4[2] ## int, diff4[3] ## int, bt[4], bt[5], bt[6], bt[7], bt[8], bt[9]]
  if su == "day"
    # Round (diff4[3] days + t_diff) to nearest rinc days!
    rem_ns = (diff4[3] ## int) * TM_NS_DAY + t_diff
    rd = tm_round_div(rem_ns, TM_NS_DAY * (rinc ## int), rmode) * (rinc ## int)
    if lu != "day" && rd != (diff4[3] ## int)
      end_r = tm_cal_date_add(cal, y1, m1, d1, diff4[0] ## int, diff4[1] ## int, diff4[2] ## int, rd, "constrain")
      re = tm_cal_date_until(cal, y1, m1, d1, end_r[0], end_r[1], end_r[2], lu)
      return [re[0] ## int, re[1] ## int, re[2] ## int, re[3] ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
    return [diff4[0] ## int, diff4[1] ## int, diff4[2] ## int, rd, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
  # su is week, month, or year: include fractional time `t_diff` in progress!
  if su == "week"
    anchor = (diff4[0] != 0 || diff4[1] != 0) ? tm_cal_date_add(cal, y1, m1, d1, diff4[0] ## int, diff4[1] ## int, 0 ## int, 0 ## int, "constrain") : [y1, m1, d1]
    rem_ns = ns_b - tm_iso_epoch_ns(anchor[0], anchor[1], anchor[2], h1, mi1, s1, ms1, us1, ns1)
    rw = tm_round_div(rem_ns, TM_NS_DAY * ((7 * rinc) ## int), rmode) * (rinc ## int)
    return [diff4[0] ## int, diff4[1] ## int, rw, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
  if su == "month"
    base_q = (diff4[1] ## int) / (rinc ## int)
    base_m = base_q * (rinc ## int)
    next_m = base_m + ((sign * rinc) ## int)
    a1 = tm_cal_date_add(cal, y1, m1, d1, diff4[0] ## int, base_m, 0 ## int, 0 ## int, "constrain")
    a2 = tm_cal_date_add(cal, y1, m1, d1, diff4[0] ## int, next_m, 0 ## int, 0 ## int, "constrain")
    n1 = tm_iso_epoch_ns(a1[0], a1[1], a1[2], h1, mi1, s1, ms1, us1, ns1)
    n2 = tm_iso_epoch_ns(a2[0], a2[1], a2[2], h1, mi1, s1, ms1, us1, ns1)
    span = tm_abs_i(n2 - n1)
    rm = span == (0 ## int) ? base_m : (tm_round_div(base_q * span + (ns_b - n1), span, rmode) * (rinc ## int))
    if lu == "year"
      end_r = tm_cal_date_add(cal, y1, m1, d1, diff4[0] ## int, rm, 0 ## int, 0 ## int, "constrain")
      re = tm_cal_date_until(cal, y1, m1, d1, end_r[0], end_r[1], end_r[2], "year")
      return [re[0] ## int, re[1] ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
    return [diff4[0] ## int, rm, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
  # su == "year"
  base_q = (diff4[0] ## int) / (rinc ## int)
  base_y = base_q * (rinc ## int)
  next_y = base_y + ((sign * rinc) ## int)
  a1 = tm_cal_date_add(cal, y1, m1, d1, base_y, 0 ## int, 0 ## int, 0 ## int, "constrain")
  a2 = tm_cal_date_add(cal, y1, m1, d1, next_y, 0 ## int, 0 ## int, 0 ## int, "constrain")
  n1 = tm_iso_epoch_ns(a1[0], a1[1], a1[2], h1, mi1, s1, ms1, us1, ns1)
  n2 = tm_iso_epoch_ns(a2[0], a2[1], a2[2], h1, mi1, s1, ms1, us1, ns1)
  span = tm_abs_i(n2 - n1)
  ry = span == (0 ## int) ? base_y : (tm_round_div(base_q * span + (ns_b - n1), span, rmode) * (rinc ## int))
  [ry, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]

# Compute exact floating-point total in `unit` from (y1, m1, d1, 00:00) to (y2, m2, d2, rem_t)
-> tm_dt_total_in_unit(y1, m1, d1, y2, m2, d2, rem_t, cal, unit)
  ns1 = tm_epoch_days(y1, m1, d1) * TM_NS_DAY
  ns2 = tm_epoch_days(y2, m2, d2) * TM_NS_DAY + rem_t
  tot_ns = ns2 - ns1
  return ~0.0 if tot_ns == (0 ## int)
  if TM_UNIT_RANK[unit] >= 3
    return tm_exact_div_to_num(tot_ns, TM_UNIT_NS[unit])
  if unit == "week"
    return tm_exact_div_to_num(tot_ns, TM_NS_DAY * (7 ## int))
  sign = tot_ns >= (0 ## int) ? 1 : -1
  diff4 = tm_cal_date_until(cal, y1, m1, d1, y2, m2, d2, unit)
  whole = unit == "year" ? (diff4[0] ## int) : (diff4[1] ## int)
  a1 = unit == "year" ? tm_cal_date_add(cal, y1, m1, d1, whole, 0 ## int, 0 ## int, 0 ## int, "constrain") : tm_cal_date_add(cal, y1, m1, d1, 0 ## int, whole, 0 ## int, 0 ## int, "constrain")
  n1 = tm_epoch_days(a1[0], a1[1], a1[2]) * TM_NS_DAY
  if (sign > 0 && n1 > ns2) || (sign < 0 && n1 < ns2)
    whole = whole - (sign ## int)
    a1 = unit == "year" ? tm_cal_date_add(cal, y1, m1, d1, whole, 0 ## int, 0 ## int, 0 ## int, "constrain") : tm_cal_date_add(cal, y1, m1, d1, 0 ## int, whole, 0 ## int, 0 ## int, "constrain")
    n1 = tm_epoch_days(a1[0], a1[1], a1[2]) * TM_NS_DAY
  a2 = unit == "year" ? tm_cal_date_add(cal, y1, m1, d1, whole + (sign ## int), 0 ## int, 0 ## int, 0 ## int, "constrain") : tm_cal_date_add(cal, y1, m1, d1, 0 ## int, whole + (sign ## int), 0 ## int, 0 ## int, "constrain")
  n2 = tm_epoch_days(a2[0], a2[1], a2[2]) * TM_NS_DAY
  span = tm_abs_i(n2 - n1)
  return tm_int_to_num(whole) if span == (0 ## int)
  tm_exact_div_to_num(whole * span + (ns2 - n1), span)

-> tm_dt_diff(this, other_arg, opts_arg, op)
  d1 = tm_check(this, "Temporal.PlainDateTime", op == :until ? "until" : "since")
  d2 = tm_to_dt_vals(other_arg)
  js_throw_range("Cannot compute difference between PlainDateTimes with different calendars") if d1[9] != d2[9]
  cfg = tm_get_diff_settings(op, opts_arg, :datetime, nil, "nanosecond", "day")
  su = cfg[0]
  lu = cfg[1]
  rmode = cfg[2]
  rinc = cfg[3]
  vals = tm_dt_diff_dur_vals(d1[0], d1[1], d1[2], d1[3], d1[4], d1[5], d1[6], d1[7], d1[8],
                             d2[0], d2[1], d2[2], d2[3], d2[4], d2[5], d2[6], d2[7], d2[8], 0 ## int,
                             d1[9], su, lu, rinc, rmode)
  if op == :since
    i = 0
    while i < 10
      vals[i] = (0 ## int) - vals[i]
      i += 1
  tm_make_duration(vals)

-> tm_dt_round(this, arg)
  dt = tm_check(this, "Temporal.PlainDateTime", "round")
  cfg = tm_parse_round_to(arg, :time, true)
  su = cfg[0]
  rinc = cfg[1]
  rmode = cfg[2]
  if su == "day"
    tm_validate_rounding_inc(rinc, 1, true)
  else
    tm_validate_rounding_inc(rinc, TM_UNIT_MAX_INC[su], false)
  t_ns = (dt[3] ## int) * TM_NS_HOUR + (dt[4] ## int) * TM_NS_MIN + (dt[5] ## int) * TM_NS_SEC +
         (dt[6] ## int) * TM_NS_MS + (dt[7] ## int) * TM_NS_US + (dt[8] ## int)
  r_ns = tm_round_to_inc(t_ns, TM_UNIT_NS[su] * (rinc ## int), rmode)
  bt = tm_balance_time(0, 0, 0, 0, 0, r_ns)
  ymd = bt[0] != (0 ## int) ? tm_ymd_from_days(tm_epoch_days(dt[0], dt[1], dt[2]) + bt[0]) : [dt[0], dt[1], dt[2]]
  tm_make_dt(ymd[0], ymd[1], ymd[2], bt[1], bt[2], bt[3], bt[4], bt[5], bt[6], dt[9])

-> tm_dt_to_string(this, opts_arg)
  dt = tm_check(this, "Temporal.PlainDateTime", "toString")
  opts = tm_get_options_obj(opts_arg)
  # Exact alphabetical order: calendarName, fractionalSecondDigits, roundingMode, smallestUnit!
  show_cal = tm_get_show_cal(opts)
  digits = tm_get_frac_sec_digits(opts)
  rmode = tm_get_rounding_mode(opts, "trunc")
  su = tm_get_unit(opts, "smallestUnit", :time, nil, false)
  js_throw_range("hour is not valid smallestUnit for PlainDateTime.prototype.toString") if su == "hour"
  sp = tm_sec_str_prec(digits, su)
  prec = sp[0]
  unit = sp[1]
  inc = sp[2]
  t_ns = (dt[3] ## int) * TM_NS_HOUR + (dt[4] ## int) * TM_NS_MIN + (dt[5] ## int) * TM_NS_SEC +
         (dt[6] ## int) * TM_NS_MS + (dt[7] ## int) * TM_NS_US + (dt[8] ## int)
  r_ns = tm_round_to_inc(t_ns, TM_UNIT_NS[unit] * (inc ## int), rmode)
  bt = tm_balance_time(0, 0, 0, 0, 0, r_ns)
  ymd = bt[0] != (0 ## int) ? tm_ymd_from_days(tm_epoch_days(dt[0], dt[1], dt[2]) + bt[0]) : [dt[0], dt[1], dt[2]]
  js_throw_range("DateTime out of Temporal range") if !tm_iso_dt_within_limits?(ymd[0], ymd[1], ymd[2], bt[1], bt[2], bt[3], bt[4], bt[5], bt[6])
  tm_fmt_iso_date(ymd[0], ymd[1], ymd[2]) + "T" + tm_fmt_time(bt[1], bt[2], bt[3], bt[4], bt[5], bt[6], prec) + tm_fmt_cal_ann(dt[9], show_cal)
