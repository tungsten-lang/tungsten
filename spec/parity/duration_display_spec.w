# Durations: compound literals, unit words, arithmetic, comparison, type.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "dur.m [5m30s]"
<< "dur.h [2h30m]"
<< "dur.ymd [1y2mo3d]"
<< "dur.ms [500ms]"
<< "dur.days [210 days]"
<< "dur.day [1 day]"
<< "dur.week [2 weeks]"
<< "dur.type [type(2h30m)]"
<< "days.type [type(210 days)]"
<< "dur.add [2h + 30s]"
<< "dur.mul [2 * 30s]"
<< "dur.tos [(2h30m).to_s]"
<< "dur.cmp [1h > 59s]"
<< 5m30s
