+ AtomicGateProbe
  -> new(@value)
    self
  -> cas(expected, desired)
    expected == desired
  -> increment
    1
  -> decrement
    1

value = AtomicGateProbe.new(0)
checksum = value.cas(1, 1) ? 1 : 0
checksum += value.increment
checksum += value.decrement
<< checksum
