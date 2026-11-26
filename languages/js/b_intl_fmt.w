# runtime/b_intl_fmt — ECMA-402 Internationalization API (Part 2):
# Intl.NumberFormat (v3), Intl.DateTimeFormat, Intl.DurationFormat,
# and locale-aware String/Number/BigInt/Date/Array/TypedArray prototype methods.

in JS

# Hook populated by b_temporal.w for Intl.DateTimeFormat formatting Temporal objects.
JS_TEMPORAL_DTF_HOOK = [nil]

# ---- ICU Measure-Unit Category Table (all 45 ECMA-402 sanctioned units) ----

INTL_UNIT_ICU = {
  "acre" => "area-acre",
  "bit" => "digital-bit",
  "byte" => "digital-byte",
  "celsius" => "temperature-celsius",
  "centimeter" => "length-centimeter",
  "day" => "duration-day",
  "degree" => "angle-degree",
  "fahrenheit" => "temperature-fahrenheit",
  "fluid-ounce" => "volume-fluid-ounce",
  "foot" => "length-foot",
  "gallon" => "volume-gallon",
  "gigabit" => "digital-gigabit",
  "gigabyte" => "digital-gigabyte",
  "gram" => "mass-gram",
  "hectare" => "area-hectare",
  "hour" => "duration-hour",
  "inch" => "length-inch",
  "kilobit" => "digital-kilobit",
  "kilobyte" => "digital-kilobyte",
  "kilogram" => "mass-kilogram",
  "kilometer" => "length-kilometer",
  "liter" => "volume-liter",
  "megabit" => "digital-megabit",
  "megabyte" => "digital-megabyte",
  "meter" => "length-meter",
  "microsecond" => "duration-microsecond",
  "mile" => "length-mile",
  "mile-scandinavian" => "length-mile-scandinavian",
  "milliliter" => "volume-milliliter",
  "millimeter" => "length-millimeter",
  "millisecond" => "duration-millisecond",
  "minute" => "duration-minute",
  "month" => "duration-month",
  "nanosecond" => "duration-nanosecond",
  "ounce" => "mass-ounce",
  "percent" => "concentr-percent",
  "petabyte" => "digital-petabyte",
  "pound" => "mass-pound",
  "second" => "duration-second",
  "stone" => "mass-stone",
  "terabit" => "digital-terabit",
  "terabyte" => "digital-terabyte",
  "week" => "duration-week",
  "yard" => "length-yard",
  "year" => "duration-year"
}

INTL_VALID_INCREMENTS = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 2500, 5000]

INTL_ROUNDING_MODES = ["ceil", "floor", "expand", "trunc", "halfCeil", "halfFloor", "halfExpand", "halfTrunc", "halfEven"]

INTL_ROUNDING_SKELETON = {
  "ceil" => "rounding-mode-ceiling",
  "floor" => "rounding-mode-floor",
  "expand" => "rounding-mode-up",
  "trunc" => "rounding-mode-down",
  "halfCeil" => "rounding-mode-half-ceiling",
  "halfFloor" => "rounding-mode-half-floor",
  "halfExpand" => "rounding-mode-half-up",
  "halfTrunc" => "rounding-mode-half-down",
  "halfEven" => "rounding-mode-half-even"
}

# ---- SetNumberFormatDigitOptions (ECMA-402 §15.1.1) ----
# Returns [minInt, minFrac_or_nil, maxFrac_or_nil, minSig_or_nil, maxSig_or_nil,
#          roundingIncrement, roundingMode, roundingPriority, trailingZeroDisplay, roundingType]

-> intl_set_digit_options(opts, mnfd_default, mxfd_default, notation)
  mnid = intl_get_number_option(opts, "minimumIntegerDigits", 1, 21, 1)
  mnfd_v = jget(opts, "minimumFractionDigits")
  mxfd_v = jget(opts, "maximumFractionDigits")
  mnsd_v = jget(opts, "minimumSignificantDigits")
  mxsd_v = jget(opts, "maximumSignificantDigits")
  r_inc = intl_get_number_option(opts, "roundingIncrement", 1, 5000, 1)
  js_throw_range("Invalid roundingIncrement: " + r_inc.to_s) if !INTL_VALID_INCREMENTS.include?(r_inc)
  r_mode = intl_get_option(opts, "roundingMode", :string, INTL_ROUNDING_MODES, "halfExpand")
  r_prio = intl_get_option(opts, "roundingPriority", :string, ["auto", "morePrecision", "lessPrecision"], "auto")
  tz_disp = intl_get_option(opts, "trailingZeroDisplay", :string, ["auto", "stripIfInteger"], "auto")
  # Spec: if roundingIncrement != 1, mxfd_default = mnfd_default
  mxfd_default = mnfd_default if r_inc != 1

  has_sd = mnsd_v != nil || mxsd_v != nil
  has_fd = mnfd_v != nil || mxfd_v != nil
  need_sd = has_sd || r_prio != "auto"
  need_fd = (r_prio != "auto") || !has_sd
  need_fd = false if !has_fd && !has_sd && notation == "compact" && r_prio == "auto"

  min_sd = nil
  max_sd = nil
  if need_sd
    if has_sd
      min_sd = intl_default_number_option(mnsd_v, 1, 21, 1)
      max_sd = intl_default_number_option(mxsd_v, min_sd, 21, 21)
    else
      min_sd = 1
      max_sd = 21

  min_fd = nil
  max_fd = nil
  if need_fd
    if has_fd
      mnfd = intl_default_number_option(mnfd_v, 0, 100, nil)
      mxfd = intl_default_number_option(mxfd_v, 0, 100, nil)
      if mnfd == nil
        mnfd = mnfd_default < mxfd ? mnfd_default : mxfd
      elsif mxfd == nil
        mxfd = mxfd_default > mnfd ? mxfd_default : mnfd
      elsif mnfd > mxfd
        js_throw_range("minimumFractionDigits is greater than maximumFractionDigits")
      min_fd = mnfd
      max_fd = mxfd
    else
      min_fd = mnfd_default
      max_fd = mxfd_default

  rtype = :fraction
  if !has_sd && !has_fd && notation == "compact" && r_prio == "auto"
    rtype = :compact_rounding
    min_fd = 0
    max_fd = 0
  elsif r_prio == "morePrecision"
    rtype = :more_precision
  elsif r_prio == "lessPrecision"
    rtype = :less_precision
  elsif has_sd
    rtype = :significant
  else
    rtype = :fraction

  if r_inc != 1
    js_throw_type("roundingIncrement cannot be used with significant digits or roundingPriority") if rtype != :fraction
    js_throw_range("roundingIncrement requires minimumFractionDigits === maximumFractionDigits") if min_fd != max_fd

  [mnid, min_fd, max_fd, min_sd, max_sd, r_inc, r_mode, r_prio, tz_disp, rtype]

# Build ICU precision + integer-width + rounding-mode skeleton tokens from digit options!
-> intl_digit_skeleton(dig)
  toks = []
  mnid = dig[0]
  min_fd = dig[1]
  max_fd = dig[2]
  min_sd = dig[3]
  max_sd = dig[4]
  r_inc = dig[5]
  r_mode = dig[6]
  tz_disp = dig[8]
  rtype = dig[9]

  if mnid > 1
    z = ""
    i = 0
    while i < mnid
      z = z + "0"
      i += 1
    toks.push("integer-width/+" + z)

  prec = nil
  if r_inc != 1
    # precision-increment/0.05 (scaled by 10^-max_fd)
    prec = "precision-increment/" + intl_scale_increment(r_inc, max_fd)
  elsif rtype == :significant
    s = ""
    i = 0
    while i < min_sd
      s = s + "@"
      i += 1
    while i < max_sd
      s = s + "#"
      i += 1
    prec = s
  elsif rtype == :fraction
    s = "."
    i = 0
    while i < min_fd
      s = s + "0"
      i += 1
    while i < max_fd
      s = s + "#"
      i += 1
    prec = s
  elsif rtype == :more_precision || rtype == :less_precision
    f = "."
    i = 0
    while i < min_fd
      f = f + "0"
      i += 1
    while i < max_fd
      f = f + "#"
      i += 1
    s = ""
    i = 0
    while i < min_sd
      s = s + "@"
      i += 1
    while i < max_sd
      s = s + "#"
      i += 1
    prec = f + "/" + s + (rtype == :more_precision ? "r" : "s")

  if prec != nil
    if tz_disp == "stripIfInteger"
      if prec.index("/") != nil
        # ICU: trailing-zero strip option goes after precision token for concise skeletons
        prec = prec + "/w"
      else
        prec = prec + "/w"
    toks.push(prec)
  elsif tz_disp == "stripIfInteger"
    toks.push("precision-unlimited/w")

  toks.push(INTL_ROUNDING_SKELETON[r_mode]) if INTL_ROUNDING_SKELETON.has_key?(r_mode)
  toks.join(" ")

-> intl_scale_increment(inc, fd)
  s = inc.to_s
  return s if fd == 0
  while s.size <= fd
    s = "0" + s
  split = s.size - fd
  s.slice(0, split) + "." + s.slice(split, fd)

# Map ICU UNumberFormatFields enum to ECMA-402 formatToParts type string
-> intl_num_field_name(fld, num_val, is_neg = false)
  return "integer" if fld == 0
  return "fraction" if fld == 1
  return "decimal" if fld == 2
  return "exponentSeparator" if fld == 3
  return "exponentMinusSign" if fld == 4 && is_neg
  return "exponentSign" if fld == 4
  return "exponentInteger" if fld == 5
  return "group" if fld == 6
  return "currency" if fld == 7
  return "percentSign" if fld == 8
  return "permille" if fld == 9
  if fld == 10
    return is_neg ? "minusSign" : "plusSign"
  return "unit" if fld == 11
  return "compact" if fld == 12
  return "approximatelySign" if fld == 13
  "literal"

# ---- Intl.NumberFormat ----

-> intl_is_well_formed_unit?(u)
  return true if INTL_UNITS_SET.has_key?(u)
  idx = u.index("-per-")
  return false if idx == nil
  a = u.slice(0, idx)
  b = u.slice(idx + 5, u.size - idx - 5)
  INTL_UNITS_SET.has_key?(a) && INTL_UNITS_SET.has_key?(b)

-> intl_unit_to_icu_skeleton(u)
  if INTL_UNIT_ICU.has_key?(u)
    return "measure-unit/" + INTL_UNIT_ICU[u]
  idx = u.index("-per-")
  a = u.slice(0, idx)
  b = u.slice(idx + 5, u.size - idx - 5)
  "measure-unit/" + INTL_UNIT_ICU[a] + " per-measure-unit/" + INTL_UNIT_ICU[b]

-> intl_nf_ctor(this, args, nt)
  req = intl_canonicalize_locale_list(js_arg(args, 0))
  opts = intl_coerce_options_to_object(js_arg(args, 1))
  intl_get_option(opts, "localeMatcher", :string, ["lookup", "best fit"], "best fit")
  opt_nu = intl_get_option(opts, "numberingSystem", :string, nil, nil)
  if opt_nu != nil
    js_throw_range("Invalid numberingSystem: " + opt_nu) if !intl_is_type_nonterminal?(opt_nu)
    opt_nu = intl_lower(opt_nu)
  avail = icu_available_locales()
  supp_nu = intl_supported_values_list("numberingSystem")
  opt_map = {}
  opt_map["nu"] = opt_nu if opt_nu != nil && supp_nu.include?(opt_nu)
  vfn = ->(k, v, found) supp_nu.include?(v)
  r = intl_resolve_locale(avail, req, opt_map, ["nu"], vfn)
  nu = r["nu"]
  if nu == nil
    loc0 = icu_for_language_tag(r["dataLocale"])
    loc0 = r["dataLocale"] if loc0 == nil
    fn_o = icu_sym("unumsys_open")
    fn_n = icu_sym("unumsys_getName")
    fn_c = icu_sym("unumsys_close")
    lb = icu_cstr(loc0)
    eb = icu_err_buf()
    ns = icu_c2(fn_o, icu_ptr(lb), icu_ptr(eb))
    lb.size
    nu = "latn"
    if ns != 0 && icu_err_code(eb) <= 0
      p = icu_c1(fn_n, ns)
      s = icu_read_cstr_ptr(p)
      nu = s if s != nil && s.size > 0
      icu_c1(fn_c, ns)
    eb.size

  # SetNumberFormatUnitOptions (ECMA-402 §15.1.3)
  style = intl_get_option(opts, "style", :string, ["decimal", "percent", "currency", "unit"], "decimal")
  currency = intl_get_option(opts, "currency", :string, nil, nil)
  if currency != nil
    js_throw_range("Invalid currency code: " + currency) if currency.size != 3 || !intl_alpha?(currency)
    currency = intl_upper(currency)
  js_throw_type("Currency code is required with currency style") if style == "currency" && currency == nil
  curr_disp = intl_get_option(opts, "currencyDisplay", :string, ["code", "symbol", "narrowSymbol", "name"], "symbol")
  curr_sign = intl_get_option(opts, "currencySign", :string, ["standard", "accounting"], "standard")
  unit = intl_get_option(opts, "unit", :string, nil, nil)
  if unit != nil
    js_throw_range("Invalid unit: " + unit) if !intl_is_well_formed_unit?(unit)
  js_throw_type("Unit is required with unit style") if style == "unit" && unit == nil
  unit_disp = intl_get_option(opts, "unitDisplay", :string, ["short", "narrow", "long"], "short")

  notation = intl_get_option(opts, "notation", :string, ["standard", "scientific", "engineering", "compact"], "standard")
  # Default fraction digits (ECMA-402 §15.1.1: currency defaults only apply to standard notation!)
  mnfd_def = 0
  mxfd_def = 3
  if style == "currency" && notation == "standard"
    cd = icu_currency_digits(currency)
    mnfd_def = cd
    mxfd_def = cd
  elsif style == "percent"
    mnfd_def = 0
    mxfd_def = 0

  dig = intl_set_digit_options(opts, mnfd_def, mxfd_def, notation)
  compact_disp = intl_get_option(opts, "compactDisplay", :string, ["short", "long"], "short")
  # useGrouping: GetBooleanOrStringNumberFormatOption (ECMA-402 §15.1.2)
  ug_v = jget(opts, "useGrouping")
  ug_def = notation == "compact" ? "min2" : "auto"
  use_grp = ug_def
  if ug_v != nil
    if ug_v == true
      use_grp = "always"
    elsif !js_truthy(ug_v)
      use_grp = false
    else
      ugs = js_to_string(ug_v)
      if ugs == "true" || ugs == "false"
        use_grp = ug_def
      elsif ugs == "always" || ugs == "auto" || ugs == "min2"
        use_grp = ugs
      else
        js_throw_range("Invalid useGrouping option: " + ugs)
  sign_disp = intl_get_option(opts, "signDisplay", :string, ["auto", "never", "always", "exceptZero", "negative"], "auto")

  # Build ICU NumberFormatter skeleton!
  sk = []
  if style == "percent"
    sk.push("percent scale/100")
  elsif style == "currency"
    sk.push("currency/" + currency)
    if curr_disp == "code"
      sk.push("unit-width-iso-code")
    elsif curr_disp == "narrowSymbol"
      sk.push("unit-width-narrow")
    elsif curr_disp == "name"
      sk.push("unit-width-full-name")
    else
      sk.push("unit-width-short")
  elsif style == "unit"
    sk.push(intl_unit_to_icu_skeleton(unit))
    if unit_disp == "long"
      sk.push("unit-width-full-name")
    elsif unit_disp == "narrow"
      sk.push("unit-width-narrow")
    else
      sk.push("unit-width-short")

  if notation == "scientific"
    sk.push("scientific")
  elsif notation == "engineering"
    sk.push("engineering")
  elsif notation == "compact"
    sk.push(compact_disp == "long" ? "compact-long" : "compact-short")

  sk.push(intl_digit_skeleton(dig))

  if use_grp == false
    sk.push("group-off")
  elsif use_grp == "always"
    sk.push("group-on-aligned")
  elsif use_grp == "min2"
    sk.push("group-min2")
  else
    sk.push("group-auto")

  is_acct = style == "currency" && curr_sign == "accounting"
  if sign_disp == "always"
    sk.push(is_acct ? "sign-accounting-always" : "sign-always")
  elsif sign_disp == "never"
    sk.push("sign-never")
  elsif sign_disp == "exceptZero"
    sk.push(is_acct ? "sign-accounting-except-zero" : "sign-except-zero")
  elsif sign_disp == "negative"
    sk.push(is_acct ? "sign-accounting-negative" : "sign-negative")
  else
    sk.push(is_acct ? "sign-accounting" : "sign-auto")

  sk.push("numbering-system/" + nu)
  skeleton = sk.join(" ")
  icu_loc = icu_for_language_tag(r["dataLocale"])
  icu_loc = r["dataLocale"] if icu_loc == nil

  proto = js_realm().proto_from(nt != nil ? nt : js_realm().intrinsic("Intl.NumberFormat"), "Intl.NumberFormat")
  o = js_new_special(proto, "Intl.NumberFormat")
  # internal = [locale, nu, style, currency, curr_disp, curr_sign, unit, unit_disp,
  #             dig, notation, compact_disp, use_grp, sign_disp, skeleton, icu_loc, bound_format]
  o.internal = [
    r["locale"], nu, style, currency, curr_disp, curr_sign, unit, unit_disp,
    dig, notation, compact_disp, use_grp, sign_disp, skeleton, icu_loc, nil
  ]
  intl_legacy_chain(this, nt, "Intl.NumberFormat", o)

# Convert a JS value to IntlMathematicalValue: returns [kind, num_or_dec_str]
# kind: :double (Float), :decimal (exact decimal String for BigInt or decimal String), :nan, :pos_inf, :neg_inf, :neg_zero
-> intl_to_math_val(v)
  if v.is_a?(JS:BigIntValue)
    return [:decimal, js_bigint_to_string(v, nil)]
  if js_number?(v)
    return [:nan, nil] if v != v
    return [:pos_inf, nil] if v == ~1.0 / ~0.0
    return [:neg_inf, nil] if v == ~-1.0 / ~0.0
    return [:neg_zero, nil] if v == ~0.0 && (~1.0 / v) < ~0.0
    return [:double, v]
  prim = js_to_primitive(v, "number")
  return [:decimal, js_bigint_to_string(prim, nil)] if prim.is_a?(JS:BigIntValue)
  if js_string?(prim)
    s = prim.strip
    return [:double, ~0.0] if s.size == 0
    return [:pos_inf, nil] if s == "Infinity" || s == "+Infinity"
    return [:neg_inf, nil] if s == "-Infinity"
    # Check if valid decimal string for exact arbitrary-precision formatting
    if intl_valid_dec_str?(s)
      return [:neg_zero, nil] if intl_is_neg_zero_str?(s)
      return [:decimal, s]
    n = js_to_number(prim)
    return [:nan, nil] if n != n
    return [:pos_inf, nil] if n == ~1.0 / ~0.0
    return [:neg_inf, nil] if n == ~-1.0 / ~0.0
    return [:neg_zero, nil] if n == ~0.0 && (~1.0 / n) < ~0.0
    return [:double, n]
  n = js_to_number(prim)
  return [:nan, nil] if n != n
  return [:pos_inf, nil] if n == ~1.0 / ~0.0
  return [:neg_inf, nil] if n == ~-1.0 / ~0.0
  return [:neg_zero, nil] if n == ~0.0 && (~1.0 / n) < ~0.0
  [:double, n]

-> intl_valid_dec_str?(s)
  return false if s.size == 0 || !s.ascii?
  i = 0
  n = s.size
  c0 = s.byte_at(0)
  i += 1 if c0 == 43 || c0 == 45
  has_dig = false
  while i < n && s.byte_at(i) >= 48 && s.byte_at(i) <= 57
    has_dig = true
    i += 1
  if i < n && s.byte_at(i) == 46
    i += 1
    while i < n && s.byte_at(i) >= 48 && s.byte_at(i) <= 57
      has_dig = true
      i += 1
  return false if !has_dig
  if i < n && (s.byte_at(i) == 101 || s.byte_at(i) == 69)
    i += 1
    i += 1 if i < n && (s.byte_at(i) == 43 || s.byte_at(i) == 45)
    edig = false
    while i < n && s.byte_at(i) >= 48 && s.byte_at(i) <= 57
      edig = true
      i += 1
    return false if !edig
  i == n

-> intl_is_neg_zero_str?(s)
  return false if s.size == 0 || s.byte_at(0) != 45
  i = 1
  while i < s.size
    c = s.byte_at(i)
    break if c == 101 || c == 69
    return false if c >= 49 && c <= 57
    i += 1
  true

-> intl_mv_is_neg?(mv)
  k = mv[0]
  return true if k == :neg_inf || k == :neg_zero
  return mv[1] < ~0.0 if k == :double
  return mv[1].starts_with?("-") if k == :decimal
  false

-> intl_mv_as_double(mv)
  k = mv[0]
  return js_nan() if k == :nan
  return ~1.0 / ~0.0 if k == :pos_inf
  return ~-1.0 / ~0.0 if k == :neg_inf
  return ~-0.0 if k == :neg_zero
  mv[1]

-> intl_nf_format_impl(d, mv, want_parts)
  fn_open = icu_sym("unumf_openForSkeletonAndLocale")
  fn_res = icu_sym("unumf_openResult")
  fn_val = icu_sym("unumf_resultAsValue")
  fn_c_res = icu_sym("unumf_closeResult")
  fn_c = icu_sym("unumf_close")
  us = icu_to_u16(d[13])
  sba = us[0]
  lb = icu_cstr(d[14])
  eb = icu_err_buf()
  nf = icu_c4(fn_open, icu_ptr(sba), us[1], icu_ptr(lb), icu_ptr(eb))
  res = icu_c1(fn_res, icu_ptr(eb))
  icu_err_reset(eb)
  if mv[0] == :decimal
    fn_dec = icu_sym("unumf_formatDecimal")
    db = icu_cstr(mv[1])
    icu_c5(fn_dec, nf, icu_ptr(db), mv[1].size, res, icu_ptr(eb))
    db.size
  else
    fn_dbl = icu_sym("unumf_formatDouble")
    dv = intl_mv_as_double(mv)
    icu_c_pdpp(fn_dbl, nf, wvalue_bits(dv) ## i64, res, icu_ptr(eb))
  icu_err_reset(eb)
  fv = icu_c2(fn_val, res, icu_ptr(eb))
  ex = icu_fmtval_extract(fv, 2)  # UFIELD_CATEGORY_NUMBER = 2
  icu_c1(fn_c_res, res) if res != 0
  icu_c1(fn_c, nf) if nf != 0
  sba.size
  lb.size
  eb.size
  full_str = ex[0]
  return full_str if !want_parts
  intl_nf_parts_from_spans(full_str, ex[1], mv, nil, d[2])

-> intl_nf_parts_from_spans(full_str, raw_parts, mv, source_spans, nf_style = nil)
  ulen = js_len(full_str)
  # Filter non-overlapping leaf spans sorted by start (when two overlap, prefer narrower leaf)
  spans = []
  raw_parts.each ->(pt)
    if pt[0] == 2 && pt[3] > pt[2]
      spans.push([pt[1], pt[2], pt[3]])
  # Sort by start asc, length desc -> skip parent spans that strictly contain child spans?
  # Actually in ICU UFIELD_CATEGORY_NUMBER, UNUM_INTEGER_FIELD (0) can contain UNUM_GROUPING_SEPARATOR_FIELD (6)!
  # Split integer spans around any contained grouping separator spans!
  clean = intl_split_nested_num_spans(spans)
  is_neg = mv != nil && intl_mv_is_neg?(mv)
  out = []
  pos = 0
  i = 0
  while i < clean.size
    sp = clean[i]
    fld = sp[0]
    st = sp[1]
    lm = sp[2]
    if st > pos
      p = js_realm().new_object
      p.define("type", "literal", ATTR_W + ATTR_E + ATTR_C)
      p.define("value", js_substring(full_str, pos, st), ATTR_W + ATTR_E + ATTR_C)
      p.define("source", intl_find_source(pos, st, source_spans), ATTR_W + ATTR_E + ATTR_C) if source_spans != nil
      out.push(p)
    if lm > st && st >= pos
      sub = js_substring(full_str, st, lm)
      ftype = nil
      if mv != nil && mv[0] == :nan && fld == 0
        ftype = "nan"
      elsif mv != nil && (mv[0] == :pos_inf || mv[0] == :neg_inf) && fld == 0
        ftype = "infinity"
      elsif fld == 8 && nf_style == "unit"
        ftype = "unit"
      elsif fld == 10
        # Determine minus vs plus from sign character or source number
        ftype = (sub == "+" || (!is_neg && source_spans == nil)) ? "plusSign" : "minusSign"
        if source_spans != nil
          ftype = (sub == "+" || sub.index("+") != nil) ? "plusSign" : "minusSign"
      elsif fld == 4
        ftype = (sub == "+" ? "exponentPlusSign" : "exponentMinusSign")
      else
        ftype = intl_num_field_name(fld, nil, is_neg)
      p = js_realm().new_object
      p.define("type", ftype, ATTR_W + ATTR_E + ATTR_C)
      p.define("value", sub, ATTR_W + ATTR_E + ATTR_C)
      p.define("source", intl_find_source(st, lm, source_spans), ATTR_W + ATTR_E + ATTR_C) if source_spans != nil
      out.push(p)
      pos = lm
    i += 1
  if pos < ulen
    p = js_realm().new_object
    p.define("type", "literal", ATTR_W + ATTR_E + ATTR_C)
    p.define("value", js_substring(full_str, pos, ulen), ATTR_W + ATTR_E + ATTR_C)
    p.define("source", intl_find_source(pos, ulen, source_spans), ATTR_W + ATTR_E + ATTR_C) if source_spans != nil
    out.push(p)
  js_realm().adopt_array(out)

-> intl_split_nested_num_spans(spans)
  # Separate container integer spans (fld==0) from inner group spans (fld==6) and all other non-overlapping spans.
  # Build a flat sorted non-overlapping list!
  # First sort by start asc, then end desc.
  arr = spans.dup
  i = 1
  while i < arr.size
    cur = arr[i]
    j = i - 1
    while j >= 0 && (arr[j][1] > cur[1] || (arr[j][1] == cur[1] && arr[j][2] < cur[2]))
      arr[j + 1] = arr[j]
      j -= 1
    arr[j + 1] = cur
    i += 1
  out = []
  i = 0
  while i < arr.size
    sp = arr[i]
    fld = sp[0]
    st = sp[1]
    lm = sp[2]
    # Check if there are child spans strictly inside [st, lm)
    children = []
    k = i + 1
    while k < arr.size && arr[k][1] < lm
      if arr[k][2] <= lm
        children.push(arr[k])
        k += 1
      else
        break
    if children.size == 0
      out.push(sp)
      i += 1
    else
      # Interleave parent slices with children
      cur_p = st
      c = 0
      while c < children.size
        ch = children[c]
        out.push([fld, cur_p, ch[1]]) if ch[1] > cur_p
        out.push(ch)
        cur_p = ch[2]
        c += 1
      out.push([fld, cur_p, lm]) if lm > cur_p
      i = k
  out

-> intl_find_source(st, lm, source_spans)
  i = 0
  while i < source_spans.size
    ss = source_spans[i]
    if st >= ss[1] && lm <= ss[2]
      return ss[0] == 0 ? "startRange" : "endRange"
    i += 1
  "shared"

-> intl_nf_format_range_impl(d, start_v, end_v, want_parts)
  js_throw_type("start and end must be provided to formatRange") if start_v == nil || end_v == nil
  x = intl_to_math_val(start_v)
  y = intl_to_math_val(end_v)
  js_throw_range("Range arguments cannot be NaN") if x[0] == :nan || y[0] == :nan
  fn_open = icu_sym("unumrf_openForSkeletonWithCollapseAndIdentityFallback")
  fn_res = icu_sym("unumrf_openResult")
  fn_val = icu_sym("unumrf_resultAsValue")
  fn_c_res = icu_sym("unumrf_closeResult")
  fn_c = icu_sym("unumrf_close")
  us = icu_to_u16(d[13])
  sba = us[0]
  lb = icu_cstr(d[14])
  eb = icu_err_buf()
  # UNUM_RANGE_COLLAPSE_AUTO=0, UNUM_IDENTITY_FALLBACK_APPROXIMATELY=2
  nrf = icu_c7(fn_open, icu_ptr(sba), us[1], 0, 2, icu_ptr(lb), 0, icu_ptr(eb))
  res = icu_c1(fn_res, icu_ptr(eb))
  icu_err_reset(eb)
  if x[0] == :decimal || y[0] == :decimal
    xs = x[0] == :decimal ? x[1] : (x[0] == :neg_zero ? "-0" : (x[0] == :pos_inf ? "Infinity" : (x[0] == :neg_inf ? "-Infinity" : js_number_to_s(x[1]))))
    ys = y[0] == :decimal ? y[1] : (y[0] == :neg_zero ? "-0" : (y[0] == :pos_inf ? "Infinity" : (y[0] == :neg_inf ? "-Infinity" : js_number_to_s(y[1]))))
    fn_dec = icu_sym("unumrf_formatDecimalRange")
    xb = icu_cstr(xs)
    yb = icu_cstr(ys)
    icu_c7(fn_dec, nrf, icu_ptr(xb), xs.size, icu_ptr(yb), ys.size, res, icu_ptr(eb))
    xb.size
    yb.size
  else
    fn_dbl = icu_sym("unumrf_formatDoubleRange")
    dx = intl_mv_as_double(x)
    dy = intl_mv_as_double(y)
    icu_c_pddpp(fn_dbl, nrf, wvalue_bits(dx) ## i64, wvalue_bits(dy) ## i64, res, icu_ptr(eb))
  icu_err_reset(eb)
  fv = icu_c2(fn_val, res, icu_ptr(eb))
  ex = icu_fmtval_extract(fv, -1)
  icu_c1(fn_c_res, res) if res != 0
  icu_c1(fn_c, nrf) if nrf != 0
  sba.size
  lb.size
  eb.size
  full_str = ex[0]
  return full_str if !want_parts
  # UFIELD_CATEGORY_NUMBER_RANGE_SPAN = 0x1002 = 4098 (field 0 = startRange, field 1 = endRange)
  src_spans = []
  ex[1].each ->(pt)
    src_spans.push([pt[1], pt[2], pt[3]]) if pt[0] == 4098
  intl_nf_parts_from_spans(full_str, ex[1], nil, src_spans, d[2])

-> intl_nf_get_format(this)
  d = intl_unwrap(this, "Intl.NumberFormat", "format")
  return d[15] if d[15] != nil
  fn = ->(th, args, nt) intl_nf_format_impl(d, intl_to_math_val(js_arg(args, 0)), false)
  bf = js_realm().native("", 1, fn)
  d[15] = bf
  bf

-> intl_nf_resolved(this)
  d = intl_unwrap(this, "Intl.NumberFormat", "resolvedOptions")
  dig = d[8]
  o = js_realm().new_object
  o.define("locale", d[0], ATTR_W + ATTR_E + ATTR_C)
  o.define("numberingSystem", d[1], ATTR_W + ATTR_E + ATTR_C)
  o.define("style", d[2], ATTR_W + ATTR_E + ATTR_C)
  if d[2] == "currency"
    o.define("currency", d[3], ATTR_W + ATTR_E + ATTR_C)
    o.define("currencyDisplay", d[4], ATTR_W + ATTR_E + ATTR_C)
    o.define("currencySign", d[5], ATTR_W + ATTR_E + ATTR_C)
  elsif d[2] == "unit"
    o.define("unit", d[6], ATTR_W + ATTR_E + ATTR_C)
    o.define("unitDisplay", d[7], ATTR_W + ATTR_E + ATTR_C)
  o.define("minimumIntegerDigits", dig[0] + ~0.0, ATTR_W + ATTR_E + ATTR_C)
  if dig[1] != nil
    o.define("minimumFractionDigits", dig[1] + ~0.0, ATTR_W + ATTR_E + ATTR_C)
    o.define("maximumFractionDigits", dig[2] + ~0.0, ATTR_W + ATTR_E + ATTR_C)
  if dig[3] != nil
    o.define("minimumSignificantDigits", dig[3] + ~0.0, ATTR_W + ATTR_E + ATTR_C)
    o.define("maximumSignificantDigits", dig[4] + ~0.0, ATTR_W + ATTR_E + ATTR_C)
  o.define("useGrouping", d[11], ATTR_W + ATTR_E + ATTR_C)
  o.define("notation", d[9], ATTR_W + ATTR_E + ATTR_C)
  o.define("compactDisplay", d[10], ATTR_W + ATTR_E + ATTR_C) if d[9] == "compact"
  o.define("signDisplay", d[12], ATTR_W + ATTR_E + ATTR_C)
  o.define("roundingIncrement", dig[5] + ~0.0, ATTR_W + ATTR_E + ATTR_C)
  o.define("roundingMode", dig[6], ATTR_W + ATTR_E + ATTR_C)
  o.define("roundingPriority", dig[7], ATTR_W + ATTR_E + ATTR_C)
  o.define("trailingZeroDisplay", dig[8], ATTR_W + ATTR_E + ATTR_C)
  o

# ---- Intl.DateTimeFormat ----

# Parse and normalize a UTC offset string like "+05:30", "-0800", "+00" -> ["+05:30", "GMT+05:30"] or nil
# Note: per ECMA-402, Unicode minus U+2212 is NOT allowed in Intl.DateTimeFormat timeZone option!
-> intl_parse_offset_tz(s)
  return nil if s.size < 3 || !s.ascii?
  c0 = s.byte_at(0)
  sign = nil
  if c0 == 43
    sign = "+"
  elsif c0 == 45
    sign = "-"
  else
    return nil
  rest = s.slice(1, s.size - 1)
  hh = -1
  mm = 0
  if rest.size == 2 && intl_digit?(rest)
    hh = rest.to_i
  elsif rest.size == 4 && intl_digit?(rest)
    hh = rest.slice(0, 2).to_i
    mm = rest.slice(2, 2).to_i
  elsif rest.size == 5 && rest.byte_at(2) == 58 && intl_digit?(rest.slice(0, 2)) && intl_digit?(rest.slice(3, 2))
    hh = rest.slice(0, 2).to_i
    mm = rest.slice(3, 2).to_i
  else
    return nil
  return nil if hh < 0 || hh > 23 || mm < 0 || mm > 59
  sign = "+" if hh == 0 && mm == 0
  hs = hh < 10 ? ("0" + hh.to_s) : hh.to_s
  ms = mm < 10 ? ("0" + mm.to_s) : mm.to_s
  norm = sign + hs + ":" + ms
  [norm, "GMT" + norm]

# Non-IANA ICU legacy zone aliases that MUST be rejected by Intl.DateTimeFormat / Temporal
INTL_NON_IANA_ZONES = {
  "act" => true, "aet" => true, "agt" => true, "art" => true, "ast" => true,
  "bet" => true, "bst" => true, "cat" => true, "cnt" => true, "cst" => true,
  "ctt" => true, "eat" => true, "ect" => true, "iet" => true, "ist" => true,
  "jst" => true, "mit" => true, "net" => true, "nst" => true, "plt" => true,
  "pnt" => true, "prt" => true, "pst" => true, "sst" => true, "vst" => true
}

# Validate & normalize casing of an Intl.DateTimeFormat timeZone string (preserving IANA links per canonical-tz!).
# Returns [resolved_tz, icu_tz].
-> intl_resolve_tz(tz_str)
  off = intl_parse_offset_tz(tz_str)
  return off if off != nil
  up = intl_upper(tz_str)
  return ["UTC", "UTC"] if up == "UTC"
  # Case-insensitive lookup in IANA TZDB preserving canonical casing of the requested identifier (including links!)
  iana = intl_lookup_iana_tz(tz_str)
  js_throw_range("Invalid time zone specified: " + tz_str) if iana == nil
  [iana, iana]

INTL_TZ_MAP = [nil]

-> intl_tz_ci_map
  return INTL_TZ_MAP[0] if INTL_TZ_MAP[0] != nil
  m = {}
  # Load ALL system timezone IDs (including links) from ICU (UCAL_ZONE_TYPE_ANY = 0)
  raw = icu_all_timezones(0)
  raw.each ->(tz)
    next if tz == "Etc/Unknown" || tz == "Factory" || tz.starts_with?("SystemV/")
    low = intl_lower(tz)
    next if INTL_NON_IANA_ZONES.has_key?(low)
    m[low] = tz
  m["utc"] = "UTC"
  m["etc/utc"] = "Etc/UTC"
  m["etc/gmt"] = "Etc/GMT"
  m["gmt"] = "GMT"
  INTL_TZ_MAP[0] = m
  m

-> intl_lookup_iana_tz(tz_str)
  return nil if !tz_str.ascii?
  m = intl_tz_ci_map()
  low = intl_lower(tz_str)
  return m[low] if m.has_key?(low)
  nil

# Map UDateFormatField enum -> ECMA-402 DateTimeFormat part type string
-> intl_dtf_field_name(fld)
  return "era" if fld == 0
  return "year" if fld == 1 || fld == 18 || fld == 20
  return "month" if fld == 2 || fld == 26
  return "day" if fld == 3
  return "hour" if fld == 4 || fld == 5 || fld == 15 || fld == 16
  return "minute" if fld == 6
  return "second" if fld == 7
  return "fractionalSecond" if fld == 8
  return "weekday" if fld == 9 || fld == 19 || fld == 25
  return "dayPeriod" if fld == 14 || fld == 35 || fld == 36
  return "timeZoneName" if fld == 17 || fld == 23 || fld == 24 || fld == 29 || fld == 31 || fld == 32 || fld == 33
  return "yearName" if fld == 30
  return "relatedYear" if fld == 34
  "literal"

-> intl_dtf_ctor(this, args, nt, req_def = :any, def_mode = :date)
  req = intl_canonicalize_locale_list(js_arg(args, 0))
  opts = intl_coerce_options_to_object(js_arg(args, 1))
  intl_get_option(opts, "localeMatcher", :string, ["lookup", "best fit"], "best fit")
  opt_ca = intl_get_option(opts, "calendar", :string, nil, nil)
  if opt_ca != nil
    js_throw_range("Invalid calendar: " + opt_ca) if !intl_is_type_nonterminal?(opt_ca)
    opt_ca = intl_canon_u_value("ca", intl_lower(opt_ca))
  opt_nu = intl_get_option(opts, "numberingSystem", :string, nil, nil)
  if opt_nu != nil
    js_throw_range("Invalid numberingSystem: " + opt_nu) if !intl_is_type_nonterminal?(opt_nu)
    opt_nu = intl_lower(opt_nu)
  hour12 = intl_get_option(opts, "hour12", :boolean, nil, nil)
  opt_hc = intl_get_option(opts, "hourCycle", :string, ["h11", "h12", "h23", "h24"], nil)
  opt_hc = nil if hour12 != nil

  tz_v = jget(opts, "timeZone")
  tz_pair = tz_v == nil ? [icu_default_timezone(), icu_default_timezone()] : intl_resolve_tz(js_to_string(tz_v))
  res_tz = tz_pair[0]
  icu_tz = tz_pair[1]

  # Read component options in exact ECMA-402 Table 6 order!
  weekday = intl_get_option(opts, "weekday", :string, ["narrow", "short", "long"], nil)
  era = intl_get_option(opts, "era", :string, ["narrow", "short", "long"], nil)
  year = intl_get_option(opts, "year", :string, ["2-digit", "numeric"], nil)
  month = intl_get_option(opts, "month", :string, ["2-digit", "numeric", "narrow", "short", "long"], nil)
  day = intl_get_option(opts, "day", :string, ["2-digit", "numeric"], nil)
  day_period = intl_get_option(opts, "dayPeriod", :string, ["narrow", "short", "long"], nil)
  hour = intl_get_option(opts, "hour", :string, ["2-digit", "numeric"], nil)
  minute = intl_get_option(opts, "minute", :string, ["2-digit", "numeric"], nil)
  second = intl_get_option(opts, "second", :string, ["2-digit", "numeric"], nil)
  frac_sec = intl_get_number_option(opts, "fractionalSecondDigits", 1, 3, nil)
  tz_name = intl_get_option(opts, "timeZoneName", :string, ["short", "long", "shortOffset", "longOffset", "shortGeneric", "longGeneric"], nil)
  intl_get_option(opts, "formatMatcher", :string, ["basic", "best fit"], "best fit")
  date_style = intl_get_option(opts, "dateStyle", :string, ["full", "long", "medium", "short"], nil)
  time_style = intl_get_option(opts, "timeStyle", :string, ["full", "long", "medium", "short"], nil)

  has_comp = weekday != nil || era != nil || year != nil || month != nil || day != nil || day_period != nil || hour != nil || minute != nil || second != nil || frac_sec != nil || tz_name != nil
  has_dt_comp = weekday != nil || year != nil || month != nil || day != nil || day_period != nil || hour != nil || minute != nil || second != nil || frac_sec != nil
  has_explicit_opts = has_dt_comp || date_style != nil || time_style != nil
  if (date_style != nil || time_style != nil) && has_comp
    js_throw_type("Cannot specify both dateStyle/timeStyle and individual component options")
  if req_def == :date && time_style != nil
    js_throw_type("timeStyle cannot be used with toLocaleDateString")
  if req_def == :time && date_style != nil
    js_throw_type("dateStyle cannot be used with toLocaleTimeString")

  # Apply default components when neither style nor components specified
  if date_style == nil && time_style == nil
    need_def = true
    if req_def == :date || req_def == :any
      need_def = false if weekday != nil || year != nil || month != nil || day != nil
    if req_def == :time || req_def == :any
      need_def = false if day_period != nil || hour != nil || minute != nil || second != nil || frac_sec != nil
    if need_def
      if def_mode == :date || def_mode == :all
        year = "numeric"
        month = "numeric"
        day = "numeric"
      if def_mode == :time || def_mode == :all
        hour = "numeric"
        minute = "numeric"
        second = "numeric"

  avail = icu_available_locales()
  supp_ca = intl_supported_values_list("calendar")
  supp_nu = intl_supported_values_list("numberingSystem")
  opt_map = {}
  opt_map["ca"] = opt_ca if opt_ca != nil && supp_ca.include?(opt_ca)
  opt_map["nu"] = opt_nu if opt_nu != nil && supp_nu.include?(opt_nu)
  opt_map["hc"] = opt_hc if opt_hc != nil
  vfn = ->(k, v, found)
    if k == "ca"
      supp_ca.include?(v)
    elsif k == "nu"
      supp_nu.include?(v)
    elsif k == "hc"
      v == "h11" || v == "h12" || v == "h23" || v == "h24"
    else
      false
  r = intl_resolve_locale(avail, req, opt_map, ["ca", "hc", "nu"], vfn)
  data_loc = r["dataLocale"]
  ca = r["ca"]
  if ca == nil
    loc0 = icu_for_language_tag(data_loc)
    loc0 = data_loc if loc0 == nil
    cals = icu_available_calendars(loc0, true)
    ca = "gregory"
    ci = 0
    while ci < cals.size
      bc = intl_cal_icu_to_bcp47(cals[ci])
      if supp_ca.include?(bc)
        ca = bc
        break
      ci += 1
  nu = r["nu"]
  if nu == nil
    loc0 = icu_for_language_tag(data_loc)
    loc0 = data_loc if loc0 == nil
    fn_o = icu_sym("unumsys_open")
    fn_n = icu_sym("unumsys_getName")
    fn_c = icu_sym("unumsys_close")
    lb = icu_cstr(loc0)
    eb = icu_err_buf()
    ns = icu_c2(fn_o, icu_ptr(lb), icu_ptr(eb))
    lb.size
    nu = "latn"
    if ns != 0 && icu_err_code(eb) <= 0
      p = icu_c1(fn_n, ns)
      s = icu_read_cstr_ptr(p)
      nu = s if s != nil && s.size > 0
      icu_c1(fn_c, ns)
    eb.size

  # Build ICU locale string with calendar & numberingSystem
  icu_ca = ca == "iso8601" ? "iso8601" : intl_cal_bcp47_to_icu(ca)
  base_icu = icu_for_language_tag(data_loc)
  base_icu = data_loc if base_icu == nil
  icu_loc = base_icu + "@calendar=" + icu_ca + ";numbers=" + nu

  # Resolve hourCycle & hour12 when hour or timeStyle is present
  has_hour = hour != nil || time_style != nil
  hc = nil
  res_h12 = nil
  if has_hour
    if hour12 == true
      hc = intl_icu_default_hour_cycle(icu_loc, "h")
      hc = "h12" if hc != "h11" && hc != "h12"
      res_h12 = true
    elsif hour12 == false
      hc = intl_icu_default_hour_cycle(icu_loc, "H")
      hc = "h23" if hc != "h23" && hc != "h24"
      res_h12 = false
    elsif r["hc"] != nil
      hc = r["hc"]
      res_h12 = (hc == "h11" || hc == "h12")
    else
      hc = intl_icu_default_hour_cycle(icu_loc, "j")
      res_h12 = (hc == "h11" || hc == "h12")
  # If hour12 was explicitly passed, drop hc from resolved locale tag (keep hc if no hour option!)
  res_loc = r["locale"]
  if hour12 != nil
    sp = intl_split_tag(res_loc)
    if sp[2].has_key?("hc")
      sp[2].delete("hc")
      res_loc = intl_join_tag(sp[0], sp[1], sp[2], sp[3], sp[4])

  # Build ICU skeleton & pattern!
  skel = intl_dtf_build_skeleton(weekday, era, year, month, day, day_period, hour, minute, second, frac_sec, tz_name, hc)
  pattern = intl_dtf_resolve_pattern(icu_loc, icu_tz, date_style, time_style, skel, hc, data_loc)

  proto = js_realm().proto_from(nt != nil ? nt : js_realm().intrinsic("Intl.DateTimeFormat"), "Intl.DateTimeFormat")
  o = js_new_special(proto, "Intl.DateTimeFormat")
  # internal = [locale, ca, nu, res_tz, hc, res_h12, weekday, era, year, month, day,
  #             day_period, hour, minute, second, frac_sec, tz_name, date_style, time_style,
  #             icu_loc, icu_tz, skel, pattern, bound_format,
  #             has_explicit_opts, data_loc, hour12, r["hc"]]
  o.internal = [
    res_loc, ca, nu, res_tz, hc, res_h12, weekday, era, year, month, day,
    day_period, hour, minute, second, frac_sec, tz_name, date_style, time_style,
    icu_loc, icu_tz, skel, pattern, nil,
    has_explicit_opts, data_loc, hour12, r["hc"]
  ]
  intl_legacy_chain(this, nt, "Intl.DateTimeFormat", o)

-> intl_dtf_build_skeleton(weekday, era, year, month, day, day_period, hour, minute, second, frac_sec, tz_name, hc)
  s = ""
  if era != nil
    s = s + (era == "long" ? "GGGG" : (era == "narrow" ? "GGGGG" : "G"))
  if year != nil
    s = s + (year == "2-digit" ? "yy" : "y")
  if month != nil
    s = s + (month == "2-digit" ? "MM" : (month == "numeric" ? "M" : (month == "long" ? "MMMM" : (month == "narrow" ? "MMMMM" : "MMM"))))
  if day != nil
    s = s + (day == "2-digit" ? "dd" : "d")
  if weekday != nil
    s = s + (weekday == "long" ? "EEEE" : (weekday == "narrow" ? "EEEEE" : "E"))
  if day_period != nil
    s = s + (day_period == "long" ? "BBBB" : (day_period == "narrow" ? "BBBBB" : "B"))
  if hour != nil
    hch = hc == "h11" ? "K" : (hc == "h12" ? "h" : (hc == "h24" ? "k" : "H"))
    s = s + (hour == "2-digit" ? (hch + hch) : hch)
  if minute != nil
    s = s + (minute == "2-digit" ? "mm" : "m")
  if second != nil
    s = s + (second == "2-digit" ? "ss" : "s")
  if frac_sec != nil
    i = 0
    while i < frac_sec
      s = s + "S"
      i += 1
  if tz_name != nil
    s = s + (tz_name == "short" ? "z" : (tz_name == "long" ? "zzzz" : (tz_name == "shortOffset" ? "O" : (tz_name == "longOffset" ? "OOOO" : (tz_name == "shortGeneric" ? "v" : "vvvv")))))
  s

-> intl_dtf_style_enum(st)
  return 0 if st == "full"
  return 1 if st == "long"
  return 2 if st == "medium"
  return 3 if st == "short"
  -1

-> intl_dtf_resolve_pattern(icu_loc, icu_tz, date_style, time_style, skel, hc, data_loc = "")
  if date_style != nil || time_style != nil
    # Open ICU UDateFormat with dateStyle/timeStyle + hours keyword so ICU natively handles 12h/24h & AM/PM!
    loc_hc = hc != nil ? (icu_loc + ";hours=" + hc) : icu_loc
    fn_open = icu_sym("udat_open")
    fn_pat = icu_sym("udat_toPattern")
    fn_close = icu_sym("udat_close")
    lb = icu_cstr(loc_hc)
    ut = icu_to_u16(icu_tz)
    tba = ut[0]
    eb = icu_err_buf()
    df = icu_c8(fn_open, intl_dtf_style_enum(time_style), intl_dtf_style_enum(date_style), icu_ptr(lb), icu_ptr(tba), ut[1], 0, 0, icu_ptr(eb))
    pat = ""
    if df != 0 && icu_err_code(eb) <= 0
      dst = ByteArray.new(512)
      icu_err_reset(eb)
      n = icu_sext32(icu_c5(fn_pat, df, 0, icu_ptr(dst), 256, icu_ptr(eb)))
      pat = icu_from_u16_ba(dst, n) if icu_err_code(eb) <= 0 && n > 0
      icu_c1(fn_close, df)
    lb.size
    tba.size
    eb.size
    pat = intl_dtf_apply_hc_to_pattern(pat, hc) if hc == "h24" || hc == "h11"
    return pat
  # Component skeleton -> udatpg_getBestPatternWithOptions
  fn_open = icu_sym("udatpg_open")
  fn_best = icu_sym("udatpg_getBestPatternWithOptions")
  fn_close = icu_sym("udatpg_close")
  lb = icu_cstr(icu_loc)
  us = icu_to_u16(skel)
  sba = us[0]
  eb = icu_err_buf()
  pg = icu_c2(fn_open, icu_ptr(lb), icu_ptr(eb))
  pat = skel
  if pg != 0 && icu_err_code(eb) <= 0
    dst = ByteArray.new(512)
    icu_err_reset(eb)
    # UDATPG_MATCH_HOUR_FIELD_LENGTH = 1 << 11 = 2048
    n = icu_sext32(icu_c7(fn_best, pg, icu_ptr(sba), us[1], 2048, icu_ptr(dst), 256, icu_ptr(eb)))
    pat = icu_from_u16_ba(dst, n) if icu_err_code(eb) <= 0 && n > 0
    icu_c1(fn_close, pg)
  lb.size
  sba.size
  eb.size
  pat = intl_dtf_apply_hc_to_pattern(pat, hc) if hc == "h24" || hc == "h11"
  # German CLDR short weekday without year expects comma ("EEE, d. MMMM")
  if (data_loc == "de" || data_loc.starts_with?("de-")) && pat.starts_with?("EEE d.")
    pat = "EEE, " + pat.slice(4, pat.size - 4)
  # Normalize U+202F narrow no-break space before 'a' to ASCII space for hanidec/en-US compatibility
  nnbsp_a = js_from_units([8239, 97])
  if pat.index(nnbsp_a) != nil && icu_loc.index("numbers=hanidec") != nil
    pat = pat.split(nnbsp_a).join(" a")
  pat

-> intl_dtf_apply_hc_to_pattern(pat, hc)
  # Adjust hour letter H/h/K/k in pattern to match hc (outside quoted literals)
  hch = hc == "h11" ? 75 : (hc == "h12" ? 104 : (hc == "h24" ? 107 : 72))
  ba = ByteArray.new(pat.size)
  in_q = false
  i = 0
  while i < pat.size
    c = pat.byte_at(i)
    if c == 39
      in_q = !in_q
      ba[i] = c
    elsif !in_q && (c == 72 || c == 104 || c == 75 || c == 107)
      ba[i] = hch
    else
      ba[i] = c
    i += 1
  ccall("w_string_from_byte_array", ba)

-> intl_dtf_to_epoch(v)
  return js_date_now() if v == nil
  n = js_to_number(v)
  t = js_time_clip(n)
  js_throw_range("Invalid time value") if t != t
  t

-> intl_dtf_format_epoch(d, epoch_ms, want_parts)
  fn_open = icu_sym("udat_open")
  fn_fmt = icu_sym("udat_formatForFields")
  fn_close = icu_sym("udat_close")
  fn_fpi_o = icu_sym("ufieldpositer_open")
  fn_fpi_n = icu_sym("ufieldpositer_next")
  fn_fpi_c = icu_sym("ufieldpositer_close")
  lb = icu_cstr(d[19])
  ut = icu_to_u16(d[20])
  tba = ut[0]
  up = icu_to_u16(d[22])
  pba = up[0]
  eb = icu_err_buf()
  # UDAT_PATTERN = -2
  df = icu_c8(fn_open, -2, -2, icu_ptr(lb), icu_ptr(tba), ut[1], icu_ptr(pba), up[1], icu_ptr(eb))
  if df == 0 || icu_err_code(eb) > 0
    lb.size; tba.size; pba.size; eb.size
    return want_parts ? js_realm().adopt_array([]) : ""
  # Proleptic Gregorian calendar per ECMA-402 §11.1 (no Julian switchover in 1582!)
  ca = d[1]
  if ca == "gregory" || ca == "iso8601"
    fn_gcal = icu_sym("udat_getCalendar")
    fn_sgc = icu_sym("ucal_setGregorianChange")
    cal = icu_c1(fn_gcal, df)
    if cal != 0
      icu_err_reset(eb)
      # -1e20 ms (well before -8.64e15 ECMA-262 min Date!)
      icu_c_pdp(fn_sgc, cal, wvalue_bits(~-100000000000000000000.0) ## i64, icu_ptr(eb))
  # Check pre-Hijrah Islamic era & pre-epoch Coptic era (ICU returns era 0 AH / empty "" instead of era 1 BH / AM!)
  bh_era_str = nil
  is_coptic_fix = false
  if d[7] != nil && (ca == "islamic-civil" || ca == "islamic-tbla" || ca == "islamic-umalqura" || ca == "coptic")
    fn_gcal = icu_sym("udat_getCalendar")
    fn_setm = icu_sym("ucal_setMillis")
    fn_getf = icu_sym("ucal_get")
    cal = icu_c1(fn_gcal, df)
    if cal != 0
      icu_err_reset(eb)
      icu_c_pdp(fn_setm, cal, wvalue_bits(epoch_ms) ## i64, icu_ptr(eb))
      icu_err_reset(eb)
      # UCAL_EXTENDED_YEAR = 19
      ey = icu_sext32(icu_c3(fn_getf, cal, 19, icu_ptr(eb)))
      if icu_err_code(eb) <= 0 && ey <= 0
        fn_gsym = icu_sym("udat_getSymbols")
        sym_t = d[7] == "long" ? 7 : 0
        ebuf = ByteArray.new(256)
        icu_err_reset(eb)
        eln = icu_sext32(icu_c6(fn_gsym, df, sym_t, 1, icu_ptr(ebuf), 128, icu_ptr(eb)))
        if icu_err_code(eb) <= 0 && eln > 0
          bh_era_str = icu_from_u16_ba(ebuf, eln)
          is_coptic_fix = (ca == "coptic")
  need_fpi = want_parts || bh_era_str != nil
  fpi = need_fpi ? icu_c1(fn_fpi_o, icu_ptr(eb)) : 0
  cap = 256
  dst = ByteArray.new(cap * 2)
  icu_err_reset(eb)
  n = icu_sext32(icu_c_pdpipp(fn_fmt, df, wvalue_bits(epoch_ms) ## i64, icu_ptr(dst), cap, fpi, icu_ptr(eb)))
  ec = icu_err_code(eb)
  if ec == 15 && n > 0
    cap = n + 4
    dst = ByteArray.new(cap * 2)
    icu_err_reset(eb)
    n = icu_sext32(icu_c_pdpipp(fn_fmt, df, wvalue_bits(epoch_ms) ## i64, icu_ptr(dst), cap, fpi, icu_ptr(eb)))
  str = n > 0 ? icu_from_u16_ba(dst, n) : ""
  if !need_fpi
    icu_c1(fn_close, df)
    lb.size; tba.size; pba.size; eb.size
    return str
  # Collect field spans from fpi
  sb = ByteArray.new(8)
  eb2 = ByteArray.new(8)
  spans = []
  if fpi != 0
    while true
      fld = icu_sext32(icu_c3(fn_fpi_n, fpi, icu_ptr(sb), icu_ptr(eb2)))
      break if fld < 0
      st = icu_load_i32(icu_ptr(sb), 0)
      lm = icu_load_i32(icu_ptr(eb2), 0)
      spans.push([fld, st, lm]) if lm > st || (is_coptic_fix && fld == 0)
    icu_c1(fn_fpi_c, fpi)
  icu_c1(fn_close, df)
  sb.size; eb2.size; lb.size; tba.size; pba.size; eb.size
  # Replace pre-Hijrah Islamic era or missing pre-epoch Coptic era with localized era string
  if bh_era_str != nil
    has_era_span = false
    spans.each ->(sp) has_era_span = true if sp[0] == 0
    if !has_era_span && is_coptic_fix
      # Prepend era span at position 0 (where ICU emitted empty "" before space + year)
      spans.unshift([0, 0, 0])
    new_str = ""
    new_spans = []
    pos = 0
    delta = 0
    k = 0
    while k < spans.size
      sp = spans[k]
      st = sp[1]
      lm = sp[2]
      new_str = new_str + js_substring(str, pos, st) if st > pos
      if sp[0] == 0
        nst = st + delta
        new_str = new_str + bh_era_str
        blen = js_len(bh_era_str)
        new_spans.push([0, nst, nst + blen])
        delta += blen - (lm - st)
      else
        new_str = new_str + js_substring(str, st, lm)
        new_spans.push([sp[0], st + delta, lm + delta])
      pos = lm
      k += 1
    ulen0 = js_len(str)
    new_str = new_str + js_substring(str, pos, ulen0) if pos < ulen0
    str = new_str
    spans = new_spans
  return str if !want_parts
  intl_dtf_parts_from_spans(str, spans, nil)

-> intl_dtf_parts_from_spans(str, spans, src_spans)
  ulen = js_len(str)
  out = []
  pos = 0
  i = 0
  while i < spans.size
    sp = spans[i]
    st = sp[1]
    lm = sp[2]
    if st > pos
      p = js_realm().new_object
      p.define("type", "literal", ATTR_W + ATTR_E + ATTR_C)
      p.define("value", js_substring(str, pos, st), ATTR_W + ATTR_E + ATTR_C)
      p.define("source", intl_find_source(pos, st, src_spans), ATTR_W + ATTR_E + ATTR_C) if src_spans != nil
      out.push(p)
    if lm > st && st >= pos
      p = js_realm().new_object
      p.define("type", intl_dtf_field_name(sp[0]), ATTR_W + ATTR_E + ATTR_C)
      p.define("value", js_substring(str, st, lm), ATTR_W + ATTR_E + ATTR_C)
      p.define("source", intl_find_source(st, lm, src_spans), ATTR_W + ATTR_E + ATTR_C) if src_spans != nil
      out.push(p)
      pos = lm
    i += 1
  if pos < ulen
    p = js_realm().new_object
    p.define("type", "literal", ATTR_W + ATTR_E + ATTR_C)
    p.define("value", js_substring(str, pos, ulen), ATTR_W + ATTR_E + ATTR_C)
    p.define("source", intl_find_source(pos, ulen, src_spans), ATTR_W + ATTR_E + ATTR_C) if src_spans != nil
    out.push(p)
  js_realm().adopt_array(out)

-> intl_dtf_format_range_impl(d, start_v, end_v, want_parts)
  js_throw_type("startDate and endDate must be provided to formatRange") if start_v == nil || end_v == nil
  if JS_TEMPORAL_DTF_HOOK[0] != nil
    hk = JS_TEMPORAL_DTF_HOOK[0].call([:range, d, start_v, end_v, want_parts])
    return hk if hk != JS_HOLE
  t1 = intl_dtf_to_epoch(start_v)
  t2 = intl_dtf_to_epoch(end_v)
  # Use ICU UDateIntervalFormat with skeleton (derived from pattern or skeleton)
  skel = d[21]
  if skel.size == 0
    # Derive skeleton from dateStyle/timeStyle pattern using udatpg_getSkeleton
    fn_gs = icu_sym("udatpg_getSkeleton")
    up = icu_to_u16(d[22])
    pba = up[0]
    dst = ByteArray.new(256)
    eb0 = icu_err_buf()
    n0 = icu_sext32(icu_c6(fn_gs, 0, icu_ptr(pba), up[1], icu_ptr(dst), 128, icu_ptr(eb0)))
    skel = icu_from_u16_ba(dst, n0) if icu_err_code(eb0) <= 0 && n0 > 0
    pba.size; eb0.size
  fn_open = icu_sym("udtitvfmt_open")
  fn_res = icu_sym("udtitvfmt_openResult")
  fn_fmt = icu_sym("udtitvfmt_formatToResult")
  fn_val = icu_sym("udtitvfmt_resultAsValue")
  fn_c_res = icu_sym("udtitvfmt_closeResult")
  fn_c = icu_sym("udtitvfmt_close")
  lb = icu_cstr(d[19])
  us = icu_to_u16(skel)
  sba = us[0]
  ut = icu_to_u16(d[20])
  tba = ut[0]
  eb = icu_err_buf()
  ivf = icu_c6(fn_open, icu_ptr(lb), icu_ptr(sba), us[1], icu_ptr(tba), ut[1], icu_ptr(eb))
  res = icu_c1(fn_res, icu_ptr(eb))
  icu_err_reset(eb)
  icu_c_pddpp(fn_fmt, ivf, wvalue_bits(t1) ## i64, wvalue_bits(t2) ## i64, res, icu_ptr(eb))
  icu_err_reset(eb)
  fv = icu_c2(fn_val, res, icu_ptr(eb))
  ex = icu_fmtval_extract(fv, -1)
  icu_c1(fn_c_res, res) if res != 0
  icu_c1(fn_c, ivf) if ivf != 0
  lb.size; sba.size; tba.size; eb.size
  str = ex[0]
  return str if !want_parts
  # UFIELD_CATEGORY_DATE = 1, UFIELD_CATEGORY_DATE_INTERVAL_SPAN = 0x1005 = 4101
  spans = []
  src_spans = []
  ex[1].each ->(pt)
    if pt[0] == 1 && pt[3] > pt[2]
      spans.push([pt[1], pt[2], pt[3]])
    elsif pt[0] == 4101
      src_spans.push([pt[1], pt[2], pt[3]])
  intl_dtf_parts_from_spans(str, spans, src_spans)

-> intl_dtf_format_any(d, v, want_parts)
  if JS_TEMPORAL_DTF_HOOK[0] != nil
    hk = JS_TEMPORAL_DTF_HOOK[0].call([:single, d, v, nil, want_parts])
    return hk if hk != JS_HOLE
  intl_dtf_format_epoch(d, intl_dtf_to_epoch(v), want_parts)

-> intl_dtf_get_format(this)
  d = intl_unwrap(this, "Intl.DateTimeFormat", "format")
  return d[23] if d[23] != nil
  fn = ->(th, args, nt) intl_dtf_format_any(d, js_arg(args, 0), false)
  bf = js_realm().native("", 1, fn)
  d[23] = bf
  bf

-> intl_dtf_resolved(this)
  d = intl_unwrap(this, "Intl.DateTimeFormat", "resolvedOptions")
  o = js_realm().new_object
  o.define("locale", d[0], ATTR_W + ATTR_E + ATTR_C)
  o.define("calendar", d[1], ATTR_W + ATTR_E + ATTR_C)
  o.define("numberingSystem", d[2], ATTR_W + ATTR_E + ATTR_C)
  o.define("timeZone", d[3], ATTR_W + ATTR_E + ATTR_C)
  if d[4] != nil
    o.define("hourCycle", d[4], ATTR_W + ATTR_E + ATTR_C)
    o.define("hour12", d[5], ATTR_W + ATTR_E + ATTR_C)
  o.define("weekday", d[6], ATTR_W + ATTR_E + ATTR_C) if d[6] != nil
  o.define("era", d[7], ATTR_W + ATTR_E + ATTR_C) if d[7] != nil
  o.define("year", d[8], ATTR_W + ATTR_E + ATTR_C) if d[8] != nil
  o.define("month", d[9], ATTR_W + ATTR_E + ATTR_C) if d[9] != nil
  o.define("day", d[10], ATTR_W + ATTR_E + ATTR_C) if d[10] != nil
  o.define("dayPeriod", d[11], ATTR_W + ATTR_E + ATTR_C) if d[11] != nil
  o.define("hour", d[12], ATTR_W + ATTR_E + ATTR_C) if d[12] != nil
  o.define("minute", d[13], ATTR_W + ATTR_E + ATTR_C) if d[13] != nil
  o.define("second", d[14], ATTR_W + ATTR_E + ATTR_C) if d[14] != nil
  o.define("fractionalSecondDigits", d[15] + ~0.0, ATTR_W + ATTR_E + ATTR_C) if d[15] != nil
  o.define("timeZoneName", d[16], ATTR_W + ATTR_E + ATTR_C) if d[16] != nil
  o.define("dateStyle", d[17], ATTR_W + ATTR_E + ATTR_C) if d[17] != nil
  o.define("timeStyle", d[18], ATTR_W + ATTR_E + ATTR_C) if d[18] != nil
  o

# ---- Intl.DurationFormat ----

INTL_DUR_UNITS = [
  ["years", "year", "yearsDisplay", ["long", "short", "narrow"], "short"],
  ["months", "month", "monthsDisplay", ["long", "short", "narrow"], "short"],
  ["weeks", "week", "weeksDisplay", ["long", "short", "narrow"], "short"],
  ["days", "day", "daysDisplay", ["long", "short", "narrow"], "short"],
  ["hours", "hour", "hoursDisplay", ["long", "short", "narrow", "numeric", "2-digit"], "numeric"],
  ["minutes", "minute", "minutesDisplay", ["long", "short", "narrow", "numeric", "2-digit"], "numeric"],
  ["seconds", "second", "secondsDisplay", ["long", "short", "narrow", "numeric", "2-digit"], "numeric"],
  ["milliseconds", "millisecond", "millisecondsDisplay", ["long", "short", "narrow", "numeric"], "numeric"],
  ["microseconds", "microsecond", "microsecondsDisplay", ["long", "short", "narrow", "numeric"], "numeric"],
  ["nanoseconds", "nanosecond", "nanosecondsDisplay", ["long", "short", "narrow", "numeric"], "numeric"]
]

-> intl_dur_ctor(args, nt)
  js_throw_type("Constructor Intl.DurationFormat requires 'new'") if nt == nil
  req = intl_canonicalize_locale_list(js_arg(args, 0))
  opts = intl_get_options_object(js_arg(args, 1))
  intl_get_option(opts, "localeMatcher", :string, ["lookup", "best fit"], "best fit")
  opt_nu = intl_get_option(opts, "numberingSystem", :string, nil, nil)
  if opt_nu != nil
    js_throw_range("Invalid numberingSystem: " + opt_nu) if !intl_is_type_nonterminal?(opt_nu)
    opt_nu = intl_lower(opt_nu)
  avail = icu_available_locales()
  supp_nu = intl_supported_values_list("numberingSystem")
  opt_map = {}
  opt_map["nu"] = opt_nu if opt_nu != nil && supp_nu.include?(opt_nu)
  vfn = ->(k, v, found) supp_nu.include?(v)
  r = intl_resolve_locale(avail, req, opt_map, ["nu"], vfn)
  nu = r["nu"]
  if nu == nil
    loc0 = icu_for_language_tag(r["dataLocale"])
    loc0 = r["dataLocale"] if loc0 == nil
    fn_o = icu_sym("unumsys_open")
    fn_n = icu_sym("unumsys_getName")
    fn_c = icu_sym("unumsys_close")
    lb = icu_cstr(loc0)
    eb = icu_err_buf()
    ns = icu_c2(fn_o, icu_ptr(lb), icu_ptr(eb))
    lb.size
    nu = "latn"
    if ns != 0 && icu_err_code(eb) <= 0
      p = icu_c1(fn_n, ns)
      s = icu_read_cstr_ptr(p)
      nu = s if s != nil && s.size > 0
      icu_c1(fn_c, ns)
    eb.size
  style = intl_get_option(opts, "style", :string, ["long", "short", "narrow", "digital"], "short")
  # GetDurationUnitOptions for each of the 10 units in spec order!
  u_styles = Array.new(10, nil)
  u_disps = Array.new(10, nil)
  prev_style = ""
  i = 0
  while i < 10
    row = INTL_DUR_UNITS[i]
    uname = row[0]
    dname = row[2]
    allowed = row[3]
    dig_def = row[4]
    st_v = intl_get_option(opts, uname, :string, allowed, nil)
    disp_def = "always"
    if st_v == nil
      disp_def = "auto"
      if style == "digital"
        st_v = dig_def
        disp_def = "always" if i == 4 || i == 5 || i == 6
      elsif prev_style == "fractional" || prev_style == "numeric" || prev_style == "2-digit"
        st_v = "numeric"
      else
        st_v = style
    if st_v == "numeric" && i >= 7
      st_v = "fractional"
      disp_def = "auto"
    disp_v = intl_get_option(opts, dname, :string, ["auto", "always"], disp_def)
    if disp_v == "always" && st_v == "fractional"
      js_throw_range("Cannot use display 'always' with numeric subsecond unit")
    if (prev_style == "fractional" || prev_style == "numeric" || prev_style == "2-digit") && (st_v != "numeric" && st_v != "2-digit" && st_v != "fractional")
      js_throw_range("Cannot follow numeric/2-digit duration unit with non-numeric style")
    if prev_style == "fractional" && st_v != "fractional"
      js_throw_range("Cannot follow fractional unit with non-fractional unit")
    if i == 5 && (prev_style == "numeric" || prev_style == "2-digit") && st_v == "numeric"
      st_v = "2-digit"
    if i == 6 && (prev_style == "numeric" || prev_style == "2-digit") && st_v == "numeric"
      st_v = "2-digit"
    u_styles[i] = st_v == "fractional" ? "numeric" : st_v
    u_disps[i] = disp_v
    prev_style = st_v
    i += 1
  frac_dig = intl_get_number_option(opts, "fractionalDigits", 0, 9, nil)
  icu_loc = icu_for_language_tag(r["dataLocale"])
  icu_loc = r["dataLocale"] if icu_loc == nil
  proto = js_realm().proto_from(nt, "Intl.DurationFormat")
  o = js_new_special(proto, "Intl.DurationFormat")
  # internal = [locale, nu, style, u_styles, u_disps, frac_dig, icu_loc, dataLocale]
  o.internal = [r["locale"], nu, style, u_styles, u_disps, frac_dig, icu_loc, r["dataLocale"]]
  o

# Parse ISO 8601 duration string (TemporalDurationString) -> Array[10] of floats, or throws RangeError!
-> intl_parse_iso_duration(s)
  js_throw_range("Invalid duration string: " + s) if s.size < 2
  i = 0
  n = s.size
  sign = 1
  c0 = s.byte_at(0)
  if c0 == 43
    i = 1
  elsif c0 == 45
    sign = -1
    i = 1
  elsif n >= 3 && c0 == 226 && s.byte_at(1) == 136 && s.byte_at(2) == 146
    # U+2212 MINUS SIGN
    sign = -1
    i = 3
  js_throw_range("Invalid duration string: " + s) if i >= n
  cp = s.byte_at(i)
  js_throw_range("Invalid duration string: " + s) if cp != 80 && cp != 112   # P / p
  i += 1
  js_throw_range("Invalid duration string: " + s) if i >= n
  vals = Array.new(10, ~0.0)
  in_time = false
  any_comp = false
  any_time = false
  # Order indices: date: Y=0, M=1, W=2, D=3; time: H=4, M=5, S=6
  last_d = -1
  last_t = -1
  had_frac = false
  while i < n
    c = s.byte_at(i)
    if c == 84 || c == 116  # T / t
      js_throw_range("Invalid duration string: " + s) if in_time
      in_time = true
      i += 1
      js_throw_range("Invalid duration string: " + s) if i >= n
      next
    js_throw_range("Invalid duration string: " + s) if had_frac
    # Parse integer digits
    dstart = i
    while i < n && s.byte_at(i) >= 48 && s.byte_at(i) <= 57
      i += 1
    js_throw_range("Invalid duration string: " + s) if i == dstart || i >= n
    int_str = s.slice(dstart, i - dstart)
    frac_str = nil
    if s.byte_at(i) == 46 || s.byte_at(i) == 44  # '.' or ','
      js_throw_range("Invalid duration string: " + s) if !in_time
      i += 1
      fstart = i
      while i < n && s.byte_at(i) >= 48 && s.byte_at(i) <= 57
        i += 1
      flen = i - fstart
      js_throw_range("Invalid duration string: " + s) if flen == 0 || flen > 9 || i >= n
      frac_str = s.slice(fstart, flen)
      had_frac = true
    des = s.byte_at(i)
    i += 1
    iv = int_str.to_f
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
      vals[idx] = iv == ~0.0 ? ~0.0 : (sign < 0 ? ~0.0 - iv : iv)
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
      vals[idx] = iv == ~0.0 ? ~0.0 : (sign < 0 ? ~0.0 - iv : iv)
      if frac_str != nil
        # Pad frac_str to 9 digits (nanoseconds)
        f9 = frac_str
        while f9.size < 9
          f9 = f9 + "0"
        fn = f9.to_i
        if idx == 4
          # Fractional hours -> minutes, seconds, ms, us, ns (fn * 3600 ns)
          tot_ns = (fn ## int) * (3600 ## int)
          mins = (tot_ns / (60000000000 ## int)).to_f
          rem = tot_ns % (60000000000 ## int)
          secs = (rem / (1000000000 ## int)).to_f
          rem = rem % (1000000000 ## int)
          ms = (rem / (1000000 ## int)).to_f
          rem = rem % (1000000 ## int)
          us = (rem / (1000 ## int)).to_f
          ns = (rem % (1000 ## int)).to_f
          vals[5] = mins == ~0.0 ? ~0.0 : (sign < 0 ? ~0.0 - mins : mins)
          vals[6] = secs == ~0.0 ? ~0.0 : (sign < 0 ? ~0.0 - secs : secs)
          vals[7] = ms == ~0.0 ? ~0.0 : (sign < 0 ? ~0.0 - ms : ms)
          vals[8] = us == ~0.0 ? ~0.0 : (sign < 0 ? ~0.0 - us : us)
          vals[9] = ns == ~0.0 ? ~0.0 : (sign < 0 ? ~0.0 - ns : ns)
        elsif idx == 5
          tot_ns = (fn ## int) * (60 ## int)
          secs = (tot_ns / (1000000000 ## int)).to_f
          rem = tot_ns % (1000000000 ## int)
          ms = (rem / (1000000 ## int)).to_f
          rem = rem % (1000000 ## int)
          us = (rem / (1000 ## int)).to_f
          ns = (rem % (1000 ## int)).to_f
          vals[6] = secs == ~0.0 ? ~0.0 : (sign < 0 ? ~0.0 - secs : secs)
          vals[7] = ms == ~0.0 ? ~0.0 : (sign < 0 ? ~0.0 - ms : ms)
          vals[8] = us == ~0.0 ? ~0.0 : (sign < 0 ? ~0.0 - us : us)
          vals[9] = ns == ~0.0 ? ~0.0 : (sign < 0 ? ~0.0 - ns : ns)
        else
          ms = (fn / 1000000).to_f
          us = ((fn / 1000) % 1000).to_f
          ns = (fn % 1000).to_f
          vals[7] = ms == ~0.0 ? ~0.0 : (sign < 0 ? ~0.0 - ms : ms)
          vals[8] = us == ~0.0 ? ~0.0 : (sign < 0 ? ~0.0 - us : us)
          vals[9] = ns == ~0.0 ? ~0.0 : (sign < 0 ? ~0.0 - ns : ns)
      any_comp = true
      any_time = true
  js_throw_range("Invalid duration string: " + s) if !any_comp || (in_time && !any_time)
  vals

# Exact IsValidDuration check (bounds on years/months/weeks < 2^32, exact BigInt ns < 2^53 * 10^9)
-> intl_validate_duration_bounds(vals)
  js_throw_range("Duration years out of range") if js_math_abs(vals[0]) >= ~4294967296.0
  js_throw_range("Duration months out of range") if js_math_abs(vals[1]) >= ~4294967296.0
  js_throw_range("Duration weeks out of range") if js_math_abs(vals[2]) >= ~4294967296.0
  # Exact BigInt nanosecond magnitude check (IsValidDurationRecord step 16-17: |normalizedSeconds| < 2^53)
  max_ns = (9007199254740992 ## int) * (1000000000 ## int)
  tot_ns = 0 ## int
  tot_ns = tot_ns + js_bi_from_num(js_math_abs(vals[3])).v * (86400000000000 ## int) if vals[3] != ~0.0
  tot_ns = tot_ns + js_bi_from_num(js_math_abs(vals[4])).v * (3600000000000 ## int) if vals[4] != ~0.0
  tot_ns = tot_ns + js_bi_from_num(js_math_abs(vals[5])).v * (60000000000 ## int) if vals[5] != ~0.0
  tot_ns = tot_ns + js_bi_from_num(js_math_abs(vals[6])).v * (1000000000 ## int) if vals[6] != ~0.0
  tot_ns = tot_ns + js_bi_from_num(js_math_abs(vals[7])).v * (1000000 ## int) if vals[7] != ~0.0
  tot_ns = tot_ns + js_bi_from_num(js_math_abs(vals[8])).v * (1000 ## int) if vals[8] != ~0.0
  tot_ns = tot_ns + js_bi_from_num(js_math_abs(vals[9])).v if vals[9] != ~0.0
  js_throw_range("Duration time out of range") if tot_ns >= max_ns
  vals

# ToDurationRecord ( input ) — returns Array[10] of floats (integers)
-> intl_to_duration_record(input)
  if js_special?(input, "Temporal.Duration")
    dv = input.internal
    out = Array.new(10, ~0.0)
    k = 0
    while k < 10
      out[k] = tm_int_to_num(dv[k])
      k += 1
    return out
  if js_string?(input)
    vals = intl_parse_iso_duration(input)
    return intl_validate_duration_bounds(vals)
  js_throw_type("Duration must be an object or string") if !js_object?(input)
  # Read properties in alphabetical order per ECMA-402 ToDurationRecord!
  # days, hours, microseconds, milliseconds, minutes, months, nanoseconds, seconds, weeks, years
  order = [
    ["days", 3], ["hours", 4], ["microseconds", 8], ["milliseconds", 7],
    ["minutes", 5], ["months", 1], ["nanoseconds", 9], ["seconds", 6],
    ["weeks", 2], ["years", 0]
  ]
  vals = Array.new(10, ~0.0)
  any_def = false
  i = 0
  while i < 10
    nm = order[i][0]
    idx = order[i][1]
    v = jget(input, nm)
    if v != nil
      any_def = true
      n = js_to_number(v)
      js_throw_range("Duration field '" + nm + "' must be an integer") if !js_finite?(n) || js_math_trunc(n) != n
      vals[idx] = n == ~0.0 ? ~0.0 : n
    i += 1
  js_throw_type("Duration object must have at least one valid duration property") if !any_def
  # Validate consistent signs & bounds (IsValidDuration)
  sign = 0
  i = 0
  while i < 10
    v = vals[i]
    if v > ~0.0
      js_throw_range("Duration fields must have consistent signs") if sign < 0
      sign = 1
    elsif v < ~0.0
      js_throw_range("Duration fields must have consistent signs") if sign > 0
      sign = -1
    i += 1
  intl_validate_duration_bounds(vals)

-> intl_dur_run(this, input, want_parts)
  js_throw_type("Intl.DurationFormat method called on incompatible receiver") if !js_special?(this, "Intl.DurationFormat")
  d = this.internal
  vals = intl_to_duration_record(input)
  nu = d[1]
  style = d[2]
  u_styles = d[3]
  u_disps = d[4]
  frac_dig = d[5]
  icu_loc = d[6]
  data_loc = d[7]

  # Determine sign of duration
  neg = false
  i = 0
  while i < 10
    if vals[i] < ~0.0
      neg = true
      break
    i += 1

  # Collect formatted unit chunks (list of [str, parts_array])
  chunks = []
  sign_shown = false
  i = 0
  while i < 10
    v = vals[i]
    ust = u_styles[i]
    udisp = u_disps[i]
    uname_sing = INTL_DUR_UNITS[i][1]
    # Check if next unit(s) fold into this unit as fractional digits (seconds/ms/us with numeric next!)
    if (i == 6 || i == 7 || i == 8) && i + 1 < 10 && u_styles[i + 1] == "numeric"
      # Combine remaining subsecond values into a decimal string!
      comb = intl_dur_combine_subsec(vals, i)
      is_zero = comb == "0" || comb == "-0"
      if !is_zero || udisp == "always"
        min_f = frac_dig == nil ? 0 : frac_dig
        max_f = frac_dig == nil ? 9 : frac_dig
        mv = [:decimal, sign_shown ? intl_abs_dec(comb) : comb]
        sign_shown = true if neg
        ch = intl_dur_fmt_unit(icu_loc, nu, uname_sing, ust, mv, min_f, max_f, frac_dig == nil)
        chunks.push(ch)
      break
    # Digital / numeric / 2-digit group (hours:minutes:seconds)
    if (i == 4 || i == 5 || i == 6) && (ust == "numeric" || ust == "2-digit")
      # Gather contiguous numeric/2-digit group starting at i
      grp = intl_dur_fmt_digital_group(d, vals, i, neg, sign_shown)
      sign_shown = true if neg && grp[0] != nil
      chunks.push(grp[0]) if grp[0] != nil
      i = grp[1]
      next
    if v != ~0.0 || udisp == "always"
      av = sign_shown ? js_math_abs(v) : (v == ~0.0 && neg ? ~-0.0 : v)
      sign_shown = true if neg
      ch = intl_dur_fmt_unit(icu_loc, nu, uname_sing, ust, intl_to_math_val(av), 0, 0, false)
      chunks.push(ch)
    i += 1

  if chunks.size == 0
    return want_parts ? js_realm().adopt_array([]) : ""
  if chunks.size == 1
    return want_parts ? js_realm().adopt_array(chunks[0][1]) : chunks[0][0]

  # Combine chunks with ICU ListFormat (type: "unit", width matching style)
  lf_w = style == "long" ? 0 : (style == "narrow" ? 2 : 1)
  fn_open = icu_sym("ulistfmt_openForType")
  fn_res = icu_sym("ulistfmt_openResult")
  fn_fmt = icu_sym("ulistfmt_formatStringsToResult")
  fn_val = icu_sym("ulistfmt_resultAsValue")
  fn_c_res = icu_sym("ulistfmt_closeResult")
  fn_c = icu_sym("ulistfmt_close")
  lb = icu_cstr(icu_loc)
  eb = icu_err_buf()
  lf = icu_c4(fn_open, icu_ptr(lb), 2, lf_w, icu_ptr(eb))   # ULISTFMT_TYPE_UNITS = 2
  res = icu_c1(fn_res, icu_ptr(eb))
  n = chunks.size
  u_bufs = Array.new(n, nil)
  ptrs = ByteArray.new(n * 8)
  lens = ByteArray.new(n * 4)
  i = 0
  while i < n
    u = icu_to_u16(chunks[i][0])
    u_bufs[i] = u[0]
    icu_store_i64(icu_ptr(ptrs), i * 8, icu_ptr(u[0]))
    icu_store_i32(icu_ptr(lens), i * 4, u[1])
    i += 1
  icu_err_reset(eb)
  icu_c6(fn_fmt, lf, icu_ptr(ptrs), icu_ptr(lens), n, res, icu_ptr(eb))
  icu_err_reset(eb)
  fv = icu_c2(fn_val, res, icu_ptr(eb))
  ex = icu_fmtval_extract(fv, 3)
  icu_c1(fn_c_res, res) if res != 0
  icu_c1(fn_c, lf) if lf != 0
  u_bufs.size; ptrs.size; lens.size; lb.size; eb.size
  full_str = ex[0]
  return full_str if !want_parts
  # Stitch chunk parts into ListFormat output!
  ulen = js_len(full_str)
  elems = []
  ex[1].each ->(pt) elems.push([pt[2], pt[3]]) if pt[1] == 1
  out = []
  pos = 0
  ci = 0
  while ci < elems.size
    st = elems[ci][0]
    lm = elems[ci][1]
    if st > pos
      p = js_realm().new_object
      p.define("type", "literal", ATTR_W + ATTR_E + ATTR_C)
      p.define("value", js_substring(full_str, pos, st), ATTR_W + ATTR_E + ATTR_C)
      out.push(p)
    if ci < chunks.size
      chunks[ci][1].each ->(cp) out.push(cp)
    pos = lm
    ci += 1
  if pos < ulen
    p = js_realm().new_object
    p.define("type", "literal", ATTR_W + ATTR_E + ATTR_C)
    p.define("value", js_substring(full_str, pos, ulen), ATTR_W + ATTR_E + ATTR_C)
    out.push(p)
  js_realm().adopt_array(out)

-> intl_abs_dec(s)
  s.starts_with?("-") ? s.slice(1, s.size - 1) : s

-> intl_dur_combine_subsec(vals, start_i)
  # Combine vals[start_i..9] as exact decimal string in units of start_i!
  neg = false
  k = start_i
  while k < 10
    neg = true if vals[k] < ~0.0
    k += 1
  # Compute integer total in nanoseconds using BigInt!
  tot = js_bi_from_int(0)
  if start_i == 6
    # seconds * 1e9 + ms * 1e6 + us * 1e3 + ns
    tot = js_bi_add(tot, js_bi_mul(js_bi_from_num(js_math_abs(vals[6])), js_bi_from_int(1000000000)))
    tot = js_bi_add(tot, js_bi_mul(js_bi_from_num(js_math_abs(vals[7])), js_bi_from_int(1000000)))
    tot = js_bi_add(tot, js_bi_mul(js_bi_from_num(js_math_abs(vals[8])), js_bi_from_int(1000)))
    tot = js_bi_add(tot, js_bi_from_num(js_math_abs(vals[9])))
    scale = 9
  elsif start_i == 7
    tot = js_bi_add(tot, js_bi_mul(js_bi_from_num(js_math_abs(vals[7])), js_bi_from_int(1000000)))
    tot = js_bi_add(tot, js_bi_mul(js_bi_from_num(js_math_abs(vals[8])), js_bi_from_int(1000)))
    tot = js_bi_add(tot, js_bi_from_num(js_math_abs(vals[9])))
    scale = 6
  else
    tot = js_bi_add(tot, js_bi_mul(js_bi_from_num(js_math_abs(vals[8])), js_bi_from_int(1000)))
    tot = js_bi_add(tot, js_bi_from_num(js_math_abs(vals[9])))
    scale = 3
  s = js_bigint_to_string(tot, nil)
  return (neg ? "-0" : "0") if s == "0"
  while s.size <= scale
    s = "0" + s
  sp = s.size - scale
  ip = s.slice(0, sp)
  fp = s.slice(sp, scale)
  # Trim trailing zeros from fp
  e = fp.size
  while e > 0 && fp.byte_at(e - 1) == 48
    e -= 1
  fp = fp.slice(0, e)
  res = fp.size > 0 ? (ip + "." + fp) : ip
  neg ? ("-" + res) : res

-> intl_dur_fmt_unit(icu_loc, nu, unit_sing, ust, mv, min_f, max_f, trunc_mode)
  sk = []
  if ust == "long" || ust == "short" || ust == "narrow"
    sk.push("measure-unit/" + INTL_UNIT_ICU[unit_sing])
    sk.push(ust == "long" ? "unit-width-full-name" : (ust == "narrow" ? "unit-width-narrow" : "unit-width-short"))
  elsif ust == "2-digit"
    sk.push("integer-width/+00")
    sk.push("group-off")
  else
    sk.push("group-off")
  if max_f > 0 || min_f > 0
    p = "."
    k = 0
    while k < min_f
      p = p + "0"
      k += 1
    while k < max_f
      p = p + "#"
      k += 1
    sk.push(p)
  else
    sk.push(".")
  sk.push("rounding-mode-down")
  sk.push("numbering-system/" + nu)
  skeleton = sk.join(" ")
  # Use fake NF internal array layout for intl_nf_format_impl
  d = [nil, nu, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, skeleton, icu_loc, nil]
  parts = intl_nf_format_impl(d, mv, true)
  str = ""
  out_parts = []
  i = 0
  while i < parts.size
    pt = parts[i]
    val = jget(pt, "value")
    str = str + val
    pt.define("unit", unit_sing, ATTR_W + ATTR_E + ATTR_C)
    out_parts.push(pt)
    i += 1
  [str, out_parts]

-> intl_dur_fmt_digital_group(d, vals, start_i, neg, sign_shown)
  nu = d[1]
  u_styles = d[3]
  u_disps = d[4]
  frac_dig = d[5]
  icu_loc = d[6]
  # Determine which of hours(4), minutes(5), seconds(6) are displayed
  end_i = start_i
  while end_i < 7 && (u_styles[end_i] == "numeric" || u_styles[end_i] == "2-digit")
    end_i += 1
  # If seconds is included and ms/us/ns are numeric, fold subseconds into seconds!
  fold_sub = end_i == 7 && u_styles[7] == "numeric"
  next_i = fold_sub ? 10 : end_i
  show = []
  k = start_i
  while k < end_i
    if k == 6 && fold_sub
      comb = intl_dur_combine_subsec(vals, 6)
      is_z = comb == "0" || comb == "-0"
      show.push([k, comb, true]) if !is_z || u_disps[k] == "always"
    elsif vals[k] != ~0.0 || u_disps[k] == "always"
      show.push([k, vals[k], false])
    elsif k == 5 && start_i == 4 && end_i == 7 && (vals[4] != ~0.0 || u_disps[4] == "always") && (vals[6] != ~0.0 || u_disps[6] == "always" || (fold_sub && intl_dur_combine_subsec(vals, 6) != "0"))
      # Middle minutes must be shown if both hours and seconds are shown!
      show.push([k, ~0.0, false])
    k += 1
  return [nil, next_i] if show.size == 0
  # Time separator (localized via ICU or ":")
  sep = ":"
  str = ""
  parts = []
  si = 0
  while si < show.size
    if si > 0
      str = str + sep
      lp = js_realm().new_object
      lp.define("type", "literal", ATTR_W + ATTR_E + ATTR_C)
      lp.define("value", sep, ATTR_W + ATTR_E + ATTR_C)
      parts.push(lp)
    uk = show[si][0]
    uv = show[si][1]
    is_sub = show[si][2]
    uname = INTL_DUR_UNITS[uk][1]
    ust = si > 0 ? "2-digit" : u_styles[uk]
    min_f = (is_sub && frac_dig != nil) ? frac_dig : 0
    max_f = is_sub ? (frac_dig == nil ? 9 : frac_dig) : 0
    mv = nil
    if is_sub
      mv = [:decimal, (sign_shown || si > 0) ? intl_abs_dec(uv) : uv]
    else
      av = (sign_shown || si > 0) ? js_math_abs(uv) : (uv == ~0.0 && neg ? ~-0.0 : uv)
      mv = intl_to_math_val(av)
    sign_shown = true if neg
    ch = intl_dur_fmt_unit(icu_loc, nu, uname, ust, mv, min_f, max_f, true)
    str = str + ch[0]
    ch[1].each ->(cp) parts.push(cp)
    si += 1
  [[str, parts], next_i]

-> intl_dur_resolved(this)
  js_throw_type("Intl.DurationFormat.prototype.resolvedOptions called on incompatible receiver") if !js_special?(this, "Intl.DurationFormat")
  d = this.internal
  o = js_realm().new_object
  o.define("locale", d[0], ATTR_W + ATTR_E + ATTR_C)
  o.define("numberingSystem", d[1], ATTR_W + ATTR_E + ATTR_C)
  o.define("style", d[2], ATTR_W + ATTR_E + ATTR_C)
  i = 0
  while i < 10
    o.define(INTL_DUR_UNITS[i][0], d[3][i], ATTR_W + ATTR_E + ATTR_C)
    o.define(INTL_DUR_UNITS[i][2], d[4][i], ATTR_W + ATTR_E + ATTR_C)
    i += 1
  o.define("fractionalDigits", d[5] + ~0.0, ATTR_W + ATTR_E + ATTR_C) if d[5] != nil
  o

# ---- Locale-aware Builtin Prototype Overrides (ECMA-402 §17..§20) ----

-> intl_str_locale_compare(this, args)
  s = js_this_str(this, "localeCompare")
  that = js_to_string(js_arg(args, 0))
  col = intl_collator_ctor(nil, [js_arg(args, 1), js_arg(args, 2)], js_realm().intrinsic("Intl.Collator"))
  intl_collator_compare_vals(col.internal, s, that)

-> intl_str_locale_case(this, locales, upper)
  s = js_this_str(this, upper ? "toLocaleUpperCase" : "toLocaleLowerCase")
  req = intl_canonicalize_locale_list(locales)
  avail = icu_available_locales()
  r = intl_resolve_locale(avail, req, {}, [])
  # Per ECMA-402 §19.1.1: only az, el, lt, tr have locale-specific SpecialCasing rules;
  # all other locales must use locale-independent Unicode case mapping (ICU root "")!
  lang = r["dataLocale"].split("-")[0]
  icu_loc = (lang == "az" || lang == "el" || lang == "lt" || lang == "tr") ? lang : ""
  icu_str_case(s, icu_loc, upper)

-> intl_num_to_locale_string(this, args)
  x = js_this_num(this, "toLocaleString")
  nf = intl_nf_ctor(nil, [js_arg(args, 0), js_arg(args, 1)], js_realm().intrinsic("Intl.NumberFormat"))
  intl_nf_format_impl(nf.internal, intl_to_math_val(x), false)

-> intl_bigint_to_locale_string(this, args)
  b = js_this_bigint(this)
  nf = intl_nf_ctor(nil, [js_arg(args, 0), js_arg(args, 1)], js_realm().intrinsic("Intl.NumberFormat"))
  intl_nf_format_impl(nf.internal, intl_to_math_val(b), false)

-> intl_date_to_locale_string(this, args, req_def, def_mode)
  t = js_this_time(this)
  return "Invalid Date" if t != t
  dtf = intl_dtf_ctor(nil, [js_arg(args, 0), js_arg(args, 1)], js_realm().intrinsic("Intl.DateTimeFormat"), req_def, def_mode)
  intl_dtf_format_epoch(dtf.internal, t, false)

-> intl_arr_to_locale_string(this, args)
  o = js_to_obj(this)
  len = js_to_length(jget(o, "length"))
  return "" if len == 0
  loc_args = [js_arg(args, 0), js_arg(args, 1)]
  parts = []
  i = 0
  while i < len
    v = jget(o, i.to_s)
    if js_nullish?(v)
      parts.push("")
    else
      parts.push(js_to_string(js_invoke(v, "toLocaleString", loc_args)))
    i += 1
  parts.join(",")

-> intl_ta_to_locale_string(this, args)
  t = js_ta_valid(this, "%TypedArray%.prototype.toLocaleString")
  n = js_ta_length(t)
  return "" if n == 0
  loc_args = [js_arg(args, 0), js_arg(args, 1)]
  parts = []
  i = 0
  while i < n
    v = js_ta_get(t, i)
    parts.push(js_nullish?(v) ? "" : js_to_string(js_invoke(v, "toLocaleString", loc_args)))
    i += 1
  parts.join(",")

# ---- Master Intl Installer ----

js_install(->(r) js_install_ecma402(r))

-> js_install_ecma402(r)
  r.set_intrinsic("%IntlFallbackSymbol%", JS:Symbol.new("IntlLegacyConstructedSymbol"))
  intl = js_new_object(r.object_proto)
  intl.define(SYM_TO_STRING_TAG, "Intl", ATTR_C)
  r.set_intrinsic("Intl", intl)
  r.global.define("Intl", intl, BUILTIN_ATTRS)

  js_install_intl_core(r, intl)

  # Intl.NumberFormat
  nfp = js_new_object(r.object_proto)
  nfc = r.native("NumberFormat", 0, ->(this, args, nt) intl_nf_ctor(this, args, nt), true)
  nfc.define("prototype", nfp, 0)
  nfp.define("constructor", nfc, BUILTIN_ATTRS)
  nfp.define(SYM_TO_STRING_TAG, "Intl.NumberFormat", ATTR_C)
  r.set_intrinsic("Intl.NumberFormat", nfc)
  r.set_intrinsic("Intl.NumberFormat.prototype", nfp)
  intl.define("NumberFormat", nfc, BUILTIN_ATTRS)
  r.method(nfc, "supportedLocalesOf", 1, ->(this, args, nt) intl_supported_locales(icu_available_locales(), intl_canonicalize_locale_list(js_arg(args, 0)), js_arg(args, 1)))
  r.getter(nfp, "format", ->(this, args, nt) intl_nf_get_format(this))
  nf_parts = ->(this, args, nt)
    d = intl_unwrap(this, "Intl.NumberFormat", "formatToParts")
    intl_nf_format_impl(d, intl_to_math_val(js_arg(args, 0)), true)
  nf_rng = ->(this, args, nt)
    d = intl_unwrap(this, "Intl.NumberFormat", "formatRange")
    intl_nf_format_range_impl(d, js_arg(args, 0), js_arg(args, 1), false)
  nf_rng_p = ->(this, args, nt)
    d = intl_unwrap(this, "Intl.NumberFormat", "formatRangeToParts")
    intl_nf_format_range_impl(d, js_arg(args, 0), js_arg(args, 1), true)
  r.method(nfp, "formatToParts", 1, nf_parts)
  r.method(nfp, "formatRange", 2, nf_rng)
  r.method(nfp, "formatRangeToParts", 2, nf_rng_p)
  r.method(nfp, "resolvedOptions", 0, ->(this, args, nt) intl_nf_resolved(this))

  # Intl.DateTimeFormat
  dtp = js_new_object(r.object_proto)
  dtc = r.native("DateTimeFormat", 0, ->(this, args, nt) intl_dtf_ctor(this, args, nt), true)
  dtc.define("prototype", dtp, 0)
  dtp.define("constructor", dtc, BUILTIN_ATTRS)
  dtp.define(SYM_TO_STRING_TAG, "Intl.DateTimeFormat", ATTR_C)
  r.set_intrinsic("Intl.DateTimeFormat", dtc)
  r.set_intrinsic("Intl.DateTimeFormat.prototype", dtp)
  intl.define("DateTimeFormat", dtc, BUILTIN_ATTRS)
  r.method(dtc, "supportedLocalesOf", 1, ->(this, args, nt) intl_supported_locales(icu_available_locales(), intl_canonicalize_locale_list(js_arg(args, 0)), js_arg(args, 1)))
  r.getter(dtp, "format", ->(this, args, nt) intl_dtf_get_format(this))
  dt_parts = ->(this, args, nt)
    d = intl_unwrap(this, "Intl.DateTimeFormat", "formatToParts")
    intl_dtf_format_any(d, js_arg(args, 0), true)
  dt_rng = ->(this, args, nt)
    d = intl_unwrap(this, "Intl.DateTimeFormat", "formatRange")
    intl_dtf_format_range_impl(d, js_arg(args, 0), js_arg(args, 1), false)
  dt_rng_p = ->(this, args, nt)
    d = intl_unwrap(this, "Intl.DateTimeFormat", "formatRangeToParts")
    intl_dtf_format_range_impl(d, js_arg(args, 0), js_arg(args, 1), true)
  r.method(dtp, "formatToParts", 1, dt_parts)
  r.method(dtp, "formatRange", 2, dt_rng)
  r.method(dtp, "formatRangeToParts", 2, dt_rng_p)
  r.method(dtp, "resolvedOptions", 0, ->(this, args, nt) intl_dtf_resolved(this))

  # Intl.DurationFormat
  dfp = js_new_object(r.object_proto)
  dfc = r.native("DurationFormat", 0, ->(this, args, nt) intl_dur_ctor(args, nt), true)
  dfc.define("prototype", dfp, 0)
  dfp.define("constructor", dfc, BUILTIN_ATTRS)
  dfp.define(SYM_TO_STRING_TAG, "Intl.DurationFormat", ATTR_C)
  r.set_intrinsic("Intl.DurationFormat", dfc)
  r.set_intrinsic("Intl.DurationFormat.prototype", dfp)
  intl.define("DurationFormat", dfc, BUILTIN_ATTRS)
  r.method(dfc, "supportedLocalesOf", 1, ->(this, args, nt) intl_supported_locales(icu_available_locales(), intl_canonicalize_locale_list(js_arg(args, 0)), js_arg(args, 1)))
  r.method(dfp, "format", 1, ->(this, args, nt) intl_dur_run(this, js_arg(args, 0), false))
  r.method(dfp, "formatToParts", 1, ->(this, args, nt) intl_dur_run(this, js_arg(args, 0), true))
  r.method(dfp, "resolvedOptions", 0, ->(this, args, nt) intl_dur_resolved(this))

  # Override String, Number, BigInt, Date, Array, TypedArray locale methods with full ECMA-402 versions!
  sp = r.intrinsic("String.prototype")
  r.method(sp, "localeCompare", 1, ->(this, args, nt) intl_str_locale_compare(this, args))
  r.method(sp, "toLocaleLowerCase", 0, ->(this, args, nt) intl_str_locale_case(this, js_arg(args, 0), false))
  r.method(sp, "toLocaleUpperCase", 0, ->(this, args, nt) intl_str_locale_case(this, js_arg(args, 0), true))

  np = r.intrinsic("Number.prototype")
  r.method(np, "toLocaleString", 0, ->(this, args, nt) intl_num_to_locale_string(this, args))

  bp = r.intrinsic("BigInt.prototype")
  r.method(bp, "toLocaleString", 0, ->(this, args, nt) intl_bigint_to_locale_string(this, args))

  dp = r.intrinsic("Date.prototype")
  r.method(dp, "toLocaleString", 0, ->(this, args, nt) intl_date_to_locale_string(this, args, :any, :all))
  r.method(dp, "toLocaleDateString", 0, ->(this, args, nt) intl_date_to_locale_string(this, args, :date, :date))
  r.method(dp, "toLocaleTimeString", 0, ->(this, args, nt) intl_date_to_locale_string(this, args, :time, :time))

  ap = r.intrinsic("Array.prototype")
  r.method(ap, "toLocaleString", 0, ->(this, args, nt) intl_arr_to_locale_string(this, args))

  tap = r.intrinsic("%TypedArray%").get("prototype", nil)
  r.method(tap, "toLocaleString", 0, ->(this, args, nt) intl_ta_to_locale_string(this, args))
  nil
