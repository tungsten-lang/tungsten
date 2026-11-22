# spec: compiled -- guards the ownership pass's free insertion
# Replacing a container held in a global slot must not free the old one:
# anything that read the slot (here `rows`, and `held` inside a function)
# still holds it, and a global is reachable from every function, so the
# ownership pass cannot prove the old container dead. Callers that know it
# is dead release it themselves (ccall("w_value_free_w", old)).

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

P = [[], {}]
HELD = []

-> refill(i)
  held = P[0]
  HELD.push(held) if i % 100 == 0
  P[0] = [i, i + 1]
  P[1] = {k: i}
  held

i = 0
last = nil
while i < 1000
  rows = P[0]
  last = rows
  P[0] = [i]
  P[1] = {}
  i += 1
check("the replaced container read before the store stays valid", last.size == 1 && last[0] == 998)

i = 0
prev = nil
while i < 1000
  prev = refill(i)
  i += 1
check("a container returned after its slot was replaced stays valid", prev[0] == 998 && prev[1] == 999)
check("containers kept elsewhere stay valid", HELD.size == 10 && HELD[9][0] == 899)
