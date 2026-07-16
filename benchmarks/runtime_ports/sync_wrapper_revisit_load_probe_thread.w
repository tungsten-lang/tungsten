+ ThreadGateProbe
  -> new(@value)
    self
  -> alive?
    false

value = ThreadGateProbe.new(0)
checksum = value.alive? ? 1 : 0
<< checksum
