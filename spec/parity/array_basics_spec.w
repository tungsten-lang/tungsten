# Arrays: literals, first/last, push/pop, indexing, slicing, aggregates,
# printing of mixed elements.
#
# Cross-engine parity spec (scripts/parity.sh).

nums = [3, 1, 2]
<< "lit [nums]"
<< "first [nums.first]"
<< "last [nums.last]"
<< "size [nums.size]"
<< "push [nums.push(4)]"
<< "pop [nums.pop]"
<< "after [nums]"
<< "idx.neg [nums[-1]]"
<< "slice [[1, 2, 3, 4, 5][1..3]]"
<< "slice.excl [[1, 2, 3, 4, 5][1...3]]"
<< "include [nums.include?(2)]"
<< "index [nums.index(2)]"
<< "sum [nums.sum]"
<< "min [nums.min]"
<< "max [nums.max]"
<< "reverse [nums.reverse]"
<< "join [nums.join(",")]"
<< "concat [[1, 2] + [3]]"
<< "flatten [[1, [2, [3]]].flatten]"
<< "uniq [[1, 1, 2, 3, 3].uniq]"
<< "compact [[1, nil, 2].compact]"
<< "empty [[].empty?]"
<< "empty.lit [[]]"
<< "mixed [[1, 3.0, true, :sym]]"
<< "tos [[1, 2].to_s]"
<< "fill [Array.new(3, 0)]"
<< "range.to_a [(1..5).to_a]"
<< "nested [[[1, 2], [3, 4]][1][0]]"
<< [1, 2, 3]
