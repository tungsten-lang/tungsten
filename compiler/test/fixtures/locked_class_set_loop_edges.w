+ LoopEdgeDog
  -> value()
    41

+ LoopEdgeCat
  -> value()
    42

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

# Both calls see the bounded {LoopEdgeDog, LoopEdgeCat} set. The first sits
# inside a loop with a next edge; the second joins the condition-false and
# break exits.
value = LoopEdgeDog.new()
total = 0
i = 0
while i < 4
  if i == 0
    value = LoopEdgeCat.new()
    total += value.value()
    i += 1
    next
  if i == 2
    break
  value = LoopEdgeDog.new()
  total += value.value()
  i += 1

<< total
<< value.value()
