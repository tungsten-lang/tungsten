# Block passthrough (C2): a trailing block on a method that declares no block
# of its own is NOT consumed by that method — it iterates over the call's
# RESULT (implicit `.each`). Methods that DO take a block still bind it.

+ Bag < Object
  -> items
    [10, 20, 30]
  -> n
    4

b = Bag.new()

# No-block method returning an array → block iterates the elements.
s = 0
b.items -> s += item
<< (s == 60 ? "PASS items.passthrough" : "FAIL items.passthrough " + s.to_s())

# No-block method returning an int → block runs that many times.
t = 0
b.n -> t += 1
<< (t == 4 ? "PASS n.passthrough" : "FAIL n.passthrough " + t.to_s())

# A builtin no-block method (abs) returning an int → runs abs times.
u = 0
(-5).abs -> u += 1
<< (u == 5 ? "PASS abs.passthrough" : "FAIL abs.passthrough " + u.to_s())

# Real block methods still BIND their block (must NOT be rewritten to .each).
doubled = [1, 2, 3].map -> item * 2
<< (doubled.sum == 12 && doubled[0] == 2 && doubled[2] == 6 ? "PASS map.binds" : "FAIL map.binds")

evens = [1, 2, 3, 4].select -> item % 2 == 0
<< (evens.size == 2 && evens.sum == 6 ? "PASS select.binds" : "FAIL select.binds")
