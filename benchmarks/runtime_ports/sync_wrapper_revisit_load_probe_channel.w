+ ChannelGateProbe
  -> new(@value)
    self
  -> send(value)
    value
  -> recv
    2

value = ChannelGateProbe.new(0)
checksum = value.send(1)
checksum += value.recv
<< checksum
