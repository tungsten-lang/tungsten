# False-positive autoload probe. Every selector is invoked on an ordinary
# source object, never on a synchronization handle. Candidate-only growth is
# therefore exactly the cost of the bounded synchronization selector gates.

+ SyncGateProbe
  -> new(@value)
    self

  -> cas(expected, desired)
    if @value == expected
      @value = desired
      return true
    false

  -> get
    @value

  -> set(value)
    @value = value

  -> increment
    @value += 1

  -> decrement
    @value -= 1

  -> add(delta)
    old = @value
    @value += delta
    old

  -> send(value)
    @value = value
    nil

  -> recv
    @value

  -> close
    nil

  -> join(timeout = nil)
    @value

  -> alive?
    false

  -> kill
    nil

value = SyncGateProbe.new(1)
checksum = 0
checksum += value.cas(1, 2) ? 1 : 0
checksum += value.get
checksum += value.set(3)
checksum += value.increment
checksum += value.decrement
checksum += value.add(2)
value.send(7)
checksum += value.recv
value.close
checksum += value.join(0)
checksum += value.alive? ? 1 : 0
value.kill
<< checksum
