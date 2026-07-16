# These retained-native spellings must not autoload any synchronization facade
# when used on an unrelated source class.
+ RetainedGateProbe
  -> new(@value)
    self
  -> cas(expected, desired)
    expected == desired
  -> get
    1
  -> set(value)
    value
  -> add(value)
    value
  -> send(value)
    value
  -> close
    nil
  -> join(value = nil)
    1
  -> kill
    nil

value = RetainedGateProbe.new(0)
checksum = value.get + value.set(1) + value.add(1) + value.send(1) + value.join(0)
checksum += value.cas(1, 1) ? 1 : 0
<< checksum
value.close
value.kill
