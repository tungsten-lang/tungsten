# DateTimes: Z and offset literals, tz accessor, time arithmetic across a
# minute/day boundary, printed suffix.
#
# Cross-engine parity spec (scripts/parity.sh).

ld = 2024-02-29T23:59:58-05:00
<< "tz.lit [ld]"
<< "tz [ld.tz]"
<< "tz.hms [ld.hour] [ld.minute] [ld.second]"
<< "tz.add [ld + 2s]"
<< "dt.z [2024-01-15T12:30:00Z]"
<< "dt.add.h [2024-01-15T12:00:00Z + 2h]"
<< "dt.add.s [2024-01-15T23:59:00Z + 90s]"
<< "dt.type [type(2024-01-15T12:30:00Z)]"
<< ld
