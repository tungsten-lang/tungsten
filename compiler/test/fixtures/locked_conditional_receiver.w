+ ConditionalReceiver
  -> value()
    42

Tungsten.LOCK_THE_DOORS!

condition = argv().size() > 0
if condition
  receiver = ConditionalReceiver.new()
<< receiver.value()
