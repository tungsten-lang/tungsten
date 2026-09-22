# Dates order by the packed civil tuple. The raw word is year-major, so
# this is the BitOrdered comparison. Equality was already payload bits.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "lt [2024-01-15 < 2024-02-01]"
<< "gt [2024-03-01 > 2024-02-01]"
<< "eq [2024-01-15 == 2024-01-15]"
<< "le [2024-01-15 <= 2024-01-15]"
<< "ge [2024-02-01 >= 2024-03-01]"
<< "sub [2024-02-01 - 2024-01-15]"
<< "clock [2024-01-15T09:00:00Z < 2024-01-15T10:00:00Z]"
