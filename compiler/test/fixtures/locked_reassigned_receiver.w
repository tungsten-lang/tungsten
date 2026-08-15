+ FirstReceiver
  -> value()
    1

+ SecondReceiver
  -> value()
    2

Tungsten.LOCK_THE_DOORS!

receiver = FirstReceiver.new()
receiver = SecondReceiver.new()
<< receiver.value()
