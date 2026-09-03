# Arrays: enumerable methods with implicit `item` and explicit params.
#
# Cross-engine parity spec (scripts/parity.sh).

nums = [3, 1, 2]
<< "map [nums.map -> item * 2]"
<< "select [nums.select -> item % 2 == 1]"
<< "reject [nums.reject -> item % 2 == 1]"
<< "reduce [nums.reduce(0) ->(acc, x) acc + x]"
<< "any [nums.any? -> item > 2]"
<< "all [nums.all? -> item > 0]"
<< "count [nums.count -> item > 1]"
<< "find [nums.find -> item > 1]"
<< "zip [[1, 2].zip([3, 4])]"
<< "take [[1, 2, 3].take(2)]"
<< "drop [[1, 2, 3].drop(1)]"
<< "nested.map [[[1, 2], [3]].map -> item.size]"
<< "map.explicit [[7, 8].map ->(x) x + 1]"
<< "map.str [(["a", "b"].map -> item.upcase).join(",")]"
<< "chain [(nums.map -> item * 10).select -> item > 10]"
