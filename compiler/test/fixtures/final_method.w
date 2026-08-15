+ FinalCounter
  @final -> step(x)
    x + 1

  -> run(x)
    step(x)

  -> relay(other) (FinalCounter)
    other.step(1)

counter = FinalCounter.new
<< counter.run(41)
<< counter.step(1)
<< counter.relay(counter)
