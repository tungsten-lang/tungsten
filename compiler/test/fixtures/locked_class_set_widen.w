+ WidenSetBase
  -> value()
    0

+ WidenSetA < WidenSetBase
  -> value()
    1

+ WidenSetB < WidenSetBase
  -> value()
    2

+ WidenSetC < WidenSetBase
  -> value()
    3

+ WidenSetD < WidenSetBase
  -> value()
    4

+ WidenSetE < WidenSetBase
  -> value()
    5

Tungsten.LOCK_THE_DOORS!

choice = argv().size()
if choice == 0
  receiver = WidenSetA.new()
elsif choice == 1
  receiver = WidenSetB.new()
elsif choice == 2
  receiver = WidenSetC.new()
elsif choice == 3
  receiver = WidenSetD.new()
else
  receiver = WidenSetE.new()
<< receiver.value()
