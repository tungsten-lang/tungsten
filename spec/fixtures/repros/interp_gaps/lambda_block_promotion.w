# Source-trait Enumerable methods with a required-block param (&block) must
# accept a sole paren-lambda positionally AND the trailing-closure form in
# BOTH engines. Interpreted, these were "undefined method": lazily autoloaded
# core classes dropped their `is Enumerable` because the trait file was never
# autoloaded (expand_trait_includes now autoloads traits through the same
# registry as classes). The splice also required trait methods to act as
# DEFAULTS — Enumerable#sort (arity 0, `to_a.sort`) must not beat Array's own
# sort(&) in exact-arity lookup (Array#to_a is self: that pairing recursed).
arr = ["ccc", "a", "bb"]
v1 = arr.sort_by(-> (x) x.size).join("-")
<< "sort_by=[v1]"
v2 = arr.min_by(-> (x) x.size)
<< "min_by=[v2]"
v3 = arr.max_by(-> (x) x.size)
<< "max_by=[v3]"
r2 = arr.sort_by -> (x) x.size
v4 = r2.join("-")
<< "trailing=[v4]"
nums = [5, 1, 4]
v5 = nums.sort_by(-> (n) 0 - n).join("-")
<< "desc=[v5]"
v6 = [3, 1, 2].sort.join("-")
<< "sort=[v6]"
pairs = [[2, 9], [1, 5]]
v7 = pairs.sort.first.join("-")
<< "nested-sort=[v7]"
