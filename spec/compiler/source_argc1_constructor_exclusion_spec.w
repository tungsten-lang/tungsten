+ PositiveTarget
  -> argc1(value)
    value

+ PositiveHolder
  -> new
    @receiver = PositiveTarget.new()

  -> call(value)
    @receiver.argc1(value)

+ Atomic
  -> argc1(value)
    value

+ AtomicHolder
  -> new
    @receiver = Atomic.new(0)

  -> call(value)
    @receiver.argc1(value)

+ Channel
  -> argc1(value)
    value

+ ChannelHolder
  -> new
    @receiver = Channel.new(1)

  -> call(value)
    @receiver.argc1(value)

+ Thread
  -> argc1(value)
    value

+ ThreadHolder
  -> new
    @receiver = Thread.new ->
      1

  -> call(value)
    @receiver.argc1(value)

+ Response
  -> argc1(value)
    value

+ ResponseHolder
  -> new
    @receiver = Response.new(200, "ok")

  -> call(value)
    @receiver.argc1(value)

+ BigArray
  -> argc1(value)
    value

+ BigArrayHolder
  -> new
    @receiver = BigArray.new(:w64, 4)

  -> call(value)
    @receiver.argc1(value)

+ SmallArray
  -> argc1(value)
    value

+ SmallArrayHolder
  -> new
    @receiver = SmallArray.new(:w64, 4)

  -> call(value)
    @receiver.argc1(value)

+ ByteArray
  -> argc1(value)
    value

+ ByteArrayHolder
  -> new
    @receiver = ByteArray.new(4)

  -> call(value)
    @receiver.argc1(value)

+ BoolArray
  -> argc1(value)
    value

+ BoolArrayHolder
  -> new
    @receiver = BoolArray.new(4)

  -> call(value)
    @receiver.argc1(value)
