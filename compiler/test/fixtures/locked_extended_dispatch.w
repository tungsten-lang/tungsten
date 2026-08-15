+ SharedDispatchBase
  -> step(value)
    value + 1

  -> through_self(value)
    self.step(value)

+ SharedDispatchChild < SharedDispatchBase

+ OverrideDispatchBase
  -> step(value)
    value + 1

  -> through_self(value)
    self.step(value)

+ OverrideDispatchChild < OverrideDispatchBase
  -> step(value)
    value + 2

+ FreshDispatchReceiver
  -> value()
    42

Tungsten.LOCK_THE_DOORS!

original = FreshDispatchReceiver.new()
copied = original
<< copied.value()
<< FreshDispatchReceiver.new().value()
<< SharedDispatchChild.new().through_self(40)
<< OverrideDispatchChild.new().through_self(40)
