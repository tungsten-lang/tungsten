+ SharedSetBase
  -> value()
    40

+ SharedSetDog < SharedSetBase

+ SharedSetCat < SharedSetBase

+ DistinctSetDog
  -> value()
    41

+ DistinctSetCat
  -> value()
    42

Tungsten.LOCK_THE_DOORS!

choose_dog = argv().size() > 0
if choose_dog
  shared = SharedSetDog.new()
else
  shared = SharedSetCat.new()
<< shared.value()

if choose_dog
  distinct = DistinctSetDog.new()
else
  distinct = DistinctSetCat.new()
<< distinct.value()

# The loop header converges from the entry singleton to the two-class union.
# Its exit fact therefore remains exhaustive rather than being erased merely
# because the local was reassigned in a loop.
loop_value = DistinctSetDog.new()
i = 0
while i < 2
  if i == 0
    loop_value = DistinctSetCat.new()
  else
    loop_value = DistinctSetDog.new()
  i += 1
<< loop_value.value()
