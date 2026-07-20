# Repro: Array#sort! / #mergesort! were broken on BOTH engines — their
# core/array.w bodies called `array_mergesort!`, an extern that only ever
# existed as a Ruby-engine builtin ("undefined method 'array_mergesort!'"
# since inception). Comparator blocks on `sort` were SILENTLY IGNORED on
# both engines too (the WN_sort IC row and the interpreter's mirror of it
# dropped the trailing closure): [3,1,2].sort -> (x,y) y <=> x returned
# ascending [1,2,3]. Fixed by routing blocked compiled sorts to the
# stable w_array_sort_block mergesort, rewriting the in-place bodies over
# the working sort machinery, and making the interpreter's overload
# lookup block-aware so `-> sort!` / `-> sort!(&)` pairs dispatch like
# the compiled engine's block-presence specialization gate.

a = [3, 1, 2]
a.sort!
<< "sort_bang=" + a.to_s

# sort! returns self (chainable).
<< "sort_bang_chain=" + [2, 1].sort!.to_s

# Comparator block on sort — was silently ignored (returned ascending).
b = [3, 1, 2]
desc = b.sort -> (x, y)
  y <=> x
<< "sort_desc=" + desc.to_s
<< "sort_src_unchanged=" + b.to_s

# Comparator block on sort! — in place.
c = [3, 1, 2]
c.sort! -> (x, y)
  y <=> x
<< "sort_bang_desc=" + c.to_s

# mergesort! — blockless and comparator forms.
d = [5, 4, 9, 1]
d.mergesort!
<< "mergesort_bang=" + d.to_s
e = [5, 4, 9, 1]
e.mergesort! -> (x, y)
  y <=> x
<< "mergesort_bang_desc=" + e.to_s

# Comparator sorts are STABLE: equal-comparing keys keep original order.
words = ["cc", "b", "aa", "d", "ee"]
by_len = words.sort -> (x, y)
  x.size <=> y.size
<< "stable_sort=" + by_len.join(",")
words2 = ["cc", "b", "aa", "d", "ee"]
words2.mergesort! -> (x, y)
  x.size <=> y.size
<< "stable_mergesort_bang=" + words2.join(",")
