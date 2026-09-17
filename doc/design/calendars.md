# Calendars, catch-up days, leap seconds, and location

Packed `Date` is a dumb civil tuple: year, month, day, hour, minute, second,
and a 15-minute UTC offset. Years −1024…3071 (12-bit field stored as
year+1024). The bit layout does not know
history. `Date.parse`, `Date.new`, and compiled literals decide which civil
tuples existed.

That is the right default for almost every program. Some civil dates and
clocks that people actually lived through are **not** proleptic Gregorian
UTC.

## Catch-up days

When a jurisdiction switched calendars it sometimes inserted extra days
instead of skipping them. Those days existed on the street even though they
are invalid in proleptic Gregorian:

| Date | Where | Why |
|------|--------|-----|
| 1712-02-30 | Sweden | Julian→Gregorian conversion gave February 30 (and 31 was planned, then dropped) |
| 1700-02-29, 1800-02-29, 1900-02-29 | Julian jurisdictions (Britain until 1752, Russia until 1918, …) | Century leap days that Gregorian rejects |

Tungsten accepts those dates in `Date.new` / `Date.parse` / date literals.
`2024-02-30` and `2100-02-29` are still rejected.

## Numbered days (`YYYY-DDD`)

`1867-250` is the 250th day of 1867 in **proleptic Gregorian**, resolved
to civil `Y-M-D` (the packed day field is only 5 bits, so the ordinal is
never stored raw). `Date.ordinal(year, n)` is the inverse of
`day_of_year`: `Date.ordinal(y, d.day_of_year) == d`. Samoa, Alaska, and
other local midnight walks live on `Date.in("Samoa").ordinal`.

Catch-up labels such as `1712-02-30` are valid civil tuples: fields,
`to_s`, equality, and `+ 0` work without a calendar. Neighbor-walking
(`+ 1`, weekday, ordinal, Julian day) raises `calendar context required`
until `Date.in("Sweden")` (or another jurisdiction) names the neighbors.

```
1712-02-29 + 1                         # 1712-03-01  (Gregorian)
1712-02-30 + 1                         # raise
Date.in("Sweden").parse("1712-02-29") + 1  # 1712-02-30
Date.in("Sweden").parse("1712-02-30") + 1  # 1712-03-01
```

## Leap seconds

Packed `sec` is 6 bits, so 60 fits. That is storage, not permission.

`Date.parse` / `Date.new` / datetime literals accept **second 60 only** as
the IERS positive UTC leap second: `23:59:60Z` on one of the 27 dates
1972-06-30 … 2016-12-31. Time-only `23:59:60` / `23:59:60Z` is the same
clock face. Everything else with `:60` is rejected (`2024-01-01T23:59:60`,
`2016-12-31T12:00:60`, `2016-12-31T23:59:60+01:00`).

How a *clock in a place* displays that instant is a location policy, not a
packed field:

| Policy | What the clock shows | Who |
|--------|----------------------|-----|
| UTC / IERS | `23:59:60` exists | What Tungsten stores |
| Smear | Never `:60`; seconds run slightly long (Google 24h noon-to-noon, AWS, UTC-SLS last 1000s, Bloomberg 2000s *after* midnight) | Cloud NTP |
| POSIX / Linux kernel default | No `:60`. At `00:00:00` UTC the clock steps back one second, so the first second of the new minute is repeated (duplicate timestamps). NTP historically froze `23:59:59` instead. | Most Unix |
| Ignore / slew | Clock runs through; one second fast until it slews back | `ntpd -x`, some Windows historically |
| Negative leap | Skip `23:59:59` (never issued) | — |

Smear vs step vs skip-the-next-second are not extra bits on Date. They
belong on `Date.in(jurisdiction)` once a timezone database exists.

## Timezone offset vs location

The packed tz field is 7 bits (128 codes). Linear codes are signed
quarter-hours (−16:00…+15:30). Spare codes that are not a real civil
15-minute offset are **singletons**. Code 63 is Amsterdam statutory
`+00:20`. Nepal `+05:45` is ordinary linear (345/15=23).

Paris `+00:09:21` and Amsterdam LMT `+00:19:32` are still not packed;
`Date.in("Amsterdam")` applies `+00:20` for 1937-05-01…1940-05-15.

### `Date.in`

Packed Date does not remember a place. `Date.in(name)` returns a
`Calendar` that validates cutovers and can attach a known offset:

```
Date.parse("1712-02-30")                      # catch-up, packed
Date.in("Sweden").parse("1712-02-30")         # ok
Date.in("London").parse("1712-02-30")         # invalid there
Date.in("Denmark").parse("1700-02-18")        # last Julian day
Date.in("Denmark").parse("1700-02-19")        # skipped
Date.in("Rome").parse("1582-10-04")           # Thursday; next civil day is the 15th
Date.in("Russia").parse("1918-01-31")         # last Julian day
Date.in("Russia").parse("1918-02-14")         # first Gregorian day
Date.in("Amsterdam").parse("1937-07-01T12:00:00")  # tz = 20
Date.parse("1937-07-01T12:00:00+00:20")       # packed singleton
```

| Calendar | Last old date | Next date | Notes |
|----------|---------------|-----------|--------|
| Catholic / Rome | 1582-10-04 | 1582-10-15 | skip 5–14 Oct (10 days) |
| Denmark–Norway | 1700-02-18 | 1700-03-01 | skip 19–29 Feb (11 days) |
| Sweden | 1700-02-28 | 1700-03-01 | skipped the leap day only |
| Sweden | 1712-02-30 | 1712-03-01 | extra day, back to Julian |
| Sweden | 1753-02-17 | 1753-03-01 | skip 18–28 Feb (11 days) |
| Britain | 1752-09-02 | 1752-09-14 | skip 3–13 Sep (11 days) |
| Russia | 1918-01-31 | 1918-02-14 | skip 1–13 Feb (13 days) |

Civil Russia has been Gregorian since 1918. The Russian Orthodox Church
still uses Julian (Christmas on 7 January). Julian did **not** ignore
leap days — it kept century leaps (1700/1800/1900), so the gap vs
Gregorian grew 10→11→12→13, then they jumped 13 days at once.

`Date.in` is not yet full IANA tzdata (DST folds, every LMT). It is the
jurisdiction layer. Do not grow a second Date type; attach place when
asked.

Skip ranges, extra days, and repeated midnights are one list on
`Calendar`. Local year length is the era leap length plus extras and
repeats minus the skip count from that list. WIT `?` and the Ruby
inspector read `Calendar.history_title` / `history_art`; they do not
keep a fourth copy of the cutovers.

Which calendar was in force depends on **where** and **when**:

- Italy/Spain: Gregorian from 1582-10-15
- Britain and colonies: 1752-09-14
- Sweden: messy 1700–1712, including 1712-02-30, then 1753
- Russia: civil Gregorian from 1918-02-14; church still Julian
- Julian leap years (1700, 1800, 1900) have 29 February; Gregorian does not
