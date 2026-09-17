# Date.in / Calendar: jurisdiction cutovers and Amsterdam +00:20.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

se = Date.in("Sweden")
dk = Date.in("Denmark")
gb = Date.in("Britain")
rome = Date.in("Rome")
ru = Date.in("Russia")
ams = Date.in("Amsterdam")

check("sweden 1712-02-30", se.parse("1712-02-30").day, 30)
sweden_leap = false
begin
  se.parse("1700-02-29")
rescue error
  sweden_leap = true
check("sweden rejects 1700 leap", sweden_leap, true)
check("sweden 1753-02-17", se.parse("1753-02-17").day, 17)
sweden_skip = false
begin
  se.parse("1753-02-18")
rescue error
  sweden_skip = true
check("sweden skips 1753-02-18", sweden_skip, true)
check("sweden 1753-03-01", se.parse("1753-03-01").month, 3)
check("sweden date() 1712-02-30", se.date(1712, 2, 30).day, 30)

check("denmark 1700-02-18", dk.parse("1700-02-18").day, 18)
dk_19 = false
begin
  dk.parse("1700-02-19")
rescue error
  dk_19 = true
check("denmark skips 1700-02-19", dk_19, true)
dk_29 = false
begin
  dk.parse("1700-02-29")
rescue error
  dk_29 = true
check("denmark skips 1700-02-29", dk_29, true)
check("denmark 1700-03-01", dk.parse("1700-03-01").month, 3)
check("denmark alias Norway", Date.in("Norway").parse("1700-02-18").day, 18)

check("britain 1752-09-02", gb.parse("1752-09-02").day, 2)
gb_skip = false
begin
  gb.parse("1752-09-03")
rescue error
  gb_skip = true
check("britain skips 1752-09-03", gb_skip, true)
check("britain 1752-09-14", gb.parse("1752-09-14").day, 14)
check("britain keeps 1700-02-29", gb.parse("1700-02-29").day, 29)

check("rome 1582-10-04", rome.parse("1582-10-04").day, 4)
rome_skip = false
begin
  rome.parse("1582-10-05")
rescue error
  rome_skip = true
check("rome skips 1582-10-05", rome_skip, true)
check("rome 1582-10-15", rome.parse("1582-10-15").day, 15)
rome_leap = false
begin
  rome.parse("1700-02-29")
rescue error
  rome_leap = true
check("rome rejects 1700-02-29", rome_leap, true)

check("russia 1918-01-31", ru.parse("1918-01-31").day, 31)
ru_skip = false
begin
  ru.parse("1918-02-01")
rescue error
  ru_skip = true
check("russia skips 1918-02-01", ru_skip, true)
check("russia 1918-02-14", ru.parse("1918-02-14").day, 14)
check("russia keeps 1900-02-29", ru.parse("1900-02-29").day, 29)
check("russia 2000-02-29 gregorian leap", ru.parse("2000-02-29").day, 29)

amt = ams.parse("1937-07-01T12:00:00")
check("amsterdam 1937 offset", amt.tz, 20)
check("amsterdam +00:20 literal", (1937-07-01T12:00:00+00:20).tz, 20)
check("amsterdam parse offset", Date.parse("1937-07-01T12:00:00+00:20").tz, 20)
check("amsterdam Date.new offset", Date.new(1937, 7, 1, 12, 0, 0, 20).tz, 20)
check("nepal still +05:45", Date.parse("2024-01-01T12:00:00+05:45").tz, 345)
check("amsterdam winter 1936 not amt", Date.in("Amsterdam").parse("1936-07-01T12:00:00").tz, 0)
check("amsterdam Z stays utc", Date.in("Amsterdam").parse("1938-01-01T12:00:00Z").tz, 0)
check("amsterdam naive gets +20", Date.in("Amsterdam").parse("1938-01-01T12:00:00").tz, 20)

samoa = Date.in("Samoa")
check("samoa local 364 is Dec 31 2011", samoa.ordinal(2011, 364), Date.new(2011, 12, 31))
samoa_365 = false
begin
  samoa.ordinal(2011, 365)
rescue error
  samoa_365 = true
check("samoa 2011 has 364 local midnights", samoa_365, true)
check("samoa skipped Dec 30", samoa.parse("2011-12-29") + 1, Date.parse("2011-12-31"))
check("samoa 1892 first July 4", samoa.ordinal(1892, 186), Date.new(1892, 7, 4))
check("samoa 1892 repeated July 4", samoa.ordinal(1892, 187), Date.new(1892, 7, 4))
check("samoa 1892 day after pair", samoa.ordinal(1892, 188), Date.new(1892, 7, 5))

ak = Date.in("Alaska")
check("alaska local 279 is Oct 6", ak.ordinal(1867, 279), Date.new(1867, 10, 6))
check("alaska local 280 is Oct 18", ak.ordinal(1867, 280), Date.new(1867, 10, 18))

gb1752 = Date.in("Britain").ordinal(1752, 355)
check("britain 1752 last local midnight", gb1752.month, 12)
check("britain 1752 last local day", gb1752.day, 31)

check("bare Date still accepts 1712-02-30", Date.parse("1712-02-30").day, 30)
check("bare Date still accepts 1700-02-29", Date.parse("1700-02-29").day, 29)

# Year length is derived from the one skip/extra/repeat list, not a
# parallel subtraction table.
check("samoa 2011 length", samoa.local_ordinal_len(2011), 364)
check("samoa 1892 length", samoa.local_ordinal_len(1892), 367)
check("sweden 1712 length", se.local_ordinal_len(1712), 367)
check("sweden 1700 length", se.local_ordinal_len(1700), 365)
check("sweden 1753 length", se.local_ordinal_len(1753), 354)
check("britain 1752 length", Date.in("Britain").local_ordinal_len(1752), 355)
check("denmark 1700 length", dk.local_ordinal_len(1700), 355)
check("rome 1582 length", rome.local_ordinal_len(1582), 355)
check("russia 1918 length", ru.local_ordinal_len(1918), 352)
check("alaska 1867 length", ak.local_ordinal_len(1867), 354)
check("philippines 1844 length", Date.in("Philippines").local_ordinal_len(1844), 365)
check("kwajalein 1993 length", Date.in("Kwajalein").local_ordinal_len(1993), 364)
check("sweden 1712 last midnight", se.ordinal(1712, 367), Date.new(1712, 12, 31))
check("sweden 1712 feb 30 ordinal", se.ordinal(1712, 61), Date.new(1712, 2, 30))
check("history tillokning", Calendar.history_title(1712, 2, 30), "tillökningsdagen")
check("history leap second", Calendar.history_title(2016, 12, 31, 60), "UTC leap second")
check("history ordinary empty", Calendar.history_title(2024, 1, 1), "")

<< "calendar_spec: all checks passed"
