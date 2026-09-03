# Ranges: literals, inclusive/exclusive, to_a, size, membership, step,
# implicit `item` in map/select.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "lit [1..5]"
<< "excl [1...5]"
<< "to_a [(1..5).to_a]"
<< "to_a.excl [(1...5).to_a]"
<< "size [(1..5).size]"
<< "include [(1..5).include?(3)]"
<< "include.excl [(1...5).include?(5)]"
<< "first [(1..5).first]"
<< "last [(1..5).last]"
<< "min [(3..7).min]"
<< "max [(3..7).max]"
<< "empty [(5..1).to_a]"
<< "neg [(-2..2).to_a]"
<< "step [(1..10).step(3).to_a]"
<< "step.slash [(1..10 / 3).to_a]"
<< "reverse [(1..5).to_a.reverse]"
<< "map.item [(1..3).map -> item + 1]"
<< "select [(1..10).select -> item % 3 == 0]"
<< "reduce [(1..5).reduce(1) ->(acc, x) acc * x]"
n = 4
<< "var.bound [(1..n).to_a]"
