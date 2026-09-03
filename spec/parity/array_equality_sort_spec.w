# Arrays and hashes: structural equality; sort, sort_by, sort with a block.
#
# Cross-engine parity spec (scripts/parity.sh).

nums = [3, 1, 2]
<< "eq [[1, 2, 3] == [1, 2, 3]]"
<< "eq.ne [[1, 2, 3] == [1, 2, 4]]"
<< "eq.nested [[1, [2, 3]] == [1, [2, 3]]]"
<< "eq.len [[1, 2] == [1, 2, 3]]"
<< "eq.hash [{a: 1, b: 2} == {b: 2, a: 1}]"
<< "eq.hash.ne [{a: 1} == {a: 2}]"
<< "eq.str [["a"] == ["a"]]"
<< "dup [nums.dup == nums]"
<< "sort [nums.sort]"
<< "sort.orig [nums]"
<< "sort.desc [nums.sort.reverse]"
<< "sort.str [["pear", "apple", "fig"].sort.join(",")]"
<< "sort_by [(["bb", "a", "ccc"].sort_by ->(s) s.size).join(",")]"
<< "sort.block [[1, 3, 2].sort ->(a, b) b <=> a]"
<< "sort.dec [[2.5, 1.5, 2.0].sort]"
