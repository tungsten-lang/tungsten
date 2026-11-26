# runtime/b_temporal_cal — Complete TC39 Temporal & Intl.Era-monthcode Calendar Engine:
# Supports all 16 ECMA-402 / Temporal calendars:
#   iso8601, gregory, buddhist, roc, japanese, coptic, ethiopic, ethioaa,
#   indian, islamic-civil, islamic-tbla, hebrew, persian, islamic-umalqura, chinese, dangi.

in JS

TM_CAL_VALID = {}
INTL_ECMA_CALENDARS.each ->(c) TM_CAL_VALID[c] = true

# Canonicalize a calendar identifier string (case-insensitive ASCII, handles aliases islamicc & ethiopic-amete-alem)
-> tm_cal_canon_id(s)
  js_throw_range("Invalid calendar identifier: " + s) if s.size == 0 || !s.ascii?
  low = intl_lower(s)
  low = "islamic-civil" if low == "islamicc"
  low = "ethioaa" if low == "ethiopic-amete-alem"
  return low if TM_CAL_VALID.has_key?(low)
  js_throw_range("Unsupported calendar: " + s)

# ToTemporalCalendarIdentifier ( val )
-> tm_to_cal_id(val)
  if js_special?(val, "Temporal.PlainDate")
    return val.internal[3]
  elsif js_special?(val, "Temporal.PlainDateTime")
    return val.internal[9]
  elsif js_special?(val, "Temporal.PlainYearMonth")
    return val.internal[3]
  elsif js_special?(val, "Temporal.PlainMonthDay")
    return val.internal[3]
  elsif js_special?(val, "Temporal.ZonedDateTime")
    return val.internal[2]
  js_throw_type("Calendar must be a string or Temporal object") if !js_string?(val)
  # Try direct calendar ID first (case-insensitive)
  if val.size > 0 && val.ascii? && intl_is_type_nonterminal?(val)
    low = intl_lower(val)
    low = "islamic-civil" if low == "islamicc"
    low = "ethioaa" if low == "ethiopic-amete-alem"
    return low if TM_CAL_VALID.has_key?(low)
  # Otherwise try parsing as ISO 8601 string and extract [u-ca=...] annotation (default "iso8601")!
  # Try full datetime, YearMonth, MonthDay, or Time string
  cal = tm_extract_cal_from_iso_str(val)
  js_throw_range("Invalid calendar identifier: " + val) if cal == nil
  tm_cal_canon_id(cal)

-> tm_extract_cal_from_iso_str(s)
  begin
    r = tm_parse_iso_datetime(s)
    return r["cal_ann"] != nil ? r["cal_ann"] : "iso8601"
  rescue e
    nil
  begin
    ym = tm_parse_iso_ym(s)
    return ym[3] != nil ? ym[3] : "iso8601"
  rescue e
    nil
  begin
    md = tm_parse_iso_md(s)
    return md[3] != nil ? md[3] : "iso8601"
  rescue e
    nil
  # Check TemporalTimeString (must NOT contain Z)
  begin
    tm_parse_iso_time(s)
    # Extract u-ca annotation from end if present
    idx = s.index("\[")
    if idx != nil
      ann = tm_parse_annotations(s, idx)
      return ann[2] != nil ? ann[2] : "iso8601"
    return "iso8601"
  rescue e
    nil
  nil

-> tm_cal_has_eras?(cal)
  cal != "iso8601" && cal != "chinese" && cal != "dangi"

# Canonicalize era string for a given calendar (returns canonical era or nil if invalid!)
-> tm_cal_canon_era(cal, era)
  return nil if !js_string?(era)
  if cal == "gregory"
    return "ce" if era == "ce" || era == "ad"
    return "bce" if era == "bce" || era == "bc"
  elsif cal == "japanese"
    return "ce" if era == "ce" || era == "ad"
    return "bce" if era == "bce" || era == "bc"
    return era if era == "meiji" || era == "taisho" || era == "showa" || era == "heisei" || era == "reiwa"
  elsif cal == "buddhist"
    return "be" if era == "be"
  elsif cal == "roc"
    return era if era == "roc" || era == "broc"
  elsif cal == "coptic"
    return "am" if era == "am"
  elsif cal == "ethiopic"
    return era if era == "am" || era == "aa"
  elsif cal == "ethioaa"
    return "aa" if era == "aa"
  elsif cal == "hebrew"
    return "am" if era == "am"
  elsif cal == "indian"
    return "shaka" if era == "shaka"
  elsif cal == "persian"
    return "ap" if era == "ap"
  elsif cal == "islamic-civil" || cal == "islamic-tbla" || cal == "islamic-umalqura"
    return era if era == "ah" || era == "bh"
  nil

# Resolve (era, eraYear) -> arithmetic year for calendar `cal` (returns Int or throws RangeError)
-> tm_cal_era_to_year(cal, era, era_y)
  ce = tm_cal_canon_era(cal, era)
  js_throw_range("Invalid era '" + era.to_s + "' for calendar '" + cal + "'") if ce == nil
  if cal == "gregory"
    return ce == "bce" ? (1 - era_y) : era_y
  elsif cal == "japanese"
    return 1 - era_y if ce == "bce"
    return era_y if ce == "ce"
    return 1867 + era_y if ce == "meiji"
    return 1911 + era_y if ce == "taisho"
    return 1925 + era_y if ce == "showa"
    return 1988 + era_y if ce == "heisei"
    return 2018 + era_y if ce == "reiwa"
  elsif cal == "buddhist" || cal == "coptic" || cal == "ethioaa" || cal == "hebrew" || cal == "indian" || cal == "persian"
    return era_y
  elsif cal == "roc"
    return ce == "broc" ? (1 - era_y) : era_y
  elsif cal == "ethiopic"
    return ce == "aa" ? (era_y - 5500) : era_y
  elsif cal == "islamic-civil" || cal == "islamic-tbla" || cal == "islamic-umalqura"
    return ce == "bh" ? (1 - era_y) : era_y
  js_throw_range("Invalid era for calendar " + cal)

# Format monthCode string "M01".."M13" or "M01L".."M12L"
-> tm_make_mcode(m_num, is_leap = false)
  base = "M" + tm_pad2(m_num)
  is_leap ? (base + "L") : base

# Validate monthCode syntax ONLY (M + 2 ASCII digits + optional L, per PrepareCalendarFields / ParseMonthCode!)
-> tm_parse_mcode_syntax(mc)
  js_throw_range("Invalid monthCode syntax: " + mc) if mc.size != 3 && mc.size != 4
  js_throw_range("Invalid monthCode syntax: " + mc) if mc.byte_at(0) != 77 # 'M'
  d1 = mc.byte_at(1)
  d2 = mc.byte_at(2)
  js_throw_range("Invalid monthCode syntax: " + mc) if d1 < 48 || d1 > 57 || d2 < 48 || d2 > 57
  if mc.size == 4
    js_throw_range("Invalid monthCode syntax: " + mc) if mc.byte_at(3) != 76 # 'L'
  mc

# Parse monthCode string -> [month_num(1..13), is_leap_bool] or throws RangeError!
-> tm_parse_mcode(mc)
  tm_parse_mcode_syntax(mc)
  d1 = mc.byte_at(1)
  d2 = mc.byte_at(2)
  mn = (d1 - 48) * 10 + (d2 - 48)
  is_l = mc.size == 4
  js_throw_range("Invalid monthCode: " + mc) if mn < 1 || mn > 13 || (is_l && mn > 12)
  [mn, is_l]

# ---- Pure-Tungsten Exact Algorithmic Calendars ----

# 1. Coptic / Ethiopic / EthioAA (identical 12x30 + 5/6 structure!)
TM_COPTIC_EPOCH   = tm_epoch_days(284, 8, 29)
TM_ETHIOPIC_EPOCH = tm_epoch_days(8, 8, 27)

-> tm_coptic_leap?(y)
  tm_floor_mod(y ## int, 4 ## int) == (3 ## int)

-> tm_coptic_ny(y, ep)
  yi = y ## int
  ep + (yi - (1 ## int)) * (365 ## int) + tm_floor_div(yi, 4 ## int)

-> tm_coptic_from_ed(ed, ep)
  d = ed - ep
  y = tm_floor_div((4 ## int) * d + (1463 ## int), 1461 ## int).to_i
  doy = (d - ((y - 1) ## int) * (365 ## int) - tm_floor_div(y ## int, 4 ## int)).to_i
  m = (doy / 30) + 1
  day = (doy % 30) + 1
  [y, m, day, doy + 1]

-> tm_coptic_to_ed(y, m, d, ep)
  tm_coptic_ny(y, ep) + (((m - 1) * 30 + (d - 1)) ## int)

# 2. Indian National (Saka) Calendar
-> tm_indian_from_ed(ed)
  ymd = tm_ymd_from_days(ed)
  gy = ymd[0]
  leap = tm_iso_leap?(gy)
  chaitra1 = tm_epoch_days(gy, 3, leap ? 21 : 22)
  if ed < chaitra1
    gy -= 1
    leap = tm_iso_leap?(gy)
    chaitra1 = tm_epoch_days(gy, 3, leap ? 21 : 22)
  y = gy - 78
  doy = (ed - chaitra1).to_i # 0-based
  m1_len = leap ? 31 : 30
  if doy < m1_len
    return [y, 1, doy + 1, doy + 1, leap]
  rem = doy - m1_len
  if rem < 155 # 5 months of 31 days (months 2..6)
    m = 2 + (rem / 31)
    day = (rem % 31) + 1
    return [y, m, day, doy + 1, leap]
  rem -= 155
  m = 7 + (rem / 30)
  day = (rem % 30) + 1
  [y, m, day, doy + 1, leap]

-> tm_indian_days_in_month(y, m)
  return tm_iso_leap?(y + 78) ? 31 : 30 if m == 1
  m <= 6 ? 31 : 30

-> tm_indian_to_ed(y, m, d)
  gy = y + 78
  leap = tm_iso_leap?(gy)
  chaitra1 = tm_epoch_days(gy, 3, leap ? 21 : 22)
  off = 0
  if m == 1
    off = d - 1
  elsif m <= 6
    off = (leap ? 31 : 30) + (m - 2) * 31 + (d - 1)
  else
    off = (leap ? 31 : 30) + 155 + (m - 7) * 30 + (d - 1)
  chaitra1 + (off ## int)

# 3. Islamic Tabular (islamic-civil & islamic-tbla)
TM_ISL_CIVIL_EPOCH = tm_epoch_days(622, 7, 19)
TM_ISL_TBLA_EPOCH  = tm_epoch_days(622, 7, 18)

-> tm_isl_leap?(y)
  tm_floor_mod((11 ## int) * (y ## int) + (14 ## int), 30 ## int) < (11 ## int)

-> tm_isl_ny(y, ep)
  yi = y ## int
  ep + (yi - (1 ## int)) * (354 ## int) + tm_floor_div((3 ## int) + (11 ## int) * yi, 30 ## int)

-> tm_isl_days_in_month(y, m)
  return 30 if m == 12 && tm_isl_leap?(y)
  (m % 2) == 1 ? 30 : 29

-> tm_isl_from_ed(ed, ep)
  y = tm_floor_div((30 ## int) * (ed - ep) + (10646 ## int), 10631 ## int).to_i
  while tm_isl_ny(y, ep) > ed
    y -= 1
  while tm_isl_ny(y + 1, ep) <= ed
    y += 1
  doy = (ed - tm_isl_ny(y, ep)).to_i
  m = (11 * doy + 330) / 325
  m = 12 if m > 12
  m = 1 if m < 1
  while ((m - 1) * 29 + (m / 2)) > doy
    m -= 1
  while m < 12 && (m * 29 + ((m + 1) / 2)) <= doy
    m += 1
  day = doy - ((m - 1) * 29 + (m / 2)) + 1
  [y, m, day, doy + 1]

-> tm_isl_to_ed(y, m, d, ep)
  tm_isl_ny(y, ep) + (((m - 1) * 29 + (m / 2) + (d - 1)) ## int)

# 4. Hebrew Calendar (exact Reingold & Dershowitz arithmetic!)
TM_HEB_EPOCH = tm_epoch_days(-3760, 9, 7)

-> tm_heb_leap?(y)
  tm_floor_mod((7 ## int) * (y ## int) + (1 ## int), 19 ## int) < (7 ## int)

-> tm_heb_delay1(y)
  yi = y ## int
  months = tm_floor_div((235 ## int) * yi - (234 ## int), 19 ## int)
  parts = (12084 ## int) + (13753 ## int) * months
  day = months * (29 ## int) + tm_floor_div(parts, 25920 ## int)
  if tm_floor_mod((3 ## int) * (day + (1 ## int)), 7 ## int) < (3 ## int)
    day = day + (1 ## int)
  day

-> tm_heb_ny(y)
  d0 = tm_heb_delay1(y - 1)
  d1 = tm_heb_delay1(y)
  d2 = tm_heb_delay1(y + 1)
  adj = 0 ## int
  if (d2 - d1) == (356 ## int)
    adj = 2 ## int
  elsif (d1 - d0) == (382 ## int)
    adj = 1 ## int
  TM_HEB_EPOCH + d1 + adj

-> tm_heb_month_table(y)
  yl = (tm_heb_ny(y + 1) - tm_heb_ny(y)).to_i
  long_h = (yl % 10) == 5
  short_k = (yl % 10) == 3
  leap = tm_heb_leap?(y)
  if leap
    lens = [30, long_h ? 30 : 29, short_k ? 29 : 30, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29]
    codes = ["M01", "M02", "M03", "M04", "M05", "M05L", "M06", "M07", "M08", "M09", "M10", "M11", "M12"]
    return [lens, codes, yl, true]
  lens = [30, long_h ? 30 : 29, short_k ? 29 : 30, 29, 30, 29, 30, 29, 30, 29, 30, 29]
  codes = ["M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08", "M09", "M10", "M11", "M12"]
  [lens, codes, yl, false]

-> tm_heb_from_ed(ed)
  y = tm_floor_div((ed - TM_HEB_EPOCH) * (98496 ## int), 35975351 ## int).to_i + 1
  while tm_heb_ny(y) > ed
    y -= 1
  while tm_heb_ny(y + 1) <= ed
    y += 1
  tbl = tm_heb_month_table(y)
  lens = tbl[0]
  codes = tbl[1]
  doy = (ed - tm_heb_ny(y)).to_i
  rem = doy
  m = 0
  while m < lens.size && rem >= lens[m]
    rem -= lens[m]
    m += 1
  [y, m + 1, codes[m], rem + 1, doy + 1, lens[m], tbl[2], lens.size, tbl[3]]

-> tm_heb_to_ed(y, m, d)
  tbl = tm_heb_month_table(y)
  lens = tbl[0]
  off = 0
  i = 0
  while i < m - 1
    off += lens[i]
    i += 1
  tm_heb_ny(y) + ((off + d - 1) ## int)

# ---- ICU-Backed Calendars (persian, islamic-umalqura [1300..1500], chinese, dangi) ----

TM_ICU_CAL_CACHE = {}

-> tm_icu_cal_handle(cal)
  c = TM_ICU_CAL_CACHE[cal]
  return c if c != nil
  fn_open = icu_sym("ucal_open")
  ut = icu_to_u16("UTC")
  tba = ut[0]
  lb = icu_cstr("en@calendar=" + cal)
  eb = icu_err_buf()
  h = icu_c5(fn_open, icu_ptr(tba), ut[1], icu_ptr(lb), 0, icu_ptr(eb))
  tba.size
  lb.size
  ec = icu_err_code(eb)
  eb.size
  return 0 if h == 0 || ec > 0
  TM_ICU_CAL_CACHE[cal] = h
  h

# Query ICU calendar at epoch_days `ed` -> [year, month(1-based), monthCode, day, doy, dim, diy, miy, leap_bool]
-> tm_icu_cal_from_ed(cal, ed)
  # islamic-umalqura falls back to islamic-civil outside its tabular range (roughly ISO 1882..2077, hijri 1300..1500)!
  if cal == "islamic-umalqura" && (ed < (-32140 ## int) || ed > (39440 ## int))
    ic = tm_isl_from_ed(ed, TM_ISL_CIVIL_EPOCH)
    y = ic[0]
    m = ic[1]
    d = ic[2]
    doy = ic[3]
    lp = tm_isl_leap?(y)
    return [y, m, tm_make_mcode(m, false), d, doy, tm_isl_days_in_month(y, m), lp ? 355 : 354, 12, lp]
  h = tm_icu_cal_handle(cal)
  ms_f = tm_int_to_num(ed) * ~86400000.0
  fn_setm = icu_sym("ucal_setMillis")
  fn_get = icu_sym("ucal_get")
  fn_lim = icu_sym("ucal_getLimit")
  eb = icu_err_buf()
  icu_c_pdp(fn_setm, h, wvalue_bits(ms_f) ## i64, icu_ptr(eb))
  icu_err_reset(eb)
  ey = icu_sext32(icu_c3(fn_get, h, 19, icu_ptr(eb))) # UCAL_EXTENDED_YEAR
  icu_err_reset(eb)
  m0 = icu_sext32(icu_c3(fn_get, h, 2, icu_ptr(eb)))  # UCAL_MONTH (0-based)
  icu_err_reset(eb)
  day = icu_sext32(icu_c3(fn_get, h, 5, icu_ptr(eb))) # UCAL_DATE
  icu_err_reset(eb)
  doy = icu_sext32(icu_c3(fn_get, h, 6, icu_ptr(eb))) # UCAL_DAY_OF_YEAR
  icu_err_reset(eb)
  is_lm = icu_sext32(icu_c3(fn_get, h, 22, icu_ptr(eb))) # UCAL_IS_LEAP_MONTH
  icu_err_reset(eb)
  om0 = icu_sext32(icu_c3(fn_get, h, 23, icu_ptr(eb))) # UCAL_ORDINAL_MONTH
  icu_err_reset(eb)
  dim = icu_sext32(icu_c4(fn_lim, h, 5, 5, icu_ptr(eb))) # UCAL_DATE, UCAL_ACTUAL_MAXIMUM = 5
  icu_err_reset(eb)
  diy = icu_sext32(icu_c4(fn_lim, h, 6, 5, icu_ptr(eb))) # UCAL_DAY_OF_YEAR, UCAL_ACTUAL_MAXIMUM = 5
  eb.size
  if cal == "chinese" || cal == "dangi"
    # Note: UCAL_ACTUAL_MAXIMUM for UCAL_ORDINAL_MONTH (23) may not be supported; compute miy from diy (> 360 -> 13 months!)
    miy = diy > 360 ? 13 : 12
    leap = miy == 13
    mc = tm_make_mcode(m0 + 1, is_lm != 0)
    return [ey, om0 + 1, mc, day, doy, dim, diy, miy, leap]
  if cal == "persian"
    leap = diy == 366
    return [ey, m0 + 1, tm_make_mcode(m0 + 1, false), day, doy, dim, diy, 12, leap]
  # islamic-umalqura inside [1300..1500]: if ICU falls outside, check
  if cal == "islamic-umalqura" && (ey < 1300 || ey > 1500)
    ic = tm_isl_from_ed(ed, TM_ISL_CIVIL_EPOCH)
    y = ic[0]
    m = ic[1]
    d = ic[2]
    doy2 = ic[3]
    lp = tm_isl_leap?(y)
    return [y, m, tm_make_mcode(m, false), d, doy2, tm_isl_days_in_month(y, m), lp ? 355 : 354, 12, lp]
  leap = diy == 355
  [ey, m0 + 1, tm_make_mcode(m0 + 1, false), day, doy, dim, diy, 12, leap]

# Build month structure table for an ICU calendar year `y`: returns Array of [month_num(1..13), monthCode, daysInMonth, start_ed]
TM_ICU_YEAR_CACHE = {}

-> tm_icu_cal_year_table(cal, y)
  ckey = cal + ":" + y.to_s
  cached = TM_ICU_YEAR_CACHE[ckey]
  return cached if cached != nil
  # For chinese/dangi far outside astronomical range, synthesize a clean deterministic 12-month table
  if (cal == "chinese" || cal == "dangi") && (y < -10000 || y > 10000)
    st = tm_epoch_days(y, 1, 20)
    mlens = [30, 29, 30, 29, 30, 29, 30, 30, 29, 30, 29, 30]
    months = []
    mi = 0
    while mi < 12
      months.push([mi + 1, tm_make_mcode(mi + 1, false), mlens[mi], st])
      st = st + (mlens[mi] ## int)
      mi += 1
    return months
  # Find approximate start epoch_days for year `y`
  if cal == "persian"
    est = tm_epoch_days(y + 621, 3, 21)
  elsif cal == "islamic-umalqura"
    est = tm_isl_ny(y, TM_ISL_CIVIL_EPOCH)
  else
    # chinese / dangi: year `y` starts in Jan/Feb of Gregorian year `y`!
    est = tm_epoch_days(y, 2, 1)
  # Walk to exact start of year `y` (day 1, month 1)
  cur = est
  r = tm_icu_cal_from_ed(cal, cur)
  tries = 0
  while r[0] < y && tries < 60
    cur = cur + (((y - r[0]) * 365 + 15) ## int)
    r = tm_icu_cal_from_ed(cal, cur)
    tries += 1
  while r[0] > y && tries < 120
    cur = cur - (((r[0] - y) * 365 + 15) ## int)
    r = tm_icu_cal_from_ed(cal, cur)
    tries += 1
  # Fine-tune if still off by a few years
  while r[0] < y && tries < 200
    cur = cur + (350 ## int)
    r = tm_icu_cal_from_ed(cal, cur)
    tries += 1
  while r[0] > y && tries < 280
    cur = cur - (350 ## int)
    r = tm_icu_cal_from_ed(cal, cur)
    tries += 1
  # Backtrack to day 1 of year `y` using doy!
  cur = cur - ((r[4] - 1) ## int)
  r = tm_icu_cal_from_ed(cal, cur)
  bt = 0
  while r[0] < y && bt < 400
    cur = cur + (1 ## int)
    r = tm_icu_cal_from_ed(cal, cur)
    bt += 1
  while r[0] == y && r[4] > 1 && bt < 450
    cur = cur - ((r[4] - 1) ## int)
    r = tm_icu_cal_from_ed(cal, cur)
    bt += 1
  # Now walk month by month through year `y`!
  months = []
  m_idx = 1
  while r[0] == y && m_idx <= 14
    dim = r[5]
    # Verify actual end of month (ICU UCAL_ACTUAL_MAXIMUM can occasionally be 1 off on chinese edges, verify!)
    r_end = tm_icu_cal_from_ed(cal, cur + ((dim - 1) ## int))
    if r_end[2] != r[2] || r_end[0] != y
      dim -= 1
    else
      r_nxt = tm_icu_cal_from_ed(cal, cur + (dim ## int))
      dim += 1 if r_nxt[2] == r[2] && r_nxt[0] == y
    months.push([m_idx, r[2], dim, cur])
    cur = cur + (dim ## int)
    r = tm_icu_cal_from_ed(cal, cur)
    m_idx += 1
  if months.size == 0
    # Fallback safety for extreme dates outside ICU ephemeris
    st = est
    mlens = cal == "persian" ? [31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29] : [30, 29, 30, 29, 30, 29, 30, 30, 29, 30, 29, 30]
    mi = 0
    while mi < 12
      months.push([mi + 1, tm_make_mcode(mi + 1, false), mlens[mi], st])
      st = st + (mlens[mi] ## int)
      mi += 1
  TM_ICU_YEAR_CACHE[ckey] = months if TM_ICU_YEAR_CACHE.size < 2000
  months

# ---- Master Calendar Conversion API ----

# Convert ISO (y, m, d) to calendar fields for `cal`!
# Returns [era, eraYear, year, month, monthCode, day, doy, daysInMonth, daysInYear, monthsInYear, inLeapYear]
-> tm_cal_iso_to_fields(cal, iso_y, iso_m, iso_d)
  if cal == "iso8601"
    lp = tm_iso_leap?(iso_y)
    return [nil, nil, iso_y, iso_m, tm_make_mcode(iso_m), iso_d, tm_iso_doy(iso_y, iso_m, iso_d), tm_iso_days_in_month(iso_y, iso_m), lp ? 366 : 365, 12, lp]
  if cal == "gregory"
    lp = tm_iso_leap?(iso_y)
    era = iso_y >= 1 ? "ce" : "bce"
    ey = iso_y >= 1 ? iso_y : (1 - iso_y)
    return [era, ey, iso_y, iso_m, tm_make_mcode(iso_m), iso_d, tm_iso_doy(iso_y, iso_m, iso_d), tm_iso_days_in_month(iso_y, iso_m), lp ? 366 : 365, 12, lp]
  if cal == "buddhist"
    lp = tm_iso_leap?(iso_y)
    by = iso_y + 543
    return ["be", by, by, iso_m, tm_make_mcode(iso_m), iso_d, tm_iso_doy(iso_y, iso_m, iso_d), tm_iso_days_in_month(iso_y, iso_m), lp ? 366 : 365, 12, lp]
  if cal == "roc"
    lp = tm_iso_leap?(iso_y)
    ry = iso_y - 1911
    era = ry >= 1 ? "roc" : "broc"
    ey = ry >= 1 ? ry : (1 - ry)
    return [era, ey, ry, iso_m, tm_make_mcode(iso_m), iso_d, tm_iso_doy(iso_y, iso_m, iso_d), tm_iso_days_in_month(iso_y, iso_m), lp ? 366 : 365, 12, lp]
  if cal == "japanese"
    lp = tm_iso_leap?(iso_y)
    era = nil
    ey = 0
    if iso_y > 2019 || (iso_y == 2019 && iso_m >= 5)
      era = "reiwa"
      ey = iso_y - 2018
    elsif iso_y > 1989 || (iso_y == 1989 && (iso_m > 1 || iso_d >= 8))
      era = "heisei"
      ey = iso_y - 1988
    elsif iso_y > 1926 || (iso_y == 1926 && iso_m == 12 && iso_d >= 25)
      era = "showa"
      ey = iso_y - 1925
    elsif iso_y > 1912 || (iso_y == 1912 && (iso_m > 7 || (iso_m == 7 && iso_d >= 30)))
      era = "taisho"
      ey = iso_y - 1911
    elsif iso_y >= 1873
      era = "meiji"
      ey = iso_y - 1867
    elsif iso_y >= 1
      era = "ce"
      ey = iso_y
    else
      era = "bce"
      ey = 1 - iso_y
    return [era, ey, iso_y, iso_m, tm_make_mcode(iso_m), iso_d, tm_iso_doy(iso_y, iso_m, iso_d), tm_iso_days_in_month(iso_y, iso_m), lp ? 366 : 365, 12, lp]
  ed = tm_epoch_days(iso_y, iso_m, iso_d)
  if cal == "coptic"
    r = tm_coptic_from_ed(ed, TM_COPTIC_EPOCH)
    y = r[0]
    m = r[1]
    d = r[2]
    doy = r[3]
    lp = tm_coptic_leap?(y)
    dim = m < 13 ? 30 : (lp ? 6 : 5)
    return ["am", y, y, m, tm_make_mcode(m), d, doy, dim, lp ? 366 : 365, 13, lp]
  if cal == "ethioaa"
    r = tm_coptic_from_ed(ed, TM_ETHIOPIC_EPOCH)
    y = r[0] + 5500
    m = r[1]
    d = r[2]
    doy = r[3]
    lp = tm_coptic_leap?(r[0])
    dim = m < 13 ? 30 : (lp ? 6 : 5)
    return ["aa", y, y, m, tm_make_mcode(m), d, doy, dim, lp ? 366 : 365, 13, lp]
  if cal == "ethiopic"
    r = tm_coptic_from_ed(ed, TM_ETHIOPIC_EPOCH)
    y = r[0]
    m = r[1]
    d = r[2]
    doy = r[3]
    lp = tm_coptic_leap?(y)
    dim = m < 13 ? 30 : (lp ? 6 : 5)
    era = y >= 1 ? "am" : "aa"
    ey = y >= 1 ? y : (y + 5500)
    return [era, ey, y, m, tm_make_mcode(m), d, doy, dim, lp ? 366 : 365, 13, lp]
  if cal == "indian"
    r = tm_indian_from_ed(ed)
    y = r[0]
    m = r[1]
    d = r[2]
    doy = r[3]
    lp = r[4]
    return ["shaka", y, y, m, tm_make_mcode(m), d, doy, tm_indian_days_in_month(y, m), lp ? 366 : 365, 12, lp]
  if cal == "islamic-civil" || cal == "islamic-tbla"
    ep = cal == "islamic-civil" ? TM_ISL_CIVIL_EPOCH : TM_ISL_TBLA_EPOCH
    r = tm_isl_from_ed(ed, ep)
    y = r[0]
    m = r[1]
    d = r[2]
    doy = r[3]
    lp = tm_isl_leap?(y)
    era = y >= 1 ? "ah" : "bh"
    ey = y >= 1 ? y : (1 - y)
    return [era, ey, y, m, tm_make_mcode(m), d, doy, tm_isl_days_in_month(y, m), lp ? 355 : 354, 12, lp]
  if cal == "hebrew"
    r = tm_heb_from_ed(ed)
    return ["am", r[0], r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8]]
  # ICU-backed: persian, islamic-umalqura, chinese, dangi
  r = tm_icu_cal_from_ed(cal, ed)
  y = r[0]
  era = nil
  ey = nil
  if cal == "persian"
    era = "ap"
    ey = y
  elsif cal == "islamic-umalqura"
    era = y >= 1 ? "ah" : "bh"
    ey = y >= 1 ? y : (1 - y)
  [era, ey, y, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8]]

# Helper: Get [months_in_year, month_idx, dim, month_start_ed] for calendar `cal`, arithmetic `year`, given (month_or_nil, monthCode_or_nil, overflow)
-> tm_cal_resolve_month_and_day(cal, year, month, mcode, day, overflow)
  # Validate monthCode format if present
  parsed_mc = mcode != nil ? tm_parse_mcode(mcode) : nil
  if cal == "iso8601" || cal == "gregory" || cal == "buddhist" || cal == "roc" || cal == "japanese"
    gy = cal == "buddhist" ? (year - 543) : (cal == "roc" ? (year + 1911) : year)
    if parsed_mc != nil
      js_throw_range("Invalid monthCode '" + mcode + "' for " + cal) if parsed_mc[1] || parsed_mc[0] > 12
      mc_m = parsed_mc[0]
      js_throw_range("Inconsistent month and monthCode") if month != nil && month != mc_m
      month = mc_m
    js_throw_range("Invalid month") if month < 1
    if month > 12
      js_throw_range("Month out of range") if overflow == "reject"
      month = 12
    dim = tm_iso_days_in_month(gy, month)
    js_throw_range("Invalid day") if day < 1
    if day > dim
      js_throw_range("Day out of range") if overflow == "reject"
      day = dim
    return [gy, month, day]

  if cal == "coptic" || cal == "ethiopic" || cal == "ethioaa"
    cy = cal == "ethioaa" ? (year - 5500) : year
    ep = cal == "coptic" ? TM_COPTIC_EPOCH : TM_ETHIOPIC_EPOCH
    if parsed_mc != nil
      js_throw_range("Invalid monthCode '" + mcode + "' for " + cal) if parsed_mc[1]
      mc_m = parsed_mc[0]
      js_throw_range("Inconsistent month and monthCode") if month != nil && month != mc_m
      month = mc_m
    js_throw_range("Invalid month") if month < 1
    if month > 13
      js_throw_range("Month out of range") if overflow == "reject"
      month = 13
    lp = tm_coptic_leap?(cy)
    dim = month < 13 ? 30 : (lp ? 6 : 5)
    js_throw_range("Invalid day") if day < 1
    if day > dim
      js_throw_range("Day out of range") if overflow == "reject"
      day = dim
    return tm_ymd_from_days(tm_coptic_to_ed(cy, month, day, ep))

  if cal == "indian"
    if parsed_mc != nil
      js_throw_range("Invalid monthCode '" + mcode + "' for indian") if parsed_mc[1] || parsed_mc[0] > 12
      mc_m = parsed_mc[0]
      js_throw_range("Inconsistent month and monthCode") if month != nil && month != mc_m
      month = mc_m
    js_throw_range("Invalid month") if month < 1
    if month > 12
      js_throw_range("Month out of range") if overflow == "reject"
      month = 12
    dim = tm_indian_days_in_month(year, month)
    js_throw_range("Invalid day") if day < 1
    if day > dim
      js_throw_range("Day out of range") if overflow == "reject"
      day = dim
    return tm_ymd_from_days(tm_indian_to_ed(year, month, day))

  if cal == "islamic-civil" || cal == "islamic-tbla" || (cal == "islamic-umalqura" && (year < 1300 || year > 1500))
    ep = cal == "islamic-tbla" ? TM_ISL_TBLA_EPOCH : TM_ISL_CIVIL_EPOCH
    if parsed_mc != nil
      js_throw_range("Invalid monthCode '" + mcode + "' for " + cal) if parsed_mc[1] || parsed_mc[0] > 12
      mc_m = parsed_mc[0]
      js_throw_range("Inconsistent month and monthCode") if month != nil && month != mc_m
      month = mc_m
    js_throw_range("Invalid month") if month < 1
    if month > 12
      js_throw_range("Month out of range") if overflow == "reject"
      month = 12
    dim = tm_isl_days_in_month(year, month)
    js_throw_range("Invalid day") if day < 1
    if day > dim
      js_throw_range("Day out of range") if overflow == "reject"
      day = dim
    return tm_ymd_from_days(tm_isl_to_ed(year, month, day, ep))

  if cal == "hebrew"
    tbl = tm_heb_month_table(year)
    lens = tbl[0]
    codes = tbl[1]
    miy = lens.size
    if parsed_mc != nil
      # Only M01..M12 and M05L are valid Hebrew month codes!
      js_throw_range("Invalid Hebrew monthCode: " + mcode) if parsed_mc[0] > 12 || (parsed_mc[1] && parsed_mc[0] != 5)
      idx = codes.index(mcode)
      if idx == nil
        # M05L in a non-leap year!
        js_throw_range("M05L does not exist in non-leap Hebrew year " + year.to_s) if overflow == "reject"
        idx = codes.index("M06") # Constrain M05L -> M06 (Adar)!
      mc_m = idx + 1
      js_throw_range("Inconsistent month and monthCode") if month != nil && month != mc_m
      month = mc_m
    js_throw_range("Invalid month") if month < 1
    if month > miy
      js_throw_range("Month out of range") if overflow == "reject"
      month = miy
    dim = lens[month - 1]
    js_throw_range("Invalid day") if day < 1
    if day > dim
      js_throw_range("Day out of range") if overflow == "reject"
      day = dim
    return tm_ymd_from_days(tm_heb_to_ed(year, month, day))

  # ICU-backed: persian, islamic-umalqura (1300..1500), chinese, dangi
  tbl = tm_icu_cal_year_table(cal, year)
  miy = tbl.size
  if parsed_mc != nil
    if cal == "persian" || cal == "islamic-umalqura"
      js_throw_range("Invalid monthCode '" + mcode + "' for " + cal) if parsed_mc[1] || parsed_mc[0] > 12
    else
      # chinese / dangi: M01..M12 and M01L..M12L allowed
      js_throw_range("Invalid monthCode '" + mcode + "' for " + cal) if parsed_mc[0] > 12
    found_idx = -1
    k = 0
    while k < miy
      if tbl[k][1] == mcode
        found_idx = k
        break
      k += 1
    if found_idx < 0
      # Leap month code (e.g. M02L) in a year without that leap month!
      js_throw_range("MonthCode " + mcode + " does not exist in year " + year.to_s) if overflow == "reject"
      # Constrain MxxL -> Mxx!
      non_leap = tm_make_mcode(parsed_mc[0], false)
      k = 0
      while k < miy
        if tbl[k][1] == non_leap
          found_idx = k
          break
        k += 1
    mc_m = found_idx + 1
    js_throw_range("Inconsistent month and monthCode") if month != nil && month != mc_m
    month = mc_m
  js_throw_range("Invalid month") if month < 1
  if month > miy
    js_throw_range("Month out of range") if overflow == "reject"
    month = miy
  mrow = tbl[month - 1]
  dim = mrow[2]
  js_throw_range("Invalid day") if day < 1
  if day > dim
    js_throw_range("Day out of range") if overflow == "reject"
    day = dim
  tm_ymd_from_days(mrow[3] + ((day - 1) ## int))

# Resolve calendar property bag fields -> ISO [y, m, d]!
# fields hash keys: "era", "eraYear", "year", "month", "monthCode", "day" (values already converted or nil)
# mode: :date, :year_month, :month_day
-> tm_cal_fields_to_iso(cal, fields, overflow, mode)
  era = fields["era"]
  era_y = fields["eraYear"]
  year = fields["year"]
  month = fields["month"]
  mcode = fields["monthCode"]
  day = fields["day"]

  # Per CalendarResolveFields: ALL missing-field TypeError checks MUST precede RangeError suitability checks!
  if tm_cal_has_eras?(cal)
    if (era != nil && era_y == nil) || (era == nil && era_y != nil)
      js_throw_type("era and eraYear must both be provided or both omitted")

  if mode == :date || mode == :year_month
    js_throw_type("Missing year field") if year == nil && era == nil
    js_throw_type("Missing month or monthCode field") if month == nil && mcode == nil
    if mode == :date
      js_throw_type("Missing day field") if day == nil
    else
      day = 1
  else
    # mode == :month_day
    js_throw_type("Missing day field") if day == nil
    js_throw_type("Missing month or monthCode field") if month == nil && mcode == nil
    if year == nil && era == nil && month != nil && cal != "iso8601"
      js_throw_type("Non-ISO PlainMonthDay requires year when month is provided")

  # Now validate era -> year mapping (RangeError on unknown era or year mismatch!)
  if tm_cal_has_eras?(cal) && era != nil
    ey_yr = tm_cal_era_to_year(cal, era, era_y)
    if year != nil && year != ey_yr
      js_throw_range("Inconsistent year and era/eraYear")
    year = ey_yr

  if mode == :date || mode == :year_month
    # Guard extreme years before invoking calendar conversion
    js_throw_range("Year out of range") if year < -285000 || year > 285000
    ymd = tm_cal_resolve_month_and_day(cal, year, month, mcode, day, overflow)
    if mode == :date
      js_throw_range("Date out of Temporal range") if !tm_iso_date_within_limits?(ymd[0], ymd[1], ymd[2])
    else
      js_throw_range("YearMonth out of Temporal range") if !tm_iso_ym_within_limits?(ymd[0], ymd[1])
    return ymd

  # mode == :month_day
  if year != nil
    if cal == "iso8601"
      # Special case for iso8601 PlainMonthDay: year is used ONLY for leap-year overflow check, NOT range-checked!
      ymd0 = tm_cal_resolve_month_and_day(cal, year, month, mcode, day, overflow)
      return [1972, ymd0[1], ymd0[2]]
    js_throw_range("Year out of range") if year < -285000 || year > 285000
    # Non-ISO with year: resolve full date, check ISO range, then map (monthCode, day) to canonical reference ISO year!
    ymd0 = tm_cal_resolve_month_and_day(cal, year, month, mcode, day, overflow)
    js_throw_range("Date out of Temporal range") if !tm_iso_date_within_limits?(ymd0[0], ymd0[1], ymd0[2])
    f = tm_cal_iso_to_fields(cal, ymd0[0], ymd0[1], ymd0[2])
    mcode = f[4]
    day = f[5]
    return tm_cal_month_day_ref_iso(cal, mcode, day, overflow)
  elsif month != nil && mcode == nil
    mcode = tm_make_mcode(month)
  if cal == "iso8601"
    pmc = tm_parse_mcode(mcode)
    js_throw_range("Invalid monthCode for iso8601: " + mcode) if pmc[1] || pmc[0] > 12
    js_throw_range("Inconsistent month and monthCode") if month != nil && month != pmc[0]
    res = tm_constrain_iso_date(1972, pmc[0], day, overflow)
    return [1972, res[1], res[2]]
  # Non-ISO PlainMonthDay: find canonical reference ISO date per NonISOMonthDayToISOReferenceDate!
  tm_cal_month_day_ref_iso(cal, mcode, day, overflow)

# Table 6 (ECMA-402 / Intl.Era-monthcode 4.1.21) for chinese/dangi leap month reference years!
TM_LUNISOLAR_LEAP_29 = {
  "M02L" => 1947, "M03L" => 1966, "M04L" => 1963, "M05L" => 1971, "M06L" => 1960,
  "M07L" => 1968, "M08L" => 1957, "M09L" => 2014, "M10L" => 1984, "M11L" => 2033
}
TM_LUNISOLAR_LEAP_30 = {
  "M03L" => 1955, "M04L" => 1944, "M05L" => 1952, "M06L" => 1941, "M07L" => 1938
}

-> tm_cal_month_day_ref_iso(cal, mcode, day, overflow)
  pmc = tm_parse_mcode(mcode)
  js_throw_range("Invalid day") if day < 1
  if cal == "gregory" || cal == "buddhist" || cal == "roc" || cal == "japanese"
    js_throw_range("Invalid monthCode: " + mcode) if pmc[1] || pmc[0] > 12
    res = tm_constrain_iso_date(1972, pmc[0], day, overflow)
    return [1972, res[1], res[2]]
  if cal == "chinese" || cal == "dangi"
    js_throw_range("Invalid monthCode for " + cal + ": " + mcode) if pmc[0] > 12
    if day > 30
      js_throw_range("Day out of range for " + cal) if overflow == "reject"
      day = 30
    if pmc[1]
      # Leap month code M01L..M12L per Table 6!
      if !TM_LUNISOLAR_LEAP_29.has_key?(mcode) || (day == 30 && !TM_LUNISOLAR_LEAP_30.has_key?(mcode))
        js_throw_range("Invalid leap month/day for " + cal + ": " + mcode + "-" + day.to_s) if overflow == "reject"
        # Constrain to non-leap month of the same number & day!
        mcode = tm_make_mcode(pmc[0], false)
      else
        ref_y = day == 30 ? TM_LUNISOLAR_LEAP_30[mcode] : TM_LUNISOLAR_LEAP_29[mcode]
        return tm_cal_resolve_month_and_day(cal, ref_y, nil, mcode, day, "reject")
    # Regular month M01..M12 (days 1..30): search backwards from calendar year containing 1972-12-31!
    f72 = tm_cal_iso_to_fields(cal, 1972, 12, 31)
    start_y = f72[2]
    ed_lim = tm_epoch_days(1972, 12, 31)
    back = 0
    while back <= 40
      try_y = start_y - back
      begin
        ymd = tm_cal_resolve_month_and_day(cal, try_y, nil, mcode, day, "reject")
        return ymd if tm_epoch_days(ymd[0], ymd[1], ymd[2]) <= ed_lim
      rescue e
        nil
      back += 1
    js_throw_range("Could not resolve reference date for " + cal + " " + mcode + "-" + day.to_s)
  # All other non-ISO calendars: coptic, ethiopic, ethioaa, indian, islamic-civil, islamic-tbla, islamic-umalqura, hebrew, persian
  # Validate monthCode suitability for calendar first!
  if cal == "hebrew"
    js_throw_range("Invalid Hebrew monthCode: " + mcode) if pmc[0] > 12 || (pmc[1] && pmc[0] != 5)
  elsif cal == "coptic" || cal == "ethiopic" || cal == "ethioaa"
    js_throw_range("Invalid monthCode for " + cal + ": " + mcode) if pmc[1] || pmc[0] > 13
  else
    js_throw_range("Invalid monthCode for " + cal + ": " + mcode) if pmc[1] || pmc[0] > 12
  # Determine max possible daysInMonth for `mcode` across calendar years on or before 1972-12-31!
  f72 = tm_cal_iso_to_fields(cal, 1972, 12, 31)
  start_y = f72[2]
  ed_lim = tm_epoch_days(1972, 12, 31)
  max_dim = 0
  back = 0
  while back <= 35
    try_y = start_y - back
    begin
      ymd1 = tm_cal_resolve_month_and_day(cal, try_y, nil, mcode, 1, "reject")
      if tm_epoch_days(ymd1[0], ymd1[1], ymd1[2]) <= ed_lim
        ff = tm_cal_iso_to_fields(cal, ymd1[0], ymd1[1], ymd1[2])
        max_dim = ff[7] if ff[7] > max_dim
    rescue e
      nil
    back += 1
  js_throw_range("Invalid monthCode for " + cal + ": " + mcode) if max_dim == 0
  if day > max_dim
    js_throw_range("Day out of range for " + cal + " " + mcode) if overflow == "reject"
    day = max_dim
  # Now pick the LATEST occurrence of (mcode, day) on or before 1972-12-31!
  back = 0
  while back <= 35
    try_y = start_y - back
    begin
      ymd = tm_cal_resolve_month_and_day(cal, try_y, nil, mcode, day, "reject")
      return ymd if tm_epoch_days(ymd[0], ymd[1], ymd[2]) <= ed_lim
    rescue e
      nil
    back += 1
  js_throw_range("Invalid monthCode/day for calendar " + cal + ": " + mcode + "-" + day.to_s)

# ---- Calendar Date Addition & Difference ----

# CalendarDateAdd ( cal, iso_y, iso_m, iso_d, dy, dmo, dw, dd, overflow ) -> [ny, nm, nd]
-> tm_cal_date_add(cal, iso_y, iso_m, iso_d, dy, dmo, dw, dd, overflow)
  if cal == "iso8601" || cal == "gregory" || cal == "buddhist" || cal == "roc" || cal == "japanese"
    return tm_add_iso_date(iso_y, iso_m, iso_d, dy, dmo, dw, dd, overflow)
  if dy == (0 ## int) && dmo == (0 ## int)
    # Pure weeks + days addition is calendar-independent!
    ed = tm_epoch_days(iso_y, iso_m, iso_d) + (dw ## int) * (7 ## int) + (dd ## int)
    js_throw_range("Date out of range") if ed < (-100000005 ## int) || ed > (100000005 ## int)
    res = tm_ymd_from_days(ed)
    js_throw_range("Date out of range") if !tm_iso_date_within_limits?(res[0], res[1], res[2])
    return res
  # Non-Gregorian calendar with years/months!
  f = tm_cal_iso_to_fields(cal, iso_y, iso_m, iso_d)
  cy = f[2]
  cm = f[3]
  cmc = f[4]
  cd = f[5]
  # Step 1: Add years (preserving monthCode!)
  if dy != (0 ## int)
    ny = (cy ## int) + (dy ## int)
    js_throw_range("Year out of range") if ny < (-285000 ## int) || ny > (285000 ## int)
    cy = ny.to_i
    # Resolve (cy, monthCode=cmc, day=cd) under overflow if dmo == 0, else find ordinal month for cmc in cy!
    if dmo == (0 ## int)
      ymd1 = tm_cal_resolve_month_and_day(cal, cy, nil, cmc, cd, overflow)
      ed = tm_epoch_days(ymd1[0], ymd1[1], ymd1[2]) + (dw ## int) * (7 ## int) + (dd ## int)
      res = tm_ymd_from_days(ed)
      js_throw_range("Date out of range") if !tm_iso_date_within_limits?(res[0], res[1], res[2])
      return res
    # Resolve monthCode in new year under `overflow` (throws RangeError on missing leap month when overflow == "reject"!)
    ymd_y = tm_cal_resolve_month_and_day(cal, cy, nil, cmc, 1, overflow)
    fy = tm_cal_iso_to_fields(cal, ymd_y[0], ymd_y[1], ymd_y[2])
    cm = fy[3]
  # Step 2: Add months (advancing across variable-length years 12 or 13 months!)
  rem_m = dmo ## int
  if rem_m != (0 ## int)
    if cal == "coptic" || cal == "ethiopic" || cal == "ethioaa"
      tot = ((cm - 1) ## int) + rem_m
      cy = ((cy ## int) + tm_floor_div(tot, 13 ## int)).to_i
      cm = tm_floor_mod(tot, 13 ## int).to_i + 1
    elsif cal == "indian" || cal == "islamic-civil" || cal == "islamic-tbla" || cal == "islamic-umalqura" || cal == "persian"
      tot = ((cm - 1) ## int) + rem_m
      cy = ((cy ## int) + tm_floor_div(tot, 12 ## int)).to_i
      cm = tm_floor_mod(tot, 12 ## int).to_i + 1
    else
      # Lunisolar calendars (hebrew, chinese, dangi): 12 or 13 months per year!
      m_cur = cm
      if rem_m > (0 ## int)
        while rem_m > (0 ## int)
          miy = tm_cal_months_in_year(cal, cy)
          left = miy - m_cur
          if rem_m <= (left ## int)
            m_cur += rem_m.to_i
            rem_m = 0 ## int
          else
            rem_m = rem_m - ((left + 1) ## int)
            cy += 1
            m_cur = 1
      else
        while rem_m < (0 ## int)
          if ((0 ## int) - rem_m) < (m_cur ## int)
            m_cur += rem_m.to_i
            rem_m = 0 ## int
          else
            rem_m = rem_m + (m_cur ## int)
            cy -= 1
            m_cur = tm_cal_months_in_year(cal, cy)
      cm = m_cur
  ymd2 = tm_cal_resolve_month_and_day(cal, cy, cm, nil, cd, overflow)
  ed = tm_epoch_days(ymd2[0], ymd2[1], ymd2[2]) + (dw ## int) * (7 ## int) + (dd ## int)
  js_throw_range("Date out of range") if ed < (-100000005 ## int) || ed > (100000005 ## int)
  res = tm_ymd_from_days(ed)
  js_throw_range("Date out of range") if !tm_iso_date_within_limits?(res[0], res[1], res[2])
  res

-> tm_cal_months_in_year(cal, y)
  return 13 if cal == "coptic" || cal == "ethiopic" || cal == "ethioaa"
  return tm_heb_leap?(y) ? 13 : 12 if cal == "hebrew"
  return tm_icu_cal_year_table(cal, y).size if cal == "chinese" || cal == "dangi"
  12

-> tm_mcode_order_key(mc)
  p = tm_parse_mcode(mc)
  p[0] * 2 + (p[1] ? 1 : 0)

# Count ordinal months from (cy1, cm1) to (cy2, cm2) in calendar `cal`
-> tm_cal_count_months(cal, cy1, cm1, cy2, cm2)
  return (cy2 - cy1) * 13 + (cm2 - cm1) if cal == "coptic" || cal == "ethiopic" || cal == "ethioaa"
  return (cy2 - cy1) * 12 + (cm2 - cm1) if cal == "indian" || cal == "islamic-civil" || cal == "islamic-tbla" || cal == "islamic-umalqura" || cal == "persian"
  # Variable-length lunisolar years (hebrew, chinese, dangi)
  return cm2 - cm1 if cy1 == cy2
  if cy2 > cy1
    tot = tm_cal_months_in_year(cal, cy1) - cm1
    y = cy1 + 1
    while y < cy2
      tot += tm_cal_months_in_year(cal, y)
      y += 1
    return tot + cm2
  tot = cm1
  y = cy1 - 1
  while y > cy2
    tot += tm_cal_months_in_year(cal, y)
    y -= 1
  tot += tm_cal_months_in_year(cal, cy2) - cm2
  0 - tot

# CalendarDateUntil ( cal, y1, m1, d1, y2, m2, d2, largest_unit ) -> [years, months, weeks, days]
# Exact ECMA-402 / Intl.Era-monthcode CalendarDateUntil (unclamped monthCode & day comparisons!)
-> tm_cal_date_until(cal, y1, m1, d1, y2, m2, d2, largest_unit)
  if cal == "iso8601" || cal == "gregory" || cal == "buddhist" || cal == "roc" || cal == "japanese"
    return tm_diff_iso_date(y1, m1, d1, y2, m2, d2, largest_unit)
  ed1 = tm_epoch_days(y1, m1, d1)
  ed2 = tm_epoch_days(y2, m2, d2)
  diff_d = (ed2 - ed1).to_i
  return [0, 0, 0, 0] if diff_d == 0
  return [0, 0, 0, diff_d] if largest_unit == "day"
  if largest_unit == "week"
    w = diff_d / 7
    return [0, 0, w, diff_d - w * 7]
  sign = diff_d > 0 ? 1 : -1
  f1 = tm_cal_iso_to_fields(cal, y1, m1, d1)
  f2 = tm_cal_iso_to_fields(cal, y2, m2, d2)
  cy1 = f1[2]; mc1 = f1[4]; cd1 = f1[5]; mk1 = tm_mcode_order_key(mc1)
  cy2 = f2[2]; mc2 = f2[4]; cd2 = f2[5]; mk2 = tm_mcode_order_key(mc2)

  # Step 1: Compute unclamped whole years!
  years = 0
  if largest_unit == "year"
    years = cy2 - cy1
    if sign > 0
      if mk2 < mk1 || (mk2 == mk1 && cd2 < cd1)
        years -= 1
    else
      if mk2 > mk1 || (mk2 == mk1 && cd2 > cd1)
        years += 1

  # Step 2: Anchor after adding `years` (preserving original cd1 for end-of-month comparison!)
  mid_y = cy1 + years
  mid_m = f1[3]
  if years != 0
    ymd_y = tm_cal_resolve_month_and_day(cal, mid_y, nil, mc1, 1, "constrain")
    fy = tm_cal_iso_to_fields(cal, ymd_y[0], ymd_y[1], ymd_y[2])
    mid_m = fy[3]
  # Count exact ordinal months from (mid_y, mid_m) to (cy2, f2[3])!
  months = tm_cal_count_months(cal, mid_y, mid_m, cy2, f2[3])
  # Adjust if target day hasn't reached starting day (never count end-of-month clamping as a full month!)
  if sign > 0 && cd2 < cd1
    months -= 1
  elsif sign < 0 && cd2 > cd1
    months += 1
  # Ensure `years` and `months` have consistent sign with `sign` (e.g., M05L -> M06 when years was adjusted)
  if sign > 0 && months < 0
    years -= 1
    mid_y = cy1 + years
    ymd_y = tm_cal_resolve_month_and_day(cal, mid_y, nil, mc1, 1, "constrain")
    fy = tm_cal_iso_to_fields(cal, ymd_y[0], ymd_y[1], ymd_y[2])
    months = tm_cal_count_months(cal, mid_y, fy[3], cy2, f2[3])
    months -= 1 if cd2 < cd1
  elsif sign < 0 && months > 0
    years += 1
    mid_y = cy1 + years
    ymd_y = tm_cal_resolve_month_and_day(cal, mid_y, nil, mc1, 1, "constrain")
    fy = tm_cal_iso_to_fields(cal, ymd_y[0], ymd_y[1], ymd_y[2])
    months = tm_cal_count_months(cal, mid_y, fy[3], cy2, f2[3])
    months += 1 if cd2 > cd1
  # Compute remaining days from CalendarDateAdd(d1, { years, months }, "constrain") to d2!
  cand = tm_cal_date_add(cal, y1, m1, d1, years ## int, months ## int, 0 ## int, 0 ## int, "constrain")
  ced = tm_epoch_days(cand[0], cand[1], cand[2])
  # Safety check in case leap-month constraining caused overshoot
  while (sign > 0 && ced > ed2) || (sign < 0 && ced < ed2)
    months -= sign
    cand = tm_cal_date_add(cal, y1, m1, d1, years ## int, months ## int, 0 ## int, 0 ## int, "constrain")
    ced = tm_epoch_days(cand[0], cand[1], cand[2])
  [years, months, 0, (ed2 - ced).to_i]
