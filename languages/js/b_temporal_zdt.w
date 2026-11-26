# runtime/b_temporal_zdt — TC39 Temporal (Part 2):
# Temporal.PlainYearMonth, Temporal.PlainMonthDay, Temporal.ZonedDateTime,
# Intl.DateTimeFormat Temporal formatting hook, Date.prototype.toTemporalInstant,
# and master Temporal realm installer.

in JS

# ---- Temporal.PlainYearMonth ----

-> tm_to_ym_vals(item, opts_arg = nil)
  if js_special?(item, "Temporal.PlainYearMonth")
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    return item.internal.dup
  if js_string?(item)
    ym = tm_parse_iso_ym(item)
    cal = ym[3] != nil ? tm_cal_canon_id(ym[3]) : "iso8601"
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    if !ym[4] && cal != "iso8601"
      js_throw_range("Non-ISO calendar requires full date in PlainYearMonth string: " + item)
    if cal == "iso8601"
      js_throw_range("YearMonth out of Temporal range") if !tm_iso_ym_within_limits?(ym[0], ym[1])
      return [ym[0], ym[1], 1, "iso8601"]
    # For non-ISO calendar with full date string: normalize reference day to day 1 of that calendar month!
    f = tm_cal_iso_to_fields(cal, ym[0], ym[1], ym[2])
    ymd = tm_cal_resolve_month_and_day(cal, f[2], f[3], nil, 1, "constrain")
    js_throw_range("YearMonth out of Temporal range") if !tm_iso_ym_within_limits?(ymd[0], ymd[1])
    return [ymd[0], ymd[1], ymd[2], cal]
  js_throw_type("Invalid argument for Temporal.PlainYearMonth") if !js_object?(item)
  cal_v = jget(item, "calendar")
  cal = cal_v == nil ? "iso8601" : tm_to_cal_id(cal_v)
  fields = tm_read_date_fields(item, cal, false)
  opts = tm_get_options_obj(opts_arg)
  ov = tm_get_overflow(opts)
  ymd = tm_cal_fields_to_iso(cal, fields, ov, :year_month)
  [ymd[0], ymd[1], ymd[2], cal]

-> tm_ym_ctor(args, nt)
  js_throw_type("Constructor Temporal.PlainYearMonth requires 'new'") if nt == nil
  y = tm_to_int_trunc(js_arg(args, 0)).to_i
  m = tm_to_int_trunc(js_arg(args, 1)).to_i
  ca = js_arg(args, 2)
  cal = ca == nil ? "iso8601" : tm_cal_canon_id(js_string?(ca) ? ca : js_throw_type("Calendar must be a string"))
  ref_d = js_arg(args, 3) == nil ? 1 : tm_to_int_trunc(js_arg(args, 3)).to_i
  tm_make_ym(y, m, ref_d, cal, js_realm().proto_from(nt, "Temporal.PlainYearMonth"))

-> tm_ym_compare(a, b)
  y1 = tm_to_ym_vals(a)
  y2 = tm_to_ym_vals(b)
  tm_date_cmp_arr(y1, y2) + ~0.0

-> tm_ym_add_sub(this, dur_arg, opts_arg, sign)
  ym = tm_check(this, "Temporal.PlainYearMonth", sign > 0 ? "add" : "subtract")
  dv = tm_to_duration_vals(dur_arg)
  opts = tm_get_options_obj(opts_arg)
  ov = tm_get_overflow(opts)
  # Reject weeks, days, or any time unit in PlainYearMonth add/subtract!
  if dv[2] != (0 ## int) || dv[3] != (0 ## int) || tm_dur_time_ns(dv) != (0 ## int)
    js_throw_range("Cannot add weeks, days, or time units to Temporal.PlainYearMonth")
  cal = ym[3]
  dy = sign > 0 ? dv[0] : ((0 ## int) - dv[0])
  dmo = sign > 0 ? dv[1] : ((0 ## int) - dv[1])
  # Per Temporal spec: convert receiver YearMonth to start-of-month date (or end-of-month for negative), checking ISO date limits!
  f = tm_cal_iso_to_fields(cal, ym[0], ym[1], ym[2])
  ymd1 = tm_cal_resolve_month_and_day(cal, f[2], f[3], nil, 1, "constrain")
  js_throw_range("YearMonth start date outside ISO date limits") if !tm_iso_date_within_limits?(ymd1[0], ymd1[1], ymd1[2])
  res = tm_cal_date_add(cal, ymd1[0], ymd1[1], ymd1[2], dy, dmo, 0 ## int, 0 ## int, ov)
  # Normalize reference ISO day to day 1 of resulting calendar month
  f2 = tm_cal_iso_to_fields(cal, res[0], res[1], res[2])
  ymd2 = tm_cal_resolve_month_and_day(cal, f2[2], f2[3], nil, 1, "constrain")
  tm_make_ym(ymd2[0], ymd2[1], ymd2[2], cal)

-> tm_ym_with(this, like_arg, opts_arg)
  ym = tm_check(this, "Temporal.PlainYearMonth", "with")
  js_throw_type("PlainYearMonth.prototype.with requires an object") if !js_object?(like_arg)
  tm_reject_temporal_like_with(like_arg)
  cal = ym[3]
  cur = tm_cal_iso_to_fields(cal, ym[0], ym[1], ym[2])
  pf = tm_read_date_fields(like_arg, cal, false)
  js_throw_type("PlainYearMonth.prototype.with requires at least one year/month property") if pf.size == 0
  merged = {}
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
  ymd = tm_cal_fields_to_iso(cal, merged, ov, :year_month)
  tm_make_ym(ymd[0], ymd[1], ymd[2], cal)

-> tm_ym_diff(this, other_arg, opts_arg, op)
  y1 = tm_check(this, "Temporal.PlainYearMonth", op == :until ? "until" : "since")
  y2 = tm_to_ym_vals(other_arg)
  js_throw_range("Cannot compute difference between PlainYearMonths with different calendars") if y1[3] != y2[3]
  cfg = tm_get_diff_settings(op, opts_arg, :date, ["week", "day"], "month", "year")
  su = cfg[0]
  lu = cfg[1]
  rmode = cfg[2]
  rinc = cfg[3]
  cal = y1[3]
  # Per DifferenceTemporalPlainYearMonth step 7: identical YearMonth immediately returns zero duration BEFORE CalendarDateFromFields!
  if y1[0] == y2[0] && y1[1] == y2[1] && y1[2] == y2[2]
    return tm_make_duration(Array.new(10, 0 ## int))
  f1 = tm_cal_iso_to_fields(cal, y1[0], y1[1], y1[2])
  f2 = tm_cal_iso_to_fields(cal, y2[0], y2[1], y2[2])
  d1 = tm_cal_resolve_month_and_day(cal, f1[2], f1[3], nil, 1, "constrain")
  d2 = tm_cal_resolve_month_and_day(cal, f2[2], f2[3], nil, 1, "constrain")
  js_throw_range("YearMonth start date outside ISO date limits") if !tm_iso_date_within_limits?(d1[0], d1[1], d1[2]) || !tm_iso_date_within_limits?(d2[0], d2[1], d2[2])
  diff4 = tm_cal_date_until(cal, d1[0], d1[1], d1[2], d2[0], d2[1], d2[2], lu)
  vals = (su == "month" && rinc == 1) ? [diff4[0] ## int, diff4[1] ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int] : tm_round_date_diff(cal, d1[0], d1[1], d1[2], d2[0], d2[1], d2[2], diff4, su, lu, rinc, rmode)
  if op == :since
    i = 0
    while i < 10
      vals[i] = (0 ## int) - vals[i]
      i += 1
  tm_make_duration(vals)

-> tm_ym_to_plain_date(this, item)
  ym = tm_check(this, "Temporal.PlainYearMonth", "toPlainDate")
  js_throw_type("PlainYearMonth.prototype.toPlainDate requires an object") if !js_object?(item)
  cal = ym[3]
  cur = tm_cal_iso_to_fields(cal, ym[0], ym[1], ym[2])
  dv = jget(item, "day")
  js_throw_type("day property is required for toPlainDate") if dv == nil
  day = tm_to_pos_int_trunc(dv).to_i
  ymd = tm_cal_resolve_month_and_day(cal, cur[2], nil, cur[4], day, "constrain")
  tm_make_date(ymd[0], ymd[1], ymd[2], cal)

-> tm_ym_to_string(this, opts_arg)
  ym = tm_check(this, "Temporal.PlainYearMonth", "toString")
  opts = tm_get_options_obj(opts_arg)
  show_cal = tm_get_show_cal(opts)
  cal = ym[3]
  base = tm_fmt_iso_year(ym[0]) + "-" + tm_pad2(ym[1])
  if cal != "iso8601" || show_cal == "always" || show_cal == "critical"
    base = base + "-" + tm_pad2(ym[2])
  base + tm_fmt_cal_ann(cal, show_cal)

# ---- Temporal.PlainMonthDay ----

-> tm_to_md_vals(item, opts_arg = nil)
  if js_special?(item, "Temporal.PlainMonthDay")
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    return item.internal.dup
  if js_string?(item)
    md = tm_parse_iso_md(item)
    cal = md[3] != nil ? tm_cal_canon_id(md[3]) : "iso8601"
    opts = tm_get_options_obj(opts_arg)
    tm_get_overflow(opts)
    if md[0] == nil && cal != "iso8601"
      js_throw_range("Non-ISO calendar requires full date with year in PlainMonthDay string: " + item)
    if cal == "iso8601"
      return [1972, md[1], md[2], "iso8601"]
    js_throw_range("Date out of Temporal range in PlainMonthDay string: " + item) if !tm_iso_date_within_limits?(md[0], md[1], md[2])
    f = tm_cal_iso_to_fields(cal, md[0], md[1], md[2])
    ymd = tm_cal_month_day_ref_iso(cal, f[4], f[5], "constrain")
    return [ymd[0], ymd[1], ymd[2], cal]
  js_throw_type("Invalid argument for Temporal.PlainMonthDay") if !js_object?(item)
  cal_v = jget(item, "calendar")
  cal = cal_v == nil ? "iso8601" : tm_to_cal_id(cal_v)
  fields = tm_read_date_fields(item, cal, true)
  opts = tm_get_options_obj(opts_arg)
  ov = tm_get_overflow(opts)
  ymd = tm_cal_fields_to_iso(cal, fields, ov, :month_day)
  [ymd[0], ymd[1], ymd[2], cal]

-> tm_md_ctor(args, nt)
  js_throw_type("Constructor Temporal.PlainMonthDay requires 'new'") if nt == nil
  m = tm_to_int_trunc(js_arg(args, 0)).to_i
  d = tm_to_int_trunc(js_arg(args, 1)).to_i
  ca = js_arg(args, 2)
  cal = ca == nil ? "iso8601" : tm_cal_canon_id(js_string?(ca) ? ca : js_throw_type("Calendar must be a string"))
  ref_y = js_arg(args, 3) == nil ? 1972 : tm_to_int_trunc(js_arg(args, 3)).to_i
  tm_make_md(ref_y, m, d, cal, js_realm().proto_from(nt, "Temporal.PlainMonthDay"))

-> tm_md_with(this, like_arg, opts_arg)
  md = tm_check(this, "Temporal.PlainMonthDay", "with")
  js_throw_type("PlainMonthDay.prototype.with requires an object") if !js_object?(like_arg)
  tm_reject_temporal_like_with(like_arg)
  cal = md[3]
  cur = tm_cal_iso_to_fields(cal, md[0], md[1], md[2])
  pf = tm_read_date_fields(like_arg, cal, true)
  js_throw_type("PlainMonthDay.prototype.with requires at least one valid property") if pf.size == 0
  merged = {}
  merged["day"] = pf.has_key?("day") ? pf["day"] : cur[5]
  if pf.has_key?("month") || pf.has_key?("monthCode")
    merged["month"] = pf["month"] if pf.has_key?("month")
    merged["monthCode"] = pf["monthCode"] if pf.has_key?("monthCode")
  else
    merged["monthCode"] = cur[4]
  merged["year"] = pf["year"] if pf.has_key?("year")
  merged["era"] = pf["era"] if pf.has_key?("era")
  merged["eraYear"] = pf["eraYear"] if pf.has_key?("eraYear")
  opts = tm_get_options_obj(opts_arg)
  ov = tm_get_overflow(opts)
  ymd = tm_cal_fields_to_iso(cal, merged, ov, :month_day)
  tm_make_md(ymd[0], ymd[1], ymd[2], cal)

-> tm_md_to_plain_date(this, item)
  md = tm_check(this, "Temporal.PlainMonthDay", "toPlainDate")
  js_throw_type("PlainMonthDay.prototype.toPlainDate requires an object") if !js_object?(item)
  cal = md[3]
  cur = tm_cal_iso_to_fields(cal, md[0], md[1], md[2])
  f = {}
  if tm_cal_has_eras?(cal)
    v = jget(item, "era")
    f["era"] = tm_to_prim_require_str(v) if v != nil
    v = jget(item, "eraYear")
    f["eraYear"] = tm_to_int_trunc(v).to_i if v != nil
  v = jget(item, "year")
  f["year"] = tm_to_int_trunc(v).to_i if v != nil
  f["monthCode"] = cur[4]
  f["day"] = cur[5]
  ymd = tm_cal_fields_to_iso(cal, f, "constrain", :date)
  tm_make_date(ymd[0], ymd[1], ymd[2], cal)

-> tm_md_to_string(this, opts_arg)
  md = tm_check(this, "Temporal.PlainMonthDay", "toString")
  opts = tm_get_options_obj(opts_arg)
  show_cal = tm_get_show_cal(opts)
  cal = md[3]
  base = tm_pad2(md[1]) + "-" + tm_pad2(md[2])
  if cal != "iso8601" || show_cal == "always" || show_cal == "critical"
    base = tm_fmt_iso_year(md[0]) + "-" + base
  base + tm_fmt_cal_ann(cal, show_cal)

# ---- Temporal.ZonedDateTime ----

# GetStartOfDay ( timeZone, isoDate ) — exact TC39 spec!
# When midnight 00:00:00 falls in a DST gap (including a gap that crosses midnight!), returns the transition instant itself!
-> tm_zdt_start_of_day_ns(tz, y, m, d)
  poss = tm_tz_possible_instants(tz, y, m, d, 0, 0, 0, 0, 0, 0)
  if poss.size > 0
    res = poss[0]
    js_throw_range("Start of day out of valid Temporal range") if !tm_epoch_ns_valid?(res)
    return res
  # Midnight fell in a gap! Find the exact transition instant starting this day!
  local_ns = tm_iso_epoch_ns(y, m, d, 0, 0, 0, 0, 0, 0)
  t_probe = local_ns - TM_NS_DAY
  t_probe = TM_MIN_EPOCH_NS if t_probe < TM_MIN_EPOCH_NS
  off_before = tm_tz_get_offset_ns(tz, t_probe)
  search_start = local_ns - off_before - (1 ## int)
  tr = tm_tz_get_transition(tz, search_start - TM_NS_DAY, 1)
  tries = 0
  while tr != nil && tries < 8
    dt = tm_iso_dt_from_epoch_ns(tr + tm_tz_get_offset_ns(tz, tr))
    if dt[0] > y || (dt[0] == y && (dt[1] > m || (dt[1] == m && dt[2] >= d)))
      js_throw_range("Start of day out of valid Temporal range") if !tm_epoch_ns_valid?(tr)
      return tr
    tr = tm_tz_get_transition(tz, tr, 1)
    tries += 1
  tm_tz_disambiguate(tz, y, m, d, 0, 0, 0, 0, 0, 0, "compatible")

-> tm_zdt_local_dt(z)
  off = tm_tz_get_offset_ns(z[1], z[0])
  tm_iso_dt_from_epoch_ns(z[0] + off)

# ToTemporalZonedDateTime ( item, opts_arg ) -> [epoch_ns, tz, cal]
-> tm_to_zdt_vals(item, opts_arg = nil)
  if js_special?(item, "Temporal.ZonedDateTime")
    opts = tm_get_options_obj(opts_arg)
    tm_get_disambig(opts)
    tm_get_offset_opt(opts, "reject")
    tm_get_overflow(opts)
    return item.internal.dup
  if js_string?(item)
    r = tm_parse_iso_datetime(item)
    js_throw_range("ZonedDateTime string must include a \[timeZone] annotation: " + item) if r["tz_ann"] == nil
    tz = tm_resolve_tz_id(r["tz_ann"])
    cal = r["cal_ann"] != nil ? tm_cal_canon_id(r["cal_ann"]) : "iso8601"
    opts = tm_get_options_obj(opts_arg)
    dis = tm_get_disambig(opts)
    off_opt = tm_get_offset_opt(opts, "reject")
    tm_get_overflow(opts)
    if !r["has_time"]
      ns = tm_zdt_start_of_day_ns(tz, r["y"], r["m"], r["d"])
      return [ns, tz, cal]
    off_beh = r["z"] ? :exact : (r["off_ns"] != nil ? :option : :wall)
    off_ns = r["z"] ? (0 ## int) : r["off_ns"]
    ns = tm_interpret_iso_dt_offset(r["y"], r["m"], r["d"], r["h"], r["mi"], r["s"], r["ms"], r["us"], r["ns"],
                                    off_beh, off_ns, tz, dis, off_opt, r["off_has_sec"])
    return [ns, tz, cal]
  js_throw_type("Invalid argument for Temporal.ZonedDateTime") if !js_object?(item)
  # Read calendar, then date/time/offset/timeZone fields in exact alphabetical order!
  cal_v = jget(item, "calendar")
  cal = cal_v == nil ? "iso8601" : tm_to_cal_id(cal_v)
  f = {}
  v = jget(item, "day")
  f["day"] = tm_to_pos_int_trunc(v).to_i if v != nil
  if tm_cal_has_eras?(cal)
    v = jget(item, "era")
    f["era"] = tm_to_prim_require_str(v) if v != nil
    v = jget(item, "eraYear")
    f["eraYear"] = tm_to_int_trunc(v).to_i if v != nil
  has_t = false
  h = 0
  us = 0
  ms = 0
  mi = 0
  ns = 0
  s = 0
  v = jget(item, "hour")
  if v != nil
    has_t = true
    h = tm_to_int_trunc(v).to_i
  v = jget(item, "microsecond")
  if v != nil
    has_t = true
    us = tm_to_int_trunc(v).to_i
  v = jget(item, "millisecond")
  if v != nil
    has_t = true
    ms = tm_to_int_trunc(v).to_i
  v = jget(item, "minute")
  if v != nil
    has_t = true
    mi = tm_to_int_trunc(v).to_i
  v = jget(item, "month")
  f["month"] = tm_to_pos_int_trunc(v).to_i if v != nil
  v = jget(item, "monthCode")
  f["monthCode"] = tm_parse_mcode_syntax(tm_to_prim_require_str(v)) if v != nil
  v = jget(item, "nanosecond")
  if v != nil
    has_t = true
    ns = tm_to_int_trunc(v).to_i
  off_v = jget(item, "offset")
  off_ns = nil
  off_has_sec = false
  if off_v != nil
    os = tm_to_prim_require_str(off_v)
    op = tm_parse_utc_offset(os, 0, true)
    js_throw_range("Invalid offset property: " + os) if op == nil || op[2] != os.size
    off_ns = op[0]
    off_has_sec = op[1]
  v = jget(item, "second")
  if v != nil
    has_t = true
    s = tm_to_int_trunc(v).to_i
  tz_v = jget(item, "timeZone")
  js_throw_type("timeZone property is required for ZonedDateTime.from") if tz_v == nil
  tz = tm_parse_tz_arg(tz_v)
  v = jget(item, "year")
  f["year"] = tm_to_int_trunc(v).to_i if v != nil
  opts = tm_get_options_obj(opts_arg)
  dis = tm_get_disambig(opts)
  off_opt = tm_get_offset_opt(opts, "reject")
  ov = tm_get_overflow(opts)
  ymd = tm_cal_fields_to_iso(cal, f, ov, :date)
  ct = tm_constrain_time(h, mi, s, ms, us, ns, ov)
  off_beh = off_ns != nil ? :option : :wall
  ep = tm_interpret_iso_dt_offset(ymd[0], ymd[1], ymd[2], ct[0], ct[1], ct[2], ct[3], ct[4], ct[5],
                                  off_beh, off_ns, tz, dis, off_opt, true)
  [ep, tz, cal]

-> tm_zdt_ctor(args, nt)
  js_throw_type("Constructor Temporal.ZonedDateTime requires 'new'") if nt == nil
  ns = js_to_bigint(js_arg(args, 0)).v
  tz_a = js_arg(args, 1)
  js_throw_type("timeZone must be a string") if !js_string?(tz_a)
  tz = tm_resolve_tz_id(tz_a)
  ca = js_arg(args, 2)
  cal = ca == nil ? "iso8601" : tm_cal_canon_id(js_string?(ca) ? ca : js_throw_type("Calendar must be a string"))
  tm_make_zdt(ns, tz, cal, js_realm().proto_from(nt, "Temporal.ZonedDateTime"))

-> tm_zdt_compare(a, b)
  z1 = tm_to_zdt_vals(a)
  z2 = tm_to_zdt_vals(b)
  z1[0] < z2[0] ? ~-1.0 : (z1[0] > z2[0] ? ~1.0 : ~0.0)

# AddZonedDateTime ( epoch_ns, tz, cal, dv, overflow ) -> ## int epoch_ns
-> tm_zdt_add_dur_ns(epoch_ns, tz, cal, dv, ov)
  t_ns = tm_dur_time_ns(dv)
  if dv[0] == (0 ## int) && dv[1] == (0 ## int) && dv[2] == (0 ## int) && dv[3] == (0 ## int)
    res = epoch_ns + t_ns
    js_throw_range("ZonedDateTime out of range") if !tm_epoch_ns_valid?(res)
    return res
  # Add calendar date portion in local wall time, re-interpret in timezone, then add exact time nanoseconds!
  off = tm_tz_get_offset_ns(tz, epoch_ns)
  dt = tm_iso_dt_from_epoch_ns(epoch_ns + off)
  ymd = tm_cal_date_add(cal, dt[0], dt[1], dt[2], dv[0], dv[1], dv[2], dv[3], ov)
  mid_ns = tm_tz_disambiguate(tz, ymd[0], ymd[1], ymd[2], dt[3], dt[4], dt[5], dt[6], dt[7], dt[8], "compatible")
  res = mid_ns + t_ns
  js_throw_range("ZonedDateTime out of range") if !tm_epoch_ns_valid?(res)
  res

-> tm_zdt_add_sub(this, dur_arg, opts_arg, sign)
  z = tm_check(this, "Temporal.ZonedDateTime", sign > 0 ? "add" : "subtract")
  dv = tm_to_duration_vals(dur_arg)
  if sign < 0
    nd = Array.new(10, 0 ## int)
    i = 0
    while i < 10
      nd[i] = (0 ## int) - dv[i]
      i += 1
    dv = nd
  opts = tm_get_options_obj(opts_arg)
  ov = tm_get_overflow(opts)
  res_ns = tm_zdt_add_dur_ns(z[0], z[1], z[2], dv, ov)
  tm_make_zdt(res_ns, z[1], z[2])

# Non-throwing variant of tm_zdt_add_dur_ns (returns nil if result is outside valid epochNs range!)
-> tm_zdt_add_dur_ns_try(epoch_ns, tz, cal, dv)
  begin
    return tm_zdt_add_dur_ns(epoch_ns, tz, cal, dv, "constrain")
  rescue e
    return nil

# DifferenceZonedDateTimeWithRounding ( ns1, ns2, tz, cal, su, lu, rinc, rmode, from_dur = false ) -> Array[10] of ## int
-> tm_zdt_diff_dur_vals(ns1, ns2, tz, cal, su, lu, rinc, rmode, from_dur = false)
  diff_ns = ns2 - ns1
  rk_lu = TM_UNIT_RANK[lu]
  rk_su = TM_UNIT_RANK[su]
  if diff_ns == (0 ## int)
    # Per Temporal Duration.prototype.round: when actually rounding with day+ ZonedDateTime, validate next-day boundary!
    if from_dur && rk_lu <= 3 && rk_su >= 4 && (su != "nanosecond" || rinc > 1)
      tm_zdt_add_dur_ns(ns1, tz, cal, [0 ## int, 0 ## int, 0 ## int, 1 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int], "constrain")
    return Array.new(10, 0 ## int)
  # Pure time units (hour..nanosecond): exact instant difference!
  if rk_lu >= 4 && rk_su >= 4
    r_ns = tm_round_to_inc(diff_ns, TM_UNIT_NS[su] * (rinc ## int), rmode)
    return tm_balance_time_duration(r_ns, lu)
  # Includes days, weeks, months, or years (DST-aware day lengths!)
  sign = diff_ns >= (0 ## int) ? 1 : -1
  off1 = tm_tz_get_offset_ns(tz, ns1)
  off2 = tm_tz_get_offset_ns(tz, ns2)
  dt1 = tm_iso_dt_from_epoch_ns(ns1 + off1)
  dt2 = tm_iso_dt_from_epoch_ns(ns2 + off2)
  # Per DifferenceZonedDateTime (TC39 #3141): if same ISO date (or opposite-direction wall-clock date), date diff is 0!
  dcmp = tm_date_cmp_arr(dt1, dt2)
  if dcmp == 0 || (sign > 0 && dcmp > 0) || (sign < 0 && dcmp < 0)
    diff4 = [0, 0, 0, 0]
    mid_ns = ns1
  else
    # Compare wall-clock times first! If time-of-day has opposite sign, adjust target date by -sign day!
    t1 = (dt1[3] ## int) * TM_NS_HOUR + (dt1[4] ## int) * TM_NS_MIN + (dt1[5] ## int) * TM_NS_SEC + (dt1[6] ## int) * TM_NS_MS + (dt1[7] ## int) * TM_NS_US + (dt1[8] ## int)
    t2 = (dt2[3] ## int) * TM_NS_HOUR + (dt2[4] ## int) * TM_NS_MIN + (dt2[5] ## int) * TM_NS_SEC + (dt2[6] ## int) * TM_NS_MS + (dt2[7] ## int) * TM_NS_US + (dt2[8] ## int)
    end_y = dt2[0]
    end_m = dt2[1]
    end_d = dt2[2]
    if (sign > 0 && t2 < t1) || (sign < 0 && t2 > t1)
      adj0 = tm_ymd_from_days(tm_epoch_days(end_y, end_m, end_d) - (sign ## int))
      end_y = adj0[0]
      end_m = adj0[1]
      end_d = adj0[2]
    diff4 = tm_cal_date_until(cal, dt1[0], dt1[1], dt1[2], end_y, end_m, end_d, lu)
    # Check if adding diff4 to zdt1 overshoots ns2 (due to DST shift or skipped 24h day like Samoa!)
    mid_ns = tm_zdt_add_dur_ns_try(ns1, tz, cal, [diff4[0] ## int, diff4[1] ## int, diff4[2] ## int, diff4[3] ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int])
    bt_tries = 0
    while (mid_ns == nil || (sign > 0 && mid_ns > ns2) || (sign < 0 && mid_ns < ns2)) && bt_tries < 5
      adj = tm_ymd_from_days(tm_epoch_days(end_y, end_m, end_d) - (sign ## int))
      end_y = adj[0]
      end_m = adj[1]
      end_d = adj[2]
      diff4 = tm_cal_date_until(cal, dt1[0], dt1[1], dt1[2], end_y, end_m, end_d, lu)
      mid_ns = tm_zdt_add_dur_ns_try(ns1, tz, cal, [diff4[0] ## int, diff4[1] ## int, diff4[2] ## int, diff4[3] ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int])
      bt_tries += 1
    mid_ns = ns1 if mid_ns == nil
  rem_ns = ns2 - mid_ns
  if rk_su >= 4
    # Round time remainder by su*rinc, applying AdjustRoundedDurationDays when |rt| >= day_len!
    inc_ns = TM_UNIT_NS[su] * (rinc ## int)
    rt = tm_round_to_inc(rem_ns, inc_ns, rmode)
    carried = false
    if rt != (0 ## int) && rt != rem_ns
      adj_tries = 0
      while adj_tries < 4
        nxt_ns = tm_zdt_add_dur_ns_try(ns1, tz, cal, [diff4[0] ## int, diff4[1] ## int, diff4[2] ## int, (diff4[3] + sign) ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int])
        break if nxt_ns == nil
        day_len = tm_abs_i(nxt_ns - mid_ns)
        break if day_len <= (0 ## int) || tm_abs_i(rt) < day_len
        diff4[3] += sign
        mid_ns = nxt_ns
        carried = true
        rem_after = sign > 0 ? (rt - day_len) : (rt + day_len)
        rt = tm_round_to_inc(rem_after, inc_ns, rmode)
        adj_tries += 1
    if carried && rk_lu <= 2
      mid_dt = tm_iso_dt_from_epoch_ns(mid_ns + tm_tz_get_offset_ns(tz, mid_ns))
      diff4 = tm_cal_date_until(cal, dt1[0], dt1[1], dt1[2], mid_dt[0], mid_dt[1], mid_dt[2], lu)
    bt = tm_balance_time_duration(rt, "hour")
    return [diff4[0] ## int, diff4[1] ## int, diff4[2] ## int, diff4[3] ## int, bt[4], bt[5], bt[6], bt[7], bt[8], bt[9]]
  if su == "day"
    base_q = (diff4[3] ## int) / (rinc ## int)
    base_d = base_q * (rinc ## int)
    n1 = tm_zdt_add_dur_ns(ns1, tz, cal, [diff4[0] ## int, diff4[1] ## int, diff4[2] ## int, base_d, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int], "constrain")
    if ns2 == n1
      rd = base_d
    else
      next_d = base_d + ((sign * rinc) ## int)
      n2 = tm_zdt_add_dur_ns(ns1, tz, cal, [diff4[0] ## int, diff4[1] ## int, diff4[2] ## int, next_d, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int], "constrain")
      span = tm_abs_i(n2 - n1)
      rd = span == (0 ## int) ? base_d : (tm_round_div(base_q * span + (ns2 - n1), span, rmode) * (rinc ## int))
    if lu != "day" && rd != (diff4[3] ## int)
      end_r = tm_cal_date_add(cal, dt1[0], dt1[1], dt1[2], diff4[0] ## int, diff4[1] ## int, diff4[2] ## int, rd, "constrain")
      re = tm_cal_date_until(cal, dt1[0], dt1[1], dt1[2], end_r[0], end_r[1], end_r[2], lu)
      return [re[0] ## int, re[1] ## int, re[2] ## int, re[3] ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
    return [diff4[0] ## int, diff4[1] ## int, diff4[2] ## int, rd, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
  if su == "week"
    base_q = (diff4[2] ## int) / (rinc ## int)
    base_w = base_q * (rinc ## int)
    n1 = tm_zdt_add_dur_ns(ns1, tz, cal, [diff4[0] ## int, diff4[1] ## int, base_w, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int], "constrain")
    if ns2 == n1
      rw = base_w
    else
      next_w = base_w + ((sign * rinc) ## int)
      n2 = tm_zdt_add_dur_ns(ns1, tz, cal, [diff4[0] ## int, diff4[1] ## int, next_w, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int], "constrain")
      span = tm_abs_i(n2 - n1)
      rw = span == (0 ## int) ? base_w : (tm_round_div(base_q * span + (ns2 - n1), span, rmode) * (rinc ## int))
    return [diff4[0] ## int, diff4[1] ## int, rw, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
  if su == "month"
    base_q = (diff4[1] ## int) / (rinc ## int)
    base_m = base_q * (rinc ## int)
    n1 = tm_zdt_add_dur_ns(ns1, tz, cal, [diff4[0] ## int, base_m, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int], "constrain")
    if ns2 == n1
      rm = base_m
    else
      next_m = base_m + ((sign * rinc) ## int)
      n2 = tm_zdt_add_dur_ns(ns1, tz, cal, [diff4[0] ## int, next_m, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int], "constrain")
      span = tm_abs_i(n2 - n1)
      rm = span == (0 ## int) ? base_m : (tm_round_div(base_q * span + (ns2 - n1), span, rmode) * (rinc ## int))
    if lu == "year" && rm != (diff4[1] ## int)
      end_r = tm_cal_date_add(cal, dt1[0], dt1[1], dt1[2], diff4[0] ## int, rm, 0 ## int, 0 ## int, "constrain")
      re = tm_cal_date_until(cal, dt1[0], dt1[1], dt1[2], end_r[0], end_r[1], end_r[2], "year")
      return [re[0] ## int, re[1] ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
    return [diff4[0] ## int, rm, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]
  # su == "year"
  base_q = (diff4[0] ## int) / (rinc ## int)
  base_y = base_q * (rinc ## int)
  n1 = tm_zdt_add_dur_ns(ns1, tz, cal, [base_y, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int], "constrain")
  if ns2 == n1
    ry = base_y
  else
    next_y = base_y + ((sign * rinc) ## int)
    n2 = tm_zdt_add_dur_ns(ns1, tz, cal, [next_y, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int], "constrain")
    span = tm_abs_i(n2 - n1)
    ry = span == (0 ## int) ? base_y : (tm_round_div(base_q * span + (ns2 - n1), span, rmode) * (rinc ## int))
  [ry, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int, 0 ## int]

-> tm_zdt_total_in_unit(ns1, ns2, tz, cal, unit)
  diff_ns = ns2 - ns1
  if diff_ns == (0 ## int)
    # Even for 0 duration, calendar-unit totals relative to ZDT validate that +1 unit boundary is within valid epochNs range!
    if TM_UNIT_RANK[unit] <= 3
      d_one = Array.new(10, 0 ## int)
      d_one[TM_UNIT_RANK[unit]] = 1 ## int
      tm_zdt_add_dur_ns(ns1, tz, cal, d_one, "constrain")
    return ~0.0
  if TM_UNIT_RANK[unit] >= 4
    return tm_exact_div_to_num(diff_ns, TM_UNIT_NS[unit])
  sign = diff_ns >= (0 ## int) ? 1 : -1
  # Find whole units (year, month, week, or day) without overshooting ns2!
  dv = tm_zdt_diff_dur_vals(ns1, ns2, tz, cal, "nanosecond", unit, 1, "trunc")
  idx = TM_UNIT_RANK[unit]
  whole = dv[idx]
  d_base = Array.new(10, 0 ## int)
  d_base[idx] = whole
  d_next = Array.new(10, 0 ## int)
  d_next[idx] = whole + (sign ## int)
  n1 = tm_zdt_add_dur_ns(ns1, tz, cal, d_base, "constrain")
  n2 = tm_zdt_add_dur_ns(ns1, tz, cal, d_next, "constrain")
  span = tm_abs_i(n2 - n1)
  return tm_int_to_num(whole) if span == (0 ## int)
  tm_exact_div_to_num(whole * span + (ns2 - n1), span)

-> tm_zdt_diff(this, other_arg, opts_arg, op)
  z1 = tm_check(this, "Temporal.ZonedDateTime", op == :until ? "until" : "since")
  z2 = tm_to_zdt_vals(other_arg)
  js_throw_range("Cannot compute difference between ZonedDateTimes with different calendars") if z1[2] != z2[2]
  cfg = tm_get_diff_settings(op, opts_arg, :datetime, nil, "nanosecond", "hour")
  su = cfg[0]
  lu = cfg[1]
  rmode = cfg[2]
  rinc = cfg[3]
  if TM_UNIT_RANK[lu] <= 3 && !tm_tz_equals?(z1[1], z2[1])
    js_throw_range("Cannot compute date-unit difference between ZonedDateTimes with different time zones")
  vals = tm_zdt_diff_dur_vals(z1[0], z2[0], z1[1], z1[2], su, lu, rinc, rmode)
  if op == :since
    i = 0
    while i < 10
      vals[i] = (0 ## int) - vals[i]
      i += 1
  tm_make_duration(vals)

-> tm_zdt_hours_in_day(this)
  z = tm_check(this, "Temporal.ZonedDateTime", "hoursInDay")
  dt = tm_zdt_local_dt(z)
  s1 = tm_zdt_start_of_day_ns(z[1], dt[0], dt[1], dt[2])
  nxt = tm_ymd_from_days(tm_epoch_days(dt[0], dt[1], dt[2]) + (1 ## int))
  s2 = tm_zdt_start_of_day_ns(z[1], nxt[0], nxt[1], nxt[2])
  diff = s2 - s1
  tm_int_to_num(diff / TM_NS_HOUR) + tm_int_to_num(diff % TM_NS_HOUR) / tm_int_to_num(TM_NS_HOUR)

-> tm_zdt_start_of_day(this)
  z = tm_check(this, "Temporal.ZonedDateTime", "startOfDay")
  dt = tm_zdt_local_dt(z)
  tm_make_zdt(tm_zdt_start_of_day_ns(z[1], dt[0], dt[1], dt[2]), z[1], z[2])

-> tm_zdt_get_transition(this, arg)
  z = tm_check(this, "Temporal.ZonedDateTime", "getTimeZoneTransition")
  js_throw_type("getTimeZoneTransition requires a direction argument") if arg == nil
  dir_s = nil
  if js_string?(arg)
    dir_s = arg
  elsif js_object?(arg)
    dir_s = tm_get_option(arg, "direction", :string, ["next", "previous"], :required)
  else
    js_throw_type("getTimeZoneTransition argument must be string or object")
  js_throw_range("Invalid direction: " + dir_s) if dir_s != "next" && dir_s != "previous"
  tr = tm_tz_get_transition(z[1], z[0], dir_s == "next" ? 1 : -1)
  return JS_NULL if tr == nil
  tm_make_zdt(tr, z[1], z[2])

-> tm_zdt_with(this, like_arg, opts_arg)
  z = tm_check(this, "Temporal.ZonedDateTime", "with")
  js_throw_type("ZonedDateTime.prototype.with requires an object") if !js_object?(like_arg)
  tm_reject_temporal_like_with(like_arg)
  tz = z[1]
  cal = z[2]
  off_cur = tm_tz_get_offset_ns(tz, z[0])
  dt = tm_iso_dt_from_epoch_ns(z[0] + off_cur)
  cur = tm_cal_iso_to_fields(cal, dt[0], dt[1], dt[2])
  pf = {}
  any = false
  h = dt[3]
  mi = dt[4]
  s = dt[5]
  ms = dt[6]
  us = dt[7]
  ns = dt[8]
  off_ns = off_cur
  off_from_user = false
  off_has_sec = true
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
  v = jget(like_arg, "offset")
  if v != nil
    any = true
    os = tm_to_prim_require_str(v)
    op = tm_parse_utc_offset(os, 0, true)
    js_throw_range("Invalid offset: " + os) if op == nil || op[2] != os.size
    off_ns = op[0]
    off_has_sec = op[1]
    off_from_user = true
  v = jget(like_arg, "second")
  if v != nil
    any = true
    s = tm_to_int_trunc(v).to_i
  v = jget(like_arg, "year")
  if v != nil
    any = true
    pf["year"] = tm_to_int_trunc(v).to_i
  js_throw_type("ZonedDateTime.prototype.with requires at least one valid property") if !any
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
  dis = tm_get_disambig(opts)
  off_opt = tm_get_offset_opt(opts, "prefer")
  ov = tm_get_overflow(opts)
  ymd = tm_cal_fields_to_iso(cal, merged, ov, :date)
  ct = tm_constrain_time(h, mi, s, ms, us, ns, ov)
  ep = tm_interpret_iso_dt_offset(ymd[0], ymd[1], ymd[2], ct[0], ct[1], ct[2], ct[3], ct[4], ct[5],
                                  :option, off_ns, tz, dis, off_opt, true)
  tm_make_zdt(ep, tz, cal)

-> tm_zdt_with_plain_time(this, pt_arg)
  z = tm_check(this, "Temporal.ZonedDateTime", "withPlainTime")
  dt = tm_zdt_local_dt(z)
  if pt_arg == nil
    return tm_make_zdt(tm_zdt_start_of_day_ns(z[1], dt[0], dt[1], dt[2]), z[1], z[2])
  tf = tm_to_time_fields(pt_arg, "constrain")
  ep = tm_tz_disambiguate(z[1], dt[0], dt[1], dt[2], tf[0], tf[1], tf[2], tf[3], tf[4], tf[5], "compatible")
  tm_make_zdt(ep, z[1], z[2])

-> tm_zdt_round(this, arg)
  z = tm_check(this, "Temporal.ZonedDateTime", "round")
  cfg = tm_parse_round_to(arg, :time, true)
  su = cfg[0]
  rinc = cfg[1]
  rmode = cfg[2]
  tz = z[1]
  cal = z[2]
  if su == "day"
    tm_validate_rounding_inc(rinc, 1, true)
    dt = tm_zdt_local_dt(z)
    s1 = tm_zdt_start_of_day_ns(tz, dt[0], dt[1], dt[2])
    nxt = tm_ymd_from_days(tm_epoch_days(dt[0], dt[1], dt[2]) + (1 ## int))
    s2 = tm_zdt_start_of_day_ns(tz, nxt[0], nxt[1], nxt[2])
    day_end = s2
    if z[0] >= day_end
      # Backwards DST transition crossed midnight (TC39 PR #3312): measure progress against the later midnight of nxt!
      p_nxt = tm_tz_possible_instants(tz, nxt[0], nxt[1], nxt[2], 0, 0, 0, 0, 0, 0)
      day_end = p_nxt[p_nxt.size - 1] if p_nxt.size > 1 && p_nxt[p_nxt.size - 1] > z[0]
    span = day_end - s1
    js_throw_range("Non-positive day length") if span <= (0 ## int)
    r = tm_round_div(z[0] - s1, span, rmode)
    return tm_make_zdt(r == (0 ## int) ? s1 : s2, tz, cal)
  tm_validate_rounding_inc(rinc, TM_UNIT_MAX_INC[su], false)
  # Round elapsed nanoseconds since startOfDay (preserving DST day lengths!)
  dt = tm_zdt_local_dt(z)
  s1 = tm_zdt_start_of_day_ns(tz, dt[0], dt[1], dt[2])
  elapsed = z[0] - s1
  r_el = tm_round_to_inc(elapsed, TM_UNIT_NS[su] * (rinc ## int), rmode)
  tm_make_zdt(s1 + r_el, tz, cal)

-> tm_zdt_to_string(this, opts_arg)
  z = tm_check(this, "Temporal.ZonedDateTime", "toString")
  opts = tm_get_options_obj(opts_arg)
  # Exact alphabetical order BEFORE unit-group validation: calendarName, fractionalSecondDigits, offset, roundingMode, smallestUnit, timeZoneName!
  show_cal = tm_get_show_cal(opts)
  digits = tm_get_frac_sec_digits(opts)
  show_off = tm_get_show_off(opts)
  rmode = tm_get_rounding_mode(opts, "trunc")
  su = tm_get_unit(opts, "smallestUnit", :any, nil, false)
  show_tz = tm_get_show_tz(opts)
  tm_validate_unit_group(su, :time)
  js_throw_range("hour is not valid smallestUnit for ZonedDateTime.prototype.toString") if su == "hour"
  sp = tm_sec_str_prec(digits, su)
  prec = sp[0]
  unit = sp[1]
  inc = sp[2]
  r_ns = tm_round_unsigned_to_inc(z[0], TM_UNIT_NS[unit] * (inc ## int), rmode)
  js_throw_range("Rounded ZonedDateTime out of range") if !tm_epoch_ns_valid?(r_ns)
  off = tm_tz_get_offset_ns(z[1], r_ns)
  dt = tm_iso_dt_from_epoch_ns(r_ns + off)
  out = tm_fmt_iso_date(dt[0], dt[1], dt[2]) + "T" + tm_fmt_time(dt[3], dt[4], dt[5], dt[6], dt[7], dt[8], prec)
  if show_off != "never"
    # Per FormatDateTimeUTCOffsetRounded: round sub-minute offset to nearest minute (halfExpand)!
    off_min = tm_round_to_inc(off, TM_NS_MIN, "halfExpand")
    out = out + tm_fmt_offset_ns(off_min)
  if show_tz == "auto"
    out = out + "\[" + z[1] + "]"
  elsif show_tz == "critical"
    out = out + "\[!" + z[1] + "]"
  out + tm_fmt_cal_ann(z[2], show_cal)

# ---- Intl.DateTimeFormat Temporal Hook & toLocaleString ----

-> tm_is_temporal_formattable?(v)
  js_special?(v, "Temporal.Instant") || js_special?(v, "Temporal.PlainDate") ||
  js_special?(v, "Temporal.PlainTime") || js_special?(v, "Temporal.PlainDateTime") ||
  js_special?(v, "Temporal.PlainYearMonth") || js_special?(v, "Temporal.PlainMonthDay") ||
  js_special?(v, "Temporal.ZonedDateTime")

# Resolve hourCycle for Temporal default formatting when dtf had no explicit hour option
-> tm_dtf_resolve_hc(d)
  return d[4] if d[4] != nil
  h12 = d[26]
  r_hc = d[27]
  if h12 == true
    hc = intl_icu_default_hour_cycle(d[19], "h")
    return (hc == "h11" || hc == "h12") ? hc : "h12"
  elsif h12 == false
    hc = intl_icu_default_hour_cycle(d[19], "H")
    return (hc == "h23" || hc == "h24") ? hc : "h23"
  elsif r_hc != nil
    return r_hc
  intl_icu_default_hour_cycle(d[19], "j")

# Build a derived DateTimeFormat internal array with filtered components/styles & timezone
-> tm_dtf_derive(d, tz_override, weekday, era, year, month, day, day_period, hour, minute, second, frac_sec, tz_name, date_style, time_style)
  d2 = d.dup
  d2[20] = tz_override if tz_override != nil
  d2[6] = weekday
  d2[7] = era
  d2[8] = year
  d2[9] = month
  d2[10] = day
  d2[11] = day_period
  d2[12] = hour
  d2[13] = minute
  d2[14] = second
  d2[15] = frac_sec
  d2[16] = tz_name
  d2[17] = date_style
  d2[18] = time_style
  has_hour = hour != nil || time_style != nil
  hc = has_hour ? tm_dtf_resolve_hc(d) : nil
  d2[4] = hc
  skel = intl_dtf_build_skeleton(weekday, era, year, month, day, day_period, hour, minute, second, frac_sec, tz_name, hc)
  pat = intl_dtf_resolve_pattern(d2[19], d2[20], date_style, time_style, skel, hc, d2[25])
  d2[21] = skel
  d2[22] = pat
  d2

-> tm_dtf_plain_ts(ts)
  return nil if ts == nil
  return "medium" if ts == "full" || ts == "long"
  ts

# Extract skeleton from an ICU dateStyle pattern and filter out characters in `strip_chars` (e.g. for PlainYearMonth/PlainMonthDay with dateStyle!)
-> tm_dtf_style_filtered(d, ds, strip_chars)
  pat0 = intl_dtf_resolve_pattern(d[19], "UTC", ds, nil, "", nil, d[25])
  fn_gs = icu_sym("udatpg_getSkeleton")
  up = icu_to_u16(pat0)
  pba = up[0]
  dst = ByteArray.new(256)
  eb = icu_err_buf()
  n = icu_sext32(icu_c6(fn_gs, 0, icu_ptr(pba), up[1], icu_ptr(dst), 128, icu_ptr(eb)))
  skel0 = (icu_err_code(eb) <= 0 && n > 0) ? icu_from_u16_ba(dst, n) : pat0
  pba.size
  eb.size
  out_s = ""
  i = 0
  while i < skel0.size
    ch = skel0.slice(i, 1)
    out_s = out_s + ch if strip_chars.index(ch) == nil
    i += 1
  d2 = d.dup
  d2[20] = "UTC"
  d2[17] = nil
  d2[18] = nil
  d2[21] = out_s
  d2[22] = intl_dtf_resolve_pattern(d2[19], "UTC", nil, nil, out_s, nil, d2[25])
  d2

# Convert a Temporal object to [epoch_ms_float, dtf_internal_to_use] for Intl.DateTimeFormat!
-> tm_dtf_prepare(d, v)
  js_throw_type("Intl.DateTimeFormat cannot format Temporal.ZonedDateTime directly; use toLocaleString()") if js_special?(v, "Temporal.ZonedDateTime")
  has_exp = d[24]
  ds = d[17]
  ts = d[18]
  has_style = ds != nil || ts != nil
  if js_special?(v, "Temporal.Instant")
    ns = v.internal[0]
    ms = tm_int_to_num(tm_floor_div(ns, TM_NS_MS))
    if !has_exp
      d2 = tm_dtf_derive(d, nil, nil, d[7], "numeric", "numeric", "numeric", nil, "numeric", "numeric", "numeric", nil, d[16], nil, nil)
      return [ms, d2]
    return [ms, d]
  if js_special?(v, "Temporal.PlainDate")
    pd = v.internal
    cal = pd[3]
    js_throw_range("Calendar mismatch between Intl.DateTimeFormat (" + d[1] + ") and PlainDate (" + cal + ")") if cal != "iso8601" && cal != d[1]
    ms = tm_int_to_num(tm_epoch_days(pd[0], pd[1], pd[2]) * (86400000 ## int) + (43200000 ## int))
    if !has_exp
      d2 = tm_dtf_derive(d, "UTC", nil, d[7], "numeric", "numeric", "numeric", nil, nil, nil, nil, nil, nil, nil, nil)
      return [ms, d2]
    if has_style
      js_throw_type("Cannot format PlainDate with timeStyle-only DateTimeFormat") if ds == nil
      d2 = tm_dtf_derive(d, "UTC", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, ds, nil)
      return [ms, d2]
    if d[6] == nil && d[7] == nil && d[8] == nil && d[9] == nil && d[10] == nil
      js_throw_type("No overlapping date fields for PlainDate in DateTimeFormat")
    d2 = tm_dtf_derive(d, "UTC", d[6], d[7], d[8], d[9], d[10], nil, nil, nil, nil, nil, nil, nil, nil)
    return [ms, d2]
  if js_special?(v, "Temporal.PlainTime")
    pt = v.internal
    ms = ((pt[0] * 3600 + pt[1] * 60 + pt[2]) * 1000 + pt[3]) + ~0.0
    if !has_exp
      d2 = tm_dtf_derive(d, "UTC", nil, nil, nil, nil, nil, nil, "numeric", "numeric", "numeric", nil, nil, nil, nil)
      return [ms, d2]
    if has_style
      js_throw_type("Cannot format PlainTime with dateStyle-only DateTimeFormat") if ts == nil
      d2 = tm_dtf_derive(d, "UTC", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, tm_dtf_plain_ts(ts))
      return [ms, d2]
    if d[11] == nil && d[12] == nil && d[13] == nil && d[14] == nil && d[15] == nil
      js_throw_type("No overlapping time fields for PlainTime in DateTimeFormat")
    d2 = tm_dtf_derive(d, "UTC", nil, nil, nil, nil, nil, d[11], d[12], d[13], d[14], d[15], nil, nil, nil)
    return [ms, d2]
  if js_special?(v, "Temporal.PlainDateTime")
    pdt = v.internal
    cal = pdt[9]
    js_throw_range("Calendar mismatch between Intl.DateTimeFormat (" + d[1] + ") and PlainDateTime (" + cal + ")") if cal != "iso8601" && cal != d[1]
    ms = tm_int_to_num(tm_floor_div(tm_iso_epoch_ns(pdt[0], pdt[1], pdt[2], pdt[3], pdt[4], pdt[5], pdt[6], pdt[7], pdt[8]), TM_NS_MS))
    if !has_exp
      d2 = tm_dtf_derive(d, "UTC", nil, d[7], "numeric", "numeric", "numeric", nil, "numeric", "numeric", "numeric", nil, nil, nil, nil)
      return [ms, d2]
    if has_style
      d2 = tm_dtf_derive(d, "UTC", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, ds, tm_dtf_plain_ts(ts))
      return [ms, d2]
    if d[6] == nil && d[7] == nil && d[8] == nil && d[9] == nil && d[10] == nil && d[11] == nil && d[12] == nil && d[13] == nil && d[14] == nil && d[15] == nil
      js_throw_type("No overlapping fields for PlainDateTime in DateTimeFormat")
    d2 = tm_dtf_derive(d, "UTC", d[6], d[7], d[8], d[9], d[10], d[11], d[12], d[13], d[14], d[15], nil, nil, nil)
    return [ms, d2]
  if js_special?(v, "Temporal.PlainYearMonth")
    ym = v.internal
    cal = ym[3]
    js_throw_range("Calendar mismatch between Intl.DateTimeFormat (" + d[1] + ") and PlainYearMonth (" + cal + ")") if cal != d[1]
    ms = tm_int_to_num(tm_epoch_days(ym[0], ym[1], ym[2]) * (86400000 ## int) + (43200000 ## int))
    if !has_exp
      d2 = tm_dtf_derive(d, "UTC", nil, d[7], "numeric", "numeric", nil, nil, nil, nil, nil, nil, nil, nil, nil)
      return [ms, d2]
    if has_style
      js_throw_type("Cannot format PlainYearMonth with timeStyle-only DateTimeFormat") if ds == nil
      return [ms, tm_dtf_style_filtered(d, ds, "dDFgEec")]
    if d[7] == nil && d[8] == nil && d[9] == nil
      js_throw_type("No overlapping year/month fields for PlainYearMonth in DateTimeFormat")
    d2 = tm_dtf_derive(d, "UTC", nil, d[7], d[8], d[9], nil, nil, nil, nil, nil, nil, nil, nil, nil)
    return [ms, d2]
  if js_special?(v, "Temporal.PlainMonthDay")
    md = v.internal
    cal = md[3]
    js_throw_range("Calendar mismatch between Intl.DateTimeFormat (" + d[1] + ") and PlainMonthDay (" + cal + ")") if cal != d[1]
    ms = tm_int_to_num(tm_epoch_days(md[0], md[1], md[2]) * (86400000 ## int) + (43200000 ## int))
    if !has_exp
      d2 = tm_dtf_derive(d, "UTC", nil, nil, nil, "numeric", "numeric", nil, nil, nil, nil, nil, nil, nil, nil)
      return [ms, d2]
    if has_style
      js_throw_type("Cannot format PlainMonthDay with timeStyle-only DateTimeFormat") if ds == nil
      return [ms, tm_dtf_style_filtered(d, ds, "GyYurEec")]
    if d[9] == nil && d[10] == nil
      js_throw_type("No overlapping month/day fields for PlainMonthDay in DateTimeFormat")
    d2 = tm_dtf_derive(d, "UTC", nil, nil, nil, d[9], d[10], nil, nil, nil, nil, nil, nil, nil, nil)
    return [ms, d2]
  nil

-> tm_dtf_hook(mode, d, v1, v2, want_parts)
  if mode == :single
    return JS_HOLE if !tm_is_temporal_formattable?(v1)
    pr = tm_dtf_prepare(d, v1)
    return intl_dtf_format_epoch(pr[1], pr[0], want_parts)
  # mode == :range: ToDateTimeFormattable converts non-Temporal args via ToNumber BEFORE checking kind mismatch!
  t1 = tm_is_temporal_formattable?(v1)
  t2 = tm_is_temporal_formattable?(v2)
  return JS_HOLE if !t1 && !t2
  js_to_number(v1) if !t1
  js_to_number(v2) if !t2
  js_throw_type("Both arguments to formatRange must be of the same Temporal type") if !t1 || !t2 || v1.cls != v2.cls
  pr1 = tm_dtf_prepare(d, v1)
  pr2 = tm_dtf_prepare(d, v2)
  d2 = pr1[1]
  # Proleptic Gregorian dates before 1582-10-15: UDateIntervalFormat uses Julian switchover, so format endpoints via proleptic udat!
  if (d2[1] == "gregory" || d2[1] == "iso8601") && (pr1[0] < ~-12219292800000.0 || pr2[0] < ~-12219292800000.0)
    sep = " " + js_from_units([8211]) + " "
    if !want_parts
      s1 = intl_dtf_format_epoch(d2, pr1[0], false)
      s2 = intl_dtf_format_epoch(d2, pr2[0], false)
      return s1 == s2 ? s1 : (s1 + sep + s2)
    p1 = intl_dtf_format_epoch(d2, pr1[0], true)
    p2 = intl_dtf_format_epoch(d2, pr2[0], true)
    out_p = []
    i1 = 0
    while i1 < p1.size
      p1[i1].define("source", "startRange", ATTR_W + ATTR_E + ATTR_C)
      out_p.push(p1[i1])
      i1 += 1
    sp_obj = js_realm().new_object
    sp_obj.define("type", "literal", ATTR_W + ATTR_E + ATTR_C)
    sp_obj.define("value", sep, ATTR_W + ATTR_E + ATTR_C)
    sp_obj.define("source", "shared", ATTR_W + ATTR_E + ATTR_C)
    out_p.push(sp_obj)
    i2 = 0
    while i2 < p2.size
      p2[i2].define("source", "endRange", ATTR_W + ATTR_E + ATTR_C)
      out_p.push(p2[i2])
      i2 += 1
    return js_realm().adopt_array(out_p)
  # Reuse ICU interval formatter with prepared dtf internal and epoch ms
  skel = d2[21]
  if skel.size == 0
    fn_gs = icu_sym("udatpg_getSkeleton")
    up = icu_to_u16(d2[22])
    pba = up[0]
    dst = ByteArray.new(256)
    eb0 = icu_err_buf()
    n0 = icu_sext32(icu_c6(fn_gs, 0, icu_ptr(pba), up[1], icu_ptr(dst), 128, icu_ptr(eb0)))
    skel = icu_from_u16_ba(dst, n0) if icu_err_code(eb0) <= 0 && n0 > 0
    pba.size
    eb0.size
  fn_open = icu_sym("udtitvfmt_open")
  fn_res = icu_sym("udtitvfmt_openResult")
  fn_fmt = icu_sym("udtitvfmt_formatToResult")
  fn_val = icu_sym("udtitvfmt_resultAsValue")
  fn_c_res = icu_sym("udtitvfmt_closeResult")
  fn_c = icu_sym("udtitvfmt_close")
  lb = icu_cstr(d2[19])
  us = icu_to_u16(skel)
  sba = us[0]
  ut = icu_to_u16(d2[20])
  tba = ut[0]
  eb = icu_err_buf()
  ivf = icu_c6(fn_open, icu_ptr(lb), icu_ptr(sba), us[1], icu_ptr(tba), ut[1], icu_ptr(eb))
  res = icu_c1(fn_res, icu_ptr(eb))
  icu_err_reset(eb)
  icu_c_pddpp(fn_fmt, ivf, wvalue_bits(pr1[0]) ## i64, wvalue_bits(pr2[0]) ## i64, res, icu_ptr(eb))
  icu_err_reset(eb)
  fv = icu_c2(fn_val, res, icu_ptr(eb))
  ex = icu_fmtval_extract(fv, -1)
  icu_c1(fn_c_res, res) if res != 0
  icu_c1(fn_c, ivf) if ivf != 0
  lb.size
  sba.size
  tba.size
  eb.size
  str = ex[0]
  return str if !want_parts
  spans = []
  src_spans = []
  ex[1].each ->(pt)
    if pt[0] == 1 && pt[3] > pt[2]
      spans.push([pt[1], pt[2], pt[3]])
    elsif pt[0] == 4101
      src_spans.push([pt[1], pt[2], pt[3]])
  intl_dtf_parts_from_spans(str, spans, src_spans)

-> tm_to_locale_string(this, cls, args, req_def, def_mode)
  tm_check(this, cls, "toLocaleString")
  if cls == "Temporal.Duration"
    df = intl_dur_ctor([js_arg(args, 0), js_arg(args, 1)], js_realm().intrinsic("Intl.DurationFormat"))
    return intl_dur_run(df, this, false)
  if cls == "Temporal.ZonedDateTime"
    z = this.internal
    opts_in = js_arg(args, 1)
    if opts_in != nil
      o_obj = js_to_obj(opts_in)
      js_throw_type("timeZone option cannot be passed to ZonedDateTime.prototype.toLocaleString") if jget(o_obj, "timeZone") != nil
    dtf = intl_dtf_ctor(nil, [js_arg(args, 0), opts_in], js_realm().intrinsic("Intl.DateTimeFormat"), :any, :date)
    d = dtf.internal
    js_throw_range("Calendar mismatch") if z[2] != "iso8601" && z[2] != d[1]
    icu_tz = tm_tz_is_offset?(z[1]) ? ("GMT" + z[1]) : z[1]
    tzn = d[16] != nil ? d[16] : "short"
    d2 = d[24] ? (d.dup) : tm_dtf_derive(d, icu_tz, nil, d[7], "numeric", "numeric", "numeric", nil, "numeric", "numeric", "numeric", nil, tzn, nil, nil)
    d2[20] = icu_tz
    ms = tm_int_to_num(tm_floor_div(z[0], TM_NS_MS))
    return intl_dtf_format_epoch(d2, ms, false)
  dtf = intl_dtf_ctor(nil, [js_arg(args, 0), js_arg(args, 1)], js_realm().intrinsic("Intl.DateTimeFormat"), req_def, def_mode)
  pr = tm_dtf_prepare(dtf.internal, this)
  intl_dtf_format_epoch(pr[1], pr[0], false)

# ---- Master Temporal Realm Installer ----

js_install(->(r) js_install_temporal(r))

-> js_install_temporal(r)
  JS_TEMPORAL_DTF_HOOK[0] = ->(a) tm_dtf_hook(a[0], a[1], a[2], a[3], a[4])

  tm = js_new_object(r.object_proto)
  tm.define(SYM_TO_STRING_TAG, "Temporal", ATTR_C)
  r.set_intrinsic("Temporal", tm)
  r.global.define("Temporal", tm, BUILTIN_ATTRS)

  # Date.prototype.toTemporalInstant()
  dp = r.intrinsic("Date.prototype")
  tm_fn_1 = ->(this, args, nt)
    t = js_this_time(this)
    js_throw_range("Invalid Date") if t != t
    tm_make_instant(js_bi_from_num(t).v * TM_NS_MS)
  r.method(dp, "toTemporalInstant", 0, tm_fn_1)

  # 1. Temporal.Now
  now = js_new_object(r.object_proto)
  now.define(SYM_TO_STRING_TAG, "Temporal.Now", ATTR_C)
  tm.define("Now", now, BUILTIN_ATTRS)
  r.method(now, "timeZoneId", 0, ->(this, args, nt) tm_now_tz_id())
  r.method(now, "instant", 0, ->(this, args, nt) tm_make_instant(tm_now_epoch_ns()))
  r.method(now, "zonedDateTimeISO", 0, ->(this, args, nt) tm_now_zdt_iso(js_arg(args, 0)))
  r.method(now, "plainDateTimeISO", 0, ->(this, args, nt) tm_now_dt_iso(js_arg(args, 0)))
  r.method(now, "plainDateISO", 0, ->(this, args, nt) tm_now_date_iso(js_arg(args, 0)))
  r.method(now, "plainTimeISO", 0, ->(this, args, nt) tm_now_time_iso(js_arg(args, 0)))

  # 2. Temporal.Instant
  ip = js_new_object(r.object_proto)
  ic = r.native("Instant", 1, ->(this, args, nt) tm_instant_ctor(args, nt), true)
  ic.define("prototype", ip, 0)
  ip.define("constructor", ic, BUILTIN_ATTRS)
  ip.define(SYM_TO_STRING_TAG, "Temporal.Instant", ATTR_C)
  r.set_intrinsic("Temporal.Instant", ic)
  r.set_intrinsic("Temporal.Instant.prototype", ip)
  tm.define("Instant", ic, BUILTIN_ATTRS)
  r.method(ic, "from", 1, ->(this, args, nt) tm_make_instant(tm_to_instant_ns(js_arg(args, 0))))
  r.method(ic, "fromEpochMilliseconds", 1, ->(this, args, nt) tm_instant_from_epoch_ms(js_arg(args, 0)))
  r.method(ic, "fromEpochNanoseconds", 1, ->(this, args, nt) tm_instant_from_epoch_ns(js_arg(args, 0)))
  tm_fn_2 = ->(this, args, nt)
    n1 = tm_to_instant_ns(js_arg(args, 0))
    n2 = tm_to_instant_ns(js_arg(args, 1))
    n1 < n2 ? ~-1.0 : (n1 > n2 ? ~1.0 : ~0.0)
  r.method(ic, "compare", 2, tm_fn_2)
  r.getter(ip, "epochMilliseconds", ->(this, args, nt) tm_int_to_num(tm_floor_div(tm_check(this, "Temporal.Instant", "epochMilliseconds")[0], TM_NS_MS)))
  r.getter(ip, "epochNanoseconds", ->(this, args, nt) JS:BigIntValue.new(tm_check(this, "Temporal.Instant", "epochNanoseconds")[0]))
  r.method(ip, "add", 1, ->(this, args, nt) tm_instant_add_sub(this, js_arg(args, 0), 1))
  r.method(ip, "subtract", 1, ->(this, args, nt) tm_instant_add_sub(this, js_arg(args, 0), -1))
  r.method(ip, "until", 1, ->(this, args, nt) tm_instant_diff(this, js_arg(args, 0), js_arg(args, 1), :until))
  r.method(ip, "since", 1, ->(this, args, nt) tm_instant_diff(this, js_arg(args, 0), js_arg(args, 1), :since))
  r.method(ip, "round", 1, ->(this, args, nt) tm_instant_round(this, js_arg(args, 0)))
  r.method(ip, "equals", 1, ->(this, args, nt) tm_check(this, "Temporal.Instant", "equals")[0] == tm_to_instant_ns(js_arg(args, 0)))
  r.method(ip, "toString", 0, ->(this, args, nt) tm_instant_to_string(this, js_arg(args, 0)))
  r.method(ip, "toJSON", 0, ->(this, args, nt) tm_instant_to_string(this, nil))
  r.method(ip, "toLocaleString", 0, ->(this, args, nt) tm_to_locale_string(this, "Temporal.Instant", args, :any, :all))
  r.method(ip, "valueOf", 0, ->(this, args, nt) js_throw_type("Cannot convert Temporal.Instant to a primitive value"))
  tm_fn_3 = ->(this, args, nt)
    ns = tm_check(this, "Temporal.Instant", "toZonedDateTimeISO")[0]
    tz = tm_parse_tz_arg(js_arg(args, 0))
    tm_make_zdt(ns, tz, "iso8601")
  r.method(ip, "toZonedDateTimeISO", 1, tm_fn_3)

  # 3. Temporal.Duration
  dup = js_new_object(r.object_proto)
  duc = r.native("Duration", 0, ->(this, args, nt) tm_dur_ctor(args, nt), true)
  duc.define("prototype", dup, 0)
  dup.define("constructor", duc, BUILTIN_ATTRS)
  dup.define(SYM_TO_STRING_TAG, "Temporal.Duration", ATTR_C)
  r.set_intrinsic("Temporal.Duration", duc)
  r.set_intrinsic("Temporal.Duration.prototype", dup)
  tm.define("Duration", duc, BUILTIN_ATTRS)
  r.method(duc, "from", 1, ->(this, args, nt) tm_make_duration(tm_to_duration_vals(js_arg(args, 0))))
  r.method(duc, "compare", 2, ->(this, args, nt) tm_dur_compare(js_arg(args, 0), js_arg(args, 1), js_arg(args, 2)))
  r.getter(dup, "years", ->(this, args, nt) tm_int_to_num(tm_check(this, "Temporal.Duration", "years")[0]))
  r.getter(dup, "months", ->(this, args, nt) tm_int_to_num(tm_check(this, "Temporal.Duration", "months")[1]))
  r.getter(dup, "weeks", ->(this, args, nt) tm_int_to_num(tm_check(this, "Temporal.Duration", "weeks")[2]))
  r.getter(dup, "days", ->(this, args, nt) tm_int_to_num(tm_check(this, "Temporal.Duration", "days")[3]))
  r.getter(dup, "hours", ->(this, args, nt) tm_int_to_num(tm_check(this, "Temporal.Duration", "hours")[4]))
  r.getter(dup, "minutes", ->(this, args, nt) tm_int_to_num(tm_check(this, "Temporal.Duration", "minutes")[5]))
  r.getter(dup, "seconds", ->(this, args, nt) tm_int_to_num(tm_check(this, "Temporal.Duration", "seconds")[6]))
  r.getter(dup, "milliseconds", ->(this, args, nt) tm_int_to_num(tm_check(this, "Temporal.Duration", "milliseconds")[7]))
  r.getter(dup, "microseconds", ->(this, args, nt) tm_int_to_num(tm_check(this, "Temporal.Duration", "microseconds")[8]))
  r.getter(dup, "nanoseconds", ->(this, args, nt) tm_int_to_num(tm_check(this, "Temporal.Duration", "nanoseconds")[9]))
  r.getter(dup, "sign", ->(this, args, nt) tm_dur_sign(tm_check(this, "Temporal.Duration", "sign")) + ~0.0)
  r.getter(dup, "blank", ->(this, args, nt) tm_dur_sign(tm_check(this, "Temporal.Duration", "blank")) == 0)
  r.method(dup, "with", 1, ->(this, args, nt) tm_dur_with(this, js_arg(args, 0)))
  r.method(dup, "negated", 0, ->(this, args, nt) tm_dur_negated(this))
  r.method(dup, "abs", 0, ->(this, args, nt) tm_dur_abs(this))
  r.method(dup, "add", 1, ->(this, args, nt) tm_dur_add_sub(this, js_arg(args, 0), 1))
  r.method(dup, "subtract", 1, ->(this, args, nt) tm_dur_add_sub(this, js_arg(args, 0), -1))
  r.method(dup, "round", 1, ->(this, args, nt) tm_dur_round(this, js_arg(args, 0)))
  r.method(dup, "total", 1, ->(this, args, nt) tm_dur_total(this, js_arg(args, 0)))
  r.method(dup, "toString", 0, ->(this, args, nt) tm_dur_to_string(this, js_arg(args, 0)))
  r.method(dup, "toJSON", 0, ->(this, args, nt) tm_dur_to_string(this, nil))
  r.method(dup, "toLocaleString", 0, ->(this, args, nt) tm_to_locale_string(this, "Temporal.Duration", args, :any, :all))
  r.method(dup, "valueOf", 0, ->(this, args, nt) js_throw_type("Cannot convert Temporal.Duration to a primitive value"))

  # 4. Temporal.PlainTime
  ptp = js_new_object(r.object_proto)
  ptc = r.native("PlainTime", 0, ->(this, args, nt) tm_time_ctor(args, nt), true)
  ptc.define("prototype", ptp, 0)
  ptp.define("constructor", ptc, BUILTIN_ATTRS)
  ptp.define(SYM_TO_STRING_TAG, "Temporal.PlainTime", ATTR_C)
  r.set_intrinsic("Temporal.PlainTime", ptc)
  r.set_intrinsic("Temporal.PlainTime.prototype", ptp)
  tm.define("PlainTime", ptc, BUILTIN_ATTRS)
  r.method(ptc, "from", 1, ->(this, args, nt) tm_time_from(js_arg(args, 0), js_arg(args, 1)))
  r.method(ptc, "compare", 2, ->(this, args, nt) tm_time_compare(js_arg(args, 0), js_arg(args, 1)))
  r.getter(ptp, "hour", ->(this, args, nt) tm_check(this, "Temporal.PlainTime", "hour")[0] + ~0.0)
  r.getter(ptp, "minute", ->(this, args, nt) tm_check(this, "Temporal.PlainTime", "minute")[1] + ~0.0)
  r.getter(ptp, "second", ->(this, args, nt) tm_check(this, "Temporal.PlainTime", "second")[2] + ~0.0)
  r.getter(ptp, "millisecond", ->(this, args, nt) tm_check(this, "Temporal.PlainTime", "millisecond")[3] + ~0.0)
  r.getter(ptp, "microsecond", ->(this, args, nt) tm_check(this, "Temporal.PlainTime", "microsecond")[4] + ~0.0)
  r.getter(ptp, "nanosecond", ->(this, args, nt) tm_check(this, "Temporal.PlainTime", "nanosecond")[5] + ~0.0)
  r.method(ptp, "add", 1, ->(this, args, nt) tm_time_add_sub(this, js_arg(args, 0), 1))
  r.method(ptp, "subtract", 1, ->(this, args, nt) tm_time_add_sub(this, js_arg(args, 0), -1))
  r.method(ptp, "with", 1, ->(this, args, nt) tm_time_with(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(ptp, "until", 1, ->(this, args, nt) tm_time_diff(this, js_arg(args, 0), js_arg(args, 1), :until))
  r.method(ptp, "since", 1, ->(this, args, nt) tm_time_diff(this, js_arg(args, 0), js_arg(args, 1), :since))
  r.method(ptp, "round", 1, ->(this, args, nt) tm_time_round(this, js_arg(args, 0)))
  r.method(ptp, "equals", 1, ->(this, args, nt) tm_time_cmp_arr(tm_check(this, "Temporal.PlainTime", "equals"), tm_to_time_fields(js_arg(args, 0), "constrain")) == 0)
  r.method(ptp, "toString", 0, ->(this, args, nt) tm_time_to_string(this, js_arg(args, 0)))
  r.method(ptp, "toJSON", 0, ->(this, args, nt) tm_time_to_string(this, nil))
  r.method(ptp, "toLocaleString", 0, ->(this, args, nt) tm_to_locale_string(this, "Temporal.PlainTime", args, :time, :time))
  r.method(ptp, "valueOf", 0, ->(this, args, nt) js_throw_type("Cannot convert Temporal.PlainTime to a primitive value"))

  # 5. Temporal.PlainDate
  pdp = js_new_object(r.object_proto)
  pdc = r.native("PlainDate", 3, ->(this, args, nt) tm_date_ctor(args, nt), true)
  pdc.define("prototype", pdp, 0)
  pdp.define("constructor", pdc, BUILTIN_ATTRS)
  pdp.define(SYM_TO_STRING_TAG, "Temporal.PlainDate", ATTR_C)
  r.set_intrinsic("Temporal.PlainDate", pdc)
  r.set_intrinsic("Temporal.PlainDate.prototype", pdp)
  tm.define("PlainDate", pdc, BUILTIN_ATTRS)
  tm_fn_4 = ->(this, args, nt)
    v = tm_to_date_vals(js_arg(args, 0), js_arg(args, 1))
    tm_make_date(v[0], v[1], v[2], v[3])
  r.method(pdc, "from", 1, tm_fn_4)
  r.method(pdc, "compare", 2, ->(this, args, nt) tm_date_compare(js_arg(args, 0), js_arg(args, 1)))
  r.getter(pdp, "calendarId", ->(this, args, nt) tm_check(this, "Temporal.PlainDate", "calendarId")[3])
  tm_fn_101 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "era")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[0]
  r.getter(pdp, "era", tm_fn_101)
  tm_fn_102 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "eraYear")
    v = tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[1]
    v == nil ? nil : (v + ~0.0)
  r.getter(pdp, "eraYear", tm_fn_102)
  tm_fn_103 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "year")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[2] + ~0.0
  r.getter(pdp, "year", tm_fn_103)
  tm_fn_104 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "month")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[3] + ~0.0
  r.getter(pdp, "month", tm_fn_104)
  tm_fn_105 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "monthCode")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[4]
  r.getter(pdp, "monthCode", tm_fn_105)
  tm_fn_106 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "day")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[5] + ~0.0
  r.getter(pdp, "day", tm_fn_106)
  tm_fn_107 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "dayOfWeek")
    tm_iso_dow(d[0], d[1], d[2]) + ~0.0
  r.getter(pdp, "dayOfWeek", tm_fn_107)
  tm_fn_108 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "dayOfYear")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[6] + ~0.0
  r.getter(pdp, "dayOfYear", tm_fn_108)
  tm_fn_109 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "weekOfYear")
    d[3] == "iso8601" ? (tm_iso_week_info(d[0], d[1], d[2])[0] + ~0.0) : nil
  r.getter(pdp, "weekOfYear", tm_fn_109)
  tm_fn_110 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "yearOfWeek")
    d[3] == "iso8601" ? (tm_iso_week_info(d[0], d[1], d[2])[1] + ~0.0) : nil
  r.getter(pdp, "yearOfWeek", tm_fn_110)
  tm_fn_111 = ->(this, args, nt)
    tm_check(this, "Temporal.PlainDate", "daysInWeek")
    ~7.0
  r.getter(pdp, "daysInWeek", tm_fn_111)
  tm_fn_112 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "daysInMonth")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[7] + ~0.0
  r.getter(pdp, "daysInMonth", tm_fn_112)
  tm_fn_113 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "daysInYear")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[8] + ~0.0
  r.getter(pdp, "daysInYear", tm_fn_113)
  tm_fn_114 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "monthsInYear")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[9] + ~0.0
  r.getter(pdp, "monthsInYear", tm_fn_114)
  tm_fn_115 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "inLeapYear")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[10]
  r.getter(pdp, "inLeapYear", tm_fn_115)
  tm_fn_5 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "toPlainYearMonth")
    f = tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])
    ymd = tm_cal_resolve_month_and_day(d[3], f[2], f[3], nil, 1, "constrain")
    tm_make_ym(ymd[0], ymd[1], ymd[2], d[3])
  r.method(pdp, "toPlainYearMonth", 0, tm_fn_5)
  tm_fn_6 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "toPlainMonthDay")
    if d[3] == "iso8601"
      tm_make_md(1972, d[1], d[2], "iso8601")
    else
      f = tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])
      ymd = tm_cal_month_day_ref_iso(d[3], f[4], f[5], "constrain")
      tm_make_md(ymd[0], ymd[1], ymd[2], d[3])
  r.method(pdp, "toPlainMonthDay", 0, tm_fn_6)
  tm_fn_7 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "toPlainDateTime")
    ta = js_arg(args, 0)
    tf = ta == nil ? [0, 0, 0, 0, 0, 0] : tm_to_time_fields(ta, "constrain")
    tm_make_dt(d[0], d[1], d[2], tf[0], tf[1], tf[2], tf[3], tf[4], tf[5], d[3])
  r.method(pdp, "toPlainDateTime", 0, tm_fn_7)
  tm_fn_8 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "toZonedDateTime")
    item = js_arg(args, 0)
    if js_object?(item) && !js_special?(item, "Temporal.ZonedDateTime")
      tz_v = jget(item, "timeZone")
      js_throw_type("timeZone property is required") if tz_v == nil
      tz = tm_parse_tz_arg(tz_v)
      pt_v = jget(item, "plainTime")
      if pt_v == nil
        tm_make_zdt(tm_zdt_start_of_day_ns(tz, d[0], d[1], d[2]), tz, d[3])
      else
        tf = tm_to_time_fields(pt_v, "constrain")
        tm_make_zdt(tm_tz_disambiguate(tz, d[0], d[1], d[2], tf[0], tf[1], tf[2], tf[3], tf[4], tf[5], "compatible"), tz, d[3])
    else
      tz = tm_parse_tz_arg(item)
      tm_make_zdt(tm_zdt_start_of_day_ns(tz, d[0], d[1], d[2]), tz, d[3])
  r.method(pdp, "toZonedDateTime", 1, tm_fn_8)
  r.method(pdp, "with", 1, ->(this, args, nt) tm_date_with(this, js_arg(args, 0), js_arg(args, 1)))
  tm_fn_9 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDate", "withCalendar")
    tm_make_date(d[0], d[1], d[2], tm_to_cal_id(js_arg(args, 0)))
  r.method(pdp, "withCalendar", 1, tm_fn_9)
  r.method(pdp, "add", 1, ->(this, args, nt) tm_date_add_sub(this, js_arg(args, 0), js_arg(args, 1), 1))
  r.method(pdp, "subtract", 1, ->(this, args, nt) tm_date_add_sub(this, js_arg(args, 0), js_arg(args, 1), -1))
  r.method(pdp, "until", 1, ->(this, args, nt) tm_date_diff(this, js_arg(args, 0), js_arg(args, 1), :until))
  r.method(pdp, "since", 1, ->(this, args, nt) tm_date_diff(this, js_arg(args, 0), js_arg(args, 1), :since))
  tm_fn_10 = ->(this, args, nt)
    d1 = tm_check(this, "Temporal.PlainDate", "equals")
    d2 = tm_to_date_vals(js_arg(args, 0))
    d1[0] == d2[0] && d1[1] == d2[1] && d1[2] == d2[2] && d1[3] == d2[3]
  r.method(pdp, "equals", 1, tm_fn_10)
  r.method(pdp, "toString", 0, ->(this, args, nt) tm_date_to_string(this, js_arg(args, 0)))
  r.method(pdp, "toJSON", 0, ->(this, args, nt) tm_date_to_string(this, nil))
  r.method(pdp, "toLocaleString", 0, ->(this, args, nt) tm_to_locale_string(this, "Temporal.PlainDate", args, :date, :date))
  r.method(pdp, "valueOf", 0, ->(this, args, nt) js_throw_type("Cannot convert Temporal.PlainDate to a primitive value"))

  # 6. Temporal.PlainDateTime
  pdtp = js_new_object(r.object_proto)
  pdtc = r.native("PlainDateTime", 3, ->(this, args, nt) tm_dt_ctor(args, nt), true)
  pdtc.define("prototype", pdtp, 0)
  pdtp.define("constructor", pdtc, BUILTIN_ATTRS)
  pdtp.define(SYM_TO_STRING_TAG, "Temporal.PlainDateTime", ATTR_C)
  r.set_intrinsic("Temporal.PlainDateTime", pdtc)
  r.set_intrinsic("Temporal.PlainDateTime.prototype", pdtp)
  tm.define("PlainDateTime", pdtc, BUILTIN_ATTRS)
  tm_fn_11 = ->(this, args, nt)
    v = tm_to_dt_vals(js_arg(args, 0), js_arg(args, 1))
    tm_make_dt(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9])
  r.method(pdtc, "from", 1, tm_fn_11)
  r.method(pdtc, "compare", 2, ->(this, args, nt) tm_dt_compare(js_arg(args, 0), js_arg(args, 1)))
  r.getter(pdtp, "calendarId", ->(this, args, nt) tm_check(this, "Temporal.PlainDateTime", "calendarId")[9])
  tm_fn_116 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "era")
    tm_cal_iso_to_fields(d[9], d[0], d[1], d[2])[0]
  r.getter(pdtp, "era", tm_fn_116)
  tm_fn_117 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "eraYear")
    v = tm_cal_iso_to_fields(d[9], d[0], d[1], d[2])[1]
    v == nil ? nil : (v + ~0.0)
  r.getter(pdtp, "eraYear", tm_fn_117)
  tm_fn_118 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "year")
    tm_cal_iso_to_fields(d[9], d[0], d[1], d[2])[2] + ~0.0
  r.getter(pdtp, "year", tm_fn_118)
  tm_fn_119 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "month")
    tm_cal_iso_to_fields(d[9], d[0], d[1], d[2])[3] + ~0.0
  r.getter(pdtp, "month", tm_fn_119)
  tm_fn_120 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "monthCode")
    tm_cal_iso_to_fields(d[9], d[0], d[1], d[2])[4]
  r.getter(pdtp, "monthCode", tm_fn_120)
  tm_fn_121 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "day")
    tm_cal_iso_to_fields(d[9], d[0], d[1], d[2])[5] + ~0.0
  r.getter(pdtp, "day", tm_fn_121)
  r.getter(pdtp, "hour", ->(this, args, nt) tm_check(this, "Temporal.PlainDateTime", "hour")[3] + ~0.0)
  r.getter(pdtp, "minute", ->(this, args, nt) tm_check(this, "Temporal.PlainDateTime", "minute")[4] + ~0.0)
  r.getter(pdtp, "second", ->(this, args, nt) tm_check(this, "Temporal.PlainDateTime", "second")[5] + ~0.0)
  r.getter(pdtp, "millisecond", ->(this, args, nt) tm_check(this, "Temporal.PlainDateTime", "millisecond")[6] + ~0.0)
  r.getter(pdtp, "microsecond", ->(this, args, nt) tm_check(this, "Temporal.PlainDateTime", "microsecond")[7] + ~0.0)
  r.getter(pdtp, "nanosecond", ->(this, args, nt) tm_check(this, "Temporal.PlainDateTime", "nanosecond")[8] + ~0.0)
  tm_fn_122 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "dayOfWeek")
    tm_iso_dow(d[0], d[1], d[2]) + ~0.0
  r.getter(pdtp, "dayOfWeek", tm_fn_122)
  tm_fn_123 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "dayOfYear")
    tm_cal_iso_to_fields(d[9], d[0], d[1], d[2])[6] + ~0.0
  r.getter(pdtp, "dayOfYear", tm_fn_123)
  tm_fn_124 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "weekOfYear")
    d[9] == "iso8601" ? (tm_iso_week_info(d[0], d[1], d[2])[0] + ~0.0) : nil
  r.getter(pdtp, "weekOfYear", tm_fn_124)
  tm_fn_125 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "yearOfWeek")
    d[9] == "iso8601" ? (tm_iso_week_info(d[0], d[1], d[2])[1] + ~0.0) : nil
  r.getter(pdtp, "yearOfWeek", tm_fn_125)
  tm_fn_126 = ->(this, args, nt)
    tm_check(this, "Temporal.PlainDateTime", "daysInWeek")
    ~7.0
  r.getter(pdtp, "daysInWeek", tm_fn_126)
  tm_fn_127 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "daysInMonth")
    tm_cal_iso_to_fields(d[9], d[0], d[1], d[2])[7] + ~0.0
  r.getter(pdtp, "daysInMonth", tm_fn_127)
  tm_fn_128 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "daysInYear")
    tm_cal_iso_to_fields(d[9], d[0], d[1], d[2])[8] + ~0.0
  r.getter(pdtp, "daysInYear", tm_fn_128)
  tm_fn_129 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "monthsInYear")
    tm_cal_iso_to_fields(d[9], d[0], d[1], d[2])[9] + ~0.0
  r.getter(pdtp, "monthsInYear", tm_fn_129)
  tm_fn_130 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "inLeapYear")
    tm_cal_iso_to_fields(d[9], d[0], d[1], d[2])[10]
  r.getter(pdtp, "inLeapYear", tm_fn_130)
  r.method(pdtp, "with", 1, ->(this, args, nt) tm_dt_with(this, js_arg(args, 0), js_arg(args, 1)))
  tm_fn_12 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "withPlainTime")
    ta = js_arg(args, 0)
    tf = ta == nil ? [0, 0, 0, 0, 0, 0] : tm_to_time_fields(ta, "constrain")
    tm_make_dt(d[0], d[1], d[2], tf[0], tf[1], tf[2], tf[3], tf[4], tf[5], d[9])
  r.method(pdtp, "withPlainTime", 0, tm_fn_12)
  tm_fn_13 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "withCalendar")
    tm_make_dt(d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], tm_to_cal_id(js_arg(args, 0)))
  r.method(pdtp, "withCalendar", 1, tm_fn_13)
  r.method(pdtp, "add", 1, ->(this, args, nt) tm_dt_add_sub(this, js_arg(args, 0), js_arg(args, 1), 1))
  r.method(pdtp, "subtract", 1, ->(this, args, nt) tm_dt_add_sub(this, js_arg(args, 0), js_arg(args, 1), -1))
  r.method(pdtp, "until", 1, ->(this, args, nt) tm_dt_diff(this, js_arg(args, 0), js_arg(args, 1), :until))
  r.method(pdtp, "since", 1, ->(this, args, nt) tm_dt_diff(this, js_arg(args, 0), js_arg(args, 1), :since))
  r.method(pdtp, "round", 1, ->(this, args, nt) tm_dt_round(this, js_arg(args, 0)))
  tm_fn_14 = ->(this, args, nt)
    d1 = tm_check(this, "Temporal.PlainDateTime", "equals")
    d2 = tm_to_dt_vals(js_arg(args, 0))
    tm_dt_cmp_arr(d1, d2) == 0 && d1[9] == d2[9]
  r.method(pdtp, "equals", 1, tm_fn_14)
  r.method(pdtp, "toString", 0, ->(this, args, nt) tm_dt_to_string(this, js_arg(args, 0)))
  r.method(pdtp, "toJSON", 0, ->(this, args, nt) tm_dt_to_string(this, nil))
  r.method(pdtp, "toLocaleString", 0, ->(this, args, nt) tm_to_locale_string(this, "Temporal.PlainDateTime", args, :any, :all))
  r.method(pdtp, "valueOf", 0, ->(this, args, nt) js_throw_type("Cannot convert Temporal.PlainDateTime to a primitive value"))
  tm_fn_15 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "toZonedDateTime")
    tz = tm_parse_tz_arg(js_arg(args, 0))
    opts = tm_get_options_obj(js_arg(args, 1))
    dis = tm_get_disambig(opts)
    ep = tm_tz_disambiguate(tz, d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], dis)
    tm_make_zdt(ep, tz, d[9])
  r.method(pdtp, "toZonedDateTime", 1, tm_fn_15)
  tm_fn_16 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "toPlainDate")
    tm_make_date(d[0], d[1], d[2], d[9])
  r.method(pdtp, "toPlainDate", 0, tm_fn_16)
  tm_fn_17 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainDateTime", "toPlainTime")
    tm_make_time(d[3], d[4], d[5], d[6], d[7], d[8])
  r.method(pdtp, "toPlainTime", 0, tm_fn_17)

  # 7. Temporal.PlainYearMonth
  ymp = js_new_object(r.object_proto)
  ymc = r.native("PlainYearMonth", 2, ->(this, args, nt) tm_ym_ctor(args, nt), true)
  ymc.define("prototype", ymp, 0)
  ymp.define("constructor", ymc, BUILTIN_ATTRS)
  ymp.define(SYM_TO_STRING_TAG, "Temporal.PlainYearMonth", ATTR_C)
  r.set_intrinsic("Temporal.PlainYearMonth", ymc)
  r.set_intrinsic("Temporal.PlainYearMonth.prototype", ymp)
  tm.define("PlainYearMonth", ymc, BUILTIN_ATTRS)
  tm_fn_18 = ->(this, args, nt)
    v = tm_to_ym_vals(js_arg(args, 0), js_arg(args, 1))
    tm_make_ym(v[0], v[1], v[2], v[3])
  r.method(ymc, "from", 1, tm_fn_18)
  r.method(ymc, "compare", 2, ->(this, args, nt) tm_ym_compare(js_arg(args, 0), js_arg(args, 1)))
  r.getter(ymp, "calendarId", ->(this, args, nt) tm_check(this, "Temporal.PlainYearMonth", "calendarId")[3])
  tm_fn_131 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainYearMonth", "era")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[0]
  r.getter(ymp, "era", tm_fn_131)
  tm_fn_132 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainYearMonth", "eraYear")
    v = tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[1]
    v == nil ? nil : (v + ~0.0)
  r.getter(ymp, "eraYear", tm_fn_132)
  tm_fn_133 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainYearMonth", "year")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[2] + ~0.0
  r.getter(ymp, "year", tm_fn_133)
  tm_fn_134 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainYearMonth", "month")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[3] + ~0.0
  r.getter(ymp, "month", tm_fn_134)
  tm_fn_135 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainYearMonth", "monthCode")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[4]
  r.getter(ymp, "monthCode", tm_fn_135)
  tm_fn_136 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainYearMonth", "daysInMonth")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[7] + ~0.0
  r.getter(ymp, "daysInMonth", tm_fn_136)
  tm_fn_137 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainYearMonth", "daysInYear")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[8] + ~0.0
  r.getter(ymp, "daysInYear", tm_fn_137)
  tm_fn_138 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainYearMonth", "monthsInYear")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[9] + ~0.0
  r.getter(ymp, "monthsInYear", tm_fn_138)
  tm_fn_139 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainYearMonth", "inLeapYear")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[10]
  r.getter(ymp, "inLeapYear", tm_fn_139)
  r.method(ymp, "with", 1, ->(this, args, nt) tm_ym_with(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(ymp, "add", 1, ->(this, args, nt) tm_ym_add_sub(this, js_arg(args, 0), js_arg(args, 1), 1))
  r.method(ymp, "subtract", 1, ->(this, args, nt) tm_ym_add_sub(this, js_arg(args, 0), js_arg(args, 1), -1))
  r.method(ymp, "until", 1, ->(this, args, nt) tm_ym_diff(this, js_arg(args, 0), js_arg(args, 1), :until))
  r.method(ymp, "since", 1, ->(this, args, nt) tm_ym_diff(this, js_arg(args, 0), js_arg(args, 1), :since))
  tm_fn_19 = ->(this, args, nt)
    y1 = tm_check(this, "Temporal.PlainYearMonth", "equals")
    y2 = tm_to_ym_vals(js_arg(args, 0))
    y1[0] == y2[0] && y1[1] == y2[1] && y1[2] == y2[2] && y1[3] == y2[3]
  r.method(ymp, "equals", 1, tm_fn_19)
  r.method(ymp, "toString", 0, ->(this, args, nt) tm_ym_to_string(this, js_arg(args, 0)))
  r.method(ymp, "toJSON", 0, ->(this, args, nt) tm_ym_to_string(this, nil))
  r.method(ymp, "toLocaleString", 0, ->(this, args, nt) tm_to_locale_string(this, "Temporal.PlainYearMonth", args, :date, :date))
  r.method(ymp, "valueOf", 0, ->(this, args, nt) js_throw_type("Cannot convert Temporal.PlainYearMonth to a primitive value"))
  r.method(ymp, "toPlainDate", 1, ->(this, args, nt) tm_ym_to_plain_date(this, js_arg(args, 0)))

  # 8. Temporal.PlainMonthDay
  mdp = js_new_object(r.object_proto)
  mdc = r.native("PlainMonthDay", 2, ->(this, args, nt) tm_md_ctor(args, nt), true)
  mdc.define("prototype", mdp, 0)
  mdp.define("constructor", mdc, BUILTIN_ATTRS)
  mdp.define(SYM_TO_STRING_TAG, "Temporal.PlainMonthDay", ATTR_C)
  r.set_intrinsic("Temporal.PlainMonthDay", mdc)
  r.set_intrinsic("Temporal.PlainMonthDay.prototype", mdp)
  tm.define("PlainMonthDay", mdc, BUILTIN_ATTRS)
  tm_fn_20 = ->(this, args, nt)
    v = tm_to_md_vals(js_arg(args, 0), js_arg(args, 1))
    tm_make_md(v[0], v[1], v[2], v[3])
  r.method(mdc, "from", 1, tm_fn_20)
  r.getter(mdp, "calendarId", ->(this, args, nt) tm_check(this, "Temporal.PlainMonthDay", "calendarId")[3])
  tm_fn_140 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainMonthDay", "monthCode")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[4]
  r.getter(mdp, "monthCode", tm_fn_140)
  tm_fn_141 = ->(this, args, nt)
    d = tm_check(this, "Temporal.PlainMonthDay", "day")
    tm_cal_iso_to_fields(d[3], d[0], d[1], d[2])[5] + ~0.0
  r.getter(mdp, "day", tm_fn_141)
  r.method(mdp, "with", 1, ->(this, args, nt) tm_md_with(this, js_arg(args, 0), js_arg(args, 1)))
  tm_fn_21 = ->(this, args, nt)
    m1 = tm_check(this, "Temporal.PlainMonthDay", "equals")
    m2 = tm_to_md_vals(js_arg(args, 0))
    m1[0] == m2[0] && m1[1] == m2[1] && m1[2] == m2[2] && m1[3] == m2[3]
  r.method(mdp, "equals", 1, tm_fn_21)
  r.method(mdp, "toString", 0, ->(this, args, nt) tm_md_to_string(this, js_arg(args, 0)))
  r.method(mdp, "toJSON", 0, ->(this, args, nt) tm_md_to_string(this, nil))
  r.method(mdp, "toLocaleString", 0, ->(this, args, nt) tm_to_locale_string(this, "Temporal.PlainMonthDay", args, :date, :date))
  r.method(mdp, "valueOf", 0, ->(this, args, nt) js_throw_type("Cannot convert Temporal.PlainMonthDay to a primitive value"))
  r.method(mdp, "toPlainDate", 1, ->(this, args, nt) tm_md_to_plain_date(this, js_arg(args, 0)))

  # 9. Temporal.ZonedDateTime
  zdp = js_new_object(r.object_proto)
  zdc = r.native("ZonedDateTime", 2, ->(this, args, nt) tm_zdt_ctor(args, nt), true)
  zdc.define("prototype", zdp, 0)
  zdp.define("constructor", zdc, BUILTIN_ATTRS)
  zdp.define(SYM_TO_STRING_TAG, "Temporal.ZonedDateTime", ATTR_C)
  r.set_intrinsic("Temporal.ZonedDateTime", zdc)
  r.set_intrinsic("Temporal.ZonedDateTime.prototype", zdp)
  tm.define("ZonedDateTime", zdc, BUILTIN_ATTRS)
  tm_fn_22 = ->(this, args, nt)
    v = tm_to_zdt_vals(js_arg(args, 0), js_arg(args, 1))
    tm_make_zdt(v[0], v[1], v[2])
  r.method(zdc, "from", 1, tm_fn_22)
  r.method(zdc, "compare", 2, ->(this, args, nt) tm_zdt_compare(js_arg(args, 0), js_arg(args, 1)))
  r.getter(zdp, "calendarId", ->(this, args, nt) tm_check(this, "Temporal.ZonedDateTime", "calendarId")[2])
  r.getter(zdp, "timeZoneId", ->(this, args, nt) tm_check(this, "Temporal.ZonedDateTime", "timeZoneId")[1])
  tm_fn_142 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "era")
    dt = tm_zdt_local_dt(z)
    tm_cal_iso_to_fields(z[2], dt[0], dt[1], dt[2])[0]
  r.getter(zdp, "era", tm_fn_142)
  tm_fn_143 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "eraYear")
    dt = tm_zdt_local_dt(z)
    v = tm_cal_iso_to_fields(z[2], dt[0], dt[1], dt[2])[1]
    v == nil ? nil : (v + ~0.0)
  r.getter(zdp, "eraYear", tm_fn_143)
  tm_fn_144 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "year")
    dt = tm_zdt_local_dt(z)
    tm_cal_iso_to_fields(z[2], dt[0], dt[1], dt[2])[2] + ~0.0
  r.getter(zdp, "year", tm_fn_144)
  tm_fn_145 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "month")
    dt = tm_zdt_local_dt(z)
    tm_cal_iso_to_fields(z[2], dt[0], dt[1], dt[2])[3] + ~0.0
  r.getter(zdp, "month", tm_fn_145)
  tm_fn_146 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "monthCode")
    dt = tm_zdt_local_dt(z)
    tm_cal_iso_to_fields(z[2], dt[0], dt[1], dt[2])[4]
  r.getter(zdp, "monthCode", tm_fn_146)
  tm_fn_147 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "day")
    dt = tm_zdt_local_dt(z)
    tm_cal_iso_to_fields(z[2], dt[0], dt[1], dt[2])[5] + ~0.0
  r.getter(zdp, "day", tm_fn_147)
  r.getter(zdp, "hour", ->(this, args, nt) tm_zdt_local_dt(tm_check(this, "Temporal.ZonedDateTime", "hour"))[3] + ~0.0)
  r.getter(zdp, "minute", ->(this, args, nt) tm_zdt_local_dt(tm_check(this, "Temporal.ZonedDateTime", "minute"))[4] + ~0.0)
  r.getter(zdp, "second", ->(this, args, nt) tm_zdt_local_dt(tm_check(this, "Temporal.ZonedDateTime", "second"))[5] + ~0.0)
  r.getter(zdp, "millisecond", ->(this, args, nt) tm_zdt_local_dt(tm_check(this, "Temporal.ZonedDateTime", "millisecond"))[6] + ~0.0)
  r.getter(zdp, "microsecond", ->(this, args, nt) tm_zdt_local_dt(tm_check(this, "Temporal.ZonedDateTime", "microsecond"))[7] + ~0.0)
  r.getter(zdp, "nanosecond", ->(this, args, nt) tm_zdt_local_dt(tm_check(this, "Temporal.ZonedDateTime", "nanosecond"))[8] + ~0.0)
  r.getter(zdp, "epochMilliseconds", ->(this, args, nt) tm_int_to_num(tm_floor_div(tm_check(this, "Temporal.ZonedDateTime", "epochMilliseconds")[0], TM_NS_MS)))
  r.getter(zdp, "epochNanoseconds", ->(this, args, nt) JS:BigIntValue.new(tm_check(this, "Temporal.ZonedDateTime", "epochNanoseconds")[0]))
  tm_fn_148 = ->(this, args, nt)
    dt = tm_zdt_local_dt(tm_check(this, "Temporal.ZonedDateTime", "dayOfWeek"))
    tm_iso_dow(dt[0], dt[1], dt[2]) + ~0.0
  r.getter(zdp, "dayOfWeek", tm_fn_148)
  tm_fn_149 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "dayOfYear")
    dt = tm_zdt_local_dt(z)
    tm_cal_iso_to_fields(z[2], dt[0], dt[1], dt[2])[6] + ~0.0
  r.getter(zdp, "dayOfYear", tm_fn_149)
  tm_fn_150 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "weekOfYear")
    dt = tm_zdt_local_dt(z)
    z[2] == "iso8601" ? (tm_iso_week_info(dt[0], dt[1], dt[2])[0] + ~0.0) : nil
  r.getter(zdp, "weekOfYear", tm_fn_150)
  tm_fn_151 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "yearOfWeek")
    dt = tm_zdt_local_dt(z)
    z[2] == "iso8601" ? (tm_iso_week_info(dt[0], dt[1], dt[2])[1] + ~0.0) : nil
  r.getter(zdp, "yearOfWeek", tm_fn_151)
  r.getter(zdp, "hoursInDay", ->(this, args, nt) tm_zdt_hours_in_day(this))
  tm_fn_152 = ->(this, args, nt)
    tm_check(this, "Temporal.ZonedDateTime", "daysInWeek")
    ~7.0
  r.getter(zdp, "daysInWeek", tm_fn_152)
  tm_fn_153 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "daysInMonth")
    dt = tm_zdt_local_dt(z)
    tm_cal_iso_to_fields(z[2], dt[0], dt[1], dt[2])[7] + ~0.0
  r.getter(zdp, "daysInMonth", tm_fn_153)
  tm_fn_154 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "daysInYear")
    dt = tm_zdt_local_dt(z)
    tm_cal_iso_to_fields(z[2], dt[0], dt[1], dt[2])[8] + ~0.0
  r.getter(zdp, "daysInYear", tm_fn_154)
  tm_fn_155 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "monthsInYear")
    dt = tm_zdt_local_dt(z)
    tm_cal_iso_to_fields(z[2], dt[0], dt[1], dt[2])[9] + ~0.0
  r.getter(zdp, "monthsInYear", tm_fn_155)
  tm_fn_156 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "inLeapYear")
    dt = tm_zdt_local_dt(z)
    tm_cal_iso_to_fields(z[2], dt[0], dt[1], dt[2])[10]
  r.getter(zdp, "inLeapYear", tm_fn_156)
  tm_fn_157 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "offsetNanoseconds")
    tm_int_to_num(tm_tz_get_offset_ns(z[1], z[0]))
  r.getter(zdp, "offsetNanoseconds", tm_fn_157)
  tm_fn_158 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "offset")
    tm_fmt_offset_ns(tm_tz_get_offset_ns(z[1], z[0]))
  r.getter(zdp, "offset", tm_fn_158)
  r.method(zdp, "with", 1, ->(this, args, nt) tm_zdt_with(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(zdp, "withPlainTime", 0, ->(this, args, nt) tm_zdt_with_plain_time(this, js_arg(args, 0)))
  tm_fn_23 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "withTimeZone")
    tm_make_zdt(z[0], tm_parse_tz_arg(js_arg(args, 0)), z[2])
  r.method(zdp, "withTimeZone", 1, tm_fn_23)
  tm_fn_24 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "withCalendar")
    tm_make_zdt(z[0], z[1], tm_to_cal_id(js_arg(args, 0)))
  r.method(zdp, "withCalendar", 1, tm_fn_24)
  r.method(zdp, "add", 1, ->(this, args, nt) tm_zdt_add_sub(this, js_arg(args, 0), js_arg(args, 1), 1))
  r.method(zdp, "subtract", 1, ->(this, args, nt) tm_zdt_add_sub(this, js_arg(args, 0), js_arg(args, 1), -1))
  r.method(zdp, "until", 1, ->(this, args, nt) tm_zdt_diff(this, js_arg(args, 0), js_arg(args, 1), :until))
  r.method(zdp, "since", 1, ->(this, args, nt) tm_zdt_diff(this, js_arg(args, 0), js_arg(args, 1), :since))
  r.method(zdp, "round", 1, ->(this, args, nt) tm_zdt_round(this, js_arg(args, 0)))
  tm_fn_25 = ->(this, args, nt)
    z1 = tm_check(this, "Temporal.ZonedDateTime", "equals")
    z2 = tm_to_zdt_vals(js_arg(args, 0))
    z1[0] == z2[0] && tm_tz_equals?(z1[1], z2[1]) && z1[2] == z2[2]
  r.method(zdp, "equals", 1, tm_fn_25)
  r.method(zdp, "toString", 0, ->(this, args, nt) tm_zdt_to_string(this, js_arg(args, 0)))
  r.method(zdp, "toJSON", 0, ->(this, args, nt) tm_zdt_to_string(this, nil))
  r.method(zdp, "toLocaleString", 0, ->(this, args, nt) tm_to_locale_string(this, "Temporal.ZonedDateTime", args, :any, :all))
  r.method(zdp, "valueOf", 0, ->(this, args, nt) js_throw_type("Cannot convert Temporal.ZonedDateTime to a primitive value"))
  r.method(zdp, "startOfDay", 0, ->(this, args, nt) tm_zdt_start_of_day(this))
  r.method(zdp, "getTimeZoneTransition", 1, ->(this, args, nt) tm_zdt_get_transition(this, js_arg(args, 0)))
  r.method(zdp, "toInstant", 0, ->(this, args, nt) tm_make_instant(tm_check(this, "Temporal.ZonedDateTime", "toInstant")[0]))
  tm_fn_26 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "toPlainDate")
    dt = tm_zdt_local_dt(z)
    tm_make_date(dt[0], dt[1], dt[2], z[2])
  r.method(zdp, "toPlainDate", 0, tm_fn_26)
  tm_fn_27 = ->(this, args, nt)
    dt = tm_zdt_local_dt(tm_check(this, "Temporal.ZonedDateTime", "toPlainTime"))
    tm_make_time(dt[3], dt[4], dt[5], dt[6], dt[7], dt[8])
  r.method(zdp, "toPlainTime", 0, tm_fn_27)
  tm_fn_28 = ->(this, args, nt)
    z = tm_check(this, "Temporal.ZonedDateTime", "toPlainDateTime")
    dt = tm_zdt_local_dt(z)
    tm_make_dt(dt[0], dt[1], dt[2], dt[3], dt[4], dt[5], dt[6], dt[7], dt[8], z[2])
  r.method(zdp, "toPlainDateTime", 0, tm_fn_28)
  nil
