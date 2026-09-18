# DateScene — the `? date` inspection scene, shared by every host.
#
# The compiled REPL (compiler/lib/repl.w) calls this natively and the Ruby
# REPL evaluates it through its interpreter, so holiday names, artwork,
# the season rail, and the calendar grid are written once. Everything here
# is a pure function of civil fields (ints in, strings out): no Date value
# is required, which also keeps extra civil labels such as 1712-02-30
# renderable (they continue the weekday/day-of-year sequence).
#
# Layout contract (80 columns): header line, subheader (holiday or history
# title, blank when neither so scrubbing keeps a constant line count), a
# blank, then the calendar with the art panel starting at column 42.
+ DateScene
  DAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
  MONTH_NAMES = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
  WEEKDAYS = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
  WIDTH = 80
  RIGHT_COLUMN = 42
  SEASON_SHIFT = 4
  CURRENT_DAY_COLOR = "97"

  # ---- text helpers ----------------------------------------------------

  -> .ansi(text, code)
    "\e\[" + code + "m" + text + "\e\[0m"

  -> .dim(text)
    DateScene.ansi(text, "2")

  # Visible width: ANSI sequences stripped, counted in characters.
  -> .vlen(s)
    out = ""
    i = 0
    n = s.size()
    while i < n
      c = s.slice(i, 1)
      if c == "\e"
        while i < n && s.slice(i, 1) != "m"
          i = i + 1
        i = i + 1
      else
        out = out + c
        i = i + 1
    out.chars().size()

  -> .pad(n)
    if n <= 0
      return ""
    " " * n

  -> .rstrip(s)
    n = s.size()
    while n > 0 && s.slice(n - 1, 1) == " "
      n = n - 1
    s.slice(0, n)

  -> .pad2(n)
    if n < 10
      return "0" + n.to_s()
    n.to_s()

  # Overwrite buf[col, len(text)] (ASCII-only buffer, so byte == column).
  -> .splice(buf, col, text)
    tl = text.size()
    buf.slice(0, col) + text + buf.slice(col + tl, buf.size() - (col + tl))

  -> .ordinal_suffix(day)
    m100 = day % 100
    if m100 >= 11 && m100 <= 13
      return "th"
    m10 = day % 10
    if m10 == 1
      return "st"
    if m10 == 2
      return "nd"
    if m10 == 3
      return "rd"
    "th"

  # Colour `text` per a parallel mask string (one mask char per CHARACTER of
  # text): r red, b blue, w white, y yellow, g green, m magenta, p pink,
  # o orange, c cyan, k brown, space = plain. Walks characters, not bytes,
  # so a colour change never splits a multi-byte glyph such as ♥.
  -> .paint(text, mask)
    cs = text.chars()
    n = cs.size()
    out = ""
    i = 0
    while i < n
      m = DateScene.mask_at(mask, i)
      j = i + 1
      while j < n && DateScene.mask_at(mask, j) == m
        j = j + 1
      seg = ""
      k = i
      while k < j
        seg = seg + cs[k]
        k = k + 1
      code = DateScene.mask_code(m)
      if code == ""
        out = out + seg
      else
        out = out + DateScene.ansi(seg, code)
      i = j
    out

  -> .mask_at(mask, i)
    if i >= mask.size()
      return " "
    mask.slice(i, 1)

  -> .mask_code(m)
    if m == "r"
      return "31"
    if m == "b"
      return "34"
    if m == "w"
      return "37"
    if m == "y"
      return "33"
    if m == "g"
      return "32"
    if m == "m"
      return "35"
    if m == "p"
      return "38;5;205"
    if m == "o"
      return "38;5;208"
    if m == "c"
      return "36"
    if m == "k"
      return "38;5;94"
    ""

  # ---- proleptic Gregorian calendar math ----------------------------------

  -> .leap?(y)
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0

  -> .days_in_month(y, m)
    if m == 2
      if DateScene.leap?(y)
        return 29
      return 28
    if m == 4 || m == 6 || m == 9 || m == 11
      return 30
    31

  -> .days_in_year(y)
    if DateScene.leap?(y)
      return 366
    365

  -> .jdn(y, m, d)
    a = ((14 - m) / 12) ## i64
    yy = (y + 4800 - a) ## i64
    mm = (m + 12 * a - 3) ## i64
    (d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045) ## i64

  # Julian day number → [year, month, day].
  -> .civil(jdn)
    a = (jdn + 32044) ## i64
    b = ((4 * a + 3) / 146097) ## i64
    c = (a - 146097 * b / 4) ## i64
    d = ((4 * c + 3) / 1461) ## i64
    e = (c - 1461 * d / 4) ## i64
    m = ((5 * e + 2) / 153) ## i64
    day = (e - (153 * m + 2) / 5 + 1) ## i64
    month = (m + 3 - 12 * (m / 10)) ## i64
    year = (100 * b + d - 4800 + m / 10) ## i64
    [year, month, day]

  # 0 = Sunday. Day 30 of February continues the sequence (Sweden 1712).
  -> .wday(y, m, d)
    (((DateScene.jdn(y, m, d) + 1) % 7) + 7) % 7

  -> .day_of_year(y, m, d)
    DateScene.jdn(y, m, d) - DateScene.jdn(y, 1, 1) + 1

  -> .iso_weeks_in_year(y)
    p = ((y + y / 4 - y / 100 + y / 400) % 7 + 7) % 7
    y1 = y - 1
    p1 = ((y1 + y1 / 4 - y1 / 100 + y1 / 400) % 7 + 7) % 7
    if p == 4 || p1 == 3
      return 53
    52

  # ISO 8601 week number (weeks start Monday; week 1 holds January 4).
  -> .iso_week(y, m, d)
    wd = DateScene.wday(y, m, d)
    iso_wd = wd
    if iso_wd == 0
      iso_wd = 7
    week = (DateScene.day_of_year(y, m, d) - iso_wd + 10) / 7
    if week < 1
      return DateScene.iso_weeks_in_year(y - 1)
    if week > DateScene.iso_weeks_in_year(y)
      return 1
    week

  # ---- seasons ---------------------------------------------------------

  -> .season_index(m, d)
    md = m * 100 + d
    if md >= 320 && md <= 620
      return 0
    if md >= 621 && md <= 921
      return 1
    if md >= 922 && md <= 1220
      return 2
    3

  -> .season_rail(idx)
    if idx == 0
      return "\[✿\] ☀  ☙  ❄"
    if idx == 1
      return "✿ \[☀\] ☙  ❄"
    if idx == 2
      return "✿  ☀ \[☙\] ❄"
    "✿  ☀  ☙ \[❄\]"

  # Equinox / solstice civil day for `year` (k: 0 March, 1 June, 2 September,
  # 3 December). Meeus, Astronomical Algorithms ch. 27, Table 27.B (valid
  # 1000–3000; used for every year — the error outside is well under a day).
  # Scaled integer arithmetic in units of 1e-5 day so no float is needed:
  # Y = (year − 2000) / 1000, JDE0 = c0 + c1·Y + c2·Y² + c3·Y³ + c4·Y⁴.
  # The result is the Julian day number of floor(JDE0 + 0.5) in civil terms.
  -> .solstice_day(year, k)
    dy = (year - 2000) ## i64
    d2 = (dy * dy) ## i64
    d3 = (d2 * dy) ## i64
    d4 = (d3 * dy) ## i64
    t = 0 ## i64
    if k == 0
      t = 245162380984 + 36524237404 * dy / 1000 + 5169 * d2 / 1000000 - 411 * d3 / 1000000000 - 57 * d4 / 1000000000000
    elsif k == 1
      t = 245171656767 + 36524162603 * dy / 1000 + 325 * d2 / 1000000 + 888 * d3 / 1000000000 - 30 * d4 / 1000000000000
    elsif k == 2
      t = 245181021715 + 36524201767 * dy / 1000 - 11575 * d2 / 1000000 + 337 * d3 / 1000000000 + 78 * d4 / 1000000000000
    else
      t = 245190005952 + 36524274049 * dy / 1000 - 6223 * d2 / 1000000 - 823 * d3 / 1000000000 + 32 * d4 / 1000000000000
    jd = ((t + 50000) / 100000) ## i64
    DateScene.civil(jd)

  -> .solstice_name(y, m, d)
    k = 0
    while k < 4
      ev = DateScene.solstice_day(y, k)
      if ev[1] == m && ev[2] == d
        if k == 0
          return "Spring Equinox"
        if k == 1
          return "Summer Solstice"
        if k == 2
          return "Autumn Equinox"
        return "Winter Solstice"
      k = k + 1
    ""

  # ---- holidays ----------------------------------------------------------

  -> .nth_weekday?(y, m, d, month, weekday, nth)
    m == month && DateScene.wday(y, m, d) == weekday && (d - 1) / 7 + 1 == nth

  -> .last_weekday?(y, m, d, month, weekday)
    m == month && DateScene.wday(y, m, d) == weekday && d + 7 > DateScene.days_in_month(y, m)

  # Anonymous Gregorian computus → [month, day].
  -> .easter(year)
    a = year % 19
    b = year / 100
    c = year % 100
    d = b / 4
    e = b % 4
    f = (b + 8) / 25
    g = (b - f + 1) / 3
    h = (19 * a + b - d - g + 15) % 30
    i = c / 4
    k = c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) / 451
    month = (h + l - 7 * m + 114) / 31
    day = (h + l - 7 * m + 114) % 31 + 1
    [month, day]

  -> .easter?(y, m, d)
    e = DateScene.easter(y)
    e[0] == m && e[1] == d

  # Holiday name for the subheader, or "" when the day has none. Fixed
  # dates first, then the floating US holidays, then the astronomical
  # season boundaries.
  -> .holiday_name(y, m, d)
    if m == 1 && d == 1
      return "New Year's Day"
    if m == 2 && d == 14
      return "Valentine's Day"
    if m == 2 && d == 29
      return "Leap Day"
    if m == 3 && d == 14
      return "Pi Day"
    if m == 3 && d == 17
      return "St. Patrick's Day"
    if m == 4 && d == 1
      return "April Fools' Day"
    if m == 6 && d == 19
      return "Juneteenth"
    if m == 7 && d == 4
      return "US Independence Day · Tungsten's Birthday"
    if m == 10 && d == 31
      return "Halloween"
    if m == 12 && d == 24
      return "Christmas Eve"
    if m == 12 && d == 25
      return "Christmas"
    if m == 12 && d == 31
      return "New Year's Eve"
    if DateScene.nth_weekday?(y, m, d, 1, 1, 3)
      return "Martin Luther King Jr. Day"
    if DateScene.easter?(y, m, d)
      return "Easter"
    if DateScene.last_weekday?(y, m, d, 5, 1)
      return "Memorial Day"
    if DateScene.nth_weekday?(y, m, d, 9, 1, 1)
      return "Labor Day"
    if DateScene.nth_weekday?(y, m, d, 11, 4, 4)
      return "Thanksgiving"
    DateScene.solstice_name(y, m, d)

  -> .holiday_art(y, m, d)
    if m == 12 && d == 25
      return DateScene.christmas_tree
    if m == 7 && d == 4
      return DateScene.fireworks_74
    if m == 10 && d == 31
      return DateScene.halloween_pumpkin
    if m == 3 && d == 17
      return DateScene.st_patricks
    if m == 2 && d == 14
      return DateScene.valentine_hearts
    if DateScene.nth_weekday?(y, m, d, 11, 4, 4)
      return DateScene.thanksgiving_turkey
    if DateScene.easter?(y, m, d)
      return DateScene.easter_bunny
    []

  # ---- artwork (≤ 38 columns; panel starts at column 42) --------------

  -> .christmas_tree
    g = "32"
    lights = DateScene.ansi(" o", "31") + "--" + DateScene.ansi("o", "33") + "--" + DateScene.ansi("o", "32") + "--" + DateScene.ansi("o", "36") + "--" + DateScene.ansi("o", "35") + "--" + DateScene.ansi("o", "31") + "--" + DateScene.ansi("o", "33") + "--" + DateScene.ansi("o", "32")
    [lights,
     "                         " + DateScene.ansi("*", "33"),
     "                        " + DateScene.ansi("/_\\", g),
     "                       " + DateScene.ansi("/_", g) + DateScene.ansi("o", "31") + DateScene.ansi("_\\", g),
     "                      " + DateScene.ansi("/_", g) + DateScene.ansi("o", "33") + DateScene.ansi("_", g) + DateScene.ansi("o", "31") + DateScene.ansi("_\\", g),
     "                     " + DateScene.ansi("/_", g) + DateScene.ansi("o", "31") + DateScene.ansi("_", g) + DateScene.ansi("o", "33") + DateScene.ansi("_", g) + DateScene.ansi("o", "36") + DateScene.ansi("_\\", g),
     "                    " + DateScene.ansi("/_________\\", g),
     "                        " + DateScene.ansi("|_|", "38;5;94")]

  # Fireworks bursting in the shape of 7 4: Tungsten's birthday.
  -> .fireworks_74
    [DateScene.paint("   .   *      *******     .   *   *  .", "   w   y      rrrrrrr     w   b   b  w"),
     DateScene.paint("  *     .          *     *    *   *  .", "  w     y          r     y    b   b  w"),
     DateScene.paint("     .    *       *     .     *****", "     w    w       r     w     bbbbb"),
     DateScene.paint("  *    .    *    *     *    .     *  *", "  y    w    w    r     w    y     b  w"),
     DateScene.paint("    .     .     *    *    .    *  *", "    w     y     r    y    w    w  b"),
     DateScene.paint("       *   .   *    .    *    .   *  .", "       w   w   r    w    y    w   b  y")]

  -> .halloween_pumpkin
    [DateScene.paint("                 _", "                 g"),
     DateScene.paint("            .-\"\"\"\"\"\"\"-.", "            ooooooooooo"),
     DateScene.paint("          .'  /\\   /\\  '.", "          oo  yy   yy  oo"),
     DateScene.paint("         /      /_\\      \\", "         o      yyy      o"),
     DateScene.paint("        |    \\_/\\_/\\_/    |", "        o    yyyyyyyyy    o"),
     DateScene.paint("         \\    '--v--'    /", "         o    yyyyyyy    o"),
     DateScene.paint("          '._         _.'", "          ooo         ooo"),
     DateScene.paint("             '-------'", "             ooooooooo")]

  -> .st_patricks
    g = "32"
    dg = "38;5;28"
    gold = "33"
    pot = "38;5;94"
    [
      " " + DateScene.ansi("~~~~", "31") + DateScene.ansi("~~~~", "38;5;208") + DateScene.ansi("~~~~", gold) + DateScene.ansi("~~~~", g) + DateScene.ansi("~~~~", "34") + DateScene.ansi("~~~~", "35"),
      "       " + DateScene.ansi("☘", g) + "             " + DateScene.ansi("☘", g),
      "          " + DateScene.ansi("☘", g) + "  " + DateScene.ansi("☘", g) + "  " + DateScene.ansi("☘", g),
      "            " + DateScene.ansi("\\ | /", dg),
      "       " + DateScene.ansi(".-======-.", pot) + "  " + DateScene.ansi("$", gold),
      "      " + DateScene.ansi("/", pot) + " " + DateScene.ansi("$ $ $ $", gold) + " " + DateScene.ansi("\\", pot),
      "      " + DateScene.ansi("\\________/", pot)
    ]

  -> .valentine_hearts
    [DateScene.paint("               ♥♥♥   ♥♥♥", "               ppp   rrr"),
     DateScene.paint("    .----.    ♥♥♥♥♥♥♥♥♥♥♥♥♥", "    wwwwww    pppppprrrrrrr"),
     DateScene.paint("    |love|     ♥♥♥♥♥♥♥♥♥♥♥", "    wwwwww     ppppprrrrrr"),
     DateScene.paint("    '----'      ♥♥♥♥♥♥♥♥♥", "    wwwwww      pppprrrrr"),
     DateScene.paint("                 ♥♥♥♥♥♥♥", "                 ppprrrr"),
     DateScene.paint("                  ♥♥♥♥♥", "                  pprrr"),
     DateScene.paint("                   ♥♥♥", "                   prr"),
     DateScene.paint("                    ♥", "                    r")]

  -> .easter_bunny
    p = "35"
    y = "33"
    c = "36"
    [
      "                    " + DateScene.ansi("(\\_/)", "37"),
      "                    " + DateScene.ansi("(o.o)", "37"),
      "                    " + DateScene.ansi("/ >🥕", "32"),
      "       " + DateScene.ansi(".-.", p) + "      " + DateScene.ansi(".-.", y) + "      " + DateScene.ansi(".-.", c),
      "      " + DateScene.ansi("/ ~ \\", p) + "    " + DateScene.ansi("/ ^ \\", y) + "    " + DateScene.ansi("/ * \\", c),
      "      " + DateScene.ansi("\\___/", p) + "    " + DateScene.ansi("\\___/", y) + "    " + DateScene.ansi("\\___/", c)
    ]

  -> .thanksgiving_turkey
    [DateScene.paint("  ^^^  ^^^        .-^-.", "  rrr  ooo        yyyyy"),
     DateScene.paint(" ^^^^^ ^^^^^   .-' \\|/ '-.", " ooooo yyyyy   ggg oyr mmm"),
     DateScene.paint("  ||    ||     .' \\ | / '.", "  kk    kk     rr o y r mm"),
     DateScene.paint("             --=  (o o)  =--", "             yyy  kkkkk  yyy"),
     DateScene.paint("                  \\ v /", "                  r r r"),
     DateScene.paint("                 /( : )\\", "                 kkkkkkk"),
     DateScene.paint("                   /|\\", "                   kkk"),
     DateScene.paint("                  /_|_\\", "                  kkkkk")]

  -> .calendar(y, m, d)
    lines = []
    hdr = " "
    wi = 0
    while wi < 7
      hdr = hdr + WEEKDAYS[wi]
      if wi < 6
        hdr = hdr + "   "
      wi = wi + 1
    lines.push(hdr)
    lines.push(" " + "-" * 33)
    dim = DateScene.days_in_month(y, m)
    if d > dim
      dim = d
    wd = DateScene.wday(y, m, 1)
    buf = " " * 34
    marked = -1
    day = 1
    while day <= dim
      col = 1 + wd * 5
      buf = DateScene.splice(buf, col, DateScene.pad2(day))
      if day == d
        buf = DateScene.splice(buf, col - 1, "\[")
        buf = DateScene.splice(buf, col + 2, "\]")
        marked = col - 1
      if wd == 6
        lines.push(DateScene.calendar_row(buf, marked))
        buf = " " * 34
        marked = -1
      day = day + 1
      wd = wd + 1
      if wd > 6
        wd = 0
    if DateScene.rstrip(buf).size() > 0
      lines.push(DateScene.calendar_row(buf, marked))
    # A 5-week month is one row shorter than a 6-week one (and than the
    # 8-line art); pad so the block keeps its height while scrubbing.
    if lines.size() == 7
      lines.push("")
    lines

  -> .calendar_row(buf, marked)
    row = DateScene.rstrip(buf)
    if marked < 0
      return row
    row.slice(0, marked) + DateScene.ansi(row.slice(marked, 4), CURRENT_DAY_COLOR) + row.slice(marked + 4, row.size() - (marked + 4))

  -> .header(y, m, d)
    wd = DateScene.wday(y, m, d)
    title = DAY_NAMES[wd] + ", " + MONTH_NAMES[m - 1] + " " + d.to_s() + DateScene.ordinal_suffix(d) + ", " + y.to_s()
    daywk = "\[Day " + DateScene.day_of_year(y, m, d).to_s() + "/" + DateScene.days_in_year(y).to_s() + "\] Week " + DateScene.iso_week(y, m, d).to_s()
    rail = DateScene.season_rail(DateScene.season_index(m, d))
    statscol = WIDTH - DateScene.vlen(daywk)
    seasoncol = (WIDTH - DateScene.vlen(rail)) / 2 + SEASON_SHIFT
    leftb = DateScene.vlen(title) + 2
    rightb = statscol - DateScene.vlen(rail) - 2
    if seasoncol < leftb
      seasoncol = leftb
    if seasoncol > rightb
      seasoncol = rightb
    line = title
    line = line + DateScene.pad(seasoncol - DateScene.vlen(line)) + rail
    line + DateScene.pad(statscol - DateScene.vlen(line)) + daywk

  # History (cutovers, leap seconds) outranks a holiday name.
  -> .subheader(y, m, d, second)
    title = Calendar.history_title(y, m, d, second)
    if title != ""
      return title
    DateScene.holiday_name(y, m, d)

  -> .right_panel(y, m, d, second)
    hist = Calendar.history_art(y, m, d, second)
    if hist.size() > 0
      out = []
      i = 0
      while i < hist.size()
        out.push(DateScene.dim(hist[i]))
        i = i + 1
      return out
    DateScene.holiday_art(y, m, d)

  -> .scene_columns(left, right)
    if right == ""
      return left
    left + DateScene.pad(RIGHT_COLUMN - DateScene.vlen(left)) + right

  # The full scene as lines: blank, header, subheader, blank, calendar +
  # art rows, blank.
  -> .scene(y, m, d, second)
    lines = [""]
    lines.push(DateScene.header(y, m, d))
    lines.push(DateScene.subheader(y, m, d, second))
    lines.push("")
    cal = DateScene.calendar(y, m, d)
    art = DateScene.right_panel(y, m, d, second)
    n = cal.size()
    if art.size() > n
      n = art.size()
    i = 0
    while i < n
      l = ""
      if i < cal.size()
        l = cal[i]
      r = ""
      if i < art.size()
        r = art[i]
      lines.push(DateScene.scene_columns(l, r))
      i = i + 1
    lines.push("")
    lines
