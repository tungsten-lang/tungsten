# Set — unique, unordered elements with O(1) membership (core/set.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/set_spec.w
#   bin/tungsten -o /tmp/set_spec spec/core/set_spec.w && /tmp/set_spec

use core/set

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

s = Set.new
check("constructs", type(s) == "Set")
check("is_a? Set", s.is_a?(Set))

# The Set surface is declared bodyless and nothing implements it yet on either engine.
# BUG: the documented literal `{1, 2, 3}` is a parse error ("Expected ..., got COMMA") on both engines
# check("literal", {1, 2, 3}.size == 3)
# BUG: Set.of / Set.empty / Set.from_array / Set.parse are undefined (both engines)
# s = Set.of([3, 1, 2, 2])
# check("of dedups", s.size == 3)
# check("empty", Set.empty.empty?)
# check("from_array", Set.from_array([1, 2]).size == 2)
# check("parse", Set.parse("{1, 2}").size == 2)
# BUG: Set#size / #to_s / #include? / #add / #remove / #union ... return nil (bodyless), so even the
# bodied helpers built on them (length, empty?, member?, disjoint?, ==, <=>) are wrong
# check("size", s.size == 3)
# check("length", s.length == 3)
# check("empty?", !s.empty?)
# check("include?", s.include?(2) && !s.include?(9))
# check("member?", s.member?(3))
# check("union", s.union(Set.of([3, 4])).size == 4)
# check("intersect", s.intersect(Set.of([2, 3, 4])).size == 2)
# check("diff", s.diff(Set.of([2])).size == 2)
# check("symmetric_diff", s.symmetric_diff(Set.of([3, 4])).size == 3)
# check("subset?", Set.of([1]).subset?(s) && s.subset?(s))
# check("proper_subset?", Set.of([1]).proper_subset?(s) && !s.proper_subset?(s))
# check("superset?", s.superset?(Set.of([1])))
# check("proper_superset?", s.proper_superset?(Set.of([1])) && !s.proper_superset?(s))
# check("disjoint?", s.disjoint?(Set.of([7])) && !s.disjoint?(Set.of([3])))
# check("add returns new set", s.add(4).size == 4 && s.size == 3)
# check("remove returns new set", s.remove(1).size == 2 && s.size == 3)
# check("to_a", s.to_a.sort == [1, 2, 3])
# check("to_multiset", type(s.to_multiset) == "Multiset")
# check("== is structural", s == Set.of([1, 2, 3]))
# check("<=> subset order", (Set.of([1]) <=> s) == -1 && (s <=> Set.of([1])) == 1 && (s <=> s) == 0)
# check("<=> incomparable", (Set.of([9]) <=> s) == nil)
# check("hash agrees with ==", s.hash == Set.of([3, 2, 1]).hash)
# check("to_s", Set.of([1]).to_s == "{1}")
# check("inspect", Set.of([1]).inspect == "{1}")

<< "ALL PASS set_spec ([passed.load()] checks)"
