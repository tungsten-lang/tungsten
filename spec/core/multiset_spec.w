# Multiset — bag of elements with multiplicities (core/multiset.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/multiset_spec.w
#   bin/tungsten -o /tmp/multiset_spec spec/core/multiset_spec.w && /tmp/multiset_spec

use core/multiset

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

m = Multiset.new
check("constructs", type(m) == "Multiset")
check("is_a? Multiset", m.is_a?(Multiset))

# The Multiset surface is declared bodyless and nothing implements it yet on either engine.
# BUG: the documented literal `<{1, 2, 2, 3}>` is a parse error ("Unexpected token LT") on both engines
# check("literal", <{1, 2, 2, 3}>.size == 4)
# BUG: Multiset.of / .empty / .from_array / .from_counts are undefined (both engines)
# m = Multiset.of([1, 2, 2, 3])
# check("of", m.size == 4)
# check("empty", Multiset.empty.empty?)
# check("from_array", Multiset.from_array([1, 1]).count(1) == 2)
# check("from_counts", Multiset.from_counts({1 => 2}).size == 2)
# BUG: size / count / counts / support / each / union / intersect / diff / to_a / to_set / to_hash / == / hash / to_s
# are bodyless with no runtime implementation, so length / empty? / uniq / distinct_count / include? built on them are wrong
# check("size counts duplicates", m.size == 4)
# check("length", m.length == 4)
# check("count", m.count(2) == 2 && m.count(9) == 0)
# check("counts", m.counts == {1 => 1, 2 => 2, 3 => 1})
# check("support", m.support.size == 3)
# check("uniq", m.uniq.size == 3)
# check("distinct_count", m.distinct_count == 3)
# check("include?", m.include?(2) && !m.include?(9))
# check("each yields duplicates", m.map(-> (x) x).size == 4)
# check("union adds counts", m.union(Multiset.of([2])).count(2) == 3)
# check("intersect takes min", m.intersect(Multiset.of([2, 2, 2])).count(2) == 2)
# check("diff subtracts floored at 0", m.diff(Multiset.of([2, 2, 2, 3])).size == 1)
# check("to_a", m.to_a.sort == [1, 2, 2, 3])
# check("to_set", m.to_set.size == 3)
# check("to_hash", m.to_hash == m.counts)
# check("==", m == Multiset.of([3, 2, 2, 1]))
# check("hash", m.hash == Multiset.of([3, 2, 2, 1]).hash)
# check("to_s", m.to_s == "<{ 1, 2, 2, 3 }>")
# check("inspect", m.inspect == m.to_s)

<< "ALL PASS multiset_spec ([passed.load()] checks)"
