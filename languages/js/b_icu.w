# runtime/b_icu — Pure-Tungsten bridge to Apple's system ICU 78.1 (/usr/lib/libicucore.A.dylib).
# Zero external dependencies: loaded lazily via w_dlopen/w_dlsym and invoked through
# inline LLVM IR C-ABI trampolines. Used by both ECMA-402 Intl (b_intl.w) and TC39 Temporal (b_temporal.w).

in JS

# ---- Low-level LLVM IR memory & C-ABI trampolines ----

fn icu_ba_ptr(ba_bits) (i64) i64
  ll <<~IR
    %p = and i64 %ba_bits, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 16
    %s = load i64, ptr %a, align 8
    ret i64 %s
  IR

fn icu_sext32(v) (i64) i64
  ll <<~IR
    %t = trunc i64 %v to i32
    %r = sext i32 %t to i64
    ret i64 %r
  IR

fn icu_load_u8(addr, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    %v = load i8, ptr %q, align 1
    %r = zext i8 %v to i64
    ret i64 %r
  IR

fn icu_load_u16(addr, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    %v = load i16, ptr %q, align 2
    %r = zext i16 %v to i64
    ret i64 %r
  IR

fn icu_load_i32(addr, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    %v = load i32, ptr %q, align 4
    %r = sext i32 %v to i64
    ret i64 %r
  IR

fn icu_load_i64(addr, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    %v = load i64, ptr %q, align 8
    ret i64 %v
  IR

fn icu_load_f64_bits(addr, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    %d = load double, ptr %q, align 8
    %n = fcmp uno double %d, %d
    %d2 = select i1 %n, double 0x7FF8000000000000, double %d
    %di = bitcast double %d2 to i64
    %r = add i64 %di, 281474976710656
    ret i64 %r
  IR

fn icu_store_i32(addr, off, val) (i64 i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    %v = trunc i64 %val to i32
    store i32 %v, ptr %q, align 4
    ret i64 0
  IR

fn icu_store_i64(addr, off, val) (i64 i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    store i64 %val, ptr %q, align 8
    ret i64 0
  IR

# Integer/pointer C-ABI call trampolines (0..8 args)
fn icu_c0(fp) (i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f()
    ret i64 %r
  IR

fn icu_c1(fp, a0) (i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0)
    ret i64 %r
  IR

fn icu_c2(fp, a0, a1) (i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1)
    ret i64 %r
  IR

fn icu_c3(fp, a0, a1, a2) (i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2)
    ret i64 %r
  IR

fn icu_c4(fp, a0, a1, a2, a3) (i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3)
    ret i64 %r
  IR

fn icu_c5(fp, a0, a1, a2, a3, a4) (i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4)
    ret i64 %r
  IR

fn icu_c6(fp, a0, a1, a2, a3, a4, a5) (i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5)
    ret i64 %r
  IR

fn icu_c7(fp, a0, a1, a2, a3, a4, a5, a6) (i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6)
    ret i64 %r
  IR

fn icu_c8(fp, a0, a1, a2, a3, a4, a5, a6, a7) (i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7)
    ret i64 %r
  IR

# Double-arg C-ABI call trampolines (ARM64 passes doubles in d0..d7; args take biased WValue bits)
fn icu_c_pdp(fp, p0, d1_bits, p2) (i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %di = sub i64 %d1_bits, 281474976710656
    %d = bitcast i64 %di to double
    %r = call i64 %f(i64 %p0, double %d, i64 %p2)
    ret i64 %r
  IR

fn icu_c_pdpp(fp, p0, d1_bits, p2, p3) (i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %di = sub i64 %d1_bits, 281474976710656
    %d = bitcast i64 %di to double
    %r = call i64 %f(i64 %p0, double %d, i64 %p2, i64 %p3)
    ret i64 %r
  IR

fn icu_c_pddpp(fp, p0, d1_bits, d2_bits, p3, p4) (i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %di1 = sub i64 %d1_bits, 281474976710656
    %d1 = bitcast i64 %di1 to double
    %di2 = sub i64 %d2_bits, 281474976710656
    %d2 = bitcast i64 %di2 to double
    %r = call i64 %f(i64 %p0, double %d1, double %d2, i64 %p3, i64 %p4)
    ret i64 %r
  IR

fn icu_c_pdipp(fp, p0, d1_bits, i2, p3, p4) (i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %di = sub i64 %d1_bits, 281474976710656
    %d = bitcast i64 %di to double
    %r = call i64 %f(i64 %p0, double %d, i64 %i2, i64 %p3, i64 %p4)
    ret i64 %r
  IR

fn icu_c_pdpip(fp, p0, d1_bits, p2, i3, p4) (i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %di = sub i64 %d1_bits, 281474976710656
    %d = bitcast i64 %di to double
    %r = call i64 %f(i64 %p0, double %d, i64 %p2, i64 %i3, i64 %p4)
    ret i64 %r
  IR

fn icu_c_pdpipp(fp, p0, d1_bits, p2, i3, p4, p5) (i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %di = sub i64 %d1_bits, 281474976710656
    %d = bitcast i64 %di to double
    %r = call i64 %f(i64 %p0, double %d, i64 %p2, i64 %i3, i64 %p4, i64 %p5)
    ret i64 %r
  IR

fn icu_c_pp_f64(fp, p0, p1) (i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %d = call double %f(i64 %p0, i64 %p1)
    %n = fcmp uno double %d, %d
    %d2 = select i1 %n, double 0x7FF8000000000000, double %d
    %di = bitcast double %d2 to i64
    %r = add i64 %di, 281474976710656
    ret i64 %r
  IR

# ---- Library handle & symbol cache ----

ICU_HANDLE = [0]
ICU_SYMS = {}
ICU_PIN = [nil, nil, nil, nil, nil, nil]

-> icu_pin(a, b = nil, c = nil, d = nil)
  ICU_PIN[0] = a
  ICU_PIN[1] = b
  ICU_PIN[2] = c
  ICU_PIN[3] = d
  nil

-> icu_init
  h = ICU_HANDLE[0]
  return h if h != 0
  h = ccall("w_dlopen", "/usr/lib/libicucore.A.dylib")
  raise "icu: failed to load /usr/lib/libicucore.A.dylib" if h == nil || h == 0
  ICU_HANDLE[0] = h
  h

-> icu_sym(name)
  fp = ICU_SYMS[name]
  return fp if fp != nil
  h = icu_init()
  p = ccall("w_dlsym", h, name)
  raise "icu: missing symbol " + name if p == nil || p == 0
  fp = p ## i64
  ICU_SYMS[name] = fp
  fp

# ---- Buffer & string conversion helpers ----

-> icu_ptr(ba)
  icu_ba_ptr(wvalue_bits(ba) ## i64)

-> icu_err_buf
  ba = ByteArray.new(8)
  ba

-> icu_err_reset(ba)
  icu_store_i32(icu_ptr(ba), 0, 0)
  ba.size
  nil

-> icu_err_code(ba)
  c = icu_load_i32(icu_ptr(ba), 0)
  ba.size
  c

-> icu_cstr(s)
  n = s.size
  ba = ByteArray.new(n + 1)
  i = 0
  while i < n
    ba[i] = s.byte_at(i)
    i += 1
  ba[n] = 0
  ba

-> icu_read_cstr_ptr(ptr)
  return nil if ptr == 0
  n = 0
  while icu_load_u8(ptr, n) != 0
    n += 1
  return "" if n == 0
  ba = ByteArray.new(n)
  i = 0
  while i < n
    ba[i] = icu_load_u8(ptr, i)
    i += 1
  ccall("w_string_from_byte_array", ba)

-> icu_read_cstr_ba(ba, len)
  return "" if len <= 0
  out = ByteArray.new(len)
  i = 0
  while i < len
    out[i] = ba[i]
    i += 1
  ccall("w_string_from_byte_array", out)

-> icu_to_u16(s)
  if s.ascii?
    n = s.size
    ba = ByteArray.new((n + 1) * 2)
    i = 0
    while i < n
      ba[i * 2] = s.byte_at(i)
      ba[i * 2 + 1] = 0
      i += 1
    ba[n * 2] = 0
    ba[n * 2 + 1] = 0
    return [ba, n]
  u = js_units(s)
  n = u.size
  ba = ByteArray.new((n + 1) * 2)
  i = 0
  while i < n
    c = u[i]
    ba[i * 2] = c & 255
    ba[i * 2 + 1] = (c >> 8) & 255
    i += 1
  ba[n * 2] = 0
  ba[n * 2 + 1] = 0
  [ba, n]

-> icu_from_u16_ptr(ptr, len)
  return "" if ptr == 0 || len <= 0
  ascii = true
  i = 0
  while i < len
    if icu_load_u16(ptr, i * 2) >= 128
      ascii = false
      break
    i += 1
  if ascii
    ba = ByteArray.new(len)
    i = 0
    while i < len
      ba[i] = icu_load_u16(ptr, i * 2)
      i += 1
    return ccall("w_string_from_byte_array", ba)
  u = Array.new(len, 0)
  i = 0
  while i < len
    u[i] = icu_load_u16(ptr, i * 2)
    i += 1
  js_from_units(u)

-> icu_from_u16_ba(ba, len)
  s = icu_from_u16_ptr(icu_ptr(ba), len)
  ba.size
  s

# ---- High-level ICU helpers ----

# Read and close an ICU UEnumeration* into an Array of Strings.
-> icu_read_enum(en)
  out = []
  return out if en == 0
  fn_next = icu_sym("uenum_next")
  fn_close = icu_sym("uenum_close")
  eb = icu_err_buf()
  lb = ByteArray.new(8)
  while true
    icu_err_reset(eb)
    p = icu_c3(fn_next, en, icu_ptr(lb), icu_ptr(eb))
    break if p == 0 || icu_err_code(eb) > 0
    ln = icu_load_i32(icu_ptr(lb), 0)
    if ln >= 0
      ba = ByteArray.new(ln)
      i = 0
      while i < ln
        ba[i] = icu_load_u8(p, i)
        i += 1
      out.push(ccall("w_string_from_byte_array", ba))
    else
      out.push(icu_read_cstr_ptr(p))
  icu_c1(fn_close, en)
  eb.size
  lb.size
  out

# Call a C-string-returning uloc_* function (src, dst, cap, &err) -> String or nil
-> icu_uloc_call(sym_name, loc)
  fn_p = icu_sym(sym_name)
  src = icu_cstr(loc)
  cap = 256
  dst = ByteArray.new(cap)
  eb = icu_err_buf()
  n = icu_sext32(icu_c4(fn_p, icu_ptr(src), icu_ptr(dst), cap, icu_ptr(eb)))
  ec = icu_err_code(eb)
  if ec == 15 && n > 0
    # U_BUFFER_OVERFLOW_ERROR = 15
    cap = n + 4
    dst = ByteArray.new(cap)
    icu_err_reset(eb)
    n = icu_sext32(icu_c4(fn_p, icu_ptr(src), icu_ptr(dst), cap, icu_ptr(eb)))
    ec = icu_err_code(eb)
  src.size
  eb.size
  return nil if ec > 0 || n < 0
  icu_read_cstr_ba(dst, n)

-> icu_for_language_tag(tag)
  fn_p = icu_sym("uloc_forLanguageTag")
  src = icu_cstr(tag)
  cap = 256
  dst = ByteArray.new(cap)
  pb = ByteArray.new(8)
  eb = icu_err_buf()
  n = icu_sext32(icu_c5(fn_p, icu_ptr(src), icu_ptr(dst), cap, icu_ptr(pb), icu_ptr(eb)))
  ec = icu_err_code(eb)
  if ec == 15 && n > 0
    cap = n + 4
    dst = ByteArray.new(cap)
    icu_err_reset(eb)
    n = icu_sext32(icu_c5(fn_p, icu_ptr(src), icu_ptr(dst), cap, icu_ptr(pb), icu_ptr(eb)))
    ec = icu_err_code(eb)
  parsed = icu_load_i32(icu_ptr(pb), 0)
  src.size
  pb.size
  eb.size
  return nil if ec > 0 || n < 0 || parsed != tag.size
  icu_read_cstr_ba(dst, n)

-> icu_to_language_tag(loc, strict = true)
  fn_p = icu_sym("uloc_toLanguageTag")
  src = icu_cstr(loc)
  cap = 256
  dst = ByteArray.new(cap)
  eb = icu_err_buf()
  n = icu_sext32(icu_c5(fn_p, icu_ptr(src), icu_ptr(dst), cap, strict ? 1 : 0, icu_ptr(eb)))
  ec = icu_err_code(eb)
  if ec == 15 && n > 0
    cap = n + 4
    dst = ByteArray.new(cap)
    icu_err_reset(eb)
    n = icu_sext32(icu_c5(fn_p, icu_ptr(src), icu_ptr(dst), cap, strict ? 1 : 0, icu_ptr(eb)))
    ec = icu_err_code(eb)
  src.size
  eb.size
  return nil if ec > 0 || n < 0
  icu_read_cstr_ba(dst, n)

-> icu_add_likely_subtags(loc)
  icu_uloc_call("uloc_addLikelySubtags", loc)

-> icu_minimize_subtags(loc)
  icu_uloc_call("uloc_minimizeSubtags", loc)

-> icu_canonicalize(loc)
  icu_uloc_call("uloc_canonicalize", loc)

-> icu_char_orientation(loc)
  fn_p = icu_sym("uloc_getCharacterOrientation")
  src = icu_cstr(loc)
  eb = icu_err_buf()
  r = icu_sext32(icu_c2(fn_p, icu_ptr(src), icu_ptr(eb)))
  src.size
  eb.size
  r == 1 ? "rtl" : "ltr"

-> icu_script_direction(sc)
  return nil if sc == nil || sc.size != 4
  return nil if sc == "Zyyy" || sc == "Zinh" || sc == "Zzzz" || sc == "Zxxx" || sc == "Brai"
  fn_enum = icu_sym("u_getPropertyValueEnum")
  fn_rtl = icu_sym("uscript_isRightToLeft")
  sb = icu_cstr(sc)
  # UCHAR_SCRIPT = 0x100A = 4106
  code = icu_sext32(icu_c2(fn_enum, 4106, icu_ptr(sb)))
  sb.size
  return nil if code < 0
  rtl = icu_c1(fn_rtl, code) & 255
  rtl != 0 ? "rtl" : "ltr"

-> icu_to_unicode_locale_type(k, v)
  fn_p = icu_sym("uloc_toUnicodeLocaleType")
  kb = icu_cstr(k)
  vb = icu_cstr(v)
  p = icu_c2(fn_p, icu_ptr(kb), icu_ptr(vb))
  kb.size
  vb.size
  return nil if p == 0
  icu_read_cstr_ptr(p)

ICU_AVAIL_LOCALES = [nil]

-> icu_available_locales
  return ICU_AVAIL_LOCALES[0] if ICU_AVAIL_LOCALES[0] != nil
  fn_cnt = icu_sym("uloc_countAvailable")
  fn_get = icu_sym("uloc_getAvailable")
  n = icu_sext32(icu_c0(fn_cnt))
  out = {}
  i = 0
  while i < n
    p = icu_c1(fn_get, i)
    loc = icu_read_cstr_ptr(p)
    if loc != nil && loc.size > 0
      tag = icu_to_language_tag(loc, false)
      if tag != nil && tag.size > 0 && tag != "und"
        out[tag] = true
        # Also register minimized form (e.g. zh-Hant-TW -> zh-TW, zh-Hans-CN -> zh-CN)
        mloc = icu_minimize_subtags(loc)
        if mloc != nil && mloc.size > 0 && mloc != loc
          mtag = icu_to_language_tag(mloc, false)
          out[mtag] = true if mtag != nil && mtag.size > 0 && mtag != "und"
    i += 1
  out["en"] = true
  out["en-US"] = true
  ICU_AVAIL_LOCALES[0] = out
  out

-> icu_default_locale
  env_loc = Env.get("LC_ALL", "")
  env_loc = Env.get("LC_CTYPE", "") if env_loc.size == 0
  env_loc = Env.get("LANG", "") if env_loc.size == 0
  if env_loc.size > 0 && env_loc != "C" && env_loc != "POSIX"
    dot = env_loc.index(".")
    base = dot == nil ? env_loc : env_loc.slice(0, dot)
    at = base.index("@")
    base = base.slice(0, at) if at != nil
    if base.size > 0 && base != "C" && base != "POSIX"
      tag = icu_to_language_tag(base, false)
      return tag if tag != nil && tag.size > 0 && tag != "und"
  "en-US"

-> icu_default_timezone
  tz_env = Env.get("TZ", "")
  if tz_env.size > 0
    t = tz_env.starts_with?(":") ? tz_env.slice(1, tz_env.size - 1) : tz_env
    return "UTC" if t == "UTC" || t == "GMT" || t == "Etc/UTC" || t == "Etc/GMT" || t == "Z"
    iana = icu_iana_tz(t)
    return iana if iana != nil && iana.size > 0
  fn_p = icu_sym("ucal_getDefaultTimeZone")
  dst = ByteArray.new(256)
  eb = icu_err_buf()
  n = icu_sext32(icu_c3(fn_p, icu_ptr(dst), 128, icu_ptr(eb)))
  ec = icu_err_code(eb)
  eb.size
  if ec <= 0 && n > 0
    s = icu_from_u16_ba(dst, n)
    iana = icu_iana_tz(s)
    return iana if iana != nil && iana.size > 0
    return s
  "UTC"

# Returns [canonical_id, is_system_bool] or nil
-> icu_canonical_tz(id)
  fn_p = icu_sym("ucal_getCanonicalTimeZoneID")
  u = icu_to_u16(id)
  ba = u[0]
  ulen = u[1]
  dst = ByteArray.new(256)
  sb = ByteArray.new(8)
  eb = icu_err_buf()
  n = icu_sext32(icu_c6(fn_p, icu_ptr(ba), ulen, icu_ptr(dst), 128, icu_ptr(sb), icu_ptr(eb)))
  ec = icu_err_code(eb)
  is_sys = sb.byte_at(0) != 0
  ba.size
  sb.size
  eb.size
  return nil if ec > 0 || n <= 0
  [icu_from_u16_ba(dst, n), is_sys]

-> icu_iana_tz(id)
  fn_p = icu_sym("ucal_getIanaTimeZoneID")
  u = icu_to_u16(id)
  ba = u[0]
  ulen = u[1]
  dst = ByteArray.new(256)
  eb = icu_err_buf()
  n = icu_sext32(icu_c5(fn_p, icu_ptr(ba), ulen, icu_ptr(dst), 128, icu_ptr(eb)))
  ec = icu_err_code(eb)
  ba.size
  eb.size
  return nil if ec > 0 || n <= 0
  s = icu_from_u16_ba(dst, n)
  return nil if s == "Etc/Unknown"
  s

-> icu_all_timezones(zone_type = 1)
  fn_p = icu_sym("ucal_openTimeZoneIDEnumeration")
  eb = icu_err_buf()
  en = icu_c4(fn_p, zone_type, 0, 0, icu_ptr(eb))
  ec = icu_err_code(eb)
  eb.size
  return [] if ec > 0 || en == 0
  icu_read_enum(en)

-> icu_keyword_values(fn_name, key, loc, common_only)
  fn_p = icu_sym(fn_name)
  kb = icu_cstr(key)
  lb = icu_cstr(loc)
  eb = icu_err_buf()
  en = icu_c4(fn_p, icu_ptr(kb), icu_ptr(lb), common_only ? 1 : 0, icu_ptr(eb))
  ec = icu_err_code(eb)
  kb.size
  lb.size
  eb.size
  return [] if ec > 0 || en == 0
  icu_read_enum(en)

-> icu_available_calendars(loc = "und", common_only = false)
  icu_keyword_values("ucal_getKeywordValuesForLocale", "calendar", loc, common_only)

-> icu_available_collations(loc = "und", common_only = false)
  icu_keyword_values("ucol_getKeywordValuesForLocale", "collation", loc, common_only)

-> icu_all_collations
  fn_p = icu_sym("ucol_getKeywordValues")
  kb = icu_cstr("collation")
  eb = icu_err_buf()
  en = icu_c2(fn_p, icu_ptr(kb), icu_ptr(eb))
  ec = icu_err_code(eb)
  kb.size
  eb.size
  return [] if ec > 0 || en == 0
  icu_read_enum(en)

-> icu_available_numbering_systems
  fn_p = icu_sym("unumsys_openAvailableNames")
  fn_open = icu_sym("unumsys_openByName")
  fn_alg = icu_sym("unumsys_isAlgorithmic")
  fn_close = icu_sym("unumsys_close")
  eb = icu_err_buf()
  en = icu_c1(fn_p, icu_ptr(eb))
  ec = icu_err_code(eb)
  return [] if ec > 0 || en == 0
  raw = icu_read_enum(en)
  out = []
  i = 0
  while i < raw.size
    nm = raw[i]
    nb = icu_cstr(nm)
    icu_err_reset(eb)
    ns = icu_c2(fn_open, icu_ptr(nb), icu_ptr(eb))
    nb.size
    if ns != 0
      alg = icu_c1(fn_alg, ns) != 0
      icu_c1(fn_close, ns)
      out.push(nm) if !alg
    i += 1
  eb.size
  out

-> icu_available_currencies
  fn_p = icu_sym("ucurr_openISOCurrencies")
  eb = icu_err_buf()
  # UCURR_ALL = 0 (includes all ISO 4217 currencies accepted by DisplayNames!)
  en = icu_c2(fn_p, 0, icu_ptr(eb))
  ec = icu_err_code(eb)
  eb.size
  return [] if ec > 0 || en == 0
  icu_read_enum(en)

-> icu_currency_digits(code)
  fn_p = icu_sym("ucurr_getDefaultFractionDigits")
  u = icu_to_u16(code)
  ba = u[0]
  eb = icu_err_buf()
  d = icu_sext32(icu_c2(fn_p, icu_ptr(ba), icu_ptr(eb)))
  ec = icu_err_code(eb)
  ba.size
  eb.size
  ec > 0 ? 2 : d

# Extract string and field positions from a const UFormattedValue*.
# Returns [str, parts] where parts is Array of [category, field, start_u16, limit_u16].
-> icu_fmtval_extract(fv, cat_filter = -1)
  fn_str = icu_sym("ufmtval_getString")
  fn_next = icu_sym("ufmtval_nextPosition")
  fn_open = icu_sym("ucfpos_open")
  fn_close = icu_sym("ucfpos_close")
  fn_cat = icu_sym("ucfpos_getCategory")
  fn_fld = icu_sym("ucfpos_getField")
  fn_idx = icu_sym("ucfpos_getIndexes")
  fn_con = icu_sym("ucfpos_constrainCategory")
  eb = icu_err_buf()
  lb = ByteArray.new(8)
  sptr = icu_c3(fn_str, fv, icu_ptr(lb), icu_ptr(eb))
  slen = icu_load_i32(icu_ptr(lb), 0)
  str = icu_from_u16_ptr(sptr, slen)
  parts = []
  icu_err_reset(eb)
  fp = icu_c1(fn_open, icu_ptr(eb))
  if fp != 0 && icu_err_code(eb) <= 0
    if cat_filter >= 0
      icu_c3(fn_con, fp, cat_filter, icu_ptr(eb))
    sb = ByteArray.new(8)
    eb2 = ByteArray.new(8)
    while true
      icu_err_reset(eb)
      ok = icu_c3(fn_next, fv, fp, icu_ptr(eb))
      break if ok == 0 || icu_err_code(eb) > 0
      cat = icu_sext32(icu_c2(fn_cat, fp, icu_ptr(eb)))
      fld = icu_sext32(icu_c2(fn_fld, fp, icu_ptr(eb)))
      icu_c4(fn_idx, fp, icu_ptr(sb), icu_ptr(eb2), icu_ptr(eb))
      st = icu_load_i32(icu_ptr(sb), 0)
      lm = icu_load_i32(icu_ptr(eb2), 0)
      parts.push([cat, fld, st, lm])
    sb.size
    eb2.size
    icu_c1(fn_close, fp)
  lb.size
  eb.size
  [str, parts]

-> icu_str_case(s, loc, upper)
  return "" if s.size == 0
  fn_p = icu_sym(upper ? "u_strToUpper" : "u_strToLower")
  u = icu_to_u16(s)
  src = u[0]
  slen = u[1]
  lb = icu_cstr(loc)
  cap = slen * 2 + 16
  dst = ByteArray.new(cap * 2)
  eb = icu_err_buf()
  n = icu_sext32(icu_c6(fn_p, icu_ptr(dst), cap, icu_ptr(src), slen, icu_ptr(lb), icu_ptr(eb)))
  ec = icu_err_code(eb)
  if ec == 15 && n > 0
    cap = n + 4
    dst = ByteArray.new(cap * 2)
    icu_err_reset(eb)
    n = icu_sext32(icu_c6(fn_p, icu_ptr(dst), cap, icu_ptr(src), slen, icu_ptr(lb), icu_ptr(eb)))
    ec = icu_err_code(eb)
  src.size
  lb.size
  eb.size
  return s if ec > 0 || n < 0
  icu_from_u16_ba(dst, n)
