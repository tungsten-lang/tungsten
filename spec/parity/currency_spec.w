# Currency literals: arithmetic, cents, percent discounts, printing.
#
# Cross-engine parity spec (scripts/parity.sh).

price = $499.99
<< "lit [price]"
<< "pct.sub [price - 15%]"
<< "pct.chain [price - 15% + 8.25%]"
<< "cents [$3.50 - 25¢]"
<< "cur.add [$1.25 + $2.50]"
<< "cur.mul [$5.50 * 4]"
<< "cur.mulf [$27.60 * 0.0765]"
<< "cur.type [type($1.00)]"
<< "cur.eq [$5.00 == $5.00]"
<< "cur.zero [$0.00]"
<< "cur.neg [$5.00 - $7.25]"
<< "cur.big [$1234567.89]"
