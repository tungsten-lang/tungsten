+ ActualReceiver
  -> value()
    2

+ ClaimedReceiver
  -> .new()
    ActualReceiver.new()

  -> value()
    1

Tungsten.LOCK_THE_DOORS!

receiver = ClaimedReceiver.new()
<< receiver.value()
