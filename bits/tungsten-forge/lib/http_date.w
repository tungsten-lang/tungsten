# Forge::HttpDate — HTTP-date parsing and formatting (RFC 7231 §7.1.1.1).
#
# An HTTP-date is the timestamp format used by Date, Last-Modified,
# If-Modified-Since, If-Unmodified-Since, Expires, Retry-After (date form)
# and the Expires attribute of a Set-Cookie. Before this file Forge could
# neither read nor write one: a handler could copy an opaque date string
# around, but nothing could compare two dates, decide whether a resource
# had changed since a client last saw it, or stamp a fresh Date header —
# so conditional requests (304 Not Modified) were impossible. It is the
# time counterpart to the ByteRange / Negotiation / Forwarded parsers, and
# the engine lib/conditional.w builds RFC 7232 preconditions on top of.
#
# RFC 7231 requires a recipient to accept all THREE historical formats and
# a sender to emit only the first:
#
#   IMF-fixdate   "Sun, 06 Nov 1994 08:49:37 GMT"    the modern, preferred
#   RFC 850       "Sunday, 06-Nov-94 08:49:37 GMT"   obsolete (2-digit year)
#   asctime()     "Sun Nov  6 08:49:37 1994"         obsolete (no time zone)
#
# All three name the SAME instant, so parsing is lossy only in the sense
# that it discards the day-of-week (which is redundant) and the source
# format. Every HTTP-date is GMT/UTC by definition, so there is no zone to
# track — .parse yields plain seconds since the Unix epoch (1970-01-01
# 00:00:00 GMT), a signed Integer that sorts and compares directly.
#
# Two entry points, each pure (no clock, no I/O) so both are testable
# under the interpreter and compiled:
#
#   .parse(value)  — any of the three formats -> epoch seconds, or nil.
#   .format(epoch) — epoch seconds -> a fresh IMF-fixdate string (the one
#                    form a server is allowed to send). Assumes epoch >= 0
#                    (the whole HTTP era is post-1970); nil otherwise.
#
# The Y/M/D <-> day-count conversions are Howard Hinnant's civil-calendar
# algorithms (days_from_civil / civil_from_days), exact for the proleptic
# Gregorian calendar with no lookup tables. They assume a non-negative
# year, which every HTTP-date satisfies (RFC 850's 2-digit year expands
# into 1970-2069 per the RFC 6265 §5.1.1 rule; the other two carry a
# 4-digit year).
#
# NOTE: no `&.` / safe-navigation and no early-return-from-inside-a-block
# below, mirroring request.w / byte_range.w / forwarded.w — the
# self-hosted interpreter implements neither. Numeric fields are validated
# digit-by-digit because String#to_i silently yields 0 for non-numeric
# text, and a malformed date must parse to nil (ignore the header), never
# to a bogus instant.

+ HttpDate
  # --- Parsing ---

  # Parse an HTTP-date in any RFC 7231 format into seconds since the Unix
  # epoch, or nil when the value is absent, empty, or not a well-formed
  # HTTP-date. The day-of-week token is not cross-checked against the date
  # (RFC 7231 permits, but does not require, that check).
  -> .parse(value)
    return nil if value == nil
    s = value.strip
    return nil if s.empty?
    toks = self.tokens(s)
    n = toks.size
    if self.ends_with?(toks[0], ",")
      # A day-name followed by "," is IMF-fixdate or RFC 850. They differ
      # in the date field: IMF spaces it ("06 Nov 1994"), RFC 850 dashes
      # it into one token ("06-Nov-94").
      if n >= 4 && toks[1].index("-") != nil
        self.from_rfc850(toks)
      elsif n >= 6
        self.from_imf(toks)
      else
        nil
    elsif n >= 5
      self.from_asctime(toks)
    else
      nil

  # "Sun, 06 Nov 1994 08:49:37 GMT"
  -> .from_imf(toks)
    day  = self.to_int(toks[1])
    mon  = self.month_num(toks[2])
    year = self.to_int(toks[3])
    time = self.parse_time(toks[4])
    return nil if day == nil || mon == nil || year == nil || time == nil
    return nil unless self.gmt?(toks[5])
    self.compose(year, mon, day, time)

  # "Sunday, 06-Nov-94 08:49:37 GMT"
  -> .from_rfc850(toks)
    date = toks[1].split("-")
    return nil unless date.size == 3
    day  = self.to_int(date[0])
    mon  = self.month_num(date[1])
    yy   = self.to_int(date[2])
    time = self.parse_time(toks[2])
    return nil if day == nil || mon == nil || yy == nil || time == nil
    return nil unless self.gmt?(toks[3])
    self.compose(self.expand_year(yy), mon, day, time)

  # "Sun Nov  6 08:49:37 1994" — no zone (GMT is implied).
  -> .from_asctime(toks)
    mon  = self.month_num(toks[1])
    day  = self.to_int(toks[2])
    time = self.parse_time(toks[3])
    year = self.to_int(toks[4])
    return nil if mon == nil || day == nil || time == nil || year == nil
    self.compose(year, mon, day, time)

  # Validate the calendar fields and fold them, with the parsed time, into
  # epoch seconds. Rejects an out-of-range month or day-of-month.
  -> .compose(year, mon, day, time)
    return nil unless mon >= 1 && mon <= 12
    return nil unless day >= 1 && day <= 31
    days = self.days_from_civil(year, mon, day)
    days * 86400 + time[:h] * 3600 + time[:m] * 60 + time[:s]

  # "hh:mm:ss" -> {h:, m:, s:} with range checks (leap second ss=60
  # tolerated), or nil.
  -> .parse_time(tok)
    parts = tok.split(":")
    return nil unless parts.size == 3
    h = self.to_int(parts[0])
    m = self.to_int(parts[1])
    s = self.to_int(parts[2])
    return nil if h == nil || m == nil || s == nil
    return nil unless h >= 0 && h <= 23
    return nil unless m >= 0 && m <= 59
    return nil unless s >= 0 && s <= 60
    {h: h, m: m, s: s}

  # Expand an RFC 850 two-digit year (RFC 6265 §5.1.1): 0-69 -> 2000-2069,
  # 70-99 -> 1970-1999. A value already >= 100 (a lenient 4-digit RFC 850
  # date) passes through unchanged.
  -> .expand_year(y)
    return y if y >= 100
    return y + 2000 if y <= 69
    y + 1900

  # True when the zone token names GMT/UTC. RFC 7231 fixes every HTTP-date
  # to GMT; a differently-named zone is malformed.
  -> .gmt?(zone)
    return false if zone == nil
    z = zone.upcase
    z == "GMT" || z == "UTC"

  # --- Formatting ---

  # Render epoch seconds as a fresh IMF-fixdate — the sole format a server
  # is permitted to send (RFC 7231 §7.1.1.1). nil for a nil or negative
  # epoch (the HTTP era is entirely post-1970).
  -> .format(epoch)
    return nil if epoch == nil
    return nil if epoch < 0
    days = epoch / 86400
    secs = epoch % 86400
    hh = secs / 3600
    mm = (secs % 3600) / 60
    ss = secs % 60
    civ = self.civil_from_days(days)
    wd = self.weekday_name(days)
    mn = self.month_name(civ[:m])
    "[wd], [self.pad2(civ[:d])] [mn] [civ[:y]] [self.pad2(hh)]:[self.pad2(mm)]:[self.pad2(ss)] GMT"

  # --- Civil-calendar arithmetic (Howard Hinnant; non-negative year) ---

  # Days from 1970-01-01 to the given proleptic-Gregorian date. Exact, no
  # tables. Negative for dates before the epoch.
  -> .days_from_civil(y, m, d)
    yy = y
    yy = yy - 1 if m <= 2
    era = yy / 400
    yoe = yy - era * 400
    mp = m + 9
    mp = m - 3 if m > 2
    doy = (153 * mp + 2) / 5 + d - 1
    doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    era * 146097 + doe - 719468

  # Inverse of days_from_civil: a non-negative day-count -> {y:, m:, d:}.
  -> .civil_from_days(z0)
    z = z0 + 719468
    era = z / 146097
    doe = z - era * 146097
    yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    y = yoe + era * 400
    doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    mp = (5 * doy + 2) / 153
    d = doy - (153 * mp + 2) / 5 + 1
    m = mp + 3
    m = mp - 9 if mp >= 10
    y = y + 1 if m <= 2
    {y: y, m: m, d: d}

  # Day-of-week name for a non-negative day-count. 1970-01-01 (day 0) is a
  # Thursday, so index (days + 4) mod 7 with 0 = Sunday.
  -> .weekday_name(days)
    case (days + 4) % 7
      0 => "Sun"
      1 => "Mon"
      2 => "Tue"
      3 => "Wed"
      4 => "Thu"
      5 => "Fri"
      => "Sat"

  # --- Small lexical helpers ---

  # Split on spaces, dropping the empty pieces a run of spaces produces
  # (asctime pads a single-digit day with a second space).
  -> .tokens(s)
    out = []
    s.split(" ").each -> (t)
      out.push(t) unless t.empty?
    out

  -> .ends_with?(s, suffix)
    n = s.size
    m = suffix.size
    return false if n < m
    s.slice(n - m, m) == suffix

  # A run of one-or-more ASCII digits as a non-negative Integer, or nil for
  # empty / non-digit text (String#to_i would silently yield 0).
  -> .to_int(s)
    return nil if s == nil || s.empty?
    i = 0
    n = s.size
    while i < n
      return nil if "0123456789".index(s.slice(i, 1)) == nil
      i += 1
    s.to_i

  -> .pad2(n)
    return "0" + n.to_s if n < 10
    n.to_s

  -> .month_num(name)
    return nil if name == nil || name.size != 3
    case name.downcase
      "jan" => 1
      "feb" => 2
      "mar" => 3
      "apr" => 4
      "may" => 5
      "jun" => 6
      "jul" => 7
      "aug" => 8
      "sep" => 9
      "oct" => 10
      "nov" => 11
      "dec" => 12
      => nil

  -> .month_name(m)
    case m
      1 => "Jan"
      2 => "Feb"
      3 => "Mar"
      4 => "Apr"
      5 => "May"
      6 => "Jun"
      7 => "Jul"
      8 => "Aug"
      9 => "Sep"
      10 => "Oct"
      11 => "Nov"
      => "Dec"
