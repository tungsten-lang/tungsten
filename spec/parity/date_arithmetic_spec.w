# Dates: literals, duration arithmetic, month clamping, accessors,
# formatting, differences, parsing.
#
# Cross-engine parity spec (scripts/parity.sh).

d = 2024-01-15
<< "lit [d]"
<< "tos [d.to_s]"
<< "type [type(d)]"
<< "add.days [d + 210 days]"
<< "add.int [d + 210]"
<< "days.add [210 days + d]"
<< "sub.days [d - 30 days]"
<< "add.mo [d + 1mo]"
<< "clamp [2024-01-31 + 1mo]"
<< "strftime [d.strftime("%Y/%m/%d")]"
<< "tos.fmt [d.to_s("%d.%m.%Y")]"
<< "year [d.year] month [d.month] day [d.day]"
<< "wday [d.wday] yday [d.yday]"
<< "leap [(2024-02-29).leap?]"
<< "quarter [d.quarter]"
<< "eq [2024-01-15 == 2024-01-15]"
<< "diff [(2024-02-01 - 2024-01-15)]"
<< "parse [Date.parse("2020-05-06")]"
<< d
