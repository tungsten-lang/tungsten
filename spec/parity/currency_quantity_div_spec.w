# Currency divided by a scalar stays currency. A quantity divided by a
# scalar stays a quantity. Same-symbol currency divided by currency is
# a unitless decimal.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "cur.scalar [$10.00 / 3]"
<< "cur.ratio [$10.00 / $2.00]"
<< "qty.scalar [10 m / 2]"
<< "qty.frac [9 m / 2]"
