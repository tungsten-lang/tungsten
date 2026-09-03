# Percent literals: arithmetic between percents and with numbers.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "pct.diff [20% - 15%]"
<< "pct.add [20% + 15%]"
<< "pct.type [type(15%)]"
<< "pct.of [200 * 15%]"
<< "pct.of2 [15% * 200]"
<< "pct.val [(15%).value]"
<< "pct.frac [12.5%]"
<< "pct.big [150%]"
<< "pct.price [$100.00 - 25%]"
