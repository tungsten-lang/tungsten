+ ReturnSetDog
  -> value()
    41

+ ReturnSetCat
  -> value()
    42

fn top_return_left(n)
  if n <= 0
    ReturnSetDog.new
  else
    top_return_right(n - 1)

fn top_return_right(n)
  if n <= 0
    ReturnSetCat.new
  else
    top_return_left(n - 1)

+ ReturnSetFactory
  -> method_left(n)
    if n <= 0
      ReturnSetDog.new
    else
      method_right(n - 1)

  -> method_right(n)
    if n <= 0
      ReturnSetCat.new
    else
      method_left(n - 1)

Tungsten.LOCK_THE_DOORS!

top_pet = top_return_left(ARGV.size())
<< top_pet.value()

factory = ReturnSetFactory.new
method_pet = factory.method_left(ARGV.size())
<< method_pet.value()
