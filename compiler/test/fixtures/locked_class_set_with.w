+ WithSetFirst
  -> value()
    1

+ WithSetSecond
  -> value()
    2

Tungsten.LOCK_THE_DOORS!

receiver = WithSetFirst.new()
with i in 1..2
  << receiver.value()
  receiver = WithSetSecond.new()
